--[[
    PYC Auto-Farm + Auto-Sell v10 (Custom Obfuscated)
    - Multi-layer obfuscation (XOR + custom base64 + noise)
    - Dashboard UI + Graph + Optimize
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============ DECODER ============
local _a = "pYc@"
local _b = "2026#"
local _c = "KyR!"
local _d = "xZq$"
local _e = "l0k"
local MASTER_KEY = _a.._b.._c.._d.._e

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CUSTOM_ALPHA = {}
for i = 1, #ALPHABET do
    local newIdx = ((i - 1 + 17) % #ALPHABET) + 1
    CUSTOM_ALPHA[i] = ALPHABET:sub(newIdx, newIdx)
end
local CUSTOM_ALPHABET = table.concat(CUSTOM_ALPHA)

local REVERSE_MAP = {}
for i = 1, #CUSTOM_ALPHABET do
    REVERSE_MAP[CUSTOM_ALPHABET:sub(i, i)] = i - 1
end

local function xorByte(a, b)
    if bit32 and bit32.bxor then return bit32.bxor(a, b) end
    local r, m = 0, 1
    while a > 0 or b > 0 do
        local ab, bb = a % 2, b % 2
        if ab ~= bb then r = r + m end
        a = math.floor(a / 2); b = math.floor(b / 2); m = m * 2
    end
    return r
end

local function removeNoise(s)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if REVERSE_MAP[c] then table.insert(out, c) end
    end
    return table.concat(out)
end

local function b64ToBytes(s)
    local bytes = {}
    local i = 1
    while i <= #s do
        local c1 = REVERSE_MAP[s:sub(i, i)] or 0
        local c2 = REVERSE_MAP[s:sub(i+1, i+1)] or 0
        local c3 = REVERSE_MAP[s:sub(i+2, i+2)] or 0
        local c4 = REVERSE_MAP[s:sub(i+3, i+3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        local b1 = math.floor(n / 65536) % 256
        local b2 = math.floor(n / 256) % 256
        local b3 = n % 256
        if i + 1 <= #s then table.insert(bytes, b1) end
        if i + 2 <= #s then table.insert(bytes, b2) end
        if i + 3 <= #s then table.insert(bytes, b3) end
        i = i + 4
    end
    return bytes
end

local function decode(obfuscated)
    if not obfuscated or obfuscated == "" then return "" end
    local cleaned = removeNoise(obfuscated)
    local bytes = b64ToBytes(cleaned)
    local out = {}
    for i = 1, #bytes do
        local k = MASTER_KEY:byte(((i - 1) % #MASTER_KEY) + 1)
        out[i] = string.char(xorByte(bytes[i], k))
    end
    return table.concat(out)
end

-- ============ OBF (PASTE DARI OBFUSCATOR) ============
local OBF = {
    WebhookURL = "XTFo9dVVb2Yi2Y8Zx5C9kx5PxoFtU?olhi/bh6A/immh~o1B1`VzVf!jnOY@WW5V#lFi8$lIpW%SBVg^WIGc&qBJs*Yz29(a22w)SUFn_V2Bu+THZo-cCZn=vkVP[iGtE]R0BX{eBB+}qRy0|lYV1;dUSP:Rh5/,WWKO.lChZ<Uk1S>rX+j9rCxy2gipM8djm/9U1WjxZ",
    AuthorizedUserID = "iHGr9txVY2SxZl8vFC19XVC0xhya",
    BotToken = "ghFH9t4OF2rBq+8YDx29sRZOxhn15?pmxQ/UkaB/wGtt~tmp+`Znlh!mz5G@si6D#Zyhf$TIqC%TSNV^lD5D&gndQ*ZUuy(TXdO)cHxb_RlpS+SBuR-tyF",
    ChannelID = "hnCm9tRhV2Txhi8v1Wy9V1S5xhCqw?T",
}

-- ============ CONFIG ============
local CONFIG = {
    Enabled = false,
    SellMode = false,
    CapacitorName = "CrimsonBattery",
    TimerThreshold = 5,
    CapacitorTolerance = 6,
    GreenTolerance = 5,
    StayAtGreenTime = 1.5,
    FallbackTimerDuration = 170,
    SpamKey = Enum.KeyCode.One,
    SpamInterval = 0.15,
    EnergyPath = {"PlayerGui", "Main", "HUD", "BottomLeft", "Power"},
    MoneyPath = {"PlayerGui", "Main", "HUD", "BottomLeft", "Money"},
    TeleportBtnPath = {"PlayerGui", "Main", "HUD", "Top", "Sell"},
    MultiplierWaypoint = Vector3.new(930, 5.5, 270),
    StayAtWaypoint = 0.8,
    UseTeleport = true,
    TeleportWaitTime = 1.5,
    ChaseTriggerTimeout = 10,
    BackToPlotTimeout = 20,
    GetCaughtTimeout = 5,
    MaxSellRetries = 5,
    PreferExactName = "Sell",
    PostClickDelay = 0.7,
    OfferDetectDelay = 0.5,
    WebhookURL = decode(OBF.WebhookURL),
    BotToken = decode(OBF.BotToken),
    ChannelID = decode(OBF.ChannelID),
    AuthorizedUserID = decode(OBF.AuthorizedUserID),
    PollInterval = 5,
    AutoReportOnSell = true,
}

if CONFIG.WebhookURL == "" or CONFIG.BotToken == "" then
    warn("[PYC] ⚠️ OBF kosong, jalanin obfuscator dulu")
end

-- ============ STATE ============
local State = {
    Mode = "IDLE", FarmState = "IDLE", SellState = "IDLE",
    FallbackCycleStart = 0, LastGreenEnter = 0, LastSpamTime = 0,
    SpamCount = 0, CheckStartTime = 0, GreenInjected = false,
    OfferVisibleSince = 0, LoggedButtons = false,
    SessionStart = tick(), TotalSells = 0, TotalEnergySold = 0,
    LastMessageID = nil, PosBeforeChase = nil, BackToPlotTime = 0,
    EnergyBeforeSell = nil, PlotNum = nil, StayStartTime = 0,
    GetCaughtTime = 0, StartTime = 0, SellRetryCount = 0,
    DiscordStatus = "Connecting", Ping = 0, FPS = 0,
    LastOptimizeTime = 0,
}

local Refs = {
    TimerObject = nil, CapacitorPos = nil, GreenPlatePos = nil,
    PlotFolder = nil, PlotNumber = nil, EnergyObject = nil,
    MoneyObject = nil, TeleportBtn = nil, SellZone = nil,
}

local EnergyHistory = {}
local MAX_HISTORY = 60

-- ============ GUI ============
local parentGui = gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PYCCombined"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9999
screenGui.Parent = parentGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 400, 0, 480)
main.Position = UDim2.new(0.5, -200, 0.5, -240)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
main.BorderSizePixel = 0
main.Active = true
main.Parent = screenGui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 12)
mc.Parent = main

local ms = Instance.new("UIStroke")
ms.Color = Color3.fromRGB(90, 90, 130)
ms.Thickness = 1
ms.Transparency = 0.3
ms.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 12)
tc.Parent = titleBar

local tf = Instance.new("Frame")
tf.Size = UDim2.new(1, 0, 0, 12)
tf.Position = UDim2.new(0, 0, 1, -12)
tf.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
tf.BorderSizePixel = 0
tf.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡ PYC Auto v10"
title.TextColor3 = Color3.fromRGB(240, 240, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0.5, -12)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar

local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0, 6)
cc.Parent = closeBtn

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -24, 1, -50)
content.Position = UDim2.new(0, 12, 0, 44)
content.BackgroundTransparency = 1
content.Parent = main

local topRow = Instance.new("Frame")
topRow.Size = UDim2.new(1, 0, 0, 36)
topRow.BackgroundTransparency = 1
topRow.Parent = content

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.5, -4, 1, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "⚪ OFF"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = topRow

local tcc = Instance.new("UICorner")
tcc.CornerRadius = UDim.new(0, 8)
tcc.Parent = toggleBtn

local optimizeBtn = Instance.new("TextButton")
optimizeBtn.Size = UDim2.new(0.5, -4, 1, 0)
optimizeBtn.Position = UDim2.new(0.5, 4, 0, 0)
optimizeBtn.BackgroundColor3 = Color3.fromRGB(70, 100, 160)
optimizeBtn.BorderSizePixel = 0
optimizeBtn.Text = "⚙ Optimize"
optimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
optimizeBtn.Font = Enum.Font.GothamBold
optimizeBtn.TextSize = 12
optimizeBtn.AutoButtonColor = false
optimizeBtn.Parent = topRow

local obc = Instance.new("UICorner")
obc.CornerRadius = UDim.new(0, 8)
obc.Parent = optimizeBtn

local statsFrame = Instance.new("Frame")
statsFrame.Size = UDim2.new(1, 0, 0, 130)
statsFrame.Position = UDim2.new(0, 0, 0, 44)
statsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
statsFrame.BorderSizePixel = 0
statsFrame.Parent = content

local sfc = Instance.new("UICorner")
sfc.CornerRadius = UDim.new(0, 8)
sfc.Parent = statsFrame

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -8, 0, 32)
grid.CellPadding = UDim2.new(0, 6, 0, 4)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = statsFrame

local gridPad = Instance.new("UIPadding")
gridPad.PaddingTop = UDim.new(0, 6)
gridPad.PaddingLeft = UDim.new(0, 6)
gridPad.PaddingRight = UDim.new(0, 6)
gridPad.PaddingBottom = UDim.new(0, 6)
gridPad.Parent = statsFrame

local statCells = {}
local function createStatCell(label)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    f.BorderSizePixel = 0
    f.Parent = statsFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = f
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 1, 0)
    lbl.Position = UDim2.new(0, 6, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.Parent = f
    return lbl
end

statCells.money = createStatCell("💰 Money: -")
statCells.energy = createStatCell("⚡ Energy: -")
statCells.discord = createStatCell("🤖 Discord: -")
statCells.ping = createStatCell("📡 Ping: -")
statCells.fps = createStatCell("🎮 FPS: -")
statCells.retry = createStatCell("🔁 Retry: 0/0")
statCells.sold = createStatCell("📦 Sold: 0")
statCells.barrier = createStatCell("🛡️ Barrier: -")

local stateFrame = Instance.new("Frame")
stateFrame.Size = UDim2.new(1, 0, 0, 24)
stateFrame.Position = UDim2.new(0, 0, 0, 180)
stateFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
stateFrame.BorderSizePixel = 0
stateFrame.Parent = content

local stc = Instance.new("UICorner")
stc.CornerRadius = UDim.new(0, 6)
stc.Parent = stateFrame

local stateLbl = Instance.new("TextLabel")
stateLbl.Size = UDim2.new(1, -12, 1, 0)
stateLbl.Position = UDim2.new(0, 6, 0, 0)
stateLbl.BackgroundTransparency = 1
stateLbl.Text = "Mode: IDLE"
stateLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
stateLbl.TextXAlignment = Enum.TextXAlignment.Left
stateLbl.Font = Enum.Font.Code
stateLbl.TextSize = 11
stateLbl.Parent = stateFrame

local graphFrame = Instance.new("Frame")
graphFrame.Size = UDim2.new(1, 0, 0, 100)
graphFrame.Position = UDim2.new(0, 0, 0, 212)
graphFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
graphFrame.BorderSizePixel = 0
graphFrame.Parent = content

local gfc = Instance.new("UICorner")
gfc.CornerRadius = UDim.new(0, 8)
gfc.Parent = graphFrame

local graphTitle = Instance.new("TextLabel")
graphTitle.Size = UDim2.new(1, -12, 0, 18)
graphTitle.Position = UDim2.new(0, 6, 0, 4)
graphTitle.BackgroundTransparency = 1
graphTitle.Text = "📈 Energy Rate (last 60s)"
graphTitle.TextColor3 = Color3.fromRGB(180, 180, 200)
graphTitle.TextXAlignment = Enum.TextXAlignment.Left
graphTitle.Font = Enum.Font.GothamBold
graphTitle.TextSize = 11
graphTitle.Parent = graphFrame

local graphCanvas = Instance.new("Frame")
graphCanvas.Size = UDim2.new(1, -12, 1, -28)
graphCanvas.Position = UDim2.new(0, 6, 0, 24)
graphCanvas.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
graphCanvas.BorderSizePixel = 0
graphCanvas.ClipsDescendants = true
graphCanvas.Parent = graphFrame

local gcc = Instance.new("UICorner")
gcc.CornerRadius = UDim.new(0, 4)
gcc.Parent = graphCanvas

local graphBars = Instance.new("Frame")
graphBars.Size = UDim2.new(1, 0, 1, 0)
graphBars.BackgroundTransparency = 1
graphBars.Parent = graphCanvas

local graphLayout = Instance.new("UIListLayout")
graphLayout.FillDirection = Enum.FillDirection.Horizontal
graphLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
graphLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
graphLayout.SortOrder = Enum.SortOrder.LayoutOrder
graphLayout.Parent = graphBars

-- ============ UTILS ============
local function getChar()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
end

local function walkTo(pos)
    local hrp, humanoid = getChar()
    if not hrp or not humanoid then return end
    humanoid:MoveTo(pos)
end

local function teleportTo(pos)
    local hrp = getChar()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(pos)
    return true
end

local function setSpeed(speed)
    local _, humanoid = getChar()
    if humanoid then humanoid.WalkSpeed = speed end
end

local function spamKey(key)
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(0.03)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function httpRequest(opts)
    if typeof(request) == "function" then return request(opts) end
    if typeof(http_request) == "function" then return http_request(opts) end
    if typeof(syn) == "table" and typeof(syn.request) == "function" then return syn.request(opts) end
    return nil
end

local function parseNumber(str)
    if not str then return nil end
    str = tostring(str):gsub(",", ""):gsub("%s", ""):gsub("%$", "")
    local num, suffix = str:match("([%d%.]+)([KkMmBbTt]?)")
    if not num then return nil end
    num = tonumber(num)
    if not num then return nil end
    suffix = suffix:lower()
    if suffix == "k" then return num * 1000
    elseif suffix == "m" then return num * 1000000
    elseif suffix == "b" then return num * 1000000000
    elseif suffix == "t" then return num * 1000000000000
    else return num end
end

local function formatNumber(n)
    if not n then return "-" end
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n/1e3)
    else return string.format("%.0f", n) end
