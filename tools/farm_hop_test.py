"""Where the farming pass hops to when a specific farm is picked (spudFarmHop).

A distant plot is streamed out, so `findMyFields` / `findTractor` see nothing and
the run says "no fields / tractor not found". The user wants the pass to
teleport to the picked farm, find that farm's tools, then run.

`spudFarmHop(here, plotPos)` returns the target and the distance, or nil + why:
  * no plot position -> "no plot" (the plot model is not streamed)
  * already within 60 studs -> "close" (never hop for nothing)
  * otherwise the plot centre, 5 studs up (so the character lands on it).

    python tools/farm_hop_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["spudFarmHop"]

PRE = r"""
local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end }
local function v(x, y, z) return Vector3.new(x, y, z) end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local here = v(0, 100, 0)

-- 1. nothing to hop to
local t, why = spudFarmHop(here, nil)
check("no plot position -> no hop", t == nil and why == "no plot", tostring(why))
t, why = spudFarmHop(nil, v(500, 100, 0))
check("no player position -> no hop", t == nil and why == "no position", tostring(why))

-- 2. already there
t, why = spudFarmHop(here, v(30, 100, 0))
check("within 60 studs -> no hop", t == nil and why == "close", tostring(why))

-- 3. far: hop to the plot centre, 5 studs up
t, why = spudFarmHop(here, v(500, 100, -200))
check("far plot -> a hop target", t ~= nil)
check("hop lands on the plot centre", t and t.X == 500 and t.Z == -200,
    t and string.format("%.0f,%.0f,%.0f", t.X, t.Y, t.Z))
check("hop is 5 studs above the plot", t and t.Y == 105, t and tostring(t.Y))
check("the distance is the real one", math.abs((why or 0) - math.sqrt(500 * 500 + 200 * 200)) < 0.01,
    tostring(why))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


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
