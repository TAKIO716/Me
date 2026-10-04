--[[
    ═══════════════════════════════════════════════════════════
    FAST CLIMB UI v1.5
    - NEW: AUTO FARM MODE (teleport → climb → jump → fall → repeat)
    - NEW: FULL UNLOAD (cleanup semua connection)
    - Editable value (input angka berapapun)
    - ALL ON / ALL OFF + keybind Ctrl
    ═══════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ============================================
-- CONFIG
-- ============================================
local Config = {
    -- Manual modes
    WalkSpeedEnabled = false,
    WalkSpeedValue = 80,
    TrussEnabled = false,
    TrussSpeed = 100,
    VelocityEnabled = false,
    VelocitySpeed = 80,
    TeleportEnabled = false,
    TeleportStep = 3,
    TeleportInterval = 0.1,
    AutoDetect = true,
    
    -- Auto Farm Mode
    AutoFarmEnabled = false,
    AutoFarmSearchRadius = 500,
    AutoFarmClimbSpeed = 120,
    AutoFarmJumpHeight = 5,        -- jump offset dari top ladder
    AutoFarmClimbTimeout = 15,     -- max detik climb
    AutoFarmFallDelay = 2,         -- tunggu jatuh
    AutoFarmCollectDelay = 1.5,    -- tunggu reward
    AutoFarmLoopDelay = 0.5,       -- jeda antar cycle
    AutoFarmTeleportOffset = 3,    -- offset dari ladder
    AutoFarmMaxCycles = 0,         -- 0 = infinite
}

-- ============================================
-- STATE
-- ============================================
local State = {
    onTruss = false,
    teleportActive = false,
    velocityActive = false,
    currentVelocity = nil,
    -- Auto farm state
    autoFarmPhase = "idle",  -- idle | teleport | climb | jump | fall | collect
    autoFarmCycles = 0,
    autoFarmTarget = nil,
    autoFarmStartY = 0,
    autoFarmTargetY = 0,
    autoFarmPhaseStart = 0,
}

local Stats = {
    ticks = 0,
    trussDetected = 0,
    velocityApplied = 0,
    teleportsDone = 0,
    autoFarmCycles = 0,
}

local ToggleRegistry = {}
local SliderRegistry = {}
local Connections = {}  -- track semua connection buat cleanup
local Instances = {}    -- track instance buat cleanup
local IsUnloaded = false

-- Helper untuk track connection
local function trackConn(conn)
    table.insert(Connections, conn)
    return conn
end

-- ============================================
-- UI SETUP
-- ============================================
local parentGui
if gethui then
    local ok, r = pcall(gethui)
    if ok and r then parentGui = r end
end
if not parentGui then parentGui = LocalPlayer:WaitForChild("PlayerGui") end

local existing = parentGui:FindFirstChild("FastClimbUI")
if existing then existing:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "FastClimbUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 99999
screen.Parent = parentGui
table.insert(Instances, screen)

local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(0, 50, 0, 50)
reopenBtn.Position = UDim2.new(0, 15, 0.4, 0)
reopenBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
reopenBtn.Text = "FC"
reopenBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
reopenBtn.Font = Enum.Font.GothamBold
reopenBtn.TextSize = 18
reopenBtn.Visible = false
reopenBtn.Parent = screen

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 720, 0, 620)
main.Position = UDim2.new(0.5, -360, 0.5, -310)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
main.Active = true
main.Parent = screen
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(100, 120, 200)
stroke.Thickness = 1.5

-- Title
local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
title.BorderSizePixel = 0
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -280, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Fast Climb UI v1.5"
titleLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.Parent = title

-- ============================================
-- LOG SYSTEM
-- ============================================
local LogConsole = { lines = {}, text = "", maxLines = 200 }
local consoleLbl = nil
local consoleScroll = nil

local function log(text)
    if IsUnloaded then return end
    table.insert(LogConsole.lines, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(text))
    while #LogConsole.lines > LogConsole.maxLines do 
        table.remove(LogConsole.lines, 1) 
    end
    LogConsole.text = table.concat(LogConsole.lines, "\n")
    if consoleLbl then
        consoleLbl.Text = LogConsole.text
        task.defer(function()
            if consoleScroll then
                consoleScroll.CanvasPosition = Vector2.new(0, consoleScroll.AbsoluteCanvasSize.Y)
            end
        end)
    end
    print("[FastClimb] " .. tostring(text))
end

local function clearLog()
    LogConsole.lines = {}
    LogConsole.text = ""
    if consoleLbl then consoleLbl.Text = "" end
    if consoleScroll then consoleScroll.CanvasPosition = Vector2.new(0, 0) end
end

-- ============================================
-- AUTO FARM LOGIC
-- ============================================
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Cari TrussPart terdekat
local function findNearestTruss(radius)
    local hrp = getHRP()
    if not hrp then return nil end
    
    local nearest = nil
    local nearestDist = math.huge
    
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("TrussPart") then
            local dist = (obj.Position - hrp.Position).Magnitude
            if dist < radius and dist < nearestDist then
                nearest = obj
                nearestDist = dist
            end
        end
    end
    
    return nearest, nearestDist
end

-- Cari top Y dari TrussPart
local function getTrussTopY(truss)
    if not truss then return nil end
    return truss.Position.Y + (truss.Size.Y / 2)
end

-- Reset auto farm state
local function resetAutoFarm()
    State.autoFarmPhase = "idle"
    State.autoFarmCycles = 0
    State.autoFarmTarget = nil
    State.autoFarmStartY = 0
    State.autoFarmTargetY = 0
    State.autoFarmPhaseStart = 0
    Stats.autoFarmCycles = 0
end

-- Auto Farm main logic
local function updateAutoFarm(now)
    if not Config.AutoFarmEnabled then
        if State.autoFarmPhase ~= "idle" then
            resetAutoFarm()
            log("[Auto] Disabled, resetting")
        end
        return
    end
    
    local hrp = getHRP()
    local humanoid = getHumanoid()
    if not hrp or not humanoid or humanoid.Health <= 0 then return end
    
    local phase = State.autoFarmPhase
    local phaseTime = now - State.autoFarmPhaseStart
    
    -- ============ PHASE: IDLE ============
    if phase == "idle" then
        -- Cek max cycles
        if Config.AutoFarmMaxCycles > 0 and Stats.autoFarmCycles >= Config.AutoFarmMaxCycles then
            log("[Auto] Max cycles reached (" .. Config.AutoFarmMaxCycles .. "), stopping")
            Config.AutoFarmEnabled = false
            return
        end
        
        -- Cari truss
        local truss, dist = findNearestTruss(Config.AutoFarmSearchRadius)
        if truss then
            State.autoFarmTarget = truss
            State.autoFarmPhase = "teleport"
            State.autoFarmPhaseStart = now
            log(string.format("[Auto] Target found: %s (dist=%.1f)", truss.Name, dist))
        else
            -- Log tiap 3 detik
            if phaseTime > 3 then
                State.autoFarmPhaseStart = now
                log("[Auto] Searching truss...")
            end
        end
    end
    
    -- ============ PHASE: TELEPORT ============
    elseif phase == "teleport" then
        local target = State.autoFarmTarget
        if not target or not target.Parent then
            log("[Auto] Target lost")
            State.autoFarmPhase = "idle"
            return
        end
        
        -- Teleport ke base truss + offset
        local targetPos = target.Position 
        local baseY = targetPos.Y - (target.Size.Y / 2)
        local teleportPos = Vector3.new(
            targetPos.X,
            baseY + Config.AutoFarmTeleportOffset,
            targetPos.Z
        )
        
        hrp.CFrame = CFrame.new(teleportPos)
        
        State.autoFarmStartY = teleportPos.Y
        State.autoFarmTargetY = getTrussTopY(target)
        State.autoFarmPhase = "climb"
        State.autoFarmPhaseStart = now
        
        log(string.format("[Auto] Teleported to base Y=%.1f, target Y=%.1f", 
            State.autoFarmStartY, State.autoFarmTargetY))
    end
    
    -- ============ PHASE: CLIMB ============
    elseif phase == "climb" then
        local target = State.autoFarmTarget
        if not target or not target.Parent then
            State.autoFarmPhase = "idle"
            return
        end
        
        -- Timeout
        if phaseTime > Config.AutoFarmClimbTimeout then
            log("[Auto] Climb timeout!")
            State.autoFarmPhase = "idle"
            return
        end
        
        -- Force climb velocity
        local climbY = Config.AutoFarmClimbSpeed
        hrp.AssemblyLinearVelocity = Vector3.new(0, climbY, 0)
        
        -- Cek udah sampe target
        if hrp.Position.Y >= State.autoFarmTargetY then
            State.autoFarmPhase = "jump"
            State.autoFarmPhaseStart = now
            log(string.format("[Auto] Reached top Y=%.1f, jumping!", hrp.Position.Y))
        end
    end
    
    -- ============ PHASE: JUMP ============
    elseif phase == "jump" then
        -- Jump untuk lepas dari truss
        if phaseTime < 0.1 then
            humanoid.Jump = true
            -- Force velocity ke atas dikit
            hrp.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
        end
        
        if phaseTime > 0.5 then
            State.autoFarmPhase = "fall"
            State.autoFarmPhaseStart = now
            log("[Auto] Falling...")
        end
    end
    
    -- ============ PHASE: FALL ============
    elseif phase == "fall" then
        -- Jangan force velocity apapun, biarin physics jalan
        -- Tunggu sampe jatuh ke ground
        
        local isOnGround = false
        local rayOrigin = hrp.Position
        local rayDir = Vector3.new(0, -10, 0)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {LocalPlayer.Character}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(rayOrigin, rayDir, params)
        
        if result and result.Distance <= 5 then
            isOnGround = true
        end
        
        if isOnGround or phaseTime > Config.AutoFarmFallDelay + 2 then
            State.autoFarmPhase = "collect"
            State.autoFarmPhaseStart = now
            log("[Auto] Landed, collecting reward...")
        end
    end
    
    -- ============ PHASE: COLLECT ============
    elseif phase == "collect" then
        -- Tunggu reward
        if phaseTime > Config.AutoFarmCollectDelay then
            Stats.autoFarmCycles = Stats.autoFarmCycles + 1
            log("[Auto] Cycle #" .. Stats.autoFarmCycles .. " complete!")
            
            -- Delay antar cycle
            State.autoFarmPhase = "idle"
            State.autoFarmPhaseStart = now
            State.autoFarmTarget = nil
            
            task.wait(Config.AutoFarmLoopDelay)
        end
    end
end

-- ============================================
-- ALL ON / ALL OFF
-- ============================================
local function allFeaturesOn()
    for _, toggle in ipairs(ToggleRegistry) do
        toggle.setter(true)
    end
    log(">>> ALL ON")
end

local function allFeaturesOff()
    for _, toggle in ipairs(ToggleRegistry) do
        toggle.setter(false)
    end
    if State.currentVelocity then
        State.currentVelocity:Destroy()
        State.currentVelocity = nil
        State.velocityActive = false
    end
    resetAutoFarm()
    log(">>> ALL OFF")
end

-- ============================================
-- UNLOAD
-- ============================================
local function unload()
    IsUnloaded = true
    print("[FastClimb] Unloading...")
    
    -- Disable semua
    for k in pairs(Config) do
        if type(Config[k]) == "boolean" then
            Config[k] = false
        end
    end
    
    -- Cleanup velocity
    if State.currentVelocity then
        pcall(function() State.currentVelocity:Destroy() end)
        State.currentVelocity = nil
    end
    
    -- Disconnect semua connection
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
    
    -- Destroy semua instance
    for _, inst in ipairs(Instances) do
        pcall(function() inst:Destroy() end)
    end
    Instances = {}
    
    -- Destroy ScreenGui
    if screen and screen.Parent then
        screen:Destroy()
    end
    
    print("[FastClimb] Unloaded successfully")
end

-- ============================================
-- TITLE BUTTONS
-- ============================================
local function makeTitleBtn(text, xPos, w, bg, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w, 0, 22)
    btn.Position = UDim2.new(1, xPos, 0.5, -11)
    btn.BackgroundColor3 = bg
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Parent = title
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    return btn
end

makeTitleBtn("COPY", -290, 55, Color3.fromRGB(45, 90, 160), function()
    if setclipboard then setclipboard(LogConsole.text)
    elseif syn and syn.write_clipboard then syn.write_clipboard(LogConsole.text) end
    titleLbl.Text = "Copied!"
    task.delay(1.2, function() titleLbl.Text = "Fast Climb UI v1.5" end)
end)

makeTitleBtn("CLEAR", -230, 55, Color3.fromRGB(160, 70, 40), function()
    clearLog()
    log("Log cleared")
end)

makeTitleBtn("UNLOAD", -170, 55, Color3.fromRGB(200, 50, 50), function()
    unload()
end)

makeTitleBtn("—", -110, 30, Color3.fromRGB(70, 70, 100), function()
    main.Visible = false; reopenBtn.Visible = true
end)

makeTitleBtn("X", -55, 30, Color3.fromRGB(170, 45, 45), function()
    main.Visible = false; reopenBtn.Visible = false
end)

reopenBtn.MouseButton1Click:Connect(function()
    main.Visible = true; reopenBtn.Visible = false
end)

-- Info bar
local infoBar = Instance.new("Frame")
infoBar.Size = UDim2.new(1, -10, 0, 26)
infoBar.Position = UDim2.new(0, 5, 0, 35)
infoBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
infoBar.BorderSizePixel = 0
infoBar.Parent = main
Instance.new("UICorner", infoBar).CornerRadius = UDim.new(0, 6)

local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 1, 0)
infoLbl.Position = UDim2.new(0, 10, 0, 0)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "Ready"
infoLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 11
infoLbl.Parent = infoBar

