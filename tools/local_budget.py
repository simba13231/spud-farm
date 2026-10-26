#!/usr/bin/env python3
"""
Local-variable budget check for SpudFarm_Full.lua (advisory).

Roblox's Luau compiler allows 200 locals per function. The whole farm script
lives inside one big `pcall(function() ... end)`, so every `local` declared at
4-space indentation in that body competes for the same 200. Going over it is a
COMPILE error, which looks exactly like the script not loading at all:

    compile error: ...:8897: Out of local registers when trying to allocate
    milkCycle: exceeded limit 200

The local luau-compile binary does NOT enforce this limit, so counting is the
only local defence. The count below is an upper bound: it also includes locals
inside `do` blocks that have already closed and freed their registers, which is
why the real live count at the milkCycle line was ~10 higher than the number
printed here when this failed for real.

So: treat 184 as the practical ceiling for the count printed at the
`milkCycle` checkpoint. New state belongs on a global table (see milkFast),
not in another local.

    python tools/local_budget.py
"""

import pathlib
import re
import sys

SAFE = 185     # the count that compiled fine
DANGER = 195   # anything above this is one small edit away from the 200 wall

path = pathlib.Path(__file__).resolve().parent.parent / "SpudFarm_Full.lua"
lines = path.read_text(encoding="utf-8").splitlines()

start = None
for i, line in enumerate(lines):
    if line.startswith("local okBuild"):
        start = i
        break
if start is None:
    print("could not find the `local okBuild, errBuild = pcall(function()` opener")
    sys.exit(2)

checkpoint = None
for i, line in enumerate(lines):
    if "local function milkCycle" in line or line.strip().startswith("function milkCycle"):
        checkpoint = i
        break


def count4(upto):
    return sum(1 for ln in lines[start:upto] if re.match(r"^    local\s", ln))


at_cycle = count4(checkpoint if checkpoint else len(lines))
whole = count4(len(lines))

print(f"4-space locals before milkCycle : {at_cycle}  (practical ceiling {SAFE})")
print(f"4-space locals in the whole body: {whole}  (hard limit 200 for the pcall)")

worst = max(at_cycle, whole - 12)  # later locals free registers as blocks close
if at_cycle > DANGER or whole > 205:
    print("DANGER: park new state on the global milkFast-style table, not in locals")
    sys.exit(1)
if at_cycle > SAFE:
    print("WARNING: over the count that last compiled — check before pushing")
else:
    print(f"headroom: {SAFE - at_cycle}")
