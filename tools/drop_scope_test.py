"""Run the REAL milkDrops on a fake world and check what it counts.

DraggableObjects is world-wide, so on a public server another player's milk
jug appearing during the 10 s milk wait used to read as "this cow gave milk"
and the gate opened on an unmilked cow. With a position only drops near the
stall may count; without one the old world-wide count is kept.

    python tools/drop_scope_test.py [path-to-luau.exe]
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
local V = {}
V.__sub = function(a, b)
    return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V)
end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
Vector3 = { new = vec }

JUGS = {}
local function part(name, x)
    return { Name = name, Position = vec(x, 0, 0),
        IsA = function(_, c) return c == "BasePart" end }
end
local function model(name, x)
    return { Name = name, IsA = function(_, c) return c == "Model" end,
        GetPivot = function() return { Position = vec(x, 0, 0) } end }
end
local BOX = { GetChildren = function() return JUGS end }
local OBJECTS = { FindFirstChild = function(_, k)
    if k == "DraggableObjects" then return BOX end
    return nil
end }
workspace = { FindFirstChild = function(_, n)
    if n == "Objects" then return OBJECTS end
    return nil
end }
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. no position: the old world-wide count (every milk-ish object, any plot)
JUGS = { part("MilkJug", 0), part("MilkJug", 40), part("MilkJug", 900), part("HayBale", 5) }
check("no position: every milk jug in the world counts", milkDrops() == 3,
    "counted " .. tostring(milkDrops()))
check("no position: non-milk objects never count", milkDrops() == 3,
    "counted " .. tostring(milkDrops()))

-- 2. with the stall's position: only this plot's jugs count
check("with a position: the far plot's jug is ignored", milkDrops(vec(0, 0, 0), 250) == 2,
    "counted " .. tostring(milkDrops(vec(0, 0, 0), 250)))
JUGS = { part("MilkJug", 0), part("MilkJug", 400), part("MilkJug", 20) }
check("models and parts are both read", milkDrops(vec(0, 0, 0), 100) == 2,
    "counted " .. tostring(milkDrops(vec(0, 0, 0), 100)))
check("the radius is honoured", milkDrops(vec(0, 0, 0), 10) == 1,
    "counted " .. tostring(milkDrops(vec(0, 0, 0), 10)))

-- 3. a jug whose position cannot be read is not guessed into the count
JUGS = { { Name = "MilkJug", IsA = function() return true end,
    GetPivot = function() error("streamed out") end } }
check("an unreadable drop is not counted", milkDrops(vec(0, 0, 0), 100) == 0,
    "counted " .. tostring(milkDrops(vec(0, 0, 0), 100)))

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
    code = extract(src, "milkDrops")
    if not code:
        print("missing milkDrops")
        return 2
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + "\n" + code + "\n" + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1200:])
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
