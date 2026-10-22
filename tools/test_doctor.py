"""Run the DOCTOR report from SpudFarm_Full.lua outside Roblox.

The report is read-only, so it can be exercised with stubbed game objects:
this slices the real code out of the script (no copy-paste) and runs it under
the real Luau interpreter with fake Vector3 / workspace / equipment.
"""
import subprocess
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
LUAU = pathlib.Path(r"C:/Users/MIOUTH~1/AppData/Local/Temp/luau-check/luau.exe")

START = "    local okPanel, errPanel = pcall(function()"
END = "    -- ON = spawn the loop on its own thread"

text = SRC.read_text(encoding="utf-8")
i = text.index(START)
j = text.index(END, i)
block = text[i:j]
block = "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())

PRE = """
-- ── stubs ────────────────────────────────────────────────────────────────
VERSION = "test-build"
local V3 = {}
V3.__index = V3
V3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
-- Magnitude is a FIELD here (a property in Roblox), so format("%.0f") sees a number
local function v3(x, y, z)
  return setmetatable({ X = x, Y = y, Z = z,
    Magnitude = math.sqrt(x * x + y * y + z * z) }, V3)
end
Vector3 = { zero = v3(0, 0, 0), new = v3 }

local GENV = {}
getgenv = function() return GENV end

local CHAR = { HumanoidRootPart = { Position = Vector3.new(10, 5, 20) } }
function CHAR.FindFirstChild(self, k)
  if k == "HumanoidRootPart" then return self.HumanoidRootPart end
  return nil
end
LocalPlayer = { Name = "Tester", Character = CHAR }

local function part(pos, cls)  -- a fake BasePart-ish object
  return { Position = pos, IsA = function(_, c) return c == (cls or "BasePart") end }
end

local function model(name, cls, at, attrs, ints)
  local kids = {}
  local m = {
    Name = name,
    _pivot = at,
    IsA = function(_, c) return c == cls end,
    GetAttribute = function(_, k) return (attrs or {})[k] end,
    GetPivot = function(self) return { Position = self._pivot } end,
    GetChildren = function() return kids end,
    FindFirstChild = function(_, k)
      for _, v in ipairs(kids) do if v.Name == k then return v end end
      return nil
    end,
  }
  for k, v in pairs(ints or {}) do
    kids[#kids + 1] = { Name = k, Value = v, IsA = function(_, c) return c == "IntValue" end }
  end
  -- Configurations holder
  if ints then
    kids = { { Name = "Configurations", IsA = function(_, c) return c == "Folder" end,
               GetChildren = function() return (function()
                 local out = {}
                 for k, v in pairs(ints) do
                   out[#out + 1] = { Name = k, Value = v,
                     IsA = function(_, c) return c == "IntValue" end }
                 end
                 return out
               end)() end } }
  end
  return m
end

local EQUIP = {
  model("ZM80", "Model", Vector3.new(12, 3, 24), { EquipmentType = "Harvester" },
        { Capacity = 30, MaxCapacity = 60 }),
  model("KADL", "Model", Vector3.new(-100000, 20, 5), { EquipmentType = "Planter", InStorage = true }),
  model("PLOWY", "Model", Vector3.new(14, 3, 26), { EquipmentType = "Plow" }),
}
equipmentFolder = function() return { GetChildren = function() return EQUIP end } end

local PLATE = { X = 60, Y = 1, Z = 40 }
fieldFrame = function(d) return { Position = Vector3.new(0, 0, 0) }, (d and d.plate or nil) end

SALE = {
  { p = Vector3.new(100, 4, 100), what = "SellArea.SellPad", store = "FarmCo",
    named = true, dist = 812 },
  { p = Vector3.new(900, 4, 100), what = "AreaMarkers.FarmCoPad", store = "FarmCo",
    named = true, dist = 1400 },
}

findSellSpots = function() return SALE end

local function field(name, owned, withPlate)
  local cfgKids = {}
  local owner = { Name = "Owner", Value = owned and LocalPlayer or { Name = "other" },
                  IsA = function(_, c) return c == "ObjectValue" end }
  local ftype = { Name = "FieldType", Value = "Crop",
                  IsA = function(_, c) return c == "StringValue" end }
  return {
    Name = name, plate = withPlate and PLATE or nil,
    IsA = function(_, c) return c == "Model" end,
    GetPivot = function() return { Position = Vector3.new(50, 0, 50) } end,
    FindFirstChild = function(_, k)
      if k == "Configurations" then
        return { FindFirstChild = function(_, kk)
          if kk == "Owner" then return owner end
          if kk == "FieldType" then return ftype end
          return nil
        end }
      end
      return nil
    end,
  }
end

local FIELDS = { field("Field_1", true, true), field("Field_2", true, false), field("Field_9", false, true) }
workspace = {
  FindFirstChild = function(_, k)
    if k == "Objects" then
      return { FindFirstChild = function(_, kk)
        if kk == "Equipment" then return equipmentFolder() end
        if kk == "Fields" then return { GetChildren = function() return FIELDS end } end
        return nil
      end }
    end
    return nil  -- no Plots folder: the second source must be optional
  end,
}

local PARAVAL = nil
Tabs = { Doctor = {} }
function Tabs.Doctor.CreateParagraph(self, name, opts)
  return { SetValue = function(_, v) PARAVAL = v end }
end
local BTN = nil
function Tabs.Doctor.CreateButton(self, opts) BTN = opts end

local LOGS = {}
log = function(s) LOGS[#LOGS + 1] = tostring(s) end

loopThread = nil
runStage = "harvest pass"
sellCooldownUntil = 0
harvesterLoad = function() return 30, 60 end

-- ── the real DOCTOR code, verbatim from SpudFarm_Full.lua ────────────────
"""

