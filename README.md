# 🥔 SPUD FARM — Farming and Friends scripts

> **Status: clean rebuild in progress.** The current build is a *skeleton* — GUI
> shell + console + 🔄 reload only, no game features. Features are being re-added
> one at a time and tested in-game. The full previous version is preserved in the
> git history.

## UI RULES (non-negotiable, per project owner)
1. **No text under anything.** Elements get a title and nothing else: no window
   SubTitle, no Description lines under buttons/toggles, no helper text, no
   placeholder sub-text. Titles only. This applies to every future feature.
2. The window must stay comfortably large on mobile/emulator screens (use
   `Resize = true` and a generous base Size).

## Quick start (using the script)
1. Copy the raw script link:
   `https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua`
2. Paste that link into your executor's script box (or open the file here, click
   **Raw**, copy everything) and execute.
3. In game: **RIGHT SHIFT** = menu · **📡** = webhook panel · **🥔** = hide/show all.

Free VIP servers (this game has them) + short sessions = far lower report risk.
Read the Stealth section below before farming in public servers.

## Files

### `SpudFarm_Full.lua` — THE MAIN SCRIPT (use this one)
Everything merged into one paste-and-run file:
- **Farm tab** — Farming auto-cycle (PLOW → CULTIVATE → PLANT → GROW → HARVEST → SELL),
  **crop selector** (Wheat, Corn, Rice, Oat, Sugar Cane, Soybeans, Tomatoes, Cabbage,
  Carrots, Potatoes, Cocoa, **Grape**, Custom) with auto set grow-time from wiki data,
  a **live crop info line** (grow time · seed cost/box · avg $/hr · equipment
  requirements · price-rotation tip), auto seed-loading during PLANT, Auto-Sell,
  Grow time slider, Skip Stage / Reset buttons, live status line,
  **live sell-price readout** (reads the in-game SellValueBoards every 3s)
