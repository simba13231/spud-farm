# SPUD FARM — the one-file brief

Everything an agent (or a person) needs before touching this repo: the owner's
rules, the game facts we have actually **verified**, the history of what was
asked and fixed, and the exact loop to prove a change works.

**Read this file first. Then read [README.md](README.md)** for the user-facing
description — it is the long-form manual and it is kept in sync with behaviour.

- Main script: [SpudFarm_Full.lua](SpudFarm_Full.lua) — one paste-and-run Luau
  file for the Roblox game *Farming and Friends*, currently `rebuild v1.27 ·
  fluent gui` (`VERSION`, line 9). ≈11.4k lines.
- Target: Windows + Git Bash. Luau toolchain lives in
  `%LOCALAPPDATA%\Temp\opencode\luau\` (`luau.exe`, `luau-compile.exe`,
  `luau-analyze.exe`).
- Nothing here is a library or a build system. There is no bundler, no package
  manager, no CI. Validation is a compile check plus eighteen harness scripts in
  `tools/` (`python tools/run_all.py` runs the whole gate).

---

## 1. The owner's rules (non-negotiable)

### 1.1 UI

1. **No text under anything.** Every element gets a **title only**: no window
   subtitle, no description line under a button/toggle, no helper text, no
   placeholder sub-text. This applies to every future feature. (Recorded in the
   README as rule #1 and it has been violated and re-fixed before.)
2. **The window must stay comfortably large** on mobile/emulator screens:
   `Resize = true` and a generous base `Size`.
3. The HUD pattern is fixed: **RIGHT SHIFT** toggles the menu, **📡** opens the
   webhook window, **🥔** (draggable, left edge) hides/shows every window and
   stays visible while the rest is hidden.

### 1.2 Never guess a game field

4. **Probe before implementing.** If a behaviour depends on a live game
   structure, run the matching read-only probe and paste its report; do not
   invent a path, attribute or remote name. The probes exist precisely because
   guesses were wrong: the documented `Spots.<n>.Filth` shape was **not** what
   one live build exposed.
5. **Probes are read-only.** A probe presses nothing, teleports nothing, writes
   nothing. The only exceptions are the scripts that are *about* writing
   (`SpudFarm_Full.lua`) and the remote probe's own stop/upload buttons.
6. **Never derive "clean" from a trip.** Asking "is this stall dirty?" must be a
   read you can do **from where the character stands**. The teleport tour (visit
   all twelve) cost 12 hops / 6.00 s per pass on a clean barn and is banned.
7. **Unreadable is not empty.** An unreadable farm is not `0 cows`; an
   unreadable stall is not `clean`; a streamed-out plot is not `no farm`.
   Unreadable means: name it in the log, make no decision that depends on it,
   never teleport on the guess.

### 1.3 Timing and motion

8. **Wait on the game's own signal**, not a flat sleep. A clean takes ~**2 s**
   in this game (owner's number), so the script watches the Clean offer switch
   off rather than sleeping a guessed 0.96 s and pressing mid-clean.
9. **`task.wait(t)` is frame-quantised** — it sleeps *at least* `t` and resumes
   on the next Heartbeat, so at 60 FPS `task.wait(0.2)` costs 200–216 ms. Do not
   build stand-still loops out of it.
10. **Poll at the frequency the read deserves**: every frame only when the read
    is a cheap property that the game already updates (jug left the world, hand
    filled, tank label). **50 ms** for GUI-shaped reads (`milkMenuFor`,
    `milkStallGui`). `milkDrops` walks a world folder, so it is read at **4 Hz**
    (250 ms), only counts jugs near the stall being milked, and never per frame.
11. **A CFrame teleport needs ~50 ms to reach the server** (physics replication
    ~20 Hz): wait three frames after one, not 150–250 ms.
12. **No teleport just to look.** A hop is for an action the script is about to
    take, and only when the action is not already offered where it stands.

### 1.4 Script limits (these have broken the build before)

13. **Luau's 200-local limit is real and we are 2 away from the practical
    ceiling.** Run `python tools/local_budget.py`. As of v1.27:
    `4-space locals before milkCycle: 183 (practical ceiling 185)`,
    whole body `190 / 200`, **headroom 2**. Do **not** add a `local` inside the
    main build closure. Reuse an existing local, convert the feature to a
    **global** (the established pattern), or restructure — and re-run the budget.
14. **A bare global assignment silently clobbers.** That is exactly how
    `function milkDrops(...)` overwrote `milkDrops = {}` (the three farm
    dropdowns), so every later `milkDrops[slot]` indexed a function. Run
    `python tools/name_audit.py` before/after adding any global.
15. **The file must load first try.** A syntax error means the user sees a
    dead script; `SpudBoot.lua` exists so the error is at least visible.

### 1.5 Scope and process

16. **Do what was asked, nothing more.** No unrequested refactors, features,
    dependencies or polish. A bug report gets a fix, not a redesign.
17. **The version string and the README move with behaviour.** Bump
    `VERSION` (`rebuild vX.YY · fluent gui`) and update the affected README
    paragraph in the same change. Commits are focused and message-first, e.g.
    `Keep cows out of dirty stalls and clean above the meter's clean baseline`.
