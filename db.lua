--[[
    ██╗      █████╗ ███╗   ██╗███████╗    ██████╗ ██████╗      ██╗   ██╗██╗  ██╗ ██████╗
    ██║     ██╔══██╗████╗  ██║╚══███╔╝    ██╔══██╗██╔══██╗     ██║   ██║██║  ██║██╔═══██╗
    ██║     ███████║██╔██╗ ██║  ███╔╝     ██║  ██║██████╔╝     ██║   ██║███████║██║   ██║
    ██║     ██╔══██║██║╚██╗██║ ███╔╝      ██║  ██║██╔══██╗     ╚██╗ ██╔╝╚════██║██║   ██║
    ███████╗██║  ██║██║ ╚████║███████╗    ██████╔╝██████╔╝      ╚████╔╝      ██║╚██████╔╝
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝    ╚═════╝ ╚═════╝        ╚═══╝       ╚═╝ ╚═════╝
    Death Ball Bot v4.0 — Clean Architecture Rewrite
    Author: Lanz | Architecture: PRD v4.0
    Zero globals · Single heartbeat · FSM movement · Error boundaries
--]]

-- ══════════════════════════════════════════════════════════════════════
-- GUARD: Kill previous instance cleanly before re-executing
-- ══════════════════════════════════════════════════════════════════════
if getgenv().LanzDB and type(getgenv().LanzDB.Shutdown) == "function" then
    pcall(getgenv().LanzDB.Shutdown)
    task.wait(0.1)
end

-- ══════════════════════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════════════════════
local RunService     = game:GetService("RunService")
local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local HttpService    = game:GetService("HttpService")

local Player   = Players.LocalPlayer
local Mouse    = Player:GetMouse()

-- ══════════════════════════════════════════════════════════════════════
-- MODULE SCOPE (all state lives here, nothing leaks to getgenv)
-- ══════════════════════════════════════════════════════════════════════
local LanzDB = {}  -- public API handle (only thing exposed to getgenv)

-- ══════════════════════════════════════════════════════════════════════
-- KERNEL — REGISTRY
-- ══════════════════════════════════════════════════════════════════════
local Registry = {
    connections = {},
    instances   = {},
    threads     = {},
}

function Registry:Track(category, handle)
    table.insert(self[category], handle)
    return handle
end

function Registry:DisconnectAll()
    for _, conn in ipairs(self.connections) do
        pcall(function() conn:Disconnect() end)
    end
    self.connections = {}
end

function Registry:DestroyAll()
    for _, inst in ipairs(self.instances) do
        pcall(function() inst:Destroy() end)
    end
    self.instances = {}
end

function Registry:StopAll()
    for _, thr in ipairs(self.threads) do
        pcall(function() task.cancel(thr) end)
    end
    self.threads = {}
end

function Registry:CleanupAll()
    self:DisconnectAll()
    self:DestroyAll()
    self:StopAll()
end

-- ══════════════════════════════════════════════════════════════════════
-- KERNEL — LOGGER
-- ══════════════════════════════════════════════════════════════════════
local Logger = {
    _prefix  = "[Lanz v4.0]",
    _debugOn = false,
}

function Logger:SetDebug(on) self._debugOn = on end

function Logger:Debug(msg)
    if self._debugOn then print(self._prefix .. " [DEBUG] " .. tostring(msg)) end
end

function Logger:Info(msg)  print(self._prefix .. " [INFO]  " .. tostring(msg)) end
function Logger:Warn(msg)  warn(self._prefix  .. " [WARN]  " .. tostring(msg)) end
function Logger:Error(msg) warn(self._prefix  .. " [ERROR] " .. tostring(msg)) end

-- ══════════════════════════════════════════════════════════════════════
-- KERNEL — CONFIG (defaults + whitelist)
-- ══════════════════════════════════════════════════════════════════════
local CONFIG_VERSION = "4.0"

local ConfigDefaults = {
    _version             = CONFIG_VERSION,
    AutoParry            = true,
    SpamDistance         = 6,
    ParryDistance        = 10,
    ShowParryVisualizer  = true,
    CurveMode            = "NONE",   -- NONE | LEFT | RIGHT | SPIN
    AutoAbility          = false,
    GodMode              = false,
    AutoJoin             = false,
    AutoFollow           = false,
    WanderMode           = false,
    WanderRadius         = 60,
    WanderInterval       = 3,
    DashChance           = 0.35,
    JumpChance           = 0.20,
    InMatchCheck         = true,
    TeleportThreshold    = 80,
    SuddenMoveThreshold  = 50,
    RequireBallCheck     = true,
    WebhookURL           = "",
    WebhookInterval      = 3600,
    DebugMode            = false,
}

-- Keys allowed to be saved/loaded (excludes function-valued fields)
local CONFIG_WHITELIST = {
    "AutoParry", "SpamDistance", "ParryDistance", "ShowParryVisualizer",
    "CurveMode", "AutoAbility", "GodMode", "AutoJoin", "AutoFollow",
    "WanderMode", "WanderRadius", "WanderInterval", "DashChance", "JumpChance",
    "InMatchCheck", "TeleportThreshold", "SuddenMoveThreshold", "RequireBallCheck",
    "WebhookURL", "WebhookInterval", "DebugMode",
}

