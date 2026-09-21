-- ============================================================================
-- MemoryService.lua — 关系记忆的接口层（内存 → 本地文件 → 云，逐级降级）
-- 约定：
--   * Load/Save 是同步的本地能力，本地失败就退回内存并打日志，绝不让 UI 崩。
--   * clientCloud 只暴露异步接口，且按轮次节流（不逐条消息写云）。
--   * 预览是否成功不依赖云存储：云回调只打日志，不驱动任何 UI 状态。
-- ============================================================================

local MemoryService = {}

local SAVE_DIR = "memory"
local SAVE_FILE = "memory/m0-1-la-stranger.json"
local CLOUD_KEY = "companion_memory_la"
local CLOUD_FLUSH_EVERY_TURNS = 5
local TRANSCRIPT_CAP = 40

---@class MemoryTurn
---@field role string
---@field text string
---@field serverTime integer

---@class CompanionMemory
---@field version integer
---@field cityId string
---@field turns integer
---@field firstServerTime integer
---@field lastServerTime integer
---@field lastFactId string
---@field topics string[]
---@field transcript MemoryTurn[]

---@type CompanionMemory
local mem_ = {
    version = 1,
    cityId = "los_angeles",
    turns = 0,
    firstServerTime = 0,
    lastServerTime = 0,
    lastFactId = "",
    topics = {},
    transcript = {},
}

local source_ = "memory"
local cloudDirty_ = false
local turnsSinceFlush_ = 0

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

---@param opts? {cityId?: string, cloud?: CloudAdapter}
function MemoryService.Init(opts)
    opts = opts or {}
    mem_.cityId = opts.cityId or mem_.cityId
    cloud_ = opts.cloud
    logInfo("初始化，本地存档路径 " .. SAVE_FILE .. " 云适配器=" .. (cloud_ and "有" or "无"))
end

--- 读本地存档；失败退回内存并记录来源
---@return CompanionMemory, string source
function MemoryService.Load()
    local ok, err = pcall(function()
        if not fileSystem:FileExists(SAVE_FILE) then
            logInfo("没有本地存档，使用初始内存状态")
            source_ = "memory"
            return
        end
        local file = File(SAVE_FILE, FILE_READ)
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
        mem_.firstServerTime = math.floor(data.firstServerTime or 0)
        mem_.lastServerTime = math.floor(data.lastServerTime or 0)
        mem_.lastFactId = data.lastFactId or ""
        mem_.topics = (type(data.topics) == "table") and data.topics or {}
        mem_.transcript = (type(data.transcript) == "table") and data.transcript or {}
        source_ = "file"
        logInfo(string.format("本地存档已读回 turns=%d 记录=%d 条", mem_.turns, #mem_.transcript))
    end)

    if not ok then
        logError("读本地存档失败，退回内存：" .. tostring(err))
        MemoryService.ResetInMemory()
    end
    return mem_, source_
end

--- 写本地存档；任何失败都只降级到内存，不抛出
---@return boolean ok, string source
function MemoryService.Save()
    local ok, err = pcall(function()
        if not fileSystem:DirExists(SAVE_DIR) then
            fileSystem:CreateDir(SAVE_DIR)
        end
        local encoded = cjson.encode(mem_)
        local file = File(SAVE_FILE, FILE_WRITE)
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

--- 一轮完整问答落库（发送时记一半，回复后再记另一半由调用方决定；这里一次记整轮）
---@param userMsg MsgEntry
---@param replyMsg MsgEntry|nil
---@param fact EventFact
---@param topics string[]
---@return CompanionMemory
function MemoryService.RecordTurn(userMsg, replyMsg, fact, topics)
    mem_.turns = mem_.turns + 1
    if mem_.firstServerTime == 0 then
        mem_.firstServerTime = userMsg.serverTime
    end
    mem_.lastServerTime = userMsg.serverTime
    mem_.lastFactId = fact.id

    mem_.transcript[#mem_.transcript + 1] = {
        role = userMsg.role,
        text = userMsg.text,
        serverTime = userMsg.serverTime,
    }
    if replyMsg then
        mem_.transcript[#mem_.transcript + 1] = {
            role = replyMsg.role,
            text = replyMsg.text,
            serverTime = replyMsg.serverTime,
        }
        mem_.lastServerTime = replyMsg.serverTime
    end
    while #mem_.transcript > TRANSCRIPT_CAP do
        table.remove(mem_.transcript, 1)
    end

    mergeTopics(topics or {})
    cloudDirty_ = true
    turnsSinceFlush_ = turnsSinceFlush_ + 1

    local saved = MemoryService.Save()
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
    mem_.turns = 0
    mem_.firstServerTime = 0
    mem_.lastServerTime = 0
    mem_.lastFactId = ""
    mem_.topics = {}
    mem_.transcript = {}
    source_ = "memory"
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
