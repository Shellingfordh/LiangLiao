-- memory_io.lua
-- 客户端存档读写封装 —— 跟随登录用户的 cloud data
--
-- 数据归属原则（见 docs/integration.md §2.4）：
--   - 玩家进度 / 日记 / 好感度 → clientCloud（单人 PoC，不上 server）
--   - 关键 key 命名空间：stl_<role_id>_<field>（stl = santianliang 项目缩写）
--
-- Maker 文档提示：
--   - clientCloud 只在 Standalone / Client 模式可用
--   - 写入是异步，必须处理成功/失败/超时回调
--   - 浏览器预览不持久化，实机测试/线上才会留下

local M = {}

local PREFIX = "stl_"

-- ----- 事件日志（每个角色一份）-------------------------------------------

local function event_key(role_id) return PREFIX .. role_id .. "_events" end

function M.append_event(role_id, event)
    local key = event_key(role_id)
    local current_json = clientCloud.Get(key) or "[]"
    local ok, current = pcall(json.decode, current_json)
    if not ok or type(current) ~= "table" then
        current = {}
    end
    -- 去重：同 (type, ts, source) 只保留一条
    local exists = false
    for _, e in ipairs(current) do
        if e.type == event.type and e.ts == event.ts and e.source == event.source then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(current, event)
        -- 单角色事件最多保留 100 条（FIFO）
        while #current > 100 do
            table.remove(current, 1)
        end
        clientCloud.Set(key, json.encode(current), function(success)
            if not success then
                log(string.format("[memory_io] ✗ 写入 %s 失败", key))
            end
        end)
    end
end

function M.get_events(role_id, limit)
    local key = event_key(role_id)
    local raw = clientCloud.Get(key) or "[]"
    local ok, list = pcall(json.decode, raw)
    if not ok then return {} end
    -- 最近的在前
    local out = {}
    local n = #list
    local cap = limit or n
    for i = n, math.max(1, n - cap + 1), -1 do
        table.insert(out, list[i])
    end
    return out
end

-- ----- 日记（玩家可翻看）------------------------------------------------

local function diary_key(role_id) return PREFIX .. role_id .. "_diary" end

function M.append_diary(role_id, entry)
    -- entry: { date = "2026-09-10", body = "..." }
    local key = diary_key(role_id)
    local raw = clientCloud.Get(key) or "[]"
    local ok, list = pcall(json.decode, raw)
    if not ok then list = {} end
    -- 同一天只保留一条
    for i, e in ipairs(list) do
        if e.date == entry.date then
            list[i] = entry
            clientCloud.Set(key, json.encode(list))
            return
        end
    end
    table.insert(list, entry)
    -- 单角色日记最多保留 30 天
    while #list > 30 do table.remove(list, 1) end
    clientCloud.Set(key, json.encode(list))
end

function M.get_diary(role_id)
    local key = diary_key(role_id)
    local raw = clientCloud.Get(key) or "[]"
    local ok, list = pcall(json.decode, raw)
    if not ok then return {} end
    return list
end

-- ----- 全局字段（int） --------------------------------------------------

function M.set_int(name, value)
    clientCloud.SetInt(PREFIX .. name, value)
end

function M.get_int(name, default)
    local v = clientCloud.GetInt(PREFIX .. name)
    if v == 0 and default then return default end
    return v
end

-- ----- 全局字段（string / table） ---------------------------------------

function M.set(name, value)
    clientCloud.Set(PREFIX .. name, value)
end

function M.get(name, default)
    local v = clientCloud.Get(PREFIX .. name)
    if not v and default then return default end
    return v
end

-- ----- 调试：导出所有 key 的快照 ---------------------------------------

function M.debug_snapshot()
    local out = {}
    for _, name in ipairs({"last_visit_ts", "visit_count"}) do
        out[name] = M.get_int(name)
    end
    return json.encode(out)
end

return M