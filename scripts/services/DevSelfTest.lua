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
--   * 场景 Q：逐句上屏期间后发消息照常入队，FIFO 与「一对一回复」都不被卡住；
--   * 场景 R：M2-B 润色适配层的严格契约与全量回落（非法 JSON、额外字段、空数组、
--     超长句、错引用 id、401/429/502/503、抛异常、词表守卫、brief 档）——假 transport，零外发；
--   * 场景 S：润色在途 FIFO 与 8 秒预算（后发不越序、队头超预算必回落、迟到结果作废）；
--   * 场景 T：润色开启态下走真实队列链路（main.lua 的 HandleDeliver），FIFO、
--     逐句上屏与「事实仍全部由 Lua 给」在开启态下一条不破；
--   * 场景 U：四城时区表 —— 同一权威 UTC 秒在四城各得正确的当地钟点/日期，
--     含夏令冬令与跨日；U10 反查 UtcAtLocal↔Snapshot 互为逆，证设备时区无从掺入。
--   * 场景 V/W：洛杉矶与伦敦的 DST 收尾边界 —— 「回拨的那一小时」当地钟点相同
--     而 UTC 不同，排队窗口不得回退到已过期或重复的那一小时；
--   * 场景 X：随机入口 —— 定种派生可复现、16 个固定秒覆盖四城分布、
--     首次结果落盘重进后不重抽（存档 → InitServices → ProfileService 同一条链）；
--   * 场景 Y：四城切换核心链路不回归 —— 每城各跑一遍作息自洽、档案/场景/事件同源、
--     睡眠排队 FIFO、引用她的回复、落盘重进（与洛杉矶用的完全是同一套 helper，不另开旁路）；
--   * 场景 Z：v4 旧档迁移 —— 缺 profile 按「洛杉矶×陌生网友·已初始化」迁移，
--     transcript 更名 messages，引用字段/排队计划/事件计划一条不丢、不弹初始化界面。
--   * 场景 AI（M2-B 路径 A）：LLM 中继客户端一侧 —— 信封编解码与尺寸闸、应答按
--     requestId 配对、网络层 7 秒超时、断线批量结清、迟到结果一律作废。全程无网络；
--     服务端一侧不在客户端自检里跑（network/Server.lua 是 c_or_s="s"，客户端加载不到）。
--   * 场景 AB–AG（M4）：三段人生槽互不串写与满员拒建、冷启动选段与旧档收编、
--     16 个场景状态包完整且背景不复用、2.5D 生活痕迹全生命周期、切换人生不残留旧城市/旧景/旧痕、
--     建档时选的关系起点与种子必须落进段存档并在重进后原样接回。
-- 不 mock 任何被测服务，也不依赖被测服务没有的能力：
--   * 时间用 TimeState.DevClockOffset 投影（权威时间源不变，只是把 now 拨到某个当地整点）；
--   * 推进用 MessageService.Update(utcNow) 这个正式入口；
--   * 回复生成、落盘、读档都走 main.lua 挂的那套钩子。
-- 自检用独立存档，绝不碰玩家的聊天记录。任一断言失败都以 logError 落日志，
-- 所以 runtime.log 里 ERROR = 0 就等价于自检全绿。
-- ============================================================================

local TimeState = require("TimeState")
local ProfileService = require("ProfileService")
local MessageService = require("services.MessageService")
local ContentService = require("services.ContentService")
local MemoryService = require("services.MemoryService")
local EventService = require("services.EventService")
-- EventService 的 M7 扩展与旧 M1–M5 接口并存；自检只经这两个公开入口观察
-- 关键卡，不把计划器内部表当成另一条测试路径。EmmyLua 对跨模块增量字段不作合并，
-- 这里以公开适配面标成 any，实际字段断言仍在 AJ1–AJ4。
---@type any
local M7EventService = EventService
local PolishService = require("services.PolishService")
local ElizaService = require("services.ElizaService")
local SceneService = require("SceneService")
local LifeService = require("services.LifeService")

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
---@field reinit fun(saveFile: string|nil, lifeSlot: LifeSlot|nil, freshSlot: boolean|nil)
---@field updateTrace fun(fact: EventFact?)
---@field ensureTrace fun()
---@field reinitLife fun()

---@type string
local cityId_ = "los_angeles"
---@type number
local idleWait_ = 10
-- 未赋值的函数槽按 AGENTS 规则 #11 标注类型源头，调用点才有推导
---@type fun(snap: TimeSnapshot, quote?: QuoteRef): SendContext
local makeSendContext_
---@type fun(saveFile: string|nil, lifeSlot: LifeSlot|nil, freshSlot: boolean|nil)
local reinit_
---@type fun(fact: EventFact?)
local updateTrace_
---@type fun()
local ensureTrace_
---@type fun()
local reinitLife_

---@type integer
local passed_ = 0
---@type integer
local failed_ = 0
---@type string[]
local done_ = {}
--- 判定失败（含整条场景抛出）的场景名，结论行靠它指到该看哪一段断言
---@type string[]
local bad_ = {}
--- 失败断言的 label+detail 明细。设备上逐条走 logError 可见，但本地引擎日志不落 print/log
--- （AGENTS.md 边界 1），所以还要一份能被 PoC 直接读走的列表，否则只剩「AF×2」猜不出是哪两条。
---@type string[]
local failures_ = {}
---@type string
local summary_ = "自检未运行"

--- Run 里 runScenario 的调用条数；结论行拿它判断「有没有场景被整批日志丢掉」
local SCENARIO_TOTAL = 36

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
        failures_[#failures_ + 1] = string.format("%s %s", label, detail or "")
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
-- M2-B 辅助：按白名单契约造交付时刻的事实与消息，用假 transport 驱动
-- PolishService —— S1 阶段网关未部署，这些场景全程零外发。
-- ---------------------------------------------------------------------------

local POLISH_BASE_UTC = 1700000000

---@param overrides? table
---@return EventFact
local function polishFact(overrides)
    ---@type any
    local fact = {
        -- 刻意用真实模板之外的事件名：润色句里出现任何真事件名都该被守卫拦下
        eventTitle = "今晚这一场",
        eventSummary = "店里人不多，她在角落整理物料。",
        placeLabel = "小场地",
        clock = "19:45",
        weather = "晴",
        availabilityLabel = "空闲",
        eventEndsAt = "22:00",
        eventState = "ongoing",
        queued = false,
        phrase = "正整理着物料",
        availability = "idle",
        -- 城市名取自当前档案：M3 之后自检会切城，守卫判定不能钉死在洛杉矶
        cityLabel = ProfileService.Get().cityLabel,
        brief = false,
    }
    if overrides then
        for k, v in pairs(overrides) do
            fact[k] = v
        end
    end
    return fact
end

---@param overrides? table
---@return MsgEntry
local function polishPending(overrides)
    ---@type any
    local pending = { id = 4001, text = "那边现在安静吗？" }
    if overrides then
        for k, v in pairs(overrides) do
            pending[k] = v
        end
    end
    return pending
end

---@param segmentsJson string
---@param quoteJson? string
---@return string
local function polishBody(segmentsJson, quoteJson)
    return string.format('{"segments":[%s],"replyToQuotedMessageId":%s}',
        segmentsJson, quoteJson or "null")
end

---@param segText string
---@return PolishTransportResult
local function okResponse(segText)
    return { ok = true, status = 200, bodyText = polishBody('"' .. segText .. '"') }
end

--- 在当前已配置的 transport 上发一条润色（不重下配置，用于连续调用）
---@param fact? EventFact
---@param pending? MsgEntry
---@param nowUtc? number
---@return string[]|nil segments
---@return string category
local function polishNow(fact, pending, nowUtc)
    local out, reason
    PolishService.Polish({
        fact = fact or polishFact(),
        pending = pending or polishPending(),
        nowUtc = nowUtc or POLISH_BASE_UTC,
    }, function(segments, category)
        out, reason = segments, category
    end)
    return out, reason
end

--- 用假同步 transport 跑一条润色，返回段、结果类别与抓到的出站 payload
---@param result PolishTransportResult
---@param fact? EventFact
---@param pending? MsgEntry
---@return string[]|nil segments
---@return string category
---@return table? payload
local function polishOnce(result, fact, pending)
    local captured = nil
    PolishService.Configure({ enabled = true, transport = {
        request = function(payload, callback)
            captured = payload
            callback(result)
        end,
    } })
    local out, reason = polishNow(fact, pending)
    return out, reason, captured
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
        queuedStatus:find("Delivered") ~= nil and queuedStatus:find("Read") == nil, queuedStatus)

    local at16 = goLocalHour(16, dateKey)
    advance(30)
    check("C5 仍在忙碌窗口内不回复", at16.availability == "busy"
        and MessageService.GetQueueLength() == 1 and herReplyCount() == opens)

    local at17 = goLocalHour(17, dateKey)
    advance(30)
    check("C6 进入可回复窗口后回复", at17.availability == "fragments"
        and MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 1)
    local reply = lastHerReply()
    check("C7 回复引用送达时的作息事实而非捏造", TextOf(reply and reply.text):find("Working on a deadline") ~= nil,
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
        and firstStatus:find("Read") == nil,
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
    check("G2 摘要含客观间隔与两头作息", line:find("5h 12min") ~= nil
        and line:find("Working on a deadline") ~= nil and line:find("Still out") ~= nil, line)
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
    local rows = TimeState.ScheduleFor(cityId_)
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
    -- M7 关键卡命中自然发问时优先用卡片的固定回答；普通事件仍用实例原话。
    -- 两者都必须来自这个 19:45 实例，不能用宽松的 A/B/C 任意匹配。
    local expectedFactText = fact1945.m7Answer or fact1945.eventPhrase
    check("J1 19:45 回复用了开放麦实例自己的事实句",
        expectedFactText ~= "" and text1945:find(expectedFactText, 1, true) ~= nil,
        string.format("期望含=%s 实际=%s", expectedFactText, text1945))
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
    local endedMark = "ended at " .. nightFact.eventEndsAt
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
    local studioEndedMark = "ended at " .. studioFact.eventEndsAt
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
        text:find("I saw what you said") ~= nil or text:find("I'll keep that in mind") ~= nil, text)
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
    check("M8 降级后的回复里没有回指句", text:find("I saw what you said") == nil
        and text:find("I'll keep that in mind") == nil, text)
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
        status:find("Delivered") ~= nil and status:find("Read") == nil, status)

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
        status:find("Delivered") ~= nil and status:find("Read") == nil, status)

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

