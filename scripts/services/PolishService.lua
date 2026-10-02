-- ============================================================================
-- PolishService.lua — M2-B 客户端适配层（外发润色的唯一出口与最后一道校验）
-- 契约与 gateway/src/validate.js 是同一套规则的两份实现：
--   顶层恰为 segments / replyToQuotedMessageId 两键；1–3 条非空短句；
--   单句 ≤ min(40, maxCharsPerSegment)（brief → ≤20 且恰 1 句）；总长 ≤ 120；
--   引用 id 只可能是本次请求允许的 id 或 null；含 { } ` 或控制字符即拒。
-- 客户端额外做事实词表守卫（设计 §2 最后一道）：润色句里出现
-- 别的城市名 / 别的事件标题 / 白名单外的钟点表达 → 整条回落。
-- 任何失败（网络、超时、HTTP、JSON、守卫）都回落 ContentService 本地模板；
-- 回调按请求发起顺序交付（FIFO），同一条回复没落地前下一条不会先插队，
-- 但每条各自带 8 秒预算：到点必交付，队列永不阻塞。
-- ⚠️ API Key / GATEWAY_SHARED_SECRET 绝不在本文件出现：出站鉴权归 transport
--   （路径 A 的 Maker 服务端中转）负责，游戏端只交白名单 payload。
-- ============================================================================

local ContentService = require("services.ContentService")
local EventService = require("services.EventService")
local ProfileService = require("ProfileService")
local TimeState = require("TimeState")

local PolishService = {}

-- 构建期常量：只描述人格与说话方式，不含任何用户数据。
-- 身份与关系阶段随当前档案走（M3 四城 × 关系）；性格与语气红线是固定的。
local CORE = {
    characterId = "lin_ruoxi",
    characterName = "林若夕",
    personaTail = "Use natural, warm, understated English for a long-distance chat. "
        .. "Keep replies short. Use only the given facts; invent no history or promises, and imitate no real person.",
}

--- 每次请求从档案现取，不缓存：换档案后下一条请求的 persona 就是新城身份
---@return string
local function personaOf()
    return "Original character: " .. ProfileService.Get().identity .. " " .. CORE.personaTail
end

local MAX_SEG_CHARS = 40
local MAX_TOTAL_CHARS = 120
local BRIEF_SEG_CHARS = 20
local MAX_USER_RUNES = 300
local MAX_QUOTE_PREVIEW_RUNES = 24
-- 客户端总预算（设计 §5）：到点回落模板，绝不无限等
local POLISH_BUDGET_SECONDS = 8
-- 503（预算耗尽/熔断）后的会话级冷却
local COOLDOWN_SECONDS = 600

---@class PolishTransportResult
---@field ok boolean 网络层成功（不保证契约成立）
---@field status? integer HTTP 状态码
---@field bodyText? string 响应体原文（成功时也由本模块解码与校验，不信任上游解析）
---@field category? string 失败类别（timeout|network|http…），只进日志不进存档

---@class PolishTransport
---@field request fun(payload: table, callback: fun(result: PolishTransportResult)): nil

---@type boolean
local enabled_ = false
---@type PolishTransport|nil
local transport_ = nil
--- 401 一次即本会话熔断；503/预算类进冷却
local hardOff_ = false
local cooldownUntilUtc_ = 0

--- 在途/待交付的润色请求，按发起顺序排列（FIFO 交付序）
---@class PolishSlot
---@field req table 已构建的白名单请求
---@field onDone fun(segments: string[]|nil, category: string): nil
---@field deadlineUtc number
---@field settled boolean 传输层结果是否已回来
---@field result? PolishTransportResult
---@field delivered boolean
---@type PolishSlot[]
local slots_ = {}

local function logInfo(msg)
    print("[PolishService] " .. msg)
    log:Write(LOG_INFO, "[PolishService] " .. msg)
end

--- 回落路径一律 WARN，不用 ERROR：契约里「网络/超时/预算/守卫任何失败都回落模板」
--- 是设计内的正常收尾，不是故障。DevSelfTest 的判据是 runtime.log 里 ERROR=0 ⟺ 自检全绿，
--- 这里报 ERROR 会让「故意打负路径」的 R16/S4 把 ERROR 变成常态噪音。
local function logWarn(msg)
    print("[PolishService] WARN: " .. msg)
    log:Write(LOG_WARNING, "[PolishService] " .. msg)
end

--- UTF-8 码点计数：与网关 Array.from(s).length 同口径（一个汉字记 1）
---@param s string
---@return integer
local function runeLen(s)
    local n = 0
    for _ in (s or ""):gmatch("[\1-\127\194-\244][\128-\191]*") do
        n = n + 1
    end
    return n
end
PolishService.RuneLenForTest = runeLen

---@param s string
---@return string
local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- 裁到 maxRunes 个码点，不加省略号（发送前裁剪用户原文用）
---@param s string
---@param maxRunes integer
---@return string
local function clipRaw(s, maxRunes)
    s = s or ""
    if runeLen(s) <= maxRunes then
        return s
    end
    local pos, n = 1, 0
    local len = #s
    while pos <= len and n < maxRunes do
        local b = s:byte(pos)
        local step = 1
        if b >= 0xF0 then
            step = 4
        elseif b >= 0xE0 then
            step = 3
        elseif b >= 0xC0 then
            step = 2
        end
        pos = pos + step
        n = n + 1
    end
    return s:sub(1, pos - 1)
end

---@param opts? { enabled?: boolean, transport?: PolishTransport }
function PolishService.Configure(opts)
    opts = opts or {}
    if opts.enabled ~= nil then
        enabled_ = opts.enabled == true
    end
    if opts.transport ~= nil then
        transport_ = opts.transport
    end
    hardOff_ = false
    cooldownUntilUtc_ = 0
    slots_ = {}
    logInfo(string.format("配置 enabled=%s transport=%s",
        tostring(enabled_), transport_ and "custom" or "none"))
end

---@return boolean
function PolishService.IsEnabled()
    return enabled_ and not hardOff_ and transport_ ~= nil
end

--- 只暴露给测试：重置内部熔断/冷却/在途队列
function PolishService.ResetForTest()
    hardOff_ = false
    cooldownUntilUtc_ = 0
    slots_ = {}
end

-- =========================================================================
-- 白名单 payload（设计 §3）：全部来自交付时刻的 EventFact / MsgEntry 快照。
-- 不发送历史消息、MemoryService 内容、设备或真实 id。
-- =========================================================================

---@param fact EventFact
---@param pending MsgEntry
---@param nowUtc number
---@return table|nil req 组装不出合法白名单字段时返回 nil（调用方直接回落）
function PolishService.BuildRequest(fact, pending, nowUtc)
    local function okStr(s, max)
        return type(s) == "string" and s ~= "" and runeLen(s) <= max
    end
    -- 网关对 deliveryFact 的七个字段全部必填非空；缺任何一个都不该出站
    if not (okStr(fact.eventTitle, 60) and okStr(fact.eventSummary, 200)
            and okStr(fact.placeLabel, 60) and okStr(fact.clock, 8)
            and okStr(fact.weather, 20) and okStr(fact.availabilityLabel, 20)
            and okStr(fact.eventEndsAt, 8)
            and (fact.eventState == "ongoing" or fact.eventState == "ended" or fact.eventState == "upcoming")) then
        return nil
    end
    local queued = fact.queued == true
    local sendTitle = queued and fact.sentEventTitle or fact.eventTitle
    local sendState = queued and fact.sentEventState or fact.eventState
    local sendEnds = queued and fact.sentEventEndsAt or fact.eventEndsAt
    local gapText = ContentService.FormatGap(queued and fact.gapSeconds or 0)
    local thenPhrase = queued and fact.thenPhrase or fact.phrase
    if not (okStr(sendTitle, 60) and (sendState == "ongoing" or sendState == "ended" or sendState == "upcoming")
            and okStr(sendEnds, 8) and okStr(gapText, 20) and okStr(thenPhrase, 40)) then
        return nil
    end

    local quote = nil
    if pending.quotedMessageId then
        local preview = trim(ContentService.ClipPreview(pending.quotedTextPreview or "", MAX_QUOTE_PREVIEW_RUNES))
        if preview ~= "" and (pending.quotedRole == "user" or pending.quotedRole == "her") then
            quote = { messageId = pending.quotedMessageId, role = pending.quotedRole, preview = preview }
        end
    end

    local availability = fact.availability
    if availability ~= "idle" and availability ~= "fragments"
        and availability ~= "busy" and availability ~= "offline" then
        return nil
    end

    return {
        v = 1,
        requestId = string.format("c-%d-%d", pending.id or 0, math.floor(nowUtc)),
        core = {
            characterId = CORE.characterId,
            characterName = CORE.characterName,
            cityLabel = fact.cityLabel,
            relationStage = ProfileService.Get().relationLabel,
            persona = personaOf(),
        },
        deliveryFact = {
            eventTitle = fact.eventTitle,
            eventSummary = fact.eventSummary,
            sceneLabel = fact.placeLabel,
            clock = fact.clock,
            weather = fact.weather,
            availabilityLabel = fact.availabilityLabel,
            endTime = fact.eventEndsAt,
            state = fact.eventState,
        },
        sendFact = {
            eventTitle = sendTitle,
            state = sendState,
            endTime = sendEnds,
            gapText = gapText,
            thenPhrase = thenPhrase,
        },
        queued = queued,
        availability = availability,
        brief = fact.brief == true,
        maxCharsPerSegment = MAX_SEG_CHARS,
        maxTotalChars = MAX_TOTAL_CHARS,
        userMessage = clipRaw(trim(pending.text or ""), MAX_USER_RUNES),
        -- 显式契约：无引用也必须带 quote 键并编码为 null（网关对缺键直接 400）
        quote = quote or (cjson and cjson.null),
    }
end

-- =========================================================================
-- 响应严格校验（validate.js 的 Lua 镜像）
-- =========================================================================

local function hasForbiddenChar(s)
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x20 or b == 0x7f then
            return true
        end
    end
    return s:find("[{}]", 1, false) ~= nil or s:find("`", 1, true) ~= nil
