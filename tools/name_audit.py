"""Find top-level name collisions in SpudFarm_Full.lua (the 200-local wall).

Every feature that needs a register is converted from `local` to a global so the
build closure stays under Luau's 200-local limit. The catch: a bare global
assignment silently CLOBBERS whatever already held that name. That is exactly
how `function milkDrops(...)` (the jug counter) overwrote `milkDrops = {}` (the
three farm dropdowns) - every later `milkDrops[slot]` then indexed a function.

This scans the top level of the build closure (4-space indentation) and reports
any name that is assigned more than once in a way a global would clobber.

    python tools/name_audit.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SpudFarm_Full.lua"

PATTERNS = [
    # (regex, kind, is_local)
    (re.compile(r"^    function ([A-Za-z_]\w*)\s*\("), "function", False),
    (re.compile(r"^    local function ([A-Za-z_]\w*)\s*\("), "local function", True),
    (re.compile(r"^    ([A-Za-z_]\w*)\s*=(?!=)"), "global", False),
    (re.compile(r"^    local ([A-Za-z_]\w*)\s*=(?!=)"), "local", True),
]

COUNTER = re.compile(r"^    [A-Za-z_]\w*\s*(\+=|-=|\*=|/=)")


def main() -> int:
    lines = SRC.read_text(encoding="utf-8").splitlines()
    seen: dict[str, list[tuple[int, str, bool]]] = {}
    counters: dict[str, list[int]] = {}

    for n, line in enumerate(lines, 1):
        for pat, kind, is_local in PATTERNS:
            m = pat.match(line)
            if m:
                seen.setdefault(m.group(1), []).append((n, kind, is_local))
                break
        m = COUNTER.match(line)
        if m:
            counters.setdefault(m.group(0).split("=")[0].strip(), []).append(n)

    bad = []
    for name, hits in sorted(seen.items()):
        globals_ = [h for h in hits if not h[2]]
        if not globals_:
            continue
        # a global assigned more than once is a clobber; so is a global whose
        # name is also declared local at top level (the local only shadows
        # AFTER its declaration, so the global can still be hit by earlier code)
        if len(globals_) > 1 or len(hits) > 1:
            bad.append((name, hits))

    # +=/-= on a name that is declared `local` in this scope is fine; on an
    # undeclared name it is a global that other builds also touch.
    for name, where in sorted(counters.items()):
        if name not in seen:
            bad.append((name, [(w, "undeclared counter", False) for w in where]))

    if not bad:
        print(f"name audit: clean ({len(seen)} top-level names)")
        return 0

    print(f"name audit: {len(bad)} name(s) assigned more than once at the top level")
    for name, hits in bad:
        print(f"  {name}: " + " · ".join(f"line {n} {kind}" for n, kind, _ in hits))
    return 1


if __name__ == "__main__":
    sys.exit(main())
