-- ============================================================================
-- EventService.lua — 每日事件计划 + 按 UTC 查询事件实例（设计规格 §5.3）
-- 「先选事实，后写文案」在这里落地：每天用 城市 + 当地日期 + 固定种子 生成一份
-- 覆盖 00:00–24:00 的事件实例表（plan），查询只按 UTC 命中其中一个 occurrence。
-- 因此同一天同一城市任何时候得到同一批 occurrenceKey，重启读档后仍然复用存档里那份，
-- 不再按当前地点现挑模板 —— 地点只是模板的属性，不是选择器。
-- 事实是纯 Lua 规则的产物：没有随机数、没有运行时 LLM、没有外部服务。
-- 变体由日期定种（同一天永远同一变体），所以「有日期差异」不等于「会漂移」。
-- ============================================================================

local TimeState = require("TimeState")

local EventService = {}

-- 定种盐：换这一串就等于换一套日程叙事，是版本标记而不是随机源。
local SEED_SALT = "m1-events-v1"
-- 存档里保留的本地日期数：跨日补回要看昨天，4 天足够且不会无限增长。
local PLAN_DATE_CAP = 4

---@class EventTemplateVariant
---@field title string
---@field summary string
---@field emotion string
---@field phrase string

---@class EventTemplate
---@field id string 模板 id（= 回复文案的键，落进消息的 factId）
---@field sceneId string 固定原创静帧 id，不做地图
---@field variants EventTemplateVariant[] 日期变体，按下标定种选取

