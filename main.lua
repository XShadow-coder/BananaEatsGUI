--========================================================
-- BANANA FARM V8 (AutoEscape spam 3s inside door) - Aggiornato
--========================================================

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")

-- Player / constants
local player = Players.LocalPlayer
local MONEY_NAME = "Token"
local RUNNER_TEAM = "Runners"
local BANANA_TEAM = "Banana"
local SAFE_HEIGHT = 500

-- Attempt to fetch GameClock safely
local GameClock
pcall(function()
    if Workspace:FindFirstChild("GameProperties") then
        GameClock = Workspace.GameProperties:FindFirstChild("GameClock")
    end
end)

-- Toggles central store
local Toggles = {
    AutoCollect = false,
    SafePlace = false,
    AutoEscape = false,
    EspTokens = false,
    EspEntities = false,
    EspPuzzles = false
}

-- State
local myPlatform = nil
local savedPosition = nil
local espCache = {}
local espInterval = 0.5
local autoEscapeDelay = 5
local roundStartTick = 0
local isEscaping = false

-- Magnet control
local magnetTask = nil

-- Anti-AFK
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- UTIL
local function getAdorneeFromObject(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- GUI (stile precedente, colori minimal)
local COLORS = {
    darkBG = Color3.fromRGB(20,20,20),
    strokeGray = Color3.fromRGB(70,70,70),
    white = Color3.fromRGB(230,230,230),
    blue = Color3.fromRGB(0,170,255),
    banana = Color3.fromRGB(230,190,30),
    puzzle = Color3.fromRGB(0,200,110),
    yellow = Color3.fromRGB(220,220,80)
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BananaFarmGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0,280,0,420)
mainFrame.Position = UDim2.new(0.5,-140,0.5,-210)
mainFrame.BackgroundColor3 = COLORS.darkBG
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,10)

local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = COLORS.strokeGray
stroke.Thickness = 1.4

local title = Instance.new("TextLabel", mainFrame)
title.Size = UDim2.new(1,-20,0,28)
title.Position = UDim2.new(0,10,0,6)
title.BackgroundTransparency = 1
title.Text = "BANANA FARM V8"
title.Font = Enum.Font.GothamBold
title.TextColor3 = COLORS.white
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left

local separator = Instance.new("Frame", mainFrame)
separator.Size = UDim2.new(1,-20,0,2)
separator.Position = UDim2.new(0,10,0,34)
separator.BackgroundColor3 = COLORS.strokeGray
separator.BorderSizePixel = 0

-- CreateToggle that writes to Toggles[key] and calls onChanged
local function CreateToggle(name, posY, key, onChanged)
    Toggles[key] = Toggles[key] or false
    local btn = Instance.new("TextButton", mainFrame)
    btn.Size = UDim2.new(0,260,0,28)
    btn.Position = UDim2.new(0,10,0,posY)
    btn.BackgroundColor3 = COLORS.strokeGray
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = COLORS.white
    btn.TextSize = 14
    btn.Text = name .. ": " .. (Toggles[key] and "On" or "Off")
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

    btn.MouseButton1Click:Connect(function()
        Toggles[key] = not Toggles[key]
        btn.Text = name .. ": " .. (Toggles[key] and "On" or "Off")
        pcall(function() if onChanged then onChanged(Toggles[key]) end end)
    end)

    return btn
end

-- Forward declarations for callbacks
local function onAutoCollectChanged(state) end
local function onSafePlaceChanged(state) end

-- Buttons positions
local y = 60
local spacing = 40
local btnAutoCollect = CreateToggle("Auto Collect Coins", y, "AutoCollect", function(s) onAutoCollectChanged(s) end); y = y + spacing
local btnSafePlace   = CreateToggle("Safe Place", y, "SafePlace", function(s) onSafePlaceChanged(s) end); y = y + spacing
local btnAutoEscape  = CreateToggle("Auto Escape (<60s)", y, "AutoEscape", nil); y = y + spacing
local btnEspTokens   = CreateToggle("Esp Tokens", y, "EspTokens", nil); y = y + spacing
local btnEspEntities = CreateToggle("Esp Entities", y, "EspEntities", nil); y = y + spacing
local btnEspPuzzles  = CreateToggle("Esp Puzzles", y, "EspPuzzles", nil); y = y + spacing