- **Presets tab** — **Barn Care** (walks every stall near your plot and cleans it —
  uses the game's own CleanAnimalContainer = V context), Chocolate Milk
  (clean stalls → milk cows → deposit → cocoa → levers → collect → sell),
  Cake & Eggs (**7 steps**: eggs → milk → wheat/milk/egg deposits → 4 levers →
  **batter → oven bake** → collect + sell), Wool Run (shear → spindel bundles,
  5 wool each → sell); LOOP toggle, STOP button
- **Milk tab** — **three Farm pickers worked in a rotation** (farm 1 → 2 → 3;
  a slot left on "(none)" is skipped, farm 3 wraps back to farm 1, and a farm
  takes over as soon as the current one has nothing left to milk). A farm that
  **cannot fill one herd batch** is skipped too: a pass on a farm with fewer
  ready cows than the typed amount hands the next pass to the first farm in the
  rotation that can fill one, so the batch is never run short while another
  farm has the cows. Cleaning still happens first — a dirty stall is never
  skipped — and a farm with cows **already parked in its stalls** is never
  skipped either, because there is milk to take. When **no** farm can fill a
  batch the current one is worked exactly as before, so a small farm cannot
  stall the loop. The check reads the other farms without moving the character
  (see `milkFarmReadyCount`) and never treats a farm it cannot read — streamed
  out, not built yet — as empty. The whole rule lives in one function
  ([tools/farm_batch_test.py](tools/farm_batch_test.py) exercises the real one:
  30 checks). The **herd
  batch size typed in a box
  (1–12)**, **Store milk in** (live list of the picked account's trailers/silos;
  only free-range jugs are loaded there), **Deliver all milk** switch, **Refill
  feed dispenser** switch (tops the plot's FeedDispenser up from the
  AnimalFoodBoxes), live status paragraph, **milk loop** toggle. The loop cleans
  dirty stalls first, then **milks any cow already waiting in a stall**, herds
  the batch in picking the **cows nearest the barn first** (a far cow can't hold
  the round up), **milks each cow the moment it lands in its stall** and waits
  for the next one — it does not sit until the whole herd is parked — and a
  finished round goes **straight into the next one** (no idle gap); only a pass
  with nothing to do rests for a minute. If a plot has **more than one barn
  building**, the first cycle locks to one of them (the one nearest the plot
  centre)  for the rest of the session, so stalls, the parked count, the batch
  and the lasso press are never split across two barns. That lock is held as
  **name + where the building stands**, not as the model itself: a barn that
  streams out and comes back is a *new* instance, and matching it by identity
  used to leave the herd step with no barn at all — it then fell back to the
  first building named `AutoWoodenBarn` in the map, which is another player's,
  so the cows were herded and sent to the wrong barn (or nowhere). The bug, its
  reproduction and the fix are in
  [tools/herd_send_test.py](tools/herd_send_test.py)
- **Player tab** — walkspeed, jump power, infinite jump, noclip, anti-AFK, FPS boost
- **Teleport tab** — Ctrl+Click teleport + FarmCo / AnimalCo / TractorCo / LumberCo /
  Bulk Store / Warehouse / **My Farm** (resolves your plot by its "Your Farm"
  billboard) / Spawn buttons (2026 central-town map, part names from in-game dump)
- **Stealth tab** — detection-risk reduction (see below)
- **Settings tab** — Movement mode (**VFly** = fast BodyVelocity fly + snap teleport,
  **Tween** = slow safe glide) + vfly speed slider; fix in-game names (cow, milker, shop,
  factory, field tile, sell key, tractor, **planter, harvester, batter drop, oven**)
  without touching code; unload button
- **Webhook window** (📡 button in the title bar) — its own UI with URL box, enable
  toggle, test button, **live feed** (every farm round, preset cycle and stealth
  break appears instantly, even with logging off) and a queue status line.
  Sends to your own Discord webhook, rate-limited (≈1 msg / 6.5s) with coin-gain notes
- **🥔 potato button** (left edge of the screen, its own overlay) — press it to hide
  **every** window at once (main + webhook), press again to bring them all back. It
  stays visible while everything else is hidden, and you can drag it anywhere
- Menu keybind: **RIGHT SHIFT** (same as the potato: toggles all windows)

Wiki-accurate details baked in (researched 2026): FarmCo selling = drive onto the
elevated platform → **Q** (opens sell menu) → **E** (confirms); **prices rotate every
~5 min** — red/green/rainbow boards, rainbow = peak (wait for it on big potato/tomato
hauls); real equipment names (ZM80 tractor, SRC6 combine, KGF 3000 planter, AED300
lvl-2 seeder, Oxbo3220 cocoa harvester, TK500/chainsaw forestry); factory levers pulled
one-by-one in the exact wiki sequences.

Recipes: **Chocolate Milk** = 25 cocoa + 10 regular milk (or 5 free-range, 2:1;
spoiled milk rejected) per jug, ~20–23k coins, max 60/run; **Cake** = 100 wheat + 1 egg
box (12 eggs) + 1 milk → batter → oven; **Wool** = 5 raw wool per spindel bundle.
Cow happiness decides milk quality (<60% spoiled, 60–89% regular, 90%+ free-range).
The milk store step only loads **free-range** jugs — regular and spoiled are left
on the ground for selling (`store: leaving N non-free-range jug(s)`).

### Speed — what was actually slow
Measured, not guessed. The deposit pass now prints its own time:
`store: 20 jug(s) into LH150 in 5.8s (100/180)`.

- **`task.wait(t)` is frame-quantised.** It sleeps *at least* `t` and then
  resumes on the next Heartbeat, so at 60 FPS `task.wait(0.2)` costs 200–216 ms
  and a loop of them is pure stand-still. The store step now polls **every
  frame** (same deadline in seconds, so a high-FPS client does not give up
  early) against a read the game already answers: the jug leaving the world,
  the hand filling, the tank label changing.
- **`FireServer` does not wait for a reply.** Only the *result* has to come back,
  so the fast path is one network round trip per action, not a fixed sleep.
- **A CFrame teleport needs ~50 ms to reach the server** (physics replication is
  ~20 Hz), so the step waits three frames after a teleport instead of 150–250 ms.
- **GUI-shaped reads stay at 50 ms**, not per frame: `milkMenuFor`, `milkStallGui`
  and `milkDrops` walk the GUI/world, so polling them per frame would cost more
  CPU than it saves.

Measured with [tools/store_timing.py](tools/store_timing.py) (virtual clock, real
extracted functions, `task.wait` modelled as frame-quantised): a 10-jug pass at
120 ms latency went **5.42 s → 2.75 s** (0.54 → 0.27 s per jug), at 40 ms it went
**4.08 s → 1.50 s**. Arm-the-herd (`milkHerdArm`) went **1.6 s → ~0.05 s** per cow
when the menu is up, and the old 3.6 s "no menu" timeout is 3.0 s
([tools/herd_arm_test.py](tools/herd_arm_test.py)). The rest of the time is the
cows walking in and the server's own answer — no script can remove those.

**The cow checks, cached.** A scan (`milkCows`) reads three things off every
animal in the world, and the Owner read walks up to eight parents per animal
looking for a `Configurations.Owner` when the animal has none - which is most of
them. The **instances** are now remembered per model in a weak-keyed table, so a
repeat read is one property access. Measured on a fake 120-animal world (40 tagged,
80 strays) with the real functions ([tools/cow_scan_bench.py](tools/cow_scan_bench.py)):
**1400 → 560 instance calls per scan** (11.7 → 4.7 per cow) once warm; the cold
pass is unchanged, and an animal is never cached as untagged, so a cow that gets
its owner a moment later is still picked up. The **arrival wait** no longer scans
at all while nothing is happening: it watches the plot's own stall `Occupant`
values (12 parts, ~30 reads) and only scans when a cow that was not milked yet
turns up parked. [tools/milk_arrivals_test.py](tools/milk_arrivals_test.py) counts
the scans: 6 scans over the 12.6 s a five-cow batch took, where the old code
scanned on every 200 ms poll (~60).

**The stall scan, narrowed.** Finding one barn's stalls was
`workspace:GetDescendants()` plus a name compare per instance — and this game has
~112,531 instances (run-3 dump), so every pass built that table to find a dozen
parts. The stalls are `<barn>.Spots.<n>.Adornee_BarnStallMenu` and barns are the
models in `Objects.Buildings`, so the scan now starts at those few buildings (and
at the barn the farm is already locked to, which is one building). Measured on a
95k-instance fake map with 8 barns and the real functions
([tools/stall_scan_bench.py](tools/stall_scan_bench.py)): **95,517 calls + 95,410
name reads per pass → 73 calls + 0 name reads** once the barn is locked, 101 on
the first pass, 380 if the distance prune takes nothing out. Same 12 stalls kept,
and the whole-map walk still runs as a fallback if a layout matches none of this.
The stall's `Occupant` value is cached per stall too (the arrival wait reads it
five times a second, and the milk step reads it per cow), so a repeat read is one
property access instead of two instance calls. The pass now prints the scan time:
`milk: 12 stall(s) found by the narrow scan in 0 ms - ...`.

