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

    return UI.Panel {
        width = rowW_ or "100%",
        flexDirection = "row",
        justifyContent = isUser and "flex-end" or "flex-start",
        children = {
            UI.Panel {
                maxWidth = bubbleOuterMaxW_ or "78%",
                backgroundColor = isUser and COLORS.userBubble or COLORS.herBubble,
                borderRadius = 12,
                paddingHorizontal = BUBBLE_PAD_X,
                paddingVertical = 8,
                children = {
                    UI.Label {
                        text = msg.text,
                        fontSize = 13,
                        fontColor = isUser and COLORS.userText or COLORS.herText,
                        whiteSpace = "normal",
                        wordBreak = "break-word",
                        maxWidth = bubbleTextMaxW_,
                        lineHeight = 1.35,
                    },
                    UI.Label {
                        text = (msg.clockText or "") .. (isUser and " · 洛杉矶 · 你" or " · 若夕"),
                        fontSize = 9,
                        fontColor = COLORS.dimText,
                        whiteSpace = "nowrap",
                        marginTop = 3,
                    },
                },
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

--- 相位与状态文案由 main 驱动
---@param phase string
---@param statusText string
---@param awaiting boolean
function ChatPanel.SetPhase(phase, statusText, awaiting)
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
        sendButton_:SetDisabled(awaiting)
        sendButton_:SetText(awaiting and "等待中" or "发送")
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
    renderedVersion_ = -1
end

return ChatPanel
