--------------------------------------------------------------------
-- SpudCapture — RESPAWN REMOTE ARGS (§29) with its own DEBUG GUI
-- v5: COLLAPSE-TO-PILL + MENU CARD COUNTER.
--   * user report: "it makes the tractor and tools in the ui go away
--     and i dont see them" — v4 spawned 440×300 DEAD CENTRE at
--     DisplayOrder 9999, exactly on top of the Equipment Manager's
--     card grid. v5 STARTS COLLAPSED as a small pill (bottom-left);
--     nothing covers the menu. Tap the pill to expand, "–" to
--     collapse, ✕ to close. The pill shows the live line count.
--   * SELF-DIAGNOSTIC: when GarageMenu opens the script COUNTS the
--     cards itself and flashes "MENU: N CARDS" (green) / "MENU: 0
--     CARDS" (red) on pill + status chip + console. N>0 = cards were
--     only being COVERED before; N=0 = menu really empty (then the
--     hook is the suspect, not the window).
-- v4 fixes stay: window lives in gethui()/CoreGui (games sweep
-- unknown PlayerGui ScreenGuis), 2s alive/vanished watchdog,
-- pcall'd build with console-only fallback, boot line first.
--
-- RUN: loadstring(game:HttpGet("…/SpudCapture.lua"))()
-- Then: collapse (–) → your video's 3 clicks (menu → ZM80 card →
-- Spawn) → expand → COPY → paste it back.
-- Changes NO game state — it only watches.
--------------------------------------------------------------------

print("[SpudCapture] boot v5 — building capture window")

_G.SpudCaptureSeq = (_G.SpudCaptureSeq or 0) + 1
local mySeq = _G.SpudCaptureSeq
local lines = _G.SpudCaptureLog or {}
_G.SpudCaptureLog = lines

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

-- ▸ WHERE THE WINDOW LIVES: gethui() → CoreGui → PlayerGui fallback
local holder, holderName
pcall(function()
    if type(gethui) == "function" then holder = gethui() end
end)
if holder then
    holderName = "gethui()"
else
    local okCG, cg = pcall(function() return game:GetService("CoreGui") end)
    if okCG and cg then
        holder, holderName = cg, "CoreGui"
    else
        holder = Players.LocalPlayer:WaitForChild("PlayerGui")
        holderName = "PlayerGui (FALLBACK — sweep risk)"
    end
end
print("[SpudCapture] holder: " .. holderName)

pcall(function()
    local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
    for _, container in ipairs({ holder, pg, game:GetService("CoreGui") }) do
        if container then
            local prior = container:FindFirstChild("SpudCaptureGui")
            if prior then prior:Destroy() end
        end
    end
end)

local status, pill, refresh, hookOK

