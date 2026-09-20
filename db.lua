local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local env = getgenv()

local DEFAULT_CONFIG = {
    _version = "4.0",
    _savedAt = "",
    _game = tostring(game.GameId),
    _player = player and player.Name or "",
    AutoParry = true,
    SpamDistance = 6,
    ParryDistance = 10,
    ShowParryVisualizer = true,
    CurveMode = "NONE",
    AutoAbility = false,
    GodMode = false,
    AutoJoin = false,
    AutoFollow = false,
    WanderMode = false,
    WanderRadius = 60,
    WanderInterval = 3,
    DashChance = 0.35,
    JumpChance = 0.20,
    InMatchCheck = true,
    TeleportThreshold = 80,
    SuddenMoveThreshold = 50,
    RequireBallCheck = true,
    WebhookURL = "",
    WebhookInterval = 3600,
    DebugMode = false,
}

local ALLOWED_KEYS = {}
for key in pairs(DEFAULT_CONFIG) do
    ALLOWED_KEYS[key] = true
end

local Registry = {
    connections = {},
    instances = {},
    threads = {},
}

function Registry:Track(category, handle)
    if not self[category] then
        self[category] = {}
    end
    table.insert(self[category], handle)
    return handle
end

function Registry:DisconnectAll()
    for _, conn in ipairs(self.connections) do
        pcall(function()
            if conn and typeof(conn.Disconnect) == "function" then
                conn:Disconnect()
            end
        end)
    end
    self.connections = {}
end

function Registry:DestroyAll()
    for _, inst in ipairs(self.instances) do
        pcall(function()
            if inst and inst.Destroy then
                inst:Destroy()
            end
        end)
    end
    self.instances = {}
end

function Registry:StopAll()
    for _, th in ipairs(self.threads) do
        pcall(function()
            if th and task.cancel then
                task.cancel(th)
            end
        end)
    end
    self.threads = {}
end

function Registry:Reset()
    self:DisconnectAll()
    self:DestroyAll()
    self:StopAll()
end

local State = {
    Match = {
        InMatch = false,
        ConfirmedAt = 0,
        ReadyZonePos = nil,
        LastHRPPos = nil,
        LastTransition = 0,
    },
    Movement = {
        Current = "IDLE",
        TargetPos = nil,
        LastTarget = 0,
        LastMoveTick = tick(),
        LastPos = nil,
        StuckCounter = 0,
    },
    Combat = {
        LastParry = 0,
        CurrentBall = nil,
        LastBallCheck = 0,
    },
}

local Logger = {}

function Logger:Format(level, message)
    return "[Lanz v4.0] [" .. tostring(level) .. "] " .. tostring(message)
end

function Logger:Log(level, message)
    if level == "DEBUG" and not Config.Data.DebugMode then
        return
    end

    local text = self:Format(level, message)
    if level == "ERROR" then
        warn(text)
    elseif level == "WARN" then
        warn(text)
    else
        print(text)
    end
end

function Logger:Debug(message)
    self:Log("DEBUG", message)
end

function Logger:Info(message)
    self:Log("INFO", message)
end

function Logger:Warn(message)
    self:Log("WARN", message)
end

function Logger:Error(message)
    self:Log("ERROR", message)
end

local Config = {
    Data = {},
    SavePath = nil,
    DebounceHandle = nil,
}

function Config:CloneDefaults()
    local copy = {}
    for key, value in pairs(DEFAULT_CONFIG) do
        copy[key] = value
    end
    return copy
end

function Config:ValidateTable(raw)
    if type(raw) ~= "table" then
        return self:CloneDefaults()
    end

    local merged = self:CloneDefaults()
    for key, value in pairs(raw) do
        if ALLOWED_KEYS[key] then
            local defaultValue = DEFAULT_CONFIG[key]
            if type(defaultValue) == type(value) then
                merged[key] = value
            elseif defaultValue ~= nil then
                merged[key] = defaultValue
            end
        end
    end

    merged._version = DEFAULT_CONFIG._version
    merged._game = tostring(game.GameId)
    merged._player = player and player.Name or ""
    return merged
