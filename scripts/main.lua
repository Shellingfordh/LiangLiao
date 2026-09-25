-- ============================================================================
-- 《送给你这个回来的人》M1 首个可玩闭环（建在已验收的 M0-1 竖切片之上）
-- 竖屏手机：固定镜头 4:3 状态窗 + 真实时间驱动的生活状态 + 会排队的聊天闭环。
-- 后端 = 同工程内的 Lua 服务（消息/事件/内容/记忆/润色适配/开发自检）。M2-B：LLM 网关
-- 在独立的 gateway/ 目录且未部署；GatewayEnabled=false 时运行时零外发，回复仍是本地模板。
-- M1 新增：忙碌与睡眠时消息按 FIFO 排队到下一个可回复窗口；重进恢复完整记录与队列；
-- 回复只引用「送达时刻」与「交付时刻」两个确定时间快照里的事实。
-- 日志前缀仍留 [M0-1]：AGENTS.md 把它当作「已进入 Lua」的判据字符串。
-- ============================================================================

local UI = require("urhox-libs/UI")
local StatusWindow = require("StatusWindow")
local TimeState = require("TimeState")
local MessageService = require("services.MessageService")
local EventService = require("services.EventService")
local ContentService = require("services.ContentService")
local MemoryService = require("services.MemoryService")
local PolishService = require("services.PolishService")
local DevSelfTest = require("services.DevSelfTest")
local ChatPanel = require("ui.ChatPanel")
local DevTestPanel = require("ui.DevTestPanel")
local ProfileService = require("ProfileService")
local ProfileOverlay = require("ui.ProfileOverlay")
local SceneService = require("SceneService")
local LifeService = require("services.LifeService")
local SettingsOverlay = require("ui.SettingsOverlay")
local ProfilePageOverlay = require("ui.ProfilePageOverlay")
local LifeCardsOverlay = require("ui.LifeCardsOverlay")

---@type {Title: string, City: string, ReplyWaitSeconds: integer, DevTools: boolean, UseCloudMemory: boolean, DevSelfTest: boolean, AwaySummaryMinSeconds: integer, GatewayEnabled: boolean}
local CONFIG = {
    Title = "送给你这个回来的人",
    City = "los_angeles",        -- 干净安装的初始城市；存档/换档案后的城市走 ProfileService
    ReplyWaitSeconds = 10,   -- 空闲档的固定等待（M0-1 验收过的那条链路）
    DevTools = false,        -- 正式体验不展示覆盖式测试台；需验收时再显式打开
    UseCloudMemory = false,  -- 预览不绑定云存储，只保留异步接口
    DevSelfTest = true,      -- 启动时跑一次真实服务自检（busy/offline/idle + FIFO + 重进）
    AwaySummaryMinSeconds = 60, -- 离开超过这个时长才给一条「离开期间」摘要
    -- M2-B S1：网关与适配层已就位，但客户端 HTTP 被平台屏蔽（引擎文档 http.md），
    -- 真正接入要等「Maker 多人房服务端中转 + TapTap URL 白名单」这条路径被确认。
    -- 置 false 时 HandleDeliver 的行为与 M2-A 完全一致（同步模板回复）。
    GatewayEnabled = false,
}

--- 事件实例的生命周期上屏文案：状态窗注释行与回复共用同一套说法
---@type table<string, string>
local EVENT_STATE_LABEL = {
    upcoming = "还没开始",
    ongoing = "正在进行",
    ended = "已经收了",
}

---@type Widget|nil
local uiRoot_ = nil
---@type Widget|nil
local preview_ = nil
---@type Widget|nil
local traceImage_ = nil
---@type number
local frameW_ = 0
---@type number
local frameH_ = 0
---@type Label|nil
local infoClockLabel_ = nil
---@type Label|nil
local infoCityLabel_ = nil
---@type Label|nil
local infoPlaceLabel_ = nil
---@type Label|nil
local infoStateLabel_ = nil
---@type Label|nil
local infoRelationLabel_ = nil
---@type Label|nil
local errorLabel_ = nil
---@type Label|nil
local noteLabel_ = nil
---@type Widget|nil
local devTestPanel_ = nil

-- 上一次上屏的状态文案，用来判断这一分钟要不要重画
local statusLine_ = ""
---@type number
local clockElapsed_ = 0
---@type { id: integer, role: string, text: string }|nil
local pendingQuote_ = nil

---@class SelfTestEcho
---@field text string 落日志的完整结论（判据：场景=N/总数，总数由 DevSelfTest.SCENARIO_TOTAL 给出）
---@field panel string 面板用的短结论（那行 nowrap，长文本会被裁掉）
---@field left integer
---@field elapsed number
---@type SelfTestEcho?
local selfTestEcho_ = nil
---@type table|nil
local lastSnap_ = nil
---@type EventFact|nil
local lastFact_ = nil
--- 本会话所属人生槽 id（InitServices 挂存档时定）。痕迹与档案一律按它读写，
--- 不用 LifeService.Active()：注册表的 active 由 CreateSlot/OpenSlot 各自维护，
--- 与当前挂载的存档一旦错位，A 段的事件就会写进 B 段（2026-09-25 自检 AF 实测串写）。
---@type string|nil
local sessionSlotId_ = nil
---@type integer
local turnIndex_ = 0

local function logInfo(msg)
    print("[M0-1] " .. msg)
    log:Write(LOG_INFO, "[M0-1] " .. msg)
end

local function logError(msg)
    print("[M0-1] ERROR: " .. msg)
    log:Write(LOG_ERROR, "[M0-1] " .. msg)
end

local function logWarn(msg)
    print("[M0-1] WARN: " .. msg)
    log:Write(LOG_WARNING, "[M0-1] " .. msg)
end

--- 本会话那一段人生的卡片。干净安装/自检临时会话没有槽（sessionSlotId_ 为 nil），
--- 这时退回注册表 active；有槽时只认它，写入就不可能被别的段带走。
---@return LifeSlot|nil
local function SessionSlot()
    if sessionSlotId_ then
        return LifeService.SlotById(sessionSlotId_)
    end
    return LifeService.Active()
end

--- 全工程唯一取时刻的地方：权威 UTC 秒 + 开发自检投影（普通运行路径偏移恒为 0）
---@return number
local function NowUtc()
    return TimeState.NowUtc()
end

--- 当前玩法城市的唯一入口：以 profile 为准。CONFIG.City 只是干净安装的初始城市，
--- 存档带回来的、或玩家换档案后的城市都从这里走，不再直接读配置。
---@return string
local function City()
    return ProfileService.GetCityId()
end

--- 刷新时间快照，并保证 lastFact_ 与它同源：事实来自当天的事件计划，不是现挑模板。
--- M4：快照刷新同时是「当前生活痕迹」的推进点——ongoing 的关键事件会替换痕迹，
--- 状态窗、档案页与回复事实引用的都是同一份 SceneState。
local function RefreshSnapshot()
    local snap = TimeState.Snapshot(City(), NowUtc())
    lastSnap_ = snap
    lastFact_ = EventService.FactFor(City(), snap.utcSec)
    UpdateCurrentTrace(lastFact_)
    return snap
end

--- 新生成了某一天的事件计划就立刻落盘（只写记忆，不动消息数组）。
--- 计划一旦落盘，重进时由 EventService.Restore 接管，不会重算同日事件。
function PublishEventPlans()
    MemoryService.SetEventPlans(EventService.ExportPlans())
    local ok = MemoryService.Save()
    logInfo(string.format("事件计划落盘 %s", tostring(ok)))
end

-- ============================================================================
-- M4：当前生活痕迹（每段人生一条，绑定最近确定的关键事件，下一关键事件替换）
-- ============================================================================

