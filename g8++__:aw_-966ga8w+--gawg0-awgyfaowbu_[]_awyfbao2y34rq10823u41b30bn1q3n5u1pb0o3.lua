--[[
    ═══════════════════════════════════════════════════════════
    DEATH BALL AUTO — Full Script v1.2 (Force Control)
    ═══════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- CONFIG
local Config = {
    AutoReady = true,
    FollowBall = true,
    Parry = true,
    WalkSpeed = 1.0,
    ParryDistance = 15,
    ParryTimeToImpact = 0.15,
    ForceWalkSpeed = 24,
    ForceMoveThreshold = 2,
}

-- STATE
local State = {
    autoMoveDir = Vector3.zero,
    walkTarget = nil,
    currentLobbyTarget = nil,
    lastParry = 0,
    ball = {
        obj = nil,
        position = nil,
        velocity = Vector3.zero,
        lastPos = nil,
        lastUpdate = 0,
        name = nil,
        lastScan = 0,
        scanInterval = 0.05,
        notFoundCount = 0,
    },
    stats = {
        ballFound = 0,
        parryFired = 0,
        forceApplied = 0,
    },
}

-- LOG
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
    self.lines = {}
    self.logText = ""
    if self.label then self.label.Text = "" end
end

local function log(text)
    LogConsole:append(text)
    print("[DB] " .. tostring(text))
end

-- UI
local parentGui
if gethui then
    local ok, r = pcall(gethui)
    if ok and r then parentGui = r end
end
if not parentGui then parentGui = LocalPlayer:WaitForChild("PlayerGui") end

local existing = parentGui:FindFirstChild("DeathBallAutoUI")
if existing then existing:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "DeathBallAutoUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 99999
screen.Parent = parentGui

local reopenBtn = Instance.new("TextButton")
reopenBtn.Size = UDim2.new(0, 50, 0, 50)
reopenBtn.Position = UDim2.new(0, 15, 0.3, 0)
reopenBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
reopenBtn.Text = "DB"
reopenBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
reopenBtn.Font = Enum.Font.GothamBold
reopenBtn.TextSize = 18
reopenBtn.Visible = false
reopenBtn.Parent = screen
Instance.new("UICorner", reopenBtn).CornerRadius = UDim.new(0, 8)

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 620, 0, 480)
main.Position = UDim2.new(0.5, -310, 0, 20)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
main.Active = true
main.Parent = screen
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(100, 120, 200)
stroke.Thickness = 1.5

local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
title.BorderSizePixel = 0
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -300, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Death Ball Auto v1.2"
titleLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.Parent = title

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
    btn.MouseButton1Click:Connect(function()
        pcall(cb)
    end)
    return btn
end

makeTitleBtn("COPY", -230, 55, Color3.fromRGB(45, 90, 160), function()
    if setclipboard then setclipboard(LogConsole.logText)
    elseif syn and syn.write_clipboard then syn.write_clipboard(LogConsole.logText) end
    titleLbl.Text = "Copied!"
    task.delay(1.2, function() titleLbl.Text = "Death Ball Auto v1.2" end)
end)

makeTitleBtn("CLEAR", -170, 55, Color3.fromRGB(160, 70, 40), function()
    LogConsole:clear()
    log("Cleared")
end)

makeTitleBtn("—", -110, 30, Color3.fromRGB(70, 70, 100), function()
    main.Visible = false
    reopenBtn.Visible = true
end)

makeTitleBtn("X", -55, 30, Color3.fromRGB(170, 45, 45), function()
    main.Visible = false
    reopenBtn.Visible = false
end)

reopenBtn.MouseButton1Click:Connect(function()
    main.Visible = true
    reopenBtn.Visible = false
end)

-- Stats bar
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

-- Toggle row
local toggleRow = Instance.new("Frame")
toggleRow.Size = UDim2.new(1, -10, 0, 32)
toggleRow.Position = UDim2.new(0, 5, 0, 66)
toggleRow.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
toggleRow.BorderSizePixel = 0
toggleRow.Parent = main
Instance.new("UICorner", toggleRow).CornerRadius = UDim.new(0, 6)

local function makeToggle(text, xPos, initState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 140, 0, 24)
    btn.Position = UDim2.new(0, xPos, 0.5, -12)
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = toggleRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local state = initState
    local baseText = text

    local function render()
        btn.Text = baseText .. ": " .. (state and "ON" or "OFF")
        btn.BackgroundColor3 = state and Color3.fromRGB(50, 160, 60) or Color3.fromRGB(60, 60, 80)
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        render()
        callback(state)
    end)

    render()
    return btn
