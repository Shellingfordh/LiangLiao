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
    los_angeles = { label = "洛杉矶", stdOffset = -8 * 3600, dstOffset = -7 * 3600, dstRange = usPacificDst, hemisphere = "N" },
    london      = { label = "伦敦",   stdOffset = 0,         dstOffset = 1 * 3600,  dstRange = europeLondonDst, hemisphere = "N" },
    shanghai    = { label = "上海",   stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
    chengdu     = { label = "成都",   stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
}

-- 作息表：规格 §5.2 只给了「内部状态 / 可能地点 / 聊天行为」，没给钟点。
-- 这张表是可实现层的创作，改这里就能改她的日程，不用动逻辑。
local SCHEDULE = {
    { from = 0,  to = 6,  availability = "offline",    place = "apartment", phrase = "已经睡下了" },
    { from = 6,  to = 8,  availability = "idle",       place = "apartment", phrase = "在煮咖啡" },
    { from = 8,  to = 12, availability = "busy",       place = "campus",    phrase = "在上课" },
    { from = 12, to = 13, availability = "fragments",  place = "cafe",      phrase = "在吃午饭" },
    { from = 13, to = 17, availability = "busy",       place = "studio",    phrase = "在赶项目" },
    { from = 17, to = 19, availability = "fragments",  place = "commute",   phrase = "在路上" },
    { from = 19, to = 22, availability = "idle",       place = "cafe",      phrase = "还在外面" },
    { from = 22, to = 24, availability = "idle",       place = "apartment", phrase = "回到公寓了" },
}

---@type string[]
local SEASONS = { "冬", "春", "春", "春", "夏", "夏", "夏", "秋", "秋", "冬", "冬", "冬" }

-- 天气只走低风险状态，且由 city_id + 当地日期定种，全天一致（§5.1）
local WEATHER_BY_CITY = {
    los_angeles = { { "晴", 62 }, { "阴", 26 }, { "风", 12 } },
    london      = { { "阴", 48 }, { "雨", 34 }, { "风", 12 }, { "晴", 6 } },
    shanghai    = { { "阴", 34 }, { "雨", 30 }, { "晴", 26 }, { "风", 10 } },
    chengdu     = { { "阴", 46 }, { "晴", 24 }, { "雨", 22 }, { "风", 8 } },
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

local function slotAt(hour)
    for i = 1, #SCHEDULE do
        local slot = SCHEDULE[i]
        if hour >= slot.from and hour < slot.to then
            return slot
        end
    end
    return SCHEDULE[#SCHEDULE]
end

---@param cityId string
---@param utcSec integer? 省略则取权威服务器时间
---@return table
function TimeState.Snapshot(cityId, utcSec)
    local city = TimeState.CITIES[cityId] or TimeState.CITIES.los_angeles
    local utc = utcSec or common.get_server_time()
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

    local slot = slotAt(hour)

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
        place = slot.place,
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