-- ▸ THE WINDOW — starts COLLAPSED (pill) so it never covers the menu
local okBuild, errBuild = pcall(function()
    local gui = mk("ScreenGui", {
        Name = "SpudCaptureGui",
        ResetOnSpawn = false,
        DisplayOrder = 9999,
    }, holder)

    -- the pill: small, bottom-left, always out of the menu's way
    pill = mk("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 14, 1, -48),
        Size = UDim2.fromOffset(190, 32),
        BackgroundColor3 = Color3.fromRGB(31, 31, 31),
        BorderSizePixel = 0,
        Text = "SPAWN CAPTURE (0)",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        Visible = true,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 16) }, pill)
    mk("UIStroke", { Color = Color3.fromRGB(0, 120, 212), Thickness = 1 }, pill)

    local frame = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(440, 300),
        BackgroundColor3 = Color3.fromRGB(23, 23, 23),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
        Visible = false, -- STARTS COLLAPSED — nothing covers the menu
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
    mk("UIStroke", { Color = Color3.fromRGB(42, 42, 42), Thickness = 1 }, frame)

    local titleBar = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Color3.fromRGB(31, 31, 31),
        BorderSizePixel = 0,
    }, frame)
    mk("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -195, 1, 0),
        BackgroundTransparency = 1,
        Text = "SPAWN CAPTURE",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    status = mk("TextLabel", {
        Position = UDim2.new(1, -185, 0, 0),
        Size = UDim2.new(0, 112, 1, 0),
        BackgroundTransparency = 1,
        Text = "starting…",
        TextColor3 = Color3.fromRGB(160, 160, 160),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, titleBar)

    local collapseBtn = mk("TextButton", {
        Position = UDim2.new(1, -66, 0, 5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "–",
        TextColor3 = Color3.fromRGB(180, 180, 180),
        TextSize = 16,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
    }, titleBar)

    local closeBtn = mk("TextButton", {
        Position = UDim2.new(1, -34, 0, 5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "✕",
        TextColor3 = Color3.fromRGB(180, 180, 180),
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
    }, titleBar)

    local logLabel = mk("TextLabel", {
        Position = UDim2.new(0, 8, 0, 42),
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Color3.fromRGB(210, 210, 210),
        TextSize = 13,
        Font = Enum.Font.Code,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, frame)

    local logScroll = mk("ScrollingFrame", {
        Position = UDim2.new(0, 8, 0, 42),
        Size = UDim2.new(1, -16, 1, -88),
        BackgroundColor3 = Color3.fromRGB(14, 14, 14),
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, frame)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, logScroll)
    logLabel.Parent = logScroll

    local copyBtn = mk("TextButton", {
        Position = UDim2.new(0, 8, 1, -40),
        Size = UDim2.new(1, -16, 0, 32),
        BackgroundColor3 = Color3.fromRGB(0, 120, 212),
        Text = "COPY",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    }, frame)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, copyBtn)

    local function setExpanded(on)
        frame.Visible = on
        pill.Visible = not on
    end

    refresh = function()
        logLabel.Text = table.concat(lines, "\n")
        if pill.Visible then
            pill.Text = "SPAWN CAPTURE (" .. #lines .. ")"
        end
    end

    pill.MouseButton1Click:Connect(function() setExpanded(true) end)
    collapseBtn.MouseButton1Click:Connect(function() setExpanded(false) end)
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy() -- the console [SPAWNWATCH …] backup keeps working
    end)

    copyBtn.MouseButton1Click:Connect(function()
        if #lines == 0 then
            copyBtn.Text = "NOTHING YET"
        else
            local ok = pcall(setclipboard, table.concat(lines, "\n"))
            copyBtn.Text = ok and "COPIED" or "NO CLIPBOARD"
        end
        task.delay(1.4, function()
            if copyBtn.Parent then copyBtn.Text = "COPY" end
        end)
    end)

    -- drag by the title bar (mouse on PC, touch in MuMu)
    local dragging, dStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging, dStart, startPos = true, inp.Position, frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
            local d = inp.Position - dStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    refresh()
    print("[SpudCapture] ✔ pill up under " .. holderName
        .. " (bottom-left; tap to expand, – collapses, ✕ closes)")
end)
if not okBuild then
    warn("[SpudCapture] ✘ WINDOW BUILD FAILED: " .. tostring(errBuild))
    warn("[SpudCapture] falling back to CONSOLE-ONLY — watch [SPAWNWATCH …] lines")
end

task.delay(2, function()
    if not pill and not status then return end -- build failed: console-only
    local gui = pill and pill.Parent or (status and status:FindFirstAncestorWhichIsA("ScreenGui"))
    if not gui then return end
    if not gui.Parent then
        warn("[SpudCapture] ✘ window VANISHED after 2s — something destroyed it")
    else
        print("[SpudCapture] ✔ window still alive (+2s)")
    end
end)

local function refreshSafe()
    if refresh then pcall(refresh) end
end

-- ▸ STATUS FLASH (also answers the "cards gone" question) ----------
local flashTok = 0
local function restoreBase()
    if pill then
        pill.Text = "SPAWN CAPTURE (" .. #lines .. ")"
        pill.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    if status then
        status.Text = hookOK and "CAPTURE ON" or "HOOK FAILED"
        status.TextColor3 = hookOK and Color3.fromRGB(60, 200, 110)
            or Color3.fromRGB(240, 80, 80)
    end
end
local function flash(msg, good)
    flashTok += 1
    local my = flashTok
    local col = good and Color3.fromRGB(60, 200, 110)
        or Color3.fromRGB(240, 80, 80)
    if pill then
        pill.Text = msg
        pill.TextColor3 = col
    end
    if status then
        status.Text = msg
        status.TextColor3 = col
    end
    task.delay(5, function()
        if flashTok == my then restoreBase() end
    end)
end

-- ▸ ARG PRINTER (dump §28's summarize, returns the string) ---------
local function summarizeArgs(...)
    local parts = {}
    for i, v in ipairs({...}) do
        local t = typeof(v)
        local s
        if t == "table" then
            local n = 0
            for _ in pairs(v) do n += 1 end
            s = "table{" .. n .. "}: "
            local shown = 0
            for k, val in pairs(v) do
                shown += 1
                if shown > 8 then s = s .. "…"; break end
                s = s .. tostring(k) .. "=" .. tostring(val) .. " "
            end
        elseif t == "string" then
            s = string.format("string(%d) %q", #v, string.sub(v, 1, 200))
        elseif t == "Instance" then
            s = "Instance " .. v:GetFullName()
        else
            s = t .. "=" .. tostring(v)
        end
        parts[#parts + 1] = "[" .. i .. "] " .. s
    end
    return table.concat(parts, "  ")
end

local KEYS = { "respawn", "spawn", "store", "equip", "garage",
    "manager", "select", "hitch" }
local MODELS = { "ZM80", "KADL", "KQF3000", "SRC6", "R150", "S4204", "Trailer" }

local function interesting(nm, ...)
    local nml = nm:lower()
    for _, k in ipairs(KEYS) do
        if nml:find(k, 1, true) then return true end
    end
    for _, a in ipairs({...}) do
        if type(a) == "string" then
            for _, m in ipairs(MODELS) do
                if a:find(m, 1, true) then return true end
            end
        end
    end
    return false
end

local function addLine(method, nm, ...)
    if mySeq ~= _G.SpudCaptureSeq then return end -- an older run's hook stays silent
    local s = string.format("#%d [SPAWNWATCH %s %s] %s",
        #lines + 1, method, nm, summarizeArgs(...))
    lines[#lines + 1] = s
    warn(s) -- console backup, in case the window is closed
    refreshSafe()
end

local okHook, errHook = pcall(function()
    local oldHook
    oldHook = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local nm, meth = tostring(self.Name), getnamecallmethod()
        if (meth == "FireServer" or meth == "InvokeServer")
            and interesting(nm, ...) then
            pcall(addLine, meth, nm, ...)
        end
        return oldHook(self, ...)
    end))
end)
hookOK = okHook
restoreBase()
if not okHook then
    warn("[SPAWNWATCH] hook FAILED: " .. tostring(errHook))
end

-- ▸ MENU CARD COUNTER — when the Equipment Manager opens, count the
--   cards: N>0 = they were only being COVERED before; N=0 = the menu
--   is really empty (then the hook, not the window, is the suspect)
local okWatch, errWatch = pcall(function()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gv = pg:WaitForChild("GuiViews", 5)
    local menus = gv and gv:WaitForChild("Menus", 5)
    local menu = menus and menus:FindFirstChild("GarageMenu")
    assert(menu, "GarageMenu not found under GuiViews.Menus")
    local function countCards()
        local bg = menu:FindFirstChild("Background")
        local content = bg and bg:FindFirstChild("Content")
        local cards = content and content:FindFirstChild("Cards")
        if not cards then return nil end
        local n = 0
        for _, d in ipairs(cards:GetDescendants()) do
            if d:IsA("ImageButton") and d:FindFirstChild("EquipmentName") then
                n += 1
            end
        end
        return n
    end
    menu:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not menu.Enabled then return end
        local n = countCards()
        warn("[SPAWNWATCH] GarageMenu opened — "
            .. (n and (n .. " cards") or "card count FAILED"))
        if n then
            flash("MENU: " .. n .. " CARDS", n > 0)
        else
            flash("MENU: ? CARDS", false)
        end
    end)
end)
if not okWatch then
    warn("[SpudCapture] menu watcher FAILED: " .. tostring(errWatch))
end

print("══════ SPAWN ARGS CAPTURE (§29 v5) ══════")
print("holder:  " .. holderName)
print(okBuild and "window:  ✔ PILL bottom-left (tap to expand)"
    or "window:  ✘ FAILED (error above)")
print(okWatch and "watcher: ✔ GarageMenu card counter ON"
    or ("watcher: ✘ " .. tostring(errWatch)))
print(okHook and "capture: ✔ ON — collapse (–) → 3 clicks → expand → COPY"
    or ("capture: ✘ hook FAILED: " .. tostring(errHook)))
print("══════════════════════════════════════")