--- 关键事件进入 ongoing 就替换当前痕迹；痕迹跟着人生槽走，换段读回各自的那一条。
---@param fact? EventFact
function UpdateCurrentTrace(fact)
    local slot = SessionSlot()
    if not slot or not fact then
        return
    end
    if not fact.traceKey or fact.eventState ~= "ongoing" then
        return
    end
    if slot.trace and slot.trace.occurrenceKey == fact.occurrenceKey then
        return
    end
    LifeService.SetTrace(slot.slotId, {
        traceKey = fact.traceKey,
        occurrenceKey = fact.occurrenceKey,
        eventTitle = fact.eventTitle or "",
        sceneId = fact.sceneId,
    }, fact.serverTime)
    logInfo(string.format("生活痕迹替换 槽=%s 痕迹=%s 场景=%s 事件=%s",
        slot.slotId, fact.traceKey, fact.sceneId, tostring(fact.eventTitle or "")))
    ApplyScene(true)
end

--- 旧档升级/新人生还没有痕迹时，从当天计划里补挂最近一个已开始的关键事件。
function EnsureTraceSeeded()
    local slot = SessionSlot()
    if not slot or slot.trace or not lastSnap_ then
        return
    end
    local plan = EventService.PlanFor(City(), lastSnap_.dateKey)
    local best = nil
    for i = 1, #plan.occurrences do
        local occ = plan.occurrences[i]
        if occ.traceKey and occ.startUtc <= lastSnap_.utcSec then
            if not best or occ.startUtc > best.startUtc then
                best = occ
            end
        end
    end
    if best then
        LifeService.SetTrace(slot.slotId, {
            traceKey = best.traceKey,
            occurrenceKey = best.occurrenceKey,
            eventTitle = best.title,
            sceneId = best.sceneId,
        }, lastSnap_.utcSec)
        logInfo("生活痕迹按当日计划补挂 槽=" .. slot.slotId .. " 痕迹=" .. tostring(best.traceKey))
    end
end

-- UTC 秒 → 当地钟点的单格缓存：同一条排队消息的计划窗口是固定的，
-- 但状态条每帧都要问一次，不缓存就会每帧都跑一遍时区换算。
---@type integer|nil
local clockCacheKey_ = nil
---@type string
local clockCacheVal_ = ""

--- UTC 秒 → 当地钟点，排队提示要说「她什么时候能回」而不是假倒计时
---@param utcSec number
---@return string
local function FormatClock(utcSec)
    local key = math.floor(utcSec / 60)
    if key == clockCacheKey_ then
        return clockCacheVal_
    end
    local clock = TimeState.Snapshot(City(), key * 60).clock
    clockCacheKey_ = key
    clockCacheVal_ = clock
    return clock
end

--- 发送瞬间确定的那批事实：可用性、地点、场景、事件事实 id 与回复计划。
--- 主循环与开发自检共用这一份构造，避免两条路径各说一套。
---@param snap TimeSnapshot
---@param quote? { id: integer, role: string, text: string }
---@return SendContext
local function MakeSendContext(snap, quote)
    -- 与当前快照同一 UTC 时复用已刷新的那一份事实；否则现查，
    -- 保证开发自检在没有走 RefreshSnapshot 的路径上也不会带上上一场景的旧实例键
    local fact = (lastFact_ and lastFact_.serverTime == snap.utcSec and lastFact_)
        or EventService.FactFor(City(), snap.utcSec)
    lastFact_ = fact
    return {
        plan = TimeState.ReplyPlanFor(City(), snap.utcSec),
        availability = snap.availability,
        availabilityLabel = snap.availabilityLabel,
        place = snap.place,
        sceneId = snap.sceneId,
        cityId = snap.cityId,
        phrase = snap.phrase,
        factId = fact.id,
        -- 送达瞬间命中的事件实例：补回与重进都引用同一个键
        factKey = fact.occurrenceKey,
        -- 引用只是附加信息：MessageService 会校验它是否成立，不成立就降级
        quote = quote,
    }
end

--- 把 MessageService 的当前相位推给聊天面板
local function PushChatPhase()
    local phase = MessageService.GetPhase()
    local awaiting = MessageService.IsAwaiting()
    ChatPanel.SetPhase(phase, MessageService.StatusLine(NowUtc()), awaiting)
end

