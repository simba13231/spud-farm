"""Run the REAL milkFarmSwitch / milkFarmReadyCount and check the hand-over rule.

The user's rule: "if the farm does not have the set amount of cows to herd at a
time it goes to the next farm" - and the report that came back was "it does not
switch the plot/players field when it get under the heard amount". The first
version only handed over to a farm that could fill the WHOLE batch, which a real
pair of alts almost never reaches, so it never moved. This asserts the rule that
replaced it:

  * a farm with cows PARKED is never skipped (there is milk to take)
  * a farm that can fill the batch is never skipped
  * under the batch size, the farm with MORE ready cows takes the next pass -
    even when that is still under the batch size
  * a farm that cannot be read (nil) never wins a hand-over
  * the farm being worked is never its own target
  * after a hand-over the old farm cannot take the pass straight back

Usage:  python tools/farm_switch_test.py [path-to-luau.exe]
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
-- who is configured in the three farm slots, and which one is being worked
milkPicks, milkTurn, milkUser = {}, 1, "A"
milkFarmOf = function(slot) local v = milkPicks[slot]
    if v == nil or v == "(none)" then return nil end
    return v end
milkStopping = function() return false end
farmTookBody = function() return false end

-- what each account's farm would report. false = the farm cannot be read here
READY = {}
local seenWho = {}
milkPlotOf = function(who)
    if not seenWho[who] then return nil end
    return { Name = "Plot", GetBoundingBox = function() return { Position = 0 }, { X = 1 } end }
end
milkStalls = function() return { {} } end
milkCows = function(who)
    local n = READY[who]
    if n == nil then return {} end
    seenWho[who] = true
    local out = {}
    for i = 1, n do out[i] = { index = i, percent = 300 } end
    return out
end
milkReadyToHerd = function(c) return c ~= nil and (c.percent or 0) >= 300 end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end
local function setup(ready, picks, turn)
    READY = ready
    seenWho = {}
    for k in pairs(ready) do seenWho[k] = true end
    milkPicks = picks
    milkTurn = turn or 1
    milkUser = nil
    for slot = 1, 3 do
        local w = milkPicks[slot]
        if w and w ~= "(none)" then milkUser = w break end
    end
end
local function desc(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    return table.concat(t, " / ")
end

-- the rule no longer demands a FULL batch: 9 beats 6 and takes the pass
setup({ A = 6, B = 9 }, { "A", "B", "(none)" })
local slot, who, n, why = milkFarmSwitch(12, "A", 6, 0)
check("6 here vs 9 there: hand over to the fuller farm", slot == 2 and who == "B" and n == 9,
    desc(slot, who, n, why))

-- and it is still only a hand-over when this farm really is short
-- (a pass that does NOT move returns the reason as its 2nd value)
setup({ A = 12, B = 12 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 12, 0)
check("a full batch here is never skipped", slot == nil and why == "full", desc(slot, why))

-- parked cows are milk to take, whatever the field looks like
setup({ A = 2, B = 11 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 2, 3)
check("parked cows keep the pass here", slot == nil and why == "parked", desc(slot, why))

-- fewer ready cows over there: no teleport for nothing
setup({ A = 6, B = 3 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 6, 0)
check("a barer farm does not steal the pass", slot == nil and why == "nothing-better",
    desc(slot, why))

-- an equal farm does not either (>= would ping-pong two equal alts)
setup({ A = 6, B = 6 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 6, 0)
check("an equal farm does not steal the pass", slot == nil, desc(slot, why))

-- unreadable is never empty and never a target
setup({ A = 6 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 6, 0)
check("an unreadable farm is not a target", slot == nil, desc(slot, why))

-- the farm being worked is never its own target, even if it looks fuller
setup({ A = 6 }, { "A", "(none)", "(none)" })
slot, why = milkFarmSwitch(12, "A", 6, 0)
check("with one farm set there is nothing to switch to",
    slot == nil and why == "alone", desc(slot, why))

-- three slots: the FULLEST of them wins, not merely the next one in the rotation
setup({ A = 4, B = 7, C = 10 }, { "A", "B", "C" }, 1)
slot, who, n = milkFarmSwitch(12, "A", 4, 0)
check("the fullest of three farms wins", slot == 3 and who == "C" and n == 10,
    desc(slot, who, n))

-- after the hand-over the old farm cannot take it straight back
setup({ A = 6, B = 9 }, { "A", "B", "(none)" }, 2)
slot, why = milkFarmSwitch(12, "B", 9, 0)
check("no ping-pong: the emptier farm stays put", slot == nil, desc(slot, why))

-- an empty farm leaves as soon as anywhere has a cow
setup({ A = 0, B = 1 }, { "A", "B", "(none)" })
slot, who, n = milkFarmSwitch(12, "A", 0, 0)
check("an empty farm hands over to one ready cow", slot == 2 and who == "B",
    desc(slot, who, n))

-- and two empty farms do not chase each other
setup({ A = 0, B = 0 }, { "A", "B", "(none)" })
slot, why = milkFarmSwitch(12, "A", 0, 0)
check("two empty farms do not chase each other", slot == nil, desc(slot, why))

-- the real reader behind it: count cows, never invent them
setup({ A = 3 }, { "A", "(none)", "(none)" })
check("milkFarmReadyCount reads a real count", milkFarmReadyCount("A") == 3,
    tostring(milkFarmReadyCount("A")))
check("milkFarmReadyCount: an unreadable plot is nil, not 0",
    milkFarmReadyCount("B") == nil, tostring(milkFarmReadyCount("B")))
check("milkFarmReadyCount: no account is nil", milkFarmReadyCount(nil) == nil,
    tostring(milkFarmReadyCount(nil)))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def dedent_block(block: str) -> str:
    return "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())


def extract(text: str) -> str:
    """The REAL order / count / switch, not a copy of them."""
    m1 = re.search(r"^    function milkFarmOrder\(", text, re.M)
    m2 = re.search(r"^    -- a slot changed by hand", text, re.M)
    if not m1 or not m2 or m2.start() < m1.start():
        raise SystemExit("milkFarmOrder not found in SpudFarm_Full.lua")
    order = dedent_block(text[m1.start():m2.start()])

    m3 = re.search(r"^    function milkFarmReadyCount\(", text, re.M)
    m4 = re.search(r"^    -- hand the rotation to a farm the chooser picked", text, re.M)
    if not m3 or not m4 or m4.start() < m3.start():
        raise SystemExit("milkFarmReadyCount / milkFarmSwitch not found in SpudFarm_Full.lua")
    return order + "\n" + dedent_block(text[m3.start():m4.start()])


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
