--------------------------------------------------------------------
-- SpudCapture — RESPAWN REMOTE ARGS (§29) with its own DEBUG GUI
-- v4: PARENT FIX — the window now lives in gethui()/CoreGui like
-- every executor UI library (the farming script's Fluent window is
-- there too), because games may SWEEP unknown ScreenGuis out of
-- PlayerGui — the classic "built but never shows" trap. v3's
-- diagnostics stay (boot line first, pcall'd build, exact-error
-- report, console-only fallback) + a 2s watchdog reports if anything
-- destroys the window anyway.
--
-- WHY: the menu flow (open manager -> card -> Spawn) takes ~8-10 s of
-- mouse work. The game must be firing a REMOTE to do the respawn
-- (dump §28 found FNCRespawnEquipment / FNCForceRespawnEquipment).
-- If we know that remote's EXACT arguments, the farming script can
-- fire it directly — no menu, no clicks, instant.
--
-- RUN: paste + execute, then do the video's 3 clicks ONCE by hand:
--   1) open the Equipment Manager  2) click the ZM80 card
--   3) click Spawn            -> press COPY -> paste it back.
-- Changes NO game state — it only watches.
--------------------------------------------------------------------

print("[SpudCapture] boot v4 — building capture window")

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

-- ▸ WHERE THE WINDOW LIVES: gethui() (hidden, game can't see it) →
--   CoreGui (games can't sweep it) → PlayerGui only as last resort
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

-- kill any window from an earlier run, wherever it lives
pcall(function()
    local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
    for _, container in ipairs({ holder, pg, game:GetService("CoreGui") }) do
        if container then
            local prior = container:FindFirstChild("SpudCaptureGui")
            if prior then prior:Destroy() end
        end
    end
end)

local status, refresh, guiRef

-- ▸ THE WINDOW — built inside pcall so ANY failure is reported and
--   degrades to console-only capture instead of dying silently ------
local okBuild, errBuild = pcall(function()
    local gui = mk("ScreenGui", {
        Name = "SpudCaptureGui",
        ResetOnSpawn = false,
        DisplayOrder = 9999,
    }, holder)
    guiRef = gui

    local frame = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(440, 300),
        BackgroundColor3 = Color3.fromRGB(23, 23, 23),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
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
        Size = UDim2.new(1, -160, 1, 0),
        BackgroundTransparency = 1,
        Text = "SPAWN CAPTURE",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    status = mk("TextLabel", {
        Position = UDim2.new(1, -160, 0, 0),
        Size = UDim2.new(0, 118, 1, 0),
        BackgroundTransparency = 1,
        Text = "starting…",
        TextColor3 = Color3.fromRGB(160, 160, 160),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
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
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy() -- the console [SPAWNWATCH …] backup keeps working
    end)

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
    logLabel.Parent = logScroll -- label lives INSIDE the scroller

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

    refresh = function()
        logLabel.Text = table.concat(lines, "\n")
    end

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
    print("[SpudCapture] ✔ window up under " .. holderName
        .. " (440×300, centre screen, drag by title)")
end)
if not okBuild then
    warn("[SpudCapture] ✘ WINDOW BUILD FAILED: " .. tostring(errBuild))
    warn("[SpudCapture] falling back to CONSOLE-ONLY — watch [SPAWNWATCH …] lines")
end

-- watchdog: did anything destroy it after the fact?
task.delay(2, function()
    if not guiRef then return end
    if not guiRef.Parent then
        warn("[SpudCapture] ✘ window VANISHED after 2s — something destroyed"
            .. " it (game sweeping " .. holderName .. "?)")
    else
        print("[SpudCapture] ✔ window still alive under " .. holderName .. " (+2s)")
    end
end)

local function refreshSafe()
    if refresh then pcall(refresh) end
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

-- remotes the menu flow plausibly calls by NAME, plus any call whose
-- STRING args mention a known model (catches an oddly-named remote)
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

if status then
    status.Text = okHook and "CAPTURE ON" or "HOOK FAILED"
    status.TextColor3 = okHook and Color3.fromRGB(60, 200, 110)
        or Color3.fromRGB(240, 80, 80)
end
if not okHook then
    warn("[SPAWNWATCH] hook FAILED: " .. tostring(errHook))
end

print("══════ SPAWN ARGS CAPTURE (§29 v4) ══════")
print("holder:  " .. holderName)
print(okBuild and "window: ✔ built" or "window: ✘ FAILED (error above)")
print(okHook and "capture: ✔ ON — 3 clicks once (menu → ZM80 card →"
    .. " Spawn), then press COPY" or ("capture: ✘ hook FAILED: "
    .. tostring(errHook)))
print("══════════════════════════════════════")