end

function Config:Load()
    local path = self:GetPath()
    self.SavePath = path

    if not path then
        self.Data = self:CloneDefaults()
        return self.Data
    end

    local ok, raw = pcall(function()
        if not isfile(path) then
            return nil
        end
        return HttpService:JSONDecode(readfile(path))
    end)

    if not ok or type(raw) ~= "table" then
        Logger:Warn("Config file missing or corrupted; using defaults.")
        self.Data = self:CloneDefaults()
        return self.Data
    end

    self.Data = self:ValidateTable(raw)
    self.Data._savedAt = os.date("%Y-%m-%d %H:%M:%S")
    return self.Data
end

function Config:Save(silent)
    local data = self.Data or self:CloneDefaults()
    if not data then
        return false
    end

    if not self.SavePath then
        self.SavePath = self:GetPath()
    end

    local payload = {}
    for key, _ in pairs(ALLOWED_KEYS) do
        payload[key] = data[key]
    end
    payload._version = DEFAULT_CONFIG._version
    payload._savedAt = os.date("%Y-%m-%d %H:%M:%S")
    payload._game = tostring(game.GameId)
    payload._player = player and player.Name or ""

    local json = HttpService:JSONEncode(payload)
    local path = self.SavePath
    if not path then
        return false
    end

    local ok, err = pcall(function()
        writefile(path, json)
    end)

    if not ok then
        Logger:Warn("Config save failed: " .. tostring(err))
        return false
    end

    if not silent then
        Logger:Info("Config saved to " .. tostring(path))
    end
    return true
end

function Config:RequestSave()
    if self.DebounceHandle then
        task.cancel(self.DebounceHandle)
    end

    self.DebounceHandle = task.delay(0.15, function()
        self:Save(true)
    end)
    Registry:Track("threads", self.DebounceHandle)
end

function Config:GetPath()
    local paths = {
        "LanzConfig/save.json",
        "Configs/Lanz/save.json",
        "Lanz_DB_save.json",
    }

    for _, path in ipairs(paths) do
        local dir = path:match("(.+)/[^/]+$")
        if dir and not isfolder(dir) then
            local ok = pcall(function()
                makefolder(dir)
            end)
            if not ok then
                continue
            end
        end

        if not isfile(path) then
            local ok, err = pcall(function()
                writefile(path, "{}")
            end)
            if ok then
                local status, _ = pcall(function()
                    delfile(path)
                end)
                if status then
                    return path
                end
            end
        else
            return path
        end
    end

    return "Lanz_DB_save.json"
end

function Config:Reset()
    local path = self:GetPath()
    if isfile(path) then
        pcall(function()
            delfile(path)
        end)
    end
    self.Data = self:CloneDefaults()
    self:Save(true)
    Logger:Info("Config reset to defaults.")
end

local FileIO = {}

function FileIO:GetPath()
    return Config:GetPath()
end

function FileIO:Load()
    return Config:Load()
end

function FileIO:Save(silent)
    return Config:Save(silent)
end

function FileIO:Reset()
    return Config:Reset()
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function getCharacter()
    if not player then
        return nil
    end
    return player.Character
end

local function getHumanoid()
    local character = getCharacter()
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
    local character = getCharacter()
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getBall()
    local workspace = game:GetService("Workspace")
    local nearest = nil
    local nearestDistance = math.huge
    local root = getRootPart()
    local rootPos = root and root.Position or Vector3.new()

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local name = descendant.Name:lower()
            if name == "ball" or name:find("ball") then
                local distance = (descendant.Position - rootPos).Magnitude
                if distance < nearestDistance then
                    nearest = descendant
                    nearestDistance = distance
                end
            end
        end
    end

    return nearest
