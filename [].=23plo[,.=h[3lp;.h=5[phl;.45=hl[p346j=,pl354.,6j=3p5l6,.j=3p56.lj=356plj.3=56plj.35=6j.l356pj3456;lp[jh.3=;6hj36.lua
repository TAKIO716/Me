--[[
    DEATH BALL AUTO — v2.0 (FIXED)
    - Hook ReplicatedStorage.Actions.Action (benar)
    - Parse (ballId, cframe) payload
    - Track velocity dari delta posisi
    - Highlight detect buat threat
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Config = {
    AutoReady = true,
    FollowBall = true,
    Parry = true,
    ForceWalkSpeed = 32,
    RotationLerp = 0.4,
    StopDistance = 2.5,
}

local State = {
    autoMoveDir = Vector3.zero,
    walkTarget = nil,
    lastParryTime = 0,
    balls = {},
    PARRY_COOLDOWN = 0,
    PARRY_TRIGGER_TIME = 0.2,
    stats = { parryFired = 0, wsReset = 0, remoteBallCount = 0, rotationApplied = 0 },
}

-- ============================================
-- LOG + UI (SAMA KAYAK SEBELUMNYA)
-- ============================================
local LogConsole = { lines = {}, maxLines = 400, logText = "", label = nil, scroll = nil }

function LogConsole:append(text)
    table.insert(self.lines, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(text))
    while #self.lines > self.maxLines do table.remove(self.lines, 1) end
    self.logText = table.concat(self.lines, "\n")
    if self.label then
        self.label.Text = self.logText
        task.defer(function()
            if self.scroll then
                self.scroll.CanvasPosition = Vector2.new(0, self.scroll.AbsoluteCanvasSize.Y)
            end
        end)
    end
end

function LogConsole:clear()
    self.lines = {}; self.logText = ""
    if self.label then self.label.Text = "" end
end

local function log(text)
    LogConsole:append(text)
    print("[DB] " .. tostring(text))
end

-- UI setup
local parentGui = gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")
local existing = parentGui:FindFirstChild("DeathBallAutoUI")
if existing then existing:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "DeathBallAutoUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 99999
screen.Parent = parentGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 620, 0, 480)
main.Position = UDim2.new(0.5, -310, 0, 20)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BorderSizePixel = 0
main.Active = true
main.Parent = screen
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
title.BorderSizePixel = 0
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -200, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Death Ball Auto v2.0 (FIXED)"
titleLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 22)
closeBtn.Position = UDim2.new(1, -32, 0.5, -11)
closeBtn.BackgroundColor3 = Color3.fromRGB(170, 45, 45)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.Parent = title
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

local statsBar = Instance.new("Frame")
statsBar.Size = UDim2.new(1, -10, 0, 26)
statsBar.Position = UDim2.new(0, 5, 0, 35)
statsBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
statsBar.BorderSizePixel = 0
statsBar.Parent = main
Instance.new("UICorner", statsBar).CornerRadius = UDim.new(0, 6)

local statsLbl = Instance.new("TextLabel")
statsLbl.Size = UDim2.new(1, -20, 1, 0)
statsLbl.Position = UDim2.new(0, 10, 0, 0)
statsLbl.BackgroundTransparency = 1
statsLbl.Text = "Loading..."
statsLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 11
statsLbl.Parent = statsBar

local logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -10, 1, -110)
logScroll.Position = UDim2.new(0, 5, 0, 68)
logScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.Parent = main
Instance.new("UICorner", logScroll).CornerRadius = UDim.new(0, 6)

local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, -12, 0, 0)
logLbl.Position = UDim2.new(0, 6, 0, 4)
logLbl.BackgroundTransparency = 1
logLbl.Text = ""
logLbl.TextColor3 = Color3.fromRGB(200, 210, 230)
logLbl.TextXAlignment = Enum.TextXAlignment.Left
logLbl.TextYAlignment = Enum.TextYAlignment.Top
logLbl.Font = Enum.Font.Code
logLbl.TextSize = 11
logLbl.TextWrapped = true
logLbl.AutomaticSize = Enum.AutomaticSize.Y
logLbl.Parent = logScroll

LogConsole.label = logLbl
LogConsole.scroll = logScroll

local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, -10, 0, 28)
btnRow.Position = UDim2.new(0, 5, 1, -34)
btnRow.BackgroundTransparency = 1
btnRow.Parent = main

local function makeBtn(text, x, w, bg, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 1, 0)
    b.Position = UDim2.new(0, x, 0, 0)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Parent = btnRow
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(function() pcall(cb) end)
    return b
end

makeBtn("SCAN BALL", 0, 100, Color3.fromRGB(60, 130, 60), function()
    log("=== BALL SCAN ===")
    local count = 0
    for id, e in pairs(State.balls) do
        count = count + 1
        if count > 10 then break end
        log(string.format("ID=%s pos=(%.1f,%.1f,%.1f) v=%.1f",
            tostring(id), e.position.X, e.position.Y, e.position.Z, e.velocity.Magnitude))
    end
    if count == 0 then log("No balls tracked") end
end)

makeBtn("RESET", 108, 100, Color3.fromRGB(120, 80, 40), function()
    State.stats = { parryFired = 0, wsReset = 0, remoteBallCount = 0, rotationApplied = 0 }
    log("Stats reset")
end)

makeBtn("COPY", 216, 100, Color3.fromRGB(45, 90, 160), function()
    if setclipboard then setclipboard(LogConsole.logText) end
    log("Copied")
end)

makeBtn("UNLOAD", 324, 80, Color3.fromRGB(80, 80, 100), function()
    screen:Destroy()
end)

-- Dragging
local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ============================================
-- FORCE WALKSPEED
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.1)
        if screen.Parent == nil then break end
        if Config.AutoReady or Config.FollowBall then
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if math.abs(humanoid.WalkSpeed - Config.ForceWalkSpeed) > 0.5 then
                    humanoid.WalkSpeed = Config.ForceWalkSpeed
                    State.stats.wsReset = State.stats.wsReset + 1
                end
            end
        end
    end
end)

