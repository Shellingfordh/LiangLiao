-- role/xiaoman.lua
-- 小满（面包店）—— 暖系少女，嘴硬心软
--
-- 触发事件清单：
--   - 游戏内时间到 7:00 → "面包出炉"
--   - 玩家喜欢的口味（从 clientCloud 读取）今天出炉 → "为你留了一份"
--   - 下雨天 → "闭店不开窗"
--   - 玩家超过 1 小时没来 → "在想你"（统一在 main.lua 触发）

local MemoryIO = require("scripts.memory_io")

local M = {}

-- 角色人设常量
M.id = "xiaoman"
M.display_name = "小满"
M.home = "面包店"

-- 小满的专属事件触发器（在主循环 / 定时器里调用）
-- @param game_time_hour int  游戏内小时（0~23）
function M.tick(game_time_hour)
    local now = os.time()

    -- 早上 7 点：面包出炉
    if game_time_hour == 7 then
        local ev = {
            type = "bread_ready",
            ts = now,
            title = "面包出炉",
            body = "今天的盐可颂刚出炉，香得整个店都是味道。",
            emotion = "happy",
            source = "scheduled",
        }
        MemoryIO.append_event(M.id, ev)
        require("scripts.event_scheduler").show_bubble(M.id, ev)
    end

    -- 玩家上次点单的口味今天出炉（从 cloud 读取 favorite_flavor）
    local fav = MemoryIO.get("xiaoman_favorite_flavor", "")
    if fav ~= "" and game_time_hour == 8 then
        local ev = {
            type = "favorite_ready",
            ts = now,
            title = "为你留了一份",
            body = string.format("记得你喜欢 %s，正好刚出炉一份。", fav),
            emotion = "warm",
            priority = "high",
            source = "scheduled",
        }
        MemoryIO.append_event(M.id, ev)
        require("scripts.event_scheduler").show_bubble(M.id, ev)
    end
end

-- 下雨天（外部天气模块调用）
function M.on_rainy()
    local ev = {
        type = "closed_for_rain",
        ts = os.time(),
        title = "闭店了",
        body = "下雨天，今天不开窗。想你就在家暖暖地等着吧。",
        emotion = "tender",
        source = "weather",
    }
    MemoryIO.append_event(M.id, ev)
    require("scripts.event_scheduler").show_bubble(M.id, ev)
end

return M