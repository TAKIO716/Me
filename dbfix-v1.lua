-- ============================================
-- DEBUG CONSOLE OVERLAY v1.0
-- Overlay buat liat output print/warn/error
-- Fitur: Copy, Clear, Minimize, Drag, Close
-- ============================================
local DebugConsole = (function()
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local LogService = game:GetService("LogService")
    local LocalPlayer = Players.LocalPlayer

    -- Parent GUI (support gethui biar di atas game UI)
    local parentGui
    if gethui then
        local ok, result = pcall(gethui)
        if ok and result then parentGui = result end
    end
    if not parentGui then
        parentGui = LocalPlayer:WaitForChild("PlayerGui")
    end

    -- Cleanup existing
    local existing = parentGui:FindFirstChild("LanzDebugConsole")
    if existing then existing:Destroy() end

    -- ScreenGui
    local screen = Instance.new("ScreenGui")
    screen.Name = "LanzDebugConsole"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 99999
    screen.Parent = parentGui

    -- Main frame
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 520, 0, 320)
    main.Position = UDim2.new(0.5, -260, 0, 15)
    main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screen

    local corner = Instance.new("UICorner", main)
    corner.CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(90, 90, 140)
    stroke.Thickness = 1.5

    -- Title bar
    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
    title.BorderSizePixel = 0
    title.Parent = main
    local titleCorner = Instance.new("UICorner", title)
    titleCorner.CornerRadius = UDim.new(0, 8)

    -- Cover bottom curve
    local titleCover = Instance.new("Frame")
    titleCover.Size = UDim2.new(1, 0, 0, 8)
    titleCover.Position = UDim2.new(0, 0, 1, -8)
    titleCover.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
    titleCover.BorderSizePixel = 0
    titleCover.Parent = title

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -240, 1, 0)
    titleLbl.Position = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "Debug Console"
    titleLbl.TextColor3 = Color3.fromRGB(180, 180, 255)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.Parent = title

    -- Log state
    local logText = ""
    local lines = {}
    local MAX_LINES = 300

    -- Scroll
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -10, 1, -40)
    scroll.Position = UDim2.new(0, 5, 0, 35)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 180)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local logLbl = Instance.new("TextLabel")
    logLbl.Size = UDim2.new(1, -8, 0, 0)
    logLbl.Position = UDim2.new(0, 4, 0, 0)
    logLbl.BackgroundTransparency = 1
    logLbl.Text = ""
    logLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    logLbl.TextXAlignment = Enum.TextXAlignment.Left
    logLbl.TextYAlignment = Enum.TextYAlignment.Top
    logLbl.Font = Enum.Font.Code
    logLbl.TextSize = 11
    logLbl.TextWrapped = true
    logLbl.AutomaticSize = Enum.AutomaticSize.Y
    logLbl.Parent = scroll

    local function append(text)
        table.insert(lines, tostring(text))
        while #lines > MAX_LINES do
            table.remove(lines, 1)
        end
        logText = table.concat(lines, "\n")
        logLbl.Text = logText
        task.defer(function()
            scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
        end)
    end

    -- Button factory
    local function makeBtn(text, xOff, bgColor, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 55, 0, 22)
        btn.Position = UDim2.new(1, xOff, 0.5, -11)
        btn.BackgroundColor3 = bgColor
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = title
        local c = Instance.new("UICorner", btn)
        c.CornerRadius = UDim.new(0, 4)
        btn.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then append("[ERR] Button: " .. tostring(err)) end
        end)
        return btn
    end

    -- COPY
    makeBtn("COPY", -190, Color3.fromRGB(45, 90, 160), function()
        if setclipboard then
            setclipboard(logText)
            titleLbl.Text = "Copied!"
        elseif syn and syn.write_clipboard then
            syn.write_clipboard(logText)
            titleLbl.Text = "Copied!"
        else
            titleLbl.Text = "No clipboard"
        end
        task.delay(1.2, function()
            titleLbl.Text = "Debug Console"
        end)
    end)

    -- CLEAR
    makeBtn("CLEAR", -130, Color3.fromRGB(160, 70, 40), function()
        lines = {}
        logText = ""
        logLbl.Text = ""
        append("[SYS] Cleared at " .. os.date("%H:%M:%S"))
    end)

    -- MINIMIZE
    local isMin = false
    makeBtn("_", -70, Color3.fromRGB(60, 60, 80), function()
        isMin = not isMin
        if isMin then
            main.Size = UDim2.new(0, 520, 0, 30)
        else
            main.Size = UDim2.new(0, 520, 0, 320)
        end
    end)

    -- CLOSE
    makeBtn("X", -12, Color3.fromRGB(170, 45, 45), function()
        screen:Destroy()
    end)

    -- Drag
    local dragging = false
    local dragStart, startPos

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
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Hook LogService (capture print, warn, error)
    LogService.MessageOut:Connect(function(msg, msgType)
        local prefix = "[OUT] "
        if msgType == Enum.MessageType.MessageError then
            prefix = "[ERR] "
        elseif msgType == Enum.MessageType.MessageWarning then
            prefix = "[WRN] "
        elseif msgType == Enum.MessageType.MessageInfo then
            prefix = "[INF] "
        end
        append(prefix .. msg)
    end)

    append("[SYS] Debug Console initialized")
    append("[SYS] Waiting for output...")

    -- API
    return {
        Log = append,
        Clear = function()
            lines = {}
            logText = ""
            logLbl.Text = ""
        end,
        Destroy = function() screen:Destroy() end,
        Show = function() screen.Enabled = true end,
        Hide = function() screen.Enabled = false end,
    }
