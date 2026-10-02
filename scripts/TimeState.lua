-- ============================================================================
-- 真实时间与可用性（设计规格 §5.1 / §5.2）
-- 权威时间源 = common.get_server_time()（UTC 秒，用户改系统时间无效）
-- 引擎无 IANA 时区库，四城各一张带生效区间的偏移表。
-- ============================================================================

local TimeState = {}

-- days from civil / civil from days：Howard Hinnant 算法。
-- 不用 os.time{...} 造时间戳，因为标准 Lua 的 os.time 按**运行设备本地时区**解释字段，
-- 而这里要的正是"某个 UTC 时刻"——在开发者自己机器上看不出来，到别的时区就错。
local function daysFromCivil(y, m, d)
    y = y - ((m <= 2) and 1 or 0)
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = m + ((m > 2) and -3 or 9)
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- 0=Sunday
local function weekdayFromDays(days)
    return (days + 4) % 7
end

local function firstWeekdayOfMonth(y, m, targetWday)
    local wday1 = weekdayFromDays(daysFromCivil(y, m, 1))
    return 1 + ((targetWday - wday1 + 7) % 7)
end

local function lastWeekdayOfMonth(y, m, targetWday, lastDay)
    local wdayLast = weekdayFromDays(daysFromCivil(y, m, lastDay))
    return lastDay - ((wdayLast - targetWday + 7) % 7)
end

local function utcAt(y, m, d, hourUtc)
    return daysFromCivil(y, m, d) * 86400 + hourUtc * 3600
end

-- 美西：第二个周日 3 月 02:00 本地标准时(=10:00 UTC) 起 PDT，第一个周日 11 月 02:00 本地夏令时(=09:00 UTC) 止 PST
local function usPacificDst(y)
    return utcAt(y, 3, firstWeekdayOfMonth(y, 3, 0) + 7, 10),
        utcAt(y, 11, firstWeekdayOfMonth(y, 11, 0), 9)
end

-- 英国：最后一个周日 3 月 01:00 UTC 起 BST，最后一个周日 10 月 01:00 UTC 止 GMT
local function europeLondonDst(y)
    return utcAt(y, 3, lastWeekdayOfMonth(y, 3, 0, 31), 1),
        utcAt(y, 10, lastWeekdayOfMonth(y, 10, 0, 31), 1)
end