end

makeToggle("Auto Ready", 8, Config.AutoReady, function(v) Config.AutoReady = v; log("AutoReady: " .. tostring(v)) end)
makeToggle("Follow Ball", 155, Config.FollowBall, function(v) Config.FollowBall = v; log("FollowBall: " .. tostring(v)) end)
makeToggle("Parry", 302, Config.Parry, function(v) Config.Parry = v; log("Parry: " .. tostring(v)) end)

-- Console header
local consoleHeader = Instance.new("Frame")
consoleHeader.Size = UDim2.new(1, -10, 0, 20)
consoleHeader.Position = UDim2.new(0, 5, 0, 104)
consoleHeader.BackgroundTransparency = 1
consoleHeader.Parent = main

local consoleTitle = Instance.new("TextLabel")
consoleTitle.Size = UDim2.new(1, -20, 1, 0)
consoleTitle.Position = UDim2.new(0, 8, 0, 0)
consoleTitle.BackgroundTransparency = 1
consoleTitle.Text = "── LOG CONSOLE ──"
consoleTitle.TextColor3 = Color3.fromRGB(120, 140, 200)
consoleTitle.TextXAlignment = Enum.TextXAlignment.Left
consoleTitle.Font = Enum.Font.GothamBold
consoleTitle.TextSize = 10
consoleTitle.Parent = consoleHeader

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -10, 1, -160)
scroll.Position = UDim2.new(0, 5, 0, 128)
scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 180)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

local padding = Instance.new("UIPadding", scroll)
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 4)

local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, -8, 0, 0)
logLbl.Position = UDim2.new(0, 4, 0, 0)
logLbl.BackgroundTransparency = 1
logLbl.Text = ""
logLbl.TextColor3 = Color3.fromRGB(200, 210, 230)
logLbl.TextXAlignment = Enum.TextXAlignment.Left
logLbl.TextYAlignment = Enum.TextYAlignment.Top
logLbl.Font = Enum.Font.Code
logLbl.TextSize = 11
logLbl.TextWrapped = true
logLbl.AutomaticSize = Enum.AutomaticSize.Y
logLbl.Parent = scroll

LogConsole.label = logLbl
LogConsole.scroll = scroll

-- Action row
local actionRow = Instance.new("Frame")
actionRow.Size = UDim2.new(1, -10, 0, 30)
actionRow.Position = UDim2.new(0, 5, 1, -35)
actionRow.BackgroundTransparency = 1
actionRow.Parent = main

local function makeActionBtn(text, xPos, w, bg, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w, 0, 26)
    btn.Position = UDim2.new(0, xPos, 0, 0)
    btn.BackgroundColor3 = bg
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = actionRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    return btn
end

makeActionBtn("SCAN BALL", 0, 100, Color3.fromRGB(60, 130, 60), function()
    if _G.__DBA_scanBall then _G.__DBA_scanBall() end
end)

makeActionBtn("SCAN ZONE", 108, 100, Color3.fromRGB(60, 100, 130), function()
    if _G.__DBA_scanZone then _G.__DBA_scanZone() end
end)

makeActionBtn("RESET STATS", 216, 100, Color3.fromRGB(120, 80, 40), function()
    State.stats.ballFound = 0
    State.stats.parryFired = 0
    State.stats.forceApplied = 0
    log("Stats reset")
end)

makeActionBtn("UNLOAD", 324, 80, Color3.fromRGB(80, 80, 100), function()
    screen:Destroy()
end)

-- Drag
local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- ============================================
-- FORCE CONTROL RESTORE
-- ============================================
task.spawn(function()
    while true do
        task.wait(0.3)
        if screen.Parent == nil then break end
        
        if Config.AutoReady or Config.FollowBall then
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                -- Restore WalkSpeed kalau di-lock
                if humanoid.WalkSpeed < 8 then
                    humanoid.WalkSpeed = Config.ForceWalkSpeed
                    State.stats.forceApplied = State.stats.forceApplied + 1
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

RunService.Heartbeat:Connect(function()
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
    if flat.Magnitude < 1.5 then
        State.autoMoveDir = Vector3.zero
        return
    end
    State.autoMoveDir = flat.Unit * Config.WalkSpeed
end)

-- Approach 1: humanoid:Move
RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:Move(State.autoMoveDir, false)
        end
    end
end)

