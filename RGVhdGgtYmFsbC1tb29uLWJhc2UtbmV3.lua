-- ============================================================
-- Moon Script (Rayfield UI) — for_jamalkun
-- Rewritten from Obsidian → Rayfield (mobile-friendly)
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- UI: Rayfield
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/Footagesus/Rayfield/main/source.lua'))()

local Window = Rayfield:CreateWindow({
    Name = "Moon",
    Icon = 0,
    LoadingTitle = "Moon",
    LoadingSubtitle = "version: for_jamalkun",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "Moon",
        FileName = "Config"
    },
    KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 0)
local SettingsTab = Window:CreateTab("UI Settings", 0)

-- ============================================================
-- State flags
-- ============================================================
local AutoReadyEnabled = false
local AIMoveEnabled = false
local FollowBallEnabled = false

MainTab:CreateSection("Controls")

MainTab:CreateToggle({
    Name = "Auto Ready",
    CurrentValue = false,
    Flag = "AutoReady",
    Callback = function(Value)
        AutoReadyEnabled = Value
    end,
})

MainTab:CreateToggle({
    Name = "Ai move",
    CurrentValue = false,
    Flag = "AIMove",
    Callback = function(Value)
        AIMoveEnabled = Value
    end,
})

MainTab:CreateToggle({
    Name = "Follow ball",
    CurrentValue = false,
    Flag = "FollowBall",
    Callback = function(Value)
        FollowBallEnabled = Value
    end,
})

-- ============================================================
-- Bit stream decoder
-- ============================================================
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
for i = 0, 53 do
    POW2[i] = 2 ^ i
end

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
    if size <= 32 then
        return readUnit(self, size)
    end
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
    if value >= sign then
        return value - POW2[size]
    end
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

-- ============================================================
-- SharedData
-- ============================================================
local SharedData = require(ReplicatedStorage:WaitForChild("DataBins"):WaitForChild("SharedData"))
local replicationOrder = SharedData.BALL_REMOTE_REPLICATION_ORDER

local function GetNil(name, className)
    if getnilinstances then
        for _, obj in getnilinstances() do
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

-- ============================================================
-- Field schema
-- ============================================================
local TYPE_VECTOR3 = 1
local TYPE_UINT = 2
local TYPE_FLOAT = 3
local TYPE_INT = 4
local TYPE_ID = 5
local SCALE = 0.001

local fieldCount = #replicationOrder
local fieldNames = table.create(fieldCount)
local fieldBits = table.create(fieldCount)
local fieldTypes = table.create(fieldCount)

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

-- ============================================================
-- Ball tracking + parry
-- ============================================================
local balls = {}
local lastParryTime = 0
local PARRY_COOLDOWN = 0
local PARRY_TRIGGER_TIME = 0.15

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
end

local function calculateTimeToImpact(ballPos, ballVel, playerPos, playerVel)
    local relPos = playerPos - ballPos
    local relVel = ballVel - playerVel
    local relSpeedSq = relVel:Dot(relVel)

    if relSpeedSq <= 1e-4 then
        return math.huge
    end

    local timeToCPA = relPos:Dot(relVel) / relSpeedSq
    if timeToCPA <= 0 then
        return math.huge
    end

    local closestPos = relPos - (relVel * timeToCPA)
    local missDistance = closestPos.Magnitude

    if missDistance <= 15 then
        return timeToCPA
    end

    return math.huge
end

if BallRepUnreliable then
    BallRepUnreliable.OnClientEvent:Connect(function(actionType, payload)
        local now = os.clock()
        if actionType == "Update" then
            local data = decodeBallData(payload)
            local id = data.Id
            if id then
                local existing = balls[id]
                local vel = data.Velocity

                if not vel and existing then
                    local dt = now - existing.lastUpdate
                    if dt > 0 then
                        vel = (data.Position - existing.position) / dt
                    end
                end

                balls[id] = {
                    position = data.Position,
                    velocity = vel or Vector3.zero,
                    lastUpdate = now
                }
            end
        elseif actionType == "Destroy" then
            balls[tostring(payload)] = nil
        end
    end)
