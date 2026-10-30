"""Field work through the game's own remotes (captured 2026-10-30).

SpudRemoteProbe caught the game firing, while cultivating by hand:

    EVTCultivateFieldCell:FireServer(field, {cellId}, {raycastAttachment})
    FNCFillSeeder:InvokeServer(seeder)

`cellId` is the FieldHelper.GetCells key (x*128+y), and the attachment is the
hitched tool's own RaycastPart attachment. The plow/seed/harvest calls are the
sibling remotes on the same path, so `spudFieldRemotePass` fires one call per
remaining cell id, re-reads the stages, and reports what the server took:

  * every cell took the call  -> true, 0   (the sweep is not driven)
  * some took it              -> true, n   (drive the rest)
  * none took it / unreadable -> false, n  (drive; the job's fast path is off)

Nothing is trusted: the stage re-read is the proof, and the drive-over sweep
stays the fallback. `spudFillSeederRemote` is only counted as a fill once the
seeder's own seed count rises (checked by the caller, which keeps V).

    python tools/field_remote_test.py [path-to-luau.exe]
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
    "cellsAtStage",
    "spudSweepCells",
    "spudHopCells",
    "spudFieldRemoteKit",
    "spudFieldCellIds",
    "spudToolAttachment",
    "spudFieldRemoteCall",
    "spudFieldRemoteCallMany",
    "spudFieldRemotePass",
    "spudFillSeederRemote",
]

PRE = r"""
-- ▸ fake instancing: only what the helpers touch (Name/Parent/IsA/kids)
local function newInst(name, class)
    local o = { Name = name, ClassName = class, kids = {} }
    function o:IsA(c) return self.ClassName == c end
    function o:FindFirstChild(n)
        for _, k in ipairs(self.kids) do
            if k.Name == n then return k end
        end
        return nil
    end
    function o:GetDescendants()
        local out = {}
        local function walk(node)
            for _, k in ipairs(node.kids) do
                out[#out + 1] = k
                walk(k)
            end
        end
        walk(self)
        return out
    end
    return o
end
local function adopt(parent, kid)
    parent.kids[#parent.kids + 1] = kid
    kid.Parent = parent
    return kid
end

local logs = {}
function log(msg) logs[#logs + 1] = tostring(msg) end
function loggedText() return table.concat(logs, "|") end
function stopping() return false end
task = task or {}
task.wait = function(_) end
function require(x) return x end

grownStage = function(s) return s == "Grown" end
spudFieldRemoteState = { kit = nil, off = {} }

-- ▸ vectors/CFrames for the hop fixtures (cellsAtStage + spudHopCells)
local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
function V.__mul(a, b)
    if type(a) == "number" then return setmetatable({ X = b.X * a, Y = b.Y * a, Z = b.Z * a }, V) end
    return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V)
end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end }
local CF = {}
CF.__index = CF
CF.__mul = function(a, b)
    if a.base then return { Position = a.Position + (b.pos or b.Position) } end
    return a
end
CF.__sub = function(a, b) return { rot = true } end
CFrame = { new = function(x, y, z)
    if type(x) == "table" then return setmetatable({ pos = x }, CF) end
    return setmetatable({ pos = Vector3.new(x or 0, y or 0, z or 0) }, CF)
end }
function cellPosOf(id)
    local x, y = math.floor(id / 128), id % 128
    return Vector3.new((x - 3) * 10, 0, (y - 2) * 10) -- the fixture's rows = 3 (643 is Seeded)
end
ATTPARENT = nil
RIDE_POS = Vector3.new(0, 0, 0)

local fieldState = {}
local fieldHelper = newInst("FieldHelper", "ModuleScript")
function fieldHelper.GetCells(field) return fieldState[field] or {} end

local function newRemote(name, class, handler)
    local o = newInst(name, class)
    o.fireCalls, o.invokeCalls = 0, 0
    local function remember(...)
        local a = table.pack(...)
        o.lastArg, o.lastField = a[1], a[1]
        o.lastAtt = type(a[3]) == "table" and a[3][1] or a[3]
        if type(a[2]) == "table" then o.lastId = a[2][#a[2]] end
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

local mode = { seed = "all", fill = "ok" }
local acceptR = 2 -- how close the blade must be for the server to take a cell
local tries = {}
spudBatchRemotes = false

local function seedHandler(field, ids)
    if mode.seed == "none" then return end
    -- a server that validates ONE id per call ignores a longer list
    if mode.seed == "oneOnly" and #ids ~= 1 then return end
    local cells = fieldState[field]
    for _, id in ipairs(ids) do
        local cell = cells and cells[id]
        if cell and cell.Stage == "Cultivated" then
            local take
            if mode.seed == "retryOnce" then
                tries[id] = (tries[id] or 0) + 1
                take = tries[id] >= 2
            elseif mode.seed == "all" or mode.seed == "oneOnly" then
                take = true
            elseif mode.seed == "first" then
                take = (id == 641)
            elseif mode.seed == "firstBatch" then
                -- takes the first id of a list, but any single-id call
                take = (id == 641) or (#ids == 1)
            end
            if take and mode.atCell then
                -- the live rule: only a cell the blade is over is accepted
                local p = ATTPARENT and ATTPARENT.Position
                if not (p and (p - cellPosOf(id)).Magnitude <= acceptR) then take = false end
            end
            if take then cell.Stage = "Seeded" end
        end
    end
end
local function harvestHandler(field, ids)
    local cells = fieldState[field]
    for _, id in ipairs(ids) do
        local cell = cells and cells[id]
        if cell and cell.Stage == "Grown" then cell.Stage = "Empty" end
    end
end
local function fillHandler()
    if mode.fill == "no" then return false end
    return true
end

local function cultHandler(field, ids)
    local cells = fieldState[field]
    for _, id in ipairs(ids) do
        local cell = cells and cells[id]
        if cell and cell.Stage == "Cultivated" then
            local p = ATTPARENT and ATTPARENT.Position
            if not mode.atCell or (p and (p - cellPosOf(id)).Magnitude <= acceptR) then
                cell.Stage = "Seeded"
            end
        end
    end
end

local seedRemote = newRemote("FNCSeedFieldCell", "RemoteFunction", seedHandler)
local cultRemote = newRemote("EVTCultivateFieldCell", "RemoteEvent", cultHandler)
local plowRemote = newRemote("EVTPlowFieldCell", "RemoteEvent", nil)
local harvestRemote = newRemote("FNCHarvestFieldCell", "RemoteFunction", harvestHandler)
local fillRemote = newRemote("FNCFillSeeder", "RemoteFunction", fillHandler)

local larry = newInst("Larry", "Folder")
adopt(larry, seedRemote)
adopt(larry, cultRemote)
adopt(larry, plowRemote)
adopt(larry, harvestRemote)
adopt(larry, fillRemote)
local modules = newInst("Modules", "Folder")
adopt(modules, larry)
adopt(modules, fieldHelper)
local rs = newInst("ReplicatedStorage", "ReplicatedStorage")
adopt(rs, modules)
game = { GetService = function(_, name) return rs end }

local field = newInst("Field", "Model")
local function resetCells()
    tries = {}
    fieldState[field] = {
        [641] = { Stage = "Cultivated" },
        [642] = { Stage = "Cultivated" },
        [643] = { Stage = "Seeded" },
        ["odd"] = { Stage = "Cultivated" },
    }
end
resetCells()

local tool = newInst("KADL", "Model")
local comps = adopt(tool, newInst("Components", "Folder"))
local impl = adopt(comps, newInst("Seeder", "Model"))
local att = adopt(adopt(impl, newInst("RaycastPart", "Part")), newInst("Attachment", "Attachment"))

local decoyTool = newInst("S4204", "Model")
adopt(adopt(decoyTool, newInst("Misc", "Part")), newInst("Attachment", "Attachment"))

local noAttTool = newInst("Empty", "Model")

local function resetState()
    spudFieldRemoteState.kit = nil
    spudFieldRemoteState.off = {}
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. cell ids come from the game's own dict, keyed x*128+y
local ids = spudFieldCellIds(field, "Cultivated")
check("ids for a stage are sorted and numeric-only",
    ids and #ids == 2 and ids[1] == 641 and ids[2] == 642,
    ids and table.concat(ids, ",") or "nil")
check("a stage with no cells returns an empty list",
    spudFieldCellIds(field, "Plowed") and #spudFieldCellIds(field, "Plowed") == 0)
check("a stage predicate is accepted",
    spudFieldCellIds(field, function(s) return s == "Seeded" end)[1] == 643)

local realGet = fieldHelper.GetCells
fieldHelper.GetCells = function() return nil end
check("a failed cell read stays unknown (nil), not empty",
    spudFieldCellIds(field, "Cultivated") == nil)
fieldHelper.GetCells = realGet

-- 2. the attachment the game sends is the tool's raycast one
check("the RaycastPart attachment is chosen", spudToolAttachment(tool) == att)
check("a tool with no raycast/seed attachment returns nil",
    spudToolAttachment(noAttTool) == nil)
check("nil tool -> nil", spudToolAttachment(nil) == nil)

local seedJob = { verb = "seed", stage = "Cultivated",
    remote = "FNCSeedFieldCell", prog = "seeding" }

-- 3. a full batch: one call per id with (field, {id}, {attachment})
resetCells()
resetState()
local before = seedRemote.invokeCalls
local done, left = spudFieldRemotePass(seedJob, field, tool)
check("full batch is reported done", done == true and left == 0,
    tostring(done) .. "," .. tostring(left))
check("one call per addressable cell", seedRemote.invokeCalls - before == 2,
    tostring(seedRemote.invokeCalls - before))
check("the call carries the field, the id list and the attachment",
    seedRemote.lastField == field and seedRemote.lastId == 642
        and seedRemote.lastAtt == att,
    string.format("field=%s id=%s att=%s",
        tostring(seedRemote.lastField == field), tostring(seedRemote.lastId),
        tostring(seedRemote.lastAtt == att)))

-- 4. a partial batch keeps the fast path on and hands back the remainder
resetCells()
resetState()
mode.seed = "first"
done, left = spudFieldRemotePass(seedJob, field, tool)
check("partial batch -> done with cells left", done == true and left == 1,
    tostring(done) .. "," .. tostring(left))
check("partial batch does not disable the job", spudFieldRemoteState.off.seed ~= true)

-- 5. an ignored batch drives instead and switches the job off for the session
resetCells()
resetState()
mode.seed = "none"
done, left = spudFieldRemotePass(seedJob, field, tool)
check("ignored batch -> false with every cell left", done == false and left == 2,
    tostring(done) .. "," .. tostring(left))
check("ignored batch switches the job off", spudFieldRemoteState.off.seed == true)
local calls = seedRemote.invokeCalls
spudFieldRemotePass(seedJob, field, tool)
check("a job switched off fires nothing", seedRemote.invokeCalls == calls)

-- 6. TESTS · batch field remote (off by default): one call with every id
spudBatchRemotes = true
resetCells()
resetState()
mode.seed = "all"
local b0 = seedRemote.invokeCalls
done, left = spudFieldRemotePass(seedJob, field, tool)
check("batch test: one call finishes the field", done == true and left == 0,
    tostring(done) .. "," .. tostring(left))
check("batch test: exactly one call was made", seedRemote.invokeCalls - b0 == 1,
    tostring(seedRemote.invokeCalls - b0))
check("batch test: the call carries every id",
    seedRemote.lastId == 642 and seedRemote.lastAtt == att)
check("batch test: it says the whole field took the list",
    loggedText():find("✅ batch test") ~= nil)

resetCells()
resetState()
mode.seed = "firstBatch"
b0 = seedRemote.invokeCalls
done, left = spudFieldRemotePass(seedJob, field, tool)
check("batch test: a partial list still finishes the field",
    done == true and left == 0, tostring(done) .. "," .. tostring(left))
check("batch test: the rest go one call per cell", seedRemote.invokeCalls - b0 == 2,
    tostring(seedRemote.invokeCalls - b0))
check("batch test: the log names the partial take",
    loggedText():find("took the id list") ~= nil)

resetCells()
resetState()
mode.seed = "oneOnly"
b0 = seedRemote.invokeCalls
done, left = spudFieldRemotePass(seedJob, field, tool)
check("batch test: an ignored list falls back to per-cell",
    done == true and left == 0, tostring(done) .. "," .. tostring(left))
check("batch test: an ignored list never switches the job off",
    spudFieldRemoteState.off.seed ~= true)
check("batch test: the log names the ignored list",
    loggedText():find("ignored the id list") ~= nil)
spudBatchRemotes = false

-- 7. no attachment / no remote -> no calls, drive instead
resetCells()
resetState()
mode.seed = "all"
calls = seedRemote.invokeCalls
done, left = spudFieldRemotePass(seedJob, field, noAttTool)
check("no attachment -> drive, no calls",
    done == false and seedRemote.invokeCalls == calls)
check("no attachment switches the job off", spudFieldRemoteState.off.seed == true)

resetCells()
resetState()
seedRemote.Name = "hidden"
done, left = spudFieldRemotePass(seedJob, field, tool)
check("missing remote -> drive, no calls",
    done == false and spudFieldRemoteState.off.seed == true)
seedRemote.Name = "FNCSeedFieldCell"

-- 6b. a seeder only fires as many calls as it holds seeds
local capConf = adopt(tool, newInst("Configurations", "Folder"))
local capVal = adopt(capConf, newInst("Capacity", "IntValue"))
capVal.Value = 0
resetCells()
resetState()
mode.seed = "all"
local d0 = seedRemote.invokeCalls
local dry
done, left, dry = spudFieldRemotePass(seedJob, field, tool)
check("empty seeder: not one seed call is fired", seedRemote.invokeCalls == d0,
    (seedRemote.invokeCalls - d0) .. " call(s)")
check("empty seeder: the pass hands the field back (dry)",
    done == true and left == 2 and dry == true,
    string.format("%s,%s,%s", tostring(done), tostring(left), tostring(dry)))
check("empty seeder: the job stays on", spudFieldRemoteState.off.seed ~= true)
capVal.Value = 1
resetCells()
resetState()
d0 = seedRemote.invokeCalls
done, left, dry = spudFieldRemotePass(seedJob, field, tool)
check("one seed: exactly one call", seedRemote.invokeCalls - d0 == 1,
    (seedRemote.invokeCalls - d0) .. " call(s)")
check("one seed: dry with one cell left", dry == true and left == 1,
    string.format("%s,%s", tostring(left), tostring(dry)))
capVal.Value = 50
resetCells()
resetState()
d0 = seedRemote.invokeCalls
done, left, dry = spudFieldRemotePass(seedJob, field, tool)
check("a full seeder: the whole field in one pass",
    done == true and left == 0 and not dry and seedRemote.invokeCalls - d0 == 2,
    string.format("%s,%s", tostring(done), tostring(left)))

-- 8. the harvest sibling is a RemoteFunction on the grown predicate
resetCells()
fieldState[field][700] = { Stage = "Grown" }
resetState()
local hv0 = harvestRemote.invokeCalls
local hf0 = harvestRemote.fireCalls
local harvestJob = { verb = "harvest", grown = true,
    remote = "FNCHarvestFieldCell", prog = "harvesting" }
done, left = spudFieldRemotePass(harvestJob, field, tool)
check("harvest uses InvokeServer, not FireServer",
    harvestRemote.invokeCalls - hv0 == 1 and harvestRemote.fireCalls == hf0,
    tostring(harvestRemote.invokeCalls - hv0))
check("harvest batch reports done", done == true and left == 0,
    tostring(done) .. "," .. tostring(left))

-- 8b. a harvester only takes what its tank has room for, and the tail is
--     retried once before a single row is driven
local maxVal = adopt(capConf, newInst("MaxCapacity", "IntValue"))
capVal.Value = 49
maxVal.Value = 50
fieldState[field][701] = { Stage = "Grown" }
resetCells()
fieldState[field][700] = { Stage = "Grown" }
fieldState[field][701] = { Stage = "Grown" }
resetState()
hv0 = harvestRemote.invokeCalls
capVal.Value = 50 -- tank full
done, left, dry = spudFieldRemotePass(harvestJob, field, tool)
check("full tank: no harvest call is fired", harvestRemote.invokeCalls == hv0,
    (harvestRemote.invokeCalls - hv0) .. " call(s)")
check("full tank: the pass hands the field back (dry)",
    done == true and left == 2 and dry == true,
    string.format("%s,%s,%s", tostring(done), tostring(left), tostring(dry)))
capVal.Value = 49 -- room for exactly one
resetCells()
fieldState[field][700] = { Stage = "Grown" }
fieldState[field][701] = { Stage = "Grown" }
resetState()
hv0 = harvestRemote.invokeCalls
done, left, dry = spudFieldRemotePass(harvestJob, field, tool)
check("one slot: exactly one harvest call", harvestRemote.invokeCalls - hv0 == 1,
    (harvestRemote.invokeCalls - hv0) .. " call(s)")
check("one slot: dry with one cell standing", dry == true and left == 1,
    string.format("%s,%s", tostring(left), tostring(dry)))

-- 8c. a refused tail is retried once, and a full seeder still needs no rows
capVal.Value = 50
maxVal.Value = 50
resetCells()
resetState()
mode.seed = "retryOnce"
d0 = seedRemote.invokeCalls
done, left, dry = spudFieldRemotePass(seedJob, field, tool)
check("retry: the refused tail is fired again", seedRemote.invokeCalls - d0 == 4,
    (seedRemote.invokeCalls - d0) .. " call(s)")
check("retry: the field finishes with no row",
    done == true and left == 0 and not dry,
    string.format("%s,%s", tostring(done), tostring(left)))
check("retry: the log says the retry finished it",
    loggedText():find("the retry finished the field") ~= nil)
mode.seed = "all"

-- 9. FillSeeder: fired with the seeder, refusal falls back to V
resetState()
mode.fill = "ok"
local f0 = fillRemote.invokeCalls
check("FillSeeder fires with the seeder model",
    spudFillSeederRemote(tool) == true and fillRemote.invokeCalls - f0 == 1
        and fillRemote.lastArg == tool)
check("FillSeeder with no seeder fires nothing",
    spudFillSeederRemote(nil) == false)
mode.fill = "no"
check("a refused FillSeeder reports false (V is the fallback)",
    spudFillSeederRemote(tool) == false)

-- 10. the kit goes away with the module folder
resetState()
larry.Name = "LarryX"
check("no Modules.Larry -> no kit", spudFieldRemoteKit() == nil)
larry.Name = "Larry"

-- 11. the ride is hopped onto each remaining cell so the blade is over it
local hopAttPart = newInst("RaycastPart", "Part")
hopAttPart.Position = Vector3.new(0, 0, -5)
local hopAtt = newInst("Attachment", "Attachment")
hopAtt.Parent = hopAttPart
ATTPARENT = hopAttPart
RIDE_POS = Vector3.new(0, 0, 0)
local hopRide = {}
local rides = 0
function hopRide:GetPivot() return setmetatable({ Position = RIDE_POS }, CF) end
function hopRide:PivotTo(cf)
    rides = rides + 1
    RIDE_POS = cf.pos
    ATTPARENT.Position = RIDE_POS + Vector3.new(0, 0, -5)
end
local baseCF = setmetatable({ base = true, Position = Vector3.new(0, 0, 0) }, CF)
local baseSize = Vector3.new(50, 1, 20)
capVal.Value = 50
mode.seed = "all"
mode.atCell = true
resetCells()
resetState()
local h0 = seedRemote.invokeCalls
local tookHop, hopDry = spudHopCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("hop: the blade is lined up on both cells", tookHop == 2, tostring(tookHop))
check("hop: one call per cell", seedRemote.invokeCalls - h0 == 2,
    (seedRemote.invokeCalls - h0) .. " call(s)")
check("hop: the field is done afterwards",
    #spudFieldCellIds(field, "Cultivated") == 0)
check("hop: a full seeder means not dry", hopDry == false, tostring(hopDry))

resetCells()
resetState()
capVal.Value = 1
local tookOne, dryOne = spudHopCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("hop: one seed hops one cell and hands back",
    tookOne == 1 and dryOne == true,
    string.format("%s,%s", tostring(tookOne), tostring(dryOne)))
capVal.Value = 50
mode.atCell = false

-- 12. SWEEP + FIRE: one serpentine tween, a burst every 0.5 s (10 studs at
--     the 20 studs/s default) at the cells the blade is passing
local function sweepGrid()
    fieldState[field] = {}
    for x = 1, 5 do
        for y = 1, 3 do
            fieldState[field][x * 128 + y] = { Stage = "Cultivated" }
        end
    end
end

mode.seed = "all"
mode.atCell = true
acceptR = 14 -- the blade's catch range: what the sweep fires at, it takes
capVal.Value = 50
sweepGrid()
resetState()
local r0 = rides
local s0 = seedRemote.invokeCalls
local tookS, dryS = spudSweepCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("sweep: every cell of the field is taken", tookS == 15, tostring(tookS))
check("sweep: one call per cell", seedRemote.invokeCalls - s0 == 15,
    (seedRemote.invokeCalls - s0) .. " call(s)")
check("sweep: the field is empty afterwards",
    #spudFieldCellIds(field, "Cultivated") == 0)
check("sweep: a full seeder means not dry", dryS == false, tostring(dryS))
check("sweep: the ride is tweened, not teleported", rides - r0 > 50,
    (rides - r0) .. " pivot(s)")
check("sweep: the log says what the sweep did",
    loggedText():find("swept 15 cell") ~= nil
        and loggedText():find("at 45 studs/s, range 14") ~= nil)

-- a seeder can only fire as many calls as it holds seeds
capVal.Value = 3
sweepGrid()
resetState()
s0 = seedRemote.invokeCalls
local tookB, dryB = spudSweepCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("sweep: 3 seeds fire 3 calls", seedRemote.invokeCalls - s0 == 3,
    (seedRemote.invokeCalls - s0) .. " call(s)")
check("sweep: the seeder runs dry mid-field", dryB == true and tookB == 3,
    string.format("%s,%s", tostring(tookB), tostring(dryB)))

-- a server that only takes a cell under the blade: the near fire catches it
-- even though the bursts are 22 studs apart
acceptR = 5
capVal.Value = 50
sweepGrid()
resetState()
s0 = seedRemote.invokeCalls
local tookN, dryN = spudSweepCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("sweep: a blade-over server still gets every cell", tookN == 15, tostring(tookN))
check("sweep: no cell is fired twice", seedRemote.invokeCalls - s0 == 15,
    (seedRemote.invokeCalls - s0) .. " call(s)")
check("sweep: a passing cell never leaves the field dry", dryN == false, tostring(dryN))

-- a job with no load to spend (plow/cultivate) also gets the wide burst, and
-- a burst the server refuses must NOT stop the close fire later
acceptR = 5
sweepGrid()
resetState()
local cultJob = { verb = "cultivate", stage = "Cultivated",
    remote = "EVTCultivateFieldCell", prog = "cultivating" }
local cu0 = cultRemote.fireCalls
local tookC, dryC = spudSweepCells(cultJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("sweep: a refused wide burst does not block the close fire",
    tookC == 15, tostring(tookC))
check("sweep: a close-only budget is never charged for a burst",
    dryC == false, tostring(dryC))
check("sweep: a no-load job does burst and then fire close", cultRemote.fireCalls - cu0 >= 15,
    (cultRemote.fireCalls - cu0) .. " call(s)")

-- a server that takes nothing leaves the whole field for the hop/drive
acceptR = -1
capVal.Value = 50
sweepGrid()
resetState()
s0 = seedRemote.invokeCalls
local tookI, dryI = spudSweepCells(seedJob, field, hopRide, tool, "Cultivated",
    baseCF, baseSize, hopAtt)
check("sweep: an ignored sweep takes nothing", tookI == 0, tostring(tookI))
check("sweep: every cell is still standing",
    #spudFieldCellIds(field, "Cultivated") == 15)
check("sweep: an ignored sweep never switches the job off",
    spudFieldRemoteState.off.seed ~= true)
check("sweep: an ignored sweep is not dry", dryI == false, tostring(dryI))
resetCells()
mode.atCell = false
acceptR = 2

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
