"""Equipment actions through the game's own remotes (captured 2026-10-30).

SpudRemoteProbe recorded these from the game's own client while the actions
were done by hand (spawn/store a machine, mount a tractor, hitch/unhitch a
tool, pick a crate up), all under Modules.Larry:

    FNCEnterEquipment(vehicle, seat)
    FNCAttemptHitch(tractor.Components.Hitchable, tool.Chassis.HitchableSocket)
    FNCUnhitch(tractor.Components.Hitchable)
    FNCSpawnEquipment(model) / FNCStoreEquipment(model)
    EVTRequestToCarry(draggable) / EVTRequestToDrop()

Every helper fires the call only where the game offers the action and demands
proof before trusting it:

  * enter   -> the humanoid is seated in that vehicle
  * hitch   -> the caller's tug (unchanged, in attemptHitch)
  * unhitch -> the caller's tug (unchanged, in dropImplementAtOrigin)
  * spawn   -> InStorage flips false or the model moves > 100 studs
  * store   -> InStorage flips true
  * carry   -> carrying() turns true

An ignored call counts a miss; three take that action back to keys/UI for the
session. Nothing here can skip the old path.

    python tools/equip_remote_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = [
    "spudEquipRemoteKit",
    "spudEquipRemoteMiss",
    "spudEquipRemoteCall",
    "spudEquipRemoteAct",
    "spudEnterRemote",
    "spudHitchParts",
    "spudHitchRemote",
    "spudUnhitchRemote",
    "spudCarryRemote",
    "spudDropRemote",
]

PRE = r"""
local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end }
local function v(x, y, z) return Vector3.new(x, y, z) end