--- 用户点发送 / 回车
---@param rawText string
function HandleSend(rawText)
    local snap = RefreshSnapshot()
    local text = (rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local msg = MessageService.Send(text, snap.utcSec, snap.clock, MakeSendContext(snap, pendingQuote_))
    -- 引用是一次性的：无论这一条是否成功发出，都不该粘到下一条上
    pendingQuote_ = nil
    ChatPanel.ClearPendingQuote()
    if not msg then
        -- 只有空白草稿会被拒；这条不打 ERROR，免得把正常操作记成故障（服务内部已有自己的错误日志）
        logInfo("发送未生效，草稿留在输入框")
        PushChatPhase()
        return
    end
    ChatPanel.ClearDraft()
    if msg.quotedMessageId then
        logInfo(string.format("发送 #%d 引用 #%d（%s）", msg.id, msg.quotedMessageId, msg.quotedRole or "?"))
    end
    if msg.planWindowStartUtc then
        logInfo(string.format("发送 #%d → 排队（她 %s 之后能回，计划 %d）",
            msg.id, FormatClock(msg.planWindowStartUtc), msg.planReplyAtUtc or 0))
    else
        logInfo(string.format("发送 #%d → sent（%.0f 秒后回复）",
            msg.id, (msg.planReplyAtUtc or snap.utcSec) - snap.utcSec))
    end
    MemoryService.Persist(MessageService.GetMessages())
    PushChatPhase()
end

--- 点某条气泡上的「引用」：只记 id/role/text，不在这里判断合不合法
---（合法性由 MessageService.Send 统一判，判不过就降级成普通消息）
---@param msg MsgEntry
function HandleQuote(msg)
    if not msg or not msg.id then
        return
    end
    if msg.role ~= "user" and msg.role ~= "her" then
        logInfo(string.format("消息 #%d 是系统消息，不能引用", msg.id))
        return
    end
    pendingQuote_ = { id = msg.id, role = msg.role, text = msg.text or "" }
    ChatPanel.SetPendingQuote(pendingQuote_)
end

--- 开发预览：直接推进到回复，走的仍是同一条生成 + 落库路径
function HandleSkip()
    if not MessageService.IsAwaiting() then
        logInfo("没有待回复的消息，跳过无效果")
        return
    end
    MessageService.Skip()
    PushChatPhase()
end

--- 状态机到点后的回复生成：送达时刻与交付时刻两个快照 + 用户原文 → 模板
--- M2-B：先问 PolishService（网关关闭态同步回调，行为与 M2-A 完全一致；
--- 开启态等润色结果或 8 秒预算到点，任何失败都回落到同一条模板路径）。
---@param pending MsgEntry
function HandleDeliver(pending)
    local snap = RefreshSnapshot()
    -- 送达时刻的那一个事件实例由 EventService 按 UTC 查出来：它现在多半已经收了
    local fact = EventService.FactFor(City(), snap.utcSec, pending.serverTime)
    lastFact_ = fact
    turnIndex_ = turnIndex_ + 1
    local turn = turnIndex_

    -- 引用只作为被回指的宾语与话题词输入，可用性/事件/时刻仍全部来自 fact
    local quote = pending.quotedMessageId and {
        role = pending.quotedRole or "user",
        text = pending.quotedTextPreview or "",
    } or nil

    --- 交付一条回复：segments 来源可以是 LLM 或模板，后续上屏、落库、日志同一条路
    ---@param segments string[]
    ---@param source string
    local function finish(segments, source)
        ---@type MsgEntry|nil
        local reply = nil
        local okStream = pcall(function()
            reply = MessageService.BeginReplyStream(
                segments, snap.utcSec, fact.id, snap.clock, fact.occurrenceKey)
        end)
        -- 多段上屏是纯增强：任何异常都退回既有的单串模板，绝不让队列卡在这一条上
        if not okStream or not reply then
            logError("多段回复失败，退回单串模板（队列不中断）")
            reply = MessageService.AppendReply(
                table.concat(segments, ""),
                snap.utcSec, fact.id, snap.clock, fact.occurrenceKey)
        end

        local topics = ContentService.DetectTopics(pending.text)
        MemoryService.RecordTurn(pending, reply, fact, topics, MessageService.GetMessages())
        ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())

        -- 只记事实、来源与长度：回复正文会带上用户原文片段，不整条进运行日志
        logInfo(string.format("回复 #%d → replied 来源=%s 事实=%s key=%s 状态=%s 场景=%s 送达key=%s 送达态=%s 正文长度=%d 引用=%s",
            pending.id, source, fact.id, fact.occurrenceKey, fact.eventState, fact.sceneId,
            tostring(pending.factKey or fact.sentOccurrenceKey), tostring(fact.sentEventState),
            #reply.text, tostring(pending.quotedMessageId or 0)))
    end

    PolishService.Polish({ fact = fact, pending = pending, nowUtc = snap.utcSec },
        function(segments, reason)
            if segments then
                finish(segments, "llm")
            else
                finish(ContentService.ReplySegments(fact, pending.text, turn, quote),
                    "template:" .. tostring(reason or "fallback"))
            end
        end)
end

function Start()
    graphics.windowTitle = CONFIG.Title
    -- 禁止自由相机 / 相对鼠标，保持光标可见，无镜头旋转
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    logInfo("启动 M0-1 竖切片 · M4 可感知的平行人生")
    logInfo("屏幕物理分辨率: " .. tostring(graphics.width) .. "x" .. tostring(graphics.height)
        .. " DPR=" .. tostring(graphics:GetDPR()))

    -- 自检用独立存档 + 独立人生注册表跑真实服务，跑完交还时钟与注册表；
    -- 正式会话在它之后重新初始化。pcall 不是把检查吞掉：自检里任何断言失败本来就走
    -- logError，这里兜的是「自检自身出异常也不许把正式会话带崩」——
    -- M0-1 已验收的链路不能因为工具而死。
    LifeService.Init()
    if CONFIG.DevSelfTest then
        -- 旧档收编路径也隔离到自检夹具：自检绝不读玩家的 memory/m0-1-la-stranger.json
        local lifeSelftestOpts = {
            registryFile = "memory/life-selftest.json",
            savePrefix = "memory/life-selftest-",
            legacyFile = "memory/life-selftest-legacy.json",
        }
        LifeService.Init(lifeSelftestOpts)
        LifeService.ClearAll()
        InitServices("memory/m1-selftest-la.json")
        local okRun, errRun = pcall(DevSelfTest.Run, {
            cityId = CONFIG.City,
            idleWaitSeconds = CONFIG.ReplyWaitSeconds,
            makeSendContext = MakeSendContext,
            reinit = InitServices,
            -- M4 场景钩子：痕迹替换/计划补挂/注册表重建都借同一份活函数，不开旁路
            updateTrace = UpdateCurrentTrace,
            ensureTrace = EnsureTraceSeeded,
            reinitLife = function() LifeService.Init(lifeSelftestOpts) end,
        })
        if not okRun then
            logError("开发自检异常退出（正式会话继续，不受影响）：" .. tostring(errRun))
        end
        -- 开机那一瞬的整批日志会被日志管道丢掉（2026-09-22 实测：自检只上来 PASS A0…A6，
        -- 同批的尾巴连同 M1 已就绪 一起没落盘），所以结论行要在之后几个真实帧里原样重发，
        -- 让它落进别的抓取窗口。判据是结论行里的 场景=N/总数（当前 33，含 M4 的 AB–AG）。
        -- 屏上也挂一份短结论（面板那行 nowrap，长文本会被裁）：日志整批丢了也能肉眼读数。
        local p, f, d, total = DevSelfTest.Result()
        -- 全绿时面板那行不变长；只有真没过才多挂一段名字，避免 nowrap 那行被裁
        local bad = DevSelfTest.BadScenarios()
        selfTestEcho_ = {
            text = DevSelfTest.Summary(),
            panel = string.format("自检 通过=%d 失败=%d 场景=%d/%d%s",
                p, f, d, total, bad == "" and "" or (" 需看=" .. bad)),
            left = 3,
            elapsed = 0,
        }
        TimeState.DevClockOffset = 0
        LifeService.Init()
    end

    -- M4 冷启动：读注册表，直接进「最近打开的那一段人生」的聊天。
    -- 没有任何一段人生（干净安装）才走首次新故事创建。
    LifeService.Load(NowUtc())
    local slot = LifeService.Active() or LifeService.LatestOpened()
    if slot then
        slot = LifeService.OpenSlot(slot.slotId, NowUtc())
        logInfo(string.format("冷启动进入最近人生 槽=%s 城市=%s 关系=%s",
            slot.slotId, slot.cityId, slot.relationId))
        InitServices(LifeService.SlotSaveFile(slot.slotId), slot)
    else
        logInfo("没有任何人生槽：干净安装，等待首次新故事创建")
        InitServices()
    end
    InitUI()
    StatusWindow.Init()
    -- M4：先把「存档接管后的那一份事实」算出来，再建页面。CreatePage 末尾那次 ApplyScene
    -- 用的就是这一刻的 lastFact_ —— 顺序反了会把自检留下的旧事实钉上屏，而冷启动这条路径
    -- 不经过 StartLifeSession，之后再没人重刷（2026-09-25 逐帧取证实测：跨零点重进后事件、
    -- 痕迹、档案页都已是公寓「已经睡下了」，状态窗却还挂着昨夜那间咖啡馆，信息卡四格整场
    -- 保持 `--:--`）。
    RefreshSnapshot()
    CreatePage()
    SubscribeToEvents()
    StatusWindow.SetNoticesChanged(RefreshResourceNotices)
    RefreshResourceNotices()
    -- 状态窗四格（钟点/城市/地点/状态）在换段与新故事那条路由 StartLifeSession 强制刷；
    -- 冷启动同样要刷一次，否则它们停在字面量里的占位符。
    RefreshStatusLine(true)
    -- 真机上没有 console，时间状态这条是「状态算错时」的唯一线索（M1 起保留的取证行）
    if lastSnap_ then
        local snap = lastSnap_
        logInfo(string.format("时间状态: %s %s %s UTC%+d DST=%s 季节=%s 天气=%s 可用性=%s 地点=%s",
            snap.dateKey, snap.clock, snap.cityLabel,
            math.floor(snap.offsetSeconds / 3600), tostring(snap.isDst),
            snap.season, snap.weather, snap.availability, snap.place))
    end
    EnsureTraceSeeded()
    BootChat()
    -- 开场就把这一份事件事实的身份挂上屏：同一天第二次进入时这里该读成 计划=存档
    if lastFact_ then
        DevTestPanel.SetDetail(lastFact_.id .. " · " .. lastFact_.sceneId
            .. " · 计划=" .. (lastFact_.planFromSave and "存档" or "当场"))
    end

    logInfo(string.format(
        "M4 已就绪：三段人生 + 场景状态包 + 状态窗排队聊天（空闲等待 %.0f 秒，跳过按钮=%s，云记忆=%s）",
        CONFIG.ReplyWaitSeconds, tostring(CONFIG.DevTools), tostring(CONFIG.UseCloudMemory)))
end

function Stop()
    MemoryService.FlushCloud()
    DevTestPanel.Shutdown()
    ProfileOverlay.Shutdown()
    SettingsOverlay.Shutdown()
    ProfilePageOverlay.Shutdown()
    LifeCardsOverlay.Shutdown()
    ChatPanel.Shutdown()
    StatusWindow.Shutdown()
    UI.Shutdown()
end

--- 开发测试台切换的是 TimeState 的本次运行投影，而非系统时间或存档。
---@param hour integer
---@param label string
---@param minute? integer
function HandleDevPreset(hour, label, minute)
    local snap = TimeState.SetDevLocalHour(City(), hour, minute)
    logInfo("开发测试切换：" .. label .. " → " .. snap.clock .. " " .. snap.availability)
    RefreshStatusLine(true)
    PushChatPhase()
    -- 一次切换打全三条证据：事件提示（标题+生命周期）、状态背景（sceneId）、当地钟点
    if lastFact_ then
        logInfo(string.format("开发测试事件 key=%s 模板=%s 状态=%s 场景=%s 提示=%s 钟点=%s",
            lastFact_.occurrenceKey, lastFact_.id, lastFact_.eventState, lastFact_.sceneId,
            lastFact_.eventTitle, snap.clock))
    end
    DevTestPanel.SetSummary("测试时间：" .. label .. " · " .. (lastFact_ and lastFact_.eventTitle or "")
        .. "/" .. (lastFact_ and EVENT_STATE_LABEL[lastFact_.eventState] or ""))
    -- 第二行放证据字段：条件 (a) 的三向一致与 (b) 的「不重算」都能肉眼读，不用等那条随时会被整批丢掉的日志
    DevTestPanel.SetDetail((lastFact_ and (lastFact_.id .. " · " .. lastFact_.sceneId
        .. " · 计划=" .. (lastFact_.planFromSave and "存档" or "当场")) or ""))
end

function HandleDevReset()
    TimeState.ResetDevClock()
    logInfo("开发测试恢复真实时间")
    RefreshStatusLine(true)
    PushChatPhase()
    DevTestPanel.SetSummary("测试时间：真实时间")
    DevTestPanel.SetDetail("已交还权威时间源")
end

function HandleDevAdvance()
    local head = MessageService.GetHead()
    if not head then
        logInfo("开发测试推进无效：没有待回复消息")
        DevTestPanel.SetSummary("先发送一条消息再推进")
        return
    end
    local target = head.planWindowStartUtc or head.planReplyAtUtc
    if not target then
        logError("开发测试无法推进：队首没有可回复计划")
        return
    end
    -- 进入窗口（或到计划时刻）后仍保留短暂 typing；不直接伪造回复气泡。
    TimeState.SetDevUtc(target)
    logInfo("开发测试推进到队首可回复时刻 UTC=" .. tostring(target))
    RefreshStatusLine(true)
    MessageService.Update(NowUtc())
    PushChatPhase()
    DevTestPanel.SetSummary("已推进 · " .. FormatClock(target) .. " 可回复")
end

--- 用户确认后的对话重置：聊天文本、草稿、队列和在途润色都失效；
--- 城市/关系档案与当天事件计划保留，避免「清聊天」变成重开角色人生。
function HandleResetConversation()
    PolishService.CancelAll()
    MessageService.Reset()
    pendingQuote_ = nil
    turnIndex_ = 0
    local saved = MemoryService.ClearConversation()
    local draft = ProfileService.DefaultDraft()
    MessageService.SetDraft(draft)
    ChatPanel.ResetConversation()
    ChatPanel.SetDraft(draft)
    ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())
    PushChatPhase()
    logInfo("用户重置对话记录，落盘=" .. tostring(saved))
end

--- 开发验收时可直接切城市；关系保持不变，便于对比同一关系在四城的状态与回复。
---@param cityId string
---@param label string
function HandleDevCity(cityId, label)
    ApplyProfile(cityId, ProfileService.GetRelationId())
    DevTestPanel.SetSummary("开发城市：" .. label .. " · " .. (lastSnap_ and lastSnap_.clock or ""))
    DevTestPanel.SetDetail((lastFact_ and (lastFact_.id .. " · " .. lastFact_.sceneId)) or "等待事件快照")
end

---@param saveFile? string 独立存档路径（开发自检用），省略则用玩家的历史
---@param lifeSlot? LifeSlot M4 人生槽；nil = 自检/干净安装的临时会话
function InitServices(saveFile, lifeSlot)
    -- 会话槽与段存档在同一条线上定：此后痕迹/档案的读写都只认这一段
    sessionSlotId_ = lifeSlot and lifeSlot.slotId or nil
    TimeState.SetReplyDelay("idle", CONFIG.ReplyWaitSeconds)
    -- M2-B S1：GatewayEnabled=false 时 PolishService 全程同步回落，不产生任何外发。
    -- 真正开启要等中转路径确认后再注入 transport（网关 URL + 共享密钥走服务端配置）。
    PolishService.Configure({ enabled = CONFIG.GatewayEnabled })
    MessageService.Init({
        hooks = {
            onPhaseChange = function()
                PushChatPhase()
            end,
            onDeliver = HandleDeliver,
            formatClock = FormatClock,
        },
    })

    local adapter = nil
    if CONFIG.UseCloudMemory then
        adapter = MemoryService.DefaultClientCloudAdapter()
    end
    MemoryService.Init({
        cityId = lifeSlot and lifeSlot.cityId or CONFIG.City,
        cloud = adapter,
        saveFile = saveFile,
        lifeId = lifeSlot and lifeSlot.slotId or nil,
    })
    local _, source = MemoryService.Load()
    logInfo("记忆装载来源: " .. source)
    -- 档案在记忆之后、事件层之前接：存档带 profile 就原样恢复；v1–v4 旧档由
    -- MemoryService 迁移成 LA×陌生网友（initialized=true，不弹初始化）；
    -- 新人生槽还没有存档 → 用注册表卡片里的档案（initialized=true）。
    local saved = MemoryService.GetProfile()
    if saved then
        ProfileService.Set(saved.cityId, saved.relationId, {
            seedText = saved.seedText,
            isRandom = saved.isRandom,
            initialized = saved.initialized,
        })
    elseif lifeSlot then
        ProfileService.Set(lifeSlot.cityId, lifeSlot.relationId, {
            seedText = lifeSlot.seedText,
            isRandom = lifeSlot.isRandom,
            initialized = true,
        })
        -- 注册表那张卡就是这一段的档案来源，建档/换卡当场就得收进段存档：
        -- `MemoryService.SetProfile` 原先只在开发测试台的 `ApplyProfile` 里被调过，
        -- 新故事这条路的存档一直「带记录却缺 profile」，于是下一次读取按迁移规则
        -- 补成「本城 × 陌生网友」——选前同事/高中同学/久未联系的朋友建的段，
        -- 聊过一轮再重进就变成陌生网友，回复的关系语气壳也跟着换掉
        -- （2026-09-25 换卡跨进程取证 D/E 实测，见 CHANGELOG）。
        MemoryService.SetProfile(ProfileService.Get())
    else
        ProfileService.Set(CONFIG.City, "stranger", { initialized = false })
    end
    logInfo(string.format("档案: 槽=%s 城市=%s 关系=%s 随机=%s 已初始化=%s",
        tostring(lifeSlot and lifeSlot.slotId or "无"),
        saved and saved.cityId or (lifeSlot and lifeSlot.cityId or CONFIG.City),
        saved and saved.relationId or (lifeSlot and lifeSlot.relationId or "stranger"),
        tostring(saved and saved.isRandom or (lifeSlot and lifeSlot.isRandom) or false),
        tostring(saved and saved.initialized or (lifeSlot ~= nil))))
    -- 事件层在记忆之后接：存档里已有当天的计划就直接接管，不重新生成同日事件
    EventService.Init({ cityId = City(), onPlansChanged = PublishEventPlans })
    local restoredPlans = EventService.Restore(MemoryService.GetEventPlans())
    logInfo(string.format("事件计划接管：存档 %d 天（记忆来源 %s）", restoredPlans, source))
    turnIndex_ = MemoryService.Get().turns
    MemoryService.CloudLoadAsync()
end

--- 会话开场：恢复历史与队列；新档先等首次初始化，旧档直接开场。
--- 「离开期间」摘要与开场白的判定都在下面两个小函数里，BootChat 只管先后顺序。
function BootChat()
    local fact = lastFact_
    local snap = lastSnap_
    if not fact or not snap then
        logError("开场时事件事实或时间快照为空，跳过开场")
        return
    end

    local pendingCount = MessageService.Restore(MemoryService.GetRestoredMessages())
    ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())
    ChatPanel.SetProfileLine(ProfileService.ProfileLine())
    -- 开场就报一次事件实例的键与生命周期，并说明它是不是从存档接管的
    logInfo(string.format("开场事件 key=%s 模板=%s 状态=%s 场景=%s 计划来源=%s",
        fact.occurrenceKey, fact.id, fact.eventState, fact.sceneId,
        fact.planFromSave and "存档" or "当场生成"))

    if not ProfileService.Get().initialized then
        -- 干净安装：开场白要等玩家创建第一段人生再写，不然会把默认 LA 的话先钉进历史。
        -- 这里不落盘，profile 只在内存里标着未初始化。
        logInfo("没有人生存档：等待首次新故事创建")
        ProfileOverlay.Show({ mode = "init", onConfirm = HandleNewStoryConfirm })
        PushChatPhase()
        return
    end

    WriteBootGreeting(pendingCount)
    WriteAwaySummary()
    PushChatPhase()