-- ============================================
-- AUTO FARM PANEL (TOP PRIORITY)
-- ============================================
local autoPanel = Instance.new("Frame")
autoPanel.Size = UDim2.new(1, -10, 0, 60)
autoPanel.Position = UDim2.new(0, 5, 0, 66)
autoPanel.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
autoPanel.BorderSizePixel = 0
autoPanel.Parent = main
Instance.new("UICorner", autoPanel).CornerRadius = UDim.new(0, 6)
local autoStroke = Instance.new("UIStroke", autoPanel)
autoStroke.Color = Color3.fromRGB(200, 100, 255)
autoStroke.Thickness = 1.5

local autoLabel = Instance.new("TextLabel")
autoLabel.Size = UDim2.new(0, 100, 1, 0)
autoLabel.Position = UDim2.new(0, 12, 0, 0)
autoLabel.BackgroundTransparency = 1
autoLabel.Text = "AUTO FARM"
autoLabel.TextColor3 = Color3.fromRGB(220, 140, 255)
autoLabel.TextXAlignment = Enum.TextXAlignment.Left
autoLabel.Font = Enum.Font.GothamBold
autoLabel.TextSize = 14
autoLabel.Parent = autoPanel

local autoStatusLbl = Instance.new("TextLabel")
autoStatusLbl.Size = UDim2.new(0, 260, 1, 0)
autoStatusLbl.Position = UDim2.new(0, 115, 0, 0)
autoStatusLbl.BackgroundTransparency = 1
autoStatusLbl.Text = "Phase: idle"
autoStatusLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
autoStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
autoStatusLbl.Font = Enum.Font.Code
autoStatusLbl.TextSize = 11
autoStatusLbl.Parent = autoPanel

