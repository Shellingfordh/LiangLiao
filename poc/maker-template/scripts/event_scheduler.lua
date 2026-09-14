-- event_scheduler.lua
-- 事件调度器：去重 + 优先级 + 触发
--
-- 触发来源：
--   1. time_sync 反推的离线事件（进入时一次性灌入）
--   2. 玩家走近角色（5 米内）→ "打招呼"
--   3. 玩家点击角色 → "对话入口"
--   4. 实时事件（如下雨 / 节气）→ 全员
--
-- 调度策略：
--   - 同 type 在 1 小时内不重复显示
--   - 同一时刻只有一个"高优先级"气泡（避免遮挡）
--   - 长内容（生日、长信）走日记面板，不弹气泡

local Bubble = require("scripts.ui.bubble")

local M = {}

-- 内存中的"已显示去重表"，key = role_id + ":" + type
local _shown = {}  -- { ["xiaoman:miss_you"] = os.time() }

local DEDUP_WINDOW_SEC = 3600

-- 检查 + 标记
local function should_show(role_id, event_type)
    local key = role_id .. ":" .. event_type
    local last = _shown[key] or 0
    if os.time() - last < DEDUP_WINDOW_SEC then
        return false
    end
    _shown[key] = os.time()
    return true
end

-- 气泡显示入口
-- @param role_id string
-- @param event dict  { type, title, body, emotion, priority }
function M.show_bubble(role_id, event)
    if not should_show(role_id, event.type) then
        return
    end
    Bubble.show(role_id, event)
end

-- 玩家走近（每帧 / 间隔检测）
-- 在 main.lua 或 UI 钩子里调用：scheduler.on_player_near("xiaoman")
function M.on_player_near(role_id)
    local ev = {
        type = "greeting",
        ts = os.time(),
        title = "打招呼",
        body = "嘿，你来啦。",
        emotion = "happy",
        source = "proximity",
    }
    M.show_bubble(role_id, ev)
end

-- 玩家点击角色 → 打开对话
function M.on_player_tap(role_id)
    -- 通知 Maker AI 进入对话模式
    ai.OpenConversation(role_id, {
        system_prompt_file = "prompts/" .. role_id .. ".system.md",
        memory_events = require("scripts.memory_io").get_events(role_id, 5),
        memory_diary  = require("scripts.memory_io").get_diary(role_id),
    })
end

-- 实时事件触发（天气 / 节气）
-- @param event dict { type = "weather_rain", affects = "all", title, body, emotion }
function M.broadcast(event)
    if event.affects == "all" then
        for _, role_id in ipairs({"xiaoman", "aize", "grandma"}) do
            M.show_bubble(role_id, event)
        end
    elseif type(event.affects) == "table" then
        for _, role_id in ipairs(event.affects) do
            M.show_bubble(role_id, event)
        end
    end
end

return M