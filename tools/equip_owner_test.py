"""Whose tractor/tool does a farming pass use? (equipOwnerRank)

The sweep found the NEAREST machine in Objects.Equipment, whoever owned it.
Working another account's field therefore grabbed that account's tractor only
by luck - a nearer stranger's ZM80 won. The probe proved every machine carries
Configurations.Owner (ZM80/SRC6 = oksimba_1, LH150/MTS/UH = Miou2251), so the
pick is now the selected farm owner's machine first, an unowned/unreadable
machine second, and another account's machine never.

    python tools/equip_owner_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
START = "-- >>> SPUD FARM MODULE"
END = "-- <<< SPUD FARM MODULE"

WANTED = [
    "milkStoreOwnerOf",
    "equipTypeOf",
    "equipInStorage",
    "equipOwnerRank",
    "findTractor",
    "findImplement",
]

PRE = r"""
local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end

function typeof(v)
    if type(v) == "table" and getmetatable(v) == V then return "Vector3" end
    return type(v)
end

local NODE = {}
NODE.__index = NODE
function NODE:FindFirstChild(name)
    return self.kids[name]
end
function NODE:GetChildren()
    return self.list
end
function NODE:GetDescendants()
    local out = {}
    local function walk(n)
        for _, k in ipairs(n.list) do out[#out + 1] = k walk(k) end
    end
    walk(self)
    return out
end
function NODE:FindFirstChildWhichIsA(cls, recursive)
    for _, k in ipairs(self.list) do
        if k._cls == cls then return k end
        if recursive then
            local hit = k:FindFirstChildWhichIsA(cls, true)
            if hit then return hit end
        end
    end
    return nil
end
function NODE:IsA(cls)
    return cls == self._cls
end
function NODE:GetAttribute(n)
    return (self._attrs or {})[n]
end
function NODE:GetPivot()
    return { Position = self._pos or vec(0, 0, 0) }
end

local ROOTNODE
TYPE_MODEL = { Cultivator = "KQF3000", Planter = "KADL" }
local function node(name, parent, cls)
    local n = setmetatable({ Name = name, _name = name, _cls = cls or "Folder",
        kids = {}, list = {} }, NODE)
    if parent then
        n.Parent = parent
        parent.kids[name] = n
        parent.list[#parent.list + 1] = n
    else
        ROOTNODE = n
    end
    return n
end

-- a machine the way the live build exposes it: EquipmentType/InStorage
-- attributes, a Configurations.Owner tag, a painted name and one seat
local function machine(name, etype, x, owner, stored)
    local m = node(name, nil, "Model")
    m._attrs = { EquipmentType = etype, InStorage = stored == true }
    m._pos = vec(x, 0, 0)
    local seat = node("DriveSeat", m, "VehicleSeat")
    seat.Position = vec(x, 0, 0)
    local conf = node("Configurations", m)
    if owner then
        local o = node("Owner", conf, "ObjectValue")
        o.Value = { Name = owner }
    end
    return m
end

-- fresh world: the machines are the only children of Objects.Equipment
local WORKSPACE
local function world(machines)
    local ws = node("Workspace", nil, "Workspace")
    local objects = node("Objects", ws)
    local eq = node("Equipment", objects)
    for _, m in ipairs(machines) do
        m.Parent = eq
        eq.kids[m.Name] = m
        eq.list[#eq.list + 1] = m
    end
    WORKSPACE = ws
    workspace = ws
    local char = node("Character", nil, "Model")
    local hrp = node("HumanoidRootPart", char, "Part")
    hrp.Position = vec(0, 0, 0)
    LocalPlayer = { Name = "simba", Character = char }
    farmOwnerPick = nil
end

function equipmentFolder()
    local objects = WORKSPACE:FindFirstChild("Objects")
    return objects and objects:FindFirstChild("Equipment")
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-60s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function equipNames(machines)
    local out = {}
    for _, m in ipairs(machines) do out[#out + 1] = m.Name .. "@" .. (m._pos.X) end
    return table.concat(out, ", ")
end

-- ── 1. the rank itself ─────────────────────────────────────────────────────
world({})
local mine = machine("ZM80", "Tractor", 10, "simba")
local bob = machine("ZM80", "Tractor", 20, "bob")
local loose = machine("ZM80", "Tractor", 30, nil)
check("rank: my machine is rank 0", equipOwnerRank(mine) == 0, tostring(equipOwnerRank(mine)))
check("rank: another account is refused", equipOwnerRank(bob) == nil, tostring(equipOwnerRank(bob)))
check("rank: no owner tag is rank 1 (usable)", equipOwnerRank(loose) == 1, tostring(equipOwnerRank(loose)))
farmOwnerPick = "bob"
check("rank: the picked farm's machine is rank 0", equipOwnerRank(bob) == 0)
check("rank: mine ranks below the pick but stays usable", equipOwnerRank(mine) == 1,
    tostring(equipOwnerRank(mine)))
local alice = machine("ZM80", "Tractor", 40, "alice")
check("rank: a third account is refused under a pick", equipOwnerRank(alice) == nil)
check("rank: an untagged machine ranks below mine under a pick", equipOwnerRank(loose) == 2,
    tostring(equipOwnerRank(loose)))

-- ── 2. tractors: the nearest is no longer enough ───────────────────────────
world({ machine("ZM80", "Tractor", 1, "bob"), machine("ZM80", "Tractor", 100, "simba") })
local tr = findTractor()
check("tractor: mine wins even when a stranger's is nearer",
    tr and tr.Name == "ZM80" and tr._pos.X == 100,
    tr and ("x=" .. tr._pos.X) or "none")

world({ machine("ZM80", "Tractor", 1, "bob") })
tr = findTractor()
check("tractor: a stranger's spawn is never borrowed", tr == nil,
    tr and tr._pos and ("x=" .. tr._pos.X) or "none")

world({ machine("ZM80", "Tractor", 10, nil), machine("ZM80", "Tractor", 100, "simba") })
tr = findTractor()
check("tractor: owner beats an unreadable owner",
    tr and tr._pos.X == 100, tr and ("x=" .. tr._pos.X) or "none")

world({ machine("ZM80", "Tractor", 10, nil) })
tr = findTractor()
check("tractor: an unreadable owner is still usable", tr and tr._pos.X == 10,
    tr and ("x=" .. tr._pos.X) or "none")

world({ machine("ZM80", "Tractor", 1, "bob"), machine("ZM80", "Tractor", 100, "simba") })
farmOwnerPick = "bob"
tr = findTractor()
check("tractor: the picked farm gets its own machine",
    tr and tr._pos.X == 1, tr and ("x=" .. tr._pos.X) or "none")

-- the owner's machine is in storage and a stranger's is out: spawn OURS
world({ machine("ZM80", "Tractor", 1, "bob"), machine("ZM80", "Tractor", 100, "simba", true) })
tr = findTractor()
check("tractor: our stored one is reported for spawning, not the other's",
    tr == nil, tr and ("x=" .. tr._pos.X) or "none")
-- findTractor returns stashedModel in slot 4
local stored = (findTractor())
stored = select(4, findTractor())
check("tractor: the stored model handed back is ours",
    stored ~= nil and stored._pos.X == 100,
    stored and ("x=" .. stored._pos.X) or "none")

-- ── 3. implements ──────────────────────────────────────────────────────────
world({ machine("KQF3000", "Cultivator", 1, "bob"), machine("KQF3000", "Cultivator", 100, "simba") })
local impl, dist, basis = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: mine wins over a nearer stranger's",
    impl and impl._pos.X == 100, impl and ("x=" .. impl._pos.X .. " via " .. tostring(basis)) or "none")
check("implement: the distance returned is the real one", math.abs((dist or -1) - 100) < 0.01,
    tostring(dist))
check("implement: the basis still names the model", basis == "model name KQF3000", tostring(basis))

world({ machine("KQF3000", "Cultivator", 1, "bob") })
impl = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: a stranger's tool is never hooked", impl == nil,
    impl and ("x=" .. impl._pos.X) or "none")

world({ machine("KQF3000", "Cultivator", 1, "bob"), machine("KQF3000", "Cultivator", 100, "simba") })
farmOwnerPick = "bob"
impl = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: the picked farm gets its own tool", impl and impl._pos.X == 1,
    impl and ("x=" .. impl._pos.X) or "none")

world({ machine("GENERIC", "Cultivator", 50, "simba") })
impl, dist, basis = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: EquipmentType fallback still works", impl ~= nil and basis == "EquipmentType",
    tostring(basis))