local autoToggleBtn = Instance.new("TextButton")
autoToggleBtn.Size = UDim2.new(0, 140, 0, 30)
autoToggleBtn.Position = UDim2.new(1, -150, 0.5, -15)
autoToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
autoToggleBtn.BorderSizePixel = 0
autoToggleBtn.Text = "AUTO: OFF"
autoToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoToggleBtn.Font = Enum.Font.GothamBold
autoToggleBtn.TextSize = 12
autoToggleBtn.Parent = autoPanel
Instance.new("UICorner", autoToggleBtn).CornerRadius = UDim.new(0, 6)

local autoToggleKnob = Instance.new("Frame", autoToggleBtn)
autoToggleKnob.Size = UDim2.new(0, 22, 0, 22)
autoToggleKnob.Position = UDim2.new(0, 4, 0.5, -11)
autoToggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
autoToggleKnob.BorderSizePixel = 0
Instance.new("UICorner", autoToggleKnob).CornerRadius = UDim.new(1, 0)

autoToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoFarmEnabled = not Config.AutoFarmEnabled
    if Config.AutoFarmEnabled then
        autoToggleBtn.Text = "AUTO: ON"
        autoToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
        autoToggleKnob.Position = UDim2.new(1, -26, 0.5, -11)
        resetAutoFarm()
        log(">>> AUTO FARM ON")
    else
        autoToggleBtn.Text = "AUTO: OFF"
        autoToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        autoToggleKnob.Position = UDim2.new(0, 4, 0.5, -11)
        resetAutoFarm()
        log(">>> AUTO FARM OFF")
    end