end)()

-- Expose ke getgenv
if getgenv then
    getgenv().DebugConsole = DebugConsole
end

DebugConsole.Log("[TEST] Debug Console loaded successfully")


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ============================================
-- MOVEMENT — pakai humanoid:Move() loop
-- (ganti hook PlayerModule yang gak support)
-- ============================================
local autoMoveDirection = Vector3.zero

RunService.Heartbeat:Connect(function()
    if autoMoveDirection.Magnitude > 0 then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:Move(autoMoveDirection, false)
        end
    end
end)


local CONFIG_FILE = "Jamalkin.json"

local Config = {
	AutoReady = false,
	AIMove = false,
	FollowBall = false,
}

local function saveConfig()
	if not writefile then return end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(Config)
	end)
	if ok and encoded then
		pcall(writefile, CONFIG_FILE, encoded)
	end
end

local function loadConfig()
	if not readfile or not isfile then return end
	local okExists, exists = pcall(isfile, CONFIG_FILE)
	if not okExists or not exists then return end
	local okRead, content = pcall(readfile, CONFIG_FILE)
	if not okRead or not content or content == "" then return end
	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if okDecode and type(decoded) == "table" then
		for k, v in pairs(decoded) do
			if Config[k] ~= nil then
				Config[k] = v
			end
		end
	end
end

loadConfig()

local parentGui
if gethui then
	local ok, result = pcall(gethui)
	if ok and result then
		parentGui = result
	end
end
if not parentGui then
	parentGui = LocalPlayer:WaitForChild("PlayerGui")
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MoonGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 9999
screenGui.Parent = parentGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 280, 0, 420)
main.Position = UDim2.new(0.5, -140, 0.5, -210)
main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
main.BackgroundTransparency = 0.5
main.BorderSizePixel = 0
main.Active = true
main.Parent = screenGui

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
titleBar.BackgroundTransparency = 0.3
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -110, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Moon"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -32, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.BackgroundTransparency = 0.3
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 26, 0, 26)
minimizeBtn.Position = UDim2.new(1, -62, 0, 3)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
minimizeBtn.BackgroundTransparency = 0.3
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "-"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 16
minimizeBtn.Parent = titleBar

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Content"
scroll.Size = UDim2.new(1, 0, 1, -40)
scroll.Position = UDim2.new(0, 0, 0, 36)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(160, 160, 160)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = scroll

