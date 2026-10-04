-- ============================================================================
-- ProfileService.lua — 城市 × 关系档案的唯一声明处（M3）
-- 把「她住在哪座城市、和你是什么关系」收进一张矩阵：城市决定生活身份与日程叙事，
-- 关系决定称呼、开场语气、离线摘要说法与关系风味句。二者共同决定档案，
-- 而不是把「洛杉矶」换成「上海」的名字换皮游戏。
--
-- 分工边界（避免和已有服务抢真源）：
--   * 钟点/地点/可用性/事件实例：TimeState + EventService 才是事实源，本模块不重复声明。
--     这里的事件短语只是「身份摘要」，与 EventService 当日 occurrence 的叙事口径一致。
--   * 回复正文：仍由 ContentService 按事件模板句池生成，本模块只提供关系风味第三段。
--   * 随机入口：定种派生（fnv1a + 创建 UTC 秒），无 math.random；首次结果落盘后不再变。
--
-- 日志红线：本模块产出的文本会进聊天流，但运行日志只记 cityId/relationId/长度，
-- 不落任何含用户原文的串。
-- ============================================================================

local EnglishText = require("EnglishText")
local ProfileService = {}

local CITY_ORDER = { "shanghai", "chengdu", "los_angeles", "london" }
local RELATION_ORDER = { "stranger", "classmate", "ex_colleague", "old_friend" }

-- 随机盐：换这一串等于换一套随机分布，是版本标记而非随机源（与 EventService 的 SEED_SALT 同性质）
local RANDOM_SALT = "m3-random-v1"

local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h ~ s:byte(i)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    end
    return h
end

-- ============================================================================
-- 城市档案：生活身份 + 场景词汇 + 事件叙事摘要 + 默认草稿
-- sceneVocab 列出该城可见的状态窗场景 id（每城 ≥2），与 StatusWindow 的静帧键对齐。
-- events 是「这一档她在做什么」的短语摘要，钟点与命中实例由 TimeState/EventService 决定。
-- ============================================================================

---@class CityProfile
---@field id string
---@field label string
---@field identity string 生活身份（原创）
---@field identityShort string 信息卡用的短身份
---@field defaultRelation string
---@field sceneVocab string[] 可见状态窗场景 id（≥2）
---@field events table<string, string> occurrenceKey 片段(模板 id) → 叙事短语
---@field defaultDraft string 首次进入输入框的默认草稿（任务书指定句或本城对应句）

