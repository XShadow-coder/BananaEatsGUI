--========================================================
-- BANANA FARM V9
-- Behavior:
--  - se vai in Lobby: la piattaforma SafePlace viene distrutta (no teleport back)
--  - se torni in Runners e SafePlace è On: la piattaforma viene ricreata e spam-teleport per 1s
--  - in Lobby le feature principali (AutoCollect, AutoEscape, ESP) non vengono eseguite
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

-- GameClock (safe attempt)
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

-- UTIL helpers
local function isInLobby()
    return player.Team and player.Team.Name == "Lobby"
end

local function isRunner()
    return player.Team and player.Team.Name == RUNNER_TEAM
end

local function getAdorneeFromObject(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- GUI minimal (come richiesto)
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
title.Text = "BANANA FARM V9"
title.Font = Enum.Font.GothamBold
title.TextColor3 = COLORS.white
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left

local separator = Instance.new("Frame", mainFrame)
separator.Size = UDim2.new(1,-20,0,2)
separator.Position = UDim2.new(0,10,0,34)
separator.BackgroundColor3 = COLORS.strokeGray
separator.BorderSizePixel = 0

-- Toggle creator
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

-- Forward callbacks
local function onAutoCollectChanged(state) end
local function onSafePlaceChanged(state) end

-- Buttons
local y = 60
local spacing = 40
local btnAutoCollect = CreateToggle("Auto Collect Coins", y, "AutoCollect", function(s) onAutoCollectChanged(s) end); y = y + spacing
local btnSafePlace   = CreateToggle("Safe Place", y, "SafePlace", function(s) onSafePlaceChanged(s) end); y = y + spacing
local btnAutoEscape  = CreateToggle("Auto Escape (<60s)", y, "AutoEscape", nil); y = y + spacing
local btnEspTokens   = CreateToggle("Esp Tokens", y, "EspTokens", nil); y = y + spacing
local btnEspEntities = CreateToggle("Esp Entities", y, "EspEntities", nil); y = y + spacing
local btnEspPuzzles  = CreateToggle("Esp Puzzles", y, "EspPuzzles", nil); y = y + spacing

-- Clean button at bottom
local btnClean = Instance.new("TextButton", mainFrame)
btnClean.Size = UDim2.new(0,260,0,36)
btnClean.Position = UDim2.new(0,10,1,-46) -- bottom
btnClean.BackgroundColor3 = Color3.fromRGB(90,90,90)
btnClean.Font = Enum.Font.GothamBold
btnClean.TextColor3 = COLORS.white
btnClean.TextSize = 15
btnClean.Text = "CLEAN UP (RESET)"
Instance.new("UICorner", btnClean).CornerRadius = UDim.new(0,8)

-- SAFE PLACE: create/destroy logic
local function enableSafePlace()
    if isInLobby() then return end -- non creare in lobby
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- salva posizione corrente (usata se user fa clean up)
    savedPosition = hrp.Position

    -- crea piattaforma sopra la mappa
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

    -- spam teletrasporto per 1 secondo
    local spamTime = 1.0
    local interval = 0.05
    local iterations = math.floor(spamTime / interval)
    task.spawn(function()
        for i = 1, iterations do
            if not Toggles.SafePlace or isInLobby() then break end
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
        if Toggles.SafePlace and not isInLobby() and player.Character and myPlatform then
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

-- normal disable: teleport back to savedPosition
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

-- disable without teleport (for Lobby)
local function disableSafePlaceNoTeleport()
    if myPlatform then
        myPlatform:Destroy()
        myPlatform = nil
    end
    -- clear savedPosition so we won't accidentally teleport back later
    savedPosition = nil
end

-- SafePlace toggle callback
onSafePlaceChanged = function(state)
    if state then
        -- create only if not in Lobby
        if not isInLobby() then
            enableSafePlace()
        end
    else
        disableSafePlace()
    end
end

-- When character respawns and SafePlace is On and we are Runner -> recreate
player.CharacterAdded:Connect(function()
    task.wait(0.8)
    if Toggles.SafePlace and isRunner() then
        enableSafePlace()
    end
end)

-- TEAM CHANGE HANDLER:
-- - if enter Lobby: destroy platform without teleport (disable visual only)
-- - if enter Runners and SafePlace On: create platform above current pos
player:GetPropertyChangedSignal("Team"):Connect(function()
    local t = player.Team
    if t and t.Name == "Lobby" then
        -- remove platform without teleport
        if myPlatform then
            disableSafePlaceNoTeleport()
        end
        -- do NOT flip the toggle: user choice is preserved
        -- stop effects: loops check isInLobby() and will skip while in lobby
        -- clear ESP artifacts to avoid showing things in lobby
        for k, _ in pairs(espCache) do
            if espCache[k] then
                if espCache[k].hl and espCache[k].hl.Parent then pcall(function() espCache[k].hl:Destroy() end) end
                if espCache[k].bill and espCache[k].bill.Parent then pcall(function() espCache[k].bill:Destroy() end) end
            end
            espCache[k] = nil
        end
    elseif t and t.Name == RUNNER_TEAM then
        -- returning to Runner: if SafePlace toggle is On, recreate platform
        if Toggles.SafePlace then
            enableSafePlace()
        end
    end
end)

-- MAGNET: teletrasporto diretto ogni 0.5s, but skip while in Lobby
local function magnetLoop()
    while Toggles.AutoCollect do
        if isInLobby() then
            -- don't collect in lobby; wait and continue
            task.wait(0.5)
            continue
        end

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
                            if not Toggles.AutoCollect or isInLobby() then break end
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

onAutoCollectChanged = function(state)
    if state then
        startMagnet()
    else
        -- loop will stop naturally
    end
end

-- AUTO ESCAPE: only when Runner and not in Lobby; spam-inside for 3s
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
        task.wait(0.2)
        if not Toggles.AutoEscape then continue end
        if isInLobby() then continue end
        if not isRunner() then continue end
        if not GameClock then continue end
        if GameClock.Value > 60 then
            isEscaping = false
            continue
        end
        if roundStartTick ~= 0 and tick() - roundStartTick < autoEscapeDelay then continue end
        if isEscaping then continue end

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

        -- spam inside for 3 seconds
        isEscaping = true
        local spamDuration = 3.0
        local spamInterval = 0.05
        local iterations = math.floor(spamDuration / spamInterval)
        for i = 1, iterations do
            if not Toggles.AutoEscape or isInLobby() or not isRunner() then
                isEscaping = false
                break
            end
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
                isEscaping = false
                break
            end
            pcall(function()
                local hrp = player.Character.HumanoidRootPart
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                -- teleport "inside" exitPart (no additional y offset)
                hrp.CFrame = exitPart.CFrame
            end)
            task.wait(spamInterval)
        end
        -- leave isEscaping true until situation resets (GameClock change) to avoid re-triggering immediately
    end
end)

-- ESP: skip while in Lobby; if entering Lobby clear ESP
local function clearAllEsp()
    for adornee, entry in pairs(espCache) do
        if entry then
            pcall(function()
                if entry.hl and entry.hl.Parent then entry.hl:Destroy() end
                if entry.bill and entry.bill.Parent then entry.bill:Destroy() end
            end)
        end
        espCache[adornee] = nil
    end
end

task.spawn(function()
    while true do
        task.wait(espInterval)
        if isInLobby() then
            -- ensure no ESP while in lobby
            if next(espCache) ~= nil then clearAllEsp() end
            continue
        end

        local seen = {}

        if Toggles.EspTokens then
            local tokensFolder = Workspace:FindFirstChild("GameKeeper")
                and Workspace.GameKeeper:FindFirstChild("Map")
                and Workspace.GameKeeper.Map:FindFirstChild("Tokens")
            if tokensFolder then
                for _, token in ipairs(tokensFolder:GetChildren()) do
                    local adornee = getAdorneeFromObject(token)
                    if adornee then
                        if not espCache[adornee] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "BF_Highlight"
                            hl.FillColor = COLORS.yellow
                            hl.OutlineColor = Color3.new(0,0,0)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Parent = adornee
                            espCache[adornee] = { hl = hl, bill = nil }
                        end
                        seen[adornee] = true
                    end
                end
            end
        end

        if Toggles.EspEntities then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Character then
                    local adorn = getAdorneeFromObject(plr.Character)
                    if adorn then
                        local team = plr.Team and plr.Team.Name or ""
                        if team == RUNNER_TEAM then
                            if not espCache[adorn] then
                                local hl = Instance.new("Highlight")
                                hl.FillColor = COLORS.blue
                                hl.OutlineColor = Color3.new(0,0,0)
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Parent = plr.Character
                                local bill = Instance.new("BillboardGui")
                                bill.Adornee = adorn
                                bill.Size = UDim2.new(0,160,0,28)
                                bill.StudsOffset = Vector3.new(0,3,0)
                                bill.AlwaysOnTop = true
                                local lbl = Instance.new("TextLabel", bill)
                                lbl.Size = UDim2.new(1,0,1,0)
                                lbl.BackgroundTransparency = 1
                                lbl.Text = plr.Name
                                lbl.Font = Enum.Font.GothamBold
                                lbl.TextColor3 = COLORS.blue
                                lbl.TextScaled = true
                                bill.Parent = workspace
                                espCache[adorn] = { hl = hl, bill = bill }
                            end
                            seen[adorn] = true
                        elseif team == BANANA_TEAM then
                            if not espCache[adorn] then
                                local hl = Instance.new("Highlight")
                                hl.FillColor = COLORS.banana
                                hl.OutlineColor = Color3.new(0,0,0)
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Parent = plr.Character
                                local bill = Instance.new("BillboardGui")
                                bill.Adornee = adorn
                                bill.Size = UDim2.new(0,160,0,28)
                                bill.StudsOffset = Vector3.new(0,3,0)
                                bill.AlwaysOnTop = true
                                local lbl = Instance.new("TextLabel", bill)
                                lbl.Size = UDim2.new(1,0,1,0)
                                lbl.BackgroundTransparency = 1
                                lbl.Text = plr.Name
                                lbl.Font = Enum.Font.GothamBold
                                lbl.TextColor3 = COLORS.banana
                                lbl.TextScaled = true
                                bill.Parent = workspace
                                espCache[adorn] = { hl = hl, bill = bill }
                            end
                            seen[adorn] = true
                        end
                    end
                end
            end
        end

        if Toggles.EspPuzzles then
            local puzzleFolder = Workspace:FindFirstChild("GameKeeper") and Workspace.GameKeeper:FindFirstChild("Puzzles")
            if not puzzleFolder then
                puzzleFolder = Workspace:FindFirstChild("GameKeeper") and Workspace.GameKeeper:FindFirstChild("Map") and Workspace.GameKeeper.Map:FindFirstChild("Puzzles")
            end
            if puzzleFolder then
                for _, obj in ipairs(puzzleFolder:GetChildren()) do
                    local adornee = getAdorneeFromObject(obj)
                    if adornee then
                        if not espCache[adornee] then
                            local hl = Instance.new("Highlight")
                            hl.FillColor = COLORS.puzzle
                            hl.OutlineColor = Color3.new(0,0,0)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Parent = adornee
                            local bill = Instance.new("BillboardGui")
                            bill.Adornee = adornee
                            bill.Size = UDim2.new(0,160,0,28)
                            bill.StudsOffset = Vector3.new(0,3,0)
                            bill.AlwaysOnTop = true
                            local lbl = Instance.new("TextLabel", bill)
                            lbl.Size = UDim2.new(1,0,1,0)
                            lbl.BackgroundTransparency = 1
                            lbl.Text = tostring(obj.Name)
                            lbl.Font = Enum.Font.GothamBold
                            lbl.TextColor3 = COLORS.puzzle
                            lbl.TextScaled = true
                            bill.Parent = workspace
                            espCache[adornee] = { hl = hl, bill = bill }
                        end
                        seen[adornee] = true
                    end
                end
            end
        end

        -- cleanup entries not seen
        for adornee, _ in pairs(espCache) do
            if not seen[adornee] then
                if espCache[adornee].hl and espCache[adornee].hl.Parent then pcall(function() espCache[adornee].hl:Destroy() end) end
                if espCache[adornee].bill and espCache[adornee].bill.Parent then pcall(function() espCache[adornee].bill:Destroy() end) end
                espCache[adornee] = nil
            end
        end
    end
end)

-- cleanup on character remove
player.CharacterRemoving:Connect(function()
    clearAllEsp()
    if myPlatform then
        myPlatform:Destroy()
        myPlatform = nil
    end
end)

-- CLEAN UP function: if SafePlace active -> teleport back savedPosition before reset
local function doCleanUp()
    if Toggles.SafePlace and savedPosition and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function()
            local hrp = player.Character.HumanoidRootPart
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            hrp.CFrame = CFrame.new(savedPosition)
        end)
    end

    -- disable toggles
    for k,_ in pairs(Toggles) do Toggles[k] = false end

    -- stop magnet by letting loop see Toggles.AutoCollect == false
    task.spawn(function()
        task.wait(0.3)
        magnetTask = nil
    end)

    -- destroy platform
    if myPlatform then
        pcall(function() myPlatform:Destroy() end)
        myPlatform = nil
    end

    -- reset state
    savedPosition = nil
    isEscaping = false
    roundStartTick = 0

    -- clear ESP
    clearAllEsp()

    -- update UI text
    local function setBtnOff(btn,label) if btn and btn:IsA("TextButton") then btn.Text = label..": Off" end end
    setBtnOff(btnAutoCollect,"Auto Collect Coins")
    setBtnOff(btnSafePlace,"Safe Place")
    setBtnOff(btnAutoEscape,"Auto Escape (<60s)")
    setBtnOff(btnEspTokens,"Esp Tokens")
    setBtnOff(btnEspEntities,"Esp Entities")
    setBtnOff(btnEspPuzzles,"Esp Puzzles")

    -- collect garbage
    pcall(function() collectgarbage("collect") end)
end

btnClean.MouseButton1Click:Connect(function()
    doCleanUp()
end)

-- Ensure magnet starts if user toggles On (CreateToggle calls onAutoCollectChanged)
onAutoCollectChanged = function(state)
    if state then
        startMagnet()
    end
end

-- show UI
screenGui.Enabled = true
