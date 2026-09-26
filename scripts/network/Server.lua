-- ============================================================================
-- network/Server.lua — LLM 中继（本工程唯一的出站 HTTP 出口，服务端专用）
--
-- ⚠️ 本文件必须带 .meta `"c_or_s": "s"`：API Key、上游地址、系统提示词与限流预算
--    只允许存在于这里，不能进入客户端包、日志、UI 文本或 RemoteEvent 参数。
--
-- 它只做四件事：
--   1) 校验信封（形状 + 尺寸），拒绝不像白名单 payload 的输入；
--   2) 限流（每连接每分钟）与日预算——防有人反编译客户端后把它当免费 LLM 代理；
--   3) 出站调上游，把 choices[1].message.content 原样回给客户端；
--   4) 不记录用户消息正文、模型输出正文与 Key，只记类别、尺寸与时延。
--
-- 事实权威仍在本地的 Lua（TimeState / EventService / MessageService）：模型只被允许
-- 把已经选定的事实用更自然的口气说出来；任何失败客户端立即回落本地模板，队列不阻塞。
--
-- 平台前提：客户端模式 HTTP 被完全屏蔽，服务端模式可用但受 URL 白名单约束，
-- 且白名单是**全字符串精确匹配**（engine-docs/recipes/http.md）。改 UPSTREAM_URL 的
-- 任何一个字符都要同步向 TapTap 制造团队更新白名单，否则请求在引擎层就被拦掉。
-- ============================================================================

local Shared = require("network.Shared")

local Server = {}

local TAG = "[LlmRelay]"

-- =========================================================================
-- 上游配置（服务端专有）
-- =========================================================================

--- 白名单必须精确到这一整串（含协议、域名、路径，不含查询参数）
local UPSTREAM_URL = "https://api.deepseek.com/chat/completions"
-- DeepSeek 当前 OpenAI 兼容模型；deepseek-chat 已在官方退役计划后不可作为新接入目标。
local UPSTREAM_MODEL = "deepseek-v4-flash"

--- ⚠️ API Key 只允许放在这一行。
--- 留空时中继直接回 not_configured，客户端回落模板——即「没配 key」与「没接 LLM」
--- 行为一致，不会报错、不会静默超时。
--- 请不要把 key 贴进任何对话、提交信息、文档或客户端模块。
local LLM_API_KEY = ""

--- 系统提示词是构建期常量（对应 M2-B 设计 §7），不是用户数据，也不来自客户端。
--- 客户端送来的只有事实区块（白名单 payload），提示词与模型名由服务端固定。
local SYSTEM_PROMPT = table.concat({
    "你是「林若夕」，一位生活在既定城市的原创角色，正在用中文聊天软件与对方交流。",
    "下面会给你一段 JSON，描述此刻已经确定发生的「事实」。请把既定事实说成自然、克制、生活化的中文聊天口语。",
    "硬性规则：",
    "1. 只允许表达「事实」里出现的内容；不得新增城市、事件、时间、关系历史、承诺或任何私人事实。",
    "2. 优先回应其中的「对方消息」或被引用内容，但不要机械复述。",
    "3. 说 1–3 句短句就好，不必长篇；不确定时保守、含糊也可以。",
    "4. 不声称记得未提供的历史；不承诺现实中的行动；不扮演真人或任何现有作品中的角色。",
    "5. 输出只能是下面这个 JSON，不要 Markdown 围栏、不要解释、不要额外字段：",
    '{"segments": ["短句一", "短句二"], "replyToQuotedMessageId": <数字或null>}',
}, "\n")

-- =========================================================================
-- 限额（演示级：单实例、内存计数，无数据库）
-- =========================================================================

--- 每条连接的固定窗口限流（设计 §4：默认 2 req/min）
local PER_CONNECTION_PER_MINUTE = 2
--- 全局日预算（按「请求条数」计；上游 token 用量只进日志、不做硬闸）
local DAILY_REQUEST_BUDGET = 200
--- 上游超时；客户端那侧还有 8 秒总预算，到点必回落
-- 不得晚于客户端的 7 秒中继预算；客户端回落后继续耗费上游额度没有产品价值。
local UPSTREAM_TIMEOUT_MS = 6500

-- =========================================================================
-- 状态
-- =========================================================================

--- 中继专用的空场景：引擎要求联网必须有 Scene 作为同步媒介
--- （network-game-guide §11.2），但它只用来承载连接，不参与任何渲染与玩法。
---@type Scene
local relayScene_ = nil

---@type table<string, { windowStart: number, count: integer }>
local buckets_ = {}
---@type integer
local budgetDay_ = -1
---@type integer
local budgetCount_ = 0

local function logInfo(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_INFO, TAG .. " " .. msg)
end

--- 回落路径一律 WARN：契约里「网络坏、上游拒、超预算」都是设计内收尾，不是故障。
--- 项目的判据是 runtime.log 里 ERROR = 0 ⟺ 自检全绿，这里报 ERROR 会把负路径变成常态噪音。
local function logWarn(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_WARNING, TAG .. " " .. msg)
end

