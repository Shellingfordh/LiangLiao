-- ============================================================================
-- 《送给你这个回来的人》M0-1 竖切片
-- 竖屏手机：固定镜头 4:3 状态窗 + 真实时间驱动的生活状态 + 一条完整聊天闭环
-- 后端 = 同工程内的四个 Lua 服务（消息/事件/内容/记忆），无外部服务、无 LLM。
-- ============================================================================

local UI = require("urhox-libs/UI")
local StatusWindow = require("StatusWindow")
local TimeState = require("TimeState")
local MessageService = require("services.MessageService")
local EventService = require("services.EventService")
local ContentService = require("services.ContentService")
local MemoryService = require("services.MemoryService")
local ChatPanel = require("ui.ChatPanel")

---@type {Title: string, City: string, ReplyWaitSeconds: integer, DevTools: boolean, UseCloudMemory: boolean}
local CONFIG = {
    Title = "送给你这个回来的人",
    City = "los_angeles",
    ReplyWaitSeconds = 10,   -- 正式发送链路的固定等待
    DevTools = true,         -- 开发预览：显示「跳过等待」
    UseCloudMemory = false,  -- 预览不绑定云存储，只保留异步接口
}

---@type Widget|nil
local uiRoot_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Label|nil
local errorLabel_ = nil
---@type Label|nil
local noteLabel_ = nil

-- 上一次上屏的状态文案，用来判断这一分钟要不要重画
local statusLine_ = ""
---@type number
local clockElapsed_ = 0
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

--- 刷新时间快照，并保证 lastFact_ 与它同源
local function RefreshSnapshot()
    local snap = TimeState.Snapshot(CONFIG.City)
    lastSnap_ = snap
    lastFact_ = EventService.FromSnapshot(snap)
    return snap
end

--- 把 MessageService 的当前相位推给聊天面板
local function PushChatPhase()
    local phase = MessageService.GetPhase()
    local awaiting = MessageService.IsAwaiting()
    local statusText = awaiting and MessageService.StatusText(phase, nil) or ""
    ChatPanel.SetPhase(phase, statusText, awaiting)
end

--- 用户点发送 / 回车
---@param rawText string
function HandleSend(rawText)
    local snap = RefreshSnapshot()
    local text = (rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if MessageService.IsAwaiting() then
        -- 等待期间不许重复触发，但原文必须留在输入框里
        MessageService.SetDraft(text)
        ChatPanel.SetDraft(text)
        logInfo("等待回复中，本次发送已忽略并保留草稿")
        PushChatPhase()
        return
    end

    if text == "" then
        logInfo("空草稿，忽略发送")
        return
    end

    local msg = MessageService.Send(text, snap.utcSec, snap.clock)
    if not msg then
        logError("Send 被拒绝但相位是 idle，状态机不一致")
        return
    end
    ChatPanel.ClearDraft()
    logInfo(string.format("发送 #%d → sent（%.0f 秒后回复）", msg.id, CONFIG.ReplyWaitSeconds))
    PushChatPhase()
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

--- 状态机到点后的回复生成：事件事实 + 用户原文 → 模板
---@param pending MsgEntry
function HandleDeliver(pending)
    local snap = RefreshSnapshot()
    local fact = EventService.FromSnapshot(snap)
    lastFact_ = fact
    turnIndex_ = turnIndex_ + 1

    local replyText = ContentService.Reply(fact, pending.text, turnIndex_)
    local reply = MessageService.AppendReply(replyText, snap.utcSec, fact.id, snap.clock)
    local topics = ContentService.DetectTopics(pending.text)
    MemoryService.RecordTurn(pending, reply, fact, topics)
    ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())

    logInfo(string.format("回复 #%d → replied 事实=%s 状态=%s 话题=%s 正文=%s",
        pending.id, fact.id, fact.eventState,
        table.concat(topics, ",") == "" and "无" or table.concat(topics, ","),
        replyText))
end