-- Live config table (copy of defaults; mutated at runtime)
local Config = {}
for k, v in pairs(ConfigDefaults) do Config[k] = v end

-- ══════════════════════════════════════════════════════════════════════
-- KERNEL — STATE
-- ══════════════════════════════════════════════════════════════════════
local State = {
    Match = {
        InMatch       = false,
        ConfirmedAt   = 0,
        ReadyZonePos  = nil,
        LastHRPPos    = nil,
    },
    Movement = {
        Current       = "IDLE",  -- IDLE | JOIN | FOLLOW | WANDER
        TargetPos     = nil,
        LastTarget    = 0,
        LastMoveTick  = tick(),
        LastPos       = nil,
        StuckCounter  = 0,
        WanderTimer   = 0,
    },
    Combat = {
        LastParry     = 0,
        CurrentBall   = nil,
        LastBallCheck = 0,
        LastAbility   = 0,
    },
    Watchdog = {
        LastHeartbeat = tick(),
        LastUICheck   = 0,
        LastBallScan  = 0,
    },
    Boot = {
        Time          = 0,
        Ready         = false,
    },
}

-- ══════════════════════════════════════════════════════════════════════
-- SERVICES — FILE IO
-- ══════════════════════════════════════════════════════════════════════
local FileIO = {
    _path       = nil,
    _saveTimer  = nil,
    _saveDelay  = 0.15,  -- 150ms debounce
}

local FILE_PATHS = {
    "LanzConfig/save.json",
    "Configs/Lanz/save.json",
    "Lanz_DB_save.json",
}

