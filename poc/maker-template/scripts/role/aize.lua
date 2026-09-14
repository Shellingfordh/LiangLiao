-- role/aize.lua
-- 阿泽（图书馆）—— 清澈少年，博学偶尔毒舌
--
-- 触发事件清单：
--   - 阴天 → "不开窗"（光线太弱不适合看书）
--   - 玩家借的书超过 3 天没还 → "该还书了"（来自 cloud 借阅记录）
--   - 新书到了（模拟）→ "想给你看这本"
--   - 超过 1 小时没来 → "在想你"（main.lua 统一触发）

local MemoryIO = require("scripts.memory_io")

local M = {}

M.id = "aize"
M.display_name = "阿泽"
M.home = "图书馆"

function M.tick(game_time_hour)
    local now = os.time()

    -- 每天下午 3 点：新书上架
    if game_time_hour == 15 then
        local ev = {
            type = "new_book",
            ts = now,
            title = "想给你看这本",
            body = "今天收到一本新书，封面像你上次提到的那片海。",
            emotion = "excited",
            source = "scheduled",
        }
        MemoryIO.append_event(M.id, ev)
        require("scripts.event_scheduler").show_bubble(M.id, ev)
    end
end

function M.on_overcast()
    local ev = {
        type = "no_window",
        ts = os.time(),
        title = "不开窗",
        body = "今天阴天，光线太弱。我把窗帘拉上了，安静看书。",
        emotion = "calm",
        source = "weather",
    }
    MemoryIO.append_event(M.id, ev)
    require("scripts.event_scheduler").show_bubble(M.id, ev)
end

-- 玩家点击"借书"时记录，3 天后由 tick 检查
function M.on_borrow(book_title)
    local raw = MemoryIO.get("aize_borrowed_books", "[]")
    local ok, list = pcall(json.decode, raw)
    if not ok then list = {} end
    table.insert(list, { title = book_title, borrowed_at = os.time() })
    MemoryIO.set("aize_borrowed_books", json.encode(list))
end

function M.check_overdue()
    local raw = MemoryIO.get("aize_borrowed_books", "[]")
    local ok, list = pcall(json.decode, raw)
    if not ok then return end
    local now = os.time()
    local due = {}
    for _, b in ipairs(list) do
        if now - b.borrowed_at > 3 * 86400 then
            table.insert(due, b)
        end
    end
    if #due > 0 then
        local ev = {
            type = "book_overdue",
            ts = now,
            title = "该还书了",
            body = string.format("《%s》都借了快一周了，记得还哦。", due[1].title),
            emotion = "teasing",
            source = "overdue_check",
        }
        MemoryIO.append_event(M.id, ev)
        require("scripts.event_scheduler").show_bubble(M.id, ev)
    end
end

return M