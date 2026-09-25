-- ============================================================================
-- LifeService.lua — 平行人生存档槽（M4 §3）
-- 一张人生卡 = 一份完整、互不串写的存档：城市、关系起点、聊天记录、事件计划、
-- 共同记忆、最近打开时间与当前生活痕迹。最多三段；创建第四段前必须由用户
-- 明确选择要替换的卡片（本模块返回 needsReplace，绝不静默淘汰最旧一段）。
-- 冷启动恢复最近打开的一段：注册表按 lastOpenedUtc 选段，随后 main.lua 把该段
-- 的独立存档文件挂给 MemoryService —— 三段各用各的文件，结构上不可能互写。
--
-- 注册表 memory/lives.json 只放「卡片级」信息（选段、档案页摘要、当前痕迹）；
-- 聊天/事件/记忆全在各段自己的文件里。注册表损坏时退回「从段文件重建」，
-- 任何一段都不会因为一张索引而丢。
-- ============================================================================

local LifeService = {}

local ProfileService = require("ProfileService")

local REGISTRY_FILE = "memory/lives.json"
local SAVE_PREFIX = "memory/life-"
local LEGACY_SAVE_FILE = "memory/m0-1-la-stranger.json"
local MAX_SLOTS = 3
local REGISTRY_VERSION = 1

---@class LifeSlot
---@field slotId string life-1|life-2|life-3（同时决定存档文件名，稳定不变）
---@field cityId string
---@field relationId string
---@field seedText string
---@field isRandom boolean
---@field createdAtUtc integer
---@field lastOpenedUtc integer
---@field trace? CurrentTrace 当前生活痕迹（绑定最近确定的关键事件）

---@class LifeRegistry
---@field version integer
---@field activeSlotId? string
---@field slots LifeSlot[]

---@type LifeRegistry
local registry_ = {
    version = REGISTRY_VERSION,
    activeSlotId = nil,
    slots = {},
}

---@type string
local registryFile_ = REGISTRY_FILE
---@type string
local savePrefix_ = SAVE_PREFIX
---@type string
local legacyFile_ = LEGACY_SAVE_FILE
local loaded_ = false

local function logInfo(msg)
    print("[Life] " .. msg)
    log:Write(LOG_INFO, "[Life] " .. msg)
end

local function logWarn(msg)
    print("[Life] WARN: " .. msg)
    log:Write(LOG_WARNING, "[Life] " .. msg)
end

local function logError(msg)
    print("[Life] ERROR: " .. msg)
    log:Write(LOG_ERROR, "[Life] " .. msg)
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

---@param raw any
---@return LifeSlot?
local function readSlot(raw)    if type(raw) ~= "table" then
        return nil
    end
    local slotId = asString(raw.slotId)
    local cityId = asString(raw.cityId)
    local relationId = asString(raw.relationId)
    if not slotId or not cityId or not relationId then
        return nil
    end
    ---@type LifeSlot
    local slot = {
        slotId = slotId,
        cityId = cityId,
        relationId = relationId,
        seedText = asString(raw.seedText) or "",
        isRandom = raw.isRandom == true,
        createdAtUtc = asInteger(raw.createdAtUtc) or 0,
        lastOpenedUtc = asInteger(raw.lastOpenedUtc) or 0,
        trace = nil,
    }
    if type(raw.trace) == "table" then
        local traceKey = asString(raw.trace.traceKey)
        local occurrenceKey = asString(raw.trace.occurrenceKey)
        local sceneId = asString(raw.trace.sceneId)
        if traceKey and occurrenceKey and sceneId then
            slot.trace = {
                traceKey = traceKey,
                occurrenceKey = occurrenceKey,
                eventTitle = asString(raw.trace.eventTitle) or "",
                sceneId = sceneId,
                boundAtUtc = asInteger(raw.trace.boundAtUtc) or 0,
            }
        end
    end
    return slot
end

--- 独立测试/自检可注入自己的注册表与段文件前缀，绝不碰玩家的 lives.json。
---@class LifeInitOptions
---@field registryFile? string
---@field savePrefix? string
---@field legacyFile? string

---@param opts? LifeInitOptions
function LifeService.Init(opts)
    opts = opts or {}
    registryFile_ = opts.registryFile or REGISTRY_FILE
    savePrefix_ = opts.savePrefix or SAVE_PREFIX
    legacyFile_ = opts.legacyFile or LEGACY_SAVE_FILE
    loaded_ = false
    registry_ = { version = REGISTRY_VERSION, activeSlotId = nil, slots = {} }
end

