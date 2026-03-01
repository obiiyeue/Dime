-- ================================================================
-- BOUNTY HUNTER PRO v6 - BLOX FRUITS
-- Fix: 100% haki/v3/v4, kite mode HP<50%, return HP>70%
-- ================================================================
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ==================== SERVICES ====================
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui  = game:GetService("StarterGui")
local RS          = game:GetService("ReplicatedStorage")
local TS          = game:GetService("TeleportService")
local VIM         = game:GetService("VirtualInputManager")

local LP  = Players.LocalPlayer
local Cam = workspace.CurrentCamera

-- ==================== CONFIG ====================
getgenv().Team = getgenv().Team or "Pirates"
getgenv().Config = getgenv().Config or {
    ["SafeZone"]   = {["Enable"]=true,["LowHealth"]=4500,["MaxHealth"]=6000,["Teleport Y"]=9999},
    ["Hop Server"] = {["Enable"]=true,["Delay Hop"]=1},
    ["Setting"]    = {["Fast Delay"]=0.45,["Url"]=""},
    ["Auto turn on v4"]=true,
    ["Items"]={
        ["Melee"]={Enable=true,Delay=0,Skills={
            Z={Enable=true,HoldTime=0.1},
            X={Enable=true,HoldTime=0.1},
            C={Enable=true,HoldTime=0.1},
        }},
        ["Sword"]={Enable=true,Delay=0,Skills={
            Z={Enable=true,HoldTime=0.1},
            X={Enable=true,HoldTime=0.0},
        }},
    }
}
local CFG       = getgenv().Config
local FastDelay = CFG["Setting"]["Fast Delay"] or 0.45

-- ==================== STATE ====================
local S = {
    Running         = true,
    Target          = nil,
    TargetTimer     = 0,
    InSafeZone      = false,
    KillCount       = 0,
    VisitedServers  = {},
    AttackEnabled   = true,
    CurrentWeapon   = "Melee",
    WeaponSwapTimer = 0,
    SkillActive     = false,
    ChaseTimeout    = 120,
    JobId           = game.JobId,
    Blacklist       = {},       -- đã kill hoặc skip
    HopBusy         = false,
    Status          = "hunting", -- hunting | kiting | waiting | hopping
    TargetReached   = false,
    SkillAllowed    = false,
    KiteMode        = false,    -- đang kite (máu < 50%)
    KiteY           = 0,        -- độ cao kite hiện tại
}

-- ==================== HP HELPERS ====================
local function GetMyHP()
    local hum = GetHum and GetHum()
    if not hum then return 100, 100 end
    return hum.Health, hum.MaxHealth
end

-- ==================== HELPERS ====================
local function GetChar() return LP.Character end
local function GetHRP()  local c=GetChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function GetHum()  local c=GetChar(); return c and c:FindFirstChild("Humanoid") end

local function IsAlive(p)
    if not p or not p.Character then return false end
    local h = p.Character:FindFirstChild("Humanoid")
    return h and h.Health > 0
end

-- ==================== PVP CHECK ====================
local function IsPVPReady(p)
    if not p or not p.Character then return false end
    local pvp = p:GetAttribute("PVP") or p:GetAttribute("pvp") or p:GetAttribute("IsPVP")
    if pvp == false then return false end
    local inSafe = p:GetAttribute("InSafeZone") or p:GetAttribute("SafeZone") or p:GetAttribute("isSafe")
    if inSafe == true then return false end
    local pvpFolder = p:FindFirstChild("PVP") or (p.Character and p.Character:FindFirstChild("PVP"))
    if pvpFolder and pvpFolder:IsA("BoolValue") and pvpFolder.Value == false then return false end
    if p.Character then
        local safeTag = p.Character:FindFirstChild("SafeZone") or p.Character:FindFirstChild("InSafeZone")
        if safeTag then return false end
    end
    return true
end

-- ==================== MOVERS ====================
local function ClearMover(name)
    local hrp = GetHRP(); if not hrp then return end
    local o = hrp:FindFirstChild(name); if o then o:Destroy() end
end

local function SetBV(v)
    local hrp = GetHRP(); if not hrp then return end
    local bv = hrp:FindFirstChild("__BV__") or Instance.new("BodyVelocity")
    bv.Name="__BV__"; bv.MaxForce=Vector3.new(1e9,1e9,1e9); bv.P=1e5; bv.Velocity=v; bv.Parent=hrp
end

local function SetBP(pos)
    local hrp = GetHRP(); if not hrp then return end
    local bp = hrp:FindFirstChild("__BP__") or Instance.new("BodyPosition")
    bp.Name="__BP__"; bp.MaxForce=Vector3.new(1e9,1e9,1e9); bp.D=300; bp.P=5e4; bp.Position=pos; bp.Parent=hrp
end

local function SetBG(cf)
    local hrp = GetHRP(); if not hrp then return end
    local bg = hrp:FindFirstChild("__BG__") or Instance.new("BodyGyro")
    bg.Name="__BG__"; bg.MaxTorque=Vector3.new(1e9,1e9,1e9); bg.D=200; bg.CFrame=cf; bg.Parent=hrp
end

local function ClearFly()
    ClearMover("__BV__"); ClearMover("__BP__"); ClearMover("__BG__")
end

local function Gravity(on) workspace.Gravity = on and 196.2 or 0 end

