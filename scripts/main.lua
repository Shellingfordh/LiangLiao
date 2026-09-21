-- ============================================================================
-- 《送给你这个回来的人》M0-1 起步
-- 竖屏手机原型：固定镜头 3D 状态窗 + 由真实时间驱动的生活状态
-- 本阶段接时间/可用性；聊天、排队、存档在后续模块。
-- ============================================================================

local UI = require("urhox-libs/UI")
local StatusWindow = require("StatusWindow")
local TimeState = require("TimeState")

local CONFIG = {
    Title = "送给你这个回来的人",
    City = "los_angeles",
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
local clockElapsed_ = 0

local function logInfo(msg)
    print("[M0-0] " .. msg)
    log:Write(LOG_INFO, "[M0-0] " .. msg)
end

function Start()
    graphics.windowTitle = CONFIG.Title
    -- 禁止自由相机 / 相对鼠标，保持光标可见，无镜头旋转
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    logInfo("启动 M0-0 原型")
    logInfo("屏幕物理分辨率: " .. tostring(graphics.width) .. "x" .. tostring(graphics.height)
        .. " DPR=" .. tostring(graphics:GetDPR()))

    -- 时间层先落一条日志：真机上没有 console，状态算错时这条是唯一线索
    local snap = TimeState.Snapshot(CONFIG.City)
    statusLine_ = snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
    logInfo(string.format("时间状态: %s %s %s UTC%+d DST=%s 季节=%s 天气=%s 可用性=%s 地点=%s",
        snap.dateKey, snap.clock, snap.cityLabel,
        math.floor(snap.offsetSeconds / 3600), tostring(snap.isDst),
        snap.season, snap.weather, snap.availability, snap.place))

    InitUI()
    StatusWindow.Init()
    CreatePage()
    SubscribeToEvents()
    StatusWindow.SetNoticesChanged(RefreshResourceNotices)
    RefreshResourceNotices()

    logInfo("M0-0 已就绪：固定镜头状态窗，无摇杆/旋转/点击互动")
end

function Stop()
    StatusWindow.Shutdown()
    UI.Shutdown()
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
        text = "M0-0 状态窗预览 · 镜头已锁定",
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
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        id = "statusWindowFrame",
                        width = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "none",
                        children = {
                            preview,
                        },
                    },
                    statusLabel_,
                    errorLabel_,
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        pointerEvents = "none",
                    },
                    noteLabel_,
                },
            },
        },
    }

    UI.SetRoot(uiRoot_)
    logInfo("竖屏页面已创建：顶部真 4:3 状态窗，高度由宽度推出")

    -- 静帧到手之后才挂背景：UI 的 ImageCache 会把首次加载失败永久缓存，
    -- DWP 冷启动时提前挂上去会让背景在整个会话里静默缺失。
    StatusWindow.WarmUpBackground(function(path)
        preview:SetBackgroundImage(path)
        logInfo("状态窗背景已挂载: " .. path)
    end)
end

function RefreshResourceNotices()
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
    local line = TimeState.StatusLine(CONFIG.City)
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
