-- SPUD BARN PROBE — read-only, for one bug: "it herds the cows but does not
-- send them to the barn". It touches nothing and presses nothing.
--
-- HOW TO RUN
--   1. stand at the farm you saw it fail on (farm 1) and run this loader:
--        loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudBarnProbe.lua?t=" .. os.time()))()
--   2. it prints the barn tree straight away, then watches for herd mode for
--      60 seconds — START THE MILK LOOP NOW, so it catches the HerdTargets
--      while the herd is open.
--   3. paste everything it prints (it is one block) plus the milk lines around
--      "herd target" / "lasso pressed" from the same run.
--
-- WHAT IT ANSWERS
--   * is the stalls folder a DIRECT child of the barn model, or nested deeper?
--     (that is what decides which node the script calls "the barn")
--   * how many models are named like a barn, and where is each one — a name
--     lookup returns the FIRST one, which may be another player's plot
--   * what the game's HerdTargets are adorneed to, and which of their ancestors
--     has a Spots folder — i.e. which node "inside the barn" really means
--   * how far each barn is from each plot centre, so we can see whether the
--     nearest-to-the-centre pick can land on a neighbour's barn

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function say(s) print("[BARN] " .. s) end

local function pivotOf(inst)
    local ok, p = pcall(function() return inst:GetPivot().Position end)
    if ok and p then
        return string.format("%d,%d,%d", math.floor(p.X), math.floor(p.Y), math.floor(p.Z)), p
    end
    return "?", nil
end

local function spotsOf(b)
    local direct = b:FindFirstChild("Spots")
    local any
    pcall(function() any = b:FindFirstChild("Spots", true) end)
    return direct, any
end

