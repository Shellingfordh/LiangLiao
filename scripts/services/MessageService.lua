-- ============================================================================
-- MessageService.lua — 消息数组 + 每条消息独立的相位机 + FIFO 回复队列
-- 只管「有哪些消息」和「这条用户消息走到哪个状态」：
--   sent（已送达）→ waiting | queued → typing → replied
-- 时机一律用权威 UTC 绝对时刻判定（Update 由外部注入 utcNow），本模块自己不读时钟，
-- 所以真机上跟 common.get_server_time() 走，开发自检可以用可控 UTC 驱动。
-- 计划回复时刻（planReplyAtUtc）由 main.lua 用 TimeState.ReplyPlanFor 算好传进来；
-- 文案由 ContentService 生成，事实由 EventService 选，存档由 MemoryService 落。
-- 另管两件 M2-A 的事：
--   * 引用（quotedMessageId/quotedRole/quotedTextPreview）：只认当前会话里真实存在的
--     user/her 消息，任何不成立都降级成普通消息，而不是拒绝发送。
--   * 多段回复：一条回复仍是一个 MsgEntry，短句按间隔追加进同一条 text，
--     期间相位回到 typing。拆成多条会同时搅乱 FIFO 计数与「一条回复一条记录」。
-- ============================================================================

local ContentService = require("services.ContentService")

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
    QUEUED = "queued",
    TYPING = "typing",
}

-- 逐句上屏的段间隔对外公开：DevSelfTest 要靠它把时钟拨到下一句，主循环也可能要读。
MessageService.SEGMENT_GAP_SECONDS = 2.5

-- 相位时长（秒）。sent 与 typing 固定；waiting/queued 的长度取决于外部传入的计划。
local SENT_SECONDS = 1.5
local TYPING_SECONDS = 3.0
-- 队首的交付时刻至少要留出 sent+typing，否则相位会挤在同一秒里塌掉。
-- 取整是必须的：这些秒数会加到 UTC 秒上，而 UTC 秒要能进 %d 与存档。
local MIN_REPLY_LEAD = math.floor(SENT_SECONDS + TYPING_SECONDS + 0.5)
-- 她连续两条回复之间的最小间隔：后发的消息不得越过先发的消息
local RESPONSE_GAP_SECONDS = 4
-- 同一条回复里，上一句与下一句之间的间隔。复用 typing 相位，所以这个值同时决定
-- 「正在输入」气泡停留多久；太短会像一次性刷出一整段，太长会让人以为她没在打。
local SEGMENT_GAP_SECONDS = MessageService.SEGMENT_GAP_SECONDS
-- 引用预览的字符数上限。裁过的文本才落盘，存档里不放第二条私聊原文。
local QUOTE_PREVIEW_MAX = 24

---@class MsgEntry
---@field id integer
---@field role string MessageService.ROLE_*
---@field text string 原文
---@field serverTime integer 该条消息落库时的权威 UTC 秒
---@field state string draft|sent|waiting|queued|typing|replied（用户消息）；her/system 固定 replied
---@field factId? string 回复（或送达时）引用的事件事实 id
---@field factKey? string 引用的事件实例 occurrenceKey（送达与回复共用同一个键）
---@field statusText? string 用户消息当前给看的状态文案
---@field clockText? string 该条消息落库时当地的钟点，只用于气泡角标
---@field planReplyAtUtc? integer 计划回复的权威 UTC 秒（用户消息）
---@field planWindowStartUtc? integer 下一个可回复窗口的起始 UTC 秒；当下即可回复时为 nil
---@field replyableAtSend? boolean 送达时她是否处于可回复档
---@field brief? boolean 碎片时间档：回复要短
---@field availabilityAtSend? string 送达时的可用性（idle|fragments|busy|offline）
---@field availabilityLabelAtSend? string 送达时可用性的中文标签
---@field placeAtSend? string 送达时的地点（作息表事实，不是猜测）
---@field sceneIdAtSend? string 送达时的场景 id
---@field phraseAtSend? string 送达时作息表里的那句原话
---@field quotedMessageId? integer 引用的消息 id（只可能是当前会话里的 user/her 消息）
---@field quotedRole? string 被引用消息的角色
---@field quotedTextPreview? string 被引用消息的裁剪预览，随存档走
---@field effReplyAtUtc? number 本轮实际交付时刻（补发时重排，不落盘）
---@field streamSegments? string[] 还没上屏的短句（本轮运行时字段，不落盘）
---@field streamIndex? integer 已经上屏到第几句
---@field streamNextAtUtc? number 下一句的权威 UTC 秒（本轮运行时字段，不落盘）