-- ---------------------------------------------------------------------------
-- 场景 R：M2-B 润色契约与全量回落 —— 假 transport 驱动 PolishService，零外发。
-- 覆盖测试矩阵：非法 JSON / 额外字段 / 空数组 / 超长句 / 错误引用 id /
-- 401·429·5xx / 超时（见 S）/ 模型不可用（503 冷却）/ 词表守卫 / brief 档。
-- ---------------------------------------------------------------------------
local function ScenarioPolishContract()
    logInfo("场景 R LLM 润色契约与回落（假 transport，零外发）")

    -- R0 关闭态：回调在 Polish 返回前就同步完成 —— main.lua 靠这条保证与 M2-A 一字不差
    local r0Seg, r0Cat
    PolishService.Configure({ enabled = false })
    PolishService.Polish({ fact = polishFact(), pending = polishPending(), nowUtc = POLISH_BASE_UTC },
        function(segments, category)
            r0Seg, r0Cat = segments, category
        end)
    check("R0 关闭态同步回落 disabled，不留在途槽位",
        r0Seg == nil and r0Cat == "disabled" and PolishService.GetPendingCount() == 0,
        tostring(r0Cat))

    local segs2, cat2, payload2 = polishOnce(
        { ok = true, status = 200, bodyText = polishBody('"Okay.","Give me a moment."') })
    check("R1 合法两段通过（llm）", segs2 ~= nil and #segs2 == 2 and cat2 == "llm",
        string.format("段数=%s 结果=%s", tostring(segs2 and #segs2), tostring(cat2)))
    check("R2 白名单 payload：quote 缺省也显式为 null，core/事实齐备",
        payload2 ~= nil and payload2.v == 1 and payload2.quote == cjson.null
        and payload2.core ~= nil and payload2.core.characterId == "lin_ruoxi"
        and payload2.deliveryFact ~= nil and payload2.sendFact ~= nil,
        string.format("quote=%s", tostring(payload2 and payload2.quote)))

    local _, _, clipped = polishOnce(okResponse("Okay."), nil,
        polishPending({ text = string.rep("话", 350) }))
    check("R3 用户原文超 300 码点出站前裁到 300", clipped ~= nil
        and PolishService.RuneLenForTest(clipped.userMessage) == 300,
        string.format("实裁 %d 码点",
            clipped and PolishService.RuneLenForTest(clipped.userMessage) or -1))

    local _, c4 = polishOnce({ ok = true, status = 200, bodyText = "{这不是 json" })
    check("R4 非法 JSON → schema_json", c4 == "schema_json", tostring(c4))

    local _, c5 = polishOnce({ ok = true, status = 200,
        bodyText = '{"segments":["好。"],"replyToQuotedMessageId":null,"source":"llm"}' })
    check("R5 额外字段 → schema_key_set", c5 == "schema_key_set", tostring(c5))

    local _, c6 = polishOnce({ ok = true, status = 200, bodyText = polishBody("") })
    check("R6 空数组 → schema_segments_count", c6 == "schema_segments_count", tostring(c6))

    local _, c7 = polishOnce(okResponse(string.rep("长", 45)))
    check("R7 单句超 40 字 → schema_segment_long", c7 == "schema_segment_long", tostring(c7))

    ---@type any
    local quotedPending = { id = 4002, text = "再说说那句。",
        quotedMessageId = 77, quotedRole = "user", quotedTextPreview = "那句想再听听" }
    local _, c8 = polishOnce({ ok = true, status = 200,
        bodyText = polishBody('"Okay."', "88") }, nil, quotedPending)
    check("R8 引用 id 与本次允许值不符 → schema_quote_id", c8 == "schema_quote_id", tostring(c8))
    local segs9, cat9 = polishOnce({ ok = true, status = 200,
        bodyText = polishBody('"Okay."', "77") }, nil, quotedPending)
    check("R8b 引用 id 与允许值一致 → 通过", segs9 ~= nil and cat9 == "llm", tostring(cat9))
    local _, c8c = polishOnce({ ok = true, status = 200,
        bodyText = polishBody('"Okay."', "77") })
    check("R8c 无引用请求里出数字 id → schema_quote_id", c8c == "schema_quote_id", tostring(c8c))

    local _, c10 = polishOnce(okResponse("   "))
    check("R10 纯空白句 trim 后为空 → schema_segment_empty",
        c10 == "schema_segment_empty", tostring(c10))
    local _, c11 = polishOnce(okResponse("好的`嗯"))
    check("R11 含反引号 → schema_segment_char", c11 == "schema_segment_char", tostring(c11))

    -- 401：回落一次并熔断本会话 —— 连续两条在同一次配置下才测得出「第二条不再外发」
    PolishService.Configure({ enabled = true, transport = { request = function(_, callback)
        callback({ ok = false, status = 401 })
    end } })
    local _, c12 = polishNow()
    local _, c12b = polishNow()
    check("R12 401 → http_401 且本会话熔断（下一条直接 disabled，不再出站）",
        c12 == "http_401" and c12b == "disabled" and PolishService.IsEnabled() == false,
        string.format("首=%s 次=%s", tostring(c12), tostring(c12b)))

    local _, c13 = polishOnce({ ok = false, status = 429 })
    check("R13 429 → http_429", c13 == "http_429", tostring(c13))
    local _, c14 = polishOnce({ ok = false, status = 502 })
    check("R14 5xx → http_502", c14 == "http_502", tostring(c14))

    -- 503 → 会话级冷却：同一次配置里连发两条，第二条必须不出站
    local hits503 = 0
    PolishService.Configure({ enabled = true, transport = { request = function(_, callback)
        hits503 = hits503 + 1
        callback({ ok = false, status = 503 })
    end } })
    local _, c15 = polishNow()
    local _, c15b = polishNow()
    check("R15 503（预算/模型不可用）→ http_503 并进冷却：600 秒内第二条不出站",
        c15 == "http_503" and c15b == "cooldown" and hits503 == 1,
        string.format("首=%s 次=%s 出站=%d", tostring(c15), tostring(c15b), hits503))

    PolishService.Configure({ enabled = true, transport = { request = function()
        error("transport 炸了")
    end } })
    local _, c16 = polishNow()
    check("R16 transport 抛异常 → transport_error（不崩调用方）",
        c16 == "transport_error", tostring(c16))

    -- 事实词表守卫（设计 §2 客户端最后一道）
    local otherCity = nil
    local homeCityLabel = ProfileService.Get().cityLabel
    for _, city in pairs(TimeState.CITIES) do
        if city.label ~= homeCityLabel then
            otherCity = city.label
            break
        end
    end
    local _, g1 = polishOnce(okResponse((otherCity or "别的城") .. "的晚高峰刚过。"))
    check("R17 润色句带别的城市 → guard_city", g1 == "guard_city", tostring(g1))

    local otherTitle = nil
    for _, title in ipairs(EventService.KnownEventTitles()) do
        if title ~= "今晚这一场" then
            otherTitle = title
            break
        end
    end
    local _, g2 = polishOnce(okResponse("刚看完" .. (otherTitle or "?") .. "的现场。"))
    check("R18 润色句带白名单外的事件名 → guard_event", g2 == "guard_event", tostring(g2))

    local _, g3 = polishOnce(okResponse("明天 23:30 才收工。"))
    check("R19 润色句带白名单外钟点 → guard_time", g3 == "guard_time", tostring(g3))
    local segs20, cat20 = polishOnce(okResponse("Still finishing at 19:45."))
    check("R20 请求事实里已有的钟点放行", segs20 ~= nil and cat20 == "llm", tostring(cat20))

    local _, b1 = polishOnce({ ok = true, status = 200, bodyText = polishBody('"好的。","马上。"') },
        polishFact({ brief = true }))
    check("R21 碎片档出两句 → schema_brief_multi", b1 == "schema_brief_multi", tostring(b1))
    local segs22, cat22 = polishOnce(okResponse("Okay."), polishFact({ brief = true }))
    check("R22 碎片档一句短回复通过", segs22 ~= nil and cat22 == "llm", tostring(cat22))
    local _, languageReason = polishOnce(okResponse("还是中文。"))
    check("R23 非英文润色回落英文模板", languageReason == "guard_language", tostring(languageReason))

    PolishService.Configure({ enabled = false })
end

-- ---------------------------------------------------------------------------
-- 场景 AA：离线 Eliza 规则层。它只根据输入或引用补一条陪伴式回应，
-- 不新增任何城市、事件或时间事实；未命中时必须交回 ContentService 的模板回退。
-- ---------------------------------------------------------------------------
local function ScenarioElizaRules()
    logInfo("场景 AA 离线 Eliza 规则层")

    local tail1, rule1 = ElizaService.ReplyTail("项目赶得我好累", nil, 17)
    local tail2, rule2 = ElizaService.ReplyTail("项目赶得我好累", nil, 17)
    check("AA1 匹配疲惫主题", rule1 == "fatigue" and tail1 ~= "", tostring(rule1))
    check("AA2 相同输入稳定返回", tail1 == tail2 and rule1 == rule2, tostring(tail1))

    local fallback, fallbackRule = ElizaService.ReplyTail("今天路过一盏灯", nil, 17)
    check("AA3 不匹配时交回模板链路", fallback == nil and fallbackRule == nil, tostring(fallbackRule))

    local quoteTail, quoteRule = ElizaService.ReplyTail("嗯", "今天项目很赶", 18)
    check("AA4 引用参与主题匹配", quoteRule == "work" and quoteTail ~= nil, tostring(quoteRule))
end

-- ---------------------------------------------------------------------------
-- 场景 S：润色在途的 FIFO 与 8 秒预算 —— 后发不越序、队头超预算必回落、迟到作废
-- ---------------------------------------------------------------------------
local function ScenarioPolishFifo()
    logInfo("场景 S 润色在途 FIFO 与预算：不越序、不阻塞、迟到作废")

    local callbacks = {}
    PolishService.Configure({ enabled = true, transport = { request = function(_, callback)
        callbacks[#callbacks + 1] = callback
    end } })
    local order = {}
    PolishService.Polish({ fact = polishFact(), pending = polishPending({ id = 501 }),
        nowUtc = POLISH_BASE_UTC }, function(s)
        order[#order + 1] = s and "A" or "A!"
    end)
    PolishService.Polish({ fact = polishFact(), pending = polishPending({ id = 502 }),
        nowUtc = POLISH_BASE_UTC }, function(s)
        order[#order + 1] = s and "B" or "B!"
    end)
    check("S0 两条都在途排队", #callbacks == 2 and PolishService.GetPendingCount() == 2,
        string.format("回调 %d 个 槽位 %d", #callbacks, PolishService.GetPendingCount()))

    -- 结果落地 → 交付由主循环那一次 Update 推进（真机每帧调 HandleUpdate；
    -- 自检在 Start 里同步跑，没有帧循环，所以这里手动推一拍，走的仍是同一个入口）
    callbacks[2](okResponse("B reply."))
    PolishService.Update(POLISH_BASE_UTC)
    check("S1 后发的结果先回来也不越序：一条都不交付", #order == 0,
        table.concat(order, ","))
    callbacks[1](okResponse("A reply."))
    PolishService.Update(POLISH_BASE_UTC)
    check("S2 队头落地后按发起顺序连发（A 先 B 后）",
        #order == 2 and order[1] == "A" and order[2] == "B"
        and PolishService.GetPendingCount() == 0,
        table.concat(order, ","))

    -- 预算：transport 从不调回调（违约），到点必须回落；迟到结果作废
    local lateCb = nil
    PolishService.Configure({ enabled = true, transport = { request = function(_, callback)
        lateCb = callback
    end } })
    local hits = 0
    PolishService.Polish({ fact = polishFact(), pending = polishPending({ id = 503 }),
        nowUtc = POLISH_BASE_UTC }, function()
        hits = hits + 1
    end)
    check("S3 预算内不提前交付", hits == 0 and PolishService.GetPendingCount() == 1)
    PolishService.Update(POLISH_BASE_UTC + 9)
    check("S4 超 8 秒预算必回落（队列不无限等）",
        hits == 1 and PolishService.GetPendingCount() == 0,
        string.format("回调 %d 次 槽位 %d", hits, PolishService.GetPendingCount()))
    lateCb(okResponse("迟到的句子。"))
    check("S5 预算回落后迟到的结果作废：不二次交付", hits == 1,
        string.format("回调 %d 次", hits))

    PolishService.Configure({ enabled = false })
end

-- ---------------------------------------------------------------------------
-- 场景 T：润色开启态走真实队列链路 —— onDeliver 钩子是 main.lua 的 HandleDeliver，
-- 只是 transport 换成假的。FIFO、逐句上屏与「事实由 Lua 给」在开启态一条不破。
-- ---------------------------------------------------------------------------
local function ScenarioPolishQueueFlow(dateKey)
    logInfo("场景 T 润色开启态下队列连续发送（真实 HandleDeliver 链路）")
    beginScenario()
    goLocalHour(19, dateKey, 45)
    -- reinit_ 把配置放回 GatewayEnabled=false；本场景注入假 transport 进入开启态
    PolishService.Configure({ enabled = true, transport = { request = function(payload, callback)
        local mark = payload.userMessage:find("第一条", 1, true) and "A" or "B"
        callback({ ok = true, status = 200,
            bodyText = polishBody('"' .. mark .. ' one.","' .. mark .. ' two."') })
    end } })

    sendNow("第一条。")
    sendNow("第二条。")
    local opens = herReplyCount()
    local markIndex = #MessageService.GetMessages()
    advance(idleWait_ * 2 + 60)
    local replies = herRepliesAfter(markIndex)
    check("T1 两条都回完且队列放空（润色开启不卡队列）",
        MessageService.GetQueueLength() == 0 and herReplyCount() == opens + 2,
        string.format("回复增量 %d 队列 %d", herReplyCount() - opens,
            MessageService.GetQueueLength()))
    check("T2 回复按送达顺序 FIFO：第一条落甲句、第二条落乙句", #replies == 2
        and TextOf(replies[1] and replies[1].text):find("A one", 1, true) ~= nil
        and TextOf(replies[2] and replies[2].text):find("B one", 1, true) ~= nil,
        string.format("一=%s 二=%s", TextOf(replies[1] and replies[1].text),
            TextOf(replies[2] and replies[2].text)))
    check("T3 润色文本逐句上屏后完整落库，一次回复仍只有一条记录", #replies == 2
        and replies[1] ~= nil and replies[1].text == "A one. A two."
        and replies[1].streamSegments == nil,
        TextOf(replies[1] and replies[1].text))
    check("T4 回复记录的送达事实照常由 Lua 带上（LLM 不碰事实）",
        replies[1] ~= nil and replies[1].factId ~= nil and replies[1].factKey ~= nil,
        string.format("fact=%s key=%s", tostring(replies[1] and replies[1].factId),
            tostring(replies[1] and replies[1].factKey)))

    PolishService.Configure({ enabled = false })
end

-- ---------------------------------------------------------------------------
-- M3 辅助：DST / 时区断言的期望常量全部手算自日历（2026-11-01、2026-10-25
-- 都是周日；美国 11 月第一个周日 02:00 本地回拨、英国 10 月最后一个周日
-- 02:00 本地回拨），不经任何被测代码，才算独立判据。
-- ---------------------------------------------------------------------------

local SUMMER_UTC = 1784116800   -- 2026-07-15 12:00 UTC（夏令时中段）
local WINTER_UTC = 1796126400   -- 2026-12-01 12:00 UTC（冬令时中段）
local CROSS_UTC = 1796144400    -- 2026-12-01 17:00 UTC（上海已跨日，洛杉矶还在当日上午）

local LA_DST_PRE = 1793521800   -- 2026-11-01 08:30Z，当地 01:30 PDT（切换前）
local LA_DST_POST = 1793525400  -- 同日 09:30Z，当地 01:30 PST（切换后：同钟点，UTC 晚一小时）
local LA_MORNING_UTC = 1793541600 -- 同日 14:00Z = 当地 06:00 PST，醒来的第一档 idle

local LON_DST_PRE = 1792888200  -- 2026-10-25 00:30Z，当地 01:30 BST（切换前）
local LON_DST_POST = 1792891800 -- 同日 01:30Z，当地 01:30 GMT（切换后：同一个 01:30）
local LON_MORNING_UTC = 1792908000 -- 同日 06:00Z = 当地 06:00 GMT，醒来的第一档 idle

-- 随机派生的固定创作秒：与 ProfileService.RandomPick 同一算法（无 math.random），
-- X1 的两个期望组合在实施时用独立实现逐位对拍过。
local RANDOM_SEC_0 = 1789600000
local RANDOM_STEP = 7919
local RANDOM_SAMPLES = 16

---@param label string
---@param cityId string
---@param utcSec number
---@param wantClock string
---@param wantDateKey string
---@param wantOffsetHours integer
---@param wantDst boolean
local function checkClock(label, cityId, utcSec, wantClock, wantDateKey, wantOffsetHours, wantDst)
    local snap = TimeState.Snapshot(cityId, utcSec)
    check(label, snap.clock == wantClock and snap.dateKey == wantDateKey
        and snap.offsetSeconds == wantOffsetHours * 3600 and snap.isDst == wantDst,
        string.format("实际=%s %s off=%ds dst=%s", snap.dateKey, snap.clock,
            snap.offsetSeconds, tostring(snap.isDst)))
end

-- ---------------------------------------------------------------------------
-- 场景 U：四城时区表 —— 同一权威 UTC 在四城各得正确的当地钟点与日期
-- ---------------------------------------------------------------------------
local function ScenarioFourCityTime()
    logInfo("场景 U 四城时区：夏冬令、跨日、同一 UTC 恒得同一结果")
    checkClock("U1 夏令·洛杉矶 12:00Z → 05:00 PDT(-7)", "los_angeles", SUMMER_UTC, "05:00", "2026-07-15", -7, true)
    checkClock("U2 夏令·伦敦 12:00Z → 13:00 BST(+1)", "london", SUMMER_UTC, "13:00", "2026-07-15", 1, true)
    checkClock("U3 夏令·上海 12:00Z → 20:00(+8 无 DST)", "shanghai", SUMMER_UTC, "20:00", "2026-07-15", 8, false)
    checkClock("U4 夏令·成都 12:00Z → 20:00(+8 无 DST)", "chengdu", SUMMER_UTC, "20:00", "2026-07-15", 8, false)
    checkClock("U5 冬令·洛杉矶 12:00Z → 04:00 PST(-8)", "los_angeles", WINTER_UTC, "04:00", "2026-12-01", -8, false)
    checkClock("U6 冬令·伦敦 12:00Z → 12:00 GMT(+0)", "london", WINTER_UTC, "12:00", "2026-12-01", 0, false)
    checkClock("U7 冬令·上海 12:00Z → 20:00(+8)", "shanghai", WINTER_UTC, "20:00", "2026-12-01", 8, false)
    checkClock("U8 跨日·上海 17:00Z → 次日 01:00", "shanghai", CROSS_UTC, "01:00", "2026-12-02", 8, false)
    checkClock("U9 跨日·同一 UTC 洛杉矶仍是当日 09:00", "los_angeles", CROSS_UTC, "09:00", "2026-12-01", -8, false)
    -- 反查互逆：UtcAtLocal 与 Snapshot 读同一张偏移表。整条链只碰 os.date("!")，
    -- 设备时区无从参与 —— 同一 UTC 秒在任何机器上算出的当地钟点都一样。
    check("U10 UtcAtLocal 与 Snapshot 互为逆（设备时区无从掺入）",
        TimeState.UtcAtLocal("los_angeles", "2026-12-01", 9) == CROSS_UTC
        and TimeState.UtcAtLocal("shanghai", "2026-12-02", 1) == CROSS_UTC,
        string.format("la=%d sha=%d 期望=%d",
            TimeState.UtcAtLocal("los_angeles", "2026-12-01", 9),
            TimeState.UtcAtLocal("shanghai", "2026-12-02", 1), CROSS_UTC))
end

-- ---------------------------------------------------------------------------
-- 场景 V：洛杉矶 DST 收尾边界 —— 「回拨的那一小时」不得把窗口回退到过期区间
-- ---------------------------------------------------------------------------
local function ScenarioLaDstBoundary()
    logInfo("场景 V 洛杉矶 DST 边界：同钟点不同偏移，窗口不回退")
    checkClock("V1 切换前 08:30Z → 01:30 PDT(-7)", "los_angeles", LA_DST_PRE, "01:30", "2026-11-01", -7, true)
    checkClock("V2 切换后 09:30Z → 01:30 PST(-8)（当地重复的那一小时）", "los_angeles", LA_DST_POST, "01:30", "2026-11-01", -8, false)
    local prePlan = TimeState.ReplyPlanFor("los_angeles", LA_DST_PRE)
    check("V3 切换前凌晨送达 → 排到 06:00 PST，只往前走不回退进重复小时",
        prePlan.replyable == false and prePlan.windowStartUtc == LA_MORNING_UTC
        and prePlan.replyAtUtc == LA_MORNING_UTC + prePlan.delaySeconds
        and prePlan.replyAtUtc > LA_DST_PRE,
        string.format("window=%s replyAt=%s", tostring(prePlan.windowStartUtc), tostring(prePlan.replyAtUtc)))
    local postNext = TimeState.NextReplyableUtc("los_angeles", LA_DST_POST)
    check("V4 切换后同钟点 → 仍是同一个 06:00 PST 窗口（结果只由 UTC 秒决定）",
        postNext == LA_MORNING_UTC, tostring(postNext))
end

-- ---------------------------------------------------------------------------
-- 场景 W：伦敦 DST 收尾边界 —— 与洛杉矶同判据，证第二张偏移表独立成立
-- ---------------------------------------------------------------------------
local function ScenarioLondonDstBoundary()
    logInfo("场景 W 伦敦 DST 边界：钟点回拨、窗口不回拨")
    checkClock("W1 切换前 00:30Z → 01:30 BST(+1)", "london", LON_DST_PRE, "01:30", "2026-10-25", 1, true)
    checkClock("W2 切换后 01:30Z → 01:30 GMT(+0)（当地重复的那一小时）", "london", LON_DST_POST, "01:30", "2026-10-25", 0, false)
    local nextWin = TimeState.NextReplyableUtc("london", LON_DST_PRE)
    check("W3 钟点回拨但窗口不回拨：06:00 GMT 才是第一个 idle 档",
        nextWin == LON_MORNING_UTC and nextWin > LON_DST_PRE, tostring(nextWin))
    local plan = TimeState.ReplyPlanFor("london", LON_DST_PRE)
    check("W4 伦敦睡眠排队计划 = 窗口 + 反应时间（策略与洛杉矶同源）",
        plan.replyable == false and plan.windowStartUtc == LON_MORNING_UTC
        and plan.replyAtUtc == LON_MORNING_UTC + plan.delaySeconds,
        string.format("window=%s delay=%s", tostring(plan.windowStartUtc), tostring(plan.delaySeconds)))
    local postNext = TimeState.NextReplyableUtc("london", LON_DST_POST)
    check("W5 切换后同钟点 → 同一个 06:00 GMT 窗口", postNext == LON_MORNING_UTC, tostring(postNext))
end

-- ---------------------------------------------------------------------------
-- 场景 X：随机入口 —— 定种派生可复现，首次结果落盘后重进不重抽
-- ---------------------------------------------------------------------------
local function ScenarioRandomPersistence()
    logInfo("场景 X 随机入口：可复现、跨重启固化")
    beginScenario()

    local first = ProfileService.RandomPick(RANDOM_SEC_0)
    local second = ProfileService.RandomPick(RANDOM_SEC_0 + RANDOM_STEP)
    check("X1 盐值钉死组合：1789600000→上海×陌生网友，+7919→洛杉矶×前同事",
        first.cityId == "shanghai" and first.relationId == "stranger"
        and second.cityId == "los_angeles" and second.relationId == "ex_colleague",
        string.format("%s×%s | %s×%s", first.cityId, first.relationId, second.cityId, second.relationId))
    local repicked = ProfileService.RandomPick(RANDOM_SEC_0)
    check("X2 同一创作秒重复抽取逐字相同（定种派生，无 math.random）",
        repicked.cityId == first.cityId and repicked.relationId == first.relationId
        and repicked.seedText == first.seedText, repicked.seedText)

    local seenCities, seenRelations = {}, {}
    for i = 0, RANDOM_SAMPLES - 1 do
        local picked = ProfileService.RandomPick(RANDOM_SEC_0 + i * RANDOM_STEP)
        seenCities[picked.cityId] = true
        seenRelations[picked.relationId] = true
    end
    local covered = true
    for _, id in ipairs(ProfileService.CITY_ORDER) do
        if not seenCities[id] then
            covered = false
        end
    end
    local relCount = 0
    for _ in pairs(seenRelations) do
        relCount = relCount + 1
    end
    check("X3 连续 16 个秒覆盖四城且关系不塌缩（分布可用）", covered and relCount >= 3,
        string.format("关系种数=%d", relCount))

    local p = ProfileService.ApplyRandom(RANDOM_SEC_0)
    check("X4 ApplyRandom 落到完整随机档案（isRandom/initialized/seedText 齐备）",
        p.isRandom == true and p.initialized == true and p.seedText ~= ""
        and p.cityId == first.cityId and p.relationId == first.relationId, p.seedText)

    MemoryService.SetProfile({
        cityId = p.cityId, relationId = p.relationId, seedText = p.seedText,
        isRandom = p.isRandom, initialized = p.initialized,
    })
    MemoryService.Persist(MessageService.GetMessages())
    reinit_(SELFTEST_SAVE)
    local back = MemoryService.GetProfile()
    local active = ProfileService.Get()
    check("X5 落盘重进后随机结果原样使用、不重抽（存档→InitServices→ProfileService）",
        back ~= nil and back.cityId == p.cityId and back.relationId == p.relationId
        and back.isRandom == true and back.seedText == p.seedText
        and active.cityId == p.cityId and active.relationId == p.relationId
        and active.isRandom == true,
        string.format("存档=%s×%s 运行时=%s×%s", tostring(back and back.cityId),
            tostring(back and back.relationId), active.cityId, active.relationId))
end

-- ---------------------------------------------------------------------------
-- 场景 Y：四城切换核心链路不回归 —— 每城跑与洛杉矶完全同一套 helper：
-- 排队 FIFO、引用她的回复、落盘重进，外加档案/作息/场景/事件四层同源断言。
-- ---------------------------------------------------------------------------
local function ScenarioCityConsistency(dateKey)
    logInfo("场景 Y 四城切换：作息-场景-事件-回复-排队-存档同源不回归")
    for _, city in ipairs(ProfileService.CITY_ORDER) do
        beginScenario()
        cityId_ = city
        local cityProf = ProfileService.CityFor(city)
        ProfileService.Set(city, cityProf.defaultRelation, { initialized = true })
        local prefix = TimeState.CITIES[city].scenePrefix

        local rows = TimeState.ScheduleFor(city)
        local seamless = rows[1].from == 0 and rows[#rows].to == 24
        local kinds = {}
        local ownEvents = true
        for i = 1, #rows do
            if i > 1 and rows[i].from ~= rows[i - 1].to then
                seamless = false
            end
            kinds[rows[i].availability] = true
            if rows[i].event:sub(1, #prefix + 1) ~= prefix .. "_" then
                ownEvents = false
            end
        end
        local kindCount = 0
        for _ in pairs(kinds) do
            kindCount = kindCount + 1
        end
        check(city .. " Y1 作息无缝覆盖 00–24 且可用性档 ≥3 种", seamless and kindCount >= 3,
            string.format("段=%d 可用性=%d", #rows, kindCount))
        check(city .. " Y2 每档事件 id 都是本城前缀（作息表没混进别城的行）", ownEvents)
        check(city .. " Y3 档案身份齐备且状态窗场景词汇 ≥2",
            #cityProf.sceneVocab >= 2 and cityProf.identity ~= "",
            string.format("场景词 %d 条", #cityProf.sceneVocab))
        local narrated = true
        for i = 1, #rows do
            if not ProfileService.EventNarration(city, rows[i].event) then
                narrated = false
            end
        end
        check(city .. " Y4 档案叙事覆盖作息每一档（换城不缺叙事）", narrated)

        goLocalHour(1, dateKey)
        local snap = TimeState.Snapshot(city, TimeState.NowUtc())
        local plan = EventService.PlanFor(city, snap.dateKey)
        local fact = EventService.FactFor(city, snap.utcSec)
        local q = EventService.QueryAt(city, snap.utcSec)
        check(city .. " Y5 事件计划逐行覆盖作息表", #plan.occurrences == #rows,
            string.format("事件 %d / 作息 %d", #plan.occurrences, #rows))
        check(city .. " Y6 当地 01:00 睡眠·公寓，快照/事件/查询三方场景一致",
            snap.availability == "offline" and snap.place == "apartment"
            and snap.sceneId == prefix .. "_apartment"
            and fact.sceneId == snap.sceneId and fact.eventState == "ongoing"
            and q.allStates[fact.id] == "ongoing",
            string.format("scene=%s event=%s", snap.sceneId, fact.id))

        local first = sendNow("你那边现在冷吗？")
        local second = sendNow("再说一句。")
        local markIndex = #MessageService.GetMessages()
        check(city .. " Y7 睡眠档两条消息排队不即时回复、计划先后有序",
            MessageService.GetQueueLength() == 2 and first ~= nil and second ~= nil
            and second.planReplyAtUtc > first.planReplyAtUtc,
            string.format("队列 %d", MessageService.GetQueueLength()))
        goLocalHour(7, dateKey)
        advance(60)
        local replies = herRepliesAfter(markIndex)
        check(city .. " Y8 醒后两条按 FIFO 回完且各带本城送达事实",
            MessageService.GetQueueLength() == 0 and #replies == 2
            and replies[1] ~= nil and replies[1].factId ~= nil
            and replies[2] ~= nil and replies[2].factId ~= nil,
            string.format("回复 %d 队列剩 %d", #replies, MessageService.GetQueueLength()))
        local preview = replies[1] and ContentService.ClipPreview(replies[1].text, 24) or ""
        local quoted = sendNow("这句再说一遍。",
            replies[1] and { id = replies[1].id, role = "her", text = replies[1].text } or nil)
        check(city .. " Y9 引用她刚回的句：引用字段照常落在新消息上", quoted ~= nil
            and quoted.quotedMessageId == replies[1].id
            and quoted.quotedRole == MessageService.ROLE.HER and preview ~= "",
            string.format("id=%s", tostring(quoted and quoted.quotedMessageId)))
        advance(idleWait_ + 20)
        local quoteReply = lastHerReply()
        local qText = TextOf(quoteReply and quoteReply.text)
        check(city .. " Y10 被引句在本城回复里被完整带出（引用链路跨城可用）",
            quoteReply ~= nil and quoteReply ~= replies[1]
            and qText:find(preview, 1, true) ~= nil, qText)

        local totalBefore = #MessageService.GetMessages()
        local stampBefore = nil
        for i = totalBefore, 1, -1 do
            if MessageService.GetMessages()[i].role == MessageService.ROLE.USER then
                stampBefore = MessageService.GetMessages()[i].cityIdAtSend
                break
            end
        end
        MemoryService.SetProfile({
            cityId = city, relationId = cityProf.defaultRelation,
            seedText = "", isRandom = false, initialized = true,
        })
        MemoryService.Persist(MessageService.GetMessages())
        reinit_(SELFTEST_SAVE)
        local backProf = MemoryService.GetProfile()
        local reopened = MessageService.Restore(MemoryService.GetRestoredMessages())
        local msgsAfter = MessageService.GetMessages()
        local stampAfter = nil
        for i = #msgsAfter, 1, -1 do
            if msgsAfter[i].role == MessageService.ROLE.USER then
                stampAfter = msgsAfter[i].cityIdAtSend
                break
            end
        end
        check(city .. " Y11 落盘重进：档案是本城、记录一条不丢、已回完的不重回",
            backProf ~= nil and backProf.cityId == city
            and backProf.relationId == cityProf.defaultRelation
            and reopened == 0 and #msgsAfter == totalBefore,
            string.format("档案=%s×%s 记录 %d/%d",
                tostring(backProf and backProf.cityId), tostring(backProf and backProf.relationId),
                #msgsAfter, totalBefore))
        check(city .. " Y12 城市戳随消息落盘重进不漂移（发送城=读回城=本城）",
            stampBefore == city and stampAfter == city,
            string.format("发送=%s 读回=%s", tostring(stampBefore), tostring(stampAfter)))
    end
    -- 气泡城市戳取消息自带的城；缺字段（旧档）或未知城才回落当前档案
    ProfileService.Set("los_angeles", "stranger", { initialized = true })
    check("Y13 城市戳优先取消息自带城市，缺省/未知回落当前档案",
        ProfileService.MessageSuffix(true, "shanghai"):find("Shanghai", 1, true) ~= nil
        and ProfileService.MessageSuffix(true, nil):find("Los Angeles", 1, true) ~= nil
        and ProfileService.MessageSuffix(true, "no_such_city"):find("Los Angeles", 1, true) ~= nil)
    cityId_ = "los_angeles"
end

-- ---------------------------------------------------------------------------
-- 场景 Z：v4 旧档迁移 —— 缺 profile 按明确规则补齐，历史一条不丢、不弹初始化
-- ---------------------------------------------------------------------------

--- 只给本场景造旧版本夹具用：正常路径一律走 MemoryService.Save
---@param path string
---@param tbl table
---@return integer bytes
local function writeRawSave(path, tbl)
    local encoded = cjson.encode(tbl)
    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then
        error("无法写入夹具存档: " .. path)
    end
    file:WriteString(encoded)
    file:Close()
    file:Dispose()
    return #encoded
end

local function ScenarioV4Migration()
    logInfo("场景 Z v4 旧档迁移：不弹初始化、记录/引用/队列/计划不丢")
    beginScenario()

    ---@type any
    local fixture = {
        version = 4,
        cityId = "los_angeles",
        turns = 7,
        firstServerTime = 1796000000,
        lastServerTime = 1796003600,
        lastFactId = "la_cafe_open_mic",
        topics = { "书店" },
        transcript = {
            { id = 9001, role = "user", text = "今晚店里人多吗？", serverTime = 1796000000,
                state = "replied", statusText = "已送达", clockText = "19:45",
                factId = "la_cafe_open_mic", availabilityAtSend = "idle",
                quotedMessageId = 9000, quotedRole = "her", quotedTextPreview = "人不多。" },
            { id = 9002, role = "her", text = "人不多，在整理物料。", serverTime = 1796000010,
                state = "delivered", clockText = "19:45", factId = "la_cafe_open_mic" },
            { id = 9003, role = "user", text = "明早想去你那逛逛。", serverTime = 1796003600,
                state = "queued", statusText = "排队中", clockText = "04:00",
                availabilityAtSend = "offline", replyableAtSend = false,
                planReplyAtUtc = 1796047210, planWindowStartUtc = 1796047200 },
        },
        eventLedger = {
            { key = "los_angeles/2026-11-30/la_apartment_night_rest", eventId = "la_apartment_night_rest",
                title = "凌晨在公寓睡下", sceneId = "la_apartment",
                startUtc = 1796025600, endUtc = 1796047200,
                lastEventState = "ongoing", lastServerTime = 1796030000 },
        },
        eventPlans = {
            {
                cityId = "los_angeles",
                dateKey = "2026-11-30",
                seedText = "fixture",
                generatedAtUtc = 1796000000,
                occurrences = {
                    { occurrenceKey = "los_angeles/2026-11-30/la_apartment_night_rest",
                        templateId = "la_apartment_night_rest", variantIndex = 1,
                        startUtc = 1796025600, endUtc = 1796047200,
                        place = "apartment", availability = "offline" },
                },
            },
        },
    }
    local bytes = writeRawSave(SELFTEST_SAVE, fixture)
    reinit_(SELFTEST_SAVE)

    local prof = MemoryService.GetProfile()
    check("Z1 v4 缺档案迁移为洛杉矶×陌生网友且已初始化（不弹初始化界面）",
        prof ~= nil and prof.cityId == "los_angeles" and prof.relationId == "stranger"
        and prof.isRandom == false and prof.initialized == true
        and ProfileService.Get().cityId == "los_angeles"
        and ProfileService.Get().initialized == true,
        string.format("profile=%s×%s init=%s 夹具 %d 字节",
            tostring(prof and prof.cityId), tostring(prof and prof.relationId),
            tostring(prof and prof.initialized), bytes))
    check("Z2 迁移后内存版本抬到 v6", MemoryService.Get().version == 6,
        tostring(MemoryService.Get().version))
    local reopened = MessageService.Restore(MemoryService.GetRestoredMessages())
    local msgs = MessageService.GetMessages()
    check("Z3 transcript 三条全部迁为 messages（一条不丢、待回复的仍算排队）",
        #msgs == 3 and reopened == 1, string.format("记录 %d 待回复 %d", #msgs, reopened))
    local quotedEntry = msgs[1]
    check("Z4 引用字段原样迁移（quotedMessageId/role/preview 都在）",
        quotedEntry ~= nil and quotedEntry.quotedMessageId == 9000
        and quotedEntry.quotedRole == "her"
        and TextOf(quotedEntry.quotedTextPreview) == "Not many people here.",
        string.format("id=%s role=%s", tostring(quotedEntry and quotedEntry.quotedMessageId),
            tostring(quotedEntry and quotedEntry.quotedRole)))
    local queued = head()
    check("Z5 待回复消息带着原计划时刻回来（不会读档即提前回复）",
        queued ~= nil and queued.id == 9003 and queued.planReplyAtUtc == 1796047210
        and queued.availabilityAtSend == "offline",
        string.format("id=%s plan=%s", tostring(queued and queued.id),
            tostring(queued and queued.planReplyAtUtc)))
    local plan = EventService.PeekPlan("los_angeles", "2026-11-30")
    check("Z6 事件计划由存档接管：fromSave=true 且 occurrenceKey 不变",
        plan ~= nil and plan.fromSave == true and plan.occurrences[1] ~= nil
        and plan.occurrences[1].occurrenceKey == "los_angeles/2026-11-30/la_apartment_night_rest"
        and plan.occurrences[1].templateId == "la_apartment_night_rest",
        string.format("plan=%s", plan and plan.occurrences[1].occurrenceKey or "nil"))

    -- v5 带记录却缺 profile：只可能是初始化前被强杀的脏写半截，按 LA×陌生网友兜底；
    -- 真正没记录的新档（Load 无文件 / 空 messages）才留给初始化界面
    ---@type any
    local fixture5 = {
        version = 5,
        cityId = "los_angeles",
        turns = 2,
        firstServerTime = 1796000000,
        lastServerTime = 1796000010,
        lastFactId = "la_cafe_open_mic",
        topics = {},
        messages = {
            { id = 8100, role = "user", text = "在吗？", serverTime = 1796000000,
                state = "replied", clockText = "19:45", cityIdAtSend = "shanghai" },
            { id = 8101, role = "her", text = "在的。", serverTime = 1796000010,
                state = "replied", clockText = "19:45" },
        },
    }
    writeRawSave(SELFTEST_SAVE, fixture5)
    reinit_(SELFTEST_SAVE)
    local prof5 = MemoryService.GetProfile()
    -- 与 Z3 同一条路：InitServices 只装服务，读回的记录要显式交给 MessageService
    -- （真机上是 BootChat 里那一次 Restore）。少了这一步读的是空数组，不是存档。
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local back5 = MessageService.GetMessages()
    check("Z7 v5 半截脏档（带记录缺 profile）兜底为 LA×陌生网友已初始化，不弹初始化",
        prof5 ~= nil and prof5.cityId == "los_angeles" and prof5.relationId == "stranger"
        and prof5.initialized == true and ProfileService.Get().initialized == true
        and #back5 == 2,
        string.format("profile=%s×%s 记录 %d",
            tostring(prof5 and prof5.cityId), tostring(prof5 and prof5.relationId), #back5))
    check("Z8 消息城市戳穿存档往返（上海时期发的消息重进仍带上海）",
        back5[1] ~= nil and back5[1].cityIdAtSend == "shanghai",
        tostring(back5[1] and back5[1].cityIdAtSend))
end


-- ---------------------------------------------------------------------------
-- M4 场景 AB–AG：平行人生槽、冷启动选段、场景状态包、生活痕迹、切换无残留与建档关系落盘。
-- 全部走自检专属的人生注册表（main.lua 注入三个路径），绝不碰玩家的
-- lives.json、段存档与 M0–M3 旧档。
-- ---------------------------------------------------------------------------

--- 自检旧单存档夹具路径，与 main.lua 的 legacyFile 注入严格一致
local SELFTEST_LIFE_LEGACY = "memory/life-selftest-legacy.json"

--- 读回存档原始表（隔离互证用：断言文件里写了什么，不是服务内存里说什么）
---@param path string
---@return any
local function readRawSave(path)
    local out = nil
    pcall(function()
        if not fileSystem:FileExists(path) then
            return
        end
        local file = File(path, FILE_READ)
        if not file:IsOpen() then
            return
        end
        local raw = file:ReadString()
        file:Close()
        file:Dispose()
        out = cjson.decode(raw)
    end)
    return out
end

--- 清掉 M4 场景用到的全部人生文件并重建内存注册表（场景之间不留残留）
local function resetLifeRegistry()
    reinitLife_()
    LifeService.ClearAll()
    pcall(function()
        if fileSystem:FileExists(SELFTEST_LIFE_LEGACY) then
            fileSystem:Delete(SELFTEST_LIFE_LEGACY)
        end
    end)
end

--- 场景 AB：最多三段、各写各的、第四段必须显式替换
local function ScenarioLifeIsolation(dateKey)
    logInfo("场景 AB 人生槽互不串写与三段上限")
    beginScenario()
    resetLifeRegistry()
    local t0 = TimeState.NowUtc()
    local slotA = LifeService.CreateSlot("los_angeles", "stranger", nil, t0)
    local slotB = LifeService.CreateSlot("shanghai", "classmate", nil, t0 + 1)
    local slotC = LifeService.CreateSlot("chengdu", "old_friend", nil, t0 + 2)
    local fourth, reason = LifeService.CreateSlot("london", "ex_colleague", nil, t0 + 3)
    check("AB1 满三段：第四段被拒 reason=full 且前三段原样在（不静默淘汰）",
        slotA ~= nil and slotB ~= nil and slotC ~= nil and fourth == nil and reason == "full"
        and LifeService.Count() == 3, tostring(reason))
    check("AB2 段号固定为 life-1/2/3（段号同时决定存档文件名，跨重启稳定）",
        slotA.slotId == "life-1" and slotB.slotId == "life-2" and slotC.slotId == "life-3")

    LifeService.OpenSlot("life-1", t0 + 10)
    reinit_(LifeService.SlotSaveFile("life-1"), LifeService.Active())
    goLocalHour(12, dateKey)
    sendNow("中午吃过了吗？")
    advance(30)
    MemoryService.Persist(MessageService.GetMessages())
    local msgsA = MessageService.GetMessages()
    check("AB3 life-1 全链路写聊天：落盘后条数在、lifeId 钉的是 life-1",
        #msgsA >= 2 and MemoryService.GetLifeId() == "life-1",
        string.format("条数 %d lifeId=%s", #msgsA, tostring(MemoryService.GetLifeId())))

    LifeService.OpenSlot("life-2", t0 + 11)
    reinit_(LifeService.SlotSaveFile("life-2"), LifeService.Active())
    local restoredB = MessageService.Restore(MemoryService.GetRestoredMessages())
    check("AB4 打开 life-2 是另一份空历史：A 的记录没漏进来、档案是上海",
        #MessageService.GetMessages() == 0 and restoredB == 0
        and ProfileService.GetCityId() == "shanghai"
        and MemoryService.GetLifeId() == "life-2",
        string.format("lifeId=%s city=%s", tostring(MemoryService.GetLifeId()), ProfileService.GetCityId()))

    LifeService.SetTrace("life-3", { traceKey = "postcard", occurrenceKey = "cdu/seed-a",
        eventTitle = "在公寓写明信片", sceneId = "cdu_apartment" }, t0 + 12)
    LifeService.SetTrace("life-1", { traceKey = "coffee", occurrenceKey = "la/seed-a",
        eventTitle = "中午的咖啡馆", sceneId = "la_cafe" }, t0 + 12)
    local tr1, tr2, tr3 = LifeService.GetTrace("life-1"), LifeService.GetTrace("life-2"), LifeService.GetTrace("life-3")
    check("AB5 痕迹按段各写各的：life-1 与 life-3 各说各的，life-2 仍是空",
        tr1 ~= nil and tr1.traceKey == "coffee" and tr2 == nil
        and tr3 ~= nil and tr3.traceKey == "postcard")

    local rawA = readRawSave(LifeService.SlotSaveFile("life-1"))
    local rawB = readRawSave(LifeService.SlotSaveFile("life-2"))
    -- life-2 的文件现在可能在挂载时就因「卡片档案落档」而出现（M5 起 InitServices 当场
    -- 写一次），所以判据不是「有没有文件」，而是「它带的是不是自己那一段的东西」
    check("AB6 段存档文件各写各的：life-1 文件里才有 life-1 的记录，life-2 不带着 life-1 的东西",
        rawA ~= nil and rawA.lifeId == "life-1" and rawA.messages ~= nil and #rawA.messages == #msgsA
        and (rawB == nil or (rawB.lifeId == "life-2"
            and (rawB.messages == nil or #rawB.messages == 0)))
        and LifeService.SlotSaveFile("life-1") ~= LifeService.SlotSaveFile("life-2"),
        string.format("A=%s B=%s", tostring(rawA and rawA.lifeId), tostring(rawB and rawB.lifeId)))

    LifeService.OpenSlot("life-1", t0 + 13)
    reinit_(LifeService.SlotSaveFile("life-1"), LifeService.Active())
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local backA = MessageService.GetMessages()
    local profA = MemoryService.GetProfile()
    check("AB7 回到 life-1：聊天条数、档案、痕迹原样回来（换段不丢东西）",
        #backA == #msgsA and profA ~= nil and profA.cityId == "los_angeles"
        and LifeService.GetTrace().traceKey == "coffee")

    -- 存档 lifeId 与当前槽不符是串写嫌疑：WARN 已落日志，会话仍按自己的槽指针继续
    ---@type any
    local crossed = {
        version = 6, lifeId = "life-9", cityId = "shanghai", turns = 0,
        firstServerTime = t0, lastServerTime = t0 + 1, lastFactId = "", topics = {},
        messages = {},
        profile = { cityId = "shanghai", relationId = "stranger", seedText = "x",
            isRandom = false, initialized = true },
    }
    writeRawSave(SELFTEST_SAVE, crossed)
    reinit_(SELFTEST_SAVE, LifeService.SlotById("life-1"))
    check("AB8 存档带着别人的 lifeId：仍按当前槽指针继续（串写可见化但不被劫持）",
        MemoryService.GetLifeId() == "life-1", tostring(MemoryService.GetLifeId()))
end

--- 场景 AC：旧单存档收编 + 冷启动直达最近打开的人生
local function ScenarioColdStartLegacy(dateKey)
    logInfo("场景 AC 冷启动选段与旧档收编（隔离注册表，不碰玩家存档）")
    beginScenario()
    resetLifeRegistry()
    local t0 = TimeState.NowUtc()
    ---@type any
    local legacy = {
        version = 5, cityId = "london", turns = 3,
        firstServerTime = t0 - 86400, lastServerTime = t0 - 3600,
        lastFactId = "lon_apartment_mixdown", topics = {},
        profile = { cityId = "london", relationId = "old_friend", seedText = "fixture",
            isRandom = false, initialized = true },
        messages = {
            { id = 7001, role = "user", text = "还在混音吗？", serverTime = t0 - 8000,
                state = "replied", clockText = "23:10" },
        },
    }
    writeRawSave(SELFTEST_LIFE_LEGACY, legacy)
    LifeService.Load(t0)
    local adopted = LifeService.Active()
    check("AC1 无注册表但有旧档：收编为 life-1 且直接活跃（不弹初始化、不清历史）",
        adopted ~= nil and adopted.slotId == "life-1" and adopted.cityId == "london"
        and adopted.relationId == "old_friend" and LifeService.Count() == 1,
        string.format("段数 %d 活跃=%s", LifeService.Count(), tostring(adopted and adopted.slotId)))
    local copied = readRawSave(LifeService.SlotSaveFile("life-1"))
    check("AC2 收编把历史复制进 life-1 自己的段存档（旧文件留作只读备份，此后不再被读）",
        copied ~= nil and copied.messages ~= nil and copied.messages[1] ~= nil
        and copied.messages[1].text == "还在混音吗？",
        tostring(copied and copied.messages and #copied.messages or "无文件"))

    LifeService.CreateSlot("shanghai", "stranger", nil, t0 + 100)
    LifeService.CreateSlot("chengdu", "stranger", nil, t0 + 200)
    LifeService.OpenSlot("life-1", t0 + 300)
    LifeService.OpenSlot("life-2", t0 + 400)
    LifeService.OpenSlot("life-3", t0 + 500)
    LifeService.OpenSlot("life-2", t0 + 600)
    -- 模拟进程重启：内存全部清掉，一切以注册表文件为准
    reinitLife_()
    LifeService.Load(t0 + 700)
    local cold = LifeService.Active()
    local latest = LifeService.LatestOpened()
    check("AC3 冷启动重读注册表：活跃段仍是最后打开的 life-2",
        cold ~= nil and cold.slotId == "life-2", tostring(cold and cold.slotId))
    check("AC4 LatestOpened 按 lastOpenedUtc 取段（与冷启动同一条兜底路，life-3 停在 t0+500）",
        latest ~= nil and latest.slotId == "life-2"
        and LifeService.SlotById("life-3").lastOpenedUtc == math.floor(t0 + 500),
        string.format("latest=%s life-3=%s", tostring(latest and latest.slotId),
            tostring(LifeService.SlotById("life-3").lastOpenedUtc)))
    check("AC5 段文件与旧档路径全锁在自检前缀：不碰玩家 lives.json / m0-1 旧档",
        LifeService.SlotSaveFile("life-1") == "memory/life-selftest-1.json"
        and SELFTEST_LIFE_LEGACY == "memory/life-selftest-legacy.json",
        LifeService.SlotSaveFile("life-1"))
    resetLifeRegistry()
end

--- 场景 AD：16 个场景状态包声明齐、背景不复用、作息表永远落在真包上
local function ScenarioScenePackages(dateKey)
    logInfo("场景 AD 十六个场景状态包与作息表同源")
    local order = SceneService.SCENE_ORDER
    local hits = 0
    for i = 1, #order do
        if SceneService.PackageFor(order[i]) then
            hits = hits + 1
        end
    end
    check("AD1 四城 × 四场景型 = 16 个包，逐个声明在",
        #order == 16 and hits == 16, string.format("表 %d 命中 %d", #order, hits))

    local badFields = nil
    local dupPath = nil
    local seenPath = {}
    local typeCount = {}
    for i = 1, #order do
        local pkg = SceneService.PackageFor(order[i])
        typeCount[pkg.cityId .. "/" .. pkg.type] = (typeCount[pkg.cityId .. "/" .. pkg.type] or 0) + 1
        if seenPath[pkg.backgroundPath] then
            dupPath = pkg.id
        end
        seenPath[pkg.backgroundPath] = true
        local mm = pkg.microMotion
        local okFields = pkg.id == order[i] and pkg.backgroundKey == pkg.id
            and (pkg.type == "home" or pkg.type == "work" or pkg.type == "public" or pkg.type == "transit")
            and pkg.label ~= nil and pkg.label ~= ""
            and pkg.colorTemperature >= 2500 and pkg.colorTemperature <= 7000
            and pkg.keyLightDirection ~= nil and pkg.keyLightDirection.x ~= nil
            and pkg.keyLightDirection.y ~= nil and pkg.keyLightDirection.z ~= nil
            and pkg.characterPlacement ~= nil
            and (pkg.characterPlacement.side == "right" or pkg.characterPlacement.side == "left")
            and pkg.groundShadow ~= nil
            and pkg.groundShadow.anchorX > 0 and pkg.groundShadow.anchorX < 1
            and pkg.groundShadow.anchorY > 0 and pkg.groundShadow.anchorY < 1
            and pkg.groundShadow.rx > 0 and pkg.groundShadow.ry > 0
            and (mm == "breathe" or mm == "sway" or mm == "turn" or mm == "dolly")
            and pkg.traceAnchor ~= nil
            and pkg.traceAnchor.x > 0 and pkg.traceAnchor.x < 1
            and pkg.traceAnchor.y > 0 and pkg.traceAnchor.y < 1
            and pkg.traceAnchor.scale > 0 and pkg.traceAnchor.layer >= 1
            and pkg.future3D ~= nil and pkg.future3D.sceneRef == "scene/" .. pkg.id
            and pkg.future3D.anchorId ~= nil and pkg.future3D.anchorId ~= ""
        if not okFields and not badFields then
            badFields = pkg.id
        end
    end
    check("AD2 每个包字段齐：色温/主光向/站位/接地阴影/微动/痕迹锚点/future3D 全在",
        badFields == nil, tostring(badFields))
    local typesOk = true
    for ci = 1, #ProfileService.CITY_ORDER do
        local city = ProfileService.CITY_ORDER[ci]
        if (typeCount[city .. "/home"] or 0) ~= 1 or (typeCount[city .. "/work"] or 0) ~= 1
            or (typeCount[city .. "/public"] or 0) ~= 1 or (typeCount[city .. "/transit"] or 0) ~= 1 then
            typesOk = false
        end
    end
    check("AD3 每城四种各一不缺不重，16 条背景路径全局唯一（不复用错误背景）",
        typesOk and dupPath == nil, tostring(dupPath))

    local misses = ""
    for ci = 1, #ProfileService.CITY_ORDER do
        local city = ProfileService.CITY_ORDER[ci]
        for h = 0, 23 do
            local utc = TimeState.UtcAtLocal(city, dateKey, h, 0)
            local snap = TimeState.Snapshot(city, utc)
            if not SceneService.PackageFor(snap.sceneId) then
                misses = misses .. string.format(" %s@%02d→%s", city, h, tostring(snap.sceneId))
            end
        end
    end
    check("AD4 四城 24 小时作息快照 sceneId 全部落在真包上（作息表里没有第五景）",
        misses == "", misses)

    check("AD5 退役/不存在的场景 id 必须显式降级：StateFor 返回 nil，不拿旧图假称已切换",
        SceneService.StateFor("la_campus", nil) == nil
        and SceneService.StateFor("lon_cafe", nil) == nil
        and SceneService.StateFor("sha_jiaguan", nil) == nil)

    local vocabBad = nil
    for ci = 1, #ProfileService.CITY_ORDER do
        local cityId = ProfileService.CITY_ORDER[ci]
        local city = ProfileService.CityFor(cityId)
        for vi = 1, #city.sceneVocab do
            local pkg = SceneService.PackageFor(city.sceneVocab[vi])
            if not pkg or pkg.cityId ~= cityId then
                vocabBad = cityId .. ":" .. city.sceneVocab[vi]
            end
        end
    end
    check("AD6 档案 sceneVocab 与包同源：档案页可见场景全属该城的包（说的=画的）",
        vocabBad == nil, tostring(vocabBad))

    beginScenario()
    local occBad = ""
    local occChecked = 0
    for ci = 1, #ProfileService.CITY_ORDER do
        local cityId = ProfileService.CITY_ORDER[ci]
        local plan = EventService.PlanFor(cityId, dateKey)
        for i = 1, #plan.occurrences do
            local occ = plan.occurrences[i]
            occChecked = occChecked + 1
            if occ.traceKey and not SceneService.TraceFor(occ.traceKey) then
                occBad = occBad .. " trace:" .. occ.traceKey
            end
            if not SceneService.PackageFor(occ.sceneId) then
                occBad = occBad .. " scene:" .. tostring(occ.sceneId)
            end
        end
    end
    check("AD7 四城当日事件实例都带有效 traceKey 且 sceneId 落在包上（痕迹与画面同一份声明）",
        occBad == "" and occChecked >= 24, string.format("实例 %d%s", occChecked, occBad))
end

--- 场景 AE：2.5D 生活痕迹全生命周期（真链路绑定 / 去重 / 落盘往返 / 计划补挂 / 场景匹配）
local function ScenarioTraceBinding(dateKey)
    logInfo("场景 AE 生活痕迹生命周期")
    beginScenario()
    resetLifeRegistry()
    local t0 = TimeState.NowUtc()
    local slot = LifeService.CreateSlot("los_angeles", "stranger", nil, t0)
    reinit_(LifeService.SlotSaveFile("life-1"), slot)
    -- 真实交付链路：中午咖啡馆（fragments 档）发送，HandleDeliver 里 RefreshSnapshot
    -- 命中 ongoing 的 la_cafe_midday（traceKey=coffee），痕迹被活路径钉进槽里
    goLocalHour(12, dateKey)
    sendNow("中午的咖啡馆怎么样？")
    advance(30)
    local plan = EventService.PlanFor(cityId_, dateKey)
    ---@type EventOccurrence?
    local midday = nil
    for i = 1, #plan.occurrences do
        if plan.occurrences[i].templateId == "la_cafe_midday" then
            midday = plan.occurrences[i]
        end
    end
    local trace = LifeService.GetTrace()
    check("AE1 ongoing 关键事件经真实交付链路替换痕迹（与事件实例同一份键）",
        trace ~= nil and midday ~= nil and trace.occurrenceKey == midday.occurrenceKey
        and trace.traceKey == "coffee" and trace.sceneId == "la_cafe",
        string.format("trace=%s/%s", tostring(trace and trace.traceKey),
            tostring(trace and trace.occurrenceKey)))

    ---@type any
    local endedFact = { traceKey = "note", eventState = "ended", occurrenceKey = "la/ended-1",
        sceneId = "la_apartment", eventTitle = "睡下了", serverTime = TimeState.NowUtc() }
    ---@type any
    local plainFact = { eventState = "ongoing", occurrenceKey = "la/plain-1",
        sceneId = "la_studio", eventTitle = "非关键事件", serverTime = TimeState.NowUtc() }
    updateTrace_(endedFact)
    updateTrace_(plainFact)
    local kept = LifeService.GetTrace()
    check("AE2 已结束或无痕迹键的事件不动痕迹（只有 ongoing 的关键事件有替换权）",
        kept ~= nil and midday ~= nil and kept.occurrenceKey == midday.occurrenceKey)

    ---@type any
    local nextFact = { traceKey = "proofs", eventState = "ongoing", occurrenceKey = "la/layout-1",
        sceneId = "la_studio", eventTitle = "在工作室排版", serverTime = TimeState.NowUtc() }
    updateTrace_(nextFact)
    local bound = LifeService.GetTrace()
    check("AE3 下一个关键事件 ongoing：直接替换（最新为准，不叠痕）",
        bound ~= nil and bound.traceKey == "proofs" and bound.occurrenceKey == "la/layout-1"
        and bound.sceneId == "la_studio")

    ---@type any
    local sameFact = { traceKey = "proofs", eventState = "ongoing", occurrenceKey = "la/layout-1",
        sceneId = "la_studio", eventTitle = "在工作室排版", serverTime = TimeState.NowUtc() + 500 }
    updateTrace_(sameFact)
    check("AE4 同一事件实例反复扫到：occurrenceKey 去重，boundAt 不漂",
        bound ~= nil and LifeService.GetTrace().boundAtUtc == bound.boundAtUtc,
        string.format("%s vs %s", tostring(LifeService.GetTrace().boundAtUtc),
            tostring(bound and bound.boundAtUtc)))

    -- 注册表落盘往返：痕迹随 lives.json 走，重启后仍是 proofs@la_studio
    reinitLife_()
    LifeService.Load(TimeState.NowUtc())
    local revived = LifeService.GetTrace("life-1")
    check("AE5 痕迹随注册表落盘：进程重启读回仍是 proofs@la_studio",
        revived ~= nil and revived.traceKey == "proofs" and revived.sceneId == "la_studio"
        and revived.occurrenceKey == "la/layout-1",
        string.format("痕迹=%s", tostring(revived and revived.traceKey)))

    -- 旧档升级：槽里没有痕迹 → 按当日计划补挂最近一个已开始的关键事件
    LifeService.SetTrace("life-1", nil, TimeState.NowUtc())
    ensureTrace_()
    local snapNow = TimeState.Snapshot(cityId_, TimeState.NowUtc())
    ---@type EventOccurrence?
    local best = nil
    for i = 1, #plan.occurrences do
        local occ = plan.occurrences[i]
        if occ.traceKey and occ.startUtc <= snapNow.utcSec
            and (best == nil or occ.startUtc > best.startUtc) then
            best = occ
        end
    end
    local seeded = LifeService.GetTrace()
    check("AE6 旧档升级（无痕迹）：按当日计划补挂最近一个已开始的关键事件",
        best ~= nil and seeded ~= nil
        and seeded.occurrenceKey == best.occurrenceKey and seeded.traceKey == best.traceKey,
        string.format("补挂=%s 期望=%s", tostring(seeded and seeded.occurrenceKey),
            tostring(best and best.occurrenceKey)))

    ---@type any
    local pinned = { traceKey = "umbrella", occurrenceKey = "la/pinned-1",
        eventTitle = "手工钉住的痕迹", sceneId = "la_studio" }
    LifeService.SetTrace("life-1", pinned, TimeState.NowUtc())
    ensureTrace_()
    local pinnedBack = LifeService.GetTrace()
    check("AE7 槽里已有痕迹：补挂不覆盖（只补空）",
        pinnedBack ~= nil and pinnedBack.traceKey == "umbrella")

    -- 痕迹只出现在它绑定的那个场景（验收 4：换景不跟旧痕）
    local pkgStudio = SceneService.PackageFor("la_studio")
    local sSame = SceneService.StateFor("la_studio", pinned)
    local sAway = SceneService.StateFor("la_cafe", pinned)
    check("AE8 StateFor 按场景匹配痕迹：同一条在 la_studio 有锚点、在 la_cafe 一律没有",
        sSame ~= nil and sSame.recentTrace ~= nil and sSame.recentTrace.assetKey == "umbrella"
        and pkgStudio ~= nil and sSame.recentTrace.anchorX == pkgStudio.traceAnchor.x
        and sAway ~= nil and sAway.recentTrace == nil,
        string.format("同景=%s 异景=%s", tostring(sSame ~= nil and sSame.recentTrace ~= nil),
            tostring(sAway ~= nil and sAway.recentTrace ~= nil)))
end

--- 场景 AF：切换人生 / 重进后不残留旧城市、旧场景、旧痕迹
local function ScenarioSwitchNoResidue(dateKey)
    logInfo("场景 AF 切换人生后无残留")
    beginScenario()
    resetLifeRegistry()
    local t0 = TimeState.NowUtc()
    local slotA = LifeService.CreateSlot("los_angeles", "stranger", nil, t0)
    LifeService.CreateSlot("shanghai", "stranger", nil, t0 + 1)
    -- A 段跑出一条真链路：交付后自然带着中午咖啡馆的痕迹
    reinit_(LifeService.SlotSaveFile("life-1"), slotA)
    goLocalHour(12, dateKey)
    sendNow("你在咖啡馆吗？")
    advance(30)
    MemoryService.Persist(MessageService.GetMessages())
    local msgsA = #MessageService.GetMessages()
    -- 痕迹按槽读，不按注册表 active 读：CreateSlot(B) 会把 active 挪到 B，
    -- 而这一段会话挂的是 A 的存档。会话槽才是「A 自己的痕迹」（main.lua 的 SessionSlot）。
    local traceA = LifeService.GetTrace("life-1")
    -- 串写守卫：CreateSlot(B) 把注册表 active 挪到了 life-2，而会话挂的是 A 的存档。
    -- A 那条真链路跑出来的痕迹只许落在 A 身上，落进 B 就是完成标准 1「互不串写」失败
    -- （2026-09-25 本地引擎真跑自检时正是这样串过去的：痕迹写到了 active 段）。
    local activeNow = LifeService.Active()
    check("AF0 会话槽≠注册表 active 时痕迹只写会话槽",
        traceA ~= nil and traceA.traceKey ~= nil
        and activeNow ~= nil and activeNow.slotId == "life-2"
        and LifeService.GetTrace("life-2") == nil,
        string.format("active=%s A=%s B=%s", tostring(activeNow and activeNow.slotId),
            tostring(traceA and traceA.traceKey),
            tostring(LifeService.GetTrace("life-2")
                and LifeService.GetTrace("life-2").traceKey)))

    -- 切到 B：和 main.lua HandleSwitchLife 同一条链路——开段、挂该段存档、从头恢复
    local slotB = LifeService.OpenSlot("life-2", t0 + 3)
    reinit_(LifeService.SlotSaveFile("life-2"), slotB)
    local restoredB = MessageService.Restore(MemoryService.GetRestoredMessages())
    local snapB = TimeState.Snapshot("shanghai", TimeState.NowUtc())
    check("AF1 刚切过去：聊天是空的、档案是上海（A 的记录与城市都没跟来）",
        #MessageService.GetMessages() == 0 and restoredB == 0
        and ProfileService.GetCityId() == "shanghai",
        string.format("条数 %d 恢复 %d 城市=%s", #MessageService.GetMessages(),
            restoredB, ProfileService.GetCityId()))
    -- 前缀判定用 sub 不用 find("^sha_",1,true)：plain=true 时 "^" 是字面字符，
    -- 锚住不了开头，永远匹配不上（2026-09-25 本地引擎真跑自检把这条假失败暴露出来）。
    check("AF2 B 段画面没有旧景旧痕：作息场景是上海的包、活跃段痕迹为空",
        LifeService.GetTrace("life-2") == nil
        and snapB.sceneId:sub(1, 4) == "sha_"
        and SceneService.PackageFor(snapB.sceneId) ~= nil,
        string.format("场景=%s B痕=%s A痕还在=%s", snapB.sceneId,
            tostring(LifeService.GetTrace("life-2")),
            tostring(LifeService.GetTrace("life-1")
                and LifeService.GetTrace("life-1").traceKey)))

    -- 回 A：先模拟进程重启读注册表，再挂 A 段存档
    reinitLife_()
    LifeService.Load(TimeState.NowUtc())
    local slotA2 = LifeService.OpenSlot("life-1", TimeState.NowUtc())
    reinit_(LifeService.SlotSaveFile("life-1"), slotA2)
    MessageService.Restore(MemoryService.GetRestoredMessages())
    local traceA2 = LifeService.GetTrace("life-1")
    check("AF3 回到 life-1：聊天条数原样恢复、档案仍是洛杉矶（城市不跟着最后停留的段走）",
        #MessageService.GetMessages() == msgsA and ProfileService.GetCityId() == "los_angeles"
        and MemoryService.GetLifeId() == "life-1",
        string.format("条数 %d/%d", #MessageService.GetMessages(), msgsA))
    check("AF4 回到 life-1：痕迹仍是 A 段自己那条（B 没有痕迹，切换不把它抹掉也不借用）",
        (traceA2 ~= nil) == (traceA ~= nil)
        and (traceA == nil or (traceA2.traceKey == traceA.traceKey
            and traceA2.occurrenceKey == traceA.occurrenceKey)),
        string.format("A=%s 回来=%s", tostring(traceA and traceA.traceKey),
            tostring(traceA2 and traceA2.traceKey)))
    local rawA = readRawSave(LifeService.SlotSaveFile("life-1"))
    local rawB = readRawSave(LifeService.SlotSaveFile("life-2"))
    check("AF5 两段存档文件各自只有各自的历史：来回切一次 A 不变、B 没被写过内容",
        rawA ~= nil and rawA.messages ~= nil and #rawA.messages == msgsA
        and (rawB == nil or rawB.messages == nil or #rawB.messages == 0),
        string.format("A=%d B=%s", msgsA,
            tostring(rawB and rawB.messages and #rawB.messages or "无")))
    resetLifeRegistry()
end

--- 建档/换卡时选的关系起点与种子必须进段存档。
--- 2026-09-25 换卡跨进程取证（`.tmp/poc/m4_replace_d.lua` / `_e.lua`）实测：`MemoryService.SetProfile`
--- 原先只有开发测试台 `ApplyProfile` 一个调用点，新故事那条路只 `ProfileService.Set` 进内存，
--- 于是第一次落盘的存档「带记录却没有 profile」，下一次读取命中旧档迁移兜底补成
--- 「本城 × 陌生网友」——用 前同事/高中同学/久未联系的朋友 建的段，重进之后关系就变了，
--- 档案页「关系起点」那行与回复的关系语气壳跟着错，seedText 也丢。
---@param dateKey string
local function ScenarioRelationPersisted(dateKey)
    logInfo("场景 AG 建档关系落盘")
    beginScenario()
    resetLifeRegistry()
    local t0 = TimeState.NowUtc()
    LifeService.CreateSlot("chengdu", "ex_colleague", { seedText = "chengdu|ex_colleague" }, t0)
    local slot = LifeService.OpenSlot("life-1", t0)
    reinit_(LifeService.SlotSaveFile("life-1"), slot)
    goLocalHour(12, dateKey)
    sendNow("下班一起走吗？")
    advance(30)
    MemoryService.Persist(MessageService.GetMessages())

    local raw = readRawSave(LifeService.SlotSaveFile("life-1"))
    local p = raw and raw.profile or nil
    check("AG0 建档时选的关系与种子写进了段存档",
        p ~= nil and p.cityId == "chengdu" and p.relationId == "ex_colleague"
        and tostring(p.seedText) == "chengdu|ex_colleague",
        string.format("存档=%s/%s/%s 卡片=%s/%s", tostring(p and p.cityId),
            tostring(p and p.relationId), tostring(p and p.seedText),
            tostring(slot.cityId), tostring(slot.relationId)))

    -- 再走一次「重启读盘」：档案必须从存档接回建段时那条关系，而不是被兜底改成陌生网友
    reinitLife_()
    LifeService.Load(TimeState.NowUtc())
    local again = LifeService.OpenSlot("life-1", TimeState.NowUtc())
    reinit_(LifeService.SlotSaveFile("life-1"), again)
    local memProfile = MemoryService.GetProfile()
    check("AG1 重进后关系起点还是建段时选的那条（回复用的也是这条关系的壳）",
        ProfileService.GetRelationId() == "ex_colleague"
        and again ~= nil and again.relationId == "ex_colleague"
        and memProfile ~= nil and memProfile.relationId == "ex_colleague",
        string.format("内存=%s 卡片=%s 存档=%s", ProfileService.GetRelationId(),
            tostring(again and again.relationId),
            tostring(memProfile and memProfile.relationId)))
    resetLifeRegistry()
end

--- 该城当天的事件事实是否落在本城可见的场景里（「事件/场景事实用同一对选择值」的判据）。
---@param cityId string
---@param sceneId string
---@return boolean
local function SceneBelongsToCity(cityId, sceneId)
    local city = ProfileService.CityFor(cityId)
    local vocab = city and city.sceneVocab or nil
    if not vocab or type(sceneId) ~= "string" then
        return false
    end
    for i = 1, #vocab do
        if vocab[i] == sceneId then
            return true
        end
    end
    return false
end

--- 快照一张卡片的全部档案字段，用来证明「替换只动点选那张卡」。
---@param slotId string
---@return string
local function SlotFingerprint(slotId)
    local slot = LifeService.SlotById(slotId)
    if not slot then
        return "缺失"
    end
    return string.format("%s|%s|%s|%s|%d|%d|%s",
        slot.cityId, slot.relationId, slot.seedText, tostring(slot.isRandom),
        slot.createdAtUtc, slot.lastOpenedUtc,
        slot.trace and slot.trace.occurrenceKey or "无痕迹")
end

--- 场景 AH（M5「可控的新故事」）：显式选的城市×关系必须 100% 落地，随机只在随机入口生效。
--- 缺陷原形：预览里点「上海 × 前同事」，落成「成都 × 高中同学」——
--- 选择层丢点击（OnClick 撞布局位移）与段存档里的旧档案盖掉刚建的卡片，两条都被这里堵住。
local function ScenarioExplicitStoryAdopted(dateKey)
    logInfo("场景 AH 显式选择落地与随机入口独占")
    beginScenario()
    local t0 = TimeState.NowUtc()

    -- 一、显式「上海 × 前同事」：卡片 / 当前档案 / 段存档 profile 三处必须同一对
    resetLifeRegistry()
    local sha = LifeService.CreateSlot("shanghai", "ex_colleague", nil, t0)
    reinit_(LifeService.SlotSaveFile("life-1"), sha, true)
    goLocalHour(15, dateKey)
    local rawSha = readRawSave(LifeService.SlotSaveFile("life-1"))
    local profSha = rawSha and rawSha.profile or nil
    check("AH0 显式建「上海×前同事」：卡片/当前档案/段存档 profile 三处同一对",
        sha ~= nil and sha.cityId == "shanghai" and sha.relationId == "ex_colleague"
        and ProfileService.GetCityId() == "shanghai"
        and ProfileService.GetRelationId() == "ex_colleague"
        and profSha ~= nil and profSha.cityId == "shanghai"
        and profSha.relationId == "ex_colleague",
        string.format("卡片=%s/%s 档案=%s/%s 存档=%s/%s",
            tostring(sha and sha.cityId), tostring(sha and sha.relationId),
            ProfileService.GetCityId(), ProfileService.GetRelationId(),
            tostring(profSha and profSha.cityId), tostring(profSha and profSha.relationId)))
    check("AH1 聊天顶部标签与档案页那行都读这一对（同源，没有第二处默认值）",
        ProfileService.ProfileLine() == "Former colleague · Shanghai"
        and ProfileService.RelationCityLine():find("Former colleague × Shanghai", 1, true) ~= nil,
        ProfileService.ProfileLine())

    local factSha = EventService.FactFor("shanghai", TimeState.NowUtc())
    check("AH2 事件事实的场景属于上海（事件/场景不跟着别的城或旧指针走）",
        factSha ~= nil and SceneBelongsToCity("shanghai", factSha.sceneId),
        factSha and (tostring(factSha.sceneId) .. "/" .. tostring(factSha.id)) or "无事实")

    -- 二、非随机入口绝不随机：isRandom=false，seedText 就是选定的那一对
    check("AH3 非随机入口不抽档：isRandom=false 且 seedText=上海|前同事",
        sha ~= nil and sha.isRandom == false and sha.seedText == "shanghai|ex_colleague",
        string.format("随机=%s 种子=%s", tostring(sha and sha.isRandom),
            tostring(sha and sha.seedText)))

    -- 三、重启读回：显式那一对落在磁盘上，重进不许变成别的对
    reinitLife_()
    LifeService.Load(TimeState.NowUtc())
    local againSha = LifeService.OpenSlot("life-1", TimeState.NowUtc())
    reinit_(LifeService.SlotSaveFile("life-1"), againSha)
    check("AH4 重进后读回的还是上海×前同事（不重抽、不被兜底改掉）",
        againSha ~= nil and againSha.cityId == "shanghai"
        and againSha.relationId == "ex_colleague"
        and ProfileService.GetCityId() == "shanghai"
        and ProfileService.GetRelationId() == "ex_colleague",
        string.format("卡片=%s/%s 档案=%s/%s",
            tostring(againSha and againSha.cityId), tostring(againSha and againSha.relationId),
            ProfileService.GetCityId(), ProfileService.GetRelationId()))

    -- 四、反向对照「成都 × 高中同学」：两城的默认关系恰好互换（上海=高中同学、成都=前同事），
    -- 任何一处残留默认值都会在这一条上暴露，不会被上一条掩盖
    resetLifeRegistry()
    local cdu = LifeService.CreateSlot("chengdu", "classmate", nil, t0 + 60)
    reinit_(LifeService.SlotSaveFile("life-1"), cdu, true)
    local rawCdu = readRawSave(LifeService.SlotSaveFile("life-1"))
    local profCdu = rawCdu and rawCdu.profile or nil
    check("AH5 显式建「成都×高中同学」同样三处落地（反向对照互换默认关系）",
        cdu ~= nil and cdu.cityId == "chengdu" and cdu.relationId == "classmate"
        and ProfileService.GetCityId() == "chengdu"
        and ProfileService.GetRelationId() == "classmate"
        and ProfileService.ProfileLine() == "School friend · Chengdu"
        and profCdu ~= nil and profCdu.cityId == "chengdu"
        and profCdu.relationId == "classmate",
        string.format("档案=%s/%s 标签=%s 存档=%s/%s",
            ProfileService.GetCityId(), ProfileService.GetRelationId(),
            ProfileService.ProfileLine(),
            tostring(profCdu and profCdu.cityId), tostring(profCdu and profCdu.relationId)))

    -- 五、脏 id 宁可不建：不能悄悄回落成「洛杉矶×陌生网友」
    local before = LifeService.Count()
    local dirty, dirtyReason = LifeService.CreateSlot("atlantis", "ex_colleague", nil, t0 + 120)
    local dirtyRel, dirtyRelReason = LifeService.CreateSlot("shanghai", "school_buddy", nil, t0 + 121)
    check("AH6 不在四城×四关系矩阵里的 id 直接拒建（不回落成默认档案）",
        dirty == nil and dirtyReason == "invalid" and dirtyRel == nil
        and dirtyRelReason == "invalid" and LifeService.Count() == before,
        string.format("理由=%s/%s 段数=%d→%d", tostring(dirtyReason),
            tostring(dirtyRelReason), before, LifeService.Count()))

    -- 六、新故事挂载前必须作废该路径上残留的旧段内容（段存档 profile 盖掉卡片那条洞）
    MemoryService.Init({ cityId = "chengdu", saveFile = SELFTEST_SAVE, lifeId = "life-1" })
    MemoryService.SetProfile({
        cityId = "chengdu", relationId = "classmate", seedText = "stale",
        isRandom = false, initialized = true,
    })
    MemoryService.Save()
    MemoryService.Init({ cityId = "shanghai", saveFile = SELFTEST_SAVE, lifeId = "life-2" })
    local wiped = MemoryService.ResetForNewLife()
    check("AH7 新故事挂载前作废旧段存档：档案与消息不残留、lifeId 归属保留",
        wiped and MemoryService.GetProfile() == nil
        and #MemoryService.Get().messages == 0
        and MemoryService.GetLifeId() == "life-2",
        string.format("档案=%s 消息=%d lifeId=%s",
            tostring(MemoryService.GetProfile() and MemoryService.GetProfile().cityId),
            #MemoryService.Get().messages, tostring(MemoryService.GetLifeId())))

    -- 七、满三段后的替换：只动用户点选那张卡，另两槽逐字段不变
    resetLifeRegistry()
    LifeService.CreateSlot("los_angeles", "stranger", { seedText = "la|stranger" }, t0 + 200)
    local slot2 = LifeService.CreateSlot("london", "old_friend", { seedText = "lon|old_friend" }, t0 + 201)
    LifeService.CreateSlot("chengdu", "ex_colleague", { seedText = "cdu|ex_colleague" }, t0 + 202)
    -- 先让 life-2 真的带上「伦敦×久未联系的朋友」这段历史，替换才有东西可作废
    reinit_(LifeService.SlotSaveFile("life-2"), slot2)
    MemoryService.Save()
    local fp1 = SlotFingerprint("life-1")
    local fp3 = SlotFingerprint("life-3")
    local cleared = LifeService.ClearSlotSaveFile("life-2")
    local rawCleared = readRawSave(LifeService.SlotSaveFile("life-2"))
    local rep = LifeService.ReplaceSlot("life-2", "shanghai", "ex_colleague",
        { seedText = "shanghai|ex_colleague" }, t0 + 300)
    reinit_(LifeService.SlotSaveFile("life-2"), rep, true)
    local rawRep = readRawSave(LifeService.SlotSaveFile("life-2"))
    local profRep = rawRep and rawRep.profile or nil
    check("AH8 满三段替换：旧段存档作废，目标槽换成新选择（卡片与存档同一对）",
        rep ~= nil and rep.slotId == "life-2" and rep.cityId == "shanghai"
        and rep.relationId == "ex_colleague" and rep.isRandom == false
        and cleared
        and (rawCleared == nil or (rawCleared.profile == nil and rawCleared.messages == nil))
        and ProfileService.GetCityId() == "shanghai"
        and ProfileService.GetRelationId() == "ex_colleague"
        and profRep ~= nil and profRep.cityId == "shanghai"
        and profRep.relationId == "ex_colleague",
        string.format("清理=%s 清后文件=%s 卡片=%s/%s 存档=%s/%s", tostring(cleared),
            tostring(rawCleared == nil and "已无" or "仍在"),
            tostring(rep and rep.cityId), tostring(rep and rep.relationId),
            tostring(profRep and profRep.cityId), tostring(profRep and profRep.relationId)))
    check("AH9 替换只动那一张卡：life-1 与 life-3 逐字段不变",
        fp1 == SlotFingerprint("life-1") and fp3 == SlotFingerprint("life-3")
        and LifeService.Count() == 3,
        string.format("前=[%s | %s] 后=[%s | %s]", fp1, fp3,
            SlotFingerprint("life-1"), SlotFingerprint("life-3")))

    -- 八、随机入口仍然可复现：同一创建秒同一结果，seedText 带上抽中的那一对
    local pickA = ProfileService.RandomPick(RANDOM_SEC_0)
    local pickB = ProfileService.RandomPick(RANDOM_SEC_0)
    check("AH10 随机入口仍按既有 seedText 可复现（同秒同结果，两轴都同）",
        pickA.cityId == pickB.cityId and pickA.relationId == pickB.relationId
        and pickA.seedText == pickB.seedText
        and ProfileService.IsValidCityId(pickA.cityId)
        and ProfileService.IsValidRelationId(pickA.relationId)
        and pickA.seedText:find(pickA.cityId .. "|" .. pickA.relationId, 1, true) ~= nil,
        string.format("%s/%s 种子=%s", pickA.cityId, pickA.relationId, pickA.seedText))
    resetLifeRegistry()
end

-- ---------------------------------------------------------------------------
-- 场景 AJ（M7）：四城事件四件套。每城只有一条关键事件；线索、可问方向、
-- 固定事实和事后痕迹必须挂同一 occurrenceKey。普通日程不会抢走当前痕迹。
-- ---------------------------------------------------------------------------
local function ScenarioM7FourPieceCards(dateKey)
    logInfo("场景 AJ M7 四城事件四件套")
    beginScenario()
    local expected = {
        los_angeles = "la_cafe_open_mic",
        shanghai = "sha_bookstore_evening",
        chengdu = "cdu_nightmarket_supper",
        london = "lon_recordshop_shift",
    }
    local cards = M7EventService.M7Cards()
    local bad = ""
    for cityId, templateId in pairs(expected) do
        local card = cards[cityId]
        local plan = EventService.PlanFor(cityId, dateKey)
        ---@type any
        local occurrence = nil
        for i = 1, #plan.occurrences do
            if plan.occurrences[i].templateId == templateId then
                occurrence = plan.occurrences[i]
                break
            end
        end
        local fieldsOk = card ~= nil and card.templateId == templateId
            and type(card.id) == "string" and card.id ~= ""
            and type(card.clue) == "string" and card.clue ~= ""
            and type(card.questionHints) == "table" and #card.questionHints > 0
            and type(card.answer) == "string" and card.answer ~= ""
            and type(card.forbidden) == "string" and card.forbidden ~= ""
            and type(card.traceLifecycle) == "string" and card.traceLifecycle ~= ""
        local occurrenceOk = occurrence ~= nil and occurrence.isM7KeyEvent == true
            and occurrence.m7CardId == card.id and occurrence.traceKey ~= nil
            and occurrence.clue == card.clue
        if not (fieldsOk and occurrenceOk) then
            bad = bad .. " " .. cityId
        end
    end
    check("AJ1 四城各一张完整事件卡，计划实例带同一张卡与有效痕迹", bad == "", bad)

    local laPlan = EventService.PlanFor("los_angeles", dateKey)
    ---@type any
    local laKey = nil
    for i = 1, #laPlan.occurrences do
        if laPlan.occurrences[i].isM7KeyEvent then
            laKey = laPlan.occurrences[i]
            break
        end
    end
    local regenerated = EventService.Regenerate("los_angeles", dateKey)
    ---@type any
    local regeneratedKey = nil
    for i = 1, #regenerated.occurrences do
        if regenerated.occurrences[i].isM7KeyEvent then
            regeneratedKey = regenerated.occurrences[i]
            break
        end
    end
    check("AJ2 同城同日重算仍是同一关键事件实例键与卡片（不重复产出）",
        laKey ~= nil and regeneratedKey ~= nil
        and laKey.occurrenceKey == regeneratedKey.occurrenceKey
        and laKey.m7CardId == regeneratedKey.m7CardId,
        string.format("%s / %s", tostring(laKey and laKey.occurrenceKey),
            tostring(regeneratedKey and regeneratedKey.occurrenceKey)))

    -- 真正走一次存档→服务重建：M7 字段可由旧计划补齐，但实例键绝不随升级变化。
    MemoryService.SetEventPlans(EventService.ExportPlans())
    MemoryService.Save()
    reinit_(SELFTEST_SAVE)
    local restoredPlan = EventService.PeekPlan("los_angeles", dateKey)
    ---@type any
    local restoredKey = nil
    if restoredPlan then
        for i = 1, #restoredPlan.occurrences do
            if restoredPlan.occurrences[i].templateId == "la_cafe_open_mic" then
                restoredKey = restoredPlan.occurrences[i]
                break
            end
        end
    end
    check("AJ2b 离线重进接管同一关键实例并保留四件套字段",
        restoredPlan ~= nil and restoredPlan.fromSave == true and restoredKey ~= nil
        and regeneratedKey ~= nil and restoredKey.occurrenceKey == regeneratedKey.occurrenceKey
        and restoredKey.m7CardId == regeneratedKey.m7CardId and restoredKey.clue ~= "",
        string.format("fromSave=%s key=%s", tostring(restoredPlan and restoredPlan.fromSave),
            tostring(restoredKey and restoredKey.occurrenceKey)))

    if regeneratedKey then
        ---@type any
        local during = EventService.FactFor("los_angeles", regeneratedKey.startUtc + 60)
        local known = ContentService.Reply(during, "开放麦什么时候开始？", 91)
        local unknown = ContentService.Reply(during, "你今天认识了谁？", 92)
        check("AJ3 线索与已知发问走关键事件事实，未知自由输入不假装精准理解",
            during.isM7KeyEvent == true and during.occurrenceKey == regeneratedKey.occurrenceKey
            and known:find(during.m7Answer, 1, true) ~= nil
            and unknown:find("What I can tell you is", 1, true) ~= nil,
            string.format("known=%s unknown=%s", known, unknown))

        local before = M7EventService.LatestCompletedKeyEvent("los_angeles", regeneratedKey.endUtc - 1)
        local after = M7EventService.LatestCompletedKeyEvent("los_angeles", regeneratedKey.endUtc + 1)
        check("AJ4 关键事件结束前不留事后痕迹，结束后只返回该实例作为替换源",
            before == nil and after ~= nil and after.occurrenceKey == regeneratedKey.occurrenceKey
            and after.traceKey == regeneratedKey.traceKey,
            string.format("before=%s after=%s", tostring(before and before.occurrenceKey),
                tostring(after and after.occurrenceKey)))

        resetLifeRegistry()
        local slot = LifeService.CreateSlot("los_angeles", "stranger", nil, regeneratedKey.endUtc + 1)
        reinit_(LifeService.SlotSaveFile("life-1"), slot)
        local afterFact = EventService.FactFor("los_angeles", regeneratedKey.endUtc + 1)
        updateTrace_(afterFact)
        local bound = LifeService.GetTrace("life-1")
        local routineFact = EventService.FactFor("los_angeles", regeneratedKey.endUtc + 1801)
        updateTrace_(routineFact)
        local kept = LifeService.GetTrace("life-1")
        check("AJ5 事后痕迹写入人生槽后，后续普通日程不能覆盖；换段/重进可持久化",
            bound ~= nil and bound.isM7KeyEvent == true
            and bound.occurrenceKey == regeneratedKey.occurrenceKey
            and kept ~= nil and kept.occurrenceKey == regeneratedKey.occurrenceKey,
            string.format("bound=%s kept=%s", tostring(bound and bound.occurrenceKey),
                tostring(kept and kept.occurrenceKey)))
        resetLifeRegistry()
    end
end

-- ---------------------------------------------------------------------------
-- 场景 AI（M2-B 路径 A）：LLM 中继的客户端一侧 —— 信封契约、应答配对、超时与断线结清。
-- 全程不碰网络，本地就能验那条底线：网络怎么坏，她也永远有回话（回落模板）。
-- 服务端一侧（HTTP 出站、限流、上游解析）刻意不在客户端自检里跑：network/Server.lua
-- 带 .meta c_or_s="s"，客户端根本加载不到它——这正是要的性质，不是覆盖缺口。
-- ---------------------------------------------------------------------------
local function ScenarioRelayContract()
    logInfo("场景 AI LLM 中继客户端：信封、配对、超时、断线")

    local Shared = require("network.Shared")
    local RelayClient = require("network.Client")

    -- 一、信封往返：白名单 payload 编码再解码必须同构；超限直接拒绝（不发出去）
    local payload = { v = 1, userMessage = "今天有点累", core = { cityLabel = "洛杉矶" } }
    local json, why = Shared.EncodePayload(payload)
    check("AI1 白名单 payload 编码成功且不为空", json ~= nil and #json > 0, tostring(why))
    local back, backWhy = Shared.DecodePayload(json or "")
    check("AI2 解码后与原文同构（嵌套字段不丢）",
        type(back) == "table" and back.userMessage == "今天有点累"
        and type(back.core) == "table" and back.core.cityLabel == "洛杉矶",
        tostring(backWhy))
    local bigJson, bigWhy = Shared.EncodePayload(
        { userMessage = string.rep("字", Shared.MAX_PAYLOAD_BYTES) })
    check("AI3 超尺寸 payload 被拒（不发出去，也不当成网络错误）",
        bigJson == nil and bigWhy == "payload_too_large", tostring(bigWhy))

    -- 二、真路由：没有服务器连接时必须同步回落，绝不挂起（挂起会把 FIFO 拖住）
    RelayClient.ResetForTest()
    ---@type PolishTransportResult|nil
    local syncResult = nil
    RelayClient.RequestForTest(payload, function(result)
        syncResult = result
    end)
    check("AI4 无连接时 transport 同步回落 no_connection（不挂起、不抛异常）",
        syncResult ~= nil and syncResult.ok == false and syncResult.category == "no_connection",
        syncResult and tostring(syncResult.category) or "未回调")

    -- 三、应答配对：喂一条应答，回调必须拿到 bodyText；配不上的 id 不许二次回调
    local clock = 1000
    RelayClient.SetClockForTest(function()
        return clock
    end)
    ---@type PolishTransportResult|nil
    local got = nil
    local hits = 0
    local rid = RelayClient.EnqueueForTest("{}", function(result)
        hits = hits + 1
        got = result
    end)
    RelayClient.FeedReplyForTest(rid, true, 200, '{"segments":["好。"]}', "")
    check("AI5 应答按 requestId 配回槽位并带 bodyText",
        hits == 1 and got ~= nil and got.ok == true and got.status == 200
        and got.bodyText == '{"segments":["好。"]}',
        got and tostring(got.bodyText) or "无结果")
    RelayClient.FeedReplyForTest(rid, true, 200, '{"segments":["迟到。"]}', "")
    check("AI6 同一 requestId 的迟到应答不二次回调", hits == 1, "回调 " .. tostring(hits) .. " 次")

    -- 四、网络层超时：到点结清；结清之后的应答同样不许回写
    local timeouts = 0
    local r2 = RelayClient.EnqueueForTest("{}", function(result)
        timeouts = timeouts + 1
        got = result
    end)
    RelayClient.Update()
    check("AI7 未到 7 秒不误判超时", timeouts == 0 and RelayClient.GetPendingCount() == 1,
        "在途 " .. tostring(RelayClient.GetPendingCount()))
    clock = clock + 8
    RelayClient.Update()
    check("AI8 超 7 秒按 timeout 结清（不留悬挂槽位）",
        timeouts == 1 and got ~= nil and got.category == "timeout"
        and RelayClient.GetPendingCount() == 0,
        got and tostring(got.category) or "无结果")
    RelayClient.FeedReplyForTest(r2, true, 200, "{}", "")
    check("AI9 超时后的迟到应答作废（不二次回调）", timeouts == 1,
        "回调 " .. tostring(timeouts) .. " 次")

    -- 五、断线：在途请求一次性结清，不等各自耗满 7 秒
    local dropped = 0
    RelayClient.EnqueueForTest("{}", function(result)
        dropped = dropped + 1
        got = result
    end)
    RelayClient.EnqueueForTest("{}", function(result)
        dropped = dropped + 1
    end)
    local cleared = RelayClient.FailPendingForTest("disconnected")
    check("AI10 断线时批量结清在途请求（category=disconnected）",
        cleared == 2 and dropped == 2 and got ~= nil and got.category == "disconnected"
        and RelayClient.GetPendingCount() == 0,
        string.format("结清 %d 回调 %d", cleared, dropped))

    RelayClient.ResetForTest()
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
        failures_[#failures_ + 1] = string.format("场景 %s 抛出：%s", name, tostring(err))
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

--- 失败断言明细（label + detail，含整条场景抛出）。设备上与逐条 logError 同源，
--- 但本地引擎运行时 print/log 不落盘，PoC 只能靠这个接口取到「AF×2 到底是哪两条」。
---@return string[]
function DevSelfTest.Failures()
    return failures_
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
    updateTrace_ = options.updateTrace
    ensureTrace_ = options.ensureTrace
    reinitLife_ = options.reinitLife
    passed_ = 0
    failed_ = 0
    done_ = {}
    bad_ = {}
    failures_ = {}
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
    runScenario("AA", ScenarioElizaRules, dateKey)
    -- M2-B 润色：R 验适配层契约与全量回落（假 transport），S 验在途 FIFO 与预算，
    -- T 验开启态下真实队列链路（HandleDeliver）与 M2-A 时序不冲突
    runScenario("R", ScenarioPolishContract, dateKey)
    runScenario("S", ScenarioPolishFifo, dateKey)
    runScenario("T", ScenarioPolishQueueFlow, dateKey)
    -- M3 四城与档案：U 时区表、V/W 两个 DST 边界（纯函数，不动服务状态），
    -- X 随机入口持久化，Y 四城核心链路（排队/引用/落盘重进）逐城跑，Z v4 旧档迁移。
    -- Z 放最后：它往自检存档写 v4 夹具，跑完 Run 收尾的 ClearSavedData 会一并清掉。
    runScenario("U", ScenarioFourCityTime, dateKey)
    runScenario("V", ScenarioLaDstBoundary, dateKey)
    runScenario("W", ScenarioLondonDstBoundary, dateKey)
    runScenario("X", ScenarioRandomPersistence, dateKey)
    runScenario("Y", ScenarioCityConsistency, dateKey)
    runScenario("Z", ScenarioV4Migration, dateKey)
    -- M4：AB 人生槽互不串写、AC 冷启动与旧档收编、AD 十六场景包、
    -- AE 生活痕迹生命周期、AF 切换人生无残留。AB 起各场景先清人生注册表，跑完 Run 收尾再整体清一遍。
    runScenario("AB", ScenarioLifeIsolation, dateKey)
    runScenario("AC", ScenarioColdStartLegacy, dateKey)
    runScenario("AD", ScenarioScenePackages, dateKey)
    runScenario("AE", ScenarioTraceBinding, dateKey)
    runScenario("AF", ScenarioSwitchNoResidue, dateKey)
    runScenario("AG", ScenarioRelationPersisted, dateKey)
    runScenario("AH", ScenarioExplicitStoryAdopted, dateKey)
    runScenario("AJ", ScenarioM7FourPieceCards, dateKey)
    -- M2-B 路径 A：中继客户端一侧的信封/配对/超时/断线结清（全程无网络）
    runScenario("AI", ScenarioRelayContract, dateKey)

    MemoryService.ClearSavedData()
    -- M4 场景的注册表与段文件同理收尾清掉：自检不在设备上留人生
    reinitLife_()
    LifeService.ClearAll()
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