--- 一天的事件窗口不在这里声明：TimeState.SCHEDULE_BY_CITY[cityId] 逐行给出 from/to/place/event，
--- 模板只管「那件事叫什么、什么情绪、在哪一幕」。改钟点只需要动作息表那一个地方，
--- 不会出现「人说在上课、事写着校样」的两套真相。
---@type table<string, EventTemplate>
local EVENT_TEMPLATES = {
    la_apartment_night_rest = {
        id = "la_apartment_night_rest", sceneId = "la_apartment",
        variants = {
            {
                title = "凌晨的安静",
                summary = "凌晨在公寓睡着，白天那场活动的便签还摊在桌上",
                emotion = "安静、低沉",
                phrase = "我在公寓睡下了，桌上的便签还没收",
            },
            {
                title = "凌晨的复盘梦",
                summary = "凌晨在公寓休息，梦里还在排今天的流程",
                emotion = "疲惫、松弛",
                phrase = "刚睡下不久，梦里还在排今天的流程",
            },
        },
    },
    la_apartment_morning_inbox = {
        id = "la_apartment_morning_inbox", sceneId = "la_apartment",
        variants = {
            {
                title = "清晨的活动邮件",
                summary = "清晨整理了今天活动的邮件和便签",
                emotion = "安静、专注",
                phrase = "我在公寓把活动邮件和便签归到一起",
            },
            {
                title = "清晨的活动清单",
                summary = "清晨在公寓核对今天的活动清单并冲了咖啡",
                emotion = "清醒、有条理",
                phrase = "咖啡刚好冲完，我在核对今天的活动清单",
            },
        },
    },
    la_campus_workshop = {
        id = "la_campus_workshop", sceneId = "la_studio",
        variants = {
            {
                title = "学校工作坊的准备",
                summary = "在学校准备一场小型工作坊",
                emotion = "忙碌、期待",
                phrase = "学校工作坊快开始了，我在整理要用的材料",
            },
            {
                title = "学校的示例课",
                summary = "在学校的工作桌边过了一遍示例",
                emotion = "专注、略赶",
                phrase = "我在学校的工作桌边，把示例顺了一遍",
            },
        },
    },
    la_cafe_midday = {
        id = "la_cafe_midday", sceneId = "la_cafe",
        variants = {
            {
                title = "午间的咖啡馆间隙",
                summary = "中午在咖啡馆吃午饭，顺手看晚上的安排",
                emotion = "松弛、简短",
                phrase = "我在店里吃午饭，顺便看晚上的安排",
            },
            {
                title = "午间的活动电话",
                summary = "中午在咖啡馆接了一个关于今晚活动的电话",
                emotion = "有点被打断",
                phrase = "在店里吃两口就接了个电话，说今晚的场地",
            },
        },
    },
    la_studio_zine_layout = {
        id = "la_studio_zine_layout", sceneId = "la_studio",
        variants = {
            {
                title = "小册子版面校样",
                summary = "在工作室完成小册子版面校样",
                emotion = "专注、略紧张",
                phrase = "工作室里在对小册子的最后一版校样",
            },
            {
                title = "工作室的样张",
                summary = "在工作室挪版面，桌上堆着没裁的样张",
                emotion = "沉浸、有点赶",
                phrase = "我在工作室挪版面，桌上全是没裁的样张",
            },
        },
    },
    la_commute_voice_notes = {
        id = "la_commute_voice_notes", sceneId = "la_cafe",
        variants = {
            {
                title = "路上的语音便签",
                summary = "在路上整理晚间活动的语音便签",
                emotion = "短暂、轻快",
                phrase = "我在路上，刚把一个想法录进语音便签",
            },
            {
                title = "路上的等车时间",
                summary = "在等车，看晚上的活动安排",
                emotion = "零散、期待",
                phrase = "车还没到站，我在看晚上的活动安排",
            },
        },
    },
    la_cafe_open_mic = {
        id = "la_cafe_open_mic", sceneId = "la_cafe",
        variants = {
            {
                title = "咖啡馆的开放麦克风夜",
                summary = "在咖啡馆参与开放麦克风夜",
                emotion = "放松、投入",
                phrase = "咖啡馆这场开放麦克风还没收，人比昨天多一点",
            },
            {
                title = "咖啡馆的下一位上台",
                summary = "在咖啡馆等下一位上台，坐在靠窗的位置",
                emotion = "期待、安静",
                phrase = "店里正在轮到下一位上台，我坐在靠窗的位置",
            },
        },
    },
    la_apartment_wind_down = {
        id = "la_apartment_wind_down", sceneId = "la_apartment",
        variants = {
            {
                title = "回家后的活动复盘",
                summary = "回到公寓整理活动后的便签",
                emotion = "疲惫、踏实",
                phrase = "我回到公寓，把今晚活动的几张便签摊开了",
            },
            {
                title = "明天的清单",
                summary = "回到家把今天剩下的事情写进明天的清单",
                emotion = "收束、平静",
                phrase = "刚到家，正在把今天剩下的事情写进明天的清单",
            },
        },
    },

    -- ===== 上海（sha）：专栏编辑 + 旧书店志愿。sceneId 与作息表 place 同源 =====
    sha_apartment_night_rest = {
        id = "sha_apartment_night_rest", sceneId = "sha_apartment",
        variants = {
            { title = "凌晨的选题草稿", summary = "凌晨在公寓睡着，明天专栏的选题草稿还摊着", emotion = "安静、低沉", phrase = "我在公寓睡下了，明天的选题草稿还摊在桌上" },
            { title = "凌晨的稿子梦", summary = "凌晨休息，梦里还在理顺明天的稿", emotion = "疲惫、松弛", phrase = "刚睡下，梦里还在理顺明天的那篇稿" },
        },
    },
    sha_apartment_morning_balcony = {
        id = "sha_apartment_morning_balcony", sceneId = "sha_apartment",
        variants = {
            { title = "清晨的阳台", summary = "清晨在阳台浇花，顺手过一遍要交的字", emotion = "清醒、有条理", phrase = "我在阳台浇花，顺手把要交的字过了一遍" },
            { title = "清晨的头一遍读", summary = "咖啡温着，把稿子开头读了遍", emotion = "安静、专注", phrase = "咖啡温着，我在阳台把那篇稿的开头读了遍" },
        },
    },
    sha_commute_rush = {
        id = "sha_commute_rush", sceneId = "sha_commute",
        variants = {
            { title = "早高峰的地铁", summary = "在早高峰的地铁里通勤", emotion = "拥挤、简短", phrase = "在早高峰的地铁里，字打不长" },
            { title = "换乘路上", summary = "车厢很挤，等下车再看", emotion = "零散、期待", phrase = "车厢很挤，等下了车我再仔细看" },
        },
    },
    sha_office_topic_meeting = {
        id = "sha_office_topic_meeting", sceneId = "sha_office",
        variants = {
            { title = "选题会", summary = "报社在开选题会，一上午没停", emotion = "忙碌、专注", phrase = "报社在开选题会，一上午没停" },
            { title = "会中速记", summary = "在记会议要点，回得慢", emotion = "忙、略赶", phrase = "手在记会议要点，回得慢一点" },
        },
    },
    sha_cafe_midday = {
        id = "sha_cafe_midday", sceneId = "sha_cafe",
        variants = {
            { title = "午间版面", summary = "中午在楼下咖啡馆边吃边看版面", emotion = "松弛、简短", phrase = "中午在楼下咖啡馆，边吃边看版面" },
            { title = "午间小憩", summary = "扒完两口就要回版房", emotion = "有点赶", phrase = "扒完两口就要回版房" },
        },
    },
    sha_office_layout = {
        id = "sha_office_layout", sceneId = "sha_office",
        variants = {
            { title = "盯排版", summary = "下午在版房盯这一期的排版", emotion = "专注、略紧张", phrase = "下午在版房盯这一期的排版" },
            { title = "页码对齐", summary = "这版页码还差一点对齐", emotion = "沉浸、有点赶", phrase = "这一版的页码还差一点没对齐" },
        },
    },
    sha_commute_market = {
        id = "sha_commute_market", sceneId = "sha_commute",
        variants = {
            { title = "绕菜场", summary = "绕到菜场给屋里添点吃的", emotion = "生活气、零散", phrase = "绕到菜场给屋里添点吃的" },
            { title = "拎着菜", summary = "拎着菜，晚点再说", emotion = "短暂、轻快", phrase = "拎着菜呢，晚点再和你说" },
        },
    },
    sha_bookstore_evening = {
        id = "sha_bookstore_evening", sceneId = "sha_bookstore",
        variants = {
            { title = "旧书店夜班", summary = "在旧书店值夜班的台，安静得很", emotion = "安静、松弛", phrase = "我在旧书店值夜班的台，店里安静得很" },
            { title = "靠窗的书台", summary = "店里客人不多，能多说两句", emotion = "平和、有空", phrase = "店里客人不多，我能多和你说两句" },
        },
    },
    sha_apartment_reread = {
        id = "sha_apartment_reread", sceneId = "sha_apartment",
        variants = {
            { title = "灯下改稿", summary = "回公寓把明天的稿子又读了一遍", emotion = "踏实、收束", phrase = "我回公寓了，把明天的稿子又读了一遍" },
            { title = "最后几行", summary = "灯下改最后几行，快收了", emotion = "专注、平静", phrase = "灯下改最后几行，一会儿就收" },
        },
    },

    -- ===== 成都（cdu）：自由插画师 + 夜市。整体节奏更慢、夜间更长 =====
    cdu_apartment_night_rest = {
        id = "cdu_apartment_night_rest", sceneId = "cdu_apartment",
        variants = {
            { title = "凌晨的明信片", summary = "凌晨在公寓睡下，桌上一叠没干的明信片", emotion = "安静、低沉", phrase = "我在公寓睡下了，桌上一叠明信片还没干" },
            { title = "颜料味的梦", summary = "睡了，颜料味还没散", emotion = "疲惫、松弛", phrase = "刚睡下，屋里颜料味还没散" },
        },
    },
    cdu_apartment_morning_water = {
        id = "cdu_apartment_morning_water", sceneId = "cdu_apartment",
        variants = {
            { title = "清晨浇花", summary = "早上给阳台的花浇水，还没开工", emotion = "松弛、清醒", phrase = "早上给阳台的花浇了水，还没开工" },
            { title = "等会儿动笔", summary = "泡了盏茶，等会儿再动笔", emotion = "安静、有条理", phrase = "泡了盏茶，等会儿再动笔" },
        },
    },
    cdu_studio_morning_ink = {
        id = "cdu_studio_morning_ink", sceneId = "cdu_studio",
        variants = {
            { title = "勾线上色", summary = "上午在画室给一批明信片勾线上色", emotion = "专注、沉浸", phrase = "上午在画室给一批明信片勾线上色" },
            { title = "描屋檐", summary = "正描一条街的屋檐，别催", emotion = "沉浸、略赶", phrase = "正描着一条街的屋檐，先别催我" },
        },
    },
    cdu_cafe_midday = {
        id = "cdu_cafe_midday", sceneId = "cdu_cafe",
        variants = {
            { title = "茶馆午饭", summary = "中午在茶馆吃面，顺便看别人的稿", emotion = "松弛、简短", phrase = "中午在茶馆吃碗面，顺便看看别人的稿" },
            { title = "人多说短点", summary = "茶馆人多，我说短点", emotion = "热闹、零散", phrase = "茶馆人多，我先把话说短点" },
        },
    },
    cdu_studio_color = {
        id = "cdu_studio_color", sceneId = "cdu_studio",
        variants = {
            { title = "调颜色", summary = "下午在工作台把这批颜色调完", emotion = "专注、略紧张", phrase = "下午在工作台把今天这批颜色调完" },
            { title = "手有点忙", summary = "在调色，手有点忙", emotion = "沉浸、有点赶", phrase = "在调色呢，手有点忙" },
        },
    },
    cdu_commute_supplies = {
        id = "cdu_commute_supplies", sceneId = "cdu_commute",
        variants = {
            { title = "买颜料纸", summary = "出去买颜料和纸，一趟要走一会儿", emotion = "零散、轻快", phrase = "出去买颜料和纸，一趟要走一会儿" },
            { title = "在路上", summary = "在路上，到店里再聊", emotion = "短暂、期待", phrase = "在路上，等我到店里再和你说" },
        },
    },
    cdu_nightmarket_supper = {
        id = "cdu_nightmarket_supper", sceneId = "cdu_nightmarket",
        variants = {
            { title = "夜市收摊", summary = "在夜市摆摊收工，顺便吃了口夜宵", emotion = "松弛、踏实", phrase = "在夜市摆摊收工，顺便吃了口夜宵" },
            { title = "路边缓会儿", summary = "摊子刚收，坐在路边缓会儿", emotion = "疲惫、平静", phrase = "摊子刚收，我坐在路边缓一会儿" },
        },
    },
    cdu_apartment_letters = {
        id = "cdu_apartment_letters", sceneId = "cdu_apartment",
        variants = {
            { title = "写明信片地址", summary = "回公寓把寄出去的明信片写地址", emotion = "安静、专注", phrase = "回公寓了，在给寄出去的明信片写地址" },
            { title = "灯下收尾", summary = "灯下写地址，快写完了", emotion = "收束、平静", phrase = "灯下写地址，快写完了" },
        },
    },

    -- ===== 伦敦（lon）：声音设计研究生 + 唱片行当值。课在上午、棚在下午、店在夜里 =====
    lon_apartment_night_rest = {
        id = "lon_apartment_night_rest", sceneId = "lon_apartment",
        variants = {
            { title = "凌晨的混音", summary = "凌晨在公寓睡了，混音工程还没导出", emotion = "安静、低沉", phrase = "我在公寓睡下了，混音工程还没导出" },
            { title = "摊着的耳机", summary = "睡了，耳机还摊在桌上", emotion = "疲惫、松弛", phrase = "刚睡下，耳机还摊在桌上" },
        },
    },
    lon_apartment_morning_tea = {
        id = "lon_apartment_morning_tea", sceneId = "lon_apartment",
        variants = {
            { title = "晨间课表", summary = "早上煮了茶，翻了翻今天的课表", emotion = "清醒、有条理", phrase = "早上煮了茶，翻了翻今天的课表" },
            { title = "热茶与时序", summary = "茶还热，我在看时间安排", emotion = "安静、专注", phrase = "茶还热着，我在看今天的时间安排" },
        },
    },
    lon_commute_early_train = {
        id = "lon_commute_early_train", sceneId = "lon_commute",
        variants = {
            { title = "一早的火车", summary = "赶一早的火车，信号断断续续", emotion = "零散、略赶", phrase = "在赶一早的火车，信号断断续续" },
            { title = "车上没网", summary = "在车上，等下可能又没网", emotion = "短暂、期待", phrase = "在车上，等下可能又没网了" },
        },
    },
    lon_campus_lecture = {
        id = "lon_campus_lecture", sceneId = "lon_campus",
        variants = {
            { title = "声音设计讲座", summary = "学院里有声音设计的讲座，走不开", emotion = "专注、忙碌", phrase = "学院里有场声音设计的讲座，走不开" },
            { title = "讲座中", summary = "在听讲座，晚点回", emotion = "忙、略赶", phrase = "讲座进行中，我晚点回你" },
        },
    },
    lon_cafe_midday = {
        id = "lon_cafe_midday", sceneId = "lon_cafe",
        variants = {
            { title = "午间三明治", summary = "中午在咖啡馆吃三明治，赶下午的棚", emotion = "简短、有点赶", phrase = "中午在咖啡馆吃个三明治，赶下午的棚" },
            { title = "啃完就走", summary = "吃完就要去录音", emotion = "忙、零散", phrase = "啃完两口就要去录音" },
        },
    },
    lon_studio_field_recording = {
        id = "lon_studio_field_recording", sceneId = "lon_studio",
        variants = {
            { title = "田野录音", summary = "录音棚里采集一段田野录音", emotion = "专注、沉浸", phrase = "在录音棚里采集一段田野录音" },
            { title = "戴着监听", summary = "戴着监听，回得慢", emotion = "沉浸、略忙", phrase = "戴着监听呢，回得会慢一点" },
        },
    },
    lon_commute_dark = {
        id = "lon_commute_dark", sceneId = "lon_commute",
        variants = {
            { title = "天黑路上", summary = "天已经黑了，路上人多走得慢", emotion = "零散、疲惫", phrase = "天已经黑了，路上人多走得慢" },
            { title = "回家路上", summary = "在回家路上，风有点大", emotion = "短暂、低沉", phrase = "在回家路上，今天风有点大" },
        },
    },
    lon_recordshop_shift = {
        id = "lon_recordshop_shift", sceneId = "lon_recordshop",
        variants = {
            { title = "唱片行当值", summary = "在老唱片行当值，帮人找一张难找的唱片", emotion = "松弛、专注", phrase = "在老唱片行当值，正帮人找一张难找的唱片" },
            { title = "守着台", summary = "店里放着一张老唱片，我守着台", emotion = "安静、平和", phrase = "店里在放一张老唱片，我守着台" },
        },
    },
    lon_apartment_mixdown = {
        id = "lon_apartment_mixdown", sceneId = "lon_apartment",
        variants = {
            { title = "混音收尾", summary = "回公寓把今天的混音收到最后", emotion = "踏实、收束", phrase = "我回公寓了，把今天的混音收到最后" },
            { title = "灯下最后", summary = "灯下收尾，一会儿就弄完", emotion = "专注、平静", phrase = "灯下收尾，一会儿就弄完了" },
        },
    },
}