---@param slotId string
---@return string
function LifeService.SlotSaveFile(slotId)
    -- slotId 自带 "life-" 段，前缀也以此收尾：去重后文件名是 memory/life-1.json，
    -- 与 ClearAll 的 savePrefix..n..".json" 严格一致，自检清理不会漏文件。
    local suffix = tostring(slotId):match("^life%-(.+)$") or tostring(slotId)
    return savePrefix_ .. suffix .. ".json"
end

function LifeService.Save()
    local ok, err = pcall(function()
        if not fileSystem:DirExists("memory") then
            fileSystem:CreateDir("memory")
        end
        local encoded = cjson.encode({
            version = registry_.version,
            activeSlotId = registry_.activeSlotId,
            slots = registry_.slots,
        })
        local file = File(registryFile_, FILE_WRITE)
        if not file:IsOpen() then
            error("注册表不可写")
        end
        file:WriteString(encoded)
        file:Close()
        file:Dispose()
        logInfo(string.format("人生注册表已写入 %d 字节（%d 段）", #encoded, #registry_.slots))
    end)
    if not ok then
        logWarn("写人生注册表失败，本轮只留在内存：" .. tostring(err))
        return false
    end
    return true
end

--- 旧版单存档迁移：没有注册表但 M0–M3 的历史文件还在，就把它收编为第一段人生，
--- 聊天记录、事件计划、档案原样保留，不弹初始化、不清历史。
local function migrateLegacy(utcNow)
    local migrated = pcall(function()
        if not fileSystem:FileExists(legacyFile_) then
            return
        end
        local file = File(legacyFile_, FILE_READ)
        if not file:IsOpen() then
            return
        end
        local raw = file:ReadString()
        file:Close()
        file:Dispose()
        local decoded = nil
        local decodeOk = pcall(function()
            decoded = cjson.decode(raw)
        end)
        if not decodeOk or type(decoded) ~= "table" then
            return
        end
        local profile = type(decoded.profile) == "table" and decoded.profile or nil
        local slot = readSlot({
            slotId = "life-1",
            cityId = profile and profile.cityId or asString(decoded.cityId) or "los_angeles",
            relationId = profile and profile.relationId or "stranger",
            seedText = profile and profile.seedText or "",
            isRandom = profile and profile.isRandom == true,
            createdAtUtc = asInteger(decoded.firstServerTime) or 0,
            lastOpenedUtc = asInteger(decoded.lastServerTime) or utcNow or 0,
            trace = nil,
        })
        if slot then
            registry_.slots[#registry_.slots + 1] = slot
            registry_.activeSlotId = slot.slotId
            -- 收编不只是登记卡片：会话此后从 life-1 自己的段文件读，历史必须原地复制一份过去，
            -- 否则「不丢历史」只写在注释里。旧文件原样留着，当只读备份。
            local target = File(LifeService.SlotSaveFile(slot.slotId), FILE_WRITE)
            if target:IsOpen() then
                target:WriteString(raw)
                target:Close()
                target:Dispose()
            end
            logInfo("旧单存档已收编为人生 life-1（" .. slot.cityId .. "×" .. slot.relationId .. "）")
        end
    end)
    if not migrated then
        logWarn("旧存档收编失败，按干净安装处理")
    end
end

---@param utcNow? number
---@return LifeRegistry
function LifeService.Load(utcNow)
    loaded_ = true
    local ok, err = pcall(function()
        if not fileSystem:FileExists(registryFile_) then
            migrateLegacy(utcNow)
            if #registry_.slots > 0 then
                LifeService.Save()
            end
            return
        end
        local file = File(registryFile_, FILE_READ)
        if not file:IsOpen() then
            error("注册表打不开")
        end
        local raw = file:ReadString()
        file:Close()
        file:Dispose()
        local decoded = nil
        local decodeOk = pcall(function()
            decoded = cjson.decode(raw)
        end)
        if not decodeOk or type(decoded) ~= "table" or type(decoded.slots) ~= "table" then
            error("JSON 解析失败或结构不符")
        end
        local slots = {}
        for i = 1, #decoded.slots do
            local slot = readSlot(decoded.slots[i])
            if slot then
                slots[#slots + 1] = slot
            end
        end
        registry_.version = asInteger(decoded.version) or REGISTRY_VERSION
        registry_.slots = slots
        local active = asString(decoded.activeSlotId)
        registry_.activeSlotId = LifeService.SlotById(active) and active or nil
    end)
    if not ok then
        logError("读人生注册表失败，退回旧存档收编：" .. tostring(err))
        registry_ = { version = REGISTRY_VERSION, activeSlotId = nil, slots = {} }
        migrateLegacy(utcNow)
    end
    logInfo(string.format("人生槽加载：%d 段，活跃=%s",
        #registry_.slots, tostring(registry_.activeSlotId or "无")))
    return registry_
end

---@param slotId? string
---@return LifeSlot?
function LifeService.SlotById(slotId)
    if type(slotId) ~= "string" then
        return nil
    end
    for i = 1, #registry_.slots do
        if registry_.slots[i].slotId == slotId then
            return registry_.slots[i]
        end
    end
    return nil
end

---@return LifeSlot[]
function LifeService.Slots()
    if not loaded_ then
        LifeService.Load()
    end
    return registry_.slots
end

---@return integer
function LifeService.Count()
    return #LifeService.Slots()
end

function LifeService.IsFull()
    return LifeService.Count() >= MAX_SLOTS
end

---@return LifeSlot?
function LifeService.Active()
    if not loaded_ then
        LifeService.Load()
    end
    return LifeService.SlotById(registry_.activeSlotId)
end

--- 冷启动入口：没有活跃指针就取「最近打开」的那一段（M4 验收：冷启动直达最近人生）。
---@return LifeSlot?
function LifeService.LatestOpened()
    local best = nil
    for i = 1, #registry_.slots do
        local slot = registry_.slots[i]
        if not best or slot.lastOpenedUtc > best.lastOpenedUtc then
            best = slot
        end
    end
    return best
end

local function nextFreeSlotId()
    local used = {}
    for i = 1, #registry_.slots do
        used[registry_.slots[i].slotId] = true
    end
    for n = 1, MAX_SLOTS do
        local candidate = "life-" .. tostring(n)
        if not used[candidate] then
            return candidate
        end
    end
    return nil
end

--- 创建/替换的入闸判定：id 必须命中 ProfileService 那张四城×四关系矩阵。
--- 不在矩阵里就返回 invalid，绝不落一张「玩家没选过」的卡片
--- （ProfileService.compose 那套 LA×陌生网友 回落是给脏存档做迁移用的，不是给选择用的）。
---@param cityId any
---@param relationId any
---@return boolean
local function isKnownPair(cityId, relationId)
    return ProfileService.IsValidCityId(cityId) and ProfileService.IsValidRelationId(relationId)
end

---@class LifeCreateOptions
---@field seedText? string
---@field isRandom? boolean

--- 创建一段新人生。满三段时不创建、不淘汰 —— 返回 "full"，
--- 由 UI 层请用户明确点选要替换的那张卡片（设计 §3）。
---@param cityId string
---@param relationId string
---@param opts? LifeCreateOptions
---@param utcNow number
---@return LifeSlot? slot
---@return string? reason ok|full|invalid
function LifeService.CreateSlot(cityId, relationId, opts, utcNow)
    if not loaded_ then
        LifeService.Load(utcNow)
    end
    if not isKnownPair(cityId, relationId) then
        logWarn("拒绝创建：城市=" .. tostring(cityId) .. " 关系=" .. tostring(relationId) .. " 不在矩阵内")
        return nil, "invalid"
    end
    if #registry_.slots >= MAX_SLOTS then
        return nil, "full"
    end
    opts = opts or {}
    local slotId = nextFreeSlotId()
    if not slotId then
        return nil, "full"
    end
    ---@type LifeSlot
    local slot = {
        slotId = slotId,
        cityId = cityId,
        relationId = relationId,
        seedText = opts.seedText or (cityId .. "|" .. relationId),
        isRandom = opts.isRandom == true,
        createdAtUtc = math.floor(utcNow or 0),
        lastOpenedUtc = math.floor(utcNow or 0),
        trace = nil,
    }
    registry_.slots[#registry_.slots + 1] = slot
    registry_.activeSlotId = slotId
    LifeService.Save()
    logInfo(string.format("新人生 %s：城市=%s 关系=%s 随机=%s",
        slotId, cityId, relationId, tostring(slot.isRandom)))
    return slot, "ok"
end

--- 用新档案替换一张既有卡片：段号与存档文件名保持不变，旧内容整段作废。
--- 旧段文件的删除由调用方走 ClearSlotSaveFile，成功与否都先把卡片换成新人生。
---@param slotId string
---@param cityId string
---@param relationId string
---@param opts? LifeCreateOptions
---@param utcNow number
---@return LifeSlot? slot
---@return string? reason
function LifeService.ReplaceSlot(slotId, cityId, relationId, opts, utcNow)
    if not loaded_ then
        LifeService.Load(utcNow)
    end
    local slot = LifeService.SlotById(slotId)
    if not slot then
        return nil, "missing"
    end
    if not isKnownPair(cityId, relationId) then
        logWarn("拒绝替换：城市=" .. tostring(cityId) .. " 关系=" .. tostring(relationId) .. " 不在矩阵内")
        return nil, "invalid"
    end
    opts = opts or {}
    slot.cityId = cityId
    slot.relationId = relationId
    slot.seedText = opts.seedText or (cityId .. "|" .. relationId)
    slot.isRandom = opts.isRandom == true
    slot.createdAtUtc = math.floor(utcNow or 0)
    slot.lastOpenedUtc = math.floor(utcNow or 0)
    slot.trace = nil
    registry_.activeSlotId = slotId
    LifeService.Save()
    logInfo(string.format("替换人生 %s：城市=%s 关系=%s", slotId, cityId, relationId))
    return slot, "ok"
end

--- 打开一段人生：设为活跃并刷新最近打开时间（冷启动选段、切换卡片都走这里）。
---@param slotId string
---@param utcNow number
---@return LifeSlot?
function LifeService.OpenSlot(slotId, utcNow)
    if not loaded_ then
        LifeService.Load(utcNow)
    end
    local slot = LifeService.SlotById(slotId)
    if not slot then
        logWarn("打开不存在的人生槽: " .. tostring(slotId))
        return nil
    end
    slot.lastOpenedUtc = math.floor(utcNow or slot.lastOpenedUtc or 0)
    registry_.activeSlotId = slotId
    LifeService.Save()
    return slot
end

--- 开发链路（HandleDevCity）切城市时同步卡片摘要：注册表与存档说的是同一份档案。
--- isRandom/seedText 只在 opts 显式给出时才改：省略不等于「清成非随机」，
--- 否则一次切城就把随机段的派生记录抹掉，重进时说法就不一致了。
---@param slotId string
---@param cityId string
---@param relationId string
---@param opts? LifeCreateOptions
---@return boolean
function LifeService.UpdateSlotProfile(slotId, cityId, relationId, opts)
    local slot = LifeService.SlotById(slotId)
    if not slot then
        return false
    end
    opts = opts or {}
    slot.cityId = cityId
    slot.relationId = relationId
    if opts.seedText ~= nil then
        slot.seedText = opts.seedText
    end
    if opts.isRandom ~= nil then
        slot.isRandom = opts.isRandom == true
    end
    LifeService.Save()
    return true
end

--- 当前生活痕迹的唯一写入点：绑定「最近确定的关键事件」，下一关键事件替换。
--- 痕迹跟着槽走、不跟着城市指针走 —— 换段人生读回的是那一段自己的痕迹。
---@param slotId string
---@param trace CurrentTrace?
---@param utcNow number
---@return boolean
function LifeService.SetTrace(slotId, trace, utcNow)
    local slot = LifeService.SlotById(slotId)
    if not slot then
        return false
    end
    if trace and trace.traceKey and trace.occurrenceKey and trace.sceneId then
        slot.trace = {
            traceKey = trace.traceKey,
            occurrenceKey = trace.occurrenceKey,
            eventTitle = trace.eventTitle or "",
            sceneId = trace.sceneId,
            boundAtUtc = math.floor(utcNow or 0),
        }
    else
        slot.trace = nil
    end
    LifeService.Save()
    return true
end

---@param slotId? string 省略则取活跃段
---@return CurrentTrace?
function LifeService.GetTrace(slotId)
    local slot = (slotId and LifeService.SlotById(slotId)) or LifeService.Active()
    return slot and slot.trace or nil
end

--- 删除某段的独立存档文件（替换卡片时先毁旧历史；注册表条目由 ReplaceSlot 覆盖）。
--- 删不掉就把文件覆盖成一个「不是存档」的桩：MemoryService.Load 读回时结构判定不过，
--- 会退回干净内存态 —— 替换后的那一段绝不能带着上一段的档案/聊天重新挂载。
---@param slotId string
---@return boolean cleared
function LifeService.ClearSlotSaveFile(slotId)
    local path = LifeService.SlotSaveFile(slotId)
    local ok, err = pcall(function()
        if not fileSystem:FileExists(path) then
            return
        end
        fileSystem:Delete(path)
        if fileSystem:FileExists(path) then
            local file = File(path, FILE_WRITE)
            if not file:IsOpen() then
                error("既删不掉也覆盖不了")
            end
            file:WriteString("{}")
            file:Close()
            file:Dispose()
            logWarn("存档删不掉，已用空档覆盖: " .. path)
        end
    end)
    if not ok then
        logWarn("清理人生段存档失败: " .. path .. " " .. tostring(err))
        return false
    end
    return true
end

--- 自检/重置用：清掉注册表与全部段文件，回到干净安装。
function LifeService.ClearAll()
    pcall(function()
        if fileSystem:FileExists(registryFile_) then
            fileSystem:Delete(registryFile_)
        end
        for n = 1, MAX_SLOTS do
            local path = savePrefix_ .. tostring(n) .. ".json"
            if fileSystem:FileExists(path) then
                fileSystem:Delete(path)
            end
        end
    end)
    registry_ = { version = REGISTRY_VERSION, activeSlotId = nil, slots = {} }
    loaded_ = true
end

return LifeService