**The clean pass, without the teleport tour.** Asking "is this stall dirty?"
used to mean **teleporting into all twelve stalls every pass** — 0.2 s for the
teleport to settle plus a 0.3 s floor before the first read, so a barn with
nothing to clean still cost twelve teleports and 6.00 s of standing still, every
single pass. The answer is read without moving, and the pass only visits a stall
that **reports** dirt. What the live build actually uses was named by
`SpudStallProbe.lua`: the stall folder (`<barn>.AnimalContainer.Spots.<n>`) carries
**`FilthLevel`** (0–4, how many of its four stain levels are showing) and
`FilthPercentage`. **`FilthLevel > 0` is the trigger** — it is the game saying
dirt is drawn there, readable from the plot centre. `FilthPercentage` is
**deliberately not** a trigger: the probe found 24% on a stall whose every stain
was still invisible, so treating the meter as dirt would put the twelve-stall
tour straight back. If a build loses the attribute, the **same answer is read
from the drawing**: `Filth/Level1..Level4` are the four level meshes and every
one of them is `Transparency = 1` while its level is clean, so the count of
visible ones is `FilthLevel` by another route and needs no teleport either. The
folder is only trusted when it actually holds `Level` parts — any other `Filth`
shape falls through instead of answering "0". For builds without any of that, a
direct `Filth` child (the old dump's shape), a nested value, an attribute (`Filth`
/ `Dirt` / `Grime`) or a dirty-named child are all still read.

A build that exposes **none** of those used to fall back to visiting all twelve
(every stall "unreadable" = a visit), which is exactly the tour this was meant
to remove — the console said `12 of 12 stall(s) need a visit (no readable dirt)`.
That fallback is **gone**: an unreadable stall is **never** a reason to move, it
is cleaned at the stall itself while a cow there is milked (the game only offers
Clean while you stand in that stall anyway), and the console names the stall and
lists what it actually holds **once per session**, so a build whose dirt lives
somewhere unexpected can be pointed at exactly instead of guessed at. A clean
barn is **0 teleports and 0.00 s** (`milk: 12 stall(s) read from here - none
reports dirt, so no teleports`). Measured with
[tools/clean_visit_test.py](tools/clean_visit_test.py) (virtual clock, real
extracted functions, a fake 12-stall barn): **12 teleports / 6.00 s → 0 / 0.00 s**
on a clean barn, **12 → 1** when one stall is dirty, **12 → 0** when the dirt is
unreadable, **12 → 1** for dirt given as an attribute or as a nested value (both
of which the old read missed entirely), **12 → 1** for dirt that is only drawn as
visible `Level` meshes and **12 → 0** when those meshes are all hidden, and a
stall that keeps refusing Clean still gets the same three attempts.

