--------------------------------------------------------------------
-- SpudCapture — RESPAWN REMOTE ARGS (§29 v7, HOOK-FREE)
--
-- v6 A/B RESULT (user: "it wroks now"): with NO namecall hook the
-- Equipment Manager's card list works again → the hook was proven
-- guilty (it killed InvokeServer data returns the cards depend on).
-- v7 therefore installs NO hook at all. Instead it uses the hook-free
-- path: when you expand a card, the Spawn button's OWN click handler
-- connections are read (getconnections) and the handler's UPVALUES
-- are printed (debug.getupvalues) — the game's module-scope remote
-- reference (FNCRespawnEquipment) and selected-vehicle state live in
-- there. Read-only; cannot affect game data.
--
-- v7.1: the Spawn button is found RECURSIVELY under Background.Content
-- (the dump's full path showed it nested — Cards.1.ExpandedCard… — so
-- the v7 direct-child lookup found nothing and the user got an empty
-- buffer: "nothing yet even tho i spawned the vehicle"); polls start
-- even if the menu was already open; an "armed" line proves the buffer
-- works; poll ticks are pcall'd so one error can't kill the loop.
--
-- RUN: loadstring(game:HttpGet("…/SpudCapture.lua"))()
-- FLOW: open the Equipment Manager → click the ZM80 card (expand) →
-- the pill flashes "SPAWN: n handler(s) read" → expand the pill →
-- press COPY → paste it back. Rejoin NOT required (no hooks).
--------------------------------------------------------------------

print("[SpudCapture] boot v7.3 — hook-free capture (ancestor handlers + deep upvalue walk + GC remote sweep)")

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

-- ▸ CAPABILITIES (printed first — decides if the read is possible) --
local hasGetConn = pcall(function()
    assert(type(getconnections) == "function", "no getconnections")
end)
local hasDebug = pcall(function()
    assert(type(debug) == "table"
        and (type(debug.getupvalues) == "function"
            or type(debug.getupvalue) == "function"), "no debug upvalues")
end)
local hasGetGc = pcall(function()
    assert(type(getgc) == "function", "no getgc")
end)
print("[SpudCapture] getconnections: " .. (hasGetConn and "yes"
    or "NO — handler read unavailable"))
print("[SpudCapture] debug upvalues: " .. (hasDebug and "yes" or "NO"))
print("[SpudCapture] getgc: " .. (hasGetGc and "yes" or "NO"))

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

local status, pill, refresh, baseText, baseColor, flashTok