world({ machine("KQF3000", "Cultivator", 5, "simba", true) })
impl = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: a stored tool is skipped for hitching", impl == nil)
impl = findImplement("Cultivator", vec(0, 0, 0), nil, true)
check("implement: the respawn check can still see it", impl ~= nil and impl._pos.X == 5)

world({ machine("KQF3000", "Cultivator", 5, nil) })
impl = findImplement("Cultivator", vec(0, 0, 0), nil)
check("implement: an unreadable owner is still usable", impl ~= nil and impl._pos.X == 5)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def dedent(block: str) -> str:
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return dedent(block)


def module(text: str) -> str:
    a, b = text.find(START), text.find(END)
    if a < 0 or b <= a:
        return ""
    return text[a:b].strip() + "\n"


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    parts = []
    mod = module(src)
    if not mod:
        print("missing SPUD FARM MODULE markers in SpudFarm_Full.lua")
        return 2
    for name in WANTED:
        code = extract(src, name)
        if not code:
            print("missing " + name)
            return 2
        parts.append(code)
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(mod + "\n" + PRE + "\n" + "\n\n".join(parts) + "\n" + POST)
        path = fh.name
    try:
        out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8",
                             errors="replace")
        print(out.stdout.strip())
        if out.returncode != 0:
            print(out.stderr.strip()[-2000:])
        return out.returncode
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
