"""Count the teleports the clean pass makes, and the time it spends waiting.

The pass used to hop into every stall just to ask "dirty?": a dozen teleports
and a 0.2 s settle + 0.3 s floor each, every pass, on a clean barn.

The answer is read without moving - the game's own Filth value (direct child,
nested, or as an attribute), or a visible stain part - so this runs the REAL
milkClean / milkCleanUp / milkFilth / milkStain / milkTrigger over a fake barn
and counts teleports, key presses and virtual-clock seconds. A stall that cannot
be READ is not visited at all: it is cleaned at the stall while a cow there is
milkened, and the console says which one and what it holds.

    python tools/clean_visit_test.py [path-to-luau.exe] [git-ref]

With a git ref it runs that revision instead, which is how the "before" numbers
in the report were taken.
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

WANTED = ["milkTrigger", "milkStain", "milkFilth", "milkCleanUp", "milkClean"]
OPTIONAL = {"milkFilth"}

PRE = r"""
VT, TELEPORTS, PRESSES = 0, 0, 0
os = { clock = function() return VT end }
task = { wait = function(t) VT = VT + math.max(t or 0, 1 / 60) end }
LOG = {}
log = function(s) LOG[#LOG + 1] = s end
milkStopping = function() return false end
farmTookBody = function() return false end
Enum = { KeyCode = setmetatable({}, { __index = function(_, k) return k end }) }
print = print

local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
Vector3 = { new = function(x, y, z) return vec(x, y, z) end }

-- ── the game's own Clean billboard, in PlayerGui, adorned to whichever stall
--    the character stands in (that is what makes the action proximity gated)
local BILL = { Name = "CleanAnimalContainer", Enabled = false, Adornee = nil }
function BILL:FindFirstChild() return nil end
function BILL:GetDescendants() return {} end
local BILLS = { FindFirstChild = function(_, n) if n == "CleanAnimalContainer" then return BILL end end }
local CPA = { Billboards = BILLS, FindFirstChild = function(_, n) if n == "Billboards" then return BILLS end end }
local MAINHUD = { FindFirstChild = function(_, n) if n == "PCGP_ContextActions" then return CPA end end }
local HUD = { FindFirstChild = function(_, n) if n == "MainHUD" then return MAINHUD end end }
local GUIVIEWS = { FindFirstChild = function(_, n) if n == "HUD" then return HUD end end }
local PG = { GuiViews = GUIVIEWS, FindFirstChild = function() return nil end }
LocalPlayer = { Name = "Me", FindFirstChildOfClass = function() return PG end }

-- ── the barn: stalls 20 studs apart, each with the game's own dirt in one of
--    the shapes a build can use, its Center part, a trigger, and any stains
STALLS = {}
local HERE = -1000
local function part(name, x)
    return { Name = name, ClassName = "Part", Position = vec(x, 0, 0), Transparency = 0,
        IsA = function(self, cls) return cls == "BasePart" end }
end
local function value(name, v)
    return { Name = name, ClassName = "NumberValue", Value = v,
        IsA = function(self, cls) return cls == "ValueBase" end }
end

local function stallSpot(i, spec)
    local x = i * 20
    local centre, prox = part("Center", x), part("ProximityPart", x)
    local list = { centre, prox }
    for _ = 1, (spec.stains or 0) do list[#list + 1] = part("Stain", x) end
    local direct = spec.filth ~= nil and value("Filth", spec.filth) or nil
    local nested = spec.nested ~= nil and value("Filth", spec.nested) or nil
    local attr = (spec.attrs or {}).Filth
    local spot = {
        Name = "Spot" .. i, ClassName = "Folder", _x = x, _centre = centre,
        _noOffer = spec.noOffer,
        _dirty = (type(spec.filth) == "number" and spec.filth > 0)
            or (type(spec.nested) == "number" and spec.nested > 0)
            or (type(attr) == "number" and attr > 0)
            or (spec.stains or 0) > 0,
    }
    function spot:FindFirstChild(n, recursive)
        if n == "Center" then return centre end
        if n == "Filth" then
            if direct then return direct end
            if recursive then return nested end
            return nil
        end
        if n == "ProximityPart" then return prox end
        return nil
    end
    function spot:GetAttribute(name) return (spec.attrs or {})[name] end
    function spot:GetChildren()
        local out = { centre, prox }
        if direct then out[#out + 1] = direct end
        return out
    end
    function spot:GetDescendants() return list end
    return spot
end

-- moving is when the game re-adorns the billboard, exactly like the real thing
local function settle()
    BILL.Adornee, BILL.Enabled = nil, false
    for _, s in ipairs(STALLS) do
        local sp = s.spot
        if not sp._noOffer and math.abs(sp._x - HERE) < 6 then
            BILL.Adornee = sp._centre
            BILL.Enabled = sp._dirty
            return
        end
    end
end

milkTp = function(target, noWait)
    TELEPORTS = TELEPORTS + 1
    if math.abs(target.X - HERE) > 4 and not noWait then VT = VT + 0.2 end
    HERE = target.X
    settle()
    return true
end

pressKey = function()
    PRESSES = PRESSES + 1
    for _, s in ipairs(STALLS) do
        local sp = s.spot
        if math.abs(sp._x - HERE) < 6 and sp._dirty and not sp._refuse then
            sp._dirty = false
            BILL.Enabled = false -- the game's own answer: Clean is now off
            return
        end
    end
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function build(spec)
    STALLS = {}
    for i = 1, 12 do
        local sp = spec(i) or {}
        local spot = stallSpot(i, sp)
        spot._refuse = sp.refuse
        STALLS[i] = { spot = spot, pos = vec(i * 20, 0, 0) }
    end
    VT, TELEPORTS, PRESSES, LOG = 0, 0, 0, {}
    milkFilthSaid = nil
    HERE = -1000
end

local function run()
    local dirty, cleaned, unknown = milkClean(STALLS)
    return dirty, cleaned, unknown
end

-- 1. a clean barn: not one teleport, not one second of waiting
build(function() return { filth = 0 } end)
local dirty, cleaned, unknown = run()
check("clean barn: no teleports at all", TELEPORTS == 0, TELEPORTS .. " teleport(s)")
check("clean barn: no waiting at all", VT == 0, string.format("%.2fs", VT))
check("clean barn: nothing counted as dirty", dirty == 0 and cleaned == 0 and unknown == 0,
    string.format("dirty=%d cleaned=%d unknown=%d", dirty, cleaned, unknown))
check("clean barn: says so once", #LOG == 1 and LOG[1]:find("no teleports", 1, true) ~= nil,
    #LOG > 0 and LOG[1] or "no log")

-- 2. one dirty stall: exactly one visit, and it is that stall
build(function(i) return { filth = (i == 5) and 40 or 0 } end)
dirty, cleaned, unknown = run()
check("one dirty stall: exactly one teleport", TELEPORTS == 1, TELEPORTS .. " teleport(s)")
check("one dirty stall: cleaned and counted", dirty == 1 and cleaned == 1 and unknown == 0,
    string.format("dirty=%d cleaned=%d unknown=%d", dirty, cleaned, unknown))
check("one dirty stall: the key was pressed once", PRESSES == 1, PRESSES .. " press(es)")

-- 3. dirt that CANNOT be read is never a reason to move (user: "fix it so it
--    does not tp anymore") - and it is never counted as clean either
build(function(i)
    if i == 7 then return {} end -- no Filth value in any shape
    return { filth = 0 }
end)
dirty, cleaned, unknown = run()
check("unreadable dirt: no teleports", TELEPORTS == 0, TELEPORTS .. " teleport(s)")
check("unreadable dirt: nothing counted as cleaned", cleaned == 0 and unknown == 0,
    string.format("cleaned=%d unknown=%d", cleaned, unknown))
local said = false
for _, l in ipairs(LOG) do
    if l:find("no readable dirt value and are NOT visited", 1, true) then said = true end
end
check("unreadable dirt: the console says which stall and what it holds", said,
    LOG[1] or "no log")

-- 4. a stall the game will not clean: same three attempts as before
build(function(i) return { filth = (i == 3) and 10 or 0, refuse = (i == 3) } end)
dirty, cleaned, unknown = run()
check("a refusing stall: three presses, not counted as cleaned",
    PRESSES == 3 and cleaned == 0 and dirty == 1,
    string.format("presses=%d cleaned=%d dirty=%d", PRESSES, cleaned, dirty))

-- 5. the dirt as an ATTRIBUTE on the stall folder
build(function(i) return { attrs = { Filth = (i == 2) and 6 or 0 } } end)
dirty, cleaned, unknown = run()
check("attribute dirt: that stall is visited and cleaned",
    TELEPORTS == 1 and cleaned == 1, string.format("teleports=%d cleaned=%d", TELEPORTS, cleaned))

-- 6. the dirt as a value nested inside the stall folder
build(function(i) return { nested = (i == 4) and 9 or nil } end)
dirty, cleaned, unknown = run()
check("nested dirt: that stall is visited and cleaned",
    TELEPORTS == 1 and cleaned == 1, string.format("teleports=%d cleaned=%d", TELEPORTS, cleaned))

-- 7. stains only (the other readable signal)
build(function(i) return { stains = (i == 9) and 2 or 0 } end)
dirty, cleaned, unknown = run()
check("visible stains: that stall is visited and cleaned",
    TELEPORTS == 1 and cleaned == 1, string.format("teleports=%d cleaned=%d", TELEPORTS, cleaned))

-- 8. an unreadable stall does not hide a readable dirty one
build(function(i)
    if i == 1 then return {} end
    return { filth = (i == 11) and 3 or 0 }
end)
dirty, cleaned, unknown = run()
check("one blind stall + one dirty stall: only the dirty one is visited",
    TELEPORTS == 1 and cleaned == 1,
    string.format("teleports=%d cleaned=%d", TELEPORTS, cleaned))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def dedent(block: str) -> str:
    return "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return dedent(block)


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
