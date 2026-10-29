"""Working-width and row-plan tests for the farm sweep (SpudFarm module).

The sweep used to assume ONE 10-stud tile: rows every 10 studs, a 10-stud
headland band. A 3-wide tool would then overlap three times and take three
times as long. The module measures the tool's physical width across the step
axis, turns it into tiles (the field grid is 10-stud tiles) and plans rows at
`tiles * 10`.

    python tools/farm_width_test.py [path-to-luau.exe]
"""

import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
START = "-- >>> SPUD FARM MODULE"
END = "-- <<< SPUD FARM MODULE"

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- a box: centre (x,z), size, and the model's own right/up/look axes
local function box(x, z, sx, sz, right, look)
    return { x = x, z = z, sx = sx, sy = 1, sz = sz,
        r = right or { 1, 0, 0 }, u = { 0, 1, 0 }, l = look or { 0, 0, 1 } }
end

-- ── 1. studs -> tiles (10-stud field grid) ─────────────────────────────────
check("width: 30 studs is 3 tiles", SpudFarm.widthTiles(30) == 3,
    tostring(SpudFarm.widthTiles(30)))
check("width: 28 studs rounds to 3", SpudFarm.widthTiles(28) == 3,
    tostring(SpudFarm.widthTiles(28)))
check("width: 25 studs rounds to 3 (covers 3 rows)", SpudFarm.widthTiles(25) == 3,
    tostring(SpudFarm.widthTiles(25)))
check("width: 10 studs is 1 tile", SpudFarm.widthTiles(10) == 1,
    tostring(SpudFarm.widthTiles(10)))
check("width: 15 studs is 2 tiles", SpudFarm.widthTiles(15) == 2,
    tostring(SpudFarm.widthTiles(15)))
check("width: unreadable is 1 tile", SpudFarm.widthTiles(0) == 1,
    tostring(SpudFarm.widthTiles(0)))
check("width: absurd width is clamped to 12", SpudFarm.widthTiles(500) == 12,
    tostring(SpudFarm.widthTiles(500)))

-- ── 2. physical width across the step axis ─────────────────────────────────
local step = { x = 1, z = 0 }
local w = SpudFarm.widthFromParts({ box(0, 0, 30, 4) }, step)
check("parts: a 30-stud blade measures 30", math.abs(w - 30) < 0.01,
    string.format("%.2f", w))

-- two discs 20 studs apart, 6 wide each: the union spans 26
w = SpudFarm.widthFromParts({ box(-10, 0, 6, 4), box(10, 0, 6, 4) }, step)
check("parts: spread discs are a union, not one disc", math.abs(w - 26) < 0.01,
    string.format("%.2f", w))

-- a bar turned 90 degrees: its 30-stud dimension is now size.Z along look
w = SpudFarm.widthFromParts({ box(0, 0, 4, 30, { 0, 0, 1 }, { 1, 0, 0 }) }, step)
check("parts: a rotated bar measures its real ground width", math.abs(w - 30) < 0.01,
    string.format("%.2f", w))

check("parts: no parts measures 0", SpudFarm.widthFromParts({}, step) == 0,
    tostring(SpudFarm.widthFromParts({}, step)))

-- ── 3. row plan: 1-wide is exactly the old geometry ────────────────────────
local p = SpudFarm.rowPlan(100, 1)
check("plan 1-wide: row step 10", p.rowStep == 10, tostring(p.rowStep))
check("plan 1-wide: headland 10", p.headBand == 10, tostring(p.headBand))
check("plan 1-wide: row half-extent 45", math.abs(p.rowHalf - 45) < 0.01,
    tostring(p.rowHalf))
