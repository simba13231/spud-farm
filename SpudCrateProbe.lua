-- SPUD CRATE PROBE — research only, changes nothing except ONE key press (E).
-- Run it while standing at a seed crate (let the farming loop tp you there,
-- then run this). It prints one block per crate to the executor console and
-- then tests whether E actually carries the nearest one.

local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

local function say(s) print("[CRATE] " .. s) end

local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function firstPart(m)
    return m:FindFirstChild("Primary") or m:FindFirstChildWhichIsA("BasePart", true)
end

local function enabledActs()
    local out = {}
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return out end
    pcall(function()
        local btns = pg.GuiViews.HUD.PCGP_ContextActions.Buttons
        for _, b in ipairs(btns:GetChildren()) do
            if b:IsA("GuiObject") and b.Visible then out[#out + 1] = b.Name end
        end
    end)
    return out
end

local function enabledBills()
    local out = {}
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return out end
    pcall(function()
        local bb = pg.GuiViews.HUD.PCGP_ContextActions.Billboards
        for _, b in ipairs(bb:GetChildren()) do
            if b:IsA("BillboardGui") and b.Enabled then
                local ad = b.Adornee
                out[#out + 1] = b.Name .. " -> " .. (ad and ad:GetFullName() or "?")
            end
        end
    end)
    return out
end

-- ── every model that carries the game's own SeedType tag ────────────────
local crates = {}
for _, d in ipairs(workspace:GetDescendants()) do
    if d.Name == "SeedType" then
        local m = d.Parent and d.Parent.Parent
        if m and m:IsA("Model") then
            local p = firstPart(m)
            if p then
                local seed = "?"
                pcall(function() seed = tostring(d.Value) end)
                crates[#crates + 1] = { m = m, p = p, seed = seed, tag = d }
            end
        end
    end
end

local r = hrp()
if not r then say("no HumanoidRootPart — can't measure") return end

say(string.format("character at (%.1f, %.1f, %.1f)  seated=%s  state=%s",
    r.Position.X, r.Position.Y, r.Position.Z,
    tostring(LP.Character:FindFirstChildOfClass("Humanoid")
        and LP.Character:FindFirstChildOfClass("Humanoid").SeatPart ~= nil),
    tostring(LP.Character:FindFirstChildOfClass("Humanoid")
        and LP.Character:FindFirstChildOfClass("Humanoid"):GetState())))
say("seed-tagged crates found: " .. #crates)

for _, c in ipairs(crates) do
    c.d = (c.p.Position - r.Position).Magnitude
    c.dy = c.p.Position.Y - r.Position.Y
end
table.sort(crates, function(a, b) return a.d < b.d end)

for i = 1, math.min(#crates, 8) do
    local c = crates[i]
    local m = c.m
    local cfg = m:FindFirstChild("Configurations")
    local function val(name)
        local v = cfg and cfg:FindFirstChild(name)
        if not v then return "nil" end
        local ok, x = pcall(function() return v.Value end)
        if not ok then return "?" end
        if typeof(x) == "Instance" then return x.Name end
        return tostring(x)
    end
    say(string.format("#%d  seed='%s'  %.1f studs away (dY %.1f)  %s",
        i, c.seed, c.d, c.dy, m:GetFullName()))
    say(string.format("     part='%s' pos=(%.1f, %.1f, %.1f)  size=%s",
        c.p.Name, c.p.Position.X, c.p.Position.Y, c.p.Position.Z,
        tostring(c.p.Size)))
    say(string.format("     attrs CarryCategory=%s CarryWeight=%s Precedence=%s PreventCarry=%s",
        tostring(m:GetAttribute("CarryCategory")),
        tostring(m:GetAttribute("CarryWeight")),
        tostring(m:GetAttribute("CarryPrecedence")),
        tostring(m:GetAttribute("PreventCarry"))))
    say(string.format("     cfg Owner=%s CurrentHolder=%s StoreClaim=%s Capacity=%s",
        val("Owner"), val("CurrentHolder"), val("StoreClaim"), val("Capacity")))
    local cb = m:FindFirstChild("CostBillboard", true)
    local pl = cb and cb:FindFirstChild("TextLabel", true)
    say("     price label: " .. (pl and ("'" .. pl.Text .. "'") or "none"))
end

-- ── what the game says you can do right here ────────────────────────────
say("context actions NOW: " .. (#enabledActs() > 0
    and table.concat(enabledActs(), " · ") or "NONE"))
say("billboards NOW: " .. (#enabledBills() > 0
    and table.concat(enabledBills(), " · ") or "NONE"))

if #crates == 0 then
    say("no crate in the workspace at all — the shelf is not streamed in here")
    return
end

local near = crates[1]
say(string.format("closest crate: '%s' seed=%s at %.1f studs",
    near.m.Name, near.seed, near.d))

-- ── does E carry it? ────────────────────────────────────────────────────
local function carriedState()
    local ch = LP.Character
    local links = ch and ch:FindFirstChild("CarryLinks")
    local names = {}
    if links then
        for _, v in ipairs(links:GetChildren()) do names[#names + 1] = v.Name end
    end
    local p = firstPart(near.m)
    return string.format("crate now %.1f studs from you (dY %.1f); CarryLinks=[%s]",
        p and (p.Position - r.Position).Magnitude or -1,
        p and (p.Position.Y - r.Position.Y) or 0,
        table.concat(names, ","))
end

say("BEFORE E: " .. carriedState())

local okKey, errKey = pcall(function()
    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.12)
    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end)
say("E sent via VirtualInputManager: " .. tostring(okKey) .. (okKey and "" or (" (" .. tostring(errKey) .. ")")))
task.wait(1.0)

say("AFTER E: " .. carriedState())
say("context actions AFTER: " .. (#enabledActs() > 0
    and table.concat(enabledActs(), " · ") or "NONE"))
say("billboards AFTER: " .. (#enabledBills() > 0
    and table.concat(enabledBills(), " · ") or "NONE"))

-- ── if the key did nothing, try the game's own button handler ───────────
if (firstPart(near.m).Position - r.Position).Magnitude > 12 then
    say("E did not carry it — trying the game's own PickupSeedBox button")
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local btn = pg and pg.GuiViews.HUD.PCGP_ContextActions.Buttons
        and pg.GuiViews.HUD.PCGP_ContextActions.Buttons:FindFirstChild("PickupSeedBox")
    say("PickupSeedBox button: " .. (btn and ("Visible=" .. tostring(btn.Visible)) or "MISSING"))
    local okAct, errAct = pcall(function()
        if getconnections then
            local cs = getconnections(btn.Activated)
            if #cs > 0 then cs[1]:Fire() return "fired Activated connection" end
        end
        btn:Activate()
        return "called :Activate()"
    end)
    say("button attempt: " .. tostring(okAct) .. " " .. tostring(errAct))
    task.wait(1.0)
    say("AFTER button: " .. carriedState())
end

say("── done. paste ALL [CRATE] lines ──")
