"""Run the REAL herd-send path and check which target gets the lasso press.

Symptom: "it herds the cows but does not send them to the barn". Arming works
(the cows get herded), so the failure is in milkHerdSend choosing the game's
HerdTarget to press. That choice is:

    - the target whose adornee IS the barn, or has the barn as an ancestor
      (milkHerdTargets marks those `inBarn`), else
    - "the one that is not a gate", nearest the barn first.

"The barn" there is `milkBarnPicked()` - the building the stall scan locked. If
that returns nil, the code falls back to `workspace:FindFirstChild(
"AutoWoodenBarn", true)`, which returns the FIRST barn in the map. Every plot
has a barn of that name, so the first one is often another player's.

This runs the real functions over fake worlds that differ only in layout:
 1. the dumped shape (Spots a direct child of the barn model)
 2. Spots nested one level deeper (barn/Structure/Spots)
 3. a loose field target mixed into the game's target list
 4. the same farm after its barn STREAMED OUT AND BACK as a new instance, with
    another plot's barn standing in Objects.Buildings ahead of ours

Usage:  python tools/herd_send_test.py [path-to-luau.exe] [git-ref]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

# order matters: each is a local in the generated chunk
WANTED = [
    "milkInBox", "milkTrigger", "milkBarnKey", "milkBarnLive", "milkBarnPicked", "milkBarnKeep",
    "milkBarnStalls", "milkStallOccupant", "milkStalls", "milkHerdTargets",
    "milkHerdSend", "milkHerdBatch",
]
OPTIONAL = {"milkBarnStalls", "milkStallOccupant", "milkBarnLive"}

PRE = r"""
CALLS = 0
local function call() CALLS = CALLS + 1 end

local NODE = {}
function NODE:FindFirstChild(name, recursive)
    call()
    local c = self.kids[name]
    if c then c.Parent = self return c end
    if recursive then
        for _, k in ipairs(self.list) do
            call()
            if k._name == name then return k end
            local hit = k:FindFirstChild(name, true)
            if hit then return hit end
        end
    end
    return nil
