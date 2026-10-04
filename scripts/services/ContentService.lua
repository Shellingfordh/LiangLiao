-- ============================================================================
-- ContentService.lua — 固定模板 + 变量替换生成回复
-- 运行时没有 LLM（见 docs/maker-lua-api-verification.md），这里只做查表拼装：
-- 输入 = EventService 的事件事实 + 用户原文（+ 可选引用），输出 = 1–3 条短句。
-- 同一事实 + 同一原文必须得到同一句（可复现，不引入随机）。
-- 模板用 {token} 占位，避免 string.format 的参数顺序在中文句子里数错。
-- 引用（quote）只做两件事：被回指的宾语、话题词匹配的额外输入。
-- 它没有任何入口能改写事实——可用性/事件/时刻一律来自 EventService 的 fact。
-- ============================================================================

local ProfileService = require("ProfileService")
local ElizaService = require("services.ElizaService")

local ContentService = {}

-- 关键词 → 话题，用于记忆与模板分支
---@type { topic: string, words: string[] }[]
local TOPIC_WORDS = {
    { topic = "time",    words = { "几点", "傍晚", "时间", "今天", "现在", "晚上" , "what time", "evening", "time", "today", "now", "tonight" } },
    { topic = "event",   words = { "活动", "顺利", "演出", "麦克风", "店里", "咖啡馆", "忙" , "event", "well", "show", "mic", "shop", "cafe", "busy" } },
    { topic = "weather", words = { "天气", "下雨", "晴", "冷", "热", "风" , "weather", "rain", "sunny", "cold", "hot", "wind" } },
    { topic = "feel",    words = { "累", "开心", "难过", "想", "还好", "辛苦" , "tired", "happy", "sad", "miss", "okay", "exhausted" } },
    { topic = "food",    words = { "吃", "喝", "咖啡", "饭", "夜宵" , "eat", "drink", "coffee", "food", "dinner" } },
}