end)

-- Auto stats mini
local autoStatsLbl = Instance.new("TextLabel")
autoStatsLbl.Size = UDim2.new(0, 200, 1, 0)
autoStatsLbl.Position = UDim2.new(0, 380, 0, 0)
autoStatsLbl.BackgroundTransparency = 1
autoStatsLbl.Text = ""
autoStatsLbl.TextColor3 = Color3.fromRGB(150, 200, 255)
autoStatsLbl.TextXAlignment = Enum.TextXAlignment.Right
autoStatsLbl.Font = Enum.Font.Code
autoStatsLbl.TextSize = 10
autoStatsLbl.Parent = autoPanel

-- ============================================
-- TOGGLE PANEL
-- ============================================
local togglePanel = Instance.new("ScrollingFrame")
togglePanel.Size = UDim2.new(0.55, -8, 1, -275)
togglePanel.Position = UDim2.new(0, 5, 0, 132)
togglePanel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
togglePanel.BorderSizePixel = 0
togglePanel.ScrollBarThickness = 4
togglePanel.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 180)
togglePanel.CanvasSize = UDim2.new(0, 0, 0, 0)
togglePanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
togglePanel.Parent = main
Instance.new("UICorner", togglePanel).CornerRadius = UDim.new(0, 6)

local toggleLayout = Instance.new("UIListLayout", togglePanel)
toggleLayout.Padding = UDim.new(0, 4)
toggleLayout.SortOrder = Enum.SortOrder.LayoutOrder