local reopenBtn = Instance.new("TextButton")
reopenBtn.Name = "ReopenBtn"
reopenBtn.Size = UDim2.new(0, 42, 0, 42)
reopenBtn.Position = UDim2.new(0, 12, 0, 12)
reopenBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
reopenBtn.BackgroundTransparency = 0.5
reopenBtn.BorderSizePixel = 0
reopenBtn.Text = "M"
reopenBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
reopenBtn.Font = Enum.Font.GothamBold
reopenBtn.TextSize = 16
reopenBtn.Visible = false
reopenBtn.Active = true
reopenBtn.Parent = screenGui

local function createSection(text)
	local section = Instance.new("TextLabel")
	section.Size = UDim2.new(1, 0, 0, 22)
	section.BackgroundTransparency = 1
	section.Text = text
	section.TextColor3 = Color3.fromRGB(220, 220, 220)
	section.TextXAlignment = Enum.TextXAlignment.Left
	section.Font = Enum.Font.GothamBold
	section.TextSize = 12
	section.Parent = scroll
	return section
end

local function createToggle(key, text, default, callback)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 32)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = scroll

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 44, 0, 22)
	btn.Position = UDim2.new(1, -52, 0.5, -11)
	btn.BackgroundColor3 = default and Color3.fromRGB(50, 160, 60) or Color3.fromRGB(50, 50, 50)
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.Parent = frame

	local indicator = Instance.new("Frame")
	indicator.Size = UDim2.new(0, 18, 0, 18)
	indicator.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
	indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	indicator.BorderSizePixel = 0
	indicator.Parent = btn

	local state = default

	local function render()
		btn.BackgroundColor3 = state and Color3.fromRGB(50, 160, 60) or Color3.fromRGB(50, 50, 50)
		indicator.Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
	end

	render()
	callback(state)

	btn.MouseButton1Click:Connect(function()
		state = not state
		if key then
			Config[key] = state
			saveConfig()
		end
		render()
		callback(state)
	end)

	return {
		Set = function(value)
			state = value
			if key then
				Config[key] = state
				saveConfig()
			end
			render()
			callback(state)
		end,
		Get = function()
			return state
		end
	}
end

local function createButton(text, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.Parent = scroll
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local function createLabel(text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 24)
	lbl.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	lbl.BackgroundTransparency = 0.25
	lbl.BorderSizePixel = 0
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.Parent = scroll
	return lbl
end

local dragging = false
local dragStart, startPos
local activeDragTarget = nil

local function makeDraggable(handle, target)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			activeDragTarget = target
			dragStart = input.Position
			startPos = target.Position
		end
	end)
end

makeDraggable(titleBar, main)
makeDraggable(reopenBtn, reopenBtn)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		if activeDragTarget then
			activeDragTarget.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		activeDragTarget = nil
	end
end)

local originalSize = main.Size
local minimized = false

minimizeBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	main.Size = minimized and UDim2.new(0, 280, 0, 32) or originalSize
	scroll.Visible = not minimized
end)

closeBtn.MouseButton1Click:Connect(function()
	main.Visible = false
	reopenBtn.Visible = true
end)

reopenBtn.MouseButton1Click:Connect(function()
	main.Visible = true
	reopenBtn.Visible = false
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		main.Visible = not main.Visible
		reopenBtn.Visible = not main.Visible
	end
end)

local AutoReadyEnabled = Config.AutoReady
local AIMoveEnabled = Config.AIMove
local FollowBallEnabled = Config.FollowBall

createSection("Controls")
createToggle("AutoReady", "Auto Ready", Config.AutoReady, function(v) AutoReadyEnabled = v end)
createToggle("AIMove", "Ai move", Config.AIMove, function(v) AIMoveEnabled = v end)
createToggle("FollowBall", "Follow ball", Config.FollowBall, function(v) FollowBallEnabled = v end)

createSection("Menu")
createLabel("Menu keybind: RightShift")
createButton("Unload", function()
	saveConfig()
	screenGui:Destroy()
end)

local function isHealthBarVisible()
	local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pGui then return false end
	local hud = pGui:FindFirstChild("HUD")
	if not hud then return false end

	local direct = hud:FindFirstChild("HealthBar")
	if direct and direct.Visible then
		return true
	end

	local holder = hud:FindFirstChild("HolderBottom")
	if holder then
		local nested = holder:FindFirstChild("HealthBar")
		if nested and nested.Visible then
			return true
		end
	end

	return false
