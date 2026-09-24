-- ============================================================================
-- ElizaService.lua — 离线规则式陪伴对话层
--
-- 它不是事实源，也不尝试模拟大语言模型：只从本条消息与可选引用里匹配有限主题，
-- 产出一条不含新城市/事件/时间承诺的回应或追问。所有生活事实仍由 EventService
-- 和 ContentService 生成；没匹配到就返回 nil，保留既有模板回复。
-- ============================================================================

local ProfileService = require("ProfileService")

local ElizaService = {}

---@class ElizaRule
---@field id string
---@field words string[]
---@field lines string[]

---@type ElizaRule[]
local RULES = {
    {
        id = "fatigue",
        words = { "累", "困", "辛苦", "熬夜", "没睡" },
        lines = {
            "听着挺累的。你现在能歇一会儿吗？",
            "先别硬撑。你想先缓一缓，还是把这件事说完？",
        },
    },
    {
        id = "pressure",
        words = { "难过", "烦", "焦虑", "压力", "崩", "委屈" },
        lines = {
            "这件事听着不轻。你想先从哪一段说起？",
            "不用急着把它讲明白。现在最让你难受的是哪一点？",
        },
    },
    {
        id = "work",
        words = { "项目", "工作", "作业", "开会", "赶", "加班" },
        lines = {
            "先别把所有事一起扛着。最卡的是哪一块？",
            "听起来今天又被事情追着跑。要不要挑一件先说？",
        },
    },
    {
        id = "food",
        words = { "吃", "饭", "饿", "咖啡", "夜宵" },
        lines = {
            "先把这一口顾上。你现在吃到什么了？",
            "饿着的时候什么都容易变难。你先找点热的？",
        },
    },
    {
        id = "thanks",
        words = { "谢谢", "谢了", "多谢" },
        lines = {
            "不用谢。你愿意说，我就听着。",
            "没事，能帮你接住一点就好。",
        },
    },
    {
        id = "care",
        words = { "还好吗", "怎么样", "在忙吗", "睡了吗" },
        lines = {
            "我在。你今天过得还顺吗？",
            "这边没事。倒是你，今天有没有一点能喘气的空档？",
        },
    },
}

---@type table<string, string[]>
local RELATION_PREFIX = {
    stranger = { "", "" },
    classmate = { "老同学，", "" },
    ex_colleague = { "老搭档，", "" },
    old_friend = { "好久没听你这么说了，", "" },
}

local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 ~ s:byte(i)) & 0x7FFFFFFF
    end
    return h
end

---@param source string
---@param words string[]
---@return boolean
local function containsAny(source, words)
    for i = 1, #words do
        if source:find(words[i], 1, true) then
            return true
        end
    end
    return false
end

--- 从本条消息与引用中选择一条确定性的规则回应；不匹配即 nil。
---@param userText string
---@param quoteText? string
---@param turnIndex integer
---@return string|nil tail
---@return string|nil ruleId
function ElizaService.ReplyTail(userText, quoteText, turnIndex)
    local source = (userText or "") .. " " .. (quoteText or "")
    for i = 1, #RULES do
        local rule = RULES[i]
        if containsAny(source, rule.words) then
            local seed = source .. "|" .. rule.id .. "|" .. tostring(turnIndex or 0)
            local line = rule.lines[(hash(seed) % #rule.lines) + 1]
            local relationId = ProfileService.GetRelationId()
            local prefixes = RELATION_PREFIX[relationId] or RELATION_PREFIX.stranger
            local prefix = prefixes[(hash(seed .. "|relation") % #prefixes) + 1]
            return prefix .. line, rule.id
        end
    end
    return nil, nil
end

return ElizaService