local togglePad = Instance.new("UIPadding", togglePanel)
togglePad.PaddingTop = UDim.new(0, 6)
togglePad.PaddingBottom = UDim.new(0, 6)
togglePad.PaddingLeft = UDim.new(0, 6)
togglePad.PaddingRight = UDim.new(0, 6)

local function makeSection(text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = "── " .. text .. " ──"
    lbl.TextColor3 = Color3.fromRGB(120, 140, 200)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.Parent = togglePanel
    return lbl
end

local function makeToggle(key, text, defaultValue, callback, isMainFeature)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(28, 28, 42)
    row.BorderSizePixel = 0
    row.Parent = togglePanel
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(220, 220, 240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 44, 0, 20)
    btn.Position = UDim2.new(1, -50, 0.5, -10)
    btn.BackgroundColor3 = defaultValue and Color3.fromRGB(50, 160, 60) or Color3.fromRGB(60, 60, 80)
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", btn)
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = defaultValue and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = defaultValue

    local function render()
        btn.BackgroundColor3 = state and Color3.fromRGB(50, 160, 60) or Color3.fromRGB(60, 60, 80)
        knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    end

    local setter = function(newState)
        state = newState
        Config[key] = newState
        render()
        if callback then callback(newState) end
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        render()
        Config[key] = state
        if callback then callback(state) end
    end)

    render()

    if isMainFeature then
        table.insert(ToggleRegistry, {
            key = key,
            name = text,
            setter = setter,
        })
    end

    return btn
end

