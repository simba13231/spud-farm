"""Behaviour tests for the path engine (SpudPath) in SpudFarm_Full.lua.

The engine lives at the TOP LEVEL of the file, outside the GUI build closure,
because that closure is one register away from Luau's 200-local wall. The
harness slices the `-- >>> SPUD PATH MODULE` block out of the real script and
runs it under the real Luau interpreter, so these are the shipped functions,
not a copy.

What is proved here:
  * the heap pops lowest f (ties by h) - the old open list was a linear scan
  * 8-connected A* finds the gap, never cuts a corner, and reports pops
  * exact grid traversal sees a thin wall a sampled line could step over
  * Lazy Theta* produces any-angle paths that are shorter than 8-way ones
  * clearance stops a line hugging an obstacle
  * a corner arc is refused when it would swing into gear (clearance margin)
    and curvature is bounded (or the vertex stays sharp)
  * obstacles ABOVE the ride (roofs/pipes) no longer block the ground, and a
    buried or ignored part does not either
  * cell size follows trip length (finer than the old 24-stud long-haul grid)

    python tools/path_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

START = "-- >>> SPUD PATH MODULE"
END = "-- <<< SPUD PATH MODULE"

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function key(ix, iz) return ix * 100000 + iz end

local function map(nx, nz, walls)
    local blocked = {}
    for _, w in ipairs(walls or {}) do blocked[key(w[1], w[2])] = true end
    local m = { nx = nx, nz = nz, blocked = blocked, cell = 1, x0 = 0, z0 = 0 }
    m.clear = SpudPath.clearance(nx, nz, blocked)
    return m
end

local function opts(m, sx, sz, gx, gz)
    return { nx = m.nx, nz = m.nz, blocked = m.blocked, clear = m.clear,
        cell = m.cell, x0 = m.x0, z0 = m.z0, sx = sx, sz = sz, gx = gx, gz = gz }
end

local function pathFree(m, path)
    for _, p in ipairs(path or {}) do
        if m.blocked[key(p[1], p[2])] then return false end
    end
    return true
end

local function noCornerCut(m, path)
    for i = 2, #path do
        local ax, az = path[i - 1][1], path[i - 1][2]
        local bx, bz = path[i][1], path[i][2]
        if math.abs(bx - ax) <= 1 and math.abs(bz - az) <= 1
            and bx ~= ax and bz ~= az then
            if m.blocked[key(bx, az)] and m.blocked[key(ax, bz)] then
                return false
            end
        end
    end
    return true
end

local function cellLen(path)
    local d = 0
    for i = 2, #path do
        local dx = path[i][1] - path[i - 1][1]
        local dz = path[i][2] - path[i - 1][2]
        d = d + math.sqrt(dx * dx + dz * dz)
    end
    return d
end

local function clearAt(ctx, x, z)
    local ix = math.floor((x - ctx.x0) / ctx.cell)
    local iz = math.floor((z - ctx.z0) / ctx.cell)
    if ix < 0 or iz < 0 or ix >= ctx.nx or iz >= ctx.nz then return -1 end
    return ctx.clear[key(ix, iz)] or 0
end

local function curvatureOf(a, b, c)
    local ux, uz = b[1] - a[1], b[2] - a[2]
    local vx, vz = c[1] - b[1], c[2] - b[2]
    local lu = math.sqrt(ux * ux + uz * uz)
    local lv = math.sqrt(vx * vx + vz * vz)
    if lu < 1e-6 or lv < 1e-6 then return 0 end
    local cosang = math.clamp((ux * vx + uz * vz) / (lu * lv), -1, 1)
    return math.acos(cosang) / ((lu + lv) / 2)
end

local function fakePart(x, y, z, sx, sy, sz)
    return {
        CFrame = {
            Position = { X = x, Y = y, Z = z },
            RightVector = { X = 1, Y = 0, Z = 0 },
            UpVector = { X = 0, Y = 1, Z = 0 },
            LookVector = { X = 0, Y = 0, Z = 1 },
        },
        Size = { X = sx, Y = sy, Z = sz },
        CanCollide = true,
    }
end

-- ── 1. heap: lowest f first, ties by h, every entry pops exactly once ───────
local h = {}
SpudPath.heapPush(h, { f = 5, h = 0, k = 1 })
SpudPath.heapPush(h, { f = 3, h = 2, k = 2 })
SpudPath.heapPush(h, { f = 9, h = 0, k = 9 })
SpudPath.heapPush(h, { f = 3, h = 1, k = 3 })
local order = {}
while #h > 0 do local e = SpudPath.heapPop(h); order[#order + 1] = e.k end
check("heap: lowest f first, ties by lower h",
    #order == 4 and order[1] == 3 and order[2] == 2 and order[3] == 1 and order[4] == 9,
    table.concat(order, ","))

-- ── 2. A* on open ground: the straight diagonal, no detour ──────────────────
local m = map(10, 10)
local path, st = SpudPath.astar(opts(m, 0, 0, 9, 9))
check("A* open grid: path found", path ~= nil and #path > 0)
check("A* open grid: diagonal length, no detour", path and #path == 10,
    path and #path or "nil")
check("A* open grid: every cell free", path and pathFree(m, path))
check("A* open grid: bounded expansions", st and st.pops > 0 and st.pops < 100,
    st and (st.pops .. " pops") or "nil")

-- ── 3. A* wall: it finds the gap instead of giving up ───────────────────────
local walls = {}
for iz = 0, 8 do walls[#walls + 1] = { 5, iz } end
m = map(12, 12, walls)
path, st = SpudPath.astar(opts(m, 1, 1, 10, 1))
local throughGap = false
for _, p in ipairs(path or {}) do
    if p[1] == 5 and p[2] >= 9 then throughGap = true end
end
check("A* wall: path found through the gap", path ~= nil and throughGap,
    path and (#path .. " cells") or "nil")
check("A* wall: no corner cutting", path and noCornerCut(m, path))

-- ── 4. A* with no route says so ─────────────────────────────────────────────
walls = {}
for iz = 0, 7 do walls[#walls + 1] = { 4, iz } end
m = map(8, 8, walls)
path, st = SpudPath.astar(opts(m, 0, 0, 7, 7))
check("A* sealed wall: nil path, honest stats", path == nil and st and st.pops > 0,
    path and "path?!" or (st and (st.pops .. " pops") or "no stats"))

-- ── 5. exact traversal: a thin wall on the line is seen ─────────────────────
m = map(20, 20)
local ok = SpudPath.los(m, 0.5, 0.5, 10.5, 10.5, 0)
check("LOS: open line is clear", ok)
m = map(20, 20, { { 5, 5 } })
ok = SpudPath.los(m, 0.5, 0.5, 10.5, 10.5, 0)
check("LOS: a single blocked cell on the line is seen", not ok)

-- ── 6. clearance: a line one cell from a wall is refused when asked ─────────
walls = {}
for iz = 0, 9 do walls[#walls + 1] = { 1, iz } end
m = map(12, 12, walls)
local okHug = SpudPath.los(m, 0.5, 0.5, 0.5, 9.5, 0)
local okSafe = SpudPath.los(m, 0.5, 0.5, 0.5, 9.5, 2)
check("LOS: hugging the wall is allowed at clearance 0", okHug)
check("LOS: the same line is refused at clearance 2", not okSafe)

-- ── 7. Lazy Theta*: any-angle, shorter than 8-way, still clear ──────────────
m = map(20, 20)
local tpath, tst = SpudPath.thetastar(opts(m, 1, 1, 18, 18))
check("Theta* open grid: one straight edge", tpath and #tpath <= 3,
    tpath and (#tpath .. " point(s)") or "nil")
check("Theta* open grid: every point free", tpath and pathFree(m, tpath))

walls = {}
for iz = 0, 14 do walls[#walls + 1] = { 10, iz } end
m = map(22, 22, walls)
local apath = SpudPath.astar(opts(m, 2, 2, 19, 2))
tpath = SpudPath.thetastar(opts(m, 2, 2, 19, 2))
local alen = apath and cellLen(apath) or 0
local tlen = tpath and cellLen(tpath) or 0
check("Theta* wall: path found and clear", tpath ~= nil and pathFree(m, tpath))
check("Theta* wall: any-angle is not longer than 8-way", tpath ~= nil and apath ~= nil
    and tlen <= alen + 0.001,
    string.format("theta %.2f vs a* %.2f", tlen, alen))

-- ── 8. smoothing: corners become arcs, and stay out of the gear ─────────────
m = map(60, 60)
local ctx = { cell = 1, x0 = 0, z0 = 0, nx = 60, nz = 60, blocked = m.blocked,
    clear = m.clear, arcMargin = 1, maxCurv = 0.2 }
local out, minC = SpudPath.smooth({ { 2.5, 2.5 }, { 30.5, 2.5 }, { 30.5, 30.5 } }, ctx)
check("smooth: the corner is an arc, not one vertex", out and #out > 3,
    out and (#out .. " point(s)") or "nil")
local allFree, allClear = true, true
for i = 2, #out - 1 do
    if clearAt(ctx, out[i][1], out[i][2]) < 0 then allFree = false end
    if clearAt(ctx, out[i][1], out[i][2]) < 1 then allClear = false end
end
check("smooth: every arc sample is on free ground", allFree)
check("smooth: the arc keeps its clearance margin", allClear and (minC or 0) >= 1,
    tostring(minC))
check("smooth: start and goal are preserved",
    out[1][1] == 2.5 and out[1][2] == 2.5
    and out[#out][1] == 30.5 and out[#out][2] == 30.5)

-- ...a wall inside the corner: the big arc must be refused (the samples may
-- not pass within `arcMargin` cells), even if the vertex stays sharp
walls = {}
for iz = 3, 12 do walls[#walls + 1] = { 15, iz } end
m = map(30, 30, walls)
ctx = { cell = 1, x0 = 0, z0 = 0, nx = 30, nz = 30, blocked = m.blocked,
    clear = m.clear, arcMargin = 2, maxCurv = 0.2 }
-- the corner sits two cells off the wall: an arc bulging toward it enters the
-- one-cell gap and must be refused
out = SpudPath.smooth({ { 5.5, 7.5 }, { 13.5, 7.5 }, { 13.5, 20.5 } }, ctx)
local safe = true
for i = 2, #out - 1 do
    local c = clearAt(ctx, out[i][1], out[i][2])
    if c < 0 or c < 2 then safe = false end
end
check("smooth: an arc that would swing into the wall is refused", safe,
    out and (#out .. " point(s)") or "nil")

-- ── 9. curvature limit: no arc tighter than asked, sharp vertex otherwise ───
m = map(60, 60)
ctx = { cell = 1, x0 = 0, z0 = 0, nx = 60, nz = 60, blocked = m.blocked,
    clear = m.clear, arcMargin = 1, maxCurv = 0.08 }
out = SpudPath.smooth({ { 2.5, 2.5 }, { 40.5, 2.5 }, { 40.5, 40.5 } }, ctx)
local worst = 0
for i = 2, #out - 1 do
    worst = math.max(worst, curvatureOf(out[i - 1], out[i], out[i + 1]))
end
check("smooth: curvature stays under the limit", worst <= 0.09,
    string.format("max %.3f rad/stud", worst))

ctx.maxCurv = 0.001 -- nothing can pass: the sharp vertex is kept
out = SpudPath.smooth({ { 2.5, 2.5 }, { 40.5, 2.5 }, { 40.5, 40.5 } }, ctx)
check("smooth: when no arc fits, the vertex stays sharp", out and #out == 3,
    out and (#out .. " point(s)") or "nil")

-- ── 10. height: a roof/pipes above the ride do not block the ground ─────────
m = map(20, 20)
local n = SpudPath.markParts({ { part = fakePart(10.5, 30, 10.5, 2, 2, 2), owner = "roof" } },
    0, 0, 20, 20, 1, m.blocked, nil, nil, 0, -1, 12)
check("mark: a part above the ride marks nothing", n == 0 and m.blocked[key(10, 10)] == nil,
    n .. " marked")

m = map(20, 20)
n = SpudPath.markParts({ { part = fakePart(10.5, 0, 10.5, 2, 2, 2), owner = "shed" } },
    0, 0, 20, 20, 1, m.blocked, nil, nil, 0, -1, 12)
check("mark: a part in the ride's band blocks its ground", n == 1 and m.blocked[key(10, 10)] == true,
    n .. " marked")

m = map(20, 20)
n = SpudPath.markParts({ { part = fakePart(10.5, -20, 10.5, 2, 2, 2), owner = "buried" } },
    0, 0, 20, 20, 1, m.blocked, nil, nil, 0, -1, 12)
check("mark: a buried part marks nothing", n == 0 and m.blocked[key(10, 10)] == nil,
    n .. " marked")

m = map(20, 20)
n = SpudPath.markParts({ { part = fakePart(10.5, 0, 10.5, 2, 2, 2), owner = "me" } },
    0, 0, 20, 20, 1, m.blocked, "me", nil, 0, -1, 12)
check("mark: the ride's own parts are ignored", n == 0 and m.blocked[key(10, 10)] == nil,
    n .. " marked")

-- ── 11. cell size follows trip length, and stays fine on long hauls ─────────
check("cell: short trip keeps 6-stud cells", SpudPath.cellSize(100) == 6,
    tostring(SpudPath.cellSize(100)))
check("cell: 700 studs is 10", SpudPath.cellSize(700) == 10,
    tostring(SpudPath.cellSize(700)))
check("cell: long haul caps at 16, not 24", SpudPath.cellSize(2000) == 16,
    tostring(SpudPath.cellSize(2000)))

-- ── 12. key round-trip (the old grid's encoding) ────────────────────────────
local kx, kz = SpudPath.unkey(SpudPath.key(17, 4))
check("key: ix/iz round-trip", kx == 17 and kz == 4, kx .. "," .. kz)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


def extract_module(text: str) -> str:
    a = text.find(START)
    b = text.find(END)
    if a < 0 or b < 0 or b <= a:
        return ""
    return text[a:b].strip() + "\n"


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    module = extract_module(src)
    if not module:
        print("missing SPUD PATH MODULE markers in SpudFarm_Full.lua")
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