-- ▸ THE WINDOW — starts COLLAPSED (pill) so it never covers the menu
local okBuild, errBuild = pcall(function()
    local gui = mk("ScreenGui", {
        Name = "SpudCaptureGui",
        ResetOnSpawn = false,
        DisplayOrder = 9999,
    }, holder)

    pill = mk("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 14, 1, -48),
        Size = UDim2.fromOffset(210, 32),
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
        if pill.Visible and flashTok == 0 then -- never clobber a flash
            pill.Text = "SPAWN CAPTURE (" .. #lines .. ")"
        end
    end

    pill.MouseButton1Click:Connect(function() setExpanded(true) end)
    collapseBtn.MouseButton1Click:Connect(function() setExpanded(false) end)
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy() -- lines stay in _G, console backup unaffected
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
    warn("[SpudCapture] falling back to CONSOLE-ONLY — watch [SPAWNBTN …] lines")
end

task.delay(2, function()
    local gui = pill and pill.Parent
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

-- ▸ STATUS FLASH --------------------------------------------------
flashTok = 0
local function restoreBase()
    if pill then
        pill.Text = "SPAWN CAPTURE (" .. #lines .. ")"
        pill.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    if status then
        status.Text = baseText or "starting…"
        status.TextColor3 = baseColor or Color3.fromRGB(160, 160, 160)
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

local function pushLine(text)
    lines[#lines + 1] = text
    warn(text) -- console backup too
    refreshSafe()
end

-- ▸ VALUE DESCRIPTOR (upvalue printer, depth-capped) ---------------
local function desc(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then
        local okN, full = pcall(function() return v:GetFullName() end)
        return "Instance " .. (okN and full or tostring(v.Name))
    elseif t == "table" then
        if depth >= 2 then return "table{…}" end
        local n = 0
        for _ in pairs(v) do n += 1 end
        local parts, shown = {}, 0
        for k, val in pairs(v) do
            shown += 1
            if shown > 8 then parts[#parts + 1] = "…"; break end
            parts[#parts + 1] = tostring(k) .. "=" .. desc(val, depth + 1)
        end
        return "table{" .. n .. "}: " .. table.concat(parts, ", ")
    elseif t == "string" then
        return string.format("string(%d) %q", #v, string.sub(v, 1, 140))
    else
        return t .. "=" .. tostring(v)
    end
end

local function readUpvalues(fn)
    local out = {}
    -- PRIMARY: debug.getupvalue(fn, i) → name, value (standard Lua shape;
    -- each step pcall'd so impls that error past the last index don't die)
    pcall(function()
        if type(debug.getupvalue) == "function" then
            for i = 1, 64 do
                local okI, nm, val = pcall(debug.getupvalue, fn, i)
                if not okI then break end
                if type(nm) ~= "string" then break end -- nil = exhausted
                out[#out + 1] = { name = nm, value = val }
            end
        end
    end)
    if #out > 0 then return out end
    -- SECONDARY: debug.getupvalues(fn) — SHAPE-AGNOSTIC. Delta can return
    -- raw VALUES in the array rather than {name,value} tables → guard by
    -- typeof instead of indexing a possible number/string ("index number
    -- with 'name'" crash). Handles {name,value}, array-form, and bare values.
    local okT, res = pcall(function() return debug.getupvalues(fn) end)
    if okT and type(res) == "table" then
        for i, u in ipairs(res) do
            local nm, val
            if type(u) == "table" then
                if u.name ~= nil or u.value ~= nil then
                    nm, val = u.name, u.value
                elseif u.Name ~= nil or u.Value ~= nil then
                    nm, val = u.Name, u.Value
                elseif u[1] ~= nil then
                    nm, val = tostring(u[1]), u[2]
                else
                    nm, val = "?" .. i, u
                end
            else
                nm, val = "?" .. i, u
            end
            out[i] = { name = tostring(nm), value = val }
        end
    end
    return out
end

-- ▸ DEEP WALK: read a function's upvalues, then recurse ONE level into
-- any upvalue function so a wrapper's inner closure gets read too.
local function deepRead(fn, tag, seen, level)
    level = level or 0
    if seen[fn] or level > 1 then return end
    seen[fn] = true
    if not hasDebug then return end
    local uvs = readUpvalues(fn)
    if #uvs == 0 then
        pushLine("[SPAWNBTN]   " .. tag .. " (no upvalues)")
    end
    for i, u in ipairs(uvs) do
        pushLine(string.format("[SPAWNBTN]   %s [%d] %s = %s",
            tag, i, u.name, desc(u.value)))
        if type(u.value) == "function" then
            deepRead(u.value, tag .. "." .. i, seen, level + 1)
        end
    end
end

-- ▸ THE SPAWN BUTTON READER — no hooks, pure reads -----------------
local spawnAnalyzed = false
local function analyzeSpawn(btn)
    if spawnAnalyzed then return end
    spawnAnalyzed = true
    local okN, full = pcall(function() return btn:GetFullName() end)
    pushLine("[SPAWNBTN] Spawn button: " .. (okN and full or btn.Name))

    if not hasGetConn then
        pushLine("[SPAWNBTN] getconnections NOT available — handlers unreadable")
        flash("SPAWN: no getconnections", false)
        return
    end

    local events = { "Activated", "MouseButton1Click", "MouseButton1Down", "InputBegan" }
    local fns = {} -- fn -> { event names }
    -- walk the button AND its ancestors: the real click handler often lives
    -- on the Actions/Content/GarageMenu frame, not the TextButton itself
    local seenObj, obj, hop = {}, btn, 0
    while obj and hop < 5 do
        seenObj[obj] = true
        local label = (hop == 0) and "button" or ("ancestor " .. tostring(obj.Name))
        for _, ev in ipairs(events) do
            local okC, conns = pcall(function() return getconnections(obj[ev]) end)
            if okC and conns then
                for _, c in ipairs(conns) do
                    local f = c.Function
                    if f then
                        fns[f] = fns[f] or {}
                        table.insert(fns[f], ev .. "@" .. label)
                    end
                end
            end
        end
        obj = obj.Parent
        hop += 1
    end

    if next(fns) == nil then
        pushLine("[SPAWNBTN] no connections on the button or ancestors")
        flash("SPAWN: 0 connections", false)
        return
    end

    local seenFn, nFn = {}, 0
    for f, evs in pairs(fns) do
        nFn += 1
        pushLine("[SPAWNBTN] handler " .. tostring(f) .. " on " .. table.concat(evs, "+"))
        deepRead(f, "", seenFn, 0)
    end
    flash("SPAWN: " .. nFn .. " handler(s) read", true)
    -- the handler above was a shallow wrapper (sound + timestamp); go find
    -- the actual respawn remote directly in the heap so we don't miss it
    gcSweep()
end

-- ▸ GC SWEEP: hunt the respawn remote(s) by name across every live object.
-- This is the guaranteed path if the button handler is a shallow wrapper
-- that only holds a sound module + timestamp (as v7.2 observed).
local function gcSweep()
    if not hasGetGc then
        pushLine("[SWEEP] getgc NOT available")
        return
    end
    local KEYS = { "FNCRespawnEquipment", "FNCForceRespawnEquipment", "RespawnEquipment" }
    local seen, hits = {}, {}
    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if typeof(v) == "Instance" and v:IsA("RemoteEvent") then
                local n = v.Name
                for _, k in ipairs(KEYS) do
                    if n == k or (n:find(k, 1, true)) then
                        if not seen[v] then
                            seen[v] = true
                            hits[#hits + 1] = v
                        end
                    end
                end
            elseif typeof(v) == "table" and not seen[v] then
                seen[v] = true
                for kk, vv in pairs(v) do
                    if typeof(vv) == "Instance"
                        and (vv:IsA("RemoteEvent") or vv:IsA("RemoteFunction")) then
                        for _, k in ipairs(KEYS) do
                            if vv.Name:find(k, 1, true) or tostring(kk):find(k, 1, true) then
                                hits[#hits + 1] = vv
                            end
                        end
                    end
                end
            end
        end
    end)
    if #hits == 0 then
        pushLine("[SWEEP] no respawn remote found in GC")
    else
        pushLine("[SWEEP] respawn remotes (" .. #hits .. "):")
        for _, r in ipairs(hits) do
            local okF, full = pcall(function() return r:GetFullName() end)
            pushLine("[SWEEP]   " .. tostring(r.ClassName) .. " "
                .. (okF and full or r.Name))
        end
    end
end

-- ▸ MENU WATCHER: card count flash + Spawn-button reader -----------
local okWatch, errWatch = pcall(function()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gv = pg:WaitForChild("GuiViews", 5)
    local menus = gv and gv:WaitForChild("Menus", 5)
    local menu = menus and menus:FindFirstChild("GarageMenu")
    assert(menu, "GarageMenu not found under GuiViews.Menus")

    local function cardsRoot()
        local bg = menu:FindFirstChild("Background")
        local content = bg and bg:FindFirstChild("Content")
        return content and content:FindFirstChild("Cards")
    end
    local function countCards()
        local cards = cardsRoot()
        if not cards then return nil end
        local n = 0
        for _, d in ipairs(cards:GetDescendants()) do
            if d:IsA("ImageButton") and d:FindFirstChild("EquipmentName") then
                n += 1
            end
        end
        return n
    end

    local function startPoll()
        local n = countCards()
        warn("[SPAWNBTN] GarageMenu open — "
            .. (n and (n .. " cards") or "card count FAILED"))
        if n then
            flash("MENU: " .. n .. " CARDS", n > 0)
        else
            flash("MENU: ? CARDS", false)
        end
        task.spawn(function()
            while menu.Enabled do
                local okT, errT = pcall(function()
                    local bg = menu:FindFirstChild("Background")
                    local content = bg and bg:FindFirstChild("Content")
                    if not content then return end
                    -- RECURSIVE: the dump's full path showed the expanded
                    -- card NESTED (Cards.1.ExpandedCard…) — find Spawn
                    -- anywhere under Content, by name OR by its text
                    local spawnBtn = content:FindFirstChild("Spawn", true)
                    if not (spawnBtn and spawnBtn:IsA("GuiButton")) then
                        spawnBtn = nil
                        for _, d in ipairs(content:GetDescendants()) do
                            if d:IsA("GuiButton")
                                and (d.Name == "Spawn"
                                    or (d:IsA("TextButton") and d.Text == "Spawn")) then
                                spawnBtn = d
                                break
                            end
                        end
                    end
                    if spawnBtn then
                        analyzeSpawn(spawnBtn)
                    end
                end)
                if not okT then
                    pushLine("[SPAWNBTN] poll error: " .. tostring(errT))
                    break
                end
                if spawnAnalyzed then break end
                task.wait(0.4)
            end
        end)
    end
    menu:GetPropertyChangedSignal("Enabled"):Connect(function()
        if menu.Enabled then startPoll() end
    end)
    if menu.Enabled then startPoll() end -- menu was already open at start
end)
if not okWatch then
    warn("[SpudCapture] menu watcher FAILED: " .. tostring(errWatch))
end

-- the buffer is never empty: proves lines work at a glance
pushLine("[SPAWNBTN] armed — open the Equipment Manager, click the ZM80 card (its Spawn button gets read into this list)")

baseText = "READY (hook-free)"
baseColor = Color3.fromRGB(60, 200, 110)
restoreBase()

print("══════ SPAWN ARGS CAPTURE (§29 v7.3) ══════")
print("holder:       " .. holderName)
print("capabilities: getconnections=" .. (hasGetConn and "yes" or "NO")
    .. "  debug.upvalues=" .. (hasDebug and "yes" or "NO"))
print(okBuild and "window:       ✔ PILL bottom-left (tap to expand)"
    or "window:       ✘ FAILED (error above)")
print(okWatch and "watcher:      ✔ card counter + Spawn-button reader ON"
    or ("watcher:      ✘ " .. tostring(errWatch)))
print("NO namecall hook is installed — cards stay intact.")
print("FLOW: open manager → click the ZM80 card → pill flashes"
    .. " \"SPAWN: n handler(s) read\" → expand → COPY → paste back")
print("══════════════════════════════════════")
