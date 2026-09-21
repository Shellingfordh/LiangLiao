-- ============================================================================
-- EventService.lua — 从 TimeState 快照挑「固定事件事实」
-- 事实是既定事实，不是生成内容：回复只能引用这里返回的东西（设计规格 §5.2）。
-- 首版只有一条事件线：洛杉矶咖啡馆的晚间开放麦克风场。
-- 钟点属于可实现层的创作（规格只给了状态与地点），改这里即可改她的日程。
-- ============================================================================

local EventService = {}

local CAFE_EVENT = {
    id = "la_cafe_open_mic",
    title = "咖啡馆的开放麦克风夜",
    startHour = 19,   -- 与 TimeState 作息 19:00「还在外面 / cafe」对齐
    endHour = 22,     -- 与 TimeState 作息 22:00「回到公寓了」对齐
    dayBreakHour = 8, -- 与作息 6:00「在煮咖啡」之后；凌晨到清晨属于「上一场已收」
}

---@type table<string, string>
local PLACE_LABEL = {
    cafe = "咖啡馆",
    apartment = "公寓",
    campus = "学校",
    studio = "工作室",
    commute = "路上",
}

local function logInfo(msg)
    print("[EventService] " .. msg)
    log:Write(LOG_INFO, "[EventService] " .. msg)
end

---@class EventFact
---@field id string
---@field eventState string ongoing|upcoming|ended
---@field eventTitle string
---@field eventPhrase string
---@field eventEndsAt string
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
---@field queued boolean? 只有当下不可回复、事后补回时才为 true
---@field thenPhrase string? 消息送达时她所处档的原话（作息表事实）
---@field thenClock string? 消息送达时的当地钟点
---@field gapSeconds integer? 从送达到交付经过了多少秒

---@return string # ongoing | upcoming | ended
local function eventStateAt(hour)
    if hour >= CAFE_EVENT.startHour and hour < CAFE_EVENT.endHour then
        return "ongoing"
    elseif hour >= CAFE_EVENT.dayBreakHour and hour < CAFE_EVENT.startHour then
        return "upcoming"
    end
    -- 22 点之后到次日早上：属于「上一场早就收了」，不能说成还没开始去占位子
    return "ended"
end

--- 「咖啡馆活动未结束」这条事实的完整表述；其余状态也要有落点，否则回复会空
---@param state string
---@param snap table
---@return string
local function phraseFor(state, snap)
    local place = PLACE_LABEL[snap.place] or "外面"
    if state == "ongoing" then
        return "咖啡馆这场还没收，人比昨天多一点"
    elseif state == "upcoming" then
        return "咖啡馆晚上那场还没开始，我还在" .. place
    elseif snap.place == "apartment" then
        return "咖啡馆那场早就收了，我回公寓了"
    end
    return "咖啡馆那场已经收了，我在" .. place
end

--- 选择当前时刻的事件事实快照。
--- 传 sentSnap（该条消息送达时刻的快照）即表示「这是排队之后的补回复」：那时的原话与
--- 钟点同样来自作息表，是既定事实，可以写进回复；这里不新增任何猜测或补全。
---@param snap table TimeState.Snapshot 的返回值（交付/当前时刻）
---@param sentSnap? table 同一条消息送达时刻的 TimeState 快照
---@return EventFact
function EventService.FromSnapshot(snap, sentSnap)
    local state = eventStateAt(snap.hour)
    ---@type EventFact
    local fact = {
        id = CAFE_EVENT.id,
        eventState = state,
        eventTitle = CAFE_EVENT.title,
        eventPhrase = phraseFor(state, snap),
        eventEndsAt = string.format("%02d:00", CAFE_EVENT.endHour),
        place = snap.place,
        placeLabel = PLACE_LABEL[snap.place] or "外面",
        sceneId = snap.sceneId or "",
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
    }
    if sentSnap and sentSnap.utcSec and sentSnap.utcSec < snap.utcSec then
        fact.queued = not sentSnap.replyable
        fact.thenPhrase = sentSnap.phrase
        fact.thenClock = sentSnap.clock
        fact.gapSeconds = math.max(0, math.floor(snap.utcSec - sentSnap.utcSec))
    end
    if fact.queued then
        logInfo(string.format("事件事实 state=%s place=%s clock=%s 排队补回 送达=%s(%s) 隔 %d 秒",
            state, fact.place, fact.clock, tostring(fact.thenClock),
            tostring(fact.thenPhrase), fact.gapSeconds or 0))
    else
        logInfo(string.format("事件事实 state=%s place=%s clock=%s", state, fact.place, fact.clock))
    end
    return fact
end

---@return string
function EventService.GetEventId()
    return CAFE_EVENT.id
end

return EventService
