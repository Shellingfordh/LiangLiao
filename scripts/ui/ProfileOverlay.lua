-- ============================================================================
-- ProfileOverlay.lua — 城市 × 关系初始化 / 换档案覆盖层（M3 §7）
-- 紧凑一张卡：城市 chips（初始化时多一枚「随机」）+ 关系 chips + 预览行 + 确认。
-- 盖在整页之上但卡片只占中部，不遮状态窗与输入区主体；窄屏 chips 换行不裁切。
-- 所有按钮 focusable=false：页面上方有输入框，按钮若可聚焦会重演
-- 「失焦收键盘 → 布局位移 → 点击静默丢失」那条实测坑（AGENTS 硬边界）。
-- 本模块只收集选择，不写档案也不落盘——那都是 main.lua 的 ApplyProfile 的事。
-- ============================================================================

local UI = require("urhox-libs/UI")
local ProfileService = require("ProfileService")

local ProfileOverlay = {}

local RANDOM_PICK = "random"

local COLORS = {
    scrim = { 8, 9, 12, 190 },
    card = { 20, 22, 27, 250 },
    title = { 238, 233, 224, 245 },
    dim = { 150, 148, 144, 190 },
    accent = { 200, 162, 122, 255 },
}

---@type Widget|nil
local root_ = nil
---@type Label|nil
local title_ = nil
---@type Label|nil
local preview_ = nil
---@type Label|nil
local hint_ = nil
---@type Button|nil
local cancelButton_ = nil
---@type Widget|nil
local randomChip_ = nil
local visible_ = false
local pickedCity_ = nil   ---@type string?
local pickedRelation_ = nil ---@type string?
---@type "init"|"switch"
local mode_ = "init"
---@type fun(cityId: string, relationId: string, isRandom: boolean)|nil
local onConfirm_ = nil
---@type fun()|nil
local onCancel_ = nil

--- 非随机时城市决定默认关系起点；预览行说「这座城市她是谁 + 你们怎么认识」，
--- 让用户在确认前就看到城市 × 关系共同决定的档案，而不是一个换名游戏。
local function RefreshPreview()
    if not preview_ then
        return
    end
    if pickedCity_ == RANDOM_PICK then
        preview_:SetText("随机 · 由创建时刻定种，抽到哪座城、什么关系，落盘后不再变")
        if hint_ then
            hint_:SetText("下面四枚城市与四枚关系都由这一次随机决定，不用再挑")
        end
        return
    end
    local city = pickedCity_ and ProfileService.CityFor(pickedCity_)
    if not city then
        preview_:SetText("先选一座城市")
        return
    end
    local relationId = pickedRelation_ or city.defaultRelation
    local relation = ProfileService.RelationFor(relationId)
    preview_:SetText(string.format("%s · %s ｜ %s × %s",
        city.label, city.identity, relation and relation.label or "?", city.label))
    if hint_ then
        hint_:SetText("她按当地时间生活；在忙或在睡时，你的消息会排队")
    end
end

---@param label string
---@param onPress fun()
---@return Widget
local function MakeChip(label, onPress)
    local chip = UI.Button {
        text = label,
        variant = "secondary",
        fontSize = 11,
        height = 30,
        paddingLeft = 10,
        paddingRight = 10,
        focusable = false,
    }
    chip.focusable = false
    -- 与其它非输入框主操作同一条链路：OnClick 只走正常抬起；
    -- 覆盖层没有输入框抢焦点，OnClick 足够可靠，但保留按下即回调的兜底不做双重触发。
    function chip:OnClick()
        onPress()
    end
    return chip
end