-- the stall folders inside a Spots folder: each holds that stall's part
local function stallFolders(spots)
    local out = {}
    for _, num in ipairs(spots:GetChildren()) do
        local part = num:FindFirstChild("Adornee_BarnStallMenu", true)
        if part then out[#out + 1] = { folder = num, part = part } end
    end
    return out
end

local function kidsOf(inst)
    local out = {}
    for _, k in ipairs(inst:GetChildren()) do out[#out + 1] = k.Name end
    return table.concat(out, ",")
end

say("== SPUD BARN PROBE (read-only) ==")
say("place: " .. tostring(game.PlaceId) .. "  job: " .. tostring(game.JobId))

-- ── 1. Objects.Buildings: the building models the milk scan walks ─────────
local objects = workspace:FindFirstChild("Objects")
local bld = objects and objects:FindFirstChild("Buildings")
if not bld then
    say("!! Workspace.Objects.Buildings is MISSING - the narrow stall scan has nothing to walk")
else
    local kids = bld:GetChildren()
    say("Objects.Buildings has " .. #kids .. " child(ren):")
    for i, b in ipairs(kids) do
        local pos, p = pivotOf(b)
        local direct, any = spotsOf(b)
        local line = string.format("  %2d %-22s %-8s @ %s", i, b.Name, b.ClassName, pos)
        if direct then
            local stalls = stallFolders(direct)
            line = line .. string.format("  Spots=DIRECT  stalls=%d  Spots'=%s",
                #stalls, direct.Parent == b and (b.Name .. " (the building itself)") or tostring(direct.Parent and direct.Parent.Name))
            if stalls[1] then
                local chain, o = {}, stalls[1].folder
                for _ = 1, 8 do
                    if not o then break end
                    chain[#chain + 1] = o.Name
                    o = o.Parent
                end
                line = line .. "\n       first stall: " .. table.concat(chain, " < ")
                    .. "\n       stall folder kids: " .. kidsOf(stalls[1].folder)
                    .. "\n       adornee part: " .. stalls[1].part:GetFullName()
            end
        elseif any then
            local stalls = stallFolders(any)
            line = line .. string.format("  Spots=NESTED (path %s)  stalls=%d",
                any:GetFullName(), #stalls)
        else
            line = line .. "  no Spots folder"
        end
        say(line)
    end
end

-- ── 2. every model in the map whose name says barn ────────────────────────
local named = {}
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("Model") and d.Name:lower():find("barn", 1, true) then
        local pos, p = pivotOf(d)
        local direct = d:FindFirstChild("Spots")
        named[#named + 1] = string.format("  %-46s @ %s   Spots=%s",
            d:GetFullName(), pos, direct and "direct" or (d:FindFirstChild("Spots", true) and "nested" or "no"))
    end
end
say(#named .. " model(s) named like a barn in workspace (a name lookup returns the FIRST):")
for _, l in ipairs(named) do say(l) end

-- ── 3. every Spots folder, and where it hangs off the tree ────────────────
local spots = {}
for _, d in ipairs(workspace:GetDescendants()) do
    if d.Name == "Spots" then
        local parent = d.Parent
        spots[#spots + 1] = string.format("  %-52s  parent=%s (%s)  stalls=%d",
            d:GetFullName(), tostring(parent and parent.Name), tostring(parent and parent.ClassName),
            #stallFolders(d))
    end
end
say(#spots .. " folder(s) named Spots:")
for _, l in ipairs(spots) do say(l) end

-- ── 4. plots and how far each barn is from each plot centre ───────────────
local plots = workspace:FindFirstChild("Plots")
if plots then
    say("plots and the distance to each barn building:")
    local centres = {}
    for _, m in ipairs(plots:GetChildren()) do
        if m:IsA("Model") then
            local _, p = pivotOf(m)
            local owner = "?"
            pcall(function()
                local v = m:FindFirstChild("Configurations", true)
                local o = v and v:FindFirstChild("Owner")
                if o and o.Value then owner = o.Value.Name end
            end)
            if owner == "?" then
                pcall(function()
                    local b = m:FindFirstChild("PlotBillboard", true)
                    local lab = b and b:FindFirstChild("Owner")
                    if lab and lab:IsA("TextLabel") then owner = lab.Text end
                end)
            end
            centres[#centres + 1] = { name = m.Name, owner = owner, p = p }
        end
    end
    for _, c in ipairs(centres) do
        local bits = {}
        if bld then
            for _, b in ipairs(bld:GetChildren()) do
                if b:IsA("Model") then
                    local _, p = pivotOf(b)
                    if p and c.p then
                        bits[#bits + 1] = string.format("%s=%d", b.Name, math.floor((p - c.p).Magnitude))
                    end
                end
            end
        end
        say(string.format("  %-10s owner=%-16s centre=%s  %s", c.name, tostring(c.owner),
            c.p and string.format("%d,%d,%d", math.floor(c.p.X), math.floor(c.p.Y), math.floor(c.p.Z)) or "?",
            table.concat(bits, "  ")))
    end
end

-- ── 5. the game's herd targets, while herd mode is open ──────────────────
-- the script presses the HerdTarget that sits inside the barn, so this prints
-- each target's adornee chain and which ancestor owns a Spots folder
local function herdRoots()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local out = {}
    if not pg then return out end
    for _, c in ipairs(pg:GetChildren()) do
        if c.Name:lower():find("herd", 1, true) then out[#out + 1] = c end
    end
    return out
end

local function printTargets()
    local seenAny = false
    for _, root in ipairs(herdRoots()) do
        say("PlayerGui." .. root.Name .. " (" .. root.ClassName .. ") children: " .. #root:GetChildren())
        local targets = {}
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("BillboardGui") and d.Name == "HerdTarget" then targets[#targets + 1] = d end
        end
        if #targets > 0 then seenAny = true end
        say("  HerdTarget count: " .. #targets)
        for i, t in ipairs(targets) do
            local ad = t.Adornee
            local chain, barnish, o = {}, nil, ad
            for _ = 1, 10 do
                if not o then break end
                chain[#chain + 1] = o.Name
                if o:FindFirstChild("Spots") or o:FindFirstChild("Spots", true) then barnish = barnish or o end
                o = o.Parent
            end
            local names = {}
            for _, k in ipairs(t:GetChildren()) do names[#names + 1] = k.Name end
            say(string.format("   %d '%s' adornee=%s\n       kids=%s  trigger=%s\n       chain=%s\n       first ancestor with Spots: %s",
                i, t.Name .. "/" .. tostring(ad and ad.Name), ad and ad:GetFullName() or "?",
                table.concat(names, ","), tostring(t:FindFirstChild("Trigger")),
                table.concat(chain, " < "), barnish and barnish:GetFullName() or "NONE"))
        end
    end
    return seenAny
end

say("watching for herd mode for 60 s - START THE MILK LOOP NOW (herd target lists print when it opens)")
local printedOn = {}
local t0 = os.clock()
while os.clock() - t0 < 60 do
    local roots = herdRoots()
    for _, root in ipairs(roots) do
        local stamp = #root:GetChildren() .. ":" .. #root:GetDescendants()
        if not printedOn[root] or printedOn[root] ~= stamp then
            printedOn[root] = stamp
            say(string.format("--- t+%.1fs: herd UI appeared/changed", os.clock() - t0))
            printTargets()
        end
    end
    task.wait(1.5)
end
say("done - nothing was changed. Paste this whole block.")
