-- ============================================================================
-- SettingsOverlay.lua — 设置层：三个明确入口（M4 §3）
-- 「查看档案 / 换一段人生 / 新故事」收进一张紧凑卡片；打开不遮状态窗主体，
-- 关闭即回聊天。本模块只收集意图，切段与建档全在 main.lua。
-- 结构 Build 一次成型、Show 只换回调槽：ClearChildren 不销毁 Yoga 节点
-- （ChatPanel 同款实测教训），反复重建会漏布局。
-- 按钮一律 focusable=false + OnPointerDown：页面上方有输入框，
-- 失焦收键盘会让 OnClick 静默丢失（AGENTS 实测坑）。
-- ============================================================================

local UI = require("urhox-libs/UI")

local SettingsOverlay = {}

local COLORS = {
    scrim = { 8, 9, 12, 190 },
    card = { 20, 22, 27, 250 },
    title = { 238, 233, 224, 245 },
    dim = { 150, 148, 144, 190 },
}

---@type Widget|nil
local root_ = nil
---@type fun()|nil
local onProfile_ = nil
---@type fun()|nil
local onSwitch_ = nil
---@type fun()|nil
local onNew_ = nil

---@param label string
---@param desc string
---@param onPress fun()
---@return Widget
local function MakeEntryRow(label, desc, onPress)
    local btn = UI.Button {
        text = label,
        variant = "secondary",
        fontSize = 13,
        height = 44,
        paddingLeft = 12,
        paddingRight = 12,
        focusable = false,
    }
    btn.focusable = false
    function btn:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
        self:SetState({ pressed = true })
        self:TransitionToStateBgColor()
        onPress()
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
        children = {
            btn,
            UI.Label {
                text = desc,
                fontSize = 10,
                fontColor = COLORS.dim,
                whiteSpace = "normal",
                wordBreak = "break-word",
            },
        },
    }
end

--- 构建并返回覆盖层子树；初始不可见，由 Show/Hide 控制
---@return Widget
function SettingsOverlay.Build()
    if root_ then
        return root_
    end
    root_ = UI.Panel {
        id = "settingsOverlay",
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = COLORS.scrim,
        visible = false,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                id = "settingsCard",
                width = "82%",
                maxWidth = 360,
                flexDirection = "column",
                gap = 10,
                paddingHorizontal = 16,
                paddingVertical = 14,
                borderRadius = 14,
                backgroundColor = COLORS.card,
                borderWidth = 1,
                borderColor = { 122, 130, 142, 90 },
                children = {
                    UI.Label {
                        text = "设置",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = COLORS.title,
                    },
                    MakeEntryRow("查看档案", "她住在哪、此刻在做什么、留下了什么生活痕迹", function()
                        if onProfile_ then
                            onProfile_()
                        end
                    end),
                    MakeEntryRow("换一段人生", "在已有人生卡片之间切换（最多三段）", function()
                        if onSwitch_ then
                            onSwitch_()
                        end
                    end),
                    MakeEntryRow("新故事", "选一座城市和一段关系起点，开始独立的一段人生", function()
                        if onNew_ then
                            onNew_()
                        end
                    end),
                    MakeEntryRow("关闭", "回到聊天", function()
                        SettingsOverlay.Hide()
                    end),
                },
            },
        },
    }
    return root_
end

---@class SettingsOverlayOptions
---@field onProfile fun()
---@field onSwitch fun()
---@field onNew fun()

---@param opts SettingsOverlayOptions
function SettingsOverlay.Show(opts)
    if not root_ then
        SettingsOverlay.Build()
    end
    onProfile_ = opts.onProfile
    onSwitch_ = opts.onSwitch
    onNew_ = opts.onNew
    root_:SetVisible(true)
end

function SettingsOverlay.Hide()
    if root_ then
        root_:SetVisible(false)
    end
end

---@return boolean
function SettingsOverlay.IsVisible()
    return root_ ~= nil and root_:IsVisible() == true
end

function SettingsOverlay.Shutdown()
    root_ = nil
    onProfile_ = nil
    onSwitch_ = nil
    onNew_ = nil
end

return SettingsOverlay
