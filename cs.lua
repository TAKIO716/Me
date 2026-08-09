--[[
    Kyriel's UI Inspector & Tab Scraper
    Hotkey: K = Toggle Panel
    Left Click GUI = Print element info
    Right Click GUI = Scan text contents inside
]]

local Player = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Mouse = Player.LocalPlayer:GetMouse()
local RunService = game:GetService("RunService")

-- ================= GUI SETUP =================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KyrielInspector"
ScreenGui.Parent = game:GetService("CoreGui") -- atau PlayerGui, bisa disesuaikan

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 350, 0, 380)
MainFrame.Position = UDim2.new(0, 10, 0, 50)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

-- Title Bar
local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Title.TextColor3 = Color3.fromRGB(0, 255, 100)
Title.Text = "Kyriel Inspector - DreZainZorLuiston"
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 14
Title.Parent = MainFrame

-- Click Info Box
local ClickInfoLabel = Instance.new("TextLabel")
ClickInfoLabel.Name = "ClickInfoLabel"
ClickInfoLabel.Size = UDim2.new(1, -10, 0, 20)
ClickInfoLabel.Position = UDim2.new(0, 5, 0, 30)
ClickInfoLabel.BackgroundTransparency = 1
ClickInfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
ClickInfoLabel.Text = "Last Click Info:"
ClickInfoLabel.Font = Enum.Font.SourceSans
ClickInfoLabel.TextSize = 12
ClickInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
ClickInfoLabel.Parent = MainFrame

local ClickOutput = Instance.new("TextBox")
ClickOutput.Name = "ClickOutput"
ClickOutput.Size = UDim2.new(1, -10, 0, 60)
ClickOutput.Position = UDim2.new(0, 5, 0, 50)
ClickOutput.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
ClickOutput.TextColor3 = Color3.fromRGB(255, 255, 255)
ClickOutput.Text = "Klik kiri di UI untuk melihat info..."
ClickOutput.Font = Enum.Font.SourceSans
ClickOutput.TextSize = 11
ClickOutput.MultiLine = true
ClickOutput.TextEditable = false
ClickOutput.BorderSizePixel = 0
ClickOutput.Parent = MainFrame

-- Tab Scraping Section
local TabScrapeLabel = Instance.new("TextLabel")
TabScrapeLabel.Name = "TabScrapeLabel"
TabScrapeLabel.Size = UDim2.new(1, -10, 0, 20)
TabScrapeLabel.Position = UDim2.new(0, 5, 0, 115)
TabScrapeLabel.BackgroundTransparency = 1
TabScrapeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TabScrapeLabel.Text = "Tab/List Contents (Right-Click frame):"
TabScrapeLabel.Font = Enum.Font.SourceSans
TabScrapeLabel.TextSize = 12
TabScrapeLabel.TextXAlignment = Enum.TextXAlignment.Left
TabScrapeLabel.Parent = MainFrame

local TabOutput = Instance.new("TextBox")
TabOutput.Name = "TabOutput"
TabOutput.Size = UDim2.new(1, -10, 0, 150)
TabOutput.Position = UDim2.new(0, 5, 0, 135)
TabOutput.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
TabOutput.TextColor3 = Color3.fromRGB(255, 255, 255)
TabOutput.Text = "Klik kanan di frame/tab untuk ambil isinya..."
TabOutput.Font = Enum.Font.SourceSans
TabOutput.TextSize = 11
TabOutput.MultiLine = true
TabOutput.TextEditable = false
TabOutput.TextYAlignment = Enum.TextYAlignment.Top
TabOutput.Parent = MainFrame

-- Buttons
local CopyButton = Instance.new("TextButton")
CopyButton.Name = "CopyButton"
CopyButton.Size = UDim2.new(0, 80, 0, 25)
CopyButton.Position = UDim2.new(0, 5, 0, 295)
CopyButton.BackgroundColor3 = Color3.fromRGB(0, 150, 50)
CopyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyButton.Text = "Copy All"
CopyButton.Font = Enum.Font.SourceSansBold
CopyButton.TextSize = 13
CopyButton.Parent = MainFrame

local ClearButton = Instance.new("TextButton")
ClearButton.Name = "ClearButton"
ClearButton.Size = UDim2.new(0, 80, 0, 25)
ClearButton.Position = UDim2.new(0, 95, 0, 295)
ClearButton.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
ClearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearButton.Text = "Clear"
ClearButton.Font = Enum.Font.SourceSansBold
ClearButton.TextSize = 13
ClearButton.Parent = MainFrame