end

local function getByPath(root, pathArr)
    local current = root
    for _, part in ipairs(pathArr) do
        local next = current:FindFirstChild(part)
        if not next then return nil end
        current = next
    end
    return current
end

local function getEnergyValue()
    if not Refs.EnergyObject then return nil end
    local ok, text = pcall(function() return Refs.EnergyObject.Text end)
    if ok and text then return parseNumber(text) end
    return nil
end

local function getMoneyValue()
    if not Refs.MoneyObject then return nil end
    local ok, text = pcall(function() return Refs.MoneyObject.Text end)
    if ok and text then return parseNumber(text) end
    return nil
end

local function getTimerValue()
    if Refs.TimerObject then
        local ok, text = pcall(function() return Refs.TimerObject.Text end)
        if ok and text then
            local num = tonumber(text:match("(%d+)"))
            if num then return num end
        end
    end
    if State.FallbackCycleStart > 0 then
        local elapsed = tick() - State.FallbackCycleStart
        local remaining = CONFIG.FallbackTimerDuration - elapsed
        if remaining < 0 then remaining = 0 end
        return math.floor(remaining)
    end
    return nil
end

local function detectPlot()
    local hrp = getChar()
    if not hrp then return nil, nil end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil, nil end
    local closest, dist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        local spawn = plot:FindFirstChild("Spawn")
        if spawn then
            local d = (spawn.Position - hrp.Position).Magnitude
            if d < dist then dist = d; closest = plot end
        end
    end
    return closest, closest and tonumber(closest.Name) or nil
