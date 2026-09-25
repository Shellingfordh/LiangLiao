-- ============================================================================
-- ProfileOverlay.lua — 城市 × 关系选择层（M3 §7 / M5「可控的新故事」）
-- 紧凑一张卡：城市 chips（初始化时多一枚「随机」）+ 关系 chips + 预览行 + 确认。
-- 盖在整页之上但卡片只占中部，不遮状态窗与输入区主体；窄屏 chips 换行不裁切。
--
-- M5 三条硬规则（缺陷「选上海×前同事却落成成都×高中同学」的根因，见 CHANGELOG）：
--  ① 主操作一律走 OnPointerDown 按下即回调，不再依赖 OnClick。引擎 UI.lua:2379 只在
--     「抬起仍命中按下那个控件」时才派发 OnClick；本卡片垂直居中，只要卡片内容高度变化
--     全部 chip 就跟着挪位，下一拍就会瞄在旧布局上 —— 落在隔壁 = 静默提交错值，
--     落在空白 = 静默丢弃，两者都不报任何错。与 ChatPanel / SettingsOverlay /
--     LifeCardsOverlay 同一条口径（AGENTS 实测坑）。
--  ② 预览行与提示行高度写死：卡片内容高度在任何点选组合下不变，①那条位移通道从根上封掉。
--  ③ 城市与关系两轴都必须由用户亲手点过才可确认。城市的 defaultRelation 只作为预填
--     提示显示，既不覆盖已显式选过的关系，也不代替用户提交；「随机」是唯一免两轴的入口。
--
-- 本模块只收集选择，不写档案也不落盘 —— 那都是 main.lua 的人生入口的事。
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

-- chip 的三态：未选 / 预填（城市带来的默认关系，还没被用户点过）/ 已选
---@alias ChipPick "idle"|"prefill"|"picked"
---@type table<ChipPick, { bg: integer[], border: integer[], text: integer[] }>
local CHIP_STYLE = {
    idle = {
        bg = { 30, 33, 40, 255 },
        border = { 122, 130, 142, 70 },
        text = { 206, 202, 196, 235 },
    },
    prefill = {
        bg = { 33, 37, 45, 255 },
        border = { 200, 162, 122, 120 },
        text = { 214, 209, 199, 240 },
    },
    picked = {
        bg = { 52, 43, 27, 255 },
        border = { 200, 162, 122, 255 },
        text = { 246, 239, 227, 255 },
    },
}

-- 预览/提示两行的高度写死：文字换行不再挪动任何一枚 chip（规则 ②）。
-- 预览留到 3 行的量：窄屏（320px 宽）下 82% 卡片内宽约 230px，最长那句 33 字要占 2 行，
-- 只按宽屏估会裁字——裁了没人报，只会读成「没选对」。
local PREVIEW_HEIGHT = 48
local HINT_HEIGHT = 18
local CHIP_HEIGHT = 30
local ACTION_HEIGHT = 38

---@type Widget|nil
local root_ = nil
---@type Label|nil
local title_ = nil
---@type Label|nil
local preview_ = nil
---@type Label|nil
local hint_ = nil
---@type Button|nil
local confirmButton_ = nil
---@type Button|nil
local cancelButton_ = nil
---@type { id: string, widget: Widget }[]
local cityChips_ = {}
---@type { id: string, widget: Widget }[]
local relationChips_ = {}
---@type { id: string, widget: Widget }|nil
local randomChip_ = nil
local visible_ = false
local pickedCity_ = nil   ---@type string?
local pickedRelation_ = nil ---@type string?
local cityChosen_ = false
local relationChosen_ = false
---@type "init"|"switch"
local mode_ = "init"
---@type fun(cityId: string, relationId: string, isRandom: boolean)|nil
local onConfirm_ = nil
---@type fun()|nil
local onCancel_ = nil

local function logWarn(msg)
    print("[Profile] WARN: " .. msg)
    log:Write(LOG_WARNING, "[Profile] " .. msg)
end

---@return boolean
local function IsRandomPick()
    return pickedCity_ == RANDOM_PICK
end

--- 两轴都要被用户亲手点过才允许确认；随机是唯一免两轴的入口（规则 ③）。
---@return boolean
local function CanConfirm()
    if IsRandomPick() then
        return true
    end
    return cityChosen_ == true and relationChosen_ == true
end

local function ResetSelection()
    pickedCity_ = nil
    pickedRelation_ = nil
    cityChosen_ = false
    relationChosen_ = false
end

