"""Run the REAL milkHerdArm on a virtual clock and check the rewrite.

The old version spent a blind 0.6 s after the teleport, then polled the menu in
0.25 s steps, then slept a flat 1.0 s after the Herd press, then polled
membership in 0.5 s steps. This asserts the frame/50 ms version keeps every
outcome (armed, refused, no menu) and removes the dead time.
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
local FRAME = 1 / 60
local VT = 0
os = { clock = function() return VT end }
task = { wait = function(t)
    VT = math.ceil((VT + math.max(t or 0, FRAME)) / FRAME - 1e-9) * FRAME
end }
game = { GetService = function() return {} end }
Enum = { KeyCode = setmetatable({}, { __index = function(_, k) return k end }) }
workspace = { FindFirstChild = function() return nil end }

milkStopping = function() return false end
farmTookBody = function() return false end
log = function(s) LOG[#LOG + 1] = s end
LOG = {}
milkTp = function() return true end
milkLogButtons = function() end
invokeHandlers = function() return true, "connection:Fire" end
pressKey = function() end

Sc = { menuAfter = 0, herdOnAfter = 0, herdOnValue = true, memberAfter = nil, calls = 0, menuCalls = 0 }
milkHerdOn = function()
    Sc.calls = Sc.calls + 1
    if not Sc.herdOnValue then return false end
    return Sc.calls > Sc.herdOnAfter
end
local memberCalls = 0
milkInHerd = function()
    if Sc.memberAfter == nil then return nil end
    memberCalls = memberCalls + 1
    return memberCalls > Sc.memberAfter
end

local V3 = {}
function V3.__add(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V3) end
function V3.__sub(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V3) end
Vector3 = { new = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end }
local btn = { Name = "Herd" }
local list = { FindFirstChild = function(_, n) return n == "Herd" and btn or nil end }
local inter = { FindFirstChild = function(_, n) return n == "InteractionsList" and list or nil end }
local menu = { FindFirstChild = function(_, n) return n == "Interactions" and inter or nil end }
milkMenuFor = function()
    Sc.menuCalls = Sc.menuCalls + 1
    if Sc.menuCalls > Sc.menuAfter then return menu, 1, 1 end
    return nil, 0, 0
end
"""

POST = r"""
local cow = { model = { Name = "Cow", GetPivot = function() return { Position = Vector3.new(0, 0, 0) } end }, index = 1 }

local function run(name, setup, want)
    Sc.menuAfter = setup.menuAfter or 1e9
    Sc.herdOnAfter = setup.herdOnAfter or 0
    Sc.herdOnValue = setup.herdOnValue ~= false
    Sc.memberAfter = setup.memberAfter
    Sc.calls, Sc.menuCalls = 0, 0
    memberCalls = 0
    LOG = {}
    VT = 0
    local got
    for i = 1, 1 do got = milkHerdArm(cow, i == 1) end
    local verdict = (got == want) and "PASS" or "FAIL"
    print(string.format("%-22s %s  %5.2fs  returned %s", name, verdict, VT, tostring(got)))
    if got ~= want then
        for _, l in ipairs(LOG) do print("    " .. l) end
    end
end

run("menu on frame 1", { menuAfter = 0, herdOnAfter = 0, herdOnValue = true, memberAfter = 1 }, true)
run("menu after 0.5 s", { menuAfter = 10, herdOnAfter = 0, herdOnValue = true, memberAfter = 2 }, true)
run("herd refused", { menuAfter = 0, herdOnAfter = 0, herdOnValue = false, memberAfter = 1 }, false)
run("no menu at all", { menuAfter = 1e9, herdOnAfter = 0, herdOnValue = true, memberAfter = 1 }, false)
run("membership unreadable", { menuAfter = 0, herdOnAfter = 0, herdOnValue = true, memberAfter = nil }, true)
"""


def extract(text: str) -> str:
    m1 = re.search(r"^    function milkHerdArm\(", text, re.M)
    m2 = re.search(r"^    function milkHerdSend\(", text, re.M)
    if not m1 or not m2:
        raise SystemExit("milkHerdArm not found")
    block = text[m1.start():m2.start()]
    return "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    versions = [("before " + ref, subprocess.run(
        ["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT, capture_output=True,
        encoding="utf-8", errors="replace").stdout),
        ("now", SRC.read_text(encoding="utf-8"))]
    for name, src in versions:
        if not src:
            print(name + ": no source")
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
            fh.write(PRE + extract(src) + POST)
            path = fh.name
        out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
        print("=== " + name + " ===")
        print(out.stdout.strip())
        if out.returncode != 0:
            print(out.stderr.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
