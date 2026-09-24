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
        id = "los_angeles", label = "洛杉矶",
        identity = "在洛杉矶办开放麦克风夜、做独立小册子的活动策划系毕业生",
        identityShort = "活动策划 · 独立出版",
        defaultRelation = "stranger",
        sceneVocab = { "la_cafe", "la_apartment", "la_studio" },
        events = {
            la_apartment_night_rest = "凌晨在公寓睡下，白天活动的便签还摊在桌上",
            la_apartment_morning_inbox = "清晨把活动邮件和便签归到一起",
            la_campus_workshop = "在学校准备一场小型工作坊",
            la_cafe_midday = "中午在咖啡馆吃午饭、顺看晚上的安排",
            la_studio_zine_layout = "在工作室对独立小册子的版面校样",
            la_commute_voice_notes = "在路上整理晚间活动的语音便签",
            la_cafe_open_mic = "在咖啡馆参与开放麦克风夜",
            la_apartment_wind_down = "回公寓整理今晚活动的复盘便签",
        },
        defaultDraft = "你那边是不是快傍晚了？今天的活动还顺利吗？",
    },
    shanghai = {
        id = "shanghai", label = "上海",
        identity = "在市区做城市生活专栏、晚上还会去旧书店值班的女编辑",
        identityShort = "专栏编辑 · 旧书店志愿",
        defaultRelation = "classmate",
        sceneVocab = { "sha_office", "sha_apartment", "sha_bookstore", "sha_cafe" },
        events = {
            sha_apartment_night_rest = "凌晨在公寓睡着，明天专栏的选题草稿还摊着",
            sha_apartment_morning_balcony = "清晨在阳台浇花、顺手把要交的字过一遍",
            sha_commute_rush = "在早高峰的地铁里，手机打字不太方便",
            sha_office_topic_meeting = "报社在开选题会，一上午没停",
            sha_cafe_midday = "中午在楼下咖啡馆边吃边看版面",
            sha_office_layout = "下午在版房盯这一期的排版",
            sha_commute_market = "绕到菜场给屋里添点吃的",
            sha_bookstore_evening = "在旧书店值夜班的台，安静得很",
            sha_apartment_reread = "回公寓把明天的稿子又读了一遍",
        },
        defaultDraft = "你那边到下午了吧？今天专栏的稿子顺不顺？",
    },
    chengdu = {
        id = "chengdu", label = "成都",
        identity = "画本地风物明信片、常在茶馆和夜市出没的自由插画师",
        identityShort = "自由插画 · 风物明信片",
        defaultRelation = "ex_colleague",
        sceneVocab = { "cdu_studio", "cdu_apartment", "cdu_nightmarket", "cdu_cafe" },
        events = {
            cdu_apartment_night_rest = "凌晨在公寓睡下，桌上一叠没干的明信片",
            cdu_apartment_morning_water = "早上给阳台的花浇了水，还没开工",
            cdu_studio_morning_ink = "上午在画室给一批明信片勾线上色",
            cdu_cafe_midday = "中午在茶馆吃碗面，顺便看看别人的稿",
            cdu_studio_color = "下午在工作台把今天这批颜色调完",
            cdu_commute_supplies = "出去买颜料和纸，一趟要走一会儿",
            cdu_nightmarket_supper = "在夜市摆摊收工，顺便吃了口夜宵",
            cdu_apartment_letters = "回公寓把寄出去的明信片写了地址",
        },
        defaultDraft = "你那边这个点吃了吗？我今天这批明信片还没画完。",
    },
    london = {
        id = "london", label = "伦敦",
        identity = "在学院读声音设计、周末在老唱片行当值的研究生",
        identityShort = "声音设计 · 唱片行当值",
        defaultRelation = "old_friend",
        sceneVocab = { "lon_studio", "lon_apartment", "lon_recordshop", "lon_campus" },
        events = {
            lon_apartment_night_rest = "凌晨在公寓睡了，混音工程还没导出",
            lon_apartment_morning_tea = "早上煮了茶，翻了翻今天的课表",
            lon_commute_early_train = "赶一早的火车，信号断断续续",
            lon_campus_lecture = "学院里有声音设计的讲座，走不开",
            lon_cafe_midday = "中午在咖啡馆吃三明治，赶下午的棚",
            lon_studio_field_recording = "录音棚里采集一段田野录音",
            lon_commute_dark = "天已经黑了，路上人多走得慢",
            lon_recordshop_shift = "在老唱片行当值，帮人找一张难找的唱片",
            lon_apartment_mixdown = "回公寓把今天的混音收到最后",
        },
        defaultDraft = "你那边是白天吧？伦敦刚下过一阵雨。",
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
        id = "stranger", label = "陌生网友",
        greeting = "你好，我们还没见过面。{city}这边{event}，你说，我听着。",
        flavorLines = {
            "虽然不认识，但你说的我会认真听完。",
            "陌生人的话反而好说，你说吧。",
        },
        summaryThen = "那会儿她{phrase}",
        summaryNow = "现在她{phrase}",
    },
    classmate = {
        id = "classmate", label = "高中同学",
        greeting = "是你啊。{city}这边{event}，好久没被人这么吵醒了。",
        flavorLines = {
            "还记不记得以前那间朝西的教室。",
            "毕业以后好多事，也就还能和你念叨。",
        },
        summaryThen = "那会儿她{phrase}",
        summaryNow = "这会儿她{phrase}",
    },
    ex_colleague = {
        id = "ex_colleague", label = "前同事",
        greeting = "好久不见。{city}这边{event}，还是老样子先干活再说话。",
        flavorLines = {
            "以前一起赶工的劲儿还在，就是换了地方。",
            "工作的事先说到这儿，别又聊成加班。",
        },
        summaryThen = "那会儿她正{phrase}",
        summaryNow = "现在她{phrase}",
    },
    old_friend = {
        id = "old_friend", label = "久未联系的朋友",
        greeting = "隔了这么久才又说话了。{city}这边{event}，你先坐。",
        flavorLines = {
            "这么久没联系，我也常想起从前。",
            "不急，你想说的时候我都在。",
        },
        summaryThen = "那会儿她{phrase}",
        summaryNow = "如今她{phrase}",
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
        .. " · 她按当地时间生活，在忙或在睡时你的消息会排队"
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
        return " · " .. (city and city.label or p.cityLabel) .. " · 你"
    end
    return " · 若夕"
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
    local filler = (eventPhrase and eventPhrase ~= "") and eventPhrase or "这会儿没什么特别的安排"
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
    local thenOut = (relation.summaryThen:gsub("{phrase}", thenPhrase or ""))
    local nowOut = (relation.summaryNow:gsub("{phrase}", nowPhrase or ""))
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
