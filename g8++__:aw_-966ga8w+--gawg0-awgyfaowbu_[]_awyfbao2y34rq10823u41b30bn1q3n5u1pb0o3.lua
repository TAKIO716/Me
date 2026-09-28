--[[
    ═══════════════════════════════════════════════════════════
    DEATH BALL AUTO — Full Script v1.1 (Fixed)
    ═══════════════════════════════════════════════════════════
    Fitur:
    - Auto Ready (jalan ke ReadyZone pas intermission)
    - Follow Ball (track via getnilinstances + delta velocity)
    - Auto Parry (time-to-impact)
    - UI Console (COPY / CLEAR / SCAN / MINIMIZE)
    - Unified Movement (no conflict)
    
    Keybind: RightShift = toggle UI visible
    ═══════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ============================================
-- CONFIG
-- ============================================
local Config = {
    AutoReady = true,
    FollowBall = false,
    Parry = false,
    WalkSpeed = 1.0,
    ParryDistance = 15,
    ParryTimeToImpact = 0.15,
}

-- ============================================
-- STATE
-- ============================================
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
    },
}

-- ============================================
-- LOG CONSOLE
-- ============================================
local LogConsole = {
    lines = {},
    maxLines = 400,
    logText = "",
    label = nil,
    scroll = nil,
}

function LogConsole:append(text)
    local ts = os.date("%H:%M:%S")
    table.insert(self.lines, "[" .. ts .. "] " .. tostring(text))
    while #self.lines > self.maxLines do
        table.remove(self.lines, 1)
    end
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
    if self.scroll then self.scroll.CanvasPosition = Vector2.new(0, 0) end
end

local function log(text)
    LogConsole:append(text)
    print("[DB] " .. tostring(text))
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

local existing = parentGui:FindFirstChild("DeathBallAutoUI")
if existing then existing:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "DeathBallAutoUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.DisplayOrder = 99999
screen.Parent = parentGui

-- Reopen Button (kecil, di kiri atas)
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
local reopenStroke = Instance.new("UIStroke", reopenBtn)
reopenStroke.Color = Color3.fromRGB(100, 150, 255)
reopenStroke.Thickness = 2

-- Main Frame
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

-- Title Bar
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
titleLbl.Text = "Death Ball Auto"
titleLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.Parent = title

-- Title bar buttons
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
        local ok, err = pcall(cb)
        if not ok then log("ERR: " .. tostring(err)) end
    end)
    return btn
end

makeTitleBtn("COPY", -230, 55, Color3.fromRGB(45, 90, 160), function()
    if setclipboard then setclipboard(LogConsole.logText)
    elseif syn and syn.write_clipboard then syn.write_clipboard(LogConsole.logText) end
    titleLbl.Text = "Copied!"
    task.delay(1.2, function() titleLbl.Text = "Death Ball Auto" end)
end)

makeTitleBtn("CLEAR", -170, 55, Color3.fromRGB(160, 70, 40), function()
    LogConsole:clear()
    log("Cleared")
end)

-- Minimize button
makeTitleBtn("—", -110, 30, Color3.fromRGB(70, 70, 100), function()
    main.Visible = false
    reopenBtn.Visible = true
    log("UI minimized")
end)

-- Close button
makeTitleBtn("X", -55, 30, Color3.fromRGB(170, 45, 45), function()
    main.Visible = false
    reopenBtn.Visible = false
    log("UI hidden")
end)

-- Reopen
reopenBtn.MouseButton1Click:Connect(function()
    main.Visible = true
    reopenBtn.Visible = false
    log("UI reopened")
end)

-- Stats Bar
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

-- Toggle Row
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
        btn.BackgroundColor3 = state 
            and Color3.fromRGB(50, 160, 60)
            or Color3.fromRGB(60, 60, 80)
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        render()
        callback(state)
    end)

    render()
    return btn
end

makeToggle("Auto Ready", 8, Config.AutoReady, function(v)
    Config.AutoReady = v
    log("AutoReady: " .. tostring(v))
end)

makeToggle("Follow Ball", 155, Config.FollowBall, function(v)
    Config.FollowBall = v
    log("FollowBall: " .. tostring(v))
end)

makeToggle("Parry", 302, Config.Parry, function(v)
    Config.Parry = v
    log("Parry: " .. tostring(v))
end)

-- Console Header
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

-- Scroll Frame
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

-- Action Row
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
    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(cb)
        if not ok then log("ERR: " .. tostring(err)) end
    end)
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
    log("Stats reset")
end)

