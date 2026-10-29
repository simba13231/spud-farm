"""Should a full harvester go and sell? (spudSellNow)

The real drop-off is the Fulfillment building next to Shipment, and its pad /
lever has not been probed yet. Until it is, a full tank must STOP the run
instead of driving to a guessed pad and wasting the pass (user: "once the
harvester is full just make it stop because we dont have the spot yet").

`spudSellWired` is the switch: false today, true in the change that learns the
Fulfillment spot. `spudSellNow(cur, max)` answers the gate:

    python tools/sell_gate_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"
WANTED = ["spudSellNow"]


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
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

-- 1. today: the drop-off is not wired, so a full tank never sells
spudSellWired = false
check("unwired: a full tank does not sell", spudSellNow(50, 50) == false)
check("unwired: an over-full tank does not sell", spudSellNow(60, 50) == false)

-- 2. once wired: full sells, not-full does not
spudSellWired = true
check("wired: a full tank sells", spudSellNow(50, 50) == true)
check("wired: an over-full tank sells", spudSellNow(60, 50) == true)
check("wired: a half tank does not sell", spudSellNow(25, 50) == false)
check("wired: unreadable load does not sell", spudSellNow(nil, nil) == false)
check("wired: zero capacity does not sell", spudSellNow(0, 0) == false)

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