---@type table<string, CityProfile>
local CITIES = {
    los_angeles = {
        id = "los_angeles", label = "Los Angeles",
        identity = "An event-planning graduate in Los Angeles who hosts open mic nights and makes independent zines.",
        identityShort = "Events · Independent zines",
        defaultRelation = "stranger",
        sceneVocab = { "la_apartment", "la_studio", "la_cafe", "la_commute" },
        events = {
            la_apartment_night_rest = "I'm asleep at home, with notes from the day's event still on the desk",
            la_apartment_morning_inbox = "I'm sorting the event emails and notes this morning",
            la_campus_workshop = "I'm preparing a small workshop in the studio",
            la_cafe_midday = "I'm having lunch at the cafe and checking tonight's plans",
            la_studio_zine_layout = "I'm checking the zine layout proofs in the studio",
            la_commute_voice_notes = "I'm organising voice notes for tonight's event on my way",
            la_cafe_open_mic = "I'm at the cafe's open mic night",
            la_apartment_wind_down = "I'm back at the apartment, sorting tonight's event notes",
        },
        defaultDraft = "Is it almost evening there? How did today's event go?",
    },
    shanghai = {
        id = "shanghai", label = "Shanghai",
        identity = "A city-life editor who also volunteers at a second-hand bookshop in the evenings.",
        identityShort = "Editor · Bookshop volunteer",
        defaultRelation = "classmate",
        sceneVocab = { "sha_apartment", "sha_office", "sha_bookstore", "sha_commute" },
        events = {
            sha_apartment_night_rest = "I'm asleep at home, with tomorrow's column draft still out",
            sha_apartment_morning_balcony = "I'm watering the balcony plants and reviewing today's writing",
            sha_commute_rush = "I'm on the rush-hour metro, so typing is a little tricky",
            sha_office_topic_meeting = "I'm in the newsroom's editorial meeting; it's been going all morning",
            sha_cafe_midday = "I'm having lunch in the newsroom while checking layouts",
            sha_office_layout = "I'm checking this issue's layout in the newsroom",
            sha_commute_market = "I'm stopping at the market to pick up some food for home",
            sha_bookstore_evening = "I'm on the evening shift at the second-hand bookshop; it's very quiet",
            sha_apartment_reread = "I'm back at the apartment and I've reread tomorrow's article",
        },
        defaultDraft = "Is it afternoon there already? How's your column coming along?",
    },
    chengdu = {
        id = "chengdu", label = "Chengdu",
        identity = "A freelance illustrator making postcards of local life, often found at teahouses and night markets.",
        identityShort = "Illustrator · Local postcards",
        defaultRelation = "ex_colleague",
        sceneVocab = { "cdu_apartment", "cdu_studio", "cdu_cafe", "cdu_commute" },
        events = {
            cdu_apartment_night_rest = "I'm asleep at home, with postcards still drying on the desk",
            cdu_apartment_morning_water = "I've watered the balcony plants, but haven't started work yet",
            cdu_studio_morning_ink = "I'm outlining and colouring a batch of postcards in the studio",
            cdu_cafe_midday = "I'm having noodles at the teahouse and looking at other people's sketches",
            cdu_studio_color = "I'm finishing today's colours at the workbench",
            cdu_commute_supplies = "I'm out buying paint and paper; it's a bit of a trip",
            cdu_nightmarket_supper = "I've packed up my night-market stall and had a late snack",
            cdu_apartment_letters = "I'm back at the apartment, addressing the postcards I'm sending out",
        },
        defaultDraft = "Have you eaten yet? I haven't finished today's postcards.",
    },
    london = {
        id = "london", label = "London",
        identity = "A sound-design postgraduate who works weekends at an old record shop.",
        identityShort = "Sound design · Record shop",
        defaultRelation = "old_friend",
        sceneVocab = { "lon_apartment", "lon_studio", "lon_recordshop", "lon_commute" },
        events = {
            lon_apartment_night_rest = "I'm asleep at home, and the mix hasn't been exported yet",
            lon_apartment_morning_tea = "I've made tea and checked today's class timetable",
            lon_commute_early_train = "I'm catching an early train, and the signal keeps dropping",
            lon_campus_lecture = "I'm at a sound-design workshop in the college studio and can't step away",
            lon_cafe_midday = "I've bought a sandwich on the street before heading to the studio",
            lon_studio_field_recording = "I'm collecting a field recording in the studio",
            lon_commute_dark = "It's dark already, and the crowds are slowing me down",
            lon_recordshop_shift = "I'm on shift at the old record shop, helping someone find a rare record",
            lon_apartment_mixdown = "I'm back at the apartment, finishing today's mix",
        },
        defaultDraft = "Is it daytime there? We've just had some rain in London.",
    },
}

-- ============================================================================
-- 关系档案：称呼 + 语气 + 关系风味句
-- flavorLines 作为多段回复的第三段候选（仅当本轮没有话题后缀时），不新增段数上限。
-- summaryThen/summaryNow 把作息短语套进「那会儿她…/现在她…」，措辞随关系而变。
-- ============================================================================

---@class RelationProfile
---@field id string
---@field label string
---@field greeting string 开场招呼的起手（可含 {city} {event} 占位）
---@field flavorLines string[] 关系风味句
---@field summaryThen string 「那会儿她…」的模板（含 {phrase}）
---@field summaryNow string 「现在她…」的模板（含 {phrase}）

---@type table<string, RelationProfile>
local RELATIONS = {
    stranger = {
        id = "stranger", label = "Someone new",
        greeting = "Hi, we haven't met yet. Here in {city}, {event}. Tell me what's on your mind.",
        flavorLines = {
            "We may have just met, but I'm listening.",
            "Sometimes it's easier to talk to someone new. Go ahead.",
        },
        summaryThen = "Then: {phrase}",
        summaryNow = "Now: {phrase}",
    },
    classmate = {
        id = "classmate", label = "School friend",
        greeting = "Hey, it's you. Here in {city}, {event}. It's been a while since we talked.",
        flavorLines = {
            "Do you remember our classroom with the west-facing windows?",
            "So much has happened since school. It's nice to talk it over with you.",
        },
        summaryThen = "Then: {phrase}",
        summaryNow = "Now: {phrase}",
    },
    ex_colleague = {
        id = "ex_colleague", label = "Former colleague",
        greeting = "It's been a while. Here in {city}, {event}. Still fitting our chats around work, I see.",
        flavorLines = {
            "Same old deadlines, just a different place now.",
            "Let's leave work there for now, before this turns into overtime.",
        },
        summaryThen = "Then: {phrase}",
        summaryNow = "Now: {phrase}",
    },
    old_friend = {
        id = "old_friend", label = "Old friend",
        greeting = "It's good to hear from you again. Here in {city}, {event}. Make yourself comfortable.",
        flavorLines = {
            "Even after all this time, I still think about those days.",
            "Take your time. I'm here when you feel like talking.",
        },
        summaryThen = "Then: {phrase}",
        summaryNow = "Now: {phrase}",
    },
}