local function makeEditableSlider(key, text, min, max, default, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(28, 28, 42)
    row.BorderSizePixel = 0
    row.Parent = togglePanel
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -130, 0, 18)
    lbl.Position = UDim2.new(0, 10, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(220, 220, 240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11
    lbl.Parent = row

    local minLbl = Instance.new("TextLabel")
    minLbl.Size = UDim2.new(0, 30, 0, 14)
    minLbl.Position = UDim2.new(0, 10, 0, 22)
    minLbl.BackgroundTransparency = 1
    minLbl.Text = tostring(min)
    minLbl.TextColor3 = Color3.fromRGB(100, 100, 130)
    minLbl.TextXAlignment = Enum.TextXAlignment.Left
    minLbl.Font = Enum.Font.Code
    minLbl.TextSize = 9
    minLbl.Parent = row

    local maxLbl = Instance.new("TextLabel")
    maxLbl.Size = UDim2.new(0, 30, 0, 14)
    maxLbl.Position = UDim2.new(0, 10 + 145, 0, 22)
    maxLbl.BackgroundTransparency = 1
    maxLbl.Text = tostring(max)
    maxLbl.TextColor3 = Color3.fromRGB(100, 100, 130)
    maxLbl.TextXAlignment = Enum.TextXAlignment.Right
    maxLbl.Font = Enum.Font.Code
    maxLbl.TextSize = 9
    maxLbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -180, 0, 4)
    track.Position = UDim2.new(0, 45, 0, 28)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local initPos = math.clamp((default - min) / (max - min), 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(initPos, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = UDim2.new(initPos, -6, 0.5, -6)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Text = ""
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local textBox = Instance.new("TextBox")
    textBox.Size = UDim2.new(0, 60, 0, 22)
    textBox.Position = UDim2.new(1, -68, 0, 12)
    textBox.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    textBox.BorderSizePixel = 0
    textBox.Text = tostring(default)
    textBox.TextColor3 = Color3.fromRGB(120, 200, 255)
    textBox.TextXAlignment = Enum.TextXAlignment.Center
    textBox.Font = Enum.Font.Code
    textBox.TextSize = 12
    textBox.ClearTextOnFocus = false
    textBox.Parent = row
    Instance.new("UICorner", textBox).CornerRadius = UDim.new(0, 4)
    local tbStroke = Instance.new("UIStroke", textBox)
    tbStroke.Color = Color3.fromRGB(80, 100, 150)
    tbStroke.Thickness = 1

    local sliderDragging = false
    local currentValue = default

    local function updateSlider(posX)
        local pos = math.clamp((posX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * pos)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        knob.Position = UDim2.new(pos, -6, 0.5, -6)
        textBox.Text = tostring(val)
        currentValue = val
        Config[key] = val
        if callback then callback(val) end
    end

    local function updateFromTextBox(inputVal)
        local num = tonumber(inputVal)
        if not num then
            textBox.Text = tostring(currentValue)
            return
        end
        num = math.floor(num)
        if num < min then num = min end
        if num > max then num = max end
        currentValue = num
        textBox.Text = tostring(num)
        Config[key] = num
        local pos = math.clamp((num - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        knob.Position = UDim2.new(pos, -6, 0.5, -6)
        if callback then callback(num) end
    end

    knob.MouseButton1Down:Connect(function() sliderDragging = true end)
    knob.MouseButton1Up:Connect(function() sliderDragging = false end)

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliderDragging = true
            updateSlider(input.Position.X)
        end
    end)

    trackConn(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            sliderDragging = false
        end
    end))

    trackConn(UserInputService.InputChanged:Connect(function(input)
        if sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input.Position.X)
        end
    end))

    textBox.FocusLost:Connect(function(enterPressed)
        updateFromTextBox(textBox.Text)
    end)

    textBox.FocusGained:Connect(function()
        task.defer(function()
            if textBox.TextBoxCursorPosition then
                textBox.CursorPosition = #textBox.Text + 1
                textBox.SelectionStart = 1
            end
        end)
    end)

    table.insert(SliderRegistry, {
        key = key,
        setter = function(val) updateFromTextBox(tostring(val)) end,
    })
end

-- ============================================
-- BUILD TOGGLES
-- ============================================
makeSection("Auto Farm Settings")
makeEditableSlider("AutoFarmSearchRadius", "Search Radius", 50, 2000, 500, function(v) end)
makeEditableSlider("AutoFarmClimbSpeed", "Climb Speed", 20, 1000, 120, function(v) end)
makeEditableSlider("AutoFarmClimbTimeout", "Climb Timeout (s)", 1, 60, 15, function(v) end)
makeEditableSlider("AutoFarmFallDelay", "Fall Delay (s)", 0.5, 10, 2, function(v) end)
makeEditableSlider("AutoFarmCollectDelay", "Collect Delay (s)", 0.5, 10, 1.5, function(v) end)
makeEditableSlider("AutoFarmLoopDelay", "Loop Delay (s)", 0, 10, 0.5, function(v) end)
makeEditableSlider("AutoFarmMaxCycles", "Max Cycles (0=∞)", 0, 1000, 0, function(v) end)

makeSection("Manual Movement")
makeToggle("WalkSpeedEnabled", "WalkSpeed Boost", false, function(v) 
    log("WalkSpeed: " .. tostring(v)) 
end, true)
makeEditableSlider("WalkSpeedValue", "WalkSpeed Value", 1, 1000, 80, function(v) end)

makeSection("Truss / Ladder")
makeToggle("TrussEnabled", "Truss Climb", false, function(v) 
    log("Truss: " .. tostring(v)) 
end, true)
makeEditableSlider("TrussSpeed", "Truss Speed", 1, 1000, 100, function(v) end)

makeSection("Velocity / Teleport")
makeToggle("VelocityEnabled", "Velocity Boost", false, function(v) 
    log("Velocity: " .. tostring(v))
    if not v then 
        if State.currentVelocity then
            State.currentVelocity:Destroy()
            State.currentVelocity = nil
            State.velocityActive = false
        end
    end
end, true)
makeEditableSlider("VelocitySpeed", "Velocity Speed", 1, 1000, 80, function(v) end)

makeToggle("TeleportEnabled", "Teleport Up", false, function(v) 
    log("Teleport: " .. tostring(v))
    State.teleportActive = v
end, true)
makeEditableSlider("TeleportStep", "Teleport Step", 1, 500, 3, function(v) end)

-- ============================================
-- CONSOLE PANEL
-- ============================================
local consolePanel = Instance.new("Frame")
consolePanel.Size = UDim2.new(0.45, -8, 1, -275)
consolePanel.Position = UDim2.new(0.55, 3, 0, 132)
consolePanel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
consolePanel.BorderSizePixel = 0
consolePanel.Parent = main
Instance.new("UICorner", consolePanel).CornerRadius = UDim.new(0, 6)

local consoleTitle = Instance.new("TextLabel")
consoleTitle.Size = UDim2.new(1, -10, 0, 18)
consoleTitle.Position = UDim2.new(0, 6, 0, 4)
consoleTitle.BackgroundTransparency = 1
consoleTitle.Text = "── LOG CONSOLE ──"
consoleTitle.TextColor3 = Color3.fromRGB(120, 140, 200)
consoleTitle.TextXAlignment = Enum.TextXAlignment.Left
consoleTitle.Font = Enum.Font.GothamBold
consoleTitle.TextSize = 10
consoleTitle.Parent = consolePanel

consoleScroll = Instance.new("ScrollingFrame")
consoleScroll.Size = UDim2.new(1, -8, 1, -28)
consoleScroll.Position = UDim2.new(0, 4, 0, 24)
consoleScroll.BackgroundTransparency = 1
consoleScroll.BorderSizePixel = 0
consoleScroll.ScrollBarThickness = 4
consoleScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 180)
consoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
consoleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
consoleScroll.Parent = consolePanel

consoleLbl = Instance.new("TextLabel")
consoleLbl.Size = UDim2.new(1, -8, 0, 0)
consoleLbl.Position = UDim2.new(0, 4, 0, 0)
consoleLbl.BackgroundTransparency = 1
consoleLbl.Text = ""
consoleLbl.TextColor3 = Color3.fromRGB(200, 210, 230)
consoleLbl.TextXAlignment = Enum.TextXAlignment.Left
consoleLbl.TextYAlignment = Enum.TextYAlignment.Top
consoleLbl.Font = Enum.Font.Code
consoleLbl.TextSize = 10
consoleLbl.TextWrapped = true
consoleLbl.AutomaticSize = Enum.AutomaticSize.Y
consoleLbl.Parent = consoleScroll

-- ============================================
-- ACTION ROW
-- ============================================
local actionRow = Instance.new("Frame")
actionRow.Size = UDim2.new(1, -10, 0, 32)
actionRow.Position = UDim2.new(0, 5, 1, -38)
actionRow.BackgroundTransparency = 1
actionRow.Parent = main

local function makeActionBtn(text, xPos, w, bg, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w, 0, 28)
    btn.Position = UDim2.new(0, xPos, 0, 0)
    btn.BackgroundColor3 = bg
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Parent = actionRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    return btn
end

makeActionBtn("ALL ON", 0, 80, Color3.fromRGB(50, 160, 60), function()
    allFeaturesOn()
end)

makeActionBtn("ALL OFF", 86, 80, Color3.fromRGB(170, 60, 60), function()
    allFeaturesOff()
end)

makeActionBtn("SCAN TANGGA", 172, 110, Color3.fromRGB(60, 130, 60), function()
    if _G.__FC_scanLadder then _G.__FC_scanLadder() end
end)

makeActionBtn("TEST TP +10", 288, 90, Color3.fromRGB(60, 100, 130), function()
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0)
        log("Test teleport +10")
    end
end)

makeActionBtn("RESET STATS", 384, 100, Color3.fromRGB(120, 80, 40), function()
    Stats.ticks = 0
    Stats.trussDetected = 0
    Stats.velocityApplied = 0
    Stats.teleportsDone = 0
    Stats.autoFarmCycles = 0
    log("Stats reset")
end)

makeActionBtn("UNLOAD", 490, 90, Color3.fromRGB(200, 50, 50), function()
    unload()
end)

-- ============================================
-- MAIN UI DRAG
-- ============================================
local uiDragging = false
local uiDragStart, uiStartPos

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        uiDragging = true
        uiDragStart = input.Position
        uiStartPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then 
                uiDragging = false 
            end
        end)
    end
