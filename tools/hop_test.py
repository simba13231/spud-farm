"""Where does an arc hop land? (hopTo)

User: "when the harvester is coming back from somewhere it should drop from
higher, because right now it is coming from under."

The hop used to keep the TAKEOFF height at both ends, so a return leg from the
lower Fulfillment pad (top ~140) to the field (~172) flew the whole way under
the field and only surfaced on the last frame. The rule now:

  * the landing height is max(takeoff, target) — a trip up lands ON the higher
    target, a trip down still lands at the takeoff height (unchanged);
  * the arc always clears the landing height by ~12 studs, so the ride comes
    DOWN onto it instead of arriving flat or from below;
  * the log names both heights, so a live pass can be checked.

    python tools/hop_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["hopTo"]

PRE = r"""
local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__mul(a, b)
    if type(a) == "number" then return setmetatable({ X = b.X * a, Y = b.Y * a, Z = b.Z * a }, V) end
    return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V)
end
function V.__div(a, b) return setmetatable({ X = a.X / b, Y = a.Y / b, Z = a.Z / b }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end }

local PIVOT = {}
PIVOT.__index = PIVOT
function PIVOT.__sub(a, b) return { rot = true } end

local CF = {}
CF.__index = CF
function CF.__mul(a, b) return a end

CFrame = { new = function(p) return setmetatable({ p = p }, CF) end }

local logged = {}
function log(s) logged[#logged + 1] = tostring(s) end
function loggedText() return table.concat(logged, "\n") end

task = { wait = function() end }
local stopped = false
function stopping() return stopped end
SELL_HOP_SPEED = 140

-- a ride whose pivot is the only thing the hop reads or writes
local moves = {}
local pos = Vector3.new(0, 0, 0)
local ride = {}
function ride:GetPivot() return setmetatable({ Position = pos }, PIVOT) end
function ride:PivotTo(cf)
    pos = cf.p
    moves[#moves + 1] = { X = pos.X, Y = pos.Y, Z = pos.Z }
end
local function place(x, y, z) pos = Vector3.new(x, y, z) moves = {} stopped = false end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end
local function peak()
    local hi = -1e9
    for _, m in ipairs(moves) do if m.Y > hi then hi = m.Y end end
    return hi
end

-- 1. the reported bug: the return leg from the lower pad lands ON the field
place(0, 140, 0)
check("return: the hop completes", hopTo(ride, Vector3.new(100, 172, 0), 140) == true)
check("return: it lands on the field height", moves[#moves].Y == 172,
    tostring(moves[#moves].Y))
check("return: it climbs above the field first", peak() >= 184,
    string.format("peak %.1f", peak()))
-- the loop's last frame and the closing PivotTo both sit on the target, so the
-- frame before those is the last one still in the air
check("return: it arrives from ABOVE", moves[#moves - 2].Y > moves[#moves].Y,
    string.format("%.1f -> %.1f", moves[#moves - 2].Y, moves[#moves].Y))
check("return: x/z reach the target", moves[#moves].X == 100 and moves[#moves].Z == 0)
check("return: the log names both heights", loggedText():find("Y 140 → 172") ~= nil,
    loggedText())

-- 2. a trip down keeps the old behaviour: the takeoff height is the landing
place(0, 172, 0)
hopTo(ride, Vector3.new(100, 140, 0), 140)
check("outbound: a lower target still lands at the takeoff height",
    moves[#moves].Y == 172, tostring(moves[#moves].Y))
check("outbound: the arc still clears the field", peak() >= 184,
    string.format("peak %.1f", peak()))

-- 3. level ground stays level, and the arc still jumps
place(0, 160, 0)
hopTo(ride, Vector3.new(200, 160, 0), 140)
check("level: it lands level", moves[#moves].Y == 160)
check("level: it still jumps", peak() > 180, string.format("peak %.1f", peak()))

-- 4. no height on the target keeps the takeoff height
place(0, 150, 0)
hopTo(ride, Vector3.new(50, nil, 0), 140)
check("nil target Y: the takeoff height is kept", moves[#moves].Y == 150)

-- 5. a zero-length hop is one move, no arc
place(10, 200, 10)
hopTo(ride, Vector3.new(10, 260, 10), 140)
check("zero length: one move, no flight", #moves == 1, #moves .. " move(s)")
check("zero length: it still takes the higher height", moves[1].Y == 260)

-- 6. stopping aborts the hop and never lands it
place(0, 140, 0)
stopped = true
local aborted = hopTo(ride, Vector3.new(100, 172, 0), 140)
check("stopping: the hop aborts", aborted == nil)
check("stopping: the ride is not landed on the target", #moves == 0)

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
