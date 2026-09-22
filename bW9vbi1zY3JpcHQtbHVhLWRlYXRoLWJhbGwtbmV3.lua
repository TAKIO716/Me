local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
	Title = "Moon",
	Footer = "version: for_jamalkun",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main = Window:AddTab("Main", "user"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

local LeftGroupBox = Tabs.Main:AddGroupbox({
	Side = "Left",
	Name = "Controls",
	Description = "Main Settings",
	IconName = "boxes",
})

local AutoReadyEnabled = false
local AIMoveEnabled = false
local FollowBallEnabled = false

LeftGroupBox:AddToggle("AutoReady", {
	Text = "Auto Ready",
	Default = false,
	Callback = function(Value)
		AutoReadyEnabled = Value
	end
})

LeftGroupBox:AddToggle("AIMove", {
	Text = "Ai move",
	Default = false,
	Callback = function(Value)
		AIMoveEnabled = Value
	end
})

LeftGroupBox:AddToggle("FollowBall", {
	Text = "Follow ball",
	Default = false,
	Callback = function(Value)
		FollowBallEnabled = Value
	end
})

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

local PathController = {
	Active = false,
	TargetPosition = nil,
	Waypoints = {},
	CurrentWaypointIndex = 1,
	LastComputeTime = 0,
	Thread = nil
}

local function stopPath()
	PathController.Active = false
	PathController.TargetPosition = nil
	PathController.Waypoints = {}
	PathController.CurrentWaypointIndex = 1
	if PathController.Thread then
		task.cancel(PathController.Thread)
		PathController.Thread = nil
	end
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end
end

local function walkTo(targetPos)
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	PathController.Active = true
	local distToTarget = PathController.TargetPosition and (PathController.TargetPosition - targetPos).Magnitude or math.huge
	local now = os.clock()

	if distToTarget > 4 or (now - PathController.LastComputeTime > 1.5) then
		PathController.TargetPosition = targetPos
		PathController.LastComputeTime = now

		if PathController.Thread then
			task.cancel(PathController.Thread)
			PathController.Thread = nil
		end

		PathController.Thread = task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = 2.0,
				AgentHeight = 5.0,
				AgentCanJump = true,
			})
			
			local success, err = pcall(function()
				path:ComputeAsync(hrp.Position, targetPos)
			end)

			if success and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				PathController.Waypoints = waypoints
				
				for i = 2, #waypoints do
					local wp = waypoints[i]
					if not PathController.Active then break end
					
					humanoid:MoveTo(wp.Position)
					
					if wp.Action == Enum.PathWaypointAction.Jump then
						humanoid.Jump = true
					end

					local reached = false
					local connection
					connection = humanoid.MoveToFinished:Connect(function()
						reached = true
						if connection then connection:Disconnect() end
					end)

					local wpStart = os.clock()
					while not reached do
						task.wait()
						if os.clock() - wpStart > 1.5 then
							if connection then connection:Disconnect() end
							break
						end
						if PathController.TargetPosition ~= targetPos or not PathController.Active then
							if connection then connection:Disconnect() end
							return
						end
					end
				end
			else
				humanoid:MoveTo(targetPos)
			end
		end)
	end
end

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
						if PathController.Active then
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
			local hud = LocalPlayer.PlayerGui:FindFirstChild("HUD")
			local healthBar = hud and hud:FindFirstChild("HealthBar")
			if healthBar and healthBar.Visible then
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
			if not AutoReadyEnabled and PathController.Active then
				stopPath()
			end
		end
	end
end)

local MenuGroup = Tabs["UI Settings"]:AddGroupbox({
	Side = "Left",
	Name = "Menu",
	IconName = "wrench"
})

MenuGroup:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame.Visible,
	Text = "Open Keybind Menu",
	Callback = function(value)
		Library.KeybindFrame.Visible = value
	end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
	Text = "Custom Cursor",
	Default = Library.ShowCustomCursor,
	Callback = function(Value)
		Library.ShowCustomCursor = Value
	end,
})

MenuGroup:AddToggle("AlwaysOnTop", {
	Text = "Always On Top",
	Default = Window.AlwaysOnTop,
	Callback = function(Value)
		Window:SetAlwaysOnTop(Value)
	end,
})

MenuGroup:AddDropdown("NotificationSide", {
	Values = { "Left", "Right" },
	Default = "Right",
	Text = "Notification Side",
	Callback = function(Value)
		Library:SetNotifySide(Value)
	end,
})

MenuGroup:AddDropdown("DPIDropdown", {
	Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
	Default = "100%",
	Text = "DPI Scale",
	Callback = function(Value)
		Value = Value:gsub("%%", "")
		local DPI = tonumber(Value)
		Library:SetDPIScale(DPI)
	end,
})

MenuGroup:AddSlider("UICornerSlider", {
	Text = "Corner Radius",
	Default = Library.CornerRadius,
	Min = 0,
	Max = 20,
	Rounding = 0,
	Callback = function(value)
		Window:SetCornerRadius(value)
	end
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
	:AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("Moon")
SaveManager:SetFolder("Moon/deathball")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()
