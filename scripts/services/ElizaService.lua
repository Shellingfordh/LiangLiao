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
        words = { "累", "困", "辛苦", "熬夜", "没睡" , "tired", "sleepy", "exhausted", "late night", "no sleep" },
        lines = {
            "That sounds tiring. Can you take a little break?",
            "You don't have to push through. Want a breather, or would you rather talk it out?",
        },
    },
    {
        id = "pressure",
        words = { "难过", "烦", "焦虑", "压力", "崩", "委屈" , "sad", "upset", "anxious", "stress", "overwhelmed", "hurt" },
        lines = {
            "That sounds like a lot. Where would you like to start?",
            "No need to explain it all at once. What's weighing on you most?",
        },
    },
    {
        id = "work",
        words = { "项目", "工作", "作业", "开会", "赶", "加班" , "project", "work", "homework", "meeting", "deadline", "overtime" },
        lines = {
            "One thing at a time. What's the hardest part right now?",
            "Sounds like a busy day. Want to pick one thing to talk about?",
        },
    },
    {
        id = "food",
        words = { "吃", "饭", "饿", "咖啡", "夜宵" , "eat", "food", "hungry", "coffee", "dinner" },
        lines = {
            "Food first. What are you having?",
            "Everything feels harder on an empty stomach. Could you get something warm?",
        },
    },
    {
        id = "thanks",
        words = { "谢谢", "谢了", "多谢" , "thanks", "thank you", "thankful" },
        lines = {
            "You're welcome. I'm glad you told me.",
            "I'm glad I could make it a little easier.",
        },
    },
    {
        id = "care",
        words = { "还好吗", "怎么样", "在忙吗", "睡了吗" , "how are you", "how is it going", "are you busy", "are you asleep" },
        lines = {
            "I'm here. How's your day going?",
            "I'm okay. Have you had a moment to catch your breath today?",
        },
    },
}

---@type table<string, string[]>
local RELATION_PREFIX = {
    stranger = { "", "" },
    classmate = { "Hey, ", "" },
    ex_colleague = { "Hey, ", "" },
    old_friend = { "It's been a while since we talked like this. ", "" },
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
        local word = words[i]
        local matched = word:match("^[%a%s]+$")
            and source:find("%f[%a]" .. word .. "%f[%A]")
            or (not word:match("^[%a%s]+$") and source:find(word, 1, true))
        if matched then
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
    local source = ((userText or "") .. " " .. (quoteText or "")):lower()
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
