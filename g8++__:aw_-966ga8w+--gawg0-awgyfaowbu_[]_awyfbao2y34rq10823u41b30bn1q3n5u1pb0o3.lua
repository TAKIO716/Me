--[[
    ═══════════════════════════════════════════════════════════
    DEATH BALL AUTO — v1.5 (Body Rotation Fix)
    ═══════════════════════════════════════════════════════════
    NEW: Karakter muter ngikutin arah gerakan (bukan strafe)
    ═══════════════════════════════════════════════════════════
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
    FollowBall = false,
    Parry = true,
    ForceWalkSpeed = 30,
    RotationLerp = 0.4,
    StopDistance = 2.5,
}

local State = {
    autoMoveDir = Vector3.zero,
    walkTarget = nil,
    lastParryTime = 0,
    balls = {},
    PARRY_COOLDOWN = 0,
    PARRY_TRIGGER_TIME = 0.15,
    stats = { parryFired = 0, wsReset = 0, remoteBallCount = 0, rotationApplied = 0 },
}

-- ============================================
-- LOG
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

-- ============================================
-- UI
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
titleLbl.Text = "Death Ball Auto v1.5"
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
    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    return btn
end

makeTitleBtn("COPY", -230, 55, Color3.fromRGB(45, 90, 160), function()
    if setclipboard then setclipboard(LogConsole.logText)
    elseif syn and syn.write_clipboard then syn.write_clipboard(LogConsole.logText) end
    titleLbl.Text = "Copied!"
    task.delay(1.2, function() titleLbl.Text = "Death Ball Auto v1.5" end)
end)

makeTitleBtn("CLEAR", -170, 55, Color3.fromRGB(160, 70, 40), function()
    LogConsole:clear(); log("Cleared")
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
        state = not state; render(); callback(state)
    end)
    render()
    return btn
end

makeToggle("Auto Ready", 8, Config.AutoReady, function(v) Config.AutoReady = v; log("AutoReady: " .. tostring(v)) end)
makeToggle("Follow Ball", 155, Config.FollowBall, function(v) Config.FollowBall = v; log("FollowBall: " .. tostring(v)) end)
makeToggle("Parry", 302, Config.Parry, function(v) Config.Parry = v; log("Parry: " .. tostring(v)) end)

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
    log("=== SCAN BALL ===")
    local count = 0
    for id, entry in pairs(State.balls) do
        count = count + 1
        if count > 10 then break end
        log(string.format("ID=%s | pos=(%.1f,%.1f,%.1f)",
            tostring(id), entry.position.X, entry.position.Y, entry.position.Z))
    end
    if count == 0 then log("No remote balls tracked") end
end)

makeActionBtn("SCAN ZONE", 108, 100, Color3.fromRGB(60, 100, 130), function()
    if _G.__DBA_scanZone then _G.__DBA_scanZone() end
end)

makeActionBtn("RESET", 216, 100, Color3.fromRGB(120, 80, 40), function()
    State.stats.parryFired = 0
    State.stats.wsReset = 0
    State.stats.remoteBallCount = 0
    State.stats.rotationApplied = 0
    log("Stats reset")
end)

makeActionBtn("UNLOAD", 324, 80, Color3.fromRGB(80, 80, 100), function()
    screen:Destroy()
end)

local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
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
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            local dir = State.autoMoveDir.Unit
            if flatVel.Magnitude < Config.ForceWalkSpeed * 0.8 then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    dir.X * Config.ForceWalkSpeed, vel.Y, dir.Z * Config.ForceWalkSpeed
                )
            end
        end
    end
end)

