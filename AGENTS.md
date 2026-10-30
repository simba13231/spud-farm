# SPUD FARM — the one-file brief

Everything an agent (or a person) needs before touching this repo: the owner's
rules, the game facts we have actually **verified**, the history of what was
asked and fixed, and the exact loop to prove a change works.

**Read this file first. Then read [README.md](README.md)** for the user-facing
description — it is the long-form manual and it is kept in sync with behaviour.

- Main script: [SpudFarm_Full.lua](SpudFarm_Full.lua) — one paste-and-run Luau
  file for the Roblox game *Farming and Friends*, currently `rebuild v1.60 ·
  fluent gui` (`VERSION`, line 15). ≈12.3k lines.
- Target: Windows + Git Bash. Luau toolchain lives in
  `%LOCALAPPDATA%\Temp\opencode\luau\` (`luau.exe`, `luau-compile.exe`,
  `luau-analyze.exe`).
- Nothing here is a library or a build system. There is no bundler, no package
  manager, no CI. Validation is a compile check plus twenty-seven harness scripts in
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
    ceiling.** Run `python tools/local_budget.py`. As of v1.60:
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

`HEAD` is the latest committed build (v1.60, trimmed Tests tab),
`main`
tracks `origin/main`, and the tree is clean. Keep it that way: make the change,
run the gates, and commit only the files the change touches. `git add -A` is
banned here. **Commit and push after every completed change** (owner's standing
rule, 2026-10-28) unless the owner says they will do it themselves.

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

All of these must exit 0 (26 `*_test.py` harnesses + `test_doctor.py`, which
does not match `*_test.py`). A plain `for` loop is **not** enough on its own:
most harnesses print `FAIL` but still exit 0, so the output has to be read.
The one command that runs everything — compile, budget, name audit and every
harness, checking both the exit code and the text — is:

```bash
python tools/run_all.py        # 30/30 checks on v1.60
```

Last full run (v1.60): **30/30 checks passed** (27 harnesses + 3 gates).

| Script | What it actually proves |
|---|---|
| `barn_lock_test.py` | The barn lock survives a stream-out/stream-in (matched by name + position, not identity). |
| `clean_visit_test.py` | Dirt is read without moving: clean barn = 0 hops, one dirty stall = 1, unreadable = 0, attribute/nested/visible-mesh/nested-value shapes all found, the meter line learns and stops, a 2.0 s clean is waited for exactly once, and a refusing stall is backed off on the next pass. |
| `cow_in_stall_test.py` | The per-cow clean path: a nil first read of the Clean offer still cleans (the poll fix), a clean stall is never pressed again, and an unreadable offer costs ≤0.5 s and no key — then the milk and gate still happen. |
| `lifecycle_test.py` | The generation guard: a reload stops the old build's loops, Unload stops the current ones, and a later build cannot revive them (captures the global-vs-local `spudAlive` trap). |
| `webhook_test.py` | A webhook URL must be Discord's own host + `/api/webhooks/` path; "contains the word discord" is rejected, and blank means off. |
| `drop_scope_test.py` | A jug appearing elsewhere in the world during the 10 s milk wait is not counted as "this cow gave milk". |
| `farm_batch_test.py` | Herd-batch arithmetic: who fills a batch, who hands over. |
| `farm_hop_test.py` | The go-to-the-farm hop: no plot or no position answers with a reason, a plot within 60 studs is left alone, a far plot targets its centre +5 Y, and the reported distance is the real one. |
| `farm_rotate_test.py` | Three-farm rotation order and wrap-around. |
| `farm_switch_test.py` | The under-herd-amount hand-over: `ready + parked` compared, fullest other wins, equal counts do not swap, unreadable never a target, no self-hand-over, no ping-pong. |
| `gate_visit_test.py` | Gate opened from where we stand (0 hops when the door is offered); an already-open gate is never pressed again. |
| `herd_arm_test.py` | Arming a cow is fast when the menu is up, and the no-menu timeout is bounded. |
| `herd_order_test.py` | Cows nearest the barn go first; a dirty free stall is skipped and an all-dirty barn arms nobody. |
| `herd_send_test.py` | The wrong-barn regression: no fallback to a stranger's `AutoWoodenBarn`. |
| `hop_test.py` | The arc hop's landing height: a return leg from the lower pad lands ON the field (never keeps the pad's height, which flew it under the ground), a trip down still lands at the takeoff height, the arc clears the landing by ~12 studs and arrives from above, a level hop stays level, a missing target Y keeps the takeoff height, a zero-length hop is one move, and stopping aborts without landing. |
| `milk_arrivals_test.py` | The arrival wait watches stall `Occupant` values and scans a handful of times, not five times a second. |
| `path_test.py` | The path engine: heap order, A* gap/corner rules, exact LOS through a single blocked cell, clearance refusal, Theta* straight-line and shorter-than-8-way paths, arcs refused near a wall, curvature cap, height-banded marking, cell sizing. |
| `farm_width_test.py` | Working width and row plan: studs→tiles rounding, oriented-box union width, rotated bars, 1/2/3-wide plans (step, headland, row half-extent) and an interval-coverage proof on 100/200-stud and narrow fields; owner match rules. |
| `equip_owner_test.py` | Whose tractor/tool is picked: the farm being worked first, mine next, an unreadable owner after that, a stranger's never; stored machines are reported for spawning; the implement distance/basis stay honest. |
| `field_soil_test.py` | Tree/wood field types and names are never crop-harvest targets; a successful cell read with 0 cells is empty (skipped), while a failed read stays unknown (never a skip reason). |
| `field_remote_test.py` | The field remotes: ids come from the game's own `GetCells` dict (numeric keys only, sorted, failed read = unknown), the tool's RaycastPart attachment is the one sent, one call per remaining cell carries `(field, {id}, {attachment})`, a full batch reports done, a partial batch hands back the remainder, an ignored batch switches that job back to driving (and fires nothing again), and `FillSeeder` falls back to V on a refusal. The Tests-tab batch: one call carries every id, a full/partial/ignored id list is judged by the stage re-read, and an ignored list never switches the job off. |
| `equip_remote_test.py` | The equipment remotes: the seven captured calls resolve on `Modules.Larry`; spawn/store are proven by `InStorage` (or a >100-stud move for a rebuilt spawn) and fall back to the UI when ignored; enter is proven by the seat; hitch/unhitch use the captured `Components.Hitchable` + `Chassis.HitchableSocket` pair; carry/drop are proven by the hands; three misses switch one action off for the session. |
| `row_steer_test.py` | The row decision in the wide band: `spudRowNeedsAlign` asks for ONE snap only past `spudRowAng` (15°) or `spudRowTol` (6 studs); `spudRowSteer` presses nothing inside the band; `spudRowEase` takes a step off the throttle after three steering flips (×0.7, floor 30 %) and gives one back per steady 3 s. |
| `foreign_respawn_test.py` | `spudMayRespawn()` is false while a Farm owner is picked, and `ensureToolNearby` then never calls `respawnTool`: a stored or far-away tool is named and the pass is skipped, while `(mine)` still respawns. |
| `dropoff_test.py` | The full-tank gate follows the Farm tab's Drop-off pick: a full tank unloads with Fulfillment or Sell chosen, a half tank works on, an unknown/nil destination never moves; the Fulfillment pad is read from `Stores.DropOffs` (Deposit_Warehouse preferred over Withdraw_Warehouse), aimed at its top surface, and an unstreamed/empty folder returns no pad instead of a guess. `trySellAt` itself runs on a virtual clock: the Fulfillment pad drops the load while pressing **zero** keys and making **zero** calls, a working Sell call presses nothing, and an ignored Sell call falls back to Q and E without claiming a sale. |
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

**On a picked farm nothing is spawned or respawned** (v1.34). User: *"when it's
on someone elses plot make it not try to respawn things bro."* Bringing a
machine out of storage or respawning a far one drives the game's Equipment
Manager — the owner's call, not ours. `spudMayRespawn()` is the single rule
(false while a pick is active) and it is checked at all three places that used
to spawn: a **stored tractor** (log + stop), a **tractor beyond
`RESPAWN_RANGE`** (log + stop), and every **implement** through
`ensureToolNearby` (log + skip that pass). Each line names the machine, why
(stored / N studs away) and that `(mine)` is how to bring it out.

**The fields follow the same picker, one owner at a time** (v1.29):
`SpudFarm.ownerWanted` now means *exactly* the picked owner when a pick is
active, not "mine **or** the pick". Before that, picking Miou2251 hitched that
farm's plow (rank 0) and then toured **my** fields as well — user: *"it's using
the player it's working for's equipment then going on it's own field."* With
`(mine)` it is still exactly my fields. The tour and per-field log lines now
carry the owner (`Field · Miou2251`), so a mixed tour can never look anonymous.

### 3.8 Trees and wood soil

User: *"it's trying to harvest my trees but i don't want to."* The harvest job
(`JOBS[4]`, `grown = true`) counts **any cell stage it does not recognise** as
"a crop is standing" — because the real grown-stage name was never in a dump.
A tree/wood field's cells therefore look like a ripe crop and the harvester is
sent over standing trees.

The guard is `spudTreeField(typeName, modelName)`: a field whose
`Configurations.FieldType` or model name contains **wood, tree, log, forest,
timber, lumber, sawmill or stump** is never a crop-harvest target. It is applied
everywhere harvest work is decided (`probeWork`, `runPass`'s `anyNeed`,
`runPass`'s per-field loop, `needLeft`, `grownLeft` and the growth wait) and the
skip is logged with the real type, so a build that names the soil differently is
visible in one run instead of silently harvesting trees.

The second rule is the owner's "unreadable is not empty" (rule 7) applied to
cells: `spudNoCells(st)` is true only when the game's cell read **succeeded**
and returned `total = 0`. Such a field is skipped for every job. A `nil` read
(failed API, streamed-out field) stays *unknown* and is still never a reason to
skip work.

The full crop↔soil mapping (a crop seed works normal soil, a tree seed works
wood soil) still needs the live `FieldType` values and the seed categories —
that is what `SpudFieldProbe.lua` answers; the harvest guard is independent of
it and needs no mapping.

### 3.9 Row driving and speed

User: *"when you drive there is like a game helper that auto re steers the
tractor on course"* + *"it does not re-center"* + *"make it go faster"*. The
game has its own steering assist on a field; the align mover fought it, and its
pure-pursuit aim corrected **heading only** — a tractor parallel to the row but
2–6 studs beside it had zero heading error, pressed no key, and never came back.

- Rows are now driven on **real W** (`keyRow`, the driver the harvester already
  used), so the game's controller does the steering. `keyRow(tr, seat, from,
  goal, who)` gained the `who` label so the log says `tractor:` as well.
- **v1.35 — snap once, then go straight** (user: *"it is still going back and
  fourth bro like side to side, make it force the alignement then jus tgo
  straight and let the game do the ajustments"*). The per-tick cross-track A/D
  nudge was fighting the game's steering, which is the side-to-side. Now, at
  the start of a **row** (leg ≥ 20 studs) `keyRow` snaps the ride onto the row
  line with `CFrame.lookAt` when `spudRowNeedsAlign(angDeg, cross, tol)` says
  it is off, waits 0.15 s for the move to reach the server, and then holds
  **W only** for the rest of the leg. `spudRowSteer(angDeg, crossY)` is
  heading-only: A/D is pressed to swing the nose onto a row, and **nothing**
  while the heading is fine. Short Omega turn legs (< 20 studs) keep the
  swing-through from v1.30.
- **v1.36 — the band is WIDE** (user: *"widen the steering range it takes bro
  it's like still going side to side yo"*). The thresholds were 8° / 2.5 studs,
  close enough to the game's own corrections that they kept trading places. They
  are now globals `spudRowAng = 15` and `spudRowTol = 6`, and the row loop has
  **hysteresis**: steering starts past 15° and only stops once the nose is back
  inside half that band, so a nose wobbling around one threshold can no longer
  flip A/D/A/D.
- **v1.37 — a swinging row slows itself down** (user: *"if it keeps going back
  and fourth with the seering make it slowly go slower bro"*). `keyRow` counts
  steering **direction changes**; three of them take a step off the row's
  throttle through `spudRowEase(level, flips, steadyFor)` (×0.7, never below
  **0.3**), and every steady **3 s** earns +0.1 back (never above 1). A reduced
  throttle is a duty cycle on W (4 pulses a second), because the key API has no
  analogue input. So an oscillating row converges to a slow, steady pass instead
  of a fast wobble.
- Travel speed `ALIGN_MAXVEL` is **34 studs/s** (was 24). The align mover is now
  only the row **fallback** (`math.min(HARVEST_TWEEN_SPEED + 8, ALIGN_MAXVEL)` =
  18), so a plow doesn't snag at travel speed; the old 10-stud/s mover cap no
  longer governs a normal row.

`row_steer_test.py` pins the steering decision. The real-W row speed is the
game's own, so it is faster than the old 10-stud mover by construction.

### 3.10 A full harvester unloads at the chosen drop-off

User: *"im telling you i ON the pad to furfull bro, make a option in the farm to
either furfull or sell bro."* The Farm tab now carries **Drop-off** with two
values, and the full tank always ends in a real trip:

- global `spudDropOff` (default **Fulfillment**, remembered across a reload in
  `spudSavedDropOff`); `spudSellNow(cur, max)` is true only for a readable
  `cur >= max` **and** one of the two known destinations — an unknown or nil
  pick still stops the run rather than driving nowhere.
- **Fulfillment** → `spudFulfillSpots()` reads `Stores.DropOffs` and prefers
  `Deposit_Warehouse` (the probed pad at -353,138,-90) over `Withdraw_Warehouse`
  and the plain `DropOff`s, aiming at the pad's **top surface**. The folder
  being unstreamed/empty is logged and returns no pad — never a guessed spot.
- **Sell** → the old `findSellSpots()` crop sell-board scan, unchanged.
- The trip itself is the existing arc hop (`hopTo`, `SELL_HOP_SPEED`) plus
  `trySellAt(ride, what, pad, autoPad)`, which differs by destination:
  - **Fulfillment** (`autoPad = true`) presses **nothing** — user: *"the
    fulfillment you dont gotta do anything just go to the location and it does
    it"*. The pad unloads a parked harvester on its own; the trip only waits
    (16 s ceiling) and logs `fulfillment pad …: parked — this pad unloads by
    itself, pressing nothing`.
  - **Sell** (`autoPad = false`) fires the captured `EVTSellAtStore(ride, pad)`
    first, then falls back to Q (menu) / E (confirm) after a 3 s grace.
  **The tank dropping is the only proof** a pad took the load, in both cases. A
  failed trip backs off 60 s and the harvest carries on with the load it has.
- **The hop lands from above** (v1.42, user: *"when the harvester is coming back
  from somewhere it should drop from higher, because right now it is coming
  from under"*). `hopTo` used to keep the **takeoff** height at both ends, so
  the return leg from the Fulfillment pad (~140) flew the whole way under the
  field (~172) and only surfaced on the last frame. It now lands at
  `max(takeoff, target.Y)`, and the arc's lift is raised so the peak clears that
  landing by ~12 studs — the ride climbs and comes **down** onto it. A trip to a
  lower pad is unchanged (takeoff height, as before). The log names both heights:
  `arc hop: 412 studs, lifting 70 studs (Y 172 → 140)`.
- `SpudFulfillProbe.lua` reads the game's **live** offer billboards
  (`PCGP_ContextActions.Billboards`, with key + adornee), what the character is
  standing on, everything within 30 studs, `DropOffs` by distance, and nearby
  equipment. `PCGP_ContextActions.Buttons` is the whole action registry (70
  entries, no keys) and must not be used to answer "what is offered here".

### 3.11 A picked farm is reached before anything is read

User: *"also make it teleport to the spesific farm, find the tools then run."*
The start of a run with a **Farm owner** picked now hops to that owner's plot
before the equipment scan:

- `spudFarmHop(here, plotPos)` returns `nil, "no plot"`, `nil, "no position"`,
  `nil, "close"` (≤60 studs — no teleport for nothing), or
  `Vector3(plot.X, plot.Y + 5, plot.Z), distance`.
- The plot is `milkStorePlotOf(pick)` — the same owner lookup the milk store
  uses (`Configurations.Owner`, else the `PlotBillboard.Owner` label).
- A **seated** character is stood up first (`milkStandUp("farm")`, the game's F
  key), because a CFrame write on a seat does not replicate; if it cannot get
  out it stays put and says so instead of teleporting nowhere.
- After the hop it waits **0.5 s** so the fields and that farm's machines
  stream in, then `findTractor` / `findImplement` pick **that owner's** gear
  (§3.7), and the run logs `farm: using <tool> (<owner>) N studs away`.
- An unstreamed plot is not a guess: the run says
  `farm owner: <who>'s plot is not streamed — working from here`.

