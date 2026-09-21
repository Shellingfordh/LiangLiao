-- ============================================================================
-- ChatPanel.lua — M0-1 聊天前端（urhox-libs/UI，新 UI 系统）
-- 只负责画：消息流 / 状态文案 / 输入框 / 发送 / 跳过等待。
-- 数据与时序全部来自 main.lua 传入的 MessageService 状态，本模块不自己计时。
-- 消息行按 id 增量追加、打字气泡常驻切可见：Widget:ClearChildren 不会销毁子
-- 控件的 Yoga 节点，重建式刷新会在真机上漏节点。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ChatPanel = {}

local COLORS = {
    panelBg = { 20, 22, 27, 235 },
    userBubble = { 62, 74, 96, 255 },
    herBubble = { 40, 43, 50, 255 },
    userText = { 236, 238, 242, 255 },
    herText = { 214, 209, 200, 255 },
    systemText = { 150, 146, 140, 190 },
    dimText = { 150, 148, 144, 190 },
    accent = { 200, 162, 122, 255 },
}

local IDLE_HINT = "写下你想对她说的话，发送后她会隔一会儿才回。"
local TYPING_GLYPHS = { "。", "。。", "。。。" }
local TYPING_STEP_SECONDS = 0.45
local SCROLL_SETTLE_FRAMES = 3
local SCROLL_PAD = 10
local BUBBLE_PAD_X = 11
-- 气泡宽度按「最坏情况的状态文案」预留：状态是事后 SetText 换上去的，
-- 如果按创建那一刻的文案算宽度，消息从「已送达」变「已排队」时会溢出气泡边界。
local STATUS_WIDTH_RESERVE = "已送达 · 对方只有碎片时间，已排队 · 第 9 位"

-- 气泡宽度：ScrollView 内子树的百分比宽度在首轮测量时拿不到确定父宽，
-- "78%" 会塌成最小内容宽（预览实测：一行两个字）。所以由 main 传入屏幕逻辑宽，
-- 这里一律换成确定像素值；没传时退回百分比（桌面窗体下不影响功能）。
---@type number|nil
local rowW_ = nil
---@type number|nil
local bubbleOuterMaxW_ = nil
---@type number|nil
local bubbleTextMaxW_ = nil

---@type Widget|nil
local root_ = nil
---@type Widget|nil
local content_ = nil
---@type ScrollView|nil
local scroller_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Label|nil
local memoryLabel_ = nil
---@type TextField|nil
local inputField_ = nil
---@type Button|nil
local sendButton_ = nil
---@type Button|nil
local skipButton_ = nil
---@type Widget|nil
local typingRow_ = nil
---@type Label|nil
local typingLabel_ = nil

local devTools_ = false
local awaiting_ = false
local phase_ = "idle"
local statusText_ = ""
local renderedVersion_ = -1
local scrollAfterFrames_ = 0
---@type number
local typingTimer_ = 0
local typingFrame_ = 1
---@type table<integer, Widget>
local rowsById_ = {}
---@type table<integer, Label?>
local statusByMsgId_ = {}
---@type table<integer, string>
local renderedStatus_ = {}

---@type fun(text: string): nil
local onSend_ = function() end
---@type fun(): nil
local onSkip_ = function() end
---@type fun(text: string): nil
local onDraftChange_ = function() end
---@type fun(): MsgEntry[]
local messagesProvider_ = function()
    return {}
end
---@type fun(): integer
local versionProvider_ = function()
    return 0
end

local function logInfo(msg)
    print("[ChatPanel] " .. msg)
    log:Write(LOG_INFO, "[ChatPanel] " .. msg)
end

--- 估算文本宽度：中日韩按 1em、ASCII 按 0.55em。
--- 气泡宽度必须由这里算出来并钉成确定值：ScrollView 子树里引擎的文本测量
--- 不会把容器撑开，预览实测正文被同层角标挤成一行 4 个字。
---@param s string
---@param fontSize number
---@return number
local function estTextWidth(s, fontSize)
    ---@type number
    local w = 0
    local i = 1
    local n = #s
    while i <= n do
        local b = s:byte(i)
        local step = 1
        local adv = fontSize * 0.55
        if b >= 0xF0 then
            step = 4
        elseif b >= 0xE0 then
            step = 3
            adv = fontSize
        elseif b >= 0xC0 then
            step = 2
            adv = fontSize
        end
        w = w + adv
        i = i + step
    end
    return w
end

