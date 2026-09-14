-- time_sync.lua
-- 平行时间线：现实时间差 → 离线事件反推
--
-- 关键设计：因为 Maker 引擎不能后台跑 NPC 逻辑（UrhoX + WASM），
-- 我们在玩家每次进入的瞬间，根据"上次访问时间戳 → 现在"的差，
-- 反推出这段时间里"合理会发生"的事件，按规则去重后写到日志。
--
-- 反推规则（保持简单可信）：
--   每小时 → 1 条 "background"（日常/想念）
--   每 6 小时 → 1 条 "habit"（角色习惯性动作）
--   每 24 小时 → 1 条 "weather"（天气相关，如果当前日期属于雨季）
--   每 168 小时（7天） → 1 条 "long_term"（周记）
--   生日（公历）→ 1 条 "birthday"
--
-- 反推出来的事件内容由 Maker AI 在玩家点击"日记"标签时按人设生成。

local MemoryIO = require("scripts.memory_io")

local M = {}

-- 每天 24 小时分成 4 个时段（用于选不同的人设动作）
local function time_of_day(ts)
    local h = (ts % 86400) / 3600  -- 简化：用 ts 自带的小时数（基于 1970 起点也行）
    -- 如果需要本地时间，用 os.date("*t", ts)
    local t = os.date("*t", ts)
    h = t.hour
    if h < 6  then return "deep_night" end
    if h < 11 then return "morning"   end
    if h < 14 then return "noon"      end
    if h < 18 then return "afternoon" end
    if h < 22 then return "evening"   end
    return "night"
end

-- 简单的"雨季"判断（4-9 月华东）
local function is_rainy_season(ts)
    local t = os.date("*t", ts)
    return t.month >= 4 and t.month <= 9
end

-- 检查 ts 这一天是否是角色生日（按月-日）
local function is_birthday(role_id, ts)
    local birthdays = {
        xiaoman = {6, 12},  -- 6 月 12 日
        aize    = {3, 21},  -- 3 月 21 日
        grandma = {10, 1},  -- 10 月 1 日
    }
    local b = birthdays[role_id]
    if not b then return false end
    local t = os.date("*t", ts)
    return t.month == b[1] and t.day == b[2]
end

-- 反推离线事件
-- @param role_id string
-- @param last_visit int  上次访问的 unix timestamp
-- @param now int         当前 unix timestamp
-- @return list of event dict
function M.estimate_offline_events(role_id, last_visit, now)
    if last_visit == 0 or last_visit >= now then
        return {}
    end
    local elapsed_sec = now - last_visit
    local elapsed_hours = math.floor(elapsed_sec / 3600)

    -- 最多反推 7 天的事件，再多会失真
    local cap_hours = math.min(elapsed_hours, 168)
    if cap_hours <= 0 then return {} end

    local events = {}

    -- 每小时 1 条 background（上限 7 条，避免日志爆炸）
    local n_bg = math.min(cap_hours, 7)
    for i = 1, n_bg do
        -- 把生成时刻均匀分布在 [last_visit, now] 之间
        local ev_ts = last_visit + math.floor((i / (n_bg + 1)) * elapsed_sec)
        table.insert(events, {
            type = "background",
            ts = ev_ts,
            title = "日常",
            time_of_day = time_of_day(ev_ts),
            source = "offline_inferred",
        })
    end

    -- 每 6 小时 1 条 habit
    local n_habit = math.floor(cap_hours / 6)
    for i = 1, n_habit do
        local ev_ts = last_visit + math.floor(((i * 6) / cap_hours) * elapsed_sec)
        table.insert(events, {
            type = "habit",
            ts = ev_ts,
            title = "习惯",
            role_specific = true,
            source = "offline_inferred",
        })
    end

    -- 雨季每 24 小时 1 条 weather
    if is_rainy_season(now) then
        local n_weather = math.floor(cap_hours / 24)
        for i = 1, n_weather do
            local ev_ts = last_visit + math.floor(((i * 24) / cap_hours) * elapsed_sec)
            table.insert(events, {
                type = "weather",
                ts = ev_ts,
                title = "下雨",
                weather = "rain",
                source = "offline_inferred",
            })
        end
    end

    -- 生日事件：检查整段时间内是否跨过角色生日
    if is_birthday(role_id, now) or is_birthday(role_id, last_visit) then
        local bday_ts = now  -- 简化：取 now 标记
        -- 找到 midnight of birthday
        local t = os.date("*t", bday_ts)
        local bday_midnight = os.time({year = t.year, month = t.month, day = t.day, hour = 0})
        if bday_midnight >= last_visit and bday_midnight <= now then
            table.insert(events, {
                type = "birthday",
                ts = bday_midnight,
                title = "生日",
                priority = "high",
                source = "offline_inferred",
            })
        end
    end

    -- 按时间戳排序
    table.sort(events, function(a, b) return a.ts < b.ts end)

    return events
end

-- 工具：格式化为可读时间
function M.fmt_ts(ts)
    return os.date("%m-%d %H:%M", ts)
end

return M