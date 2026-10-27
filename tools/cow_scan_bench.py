"""Measure the cow reads that a scan pays, before and after the cache.

A scan (milkCows) reads three things off every animal in the world: its Owner
(walking parents until a Configurations.Owner appears), its Production value and
its AnimoidState. The owner walk is the expensive one and it used to run again
for every animal, every scan - and the arrival wait scanned five times a second.

This runs the REAL milkOwnerOf / milkPercentOf / milkStateOf out of
SpudFarm_Full.lua against a fake world of 120 cow models and counts every
instance call (FindFirstChild / IsA / GetAttribute), twice: a cold pass (no
cache) and a warm pass (the cache the script keeps between scans).

Usage:  python tools/cow_scan_bench.py [path-to-luau.exe] [git-ref]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

WANTED = ["milkOwnerOf", "milkPercentOf", "milkStateOf"]

PRE = r"""
OPS = 0
local function bump() OPS = OPS + 1 end

milkCowFast = {
    prod = setmetatable({}, { __mode = "k" }),
    state = setmetatable({}, { __mode = "k" }),
    owner = setmetatable({}, { __mode = "k" }),
}

local function value(cls, v)
    local o = { Value = v, Parent = nil }
    function o:IsA(c) bump() return c == cls end
    function o:GetAttribute() bump() return nil end
    function o:FindFirstChild() bump() return nil end
    return o
end

local function node(name, kids, cls)
    local o = { Name = name, Parent = nil, kids = kids or {}, cls = cls or "Model" }
    function o:FindFirstChild(n)
        bump()
        local c = self.kids[n]
        if c then c.Parent = self end
        return c
    end
    function o:GetAttribute() bump() return nil end
    function o:IsA(c) bump() return c == self.cls end
    function o:GetPivot() return { Position = { X = 0, Y = 0, Z = 0 } } end
    return o
end

-- a cow exactly as the dump has it: Configurations.{Production, AnimoidState,
-- Owner}. An animal with NO Owner value is the expensive case: the owner read
-- walks up parent by parent looking for a Configurations.Owner that is not
-- there, so the model sits inside a realistic parent chain.
local function cow(ownerName, parked)
    local conf = node("Configurations", {
        Production = value("NumberValue", 300),
        AnimoidState = value("StringValue", parked and "IdleLocked" or "Wander"),
        Owner = value("ObjectValue", ownerName and { Name = ownerName } or nil),
    })
    local model = node("Cow", { Configurations = conf })
    local holder = node("Animals", { [model.Name] = model })
    model.Parent = holder
    holder.Parent = node("Fence", {})
    holder.Parent.Parent = node("Plots", {})
    holder.Parent.Parent.Parent = node("Workspace", {})
    return model
end
"""

POST = r"""
local cows = {}
for i = 1, 120 do
    -- 40 tagged animals (the farm's own cows and other players'), 80 untagged
    -- strays - the ones that pay the full 8-level owner walk every scan
    cows[i] = cow(i % 3 == 0 and "Simba" or nil, i % 4 == 0)
end

-- exactly the per-cow work a scan does, in the order milkCows does it
local function scan(list)
    local mine = 0
    for _, m in ipairs(list) do
        local who = milkOwnerOf(m)
        local pct = milkPercentOf(m)
        local st = milkStateOf(m)
        if who == "Simba" and pct and st then mine = mine + 1 end
    end
    return mine
end

OPS = 0
local mine = scan(cows) -- cold: the cache is empty
local cold = OPS
OPS = 0
scan(cows)
local warm1 = OPS
OPS = 0
scan(cows)
local warm2 = OPS
print(string.format("1st scan (cold): %5d ops (%5.1f per cow) -> %d cows matched", cold, cold / 120, mine))
print(string.format("2nd scan (warm): %5d ops (%5.1f per cow)", warm1, warm1 / 120))
print(string.format("3rd scan (warm): %5d ops (%5.1f per cow)", warm2, warm2 / 120))
"""


def extract(text: str) -> str:
    """The three read functions with their indentation stripped."""
    out = []
    for name in WANTED:
        m = re.search(r"^    local function " + name + r"\(", text, re.M)
        if not m:
            raise SystemExit("could not find " + name)
        tail = text[m.start():]
        end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
        block = tail[: end.start() + 10] if end else tail
        out.append("\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines()))
    return "\n\n".join(out)


def run(exe, label, src, tmpdir):
    if not src:
        print(label + ": no source")
        return
    path = tmpdir / (re.sub(r"\W+", "_", label) + ".lua")
    path.write_text(PRE + extract(src) + POST, encoding="utf-8")
    out = subprocess.run([str(exe), str(path)], capture_output=True,
                         encoding="utf-8", errors="replace")
    print("=== " + label + " ===")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip())


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    before = subprocess.run(["git", "show", ref + ":SpudFarm_Full.lua"], cwd=ROOT,
                            capture_output=True, encoding="utf-8", errors="replace").stdout
    with tempfile.TemporaryDirectory() as td:
        tmpdir = pathlib.Path(td)
        run(exe, "before " + ref, before, tmpdir)
        run(exe, "now (cached)", SRC.read_text(encoding="utf-8"), tmpdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
