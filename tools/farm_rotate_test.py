"""Run the REAL farm-rotation helpers and check the rules the user asked for.

"2 more drop downs like the first one ... farm1>farm2>farm3 if no farm2 but
there is a farm3 do farm3 but if there is no farm3 make it go to 1".

This asserts, against the real milkFarmOf / milkFarmOptions / milkFarmNext /
milkFarmChanged:
  * an empty slot ("(none)") is skipped, not worked
  * farm 3 wraps back to farm 1
  * a slot set by hand while nothing is picked adopts that farm
  * emptying the farm being worked hands over to the next one
  * the store pick is reset ONLY when the working account really changes
  * "(nobody else is here)" is never mistaken for a player

Usage:  python tools/farm_rotate_test.py [path-to-luau.exe]
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
PLAYERS = { "Simba", "Bob" }
milkUserChoices = function()
    if #PLAYERS == 0 then return { "(nobody else is here)" } end
    local out = {}
    for i, n in ipairs(PLAYERS) do out[i] = n end
    return out
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-52s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the options list: "(none)" first, placeholders dropped
local opts = milkFarmOptions()
check('options are "(none)" + players', table.concat(opts, ",") == "(none),Simba,Bob",
    table.concat(opts, ","))
PLAYERS = {}
opts = milkFarmOptions()
check("placeholders are not offered as farms", table.concat(opts, ",") == "(none)",
    table.concat(opts, ","))
PLAYERS = { "Simba", "Bob" }

-- 2. skip the empty middle slot, then wrap 3 -> 1
milkPicks, milkTurn, milkUser = { "A", "(none)", "C" }, 0, nil
local a = milkFarmNext()
local b = milkFarmNext()
local c = milkFarmNext()
check("farm 1 first, empty farm 2 skipped", a == "A" and b == "C",
    tostring(a) .. " then " .. tostring(b))
check("farm 3 wraps back to farm 1", c == "A" and milkTurn == 1,
    tostring(c) .. " (turn " .. tostring(milkTurn) .. ")")

-- 3. nothing set anywhere
milkPicks, milkTurn, milkUser = { "(none)", "(none)", "(none)" }, 0, nil
local none = milkFarmNext()
check("no farm set: nothing is worked", none == nil and milkUser == nil,
    tostring(none))

-- 4. only farm 3 set: it is the one that runs
milkPicks, milkTurn, milkUser = { "(none)", "(none)", "C" }, 0, nil
check("only farm 3 set: it runs", milkFarmNext() == "C", "turn " .. tostring(milkTurn))

-- 5. a slot set by hand while nothing is picked adopts it
milkPicks, milkTurn, milkUser = { "(none)", "B", "(none)" }, 0, nil
milkFarmChanged(2)
check("first pick becomes the working farm", milkUser == "B" and milkTurn == 2,
    tostring(milkUser) .. " (turn " .. tostring(milkTurn) .. ")")

-- 6. emptying the farm being worked hands over to the next one
--    (the dropdown callback stores the new value first, then tells the
--    rotation - so the slot really is "(none)" by the time it runs)
milkPicks, milkTurn, milkUser = { "A", "B", "(none)" }, 1, "A"
milkPicks[1] = "(none)"
milkFarmChanged(1)
check("emptying the working farm moves on", milkUser == "B" and milkTurn == 2,
    tostring(milkUser) .. " (turn " .. tostring(milkTurn) .. ")")

-- 7. the store pick survives a lap that lands on the SAME farm...
milkPicks, milkTurn, milkUser = { "A", "(none)", "(none)" }, 1, "A"
milkStorePick, milkStoreScanAt = "LH150", 5
milkFarmNext()
check("same farm: the carrier pick is kept",
    milkStorePick == "LH150" and milkStoreScanAt == 5,
    tostring(milkStorePick) .. " / " .. tostring(milkStoreScanAt))

-- 8. ...and is reset when the account really changes
milkPicks, milkTurn, milkUser = { "A", "(none)", "C" }, 1, "A"
milkStorePick, milkStoreScanAt = "LH150", 5
milkFarmNext()
check("new farm: the carrier pick is reset",
    milkStorePick == nil and milkStoreScanAt == nil and milkUser == "C",
    tostring(milkUser))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str) -> str:
    m1 = re.search(r"^    function milkFarmOf\(", text, re.M)
    m2 = re.search(r"^    milkDrops\[1\] = Tabs\.Milk:CreateDropdown\(", text, re.M)
    if not m1 or not m2 or m2.start() < m1.start():
        raise SystemExit("the farm-rotation helpers were not found in SpudFarm_Full.lua")
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
