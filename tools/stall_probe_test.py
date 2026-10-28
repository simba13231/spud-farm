"""Run the real SpudStallProbe.lua on a fake game tree.

The probe is the evidence tool for naming a stall's dirt field, so it has to do
two things without a real client: print everything about one stall folder
(children, values, attributes, visible stains, the Clean billboard) and never
crash on a shape it did not expect. Both are checked here, plus the "read-only"
claim (no key press, no CFrame write, no metatable hook, no remote).

    python tools/stall_probe_test.py [path-to-luau.exe]
"""

import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudStallProbe.lua"

PRE = r"""
local V = {}
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end

typeof = function(v)
    if type(v) == "table" and v._inst then return "Instance" end
    return type(v)
end

local function node(name, cls, kids, extra)
    local o = { Name = name, ClassName = cls, _kids = {}, _attrs = {}, _inst = true }
    for k, v in pairs(extra or {}) do o[k] = v end
    for _, c in ipairs(kids or {}) do
        c.Parent = o
        o._kids[#o._kids + 1] = c
    end
    function o:FindFirstChild(n, rec)
        for _, c in ipairs(self._kids) do
            if c.Name == n then return c end
        end
        if rec then
            for _, c in ipairs(self._kids) do
                local hit = c:FindFirstChild(n, true)
                if hit then return hit end
            end
        end
        return nil
    end
    function o:GetChildren() return self._kids end
    function o:GetDescendants()
        local out = {}
        local function walk(x)
            for _, c in ipairs(x._kids) do out[#out + 1] = c; walk(c) end
        end
        walk(self)
        return out
    end
    function o:IsA(c)
        if self.ClassName == c then return true end
        if c == "BasePart" and self.ClassName == "Part" then return true end
        return false
    end
    function o:GetPivot() return { Position = self.Position or vec(0, 0, 0) } end
    function o:GetAttributes() return self._attrs end
    function o:GetFullName()
        if self.Parent then return self.Parent:GetFullName() .. "." .. self.Name end
        return self.Name
    end
    return o
end

-- ── the fake farm: one barn in Objects.Buildings, two stalls, one plot ─────
local centre1 = node("Center", "Part", nil, { Position = vec(100, 0, 0), Transparency = 0, Size = vec(4, 1, 4) })
local spot1 = node("1", "Folder", {
    centre1,
    node("ProximityPart", "Part", nil, { Position = vec(100, 0, 0), Transparency = 0, Size = vec(4, 4, 4) }),
    node("Filth", "NumberValue", nil, { Value = 0 }),
    node("Stain", "Part", nil, { Position = vec(100, 0.1, 0), Transparency = 0.1, Size = vec(2, 0.1, 2) }),
    node("Stain", "Part", nil, { Position = vec(102, 0.1, 0), Transparency = 1, Size = vec(2, 0.1, 2) }),
    node("Adornee_BarnStallMenu", "Part", nil, { Position = vec(101, 2, 0), Transparency = 0, Size = vec(1, 1, 1) }),
}, { _attrs = { Filth = 12 } })

local spot2 = node("2", "Folder", {
    node("Center", "Part", nil, { Position = vec(120, 0, 0), Transparency = 0, Size = vec(4, 1, 4) }),
    node("Stain", "Part", nil, { Position = vec(120, 0.1, 0), Transparency = 0.2, Size = vec(2, 0.1, 2) }),
    node("Stain", "Part", nil, { Position = vec(121, 0.1, 0), Transparency = 1, Size = vec(2, 0.1, 2) }),
    node("Adornee_BarnStallMenu", "Part", nil, { Position = vec(121, 2, 0), Transparency = 0, Size = vec(1, 1, 1) }),
})

local spots = node("Spots", "Folder", { spot1, spot2 })
local barn = node("AutoWoodenBarn", "Model", { spots }, { Position = vec(110, 0, 0) })
local buildings = node("Buildings", "Folder", { barn })
local objects = node("Objects", "Folder", { buildings })
local plot = node("FarmPlot", "Model", {
    node("Dirt", "NumberValue", nil, { Value = 3 }),
}, { Position = vec(120, 0, 0) })
workspace = node("Workspace", "Workspace", { objects, plot })

-- the game's own Clean billboard, adorned to the FIRST stall right now
local billText = node("Label", "TextLabel", nil, { Text = "V | Clean" })
local bill = node("CleanAnimalContainer", "BillboardGui", { billText },
    { Enabled = true, Adornee = centre1 })
local bills = node("Billboards", "Folder", { bill })
local cpa = node("PCGP_ContextActions", "Folder", { bills })
local mainhud = node("MainHUD", "Folder", { cpa })
local hud = node("HUD", "ScreenGui", { mainhud })
local guiviews = node("GuiViews", "Folder", { hud })
local pg = node("PlayerGui", "PlayerGui", { guiviews })

local char = node("Character", "Model", {
    node("HumanoidRootPart", "Part", nil, { Position = vec(100, 3, 0) }),
})

-- ── the panel: enough of the Roblox UI API for the real code path to run ───
CREATED, CLIP = {}, nil
setclipboard = function(t) CLIP = t end
task = { delay = function(_, fn) fn() end }
UDim2 = setmetatable({}, { __index = function() return function(...) return { args = { ... } } end end })
Color3 = setmetatable({}, { __index = function() return function(...) return { args = { ... } } end end })
Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return {} end }) end })
Instance = {
    new = function(cls)
        local o = { ClassName = cls, _kids = {} }
        CREATED[#CREATED + 1] = o
        return setmetatable(o, {
            __index = function(_, k)
                if k == "Destroy" then return function() end end
                return { Connect = function() end }
            end,
        })
    end,
}
local LP = node("Me", "Player", { char })
LP.Character = char -- a property, not a child: the probe reads it directly
function LP:FindFirstChildOfClass(c) if c == "PlayerGui" then return pg end end
PLAYERS = { LocalPlayer = LP }
game = {
    PlaceId = 12345,
    JobId = "fake-job",
    GetService = function(_, n) if n == "Players" then return PLAYERS end end,
}
"""