-- CLEAN UP BUTTON (minimal style, fixed at bottom)
local btnClean = Instance.new("TextButton", mainFrame)
btnClean.Size = UDim2.new(0,260,0,36)
btnClean.Position = UDim2.new(0,10,1,-46) -- bottom with 10px margin
btnClean.BackgroundColor3 = Color3.fromRGB(90,90,90) -- minimal accent
btnClean.Font = Enum.Font.GothamBold
btnClean.TextColor3 = COLORS.white
btnClean.TextSize = 15
btnClean.Text = "CLEAN UP (RESET)"
Instance.new("UICorner", btnClean).CornerRadius = UDim.new(0,8)

--========================================================
-- SAFE PLACE: spam teleport 1s then keep platform
--========================================================

local function enableSafePlace()
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- save current position
    savedPosition = hrp.Position

    -- create platform if not exists
    if not myPlatform then
        myPlatform = Instance.new("Part")
        myPlatform.Name = "BF_SafePlatform"
        myPlatform.Size = Vector3.new(140,1,140)
        myPlatform.Anchored = true
        myPlatform.CanCollide = true
        myPlatform.Transparency = 0.25
        myPlatform.Position = Vector3.new(hrp.Position.X, SAFE_HEIGHT, hrp.Position.Z) - Vector3.new(0,3,0)
        myPlatform.Parent = Workspace
    end

    -- spam teleport for 1 second (0.05s step)
    local spamTime = 1.0
    local interval = 0.05
    local iterations = math.floor(spamTime / interval)
    task.spawn(function()
        for i = 1, iterations do
            if not Toggles.SafePlace then break end
            if not player.Character then break end
            local hrp2 = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp2 and myPlatform then
                pcall(function()
                    hrp2.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    hrp2.CFrame = myPlatform.CFrame + Vector3.new(0,3,0)
                end)
            end
            task.wait(interval)
        end
        -- final adjustment
        if Toggles.SafePlace and player.Character and myPlatform then
            local hrp3 = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp3 then
                pcall(function()
                    hrp3.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    hrp3.CFrame = myPlatform.CFrame + Vector3.new(0,3,0)
                end)
            end
        end
    end)
end

-- normal disable (teleport back to savedPosition)
local function disableSafePlace()
    local char = player.Character
    if char and savedPosition then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                hrp.CFrame = CFrame.new(savedPosition)
            end)
        end
    end

    if myPlatform then
        myPlatform:Destroy()
        myPlatform = nil
    end

    savedPosition = nil
end

-- disable without teleport (for Lobby case)
local function disableSafePlaceNoTeleport()
    if myPlatform then
        myPlatform:Destroy()
        myPlatform = nil
    end
    savedPosition = nil
end

-- SafePlace toggle callback
onSafePlaceChanged = function(state)
    if state then
        enableSafePlace()
    else
        disableSafePlace()
    end
end

-- Re-enable safe place after respawn if needed
player.CharacterAdded:Connect(function()
    if Toggles.SafePlace then
        task.wait(0.8)
        enableSafePlace()
    end
end)

-- If player team changes to Lobby -> disable platform without teleport
player:GetPropertyChangedSignal("Team"):Connect(function()
    local t = player.Team
    if t and t.Name == "Lobby" then
        if myPlatform then
            disableSafePlaceNoTeleport()
        end
        Toggles.SafePlace = false
        if btnSafePlace and btnSafePlace:IsA("TextButton") then
            btnSafePlace.Text = "Safe Place: Off"
        end
    end
end)

--========================================================
-- MAGNET: teletrasporto diretto ogni 0.5s
--========================================================

local function magnetLoop()
    while Toggles.AutoCollect do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local tokensFolder = Workspace:FindFirstChild("GameKeeper")
                    and Workspace.GameKeeper:FindFirstChild("Map")
                    and Workspace.GameKeeper.Map:FindFirstChild("Tokens")
                if tokensFolder then
                    pcall(function()
                        for _, token in ipairs(tokensFolder:GetChildren()) do
                            if not Toggles.AutoCollect then break end
                            local part = getAdorneeFromObject(token)
                            if part and part.Name == MONEY_NAME then
                                part.CanCollide = false
                                part.CFrame = hrp.CFrame + Vector3.new(0,3,0)
                            end
                        end
                    end)
                end
            end
        end
        task.wait(0.5)
    end
    magnetTask = nil
end

local function startMagnet()
    if magnetTask then return end
    magnetTask = task.spawn(magnetLoop)
end

-- AutoCollect toggle callback
onAutoCollectChanged = function(state)
    if state then
        startMagnet()
    else
        -- toggle off: loop will stop because it checks Toggles.AutoCollect
    end
end

-- Ensure initial magnet if toggled on (default false)
if Toggles.AutoCollect then startMagnet() end

