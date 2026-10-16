--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD DUMP — in-game structure scraper (READ-ONLY)
═══════════════════════════════════════════════════════════════════════════
  What it does:  reads public game data (names, prompts, tools, GUI text)
                 and builds one text report. It SENDS NOTHING anywhere —
                 the report is only copied to your clipboard and (if your
                 executor supports it) written to a file.

  HOW TO USE (MuMu Player + Delta):
    1. Execute this script IN GAME — only AFTER your character has spawned
       and you can walk around (it now waits up to 45s for the character,
       so loading screens no longer produce empty sections).
    2. Stand in TOWN (near the roundabout / stores) with camera zoomed all
       the way out, so as much of the map as possible is loaded.
    3. Run it — it uploads the dump and PRINTS A LINK (like
       https://paste.rs/AbC123). Copy that short link and send it back.
       Roblox only loads nearby stuff (streaming), so run it TWICE:
         run 1 in town → send link 1
         run 2 AT YOUR FARM (fields/animals/barn in view) → send link 2
    4. If upload fails (blocked site), it falls back to setclipboard —
       paste anywhere in Android (a notes app works) and send the text.
       writefile also saves "spud_dump.txt" inside the executor folder.

  The dump contains public game data + your username — treat the link like
  you'd treat the dump itself (send it to the script author only).
═══════════════════════════════════════════════════════════════════════════
]]