---@type table<string, string>
local PLACE_LABEL = {
    cafe = "咖啡馆",
    apartment = "公寓",
    campus = "学校",
    studio = "工作室",
    commute = "路上",
    office = "办公室",
    bookstore = "书店",
    nightmarket = "夜市",
    recordshop = "唱片行",
}

-- 当前城日程无命中时的兜底事件（消息缺事实才走到这里）：各城傍晚空闲档。
local FALLBACK_EVENT = {
    shanghai = "sha_bookstore_evening",
    chengdu = "cdu_nightmarket_supper",
    los_angeles = "la_cafe_open_mic",
    london = "lon_recordshop_shift",
}

---@class EventOccurrence
---@field occurrenceKey string 城市/当地日期/模板 id
---@field templateId string
---@field cityId string
---@field dateKey string 该实例所属的当地日期
---@field startUtc integer 事件开始的权威 UTC 秒
---@field endUtc integer 事件结束的权威 UTC 秒
---@field startClock string 当地开始钟点（展示用）
---@field endClock string 当地结束钟点（展示用）
---@field place string
---@field placeLabel string
---@field sceneId string
---@field title string
---@field summary string
---@field emotion string
---@field phrase string
---@field variantIndex integer 当天定中第几个变体（可复现，不是随机）

---@class EventPlan
---@field cityId string
---@field dateKey string
---@field seedText string 定种输入，写进日志便于核对可复现性
---@field generatedAtUtc integer 首次生成的 UTC 秒；读档后不变
---@field fromSave boolean 是否来自存档（true = 没有重新生成同日事件）
---@field occurrences EventOccurrence[]

