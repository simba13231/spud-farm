--[[
═══════════════════════════════════════════════════════════════════════════
  FARMING AND FRIENDS — FULL FEATURE SUITE
  Compatible executors: Synapse X, Xeno, Delta, Wave, Solara, Fluxus, etc.
═══════════════════════════════════════════════════════════════════════════
  HOW TO USE
    1. Join "Farming and Friends" on Roblox
    2. Paste this whole script into your executor and Execute
    3. Press RIGHT SHIFT to show/hide the menu
    4. Toggle features in the GUI

  IF SOMETHING DOESN'T WORK
    Games update their internal names often. Open the Settings tab and
    change the "Crop Folder" / "Remote Hint" text boxes to match the
    current game (use your executor's esp/remote spy to find names).
═══════════════════════════════════════════════════════════════════════════
]]

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local StarterGui         = game:GetService("StarterGui")
local VirtualUser        = game:GetService("VirtualUser")
local VirtualInputManager= game:GetService("VirtualInputManager")
local Lighting           = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------
-- EXECUTOR COMPATIBILITY HELPERS
------------------------------------------------------------
local function try(f, ...)
    return pcall(f, ...)
end

local function realRef(obj)
    if cloneref then
        local ok, ref = try(cloneref, obj)
        if ok and ref then return ref end
    end
    return obj
end

local function guiParent()
    if gethui then
        local ok, p = try(gethui)
        if ok and p then return p end
    end
    return game:GetService("CoreGui")
end

------------------------------------------------------------
-- GAME CONFIG — adjust these in the Settings tab if needed
------------------------------------------------------------
local GameConfig = {
    -- Folder/model names (in Workspace) that hold crops/plots
    PlotFolders     = { "Crops", "Plots", "CropPlots", "FarmPlots", "Plants", "Farm", "Fields" },
    -- Folder/model names that hold collectable coins/cash
    CoinFolders     = { "Coins", "Cash", "Drops", "Rewards", "Pickups", "Money" },
    -- Location names for the sell station
    SellLocations   = { "Sell", "SellZone", "SellArea", "SellPad", "Market", "Merchant", "Shop" },
    -- Player spawn location name
    SpawnLocations  = { "SpawnPoint", "Spawn", "Start" },
    -- Attributes that mean "this crop is ready"
    RipeAttributes  = { "Ripe", "Ready", "FullyGrown", "IsRipe", "Harvestable", "Grown", "IsGrown" },
    -- Numeric attributes where >= 100 means ready
    GrowthAttributes= { "Growth", "GrowthProgress", "GrowProgress", "Progress" },
    -- Name hints used to fuzzy-find remote events (case-insensitive)
    HarvestRemoteHints = { "harvest", "pickcrop", "collectcrop", "getcrop" },
    PlantRemoteHints   = { "plant", "plantseed", "placeseed", "sow" },
    SellRemoteHints    = { "sell", "sellall", "sellcrops", "sellinventory" },
    RebirthRemoteHints = { "rebirth" },
}

------------------------------------------------------------
-- PLAYER / CHARACTER STATE
------------------------------------------------------------
local Character, Humanoid, RootPart

local function hookCharacter(char)
    Character = realRef(char)
    RootPart  = Character:WaitForChild("HumanoidRootPart", 10)
    Humanoid  = Character:WaitForChild("Humanoid", 10)
end
if LocalPlayer.Character then hookCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    hookCharacter(char)
end)

------------------------------------------------------------
-- USER OPTIONS (toggled from the GUI)
------------------------------------------------------------
local Options = {
    -- Farm
    AutoHarvest   = false,
    AutoPlant     = false,
    AutoCollect   = false,
    AutoSell      = false,
    AutoRebirth   = false,
    SelectedSeed  = "Auto",
    HarvestDelay  = 0.25,   -- seconds between harvest actions
    SellInterval  = 20,     -- seconds between sell attempts
    -- Player
    SpeedEnabled  = false,
    WalkSpeed     = 16,
    JumpEnabled   = false,
    JumpPower     = 50,
    InfiniteJump  = false,
    NoClip        = false,
    AntiAFK       = false,
    -- Teleport / Misc
    ClickTeleport = false,
    FPSBoost      = false,
    Notifications = true,
}

