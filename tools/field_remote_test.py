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
    "spudFieldRemoteKit",
    "spudFieldCellIds",
    "spudToolAttachment",
    "spudFieldRemoteCall",
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
function stopping() return false end
task = task or {}
task.wait = function(_) end
function require(x) return x end

grownStage = function(s) return s == "Grown" end
spudFieldRemoteState = { kit = nil, off = {} }

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

local function seedHandler(field, ids)
    if mode.seed == "none" then return end
    local cells = fieldState[field]
    for _, id in ipairs(ids) do
        local cell = cells and cells[id]
        if cell and cell.Stage == "Cultivated" then
            if mode.seed == "all" or (mode.seed == "first" and id == 641) then
                cell.Stage = "Seeded"
            end
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

local seedRemote = newRemote("FNCSeedFieldCell", "RemoteFunction", seedHandler)
local cultRemote = newRemote("EVTCultivateFieldCell", "RemoteEvent", nil)
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

-- 6. no attachment / no remote -> no calls, drive instead
resetCells()
resetState()
mode.seed = "all"
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

-- 7. the harvest sibling is a RemoteFunction on the grown predicate
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

-- 8. FillSeeder: fired with the seeder, refusal falls back to V
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

-- 9. the kit goes away with the module folder
resetState()
larry.Name = "LarryX"
check("no Modules.Larry -> no kit", spudFieldRemoteKit() == nil)
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