---@param chips { id: string, widget: Widget }[]
---@param selectedId string|nil
---@param picked boolean 该轴是否已被用户亲手点过（否则命中只算预填）
local function PaintChips(chips, selectedId, picked)
    for i = 1, #chips do
        local chip = chips[i]
        ---@type ChipPick
        local kind = "idle"
        if selectedId ~= nil and chip.id == selectedId then
            kind = picked and "picked" or "prefill"
        end
        local style = CHIP_STYLE[kind]
        chip.widget:SetStyle({
            backgroundColor = style.bg,
            borderColor = style.border,
            textColor = style.text,
        })
    end
end

local function RefreshChips()
    local randomId = IsRandomPick() and RANDOM_PICK or nil
    PaintChips(cityChips_, randomId or pickedCity_, cityChosen_)
    if randomChip_ then
        local style = CHIP_STYLE[IsRandomPick() and "picked" or "idle"]
        randomChip_.widget:SetStyle({
            backgroundColor = style.bg,
            borderColor = style.border,
            textColor = style.text,
        })
    end
    -- 预填只在用户还没点过关系时以 prefill 态显示，绝不当成「已选」画成选中色
    PaintChips(relationChips_, pickedRelation_, relationChosen_)
end

local function RefreshPreview()
    if not preview_ or not hint_ then
        return
    end
    if IsRandomPick() then
        preview_:SetText("随机 · 由创建时刻定种，落盘后不再变")
        hint_:SetText("城市与关系都由这一次随机决定，不用再挑")
        RefreshChips()
        return
    end
    local city = pickedCity_ and ProfileService.CityFor(pickedCity_) or nil
    if not city then
        preview_:SetText("要点两下：一枚城市 + 一枚关系起点")
        hint_:SetText("她按当地时间生活，忙或在睡时消息排队")
        RefreshChips()
        return
    end
    local relation = pickedRelation_ and ProfileService.RelationFor(pickedRelation_) or nil
    if not relationChosen_ then
        -- 默认关系只是预填：说清楚还差一步，别让它替用户提交
        local prefill = relation and relation.label or "?"
        preview_:SetText(string.format("%s · %s｜关系起点未选（预填 %s）",
            city.label, city.identityShort, prefill))
        hint_:SetText("再点一枚关系起点才算选它")
    else
        preview_:SetText(string.format("就这么开始：%s × %s",
            relation and relation.label or "?", city.label))
        hint_:SetText("她按当地时间生活，忙或在睡时消息排队")
    end
    RefreshChips()
end

local function RefreshConfirmButton()
    if not confirmButton_ then
        return
    end
    local ready = CanConfirm()
    confirmButton_:SetStyle({ disabled = not ready })
end

--- 城市决定预填关系，但绝不覆盖用户已显式点过的关系（规则 ③）。
---@param cityId string
local function PickCity(cityId)
    pickedCity_ = cityId
    cityChosen_ = true
    local city = ProfileService.CityFor(cityId)
    if not relationChosen_ and city then
        pickedRelation_ = city.defaultRelation
    end
    RefreshPreview()
    RefreshConfirmButton()
end

---@param relationId string
local function PickRelation(relationId)
    if IsRandomPick() then
        return
    end
    pickedRelation_ = relationId
    relationChosen_ = true
    RefreshPreview()
    RefreshConfirmButton()
end

local function PickRandom()
    if mode_ == "switch" then
        return
    end
    pickedCity_ = RANDOM_PICK
    pickedRelation_ = nil
    cityChosen_ = true
    relationChosen_ = false
    RefreshPreview()
    RefreshConfirmButton()
end

---@class ProfileChipSpec
---@field id string
---@field label string
---@field onPress fun():void

--- 一枚 chip = 一个 Button：focusable 属性与实例两处都写（AGENTS 硬边界），
--- 主操作落在 OnPointerDown，不等抬起命中同一控件（规则 ①）。
---@param spec ProfileChipSpec
---@return Widget
local function MakeChip(spec)
    local chip = UI.Button {
        text = spec.label,
        variant = "secondary",
        fontSize = 11,
        height = CHIP_HEIGHT,
        paddingLeft = 10,
        paddingRight = 10,
        backgroundColor = CHIP_STYLE.idle.bg,
        borderColor = CHIP_STYLE.idle.border,
        textColor = CHIP_STYLE.idle.text,
        focusable = false,
    }
    chip.focusable = false
    function chip:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
        self:SetState({ pressed = true })
        self:TransitionToStateBgColor()
        spec.onPress()
    end
    return chip
end

