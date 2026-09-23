-- ============================================================================
-- DevSelfTest.lua — 开发自检（职责单一：用可控 UTC 驱动真实服务并断言时机）
-- 只做一件事：把 MessageService / EventService / ContentService / MemoryService
-- 按真实调用路径跑一遍 busy / offline / idle 三档、FIFO 顺序、落盘重进、
-- 「计划回复时刻在未来就不许提前回复」的反向验证，以及每日事件计划：
--   * 场景 I：固定 01:30 / 14:30 / 19:45 三个当地钟点，断言事件实例 id、occurrenceKey、
--     sceneId、生命周期（upcoming/ongoing/ended）、同日重算的可复现性、下一日期才出新实例；
--   * 场景 J：断言三个钟点的回复出自各自模板分支、排队补回把已结束事件说成「几点收的」，
--     以及落盘重进后计划来自存档（fromSave=true、生成时刻未变）且实例键不变；
--   * 场景 K/L：引用她自己的消息、引用自己更早的消息，引用字段与回指句都要出现；
--   * 场景 M：四类失效引用（id 不在本次会话 / 系统消息 / id 非正整数 / 空内容）
--     一律降级为普通消息——照常发送、不带引用字段、回复里不出回指句；
--   * 场景 N/O：引用跨过忙碌与睡眠两个排队窗口不丢，排队气泡只写「已送达 / 排队」；
--   * 场景 P：多段回复按序追加，一次回复仍然只有一条记录，上屏完成后相位回空闲；
--   * 场景 Q：逐句上屏期间后发消息照常入队，FIFO 与「一对一回复」都不被卡住。
-- 不 mock 任何被测服务，也不依赖被测服务没有的能力：
--   * 时间用 TimeState.DevClockOffset 投影（权威时间源不变，只是把 now 拨到某个当地整点）；
--   * 推进用 MessageService.Update(utcNow) 这个正式入口；
--   * 回复生成、落盘、读档都走 main.lua 挂的那套钩子。
-- 自检用独立存档，绝不碰玩家的聊天记录。任一断言失败都以 logError 落日志，
-- 所以 runtime.log 里 ERROR = 0 就等价于自检全绿。
-- ============================================================================

local TimeState = require("TimeState")
local MessageService = require("services.MessageService")
local ContentService = require("services.ContentService")
local MemoryService = require("services.MemoryService")
local EventService = require("services.EventService")

local DevSelfTest = {}

local TAG = "[DevSelfTest]"
local SELFTEST_SAVE = "memory/m1-selftest-la.json"
local STEP_SECONDS = 1
-- 逐句上屏的段间隔取 MessageService 的公开常量，自检里不再复制一份秒数
local SEGMENT_GAP_SECONDS = MessageService.SEGMENT_GAP_SECONDS

---@class DevSelfTestOptions
---@field cityId string
---@field idleWaitSeconds number
---@field makeSendContext fun(snap: TimeSnapshot, quote?: QuoteRef): SendContext
---@field reinit fun(saveFile: string|nil)

---@type string
local cityId_ = "los_angeles"
---@type number
local idleWait_ = 10
-- 未赋值的函数槽按 AGENTS 规则 #11 标注类型源头，调用点才有推导
---@type fun(snap: TimeSnapshot, quote?: QuoteRef): SendContext
local makeSendContext_
---@type fun(saveFile: string|nil)
local reinit_

---@type integer
local passed_ = 0
---@type integer
local failed_ = 0
---@type string[]
local done_ = {}
--- 判定失败（含整条场景抛出）的场景名，结论行靠它指到该看哪一段断言
---@type string[]
local bad_ = {}
---@type string
local summary_ = "自检未运行"

--- Run 里 runScenario 的调用条数；结论行拿它判断「有没有场景被整批日志丢掉」
local SCENARIO_TOTAL = 17

local function logInfo(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_INFO, TAG .. " " .. msg)
end

local function logError(msg)
    print(TAG .. " ERROR: " .. msg)
    log:Write(LOG_ERROR, TAG .. " " .. msg)
end

---@param label string
---@param ok boolean
---@param detail? string
---@return boolean
local function check(label, ok, detail)
    if ok then
        passed_ = passed_ + 1
        logInfo(string.format("PASS %s %s", label, detail or ""))
    else
        failed_ = failed_ + 1
        logError(string.format("FAIL %s %s", label, detail or ""))
    end
    return ok
end

--- 带状态的字段可能为 nil，比较之前先夹成字符串，避免对 optional 调 :find
---@param entry MsgEntry|nil
---@return string
local function StatusOf(entry)
    if not entry or not entry.statusText then
        return ""
    end
    return entry.statusText
end

---@param text string|nil
---@return string
local function TextOf(text)
    return text or ""
end

--- 把权威时钟投影到「当地某天某时某分」：偏移 = 目标 UTC - 真实 UTC
---@param hour integer
---@param dateKey string
---@param minute? integer
---@return TimeSnapshot
local function goLocalHour(hour, dateKey, minute)
    local target = TimeState.UtcAtLocal(cityId_, dateKey, hour, minute)
    TimeState.DevClockOffset = target - common.get_server_time()
    return TimeState.Snapshot(cityId_, TimeState.NowUtc())
end

--- 走与界面完全同一条入口：上下文由 main.lua 的 MakeSendContext 造，引用意图作为
--- 第二个参数交给它。自检不另开旁路，失效引用的降级才会和真机一致。
---@param text string
---@param quote? QuoteRef
---@return MsgEntry|nil
local function sendNow(text, quote)
    local snap = TimeState.Snapshot(cityId_, TimeState.NowUtc())
    return MessageService.Send(text, snap.utcSec, snap.clock, makeSendContext_(snap, quote))
end

--- 按 STEP_SECONDS 步进推进真实状态机；每一帧都走主循环同一个入口
---@param seconds number
local function advance(seconds)
    local left = seconds
    while left > 0 do
        local step = math.min(STEP_SECONDS, left)
        TimeState.DevClockOffset = TimeState.DevClockOffset + step
        MessageService.Update(TimeState.NowUtc())
        left = left - step
    end
end

---@return MsgEntry|nil
local function head()
    return MessageService.GetHead()
end

---@return integer
local function herReplyCount()
    local msgs = MessageService.GetMessages()
    local n = 0
    for i = 1, #msgs do
        if msgs[i].role == MessageService.ROLE.HER then
            n = n + 1
        end
    end
    return n
end

---@return MsgEntry|nil
local function lastHerReply()
    local msgs = MessageService.GetMessages()
    for i = #msgs, 1, -1 do
        if msgs[i].role == MessageService.ROLE.HER then
            return msgs[i]
        end
    end
    return nil
end