end

local function setupRefs()
    local _, plotNum = detectPlot()
    if plotNum then
        State.PlotNum = plotNum
        Refs.PlotNumber = plotNum
        local plots = Workspace:FindFirstChild("Plots")
        if plots then Refs.PlotFolder = plots:FindFirstChild(tostring(plotNum)) end
        if Refs.PlotFolder then
            local lock = Refs.PlotFolder:FindFirstChild("Lock")
            if lock then
                local att = lock:FindFirstChild("Attachment")
                if att then
                    local bb = att:FindFirstChild("BillboardGui")
                    if bb then
                        local timer = bb:FindFirstChild("Timer")
                        if timer and timer:IsA("TextLabel") then Refs.TimerObject = timer end
                    end
                end
                local lf = lock:FindFirstChild("LockFree")
                if lf then
                    local hit = lf:FindFirstChild("Hit")
                    if hit then Refs.GreenPlatePos = hit.Position end
                end
            end
            local placed = Refs.PlotFolder:FindFirstChild("PlacedObjects")
            if placed then
                local cap = placed:FindFirstChild(CONFIG.CapacitorName)
                if cap then
                    local base = cap:FindFirstChild("Bottom") or cap:FindFirstChildWhichIsA("BasePart", true)
                    if base then Refs.CapacitorPos = base.Position end
                end
            end
        end
        local sell = Workspace:FindFirstChild("Sell")
        if sell then
            local zones = sell:FindFirstChild("Zones")
            if zones then Refs.SellZone = zones:FindFirstChild(tostring(plotNum)) end
        end
    end
    local eObj = getByPath(LocalPlayer, CONFIG.EnergyPath)
    if eObj and eObj:IsA("TextLabel") then Refs.EnergyObject = eObj end
    local mObj = getByPath(LocalPlayer, CONFIG.MoneyPath)
    if mObj and mObj:IsA("TextLabel") then Refs.MoneyObject = mObj end
    local tpBtn = getByPath(LocalPlayer, CONFIG.TeleportBtnPath)
    if tpBtn then Refs.TeleportBtn = tpBtn end
    return Refs.CapacitorPos ~= nil and Refs.GreenPlatePos ~= nil