end)

trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        uiDragging = false
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input)
    if uiDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - uiDragStart
        main.Position = UDim2.new(
            uiStartPos.X.Scale, uiStartPos.X.Offset + delta.X,
            uiStartPos.Y.Scale, uiStartPos.Y.Offset + delta.Y)
    end
end))

-- ============================================
-- SCAN TANGGA
-- ============================================
_G.__FC_scanLadder = function()
    local hrp = getHRP()
    if not hrp then log("No HRP"); return end

    log("=== Scan tangga ===")
    local parts = workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(30, 30, 30))

    local counts = {Truss = 0, Stairs = 0, Ramp = 0, Other = 0}
    local samples = {}

    for _, p in ipairs(parts) do
        if p:IsA("TrussPart") then
            counts.Truss = counts.Truss + 1
            if #samples < 5 then 
                table.insert(samples, string.format("Truss: %s | pos=(%.1f,%.1f,%.1f) | topY=%.1f", 
                    p.Name, p.Position.X, p.Position.Y, p.Position.Z,
                    p.Position.Y + p.Size.Y/2))
            end
        elseif p:IsA("WedgePart") then
            counts.Ramp = counts.Ramp + 1
        elseif p:IsA("Part") and p.Size.Y < 3 then
            counts.Stairs = counts.Stairs + 1
        else
            counts.Other = counts.Other + 1
        end
    end

    log(string.format("Truss: %d | Stairs: %d | Ramp: %d | Other: %d",
        counts.Truss, counts.Stairs, counts.Ramp, counts.Other))
    for _, s in ipairs(samples) do
        log("  " .. s)
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================
local lastTeleport = 0