POST = r"""
local gui, box, copyBtn, closeBtn
for _, o in ipairs(CREATED) do
    if o.ClassName == "ScreenGui" then gui = o end
    if o.ClassName == "TextBox" then box = o end
    if o.ClassName == "TextButton" and o.Text == "COPY REPORT" then copyBtn = o end
    if o.ClassName == "TextButton" and o.Text == "CLOSE" then closeBtn = o end
end
print("PROBE-CHECK gui=" .. tostring(gui ~= nil and gui.Name == "SpudStallProbe"))
print("PROBE-CHECK box=" .. tostring(box ~= nil and type(box.Text) == "string"
    and box.Text:find("SPUD STALL PROBE", 1, true) ~= nil
    and box.Text:find("== STALL", 1, true) ~= nil))
print("PROBE-CHECK buttons=" .. tostring(copyBtn ~= nil and closeBtn ~= nil))
print("PROBE-CHECK clipboard=" .. tostring(CLIP ~= nil
    and CLIP:find("== STALL", 1, true) ~= nil
    and CLIP:find("visible stain parts", 1, true) ~= nil))
"""


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")

    # the read-only claim, checked on the file itself
    banned = ["pressKey", "FireServer", "SimulateInput", "hookmetamethod",
              "getrawmetatable", "CFrame"]
    hits = [b for b in banned if b in src]
    fails = 0
    if hits:
        fails += 1
        print("read-only: FAIL  file mentions " + ", ".join(hits))

    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + "\n" + src + "\n" + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    text = out.stdout
    if out.returncode != 0:
        print(text.strip()[-2000:])
        print(out.stderr.strip()[-2000:])
        return out.returncode

    def has(needle, label, strict=True):
        nonlocal fails
        ok = needle in text if strict else needle.lower() in text.lower()
        if not ok:
            fails += 1
        print(f"{label:<56} {'PASS' if ok else 'FAIL'}")
        return ok

    if not hits:
        print(f"{'read-only: no key press, no CFrame, no hook':<56} PASS")

    has("== SPUD STALL PROBE", "it starts and names itself")
    has("stall(s) found in it: 2", "it counts the barn's stalls")
    has("== STALL 1", "it dumps one complete stall folder")
    has("Filth  [NumberValue]  0", "a value child is printed with its value")
    has("attrs{Filth=12}", "attributes are printed")
    has("<<< matches 'filth'", "dirt-sounding children are flagged inline")
    has("Adornee_BarnStallMenu", "the stall's menu part is in the dump")
    has("Workspace.Objects.Buildings.AutoWoodenBarn.Spots.1.Filth",
        "the candidate sweep names the field's path")
    has("barn  ", "the sweep looks outside the stall too")
    has("plot  ", "and at the plot")
    has("visible stain parts: 1", "only the VISIBLE stain counts as a stain")
    has("invisible stain parts: 1", "and the faded one is counted separately")
    has("VISIBLE  Stain", "the visible stain is listed with its transparency")
    has("adorned to:", "the Clean billboard's adornee is printed")
    has("text: V | Clean", "the Clean billboard's own key is printed")
    has("^ that is inside THIS stall", "it says when the billboard points at the stall")
    has("PROBE-CHECK gui=true", "a small panel is built on screen")
    has("PROBE-CHECK box=true", "the report is in the panel's text box")
    has("PROBE-CHECK buttons=true", "COPY REPORT and CLOSE are on the panel")
    has("PROBE-CHECK clipboard=true", "the report is copied to the clipboard")
    if "!!" in text:
        fails += 1
        print(f"{'no failure notices (!!) on a normal farm':<56} FAIL")
    else:
        print(f"{'no failure notices (!!) on a normal farm':<56} PASS")

    if fails:
        print(f"\n{fails} FAILED")
        print(text)
        return 1
    print("\nALL OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
