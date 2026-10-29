"""Old A* vs the new engine on the same synthetic maps.

The old `astarPath` is pulled out of git HEAD (the linear min-scan open list
with table.remove), the new SpudPath block out of the working tree. Both run
under the real Luau interpreter on identical blocked/clearance arrays, so the
numbers are the shipped algorithms, not a re-implementation.

    python tools/path_bench.py [path-to-luau.exe] [git-ref]

Reports best-of-8 wall time, path cells, geometric length and (new only)
expansions. This is a measurement tool, not a gate (run_all.py does not run it).
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
local function key(ix, iz) return ix * 100000 + iz end

local function makeMap(nx, nz, kind)
    local blocked = {}
    if kind == "clutter" then
        local seed = 48271
        for ix = 0, nx - 1 do
            for iz = 0, nz - 1 do
                seed = (seed * 48271) % 2147483647
                if seed % 100 < 12 then blocked[key(ix, iz)] = true end
            end
        end
    elseif kind == "walls" then
        for iz = 0, nz - 1 do
            for _, wx in ipairs({ 10, 25, 40, 55 }) do
                if iz % 17 ~= 0 and wx < nx then blocked[key(wx, iz)] = true end
            end
        end
    elseif kind == "diag" then
        for i = 5, math.min(nx, nz) - 5 do
            blocked[key(i, i)] = true
            if i + 2 < nz then blocked[key(i, i + 2)] = true end
        end
    end
    local function clearAt(ix, iz)
        for dx = -2, 2 do
            for dz = -2, 2 do
                blocked[key(ix + dx, iz + dz)] = nil
            end
        end
    end
    clearAt(1, 1)
    clearAt(nx - 2, nz - 2)
    return blocked
end

local function lenOf(path)
    local d = 0
    for i = 2, #(path or {}) do
        local dx, dz = path[i][1] - path[i - 1][1], path[i][2] - path[i - 1][2]
        d = d + math.sqrt(dx * dx + dz * dz)
    end
    return d
end

local function bench(times, fn)
    local best, out = math.huge, nil
    for _ = 1, times do
        local t0 = os.clock()
        out = fn()
        local dt = (os.clock() - t0) * 1000
        if dt < best then best = dt end
    end
    return best, out
end

print(string.format("%-10s %-8s %10s %8s %8s %8s",
    "map", "engine", "best ms", "cells", "length", "pops"))
print(string.rep("-", 62))

local maps = {
    { name = "open", nx = 60, nz = 60, kind = "open" },
    { name = "clutter", nx = 120, nz = 120, kind = "clutter" },
    { name = "walls", nx = 80, nz = 80, kind = "walls" },
    { name = "diag", nx = 80, nz = 80, kind = "diag" },
}

local failures = 0
for _, spec in ipairs(maps) do
    local nx, nz = spec.nx, spec.nz
    local blocked = makeMap(nx, nz, spec.kind)
    local clear = SpudPath.clearance(nx, nz, blocked)
    local sx, sz, gx, gz = 1, 1, nx - 2, nz - 2

    local ms, oldPath = bench(8, function()
        return astarPath(1, nx, nz, blocked, clear, sx, sz, gx, gz)
    end)
    if not oldPath then failures = failures + 1 end
    print(string.format("%-10s %-8s %10.2f %8s %8.1f %8s",
        spec.name, "old a*", ms, oldPath and #oldPath or "nil",
        oldPath and lenOf(oldPath) or 0, "-"))

    local ams, apath, ast = bench(8, function()
        local p, st = SpudPath.astar({ nx = nx, nz = nz, blocked = blocked,
            clear = clear, sx = sx, sz = sz, gx = gx, gz = gz })
        return p, st
    end)
    -- bench() keeps the last return only; re-run once for stats
    local _, astats = SpudPath.astar({ nx = nx, nz = nz, blocked = blocked,
        clear = clear, sx = sx, sz = sz, gx = gx, gz = gz })
    print(string.format("%-10s %-8s %10.2f %8s %8.1f %8d",
        spec.name, "new a*", ams, apath and #apath or "nil",
        apath and lenOf(apath) or 0, astats and astats.pops or 0))

    local tms, tpath = bench(8, function()
        local p = SpudPath.thetastar({ nx = nx, nz = nz, blocked = blocked,
            clear = clear, sx = sx, sz = sz, gx = gx, gz = gz })
        return p
    end)
    local _, tstats = SpudPath.thetastar({ nx = nx, nz = nz, blocked = blocked,
        clear = clear, sx = sx, sz = sz, gx = gx, gz = gz })
    print(string.format("%-10s %-8s %10.2f %8s %8.1f %8d",
        spec.name, "theta*", tms, tpath and #tpath or "nil",
        tpath and lenOf(tpath) or 0, tstats and tstats.pops or 0))
    print("")
end

print(failures == 0 and "ALL MAPS SOLVED" or (failures .. " OLD RUN(S) FAILED"))
"""


def extract_module(text: str) -> str:
    a, b = text.find(START), text.find(END)
    if a < 0 or b <= a:
        return ""
    return text[a:b].strip() + "\n"


def dedent(block: str) -> str:
    return "\n".join(line[4:] if line.startswith("    ") else line
                     for line in block.splitlines())


def extract_old(text: str) -> str:
    m = re.search(r"^    local function astarPath\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return dedent(block)


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    module = extract_module(SRC.read_text(encoding="utf-8"))
    old_src = subprocess.run(["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT,
                             capture_output=True, encoding="utf-8",
                             errors="replace").stdout
    old = extract_old(old_src)
    if not module:
        print("missing SPUD PATH MODULE")
        return 2
    if not old:
        print("could not extract the old astarPath from " + ref)
        return 2
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False,
                                     encoding="utf-8") as fh:
        fh.write(module + "\n" + old + "\n" + POST)
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
