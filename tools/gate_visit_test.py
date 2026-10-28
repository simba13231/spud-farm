"""Does letting a cow out still need a teleport?

Opening the stall gate used to always hop to `Gate.ProximityPart` and sleep a
flat 0.9 s first. But the game's `BarnDoorInteract` billboard names THAT gate
(Adornee = its ProximityPart) wherever the press comes from, and after milking a
cow the character is already standing in the stall - so the hop and the settle
were pure waste whenever the action is already up.

This runs the REAL milkGateOpen against a fake gate and counts teleports. The
cow's own answer (Occupant / AnimoidState) is stubbed, since that is not what
changed here.

    python tools/gate_visit_test.py [path-to-luau.exe] [git-ref]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

WANTED = ["milkGateOpen"]

PRE = r"""
VT, TELEPORTS, PRESSES = 0, 0, 0
os = { clock = function() return VT end }
task = { wait = function(t) VT = VT + math.max(t or 0, 1 / 60) end }
LOG = {}
log = function(s) LOG[#LOG + 1] = s end
milkStopping = function() return false end
farmTookBody = function() return false end
Enum = { KeyCode = setmetatable({}, { __index = function(_, k)
    return { Name = k } end }) }

local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end }

-- the game's own door billboard, adorned to whichever gate we stand at
BILL = { Name = "BarnDoorInteract", Enabled = true, Adornee = nil, _text = "E | Open" }
function BILL:GetDescendants()
    return { { Text = "E", IsA = function(_, c) return c == "TextLabel" end },
             { Text = self._text, IsA = function(_, c) return c == "TextLabel" end } }
end
local BILLS = { FindFirstChild = function(_, n) if n == "BarnDoorInteract" then return BILL end end }
local CPA = { Billboards = BILLS, FindFirstChild = function(_, n) if n == "Billboards" then return BILLS end end }
local MAINHUD = { FindFirstChild = function(_, n) if n == "PCGP_ContextActions" then return CPA end end }
local HUD = { FindFirstChild = function(_, n) if n == "MainHUD" then return MAINHUD end end }
local GUIVIEWS = { FindFirstChild = function(_, n) if n == "HUD" then return HUD end end }
local PG = { GuiViews = GUIVIEWS, FindFirstChild = function() return nil end }
-- the character really moves, so "am I already at the gate" is answerable
local CHAR = { Position = Vector3.new(-500, 0, 0) }
LocalPlayer = { Name = "Me", FindFirstChildOfClass = function() return PG end,
    Character = { FindFirstChild = function(_, k)
        if k == "HumanoidRootPart" then return CHAR end
    end } }

-- where we are, and what the cow is doing: both change when the key lands
HERE = nil
GATE = nil
local OCC, STATE = nil, {}
milkStallOccupant = function() return OCC end
milkStateOf = function(m) return STATE[m] end

milkTp = function(target, noWait)
    TELEPORTS = TELEPORTS + 1
    if not noWait then VT = VT + 0.2 end
    HERE = target.X
    CHAR.Position = target
    if target.X == GATE then BILL.Adornee = GATE_PART end
    return true
end

pressKey = function()
    PRESSES = PRESSES + 1
    -- the game's answer: the key opens the gate, the cow walks out
    OCC = nil
    for m in pairs(STATE) do STATE[m] = "Wander" end
end

GATE_PART = { Position = Vector3.new(0, 0, 0),
    IsA = function(_, c) return c == "BasePart" end }
local function fakeSpot()
    return { Name = "Spot1",
        FindFirstChild = function(_, n)
            if n == "Gate" then
                return { FindFirstChild = function(_, k)
                    if k == "ProximityPart" then return GATE_PART end
                end }
            end
            return nil
        end }
end

-- normal state: a cow parked in the stall, the door not offered yet
local function reset(offerDoor, text)
    VT, TELEPORTS, PRESSES, LOG = 0, 0, 0, {}
    BILL._text = text or "E | Open"
    BILL.Adornee = offerDoor and GATE_PART or nil
    local cowModel = { Name = "Cow1" }
    STATE = { [cowModel] = "IdleLocked" }
    OCC = { IsA = function(_, c) return c == "ObjectValue" end, Value = cowModel }
    CHAR.Position = Vector3.new(-500, 0, 0) -- back in the stall end of the barn
    return fakeSpot(), { index = 1, model = cowModel }
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the action is already up: no teleport, no waiting, the key is pressed
local spot, cow = reset(true)
local out = milkGateOpen(spot, cow)
check("door offered: no teleport", TELEPORTS == 0, TELEPORTS .. " teleport(s)")
check("door offered: no waiting", VT == 0, string.format("%.2fs", VT))
check("door offered: the key was pressed and the cow is out", out == true and PRESSES == 1,
    string.format("returned=%s presses=%d", tostring(out), PRESSES))

-- 2. the action is not up yet: that is when the hop is worth it
spot, cow = reset(false)
GATE = -3 -- stand three studs from the gate so the move is a real move
GATE_PART.Position = Vector3.new(GATE, 0, 0)
out = milkGateOpen(spot, cow)
check("door not offered: exactly one teleport", TELEPORTS == 1, TELEPORTS .. " teleport(s)")
check("door not offered: still opens, cow out", out == true and PRESSES == 1,
    string.format("returned=%s presses=%d", tostring(out), PRESSES))

-- 3. the game never offers the door: three attempts, then an honest false
spot, cow = reset(false)
GATE = nil -- the billboard never turns up
out = milkGateOpen(spot, cow)
check("no door action at all: one hop, then it polls from there",
    TELEPORTS == 1 and PRESSES == 0 and out == false,
    string.format("teleports=%d presses=%d returned=%s", TELEPORTS, PRESSES, tostring(out)))
check("no door action at all: says so",
    LOG[#LOG] and LOG[#LOG]:find("never opened", 1, true) ~= nil, LOG[#LOG] or "no log")

-- 4. the gate is ALREADY open: pressing again would shut it on the cow
spot, cow = reset(true, "E | Close")
OCC = nil -- and the cow is out already, so nothing to press
for m in pairs(STATE) do STATE[m] = "Wander" end
out = milkGateOpen(spot, cow)
check("gate already open: no key press", PRESSES == 0, PRESSES .. " press(es)")
check("gate already open: reports the cow is out", out == true, tostring(out))

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
            print("missing " + name)
            return 2
        parts.append(code)
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + "\n" + "\n\n".join(parts) + "\n" + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1200:])
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
