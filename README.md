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