-- ============================================
-- MOVEMENT
-- ============================================
local function walkTo(pos) State.walkTarget = pos end
local function stopPath()
    State.walkTarget = nil
    State.autoMoveDir = Vector3.zero
end

RunService.Stepped:Connect(function()
    if not State.walkTarget then
        State.autoMoveDir = Vector3.zero
        return
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        State.autoMoveDir = Vector3.zero
        return
    end
    local toTarget = State.walkTarget - hrp.Position
    local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flat.Magnitude < Config.StopDistance then
        State.autoMoveDir = Vector3.zero
        return
    end
    State.autoMoveDir = flat.Unit
end)

RunService.Stepped:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:Move(State.autoMoveDir, false)
        end
    end
end)

RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and humanoid and humanoid.Health > 0 then
            local vel = hrp.AssemblyLinearVelocity
            local dir = State.autoMoveDir.Unit
            if Vector3.new(vel.X, 0, vel.Z).Magnitude < Config.ForceWalkSpeed * 0.8 then
                hrp.AssemblyLinearVelocity = Vector3.new(dir.X * Config.ForceWalkSpeed, vel.Y, dir.Z * Config.ForceWalkSpeed)
            end
        end
    end
end)

-- Body rotation
RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and humanoid and humanoid.Health > 0 then
            humanoid.AutoRotate = true
            local dir = Vector3.new(State.autoMoveDir.X, 0, State.autoMoveDir.Z)
            if dir.Magnitude > 0.01 then
                dir = dir.Unit
                local currentCF = hrp.CFrame
                local targetCF = CFrame.lookAt(currentCF.Position, currentCF.Position + dir)
                hrp.CFrame = currentCF:Lerp(targetCF, Config.RotationLerp)
                State.stats.rotationApplied = State.stats.rotationApplied + 1
            end
        end
    end
end)

-- ============================================
-- BALL TRACKER (FIXED)
-- ============================================
local ActionsFolder = ReplicatedStorage:WaitForChild("Actions")
local BallAction = ActionsFolder:WaitForChild("Action")

local ballTracker = {}

BallAction.OnClientEvent:Connect(function(arg1, arg2)
    if type(arg1) == "string" and typeof(arg2) == "CFrame" then
        local ballId = arg1
        local cframe = arg2
        local now = os.clock()
        local newPos = cframe.Position
        
        local existing = ballTracker[ballId]
        local velocity = Vector3.zero
        if existing then
            local dt = now - existing.lastUpdate
            if dt > 0.01 then
                velocity = (newPos - existing.position) / dt
            end
        end
        
        ballTracker[ballId] = {
            position = newPos,
            cframe = cframe,
            velocity = velocity,
            lastUpdate = now,
        }
        
        State.balls = ballTracker
        State.stats.remoteBallCount = State.stats.remoteBallCount + 1
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if screen.Parent == nil then break end
        local now = os.clock()
        for id, entry in pairs(ballTracker) do
            if now - entry.lastUpdate > 1.5 then
                ballTracker[id] = nil
            end
        end
    end
end)

-- ============================================
-- THREAT DETECT
-- ============================================
local function isPlayerThreatened()
    local char = LocalPlayer.Character
    if not char then return false end
    
    local highlight = char:FindFirstChildWhichIsA("Highlight")
    if highlight and highlight.Enabled then return true end
    
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name == "Part" and obj:IsA("MeshPart") then
            local h = obj:FindFirstChildWhichIsA("Highlight")
            if h and h.Enabled then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp and (obj.Position - hrp.Position).Magnitude < 15 then
                    return true
                end
            end
        end
    end
    
    return false