18. **Never claim in-game verification you did not do.** "Harness green" and
    "tested in game" are different statements. Say which one it is.
19. **One barn per farm per session.** When a plot has more than one barn, the
    first cycle locks one (nearest the plot centre) and it is held as
    **name + position**, never as the model instance (a streamed-out barn
    returns as a *new* instance). Falling back to "the first model named
    `AutoWoodenBarn` in the map" herds other players' cows into the wrong barn —
    that was a real bug.
20. **Never put a cow into a stall that reports dirt.** The cleaner and the herd
    gate must read dirt the same way, or they disagree about what "dirty" means.

### 1.6 Working tree state (read before editing)

`HEAD` is the latest committed build (v1.27, owner-first equipment), `main`
tracks `origin/main`, and the tree is clean. Keep it that way: make the change,
run the gates, and commit only the files the change touches. `git add -A` is
banned here. Do not commit or push unless asked.

---

## 2. The verification loop

### 2.1 Compile

```bash
LC="$LOCALAPPDATA/Temp/opencode/luau"
"$LC/luau-compile.exe" --binary SpudFarm_Full.lua > /dev/null && echo "SYNTAX OK"
```

### 2.2 The full suite

```bash
for t in tools/*_test.py; do
  printf '%-30s ' "$(basename "$t")"
  PYTHONIOENCODING=utf-8 python "$t" >/dev/null 2>&1 && echo OK || echo FAILED
done
PYTHONIOENCODING=utf-8 python tools/test_doctor.py
```

All of these must exit 0 (18 `*_test.py` harnesses + `test_doctor.py`, which
does not match `*_test.py`). A plain `for` loop is **not** enough on its own:
most harnesses print `FAIL` but still exit 0, so the output has to be read.
The one command that runs everything — compile, budget, name audit and every
harness, checking both the exit code and the text — is:

```bash
python tools/run_all.py        # 22/22 checks on v1.27
```

Last full run (v1.27): **22/22 checks passed** (19 harnesses + 3 gates).

| Script | What it actually proves |
|---|---|
| `barn_lock_test.py` | The barn lock survives a stream-out/stream-in (matched by name + position, not identity). |
| `clean_visit_test.py` | Dirt is read without moving: clean barn = 0 hops, one dirty stall = 1, unreadable = 0, attribute/nested/visible-mesh/nested-value shapes all found, the meter line learns and stops, a 2.0 s clean is waited for exactly once, and a refusing stall is backed off on the next pass. |
| `cow_in_stall_test.py` | The per-cow clean path: a nil first read of the Clean offer still cleans (the poll fix), a clean stall is never pressed again, and an unreadable offer costs ≤0.5 s and no key — then the milk and gate still happen. |
| `lifecycle_test.py` | The generation guard: a reload stops the old build's loops, Unload stops the current ones, and a later build cannot revive them (captures the global-vs-local `spudAlive` trap). |
| `webhook_test.py` | A webhook URL must be Discord's own host + `/api/webhooks/` path; "contains the word discord" is rejected, and blank means off. |
| `drop_scope_test.py` | A jug appearing elsewhere in the world during the 10 s milk wait is not counted as "this cow gave milk". |
| `farm_batch_test.py` | Herd-batch arithmetic: who fills a batch, who hands over. |
| `farm_rotate_test.py` | Three-farm rotation order and wrap-around. |
| `farm_switch_test.py` | The under-herd-amount hand-over: `ready + parked` compared, fullest other wins, equal counts do not swap, unreadable never a target, no self-hand-over, no ping-pong. |
| `gate_visit_test.py` | Gate opened from where we stand (0 hops when the door is offered); an already-open gate is never pressed again. |
| `herd_arm_test.py` | Arming a cow is fast when the menu is up, and the no-menu timeout is bounded. |
| `herd_order_test.py` | Cows nearest the barn go first; a dirty free stall is skipped and an all-dirty barn arms nobody. |
| `herd_send_test.py` | The wrong-barn regression: no fallback to a stranger's `AutoWoodenBarn`. |
| `milk_arrivals_test.py` | The arrival wait watches stall `Occupant` values and scans a handful of times, not five times a second. |
| `path_test.py` | The path engine: heap order, A* gap/corner rules, exact LOS through a single blocked cell, clearance refusal, Theta* straight-line and shorter-than-8-way paths, arcs refused near a wall, curvature cap, height-banded marking, cell sizing. |
| `farm_width_test.py` | Working width and row plan: studs→tiles rounding, oriented-box union width, rotated bars, 1/2/3-wide plans (step, headland, row half-extent) and an interval-coverage proof on 100/200-stud and narrow fields; owner match rules. |
| `equip_owner_test.py` | Whose tractor/tool is picked: the farm being worked first, mine next, an unreadable owner after that, a stranger's never; stored machines are reported for spawning; the implement distance/basis stay honest. |
| `stall_probe_test.py` | The stall probe's report shape (it must name every dirt candidate and count visible stains). |
| `test_doctor.py` | The in-script 🩺 DOCTOR report runs on stubbed world objects and reports, not crashes. |

