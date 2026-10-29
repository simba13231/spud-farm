"""May the run touch the Equipment Manager on someone else's farm?

Spawn/respawn means driving the game's Equipment Manager: it is the owner's
call whether a machine comes out. On another player's plot the run must not
do that at all (user: "when it's on someone elses plot make it not try to
respawn things bro") - it names the machine that is missing / stored / far
away and skips, instead of spawning a stranger's equipment.

spudMayRespawn() is the single policy: false while a Farm owner is picked.
ensureToolNearby() must consult it BEFORE it calls respawnTool().

    python tools/foreign_respawn_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["spudMayRespawn", "ensureToolNearby"]

PRE = r"""
local V = {}
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end }

local RESPAWN_RANGE = 1000
local logged = {}
function log(s) logged[#logged + 1] = tostring(s) end
function loggedText() return table.concat(logged, "\n") end
function setStage(_) end
function stopping() return false end

-- the world stub: one implement at a time, and a respawn counter
SCEN = { impl = nil, after = nil }
RESPAWNS = 0
function respawnTool(name, getPos, attempts)
    RESPAWNS = RESPAWNS + 1
    SCEN.impl = SCEN.after or SCEN.impl
    return true
end
function findImplement(typeName, pos, tr, strict)
    return SCEN.impl, SCEN.dist, SCEN.basis
end
local function impl(name, dist, stored)
    SCEN.impl, SCEN.dist, SCEN.basis = {
        Name = name,
        stored = stored and true or false,
        GetAttribute = function(self, k)
            if k == "InStorage" then return self.stored end
            return nil
        end,
        GetPivot = function(self) return { Position = Vector3.new(0, 0, 0) } end,
    }, dist, "model"
    return SCEN.impl
end
local TR = {
    Name = "ZM80",
    GetPivot = function(self) return { Position = Vector3.new(0, 0, 0) } end,
}
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the policy itself
farmOwnerPick = nil
check("policy: my own farm may respawn", spudMayRespawn() == true)
farmOwnerPick = "Miou2251"
check("policy: a picked farm may not", spudMayRespawn() == false)
farmOwnerPick = ""
check("policy: an empty pick is my own farm", spudMayRespawn() == true)

-- 2. a stored tool on someone else's plot: name it, do not spawn it
farmOwnerPick = "Miou2251"
RESPAWNS = 0
logged = {}
impl("KQF3000", 0, true)
local got = ensureToolNearby(TR, "Cultivator", "cultivator")
check("foreign + stored: respawn is not called", RESPAWNS == 0, "calls=" .. RESPAWNS)
check("foreign + stored: the pass is skipped", got == nil)
check("foreign + stored: the log says why", loggedText():lower():find("not respawning") ~= nil,
    loggedText())

-- 3. a far tool on someone else's plot: same
RESPAWNS = 0
logged = {}
impl("KQF3000", 5000, false)
local got2 = ensureToolNearby(TR, "Cultivator", "cultivator")
check("foreign + far: respawn is not called", RESPAWNS == 0, "calls=" .. RESPAWNS)
check("foreign + far: the pass is skipped", got2 == nil)
check("foreign + far: the log names the distance", loggedText():find("5000") ~= nil, loggedText())

-- 4. a near tool on someone else's plot is used as-is
RESPAWNS = 0
logged = {}
impl("KQF3000", 20, false)
local got3 = ensureToolNearby(TR, "Cultivator", "cultivator")
check("foreign + near: the tool is returned", got3 ~= nil and got3.Name == "KQF3000")
check("foreign + near: respawn is not called", RESPAWNS == 0, "calls=" .. RESPAWNS)

-- 5. my own farm keeps the old behaviour (stored and far both respawn)
farmOwnerPick = nil
RESPAWNS = 0
logged = {}
impl("KQF3000", 0, true)
SCEN.after = {
    Name = "KQF3000", stored = false,
    GetAttribute = function(self, k) if k == "InStorage" then return false end end,
    GetPivot = function(self) return { Position = Vector3.new(0, 0, 0) } end,
}
local got4 = ensureToolNearby(TR, "Cultivator", "cultivator")
check("mine + stored: respawn IS called", RESPAWNS == 1, "calls=" .. RESPAWNS)
check("mine + stored: the fresh tool is returned", got4 ~= nil, nil)

RESPAWNS = 0
logged = {}
impl("KQF3000", 5000, false)
local got5 = ensureToolNearby(TR, "Cultivator", "cultivator")
check("mine + far: respawn IS called", RESPAWNS == 1, "calls=" .. RESPAWNS)
check("mine + far: the fresh tool is returned", got5 ~= nil, nil)

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
