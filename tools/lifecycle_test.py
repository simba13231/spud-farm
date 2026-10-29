"""Run the REAL session-token block: do old loops stop on Unload / Reload?

Unload used to leave the milk loop, the delivery loop, the webhook pump, the
field scan and the FPS meter running with no UI; every Reload stacked another
copy of each. The fix is a generation counter plus a per-build `spudAlive`.

This slices the real block out of SpudFarm_Full.lua and simulates builds, so it
also catches the trap the naive fix had: a GLOBAL spudAlive would be overwritten
by the next build and old loops would read the new build's token as "alive".

    python tools/lifecycle_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

TOKEN = re.compile(
    r"(?m)^    spudGen = \(spudGen or 0\) \+ 1\n"
    r"    local myGen = spudGen\n"
    r"(?:    --.*\n)*"
    r"    local function spudAlive\(\) return spudGen == myGen end\n"
)

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-56s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- a fake long-lived loop: ticks while its own build is alive
local function loop(buildAlive)
    return function(limit)
        local n = 0
        while n < limit and buildAlive() do n += 1 end
        return n
    end
end

local a = newBuild()
check("the first build is alive", a() == true)
local b = newBuild()
check("the second build is alive", b() == true)
check("a rebuild stops the old build", a() == false and b() == true)

-- a real loop from the OLD build must stop at its next tick
local oldLoop = loop(a)
local ticks = oldLoop(1000)
check("an old loop stops instead of spinning", ticks == 0, "ticks " .. ticks)

-- Unload: bump the generation, everything from this build stops
spudGen = spudGen + 1
check("unload stops the current build", b() == false)
local liveLoop = loop(b)
ticks = liveLoop(1000)
check("the unloaded loop stops too", ticks == 0, "ticks " .. ticks)

-- Reload after Unload: a fresh build runs, and nothing old comes back
local c = newBuild()
check("a build after unload is alive", c() == true)
check("pre-unload builds stay dead", a() == false and b() == false)
check("the previous build's loops stay dead", loop(b)(10) == 0)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
"""


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    m = TOKEN.search(src)
    if not m:
        print("session-token block not found in SpudFarm_Full.lua")
        return 2
    block = "\n".join(line[4:] if line.startswith("    ") else line
                     for line in m.group(0).splitlines())
    lua = ("local function newBuild()\n" + block + "\n    return spudAlive\nend\n\n" + POST)
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(lua)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1200:])
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