-- ============================================
-- BODY ROTATION (FIX!)
-- ============================================
RunService.Heartbeat:Connect(function()
    if State.autoMoveDir.Magnitude > 0.1 then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and humanoid and humanoid.Health > 0 then
            -- Force AutoRotate ON
            humanoid.AutoRotate = true

            -- Rotate toward movement
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
                    log(string.format("AR: pos=(%.1f,%.1f,%.1f)",
                        hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
                end

                if isInt and readyZone then
                    if not isInsideZone(hrp.Position, readyZone) then
                        walkTo(readyZone.Position)
                    else
                        stopPath()
                    end
                end
            end
        end
    end
end)

-- ============================================
-- BIT DECODE
-- ============================================
local bit32_extract = bit32.extract
local bit32_lshift = bit32.lshift
local bit32_rshift = bit32.rshift
local bit32_bor = bit32.bor
local string_unpack = string.unpack
local string_pack = string.pack
local table_create = table.create
local setmetatable = setmetatable

local UINT32_SCALE = 4294967296
local POW2 = table_create(54)
for i = 0, 53 do POW2[i] = 2 ^ i end

local Bitbuf = {}
local Methods = {}
local Meta = { __index = Methods }

function Bitbuf.fromString(str)
    local byteCount = #str
    local wordCount = (byteCount + 3) // 4
    local words = table_create(wordCount, 0)
    local fullWords = byteCount // 4
    local pos = 1
    for i = 1, fullWords do
        words[i] = string_unpack("<I4", str, pos)
        pos += 4
    end
    local rem = byteCount - fullWords * 4
    if rem > 0 then
        words[fullWords + 1] = string_unpack("<I" .. rem, str, pos)
    end
    return setmetatable({ buf = words, i = 0 }, Meta)
end

local function readUnit(self, size)
    if size == 0 then return 0 end
    local bitIndex = self.i
    local wordIndex = bit32_rshift(bitIndex, 5) + 1
    local offset = bitIndex % 32
    self.i = bitIndex + size
    local words = self.buf
    if offset == 0 then
        local word = words[wordIndex] or 0
        if size == 32 then return word end
        return bit32_extract(word, 0, size)
    end
    local available = 32 - offset
    local word = words[wordIndex] or 0
    if size <= available then
        return bit32_extract(word, offset, size)
    end
    local low = bit32_extract(word, offset, available)
    local highSize = size - available
    local highWord = words[wordIndex + 1] or 0
    local high = bit32_extract(highWord, 0, highSize)
    return bit32_bor(low, bit32_lshift(high, available))
end

function Methods:ReadUint(size)
    if size <= 32 then return readUnit(self, size) end
    local low = readUnit(self, 32)
    local high = readUnit(self, size - 32)
    return low + high * UINT32_SCALE
end

function Methods:ReadInt(size)
    local value
    if size <= 32 then
        value = readUnit(self, size)
    else
        value = readUnit(self, 32) + readUnit(self, size - 32) * UINT32_SCALE
    end
    local sign = POW2[size - 1]
    if value >= sign then return value - POW2[size] end
    return value
end

function Methods:ReadFloat(size)
    if size == 32 then
        local raw = readUnit(self, 32)
        return string_unpack("<f", string_pack("<I4", raw))
    end
    local low = readUnit(self, 32)
    local high = readUnit(self, 32)
    return string_unpack("<d", string_pack("<I4I4", low, high))
end

-- ============================================
-- SHARED DATA + REMOTE
-- ============================================
local SharedData = require(ReplicatedStorage:WaitForChild("DataBins"):WaitForChild("SharedData"))
local replicationOrder = SharedData.BALL_REMOTE_REPLICATION_ORDER

local function GetNil(name, className)
    if getnilinstances then
        for _, obj in ipairs(getnilinstances()) do
            if obj.Name == name and obj.ClassName == className then
                return obj
            end
        end
    end
    return nil
end

local BallRepUnreliable = GetNil("Action", "UnreliableRemoteEvent") or ReplicatedStorage:FindFirstChild("Action")

local function GetBallSpawn()
    local activeMap = Workspace:FindFirstChild("ActiveMap")
    if activeMap then
        local mapObj = activeMap:GetChildren()[1]
        if mapObj and (mapObj:IsA("Model") or mapObj:IsA("Folder")) then
            local spawns = mapObj:FindFirstChild("BallSpawns")
            if spawns and #spawns:GetChildren() > 0 then
                return spawns:GetChildren()[1]
            end
        end
    end
    return nil
end

local cachedSpawn = nil
local function getSpawnPosition()
    if cachedSpawn == nil or cachedSpawn.Parent == nil then
        cachedSpawn = GetBallSpawn()
    end
    return cachedSpawn and cachedSpawn.Position or nil
end

local TYPE_VECTOR3 = 1
local TYPE_UINT = 2
local TYPE_FLOAT = 3
local TYPE_INT = 4
local TYPE_ID = 5
local SCALE = 0.001

local fieldCount = #replicationOrder
local fieldNames = table_create(fieldCount)
local fieldBits = table_create(fieldCount)
local fieldTypes = table_create(fieldCount)

for i = 1, fieldCount do
    local field = replicationOrder[i]
    fieldNames[i] = field[1]
    fieldBits[i] = field[2]
    local dataType = field[3]
    if dataType == "Vector3" then
        fieldTypes[i] = TYPE_VECTOR3
    elseif dataType == "Uint" then
        fieldTypes[i] = TYPE_UINT
    elseif dataType == "Float" then
        fieldTypes[i] = TYPE_FLOAT
    elseif field[1] == "Id" then
        fieldTypes[i] = TYPE_ID
    else
        fieldTypes[i] = TYPE_INT
    end
end

local function decodeBallData(bitString)
    local buf = Bitbuf.fromString(bitString)
    local data = {}
    local readInt = buf.ReadInt
    local readUint = buf.ReadUint
    local readFloat = buf.ReadFloat
    local spawnPosition = getSpawnPosition()
    for i = 1, fieldCount do
        local fieldType = fieldTypes[i]
        local bits = fieldBits[i]
        local name = fieldNames[i]
        if fieldType == TYPE_VECTOR3 then
            local value = Vector3.new(
                readInt(buf, bits) * SCALE,
                readInt(buf, bits) * SCALE,
                readInt(buf, bits) * SCALE
            )
            if name == "Position" and spawnPosition then
                value += spawnPosition
            end
            data[name] = value
        elseif fieldType == TYPE_UINT then
            data[name] = readUint(buf, bits)
        elseif fieldType == TYPE_FLOAT then
            data[name] = readFloat(buf, bits)
        elseif fieldType == TYPE_ID then
            data[name] = tostring(readInt(buf, bits))
        else
            data[name] = readInt(buf, bits)
        end
    end
    return data
end

if BallRepUnreliable then
    BallRepUnreliable.OnClientEvent:Connect(function(actionType, payload)
        local now = os.clock()
        if actionType == "Update" then
            local ok, data = pcall(decodeBallData, payload)
            if ok and data and data.Id then
                local id = data.Id
                local existing = State.balls[id]
                local vel = data.Velocity
                if not vel and existing then
                    local dt = now - existing.lastUpdate
                    if dt > 0 then vel = (data.Position - existing.position) / dt end
                end
                State.balls[id] = {
                    position = data.Position,
                    velocity = vel or Vector3.zero,
                    lastUpdate = now,
                }
                State.stats.remoteBallCount = State.stats.remoteBallCount + 1
            end
        elseif actionType == "Destroy" then
            State.balls[tostring(payload)] = nil
        end
    end)
end

local function isPlayerThreatened()
    local char = LocalPlayer.Character
    if not char then return false end
    local highlight = char:FindFirstChildWhichIsA("Highlight")
    if highlight and highlight.Enabled then
        return math.abs(highlight.FillTransparency - 0.34) <= 0.01
    end
    return false
end

local function parry()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
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
    if closestPos.Magnitude <= 15 then return timeToCPA end
    return math.huge
end

RunService.Heartbeat:Connect(function()
    if not Config.Parry then return end
    local now = os.clock()
    for id, entry in pairs(State.balls) do
        if now - entry.lastUpdate > 1.5 then
            State.balls[id] = nil
        end
    end
    if not isPlayerThreatened() then return end
    if now - State.lastParryTime < State.PARRY_COOLDOWN then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position
    local playerVel = hrp.AssemblyLinearVelocity
    for _, entry in pairs(State.balls) do
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
-- FOLLOW BALL
-- ============================================
local function findRealBallFromNil()
    if not getnilinstances then return nil end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local bestBall, bestDist = nil, math.huge
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
                if dist < bestDist then bestDist = dist; bestBall = obj end
            end
        end
    end
    return bestBall, bestDist
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if screen.Parent == nil then break end
        if Config.FollowBall then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local targetPos = nil
                local bestBall, bestDist = nil, math.huge
                for _, entry in pairs(State.balls) do
                    local dist = (entry.position - hrp.Position).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestBall = entry
                    end
                end
                if bestBall then
                    targetPos = bestBall.position
                else
                    local nilBall = findRealBallFromNil()
                    if nilBall then targetPos = nilBall.Position end
                end
                if targetPos then
                    local flat = Vector3.new(
                        (targetPos - hrp.Position).X, 0,
                        (targetPos - hrp.Position).Z)
                    if flat.Magnitude > 3 then
                        walkTo(targetPos)
                    else
                        stopPath()
                    end
                else
                    stopPath()
                end
            end
        end
    end
end)

_G.__DBA_scanZone = function()
    log("=== SCAN ZONE ===")
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then log("No HRP"); return end
    log("Intermission: " .. tostring(isIntermission()))
    local readyZone = getReadyZone()
    if readyZone then
        log(string.format("Zone: (%.1f,%.1f,%.1f)",
            readyZone.Position.X, readyZone.Position.Y, readyZone.Position.Z))
        log("Inside: " .. tostring(isInsideZone(hrp.Position, readyZone)))
    end
end

-- Stats
task.spawn(function()
    while true do
        task.wait(0.3)
        if screen.Parent == nil then break end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local matchTxt = isIntermission() and "INTER" or "INGAME"
        local remoteBallTxt = 0
        for _ in pairs(State.balls) do remoteBallTxt = remoteBallTxt + 1 end
        local wsTxt = humanoid and string.format("%.0f", humanoid.WalkSpeed) or "?"
        local threatenedTxt = isPlayerThreatened() and "TARGETED" or "safe"
        statsLbl.Text = string.format(
            "%s | Ball:%d | WS:%s | Parry:%d | Rot:%d | %s",
            matchTxt, remoteBallTxt, wsTxt,
            State.stats.parryFired, State.stats.rotationApplied,
            threatenedTxt)
    end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        reopenBtn.Visible = not main.Visible
    end
end)

log("═══════════════════════════════════════")
log("Death Ball Auto v1.5")
log("═══════════════════════════════════════")
log("✅ Body Rotation FIX (ngikutin arah gerak)")
log("✅ RotationLerp: " .. Config.RotationLerp)
log("✅ Parry: Remote decode")
log("✅ Movement: Stepped + Force Velocity")
log("✅ AutoReady: IntermissionFrame detect")
log("")
if BallRepUnreliable then
    log("✅ BallRepUnreliable: " .. BallRepUnreliable:GetFullName())
else
    log("❌ BallRepUnreliable NOT found")
end
