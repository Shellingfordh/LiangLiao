-- Local English regression: memory APIs are virtualised to protect player saves.
local actualFile = File
local storage = {}
File = function(path, mode)
    if type(path) ~= "string" or path:sub(1, 7) ~= "memory/" then return actualFile(path, mode) end
    local f = {}
    function f:IsOpen() return mode == FILE_WRITE or storage[path] ~= nil end
    function f:WriteString(value) storage[path] = value end
    function f:ReadString() return storage[path] or "" end
    function f:Close() end
    function f:Dispose() end
    return f
end
local actualFS = fileSystem
fileSystem = setmetatable({
    FileExists = function(_, path) if path:sub(1,7) == "memory/" then return storage[path] ~= nil end return actualFS:FileExists(path) end,
    DirExists = function(_, path) if path == "memory" then return true end return actualFS:DirExists(path) end,
    CreateDir = function(_, path) if path == "memory" then return true end return actualFS:CreateDir(path) end,
    Delete = function(_, path) if path:sub(1,7) == "memory/" then storage[path] = nil return true end return actualFS:Delete(path) end,
}, {__index = actualFS})
common.get_server_time = function() return 1790928000 end
local lines = {}
local pass, fail = 0, 0
local function check(label, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1 end
    lines[#lines+1] = (ok and "PASS " or "FAIL ") .. label .. " " .. tostring(detail or "")
end
local function hasHan(s)
    for _, code in utf8.codes(s or "") do if code >= 0x4e00 and code <= 0x9fff then return true end end
    return false
end
require("urhox-libs/UI").Init({scale=1,fonts={{family="sans",weights={normal="C:/Windows/Fonts/arial.ttf",bold="C:/Windows/Fonts/arialbd.ttf"}}}})
require("main")
Start()
function RunEnglishChecks()
local ok, err = pcall(function()
    local selftest = require("services.DevSelfTest")
    local p, f, d, total = selftest.Result()
    check("Existing regression suite", f == 0 and d == total, string.format("%d passed, %d failed, %d/%d scenarios", p,f,d,total))
    for _, value in ipairs(selftest.Failures()) do lines[#lines+1] = "REGRESSION " .. value end
    local Profile = require("ProfileService")
    local Time = require("TimeState")
    local Events = require("services.EventService")
    local Content = require("services.ContentService")
    local Eliza = require("services.ElizaService")
    local English = require("EnglishText")
    for _, city in ipairs(Profile.CITY_ORDER) do
        for _, relation in ipairs(Profile.RELATION_ORDER) do
            Profile.Set(city,relation)
            local p = Profile.Get()
            check("Profile "..city.."/"..relation, not hasHan(p.identity..Profile.ProfileLine()..Profile.DefaultDraft()))
            Events.Init({cityId=city})
            local plan = Events.PlanFor(city,"2026-10-02")
            for _, occ in ipairs(plan.occurrences) do
                local fact = Events.FactFor(city,occ.startUtc + 20)
                for turn = 1, 4 do
                    local reply = Content.Reply(fact,"How is your day going?",turn)
                    check("Reply "..city.."/"..relation.."/"..occ.templateId.."/"..turn,not hasHan(reply) and not reply:find("{",1,true),reply)
                end
                local queued = Events.FactFor(city,occ.endUtc + 30, occ.startUtc+20)
                local reply = Content.Reply(queued,"Are you busy?",1)
                check("Queued facts "..occ.templateId,not hasHan(reply) and (not queued.queued or reply:find(queued.sentEventEndsAt,1,true)~=nil),reply)
            end
            check("Opening "..city.."/"..relation,not hasHan(Profile.OpeningLine(city,relation,Events.FactFor(city,plan.occurrences[1].endUtc+20).eventPhrase)))
        end
    end
    check("English input detection", Eliza.ReplyTail("I am TIRED", "", 1) ~= nil)
    local _, rule = Eliza.ReplyTail("I am thoughtful", "",1)
    check("No hunger substring match",rule ~= "food")
    local sample = '「今天好累」我在公寓把活动邮件和便签归到一起，水刚烧开。虽然不认识，但你说的我会认真听完。'
    local migrated = English.Translate(sample)
    check("Preserve quoted player text",migrated:find('今天好累',1,true)~=nil,migrated)
    check("Translate legacy reply around player quote",not hasHan((migrated:gsub('今天好累',''))),migrated)
    local queued = '「Are you busy」那会儿在赶项目，小册子版面校样到17:00就收了，隔了2 小时 35 分才回你。我在路上，刚把一个想法录进语音便签，等到站我再看仔细一点。'
    local migratedQueue = English.Translate(queued)
    check("Legacy queued reply",not hasHan(migratedQueue) and migratedQueue:find('17:00',1,true)~=nil,migratedQueue)
    local Memory = require("services.MemoryService")
    Memory.Init({saveFile="memory/english-fixture.json"})
    local fixture = {version=6,cityId="los_angeles",turns=1,firstServerTime=1790928000,lastServerTime=1790928000,lastFactId="la_cafe_open_mic",profile={cityId="los_angeles",relationId="stranger",initialized=true},messages={
        {id=1,role="user",text="今天好累",serverTime=1790928000,state="queued",statusText="已送达",availabilityLabelAtSend="在忙",phraseAtSend="在赶项目",planReplyAtUtc=1790938000,factKey="old-key"},
        {id=2,role="her",text=sample,serverTime=1790928001,state="replied",factId="la_apartment_morning_inbox",factKey="old-reply-key"}},eventLedger={{key="old-key",eventId="la_cafe_open_mic",title="咖啡馆的开放麦克风夜",sceneId="la_cafe",startUtc=12,endUtc=34,lastEventState="ended"}},eventPlans={}}
    storage["memory/english-fixture.json"] = cjson.encode(fixture)
    Memory.Load()
    local saved = Memory.Get()
    check("Old save user text unchanged",saved.messages[1].text=="今天好累")
    check("Old save IDs/time/queue unchanged",saved.messages[1].planReplyAtUtc==1790938000 and saved.messages[1].factKey=="old-key" and saved.messages[1].state=="queued")
    check("Old save generated text English",not hasHan(saved.messages[1].statusText..saved.messages[1].phraseAtSend..saved.eventLedger[1].title))
    local legacyPlan = {cityId="los_angeles",dateKey="2026-10-02",seedText="saved-seed",generatedAtUtc=123,occurrences={
        {occurrenceKey="saved-occurrence",templateId="la_studio_zine_layout",variantIndex=2,startUtc=1790928100,endUtc=1790938100,title="小册子版面校样",summary="在工作室完成小册子版面校样",emotion="专注、略紧张",phrase="工作室里在对小册子的最后一版校样",sceneId="la_studio",startClock="13:00",endClock="17:00"}}}
    Events.Init({cityId="los_angeles"})
    Events.Restore({legacyPlan})
    local restoredPlan = Events.PeekPlan("los_angeles","2026-10-02")
    local restoredOcc = restoredPlan.occurrences[1]
    check("Saved plan facts unchanged",restoredPlan.fromSave and restoredPlan.seedText=="saved-seed" and restoredPlan.generatedAtUtc==123 and restoredOcc.occurrenceKey=="saved-occurrence" and restoredOcc.variantIndex==2 and restoredOcc.startUtc==1790928100 and restoredOcc.endUtc==1790938100)
    check("Saved plan prose English",not hasHan(restoredOcc.title..restoredOcc.summary..restoredOcc.emotion..restoredOcc.phrase))
    check("Translation idempotent",English.Translate(migratedQueue)==migratedQueue)
    local UI = require("urhox-libs/UI")
    local Overlays = {require("ui.ProfileOverlay"),require("ui.SettingsOverlay"),require("ui.LifeCardsOverlay"),require("ui.ProfilePageOverlay")}
    local function hide() for _, overlay in ipairs(Overlays) do overlay.Hide() end end
    local function inspect(page)
        for i=1,4 do UI.Layout(); UI.Render() end
        local function walk(w,shown)
            shown = shown and w:IsVisible()
            if shown then
                local props=w.props or {}
                if type(props.text)=="string" and props.text~="" then
                    local text=props.text
                    local rect=w:GetAbsoluteLayout()
                    check(page.." English "..tostring(w.id or w.type),not hasHan(text),text)
                    if rect and rect.w > 0 and rect.h > 0 then
                        local fit=UI.MeasureTextFit(text,{fontSize=props.fontSize or 14,fontFace="sans",width=rect.w,multiline=props.whiteSpace=="normal",lineHeight=props.lineHeight or 1.2,minFontSize=props.fontSize or 14})
                        check(page.." text box "..tostring(w.id or w.type),fit.height > 0 and fit.height <= rect.h + 3 and fit.width <= rect.w + 3,string.format("%.0fx%.0f text=%.0f %s",rect.w,rect.h,fit.height,text))
                    end
                end
            end
            for _, child in ipairs(w.children or {}) do walk(child,shown) end
        end
        walk(UI.GetRoot(),true)
    end
    UI.SetScale(1)
    UI.Layout()
    lines[#lines+1]=string.format("UI viewport %.0fx%.0f",UI.GetWidth(),UI.GetHeight())
    hide(); Overlays[1].Show({mode="init",onConfirm=function() end}); inspect("New story")
    hide(); Overlays[2].Show({onProfile=function()end,onSwitch=function()end,onNew=function()end}); inspect("Settings")
    hide(); Overlays[3].Show({title="Which story should this replace?",hint="All three slots are full. Tap a story to replace it. Its chat, events and traces will be lost.",cards={
        {slotId="life-1",head="Los Angeles × Former colleague (current)",body="13:00 · Working on a deadline\nTrace: A half-finished coffee\nLast opened: 10-02 20:00",isActive=true},
        {slotId="life-2",head="Shanghai × School friend",body="21:00 · On shift at the bookshop",isActive=false},
        {slotId="life-3",head="London × Old friend",body="13:00 · Having a sandwich",isActive=false}},onPick=function()end}); inspect("Story cards")
    hide(); Overlays[4].Show({cityClock="Los Angeles · 13:00 · 2026-10-02",identity=Profile.CityFor("los_angeles").identity,relation="Former colleague × Los Angeles",scene="Los Angeles studio · Studio",status="Busy · Working on a deadline",recent={"Zine proofs (Ongoing)","A lunchtime call (Ended)","Getting the workshop ready (Ended)"},trace="Annotated proofs (from Zine proofs)"}); inspect("Profile")
    hide(); require("ui.ChatPanel").ResetConversation()
    local Messages=require("services.MessageService")
    Messages.Init();Messages.AppendReply("I'm checking the final zine proofs in the studio. Let me check the last two pages first.",1790928000,"la_studio_zine_layout","13:00","test-key")
    require("ui.ChatPanel").Tick(0.1); inspect("Chat")
    Memory.Save()
    Memory.Load()
    check("Migration survives save/reload",Memory.Get().messages[2].text==saved.messages[2].text)
end)
check("Harness completed",ok,err)
lines[#lines+1] = string.format("RESULT %d passed %d failed",pass,fail)
local report=actualFile("english-local-check.txt",FILE_WRITE)
if report:IsOpen() then report:WriteString(table.concat(lines,"\n"));report:Close() end
report:Dispose()
engine:Exit()

end
local englishFrames=0
local chatForCheck=require("ui.ChatPanel")
local originalTick=chatForCheck.Tick
chatForCheck.Tick=function(dt)
    originalTick(dt)
    englishFrames=englishFrames+1
    if englishFrames==10 then RunEnglishChecks() end
end
