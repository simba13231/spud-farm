"""Run the REAL milkHerdBatch and check the herd pick order.

The pick used to be whatever order Objects.Animals happened to list the cows
in, so a cow 200 studs from the barn could be armed first and the whole batch
waited on it. The user asked for the near ones to start ("i want it to start
with the cows that are in stall so it is much faster"): the ready cows are now
sorted by distance to the barn before anything is armed.

This asserts:
  * only the N nearest ready cows are armed (N = the typed 1-12 batch size)
  * a cow that refuses the Herd press is skipped and the next nearest is tried
  * a cow whose position cannot be read is never preferred over a readable one
  * a barn that is already at the batch size is not herded into at all

Usage:  python tools/herd_order_test.py [path-to-luau.exe]
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
local FRAME = 1 / 60
local VT = 0.0
os = { clock = function() return VT end }
task = { wait = function(t)
    VT = math.ceil((VT + math.max(t or 0, FRAME)) / FRAME - 1e-9) * FRAME
end }

LOG = {}
milkBatchSize = 5
milkStopping = function() return false end
farmTookBody = function() return false end
log = function(s) LOG[#LOG + 1] = s end
milkHerdOff = function() return true end

local V3 = {}
function V3.__sub(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V3) end
V3.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z) end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3)
end }

local barn = { GetPivot = function() return { Position = Vector3.new(0, 0, 0) } end }
workspace = { FindFirstChild = function(_, n)
    if n == "AutoWoodenBarn" then return barn end
    return nil
end }
-- no barn locked for this owner: the anchor falls back to the barn above
milkBarnPicked = function() return nil end

-- what got armed, in order
ARMED = {}
ARM_FAILS = {}
milkHerdArm = function(cow, first)
    local fails = false
    for _, i in ipairs(ARM_FAILS) do if i == cow.index then fails = true end end
    if fails then
        ARMED[#ARMED + 1] = { index = cow.index, dist = cow.dist, ok = false }
        return false
    end
    ARMED[#ARMED + 1] = { index = cow.index, dist = cow.dist, ok = true }
    return true
end
SENT = nil
milkHerdSend = function(picks)
    SENT = picks
    return 1
end

local function spot(occupied)
    return { Name = "Spots", FindFirstChild = function(_, n)
        if n == "Occupant" and occupied then
            return { IsA = function(_, c) return c == "ObjectValue" end, Value = { Name = "Cow" } }
        end
        return nil
    end }
end

local function stalls(n, occupied)
    local out = {}
    for i = 1, n or 12 do
        out[i] = { spot = spot(i <= (occupied or 0)), pos = Vector3.new(i, 0, 0) }
    end
    return out
end
"""

POST = r"""
local function cow(i, dist)
    return {
        index = i, model = { Name = "Cow" .. i }, percent = 300, state = "Wander",
        pos = dist and Vector3.new(dist, 0, 0) or nil, dist = dist or -1,
    }
end

local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-48s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function armedList()
    local out = {}
    for _, a in ipairs(ARMED) do out[#out + 1] = a.dist end
    return table.concat(out, ",")
end

local function reset()
    ARMED, ARM_FAILS, SENT, LOG = {}, {}, nil, {}
end

-- 1. nearest three of five, whatever order they are listed in
reset()
milkBatchSize = 3
milkHerdBatch(stalls(12), { cow(1, 90), cow(2, 20), cow(3, 55), cow(4, 5), cow(5, 70) })
check("nearest three armed first", armedList() == "5,20,55", "armed " .. armedList())
check("three picks handed to the lasso", SENT ~= nil and #SENT == 3,
    SENT and (#SENT .. " pick(s)") or "no lasso")
check("picks are the nearest cows", SENT ~= nil and SENT[1].cow.dist == 5 and SENT[3].cow.dist == 55,
    SENT and ("first " .. tostring(SENT[1].cow.dist) .. ", last " .. tostring(SENT[#SENT].cow.dist)) or "no lasso")

-- 2. more cows wanted than are ready: take them all, nearest first
reset()
milkBatchSize = 12
milkHerdBatch(stalls(12), { cow(1, 300), cow(2, 40) })
check("wanted 12, took the 2 that are ready", armedList() == "40,300", "armed " .. armedList())

-- 3. a cow with an unreadable position is tried last, never first
reset()
milkBatchSize = 2
milkHerdBatch(stalls(12), { cow(1, 10), cow(2, nil), cow(3, 30) })
check("unreadable position goes last", armedList() == "10,30", "armed " .. armedList())

-- 4. a refused Herd press moves on to the next nearest
reset()
milkBatchSize = 3
ARM_FAILS = { 2 }
milkHerdBatch(stalls(12), { cow(1, 90), cow(2, 20), cow(3, 55), cow(4, 5), cow(5, 70) })
check("refusal falls through to the next cow", armedList() == "5,20,55,70", "armed " .. armedList())
check("only accepted cows go to the lasso", SENT ~= nil and #SENT == 3 and SENT[2].cow.dist == 55,
    SENT and (#SENT .. " pick(s)") or "no lasso")

-- 5. the barn is already at the batch size: nothing is herded
reset()
milkBatchSize = 3
local done, tried, parked, picks = milkHerdBatch(stalls(12, 3), { cow(1, 10), cow(2, 20) })
check("full barn is not herded into", #ARMED == 0 and parked == 3 and done == 0,
    string.format("armed=%d parked=%d", #ARMED, parked))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str) -> str:
    m1 = re.search(r"^    function milkHerdBatch\(", text, re.M)
    m2 = re.search(r"^    -- ▸ THE MILK STEP", text, re.M)
    if not m1 or not m2 or m2.start() < m1.start():
        raise SystemExit("milkHerdBatch not found in SpudFarm_Full.lua")
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
