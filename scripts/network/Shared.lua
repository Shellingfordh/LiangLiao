-- ============================================================================
-- network/Shared.lua — LLM 中继的两端共享契约（事件名 + 信封 + 注册函数）
--
-- 分工（M2-B 路径 A：服务端直连上游模型）：
--   客户端 Lua ──RemoteEvent(Request)──> 服务端 Lua ──HTTP──> DeepSeek
--   客户端 Lua <──RemoteEvent(Reply)─── 服务端 Lua <──HTTP────
-- 客户端 HTTP 被平台完全屏蔽（engine-docs/recipes/http.md），所以出站只能由服务端做。
--
-- 本文件被两端同时加载，**只放两端都要用的东西**：事件名、信封字段、编解码与尺寸上限。
-- ⚠️ 服务端专有物（API Key、上游 URL、系统提示词、限流预算）一律在 network/Server.lua，
--    该文件带 .meta `"c_or_s": "s"`，不会打进客户端包。
-- ⚠️ 这里不出现任何密钥；信封里也不传模型名与提示词——那些由服务端固定，
--    客户端只交白名单事实（PolishService.BuildRequest 的产物）。
-- ============================================================================

local Shared = {}

-- =========================================================================
-- 事件名
-- =========================================================================

Shared.EVENTS = {
    --- 客户端 → 服务端：一条润色请求
    REQUEST = "RuoxiLlmPolishRequest",
    --- 服务端 → 客户端：对应的结果（成功或机器码失败）
    REPLY = "RuoxiLlmPolishReply",
    --- 客户端 → 服务端：放弃某条在途请求（本地超时 / 主动停止）。
    --- 服务端收到后取消对应上游请求，结果不再交付——双向收口，
    --- 免得玩家已经在本地回落模板了，上游额度还在被这条请求消耗。
    CANCEL = "RuoxiLlmPolishCancel",
    --- 客户端 → 服务端：连接就绪握手（引擎要求的远端事件时序，见 network-game-guide §11.1）
    READY = "RuoxiLlmRelayReady",
}

-- 服务端要接收的事件（客户端发的）
Shared.SERVER_EVENTS = {
    Shared.EVENTS.REQUEST,
    Shared.EVENTS.CANCEL,
    Shared.EVENTS.READY,
}

-- 客户端要接收的事件（服务端发的）
Shared.CLIENT_EVENTS = {
    Shared.EVENTS.REPLY,
}

--- 单条请求的 JSON 上限（设计 §4 的 16KB 是网关口径；RemoteEvent 走的是游戏连接，
--- 白名单 payload 正常在 1–2KB，这里留一倍余量并在超限时直接回落模板）
Shared.MAX_PAYLOAD_BYTES = 4096

--- 同一 requestId 的幂等窗口（设计 §4）：5 分钟内重复请求复用在途或已完成结果，
--- 不重复扣预算、不重复请求模型。
Shared.IDEMPOTENCY_WINDOW_SECONDS = 300

--- requestId 形状：`c-<序号>-<发起时刻 UTC 秒>`（两端共用一份判定）。
--- 服务端在解 payload 之前先按它挡掉不像 id 的字符串——幂等表的键不能是任意串。
---@param requestId any
---@return boolean
function Shared.IsValidRequestId(requestId)
    if type(requestId) ~= "string" or #requestId > 40 then
        return false
    end
    return requestId:match("^c%-%d+%-%d+$") ~= nil
end

--- 上游回包只取 choices[1].message.content，长度另设上限防异常体
Shared.MAX_BODY_BYTES = 8192

-- =========================================================================
-- 注册：接收方必须注册，否则日志报 "Discarding not allowed remote event"
-- =========================================================================

function Shared.RegisterServerEvents()
    for _, eventName in ipairs(Shared.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

function Shared.RegisterClientEvents()
    for _, eventName in ipairs(Shared.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

-- =========================================================================
-- 信封编解码
--
-- 请求信封（VariantMap）：RequestId=String, Payload=String(白名单 payload 的 JSON 文本)
-- 应答信封（VariantMap）：RequestId=String, Ok=Bool, Status=Int, Body=String, Category=String
-- 之所以把 payload 压成一段 JSON 字符串，是因为它是一种嵌套结构
-- （core / deliveryFact / sendFact / quote），Variant 只支持平铺的标量与向量。
-- =========================================================================

--- 请求 id：一次会话内自增 + 发起时刻，仅用于把应答配回请求槽位
---@param seq integer
---@param nowUtc number
---@return string
function Shared.MakeRequestId(seq, nowUtc)
    return string.format("c-%d-%d", seq, math.floor(nowUtc))
end

---@param payload table
---@return string|nil json
---@return string|nil reason
function Shared.EncodePayload(payload)
    if type(payload) ~= "table" then
        return nil, "payload_type"
    end
    local ok, json = pcall(cjson.encode, payload)
    if not ok or type(json) ~= "string" then
        return nil, "payload_encode"
    end
    if #json > Shared.MAX_PAYLOAD_BYTES then
        return nil, "payload_too_large"
    end
    return json, nil
end

---@param json string
---@return table|nil payload
---@return string|nil reason
function Shared.DecodePayload(json)
    if type(json) ~= "string" or json == "" then
        return nil, "empty"
    end
    if #json > Shared.MAX_PAYLOAD_BYTES then
        return nil, "payload_too_large"
    end
    local ok, obj = pcall(cjson.decode, json)
    if not ok or type(obj) ~= "table" then
        return nil, "payload_json"
    end
    return obj, nil
end

return Shared