--- 服务端侧秒级 UTC：与客户端同源（common.get_server_time()），避免用设备本地时间
---@return number
local function NowUtc()
    return common.get_server_time()
end

-- =========================================================================
-- 限额判定
-- =========================================================================

--- 按连接取一个稳定的限额桶键：地址 + 端口。用地址而不是昵称，
--- 因为限流必须在身份建立之前就能生效。
---@param connection Connection
---@return string
local function BucketKey(connection)
    local ok, key = pcall(function()
        return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
    end)
    if ok and type(key) == "string" then
        return key
    end
    return "unknown"
end

---@param connection Connection
---@param nowUtc number
---@return boolean allowed
---@return string category
local function AllowRate(connection, nowUtc)
    local key = BucketKey(connection)
    local bucket = buckets_[key]
    if not bucket or nowUtc - bucket.windowStart >= 60 then
        buckets_[key] = { windowStart = nowUtc, count = 1 }
        return true, ""
    end
    if bucket.count >= PER_CONNECTION_PER_MINUTE then
        return false, "rate_limited"
    end
    bucket.count = bucket.count + 1
    return true, ""
end

---@param nowUtc number
---@return boolean allowed
---@return string category
local function AllowBudget(nowUtc)
    local day = math.floor(nowUtc / 86400)
    if day ~= budgetDay_ then
        budgetDay_ = day
        budgetCount_ = 0
    end
    if budgetCount_ >= DAILY_REQUEST_BUDGET then
        return false, "budget_exhausted"
    end
    budgetCount_ = budgetCount_ + 1
    return true, ""
end

-- =========================================================================
-- 应答
-- =========================================================================

---@param connection Connection
---@param requestId string
---@param ok boolean
---@param status integer
---@param body string
---@param category string
local function Reply(connection, requestId, ok, status, body, category)
    local data = VariantMap()
    data["RequestId"] = Variant(requestId)
    data["Ok"] = Variant(ok)
    data["Status"] = Variant(status)
    data["Body"] = Variant(body)
    data["Category"] = Variant(category)
    connection:SendRemoteEvent(Shared.EVENTS.REPLY, true, data)
end

-- =========================================================================
-- 出站
-- =========================================================================

--- 上游 OpenAI 兼容请求体：模型、提示词、上限全部由服务端决定，客户端无从干预。
---@param payloadJson string
---@return string
local function BuildUpstreamBody(payloadJson)
    local ok, json = pcall(cjson.encode, {
        model = UPSTREAM_MODEL,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            -- 事实区块整体作为一条 user 消息；模型被要求只依据它说话
            { role = "user", content = payloadJson },
        },
        max_tokens = 250,
        temperature = 0.7,
        stream = false,
        response_format = { type = "json_object" },
    })
    if ok and type(json) == "string" then
        return json
    end
    return ""
end

--- 从上游回包里取出模型输出文本（choices[1].message.content）。
--- 只判「取不取得到」；句法契约仍由客户端 PolishService.ValidateResponse 做最后一道，
--- 服务端不替它放行——两道校验各自独立。
---@param bodyText string
---@return string|nil content
---@return string|nil reason
local function ExtractContent(bodyText)
    local ok, decoded = pcall(cjson.decode, bodyText)
    if not ok or type(decoded) ~= "table" then
        return nil, "upstream_json"
    end
    local choices = decoded.choices
    if type(choices) ~= "table" or type(choices[1]) ~= "table" then
        return nil, "upstream_shape"
    end
    local message = choices[1].message
    if type(message) ~= "table" or type(message.content) ~= "string" or message.content == "" then
        return nil, "upstream_shape"
    end
    if #message.content > Shared.MAX_BODY_BYTES then
        return nil, "upstream_large"
    end
    return message.content, nil
end

