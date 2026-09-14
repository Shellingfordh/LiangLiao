-- role/grandma.lua
-- 奶奶（镇郊菜园）—— 慈祥老奶奶，慢节奏爱操心
--
-- 触发事件清单：
--   - 节气提醒（春分/夏至/秋分/冬至/立冬...）
--   - 玩家上次说喜欢的菜熟了
--   - 阴历生日（角色本身的 10/1）
--   - 超过 1 小时没来 → "在想你"（main.lua 统一触发）

local MemoryIO = require("scripts.memory_io")

local M = {}

M.id = "grandma"
M.display_name = "奶奶"
M.home = "镇郊菜园"

-- 节气表（公历近似日期，每年浮动 ±1 天）
local SOLAR_TERMS = {
    {3, 20, "春分", "记得加衣，别贪凉。"},
    {6, 21, "夏至", "今天白天最长，记得防晒。"},
    {9, 22, "秋分", "风起了，出门披件外套。"},
    {12, 21, "冬至", "今天要吃饺子。"},
    {11, 7,  "立冬", "再过三天立冬了，记得添衣。"},
}

local function today_solar_term()
    local t = os.date("*t")
    for _, st in ipairs(SOLAR_TERMS) do
        if t.month == st[1] and math.abs(t.day - st[2]) <= 1 then
            return st[3], st[4]
        end
    end
    return nil
end

function M.tick(game_time_hour)
    local now = os.time()

    -- 早上 6 点：检查今天是不是节气
    if game_time_hour == 6 then
        local term_name, term_msg = today_solar_term()
        if term_name then
            local ev = {
                type = "solar_term",
                ts = now,
                title = term_name,
                body = term_msg,
                emotion = "caring",
                priority = "high",
                source = "calendar",
            }
            MemoryIO.append_event(M.id, ev)
            require("scripts.event_scheduler").show_bubble(M.id, ev)
        end
    end

    -- 早上 8 点：检查玩家喜欢的菜是否熟了（从 cloud 读取 grandma_favorite_veg）
    local fav = MemoryIO.get("grandma_favorite_veg", "")
    if fav ~= "" and game_time_hour == 8 then
        local ev = {
            type = "veg_ready",
            ts = now,
            title = "菜熟了",
            body = string.format("上次你说你喜欢 %s，今天正好熟了。来拿点？", fav),
            emotion = "warm",
            priority = "high",
            source = "scheduled",
        }
        MemoryIO.append_event(M.id, ev)
        require("scripts.event_scheduler").show_bubble(M.id, ev)
    end
end

-- 玩家第一次来时调用，记住他喜欢的菜
function M.on_player_say_like(veg_name)
    MemoryIO.set("grandma_favorite_veg", veg_name)
end

return M