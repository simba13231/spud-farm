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
                    -- BillboardGui is NOT a GuiObject — read Enabled directly
                    local okE, e = pcall(function() return b.Enabled end)
                    e = okE and e == true
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

    ------------------------------------------------------------------
    -- 20. EQUIPMENT MANAGER (which coded model is the plow?)
    --     open the Equipment Manager in-game BEFORE running the dump,
    --     so its labels are populated
    ------------------------------------------------------------------
    header("EQUIPMENT MANAGER GUI (open it first!)")
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local guiViews = pg and pg:FindFirstChild("GuiViews")
    local menus = guiViews and guiViews:FindFirstChild("Menus")
    if menus then
        w("GuiViews.Menus children:")
        for _, m in ipairs(menus:GetChildren()) do
            local en = (m:IsA("LayerCollector") or m:IsA("GuiObject"))
                and ("  Enabled=" .. tostring(m.Enabled)) or ""
            w("  - " .. m.Name .. " [" .. m.ClassName .. "]" .. en)
        end
    else
        w("  (no PlayerGui.GuiViews.Menus)")
    end
    -- find equipment-related GUIs anywhere in PlayerGui
    local roots, seen = {}, {}
    local function addRoot(d)
        if d and not seen[d] then
            seen[d] = true
            roots[#roots + 1] = d
        end
    end
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            local n = d.Name:lower()
            if n:find("equip", 1, true) or n:find("garage", 1, true)
                or n == "vehicleselection" then
                addRoot(d)
            end
        end
    end
    w("equipment-named GUI hits: " .. #roots)
    if #roots == 0 then
        w("  (nothing — is the Equipment Manager open?)")
    end
    local shown = 0
    for _, d in ipairs(roots) do
        if (d:IsA("LayerCollector") or d:IsA("GuiObject")) and shown < 100 then
            w("  ▸ " .. pathOf(d, 6))
            for _, t in ipairs(d:GetDescendants()) do
                if (t:IsA("TextLabel") or t:IsA("TextButton")) and shown < 100 then
                    w("      " .. t.Name .. "  text=\"" .. tostring(t.Text) .. "\"")
                    shown += 1
                end
            end
        end
    end
    if shown >= 100 then w("      … text cap reached") end

    ------------------------------------------------------------------
    -- 21. EQUIPMENT MODELS deep (attributes / configuration = type?)
    ------------------------------------------------------------------
    header("EQUIPMENT MODELS deep (attributes + configuration)")
    local eqFolder = Workspace:FindFirstChild("Objects")
        and Workspace.Objects:FindFirstChild("Equipment")
    if eqFolder then
        for _, m in ipairs(eqFolder:GetChildren()) do
            if m:IsA("Model") then
                w("  " .. m.Name .. " [" .. m.ClassName .. "]")
                local any = false
                for k, v in pairs(m:GetAttributes()) do
                    w("    attr." .. tostring(k) .. " = " .. tostring(v))
                    any = true
                end
                for _, cfgName in ipairs({ "Configurations", "Configuration" }) do
                    local cfg = m:FindFirstChild(cfgName)
                    if cfg then
                        w("    " .. cfgName .. ":")
                        for _, d in ipairs(cfg:GetDescendants()) do
                            local line = "      - " .. d.Name .. " [" .. d.ClassName .. "]"
                            if d:IsA("ValueBase") then
                                line = line .. " = " .. tostring(d.Value)
                            end
                            w(line)
                        end
                        any = true
                    end
                end
                if not any then w("    (no attributes or configuration)") end
            end
        end
    else
        w("  (no Objects.Equipment folder)")
    end

    ------------------------------------------------------------------
    -- 22. HITCH PROMPT LIVE (run this with the X button showing!)
    --     reads EXACTLY what SpudFarm_Full.hitchPromptUp() reads, so we
    --     can confirm the path/class/flag before trusting the creep loop
    ------------------------------------------------------------------
    header("HITCH PROMPT LIVE (X visible on screen right now?)")
    -- mirror SpudFarm_Full.hitchPromptUp() EXACTLY (both parents, both namings)
    local hud = pGui and pGui:FindFirstChild("GuiViews")
        and pGui.GuiViews:FindFirstChild("HUD")
    local cpa
    if hud then
        local main = hud:FindFirstChild("MainHUD")
        cpa = main and main:FindFirstChild("PCGP_ContextActions")
        cpa = cpa or hud:FindFirstChild("PCGP_ContextActions")
    end
    w("  script reads: GuiViews.HUD[.MainHUD].PCGP_ContextActions"
        .. ".Billboards[\"VehicleHUD.Hitch\"]")
    w("  (PCGP parent: " .. (cpa and (cpa.Parent.Name == "MainHUD"
        and "under MainHUD" or "direct under HUD") or "NOT FOUND") .. ")")
    local bills = cpa and cpa:FindFirstChild("Billboards")
    local hitchBill = bills
        and (bills:FindFirstChild("VehicleHUD.Hitch")
            or (bills:FindFirstChild("VehicleHUD")
                and bills.VehicleHUD:FindFirstChild("Hitch")))
    if hitchBill then
        w("    FOUND  class=" .. hitchBill.ClassName
            .. "  Enabled=" .. tostring(hitchBill.Enabled)
            .. "  name=" .. hitchBill.Name)
        w("    (script treats Enabled==true as 'prompt up → press X')")
    else
        w("    NOT FOUND — script would fall back to pressing X blind")
    end
    -- alternates the game might be using instead (report anything Enabled)
    local alts = {
        { "ViewportUI.HitchBillboard", pGui and pGui:FindFirstChild("GuiViews")
            and pGui.GuiViews.HUD:FindFirstChild("VehicleHUD")
            and pGui.GuiViews.HUD.VehicleHUD:FindFirstChild("ViewportUI")
            and pGui.GuiViews.HUD.VehicleHUD.ViewportUI:FindFirstChild("HitchBillboard") },
        { "Buttons flat [VehicleHUD.Hitch]", bills and cpa
            and cpa:FindFirstChild("Buttons")
            and cpa.Buttons:FindFirstChild("VehicleHUD.Hitch") },
    }
    for _, a in ipairs(alts) do
        local inst = a[2]
        if inst then
            local okE, e = pcall(function() return inst.Enabled end)
            w("    alt " .. a[1] .. "  class=" .. inst.ClassName
                .. "  Enabled=" .. (okE and tostring(e) or "?"))
        else
            w("    alt " .. a[1] .. "  NOT FOUND")
        end
    end

    ------------------------------------------------------------------
    -- 23. HITCH PARTS (who owns Hitch/HitchRoot/HitchKnob/HitchTip?)
    --     powers the script's physical line-up: tractor hitch part
    --     placed EXACTLY on the plow's hitch part
    ------------------------------------------------------------------
    header("HITCH PARTS (full paths — tractor vs plow ownership)")
    local found = 0
    for _, d in ipairs(desc) do
        if d:IsA("BasePart") and d.Name:lower():find("hitch", 1, true) then
            found += 1
            w("  - " .. pathOf(d, 7)
                .. string.format("  pos=(%.1f, %.1f, %.1f)", d.Position.X, d.Position.Y, d.Position.Z))
        end
    end
    if found == 0 then w("  (no parts with 'hitch' in the name!)") end
    w("  total hitch parts: " .. found)

    ------------------------------------------------------------------
    -- 24. FIELD + GOTO LOCATIONS (drive-to-field step)
    --     where the field is / what cells it holds / the game's own
    --     named waypoints we could drive toward
    ------------------------------------------------------------------
    header("FIELD + GOTO LOCATIONS (drive-to-field research)")
    local markers = Workspace:FindFirstChild("Markers")
    local gLoc = markers and markers:FindFirstChild("GotoLocations")
    if gLoc then
        w("  Markers.GotoLocations children:")
        if #gLoc:GetChildren() == 0 then w("    (empty)") end
        for _, d in ipairs(gLoc:GetChildren()) do
            local pos
            if d:IsA("BasePart") then
                pos = d.Position
            elseif d:IsA("Model") then
                pos = d:GetPivot().Position
            elseif d:IsA("Attachment") then
                pos = d.WorldPosition
            elseif d:IsA("Folder") then
                local p = d:FindFirstChildWhichIsA("BasePart", true)
                pos = p and p.Position
            end
            w(string.format("    · %s [%s]%s", d.Name, d.ClassName,
                pos and string.format("  pos=(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z) or ""))
        end
    else
        w("  Markers/GotoLocations NOT FOUND")
    end

    local objects = Workspace:FindFirstChild("Objects")
    local fields = objects and objects:FindFirstChild("Fields")
    if not fields then
        w("  Objects.Fields NOT FOUND")
    else
        w("  Objects.Fields children:")
        for _, f in ipairs(fields:GetChildren()) do
            w("    - " .. f.Name .. " [" .. f.ClassName .. "]")
            if f:IsA("Model") then
                local okB, cf, sz = pcall(function() return f:GetBoundingBox() end)
                if okB and cf then
                    w(string.format("      bounds pos=(%.0f, %.0f, %.0f) size=(%.0f, %.0f, %.0f)",
                        cf.Position.X, cf.Position.Y, cf.Position.Z,
                        sz.X, sz.Y, sz.Z))
                end
                local okP, pv = pcall(function() return f:GetPivot() end)
                if okP and pv then
                    w(string.format("      pivot pos=(%.0f, %.0f, %.0f) look=(%.2f, %.2f, %.2f)",
                        pv.Position.X, pv.Position.Y, pv.Position.Z,
                        pv.LookVector.X, pv.LookVector.Y, pv.LookVector.Z))
                end
            end
            local attrs = f:GetAttributes()
            local ak = {}
            for k in pairs(attrs) do ak[#ak + 1] = k end
            table.sort(ak)
            for _, k in ipairs(ak) do w("      attr." .. k .. " = " .. tostring(attrs[k])) end
            local cfg = f:FindFirstChild("Configurations")
            if cfg then
                for _, v in ipairs(cfg:GetDescendants()) do
                    local okV, val = pcall(function()
                        return v:IsA("ValueBase") and v.Value or v.ClassName
                    end)
                    w("      cfg." .. v.Name .. " = " .. (okV and tostring(val) or "?"))
                end
            end
            local seen = {}
            for _, k in ipairs(f:GetChildren()) do
                if not seen[k.Name] then seen[k.Name] = 0 end
                seen[k.Name] += 1
            end
            local names = {}
            for n, c in pairs(seen) do
                names[#names + 1] = n .. (c > 1 and (" ×" .. c) or "")
            end
            table.sort(names)
            local show = {}
            for i, n in ipairs(names) do
                if i > 20 then
                    show[#show + 1] = "… +" .. (#names - 20) .. " more"
                    break
                end
                show[#show + 1] = n
            end
            w("      child names: " .. table.concat(show, ", "))
        end
        w("  field models: " .. #fields:GetChildren())
    end

    -- FieldTile parts anywhere (cells for the future plow step)
    w("  FieldTile parts (workspace-wide):")
    local tiles, shown, union = 0, 0, {}
    for _, d in ipairs(desc) do
        if d:IsA("BasePart") and d.Name:find("FieldTile", 1, true) then
            tiles += 1
            for k, v in pairs(d:GetAttributes()) do union[k] = v end
            if shown < 8 then
                shown += 1
                w(string.format("    · %s  pos=(%.0f, %.0f, %.0f)",
                    d.Name, d.Position.X, d.Position.Y, d.Position.Z))
            end
        end
    end
    w("  total FieldTile parts: " .. tiles)
    local uk = {}
    for k in pairs(union) do uk[#uk + 1] = k end
    table.sort(uk)
    for _, k in ipairs(uk) do
        w("    tile attr union: " .. k .. " = " .. tostring(union[k]))
    end

    -- my plot as the frame of reference (drive FROM here)
    local plots = Workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild("1")
    if plot then
        w("  my plot 1:")
        local cfv = plot:FindFirstChild("CFrame")
        if cfv and cfv:IsA("CFrameValue") then
            local v = cfv.Value
            w(string.format("    CFrameValue pos=(%.0f, %.0f, %.0f)",
                v.Position.X, v.Position.Y, v.Position.Z))
        end
        local fp = plot:FindFirstChild("FrontPlot")
        if fp and fp:IsA("BasePart") then
            w(string.format("    FrontPlot pos=(%.0f, %.0f, %.0f)",
                fp.Position.X, fp.Position.Y, fp.Position.Z))
        end
    else
        w("  my plot 1 NOT FOUND")
    end

    ------------------------------------------------------------------
    -- 25. FIELD CELL MACHINERY (enumerate EVERY cultivatable cell)
    --      No process-memory reading (executors don't expose it) — the
    --      game hands the data to the client: packet remotes, per-cell
    --      GUIs, visuals, and module config.
    ------------------------------------------------------------------
    header("FIELD CELL MACHINERY (cultivable-land enumeration)")
    local RS = game:GetService("ReplicatedStorage")

    -- A. the field model's guts: Plate (the checkered surface?) + guis
    local fObjects = Workspace:FindFirstChild("Objects")
    local fFields = fObjects and fObjects:FindFirstChild("Fields")
    local fModel = fFields and fFields:FindFirstChildWhichIsA("Model")
    if not fModel then
        w("  field model NOT FOUND")
    else
        w("  field model: " .. fModel.Name)
        local plate = fModel:FindFirstChild("Plate")
        if plate then
            w("  Plate [" .. plate.ClassName .. "]"
                .. (plate:IsA("BasePart") and string.format(
                    "  size=(%.0f, %.0f, %.0f)  pos=(%.0f, %.0f, %.0f)",
                    plate.Size.X, plate.Size.Y, plate.Size.Z,
                    plate.Position.X, plate.Position.Y, plate.Position.Z) or ""))
            local kinds = {}
            for _, d in ipairs(plate:GetDescendants()) do
                local key = d.ClassName .. " · " .. d.Name
                kinds[key] = (kinds[key] or 0) + 1
            end
            local kk = {}
            for k, c in pairs(kinds) do kk[#kk + 1] = k .. (c > 1 and (" ×" .. c) or "") end
            table.sort(kk)
            w("  Plate descendants (" .. #kk .. " kinds):")
            for i, k in ipairs(kk) do
                if i > 25 then w("      … +" .. (#kk - 25) .. " more"); break end
                w("      · " .. k)
            end
            if plate:IsA("BasePart") then
                for _, d in ipairs(plate:GetDescendants()) do
                    if d:IsA("Texture") or d:IsA("Decal") then
                        w("      " .. d.ClassName .. " " .. d.Name
                            .. " Face=" .. tostring(d.Face)
                            .. "  tex=" .. string.sub(tostring(d.Texture), 1, 90))
                    end
                end
            end
        else
            w("  Plate NOT FOUND")
        end
        local fg = fModel:FindFirstChild("FieldProgressGui")
        if fg then
            w("  FieldProgressGui [" .. fg.ClassName .. "] children: " .. #fg:GetChildren())
            for i, d in ipairs(fg:GetChildren()) do
                if i > 15 then w("      … +" .. (#fg:GetChildren() - 15) .. " more"); break end
                w("      · " .. d.Name .. " [" .. d.ClassName .. "]")
            end
        else
            w("  FieldProgressGui NOT FOUND")
        end
    end

    -- B. per-cell progress guis on the PlayerGui side (adornee = the cell?)
    local pgUi = LocalPlayer:FindFirstChild("PlayerGui")
    local adornee = pgUi and pgUi:FindFirstChild("AdorneeGuis")
    local prog = adornee and adornee:FindFirstChild("FieldProgressGuis")
    if prog then
        local kids = prog:GetChildren()
        w("  AdorneeGuis.FieldProgressGuis children: " .. #kids)
        for i, d in ipairs(kids) do
            if i > 12 then w("      … +" .. (#kids - 12) .. " more"); break end
            local ad
            if d:IsA("LayerCollector") then ad = d.Adornee end
            w(string.format("      · %s [%s]%s", d.Name, d.ClassName,
                ad and ad:IsA("BasePart") and string.format("  @ (%.0f, %.0f, %.0f)",
                    ad.Position.X, ad.Position.Y, ad.Position.Z) or ""))
            -- deep: what does the progress board SHOW? texts may reveal
            -- cell counts ("0 / 125") or stage names
            local shown = 0
            for _, sub in ipairs(d:GetDescendants()) do
                if shown >= 20 then w("        … (cap)"); break end
                shown += 1
                local txt = ""
                if sub:IsA("TextLabel") or sub:IsA("TextButton") or sub:IsA("TextBox") then
                    txt = "  text=" .. string.sub(sub.Text, 1, 70)
                end
                w("        · " .. sub.Name .. " [" .. sub.ClassName .. "]" .. txt)
            end
        end
    else
        w("  AdorneeGuis.FieldProgressGuis NOT FOUND")
    end

    -- C. CropAesthetics — folders named like "0->129" (last run: 56 of
    --    them). Dump ALL top-level names + what's inside the first two.
    local gameplay = Workspace:FindFirstChild("GameplayVisuals")
    local crop = gameplay and gameplay:FindFirstChild("CropAesthetics")
    if crop then
        local tops = crop:GetChildren()
        w("  CropAesthetics top-level: " .. #tops)
        for i, d in ipairs(tops) do
            if i > 60 then w("      … +" .. (#tops - 60) .. " more"); break end
            w(string.format("      · %s [%s]  children=%d",
                d.Name, d.ClassName, #d:GetChildren()))
        end
        for i = 1, math.min(2, #tops) do
            local f = tops[i]
            w("  inside " .. f.Name .. ":")
            local shown = 0
            for _, sub in ipairs(f:GetDescendants()) do
                if shown >= 20 then w("      … (cap)"); break end
                shown += 1
                local extra = ""
                if sub:IsA("BasePart") then
                    extra = string.format("  @ (%.1f, %.1f, %.1f)  size (%.1f, %.1f, %.1f)",
                        sub.Position.X, sub.Position.Y, sub.Position.Z,
                        sub.Size.X, sub.Size.Y, sub.Size.Z)
                end
                w("      · " .. sub.Name .. " [" .. sub.ClassName .. "]" .. extra)
            end
        end
    else
        w("  CropAesthetics NOT FOUND")
    end

    -- D. cell-ish instance names anywhere (cell/grid/quad/checker/tile)
    local patts = { "cell", "grid", "quad", "checker", "furrow", "tile" }
    local hits = {}
    for _, d in ipairs(desc) do
        local n = d.Name:lower()
        for _, p in ipairs(patts) do
            if n:find(p, 1, true) then
                hits[#hits + 1] = d.ClassName .. " @ " .. pathOf(d, 6)
                break
            end
        end
    end
    w("  cell-ish name hits: " .. #hits)
    for i, h in ipairs(hits) do
        if i > 25 then w("      … +" .. (#hits - 25) .. " more"); break end
        w("      · " .. h)
    end

    -- E. field modules: list them all, probe Source on the richest one
    --    (last run: 3 peeks burned on EMPTY Cmdr stubs — blocked or
    --    stub?), then REQUIRE the real candidates and dump their
    --    exports: function names + config keys ARE the cell math.
    local mods = {}
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("ModuleScript") then
            local n = d.Name:lower()
            if n:find("field", 1, true) or n:find("grid", 1, true)
                or n:find("cell", 1, true) or n:find("soil", 1, true)
                or n:find("crop", 1, true) then
                mods[#mods + 1] = d
            end
        end
    end
    table.sort(mods, function(a, b) return a:GetFullName() < b:GetFullName() end)
    w("  field-ish ModuleScripts in ReplicatedStorage: " .. #mods)
    for _, m in ipairs(mods) do
        w("      · " .. pathOf(m, 7))
    end

    local probe = RS:FindFirstChild("FieldHelper", true)
    if probe then
        local okS, src = pcall(function() return probe.Source end)
        if okS and type(src) == "string" and #src > 0 then
            w("  Source probe FieldHelper: readable (" .. #src
                .. " chars), first 1200:")
            for line in (string.sub(src, 1, 1200) .. "\n"):gmatch("(.-)\n") do
                w("    | " .. line)
            end
        elseif okS and type(src) == "string" then
            w("  Source probe FieldHelper: EMPTY string → Source is blocked"
                .. " in live games (use require() below instead)")
        else
            w("  Source probe FieldHelper: error → "
                .. string.sub(tostring(src), 1, 80))
        end
    else
        w("  Source probe: FieldHelper NOT FOUND")
    end

    local function dumpExport(label, mod)
        if type(mod) ~= "table" then
            w("  " .. label .. " → returned type=" .. type(mod))
            return
        end
        local keys = {}
        for k in pairs(mod) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        w("  require " .. label .. " → table, " .. #keys .. " keys:")
        for i, k in ipairs(keys) do
            if i > 40 then w("      … +" .. (#keys - 40) .. " more keys"); break end
            local v = mod[k]
            local t = type(v)
            if t == "function" then
                w("      · " .. tostring(k) .. "()")
            elseif t == "table" then
                local n = 0
                for _ in pairs(v) do n += 1 end
                local sample, shown = "", 0
                for kk, vv in pairs(v) do
                    shown += 1
                    if shown > 6 then sample = sample .. "…"; break end
                    local vt = type(vv)
                    sample = sample .. tostring(kk) .. "="
                        .. (vt == "function" and "fn" or string.sub(tostring(vv), 1, 40))
                        .. " "
                end
                w("      · " .. tostring(k) .. " = table{" .. n .. "} " .. sample)
            else
                w("      · " .. tostring(k) .. " = " .. t .. "("
                    .. string.sub(tostring(v), 1, 60) .. ")")
            end
        end
    end
    for _, name in ipairs({ "FieldHelper", "CellBufferStructure",
        "CropGrowthConfigClient", "FieldConstruction" }) do
        local m = RS:FindFirstChild(name, true)
        if not m then
            w("  require " .. name .. ": NOT FOUND")
        else
            local okR, mod = pcall(require, m)
            if okR then
                dumpExport(name, mod)
            else
                w("  require " .. name .. " FAILED: "
                    .. string.sub(tostring(mod), 1, 100))
            end
        end
    end

    -- F. LIVE server→client watchers (stay connected after this dump
    --    prints!). The server PUSHES field state to us — connect and echo
    --    to the executor console. Trigger: rejoin or drive onto the field,
    --    then paste the [FIELDDATA …] lines the console prints.
    local nLogged = 0
    local function summarize(prefix, ...)
        local parts = {}
        for i, v in ipairs({...}) do
            local t = typeof(v)
            local s
            if t == "table" then
                local n = 0
                for _ in pairs(v) do n += 1 end
                s = "table{" .. n .. "}: "
                local shown = 0
                for k, val in pairs(v) do
                    shown += 1
                    if shown > 8 then s = s .. "…"; break end
                    s = s .. tostring(k) .. "=" .. tostring(val) .. " "
                end
            elseif t == "string" then
                s = string.format("string(%d) %q", #v, string.sub(v, 1, 140))
            else
                s = t .. "=" .. tostring(v)
            end
            parts[#parts + 1] = "[" .. i .. "] " .. s
        end
        warn(prefix .. " " .. table.concat(parts, "  "))
    end
    local function watch(remoteName)
        -- RECURSIVE: remotes live under Modules.Larry / Modules.Beast… —
        -- last run's plain FindFirstChild reported every one NOT FOUND
        local r = RS:FindFirstChild(remoteName, true)
        if not r then
            w("  live-watch: " .. remoteName .. " NOT FOUND (recursive)")
            return
        end
        local okC = pcall(function()
            r.OnClientEvent:Connect(function(...)
                nLogged += 1
                summarize("[FIELDDATA " .. remoteName .. " #" .. nLogged .. "]", ...)
            end)
        end)
        w(okC and ("  live-watch ON: " .. r:GetFullName()
                .. " — watch executor console; rejoin/drive to trigger a send")
            or ("  live-watch FAILED: " .. remoteName))
    end
    watch("EVTFieldPacket")
    watch("EventEventDataUpdated")
    watch("EventConfigChanged")
    watch("EVTUpdateCropGrowthConfig")

    ------------------------------------------------------------------
    -- 26. CELL ENUMERATION — call FieldHelper's own API to list EVERY
    --     cultivatable cell (encoded id + world position + stage), plus
    --     a PASSIVE capture of what the client sends on the cell-action
    --     remotes (log-only; the original call always passes through)
    ------------------------------------------------------------------
    local ok26, err26 = pcall(function()
        header("CELL ENUMERATION (FieldHelper API)")
        local function pv(v, depth)
            depth = depth or 0
            local t = typeof(v)
            if t == "table" then
                local n = 0
                for _ in pairs(v) do n += 1 end
                if depth >= 2 then return "table{" .. n .. "}" end
                local sample, shown = "", 0
                for k, val in pairs(v) do
                    shown += 1
                    if shown > 8 then sample = sample .. "…"; break end
                    sample = sample .. tostring(k) .. "=" .. pv(val, depth + 1) .. " "
                end
                return "table{" .. n .. "} " .. sample
            elseif t == "string" then
                return string.format("string(%d) %q", #v, string.sub(v, 1, 50))
            end
            return t .. "(" .. string.sub(tostring(v), 1, 50) .. ")"
        end
        local function tryCall(label, fn, variants)
            if type(fn) ~= "function" then
                w("  " .. label .. ": not a function (" .. pv(fn) .. ")")
                return nil
            end
            local errs = {}
            for i, args in ipairs(variants) do
                local pack = table.pack(pcall(fn, table.unpack(args)))
                if pack[1] then
                    local parts = {}
                    for j = 2, pack.n do parts[#parts + 1] = pv(pack[j]) end
                    w(string.format("  %s [args#%d] → %s", label, #args,
                        table.concat(parts, ", ")))
                    return pack
                end
                errs[#errs + 1] = "#" .. i .. ":" .. string.sub(tostring(pack[2]), 1, 45)
            end
            w("  " .. label .. " FAILED all variants (" .. table.concat(errs, " | ") .. ")")
            return nil
        end

        local okFH, F = pcall(require, RS:FindFirstChild("FieldHelper", true))
        if not (okFH and type(F) == "table") then
            w("  require FieldHelper FAILED: " .. pv(F))
            return
        end

        -- A. full export list (last dump capped at 40 → 7 keys were hidden)
        local keys = {}
        for k in pairs(F) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        w("  FieldHelper keys (" .. #keys .. "): " .. table.concat(keys, ", "))

        -- B. constants: the cell-state vocabulary
        for _, cname in ipairs({ "CELL_STAGES", "STAGE_MASK", "SEED_TYPE" }) do
            local t = F[cname]
            if type(t) == "table" then
                local parts = {}
                for k, v in pairs(t) do
                    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
                end
                table.sort(parts)
                w("  " .. cname .. " {" .. #parts .. "}:")
                local line = ""
                for _, p in ipairs(parts) do
                    if #line + #p > 150 then w("     " .. line); line = "" end
                    line = line .. p .. "  "
                end
                if #line > 0 then w("     " .. line) end
            else
                w("  " .. cname .. " = " .. pv(t))
            end
        end

        local fieldM = fModel
        w("  field: " .. (fieldM and fieldM.Name or "NOT FOUND"))
        if not fieldM then return end

        -- C. geometry + cell API (arg lists unknown → try variants)
        local minP = Vector3.new(-1106, 166, -640)
        local maxP = Vector3.new(-1056, 166, -540)
        tryCall("GetFieldSize", F.GetFieldSize, { { fieldM }, {} })
        tryCall("GetFieldTileSize", F.GetFieldTileSize, { {}, { fieldM } })
        tryCall("CountFieldTiles", F.CountFieldTiles, { { fieldM }, {} })
        tryCall("DefaultCell", F.DefaultCell, { {}, { fieldM } })
        tryCall("IsField", F.IsField, { { fieldM }, { fieldM.PrimaryPart } })
        tryCall("GetCells", F.GetCells, { { fieldM }, {} })
        tryCall("ProbeCells", F.ProbeCells, { { fieldM }, {} })

        -- world corner probes → which cell sits at each corner (orientation)
        local corners = {
            { "SW(-X,-Z)", minP + Vector3.new(1, 0, 1) },
            { "SE(+X,-Z)", Vector3.new(maxP.X - 1, 166, minP.Z + 1) },
            { "NW(-X,+Z)", Vector3.new(minP.X + 1, 166, maxP.Z - 1) },
            { "NE(+X,+Z)", maxP - Vector3.new(1, 0, 1) },
        }
        local cornerCells = {}
        for _, cn in ipairs(corners) do
            local pack = tryCall("GetCellClosestTo " .. cn[1],
                F.GetCellClosestTo,
                { { fieldM, cn[2] }, { cn[2] }, { cn[2], fieldM } })
            if pack then cornerCells[cn[1]] = pack[2] end
        end

        -- iterator: closure-style OR (table, idx)-style — try both states
        local cellList = {}
        local function iterDump(label, fn)
            if type(fn) ~= "function" then
                w("  " .. label .. " not a function: " .. pv(fn))
                return
            end
            for _, combo in ipairs({ { nil, nil }, { fieldM, nil } }) do
                local okIt, res = pcall(function()
                    local c = 0
                    for a, b, cc in fn, combo[1], combo[2] do
                        c += 1
                        if c <= 60 then
                            w(string.format("  %s cell#%d: %s | %s | %s",
                                label, c, pv(a), pv(b), pv(cc)))
                        end
                        if c == 1 then cellList[#cellList + 1] = a end
                        if c >= 500 then w("  " .. label .. ": HARD CAP 500"); break end
                    end
                    return c
                end)
                if okIt then
                    w(string.format("  %s total (state=%s): %s cells", label,
                        combo[1] and "field" or "nil", tostring(res)))
                    if tonumber(res) and tonumber(res) > 0 then return end
                else
                    w("  " .. label .. " (state=" .. (combo[1] and "field" or "nil")
                        .. ") FAILED: " .. string.sub(tostring(res), 1, 80))
                end
            end
        end
        iterDump("IterFieldCells(field)", select(2, pcall(F.IterFieldCells, fieldM)))
        local okIF, iterF = pcall(F.IterField, fieldM)
        iterDump("IterField(field)", okIF and iterF or nil)

        -- world CFrame for EVERY enumerated cell (find a working signature)
        if #cellList > 0 then
            local cands = {
                function(cell) return fieldM, cell end,
                function(cell) return cell end,
                function(cell) return cell, fieldM end,
            }
            local build, testCf
            for _, b in ipairs(cands) do
                local okCf, cf = pcall(F.GetCellCFrame, b(cellList[1]))
                if okCf and typeof(cf) == "CFrame" then build = b; testCf = cf; break end
            end
            if build then
                w(string.format("  GetCellCFrame cell#1 → (%.1f, %.1f, %.1f)",
                    testCf.Position.X, testCf.Position.Y, testCf.Position.Z))
                for i, cell in ipairs(cellList) do
                    local okCf, cf = pcall(F.GetCellCFrame, build(cell))
                    if okCf and typeof(cf) == "CFrame" then
                        w(string.format("  cell#%d world=(%.1f, %.1f, %.1f)",
                            i, cf.Position.X, cf.Position.Y, cf.Position.Z))
                    end
                end
            else
                w("  GetCellCFrame: no arg pattern returned a CFrame")
            end
        end

        -- D. decode the REAL CropAesthetics ids (the game's own cell ids)
        local ca = Workspace:FindFirstChild("GameplayVisuals")
            and Workspace.GameplayVisuals:FindFirstChild("CropAesthetics")
        local ids = {}
        if ca then
            for _, d in ipairs(ca:GetChildren()) do
                local num = tonumber(d.Name:match("(%d+)$"))
                if num then ids[#ids + 1] = num end
            end
            table.sort(ids)
        end
        w("  CropAesthetics ids (" .. #ids .. "): " .. table.concat(ids, ", "))
        local idSet = {}
        for _, id in ipairs(ids) do idSet[id] = true end
        for _, id in ipairs(ids) do
            tryCall("DecodeCoordinate(" .. id .. ")", F.DecodeCoordinate, { { id } })
        end

        -- E. encode sweeps: which (axis1×axis2, base) reproduces the ids
        local function enc(a, b)
            local okE, id = pcall(F.EncodeCoordinate, a, b)
            if okE and type(id) == "number" then return id end
            okE, id = pcall(F.EncodeCoordinate, fieldM, a, b)
            if okE and type(id) == "number" then return id end
            return nil
        end
        w(string.format("  encode samples: (0,0)=%s (1,0)=%s (0,1)=%s (1,1)=%s",
            tostring(enc(0, 0)), tostring(enc(1, 0)),
            tostring(enc(0, 1)), tostring(enc(1, 1))))
        local sweeps = {
            { "axis1=0..4, axis2=0..9 (0-based)", 0, 4, 0, 9 },
            { "axis1=1..5, axis2=1..10 (1-based)", 1, 5, 1, 10 },
            { "axis1=0..9, axis2=0..4 (swapped 0)", 0, 9, 0, 4 },
            { "axis1=1..10, axis2=1..5 (swapped 1)", 1, 10, 1, 5 },
        }
        local best, bestHits = 0, -1
        for i, s in ipairs(sweeps) do
            local hits, total = 0, 0
            for a = s[2], s[3] do
                for b = s[4], s[5] do
                    total += 1
                    local id = enc(a, b)
                    if id and idSet[id] then hits += 1 end
                end
            end
            w(string.format("  sweep %s → %d/%d match CropAesthetics",
                s[1], hits, total))
            if hits > bestHits then best, bestHits = i, hits end
        end

        -- F. the computed grid: EVERY cultivatable cell, world position
        --    (field 50×100 → 5 cols along X × 10 rows along Z, 10×10 studs)
        local mapFn
        if best == 1 then mapFn = function(c, r) return enc(c - 1, r - 1) end
        elseif best == 2 then mapFn = function(c, r) return enc(c, r) end
        elseif best == 3 then mapFn = function(c, r) return enc(r - 1, c - 1) end
        elseif best == 4 then mapFn = function(c, r) return enc(r, c) end
        else mapFn = function() return nil end end
        w("  computed grid (5 cols(X) × 10 rows(Z), 10×10 studs, ids via best sweep):")
        for r = 1, 10 do
            local parts = {}
            for c = 1, 5 do
                parts[#parts + 1] = string.format("id=%s @(%.0f,%.0f)",
                    tostring(mapFn(c, r) or "?"), -1111 + c * 10, -645 + r * 10)
            end
            w(string.format("     Z=%d : %s", -645 + r * 10, table.concat(parts, "  ")))
        end

        -- G. crop growth config (durations per crop/stage)
        local okG, CG = pcall(require, RS:FindFirstChild("CropGrowthConfigClient", true))
        if okG and type(CG) == "table" then
            tryCall("CropGrowthConfigClient.GetConfig()", CG.GetConfig, { {} })
        else
            w("  require CropGrowthConfigClient FAILED: " .. pv(CG))
        end

        -- H. PASSIVE outgoing capture: the game's own client fires these
        --    remotes when YOU plow/seed/harvest a cell. Do ONE of those
        --    manually → [CELLACTION …] lines land in the executor console.
        --    Log-only; the original call always passes through (pcall).
        local okHook, hookErr = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local nm = self.Name
                local meth = getnamecallmethod()
                if (meth == "FireServer" or meth == "InvokeServer")
                    and (nm == "EVTPlowFieldCell" or nm == "EVTCultivateFieldCell"
                        or nm == "FNCSeedFieldCell" or nm == "FNCHarvestFieldCell") then
                    pcall(summarize, "[CELLACTION " .. nm .. "]", ...)
                end
                return old(self, ...)
            end))
        end)
        w(okHook and ("  outgoing-capture ON: plow/seed/harvest ONE cell manually"
                .. " → [CELLACTION …] in the EXECUTOR console")
            or ("  outgoing-capture FAILED: " .. string.sub(tostring(hookErr), 1, 100)))
    end)
    if not ok26 then
        w("NOTE: §26 stopped: " .. string.sub(tostring(err26), 1, 120))
    end

    ------------------------------------------------------------------
    -- 27. SEEDER SEED STATE — the seeding feature's first question
    --     (user: "we need to know if it has seeds in it or not"):
    --     where does the game keep the seeder's seed count? Dumps every
    --     KADL/Planter model (attributes, Configurations leaves, tree
    --     with Text/Value/attr probes), seed/fill/empty/count-labeled
    --     GUI text ANYWHERE, live HUD billboards, and PASSIVELY
    --     captures the fill remotes when you press V yourself.
    --     RUN WITH: stand at the seeder (press V if FillSeeder shows),
    --     then sit in the tractor with the seeder hitched; seed ONE
    --     cell by hand if you can. Paste output + executor console.
    ------------------------------------------------------------------
    local ok27, err27 = pcall(function()
        header("SEEDER SEED STATE (KADL / Planter deep)")
        local function pv27(v, depth)
            depth = depth or 0
            local t = typeof(v)
            if t == "table" then
                local n = 0
                for _ in pairs(v) do n += 1 end
                if depth >= 2 then return "table{" .. n .. "}" end
                local sample, shown = "", 0
                for k, val in pairs(v) do
                    shown += 1
                    if shown > 8 then sample = sample .. "…"; break end
                    sample = sample .. tostring(k) .. "=" .. pv27(val, depth + 1) .. " "
                end
                return "table{" .. n .. "} " .. sample
            elseif t == "string" then
                return string.format("string(%d) %q", #v, string.sub(v, 1, 60))
            end
            return t .. "(" .. string.sub(tostring(v), 1, 60) .. ")"
        end

        -- A. seeder models: attributes + Configurations + tree probes
        local objects27 = workspace:FindFirstChild("Objects")
        local eqf27 = objects27 and objects27:FindFirstChild("Equipment")
        local seeders27 = {}
        for _, d in ipairs(eqf27 and eqf27:GetChildren() or {}) do
            if d:IsA("Model") and (d.Name == "KADL"
                or d:GetAttribute("EquipmentType") == "Planter") then
                seeders27[#seeders27 + 1] = d
            end
        end
        w("seeder models (KADL or EquipmentType=Planter): " .. #seeders27)
        for _, sm in ipairs(seeders27) do
            w("")
            w("── " .. sm:GetFullName() .. "   InStorage=" .. tostring(sm:GetAttribute("InStorage")))
            for k, v in pairs(sm:GetAttributes()) do
                w("  attr." .. tostring(k) .. " = " .. pv27(v))
            end
            local conf27 = sm:FindFirstChild("Configurations") or sm:FindFirstChild("Configuration")
            if conf27 then
                local shownC = 0
                for _, d in ipairs(conf27:GetDescendants()) do
                    if shownC >= 40 then w("  … (Configurations capped)"); break end
                    if d:IsA("ValueBase") then
                        shownC += 1
                        local full = d:GetFullName()
                        local at = full:find("Configurations", 1, true)
                        w("  conf." .. (at and full:sub(at) or full) .. " = " .. pv27(d.Value))
                    end
                end
            else
                w("  (no Configurations child)")
            end
            local desc27, shownT, hidden27 = sm:GetDescendants(), 0, 0
            w("  tree (" .. #desc27 .. " descendants; matching lines only):")
            for _, d in ipairs(desc27) do
                if shownT >= 150 then w("  … (tree capped)"); break end
                local line27, keep27 = nil, false
                local nm27 = d.Name:lower()
                local seedish = nm27:find("seed", 1, true) or nm27:find("fill", 1, true)
                    or nm27:find("empty", 1, true) or nm27:find("count", 1, true)
                    or nm27:find("amount", 1, true) or nm27:find("capacity", 1, true)
                if d:IsA("ValueBase") then
                    line27 = "[" .. d.ClassName .. "] " .. d.Name .. "  = " .. pv27(d.Value)
                    keep27 = true
                elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    line27 = "[" .. d.ClassName .. "] " .. d.Name .. "  Text="
                        .. string.format("%q", string.sub(tostring(d.Text), 1, 60))
                        .. "  Visible=" .. tostring(d.Visible)
                    keep27 = true
                elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
                    line27 = "[" .. d.ClassName .. "] " .. d.Name .. "  Enabled=" .. tostring(d.Enabled)
                    keep27 = true
                elseif d:IsA("Folder") or d:IsA("Model") then
                    line27 = "[" .. d.ClassName .. "] " .. d.Name
                    keep27 = true
                end
                local attrs27 = d:GetAttributes()
                if next(attrs27) ~= nil then
                    local parts27 = {}
                    for k, v in pairs(attrs27) do
                        parts27[#parts27 + 1] = tostring(k) .. "=" .. pv27(v)
                    end
                    line27 = (line27 or ("[" .. d.ClassName .. "] " .. d.Name))
                        .. "  attrs{" .. table.concat(parts27, "; ") .. "}"
                    keep27 = true
                end
                if seedish then
                    line27 = "[SEEDHIT] " .. (line27 or ("[" .. d.ClassName .. "] " .. d.Name))
                    keep27 = true
                end
                if keep27 then
                    shownT += 1
                    w("  " .. line27)
                else
                    hidden27 += 1
                end
            end
            w("  (non-matching skipped: " .. hidden27 .. ")")
        end

        -- B. seed/fill/empty/count text ANYWHERE (PlayerGui + workspace)
        header("SEED / FILL / EMPTY TEXT ANYWHERE (PlayerGui + workspace)")
        local pg27 = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local hits27 = 0
        local function scanText27(rt, tag)
            if not rt then return end
            for _, d in ipairs(rt:GetDescendants()) do
                if hits27 >= 70 then return end
                local nm27 = d.Name:lower()
                local tx27
                if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    tx27 = tostring(d.Text)
                end
                local ltx27 = tx27 and tx27:lower() or ""
                local hit27 = nm27:find("seed", 1, true) or ltx27:find("seed", 1, true)
                    or nm27:find("fill", 1, true) or ltx27:find("fill", 1, true)
                    or ltx27:find("empty", 1, true)
                    or (ltx27:find("%d+/%d+") and (nm27:find("label", 1, true)
                        or nm27:find("count", 1, true) or nm27:find("amount", 1, true)
                        or nm27:find("state", 1, true) or nm27:find("type", 1, true)))
                if hit27 then
                    hits27 += 1
                    local extra27 = ""
                    if d:IsA("GuiObject") then
                        extra27 = "  Visible=" .. tostring(d.Visible)
                        if d:IsA("Frame") then
                            extra27 = extra27 .. "  Size=" .. tostring(d.Size) -- fill-bar scale?
                        end
                    end
                    w(string.format("  [%s] %s  Text=%q%s", tag, d:GetFullName(),
                        string.sub(tx27 or "", 1, 60), extra27))
                end
            end
        end
        scanText27(pg27, "gui")
        scanText27(workspace, "ws")
        w("  hits: " .. hits27)

        -- C. HUD billboards live (context/state mirrors when in range)
        header("HUD BILLBOARDS (live Enabled + inner text)")
        local hud27 = pg27 and pg27:FindFirstChild("GuiViews")
            and pg27.GuiViews:FindFirstChild("HUD")
        local bil27 = nil
        if hud27 then
            bil27 = hud27:FindFirstChild("Billboards")
            local main27 = hud27:FindFirstChild("MainHUD")
            bil27 = (main27 and main27:FindFirstChild("Billboards")) or bil27
        end
        if not bil27 and pg27 then
            for _, d in ipairs(pg27:GetDescendants()) do
                if d.Name == "Billboards" and (d:IsA("Folder") or d:IsA("Model")) then
                    bil27 = d
                    break
                end
            end
        end
        if bil27 then
            local n27 = 0
            for _, b in ipairs(bil27:GetChildren()) do
                if n27 >= 60 then w("  … (capped)"); break end
                if b:IsA("BillboardGui") then
                    local bnm = b.Name:lower()
                    local bkeep = b.Enabled or bnm:find("seed", 1, true)
                        or bnm:find("fill", 1, true) or bnm:find("vehicle", 1, true)
                    if bkeep then
                        n27 += 1
                        local txt27 = {}
                        for _, t in ipairs(b:GetDescendants()) do
                            if t:IsA("TextLabel") and t.Text ~= "" then
                                txt27[#txt27 + 1] = t.Name .. "=" .. string.sub(t.Text, 1, 40)
                            end
                        end
                        w(string.format("  %s  Enabled=%s  Adornee=%s  text{%s}",
                            b.Name, tostring(b.Enabled),
                            b.Adornee and b.Adornee:GetFullName() or "?",
                            table.concat(txt27, " | ")))
                    end
                end
            end
            w("  printed: " .. n27 .. " (enabled or seed/fill/vehicle)")
        else
            w("  (no Billboards folder found under PlayerGui)")
        end

        -- D. PASSIVE fill-watch: press V at the seeder manually → the
        --    args land in the EXECUTOR console as [FILLWATCH …]. Chains
        --    over §26's namecall hook (each calls the previous one).
        local okHook27, errHook27 = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local nm, meth = self.Name, getnamecallmethod()
                if (meth == "FireServer" or meth == "InvokeServer")
                    and (nm:find("Fill", 1, true) or nm:find("Seeder", 1, true)) then
                    pcall(summarize, "[FILLWATCH " .. nm .. "]", ...)
                end
                return old(self, ...)
            end))
        end)
        w(okHook27 and "  fill-watch ON: press V at the seeder → [FILLWATCH …] lines in the EXECUTOR console"
            or ("  fill-watch FAILED: " .. string.sub(tostring(errHook27), 1, 100)))

        w("")
        w("DO NOW: (1) stand at the seeder — press V if FillSeeder shows;")
        w("(2) sit in the tractor with the seeder hitched (VehicleHUD live);")
        w("(3) seed ONE cell by hand if you can; (4) wait ~3s, stop the dump,")
        w("paste the output + any [FILLWATCH …] executor-console lines.")
    end)
    if not ok27 then
        w("NOTE: §27 stopped: " .. string.sub(tostring(err27), 1, 120))
    end

    ------------------------------------------------------------------
    -- 28. EQUIPMENT MANAGER — the far-vehicle respawn's data (user:
    --     "let me dump it for you"). The blind build (5080472) clicks
    --     by NAME; this dump shows the REAL structure: the
    --     MenuSelection.Garage button (class + what's inside — can
    --     :Activate() even work?), the GarageMenu tree CLOSED and
    --     OPEN (the dump clicks the menu button itself, waits for the
    --     cards to populate, prints the full tree, then closes it),
    --     every respawn/garage-ish text ANYWHERE in PlayerGui, the
    --     respawn REMOTES, and a PASSIVE [MGRWATCH] namecall hook that
    --     captures the exact remote + args if you click things by hand
    --     AFTER the dump. RUN WITH: just run it — opening + closing a
    --     menu changes no game state; optionally, afterwards open the
    --     manager yourself and click Respawn once to feed [MGRWATCH].
    ------------------------------------------------------------------
    local ok28, err28 = pcall(function()
        -- crash-proof property reader — §28 run 1 died reading .Enabled
        -- off the Percy FOLDER inside Menus (Folders have no Enabled)
        local function propOf(inst, prop)
            local okv, v = pcall(function() return inst[prop] end)
            return okv and v or nil
        end
        header("EQUIPMENT MANAGER (GarageMenu structure)")
        local pg28 = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gv28 = pg28 and pg28:FindFirstChild("GuiViews")
        local menus28 = gv28 and gv28:FindFirstChild("Menus")
        local menu28 = menus28 and menus28:FindFirstChild("GarageMenu")
        local hud28 = gv28 and gv28:FindFirstChild("HUD")
        local main28 = hud28 and hud28:FindFirstChild("MainHUD")
        local sel28 = main28 and main28:FindFirstChild("MenuSelection")
        local garage28 = sel28 and sel28:FindFirstChild("Garage")

        -- the menu-opening button: what class is Garage, and is it
        -- actually clickable (:Activate() needs a GuiButton somewhere)
        if garage28 then
            w(string.format("  menu button: %s (%s)  Visible=%s", garage28:GetFullName(),
                garage28.ClassName,
                garage28:IsA("GuiObject") and tostring(garage28.Visible) or "n/a"))
            for _, d in ipairs(garage28:GetDescendants()) do
                w(string.format("    · %s (%s)%s", d.Name, d.ClassName,
                    (d:IsA("TextButton") or d:IsA("TextLabel")) and ("  Text=" .. string.sub(d.Text, 1, 40)) or ""))
            end
            local inner28
            for _, d in ipairs(garage28:GetDescendants()) do
                if d:IsA("GuiButton") then inner28 = d break end
            end
            w(garage28:IsA("GuiButton") and "    -> IS a GuiButton: :Activate() will work"
                or (inner28 and ("    -> first inner GuiButton: " .. inner28:GetFullName())
                    or "    -> NO GuiButton anywhere inside (open-by-click would fail!)"))
        else
            w("  menu button: MenuSelection.Garage NOT FOUND")
        end
        local menuNames28 = {}
        for _, m in ipairs(menus28 and menus28:GetChildren() or {}) do
            local en28 = propOf(m, "Enabled") -- Folders in Menus have no Enabled
            menuNames28[#menuNames28 + 1] = string.format("%s[%s] Enabled=%s",
                m.Name, m.ClassName, en28 ~= nil and tostring(en28) or "n/a")
        end
        w("  GuiViews.Menus children: " .. (#menuNames28 > 0
            and table.concat(menuNames28, ", ") or "(none / no GuiViews.Menus)"))

        -- tree printer: indent = depth, plus class/text/visibility
        local function tree28(node, cap)
            local n = 0
            local function rec(inst, depth)
                if n >= cap then return end
                n += 1
                local extra = ""
                if inst:IsA("GuiObject") then
                    local en28 = propOf(inst, "Enabled")
                    extra = string.format("  Vis=%s%s", tostring(inst.Visible),
                        en28 ~= nil and (" Enabled=" .. tostring(en28)) or "")
                end
                local txt = ""
                if (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox"))
                    and inst.Text ~= "" then
                    txt = "  Text=" .. string.sub(inst.Text, 1, 48)
                end
                w(string.format("  %s%s [%s]%s%s", string.rep("  ", depth), inst.Name,
                    inst.ClassName, txt, extra))
                for _, d in ipairs(inst:GetChildren()) do
                    rec(d, depth + 1)
                end
            end
            rec(node, 0)
            if n >= cap then w("  … (capped at " .. cap .. " entries)") end
            return n
        end

        if menu28 then
            w(string.format("  GarageMenu: Enabled=%s — current tree%s:", tostring(menu28.Enabled),
                menu28.Enabled and " (it's already OPEN — the dump skips the open-click and just closes it after)"
                    or " (closed state)"))
            tree28(menu28, 150)
        else
            w("  GuiViews.Menus.GarageMenu NOT FOUND")
        end

        -- open it the way the script does, dump the POPULATED tree, close
        local garageBtn28
        if garage28 then
            if garage28:IsA("GuiButton") then
                garageBtn28 = garage28
            else
                for _, d in ipairs(garage28:GetDescendants()) do
                    if d:IsA("GuiButton") then garageBtn28 = d break end
                end
            end
        end
        if menu28 and garageBtn28 then
            w("  … clicking the menu button to OPEN the manager (menu open/close only — no game state changes)")
            pcall(function() garageBtn28:Activate() end)
            for _ = 1, 6 do
                if menu28.Enabled then break end
                task.wait(0.5)
            end
            w("  GarageMenu.Enabled after the click: " .. tostring(menu28.Enabled))
            if menu28.Enabled then
                task.wait(1) -- let the card list populate
                w("  OPEN / populated tree:")
                tree28(menu28, 400)
                local closed28 = false
                for _, d in ipairs(menu28:GetDescendants()) do
                    if d:IsA("GuiButton") then
                        local nm28 = d.Name:lower()
                        local tx28 = d:IsA("TextButton") and d.Text:lower():gsub("%s+", "") or ""
                        if nm28:find("close", 1, true) or tx28 == "x" or tx28 == "✕" or tx28 == "×" then
                            w("  closing via: " .. d:GetFullName())
                            pcall(function() d:Activate() end)
                            task.wait(0.4)
                            closed28 = not menu28.Enabled
                            if closed28 then break end
                        end
                    end
                end
                if not closed28 then
                    pcall(function() garageBtn28:Activate() end)
                    task.wait(0.4)
                    w("  closed via the menu toggle: " .. tostring(not menu28.Enabled))
                end
            end
        elseif not menu28 then
            w("  (no GarageMenu — nothing to open/dump)")
        else
            w("  (no clickable Garage button — can't open it programmatically)")
        end

        -- every respawn/garage-ish node ANYWHERE in PlayerGui
        header("RESPAWN-ISH UI ANYWHERE (PlayerGui name/text hunt)")
        local hits28 = 0
        for _, d in ipairs(pg28 and pg28:GetDescendants() or {}) do
            if hits28 >= 60 then break end
            local nm28 = d.Name:lower()
            local tx28
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                tx28 = tostring(d.Text):lower()
            end
            local hit28 = nm28:find("respawn", 1, true) or (tx28 and tx28:find("respawn", 1, true))
                or nm28:find("garage", 1, true) or (tx28 and tx28:find("equipment manager", 1, true))
            if hit28 then
                hits28 += 1
                w(string.format("  [%d] %s (%s)%s%s", hits28, d:GetFullName(), d.ClassName,
                    (tx28 and tx28 ~= "") and ("  Text=" .. string.sub(tx28, 1, 40)) or "",
                    d:IsA("GuiButton") and ("  Enabled=" .. tostring(propOf(d, "Enabled"))) or ""))
            end
        end
        w("  hits: " .. hits28)

        -- the respawn/spawn/store remotes themselves
        header("RESPAWN REMOTES (ReplicatedStorage name hunt)")
        local rcount28 = 0
        for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if rcount28 >= 40 then break end
            if (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
                local nm28 = d.Name:lower()
                if nm28:find("respawn", 1, true) or nm28:find("spawn", 1, true)
                    or nm28:find("store", 1, true) then
                    rcount28 += 1
                    w(string.format("  - %s (%s)", d:GetFullName(), d.ClassName))
                end
            end
        end
        w("  found: " .. rcount28)

        -- passive namecall watch (chains §27's hook): after the dump,
        -- open the manager BY HAND and click Respawn once — the exact
        -- remote + args land in the EXECUTOR console as [MGRWATCH …]
        local okHook28, errHook28 = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local nm, meth = self.Name, getnamecallmethod()
                if (meth == "FireServer" or meth == "InvokeServer")
                    and (nm:find("Respawn", 1, true) or nm:find("Spawn", 1, true)
                        or nm:find("Store", 1, true) or nm:find("Equipment", 1, true)) then
                    pcall(summarize, "[MGRWATCH " .. nm .. "]", ...)
                end
                return old(self, ...)
            end))
        end)
        w(okHook28 and "  mgr-watch ON: after the dump, open the manager and click Respawn once → [MGRWATCH …] lines in the EXECUTOR console"
            or ("  mgr-watch FAILED: " .. string.sub(tostring(errHook28), 1, 100)))

        w("")
        w("DO NOW: wait for the dump to finish (it opens + closes the manager")
        w("itself); then optionally open the Equipment Manager, click Respawn")
        w("on a vehicle ONCE, and paste the whole dump output + any")
        w("[MGRWATCH …] executor-console lines.")
    end)
    if not ok28 then
        w("NOTE: §28 stopped: " .. string.sub(tostring(err28), 1, 120))
    end
end)

w("")
w("══════ END OF DUMP ══════")
if not ok then w("NOTE: scraper stopped early: " .. tostring(err) .. " (partial dump above)") end

------------------------------------------------------------------
-- 17. REMOTE EVENTS + SOCIAL/INVITE UI — research for remote-sell
--     and auto-accept-invite features (names only, wrapped so it
--     can never break the rest of the dump)
------------------------------------------------------------------
pcall(function()
    header("REMOTE EVENTS (names only — remote-sell research)")
    local n = 0
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and n < 150 then
            w("  - " .. d:GetFullName() .. "  (" .. d.ClassName .. ")")
            n += 1
        end
    end
    w("  listed: " .. n .. " (capped at 150)")
    header("SOCIAL / INVITE / TRADE UI (PlayerGui name matches)")
    local pGui2 = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local keys = { "invite", "trade", "party", "clan", "request", "friend" }
    local found = 0
    if pGui2 then
        for _, o in ipairs(pGui2:GetDescendants()) do
            if found >= 60 then break end
            local nm = o.Name:lower()
            for _, k in ipairs(keys) do
                if nm:find(k, 1, true) then
                    w("  - " .. o:GetFullName() .. "  (" .. o.ClassName .. ")")
                    found += 1
                    break
                end
            end
        end
    end
    w("  matches: " .. found)
end)

------------------------------------------------------------------
-- 18. SEED CRATE PICKUP (live) — user: "it isnt picking up anything".
--     Measures the crate the shop trip tps to: how far it really is,
--     its carry tags, who holds it, and what the game offers there.
--     Presses E ONCE (a real key press) to see if that carries it.
--     Wrapped so it can never break the rest of the dump.
------------------------------------------------------------------
pcall(function()
    header("SEED CRATE PICKUP (live — distance, tags, what E does)")
    local lp = game:GetService("Players").LocalPlayer
    local vim = game:GetService("VirtualInputManager")
    local ch = lp.Character
    local r0 = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not r0 then w("  no HumanoidRootPart — skipped") return end

    local function enabledActs()
        local o = {}
        pcall(function()
            local pg = lp:FindFirstChildOfClass("PlayerGui")
            for _, b in ipairs(pg.GuiViews.HUD.PCGP_ContextActions.Buttons:GetChildren()) do
                if b:IsA("GuiObject") and b.Visible then o[#o + 1] = b.Name end
            end
        end)
        return o
    end
    local function enabledBills()
        local o = {}
        pcall(function()
            local pg = lp:FindFirstChildOfClass("PlayerGui")
            local bb = pg.GuiViews.HUD.PCGP_ContextActions.Billboards
            for _, b in ipairs(bb:GetChildren()) do
                if b:IsA("BillboardGui") and b.Enabled then
                    o[#o + 1] = b.Name .. " -> " .. (b.Adornee and b.Adornee:GetFullName() or "?")
                end
            end
        end)
        return o
    end

    w(string.format("  character at (%.1f, %.1f, %.1f)  seated=%s  state=%s",
        r0.Position.X, r0.Position.Y, r0.Position.Z,
        tostring(hum and hum.SeatPart ~= nil), tostring(hum and hum:GetState())))

    local crates = {}
    local walked = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        walked += 1
        if d.Name == "SeedType" then
            local m = d.Parent and d.Parent.Parent
            if m and m:IsA("Model") then
                local p = m:FindFirstChild("Primary") or m:FindFirstChildWhichIsA("BasePart", true)
                if p then
                    local seed = "?"
                    pcall(function() seed = tostring(d.Value) end)
                    crates[#crates + 1] = { m = m, p = p, seed = seed, d = (p.Position - r0.Position).Magnitude }
                end
            end
        end
    end
    w("  walked " .. walked .. " workspace instance(s) — seed-tagged crates: " .. #crates)

    table.sort(crates, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#crates, 8) do
        local c = crates[i]
        local m = c.m
        local cfg = m:FindFirstChild("Configurations")
        local function val(name)
            local v = cfg and cfg:FindFirstChild(name)
            if not v then return "nil" end
            local ok2, x = pcall(function() return v.Value end)
            if not ok2 then return "?" end
            if typeof(x) == "Instance" then return x.Name end
            return tostring(x)
        end
        w(string.format("  #%d seed='%s' %.1f studs away (dY %.1f) part='%s' %s",
            i, c.seed, c.d, c.p.Position.Y - r0.Position.Y, c.p.Name, m:GetFullName()))
        w(string.format("     CarryCategory=%s CarryWeight=%s Precedence=%s PreventCarry=%s",
            tostring(m:GetAttribute("CarryCategory")), tostring(m:GetAttribute("CarryWeight")),
            tostring(m:GetAttribute("CarryPrecedence")), tostring(m:GetAttribute("PreventCarry"))))
        w(string.format("     Owner=%s CurrentHolder=%s StoreClaim=%s Capacity=%s",
            val("Owner"), val("CurrentHolder"), val("StoreClaim"), val("Capacity")))
    end

    local a0 = enabledActs()
    local b0 = enabledBills()
    w("  context actions NOW: " .. (#a0 > 0 and table.concat(a0, " · ") or "NONE"))
    w("  billboards NOW: " .. (#b0 > 0 and table.concat(b0, " · ") or "NONE"))

    if #crates == 0 then
        w("  no crate in the workspace — the shelf is not streamed in here")
        return
    end

    local near = crates[1]
    local function stateOf()
        local p = near.m:FindFirstChild("Primary") or near.m:FindFirstChildWhichIsA("BasePart", true)
        local links = ch:FindFirstChild("CarryLinks")
        local nm = {}
        if links then for _, v in ipairs(links:GetChildren()) do nm[#nm + 1] = v.Name end end
        return string.format("crate %.1f studs from you (dY %.1f) CarryLinks=[%s]",
            p and (p.Position - r0.Position).Magnitude or -1,
            p and (p.Position.Y - r0.Position.Y) or 0,
            table.concat(nm, ","))
    end
    w("  BEFORE E: " .. stateOf())
    local okE, errE = pcall(function()
        vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.12)
        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
    w("  E press: " .. (okE and "sent" or ("FAILED " .. tostring(errE))))
    task.wait(1.0)
    w("  AFTER E: " .. stateOf())
    local a1 = enabledActs()
    w("  context actions AFTER: " .. (#a1 > 0 and table.concat(a1, " · ") or "NONE"))
    w("  billboards AFTER: " .. (#enabledBills() > 0 and table.concat(enabledBills(), " · ") or "NONE"))

    -- if the key did nothing, try the game's own PickupSeedBox button
    local p2 = near.m:FindFirstChild("Primary") or near.m:FindFirstChildWhichIsA("BasePart", true)
    if p2 and (p2.Position - r0.Position).Magnitude > 12 then
        w("  E did not carry it — trying the game's own PickupSeedBox button")
        local btn
        pcall(function()
            local pg = lp:FindFirstChildOfClass("PlayerGui")
            btn = pg.GuiViews.HUD.PCGP_ContextActions.Buttons:FindFirstChild("PickupSeedBox")
        end)
        w("  PickupSeedBox button: " .. (btn and ("Visible=" .. tostring(btn.Visible)) or "MISSING"))
        local okB, errB = pcall(function()
            if getconnections then
                local cs = getconnections(btn.Activated)
                if #cs > 0 then cs[1]:Fire() return end
            end
            btn:Activate()
        end)
        w("  button attempt: " .. (okB and "fired" or ("FAILED " .. tostring(errB))))
        task.wait(1.0)
        w("  AFTER button: " .. stateOf())
    end
    w("  DO NOW: run this while standing at the crate the shop trip picks")
end)

------------------------------------------------------------------
-- 19. SPUD SCRIPT TRACE — the farming loop's own log, kept in
--     _G.SPUD_TRACE by SpudFarm_Full.lua so the dump carries it.
--     Run the loop until it goes wrong, then run this dump: the
--     reason is in these lines without copying the GUI console.
------------------------------------------------------------------
pcall(function()
    header("SPUD SCRIPT TRACE (what the farming loop logged, newest last)")
    local t = _G.SPUD_TRACE
    if type(t) ~= "table" or #t == 0 then
        w("  empty — the main script hasn't run since this game session started")
        w("  (run SpudFarm_Full.lua once, let it reach the step that fails, then run this dump)")
        return
    end
    local from = math.max(1, #t - 150)
    for i = from, #t do w("  " .. tostring(t[i])) end
    w("  shown: " .. (#t - from + 1) .. " of " .. #t .. " line(s)")
end)

------------------------------------------------------------------
-- 20. SELL POINT (live) — run it while the HARVESTER stands on the
--     sell board. Says whether the pad is really there, which menu
--     (if any) the game opens, and what one Q press does to the load.
------------------------------------------------------------------
pcall(function()
    header("SELL POINT (live — pad, menu, and what Q does)")
    local lp = game:GetService("Players").LocalPlayer
    local vim = game:GetService("VirtualInputManager")
    local ch = lp.Character
    local r0 = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not r0 then w("  no HumanoidRootPart — skipped") return end
    local pos = r0.Position
    w(string.format("  you are at (%.0f, %.0f, %.0f)  seated=%s",
        pos.X, pos.Y, pos.Z, tostring(hum and hum.SeatPart ~= nil)))

    -- the marker the script now aims at
    local gotos = workspace:FindFirstChild("Markers")
    gotos = gotos and gotos:FindFirstChild("GotoLocations")
    local board = gotos and gotos:FindFirstChild("SellBoardSeeds")
    if board then
        w(string.format("  SellBoardSeeds marker at (%.0f, %.0f, %.0f) — %.0f studs away, dY %.1f",
            board.Position.X, board.Position.Y, board.Position.Z,
            (board.Position - pos).Magnitude, board.Position.Y - pos.Y))
    else
        w("  SellBoardSeeds marker NOT FOUND under Markers.GotoLocations")
    end

    -- the ride + its load
    local seat = hum and hum.SeatPart
    local ride = seat and seat:FindFirstAncestorOfClass("Model")
    local function loadNow()
        if not ride then return nil, nil end
        local conf = ride:FindFirstChild("Configurations")
        local c = conf and conf:FindFirstChild("Capacity")
        local m = conf and conf:FindFirstChild("MaxCapacity")
        return c and c.Value or nil, m and m.Value or nil
    end
    local cur0, max0 = loadNow()
    if ride then
        w(string.format("  seated in %s — EquipmentType=%s, load %s/%s",
            ride.Name, tostring(ride:GetAttribute("EquipmentType")),
            tostring(cur0), tostring(max0)))
    else
        w("  NOT seated — stand the harvester on the pad and run this again")
    end

    -- the pad itself: collidable parts under and around you
    local parts, n = {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and (d.Position - pos).Magnitude < 45 then
            n += 1
            if #parts < 18 and d.CanCollide then
                parts[#parts + 1] = string.format("    %-24s %-10s (%.0f, %.0f, %.0f) %.0fx%.0fx%.0f",
                    d.Name, d.ClassName, d.Position.X, d.Position.Y, d.Position.Z,
                    d.Size.X, d.Size.Y, d.Size.Z)
            end
        end
    end
    for _, l in ipairs(parts) do w(l) end
    w("  parts within 45 studs: " .. n)

    -- every menu that could be the sell one
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    local views = pg and pg:FindFirstChild("GuiViews")
    local menus = views and views:FindFirstChild("Menus")
    local stores = views and views:FindFirstChild("Stores")
    local function st(g, nm)
        return string.format("%s=%s", nm, g and tostring(g.Enabled) or "missing")
    end
    local sellMenu = menus and menus:FindFirstChild("SellMenu")
    local depMenu = menus and menus:FindFirstChild("DepositMenu")
    local storeMenu = stores and stores:FindFirstChild("StoreMenu")
    w("  menus before any key: " .. st(sellMenu, "Menus.SellMenu")
        .. "  " .. st(depMenu, "Menus.DepositMenu")
        .. "  " .. st(storeMenu, "Stores.StoreMenu"))

    -- context actions live here
    local acts = {}
    pcall(function()
        for _, b in ipairs(pg.GuiViews.HUD.PCGP_ContextActions.Buttons:GetChildren()) do
            if b:IsA("GuiObject") and b.Visible then acts[#acts + 1] = b.Name end
        end
    end)
    w("  context actions: " .. (#acts > 0 and table.concat(acts, " · ") or "NONE"))

    -- one Q press (the key the script uses to open the sell menu)
    vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
    task.wait(0.08)
    vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    task.wait(1.4)
    local cur1 = loadNow()
    w("  Q press sent. menus after: " .. st(sellMenu, "SellMenu")
        .. "  " .. st(depMenu, "DepositMenu"))
    w(string.format("  load %s -> %s (a drop means the pad sells on Q alone)",
        tostring(cur0), tostring(cur1)))
    local btns
    if sellMenu and sellMenu.Enabled then
        btns = {}
        for _, d in ipairs(sellMenu:GetDescendants()) do
            if d:IsA("GuiButton") and #btns < 14 then
                local t = ""
                pcall(function() t = d.Text end)
                if t ~= "" then btns[#btns + 1] = "'" .. t .. "'" end
            end
        end
        w("  SellMenu buttons: " .. (#btns > 0 and table.concat(btns, " · ") or "none"))
    end
    w("  DO NOW: if nothing opened, look at the screen and say what the pad shows")
end)

-- 21. MILK (live) — the two things the milk loop still cannot see:
--     (a) where a stall really is and HOW the game marks it dirty,
--     (b) why the animal menu only answers for some cows.
--     Prints the 12 Adornee_BarnStallMenu parts + their barn, the plot's
--     cows, then TP-probes ONE cow (menu latency + what the menu is adorneed
--     to) and ONE stall (every prompt that is up, then a single V press).
--     TURN THE MILK LOOP OFF before running this: it moves the same body.
------------------------------------------------------------------
pcall(function()
    header("MILK (stalls, cows, and the game's own Clean prompt)")
    local lp = game:GetService("Players").LocalPlayer
    local vim = game:GetService("VirtualInputManager")
    local ch = lp.Character
    local r0 = ch and ch:FindFirstChild("HumanoidRootPart")
    if not r0 then w("  no HumanoidRootPart - skipped") return end
    local pg = lp:FindFirstChildOfClass("PlayerGui")

    local function ownerOf(inst)
        local p = inst
        for _ = 1, 10 do
            if not p then break end
            local conf = p:FindFirstChild("Configurations")
            local o = conf and conf:FindFirstChild("Owner")
            if o and o:IsA("ObjectValue") and o.Value then return o.Value.Name end
            p = p.Parent
        end
        return nil
    end
    local function attrsOf(inst, cap)
        local keys = {}
        for k in pairs(inst:GetAttributes()) do keys[#keys + 1] = k end
        table.sort(keys)
        local bits = {}
        for i, k in ipairs(keys) do
            if i > (cap or 12) then
                bits[#bits + 1] = "+" .. (#keys - i + 1) .. " more"
                break
            end
            bits[#bits + 1] = k .. "=" .. tostring(inst:GetAttribute(k))
        end
        return #bits > 0 and table.concat(bits, "; ") or "(no attrs)"
    end
    local function confOf(inst)
        local c = inst:FindFirstChild("Configurations")
        if not c then return "no Configurations" end
        local bits = {}
        for _, v in ipairs(c:GetChildren()) do
            bits[#bits + 1] = v.Name .. "[" .. v.ClassName .. "]=" .. tostring(v.Value)
        end
        return #bits > 0 and table.concat(bits, "; ") or "empty"
    end

    -- 1. the stall parts
    local stalls = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "Adornee_BarnStallMenu" then stalls[#stalls + 1] = d end
    end
    w(string.format("  Adornee_BarnStallMenu instances: %d", #stalls))
    for i, d in ipairs(stalls) do
        local pos = (d:IsA("BasePart")) and d.Position or nil
        w(string.format("  [%d] %s %s %s", i, d.ClassName, pathOf(d, 6),
            pos and string.format("(%.1f, %.1f, %.1f) %.1fx%.1fx%.1f", pos.X, pos.Y, pos.Z,
                d.Size.X, d.Size.Y, d.Size.Z) or "no position"))
        w("       owner=" .. tostring(ownerOf(d)) .. "  attrs=" .. attrsOf(d))
        if i <= 3 then
            local chain, p = {}, d
            for _ = 1, 5 do
                p = p and p.Parent
                if not p or p == game then break end
                chain[#chain + 1] = p.Name .. "[" .. p.ClassName .. "]"
            end
            w("       up: " .. table.concat(chain, " < "))
        end
    end

    -- 2. what sits around the first three stalls (this is where a dirt marker
    --    would live, if the game has one)
    for i = 1, math.min(3, #stalls) do
        local d = stalls[i]
        if d:IsA("BasePart") then
            local hits, n = {}, 0
            for _, o in ipairs(workspace:GetDescendants()) do
                local p
                if o:IsA("BasePart") then
                    p = o.Position
                elseif o:IsA("BillboardGui") then
                    local a = o.Adornee
                    if a and a:IsA("BasePart") then p = a.Position end
                end
                if p and (p - d.Position).Magnitude <= 14 then
                    n += 1
                    if #hits < 12 then
                        hits[#hits + 1] = string.format("       %-26s %-11s attrs=%s",
                            o.Name, o.ClassName, attrsOf(o, 4))
                    end
                end
            end
            w(string.format("  --- around stall [%d] (14 studs, %d hit(s))", i, n))
            for _, l in ipairs(hits) do w(l) end
        end
    end

    -- 3. the barn model that owns the stalls
    local barn = stalls[1] and stalls[1]:FindFirstAncestorOfClass("Model")
    if barn then
        w("  stall barn: " .. pathOf(barn) .. " [" .. barn.ClassName .. "] attrs=" .. attrsOf(barn, 16))
        w("    Configurations: " .. confOf(barn))
        local groups, keys = {}, {}
        for _, c in ipairs(barn:GetDescendants()) do
            local b = baseName(c.Name)
            if not groups[b] then keys[#keys + 1] = b end
            groups[b] = (groups[b] or 0) + 1
        end
        table.sort(keys)
        local bits = {}
        for i, k in ipairs(keys) do
            if i > 40 then break end
            bits[#bits + 1] = k .. " x" .. groups[k]
        end
        w("    descendants: " .. table.concat(bits, ", "))
    else
        w("  stall barn: no Model ancestor found")
    end

    -- 4. the cows (same rule the script uses: any model with cow in its name)
    local objects = workspace:FindFirstChild("Objects")
    local animals = objects and objects:FindFirstChild("Animals")
    local cows = {}
    for _, m in ipairs((animals and animals:GetChildren()) or {}) do
        if m:IsA("Model") and m.Name:lower():find("cow", 1, true) then
            cows[#cows + 1] = { model = m, pos = m:GetPivot().Position }
        end
    end
    w(string.format("  cow models in Objects.Animals: %d of %d models", #cows,
        animals and #animals:GetChildren() or 0))
    for i, c in ipairs(cows) do
        w(string.format("  cow %d (%s) at (%.0f, %.0f, %.0f) owner=%s attrs=%s",
            i, c.model.Name, c.pos.X, c.pos.Y, c.pos.Z,
            tostring(ownerOf(c.model)), attrsOf(c.model, 10)))
        if i <= 4 then
            w("       Configurations: " .. confOf(c.model))
            local labs = {}
            for _, d in ipairs(c.model:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("SurfaceGui") or d:IsA("BillboardGui")) and #labs < 8 then
                    local t = d:IsA("TextLabel") and (" text='" .. d.Text .. "'") or ""
                    labs[#labs + 1] = d.Name .. "[" .. d.ClassName .. "]" .. t
                end
            end
            w("       gui/labels: " .. (#labs > 0 and table.concat(labs, " | ") or "none"))
        end
    end

    -- 5. LIVE cow probe: watch the animal menu for 3 s from one cow
    local function menuOf()
        local gv = pg and pg:FindFirstChild("GuiViews")
        local g = gv and gv:FindFirstChild("Animal")
        local ai = g and g:FindFirstChild("AnimalInteractions")
        local ag = ai and ai:FindFirstChild("AnimalInteractionGuis")
        return ag and ag:FindFirstChild("AnimalInteractionMenu")
    end
    if cows[1] then
        w("  --- TP probe: cow 1")
        r0.CFrame = CFrame.new(cows[1].pos + Vector3.new(0, 3, 0))
        local last
        for t = 1, 12 do
            task.wait(0.25)
            local menu = menuOf()
            local enabled, ad, nameT, prodT = nil, "nil", "?", "?"
            if menu then
                enabled = menu.Enabled
                pcall(function()
                    local a = menu.Adornee
                    ad = a and pathOf(a, 4) or "nil"
                end)
                pcall(function()
                    local al = menu.QuickInfo.AnimalLabel
                    nameT = al.NameLabel.Text
                    prodT = al.ProductionFrame.ProductionVisual.ProgressLabel.Text
                end)
            end
            local sig = tostring(enabled) .. "|" .. ad .. "|" .. nameT .. "|" .. prodT
            if sig ~= last then
                w(string.format("       t=%.2fs menu=%s enabled=%s adornee=%s name='%s' prod='%s'",
                    t * 0.25, tostring(menu ~= nil), tostring(enabled), tostring(ad), nameT, prodT))
                last = sig
            end
        end
        local menu = menuOf()
        if menu then
            local labs, attrs = {}, {}
            for _, d in ipairs(menu:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text ~= "" and #labs < 16 then
                    labs[#labs + 1] = d.Name .. "='" .. d.Text .. "'"
                end
            end
            for k, v in pairs(menu:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
            w("       menu labels: " .. (#labs > 0 and table.concat(labs, " | ") or "none"))
            w("       menu attrs: " .. (#attrs > 0 and table.concat(attrs, "; ") or "none"))
        end
    end

    -- 6. LIVE stall probe: what is offered at stall 1, then ONE V press
    local s1 = stalls[1]
    if s1 and s1:IsA("BasePart") then
        w("  --- TP probe: stall 1")
        r0.CFrame = CFrame.new(s1.Position + Vector3.new(0, 3, 0))
        task.wait(1.0)
        local function promptsUp()
            local on = {}
            pcall(function()
                local bills = pg.GuiViews.HUD.PCGP_ContextActions.Billboards
                for _, b in ipairs(bills:GetChildren()) do
                    local e = (b:IsA("LayerCollector") and b.Enabled)
                        or (b:IsA("GuiObject") and b.Visible)
                    if e then on[#on + 1] = b.Name end
                end
            end)
            return #on > 0 and table.concat(on, " | ") or "NONE"
        end
        w("       prompts UP: " .. promptsUp())
        local btns = {}
        pcall(function()
            for _, b in ipairs(pg.GuiViews.HUD.PCGP_ContextActions.Buttons:GetChildren()) do
                local n = b.Name:lower()
                if (n:find("clean") or n:find("dirt") or n:find("filth") or n:find("muck"))
                    and #btns < 10 then
                    btns[#btns + 1] = b.Name .. " visible=" .. tostring(b.Visible)
                end
            end
        end)
        w("       clean-ish buttons: " .. (#btns > 0 and table.concat(btns, " | ") or "none"))
        local hits = {}
        for _, d in ipairs(pg:GetDescendants()) do
            local n = d.Name:lower()
            if (n:find("stall") or n:find("filth") or n:find("dirt") or n:find("manure"))
                and #hits < 12 then
                hits[#hits + 1] = pathOf(d, 5) .. "[" .. d.ClassName .. "] enabled="
                    .. tostring(d.Enabled) .. " visible=" .. tostring(d.Visible)
            end
        end
        w("       stall/dirt gui hits: " .. (#hits > 0 and table.concat(hits, " | ") or "none"))
        w("       stall part attrs before V: " .. attrsOf(s1, 16))
        vim:SendKeyEvent(true, Enum.KeyCode.V, false, game)
        task.wait(0.08)
        vim:SendKeyEvent(false, Enum.KeyCode.V, false, game)
        task.wait(1.4)
        w("       after V, prompts UP: " .. promptsUp())
        w("       stall part attrs after V: " .. attrsOf(s1, 16))
    end

    -- 7. food for the animals (parked for later, but cheap to capture now)
    local buildings = objects and objects:FindFirstChild("Buildings")
    local disp = buildings and buildings:FindFirstChild("FeedDispenser")
    if disp then
        local lbl = "?"
        for _, d in ipairs(disp:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" then
                lbl = d.Name .. "='" .. d.Text .. "'"
                break
            end
        end
        w("  food: FeedDispenser attrs=" .. attrsOf(disp, 8)
            .. "  Configurations: " .. confOf(disp) .. "  label=" .. lbl)
    end
    local feeders = {}
    for _, m in ipairs((buildings and buildings:GetChildren()) or {}) do
        if m.Name:lower():find("feeder") then feeders[#feeders + 1] = m end
    end
    w(string.format("  feeder models: %d", #feeders))
    for _, m in ipairs(feeders) do
        w("    " .. pathOf(m) .. " owner=" .. tostring(ownerOf(m)) .. " attrs=" .. attrsOf(m, 6))
    end

    w("  DO NOW: paste this whole section. You are left standing at stall 1.")
end)

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
