-- ============================================================================
-- MessageService.lua — 消息数组 + 会话状态机
-- 只管「有哪些消息」和「这条用户消息走到哪个状态」：draft → sent → waiting →
-- typing → replied。文案由 ContentService 生成，事实由 EventService 选，
-- 存档由 MemoryService 落，本模块一概不碰。
-- ============================================================================

local MessageService = {}

MessageService.ROLE = {
    USER = "user",
    HER = "her",
    SYSTEM = "system",
}

MessageService.PHASE = {
    IDLE = "idle",
    SENT = "sent",
    WAITING = "waiting",
    TYPING = "typing",
}

-- 相位时长（秒）。sent 与 typing 固定，中段 waiting 补足到总时长。
local SENT_SECONDS = 1.5
local TYPING_SECONDS = 3.0
local DEFAULT_WAIT_SECONDS = 10

---@class MsgEntry
---@field id integer
---@field role string MessageService.ROLE_*
---@field text string 原文
---@field serverTime integer 该条消息落库时的权威 UTC 秒
---@field state string draft|sent|waiting|typing|replied（用户消息）；her/system 固定 replied
---@field factId? string 回复引用的事件事实 id
---@field statusText? string 用户消息当前给看的状态文案
---@field clockText? string 该条消息落库时当地的钟点，只用于气泡角标

---@type MsgEntry[]
local messages_ = {}
---@type MsgEntry|nil
local pending_ = nil
---@type number
local elapsed_ = 0
---@type integer
local version_ = 0
---@type integer
local nextId_ = 1
---@type number
local waitSeconds_ = DEFAULT_WAIT_SECONDS
---@type string
local phase_ = MessageService.PHASE.IDLE
---@type string
local draft_ = ""

---@class MessageServiceHooks
---@field onPhaseChange? fun(phase: string, pending: MsgEntry|nil): nil
---@field onDeliver? fun(pending: MsgEntry): nil

---@type MessageServiceHooks
local hooks_ = { onPhaseChange = nil, onDeliver = nil }

local function logInfo(msg)
    print("[MsgService] " .. msg)
    log:Write(LOG_INFO, "[MsgService] " .. msg)
end

local function logError(msg)
    print("[MsgService] ERROR: " .. msg)
    log:Write(LOG_ERROR, "[MsgService] " .. msg)
end

--- 相位 → 上屏文案（总时长在这里换算，UI 只负责显示）
---@param phase string
---@param pending MsgEntry|nil
---@return string
function MessageService.StatusText(phase, pending)
    if phase == MessageService.PHASE.SENT then
        return "已送达"
    elseif phase == MessageService.PHASE.WAITING then
        local left = math.max(0, math.ceil(waitSeconds_ - elapsed_))
        return "等待若夕回复 · 约 " .. tostring(left) .. " 秒"
    elseif phase == MessageService.PHASE.TYPING then
        return "若夕正在输入…"
    end
    if pending and pending.state == "replied" then
        return "已回复"
    end
    return ""
end

local function EmitPhase(newPhase)
    phase_ = newPhase
    if pending_ then
        pending_.state = newPhase
        pending_.statusText = MessageService.StatusText(newPhase, pending_)
    end
    logInfo("状态迁移 " .. newPhase)
    if hooks_.onPhaseChange then
        hooks_.onPhaseChange(newPhase, pending_)
    end
end

---@param opts? {waitSeconds?: integer, hooks?: MessageServiceHooks}
function MessageService.Init(opts)
    opts = opts or {}
    waitSeconds_ = opts.waitSeconds or DEFAULT_WAIT_SECONDS
    if waitSeconds_ < SENT_SECONDS + TYPING_SECONDS then
        logError(string.format(
            "等待时长 %.1f 秒小于 sent+typing 之和，已抬到最小可用值", waitSeconds_))
        waitSeconds_ = SENT_SECONDS + TYPING_SECONDS + 1
    end
    hooks_ = opts.hooks or { onPhaseChange = nil, onDeliver = nil }
    messages_ = {}
    pending_ = nil
    elapsed_ = 0
    nextId_ = 1
    phase_ = MessageService.PHASE.IDLE
    logInfo(string.format("初始化完成，正式链路等待 %.1f 秒", waitSeconds_))
end

---@return number
function MessageService.GetWaitSeconds()
    return waitSeconds_
end

---@param text string
function MessageService.SetDraft(text)
    draft_ = text or ""
end

---@return string
function MessageService.GetDraft()
    return draft_
end

---@return boolean
function MessageService.IsAwaiting()
    return pending_ ~= nil
end

---@return string
function MessageService.GetPhase()
    return phase_