Plus the two non-test gates:

```bash
python tools/local_budget.py   # headroom must stay >= 1 (currently 2)
python tools/name_audit.py     # no top-level name collisions
```

Measurement harnesses (run when you touch the thing they measure, quote the
numbers in the README):

- `cow_scan_bench.py` — instance calls per cow scan (cache effect).
- `stall_scan_bench.py` — calls/name reads to find 12 stalls (narrow scan).
- `path_bench.py` — old HEAD `astarPath` vs the new heap A*/Theta* on synthetic
  maps (best-of-8 ms, cells, length, pops); the README numbers come from it.
- `store_timing.py` — milk store pass on a virtual clock with latency.

### 2.3 What green does **not** prove

The harness slices the **real** functions out of `SpudFarm_Full.lua` and runs
them under the real Luau interpreter against fake world objects. That catches
logic, arithmetic, and "did I break the shape" — it does **not** prove the live
game exposes those fields, that a GUI appears, or that an action is accepted.
Anything touching the game's own menus must be confirmed in game after a reload.

Known gaps: the **store deposit** and **feed top-up** paths have no harness (they
need a fake carrier + dispenser), and nothing in the suite proves the live game
exposes these fields. The per-cow clean path is covered by
`cow_in_stall_test.py`.

---

## 3. The game, as measured (not guessed)

### 3.1 Where things are

```
Workspace.Objects.Buildings.<barn model>          -- barns live in Objects.Buildings
  AnimalContainer.Spots.<n>                       -- one folder per stall; 12 stalls seen
    (attributes) AnimalMask, FilthLevel, FilthPercentage
    Center                    Part (transparent) · child MilkContainerSpawn [Attachment]
    Adornee_BarnStallMenu     Part (transparent) · child AlwaysInvisible, LinkedGui
    Filth                     Folder
      Stain  Part (1×2×0 / 2×2×0, Transparency 1 when clean) with a Decal child
      Level1..Level4  MeshPart (the four drawn dirt levels)
    Occupant                  ObjectValue (the cow parked here, or nil)
    NodeLink                  ObjectValue -> <barn>.AnimalContainer.Nodes.Stall<n>
    Gate                      Model {Enabled, Moving, Opened, OpenedAngle}, parts +
                              ProximityPart + GateHinge
    Hay                       Part · child FilthEffect [ParticleEmitter]
  Other.Dirt                  Part (18×1×70) -- scenery, never a stall's dirt
```

A probe report, verbatim, is the source of truth. `SpudStallProbe.lua` prints
one complete stall folder — every descendant, value, attribute, part
transparency/position, the visible-stain count, every dirt-sounding instance in
stall/barn/plot with its full path, and the game's own `CleanAnimalContainer`
billboard.

### 3.2 The dirt model

- **`FilthLevel`** (attribute on the stall folder, 0–4) = how many of the four
  stain levels are showing. **`FilthLevel > 0` is the primary trigger.** It is
  readable from the plot centre.