---@type table<string, EventPlan>
local plans_ = {}

--- 计划表按「城市/日期」分键：换城市就是换一份日程，不共用同一批实例。
---@param cityId string
---@param dateKey string
---@return string
local function planKey(cityId, dateKey)
    return cityId .. "@" .. dateKey
end

local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h ~ s:byte(i)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    end
    return h
end

local function logInfo(msg)
    print("[EventService] " .. msg)
    log:Write(LOG_INFO, "[EventService] " .. msg)
end

local function logWarn(msg)
    print("[EventService] WARN: " .. msg)
    log:Write(LOG_WARNING, "[EventService] " .. msg)
end

---@class EventServiceInitOptions
---@field cityId? string
---@field onPlansChanged? fun() 新生成了一天的计划（main.lua 用它把计划落盘）

---@type fun()|nil
local onPlansChanged_ = nil

---@type string
local cityId_ = "los_angeles"

--- 进程级重建：清空计划缓存、设定默认城市、挂落盘回调。
--- 清空是必须的，否则开发自检的「重进」场景会读到上一次缓存，
--- 断言就成了「内存复用」而不是「存档复用」。
---@param opts? EventServiceInitOptions
function EventService.Init(opts)
    opts = opts or {}
    cityId_ = opts.cityId or cityId_
    onPlansChanged_ = opts.onPlansChanged
    plans_ = {}