end

local TargetScanner = {
    lastScan = 0,
    ball = nil,
}

function TargetScanner:RefreshBall()
    local now = os.clock()
    if now - self.lastScan >= 0.5 or self.ball == nil then
        self.ball = getBall()
        self.lastScan = now
    end
    return self.ball
end

function TargetScanner:GetBall()
    return self:RefreshBall()
end

function TargetScanner:IsTarget()
    local character = getCharacter()
    if not character then
        return false
    end

    local highlight = character:FindFirstChild("Highlight")
    if not highlight then
        return false
    end

    local fillTransparency = highlight.FillTransparency
    if typeof(fillTransparency) == "number" then
        return fillTransparency < 1
    end

    return false
end

local InputSim = {}

function InputSim:Guard()
    local humanoid = getHumanoid()
    if not humanoid then
        return false
    end
    if humanoid.Health <= 0 then
        return false
    end
    return true
end

function InputSim:KeyDown(key)
    if not self:Guard() then
        return
    end
    local keyCode = typeof(key) == "EnumItem" and key or Enum.KeyCode[key]
    if not keyCode then
        return
    end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    end)
end

function InputSim:KeyUp(key)
    if not self:Guard() then
        return
    end
    local keyCode = typeof(key) == "EnumItem" and key or Enum.KeyCode[key]
    if not keyCode then
        return
    end
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)
end

function InputSim:Tap(key, duration)
    local actualKey = typeof(key) == "EnumItem" and key or Enum.KeyCode[key]
    if not actualKey then
        return
    end
    self:KeyDown(actualKey)
    task.delay(duration or 0.01, function()
        self:KeyUp(actualKey)
    end)
end

function InputSim:MoveMouse(x, y)
    if not self:Guard() then
        return
    end
    pcall(function()
        VirtualInputManager:SendMouseMoveEvent(x, y, x, y)
    end)
end

local function createSingletonPart(name, color, size, cframe)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.Transparency = 0.3
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Size = size or Vector3.new(1, 1, 1)
    part.CFrame = cframe or CFrame.new()
    part.Parent = workspace
    Registry:Track("instances", part)
    return part
end

local CombatEngine = {
    visualizer = nil,
}

function CombatEngine:FlashVisualizer()
    if not Config.Data.ShowParryVisualizer then
        return
    end
    local root = getRootPart()
    if not root then
        return
    end

    if self.visualizer and self.visualizer.Parent then
        self.visualizer:Destroy()
    end

    local part = createSingletonPart("LanzDB_ParryVisualizer", Color3.fromRGB(80, 255, 120), Vector3.new(6, 6, 6), CFrame.new(root.Position))
    part.Shape = Enum.PartType.Cylinder
    part.Orientation = Vector3.new(90, 0, 0)
    part.Transparency = 0.35
    self.visualizer = part

    task.delay(0.1, function()
        if self.visualizer and self.visualizer.Parent then
            self.visualizer:Destroy()
        end
        self.visualizer = nil
    end)
end

function CombatEngine:IsApproaching(ball)
    local root = getRootPart()
    if not root or not ball then
        return false
    end

    local directionToBall = (ball.Position - root.Position)
    local velocity = ball.Velocity
    local speed = velocity.Magnitude
    if speed <= 0 then
        return false
    end

    return directionToBall.Unit:Dot(velocity.Unit) < 0
end

function CombatEngine:CanExecParry()
    local cfg = Config.Data
    if not cfg.AutoParry then
        return false
    end

    local hero = getCharacter()
    if not hero then
        return false
    end

    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if not TargetScanner:IsTarget() then
        return false
    end

    local ball = TargetScanner:GetBall()
    if not ball then
        return false
    end

    local root = getRootPart()
    if not root then
        return false
    end

    local distance = (root.Position - ball.Position).Magnitude
    local speed = ball.Velocity.Magnitude
    if speed > 100 then
        return false
    end

    if not self:IsApproaching(ball) then
        return false
    end

    local ratio = speed == 0 and 0 or (distance / speed)
    local shouldParry = false

    if distance <= cfg.SpamDistance then
        shouldParry = true
    elseif distance <= 55 and ratio <= cfg.ParryDistance then
        shouldParry = true
    end

    return shouldParry