end

-- ============ WEBHOOK ============
local function sendWebhook(reason)
    if CONFIG.WebhookURL == "" then return end
    local e = getEnergyValue()
    local elapsed = tick() - State.SessionStart
    local payload = {
        embeds = {{
            title = "⚡ PYC Report",
            description = "**"..reason.."**",
            color = 16766720,
            fields = {
                {name = "Plot", value = tostring(Refs.PlotNumber or "?"), inline = true},
                {name = "Session", value = string.format("%dm %ds", math.floor(elapsed/60), math.floor(elapsed%60)), inline = true},
                {name = "Energy", value = formatNumber(e), inline = true},
                {name = "Sells", value = tostring(State.TotalSells), inline = true},
                {name = "Sold", value = formatNumber(State.TotalEnergySold), inline = true},
            },
            footer = {text = "PYC v10 • "..os.date("%Y-%m-%d %H:%M:%S")}
        }}
    }
    httpRequest({
        Url = CONFIG.WebhookURL, Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode(payload),
    })
end

local function sendDiscordMessage(text)
    if CONFIG.WebhookURL == "" then return end
    httpRequest({
        Url = CONFIG.WebhookURL, Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({content = text}),
    })
end

-- ============ CLICK BUTTON ============
local function clickButton(btn)
    pcall(function() btn.Active = true; btn.Selectable = true end)
    local absPos, absSize = btn.AbsolutePosition, btn.AbsoluteSize
    local x, y = absPos.X + absSize.X/2, absPos.Y + absSize.Y/2
    pcall(function() VirtualUser:ClickButton1(Vector2.new(x, y)) end)
    task.wait(0.05)
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(x, y))
        task.wait(0.03)
        VirtualUser:Button1Up(Vector2.new(x, y))
    end)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    pcall(function() btn.MouseButton1Click:Fire() end)
    pcall(function()
        btn.MouseButton1Down:Fire()
        task.wait(0.02)
        btn.MouseButton1Up:Fire()
    end)
    pcall(function() if btn.Activated then btn.Activated:Fire() end end)
    if getconnections then
        pcall(function()
            for _, evt in ipairs({btn.MouseButton1Click, btn.Activated, btn.MouseButton1Down, btn.MouseButton1Up}) do
                if evt then
                    for _, conn in ipairs(getconnections(evt)) do
                        if conn and conn.Fire then pcall(function() conn:Fire() end) end
                    end
                end
            end
        end)
    end
    if firesignal then
        pcall(function()
            firesignal(btn.MouseButton1Click)
            if btn.Activated then firesignal(btn.Activated) end
        end)
    end
