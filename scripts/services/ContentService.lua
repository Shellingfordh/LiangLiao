-- ============================================================================
-- ContentService.lua — 固定模板 + 变量替换生成回复
-- 运行时没有 LLM（见 docs/maker-lua-api-verification.md），这里只做查表拼装：
-- 输入 = EventService 的事件事实 + 用户原文，输出 = 一条简短中文。
-- 同一事实 + 同一原文必须得到同一句（可复现，不引入随机）。
-- 模板用 {token} 占位，避免 string.format 的参数顺序在中文句子里数错。
-- ============================================================================

local ContentService = {}

-- 关键词 → 话题，用于记忆与模板分支
---@type { topic: string, words: string[] }[]
local TOPIC_WORDS = {
    { topic = "time",    words = { "几点", "傍晚", "时间", "今天", "现在", "晚上" } },
    { topic = "event",   words = { "活动", "顺利", "演出", "麦克风", "店里", "咖啡馆", "忙" } },
    { topic = "weather", words = { "天气", "下雨", "晴", "冷", "热", "风" } },
    { topic = "feel",    words = { "累", "开心", "难过", "想", "还好", "辛苦" } },
    { topic = "food",    words = { "吃", "喝", "咖啡", "饭", "夜宵" } },
}

-- 事件事实 → 主干句。首版唯一的话题就是洛杉矶咖啡馆这一场。
-- {event} 自带地点，所以模板里不再重复 {place}，否则会出现「咖啡馆…咖啡馆…」
---@type table<string, string[]>
local EVENT_LINES = {
    ongoing = {
        "{event}，店里这会儿{weather}。",
        "嗯，{event}，要到{ends}才收。",
        "{event}。你那边这个点还醒着？",
    },
    upcoming = {
        "{event}，{ends}才开始。",
        "{event}，今天{weather}，我先把手头的做完。",
        "{event}，你要跟我说说今天吗？",
    },
    ended = {
        "{event}。你今天过得怎么样？",
        "{event}，明天还有一场。",
        "{event}，刚坐下。",
    },
}

-- 用户原文里出现了某个话题时追加的半句
---@type table<string, string>
local TOPIC_SUFFIX = {
    time = "你那边这个点是白天吧",
    weather = "这边{weather}，风不大",
    feel = "我还好，就是站久了有点累",
    food = "手边是一杯冰的",
    event = "你要是在就好了",
}

local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 ~ s:byte(i)) & 0x7FFFFFFF
    end
    return h
end

---@param tpl string
---@param vars table<string, string>
---@return string
local function fill(tpl, vars)
    local out = (tpl:gsub("{(%w+)}", function(key)
        return vars[key] or ""
    end))
    return out
end

--- UTF-8 安全截断，只用于回显用户原文，按字符数裁
---@param s string
---@param maxRunes integer
---@return string
local function clip(s, maxRunes)
    local runes = 0
    local bytePos = 1
    local n = #s
    while bytePos <= n and runes < maxRunes do
        local b = s:byte(bytePos)
        local step = 1
        if b >= 0xF0 then
            step = 4
        elseif b >= 0xE0 then
            step = 3
        elseif b >= 0xC0 then
            step = 2
        end
        bytePos = bytePos + step
        runes = runes + 1
    end
    if bytePos > n then
        return s
    end
    return s:sub(1, bytePos - 1) .. "…"
end

--- 事件事实 → 模板变量表
---@param fact EventFact
---@return table<string, string>
local function varsOf(fact)
    return {
        place = fact.placeLabel,
        event = fact.eventPhrase,
        ends = fact.eventEndsAt,
        clock = fact.clock,
        weather = fact.weather,
        city = fact.cityLabel,
    }
end

---@param text string
---@return string[] topics
function ContentService.DetectTopics(text)
    ---@type string[]
    local found = {}
    local src = text or ""
    for i = 1, #TOPIC_WORDS do
        local entry = TOPIC_WORDS[i]
        for j = 1, #entry.words do
            if src:find(entry.words[j], 1, true) then
                found[#found + 1] = entry.topic
                break
            end
        end
    end
    return found
end

--- 生成回复正文
---@param fact EventFact
---@param userText string 用户原文（参与选模板与回显）
---@param turnIndex integer 第几轮，用于稳定地换措辞
---@return string
function ContentService.Reply(fact, userText, turnIndex)
    local pool = EVENT_LINES[fact.eventState] or EVENT_LINES.ongoing
    local seed = (userText or "") .. "|" .. fact.id .. "|" .. tostring(turnIndex)
    local pick = (hash(seed) % #pool) + 1
    local vars = varsOf(fact)

    local body = fill(pool[pick] or pool[1] or "", vars)

    -- 回显用户原文：证明回复是对这句话的回应，而不是自说自话
    local quoted = clip(userText or "", 12)
    if quoted ~= "" then
        body = "「" .. quoted .. "」" .. body
    end

    local topics = ContentService.DetectTopics(userText)
    local suffixTpl = topics[1] and TOPIC_SUFFIX[topics[1]]
    if suffixTpl and suffixTpl ~= "" then
        body = body .. "，" .. fill(suffixTpl, vars)
    end

    return body
end

--- 开场白（不属于回复链路，仅用于让会话看起来是活的）
---@param fact EventFact
---@return string
function ContentService.OpeningLine(fact)
    return fill("我在{place}，{event}。你可以随便说点什么。", varsOf(fact))
end

--- 首条默认草稿（任务书指定的那句原文）
---@return string
function ContentService.DefaultDraft()
    return "你那边是不是快傍晚了？今天的活动还顺利吗？"
end

return ContentService
