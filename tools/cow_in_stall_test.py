"""Run the REAL milkCowInStall: does it clean, wait, milk, and let the cow out?

The fix under test: the per-cow clean used to read the game's Clean action ONCE,
right after a teleport with no settle. A nil read ("not this stall yet") skipped
the clean entirely, so a dirty stall was milked in. It now polls for up to
0.5 s before deciding, and the 2 s clean is still waited out.

    python tools/cow_in_stall_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["milkCleanUp", "milkCowInStall"]

PRE = r"""
VT, PRESSES, TELEPORTS, GATES, SETTLE = 0, 0, 0, 0, nil
os = { clock = function() return VT end }
task = { wait = function(t)
    VT = VT + math.max(t or 0, 1 / 60)
    if SETTLE then SETTLE() end
end }
LOG = {}
log = function(s) LOG[#LOG + 1] = s end
milkStopping = function() return false end
farmTookBody = function() return false end

local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end }
Enum = { KeyCode = setmetatable({}, { __index = function(_, k) return k end }) }

-- the game's Clean billboard, adorned to the stall we stand in
CENTRE = { Name = "Center", Position = Vector3.new(0, 0, 0),
    IsA = function(_, c) return c == "BasePart" end }
BILL = { Name = "CleanAnimalContainer", Enabled = false, Adornee = nil }
local BILLS = { FindFirstChild = function(_, n)
    if n == "CleanAnimalContainer" then return BILL end
end }
local CPA = { Billboards = BILLS, FindFirstChild = function(_, n)
    if n == "Billboards" then return BILLS end
end }
local MAINHUD = { FindFirstChild = function(_, n)
    if n == "PCGP_ContextActions" then return CPA end
end }
local HUD = { FindFirstChild = function(_, n)
    if n == "MainHUD" then return MAINHUD end
end }
local GUIVIEWS = { FindFirstChild = function(_, n) if n == "HUD" then return HUD end end }
local PG = { GuiViews = GUIVIEWS, FindFirstChild = function() return nil end }
LocalPlayer = { Name = "Me", FindFirstChildOfClass = function() return PG end }

function milkTrigger() return { Position = Vector3.new(0, 0, 0) } end
milkTp = function() TELEPORTS = TELEPORTS + 1 return true end
milkInStallNow = function() return true end
milkGateOpen = function() GATES = GATES + 1 return true end
milkNearPrompts = function() return {} end
milkLogButtons = function() end
milkActions = function() return {} end
milkFindButton = function() return nil end
milkDrops = function() return 0 end
milkCall = 0 -- the real milkCleanUp increments this on every read

-- the milk itself: the stall menu's button turns 300% into 0%
PERCENT = { [1] = 300 }
MODEL = setmetatable({ Name = "Cow1" }, { __index = function() return nil end })
milkPercentOf = function() return PERCENT[MODEL] end
local GUI = { Name = "BarnStallMenu", Enabled = true,
    GetDescendants = function() return {} end }
milkStallGui = function() return GUI end
milkStallButton = function() return { Name = "Milk" } end
invokeHandlers = function() PERCENT[MODEL] = 0 return true, "handler" end

local SPOT = {
    Name = "Spot1",
    FindFirstChild = function(_, n)
        if n == "Center" then return CENTRE end
        if n == "Gate" then return nil end
        return nil
    end,
}

pressKey = function(key)
    PRESSES = PRESSES + 1
    if key == "V" then CLEAN_STARTED = VT end
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end
local function logged(word)
    for _, l in ipairs(LOG) do if tostring(l):find(word, 1, true) then return true end end
    return false
end
local function cow()
    return { index = 1, model = MODEL, stall = SPOT, pos = Vector3.new(0, 0, 0) }
end

-- 1. the HUD is not pointing at the stall for the first two frames: the read is
--    nil, and the old code skipped the clean. Now it polls, sees Clean, and does it.
VT, PRESSES, TELEPORTS, GATES, LOG = 0, 0, 0, 0, {}
BILL.Adornee, BILL.Enabled = nil, false
SETTLE = function()
    if not CLEAN_STARTED and VT >= 0.1 then
        BILL.Adornee, BILL.Enabled = CENTRE, true -- the game caught up: it is dirty
    elseif CLEAN_STARTED and VT >= CLEAN_STARTED + 2 then
        BILL.Enabled = false -- the 2 s clean finished
    end
end
PERCENT[MODEL] = 300
local out = milkCowInStall(cow())
check("a nil first read still cleans the stall", PRESSES == 1 and logged("is dirty"),
    "presses=" .. PRESSES)
check("...and waits the game's 2 s clean", logged("cleaned in 2."), LOG[#LOG] or "")
check("...then milks and opens the gate", out == true and GATES == 1 and PERCENT[MODEL] == 0,
    string.format("returned=%s gates=%d pct=%s", tostring(out), GATES, tostring(PERCENT[MODEL])))

-- 2. the game says CLEAN from the start: no key, no waiting, straight to milk
VT, PRESSES, TELEPORTS, GATES, LOG = 0, 0, 0, 0, {}
BILL.Adornee, BILL.Enabled = CENTRE, false
SETTLE = nil
CLEAN_STARTED = nil
PERCENT[MODEL] = 300
out = milkCowInStall(cow())
check("a clean stall is not pressed again", PRESSES == 0 and out == true and GATES == 1,
    string.format("presses=%d returned=%s", PRESSES, tostring(out)))

-- 3. no Clean billboard at all (another build): the old 0.5 s poll must not
--    turn into a second clean loop or a key press
VT, PRESSES, TELEPORTS, GATES, LOG = 0, 0, 0, 0, {}
BILL.Adornee, BILL.Enabled = nil, false
PERCENT[MODEL] = 300
out = milkCowInStall(cow())
check("an unreadable Clean offer costs at most 0.5 s and no key",
    PRESSES == 0 and VT < 0.6 and out == true,
    string.format("presses=%d vt=%.2f returned=%s", PRESSES, VT, tostring(out)))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
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
    src = SRC.read_text(encoding="utf-8")
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