--- 构建并返回覆盖层子树；初始不可见，由 Show/Hide 控制
---@return Widget
function ProfileOverlay.Build()
    if root_ then
        return root_
    end

    ResetSelection()

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
        text = "要点两下：一枚城市 + 一枚关系起点",
        fontSize = 11,
        fontColor = COLORS.accent,
        height = PREVIEW_HEIGHT,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }
    hint_ = UI.Label {
        id = "profileHint",
        text = "她按当地时间生活，忙或在睡时消息排队",
        fontSize = 10,
        fontColor = COLORS.dim,
        height = HINT_HEIGHT,
        whiteSpace = "normal",
        wordBreak = "break-word",
    }

    cityChips_ = {}
    ---@type Widget[]
    local cityWidgets = {}
    for i = 1, #ProfileService.CITY_ORDER do
        local cityId = ProfileService.CITY_ORDER[i]
        local city = ProfileService.CityFor(cityId)
        if city then
            cityWidgets[#cityWidgets + 1] = MakeChip({
                id = cityId,
                label = city.label,
                onPress = function()
                    PickCity(cityId)
                end,
            })
            cityChips_[#cityChips_ + 1] = { id = cityId, widget = cityWidgets[#cityWidgets] }
        end
    end
    -- 随机入口只在初始化时给；换档案时目标明确，不再赌一次（Show 里按 mode 隐藏）
    local randomWidget = MakeChip({
        id = RANDOM_PICK,
        label = "随机",
        onPress = PickRandom,
    })
    randomChip_ = { id = RANDOM_PICK, widget = randomWidget }
    cityWidgets[#cityWidgets + 1] = randomWidget

    relationChips_ = {}
    ---@type Widget[]
    local relationWidgets = {}
    for i = 1, #ProfileService.RELATION_ORDER do
        local relationId = ProfileService.RELATION_ORDER[i]
        local relation = ProfileService.RelationFor(relationId)
        if relation then
            relationWidgets[#relationWidgets + 1] = MakeChip({
                id = relationId,
                label = relation.label,
                onPress = function()
                    PickRelation(relationId)
                end,
            })
            relationChips_[#relationChips_ + 1] = { id = relationId, widget = relationWidgets[#relationWidgets] }
        end
    end

    confirmButton_ = UI.Button {
        id = "profileConfirm",
        text = "就这么开始",
        variant = "primary",
        fontSize = 13,
        height = ACTION_HEIGHT,
        focusable = false,
        disabled = true,
    }
    confirmButton_.focusable = false
    function confirmButton_:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
        self:SetState({ pressed = true })
        self:TransitionToStateBgColor()
        -- 两轴不齐就什么都不写：不给任何默认值替用户做主
        if not CanConfirm() or not onConfirm_ or not pickedCity_ then
            logWarn("确认被挡住：城市与关系起点都要点一下")
            return
        end
        local isRandom = IsRandomPick()
        -- 随机模式下 pickedRelation_ 本就是 nil：两轴由这一次随机决定（main 的
        -- RandomPick 分支负责抽档）。2026-09-26 B-8 ④ 真机抓到旧写法在这里无条件
        -- 要求非空 relationId，随机点确认被自己挡死、静默无响应。
        local relationId = pickedRelation_
        if not relationId and not isRandom then
            logWarn("确认被挡住：关系起点为空")
            return
        end
        onConfirm_(pickedCity_, relationId, isRandom)
    end

    cancelButton_ = UI.Button {
        id = "profileCancel",
        text = "先不换",
        variant = "secondary",
        fontSize = 12,
        height = ACTION_HEIGHT,
        focusable = false,
        visible = false,
    }
    cancelButton_.focusable = false
    function cancelButton_:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
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
                        children = cityWidgets,
                    },
                    UI.Row {
                        flexWrap = "wrap",
                        gap = 6,
                        children = relationWidgets,
                    },
                    preview_,
                    hint_,
                    UI.Row {
                        gap = 8,
                        children = { confirmButton_, cancelButton_ },
                    },
                },
            },
        },
    }
    RefreshPreview()
    RefreshConfirmButton()
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
    ResetSelection()
    onConfirm_ = opts.onConfirm
    onCancel_ = opts.onCancel
    local isSwitch = opts.mode == "switch"
    mode_ = isSwitch and "switch" or "init"
    title_:SetText(isSwitch and "换一个档案再见她" or "选择你想遇见她的城市")
    if cancelButton_ then
        cancelButton_:SetVisible(isSwitch)
    end
    if randomChip_ then
        randomChip_.widget:SetVisible(not isSwitch)
    end
    RefreshPreview()
    RefreshConfirmButton()
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
    confirmButton_ = nil
    cancelButton_ = nil
    cityChips_ = {}
    relationChips_ = {}
    randomChip_ = nil
    visible_ = false
    onConfirm_ = nil
    onCancel_ = nil
    ResetSelection()
end

return ProfileOverlay