`farm_hop_test.py` pins the helper's decisions (7 checks).

### 3.12 Field work fires the game's own cell remotes

User: *"i want to make the seeding and planting and things use remotes."*
`SpudRemoteProbe.lua` was extended to capture field calls, and one manual
cultivate pass recorded the shape (2026-10-30):

```
ReplicatedStorage.Modules.Larry.EVTCultivateFieldCell:FireServer(
    Workspace.Objects.Fields.Field, {1=641},
    {1=Workspace.Objects.Equipment.KQF3000.Components.Cultivator.RaycastPart.Attachment})
ReplicatedStorage.Modules.Larry.FNCFillSeeder:InvokeServer(Workspace.Objects.Equipment.KADL)
```

- **Cell ids are the game's own keys.** `FieldHelper.GetCells(field)` is a dict
  keyed `x*128+y` (the same key `cellsAtStage` already decodes), so
  `spudFieldCellIds(field, stage)` returns exactly the numbers the call wants.
  A failed read returns **nil** (unknown), never an empty list.
- **The attachment is the tool's own.** `spudToolAttachment(impl)` prefers a
  `RaycastPart` attachment (the captured shape), falls back to a Seed/Detect
  one, and returns nil otherwise — nil means "drive".
- **The batch is verified, never trusted.** `spudFieldRemotePass(job, field,
  impl)` fires one call per remaining id (40 ms apart), then re-reads the
  stages: 0 left = `✅ remote seed: 50 cell(s) in 2.4s — the field is done
  without driving` and the sweep is skipped; some left = the sweep drives the
  remainder; none taken = the job is switched off **for the session** and the
  sweep drives (`remote seed: the game ignored 50 call(s) … — driving for this
  session`). A missing remote or attachment also disables that job once.