trackConn(RunService.Heartbeat:Connect(function(dt)
    if IsUnloaded then return end
    Stats.ticks = Stats.ticks + 1
    local hrp = getHRP()
    local humanoid = getHumanoid()
    if not hrp or not humanoid then return end
    
    local now = tick()
    
    -- Auto Farm (priority)
    updateAutoFarm(now)
    
    -- Manual: WalkSpeed (skip kalau auto farm running)
    if not Config.AutoFarmEnabled then
        if Config.WalkSpeedEnabled then
            if math.abs(humanoid.WalkSpeed - Config.WalkSpeedValue) > 0.5 then
                humanoid.WalkSpeed = Config.WalkSpeedValue
            end
        end
    end

    -- Manual: Truss (skip kalau auto farm)
    if Config.TrussEnabled and not Config.AutoFarmEnabled then
        local parts = workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(6, 12, 6))
        local onTruss = false
        for _, p in ipairs(parts) do
            if p:IsA("TrussPart") then
                onTruss = true
                break
            end
        end
        State.onTruss = onTruss

        if onTruss then
            hrp.AssemblyLinearVelocity = Vector3.new(
                hrp.AssemblyLinearVelocity.X,
                Config.TrussSpeed,
                hrp.AssemblyLinearVelocity.Z
            )
            Stats.trussDetected = Stats.trussDetected + 1
        end
    end

    -- Manual: Velocity
    if Config.VelocityEnabled and not Config.AutoFarmEnabled then
        if not State.currentVelocity then
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(0, math.huge, 0)
            bv.Velocity = Vector3.new(0, Config.VelocitySpeed, 0)
            bv.Parent = hrp
            State.currentVelocity = bv
            State.velocityActive = true
        end
    else
        if State.currentVelocity then
            State.currentVelocity:Destroy()
            State.currentVelocity = nil
            State.velocityActive = false
        end
    end

    -- Manual: Teleport
    if Config.TeleportEnabled and not Config.AutoFarmEnabled then
        if now - lastTeleport >= Config.TeleportInterval then
            lastTeleport = now
            hrp.CFrame = hrp.CFrame + Vector3.new(0, Config.TeleportStep, 0)
            Stats.teleportsDone = Stats.teleportsDone + 1
        end
    end

    -- Info bar (tiap 0.5s)
    if Stats.ticks % 30 == 0 then
        local activeCount = 0
        for _, t in ipairs(ToggleRegistry) do
            if Config[t.key] then activeCount = activeCount + 1 end
        end
        local trussTxt = State.onTruss and "TRUSS" or "-"
        infoLbl.Text = string.format(
            "Active:%d/%d | WS:%d | %s | TP:%d | Vel:%s | Auto:%s",
            activeCount, #ToggleRegistry,
            math.floor(humanoid.WalkSpeed),
            trussTxt,
            Stats.teleportsDone,
            State.velocityActive and "ON" or "OFF",
            Config.AutoFarmEnabled and "ON" or "OFF"
        )
        
        -- Auto status
        autoStatusLbl.Text = string.format("Phase: %s | Y: %.1f", 
            State.autoFarmPhase:upper(), 
            hrp.Position.Y)
        
        autoStatsLbl.Text = string.format("Cycles: %d", Stats.autoFarmCycles)
    end
end))

-- ============================================
-- KEYBIND
-- ============================================
trackConn(UserInputService.InputBegan:Connect(function(input, gpe)
    if IsUnloaded then return end
    
    -- Priority keybinds
    if input.KeyCode == Enum.KeyCode.LeftControl then
        allFeaturesOn()
        return
    end
    
    if input.KeyCode == Enum.KeyCode.RightControl then
        allFeaturesOff()
        return
    end
    
    -- Auto Farm toggle: Right Alt
    if input.KeyCode == Enum.KeyCode.RightAlt then
        Config.AutoFarmEnabled = not Config.AutoFarmEnabled
        if Config.AutoFarmEnabled then
            autoToggleBtn.Text = "AUTO: ON"
            autoToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
            autoToggleKnob.Position = UDim2.new(1, -26, 0.5, -11)
            resetAutoFarm()
            log(">>> AUTO FARM ON (keybind)")
        else
            autoToggleBtn.Text = "AUTO: OFF"
            autoToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
            autoToggleKnob.Position = UDim2.new(0, 4, 0.5, -11)
            resetAutoFarm()
            log(">>> AUTO FARM OFF (keybind)")
        end
        return
    end
    
    if gpe then return end
    
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        reopenBtn.Visible = not main.Visible
    end
end))

-- ============================================
-- INIT
-- ============================================
log("═══════════════════════════════════")
log("Fast Climb UI v1.5 loaded")
log("═══════════════════════════════════")
log("")
log("NEW: AUTO FARM MODE")
log("  - Auto search truss")
log("  - Teleport ke base")
log("  - Auto climb sampe atas")
log("  - Auto jump & fall")
log("  - Loop otomatis")
log("")
log("Keybind:")
log("  RightShift  = Toggle UI")
log("  Left Ctrl   = ALL ON")
log("  Right Ctrl  = ALL OFF")
log("  Right Alt   = AUTO FARM Toggle")
log("")
log("Registered toggles: " .. #ToggleRegistry)
log("")