function FileIO:GetPath()
    if self._path then return self._path end
    -- Try paths; use first writable one
    for _, p in ipairs(FILE_PATHS) do
        local ok = pcall(function()
            local folder = p:match("^(.+)/[^/]+$")
            if folder and isfolder and not isfolder(folder) then
                if makefolder then makefolder(folder) end
            end
        end)
        if ok then
            self._path = p
            return p
        end
    end
    self._path = FILE_PATHS[#FILE_PATHS]
    return self._path
end

function FileIO:Save(cfg, silent)
    if self._saveTimer then
        pcall(function() task.cancel(self._saveTimer) end)
    end
    self._saveTimer = Registry:Track("threads", task.delay(self._saveDelay, function()
        local function doSave()
            local data = {
                _version  = CONFIG_VERSION,
                _savedAt  = os.date("%Y-%m-%d %H:%M:%S"),
                _game     = game.PlaceId,
                _player   = Player.Name,
            }
            for _, k in ipairs(CONFIG_WHITELIST) do
                data[k] = cfg[k]
            end
            local encoded = HttpService:JSONEncode(data)
            local path = self:GetPath()
            writefile(path, encoded)
            if not silent then Logger:Info("Config saved → " .. path) end
        end

        local ok, err = pcall(doSave)
        if not ok then
            -- Retry once after 0.2s
            task.wait(0.2)
            local ok2, err2 = pcall(doSave)
            if not ok2 then
                Logger:Warn("Save failed: " .. tostring(err2))
            end
        end
    end))
end

function FileIO:Load()
    local path = self:GetPath()
    local ok, raw = pcall(function()
        if isfile and isfile(path) then
            return readfile(path)
        end
        return nil
    end)
    if not ok or not raw or raw == "" then return nil end

    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 or type(data) ~= "table" then
        Logger:Warn("Config file corrupt — resetting to default")
        self:_BackupCorrupt(path)
        return nil
    end

    -- Validate types against defaults
    local out = {}
    for _, k in ipairs(CONFIG_WHITELIST) do
        if data[k] ~= nil and type(data[k]) == type(ConfigDefaults[k]) then
            out[k] = data[k]
        else
            out[k] = ConfigDefaults[k]
        end
    end
    return out
end

function FileIO:Reset()
    local path = self:GetPath()
    pcall(function()
        if isfile and isfile(path) then
            if delfile then delfile(path) end
        end
    end)
    Logger:Info("Config reset — file deleted")
end

function FileIO:_BackupCorrupt(path)
    pcall(function()
        if isfile and isfile(path) then
            local raw = readfile(path)
            writefile(path .. ".bak", raw)
            if delfile then delfile(path) end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════
-- SERVICES — NOTIFIER (Discord webhook)
-- ══════════════════════════════════════════════════════════════════════
local Notifier = {
    _lastSent = 0,
    _rateLimit = 5,  -- seconds
}

function Notifier:Send(message)
    if Config.WebhookURL == "" then return end
    local now = tick()
    if now - self._lastSent < self._rateLimit then return end
    self._lastSent = now

    Registry:Track("threads", task.spawn(function()
        local function doSend()
            local payload = HttpService:JSONEncode({
                embeds = {{
                    title       = "Lanz DB v4.0",
                    description = message,
                    color       = 6614015,
                    footer      = { text = Player.Name .. " | " .. os.date() },
                    fields = {
                        { name = "Match", value = tostring(State.Match.InMatch), inline = true },
                        { name = "Mode",  value = State.Movement.Current,        inline = true },
                    },
                }}
            })
            local ok = pcall(function()
                -- request() is executor-provided
                request({
                    Url    = Config.WebhookURL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body   = payload,
                })
            end)
            if not ok then
                task.wait(2)
                pcall(function()
                    request({ Url = Config.WebhookURL, Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" }, Body = payload })
                end)
            end
        end

        -- Timeout guard: cancel if > 10s
        local done = false
        local thr = task.spawn(function() doSend(); done = true end)
        task.delay(10, function()
            if not done then pcall(function() task.cancel(thr) end) end
        end)
    end))
end

-- ══════════════════════════════════════════════════════════════════════
-- SERVICES — INPUT SIM
-- ══════════════════════════════════════════════════════════════════════
local InputSim = {
    _lastInput = 0,
    _rateLimit = 1/30,   -- max 30 inputs/sec
    _vim       = nil,
}

function InputSim:_GetVIM()
    if self._vim then return self._vim end
    local ok, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if ok then self._vim = vim end
    return self._vim
end

function InputSim:_CanSend()
    local char = Player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local now = tick()
    if now - self._lastInput < self._rateLimit then return false end
    self._lastInput = now
    return true
end

function InputSim:KeyDown(key)
    if not self:_CanSend() then return end
    local vim = self:_GetVIM()
    if vim then
        pcall(function() vim:SendKeyEvent(true, key, false, game) end)
    end
end

function InputSim:KeyUp(key)
    if not self:_CanSend() then return end
    local vim = self:_GetVIM()
    if vim then
        pcall(function() vim:SendKeyEvent(false, key, false, game) end)
    end
end

function InputSim:Tap(key, duration)
    duration = duration or 0.01
    self:KeyDown(key)
    task.delay(duration, function() self:KeyUp(key) end)
end

function InputSim:Click(x, y)
    local vim = self:_GetVIM()
    if vim then
        pcall(function()
            vim:SendMouseButtonEvent(x or 0, y or 0, 0, true,  game, 1)
            vim:SendMouseButtonEvent(x or 0, y or 0, 0, false, game, 1)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════════
-- SERVICES — TARGET SCANNER
-- ══════════════════════════════════════════════════════════════════════
local TargetScanner = {
    _cachedBall    = nil,
    _cacheTime     = 0,
    _cacheInterval = 0.5,
    _ballConn      = nil,
}

function TargetScanner:IsTarget()
    local char = Player.Character
    if not char then return false end
    local h = char:FindFirstChildOfClass("Highlight")
    if not h then return false end
    return h.FillTransparency < 1
end

function TargetScanner:FindBall()
    local now = tick()
    if self._cachedBall and self._cachedBall.Parent and (now - self._cacheTime) < self._cacheInterval then
        return self._cachedBall
    end

    local best, bestDist = nil, math.huge
    local hrp = self:_GetHRP()
    local origin = hrp and hrp.Position or Vector3.new(0,0,0)

    local function scanPart(p)
        if p:IsA("Part") and p.Parent then
            local n = p.Name:lower()
            if n:find("ball") or n:find("deathball") then
                local d = (p.Position - origin).Magnitude
                if d < bestDist then best = p; bestDist = d end
            end
        end
    end

    -- Check known containers first
    local spawns = workspace:FindFirstChild("BallSpawns")
    if spawns then
        for _, v in ipairs(spawns:GetDescendants()) do scanPart(v) end
    end

    -- Fallback: workspace scan (cached, not per-frame)
    if not best then
        for _, v in ipairs(workspace:GetChildren()) do
            if v:IsA("Part") then scanPart(v) end
        end
    end

    self._cachedBall = best
    self._cacheTime  = now
    State.Combat.CurrentBall = best

    return best
end

function TargetScanner:GetBallVelocity()
    local ball = State.Combat.CurrentBall
    if not ball then return Vector3.new(0,0,0) end
    local a = ball:FindFirstChildOfClass("BodyVelocity")
    if a then return a.Velocity end
    return ball.AssemblyLinearVelocity or Vector3.new(0,0,0)
end

function TargetScanner:GetBallDistance()
    local hrp  = self:_GetHRP()
    local ball = State.Combat.CurrentBall
    if not hrp or not ball or not ball.Parent then return math.huge end
    return (ball.Position - hrp.Position).Magnitude
end

function TargetScanner:IsApproaching()
    local hrp  = self:_GetHRP()
    local ball = State.Combat.CurrentBall
    if not hrp or not ball or not ball.Parent then return false end
    local vel = self:GetBallVelocity()
    if vel.Magnitude > 100 then return false end  -- network spike
    local dir = (hrp.Position - ball.Position).Unit
    return vel:Dot(dir) > 0
end

function TargetScanner:_GetHRP()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function TargetScanner:Update()
    local now = tick()
    if now - self._cacheTime >= self._cacheInterval then
        self:FindBall()
    end
end

-- ══════════════════════════════════════════════════════════════════════
-- LOGIC — COMBAT ENGINE
-- ══════════════════════════════════════════════════════════════════════
local CombatEngine = {
    _dome       = nil,
    _domeFlash  = nil,
}

function CombatEngine:_GetHRP()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function CombatEngine:_GetHum()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

function CombatEngine:_GetCamera()
    return game.Workspace.CurrentCamera
end

function CombatEngine:_ApplyCurve()
    local mode = Config.CurveMode
    if mode == "NONE" then return nil end
    local cam = self:_GetCamera()
    if not cam then return nil end
    local saved = cam.CFrame
    if mode == "LEFT" then
        cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(15), 0)
    elseif mode == "RIGHT" then
        cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(-15), 0)
    elseif mode == "SPIN" then
        cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(45), 0)
    end
    return saved
end

function CombatEngine:_RestoreCurve(saved)
    if not saved then return end
    local cam = self:_GetCamera()
    if cam then cam.CFrame = saved end
end

function CombatEngine:_ExecuteParry()
    local saved = self:_ApplyCurve()
    InputSim:Tap(Enum.KeyCode.F, 0.01)
    self:_RestoreCurve(saved)
    self:_FlashVisualizer()
    Logger:Debug("Parry executed")
end

function CombatEngine:_FlashVisualizer()
    if not Config.ShowParryVisualizer then return end
    if not self._dome then return end
    local dome = self._dome
    local ok, _ = pcall(function()
        local orig = dome.Color3
        dome.Color3 = Color3.fromRGB(80, 255, 120)
        task.delay(0.1, function()
            pcall(function() dome.Color3 = orig end)
        end)
    end)
end

function CombatEngine:RebuildDome()
    -- Clean old
    if self._dome then
        pcall(function() self._dome:Destroy() end)
        self._dome = nil
    end
    if not Config.ShowParryVisualizer then return end
    local hrp = self:_GetHRP()
    if not hrp then return end

    local sphere = Instance.new("SelectionSphere")
    sphere.SurfaceTransparency = 0.85
    sphere.SurfaceColor3      = Color3.fromRGB(100, 150, 255)
    sphere.Color3              = Color3.fromRGB(100, 150, 255)
    sphere.Adornee             = hrp
    sphere.Parent              = game:GetService("CoreGui"):FindFirstChild("RobloxGui") or game:GetService("CoreGui")

    Registry:Track("instances", sphere)
    self._dome = sphere
    self:_UpdateDomeSize()
end

function CombatEngine:_UpdateDomeSize()
    if not self._dome then return end
    pcall(function()
        self._dome.SizeRelativeOffset = Vector3.new(Config.ParryDistance, Config.ParryDistance, Config.ParryDistance)
    end)
end

function CombatEngine:Update(dt)
    if not Config.AutoParry then return end
    if not TargetScanner:IsTarget() then return end

    local dist = TargetScanner:GetBallDistance()
    local vel  = TargetScanner:GetBallVelocity()

    -- Network spike guard
    if vel.Magnitude > 100 then return end
    if not TargetScanner:IsApproaching() then return end

    local now  = tick()
    local hrp  = self:_GetHRP()
    if not hrp then return end

    if dist <= Config.SpamDistance then
        -- Spam parry
        if now - State.Combat.LastParry >= 0.01 then
            State.Combat.LastParry = now
            self:_ExecuteParry()
        end
    elseif dist > Config.SpamDistance and dist <= Config.ParryDistance and dist <= 55 then
        -- Ratio-based parry
        local ratio = dist / Config.ParryDistance
        if ratio <= 1.0 and now - State.Combat.LastParry >= 0.05 then
            State.Combat.LastParry = now
            self:_ExecuteParry()
        end
    end

    -- Auto ability Q
    if Config.AutoAbility and dist <= Config.SpamDistance then
        local ratio = dist / Config.ParryDistance
        if ratio < 1.0 and now - State.Combat.LastAbility >= 0.5 then
            State.Combat.LastAbility = now
            InputSim:Tap(Enum.KeyCode.Q, 0.01)
            Logger:Debug("Ability Q triggered")
        end
    end

    -- God mode: strip touch transmitters
    if Config.GodMode then
        local char = Player.Character
        if char then
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("TouchTransmitter") then v:Destroy() end
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════
-- LOGIC — MATCH DETECTOR
-- ══════════════════════════════════════════════════════════════════════
local MatchDetector = {
    _lastTransition = 0,
    _ballAbsent     = 0,
    _ballAbsentSince = 0,
}

function MatchDetector:_GetHRP()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function MatchDetector:_FindReadyZone()
    local candidates = {
        workspace:FindFirstChild("ReadyZone"),
        workspace:FindFirstChild("Lobby"),
        workspace:FindFirstChild("Spawn"),
    }
    for _, c in ipairs(candidates) do
        if c then return c end
    end
    return nil
end

function MatchDetector:Update()
    local now = tick()
    -- Debounce: min 2s between transitions
    if now - self._lastTransition < 2 then return end

    local hrp = self:_GetHRP()
    if not hrp then return end
    local pos = hrp.Position

    -- Cache ready zone position
    if not State.Match.ReadyZonePos then
        local rz = self:_FindReadyZone()
        if rz then
            State.Match.ReadyZonePos = rz:IsA("BasePart") and rz.Position
                or (rz:FindFirstChildOfClass("BasePart") and rz:FindFirstChildOfClass("BasePart").Position)
        end
    end

    local ballExists = State.Combat.CurrentBall and State.Combat.CurrentBall.Parent ~= nil

    if not ballExists then
        if self._ballAbsentSince == 0 then
            self._ballAbsentSince = now
        elseif now - self._ballAbsentSince > 10 and State.Match.InMatch then
            -- Ball gone > 10s → left match
            self:_SetMatch(false)
        end
    else
        self._ballAbsentSince = 0
    end

    if not State.Match.InMatch then
        -- Check entry conditions
        local teleported = false
        if State.Match.LastHRPPos then
            local delta = (pos - State.Match.LastHRPPos).Magnitude
            teleported = delta > Config.TeleportThreshold
        end

        local farFromReady = true
        if State.Match.ReadyZonePos then
            farFromReady = (pos - State.Match.ReadyZonePos).Magnitude > Config.SuddenMoveThreshold
        end

        local trigger = teleported or farFromReady
        if trigger and (not Config.RequireBallCheck or ballExists) then
            self:_SetMatch(true)
        end
    else
        -- Check exit conditions
        local nearReady = false
        if State.Match.ReadyZonePos then
            nearReady = (pos - State.Match.ReadyZonePos).Magnitude < 15
        end
        if nearReady then
            self:_SetMatch(false)
        end
    end

    State.Match.LastHRPPos = pos
end

function MatchDetector:_SetMatch(val)
    if State.Match.InMatch == val then return end
    State.Match.InMatch     = val
    State.Match.ConfirmedAt = tick()
    self._lastTransition    = tick()
    Logger:Info("Match state → " .. (val and "IN MATCH" or "LOBBY"))
    if val then
        Notifier:Send("🎮 Entered match!")
    else
        Notifier:Send("🏠 Returned to lobby")
    end
end

-- ══════════════════════════════════════════════════════════════════════
-- LOGIC — MOVEMENT FSM
-- ══════════════════════════════════════════════════════════════════════
local MovementFSM = {
    _priority = { JOIN = 3, FOLLOW = 2, WANDER = 1, IDLE = 0 },
}

function MovementFSM:_GetHRP()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function MovementFSM:_GetHum()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

function MovementFSM:Resolve()
    local candidates = {}
    if Config.AutoJoin and not State.Match.InMatch then
        table.insert(candidates, "JOIN")
    end
    if Config.AutoFollow and State.Match.InMatch then
        table.insert(candidates, "FOLLOW")
    end
    if Config.WanderMode and State.Match.InMatch then
        -- FOLLOW wins over WANDER (priority system handles it)
        table.insert(candidates, "WANDER")
    end

    table.sort(candidates, function(a, b)
        return self._priority[a] > self._priority[b]
    end)

    local next = candidates[1] or "IDLE"
    if next ~= State.Movement.Current then
        Logger:Debug("FSM: " .. State.Movement.Current .. " → " .. next)
        State.Movement.Current    = next
        State.Movement.TargetPos  = nil  -- reset target on transition
        State.Movement.StuckCounter = 0
    end
end

function MovementFSM:_AntiStuck(hum, hrp)
    local now = tick()
    local pos = hrp.Position

    if State.Movement.LastPos then
        local moved = (pos - State.Movement.LastPos).Magnitude
        if moved < 1 and now - State.Movement.LastMoveTick > 2 then
            State.Movement.StuckCounter = State.Movement.StuckCounter + 1
            if State.Movement.StuckCounter >= 3 then
                Logger:Warn("Stuck x3 — forcing IDLE reset")
            end
            -- Force idle 1 frame to cancel stuck MoveTo
            hum:Move(Vector3.new(0, 0, 0), false)
            State.Movement.TargetPos  = nil
            State.Movement.LastMoveTick = now
            return true  -- was stuck
        else
            State.Movement.StuckCounter = 0
        end
    end

    if State.Movement.LastPos == nil or (pos - State.Movement.LastPos).Magnitude > 0.1 then
        State.Movement.LastMoveTick = now
    end
    State.Movement.LastPos = pos
    return false
end

function MovementFSM:Update(dt)
    local hum = self:_GetHum()
    local hrp = self:_GetHRP()
    if not hum or not hrp or hum.Health <= 0 then return end

    self:Resolve()

    local stuck = self:_AntiStuck(hum, hrp)
    if stuck then return end

    local mode = State.Movement.Current

    if mode == "IDLE" then
        hum:Move(Vector3.new(0, 0, 0), false)

    elseif mode == "JOIN" then
        self:_DoJoin(hum, hrp)

    elseif mode == "FOLLOW" then
        self:_DoFollow(hum, hrp)

    elseif mode == "WANDER" then
        self:_DoWander(hum, hrp, dt)
    end
end

function MovementFSM:_DoJoin(hum, hrp)
    -- Move toward ready zone / join button
    local target = State.Match.ReadyZonePos
    if not target then
        -- Heuristic: find ReadyZone button in workspace
        local btn = workspace:FindFirstChild("JoinButton") or workspace:FindFirstChild("PlayButton")
        if btn and btn:IsA("BasePart") then target = btn.Position end
    end
    if not target then return end

    if not State.Movement.TargetPos or (target - State.Movement.TargetPos).Magnitude > 1 then
        hum:Move(Vector3.new(0, 0, 0), false)
        State.Movement.TargetPos = target
    end
    hum:MoveTo(target)
end

function MovementFSM:_DoFollow(hum, hrp)
    local ball = State.Combat.CurrentBall
    if not ball or not ball.Parent then return end

    local target = ball.Position
    if State.Movement.TargetPos and (target - State.Movement.TargetPos).Magnitude < 2 then
        return  -- no need to re-issue MoveTo
    end

    hum:Move(Vector3.new(0, 0, 0), false)
    State.Movement.TargetPos = target
    hum:MoveTo(target)
end

function MovementFSM:_DoWander(hum, hrp, dt)
    State.Movement.WanderTimer = (State.Movement.WanderTimer or 0) + dt
    if State.Movement.WanderTimer < Config.WanderInterval then
        return
    end
    State.Movement.WanderTimer = 0

    -- Pick random point within radius
    local angle  = math.random() * math.pi * 2
    local radius = math.random() * Config.WanderRadius
    local pos    = hrp.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

    hum:Move(Vector3.new(0, 0, 0), false)
    State.Movement.TargetPos = pos
    hum:MoveTo(pos)

    -- Random dash
    if math.random() < Config.DashChance then
        task.delay(0.1, function()
            InputSim:Tap(Enum.KeyCode.LeftShift, 0.05)
        end)
    end

    -- Random jump
    if math.random() < Config.JumpChance then
        task.delay(0.15, function()
            InputSim:Tap(Enum.KeyCode.Space, 0.05)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════════
-- LOGIC — ANTI IDLE
-- ══════════════════════════════════════════════════════════════════════
local AntiIdle = {}

function AntiIdle:Start()
    -- Periodic mouse click every 180s
    Registry:Track("threads", task.spawn(function()
        while true do
            task.wait(180)
            InputSim:Click(0, 0)
            Logger:Debug("Anti-AFK click sent")
        end
    end))

    -- React to Idled event
    Registry:Track("connections", Player.Idled:Connect(function()
        InputSim:Tap(Enum.KeyCode.Space, 0.05)
        Logger:Debug("Anti-AFK: Idled event → Space")
    end))
end

-- ══════════════════════════════════════════════════════════════════════
-- UI — THEME
-- ══════════════════════════════════════════════════════════════════════
local Theme = {
    bg        = Color3.fromRGB(20,  20,  30),
    card      = Color3.fromRGB(25,  25,  40),
    accent    = Color3.fromRGB(100, 150, 255),
    success   = Color3.fromRGB(80,  255, 120),
    danger    = Color3.fromRGB(255, 60,  60),
    text      = Color3.fromRGB(255, 255, 255),
    textDim   = Color3.fromRGB(150, 150, 200),
    font      = Enum.Font.GothamMedium,
    fontBold  = Enum.Font.GothamBold,
    corner    = UDim.new(0, 10),
    size      = {
        title  = 14,
        body   = 12,
        small  = 10,
    },
}

-- ══════════════════════════════════════════════════════════════════════
-- UI — SCREEN
-- ══════════════════════════════════════════════════════════════════════
local Screen = {
    _gui        = nil,
    _mainFrame  = nil,
    _visible    = true,
    _toggleBtn  = nil,
    _statusLabels = {},
}

function Screen:_GetCoreGui()
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok then return cg end
    local ok2, hg = pcall(function() return gethui() end)
    if ok2 then return hg end
    return nil
end

function Screen:_MakeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or Theme.corner
    c.Parent = parent
    return c
end

function Screen:_MakePadding(parent, px)
    local p = Instance.new("UIPadding")
    local u = UDim.new(0, px or 8)
    p.PaddingTop = u; p.PaddingBottom = u
    p.PaddingLeft = u; p.PaddingRight = u
    p.Parent = parent
end

function Screen:_MakeLabel(parent, text, size, color, bold)
    local l = Instance.new("TextLabel")
    l.Text              = text
    l.TextSize          = size or Theme.size.body
    l.TextColor3        = color or Theme.text
    l.Font              = bold and Theme.fontBold or Theme.font
    l.BackgroundTransparency = 1
    l.TextXAlignment    = Enum.TextXAlignment.Left
    l.Size              = UDim2.new(1, 0, 0, size and size + 4 or 20)
    l.Parent            = parent
    return l
end

function Screen:_MakeSeparator(parent)
    local f = Instance.new("Frame")
    f.Size              = UDim2.new(1, 0, 0, 1)
    f.BackgroundColor3  = Theme.accent
    f.BackgroundTransparency = 0.7
    f.BorderSizePixel   = 0
    f.Parent            = parent
    return f
end

function Screen:_MakeCard(parent, title)
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Theme.card
    card.BorderSizePixel  = 0
    card.Size             = UDim2.new(1, -16, 0, 0)
    card.AutomaticSize    = Enum.AutomaticSize.Y
    card.Parent           = parent
    self:_MakeCorner(card)
    self:_MakePadding(card, 10)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection     = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding            = UDim.new(0, 6)
    layout.Parent             = card

    if title then
        self:_MakeLabel(card, title, Theme.size.title, Theme.accent, true)
        self:_MakeSeparator(card)
    end

    return card
end

function Screen:_MakeToggle(parent, label, key, callback)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size                   = UDim2.new(1, 0, 0, 28)
    row.Parent                 = parent

    local lbl = Instance.new("TextLabel")
    lbl.Text              = label
    lbl.TextSize          = Theme.size.body
    lbl.TextColor3        = Theme.text
    lbl.Font              = Theme.font
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.Size              = UDim2.new(1, -50, 1, 0)
    lbl.Parent            = row

    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(0, 44, 0, 22)
    btn.Position          = UDim2.new(1, -44, 0.5, -11)
    btn.BorderSizePixel   = 0
    btn.Font              = Theme.fontBold
    btn.TextSize          = Theme.size.small
    btn.Parent            = row
    self:_MakeCorner(btn, UDim.new(0, 11))

    local function refresh()
        local val = Config[key]
        btn.Text             = val and "ON" or "OFF"
        btn.BackgroundColor3 = val and Theme.success or Theme.danger
        btn.TextColor3       = Theme.bg
    end
    refresh()

    btn.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        if key == "DebugMode" then Logger:SetDebug(Config[key]) end
        if key == "ShowParryVisualizer" then
            if Config[key] then CombatEngine:RebuildDome()
            else
                if CombatEngine._dome then
                    pcall(function() CombatEngine._dome:Destroy() end)
                    CombatEngine._dome = nil
                end
            end
        end
        refresh()
        FileIO:Save(Config)
        if callback then callback(Config[key]) end
    end)

    return row, refresh
end

function Screen:_MakeSlider(parent, label, key, min, max)
    local col = Instance.new("Frame")
    col.BackgroundTransparency = 1
    col.Size                   = UDim2.new(1, 0, 0, 48)
    col.Parent                 = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding       = UDim.new(0, 2)
    layout.Parent        = col

    local topRow = Instance.new("Frame")
    topRow.BackgroundTransparency = 1
    topRow.Size                   = UDim2.new(1, 0, 0, 20)
    topRow.Parent                 = col

    local lbl = self:_MakeLabel(topRow, label, Theme.size.body, Theme.text)
    lbl.Size = UDim2.new(0.7, 0, 1, 0)

    local valLbl = Instance.new("TextLabel")
    valLbl.TextSize   = Theme.size.body
    valLbl.TextColor3 = Theme.accent
    valLbl.Font       = Theme.fontBold
    valLbl.BackgroundTransparency = 1
    valLbl.Size       = UDim2.new(0.3, 0, 1, 0)
    valLbl.Position   = UDim2.new(0.7, 0, 0, 0)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent     = topRow

    local track = Instance.new("Frame")
    track.Size              = UDim2.new(1, 0, 0, 8)
    track.BackgroundColor3  = Color3.fromRGB(40, 40, 60)
    track.BorderSizePixel   = 0
    track.Parent            = col
    self:_MakeCorner(track, UDim.new(0, 4))

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Theme.accent
    fill.BorderSizePixel  = 0
    fill.Size             = UDim2.new(0, 0, 1, 0)
    fill.Parent           = track
    self:_MakeCorner(fill, UDim.new(0, 4))

    local function refresh()
        local val   = math.clamp(Config[key] or min, min, max)
        local pct   = (val - min) / (max - min)
        fill.Size   = UDim2.new(pct, 0, 1, 0)
        valLbl.Text = tostring(val)
    end
    refresh()

    -- Drag
    local dragging = false
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement and
           inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local abs = track.AbsolutePosition
        local sz  = track.AbsoluteSize
        local pct = math.clamp((inp.Position.X - abs.X) / sz.X, 0, 1)
        local val = math.floor(min + pct * (max - min) + 0.5)
        Config[key] = val
        refresh()
        FileIO:Save(Config)
    end)

    return col, refresh
end

function Screen:Build()
    -- Clean old
    if self._gui then
        pcall(function() self._gui:Destroy() end)
        self._gui = nil
    end

    local cg = self:_GetCoreGui()
    if not cg then Logger:Warn("No CoreGui — UI skipped"); return end

    -- Root ScreenGui
    local sg = Instance.new("ScreenGui")
    sg.Name               = "LanzDB_v4"
    sg.ResetOnSpawn       = false
    sg.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset     = true
    sg.Parent             = cg
    Registry:Track("instances", sg)
    self._gui = sg

    -- Toggle button (top-left)
    local tBtn = Instance.new("TextButton")
    tBtn.Name             = "ToggleBtn"
    tBtn.Size             = UDim2.new(0, 60, 0, 45)
    tBtn.Position         = UDim2.new(0, 10, 0, 10)
    tBtn.BackgroundColor3 = Theme.accent
    tBtn.TextColor3       = Theme.bg
    tBtn.Text             = "DB\nv4.0"
    tBtn.TextSize         = 11
    tBtn.Font             = Theme.fontBold
    tBtn.BorderSizePixel  = 0
    tBtn.ZIndex           = 10
    tBtn.Parent           = sg
    self:_MakeCorner(tBtn)
    self._toggleBtn = tBtn

    -- Main frame
    local main = Instance.new("Frame")
    main.Name             = "MainFrame"
    main.Size             = UDim2.new(0, 300, 0, 0)
    main.Position         = UDim2.new(0, 10, 0, 60)
    main.BackgroundColor3 = Theme.bg
    main.BorderSizePixel  = 0
    main.AutomaticSize    = Enum.AutomaticSize.Y
    main.ClipsDescendants = true
    main.Parent           = sg
    self:_MakeCorner(main)
    self._mainFrame = main

    -- Outline
    local stroke = Instance.new("UIStroke")
    stroke.Color     = Theme.accent
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent    = main

    -- Content layout
    local content = Instance.new("Frame")
    content.Name            = "Content"
    content.BackgroundTransparency = 1
    content.Size            = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize   = Enum.AutomaticSize.Y
    content.Parent          = main
    self:_MakePadding(content, 8)

    local cl = Instance.new("UIListLayout")
    cl.FillDirection        = Enum.FillDirection.Vertical
    cl.HorizontalAlignment  = Enum.HorizontalAlignment.Center
    cl.Padding              = UDim.new(0, 6)
    cl.Parent               = content

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.BackgroundColor3 = Theme.accent
    titleBar.BorderSizePixel  = 0
    titleBar.Size             = UDim2.new(1, 0, 0, 32)
    titleBar.Parent           = content
    self:_MakeCorner(titleBar)

    local titleLbl = self:_MakeLabel(titleBar, "  💀 Death Ball Bot  v4.0", Theme.size.title, Theme.bg, true)
    titleLbl.Size        = UDim2.new(1, 0, 1, 0)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Center

    -- ── STATUS MONITOR ──────────────────────────────────
    local statusCard = self:_MakeCard(content, "📊 Status Monitor")
    local statusMatch  = self:_MakeLabel(statusCard, "Match: —", Theme.size.body, Theme.textDim)
    local statusMode   = self:_MakeLabel(statusCard, "Mode:  —", Theme.size.body, Theme.textDim)
    local statusBall   = self:_MakeLabel(statusCard, "Ball:  —", Theme.size.body, Theme.textDim)
    local statusPath   = self:_MakeLabel(statusCard, "Path:  " .. FileIO:GetPath(), Theme.size.small, Theme.textDim)
    self._statusLabels = { match = statusMatch, mode = statusMode, ball = statusBall }

    -- ── CURVE MODE ───────────────────────────────────────
    local curveCard = self:_MakeCard(content, "🌀 Curve Mode")
    local curveModes = { "NONE", "LEFT", "RIGHT", "SPIN" }
    local curveLbl   = self:_MakeLabel(curveCard, "Current: " .. Config.CurveMode, Theme.size.body, Theme.accent)

    local curveBtn = Instance.new("TextButton")
    curveBtn.Size             = UDim2.new(1, 0, 0, 26)
    curveBtn.BackgroundColor3 = Theme.card
    curveBtn.TextColor3       = Theme.text
    curveBtn.Text             = "Cycle Mode →"
    curveBtn.Font             = Theme.font
    curveBtn.TextSize         = Theme.size.body
    curveBtn.BorderSizePixel  = 0
    curveBtn.Parent           = curveCard
    self:_MakeCorner(curveBtn)

    curveBtn.MouseButton1Click:Connect(function()
        local idx = table.find(curveModes, Config.CurveMode) or 1
        Config.CurveMode = curveModes[(idx % #curveModes) + 1]
        curveLbl.Text    = "Current: " .. Config.CurveMode
        FileIO:Save(Config)
    end)

    -- ── FARM SETTINGS ────────────────────────────────────
    local farmCard = self:_MakeCard(content, "🌾 Farm Settings")
    self:_MakeToggle(farmCard, "Auto Join Match", "AutoJoin")
    self:_MakeToggle(farmCard, "Auto Follow Ball", "AutoFollow")

    -- ── COMBAT ───────────────────────────────────────────
    local combatCard = self:_MakeCard(content, "⚔️ Combat")
    self:_MakeToggle(combatCard, "Auto Parry", "AutoParry")
    self:_MakeToggle(combatCard, "Parry Visualizer Dome", "ShowParryVisualizer")
    self:_MakeToggle(combatCard, "Auto Ability (Q)", "AutoAbility")
    self:_MakeToggle(combatCard, "God Mode", "GodMode")

    -- ── WANDER ───────────────────────────────────────────
    local wanderCard = self:_MakeCard(content, "🚶 Wander")
    self:_MakeToggle(wanderCard, "Wander Mode", "WanderMode")
    self:_MakeToggle(wanderCard, "In-Match Check", "InMatchCheck")
    self:_MakeLabel(wanderCard, "ℹ️  FOLLOW > WANDER (priority)", Theme.size.small, Theme.textDim)

    -- ── PARRY RANGE ──────────────────────────────────────
    local rangeCa... (12 KB left)