end
function NODE:GetChildren() CALLS = CALLS + #self.list return self.list end
function NODE:GetDescendants()
    local out = {}
    local function walk(n) for _, k in ipairs(n.list) do out[#out + 1] = k walk(k) end end
    walk(self)
    CALLS = CALLS + #out
    return out
end
function NODE:IsA(cls) call() return cls == rawget(self, "_cls") end
function NODE:GetPivot() call() return { Position = rawget(self, "Position") } end
function NODE:GetFullName() return (self.Parent and self.Parent:GetFullName() .. "." or "") .. self._name end

VT = 0
os = { clock = function() return VT end }
task = { wait = function(t) VT = VT + math.max(t or 0, 1 / 60) end }
PARK_HOOK = nil

local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
Vector3 = { new = function(x, y, z) return vec(x, y, z) end }

local function node(name, parent, cls)
    local o = setmetatable({
        _name = name, _cls = cls or "Model", kids = {}, list = {}, Parent = parent,
        Position = vec(0, 0, 0),
    }, { __index = function(t, k)
        if k == "Name" then return rawget(t, "_name") end
        return NODE[k]
    end })
    if parent then
        parent.list[#parent.list + 1] = o
        if not parent.kids[name] then parent.kids[name] = o end
    end
    return o
end

local function drop(inst) -- the world streams it out
    if not inst or not inst.Parent then return end
    local p = inst.Parent
    for i, k in ipairs(p.list) do if k == inst then table.remove(p.list, i) break end end
    if p.kids[inst._name] == inst then p.kids[inst._name] = p.list[1] end
    inst.Parent = nil
end

workspace = node("Workspace", nil, "DataModel")
local objects = node("Objects", workspace)
local animals = node("Animals", objects)
local bld = node("Buildings", objects)
LOG = {}
log = function(s) LOG[#LOG + 1] = s end
milkUser = "Simba"
milkBarns = {}
milkSpotFast = setmetatable({}, { __mode = "k" })
milkBatchSize = 2
milkStopping = function() return false end
farmTookBody = function() return false end
milkHerdOff = function() return true end

-- the barn building, in the dumped shape: <barn>.Spots.<n>.Adornee_BarnStallMenu
-- `nested` puts a folder between the barn model and Spots; `tag` is that
-- plot's owner; `door` names the part the game adornees a HerdTarget to
local function barn(name, stalls, nested, tag, x, door, ownerTag)
    local b = node(name, bld)
    b.Position = vec(x or 0, 0, 0)
    local mid = nested and node("Structure", b) or b
    local spots = node("Spots", mid)
    for i = 1, stalls do
        local num = node("Spot" .. i, spots)
        local part = node("Adornee_BarnStallMenu", num, "BasePart")
        part.Position = vec((x or 0) + i * 5, 0, 0)
        local prox = node("ProximityPart", num, "BasePart")
        prox.Position = part.Position
        node("Occupant", num, "ObjectValue")
    end
    b._door = node(door or "Door", b, "BasePart")
    b._door.Position = vec((x or 0) + 2, 0, 0) -- the door stands in the barn
    return b
end

-- the game's herd UI: a HerdTarget per barn door/ gate, plus optionally a
-- loose one far from any barn
local function herdingVisuals(list, stray)
    LocalPlayer.list, LocalPlayer.kids = {}, {}
    local pg = node("PlayerGui", LocalPlayer, "PlayerGui")
    pg.Parent = LocalPlayer
    local vis = node("HerdingVisuals", pg)
    local function target(label, adornee)
        local t = node("HerdTarget", vis, "BillboardGui")
        t.Adornee = adornee
        node("Trigger", t, "Part")
    end
    for _, b in ipairs(list) do
        target("Door", b._door)
        target("Gate", b._door)
    end
    if stray then target("FieldSpot", node("HerdSpot", workspace, "BasePart")) end
    return vis
end

-- the owner read, measured elsewhere: this test is about the send path
milkOwnerOf = function(inst) call() return rawget(inst, "_ownerTag") end

PRESSED, TP = {}, {}
invokeHandlers = function(trig)
    PRESSED[#PRESSED + 1] = trig and trig.Parent and trig.Parent.Adornee and trig.Parent.Adornee.Name or "?"
    if PARK_HOOK then PARK_HOOK() end -- the game parks the herd once the barn is pressed
    return true, "connection:Fire"
end
milkTp = function(pos) TP[#TP + 1] = pos return true end
milkHerdArm = function(cow, first) return true end

local LP = node("LocalPlayer", nil, "Player")
LP.FindFirstChildOfClass = function(_, cls) call() return LP.kids[cls] end
LocalPlayer = LP
LP.Parent = nil

CF = {
    Position = vec(0, 0, 0),
    PointToObjectSpace = function(self, p)
        return vec(p.X - self.Position.X, p.Y - self.Position.Y, p.Z - self.Position.Z)
    end,
}
SIZE = { X = 400, Y = 100, Z = 400 }
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-52s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function cow(i, dist)
    local m = node("Cow" .. i, animals)
    return { index = i, model = m, percent = 300, state = "Wander", pos = vec(dist or 0, 0, 0) }
end

-- the game parks the armed cows once the barn is pressed
local function park(stalls, cows)
    for i, c in ipairs(cows) do
        local s = stalls[i]
        if s then
            local o = s.spot:FindFirstChild("Occupant")
            if o then o.Value = c.model end
            c.model.Parent = nil
        end
    end
end

local function pass(label, stalls, cows, quiet)
    PRESSED, LOG, VT = {}, {}, 0
    PARK_HOOK = function() park(stalls, cows) end
    local got = milkHerdBatch(stalls, cows)
    local locked = milkBarns["simba"]
    print(string.format("--- %s: %d stall(s), lock=%s(%s), pressed=%s, got=%d", label, #stalls,
        locked and tostring(locked.inst and locked.inst._name or "dead") or "none",
        locked and tostring(locked.inst and locked.inst.Parent ~= nil) or "-",
        #PRESSED > 0 and table.concat(PRESSED, ",") or "NONE", got))
    if not quiet then for _, l in ipairs(LOG) do print("      " .. l) end end
    return stalls, PRESSED, locked, got
end

local function freshWorld(opts)
    bld.list, bld.kids = {}, {}
    animals.list, animals.kids = {}, {}
    milkBarns = {}
    milkSpotFast = setmetatable({}, { __mode = "k" })
    local list = {}
    if opts.neighbour then
        -- another plot's barn, listed FIRST in Objects.Buildings, so a name
        -- lookup finds it before ours
        table.insert(list, barn("AutoWoodenBarn", 10, false, "Other", 9000, "NeighbourDoor"))
    end
    local ours = barn("AutoWoodenBarn", 12, opts.nested, "Simba", 0, "OursDoor")
    table.insert(list, ours)
    herdingVisuals(list, opts.stray)
    return list, ours
end

-- 1. the dumped shape: Spots is a direct child of the barn model, and the
--    game's HerdTarget is adorneed inside that same model
local _, ours = freshWorld({})
local stalls = milkStalls("Simba", CF, SIZE)
local cows = { cow(1, 10), cow(2, 20) }
stalls, pressed, locked, got = pass("direct Spots (dumped shape)", stalls, cows)
check("the barn's own door is the one pressed", pressed[1] == "OursDoor", table.concat(pressed, ","))
check("the lock is the barn model itself", locked ~= nil and locked.inst == ours)
check("the stall the cows go to is inside the barn", #stalls > 0 and stalls[1].spot.Parent._name == "Spots")

-- 2. Spots nested one level deeper (barn/Structure/Spots)
freshWorld({ nested = true })
stalls = milkStalls("Simba", CF, SIZE)
cows = { cow(1, 10), cow(2, 20) }
stalls, pressed = pass("nested Spots (barn/Structure/Spots)", stalls, cows)
check("a nested Spots still finds the stalls", #stalls > 0, tostring(#stalls) .. " stall(s)")
check("the barn's own door is still pressed", pressed[1] == "OursDoor", table.concat(pressed, ","))

-- 3. a target that is NOT inside any barn (the game draws it in the field)
freshWorld({ stray = true })
stalls = milkStalls("Simba", CF, SIZE)
cows = { cow(1, 10), cow(2, 20) }
stalls, pressed = pass("a loose field target in the list", stalls, cows)
check("the barn target still wins over the loose one", pressed[1] == "OursDoor", table.concat(pressed, ","))

-- 4. the farm's barn streamed out and came back as a NEW instance, with another
--    plot's barn standing ahead of ours in Objects.Buildings. Pass 1 locks the
--    barn; then the barn is destroyed and rebuilt identically (same name, same
--    spot), which is what streaming does - and pass 2 must still press OUR barn
local list, firstBarn = freshWorld({ neighbour = true })
stalls = milkStalls("Simba", CF, SIZE)
cows = { cow(1, 10), cow(2, 20) }
stalls, pressed = pass("pass 1 (barn live, neighbour ahead)", stalls, cows, true)
check("pass 1 presses our door", pressed[1] == "OursDoor", table.concat(pressed, ","))

local neighbour = list[1]
drop(firstBarn)                     -- it streams out...
local rebuilt = barn("AutoWoodenBarn", 12, false, "Simba", 0, "OursDoor")  -- ...and back
herdingVisuals({ neighbour, rebuilt }, false)
stalls = milkStalls("Simba", CF, SIZE)
cows = { cow(1, 10), cow(2, 20) }
stalls, pressed, locked, got = pass("pass 2 (barn rebuilt as a new instance)", stalls, cows)
check("the barn's stalls are still found after the rebuild", #stalls > 0, tostring(#stalls) .. " stall(s)")
check("the lock follows the rebuilt barn", locked ~= nil and locked.inst == rebuilt,
    locked and tostring(locked.inst and locked.inst._name) or "no lock")
check("pass 2 still presses OUR door, not the neighbour's",
    pressed[1] == "OursDoor", table.concat(pressed, ","))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else None
    src = SRC.read_text(encoding="utf-8")
    if ref:
        src = subprocess.run(["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT,
                             capture_output=True, encoding="utf-8", errors="replace").stdout
    parts = []
    for name in WANTED:
        code = extract(src, name)
        if not code:
            if name in OPTIONAL:
                continue
            print("missing " + name)
            return 2
        parts.append(code)
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + "\n" + "\n\n".join(parts) + "\n" + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1500:])
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
