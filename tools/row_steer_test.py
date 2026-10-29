"""Row steering decision for the field driver (spudRowSteer).

The game auto-steers a tractor on its field, so the row should be driven on
real W and only corrected when it is actually off course. Two failures came
from the old steering:

  * heading error > 8 degrees -> steer toward the aim (unchanged);
  * heading fine but the tractor sits 2.5+ studs BESIDE the row -> it never
    re-centers, because zero heading error pressed no key at all.

`spudRowSteer(angDeg, crossY, cross, tol)` returns (left, right):
  - a real heading error wins: crossY > 0 means the aim is to our left;
  - otherwise a cross-track offset past `tol` steers back onto the row
    (cross > 0 = we are left of the line, so steer right).

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
WANTED = ["spudRowSteer"]


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

local function keys(a, cy, c, tol)
    local l, r = spudRowSteer(a, cy, c, tol)
    return (l and "L" or "") .. (r and "R" or "")
end

-- 1. a real heading error steers toward the aim
check("20deg, aim left  -> left", keys(20, 1, 0) == "L", keys(20, 1, 0))
check("20deg, aim right -> right", keys(20, -1, 0) == "R", keys(20, -1, 0))
check("20deg, aim dead ahead -> no key", keys(20, 0, 0) == "", keys(20, 0, 0))

-- 2. heading fine: cross-track re-centers
check("straight, 5 studs left of row -> right", keys(2, 0, 5) == "R", keys(2, 0, 5))
check("straight, 5 studs right of row -> left", keys(2, 0, -5) == "L", keys(2, 0, -5))
check("straight, 1 stud left -> deadband, no key", keys(2, 0, 1) == "", keys(2, 0, 1))
check("straight, exactly at tol -> no key", keys(2, 0, 2.5) == "", keys(2, 0, 2.5))
check("custom tol: 3 studs inside a 4-stud tol -> no key", keys(2, 0, 3, 4) == "", keys(2, 0, 3, 4))

-- 3. the heading correction is not overridden by a cross offset
check("15deg left aim with a right offset still steers left", keys(15, 1, -8) == "L",
    keys(15, 1, -8))

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