function Start()
    graphics.windowTitle = CONFIG.Title
    -- 禁止自由相机 / 相对鼠标，保持光标可见，无镜头旋转
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    logInfo("启动 M0-1 竖切片")
    logInfo("屏幕物理分辨率: " .. tostring(graphics.width) .. "x" .. tostring(graphics.height)
        .. " DPR=" .. tostring(graphics:GetDPR()))

    -- 时间层先落一条日志：真机上没有 console，状态算错时这条是唯一线索
    local snap = RefreshSnapshot()
    statusLine_ = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
    logInfo(string.format("时间状态: %s %s %s UTC%+d DST=%s 季节=%s 天气=%s 可用性=%s 地点=%s",
        snap.dateKey, snap.clock, snap.cityLabel,
        math.floor(snap.offsetSeconds / 3600), tostring(snap.isDst),
        snap.season, snap.weather, snap.availability, snap.place))

    InitServices()
    InitUI()
    StatusWindow.Init()
    CreatePage()
    SubscribeToEvents()
    StatusWindow.SetNoticesChanged(RefreshResourceNotices)
    RefreshResourceNotices()
    BootChat()

    logInfo(string.format(
        "M0-1 已就绪：状态窗 + 聊天闭环（等待 %.0f 秒，跳过按钮=%s，云记忆=%s）",
        CONFIG.ReplyWaitSeconds, tostring(CONFIG.DevTools), tostring(CONFIG.UseCloudMemory)))
end

function Stop()
    MemoryService.FlushCloud()
    ChatPanel.Shutdown()
    StatusWindow.Shutdown()
    UI.Shutdown()
end

function InitServices()
    MessageService.Init({
        waitSeconds = CONFIG.ReplyWaitSeconds,
        hooks = {
            onPhaseChange = function()
                PushChatPhase()
            end,
            onDeliver = HandleDeliver,
        },
    })

    local adapter = nil
    if CONFIG.UseCloudMemory then
        adapter = MemoryService.DefaultClientCloudAdapter()
    end
    MemoryService.Init({ cityId = CONFIG.City, cloud = adapter })
    local _, source = MemoryService.Load()
    logInfo("记忆装载来源: " .. source)
    MemoryService.CloudLoadAsync()
end

--- 会话开场：一条系统说明 + 一条不属于回复链路的开场白
function BootChat()
    local fact = lastFact_
    local snap = lastSnap_
    if not fact or not snap then
        logError("开场时事件事实或时间快照为空，跳过开场")
        return
    end
    MessageService.AddSystem("M0-1 竖切片 · 现在只有「陌生网友 × 洛杉矶」这一条线",
        snap.utcSec, snap.clock)
    ChatPanel.SetMemoryLine(MemoryService.GetSummaryLine())
    logInfo("开场白（非回复链路）: " .. ContentService.OpeningLine(fact))
    MessageService.AppendReply(ContentService.OpeningLine(fact), snap.utcSec, fact.id, snap.clock)
    PushChatPhase()
end

function InitUI()
    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })
end

function CreatePage()
    statusLabel_ = UI.Label {
        id = "statusLine",
        text = TimeState.StatusLine(CONFIG.City),
        fontSize = 13,
        fontColor = { 210, 204, 196, 210 },
        textAlign = "left",
        whiteSpace = "nowrap",
        pointerEvents = "none",
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
        text = "M0-1 聊天竖切片 · 镜头仍锁定，回复走固定事件事实 + 模板",
        fontSize = 11,
        fontColor = { 150, 146, 140, 160 },
        textAlign = "left",
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

    local chat = ChatPanel.Build({
        devTools = CONFIG.DevTools,
        initialDraft = ContentService.DefaultDraft(),
        minHeight = 190,
        onSend = HandleSend,
        onSkip = HandleSkip,
        onDraftChange = MessageService.SetDraft,
        getMessages = MessageService.GetMessages,
        getVersion = MessageService.GetVersion,
    })

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
                        },
                    },
                    statusLabel_,
                    errorLabel_,
                    chat,
                    noteLabel_,
                },
            },
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
end

--- 状态文案一分钟一变；变了才重画，避免每帧 SetText
function RefreshStatusLine()
    local snap = RefreshSnapshot()
    local line = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
    if line ~= statusLine_ then
        statusLine_ = line
        if statusLabel_ then
            statusLabel_:SetText(line)
        end
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

    -- 消息状态机用真实秒推进；这就是 10 秒等待的唯一计时处
    MessageService.Update(timeStep)
    ChatPanel.Tick(timeStep)

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
