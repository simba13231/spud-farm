-- SPUD FIELD PROBE — read-only. It presses nothing, teleports nothing, and
-- dumps every field's Configurations + cells so the seed↔soil rule can be
-- named exactly instead of guessed.
--
-- WHY IT EXISTS
--   The farming pass tours EVERY field of the selected owner, whatever its
--   Configurations.FieldType says. The user's report: "when i chose a crop it
--   should work on normal soil, when it's wood it should work on the wood
--   soil." The repo has never recorded the live FieldType values (or which
--   seeds belong to which soil), so this probe answers it from the game.
--
-- HOW TO RUN
--   1. stand at your fields (the loop can be off). Have one field of each soil
--      kind streamed in; planting something in each makes the mapping visible.
--   2. run this loader:
--        loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFieldProbe.lua?t=" .. os.time()))()
--   3. a panel shows the report: COPY REPORT puts it on the clipboard, CLOSE
--      hides it. The same lines go to the console, prefixed [FIELD].
--
-- WHAT IT ANSWERS
--   * every field (Objects.Fields and fields sitting on plots): owner, the real
--     Configurations.FieldType value/class, every other Configurations leaf,
--     attributes, model name, plate size and position
--   * that field's cells via FieldHelper.GetCells: total, stage histogram, the
--     full key/value shape of a few cells, and every seed-like value found in
--     them — i.e. WHAT IS PLANTED WHERE
--   * a summary table: each FieldType value and the seed names seen in it
--   * FieldHelper's whole key list, every table dumped (capped), and every
--     table/function whose name looks like field/seed/soil/wood/tree/crop
--   * seed boxes/crates in the world: name, attributes and Configurations
--     (SeedType and anything else) — if a seed carries a soil requirement it
--     shows up here
--
-- Nothing here writes to the game. It only reads.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local REPL = {}
local function say(s)
    local line = tostring(s)
    REPL[#REPL + 1] = line
    print("[FIELD] " .. line)
end

local function safe(fn, fallback)
    local ok, v = pcall(fn)
    if ok then return v end
    return fallback
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

local function valueOf(inst)
    local cls = safe(function() return inst.ClassName end, "?")
    if cls:find("Value", 1, true) then
        local v = safe(function() return inst.Value end, nil)
        if typeof and typeof(v) == "Instance" then
            return cls .. "=" .. tostring(v:GetFullName())
        end
        return cls .. "=" .. tostring(v)
    end
    return cls
end

-- every Configurations leaf, named by its path inside the folder
local function cfgLines(model)
    local out = {}
    local cfg = model:FindFirstChild("Configurations")
        or model:FindFirstChild("Configuration")
    if not cfg then return out, false end
    for _, d in ipairs(cfg:GetDescendants()) do
        local bits = { d.Name .. " [" .. valueOf(d) .. "]" }
        local attrs = attrsOf(d)
        if #attrs > 0 then bits[#bits + 1] = "attrs{" .. table.concat(attrs, ",") .. "}" end
        out[#out + 1] = table.concat(bits, " ")
    end
    return out, true
end

local function fieldPlate(field)
    local ok, cf, sz = pcall(function() return field:GetBoundingBox() end)
    if ok and cf and sz then
        return sz, cf.Position
    end
    return nil, safe(function() return field:GetPivot().Position end, nil)
end

-- ── FieldHelper (the game's own cell API; the farm script already requires it)
local FH
local function fieldHelper()
    if FH ~= nil then return FH end
    local ok, F = pcall(function()
        local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        local m = mods and mods:FindFirstChild("FieldHelper")
        assert(m, "FieldHelper missing")
        return require(m)
    end)
    FH = (ok and type(F) == "table") and F or false
    return FH
end

local SEED_WORDS = { "seed", "crop", "plant", "tree", "soil", "wood", "log", "trellis" }
local function seedish(name)
    local n = tostring(name):lower()
    for _, w in ipairs(SEED_WORDS) do
        if n:find(w, 1, true) then return w end
    end
    return nil
end

-- ── one field: config + cells + what is planted in it
local function dumpField(field, tag)
    local sz, pos = fieldPlate(field)
    say(string.format("FIELD %s  %s  plate=%s  at %s",
        tag, field:GetFullName(),
        sz and string.format("%dx%d", math.floor(sz.X), math.floor(sz.Z)) or "?",
        posText(pos)))
    local cfg, hasCfg = cfgLines(field)
    if not hasCfg then say("  Configurations: NONE") end
    for _, line in ipairs(cfg) do say("  cfg." .. line) end
    local attrs = attrsOf(field)
    if #attrs > 0 then say("  attrs: " .. table.concat(attrs, " ")) end
    local function childNames(inst)
        local seen, out = {}, {}
        for _, c in ipairs(inst:GetChildren()) do
            seen[c.Name] = (seen[c.Name] or 0) + 1
        end
        for n, c in pairs(seen) do out[#out + 1] = n .. (c > 1 and ("x" .. c) or "") end
        table.sort(out)
        return out
    end
    local kids = childNames(field)
    if #kids > 0 then say("  children: " .. table.concat(kids, ", ")) end

    local F = fieldHelper()
    if not F then
        say("  cells: FieldHelper NOT READABLE")
        return nil
    end
    local ok, cells = pcall(function() return F.GetCells(field) end)
    if not ok or type(cells) ~= "table" then
        say("  cells: GetCells failed (" .. tostring(cells) .. ")")
        return nil
    end
    local total, stages = 0, {}
    local keySamples, seedsSeen = {}, {}
    local shownCells = 0
    for k, cell in pairs(cells) do
        if type(cell) == "table" then
            total += 1
            local st = tostring(cell.Stage or "?")
            stages[st] = (stages[st] or 0) + 1
            for ck, cv in pairs(cell) do
                local key = tostring(ck)
                if keySamples[key] == nil then
                    keySamples[key] = (type(cv) == "string") and ("'" .. cv .. "'")
                        or tostring(cv)
                end
                -- what is planted: any seed-ish key, or a string that matches
                -- a known seed name (checked later against SEED_TYPE)
                if type(cv) == "string" and (seedish(key) or ck == "Seed") then
                    seedsSeen[cv] = true
                end
            end
            if shownCells < 3 then
                shownCells += 1
                local bits = {}
                for ck, cv in pairs(cell) do
                    bits[#bits + 1] = tostring(ck) .. "=" .. tostring(cv)
                end
                table.sort(bits)
                say("  cell[" .. tostring(k) .. "]: " .. table.concat(bits, " "))
            end
        end
    end
    local sParts = {}
    for s, n in pairs(stages) do sParts[#sParts + 1] = s .. "=" .. n end
    table.sort(sParts)
    say(string.format("  cells: %d total  stages{%s}", total, table.concat(sParts, " ")))
    local kParts = {}
    for k, v in pairs(keySamples) do kParts[#kParts + 1] = k .. "=" .. v end
    table.sort(kParts)
    say("  cell keys: " .. table.concat(kParts, "  "))
    local sList = {}
    for s in pairs(seedsSeen) do sList[#sList + 1] = s end
    table.sort(sList)
    say("  seeds in cells: " .. (#sList > 0 and table.concat(sList, ", ") or "(none readable)"))
    return sList
end

-- ── the probe itself ──────────────────────────────────────────────────────
local function run()
    say("== SPUD FIELD PROBE (read-only) ==")
    say("place " .. tostring(game.PlaceId) .. "  job " .. tostring(game.JobId))
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    say("you: " .. tostring(LP and LP.Name or "?") .. " at " .. posText(root and root.Position))

    -- 1. every field streamed, with the owner + type + what is planted
    local typeSeeds = {}
    local seenFields = {}
    local function eachField(field, where)
        if not field:IsA("Model") or seenFields[field] then return end
        seenFields[field] = true
        local cfg = field:FindFirstChild("Configurations")
        local ownerV = cfg and cfg:FindFirstChild("Owner")
        local typeV = cfg and cfg:FindFirstChild("FieldType")
        local owner = ownerV and ownerV.Value
        local ownerName = (owner and owner.Name) or "?"
        local typeName = typeV and tostring(typeV.Value) or "NO FieldType"
        if typeV then
            say("  FieldType [" .. tostring(typeV.ClassName) .. "] = '" .. tostring(typeV.Value) .. "'")
        end
        local seeds = dumpField(field, where)
        local bucket = typeSeeds[typeName]
        if not bucket then bucket = {} typeSeeds[typeName] = bucket end
        bucket.owner = ownerName
        bucket.count = (bucket.count or 0) + 1
        bucket.seeds = bucket.seeds or {}
        for _, s in ipairs(seeds or {}) do bucket.seeds[s] = true end
    end

    local objects = workspace:FindFirstChild("Objects")
    local fieldsFolder = objects and objects:FindFirstChild("Fields")
    if not fieldsFolder then
        say("Objects.Fields NOT FOUND")
    else
        say("Objects.Fields: " .. #fieldsFolder:GetChildren() .. " child(ren)")
        for _, f in ipairs(fieldsFolder:GetChildren()) do
            if f:IsA("Model") then eachField(f, "Objects.Fields") end
        end
    end
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            if plot:IsA("Model") then
                for _, f in ipairs(plot:GetChildren()) do
                    if f:IsA("Model") and f:FindFirstChild("Configurations") then
                        local cfg = f:FindFirstChild("Configurations")
                        if cfg:FindFirstChild("FieldType") or cfg:FindFirstChild("Owner") then
                            eachField(f, "Plots." .. plot.Name)
                        end
                    end
                end
            end
        end
    end

    -- 2. the mapping: FieldType -> seeds seen planted in it
    say("")
    say("== FieldType -> seeds ==")
    local typeNames = {}
    for t in pairs(typeSeeds) do typeNames[#typeNames + 1] = t end
    table.sort(typeNames)
    for _, t in ipairs(typeNames) do
        local b = typeSeeds[t]
        local sList = {}
        for s in pairs(b.seeds or {}) do sList[#sList + 1] = s end
        table.sort(sList)
        say(string.format("  '%s' — %d field(s), owner=%s, planted: %s", t, b.count,
            tostring(b.owner), (#sList > 0 and table.concat(sList, ", ") or "(none readable)")))
    end
    if #typeNames == 0 then say("  (no field streamed here — walk to your fields and rerun)") end

    -- 3. FieldHelper: every key, then every table (capped)
    say("")
    say("== FieldHelper ==")
    local F = fieldHelper()
    if not F then
        say("  FieldHelper NOT READABLE")
    else
        local keyNames = {}
        for k in pairs(F) do keyNames[#keyNames + 1] = tostring(k) end
        table.sort(keyNames)
        say("  keys (" .. #keyNames .. "): " .. table.concat(keyNames, ", "))
        for _, k in ipairs(keyNames) do
            local v = F[k]
            if type(v) == "table" then
                local parts = {}
                for k2, v2 in pairs(v) do
                    parts[#parts + 1] = tostring(k2) .. "=" .. tostring(v2)
                    if #parts >= 60 then parts[#parts + 1] = "…" break end
                end
                table.sort(parts)
                local label = seedish(k) and "  >> " or "  "
                say(string.format("%s%s {%d}: %s", label, k, #v, table.concat(parts, "  ")))
            elseif seedish(k) then
                say(string.format("  >> %s = %s", k, tostring(v)))
            end
        end
    end

    -- 4. seed boxes / crates: does a seed carry a soil requirement?
    say("")
    say("== seed boxes/crates ==")
    local found = 0
    local function seedBox(m, where)
        if not m:IsA("Model") then return end
        local cfg = m:FindFirstChild("Configurations")
        local seedV = cfg and cfg:FindFirstChild("SeedType")
        local nameHit = tostring(m.Name):lower():find("seed", 1, true)
        if not (seedV or nameHit) then return end
        found += 1
        local bits = { m.Name, "at " .. posText(safe(function() return m:GetPivot().Position end, nil)) }
        if seedV then bits[#bits + 1] = "SeedType=" .. tostring(seedV.Value) end
        say("  " .. table.concat(bits, "  ") .. "   [" .. where .. "]")
        local cfgText = cfgLines(m)
        for _, line in ipairs(cfgText) do say("    cfg." .. line) end
    end
    local drag = objects and objects:FindFirstChild("DraggableObjects")
    for _, m in ipairs(drag and drag:GetChildren() or {}) do seedBox(m, "DraggableObjects") end
    for _, f in ipairs(fieldsFolder and fieldsFolder:GetChildren() or {}) do
        for _, m in ipairs(f:GetChildren()) do seedBox(m, "on a field") end
    end
    -- storage / pallet folders also hold bought seed boxes
    for _, folderName in ipairs({ "Buildings", "Equipment" }) do
        local folder = objects and objects:FindFirstChild(folderName)
        for _, m in ipairs(folder and folder:GetChildren() or {}) do seedBox(m, folderName) end
    end
    if found == 0 then say("  (no seed box streamed — stand near the ones you bought)") end

    -- 5. the game's seed vocabulary (the dropdown's source)
    say("")
    say("== SEED_TYPE ==")
    if F and type(F.SEED_TYPE) == "table" then
        local parts = {}
        for k, v in pairs(F.SEED_TYPE) do
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            if #parts >= 120 then parts[#parts + 1] = "…" break end
        end
        table.sort(parts)
        say("  " .. table.concat(parts, "  "))
    else
        say("  SEED_TYPE NOT READABLE")
    end
end

-- ── the panel: the same lines, with COPY ───────────────────────────────────
local function finish()
    local text = table.concat(REPL, "\n")
    local copied = safe(function() setclipboard(text) return true end, false)
    local ok = pcall(function()
        local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
        if not (pg and Instance and UDim2 and Color3) then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "SpudFieldProbe"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 200
        gui.IgnoreGuiInset = true
        gui.Parent = pg

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.new(0, 620, 0, 400)
        frame.Position = UDim2.new(0, 12, 0, 12)
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 26)
        title.BackgroundColor3 = Color3.fromRGB(32, 36, 42)
        title.BorderSizePixel = 0
        title.Text = "SPUD FIELD PROBE - read-only"
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

local okRun, errRun = pcall(run)
if not okRun then
    say("PROBE ERROR: " .. tostring(errRun))
end
finish()