---@type MsgEntry[]
local messages_ = {}
---@type MsgEntry[]
local queue_ = {}
---@type integer
local version_ = 0
---@type integer
local nextId_ = 1
---@type string
local phase_ = MessageService.PHASE.IDLE
---@type string
local draft_ = ""
---@type integer 最近一条已排定的计划回复时刻（UTC 秒），用来挡住后发越序
local lastPlannedAtUtc_ = 0
--- 正在逐句上屏的回复。必须是列表而不是单条：前一条还剩几句没上屏时，
--- 后一条消息也可能到点交付，单条槽位会被后一条覆盖，前一条剩下的句子就永远丢了。
--- 这些回复都已经出队，所以放在这里不影响 queue_ 的 FIFO。
---@type MsgEntry[]
local streaming_ = {}

---@class MessageServiceHooks
---@field onPhaseChange? fun(phase: string, head: MsgEntry|nil): nil
---@field onDeliver? fun(pending: MsgEntry): nil
---@field formatClock? fun(utcSec: number): string 把 UTC 秒换成当地钟点文案（排队提示要用）

---@type MessageServiceHooks
local hooks_ = {}

local function logInfo(msg)
    print("[MsgService] " .. msg)
    log:Write(LOG_INFO, "[MsgService] " .. msg)
end

local function logError(msg)
    print("[MsgService] ERROR: " .. msg)
    log:Write(LOG_ERROR, "[MsgService] " .. msg)
end

---@return MsgEntry|nil
function MessageService.GetHead()
    return queue_[1]
end

--- 还没被回复的用户消息条数
---@return integer
function MessageService.GetQueueLength()
    return #queue_
end

--- 计划回复时刻已经过了、等着补发的条数（重进时决定要不要给一条离开摘要）
---@param utcNow number
---@return integer
function MessageService.GetDueCount(utcNow)
    local n = 0
    for i = 1, #queue_ do
        if (queue_[i].planReplyAtUtc or 0) <= utcNow then
            n = n + 1
        end
    end
    return n
end

--- 该消息在队列里的位置（1 = 队首）；不在队列里返回 0
---@param entry MsgEntry
---@return integer
function MessageService.QueuePosition(entry)
    for i = 1, #queue_ do
        if queue_[i] == entry then
            return i
        end
    end
    return 0
end

local function ClockTextOf(utcSec)
    if not utcSec then
        return ""
    end
    if hooks_.formatClock then
        return hooks_.formatClock(utcSec)
    end
    return tostring(utcSec)
end

--- 单条气泡上的短状态。忙碌/睡眠只说「已送达 + 已排队」，绝不显示已读。
---@param entry MsgEntry
---@return string
function MessageService.EntryStatusText(entry)
    if entry.role ~= MessageService.ROLE.USER then
        return ""
    end
    if entry.state == MessageService.PHASE.SENT then
        return "已送达"
    elseif entry.state == MessageService.PHASE.WAITING then
        return "已送达 · 等待回复"
    elseif entry.state == MessageService.PHASE.QUEUED then
        local pos = MessageService.QueuePosition(entry)
        local tail = pos > 1 and (" · 第 " .. tostring(pos) .. " 位") or ""
        return "已送达 · 对方" .. (entry.availabilityLabelAtSend or "在忙") .. "，已排队" .. tail
    elseif entry.state == MessageService.PHASE.TYPING then
        return "若夕正在输入"
    elseif entry.state == "replied" then
        return "已回复"
    end
    return ""
