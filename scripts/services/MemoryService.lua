-- ============================================================================
-- MemoryService.lua — 关系记忆与聊天存档的接口层（内存 → 本地文件 → 云，逐级降级）
-- 约定：
--   * Load/Save 是同步的本地能力，本地失败就退回内存并打日志，绝不让 UI 崩。
--   * M1 起存档带完整消息记录：每条含权威 UTC 发送时间、当前状态、计划回复时刻、
--     事件事实 id 与送达时的作息事实，重进时由 main.lua 交给 MessageService.Restore。
--   * v1 存档（只有 transcript 摘要）仍可读，读回时迁移为消息记录。
--   * clientCloud 只暴露异步接口，且按轮次节流（不逐条消息写云）。
--   * 预览是否成功不依赖云存储：云回调只打日志，不驱动任何 UI 状态。
-- ============================================================================

local MemoryService = {}

local SAVE_DIR = "memory"
local DEFAULT_SAVE_FILE = "memory/m0-1-la-stranger.json"
local CLOUD_KEY = "companion_memory_la"
local CLOUD_FLUSH_EVERY_TURNS = 5
-- 落盘的消息条数上限：只裁「已回复」的旧记录，任何未回复的排队消息都不会被裁掉
local MESSAGE_CAP = 120
local SAVE_VERSION = 2

---@class CompanionMemory
---@field version integer
---@field cityId string
---@field turns integer
---@field firstServerTime integer
---@field lastServerTime integer
---@field lastFactId string
---@field topics string[]
---@field messages MsgEntry[]

---@type CompanionMemory
local mem_ = {
    version = SAVE_VERSION,
    cityId = "los_angeles",
    turns = 0,
    firstServerTime = 0,
    lastServerTime = 0,
    lastFactId = "",
    topics = {},
    messages = {},
}

local source_ = "memory"
local cloudDirty_ = false
local turnsSinceFlush_ = 0
---@type string
local saveFile_ = DEFAULT_SAVE_FILE
---@type integer
local messageCap_ = MESSAGE_CAP

---@class CloudAdapter
---@field LoadAsync? fun(onDone: fun(ok: boolean, data: table|nil))
---@field SaveAsync? fun(data: table, onDone: fun(ok: boolean, err: string|nil))

---@type CloudAdapter?
local cloud_ = nil

local function logInfo(msg)
    print("[Memory] " .. msg)
    log:Write(LOG_INFO, "[Memory] " .. msg)
end

local function logWarn(msg)
    print("[Memory] WARN: " .. msg)
    log:Write(LOG_WARNING, "[Memory] " .. msg)
end

local function logError(msg)
    print("[Memory] ERROR: " .. msg)
    log:Write(LOG_ERROR, "[Memory] " .. msg)
end

--- 只保留可序列化的字段，读回来的脏数据不至于把状态机带崩
---@param raw any
---@return boolean
local function looksLikeMemory(raw)
    return type(raw) == "table" and type(raw.turns) == "number" and type(raw.cityId) == "string"
end

---@param value any
---@return integer?
local function asInteger(value)
    if type(value) == "number" then
        return math.floor(value)
    end
    return nil
end

---@param value any
---@return string?
local function asString(value)
    if type(value) == "string" then
        return value
    end
    return nil
end

---@param value any
---@return boolean?
local function asBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    return nil
end

--- 把一条消息裁成可落盘的样子；缺关键字段的脏记录直接丢掉
---@param raw any
---@return MsgEntry? entry
---@return string? reason
local function sanitizeMessage(raw)
    if type(raw) ~= "table" then
        return nil, "不是表"
    end
    local role = asString(raw.role)
    local text = asString(raw.text)
    local serverTime = asInteger(raw.serverTime)
    if not role or text == nil or not serverTime then
        return nil, "缺 role/text/serverTime"
    end
    ---@type MsgEntry
    local entry = {
        id = asInteger(raw.id) or 0,
        role = role,
        text = text,
        serverTime = serverTime,
        state = asString(raw.state) or "replied",
        statusText = asString(raw.statusText) or "",
        clockText = asString(raw.clockText) or "",
        factId = asString(raw.factId),
        planReplyAtUtc = asInteger(raw.planReplyAtUtc),
        planWindowStartUtc = asInteger(raw.planWindowStartUtc),
        replyableAtSend = asBoolean(raw.replyableAtSend),
        brief = asBoolean(raw.brief),
        availabilityAtSend = asString(raw.availabilityAtSend),
        availabilityLabelAtSend = asString(raw.availabilityLabelAtSend),
        placeAtSend = asString(raw.placeAtSend),
        sceneIdAtSend = asString(raw.sceneIdAtSend),
        phraseAtSend = asString(raw.phraseAtSend),
    }
    return entry, nil