-- Approach 2: Force velocity (backup kalau Move gak works)
RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and humanoid and humanoid.Health > 0 then
            local horizontalVel = Vector3.new(
                hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z
            )
            if horizontalVel.Magnitude < Config.ForceMoveThreshold then
                local dir = State.autoMoveDir.Unit
                hrp.AssemblyLinearVelocity = Vector3.new(
                    dir.X * 20, hrp.AssemblyLinearVelocity.Y, dir.Z * 20
                )
                State.stats.forceApplied = State.stats.forceApplied + 1
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
    local lobby = Workspace:FindFirstChild("New Lobby")
    local readyArea = lobby and lobby:FindFirstChild("ReadyArea")
    return readyArea and readyArea:FindFirstChild("ReadyZone")
end

local function isInsideZone(pos, zone)
    local rel = zone.CFrame:PointToObjectSpace(pos)
    local halfX = (zone.Size.X / 2) - 1.5
    local halfZ = (zone.Size.Z / 2) - 1.5
    return math.abs(rel.X) <= halfX and math.abs(rel.Z) <= halfZ
end

local lastARState = false
local lastARDebug = 0

task.spawn(function()
    while true do
        task.wait(0.2)
        if screen.Parent == nil then break end

        if Config.AutoReady then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local isInt = isIntermission()
                local readyZone = getReadyZone()

                if isInt ~= lastARState then
                    lastARState = isInt
                    log(isInt and "AR: INTERMISSION started" or "AR: Intermission ended")
                end

                if os.clock() - lastARDebug > 5 and isInt then
                    lastARDebug = os.clock()
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    log(string.format("AR: pos=(%.1f,%.1f,%.1f) WS=%.0f",
                        hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
                        humanoid and humanoid.WalkSpeed or 0))
                end

                if isInt and readyZone then
                    if not isInsideZone(hrp.Position, readyZone) then
                        -- Target ke CENTER zone
                        walkTo(readyZone.Position)
                    else
                        State.currentLobbyTarget = nil
                        stopPath()
                    end
                end
            end
        end
    end
end)