--========================================================
-- AUTO ESCAPE (spam-teleport INSIDE exit for 3s)
-- Conditions:
--  - Toggles.AutoEscape == true
--  - player.Team == Runners
--  - GameClock.Value <= 60
--  - waited autoEscapeDelay after round start
-- Behavior:
--  - when conditions met and not already escaping, spam-teleport player to exit's CFrame (no +y) for 3s (0.05s steps)
--  - respect toggle/team during spam (will abort if toggle turned off or team changes)
--========================================================

if GameClock then
    GameClock:GetPropertyChangedSignal("Value"):Connect(function()
        if GameClock.Value > 100 then
            roundStartTick = tick()
            isEscaping = false
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(0.2) -- light check interval
        if not Toggles.AutoEscape then continue end
        if not player.Team or player.Team.Name ~= RUNNER_TEAM then continue end
        if not GameClock then continue end
        if GameClock.Value > 60 then
            isEscaping = false
            continue
        end
        if roundStartTick ~= 0 and tick() - roundStartTick < autoEscapeDelay then continue end
        if isEscaping then continue end

        -- find exit part
        local exits = Workspace:FindFirstChild("GameKeeper") and Workspace.GameKeeper:FindFirstChild("Exits")
        if not exits then continue end

        local exitPart = nil
        for _, v in ipairs(exits:GetChildren()) do
            if v.Name == "EscapeDoor" then
                exitPart = v:FindFirstChild("Root") or v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                if exitPart then break end
            end
        end

        if not exitPart then continue end
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then continue end

        -- spam-teleport inside for 3 seconds
        isEscaping = true
        local spamDuration = 3.0
        local spamInterval = 0.05
        local spamIterations = math.floor(spamDuration / spamInterval)
        for i = 1, spamIterations do
            -- abort conditions: toggle turned off or team changed or no character
            if not Toggles.AutoEscape then break end
            if not player.Team or player.Team.Name ~= RUNNER_TEAM then break end
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then break end

            pcall(function()
                local hrp = player.Character.HumanoidRootPart
                -- teleport to exit's CFrame (no vertical offset) -- places you 'inside' the door area
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                hrp.CFrame = exitPart.CFrame
            end)

            task.wait(spamInterval)
        end

        -- leave isEscaping true until the situation resets (so we don't re-trigger immediately)
        -- if we aborted early due to toggle/team change, clear isEscaping to allow future triggers
        if not Toggles.AutoEscape or not player.Team or player.Team.Name ~= RUNNER_TEAM then
            isEscaping = false
        else
            -- keep flagged true so we don't spam again this phase
            isEscaping = true
        end
    end
end)

--========================================================
-- ESP (optimized 0.5s)
--========================================================

local function clearEspEntry(key)
    local e = espCache[key]
    if not e then return end
    if e.hl and e.hl.Parent then e.hl:Destroy() end
    if e.bill and e.bill.Parent then e.bill:Destroy() end
    espCache[key] = nil
end

local function createBillboard(adornee, text, color)
    local bill = Instance.new("BillboardGui")
    bill.Name = "BF_NameTag"
    bill.Adornee = adornee
    bill.Size = UDim2.new(0,160,0,28)
    bill.StudsOffset = Vector3.new(0,3,0)
    bill.AlwaysOnTop = true

    local lbl = Instance.new("TextLabel", bill)
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextColor3 = color
    lbl.TextScaled = true

    bill.Parent = workspace
    return bill
end

local function addEspForAdornee(adornee, color, nameText)
    if not adornee then return end
    if espCache[adornee] then return end

    local hl = Instance.new("Highlight")
    hl.Name = "BF_Highlight"
    hl.FillColor = color
    hl.OutlineColor = Color3.new(0,0,0)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    if adornee.Parent and adornee.Parent:IsA("Model") then
        hl.Parent = adornee.Parent
    else
        hl.Parent = adornee
    end

    local bill = nil
    if nameText then
        bill = createBillboard(adornee, nameText, color)
    end

    espCache[adornee] = { hl = hl, bill = bill }
end

local function findAdornee(obj)
    return getAdorneeFromObject(obj)
end

task.spawn(function()
    while true do
        task.wait(espInterval)
        local seen = {}

        -- Tokens
        if Toggles.EspTokens then
            local tokensFolder = Workspace:FindFirstChild("GameKeeper")
                and Workspace.GameKeeper:FindFirstChild("Map")
                and Workspace.GameKeeper.Map:FindFirstChild("Tokens")
            if tokensFolder then
                for _, token in ipairs(tokensFolder:GetChildren()) do
                    local adornee = findAdornee(token)
                    if adornee then
                        addEspForAdornee(adornee, COLORS.yellow)
                        seen[adornee] = true
                    end
                end
            end
        end

        -- Entities (players)
        if Toggles.EspEntities then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Character then
                    local adorn = findAdornee(plr.Character)
                    if adorn then
                        local team = plr.Team and plr.Team.Name or ""
                        if team == RUNNER_TEAM then
                            addEspForAdornee(adorn, COLORS.blue, plr.Name)
                            seen[adorn] = true
                        elseif team == BANANA_TEAM then
                            addEspForAdornee(adorn, COLORS.banana, plr.Name)
                            seen[adorn] = true
                        end
                    end
                end
            end
        end

        -- Puzzles (workspace.GameKeeper.Puzzles)
        if Toggles.EspPuzzles then
            local puzzleFolder = Workspace:FindFirstChild("GameKeeper") and Workspace:FindFirstChild("Puzzles") or (Workspace:FindFirstChild("GameKeeper") and Workspace.GameKeeper:FindFirstChild("Puzzles"))
            if not puzzleFolder then
                puzzleFolder = Workspace:FindFirstChild("GameKeeper") and Workspace.GameKeeper:FindFirstChild("Map") and Workspace.GameKeeper.Map:FindFirstChild("Puzzles")
            end
            if puzzleFolder then
                for _, obj in ipairs(puzzleFolder:GetChildren()) do
                    local adornee = findAdornee(obj)
                    if adornee then
                        addEspForAdornee(adornee, COLORS.puzzle, tostring(obj.Name))
                        seen[adornee] = true
                    end
                end
            end
        end

        -- cleanup entries not seen
        for adornee, _ in pairs(espCache) do
            if not seen[adornee] then
                clearEspEntry(adornee)
            end
        end
    end
end)

-- cleanup on character remove
player.CharacterRemoving:Connect(function()
    for k, _ in pairs(espCache) do clearEspEntry(k) end
    espCache = {}
    if myPlatform then
        myPlatform:Destroy()
        myPlatform = nil
    end
end)

--========================================================
-- CLEAN UP FUNCTION (resets everything and tries to reduce lag)
-- Behavior:
--  - if SafePlace active, teleport player to savedPosition BEFORE reset
--  - when lobby entered, SafePlace is removed without teleport
--========================================================

local function doCleanUp()
    -- If SafePlace active and we have a savedPosition -> teleport back first
    if Toggles.SafePlace and savedPosition and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function()
            local hrp = player.Character.HumanoidRootPart
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            hrp.CFrame = CFrame.new(savedPosition)
        end)
    end

    -- 1) disable all toggles
    for k,_ in pairs(Toggles) do Toggles[k] = false end

    -- 2) stop magnet: loop checks Toggles.AutoCollect so it will exit
    task.spawn(function()
        task.wait(0.3)
        magnetTask = nil
    end)

    -- 3) remove platform (already teleported back if we did above)
    if myPlatform then
        pcall(function() myPlatform:Destroy() end)
        myPlatform = nil
    end

    -- 4) reset savedPosition / escape state / round tick
    savedPosition = nil
    isEscaping = false
    roundStartTick = 0

    -- 5) clear all ESP artifacts
    for adornee, _ in pairs(espCache) do
        clearEspEntry(adornee)
    end
    espCache = {}

    -- 6) update UI buttons text to Off (minimal)
    local function setBtnOff(btn, label)
        if btn and btn:IsA("TextButton") then
            btn.Text = label .. ": Off"
        end
    end
    setBtnOff(btnAutoCollect, "Auto Collect Coins")
    setBtnOff(btnSafePlace, "Safe Place")
    setBtnOff(btnAutoEscape, "Auto Escape (<60s)")
    setBtnOff(btnEspTokens, "Esp Tokens")
    setBtnOff(btnEspEntities, "Esp Entities")
    setBtnOff(btnEspPuzzles, "Esp Puzzles")

    -- 7) small garbage collection to reduce memory
    pcall(function() collectgarbage("collect") end)
end

btnClean.MouseButton1Click:Connect(function()
    doCleanUp()
end)

-- Bind callbacks (ensure these are the active handlers)
onAutoCollectChanged = function(state)
    if state then startMagnet() end
    -- when state==false the magnet loop will stop because it checks Toggles.AutoCollect
end

-- Show GUI
screenGui.Enabled = true

-- End of script
