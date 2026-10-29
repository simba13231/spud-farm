"""One gate for the whole script: compile, register budget, name audit, every
harness, and the doctor report.

The hand-run suite had already missed `test_doctor.py` once (it does not match
`*_test.py`), and the name audit exists because a "make it global to save a
register" edit silently clobbered a table. This runs all of it in one command:

    python tools/run_all.py [folder-with-luau.exe]
"""

import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
    pathlib.Path(os.environ.get("LOCALAPPDATA", ".")) / "Temp" / "opencode" / "luau")
EXE = BASE / "luau.exe"
COMPILE = BASE / "luau-compile.exe"


def run(label: str, cmd: list[str]) -> bool:
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace")
    text = out.stdout + out.stderr
    # the harnesses print PASS/FAIL and mostly exit 0, so a return code alone
    # would call a failing suite "OK"
    ok = out.returncode == 0 and "FAIL" not in out.stdout
    print(f"{'OK  ' if ok else 'FAIL'} {label}")
    if not ok:
        print(text.strip())
    return ok


def main() -> int:
    if not EXE.exists() or not COMPILE.exists():
        print(f"luau tools not found under {BASE}")
        print("pass the folder as the first argument (it needs luau.exe and luau-compile.exe)")
        return 2

    checks = [
        ("compile SpudFarm_Full.lua", [str(COMPILE), "--binary", "SpudFarm_Full.lua"]),
        ("register budget", [sys.executable, "tools/local_budget.py"]),
        ("name audit", [sys.executable, "tools/name_audit.py"]),
    ]
    tests = sorted((ROOT / "tools").glob("*_test.py"))
    tests.append(ROOT / "tools" / "test_doctor.py")  # named differently on purpose
    for t in tests:
        checks.append((t.name, [sys.executable, str(t), str(EXE)]))

    results = [run(label, cmd) for label, cmd in checks]
    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
