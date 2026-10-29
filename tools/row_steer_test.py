"""Row steering decision for the field driver (spudRowSteer / spudRowNeedsAlign).

The game auto-steers a tractor on its field. Driving the row on real W and
nudging A/D every tick to hug the line made the tractor swing side to side:
the nudge and the game's own steering fought each other.

The rule now (user: "make it force the alignement then jus tgo straight and
let the game do the ajustments"):

  * ONE snap at the start of a leg - `spudRowNeedsAlign(angDeg, cross, tol)`
    is true only for a BIG error: heading past `spudRowAng` (15 degrees) or a
    lateral offset past `tol` (`spudRowTol`, 6 studs). The band is wide on
    purpose (user: "widen the steering range it takes ... still going side to
    side") so the game steers the small stuff instead of the script fighting
    it.
  * After the snap no A/D is pressed; W holds and the game steers. A/D is
    still used while swinging onto a row (a real heading error), where
    `spudRowSteer(angDeg, crossY)` answers left/right - and answers "no key"
    whenever the heading is fine, whatever the offset.

    python tools/row_steer_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["spudRowSteer", "spudRowNeedsAlign"]


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function keys(a, cy)
    local l, r = spudRowSteer(a, cy)
    return (l and "L" or "") .. (r and "R" or "")
end

-- 1. only a BIG heading error steers, and it steers toward the aim
check("30deg, aim left  -> left", keys(30, 1) == "L", keys(30, 1))
check("30deg, aim right -> right", keys(30, -1) == "R", keys(30, -1))
check("30deg, aim dead ahead -> no key", keys(30, 0) == "", keys(30, 0))

-- 2. the wide band: small errors get NO key at all - the game steers them
check("straight, aim left -> no key", keys(2, 1) == "", keys(2, 1))
check("straight, aim right -> no key", keys(2, -1) == "", keys(2, -1))
check("10deg inside the band -> no key", keys(10, 1) == "", keys(10, 1))
check("exactly the band edge -> no key", keys(15, 1) == "", keys(15, 1))
check("16deg -> steers", keys(16, 1) == "L", keys(16, 1))

-- 3. the one-shot alignment decision, with the same wide band
check("aligned: nothing to do", spudRowNeedsAlign(0, 0) == false)
check("small offset inside the band", spudRowNeedsAlign(2, 5) == false)
check("5.5 studs beside -> still no snap", spudRowNeedsAlign(2, 5.5) == false)
check("beside the row -> snap", spudRowNeedsAlign(2, 6.5) == true)
check("10deg is inside the band", spudRowNeedsAlign(10, 0) == false)
check("heading error -> snap", spudRowNeedsAlign(16, 0) == true)
check("15deg is the edge, not an error", spudRowNeedsAlign(15, 2.0) == false)
check("custom tol: 5 inside 6", spudRowNeedsAlign(0, 5, 6) == false)
check("custom tol: 7 outside 6", spudRowNeedsAlign(0, 7, 6) == true)
check("nil-safe: no readings -> no snap", spudRowNeedsAlign(nil, nil) == false)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


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
        fh.write("\n\n".join(parts) + "\n" + POST)
        path = fh.name
    try:
        out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8",
                             errors="replace")
        print(out.stdout.strip())
        if out.returncode != 0:
            print(out.stderr.strip()[-1500:])
        return out.returncode
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