**Letting a cow out, from where we stand.** Opening the stall gate used to
**always** hop to `Gate.ProximityPart` and sleep a flat 0.9 s first — even though
the game's `BarnDoorInteract` billboard names *that* gate (its `Adornee` is the
gate's own part) wherever the press comes from, and after milking a cow the
character is already standing in its stall. So the hop now happens only when the
action is **not** already offered *and* the character is not already within 8
studs of the gate, and a retry polls from where it stands instead of jumping to
the same stud again (two inline poll loops collapsed into one helper, so the file
has two fewer `task.wait` sites than before). Measured with
[tools/gate_visit_test.py](tools/gate_visit_test.py): **1 teleport / 1.60 s → 0 /
0.00 s** when the door is already offered, **4 → 1** hop in the path where the
game never offers the action at all, and a gate that is *already open* is still
never pressed again (that press would shut it on the cow).

**Farms are teleported to, not walked to.** A distant plot is streamed *out* of
workspace, so the pass saw "no plot" and moved on - a farm that was never really
looked at. Each farm's plot centre is remembered on first sight; when the plot is
missing the character teleports to the remembered centre and waits up to 4 s for
the plot to stream back in, and when the plot is visible but we are more than 200
studs away the pass jumps to it before reading anything (every other step already
teleports to its own target, so the walk was the only slow part of a farm change).