-- Noclip
local NoclipOn = true
RunService.Stepped:Connect(function()
    if not NoclipOn then return end
    local c = GetChar(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)

-- ==================== REMOTE SCANNER (toàn bộ RS) ====================
-- Scan toàn bộ RS để tìm remotes theo tên, không cần biết folder
local function FindRemoteAnywhere(name)
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj.Name == name and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
            return obj
        end
    end
    return nil
end

local function FindRemoteLike(keyword)
    local results = {}
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local low = obj.Name:lower()
            if low:find(keyword:lower()) then
                table.insert(results, obj)
            end
        end
    end
    return results
end

-- Net remote cho hit detection
local NetRemote, NetSeed = nil, nil
local function ScanFolder(folder)
    if not folder then return end
    for _, v in ipairs(folder:GetChildren()) do
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote=v; NetSeed=v:GetAttribute("Id")
        end
    end
    folder.ChildAdded:Connect(function(v)
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote=v; NetSeed=v:GetAttribute("Id")
        end
    end)
end
for _, n in ipairs({"Util","Common","Remotes","Assets","FX"}) do ScanFolder(RS:FindFirstChild(n)) end

-- ==================== AUTO V3/V4/HAKI - 100% SCAN ====================
-- Scan toàn bộ RS descendants, không giới hạn folder
local function FireIfRemote(obj, ...)
    if not obj then return end
    pcall(function()
        if obj:IsA("RemoteEvent") then obj:FireServer(...) end
    end)
end

local V4_NAMES  = {"ActivateV4","V4Activate","UseV4","V4Transform","RaceV4","V4","activatev4"}
local V3_NAMES  = {"ActivateV3","V3Activate","UseV3","V3Transform","RaceV3","V3","activatev3"}
local HAKI_NAMES= {
    -- Buso/Armament
    "ActivateBuso","BusoHaki","Buso","ArmamentHaki","Armament",
    "EquipHaki","UseHaki","HakiOn","EnableHaki","SetHaki",
    "AuraHaki","HakiAura","Haki","ActivateAura","BusoActivate",
    -- Ken/Observation
    "ActivateKen","KenHaki","Ken","ObservationHaki","Observation",
    "KenActivate","UseKen","KenOn",
    -- Generic
    "HakiActivate","HakiMode","ActivateHaki","EnableAura",
}

local function AutoPowerLoop()
    task.spawn(function()
        -- Chờ RS load đầy đủ
        task.wait(3)
        while S.Running do
            pcall(function()
                -- V4
                for _, name in ipairs(V4_NAMES) do
                    local r = FindRemoteAnywhere(name)
                    FireIfRemote(r)
                end
                -- V3
                for _, name in ipairs(V3_NAMES) do
                    local r = FindRemoteAnywhere(name)
                    FireIfRemote(r)
                end
                -- Haki - thử tên chính xác
                for _, name in ipairs(HAKI_NAMES) do
                    local r = FindRemoteAnywhere(name)
                    FireIfRemote(r, true)
                    FireIfRemote(r)  -- thử cả không arg
                end
                -- Haki - scan keyword
                for _, r in ipairs(FindRemoteLike("haki")) do FireIfRemote(r, true) end
                for _, r in ipairs(FindRemoteLike("buso")) do FireIfRemote(r, true) end
                for _, r in ipairs(FindRemoteLike("ken"))  do FireIfRemote(r, true) end
                for _, r in ipairs(FindRemoteLike("aura")) do FireIfRemote(r, true) end
                for _, r in ipairs(FindRemoteLike("v4"))   do FireIfRemote(r) end
                for _, r in ipairs(FindRemoteLike("v3"))   do FireIfRemote(r) end
                -- Thử ép key H (haki hotkey phổ biến trong BF)
                pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.H, false, game) end)
                task.wait(0.05)
                pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.H, false, game) end)
                -- Thử key J (ken haki)
                pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.J, false, game) end)
                task.wait(0.05)
                pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.J, false, game) end)
            end)
            task.wait(1.5)
        end
    end)
end

-- ==================== AUTO PVP ====================
local PVP_NAMES = {
    "PVP","TogglePVP","EnablePVP","SetPVP","PvpToggle",
    "PVPMode","ActivatePVP","pvp","Pvp","PvpOn","PVPOn"
}
local function TurnOnPVP()
    pcall(function()
        for _, name in ipairs(PVP_NAMES) do
            local r = FindRemoteAnywhere(name)
            FireIfRemote(r, true)
            FireIfRemote(r)
        end
        for _, r in ipairs(FindRemoteLike("pvp")) do FireIfRemote(r, true) end
        pcall(function() LP:SetAttribute("PVP", true) end)
        -- Thử key P (pvp toggle hotkey)
        pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.P, false, game) end)
        task.wait(0.05)
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.P, false, game) end)
    end)
end

-- ==================== TARGET LIST ====================
local function GetTargetList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and IsAlive(p) and not S.Blacklist[p.UserId] and IsPVPReady(p) then
            table.insert(list, p)
        end
    end
    return list
end