-- 事件事实 → 主干句。每个事件有自己的模板池，禁止把咖啡馆文案套到别的生活事件上。
-- {event} 自带地点，所以模板里不再重复 {place}，否则会出现「咖啡馆…咖啡馆…」
---@type table<string, string[]>
local EVENT_LINES = {
    la_apartment_night_rest = {
        "{event}. We can talk tomorrow if you like. ",
        "{event}. I've left just one lamp on. ",
    },
    la_apartment_morning_inbox = {
        "{event}. The kettle's just boiled. ",
        "{event}. I'm still easing into today's plans. ",
    },
    la_campus_workshop = {
        "{event}. There's one small stack of materials left to set out. ",
        "{event}. I'll run through it once more before everyone arrives. ",
    },
    la_cafe_midday = {
        "{event}. It's a quick lunch today. ",
        "{event}. I'll head back to the studio soon. ",
    },
    la_studio_zine_layout = {
        "{event}. This page's margins still need a little work. ",
        "{event}. Let me check the last two proofs first. ",
        "{event}. Let me adjust this colour, then we can talk. ",
    },
    la_commute_voice_notes = {
        "{event}. I can't type much right now. ",
        "{event}. I'll read properly when I arrive. ",
    },
    la_cafe_open_mic = {
        "{event}. It's {weather} here right now. ",
        "Yes, {event}. It finishes at {ends}. ",
        "{event}. Are you still awake over there? ",
    },
    la_apartment_wind_down = {
        "{event}. I can finally sit quietly for a moment. ",
        "{event}. I've tucked the last note under my cup. ",
    },

    -- ===== 上海（sha）=====
    sha_apartment_night_rest = {
        "{event}. We can talk after I wake up. ",
        "{event}. The lights are off. ",
    },
    sha_apartment_morning_balcony = {
        "{event}. This is where the day's writing begins. ",
        "{event}. I'll head out once the plants are watered. ",
    },
    sha_commute_rush = {
        "{event}. Let's talk when I arrive. ",
        "{event}. Let me get off the train first. ",
    },
    sha_office_topic_meeting = {
        "{event}. We can talk about the article after the meeting. ",
        "{event}. I'll probably be in the meeting room until {ends}. ",
    },
    sha_cafe_midday = {
        "{event}. Two more layouts to check this afternoon. ",
        "{event}. Not much time for lunch today. ",
    },
    sha_office_layout = {
        "{event}. My eyes could use a rest. ",
        "{event}. I'll check it again before it goes to print. ",
    },
    sha_commute_market = {
        "{event}. Just a quick errand after this. ",
        "{event}. I'll say more when I'm home. ",
    },
    sha_bookstore_evening = {
        "{event}. There's still time to stop by. ",
        "{event}. It's {weather}, and the shop feels even quieter. ",
    },
    sha_apartment_reread = {
        "{event}. I'll rest after this paragraph. ",
        "{event}. That's nearly the end of my day. ",
    },

    -- ===== 成都（cdu）=====
    cdu_apartment_night_rest = {
        "{event}. We can talk tomorrow. ",
        "{event}. The lights have been off for a while. ",
    },
    cdu_apartment_morning_water = {
        "{event}. No rush; it's a slow day. ",
        "{event}. My morning tea is still warm. ",
    },
    cdu_studio_morning_ink = {
        "{event}. I'll take a breather after this batch. ",
        "{event}. It's {weather} today, and the light is just right. ",
    },
    cdu_cafe_midday = {
        "{event}. The teahouse is lively as ever. ",
        "{event}. I'll head back after these noodles. ",
    },
    cdu_studio_color = {
        "{event}. I'll feel better once this batch is done. ",
        "{event}. Even a tiny colour difference matters. ",
    },
    cdu_commute_supplies = {
        "{event}. Let's talk when I'm back. ",
        "{event}. It's a bit of a trip; I'm looking around as I go. ",
    },
    cdu_nightmarket_supper = {
        "{event}. Wish you were here to share a bite. ",
        "{event}. It's {weather}, and there's room to sit at the stall. ",
    },
    cdu_apartment_letters = {
        "{event}. This is my last card for tonight. ",
        "{event}. Tonight's words are going on paper. ",
    },

    -- ===== 伦敦（lon）=====
    lon_apartment_night_rest = {
        "{event}. Let's leave it until tomorrow. ",
        "{event}. The project can wait until morning to export. ",
    },
    lon_apartment_morning_tea = {
        "{event}. It's {weather} today; my umbrella's by the door. ",
        "{event}. I've got this little stretch before class to myself. ",
    },
    lon_commute_early_train = {
        "{event}. I'll message you when I arrive. ",
        "{event}. I'll keep sending, even if the signal drops. ",
    },
    lon_campus_lecture = {
        "{event}. I'm still taking notes. ",
        "{event}. I'll check my phone after this. ",
    },
    lon_cafe_midday = {
        "{event}. I can't be late for this afternoon's recording. ",
        "{event}. The sandwich has gone cold; I'm eating as we talk. ",
    },
    lon_studio_field_recording = {
        "{event}. It'll be quiet once this take is done. ",
        "{event}. I'll need my headphones on until {ends}. ",
    },
    lon_commute_dark = {
        "{event}. I'll write more when I'm home. ",
        "{event}. It's {weather}; I've turned my collar up. ",
    },
    lon_recordshop_shift = {
        "{event}. Tell me what record you're after; I'll look for it. ",
        "{event}. My shift ends at {ends}. ",
    },
    lon_apartment_mixdown = {
        "{event}. One last fader, then I'm done for today. ",
        "{event}. One final listen, then I'll leave it there. ",
    },
}

-- 查无此事件的最后兜底：只复述事实，不借别城的句子（四城池已全，正常走不到这里）
---@type string[]
local GENERIC_LINES = {
    "{event}. ",
    "{event}. That's about it. ",
}

-- 碎片时间档：规格 §5.2 要求「回复较短」，所以另开一组短句且不带话题后缀。
-- 唯一例外是引用回指句（用户明确点名的请求），见 BuildSegments。
---@type string[]
local BRIEF_LINES = {
    "{event}. {avail}, so I'll keep this short. ",
    "{event}. {avail}, so I'll leave it there. ",
}

-- 排队补回时的前缀：三个变量全部来自确定时间快照（作息表原话、送达钟点、两条 UTC 之差）
local QUEUED_PREFIX = "At the time: {before}. It's been {gap} before I could reply. "

-- 送达时那件事件到交付已经收了：要说它什么时候收的，不能继续用「正在进行」的口吻
-- 规格 §5.3 的底线是把已结束的说成已结束，而不是含糊地略过。
local QUEUED_ENDED_PREFIX = "At the time: {before}. {sentEvent} ended at {sentEnds}. It's been {gap} before I could reply. "

-- 用户原文里出现了某个话题时追加的半句
---@type table<string, string>
local TOPIC_SUFFIX = {
    time = "Is it daytime where you are? ",
    weather = "It's {weather} here, with hardly any wind. ",
    feel = "I'm okay, just a little tired from standing. ",
    food = "I've got a cold drink beside me. ",
    event = "Wish you were here. ",
}

