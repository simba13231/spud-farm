-- SPUD STALL PROBE — read-only. It presses nothing, teleports nothing, and
-- dumps one complete stall folder so the dirt field can be named exactly.
--
-- WHY IT EXISTS
--   milkClean asks "is this stall dirty?" from where the character stands, so it
--   never teleports into a stall just to look. The stalls in the live build do
--   not answer the read the dump suggested (the console said "12 of 12 stall(s)
--   need a visit (no readable dirt)"), so this dump is the evidence needed to
--   point the read at the real field instead of guessing.
--
-- HOW TO RUN
--   1. stand at the farm you run the milk loop on (the loop can be off).
--   2. run this loader:
--        loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudStallProbe.lua?t=" .. os.time()))()
--   3. a small panel shows the whole report: COPY puts it on the clipboard,
--      CLOSE hides it. The same lines go to the console, prefixed [STALL].
--
-- WHAT IT ANSWERS
--   * which building the stalls live in, and what the Spots folder really holds
--   * ONE stall folder, EVERY descendant: name, class, value, attributes, and
--     for parts their transparency/position — the full shape, not a sample
--   * every stain part (name matches stain/dirt/grime/poop/manure) with whether
--     it is VISIBLE right now, since a stain you can see needs no value at all
--   * anything anywhere in the stall / barn / plot whose name looks like a dirt
--     counter, with its full path — that list is the answer
--   * the game's CleanAnimalContainer billboard: does it exist, what is it
--     adorned to, is it enabled, and what text does it carry (the key it wants)
--
-- Nothing here writes to the game. It only reads.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

-- every line goes to the console AND into the panel, so nothing is only in one
-- place; the panel is built at the end even when the probe bails out early
local REPL = {}
local function say(s)
    local line = tostring(s)
    REPL[#REPL + 1] = line
    print("[STALL] " .. line)
end

local function safe(fn, fallback)
    local ok, v = pcall(fn)
    if ok then return v end
    return fallback
end

local DIRT_WORDS = {
    "filth", "dirt", "stain", "grime", "poop", "manure", "clean", "mess", "muck",
}

local function looksDirty(name)
    local n = tostring(name):lower()
    for _, w in ipairs(DIRT_WORDS) do
        if n:find(w, 1, true) then return w end
    end
    return nil
end

local function posOf(inst)
    return safe(function() return inst:GetPivot().Position end, nil)
end
local function posText(p)
    if not p then return "?" end
    return string.format("%d,%d,%d", math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
end

local function attrsOf(inst)
    local out = {}
    local list = safe(function() return inst:GetAttributes() end, nil)
    if type(list) == "table" then
        for k, v in pairs(list) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    end
    table.sort(out)
    return out
end

local function valueText(inst)
    local cls = safe(function() return inst.ClassName end, "?")
    if cls:find("Value", 1, true) then
        local v = safe(function() return inst.Value end, nil)
        if typeof and typeof(v) == "Instance" then
            return cls .. " = " .. tostring(v:GetFullName())
        end
        return cls .. " = " .. tostring(v)
    end
    local txt = safe(function() return inst.Text end, nil)
    if txt ~= nil then return cls .. " text='" .. tostring(txt) .. "'" end
    return cls
end

local function partText(inst)
    local t = safe(function() return inst.Transparency end, nil)
    if type(t) ~= "number" then return nil end
    local size = safe(function() return inst.Size end, nil)
    local bits = { string.format("transparency=%.2f", t) }
    if size then bits[#bits + 1] = string.format("size=%d,%d,%d", size.X, size.Y, size.Z) end
    bits[#bits + 1] = "pos=" .. posText(posOf(inst))
    return table.concat(bits, " ")
end

-- ── the probe itself ───────────────────────────────────────────────────────
local function run()
    say("== SPUD STALL PROBE (read-only) ==")
    say("place " .. tostring(game.PlaceId) .. "  job " .. tostring(game.JobId))
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local here = root and root.Position
    say("you: " .. tostring(LP and LP.Name or "?") .. " at " .. posText(here))

    -- 1. the barns the stall scan walks
    local objects = workspace:FindFirstChild("Objects")
    local bld = objects and objects:FindFirstChild("Buildings")
    local barns = {}
    for _, b in ipairs(bld and bld:GetChildren() or {}) do
        if b:IsA("Model") then
            local spots = b:FindFirstChild("Spots")
                or safe(function() return b:FindFirstChild("Spots", true) end, nil)
            if spots then barns[#barns + 1] = { model = b, spots = spots } end
        end
    end
    if #barns == 0 then
        say("!! no building in Objects.Buildings holds a Spots folder")
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name:lower():find("barn", 1, true) then
                local spots = safe(function() return d:FindFirstChild("Spots", true) end, nil)
                if spots then barns[#barns + 1] = { model = d, spots = spots } end
            end
        end
    end
    say("barn candidate(s): " .. #barns)
    local pick, pickD
    for i, b in ipairs(barns) do
        local p = posOf(b.model)
        local d = (p and here) and (p - here).Magnitude or nil
        say(string.format("  %d %-24s %-8s @ %-14s %s", i, b.model.Name,
            safe(function() return b.model.ClassName end, "?"), posText(p),
            d and string.format("%d studs away", math.floor(d)) or "distance ?"))
        if d and (not pickD or d < pickD) then pick, pickD = b, d end
    end
    pick = pick or barns[1]
    if not pick then
        say("!! nothing to dump - run this standing on a farm whose barn is visible")
        return
    end

    -- 2. the stall folders in that barn
    local stalls = {}
    for _, num in ipairs(pick.spots:GetChildren()) do
        local part = num:FindFirstChild("Adornee_BarnStallMenu", true)
        if part then stalls[#stalls + 1] = { folder = num, part = part } end
    end
    say("barn: " .. pick.model:GetFullName())
    say("Spots: " .. pick.spots:GetFullName() .. "  children: " .. #pick.spots:GetChildren())
    say("stall(s) found in it: " .. #stalls)
    if #stalls == 0 then
        say("!! no child holds Adornee_BarnStallMenu - Spots children are: "
            .. safe(function()
                local names = {}
                for _, c in ipairs(pick.spots:GetChildren()) do names[#names + 1] = c.Name end
                return table.concat(names, ", ")
            end, "?"))
        return
    end

    -- 3. ONE stall folder, completely
    local stall = stalls[1]
    local F = stall.folder
    say("")
    say("== STALL " .. F.Name .. " (" .. tostring(#stalls) .. " exist; this is the first) ==")
    say("path: " .. F:GetFullName())
    say("class: " .. safe(function() return F.ClassName end, "?"))
    local folderAttrs = attrsOf(F)
    say("its attributes: " .. (#folderAttrs > 0 and table.concat(folderAttrs, ", ") or "(none)"))

    local lines, over = {}, false
    local function dump(inst, depth, budget)
        if over then return end
        if #lines >= budget then
            over = true
            return
        end
        local pad = string.rep("  ", depth)
        local bits = { pad .. inst.Name .. "  [" .. safe(function() return inst.ClassName end, "?") .. "]" }
        local v = valueText(inst)
        if v and v:find("=", 1, true) then bits[#bits + 1] = (v:gsub("^.-= ", "")) end
        local p = partText(inst)
        if p then bits[#bits + 1] = p end
        local at = attrsOf(inst)
        if #at > 0 then bits[#bits + 1] = "attrs{" .. table.concat(at, ", ") .. "}" end
        local flag = looksDirty(inst.Name)
        if flag then bits[#bits + 1] = "  <<< matches '" .. flag .. "'" end
        lines[#lines + 1] = table.concat(bits, "  ")
        for _, child in ipairs(safe(function() return inst:GetChildren() end, {})) do
            dump(child, depth + 1, budget)
        end
    end
    dump(F, 0, 120)
    say("every descendant (attributes and values inline, <<< = dirt-sounding name):")
    for _, l in ipairs(lines) do say(l) end
    if over then say("...stopped at 120 lines; the tree is bigger than that") end
    say("descendants in this stall: " .. #safe(function() return F:GetDescendants() end, {}))

    -- 4. visible stains: a stain you can SEE needs no value at all
    say("")
    say("-- stain parts in this stall --")
    local stains, faded = 0, 0
    for _, d in ipairs(safe(function() return F:GetDescendants() end, {})) do
        local isPart = safe(function() return d:IsA("BasePart") end, false) == true
        local t = isPart and safe(function() return d.Transparency end, nil) or nil
        if type(t) == "number" and looksDirty(d.Name) then
            if t < 0.95 then
                stains += 1
                say(string.format("  VISIBLE  %-24s %s", d.Name, partText(d)))
            else
                faded += 1
            end
        end
    end
    say(string.format("visible stain parts: %d   (invisible stain parts: %d)", stains, faded))

    -- 5. anything that could be the dirt counter, with its path
    say("")
    say("-- every dirt-sounding instance in the stall, the barn and the plot --")
    local seen = {}
    local function sweep(rootInst, label, budget)
        local n = 0
        for _, d in ipairs(safe(function() return rootInst:GetDescendants() end, {})) do
            if n >= budget then
                say("  (" .. label .. ": stopped at " .. budget .. ")")
                break
            end
            if looksDirty(d.Name) and not seen[d] then
                seen[d] = true
                n += 1
                -- parts carry their position too: two stains share a name and a
                -- path, and which one is visible is the whole question
                local extra = partText(d) or valueText(d)
                say(string.format("  %-12s %s  %s", label, d:GetFullName(), extra))
            end
        end
    end
    sweep(F, "stall", 20)
    sweep(pick.model, "barn", 20)
    local plot
    if here then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name:lower():find("farm", 1, true) then
                local p = posOf(d)
                if p and (p - here).Magnitude < 400 then
                    plot = d
                    break
                end
            end
        end
    end
    if plot then sweep(plot, "plot", 12) end
    say("(paths above are the answer: whichever one is a number that rises when a")
    say(" stall gets dirty is the field the clean pass should read)")

    -- 6. the game's own Clean action, wherever we stand
    say("")
    say("-- CleanAnimalContainer (the game's own dirt answer) --")
    local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
    local cpa = safe(function()
        local gv = pg and pg:FindFirstChild("GuiViews")
        local hud = gv and gv:FindFirstChild("HUD")
        local gw = hud and hud:FindFirstChild("MainHUD")
        return (gw and gw:FindFirstChild("PCGP_ContextActions"))
            or (hud and hud:FindFirstChild("PCGP_ContextActions"))
    end, nil)
    local bills = cpa and safe(function() return cpa:FindFirstChild("Billboards") end, nil)
    local bill = bills and safe(function() return bills:FindFirstChild("CleanAnimalContainer") end, nil)
    if not bill then
        say("billboard: NOT FOUND (is the player spawned and the HUD built?)")
    else
        local ad = safe(function() return bill.Adornee end, nil)
        say("billboard: found  enabled=" .. tostring(safe(function() return bill.Enabled end, "?")))
        say("adorned to: " .. (ad and ad:GetFullName() or "nothing"))
        if ad and F:FindFirstChild(ad.Name, true) then
            say("  ^ that is inside THIS stall")
        end
        local texts = {}
        for _, d in ipairs(safe(function() return bill:GetDescendants() end, {})) do
            local t = safe(function() return d:IsA("TextLabel") and d.Text end, nil)
            if t and t ~= "" then texts[#texts + 1] = t end
        end
        say("text: " .. (#texts > 0 and table.concat(texts, " | ") or "(none)"))
        say("(if it is adorned to a stall while you are NOT in it, the clean pass can")
        say(" read it for that stall without moving - that is the ideal signal)")
    end
    say("== end of stall probe ==")
end

-- ── the small panel: the same lines, with COPY ─────────────────────────────
local function finish()
    local text = table.concat(REPL, "\n")
    local copied = safe(function() setclipboard(text) return true end, false)
    local ok = pcall(function()
        local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
        if not (pg and Instance and UDim2 and Color3) then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "SpudStallProbe"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 200
        gui.IgnoreGuiInset = true
        gui.Parent = pg

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.new(0, 560, 0, 380)
        frame.Position = UDim2.new(0, 12, 0, 12)
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 26)
        title.BackgroundColor3 = Color3.fromRGB(32, 36, 42)
        title.BorderSizePixel = 0
        title.Text = "SPUD STALL PROBE - read-only"
        title.TextColor3 = Color3.fromRGB(210, 230, 210)
        title.TextSize = 14
        title.Font = Enum.Font.Code
        title.Parent = frame

        local box = Instance.new("TextBox")
        box.Name = "Report"
        box.Size = UDim2.new(1, -16, 1, -76)
        box.Position = UDim2.new(0, 8, 0, 30)
        box.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
        box.BorderSizePixel = 0
        box.TextColor3 = Color3.fromRGB(200, 210, 205)
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = Enum.TextYAlignment.Top
        box.ClearTextOnFocus = false
        box.TextWrapped = false
        box.TextSize = 12
        box.Text = text
        safe(function() box.TextEditable = false end)
        box.Parent = frame

        local function button(label, x, width, colour)
            local b = Instance.new("TextButton")
            b.Name = label
            b.Size = UDim2.new(0, width, 0, 30)
            b.Position = UDim2.new(0, x, 1, -38)
            b.BackgroundColor3 = colour
            b.BorderSizePixel = 0
            b.Text = label
            b.TextColor3 = Color3.fromRGB(235, 240, 235)
            b.TextSize = 14
            b.Font = Enum.Font.Code
            b.Parent = frame
            return b
        end

        local copy = button("COPY REPORT", 8, 170, Color3.fromRGB(40, 96, 58))
        local close = button("CLOSE", 186, 100, Color3.fromRGB(70, 40, 40))

        safe(function()
            copy.MouseButton1Click:Connect(function()
                local put = pcall(function() setclipboard(text) end)
                copy.Text = put and "COPIED" or "NO CLIPBOARD"
                task.delay(1.5, function()
                    pcall(function() copy.Text = "COPY REPORT" end)
                end)
            end)
        end)
        safe(function()
            close.MouseButton1Click:Connect(function() gui:Destroy() end)
        end)
    end)
    if not ok then
        say("(the on-screen panel could not be built - the report above is the console)")
    elseif copied then
        say("(report copied to the clipboard; the panel has COPY REPORT / CLOSE)")
    else
        say("(panel on screen - press COPY REPORT to copy it)")
    end
end

run()
finish()
