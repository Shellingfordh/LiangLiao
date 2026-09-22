-- ============================================================================
-- EventService.lua — 从 TimeState 快照挑「固定事件事实」
-- 事实是既定事实，不是生成内容：回复只能引用这里返回的东西（设计规格 §5.2）。
-- 事件模板是小而确定的目录：时间状态决定当前模板，模板再决定状态窗和对话事实。
-- 不做随机剧情、不调用外部服务；同一城市、日期、时段总得到同一 occurrenceKey。
-- ============================================================================

local EventService = {}

local EVENT_TEMPLATES = {
    apartment_morning = {
        id = "la_apartment_morning_inbox", place = "apartment", sceneId = "la_apartment",
        title = "清晨的活动邮件", endHour = 8,
        phrases = { "我在公寓把活动邮件和便签归到一起", "咖啡刚好冲完，我在核对今天的活动清单" },
        summary = "清晨整理了今天活动的邮件和便签", emotion = "安静、专注",
    },
    studio_layout = {
        id = "la_studio_zine_layout", place = "studio", sceneId = "la_studio",
        title = "小册子版面校样", endHour = 17,
        phrases = { "工作室里在对小册子的最后一版校样", "我在工作室挪版面，桌上全是没裁的样张" },
        summary = "在工作室完成小册子版面校样", emotion = "专注、略紧张",
    },
    cafe_open_mic = {
        id = "la_cafe_open_mic", place = "cafe", sceneId = "la_cafe",
        title = "咖啡馆的开放麦克风夜", endHour = 22,
        phrases = { "咖啡馆这场开放麦克风还没收，人比昨天多一点", "店里正在轮到下一位上台，我坐在靠窗的位置" },
        summary = "在咖啡馆参与开放麦克风夜", emotion = "放松、投入",
    },
    apartment_wind_down = {
        id = "la_apartment_wind_down", place = "apartment", sceneId = "la_apartment",
        title = "回家后的活动复盘", endHour = 6,
        phrases = { "我回到公寓，把今晚活动的几张便签摊开了", "刚到家，正在把今天剩下的事情写进明天的清单" },
        summary = "回到公寓整理活动后的便签", emotion = "疲惫、踏实",
    },
    campus_workshop = {
        id = "la_campus_workshop", place = "campus", sceneId = "la_studio",
        title = "学校工作坊的准备", endHour = 12,
        phrases = { "学校工作坊快开始了，我在整理要用的材料", "我在学校的工作桌边，把示例顺了一遍" },
        summary = "在学校准备一场小型工作坊", emotion = "忙碌、期待",
    },
    commute_notes = {
        id = "la_commute_voice_notes", place = "commute", sceneId = "la_cafe",
        title = "路上的语音便签", endHour = 19,
        phrases = { "我在路上，刚把一个想法录进语音便签", "车还没到站，我在看晚上的活动安排" },
        summary = "在路上整理晚间活动的语音便签", emotion = "短暂、轻快",
    },
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
---@field occurrenceKey string
---@field eventState string ongoing|upcoming|ended
---@field eventTitle string
---@field eventPhrase string
---@field eventSummary string
---@field eventEmotion string
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

---@param snap table
---@return table
local function templateFor(snap)
    if snap.place == "apartment" then
        if snap.hour >= 6 and snap.hour < 8 then
            return EVENT_TEMPLATES.apartment_morning
        end
        return EVENT_TEMPLATES.apartment_wind_down
    elseif snap.place == "studio" then
        return EVENT_TEMPLATES.studio_layout
    elseif snap.place == "cafe" then
        return EVENT_TEMPLATES.cafe_open_mic
    elseif snap.place == "campus" then
        return EVENT_TEMPLATES.campus_workshop
    end
    return EVENT_TEMPLATES.commute_notes
end

---@param text string
---@return integer
local function hash(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 ~ text:byte(i)) & 0x7FFFFFFF
    end
    return h
end

---@param template table
---@param snap table
---@return string
local function phraseFor(template, snap)
    local phrases = template.phrases or { "我在" .. (PLACE_LABEL[snap.place] or "外面") }
    local index = (hash((snap.dateKey or "") .. "|" .. template.id) % #phrases) + 1
    return phrases[index]
end

--- 选择当前时刻的事件事实快照。
--- 传 sentSnap（该条消息送达时刻的快照）即表示「这是排队之后的补回复」：那时的原话与
--- 钟点同样来自作息表，是既定事实，可以写进回复；这里不新增任何猜测或补全。
---@param snap table TimeState.Snapshot 的返回值（交付/当前时刻）
---@param sentSnap? table 同一条消息送达时刻的 TimeState 快照
---@return EventFact
function EventService.FromSnapshot(snap, sentSnap)
    local template = templateFor(snap)
    local occurrenceKey = string.format("%s/%s/%s", snap.cityId or "city", snap.dateKey or "date", template.id)
    ---@type EventFact
    local fact = {
        id = template.id,
        occurrenceKey = occurrenceKey,
        eventState = "ongoing",
        eventTitle = template.title,
        eventPhrase = phraseFor(template, snap),
        eventSummary = template.summary,
        eventEmotion = template.emotion,
        eventEndsAt = string.format("%02d:00", template.endHour),
        place = snap.place,
        placeLabel = PLACE_LABEL[snap.place] or "外面",
        sceneId = template.sceneId or snap.sceneId or "",
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
        logInfo(string.format("事件事实 id=%s occurrence=%s scene=%s 排队补回 送达=%s(%s) 隔 %d 秒",
            fact.id, fact.occurrenceKey, fact.sceneId, tostring(fact.thenClock),
            tostring(fact.thenPhrase), fact.gapSeconds or 0))
    else
        logInfo(string.format("事件事实 id=%s occurrence=%s scene=%s clock=%s",
            fact.id, fact.occurrenceKey, fact.sceneId, fact.clock))
    end
    return fact
end

---@return string
function EventService.GetEventId()
    return EVENT_TEMPLATES.cafe_open_mic.id
end

return EventService