check("plan 1-wide: 8 interior lines", #p.lines == 8, tostring(#p.lines))
check("plan 1-wide: lines span +/-35", math.abs(p.lines[1] - 35) < 0.01
    and math.abs(p.lines[#p.lines] + 35) < 0.01,
    p.lines[1] .. " .. " .. p.lines[#p.lines])

-- ── 4. row plan: 3-wide covers the field without gaps ──────────────────────
local function covered(plan, rowSpan)
    local w = plan.width
    local iv = {
        { -plan.rowHalf - w / 2, -plan.rowHalf + w / 2 },
        {  plan.rowHalf - w / 2,  plan.rowHalf + w / 2 },
    }
    for _, s in ipairs(plan.lines) do
        iv[#iv + 1] = { s - w / 2, s + w / 2 }
    end
    table.sort(iv, function(a, b) return a[1] < b[1] end)
    local reach = -rowSpan / 2
    for _, seg in ipairs(iv) do
        if seg[1] > reach + 1 then
            return false, string.format("gap %.1f..%.1f", reach, seg[1])
        end
        if seg[2] > reach then reach = seg[2] end
    end
    return reach >= rowSpan / 2 - 1,
        string.format("reach %.1f/%.1f", reach, rowSpan / 2)
end

p = SpudFarm.rowPlan(100, 3)
check("plan 3-wide: row step 30", p.rowStep == 30, tostring(p.rowStep))
check("plan 3-wide: headland 30", p.headBand == 30, tostring(p.headBand))
check("plan 3-wide: row half-extent 35", math.abs(p.rowHalf - 35) < 0.01,
    tostring(p.rowHalf))
local ok, detail = covered(p, 100)
check("plan 3-wide: 100-stud field fully covered", ok, detail)

p = SpudFarm.rowPlan(200, 3)
ok, detail = covered(p, 200)
check("plan 3-wide: 200-stud field fully covered", ok, detail)

p = SpudFarm.rowPlan(100, 2)
ok, detail = covered(p, 100)
check("plan 2-wide: 100-stud field fully covered", ok, detail)

p = SpudFarm.rowPlan(100, 1)
ok, detail = covered(p, 100)
check("plan 1-wide: 100-stud field fully covered", ok, detail)

-- a field narrower than the headland band: one centre pass, not two rows
p = SpudFarm.rowPlan(40, 3)
check("plan 3-wide: narrow field gets one centre pass",
    #p.lines == 1 and p.lines[1] == 0,
    #p.lines .. " line(s)")
ok, detail = covered(p, 40)
check("plan 3-wide: narrow field still covered", ok, detail)

-- ── 5. whose field is it? ──────────────────────────────────────────────────
check("owner: my field matches", SpudFarm.ownerWanted("me", "me", nil) == true)
check("owner: the picked farm matches", SpudFarm.ownerWanted("bob", "me", "bob") == true)
check("owner: another owner does not", SpudFarm.ownerWanted("bob", "me", nil) == false)
check("owner: a different pick does not", SpudFarm.ownerWanted("bob", "me", "alice") == false)
check("owner: an unreadable owner never matches", SpudFarm.ownerWanted(nil, "me", "bob") == false)
-- a picked farm must be worked ALONE: "it's using the player it's working
-- for's equipment then going on it's own field" - my fields are not part of
-- that tour, or the machinery and the soil disagree
check("owner: my field does not match while bob is picked",
    SpudFarm.ownerWanted("me", "me", "bob") == false)
check("owner: a blank pick still means mine",
    SpudFarm.ownerWanted("me", "me", "") == true)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract(text: str) -> str:
    a, b = text.find(START), text.find(END)
    if a < 0 or b <= a:
        return ""
    return text[a:b].strip() + "\n"


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    module = extract(SRC.read_text(encoding="utf-8"))
    if not module:
        print("missing SPUD FARM MODULE markers in SpudFarm_Full.lua")
        return 2
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as fh:
        fh.write(module + "\n" + POST)
        path = fh.name
    try:
        out = subprocess.run([str(exe), path], capture_output=True,
                             encoding="utf-8", errors="replace")
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