ProfileService.CITY_ORDER = CITY_ORDER
ProfileService.RELATION_ORDER = RELATION_ORDER

---@param cityId string
---@return CityProfile?
function ProfileService.CityFor(cityId)
    return CITIES[cityId]
end

---@param relationId string
---@return RelationProfile?
function ProfileService.RelationFor(relationId)
    return RELATIONS[relationId]
end

--- 创建入口的合法性判定：id 不在矩阵里就必须当场失败，不能像 compose 那样
--- 悄悄回落成「洛杉矶 × 陌生网友」——那是给脏存档兜底的迁移行为，不是给用户
--- 的显式选择用的。用户选过什么，落盘就得是什么（M5）。
---@param cityId any
---@return boolean
function ProfileService.IsValidCityId(cityId)
    return type(cityId) == "string" and CITIES[cityId] ~= nil
end

---@param relationId any
---@return boolean
function ProfileService.IsValidRelationId(relationId)
    return type(relationId) == "string" and RELATIONS[relationId] ~= nil
end

--- 该城某事件档的叙事短语（与 EventService 当日 occurrence 口径一致；查不到返回 nil，
--- 由调用方回落 TimeState.phrase / occurrence.phrase，绝不返回别城的句子）。
---@param cityId string
---@param templateId string
---@return string?
function ProfileService.EventNarration(cityId, templateId)
    local city = CITIES[cityId]
    return city and city.events and city.events[templateId] or nil
end

-- ============================================================================
-- 档案对象：把 city + relation 合成一份可直接上屏的读视图
-- ============================================================================

---@class CompanionProfile
---@field cityId string
---@field relationId string
---@field cityLabel string
---@field relationLabel string
---@field identity string
---@field identityShort string
---@field seedText string
---@field isRandom boolean
---@field initialized boolean
---@field city CityProfile
---@field relation RelationProfile

---@type CompanionProfile
local profile_ = nil

---@param cityId string
---@param relationId string
---@param opts? { seedText?: string, isRandom?: boolean, initialized?: boolean }
---@return CompanionProfile
local function compose(cityId, relationId, opts)
    opts = opts or {}
    local city = CITIES[cityId] or CITIES.los_angeles
    local relation = RELATIONS[relationId] or RELATIONS.stranger
    ---@type CompanionProfile
    local p = {
        cityId = city.id,
        relationId = relation.id,
        cityLabel = city.label,
        relationLabel = relation.label,
        identity = city.identity,
        identityShort = city.identityShort,
        seedText = opts.seedText or (city.id .. "|" .. relation.id),
        isRandom = opts.isRandom == true,
        initialized = opts.initialized ~= false,
        city = city,
        relation = relation,
    }
    return p
end

--- 设定/切换当前档案。参数非法时逐项回落（未知城→洛杉矶、未知关系→陌生网友），
--- 绝不因为一个脏字段把整份档案作废。
---@param cityId string
---@param relationId string
---@param opts? { seedText?: string, isRandom?: boolean, initialized?: boolean }
---@return CompanionProfile
function ProfileService.Set(cityId, relationId, opts)
    profile_ = compose(cityId, relationId, opts)
    return profile_
end

---@param p CompanionProfile
---@return CompanionProfile
function ProfileService.SetActive(p)
    profile_ = p
    return profile_
end

---@return CompanionProfile
function ProfileService.Get()
    if not profile_ then
        profile_ = compose("los_angeles", "stranger", { initialized = true })
    end
    return profile_
end

function ProfileService.GetCityId()
    return ProfileService.Get().cityId
end

function ProfileService.GetRelationId()
    return ProfileService.Get().relationId
end

--- 信息卡/标题用的一行「关系 · 城市」。
---@return string
function ProfileService.ProfileLine()
    local p = ProfileService.Get()
    return p.relationLabel .. " · " .. p.cityLabel