end

--- 从落盘结构读回消息数组。脏 id 会重排，保证 UI 的 rowsById 不会撞车。
--- v1 存档只有 {role,text,serverTime} 的摘要，走同一个解析路径即可：
--- 缺 state 的记录按「已回复」处理，读回来仍能渲染完整历史，只是没有排队队列（v1 本来就没有）。
---@param rawMessages any
---@return MsgEntry[]
local function readMessages(rawMessages)
    ---@type MsgEntry[]
    local out = {}
    if type(rawMessages) ~= "table" then
        return out
    end
    local maxId = 0
    for i = 1, #rawMessages do
        local entry, reason = sanitizeMessage(rawMessages[i])
        if entry then
            out[#out + 1] = entry
            if entry.id > maxId then
                maxId = entry.id
            end
        else
            logWarn(string.format("第 %d 条消息无法解析（%s），已跳过", i, tostring(reason)))
        end
    end
    -- id 必须唯一：MessageService 的 nextId 与 ChatPanel 的行索引都靠它
    local seen = {}
    for i = 1, #out do
        local entry = out[i]
        if entry.id <= 0 or seen[entry.id] then
            maxId = maxId + 1
            entry.id = maxId
        end
        seen[entry.id] = true
    end
    return out
end

---@class MemoryInitOptions
---@field cityId? string
---@field cloud? CloudAdapter
---@field saveFile? string 存档路径（开发自检用独立文件，不碰玩家的历史）
---@field maxMessages? integer 落盘消息条数上限

---@param opts? MemoryInitOptions
function MemoryService.Init(opts)
    opts = opts or {}
    -- 先回到干净的内存态：重进/重开自检时不能把上一次的 mem_ 混进新存档
    MemoryService.ResetInMemory()
    mem_.cityId = opts.cityId or mem_.cityId
    cloud_ = opts.cloud
    saveFile_ = opts.saveFile or DEFAULT_SAVE_FILE
    messageCap_ = opts.maxMessages or MESSAGE_CAP
    logInfo("初始化，本地存档路径 " .. saveFile_ .. " 云适配器=" .. (cloud_ and "有" or "无"))
end

---@return string
function MemoryService.GetSaveFile()
    return saveFile_
end

--- 读本地存档；失败退回内存并记录来源
---@return CompanionMemory, string source
function MemoryService.Load()
    local ok, err = pcall(function()
        if not fileSystem:FileExists(saveFile_) then
            logInfo("没有本地存档，使用初始内存状态")
            source_ = "memory"
            return
        end
        local file = File(saveFile_, FILE_READ)
        if not file:IsOpen() then
            error("文件打开失败")
        end
        local raw = file:ReadString()
        file:Close()
        local decoded = nil
        local decodeOk = pcall(function()
            decoded = cjson.decode(raw)
        end)
        file:Dispose()
        if not decodeOk or not looksLikeMemory(decoded) then
            error("JSON 解析失败或结构不符")
        end
        local data = decoded ---@type any
        mem_.turns = math.floor(data.turns or 0)
        mem_.cityId = data.cityId or mem_.cityId
        mem_.version = asInteger(data.version) or 1
        mem_.firstServerTime = math.floor(data.firstServerTime or 0)
        mem_.lastServerTime = math.floor(data.lastServerTime or 0)
        mem_.lastFactId = data.lastFactId or ""
        mem_.topics = (type(data.topics) == "table") and data.topics or {}
        local migrated = mem_.version < SAVE_VERSION
        mem_.messages = readMessages(migrated and data.transcript or data.messages)
        if migrated then
            mem_.version = SAVE_VERSION
            logInfo("读到 v1 存档，已把 " .. tostring(#mem_.messages) .. " 条摘要迁移为消息记录")
        end
        source_ = "file"
        local pending = 0
        for i = 1, #mem_.messages do
            local m = mem_.messages[i]
            if m.role == "user" and m.state ~= "replied" then
                pending = pending + 1
            end
        end
        logInfo(string.format("本地存档已读回 turns=%d 记录=%d 条 待回复=%d 条",
            mem_.turns, #mem_.messages, pending))
    end)

    if not ok then
        logError("读本地存档失败，退回内存：" .. tostring(err))
        MemoryService.ResetInMemory()
    end
    return mem_, source_
end

--- 读回的消息数组（交给 MessageService.Restore）
---@return MsgEntry[]
function MemoryService.GetRestoredMessages()
    return mem_.messages
end

--- 写本地存档；任何失败都只降级到内存，不抛出
---@return boolean ok, string source
function MemoryService.Save()
    local ok, err = pcall(function()
        if not fileSystem:DirExists(SAVE_DIR) then
            fileSystem:CreateDir(SAVE_DIR)
        end
        local encoded = cjson.encode({
            version = mem_.version,
            cityId = mem_.cityId,
            turns = mem_.turns,
            firstServerTime = mem_.firstServerTime,
            lastServerTime = mem_.lastServerTime,
            lastFactId = mem_.lastFactId,
            topics = mem_.topics,
            messages = mem_.messages,
        })
        local file = File(saveFile_, FILE_WRITE)
        if not file:IsOpen() then
            error("文件不可写")
        end
        file:WriteString(encoded)
        file:Close()
        file:Dispose()
        logInfo(string.format("本地存档已写入 %d 字节", #encoded))
    end)

    if not ok then
        logWarn("写本地存档失败，本轮起只留在内存：" .. tostring(err))
        source_ = "memory"
        return false, "memory"
    end
    source_ = "file"
    return true, source_
end

--- 落盘用的字段白名单：effReplyAtUtc 这类「本轮重排」的运行时字段不进存档，
--- 否则下一次读回来会带着过期的交付时刻。
---@param entry MsgEntry
---@return MsgEntry
local function toSaved(entry)
    return {
        id = entry.id,
        role = entry.role,
        text = entry.text,
        serverTime = entry.serverTime,
        state = entry.state,
        statusText = entry.statusText or "",
        clockText = entry.clockText or "",
        factId = entry.factId,
        planReplyAtUtc = entry.planReplyAtUtc,
        planWindowStartUtc = entry.planWindowStartUtc,
        replyableAtSend = entry.replyableAtSend,
        brief = entry.brief,
        availabilityAtSend = entry.availabilityAtSend,
        availabilityLabelAtSend = entry.availabilityLabelAtSend,
        placeAtSend = entry.placeAtSend,
        sceneIdAtSend = entry.sceneIdAtSend,
        phraseAtSend = entry.phraseAtSend,
    }
end

--- 把 MessageService 的消息数组收进存档。只裁已回复的旧记录，排队中的一条都不丢。
---@param entries MsgEntry[]
---@return boolean saved
function MemoryService.Persist(entries)
    ---@type MsgEntry[]
    local kept = {}
    for i = 1, #entries do
        kept[#kept + 1] = toSaved(entries[i])
    end
    while #kept > messageCap_ do
        local dropIndex = nil
        for i = 1, #kept do
            local m = kept[i]
            if m.role ~= "user" or m.state == "replied" then
                dropIndex = i
                break
            end
        end
        if not dropIndex then
            break -- 全是未回复的排队消息：宁可超限也不丢
        end
        table.remove(kept, dropIndex)
    end
    mem_.messages = kept
    if #kept > 0 then
        mem_.lastServerTime = kept[#kept].serverTime
        if mem_.firstServerTime == 0 then
            mem_.firstServerTime = kept[1].serverTime
        end
    end
    cloudDirty_ = true
    local saved = MemoryService.Save()
    return saved
end

---@param topics string[]
local function mergeTopics(topics)
    for i = 1, #topics do
        local seen = false
        for j = 1, #mem_.topics do
            if mem_.topics[j] == topics[i] then
                seen = true
                break
            end
        end
        if not seen then
            mem_.topics[#mem_.topics + 1] = topics[i]
        end
    end
end

--- 一轮完整问答落库：轮次/话题/最近事实是关系摘要，消息记录由 messages 一次性带走。
--- 记录（含排队中的消息与计划回复时刻）与摘要同一次写盘，不产生第二条路径。
---@param userMsg MsgEntry
---@param replyMsg MsgEntry|nil
---@param fact EventFact
---@param topics string[]
---@param messages MsgEntry[] 当前完整消息数组（MessageService.GetMessages()）
---@return CompanionMemory
function MemoryService.RecordTurn(userMsg, replyMsg, fact, topics, messages)
    mem_.turns = mem_.turns + 1
    if mem_.firstServerTime == 0 then
        mem_.firstServerTime = userMsg.serverTime
    end
    mem_.lastServerTime = userMsg.serverTime
    mem_.lastFactId = fact.id
    if replyMsg then
        mem_.lastServerTime = replyMsg.serverTime
    end

    mergeTopics(topics or {})
    turnsSinceFlush_ = turnsSinceFlush_ + 1

    local saved = MemoryService.Persist(messages or {})
    if turnsSinceFlush_ >= CLOUD_FLUSH_EVERY_TURNS then
        MemoryService.FlushCloud()
    end
    logInfo(string.format("记录第 %d 轮 topics=%s 落盘=%s",
        mem_.turns, table.concat(topics or {}, ","), tostring(saved)))
    return mem_
end

---@return CompanionMemory
function MemoryService.Get()
    return mem_
end

---@return string
function MemoryService.GetSummaryLine()
    return string.format("已聊 %d 轮 · 记忆来源 %s · 最近事实 %s",
        mem_.turns, source_, mem_.lastFactId ~= "" and mem_.lastFactId or "无")
end

function MemoryService.ResetInMemory()
    mem_.version = SAVE_VERSION
    mem_.turns = 0
    mem_.firstServerTime = 0
    mem_.lastServerTime = 0
    mem_.lastFactId = ""
    mem_.topics = {}
    mem_.messages = {}
    source_ = "memory"
end

--- 清掉本地存档并回到初始内存状态。开发自检要用它保证每一轮从干净的历史开始，
--- 否则上一次自检留下的排队消息会污染这一轮的断言。删除失败也照样重置内存，
--- 并把失败记在日志里（自检的 E0 会显式打出落盘结果）。
---@return boolean cleared
function MemoryService.ClearSavedData()
    local ok, err = pcall(function()
        if fileSystem:FileExists(saveFile_) then
            fileSystem:Delete(saveFile_)
        end
    end)
    MemoryService.ResetInMemory()
    if not ok then
        logWarn("删除本地存档失败，本轮自检结果可能受历史影响：" .. tostring(err))
        return false
    end
    return true
end

--- 异步云接口。没有适配器就什么都不做，返回值不代表成功与否。
---@param onDone? fun(ok: boolean, data: table|nil)
function MemoryService.CloudLoadAsync(onDone)
    local done = onDone or function() end
    if not cloud_ or not cloud_.LoadAsync then
        logInfo("未配置云适配器，跳过异步读取")
        done(false, nil)
        return
    end
    local loader = cloud_.LoadAsync
    local ok, err = pcall(function()
        loader(function(success, data)
            if success and looksLikeMemory(data) then
                logInfo("云记忆读回成功（仅记录，不覆盖本轮内存）")
            else
                logWarn("云记忆读取未成功，继续用本地/内存")
            end
            done(success, data)
        end)
    end)
    if not ok then
        logError("调用云读取接口异常：" .. tostring(err))
        done(false, nil)
    end
end

--- 节流后的云写。逐条消息不会走到这里。
---@param onDone? fun(ok: boolean, err: string|nil)
function MemoryService.FlushCloud(onDone)
    local done = onDone or function() end
    turnsSinceFlush_ = 0
    if not cloudDirty_ then
        done(true, nil)
        return
    end
    if not cloud_ or not cloud_.SaveAsync then
        logInfo("未配置云适配器，记忆留在本地")
        done(false, "no-adapter")
        return
    end
    local payload = mem_
    local saver = cloud_.SaveAsync
    cloudDirty_ = false
    local ok, err = pcall(function()
        saver(payload, function(success, failReason)
            if success then
                logInfo("云记忆已异步写入")
            else
                logWarn("云记忆异步写入未成功，本地副本仍然有效: " .. tostring(failReason))
            end
            done(success, failReason)
        end)
    end)
    if not ok then
        cloudDirty_ = true
        logError("调用云写入接口异常：" .. tostring(err))
        done(false, tostring(err))
    end
end

--- 默认适配器：只有 clientCloud 真的存在时才用，纯异步回调
---@return CloudAdapter?
function MemoryService.DefaultClientCloudAdapter()
    if type(clientCloud) ~= "table" then
        return nil
    end
    ---@type CloudAdapter
    return {
        LoadAsync = function(onDone)
            clientCloud:Get(CLOUD_KEY, {
                ok = function(values, iscores)
                    local raw = values and values[CLOUD_KEY] or nil
                    onDone(raw ~= nil, raw)
                end,
                error = function(code, reason)
                    logWarn("clientCloud:Get 失败 " .. tostring(code) .. " " .. tostring(reason))
                    onDone(false, nil)
                end,
                timeout = function()
                    logWarn("clientCloud:Get 超时")
                    onDone(false, nil)
                end,
            })
        end,
        SaveAsync = function(data, onDone)
            clientCloud:Set(CLOUD_KEY, data, {
                ok = function()
                    onDone(true, nil)
                end,
                error = function(code, reason)
                    onDone(false, tostring(code) .. ":" .. tostring(reason))
                end,
                timeout = function()
                    onDone(false, "timeout")
                end,
            })
        end,
    }
end

return MemoryService
