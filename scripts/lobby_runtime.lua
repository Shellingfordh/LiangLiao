-- ============================================================================
-- lobby_runtime.lua — 无感联机入口（Maker 自定义大厅「完全自建」路径）
--
-- 玩家看到的仍然是「单机冷启动」：Maker 的默认五屏大厅、匹配、房间列表、
-- 等待房间一个都不出现。联机在这里只是给 LLM 润色拿一个**服务端出口**，
-- 产品仍然是一个人的陪伴体验（设计 docs/superpowers/specs/2026-09-27-seamless-online-lobby-design.md）。
--
-- 流程：
--   connecting ──自动 CreateRoom（房内只有自己）──> entering ──StartGame──> 引擎切到 main.lua（联机客户端）
--        └────────── 失败 / 8 秒无结果 / 被踢 / 平台异步错误 ─────────> 同一套本地游戏 main.lua（relay 不注入）
--
-- 生命周期纪律（逐条对应设计 §3 与验收 §6）：
--   · **不建第二份 3D 场景**：本文件不创建 Scene / Viewport，loading 只是
--     urhox-libs/UI 的轻量控件树（底色面板 + 呼吸光点 + 文案 + 跳过键）。
--     唯一的 3D 状态窗属于 main.lua，交接前不存在第二份。
--   · **只有一个 Update 订阅**：按全局名字订阅（本工程实测只有按名字订阅会派发，
--     见 AGENTS.md「本地运行时与云端验证的分工」边界 3）。交接前先注销，
--     保证任何时刻全进程只有 main.lua 那一条逐帧订阅。
--   · **stop() 必清**：注销 Update、注销平台回调（client:OnError / 系统通知 handler），
--     并销毁自己建的控件；teardown 幂等，正常交接与 stop 先后发生都不会重复拆。
--   · **主操作走 OnPointerDown + 实例级 focusable = false**：AGENTS.md 实测的两条坑
--     （软键盘失焦改布局 → OnClick 静默无效；focusable 只有实例赋值才生效）。
-- ============================================================================

local UI = require("urhox-libs.UI")
local SystemNotification = require("urhox-libs.System.SystemNotification")

local TAG = "[SeamlessLobby]"

--- 建房 + 连服共用的总预算（设计 §3）：8 秒内没有确定结果就必须落到离线。
--- 「把玩家困在加载页」和「露出默认大厅」是同一条红线。
local CONNECT_BUDGET_SECONDS = 8

--- 与 main.lua 的 InitUI() 逐字同一份参数。离线回退会走进 main.Start()，
--- 两边共用同一次 UI.Init：loading 页与正式页面的缩放 / 主题才不会在交接那一帧跳变。
--- ⚠️ 改这里就要同步改 scripts/main.lua 的 InitUI，两处必须一致。
local UI_INIT_OPTIONS = { theme = "default-dark", scale = UI.Scale.DEFAULT }

--- 加载期「安静收尾」的系统通知：一律当接通失败处理，不让引擎默认弹窗盖在 loading 上。
--- VersionTooLow 故意不在表里——那是必须让玩家看见的系统提示，返回 false 交回引擎默认弹窗。
---@type table<string, boolean>
local SILENT_NOTIFICATION_IDS = {
    Kicked = true,
    GameOpsKick = true,
    DuplicateLogin = true,
    PlayerBanned = true,
    ResourceExceeded = true,
    DisconnectChecking = true,
    Reconnecting = true,
    ConnectFailedRetry = true,
    ConnectInitiateFailed = true,
    MiddleGameJoinFailed = true,
}

local function logInfo(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_INFO, TAG .. " " .. msg)
end

--- 回落是设计内的正常收尾，不是故障：ERROR 留给真异常
--- （项目判据 runtime.log 里 ERROR = 0 ⟺ 自检全绿）。
local function logWarn(msg)
    print(TAG .. " " .. msg)
    log:Write(LOG_WARNING, TAG .. " " .. msg)
end

