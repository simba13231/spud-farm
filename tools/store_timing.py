"""Measure the milk store pass on a virtual clock.

Extracts the REAL functions out of SpudFarm_Full.lua (milkFrame, milkPollFor,
milkStoreAmount, milkStoreDeposit) and runs them against a fake world whose
server answers arrive after a fixed latency, while task.wait() is modelled the
way Roblox behaves: it sleeps at least the requested time and then resumes on
the next frame boundary.

Usage:  python tools/store_timing.py [path-to-luau.exe] [git-ref]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

REGIONS = [
    (r"^    function milkFrame\(\)", r"^    function milkRemotes\("),
    (r"^    function milkStoreAmount\(m\)", r"^    function milkStoreActs\("),
    (r"^    function milkStoreDeposit\(", r"^    local function milkCycle\("),
]

PRE = r"""
-- ── fake world ────────────────────────────────────────────────────────────
local FRAME = 1 / 60
RT = 0.12
local VT = 0.0
os = { clock = function() return VT end }

local V3 = {}
function V3.__sub(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V3) end
function V3.__add(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V3) end
V3.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z) end
    if k == "Position" then return t end
    return nil
end
local Vector3 = { new = function(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3)
end }

local world = { jugs = {}, holding = nil, tank = 0, cap = 180, carryAt = nil, fillAt = nil }

local label = { Name = "MilkTypeLabel", Text = "Milk 0/180", Parent = true }
function label:IsA(c) return c == "TextLabel" end

local dest = { Name = "LH150", Parent = true }
function dest:GetDescendants() return { label } end
function dest:FindFirstChild() return nil end
function dest:GetAttribute() return nil end
function dest:GetFullName() return "Workspace.Objects.Equipment.LH150" end

local function syncLabel() label.Text = string.format("Milk %d/%d", world.tank, world.cap) end

local function addJugs(n)
    world.jugs = {}
    for i = 1, n do
        world.jugs[i] = { model = { Name = "MilkContainer" }, part = { Position = Vector3.new(i, 0, 0) } }
    end
    world.tank, world.holding, world.carryAt, world.fillAt = 0, nil, nil, nil
    syncLabel()
end

local function deliver()
    if world.carryAt and VT >= world.carryAt then
        world.carryAt = nil
        if #world.jugs > 0 then
            table.remove(world.jugs, 1)
            world.holding = "MilkContainer"
        end
    end
    if world.fillAt and VT >= world.fillAt then
        world.fillAt = nil
        if world.holding then
            world.tank = math.min(world.cap, world.tank + 5)
            world.holding = nil
            syncLabel()
        end
    end
end

game = { GetService = function(_, _) return { Heartbeat = { Wait = function() VT = VT + FRAME deliver() end } } end }
workspace = { FindFirstChild = function() return nil end }
Enum = { KeyCode = setmetatable({}, { __index = function(_, k) return k end }) }
task = {
    wait = function(t)
        local target = math.ceil((VT + math.max(t or 0, FRAME)) / FRAME - 1e-9) * FRAME
        VT = target
        deliver()
    end,
    spawn = function(f) f() end,
    delay = function(_, f) f() end,
}

milkFast = { remoteOff = false, jugTypes = setmetatable({}, { __mode = "k" }),
             amounts = setmetatable({}, { __mode = "k" }) }
log = function(s) LOG[#LOG + 1] = s end
pressKey = function(k)
    KEYS[#KEYS + 1] = k
    if k == "E" then world.carryAt = VT + RT elseif k == "X" then world.holding = nil end
end
milkFeedButton = function() return false end
LOG, KEYS, REMOTES = {}, {}, {}
MISSES = 0

milkStopping = function() return false end
farmTookBody = function() return false end
milkStorePick, milkStoreTarget = "LH150", dest
milkStoreCandidate = function() return true end
milkStoreRefresh = function() end
milkStandUp = function() return true end
milkStoreStand = function() return Vector3.new(0, 0, 0) end
milkStoreAdornee = function() return nil end
milkStoreCarryUp = function() return false end
milkStoreFillAction = function() return nil end
milkStorePress = function() world.fillAt = VT + RT return "key V" end
milkStoreActs = function() return "" end
milkTp = function() return true end
milkStoreHolding = function() return world.holding end
milkStoreHeldCount = function() return world.holding and 1 or 0 end
milkStoreJugs = function() return world.jugs end

milkRemoteFire = function(kind, _)
    REMOTES[#REMOTES + 1] = kind
    if NOREMOTE then
        REMOTES[#REMOTES] = nil
        return false
    end
    if kind == "carry" then world.carryAt = VT + RT else world.fillAt = VT + RT end
    return true
end
NOREMOTE = false
milkRemoteMiss = function() MISSES = MISSES + 1 end
"""

POST = r"""
local function run(name, jugs, cap, rtt, noRemote)
    LOG, KEYS, REMOTES, MISSES = {}, {}, {}, 0
    NOREMOTE = noRemote or false
    RT = rtt or 0.12
    world.cap = cap or 180
    addJugs(jugs)
    VT = 0
    local ok, res, full = pcall(milkStoreDeposit,
        { Position = Vector3.new(0, 0, 0), Size = Vector3.new(10, 10, 10) },
        Vector3.new(10, 10, 10))
    print(string.format("%-26s %s %6.2fs  %2d in tank  %2d left  %2d remotes  %2d keys  full=%s",
        name, ok and "ok  " or "FAIL", VT, jugs - #world.jugs, #world.jugs,
        #REMOTES, #KEYS, tostring(full == true)))
    if not ok then print("   error: " .. tostring(res)) end
    return VT
end

local a = run("10 jugs, 120 ms server", 10, 180)
run("10 jugs, 40 ms server", 10, 180, 0.04)
run("6 jugs, tiny tank (25)", 6, 25)
run("10 jugs, no remotes", 10, 180, 0.12, true)
print(string.format("PER JUG: %.2fs", a / 10))
"""


def extract(text: str) -> str:
    chunks = []
    for start, stop in REGIONS:
        m1 = re.search(start, text, re.M)
        m2 = re.search(stop, text, re.M)
        if not m1 or not m2:
            continue  # the older revision may not have every helper yet
        block = text[m1.start():m2.start()]
        chunks.append("\n".join(line[4:] if line.startswith("    ") else line
                                for line in block.splitlines()))
    if not any("milkStoreDeposit" in c for c in chunks):
        raise SystemExit("milkStoreDeposit not found")
    return "\n\n".join(chunks)


def source_at(ref: str) -> str:
    proc = subprocess.run(["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT,
                          capture_output=True, encoding="utf-8", errors="replace")
    return proc.stdout if proc.returncode == 0 else ""


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    versions = [("before " + ref, source_at(ref)), ("now", SRC.read_text(encoding="utf-8"))]
    for name, src in versions:
        if not src:
            print(name + ": no source found")
            continue
        program = PRE + extract(src) + POST
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
            fh.write(program)
            path = fh.name
        out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
        print("=== " + name + " ===")
        print(out.stdout.strip())
        if out.returncode != 0:
            print(out.stderr.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