- **Sweep + fire** (v1.53, user: *"why dont we just make it tween and do that
  every 500ms so it's super fast"*, answered with **sweep + fire every 500 ms**).
  Hopping cell→cell is a teleport per id, so after the call pass
  `spudSweepCells(job, field, ride, impl, stage, baseCF, baseSize, att)` builds a
  serpentine over the remaining cells (rows 10 studs apart, starting at the
  nearest corner), tweens the ride along it at **45 studs/s** (the attachment
  lined up with the cell plane), and **every 0.5 s** — 22 studs at that speed —
  fires at the cells the blade passes. Two kinds of fire (v1.55, owner:
  *"it does not work so well with the plow"*): a **close fire every tick**
  (within **4 studs**, so a cell under the blade is called at once instead of
  waiting up to 22 studs for the next burst), and — for **plow/cultivate only**
  — the **every-0.5 s burst within 14 studs** the owner asked for in v1.54.
  A wide fire never blocks the close fire (that was the plow bug: the refused
  burst call marked the cell done, so it was never called with the blade over
  it); seed/harvest are close-only so seeds and tank space are not spent on
  cells the server refuses. Re-reads the stages, then runs a **second lap
  offset by half a row at 70 % speed** for whatever is left; the budget caps
  the calls (dry = hand the field back). The rest is `spudHopCells`' job, then
  the drive's, so the sweep can only add speed. Logs
  `remote seed: swept 46 cell(s) in 6.1s at 45 studs/s, range 14 — 44 took, 2
  left`.
- **It runs from the field, hitched and seated** — the same state the game fires
  the call from: the attempt sits at the top of `sweepField`, after the ride has
  arrived and the tool is hitched.
- **Plow / seed / harvest are siblings.** Only cultivate was recorded; the other
  three use the same `(field, {id}, {attachment})` shape at the same path
  (`EVTPlowFieldCell` FireServer, `FNCSeedFieldCell` / `FNCHarvestFieldCell`
  InvokeServer). If a build disagrees, the verification disables just that job
  instead of corrupting the pass.
- **Seeder fill** — `spudFillSeederRemote(seeder)` calls the captured
  `FNCFillSeeder(seeder)`; `buySeedAndFill` still presses V when the seed count
  does not rise, so a refusal costs one extra press, not a failed trip.
- **Tests tab · batch field remote** (v1.43, user: *"can we just abuse bugs to
  plow and harvest"*). The captured call already carries a **list** of ids
  (`{1=641}`), so with the Tests toggle on (`spudBatchRemotes`) the pass first
  fires **one call with every remaining id** via `spudFieldRemoteCallMany` and
  re-reads the stages: all gone = `✅ batch test: N cell(s) in ONE call` and the
  sweep is skipped; some taken = the rest go one call per cell; none taken =
  `batch test: the server ignored the id list … — one call per cell` and the
  normal per-cell pass runs. It is **off by default**, session-only, and an
  ignored list never switches a job off. The batch's own takes are counted into
  the final `✅ remote …` line.
- **Tests tab · live probes** (trimmed in v1.60, user: *"remove any tool we arenet
  using anymore in the bugs tab becuase it's getting crowsed"*). The tab now
  holds the **Batch field remote** toggle and two probes (`spudTestRun`,
  `spudTestWork`, `spudTestSay`; lines land in the Tests paragraph and as
  `test:` lines, and `spudTestCopy` puts place id + build + player + the whole
  `spudTestLog` on the clipboard with `setclipboard`):
  - **Remote list** (v1.59, user: *"we need to find another way of forcing the
    seeding and plowing"*) — read-only. Walks `ReplicatedStorage` (Modules
    first, depth 4, 600 nodes) and lists every `RemoteEvent`/`RemoteFunction`/
    `UnreliableRemoteEvent` by path. The per-cell field calls are only the ones
    the game fired by hand; a bulk/field door that was never fired would show
    up here and nowhere else.
  - **Wrong tool** — isolates the one check still untested: does the server
    care *which* tool the attachment belongs to, or only *where* the blade is?
    It reads the hitched implement (`hitchedImplementName`), works out its own
    verb, finds the nearest cell waiting for a **different** verb (cultivate →
    Plowed, plow → Empty, seed → Cultivated) within 8 studs of the blade, fires
    that verb with the hitched tool's own attachment, and waits on the stage.
    A take means one tool could plow, cultivate and seed in **one sweep** — the
    owner's "all in one go" without swapping implements.
  **Run all** runs both; both refuse while `loopThread` is live and touch no
  animals or other plots. There is **no harness** for them — the live read is
  the only verdict.
  **Removed once answered** (v1.44–v1.58; every result is in §5 and the console):
  From here / Wrong stage / No attachment / All at once (seat, stage and
  attachment are checked, and a multi-id list is only partly taken), Sell abuse
  (`EVTSellAtStore` ignores distance; an empty tank never pays twice), Grab from
  afar (carry works at 35 studs), Spawn from afar (works from anywhere), Fill
  from afar (refused at 963 studs), Field API (the module exports **no setter**;
  `UpdateCell`/`UpdateCells` are the client's own writers) and Force a tile.

**Is a tile forceable?** No. The live dump shows no setter, and Force a tile
(2026-10-30) ended `the client cell table is writable — UpdateCell kept the
forged Cultivated for 2 s` then `reads Cultivated — IGNORED: no update arrived`:
the server never reads the client's copy. A cell only holds `Alternate,
GrowthMultiplier, IsWatered, PlantGrowth, Position, SeedType, Stage` (50 cells,
`Stage=Plowed` on the live field). `spudSweepCells` therefore forces *position*,
not state — the only input the server accepts.

`field_remote_test.py` pins the ids, the attachment pick, the call shape, the
full/partial/ignored outcomes, the session switch-off, the fill fallback, the
hop and the sweep (a 15-cell field taken in one tween, the budget cutting it
short, and an ignored sweep leaving every cell standing).

### 3.13 Equipment actions fire the captured calls

User: *"use remoted for everything."* The same probe pass recorded the
equipment/action calls, so the loop now fires them instead of pressing keys or
driving the Equipment Manager UI. All live under `Modules.Larry`:

```
FNCEnterEquipment(vehicle, seat)
FNCAttemptHitch(tractor.Components.Hitchable, tool.Chassis.HitchableSocket)
FNCUnhitch(tractor.Components.Hitchable)
FNCSpawnEquipment(model) / FNCStoreEquipment(model)
EVTRequestToCarry(draggable) / EVTRequestToDrop()
```

- **Fired only where the game offers the action**: mount after the walk-up,
  hitch/unhitch at the same line-up pose the key needs, carry at the crate,
  spawn/store for a machine that is actually stored/out.
- **The effect is the proof** — the seat holding the humanoid
  (`spudEnterRemote`), the existing hitch/unhitch tug (`attemptHitch`,
  `dropImplementAtOrigin`), `InStorage` flipping (or a >100-stud move for a
  spawn that rebuilds the model) in `spudEquipRemoteAct`, and `carrying()`
  turning over for carry/drop.
- **Sell and buy** — `EVTSellAtStore(ride, pad)` is fired for the **Sell**
  destination (the tank dropping is the proof; Q/E after a 3 s grace), and
  `FNCRequestStorePurchase({crate})` is fired at the buy popup (balance or a
  new crate is the proof; the menu click is the fallback). **Fulfillment**
  makes no call and presses no key: the pad unloads a parked harvester itself
  (v1.41), so the trip only waits on the tank.
- **The old path always remains**: F for a mount, X for hitch/unhitch, E for a
  crate, the Equipment Manager UI for spawn/store. `spudEquipRemoteMiss` counts
  ignored calls; three switch that one action back to keys/UI for the session.
- **Not wired yet**: cleaning a stall, milking, herding, feeders and gates.
  Their shapes were never
  captured — `SpudRemoteProbe.lua` now has an **ACTION CALLS** section and a
  checklist for them (run it, or let one normal milk/barn cycle record while it
  runs), and `EQUIPMENT CALLS` confirms those above.

`equip_remote_test.py` pins the kit, the call shapes, the effect proofs, the
UI/key fallbacks and the three-miss switch-off.

---

## 4. Code map (names, not line numbers — they move)

| Area | Function / thing |
|---|---|
| Build identity | `VERSION` at the top of the file (`rebuild vX.YY · fluent gui`) |
| Pathfinding | top-level `SpudPath` (`heapPush`/`heapPop`, `astar`, `thetastar`, `search`, `los`, `clearance`, `smooth`, `markParts`, `worldParts`), then `pathfindAround`, `driveRoute`, `driveToField`, `driveWatchTick` |
| Farm width / owner | top-level `SpudFarm` (`widthTiles`, `widthFromParts`, `rowPlan`, `ownerWanted`, `workTiles`, `partBoxes`, `declaredWidth`), `spudOwnerChoices`, global `farmOwnerPick`, `spudFarmOwnerDrop`; `sweepField` plans rows from `rowPlan` |
| Go to the farm | global `spudFarmHop(here, plotPos)` (nil+reason, or centre +5 Y and distance), `milkStorePlotOf(who)`, `milkStandUp(who)` (default `"milk"`); wired at the top of `runFarmingBody` |
| Whose machine | global `equipOwnerRank(m)` (farm being worked → mine → no readable owner → never another account), used by `findTractor` / `findImplement`; owner tag read by `milkStoreOwnerOf` |
| Tree soil | global `spudTreeField(typeName, modelName)` (wood/tree/log/forest/timber/lumber/sawmill/stump → no crop harvest) and `spudNoCells(st)` (successful 0-cell read is empty, `nil` read is unknown); used in `probeWork`, `runPass`, `needLeft`, `grownLeft`, growth wait |
| Field remotes | global `spudFieldRemoteKit()` (Modules.Larry: plow/cultivate/seed/harvest/fillSeeder), `spudFieldCellIds(field, stage)` (GetCells keys), `spudToolAttachment(impl)`, `spudFieldRemoteCall`, `spudFieldRemoteCallMany` (Tests batch), `spudFieldRemotePass` (fires, re-reads, self-disables a job), `spudSweepCells` (serpentine tween, a burst every 0.5 s), `spudHopCells` (one cell at a time), `spudFillSeederRemote`; state `spudFieldRemoteState`, `spudBatchRemotes` (Tests toggle, default false); wired at the top of `sweepField` and in `buySeedAndFill` |
| Tests tab | `spudTestRun(kind)` (busy guard + pcall), `spudTestWork(kind)` (`remotes` / `wrongtool`), `spudTestRunAll`, `spudTestCopy` (`setclipboard`), `spudTestSay`, `spudTestLog`, `spudTestPara`/`spudTestShow`; buttons **Remote list**, **Wrong tool**, **Run all**, **Copy report** (the settled one-shots were removed in v1.60) |
| Equipment remotes | global `spudEquipRemoteKit/State` (enter/hitch/unhitch/spawn/store/carry/drop/sell/purchase), `spudEquipRemoteCall`, `spudEquipRemoteMiss`, `spudEquipRemoteAct` (spawn/store proof), `spudEnterRemote`, `spudHitchParts`, `spudHitchRemote`, `spudUnhitchRemote`, `spudCarryRemote`, `spudDropRemote`, `spudSellRemote`, `spudPurchaseRemote`; wired in `managerAction`, `mountTractor`, `attemptHitch`, `dropImplementAtOrigin`, `carryCrate`, the two held-item drops, `trySellAt` and `buySeedAndFill` |
| Row driving | `keyRow(tr, seat, from, goal, who)` drives rows on real W (the game auto-steers); global `spudRowSteer(angDeg, crossY, cross, tol)` (heading > 8°, cross-track > 2.5 studs → re-center); travel `ALIGN_MAXVEL = 34`, fallback row speed 18 |
| Dirt line | global `milkDirtLine = 24`; `milkDirtHigh(spot)` (the single "is this dirty?" answer) |
| Drop-off | global `spudDropOff` (**Fulfillment** / **Sell**, remembered in `spudSavedDropOff`), `spudSellNow(cur,max)`, `spudFulfillSpots()` (Deposit_Warehouse top), `findSellSpots()` (crop sell board), `sellHarvester` (arc hop + `trySellAt`), `harvestSellIfFull`; Farm tab dropdown `dropOffChoice` |
| Clean pass | pre-pass offer watch (0.96 s) → clean watch (2.2 s); per-cow clean `≤2.25 s` |
| Herd | `milkHerdBatch(stalls, cows)`, `milkHerdTargets`, `milkHerdSend`, ordering nearest-barn-first, `milkHerdArm` |
| Farm choice | `milkFarmReadyCount(who)`, `milkFarmSwitch(want, owner, readyHere, parkedHere)` |
| Barn lock | name + position, resolved by spot — see `milkBarnLive` / `milkBarnFor` |
| Cow reads | `milkCows`, `milkOwnerOf`, `milkPercentOf`, `milkStateOf`, `milkDrops` |
| Store | `milkStoreAmount`, `milkStoreDeposit`, `milkPollFor`, `milkFrame`; remotes `EVTRequestToCarry`, `EVTFillLiquidCarrier` (key path is the fallback) |
| GUI | Fluent shell, RIGHT SHIFT, 📡 webhook, 🥔 overlay; `spud-gui-preview.html` is a browser mock |

**Read-only probes** (run in game, paste the report): `SpudStallProbe.lua`
(stalls/dirt), `SpudDump.lua` (world structure, run twice: town + farm),
`SpudFieldProbe.lua` (every field's `FieldType`, its cells, what is planted
where, seed boxes and FieldHelper's tables), `SpudFulfillProbe.lua`
(Fulfillment / Shipment area: candidate models, unload pad parts, prompts,
signs, live context actions, and the old sell-pad targets), `SpudRemoteProbe.lua` (remotes
while you act by hand — milk calls plus the FIELD CALLS section for
plow/cultivate/seed/harvest/FillSeeder), `SpudBarnProbe.lua`,
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

**"it isnt farming in the right field … when it's wood it should work on the
wood soil" → "it's trying to harvest my trees but i dont want to"** → v1.28.
The tour still returns every field of the selected owner and `FieldType` was
only logged, so the full crop↔soil mapping is waiting on the read-only
`SpudFieldProbe.lua` report. The tree cut is fixed independently: the harvest
job treats any unknown stage as a standing crop, so `spudTreeField` now refuses
a harvest on a field whose type/name says wood/tree/log/forest/timber/lumber/
sawmill/stump (logged with the real type). `spudNoCells` applies rule 7 to cell
reads: a successful read with `total = 0` is an empty non-field and is skipped;
a `nil` read stays unknown. Applied in `probeWork`, both `runPass` decisions,
`needLeft`/`grownLeft` and the growth wait. New `field_soil_test.py`
(22 checks); suite **23/23**.

**"no but it's using the player it's working for's equipment then going on it's
own field"** → v1.29. Picking a farm did not replace my fields: `ownerWanted`
returned true for `ownerName == mine` *or* the pick, so the tour mixed both
owners — the pass hitched Miou2251's plow and then plowed my field. It is now
**one owner at a time** (`pick or mine`), so the machinery and the soil always
match. `(mine)` still means exactly mine. The tour line and each per-field line
now include the owner (`Field · Miou2251`), which is what made the mismatch
visible in the console. `farm_width_test.py` gained the two pick-vs-mine checks.

**"when it's on the field just let the game's thing that focuses is on the field
do its thing … it does not re-center … make it go faster"** → v1.30. The game
auto-steers a tractor on its field; the align mover fought it, and its aim
corrected heading only — a tractor parallel to the row but 2–6 studs beside it
had no heading error and never re-centered. Rows now run on real W (`keyRow`,
the harvester's proven driver) so the game steers; `spudRowSteer` nudges A/D
only for a heading error > 8° or a cross-track offset > 2.5 studs. Travel rose
from 24 to **34 studs/s**; the align mover is now only the row fallback (18),
so rows no longer run at its old 10-stud/s cap. New `row_steer_test.py`
(9 checks); suite **24/24**.

**"once the harvester is full just make it stop because we dont have the spot
yet … the place is called furfullement next to the shippement"** → v1.31. A full
tank used to start a sell trip against guessed pads (`SellArea` / `DropOffs`).
`spudSellWired = false` + `spudSellNow(cur,max)` now gate that: while unwired, a
full harvester logs
`stopping the run: the Fulfillment drop-off isn't wired yet`, clears
`loopThread` and switches the Farm toggle off, so the run ends instead of
driving somewhere wrong. `SpudFulfillProbe.lua` was added to dump the
Fulfillment / Shipment area (models, pad parts, prompts, signs, live context
actions, old pad targets). New `sell_gate_test.py` (7 checks); suite **25/25**.

**"also make it teleport to the spesific farm, find the tools then run"** →
v1.32. A picked farm was worked from wherever the character stood, so the far
plot's fields and machines had not streamed in when the scan ran. The run now
hops to the owner's plot first (`milkStorePlotOf` → `spudFarmHop`, >60 studs
only, centre +5 Y), standing the character up first because a seated CFrame
write does not replicate, waits 0.5 s for streaming, then finds **that
owner's** tractor/tool (§3.7) and logs `farm: using <tool> (<owner>) N studs
away`. `milkStandUp` takes a caller label now (`farm:` instead of `milk:`).
New `farm_hop_test.py` (7 checks); suite **26/26**. The Fulfillment dump the
owner pasted is useful (CompanyArea with Fulfillment/Shipment titles,
`Deposit_Warehouse` at -353,138,-90, `Withdraw_Warehouse` at -286,138,-217,
`UnloadTrailer` / `PullFactoryLever` / `TogglePipe` actions) but **not enough
to wire the unload**: the probe was run from the start point, not the pad, so
which action/key the pad offers with a full harvester is still unknown.

**"im telling you i ON the pad to furfull bro, make a option in the farm to
either furfull or sell bro"** → v1.33. The probe upgrade went in first: it now
reads `PCGP_ContextActions.Billboards` (only what is offered here, with each
action's key and adornee) instead of `Buttons` (the whole 70-action registry,
which is why two runs answered nothing). Then the Farm tab got **Drop-off**:
**Fulfillment** (default) drives the full harvester to the probed
`Stores.DropOffs.Deposit_Warehouse` top surface; **Sell** keeps the old crop
sell-board scan. The tank dropping is the only proof a pad took the load; a
failed trip backs off 60 s. `spudSellWired` is gone, so is `sell_gate_test.py` —
`dropoff_test.py` (17 checks) replaces it. Suite **26/26**.

**"when it's on someone elses plot make it not try to respawn things bro"** →
v1.34. Spawning/respawning goes through the game's Equipment Manager, which is
the owner's call: on a picked farm the run no longer brings anything out. The
shared `spudMayRespawn()` rule guards all three spawn sites (stored tractor, a
tractor past `RESPAWN_RANGE`, and `ensureToolNearby`); each one now logs the
machine, why (stored / N studs away) and that `(mine)` is how to spawn it.
New `foreign_respawn_test.py` (14 checks); suite **27/27**.

**"it is still going back and fourth bro like side to side, make it force the
alignement then jus tgo straight and let the game do the ajustments"** → v1.35.
The cross-track A/D nudge added in v1.30 was re-centering every 100 ms and
fighting the game's own steering — a visible side-to-side on every row. Now the
row is **snapped onto its line once** (`spudRowNeedsAlign`: heading > 8° or
offset > 2.5 studs, rows ≥ 20 studs only) and then driven with **W alone**;
`spudRowSteer` is heading-only, so a straight tractor presses no key. Short
Omega turns keep swinging through. `row_steer_test.py` rewritten (15 checks).

**"widen the steering range it takes bro it's like still going side to side
yo"** → v1.36. Still oscillating, so the band itself was too narrow for the
game's steering: 8° / 2.5 studs. It is now `spudRowAng = 15` and
`spudRowTol = 6`, and the row loop steers with **hysteresis** (engage past 15°,
release inside 7.5°) so the boundary cannot flip A/D back and forth. Both are
globals, so they can be retuned without touching the loop.

**"if it keeps going back and fourth with the seering make it slowly go slower
bro"** → v1.37. The throttle now eases itself: `spudRowEase` counts steering
flips, drops the row's duty to 70 % of what it was on the third flip (floor
30 %), and restores 10 % per steady 3 s. W is pulsed at 4 Hz when the duty is
below 100 %, so "slower" is real rather than a no-op. `row_steer_test.py` grew
to 23 checks.

**"i want to make the seeding and planting and things use remotes"** → v1.38.
The probe was extended for field captures; one manual cultivate pass recorded
`EVTCultivateFieldCell:FireServer(field, {cellId}, {raycastAttachment})`, and a
V at the seeder recorded `FNCFillSeeder:InvokeServer(seeder)`. A pass now fires
the game's own call for every remaining cell id (read from `FieldHelper.GetCells`)
with the hitched tool's RaycastPart attachment, re-reads the stages, and drives
only what the server did not take; a job that ignores the batch switches itself
back to driving for the session. Plow/seed/harvest reuse the captured shape
(siblings on the same path) behind the same verification. The seeder fill calls
the remote first and keeps V. New `field_remote_test.py` (24 checks); suite
**28/28**.

**"use remoted for everything"** → v1.39. The equipment calls the probe had
already recorded were wired with the same verify-then-fall-back rule:
`FNCEnterEquipment(vehicle, seat)` for a mount (the seat is the proof, F stays
the fallback), `FNCAttemptHitch(hitchable, socket)` / `FNCUnhitch(hitchable)`
inside the existing line-up + tug attempts (X stays the fallback),
`FNCSpawnEquipment` / `FNCStoreEquipment` in `managerAction` (the `InStorage`
flip or a >100-stud move is the proof; the Equipment Manager UI is the
fallback — this is where the old UI flow was slowest),
`EVTRequestToCarry` / `EVTRequestToDrop` for crates and held items. Three
ignored calls switch that one action off for the session. Cleaning, milking,
herding, fulfillment, feeders and gates are **not** wired yet: their shapes
were never captured, so the probe gained an ACTION CALLS section and a checklist
for them. New `equip_remote_test.py` (26 checks); suite **29/29**.

**Two more capture runs** → v1.40. The plow report confirmed the field shape
(`EVTPlowFieldCell(field, {id}, {plow RaycastPart})`), so plow is no longer an
inferred sibling. The sell/buy report added two actions: a **Sell** drop-off now
fires `EVTSellAtStore(harvester model, pad part)` before touching Q/E (the tank
dropping is the proof), and the seed buy fires
`FNCRequestStorePurchase({crate})` before clicking the popup (the balance or a
new crate is the proof). The two reports also showed no clean/milk/herd/fulfill/
feed/gate call, so those are still waiting on one targeted run.

**"the furfillement you dont gotta do anytihng just go ot the location and it
does it bro"** → v1.41. The Fulfillment pad unloads a parked harvester by
itself, so `trySellAt` gained the `autoPad` flag and the Fulfillment trip now
parks, logs `fulfillment pad …: parked — this pad unloads by itself, pressing
nothing`, and watches the tank for up to 16 s **without pressing Q or E**. The
Sell destination is unchanged (captured call, then Q/E after a 3 s grace), and
the tank dropping is still the only proof in both cases. `dropoff_test.py`
grew 9 checks that run `trySellAt` itself on a virtual clock: the Fulfillment
pad drops the load with **zero** keys and **zero** calls, a working Sell call
presses nothing, and an ignored Sell call still falls back to Q and E without
claiming a sale.

**"i found a but. when the harvester is coming back from somewhere it should
drop from higher, becuase right not it is coming from under"** → v1.42. The
arc hop kept the takeoff height at both ends, so the return leg from the
Fulfillment pad (~140) travelled under the field (~172) and popped up only at
the last frame. `hopTo` now lands at `max(takeoff, target.Y)` and lifts enough
to clear that landing by ~12 studs, so an upward trip arrives from above; a
downward trip is unchanged. New `hop_test.py` (15 checks) pins the landing
height, the clearance, the descent, level hops, a missing target Y, the
zero-length case and the stop; suite **30/30**.

**"wait can we just abuse bugs to plow and harvest and stuff bro" → "add it in a
new section called 'Tests'"** → v1.43. A new **Tests** tab (off by default)
holds the experiments. Its first entry, **Batch field remote**, abuses the fact
that the captured call already carries a *list* of ids: one call with every
remaining id, judged only by the stage re-read — all taken = the whole field in
one call, some taken = the rest go one call per cell, none taken = the list is
ignored and the normal per-cell pass runs (nothing is switched off). The
`field_remote_test.py` batch checks were added (8 more). Live result (the
owner's console, 2026-10-30): the 1-cell field took the list, the 48-cell field
logged `batch test: the server ignored the id list (48 still need it) — one call
per cell` — so the server takes **one id per call**.

**"maybe you can make a dump to try to find bugs to abuse"** → v1.44. The Tests
tab gained a four-button **bug finder** (`spudTestRun`/`spudTestWork`): **From
here** (one cell call with nobody seated, no hitch), **Wrong stage** (seed a
cell that is not cultivated), **No attachment** (empty attachment table) and
**All at once** (every id with no 40 ms spacing). Each writes one cell of our
own field, re-reads it, and prints `test: … TAKEN/IGNORED` plus the before/after
stage — manual experiments with no harness, since the live field is the only
judge.

**"i wnat to find ingame bugs we can abuse bro not the scripts bufgs" → "add a
button to test ALL bugs you can think of … and add a copy button"** → v1.45.
The bug finder grew to eight questions and two report buttons: **Sell abuse**
(`EVTSellAtStore` twice off-pad, then again on the emptied tank — distance and
double-sell, judged by the tank and `coinBalance`), **Grab from afar**
(`EVTRequestToCarry` on a distant SeedBox, dropped back afterwards), **Spawn
from afar** (`FNCSpawnEquipment` on a stored machine), **Fill from afar**
(`FNCFillSeeder` on a distant seeder, seeds and coins read), **Run all** and
**Copy report** (`setclipboard` of place id + build + player + every line).
The live answers so far (owner's report, 2026-10-30): seat, stage and
attachment are **IGNORED**, and a 48-id list is ignored — the field door is
closed — but **carry worked from 35 studs** (`SeedBox` grabbed and dropped
back) and **spawn worked from anywhere** (`S4204` rebuilt >100 studs away). The
fill and sell tests reported no seed field / no streamed pad, which is what
v1.46 fixes.

**First live bug report from the Tests tab** → v1.46. The user ran **Run all**
and copied the report: ride/stage/tool IGNORED (seat, stage and attachment are
checked), carry **TAKEN at 35 studs**, spawn **TAKEN from anywhere**; fill said
`seeds nil` and sell said `no sell pad found`, so both tests could not measure.
Fixes: sell pads now fall back to `spudFulfillSpots()` and a raw scan of
`SellArea`/`DropOffs`, and no streamed pad is stated instead of fired; the
seeder read accepts IntValue/NumberValue/attributes and, when still nil, dumps
the seeder's `Configurations` and attributes so the real seed field can be
named next run.

**"the harverster's contents arente getting sold vbro"** → v1.47. The v1.45
reports showed `sell: no sell pad found in the world` at three different spots:
`GameplayVisuals.SellArea` and `Stores.DropOffs` are streamed **with distance**,
so a full tank at the farm got an empty list and `sellHarvester` skipped the
unload entirely. It now hops the harvester to the store's own waypoint
(`storeAnchors`, then any `GotoLocations` marker named fulfil/ship/store/market),
waits 1.2 s for the area to stream, and looks again; `back` (the return target)
is captured before that hop so the trip back goes to the field, not the market.
Two more bugs from the same report: the `SellBoardSeeds` candidate had no `part`,
so `EVTSellAtStore` was never fired at the crop board (and the test crashed on
`s.part.Position`) — it now carries `part = g`; and the seeder's seeds are
`Capacity`/`MaxCapacity` (live dump: 0/50), not a "seed"-named value, so the
fill test read nil — it now reads that pair and reports `seeds s/m`.
`dropoff_test.py` grew 7 checks (streamed pad = one hop, no pad → store hop →
sell, trip back to the field, no marker = honest skip).

**v1.48** — the very next v1.47 report said `sell: the pads found carry no part
to fire at`. The rebuilt output list in `findSellSpots` copied `p/what/store/
dist/board` but **dropped `part`**, so every spot the trip used had no part for
`EVTSellAtStore`. Fixed (`part = c.part`), and `dropoff_test.py` now asserts
every returned spot carries a part (2 spots in the fixture). The same report
confirmed the fill reads `seeds 0/50` and the fill from 965 studs left it at
0/50 — the seeder fill needs proximity too.

**"ok, now we need to try to make it seed the wqhole fields" → "i meant
seeding plowing and all and harvesting bro"** → v1.49–v1.51. Every job got the
whole-field treatment. A **Sell** drop-off is fired from where the harvester
stands (`EVTSellAtStore` checks no distance: a full tank sold 46 studs away,
+150 coins, no double-sell on an empty one), so the pad trip is gone. Each job
is capped by the machine's own load — the seeder fires at most `Capacity`, the
harvester at most `MaxCapacity − Capacity` — and a cap that runs out hands the
field back instead of driving: the seeder refills (up to 3 shop trips in one
pass), the harvester sells and comes back. A refused tail gets **one retry of
just those** before any row is driven.

**"it wont do it all bor help fix it"** → v1.52. The live console showed the
ceiling: `batch test: 2 of 46 cell(s) took the id list` and
`remote plow: 6 of 46 cell(s) took the call in 3.9s — driving the last 40`.
**The server only accepts a cell whose blade is over it**, so one call per id
from the field edge can never finish a field. `spudHopCells` moved the ride
onto each remaining cell with the tool's attachment lined up and fired that one
id (`remote plow: hopped the ride over 46 cell(s) — 46 took`).

**"why dont we just make it tween and do that every 500ms so it's super fast"**
→ v1.53 (the owner picked **sweep + fire every 500 ms**). `spudSweepCells`
replaces the hop as the first fallback after the call pass: one serpentine
tween over the remaining cells at 20 studs/s, a burst every 0.5 s at the cells
the blade is passing (6 studs), a second lap offset by half a row for the ones
a burst skipped, then the hop for whatever is still standing, then the drive.
The seed/tank budget is enforced inside the sweep too (dry hands the field
back). `field_remote_test.py` gained the sweep checks; suite **30/30**.

**"it does not work so well with the plow bro"** → v1.55. The burst at 14
studs fired at every cell in reach and marked it done — the server refused the
far calls, so those cells were never called again with the blade over them,
and the plow came back with a field of leftovers while seeding (which the
server takes more readily) looked fine. Now the very tick a cell comes within
**4 studs** fires it, a wide burst can never block that close fire, and
seed/harvest skip the burst entirely so their budget is spent only on cells
the server takes. `field_remote_test.py` pins it with a blade-over server (all
15 cells taken, one call each) and a refused burst followed by a close fire.

**"that tween NEEDS to be faster, and have more range like before bro"** →
v1.54. The sweep ran at 20 studs/s and only fired at cells within 6 studs —
the old per-cell pass had fired at every id whatever the distance, so the
field took 12–15 s and skipped cells off the row. It now runs at **45 studs/s**
with a **14-stud** catch range, and the second lap slows to 70 % to aim; a
whole field crosses in 5–7 s. Same verification: the server decides, the hop
and the drive still take whatever it refuses.

**"isnt there a way we can force a tile to become tiles and stuff"** → v1.56.
The stage lives on the server — the owner's own Wrong-stage test answered
IGNORED — so writing `Stage` in `FieldHelper.GetCells` only edits a local
copy. Two Tests entries settle it for any build: **Field API** (read-only:
`FieldHelper`'s exports, what one cell holds, whether an export is a setter)
and **Force a tile** (forge an Empty cell to Cultivated, re-read after 2 s,
then fire seed on it — TAKEN would mean the server trusts the mirror). The
sweep therefore forces *position*, not state, since position is the only input
the server checks.

**Where it stands:** `rebuild v1.60 · fluent gui`, whole suite green (30/30),
harness verified. **Not yet reloaded in game** after v1.22–v1.46 — the next real
test is a live pass watching `path: … theta* N pops / N ms, min clear N`, the
new width line (`tool … — 3-wide …; rows every 30`), the Farm owner picker
showing ONLY that owner's fields (`Field · Miou2251`), the equipment owner
column (`· ZM80 = Tractor [spawned] · oksimba_1`), a
`SKIP … — <type> soil, trees are left alone` line on the wood field, the rows
being driven on W with the tractor re-centering after a drift, the
`farm owner: teleporting to …'s plot` hop followed by
`farm: using <tool> (<owner>)`, a full harvester taking the Drop-off trip
(`fulfillment pad: Deposit_Warehouse at (…` → `fulfillment pad … parked —
pressing nothing` → `✅ sold at …` or the honest
`still full — none of the pads took the load`), the milk lines
(`… read from here - none reports dirt`, `… cleaned in X.XXs`), the field
remote lines (`✅ remote seed: N cell(s) in X.Xs — the field is done without
driving`, or the honest `remote seed: the game ignored N call(s) … — driving
for this session`), and the equipment lines (`✅ mounted … (FNCEnterEquipment)`,
`equipment: Store KADL via store (no UI)`, `✅ carrying the … (EVTRequestToCarry)`,
`sell pad …: EVTSellAtStore(ride, pad)`,
`✅ <seed> bought via FNCRequestStorePurchase`) or their honest fallback lines
(`equipment: store didn't Store the KADL — using the Equipment Manager`,
`seed shop: FNCRequestStorePurchase didn't buy anything — clicking the menu`).

---

## 6. Open questions / known limits

1. **In-game confirmation is pending** for v1.22 (2 s clean wait), v1.23
   (meter trigger + no-cow-in-dirt gate), v1.24 (unload/reload guard, drop
   scoping, clean backoff), v1.25 (new path engine: watch the first `path:`
   lines and whether the tractor stops hugging gear), v1.26 (wide tools:
   check the `tool … — N-wide` line matches the real tool, and that a picked
   foreign farm actually accepts the drive-overs), v1.27 (owner-first
   equipment: check the owner column in the equipment log, and that a picked
   farm's tractor/tool is the one mounted), v1.28 (tree soil: the wood field
   must log `SKIP … — <type> soil, trees are left alone`, and a normal pass must
   still harvest the crop field), v1.29 (one owner at a time: with a farm
   picked, the tour must list ONLY that owner's fields and never mine), v1.30
   (real-W row driving: watch for a `tractor: the W row drive handed back`
   fallback line and whether rows actually re-center after a drift), v1.31
   (a full harvester must stop the run and NOT drive to a sell pad), v1.32
   (a picked farm: `farm owner: teleporting to …'s plot` must appear once, the
   fields must stream in, and the mounted tool must be that owner's) and v1.33
   (the Drop-off pick: a full tank must hop to the chosen pad and the tank must
   drop; if it does not, the log names the pad and whether a menu opened) and
   v1.34 (a picked farm: no `Equipment Manager` line may appear for a stored or
   far machine — the run must name it and stop/skip instead), v1.35 (rows: no
   side-to-side — the tractor may snap once onto the row and must then run
   straight with the game's own steering holding it), v1.36 (the 15°/6-stud
   band: a row should now tolerate a visible drift without touching A/D) and
   v1.37 (a swinging row: watch for `steering is swinging — easing the row to
   N% throttle` and whether the wobble settles at the lower duty) and v1.38
   (field remotes: cultivate is the only recorded shape — a seed/plow/harvest
   job must log `✅ remote X: N cell(s) in X.Xs` and leave the field finished,
   or the honest `remote X: the game ignored N call(s) … — driving for this
   session`; the seeder fill must log `seeder fill: FNCFillSeeder(seeder)` and
   the count must rise, with V only on a refusal) and v1.39 (equipment remotes:
   watch `✅ mounted … (FNCEnterEquipment)`, `equipment: Store/Spawn … via …
   (no UI)`, `✅ carrying … (EVTRequestToCarry)`; a refused call must log its
   fallback and the old F/X/E/UI path must still complete the step) and v1.40
   (sell/buy: a **Sell** drop-off must log `sell pad …: EVTSellAtStore(ride,
   pad)` and the tank must drop; a seed buy must log `✅ <seed> bought via
   FNCRequestStorePurchase` with the balance falling — otherwise the Q/E and
   menu-click fallbacks must finish the step) and v1.41 (Fulfillment: the trip
   must log `fulfillment pad … parked — this pad unloads by itself, pressing
   nothing`, press **no** key, and the tank must still drop; if it does not, the
   log must say `the pad didn't take it while parked`) and v1.42 (the arc hop:
   the return trip from a lower pad must climb and **come down** onto the field
   — watch `arc hop: N studs, lifting N studs (Y 140 → 172)` — not fly under
   the ground; a trip to a lower pad must still land at the takeoff height) and
   v1.43 (Tests → **Batch field remote**: with the toggle on, a field job must
   log `batch test: N cell id(s) in ONE call` and then either
   `✅ batch test: … in ONE call` (one call finished the field) or
   `batch test: the server ignored the id list … — one call per cell` with the
   normal per-cell pass still finishing it) and v1.44 (Tests → bug finder: press
   each button once and read its `test: … TAKEN/IGNORED` line — the answer is
   the cell's own stage, so quote the before → after in the report) and v1.45
   (Tests → **Run all** then **Copy report**: the copy must carry place/build/
   player and every line; the sell test needs a FULL harvester, the fill test a
   spawned KADL, the spawn test a stored machine of mine) and v1.46 (the sell
   test must name the pad it picked or say no pad is streamed; the fill test
   must either read the seed count or dump the seeder's fields so the next run
   can name it) and v1.47 (a full harvester with no pad streamed must log
   `no Sell pad is streamed from here — arc hop to the store`, then sell at the
   board; the fill test must read `seeds 0/50` and say whether the fill took)
   and v1.48 (every sell spot the trip receives must carry a `part`; the test
   must fire `EVTSellAtStore` instead of saying "no part to fire at") and v1.49
   (a full tank with any sell pad streamed must log `sell: EVTSellAtStore fired
   from where the harvester stands` and then `✅ sold in place … (no pad trip)`
   with the ride never moving; a refusal must still take the pad trip) and v1.50
   (a seed pass must log the seeder's budget / `seeder EMPTY … refill 1/3`, the
   shop trip must refill, and the same pass must carry on until the field is
   seeded; a refill that puts nothing in must stop it) and v1.51 (harvest: a
   full tank must log `the tank is full … the sell trip runs before the rest`
   and fire no harvest call; any refused tail must log
   `one retry of just those` and then `the retry finished the field`) and v1.52
   (a field after the call pass must log `remote <job>: hopped the ride over N
   cell(s) — N took`; if the count reaches 0 the field ends with **no row
   driven**, otherwise the drive starts from the last hopped cell).
   and v1.53 (a field job must log `remote <job>: swept N cell(s) in X.Xs at
   45 studs/s, range 14 — N took, N left`; a taken sweep finishes the field
   with **no row driven**, and any leftover must still be hopped and then
   driven), v1.54 (the sweep must cross a field in ~5–7 s and catch cells
   well off the row; anything the server refuses must still be hopped) and
   v1.55 (a plow field must finish on the sweep: watch that its leftovers are
   not a row of missed cells, and that the log's `took` is close to `swept`)
   and v1.59 (Tests → **Remote list** then **Wrong tool**: paste both. A
   remote that looks like a field/bulk door names the next experiment; a
   `TAKEN` wrong-tool verdict means one hitched tool can run every stage in a
   single sweep) and v1.57/v1.58 (Tests → **Force a tile**: the live FieldHelper dump has
   **no setter**, and the client cell table is **writable** (`UpdateCell` keeps
   a forged stage), so the remaining question is whether the server uses it —
   the verdict is `reads Seeded` = TAKEN (a real abuse) or `reads Cultivated`
   = IGNORED (client-only lie). Paste that one line).
   Harness green ≠ game green.
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
