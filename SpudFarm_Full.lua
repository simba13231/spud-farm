-- Spud Farm — CLEAN REBUILD (skeleton)
-- Every feature is being re-added ONE AT A TIME and tested in-game before
-- the next one goes in. THIS BUILD CONTAINS NO GAME FEATURES:
--   · GUI shell: window, drag by title bar, X to hide, 🥔 / Right Shift to show
--   · console log (also printed to the executor console)
--   · 🔄 reload: fetches the newest build from GitHub (no re-pasting)
-- It touches NOTHING: no movement, no keys, no workspace/lighting edits.
-- The previous full version is kept in git history if we ever need it.

local Players     = game:GetService("Players")
local UIS         = game:GetService("UserInputService")
local StarterGui  = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer or Players:GetPlayerAdded():Wait()

local VERSION = "rebuild v0 · skeleton"

------------------------------------------------------------
-- notify + log
------------------------------------------------------------
local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "SPUD FARM",
            Text = tostring(msg),
            Duration = 4,
        })
    end)
end

local LOG_LINES = {}
local MAX_LINES = 60
local logFrame -- built below; log() is only called after the GUI exists

local function log(msg)
    local t = os.date("*t")
    local line = string.format("[%02d:%02d:%02d] %s", t.hour, t.min, t.sec, tostring(msg))
    table.insert(LOG_LINES, line)
    if #LOG_LINES > MAX_LINES then table.remove(LOG_LINES, 1) end
    print("[spud] " .. tostring(msg))
    if logFrame then
        for _, child in ipairs(logFrame:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        for i, l in ipairs(LOG_LINES) do
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -4, 0, 15)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 11
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextColor3 = l:find("ERROR", 1, true)
                and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(200, 205, 215)
            lbl.Text = l
            lbl.LayoutOrder = i
            lbl.Parent = logFrame
        end
        pcall(function() logFrame.CanvasPosition = Vector2.new(0, 100000) end)
    end
end

------------------------------------------------------------
-- GUI helpers
------------------------------------------------------------
local COL = {
    Bg      = Color3.fromRGB(18, 19, 23),
    Panel   = Color3.fromRGB(26, 28, 34),
    Panel2  = Color3.fromRGB(36, 39, 47),
    Accent  = Color3.fromRGB(120, 200, 90),
    Text    = Color3.fromRGB(235, 238, 245),
    Sub     = Color3.fromRGB(150, 155, 168),
    Red     = Color3.fromRGB(200, 70, 70),
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
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
end

local function guiParent()
    local ok, pg = pcall(function() return LocalPlayer:FindFirstChildOfClass("PlayerGui") end)
    if ok and pg then return pg end
    return game:GetService("CoreGui")
end

------------------------------------------------------------
-- window
------------------------------------------------------------
local screen = mk("ScreenGui", {
    Name = "SpudScreen",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = guiParent(),
})

local main = mk("Frame", {
    Size = UDim2.fromOffset(380, 470),
    Position = UDim2.fromOffset(12, 70),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
    Parent = screen,
})
corner(main, 12)
mk("UIStroke", { Color = Color3.fromRGB(60, 64, 74), Thickness = 1, Parent = main })

local titleBar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
    Parent = main,
})
corner(titleBar, 12)
mk("Frame", { -- square off the title bar's bottom corners
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
    Parent = titleBar,
})

mk("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1,
    Text = "SPUD FARM · " .. VERSION,
    TextColor3 = COL.Accent,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = titleBar,
})

local hideBtn = mk("TextButton", {
    Size = UDim2.fromOffset(26, 26),
    Position = UDim2.new(1, -32, 0.5, -13),
    BackgroundColor3 = COL.Red,
    Text = "X",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = true,
    Parent = titleBar,
})
corner(hideBtn, 6)

local content = mk("Frame", {
    Size = UDim2.new(1, 0, 1, -40),
    Position = UDim2.fromOffset(0, 40),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
    Parent = main,
})

mk("TextLabel", {
    Size = UDim2.new(1, -20, 0, 18),
    Position = UDim2.fromOffset(10, 8),
    BackgroundTransparency = 1,
    Text = "CONSOLE — features return one at a time",
    TextColor3 = COL.Sub,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = content,
})

logFrame = mk("ScrollingFrame", {
    Size = UDim2.new(1, -20, 1, -76),
    Position = UDim2.fromOffset(10, 30),
    BackgroundColor3 = Color3.fromRGB(13, 14, 17),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COL.Accent,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    Parent = content,
})
corner(logFrame, 6)
mk("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = logFrame })
mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = logFrame })

local reloadBtn = mk("TextButton", {
    Size = UDim2.new(1, -20, 0, 32),
    Position = UDim2.new(0, 10, 1, -40),
    BackgroundColor3 = COL.Accent,
    Text = "🔄 Reload latest update",
    TextColor3 = Color3.fromRGB(15, 22, 12),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = true,
    Parent = content,
})
corner(reloadBtn, 8)

local potatoBtn = mk("TextButton", {
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 10, 0.5, -22),
    BackgroundColor3 = COL.Panel2,
    Text = "🥔",
    TextSize = 20,
    AutoButtonColor = true,
    Parent = screen,
})
corner(potatoBtn, 14)
mk("UIStroke", { Color = COL.Accent, Thickness = 1.5, Parent = potatoBtn })

------------------------------------------------------------
-- show/hide (X or 🥔 or Right Shift — UI can never get stuck)
------------------------------------------------------------
local UIState = { hidden = false }

local function toggleUI()
    UIState.hidden = not UIState.hidden
    main.Visible = not UIState.hidden
    log(UIState.hidden and "UI hidden — press 🥔 or RIGHT SHIFT to show" or "UI shown")
end

hideBtn.Activated:Connect(toggleUI)
potatoBtn.Activated:Connect(toggleUI)
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        toggleUI()
    end
end)

-- drag by title bar
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- mobile: scale to fit + center
if UIS.TouchEnabled then
    local scale = mk("UIScale", { Parent = main })
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    local function fit()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
        scale.Scale = math.clamp(math.min(vp.X / 460, vp.Y / 560), 0.55, 1.1)
        main.Position = UDim2.fromScale(0.5, 0.5)
    end
    fit()
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
    end
    task.delay(2, fit)
end

------------------------------------------------------------
-- 🔄 reload — newest build straight from GitHub, no re-paste
------------------------------------------------------------
local SCRIPT_URL = "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua"

local function doReload()
    log("fetching latest build…")
    local ok, src = pcall(function() return game:HttpGet(SCRIPT_URL) end)
    if not ok or type(src) ~= "string" or #src < 100 then
        log("ERROR fetch failed — keeping current version")
        notify("Update fetch failed — keeping current version")
        return
    end
    log("running latest build…")
    screen:Destroy()
    local ok2, err2 = pcall(function()
        local chunk, lerr = loadstring(src)
        if not chunk then error(lerr or "loadstring failed") end
        chunk()
    end)
    if not ok2 then warn("[spud] reload error: " .. tostring(err2)) end
end

reloadBtn.Activated:Connect(doReload)

------------------------------------------------------------
-- start
------------------------------------------------------------
log("skeleton loaded — " .. VERSION)
log("no game features yet; they come back one at a time")
notify("SPUD FARM rebuilt — skeleton only")
