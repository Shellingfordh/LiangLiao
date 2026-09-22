-- ============================================================================
-- DevTestPanel.lua — 仅开发模式可见的 M1 时间状态测试台。
-- 只发出“切换本次运行的测试时间 / 推进队首”意图；不接触系统时间或玩家存档。
-- ============================================================================

local UI = require("urhox-libs/UI")

local DevTestPanel = {}

---@type Label|nil
local summaryLabel_ = nil
---@type Widget[]
local controls_ = {}

local function makeButton(text, onClick)
    local button = UI.Button {
        text = text,
        variant = "secondary",
        fontSize = 10,
        height = 26,
        paddingLeft = 7,
        paddingRight = 7,
        onClick = onClick,
    }
    controls_[#controls_ + 1] = button
    return button
end

---@param opts {onPreset: fun(hour: integer, label: string), onReset: fun(), onAdvance: fun()}
---@return Widget
function DevTestPanel.Build(opts)
    controls_ = {}
    summaryLabel_ = UI.Label {
        text = "测试时间：真实时间",
        fontSize = 10,
        fontColor = { 216, 210, 198, 240 },
        whiteSpace = "nowrap",
    }

    local panel = UI.Panel {
        id = "m1DevTestPanel",
        position = "absolute",
        top = 8,
        left = 8,
        width = "auto",
        maxWidth = "94%",
        padding = 7,
        gap = 5,
        borderRadius = 9,
        backgroundColor = { 17, 20, 27, 235 },
        borderWidth = 1,
        borderColor = { 126, 172, 223, 190 },
        flexDirection = "column",
        pointerEvents = "auto",
        children = {
            UI.Row {
                gap = 6,
                alignItems = "center",
                children = {
                    UI.Label { text = "M1 测试", fontSize = 11, fontWeight = "bold", fontColor = { 150, 207, 255, 255 } },
                    summaryLabel_,
                },
            },
            UI.Row {
                gap = 4,
                flexWrap = "wrap",
                children = {
                    makeButton("睡眠 01:30", function() opts.onPreset(1, "睡眠 01:30") end),
                    makeButton("忙碌 14:30", function() opts.onPreset(14, "忙碌 14:30") end),
                    makeButton("碎片 12:30", function() opts.onPreset(12, "碎片 12:30") end),
                    makeButton("空闲 19:45", function() opts.onPreset(19, "空闲 19:45") end),
                },
            },
            UI.Row {
                gap = 4,
                children = {
                    makeButton("推进到可回复", opts.onAdvance),
                    makeButton("恢复真实时间", opts.onReset),
                },
            },
        },
    }
    for i = 1, #controls_ do
        controls_[i].focusable = false
    end
    return panel
end

---@param text string
function DevTestPanel.SetSummary(text)
    if summaryLabel_ then
        summaryLabel_:SetText(text)
    end
end

function DevTestPanel.Shutdown()
    summaryLabel_ = nil
    controls_ = {}
end

return DevTestPanel