TimeState.CITIES = {
    los_angeles = { label = "Los Angeles", scenePrefix = "la", stdOffset = -8 * 3600, dstOffset = -7 * 3600, dstRange = usPacificDst, hemisphere = "N" },
    london      = { label = "London",   scenePrefix = "lon", stdOffset = 0,         dstOffset = 1 * 3600,  dstRange = europeLondonDst, hemisphere = "N" },
    shanghai    = { label = "Shanghai",   scenePrefix = "sha", stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
    chengdu     = { label = "Chengdu",   scenePrefix = "cdu", stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
}

-- 作息表按城市分键：换城市就是换一套日程叙事，四城各自覆盖 00:00–24:00 无缝。
-- 洛杉矶这张表是 M0-1/M1/M2 已验收的那一份，原样迁移为一个键，一行不改。
-- 每城至少两处可见差异（早晨 / 忙碌·碎片 / 傍晚·深夜），且事件 id 与 ProfileService 的
-- 城市叙事摘要、EventService 的事件模板严格同名——作息行仍是「这一档她在做什么」的唯一声明处。
-- M4：每城可见地点恰好四类（居所 / 工作场所 / 公共停留处 / 街区或通勤过渡处），
-- 与 SceneService 的 16 个场景包一一对应；place 直接决定 sceneId = 前缀_place，
-- 所以这里绝不允许出现第五种 place —— 那会指向一张不存在的背景。
TimeState.SCHEDULE_BY_CITY = {
    los_angeles = {
        { from = 0,  to = 6,  availability = "offline",    place = "apartment", event = "la_apartment_night_rest",   phrase = "Asleep" },
        { from = 6,  to = 8,  availability = "idle",       place = "apartment", event = "la_apartment_morning_inbox", phrase = "Making coffee" },
        { from = 8,  to = 12, availability = "busy",       place = "studio",    event = "la_campus_workshop",         phrase = "Preparing a workshop" },
        { from = 12, to = 13, availability = "fragments",  place = "cafe",      event = "la_cafe_midday",             phrase = "Having lunch" },
        { from = 13, to = 17, availability = "busy",       place = "studio",    event = "la_studio_zine_layout",      phrase = "Working on a deadline" },
        { from = 17, to = 19, availability = "fragments",  place = "commute",   event = "la_commute_voice_notes",     phrase = "On the way" },
        { from = 19, to = 22, availability = "idle",       place = "cafe",      event = "la_cafe_open_mic",           phrase = "Still out" },
        { from = 22, to = 24, availability = "idle",       place = "apartment", event = "la_apartment_wind_down",     phrase = "Back at the apartment" },
    },
    shanghai = {
        { from = 0,  to = 6,  availability = "offline",    place = "apartment", event = "sha_apartment_night_rest",    phrase = "Asleep" },
        { from = 6,  to = 8,  availability = "idle",       place = "apartment", event = "sha_apartment_morning_balcony", phrase = "Watering the balcony plants" },
        { from = 8,  to = 9,  availability = "fragments",  place = "commute",   event = "sha_commute_rush",            phrase = "On a crowded metro" },
        { from = 9,  to = 12, availability = "busy",       place = "office",    event = "sha_office_topic_meeting",    phrase = "In an editorial meeting" },
        { from = 12, to = 13, availability = "fragments",  place = "office",    event = "sha_cafe_midday",             phrase = "Having lunch" },
        { from = 13, to = 17, availability = "busy",       place = "office",    event = "sha_office_layout",           phrase = "Checking layouts" },
        { from = 17, to = 19, availability = "fragments",  place = "commute",   event = "sha_commute_market",          phrase = "Stopping at the market" },
        { from = 19, to = 22, availability = "idle",       place = "bookstore", event = "sha_bookstore_evening",       phrase = "On shift at the bookshop" },
        { from = 22, to = 24, availability = "idle",       place = "apartment", event = "sha_apartment_reread",        phrase = "Back at the apartment" },
    },
    chengdu = {
        { from = 0,  to = 7,  availability = "offline",    place = "apartment", event = "cdu_apartment_night_rest",    phrase = "Asleep" },
        { from = 7,  to = 9,  availability = "idle",       place = "apartment", event = "cdu_apartment_morning_water", phrase = "Watering plants" },
        { from = 9,  to = 12, availability = "busy",       place = "studio",    event = "cdu_studio_morning_ink",      phrase = "Drawing postcards" },
        { from = 12, to = 14, availability = "idle",       place = "cafe",      event = "cdu_cafe_midday",             phrase = "At the teahouse" },
        { from = 14, to = 18, availability = "busy",       place = "studio",    event = "cdu_studio_color",            phrase = "Mixing colours" },
        { from = 18, to = 20, availability = "fragments",  place = "commute",   event = "cdu_commute_supplies",        phrase = "On the way" },
        { from = 20, to = 23, availability = "idle",       place = "commute",   event = "cdu_nightmarket_supper",      phrase = "At the night market" },
        { from = 23, to = 24, availability = "idle",       place = "apartment", event = "cdu_apartment_letters",       phrase = "Back at the apartment" },
    },
    london = {
        { from = 0,  to = 6,  availability = "offline",    place = "apartment", event = "lon_apartment_night_rest",    phrase = "Asleep" },
        { from = 6,  to = 7,  availability = "idle",       place = "apartment", event = "lon_apartment_morning_tea",   phrase = "Making tea" },
        { from = 7,  to = 8,  availability = "fragments",  place = "commute",   event = "lon_commute_early_train",     phrase = "Catching a train" },
        { from = 8,  to = 13, availability = "busy",       place = "studio",    event = "lon_campus_lecture",          phrase = "In the college studio" },
        { from = 13, to = 14, availability = "fragments",  place = "commute",   event = "lon_cafe_midday",             phrase = "Having a sandwich" },
        { from = 14, to = 18, availability = "busy",       place = "studio",    event = "lon_studio_field_recording",  phrase = "In the recording studio" },
        { from = 18, to = 19, availability = "fragments",  place = "commute",   event = "lon_commute_dark",            phrase = "On the way" },
        { from = 19, to = 22, availability = "idle",       place = "recordshop", event = "lon_recordshop_shift",       phrase = "At the record shop" },
        { from = 22, to = 24, availability = "idle",       place = "apartment", event = "lon_apartment_mixdown",       phrase = "Back at the apartment" },
    },
}

-- slotAt 与 EventService 读的是同一张城市表，不是副本；缺城回落洛杉矶（与 CITIES 回落一致）。
local SCHEDULE_BY_CITY = TimeState.SCHEDULE_BY_CITY
local DEFAULT_CITY = "los_angeles"

--- 取某城的作息表（未知城市回落洛杉矶）。slotAt 与 EventService 共用这一个把手。
---@param cityId string
---@return { from: integer, to: integer, availability: string, place: string, event: string, phrase: string }[]
function TimeState.ScheduleFor(cityId)
    return SCHEDULE_BY_CITY[cityId] or SCHEDULE_BY_CITY[DEFAULT_CITY]
end

-- 可回复性策略 = 规格 §5.2「聊天行为」那一列的可实现层落地：
-- 空闲 / 碎片时间能回（碎片时间更慢、更短），忙碌与睡眠一律排队到下一个可回复窗口。
-- delaySeconds 是「进入窗口之后」再给她的反应时间，idle 那条由 main.lua 用演示时长覆盖，
-- 保证 M0-1 的固定 10 秒链路仍然只有一个真源。
---@type table<string, { replyable: boolean, delaySeconds?: integer, brief?: boolean }>
local REPLY_POLICY = {
    idle      = { replyable = true,  delaySeconds = 10,   brief = false },
    fragments = { replyable = true,  delaySeconds = 16,   brief = true },
    busy      = { replyable = false },
    offline   = { replyable = false },
}

---@type table<string, string>
local AVAILABILITY_LABEL = {
    idle = "Free to chat",
    fragments = "Only a moment free",
    busy = "Busy",
    offline = "Asleep",
}

--- 取某档可用性的回复策略（返回表本身，勿在外部改写）
---@param availability string
---@return { replyable: boolean, delaySeconds?: integer, brief?: boolean }
function TimeState.PolicyFor(availability)
    return REPLY_POLICY[availability] or REPLY_POLICY.busy
end

--- 演示/自检唯一的时长覆盖点：把某档的反应时间改掉
---@param availability string
---@param seconds number
function TimeState.SetReplyDelay(availability, seconds)
    local policy = REPLY_POLICY[availability]
    if policy and seconds and seconds > 0 then
        policy.delaySeconds = math.floor(seconds)
    end
end

---@param availability string
---@return string
function TimeState.AvailabilityLabel(availability)
    return AVAILABILITY_LABEL[availability] or availability
end

---@type table<number, string>
local SEASONS = { "Winter", "Spring", "Spring", "Spring", "Summer", "Summer", "Summer", "Autumn", "Autumn", "Winter", "Winter", "Winter" }

-- 天气只走低风险状态，且由 city_id + 当地日期定种，全天一致（§5.1）
local WEATHER_BY_CITY = {
    los_angeles = { { "Sunny", 62 }, { "Cloudy", 26 }, { "Windy", 12 } },
    london      = { { "Cloudy", 48 }, { "Rainy", 34 }, { "Windy", 12 }, { "Sunny", 6 } },
    shanghai    = { { "Cloudy", 34 }, { "Rainy", 30 }, { "Sunny", 26 }, { "Windy", 10 } },
    chengdu     = { { "Cloudy", 46 }, { "Sunny", 24 }, { "Rainy", 22 }, { "Windy", 8 } },
}

local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h ~ s:byte(i)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    end
    return h
end

local function pickWeather(cityId, dateKey, month)
    local table_ = WEATHER_BY_CITY[cityId] or WEATHER_BY_CITY.los_angeles
    local roll = fnv1a(cityId .. "/" .. dateKey) % 100
    local acc = 0
    for i = 1, #table_ do
        acc = acc + table_[i][2]
        if roll < acc then
            return table_[i][1]
        end
    end
    return table_[1][1]
end

local function slotAt(cityId, hour)
    local schedule = TimeState.ScheduleFor(cityId)
    for i = 1, #schedule do
        local slot = schedule[i]
        if hour >= slot.from and hour < slot.to then
            return slot
        end
    end
    return schedule[#schedule]
end

local function civilDaySeconds(dateKey)
    local y, m, d = dateKey:match("^(%d+)-(%d+)-(%d+)$")
    if not y then
        return nil
    end
    return daysFromCivil(tonumber(y), tonumber(m), tonumber(d)) * 86400
end

--- 开发自检的时钟投影（秒）。0 = 完全交还权威时间源；只由 DevSelfTest 改写。
---@type number
TimeState.DevClockOffset = 0

--- 权威 UTC 秒 + 开发自检投影。普通运行路径只有这一处取时间。
---@return number
function TimeState.NowUtc()
    return common.get_server_time() + TimeState.DevClockOffset
end

--- 开发测试专用：把本次运行投影到角色当地日期的指定钟点。
--- 不触碰设备系统时间，也不写入存档；重启或 ResetDevClock 后立即回到权威 UTC。
---@param cityId string
---@param hour integer
---@param minute? integer
---@return TimeSnapshot
function TimeState.SetDevLocalHour(cityId, hour, minute)
    local realUtc = common.get_server_time()
    local realSnap = TimeState.Snapshot(cityId, realUtc)
    local safeHour = math.max(0, math.min(23, math.floor(hour or 0)))
    local safeMinute = math.max(0, math.min(59, math.floor(minute or 0)))
    local targetUtc = TimeState.UtcAtLocal(cityId, realSnap.dateKey, safeHour, safeMinute)
    TimeState.DevClockOffset = targetUtc - realUtc
    return TimeState.Snapshot(cityId, targetUtc)
end

--- 开发测试专用：投影到明确的 UTC 秒，供“推进到下一可回复窗口”使用。
---@param utcSec number
function TimeState.SetDevUtc(utcSec)
    TimeState.DevClockOffset = math.floor(utcSec) - common.get_server_time()
end

function TimeState.ResetDevClock()
    TimeState.DevClockOffset = 0
end

---@class ReplyPlan
---@field replyable boolean 送达时她是否处于可回复档
---@field brief boolean 碎片时间：回复要短
---@field availability string 送达时当地处于哪一档
---@field delaySeconds integer 进入可回复窗口后还要多久才回
---@field windowStartUtc integer? 可回复窗口的起始 UTC 秒（当下即可回复时为 nil）
---@field replyAtUtc integer? 计划回复 UTC 秒；nil 表示 24 小时内找不到可回复窗口

--- 给定 UTC 时刻的回复计划：现在能回就延时，在忙/在睡就推到下一个可回复窗口之后
---@param cityId string
---@param utcSec number
---@return ReplyPlan
function TimeState.ReplyPlanFor(cityId, utcSec)
    local snap = TimeState.Snapshot(cityId, utcSec)
    local policy = TimeState.PolicyFor(snap.availability)
    if policy.replyable then
        return {
            replyable = true,
            brief = policy.brief == true,
            availability = snap.availability,
            delaySeconds = policy.delaySeconds or 10,
            windowStartUtc = nil,
            replyAtUtc = math.floor(utcSec) + (policy.delaySeconds or 10),
        }
    end
    local windowStart = TimeState.NextReplyableUtc(cityId, utcSec)
    if not windowStart then
        return {
            replyable = false,
            brief = false,
            availability = snap.availability,
            delaySeconds = 0,
            windowStartUtc = nil,
            replyAtUtc = nil,
        }
    end
    local target = TimeState.PolicyFor(TimeState.Snapshot(cityId, windowStart).availability)
    return {
        replyable = false,
        brief = target.brief == true,
        availability = snap.availability,
        delaySeconds = target.delaySeconds or 10,
        windowStartUtc = windowStart,
        replyAtUtc = windowStart + (target.delaySeconds or 10),
    }
end

--- 下一个「可回复」档的起始 UTC 秒。按整小时往后试（作息表按小时分段），
--- 命中后再按分钟回退找最早的可回复那一分钟；DST 由 Snapshot 复核，不做假设。
---@param cityId string
---@param utcSec number
---@return integer|nil # 当下已可回复或 24 小时内无可回复窗口时返回 nil
function TimeState.NextReplyableUtc(cityId, utcSec)
    local base = TimeState.Snapshot(cityId, utcSec)
    if TimeState.PolicyFor(base.availability).replyable then
        return nil
    end
    local utc = math.floor(utcSec)
    -- 当前当地小时的起点：当地秒与 UTC 秒在同一固定偏移段内同步前进。
    -- minute 来自 tonumber(os.date) 是 number，这里夹回 integer，下游 %d 才安全。
    local hourStartUtc = utc - math.floor(base.minute) * 60 - math.floor(utc % 60)
    for delta = 1, 24 do
        local candidate = hourStartUtc + delta * 3600
        if TimeState.PolicyFor(TimeState.Snapshot(cityId, candidate).availability).replyable then
            -- 往前回退找这一档最早的那一分钟（作息表整小时切换，回退一圈即返回整点）
            for back = 59, 1, -1 do
                local earlier = candidate - back * 60
                if TimeState.PolicyFor(TimeState.Snapshot(cityId, earlier).availability).replyable then
                    return earlier
                end
            end
            return candidate
        end
    end
    return nil
end

--- 当地日期前后挪 N 天（事件计划要引用「昨天」和「明天」的日期键）。
--- 走 daysFromCivil + os.date("!")，不碰设备本地时区。
---@param dateKey string "YYYY-MM-DD"
---@param days integer
---@return string
function TimeState.ShiftDateKey(dateKey, days)
    local sec = civilDaySeconds(dateKey)
    if not sec then
        return dateKey
    end
    local shifted = os.date("!%Y-%m-%d", sec + math.floor(days) * 86400)
    if type(shifted) ~= "string" then
        return dateKey
    end
    return shifted
end

--- 反查「当地的某个整点」对应的 UTC 秒（开发自检用）。偏移按目标时刻自身迭代三次收敛。
---@param cityId string
---@param dateKey string "YYYY-MM-DD"（当地日期）
---@param hour integer 0-23
---@param minute? integer 0-59，省略为整点
---@return integer
function TimeState.UtcAtLocal(cityId, dateKey, hour, minute)
    local city = TimeState.CITIES[cityId] or TimeState.CITIES.los_angeles
    local daySec = civilDaySeconds(dateKey) or 0
    local localSec = daySec + hour * 3600 + math.floor(minute or 0) * 60
    local guess = localSec - city.stdOffset
    for _ = 1, 3 do
        local snap = TimeState.Snapshot(cityId, guess)
        guess = localSec - snap.offsetSeconds
    end
    return guess
end

---@class TimeSnapshot
---@field cityId string
---@field cityLabel string
---@field utcSec integer
---@field localSec integer
---@field offsetSeconds integer
---@field isDst boolean
---@field dateKey string
---@field hour number
---@field minute number
---@field clock string
---@field season string
---@field weather string
---@field availability string
---@field availabilityLabel string
---@field replyable boolean
---@field brief boolean
---@field place string
---@field sceneId string
---@field phrase string

---@param cityId string
---@param utcSec number? 省略则取权威服务器时间（含开发自检投影）
---@return TimeSnapshot
function TimeState.Snapshot(cityId, utcSec)
    local city = TimeState.CITIES[cityId] or TimeState.CITIES.los_angeles
    local utc = utcSec or TimeState.NowUtc()
    utc = math.floor(utc)

    local year = tonumber(os.date("!%Y", utc)) or 1970
    local dstStart, dstEnd = utc, utc
    if city.dstRange then
        dstStart, dstEnd = city.dstRange(year)
    end
    local onDst = city.dstRange ~= nil and utc >= dstStart and utc < dstEnd
    local offset = onDst and city.dstOffset or city.stdOffset

    -- 当地日期必须从「加了偏移」的时刻反算，用 UTC 日期会让跨日线的城市算错一天
    local localSec = utc + offset
    local dateKey = os.date("!%Y-%m-%d", localSec)
    local hour = tonumber(os.date("!%H", localSec)) or 0
    local minute = tonumber(os.date("!%M", localSec)) or 0
    local month = tonumber(os.date("!%m", localSec)) or 1

    local slot = slotAt(cityId, hour)
    local policy = TimeState.PolicyFor(slot.availability)

    return {
        cityId = cityId,
        cityLabel = city.label,
        utcSec = utc,
        localSec = localSec,
        offsetSeconds = offset,
        isDst = onDst,
        dateKey = dateKey,
        hour = hour,
        minute = minute,
        clock = string.format("%02d:%02d", hour, minute),
        season = SEASONS[month],
        weather = pickWeather(cityId, dateKey, month),
        availability = slot.availability,
        availabilityLabel = TimeState.AvailabilityLabel(slot.availability),
        replyable = policy.replyable == true,
        brief = policy.brief == true,
        place = slot.place,
        sceneId = (city.scenePrefix or cityId) .. "_" .. slot.place,
        phrase = slot.phrase,
    }
end

---@param cityId string
---@return string
function TimeState.StatusLine(cityId)
    local snap = TimeState.Snapshot(cityId)
    return snap.cityLabel .. " · " .. snap.clock .. " · " .. snap.phrase
end

return TimeState