end

--- 剥掉整段被围栏包裹的 JSON（与网关同规则：围栏外还有内容不剥）。
--- Lua 的 `.` 本身匹配任意字节（含换行），不需要 `[\s\S]` 这类正则写法。
local function stripCodeFence(text)
    local t = trim(text)
    local inner = t:match("^```[jJ][sS][oO][nN]%s*(.-)%s*```$")
    if inner then
        return inner
    end
    return t
end

---@param obj any 已解码的响应值
---@param req table 本次请求（提供长度限制与允许引用 id）
---@return string[]|nil segments
---@return string|nil reason 机器码：进 fallback:<reason> 日志
function PolishService.ValidateResponse(obj, req)
    if type(obj) ~= "table" then
        return nil, "not_object"
    end
    -- 顶层只允许 segments / replyToQuotedMessageId 两键，键名精确，别的键一律拒。
    -- ⚠️ 引擎的 cjson 解码会把「值为 JSON null」的键整个丢掉（2026-09-24 实测：
    -- {"segments":[…],"replyToQuotedMessageId":null} 解出来只有 1 个键，cjson.null
    -- 是编码用的哨兵函数、解码侧拿不到），所以「缺 quote 键」与「显式 null」等价——
    -- 无引用的合法响应必须放行，不能按多余/缺失字段拒掉。
    local count = 0
    for k in pairs(obj) do
        if k ~= "segments" and k ~= "replyToQuotedMessageId" then
            return nil, "key_set"
        end
        count = count + 1
    end
    if count < 1 or obj.segments == nil then
        return nil, "key_set"
    end

    local segs = obj.segments
    if type(segs) ~= "table" then
        return nil, "segments_type"
    end
    local count = 0
    for _ in ipairs(segs) do
        count = count + 1
    end
    if count < 1 or count > 3 then
        return nil, "segments_count"
    end
    -- 必须是 1..count 的连续数组（cjson 解出的异构表防「键值夹带」）
    for i = 1, count do
        if segs[i] == nil then
            return nil, "segments_sparse"
        end
    end

    local brief = req.brief == true
    local perMax = math.min(MAX_SEG_CHARS, req.maxCharsPerSegment or MAX_SEG_CHARS)
    local totalMax = math.min(MAX_TOTAL_CHARS, req.maxTotalChars or MAX_TOTAL_CHARS)
    if brief then
        perMax = math.min(perMax, BRIEF_SEG_CHARS)
    end

    local cleaned = {}
    local total = 0
    for i = 1, count do
        if type(segs[i]) ~= "string" then
            return nil, "segment_type"
        end
        local t = trim(segs[i])
        if t == "" then
            return nil, "segment_empty"
        end
        if hasForbiddenChar(t) then
            return nil, "segment_char"
        end
        local n2 = runeLen(t)
        if n2 > perMax then
            return nil, "segment_long"
        end
        total = total + n2
        cleaned[#cleaned + 1] = t
    end
    if total > totalMax then
        return nil, "total_long"
    end
    if brief and count > 1 then
        return nil, "brief_multi"
    end

    local qid = obj.replyToQuotedMessageId
    -- 解出来的 nil 就是 JSON null（键被解码器丢掉），按「无引用」处理
    if qid ~= nil then
        -- 无引用时 req.quote 是 cjson.null 哨兵（编码用函数），不能索引，只能按「无允许 id」处理
        local allowed = (type(req.quote) == "table" and req.quote.messageId) or nil
        if type(qid) ~= "number" or qid ~= math.floor(qid) or qid <= 0 then
            return nil, "quote_type"
        end
        if allowed == nil or qid ~= allowed then
            return nil, "quote_id"
        end
    end

    return cleaned, nil
end

-- =========================================================================
-- 事实词表守卫（最后一道）：别城、别事、白名单钟点之外都不放行
-- =========================================================================

---@param segments string[]
---@param req table
---@return string|nil reason
local function GuardFacts(segments, req)
    local otherCities = {}
    for _, city in pairs(TimeState.CITIES) do
        if city.label ~= req.core.cityLabel then
            otherCities[#otherCities + 1] = city.label
        end
    end
    local allowedTitles = { [req.deliveryFact.eventTitle] = true, [req.sendFact.eventTitle] = true }
    local otherTitles = {}
    for _, title in ipairs(EventService.KnownEventTitles()) do
        if not allowedTitles[title] then
            otherTitles[#otherTitles + 1] = title
        end
    end
    local allowedClocks = {
        [req.deliveryFact.clock] = true,
        [req.deliveryFact.endTime] = true,
        [req.sendFact.endTime] = true,
    }
    for _, s in ipairs(segments) do
        for _, city in ipairs(otherCities) do
            if s:find(city, 1, true) then
                return "guard_city"
            end
        end
        for _, title in ipairs(otherTitles) do
            if s:find(title, 1, true) then
                return "guard_event"
            end
        end
        for hhmm in s:gmatch("%d+:%d%d") do
            if not allowedClocks[hhmm] then
                return "guard_time"
            end
        end
    end
    for _, segment in ipairs(segments) do
        for _, code in utf8.codes(segment) do
            if code >= 0x4e00 and code <= 0x9fff then return "guard_language" end
        end
    end
    return nil
end

-- =========================================================================
-- 请求生命周期：FIFO 交付序 + 每条 8s 预算
-- =========================================================================

--- 按发起顺序把已 settled 或已超预算的槽位交付出去。
--- 只有队头能落地：保证她的回复到达顺序与用户消息的送达顺序一致。
---@param nowUtc number
local function Pump(nowUtc)
    while #slots_ > 0 do
        local slot = slots_[1]
        local segments, reason
        if slot.result and slot.result.ok then
            local obj = nil
            local okDecode = pcall(function()
                obj = cjson.decode(stripCodeFence(slot.result.bodyText or ""))
            end)
            if okDecode and obj then
                local v, why = PolishService.ValidateResponse(obj, slot.req)
                if v then
                    local guard = GuardFacts(v, slot.req)
                    if guard then
                        reason = guard
                    else
                        segments = v
                    end
                else
                    reason = "schema_" .. tostring(why)
                end
            else
                reason = "schema_json"
            end
        elseif slot.result then
            reason = slot.result.category or ("http_" .. tostring(slot.result.status or 0))
            if slot.result.status == 401 then
                hardOff_ = true -- 密钥不对：重试没有意义，本会话彻底闭口
            elseif slot.result.status == 503 then
                cooldownUntilUtc_ = nowUtc + COOLDOWN_SECONDS
            end
        elseif nowUtc >= slot.deadlineUtc then
            reason = "budget"
            slot.result = { ok = false, category = "budget" }
            logWarn("润色超预算未回（transport 未守约），回落模板并继续 FIFO")
        else
            break -- 队头还在预算内等结果：后面的不许插队
        end

        table.remove(slots_, 1)
        slot.delivered = true
        if segments then
            logInfo(string.format("润色 结果=llm 长度=%d 段数=%d",
                (#table.concat(segments)), #segments))
        else
            logInfo("润色 结果=fallback:" .. tostring(reason))
        end
        slot.onDone(segments, segments and "llm" or tostring(reason))
    end
end

--- 发起一次润色。onDone(segments|nil, category)：segments 为 nil 时 category 是回落原因。
--- 回调可能在返回前已同步发生（transport 立即失败 / 冷却中 / 预算已过）。
---@param opts { fact: EventFact, pending: MsgEntry, nowUtc: number }
---@param onDone fun(segments: string[]|nil, category: string): nil
function PolishService.Polish(opts, onDone)
    local nowUtc = opts.nowUtc
    if not PolishService.IsEnabled() then
        onDone(nil, "disabled")
        return
    end
    if nowUtc < cooldownUntilUtc_ then
        onDone(nil, "cooldown")
        return
    end
    local req = PolishService.BuildRequest(opts.fact, opts.pending, nowUtc)
    if not req then
        onDone(nil, "payload")
        return
    end
    slots_[#slots_ + 1] = {
        req = req,
        onDone = onDone,
        deadlineUtc = nowUtc + POLISH_BUDGET_SECONDS,
        settled = false,
        delivered = false,
    }
    local slot = slots_[#slots_]
    local okCall = pcall(function()
        transport_.request(req, function(result)
            if slot.delivered or slot.settled then
                return -- 已按预算回落：迟到的结果只丢弃，不许二次回调
            end
            slot.settled = true
            slot.result = result or { ok = false, category = "bad_result" }
        end)
    end)
    if not okCall then
        slot.result = { ok = false, category = "transport_error" }
        slot.settled = true
        logWarn("transport.request 抛异常，按网络错误回落")
    end
    Pump(nowUtc)
end

--- 每帧由主循环调用：推进预算超时与 FIFO 交付
---@param nowUtc number
function PolishService.Update(nowUtc)
    if #slots_ > 0 then
        Pump(nowUtc)
    end
end

--- 用户主动重置对话时取消仍在预算内的外部润色槽位。
--- transport 可能仍会在网络层返回，但 slots_ 已脱钩，迟到结果不会再回写新会话。
function PolishService.CancelAll()
    local count = #slots_
    slots_ = {}
    if count > 0 then
        logInfo("对话重置，已取消 " .. tostring(count) .. " 个在途润色请求")
    end
end

--- 还有几条回复在等润色结果（自检与「跳过等待」用）
---@return integer
function PolishService.GetPendingCount()
    return #slots_
end

return PolishService