--- 某个数组位置之后出现的所有她的回复（按落库顺序）——用来验 FIFO 交付顺序
---@param fromIndex integer
---@return MsgEntry[]
local function herRepliesAfter(fromIndex)
    local msgs = MessageService.GetMessages()
    ---@type MsgEntry[]
    local out = {}
    for i = fromIndex + 1, #msgs do
        if msgs[i].role == MessageService.ROLE.HER then
            out[#out + 1] = msgs[i]
        end
    end
    return out
end

--- 当前消息数组里排在前面的待回复用户消息 id（恢复顺序要用）
---@return integer[]
local function queuedIds()
    local msgs = MessageService.GetMessages()
    ---@type integer[]
    local out = {}
    for i = 1, #msgs do
        if msgs[i].role == MessageService.ROLE.USER and msgs[i].state ~= "replied" then
            out[#out + 1] = msgs[i].id
        end
    end
    return out
end

--- 每个场景开头都重置一次服务与自检存档。
--- 必须做：场景会把时钟往回拨（同一天先测 20:00 再测 12:00），而 MessageService 的
--- 「后发不得越过先发」水位是绝对 UTC，不清就会把后一个场景的计划时刻顶到前一个场景之后。
local function beginScenario()
    MemoryService.ClearSavedData()
    reinit_(SELFTEST_SAVE)
end

-- ---------------------------------------------------------------------------
-- 场景 A：洛杉矶傍晚（idle）—— M0-1 的固定 10 秒链路不得退化
-- ---------------------------------------------------------------------------
local function ScenarioIdleChain(dateKey)
    logInfo("场景 A 空闲档（洛杉矶傍晚）")
    beginScenario()
    local snap = goLocalHour(20, dateKey)
    check("A0 空闲档可即时回复", snap.availability == "idle" and snap.replyable == true,
        string.format("availability=%s replyable=%s", tostring(snap.availability), tostring(snap.replyable)))

    local msg = sendNow("傍晚的咖啡馆人多吗？")
    check("A1 发送入队", msg ~= nil and MessageService.GetQueueLength() == 1)
    local opens = herReplyCount()
    local planAt = msg and msg.planReplyAtUtc or 0
    check("A2 计划时刻 = 送达 + 演示等待", msg ~= nil
        and (planAt - snap.utcSec) == math.floor(idleWait_),
        string.format("plan=%d sent=%d", planAt, snap.utcSec))

    advance(idleWait_ - 2)
    local waitingHead = head()
    check("A3 到点前不回复", MessageService.GetQueueLength() == 1 and herReplyCount() == opens,
        StatusOf(waitingHead))
    check("A4 相位已进入正在输入", waitingHead ~= nil
        and waitingHead.state == MessageService.PHASE.TYPING, StatusOf(waitingHead))

    advance(3)
    check("A5 到点即回复", MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 1)
    local reply = lastHerReply()
    local replyAt = reply and reply.serverTime or 0
    check("A6 回复带事件事实 id", reply ~= nil and reply.factId ~= nil and reply.factId ~= "",
        reply and tostring(reply.factId) or "")
    check("A7 回复不早于计划时刻", reply ~= nil and replyAt >= planAt,
        string.format("送达=%d 计划=%d 回复=%d", snap.utcSec, planAt, replyAt))
end

-- ---------------------------------------------------------------------------
-- 场景 B：碎片时间档（洛杉矶中午）—— 会回，但更慢、更短
-- ---------------------------------------------------------------------------
local function ScenarioFragments(dateKey)
    logInfo("场景 B 碎片时间档（洛杉矶中午）")
    beginScenario()
    local snap = goLocalHour(12, dateKey)
    check("B0 碎片时间档可即时回复且标记要短", snap.availability == "fragments"
        and snap.replyable == true and snap.brief == true,
        string.format("availability=%s replyable=%s brief=%s",
            tostring(snap.availability), tostring(snap.replyable), tostring(snap.brief)))

    local msg = sendNow("吃午饭了吗？")
    local opens = herReplyCount()
    local planAt = msg and msg.planReplyAtUtc or 0
    check("B1 计划时刻比空闲档晚", msg ~= nil and (planAt - snap.utcSec) > math.floor(idleWait_),
        string.format("等了 %d 秒", planAt - snap.utcSec))

    advance(25)
    local reply = lastHerReply()
    check("B2 碎片档最终有回复", MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 1)
    -- 碎片档走短句池：这句会命中 food 话题，后缀不得出现
    check("B3 碎片档回复是短句、不带话题后缀", TextOf(reply and reply.text):find("手边是一杯冰的") == nil,
        TextOf(reply and reply.text))
end

-- ---------------------------------------------------------------------------
-- 场景 C：忙碌档（洛杉矶下午在工作室）—— 不立即回复，进窗口后带着经历回复
-- ---------------------------------------------------------------------------
local function ScenarioBusy(dateKey)
    logInfo("场景 C 忙碌档（洛杉矶下午）")
    beginScenario()
    local snap = goLocalHour(14, dateKey)
    check("C0 忙碌档不可即时回复", snap.availability == "busy" and snap.replyable == false,
        string.format("availability=%s replyable=%s", tostring(snap.availability), tostring(snap.replyable)))

    local msg = sendNow("下午忙不忙？")
    local opens = herReplyCount()
    local windowStart = msg and msg.planWindowStartUtc or 0
    local planAt = msg and msg.planReplyAtUtc or 0
    local windowSnap = TimeState.Snapshot(cityId_, windowStart)
    check("C1 计划时刻推到 17:00 那个窗口之后", msg ~= nil and windowStart > 0
        and planAt > windowStart and windowSnap.hour == 17,
        string.format("窗口=%s(%s) 计划=%d", windowSnap.clock,
            tostring(windowSnap.availability), planAt))

    advance(30)
    check("C2 忙碌中不回复", MessageService.GetQueueLength() == 1 and herReplyCount() == opens)
    local busyHead = head()
    check("C3 状态标为排队", busyHead ~= nil and busyHead.state == MessageService.PHASE.QUEUED,
        StatusOf(busyHead))
    local queuedStatus = StatusOf(busyHead)
    check("C4 气泡写了已送达但没有任何已读字样",
        queuedStatus:find("已送达") ~= nil and queuedStatus:find("已读") == nil, queuedStatus)

    local at16 = goLocalHour(16, dateKey)
    advance(30)
    check("C5 仍在忙碌窗口内不回复", at16.availability == "busy"
        and MessageService.GetQueueLength() == 1 and herReplyCount() == opens)

    local at17 = goLocalHour(17, dateKey)
    advance(30)
    check("C6 进入可回复窗口后回复", at17.availability == "fragments"
        and MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 1)
    local reply = lastHerReply()
    check("C7 回复引用送达时的作息事实而非捏造", TextOf(reply and reply.text):find("在赶项目") ~= nil,
        TextOf(reply and reply.text))
end

-- ---------------------------------------------------------------------------
-- 场景 D：睡眠档两条消息 FIFO —— 后发不得越过先发，醒来按顺序回
-- ---------------------------------------------------------------------------
local function ScenarioOfflineFifo(dateKey)
    logInfo("场景 D 睡眠档两条消息 FIFO（洛杉矶凌晨）")
    beginScenario()
    local snap = goLocalHour(3, dateKey)
    check("D0 睡眠档不可即时回复", snap.availability == "offline" and snap.replyable == false,
        string.format("availability=%s", tostring(snap.availability)))

    local first = sendNow("睡了吗？")
    local second = sendNow("睡不着也想说一句。")
    local opens = herReplyCount()
    local markIndex = #MessageService.GetMessages()
    check("D1 两条都进了队列", MessageService.GetQueueLength() == 2 and first ~= nil and second ~= nil)
    local firstPlan = first and first.planReplyAtUtc or 0
    local secondPlan = second and second.planReplyAtUtc or 0
    check("D2 后发的计划时刻晚于先发的", secondPlan > firstPlan,
        string.format("first=%d second=%d", firstPlan, secondPlan))

    advance(10)
    local firstStatus = StatusOf(first)
    check("D3 两条都只标排队（谁都没被读过）",
        first ~= nil and first.state == MessageService.PHASE.QUEUED
        and second ~= nil and second.state == MessageService.PHASE.QUEUED
        and firstStatus:find("已读") == nil,
        string.format("first=%s second=%s", StatusOf(first), StatusOf(second)))

    advance(60)
    check("D4 睡眠中一条都不回", MessageService.GetQueueLength() == 2 and herReplyCount() == opens)

    goLocalHour(6, dateKey)
    advance(40)
    local replies = herRepliesAfter(markIndex)
    check("D5 醒来后两条按 FIFO 全部回完", MessageService.GetQueueLength() == 0 and #replies == 2,
        string.format("回复 %d 条，队列剩 %d 条", #replies, MessageService.GetQueueLength()))
    check("D6 回复顺序与发送顺序一致", #replies == 2
        and TextOf(replies[1].text):find("睡了吗", 1, true) ~= nil
        and TextOf(replies[2].text):find("睡不着也想说一句", 1, true) ~= nil,
        string.format("第一条=%s 第二条=%s",
            TextOf(replies[1] and replies[1].text), TextOf(replies[2] and replies[2].text)))

    advance(60)
    check("D7 回完的消息不会重复回复", MessageService.GetQueueLength() == 0
        and herReplyCount() == opens + 2)
end

-- ---------------------------------------------------------------------------
-- 场景 E：落盘 → 重进 → 队列与顺序仍在，到期消息补发且不重复
-- ---------------------------------------------------------------------------
local function ScenarioReentry(dateKey)
    logInfo("场景 E 落盘与重进恢复")
    beginScenario()
    goLocalHour(4, dateKey)
    local first = sendNow("还在睡吗？")
    sendNow("明早想听你说说书店的事。")
    local totalBefore = #MessageService.GetMessages()
    local firstId = first and first.id or 0
    local persisted = MemoryService.Persist(MessageService.GetMessages())
    check("E0 落盘成功", persisted == true, MemoryService.GetSaveFile())

    -- 模拟重进：服务重新初始化（钩子还是 main 挂的那套），再从同一份存档读回来
    reinit_(SELFTEST_SAVE)
    local restored = MessageService.Restore(MemoryService.GetRestoredMessages())
    check("E1 完整历史读回来了", #MessageService.GetMessages() == totalBefore,
        string.format("恢复 %d 条记录", #MessageService.GetMessages()))
    local ids = queuedIds()
    check("E2 两条排队消息按原顺序恢复", restored == 2 and #ids == 2 and ids[1] == firstId,
    string.format("待回复 %d 条 id 顺序=%d,%d", restored, ids[1] or 0, ids[2] or 0))
    local queuedHead = head()
    check("E3 计划回复时刻与送达时可用性一起回来", queuedHead ~= nil
        and queuedHead.planReplyAtUtc ~= nil and queuedHead.availabilityAtSend == "offline",
        string.format("plan=%d avail=%s", queuedHead and queuedHead.planReplyAtUtc or 0,
            tostring(queuedHead and queuedHead.availabilityAtSend)))

    local opens = herReplyCount()
    goLocalHour(6, dateKey)
    advance(45)
    check("E4 离开期间到点的消息按顺序补发完", MessageService.GetQueueLength() == 0
        and herReplyCount() == opens + 2,
        string.format("回复 %d 条，队列剩 %d 条", herReplyCount() - opens, MessageService.GetQueueLength()))

    -- 再重进一次：已经回完的历史不应再生成任何回复。
    -- 必须同时盯「记录条数」：只看 reopened==0 + 回复不增的话，「恢复直接把历史弄丢」
    -- 也会满足这两条（没东西可回当然不重复回），那就成了空过。
    MemoryService.Persist(MessageService.GetMessages())
    local totalSettled = #MessageService.GetMessages()
    reinit_(SELFTEST_SAVE)
    local reopened = MessageService.Restore(MemoryService.GetRestoredMessages())
    local afterReopen = herReplyCount()
    advance(30)
    check("E5 二次重进不重复回复、也没丢记录", reopened == 0 and herReplyCount() == afterReopen
        and #MessageService.GetMessages() == totalSettled,
        string.format("待回复 %d 条 回复增量 %d 记录 %d/%d", reopened, herReplyCount() - afterReopen,
            #MessageService.GetMessages(), totalSettled))
end

-- ---------------------------------------------------------------------------
-- 场景 F：反向验证 —— 同一条时钟下，只把 queued 记录的计划时刻改到未来
-- ---------------------------------------------------------------------------
local function ScenarioFuturePlan(dateKey)
    logInfo("场景 F 反向验证：计划时刻在未来的排队消息不许提前回复")
    beginScenario()
    goLocalHour(4, dateKey)
    local msg = sendNow("这条用来做反向验证。")
    local planAt = msg and msg.planReplyAtUtc or 0
    check("F0 排队消息的计划时刻在未来", planAt > TimeState.NowUtc(),
        string.format("plan=%d now=%d", planAt, math.floor(TimeState.NowUtc())))
    MemoryService.Persist(MessageService.GetMessages())

    reinit_(SELFTEST_SAVE)
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local queued = head()
    local savedPlan = queued and queued.planReplyAtUtc or 0
    -- 把当地拨到窗口之后：真实计划本该在这里立刻补发
    goLocalHour(7, dateKey)
    local opens = herReplyCount()

    -- RED：只改计划时刻，其它一切不动
    if queued then
        queued.planReplyAtUtc = math.floor(TimeState.NowUtc()) + 300
        queued.effReplyAtUtc = queued.planReplyAtUtc
    end
    advance(60)
    check("F1 计划时刻在未来 → 不提前交付（RED）",
        MessageService.GetQueueLength() == 1 and herReplyCount() == opens,
        string.format("队列=%d 回复增量=%d", MessageService.GetQueueLength(), herReplyCount() - opens))

    -- GREEN：把存档里那条真实计划时刻放回去，同一条时钟继续推进
    if queued then
        queued.planReplyAtUtc = savedPlan
        queued.effReplyAtUtc = savedPlan
    end
    advance(15)
    check("F2 恢复真实计划后按序交付（GREEN）",
        MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 1,
        string.format("队列=%d 回复增量=%d 原计划=%d",
            MessageService.GetQueueLength(), herReplyCount() - opens, savedPlan))
end

-- ---------------------------------------------------------------------------
-- 场景 H：「离开期间」摘要的判定闸门（BootChat 用的就是这一个函数）
-- ---------------------------------------------------------------------------
local function ScenarioAwaySummaryRule(dateKey)
    logInfo("场景 H 重进摘要判定")
    beginScenario()

    local gapNew, wantNew = MemoryService.AwayGap(TimeState.NowUtc(), 2, 60)
    check("H0 全新存档没有「上次」可言 → 不补摘要", wantNew == false and gapNew == 0,
        string.format("gap=%d want=%s", gapNew, tostring(wantNew)))

    -- 造一次真实的离开：凌晨发两条（都排队）→ 落盘 → 把时钟推到醒来之后
    goLocalHour(4, dateKey)
    sendNow("离开前想跟你说一句。")
    sendNow("还有这句。")
    MemoryService.Persist(MessageService.GetMessages())

    -- H1 单独验时长阈值：这里显式传 dueCount=2，免得「没到点」替时长规则蒙混过关
    local gapShort, wantShort = MemoryService.AwayGap(TimeState.NowUtc() + 20, 2, 60)
    check("H1 离开不到阈值 → 不补摘要", wantShort == false and gapShort < 60,
        string.format("gap=%d want=%s", gapShort, tostring(wantShort)))

    -- 计划回复时刻是 06:00:10 / 06:00:14，所以要拨到窗口之后再判「有没有到点」
    goLocalHour(7, dateKey)
    local nowLate = TimeState.NowUtc()
    local due = MessageService.GetDueCount(nowLate)
    local gapLong, wantLong, thenUtc = MemoryService.AwayGap(nowLate, due, 60)
    check("H2 离开够久且有到点待补发 → 补一条", wantLong == true and due == 2 and gapLong >= 10700,
        string.format("gap=%d due=%d want=%s", gapLong, due, tostring(wantLong)))
    local gapNoDue, wantNoDue = MemoryService.AwayGap(nowLate, 0, 60)
    check("H3 没有到点消息 → 不补摘要", wantNoDue == false and gapNoDue == 0,
        string.format("gap=%d want=%s", gapNoDue, tostring(wantNoDue)))

    -- 真的把这条摘要写进消息流（和 BootChat 同一组调用），再补发完、重进一次
    local thenSnap = TimeState.Snapshot(cityId_, thenUtc)
    local nowSnap = TimeState.Snapshot(cityId_, nowLate)
    MessageService.AddSystem(
        ContentService.AwaySummary(gapLong, thenSnap.phrase, nowSnap.phrase, due),
        math.floor(nowLate), nowSnap.clock)
    advance(45)
    reinit_(SELFTEST_SAVE)
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local nowReopen = TimeState.NowUtc()
    local gapAgain, wantAgain = MemoryService.AwayGap(nowReopen,
        MessageService.GetDueCount(nowReopen), 60)
    check("H4 补发完再重进 → 不再补第二条（防流水账）", wantAgain == false,
        string.format("gap=%d want=%s 队列=%d", gapAgain, tostring(wantAgain), MessageService.GetQueueLength()))
end

-- ---------------------------------------------------------------------------
-- 场景 G：离线摘要契约 —— 只给一条，且不许出现流水账
-- ---------------------------------------------------------------------------
local function ScenarioAwaySummary()
    logInfo("场景 G 离开期间摘要")
    local line = ContentService.AwaySummary(5 * 3600 + 12 * 60, "在赶项目", "还在外面", 3)
    check("G1 摘要只有一行", line:find("\n") == nil, line)
    check("G2 摘要含客观间隔与两头作息", line:find("5 小时 12 分") ~= nil
        and line:find("在赶项目") ~= nil and line:find("还在外面") ~= nil, line)
    check("G3 摘要没有逐小时流水", line:find("在上课") == nil and line:find("在路上") == nil, line)
end

-- ---------------------------------------------------------------------------
-- 场景 I：三个固定当地钟点 —— 事件实例、场景绑定、回复分支必须出自同一份计划
-- 01:30 / 14:30 / 19:45 就是左上开发测试台的那三个按钮，这里按同一组时刻断言。
-- ---------------------------------------------------------------------------

---@param plan EventPlan
---@return string
local function KeysOf(plan)
    local parts = {}
    for i = 1, #plan.occurrences do
        parts[#parts + 1] = string.format("%s#%d", plan.occurrences[i].occurrenceKey,
            plan.occurrences[i].variantIndex)
    end
    return table.concat(parts, ",")
end

local function ScenarioEventPlan(dateKey)
    logInfo("场景 I 每日事件计划（01:30 / 14:30 / 19:45）")
    beginScenario()

    local plan = EventService.PlanFor(cityId_, dateKey)
    local rows = TimeState.SCHEDULE
    check("I0 计划逐行覆盖作息表，不多不少", #plan.occurrences == #rows,
        string.format("事件 %d 个 / 作息 %d 档", #plan.occurrences, #rows))
    local contiguous = true
    local samePlace = true
    for i = 2, #plan.occurrences do
        if plan.occurrences[i].startUtc ~= plan.occurrences[i - 1].endUtc then
            contiguous = false
        end
    end
    for i = 1, #rows do
        if plan.occurrences[i].place ~= rows[i].place then
            samePlace = false
        end
    end
    check("I1 事件窗口首尾相接，不漏一小时也不重叠", contiguous,
        string.format("首=%d 末=%d", plan.occurrences[1].startUtc,
            plan.occurrences[#plan.occurrences].endUtc))
    -- 这条就是「不另造平行真相源」的机械证明：事件说她在哪儿，作息表必须说同一处
    check("I1b 每个事件实例的地点与作息表同一档声明的地点一致", samePlace,
        string.format("计划 %d 条 vs 作息 %d 档", #plan.occurrences, #rows))

    -- 01:30：凌晨休息档（睡眠），场景必须是公寓静帧
    local at0130 = goLocalHour(1, dateKey, 30)
    local fact0130 = EventService.FactFor(cityId_, at0130.utcSec)
    check("I2 01:30 命中凌晨休息实例·ongoing·公寓",
        fact0130.id == "la_apartment_night_rest" and fact0130.eventState == "ongoing"
        and fact0130.sceneId == "la_apartment" and at0130.availability == "offline",
        string.format("id=%s state=%s scene=%s avail=%s", fact0130.id, fact0130.eventState,
            fact0130.sceneId, tostring(at0130.availability)))
    check("I3 01:30 的 occurrenceKey 由城市/日期/模板组成",
        fact0130.occurrenceKey == string.format("%s/%s/la_apartment_night_rest", cityId_, dateKey),
        fact0130.occurrenceKey)
    check("I4 事件实例带 UTC 起止、标题、摘要、情绪",
        fact0130.eventStartUtc < fact0130.eventEndUtc and fact0130.eventTitle ~= ""
        and fact0130.eventSummary ~= "" and fact0130.eventEmotion ~= "",
        string.format("%s—%s %s", fact0130.eventStartsAt, fact0130.eventEndsAt, fact0130.eventEmotion))

    -- 14:30：工作室校样正在发生；清晨的整理已经收了，晚间开放麦还没开始
    local at1430 = goLocalHour(14, dateKey, 30)
    local fact1430 = EventService.FactFor(cityId_, at1430.utcSec)
    local q1430 = EventService.QueryAt(cityId_, at1430.utcSec)
    check("I5 14:30 命中工作室校样·ongoing·工作室",
        fact1430.id == "la_studio_zine_layout" and fact1430.eventState == "ongoing"
        and fact1430.sceneId == "la_studio" and at1430.availability == "busy",
        string.format("id=%s state=%s scene=%s", fact1430.id, fact1430.eventState, fact1430.sceneId))
    check("I6 14:30 时清晨事件为 ended、晚间事件为 upcoming",
        q1430.allStates.la_apartment_morning_inbox == "ended"
        and q1430.allStates.la_cafe_open_mic == "upcoming",
        string.format("morning=%s openmic=%s", tostring(q1430.allStates.la_apartment_morning_inbox),
            tostring(q1430.allStates.la_cafe_open_mic)))

    -- 19:45：咖啡馆开放麦正在发生；工作室校样已经收了
    local at1945 = goLocalHour(19, dateKey, 45)
    local fact1945 = EventService.FactFor(cityId_, at1945.utcSec)
    local q1945 = EventService.QueryAt(cityId_, at1945.utcSec)
    check("I7 19:45 命中咖啡馆开放麦·ongoing·咖啡馆",
        fact1945.id == "la_cafe_open_mic" and fact1945.eventState == "ongoing"
        and fact1945.sceneId == "la_cafe" and at1945.availability == "idle",
        string.format("id=%s state=%s scene=%s", fact1945.id, fact1945.eventState, fact1945.sceneId))
    check("I8 19:45 时工作室事件已 ended、夜间复盘 upcoming",
        q1945.allStates.la_studio_zine_layout == "ended"
        and q1945.allStates.la_apartment_wind_down == "upcoming",
        string.format("studio=%s winddown=%s", tostring(q1945.allStates.la_studio_zine_layout),
            tostring(q1945.allStates.la_apartment_wind_down)))

    -- 三个钟点必须给出三个不同的事件实例，否则「切换时间什么都不变」也算通过就是空过
    check("I9 三个钟点得到三个互不相同的事件实例",
        fact0130.occurrenceKey ~= fact1430.occurrenceKey
        and fact1430.occurrenceKey ~= fact1945.occurrenceKey
        and fact0130.occurrenceKey ~= fact1945.occurrenceKey,
        string.format("%s | %s | %s", fact0130.occurrenceKey, fact1430.occurrenceKey,
            fact1945.occurrenceKey))

    -- 可复现性：丢掉缓存按同一规则重算，实例键与变体下标必须一字不差
    local keysBefore = KeysOf(plan)
    local rebuilt = EventService.Regenerate(cityId_, dateKey)
    check("I10 同日同城重算得到同一批实例（定种而非随机）",
        KeysOf(rebuilt) == keysBefore, keysBefore)
    -- 下一本地日期才产生新实例
    local nextDay = TimeState.ShiftDateKey(dateKey, 1)
    local nextPlan = EventService.PlanFor(cityId_, nextDay)
    check("I11 下一本地日期才产生新实例", nextPlan.occurrences[1].occurrenceKey
        ~= plan.occurrences[1].occurrenceKey
        and nextPlan.occurrences[1].templateId == plan.occurrences[1].templateId,
        string.format("%s → %s", nextPlan.occurrences[1].occurrenceKey, plan.occurrences[1].occurrenceKey))
end

-- ---------------------------------------------------------------------------
-- 场景 J：三个钟点的回复分支与落盘重进 —— 引用的是同一个事件实例
-- ---------------------------------------------------------------------------
local function ScenarioEventReentry(dateKey)
    logInfo("场景 J 事件实例的回复分支与重进一致性")
    beginScenario()

    -- 19:45 空闲：回复走开放麦那一组文案，并带上送达瞬间的实例键
    goLocalHour(19, dateKey, 45)
    local fact1945 = EventService.FactFor(cityId_, TimeState.NowUtc())
    local sentKey1945 = fact1945.occurrenceKey
    sendNow("今晚店里人多吗？")
    local opens1945 = herReplyCount()
    advance(idleWait_ + 2)
    local reply1945 = lastHerReply()
    local text1945 = TextOf(reply1945 and reply1945.text)
    check("J0 19:45 的回复引用同一个事件实例键，且确实只多出一条",
        reply1945 ~= nil and herReplyCount() == opens1945 + 1
        and reply1945.factKey == sentKey1945 and reply1945.factId == "la_cafe_open_mic",
        string.format("key=%s fact=%s 回复增量=%d 队列=%d", tostring(reply1945 and reply1945.factKey),
            tostring(reply1945 and reply1945.factId), herReplyCount() - opens1945,
            MessageService.GetQueueLength()))
    -- 精确断言：回复里必须出现「19:45 那个实例的原话」。
    -- 不用「A 或 B 或 C」的措辞或匹配 —— 空回复、错模板都可能蹭过那种写法。
    check("J1 19:45 回复用了开放麦实例自己的事实句",
        fact1945.eventPhrase ~= "" and text1945:find(fact1945.eventPhrase, 1, true) ~= nil,
        string.format("期望含=%s 实际=%s", fact1945.eventPhrase, text1945))
    check("J1b 19:45 回复没有串到别的事件文案池",
        text1945:find("边距") == nil and text1945:find("水刚烧开") == nil
        and text1945:find("便签") == nil, text1945)

    -- 睡眠档发消息 → 清晨醒来补回：凌晨那件事必须说成「已经收了」，不能仍是正在进行
    beginScenario()
    goLocalHour(1, dateKey, 30)
    local nightFact = EventService.FactFor(cityId_, TimeState.NowUtc())
    local nightMsg = sendNow("睡了吗，随便说一句。")
    MemoryService.Persist(MessageService.GetMessages())
    local nightPlan = EventService.PeekPlan(cityId_, dateKey)
    local nightGeneratedAt = nightPlan and nightPlan.generatedAtUtc or 0
    local sentNightKey = nightMsg and nightMsg.factKey or ""
    check("J2 凌晨发的消息带上凌晨那个实例键", sentNightKey ~= ""
        and sentNightKey == nightFact.occurrenceKey
        and sentNightKey == string.format("%s/%s/la_apartment_night_rest", cityId_, dateKey),
        string.format("key=%s 期望=%s", sentNightKey, nightFact.occurrenceKey))

    -- 模拟重进：服务全部重建，计划必须从存档接管而不是重算
    reinit_(SELFTEST_SAVE)
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local restoredPlan = EventService.PeekPlan(cityId_, dateKey)
    check("J3 重进后计划来自存档、生成时刻未变（没有重新生成同日事件）",
        restoredPlan ~= nil and restoredPlan.fromSave == true
        and restoredPlan.generatedAtUtc == nightGeneratedAt and nightGeneratedAt > 0,
        string.format("fromSave=%s 生成时刻 %d→%d", tostring(restoredPlan and restoredPlan.fromSave),
            nightGeneratedAt, restoredPlan and restoredPlan.generatedAtUtc or 0))
    local headMsg = head()
    check("J4 重进后排队消息仍引用同一实例键", headMsg ~= nil and headMsg.factKey == sentNightKey,
        string.format("key=%s", tostring(headMsg and headMsg.factKey)))

    local opens = herReplyCount()
    goLocalHour(6, dateKey, 5)
    advance(30)
    local morningReply = lastHerReply()
    local morningText = TextOf(morningReply and morningReply.text)
    -- 结束钟点从实例自己带上，不写死：改作息表时这条断言会跟着走，而不是留下过期的硬编码
    local endedMark = "到" .. nightFact.eventEndsAt .. "就收了"
    local morningFact = EventService.FactFor(cityId_, TimeState.NowUtc())
    check("J5 醒来补回点名凌晨那件事、并报它几点收的",
        morningText:find(endedMark, 1, true) ~= nil
        and morningText:find(nightFact.eventTitle, 1, true) ~= nil,
        string.format("期望含「%s · %s」实际=%s", nightFact.eventTitle, endedMark, morningText))
    check("J6 补回不把已结束的那件事讲成还在进行",
        nightFact.eventPhrase ~= "" and morningText:find(nightFact.eventPhrase, 1, true) == nil,
        string.format("不该含=%s 实际=%s", nightFact.eventPhrase, morningText))
    check("J7 补回的回复落在清晨实例上、用清晨自己的事实句", MessageService.GetQueueLength() == 0
        and herReplyCount() == opens + 1
        and morningReply ~= nil and morningReply.factId == "la_apartment_morning_inbox"
        and morningText:find(morningFact.eventPhrase, 1, true) ~= nil,
        string.format("fact=%s 期望含=%s 队列=%d", tostring(morningReply and morningReply.factId),
            morningFact.eventPhrase, MessageService.GetQueueLength()))
    -- 账本记的是「已经进入会话的 occurrence」：补回那一刻回复所引用的清晨实例
    local morningKey = morningReply and morningReply.factKey or ""
    local ledger = MemoryService.FindLedgerEntry(morningKey)
    check("J8 事件账本记下了回复所引用的实例（含 UTC 起止）",
        ledger ~= nil and ledger.key == string.format("%s/%s/la_apartment_morning_inbox", cityId_, dateKey)
        and ledger.startUtc < ledger.endUtc and ledger.lastServerTime > 0,
        string.format("key=%s start=%d end=%d", morningKey,
            ledger and ledger.startUtc or 0, ledger and ledger.endUtc or 0))

    -- 忙碌档 → 17:00 窗口补回：下午校样那件事同样要报「收了」，且回复落在补回那一刻的实例上
    beginScenario()
    goLocalHour(14, dateKey, 30)
    local studioFact = EventService.FactFor(cityId_, TimeState.NowUtc())
    sendNow("下午忙不忙？")
    local opensBusy = herReplyCount()
    goLocalHour(17, dateKey, 5)
    advance(30)
    local busyReply = lastHerReply()
    local busyText = TextOf(busyReply and busyReply.text)
    local studioEndedMark = "到" .. studioFact.eventEndsAt .. "就收了"
    local commuteFact = EventService.FactFor(cityId_, TimeState.NowUtc())
    check("J9 14:30 的消息在 17:05 补回时点名工作室事件已收",
        MessageService.GetQueueLength() == 0 and herReplyCount() == opensBusy + 1
        and busyText:find(studioEndedMark, 1, true) ~= nil
        and busyText:find(studioFact.eventTitle, 1, true) ~= nil,
        string.format("期望含「%s · %s」实际=%s", studioFact.eventTitle, studioEndedMark, busyText))
    check("J9b 补回落在路上那一档的实例上，并带它的 UTC 边界",
        busyReply ~= nil and busyReply.factId == "la_commute_voice_notes"
        and busyText:find(commuteFact.eventPhrase, 1, true) ~= nil
        and commuteFact.eventEndUtc - commuteFact.eventStartUtc == 2 * 3600,
        string.format("fact=%s 窗口=%d—%d 期望含=%s", tostring(busyReply and busyReply.factId),
            commuteFact.eventStartUtc, commuteFact.eventEndUtc, commuteFact.eventPhrase))
end

-- ---------------------------------------------------------------------------
-- 场景 K：引用她自己的消息 —— 回指句必须出现在回复里，且不许替被引用内容编事实
-- 注意原文选得比「主干句回显」的 12 字裁剪线长：这样主干里那句「用户原文回显」
-- 必然被裁成「…」，只有回指句能带上完整预览，两条断言不会互相冒充。
-- ---------------------------------------------------------------------------
local function ScenarioQuoteHer(dateKey)
    logInfo("场景 K 引用若夕的消息（空闲档）")
    beginScenario()
    goLocalHour(19, dateKey, 45)

    sendNow("今晚店里人多吗？")
    local opens = herReplyCount()
    advance(idleWait_ + 20)
    local first = lastHerReply()
    check("K0 先有一条她的回复可引", first ~= nil and herReplyCount() == opens + 1,
        TextOf(first and first.text))
    local preview = first and ContentService.ClipPreview(first.text, 24) or ""
    check("K1 预览按字符数裁过且没有变长", first ~= nil and preview ~= ""
        and #preview <= #TextOf(first.text),
        string.format("预览 %d 字 / 原文 %d 字", #preview, #TextOf(first and first.text)))

    local quoted = sendNow("嗯。", { id = first.id, role = "her", text = first.text })
    check("K2 引用字段落在新消息上且内容以查到的为准", quoted ~= nil
        and quoted.quotedMessageId == first.id and quoted.quotedRole == MessageService.ROLE.HER
        and quoted.quotedTextPreview == preview,
        string.format("id=%s role=%s 预览 %d 字", tostring(quoted and quoted.quotedMessageId),
            tostring(quoted and quoted.quotedRole), #TextOf(quoted and quoted.quotedTextPreview)))

    advance(idleWait_ + 20)
    local reply = lastHerReply()
    local text = TextOf(reply and reply.text)
    check("K3 回复里带上被引用那句的完整预览", preview ~= "" and text:find(preview, 1, true) ~= nil,
        string.format("期望含=%s 实际=%s", preview, text))
    check("K4 回指句只认下那句话，不做事实断言",
        text:find("我看见了") ~= nil or text:find("这句我记下了") ~= nil, text)
end

-- ---------------------------------------------------------------------------
-- 场景 L：引用自己更早发的一句 —— 引用不得影响入队与 FIFO
-- ---------------------------------------------------------------------------
local function ScenarioQuoteSelf(dateKey)
    logInfo("场景 L 引用自己的消息（空闲档）")
    beginScenario()
    goLocalHour(19, dateKey, 45)

    local first = sendNow("今晚店里人多吗？")
    local preview = first and ContentService.ClipPreview(first.text, 24) or ""
    check("L0 第一条已发出并入队", first ~= nil and MessageService.GetQueueLength() == 1,
        TextOf(first and first.text))

    local second = sendNow("对了还有一句。", { id = first.id, role = "user", text = first.text })
    check("L1 引用自己那条也成立", second ~= nil and second.quotedMessageId == first.id
        and second.quotedRole == MessageService.ROLE.USER and second.quotedTextPreview == preview,
        string.format("id=%s role=%s 预览 %d 字", tostring(second and second.quotedMessageId),
            tostring(second and second.quotedRole), #TextOf(second and second.quotedTextPreview)))
    check("L2 两条都在队列里，引用不影响入队", MessageService.GetQueueLength() == 2)

    local markIndex = #MessageService.GetMessages()
    advance(idleWait_ * 2 + 20)
    local replies = herRepliesAfter(markIndex)
    check("L3 两条都回了，顺序与发送一致", MessageService.GetQueueLength() == 0 and #replies == 2,
        string.format("回复 %d 条 队列 %d 条", #replies, MessageService.GetQueueLength()))
    check("L4 第二条的回复里带着被引用那句", preview ~= ""
        and TextOf(replies[2] and replies[2].text):find(preview, 1, true) ~= nil,
        TextOf(replies[2] and replies[2].text))
end

-- ---------------------------------------------------------------------------
-- 场景 M：失效引用一律降级为普通消息 —— 照常发送、不带引用字段、回复不出回指句
-- 覆盖四类真实现场：id 不在本次会话（重进后旧 id）、引用系统消息、id 不是正整数、
-- 以及只有脏存档才造得出的空内容记录。
-- ---------------------------------------------------------------------------
local function ScenarioInvalidQuote(dateKey)
    logInfo("场景 M 失效引用一律降级为普通消息")
    beginScenario()
    goLocalHour(19, dateKey, 45)

    local sys = MessageService.AddSystem("系统消息不能被引用",
        math.floor(TimeState.NowUtc()), TimeState.Snapshot(cityId_, TimeState.NowUtc()).clock)
    ---@type { id: any, role: string, text: string }[]
    local badQuotes = {
        { id = 999999, role = "user", text = "不在本次会话里" },
        { id = sys.id, role = "user", text = "系统消息" },
        { id = 0, role = "user", text = "零" },
        { id = -5, role = "user", text = "负数" },
        { id = 1.5, role = "user", text = "非整数" },
        { id = "1", role = "user", text = "字符串 id" },
    }
    for i = 1, #badQuotes do
        local msg = sendNow(string.format("失效引用第 %d 条。", i), badQuotes[i])
        check(string.format("M%d 失效引用仍照常发送且不带引用字段（%s）", i - 1, badQuotes[i].text),
            msg ~= nil and msg.quotedMessageId == nil and msg.quotedRole == nil
            and msg.quotedTextPreview == nil,
            string.format("quotedMessageId=%s", tostring(msg and msg.quotedMessageId)))
    end
    check("M6 六条全部入队，没有一条被拒绝",
        MessageService.GetQueueLength() == #badQuotes,
        string.format("队列 %d 条", MessageService.GetQueueLength()))

    -- 空内容：正常入口发不出空消息，只有脏存档里才会有这种 user/her 记录。
    -- 用 Restore 造一条 state=replied 的，它不进队列，不影响上面的时序判定。
    beginScenario()
    goLocalHour(19, dateKey, 45)
    local blankAt = math.floor(TimeState.NowUtc())
    MessageService.Restore({
        { id = 9001, role = "user", text = "   ", serverTime = blankAt,
          state = "replied", statusText = "", clockText = "" },
    })
    local blank = sendNow("这条引用一条空内容。", { id = 9001, role = "user", text = "   " })
    check("M7 引用空内容同样降级", blank ~= nil and blank.quotedMessageId == nil,
        string.format("quotedMessageId=%s", tostring(blank and blank.quotedMessageId)))

    advance(idleWait_ + 20)
    local text = TextOf(lastHerReply() and lastHerReply().text)
    check("M8 降级后的回复里没有回指句", text:find("我看见了") == nil
        and text:find("这句我记下了") == nil, text)
end

-- ---------------------------------------------------------------------------
-- 场景 N：忙碌排队中的引用 —— 排队不丢引用，状态只写「已送达 / 排队」，绝不写「已读」
-- 回复要落在空闲档：碎片档走短句池、不带回指句，所以补回时把钟拨到 19:45。
-- ---------------------------------------------------------------------------
local function ScenarioQuoteBusyQueue(dateKey)
    logInfo("场景 N 忙碌排队中的引用与状态文案")
    beginScenario()
    local snap = goLocalHour(14, dateKey, 30)
    check("N0 忙碌档不可即时回复", snap.availability == "busy" and snap.replyable == false,
        string.format("availability=%s replyable=%s",
            tostring(snap.availability), tostring(snap.replyable)))

    local first = sendNow("下午在忙什么？")
    local preview = first and ContentService.ClipPreview(first.text, 24) or ""
    local queued = sendNow("那先排队吧。", { id = first.id, role = "user", text = first.text })
    check("N1 忙碌中两条都排队且引用不丢", MessageService.GetQueueLength() == 2
        and queued ~= nil and queued.quotedMessageId == first.id
        and queued.quotedTextPreview == preview,
        string.format("队列 %d 条 quoted=%s", MessageService.GetQueueLength(),
            tostring(queued and queued.quotedMessageId)))

    advance(30)
    local status = StatusOf(head())
    check("N2 忙碌排队只写已送达与排队，绝不写已读",
        status:find("已送达") ~= nil and status:find("已读") == nil, status)

    local markIndex = #MessageService.GetMessages()
    goLocalHour(19, dateKey, 45)
    advance(idleWait_ + 40)
    local replies = herRepliesAfter(markIndex)
    check("N3 空闲档按 FIFO 补回两条", MessageService.GetQueueLength() == 0 and #replies == 2,
        string.format("回复 %d 条 队列 %d 条", #replies, MessageService.GetQueueLength()))
    check("N4 补回的回复里带上被引用那句", preview ~= ""
        and TextOf(replies[2] and replies[2].text):find(preview, 1, true) ~= nil,
        TextOf(replies[2] and replies[2].text))
end

-- ---------------------------------------------------------------------------
-- 场景 O：睡眠排队中的引用 —— 跨过整个睡眠窗口，引用与 FIFO 都不许丢
-- ---------------------------------------------------------------------------
local function ScenarioQuoteSleepQueue(dateKey)
    logInfo("场景 O 睡眠排队中的引用与 FIFO")
    beginScenario()
    local snap = goLocalHour(3, dateKey)
    check("O0 睡眠档不可即时回复", snap.availability == "offline" and snap.replyable == false,
        string.format("availability=%s replyable=%s",
            tostring(snap.availability), tostring(snap.replyable)))

    local first = sendNow("睡了吗？")
    local preview = first and ContentService.ClipPreview(first.text, 24) or ""
    local second = sendNow("那我也排着。", { id = first.id, role = "user", text = first.text })
    check("O1 睡眠中两条都排队且引用不丢", MessageService.GetQueueLength() == 2
        and second ~= nil and second.quotedMessageId == first.id
        and second.quotedTextPreview == preview,
        string.format("队列 %d 条 quoted=%s", MessageService.GetQueueLength(),
            tostring(second and second.quotedMessageId)))

    advance(60)
    local status = StatusOf(head())
    check("O2 睡眠排队只写已送达与排队，绝不写已读",
        status:find("已送达") ~= nil and status:find("已读") == nil, status)

    local markIndex = #MessageService.GetMessages()
    goLocalHour(7, dateKey)
    advance(90)
    local replies = herRepliesAfter(markIndex)
    check("O3 醒来后按 FIFO 补回两条", MessageService.GetQueueLength() == 0 and #replies == 2,
        string.format("回复 %d 条 队列 %d 条", #replies, MessageService.GetQueueLength()))
    check("O4 两条回复的顺序与发送顺序一致", #replies == 2
        and TextOf(replies[1] and replies[1].text):find("睡了吗", 1, true) ~= nil
        and TextOf(replies[2] and replies[2].text):find("那我也排着", 1, true) ~= nil,
        string.format("一=%s 二=%s", TextOf(replies[1] and replies[1].text),
            TextOf(replies[2] and replies[2].text)))
    check("O5 第二条的回复仍带着被引用那句", preview ~= ""
        and TextOf(replies[2] and replies[2].text):find(preview, 1, true) ~= nil,
        TextOf(replies[2] and replies[2].text))
end

-- ---------------------------------------------------------------------------
-- 场景 P：逐句上屏的顺序 —— 一次回复仍然只有一条记录，句子按序追加、可中途停在半句
-- 不断言每句的绝对文本，只断「新文本以旧文本开头」+「长度严格变长」：
-- 这样既证明了追加顺序，又不把 ContentService 的分句规则焊死在自检里。
-- ---------------------------------------------------------------------------
local function ScenarioSegmentOrder(dateKey)
    logInfo("场景 P 多段回复逐句上屏的顺序")
    beginScenario()
    goLocalHour(19, dateKey, 45)

    sendNow("今晚店里天气怎么样？")
    local opens = herReplyCount()
    advance(idleWait_)
    local reply = lastHerReply()
    check("P0 到点先上屏第一句，且仍只有一条回复记录",
        MessageService.GetQueueLength() == 0 and reply ~= nil and herReplyCount() == opens + 1,
        TextOf(reply and reply.text))
    local firstText = TextOf(reply and reply.text)
    local segmentCount = #(reply and reply.streamSegments or {})
    check("P1 这条回复被判成多段", reply ~= nil and segmentCount >= 2,
        string.format("共 %d 句", segmentCount))

    advance(1)
    local stillFirst = TextOf(lastHerReply() and lastHerReply().text)
    check("P2 段间隔内不追加", stillFirst == firstText, string.format("%d 字不变", #stillFirst))

    advance(SEGMENT_GAP_SECONDS + 1)
    local grown = TextOf(lastHerReply() and lastHerReply().text)
    check("P3 间隔之后追加下一句", #grown > #firstText and grown:sub(1, #firstText) == firstText,
        string.format("%d 字 → %d 字", #firstText, #grown))

    advance(SEGMENT_GAP_SECONDS * segmentCount + 10)
    local done = lastHerReply()
    local finalText = TextOf(done and done.text)
    check("P4 全部上屏后仍只有一条记录", herReplyCount() == opens + 1,
        string.format("回复 %d 条 共 %d 字", herReplyCount() - opens, #finalText))
    check("P5 追加只往后长，不会改写前面", finalText:sub(1, #firstText) == firstText,
        string.format("末段 %d 字", #finalText))
    check("P6 上屏完成后清掉逐句状态并回到空闲相位",
        done ~= nil and done.streamSegments == nil and done.streamIndex == nil
        and MessageService.GetPhase() == MessageService.PHASE.IDLE,
        string.format("segments=%s index=%s 相位=%s",
            tostring(done and done.streamSegments), tostring(done and done.streamIndex),
            tostring(MessageService.GetPhase())))
end

-- ---------------------------------------------------------------------------
-- 场景 Q：FIFO 与逐句上屏共存 —— 逐句不得卡住队列，后发不得越序，回复仍是一对一
-- ---------------------------------------------------------------------------
local function ScenarioStreamingFifo(dateKey)
    logInfo("场景 Q 逐句上屏期间 FIFO 不被卡住")
    beginScenario()
    goLocalHour(19, dateKey, 45)
    local markIndex = #MessageService.GetMessages()

    sendNow("今晚店里天气怎么样？")
    local opens = herReplyCount()
    advance(idleWait_)
    local firstReply = lastHerReply()
    check("Q0 第一条已开始逐句上屏", firstReply ~= nil
        and firstReply.streamSegments ~= nil and MessageService.GetQueueLength() == 0,
        TextOf(firstReply and firstReply.text))
    local firstLen = #TextOf(firstReply and firstReply.text)

    -- 趁着第一句还在逐句上屏，立刻再发一条：它必须进队，相位不能被逐句吞掉
    local second = sendNow("还想问一句。")
    check("Q1 逐句进行中后发消息照常入队", second ~= nil
        and MessageService.GetQueueLength() == 1 and second.state == MessageService.PHASE.SENT,
        StatusOf(second))
    check("Q2 逐句进行中相位是 sent，不是 typing",
        MessageService.GetPhase() == MessageService.PHASE.SENT, MessageService.GetPhase())

    advance(idleWait_ * 2 + 60)
    local replies = herRepliesAfter(markIndex)
    check("Q3 两条都回完且队列放空", MessageService.GetQueueLength() == 0
        and herReplyCount() == opens + 2,
        string.format("回复 %d 条 队列 %d 条", herReplyCount() - opens,
            MessageService.GetQueueLength()))
    check("Q4 逐句没有把队列卡死，两条回复都完整落库", #replies == 2
        and TextOf(replies[1] and replies[1].text):find("今晚店里天气怎么样", 1, true) ~= nil
        and TextOf(replies[2] and replies[2].text):find("还想问一句", 1, true) ~= nil,
        string.format("一=%s 二=%s", TextOf(replies[1] and replies[1].text),
            TextOf(replies[2] and replies[2].text)))
    -- 关键回归：第一条还剩几句没上屏时第二条就到点交付，先上屏的那条不能把剩下的句子丢掉
    check("Q5 第一条被中途打断的逐句仍然补完了", firstLen > 0
        and #TextOf(replies[1] and replies[1].text) > firstLen
        and replies[1] ~= nil and replies[1].streamSegments == nil,
        string.format("%d 字 → %d 字", firstLen, #TextOf(replies[1] and replies[1].text)))
    check("Q6 逐句状态在上屏完成后清空",
        lastHerReply() ~= nil and lastHerReply().streamSegments == nil
        and MessageService.GetPhase() == MessageService.PHASE.IDLE,
        tostring(MessageService.GetPhase()))
end

--- 一个场景独立跑完再进下一个，并落一行「本场景判定几条」。
--- 2026-09-22 云端实测：开机那一瞬的突发日志会被管道整批丢掉（suite 只剩 PASS A0…A6，
--- 同批的 开场事件 / M1 已就绪 一起缺席），而调用点本来就有 pcall，所以不是断言抛出吞掉后续场景。
--- 没有这行收尾，日志被截到一半时分不清「这条场景没过」还是「整批没上来」。
---@param name string
---@param fn fun(dateKey: string): any
---@param dateKey string
local function runScenario(name, fn, dateKey)
    local before = passed_ + failed_
    local failedBefore = failed_
    local ok, err = pcall(fn, dateKey)
    if not ok then
        failed_ = failed_ + 1
        logError(string.format("场景 %s 抛出，该场景剩余断言未执行：%s", name, tostring(err)))
    end
    done_[#done_ + 1] = name
    local scenarioFailed = failed_ - failedBefore
    if scenarioFailed > 0 then
        bad_[#bad_ + 1] = string.format("%s×%d", name, scenarioFailed)
    end
    logInfo(string.format("场景 %s 结束：本场景判定 %d 条（累计 通过=%d 失败=%d）",
        name, passed_ + failed_ - before, passed_, failed_))
end

--- 一行式结论。开机那批突发会被日志管道整批丢掉（2026-09-22 实测），
--- 所以结论必须能被 main.lua 在之后的抓取窗口里原样重发。
---@return string
function DevSelfTest.Summary()
    return summary_
end

--- 屏上面板用的紧凑计数（面板那行 nowrap，长结论会被裁掉）。
---@return integer passed
---@return integer failed
---@return integer done
---@return integer total
function DevSelfTest.Result()
    return passed_, failed_, #done_, SCENARIO_TOTAL
end

--- 哪几条场景没过（`I×1` = 场景 I 有 1 条判定失败）。日志被截断时，
--- 结论行只能告诉我有失败，这个告诉该去翻哪一段断言。
---@return string
function DevSelfTest.BadScenarios()
    return table.concat(bad_, " ")
end

--- 跑一次完整自检。调用前 main.lua 已经用自检存档 InitServices 过一遍。
---@param options DevSelfTestOptions
---@return boolean allPassed
function DevSelfTest.Run(options)
    cityId_ = options.cityId
    idleWait_ = options.idleWaitSeconds
    makeSendContext_ = options.makeSendContext
    reinit_ = options.reinit
    passed_ = 0
    failed_ = 0
    done_ = {}
    bad_ = {}
    summary_ = "自检未产出结论"

    local cleared = MemoryService.ClearSavedData()
    local baseSnap = TimeState.Snapshot(cityId_, TimeState.NowUtc())
    logInfo(string.format("自检开始：独立存档 %s（清空=%s），洛杉矶当地 %s %s",
        SELFTEST_SAVE, tostring(cleared), baseSnap.dateKey, baseSnap.clock))

    local dateKey = baseSnap.dateKey
    -- 顺序即原顺序；标签取各场景断言的编号前缀，日志里「场景 X 结束」可对回断言
    runScenario("A", ScenarioIdleChain, dateKey)
    runScenario("B", ScenarioFragments, dateKey)
    runScenario("C", ScenarioBusy, dateKey)
    runScenario("D", ScenarioOfflineFifo, dateKey)
    runScenario("E", ScenarioReentry, dateKey)
    runScenario("F", ScenarioFuturePlan, dateKey)
    runScenario("I", ScenarioEventPlan, dateKey)
    runScenario("J", ScenarioEventReentry, dateKey)
    runScenario("G", ScenarioAwaySummaryRule, dateKey)
    runScenario("H", ScenarioAwaySummary, dateKey)
    -- 引用与多段式回复：K/L 走正常引用，M 走四类失效降级，N/O 让引用跨过排队窗口，
    -- P 验逐句顺序，Q 验逐句与 FIFO 共存
    runScenario("K", ScenarioQuoteHer, dateKey)
    runScenario("L", ScenarioQuoteSelf, dateKey)
    runScenario("M", ScenarioInvalidQuote, dateKey)
    runScenario("N", ScenarioQuoteBusyQueue, dateKey)
    runScenario("O", ScenarioQuoteSleepQueue, dateKey)
    runScenario("P", ScenarioSegmentOrder, dateKey)
    runScenario("Q", ScenarioStreamingFifo, dateKey)

    MemoryService.ClearSavedData()
    summary_ = string.format("自检结论 通过=%d 失败=%d 场景=%d/%d[%s]",
        passed_, failed_, #done_, SCENARIO_TOTAL, table.concat(done_, " "))
    if #bad_ > 0 then
        summary_ = summary_ .. string.format(" 需看=%s", table.concat(bad_, " "))
    end
    if failed_ == 0 and #done_ == SCENARIO_TOTAL then
        logInfo(summary_ .. " 全部通过")
        return true
    end
    logError(summary_)
    return false
end

return DevSelfTest