end

function CombatEngine:ExecuteParry()
    local now = os.clock()
    if now - State.Combat.LastParry < 0.01 then
        return
    end

    State.Combat.LastParry = now
    local camera = workspace.CurrentCamera
    local oldCFrame = camera and camera.CFrame

    if camera then
        camera.CFrame = camera.CFrame * CFrame.Angles(0, math.rad(8), 0)
    end

    InputSim:Tap("F", 0.01)

    if camera and oldCFrame then
        camera.CFrame = oldCFrame
    end

    self:FlashVisualizer()

    if Config.Data.AutoAbility then
        local ball = TargetScanner:GetBall()
        if ball then
            local distance = (getRootPart().Position - ball.Position).Magnitude
            local speed = ball.Velocity.Magnitude
            local ratio = speed == 0 and 0 or (distance / speed)
            if distance <= 6 and ratio < 1 then
                InputSim:Tap("Q", 0.02)
            end
        end
    end
end

function CombatEngine:Update()
    if not self:CanExecParry() then
        return
    end

    self:ExecuteParry()
end

local MovementFSM = {
    current = "IDLE",
    nextWanderAt = 0,
    lastForceIdle = 0,
}

function MovementFSM:GetPriority(name)
    local weights = {
        JOIN = 3,
        FOLLOW = 2,
        WANDER = 1,
        IDLE = 0,
    }
    return weights[name] or 0
end

function MovementFSM:Resolve()
    local candidates = {}
    local cfg = Config.Data

    if cfg.AutoJoin and not State.Match.InMatch then
        table.insert(candidates, "JOIN")
    end

    if cfg.AutoFollow and State.Match.InMatch then
        table.insert(candidates, "FOLLOW")
    end

    if cfg.WanderMode and State.Match.InMatch then
        table.insert(candidates, "WANDER")
    end

    if #candidates == 0 then
        self.current = "IDLE"
        return self.current
    end

    table.sort(candidates, function(a, b)
        return self:GetPriority(a) > self:GetPriority(b)
    end)

    self.current = candidates[1]
    return self.current
end

function MovementFSM:Idle()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    humanoid:Move(Vector3.zero, false)
    State.Movement.TargetPos = nil
end

function MovementFSM:MoveTo(position)
    local humanoid = getHumanoid()
    if not humanoid or not position then
        return
    end

    humanoid:Move(Vector3.zero, false)
    State.Movement.TargetPos = position
    humanoid:MoveTo(position)
end

function MovementFSM:MoveToReadyZone()
    local root = getRootPart()
    local readyZone = State.Match.ReadyZonePos
    if not root or not readyZone then
        return
    end

    local distance = (root.Position - readyZone).Magnitude
    if distance > 5 then
        self:MoveTo(readyZone)
    else
        self:Idle()
    end
end

function MovementFSM:FollowBall()
    local ball = TargetScanner:GetBall()
    local humanoid = getHumanoid()
    if not ball or not humanoid then
        return
    end

    local targetPos = ball.Position + Vector3.new(0, 3, 0)
    self:MoveTo(targetPos)
end

function MovementFSM:Wander()
    local root = getRootPart()
    if not root then
        return
    end

    local radius = Config.Data.WanderRadius
    local offsetX = (math.random() - 0.5) * radius * 2
    local offsetZ = (math.random() - 0.5) * radius * 2
    local targetPos = Vector3.new(
        root.Position.X + offsetX,
        root.Position.Y,
        root.Position.Z + offsetZ
    )

    if math.random() < Config.Data.DashChance then
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.Jump = true
        end
    end

    self:MoveTo(targetPos)
    self.nextWanderAt = os.clock() + (Config.Data.WanderInterval or 3)