---@class ChatPanelOptions
---@field devTools? boolean 是否显示「跳过等待」（开发预览用）
---@field initialDraft? string 输入框默认内容
---@field minHeight? number 聊天区最小高度，防止短屏把输入框挤没
---@field outerWidth? number 聊天区可用逻辑宽度（屏幕逻辑宽 - 页面左右内边距），用于把气泡宽度定成确定值
---@field onSend? fun(text: string) 点击发送 / 回车
---@field onSkip? fun() 点击跳过等待
---@field onDraftChange? fun(text: string) 输入变化，回写草稿
---@field getMessages? fun(): MsgEntry[]
---@field getVersion? fun(): integer

---@param msg MsgEntry
---@return Widget
local function MakeBubbleRow(msg)
    local isUser = msg.role == "user"

    if msg.role == "system" then
        return UI.Panel {
            width = rowW_ or "100%",
            alignItems = "center",
            children = {
                UI.Label {
                    text = msg.text,
                    fontSize = 10,
                    fontColor = COLORS.systemText,
                    whiteSpace = "normal",
                    wordBreak = "break-word",
                    maxWidth = bubbleTextMaxW_,
                    textAlign = "center",
                },
            },
        }
    end

    local metaText = (msg.clockText or "") .. (isUser and " · 洛杉矶 · 你" or " · 若夕")
    local statusText = isUser and (msg.statusText or "") or ""
    local bodyW = estTextWidth(msg.text, 13)
    local metaW = estTextWidth(metaText, 9)
    -- 状态文案是事后换上去的，宽度必须当场预留，否则「已送达」变「已排队」时会撑出气泡
    local statusW = isUser and estTextWidth(STATUS_WIDTH_RESERVE, 10) or 0
    if bodyW < metaW then
        bodyW = metaW
    end
    if bodyW < statusW then
        bodyW = statusW
    end
    if bubbleTextMaxW_ and bodyW > bubbleTextMaxW_ then
        bodyW = bubbleTextMaxW_
    end
    local bubbleW = bodyW + BUBBLE_PAD_X * 2

    local statusLabel = isUser and (statusText ~= "") and UI.Label {
        id = "msgStatus" .. tostring(msg.id),
        text = statusText,
        width = bodyW,
        maxWidth = bubbleTextMaxW_,
        fontSize = 10,
        fontColor = COLORS.accent,
        whiteSpace = "normal",
        wordBreak = "break-word",
        marginTop = 2,
    } or nil

    if isUser then
        statusByMsgId_[msg.id] = statusLabel
    end

    local children = {
        UI.Label {
            text = msg.text,
            width = bodyW,
            maxWidth = bubbleTextMaxW_,
            fontSize = 13,
            fontColor = isUser and COLORS.userText or COLORS.herText,
            whiteSpace = "normal",
            wordBreak = "break-word",
            lineHeight = 1.35,
        },
        UI.Label {
            text = metaText,
            fontSize = 9,
            fontColor = COLORS.dimText,
            whiteSpace = "nowrap",
            marginTop = 3,
        },
    }
    if statusLabel then
        children[#children + 1] = statusLabel
    end

    return UI.Panel {
        width = rowW_ or "100%",
        flexDirection = "row",
        justifyContent = isUser and "flex-end" or "flex-start",
        children = {
            UI.Panel {
                width = bubbleW,
                maxWidth = bubbleOuterMaxW_ or "78%",
                backgroundColor = isUser and COLORS.userBubble or COLORS.herBubble,
                borderRadius = 12,
                paddingHorizontal = BUBBLE_PAD_X,
                paddingVertical = 8,
                children = children,
            },
        },
    }
end

--- 构建聊天区子树（消息流 + 状态行 + 输入区）
---@param opts? ChatPanelOptions
---@return Widget
function ChatPanel.Build(opts)
    opts = opts or {}
    devTools_ = opts.devTools == true
    onSend_ = opts.onSend or onSend_
    onSkip_ = opts.onSkip or onSkip_
    onDraftChange_ = opts.onDraftChange or onDraftChange_
    messagesProvider_ = opts.getMessages or messagesProvider_
    versionProvider_ = opts.getVersion or versionProvider_
    phase_ = "idle"
    awaiting_ = false
    renderedVersion_ = -1
    rowsById_ = {}
    statusByMsgId_ = {}
    renderedStatus_ = {}

    memoryLabel_ = UI.Label {
        id = "chatMemoryLine",
        text = "记忆读取中…",
        fontSize = 10,
        fontColor = COLORS.dimText,
        whiteSpace = "nowrap",
    }

    if opts.outerWidth and opts.outerWidth > 120 then
        local inner = opts.outerWidth - SCROLL_PAD * 2
        rowW_ = inner
        bubbleOuterMaxW_ = inner
        bubbleTextMaxW_ = inner - BUBBLE_PAD_X * 2
        logInfo(string.format("气泡宽度定为确定值：行 %.0f / 文本 %.0f（屏幕逻辑宽 %.0f）",
            inner, bubbleTextMaxW_, opts.outerWidth))
    end

    typingLabel_ = UI.Label {
        text = "若夕正在输入。",
        fontSize = 13,
        fontColor = COLORS.herText,
        whiteSpace = "nowrap",
    }

    typingRow_ = UI.Panel {
        width = rowW_ or "100%",
        flexDirection = "row",
        justifyContent = "flex-start",
        visible = false,
        children = {
            UI.Panel {
                backgroundColor = COLORS.herBubble,
                borderRadius = 12,
                paddingHorizontal = BUBBLE_PAD_X,
                paddingVertical = 8,
                children = { typingLabel_ },
            },
        },
    }

    content_ = UI.Panel {
        id = "chatMessages",
        width = rowW_ or "100%",
        flexDirection = "column",
        gap = 8,
        children = { typingRow_ },
    }

    scroller_ = UI.ScrollView {
        id = "chatScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        bounces = true,
        showScrollbar = true,
        backgroundColor = COLORS.panelBg,
        borderRadius = 12,
        padding = SCROLL_PAD,
        children = { content_ },
    }

    statusLabel_ = UI.Label {
        id = "chatStatusLine",
        text = IDLE_HINT,
        fontSize = 11,
        fontColor = COLORS.accent,
        whiteSpace = "normal",
        flexGrow = 1,
        flexBasis = 0,
    }

    skipButton_ = UI.Button {
        id = "chatSkip",
        text = "跳过等待",
        variant = "secondary",
        fontSize = 11,
        height = 28,
        paddingLeft = 10,
        paddingRight = 10,
        visible = devTools_,
        disabled = true,
        onClick = function()
            if awaiting_ then
                onSkip_()
            else
                logInfo("跳过按钮点击时没有待回复消息")
            end
        end,
    }

    inputField_ = UI.TextField {
        id = "chatInput",
        value = opts.initialDraft or "",
        placeholder = "说点什么…",
        fontSize = 13,
        maxLength = 120,
        height = 42,
        flexGrow = 1,
        flexBasis = 0,
        onChange = function(_, value)
            onDraftChange_(value or "")
        end,
        onSubmit = function(_, value)
            onSend_(value or "")
        end,
    }

    sendButton_ = UI.Button {
        id = "chatSend",
        text = "发送",
        variant = "primary",
        fontSize = 13,
        width = 72,
        height = 42,
        onClick = function()
            onSend_(ChatPanel.GetDraft())
        end,
    }

    root_ = UI.Panel {
        id = "chatPanel",
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        minHeight = opts.minHeight or 190,
        flexDirection = "column",
        gap = 8,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                id = "chatHeader",
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "陌生网友 · 洛杉矶",
                        fontSize = 11,
                        fontColor = COLORS.dimText,
                        whiteSpace = "nowrap",
                    },
                    memoryLabel_,
                },
            },
            scroller_,
            UI.Panel {
                id = "chatStatusBar",
                width = "100%",
                flexShrink = 0,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = { statusLabel_, skipButton_ },
            },
            UI.Panel {
                id = "chatInputBar",
                width = "100%",
                flexShrink = 0,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = { inputField_, sendButton_ },
            },
        },
    }

    logInfo(string.format("聊天区已构建 devTools=%s 草稿 %d 字",
        tostring(devTools_), #(opts.initialDraft or "")))

    -- 按钮不能抢焦点：点了「发送」会先让 TextField 失焦 → 软键盘收起 → 画布高度变化 →
    -- 整棵布局位移，而引擎的 Click 要求「按下与抬起命中同一个控件」（UI.lua:2379），
    -- 于是手机上点发送永远不触发（回车走 onSubmit 反而正常）。EditMenu 用的是同一个开关。
    sendButton_.focusable = false
    skipButton_.focusable = false

    return root_
end

--- 追加尚未上屏的消息行
local function AppendNewRows()
    if not content_ then
        return
    end
    local msgs = messagesProvider_()
    local added = 0
    for i = 1, #msgs do
        local msg = msgs[i]
        if not rowsById_[msg.id] then
            local row = MakeBubbleRow(msg)
            rowsById_[msg.id] = row
            -- 打字气泡必须始终在最下方，所以新行插在它之前
            if typingRow_ then
                content_:InsertChild(row, #content_.children)
            else
                content_:AddChild(row)
            end
            added = added + 1
        end
    end
    if added > 0 then
        scrollAfterFrames_ = SCROLL_SETTLE_FRAMES
        logInfo(string.format("追加 %d 条消息行，累计 %d 条", added, #msgs))
    end
end

--- 刷新已上屏消息的送达状态（行不重建，只换状态那一行文字）
local function RefreshStatuses()
    local msgs = messagesProvider_()
    for i = 1, #msgs do
        local msg = msgs[i]
        if msg.role == "user" then
            local label = statusByMsgId_[msg.id]
            local text = msg.statusText or ""
            if label and renderedStatus_[msg.id] ~= text then
                renderedStatus_[msg.id] = text
                label:SetText(text)
            end
        end
    end
end

--- 每帧调用：合并同一帧内的多次变更
---@param dt number
function ChatPanel.Tick(dt)
    if not root_ then
        return
    end

    local version = versionProvider_()
    if version ~= renderedVersion_ then
        renderedVersion_ = version
        AppendNewRows()
        RefreshStatuses()
    end

    if phase_ == "typing" then
        typingTimer_ = typingTimer_ + dt
        if typingTimer_ >= TYPING_STEP_SECONDS then
            typingTimer_ = 0
            typingFrame_ = typingFrame_ + 1
            if typingLabel_ then
                typingLabel_:SetText("若夕正在输入"
                    .. TYPING_GLYPHS[(typingFrame_ % #TYPING_GLYPHS) + 1])
            end
        end
    end

    if scrollAfterFrames_ > 0 then
        scrollAfterFrames_ = scrollAfterFrames_ - 1
        if scrollAfterFrames_ == 0 and scroller_ then
            scroller_:ScrollToBottom()
        end
    end
end

--- 相位与状态文案由 main 驱动；主循环每帧都会推，所以这里自己挡掉没变化的帧
---@param phase string
---@param statusText string
---@param awaiting boolean
function ChatPanel.SetPhase(phase, statusText, awaiting)
    if phase_ == phase and statusText_ == statusText and awaiting_ == awaiting then
        return
    end
    phase_ = phase
    statusText_ = statusText
    awaiting_ = awaiting

    if statusLabel_ then
        statusLabel_:SetText(awaiting and statusText or IDLE_HINT)
    end
    if typingRow_ then
        typingRow_:SetVisible(phase == "typing")
    end
    if sendButton_ then
        -- M1 起等待期间仍然可以再发：后发的会排在队首之后（队列不越序），所以按钮不禁用。
        -- 「她在忙/在睡」由状态条与气泡上的排队文案说明，不靠禁用按钮来表达。
        sendButton_:SetDisabled(false)
        sendButton_:SetText(awaiting and "继续发送" or "发送")
    end
    if skipButton_ then
        skipButton_:SetDisabled(not awaiting)
    end
    if phase == "typing" then
        typingTimer_ = 0
    end
end

---@param line string
function ChatPanel.SetMemoryLine(line)
    if memoryLabel_ then
        memoryLabel_:SetText(line)
    end
end

---@return string
function ChatPanel.GetDraft()
    if inputField_ then
        return inputField_:GetValue() or ""
    end
    return ""
end

---@param text string
function ChatPanel.SetDraft(text)
    if inputField_ then
        inputField_:SetValue(text or "")
    end
end

--- 发送成功后清空输入框（草稿已由 MessageService 接管）
function ChatPanel.ClearDraft()
    if inputField_ then
        inputField_:Clear()
    end
end

---@return Widget|nil
function ChatPanel.GetRoot()
    return root_
end

function ChatPanel.Shutdown()
    root_ = nil
    content_ = nil
    scroller_ = nil
    statusLabel_ = nil
    memoryLabel_ = nil
    inputField_ = nil
    sendButton_ = nil
    skipButton_ = nil
    typingRow_ = nil
    typingLabel_ = nil
    rowsById_ = {}
    statusByMsgId_ = {}
    renderedStatus_ = {}
    renderedVersion_ = -1
end

return ChatPanel