end

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    for id, entry in pairs(balls) do
        if now - entry.lastUpdate > 1.5 then
            balls[id] = nil
        end
    end

    if not isPlayerThreatened() then return end
    if now - lastParryTime < PARRY_COOLDOWN then return end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local playerPos = hrp.Position
    local playerVel = hrp.AssemblyLinearVelocity

    for _, entry in pairs(balls) do
        local ballPos = entry.position
        local ballVel = entry.velocity
        local ballSpeed = ballVel.Magnitude

        if ballSpeed > 0.01 then
            local timeToImpact = calculateTimeToImpact(ballPos, ballVel, playerPos, playerVel)

            if timeToImpact > 0 and timeToImpact <= PARRY_TRIGGER_TIME then
                parry()
                lastParryTime = now
                break
            end
        end
    end
end)

-- ============================================================
-- Movement (VirtualInputManager keys)
-- ============================================================
local moveKeyStates = { W = false, A = false, S = false, D = false }
local walkTarget = nil

local function setMoveKey(key, state)
    if moveKeyStates[key] == state then return end
    moveKeyStates[key] = state
    VirtualInputManager:SendKeyEvent(state, Enum.KeyCode[key], false, game)
end

local function clearMoveKeys()
    for key, state in pairs(moveKeyStates) do
        if state then
            setMoveKey(key, false)
        end
    end
end

local function stopPath()
    walkTarget = nil
    clearMoveKeys()
end

local function walkTo(targetPos)
    walkTarget = targetPos
end

RunService.Heartbeat:Connect(function()
    if not walkTarget then
        clearMoveKeys()
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        clearMoveKeys()
        return
    end

    local toTarget = walkTarget - hrp.Position
    local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flat.Magnitude < 2 then
        clearMoveKeys()
        return
    end

    local cam = Workspace.CurrentCamera
    if not cam then
        clearMoveKeys()
        return
    end

    local camLook = cam.CFrame.LookVector
    camLook = Vector3.new(camLook.X, 0, camLook.Z)
    if camLook.Magnitude < 0.01 then
        camLook = Vector3.new(0, 0, -1)
    else
        camLook = camLook.Unit
    end
    local camRight = Vector3.new(-camLook.Z, 0, camLook.X)

    local dir = flat.Unit
    local forward = dir:Dot(camLook)
    local right = dir:Dot(camRight)

    setMoveKey("W", forward > 0.2)
    setMoveKey("S", forward < -0.2)
    setMoveKey("D", right > 0.2)
    setMoveKey("A", right < -0.2)
end)

-- ============================================================
-- Auto Ready
-- ============================================================
local function getIntermissionFrame()
    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local hud = pGui and pGui:FindFirstChild("HUD")
    local holder = hud and hud:FindFirstChild("HolderBottom")
    return holder and holder:FindFirstChild("IntermissionFrame")
end

local function isInsideZone(position, zone)
    local rel = zone.CFrame:PointToObjectSpace(position)
    return math.abs(rel.X) <= (zone.Size.X / 2) and math.abs(rel.Z) <= (zone.Size.Z / 2)
end

local currentLobbyTarget = nil
local function getRandomPositionInZone(zone)
    local size = zone.Size
    local limitX = math.max(1, size.X - 4)
    local limitZ = math.max(1, size.Z - 4)
    local rx = (math.random() - 0.5) * limitX
    local rz = (math.random() - 0.5) * limitZ
    return (zone.CFrame * CFrame.new(rx, 0, rz)).Position
end

task.spawn(function()
    while true do
        task.wait(0.2)
        if AutoReadyEnabled then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local intermissionFrame = getIntermissionFrame()

            if intermissionFrame and intermissionFrame.Visible and hrp then
                local lobby = Workspace:FindFirstChild("New Lobby")
                local readyArea = lobby and lobby:FindFirstChild("ReadyArea")
                local readyZone = readyArea and readyArea:FindFirstChild("ReadyZone")

                if readyZone then
                    if not isInsideZone(hrp.Position, readyZone) then
                        if not currentLobbyTarget or not isInsideZone(currentLobbyTarget, readyZone) then
                            currentLobbyTarget = getRandomPositionInZone(readyZone)
                        end
                        walkTo(currentLobbyTarget)
                    else
                        currentLobbyTarget = nil
                        if walkTarget then
                            stopPath()
                        end
                    end
                end
            else
                if currentLobbyTarget then
                    currentLobbyTarget = nil
                    stopPath()
                end
            end
        else
            if currentLobbyTarget then
                currentLobbyTarget = nil
                stopPath()
            end
        end
    end
end)