Economy (per seed box = 50 crops, average prices): Wheat ≈3,000/hr … **Tomatoes
≈7,686/hr** (best field crop), Potatoes ≈7,500/hr, Cabbage ≈6,500/hr; Cocoa raw ≈5,625/hr
but is meant for chocolate milk (S-tier); Pine logs ≈19,500/hr; Cypress logs ≈63,000/hr.
Animal prices: chicken 1,500 · sheep 3,000 (Sheep License ~7,200 XP) · cow 4,500;
cows/barns are free of license, eggs feed the Cake + Scrambled Egg factories.
Joining the Dunn Games Roblox group (Farmer's Club) adds **+5% sell value**.
Licenses gate shops (Goals system) — the script can't buy locked stock for you.

### Stealth / "undetected" — what it can and cannot do
Roblox detection has three layers. **No Luau script can affect layer 1:**
1. **Hyperion/Byfron (client integrity)** — detects the *executor* (injection, hooks,
   unsigned modules). Depends entirely on your executor being currently patched.
2. **Server movement validation** — flags instant teleports / huge speeds.
   Mitigations built in: **two movement modes** — VFly (BodyVelocity fly +
   snap teleport, fast; the default) or Tween (slow stepped glide, safer) —
   Walkspeed/Jump clamps, NoClip force-blocked in stealth, all actions via
   real context-key binds (F/X/E/V) via virtual input (no RemoteEvent guessing =
   no honeypot risk). **One exception:** the milk store step fires two remotes
   *recorded from the game itself* (`EVTRequestToCarry`, `EVTFillLiquidCarrier`)
   to skip the context-button wait. Nothing is trusted: a jug only counts once
   it is in `CarryLinks`, a fill only once the tank rises, three ignored calls
   put the key path back for the session.
3. **Behavioral/ML scoring** — flags robotic timing, 24/7 sessions, crowded-server
   play. Mitigations built in: ±40% timing jitter, random micro-pauses, session
   limiter (auto-break, default 45 min on / 4 min off).

**Honest limits:** these reduce risk, they do not make you invisible. Use a **free VIP
server** (this game has them), keep sessions short, and consider an alt account.
Running 24/7 in public servers is the fastest way to get reported regardless.

**"Modified client" is layer 1, not layer 2 or 3.** That exact wording is
Hyperion/Byfron reporting the **injector** (or a patched Roblox build — FPS
unlockers that patch the client, modded mobile APKs), not your movement or timing.
No edit to this script can change it: every line here runs *after* the executor has
already injected, and the check fires on the injection itself. Tween mode, quieter
timings and shorter sessions do **nothing** for that notice. The only lever is not
injecting on that account.

**If you get a warning, stop on that account.** Roblox enforcement escalates —
notice, then short bans (1/3/7 days), then permanent — and a warned account's next
catch comes faster than the first. Read the exact wording under Account → Settings
→ Violations & Appeals. If it names exploiting / a modified client, standing down
means standing down: don't relaunch the executor "just to test" a build. If you
ever resume in a stock client, the loudest *script* signal is the **snap teleport**
(`root.CFrame = ...`, one jump per jug, many per minute): Tween movement plus the
key-only milk path (no fast remote) is the quietest this gets.

**The probes are louder than the farm loop.** `SpudRemoteProbe.lua`, `SpudDump.lua`
and the other scrapers hook `game`'s `__namecall` with `getrawmetatable` /
`hookmetamethod`. The farm script itself never touches the metatable — it only
presses keys and writes CFrames. If the warning came right after running a probe,
that is the more likely trigger; don't run them on an account you care about.

### `FarmingAndFriends_Main.lua` — earlier generic version
Generic crop-plot script (attribute/remote auto-detection). Kept as a fallback;
`SpudFarm_Full.lua` supersedes it for Farming and Friends.

### `spud-gui-preview.html` — GUI preview
Interactive browser preview of the GUI look/feel — open it in any browser.

### `SpudDump.lua` — in-game structure scraper (read-only)
Run it **in game** (MuMu + Delta supported) to build a text report of the live game
structure: proximity prompts, tools, your plot's tiles, equipment names, NPCs,
vehicles, remotes, signs and the **live sell-price boards**. It sends nothing
anywhere by itself — it uploads the report to a random unlisted paste link,
prints the link and copies it to your clipboard. Roblox streams objects in
near you, so run it twice: once **in town** (zoomed out) and once **at your
farm standing among your fields/animals/barn**, then send both links back so
guessed names in `CONFIG` can be replaced with real ones.

### `SpudStallProbe.lua` — one stall folder, dumped (read-only)
The clean pass decides "dirty?" from where the character stands, so it needs the
stall's own dirt field. The dump's shape (`Spots.<n>.Filth`) is not what every
build exposes — one live build answered nothing at all — so this probe dumps
**one whole stall folder**: every descendant with its class, value and
attributes, every part with its transparency/position, which stain parts are
actually **visible**, every dirt-sounding instance in the stall / barn / plot
with its full path, and the game's own `CleanAnimalContainer` billboard (what it
is adorned to, whether it is enabled, and the key it prints). It presses nothing,
teleports nothing and writes nothing, and the whole report is also shown in a
small on-screen panel with **COPY REPORT** / **CLOSE** (the report is put on the
clipboard as soon as it finishes). Stand on the farm and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudStallProbe.lua?t=" .. os.time()))()
```

Paste everything it prints (one block, prefixed `[STALL]`); the path list at the
end is what names the field exactly.

### `SpudRemoteProbe.lua` — what the game SENDS (read-only)
Run it in game, then do one milk deposit **by hand** (pick up a jug, press Fill at
the truck, milk one cow) and run `spudRemoteStop()`. It records every
`FireServer` / `InvokeServer` the game itself makes, with the exact remote name
and arguments, lists every remote in `ReplicatedStorage`, uploads the report and
copies the link to the clipboard. It fires nothing. A small on-screen panel has
**Copy report**, **Upload & stop** and **Stop (no upload)** so neither step needs
the executor console. The report it produced is what the milk store step now
uses: `EVTFillLiquidCarrier(<carrier>)` and `EVTRequestToCarry(<jug>)` are fired
as a fast path, with the key presses kept as the fallback whenever the world does
not confirm the result.

### `SpudBoot.lua` — loader that shows its own errors
A tiny (~8 KB) launcher for when the executor console is not visible: it
downloads `SpudFarm_Full.lua`, compiles it and runs it, and puts every step in a
small on-screen panel — downloaded byte count, the build string, and the exact
compile or runtime error if one happens (also copied to the clipboard so it can
be pasted into chat). Paste this one line:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudBoot.lua?t=" .. os.time()))()
```

## Contributing / fixing names
Found a wrong in-game name after a game update? Open an issue (or PR) with the
correct name and which feature it affects — Settings-box defaults live in the
`CONFIG` block at the top of `SpudFarm_Full.lua`.

## Codes (status: disabled)
As of mid-2026 Dunn Games has **temporarily removed code redemption** (confirmed by the
community manager; the medal-icon Social menu accepts nothing). Sites listing "working"
codes (HARVESTDAY, COINBLAST, …) are fake lists. Expired real codes: NOSPAM, DunnGames,
Seniac, BunnyFilms. Watch the official Discord for when redemption returns.

## Name fixing
The game updates its internals often. If a feature can't find its target
(e.g. milking does nothing), open **Settings**, use a workspace explorer /
remote spy to find the real in-game name, and type it into the matching box.
You can list **several guesses separated by commas** (e.g. `Milker, Udder Tool`) —
any candidate matching an in-game name will be used.
The wiki-sourced defaults (Cow, Milker, FarmCo, KGF, SRC6, …) are best guesses.

## Executor compatibility
Synapse X, Xeno, Delta, Wave, Solara, Fluxus, etc. (uses getgenv/gethui/cloneref
with fallbacks where available).
