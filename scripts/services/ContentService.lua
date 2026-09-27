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
    { topic = "time",    words = { "几点", "傍晚", "时间", "今天", "现在", "晚上" } },
    { topic = "event",   words = { "活动", "顺利", "演出", "麦克风", "店里", "咖啡馆", "忙" } },
    { topic = "weather", words = { "天气", "下雨", "晴", "冷", "热", "风" } },
    { topic = "feel",    words = { "累", "开心", "难过", "想", "还好", "辛苦" } },
    { topic = "food",    words = { "吃", "喝", "咖啡", "饭", "夜宵" } },
}

-- 事件事实 → 主干句。每个事件有自己的模板池，禁止把咖啡馆文案套到别的生活事件上。
-- {event} 自带地点，所以模板里不再重复 {place}，否则会出现「咖啡馆…咖啡馆…」
---@type table<string, string[]>
local EVENT_LINES = {
    la_apartment_night_rest = {
        "{event}，有什么明天再说也行。",
        "{event}，这会儿只留了一盏灯。",
    },
    la_apartment_morning_inbox = {
        "{event}，水刚烧开。",
        "{event}，今天的安排还没完全醒过来。",
    },
    la_campus_workshop = {
        "{event}，材料还差一小叠没摆好。",
        "{event}，等人到齐前我再过一遍流程。",
    },
    la_cafe_midday = {
        "{event}，饭吃得很快。",
        "{event}，一会儿还要回工作室。",
    },
    la_studio_zine_layout = {
        "{event}，这一页的边距还差一点。",
        "{event}，我先把最后两张样张对完。",
        "{event}，等我把这处颜色挪好再和你说。",
    },
    la_commute_voice_notes = {
        "{event}，现在不太方便打长字。",
        "{event}，等到站我再看仔细一点。",
    },
    la_cafe_open_mic = {
        "{event}，店里这会儿{weather}。",
        "嗯，{event}，要到{ends}才收。",
        "{event}。你那边这个点还醒着？",
    },
    la_apartment_wind_down = {
        "{event}，现在终于能安静坐一会儿。",
        "{event}，我把最后一张便签压在杯子下面了。",
    },

    -- ===== 上海（sha）=====
    sha_apartment_night_rest = {
        "{event}，有什么睡起来再说。",
        "{event}，灯已经关了。",
    },
    sha_apartment_morning_balcony = {
        "{event}，一天的字从这儿开头。",
        "{event}，浇完花我就出门。",
    },
    sha_commute_rush = {
        "{event}，到站再说。",
        "{event}，我先顾着下车。",
    },
    sha_office_topic_meeting = {
        "{event}，稿子的事散会再讲。",
        "{event}，到{ends}前多半都在会议室。",
    },
    sha_cafe_midday = {
        "{event}，下午还有两版要盯。",
        "{event}，这顿吃得快。",
    },
    sha_office_layout = {
        "{event}，眼睛快对不上了。",
        "{event}，等付印前我再过一遍。",
    },
    sha_commute_market = {
        "{event}，顺手的事，说完就去。",
        "{event}，一会儿到家再细说。",
    },
    sha_bookstore_evening = {
        "{event}，你要来也来得及。",
        "{event}，{weather}的天，店里更安静。",
    },
    sha_apartment_reread = {
        "{event}，改完这段就休息。",
        "{event}，一天到这里差不多收口了。",
    },

    -- ===== 成都（cdu）=====
    cdu_apartment_night_rest = {
        "{event}，有事明天再说。",
        "{event}，灯早关了。",
    },
    cdu_apartment_morning_water = {
        "{event}，不急，今天节奏慢。",
        "{event}，上午的茶还没凉。",
    },
    cdu_studio_morning_ink = {
        "{event}，画完这一批再喘口气。",
        "{event}，今天{weather}，光线正好。",
    },
    cdu_cafe_midday = {
        "{event}，茶馆就这样，热闹。",
        "{event}，吃完这碗再回去。",
    },
    cdu_studio_color = {
        "{event}，这批交完就松了。",
        "{event}，颜色差一点都是事。",
    },
    cdu_commute_supplies = {
        "{event}，回来再聊。",
        "{event}，一趟不容易，边走边看。",
    },
    cdu_nightmarket_supper = {
        "{event}，你要是在就一起吃口。",
        "{event}，{weather}，摊子上坐得下去。",
    },
    cdu_apartment_letters = {
        "{event}，写完这张就收工。",
        "{event}，今晚的话留到纸上。",
    },

    -- ===== 伦敦（lon）=====
    lon_apartment_night_rest = {
        "{event}，有事明天说。",
        "{event}，工程挂着明早导出。",
    },
    lon_apartment_morning_tea = {
        "{event}，今天{weather}，伞在门口。",
        "{event}，早课前的这点时间是完整的。",
    },
    lon_commute_early_train = {
        "{event}，到站再找你。",
        "{event}，消息断了我先都发着。",
    },
    lon_campus_lecture = {
        "{event}，笔记还记着呢。",
        "{event}，忙完这阵我再看手机。",
    },
    lon_cafe_midday = {
        "{event}，下午的录音不能迟到。",
        "{event}，三明治凉了，边吃边说。",
    },
    lon_studio_field_recording = {
        "{event}，这段收完就安静了。",
        "{event}，到{ends}前我都得戴着耳机。",
    },
    lon_commute_dark = {
        "{event}，到家再打长字。",
        "{event}，{weather}，我把领子竖起来了。",
    },
    lon_recordshop_shift = {
        "{event}，你要什么唱片我帮你翻。",
        "{event}，班守到{ends}。",
    },
    lon_apartment_mixdown = {
        "{event}，推子一收今天就完。",
        "{event}，最后一遍，不添话了。",
    },
}

