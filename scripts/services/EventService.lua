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
local EnglishText = require("EnglishText")

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
---@field sceneId string 16 个原创 4:3 场景包之一（SceneService），不做地图
---@field variants EventTemplateVariant[] 日期变体，按下标定种选取
---@field traceKey? string 关键事件的当前生活痕迹键（SceneService.TRACES）；nil = 不改变痕迹

--- 一天的事件窗口不在这里声明：TimeState.SCHEDULE_BY_CITY[cityId] 逐行给出 from/to/place/event，
--- 模板只管「那件事叫什么、什么情绪、在哪一幕」。改钟点只需要动作息表那一个地方，
--- 不会出现「人说在上课、事写着校样」的两套真相。
---@type table<string, EventTemplate>
local EVENT_TEMPLATES = {
    la_apartment_night_rest = {
        id = "la_apartment_night_rest", sceneId = "la_apartment", traceKey = "note",
        variants = {
            {
                title = "Quiet after midnight", summary = "Asleep at home, with notes from the day's event still on the desk", emotion = "Quiet, subdued", phrase = "I'm asleep at home, with my notes still on the desk",
            },
            {
                title = "Dreaming of the schedule", summary = "Resting at home, still arranging the day's schedule in a dream", emotion = "Tired, relaxed", phrase = "I've just fallen asleep, still dreaming about the day's schedule",
            },
        },
    },
    la_apartment_morning_inbox = {
        id = "la_apartment_morning_inbox", sceneId = "la_apartment", traceKey = "note",
        variants = {
            {
                title = "Morning event emails", summary = "Sorting the day's event emails and notes", emotion = "Quiet, focused", phrase = "I'm sorting the event emails and notes at home",
            },
            {
                title = "The morning checklist", summary = "Checking the day's event list and making coffee at home", emotion = "Alert, organised", phrase = "The coffee's ready, and I'm checking today's event list",
            },
        },
    },
    la_campus_workshop = {
        id = "la_campus_workshop", sceneId = "la_studio", traceKey = "proofs",
        variants = {
            {
                title = "Getting the workshop ready", summary = "Preparing a small workshop in the studio", emotion = "Busy, looking forward to it", phrase = "The workshop starts soon, and I'm laying out the materials",
            },
            {
                title = "Running through the examples", summary = "Reviewing the examples at the studio's long table", emotion = "Focused, a little rushed", phrase = "I'm running through the examples at the long table in the studio",
            },
        },
    },
    la_cafe_midday = {
        id = "la_cafe_midday", sceneId = "la_cafe", traceKey = "coffee",
        variants = {
            {
                title = "A cafe lunch break", summary = "Having lunch at the cafe and checking tonight's plans", emotion = "Relaxed, brief", phrase = "I'm having lunch at the cafe and checking tonight's plans",
            },
            {
                title = "A lunchtime call", summary = "Taking a call at the cafe about tonight's event", emotion = "A little interrupted", phrase = "A call about tonight's venue interrupted my lunch at the cafe",
            },
        },
    },
    la_studio_zine_layout = {
        id = "la_studio_zine_layout", sceneId = "la_studio", traceKey = "proofs",
        variants = {
            {
                title = "Zine proofs", summary = "Finishing the zine layout proofs in the studio", emotion = "Focused, a little tense", phrase = "I'm checking the final zine proofs in the studio",
            },
            {
                title = "Prints on the studio table", summary = "Adjusting the layout, with uncut proofs piled on the table", emotion = "Absorbed, a little rushed", phrase = "I'm adjusting the layout in the studio, with uncut proofs all over the table",
            },
        },
    },
    la_commute_voice_notes = {
        id = "la_commute_voice_notes", sceneId = "la_commute",
        variants = {
            {
                title = "Voice notes on the way", summary = "Organising voice notes for the evening event while travelling", emotion = "Brief, upbeat", phrase = "I'm on my way, and I've just recorded an idea as a voice note",
            },
            {
                title = "Waiting for the bus", summary = "Waiting for the bus and checking tonight's event plans", emotion = "Distracted, looking forward to it", phrase = "The bus isn't here yet, so I'm checking tonight's plans",
            },
        },
    },
    la_cafe_open_mic = {
        id = "la_cafe_open_mic", sceneId = "la_cafe", traceKey = "coffee",
        variants = {
            {
                title = "Open mic at the cafe", summary = "Taking part in an open mic night at the cafe", emotion = "Relaxed, engaged", phrase = "The cafe's open mic is still going, with a few more people than yesterday",
            },
            {
                title = "Waiting for the next performer", summary = "Waiting by the cafe window for the next performer", emotion = "Quiet, looking forward to it", phrase = "I'm sitting by the window as the next performer takes the stage",
            },
        },
    },
    la_apartment_wind_down = {
        id = "la_apartment_wind_down", sceneId = "la_apartment", traceKey = "note",
        variants = {
            {
                title = "Notes after the event", summary = "Sorting event notes back at the apartment", emotion = "Tired, settled", phrase = "I'm back at the apartment, spreading out tonight's event notes",
            },
            {
                title = "Tomorrow's list", summary = "Adding today's unfinished tasks to tomorrow's list at home", emotion = "Winding down, calm", phrase = "I've just got home and I'm adding today's unfinished tasks to tomorrow's list",
            },
        },
    },

    -- ===== 上海（sha）：专栏编辑 + 旧书店志愿。sceneId 与作息表 place 同源 =====
    sha_apartment_night_rest = {
        id = "sha_apartment_night_rest", sceneId = "sha_apartment", traceKey = "note",
        variants = {
            { title = "An article draft after midnight", summary = "Asleep at home, with tomorrow's column draft still out", emotion = "Quiet, subdued", phrase = "I'm asleep at home, with tomorrow's column draft still on the desk" },
            { title = "Dreaming of tomorrow's article", summary = "Resting, still working through tomorrow's article in a dream", emotion = "Tired, relaxed", phrase = "I've just fallen asleep, still dreaming about tomorrow's article" },
        },
    },
    sha_apartment_morning_balcony = {
        id = "sha_apartment_morning_balcony", sceneId = "sha_apartment",
        variants = {
            { title = "Morning on the balcony", summary = "Watering the balcony plants and reviewing the writing due today", emotion = "Alert, organised", phrase = "I'm watering the balcony plants and reviewing the writing I need to send" },
            { title = "The first morning read", summary = "Rereading the opening of the article while the coffee stays warm", emotion = "Quiet, focused", phrase = "I'm reading the article's opening on the balcony, with warm coffee beside me" },
        },
    },
    sha_commute_rush = {
        id = "sha_commute_rush", sceneId = "sha_commute", traceKey = "coffee",
        variants = {
            { title = "Rush hour on the metro", summary = "Commuting on the crowded morning metro", emotion = "Crowded, brief", phrase = "I'm on the rush-hour metro, so I can't type much" },
            { title = "Changing trains", summary = "Waiting to get off a crowded train before reading properly", emotion = "Distracted, looking forward to it", phrase = "The carriage is packed; I'll read properly once I'm off" },
        },
    },
    sha_office_topic_meeting = {
        id = "sha_office_topic_meeting", sceneId = "sha_office", traceKey = "proofs",
        variants = {
            { title = "The editorial meeting", summary = "In a newsroom planning meeting all morning", emotion = "Busy, focused", phrase = "I'm in the newsroom's editorial meeting; it's been going all morning" },
            { title = "Meeting notes", summary = "Taking meeting notes and replying slowly", emotion = "Busy, a little rushed", phrase = "I'm taking meeting notes, so my replies are a little slow" },
        },
    },
    sha_cafe_midday = {
        id = "sha_cafe_midday", sceneId = "sha_office", traceKey = "coffee",
        variants = {
            { title = "Layouts over lunch", summary = "Eating lunch while checking layouts in the newsroom", emotion = "Relaxed, brief", phrase = "I'm eating lunch in the newsroom while checking the layouts" },
            { title = "A quick lunch break", summary = "Taking a few bites before returning to the layouts", emotion = "A little rushed", phrase = "I've only got time for a few bites before checking the layouts again" },
        },
    },
    sha_office_layout = {
        id = "sha_office_layout", sceneId = "sha_office", traceKey = "proofs",
        variants = {
            { title = "Watching the layout", summary = "Checking this issue's layout in the newsroom", emotion = "Focused, a little tense", phrase = "I'm checking this issue's layout in the newsroom" },
            { title = "Aligning page numbers", summary = "Adjusting page numbers that are slightly out of line", emotion = "Absorbed, a little rushed", phrase = "The page numbers on this layout still need a little aligning" },
        },
    },
    sha_commute_market = {
        id = "sha_commute_market", sceneId = "sha_commute", traceKey = "grocery",
        variants = {
            { title = "A detour to the market", summary = "Picking up groceries for home at the market", emotion = "Everyday, distracted", phrase = "I'm stopping at the market to pick up some food for home" },
            { title = "Carrying groceries", summary = "Carrying groceries and leaving the conversation for later", emotion = "Brief, upbeat", phrase = "My hands are full of groceries; I'll talk to you later" },
        },
    },
    sha_bookstore_evening = {
        id = "sha_bookstore_evening", sceneId = "sha_bookstore", traceKey = "oldbook",
        variants = {
            { title = "The bookshop's evening shift", summary = "Working the counter at the quiet second-hand bookshop", emotion = "Quiet, relaxed", phrase = "I'm on the evening shift at the second-hand bookshop; it's very quiet" },
            { title = "The counter by the window", summary = "A quiet shop with room for a longer conversation", emotion = "Calm, available", phrase = "There aren't many customers, so I can talk a little longer" },
        },
    },
    sha_apartment_reread = {
        id = "sha_apartment_reread", sceneId = "sha_apartment", traceKey = "note",
        variants = {
            { title = "Editing under the lamp", summary = "Rereading tomorrow's article back at the apartment", emotion = "Settled, winding down", phrase = "I'm back at the apartment and I've reread tomorrow's article" },
            { title = "The last few lines", summary = "Editing the last few lines under the lamp before finishing", emotion = "Focused, calm", phrase = "I'm editing the last few lines under the lamp; nearly done" },
        },
    },

    -- ===== 成都（cdu）：自由插画师 + 夜市。整体节奏更慢、夜间更长 =====
    cdu_apartment_night_rest = {
        id = "cdu_apartment_night_rest", sceneId = "cdu_apartment", traceKey = "postcard",
        variants = {
            { title = "Postcards after midnight", summary = "Asleep at home, with a stack of wet postcards on the desk", emotion = "Quiet, subdued", phrase = "I'm asleep at home, with a stack of postcards still drying on the desk" },
            { title = "Dreams smelling of paint", summary = "Asleep, with the smell of paint still in the room", emotion = "Tired, relaxed", phrase = "I've just fallen asleep, and the room still smells of paint" },
        },
    },
    cdu_apartment_morning_water = {
        id = "cdu_apartment_morning_water", sceneId = "cdu_apartment",
        variants = {
            { title = "Watering plants in the morning", summary = "Watering the balcony plants before starting work", emotion = "Relaxed, alert", phrase = "I've watered the balcony plants, but haven't started work yet" },
            { title = "A little tea before drawing", summary = "Making tea and waiting a little before drawing", emotion = "Quiet, organised", phrase = "I've made some tea; I'll start drawing in a little while" },
        },
    },
    cdu_studio_morning_ink = {
        id = "cdu_studio_morning_ink", sceneId = "cdu_studio", traceKey = "postcard",
        variants = {
            { title = "Outlines and colours", summary = "Drawing outlines and colouring a batch of postcards in the studio", emotion = "Focused, absorbed", phrase = "I'm outlining and colouring a batch of postcards in the studio" },
            { title = "Drawing the rooftops", summary = "Drawing the rooftops along a street without rushing", emotion = "Absorbed, a little rushed", phrase = "I'm drawing a street's rooftops; give me a moment" },
        },
    },
    cdu_cafe_midday = {
        id = "cdu_cafe_midday", sceneId = "cdu_cafe", traceKey = "gaiwan",
        variants = {
            { title = "Lunch at the teahouse", summary = "Eating noodles at the teahouse and looking at others' sketches", emotion = "Relaxed, brief", phrase = "I'm having noodles at the teahouse and looking at other people's sketches" },
            { title = "A crowded teahouse", summary = "Keeping the conversation brief in a busy teahouse", emotion = "Lively, distracted", phrase = "The teahouse is crowded, so I'll keep this short" },
        },
    },
    cdu_studio_color = {
        id = "cdu_studio_color", sceneId = "cdu_studio", traceKey = "postcard",
        variants = {
            { title = "Mixing colours", summary = "Finishing the batch's colours at the workbench", emotion = "Focused, a little tense", phrase = "I'm finishing today's colours at the workbench" },
            { title = "Hands full of paint", summary = "Mixing colours with busy hands", emotion = "Absorbed, a little rushed", phrase = "I'm mixing colours, so my hands are a little busy" },
        },
    },
    cdu_commute_supplies = {
        id = "cdu_commute_supplies", sceneId = "cdu_commute",
        variants = {
            { title = "Buying paint and paper", summary = "Going out for paint and paper; the trip takes a while", emotion = "Distracted, upbeat", phrase = "I'm out buying paint and paper; it's a bit of a trip" },
            { title = "On the way", summary = "Travelling and waiting until arrival to chat", emotion = "Brief, looking forward to it", phrase = "I'm on my way; I'll talk to you when I reach the shop" },
        },
    },
    cdu_nightmarket_supper = {
        id = "cdu_nightmarket_supper", sceneId = "cdu_commute", traceKey = "postcard",
        variants = {
            { title = "Packing up at the night market", summary = "Packing up the night-market stall and having a late snack", emotion = "Relaxed, settled", phrase = "I've packed up my night-market stall and had a late snack" },
            { title = "A pause by the roadside", summary = "Sitting by the road for a moment after packing up", emotion = "Tired, calm", phrase = "I've just packed up the stall and I'm sitting by the road for a moment" },
        },
    },
    cdu_apartment_letters = {
        id = "cdu_apartment_letters", sceneId = "cdu_apartment", traceKey = "postcard",
        variants = {
            { title = "Addressing postcards", summary = "Writing addresses on outgoing postcards back at the apartment", emotion = "Quiet, focused", phrase = "I'm back at the apartment, addressing the postcards I'm sending out" },
            { title = "Finishing under the lamp", summary = "Writing the final addresses under the lamp", emotion = "Winding down, calm", phrase = "I'm writing addresses under the lamp; almost finished" },
        },
    },

    -- ===== 伦敦（lon）：声音设计研究生 + 唱片行当值。课在上午、棚在下午、店在夜里 =====
    lon_apartment_night_rest = {
        id = "lon_apartment_night_rest", sceneId = "lon_apartment", traceKey = "note",
        variants = {
            { title = "A mix after midnight", summary = "Asleep at home, with the mix not yet exported", emotion = "Quiet, subdued", phrase = "I'm asleep at home, and the mix hasn't been exported yet" },
            { title = "Headphones on the desk", summary = "Asleep, with headphones still on the desk", emotion = "Tired, relaxed", phrase = "I've just fallen asleep, with my headphones still on the desk" },
        },
    },
    lon_apartment_morning_tea = {
        id = "lon_apartment_morning_tea", sceneId = "lon_apartment",
        variants = {
            { title = "The morning timetable", summary = "Making tea and checking today's class timetable", emotion = "Alert, organised", phrase = "I've made tea and checked today's class timetable" },
            { title = "Hot tea and plans", summary = "Checking the schedule while the tea is still hot", emotion = "Quiet, focused", phrase = "My tea's still hot, and I'm checking today's schedule" },
        },
    },
    lon_commute_early_train = {
        id = "lon_commute_early_train", sceneId = "lon_commute", traceKey = "umbrella",
        variants = {
            { title = "An early train", summary = "Catching an early train with patchy reception", emotion = "Distracted, a little rushed", phrase = "I'm catching an early train, and the signal keeps dropping" },
            { title = "No signal on the train", summary = "Travelling with another possible loss of reception", emotion = "Brief, looking forward to it", phrase = "I'm on the train; I might lose the signal again" },
        },
    },
    lon_campus_lecture = {
        id = "lon_campus_lecture", sceneId = "lon_studio", traceKey = "note",
        variants = {
            { title = "A workshop in the college studio", summary = "Busy at a sound-design workshop in the college studio", emotion = "Focused, busy", phrase = "I'm busy in the college recording studio and can't step away" },
            { title = "During the workshop", summary = "Waiting until the workshop is over to reply", emotion = "Busy, a little rushed", phrase = "The workshop's still going; I'll reply a little later" },
        },
    },
    lon_cafe_midday = {
        id = "lon_cafe_midday", sceneId = "lon_commute", traceKey = "coffee",
        variants = {
            { title = "A lunchtime sandwich", summary = "Buying a sandwich on the street before the afternoon studio session", emotion = "Brief, a little rushed", phrase = "I'm eating a sandwich on the street before heading to the studio" },
            { title = "A bite before recording", summary = "Eating quickly before going to record", emotion = "Busy, distracted", phrase = "I've got time for a couple of bites before recording" },
        },
    },
    lon_studio_field_recording = {
        id = "lon_studio_field_recording", sceneId = "lon_studio", traceKey = "vinyl",
        variants = {
            { title = "Field recording", summary = "Collecting a field recording in the studio", emotion = "Focused, absorbed", phrase = "I'm collecting a field recording in the studio" },
            { title = "Listening on headphones", summary = "Monitoring audio and replying slowly", emotion = "Absorbed, busy", phrase = "I'm monitoring on headphones, so my replies will be a little slow" },
        },
    },
    lon_commute_dark = {
        id = "lon_commute_dark", sceneId = "lon_commute", traceKey = "umbrella",
        variants = {
            { title = "Travelling after dark", summary = "Walking slowly through the crowds after dark", emotion = "Distracted, tired", phrase = "It's dark already, and the crowds are slowing me down" },
            { title = "On the way home", summary = "Travelling home in a strong breeze", emotion = "Brief, subdued", phrase = "I'm on my way home; it's a little windy today" },
        },
    },
    lon_recordshop_shift = {
        id = "lon_recordshop_shift", sceneId = "lon_recordshop", traceKey = "vinyl",
        variants = {
            { title = "A shift at the record shop", summary = "Helping find a hard-to-find record at the old record shop", emotion = "Relaxed, focused", phrase = "I'm on shift at the old record shop, helping someone find a rare record" },
            { title = "At the counter", summary = "Working the counter while an old record plays", emotion = "Quiet, calm", phrase = "An old record's playing in the shop, and I'm at the counter" },
        },
    },
    lon_apartment_mixdown = {
        id = "lon_apartment_mixdown", sceneId = "lon_apartment", traceKey = "note",
        variants = {
            { title = "Finishing the mix", summary = "Finishing today's mix back at the apartment", emotion = "Settled, winding down", phrase = "I'm back at the apartment, finishing today's mix" },
            { title = "The last work under the lamp", summary = "Finishing under the lamp, nearly done", emotion = "Focused, calm", phrase = "I'm finishing up under the lamp; almost done" },
        },
    },
}

