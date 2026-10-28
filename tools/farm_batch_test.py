"""Run the REAL farm chooser and check the rule the user asked for.

"if the farm does not have the set amount of cows to herd at a time it goes to
the next farm".

The whole rule lives in one function (milkFarmSwitch) so it can be exercised
directly, with the farm reads stubbed, against the real milkFarmOrder /
milkFarmGoTo / milkFarmReadyCount / milkReadyToHerd / milkBatchWanted:

  * a farm short of a batch hands the next pass to the first farm that can fill
    one, in rotation order
  * a farm that can fill a batch itself never switches
  * a farm with cows PARKED in its stalls never switches (there is milk to take)
  * no farm able to fill one -> no switch, the current farm is worked as before
  * a farm that cannot be READ (streamed out) is never taken as empty
  * the walk is read-only until a farm is picked, and the store pick is reset
    only when the account really changes

    python tools/farm_batch_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

WANTED = ["milkFarmOf", "milkFarmOrder", "milkFarmReadyCount", "milkFarmGoTo",
          "milkFarmSwitch", "milkReadyToHerd", "milkBatchWanted"]

PRE = r"""
milkPicks = { "A", "B", "C" }
milkTurn = 1
milkUser = "A"
milkStorePick, milkStoreScanAt = "LH150", 5
milkStopping = function() return false end
farmTookBody = function() return false end

-- each farm A/B/C: how many cows it could herd right now, or "cannot be read"
FARMS = {}
milkPlotOf = function(who)
    local f = FARMS[who]
    if not f or f.blind then return nil end
    return { GetBoundingBox = function() return { X = 0, Y = 0, Z = 0 }, { X = 10, Y = 1, Z = 10 } end }