- **`FilthPercentage`** is the meter behind it. The probe found **`24` on a stall
  whose every stain was invisible** — 24 is the *clean* baseline, not "24 units
  of dirt". The script's line is `milkDirtLine = 24` and the meter is a trigger
  **only above it** (the owner's "over 20/24 dirtyness").
- The line **only ever moves up**, and only when the game itself says a stall it
  pointed at is clean:
  `milk: stall 1 reads 60% but the game offers no Clean there - the dirty line moves to 60%`.
  The rest of the stalls at that reading are dropped from that pass, so a wrong
  baseline costs one hop, once. It learns `max(trigger reading, re-read)`, only
  from a stall with **no fresh stain** (a stain that appeared since the scan is
  dirt whatever the meter says), and a reading above 100 teaches nothing. The
  line resets to 24 on every Reload (it is learned state, not a setting).
- Fallback read, no teleport needed: count the `Filth/Level1..Level4` MeshParts
  whose `Transparency < 1`. Clean stall = all four hidden. The folder is trusted
  only when it actually holds `Level` parts; any other `Filth` shape falls
  through instead of answering "0".
- Older shapes are also read: a direct `Filth` child, a nested value, an
  attribute named `Filth` / `Dirt` / `Grime`, or a dirty-named child.
- **No shape at all is not a reason to move.** The old "12 of 12 need a visit
  (no readable dirt)" fallback is gone; an unreadable stall is cleaned at the
  stall while its cow is milked, and the console lists what the stall actually
  holds, once per session.

### 3.3 Cleaning

- The game's own action is the `CleanAnimalContainer` billboard (text
  `V | Clean`), adorned to a stall's `Center` part. It is only offered while
  standing in that stall, so a clean is inherently in-stall.
- **A clean takes ~2 s.** Three waits, all on the game's own signal:
  - pre-pass, waiting for the offer to point at the stall: `24 × 40 ms` =
    **0.96 s ceiling**;
  - pre-pass, waiting for the clean to finish: `44 × 50 ms` = **2.2 s ceiling**;
  - per-cow clean first polls the Clean offer for up to **0.5 s** (10 × 50 ms) —
    a single nil read right after the no-settle teleport used to skip the clean
    entirely and milk a dirty stall;
  - per-cow clean: `45 × 50 ms` = **2.25 s ceiling** (it used to give up at
    0.96 s and press for milk *mid-clean* — a press the game ignores, and one
    way a cow came back unmilked).
- The log states the measured duration: `OK milk: stall 3 cleaned in 1.94s
  (2 stain(s) -> 0)`.

### 3.4 Cows and milk

- A cow's owner is found via `Configurations.Owner` (walking up to eight parents
  when absent); the instance walk is cached per model in a weak table, and an
  animal is **never** cached as untagged (it can gain an owner a moment later).
- Happiness decides the jug: **<60 % spoiled, 60–89 % regular, 90 %+ free-range.**
  Only **free-range** jugs are loaded into the carrier
  (`store: leaving N non-free-range jug(s)`); the rest are left for selling.
- 12 stalls per barn, herd batch typed 1–12, per-farm teleport to a remembered
  plot centre (plots stream out when far away).
- Arrival detection watches the plot's stall `Occupant` values (~30 reads over
  12 stall parts) and only scans when an un-milked cow turns up parked.

### 3.5 Which farm gets the next pass

The owner's rule: *"before it brings the cows inside make it check for over
20/24 dirtyness"* and *"it does not switch the plot/players field when it gets
under the herd amount"*. The implemented rule, in one sentence:

> **Compare every cow waiting on each farm — ready in the field plus already
> parked in a stall — and hand the next pass to the farm with the most of them,
> as long as that is more than here.**

Consequences that are deliberate and tested:

- A farm whose cows are all parked reads `0 ready`; leaving it out was the
  "it's missing sometimes bro" miss. `ready + parked` fixes it, and milking
  parked cows is also faster than herding.
- The comparison is **not** a demand for a full batch — two alts rarely have
  twelve cows at 300 % at the same moment.
- **Equal counts never swap** (that would ping-pong two equal alts).
- **No other farm readable → work this one**; a small farm cannot stall the loop.
- A farm that **cannot be read** (streamed out, not built) is **never** a target
  and is named as unreadable in the stay line.
- Cleaning happens first, always; a dirty stall is never skipped or filled.
- The stay line explains a skipped switch:
  `milk: desbiens1235 has 6 ready cow(s) - under the 12 per herd, but the fullest other is Miou2251: 4 ready - working this one`.

### 3.6 Travel and Theta*

The engine is a **top-level global module** (`SpudPath`) in
[SpudFarm_Full.lua](SpudFarm_Full.lua) — outside the build closure, because
that closure is at Luau's 200-local wall. The closure keeps `pathfindAround`
(grid, obstacle map, calls) and `driveRoute` (the follower).

