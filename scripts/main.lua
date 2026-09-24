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

---@type {Title: string, City: string, ReplyWaitSeconds: integer, DevTools: boolean, UseCloudMemory: boolean, DevSelfTest: boolean, AwaySummaryMinSeconds: integer, GatewayEnabled: boolean}
local CONFIG = {
    Title = "送给你这个回来的人",
    City = "los_angeles",        -- 干净安装的初始城市；存档/换档案后的城市走 ProfileService
    ReplyWaitSeconds = 10,   -- 空闲档的固定等待（M0-1 验收过的那条链路）
    DevTools = true,         -- 开发预览：显示「跳过等待」
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

--- 刷新时间快照，并保证 lastFact_ 与它同源：事实来自当天的事件计划，不是现挑模板
local function RefreshSnapshot()
    local snap = TimeState.Snapshot(City(), NowUtc())
    lastSnap_ = snap
    lastFact_ = EventService.FactFor(City(), snap.utcSec)
    return snap
end

--- 新生成了某一天的事件计划就立刻落盘（只写记忆，不动消息数组）。
--- 计划一旦落盘，重进时由 EventService.Restore 接管，不会重算同日事件。
function PublishEventPlans()
    MemoryService.SetEventPlans(EventService.ExportPlans())
    local ok = MemoryService.Save()
    logInfo(string.format("事件计划落盘 %s", tostring(ok)))
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

    logInfo("启动 M0-1 竖切片 · M1 时间状态闭环")
    logInfo("屏幕物理分辨率: " .. tostring(graphics.width) .. "x" .. tostring(graphics.height)
        .. " DPR=" .. tostring(graphics:GetDPR()))

    -- 时间层先落一条日志：真机上没有 console，状态算错时这条是唯一线索
    local snap = RefreshSnapshot()
    statusLine_ = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
    logInfo(string.format("时间状态: %s %s %s UTC%+d DST=%s 季节=%s 天气=%s 可用性=%s 地点=%s",
        snap.dateKey, snap.clock, snap.cityLabel,
        math.floor(snap.offsetSeconds / 3600), tostring(snap.isDst),
        snap.season, snap.weather, snap.availability, snap.place))

    -- 自检用独立存档跑真实服务，跑完交还时钟；正式会话在它之后重新初始化。
    -- pcall 不是把检查吞掉：自检里任何断言失败本来就走 logError，这里兜的是
    -- 「自检自身出异常也不许把正式会话带崩」——M0-1 已验收的链路不能因为工具而死。
    if CONFIG.DevSelfTest then
        InitServices("memory/m1-selftest-la.json")
        local okRun, errRun = pcall(DevSelfTest.Run, {
            cityId = CONFIG.City,
            idleWaitSeconds = CONFIG.ReplyWaitSeconds,
            makeSendContext = MakeSendContext,
            reinit = InitServices,
        })
        if not okRun then
            logError("开发自检异常退出（正式会话继续，不受影响）：" .. tostring(errRun))
        end
        -- 开机那一瞬的整批日志会被日志管道丢掉（2026-09-22 实测：自检只上来 PASS A0…A6，
        -- 同批的尾巴连同 M1 已就绪 一起没落盘），所以结论行要在之后几个真实帧里原样重发，
        -- 让它落进别的抓取窗口。判据是结论行里的 场景=N/总数（当前 26，含 M3 的 U–Z）。
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
    end

    InitServices()
    InitUI()
    StatusWindow.Init()
    CreatePage()
    SubscribeToEvents()
    StatusWindow.SetNoticesChanged(RefreshResourceNotices)
    RefreshResourceNotices()
    -- 正式会话的服务与计划都在 InitServices 里重建过，开场前再取一次事实，
    -- 这样 BootChat 与状态窗引用的是存档接管后的那一份事件实例
    RefreshSnapshot()
    BootChat()
    -- 开场就把这一份事件事实的身份挂上屏：同一天第二次进入时这里该读成 计划=存档
    if lastFact_ then
        DevTestPanel.SetDetail(lastFact_.id .. " · " .. lastFact_.sceneId
            .. " · 计划=" .. (lastFact_.planFromSave and "存档" or "当场"))
    end

    logInfo(string.format(
        "M1 已就绪：状态窗 + 排队聊天（空闲等待 %.0f 秒，跳过按钮=%s，云记忆=%s）",
        CONFIG.ReplyWaitSeconds, tostring(CONFIG.DevTools), tostring(CONFIG.UseCloudMemory)))
end

function Stop()
    MemoryService.FlushCloud()
    DevTestPanel.Shutdown()
    ProfileOverlay.Shutdown()
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

---@param saveFile? string 独立存档路径（开发自检用），省略则用玩家的历史
function InitServices(saveFile)
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
    MemoryService.Init({ cityId = CONFIG.City, cloud = adapter, saveFile = saveFile })
    local _, source = MemoryService.Load()
    logInfo("记忆装载来源: " .. source)
    -- 档案在记忆之后、事件层之前接：存档带 profile 就原样恢复；v1–v4 旧档由
    -- MemoryService 迁移成 LA×陌生网友（initialized=true，不弹初始化）；
    -- 干净安装没有 profile → 标为未初始化，等 BootChat 弹首次选择。
    local saved = MemoryService.GetProfile()
    if saved then
        ProfileService.Set(saved.cityId, saved.relationId, {
            seedText = saved.seedText,
            isRandom = saved.isRandom,
            initialized = saved.initialized,
        })
    else
        ProfileService.Set(CONFIG.City, "stranger", { initialized = false })
    end
    logInfo(string.format("档案: 城市=%s 关系=%s 随机=%s 已初始化=%s",
        saved and saved.cityId or CONFIG.City, saved and saved.relationId or "stranger",
        tostring(saved and saved.isRandom or false),
        tostring(saved and saved.initialized or false)))
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
        -- 干净安装：开场白要等玩家选完城市与关系再写，不然会把默认 LA 的话先钉进历史。
        -- 这里不落盘，profile 只在内存里标着未初始化。
        logInfo("档案未初始化：等待首次城市与关系选择")
        ProfileOverlay.Show({ mode = "init", onConfirm = HandleProfileInit })
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

--- 统一的换档案入口：首次初始化与中途「换档案」走同一条路（设计 §7）。
--- 队列与 FIFO 一律不动：排队中的消息到点按新城事实回复（她人在新城）；
--- 已上屏的历史不重建行，旧城市戳原样保留。
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

--- 首次初始化确认：写开场白与计划，之后与正常会话同一条链路
function HandleProfileInit(cityId, relationId, isRandom)
    ProfileOverlay.Hide()
    ApplyProfile(cityId, relationId, { isRandom = isRandom, firstTime = true })
    WriteBootGreeting(0)
    ChatPanel.SetDraft(ProfileService.DefaultDraft())
end

--- 顶栏「换档案」：重开覆盖层（switch 模式带取消；随机只在首次给）
function HandleProfileEntry()
    ProfileOverlay.Show({
        mode = "switch",
        onConfirm = function(cityId, relationId, isRandom)
            ProfileOverlay.Hide()
            ApplyProfile(cityId, relationId, { isRandom = isRandom })
        end,
        onCancel = function()
            logInfo("换档案已取消，档案保持 " .. ProfileService.GetCityId())
        end,
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
        bottom = 10,
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
    -- backgroundImage 不在这里给：要等静帧到手后再设，见下方 WarmUpBackground
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

    local chat = ChatPanel.Build({
        devTools = CONFIG.DevTools,
        initialDraft = ProfileService.DefaultDraft(),
        minHeight = 190,
        outerWidth = chatOuterWidth,
        onSend = HandleSend,
        onSkip = HandleSkip,
        onDraftChange = MessageService.SetDraft,
        onQuote = HandleQuote,
        onProfileEntry = HandleProfileEntry,
        getMessages = MessageService.GetMessages,
        getVersion = MessageService.GetVersion,
    })

    if CONFIG.DevTools then
        devTestPanel_ = DevTestPanel.Build({
            onPreset = HandleDevPreset,
            onReset = HandleDevReset,
            onAdvance = HandleDevAdvance,
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
                        pointerEvents = "none",
                        children = {
                            preview,
                            infoCard,
                        },
                    },
                    errorLabel_,
                    chat,
                    noteLabel_,
                },
            },
            devTestPanel_,
            -- 初始化/换档案覆盖层：绝对定位铺满整页，默认不可见，最后挂保证压在一切之上
            ProfileOverlay.Build(),
        },
    }

    UI.SetRoot(uiRoot_)
    logInfo("竖屏页面已创建：顶部真 4:3 状态窗 + 下方可交互聊天区")

    -- 静帧到手之后才挂背景：UI 的 ImageCache 会把首次加载失败永久缓存，
    -- DWP 冷启动时提前挂上去会让背景在整个会话里静默缺失。
    StatusWindow.WarmUpBackground(function(path)
        preview:SetBackgroundImage(path)
        logInfo("状态窗背景已挂载: " .. path)
    end)
    ApplyScene()
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

--- 状态窗按 scene_id 尝试换远景；没有资产时 RequestScene 会留在当前静帧
function ApplyScene()
    local widget = preview_
    if not lastSnap_ or not widget then
        return
    end
    local sceneId = (lastFact_ and lastFact_.sceneId) or lastSnap_.sceneId or ""
    local result = StatusWindow.RequestScene(sceneId, function(path)
        widget:SetBackgroundImage(path)
    end)
    if result == "missing-asset" then
        logInfo("场景降级: " .. sceneId .. "（缺原创静帧，沿用当前画面）")
        RefreshNoteLine()
    elseif result == "pending" then
        RefreshNoteLine()
    end
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
