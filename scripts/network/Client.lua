-- ============================================================================
-- network/Client.lua — LLM 中继的客户端一端（把白名单 payload 送出去、把结果收回来）
--
-- 它只实现一件事：PolishService 期望的 transport 接口
--     request(payload: table, callback: fun(result: PolishTransportResult))
-- 也就是说，本文件是「网络」与「润色适配层」之间唯一的接缝：
--   PolishService 负责事实白名单、句法校验、词表守卫、FIFO 与 8 秒预算；
--   本文件只负责把信封发出去、把结果配回来、超时则如实上报。
--
-- ⚠️ 这里不出现任何密钥：出站鉴权与上游地址全在服务端（network/Server.lua，c_or_s="s"）。
-- 客户端 HTTP 被平台完全屏蔽，本文件也从不直接访问网络，只发远程事件。
-- ============================================================================

local Shared = require("network.Shared")

local Client = {}

local TAG = "[LlmRelayClient]"

--- 单条请求在网络层的上限。必须小于 PolishService 的 8 秒总预算，
--- 否则预算先到、这条结果只会被当成「迟到」丢弃，用户白等。
local TRANSPORT_TIMEOUT_SECONDS = 7

---@class RelayPending
---@field callback fun(result: PolishTransportResult): nil
---@field deadlineUtc number

---@type Connection|nil
local serverConnection_ = nil
---@type Scene|nil
local relayScene_ = nil
---@type table<string, RelayPending>
local pending_ = {}
---@type integer
local seq_ = 0
---@type boolean
local started_ = false

--- 取时刻：默认取权威 UTC。刻意不走 TimeState.NowUtc()——那个值会被开发自检的时间
--- 投影拨动，拿它做过期判定会让「拨表」顺手把在途请求判死。
---@type fun(): number
local nowFn_ = function()
    return common.get_server_time()
end

local function logInfo(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_INFO, TAG .. " " .. msg)
end

--- 回落路径一律 WARN，理由同 PolishService：设计内的失败不该把 ERROR 变成常态噪音
local function logWarn(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_WARNING, TAG .. " " .. msg)
end

--- 交付一个槽位：每个请求至多回调一次，迟到的应答与超时不会互相覆盖。
---@param requestId string
---@param result PolishTransportResult
---@return boolean delivered
local function Settle(requestId, result)
    local entry = pending_[requestId]
    if not entry then
        return false
    end
    pending_[requestId] = nil
    entry.callback(result)
    return true
end

-- =========================================================================
-- 事件
-- =========================================================================

---@param eventType string
---@param eventData VariantMap
function HandleReply(eventType, eventData)
    local requestId = eventData["RequestId"]:GetString()
    local ok = eventData["Ok"]:GetBool()
    local body = eventData["Body"]:GetString()
    local category = eventData["Category"]:GetString()
    local status = eventData["Status"]:GetInt()

    if not ok and category == "" then
        category = "http_" .. tostring(status)
    end
    ---@type PolishTransportResult
    local result = { ok = ok, status = status, bodyText = body, category = category }
    if not Settle(requestId, result) then
        -- 已按超时回落过：结果只丢弃，不许二次回调
        logWarn("应答迟到被丢弃 请求=" .. tostring(requestId))
    end
end

--- 告诉服务端「这条我放弃了」：本地已经回落模板，别再为它烧上游额度。
--- 服务端据此取消在途 HTTP，结果一律不再交付（设计 §4 的双向收口）。
--- 连接已经没了就不发——那种情况由服务端的断线清理负责。
---@param requestId string
local function NotifyCancel(requestId)
    local connection = serverConnection_
    if not connection then
        return
    end
    local data = VariantMap()
    data["RequestId"] = Variant(requestId)
    local sent = pcall(function()
        connection:SendRemoteEvent(Shared.EVENTS.CANCEL, true, data)
    end)
    if not sent then
        logWarn("放弃请求的通知没发出去 请求=" .. tostring(requestId))
    end
end

