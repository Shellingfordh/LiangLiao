-- 无感联机入口：不展示 Maker 默认大厅。它自动创建单人房；失败后仍启动原单机体验。
local UI = require("urhox-libs.UI")

local CONNECT_TIMEOUT_SECONDS = 8

return function(ctx)
    local client = ctx.client
    local root = ctx.root
    local state_ = "connecting"
    local elapsed_ = 0
    local disposed_ = false
    local startedGame_ = false
    local statusLabel_ = nil
    local glow_ = nil
    local view = nil

    local function SetStatus(text)
        if statusLabel_ then
            statusLabel_:SetText(text)
        end
    end

    local function StartOffline(reason)
        if disposed_ or startedGame_ then
            return
        end
        startedGame_ = true
        state_ = "offline"
        SetStatus("信号不太好，先按原来的方式陪你聊")
        view.visible = false
        -- lobby_runtime 本身处在完整 Runtime；复用现有单机入口，不创建第二套玩法。
        -- main.lua 的 LlmRelayEnabled 仍为 false，因此这条路径没有任何外发。
        require("main")
        Start()
    end

    local function StartOnline()
        if disposed_ or startedGame_ then
            return
        end
        startedGame_ = true
        state_ = "entering"
        SetStatus("她正在接通")
        client:StartGame({
            onProgress = function(progress)
                if statusLabel_ and progress and progress >= 0.7 then
                    SetStatus("快到了")
                end
            end,
            onError = function()
                startedGame_ = false
                StartOffline("start_game_error")
            end,
        })
    end

    local function BeginRoom()
        if disposed_ or state_ ~= "connecting" then
            return
        end
        client:CreateRoom({
            onCreated = function()
                -- 房主身份以持续的 onPlayersChanged 为准，不能在 onCreated 时猜测。
                SetStatus("她正在接通")
            end,
            onPlayersChanged = function(_, masterId)
                if masterId == client:GetMyUserId() then
                    StartOnline()
                end
            end,
            onError = function()
                StartOffline("create_room_error")
            end,
            onKicked = function()
                StartOffline("room_kicked")
            end,
        })
    end

    view = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column",
        alignItems = "center", justifyContent = "center",
        backgroundColor = { 16, 20, 38, 255 },
    }
    glow_ = UI.Panel {
        width = 18, height = 18, borderRadius = 9,
        backgroundColor = { 183, 225, 220, 200 },
    }
    statusLabel_ = UI.Label {
        text = "正在靠近若夕…", fontSize = 18,
        fontColor = { 238, 244, 241, 255 }, height = 32,
    }
    view:AddChild(glow_)
    view:AddChild(statusLabel_)
    root:AddChild(view)

    function HandleCompanionLobbyUpdate(eventType, eventData)
        if disposed_ then
            return
        end
        local dt = eventData["TimeStep"]:GetFloat()
        elapsed_ = elapsed_ + dt
        if glow_ then
            local alpha = 110 + math.floor((math.sin(elapsed_ * 3) + 1) * 65)
            glow_.opacity = alpha / 255
        end
        if state_ == "connecting" and elapsed_ >= CONNECT_TIMEOUT_SECONDS then
            StartOffline("connect_timeout")
        end
    end

    SubscribeToEvent("Update", "HandleCompanionLobbyUpdate")
    client:OnError(function()
        if state_ == "connecting" or state_ == "entering" then
            StartOffline("platform_error")
        end
    end)
    BeginRoom()

    return {
        stop = function()
            disposed_ = true
            client:OnError(nil)
            UnsubscribeFromEvent("Update")
        end,
    }
end