---@param connection Connection
---@param requestId string
---@param payloadJson string
---@param nowUtc number
local function CallUpstream(connection, requestId, payloadJson, nowUtc)
    local bodyJson = BuildUpstreamBody(payloadJson)
    if bodyJson == "" then
        Reply(connection, requestId, false, 500, "", "relay_encode")
        return
    end

    local startedAt = nowUtc
    local client = http:Create()
    client:SetUrl(UPSTREAM_URL)
    client:SetMethod(HTTP_POST)
    client:SetContentType("application/json")
    client:AddHeader("Authorization", "Bearer " .. LLM_API_KEY)
    client:SetTimeout(UPSTREAM_TIMEOUT_MS)
    client:SetBody(bodyJson)
    client:OnSuccess(function(_, response)
        local elapsed = math.floor(NowUtc() - startedAt)
        -- 上游 2xx 也要看体：模型确实可能回一段不是约定 JSON 的文本
        local content, why = ExtractContent(response.dataAsString or "")
        if content then
            logInfo(string.format("上游成功 请求=%s 用时=%ds 正文=%d 字节",
                requestId, elapsed, #content))
            Reply(connection, requestId, true, 200, content, "")
        else
            logWarn(string.format("上游体不合形状 请求=%s 类别=%s 用时=%ds",
                requestId, tostring(why), elapsed))
            Reply(connection, requestId, false, 502, "", tostring(why))
        end
    end)
    client:OnError(function(_, statusCode, error)
        local elapsed = math.floor(NowUtc() - startedAt)
        -- 401 = key 不对，重试没有意义；客户端那边会据此本会话闭口
        local category = (statusCode == 401) and "unauthorized" or "upstream_error"
        logWarn(string.format("上游失败 请求=%s 状态=%s 类别=%s 用时=%ds 错误=%s",
            requestId, tostring(statusCode), category, elapsed, tostring(error)))
        Reply(connection, requestId, false, statusCode or 0, "", category)
    end)
    client:Send()
end

-- =========================================================================
-- 事件
-- =========================================================================

--- 客户端就绪：引擎要求「客户端先赋 scene 再上报，服务端收到后才赋 scene」
--- （network-game-guide §11.1）。本中继不复制任何节点，这个空场景只是连接媒介。
---@param eventType string
---@param eventData VariantMap
function HandleRelayReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    connection.scene = relayScene_
    logInfo("客户端就绪，连接已绑定中继场景")
end

---@param eventType string
---@param eventData VariantMap
function HandlePolishRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local requestId = eventData["RequestId"]:GetString()
    local payloadJson = eventData["Payload"]:GetString()

    if LLM_API_KEY == "" then
        logWarn("未配置上游 Key，中继回 not_configured（客户端回落模板）")
        Reply(connection, requestId, false, 503, "", "not_configured")
        return
    end

    local payload, why = Shared.DecodePayload(payloadJson)
    if not payload then
        logWarn("丢弃不合形状的请求 请求=" .. tostring(requestId) .. " 类别=" .. tostring(why))
        Reply(connection, requestId, false, 400, "", "invalid_request")
        return
    end

    local nowUtc = NowUtc()
    local allowed, category = AllowRate(connection, nowUtc)
    if not allowed then
        logWarn("限流命中 请求=" .. tostring(requestId))
        Reply(connection, requestId, false, 429, "", category)
        return
    end
    allowed, category = AllowBudget(nowUtc)
    if not allowed then
        logWarn("日预算耗尽 请求=" .. tostring(requestId))
        Reply(connection, requestId, false, 503, "", category)
        return
    end

    logInfo(string.format("收到润色请求 请求=%s 载荷=%d 字节", tostring(requestId), #payloadJson))
    CallUpstream(connection, requestId, payloadJson, nowUtc)
end

---@param eventType string
---@param eventData VariantMap
function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    -- ⚠️ 这里不能赋 scene：客户端还没准备（network-game-guide §11.1）
    logInfo("客户端接入 " .. BucketKey(connection))
end

---@param eventType string
---@param eventData VariantMap
function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    buckets_[BucketKey(connection)] = nil
    logInfo("客户端断开 " .. BucketKey(connection))
end

-- =========================================================================
-- 生命周期
-- =========================================================================

function Server.Start()
    -- 中继不渲染、不复制节点，空场景只是联网媒介
    relayScene_ = Scene()
    Shared.RegisterServerEvents()
    SubscribeToEvent(Shared.EVENTS.READY, "HandleRelayReady")
    SubscribeToEvent(Shared.EVENTS.REQUEST, "HandlePolishRequest")
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    logInfo(string.format("中继就绪 上游=%s 模型=%s key=%s 限流=%d/分 日预算=%d",
        UPSTREAM_URL, UPSTREAM_MODEL,
        LLM_API_KEY == "" and "未配置" or "已配置",
        PER_CONNECTION_PER_MINUTE, DAILY_REQUEST_BUDGET))
end

function Server.Stop()
    local pending = 0
    local ok, count = pcall(function()
        return http:GetActiveRequestCount()
    end)
    if ok and type(count) == "number" then
        pending = count
    end
    if pending > 0 then
        http:CancelAllRequests()
        logInfo("退出：取消 " .. tostring(pending) .. " 个在途上游请求")
    end
end

-- 仅暴露给服务端自检：重置限额计数（不碰 Key 与场景）
function Server.ResetLimitsForTest()
    buckets_ = {}
    budgetDay_ = -1
    budgetCount_ = 0
end

-- 仅暴露给服务端自检：从上游回包里取模型输出，便于用假回包逐条验形状拒绝
---@param bodyText string
---@return string|nil content
---@return string|nil reason
function Server.ExtractContentForTest(bodyText)
    return ExtractContent(bodyText)
end

---@return integer
function Server.PerMinuteLimit()
    return PER_CONNECTION_PER_MINUTE
end

---@return integer
function Server.DailyBudget()
    return DAILY_REQUEST_BUDGET
end

return Server