local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local StarterPack  = game:GetService("StarterPack")
local StarterGui   = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local out = {}
local function w(s) out[#out + 1] = s end
local function header(t) w(""); w(""); w("══════ " .. t .. " ══════") end

-- path like "Workspace.Town.FarmCo.Platform" (max 5 levels)
local function pathOf(inst, maxLevels)
    local parts, cur, depth = {}, inst, 0
    while cur and cur ~= game and depth < (maxLevels or 5) do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
        depth += 1
    end
    return table.concat(parts, ".")
end

-- "FieldTile23" -> "FieldTile"  (group numbered duplicates)
local function baseName(n)
    return (n:gsub("[%d%s]+$", ""))
end

local ok, err = pcall(function()
    -- wait for the character BEFORE scanning: run 1 came back with empty
    -- prompts/tools because it executed during loading (no root part yet)
    local waited = 0
    while waited < 45 do
        local ch = LocalPlayer.Character
        if ch and ch:FindFirstChildOfClass("Humanoid") and ch:FindFirstChild("HumanoidRootPart") then
            break
        end
        waited += 1
        task.wait(1)
    end
    task.wait(3) -- let streaming pull in nearby objects

    local desc = Workspace:GetDescendants() -- one big scan, reused below

    ------------------------------------------------------------------
    w("SPUD DUMP — Farming and Friends structure report")
    w("placeId: " .. tostring(game.PlaceId) .. "   jobId: " .. tostring(game.JobId))
    local ch = LocalPlayer.Character
    -- NOTE: HRP's ClassName is "Part" — must look up BY NAME, not class
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    w("player: " .. LocalPlayer.Name .. "   pos: " .. (hrp and tostring(hrp.Position) or "?")
        .. (hrp and ("   hrpClass=" .. hrp.ClassName) or ""))
    local ct = ch and ch:FindFirstChild("CurrentTool")
    w("  CurrentTool = " .. tostring(ct and ct.Value or nil))
    w("character diagnostics:")
    w("  LocalPlayer.Character = " .. tostring(ch))
    if ch then
        w("  character parent = " .. tostring(ch.Parent) .. "  children = " .. #ch:GetChildren()
            .. "  has HRP = " .. tostring(hrp ~= nil))
        local hum = ch:FindFirstChildOfClass("Humanoid")
        w("  humanoid = " .. tostring(hum) .. (hum and ("  state=" .. tostring(hum:GetState())) or ""))
    end
    local wsMe = Workspace:FindFirstChild(LocalPlayer.Name)
    w("  workspace self-model = " .. tostring(wsMe)
        .. (wsMe and ("  HRP=" .. tostring(wsMe:FindFirstChild("HumanoidRootPart") ~= nil)) or ""))
    if identifyexecutor then
        pcall(function() w("executor: " .. tostring(identifyexecutor())) end)
    end
    w("instances in workspace: " .. #desc)

    ------------------------------------------------------------------
    -- 1. WORKSPACE TOP LEVELS (2 levels, capped)
    ------------------------------------------------------------------
    header("WORKSPACE TREE (2 levels)")
    local kids = Workspace:GetChildren()
    table.sort(kids, function(a, b) return a.Name < b.Name end)
    for _, v in ipairs(kids) do
        if v.Name ~= "Terrain" and v.Name ~= "Camera" then
            local sub = v:GetChildren()
            w(v.Name .. "  [" .. v.ClassName .. "]  children: " .. #sub)
            local shown = 0
            for _, c in ipairs(sub) do
                if shown >= 25 then
                    w("    … +" .. (#sub - shown) .. " more")
                    break
                end
                w("    - " .. c.Name .. " [" .. c.ClassName .. "]")
                shown += 1
            end
        end
    end

    ------------------------------------------------------------------
    -- 2. PROXIMITY PROMPTS + CLICK DETECTORS (WHOLE GAME, not just
    --    workspace — two runs found 0 prompts in workspace, so check
    --    ReplicatedStorage/PlayerGui/StarterGui too)
    ------------------------------------------------------------------
    header("PROMPTS + CLICK DETECTORS (whole-game scan)")
    local prompts, clicks = {}, {}
    local gdesc = game:GetDescendants()
    for _, o in ipairs(gdesc) do
        if o:IsA("ProximityPrompt") then
            local key = tostring(o.ActionText) .. " | " .. tostring(o.ObjectText)
            local e = prompts[key]
            if e then
                e.count += 1
            else
                prompts[key] = { count = 1, path = pathOf(o.Parent, 6) }
            end
        elseif o:IsA("ClickDetector") then
            local e = clicks[o.Name]
            if e then
                e.count += 1
            else
                clicks[o.Name] = { count = 1, path = pathOf(o.Parent, 6) }
            end
        end
    end
    w("  scanned instances: " .. #gdesc)
    local keys = {}
    for k in pairs(prompts) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then
        w("  ProximityPrompts: NONE ANYWHERE (game uses custom menu/key interactions)")
    end
    for _, k in ipairs(keys) do
        local e = prompts[k]
        w("  PROMPT \"" .. k .. "\"  ×" .. e.count .. "  @ " .. e.path)
    end
    local ckeys = {}
    for k in pairs(clicks) do ckeys[#ckeys + 1] = k end
    table.sort(ckeys)
    if #ckeys == 0 then w("  ClickDetectors: NONE") end
    for _, k in ipairs(ckeys) do
        local e = clicks[k]
        w("  CLICK  \"" .. k .. "\"  ×" .. e.count .. "  @ " .. e.path)
    end

    ------------------------------------------------------------------
    -- 3. TOOLS (StarterPack / Backpack / equipped)
    ------------------------------------------------------------------
    header("TOOLS")
    for _, o in ipairs(StarterPack:GetChildren()) do
        if o:IsA("Tool") then w("  [StarterPack] " .. o.Name) end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, o in ipairs(bp:GetChildren()) do
            if o:IsA("Tool") then w("  [Backpack] " .. o.Name) end
        end
    end
    if LocalPlayer.Character then
        for _, o in ipairs(LocalPlayer.Character:GetChildren()) do
            if o:IsA("Tool") then w("  [Equipped] " .. o.Name) end
        end
    end

    ------------------------------------------------------------------
    -- 4. PLAYER VALUES (leaderstats etc — fixes coin tracking)
    ------------------------------------------------------------------
    header("PLAYER VALUES")
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            local val = "?"
            pcall(function() val = tostring(v.Value) end)
            w("  leaderstats." .. v.Name .. " [" .. v.ClassName .. "] = " .. val)
        end
    else
        w("  (no leaderstats)")
    end
    for _, v in ipairs(LocalPlayer:GetChildren()) do
        if v:IsA("ValueBase") then
            w("  player." .. v.Name .. " [" .. v.ClassName .. "] = " .. tostring(v.Value))
        end
    end
    for k, val in pairs(LocalPlayer:GetAttributes()) do
        w("  attr." .. tostring(k) .. " = " .. tostring(val))
    end
    for k, val in pairs(game:GetAttributes()) do
        w("  game-attr." .. tostring(k) .. " = " .. tostring(val))
    end

    ------------------------------------------------------------------
    -- 5. NPCs / SHOP KEEPERS (models with a Humanoid)
    ------------------------------------------------------------------
    header("NPCs / SHOP KEEPERS  (model name ×count @ path)")
    local npcs = {}
    for _, o in ipairs(desc) do
        if o:IsA("Humanoid") then
            local model = o.Parent
            if model and model ~= LocalPlayer.Character and model.Name ~= "Humanoid" then
                local key = model.Name
                local e = npcs[key]
                if e then
                    e.count += 1
                else
                    npcs[key] = { count = 1, path = pathOf(model, 4) }
                end
            end
        end
    end
    local nkeys = {}
    for k in pairs(npcs) do nkeys[#nkeys + 1] = k end
    table.sort(nkeys)
    for _, k in ipairs(nkeys) do
        w("  " .. k .. "  ×" .. npcs[k].count .. "  @ " .. npcs[k].path)
    end

    ------------------------------------------------------------------
    -- 6. VEHICLES (VehicleSeat → owning model)
    ------------------------------------------------------------------
    header("VEHICLES")
    local vseen, vcount = {}, 0
    for _, o in ipairs(desc) do
        if o:IsA("VehicleSeat") then
            vcount += 1
            if vcount <= 80 then
                local m = o:FindFirstAncestorOfClass("Model")
                w("  seat \"" .. o.Name .. "\"  in  " .. (m and pathOf(m, 3) or "?"))
            end
        end
    end
    w("  (total VehicleSeats: " .. vcount .. ")")

    ------------------------------------------------------------------
    -- 7. REMOTES (names only — helps understand game systems)
    ------------------------------------------------------------------
    header("REMOTES (ReplicatedStorage, names only)")
    local rcount = 0
    for _, o in ipairs(ReplicatedStorage:GetDescendants()) do
        if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") then
            rcount += 1
            if rcount <= 300 then
                w("  " .. o.ClassName .. "  " .. pathOf(o, 4))
            end
        end
    end
    w("  (total remotes: " .. rcount .. ")")

    ------------------------------------------------------------------
    -- 8. WORKSPACE TEXT (signs, price boards, store labels)
    ------------------------------------------------------------------
    header("WORKSPACE TEXT (signs / boards / labels, deduped)")
    local texts = {}
    for _, o in ipairs(desc) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and o:IsA("GuiObject") then
            local t = o.Text
            if type(t) == "string" and t ~= "" and #t < 150 then
                local p = pathOf(o, 5)
                -- skip floods: global leaderboard numbers, emote popups, top3 HTML
                if not p:find("Leaderboard.ScrollingFrame", 1, true)
                    and not p:find("EmotePopup", 1, true)
                    and not p:find("Top3", 1, true) then
                    local e = texts[t]
                    if e then
                        e.count += 1
                    else
                        texts[t] = { count = 1, path = p }
                    end
                end
            end
        end
    end
    local tkeys = {}
    for k in pairs(texts) do tkeys[#tkeys + 1] = k end
    table.sort(tkeys)
    for _, k in ipairs(tkeys) do
        w("  \"" .. k .. "\"  ×" .. texts[k].count .. "  @ " .. texts[k].path)
    end

    ------------------------------------------------------------------
    -- 9. KEYWORD PARTS (grouped by base name — fields, sells, animals…)
    ------------------------------------------------------------------
    header("KEYWORD PARTS (grouped: FieldTile23 → FieldTile)")
    local kws = {
        "sell", "chute", "platform", "pad", "store", "shop", "barn", "coop",
        "feeder", "spindel", "loom", "oven", "lever", "conveyor", "seed",
        "field", "plot", "tile", "soil", "milk", "cocoa", "cow", "sheep",
        "chicken", "egg", "wool", "tractor", "trailer", "hitch", "animal",
        "tree", "log", "factory", "sawmill",
        -- v2: implements, menus, storage
        "combine", "harvest", "seeder", "plow", "cultiv", "implement",
        "silo", "board", "menu", "adornee", "station", "bay",
    }
    local kwMap = {}
    for _, o in ipairs(desc) do
        if o:IsA("BasePart") then
            local n = o.Name:lower()
            for _, kw in ipairs(kws) do
                if n:find(kw, 1, true) then
                    local m = kwMap[kw]
                    if not m then m = {}; kwMap[kw] = m end
                    local b = baseName(o.Name)
                    m[b] = (m[b] or 0) + 1
                end
            end
        end
    end
    for _, kw in ipairs(kws) do
        local m = kwMap[kw]
        if m then
            local names = {}
            for k in pairs(m) do names[#names + 1] = k end
            table.sort(names, function(a, b) return m[a] > m[b] end)
            w("  [" .. kw .. "]")
            for i, nm in ipairs(names) do
                if i > 20 then w("    … +" .. (#names - 20) .. " more base names"); break end
                w("    " .. nm .. "  ×" .. m[nm])
            end
        end
    end

    ------------------------------------------------------------------
    -- 10. GAME GUIs (store menus, sell popup — names + 2 levels)
    ------------------------------------------------------------------
    header("PLAYER GUIs (top level + 2 levels, capped)")
    local guiSeen = 0
    for _, gui in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
        if guiSeen >= 25 then break end
        guiSeen += 1
        w("  " .. gui.Name .. " [" .. gui.ClassName .. "]")
        for _, c in ipairs(gui:GetChildren()) do
            local label = c.Name
            if c:IsA("GuiObject") and c:IsA("TextLabel") then label = label .. "  text=\"" .. tostring(c.Text) .. "\"" end
            w("    - " .. label .. " [" .. c.ClassName .. "]")
        end
    end

    ------------------------------------------------------------------
    -- 11. STARTERGui (what GUIs the game gives you — sell menu etc.)
    ------------------------------------------------------------------
    header("STARTERGUI (names + 2 levels, capped)")
    local sgSeen = 0
    for _, gui in ipairs(StarterGui:GetChildren()) do
        if sgSeen >= 25 then break end
        sgSeen += 1
        w("  " .. gui.Name .. " [" .. gui.ClassName .. "]")
        for _, c in ipairs(gui:GetChildren()) do
            local label = c.Name
            if c:IsA("GuiObject") and (c:IsA("TextLabel") or c:IsA("TextButton")) then
                label = label .. "  text=\"" .. tostring(c.Text) .. "\""
            end
            w("    - " .. label .. " [" .. c.ClassName .. "]")
        end
    end

    ------------------------------------------------------------------
    -- 12. MY PLOT (own farm deep — tiles, structures, animals)
    ------------------------------------------------------------------
    header("MY PLOT (own farm deep)")
    local plots = Workspace:FindFirstChild("Plots")
    local myPlot
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            if plot:IsA("Model") then
                local bb = plot:FindFirstChild("PlotBillboard")
                local owner = bb and bb:FindFirstChild("Owner")
                if owner and owner:IsA("TextLabel") then
                    w("  plot " .. plot.Name .. ": owner = \"" .. owner.Text .. "\"")
                    if owner.Text == "Your Farm" or owner.Text == LocalPlayer.DisplayName
                        or owner.Text == LocalPlayer.Name then
                        myPlot = plot
                    end
                end
            end
        end
    else
        w("  (no Plots folder)")
    end
    if myPlot then
        w("  >>> MY PLOT: " .. myPlot.Name)
        w("  direct children:")
        for _, c in ipairs(myPlot:GetChildren()) do
            w("    - " .. c.Name .. " [" .. c.ClassName .. "]")
        end
        local g = {}
        for _, d in ipairs(myPlot:GetDescendants()) do
            local b = baseName(d.Name)
            g[b] = (g[b] or 0) + 1
        end
        local gk = {}
        for k in pairs(g) do gk[#gk + 1] = k end
        table.sort(gk, function(a, b) return g[a] > g[b] end)
        w("  descendant names (grouped, top 60):")
        for i, k in ipairs(gk) do
            if i > 60 then w("    … +" .. (#gk - 60) .. " more"); break end
            w("    " .. k .. "  ×" .. g[k])
        end
    else
        w("  (own plot not identifiable — see billboard owner texts above)")
    end

    ------------------------------------------------------------------
    -- 13. OBJECTS (spawned equipment / fields / animals / buildings)
    ------------------------------------------------------------------
    header("OBJECTS (equipment / fields / animals / buildings)")
    local objects = Workspace:FindFirstChild("Objects")
    if objects then
        for _, grp in ipairs(objects:GetChildren()) do
            w("  " .. grp.Name .. " [" .. grp.ClassName .. "] ×" .. #grp:GetChildren())
            local shown = 0
            for _, c in ipairs(grp:GetChildren()) do
                if shown >= 40 then w("    … +" .. (#grp:GetChildren() - shown) .. " more"); break end
                w("    - " .. c.Name .. " [" .. c.ClassName .. "]")
                shown += 1
            end
        end
    else
        w("  (no Objects folder)")
    end

    ------------------------------------------------------------------
    -- 14. STORES + LIVE SELL BOARDS (item → current price, High/Low key)
    ------------------------------------------------------------------
    header("STORES + SELL BOARDS (live values)")
    local stores = Workspace:FindFirstChild("Stores")
    if stores then
        for _, grp in ipairs(stores:GetChildren()) do
            w("  " .. grp.Name .. " [" .. grp.ClassName .. "] ×" .. #grp:GetChildren())
            if grp.Name ~= "Buildings" and grp.Name ~= "SellValueBoards" then
                for _, c in ipairs(grp:GetChildren()) do
                    w("    - " .. c.Name .. " [" .. c.ClassName .. "]")
                end
            end
        end
        local sv = stores:FindFirstChild("SellValueBoards")
        if sv then
            for _, node in ipairs(sv:GetDescendants()) do
                if node.Name == "List" and node:IsA("GuiObject") then
                    w("  board list @ " .. pathOf(node, 7))
                    for _, row in ipairs(node:GetChildren()) do
                        local nl = row:FindFirstChild("NameLabel")
                        local vl = row:FindFirstChild("ValueLabel")
                        if nl and vl and nl:IsA("GuiObject") and vl:IsA("GuiObject") then
                            w("    " .. tostring(nl.Text) .. " = " .. tostring(vl.Text))
                        end
                    end
                elseif node.Name == "Key" and node:IsA("GuiObject") then
                    w("  key @ " .. pathOf(node, 7))
                    for _, c in ipairs(node:GetChildren()) do
                        local extra = ""
                        if c:IsA("GuiObject") then
                            extra = "  visible=" .. tostring(c.Visible)
                                .. "  bgTransp=" .. tostring(c.BackgroundTransparency)
                        end
                        if c:IsA("TextLabel") then
                            -- color reveals which tier (High/Low) is currently active
                            local col = c.TextColor3
                            extra = extra .. string.format("  textColor=%.2f,%.2f,%.2f",
                                col.R, col.G, col.B)
                        end
                        w("    - " .. c.Name .. " [" .. c.ClassName .. "]" .. extra)
                    end
                end
            end
        end
    else
        w("  (no Stores folder)")
    end

    ------------------------------------------------------------------
    -- 15. GUI VIEWS DEEP (HUD = where the coin counter lives)
    ------------------------------------------------------------------
    header("GUI VIEWS deeper (GuiViews.HUD / Menus / Stores)")
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gv = pGui and pGui:FindFirstChild("GuiViews")
    if gv then
        for _, grp in ipairs(gv:GetChildren()) do
            w("  " .. grp.Name .. " [" .. grp.ClassName .. "]")
            local shown = 0
            for _, c in ipairs(grp:GetDescendants()) do
                if shown >= 40 then w("    … more"); break end
                local line = "    - " .. pathOf(c, 5) .. " [" .. c.ClassName .. "]"
                if (c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox"))
                    and c:IsA("GuiObject") then
                    line = line .. "  text=\"" .. tostring(c.Text) .. "\""
                elseif c:IsA("ValueBase") then
                    pcall(function() line = line .. "  value=" .. tostring(c.Value) end)
                end
                w(line)
                shown += 1
            end
        end
    else
        w("  (no GuiViews)")
    end

    ------------------------------------------------------------------
    -- 16. ANIMAL MENU — the FULL interaction button list
    --     (menu replaces ProximityPrompts: cow click → menu → buttons)
    ------------------------------------------------------------------
    header("ANIMAL MENU BUTTONS (full interaction list)")
    local foundMenu = false
    if pGui then
        for _, o in ipairs(pGui:GetDescendants()) do
            if o.Name == "AnimalInteractionMenu" then
                foundMenu = true
                w("  menu @ " .. pathOf(o, 6))
                local list = o:FindFirstChild("InteractionsList", true)
                if list then
                    w("  interaction buttons:")
                    for _, b in ipairs(list:GetChildren()) do
                        if b:IsA("GuiButton") then
                            local t = ""
                            local tt = b:FindFirstChild("temp_text", true)
                            if tt and tt:IsA("TextLabel") then t = tostring(tt.Text) end
                            w("    - " .. b.Name .. "  text=\"" .. t .. "\"")
                        end
                    end
                else
                    w("  (no InteractionsList inside)")
                end
                break
            end
        end
    end
    if not foundMenu then
        w("  (menu not in PlayerGui — click a COW once, then re-run this script)")
    end

    ------------------------------------------------------------------
    -- 16b. CONTEXT ACTIONS — what the game will accept RIGHT NOW.
    --      Billboards mirror each action; Enabled=TRUE means the action
    --      is in range at the player's current spot. Stand next to a cow
    --      (or lever / coop / seeder) with production full, then dump.
    ------------------------------------------------------------------
    header("CONTEXT ACTIONS (HUD.PCGP_ContextActions — Enabled = active here)")
    local cpa = pGui and pGui:FindFirstChild("GuiViews")
        and pGui.GuiViews:FindFirstChild("HUD")
        and pGui.GuiViews.HUD:FindFirstChild("MainHUD")
    cpa = cpa and cpa:FindFirstChild("PCGP_ContextActions")
        or (pGui and pGui:FindFirstChild("GuiViews")
            and pGui.GuiViews:FindFirstChild("HUD")
            and pGui.GuiViews.HUD:FindFirstChild("PCGP_ContextActions"))
    if cpa then
        local bills = cpa:FindFirstChild("Billboards")
        if bills then
            w("  billboards (Enabled = context active at player pos):")
            local act = 0
            for _, b in ipairs(bills:GetChildren()) do
                if b:IsA("GuiBase2d") then
                    local e = (b:IsA("GuiObject") and b.Enabled) or false
                    if e then act += 1 end
                    w("    - " .. b.Name .. "  Enabled=" .. tostring(e)
                        .. (e and "  <== ACTIVE HERE" or ""))
                end
            end
            w("  active count: " .. act)
        else
            w("  (no Billboards folder)")
        end
        local btns = cpa:FindFirstChild("Buttons")
        if btns then
            w("  button templates (Bind):")
            local n = 0
            local function listBtns(folder, depth)
                for _, b in ipairs(folder:GetChildren()) do
                    if n >= 120 then return end
                    if b:IsA("GuiObject") then
                        local bind, label = "", ""
                        local bd = b:FindFirstChild("Bind")
                        if bd then bind = tostring(bd.Text or bd.Value or "") end
                        local al = b:FindFirstChild("ActionLabel")
                        if al then label = tostring(al.Text or "") end
                        local vis = (b.Visible and b:IsA("GuiObject")) and "visible" or "hidden"
                        w("      " .. b.Name .. "  bind=" .. bind .. "  label=" .. label .. "  (" .. vis .. ")")
                        n += 1
                    end
                    if b:IsA("Folder") and depth < 2 then listBtns(b, depth + 1) end
                end
            end
            listBtns(btns, 0)
        end
    else
        w("  (PCGP_ContextActions not found in PlayerGui)")
    end

    ------------------------------------------------------------------
    -- 17. COIN / MONEY DISPLAY HUNT (fixes getCoins)
    ------------------------------------------------------------------
    header("COIN / MONEY DISPLAY HUNT")
    if pGui then
        local hits = 0
        for _, o in ipairs(pGui:GetDescendants()) do
            if hits >= 60 then w("  … cap reached"); break end
            local n = o.Name:lower()
            if n:find("coin", 1, true) or n:find("cash", 1, true) or n:find("money", 1, true)
                or n:find("balance", 1, true) or n:find("dollar", 1, true)
                or n:find("wealth", 1, true) or n:find("bank", 1, true) then
                local line = "  " .. o.Name .. " [" .. o.ClassName .. "]  @ " .. pathOf(o, 6)
                if o:IsA("ValueBase") then
                    line = line .. " = " .. tostring(o.Value)
                elseif o:IsA("GuiObject") and (o:IsA("TextLabel") or o:IsA("TextButton")) then
                    line = line .. "  text=\"" .. tostring(o.Text) .. "\""
                end
                w(line)
                hits += 1
            end
        end
        if hits == 0 then w("  (nothing named coin/cash/money… in PlayerGui)") end
        -- every HUD text label (the coin counter lives in here somewhere)
        local hud = gv and gv:FindFirstChild("HUD")
        if hud then
            w("  HUD text labels:")
            for _, o in ipairs(hud:GetDescendants()) do
                if o:IsA("GuiObject") and o:IsA("TextLabel") and o.Text ~= "" then
                    w("    " .. o.Name .. " = \"" .. tostring(o.Text) .. "\"  @ " .. pathOf(o, 6))
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- 18. SEEDBOX DEEP (how the crop TYPE is stored inside a seed box)
    ------------------------------------------------------------------
    header("SEEDBOX / DRAGGABLE DEEP")
    local dobjs = objects and objects:FindFirstChild("DraggableObjects")
    if dobjs then
        local shown = 0
        for _, m in ipairs(dobjs:GetChildren()) do
            if (m.Name == "SeedBox" or m.Name == "AnimalFoodBox") and shown < 4 then
                shown += 1
                w("  " .. m.Name .. " #" .. shown .. "  @ " .. pathOf(m, 4))
                for k, v in pairs(m:GetAttributes()) do
                    w("    attr." .. tostring(k) .. " = " .. tostring(v))
                end
                local dshown = 0
                for _, d in ipairs(m:GetDescendants()) do
                    if dshown >= 30 then w("    … more"); break end
                    local line = "    - " .. d.Name .. " [" .. d.ClassName .. "]"
                    if d:IsA("ValueBase") then
                        line = line .. " = " .. tostring(d.Value)
                    elseif d:IsA("GuiObject") and (d:IsA("TextLabel") or d:IsA("TextButton")) then
                        line = line .. "  text=\"" .. tostring(d.Text) .. "\""
                    end
                    w(line)
                    dshown += 1
                end
            end
        end
        if shown == 0 then w("  (no SeedBox/AnimalFoodBox in DraggableObjects)") end
    else
        w("  (no DraggableObjects)")
    end

    ------------------------------------------------------------------
    -- 19. PLOT CONFIGURATION (my plot's stored state)
    ------------------------------------------------------------------
    header("PLOT CONFIGURATION (my plot state)")
    if myPlot then
        local cfg = myPlot:FindFirstChild("Configurations")
        if cfg then
            for k, v in pairs(cfg:GetAttributes()) do
                w("  attr." .. tostring(k) .. " = " .. tostring(v))
            end
            for _, d in ipairs(cfg:GetDescendants()) do
                local line = "  - " .. d.Name .. " [" .. d.ClassName .. "]"
                if d:IsA("ValueBase") then line = line .. " = " .. tostring(d.Value) end
                w(line)
            end
        else
            w("  (no Configurations child in plot)")
        end
    else
        w("  (no myPlot)")
    end
end)

w("")
w("══════ END OF DUMP ══════")
if not ok then w("NOTE: scraper stopped early: " .. tostring(err) .. " (partial dump above)") end

local text = table.concat(out, "\n")

------------------------------------------------------------------
-- OUTPUT: upload link first (easiest on mobile), then clipboard/file
------------------------------------------------------------------
local function httpPost(url, body, contentType)
    local fn = nil
    if type(request) == "function" then fn = request end
    if not fn and type(http_request) == "function" then fn = http_request end
    if not fn and type(http) == "table" and type(http.request) == "function" then fn = http.request end
    if not fn then return nil end
    local okRes, res = pcall(fn, {
        Url     = url,
        Method  = "POST",
        Headers = {
            ["Content-Type"] = contentType or "text/plain; charset=utf-8",
            ["User-Agent"]   = "Mozilla/5.0 (X11; Linux x86_64)",
        },
        Body = body,
    })
    if okRes and type(res) == "table" then return res end
    return nil
end

local function urlFrom(res, wantStatus)
    if not res or not res.Body or type(res.Body) ~= "string" then return nil end
    if wantStatus and res.StatusCode ~= wantStatus then return nil end
    if wantStatus == nil and res.StatusCode and res.StatusCode >= 300 then return nil end
    return res.Body:match("(%s*https?://%S+)%s*$") or res.Body:match("^(%s*https?://%S+)")
end

-- dump must be reasonably sized for public paste services
local uploadUrl = nil
if #text < 900000 then
    uploadUrl = urlFrom(httpPost("https://paste.rs/", text), 201)
        or urlFrom(httpPost("https://0x0.st", text))
end

local gotClipboard = pcall(function()
    assert(setclipboard, "no setclipboard")
    setclipboard(text)
end)
local gotFile = pcall(function()
    assert(writefile, "no writefile")
    writefile("spud_dump.txt", text)
end)

print("══════════════ SPUD DUMP DONE ══════════════")
print("lines: " .. #out .. "   bytes: " .. #text)
if uploadUrl then
    print("✔ UPLOADED — link (also copied to clipboard):")
    print("   " .. uploadUrl)
    pcall(setclipboard, uploadUrl) -- short link goes to clipboard, easier than selecting console text
else
    print("✘ upload failed (site blocked or no 'request' in executor)")
end
if gotClipboard then
    print("✔ also copied to CLIPBOARD — paste into a notes app as backup")
else
    print("✘ no setclipboard in this executor")
end
if gotFile then
    print("✔ also saved as spud_dump.txt in the executor's file folder")
else
    print("✘ no writefile in this executor")
end
if not uploadUrl and not gotClipboard then
    print("NOTE: nothing else worked — screenshot the console output instead.")
end
print("════════════════════════════════════════════")