end

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

local walkTarget = nil

local function stopPath()
	walkTarget = nil
	autoMoveDirection = Vector3.zero
end

local function walkTo(targetPos)
	walkTarget = targetPos
end

RunService.Heartbeat:Connect(function()
	if not walkTarget then
		autoMoveDirection = Vector3.zero
		return
	end

	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		autoMoveDirection = Vector3.zero
		return
	end

	local toTarget = walkTarget - hrp.Position
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude < 2 then
		autoMoveDirection = Vector3.zero
		return
	end

	autoMoveDirection = flat.Unit
end)

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
			if isHealthBarVisible() then
				local char = LocalPlayer.Character
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if char and humanoid and hrp then
					local now = os.clock()

					if FollowBallEnabled then
						local targetBall = nil
						local minDist = math.huge
						for _, entry in pairs(balls) do
							local dist = (entry.position - hrp.Position).Magnitude
							if dist < minDist then
								minDist = dist
								targetBall = entry
							end
						end
						if targetBall then
							walkTo(targetBall.position)
						else
							stopPath()
						end
					elseif AIMoveEnabled then
						if not isPlayerThreatened() and now - aiLastQ > 0.5 then
							VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
							VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
							aiLastQ = now
						end

						if aiActiveTarget then
							local targetChar = aiActiveTarget
							if not PlayerData[aiActiveTarget] or not PlayerData[aiActiveTarget].isBot then
								targetChar = aiActiveTarget.Character
							end

							local currentHp = getPlayerHP({Character = targetChar})
							if (currentHp and currentHp <= 0) or not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then
								aiActiveTarget = nil
							end
						end

						if aiActiveTarget and now - aiAcquiredTime > 20 then
							local pName = PlayerData[aiActiveTarget] and PlayerData[aiActiveTarget].name or aiActiveTarget.Name
							getgenv().AITargets[pName] = { blacklistedUntil = now + 60 }
							aiActiveTarget = nil
						end

						if not aiActiveTarget then
							aiActiveTarget = getNewAITarget()
							if aiActiveTarget then
								aiAcquiredTime = now
							end
						end

						local activeTargetChar = aiActiveTarget
						if aiActiveTarget and (not PlayerData[aiActiveTarget] or not PlayerData[aiActiveTarget].isBot) then
							activeTargetChar = aiActiveTarget.Character
						end

						if activeTargetChar and activeTargetChar:FindFirstChild("HumanoidRootPart") then
							local targetHrp = activeTargetChar.HumanoidRootPart
							local toTarget = targetHrp.Position - hrp.Position
							local dist = toTarget.Magnitude

							local desiredPos
							if dist > 12 then
								local dir = toTarget.Unit
								desiredPos = targetHrp.Position - (dir * 10)
							elseif dist < 8 then
								local dir = (hrp.Position - targetHrp.Position).Unit
								desiredPos = hrp.Position + (dir * 6)
							else
								if not aiWanderTarget or now - aiLastWanderChoice > 3 then
									local angle = math.random() * math.pi * 2
									aiWanderTarget = targetHrp.Position + Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
									aiLastWanderChoice = now
								end
								desiredPos = aiWanderTarget
							end
							walkTo(desiredPos)
						else
							if not aiWanderTarget or now - aiLastWanderChoice > 4 then
								local rx = (math.random() - 0.5) * 60
								local rz = (math.random() - 0.5) * 60
								aiWanderTarget = hrp.Position + Vector3.new(rx, 0, rz)
								aiLastWanderChoice = now
							end
							walkTo(aiWanderTarget)
						end

						if now - aiLastJump > 2.5 and math.random(1, 10) == 1 then
							humanoid.Jump = true
							aiLastJump = now
							if math.random(1, 2) == 1 then
								task.delay(0.25, function()
									if humanoid and humanoid.Parent then
										humanoid.Jump = true
									end
								end)
							end
						end
					end
				end
			end
		else
			if not AutoReadyEnabled and walkTarget then
				stopPath()
			end
		end
	end
end)