-- 查无此事件的最后兜底：只复述事实，不借别城的句子（四城池已全，正常走不到这里）
---@type string[]
local GENERIC_LINES = {
    "{event}。",
    "{event}，就这些。",
}

-- 碎片时间档：规格 §5.2 要求「回复较短」，所以另开一组短句且不带话题后缀。
-- 唯一例外是引用回指句（用户明确点名的请求），见 BuildSegments。
---@type string[]
local BRIEF_LINES = {
    "这会儿{avail}，{event}。",
    "{event}。{avail}，先说到这儿。",
}

-- 排队补回时的前缀：三个变量全部来自确定时间快照（作息表原话、送达钟点、两条 UTC 之差）
local QUEUED_PREFIX = "那会儿{before}，隔了{gap}才回你。"

-- 送达时那件事件到交付已经收了：要说它什么时候收的，不能继续用「正在进行」的口吻
-- 规格 §5.3 的底线是把已结束的说成已结束，而不是含糊地略过。
local QUEUED_ENDED_PREFIX = "那会儿{before}，{sentEvent}到{sentEnds}就收了，隔了{gap}才回你。"

-- 用户原文里出现了某个话题时追加的半句
---@type table<string, string>
local TOPIC_SUFFIX = {
    time = "你那边这个点是白天吧",
    weather = "这边{weather}，风不大",
    feel = "我还好，就是站久了有点累",
    food = "手边是一杯冰的",
    event = "你要是在就好了",
}

-- 引用回指句：只「认下」被引用的那一句，不替它编内容、不做任何事实断言。
-- 排在通用话题后缀之前，所以「引用」比「猜话题」更早被回应。
---@type string[]
local QUOTE_ECHO_LINES = {
    "你刚才那句「{quote}」，我看见了。",
    "「{quote}」这句我记下了。",
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
        return tostring(h) .. " 小时 " .. tostring(m) .. " 分"
    elseif m > 0 then
        return tostring(m) .. " 分"
    end
    return tostring(s) .. " 秒"
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

--- M7 的自由输入守卫：命中事件卡声明的自然发问方向才给出该方向的固定回答；
--- 其他输入仍可聊天，但第一句只能承认当前可确认的事实，不能把模板伪装成精确理解。
---@param fact EventFact
---@param text string
---@return boolean
local function matchesM7Question(fact, text)
    if fact.isM7KeyEvent ~= true or type(fact.questionHints) ~= "table" then
        return false
    end
    local source = text or ""
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
            pool = { "我只能先确认：{m7Answer}" }
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
            head = fill(QUEUED_ENDED_PREFIX, vars) .. head
        else
            head = fill(QUEUED_PREFIX, vars) .. head
        end
    end
    -- 回显用户原文：证明回复是对这句话的回应，而不是自说自话
    local quoted = clip(userText or "", 12)
    if quoted ~= "" then
        head = "「" .. quoted .. "」" .. head
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
    return table.concat(BuildSegments(fact, userText, turnIndex, nil), "")
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
    local line = string.format("离开期间 · %s过了 %s · %s，%s",
        cityLabel or ProfileService.Get().cityLabel,
        ContentService.FormatGap(gapSeconds), thenText, nowText)
    if pendingCount and pendingCount > 0 then
        line = line .. string.format(" · 还有 %d 条在等她回", pendingCount)
    end
    return line
end

--- 开场白（不属于回复链路，仅用于让会话看起来是活的）
---@param fact EventFact
---@return string
function ContentService.OpeningLine(fact)
    return fill("我在{place}，{event}。你可以随便说点什么。", varsOf(fact))
end

return ContentService
