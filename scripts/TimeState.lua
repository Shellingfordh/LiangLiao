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
    los_angeles = { label = "洛杉矶", scenePrefix = "la", stdOffset = -8 * 3600, dstOffset = -7 * 3600, dstRange = usPacificDst, hemisphere = "N" },
    london      = { label = "伦敦",   scenePrefix = "lon", stdOffset = 0,         dstOffset = 1 * 3600,  dstRange = europeLondonDst, hemisphere = "N" },
    shanghai    = { label = "上海",   scenePrefix = "sha", stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
    chengdu     = { label = "成都",   scenePrefix = "cdu", stdOffset = 8 * 3600,  dstOffset = 8 * 3600,  dstRange = nil, hemisphere = "N" },
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
    idle = "有空",
    fragments = "只有碎片时间",
    busy = "在忙",
    offline = "睡了",
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
---@return TimeSnapshot
function TimeState.SetDevLocalHour(cityId, hour)
    local realUtc = common.get_server_time()
    local realSnap = TimeState.Snapshot(cityId, realUtc)
    local safeHour = math.max(0, math.min(23, math.floor(hour or 0)))
    local targetUtc = TimeState.UtcAtLocal(cityId, realSnap.dateKey, safeHour)
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

--- 反查「当地的某个整点」对应的 UTC 秒（开发自检用）。偏移按目标时刻自身迭代三次收敛。
---@param cityId string
---@param dateKey string "YYYY-MM-DD"（当地日期）
---@param hour integer 0-23
---@return integer
function TimeState.UtcAtLocal(cityId, dateKey, hour)
    local city = TimeState.CITIES[cityId] or TimeState.CITIES.los_angeles
    local daySec = civilDaySeconds(dateKey) or 0
    local localSec = daySec + hour * 3600
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

    local slot = slotAt(hour)
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
