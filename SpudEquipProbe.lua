--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD EQUIP PROBE — what the game actually calls your machines (READ-ONLY)
═══════════════════════════════════════════════════════════════════════════
  Why: the farm loop assumes every machine carries an "EquipmentType"
       attribute (Tractor / Harvester / Plow / Planter / Cultivator / ...),
       but no dump ever captured that attribute — the only mentions are in
       our own code. If the game does not set it, nothing can tell a
       harvester from a tractor, and that is exactly what we need to see.

  HOW TO USE (MuMu + Delta):
    1. Spawn in, walk to YOUR FARM with your machines spawned and streamed in
       (the tractor, the harvester, the plow, the cultivator, the seeder, any
       trailer/silo you want milk in). If one is in storage, spawn it first.
    2. Execute this file. It only reads: it presses nothing, moves nobody.
    3. It uploads the report, prints one short link and copies it to your
       clipboard. Send that link back.

  If upload is blocked, the whole report is on your clipboard instead —
  paste it in a note and send it.

  The report holds public game structure plus your username. Treat the link
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
    if not cfg then return nil end
    local list = {}
    for _, ch in ipairs(cfg:GetChildren()) do
        local ok, v = pcall(function()
            if ch:IsA("ValueBase") then return tostring(ch.Value) end
            return "?"
        end)
        list[#list + 1] = ch.Name .. "[" .. ch.ClassName .. "]=" .. tostring(v)
    end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "(empty)"
end

local function hrp()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function distTo(inst)
    local r = hrp()
    if not r then return "-" end
    local ok, p = pcall(function()
        if inst:IsA("BasePart") then return inst.Position end
        return inst:GetPivot().Position
    end)
    if not ok or not p then return "?" end
    return string.format("%.0f", (p - r.Position).Magnitude)
end

local function posOf(inst)
    local ok, p = pcall(function() return inst:GetPivot().Position end)
    if not ok or not p then return "-" end
    return string.format("%.0f,%.0f,%.0f", p.X, p.Y, p.Z)
end

-- names of the parts a machine uses to tow / seed / hold, without dumping
-- hundreds of decorative parts
local KEY_PARTS = { "hitch", "seed", "detect", "tank", "capacity", "attach",
                    "tow", "link", "node", "grab", "fill", "spill", "cut",
                    "head", "blade", "disc", "wheel" }
local function keyPartsOf(model)
    local list = {}
    for _, d in ipairs(model:GetDescendants()) do
        if #list >= 30 then break end
        local n = d.Name:lower()
        for _, k in ipairs(KEY_PARTS) do
            if n:find(k, 1, true) then
                list[#list + 1] = d.Name .. "[" .. d.ClassName .. "]"
                break
            end
        end
    end
    return #list > 0 and table.concat(list, " · ") or "-"
end

local function guiTextsOf(model, max)
    local list = {}
    for _, d in ipairs(model:GetDescendants()) do
        if #list >= (max or 14) then break end
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
            list[#list + 1] = d.Name .. "=\"" .. tostring(d.Text) .. "\""
        end
    end
    return list
end

local function modelsIn(folder)
    local list = {}
    for _, m in ipairs(folder and folder:GetChildren() or {}) do
        if m:IsA("Model") then list[#list + 1] = m end
    end
    table.sort(list, function(a, b) return a.Name < b.Name end)
    return list
end

---------------------------------------------------------------- 0. who/where
header("WHO / WHERE")
w("account: " .. LP.Name .. " (" .. tostring(LP.UserId) .. ")")
w("place: " .. tostring(game.PlaceId) .. "  job: " .. tostring(game.JobId))
w("character: " .. tostring(LP.Character and LP.Character.Name or "nil"))

---------------------------------------------------------------- 1. the machines
local objects = workspace:FindFirstChild("Objects")
local equip = objects and objects:FindFirstChild("Equipment")
local allEquip = modelsIn(equip)

header("EVERY MACHINE IN Objects.Equipment  (" .. #allEquip .. ")")
if #allEquip == 0 then
    w("(none — the folder is missing or nothing is streamed in here)")
else
    for _, m in ipairs(allEquip) do
        w("")
        w(string.format("■ %s  [%s]", m.Name, m.ClassName))
        w("    path: " .. pathOf(m, 8))
        w("    attrs: " .. attrsOf(m))
        w("    conf: " .. tostring(confOf(m) or "-"))
        w(string.format("    stored=%s  dist=%s  pos=%s",
            tostring(m:GetAttribute("InStorage")), distTo(m), posOf(m)))
        w("    key parts: " .. keyPartsOf(m))
        local txt = guiTextsOf(m)
        if #txt > 0 then w("    gui text: " .. table.concat(txt, " · ")) end
        local kids = {}
        for _, c in ipairs(m:GetChildren()) do
            kids[#kids + 1] = c.Name .. "[" .. c.ClassName .. "]"
            if #kids >= 20 then break end
        end
        w("    children: " .. (#kids > 0 and table.concat(kids, " · ") or "-"))
    end
end

---------------------------------------------------------------- 2. does the tag exist?
header("ATTRIBUTE KEYS ACROSS ALL MACHINES (is there an EquipmentType?)")
do
    local seen, order = {}, {}
    for _, m in ipairs(allEquip) do
        local ok, at = pcall(function() return m:GetAttributes() end)
        if ok and at then
            for k, v in pairs(at) do
                if not seen[k] then
                    seen[k] = { n = 0, vals = {} }
                    order[#order + 1] = k
                end
                local rec = seen[k]
                rec.n += 1
                rec.vals[tostring(v)] = (rec.vals[tostring(v)] or 0) + 1
            end
        end
    end
    table.sort(order)
    if #order == 0 then
        w("NO ATTRIBUTES AT ALL on any machine — the script cannot detect types from attributes.")
    else
        for _, k in ipairs(order) do
            local rec = seen[k]
            local vals = {}
            for v, n in pairs(rec.vals) do vals[#vals + 1] = v .. " x" .. n end
            table.sort(vals)
            w(string.format("  %s  (%d/%d machines): %s", k, rec.n, #allEquip,
                table.concat(vals, ", ")))
        end
    end
end

header("CONFIGURATIONS KEYS ACROSS ALL MACHINES")
do
    local seen, order = {}, {}
    for _, m in ipairs(allEquip) do
        local cfg = m:FindFirstChild("Configurations")
        for _, ch in ipairs(cfg and cfg:GetChildren() or {}) do
            local key = ch.Name .. "[" .. ch.ClassName .. "]"
            if not seen[key] then seen[key] = 0; order[#order + 1] = key end
            seen[key] += 1
        end
    end
    table.sort(order)
    if #order == 0 then
        w("(no machine has a Configurations folder)")
    else
        for _, k in ipairs(order) do
            w(string.format("  %s  (%d machines)", k, seen[k]))
        end
    end
end

---------------------------------------------------------------- 3. where else machines live
header("OTHER MACHINE-LOOKING MODELS (outside Objects.Equipment)")
do
    local roots = { objects, workspace:FindFirstChild("Vehicles"),
                    workspace:FindFirstChild("Plots") }
    local hits = 0
    for _, root in ipairs(roots) do
        for _, m in ipairs(root and root:GetChildren() or {}) do
            if m:IsA("Model") and hits < 40 then
                local hasConf = m:FindFirstChild("Configurations") ~= nil
                local tag = m:GetAttribute("EquipmentType")
                local nameHit = tostring(m.Name):lower():find("tractor", 1, true)
                    or tostring(m.Name):lower():find("harvest", 1, true)
                    or tostring(m.Name):lower():find("trailer", 1, true)
                    or tostring(m.Name):lower():find("silo", 1, true)
                if tag ~= nil or nameHit then
                    hits += 1
                    w(string.format("%s  tag=%s conf=%s dist=%s", pathOf(m, 6),
                        tostring(tag), tostring(hasConf), distTo(m)))
                end
            end
        end
    end
    if hits == 0 then w("(none tagged or named like a machine here)") end
end

---------------------------------------------------------------- 4. what the HUD says
header("VEHICLE HUD (what the game calls the machine you are in/next to)")
do
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local shown = 0
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if shown >= 30 then break end
            if d:IsA("TextLabel") and d.Text ~= "" then
                local t = tostring(d.Text)
                if t:find("/", 1, true) or t:find("Tractor", 1, true)
                    or t:find("Harvest", 1, true) or t:find("Trailer", 1, true)
                    or t:find("Plow", 1, true) or t:find("Cultiv", 1, true)
                    or t:find("Seed", 1, true) then
                    shown += 1
                    w(pathOf(d, 9) .. ' = "' .. t .. '"')
                end
            end
        end
    end
    if shown == 0 then w("(nothing readable — sit in a machine and run again if you can)") end
end

---------------------------------------------------------------- 5. context actions
header("CONTEXT ACTIONS RIGHT NOW")
do
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local acts = {}
    pcall(function()
        local btns = pg.GuiViews.HUD.PCGP_ContextActions.Buttons
        for _, b in ipairs(btns:GetChildren()) do
            if b:IsA("GuiObject") and b.Visible then acts[#acts + 1] = b.Name end
        end
    end)
    w(#acts > 0 and table.concat(acts, " · ") or "NONE")
end

w("")
w("══════ END OF EQUIP PROBE ══════")

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
pcall(function() writefile("spud_equip_probe.txt", text) end)

print("══════════════ SPUD EQUIP PROBE DONE ══════════════")
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