-- ============================================
-- BALL TRACKER
-- ============================================
local function findRealBall()
    if not getnilinstances then return nil end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local bestBall = nil
    local bestDist = math.huge

    for _, obj in ipairs(getnilinstances()) do
        if obj:IsA("BasePart") then
            local n = obj.Name
            local isBall = false
            if n == "Ball" then isBall = true end
            if obj:IsA("MeshPart") and n:find("Ball") then isBall = true end
            if n == "BallShadow" or n == "FakeBall" then isBall = false end
            local path = obj:GetFullName():lower()
            if path:find("/fx/") then isBall = false end

            if isBall then
                local dist = (obj.Position - hrp.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestBall = obj
                end
            end
        end
    end
    return bestBall, bestDist
end

local function updateBall()
    local now = os.clock()
    local B = State.ball

    if now - B.lastScan >= B.scanInterval or not B.obj then
        B.lastScan = now
        local ball, dist = findRealBall()
        if ball then
            if B.obj ~= ball then
                State.stats.ballFound = State.stats.ballFound + 1
                log("Ball found: " .. ball:GetFullName())
                B.lastPos = ball.Position
                B.lastUpdate = now
            end
            B.obj = ball
            B.name = ball.Name
            B.notFoundCount = 0
        else
            B.obj = nil
            B.notFoundCount = B.notFoundCount + 1
        end
    end

    if B.obj then
        local ok, pos = pcall(function() return B.obj.Position end)
        if ok and pos then
            if B.lastPos then
                local dt = now - B.lastUpdate
                if dt >= 0.03 then
                    local rawVel = (pos - B.lastPos) / dt
                    B.velocity = B.velocity:Lerp(rawVel, 0.4)
                    B.lastPos = pos
                    B.lastUpdate = now
                end
            else
                B.lastPos = pos
                B.lastUpdate = now
            end
            B.position = pos
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                return B.obj, (pos - hrp.Position).Magnitude
            end
        end
    end
    return nil
end

-- ============================================
-- PARRY
-- ============================================
local function parry()
    if os.clock() - State.lastParry < 0.05 then return end
    State.lastParry = os.clock()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    State.stats.parryFired = State.stats.parryFired + 1
end

local function isPlayerTargeted()
    local char = LocalPlayer.Character
    if not char then return false end
    local hl = char:FindFirstChildWhichIsA("Highlight")
    if hl and hl.Enabled then
        return hl.FillTransparency < 0.9 or hl.OutlineTransparency < 0.9
    end
    return false
end

-- ============================================
-- MAIN LOOP
-- ============================================
local lastStatsUpdate = 0

task.spawn(function()
    while true do
        task.wait(0.05)
        if screen.Parent == nil then break end

        local ball, dist = updateBall()
        local now = os.clock()

        -- FOLLOW BALL
        if Config.FollowBall and ball then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local toBall = ball.Position - hrp.Position
                local flat = Vector3.new(toBall.X, 0, toBall.Z)
                if flat.Magnitude > 3 then
                    walkTo(ball.Position)
                else
                    stopPath()
                end
            end
        end

        -- PARRY
        if Config.Parry and ball and isPlayerTargeted() then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local ballVel = State.ball.velocity
                local ballSpeed = ballVel.Magnitude
                if ballSpeed > 5 then
                    local playerVel = hrp.AssemblyLinearVelocity
                    local relPos = hrp.Position - ball.Position
                    local relVel = ballVel - playerVel
                    local relSpeedSq = relVel:Dot(relVel)
                    if relSpeedSq > 1e-4 then
                        local timeToCPA = relPos:Dot(relVel) / relSpeedSq
                        if timeToCPA > 0 and timeToCPA <= Config.ParryTimeToImpact then
                            local closestPos = relPos - (relVel * timeToCPA)
                            if closestPos.Magnitude <= Config.ParryDistance then
                                parry()
                            end
                        end
                    end
                end
            end
        end

        -- STATS
        if now - lastStatsUpdate > 0.3 then
            lastStatsUpdate = now
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local matchTxt = isIntermission() and "INTER" or "INGAME"
            local ballTxt = ball and string.format("%.0f", dist or 0) or "-"
            local wsTxt = humanoid and string.format("%.0f", humanoid.WalkSpeed) or "?"
            local velTxt = ball and string.format("%.0f", State.ball.velocity.Magnitude) or "0"
            statsLbl.Text = string.format(
                "%s | Ball:%s | WS:%s | V:%s | Parry:%d | Force:%d",
                matchTxt, ballTxt, wsTxt, velTxt,
                State.stats.parryFired, State.stats.forceApplied
            )
        end
    end
end)

-- ============================================
-- MANUAL SCAN
-- ============================================
_G.__DBA_scanBall = function()
    log("=== SCAN BALL ===")
    if not getnilinstances then log("getnilinstances not supported"); return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then log("No HRP"); return end
    local count, ballCount = 0, 0
    for _, obj in ipairs(getnilinstances()) do
        count = count + 1
        if obj:IsA("BasePart") then
            local n = obj.Name
            if n == "Ball" or (obj:IsA("MeshPart") and n:find("Ball") and n ~= "BallShadow") then
                ballCount = ballCount + 1
                local dist = (obj.Position - hrp.Position).Magnitude
                log(string.format("BALL: %s | dist=%.1f", obj:GetFullName(), dist))
            end
        end
    end
    log(string.format("Scanned: %d | Balls: %d", count, ballCount))
end

_G.__DBA_scanZone = function()
    log("=== SCAN ZONE ===")
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then log("No HRP"); return end

    log("Intermission: " .. tostring(isIntermission()))
    log("WalkSpeed: " .. tostring(humanoid and humanoid.WalkSpeed or "?"))

    local readyZone = getReadyZone()
    if readyZone then
        log("Zone pos: (" .. string.format("%.1f,%.1f,%.1f",
            readyZone.Position.X, readyZone.Position.Y, readyZone.Position.Z) .. ")")
        local rel = readyZone.CFrame:PointToObjectSpace(hrp.Position)
        log(string.format("Player rel: (%.2f, %.2f, %.2f)", rel.X, rel.Y, rel.Z))
        log("Inside: " .. tostring(isInsideZone(hrp.Position, readyZone)))
        log(string.format("Dist: %.1f stud", (hrp.Position - readyZone.Position).Magnitude))
    end
end

-- ============================================
-- KEYBIND
-- ============================================
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        reopenBtn.Visible = not main.Visible
    end
end)

-- INIT
log("═══════════════════════════════════════")
log("Death Ball Auto v1.2 (Force Control)")
log("═══════════════════════════════════════")
log("AutoReady: " .. tostring(Config.AutoReady))
log("FollowBall: " .. tostring(Config.FollowBall))
log("Parry: " .. tostring(Config.Parry))
log("")
log("Fix: Force WalkSpeed + Force Velocity")
log("Keybind: RightShift = toggle UI")