-- 引用回指句：只「认下」被引用的那一句，不替它编内容、不做任何事实断言。
-- 排在通用话题后缀之前，所以「引用」比「猜话题」更早被回应。
---@type string[]
local QUOTE_ECHO_LINES = {
    "I saw what you said: \"{quote}\". ",
    "I'll keep that in mind: \"{quote}\". ",
}

---@class ReplyQuote
---@field role string "user" | "her"
---@field text string 已裁剪的引用预览（MessageService 存进 quotedTextPreview 的那份）

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
    return (out:gsub("%s+$", ""))
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

--- 对外暴露的截断：引用预览也要按字符数裁，而这条规则全工程只能有一份
---@param s string
---@param maxRunes integer
---@return string
function ContentService.ClipPreview(s, maxRunes)
    return clip(s or "", maxRunes)
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
        avail = fact.availabilityLabel,
        -- 注意别用 then/if 这类 Lua 关键字做键名：表构造器里会直接语法错
        before = fact.thenPhrase or "",
        gap = ContentService.FormatGap(fact.gapSeconds),
        sentEvent = fact.sentEventTitle or "",
        sentEnds = fact.sentEventEndsAt or "",
        m7Answer = fact.m7Answer or fact.eventPhrase or "",
    }
end

--- 两条权威 UTC 之差 → 人话时长。不解释「她这段时间干了什么」，只报客观间隔。
---@param seconds integer?
---@return string
function ContentService.FormatGap(seconds)
    local s = math.max(0, math.floor(seconds or 0))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then
        return tostring(h) .. "h " .. tostring(m) .. "min"
    elseif m > 0 then
        return tostring(m) .. "min"
    end
    return tostring(s) .. "s"
end

---@param text string
---@return string[] topics
function ContentService.DetectTopics(text)
    ---@type string[]
    local found = {}
    local src = (text or ""):lower()
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

--- M7 的自由输入守卫：命中事件卡声明的自然发问方向才给出该方向的固定回答；
--- 其他输入仍可聊天，但第一句只能承认当前可确认的事实，不能把模板伪装成精确理解。
---@param fact EventFact
---@param text string
---@return boolean
local function matchesM7Question(fact, text)
    if fact.isM7KeyEvent ~= true or type(fact.questionHints) ~= "table" then
        return false
    end
    local source = (text or ""):lower()
    for i = 1, #fact.questionHints do
        local hint = fact.questionHints[i]
        if type(hint) == "string" and hint ~= "" and source:find(hint, 1, true) then
            return true
        end
    end
    return false
end