end

-- ============ OFFER GUI ============
local function getOfferGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local m = pg:FindFirstChild("Main")
    if not m then return nil end
    local f = m:FindFirstChild("Frames")
    if not f then return nil end
    return f:FindFirstChild("Offer")
end

local function isOfferVisible()
    local offer = getOfferGui()
    if not offer or not offer.Visible then return false end
    local p = offer.Parent
    while p and p ~= LocalPlayer do
        if p:IsA("GuiObject") and not p.Visible then return false end
        p = p.Parent
    end
    for _, v in ipairs(offer:GetDescendants()) do
        if (v:IsA("ImageButton") or v:IsA("TextButton")) and v.Name:lower() == "sell" then
            if not v.Visible then return false end
            if v.AbsoluteSize.X < 5 or v.AbsoluteSize.Y < 5 then return false end
            return true
        end
    end
    return false
end

local function findSellButton(offer)
    for _, v in ipairs(offer:GetDescendants()) do
        if (v:IsA("TextButton") or v:IsA("ImageButton")) and v.Name:lower() == CONFIG.PreferExactName:lower() then return v end
    end
    for _, v in ipairs(offer:GetDescendants()) do
        if (v:IsA("TextButton") or v:IsA("ImageButton")) and v.Name:lower():find("sell", 1, true) then return v end
    end
    return nil
end

-- ============ FARM ============
local function setFarmState(s)
    if State.FarmState ~= s then State.FarmState = s end
end

local function updateFarm()
    local hrp, humanoid = getChar()
    if not hrp then setFarmState("NO_CHAR") return end
    local pos = hrp.Position
    local capPos = Refs.CapacitorPos
    local greenPos = Refs.GreenPlatePos
    local timer = getTimerValue()
    local now = tick()
    
    if State.FarmState == "WAIT_BACK_TO_PLOT" then
        local elapsed = now - (State.BackToPlotTime or 0)
        local _, cp = detectPlot()
        if cp and tostring(cp) == tostring(State.PlotNum) then
            if capPos and (pos - capPos).Magnitude < 200 then
                setupRefs()
                State.FarmState = "IDLE"
                State.CheckStartTime = tick()
                State.GreenInjected = false
                return
            end
        end
        if elapsed > CONFIG.BackToPlotTimeout then setupRefs(); State.FarmState = "MOVING_TO_CAPACITOR" end
        return
    end
    
    if timer and timer <= CONFIG.TimerThreshold then
        if State.FarmState ~= "MOVING_TO_GREEN" and State.FarmState ~= "AT_GREEN" and State.FarmState ~= "RETURNING" and State.FarmState ~= "INJECT_GREEN_PLATE" then
            setFarmState("MOVING_TO_GREEN")
        end
    end
    
    if State.FarmState == "IDLE" then setFarmState("CHECK_TIMER")
    elseif State.FarmState == "CHECK_TIMER" then
        if timer then setFarmState("MOVING_TO_CAPACITOR")
        elseif tick() - State.CheckStartTime >= 5 then
            setFarmState(State.GreenInjected and "MOVING_TO_CAPACITOR" or "INJECT_GREEN_PLATE")
        end
    elseif State.FarmState == "INJECT_GREEN_PLATE" then
        if greenPos then
            walkTo(greenPos)
            if (pos - greenPos).Magnitude < CONFIG.GreenTolerance then
                State.GreenInjected = true
                task.wait(2)
                setFarmState("MOVING_TO_CAPACITOR")
            end
        else setFarmState("MOVING_TO_CAPACITOR") end
    elseif State.FarmState == "MOVING_TO_CAPACITOR" then
        if capPos then
            walkTo(capPos)
            if (pos - capPos).Magnitude < CONFIG.CapacitorTolerance then
                setFarmState("AT_CAPACITOR")
                State.SpamCount = 0
                State.LastSpamTime = 0
                State.FallbackCycleStart = tick()
            end
        end
    elseif State.FarmState == "AT_CAPACITOR" then
        if State.SpamCount == 0 and State.LastSpamTime == 0 then State.LastSpamTime = now end
        if now - State.LastSpamTime >= CONFIG.SpamInterval then
            spamKey(CONFIG.SpamKey)
            State.LastSpamTime = now
            State.SpamCount = State.SpamCount + 1
        end
        if capPos and (pos - capPos).Magnitude > CONFIG.CapacitorTolerance + 3 then walkTo(capPos) end
    elseif State.FarmState == "MOVING_TO_GREEN" then
        if greenPos then
            walkTo(greenPos)
            if (pos - greenPos).Magnitude < CONFIG.GreenTolerance then
                setFarmState("AT_GREEN")
                State.LastGreenEnter = tick()
            end
        end
    elseif State.FarmState == "AT_GREEN" then
        if tick() - State.LastGreenEnter >= CONFIG.StayAtGreenTime then
            setFarmState("RETURNING")
            State.SpamCount = 0
            State.LastSpamTime = 0
        end
    elseif State.FarmState == "RETURNING" then
        if capPos then
            walkTo(capPos)
            if (pos - capPos).Magnitude < CONFIG.CapacitorTolerance then
                setFarmState("AT_CAPACITOR")
                State.SpamCount = 0
                State.LastSpamTime = 0
                State.FallbackCycleStart = tick()
            end
        end
    end
