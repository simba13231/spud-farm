"""Which fields the crop harvester may drive on (spudTreeField / spudNoCells).

Reported: "it's trying to harvest my trees but i don't want to". The harvest
job counts ANY cell stage it does not recognise as "a crop is standing", so a
tree/wood soil field is driven over and the harvester cuts the trees.

Two rules are pinned here:
  * a field whose type/name says wood/tree/log/forest/timber/lumber is never a
    crop-harvest target;
  * a field whose cell read SUCCEEDS but returns zero cells is empty, not
    unreadable - it is skipped. A FAILED read (nil) is still "unknown" and must
    never be used to skip work (owner rule 7).

    python tools/field_soil_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

WANTED = ["spudTreeField", "spudNoCells"]


def extract(text: str, name: str) -> str:
    m = re.search(r"^    (?:local )?function " + name + r"\(", text, re.M)
    if not m:
        return ""
    tail = text[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    return "\n".join(l[4:] if l.startswith("    ") else l for l in block.splitlines())


POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-56s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- ── 1. tree/wood soil is never a crop-harvest target ───────────────────────
for _, t in ipairs({ "Wood", "wood", "TREE", "Timber", "Forest", "Lumber",
                     "Log", "TreeField", "Sawmill" }) do
    check("tree type '" .. t .. "' is recognised", spudTreeField(t) ~= nil,
        tostring(spudTreeField(t)))
end
check("type+name: a wood type is recognised", spudTreeField("Field", "WoodSoil") ~= nil)
check("type+name: a wood model name is recognised", spudTreeField("Field", "PineTrees") ~= nil)

for _, t in ipairs({ "Field", "Trellis", "Crop", "?", "", nil }) do
    check("crop type '" .. tostring(t) .. "' is not tree soil", spudTreeField(t) == nil,
        tostring(spudTreeField(t)))
end
check("normal field with no wood in its name stays a crop",
    spudTreeField("Field", "Field") == nil)

-- ── 2. empty is not unreadable ─────────────────────────────────────────────
check("a successful read with 0 cells is empty", spudNoCells({ total = 0 }) == true)
check("a field with cells is not empty", spudNoCells({ total = 12 }) == false)
check("a failed read (nil) is NOT empty", spudNoCells(nil) == false)
check("a stage table without total is not treated as empty", spudNoCells({ Empty = 3 }) == false)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
"""


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
        fh.write("\n\n".join(parts) + "\n" + POST)
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
