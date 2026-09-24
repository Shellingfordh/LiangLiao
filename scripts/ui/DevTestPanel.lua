-- ============================================================================
-- DevTestPanel.lua — 仅开发模式可见的 M1 时间状态测试台。
-- 只发出“切换本次运行的测试时间 / 推进队首”意图；不接触系统时间或玩家存档。
-- ============================================================================

local UI = require("urhox-libs/UI")

local DevTestPanel = {}

---@type Label|nil
local summaryLabel_ = nil
---@type Label|nil
local detailLabel_ = nil
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

---@param opts {onPreset: fun(hour: integer, label: string, minute: integer|nil), onReset: fun(), onAdvance: fun(), onCity: fun(cityId: string, label: string)}
---@return Widget
function DevTestPanel.Build(opts)
    controls_ = {}
    summaryLabel_ = UI.Label {
        text = "测试时间：真实时间",
        fontSize = 10,
        fontColor = { 216, 210, 198, 240 },
        whiteSpace = "nowrap",
    }
    -- 第二行单独放证据字段：那两行都 nowrap，挤成一行会在窄屏上被裁掉半截
    detailLabel_ = UI.Label {
        text = "等待切换",
        fontSize = 10,
        fontColor = { 150, 207, 255, 220 },
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
                gap = 6,
                children = { detailLabel_ },
            },
            UI.Row {
                gap = 4,
                flexWrap = "wrap",
                children = {
                    makeButton("睡眠 01:30", function() opts.onPreset(1, "睡眠 01:30", 30) end),
                    makeButton("忙碌 14:30", function() opts.onPreset(14, "忙碌 14:30", 30) end),
                    makeButton("碎片 12:30", function() opts.onPreset(12, "碎片 12:30", 30) end),
                    makeButton("空闲 19:45", function() opts.onPreset(19, "空闲 19:45", 45) end),
                },
            },
            UI.Row {
                gap = 4,
                children = {
                    makeButton("推进到可回复", opts.onAdvance),
                    makeButton("恢复真实时间", opts.onReset),
                },
            },
            UI.Row {
                gap = 4,
                flexWrap = "wrap",
                children = {
                    makeButton("上海", function() opts.onCity("shanghai", "上海") end),
                    makeButton("成都", function() opts.onCity("chengdu", "成都") end),
                    makeButton("洛杉矶", function() opts.onCity("los_angeles", "洛杉矶") end),
                    makeButton("伦敦", function() opts.onCity("london", "伦敦") end),
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

---@param text string
function DevTestPanel.SetDetail(text)
    if detailLabel_ then
        detailLabel_:SetText(text)
    end
end

function DevTestPanel.Shutdown()
    summaryLabel_ = nil
    detailLabel_ = nil
    controls_ = {}
end

return DevTestPanel