makeActionBtn("UNLOAD", 324, 80, Color3.fromRGB(80, 80, 100), function()
    screen:Destroy()
    print("[DB] Unloaded")
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
-- UNIFIED MOVEMENT (single source of truth)
-- ============================================
local function walkTo(pos)
    State.walkTarget = pos
end

local function stopPath()
    State.walkTarget = nil
    State.autoMoveDir = Vector3.zero
end

-- Heartbeat: hitung direction dari walkTarget
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

-- Heartbeat: eksekusi move
RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:Move(State.autoMoveDir, false)
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

local function getRandomInZone(zone)
    local limitX = math.max(1, zone.Size.X * 0.5)
    local limitZ = math.max(1, zone.Size.Z * 0.5)
    local rx = (math.random() - 0.5) * limitX
    local rz = (math.random() - 0.5) * limitZ
    return (zone.CFrame * CFrame.new(rx, 0, rz)).Position
end

local lastARDebug = 0
local lastARState = false

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

                -- Log state change
                if isInt ~= lastARState then
                    lastARState = isInt
                    if isInt then
                        log("AR: INTERMISSION started")
                    else
                        log("AR: Intermission ended")
                    end
                end

                -- Debug tiap 3 detik
                if os.clock() - lastARDebug > 3 and isInt then
                    lastARDebug = os.clock()
                    if readyZone then
                        local inZone = isInsideZone(hrp.Position, readyZone)
                        log("AR: Zone=" .. (inZone and "INSIDE" or "OUTSIDE")
                            .. " | pos=(" .. string.format("%.1f,%.1f,%.1f",
                                hrp.Position.X, hrp.Position.Y, hrp.Position.Z) .. ")")
                    else
                        log("AR: ReadyZone NOT FOUND")
                    end
                end

                if isInt and readyZone then
                    if not isInsideZone(hrp.Position, readyZone) then
                        if not State.currentLobbyTarget 
                        or not isInsideZone(State.currentLobbyTarget, readyZone) then
                            State.currentLobbyTarget = getRandomInZone(readyZone)
                        end
                        walkTo(State.currentLobbyTarget)
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
            if n == "BallShadow" then isBall = false end
            if n == "FakeBall" then isBall = false end

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

    -- Rescan check
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

    -- Update posisi + velocity via delta
    if B.obj then
        local ok, pos = pcall(function() return B.obj.Position end)
        if ok and pos then
            if B.lastPos then
                local dt = now - B.lastUpdate
                if dt >= 0.03 then
                    local rawVel = (pos - B.lastPos) / dt
                    -- Smoothing
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
                local dist = (pos - hrp.Position).Magnitude
                return B.obj, dist
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
local lastFollowLog = 0

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
        elseif Config.FollowBall and not ball then
            -- Kalau FollowBall ON tapi bola gak ketemu, tetep coba scan
            -- (jangan stop path, biar gak konflik sama AutoReady)
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

        -- Stats update
        if now - lastStatsUpdate > 0.3 then
            lastStatsUpdate = now
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            local matchTxt = isIntermission() and "INTERMISSION" or "IN-GAME"
            local ballTxt = ball and string.format("%.1f", dist or 0) or "nil"
            local velTxt = ball and string.format("%.1f", State.ball.velocity.Magnitude) or "0"
            local targetTxt = isPlayerTargeted() and "TARGETED" or "safe"

            statsLbl.Text = string.format(
                "%s | Ball: %s (%s vel) | Parry: %d | %s",
                matchTxt, ballTxt, velTxt,
                State.stats.parryFired, targetTxt
            )
        end
    end
end)

-- ============================================
-- MANUAL SCAN
-- ============================================
_G.__DBA_scanBall = function()
    log("=== SCAN BALL ===")
    if not getnilinstances then
        log("ERROR: getnilinstances not supported")
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        log("ERROR: No HRP")
        return
    end

    local count = 0
    local ballCount = 0

    for _, obj in ipairs(getnilinstances()) do
        count = count + 1
        if obj:IsA("BasePart") then
            local n = obj.Name
            if n == "Ball" or (obj:IsA("MeshPart") and n:find("Ball") and n ~= "BallShadow") then
                ballCount = ballCount + 1
                local dist = (obj.Position - hrp.Position).Magnitude
                log(string.format("BALL: %s | dist=%.1f | pos=(%.1f,%.1f,%.1f)",
                    obj:GetFullName(), dist,
                    obj.Position.X, obj.Position.Y, obj.Position.Z))
            end
        end
    end

    log(string.format("Scanned: %d | Balls: %d", count, ballCount))
    log("=== END ===")
end

_G.__DBA_scanZone = function()
    log("=== SCAN ZONE ===")
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        log("ERROR: No HRP")
        return
    end

    local iframe = getIntermissionFrame()
    log("IntermissionFrame: " .. (iframe and tostring(iframe.Visible) or "NOT FOUND"))

    local readyZone = getReadyZone()
    if readyZone then
        log("ReadyZone pos: (" .. string.format("%.1f,%.1f,%.1f",
            readyZone.Position.X, readyZone.Position.Y, readyZone.Position.Z) .. ")")
        log("ReadyZone size: (" .. string.format("%.1f,%.1f,%.1f",
            readyZone.Size.X, readyZone.Size.Y, readyZone.Size.Z) .. ")")

        local rel = readyZone.CFrame:PointToObjectSpace(hrp.Position)
        log(string.format("Player rel: (%.2f, %.2f, %.2f)", rel.X, rel.Y, rel.Z))

        local inZone = isInsideZone(hrp.Position, readyZone)
        log("Inside zone: " .. tostring(inZone))

        local dist = (hrp.Position - readyZone.Position).Magnitude
        log(string.format("Distance to zone center: %.1f stud", dist))
    else
        log("ReadyZone NOT FOUND")
    end
    log("=== END ===")
end

-- ============================================
-- KEYBINDS
-- ============================================
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        if main.Visible then
            reopenBtn.Visible = false
        else
            reopenBtn.Visible = true
        end
    end
end)

-- ============================================
-- INIT
-- ============================================
log("═══════════════════════════════════════")
log("Death Ball Auto v1.1 loaded")
log("═══════════════════════════════════════")
log("Auto Ready: " .. tostring(Config.AutoReady))
log("Follow Ball: " .. tostring(Config.FollowBall))
log("Parry: " .. tostring(Config.Parry))
log("")
log("Keybind: RightShift = toggle UI")
log("MINIMIZE: klik tombol — di title bar")
log("")