------------------------------------------------------------
-- NOTIFICATIONS
------------------------------------------------------------
local function notify(text, accent)
    if not Options.Notifications then return end
    try(function()
        StarterGui:SetCore("SendNotification", {
            Title    = "Farming & Friends",
            Text     = tostring(text),
            Duration = 3,
        })
    end)
end

------------------------------------------------------------
-- REMOTE / FOLDER LOOKUP
------------------------------------------------------------
local function remoteDirs()
    local dirs = {}
    for _, name in ipairs({ "Remotes", "Events", "Network", "RF", "RE" }) do
        local f = ReplicatedStorage:FindFirstChild(name)
        if f then table.insert(dirs, f) end
    end
    table.insert(dirs, ReplicatedStorage)
    return dirs
end

local function findRemote(hints)
    for _, dir in ipairs(remoteDirs()) do
        for _, obj in ipairs(dir:GetChildren()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                for _, hint in ipairs(hints) do
                    if n == hint or n:find(hint) then
                        return realRef(obj)
                    end
                end
            end
        end
    end
    return nil
end

local function fireRemote(remote, ...)
    if not remote then return false end
    return try(function(...)
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(...)
        else
            remote:FireServer(...)
        end
    end, ...)
end

local function findByNames(root, names)
    if not root then return nil end
    for _, name in ipairs(names) do
        local obj = root:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
        if obj then return obj end
    end
    return nil
end

------------------------------------------------------------
-- CROP HELPERS
------------------------------------------------------------
local cachedPlotFolders, cachedCoinFolders = {}, {}
local lastCacheTime = 0

local function nameMatchesFolder(obj, names)
    local n = obj.Name:lower()
    for _, name in ipairs(names) do
        if n == name:lower() or n:find(name:lower()) then return true end
    end
    return false
end

local function scanFolders(names)
    local found = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Folder") or obj:IsA("Model")) and nameMatchesFolder(obj, names) then
            table.insert(found, obj)
        end
    end
    return found
end

local function refreshCaches()
    cachedPlotFolders = scanFolders(GameConfig.PlotFolders)
    cachedCoinFolders = scanFolders(GameConfig.CoinFolders)
    lastCacheTime = tick()
end

local function isRipe(crop)
    for _, attr in ipairs(GameConfig.RipeAttributes) do
        if crop:GetAttribute(attr) == true then return true end
    end
    for _, attr in ipairs(GameConfig.GrowthAttributes) do
        local v = crop:GetAttribute(attr)
        if typeof(v) == "number" and v >= 100 then return true end
    end
    for _, child in ipairs(crop:GetChildren()) do
        if child:IsA("NumberValue") or child:IsA("IntValue") then
            local cn = child.Name:lower()
            for _, ga in ipairs(GameConfig.GrowthAttributes) do
                if cn == ga:lower() and child.Value >= 100 then return true end
            end
        end
    end
    local n = crop.Name:lower()
    return n:find("ripe") ~= nil or n:find("ready") ~= nil
end

local function isPlanted(plot)
    for _, attr in ipairs({ "Planted", "HasCrop", "Occupied", "IsPlanted" }) do
        local v = plot:GetAttribute(attr)
        if v == false then return false end
    end
    for _, child in ipairs(plot:GetChildren()) do
        if child:IsA("Model") and not child.Name:lower():find("plot") then return true end
    end
    return plot:GetAttribute("Planted") ~= nil
end

local function objPos(obj)
    if obj.PrimaryPart then return obj.PrimaryPart.Position end
    local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj:FindFirstChild("Base")
    if hrp and hrp:IsA("BasePart") then return hrp.Position end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then return obj:GetPivot().Position end
    return nil
end

local function getRipeCrops()
    local list = {}
    for _, folder in ipairs(cachedPlotFolders) do
        for _, plot in ipairs(folder:GetChildren()) do
            if isRipe(plot) then
                table.insert(list, plot)
            else
                for _, child in ipairs(plot:GetChildren()) do
                    if child:IsA("Model") and isRipe(child) then
                        table.insert(list, child)
                    end
                end
            end
        end
    end
    return list
end

local function nearestOf(list)
    if not RootPart then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(list) do
        local p = objPos(obj)
        if p then
            local d = (p - RootPart.Position).Magnitude
            if d < bestDist then best, bestDist = obj, d end
        end
    end
    return best
end

local function teleportTo(pos, height)
    if RootPart and RootPart.Parent then
        try(function()
            RootPart.CFrame = CFrame.new(pos + Vector3.new(0, height or 4, 0))
        end)
    end
end

local function pressKey(key)
    if VirtualInputManager then
        try(function()
            VirtualInputManager:SendKeyEvent(true,  key,   false, game)
            task.wait(0.08)
            VirtualInputManager:SendKeyEvent(false, key,   false, game)
        end)
    end
end

local function clickAt(pos)
    if VirtualInputManager then
        try(function()
            local vp = Workspace.CurrentCamera:WorldToViewportPoint(pos)
            VirtualInputManager:SendMouseButtonEvent(vp.X, vp.Y, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(vp.X, vp.Y, 0, false, game, 1)
        end)
    end
end

------------------------------------------------------------
-- FEATURE: HARVEST
------------------------------------------------------------
local function harvestCrop(crop)
    if not crop or not crop.Parent then return end

    local prompt = crop:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local p = prompt.WorldCFrame and prompt.WorldCFrame.Position or objPos(crop)
        if p then
            teleportTo(p, 3)
            task.wait(0.12)
            prompt.MaxActivationDistance = 20
            pressKey(Enum.KeyCode.E)
            try(function() firesignal(prompt.Triggered) end)
        end
        return
    end

    local detector = crop:FindFirstChildWhichIsA("ClickDetector", true)
    if detector then
        local p = objPos(crop)
        if p then
            teleportTo(p, 3)
            task.wait(0.12)
            detector.MaxActivationDistance = 50
            try(function() detector:Fire() end)
            clickAt(p)
        end
        return
    end

    local remote = findRemote(GameConfig.HarvestRemoteHints)
    if remote then
        fireRemote(remote, crop)
        fireRemote(remote, crop.Name)
    end
end

------------------------------------------------------------
-- FEATURE: PLANT
------------------------------------------------------------
local function plantPlot(plot)
    if not plot or not plot.Parent then return end
    local seedName = Options.SelectedSeed
    if seedName == "Auto" then seedName = nil end

    local remote = findRemote(GameConfig.PlantRemoteHints)
    if remote then
        if seedName then
            fireRemote(remote, seedName, plot)
            fireRemote(remote, plot, seedName)
        else
            fireRemote(remote, plot)
        end
        return
    end

    -- Fallback: teleport to the plot and touch it with the seed tool
    if RootPart then
        local p = objPos(plot)
        if p then teleportTo(p, 3) end
    end
    if seedName and LocalPlayer:FindFirstChild("Backpack") then
        for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:lower():find(seedName:lower()) then
                try(function()
                    Humanoid:EquipTool(tool)
                    task.wait(0.2)
                    Humanoid:UnequipTools()
                end)
                break
            end
        end
    end
end

------------------------------------------------------------
-- FEATURE: COLLECT COINS
------------------------------------------------------------
local function collectCoins()
    if not RootPart then return end
    local coins = {}
    for _, folder in ipairs(cachedCoinFolders) do
        for _, obj in ipairs(folder:GetChildren()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then table.insert(coins, obj) end
        end
    end
    -- fallback: scan workspace direct children
    if #coins == 0 then
        for _, obj in ipairs(Workspace:GetChildren()) do
            if (obj:IsA("BasePart") or obj:IsA("Model")) and nameMatchesFolder(obj, GameConfig.CoinFolders) then
                table.insert(coins, obj)
            end
        end
    end

    table.sort(coins, function(a, b)
        local pa, pb = objPos(a), objPos(b)
        if not pa then return false end
        if not pb then return true end
        return (pa - RootPart.Position).Magnitude < (pb - RootPart.Position).Magnitude
    end)

    local taken = 0
    for _, coin in ipairs(coins) do
        if taken >= 3 then break end
        local p = objPos(coin)
        if p and (p - RootPart.Position).Magnitude <= 500 then
            teleportTo(p, 2)
            taken += 1
            task.wait(0.05)
        end
    end
end

------------------------------------------------------------
-- FEATURE: SELL
------------------------------------------------------------
local function doSell()
    local remote = findRemote(GameConfig.SellRemoteHints)
    if remote then
        fireRemote(remote)
        fireRemote(remote, "All")
        return
    end
    local station = findByNames(Workspace, GameConfig.SellLocations)
    if station and RootPart then
        local p = objPos(station)
        if p then
            local back = RootPart.CFrame
            teleportTo(p, 3)
            task.wait(1.2)
            RootPart.CFrame = back
        end
    end
end

------------------------------------------------------------
-- FEATURE: REBIRTH
------------------------------------------------------------
local function doRebirth()
    local remote = findRemote(GameConfig.RebirthRemoteHints)
    if remote then
        local ok = fireRemote(remote)
        if ok then notify("Rebirth request sent!") end
    end
end

------------------------------------------------------------
-- FEATURE: PLAYER MODS
------------------------------------------------------------
RunService.Stepped:Connect(function()
    if Options.NoClip and Character then
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if Options.InfiniteJump and Humanoid then
        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

LocalPlayer.Idled:Connect(function()
    if Options.AntiAFK then
        try(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

------------------------------------------------------------
-- CLICK TELEPORT (Ctrl + Left Click anywhere)
------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input)
    if Options.ClickTeleport
        and input.UserInputType == Enum.UserInputType.MouseButton1
        and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        and RootPart then
        local cam = Workspace.CurrentCamera
        local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { Character }
        params.FilterType = Enum.RaycastFilterType.Exclude
        local hit = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
        if hit then
            teleportTo(hit.Position, 5)
        end
    end
end)

------------------------------------------------------------
-- FPS BOOST
------------------------------------------------------------
local function applyFpsBoost(enabled)
    if enabled then
        try(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        for _, obj in ipairs(Lighting:GetDescendants()) do
            if obj:IsA("Atmosphere") or obj:IsA("Sky") then obj.Enabled = false end
        end
        pcall(function() Workspace.FallenPartsDestroyHeight = 0/0 end)
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:lower():find("grass") then
                obj:Destroy()
            end
        end
        notify("FPS Boost enabled")
    else
        try(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
        notify("FPS Boost disabled")
    end
end

------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------
task.spawn(function()
    while task.wait(0.1) do
        local alive = Character and Character.Parent and RootPart and RootPart.Parent
        if not alive then
            task.wait(0.5)
            continue
        end

        if tick() - lastCacheTime > 15 then refreshCaches() end

        -- Speed / jump are applied continuously so respawn keeps them
        if Options.SpeedEnabled then Humanoid.WalkSpeed = Options.WalkSpeed end
        if Options.JumpEnabled  then Humanoid.UseJumpPower = true; Humanoid.JumpPower = Options.JumpPower end

        if Options.AutoCollect then
            collectCoins()
        end

        if Options.AutoHarvest then
            local target = nearestOf(getRipeCrops())
            if target then
                harvestCrop(target)
                task.wait(Options.HarvestDelay)
            end
        end

        if Options.AutoPlant then
            for _, folder in ipairs(cachedPlotFolders) do
                local done = false
                for _, plot in ipairs(folder:GetChildren()) do
                    if not isPlanted(plot) then
                        plantPlot(plot)
                        done = true
                        break
                    end
                end
                if done then break end
            end
            task.wait(Options.HarvestDelay)
        end

        if Options.AutoSell then
            if not Options._lastSell or tick() - Options._lastSell >= Options.SellInterval then
                Options._lastSell = tick()
                doSell()
            end
        end

        if Options.AutoRebirth then
            if not Options._lastRebirth or tick() - Options._lastRebirth >= 10 then
                Options._lastRebirth = tick()
                doRebirth()
            end
        end
    end
end)

refreshCaches()
notify("Script loaded! Press RIGHT SHIFT to open the menu.")

------------------------------------------------------------
-- GUI LIBRARY
------------------------------------------------------------
local COL = {
    Bg      = Color3.fromRGB(25, 26, 30),
    Panel   = Color3.fromRGB(35, 36, 42),
    Panel2  = Color3.fromRGB(45, 46, 53),
    Accent  = Color3.fromRGB(98, 190, 82),
    Accent2 = Color3.fromRGB(76, 150, 64),
    Text    = Color3.fromRGB(235, 235, 240),
    Sub     = Color3.fromRGB(155, 158, 168),
    Danger  = Color3.fromRGB(210, 80, 80),
}

local function mk(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end

local function corner(inst, r)
    return mk("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = inst })
end

local screen = mk("ScreenGui", {
    Name = "FarmingAndFriendsGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = guiParent(),
})

local main = mk("Frame", {
    Parent = screen,
    Size = UDim2.new(0, 540, 0, 380),
    Position = UDim2.new(0.5, -270, 0.5, -190),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corner(main, 10)
mk("UIStroke", { Color = Color3.fromRGB(60, 62, 70), Thickness = 1, Parent = main })

-- Title bar
local titleBar = mk("Frame", {
    Parent = main,
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
corner(titleBar, 10)
mk("Frame", { -- mask the bottom corners of the title bar
    Parent = titleBar,
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
mk("TextLabel", {
    Parent = titleBar,
    Size = UDim2.new(1, -100, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "🌱 Farming & Friends",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local minimizeBtn = mk("TextButton", {
    Parent = titleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -64, 0.5, -13),
    BackgroundColor3 = COL.Panel2,
    Text = "–",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    AutoButtonColor = false,
})
corner(minimizeBtn, 6)

local closeBtn = mk("TextButton", {
    Parent = titleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -32, 0.5, -13),
    BackgroundColor3 = COL.Danger,
    Text = "X",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
})
corner(closeBtn, 6)

-- Body split: sidebar + content
local sidebar = mk("Frame", {
    Parent = main,
    Size = UDim2.new(0, 130, 1, -40),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
local content = mk("Frame", {
    Parent = main,
    Size = UDim2.new(1, -130, 1, -40),
    Position = UDim2.new(0, 130, 0, 40),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
})

local tabs = {}
local tabButtons = {}
local activeTab = nil
local selectTab -- forward declaration (defined below, used inside makeTab)

local function makeTab(name, icon)
    local page = mk("ScrollingFrame", {
        Parent = content,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COL.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    })
    mk("UIListLayout", {
        Parent = page,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    mk("UIPadding", {
        Parent = page,
        PaddingTop = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    })

    local btn = mk("TextButton", {
        Parent = sidebar,
        Size = UDim2.new(1, -16, 0, 34),
        Position = UDim2.new(0, 8, 0, 10 + #tabs * 40),
        BackgroundColor3 = COL.Bg,
        Text = icon .. "  " .. name,
        TextColor3 = COL.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        AutoButtonColor = false,
    })
    corner(btn, 6)

    tabButtons[#tabButtons + 1] = { btn = btn, page = page }
    tabs[name] = page

    btn.Activated:Connect(function()
        selectTab(name)
    end)

    return page
end

function selectTab(name)
    for _, t in ipairs(tabButtons) do
        local isActive = (t.page == tabs[name])
        t.page.Visible = isActive
        t.btn.BackgroundColor3 = isActive and COL.Accent or COL.Bg
        t.btn.TextColor3     = isActive and Color3.new(1, 1, 1) or COL.Sub
    end
    activeTab = name
end

------------------------------------------------------------
-- CONTROL BUILDERS
------------------------------------------------------------
local function sectionLabel(parent, text, order)
    local lbl = mk("TextLabel", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "— " .. string.upper(text) .. " —",
        TextColor3 = COL.Sub,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    return lbl
end

local function makeToggle(parent, text, default, callback, order)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    })
    corner(row, 6)
    mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local pill = mk("Frame", {
        Parent = row,
        Size = UDim2.new(0, 38, 0, 20),
        Position = UDim2.new(1, -48, 0.5, -10),
        BackgroundColor3 = COL.Bg,
        BorderSizePixel = 0,
    })
    corner(pill, 10)
    local dot = mk("Frame", {
        Parent = pill,
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = Color3.fromRGB(180, 182, 190),
        BorderSizePixel = 0,
    })
    corner(dot, 7)

    local state = default or false
    local function apply(anim)
        local info = TweenInfo.new(anim and 0.15 or 0, Enum.EasingStyle.Quad)
        TweenService:Create(pill, info, { BackgroundColor3 = state and COL.Accent2 or COL.Bg }):Play()
        TweenService:Create(dot, info, {
            Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
            BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(180, 182, 190),
        }):Play()
    end
    apply(false)

    row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            state = not state
            apply(true)
            task.spawn(callback, state)
        end
    end)

    return {
        Set = function(_, v)
            state = v
            apply(false)
            task.spawn(callback, state)
        end,
        Get = function(_) return state end,
    }
end

local function makeSlider(parent, text, min, max, default, callback, order)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
    })
    corner(row, 6)
    local label = mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -60, 0, 20),
        Position = UDim2.new(0, 12, 0, 5),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local valueLabel = mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(0, 50, 0, 20),
        Position = UDim2.new(1, -62, 0, 5),
        BackgroundTransparency = 1,
        Text = tostring(default),
        TextColor3 = COL.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local bar = mk("Frame", {
        Parent = row,
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 1, -16),
        BackgroundColor3 = COL.Bg,
        BorderSizePixel = 0,
    })
    corner(bar, 3)
    local fill = mk("Frame", {
        Parent = bar,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COL.Accent,
        BorderSizePixel = 0,
    })
    corner(fill, 3)
    local knob = mk("Frame", {
        Parent = bar,
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, -6, 0.5, -6),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    })
    corner(knob, 6)

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local val = min + (max - min) * rel
        val = math.floor(val + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -6, 0.5, -6)
        valueLabel.Text = tostring(val)
        callback(val)
    end
    -- initial position
    do
        local rel = (default - min) / math.max(max - min, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -6, 0.5, -6)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return { Label = label, Value = valueLabel }
end

local function makeButton(parent, text, color, callback, order)
    local btn = mk("TextButton", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = color or COL.Accent,
        Text = text,
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
    })
    corner(btn, 6)
    btn.Activated:Connect(function()
        task.spawn(callback)
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.new(
            math.min(color and color.R or 0.38 + 0.1, 1),
            math.min(color and color.G or 0.74 + 0.1, 1),
            math.min(color and color.B or 0.32 + 0.1, 1)
        ) }):Play()
        task.delay(0.12, function()
            TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = color or COL.Accent }):Play()
        end)
    end)
    return btn
end

local function makeDropdown(parent, text, options, default, callback, order)
    local container = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 5,
    })
    corner(container, 6)
    mk("TextLabel", {
        Parent = container,
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })
    local selected = default or options[1]
    local btn = mk("TextButton", {
        Parent = container,
        Size = UDim2.new(0, 92, 0, 26),
        Position = UDim2.new(1, -102, 0.5, -13),
        BackgroundColor3 = COL.Bg,
        Text = selected .. " ▾",
        TextColor3 = COL.Accent,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 6,
    })
    corner(btn, 5)

    local list = mk("ScrollingFrame", {
        Parent = container,
        Size = UDim2.new(1, -20, 0, 0),
        Position = UDim2.new(0, 10, 1, 4),
        BackgroundColor3 = COL.Panel2,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, #options * 26),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        MaxCanvasSize = Vector2.new(0, 0, 0, 150),
        ClipsDescendants = true,
    })
    corner(list, 6)
    mk("UIListLayout", { Parent = list, Padding = UDim.new(0, 2) })

    for _, opt in ipairs(options) do
        local item = mk("TextButton", {
            Parent = list,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = COL.Bg,
            Text = opt,
            TextColor3 = COL.Text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 21,
        })
        corner(item, 4)
        item.Activated:Connect(function()
            selected = opt
            btn.Text = opt .. " ▾"
            list.Visible = false
            callback(opt)
        end)
    end

    btn.Activated:Connect(function()
        list.Visible = not list.Visible
        container.ZIndex = list.Visible and 50 or 5
    end)

    return { Set = function(_, v) selected = v; btn.Text = v .. " ▾"; callback(v) end }
end

local function makeTextbox(parent, text, default, callback, order)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
    })
    corner(row, 6)
    mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(0.45, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local box = mk("TextBox", {
        Parent = row,
        Size = UDim2.new(0.5, -18, 0, 24),
        Position = UDim2.new(0.5, 6, 0.5, -12),
        BackgroundColor3 = COL.Bg,
        Text = default or "",
        PlaceholderText = "type here...",
        PlaceholderColor3 = COL.Sub,
        TextColor3 = COL.Accent,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = false,
    })
    corner(box, 5)
    box.FocusLost:Connect(function()
        callback(box.Text)
    end)
    return box
end

local function makeInfo(parent, text, order)
    return mk("TextLabel", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
end

------------------------------------------------------------
-- TABS
------------------------------------------------------------
local farmTab    = makeTab("Farm", "🌾")
local playerTab  = makeTab("Player", "🚶")
local tpTab      = makeTab("Teleport", "🧭")
local settingsTab= makeTab("Settings", "⚙")

-- FARM TAB
sectionLabel(farmTab, "Automation", 1)
makeToggle(farmTab, "Auto Harvest", false, function(v)
    Options.AutoHarvest = v
    notify(v and "Auto Harvest ON" or "Auto Harvest OFF")
end, 2)
makeToggle(farmTab, "Auto Plant", false, function(v)
    Options.AutoPlant = v
    notify(v and "Auto Plant ON" or "Auto Plant OFF")
end, 3)
makeToggle(farmTab, "Auto Collect Coins", false, function(v)
    Options.AutoCollect = v
    notify(v and "Auto Collect ON" or "Auto Collect OFF")
end, 4)
makeToggle(farmTab, "Auto Sell", false, function(v)
    Options.AutoSell = v
    Options._lastSell = nil
    notify(v and "Auto Sell ON" or "Auto Sell OFF")
end, 5)
makeToggle(farmTab, "Auto Rebirth", false, function(v)
    Options.AutoRebirth = v
    Options._lastRebirth = nil
    notify(v and "Auto Rebirth ON" or "Auto Rebirth OFF")
end, 6)

sectionLabel(farmTab, "Options", 7)
makeDropdown(farmTab, "Seed", { "Auto", "Carrot", "Tomato", "Strawberry", "Blueberry", "Corn", "Pumpkin", "Watermelon", "Melon", "Grape", "Custom" }, "Auto", function(v)
    Options.SelectedSeed = v
end, 8)
makeSlider(farmTab, "Farm Speed (sec/action)", 1, 20, 5, function(v)
    Options.HarvestDelay = v / 20  -- 0.05 .. 1.0 seconds
end, 9)
makeSlider(farmTab, "Sell Interval (sec)", 5, 120, 20, function(v)
    Options.SellInterval = v
end, 10)
makeButton(farmTab, "💰 Sell Now", COL.Accent2, function()
    doSell()
    notify("Selling...")
end, 11)

-- PLAYER TAB
sectionLabel(playerTab, "Movement", 1)
makeToggle(playerTab, "Custom Walkspeed", false, function(v)
    Options.SpeedEnabled = v
    if not v and Humanoid then Humanoid.WalkSpeed = 16 end
end, 2)
makeSlider(playerTab, "Walkspeed", 16, 200, 16, function(v)
    Options.WalkSpeed = v
end, 3)
makeToggle(playerTab, "Custom Jump Power", false, function(v)
    Options.JumpEnabled = v
    if not v and Humanoid then Humanoid.JumpPower = 50 end
end, 4)
makeSlider(playerTab, "Jump Power", 50, 250, 50, function(v)
    Options.JumpPower = v
end, 5)
makeToggle(playerTab, "Infinite Jump", false, function(v)
    Options.InfiniteJump = v
end, 6)
makeToggle(playerTab, "NoClip (walk through walls)", false, function(v)
    Options.NoClip = v
    notify(v and "NoClip ON" or "NoClip OFF")
end, 7)

sectionLabel(playerTab, "Misc", 8)
makeToggle(playerTab, "Anti-AFK", false, function(v)
    Options.AntiAFK = v
end, 9)
makeToggle(playerTab, "FPS Boost", false, function(v)
    Options.FPSBoost = v
    applyFpsBoost(v)
end, 10)

-- TELEPORT TAB
sectionLabel(tpTab, "Fast Travel", 1)
makeToggle(tpTab, "Ctrl + Click Teleport", false, function(v)
    Options.ClickTeleport = v
    notify(v and "Ctrl+Click to teleport" or "Click TP OFF")
end, 2)
makeButton(tpTab, "🌾 Teleport to Nearest Crop", COL.Accent2, function()
    refreshCaches()
    local target = nearestOf(getRipeCrops()) or nearestOf(cachedPlotFolders)
    if target then
        local p = objPos(target)
        if p then teleportTo(p, 5); notify("Teleported!") end
    else
        notify("No crops found")
    end
end, 3)
makeButton(tpTab, "💰 Teleport to Sell Station", COL.Accent2, function()
    local station = findByNames(Workspace, GameConfig.SellLocations)
    if station then
        local p = objPos(station)
        if p then teleportTo(p, 5); notify("Teleported to sell station!") end
    else
        notify("Sell station not found")
    end
end, 4)
makeButton(tpTab, "🏠 Teleport to Spawn", COL.Accent2, function()
    local spawnLoc = findByNames(Workspace, GameConfig.SpawnLocations) or Workspace:FindFirstChild("SpawnLocation", true)
    if spawnLoc then
        local p = objPos(spawnLoc)
        if p then teleportTo(p, 5); notify("Teleported to spawn!") end
    else
        notify("Spawn not found")
    end
end, 5)
makeButton(tpTab, "🔄 Refresh Folder Scan", COL.Panel2, function()
    refreshCaches()
    notify("Rescanned " .. #cachedPlotFolders .. " plot folder(s), " .. #cachedCoinFolders .. " coin folder(s)")
end, 6)

-- SETTINGS TAB
sectionLabel(settingsTab, "Preferences", 1)
makeToggle(settingsTab, "Notifications", true, function(v)
    Options.Notifications = v
end, 2)

sectionLabel(settingsTab, "Game Config (fix if features miss)", 3)
makeTextbox(settingsTab, "Crop Folder Name", "Crops", function(v)
    if v ~= "" then
        GameConfig.PlotFolders = { v }
        refreshCaches()
        notify("Crop folder set to: " .. v)
    end
end, 4)
makeTextbox(settingsTab, "Remote Hint (harvest)", "harvest", function(v)
    if v ~= "" then
        GameConfig.HarvestRemoteHints = { v:lower() }
        notify("Harvest remote hint set to: " .. v)
    end
end, 5)
makeTextbox(settingsTab, "Remote Hint (sell)", "sell", function(v)
    if v ~= "" then
        GameConfig.SellRemoteHints = { v:lower() }
        notify("Sell remote hint set to: " .. v)
    end
end, 6)

sectionLabel(settingsTab, "Info", 7)
makeInfo(settingsTab, "Press RIGHT SHIFT to show/hide this menu. If crops aren't detected, use a remote spy / explorer to find the current folder and remote names, then update the boxes above.", 8)
makeButton(settingsTab, "⏏ Unload Script", COL.Danger, function()
    screen:Destroy()
    notify("Script unloaded")
end, 9)

------------------------------------------------------------
-- TAB BUTTON WIRING
------------------------------------------------------------
selectTab("Farm")

------------------------------------------------------------
-- WINDOW DRAG / MINIMIZE / CLOSE / KEYBIND
------------------------------------------------------------
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local minimized = false
local fullSize = main.Size
minimizeBtn.Activated:Connect(function()
    minimized = not minimized
    TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
        Size = minimized and UDim2.new(0, 540, 0, 40) or fullSize
    }):Play()
    minimizeBtn.Text = minimized and "+" or "–"
end)

closeBtn.Activated:Connect(function()
    screen.Enabled = not screen.Enabled
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        screen.Enabled = not screen.Enabled
    end
end)

-- Clean up on unload
screen.Destroying:Connect(function()
    Options.AutoHarvest = false
    Options.AutoPlant = false
    Options.AutoCollect = false
    Options.AutoSell = false
    Options.AutoRebirth = false
    Options.NoClip = false
    if Humanoid then
        Humanoid.WalkSpeed = 16
        Humanoid.JumpPower = 50
    end
end)
