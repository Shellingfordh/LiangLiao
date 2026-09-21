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
---@field availability string
---@field cityLabel string
---@field clock string
---@field dateKey string
---@field weather string
---@field season string
---@field phrase string
---@field serverTime integer

---@return string # ongoing | upcoming | ended
local function eventStateAt(hour)
    if hour >= CAFE_EVENT.startHour and hour < CAFE_EVENT.endHour then
        return "ongoing"
    elseif hour < CAFE_EVENT.startHour then
        return "upcoming"
    end
    return "ended"
end

--- 「咖啡馆活动未结束」这条事实的完整表述；其余状态也要有落点，否则回复会空
---@param state string
---@return string
local function phraseFor(state)
    if state == "ongoing" then
        return "咖啡馆这场还没收，人比昨天多一点"
    elseif state == "upcoming" then
        return "咖啡馆晚上那场还没开始，我先占位子"
    end
    return "咖啡馆那场已经收了，我在回去的路上了"
end

--- 选择当前时刻的事件事实快照
---@param snap table TimeState.Snapshot 的返回值
---@return EventFact
function EventService.FromSnapshot(snap)
    local state = eventStateAt(snap.hour)
    ---@type EventFact
    local fact = {
        id = CAFE_EVENT.id,
        eventState = state,
        eventTitle = CAFE_EVENT.title,
        eventPhrase = phraseFor(state),
        eventEndsAt = string.format("%02d:00", CAFE_EVENT.endHour),
        place = snap.place,
        placeLabel = PLACE_LABEL[snap.place] or "外面",
        availability = snap.availability,
        cityLabel = snap.cityLabel,
        clock = snap.clock,
        dateKey = snap.dateKey,
        weather = snap.weather,
        season = snap.season,
        phrase = snap.phrase,
        serverTime = snap.utcSec,
    }
    logInfo(string.format("事件事实 state=%s place=%s clock=%s", state, fact.place, fact.clock))
    return fact
end

---@return string
function EventService.GetEventId()
    return CAFE_EVENT.id
end

return EventService