--- 组装 1–3 段短回复。事实只从 fact 取（EventService 是唯一事实源），
--- quote 只作为被回指的宾语和话题词匹配的额外输入。
---@param fact EventFact
---@param userText string 用户原文（参与选模板与回显）
---@param turnIndex integer 第几轮，用于稳定地换措辞
---@param quote? ReplyQuote 本次消息引用的那条（已裁剪）
---@return string[]
local function BuildSegments(fact, userText, turnIndex, quote)
    local briefReply = fact.brief == true
    local pool
    if fact.isM7KeyEvent == true and type(fact.m7Answer) == "string" and fact.m7Answer ~= "" then
        if matchesM7Question(fact, userText or "") then
            pool = { "{m7Answer}" }
        else
            pool = { "What I can tell you is: {m7Answer}" }
        end
    elseif briefReply then
        pool = BRIEF_LINES
    else
        pool = EVENT_LINES[fact.id] or GENERIC_LINES
    end
    local quoteText = quote and quote.text or ""
    local seed = (userText or "") .. "|" .. fact.id .. "|" .. tostring(turnIndex)
    local pick = (hash(seed) % #pool) + 1
    local vars = varsOf(fact)
    vars.quote = quoteText

    ---@type string[]
    local segments = {}

    -- 第一段：主干句。碎片档到此为止（规格 §5.2 要求回复要短）
    local head = fill(pool[pick] or pool[1] or "", vars)
    if fact.queued and fact.thenPhrase then
        if fact.sentEventState == "ended" then
            head = fill(QUEUED_ENDED_PREFIX, vars) .. " " .. head
        else
            head = fill(QUEUED_PREFIX, vars) .. " " .. head
        end
    end
    -- 回显用户原文：证明回复是对这句话的回应，而不是自说自话
    local quoted = clip(userText or "", 12)
    if quoted ~= "" then
        head = "\"" .. quoted .. "\" — " .. head
    end
    segments[#segments + 1] = head

    -- 第二段：被引用的那一句。紧跟在主干句之后、通用话题后缀之前。
    -- 碎片档也保留这一段：引用是用户明确点名的请求（「这句再说一遍」），
    -- 被引句必须真的回到回复里；碎片档省的只是话题后缀与关系风味（自检 Y10 断言）。
    if quoteText ~= "" then
        local echoSeed = quoteText .. "|" .. fact.id .. "|" .. tostring(turnIndex)
        local echoPick = (hash(echoSeed) % #QUOTE_ECHO_LINES) + 1
        local echoTpl = QUOTE_ECHO_LINES[echoPick]
        if echoTpl and echoTpl ~= "" then
            segments[#segments + 1] = fill(echoTpl, vars)
        end
    end

    if briefReply then
        return segments
    end

    -- 第三段优先走离线 Eliza 规则：只回应本条话的主题，不改写城市/事件/时间事实。
    -- 不命中时才继续沿用原来的话题半句与关系风味，保证任何输入都有稳定回退。
    local elizaTail = ElizaService.ReplyTail(userText or "", quoteText, turnIndex)
    if elizaTail and elizaTail ~= "" then
        segments[#segments + 1] = elizaTail
        return segments
    end

    -- 第三段：原文（连同被引用那句）里出现某个话题时追加的半句
    local topics = ContentService.DetectTopics((userText or "") .. " " .. quoteText)
    local suffixTpl = topics[1] and TOPIC_SUFFIX[topics[1]]
    local suffixAdded = false
    if suffixTpl and suffixTpl ~= "" then
        local suffix = fill(suffixTpl, vars)
        if suffix ~= "" then
            segments[#segments + 1] = suffix
            suffixAdded = true
        end
    end

    -- 关系风味段：本轮没有话题后缀时补一段，让关系本身进正文而不只是开场。
    -- 只在段数还没到 3 时补——多段上限不因 M3 放宽。
    if not suffixAdded and #segments < 3 then
        local flavor = ProfileService.RelationFlavor(seed .. "|" .. tostring(#segments))
        if flavor and flavor ~= "" then
            segments[#segments + 1] = flavor
        end
    end

    return segments
end

--- 生成回复正文（单串）。多段上屏走 ReplySegments；这个入口留给兜底与兼容。
---@param fact EventFact
---@param userText string 用户原文（参与选模板与回显）
---@param turnIndex integer 第几轮，用于稳定地换措辞
---@return string
function ContentService.Reply(fact, userText, turnIndex)
    return table.concat(BuildSegments(fact, userText, turnIndex, nil), " ")
end

--- 生成 1–3 段短回复，由 MessageService 复用 typing 相位逐句上屏。
--- 分段之间天然以句号收尾，所以不再需要拼接口点号的兜底。
---@param fact EventFact
---@param userText string 用户原文（参与选模板与回显）
---@param turnIndex integer 第几轮，用于稳定地换措辞
---@param quote? ReplyQuote 本次消息引用的那条
---@return string[]
function ContentService.ReplySegments(fact, userText, turnIndex, quote)
    return BuildSegments(fact, userText, turnIndex, quote)
end

--- 重进时唯一一条「离开期间」摘要。只报客观间隔与两头的作息原话，
--- 不按小时铺开她做了什么（规格 §5.3：每次离线重入只交付一条最有意义的摘要）。
--- 城市标签与「那会儿她…」的措辞都取自当前档案；洛杉矶 × 陌生网友的输出与 M2 逐字一致。
---@param gapSeconds integer 上次落盘时刻 → 现在
---@param thenPhrase string 上次离开时她那档的原话
---@param nowPhrase string 现在她那档的原话
---@param pendingCount integer 还有几条排队待回
---@param cityLabel? string 省略则取当前档案城市
---@return string
function ContentService.AwaySummary(gapSeconds, thenPhrase, nowPhrase, pendingCount, cityLabel)
    local thenText, nowText = ProfileService.AwayPhrases(thenPhrase, nowPhrase)
    local line = string.format("While you were away · %s · %s elapsed · %s; %s",
        cityLabel or ProfileService.Get().cityLabel,
        ContentService.FormatGap(gapSeconds), thenText, nowText)
    if pendingCount and pendingCount > 0 then
        line = line .. string.format(" · %d messages waiting for her reply", pendingCount)
    end
    return line
end

--- 开场白（不属于回复链路，仅用于让会话看起来是活的）
---@param fact EventFact
---@return string
function ContentService.OpeningLine(fact)
    return fill("{event}. Tell me what's on your mind. ", varsOf(fact))
end

return ContentService