end

function MovementFSM:CheckStuck()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    local root = getRootPart()
    if not root then
        return
    end

    local now = tick()
    if not State.Movement.LastPos then
        State.Movement.LastPos = root.Position
        State.Movement.LastMoveTick = now
        return
    end

    local distanceMoved = (root.Position - State.Movement.LastPos).Magnitude
    if distanceMoved > 0.5 then
        State.Movement.LastPos = root.Position
        State.Movement.LastMoveTick = now
        State.Movement.StuckCounter = 0
        return
    end

    if now - State.Movement.LastMoveTick > 2 then
        State.Movement.StuckCounter = State.Movement.StuckCounter + 1
        humanoid:Move(Vector3.zero, false)
        State.Movement.TargetPos = nil
        State.Movement.Current = "IDLE"
        State.Movement.LastMoveTick = now

        if State.Movement.StuckCounter >= 3 then
            Logger:Warn("Movement stuck detected; resetting target.")
            State.Movement.StuckCounter = 0
        end
    end
end

function MovementFSM:Update()
    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local stateName = self:Resolve()
    State.Movement.Current = stateName

    if stateName == "JOIN" then
        self:MoveToReadyZone()
    elseif stateName == "FOLLOW" then
        self:FollowBall()
    elseif stateName == "WANDER" then
        if os.clock() >= self.nextWanderAt then
            self:Wander()
        end
    else
        self:Idle()
    end

    self:CheckStuck()
end

local MatchDetector = {}

function MatchDetector:CaptureReadyZone()
    local root = getRootPart()
    if root then
        State.Match.ReadyZonePos = root.Position
    end
end

function MatchDetector:EnterMatch()
    local now = os.clock()
    if now - State.Match.LastTransition < 2 then
        return
    end
    State.Match.LastTransition = now
    State.Match.InMatch = true
    State.Match.ConfirmedAt = now
    Logger:Info("Match entered.")
end

function MatchDetector:ExitMatch()
    local now = os.clock()
    if now - State.Match.LastTransition < 2 then
        return
    end
    State.Match.LastTransition = now
    State.Match.InMatch = false
    Logger:Info("Match exited.")
end

function MatchDetector:Update()
    local root = getRootPart()
    if not root then
        return
    end

    local now = os.clock()
    local prevPos = State.Match.LastHRPPos or root.Position
    local delta = (root.Position - prevPos).Magnitude
    local readyZone = State.Match.ReadyZonePos or root.Position
    local farFromReady = (root.Position - readyZone).Magnitude > (Config.Data.TeleportThreshold or 80)
    local ballExists = TargetScanner:GetBall() ~= nil

    if not State.Match.ReadyZonePos then
        self:CaptureReadyZone()
    end

    if delta > (Config.Data.SuddenMoveThreshold or 50) or farFromReady then
        if Config.Data.RequireBallCheck then
            if ballExists then
                self:EnterMatch()
            end
        else
            self:EnterMatch()
        end
    end

    if State.Match.InMatch then
        if (root.Position - readyZone).Magnitude < 15 then
            self:ExitMatch()
        elseif not ballExists and now - State.Match.ConfirmedAt > 10 then
            self:ExitMatch()
        end
    end

    State.Match.LastHRPPos = root.Position
end

local AntiIdle = {}

function AntiIdle:Start()
    local thread = task.spawn(function()
        while true do
            task.wait(180)
            local humanoid = getHumanoid()
            if humanoid and humanoid.Health > 0 then
                InputSim:MoveMouse(0, 0)
                InputSim:KeyDown("Space")
                task.delay(0.05, function()
                    InputSim:KeyUp("Space")
                end)
            end
        end
    end)

    Registry:Track("threads", thread)