end

--- 状态条长文案（含倒计时与下一个可回复窗口的当地钟点）
---@param utcNow number
---@return string
function MessageService.StatusLine(utcNow)
    local head = queue_[1]
    if not head then
        return ""
    end
    if head.state == MessageService.PHASE.TYPING then
        return "若夕正在输入…"
    elseif head.state == MessageService.PHASE.SENT then
        return "已送达"
    elseif head.state == MessageService.PHASE.WAITING then
        local left = math.max(0, math.ceil((head.effReplyAtUtc or head.planReplyAtUtc or utcNow) - utcNow))
        return "等待若夕回复 · 约 " .. tostring(left) .. " 秒"
    end
    local text = "对方" .. (head.availabilityLabelAtSend or "在忙") .. "，消息已排队"
    if #queue_ > 1 then
        text = text .. "（" .. tostring(#queue_) .. " 条）"
    end
    if head.planWindowStartUtc and head.planReplyAtUtc and head.planReplyAtUtc > utcNow then
        text = text .. " · " .. ClockTextOf(head.planWindowStartUtc) .. " 之后能回"
    end
    return text
end

--- 改状态并只在真的变化时递增版本号（UI 靠版本号做增量刷新）
---@param entry MsgEntry
---@param newState string
---@return boolean changed
local function SetState(entry, newState)
    if entry.state == newState then
        return false
    end
    entry.state = newState
    entry.statusText = MessageService.EntryStatusText(entry)
    version_ = version_ + 1
    return true
end

--- 队首相位迁移（日志字面量与 M0-1 保持一致，便于比对既有验收证据）
local function EmitPhase(newPhase)
    local head = queue_[1]
    phase_ = newPhase
    if head then
        if SetState(head, newPhase) then
            logInfo("状态迁移 " .. newPhase)
        end
    end
    if hooks_.onPhaseChange then
        hooks_.onPhaseChange(newPhase, head)
    end
end

--- 非队首消息统一显示排队；队首由相位机决定
local function SyncQueueStates()
    for i = 2, #queue_ do
        if SetState(queue_[i], MessageService.PHASE.QUEUED) then
            logInfo(string.format("消息 #%d 排队中（第 %d 位）", queue_[i].id, i))
        end
    end
end

--- 后发的消息不得越过先发的：计划时刻至少是上一条之后 RESPONSE_GAP_SECONDS
---@param plan ReplyPlan|nil
---@param sentAt integer
---@return integer
local function ResolveReplyAtUtc(plan, sentAt)
    local planned = math.floor((plan and plan.replyAtUtc) or (sentAt + MIN_REPLY_LEAD))
    if planned < sentAt + MIN_REPLY_LEAD then
        planned = sentAt + MIN_REPLY_LEAD
    end
    if lastPlannedAtUtc_ > 0 and planned < lastPlannedAtUtc_ + RESPONSE_GAP_SECONDS then
        planned = lastPlannedAtUtc_ + RESPONSE_GAP_SECONDS
    end
    lastPlannedAtUtc_ = planned
    return planned
end

---@param opts? { hooks?: MessageServiceHooks }
function MessageService.Init(opts)
    opts = opts or {}
    hooks_ = opts.hooks or {}
    messages_ = {}
    queue_ = {}
    nextId_ = 1
    version_ = 0
    lastPlannedAtUtc_ = 0
    streaming_ = {}
    phase_ = MessageService.PHASE.IDLE
    draft_ = ""
    logInfo(string.format(
        "初始化完成：FIFO 队列 · sent %.1fs + typing %.1fs + 间隔下限 %ds · 多段间隔 %.1fs",
        SENT_SECONDS, TYPING_SECONDS, RESPONSE_GAP_SECONDS, SEGMENT_GAP_SECONDS))
end

---@param text string
function MessageService.SetDraft(text)
    draft_ = text or ""
end

---@return string
function MessageService.GetDraft()
    return draft_
end

--- 队列里还有待回复的消息（M0-1 时期等价于「在等这一条回复」）
---@return boolean
function MessageService.IsAwaiting()
    return #queue_ > 0
end

---@return string
function MessageService.GetPhase()
    return phase_
end

---@return MsgEntry[]
function MessageService.GetMessages()
    return messages_
end

--- 消息数组版本号；UI 用它判断要不要重绘，避免每帧重建子树
---@return integer
function MessageService.GetVersion()
    return version_
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

--- 系统提示（不含角色气泡），例如资源缺失、排队说明、离开期间摘要
---@param text string
---@param serverTime integer
---@param clockText? string
---@return MsgEntry
function MessageService.AddSystem(text, serverTime, clockText)
    local entry = Push(MessageService.ROLE.SYSTEM, text, serverTime, clockText)
    logInfo("系统消息: " .. text)
    return entry
end

---@class SendContext 送达时刻的确定性上下文，全部来自 TimeState 快照，不允许猜测
---@field plan? ReplyPlan
---@field availability? string
---@field availabilityLabel? string
---@field place? string
---@field sceneId? string
---@field phrase? string
---@field factId? string
---@field factKey? string 送达时刻命中的事件实例（occurrenceKey），补回与重进都引用它
---@field quote? QuoteRef 本条消息引用的那条（不成立时降级为普通消息，不拒绝发送）

---@class QuoteRef 调用方声明的引用意图，id 指当前会话里的消息
---@field id integer
---@field role? string 仅供调用方自洽性检查，最终以查到的消息为准
---@field text? string 仅供调用方展示，最终以查到的消息为准

--- 引用校验：只认当前会话里真实存在的 user/her 消息。
--- 任何一条不成立都返回 nil，让这条消息按普通消息发出去——引用是附加信息，
--- 不该成为「发不出去」的理由（M2-A 规格：失效引用一律降级，不拒绝）。
---@param quote QuoteRef|nil
---@return { id: integer, role: string, text: string }|nil
local function NormalizeQuote(quote)
    if not quote then
        return nil
    end
    local id = quote.id
    if type(id) ~= "number" or id ~= math.floor(id) or id <= 0 then
        return nil
    end
    local target
    for i = 1, #messages_ do
        if messages_[i].id == id then
            target = messages_[i]
            break
        end
    end
    if not target then
        return nil
    end
    if target.role ~= MessageService.ROLE.USER and target.role ~= MessageService.ROLE.HER then
        return nil
    end
    local raw = (target.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then
        return nil
    end
    return {
        id = target.id,
        role = target.role,
        text = ContentService.ClipPreview(raw, QUOTE_PREVIEW_MAX),
    }
end

--- 发送一条用户消息：一律入队（M1 起不再拒绝），并当场算好计划回复时刻
---@param text string
---@param serverTime integer
---@param clockText? string
---@param ctx? SendContext
---@return MsgEntry|nil
function MessageService.Send(text, serverTime, clockText, ctx)
    local trimmed = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        draft_ = text or draft_
        logInfo("草稿为空，忽略发送并保留草稿")
        return nil
    end
    ctx = ctx or {}
    if not ctx.plan then
        logError("Send 缺少 TimeState 回复计划，按最短链路兜底")
    end

    draft_ = ""
    local entry = Push(MessageService.ROLE.USER, trimmed, serverTime, clockText)
    local plan = ctx.plan
    entry.planReplyAtUtc = ResolveReplyAtUtc(plan, serverTime)
    entry.planWindowStartUtc = plan and plan.windowStartUtc or nil
    entry.replyableAtSend = (plan and plan.replyable) or false
    entry.brief = (plan and plan.brief) or false
    entry.availabilityAtSend = ctx.availability
    entry.availabilityLabelAtSend = ctx.availabilityLabel
    entry.placeAtSend = ctx.place
    entry.sceneIdAtSend = ctx.sceneId
    entry.phraseAtSend = ctx.phrase
    -- 送达瞬间就带上事实 id 与实例键：引用的是「哪一场活动的哪一个实例」，不随回复时间漂移
    entry.factId = ctx.factId
    entry.factKey = ctx.factKey
    entry.effReplyAtUtc = entry.planReplyAtUtc
    local quote = NormalizeQuote(ctx.quote)
    if ctx.quote and not quote then
        logInfo(string.format("消息 #%d 的引用不成立（id 不在会话内 / 非 user|her / 内容为空），按普通消息发送",
            entry.id))
    end
    if quote then
        entry.quotedMessageId = quote.id
        entry.quotedRole = quote.role
        entry.quotedTextPreview = quote.text
    end
    queue_[#queue_ + 1] = entry

    logInfo(string.format(
        "用户消息 #%d 已发出 serverTime=%d 计划回复=%d（%s · 队列 %d 条）",
        entry.id, serverTime, entry.planReplyAtUtc,
        entry.replyableAtSend and "当下可回复" or "排队到下一个窗口", #queue_))
    if #queue_ == 1 then
        EmitPhase(MessageService.PHASE.SENT)
    else
        SetState(entry, MessageService.PHASE.QUEUED)
        logInfo(string.format("消息 #%d 排在队首之后，标记排队（第 %d 位）",
            entry.id, MessageService.QueuePosition(entry)))
    end
    SyncQueueStates()
    return entry
end

local function Deliver()
    local head = queue_[1]
    if not head then
        return
    end
    -- 顺序要紧：先把队首落成 replied，再生成回复并落盘。反过来会把
    -- 「state=typing」的这条写进存档，重进时它会被再回一次。
    SetState(head, "replied")
    head.effReplyAtUtc = nil
    if hooks_.onDeliver then
        hooks_.onDeliver(head)
    else
        logError("缺少 onDeliver 回调，回复无法生成（main.lua 未接入 ContentService？）")
    end
    table.remove(queue_, 1)

    local nextHead = queue_[1]
    if nextHead then
        phase_ = nextHead.state
        logInfo(string.format("回复 #%d 完成，队列还剩 %d 条，按顺序继续处理下一条", head.id, #queue_))
    else
        phase_ = MessageService.PHASE.IDLE
        logInfo("状态迁移 replied → idle")
    end
    if hooks_.onPhaseChange then
        hooks_.onPhaseChange(phase_, nextHead)
    end
end

--- 过期未交付的队首（离开期后重进、或排在别人后面）重排为「短暂正在输入后交付」，
--- 但不改写权威的 planReplyAtUtc —— 落盘的始终是当初算好的计划。
---
--- 「抬窗」的条件必须是「这条还没在输入中」，判据用 state 而不是另开一个标记：
---   * Update 每帧调用，若无条件把过期目标顶到 now + typing，目标永远跑在时钟前面，
---     `now >= effReplyAtUtc` 永不成立，队首卡死在正在输入（M1 云端实测的第二个坑）。
---   * 反过来，已经在打点的队首被时钟跨过计划时刻时（`state == typing` 且 `eff < now`，
---     只差一两个采样点），**必须就地交付**，不能再补一个窗口 —— 否则会凭空多等 3 秒，
---     实测让「10 秒链路」在计划后的第一个采样点被判成没回复（自检 A5/A6/A7 三连红）。
---   * 而真正需要补窗的两种情况（重进时计划早已过期、排在别人后面）进入这里时
---     state 还是 queued/sent，从没显示过输入，抬窗仍然生效。
---@param head MsgEntry
---@param now number
---@return number
local function EffectiveReplyAt(head, now)
    local planned = head.effReplyAtUtc or head.planReplyAtUtc
    if not planned then
        return now + TYPING_SECONDS
    end
    if planned < now and head.state ~= MessageService.PHASE.TYPING then
        return now + TYPING_SECONDS
    end
    return planned
end

--- 开发预览用：立刻交付队首，走的是同一条生成 + 落库路径，不是伪造气泡。
--- 队首若还排在不可回复窗口之后，这条日志会写明是开发入口越过了时间窗。
function MessageService.Skip()
    local head = queue_[1]
    if not head then
        logInfo("没有待回复的消息，跳过无效")
        return false
    end
    if head.planWindowStartUtc then
        logInfo("跳过等待：开发入口越过尚未到达的可回复窗口")
    end
    logInfo(string.format("跳过等待：从 %s 直接推进到 replied", head.state))
    head.effReplyAtUtc = 0
    if head.state ~= MessageService.PHASE.TYPING then
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
---@param factKey? string 本条回复所依据的事件实例 occurrenceKey
---@return MsgEntry
function MessageService.AppendReply(text, serverTime, factId, clockText, factKey)
    local entry = Push(MessageService.ROLE.HER, text, serverTime, clockText)
    entry.factId = factId
    entry.factKey = factKey
    -- 只记事实与长度：回复正文会带上用户原文的片段，不整条落进运行日志
    logInfo(string.format("若夕回复 #%d fact=%s key=%s 长度=%d",
        entry.id, tostring(factId), tostring(factKey), #text))
    return entry
end

--- 逐句上屏：第 1 句立刻落库（保持「到点即回复」的时序，不额外拖延），
--- 其余短句按 SEGMENT_GAP_SECONDS 间隔追加进同一条 text。
--- 走的是 Push + 版本号递增这条与 AppendReply 完全相同的路径，
--- 所以 FIFO 计数、「一条回复一条记录」、存档字段都不变。
--- 分段为空或只剩一句时退化成普通 AppendReply，不会卡住队列。
---@param segments string[]
---@param serverTime integer
---@param factId string
---@param clockText? string
---@param factKey? string
---@return MsgEntry|nil
function MessageService.BeginReplyStream(segments, serverTime, factId, clockText, factKey)
    ---@type string[]
    local list = {}
    ---@type string|nil
    local head
    for i = 1, #(segments or {}) do
        local s = segments[i]
        if type(s) == "string" and s:gsub("^%s+", ""):gsub("%s+$", "") ~= "" then
            list[#list + 1] = s
            head = head or s
        end
    end
    if not head then
        return nil
    end
    local entry = Push(MessageService.ROLE.HER, head, serverTime, clockText)
    entry.factId = factId
    entry.factKey = factKey
    if #list == 1 then
        logInfo(string.format("若夕回复 #%d fact=%s key=%s 单句，直接上屏",
            entry.id, tostring(factId), tostring(factKey)))
        return entry
    end
    entry.streamSegments = list
    entry.streamIndex = 1
    entry.streamNextAtUtc = serverTime + SEGMENT_GAP_SECONDS
    streaming_[#streaming_ + 1] = entry
    logInfo(string.format("若夕回复 #%d 分 %d 句，第 1 句已上屏，其余逐句追加",
        entry.id, #list))
    EmitPhase(MessageService.PHASE.TYPING)
    return entry
end

--- 追加下一句。队列非空时整体停一拍：还有用户消息时相位归那条消息管，
--- 否则句子流会把新消息的 sent 相位吞掉，看起来像刚发出去就已经在读回复。
---@param now number
local function AdvanceStreaming(now)
    if queue_[1] or #streaming_ == 0 then
        return
    end
    for i = #streaming_, 1, -1 do
        local entry = streaming_[i]
        local segments = entry.streamSegments or {}
        local idx = (entry.streamIndex or 1) + 1
        if idx > #segments then
            entry.streamSegments = nil
            entry.streamIndex = nil
            entry.streamNextAtUtc = nil
            table.remove(streaming_, i)
            logInfo(string.format("回复 #%d 逐句上屏完成，共 %d 句", entry.id, #segments))
        elseif now >= (entry.streamNextAtUtc or 0) then
            entry.text = entry.text .. segments[idx]
            entry.streamIndex = idx
            entry.streamNextAtUtc = now + SEGMENT_GAP_SECONDS
            version_ = version_ + 1
            logInfo(string.format("回复 #%d 追加第 %d/%d 句", entry.id, idx, #segments))
            EmitPhase(MessageService.PHASE.TYPING)
        end
    end
    -- 句子全部上屏、手上也没有待回消息时才回到空闲相位
    if #streaming_ == 0 and phase_ == MessageService.PHASE.TYPING then
        phase_ = MessageService.PHASE.IDLE
        if hooks_.onPhaseChange then
            hooks_.onPhaseChange(phase_, nil)
        end
    end
end

--- 推进状态机；由 main.lua 每帧调用，utcNow 为权威 UTC 秒（开发自检可注入）
---@param utcNow number
function MessageService.Update(utcNow)
    local now = utcNow
    local head = queue_[1]
    if head then
        head.effReplyAtUtc = EffectiveReplyAt(head, now)

        if now - head.serverTime < SENT_SECONDS then
            EmitPhase(MessageService.PHASE.SENT)
        elseif now >= head.effReplyAtUtc then
            -- 这里不能 return：同一帧可能刚开始逐句上屏，得让它接着往下走一拍
            Deliver()
        else
            local target
            if head.effReplyAtUtc - now <= TYPING_SECONDS then
                target = MessageService.PHASE.TYPING
            elseif head.replyableAtSend then
                target = MessageService.PHASE.WAITING
            else
                target = MessageService.PHASE.QUEUED
            end
            EmitPhase(target)
        end
        SyncQueueStates()
    end
    AdvanceStreaming(now)
end

--- 由 MemoryService 读回的存档重建消息数组与队列（重进不丢记录、不丢排队）
---@param entries MsgEntry[]
---@return integer restored 恢复的待回复条数
function MessageService.Restore(entries)
    messages_ = {}
    queue_ = {}
    nextId_ = 1
    lastPlannedAtUtc_ = 0
    streaming_ = {}
    for i = 1, #entries do
        local entry = entries[i]
        messages_[#messages_ + 1] = entry
        if entry.id >= nextId_ then
            nextId_ = entry.id + 1
        end
        if entry.role == MessageService.ROLE.USER and entry.state ~= "replied" then
            entry.effReplyAtUtc = entry.planReplyAtUtc
            entry.statusText = MessageService.EntryStatusText(entry)
            queue_[#queue_ + 1] = entry
            if (entry.planReplyAtUtc or 0) > lastPlannedAtUtc_ then
                lastPlannedAtUtc_ = entry.planReplyAtUtc or 0
            end
        end
    end
    -- 队列必须按发送时间（等价于 id 升序）排，读回来的顺序不保证可靠
    table.sort(queue_, function(a, b)
        if a.serverTime == b.serverTime then
            return a.id < b.id
        end
        return a.serverTime < b.serverTime
    end)
    version_ = version_ + 1
    phase_ = queue_[1] and queue_[1].state or MessageService.PHASE.IDLE
    logInfo(string.format("存档恢复：%d 条记录，其中 %d 条待回复", #messages_, #queue_))
    return #queue_
end

function MessageService.Reset()
    messages_ = {}
    queue_ = {}
    version_ = 0
    nextId_ = 1
    lastPlannedAtUtc_ = 0
    streaming_ = {}
    phase_ = MessageService.PHASE.IDLE
    draft_ = ""
end

return MessageService