POST = """
-- assertions (ASCII needles on purpose: the report has em-dashes and dots)
local function has(needle, label)
  assert(PARAVAL:find(needle, 1, true),
    (label or needle) .. " missing from the report:!" .. string.char(10) .. PARAVAL)
end
local function hasNot(needle, label)
  assert(not PARAVAL:find(needle, 1, true),
    (label or needle) .. " should not be in the report:!" .. string.char(10) .. PARAVAL)
end

assert(type(BTN) == "table" and type(BTN.Callback) == "function", "no doctor button was created")
BTN.Callback()
if type(PARAVAL) ~= "string" or #PARAVAL < 200 then
  for _, l in ipairs(LOGS) do print("LOG: " .. l) end
end
assert(type(PARAVAL) == "string" and #PARAVAL > 200,
  "report was not written to the paragraph")

-- ── the happy path ───────────────────────────────────────────────────────
has("DOCTOR")
has("test-build", "version")
has("loop: idle")
has("stage: harvest pass")
has("you: Tester at (10, 5, 20)")
has("ZM80 [Harvester")
has("Capacity=30 MaxCapacity=60")
has("KADL [Planter")
has("VOID", "void flag")
has("needs a respawn", "void anomaly")
has("Field_1 [Crop]")
has("40 plate", "field plate size")
has("NO READABLE PLATE")
has("can't plan a spiral", "plate anomaly")
has("SellArea.SellPad")
has("store FarmCo")
has("thing(s) to look at", "anomaly summary")
has("PLOWY", "every model is listed")
has("fields (yours):", "fields header")
has("sell pads (ranked", "pads header")
hasNot("Field_9", "another player's field")
assert(#LOGS >= 1 and LOGS[#LOGS]:find("doctor:", 1, true), "console tell missing")

-- ── cooldown is reported while it is in the future ───────────────────────
sellCooldownUntil = os.clock() + 41
BTN.Callback()
has("cooling down", "cooldown line")
sellCooldownUntil = 0

-- ── no character: no crash, and the distances say where they came from ───
localRealCharacter = LocalPlayer.Character
LocalPlayer.Character = nil
BTN.Callback()
has("NO CHARACTER")
has("measured from 0,0,0", "no-character anomaly")
LocalPlayer.Character = localRealCharacter

-- ── no equipment folder at all ───────────────────────────────────────────
local realFolder = equipmentFolder
equipmentFolder = function() return nil end
BTN.Callback()
has("no equipment models under Objects.Equipment", "empty-equipment anomaly")
equipmentFolder = realFolder

-- ── no sell pads at all ──────────────────────────────────────────────────
local realSpots = findSellSpots
findSellSpots = function() return {} end
BTN.Callback()
has("no sell pads found", "empty-pads anomaly")
findSellSpots = realSpots

-- no button needed: spudDoctor() must stand alone
assert(type(GENV.spudDoctor) == "function", "spudDoctor() was not exposed")
PARAVAL = nil
local msg = GENV.spudDoctor()
assert(PARAVAL and #PARAVAL > 200, "spudDoctor() did not produce the report")
assert(type(msg) == "string" and msg:find("done", 1, true), "spudDoctor() returned no tell")

-- a tab that refuses the panel must still leave the report usable
doctorPara = nil
assert(pcall(GENV.spudDoctor), "spudDoctor() crashed when the panel was missing")

print("doctor harness: OK")
print("----------------------------------------")
print(PARAVAL)
"""

full = PRE + block + POST
out = pathlib.Path(tempfile.gettempdir()) / "doctor_harness.lua"
out.write_text(full, encoding="utf-8")

res = subprocess.run([str(LUAU), str(out)], capture_output=True, text=True)
sys.stdout.write(res.stdout)
sys.stderr.write(res.stderr)
sys.exit(res.returncode)