end

local Notifier = {
    lastRequestAt = 0,
}

function Notifier:Request(payload)
    local config = Config.Data
    if type(config.WebhookURL) ~= "string" or config.WebhookURL == "" then
        return
    end

    local now = os.clock()
    if now - self.lastRequestAt < 5 then
        return
    end

    self.lastRequestAt = now

    local http = (syn and syn.request) or (http and http.request) or (http_request and http_request)
    if not http then
        return
    end

    local ok, response = pcall(function()
        return http({
            Url = config.WebhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = HttpService:JSONEncode(payload),
            Timeout = 10,
        })
    end)

    if not ok then
        Logger:Warn("Webhook request failed: " .. tostring(response))
    end
end

function Notifier:SendStatus()
    local root = getRootPart()
    local payload = {
        embeds = {
            {
                title = "Death Ball Bot",
                description = "Status update",
                color = 3066993,
                fields = {
                    { name = "Player", value = player and player.Name or "Unknown", inline = true },
                    { name = "Match", value = tostring(State.Match.InMatch), inline = true },
                    { name = "Position", value = root and tostring(root.Position) or "N/A", inline = false },
                    { name = "Config Path", value = tostring(Config.SavePath or "n/a"), inline = false },
                },
                footer = { text = "Lanz v4.0" },
            },
        },
    }
    self:Request(payload)
end

function Notifier:Start()
    local interval = Config.Data.WebhookInterval or 3600
    local thread = task.spawn(function()
        while true do
            task.wait(interval)
            local ok, err = pcall(function()
                self:SendStatus()
            end)
            if not ok then
                Logger:Warn("Webhook thread error: " .. tostring(err))
            end
        end
    end)

    Registry:Track("threads", thread)
end

local Theme = {
    bg = Color3.fromRGB(20, 20, 30),
    card = Color3.fromRGB(25, 25, 40),
    accent = Color3.fromRGB(100, 150, 255),
    success = Color3.fromRGB(80, 255, 120),
    danger = Color3.fromRGB(255, 60, 60),
    text = Color3.fromRGB(255, 255, 255),
    textDim = Color3.fromRGB(150, 150, 200),
    font = Enum.Font.GothamMedium,
    fontBold = Enum.Font.GothamBold,
    corner = UDim.new(0, 10),
}

local UI = {
    ScreenGui = nil,
    ToggleButton = nil,
    MainFrame = nil,
    StatusLabel = nil,
    ConfigPathLabel = nil,
    Body = nil,
}

local function createCorner(instance)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.corner
    corner.Parent = instance
    Registry:Track("instances", corner)
    return corner
end

local function createTextLabel(parent, text, size, position, font, textSize, color)
    local label = Instance.new("TextLabel")
    label.Parent = parent
    label.BackgroundTransparency = 1
    label.Text = text
    label.Size = size
    label.Position = position
    label.Font = font or Theme.font
    label.TextSize = textSize or 14
    label.TextColor3 = color or Theme.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.RichText = true
    Registry:Track("instances", label)
    return label
end