---@type table<string, string>
local PLACE_LABEL = {
    cafe = "Cafe",
    apartment = "Apartment",
    campus = "College",
    studio = "Studio",
    commute = "On the way",
    office = "Office",
    bookstore = "Bookshop",
    nightmarket = "Night market",
    recordshop = "Record shop",
}

-- 当前城日程无命中时的兜底事件（消息缺事实才走到这里）：各城傍晚空闲档。
local FALLBACK_EVENT = {
    shanghai = "sha_bookstore_evening",
    chengdu = "cdu_nightmarket_supper",
    los_angeles = "la_cafe_open_mic",
    london = "lon_recordshop_shift",
}

-- M7 事件四件套。这里只放每城一条「关键事件」：普通作息仍是日程，
-- 不会因为带了 traceKey 就挤进关键叙事。卡片字段同时给状态窗线索、
-- 本地模板回复和验收文档使用，避免三处再各写一套事实。
---@class M7EventCard
---@field id string
---@field templateId string
---@field clue string 用户回复前可见的线索
---@field questionHints string[] 可自然发问的词；不匹配就只回已知事实
---@field answer string Lua 固定事实，允许直接说出的回答
---@field forbidden string 禁止编造的边界说明
---@field traceLifecycle string 事后痕迹何时出现、何时被替换
---@type table<string, M7EventCard>
local M7_CARDS = {
    los_angeles = {
        id = "m7-la-open-mic", templateId = "la_cafe_open_mic",
        clue = "The coffee by the window has gone cold. Someone is checking the mic.",
        questionHints = { "开放麦", "试音", "上台", "咖啡馆", "几点" , "open mic", "sound check", "stage", "cafe", "what time" },
        answer = "It's open mic night at the cafe. I'm by the window, waiting for the next performer.",
        forbidden = "不编造表演者、曲目、她是否上台或活动结果。",
        traceLifecycle = "活动结束后，靠窗的半杯咖啡留在咖啡馆场景；下一次关键事件结束后替换。",
    },
    shanghai = {
        id = "m7-sha-bookstore", templateId = "sha_bookstore_evening",
        clue = "Two returned books sit beside the counter. The shop is quieter than usual.",
        questionHints = { "旧书", "书店", "值班", "柜台", "哪本" , "old book", "bookshop", "shift", "counter", "which book" },
        answer = "I'm on the bookshop's evening shift. I've just stacked two returned books by the counter.",
        forbidden = "不编造书名、顾客身份、成交或她私下读完了什么。",
        traceLifecycle = "值班结束后，两本旧书留在书店场景；下一次关键事件结束后替换。",
    },
    chengdu = {
        id = "m7-cdu-nightmarket", templateId = "cdu_nightmarket_supper",
        clue = "The stall is packed away. One postcard is still drying at the edge of the table.",
        questionHints = { "夜市", "明信片", "摊", "收摊", "卖" , "night market", "postcard", "stall", "packing up", "sell" },
        answer = "I've just packed up at the night market and left the last damp postcard at the edge of the table.",
        forbidden = "不编造售卖数量、收入、买家或她答应寄给谁。",
        traceLifecycle = "收摊后，未干的明信片留在夜市街口场景；下一次关键事件结束后替换。",
    },
    london = {
        id = "m7-lon-recordshop", templateId = "lon_recordshop_shift",
        clue = "A record is still beside the listening station. The counter light is on.",
        questionHints = { "唱片", "试听", "唱片行", "找", "柜台" , "record", "listen", "record shop", "find", "counter" },
        answer = "I'm on shift at the old record shop tonight, helping someone find a rare record.",
        forbidden = "不编造唱片名称、顾客身份、是否找到或她的收藏。",
        traceLifecycle = "当值结束后，试听机旁的唱片留在唱片行场景；下一次关键事件结束后替换。",
    },
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
---@field traceKey? string 关键事件的当前生活痕迹键（随实例落盘，重进读回同一绑定）
---@field isM7KeyEvent boolean 是否是 M7 每城唯一的关键事件
---@field m7CardId? string 关键事件四件套卡 id
---@field clue? string 用户回复前可见的线索
---@field questionHints? string[] 可自然发问的词
---@field answer? string Lua 固定回答
---@field forbidden? string 回复禁区说明
---@field traceLifecycle? string 痕迹生命周期说明
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
                        -- v6 及以前的计划没有 M7 卡片字段；不重算、不改变 occurrenceKey，
                        -- 只按城市与既存 templateId 补齐当前版本的内容契约。
                        for _, field in ipairs({"title", "summary", "emotion", "phrase"}) do
                            occ[field] = EnglishText.Translate(occ[field])
                        end
                        local card = M7_CARDS[raw.cityId]
                        if card and card.templateId == occ.templateId then
                            occ.isM7KeyEvent = true
                            occ.m7CardId = card.id
                            occ.clue = card.clue
                            occ.questionHints = card.questionHints
                            occ.answer = card.answer
                            occ.forbidden = card.forbidden
                            occ.traceLifecycle = card.traceLifecycle
                        else
                            occ.isM7KeyEvent = false
                        end
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
            local card = M7_CARDS[cityId]
            local isM7KeyEvent = card ~= nil and card.templateId == template.id
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
                placeLabel = PLACE_LABEL[row.place] or "Out and about",
                sceneId = template.sceneId,
                title = variant.title,
                summary = variant.summary,
                emotion = variant.emotion,
                phrase = variant.phrase,
                traceKey = template.traceKey,
                isM7KeyEvent = isM7KeyEvent,
                m7CardId = isM7KeyEvent and card.id or nil,
                clue = isM7KeyEvent and card.clue or nil,
                questionHints = isM7KeyEvent and card.questionHints or nil,
                answer = isM7KeyEvent and card.answer or nil,
                forbidden = isM7KeyEvent and card.forbidden or nil,
                traceLifecycle = isM7KeyEvent and card.traceLifecycle or nil,
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

--- 返回每城一张 M7 事件卡。只读约定：调用者不得改写；实例化时会复制必要字段进计划。
---@return table<string, M7EventCard>
function EventService.M7Cards()
    return M7_CARDS
end

--- 当地当天最近一个已结束的 M7 关键事件。跨日不重新寻找旧事件：它的痕迹已在
--- LifeService 槽里持久化，直到本地日期里的下一张关键卡结束才被替换。
---@param cityId string
---@param utcSec number
---@return EventOccurrence|nil
function EventService.LatestCompletedKeyEvent(cityId, utcSec)
    local snap = TimeState.Snapshot(cityId, utcSec)
    local plan = EventService.PlanFor(cityId, snap.dateKey)
    local best = nil
    local t = math.floor(utcSec)
    for i = 1, #plan.occurrences do
        local occurrence = plan.occurrences[i]
        if occurrence.isM7KeyEvent == true and occurrence.endUtc <= t
            and (not best or occurrence.endUtc > best.endUtc) then
            best = occurrence
        end
    end
    return best
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
---@field traceKey? string 该事件绑定的生活痕迹键（nil = 非关键事件，不改变当前痕迹）
---@field isM7KeyEvent boolean 是否是 M7 四件套关键事件
---@field m7CardId? string
---@field clue? string
---@field questionHints? string[]
---@field m7Answer? string
---@field m7Forbidden? string
---@field traceLifecycle? string
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
        placeLabel = PLACE_LABEL[snap.place] or "Out and about",
        sceneId = (occ and occ.sceneId) or snap.sceneId or "",
        traceKey = occ and occ.traceKey or nil,
        isM7KeyEvent = occ and occ.isM7KeyEvent == true or false,
        m7CardId = occ and occ.m7CardId or nil,
        clue = occ and occ.clue or nil,
        questionHints = occ and occ.questionHints or nil,
        m7Answer = occ and occ.answer or nil,
        m7Forbidden = occ and occ.forbidden or nil,
        traceLifecycle = occ and occ.traceLifecycle or nil,
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