end

---@return string
function EventService.GetCityId()
    return cityId_
end

--- 换当前城市但不清计划缓存：各城计划按 cityId@dateKey 分开存，
--- 换档案不丢弃已生成日期，旧城队列补回时仍能查到自己那天的事实。
---@param cityId string
function EventService.SetCity(cityId)
    cityId_ = cityId
end

--- 从存档接管已生成的计划。读回来的实例一律按存档内容使用，不重算，
--- 所以重启后 occurrenceKey 与生命周期与重启前完全一致。
---@param savedPlans EventPlan[]?
---@return integer taken 实际接管的日期数
function EventService.Restore(savedPlans)
    if type(savedPlans) ~= "table" then
        return 0
    end
    local taken = 0
    for i = 1, #savedPlans do
        local raw = savedPlans[i]
        if type(raw) == "table" and type(raw.dateKey) == "string" and type(raw.cityId) == "string" then
            ---@type EventOccurrence[]
            local occurrences = {}
            local rawOccs = raw.occurrences
            if type(rawOccs) == "table" then
                for j = 1, #rawOccs do
                    local occ = rawOccs[j]
                    -- 一条实例缺任一定位字段就整条丢掉：留着只会在查询时返回半截事实
                    if type(occ) == "table"
                        and type(occ.occurrenceKey) == "string"
                        and type(occ.templateId) == "string"
                        and type(occ.startUtc) == "number"
                        and type(occ.endUtc) == "number" then
                        occurrences[#occurrences + 1] = occ
                    end
                end
            end
            if #occurrences > 0 then
                plans_[planKey(raw.cityId, raw.dateKey)] = {
                    cityId = raw.cityId,
                    dateKey = raw.dateKey,
                    seedText = type(raw.seedText) == "string" and raw.seedText or "",
                    generatedAtUtc = type(raw.generatedAtUtc) == "number" and math.floor(raw.generatedAtUtc) or 0,
                    fromSave = true,
                    occurrences = occurrences,
                }
                taken = taken + 1
            end
        end
    end
    logInfo(string.format("接管存档事件计划 %d 天", taken))
    return taken
end

--- 当前缓存的计划表（落盘用）。按日期升序，只留最近 PLAN_DATE_CAP 天。
---@return EventPlan[]
function EventService.ExportPlans()
    ---@type EventPlan[]
    local list = {}
    for _, plan in pairs(plans_) do
        list[#list + 1] = plan
    end
    table.sort(list, function(a, b)
        if a.dateKey == b.dateKey then
            return a.cityId < b.cityId
        end
        return a.dateKey < b.dateKey
    end)
    while #list > PLAN_DATE_CAP do
        table.remove(list, 1)
    end
    return list
end

---@param cityId string
---@param dateKey string
---@return EventPlan?
function EventService.PeekPlan(cityId, dateKey)
    return plans_[planKey(cityId, dateKey)]
end

--- 丢掉某一天的缓存并按同一规则重建。正常路径不用它；
--- 开发自检要用它证明「同一天同一城市重算得到的还是那一批实例」，
--- 也就是可复现性而不是「一直复用内存」。
---@param cityId string
---@param dateKey string
---@return EventPlan
function EventService.Regenerate(cityId, dateKey)
    plans_[planKey(cityId, dateKey)] = nil
    return EventService.PlanFor(cityId, dateKey)
end

--- 取某城市某当地日期的事件计划。已缓存或已从存档读回就直接返回（不重算）；
--- 否则按 城市+日期+固定种子 生成一份，并通知调用方落盘。
---@param cityId string
---@param dateKey string
---@return EventPlan
function EventService.PlanFor(cityId, dateKey)
    local key = planKey(cityId, dateKey)
    local existing = plans_[key]
    if existing then
        return existing
    end

    ---@type EventOccurrence[]
    local occurrences = {}
    local rows = TimeState.ScheduleFor(cityId)
    for i = 1, #rows do
        local row = rows[i]
        local template = EVENT_TEMPLATES[row.event]
        if template then
            local seedText = cityId .. "|" .. dateKey .. "|" .. template.id .. "|" .. SEED_SALT
            local rolled = fnv1a(seedText)
            local variants = template.variants
            local variantIndex = (rolled % #variants) + 1
            local variant = variants[variantIndex]
            local endHour = row.to
            local endCityDate = dateKey
            if endHour >= 24 then
                endHour = endHour - 24
                endCityDate = TimeState.ShiftDateKey(dateKey, 1)
            end
            local startUtc = math.floor(TimeState.UtcAtLocal(cityId, dateKey, row.from))
            local endUtc = math.floor(TimeState.UtcAtLocal(cityId, endCityDate, endHour))
            ---@type EventOccurrence
            local occurrence = {
                occurrenceKey = string.format("%s/%s/%s", cityId, dateKey, template.id),
                templateId = template.id,
                cityId = cityId,
                dateKey = dateKey,
                startUtc = startUtc,
                endUtc = endUtc,
                startClock = string.format("%02d:00", row.from % 24),
                endClock = string.format("%02d:00", endHour % 24),
                place = row.place,
                placeLabel = PLACE_LABEL[row.place] or "外面",
                sceneId = template.sceneId,
                title = variant.title,
                summary = variant.summary,
                emotion = variant.emotion,
                phrase = variant.phrase,
                variantIndex = variantIndex,
            }
            occurrences[#occurrences + 1] = occurrence
        else
            -- 作息表挂了一个没有模板的事件 = 日程配置漏了一半，必须说出来而不是少给一个窗口
            logWarn(string.format("作息表 %02d:00–%02d:00 声明的事件模板缺失: %s（该窗口不生成实例）",
                row.from, row.to, tostring(row.event)))
        end
    end

    ---@type EventPlan
    local plan = {
        cityId = cityId,
        dateKey = dateKey,
        seedText = cityId .. "|" .. dateKey .. "|" .. SEED_SALT,
        generatedAtUtc = math.floor(TimeState.NowUtc()),
        fromSave = false,
        occurrences = occurrences,
    }
    plans_[key] = plan
    logInfo(string.format("生成 %s %s 的事件计划 %d 个事件（种子=%s）",
        cityId, dateKey, #occurrences, plan.seedText))
    if onPlansChanged_ then
        onPlansChanged_()
    end
    return plan
end

---@param occurrence EventOccurrence
---@param utcSec integer
---@return string
local function stateOf(occurrence, utcSec)
    if utcSec < occurrence.startUtc then
        return "upcoming"
    elseif utcSec >= occurrence.endUtc then
        return "ended"
    end
    return "ongoing"
end

---@class EventQuery
---@field occurrence EventOccurrence 命中的事件实例（含 eventState）
---@field eventState string ongoing|upcoming|ended
---@field plan EventPlan
---@field allStates table<string, string> templateId → 状态，给状态窗与自检用

--- 按权威 UTC 查当日事件计划，命中正在发生的那一个实例。
--- 计划按当地日期分键，所以跨日的排队补回只要给出对应 UTC 就能拿回同一实例。
---@param cityId string
---@param utcSec number
---@return EventQuery|nil
function EventService.QueryAt(cityId, utcSec)
    local t = math.floor(utcSec)
    local snap = TimeState.Snapshot(cityId, t)
    local plan = EventService.PlanFor(cityId, snap.dateKey)
    local occurrences = plan.occurrences
    local allStates = {}
    for i = 1, #occurrences do
        allStates[occurrences[i].templateId] = stateOf(occurrences[i], t)
    end
    for i = 1, #occurrences do
        local occ = occurrences[i]
        if t >= occ.startUtc and t < occ.endUtc then
            return {
                occurrence = occ,
                eventState = "ongoing",
                plan = plan,
                allStates = allStates,
            }
        end
    end
    -- 作息表是 00:00–24:00 连续覆盖的，走到这里说明计划与作息表错位（改日程时的真缺陷）。
    -- 退回最近一个已结束的实例，而不是伪造一个「未开始」——那正是规格禁止的说法。
    local nearest = nil
    local nearestState = "ended"
    for i = 1, #occurrences do
        local occ = occurrences[i]
        if occ.startUtc <= t and (not nearest or occ.startUtc > nearest.startUtc) then
            nearest = occ
        end
    end
    if not nearest then
        nearest = occurrences[#occurrences]
        nearestState = "upcoming"
    end
    if nearest then
        logWarn(string.format("UTC %d 未命中 %s 的任何事件窗口，回退到 %s(%s)",
            t, snap.dateKey, nearest.templateId, nearestState))
        return {
            occurrence = nearest,
            eventState = nearestState,
            plan = plan,
            allStates = allStates,
        }
    end
    return nil
end

---@class EventFact
---@field id string 模板 id（消息的 factId，回复文案的键）
---@field occurrenceKey string 当天该事件实例的稳定标识
---@field eventState string ongoing|upcoming|ended
---@field eventTitle string
---@field eventPhrase string
---@field eventSummary string
---@field eventEmotion string
---@field eventStartsAt string
---@field eventEndsAt string
---@field eventStartUtc integer
---@field eventEndUtc integer
---@field place string
---@field placeLabel string
---@field sceneId string
---@field availability string
---@field availabilityLabel string
---@field brief boolean 碎片时间档：回复要短
---@field cityLabel string
---@field clock string
---@field dateKey string
---@field weather string
---@field season string
---@field phrase string
---@field serverTime integer
---@field planFromSave boolean 这份事件事实出自存档里的计划还是当场生成
---@field queued boolean? 只有当下不可回复、事后补回时才为 true
---@field thenPhrase string? 消息送达时她所处档的原话（作息表事实）
---@field thenClock string? 消息送达时的当地钟点
---@field sentOccurrenceKey string? 送达时刻命中的事件实例
---@field sentEventState string? 交付时回头看送达那个实例的生命周期
---@field sentEventTitle string? 送达时那个事件的标题
---@field sentEventEndsAt string? 送达时那个事件的当地结束钟点
---@field gapSeconds integer? 从送达到交付经过了多少秒

--- 交付时刻 + 可选送达时刻 → 一份事件事实。
--- 传 sentUtcSec 即表示「这是排队之后的补回复」：送达那一刻命中的是另一个实例，
--- 它现在多半已经收了，这一点必须如实写进事实里，不能继续说成正在开始。
---@param cityId string
---@param utcSec number 交付（或当前）时刻的权威 UTC 秒
---@param sentUtcSec? number 同一条消息送达时刻的权威 UTC 秒
---@return EventFact
function EventService.FactFor(cityId, utcSec, sentUtcSec)
    local snap = TimeState.Snapshot(cityId, utcSec)
    local query = EventService.QueryAt(cityId, utcSec)
    local occ = query and query.occurrence or nil
    local template = occ and EVENT_TEMPLATES[occ.templateId] or nil
    ---@type EventFact
    local fact = {
        id = occ and occ.templateId or (template and template.id or snap.place),
        occurrenceKey = occ and occ.occurrenceKey or "",
        eventState = query and query.eventState or "ongoing",
        eventTitle = occ and occ.title or "",
        eventPhrase = occ and occ.phrase or snap.phrase,
        eventSummary = occ and occ.summary or "",
        eventEmotion = occ and occ.emotion or "",
        eventStartsAt = occ and occ.startClock or "",
        eventEndsAt = occ and occ.endClock or "",
        eventStartUtc = occ and occ.startUtc or snap.utcSec,
        eventEndUtc = occ and occ.endUtc or snap.utcSec,
        place = snap.place,
        placeLabel = PLACE_LABEL[snap.place] or "外面",
        sceneId = (occ and occ.sceneId) or snap.sceneId or "",
        availability = snap.availability,
        availabilityLabel = snap.availabilityLabel or "",
        brief = snap.brief == true,
        cityLabel = snap.cityLabel,
        clock = snap.clock,
        dateKey = snap.dateKey,
        weather = snap.weather,
        season = snap.season,
        phrase = snap.phrase,
        serverTime = snap.utcSec,
        planFromSave = query ~= nil and query.plan.fromSave == true,
    }

    if sentUtcSec and math.floor(sentUtcSec) < snap.utcSec then
        local sentSnap = TimeState.Snapshot(cityId, sentUtcSec)
        local sentQuery = EventService.QueryAt(cityId, sentUtcSec)
        fact.queued = not sentSnap.replyable
        fact.thenPhrase = sentSnap.phrase
        fact.thenClock = sentSnap.clock
        fact.gapSeconds = math.max(0, math.floor(snap.utcSec - sentSnap.utcSec))
        if sentQuery and sentQuery.occurrence then
            fact.sentOccurrenceKey = sentQuery.occurrence.occurrenceKey
            fact.sentEventTitle = sentQuery.occurrence.title
            fact.sentEventEndsAt = sentQuery.occurrence.endClock
            -- 送达那一刻它确实是正在发生；隔到交付时再查一次，状态可能已经收了。
            fact.sentEventState = stateOf(sentQuery.occurrence, snap.utcSec)
        end
    end

    logInfo(string.format("事件事实 key=%s state=%s scene=%s clock=%s fromSave=%s",
        fact.occurrenceKey, fact.eventState, fact.sceneId, fact.clock, tostring(fact.planFromSave)))
    if fact.queued then
        logInfo(string.format("排队补回 送达key=%s 送达态=%s 送达=%s 隔 %d 秒",
            tostring(fact.sentOccurrenceKey), tostring(fact.sentEventState),
            tostring(fact.thenClock), fact.gapSeconds or 0))
    end
    return fact
end

---@param templateId string
---@return EventTemplate?
function EventService.TemplateFor(templateId)
    return EVENT_TEMPLATES[templateId]
end

--- 全量事件标题（M2-B 事实词表守卫用：润色句里出现「不是今天那件事」的模板标题即回落）。
---@return string[]
function EventService.KnownEventTitles()
    local titles = {}
    for _, template in pairs(EVENT_TEMPLATES) do
        for _, variant in ipairs(template.variants or {}) do
            if variant.title then
                titles[#titles + 1] = variant.title
            end
        end
    end
    return titles
end

--- 当前正在发生的事件模板 id（消息缺事实时的兜底值）。
---@return string
function EventService.GetEventId()
    local query = EventService.QueryAt(cityId_, TimeState.NowUtc())
    if query then
        return query.occurrence.templateId
    end
    return FALLBACK_EVENT[cityId_] or FALLBACK_EVENT.los_angeles
end

return EventService