function UI:Build()
    if self.ScreenGui and self.ScreenGui.Parent then
        return
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LanzDB_UI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = CoreGui
    Registry:Track("instances", screenGui)
    self.ScreenGui = screenGui

    local toggle = Instance.new("TextButton")
    toggle.Name = "ToggleButton"
    toggle.Size = UDim2.new(0, 60, 0, 45)
    toggle.Position = UDim2.new(0, 20, 0, 20)
    toggle.BackgroundColor3 = Theme.accent
    toggle.Text = "DB"
    toggle.TextColor3 = Theme.text
    toggle.Font = Theme.fontBold
    toggle.TextSize = 20
    toggle.Parent = screenGui
    Registry:Track("instances", toggle)
    self.ToggleButton = toggle

    createCorner(toggle)

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 300, 0, 540)
    main.Position = UDim2.new(0.5, -150, 0.5, -270)
    main.BackgroundColor3 = Theme.card
    main.BorderSizePixel = 0
    main.Parent = screenGui
    Registry:Track("instances", main)
    self.MainFrame = main
    createCorner(main)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Theme.bg
    header.BorderSizePixel = 0
    header.Parent = main
    Registry:Track("instances", header)

    createCorner(header)

    local title = createTextLabel(header, "Death Ball Bot v4.0", UDim2.new(1, -20, 1, 0), UDim2.new(0, 10, 0, 0), Theme.fontBold, 18, Theme.text)
    title.TextXAlignment = Enum.TextXAlignment.Left

    local scroller = Instance.new("ScrollingFrame")
    scroller.Size = UDim2.new(1, -12, 1, -52)
    scroller.Position = UDim2.new(0, 6, 0, 46)
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.CanvasSize = UDim2.new(0, 0, 0, 800)
    scroller.ScrollBarThickness = 6
    scroller.Parent = main
    Registry:Track("instances", scroller)
    self.Body = scroller

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 8)
    list.Parent = scroller
    Registry:Track("instances", list)

    local statusCard = Instance.new("Frame")
    statusCard.Size = UDim2.new(1, -10, 0, 110)
    statusCard.BackgroundColor3 = Theme.bg
    statusCard.Parent = scroller
    createCorner(statusCard)
    Registry:Track("instances", statusCard)

    local statusTitle = createTextLabel(statusCard, "Status Monitor", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 0), Theme.fontBold, 15, Theme.accent)
    statusTitle.TextYAlignment = Enum.TextYAlignment.Top

    self.StatusLabel = createTextLabel(statusCard, "State: IDLE\nMatch: false\nPath: Loading...", UDim2.new(1, -20, 1, -28), UDim2.new(0, 10, 0, 24), Theme.font, 13, Theme.textDim)
    self.StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
    self.StatusLabel.TextWrapped = true

    local configCard = Instance.new("Frame")
    configCard.Size = UDim2.new(1, -10, 0, 120)
    configCard.BackgroundColor3 = Theme.bg
    configCard.Parent = scroller
    createCorner(configCard)
    Registry:Track("instances", configCard)

    local configTitle = createTextLabel(configCard, "Config", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 0), Theme.fontBold, 15, Theme.accent)
    configTitle.TextYAlignment = Enum.TextYAlignment.Top

    self.ConfigPathLabel = createTextLabel(configCard, "Path: " .. tostring(Config.SavePath or "unknown"), UDim2.new(1, -20, 1, -30), UDim2.new(0, 10, 0, 24), Theme.font, 12, Theme.textDim)
    self.ConfigPathLabel.TextYAlignment = Enum.TextYAlignment.Top
    self.ConfigPathLabel.TextWrapped = true

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.45, 0, 0, 28)
    saveBtn.Position = UDim2.new(0.05, 0, 1, -36)
    saveBtn.Text = "Save"
    saveBtn.BackgroundColor3 = Theme.success
    saveBtn.TextColor3 = Theme.text
    saveBtn.Font = Theme.fontBold
    saveBtn.TextSize = 14
    saveBtn.Parent = configCard
    createCorner(saveBtn)
    Registry:Track("instances", saveBtn)

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0.45, 0, 0, 28)
    resetBtn.Position = UDim2.new(0.52, 0, 1, -36)
    resetBtn.Text = "Reset"
    resetBtn.BackgroundColor3 = Theme.danger
    resetBtn.TextColor3 = Theme.text
    resetBtn.Font = Theme.fontBold
    resetBtn.TextSize = 14
    resetBtn.Parent = configCard
    createCorner(resetBtn)
    Registry:Track("instances", resetBtn)

    saveBtn.MouseButton1Click:Connect(function()
        pcall(function()
            Config:Save(false)
        end)
    end)

    resetBtn.MouseButton1Click:Connect(function()
        pcall(function()
            Config:Reset()
        end)
    end)

    toggle.MouseButton1Click:Connect(function()
        local isVisible = main.Visible
        main.Visible = not isVisible
    end)

    self:RefreshStatus()