--- 把在途请求一次性按某个类别结清：连接断了、模块停了都走这一条，
--- 不让每条各自耗满 7 秒才回落。
---@param category string
---@param notifyServer boolean 本地超时 / 主动停止要告知服务端取消；断线不必（连接已没）
---@return integer count
local function FailPending(category, notifyServer)
    local ids = {}
    for requestId in pairs(pending_) do
        ids[#ids + 1] = requestId
    end
    for _, requestId in ipairs(ids) do
        if notifyServer then
            NotifyCancel(requestId)
        end
        Settle(requestId, { ok = false, status = 0, category = category })
    end
    return #ids
end

---@param eventType string
---@param eventData VariantMap
function HandleServerDisconnected(eventType, eventData)
    serverConnection_ = nil
    local count = FailPending("disconnected", false)
    if count > 0 then
        logWarn("与服务器断开，已结清 " .. tostring(count) .. " 个在途请求")
    end
end

-- =========================================================================
-- 生命周期
-- =========================================================================

--- 只在「联机客户端」里调用；单机模式不进这里（没有服务器连接）。
---@return boolean ok
function Client.Start()
    if started_ then
        return true
    end
    if not IsClientMode() then
        return false
    end
    local connection = network:GetServerConnection()
    if not connection then
        logWarn("没有服务器连接，中继不启动（回复继续走本地模板）")
        return false
    end

    Shared.RegisterClientEvents()
    -- 引擎要求的时序：客户端先赋 scene，再上报就绪；服务端收到后才赋它那侧
    -- （network-game-guide §11.1）。本中继不复制节点，空场景只是联网媒介。
    relayScene_ = Scene()
    connection.scene = relayScene_
    serverConnection_ = connection

    SubscribeToEvent(Shared.EVENTS.REPLY, "HandleReply")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")
    connection:SendRemoteEvent(Shared.EVENTS.READY, true, VariantMap())

    started_ = true
    logInfo("中继已就绪（等待服务端确认）")
    return true
end

function Client.Stop()
    -- 主动停止是「玩家不会再等这条结果」的确定信号：先告知服务端取消，
    -- 否则服务端会把上游跑完，再回一条永远不会被使用的应答。
    FailPending("stopped", true)
    pending_ = {}
    serverConnection_ = nil
    relayScene_ = nil
    started_ = false
end

--- 每帧推进在途请求的过期判定。由 main.lua 的唯一 Update 订阅转发。
--- 刻意收在模块内部取时刻：过期判定必须与登记 deadline 用的是同一个钟，
--- 否则主循环那边的开发时间投影会把在途请求判死。
function Client.Update()
    -- pending_ 是 string 键的散列表，# 对它恒为 0，只能用 next 判空
    if next(pending_) == nil then
        return
    end
    local nowUtc = nowFn_()
    local ids = nil
    for requestId, entry in pairs(pending_) do
        if nowUtc >= entry.deadlineUtc then
            ids = ids or {}
            ids[#ids + 1] = requestId
        end
    end
    if not ids then
        return
    end
    -- 本地到点回落的同时告知服务端放弃：上游 6.5 秒超时虽然早于本地 7 秒，
    -- 但这条通知让「玩家已经不等了」成为一个确定事实，而不是靠时序推断。
    for _, requestId in ipairs(ids) do
        NotifyCancel(requestId)
        Settle(requestId, { ok = false, status = 0, category = "timeout" })
    end
    logWarn("网络层超时，回落模板 " .. tostring(#ids) .. " 条")
end

-- =========================================================================
-- transport（PolishService.Configure 注入的那个对象）
-- =========================================================================

---@return PolishTransport
function Client.CreateTransport()
    return {
        request = function(payload, callback)
            if not serverConnection_ then
                callback({ ok = false, status = 0, category = "no_connection" })
                return
            end
            local json, why = Shared.EncodePayload(payload)
            if not json then
                callback({ ok = false, status = 0, category = tostring(why) })
                return
            end
            seq_ = seq_ + 1
            local requestId = Shared.MakeRequestId(seq_, nowFn_())
            pending_[requestId] = {
                callback = callback,
                deadlineUtc = nowFn_() + TRANSPORT_TIMEOUT_SECONDS,
            }
            local data = VariantMap()
            data["RequestId"] = Variant(requestId)
            data["Payload"] = Variant(json)
            serverConnection_:SendRemoteEvent(Shared.EVENTS.REQUEST, true, data)
        end,
    }
end

---@return integer
function Client.GetPendingCount()
    local n = 0
    for _ in pairs(pending_) do
        n = n + 1
    end
    return n
end

--- 仅暴露给自检：换掉取时刻函数 / 直接喂一个假连接
---@param fn fun(): number
function Client.SetClockForTest(fn)
    nowFn_ = fn
end

--- 仅暴露给自检：把内部状态复位（重新 Start 前用）
function Client.ResetForTest()
    pending_ = {}
    serverConnection_ = nil
    relayScene_ = nil
    started_ = false
end

--- 仅暴露给自检：模拟「主动停掉」那一次批量结清（含发取消通知）
---@param category string
---@return integer count
function Client.FailPendingForTest(category)
    return FailPending(category, true)
end

--- 仅暴露给自检：用真路由发一条（会因没有 serverConnection_ 立刻回调 no_connection）
---@param payload table
---@param callback fun(result: PolishTransportResult): nil
function Client.RequestForTest(payload, callback)
    Client.CreateTransport().request(payload, callback)
end

--- 仅暴露给自检：不经真实连接，直接把一条请求登记进在途表并返回请求 id
---@param payloadJson string
---@param callback fun(result: PolishTransportResult): nil
---@return string requestId
function Client.EnqueueForTest(payloadJson, callback)
    seq_ = seq_ + 1
    local requestId = Shared.MakeRequestId(seq_, nowFn_())
    pending_[requestId] = {
        callback = callback,
        deadlineUtc = nowFn_() + TRANSPORT_TIMEOUT_SECONDS,
    }
    return requestId
end

--- 仅暴露给自检：把一条应答喂给 HandleReply 走的那条路（不经过网络）
---@param requestId string
---@param ok boolean
---@param status integer
---@param body string
---@param category string
function Client.FeedReplyForTest(requestId, ok, status, body, category)
    local data = VariantMap()
    data["RequestId"] = Variant(requestId)
    data["Ok"] = Variant(ok)
    data["Status"] = Variant(status)
    data["Body"] = Variant(body)
    data["Category"] = Variant(category)
    HandleReply("", data)
end

return Client
