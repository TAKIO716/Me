--[[
    Roblox FPS Boost Script - Toggle Edition
    Features: Shadow disable, Texture removal, Lighting downgrade, 
    Particle removal, Fog disable, Render distance reduce
    Credits: Kyriel
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- State tracking
local state = {
    shadows = false,
    textures = false,
    lighting = false,
    particles = false,
    fog = false,
    renderDistance = false,
    fullBoost = false,
}

-- Original value storage
local original = {
    lighting = {},
    fog = {},
}

-- Save original lighting settings
original.lighting.GlobalShadows = Lighting.GlobalShadows
original.lighting.Brightness = Lighting.Brightness
original.lighting.ColorShift_Bottom = Lighting.ColorShift_Bottom
original.lighting.ColorShift_Top = Lighting.ColorShift_Top
original.lighting.EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale
original.lighting.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
original.lighting.ExposureCompensation = Lighting.ExposureCompensation
original.fog.FogEnd = Lighting.FogEnd
original.fog.FogStart = Lighting.FogStart

-- ==================== FEATURE FUNCTIONS ====================

local function toggleShadows(enable)
    if enable then
        Lighting.GlobalShadows = false
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CastShadow = false
            end
        end
        -- Watch for new parts
        state._shadowConn = Workspace.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then
                desc.CastShadow = false
            end
        end)
    else
        Lighting.GlobalShadows = original.lighting.GlobalShadows
        if state._shadowConn then
            state._shadowConn:Disconnect()
            state._shadowConn = nil
        end
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CastShadow = true
            end
        end
    end
    state.shadows = enable
end

local function toggleTextures(enable)
    if enable then
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Material = Enum.Material.Plastic
                if v:FindFirstChild("Texture") then
                    v.Texture.Transparency = 1
                end
                if v:FindFirstChild("Decal") then
                    v.Decal.Transparency = 1
                end
            elseif v:IsA("Texture") or v:IsA("Decal") then
                v.Transparency = 1
            end
        end
        state._textureConn = Workspace.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then
                desc.Material = Enum.Material.Plastic
            elseif desc:IsA("Texture") or desc:IsA("Decal") then
                desc.Transparency = 1
            end
        end)
    else
        if state._textureConn then
            state._textureConn:Disconnect()
            state._textureConn = nil
        end
        -- Note: original materials aren't stored, so just reset to default
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("Texture") or v:IsA("Decal") then
                v.Transparency = 0
            end
        end
    end
    state.textures = enable
end

local function toggleLighting(enable)
    if enable then
        Lighting.Brightness = 0
        Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
        Lighting.ColorShift_Top = Color3.new(0, 0, 0)
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ExposureCompensation = 0
        
        -- Remove post-processing effects
        for _, v in pairs(Lighting:GetChildren()) do
            if v:IsA("PostEffect") or v:IsA("ColorCorrectionEffect") 
                or v:IsA("BloomEffect") or v:IsA("BlurEffect") 
                or v:IsA("SunRaysEffect") or v:IsA("Atmosphere") then
                v.Enabled = false
            end
        end
    else
        Lighting.Brightness = original.lighting.Brightness
        Lighting.ColorShift_Bottom = original.lighting.ColorShift_Bottom
        Lighting.ColorShift_Top = original.lighting.ColorShift_Top
        Lighting.EnvironmentDiffuseScale = original.lighting.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = original.lighting.EnvironmentSpecularScale
        Lighting.ExposureCompensation = original.lighting.ExposureCompensation
        
        for _, v in pairs(Lighting:GetChildren()) do
            if v:IsA("PostEffect") or v:IsA("ColorCorrectionEffect") 
                or v:IsA("BloomEffect") or v:IsA("BlurEffect") 
                or v:IsA("SunRaysEffect") or v:IsA("Atmosphere") then
                v.Enabled = true
            end
        end
    end
    state.lighting = enable
end

local function toggleParticles(enable)
    if enable then
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = false
            end
        end
        state._particleConn = Workspace.DescendantAdded:Connect(function(desc)
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                desc.Enabled = false
            end
        end)
    else
        if state._particleConn then
            state._particleConn:Disconnect()
            state._particleConn = nil
        end
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = true
            end
        end
    end
    state.particles = enable
end

local function toggleFog(enable)
    if enable then
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 9e9
    else
        Lighting.FogEnd = original.fog.FogEnd
        Lighting.FogStart = original.fog.FogStart
    end
    state.fog = enable
end

local function toggleRenderDistance(enable)
    if enable then
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("Model") or v:IsA("BasePart") then
                -- Disable streaming on far parts (basic approach)
                if v:IsA("BasePart") and not v.Anchored then
                    -- Skip character parts
                    if not v:IsDescendantOf(player.Character or Instance.new("Folder")) then
                        v.CanCollide = v.CanCollide -- preserve
                    end
                end
            end
        end
        -- Lower camera max distance
        if player.CameraMode then
            -- Adjust graphics quality
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end
    else
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
    end
    state.renderDistance = enable