local ScanHint = Instance.new("TextLabel")
ScanHint.Size = UDim2.new(1, -10, 0, 30)
ScanHint.Position = UDim2.new(0, 5, 0, 330)
ScanHint.BackgroundTransparency = 1
ScanHint.TextColor3 = Color3.fromRGB(150, 150, 150)
ScanHint.Text = "Hotkey: K = Toggle Panel | Left=Get Info | Right=Scrape"
ScanHint.Font = Enum.Font.SourceSans
ScanHint.TextSize = 11
ScanHint.TextXAlignment = Enum.TextXAlignment.Left
ScanHint.Parent = MainFrame

-- ================= LOGIC =================
local lastClickTarget = nil
local lastScrapeTarget = nil

-- Toggle panel visibility
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.K then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- Click detection
Mouse.Button1Down:Connect(function()
    if not MainFrame.Visible then return end
    local target = Mouse.Target
    if target then
        lastClickTarget = target
        local pos = target.AbsolutePosition
        local size = target.AbsoluteSize
        local parentPath = target:GetFullName()
        local info = string.format(
            "Name: %s\nClass: %s\nPath: %s\nPos: (%d, %d)\nSize: (%d, %d)",
            target.Name,
            target.ClassName,
            parentPath,
            pos.X, pos.Y,
            size.X, size.Y
        )
        ClickOutput.Text = info
    end
end)

-- Right-click to scrape tab contents (list of items)
Mouse.Button2Down:Connect(function()
    if not MainFrame.Visible then return end
    local target = Mouse.Target
    if target and target:IsA("GuiObject") then
        lastScrapeTarget = target
        local texts = {}
        local function recurse(parent, depth)
            depth = depth or 0
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    if child.Text and child.Text ~= "" then
                        table.insert(texts, string.rep("  ", depth) .. "[" .. child.ClassName .. "] " .. child.Name .. " = \"" .. child.Text .. "\"")
                    end
                elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                    -- skip images, but may have text in children
                end
                if #child:GetChildren() > 0 then
                    recurse(child, depth + 1)
                end
            end
        end
        recurse(target)
        if #texts > 0 then
            TabOutput.Text = "Scraped from: " .. target:GetFullName() .. "\n\n" .. table.concat(texts, "\n")
        else
            TabOutput.Text = "No text elements found inside " .. target.Name
        end
    end
end)

-- Copy button
local function setClipboard(text)
    -- Attempt to use setclipboard (some executors support)
    local success, err = pcall(function()
        if setclipboard then
            setclipboard(text)
        else
            -- fallback: select text in a TextBox
            local tempBox = Instance.new("TextBox")
            tempBox.Size = UDim2.new(0, 1, 0, 1)
            tempBox.Position = UDim2.new(0, -100, 0, -100)
            tempBox.Text = text
            tempBox.Parent = ScreenGui
            tempBox:CaptureFocus()
            tempBox.SelectionStart = 1
            tempBox.CursorPosition = #text + 1
            task.wait(0.5)
            tempBox:Destroy()
            warn("Cannot set clipboard directly. Text copied to invisible box - now use Ctrl+C manually!")
        end
    end)
    if not success then
        warn("Clipboard set failed: " .. tostring(err))
    end
end

CopyButton.MouseButton1Click:Connect(function()
    local allText = "=== CLICK INFO ===\n" .. ClickOutput.Text .. "\n\n=== TAB CONTENTS ===\n" .. TabOutput.Text
    setClipboard(allText)
    -- Also make it visible in a dedicated copy box for manual selection
    ClickOutput.Text = allText -- overwrite click output with combined for easy copying
    TabOutput.Text = "Copied! Check Click Output box above or use Ctrl+V."
    task.wait(2)
    TabOutput.Text = "Ready for next scrape..."
end)

ClearButton.MouseButton1Click:Connect(function()
    ClickOutput.Text = "Klik kiri di UI untuk melihat info..."
    TabOutput.Text = "Klik kanan di frame/tab untuk ambil isinya..."
end)

-- Prevent clicking on our own GUI from triggering events
local function protect(gui)
    gui.Active = false -- we don't want the main frame to be clickable target
    for _, child in ipairs(gui:GetChildren()) do
        if child:IsA("GuiObject") and child ~= CopyButton and child ~= ClearButton then
            child.Active = false
        end
    end
end
protect(MainFrame)

print("Kyriel Inspector loaded. Press K to toggle.")
