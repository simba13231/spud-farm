"""Run the REAL setHookURL: is a webhook URL a Discord one, or just "contains discord"?

The old check accepted any URL containing the substring "discord", and the box
mirrors the whole console into whatever it is given. This asserts the strict
host + /api/webhooks/ path rule, and that a blank value still means "off".

    python tools/webhook_test.py [path-to-luau.exe]
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

PRE = r"""
hookURL, hookFails, hookHealthy, hookQueue = "", 0, true, {}
hookSaveURL = function() end
log = function() end
"""

POST = r"""
local fails = 0
local function check(name, ok, detail)
    if not ok then fails = fails + 1 end
    print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
        detail and ("  " .. detail) or ""))
end

local function verdict(u)
    local ok = setHookURL(u)
    return ok, hookURL
end

local good = {
    "https://discord.com/api/webhooks/123/abc",
    "https://discordapp.com/api/webhooks/123/abc",
    "https://ptb.discord.com/api/webhooks/123/abc",
    "https://canary.discordapp.com/api/webhooks/123/abc",
}
for _, u in ipairs(good) do
    local ok, stored = verdict(u)
    check("accepts " .. u:gsub("^https://", ""), ok == true and stored == u, tostring(stored))
end

local bad = {
    "https://evil.com/discord.com/api/webhooks/1",
    "https://discord.com.evil.com/api/webhooks/1",
    "https://discord.com/notwebhooks/1",
    "http://discord.com/api/webhooks/1",
    "nonsense",
}
for _, u in ipairs(bad) do
    hookURL = ""
    local ok = verdict(u)
    check("rejects " .. u, ok == false and hookURL == "", tostring(ok))
end

local ok = verdict("")
check("blank turns it off", ok == true and hookURL == "", tostring(hookURL))

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
"""


def main() -> int:
    base = pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau"
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else base / "luau.exe"
    src = SRC.read_text(encoding="utf-8")
    m = re.search(r"^    local function setHookURL\(", src, re.M)
    if not m:
        print("setHookURL not found")
        return 2
    tail = src[m.start():]
    end = re.search(r"\n    (?:local function |function |-- )", tail[10:])
    block = tail[: end.start() + 10] if end else tail
    lua = "\n".join(line[4:] if line.startswith("    ") else line for line in block.splitlines())
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
        fh.write(PRE + "\n" + lua + "\n" + POST)
        path = fh.name
    out = subprocess.run([str(exe), path], capture_output=True, encoding="utf-8", errors="replace")
    print(out.stdout.strip())
    if out.returncode != 0:
        print(out.stderr.strip()[-1200:])
    return out.returncode


if __name__ == "__main__":
    raise SystemExit(main())
