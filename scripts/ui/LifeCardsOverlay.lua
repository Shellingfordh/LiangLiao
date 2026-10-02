-- ============================================================================
-- LifeCardsOverlay.lua — 人生卡片层（M4 §3「换一段人生」/ 满三段时的替换选择）
-- 一张人生卡 = 一份完整独立存档的摘要：城市、关系、当地钟点、当前状态、
-- 最近打开、当前痕迹一句话。mode="switch" 点卡切换；mode="replace" 点卡覆盖建新故事
-- （创建第四段前必须由用户明确点名替换，绝不自动淘汰）。
-- 卡片行 Build 时固定三张（MAX=3），Show 只换文字与回调槽 —— 不 ClearChildren。
-- ============================================================================

local UI = require("urhox-libs/UI")

local LifeCardsOverlay = {}

local MAX_CARDS = 3

local COLORS = {
    scrim = { 8, 9, 12, 190 },
    card = { 26, 28, 34, 252 },
    cardActive = { 38, 42, 52, 252 },
    title = { 238, 233, 224, 245 },
    dim = { 150, 148, 144, 190 },
    accent = { 200, 162, 122, 255 },
}

---@type Widget|nil
local root_ = nil
---@type Label|nil
local title_ = nil
---@type Label|nil
local hint_ = nil
---@type Button|nil
local cancelButton_ = nil
---@type { head: Label, body: Label, panel: Widget, slotId: string? }[]
local cards_ = {}
---@type fun(slotId: string)|nil
local onPick_ = nil

---@param index integer
---@return Widget
local function MakeCard(index)
    local head = UI.Label {
        text = "",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = COLORS.title,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    local body = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = COLORS.dim,
        whiteSpace = "normal",
        wordBreak = "break-word",
        lineHeight = 1.3,
    }
    local panel
    panel = UI.Panel {
        id = "lifeCardPanel" .. tostring(index),
        width = "100%",
        flexDirection = "column",
        gap = 3,
        paddingHorizontal = 12,
        paddingVertical = 9,
        borderRadius = 10,
        backgroundColor = COLORS.card,
        borderWidth = 1,
        borderColor = { 122, 130, 142, 70 },
        pointerEvents = "auto",
        children = { head, body },
    }
    -- 整张卡片就是点击区：Widget 基类的 OnPointerDown 会被命中派发（与 Button 同一条链路），
    -- 不依赖 OnClick 的「按下抬起同控件」条件（AGENTS 实测坑）。
    function panel:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
        local slotId = cards_[index].slotId
        if slotId and onPick_ then
            onPick_(slotId)
        end
    end
    cards_[index] = { head = head, body = body, panel = panel, slotId = nil }
    return panel
end

---@return Widget
function LifeCardsOverlay.Build()
    if root_ then
        return root_
    end
    ---@type Widget[]
    local cardWidgets = {}
    for i = 1, MAX_CARDS do
        cardWidgets[i] = MakeCard(i)
    end
    title_ = UI.Label {
        text = "Switch story",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = COLORS.title,
    }
    hint_ = UI.Label {
        text = "",
        fontSize = 10,
        fontColor = COLORS.dim,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    cancelButton_ = UI.Button {
        id = "lifeCardsCancel",
        text = "Cancel",
        variant = "secondary",
        fontSize = 12,
        height = 34,
        focusable = false,
    }
    cancelButton_.focusable = false
    function cancelButton_:OnPointerDown(event)
        if event and event:IsPrimaryAction() then
            LifeCardsOverlay.Hide()
        end
    end

    root_ = UI.Panel {
        id = "lifeCardsOverlay",
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
                id = "lifeCardsCard",
                width = "88%",
                maxWidth = 380,
                flexDirection = "column",
                gap = 8,
                paddingHorizontal = 14,
                paddingVertical = 12,
                borderRadius = 14,
                backgroundColor = COLORS.card,
                borderWidth = 1,
                borderColor = { 122, 130, 142, 90 },
                children = {
                    title_,
                    hint_,
                    cardWidgets[1],
                    cardWidgets[2],
                    cardWidgets[3],
                    cancelButton_,
                },
            },
        },
    }
    return root_
end

---@class LifeCardEntry
---@field slotId string
---@field head string 一行标题（城市 × 关系 · 当前）
---@field body string 摘要正文（钟点、状态、痕迹、最近打开）
---@field isActive boolean

---@class LifeCardsShowOptions
---@field title string
---@field hint string
---@field cards LifeCardEntry[]
---@field onPick fun(slotId: string)
---@field cancelText? string

---@param opts LifeCardsShowOptions
function LifeCardsOverlay.Show(opts)
    if not root_ then
        LifeCardsOverlay.Build()
    end
    title_:SetText(opts.title)
    hint_:SetText(opts.hint)
    onPick_ = opts.onPick
    if opts.cancelText then
        cancelButton_:SetText(opts.cancelText)
    end
    for i = 1, MAX_CARDS do
        local entry = opts.cards[i]
        local card = cards_[i]
        if entry then
            card.slotId = entry.slotId
            card.head:SetText(entry.head)
            card.body:SetText(entry.body)
            card.panel:SetVisible(true)
            card.panel:SetStyle({ backgroundColor = entry.isActive and COLORS.cardActive or COLORS.card })
        else
            card.slotId = nil
            card.panel:SetVisible(false)
        end
    end
    root_:SetVisible(true)
end

function LifeCardsOverlay.Hide()
    if root_ then
        root_:SetVisible(false)
    end
end

---@return boolean
function LifeCardsOverlay.IsVisible()
    return root_ ~= nil and root_:IsVisible() == true
end

function LifeCardsOverlay.Shutdown()
    root_ = nil
    title_ = nil
    hint_ = nil
    cancelButton_ = nil
    cards_ = {}
    onPick_ = nil
end

return LifeCardsOverlay
