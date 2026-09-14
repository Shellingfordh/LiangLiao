-- ui/bubble.lua
-- 头顶气泡：显示角色当前状态/想法
--
-- Maker 内置 UI 主题提供 SpeechBubble 组件（见 ttm-ui-themes.md）。
-- 这里给一个具体的样式参数 + 行为。

local M = {}

-- 当前活跃气泡
local _active = {}  -- { xiaoman = bubble_node, ... }

local DEFAULT_DURATION = 4.0  -- 秒

-- 显示气泡
-- @param role_id string
-- @param event dict  { title, body, emotion, priority, duration_sec }
function M.show(role_id, event)
    -- 同一角色已有气泡：先关闭
    if _active[role_id] then
        M.hide(role_id)
    end

    -- 调 Maker UI 主题的 SpeechBubble（具体 API 以连接到 Maker 的实际组件为准）
    local bubble = ui.CreateNode("SpeechBubble", {
        anchor = role_id,
        title  = event.title or "",
        body   = event.body or "",
        emotion = event.emotion or "neutral",
        priority = event.priority or "normal",
        duration = event.duration_sec or DEFAULT_DURATION,
        on_finished = function()
            _active[role_id] = nil
        end,
    })

    if bubble then
        _active[role_id] = bubble
    end
end

function M.hide(role_id)
    local b = _active[role_id]
    if b then
        b:Destroy()
        _active[role_id] = nil
    end
end

function M.hide_all()
    for id, _ in pairs(_active) do
        M.hide(id)
    end
end

return M