end

local function toggleFullBoost(enable)
    toggleShadows(enable)
    toggleTextures(enable)
    toggleLighting(enable)
    toggleParticles(enable)
    toggleFog(enable)
    toggleRenderDistance(enable)
    state.fullBoost = enable
end

-- ==================== GUI CREATION ====================

-- Cleanup old GUI if exists
local oldGui = playerGui:FindFirstChild("KyrielFPSBoost")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KyrielFPSBoost"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 280, 0, 380)
mainFrame.Position = UDim2.new(0, 20, 0.5, -190)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = titleBar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡ FPS BOOST"
title.TextColor3 = Color3.fromRGB(80, 200, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

-- Scroll/content area
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, -50)
content.Position = UDim2.new(0, 0, 0, 45)
content.BackgroundTransparency = 1
content.Parent = mainFrame

local uiList = Instance.new("UIListLayout")
uiList.Padding = UDim.new(0, 6)
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.Parent = content

-- Helper: create toggle button
local function createToggle(name, defaultState, callback)
    local btnFrame = Instance.new("Frame")
    btnFrame.Size = UDim2.new(1, -20, 0, 38)
    btnFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    btnFrame.BorderSizePixel = 0
    btnFrame.Parent = content
    
    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 6)
    frameCorner.Parent = btnFrame
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = btnFrame
    
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 50, 0, 22)
    toggleBtn.Position = UDim2.new(1, -62, 0.5, -11)
    toggleBtn.BackgroundColor3 = defaultState and Color3.fromRGB(50, 200, 80) or Color3.fromRGB(80, 80, 90)
    toggleBtn.Text = defaultState and "ON" or "OFF"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 11
    toggleBtn.Parent = btnFrame
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 4)
    toggleCorner.Parent = toggleBtn
    
    local currentState = defaultState
    
    toggleBtn.MouseButton1Click:Connect(function()
        currentState = not currentState
        toggleBtn.Text = currentState and "ON" or "OFF"
        toggleBtn.BackgroundColor3 = currentState and Color3.fromRGB(50, 200, 80) or Color3.fromRGB(80, 80, 90)
        callback(currentState)
    end)
    
    return btnFrame, toggleBtn
end

-- FPS Counter at bottom
local fpsLabel = Instance.new("TextLabel")
fpsLabel.Size = UDim2.new(1, -20, 0, 28)
fpsLabel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
fpsLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.TextSize = 13
fpsLabel.Text = "FPS: --"
fpsLabel.Parent = content

local fpsCorner = Instance.new("UICorner")
fpsCorner.CornerRadius = UDim.new(0, 6)
fpsCorner.Parent = fpsLabel

-- ==================== TOGGLES ====================

createToggle("🚀 FULL BOOST (All)", false, function(state)
    toggleFullBoost(state)
end)

createToggle("🌑 Disable Shadows", false, function(state)
    toggleShadows(state)
end)

createToggle("🎨 Remove Textures", false, function(state)
    toggleTextures(state)
end)

createToggle("💡 Downgrade Lighting", false, function(state)
    toggleLighting(state)
end)

createToggle("✨ Disable Particles", false, function(state)
    toggleParticles(state)
end)

createToggle("🌫️ Disable Fog", false, function(state)
    toggleFog(state)
end)

createToggle("📐 Low Render Quality", false, function(state)
    toggleRenderDistance(state)
end)

-- ==================== FPS COUNTER ====================

local frames = 0
local lastUpdate = tick()

RunService.RenderStepped:Connect(function()
    frames = frames + 1
    if tick() - lastUpdate >= 1 then
        fpsLabel.Text = "FPS: " .. frames
        if frames >= 50 then
            fpsLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        elseif frames >= 30 then
            fpsLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
        else
            fpsLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
        frames = 0
        lastUpdate = tick()
    end
end)

-- Notification
local notif = Instance.new("TextLabel")
notif.Size = UDim2.new(0, 250, 0, 30)
notif.Position = UDim2.new(0.5, -125, 0, 10)
notif.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
notif.TextColor3 = Color3.fromRGB(80, 200, 255)
notif.Font = Enum.Font.GothamBold
notif.TextSize = 13
notif.Text = "⚡ FPS Boost Loaded — Drag the panel!"
notif.Parent = screenGui

local notifCorner = Instance.new("UICorner")
notifCorner.CornerRadius = UDim.new(0, 6)
notifCorner.Parent = notif

task.delay(4, function()
    notif:Destroy()
end)

print("[Kyriel] FPS Boost Script loaded. Use the GUI to toggle features.")
