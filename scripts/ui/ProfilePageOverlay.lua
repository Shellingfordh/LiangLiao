-- ============================================================================
-- ProfilePageOverlay.lua — 只读角色档案页（M4 §4）
-- 展示：城市、当地时间、身份、关系起点、近期生活线索、当前状态与一条当前生活痕迹。
-- 全部字段由 main.lua 从「当前那一份人生」的同一事实源派生（快照 + 事件计划 +
-- 事件账本 + 痕迹），本页不查服务、不改状态、不兼任换档案选择层。
-- 只读 = 没有任何入口按钮会改写档案；关闭是唯一操作。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ProfilePageOverlay = {}

local COLORS = {
    scrim = { 8, 9, 12, 190 },
    card = { 20, 22, 27, 250 },
    title = { 238, 233, 224, 245 },
    label = { 150, 148, 144, 190 },
    value = { 214, 209, 200, 240 },
    accent = { 200, 162, 122, 255 },
}

---@type Widget|nil
local root_ = nil
---@type Label|nil
local cityClockLabel_ = nil
---@type Label|nil
local identityLabel_ = nil
---@type Label|nil
local relationLabel_ = nil
---@type Label|nil
local sceneLabel_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Label|nil
local recentLabel_ = nil
---@type Label|nil
local traceLabel_ = nil

---@param labelText string
---@param valueLabel Label
---@return Widget
local function MakeRow(labelText, valueLabel)
    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 1,
        children = {
            UI.Label {
                text = labelText,
                fontSize = 9,
                fontColor = COLORS.label,
                whiteSpace = "nowrap",
            },
            valueLabel,
        },
    }
end

---@return Widget
function ProfilePageOverlay.Build()
    if root_ then
        return root_
    end
    local function Value()
        return UI.Label {
            text = "",
            fontSize = 11,
            fontColor = COLORS.value,
            whiteSpace = "normal",
            wordBreak = "break-word",
            lineHeight = 1.35,
        }
    end
    cityClockLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = COLORS.accent,
        whiteSpace = "normal",
        wordBreak = "break-word",
        lineHeight = 1.35,
    }
    identityLabel_ = Value()
    relationLabel_ = Value()
    sceneLabel_ = Value()
    statusLabel_ = Value()
    recentLabel_ = Value()
    traceLabel_ = Value()

    -- 关闭按钮：`focusable = false` 这条属性是**装饰性的** —— 引擎派发焦点时读的是控件实例上的
    -- 字段（UI.lua 里 `widget.focusable ~= false`），而 Button 的 props.onClick 走的是
    -- 「按下与抬起命中同一控件」的 OnClick 链路。少那句实例赋值，键盘收起造成的布局位移就会
    -- 让这一点静默失效（AGENTS 实测坑；2026-09-25 本地控件树取证抓到）。
    local closeButton = UI.Button {
        id = "profilePageClose",
        text = "Close",
        variant = "secondary",
        fontSize = 12,
        height = 34,
        focusable = false,
    }
    closeButton.focusable = false
    function closeButton:OnClick()
        ProfilePageOverlay.Hide()
    end

    root_ = UI.Panel {
        id = "profilePageOverlay",
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
                id = "profilePageCard",
                width = "86%",
                maxWidth = 380,
                height = "80%",
                maxHeight = "80%",
                flexDirection = "column",
                gap = 9,
                paddingHorizontal = 16,
                paddingVertical = 14,
                borderRadius = 14,
                backgroundColor = COLORS.card,
                borderWidth = 1,
                borderColor = { 122, 130, 142, 90 },
                pointerEvents = "auto",
                children = {
                    UI.Label {
                        text = "About Ruoxi",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = COLORS.title,
                    },
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        flexShrink = 1,
                        flexBasis = 0,
                        scrollY = true,
                        showScrollbar = true,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "column",
                                gap = 9,
                                children = {
                                    MakeRow("City · Local time", cityClockLabel_),
                                    MakeRow("Her everyday life", identityLabel_),
                                    MakeRow("How you know her", relationLabel_),
                                    MakeRow("Where she is", sceneLabel_),
                                    MakeRow("Right now", statusLabel_),
                                    MakeRow("Recent moments", recentLabel_),
                                    MakeRow("A trace of her day", traceLabel_),
                                },
                            },
                        },
                    },
                    closeButton,
                },
            },
        },
    }
    return root_
end

---@class ProfilePageData
---@field cityClock string 城市 · 当地时间
---@field identity string 生活身份
---@field relation string 关系起点
---@field scene string 此刻所在（场景包 label + 地点）
---@field status string 当前状态（可用性 + 作息原话）
---@field recent string[] 近期生活线索（最多三条，可读句子，不含原始事件键）
---@field trace string 当前生活痕迹一句（与状态窗画面同源）

---@param data ProfilePageData
function ProfilePageOverlay.Show(data)
    if not root_ then
        ProfilePageOverlay.Build()
    end
    cityClockLabel_:SetText(data.cityClock or "")
    identityLabel_:SetText(data.identity or "")
    relationLabel_:SetText(data.relation or "")
    sceneLabel_:SetText(data.scene or "")
    statusLabel_:SetText(data.status or "")
    recentLabel_:SetText(#data.recent > 0 and table.concat(data.recent, "\n") or "No recent moments yet.")
    traceLabel_:SetText(data.trace ~= "" and data.trace or "No trace left yet.")
    root_:SetVisible(true)
end

function ProfilePageOverlay.Hide()
    if root_ then
        root_:SetVisible(false)
    end
end

---@return boolean
function ProfilePageOverlay.IsVisible()
    return root_ ~= nil and root_:IsVisible() == true
end

function ProfilePageOverlay.Shutdown()
    root_ = nil
    cityClockLabel_ = nil
    identityLabel_ = nil
    relationLabel_ = nil
    sceneLabel_ = nil
    statusLabel_ = nil
    recentLabel_ = nil
    traceLabel_ = nil
end

return ProfilePageOverlay