local function PickNextTarget(exclude)
    local list = GetTargetList()
    local filtered = {}
    for _, p in ipairs(list) do
        if p ~= exclude then table.insert(filtered, p) end
    end
    if #filtered == 0 then return nil end
    return filtered[math.random(1, #filtered)]
end

-- ==================== WEAPON SWITCH ====================
local SWAP_INTERVAL = 3.5

local function FindTool(wType)
    local c = GetChar(); if not c then return nil end
    local held = c:FindFirstChildOfClass("Tool")
    if held and held:GetAttribute("WeaponType") == wType then return held end
    for _, t in ipairs(LP.Backpack:GetChildren()) do
        if t:IsA("Tool") and t:GetAttribute("WeaponType") == wType then return t end
    end
    return nil
end

local function SwapWeapon()
    local next_w = S.CurrentWeapon=="Melee" and "Sword" or "Melee"
    local tool = FindTool(next_w)
    if tool then
        S.CurrentWeapon = next_w
        pcall(function() local h=GetHum(); if h then h:EquipTool(tool) end end)
    else
        local cur = FindTool(S.CurrentWeapon)
        if cur then pcall(function() local h=GetHum(); if h then h:EquipTool(cur) end end) end
    end
end

-- ==================== SKILL SYSTEM ====================
local SkillThreads = {}

local function StopSkills()
    for k, v in pairs(SkillThreads) do
        if v and type(v) ~= "boolean" then pcall(function() task.cancel(v) end) end
        SkillThreads[k] = nil
    end
    S.SkillActive = false
end

local function PressKey(keyCode, hold)
    task.spawn(function()
        S.SkillActive = true
        pcall(function() VIM:SendKeyEvent(true, keyCode, false, game) end)
        if hold and hold > 0 then task.wait(hold) end
        pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
        task.wait(0.02)
        S.SkillActive = false
    end)
end

local function StartSkillLoop(wType)
    StopSkills()
    local wCFG = CFG["Items"][wType]
    if not wCFG or not wCFG.Enable then return end
    for keyName, skillCFG in pairs(wCFG.Skills or {}) do
        if skillCFG.Enable then
            local hold    = skillCFG.HoldTime or 0
            local keyEnum = Enum.KeyCode[keyName]
            if keyEnum then
                SkillThreads[keyName] = task.spawn(function()
                    while S.AttackEnabled and S.Running do
                        if S.SkillAllowed and not S.KiteMode then
                            PressKey(keyEnum, hold)
                        end
                        task.wait()
                    end
                end)
            end
        end
    end
end

-- ==================== AUTO ATTACK ====================
local LastWType = ""
task.spawn(function()
    while true do
        task.wait(FastDelay * 0.5)
        if not S.AttackEnabled or not S.Running or S.InSafeZone then continue end
        if not S.SkillAllowed or S.KiteMode then continue end
        local c=GetChar(); local hrp=GetHRP()
        if not c or not hrp then continue end

        if tick() - S.WeaponSwapTimer >= SWAP_INTERVAL then
            S.WeaponSwapTimer = tick()
            task.spawn(SwapWeapon)
        end

        local targets = {}
        for _, folder in ipairs({workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Characters")}) do
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model ~= c then
                        local mHRP = model:FindFirstChild("HumanoidRootPart")
                        local mHum = model:FindFirstChild("Humanoid")
                        if mHRP and mHum and mHum.Health > 0
                            and (mHRP.Position - hrp.Position).Magnitude <= 60 then
                            for _, part in ipairs(model:GetChildren()) do
                                if part:IsA("BasePart") then
                                    table.insert(targets, {model, part}); break
                                end
                            end
                        end
                    end
                end
            end
        end

        if IsAlive(S.Target) then
            local tHRP  = S.Target.Character:FindFirstChild("HumanoidRootPart")
            local tHead = S.Target.Character:FindFirstChild("Head")
            if tHRP and (tHRP.Position - hrp.Position).Magnitude <= 80 then
                table.insert(targets, 1, {S.Target.Character, tHead or tHRP})
            end
        end

        if #targets == 0 then continue end
        local tool = c:FindFirstChildOfClass("Tool")
        if not tool then continue end
        local wType = tool:GetAttribute("WeaponType") or S.CurrentWeapon

        if wType ~= LastWType then
            LastWType = wType
            task.spawn(function() StartSkillLoop(wType) end)
        end

        pcall(function()
            local net = require(RS.Modules.Net)
            net:RemoteEvent("RegisterHit", true)
            RS.Modules.Net["RE/RegisterAttack"]:FireServer()
            local head = targets[1][1]:FindFirstChild("Head")
            if head then
                RS.Modules.Net["RE/RegisterHit"]:FireServer(
                    head, targets, {},
                    tostring(LP.UserId):sub(2,4)..tostring(coroutine.running()):sub(11,15)
                )
                if NetRemote and NetSeed then
                    pcall(function()
                        local seed = RS.Modules.Net.seed:InvokeServer()
                        cloneref(NetRemote):FireServer(
                            string.gsub("RE/RegisterHit",".",function(p)
                                return string.char(bit32.bxor(string.byte(p),
                                    math.floor(workspace:GetServerTimeNow()/10%10)+1))
                            end),
                            bit32.bxor(NetSeed+909090, seed*2),
                            head, targets
                        )
                    end)
                end
            end
        end)
    end
end)

-- ==================== FLY / KITE SYSTEM ====================
local FLY_SPEED  = 350
local KITE_HEIGHT = 180   -- độ cao bay lên khi kite
local KITE_DIST   = 120   -- khoảng cách giữ với target khi kite

RunService.Heartbeat:Connect(function()
    if not S.Running then return end
    local hrp = GetHRP(); local hum = GetHum()
    if not hrp or not hum then return end

    -- Đang hop/waiting
    if S.Status == "waiting" or S.Status == "hopping" then
        hum.PlatformStand = true; Gravity(false)
        local safeY = CFG["SafeZone"]["Teleport Y"] or 9999
        local myPos = hrp.Position
        if myPos.Y < safeY - 50 then
            SetBV(Vector3.new(0, FLY_SPEED, 0)); ClearMover("__BP__")
        else
            SetBV(Vector3.new(0,0,0)); SetBP(Vector3.new(myPos.X, safeY, myPos.Z))
        end
        return
    end

    -- Safe zone recover
    if S.InSafeZone then
        hum.PlatformStand = true; Gravity(false); SetBV(Vector3.new(0,0,0)); return
    end

    if not S.Target or not IsAlive(S.Target) then
        S.SkillAllowed = false; S.KiteMode = false
        SetBV(Vector3.new(0,0,0)); return
    end

    local tHRP = S.Target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end

    local myPos = hrp.Position
    local tPos  = tHRP.Position
    local dist  = (tPos - myPos).Magnitude

    hum.PlatformStand = true; Gravity(false)

    -- === KITE MODE: máu < 50% ===
    if S.KiteMode then
        S.SkillAllowed = false
        -- Bay lên cao, giữ khoảng cách KITE_DIST với target
        local kiteTargetPos = Vector3.new(myPos.X, tPos.Y + KITE_HEIGHT, myPos.Z)

        -- Di chuyển ra xa nếu target đến gần
        if dist < KITE_DIST then
            -- Bay ra xa khỏi target
            local awayDir = (myPos - tPos)
            awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
            if awayDir.Magnitude > 0.1 then awayDir = awayDir.Unit end
            local escapePos = Vector3.new(
                myPos.X + awayDir.X * 40,
                tPos.Y + KITE_HEIGHT,
                myPos.Z + awayDir.Z * 40
            )
            SetBV((escapePos - myPos).Unit * FLY_SPEED)
            SetBG(CFrame.lookAt(myPos, tPos)) -- nhìn về target
        else
            -- Đã đủ xa: hover ở tầm cao
            SetBP(kiteTargetPos)
            SetBV(Vector3.new(0,0,0))
            SetBG(CFrame.lookAt(myPos, tPos))
        end
        return
    end

    -- === NORMAL FLY/ATTACK MODE ===
    local tPosOffset = tPos + Vector3.new(0,3,0)
    local distToTarget = (tPosOffset - myPos).Magnitude

    if distToTarget > 8 then
        S.SkillAllowed = false
        local dir
        if math.abs(tPosOffset.Y - myPos.Y) < 5 then
            dir = Vector3.new(tPosOffset.X-myPos.X, 0, tPosOffset.Z-myPos.Z).Unit
        else
            dir = (tPosOffset - myPos).Unit
        end
        SetBV(dir * FLY_SPEED)
        SetBG(CFrame.lookAt(myPos, myPos+dir))
        ClearMover("__BP__")
    else
        if not S.TargetReached then
            S.TargetReached = true
            S.TargetTimer   = tick()
        end
        S.SkillAllowed = true
        SetBV(Vector3.new(0,0,0))
        SetBG(CFrame.lookAt(myPos, tHRP.Position))
        SetBP(Vector3.new(myPos.X, tPosOffset.Y, myPos.Z))
    end
end)

-- ==================== HP MONITOR (KITE LOGIC) ====================
task.spawn(function()
    while task.wait(0.2) do
        if not S.Running then break end
        local hum = GetHum()
        if not hum or hum.MaxHealth <= 0 then continue end

        local pct = hum.Health / hum.MaxHealth

        -- Máu < 50%: vào kite mode
        if pct < 0.5 and not S.KiteMode and not S.InSafeZone and S.Target then
            S.KiteMode     = true
            S.SkillAllowed = false
            S.Status       = "kiting"
            StopSkills()
        end

        -- Máu > 70% và đang kite: thoát kite, attack lại
        if pct >= 0.7 and S.KiteMode then
            S.KiteMode      = false
            S.TargetReached = false  -- bay lại gần target
            S.SkillAllowed  = false
            if S.Target and IsAlive(S.Target) then
                S.Status = "hunting"
            end
        end

        -- Safe zone logic (máu cực thấp)
        if CFG["SafeZone"]["Enable"] then
            local low  = CFG["SafeZone"]["LowHealth"]
            local full = CFG["SafeZone"]["MaxHealth"]
            if hum.Health > 0 and hum.Health <= low and not S.InSafeZone then
                S.InSafeZone   = true
                S.AttackEnabled= false
                S.SkillAllowed = false
                S.KiteMode     = false
                StopSkills(); ClearFly(); Gravity(false)
            elseif S.InSafeZone and hum.Health >= full then
                S.InSafeZone   = false
                S.AttackEnabled= true
                S.KiteMode     = false
                S.Status       = "hunting"
                Gravity(false)
            end
        end
    end
end)

-- ==================== WEBHOOK ====================
local function Webhook(name, bounty)
    local url = CFG["Setting"]["Url"] or ""
    if url == "" then return end
    pcall(function()
        game:HttpPost(url, HttpService:JSONEncode({embeds={{
            title="🏴‍☠️ Bounty Killed!",
            description="**Player:** "..name.."\n**Bounty:** 💰 "..tostring(bounty),
            color=3447003
        }}}), false, "application/json")
    end)
end

-- ==================== SERVER HOP (8-10 người) ====================
local function SpamHopServer()
    if S.HopBusy then return end
    S.HopBusy = true; S.Status = "hopping"
    StopSkills(); S.SkillAllowed = false

    task.spawn(function()
        while S.Running do
            local ok, result = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(
                    "https://games.roblox.com/v1/games/"..game.PlaceId
                    .."/servers/Public?sortOrder=Desc&limit=100"
                ))
            end)

            if ok and result and result.data then
                local preferred = {}
                local fallback  = {}
                for _, sv in ipairs(result.data) do
                    if sv.id ~= S.JobId and not S.VisitedServers[sv.id] and sv.playing then
                        -- Bỏ qua server đầy (maxPlayers)
                        local isFull = sv.maxPlayers and sv.playing >= sv.maxPlayers
                        if not isFull then
                            if sv.playing >= 8 and sv.playing <= 10 then
                                table.insert(preferred, sv)
                            elseif sv.playing > 0 and sv.playing < 8 then
                                table.insert(fallback, sv)
                            end
                        end
                    end
                end

                local pool = #preferred > 0 and preferred or fallback
                if #pool > 0 then
                    local chosen = pool[math.random(1, #pool)]
                    S.VisitedServers[chosen.id] = true
                    local hopOk = pcall(function()
                        TS:TeleportToPlaceInstance(game.PlaceId, chosen.id, LP)
                    end)
                    if hopOk then task.wait(10) end
                else
                    S.VisitedServers = {}
                end
            end

            task.wait(CFG["Hop Server"]["Delay Hop"] or 1)
        end
    end)
end

-- ==================== JOIN TEAM ====================
local function JoinTeam()
    pcall(function()
        local tn = getgenv().Team
        for _, t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(tn:lower()) then
                local r = FindRemoteAnywhere("JoinTeam")
                if r then r:FireServer(t) end
            end
        end
    end)
end

-- ==================== MAIN HUNT LOOP ====================
task.spawn(function()
    task.wait(3)
    JoinTeam()
    TurnOnPVP()

    while S.Running do
        task.wait(0.15)
        if S.Status == "hopping" then continue end
        if S.InSafeZone then continue end

        -- Target chết
        if S.Target and not IsAlive(S.Target) then
            S.KillCount = S.KillCount + 1
            local bounty = 0
            pcall(function()
                bounty = S.Target:GetAttribute("Bounty")
                    or (S.Target.leaderstats and S.Target.leaderstats:FindFirstChild("Bounty")
                        and S.Target.leaderstats.Bounty.Value) or 0
            end)
            Webhook(S.Target.Name, bounty)
            S.Blacklist[S.Target.UserId] = true
            S.Target = nil; S.SkillAllowed = false; S.KiteMode = false
            StopSkills(); SkillThreads = {}
        end

        -- Tìm target mới
        if not S.Target then
            S.Target = PickNextTarget(nil)
            if S.Target then
                S.TargetTimer=tick(); S.TargetReached=false; S.SkillAllowed=false
                S.KiteMode=false; S.Status="hunting"
            else
                S.Status = "waiting"; SpamHopServer(); continue
            end
        end

        -- Target tắt PVP / vào safe zone
        if S.Target and not IsPVPReady(S.Target) then
            S.Target = PickNextTarget(S.Target)
            if S.Target then
                S.TargetTimer=tick(); S.TargetReached=false; S.SkillAllowed=false; S.KiteMode=false
            else
                S.Status="waiting"; SpamHopServer()
            end
            StopSkills(); SkillThreads={}; continue
        end

        -- Timeout 2 phút
        if S.Target and S.TargetReached and (tick() - S.TargetTimer) >= S.ChaseTimeout then
            S.Blacklist[S.Target.UserId] = true
            S.Target = PickNextTarget(nil)
            if S.Target then
                S.TargetTimer=tick(); S.TargetReached=false; S.SkillAllowed=false; S.KiteMode=false
            else
                S.Status="waiting"; SpamHopServer()
            end
            StopSkills(); SkillThreads={}
        end

        -- Cập nhật status khi kiting
        if S.KiteMode and S.Status ~= "kiting" then
            S.Status = "kiting"
        elseif not S.KiteMode and S.Status == "kiting" then
            S.Status = "hunting"
        end
    end
end)

-- ==================== AIMBOT ====================
getgenv().AimSettings = {
    Enabled=true, AimPart="HumanoidRootPart",
    MaxDistance=2000, PrioritizeLowHP=true,
    Prediction=0.135, Smoothness=0.07, SkillSmoothing=0.18,
    ShowFOV=true, FOVSize=150,
}

local FOVCircle = Drawing.new("Circle")
FOVCircle.Color=Color3.fromRGB(255,80,80); FOVCircle.Thickness=1.5
FOVCircle.Filled=false; FOVCircle.Transparency=1
FOVCircle.NumSides=64; FOVCircle.Radius=150

local Arrow = Drawing.new("Triangle")
Arrow.Color=Color3.fromRGB(0,255,120); Arrow.Filled=true
Arrow.Transparency=0.4; Arrow.Visible=false

local AimLine = Drawing.new("Line")
AimLine.Color=Color3.fromRGB(255,200,0); AimLine.Thickness=1.5
AimLine.Transparency=0.5; AimLine.Visible=false

RunService.RenderStepped:Connect(function()
    local mp = UIS:GetMouseLocation()
    FOVCircle.Position=mp; FOVCircle.Visible=getgenv().AimSettings.ShowFOV
    FOVCircle.Radius=getgenv().AimSettings.FOVSize

    if not getgenv().AimSettings.Enabled then
        Arrow.Visible=false; AimLine.Visible=false; return
    end

    local aimT = IsAlive(S.Target) and S.Target or nil
    if not aimT then
        local best, bestScore = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and IsAlive(p) then
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local sp, on = Cam:WorldToViewportPoint(root.Position)
                    if on then
                        local d = (Vector2.new(sp.X,sp.Y)-mp).Magnitude
                        local h = p.Character:FindFirstChild("Humanoid")
                        local sc = d
                        if h and h.MaxHealth>0 then sc = sc*(h.Health/h.MaxHealth+0.5) end
                        if d <= getgenv().AimSettings.FOVSize and sc < bestScore then
                            bestScore=sc; best=p
                        end
                    end
                end
            end
        end
        aimT = best
    end

    if aimT and aimT.Character then
        local part = aimT.Character:FindFirstChild(getgenv().AimSettings.AimPart)
            or aimT.Character:FindFirstChild("HumanoidRootPart")
        if not part then Arrow.Visible=false; AimLine.Visible=false; return end

        local predicted = part.Position + part.Velocity * getgenv().AimSettings.Prediction
        local smooth = S.SkillActive and getgenv().AimSettings.SkillSmoothing or getgenv().AimSettings.Smoothness
        local cur = Cam.CFrame
        Cam.CFrame = cur:Lerp(CFrame.new(cur.Position, predicted), smooth)

        local sp, on = Cam:WorldToViewportPoint(predicted)
        local center = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
        if on then
            local ts = Vector2.new(sp.X,sp.Y)
            local ud = (ts-center).Magnitude>0 and (ts-center).Unit or Vector2.new(0,-1)
            local tip = center + ud*math.min((ts-center).Magnitude,100)
            local perp = Vector2.new(-ud.Y,ud.X)
            Arrow.PointA=tip; Arrow.PointB=tip-ud*20+perp*9; Arrow.PointC=tip-ud*20-perp*9
            Arrow.Visible=true; AimLine.From=center; AimLine.To=ts; AimLine.Visible=true
        else
            local sp2,_ = Cam:WorldToViewportPoint(predicted)
            local ed = (Vector2.new(sp2.X,sp2.Y)-center).Unit
            local edge = center+ed*130
            local perp = Vector2.new(-ed.Y,ed.X)
            Arrow.PointA=edge; Arrow.PointB=edge-ed*20+perp*9; Arrow.PointC=edge-ed*20-perp*9
            Arrow.Visible=true; AimLine.Visible=false
        end
    else
        Arrow.Visible=false; AimLine.Visible=false
    end
end)

-- ==================== ESP ====================
local ESPs = {}
local function MakeESP(p)
    if ESPs[p] then return end
    local bg = Instance.new("BillboardGui")
    bg.Size=UDim2.new(0,180,0,52); bg.StudsOffset=Vector3.new(0,3.5,0); bg.AlwaysOnTop=true
    local nL = Instance.new("TextLabel",bg)
    nL.Size=UDim2.new(1,0,0.55,0); nL.BackgroundTransparency=1
    nL.TextStrokeTransparency=0; nL.Font=Enum.Font.GothamBold; nL.TextScaled=true
    local dL = Instance.new("TextLabel",bg)
    dL.Size=UDim2.new(1,0,0.45,0); dL.Position=UDim2.new(0,0,0.55,0)
    dL.BackgroundTransparency=1; dL.TextColor3=Color3.fromRGB(200,200,200)
    dL.TextStrokeTransparency=0; dL.Font=Enum.Font.Gotham; dL.TextScaled=true
    ESPs[p] = {Gui=bg, N=nL, D=dL}
    RunService.RenderStepped:Connect(function()
        local char = p.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            bg.Parent = char.HumanoidRootPart
            local myHRP = GetHRP()
            if myHRP then
                local d = math.floor((char.HumanoidRootPart.Position-myHRP.Position).Magnitude)
                local isPVP = IsPVPReady(p)
                local isT   = S.Target==p
                local isSkip= S.Blacklist[p.UserId]
                dL.Text = d.." studs "..(isPVP and "⚔️" or "🛡")
                nL.Text = p.Name..(isT and " 🎯" or isSkip and " ✗" or "")
                nL.TextColor3 = isT and Color3.fromRGB(255,60,60)
                    or isSkip and Color3.fromRGB(120,120,120)
                    or not isPVP and Color3.fromRGB(100,100,255)
                    or Color3.fromRGB(255,220,50)
            end
        end
    end)
end
for _, p in ipairs(Players:GetPlayers()) do if p~=LP then MakeESP(p) end end
Players.PlayerAdded:Connect(MakeESP)
Players.PlayerRemoving:Connect(function(p)
    if ESPs[p] then if ESPs[p].Gui then ESPs[p].Gui:Destroy() end; ESPs[p]=nil end
end)

-- ==================== UI ====================
local oldGui = LP.PlayerGui:FindFirstChild("BountyUI")
if oldGui then oldGui:Destroy() end

local SG = Instance.new("ScreenGui", LP.PlayerGui)
SG.Name="BountyUI"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; SG.IgnoreGuiInset=true

-- FULLSCREEN AVATAR
local FullBG = Instance.new("ImageLabel", SG)
FullBG.Size    = UDim2.new(1,0,1,0); FullBG.Position=UDim2.new(0,0,0,0)
FullBG.BackgroundTransparency = 1
FullBG.Image   = "rbxthumb://type=AvatarBust&id=16060333448&w=420&h=420"
FullBG.ImageTransparency = 0.5
FullBG.ScaleType = Enum.ScaleType.Stretch; FullBG.ZIndex = 1

-- Dark overlay
local Overlay = Instance.new("Frame", SG)
Overlay.Size=UDim2.new(1,0,1,0); Overlay.BackgroundColor3=Color3.fromRGB(0,0,5)
Overlay.BackgroundTransparency=0.72; Overlay.BorderSizePixel=0; Overlay.ZIndex=2

-- Labels
local function MakeLabel(parent, size, pos, text, color, font, zindex)
    local l = Instance.new("TextLabel", parent)
    l.Size=size; l.Position=pos; l.BackgroundTransparency=1
    l.Text=text; l.TextColor3=color; l.Font=font
    l.TextScaled=true; l.TextStrokeTransparency=0.3; l.ZIndex=zindex
    return l
end

local HubTitle = MakeLabel(SG, UDim2.new(0,640,0,88), UDim2.new(0.5,-320,0.5,-175),
    "🏴‍☠️ Bounty Hunter Pro v6", Color3.fromRGB(100,215,255), Enum.Font.GothamBlack, 10)

local Divider = Instance.new("Frame", SG)
Divider.Size=UDim2.new(0,420,0,2); Divider.Position=UDim2.new(0.5,-210,0.5,-78)
Divider.BackgroundColor3=Color3.fromRGB(80,180,255); Divider.BackgroundTransparency=0.4
Divider.BorderSizePixel=0; Divider.ZIndex=10

local TargLine  = MakeLabel(SG, UDim2.new(0,520,0,34), UDim2.new(0.5,-260,0.5,-65),
    "🎯 Target: Searching...", Color3.fromRGB(255,255,255), Enum.Font.GothamBold, 10)
local HPLine    = MakeLabel(SG, UDim2.new(0,520,0,28), UDim2.new(0.5,-260,0.5,-26),
    "❤️ HP: --", Color3.fromRGB(100,255,120), Enum.Font.Gotham, 10)
local MyHPLine  = MakeLabel(SG, UDim2.new(0,520,0,24), UDim2.new(0.5,-260,0.5,-56),
    "🧬 My HP: --", Color3.fromRGB(200,255,200), Enum.Font.Gotham, 10)

local HPBarBG = Instance.new("Frame", SG)
HPBarBG.Size=UDim2.new(0,400,0,10); HPBarBG.Position=UDim2.new(0.5,-200,0.5,7)
HPBarBG.BackgroundColor3=Color3.fromRGB(40,40,40); HPBarBG.BackgroundTransparency=0.2
HPBarBG.BorderSizePixel=0; HPBarBG.ZIndex=10
Instance.new("UICorner",HPBarBG).CornerRadius=UDim.new(1,0)
local HPBar = Instance.new("Frame", HPBarBG)
HPBar.Size=UDim2.new(1,0,1,0); HPBar.BackgroundColor3=Color3.fromRGB(80,255,120)
HPBar.BorderSizePixel=0; HPBar.ZIndex=11
Instance.new("UICorner",HPBar).CornerRadius=UDim.new(1,0)

local DistLine  = MakeLabel(SG, UDim2.new(0,520,0,26), UDim2.new(0.5,-260,0.5,23),
    "📏 Distance: --", Color3.fromRGB(190,190,190), Enum.Font.Gotham, 10)
local WepLine   = MakeLabel(SG, UDim2.new(0,520,0,24), UDim2.new(0.5,-260,0.5,54),
    "⚔️ Weapon: Melee", Color3.fromRGB(255,185,50), Enum.Font.Gotham, 10)
local KillLine  = MakeLabel(SG, UDim2.new(0,520,0,24), UDim2.new(0.5,-260,0.5,83),
    "💀 Kills: 0  |  ⏱ --", Color3.fromRGB(255,110,110), Enum.Font.GothamBold, 10)
local StatusLine= MakeLabel(SG, UDim2.new(0,520,0,28), UDim2.new(0.5,-260,0.5,113),
    "", Color3.fromRGB(255,80,80), Enum.Font.GothamBold, 10)
local BLLine    = MakeLabel(SG, UDim2.new(0,520,0,22), UDim2.new(0.5,-260,0.5,146),
    "", Color3.fromRGB(160,160,160), Enum.Font.Gotham, 10)

-- My HP bar (nhỏ phía dưới)
local MyHPBarBG = Instance.new("Frame", SG)
MyHPBarBG.Size=UDim2.new(0,400,0,7); MyHPBarBG.Position=UDim2.new(0.5,-200,0.5,172)
MyHPBarBG.BackgroundColor3=Color3.fromRGB(20,20,20); MyHPBarBG.BackgroundTransparency=0.3
MyHPBarBG.BorderSizePixel=0; MyHPBarBG.ZIndex=10
Instance.new("UICorner",MyHPBarBG).CornerRadius=UDim.new(1,0)
local MyHPBar = Instance.new("Frame", MyHPBarBG)
MyHPBar.Size=UDim2.new(1,0,1,0); MyHPBar.BackgroundColor3=Color3.fromRGB(50,200,255)
MyHPBar.BorderSizePixel=0; MyHPBar.ZIndex=11
Instance.new("UICorner",MyHPBar).CornerRadius=UDim.new(1,0)

-- SKIP button
local SkipBtn = Instance.new("TextButton", SG)
SkipBtn.Size=UDim2.new(0,125,0,38); SkipBtn.Position=UDim2.new(1,-139,0,14)
SkipBtn.BackgroundColor3=Color3.fromRGB(255,255,255); SkipBtn.TextColor3=Color3.fromRGB(0,0,0)
SkipBtn.Text="⏭  Skip Player"; SkipBtn.Font=Enum.Font.GothamBold
SkipBtn.TextSize=13; SkipBtn.BorderSizePixel=0; SkipBtn.ZIndex=30
Instance.new("UICorner",SkipBtn).CornerRadius=UDim.new(0,8)
SkipBtn.MouseButton1Click:Connect(function()
    if S.Target then
        S.Blacklist[S.Target.UserId] = true
        S.Target=nil; S.SkillAllowed=false; S.KiteMode=false
        StopSkills(); SkillThreads={}
        local nxt = PickNextTarget(nil)
        if nxt then S.Target=nxt; S.TargetTimer=tick(); S.TargetReached=false; S.Status="hunting"
        else S.Status="waiting"; SpamHopServer() end
    end
end)

-- RESET button
local ResetBtn = Instance.new("TextButton", SG)
ResetBtn.Size=UDim2.new(0,125,0,26); ResetBtn.Position=UDim2.new(1,-139,0,56)
ResetBtn.BackgroundColor3=Color3.fromRGB(200,60,60); ResetBtn.TextColor3=Color3.fromRGB(255,255,255)
ResetBtn.Text="🔄 Reset Skip List"; ResetBtn.Font=Enum.Font.Gotham
ResetBtn.TextSize=11; ResetBtn.BorderSizePixel=0; ResetBtn.ZIndex=30
Instance.new("UICorner",ResetBtn).CornerRadius=UDim.new(0,6)
ResetBtn.MouseButton1Click:Connect(function()
    S.Blacklist={}
    if S.Status=="waiting" or S.Status=="hopping" then
        S.HopBusy=false; S.Status="hunting"
        local nxt=PickNextTarget(nil)
        if nxt then S.Target=nxt; S.TargetTimer=tick(); S.TargetReached=false end
    end
end)

-- ==================== UI UPDATE ====================
RunService.RenderStepped:Connect(function()
    local timeLeft = (S.Target and S.TargetReached)
        and math.max(0, S.ChaseTimeout-(tick()-S.TargetTimer)) or 0
    local timerTxt = S.TargetReached and (math.floor(timeLeft).."s") or "flying..."
    KillLine.Text = string.format("💀 Kills: %d  |  ⏱ %s", S.KillCount, timerTxt)
    WepLine.Text  = "⚔️ "..(S.CurrentWeapon or "Melee")..(S.SkillActive and " ✦" or "")

    -- My HP bar
    local hum = GetHum()
    if hum and hum.MaxHealth > 0 then
        local r = hum.Health/hum.MaxHealth
        MyHPBar.Size = UDim2.new(math.clamp(r,0,1),0,1,0)
        MyHPBar.BackgroundColor3 = r>0.7 and Color3.fromRGB(50,200,255)
            or r>0.5 and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,60,60)
        MyHPLine.Text = string.format("🧬 My HP: %d%% %s",
            math.floor(r*100), S.KiteMode and "⬆️ KITING" or "")
        MyHPLine.TextColor3 = r>0.7 and Color3.fromRGB(150,255,150)
            or r>0.5 and Color3.fromRGB(255,220,50) or Color3.fromRGB(255,80,80)
    end

    local bCount=0; for _ in pairs(S.Blacklist) do bCount=bCount+1 end
    BLLine.Text = bCount>0 and ("🚫 Killed/Skipped: "..bCount) or ""

    -- Status
    if S.Status=="hopping" then
        StatusLine.Text="🔄 Hopping (8-10 players)..."
        StatusLine.TextColor3=Color3.fromRGB(255,200,50)
    elseif S.Status=="waiting" then
        StatusLine.Text="⏳ Waiting to hop..."
        StatusLine.TextColor3=Color3.fromRGB(255,150,50)
    elseif S.Status=="kiting" then
        StatusLine.Text="⬆️ KITING — HP < 50%, giữ khoảng cách!"
        StatusLine.TextColor3=Color3.fromRGB(255,80,80)
    elseif S.InSafeZone then
        StatusLine.Text="🛡 SAFE ZONE — Recovering..."
        StatusLine.TextColor3=Color3.fromRGB(255,80,80)
    elseif S.Target and not S.TargetReached then
        StatusLine.Text="✈️ Flying to target..."
        StatusLine.TextColor3=Color3.fromRGB(100,200,255)
    elseif S.SkillAllowed then
        StatusLine.Text="⚡ Attacking!"
        StatusLine.TextColor3=Color3.fromRGB(50,255,120)
    else
        StatusLine.Text=""
    end

    if IsAlive(S.Target) then
        local tChar=S.Target.Character
        local tHum=tChar:FindFirstChild("Humanoid")
        local tHRP=tChar:FindFirstChild("HumanoidRootPart")
        local myHRP=GetHRP()
        TargLine.Text="🎯 Target: "..S.Target.Name
        if tHum and tHum.MaxHealth>0 then
            local pct=math.floor(tHum.Health/tHum.MaxHealth*100)
            HPLine.Text=string.format("❤️ HP: %d/%d (%d%%)",
                math.floor(tHum.Health),math.floor(tHum.MaxHealth),pct)
            local r=tHum.Health/tHum.MaxHealth
            HPBar.Size=UDim2.new(math.clamp(r,0,1),0,1,0)
            HPBar.BackgroundColor3=r>0.5 and Color3.fromRGB(80,255,120)
                or r>0.25 and Color3.fromRGB(255,200,50) or Color3.fromRGB(255,60,60)
        end
        if tHRP and myHRP then
            DistLine.Text="📏 "..(math.floor((tHRP.Position-myHRP.Position).Magnitude)).." studs"
        end
        HubTitle.Text=string.format("🏴‍☠️ Bounty Hunter Pro v6 | %s", timerTxt)
    else
        TargLine.Text="🎯 Target: Searching..."; HPLine.Text="❤️ HP: --"
        DistLine.Text="📏 Distance: --"; HPBar.Size=UDim2.new(0,0,1,0)
        HubTitle.Text="🏴‍☠️ Bounty Hunter Pro v6"
    end
end)

-- ==================== RESPAWN ====================
LP.CharacterAdded:Connect(function()
    task.wait(2)
    Gravity(false); NoclipOn=true
    TurnOnPVP(); JoinTeam()
    S.Blacklist={}; S.Status="hunting"; S.HopBusy=false
    S.TargetReached=false; S.SkillAllowed=false; S.KiteMode=false
end)
if LP.Character then Gravity(false); NoclipOn=true end

-- PVP giữ bật liên tục
task.spawn(function()
    while task.wait(4) do
        if not S.Running then break end
        TurnOnPVP()
    end
end)

-- ==================== BOOT AUTO POWER ====================
AutoPowerLoop()

-- ==================== DONE ====================
print("[BountyHunter Pro v6] Loaded!")
pcall(function()
    StarterGui:SetCore("SendNotification",{
        Title="🏴‍☠️ Bounty Hunter Pro v6",
        Text="✅ Loaded! Kite mode ON | Haki/V3/V4 AUTO",
        Duration=5
    })
end)
