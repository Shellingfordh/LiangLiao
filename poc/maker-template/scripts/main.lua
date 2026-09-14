-- main.lua
-- 入口：玩家进入小镇时调用
--
-- 调用时机：在 Maker AI 对话里告诉 Agent "玩家进入主场景后调用 main.lua"
-- 或在 UI 主题的事件 onShow / onSceneEnter 钩子里调用。
--
-- 职责：
--   1. 读取上次访问时间戳（clientCloud）
--   2. 计算时间差 → 触发离线累积事件
--   3. 加载 3 个角色的人设 + 历史事件
--   4. 把状态写到 clientCloud 供下一次进入使用

local TimeSync   = require("scripts.time_sync")
local MemoryIO   = require("scripts.memory_io")
local EventSched = require("scripts.event_scheduler")
local Xiaoman    = require("scripts.role.xiaoman")
local Aize       = require("scripts.role.aize")
local Grandma    = require("scripts.role.grandma")

local ROLES = {
    {id = "xiaoman", display = "小满", home = "面包店", script = Xiaoman},
    {id = "aize",    display = "阿泽", home = "图书馆", script = Aize},
    {id = "grandma", display = "奶奶", home = "镇郊菜园", script = Grandma},
}

local function main()
    -- 1. 读上次访问时间
    local now = os.time()
    local last_visit = MemoryIO.get_int("last_visit_ts")
    if last_visit == 0 then
        last_visit = now  -- 首次进入
    end
    local elapsed_sec = now - last_visit
    log(string.format("[main] now=%d  last=%d  elapsed=%ds (%.1fh)",
        now, last_visit, elapsed_sec, elapsed_sec / 3600))

    -- 2. 反推离线事件（按角色并行）
    for _, role in ipairs(ROLES) do
        local offline_events = TimeSync.estimate_offline_events(role.id, last_visit, now)
        for _, ev in ipairs(offline_events) do
            MemoryIO.append_event(role.id, ev)
            log(string.format("[main] offline event for %s: %s — %s",
                role.id, ev.type, ev.title or ""))
        end
    end

    -- 3. 写入"本次访问起点"
    MemoryIO.set_int("last_visit_ts", now)
    MemoryIO.set_int("visit_count", MemoryIO.get_int("visit_count") + 1)

    -- 4. 立即触发"想念"事件（如果时间差 ≥ 1 小时）
    if elapsed_sec >= 3600 then
        for _, role in ipairs(ROLES) do
            local miss_event = {
                type = "miss_you",
                ts = now,
                title = "在想你",
                body = string.format("已经 %d 小时没见你了。", math.floor(elapsed_sec / 3600)),
                emotion = "longing",
                source = "time_gap",
            }
            MemoryIO.append_event(role.id, miss_event)
            EventSched.show_bubble(role.id, miss_event)
        end
    end

    log("[main] 初始化完成")
end

main()