end

---@return MsgEntry[]
function MessageService.GetMessages()
    return messages_
end

---@param role string
---@param text string
---@param serverTime integer
---@param clockText? string
---@return MsgEntry
local function Push(role, text, serverTime, clockText)
    local entry = {
        id = nextId_,
        role = role,
        text = text,
        serverTime = serverTime,
        state = "replied",
        statusText = "",
        clockText = clockText or "",
    }
    nextId_ = nextId_ + 1
    messages_[#messages_ + 1] = entry
    version_ = version_ + 1
    return entry
end

--- 消息数组版本号；UI 用它判断要不要重绘，避免每帧重建子树
---@return integer
function MessageService.GetVersion()
    return version_
end

--- 系统提示（不含角色气泡），例如资源缺失、排队说明
---@param text string
---@param serverTime integer
---@param clockText? string
---@return MsgEntry
function MessageService.AddSystem(text, serverTime, clockText)
    local entry = Push(MessageService.ROLE.SYSTEM, text, serverTime, clockText)
    logInfo("系统消息: " .. text)
    return entry
end

--- 发送一条用户消息；等待期间再次调用会被拒绝（返回 nil），原文留在 draft
---@param text string
---@param serverTime integer
---@param clockText? string
---@return MsgEntry|nil
function MessageService.Send(text, serverTime, clockText)
    if pending_ then
        draft_ = text or draft_
        logInfo("仍在等待回复，草稿已保留不丢弃")
        return nil
    end
    local trimmed = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        logInfo("草稿为空，忽略发送")
        return nil
    end

    draft_ = ""
    local entry = Push(MessageService.ROLE.USER, trimmed, serverTime, clockText)
    entry.state = "sent"
    pending_ = entry
    elapsed_ = 0
    logInfo(string.format("用户消息 #%d 已发出 serverTime=%d", entry.id, serverTime))
    EmitPhase(MessageService.PHASE.SENT)
    return entry
end

local function Deliver()
    if not pending_ then
        return
    end
    if hooks_.onDeliver then
        hooks_.onDeliver(pending_)
    else
        logError("缺少 onDeliver 回调，回复无法生成（main.lua 未接入 ContentService？）")
    end
    pending_.state = "replied"
    pending_.statusText = MessageService.StatusText("replied", pending_)
    pending_ = nil
    elapsed_ = 0
    phase_ = MessageService.PHASE.IDLE
    logInfo("状态迁移 replied → idle")
    if hooks_.onPhaseChange then
        hooks_.onPhaseChange(MessageService.PHASE.IDLE, nil)
    end
end

--- 推进状态机；由 main.lua 每帧用真实 timeStep 驱动
---@param dt number
function MessageService.Update(dt)
    if not pending_ then
        return
    end
    elapsed_ = elapsed_ + (dt or 0)

    if phase_ == MessageService.PHASE.SENT then
        if elapsed_ >= SENT_SECONDS then
            EmitPhase(MessageService.PHASE.WAITING)
        end
    elseif phase_ == MessageService.PHASE.WAITING then
        local typingAt = waitSeconds_ - TYPING_SECONDS
        if elapsed_ >= typingAt then
            EmitPhase(MessageService.PHASE.TYPING)
        end
    elseif phase_ == MessageService.PHASE.TYPING then
        if elapsed_ >= waitSeconds_ then
            Deliver()
        end
    end
end

--- 开发预览用：立刻跳到回复，走的是同一条生成 + 落库路径，不是伪造气泡
function MessageService.Skip()
    if not pending_ then
        logInfo("没有待回复的消息，跳过无效")
        return false
    end
    logInfo(string.format("跳过等待：从 %s 直接推进到 replied", phase_))
    elapsed_ = waitSeconds_
    if phase_ ~= MessageService.PHASE.TYPING then
        EmitPhase(MessageService.PHASE.TYPING)
    end
    Deliver()
    return true
end

--- 把生成好的回复挂回消息流（main.lua 在 onDeliver 里调用）
---@param text string
---@param serverTime integer
---@param factId string
---@param clockText? string
---@return MsgEntry
function MessageService.AppendReply(text, serverTime, factId, clockText)
    local entry = Push(MessageService.ROLE.HER, text, serverTime, clockText)
    entry.factId = factId
    logInfo(string.format("若夕回复 #%d fact=%s: %s", entry.id, tostring(factId), text))
    return entry
end

function MessageService.Reset()
    messages_ = {}
    pending_ = nil
    elapsed_ = 0
    phase_ = MessageService.PHASE.IDLE
    draft_ = ""
end

return MessageService