end

function UI:RefreshStatus()
    if not self.StatusLabel or not self.MainFrame then
        return
    end

    local pathText = Config.SavePath or "unknown"
    self.StatusLabel.Text = string.format(
        "State: %s\nMatch: %s\nPath: %s",
        State.Movement.Current,
        tostring(State.Match.InMatch),
        pathText
    )

    if self.ConfigPathLabel then
        self.ConfigPathLabel.Text = "Path: " .. tostring(pathText)
    end
end

local function bootHeartbeat()
    local heartbeat = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(function()
            if not player or not getCharacter() then
                return
            end

            TargetScanner:GetBall()
            MatchDetector:Update()
            CombatEngine:Update()
            MovementFSM:Update()
            UI:RefreshStatus()
        end)

        if not ok then
            Logger:Warn("Heartbeat error: " .. tostring(err))
        end
    end)

    Registry:Track("connections", heartbeat)
end

local function startWatchdog()
    task.spawn(function()
        while true do
            task.wait(1)
            local ok, err = pcall(function()
                local ball = TargetScanner:GetBall()
                if not ball then
                    State.Combat.CurrentBall = nil
                else
                    State.Combat.CurrentBall = ball
                end

                if not UI.ScreenGui or not UI.ScreenGui.Parent then
                    UI:Build()
                end

                if not player or not getCharacter() then
                    State.Match.InMatch = false
                end
            end)

            if not ok then
                Logger:Warn("Watchdog error: " .. tostring(err))
            end
        end
    end)
end

local Boot = {}

function Boot:Init()
    self:CleanupLegacy()
    Registry:Reset()

    Config.Data = Config:Load()
    Config.SavePath = Config:GetPath()
    State.Match.ReadyZonePos = getRootPart() and getRootPart().Position or nil

    UI:Build()
    bootHeartbeat()
    AntiIdle:Start()
    Notifier:Start()
    startWatchdog()
    Logger:Info("Boot complete. LanzDB ready.")
end

function Boot:CleanupLegacy()
    if env.LanzDB then
        pcall(function()
            if env.LanzDB.Shutdown then
                env.LanzDB.Shutdown()
            end
        end)
    end
end

function Boot:Shutdown()
    Registry:Reset()
    if UI.ScreenGui and UI.ScreenGui.Parent then
        UI.ScreenGui:Destroy()
    end
    if env.LanzDB == LanzDB then
        env.LanzDB = nil
    end
    Logger:Info("LanzDB shutdown complete.")
end

local LanzDB = {
    Save = function()
        return FileIO:Save(false)
    end,
    Load = function()
        return FileIO:Load()
    end,
    Reset = function()
        return FileIO:Reset()
    end,
    ShowConfig = function()
        return Config.Data
    end,
    ShowPath = function()
        return Config.SavePath or FileIO:GetPath()
    end,
    GetState = function()
        return {
            match = State.Match,
            movement = State.Movement,
            combat = State.Combat,
        }
    end,
    SetDebug = function(value)
        Config.Data.DebugMode = value == true
        return Config.Data.DebugMode
    end,
    Shutdown = function()
        return Boot:Shutdown()
    end,
    Reload = function()
        Boot:Shutdown()
        task.delay(0.1, function()
            Boot:Init()
        end)
    end,
}

env.LanzDB = LanzDB

local function onCharacterAdded(character)
    if character then
        task.delay(0.5, function()
            if not State.Match.ReadyZonePos then
                MatchDetector:CaptureReadyZone()
            end
        end)
    end
end

if player then
    if player.Character then
        onCharacterAdded(player.Character)
    end
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(character)
    end)
end

Boot:Init()