end

-- ============ SELL ============
local function setSellState(s)
    if State.SellState ~= s then
        State.SellState = s
        if s == "WAIT_SELL" then State.OfferVisibleSince = tick() end
        if s == "STAY_AT_WAYPOINT" then State.StayStartTime = tick() end
        if s == "GET_CAUGHT" then State.GetCaughtTime = tick() end
        if s == "RETRY_CHASE" then State.StartTime = tick() end
    end
end

local function finishSell()
    State.TotalSells = State.TotalSells + 1
    State.SellRetryCount = 0
    local e = getEnergyValue()
    if e and State.EnergyBeforeSell then
        local sold = State.EnergyBeforeSell - e
        if sold > 0 then State.TotalEnergySold = State.TotalEnergySold + sold end
    end
    State.EnergyBeforeSell = nil
    if CONFIG.AutoReportOnSell then sendWebhook("Sell #"..State.TotalSells) end
    CONFIG.SellMode = false
    State.Mode = "FARM"
    State.SellState = "IDLE"
    State.FarmState = "WAIT_BACK_TO_PLOT"
    State.GreenInjected = false
    State.BackToPlotTime = tick()
    updateUI()
end

local function updateSell()
    if isOfferVisible() and State.SellState ~= "WAIT_SELL" and State.SellState ~= "POST_SELL" then
        setSellState("WAIT_SELL")
    end
    local hrp, humanoid = getChar()
    if not hrp then return end
    local pos = hrp.Position
    
    if State.SellState == "IDLE" then setSellState("CLICK_TELEPORT")
    elseif State.SellState == "CLICK_TELEPORT" then
        if Refs.TeleportBtn then clickButton(Refs.TeleportBtn); setSellState("WAIT_TELEPORT")
        else finishSell() end
    elseif State.SellState == "WAIT_TELEPORT" then
        task.wait(CONFIG.TeleportWaitTime)
        local h2 = getChar()
        if h2 then State.PosBeforeChase = h2.Position end
        State.StartTime = tick()
        setSellState("WAIT_CHASE_TRIGGER")
    elseif State.SellState == "WAIT_CHASE_TRIGGER" or State.SellState == "RETRY_CHASE" then
        local elapsed = tick() - State.StartTime
        local moved = State.PosBeforeChase and (pos - State.PosBeforeChase).Magnitude > 50
        local sell = Workspace:FindFirstChild("Sell")
        if sell and State.PlotNum then
            local map = sell:FindFirstChild("Map")
            if map then
                local mf = map:FindFirstChild(tostring(State.PlotNum))
                if mf then
                    local cs = mf:FindFirstChild("CharSpawn")
                    if cs and (pos - cs.Position).Magnitude < 30 then moved = true end
                end
            end
        end
        if moved then setSellState("TELEPORT_TO_WAYPOINT"); return end
        if Refs.SellZone then walkTo(Refs.SellZone.Position) end
        if elapsed > CONFIG.ChaseTriggerTimeout then setSellState("TELEPORT_TO_WAYPOINT") end
    elseif State.SellState == "TELEPORT_TO_WAYPOINT" then
        if CONFIG.UseTeleport then teleportTo(CONFIG.MultiplierWaypoint)
        else setSpeed(100); walkTo(CONFIG.MultiplierWaypoint) end
        setSellState("STAY_AT_WAYPOINT")
    elseif State.SellState == "STAY_AT_WAYPOINT" then
        if humanoid then humanoid:Move(Vector3.zero) end
        setSpeed(16)
        if tick() - State.StayStartTime >= CONFIG.StayAtWaypoint then setSellState("GET_CAUGHT") end
    elseif State.SellState == "GET_CAUGHT" then
        if humanoid then humanoid:Move(Vector3.zero) end
        if tick() - State.GetCaughtTime > CONFIG.GetCaughtTimeout then
            State.SellRetryCount = State.SellRetryCount + 1
            if State.SellRetryCount <= CONFIG.MaxSellRetries then
                local h2 = getChar()
                if h2 then State.PosBeforeChase = h2.Position end
                setSellState("RETRY_CHASE")
            else State.SellRetryCount = 0; finishSell() end
        end
    elseif State.SellState == "WAIT_SELL" then
        if not isOfferVisible() then
            if State.LoggedButtons then finishSell() end
            return
        end
        State.LoggedButtons = true
        if tick() - State.OfferVisibleSince < CONFIG.OfferDetectDelay then return end
        local offer = getOfferGui()
        if not offer then return end
        local targetBtn = findSellButton(offer)
        if targetBtn then clickButton(targetBtn); setSellState("POST_SELL") end
    elseif State.SellState == "POST_SELL" then
        task.wait(CONFIG.PostClickDelay)
        if not isOfferVisible() then finishSell() else setSellState("WAIT_SELL") end
    end