1. **Grid**: rectangle from start+goal plus 50 studs; cell size
   `clamp(trip / 70, 6, 16)`; more than **90,000 cells is refused**. Keys are
   `ix * 100000 + iz`. The old long-haul grid went to 24 studs and erased gates;
   the heap makes the extra cells affordable.
2. **Blocked cells**: `SpudPath.worldParts` caches the recursive walk of
   `Objects.Equipment`, `Objects.Buildings`, `Objects.Fences`,
   `Stores.Buildings` and plot `Foliage` (static, **1 s TTL**), plus
   `Objects.DraggableObjects` and `Objects.Animals` (**0.5 s TTL**); **only
   `CanCollide` parts**; rotated parts projected onto the ground plane; pad
   `6 + hull`; the ride and its tool are skipped by **owner** (the scanned
   folder's top-level child). `SpudPath.markParts` also drops parts whose
   vertical span misses the ride's band (`minY−2 … maxY+10`), so roofs,
   overhead pipes and raised pad edges no longer block the ground under them.
3. **Search**: **binary-heap A*** with a closed set, stale-entry skip and
   `f`-then-`h` tie-break; 8-connected, `1`/`1.4142` step cost, octile
   heuristic, no corner cutting; `maxPops = max(12,000, nx·nz)`. The default is
   **Lazy Theta\*** — a neighbour may inherit the expanded node's parent, and
   the long edge is line-of-sight checked when it is expanded — so routes are
   straight wherever the grid is open instead of 8-way staircases. If the
   any-angle search exhausts its pop budget, `SpudPath.search` falls back to
   8-connected A*.
4. **Hug penalty**: multi-source BFS `clearanceField` (capped at 5) multiplies a
   step's cost — ≥4 cells `×1`, 3 `×1.5`, 2 `×2.5`, ≤1 `×4.5`. Step cost uses
   the destination cell; Theta*'s long edge is validated with `losClear = 2`
   on interior cells only (endpoints are exempt — the ride may be parked beside
   a tool).
5. **Line of sight**: **exact voxel traversal (DDA)**, not half-cell sampling —
   a thin fence post between samples used to be invisible. A corner crossing is
   refused unless both side cells are free (the towed tool has width).
6. **Post-processing**: `SpudPath.smooth` replaces each >20° vertex with a
   **quintic Bézier** blend sampled every ~1.4 studs (radius 22 → 14 → 8) and
   keeps it only while every interior sample is free, keeps `arcMargin = 2`
   cells of clearance, and the sampled-curvature is ≤ **0.08 rad/stud**. The
   control factor is `a = 0.30·d`: the old `0.55` overshot the corner, so a
   nominal "22-stud radius" actually measured ~4 studs. If no radius fits, the
   vertex stays sharp and the speed profile slows for it.
7. **Fallback**: four attempts — base cell/full hull, **base × 0.75/full hull**
   (finer first: a narrow gap is more likely to be found on a finer grid),
   `×1.5`/half hull, `×2.2`/no hull. Then `nil` + reason + `direct` only if
   `SpudPath.los` verifies the straight line. `driveRoute` replans ~1 s while
   moving.

Verified numbers ([tools/path_bench.py](tools/path_bench.py), synthetic
1-stud grids, best of 8): the **old** linear-scan A* returned **no path** on
the cluttered 120×120 and walled 80×80 maps at its own pop cap; the new A*
solves them in **≈80–105 ms / ≈29–37 ms** (the old spent ≈90–250 ms before
failing).
Theta* cut the clutter route from **167 to 61 waypoints** (length 196.7 → 187.9)
and the walled route from **139 to 14** (144.6 → 136.8). Theta* costs more
search time on dense 1-stud grids (58–221 ms), but the game's cells are 6–16
studs and the replan budget is ~1 s. The console line is
`path: 9 point(s) (corners are arcs), 412 part(s), theta* 1,204 pops / 11 ms, min clear 3 (tool margin 6)`.

It cannot know about a gate that closes after planning, a moving vehicle, or
geometry thinner than the current cell; a part that moves inside the cache TTL
marks its old spot for that second.

### 3.7 Whose tractor and tool

A farming pass used to take the **nearest** machine in `Objects.Equipment`,
whoever owned it — on a foreign field that borrowed a stranger's ZM80 whenever
one was closer. The probe proved every machine carries
`Configurations.Owner` (`ZM80`/`SRC6` = `oksimba_1`, `LH150`/`MTS`/`UH` =
`Miou2251`), so `equipOwnerRank(m)` now ranks each machine.

With a **foreign farm picked** the order is: that farm's machines (rank 0), my
own machines (1), a machine with no readable owner (2), and another account's
**never**. With **`(mine)`** it is: mine (0), no readable owner (1), another
account's never. `findTractor` and `findImplement` scan the ranks low-first
and, inside a rank, keep the old nearest-wins rule (implement still prefers the
model name over the `EquipmentType` attribute). A stored machine of the chosen
rank is reported for the Equipment Manager instead of taking a spawned machine
from a lower rank. `logEquipment` prints each machine's owner, and the "not
found" lines name the farm the pass was looking for.

---

## 4. Code map (names, not line numbers — they move)

| Area | Function / thing |
|---|---|
| Build identity | `VERSION` at the top of the file (`rebuild vX.YY · fluent gui`) |
| Pathfinding | top-level `SpudPath` (`heapPush`/`heapPop`, `astar`, `thetastar`, `search`, `los`, `clearance`, `smooth`, `markParts`, `worldParts`), then `pathfindAround`, `driveRoute`, `driveToField`, `driveWatchTick` |
| Farm width / owner | top-level `SpudFarm` (`widthTiles`, `widthFromParts`, `rowPlan`, `ownerWanted`, `workTiles`, `partBoxes`, `declaredWidth`), `spudOwnerChoices`, global `farmOwnerPick`, `spudFarmOwnerDrop`; `sweepField` plans rows from `rowPlan` |
| Whose machine | global `equipOwnerRank(m)` (farm being worked → mine → no readable owner → never another account), used by `findTractor` / `findImplement`; owner tag read by `milkStoreOwnerOf` |
| Dirt line | global `milkDirtLine = 24`; `milkDirtHigh(spot)` (the single "is this dirty?" answer) |
| Clean pass | pre-pass offer watch (0.96 s) → clean watch (2.2 s); per-cow clean `≤2.25 s` |
| Herd | `milkHerdBatch(stalls, cows)`, `milkHerdTargets`, `milkHerdSend`, ordering nearest-barn-first, `milkHerdArm` |
| Farm choice | `milkFarmReadyCount(who)`, `milkFarmSwitch(want, owner, readyHere, parkedHere)` |
| Barn lock | name + position, resolved by spot — see `milkBarnLive` / `milkBarnFor` |
| Cow reads | `milkCows`, `milkOwnerOf`, `milkPercentOf`, `milkStateOf`, `milkDrops` |
| Store | `milkStoreAmount`, `milkStoreDeposit`, `milkPollFor`, `milkFrame`; remotes `EVTRequestToCarry`, `EVTFillLiquidCarrier` (key path is the fallback) |
| GUI | Fluent shell, RIGHT SHIFT, 📡 webhook, 🥔 overlay; `spud-gui-preview.html` is a browser mock |

**Read-only probes** (run in game, paste the report): `SpudStallProbe.lua`
(stalls/dirt), `SpudDump.lua` (world structure, run twice: town + farm),
`SpudRemoteProbe.lua` (remotes while you act by hand), `SpudBarnProbe.lua`,
`SpudCrateProbe.lua`, `SpudEquipProbe.lua`, `SpudFeedProbe.lua`,
`SpudSellProbe.lua`, `SpudCapture.lua`. `SpudBoot.lua` is the error-reporting
loader. `FarmingAndFriends_Main.lua` is the older generic script; superseded.

---

## 5. The conversation, condensed

Chronological, oldest → newest. Each entry: what was reported, what was actually
wrong, what changed.

**Early arcs (from the git history).** Build string v1.9 → clean rebuild in
progress. `2ae3d37` fixed the **200-local limit** that broke loading; `22992d1`
added the on-screen loader so failures are visible without a console; `8fd16d5`
and `831728e` cut fixed sleeps out of the milk loop and milked each cow as it
landed; `129fbf3` restricted carrier loading to free-range jugs; `d154efe` used
the game's own carry/fill remotes as a fast path with key-press fallback.
`2586443` herds the cows nearest the barn first. `7693ef3` added the three-farm
rotation. `84da366` locked one barn per farm for the session. `1a4b243` made
farm changes a teleport to the remembered plot centre instead of a walk (a
distant plot is streamed out, so the pass used to see "no farm").
`a150ffe` narrowed the stall scan to `Objects.Buildings` (95,517 → 73 calls).
`f5a2b51` added `SpudBarnProbe.lua` for the herd-not-sending bug.

**"It does not switch the plot/players field when it gets under the herd
amount"** → `f2c3e19`. The switch demanded a whole batch from the other farm,
which almost never exists at that moment. It now hands over to the **fullest
other** farm. The README keeps the owner's quote and the reasoning.

**"It's missing sometimes bro"** → `c193909`. The chooser counted only cows
*ready in the field*; a farm whose cows were already parked in its stalls read
as `0` and was skipped, so its milk sat there. Now compares `ready + parked`,
and the stay line names the reason. The test suite also caught a real bug in
that edit: early exits returned the reason as the farm-name slot, so a parked
farm would log `farm nil (full)`.

**"Btw it takes 2 seconds to clean a stall"** → `a6a5034`. The per-cow clean gave
up after 0.96 s and pressed for milk **mid-clean** — a press the game ignores,
which is one concrete way a cow comes back unmilked. It now holds until the
Clean offer clears (2.25 s ceiling), both clean paths log the real duration, and
the pre-pass polls every 40–50 ms instead of overshooting.

**"Like bro, before it brings the cows inside make it check for over 20/24
dirtyness"** → `e58935e`. The meter was read but not used as a trigger; it is now
a trigger above the 24 % clean baseline (`milkDirtLine`), and **no cow is put in
a stall that reports dirt** — the herd step tests every free stall with the same
three readings the cleaner uses, skips dirty ones, and arms nobody in an
all-dirty barn. The line self-corrects upward from the game's own answer, so it
cannot become the old twelve-stall tour.

**"Add a read-only probe that dumps one complete stall folder"** → `7901c2f`
(the probe) and `5e29ff4` (an on-screen panel with COPY REPORT). It is what
named `FilthLevel`/`FilthPercentage`, showed every stain `Transparency = 1` on a
clean stall, and found `Other.Dirt` (scenery) — the field the clean pass should
*not* read.

**"Can you explain how the A* pathfinding works?"** — answered, no code change:
grid from trip length, `CanCollide` footprints, octile heuristic, no corner
cutting, the clearance hug penalty, string-pull with a 2-cell margin, quintic
Bézier corners, three-attempt fallback, replanning while driving. Summary is in
§3.6 above.

**"Look for bugs. let me know what to improve" → "js do it all"** → v1.24
(uncommitted). The review found: Unload/Reload leaked every loop (the FPS that
kept getting worse), the per-cow clean read the offer once right after an
un-settled teleport (a dirty stall could be milked), `milkDrops` counted the
whole world (another player's jug read as "milked"), learned state survived
Reload, a crashed growth-wait left `farmResting = true`, and a global
`milkDrops` counter clobbered the dropdown table. Fixed: session generation
guard, clean-offer poll, 4 Hz plot-scoped jugs, strict webhook validation
(pasted **and** remembered), per-stall clean backoff, per-pass timing in the
status line and Doctor, persisted farm/batch/seed/movement choices,
Start/Stop-all + verbose-log controls, pinned `FLUENT_TAG`, reload payload
check, and the `name_audit` + `run_all` gates. New harnesses:
`lifecycle_test`, `cow_in_stall_test`, `drop_scope_test`, `webhook_test`. All
harness-green; **not reloaded in game**.

**"first you need to make the pathfinding MUCH better with online resources"**
→ v1.25 (uncommitted). The diagnosis: the old A* scanned its open array **and**
`table.remove`d from it on every pop (O(frontier) twice), with no closed set, so
on a cluttered map it burned its pop budget on duplicate entries and returned
**no path** — `path_bench` reproduces that (252 ms / 103 ms spent, then nil).
Obstacle marking ignored height (roofs and raised pad edges were phantom
walls) and re-walked seven folders every second; line-of-sight sampled
half-cells (a thin fence post could slip between samples); and the Bézier
control factor `0.55` overshot the corner, so the nominal "22-stud radius"
measured ~4 studs. Now: a top-level `SpudPath` module with a binary heap +
closed set, **Lazy Theta\*** (A* fallback), exact DDA line-of-sight, a 1 s/0.5 s
cached, height-banded obstacle map, a 6–16-stud grid (90k-cell cap, finer-first
retries), and clearance/curvature-gated arcs (`0.30` factor, margin 2,
0.08 rad/stud). `path:` prints mode, pops, ms and minimum clearance. New
`tools/path_test.py` (32 checks) and `tools/path_bench.py`; suite **20/20**.

**"i want the farming features to also work on another field ... they will be
3 wide instead of 1" → "make the farming be able to work on someone elses
farm"** → v1.26 (uncommitted). The sweep hard-coded one 10-stud tile (rows
every 10, headland 10), so a 3-wide tool would overlap three times. Now
`SpudFarm.workTiles` measures the implement's whole ground union across the
step axis (oriented boxes, rotated tools included), rounds it to 10-stud tiles,
and `SpudFarm.rowPlan` spaces rows by that width with a matching headland band;
the touch-up groups missed cubes by row instead of visiting each. A declared
attribute/Config width is logged next to the measurement but only used when no
part is readable. The Farm tab also has a **Farm owner** picker (mine + owners
seen in streamed fields, plus **Refresh farm list**): `findMyFields` now uses
`SpudFarm.ownerWanted`, so the same tour/growth/touch-up runs on that owner's
fields. Equipment was still found **without** an owner filter at that point
(nearest tractor/tool — fixed in v1.27 below), and a pass that changes nothing
on a foreign field says `check worker permissions`. New
`farm_width_test.py` (30 checks); suite **21/21**. Green but **not reloaded in
game**.

**"make it use the farm owners tools then commit and push"** → v1.27. The
owner picker changed which **fields** were worked, but the machines still came
from "nearest in `Objects.Equipment`" — a stranger's ZM80 was borrowed whenever
it happened to be closer. `equipOwnerRank` now ranks machines: the farm being
worked first, then mine, then one with no readable owner; another account's is
never used. `findTractor` and `findImplement` scan the ranks in order (nearest
wins inside a rank, and the implement still prefers the model name over
`EquipmentType`); a stored machine of the chosen rank goes to the Equipment
Manager for a spawn rather than taking a lower rank's spawned machine.
`logEquipment` prints every machine's owner, and the not-found lines name the
farm. New `equip_owner_test.py` (23 checks); suite **22/22**.

**Where it stands:** `rebuild v1.27 · fluent gui`, whole suite green (22/22),
harness verified. **Not yet reloaded in game** after v1.22–v1.27 — the next real
test is a live pass watching `path: … theta* N pops / N ms, min clear N`, the
new width line (`tool … — 3-wide …; rows every 30`), the Farm owner picker on
the other farm, the equipment owner column (`· ZM80 = Tractor [spawned] ·
oksimba_1`), and the milk lines (`… read from here - none reports dirt`,
`… cleaned in X.XXs`).

---

## 6. Open questions / known limits

1. **In-game confirmation is pending** for v1.22 (2 s clean wait), v1.23
   (meter trigger + no-cow-in-dirt gate), v1.24 (unload/reload guard, drop
   scoping, clean backoff), v1.25 (new path engine: watch the first `path:`
   lines and whether the tractor stops hugging gear), v1.26 (wide tools:
   check the `tool … — N-wide` line matches the real tool, and that a picked
   foreign farm actually accepts the drive-overs) and v1.27 (owner-first
   equipment: check the owner column in the equipment log, and that a picked
   farm's tractor/tool is the one mounted). Harness green ≠ game green.
2. **The 24 % baseline may differ per build.** If stalls sit higher, the first
   pass logs `reads X% but the game offers no Clean there - the dirty line moves
   to X%` and then stops hopping. That is the designed self-correction, not a
   bug — report the number if you see it.
3. **The store deposit and feed top-up paths are untested** (they need a fake
   carrier + dispenser).
4. **Long trips plan coarse or get refused** (>30,000 cells at the chosen cell
   size). The fallback is a verified-clear straight line, otherwise a logged
   failure.
5. **"Modified client" is executor detection**, not movement or timing. No edit
   to this script changes it; the README's Stealth section says so explicitly
   and should keep saying so. The probes are louder than the farm script (they
   hook `__namecall`); don't run them on an account you care about.
6. **Codes are disabled** in-game (mid-2026); any "working codes" list is fake.

---

## 7. Glossary

- **stall** — `<barn>.AnimalContainer.Spots.<n>`, one per cow slot; 12 per barn.
- **dirt line** — `milkDirtLine`, the `FilthPercentage` threshold above which a
  stall counts as dirty even with no level drawn (24 by default).
- **parked** — a cow already inside a stall (`Occupant` set), as opposed to
  **ready** in the field.
- **batch** — the typed herd size (1–12) for one pass.
- **lock** — the farm's chosen barn, held as name + position for the session.
- **probe** — a separate read-only script whose only job is to report live game
  structure so names and thresholds stop being guesses.
