"""Run the REAL barn-lock helpers and check the rules the user asked for.

"if the user has more than 1 barn make it chose only 1 of the barns to use for
the rest of the scripts life untill reloaded".

This asserts, against the real milkBarnKey / milkBarnPicked / milkBarnKeep:
  * with two buildings, the stalls of ONE are kept and the other's are dropped
    (the building nearest the plot centre wins)
  * the pick is made once per owner and kept for the session, whatever order
    the world lists the stalls in
  * a second owner picks their own building
  * a building streamed out and rebuilt (new instance, same place) is still
    recognised, so the lock survives streaming
  * a stall whose building cannot be read is never dropped
  * a farm with a single building never logs a lock

Usage:  python tools/barn_lock_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

PRE = r"""
-- real Positions carry X/Y/Z, and milkBarnKey reads them
local V3 = {}
function V3.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V3) end
V3.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    if k == "Position" then return t end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end }

LocalPlayer = { Name = "Me" }
LOG = {}
log = function(s) LOG[#LOG + 1] = s end

local function barn(name, x)
    return {
        Name = name, Parent = true,
        GetPivot = function() return { Position = Vector3.new(x, 0, 0) } end,
    }
end

BARN_NEAR = barn("AutoWoodenBarn", 10)
BARN_FAR = barn("AutoWoodenBarn", 200)
BARN_BOB = barn("SmallBarn", 5) -- nearer than BARN_NEAR, so Bob locks to his own
CF = { Position = Vector3.new(0, 0, 0) }

local function stall(b, x)
    return { barn = b, pos = Vector3.new(x or 0, 0, 0) }
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-52s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function fresh()
    milkBarns, LOG, milkUser = {}, {}, "Simba"
end

-- 1. two buildings: the near one is kept, the far one's stalls are dropped
fresh()
local out = { stall(BARN_FAR), stall(BARN_NEAR), stall(BARN_FAR), stall(BARN_NEAR) }
local kept, dropped = milkBarnKeep(out, "Simba", CF)
check("one building kept, the other dropped", #kept == 2 and dropped == 2,
    string.format("kept %d, dropped %d", #kept, dropped))
check("the near building wins", kept[1].barn == BARN_NEAR, tostring(kept[1].barn.Name))
check("the lock is said once in the log", #LOG == 1, table.concat(LOG, " | "))

-- 2. every later cycle keeps it, whatever order the world lists the stalls in
local before = #LOG
local kept2 = milkBarnKeep({ stall(BARN_NEAR), stall(BARN_FAR), stall(BARN_NEAR) }, "Simba", CF)
check("same building on the next cycle", #kept2 == 2 and kept2[1].barn == BARN_NEAR,
    string.format("kept %d", #kept2))
check("no second lock line", #LOG == before, table.concat(LOG, " | "))

-- 3. a second farm picks its own building, without disturbing the first
local bob = milkBarnKeep({ stall(BARN_BOB), stall(BARN_NEAR) }, "Bob", CF)
check("another owner locks separately",
    #bob == 1 and bob[1].barn == BARN_BOB and milkBarns["simba"].inst == BARN_NEAR,
    string.format("bob kept %d, simba still on %s", #bob, tostring(milkBarns["simba"].inst.Name)))

-- 4. the barn was streamed out and rebuilt: new instance, same place
local rebuilt = barn("AutoWoodenBarn", 10)
local kept3 = milkBarnKeep({ stall(rebuilt), stall(BARN_FAR) }, "Simba", CF)
check("a rebuilt barn at the same spot is recognised",
    #kept3 == 1 and kept3[1].barn == rebuilt, string.format("kept %d", #kept3))

-- 5. a stall with no readable building is never dropped
local kept4 = milkBarnKeep({ stall(BARN_FAR), stall(nil) }, "Simba", CF)
check("an unreadable stall is kept", #kept4 == 1 and kept4[1].barn == nil,
    string.format("kept %d", #kept4))

-- 6. one building on the farm: no lock line, everything kept
fresh()
local kept5, dropped5 = milkBarnKeep({ stall(BARN_NEAR), stall(BARN_NEAR) }, "Simba", CF)
check("single barn: nothing dropped, nothing logged",
    #kept5 == 2 and dropped5 == 0 and #LOG == 0,
    string.format("kept %d, dropped %d, log %d", #kept5, dropped5, #LOG))

-- 7. milkBarnPicked: the instance while it lives, nil once it is gone
fresh()
milkBarnKeep({ stall(BARN_NEAR), stall(BARN_FAR) }, "Simba", CF)
check("picked building is handed to the other steps", milkBarnPicked() == BARN_NEAR,
    tostring(milkBarnPicked() and milkBarnPicked().Name))
BARN_NEAR.Parent = nil
check("a streamed-out build falls back to nil", milkBarnPicked() == nil,
    tostring(milkBarnPicked()))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str) -> str:
    m1 = re.search(r"^    milkBarns = \{\}", text, re.M)
    m2 = re.search(r"^    local function milkStalls\(", text, re.M)
    if not m1 or not m2 or m2.start() < m1.start():
        raise SystemExit("the barn-lock helpers were not found in SpudFarm_Full.lua")
    block = text[m1.start():m2.start()]
    return "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + extract(src) + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip())
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
