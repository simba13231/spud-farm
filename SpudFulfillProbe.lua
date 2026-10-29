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
    say("== actions the game offers RIGHT NOW ==")
    -- ▸ USE THE BILLBOARDS, NOT THE BUTTON LIST (dump §24 pattern): every
    --   action in the game is in Buttons — that is why the first runs listed
    --   all 70 of them with no key. Billboards holds ONLY the actions the game
    --   is offering at this spot, each with its own one-letter key label and
    --   the part it is adorned to.
    local cpa = safe(function()
        local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
        local gv = pg and pg:FindFirstChild("GuiViews")
        local hud = gv and gv:FindFirstChild("HUD")
        local gw = hud and hud:FindFirstChild("MainHUD")
        return (gw and gw:FindFirstChild("PCGP_ContextActions"))
            or (hud and hud:FindFirstChild("PCGP_ContextActions"))
    end, nil)
    if not cpa then
        say("   PCGP_ContextActions NOT FOUND")
        return
    end
    local function keyOf(b)
        local texts, key = {}, nil
        for _, d in ipairs(safe(function() return b:GetDescendants() end, {})) do
            if d:IsA("TextLabel") and d.Text ~= "" then
                texts[#texts + 1] = d.Text
                if not key and d.Text:match("^%u$") then key = d.Text end
            end
        end
        return key, table.concat(texts, " | ")
    end
    local bills = safe(function() return cpa:FindFirstChild("Billboards") end, nil)
    local shown = 0
    if bills then
        for _, b in ipairs(bills:GetChildren()) do
            local on
            if b:IsA("LayerCollector") then
                on = b.Enabled == true
            elseif b:IsA("GuiObject") then
                on = b.Visible == true
            else
                on = false
            end
            if on then
                shown += 1
                local key, text = keyOf(b)
                local ad = safe(function() return b.Adornee end, nil)
                local p = ad and select(1, boxOf(ad)) or nil
                say(string.format("   ON  %s  key=%s  text='%s'  adornee=%s at %s",
                    b.Name, tostring(key or "?"), text,
                    ad and ad:GetFullName() or "none", posText(p)))
            end
        end
    else
        say("   Billboards NOT FOUND")
    end
    if shown == 0 then
        say("   (no billboard is on — the character is not on the pad, or nothing is offered here)")
    end
    local btns = safe(function() return cpa:FindFirstChild("Buttons") end, nil)
    if btns then
        local on, off = {}, 0
        for _, b in ipairs(btns:GetChildren()) do
            if b:IsA("GuiObject") and b.Visible then
                local key, text = keyOf(b)
                on[#on + 1] = string.format("%s(key=%s '%s')", b.Name, tostring(key or "?"), text)
            elseif b:IsA("GuiObject") then
                off += 1
            end
        end
        say(string.format("   visible buttons (%d, %d hidden): %s", #on, off,
            #on > 0 and table.concat(on, "  ·  ") or "none"))
    end
end

-- what the character is standing on (a pad is usually a transparent part)
local function standingOn()
    say("")
    say("== what you are standing on ==")
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then say("   no character"); return end
    local params = safe(function()
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances = { char }
        return p
    end, nil)
    local hit = params and safe(function()
        return workspace:Raycast(root.Position, Vector3.new(0, -20, 0), params)
    end, nil)
    if not (hit and hit.Instance) then
        say("   raycast hit nothing within 20 studs")
        return
    end
    local inst = hit.Instance
    say(string.format("   %s  [%s]  at %s  (you are %.1f above it)",
        inst:GetFullName(), tostring(safe(function() return inst.ClassName end, "?")),
        posText(hit.Position), hit.Distance))
    local sz = safe(function() return inst.Size end, nil)
    if sz then
        say(string.format("   size %.1fx%.1fx%.1f  transp=%.2f  collide=%s  touch=%s",
            sz.X, sz.Y, sz.Z,
            tonumber(safe(function() return inst.Transparency end, 0)) or 0,
            tostring(safe(function() return inst.CanCollide end, "?")),
            tostring(safe(function() return inst.CanTouch end, "?"))))
    end
    local attrs = attrsOf(inst)
    if #attrs > 0 then say("   attrs: " .. table.concat(attrs, " ")) end
    local chain, p = {}, inst
    for _ = 1, 6 do
        p = p and p.Parent
        if not p or p == workspace then break end
        table.insert(chain, 1, p.Name)
    end
    if #chain > 0 then say("   under: " .. table.concat(chain, " / ") .. " / " .. inst.Name) end
end

-- everything close enough to be the thing you are supposed to use
local function nearby(radius)
    radius = radius or 30
    say("")
    say("== within " .. radius .. " studs (prompts, pad parts, labels) ==")
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then say("   no character"); return end
    local here = root.Position
    local function guiSpot(d)
        local p = d
        for _ = 1, 5 do
            if not p then return nil end
            local ad = safe(function() return p.Adornee end, nil)
            if ad then return safe(function() return ad.Position end, nil), ad end
            if p:IsA("BasePart") then return safe(function() return p.Position end, nil), p end
            p = p.Parent
        end
        return nil
    end
    local prompts, pads, labels = {}, {}, {}
    for _, d in ipairs(safe(function() return workspace:GetDescendants() end, {})) do
        local cls = safe(function() return d.ClassName end, "")
        if cls == "ProximityPrompt" then
            local par = safe(function() return d.Parent end, nil)
            local pos = par and safe(function() return par.Position end, nil)
            if pos and (pos - here).Magnitude <= radius then
                prompts[#prompts + 1] = string.format(
                    "   prompt %s  key=%s  action='%s'  object='%s'  enabled=%s  dist=%.0f",
                    d:GetFullName(),
                    tostring(safe(function() return d.KeyCode end, "?")),
                    tostring(safe(function() return d.ActionText end, "")),
                    tostring(safe(function() return d.ObjectText end, "")),
                    tostring(safe(function() return d.Enabled end, "?")),
                    tonumber(safe(function() return d.MaxActivationDistance end, 0)) or 0)
            end
        elseif cls:find("Part") or cls == "UnionOperation" then
            local pos = safe(function() return d.Position end, nil)
            if pos and (pos - here).Magnitude <= radius then
                local tr = tonumber(safe(function() return d.Transparency end, 1)) or 1
                if interesting(d.Name) or tr < 0.6 then
                    local sz = safe(function() return d.Size end, nil)
                    pads[#pads + 1] = string.format(
                        "   part %s  at %s  dist=%.0f%s  transp=%.2f  collide=%s",
                        d:GetFullName(), posText(pos), (pos - here).Magnitude,
                        sz and string.format("  size %.1fx%.1fx%.1f", sz.X, sz.Y, sz.Z) or "",
                        tr, tostring(safe(function() return d.CanCollide end, "?")))
                end
            end
        elseif cls == "TextLabel" or cls == "TextButton" then
            local pos, ad = guiSpot(d)
            local txt = tostring(safe(function() return d.Text end, "") or "")
            if pos and txt ~= "" and (pos - here).Magnitude <= radius then
                labels[#labels + 1] = string.format("   text '%s'  at %s  dist=%.0f  %s%s",
                    txt, posText(pos), (pos - here).Magnitude, d:GetFullName(),
                    ad and ad ~= d and ("  -> " .. ad:GetFullName()) or "")
            end
        end
    end
    local function dump(list, cap, empty)
        for i = 1, math.min(#list, cap or 40) do say(list[i]) end
        if #list == 0 then say("   " .. empty) end
        if #list > (cap or 40) then say("   … (" .. (#list - (cap or 40)) .. " more)") end
    end
    say("   -- prompts")
    dump(prompts, 20, "(none)")
    say("   -- pad-like / see-through parts")
    dump(pads, 30, "(none)")
    say("   -- labels (a pad's key is usually one of these)")
    dump(labels, 40, "(none)")
end

-- the drop-off parts the script scans, with distance from here, and the
-- nearest one's insides (a prompt/trigger would live there)
local function dropTargets()
    say("")
    say("== Stores.DropOffs from here ==")
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local here = root and root.Position
    local stores = safe(function() return workspace:FindFirstChild("Stores") end, nil)
    local drops = stores and safe(function() return stores:FindFirstChild("DropOffs") end, nil)
    if not drops then
        say("   Stores.DropOffs NOT FOUND")
        return
    end
    local best, bestD
    for _, d in ipairs(drops:GetChildren()) do
        local p, sz = boxOf(d)
        local dist = (p and here) and (p - here).Magnitude or nil
        if dist and (not bestD or dist < bestD) then best, bestD = d, dist end
        say(string.format("   %s  at %s%s%s", d:GetFullName(), posText(p),
            sz and string.format("  size %.0fx%.0fx%.0f", sz.X, sz.Y, sz.Z) or "",
            dist and string.format("  %.0f studs from you", dist) or ""))
    end
    if best then
        say("   -- nearest: " .. best:GetFullName())
        local attrs = attrsOf(best)
        if #attrs > 0 then say("      attrs: " .. table.concat(attrs, " ")) end
        for _, d in ipairs(safe(function() return best:GetDescendants() end, {})) do
            local cls = safe(function() return d.ClassName end, "?")
            if cls == "ProximityPrompt" then
                say(string.format("      prompt %s key=%s action='%s' enabled=%s",
                    d:GetFullName(), tostring(safe(function() return d.KeyCode end, "?")),
                    tostring(safe(function() return d.ActionText end, "")),
                    tostring(safe(function() return d.Enabled end, "?"))))
            elseif cls == "TextLabel" or cls == "TextButton" then
                say(string.format("      text %s = '%s'", d:GetFullName(),
                    tostring(safe(function() return d.Text end, ""))))
            else
                say("      " .. cls .. " " .. d.Name)
            end
        end
        if #safe(function() return best:GetDescendants() end, {}) == 0 then
            say("      (no children — the part itself is the whole pad)")
        end
    end
end

-- the machines near you: is a harvester spawned, and is its tank readable?
local function equipmentNear()
    say("")
    say("== equipment within 120 studs ==")
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local here = root and root.Position
    local equip = safe(function()
        return workspace:FindFirstChild("Objects")
            and workspace.Objects:FindFirstChild("Equipment")
    end, nil)
    if not equip or not here then say("   Objects.Equipment NOT FOUND"); return end
    local any = 0
    for _, m in ipairs(equip:GetChildren()) do
        local p = safe(function() return m:GetPivot().Position end, nil)
        local dist = p and (p - here).Magnitude or nil
        if dist and dist <= 120 then
            any += 1
            say(string.format("   %s  at %s  %.0f studs", m:GetFullName(), posText(p), dist))
            local attrs = attrsOf(m)
            if #attrs > 0 then say("      attrs: " .. table.concat(attrs, " ")) end
            for _, line in ipairs(cfgLines(m)) do say("      cfg." .. line) end
        end
    end
    if any == 0 then say("   (none — spawn the harvester/trailer here first)") end
end

local function signsAnywhere()
    say("")
    say("== signs / texts that mention fulfill / ship / drop / sell ==")
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local here = root and root.Position
    local localHits, farHits = {}, {}
    for _, d in ipairs(safe(function() return workspace:GetDescendants() end, {})) do
        local cls = safe(function() return d.ClassName end, "")
        if cls:find("TextLabel") or cls == "TextButton" then
            local txt = tostring(safe(function() return d.Text end, "") or "")
            local low = txt:lower()
            if low:find("fulfill", 1, true) or low:find("fulfil", 1, true)
                or low:find("ship", 1, true) or low:find("drop", 1, true)
                or low:find("sell", 1, true) then
                -- a label's spot is its gui's adornment, or the part holding it
                local p, probe = nil, d
                for _ = 1, 5 do
                    if not probe then break end
                    local ad = safe(function() return probe.Adornee end, nil)
                    if ad then p = select(1, boxOf(ad)); break end
                    if probe:IsA("BasePart") then p = safe(function() return probe.Position end, nil); break end
                    probe = probe.Parent
                end
                local dist = (p and here) and (p - here).Magnitude or nil
                local line = string.format("   '%s'  at %s%s  %s", txt, posText(p),
                    dist and string.format("  %.0f studs", dist) or "", d:GetFullName())
                if dist and dist <= 60 then
                    localHits[#localHits + 1] = line
                elseif #farHits < 12 then
                    farHits[#farHits + 1] = line
                end
            end
        end
    end
    say("   -- near you (<=60 studs)")
    if #localHits == 0 then say("      (none)") end
    for _, line in ipairs(localHits) do say(line) end
    say("   -- elsewhere (first 12)")
    if #farHits == 0 then say("      (none)") end
    for _, line in ipairs(farHits) do say(line) end
end

local function oldTargets()
    say("")
    say("== the other old sell targets (SellArea / Buildings) ==")
    local objects = safe(function() return workspace:FindFirstChild("Objects") end, nil)
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

    -- 1. the local answer first: what is offered here, what is underfoot, and
    --    what is close enough to be the pad. This is the part that names the
    --    unload action and its key.
    contextActions()
    standingOn()
    nearby(30)
    dropTargets()
    equipmentNear()

    -- 2. candidate buildings / models anywhere whose name says what this is
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
