"""Run the REAL milkArrivals on a virtual clock and check the new behaviour.

The old flow waited for the WHOLE herd to be parked before the first press
(milkHerdSend's 45 s arrival window, then milkAllParked). The user asked for
the opposite: "the actual milking the cows to start when the first cow is in
the actual barn ready to milk then stop and wait till the next one for all the
cows". This asserts:

  * the first cow is milked before the later ones have even arrived
  * every cow is milked once, in arrival order
  * a cow that never arrives ends the wait after `quiet` seconds, not after
    the 300 s hard cap
  * the farm loop taking the body ends the wait at once

Usage:  python tools/milk_arrivals_test.py [path-to-luau.exe]
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
    if SYNC then SYNC() end -- the game parks cows as time passes, not on a scan
end }

STOP = false
TAKEN = false
LOG = {}
MILKS = {}
milkBatchSize = 5
-- the real milkStallOccupant (extracted below) caches into this
milkSpotFast = setmetatable({}, { __mode = "k" })

milkStopping = function() return STOP end
farmTookBody = function() return TAKEN and VT >= TAKEN end
log = function(s) LOG[#LOG + 1] = s end

-- fake world: every cow has an arrival time. It is in a stall from that
-- moment on, until milkCowInStall releases it (gate opened).
local world = { cows = {} }
local function cow(name, at, pct)
    local m = { Name = name, at = at, inStall = false, milked = false, pct = pct }
    world.cows[#world.cows + 1] = m
    return m
end

local function sync()
    for _, m in ipairs(world.cows) do
        if m.at and VT >= m.at and not m.milked then m.inStall = true end
    end
end
SYNC = sync

SCANS = 0 -- how many full animal scans the wait actually ran
milkCows = function()
    SCANS = SCANS + 1
    sync()
    local out = {}
    for i, m in ipairs(world.cows) do
        out[i] = {
            index = i, model = m, percent = m.pct,
            state = m.inStall and "IdleLocked" or "Wander",
            stall = m.milked and nil or {}, inBarn = true,
        }
    end
    return out
end

-- the plot's stalls, one per cow: an Occupant appears the moment the cow is in
-- its stall, which is the cheap gate the arrival wait now reads instead of
-- scanning every animal in the world
local function makeStalls(list)
    local out = {}
    for i, m in ipairs(list) do
        out[i] = { spot = { FindFirstChild = function(_, n)
            if n == "Occupant" and m.inStall then
                return { IsA = function(_, c) return c == "ObjectValue" end, Value = m }
            end
            return nil
        end } }
    end
    return out
end

milkInStallNow = function(c) return c.model.inStall == true end

milkCowInStall = function(c)
    local m = c.model
    MILKS[#MILKS + 1] = { name = m.Name, at = VT }
    VT = VT + 0.9                       -- the stall menu, the press, the gate
    m.inStall, m.milked = false, true
    if m.refuses then return false end
    return true
end
"""

POST = r"""
local function reset(cows, want, taken)
    world.cows = {}
    for _, c in ipairs(cows) do
        local m = cow(c[1], c[2], c[3] or 300)
        m.refuses = c[4] == true
    end
    VT, STOP, LOG, MILKS = 0.0, false, {}, {}
    SCANS = 0
    milkBatchSize = want or 5
    TAKEN = taken or false
    STALLS = makeStalls(world.cows)
end

local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-46s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the cow that lands first is milked long before the last one lands
reset({ { "c1", 1.1 }, { "c2", 1.6 }, { "c3", 6.0 }, { "c4", 6.5 }, { "c5", 11.0 } }, 5)
local done, handled, arrived = milkArrivals("Simba", nil, nil, STALLS, 5)
check("first milk before the last cow arrives", #MILKS > 0 and MILKS[1].at < 2.5,
    MILKS[1] and string.format("first milk at %.2fs, cow 5 lands at 11.0s", MILKS[1].at))
check("all five milked", done == 5 and handled == 5 and arrived == 5,
    string.format("done=%d handled=%d arrived=%d", done, handled, arrived))
check("milked in arrival order", #MILKS == 5 and MILKS[1].name == "c1" and MILKS[5].name == "c5",
    MILKS[1] and (MILKS[1].name .. " .. " .. MILKS[5].name) or "none")
check("no 25 s tail after the last cow", VT < 20, string.format("clock %.2fs", VT))
check("the wait did not re-scan every poll", SCANS <= 8,
    string.format("%d scan(s) over %.1fs of waiting", SCANS, VT))

-- 2. one cow never walks in: the wait ends `quiet` seconds after the last
--    event instead of the 300 s cap
reset({ { "c1", 1.1 }, { "c2", 2.0 }, { "c3", nil } }, 3)
done, handled, arrived = milkArrivals("Simba", nil, nil, STALLS, 3)
check("missing cow ends via the quiet window", done == 2 and handled == 2,
    string.format("done=%d handled=%d clock %.1fs", done, handled, VT))
check("quiet window is 25 s, not the 300 s cap", VT > 25 and VT < 45,
    string.format("clock %.1fs", VT))

-- 3. a cow that refuses to milk still gets one attempt, and the wait goes on
reset({ { "c1", 1.1, 300, true }, { "c2", 2.0 } }, 2)
done, handled, arrived = milkArrivals("Simba", nil, nil, STALLS, 2)
check("refused milk counts as handled, not as done", done == 1 and handled == 2,
    string.format("done=%d handled=%d", done, handled))

-- 4. the farm loop wants the body: bail at once
reset({ { "c1", nil }, { "c2", nil } }, 2, 3.0)
done, handled, arrived = milkArrivals("Simba", nil, nil, STALLS, 2)
check("farmTookBody stops the wait", handled == 0 and VT >= 3 and VT < 5,
    string.format("clock %.2fs", VT))

-- 5. nothing at all arrives: quiet window, no milk presses
reset({ { "c1", nil } }, 1)
done, handled, arrived = milkArrivals("Simba", nil, nil, STALLS, 1)
check("no arrival: nothing milked, exits on quiet", done == 0 and handled == 0 and #MILKS == 0,
    string.format("clock %.1fs", VT))
check("an empty wait scans once (the entry scan)", SCANS <= 1, string.format("%d scan(s)", SCANS))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def dedent(block: str) -> str:
    return "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())


def extract_occupant(text: str) -> str:
    """The REAL stall Occupant reader the arrival gate uses, not a copy."""
    m1 = re.search(r"^    function milkStallOccupant\(", text, re.M)
    m2 = re.search(r"^    local function milkStalls\(", text, re.M)
    if not m1 or not m2 or m2.start() < m1.start():
        raise SystemExit("milkStallOccupant not found in SpudFarm_Full.lua")
    return dedent(text[m1.start():m2.start()])


def extract(text: str) -> str:
    m1 = re.search(r"^    function milkArrivals\(", text, re.M)
    # the section header that follows the function (the switch one is a
    # different string, so the '(' keeps this unique)
    m2 = re.search(r"^    -- ▸ FEED TOP-UP \(", text[m1.start():] if m1 else "", re.M)
    if not m1 or not m2:
        raise SystemExit("milkArrivals not found in SpudFarm_Full.lua")
    block = text[m1.start():m1.start() + m2.start()]
    return dedent(block)


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        # the occupant reader first: it is a local in this chunk, so the
        # function defined after it captures it as an upvalue
        fh.write(PRE + extract_occupant(src) + "\n" + extract(src) + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip())
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
