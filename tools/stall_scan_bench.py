"""Measure the stall scan: whole-map walk vs the narrowed walk.

The milk pass has to find the stalls of one barn. It used to be
workspace:GetDescendants() plus a name compare per instance - and the run-3
dump counted 112,531 instances in this game (game_dump3.txt), so every pass
built that whole table to find a dozen parts.

This builds the same map shape at that size (8 plots, Objects.Buildings with a
barn per plot, 12 stalls in the target barn, the rest filler) and runs the REAL
milkStalls / milkBarnStalls / milkBarnKeep out of SpudFarm_Full.lua, counting:

  calls - instance method calls, with GetDescendants/GetChildren charged one
          per instance they return (their cost is proportional to the map)
  names - every `.Name` read, i.e. the name compare per instance

Usage:  python tools/stall_scan_bench.py [path-to-luau.exe] [git-ref]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

# emitted in this order: each is a local, so a callee has to exist before the
# function that calls it is defined
WANTED = ["milkInBox", "milkTrigger", "milkBarnKey", "milkBarnStalls", "milkBarnKeep", "milkStalls"]
OPTIONAL = {"milkBarnStalls"}

PRE = r"""
CALLS, NAMES, INSTANCES = 0, 0, 0
local function call() CALLS = CALLS + 1 end

local NODE = {}
function NODE:FindFirstChild(name, recursive)
    call()
    local c = self.kids[name]
    if c then c.Parent = self return c end
    if recursive then
        for _, k in ipairs(self.list) do
            call()
            if k._name == name then return k end
            local hit = k:FindFirstChild(name, true)
            if hit then return hit end
        end
    end
    return nil
end
function NODE:GetChildren()
    CALLS = CALLS + #self.list
    return self.list
end
function NODE:GetDescendants()
    local out = {}
    local function walk(n)
        for _, k in ipairs(n.list) do
            out[#out + 1] = k
            walk(k)
        end
    end
    walk(self)
    CALLS = CALLS + #out
    return out
end
function NODE:IsA(cls) call() return cls == rawget(self, "_cls") end
function NODE:GetPivot() call() return { Position = rawget(self, "Position") or vec(0, 0, 0) } end
function NODE:GetBoundingBox() call() return self, { X = 400, Y = 100, Z = 400 } end

local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    if k == "Position" then return t end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end

local function node(name, parent, cls)
    local o = setmetatable({
        _name = name, _cls = cls or "Model", kids = {}, list = {}, Parent = parent,
    }, {
        __index = function(t, k)
            if k == "Name" then NAMES = NAMES + 1 return rawget(t, "_name") end
            return NODE[k]
        end,
    })
    if parent then
        parent.list[#parent.list + 1] = o
        if not parent.kids[name] then parent.kids[name] = o end
    end
    INSTANCES = INSTANCES + 1
    return o
end

workspace = node("Workspace", nil, "DataModel")
local plots = node("Plots", workspace)
local objects = node("Objects", workspace)
local bld = node("Buildings", objects)

-- one barn with `stalls` stalls inside it, exactly the dumped shape:
-- <barn>.Spots.<n>.Adornee_BarnStallMenu (+ the ProximityPart the clean step
-- needs), standing `x` studs from the plot centre
local function barn(name, x, stalls, target)
    local b = node(name, bld)
    b.Position = vec(x, 0, 0)
    local spots = node("Spots", b)
    for i = 1, stalls do
        local num = node("Spot" .. i, spots)
        local part = node("Adornee_BarnStallMenu", num, "BasePart")
        part.Position = vec(x + i, 0, 0)
        part._ownerTag = target and "Simba" or "Other"
        local prox = node("ProximityPart", num, "BasePart")
        prox.Position = part.Position
        node("Occupant", num, "ObjectValue")
        node("Filth", num, "NumberValue")
        node("Hay", num, "NumberValue")
    end
    return b
end

-- the map: 8 plots, a barn per plot, and ~112k filler instances like run 3
for i = 1, 8 do
    local p = node("Plot" .. i, plots)
    local fol = node("Foliage", p)
    for _ = 1, 600 do node("Tree", fol) end
end
barn("AutoWoodenBarn", 3000, 12, true)   -- another plot's barn, far away
for i = 2, 8 do barn("AutoWoodenBarn", i * 3000, 10, false) end
for i = 1, 90000 do node("Part", plots) end

milkUser = "Simba"
milkBarns = {}
log = function() end
milkBarnPicked = function()
    local rec = milkBarns["simba"]
    if rec and rec.inst and rec.inst.Parent then return rec.inst end
    return nil
end
milkOwnerOf = function(inst)
    call()
    return rawget(inst, "_ownerTag")
end
milkInBox = function(pos, cf, size, pad) local x = pos.X or 0 return x >= 0 end
local CF = { Position = vec(3000, 0, 0),
    PointToObjectSpace = function(_, p) return p end }
SIZE = { X = 400, Y = 100, Z = 400 }
milkUser = "Simba"
"""

POST = r"""
local function scan(label, cf)
    CALLS, NAMES = 0, 0
    local stalls = milkStalls("Simba", cf, cf and SIZE or nil)
    print(string.format("%-26s %6d call(s), %6d name read(s) -> %d stall(s) kept",
        label, CALLS, NAMES, #stalls))
end

print(string.format("map: %d instances, 8 barn buildings, 12 stalls in the target one", INSTANCES))
milkBarns = {}
scan("1st pass (no lock)", CF)
scan("2nd pass (barn locked)", CF)
milkBarns = {}
scan("no distance prune (worst)", nil)
"""


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


def run(exe, label, src, tmpdir):
    parts = []
    for name in WANTED:
        code = extract(src, name)
        if not code:
            if name in OPTIONAL:
                continue
            print(label + ": missing " + name)
            return
        parts.append(code)
    body = "\n\n".join(parts)
    if "milkBarnStalls" not in body and WANTED[2] in body:
        pass
    path = tmpdir / (re.sub(r"\W+", "_", label) + ".lua")
    path.write_text(PRE + "\n" + body + "\n" + POST, encoding="utf-8")
    out = subprocess.run([str(exe), str(path)], capture_output=True,
                         encoding="utf-8", errors="replace")
    print("=== " + label + " ===")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1200:])


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    before = subprocess.run(["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT,
                            capture_output=True, encoding="utf-8", errors="replace").stdout
    with tempfile.TemporaryDirectory() as td:
        tmpdir = pathlib.Path(td)
        run(exe, "before " + ref, before, tmpdir)
        run(exe, "now (narrow scan)", SRC.read_text(encoding="utf-8"), tmpdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