end

-- ============ DISCORD POLLING ============
local function getDiscordMessages()
    if CONFIG.BotToken == "" or CONFIG.ChannelID == "" then return nil end
    local url = "https://discord.com/api/v10/channels/"..CONFIG.ChannelID.."/messages?limit=5"
    local res = httpRequest({
        Url = url, Method = "GET",
        Headers = {
            ["Authorization"] = "Bot "..CONFIG.BotToken,
            ["Content-Type"] = "application/json",
        },
    })
    if not res or not res.Body then State.DiscordStatus = "Error"; return nil end
    State.DiscordStatus = "OK"
    local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function handleCommand(content, authorID)
    if CONFIG.AuthorizedUserID ~= "" and tostring(authorID) ~= tostring(CONFIG.AuthorizedUserID) then return end
    content = content:lower():gsub("^%s+", ""):gsub("%s+$", "")
    
    if content == "!sell" then
        if not CONFIG.Enabled then sendDiscordMessage("⚠️ Farm belum ON."); return end
        if State.Mode == "SELL" then sendDiscordMessage("⚠️ Sell mode aktif."); return end
        State.SellRetryCount = 0
        State.EnergyBeforeSell = getEnergyValue()
        CONFIG.SellMode = true
        State.Mode = "SELL"
        State.SellState = "IDLE"
        updateUI()
        sendDiscordMessage("💰 Sell mode aktif! Energy: "..formatNumber(State.EnergyBeforeSell))
    elseif content == "!farm on" then
        CONFIG.Enabled = true
        State.Mode = "FARM"
        toggleBtn.Text = "🟢 ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
        setupRefs()
        State.FarmState = "IDLE"
        State.GreenInjected = false
        updateUI()
        sendDiscordMessage("✅ Auto-farm ON")
    elseif content == "!farm off" then
        CONFIG.Enabled = false
        CONFIG.SellMode = false
        State.Mode = "IDLE"
        State.FarmState = "IDLE"
        State.SellState = "IDLE"
        toggleBtn.Text = "⚪ OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        updateUI()
        sendDiscordMessage("⏹️ Auto-farm OFF")
    elseif content == "!status" then
        sendDiscordMessage("📊 Mode: "..State.Mode.." | Farm: "..State.FarmState.." | Sell: "..State.SellState.." | Energy: "..formatNumber(getEnergyValue()).." | Money: $"..formatNumber(getMoneyValue()).." | Sells: "..State.TotalSells)
    elseif content == "!help" then
        sendDiscordMessage("**Commands:** `!farm on` `!farm off` `!sell` `!status` `!help`")
    end
end

task.spawn(function()
    while screenGui.Parent do
        task.wait(CONFIG.PollInterval)
        pcall(function()
            if CONFIG.BotToken ~= "" and CONFIG.ChannelID ~= "" then
                local messages = getDiscordMessages()
                if messages and #messages > 0 then
                    local newest = messages[1]
                    if newest and newest.id and newest.id ~= State.LastMessageID then
                        State.LastMessageID = newest.id
                        if newest.author and not newest.author.bot and newest.content then
                            handleCommand(newest.content, newest.author.id)
                        end
                    end
                end
            end
        end)
    end
end)

-- ============ UI ============
function updateUI()
    if State.Mode == "FARM" then
        stateLbl.Text = "Mode: FARM | "..State.FarmState
        stateLbl.TextColor3 = Color3.fromRGB(120, 220, 160)
    elseif State.Mode == "SELL" then
        stateLbl.Text = "Mode: SELL | "..State.SellState.." | Retry "..State.SellRetryCount.."/"..CONFIG.MaxSellRetries
        stateLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
    else
        stateLbl.Text = "Mode: IDLE"
        stateLbl.TextColor3 = Color3.fromRGB(150, 150, 180)
    end
