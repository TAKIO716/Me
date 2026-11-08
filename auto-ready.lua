--[[
    Auto Walk to Ready Zone
    - Di Lobby: Jalan ke ReadyZone
    - Di Match: Diem
    - Balik ke Lobby: Jalan lagi ke ReadyZone
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ================= CONFIG ==================
local CONFIG = {
    Enabled = true,
    WalkSpeed = 16,
    MatchStopDistance = 1000, -- Jarak aman dari lobby buat ngedeteksi match
    LobbyStopDistance = 500,
    CheckInterval = 0.5,      -- Cek state tiap 0.5 detik
}

-- ================= STATE ==================
local State = {
    Current = "IDLE", -- IDLE, WALKING, MATCH, WAITING
    SpawnPos = Vector3.new(564, 286, -861), -- Titik awal spawn
    LastPosition = Vector3.zero,
}

-- ================= REFS ==================
local Refs = {
    ReadyZone = nil,
    LobbyPart = nil,
}

-- ================= UI ==================
local parentGui = gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoReadyUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9999
screenGui.Parent = parentGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 160)
main.Position = UDim2.new(0.5, -150, 0, 50)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
main.BorderSizePixel = 0
main.Active = true
main.Parent = screenGui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 10)
mc.Parent = main

local ms = Instance.new("UIStroke")
ms.Color = Color3.fromRGB(90, 90, 130)
ms.Thickness = 1
ms.Transparency = 0.3
ms.Parent = main

-- Title
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 10)
tc.Parent = titleBar

local tf = Instance.new("Frame")
tf.Size = UDim2.new(1, 0, 0, 10)
tf.Position = UDim2.new(0, 0, 1, -10)
tf.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
tf.BorderSizePixel = 0
tf.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🏃 Auto Walk to Ready"
title.TextColor3 = Color3.fromRGB(240, 240, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -26, 0.5, -10)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar

local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0, 4)
cc.Parent = closeBtn

-- Toggle Button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -24, 0, 32)
toggleBtn.Position = UDim2.new(0, 12, 0, 36)
toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "🟢 ON"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.Parent = main

local tcc = Instance.new("UICorner")
tcc.CornerRadius = UDim.new(0, 6)
tcc.Parent = toggleBtn

-- Status Label
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -24, 0, 24)
statusLbl.Position = UDim2.new(0, 12, 0, 76)
statusLbl.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
statusLbl.BorderSizePixel = 0
statusLbl.Text = "State: IDLE"
statusLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 11
statusLbl.Parent = main

local slc = Instance.new("UICorner")
slc.CornerRadius = UDim.new(0, 6)
slc.Parent = statusLbl

-- Info Label
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -24, 0, 30)
infoLbl.Position = UDim2.new(0, 12, 0, 106)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "Distance to Ready: -"
infoLbl.TextColor3 = Color3.fromRGB(120, 220, 160)
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = main

-- ================= UTILS ==================
local function getChar()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
end

local function getPosition()
    local hrp = getChar()
    return hrp and hrp.Position or nil
end

local function isInsideZone(part, pos)
    if not part or not pos then return false end
    local ok, res = pcall(function()
        local rel = part.CFrame:PointToObjectSpace(pos)
        local half = part.Size / 2
        return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
    end)
    return ok and res
end

local function setupRefs()
    -- Cari ReadyZone
    local lobby = Workspace:FindFirstChild("New Lobby before Halloween")
    if lobby then
        local readyArea = lobby:FindFirstChild("ReadyArea")
        if readyArea then
            Refs.ReadyZone = readyArea:FindFirstChild("ReadyZone")
            Refs.LobbyPart = lobby:FindFirstChild("LightingZone")
        end
    end
    
    return Refs.ReadyZone ~= nil
end

-- ================= MAIN LOGIC ==================
local function updateState()
    if not CONFIG.Enabled then
        State.Current = "IDLE"
        return
    end
    
    local hrp, humanoid = getChar()
    if not hrp or not humanoid then
        State.Current = "WAITING"
        return
    end
    
    local pos = hrp.Position
    local spawnPos = State.SpawnPos
    
    -- 1. Deteksi lagi di Match (jauh dari lobby)
    local distToSpawn = (pos - spawnPos).Magnitude
    if distToSpawn > CONFIG.MatchStopDistance then
        if State.Current ~= "MATCH" then
            State.Current = "MATCH"
            humanoid:MoveTo(pos) -- Stop gerak
        end
        return
    end
    
    -- 2. Deteksi di Lobby
    if distToSpawn < CONFIG.LobbyStopDistance then
        -- Kalo di lobby, jalan ke ReadyZone
        if Refs.ReadyZone then
            local distToReady = (pos - Refs.ReadyZone.Position).Magnitude
            
            -- Cek apakah udah di dalem zone
            if isInsideZone(Refs.ReadyZone, pos) then
                if State.Current ~= "IN_ZONE" then
                    State.Current = "IN_ZONE"
                    humanoid:MoveTo(pos) -- Stop gerak
                end
            else
                if State.Current ~= "WALKING" then
                    State.Current = "WALKING"
                end
                -- Jalan ke ReadyZone
                humanoid:MoveTo(Refs.ReadyZone.Position)
            end
            
            infoLbl.Text = string.format("Distance to Ready: %.0fm", distToReady)
        else
            -- Kalo gak nemu ReadyZone, coba cari lagi
            setupRefs()
            State.Current = "WAITING"
        end
    else
        -- Di antara lobby dan match, nunggu
        State.Current = "WAITING"
    end
end

-- ================= MAIN LOOP ==================
task.spawn(function()
    while screenGui.Parent do
        task.wait(CONFIG.CheckInterval)
        
        if CONFIG.Enabled then
            updateState()
            statusLbl.Text = "State: "..State.Current
        else
            statusLbl.Text = "State: IDLE (off)"
        end
    end
end)

-- ================= BUTTONS ==================
toggleBtn.MouseButton1Click:Connect(function()
    CONFIG.Enabled = not CONFIG.Enabled
    if CONFIG.Enabled then
        toggleBtn.Text = "🟢 ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
        State.Current = "IDLE"
    else
        toggleBtn.Text = "⚪ OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        -- Stop movement
        local _, hum = getChar()
        if hum then hum:MoveTo(hum.RootPart.Position) end
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

-- ================= DRAGGING ==================
local drag, ds, sp
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; ds = i.Position; sp = main.Position
    end
end)

UserInputService.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - ds
        main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = false
    end
end)

-- ================= INIT ==================
setupRefs()
print("[AutoReady] Loaded. ReadyZone found:", Refs.ReadyZone ~= nil)
