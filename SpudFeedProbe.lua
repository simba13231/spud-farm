--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD FEED PROBE — animal feed / seed box dump (READ-ONLY)
═══════════════════════════════════════════════════════════════════════════
  Why: the milk loop needs to know HOW FULL the feed boxes are for the cows
       (the FeedDispenser billboard shows "277/500" in old dumps, but nothing
       yet says where that number lives or how a plot's dispenser is found).

  HOW TO USE (MuMu + Delta):
    1. Spawn in, walk to YOUR FARM, and stand next to the barn — the
       FeedDispenser / Feeder / AnimalFoodBox must be streamed in.
    2. Execute this file. It only reads; it presses nothing and moves nobody.
    3. It uploads the report and prints a short link (paste.rs, then 0x0.st)
       and copies that link to your clipboard. Send the link back.

  If upload is blocked (executor has no http request), the whole report is
  copied to the clipboard instead — paste it in a notes app and send it.

  The report contains public game structure + your username. Treat the link
  like the dump itself.
═══════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local out = {}
local function w(s) out[#out + 1] = tostring(s) end
local function header(s) w(""); w("══════ " .. s .. " ══════") end

local function pathOf(inst, maxLevels)
    local parts, cur, depth = {}, inst, 0
    while cur and cur ~= game and depth < (maxLevels or 6) do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
        depth += 1
    end
    return table.concat(parts, ".")
end

local function attrsOf(inst)
    local list = {}
    local ok, at = pcall(function() return inst:GetAttributes() end)
    if ok and at then
        for k, v in pairs(at) do list[#list + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(list)
    end
    return #list > 0 and table.concat(list, ", ") or "-"
end

local function confOf(inst)
    local cfg = inst:FindFirstChild("Configurations")
    if not cfg then return "-" end
    local list = {}
    for _, ch in ipairs(cfg:GetChildren()) do
        local ok, v = pcall(function()
            if ch:IsA("ValueBase") then return tostring(ch.Value) end
            return "?"
        end)
        list[#list + 1] = ch.Name .. "[" .. ch.ClassName .. "]=" .. tostring(v)
    end
    return #list > 0 and table.concat(list, ", ") or "(empty)"
end

local function ownerOf(inst)
    local p = inst
    for _ = 1, 12 do
        if not p then break end
        local ok, who = pcall(function()
            local cfg = p:FindFirstChild("Configurations")
            local o = cfg and cfg:FindFirstChild("Owner")
            if o and o:IsA("ObjectValue") and o.Value then return o.Value.Name end
            local a = p:GetAttribute("Owner")
            if type(a) == "string" and a ~= "" then return a end
            return nil
        end)
        if ok and who then return who end
        p = p.Parent
    end
    return nil
end

local function hrp()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function distTo(inst)
    local r = hrp()
    if not r then return nil end
    local ok, p = pcall(function()
        if inst:IsA("BasePart") then return inst.Position end
        return inst:GetPivot().Position
    end)
    if not ok or not p then return nil end
    return (p - r.Position).Magnitude
end

local function labelTexts(root, max)
    local list = {}
    for _, d in ipairs(root:GetDescendants()) do
        if #list >= (max or 24) then break end
        if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" then
            list[#list + 1] = pathOf(d, 8) .. " = \"" .. tostring(d.Text) .. "\""
        end
    end
    return list
end

local function promptsOf(root)
    local list = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local key = "?"
            pcall(function() key = d.KeyboardKeyCode.Name end)
            list[#list + 1] = string.format("%s action='%s' object='%s' key=%s enabled=%s dist=%.0f",
                pathOf(d, 7), tostring(d.ActionText), tostring(d.ObjectText), key,
                tostring(d.Enabled), d.MaxActivationDistance)
        end
    end
    return list
end

-- bounded tree: class, value, part position, prompt text, attributes
local function tree(root, maxDepth, maxLines)
    local count = 0
    local function rec(inst, depth)
        if count >= (maxLines or 180) then return end
        count += 1
        local bits = { string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]" }
        local okv, extra = pcall(function()
            if inst:IsA("ValueBase") then return " = " .. tostring(inst.Value) end
            if inst:IsA("BasePart") then
                return string.format(" @(%.1f, %.1f, %.1f)", inst.Position.X, inst.Position.Y, inst.Position.Z)
            end
            if inst:IsA("ProximityPrompt") then
                local key = "?"
                pcall(function() key = inst.KeyboardKeyCode.Name end)
                return string.format(" action='%s' key=%s enabled=%s",
                    tostring(inst.ActionText), key, tostring(inst.Enabled))
            end
            if inst:IsA("TextLabel") or inst:IsA("TextButton") then
                return " text='" .. tostring(inst.Text) .. "'"
            end
            return ""
        end)
        bits[#bits + 1] = okv and extra or " (unreadable)"
        local at = attrsOf(inst)
        if at ~= "-" then bits[#bits + 1] = " {" .. at .. "}" end
        w(table.concat(bits))
        if depth < maxDepth then
            for _, ch in ipairs(inst:GetChildren()) do rec(ch, depth + 1) end
        end
    end
    rec(root, 0)
    if count >= (maxLines or 180) then w("  … tree truncated") end
end

local ok, err = pcall(function()
    -- wait for the character so streaming has actually started
    local waited = 0
    while waited < 30 do
        local r = hrp()
        if r and LP.Character:FindFirstChildOfClass("Humanoid") then break end
        waited += 1
        task.wait(1)
    end
    task.wait(2)

    local r = hrp()
    w("SPUD FEED PROBE — Farming and Friends animal feed dump")
    w(string.format("placeId: %s   jobId: %s", tostring(game.PlaceId), tostring(game.JobId)))
    w(string.format("player: %s   pos: %s", LP.Name,
        r and string.format("%.1f, %.1f, %.1f", r.Position.X, r.Position.Y, r.Position.Z) or "?"))

    -- who owns which plot (same rule as the farm script)
    header("PLOTS AND OWNERS")
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, m in ipairs(plots:GetChildren()) do
            if m:IsA("Model") then
                local bill = m:FindFirstChild("PlotBillboard")
                local lab = bill and bill:FindFirstChild("Owner")
                w(string.format("plot %s  owner=%s  billboard=%s",
                    m.Name, tostring(ownerOf(m)),
                    (lab and lab:IsA("TextLabel")) and ("'" .. tostring(lab.Text) .. "'") or "-"))
            end
        end
    else
        w("(Workspace.Plots missing)")
    end

    -- every feed-ish instance in the world, top-most only
    local matches = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        local n = d.Name:lower()
        if n:find("feeddispenser", 1, true) or n == "feeder"
            or n:find("chickenfeeder", 1, true) or n:find("animalfoodbox", 1, true)
            or n:find("fooddispenser", 1, true) or n:find("seedbox", 1, true) then
            matches[#matches + 1] = d
        end
    end
    local set = {}
    for _, d in ipairs(matches) do set[d] = true end
    local roots = {}
    for _, d in ipairs(matches) do
        local nested, anc = false, d.Parent
        while anc do
            if set[anc] then nested = true break end
            anc = anc.Parent
        end
        if not nested then roots[#roots + 1] = d end
    end
    local ranked = {}
    for _, d in ipairs(roots) do ranked[#ranked + 1] = { obj = d, d = distTo(d) or 1e9 } end
    table.sort(ranked, function(a, b) return a.d < b.d end)

    header("FEED-ISH INSTANCES (top-most matches)")
    w(string.format("total matches: %d   top-most roots: %d", #matches, #roots))
    local counts = {}
    for _, d in ipairs(matches) do counts[d.Name] = (counts[d.Name] or 0) + 1 end
    local names = {}
    for k, v in pairs(counts) do names[#names + 1] = string.format("%s x%d", k, v) end
    table.sort(names)
    w("names: " .. (#names > 0 and table.concat(names, " · ") or "NONE"))

    local shown = 0
    for _, entry in ipairs(ranked) do
        local d = entry.obj
        if shown >= 6 then
            w(string.format("(+%d more not shown)", #ranked - shown))
            break
        end
        shown += 1
        w("")
        w(string.format("── #%d  %s [%s]  %.1f studs  owner=%s", shown, pathOf(d, 8),
            d.ClassName, entry.d, tostring(ownerOf(d))))
        w("   attrs: " .. attrsOf(d))
        w("   Configurations: " .. confOf(d))
        local labels = labelTexts(d, 24)
        if #labels > 0 then
            w("   visible text:")
            for _, s in ipairs(labels) do w("     " .. s) end
        else
            w("   visible text: none")
        end
        local ps = promptsOf(d)
        if #ps > 0 then
            w("   prompts:")
            for _, s in ipairs(ps) do w("     " .. s) end
        end
        w("   tree:")
        tree(d, 6, 170)
    end

    -- what the plot's building folder looks like
    header("OBJECTS.BUILDINGS CHILDREN")
    local objs = workspace:FindFirstChild("Objects")
    local buildings = objs and objs:FindFirstChild("Buildings")
    if buildings then
        local n = 0
        for _, m in ipairs(buildings:GetChildren()) do
            n += 1
            if n <= 60 then
                w(string.format("%s [%s]  dist=%s  owner=%s  kids=%d  attrs=%s",
                    pathOf(m, 8), m.ClassName,
                    (distTo(m) and string.format("%.0f", distTo(m))) or "?",
                    tostring(ownerOf(m)), #m:GetChildren(), attrsOf(m)))
            end
        end
        w("total children: " .. n)
    else
        w("(Workspace.Objects.Buildings missing)")
    end

    -- draggable food boxes: these are the "seed boxes" that feed the cows
    header("DRAGGABLE FOOD / SEED BOXES")
    local dobjs = objs and objs:FindFirstChild("DraggableObjects")
    if dobjs then
        local boxes = {}
        for _, m in ipairs(dobjs:GetChildren()) do
            local n = m.Name:lower()
            if n:find("food", 1, true) or n:find("seed", 1, true) or n:find("feed", 1, true) then
                boxes[#boxes + 1] = m
            end
        end
        local rankedBoxes = {}
        for _, m in ipairs(boxes) do rankedBoxes[#rankedBoxes + 1] = { obj = m, d = distTo(m) or 1e9 } end
        table.sort(rankedBoxes, function(a, b) return a.d < b.d end)
        w("food/seed draggables: " .. #rankedBoxes)
        for i, entry in ipairs(rankedBoxes) do
            local m = entry.obj
            if i > 24 then w("(+more)"); break end
            w(string.format("#%d %s [%s] dist=%.0f owner=%s attrs=%s",
                i, pathOf(m, 8), m.ClassName, entry.d, tostring(ownerOf(m)), attrsOf(m)))
            w("    Configurations: " .. confOf(m))
            local vals = {}
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("ValueBase") then
                    vals[#vals + 1] = pathOf(d, 8) .. "[" .. d.ClassName .. "]=" .. tostring(d.Value)
                end
                if #vals >= 16 then break end
            end
            if #vals > 0 then w("    values: " .. table.concat(vals, " · ")) end
        end
    else
        w("(Workspace.Objects.DraggableObjects missing)")
    end

    -- every "123/500" style text in the world
    header("CAPACITY TEXTS (n/m)")
    local cap = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if cap >= 40 then break end
        if d:IsA("TextLabel") and d.Text:match("^%s*%d+%s*/%s*%d+%s*$") then
            cap += 1
            w(pathOf(d, 9) .. " = \"" .. tostring(d.Text) .. "\"")
        end
    end
    if cap == 0 then w("(none found — the boards may not be streamed in here)") end

    -- what the game offers right where you stand
    header("CONTEXT ACTIONS NOW")
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        local acts = {}
        pcall(function()
            local btns = pg.GuiViews.HUD.PCGP_ContextActions.Buttons
            for _, b in ipairs(btns:GetChildren()) do
                if b:IsA("GuiObject") and b.Visible then acts[#acts + 1] = b.Name end
            end
        end)
        w("enabled-ish buttons: " .. (#acts > 0 and table.concat(acts, " · ") or "NONE"))
        local bills = {}
        pcall(function()
            local bb = pg.GuiViews.HUD.PCGP_ContextActions.Billboards
            for _, b in ipairs(bb:GetChildren()) do
                if b:IsA("BillboardGui") and b.Enabled then
                    bills[#bills + 1] = b.Name .. " -> " .. tostring(b.Adornee and b.Adornee:GetFullName())
                end
            end
        end)
        w("enabled billboards: " .. (#bills > 0 and table.concat(bills, " · ") or "NONE"))

        header("PLAYER GUI: FEED / FOOD / DISPENSER")
        local hits = 0
        for _, d in ipairs(pg:GetDescendants()) do
            if hits >= 60 then break end
            local n = d.Name:lower()
            if n:find("feed", 1, true) or n:find("food", 1, true) or n:find("dispenser", 1, true) then
                hits += 1
                local txt = (d:IsA("TextLabel") or d:IsA("TextButton")) and (" text='" .. tostring(d.Text) .. "'") or ""
                local en, vis = "-", "-"
                if d:IsA("LayerCollector") then en = tostring(d.Enabled) end
                if d:IsA("GuiObject") then vis = tostring(d.Visible) end
                w(string.format("%s [%s] enabled=%s visible=%s%s", pathOf(d, 9),
                    d.ClassName, en, vis, txt))
            end
        end
        if hits == 0 then w("(none)") end
    end

    w("")
    w("══════ END OF FEED PROBE ══════")
end)

if not ok then
    w("")
    w("PROBE ERROR: " .. tostring(err))
end

local text = table.concat(out, "\n")

-- ── upload (same rules as SpudDump): paste.rs first, then 0x0.st ──────────
local function httpPost(url, body)
    local fn = nil
    if type(request) == "function" then fn = request end
    if not fn and type(http_request) == "function" then fn = http_request end
    if not fn and type(http) == "table" and type(http.request) == "function" then fn = http.request end
    if not fn then return nil end
    local okRes, res = pcall(fn, {
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "text/plain; charset=utf-8",
            ["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64)",
        },
        Body = body,
    })
    if okRes and type(res) == "table" then return res end
    return nil
end

local function urlFrom(res, wantStatus)
    if not res or not res.Body or type(res.Body) ~= "string" then return nil end
    if wantStatus and res.StatusCode ~= wantStatus then return nil end
    if wantStatus == nil and res.StatusCode and res.StatusCode >= 300 then return nil end
    return res.Body:match("(%s*https?://%S+)%s*$") or res.Body:match("^(%s*https?://%S+)")
end

local uploadUrl = nil
if #text < 900000 then
    uploadUrl = urlFrom(httpPost("https://paste.rs/", text), 201)
        or urlFrom(httpPost("https://0x0.st", text))
end

local gotClipboard = pcall(function()
    assert(setclipboard, "no setclipboard")
    setclipboard(text)
end)
pcall(function() writefile("spud_feed_probe.txt", text) end)

print("══════════════ SPUD FEED PROBE DONE ══════════════")
print("lines: " .. #out .. "   bytes: " .. #text)
if uploadUrl then
    print("✔ UPLOADED — link (also copied to clipboard):")
    print("   " .. uploadUrl)
    pcall(setclipboard, uploadUrl)
else
    print("✘ upload failed (site blocked or no 'request' in executor)")
end
if gotClipboard then print("✔ the whole report is on your clipboard as a backup") end
print("════════════════════════════════════════════════")