end

local function updateGraph()
    if #EnergyHistory > MAX_HISTORY then table.remove(EnergyHistory, 1) end
    for _, c in ipairs(graphBars:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    if #EnergyHistory < 2 then return end
    local maxRate = 1
    for _, v in ipairs(EnergyHistory) do if math.abs(v) > maxRate then maxRate = math.abs(v) end end
    local barWidth = graphCanvas.AbsoluteSize.X / MAX_HISTORY
    for i, v in ipairs(EnergyHistory) do
        local bar = Instance.new("Frame")
        bar.BackgroundColor3 = v >= 0 and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(220, 100, 100)
        bar.BorderSizePixel = 0
        bar.LayoutOrder = i
        local h = math.clamp(math.abs(v) / maxRate, 0.05, 1) * graphCanvas.AbsoluteSize.Y
        bar.Size = UDim2.new(0, math.max(1, barWidth - 1), 0, h)
        bar.Parent = graphBars
    end
end

task.spawn(function()
    while screenGui.Parent do
        local f, s = 0, tick()
        while tick() - s < 1 do RunService.RenderStepped:Wait(); f = f + 1 end
        State.FPS = f
    end
end)

task.spawn(function()
    while screenGui.Parent do
        task.wait(3)
        local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        State.Ping = ok and math.floor(ping) or 0
    end
end)

local lastEnergy, lastEnergyT = 0, 0
task.spawn(function()
    while screenGui.Parent do
        task.wait(1)
        local e = getEnergyValue()
        if e and lastEnergyT > 0 then
            local dt = tick() - lastEnergyT
            if dt > 0 then table.insert(EnergyHistory, (e - lastEnergy) / dt); updateGraph() end
        end
        lastEnergy = e or 0
        lastEnergyT = tick()
    end
end)

task.spawn(function()
    while screenGui.Parent do
        task.wait(0.05)
        updateUI()
        statCells.money.Text = "💰 Money: $"..formatNumber(getMoneyValue())
        statCells.energy.Text = "⚡ Energy: "..formatNumber(getEnergyValue())
        statCells.discord.Text = "🤖 Discord: "..State.DiscordStatus
        statCells.ping.Text = "📡 Ping: "..State.Ping.."ms"
        statCells.fps.Text = "🎮 FPS: "..State.FPS
        statCells.retry.Text = "🔁 Retry: "..State.SellRetryCount.."/"..CONFIG.MaxSellRetries
        statCells.sold.Text = "📦 Sold: "..formatNumber(State.TotalEnergySold)
        local timer = getTimerValue()
        statCells.barrier.Text = "🛡️ Barrier: "..(timer and (timer.."s") or "-")
        if CONFIG.Enabled then
            if CONFIG.SellMode then updateSell()
            else State.Mode = "FARM"; updateFarm() end
        end
    end
end)

-- ============ BUTTONS ============
toggleBtn.MouseButton1Click:Connect(function()
    CONFIG.Enabled = not CONFIG.Enabled
    if CONFIG.Enabled then
        toggleBtn.Text = "🟢 ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 60)
        local ok = setupRefs()
        if not ok then
            CONFIG.Enabled = false
            toggleBtn.Text = "⚪ OFF"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        else
            State.Mode = "FARM"
            State.FarmState = "IDLE"
            State.GreenInjected = false
        end
    else
        toggleBtn.Text = "⚪ OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        State.Mode = "IDLE"
        State.FarmState = "IDLE"
        State.SellState = "IDLE"
    end
    updateUI()
end)

optimizeBtn.MouseButton1Click:Connect(function()
    if tick() - State.LastOptimizeTime < 2 then return end
    State.LastOptimizeTime = tick()
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
        for _, v in ipairs(Workspace:GetDescendants()) do
            pcall(function()
                if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then v.Enabled = false end
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
                if v:IsA("BasePart") and v.Material ~= Enum.Material.SmoothPlastic then v.Material = Enum.Material.SmoothPlastic end
                if v:IsA("Light") then v.Enabled = false end
                if v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") then v:Destroy() end
                if v:IsA("Accessory") or v:IsA("Hat") then v:Destroy() end
                if v:IsA("Sound") then v.Playing = false end
            end)
        end
        local L = game:GetService("Lighting")
        L.GlobalShadows = false
        L.Brightness = 0
        L.Ambient = Color3.new(0, 0, 0)
        L.OutdoorAmbient = Color3.new(0, 0, 0)
        L.FogEnd = 100
    end)
    optimizeBtn.Text = "✓ Optimized"
    task.delay(2, function() if optimizeBtn.Parent then optimizeBtn.Text = "⚙ Optimize" end end)
end)

closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)

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
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
end)

updateUI()