end

-- ============================================
-- PARRY
-- ============================================
local function parry()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.wait(0.02)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    State.stats.parryFired = State.stats.parryFired + 1
end

local function calculateTimeToImpact(ballPos, ballVel, playerPos, playerVel)
    local relPos = playerPos - ballPos
    local relVel = ballVel - playerVel
    local relSpeedSq = relVel:Dot(relVel)
    if relSpeedSq <= 1e-4 then return math.huge end
    local timeToCPA = relPos:Dot(relVel) / relSpeedSq
    if timeToCPA <= 0 then return math.huge end
    local closestPos = relPos - (relVel * timeToCPA)
    if closestPos.Magnitude <= 12 then return timeToCPA end
    return math.huge
end

RunService.Heartbeat:Connect(function()
    if not Config.Parry then return end
    local now = os.clock()
    if not isPlayerThreatened() then return end
    if now - State.lastParryTime < State.PARRY_COOLDOWN then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local playerPos = hrp.Position
    local playerVel = hrp.AssemblyLinearVelocity
    
    for _, entry in pairs(ballTracker) do
        if entry.velocity.Magnitude > 0.01 then
            local t = calculateTimeToImpact(entry.position, entry.velocity, playerPos, playerVel)
            if t > 0 and t <= State.PARRY_TRIGGER_TIME then
                parry()
                State.lastParryTime = now
                break
            end
        end
    end
end)

-- ============================================
-- AUTO READY
-- ============================================
local function getIntermissionFrame()
    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local hud = pGui and pGui:FindFirstChild("HUD")
    local holder = hud and hud:FindFirstChild("HolderBottom")
    return holder and holder:FindFirstChild("IntermissionFrame")
end

local function isIntermission()
    local iframe = getIntermissionFrame()
    return iframe and iframe.Visible == true
end

local function getReadyZone()
    local lobby = Workspace:FindFirstChild("New Lobby before Halloween") or Workspace:FindFirstChild("New Lobby")
    local readyArea = lobby and lobby:FindFirstChild("ReadyArea")
    return readyArea and readyArea:FindFirstChild("ReadyZone")
end

local function isInsideZone(pos, zone)
    local rel = zone.CFrame:PointToObjectSpace(pos)
    return math.abs(rel.X) <= (zone.Size.X/2 - 1.5) and math.abs(rel.Z) <= (zone.Size.Z/2 - 1.5)
end

task.spawn(function()
    while true do
        task.wait(0.2)
        if screen.Parent == nil then break end
        if Config.AutoReady then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and isIntermission() then
                local readyZone = getReadyZone()
                if readyZone and not isInsideZone(hrp.Position, readyZone) then
                    walkTo(readyZone.Position)
                else
                    stopPath()
                end
            end
        end
    end
end)

-- ============================================
-- FOLLOW BALL
-- ============================================
local function isHealthBarVisible()
    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local hud = pGui and pGui:FindFirstChild("HUD")
    if not hud then return false end
    local hb = hud:FindFirstChild("HealthBar")
    if not hb then
        local holder = hud:FindFirstChild("HolderBottom")
        hb = holder and holder:FindFirstChild("HealthBar")
    end
    return hb and hb.Visible == true
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if screen.Parent == nil then break end
        if Config.FollowBall and isHealthBarVisible() then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bestBall, bestDist = nil, math.huge
                for _, entry in pairs(ballTracker) do
                    local dist = (entry.position - hrp.Position).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestBall = entry
                    end
                end
                if bestBall and bestDist > 3 then
                    walkTo(bestBall.position)
                else
                    stopPath()
                end
            end
        end
    end
end)

-- ============================================
-- STATS LOOP
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.3)
        if screen.Parent == nil then break end
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local ballCount = 0
        for _ in pairs(ballTracker) do ballCount = ballCount + 1 end
        statsLbl.Text = string.format("Ball:%d | WS:%s | Parry:%d | Rot:%d | %s",
            ballCount, humanoid and string.format("%.0f", humanoid.WalkSpeed) or "?",
            State.stats.parryFired, State.stats.rotationApplied,
            isPlayerThreatened() and "TARGETED" or "safe")
    end
end)

-- RightShift toggle
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    screen:Destroy()
end)

log("═══════════════════════════════════════")
log("Death Ball Auto v2.0 FIXED")
log("═══════════════════════════════════════")
log("✅ Hook: ReplicatedStorage.Actions.Action")
log("✅ Payload: (ballId, cframe)")
log("✅ Velocity: derived from delta")
log("✅ Threat: Highlight detect")
log("")
if BallAction then
    log("✅ BallAction found: "..BallAction:GetFullName())
else
    log("❌ BallAction NOT found")
end
