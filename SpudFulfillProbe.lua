-- SPUD FULFILLMENT PROBE — read-only. It presses nothing, teleports nothing,
-- and dumps the Fulfillment / Shipment area so the harvester's drop-off can be
-- named exactly instead of guessed.
--
-- WHY IT EXISTS
--   The harvester now STOPS when its tank is full because the real drop-off is
--   not wired yet. The place is the Fulfillment building next to Shipment
--   (user's words); its pad, prompt/key and unloading behaviour are unknown,
--   and the old sell-pad scan (GameplayVisuals.SellArea / Stores.DropOffs) may
--   point at the wrong store. This dump answers it from the game.
--
-- HOW TO RUN
--   1. stand in front of the Fulfillment / Shipment building with the vehicle
--      you unload with spawned nearby (the loop can be off).
--   2. run this loader:
--        loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFulfillProbe.lua?t=" .. os.time()))()
--   3. a panel shows the report: COPY REPORT puts it on the clipboard, CLOSE
--      hides it. The same lines go to the console, prefixed [FULFILL].
--
-- WHAT IT ANSWERS
--   * every building/model near the area whose name looks like
--     Fulfillment / Shipment / Warehouse / Drop-off / Sell / Pad / Load-in:
--     position, size, attributes, Configurations, children
--   * parts that could be the unload pad (name, position, size, transparency)
--   * text on signs/billboards (the "Fulfillment" sign included) and where it
--     is adorned
--   * ProximityPrompts in the area (action text, object text, key code)
--   * the game's own context actions RIGHT NOW (stand near the building) —
--     the key it wants for unloading will be in that list
--   * the old sell-pad targets the script scans today (Stores.DropOffs,
--     GameplayVisuals.SellArea) so a wrong pad is visible
--
-- Nothing here writes to the game. It only reads.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local REPL = {}
local function say(s)
    local line = tostring(s)
    REPL[#REPL + 1] = line
    print("[FULFILL] " .. line)
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

local function boxOf(inst)
    local ok, cf, sz = pcall(function() return inst:GetBoundingBox() end)
    if ok and cf and sz then return cf.Position, sz end
    return safe(function() return inst:GetPivot().Position end, nil), nil
end

local WORDS = {
    "fulfill", "fulfil", "shipment", "shipping", "warehouse", "dropoff",
    "drop-off", "drop off", "sell", "pad", "loadin", "load-in", "load in",
    "unload", "delivery", "trailer",
}
local function interesting(name)
    local n = tostring(name):lower()
    if n == "" then return nil end
    for _, w in ipairs(WORDS) do
        if n:find(w, 1, true) then return w end
    end
    return nil
end

local function cfgLines(model)
    local out = {}
    local cfg = model:FindFirstChild("Configurations")
        or model:FindFirstChild("Configuration")
    if not cfg then return out end
    for _, d in ipairs(cfg:GetDescendants()) do
        local bits = { d.Name .. " [" .. valueOf(d) .. "]" }
        local attrs = attrsOf(d)
        if #attrs > 0 then bits[#bits + 1] = "attrs{" .. table.concat(attrs, ",") .. "}" end
        out[#out + 1] = table.concat(bits, " ")
    end
    return out
end

local function dumpModel(m, label)
    local p, sz = boxOf(m)
    say(string.format("== %s  %s  at %s%s", label, m:GetFullName(), posText(p),
        sz and string.format("  size %.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z) or ""))
    local attrs = attrsOf(m)
    if #attrs > 0 then say("   attrs: " .. table.concat(attrs, " ")) end
    for _, line in ipairs(cfgLines(m)) do say("   cfg." .. line) end
    local kids, seen = {}, {}
    for _, c in ipairs(m:GetChildren()) do
        seen[c.Name] = (seen[c.Name] or 0) + 1
    end
    for n, c in pairs(seen) do kids[#kids + 1] = n .. (c > 1 and ("x" .. c) or "") end
    table.sort(kids)
    if #kids > 0 then say("   children: " .. table.concat(kids, ", ")) end
    -- the useful descendants: pads/parts, prompts, signs
    local shown = 0
    for _, d in ipairs(m:GetDescendants()) do
        if shown >= 70 then say("   … (descendants capped)"); break end
        local cls = safe(function() return d.ClassName end, "")
        if cls == "ProximityPrompt" then
            shown += 1
            say(string.format("   prompt %s  key=%s  action='%s'  object='%s'  enabled=%s  dist=%.0f",
                d.Name, tostring(safe(function() return d.KeyCode end, "?")),
                tostring(safe(function() return d.ActionText end, "")),
                tostring(safe(function() return d.ObjectText end, "")),
                tostring(safe(function() return d.Enabled end, "?")),
                tonumber(safe(function() return d.MaxActivationDistance end, 0)) or 0))
        elseif cls:find("TextLabel") or cls == "TextButton" then
            local txt = safe(function() return d.Text end, nil)
            if txt and tostring(txt) ~= "" then
                shown += 1
                say(string.format("   text %s = '%s'", d:GetFullName(), tostring(txt)))
            end
        elseif cls == "BillboardGui" or cls == "SurfaceGui" then
            local ad = safe(function() return d.Adornee end, nil)
            say("   gui " .. d:GetFullName() .. " adornee="
                .. (ad and ad:GetFullName() or "none"))
            shown += 1
        elseif cls:find("Part") or cls == "MeshPart" or cls == "UnionOperation" then
            local n = tostring(d.Name):lower()
            local tr = tonumber(safe(function() return d.Transparency end, 1)) or 1
            if interesting(d.Name) or n:find("trigger", 1, true)
                or n:find("pad", 1, true) or tr < 0.9 then
                shown += 1
                local dp, ds = boxOf(d)
                say(string.format("   part %s  at %s%s  transp=%.2f",
                    d:GetFullName(), posText(dp),
                    ds and string.format("  size %.0fx%.0fx%.0f", ds.X, ds.Y, ds.Z) or "",
                    tr))
            end
        end
    end
end

local function contextActions()
    say("")
    say("== context actions (you are standing here) ==")
    local ok, btns = pcall(function()
        return LP.PlayerGui.GuiViews.HUD.PCGP_ContextActions.Buttons
    end)
    if not ok or not btns then
        say("   PCGP_ContextActions.Buttons NOT FOUND")
        return
    end
    local any = 0
    for _, b in ipairs(btns:GetChildren()) do
        any += 1
        say(string.format("   %s  bind=%s  label=%s", b.Name,
            tostring(safe(function() return b:GetAttribute("Bind") end, "?")),
            tostring(safe(function() return b:FindFirstChild("ActionLabel") end, nil)
                and safe(function() return b.ActionLabel.Text end, "?") or "?")))
    end
    if any == 0 then say("   (no action buttons — stand closer / sit in the vehicle)") end
    local bills = safe(function()
        return LP.PlayerGui.GuiViews.HUD.Billboards
    end, nil)
    if bills then
        for _, b in ipairs(bills:GetChildren()) do
            local ad = safe(function() return b.Adornee end, nil)
            say("   billboard " .. b.Name .. " adornee=" .. (ad and ad:GetFullName() or "none"))
        end
    end
end

local function signsAnywhere()
    say("")
    say("== signs / texts that mention fulfill / ship / drop / sell ==")
    local hits = 0
    local root = safe(function() return workspace end, nil)
    for _, d in ipairs(root and root:GetDescendants() or {}) do
        local cls = safe(function() return d.ClassName end, "")
        if (cls:find("TextLabel") or cls == "TextButton") and hits < 40 then
            local txt = tostring(safe(function() return d.Text end, "") or "")
            local low = txt:lower()
            if low:find("fulfill", 1, true) or low:find("fulfil", 1, true)
                or low:find("ship", 1, true) or low:find("drop", 1, true)
                or low:find("sell", 1, true) then
                hits += 1
                local ad = safe(function() return d.Adornee end, nil)
                local p = ad and select(1, boxOf(ad)) or nil
                say(string.format("   '%s'  at %s  %s", txt, posText(p), d:GetFullName()))
            end
        end
    end
    if hits == 0 then say("   (none readable)") end
end

local function oldTargets()
    say("")
    say("== the old sell-pad targets the script scans today ==")
    local objects = safe(function() return workspace:FindFirstChild("Objects") end, nil)
    local stores = safe(function() return workspace:FindFirstChild("Stores") end, nil)
    local drops = stores and safe(function() return stores:FindFirstChild("DropOffs") end, nil)
    if drops then
        for _, d in ipairs(drops:GetChildren()) do
            local p, sz = boxOf(d)
            say(string.format("   DropOffs.%s  at %s%s", d.Name, posText(p),
                sz and string.format("  size %.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z) or ""))
        end
    else
        say("   Stores.DropOffs NOT FOUND")
    end
    local gv = safe(function() return workspace:FindFirstChild("GameplayVisuals") end, nil)
    local sell = gv and safe(function() return gv:FindFirstChild("SellArea") end, nil)
    if sell then
        for _, d in ipairs(sell:GetChildren()) do
            local p, sz = boxOf(d)
            say(string.format("   SellArea.%s [%s]  at %s%s", d.Name,
                safe(function() return d.ClassName end, "?"), posText(p),
                sz and string.format("  size %.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z) or ""))
        end
    else
        say("   GameplayVisuals.SellArea NOT FOUND")
    end
    local buildings = objects and safe(function() return objects:FindFirstChild("Buildings") end, nil)
    if buildings then
        say("   Objects.Buildings:")
        for _, d in ipairs(buildings:GetChildren()) do
            local p = safe(function() return d:GetPivot().Position end, nil)
            say("     " .. d.Name .. " at " .. posText(p))
        end
    end
end

local function run()
    say("== SPUD FULFILLMENT PROBE (read-only) ==")
    say("place " .. tostring(game.PlaceId) .. "  job " .. tostring(game.JobId))
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    say("you: " .. tostring(LP and LP.Name or "?") .. " at " .. posText(root and root.Position))

    -- 1. candidate buildings / models anywhere whose name says what this is
    say("")
    say("== candidate buildings/models ==")
    local seen = {}
    local shown = 0
    local function consider(m, why)
        if not (m and m:IsA("Model")) or seen[m] then return end
        seen[m] = true
        shown += 1
        dumpModel(m, why)
    end
    local objects = safe(function() return workspace:FindFirstChild("Objects") end, nil)
    local stores = safe(function() return workspace:FindFirstChild("Stores") end, nil)
    local function scanFolder(folder)
        for _, m in ipairs(folder and folder:GetChildren() or {}) do
            if interesting(m.Name) then
                consider(m, "folder " .. tostring(folder.Name))
            end
        end
    end
    scanFolder(objects and objects:FindFirstChild("Buildings"))
    scanFolder(stores and stores:FindFirstChild("Buildings"))
    scanFolder(stores)
    scanFolder(safe(function() return workspace:FindFirstChild("GameplayVisuals") end, nil))
    -- names deeper in the map (the building model may sit under a plot)
    for _, m in ipairs(safe(function() return workspace:GetDescendants() end, {})) do
        if shown >= 30 then break end
        if m:IsA("Model") and interesting(m.Name) and not seen[m] then
            consider(m, "workspace")
        end
    end
    if shown == 0 then
        say("   (no model name matched — stand closer so the area is streamed in)")
    end

    contextActions()
    signsAnywhere()
    oldTargets()
end

-- ── the panel: the same lines, with COPY ───────────────────────────────────
local function finish()
    local text = table.concat(REPL, "\n")
    local copied = safe(function() setclipboard(text) return true end, false)
    local ok = pcall(function()
        local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
        if not (pg and Instance and UDim2 and Color3) then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "SpudFulfillProbe"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 200
        gui.IgnoreGuiInset = true
        gui.Parent = pg

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.new(0, 640, 0, 420)
        frame.Position = UDim2.new(0, 12, 0, 12)
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 26)
        title.BackgroundColor3 = Color3.fromRGB(32, 36, 42)
        title.BorderSizePixel = 0
        title.Text = "SPUD FULFILLMENT PROBE - read-only"
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