--- 构建并返回覆盖层子树；初始不可见，由 Show/Hide 控制
---@return Widget
function ProfileOverlay.Build()
    if root_ then
        return root_
    end

    pickedCity_ = nil
    pickedRelation_ = nil

    title_ = UI.Label {
        id = "profileTitle",
        text = "选择你想遇见她的城市",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = COLORS.title,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    preview_ = UI.Label {
        id = "profilePreview",
        text = "先选一座城市",
        fontSize = 11,
        fontColor = COLORS.accent,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    hint_ = UI.Label {
        id = "profileHint",
        text = "她按当地时间生活；在忙或在睡时，你的消息会排队",
        fontSize = 10,
        fontColor = COLORS.dim,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }

    ---@type Widget[]
    local cityChips = {}
    for i = 1, #ProfileService.CITY_ORDER do
        local cityId = ProfileService.CITY_ORDER[i]
        local city = ProfileService.CityFor(cityId)
        cityChips[#cityChips + 1] = MakeChip(city.label, function()
            pickedCity_ = cityId
            pickedRelation_ = city.defaultRelation
            RefreshPreview()
        end)
    end
    -- 随机入口只在初始化时给；换档案时目标明确，不再赌一次（Show 里按 mode 隐藏）
    randomChip_ = MakeChip("随机", function()
        if mode_ == "switch" then
            return
        end
        pickedCity_ = RANDOM_PICK
        pickedRelation_ = nil
        RefreshPreview()
    end)
    cityChips[#cityChips + 1] = randomChip_

    ---@type Widget[]
    local relationChips = {}
    for i = 1, #ProfileService.RELATION_ORDER do
        local relationId = ProfileService.RELATION_ORDER[i]
        local relation = ProfileService.RelationFor(relationId)
        relationChips[#relationChips + 1] = MakeChip(relation.label, function()
            if pickedCity_ == RANDOM_PICK then
                return
            end
            pickedRelation_ = relationId
            RefreshPreview()
        end)
    end

    local confirmButton = UI.Button {
        id = "profileConfirm",
        text = "就这么开始",
        variant = "primary",
        fontSize = 13,
        height = 38,
        focusable = false,
    }
    confirmButton.focusable = false
    function confirmButton:OnClick()
        if not pickedCity_ or not onConfirm_ then
            return
        end
        onConfirm_(pickedCity_, pickedRelation_ or "stranger", pickedCity_ == RANDOM_PICK)
    end

    local cancelButton = UI.Button {
        id = "profileCancel",
        text = "先不换",
        variant = "secondary",
        fontSize = 12,
        height = 38,
        focusable = false,
        visible = false,
    }
    cancelButton.focusable = false
    function cancelButton:OnClick()
        ProfileOverlay.Hide()
        if onCancel_ then
            onCancel_()
        end
    end

    root_ = UI.Panel {
        id = "profileOverlay",
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
                id = "profileCard",
                width = "82%",
                maxWidth = 360,
                flexDirection = "column",
                gap = 8,
                paddingHorizontal = 16,
                paddingVertical = 14,
                borderRadius = 14,
                backgroundColor = COLORS.card,
                borderWidth = 1,
                borderColor = { 122, 130, 142, 90 },
                children = {
                    title_,
                    UI.Row {
                        flexWrap = "wrap",
                        gap = 6,
                        children = cityChips,
                    },
                    UI.Row {
                        flexWrap = "wrap",
                        gap = 6,
                        children = relationChips,
                    },
                    preview_,
                    hint_,
                    UI.Row {
                        gap = 8,
                        children = { confirmButton, cancelButton },
                    },
                },
            },
        },
    }
    cancelButton_ = cancelButton
    return root_
end

---@class ProfileOverlayShowOptions
---@field mode? "init" | "switch" 初始化无取消；换档案给取消
---@field onConfirm fun(cityId: string, relationId: string, isRandom: boolean)
---@field onCancel? fun()

---@param opts ProfileOverlayShowOptions
function ProfileOverlay.Show(opts)
    if not root_ then
        ProfileOverlay.Build()
    end
    pickedCity_ = nil
    pickedRelation_ = nil
    onConfirm_ = opts.onConfirm
    onCancel_ = opts.onCancel
    local isSwitch = opts.mode == "switch"
    mode_ = isSwitch and "switch" or "init"
    title_:SetText(isSwitch and "换一个档案再见她" or "选择你想遇见她的城市")
    if cancelButton_ then
        cancelButton_:SetVisible(isSwitch)
    end
    if randomChip_ then
        randomChip_:SetVisible(not isSwitch)
    end
    RefreshPreview()
    visible_ = true
    root_:SetVisible(true)
end

function ProfileOverlay.Hide()
    visible_ = false
    if root_ then
        root_:SetVisible(false)
    end
end

---@return boolean
function ProfileOverlay.IsVisible()
    return visible_
end

function ProfileOverlay.Shutdown()
    root_ = nil
    title_ = nil
    preview_ = nil
    hint_ = nil
    cancelButton_ = nil
    randomChip_ = nil
    visible_ = false
    onConfirm_ = nil
    onCancel_ = nil
end

return ProfileOverlay