local logs = {}
function log(msg) logs[#logs + 1] = tostring(msg) end
function stopping() return false end
task = task or {}
task.wait = function(_) end
function require(x) return x end

local function newInst(name, class)
    local o = { Name = name, ClassName = class, kids = {}, attrs = {} }
    function o:IsA(c) return self.ClassName == c end
    function o:FindFirstChild(n)
        for _, k in ipairs(self.kids) do
            if k.Name == n then return k end
        end
        return nil
    end
    function o:FindFirstChildOfClass(c)
        for _, k in ipairs(self.kids) do
            if k.ClassName == c then return k end
        end
        return nil
    end
    function o:IsDescendantOf(root)
        local cur = self.Parent
        while cur do
            if cur == root then return true end
            cur = cur.Parent
        end
        return false
    end
    function o:GetAttribute(k) return self.attrs[k] end
    function o:SetAttribute(k, val) self.attrs[k] = val end
    function o:GetPivot() return { Position = self.pivot or v(0, 0, 0) } end
    return o
end
local function adopt(parent, kid)
    parent.kids[#parent.kids + 1] = kid
    kid.Parent = parent
    return kid
end

spudEquipRemoteState = { kit = nil, fails = {}, off = {} }

local mode = { enter = "ok", store = "ok", spawn = "ok", carry = "ok", drop = "ok" }

local function newRemote(name, class, handler)
    local o = newInst(name, class)
    o.fireCalls, o.invokeCalls = 0, 0
    local function remember(...)
        local a = table.pack(...)
        o.lastArgs = a
    end
    function o:FireServer(...)
        self.fireCalls += 1
        remember(...)
        if handler then handler(...) end
    end
    function o:InvokeServer(...)
        self.invokeCalls += 1
        remember(...)
        if handler then return handler(...) end
        return true
    end
    return o
end

local hum = newInst("Humanoid", "Humanoid")
local char = newInst("Char", "Model")
adopt(char, hum)
LocalPlayer = { Character = char }

local function enterHandler(vehicle, seat)
    if mode.enter == "ok" then hum.SeatPart = seat end
end
local function storeHandler(model)
    if mode.store == "ok" then model:SetAttribute("InStorage", true) end
end
local function spawnHandler(model)
    if mode.spawn == "ok" then
        model:SetAttribute("InStorage", false)
    elseif mode.spawn == "move" then
        model.pivot = (model.pivot or v(0, 0, 0)) + v(500, 0, 0)
    end
end
local function carryHandler(model)
    if mode.carry == "ok" then carryingFlag = true end
end
local function dropHandler()
    if mode.drop == "ok" then carryingFlag = false end
end

local enterRemote = newRemote("FNCEnterEquipment", "RemoteFunction", enterHandler)
local hitchRemote = newRemote("FNCAttemptHitch", "RemoteFunction", nil)
local unhitchRemote = newRemote("FNCUnhitch", "RemoteFunction", nil)
local spawnRemote = newRemote("FNCSpawnEquipment", "RemoteFunction", spawnHandler)
local storeRemote = newRemote("FNCStoreEquipment", "RemoteFunction", storeHandler)
local carryRemote = newRemote("EVTRequestToCarry", "RemoteEvent", carryHandler)
local dropRemote = newRemote("EVTRequestToDrop", "RemoteEvent", dropHandler)

local larry = newInst("Larry", "Folder")
adopt(larry, enterRemote)
adopt(larry, hitchRemote)
adopt(larry, unhitchRemote)
adopt(larry, spawnRemote)
adopt(larry, storeRemote)
adopt(larry, carryRemote)
adopt(larry, dropRemote)
local modules = newInst("Modules", "Folder")
adopt(modules, larry)
local rs = newInst("ReplicatedStorage", "ReplicatedStorage")
adopt(rs, modules)
game = { GetService = function(_, name) return rs end }

-- equipment folder (equipmentFolder() is a global here; an upvalue in the real file)
local equipFolder = newInst("Equipment", "Folder")
local kadl = adopt(equipFolder, newInst("KADL", "Model"))
kadl:SetAttribute("InStorage", true)
local zm80 = adopt(equipFolder, newInst("ZM80", "Model"))
function equipmentFolder() return equipFolder end

-- tool hitch parts (captured paths)
local tcomps = adopt(zm80, newInst("Components", "Folder"))
local tractorHitch = adopt(tcomps, newInst("Hitchable", "Attachment"))
local kchassis = adopt(kadl, newInst("Chassis", "Model"))
local toolSocket = adopt(kchassis, newInst("HitchableSocket", "Attachment"))

carryingFlag = false
function carrying() return carryingFlag end

local function resetState()
    spudEquipRemoteState.kit = nil
    spudEquipRemoteState.fails = {}
    spudEquipRemoteState.off = {}
    carryingFlag = false
    hum.SeatPart = nil
    kadl:SetAttribute("InStorage", true)
    kadl.pivot = v(0, 0, 0)
    mode.enter, mode.store, mode.spawn, mode.carry, mode.drop = "ok", "ok", "ok", "ok", "ok"
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

resetState()

-- 1. the kit resolves the captured names on the captured path
local kit = spudEquipRemoteKit()
check("all seven equipment remotes resolve",
    kit and kit.enter and kit.hitch and kit.unhitch and kit.spawn
        and kit.store and kit.carry and kit.drop)
check("the field and equipment kits are independent",
    kit.enter.remote == enterRemote and kit.carry.remote == carryRemote)

-- 2. store: the call itself is FNCStoreEquipment(model)
kadl:SetAttribute("InStorage", false)
local s0 = storeRemote.invokeCalls
local done = spudEquipRemoteAct("KADL", "Store")
check("store fires FNCStoreEquipment with the model",
    storeRemote.invokeCalls - s0 == 1
        and storeRemote.lastArgs[1] == kadl)
check("store is confirmed by InStorage turning true", done == true
    and kadl:GetAttribute("InStorage") == true)

-- 3. spawn: InStorage flips false
resetState()
local p0 = spawnRemote.invokeCalls
done = spudEquipRemoteAct("KADL", "Spawn")
check("spawn fires FNCSpawnEquipment with the model",
    spawnRemote.invokeCalls - p0 == 1
        and spawnRemote.lastArgs[1] == kadl)
check("spawn is confirmed by InStorage turning false", done == true
    and kadl:GetAttribute("InStorage") == false)

-- 4. a spawn that rebuilds the model is confirmed by the move
resetState()
kadl:SetAttribute("InStorage", true)
mode.spawn = "move"
done = spudEquipRemoteAct("KADL", "Spawn")
check("a >100-stud move confirms a rebuilt spawn", done == true,
    string.format("done=%s stored=%s x=%s fails=%s", tostring(done),
        tostring(kadl:GetAttribute("InStorage")),
        tostring(kadl.pivot and kadl.pivot.X), tostring(spudEquipRemoteState.fails.spawn)))

-- 5. an ignored store falls back (false) and counts a miss
resetState()
kadl:SetAttribute("InStorage", false)
mode.store = "none"
done = spudEquipRemoteAct("KADL", "Store")
check("an ignored store returns false (the UI runs)",
    done == false and spudEquipRemoteState.fails.store == 1)

-- 6. three misses switch that action off for the session
resetState()
spudEquipRemoteMiss("hitch")
spudEquipRemoteMiss("hitch")
spudEquipRemoteMiss("hitch")
check("three misses switch the action off", spudEquipRemoteState.off.hitch == true)
local h0 = hitchRemote.invokeCalls
check("a switched-off action fires nothing",
    spudEquipRemoteCall("hitch", tractorHitch, toolSocket) == false
        and hitchRemote.invokeCalls == h0)

-- 7. enter: proven by the seat
resetState()
local seat = adopt(zm80, newInst("DriveSeat", "VehicleSeat"))
local e0 = enterRemote.invokeCalls
check("enter fires FNCEnterEquipment(vehicle, seat) and proves the seat",
    spudEnterRemote(zm80, seat) == true
        and enterRemote.invokeCalls - e0 == 1
        and enterRemote.lastArgs[1] == zm80
        and enterRemote.lastArgs[2] == seat)

-- 8. a refused enter reports false and counts a miss
resetState()
mode.enter = "none"
check("a refused enter returns false and counts a miss",
    spudEnterRemote(zm80, seat) == false
        and spudEquipRemoteState.fails.enter == 1)

-- 9. hitch parts: the captured pair, or nil
resetState()
local th, is = spudHitchParts(zm80, kadl)
check("hitch parts are Components.Hitchable + Chassis.HitchableSocket",
    th == tractorHitch and is == toolSocket)

local noParts = newInst("Trailer", "Model")
check("a tool without the captured parts returns nil",
    spudHitchParts(zm80, noParts) == nil)

local hi0 = hitchRemote.invokeCalls
check("hitch fires FNCAttemptHitch(hitchable, socket)",
    spudHitchRemote(zm80, kadl) == true
        and hitchRemote.invokeCalls - hi0 == 1
        and hitchRemote.lastArgs[1] == tractorHitch
        and hitchRemote.lastArgs[2] == toolSocket)

-- 10. unhitch: FNCUnhitch(hitchable)
local u0 = unhitchRemote.invokeCalls
check("unhitch fires FNCUnhitch(hitchable)",
    spudUnhitchRemote(zm80) == true
        and unhitchRemote.invokeCalls - u0 == 1
        and unhitchRemote.lastArgs[1] == tractorHitch)
check("a vehicle without a hitchable reports false",
    spudUnhitchRemote(noParts) == false)

-- 11. carry: EVTRequestToCarry(draggable), proven by carrying()
resetState()
local c0 = carryRemote.fireCalls
check("carry fires EVTRequestToCarry(crate) and proves the hands",
    spudCarryRemote(kadl) == true
        and carryRemote.fireCalls - c0 == 1
        and carryRemote.lastArgs[1] == kadl)

resetState()
mode.carry = "none"
check("a refused carry returns false and counts a miss",
    spudCarryRemote(kadl) == false
        and spudEquipRemoteState.fails.carry == 1)

-- 12. drop: EVTRequestToDrop() with no arguments, proven by empty hands
resetState()
carryingFlag = true
local d0 = dropRemote.fireCalls
check("drop fires EVTRequestToDrop() with no arguments",
    spudDropRemote() == true and dropRemote.fireCalls - d0 == 1
        and dropRemote.lastArgs.n == 0)

resetState()
carryingFlag = true
mode.drop = "none"
check("a refused drop returns false and counts a miss",
    spudDropRemote() == false and spudEquipRemoteState.fails.drop == 1)

-- 13. the kit goes away with the module folder
resetState()
larry.Name = "LarryX"
check("no Modules.Larry -> no equipment kit", spudEquipRemoteKit() == nil)
larry.Name = "Larry"

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
