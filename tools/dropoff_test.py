"""Where does a full harvester unload? (spudSellNow + spudFulfillSpots)

The Farm tab now carries a Drop-off pick: FULFILLMENT (the probed pad
Stores.DropOffs.Deposit_Warehouse at -353,138,-90) or SELL (the old crop
sell-board scan). Two things must hold:

  * spudSellNow answers "is this tank full AND is a destination chosen?" —
    a full tank with an unknown destination still must not drive anywhere;
  * spudFulfillSpots names the Fulfillment pad from the world, aims at its
    top surface, prefers Deposit_Warehouse over Withdraw_Warehouse, and
    returns nothing (with a log line) when the folder is not streamed;
  * trySellAt presses NO key on the Fulfillment pad (the pad unloads a parked
    harvester by itself), while the Sell pads still try the captured call and
    then Q/E, and the tank dropping is the only proof of either.

    python tools/dropoff_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["spudSellNow", "spudFulfillSpots", "findSellSpots", "trySellAt", "sellHarvester"]

PRE = r"""
local V = {}
function V.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V) end
function V.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V) end
V.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
Vector3 = { new = function(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end }

local NODE = {}
NODE.__index = NODE
function NODE:FindFirstChild(name) return self.kids[name] end
function NODE:GetChildren() return self.list end
function NODE:GetDescendants()
    local out = {}
    local function walk(n)
        for _, k in ipairs(n.list) do
            out[#out + 1] = k
            walk(k)
        end
    end
    walk(self)
    return out
end
function NODE:IsA(cls) return cls == self._cls end

GRID = setmetatable({ kids = {}, list = {}, _cls = "Workspace" }, NODE)
workspace = GRID
local logged = {}
function log(s) logged[#logged + 1] = tostring(s) end
function loggedText() return table.concat(logged, "\n") end

local function folder(name, parent)
    local n = setmetatable({ Name = name, kids = {}, list = {}, _cls = "Folder" }, NODE)
    if parent then parent.kids[name] = n parent.list[#parent.list + 1] = n end
    return n
end
local function part(name, parent, x, y, z, sx, sy, sz)
    local n = setmetatable({ Name = name, kids = {}, list = {}, _cls = "BasePart",
        Position = Vector3.new(x, y, z), Size = Vector3.new(sx or 10, sy or 1, sz or 10) }, NODE)
    if parent then parent.kids[name] = n parent.list[#parent.list + 1] = n end
    return n
end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. the full-tank gate follows the destination pick
spudDropOff = "Fulfillment"
check("fulfillment: a full tank unloads", spudSellNow(50, 50) == true)
check("fulfillment: an over-full tank unloads", spudSellNow(60, 50) == true)
check("fulfillment: a half tank keeps working", spudSellNow(25, 50) == false)
check("fulfillment: an unreadable load never unloads", spudSellNow(nil, nil) == false)
check("fulfillment: a zero capacity never unloads", spudSellNow(0, 0) == false)
spudDropOff = "Sell"
check("sell: a full tank sells", spudSellNow(50, 50) == true)
check("sell: a half tank keeps working", spudSellNow(25, 50) == false)
spudDropOff = ""
check("no destination: a full tank stays put", spudSellNow(50, 50) == false)
spudDropOff = nil
check("nil destination: a full tank stays put", spudSellNow(50, 50) == false)

-- 2. the Fulfillment pad is named from the world
local stores = folder("Stores", workspace)
local drops = folder("DropOffs", stores)
local deposit = part("Deposit_Warehouse", drops, -353, 138, -90, 30, 4, 30)
part("Withdraw_Warehouse", drops, -286, 138, -217, 30, 4, 30)
part("DropOff", drops, 68, 138, -289, 12, 2, 12)

local spots = spudFulfillSpots()
check("fulfillment: one pad comes back", type(spots) == "table" and #spots == 1,
    type(spots) == "table" and ("got " .. #spots) or nil)
local s = spots and spots[1]
check("fulfillment: it is the deposit pad", s and s.what == "DropOffs.Deposit_Warehouse",
    s and tostring(s.what) or nil)
check("fulfillment: it aims at the top surface", s and s.p and math.abs(s.p.Y - 140) < 0.01,
    s and s.p and string.format("y=%.2f", s.p.Y) or nil)
check("fulfillment: x/z are the pad's centre", s and s.p and math.abs(s.p.X + 353) < 0.01
    and math.abs(s.p.Z + 90) < 0.01, nil)

-- 3. a lone withdraw pad is still better than refusing to move
drops.kids["Deposit_Warehouse"] = nil
drops.list = { drops.list[1], drops.list[3] } -- withdraw + plain dropoff
local spots2 = spudFulfillSpots()
check("no deposit pad: still returns a pad", type(spots2) == "table" and #spots2 >= 1,
    type(spots2) == "table" and ("got " .. #spots2) or nil)

-- 4. an unstreamed / empty folder is named, never guessed
local empty = folder("EmptyDrops", stores)
GRID.kids["Stores"] = stores
stores.kids["DropOffs"] = empty
stores.list = { empty }
local spots3 = spudFulfillSpots()
check("empty DropOffs: no pad", type(spots3) == "table" and #spots3 == 0, nil)
check("empty DropOffs: it says so", loggedText():lower():find("dropoff") ~= nil
    or loggedText():lower():find("unload") ~= nil, loggedText())

GRID.kids["Stores"] = nil
GRID.list = {}
local spots4 = spudFulfillSpots()
check("no Stores at all: no crash, no pad", type(spots4) == "table" and #spots4 == 0, nil)

-- 5. the pad behaviour itself: Fulfillment presses nothing, Sell calls then
--    falls back to Q/E, and the tank dropping is the only proof
local vtime = 0
task = { wait = function(t) vtime = vtime + (t or 0) end }
os = { clock = function() return vtime end }
Enum = { KeyCode = { Q = "Q", E = "E" } }
local keys, calls = {}, {}
local function resetPad()
    vtime, keys, calls = 0, {}, {}
    logged = {}
end
function pressKey(k) keys[#keys + 1] = tostring(k) end
function stopping() return false end
function coinBalance() return 100 end
function sellMenuOpen() return false end
function sellMenuGui() return nil end
function closeSellMenu() return true end
local drainAt, remoteTakes = 2.4, true
function spudSellRemote(ride, pad) calls[#calls + 1] = { ride = ride, pad = pad } return remoteTakes end
function harvesterLoad(ride) return vtime >= drainAt and 0 or 50 end

-- fulfillment: parked, the pad drains it, no key ever pressed
resetPad() drainAt = 2.4 remoteTakes = true
local okPad = trySellAt("ride", "Deposit_Warehouse", nil, true)
check("fulfillment pad: the tank dropping counts as unloaded", okPad == true)
check("fulfillment pad: no key is pressed", #keys == 0, #keys .. " key(s)")
check("fulfillment pad: no sell call is made", #calls == 0, #calls .. " call(s)")
check("fulfillment pad: the log says it presses nothing",
    loggedText():lower():find("pressing nothing") ~= nil)

-- sell: the captured call takes it inside the grace window, still no key
resetPad() drainAt = 3.4 remoteTakes = true
local okSell = trySellAt("ride", "DropOff", "padpart", false)
check("sell pad: the remote unloads it", okSell == true)
check("sell pad: the call carries (ride, pad)",
    calls[1] and calls[1].ride == "ride" and calls[1].pad == "padpart")
check("sell pad: a working remote presses no key", #keys == 0, #keys .. " key(s)")

-- sell: an ignored remote falls back to Q and E, and never claims a sale
resetPad() drainAt = 999 remoteTakes = false
local okIgnored = trySellAt("ride", "DropOff", "padpart", false)
local pressed = table.concat(keys, ",")
check("sell pad: an ignored remote is not a sale", okIgnored == false)
check("sell pad: it falls back to Q and E", pressed:find("Q") ~= nil and pressed:find("E") ~= nil, pressed)
check("sell pad: the failure line names the pad", loggedText():find("DropOff") ~= nil)

-- 6. a full tank still finds the store when no pad is streamed yet
local realFindSellSpots = findSellSpots -- keep the extracted one for section 7
local hops = {}
function hopTo(ride, target, speed)
    hops[#hops + 1] = { X = target.X, Y = target.Y, Z = target.Z }
    return true
end
local soldAt = nil
function trySellAt(ride, what, pad, autoPad)
    soldAt = { what = what, pad = pad, autoPad = autoPad }
    return true
end
function harvesterLoad(ride) return 50, 50 end
local ride = { GetPivot = function() return { Position = Vector3.new(10, 170, 10) } end }
local scanPad = { what = "SellArea.Pad", part = "padpart", p = Vector3.new(-300, 140, -90) }
local scanState = "pad"
function findSellSpots()
    if scanState == "pad" then return { scanPad } end
    if scanState == "none" then return {} end
    return scanPad -- "late": empty first scan, pad after the store hop
end
function spudFulfillSpots() return {} end
function storeAnchors() return { FarmCo = Vector3.new(-900, 140, -900) } end
spudDropOff = "Sell"
spudSellNow = function() return true end

-- 6a. a pad already streamed: no store hop, one sale
scanState = "pad"
hops, soldAt = {}, nil
local okSell = sellHarvester(ride, nil, nil)
check("sell: a streamed pad sells with only the pad hop",
    okSell == true and #hops == 1 and hops[1].X == -300,
    #hops .. " hop(s)")
check("sell: the sale happens at that pad", soldAt ~= nil and soldAt.what == "SellArea.Pad")

-- 6b. nothing streamed, then the store hop makes the pad appear
local scans = 0
function findSellSpots()
    scans += 1
    if scans == 1 then return {} end
    return { scanPad }
end
hops, soldAt = {}, nil
local fieldStub = { Parent = true, Name = "Field" }
local okLate = sellHarvester(ride, nil, fieldStub)
check("sell: no pad -> it hops to the store first", #hops >= 1 and hops[1].X == -900,
    #hops .. " hop(s)")
check("sell: after the hop it sells", okLate == true and soldAt ~= nil)
check("sell: the trip back returns to the field, not the store",
    hops[#hops].X == 10 and hops[#hops].Z == 10,
    hops[#hops] and string.format("%.0f,%.0f", hops[#hops].X, hops[#hops].Z) or "no hop")

-- 6c. nothing streamed and no marker at all: it says so and fires nothing
function findSellSpots() return {} end
function storeAnchors() return {} end
hops, soldAt = {}, nil
local okNone = sellHarvester(ride, nil, nil)
check("sell: no pad and no marker -> no sale, no hop", okNone == false and #hops == 0 and soldAt == nil)
check("sell: the log says the unload was skipped",
    loggedText():find("pad found") ~= nil and loggedText():find("skipped") ~= nil)

-- 7. every sell spot carries the part the sell call fires at
local gvNode = folder("GameplayVisuals", GRID)
local saNode = folder("SellArea", gvNode)
part("Pad", saNode, 20, 100, 20, 10, 1, 10)
local markersNode = folder("Markers", GRID)
local gotosNode = folder("GotoLocations", markersNode)
part("FarmCo", gotosNode, 0, 100, 0, 8, 1, 8)
part("SellBoardSeeds", gotosNode, 0, 100, 0, 8, 1, 8)
function storeAnchors() return { FarmCo = Vector3.new(0, 100, 0) } end
local sellSpots = realFindSellSpots()
check("sell spots: pads are found", #sellSpots > 0, #sellSpots .. " spot(s)")
local missingPart = 0
for _, s in ipairs(sellSpots) do
    if not s.part then missingPart += 1 end
end
check("sell spots: every spot carries the part to fire at", missingPart == 0,
    missingPart .. " without part")

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
    if not re.search(r'spudDropOff\s*=.*"Fulfillment"', src):
        print("missing the Fulfillment default (spudDropOff)")
        return 2
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
