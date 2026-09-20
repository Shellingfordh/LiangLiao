-- ============================================================================
-- 《送给你这个回来的人》M0-0
-- 竖屏手机原型：固定镜头 3D 状态窗展示原创角色「若夕」
-- 本阶段不做聊天、存档、动画、天气或任何在线服务。
-- ============================================================================

local UI = require("urhox-libs/UI")
local StatusWindow = require("StatusWindow")

local CONFIG = {
    Title = "送给你这个回来的人",
    StatusLine = "若夕 · 洛杉矶 18:20 · 还在外面",
}

---@type Widget|nil
local uiRoot_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Label|nil
local errorLabel_ = nil
---@type Label|nil
local noteLabel_ = nil

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
        text = CONFIG.StatusLine,
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

    -- 高度跟随顶部 35% 区域，宽度由 4:3 算出，避免竖屏上被拉满整宽
    local preview = StatusWindow.CreatePreviewWidget({
        id = "statusPreview",
        height = "100%",
        maxWidth = "100%",
        aspectRatio = 4 / 3,
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
                        height = "35%",
                        minHeight = 160,
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
    logInfo("竖屏页面已创建：顶部 4:3 状态窗约占 35% 高度")
end

function RefreshResourceNotices()
    local messages = {}
    local modelError = StatusWindow.GetModelError()
    if modelError ~= "" then
        messages[#messages + 1] = modelError
    end
    if StatusWindow.IsUsingPlaceholderBackground() then
        messages[#messages + 1] = "背景图尚未导入，已使用中性临时窗景。待替换 la-cafe-4x3.png"
    end

    if #messages > 0 then
        errorLabel_:SetText(table.concat(messages, " "))
        errorLabel_:SetVisible(true)
    else
        errorLabel_:SetText("")
        errorLabel_:SetVisible(false)
    end
end

function SubscribeToEvents()
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        engine:Exit()
    end
end