end

--- 聊天顶栏副标题「<关系> × <城市> · 她按当地时间生活…」。
---@return string
function ProfileService.RelationCityLine()
    local p = ProfileService.Get()
    return p.relationLabel .. " × " .. p.cityLabel
        .. " · Her days follow local time. Messages wait while she's busy or asleep."
end

--- 消息时间行的角色标签：她的名字随档案（四城同一人，仍叫「若夕」；这里只切城市与「你」的归属）。
--- 城市戳取这条消息发送时那份（规格：历史时刻是事实），旧档没这字段才回落当前档案。
---@param isUser boolean
---@param cityId? string 该条消息落库时的城市 id
---@return string
function ProfileService.MessageSuffix(isUser, cityId)
    local p = ProfileService.Get()
    if isUser then
        local city = cityId and ProfileService.CityFor(cityId) or nil
        return " · " .. (city and city.label or p.cityLabel) .. " · You"
    end
    return " · Ruoxi"
end

-- ============================================================================
-- 开场白：城市事件 + 关系语气壳，二者都参与（不是换个城市名）
-- ============================================================================

---@param cityId string
---@param relationId string
---@param eventPhrase string 该城当前档的事件短语（来自 EventService occurrence 或 ProfileService 摘要）
---@return string
function ProfileService.OpeningLine(cityId, relationId, eventPhrase)
    local city = CITIES[cityId] or CITIES.los_angeles
    local relation = RELATIONS[relationId] or RELATIONS.stranger
    local filler = (eventPhrase and eventPhrase ~= "") and eventPhrase or "I have no special plans right now"
    return (relation.greeting:gsub("{city}", city.label):gsub("{event}", filler))
end

--- 首条默认草稿：每城一句（LA 保留任务书验收过的那句原文）。
---@param cityId? string 省略则取当前档案
---@return string
function ProfileService.DefaultDraft(cityId)
    local city = CITIES[cityId or ProfileService.GetCityId()] or CITIES.los_angeles
    return city.defaultDraft
end

--- 「离开期间」摘要里那两头的说法，措辞随关系而变。
---@param thenPhrase string
---@param nowPhrase string
---@return string, string
function ProfileService.AwayPhrases(thenPhrase, nowPhrase)
    local relation = ProfileService.Get().relation
    local thenOut = (relation.summaryThen:gsub("{phrase}", EnglishText.Translate(thenPhrase or "")))
    local nowOut = (relation.summaryNow:gsub("{phrase}", EnglishText.Translate(nowPhrase or "")))
    return thenOut, nowOut
end

--- 关系风味句（多段回复第三段候选）。按 seed 稳定取一条，同一句不重复到下一轮靠调用方变 turnIndex。
---@param seed string
---@return string?
function ProfileService.RelationFlavor(seed)
    local lines = ProfileService.Get().relation.flavorLines
    if not lines or #lines == 0 then
        return nil
    end
    local pick = (fnv1a(tostring(seed)) % #lines) + 1
    return lines[pick]
end

-- ============================================================================
-- 随机入口：定种、可复现、无 math.random
-- ============================================================================

--- 用创建时刻的权威 UTC 秒派生城市与关系。同一秒永远同一结果；结果由调用方落盘后即固定。
---@param creationUtcSec number
---@return { cityId: string, relationId: string, seedText: string }
function ProfileService.RandomPick(creationUtcSec)
    local sec = math.floor(creationUtcSec or 0)
    local seedText = RANDOM_SALT .. "|" .. tostring(sec)
    local h = fnv1a(seedText)
    local city = CITY_ORDER[(h % #CITY_ORDER) + 1]
    -- 第二路散列用不同后缀，避免关系与城市强绑成同一分布
    local relHash = fnv1a(seedText .. "#rel")
    local relation = RELATION_ORDER[(relHash % #RELATION_ORDER) + 1]
    return { cityId = city, relationId = relation, seedText = seedText .. "|" .. city .. "|" .. relation }
end

--- 应用随机入口：抽一次并直接落为当前档案（isRandom=true，seedText 供存档回写）。
---@param creationUtcSec number
---@return CompanionProfile
function ProfileService.ApplyRandom(creationUtcSec)
    local picked = ProfileService.RandomPick(creationUtcSec)
    return ProfileService.Set(picked.cityId, picked.relationId, {
        seedText = picked.seedText,
        isRandom = true,
        initialized = true,
    })
end

return ProfileService