end
milkStalls = function() return {} end
milkCows = function(who)
    local f = FARMS[who] or {}
    local out = {}
    for i = 1, (f.ready or 0) do
        out[#out + 1] = { index = i, percent = 500, state = "Wander" }
    end
    for i = 1, (f.parked or 0) do
        out[#out + 1] = { index = 100 + i, percent = 500, state = "IdleLocked", inBarn = true }
    end
    return out
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the typed box, clamped to the 1-12 it promises
local function want(v)
    milkBatchSize = v
    return milkBatchWanted()
end
check("the box: 5 is 5", want("5") == 5, tostring(want("5")))
check("the box: 12 is 12", want("12") == 12, tostring(want("12")))
check("the box: 99 clamps to 12", want("99") == 12, tostring(want("99")))
check("the box: 0 clamps to 1", want("0") == 1, tostring(want("0")))
check("the box: junk falls back to 5", want("abc") == 5, tostring(want("abc")))
check("the box: nothing set falls back to 5", want(nil) == 5, tostring(want(nil)))

-- 2. what counts as a cow to herd
check("a ready cow in the field is a cow to herd",
    milkReadyToHerd({ percent = 500, state = "Wander" }) == true)
check("a parked cow is not", milkReadyToHerd({ percent = 500, state = "IdleLocked" }) == false)
check("a cow already in a stall is not",
    milkReadyToHerd({ percent = 500, state = "Wander", stall = true }) == false)
check("a cow the game took into the barn is not",
    milkReadyToHerd({ percent = 500, state = "Wander", inBarn = true }) == false)
check("299 is not ready", milkReadyToHerd({ percent = 299, state = "Wander" }) == false)
check("300 is ready", milkReadyToHerd({ percent = 300, state = "Wander" }) == true)
check("nothing is not a cow", milkReadyToHerd(nil) == false)

-- 3. the walk: the rotation order, without touching the rotation
milkPicks, milkTurn, milkUser = { "A", "(none)", "C" }, 1, "A"
local order = milkFarmOrder()
local seen = {}
for _, c in ipairs(order) do seen[#seen + 1] = c.who end
check("order skips the empty slot and wraps (C then A)",
    table.concat(seen, ",") == "C,A", table.concat(seen, ","))
check("the walk is read-only", milkTurn == 1 and milkUser == "A",
    tostring(milkTurn) .. " / " .. tostring(milkUser))

-- 4. counting a farm: unreadable is nil, never zero
FARMS = { A = { ready = 2 }, B = { ready = 5 }, C = { blind = true } }
check("a readable farm counts its ready cows", milkFarmReadyCount("B") == 5,
    tostring(milkFarmReadyCount("B")))
check("a farm that cannot be read counts nil", milkFarmReadyCount("C") == nil,
    tostring(milkFarmReadyCount("C")))
check("an unknown farm counts nil", milkFarmReadyCount("ZZ") == nil,
    tostring(milkFarmReadyCount("ZZ")))

-- 5. THE RULE
milkPicks, milkTurn, milkUser = { "A", "B", "C" }, 1, "A"
milkStorePick, milkStoreScanAt = "LH150", 5
local slot, who, n = milkFarmSwitch(5, "A", 2, 0)
check("short farm (2 < 5): B is picked, with its count",
    slot == 2 and who == "B" and n == 5,
    tostring(slot) .. " / " .. tostring(who) .. " / " .. tostring(n))
check("...and the walk did not move the rotation yet",
    milkTurn == 1 and milkUser == "A" and milkStorePick == "LH150",
    tostring(milkTurn) .. " / " .. tostring(milkUser) .. " / " .. tostring(milkStorePick))

-- parked cows here: stay, there is milk to take
check("a farm with parked cows is never skipped", milkFarmSwitch(5, "A", 0, 1) == nil)
-- this farm can fill a batch itself
check("a farm that can fill a batch stays", milkFarmSwitch(5, "A", 5, 0) == nil)
check("more than a batch stays too", milkFarmSwitch(5, "A", 9, 0) == nil)
-- nobody can fill one: work what there is, as before
FARMS = { A = { ready = 2 }, B = { ready = 3 }, C = { ready = 1 } }
check("no farm can fill a batch: nothing switches", milkFarmSwitch(5, "A", 2, 0) == nil)
-- an unreadable farm does not block the search
FARMS = { A = { ready = 2 }, B = { blind = true }, C = { ready = 6 } }
slot, who, n = milkFarmSwitch(5, "A", 2, 0)
check("an unreadable farm is skipped over, not taken as empty",
    slot == 3 and who == "C" and n == 6,
    tostring(slot) .. " / " .. tostring(who) .. " / " .. tostring(n))
-- the same account in two slots is never a switch to itself
milkPicks, milkTurn, milkUser = { "A", "B", "A" }, 1, "A"
FARMS = { A = { ready = 9 }, B = { ready = 1 } }
check("the working farm is never handed to itself", milkFarmSwitch(5, "A", 2, 0) == nil)
-- ...and a farm whose batch is smaller than the box is still asked when it has one
FARMS = { A = { ready = 2 }, B = { ready = 5 } }
milkPicks, milkTurn, milkUser = { "A", "B", "C" }, 1, "A"
slot, who, n = milkFarmSwitch(5, "A", 2, 0)

-- 6. the hand-over: same semantics as milkFarmNext
milkStorePick, milkStoreScanAt = "LH150", 5
milkFarmGoTo(slot, who)
check("hand over: the rotation and the working farm move",
    milkTurn == 2 and milkUser == "B", tostring(milkTurn) .. " / " .. tostring(milkUser))
check("hand over to a new account: the store pick is reset",
    milkStorePick == nil and milkStoreScanAt == nil,
    tostring(milkStorePick) .. " / " .. tostring(milkStoreScanAt))
milkTurn, milkUser = 1, "A"
milkStorePick, milkStoreScanAt = "LH150", 5
milkFarmGoTo(1, "A")
check("hand over to the SAME account: the store pick is kept",
    milkStorePick == "LH150" and milkStoreScanAt == 5,
    tostring(milkStorePick) .. " / " .. tostring(milkStoreScanAt))

-- 7. reading a real cow list: parked cows do not count as herdable
FARMS = { A = { ready = 3, parked = 4 } }
check("a farm with 3 in the field + 4 parked counts 3",
    milkFarmReadyCount("A") == 3, tostring(milkFarmReadyCount("A")))

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