-- ============================================================
-- Player data (HP read from billboard)
-- ============================================================
local PlayerData = {}

local function getPlayerHP(plr)
    if not plr.Character then return nil end
    local head = plr.Character:FindFirstChild("Head")
    if not head then return nil end
    local billboard = head:FindFirstChild("PlayerBillboard")
    if not billboard then return nil end
    local bar = billboard:FindFirstChild("Bar")
    if not bar then return nil end
    local inner = bar:FindFirstChild("Inner")
    if not inner then return nil end

    local color = inner.BackgroundColor3
    local r = math.round(color.R * 255)
    local g = math.round(color.G * 255)
    local b = math.round(color.B * 255)

    if r == 38 and g == 255 and b == 0 then return 3
    elseif r == 183 and g == 250 and b == 0 then return 2
    elseif r == 255 and g == 165 and b == 1 then return 1
    elseif r == 255 and g == 0 and b == 4 then return 0
    end
    return nil
end

local function initPlayerData(plr)
    if PlayerData[plr] then return end
    PlayerData[plr] = {
        hp = nil,
        lastHp = nil,
        hasHighlight = false,
        lastHighlightState = false,
        name = plr.Name or "Unknown"
    }
end

local function updateAllTargets()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            initPlayerData(plr)
            local data = PlayerData[plr]
            data.lastHp = data.hp
            data.hp = getPlayerHP(plr)
            data.name = plr.Name
            data.displayName = plr.DisplayName
        end
    end

    local botsFolder = Workspace:FindFirstChild("Bots")
    if botsFolder then
        for _, bot in pairs(botsFolder:GetChildren()) do
            if bot:IsA("Model") and bot:FindFirstChild("Humanoid") and bot:FindFirstChild("Head") then
                if not PlayerData[bot] then
                    PlayerData[bot] = {
                        hp = nil, lastHp = nil,
                        hasHighlight = false, lastHighlightState = false,
                        isBot = true, name = bot.Name
                    }
                end
                local data = PlayerData[bot]
                data.lastHp = data.hp
                data.hp = getPlayerHP({Character = bot})
                data.name = bot.Name
                data.displayName = bot.Name
            end
        end
    end
end

-- ============================================================
-- AI Move / Follow Ball
-- ============================================================
getgenv().AITargets = getgenv().AITargets or {}
local aiActiveTarget = nil
local aiAcquiredTime = 0
local aiLastJump = 0
local aiLastQ = 0
local aiWanderTarget = nil
local aiLastWanderChoice = 0

local function getNewAITarget()
    local now = os.clock()
    local bestTarget = nil
    local minDistance = math.huge
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    updateAllTargets()

    for targetObj, data in pairs(PlayerData) do
        local targetChar = nil
        if data.isBot then
            targetChar = targetObj
        else
            targetChar = targetObj.Character
        end

        if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
            local targetName = data.name
            local blacklistData = getgenv().AITargets[targetName] or { blacklistedUntil = 0 }
            getgenv().AITargets[targetName] = blacklistData

            if now >= blacklistData.blacklistedUntil then
                local hp = data.hp or getPlayerHP({Character = targetChar}) or 3
                if hp > 0 then
                    local dist = (targetChar.HumanoidRootPart.Position - hrp.Position).Magnitude
                    if dist < minDistance then
                        minDistance = dist
                        bestTarget = targetObj
                    end
                end
            end
        end
    end
    return bestTarget
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if AIMoveEnabled or FollowBallEnabled then
            local hud = LocalPlayer.PlayerGui:FindFirstChild("HUD")
        