return function(ctx)
    local client = ctx.client
    local root = ctx.root

    --- connecting（自动建房）| entering（连服）| done（已交接，本文件不再动作）
    local state_ = "connecting"
    local elapsed_ = 0
    local handedOff_ = false        -- 已交接给 main.lua：此后本文件不做任何事
    local startGameRequested_ = false
    local engineOwnsIt_ = false     -- 平台已给出确定结果：切脚本归引擎，8 秒兜底不再抢
    local notificationRegistered_ = false
    local tornDown_ = false
    local glowPhase_ = 0

    ---@type Widget|nil
    local view = nil
    ---@type Label|nil
    local statusLabel = nil
    ---@type Widget|nil
    local glow = nil

    -- ========================================================================
    -- 清理
    -- ========================================================================

    --- 注销大厅自己的全部订阅与回调，并销毁 loading 控件。幂等。
    local function teardown()
        if tornDown_ then
            return
        end
        tornDown_ = true
        -- 全局名字订阅的那一条 Update：不注销就会把整个闭包吊在事件总线上，
        -- 交接后与 main.lua 的 HandleUpdate 并存 = 两份逐帧订阅。
        UnsubscribeFromEvent("Update")
        client:OnError(nil)
        if notificationRegistered_ then
            SystemNotification.UnregisterHandler()
            notificationRegistered_ = false
        end
        if view then
            -- Destroy 先拆子树、再从 parent 摘掉；引擎托管的 root 不用我们回收
            view:Destroy()
            view = nil
            statusLabel = nil
            glow = nil
        end
    end

    local function setStatus(text)
        if statusLabel then
            statusLabel:SetText(text)
        end
    end

    -- ========================================================================
    -- 两条出口
    -- ========================================================================

    --- 失败 / 超时 / 被踢 / 平台异步错误：收起 loading，进入同一套本地游戏。
    --- 这条路径不注入 relay transport：CONFIG.LlmRelayEnabled 仍是 false，
    --- 而且此刻并没有游戏服务器连接，network.Client.Start() 本来也不会成立。
    local function goOffline(reason)
        if handedOff_ then
            return
        end
        handedOff_ = true
        state_ = "done"
        logWarn(string.format("未接通服务端（%s），回落本地游戏，润色继续走模板", tostring(reason)))
        teardown()
        local ok, err = pcall(function()
            require("main")
            Start()
        end)
        if not ok then
            logWarn("本地游戏启动失败：" .. tostring(err))
        end
    end

    --- 房主开始游戏：链路同 StartMatch，成功后引擎自己切到 main.lua（联机客户端）。
    local function startGame()
        if handedOff_ or startGameRequested_ then
            return
        end
        startGameRequested_ = true
        state_ = "entering"
        setStatus("她正在接通")
        client:StartGame {
            onMatchFound = function()
                -- 平台已经给出确定结果：后面的连服与切脚本由引擎接管，
                -- 我们的 8 秒兜底到此为止（再抢先回落就等于在同一进程里起第二局）。
                engineOwnsIt_ = true
            end,
            onProgress = function(progress)
                if handedOff_ then
                    return
                end
                if type(progress) == "number" and progress >= 1 then
                    engineOwnsIt_ = true
                end
                -- 不显示平台下发的 status 原文（那是内部文案），也不伪造精确百分比：
                -- 只按真实进度换一句更近的话，进度本身由光点呼吸表达。
                if type(progress) == "number" and progress >= 0.6 then
                    setStatus("快到了")
                end
            end,
            onError = function(code, message)
                goOffline(string.format("start_game_error_%s/%s",
                    tostring(code), tostring(message)))
            end,
        }
    end

    --- 建房：房里只有自己，房主身份以持续的 onPlayersChanged 为准（不在 onCreated 时猜）。
    local function beginRoom()
        client:CreateRoom {
            onCreated = function()
                setStatus("她正在接通")
            end,
            onPlayersChanged = function(players, masterId)
                if handedOff_ or startGameRequested_ then
                    return
                end
                if masterId == client:GetMyUserId() then
                    logInfo(string.format("单人房已就绪（房内 %d 人），开始进入游戏",
                        players and #players or 0))
                    startGame()
                end
            end,
            onError = function(code, message)
                goOffline(string.format("create_room_error_%s/%s",
                    tostring(code), tostring(message)))
            end,
            onKicked = function()
                goOffline("room_kicked")
            end,
        }
    end

    -- ========================================================================
    -- loading 界面（轻量控件，无 3D）
    -- ========================================================================

    -- 与 main.lua 的 InitUI 同一份参数；已经初始化过就不重复 Init
    -- （UI.Init 二次调用会被忽略并在日志里打 WARNING）。
    if not UI.GetNVGContext() then
        UI.Init(UI_INIT_OPTIONS)
    end
    -- 模板路径（LobbyUI.Show）在 UI 根尚未建立时会把大厅根设为 UI 根；完全自建
    -- 这条同理——引擎没替我们 SetRoot 时，loading 才不会挂在一棵没人渲染的树上。
    -- 引擎已经建过根就一点都不碰。
    if not UI.GetRoot() then
        UI.SetRoot(root)
    end

    local viewWidget = UI.Panel {
        id = "seamlessLobbyRoot",
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center", justifyContent = "center",
        gap = 24,
        backgroundColor = { 16, 20, 38, 255 },
    }
    local glowWidget = UI.Panel {
        width = 16, height = 16, borderRadius = 8,
        backgroundColor = { 183, 225, 220, 255 },
        opacity = 0.5,
    }
    local statusWidget = UI.Label {
        id = "seamlessLobbyStatus",
        text = "正在靠近若夕…",
        fontSize = 18,
        fontColor = { 238, 244, 241, 235 },
        height = 30,   -- 写死高度：文案变化不许改容器高度（AGENTS.md 规则 ③）
    }
    -- 加载页的主操作：不必等满 8 秒。命中即回调，不等抬起。
    local skipWidget = UI.Button {
        id = "seamlessLobbySkip",
        text = "先不接通",
        fontSize = 14,
        height = 34,
        minWidth = 132,
        focusable = false,
    }
    skipWidget.focusable = false   -- ⚠️ 只有实例赋值才生效，属性那道是装饰
    function skipWidget:OnPointerDown(event)
        if not event or not event:IsPrimaryAction() then
            return
        end
        self:SetState({ pressed = true })
        self:TransitionToStateBgColor()
        goOffline("user_skip")
    end

    viewWidget:AddChild(glowWidget)
    viewWidget:AddChild(statusWidget)
    viewWidget:AddChild(skipWidget)
    root:AddChild(viewWidget)

    view = viewWidget
    glow = glowWidget
    statusLabel = statusWidget

    -- ========================================================================
    -- 唯一的一条 Update 订阅
    -- ========================================================================

    --- 定义在入口函数内部是为了闭包持有本次大厅的局部状态；函数名是全局的，
    --- 所以 teardown 里必须按名字注销，否则闭包会留在事件总线上。
    ---@param eventType string
    ---@param eventData UpdateEventData
    function HandleSeamlessLobbyUpdate(eventType, eventData)
        if handedOff_ then
            return
        end
        local dt = eventData["TimeStep"]:GetFloat()
        elapsed_ = elapsed_ + dt
        glowPhase_ = glowPhase_ + dt
        if glow then
            -- 呼吸光点：只改不透明度，不碰布局、不改任何容器高度
            local wave = (math.sin(glowPhase_ * 2.4) + 1) * 0.5
            glow.opacity = 0.35 + 0.45 * wave
        end
        if not engineOwnsIt_ and elapsed_ >= CONNECT_BUDGET_SECONDS then
            goOffline(state_ == "entering" and "start_game_timeout" or "create_room_timeout")
        end
    end

    SubscribeToEvent("Update", "HandleSeamlessLobbyUpdate")

    -- ========================================================================
    -- 平台回调
    -- ========================================================================

    client:OnError(function(errorType, errorCode)
        if handedOff_ then
            return
        end
        goOffline(string.format("platform_error_%s_%s",
            tostring(errorType), tostring(errorCode)))
    end)

    --- 加载期的系统通知：能安静收尾的一律收尾。返回 false 的交回引擎默认弹窗。
    ---@param info SystemNotificationInfo
    ---@return boolean
    local function onSystemNotification(info)
        local id = info and info.id or nil
        if type(id) ~= "string" or not SILENT_NOTIFICATION_IDS[id] then
            return false
        end
        goOffline("system_notification_" .. id)
        return true
    end
    SystemNotification.RegisterHandler(onSystemNotification)
    notificationRegistered_ = true

    logInfo("无感联机入口启动：自动建房 → 房主开局；"
        .. tostring(CONNECT_BUDGET_SECONDS) .. " 秒无结果回落本地游戏")
    beginRoom()

    return {
        stop = function()
            teardown()
        end,
    }
end