end

--- 空历史才写开场：系统行说「关系 × 城市」，第一句回复由城市事件 × 关系语气壳共同生成
---@param pendingCount integer 读档恢复的待回复条数（仅日志用）
function WriteBootGreeting(pendingCount)
    local fact = lastFact_
    local snap = lastSnap_
    if not fact or not snap then
        return
    end
    if #MessageService.GetMessages() > 0 then
        logInfo(string.format("已恢复 %d 条历史记录（其中 %d 条待回复），不再重复开场白",
            #MessageService.GetMessages(), pendingCount or 0))
        return
    end
    local p = ProfileService.Get()
    MessageService.AddSystem(ProfileService.RelationCityLine(), snap.utcSec, snap.clock)
    local narration = ProfileService.EventNarration(p.cityId, fact.id) or snap.phrase
    local opening = ProfileService.OpeningLine(p.cityId, p.relationId, narration)
    logInfo("开场白（非回复链路）: " .. opening)
    MessageService.AppendReply(opening, snap.utcSec, fact.id, snap.clock,
        fact.occurrenceKey)
    -- 首次开场也要把当天的计划留在存档里，否则重进时只能重算
    PublishEventPlans()
end

--- 离开期间到点的排队消息不丢：由状态机按 FIFO 逐条补发，这里只补一句摘要。
--- 「要不要补」的判定在 MemoryService.AwayGap（自检场景 H 直接断言它，包括
--- 补发完再重进时不再补第二次），这里只负责把它写成一条系统消息。
function WriteAwaySummary()
    local fact = lastFact_
    local snap = lastSnap_
    if not fact or not snap then
        return
    end
    local dueCount = MessageService.GetDueCount(snap.utcSec)
    local gap, shouldSummarize, thenUtc =
        MemoryService.AwayGap(snap.utcSec, dueCount, CONFIG.AwaySummaryMinSeconds)
    if shouldSummarize then
        local thenSnap = TimeState.Snapshot(City(), thenUtc)
        MessageService.AddSystem(
            ContentService.AwaySummary(gap, thenSnap.phrase, snap.phrase, dueCount),
            snap.utcSec, snap.clock)
        MemoryService.Persist(MessageService.GetMessages())
    end
end

--- 改「当前这一段人生」的档案（开发测试台切城用；玩家入口已换成三段人生）。
--- 队列与 FIFO 一律不动：排队中的消息到点按新城事实回复（她人在新城）；
--- 已上屏的历史不重建行，旧城市戳原样保留。注册表卡片摘要同步更新。
---@param cityId string
---@param relationId string
---@param opts? { isRandom?: boolean, firstTime?: boolean }
function ApplyProfile(cityId, relationId, opts)
    opts = opts or {}
    local oldLabel = ProfileService.Get().cityLabel
    local p
    if opts.isRandom then
        p = ProfileService.ApplyRandom(NowUtc())
    else
        p = ProfileService.Set(cityId, relationId, { initialized = true })
    end

    MemoryService.SetProfile(p)
    MemoryService.Save()
    local active = SessionSlot()
    if active then
        LifeService.UpdateSlotProfile(active.slotId, p.cityId, p.relationId, {
            seedText = p.seedText, isRandom = p.isRandom,
        })
    end
    EventService.SetCity(p.cityId)
    clockCacheKey_ = nil -- 城市换了，钟点缓存整格作废
    RefreshSnapshot()

    if not opts.firstTime then
        MessageService.AddSystem(
            string.format("档案更新 · 她搬去了 %s，你们的最新消息从这里继续", p.cityLabel),
            NowUtc(), lastSnap_ and lastSnap_.clock or "")
        ChatPanel.SetDraft(ProfileService.DefaultDraft(p.cityId))
        MemoryService.Persist(MessageService.GetMessages())
    end

    ChatPanel.SetProfileLine(ProfileService.ProfileLine())
    RefreshStatusLine(true)
    PublishEventPlans()
    PushChatPhase()
    -- 只记 id 与长度：档案文本会进聊天流，日志不带玩家原文
    logInfo(string.format("换档案 城市=%s 关系=%s 随机=%s 旧城=%s 消息=%d 条",
        p.cityId, p.relationId, tostring(p.isRandom), oldLabel,
        #MessageService.GetMessages()))
end

-- ============================================================================
-- M4：人生入口（新故事 / 换一段人生 / 查看档案）
-- ============================================================================

---@type { cityId: string, relationId: string, seedText: string, isRandom: boolean }|nil
local pendingNewStory_ = nil

--- 「新故事」确认：随机只是次要选项；满三段时不创建也不淘汰，
--- 必须由用户点一张卡片明确替换（设计 §3）。
function HandleNewStoryConfirm(cityId, relationId, isRandom)
    ProfileOverlay.Hide()
    local now = NowUtc()
    local pickCity, pickRel, seedText = cityId, relationId, nil
    if isRandom then
        local picked = ProfileService.RandomPick(now)
        pickCity, pickRel, seedText = picked.cityId, picked.relationId, picked.seedText
    end
    if LifeService.IsFull() then
        pendingNewStory_ = {
            cityId = pickCity, relationId = pickRel,
            seedText = seedText or (pickCity .. "|" .. pickRel), isRandom = isRandom == true,
        }
        ShowLifeCards("replace")
        logInfo("人生槽已满：等待用户点名替换卡片")
        return
    end
    local slot = LifeService.CreateSlot(pickCity, pickRel, {
        seedText = seedText, isRandom = isRandom == true,
    }, now)
    if not slot then
        logError("创建人生槽失败（意外分支），本次不写开场白")
        return
    end
    StartLifeSession(slot, true)
end

--- 打开一段人生并重建会话。firstTime=true 是新建故事（写开场白）；
--- false 是切换/冷启动（恢复那一段自己的历史，绝不带上一段的城市/场景/痕迹）。
---@param slot LifeSlot
---@param firstTime boolean
function StartLifeSession(slot, firstTime)
    PolishService.CancelAll()
    InitServices(LifeService.SlotSaveFile(slot.slotId), slot)
    clockCacheKey_ = nil
    RefreshSnapshot()
    EnsureTraceSeeded()
    if firstTime then
        -- 新故事这条路与换段一样必须先把上一段的画面摘掉：`RebuildChatForLife` 里那句
        -- 隐藏只覆盖换段，firstTime 以前不隐也不重算画面 —— 旧段的生活痕迹会留在新段画面上，
        -- 直到下一次状态文案变化才被换掉（2026-09-25 控件树逐帧取证 T2 抓到，判据见 CHANGELOG）。
        if traceImage_ then
            traceImage_:SetVisible(false)
        end
        ChatPanel.ResetConversation()
        WriteBootGreeting(0)
        ChatPanel.SetDraft(ProfileService.DefaultDraft())
        ChatPanel.SetProfileLine(ProfileService.ProfileLine())
        ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())
        RefreshStatusLine(true)
        ApplyScene(true)
    else
        RebuildChatForLife()
    end
    PushChatPhase()
    logInfo(string.format("进入人生 槽=%s 城市=%s 关系=%s 首建=%s",
        slot.slotId, slot.cityId, slot.relationId, tostring(firstTime)))
end

--- 切换人生后的会话重建：先藏旧痕迹与旧场景（验收 4 的「不显示旧东西」），
--- 再按新档恢复历史、队列、场景与痕迹。
function RebuildChatForLife()
    if traceImage_ then
        traceImage_:SetVisible(false)
    end
    ChatPanel.ResetConversation()
    local pendingCount = MessageService.Restore(MemoryService.GetRestoredMessages())
    ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())
    ChatPanel.SetProfileLine(ProfileService.ProfileLine())
    ChatPanel.SetDraft(ProfileService.DefaultDraft())
    RefreshStatusLine(true)
    ApplyScene(true)
    if #MessageService.GetMessages() == 0 then
        WriteBootGreeting(0)
    else
        logInfo(string.format("已恢复 %d 条历史记录（其中 %d 条待回复）",
            #MessageService.GetMessages(), pendingCount or 0))
    end
    WriteAwaySummary()
end

--- 点一张人生卡片切换过去：先冲刷当前段，再整段换挂目标档。
---@param slotId string
function HandleSwitchLife(slotId)
    LifeCardsOverlay.Hide()
    SettingsOverlay.Hide()
    local current = SessionSlot()
    if current and current.slotId == slotId then
        logInfo("已在这一段人生中，不重复切换")
        return
    end
    MemoryService.Persist(MessageService.GetMessages())
    local slot = LifeService.OpenSlot(slotId, NowUtc())
    if not slot then
        return
    end
    StartLifeSession(slot, false)
end

--- 「替换哪一张卡」确认后走这里：旧段历史整段作废（文件删除），槽号复用。
---@param slotId string
function HandleReplacePick(slotId)
    LifeCardsOverlay.Hide()
    local pending = pendingNewStory_
    if not pending then
        logWarn("替换请求已失效（没有待创建的新故事）")
        return
    end
    pendingNewStory_ = nil
    MemoryService.Persist(MessageService.GetMessages())
    LifeService.ClearSlotSaveFile(slotId)
    local slot = LifeService.ReplaceSlot(slotId, pending.cityId, pending.relationId, {
        seedText = pending.seedText, isRandom = pending.isRandom,
    }, NowUtc())
    if not slot then
        logError("替换人生槽失败: " .. tostring(slotId))
        return
    end
    StartLifeSession(slot, true)
    logInfo("用户点名替换卡片 槽=" .. slotId)
end

--- 卡片摘要：城市 × 关系 + 那一段自己的当地钟点/状态/痕迹/最近打开。
--- 钟点与状态按每张卡的城现算 —— 三段人生各按各的时区生活，这正是产品本身。
--- （全局：HandleNewStoryConfirm 在定义之前就要能调用到它。）
---@param mode string switch|replace
function ShowLifeCards(mode)
    local now = NowUtc()
    ---@type LifeCardEntry[]
    local cards = {}
    local slots = LifeService.Slots()
    local active = SessionSlot()
    for i = 1, #slots do
        local slot = slots[i]
        local city = ProfileService.CityFor(slot.cityId)
        local relation = ProfileService.RelationFor(slot.relationId)
        local snap = TimeState.Snapshot(slot.cityId, now)
        local trace = slot.trace and SceneService.TraceFor(slot.trace.traceKey) or nil
        local opened = slot.lastOpenedUtc > 0
            and os.date("!%m-%d %H:%M", slot.lastOpenedUtc) or "—"
        cards[i] = {
            slotId = slot.slotId,
            head = (city and city.label or slot.cityId) .. " × "
                .. (relation and relation.label or slot.relationId)
                .. (active and slot.slotId == active.slotId and "（当前）" or ""),
            body = string.format("%s · %s · %s ｜ 痕迹：%s ｜ 最近打开 %s",
                snap.clock, snap.cityLabel, snap.phrase,
                trace and trace.label or "还没有", opened),
            isActive = active ~= nil and slot.slotId == active.slotId,
        }
    end
    LifeCardsOverlay.Show({
        title = mode == "replace" and "替换哪一段人生？" or "换一段人生",
        hint = mode == "replace"
                and "三段都满了。点一张卡将被新故事覆盖，它的聊天、事件与痕迹整段作废。"
                or "每张卡是一段独立人生：聊天、事件、记忆与生活痕迹互不串写。",
        cards = cards,
        onPick = mode == "replace" and HandleReplacePick or HandleSwitchLife,
        cancelText = mode == "replace" and "先不替换" or "先不换",
    })
end

--- 「查看档案」：只读页，全部字段来自当前人生的同一事实源（设计 §4）。
function BuildProfilePageData()
    local snap = lastSnap_ or RefreshSnapshot()
    local fact = lastFact_
    local p = ProfileService.Get()
    local pkg = fact and SceneService.PackageFor(fact.sceneId) or nil
    ---@type string[]
    local recent = {}
    local ledger = MemoryService.Get().eventLedger
    for i = #ledger, 1, -1 do
        if #recent >= 3 then
            break
        end
        local entry = ledger[i]
        local stateText = EVENT_STATE_LABEL[entry.lastEventState] or ""
        local title = entry.title ~= "" and entry.title or ""
        if title ~= "" then
            recent[#recent + 1] = title .. (stateText ~= "" and ("（" .. stateText .. "）") or "")
        end
    end
    local traceSlot = SessionSlot()
    local trace = traceSlot and traceSlot.trace or nil
    local traceItem = trace and SceneService.TraceFor(trace.traceKey) or nil
    ---@type ProfilePageData
    return {
        cityClock = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.dateKey,
        identity = p.identity,
        relation = p.relationLabel .. " × " .. p.cityLabel,
        scene = pkg and (pkg.label .. " · " .. (fact and fact.placeLabel or "")) or "此刻不在任何已知场景",
        status = snap.availabilityLabel .. " · " .. snap.phrase,
        recent = recent,
        trace = traceItem and (traceItem.label .. "（" .. trace.eventTitle .. "留下的）") or "",
    }
end

function HandleViewProfile()
    SettingsOverlay.Hide()
    ProfilePageOverlay.Show(BuildProfilePageData())
end

function HandleSwitchEntry()
    SettingsOverlay.Hide()
    ShowLifeCards("switch")
end

function HandleNewStoryEntry()
    SettingsOverlay.Hide()
    ProfileOverlay.Show({ mode = "init", onConfirm = HandleNewStoryConfirm })
end

--- 顶栏「设置」入口：打开设置层（查看档案 / 换一段人生 / 新故事）。
function HandleSettingsEntry()
    SettingsOverlay.Show({
        onProfile = HandleViewProfile,
        onSwitch = HandleSwitchEntry,
        onNew = HandleNewStoryEntry,
    })
end

function InitUI()
    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })
end

function CreatePage()
    -- 信息层级收进状态窗内：一级「当地时间 + 城市」，二级「地点」，三级「当前状态」。
    -- 全部走 absolute + 左下角：状态窗是 4:3 画框，角色站在中间，
    -- 贴边放既不裁切（窄屏换行）也不压人。半透明底 + 细边，读起来是 HUD 而不是弹窗，
    -- 与左上角蓝框的开发自检面板在颜色和形状上都区分开。
    infoClockLabel_ = UI.Label {
        id = "infoClock",
        text = "--:--",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = { 238, 233, 224, 245 },
        whiteSpace = "nowrap",
    }
    infoCityLabel_ = UI.Label {
        id = "infoCity",
        text = "",
        fontSize = 10,
        fontColor = { 150, 207, 255, 220 },
        whiteSpace = "nowrap",
    }
    infoPlaceLabel_ = UI.Label {
        id = "infoPlace",
        text = "",
        fontSize = 10,
        fontColor = { 200, 194, 184, 228 },
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    infoStateLabel_ = UI.Label {
        id = "infoState",
        text = "",
        fontSize = 10,
        fontColor = { 208, 168, 126, 238 },
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    -- 「关系 · 身份」行：城市 × 关系共同决定的档案，换档后立即重挂。
    -- 长文案用 normal 换行（自检面板 642836d 的窄屏拆行教训）。
    infoRelationLabel_ = UI.Label {
        id = "infoRelation",
        text = "",
        fontSize = 10,
        fontColor = { 200, 162, 122, 235 },
        whiteSpace = "normal",
        wordBreak = "break-word",
    }

    local infoCard = UI.Panel {
        id = "statusInfoCard",
        position = "absolute",
        left = 10,
        -- M4：信息卡从左下角挪到左上角，把画面左下让给生活痕迹覆盖物
        -- （痕迹按场景包锚点摆在桌台高度，与卡片重叠会两败俱伤）
        top = 10,
        maxWidth = "66%",
        flexDirection = "column",
        gap = 1,
        paddingHorizontal = 9,
        paddingVertical = 7,
        borderRadius = 9,
        backgroundColor = { 14, 16, 21, 200 },
        borderWidth = 1,
        borderColor = { 122, 130, 142, 70 },
        pointerEvents = "none",
        children = {
            UI.Row {
                gap = 6,
                alignItems = "center",
                flexWrap = "wrap",
                children = { infoClockLabel_, infoCityLabel_ },
            },
            infoRelationLabel_,
            infoPlaceLabel_,
            infoStateLabel_,
        },
    }

    errorLabel_ = UI.Label {
        id = "resourceAlert",
        text = "",
        fontSize = 12,
        fontColor = { 232, 196, 140, 230 },
        textAlign = "left",
        whiteSpace = "normal",
        width = "100%",
        visible = false,
        pointerEvents = "none",
    }

    noteLabel_ = UI.Label {
        id = "pageNote",
        text = "",
        fontSize = 11,
        fontColor = { 150, 146, 140, 160 },
        textAlign = "left",
        whiteSpace = "normal",
        pointerEvents = "none",
    }

    -- 宽度撑满、高度由 4:3 算出：反过来用高度定宽度时，竖屏上 maxWidth 会把宽度夹到
    -- 100%，画框就不是真 4:3，cover 会裁掉静帧两侧。
    -- 背景不再在这里给：由 ApplyScene 拿场景状态包后挂载（M4，缺包显式回退）
    local preview = StatusWindow.CreatePreviewWidget({
        id = "statusPreview",
        width = "100%",
        aspectRatio = 4 / 3,
        backgroundFit = "cover",
        backgroundColor = { 18, 16, 15, 255 },
        borderRadius = 14,
        overflow = "hidden",
        pointerEvents = "none",
        boxShadow = {
            { x = 0, y = 8, blur = 24, color = { 0, 0, 0, 90 } },
        },
    })
    preview_ = preview

    -- 气泡宽度必须是确定像素：ScrollView 子树里的百分比宽度在首轮测量拿不到确定父宽，
    -- 预览实测会塌成「一行两个字」。逻辑宽 = 物理宽 / DPR（AGENTS 规则 #0.8）。
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then
        dpr = 1
    end
    local chatOuterWidth = graphics.width / dpr - 32 - 2
    -- 状态窗画框的确定像素尺寸：生活痕迹覆盖物按归一化锚点 × 画框宽高定位
    frameW_ = graphics.width / dpr - 32
    frameH_ = frameW_ * 3 / 4

    -- 2.5D 生活痕迹：静态背景上的不可点击 2D 覆盖物（M4 §6）
    traceImage_ = UI.Panel {
        id = "traceOverlay",
        position = "absolute",
        left = 0,
        top = 0,
        width = 40,
        height = 40,
        backgroundFit = "contain",
        visible = false,
        pointerEvents = "none",
    }

    local chat = ChatPanel.Build({
        devTools = CONFIG.DevTools,
        initialDraft = ProfileService.DefaultDraft(),
        minHeight = 190,
        outerWidth = chatOuterWidth,
        onSend = HandleSend,
        onSkip = HandleSkip,
        onDraftChange = MessageService.SetDraft,
        onQuote = HandleQuote,
        onSettingsEntry = HandleSettingsEntry,
        onResetConversation = HandleResetConversation,
        getMessages = MessageService.GetMessages,
        getVersion = MessageService.GetVersion,
    })

    if CONFIG.DevTools then
        devTestPanel_ = DevTestPanel.Build({
            onPreset = HandleDevPreset,
            onReset = HandleDevReset,
            onAdvance = HandleDevAdvance,
            onCity = HandleDevCity,
        })
        -- 自检跑在 Build 之前，那时 SetSummary 还没有 label 可写；这里补挂一次，
        -- 让结论行那串 场景=N/总数 从开机起就在画面上，不依赖会被整批丢掉的日志。
        if selfTestEcho_ then
            DevTestPanel.SetSummary(selfTestEcho_.panel)
        end
    end

    uiRoot_ = UI.SafeAreaView {
        id = "root",
        width = "100%",
        height = "100%",
        edges = "all",
        nativeMenuInset = true,
        backgroundColor = { 12, 14, 18, 255 },
        flexDirection = "column",
        alignItems = "stretch",
        children = {
            UI.Panel {
                id = "page",
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "column",
                paddingHorizontal = 16,
                paddingTop = 12,
                paddingBottom = 20,
                gap = 10,
                -- box-none：这层自己不接点击，但子树要能点（聊天区必须可交互）
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        id = "statusWindowFrame",
                        width = "100%",
                        flexShrink = 0,
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "box-none",
                        children = {
                            preview,
                            traceImage_,
                            infoCard,
                        },
                    },
                    errorLabel_,
                    chat,
                    noteLabel_,
                },
            },
            -- 初始化/新故事覆盖层 + M4 设置层/档案页/人生卡片层：
            -- 绝对定位铺满整页，默认不可见，最后挂保证压在一切之上。
            -- 这一串里**不许放可能为 nil 的项**：引擎 Widget:ProcessChildren 用 ipairs 遍历
            -- props.children，遇到空洞就停止挂载 —— 2026-09-25 本地控件树取证实测到，
            -- DevTools=false 时测试台那一格是 nil，后面四个覆盖层全都没挂上根节点，
            -- 点「设置」只是把一棵不在屏幕上的树标记为可见（静默无效，不报任何错）。
            ProfileOverlay.Build(),
            SettingsOverlay.Build(),
            ProfilePageOverlay.Build(),
            LifeCardsOverlay.Build(),
        },
    }

    -- 测试台是条件产物，单独补挂在第 2 格（聊天页之上、四个覆盖层之下），保持原来的压层顺序
    if devTestPanel_ then
        uiRoot_:InsertChild(devTestPanel_, 2)
    end
    -- 挂载结果进启动日志：真机 runtime.log 里这一行是「三入口确实在屏幕上」的证据把手
    logInfo(string.format("根节点子层=%d（页 1 + 测试台 %s + 覆盖层 4）",
        #uiRoot_.children, devTestPanel_ and "1" or "0"))

    UI.SetRoot(uiRoot_)
    logInfo("竖屏页面已创建：顶部真 4:3 状态窗（场景包驱动）+ 下方可交互聊天区")

    -- 首帧就按当前事实应用场景包：背景要等资源到手才挂（见 PrepareTexture 注释），
    -- 缺包会显式留在暗色底并上屏说明，不伪称已切换。
    ApplyScene(true)
end

function RefreshResourceNotices()
    if not errorLabel_ then
        return
    end
    local messages = {}
    local modelError = StatusWindow.GetModelError()
    if modelError ~= "" then
        messages[#messages + 1] = modelError
    end
    local bgError = StatusWindow.GetBackgroundError()
    if bgError ~= "" then
        messages[#messages + 1] = bgError
    end

    if #messages > 0 then
        errorLabel_:SetText(table.concat(messages, " "))
        errorLabel_:SetVisible(true)
    else
        errorLabel_:SetText("")
        errorLabel_:SetVisible(false)
    end
    RefreshNoteLine()
end

--- 缺资产不是报错，是一句要说清楚的降级说明；挂在同一条注释行上
function RefreshNoteLine()
    if not noteLabel_ then
        return
    end
    local note = "M1 · 镜头仍锁定，回复只用送达与交付两个时刻的事件事实"
    if lastFact_ and lastFact_.eventTitle then
        note = string.format("事件 · %s（%s）· %s · %s—%s",
            lastFact_.eventTitle, EVENT_STATE_LABEL[lastFact_.eventState] or lastFact_.eventState,
            (lastFact_.eventEmotion or ""), lastFact_.eventStartsAt, lastFact_.eventEndsAt)
    end
    local sceneNote = StatusWindow.GetSceneNotice()
    if sceneNote ~= "" then
        note = note .. " · " .. sceneNote
    end
    noteLabel_:SetText(note)
end

--- 状态窗按当前事实的场景 id 应用「场景状态包」（M4 §5 单源）：
--- 背景、色温、主光、站位、接地阴影、微动与生活痕迹一次换齐；
--- 缺包必须显式回退并上屏说明，绝不沿用旧图假称已切换。
---@param force? boolean 换人生/换痕迹时同场景也要重挂
function ApplyScene(force)
    local widget = preview_
    if not lastSnap_ or not widget then
        return "no-widget"
    end
    local sceneId = (lastFact_ and lastFact_.sceneId) or lastSnap_.sceneId or ""
    local state = SceneService.StateFor(sceneId, LifeService.GetTrace())
    local result = StatusWindow.ApplySceneState(state, function(path)
        widget:SetBackgroundImage(path)
        RefreshTraceOverlay(state)
        RefreshResourceNotices()
    end, force)
    if result == "missing-package" then
        RefreshTraceOverlay(nil)
        logInfo("场景降级: " .. sceneId .. "（缺场景状态包，沿用当前画面）")
        RefreshNoteLine()
    end
    return result
end

--- 2.5D 生活痕迹覆盖物：静态背景上的不可点击 2D 贴图，归一化锚点定位。
--- 与状态窗背景同一条装载纪律：先确认资源到手再 SetBackgroundImage（ImageCache
--- 会永久缓存首次失败）。换人生时先隐藏，旧痕迹绝不跟到新画面上。
---@param state? SceneState
function RefreshTraceOverlay(state)
    if not traceImage_ then
        return
    end
    local tr = state and state.recentTrace or nil
    if not tr then
        traceImage_:SetVisible(false)
        return
    end
    local w = frameW_ * tr.scale
    StatusWindow.PrepareTexture(tr.assetPath, function(path)
        traceImage_:SetBackgroundImage(path)
        traceImage_:SetStyle({
            position = "absolute",
            left = frameW_ * tr.anchorX - w / 2,
            top = frameH_ * tr.anchorY - w / 2,
            width = w,
            height = w,
        })
        traceImage_:SetVisible(true)
        logInfo(string.format("生活痕迹上屏 %s 锚点=(%.2f,%.2f)", tr.assetKey, tr.anchorX, tr.anchorY))
    end, function(failed)
        traceImage_:SetVisible(false)
        logWarn("生活痕迹贴图未就绪，本次不显示: " .. failed)
    end)
end

--- 状态文案一分钟一变；变了才重画，避免每帧 SetText
---@param force? boolean
function RefreshStatusLine(force)
    local snap = RefreshSnapshot()
    local line = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
    if force or line ~= statusLine_ then
        statusLine_ = line
        -- 信息卡按层级拆开写：钟点最重，城市次之，地点与当前状态最轻
        if infoClockLabel_ then
            infoClockLabel_:SetText(snap.clock)
        end
        if infoCityLabel_ then
            infoCityLabel_:SetText(snap.cityLabel)
        end
        if infoPlaceLabel_ then
            infoPlaceLabel_:SetText(snap.place)
        end
        if infoStateLabel_ then
            infoStateLabel_:SetText(snap.phrase)
        end
        if infoRelationLabel_ then
            local p = ProfileService.Get()
            infoRelationLabel_:SetText(p.relationLabel .. " · " .. p.identityShort)
        end
        ApplyScene()
    end
end

function SubscribeToEvents()
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("Update", "HandleUpdate")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- 消息队列用权威 UTC 绝对时刻推进；这就是「她什么时候回」的唯一计时处
    MessageService.Update(NowUtc())
    -- M2-B：润色槽位的 8 秒预算与到点回落在同一权威时钟上逐帧推进
    PolishService.Update(NowUtc())
    ChatPanel.Tick(timeStep)

    -- 自检结论重发：每 4 秒一次、共 3 次，把它挪出开机那一批
    if selfTestEcho_ and selfTestEcho_.left > 0 then
        selfTestEcho_.elapsed = selfTestEcho_.elapsed + timeStep
        if selfTestEcho_.elapsed >= 4 then
            selfTestEcho_.elapsed = 0
            selfTestEcho_.left = selfTestEcho_.left - 1
            local n = string.format(" 重发%d/3", 3 - selfTestEcho_.left)
            logInfo(selfTestEcho_.text .. n)
            DevTestPanel.SetSummary(selfTestEcho_.panel .. n)
        end
    end

    clockElapsed_ = clockElapsed_ + timeStep
    if clockElapsed_ >= 20 then
        clockElapsed_ = 0
        RefreshStatusLine()
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        engine:Exit()
    end
end
