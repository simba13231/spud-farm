-- Spud Farm — REBUILD v1.1: Fluent Renewed GUI shell (STILL NO game features)
-- GUI = Fluent Renewed (open source, no telemetry). NOTE: Renewed uses the
-- Create* API (CreateTab/CreateParagraph/CreateButton), not the old Add* one.
-- Features come back ONE AT A TIME, tested in-game before the next one lands.
-- This build only: window + tabs + console + 🔄 reload. Touches NOTHING in-game.

local LIB_URL    = "https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"
local SCRIPT_URL = "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua"
local VERSION    = "rebuild v1.1 · fluent gui"

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer or Players:GetPlayerAdded():Wait()

local function plainNotify(title, text) -- used before/outside the library
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
    end)
end

------------------------------------------------------------
-- load the GUI library
------------------------------------------------------------
local okLib, Fluent = pcall(function()
    local src = game:HttpGet(LIB_URL, true)
    return assert(loadstring(src))()
end)
if not okLib or type(Fluent) ~= "table" then
    warn("[spud] GUI library failed: " .. tostring(Fluent))
    plainNotify("SPUD FARM", "GUI library failed to load — check executor HTTP / Delta console")
    return
end

------------------------------------------------------------
-- build the interface (wrapped so any error is SHOWN, not swallowed)
------------------------------------------------------------
local okBuild, errBuild = pcall(function()

    local Window = Fluent:CreateWindow({
        Title = "SPUD FARM",
        SubTitle = "",
        TabWidth = 160,
        Size = UDim2.fromOffset(1250, 780),
        Resize = true,      -- auto-fits the window to the actual screen (mobile!)
        MinSize = Vector2.new(620, 460),
        Acrylic = false,    -- no blur: lighter on emulators
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightShift,
    })

    local Tabs = {
        Home     = Window:CreateTab({ Title = "Home", Icon = "house" }),
        Farm     = Window:CreateTab({ Title = "Farm", Icon = "wheat" }),
        Player   = Window:CreateTab({ Title = "Player", Icon = "user" }),
        Console  = Window:CreateTab({ Title = "Console", Icon = "terminal" }),
        Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" }),
    }

    -- console log (also printed to the executor console)
    local LOG = {}
    local logPara = Tabs.Console:CreateParagraph("ConsoleLog", {
        Title = "Console",
        Content = "loaded",
    })

    local function log(msg)
        table.insert(LOG, tostring(msg))
        if #LOG > 24 then table.remove(LOG, 1) end
        print("[spud] " .. tostring(msg))
        -- ▸ TRACE FOR THE DUMP: keep the last 400 lines in this game session
        --   so SpudDump can print what the loop actually did (the user runs
        --   dumps, not console copies — this is how one run names the fault).
        local t = _G.SPUD_TRACE
        if type(t) ~= "table" then t = {}; _G.SPUD_TRACE = t end
        t[#t + 1] = tostring(msg)
        if #t > 400 then table.remove(t, 1) end
        pcall(function() logPara:SetValue(table.concat(LOG, "\n")) end)
    end

    -- ▸ HOME: recent commits + last edit, fetched live from GitHub
    local homePara = Tabs.Home:CreateParagraph("HomeUpdates", {
        Title = "Recent updates",
        Content = "loading latest commits…",
    })
    task.spawn(function()
        local ok, data = pcall(function()
            local src = game:HttpGet(
                "https://api.github.com/repos/simba13231/spud-farm/commits?per_page=6", true)
            return game:GetService("HttpService"):JSONDecode(src)
        end)
        if ok and type(data) == "table" and data[1] then
            local lines = { VERSION }
            for i, c in ipairs(data) do
                if i > 6 then break end
                local msg = tostring(c.commit and c.commit.message or "?")
                msg = msg:gsub("\r", ""):match("^[^\n]*") or msg
                local date = tostring(c.commit and c.commit.author and c.commit.author.date or "")
                lines[#lines + 1] = string.format("%s  %s  %s",
                    string.sub(tostring(c.sha), 1, 7), msg, string.sub(date, 1, 16):gsub("T", " "))
            end
            pcall(function() homePara:SetValue(table.concat(lines, "\n")) end)
            log("home: fetched " .. math.min(#data, 6) .. " recent commits")
        else
            pcall(function() homePara:SetValue("updates unavailable right now (GitHub unreachable)") end)
            log("home: commit fetch failed")
        end
    end)

    -- placeholder tab (features return one at a time)
    Tabs.Player:CreateParagraph("PlayerInfo", {
        Title = "Nothing here yet",
    })

    -- ▸ AUTO-FARM STEP 1 (and nothing more): mount the tractor
    local VIM = game:GetService("VirtualInputManager")
    local function pressKey(key)
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.08)
        VIM:SendKeyEvent(false, key, false, game)
    end

    -- the live farming-loop thread (nil = no loop running). Every movement /
    -- creep / hitch helper checks stopping(), so switching the toggle OFF
    -- kills the loop at its next step instead of letting it keep going.
    -- coroutine identity (not just a bool) so a zombie loop can never be
    -- revived by turning the toggle back on for a NEW loop.
    local loopThread = nil
    local function stopping()
        if not loopThread then return true end
        return coroutine.running() ~= loopThread
    end

    -- ▸ AUTO-FARM STEP 2: movement (Tween = fly-over ARC — up, across at
    --   altitude, down onto the target; the player carries nothing so
    --   nothing smashes. VFly = legacy BodyVelocity steps.)
    local Move = { Mode = "Tween", Speed = 200 }
    local arcTween -- assigned after glideTractor (below)

    local function moveTo(target)
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        if Move.Mode == "Tween" then
            return arcTween(root, target, 30) == true
        end
        -- VFly: pure CFrame steps, NO physics objects. (BodyVelocity made the
        -- physics solver fight the humanoid → lag spikes + server rubber-band)
        for _ = 1, 200 do -- ~10s max
            if stopping() then return false end
            local off = target - root.Position
            local d = off.Magnitude
            if d < 2.5 then return true end
            local step = math.min(d * 0.35, Move.Speed * 0.05) -- capped, eases out
            local newPos = root.Position + off.Unit * step
            local flat = Vector3.new(target.X - newPos.X, 0, target.Z - newPos.Z)
            root.CFrame = flat.Magnitude > 1
                and CFrame.lookAt(newPos, newPos + flat)
                or  CFrame.new(newPos)
            task.wait(0.05)
        end
        return (target - root.Position).Magnitude < 2.5
    end

    local function findTractor()
        local hrp = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local best, bestDist, bestSeat
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name:lower():find("zm80", 1, true) then
                local seat = d:FindFirstChildWhichIsA("VehicleSeat", true)
                    or d:FindFirstChildWhichIsA("Seat", true)
                if seat and hrp then
                    local dist = (seat.Position - hrp.Position).Magnitude
                    if not bestDist or dist < bestDist then
                        best, bestDist, bestSeat = d, dist, seat
                    end
                end
            end
        end
        return best, bestDist, bestSeat
    end

    -- ▸ AUTO-FARM STEP 3: hitch the plow (rules from the old script:
    --   X is a TOGGLE → one press per attempt, never double-press blind;
    --   seated vehicles GLIDE (PivotTo steps), never instant-snap — snaps
    --   get rubber-banded by the server and desync everything;
    --   rotation is preserved; every attempt ends with a TUG-TEST)
    -- dump-confirmed structure: Workspace.Objects.Equipment.<Model> —
    -- implements are CODED models (KADL, KQF3000, S4204…), never named "plow"
    local function equipmentFolder()
        local objects = workspace:FindFirstChild("Objects")
        return objects and objects:FindFirstChild("Equipment")
    end

    -- dump-confirmed: every equipment model carries an EquipmentType
    -- attribute (Tractor/Plow/Planter/Cultivator/Harvester/Truck/Transport)
    -- and cells move through Stage strings "Empty" -> "Plowed" ->
    -- "Cultivated" -> ... — each transition fired by the game's OWN client
    -- when the matching implement passes over the cell (user-confirmed:
    -- the cultivator is auto on drive-over, same as the plow). Per-stage
    -- remotes exist (EVTPlowFieldCell / EVTCultivateFieldCell) — the game
    -- fires them itself; we never spoof.
    local JOBS = {
        { typeName = "Plow",       stage = "Empty",  verb = "plow",
          past = "plowed",    prog = "plowing",    remote = "EVTPlowFieldCell" },
        { typeName = "Cultivator", stage = "Plowed", verb = "cultivate",
          past = "cultivated", prog = "cultivating", remote = "EVTCultivateFieldCell" },
        -- ▸ the seeding pass (user: "seed in the same fields that plow and
        --   cultivate did in the same pattern") — SAME tour + SAME spiral:
        --   Cultivated → Seeded, auto on drive-over like the other two
        --   (the KADL carries a welded SeedDetectionPart, dump §27); the
        --   game fires FNCSeedFieldCell itself — never spoofed
        { typeName = "Planter",    stage = "Cultivated", verb = "seed",
          past = "seeded",    prog = "seeding",    remote = "FNCSeedFieldCell" },
        -- ▸ THE HARVEST PASS (user: "once it's in the harvester it does the
        --   same loop at the tractor to harvest the crops, goes back and
        --   re does it if any missed"): the SAME field tour + SAME
        --   outside-in spiral + touch-up/missed-cell visits — but the tool
        --   IS the ride (the harvester is a separate self-propelled tool,
        --   never hitched to the tractor), and the target is any cell with
        --   a crop STANDING (grown = a stage that is not one of the four
        --   we know; the real stage string isn't in the dumps, and the
        --   per-field log now prints every stage name so it shows up).
        { typeName = "Harvester", grown = true, selfPropelled = true,
          verb = "harvest", past = "harvested", prog = "harvesting",
          remote = "unknown (the harvest event isn't in the dumps)" },
    }

    -- dump-named MODEL per type — user-corrected live: the KQF3000 (the
    -- yellow disc bar in the user's screenshot) IS THE CULTIVATOR; the
    -- dump's labels were swapped (KADL carries the "Fill Seeder" GUI =
    -- it's the SEEDER — both the raw EquipmentType match and a KADL name
    -- preference kept hitching it). The name match wins outright; the
    -- type attribute is only a fallback, and the wrong-tool guards in
    -- runPass still catch a neighbor grab. Returns impl, dist, basis.
    local TYPE_MODEL = { Cultivator = "KQF3000", Planter = "KADL" }
    local function findImplement(typeName, nearPos, tractorModel)
        local folder = equipmentFolder()
        local wantName = TYPE_MODEL[typeName]
        local byName, nameDist, byType, typeDist
        for _, d in ipairs(folder and folder:GetChildren() or {}) do
            if d:IsA("Model") and d ~= tractorModel then
                local dist = (d:GetPivot().Position - nearPos).Magnitude
                if wantName and d.Name == wantName then
                    if not nameDist or dist < nameDist then
                        byName, nameDist = d, dist
                    end
                elseif d:GetAttribute("EquipmentType") == typeName then
                    if not typeDist or dist < typeDist then
                        byType, typeDist = d, dist
                    end
                end
            end
        end
        if byName then return byName, nameDist, "model name " .. wantName end
        if byType then return byType, typeDist, "EquipmentType" end
        return nil
    end

    -- the VehicleHUD Secondary slot = hitched implement, BUT the label goes
    -- stale after unhitching (seen in dump: "Trailer" while stored). Trust it
    -- only when the slot is visible AND the named model is spawned.
    local function hitchedImplementName()
        local ok, sec = pcall(function()
            return LocalPlayer.PlayerGui
                .GuiViews.HUD.VehicleHUD.HUD.Content
                .EquipmentInfo.Secondary
        end)
        if not ok or not sec or not sec:IsA("GuiObject") or not sec.Visible then
            return nil -- slot hidden = game says nothing attached
        end
        local lbl = sec:FindFirstChild("EquipmentName")
        if not (lbl and lbl:IsA("TextLabel")) then return nil end
        local t = tostring(lbl.Text):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then return nil end
        -- a stored implement can't be physically attached (stale label)
        local folder = equipmentFolder()
        local model = folder and folder:FindFirstChild(t)
        if model and model:GetAttribute("InStorage") then
            return nil
        end
        return t
    end

    local function logEquipment()
        local folder = equipmentFolder()
        if not folder then
            log("Objects.Equipment folder not found")
            return
        end
        log("equipment on your farm:")
        for _, d in ipairs(folder:GetChildren()) do
            if d:IsA("Model") then
                local t = tostring(d:GetAttribute("EquipmentType") or "?")
                local stored = d:GetAttribute("InStorage") and " [in storage]" or " [spawned]"
                log(string.format("  · %s = %s%s", d.Name, t, stored))
            end
        end
    end

    -- ▸ SAFETY — far-vehicle respawn through the Equipment Manager (user:
    --   "i want a new safty feature. when a vehicle is not within 1000
    --   studs it will use the equipement manager to respawn it"). The
    --   menu is driven the way a PLAYER drives it: click the MainHUD
    --   "Equipment Manager" menu button, click THIS vehicle's card,
    --   click that card's Spawn button, close. The paths are the live
    --   ones from dump §28, and the expanded card is verified BY NAME
    --   before anything is clicked — a wrong card can never be spawned.
    --   Every miss logs honestly, down to what the menu does show.
    local RESPAWN_RANGE = 1000 -- studs: farther than this = respawn, not walk

    local function guiTextOf(btn)
        if btn:IsA("TextButton") and btn.Text ~= "" then return btn.Text end
        for _, d in ipairs(btn:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" then return d.Text end
        end
        return btn.Name
    end

    -- ▸ CLICKING — NO MOUSE AT ALL (user: "revoke it's ability to use
    --   the mouse. it could buy things with robux."): the script NEVER
    --   sends mouse events, so it can never land on a purchase button.
    --   A "click" instead = call the functions the game ITSELF connected
    --   to that button (capture v7.6 proved the game acts on those — and
    --   that it IGNORES synthetic mouse events and :Activate() anyway).
    --   The effect poll after each attempt means exactly ONE effective
    --   action can ever land (never a double-toggle).

    -- call the game's OWN connections for a button (capture-proven).
    -- Prefers one event's set (the first non-empty), never mixing events
    -- — so the game's logic can't run twice.
    local function invokeHandlers(btn)
        if type(getconnections) ~= "function" then return false end
        local evs = { "MouseButton1Click", "Activated", "MouseButton1Down" }
        local obj, hop = btn, 0
        while obj and hop < 4 do
            for _, ev in ipairs(evs) do
                local okC, conns =
                    pcall(function() return getconnections(obj[ev]) end)
                if okC and conns and #conns > 0 then
                    local called = false
                    for _, c in ipairs(conns) do
                        if type(c.Function) == "function" then
                            if pcall(c.Function) then called = true end
                        end
                    end
                    if called then
                        return true, ev .. (hop > 0 and ("@" .. obj.Name) or "")
                    end
                end
            end
            obj = obj.Parent
            hop += 1
        end
        return false
    end

    local function clickEffect(btn, effect)
        if effect and effect() then return true end -- already there
        -- attempt 1: the game's OWN connected handlers (capture-proven —
        -- this is what makes the manager open in this executor)
        local called, how = invokeHandlers(btn)
        if called then
            log("clicked '" .. btn.Name .. "' via the game's own handler (" .. tostring(how) .. ")")
            for _ = 1, 8 do -- ~2 s
                if stopping() then return false end
                if effect and effect() then return true end
                task.wait(0.25)
            end
        end
        -- attempt 2: :Activate() (fires only THIS button's Activated
        -- signal — not a mouse event, so it can't hit anything else)
        pcall(function() btn:Activate() end)
        for _ = 1, 8 do
            if stopping() then return false end
            if effect and effect() then return true end
            task.wait(0.25)
        end
        return false
    end

    -- the Cards list SCROLLS (user's video: the expanded card grows
    -- DOWNWARD and its buttons sit half-clipped below the viewport until
    -- the list scrolls). We no longer mouse-click, but the game positions
    -- the ExpandedCard from the CLICKED card's spot (SetExpandedCardPos),
    -- so the target card is still scrolled into view first.
    local function ensureVisible(frame, obj)
        pcall(function() obj:ScrollIntoView() end)
        task.wait(0.3)
        local op = obj.AbsolutePosition + obj.AbsoluteSize / 2
        local fp, fs = frame.AbsolutePosition, frame.AbsoluteSize
        return op.X >= fp.X and op.X <= fp.X + fs.X
            and op.Y >= fp.Y and op.Y <= fp.Y + fs.Y
    end

    -- close the manager the way dump §28 saw it close: the menu-level
    -- ExitButton, falling back to the Garage toggle button
    local function closeManager(menu, garageBtn)
        if not menu or not menu.Enabled then return end
        local bg = menu:FindFirstChild("Background")
        local exitBtn = bg and bg:FindFirstChild("ExitButton")
        local closed = function() return not menu.Enabled end
        if exitBtn and exitBtn:IsA("GuiButton") then
            clickEffect(exitBtn, closed)
        end
        if menu.Enabled and garageBtn then
            clickEffect(garageBtn, closed)
        end
        if menu.Enabled and not stopping() then
            log("couldn't close the Equipment Manager — it's left open on screen")
        end
    end

    -- the Equipment Manager's real layout, live-dumped in §28:
    --   Background.Content.Cards.<level>.<id>   one ImageButton per vehicle
    --     └ EquipmentName  TextLabel — text starts with the model name
    --   Background.Content.Cards.<level>.ExpandedCard   fills on card
    --     click (the bare Cards.ExpandedCard is a placeholder that
    --     errors — capture v7.6: real path = Cards.1.ExpandedCard)
    --     └ Content.Info.EquipmentName           names the selected vehicle
    --     └ Content.Actions.Spawn                TextButton "Spawn"
    --   Background.ExitButton                    closes the menu
    -- user's video of the manual respawn: exactly THREE clicks —
    --   1) the Equipment Manager menu button (cards populate ~1-2 s
    --      AFTER opening — the menu starts EMPTY)
    --   2) the vehicle's card (expands INLINE, buttons can sit clipped
    --      below the scroll viewport until scrolled into view)
    --   3) the card's "Spawn" → toast "Equipment respawned in front of
    --      your plot."
    -- Flow: open → card (poll until the list populates) → verify the
    -- expanded card really shows it → Spawn (scrolled into view) → close.
    local function managerAction(vehicleName, action)
        -- action = "Spawn" (bring it out) or "Store" (put it back)
        action = action or "Spawn"
        local ok, res = pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local menus = gv and gv:FindFirstChild("Menus")
            local menu = menus and menus:FindFirstChild("GarageMenu")
            local hud = gv and gv:FindFirstChild("HUD")
            local main = hud and hud:FindFirstChild("MainHUD")
            local sel = main and main:FindFirstChild("MenuSelection")
            local garage = sel and sel:FindFirstChild("Garage")
            local garageBtn
            if garage and garage:IsA("GuiButton") then
                garageBtn = garage
            end
            if not menu then
                log("equipment manager: GuiViews.Menus.GarageMenu not found")
                return false
            end
            if not garageBtn then
                log("equipment manager: the MenuSelection.Garage button wasn't found")
                return false
            end
            -- open it the way a player does — by calling the game's OWN
            -- button handler (NO mouse: user rule) — judged by the menu
            -- actually appearing
            if not menu.Enabled then
                if not clickEffect(garageBtn, function() return menu.Enabled end) then
                    log("equipment manager: the menu button didn't open GarageMenu (the game's own handlers + :Activate() all tried — no mouse)")
                    return false
                end
                task.wait(0.4) -- let the card list populate
            end
            if stopping() then closeManager(menu, garageBtn) return false end
            local bg = menu:FindFirstChild("Background")
            local content = bg and bg:FindFirstChild("Content")
            local cards = content and content:FindFirstChild("Cards")
            if not cards then
                log("equipment manager: Background.Content.Cards not found")
                closeManager(menu, garageBtn)
                return false
            end
            -- this vehicle's card: an ImageButton whose EquipmentName text
            -- STARTS with the model name ("ZM80\n#9" → ZM80), so "Trailer"
            -- can never match a card that merely mentions it. The video
            -- showed the menu opens EMPTY and the cards land ~1-2 s
            -- later — so poll for this card instead of searching once.
            local function findCard()
                for _, d in ipairs(cards:GetDescendants()) do
                    if d:IsA("ImageButton") then
                        local nm = d:FindFirstChild("EquipmentName")
                        if nm and nm:IsA("TextLabel") then
                            local t = nm.Text:gsub("^%s+", ""):gsub("%s+$", "")
                            if t:sub(1, #vehicleName) == vehicleName then
                                return d
                            end
                        end
                    end
                end
            end
            local card
            for _ = 1, 20 do -- ~5 s for the card list to populate
                if stopping() then break end
                card = findCard()
                if card then break end
                task.wait(0.25)
            end
            -- ▸ DIAGNOSTIC (user: "the seeder respawn does not work. we
            --   might need more debugging"): EVERY attempt prints what the
            --   manager actually shows right now — the tabs and every
            --   card name — so a miss explains itself in one run instead
            --   of needing a second capture run.
            do
                local tabs = content:FindFirstChild("Tabs")
                if tabs then
                    local tn = {}
                    for _, t in ipairs(tabs:GetChildren()) do
                        if t:IsA("GuiButton") then
                            tn[#tn + 1] = t.Name
                        end
                    end
                    if #tn > 0 then
                        log("equipment manager: tabs: "
                            .. table.concat(tn, " · "))
                    end
                end
                local cn = {}
                for _, d in ipairs(cards:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Name == "EquipmentName"
                        and d.Text ~= "" then
                        cn[#cn + 1] = (d.Text:match("[^\n<]+") or d.Text)
                    end
                end
                log(string.format(
                    "equipment manager: looking for '%s' — %d card(s) showing right now: %s",
                    vehicleName, #cn,
                    (#cn > 0 and table.concat(cn, " · ") or "none")))
            end
            if not card then
                log("equipment manager: no card for " .. vehicleName
                    .. " — it is not among the cards listed above")
                closeManager(menu, garageBtn)
                return false
            end
            -- select the card by calling the game's OWN handler (NO mouse;
            -- user rule), judged by the ExpandedCard naming THIS vehicle
            -- — that fills the card's detail view. The video showed cards
            -- can sit clipped below the scroll viewport, and the game
            -- places the ExpandedCard from the clicked card's position,
            -- so it is scrolled into view first.
            if not ensureVisible(cards, card) then
                -- an OUT vehicle's card can sit outside the visible list —
                -- that only ever mattered when a screen point was clicked
                -- with a mouse. Nothing is mouse-clicked any more, so carry
                -- on and let the expanded-card effect poll judge.
                log("equipment manager: the " .. vehicleName .. " card is outside the visible list — calling it anyway (no mouse)")
            end
            -- ▸ THE EXPANDED CARD IS NESTED (user's capture: the real path
            --   is Cards.1.ExpandedCard.Content.Actions.Spawn — NOT a
            --   direct child of Cards; the bare Cards.ExpandedCard that
            --   exists before any card is clicked is a placeholder whose
            --   GetViewedEquipment errors "Unable to find referenced
            --   equipment card"). The detail view is therefore
            --   RE-RESOLVED recursively on EVERY check, preferring the
            --   nested copy that really names a card — never captured
            --   once (that was why the respawn never opened a card).
            local function findExpanded()
                local nested, named, blank
                for _, d in ipairs(cards:GetDescendants()) do
                    if d.Name == "ExpandedCard" then
                        local c = d:FindFirstChild("Content")
                        local i = c and c:FindFirstChild("Info")
                        local n = i and i:FindFirstChild("EquipmentName")
                        if n and n:IsA("TextLabel") and n.Text ~= "" then
                            if d.Parent ~= cards then
                                nested = nested or d
                            else
                                named = named or d
                            end
                        else
                            blank = blank or d
                        end
                    end
                end
                return nested or named or blank
            end
            local function expandedName()
                local ex = findExpanded()
                local c = ex and ex:FindFirstChild("Content")
                local i = c and c:FindFirstChild("Info")
                local n = i and i:FindFirstChild("EquipmentName")
                if not (n and n:IsA("TextLabel")) then return nil end
                return n.Text:gsub("^%s+", ""):gsub("%s+$", "")
            end
            local function expandedShows()
                local t = expandedName()
                return (t ~= nil and t ~= ""
                    and t:sub(1, #vehicleName) == vehicleName)
            end
            clickEffect(card, expandedShows)
            if not expandedShows() then
                -- log what the detail view DOES name, so a structure
                -- surprise is diagnosable from the Console alone
                local t = expandedName()
                log(string.format("equipment manager: clicking the %s card didn't open its detail view (it shows '%s') — clicking nothing",
                    vehicleName, t and (t:match("[^\n<]+") or t) or "nothing"))
                closeManager(menu, garageBtn)
                return false
            end
            local expanded = findExpanded()
            local expContent = expanded and expanded:FindFirstChild("Content")
            local actions = expContent and expContent:FindFirstChild("Actions")
            local actBtn = actions and actions:FindFirstChild(action)
            if not (actBtn and actBtn:IsA("GuiButton")) then
                local shown = {}
                if actions then
                    for _, d in ipairs(actions:GetDescendants()) do
                        if d:IsA("TextButton") then
                            shown[#shown + 1] = guiTextOf(d)
                        end
                    end
                end
                log("equipment manager: the " .. vehicleName .. " card has no " .. action .. " button. its actions: "
                    .. (#shown > 0 and table.concat(shown, " · ") or "none"))
                closeManager(menu, garageBtn)
                return false
            end
            -- THE GAME'S OWN SPAWN HANDLER (capture v7.6, entry 9j): the
            -- Spawn button's own handler is the spawn action itself — it
            -- closes over the menu controller, the viewed-equipment STATE
            -- (its GetViewedEquipment resolves the vehicle LIVE from this
            -- card) and the remote wrapper. Calling it = what a click
            -- does: the game fetches the vehicle itself, so there is no
            -- remote name or args to guess and nothing to spoof. It also
            -- sidesteps the clip problem entirely: the button only needs
            -- to EXIST in the tree, not be visible — a handler call can
            -- never miss (and no mouse is involved anywhere any more).
            local handled, how = invokeHandlers(actBtn)
            if handled then
                log(string.format("equipment manager: called the game's own %s handler for %s (%s — instant, no clip risk)", action, vehicleName, tostring(how)))
                task.wait(1) -- let the game process the respawn
                closeManager(menu, garageBtn)
                return true
            end
            -- FALLBACK: no handler readable → :Activate() only. NO MOUSE
            -- anywhere (user rule) — :Activate() fires just this one
            -- button's Activated signal, so it cannot hit anything else.
            -- The caller's ~15 s re-find poll is the effect check.
            log(string.format("equipment manager: no readable %s handler for %s (getconnections) — trying :Activate() instead", action, vehicleName))
            pcall(function() actBtn:Activate() end)
            task.wait(1) -- let the game process the respawn
            closeManager(menu, garageBtn)
            return true
        end)
        if not ok then
            log("equipment manager UI error: " .. tostring(res))
            return false
        end
        return res and true or false
    end

    -- ▸ SAFETY FOR EVERY TOOL (user: "make it do that for every tool
    --   now"): the exact rule the tractor gate uses, applied to each
    --   implement — farther than RESPAWN_RANGE (or sitting IN STORAGE,
    --   which is the map-edge void = always far anyway) = respawn it
    --   through the Equipment Manager instead of aborting or driving the
    --   whole map to it. ONE attempt; the respawn may REBUILD the model,
    --   so the tool is re-found by the same type-pick and polled for
    --   ~15 s. Returns the (fresh) impl, dist, basis — or nil, with an
    --   honest log either way. Nothing respawns while it's near.
    local function ensureToolNearby(tr, typeName, verb)
        if stopping() then return nil end
        local impl, dist, basis =
            findImplement(typeName, tr:GetPivot().Position, tr)
        if not impl then
            log("no equipment with EquipmentType=" .. typeName .. " found — see list above")
            return nil
        end
        local stored = impl:GetAttribute("InStorage")
        if not stored and (not dist or dist <= RESPAWN_RANGE) then
            return impl, dist, basis -- close enough — nothing to do
        end
        log(string.format("%s (the %s) is %s — respawning it via the Equipment Manager",
            impl.Name, verb,
            stored and "IN STORAGE"
                or string.format("%.0f studs away (>%d)", dist, RESPAWN_RANGE)))
        local respawned = managerAction(impl.Name)
        if respawned == false then
            log(string.format("equipment manager: the respawn for %s failed — see the lines above for why", impl.Name))
        end
        for i = 1, 30 do -- ~15 s for the respawn to land
            if stopping() then return nil end
            local impl2, dist2, basis2 =
                findImplement(typeName, tr:GetPivot().Position, tr)
            if impl2 and not impl2:GetAttribute("InStorage")
                and dist2 and dist2 <= RESPAWN_RANGE then
                log(string.format("✅ %s respawned — %.0f studs away now",
                    impl2.Name, dist2))
                return impl2, dist2, basis2
            end
            -- say so once, halfway: a respawn that never lands used to look
            -- like the run silently stopping right after the manager closed
            if i == 10 then
                log(string.format("still waiting for %s to come out (%s)…",
                    impl.Name,
                    impl2 and (impl2:GetAttribute("InStorage")
                        and "it still reads in storage"
                        or string.format("%.0f studs away", dist2 or 0))
                        or "it isn't in the folder"))
            end
            task.wait(0.5)
        end
        local impl2, dist2 = findImplement(typeName, tr:GetPivot().Position, tr)
        log(string.format("respawn didn't bring the %s back (%s) — skipping this pass",
            verb,
            impl2 and (impl2:GetAttribute("InStorage") and "still in storage"
                or string.format("still %.0f studs away", dist2 or 0))
                or "it's gone"))
        return nil
    end

    -- VFly-style vehicle glide: ease-out CFrame steps facing the direction
    -- of travel — same feel as VFly player movement. NO physics objects
    -- (BodyVelocity made the solver fight the seat → lag + rubber-banding).
    local function glideTractor(tr, targetPos)
        local pos = tr:GetPivot().Position
        local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
        if flat.Magnitude < 0.5 then return end
        local y = pos.Y -- stay on the ground plane
        local steps = math.clamp(math.floor(flat.Magnitude / 1.5), 3, 40)
        for i = 1, steps do
            if stopping() then return end
            local t = i / steps
            local ease = 1 - (1 - t) * (1 - t) -- ease-out: quick start, soft landing
            local p = Vector3.new(pos.X, y, pos.Z) + flat * ease
            tr:PivotTo(CFrame.lookAt(p, p + flat)) -- face travel direction
            task.wait(0.05)
        end
    end

    -- fly-over ARC (user's plan, smoothed): ONE smooth curve — rise,
    -- travel, settle (smoothstep lerp + sinusoidal lift), NOT three hard
    -- legs. ONLY for hops with NOTHING trailing behind (player on foot,
    -- empty tractor) — a towed implement at altitude would smash through
    -- whatever it passes over. Short hops (<4 studs) just glide.
    arcTween = function(pv, targetPos, clearY)
        clearY = clearY or 30
        local pos = pv:GetPivot().Position
        local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
        if flat.Magnitude < 4 then
            glideTractor(pv, targetPos)
            return true
        end
        local rot = CFrame.lookAt(Vector3.zero, flat.Unit) -- rotation only
        local baseY = math.max(pos.Y, targetPos.Y)
        local steps = math.clamp(math.floor(flat.Magnitude / 1.2), 12, 90)
        for i = 1, steps do
            if stopping() then return false end
            local t = i / steps
            local ease = t * t * (3 - 2 * t) -- smoothstep: soft start + landing
            local lift = math.sin(math.pi * t) * clearY -- 0 → clearY → 0
            local p = pos + Vector3.new(flat.X * ease,
                (baseY - pos.Y) * ease + lift, flat.Z * ease)
            pv:PivotTo(CFrame.new(p) * rot)
            task.wait(0.03)
        end
        pv:PivotTo(CFrame.new(targetPos) * rot) -- land exactly on target
        return true
    end

    -- the game's own context system: this billboard is Enabled only while
    -- the Hitch action is genuinely in range (dump §16b proved it live).
    -- dump §22 showed my old path was wrong TWO ways: the PCGP folder may
    -- sit under HUD.MainHUD, and the billboards are FLAT-named —
    -- "VehicleHUD.Hitch" is ONE instance, not a folder. Check both
    -- parents + both namings. If unreadable, stay permissive — press X
    -- and let the tug-test judge.
    local function hitchPromptUp()
        local ok, b = pcall(function()
            local gv = LocalPlayer.PlayerGui:FindFirstChild("GuiViews")
            local hud = gv and gv:FindFirstChild("HUD")
            local cpa
            if hud then
                local main = hud:FindFirstChild("MainHUD")
                cpa = main and main:FindFirstChild("PCGP_ContextActions")
                cpa = cpa or hud:FindFirstChild("PCGP_ContextActions")
            end
            local bills = cpa and cpa:FindFirstChild("Billboards")
            if not bills then return nil end
            return bills:FindFirstChild("VehicleHUD.Hitch")
                or (bills:FindFirstChild("VehicleHUD")
                    and bills.VehicleHUD:FindFirstChild("Hitch"))
        end)
        if ok and b then
            if b:IsA("LayerCollector") then return b.Enabled == true end
            if b:IsA("GuiObject") then return b.Visible == true end
        end
        return true
    end

    -- park the tractor ON the plow, oriented by the PLOW's own facing —
    -- no guessed stand-off direction (user's plan: teleport to the tool,
    -- align with the tool, then creep forward)
    local function alignToPlow(tr, plow, backOff)
        if stopping() then return end
        local pp = plow:GetPivot()
        local tp = tr:GetPivot()
        local f = Vector3.new(pp.LookVector.X, 0, pp.LookVector.Z)
        f = f.Magnitude > 0.1 and f.Unit or Vector3.new(0, 0, -1)
        local target = Vector3.new(
            pp.Position.X - f.X * (backOff or 0),
            tp.Position.Y,
            pp.Position.Z - f.Z * (backOff or 0))
        -- glide in (a far plow may take more than one pass; never snap whole-map)
        for _ = 1, 6 do
            local cur = tr:GetPivot().Position
            if (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 1 then
                break
            end
            glideTractor(tr, target)
        end
        tr:PivotTo(CFrame.new(target) * (pp - pp.Position)) -- final facing = plow's
        task.wait(0.25)
    end

    -- creep straight forward until the game raises the Hitch prompt —
    -- the GAME decides when we're in range, not our math
    local function creepUntilPrompt(tr, maxSteps, stepLen)
        for i = 1, maxSteps do
            if stopping() then return nil end
            if hitchPromptUp() then return i - 1 end
            tr:PivotTo(tr:GetPivot() * CFrame.new(0, 0, -stepLen)) -- -Z = forward
            task.wait(0.06)
        end
        return hitchPromptUp() and maxSteps or nil
    end

    -- physical hitch spots: parts named Hitch / HitchRoot / HitchKnob / HitchTip
    -- (dump keyword scan found all four exist somewhere in workspace)
    local function hitchRank(n)
        local l = n:lower()
        if l == "hitch" then return 1 end
        if l:find("root", 1, true) then return 2 end
        if l:find("knob", 1, true) then return 3 end
        if l:find("tip", 1, true) then return 4 end
        return 5
    end

    local function findHitchPart(model)
        local best, bestRank
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower():find("hitch", 1, true) then
                local r = hitchRank(d.Name)
                if not bestRank or r < bestRank then best, bestRank = d, r end
            end
        end
        return best
    end

    -- park the tractor so its hitch part sits EXACTLY on the plow's hitch
    -- part, rotating with the plow — physical line-up, no stand-off guessing.
    -- airborne = the tractor tows NOTHING (pre-hitch): arc over everything
    -- down onto the pose. Towed runs (the park step) must stay on the
    -- ground — an implement at altitude smashes through whatever it passes.
    local function lineUpHitch(tr, plow, airborne)
        if stopping() then return false end
        local tH = findHitchPart(tr)
        local pH = findHitchPart(plow)
        if not (tH and pH) then
            log("hitch parts: tractor=" .. (tH and tH.Name or "none")
                .. " plow=" .. (pH and pH.Name or "none") .. " — using creep alignment")
            return false
        end
        local pp = plow:GetPivot()
        local cur = tr:GetPivot()
        local rel = cur:ToObjectSpace(tH.CFrame)
        -- match XZ + rotation to the plow but KEEP the tractor's height:
        -- dump §23 showed the hitchable pose has the tractor hitch ~1.6
        -- studs ABOVE the plow's — forcing exact Y would sink the tractor
        -- into the plow and get rubber-banded
        local desired = CFrame.new(pH.Position.X, cur.Position.Y, pH.Position.Z)
            * (pp - pp.Position)
        local newPivot = desired * rel:Inverse()
        if airborne then
            -- ONE arc straight down onto the pose — the old multi-pass
            -- loop re-ARCED every pass (up/down/up/down jank)
            arcTween(tr, newPivot.Position, 30)
            if stopping() then return false end
        else
            for _ = 1, 6 do -- ground: multi-pass glide if far
                local cur = tr:GetPivot().Position
                local tgt = newPivot.Position
                if (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(tgt.X, 0, tgt.Z)).Magnitude < 1 then
                    break
                end
                glideTractor(tr, tgt)
            end
        end
        if stopping() then return false end
        tr:PivotTo(newPivot)
        task.wait(0.2)
        log(string.format("lined up %s ↔ %s (gap %.2f studs)",
            tH.Name, pH.Name, (tH.Position - pH.Position).Magnitude))
        return true
    end

    -- one hitch attempt: press X once → tug forward 5 studs → did the plow follow?
    local function attemptHitch(tr, plow)
        pressKey(Enum.KeyCode.X)
        task.wait(0.6)
        if stopping() then return false, 0 end
        local before = plow:GetPivot().Position
        local pivot = tr:GetPivot()
        local fwd = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
        if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
        glideTractor(tr, pivot.Position + fwd.Unit * 5)
        task.wait(0.5)
        local moved = (plow:GetPivot().Position - before).Magnitude
        return moved > 2.5, moved
    end

    -- ▸ after a sweep, UNHITCH the tool WHERE IT CAME FROM — tween back to
    --   the exact spot it was found at (origin captured at hitch time),
    --   then press X — the same proven toggle used to hitch, tug-verified.
    --   Works for any implement (plow, cultivator, ...) by name.
    local function dropImplementAtOrigin(tr, impl, originPos)
        log(string.format("parking %s: tweening back to where it came from (%.0f studs)",
            impl.Name, (tr:GetPivot().Position - originPos).Magnitude))
        for pass = 1, 20 do -- glideTractor covers ~60 studs per call
            if stopping() then return false end
            local p = tr:GetPivot().Position
            if (Vector3.new(p.X, 0, p.Z) - Vector3.new(originPos.X, 0, originPos.Z)).Magnitude <= 5 then
                break
            end
            glideTractor(tr, Vector3.new(originPos.X, p.Y, originPos.Z))
            task.wait(0.2)
        end
        if stopping() then return false end
        -- X-unhitch is PROXIMITY-gated like hitching: line up ON the
        -- tool's hitch — the exact pose the game accepts — let it settle,
        -- THEN press X. Prove with a tug: attached = the tool follows,
        -- parked = it stays put.
        for attempt = 1, 3 do
            local lined = lineUpHitch(tr, impl)
            if not lined then log("park: hitch line-up parts missing — pressing X anyway") end
            task.wait(1) -- let the tool stop swinging after the move
            if stopping() then return false end
            pressKey(Enum.KeyCode.X)
            task.wait(0.7)
            if stopping() then return false end
            local before = impl:GetPivot().Position
            local pivot = tr:GetPivot()
            local fwd = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
            if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
            glideTractor(tr, pivot.Position + fwd.Unit * 6)
            task.wait(0.6)
            if stopping() then return false end
            local followed = (impl:GetPivot().Position - before).Magnitude
            if followed <= 2 then
                log(string.format("✅ tool parked where it came from (X, attempt %d — stayed put)", attempt))
                return true
            end
            log(string.format("unhitch attempt %d: still follows (%.1f studs) — re-lining up, X again",
                attempt, followed))
        end
        log("⚠ still attached after 3 presses — unhitch manually with X")
        return false
    end

    -- ▸ step 1: MOUNT the tractor — walk to it if needed, F, verify seated.
    --   Extracted verbatim from the loop so the seeder-hitch path on an
    --   idle run reuses the exact same proven code. Returns true=seated.
    local function mountTractor(char, hum, tr, seat, dist, label)
        label = label or "tractor"
        -- ▸ SWITCHING RIDES: seated in ANY other vehicle (the tractor, or
        --   the harvester the harvester step just entered) → press the
        --   game's own exit key and wait to actually stand, THEN walk
        --   over. Never teleport seat-to-seat.
        if hum.SeatPart and not hum.SeatPart:IsDescendantOf(tr) then
            local from = hum.SeatPart.Parent
            log(string.format("seated in %s — getting out to reach the %s",
                from and from.Name or "another vehicle", label))
            pressKey(Enum.KeyCode.F) -- dump: ExitEquipment = F
            for _ = 1, 8 do -- ~2 s to stand up
                if stopping() then return false end
                if not hum.SeatPart then break end
                task.wait(0.25)
            end
            if hum.SeatPart then
                -- that seat didn't take the key → the humanoid's own stand
                pcall(function() hum.Sit = false end)
                for _ = 1, 4 do
                    if stopping() then return false end
                    if not hum.SeatPart then break end
                    task.wait(0.25)
                end
            end
            if hum.SeatPart then
                log(string.format("still seated in %s — couldn't get out to reach the %s",
                    hum.SeatPart.Parent and hum.SeatPart.Parent.Name or "it", label))
                return false
            end
            task.wait(0.3)
        end
        if not hum.SeatPart then
            if dist > 10 then
                log(string.format("moving to %s (%.0f studs)…", label, dist))
                local reached = moveTo(seat.Position + Vector3.new(0, 3, 0))
                if stopping() then return false end
                if not reached then
                    log("couldn't reach the " .. label)
                    return false
                end
                local root = char:FindFirstChild("HumanoidRootPart")
                dist = root and (seat.Position - root.Position).Magnitude or 0
            end
            if stopping() then return false end
            if dist > 10 then log("still too far after moving") return false end
            log("pressing F to mount the " .. label .. "…")
            pressKey(Enum.KeyCode.F)
            task.wait(0.7)
            if stopping() then return false end
            if not (hum.SeatPart and hum.SeatPart:IsDescendantOf(tr)) then
                pressKey(Enum.KeyCode.F) -- context can take a moment to register
                task.wait(0.7)
            end
            if stopping() then return false end
            if hum.SeatPart and hum.SeatPart:IsDescendantOf(tr) then
                log("✅ mounted " .. tr.Name)
            else
                log("F pressed but not seated — game didn't accept the enter")
                return false
            end
        end
        return true
    end

    -- ▸ THE PROVEN HITCH SEQUENCE — extracted unchanged from the pass code
    --   so the seeder hitch (step 2) reuses it verbatim: stale-HUD
    --   tug-verify → wrong-tool guard (X the neighbor off first) →
    --   line-up/creep retry loop with X + tug per attempt. Returns
    --   true = attached (the caller keeps it hitched).
    local function hitchTool(tr, impl)
        -- the HUD label alone can be stale (dump-proven: it said "S4204"
        -- while the hitch points sat 9.5 studs apart) — if it claims a
        -- hitch, PROVE it with a tug: the tool must follow. Pass → skip
        -- straight to drive. Fail → treat as unhitched, hitch normally.
        local didHitch = false
        local attached = hitchedImplementName()
        -- a DIFFERENT tool on the hitch (live bug: it hitched the
        -- KQF3000 seeder) — X it off first; unhitching is proximity-
        -- gated, so if it stays, only the user can free the hitch
        if attached and attached ~= impl.Name then
            log("a different tool is hitched (" .. attached .. ") — unhitching it first")
            pressKey(Enum.KeyCode.X)
            task.wait(0.8)
            if stopping() then return false end
            attached = hitchedImplementName()
            if attached and attached ~= impl.Name then
                log("⚠ " .. attached .. " is still hitched — unhitch it manually (X next to it), then run again")
                return false
            end
            log("hitch is free")
        end
        if attached then
            log("HUD says hitched (" .. attached .. ") — tug-verifying…")
            local before = impl:GetPivot().Position
            local pivot = tr:GetPivot()
            local fwd = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
            if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
            glideTractor(tr, pivot.Position + fwd.Unit * 4)
            task.wait(0.4)
            if stopping() then return false end
            local followed = (impl:GetPivot().Position - before).Magnitude
            if followed > 2 then
                log(string.format("✅ tug passed (%.1f studs) — attached, skipping hitch", followed))
                didHitch = true
            else
                log(string.format("label stale — the tool didn't follow (%.1f studs) — hitching first", followed))
            end
        end

        if not didHitch then
            -- user's plan: physical line-up of the hitch PARTS (fallback:
            -- align+creep), then the game's Hitch prompt gates the X press.
            -- Retry until the tug-test passes.
            local attempt, forceCreep = 0, false
            while not stopping() do
                attempt += 1
                if not (impl and impl:IsDescendantOf(workspace)) then
                    log("the tool disappeared (despawned?) — stopping retries")
                    return false
                end
                local backOff = math.min((attempt - 1) * 1.5, 6) -- widen stance on retries
                local lined = false
                if not forceCreep then
                    lined = lineUpHitch(tr, impl, true) -- empty tractor: arc down onto the tool
                end
                if stopping() then return false end
                if not lined then
                    alignToPlow(tr, impl, backOff)
                end
                if stopping() then return false end
                local crept = creepUntilPrompt(tr, 20, 1) -- up to 20 studs forward
                if stopping() then return false end
                if not crept then
                    log(string.format("attempt %d: hitch prompt never showed within 20 studs — re-aligning", attempt))
                    if lined then
                        -- parts found but prompt still dead: line-up pose is
                        -- wrong for the game → stop trusting it, creep from now
                        forceCreep = true
                        log("line-up pose didn't satisfy the game — falling back to creep alignment")
                    end
                    task.wait(0.4)
                else
                    log(string.format("attempt %d: hitch prompt shows — pressing X", attempt))
                    local hooked, moved = attemptHitch(tr, impl)
                    if stopping() then return false end
                    if hooked then
                        log(string.format("✅ hitched %s (attempt %d)", impl.Name, attempt))
                        didHitch = true
                        break
                    end
                    -- X may have grabbed a NEIGHBOR instead (live bug:
                    -- the KQF3000 seeder): the tool we lined up on
                    -- didn't follow, but if the HUD now names some
                    -- other tool, THAT one got grabbed — take it off
                    -- again before retrying
                    local got = hitchedImplementName()
                    if got and got ~= impl.Name then
                        log(string.format("⚠ X grabbed the wrong tool (HUD: %s, wanted %s) — unhitching",
                            got, impl.Name))
                        pressKey(Enum.KeyCode.X)
                        task.wait(0.8)
                    else
                        log(string.format("attempt %d: X pressed but the tool didn't follow (%.1f studs) — retrying",
                            attempt, moved))
                    end
                end
            end
            if not didHitch then return false end -- killed (toggle off)
        end
        return true
    end

    -- dump §24: fields live in Objects.Fields — Configurations.Owner marks
    -- whose each is; Configurations.FieldType says WHAT kind (the game
    -- has 2 kinds of farm land — crop "Field" is one). v2 (user: "does
    -- not detect new fields"): ALSO scan every model under MY PLOTS —
    -- newly placed fields can sit on the plot instead of Objects.Fields.
    -- Returns ALL my fields, EVERY type, sorted nearest-first (the tour
    -- below groups them by type); every candidate is logged so a wrong
    -- pick is visible.
    local function findMyFields(nearPos)
        local seen, mine = {}, {}
        local function consider(d)
            if d:IsA("Model") and d:FindFirstChild("Configurations") then
                local cfg = d:FindFirstChild("Configurations")
                local owner = cfg:FindFirstChild("Owner")
                local ftype = cfg:FindFirstChild("FieldType")
                local ownerName = owner and owner.Value and owner.Value.Name or "?"
                local typeName = ftype and tostring(ftype.Value) or "?"
                local dist = (d:GetPivot().Position - nearPos).Magnitude
                seen[#seen + 1] = string.format("%s (type=%s owner=%s, %.0f studs)",
                    d.Name, typeName, ownerName, dist)
                if owner and owner.Value == LocalPlayer then
                    mine[#mine + 1] = { d = d, typeName = typeName, dist = dist }
                end
            end
        end
        local objects = workspace:FindFirstChild("Objects")
        local fields = objects and objects:FindFirstChild("Fields")
        for _, d in ipairs(fields and fields:GetChildren() or {}) do consider(d) end
        local plots = workspace:FindFirstChild("Plots")
        for _, plot in ipairs(plots and plots:GetChildren() or {}) do
            if plot:IsA("Model") then
                for _, d in ipairs(plot:GetChildren()) do consider(d) end
            end
        end
        if #seen > 0 then
            log("fields here: " .. table.concat(seen, "; "))
        end
        table.sort(mine, function(a, b) return a.dist < b.dist end)
        return mine
    end

    -- ▸ THE TOUR (user request): every field of mine grouped by land TYPE
    --   (the game has 2 kinds of farm land — crop "Field" is one),
    --   nearest-first inside each group. Each pass walks the whole tour:
    --   a field that still needs the job gets WORKED, one that doesn't is
    --   LOGGED AND SKIPPED ("1 > skip 2 > 3") — one hitch for the entire
    --   tour, then the tool goes home.
    local function fieldTour(nearPos)
        local byType, order = {}, {}
        for _, m in ipairs(findMyFields(nearPos)) do
            local g = byType[m.typeName]
            if not g then
                g = { typeName = m.typeName, fields = {} }
                byType[m.typeName] = g
                order[#order + 1] = g
            end
            g.fields[#g.fields + 1] = m
        end
        return order
    end

    -- ▸ ONE GO, BEST ORDER (user: "i want it to do a path to every feild in
    --   one go not each feild at once" → "combine A+B+C to make the most
    --   eficient path"): every field in ONE flat route, nearest-neighbour —
    --   each hop is measured from the field just finished, not from the
    --   start — so the machine takes the shortest way round the whole farm
    --   instead of restarting the order inside each land-type group.
    local function tourOrder(nearPos)
        local pool, out = {}, {}
        for _, m in ipairs(findMyFields(nearPos)) do pool[#pool + 1] = m end
        local cur = nearPos
        while #pool > 0 do
            local bi, bd
            for i, m in ipairs(pool) do
                local p = m.d:GetPivot().Position
                local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(cur.X, 0, cur.Z)).Magnitude
                if not bd or d < bd then bi, bd = i, d end
            end
            local m = table.remove(pool, bi)
            out[#out + 1] = m
            cur = m.d:GetPivot().Position
        end
        return out
    end

    -- forward-declared so driveToField below can use it (defined later)
    local driveLegKeys

    -- the field's REAL frame: the plate's CFrame + Size. A rotated plate's
    -- axis-aligned bounding box is bigger than the field AND at the wrong
    -- angle (the snake then cuts across the ridges — user screenshot
    -- confirmed: bars ran perpendicular to the plowed rows). AABB is only
    -- the last-resort fallback.
    local function fieldFrame(field)
        local plate = field:FindFirstChild("Plate")
        if not (plate and plate:IsA("BasePart")) then plate = field.PrimaryPart end
        if plate and plate:IsA("BasePart") then return plate.CFrame, plate.Size end
        local okB, cf, sz = pcall(function() return field:GetBoundingBox() end)
        if okB and cf then return cf, sz end
        return nil
    end

    -- ▸ PATHFINDER (user request): A* on a grid over the area between here
    --   and the goal, avoiding everything parked on the farm — equipment,
    --   buildings, draggables, fences, animals, store buildings and plot
    --   trees. The old single far-side corridor waypoint "kind of
    --   struggled"; this finds the genuinely quickest way around and
    --   re-plans while moving.
    -- ▸ WHAT ACTUALLY BLOCKS A TRACTOR: every CanCollide PART's oriented
    --   footprint, expanded by pad + hull. The old version marked the
    --   MODEL's axis-aligned bounding SQUARE of max(size.X, size.Z) — a
    --   60×20 barn became a 72×72 phantom block, and a rotated building
    --   blocked the wrong ground. `hull` is extra clearance kept on every
    --   side while a tool is TOWED behind the ride (the trailer is wider
    --   than the nose, and swings wide on turns — the old planner only
    --   ever saw the ride's pivot, which is how a plow clipped what the
    --   tractor had just steered around).
    local function obstacleCells(x0, z0, x1, z1, cell, blocked, ignore1, ignore2, counter, hull)
        local pad = 6 + (hull or 0)
        local function mark(minX, maxX, minZ, maxZ)
            if maxX < x0 or minX > x1 or maxZ < z0 or minZ > z1 then return end
            -- clamp to the grid: a big part must not mark cells outside it
            -- (the old loop walked the part's whole extent, so one oversized
            -- baseplate cost thousands of dead writes per plan)
            local ixA = math.max(0, math.floor((minX - x0) / cell))
            local ixB = math.min(math.floor((x1 - x0) / cell),
                math.floor((maxX - x0) / cell))
            local izA = math.max(0, math.floor((minZ - z0) / cell))
            local izB = math.min(math.floor((z1 - z0) / cell),
                math.floor((maxZ - z0) / cell))
            for ix = ixA, ixB do
                for iz = izA, izB do
                    blocked[ix * 100000 + iz] = true
                end
            end
        end
        -- ground extent of a ROTATED box: project its three axes onto world
        -- X/Z, so only the ground it really covers gets marked
        local function markPart(p)
            local cf, sz = p.CFrame, p.Size
            local rx, uy, rz = cf.RightVector, cf.UpVector, cf.LookVector
            local ex = math.abs(rx.X) * sz.X + math.abs(uy.X) * sz.Y
                + math.abs(rz.X) * sz.Z
            local ez = math.abs(rx.Z) * sz.X + math.abs(uy.Z) * sz.Y
                + math.abs(rz.Z) * sz.Z
            mark(cf.Position.X - ex / 2 - pad, cf.Position.X + ex / 2 + pad,
                 cf.Position.Z - ez / 2 - pad, cf.Position.Z + ez / 2 + pad)
        end
        local function scan(container, depth)
            if not container then return end
            for _, m in ipairs(container:GetChildren()) do
                if m ~= ignore1 and m ~= ignore2 then
                    if m:IsA("BasePart") then
                        if m.CanCollide then -- a sign can't stop a wheel
                            counter.n += 1
                            markPart(m)
                        end
                    elseif m:IsA("Model") or m:IsA("Folder") then
                        -- nested categories (Buildings.<type>.<building>)
                        -- count too; a real barn isn't always a direct child
                        if (depth or 0) < 2 then scan(m, (depth or 0) + 1) end
                    end
                end
            end
        end
        local objects = workspace:FindFirstChild("Objects")
        scan(objects and objects:FindFirstChild("Equipment"))
        scan(objects and objects:FindFirstChild("Buildings"))
        scan(objects and objects:FindFirstChild("DraggableObjects"))
        scan(objects and objects:FindFirstChild("Fences"))   -- dump: Objects.Fences
        scan(objects and objects:FindFirstChild("Animals"))  -- a cow is solid
        local stores = workspace:FindFirstChild("Stores")
        scan(stores and stores:FindFirstChild("Buildings"))  -- dump: Stores.Buildings
        local plots = workspace:FindFirstChild("Plots")
        for _, plot in ipairs(plots and plots:GetChildren() or {}) do
            if plot:IsA("Model") then scan(plot:FindFirstChild("Foliage")) end
        end
    end

    -- clearance field: for every free cell, the (capped) distance to the
    -- nearest blocked cell — multi-source BFS. The A* hug penalty and the
    -- string-pull both read it, so routes prefer the MIDDLE of open space
    -- instead of skimming equipment (user: "pathfinding is getting very
    -- close to my equipment").
    local function clearanceField(nx, nz, blocked)
        local dist, bucket = {}, {}
        local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                       { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
        for ix = 0, nx - 1 do
            for iz = 0, nz - 1 do
                local k = ix * 100000 + iz
                if blocked[k] then
                    dist[k] = 0
                    bucket[0] = bucket[0] or {}
                    table.insert(bucket[0], k)
                else
                    dist[k] = 5 -- "far" (at/over the cap)
                end
            end
        end
        for d = 0, 4 do
            local b = bucket[d]
            if b then
                for i = 1, #b do
                    local k = b[i]
                    local ix, iz = math.floor(k / 100000), k % 100000
                    for _, dir in ipairs(dirs) do
                        local jx, jz = ix + dir[1], iz + dir[2]
                        if jx >= 0 and jz >= 0 and jx < nx and jz < nz then
                            local jk = jx * 100000 + jz
                            if dist[jk] and dist[jk] > d + 1 then
                                dist[jk] = d + 1
                                bucket[d + 1] = bucket[d + 1] or {}
                                table.insert(bucket[d + 1], jk)
                            end
                        end
                    end
                end
            end
        end
        return dist
    end

    -- classic A* over the grid: 8-connected, sqrt(2) diagonal cost, no
    -- corner cutting, octile heuristic — plus a HUG PENALTY: steps near
    -- an obstacle cost extra (×4.5 at 1 cell, ×2.5, ×1.5) so the route
    -- takes open space whenever any exists (penalties only ADD cost, so
    -- the heuristic stays admissible — still the quickest path). Returns
    -- the waypoint cell list (start -> goal) or nil when boxed in.
    local function astarPath(cell, nx, nz, blocked, clearDist, sx, sz, gx, gz)
        local function key(ix, iz) return ix * 100000 + iz end
        local function h(ix, iz)
            local dx, dz = math.abs(ix - gx), math.abs(iz - gz)
            return (dx + dz) + (2 - math.sqrt(2)) * math.min(dx, dz)
        end
        local open, came, gsc = {}, {}, {}
        local startK, goalK = key(sx, sz), key(gx, gz)
        gsc[startK] = 0
        open[1] = { k = startK, ix = sx, iz = sz, f = h(sx, sz) }
        local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                       { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
        local guard = 0
        local maxPops = math.max(4000, nx * nz) -- scale with the grid, not a flat cap
        while #open > 0 do
            guard += 1
            if guard > maxPops then return nil end
            local bi = 1
            for i = 2, #open do
                if open[i].f < open[bi].f then bi = i end
            end
            local cur = table.remove(open, bi)
            if cur.k == goalK then
                local path = { { cur.ix, cur.iz } }
                local k = cur.k
                while came[k] do
                    k = came[k]
                    path[#path + 1] = { math.floor(k / 100000), k % 100000 }
                end
                -- ▸ GOAL → START becomes START → GOAL. The walk above starts
                --   at the goal and follows `came` backwards, but every
                --   consumer (nodeWorld, the string-pull) indexes grid[1]
                --   as where we stand. Returning it unreversed made the
                --   string-pull build its route from the wrong end: it
                --   produced loops that came back to the START and then
                --   drove straight at the goal through whatever was in the
                --   way.
                local n = #path
                for i = 1, math.floor(n / 2) do
                    path[i], path[n - i + 1] = path[n - i + 1], path[i]
                end
                return path
            end
            for _, d in ipairs(dirs) do
                local ix2, iz2 = cur.ix + d[1], cur.iz + d[2]
                if ix2 >= 0 and iz2 >= 0 and ix2 < nx and iz2 < nz then
                    local kk = key(ix2, iz2)
                    if not blocked[kk] then
                        local diag = d[1] ~= 0 and d[2] ~= 0
                        if not diag or (not blocked[key(cur.ix + d[1], cur.iz)]
                            and not blocked[key(cur.ix, cur.iz + d[2])]) then
                            local base = diag and 1.4142 or 1
                            local cd = clearDist[kk] or 5
                            local mul = cd >= 4 and 1 or (cd == 3 and 1.5
                                or (cd == 2 and 2.5 or 4.5))
                            local ng = gsc[cur.k] + base * mul
                            if not gsc[kk] or ng < gsc[kk] then
                                gsc[kk] = ng
                                came[kk] = cur.k
                                open[#open + 1] = { k = kk, ix = ix2, iz = iz2,
                                    f = ng + h(ix2, iz2) }
                            end
                        end
                    end
                end
            end
        end
        return nil -- no path
    end

    -- plan a route around everything: trip bbox + 50 studs margin, A* on a
    -- grid whose RESOLUTION follows the trip, then string-pulled (only
    -- direction changes survive) and corner-rounded. The first point is
    -- where we stand, the last is the exact goal. Returns world waypoints
    -- { {x,z}, ... } + obstacle count, or nil + reason + whether the
    -- straight line is at least clear of mapped obstacles.
    local function pathfindAround(startPos, goalPos, ignore1, ignore2, hull)
        local margin = 50
        local x0 = math.min(startPos.X, goalPos.X) - margin
        local x1 = math.max(startPos.X, goalPos.X) + margin
        local z0 = math.min(startPos.Z, goalPos.Z) - margin
        local z1 = math.max(startPos.Z, goalPos.Z) + margin
        local trip = (Vector3.new(goalPos.X - startPos.X, 0,
            goalPos.Z - startPos.Z)).Magnitude
        -- ▸ RESOLUTION FOLLOWS DISTANCE: the fixed 6-stud grid made the
        --   search area grow with the square of the trip and then bail
        --   ("area too big") on anything past ~600 studs — the long hauls
        --   (sell pad, town) fell back to a straight line through the farm.
        --   A 900-stud trip now plans on a ~16-stud grid, and the ~1 s
        --   replan tightens it automatically as the ride closes in.
        local baseCell = math.clamp(trip / 55, 6, 24)
        local tries = {
            { c = baseCell,       hull = hull or 0 },
            { c = baseCell * 1.5, hull = (hull or 0) * 0.5 }, -- boxed in
            { c = baseCell * 2.2, hull = 0 },                 -- last resort
        }

        -- one plan on one grid; a table without .grid = A* found no path
        local function planAt(cell, hullNow)
            local nx = math.floor((x1 - x0) / cell) + 1
            local nz = math.floor((z1 - z0) / cell) + 1
            if nx * nz > 30000 then return nil, "area too big" end
            local blocked, counter = {}, { n = 0 }
            obstacleCells(x0, z0, x1, z1, cell, blocked, ignore1, ignore2,
                counter, hullNow)
            local function cellOf(v, o) return math.floor((v - o) / cell) end
            local function k(ix, iz) return ix * 100000 + iz end
            local sx, sz = cellOf(startPos.X, x0), cellOf(startPos.Z, z0)
            local gx, gz = cellOf(goalPos.X, x0), cellOf(goalPos.Z, z0)
            local m = { cell = cell, nx = nx, nz = nz, blocked = blocked,
                        cellOf = cellOf, count = counter.n }
            -- we are already standing on the start cell: never call it blocked
            blocked[k(sx, sz)] = nil
            -- ▸ THE GOAL CAN SIT INSIDE A FOOTPRINT (a pad beside a shed):
            --   walk out to the nearest free cell instead of forcing the
            --   blocked cell open — forcing it planned a route into the wall.
            if blocked[k(gx, gz)] then
                local found
                for r = 1, 4 do
                    for dx = -r, r do
                        for dz = -r, r do
                            local ix, iz = gx + dx, gz + dz
                            if ix >= 0 and iz >= 0 and ix < nx and iz < nz
                                and not blocked[k(ix, iz)] then
                                found = { ix, iz }
                                break
                            end
                        end
                        if found then break end
                    end
                    if found then break end
                end
                if not found then return nil, "goal boxed in" end
                gx, gz = found[1], found[2]
            end
            local clearDist = clearanceField(nx, nz, blocked) -- AFTER the clears
            local grid = astarPath(cell, nx, nz, blocked, clearDist, sx, sz, gx, gz)
            m.clearDist = clearDist
            m.grid = grid
            if not grid then return m end -- keep the map for the straight-line check
            return m
        end

        local map, why, lastMap
        for _, t in ipairs(tries) do
            map, why = planAt(t.c, t.hull)
            if map then
                if map.grid then break end
                lastMap = map
            end
        end
        if not (map and map.grid) then
            -- ▸ NO BLIND FALLBACK: say whether a straight line is at least
            --   free of mapped obstacles. The old caller drove straight at
            --   the goal no matter what was in the way.
            local direct = false
            if lastMap then
                direct = true
                local steps = math.ceil(math.max(math.abs(goalPos.X - startPos.X),
                    math.abs(goalPos.Z - startPos.Z)) / (lastMap.cell * 0.5))
                for i = 0, steps do
                    local t = i / math.max(steps, 1)
                    local ix = lastMap.cellOf(startPos.X + (goalPos.X - startPos.X) * t, x0)
                    local iz = lastMap.cellOf(startPos.Z + (goalPos.Z - startPos.Z) * t, z0)
                    if ix >= 0 and iz >= 0 and ix < lastMap.nx and iz < lastMap.nz
                        and lastMap.blocked[ix * 100000 + iz] then
                        direct = false
                        break
                    end
                end
            end
            return nil, why or "no path", direct
        end

        local cell, nx, nz = map.cell, map.nx, map.nz
        local blocked, clearDist, grid = map.blocked, map.clearDist, map.grid
        local cellOf = map.cellOf
        local function nodeWorld(i)
            if i == 1 then return startPos.X, startPos.Z end
            return x0 + grid[i][1] * cell + cell / 2, z0 + grid[i][2] * cell + cell / 2
        end
        local function lineClear(ax, az, bx, bz)
            local steps = math.ceil(math.max(math.abs(bx - ax), math.abs(bz - az)) / (cell * 0.5))
            for i = 0, steps do
                local t = i / math.max(steps, 1)
                local ix = cellOf(ax + (bx - ax) * t, x0)
                local iz = cellOf(az + (bz - az) * t, z0)
                if ix < 0 or iz < 0 or ix >= nx or iz >= nz then return false end
                local k = ix * 100000 + iz
                if blocked[k] then return false end
                -- long shortcuts keep a real margin: never cut closer than
                -- 2 clear cells to anything the mapper marked
                if (clearDist[k] or 0) < 2 then return false end
            end
            return true
        end
        -- string-pull: from the last kept point keep the furthest node
        -- still reachable in one straight clear line
        local pts = { { startPos.X, startPos.Z } }
        local a = 1
        while a < #grid do
            local last = a + 1
            local ax, az = nodeWorld(a)
            for b = a + 2, #grid do
                local bx, bz = nodeWorld(b)
                if not lineClear(ax, az, bx, bz) then break end
                last = b
            end
            local px, pz = nodeWorld(last)
            pts[#pts + 1] = { px, pz }
            a = last
        end
        -- land on the exact goal — if that straight hop fails the margin
        -- check, step through the last grid node first instead of cutting it
        local ax, az = pts[#pts][1], pts[#pts][2]
        local bx, bz = nodeWorld(#grid)
        if not lineClear(ax, az, goalPos.X, goalPos.Z)
            and (math.abs(bx - ax) > 0.5 or math.abs(bz - az) > 0.5) then
            pts[#pts + 1] = { bx, bz }
        end
        pts[#pts + 1] = { goalPos.X, goalPos.Z }

        -- ▸ ROUND THE CORNERS, DROP DUPLICATES. A raw A* polyline turns in
        --   place, so the align driver has to swing the nose through the
        --   whole angle at every corner (and the towed tool swings wider
        --   still). Each sharp vertex becomes a short chamfer — and the
        --   chamfer is only used when it is ITSELF clear, so a rounded
        --   corner can never clip what the polyline avoided.
        local out = { pts[1] }
        for i = 2, #pts - 1 do
            local p, q, r = pts[i - 1], pts[i], pts[i + 1]
            local d1x, d1z = q[1] - p[1], q[2] - p[2]
            local d2x, d2z = r[1] - q[1], r[2] - q[2]
            local l1 = math.sqrt(d1x * d1x + d1z * d1z)
            local l2 = math.sqrt(d2x * d2x + d2z * d2z)
            local rounded = false
            if l1 > 8 and l2 > 8 then
                local cosang = (d1x * d2x + d1z * d2z) / (l1 * l2)
                if cosang < 0.7 then -- a turn sharper than ~45°
                    local d = math.min(10, l1 * 0.35, l2 * 0.35)
                    local q1 = { q[1] - d1x / l1 * d, q[2] - d1z / l1 * d }
                    local q2 = { q[1] + d2x / l2 * d, q[2] + d2z / l2 * d }
                    if lineClear(q1[1], q1[2], q2[1], q2[2]) then
                        out[#out + 1] = q1
                        out[#out + 1] = q2
                        rounded = true
                    end
                end
            end
            if not rounded then out[#out + 1] = q end
        end
        out[#out + 1] = pts[#pts]
        local final = { out[1] }
        for i = 2, #out do
            local px, pz = final[#final][1], final[#final][2]
            local ddx, ddz = out[i][1] - px, out[i][2] - pz
            if ddx * ddx + ddz * ddz >= 9 then final[#final + 1] = out[i] end
        end
        -- the exact goal is never dropped by the merge
        local lx, lz = final[#final][1], final[#final][2]
        if lx ~= goalPos.X or lz ~= goalPos.Z then
            final[#final + 1] = { goalPos.X, goalPos.Z }
        end
        return final, map.count
    end

    -- ▸ ALIGN DRIVER (user: "is there not a away we can force it to follow the
    --   line" → "number 2 i think we can try that alignPosition" → "why dont we
    --   make it tween to align so it just has to go forward"): instead of
    --   wiggling WASD, attach the game's OWN physics constraints. AlignOrientation
    --   rotates the chassis toward a point ON the leg, rate-capped, which IS the
    --   "tween to align" — and AlignPosition then pushes only ALONG THE NOSE, so
    --   the tractor simply drives forward once it is lined up and can never slide
    --   sideways. MaxForce/MaxTorque stay finite so a real collision still stops
    --   it; MaxVelocity caps the speed and drops while the nose is still turning
    --   (creep while correcting, the key driver's rule). Note: writing the
    --   chassis CFrame every frame was REJECTED — physics dies and the towed
    --   tool jackknifes.
    local ALIGN_MAXVEL = 24 -- studs/s
    local ALIGN_YAW = 70    -- deg/s — arcs, not pivots (a pivot drags the towed tool sideways)
    local ALIGN_AIM = 14    -- how far up the leg the aim point sits
    local function alignDriveStart(tr)
        local part = tr.PrimaryPart or tr:FindFirstChildWhichIsA("BasePart", true)
        if not part then return nil, "no BasePart" end
        local mass = 0
        for _, d in ipairs(tr:GetDescendants()) do
            if d:IsA("BasePart") then mass += d:GetMass() end
        end
        if mass <= 0 then return nil, "no mass" end
        local a0 = Instance.new("Attachment")
        a0.Name = "SpudAlign"
        a0.Parent = part
        local pos = Instance.new("AlignPosition")
        pos.Name = "SpudAlignPos"
        pos.Mode = Enum.PositionAlignmentMode.OneAttachment
        pos.Attachment0 = a0
        pos.MaxForce = Vector3.new(mass * 30, 0, mass * 30) -- horizontal only
        pos.ApplyAtCenterOfMass = true -- no stray tipping torque
        pos.MaxVelocity = ALIGN_MAXVEL
        pos.Responsiveness = 30
        pos.Parent = part
        local ori = Instance.new("AlignOrientation")
        ori.Name = "SpudAlignOri"
        ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ori.Attachment0 = a0
        ori.MaxTorque = mass * 10
        ori.MaxAngularVelocity = math.rad(ALIGN_YAW * 1.5)
        ori.Responsiveness = 20
        ori.Parent = part
        -- start the targets where the tractor IS, or the first physics step
        -- would yank it toward the world origin. Heading is carried as a
        -- direction VECTOR and written with CFrame.lookAt — no hand-rolled
        -- yaw-to-Euler conversion, so no 180° convention trap.
        local cf = part.CFrame
        local look = cf.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
        flat = flat.Unit
        pos.Position = cf.Position
        ori.CFrame = CFrame.lookAt(Vector3.zero, flat)
        return {
            part = part, a0 = a0, pos = pos, ori = ori, mass = mass, dir = flat,
        }
    end

    local function alignDriveStop(h)
        if not h then return end
        for _, c in ipairs({ h.pos, h.ori, h.a0 }) do
            pcall(function() c:Destroy() end)
        end
    end

    -- one tick: pure pursuit on the leg being driven + FORWARD-ONLY thrust.
    -- The nose eases toward a point ON the leg (ALIGN_AIM studs ahead of our
    -- projection onto it), so a parallel offset converges the way a real
    -- driver corrects it. Aiming at the leg DIRECTION instead is the old bug
    -- that settled into a parallel line beside it. ALIGN_YAW caps how fast the
    -- nose may swing — that is the "tween to align": the chassis rotates
    -- smoothly instead of snapping. The pull is always along the NOSE: a
    -- wheeled tractor pushes forward, it never slides sideways.
    local function alignDriveStep(h, tr, ax, az, bx, bz, dt)
        local p = tr:GetPivot().Position
        local A = Vector3.new(ax, 0, az)
        local B = Vector3.new(bx, 0, bz)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 0.5 then return end
        local dir = leg / legLen
        local along = (Vector3.new(p.X, 0, p.Z) - A):Dot(dir)
        local aim = A + dir * math.clamp(along + ALIGN_AIM, 0, legLen)
        local want = Vector3.new(aim.X - p.X, 0, aim.Z - p.Z)
        if want.Magnitude < 0.5 then return end
        want = want.Unit
        local ang = math.acos(math.clamp(h.dir:Dot(want), -1, 1))
        if ang > 1e-4 then
            local t = math.min(1, math.rad(ALIGN_YAW) * (dt or 0.12) / ang)
            h.dir = (h.dir * (1 - t) + want * t).Unit
        end
        -- creep while the nose is still turning (the key driver's rule)
        h.pos.MaxVelocity = math.clamp(ALIGN_MAXVEL * (1 - ang / 1.6),
            ALIGN_MAXVEL * 0.15, ALIGN_MAXVEL)
        h.ori.CFrame = CFrame.lookAt(Vector3.zero, h.dir)
        local goal = p + h.dir * math.min((aim - p).Magnitude, ALIGN_AIM)
        h.pos.Position = Vector3.new(goal.X, p.Y, goal.Z)
    end

    -- ▸ ONE STRAIGHT LEG ON THE ALIGN MOVER (user: "we got to change the way
    --   the harvester moves on the feild. it needs to stay on the line not
    --   wiggle everywhere"): the same pure-pursuit mover that drives to the
    --   field now drives the sweep — one leg at a time, so a stuck corner
    --   only costs that leg. Returns true = arrived, false = gave up (caller
    --   drives this leg with keys), nil = user stopped. `stats` collects how
    --   far off the line it got and how often it crossed it, so a run says
    --   whether it really held the line.
    local function alignDriveLeg(tr, from, goal, tol, stats)
        local A = Vector3.new(from.X, 0, from.Z)
        local B = Vector3.new(goal.X, 0, goal.Z)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 1 then return true end
        local dir = leg / legLen
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        local h = alignDriveStart(tr)
        if not h then return false end
        local mark, markT = tr:GetPivot().Position, os.clock()
        local deadline = os.clock() + 8 + legLen / 6
        local t0 = os.clock()
        local ok, prevSide = false, nil
        while os.clock() < deadline do
            if stopping() then alignDriveStop(h) return nil end
            local p = tr:GetPivot().Position
            local rel = Vector3.new(p.X, 0, p.Z) - A
            local cross = rel:Dot(perp)
            -- stats skip the first 1.5 s of a leg: that is the corner entry,
            -- where being far off the new line is expected, not a wiggle
            if stats and os.clock() - t0 > 1.5 then
                stats.worst = math.max(stats.worst or 0, math.abs(cross))
                local side = cross > 0.5 and 1 or (cross < -0.5 and -1 or prevSide)
                if side and prevSide and side ~= prevSide then
                    stats.flips = (stats.flips or 0) + 1
                end
                prevSide = side
            end
            if rel:Dot(dir) >= legLen - tol and math.abs(cross) <= 8 then
                ok = true
                break
            end
            -- 3 s without 3 studs = the constraint is losing to the seat
            -- controller (or the vehicle is jammed): stop and let keys try
            if (p - mark).Magnitude >= 3 then
                mark, markT = p, os.clock()
            elseif os.clock() - markT > 3 then
                break
            end
            alignDriveStep(h, tr, A.X, A.Z, B.X, B.Z, 0.1)
            -- ease off into the leg end (the key driver's rule): the corner
            -- starts slow instead of carrying full speed into the turn
            local left = legLen - rel:Dot(dir)
            if left < legLen * 0.15 then
                h.pos.MaxVelocity = math.max(
                    h.pos.MaxVelocity * math.clamp(left / (legLen * 0.15), 0.2, 1), 2)
            end
            task.wait(0.1)
        end
        alignDriveStop(h)
        return ok
    end

    -- ▸ HOW MUCH EXTRA ROOM A TOWED TOOL NEEDS. The planner used to see
    --   only the ride's pivot, so a hitched plow — wider than the nose and
    --   swinging on every turn — clipped whatever the tractor had just
    --   steered around. The tool's narrow side is its width across travel;
    --   half of that, plus a little swing allowance, becomes extra obstacle
    --   padding. 0 when nothing is towed (the harvester is its own tool).
    local function towMargin(ride, impl)
        if not impl or impl == ride or not impl.Parent then return 0 end
        local ok, _, sz = pcall(function() return impl:GetBoundingBox() end)
        if not ok or not sz then return 6 end
        return math.clamp(math.min(sz.X, sz.Z) / 2 + 2, 4, 14)
    end

    -- to the NEAREST CORNER of the field (user: start at a corner, not the
    -- center) — 4 studs inside the edge; arrive within 8 studs of it. The
    -- route comes from A* around everything parked on the farm and is
    -- RE-PLANNED about once a second while moving (user request: "find the
    -- most useful and quickest path every second"). REAL keys drive it
    -- (true physics — the old glide WHIPPED the towed tool); the glide
    -- stays only as the fallback when keys can't move the tractor.
    -- ▸ THE ROUTE FOLLOWER: everything below was driveToField's body — A*
    --   legs re-planned about once a second, then the align driver (or real
    --   keys, or the glide fallback) drives them. Shared now, because the
    --   sell trip drives the harvester to a pad and back the same way.
    local function driveRoute(tr, seat, goal, impl)
        local startPos = tr:GetPivot().Position
        local hull = towMargin(tr, impl)
        local legs, info, direct = pathfindAround(startPos, goal, tr, impl, hull)
        if not legs then
            if direct then
                -- no plan, but nothing mapped stands on the straight line:
                -- drive it as a real two-point route (legs[1] = we are here)
                log("⚠ pathfinding failed (" .. tostring(info) .. ") — the straight line is clear, driving it")
                legs = { { startPos.X, startPos.Z }, { goal.X, goal.Z } }
                info = 0
            else
                -- ▸ NEVER DRIVE BLIND: the old fallback was a single point
                --   (so the follower had no leg to drive) and then a straight
                --   line through whatever was mapped. Stopping with a
                --   readable reason beats a route through the barn.
                log("⚠ no safe route to the target (" .. tostring(info)
                    .. ") — stopping instead of driving through the farm")
                return false, "no safe route (" .. tostring(info) .. ")"
            end
        else
            log(string.format("path: %d legs, %d obstacle part(s) mapped (tool margin %d)",
                #legs - 1, info, hull))
        end
        local useKeys = driveLegKeys ~= nil
        local ah, alignWhy = alignDriveStart(tr)
        local useAlign = ah ~= nil
        if useAlign then
            log(string.format("route: ALIGN driver on (mass %.0f, maxvel %d, aim %d) — physics follows the line",
                ah.mass, ALIGN_MAXVEL, ALIGN_AIM))
        else
            log("route: align driver unavailable (" .. tostring(alignWhy) .. ") — driving with keys")
        end
        local alignClock, alignMark = os.clock(), tr:GetPivot().Position
        -- telemetry: measured with the game's own positions, not our intent —
        -- the first run then says WHICH number is wrong instead of guessing
        local telePrev, teleClock = tr:GetPivot().Position, os.clock()
        local teleMax, teleSum, teleN = 0, 0, 0
        local li, lastPlan, pass = 2, 0, 0
        local deadline = os.clock() + 120
        while os.clock() < deadline do
            pass += 1
            if stopping() then alignDriveStop(ah) return nil end
            local p = tr:GetPivot().Position
            -- stuck probe: 3 s without 3 studs of progress = the constraint is
            -- losing to the game's controller (or we are jammed) — hand back
            -- to the key driver instead of grinding
            if useAlign then
                if (p - alignMark).Magnitude >= 3 then
                    alignMark, alignClock = p, os.clock()
                elseif os.clock() - alignClock > 3 then
                    useAlign = false
                    alignDriveStop(ah)
                    log("align driver stalled (3 s without progress) — falling back to keys")
                end
            end
            -- re-plan ~once a second: parked tools shift around, and the
            -- fresh A* always re-picks the quickest current route
            if os.clock() - lastPlan > 1 then
                lastPlan = os.clock()
                local newLegs, n = pathfindAround(p, goal, tr, impl, hull)
                if stopping() then alignDriveStop(ah) return nil end
                if newLegs then
                    if info ~= n then
                        log(string.format("re-routed: %d legs, %d obstacle part(s) mapped", #newLegs - 1, n))
                    end
                    legs, info = newLegs, n
                    -- follow the FRESH path from here (legs[1] = now). On a
                    -- failed replan the old legs keep their old first point,
                    -- so the cursor must not be reset to it.
                    li = 2
                else
                    log("re-plan failed (" .. tostring(n) .. ") — keeping the last path")
                end
            end
            local g = legs[math.min(li, #legs)]
            local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(g[1], 0, g[2])).Magnitude
            if d <= 6 then
                if li < #legs then
                    li += 1
                    g = legs[li]
                else
                    local dg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                    if dg <= 8 then
                        if useAlign then
                            log(string.format("route: arrived in %d ticks — worst line error %.1f studs",
                                pass, teleMax))
                        end
                        alignDriveStop(ah)
                        return true, pass
                    end
                end
            end
            if useAlign then
                -- cross-track error vs the leg we are on, once a second
                local a1 = legs[math.max(li - 1, 1)]
                local lx, lz = g[1] - a1[1], g[2] - a1[2]
                local ll = math.sqrt(lx * lx + lz * lz)
                if ll > 0.5 then
                    lx, lz = lx / ll, lz / ll
                    local off = math.abs((p.X - a1[1]) * lz - (p.Z - a1[2]) * lx)
                    teleMax = math.max(teleMax, off)
                    teleSum, teleN = teleSum + off, teleN + 1
                end
                local now = os.clock()
                if now - teleClock >= 1 then
                    local spd = (p - telePrev).Magnitude / (now - teleClock)
                    local nose = seat and seat.CFrame.LookVector or Vector3.new(0, 0, 1)
                    local want = Vector3.new(g[1] - p.X, 0, g[2] - p.Z)
                    local n2 = Vector3.new(nose.X, 0, nose.Z)
                    local ang = 0
                    if n2.Magnitude > 0.1 and want.Magnitude > 0.5 then
                        ang = math.deg(math.acos(math.clamp(n2.Unit:Dot(want.Unit), -1, 1)))
                    end
                    log(string.format("route: line %.1f studs off · %.0f studs/s · nose %.0f° off · leg %d/%d",
                        teleSum / math.max(teleN, 1), spd, ang, li, #legs))
                    telePrev, teleClock = p, now
                    teleSum, teleN = 0, 0
                end
                alignDriveStep(ah, tr, a1[1], a1[2], g[1], g[2], 0.12)
            elseif useKeys then
                local res = driveLegKeys(tr, seat, p, Vector3.new(g[1], p.Y, g[2]), 6)
                if res == nil then alignDriveStop(ah) return nil end
                if res == false then
                    useKeys = false
                    log("keys didn't drive to the field — falling back to glide")
                end
            end
            if not useAlign and not useKeys then
                glideTractor(tr, Vector3.new(g[1], p.Y, g[2]))
            end
            task.wait(0.12)
        end
        alignDriveStop(ah)
        local p = tr:GetPivot().Position
        local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
        if d <= 8 then return true, pass end
        return false, "still " .. math.floor(d) .. " studs short"
    end

    local function driveToField(tr, field, seat, impl)
        local baseCF, baseSize = fieldFrame(field)
        if not baseCF then return false, "no bounds" end
        local c = baseCF.Position
        local rx = Vector3.new(baseCF.RightVector.X, 0, baseCF.RightVector.Z).Unit
        local rz = Vector3.new(baseCF.LookVector.X, 0, baseCF.LookVector.Z).Unit
        local p0 = tr:GetPivot().Position - c
        -- nearest corner along the plate's OWN axes, 4 studs inside
        local goal = c
            + rx * math.max(baseSize.X / 2 - 4, 2) * (p0:Dot(rx) >= 0 and 1 or -1)
            + rz * math.max(baseSize.Z / 2 - 4, 2) * (p0:Dot(rz) >= 0 and 1 or -1)
        log(string.format("field corner target: (%.0f, %.0f)", goal.X, goal.Z))
        return driveRoute(tr, seat, goal, impl)
    end

    -- honest per-cell read via the game's OWN FieldHelper module (dump §26:
    -- require() works even though Source is blocked) — returns a table of
    -- per-Stage counts plus .total, e.g. { Empty = 50, total = 50 } on a
    -- fresh field, { Plowed = 50, total = 50 } after the plow pass, then
    -- { Cultivated = 50, total = 50 } after the cultivator.
    local function countStages(field)
        local ok, stages = pcall(function()
            local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            local F = mods and mods:FindFirstChild("FieldHelper")
            assert(F, "FieldHelper missing")
            F = require(F)
            assert(type(F.GetCells) == "function", "GetCells missing")
            local cells = F.GetCells(field)
            assert(type(cells) == "table", "GetCells returned no table")
            local st = { total = 0 }
            for _, cell in pairs(cells) do
                if type(cell) == "table" then
                    st.total += 1
                    local s = tostring(cell.Stage or "?")
                    st[s] = (st[s] or 0) + 1
                end
            end
            return st
        end)
        if ok then return stages end
        return nil
    end

    -- world centers of every cell still at `stage` — §26 ground truth:
    -- GetCells is a dict keyed by id = x*128+y (1-based x/y), the grid is
    -- cols×rows of 10-stud tiles laid over the plate, and the plate is
    -- ROTATED — so the columns' axis follows whichever plate side measures
    -- cols*10 studs. Returns { {X=, Y=, Z=}, ... } or nil when unreadable.
    -- `stage` may also be a FUNCTION (the harvester targets "any stage
    -- that isn't one of the four we know" — see whichNeed).
    local function cellsAtStage(field, stage, baseCF, baseSize)
        local ok, out = pcall(function()
            local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            local F = mods and mods:FindFirstChild("FieldHelper")
            assert(F, "FieldHelper missing")
            F = require(F)
            assert(type(F.GetCells) == "function", "GetCells missing")
            local cells = F.GetCells(field)
            assert(type(cells) == "table", "GetCells returned no table")
            local cols, rows, missed = 0, 0, {}
            for k, cell in pairs(cells) do
                if type(cell) == "table" then
                    local x, y
                    local id = tonumber(k)
                    if id then -- dict key = encoded id (all 50 decoded §26)
                        x, y = math.floor(id / 128), id % 128
                    elseif typeof(cell.Position) == "Vector3" then
                        x, y = cell.Position.X, cell.Position.Y
                    end
                    if x and y then
                        if x > cols then cols = x end
                        if y > rows then rows = y end
                        local s = tostring(cell.Stage or "?")
                        if (type(stage) == "function" and stage(s))
                            or (type(stage) ~= "function" and s == stage) then
                            missed[#missed + 1] = { x = x, y = y }
                        end
                    end
                end
            end
            if cols == 0 or rows == 0 then return nil end
            local axX = baseSize.X / 10 -- cells across the plate's local X
            local colsAlongX = math.abs(axX - cols) <= math.abs(axX - rows)
            local pts = {}
            for _, m in ipairs(missed) do
                local lx, lz
                if colsAlongX then
                    lx = (m.x - (cols + 1) / 2) * 10
                    lz = (m.y - (rows + 1) / 2) * 10
                else -- plate turned: the columns span local Z instead
                    lx = (m.y - (rows + 1) / 2) * 10
                    lz = (m.x - (cols + 1) / 2) * 10
                end
                local p = (baseCF * CFrame.new(lx, 0, lz)).Position
                pts[#pts + 1] = { X = p.X, Y = p.Y, Z = p.Z }
            end
            return pts
        end)
        if ok then return out end
        return nil
    end

    -- ▸ WHAT EACH JOB AIMS AT (shared by probeWork, runPass and sweepField).
    --   The three tractor jobs target ONE stage each (Empty → Plowed →
    --   Cultivated → Seeded, every transition fired by the game itself on
    --   drive-over). The HARVESTER has no stage name in the dumps, so "a
    --   crop is standing here" = any stage that is NOT one of the four we
    --   know — the per-field log prints every stage it sees, so the real
    --   name shows up in the Console after one run.
    local KNOWN_STAGES = {
        Empty = true, Plowed = true, Cultivated = true, Seeded = true,
    }
    local function grownStage(s) return not KNOWN_STAGES[s] end

    -- how many cells in `st` still need `job` (nil when counts unknown)
    local function whichNeed(job, st)
        if not st or st.total == 0 then return nil end
        if job.grown then
            local left = st.total
            for name in pairs(KNOWN_STAGES) do
                left -= (st[name] or 0)
            end
            return left
        end
        return st[job.stage] or 0
    end

    -- world points of the cells still needing `job` (nil = unreadable)
    local function whichCells(job, field, baseCF, baseSize)
        if job.grown then
            return cellsAtStage(field, grownStage, baseCF, baseSize)
        end
        return cellsAtStage(field, job.stage, baseCF, baseSize)
    end

    -- scan every field of mine ONCE (nearest-first) and say what work is
    -- left: any bare cells (the PLOW's job) and any Plowed cells (the
    -- CULTIVATOR's job). Every field's real state is logged. A failed
    -- count read never disqualifies a field (unknown = work to try).
    local function probeWork(nearPos)
        local crops = findMyFields(nearPos)
        if #crops == 0 then return false, false, false, false end
        local needPlow, needCult, needSeed, needHarv =
            false, false, false, false
        for _, m in ipairs(crops) do
            local st = countStages(m.d)
            if st and st.total > 0 then
                local bare, plowedN = st.Empty or 0, st.Plowed or 0
                local cultN, seedN = st.Cultivated or 0, st.Seeded or 0
                local grownN = whichNeed(JOBS[4], st) or 0
                -- EVERY stage name the field reports right now (so the
                -- harvester's real "crop is standing" name becomes visible)
                local parts = {}
                for name, n in pairs(st) do
                    if name ~= "total" then
                        parts[#parts + 1] = string.format("%s=%d", name, n)
                    end
                end
                table.sort(parts)
                log(string.format(
                    "%s: %d bare, %d plowed, %d cultivated, %d seeded, %d standing, %d total cells  [%s]",
                    m.d.Name, bare, plowedN, cultN, seedN, grownN, st.total,
                    table.concat(parts, " ")))
                if bare > 0 then needPlow = true end
                if plowedN > 0 then needCult = true end
                if cultN > 0 then needSeed = true end
                if grownN > 0 then needHarv = true end
            else
                log(m.d.Name .. ": cell count unavailable — treating as needing work")
                needPlow, needCult, needSeed = true, true, true
                needHarv = true -- unknown counts never skip the harvest
            end
        end
        return needPlow, needCult, needSeed, needHarv
    end

    -- ▸ SEEDER STEP 1 (dump §27 settled WHERE the seed state lives): the
    --   seeder (KADL, EquipmentType="Planter") keeps its seed load in
    --   Configurations — Carrying [StringValue] = seed type ("Wheat"),
    --   Capacity [IntValue] = CURRENT seeds, MaxCapacity [IntValue] = the
    --   cap (Farmer's Club "SeederCapacity_*" upgrades raise it). Same
    --   Capacity/MaxCapacity/Carrying pattern the Trailer and the harvester
    --   use, and the VehicleHUD capacity bar mirrors it live ("0 / 50" +
    --   crop name). All of it sits on the ONE KADL instance in
    --   Objects.Equipment, so it reads the same spawned or in storage.
    -- Returns count, cap, kind — or nil when unreadable (seedCheck then
    -- treats it as EMPTY: user's decision).
    local function seederSeedState(seeder)
        local ok, count, cap, kind = pcall(function()
            local conf = seeder:FindFirstChild("Configurations")
            if not conf then return nil end
            local c = conf:FindFirstChild("Capacity")
            if not (c and c:IsA("IntValue")) then return nil end
            local m = conf:FindFirstChild("MaxCapacity")
            local k = conf:FindFirstChild("Carrying")
            return c.Value,
                (m and m:IsA("IntValue")) and m.Value or nil,
                (k and k:IsA("StringValue")) and k.Value or nil
        end)
        if not ok or count == nil then return nil end
        return count, cap, kind
    end

    -- how many cells across ALL my fields still need seeding (cells at
    -- "Cultivated"), and across how many fields — the yardstick for the
    -- user's re-seed rule: "if the seeder has seeds in it and the fields
    -- are missing some seeding i want it to go back and seed on that
    -- plot of field"
    local function seedNeedLeft(nearPos)
        local crops = findMyFields(nearPos)
        local cells, fields = 0, 0
        for _, m in ipairs(crops) do
            local st = countStages(m.d)
            if st and st.total > 0 and (st.Cultivated or 0) > 0 then
                cells += st.Cultivated
                fields += 1
            end
        end
        return cells, fields
    end

    -- the seeder's CURRENT seed count right now (nil when unreadable)
    local function seederSeeds(tr)
        local seeder = findImplement("Planter", tr:GetPivot().Position, tr)
        if not seeder then return nil end
        local count = seederSeedState(seeder)
        return count
    end

    -- ▸ THE SEED SHOP (user: "if the seeder is empty at it's run, we need it
    --   to tp to the shop and buy the spesific seed" + the real flow they
    --   spelled out: "tp to crate > place crate on counter > talk the the guy
    --   (alr does) > pick it back up > go to seeder"). Seeds are bought from
    --   the FarmCo Owner NPC inside FarmCo, and the thing you buy is a CRATE
    --   off the shelf (the locked draggables — their context key is
    --   LockedCarry=E). Dump-confirmed anchors: Stores.NPCs = {FarmCo Owner,
    --   …} (§5), Markers.GotoLocations has a FarmCo waypoint (§24), the
    --   context keys are InteractWithNPC=F / Carry=E / Drop=X / FillSeeder=V
    --   (context-key dump — the same key system F already uses for
    --   ExitEquipment), and coins are live at GuiViews.HUD.MainHUD.
    --   TopRightBar.CoinsDisplay.Contents.Balance (§17). Which seed = the Farm
    --   tab picker (seedChoice, read from the game's own FieldHelper.SEED_TYPE).
    --   The trip, stage by stage, exactly as the user described: find the crate
    --   labelled with that seed → tp to it → E (carry) → tp to the counter →
    --   X (put it down) → F at the owner (buy; the menu's Buy button is called
    --   through its OWN handlers if there is one — never a mouse, never a
    --   spoofed remote) → VERIFY with the balance → E (pick it back up) → tp to
    --   the seeder → V (FillSeeder) → VERIFY the seeder's seed count. Every
    --   stage logs the game's own context-action list, and a miss logs the
    --   shelf / the menu's buttons, so nothing fails silently.
    local seedChoice -- the Farm tab picker writes this (declared up here
                     -- because the seed check below reads it)
    -- one shop trip per run, max: a failed purchase must never send the
    -- character teleporting again later in the same run
    local seedShopTried = false
    -- the game's own SEED_TYPE table both ways (filled by the Farm tab
    -- picker's read of FieldHelper): names for the dropdown, ids so a crate
    -- that keeps the numeric SeedType can still be named.
    local seedIdOf, seedNameOf = {}, {}

    local function coinBalance()
        local ok, n = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local b = pg.GuiViews.HUD.MainHUD.TopRightBar.CoinsDisplay.Contents.Balance
            local txt = b:IsA("TextLabel") and b.Text or nil
            if not txt then
                local l = b:FindFirstChildWhichIsA("TextLabel", true)
                txt = l and l.Text
            end
            return tonumber((tostring(txt):gsub("[^%d]", "")))
        end)
        if ok then return n end
        return nil
    end

    -- where the shop is: the FarmCo waypoint if it's there, else the owner NPC
    local function findSeedShop()
        local function partOf(m)
            if m:IsA("BasePart") then return m end
            return m:FindFirstChildWhichIsA("BasePart", true)
        end
        local markers = workspace:FindFirstChild("Markers")
        local gotos = markers and markers:FindFirstChild("GotoLocations")
        if gotos then
            for _, m in ipairs(gotos:GetDescendants()) do
                if m.Name:lower():find("farmco", 1, true) then
                    local p = partOf(m)
                    if p then return p.Position, "Markers.GotoLocations." .. m.Name end
                end
            end
        end
        local stores = workspace:FindFirstChild("Stores")
        local npcs = stores and stores:FindFirstChild("NPCs")
        if npcs then
            for _, m in ipairs(npcs:GetChildren()) do
                if m.Name:lower():find("farmco", 1, true) then
                    local p = partOf(m)
                    if p then return p.Position, "Stores.NPCs." .. m.Name end
                end
            end
        end
        return nil
    end

    -- tp the CHARACTER anywhere (heading kept). On foot nothing is towed, so
    -- a straight CFrame set is safe — the "never snap a tractor" rule is
    -- about vehicles, not the player.
    local function tpChar(p)
        local ch = LocalPlayer.Character
        local r = ch and ch:FindFirstChild("HumanoidRootPart")
        if not r then return false end
        r.CFrame = CFrame.new(p + Vector3.new(0, 3, 0)) * (r.CFrame - r.CFrame.Position)
        return true
    end

    -- the game's OWN "what can I do right now" list (PCGP_ContextActions.
    -- Buttons, the context-key dump). It is proximity-driven, so logging it
    -- also says whether the game thinks we're at the crate / counter / seeder.
    local function contextActions()
        local out = {}
        local ok = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local btns = pg.GuiViews.HUD.PCGP_ContextActions.Buttons
            for _, b in ipairs(btns:GetChildren()) do
                if b:IsA("GuiObject") and b.Visible then out[#out + 1] = b.Name end
            end
        end)
        if not ok then return nil end
        return out
    end

    -- ▸ IS THE CHARACTER HOLDING ANYTHING? (dump §18: a successful crate
    --   pickup fills the character's CarryLinks folder; empty = bare hands.)
    local function carrying()
        local ch = LocalPlayer.Character
        local links = ch and ch:FindFirstChild("CarryLinks")
        if not links then return false end
        return #links:GetChildren() > 0
    end

    -- ▸ PICK A CRATE UP (dump §18: standing at a seed box lights the plain
    --   "Carry" prompt, bound to E — NOT PickupSeedBox). One key press is not
    --   proof: press E until the game actually carries it, and log each miss
    --   with the game's own action list so a failure is readable.
    local function carryCrate(what)
        for attempt = 1, 3 do
            if stopping() then return false end
            pressKey(Enum.KeyCode.E) -- Carry = E
            task.wait(0.9)
            if carrying() then
                log("✅ carrying the " .. what .. " (E, attempt " .. attempt .. ")")
                return true
            end
            local acts = contextActions()
            log("the " .. what .. " didn't come up on attempt " .. attempt
                .. " (hands still empty) — the game offers: "
                .. (acts and (#acts > 0 and table.concat(acts, " · ") or "nothing") or "unreadable"))
        end
        return false
    end

    local function crateLabel(m) -- whatever the crate itself shows (crop? price?)
        local texts = {}
        for _, t in ipairs(m:GetDescendants()) do
            if (t:IsA("TextLabel") or t:IsA("TextButton")) and t.Text ~= "" then
                texts[#texts + 1] = t.Text
                if #texts >= 3 then break end
            end
        end
        return table.concat(texts, " | ")
    end

    local function crateOwner(m)
        local conf = m:FindFirstChild("Configurations")
        local o = conf and conf:FindFirstChild("Owner")
        if o and o:IsA("ObjectValue") and o.Value then return o.Value.Name end
        if o and o:IsA("StringValue") then return o.Value end
        return nil
    end

    -- ▸ THE GAME'S OWN SEED TAG (user: "when it goes to the shop make it
    --   search the game or smth for the spesific seed the user input into the
    --   thing in the farming tab then make it tp to that seed then carry it"):
    --   a seed box carries Configurations.SeedType — the seed's NAME as a
    --   StringValue (dump §27), or the numeric SEED_TYPE id on some boxes.
    --   That tag is the identity, so nothing is guessed from a model name.
    --   Returns the seed name it stands for + the raw value (for the log).
    local function crateSeedType(m)
        local conf = m:FindFirstChild("Configurations")
                or m:FindFirstChild("Configurations", true)
        local v = conf and conf:FindFirstChild("SeedType")
        if not v then return nil end
        if v:IsA("StringValue") then
            return v.Value, v.Value
        end
        if v:IsA("NumberValue") or v:IsA("IntValue") then
            return seedNameOf[v.Value], tostring(v.Value)
        end
        if v:IsA("ObjectValue") then
            local s = v.Value and v.Value.Name or nil
            return s, s or "?"
        end
        return nil, v.ClassName
    end

    -- The crate for the picked seed: ONE walk of the world for anything that
    -- carries the game's own SeedType tag, plus anything named like a crate as
    -- a fallback (a box whose tag can't be read). Someone else's crate is
    -- never taken. Prefers a SEED-TAG match over a label match, then the
    -- nearest. Returns the hit plus every candidate, so a miss logs the shelf.
    local function findSeedCrate(seedName)
        local want = (tostring(seedName):lower():gsub("%s+", ""))
        local root = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local tagged, models = {}, {}
        local walked = 0
        -- the walk below can take a while on a streamed-in town and prints
        -- nothing until it is done — say we started, so a slow shop trip
        -- can't look like the script stopping
        log("seed crate: searching the town for a " .. tostring(seedName) .. " crate…")
        for _, d in ipairs(workspace:GetDescendants()) do
            walked += 1
            if d.Name == "SeedType" then
                local m = d.Parent and d.Parent.Parent
                if m and m:IsA("Model") then tagged[m] = true end
            elseif d:IsA("Model") and d ~= LocalPlayer.Character then
                local n = d.Name:lower()
                if n:find("seedbox", 1, true) or n:find("crate", 1, true) then
                    models[d] = true
                end
            end
        end
        for m in pairs(tagged) do models[m] = true end
        -- ▸ DIAGNOSTIC (user: "it isnt going to the crate"): the walk itself
        --   says what it saw, so a streamed-out shelf or an unreadable tag is
        --   visible in the console instead of guessed at.
        local nTag, nMod = 0, 0
        for _ in pairs(tagged) do nTag += 1 end
        for _ in pairs(models) do nMod += 1 end
        log(string.format("seed crate: walked %d workspace instance(s) — %d crate-like model(s), %d with a seed tag",
            walked, nMod, nTag))
        local cands, seedHit, labelHit = {}, nil, nil
        for m in pairs(models) do
            local p = m:FindFirstChildWhichIsA("BasePart", true)
            if p then
                local seed, raw = crateSeedType(m)
                local owner = crateOwner(m)
                local c = {
                    m = m, pos = p.Position, label = crateLabel(m), owner = owner,
                    seed = seed, raw = raw,
                    other = owner ~= nil and owner ~= LocalPlayer.Name,
                    d = root and (p.Position - root.Position).Magnitude or 0,
                }
                cands[#cands + 1] = c
                if not c.other then
                    local s = seed and (seed:lower():gsub("%s+", ""))
                    if s and (s == want or s:find(want, 1, true)) then
                        if not seedHit or c.d < seedHit.d then seedHit = c end
                    else
                        local t = (c.label:lower():gsub("%s+", ""))
                        if t ~= "" and t:find(want, 1, true) then
                            if not labelHit or c.d < labelHit.d then labelHit = c end
                        end
                    end
                end
            end
        end
        return seedHit or labelHit, cands
    end

    local function buySeedAndFill(seedName)
        if not seedName then
            log("seed shop: nothing is picked in the Farm tab's Seed dropdown — nothing bought")
            return false
        end
        local root = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then log("seed shop: no character") return false end
        local pos, where = findSeedShop()
        if not pos then
            log("seed shop: FarmCo not found (Markers.GotoLocations / Stores.NPCs) — stand in town once, then run the loop again")
            return false
        end
        log(string.format("seed shop: FarmCo at %s (%.0f studs) — tp'ing there for %s",
            where, (root.Position - pos).Magnitude, seedName))
        tpChar(pos)
        task.wait(1.5) -- let the shop stream in
        if stopping() then return false end
        -- where the counter is (the owner NPC — the crate gets put down here)
        local stores = workspace:FindFirstChild("Stores")
        local npcs = stores and stores:FindFirstChild("NPCs")
        local owner
        if npcs then
            for _, m in ipairs(npcs:GetChildren()) do
                if m.Name:lower():find("farmco", 1, true) then owner = m break end
            end
        end
        local oPart = owner and owner:FindFirstChildWhichIsA("BasePart", true)
        -- ▸ STAGE 1 — THE CRATE (user's flow: "tp to crate"): the crates for
        --   sale are locked draggables on the shelf, and the right one names
        --   the picked seed on its own label.
        log("seed crate: the picked seed is '" .. tostring(seedName) .. "'")
        local hit, cands = findSeedCrate(seedName)
        log(string.format("seed crate: %d candidate(s) in the world — %s",
            #cands, hit and string.format("taking %s (seed tag '%s', label '%s') at (%.0f, %.0f, %.0f), %.0f studs away",
                hit.m.Name, hit.seed or "unreadable", hit.label,
                hit.pos.X, hit.pos.Y, hit.pos.Z, hit.d)
                or "none matches the picked seed"))
        if not hit then
            table.sort(cands, function(a, b) return a.d < b.d end)
            for i = 1, math.min(#cands, 8) do
                local c = cands[i]
                log(string.format("  crate %.0f studs away: %s — seed '%s', label '%s' at (%.0f, %.0f, %.0f)%s",
                    c.d, c.m.Name, c.seed or "unreadable",
                    c.label ~= "" and c.label or "(no label)",
                    c.pos.X, c.pos.Y, c.pos.Z,
                    c.owner and (" owner " .. c.owner) or ""))
            end
            -- what the shelf actually sells, grouped — one line that names the
            -- seeds you CAN buy here instead of only saying "no match"
            local shelf = {}
            for _, c in ipairs(cands) do
                local k = c.seed or "(no seed tag)"
                shelf[k] = (shelf[k] or 0) + 1
            end
            local parts = {}
            for k, n in pairs(shelf) do parts[#parts + 1] = k .. " ×" .. n end
            table.sort(parts)
            log("seed crate: the shelf has: "
                .. (#parts > 0 and table.concat(parts, ", ") or "nothing at all"))
            log("seed crate: nothing sells '" .. seedName
                .. "' here — pick one of those in the Farm tab's Seed dropdown")
            return false
        end
        -- what it costs (the crate's own price billboard) and whether we can
        -- pay — cheaper than discovering it at the till
        local price
        local cb = hit.m:FindFirstChild("CostBillboard", true)
        local pl = cb and cb:FindFirstChild("TextLabel", true)
        if pl and pl:IsA("TextLabel") then
            price = tonumber((tostring(pl.Text):gsub("[^%d]", "")))
        end
        local balNow = coinBalance()
        log(string.format("seed crate: the %s crate (%s) costs %s — balance %s",
            seedName, hit.m.Name,
            price and (price .. " coins") or "an unreadable price",
            tostring(balNow)))
        if price and balNow and price > balNow then
            log("seed crate: that is more than the balance — not buying it (pick a cheaper seed or sell something first)")
            return false
        end
        tpChar(hit.pos)
        task.wait(1.0)
        if stopping() then return false end
        local acts = contextActions()
        log("seed crate: E at the crate to pick it up — the game offers: "
            .. (acts and (#acts > 0 and table.concat(acts, " · ") or "nothing") or "unreadable"))
        if not carryCrate("seed crate") then
            log("seed crate: couldn't pick it up after 3 tries — stopping the shop trip here (nothing bought)")
            return false
        end
        -- ▸ STAGE 2 — PUT IT ON THE COUNTER (user: "place crate on counter"):
        --   tp to the owner; if the crate rides along, the carry took
        if oPart then
            tpChar(oPart.Position)
            task.wait(1.2)
            if stopping() then return false end
            root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or root
            local cPart = hit.m:FindFirstChildWhichIsA("BasePart", true)
            local cD = cPart and (cPart.Position - root.Position).Magnitude or -1
            log(string.format("seed crate: at the %s — the crate is %.0f studs away (%s)",
                owner.Name, cD,
                cD >= 0 and (cD < 15 and "it came with us" or "it did NOT follow the tp")))
            log("seed crate: X to put it down here")
            pressKey(Enum.KeyCode.X)
            task.wait(1.0)
            if stopping() then return false end
        else
            log("seed shop: the FarmCo Owner NPC isn't in the workspace yet — pressing F anyway")
        end
        -- open the owner's menu
        local before = coinBalance()
        log("seed shop: F at the owner (InteractWithNPC) — balance "
            .. (before and (before .. " coins") or "unreadable"))
        pressKey(Enum.KeyCode.F)
        task.wait(1.2)
        if stopping() then return false end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local views = pg and pg:FindFirstChild("GuiViews")
        if not views then log("seed shop: PlayerGui.GuiViews missing") return false end
        local function isShown(o) -- Visible all the way up to GuiViews
            local p = o
            while p and p ~= views do
                if p:IsA("GuiObject") and not p.Visible then return false end
                p = p.Parent
            end
            return true
        end
        -- the row for the picked seed: a button named by text, else a label
        local want = (seedName:lower():gsub("%s+", ""))
        local row
        for _, g in ipairs(views:GetDescendants()) do
            if g:IsA("TextButton") and isShown(g) then
                local t = (guiTextOf(g):lower():gsub("%s+", ""))
                if t == want or t:find(want, 1, true) then row = g break end
            end
        end
        if not row then
            for _, g in ipairs(views:GetDescendants()) do
                if g:IsA("TextLabel") and isShown(g) then
                    local t = (tostring(g.Text or ""):lower():gsub("%s+", ""))
                    if t ~= "" and (t == want or t:find(want, 1, true)) then row = g break end
                end
            end
        end
        local target
        if not row then
            -- no menu row: the owner may simply charge for the crate that's
            -- sitting on the counter (user's flow: "talk the the guy"). Never
            -- stop here — the balance check below is the judge.
            local seen = {}
            for _, g in ipairs(views:GetDescendants()) do
                if g:IsA("TextButton") and isShown(g) then
                    local t = guiTextOf(g)
                    if t and t ~= "" then seen[#seen + 1] = t end
                    if #seen >= 25 then break end
                end
            end
            log("seed shop: no seed row in the menu — the owner may charge for the crate directly; the visible buttons were: "
                .. (#seen > 0 and table.concat(seen, " · ") or "none (no menu opened)"))
        end
        -- the Buy button: its own row first, then up to 5 ancestors up
        local node = row
        if node then
            for _ = 1, 6 do
                for _, d in ipairs(node:GetDescendants()) do
                    if d:IsA("GuiButton") and isShown(d) then
                        local t = (guiTextOf(d) .. " " .. d.Name):lower()
                        if t:find("buy", 1, true) or t:find("purchase", 1, true) then
                            target = d
                            break
                        end
                    end
                end
                if target or node == views then break end
                node = node.Parent
            end
            target = target or (row:IsA("GuiButton") and row or nil)
            if target then
                log(string.format("seed shop: clicking %s ('%s') for %s",
                    target:GetFullName(), guiTextOf(target), seedName))
                local handled = invokeHandlers(target)
                if not handled then
                    log("seed shop: no readable handler on that button (getconnections) — trying :Activate()")
                    pcall(function() target:Activate() end)
                end
            else
                log("seed shop: the '" .. seedName .. "' row has no Buy button in it — nothing clicked in the menu")
            end
        end
        -- verify: the balance drops, or a box of that seed appears next to us
        local after, box
        for _ = 1, 12 do -- ~6 s
            if stopping() then break end
            after = coinBalance()
            if before and after and after < before then break end
            task.wait(0.5)
        end
        local bought = (before and after and after < before) or false
        local objects = workspace:FindFirstChild("Objects")
        local dobjs = objects and objects:FindFirstChild("DraggableObjects")
        if dobjs then
            for _, m in ipairs(dobjs:GetChildren()) do
                local p = m:FindFirstChildWhichIsA("BasePart", true)
                if p and (p.Position - root.Position).Magnitude < 80 then
                    local s2 = crateSeedType(m)
                    if s2 and s2:lower() == seedName:lower() then
                        box = string.format("%s box %.0f studs away", seedName,
                            (p.Position - root.Position).Magnitude)
                        break
                    end
                end
            end
        end
        log(string.format("seed shop: balance %s → %s%s",
            tostring(before), tostring(after),
            box and (" · " .. box) or ""))
        -- close the menu (its own close button if it has one, else F)
        local closed = false
        for _, g in ipairs(views:GetDescendants()) do
            if g:IsA("TextButton") and isShown(g) then
                local t = (guiTextOf(g) .. " " .. g.Name):lower()
                if t:find("close", 1, true) or t:find("exit", 1, true) then
                    invokeHandlers(g)
                    closed = true
                    break
                end
            end
        end
        if not closed then pressKey(Enum.KeyCode.F) end
        task.wait(0.6)
        if not bought then
            log("⚠ the " .. seedName .. " purchase could NOT be confirmed (the balance didn't move) — check the shop by hand")
            return false
        end
        log("✅ " .. seedName .. " bought (balance " .. tostring(before) .. " → " .. tostring(after) .. ")")
        -- ▸ STAGE 3 — PICK IT BACK UP (user: "pick it back up")
        log("seed crate: picking the bought crate back up")
        if not carryCrate("bought crate") then
            log("seed crate: the bought crate stayed on the counter — pick it up by hand (E) and the seeder fill is next time")
            return true
        end
        local cPart = hit.m:FindFirstChildWhichIsA("BasePart", true)
        -- ▸ STAGE 4 — GO TO THE SEEDER (user: "go to seeder") and fill it:
        --   V = FillSeeder, the same proximity-context rule as the crate
        local seeder = findImplement("Planter", root.Position, nil)
        if not seeder then
            log("seeder fill: no seeder (KADL) found — the " .. seedName .. " crate is with you; fill the seeder by hand (V)")
            return true
        end
        if seeder:GetAttribute("InStorage") then
            log("seeder fill: the seeder is IN STORAGE — respawn it, then fill it by hand (V); the crate is with you")
            return true
        end
        tpChar(seeder:GetPivot().Position)
        task.wait(1.2)
        if stopping() then return false end
        root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or root
        local cD = cPart and cPart.Parent and (cPart.Position - root.Position).Magnitude or -1
        log(string.format("seeder fill: at the %s — the crate is %.0f studs away (%s)",
            seeder.Name, cD, cD >= 0 and (cD < 15 and "it came with us" or "it did NOT follow") or "gone"))
        local n0 = seederSeedState(seeder)
        log("seeder fill: V (FillSeeder) — the seeder had " .. tostring(n0) .. " seeds")
        pressKey(Enum.KeyCode.V)
        task.wait(1.0)
        if stopping() then return false end
        local n1, cap1, kind1
        for _ = 1, 8 do -- ~4 s
            if stopping() then break end
            n1, cap1, kind1 = seederSeedState(seeder)
            if n1 and n0 and n1 > n0 then break end
            task.wait(0.5)
        end
        if n1 and n0 and n1 > n0 then
            log(string.format("✅ seeder now holds %d%s seeds%s — run the loop again (or turn it back on) to seed the fields",
                n1, cap1 and ("/" .. cap1) or "", kind1 and (" (" .. kind1 .. ")") or ""))
            return true
        end
        log("⚠ the fill could NOT be confirmed (the seeder still reads " .. tostring(n1) .. ") — the crate is with you; fill it by hand (V)")
        return true
    end

    -- ▸ SEEDER STEP 1 — the seed check (user: "first thing from the seeder:
    --   we need to know if it has seeds in it or not. if it does stay in
    --   tractor. if it does not get out of the tractor"). Runs at the start
    --   of a run (a read-only report), on the idle path, and in the
    --   PLANTING stage. Returns true=FULL (the caller then hitches the
    --   seeder — step 2); false=empty/unreadable.
    --   `allowBuy` is the ONLY thing that lets this function spend coins:
    --   the planting stage passes true, everything else leaves it off.
    --   Without it the empty case is reported and that is all — no F press,
    --   no teleport (user: "why does when i start it, it just teleports to
    --   the store even when it's not time to buy seeds … it should only buy
    --   seeds when it is at the planting loop"). At most ONE shop trip per
    --   run (seedShopTried). F = ExitEquipment (context-key dump), pressed
    --   ONLY while seated.
    local function seedCheck(tr, hum, allowBuy)
        if stopping() then return false end
        log("— seed check —")
        local seated = hum.SeatPart ~= nil
        local seeder, _, basis =
            findImplement("Planter", tr:GetPivot().Position, tr)
        local count, cap, kind
        if seeder then count, cap, kind = seederSeedState(seeder) end
        -- the state lines must not promise a dismount this call won't do
        local exitIntent = allowBuy
            and (seated and "getting out of the tractor"
                or "already out of the tractor")
            or "no action — this isn't the planting stage"
        if seeder and count then
            local label = string.format("%d%s seeds%s%s", count,
                cap and ("/" .. cap) or "",
                kind and kind ~= "" and (" (" .. kind .. ")") or "",
                seeder:GetAttribute("InStorage") and ", in storage" or "")
            if count > 0 then
                log("seeder has " .. label .. " — going to hitch it")
                return true
            end
            log("seeder is EMPTY: " .. label .. " — " .. exitIntent)
        elseif not seeder then
            log("no seeder (Planter/KADL) found — seed state unknown — " ..
                exitIntent)
        else
            log("seed state unreadable (" .. tostring(basis) ..
                ") — treating as empty — " .. exitIntent)
        end
        -- ▸ READ-ONLY OUTSIDE THE PLANTING STAGE. No dismount (F there would
        --   kick the driver out of the tractor for nothing) and no shop trip.
        if not allowBuy then return false end
        if seated then
            pressKey(Enum.KeyCode.F)
            task.wait(0.8)
            if stopping() then return false end
            if hum.SeatPart then
                pressKey(Enum.KeyCode.F) -- context can take a beat
                task.wait(0.8)
                if stopping() then return false end
            end
            log(hum.SeatPart and "⚠ F didn't exit — press F manually"
                or "✅ out of the tractor")
        end
        -- ▸ EMPTY SEEDER → GO SHOPPING (user: "if the seeder is empty at it's
        --   run, we need it to tp to the shop and buy the spesific seed").
        --   Only when a field still needs seed (never spend coins for nothing)
        --   and only on foot — the shop is walked into.
        if hum.SeatPart then return false end
        local needCells = seedNeedLeft(tr:GetPivot().Position)
        if not seedChoice then
            log("the seeder is empty and nothing is picked in the Farm tab's Seed dropdown — pick a seed and the loop can buy it")
            return false
        end
        if seedShopTried then
            log("the seeder is still empty and the shop was already tried this run — not teleporting again (pick a different seed, or fill it by hand)")
            return false
        end
        seedShopTried = true
        -- ▸ Only reachable with allowBuy (the PLANT stage), and the caller
        --   only passes it when Cultivated cells are actually waiting — an
        --   EMPTY seeder + a picked seed + real planting to do = buy it.
        --   The old start-of-run call is now report-only (user: "it should
        --   only buy seeds when it is at the planting loop").
        log(string.format("the seeder is empty — going to buy %s (%d cell(s) need seed right now)",
            seedChoice, needCells))
        -- the fill at the shop only works on a seeder that is OUT in the
        -- world — bring it back from storage first. If that fails, do NOT
        -- buy: the crate would land on the counter with nothing to pour it
        -- into.
        local seederOut = ensureToolNearby(tr, "Planter", "seeder")
        if stopping() then return false end
        if not seederOut then
            log("the seeder couldn't be brought out of storage — not buying a crate it can't be poured into")
            return false
        end
        buySeedAndFill(seedChoice)
        if stopping() then return false end
        -- ▸ GET BACK IN AND SEED (user's step list ends with it: "get back in
        --   and seed"). The shop trip leaves the character on foot next to
        --   the seeder; walk back, sit down, and the check-back re-enters the
        --   planting stage in THIS run now that the seeder is full.
        local char2 = LocalPlayer.Character
        local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
        if hum2 and tr.Parent
            and not (hum2.SeatPart and hum2.SeatPart:IsDescendantOf(tr)) then
            local seat2 = tr:FindFirstChildWhichIsA("VehicleSeat", true)
                or tr:FindFirstChildWhichIsA("Seat", true)
            if seat2 then
                local root2 = char2:FindFirstChild("HumanoidRootPart")
                local d2 = root2 and (seat2.Position - root2.Position).Magnitude or 0
                if mountTractor(char2, hum2, tr, seat2, d2, "tractor") then
                    log("✅ back in the tractor — the planting stage runs next")
                else
                    log("⚠ couldn't get back into the tractor — get in by hand and the next run seeds")
                end
            else
                log("⚠ the tractor has no seat any more — get in by hand and the next run seeds")
            end
        end
        return false
    end

    -- ▸ SEEDER STEP 2 (user: "ok, now if the seeder is full make the
    --   tractor go hitch to the seeder"): the seed check said FULL → the
    --   tractor goes and hitches the KADL with the SAME proven sequence
    --   every pass uses (hitchTool — it also tug-verifies an ALREADY
    --   hitched seeder and Xes a different tool off first). The seeder
    --   STAYS hitched when done — that's the point (the seeding pass is
    --   a later step, asked for one at a time). No fill, no drive.
    local function seedHitchStep(tr)
        if stopping() then return end
        -- safety for every tool (same rule as the tractor gate): the
        -- seeder in storage or far away gets respawned via the Equipment
        -- Manager, then the fresh model is hitched
        local seeder, sdist, basis = ensureToolNearby(tr, "Planter", "seeder")
        if not seeder then return end
        log(string.format("hitching the seeder: %s (%.0f studs, by %s)",
            seeder.Name, sdist or 0, basis or "?"))
        if hitchTool(tr, seeder) then
            log("✅ seeder hitched — staying hitched")
        end
    end

    -- "actual driving": HOLD REAL KEYS (WASD via VirtualInputManager) while
    -- seated — the game's own vehicle controller reads them through its
    -- normal input pipeline, so the tractor accelerates and swings through
    -- turns with true physics. (Setting seat.Throttle directly was PROVEN
    -- ignored: the seat's control script overwrites those properties from
    -- player input every frame.)
    -- MAP-FOLLOWING driver (user's plan): the path is a precomputed snake
    -- of straight legs — the script just follows it. Per leg: PURE
    -- PURSUIT — aim at a point on the leg's LINE ~12 studs ahead of the
    -- tractor; steer proportional to the heading error vs that aim (full
    -- turn past ~17°, feather past ~6°), creep while correcting, cruise
    -- when straight. Any lateral offset tilts the aim back toward the
    -- line, so the tractor always CONVERGES onto it and then runs it dead
    -- straight. (v7 nudge-only correction settled into a PARALLEL OFFSET
    -- beside the line — user: "it just follows the line instead of going
    -- back on the line"; the old heading-align mode steered back to the
    -- parallel heading and undid every nudge.)
    -- (v3 orbited goals; v4 reverse-assist jackknifed the plow — both gone.)
    -- Returns true=leg done, false=keys didn't drive (caller falls back to
    -- the glide), nil=killed.
    local KEY_W, KEY_A, KEY_D, KEY_S =
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.S
    local keyHeld = {}
    local function setKey(key, down)
        if keyHeld[key] == down then return end
        keyHeld[key] = down
        VIM:SendKeyEvent(down, key, false, game)
    end
    local function releaseDriveKeys()
        setKey(KEY_W, false) setKey(KEY_A, false)
        setKey(KEY_D, false) setKey(KEY_S, false)
    end

    -- ▸ REVERSE — ONLY where a turn is too sharp to take going forward
    --   (user: "allow it to reverse? but only when needed on turns and
    --   sharp turns"): back up while steering the nose around. Reversing
    --   MIRRORS the steering response (parallel-parking logic: steer
    --   right while backing = the NOSE swings left), so the error is
    --   flipped vs the forward pursuit. Closed-loop on the heading error
    --   — stops the moment the forward pursuit can take over (~55°), at
    --   ~1.2 s, or on shutdown, with an honest log if it couldn't clear
    --   it (blocked behind). Nothing else reverses: gentle corrections,
    --   glides, arcs and the hitch line-ups stay forward/pivot.
    local SHARP_TURN_DEG = 100 -- a leg-start heading jump bigger than this earns a reverse
    local function reverseTurn(tr, seat, aimPos)
        setKey(KEY_W, false)
        setKey(KEY_S, true)
        local cleared = false
        for _ = 1, 20 do -- ~1.2 s cap at 0.06 s ticks
            if stopping() then break end
            local p = tr:GetPivot().Position
            local look = seat.CFrame.LookVector
            local nose = Vector3.new(look.X, 0, look.Z)
            local want = Vector3.new(aimPos.X - p.X, 0, aimPos.Z - p.Z)
            if nose.Magnitude < 0.1 or want.Magnitude < 0.5 then break end
            nose, want = nose.Unit, want.Unit
            local ang = math.deg(math.acos(math.clamp(nose:Dot(want), -1, 1)))
            if ang < 55 then cleared = true break end
            local wperp = Vector3.new(-want.Z, 0, want.X) -- right of the aim
            local err = nose:Dot(wperp) -- >0 = nose right of aim → nose must swing LEFT
            if err > 0.1 then
                setKey(KEY_D, true) setKey(KEY_A, false) -- backed-up LEFT = steer right
            elseif err < -0.1 then
                setKey(KEY_A, true) setKey(KEY_D, false) -- backed-up RIGHT = steer left
            else
                setKey(KEY_A, false) setKey(KEY_D, false)
            end
            task.wait(0.06)
        end
        releaseDriveKeys()
        if not cleared and not stopping() then
            log("reverse didn't clear the turn (space behind blocked?) — continuing forward")
        end
        task.wait(0.15) -- settle before the forward pursuit re-engages
    end

    driveLegKeys = function(tr, seat, fromPt, toPt, tol)
        if not seat then return false end -- not seated: keys would do nothing
        tol = tol or 5
        local A = Vector3.new(fromPt.X, 0, fromPt.Z)
        local B = Vector3.new(toPt.X, 0, toPt.Z)
        local dir = B - A
        local legLen = dir.Magnitude
        if legLen < 0.5 then return true end
        dir = dir / legLen
        local perp = Vector3.new(-dir.Z, 0, dir.X) -- right of the leg line
        -- ▸ SHARP-TURN REVERSE (only when needed): a leg whose line
        --   points >SHARP_TURN_DEG away from where the tractor's nose
        --   faces earns a backed-up swing first — everything else
        --   (90° lap corners, gentle corrections) drives forward exactly
        --   as before. startPos is captured AFTER it so the keys-didn't-
        --   drive probe measures only the forward pursuit.
        local look0 = seat.CFrame.LookVector
        local nose0 = Vector3.new(look0.X, 0, look0.Z)
        if nose0.Magnitude > 0.1 then
            nose0 = nose0.Unit
            local ang0 = math.deg(math.acos(math.clamp(nose0:Dot(dir), -1, 1)))
            if ang0 > SHARP_TURN_DEG then
                log(string.format("sharp turn (%d°) — reversing to swing the nose around",
                    math.floor(ang0 + 0.5)))
                reverseTurn(tr, seat, A + dir * math.min(12, legLen))
            end
        end
        local startPos = tr:GetPivot().Position
        local prevPos, fwd = startPos, nil
        for tick = 1, 350 do -- ~42 s cap per leg (0.12 s ticks)
            if stopping() then releaseDriveKeys() return nil end
            local pos = tr:GetPivot().Position
            local rel = Vector3.new(pos.X, 0, pos.Z) - A
            local along, cross = rel:Dot(dir), rel:Dot(perp)
            if along >= legLen - tol and math.abs(cross) <= 14 then break end
            -- low-pass travel direction (jitter can't flip the alignment)
            local move = Vector3.new(pos.X - prevPos.X, 0, pos.Z - prevPos.Z)
            if move.Magnitude > 0.5 then
                local m = move.Unit
                fwd = fwd and (fwd * 0.7 + m * 0.3).Unit or m
            end
            prevPos = pos
            if not fwd then
                local look = seat.CFrame.LookVector
                fwd = Vector3.new(look.X, 0, look.Z)
                fwd = fwd.Magnitude > 0.1 and fwd.Unit or dir
            end
            -- PURE PURSUIT: aim at a point ON the line ~12 studs ahead.
            -- Offset sideways → the aim tilts back toward the line and the
            -- tractor converges onto it; straight on the line → the aim
            -- straightens out (no weaving).
            local aim = A + dir * math.min(along + 12, legLen)
            local want = Vector3.new(aim.X - pos.X, 0, aim.Z - pos.Z)
            if want.Magnitude < 0.5 then break end
            want = want.Unit
            local wperp = Vector3.new(-want.Z, 0, want.X)
            local err = fwd:Dot(wperp) -- >0 = nose right of the aim → steer LEFT
            local slot = tick % 3
            if err > 0.3 then
                setKey(KEY_A, true) setKey(KEY_D, false)     -- hard left
            elseif err < -0.3 then
                setKey(KEY_D, true) setKey(KEY_A, false)     -- hard right
            elseif err > 0.1 then
                setKey(KEY_A, slot < 2) setKey(KEY_D, false) -- feather left
            elseif err < -0.1 then
                setKey(KEY_D, slot < 2) setKey(KEY_A, false) -- feather right
            else
                setKey(KEY_A, false) setKey(KEY_D, false)    -- dead straight
            end
            local tDuty = math.abs(err) > 0.3 and 1 or 2 -- creep while correcting
            -- ▸ ease off into the END of the leg: over the last 15% of it the
            --   throttle drops to the creep duty, so the corner is taken at
            --   low speed instead of carrying full speed into the turn.
            --   Proportional to the leg, so the short A*-route legs (a few
            --   studs) are effectively untouched and only the long field
            --   laps slow down.
            if legLen - along < legLen * 0.15 then tDuty = 1 end
            setKey(KEY_W, slot < tDuty)
            task.wait(0.12)
            if tick == 15 then -- ~1.8 s probe: keys must produce motion
                local moved = (Vector3.new(pos.X, 0, pos.Z)
                    - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
                if moved < 1 and legLen > tol + 4 then
                    releaseDriveKeys()
                    return false
                end
            elseif tick == 125 and math.abs(cross) <= 16 then -- ~15 s: close
                if along < legLen - 10 then
                    log(string.format("leg ~%.0f studs short — accepting (plow overlap covers it)",
                        legLen - along))
                end
                break
            end
        end
        releaseDriveKeys()
        return true -- arrived, accepted close-enough, or hit the time cap
    end

    -- ▸ PLOW THE FIELD (dump §26: the field is ONE 50×100 plate of 50
    --   VIRTUAL cells, 10×10 studs each — the game's OWN client detects the
    --   implement passing over a cell and fires the plow action, so driving
    --   over every cell IS plowing: 3 cells came back Stage="Plowed" in a
    --   neat line after drive passes). Serpentine sweep: drive along the
    --   SHORT axis, step 10 studs along the LONG one, alternating ends each
    --   row. Overshoot both ends slightly so the TRAILING plow still
    --   covers the edge cells.
    -- ── visual debug: glowing bars ON the field along every leg of the
    -- snake (anchored 3D parts in workspace — always visible in every
    -- executor; the 2D Drawing-API lines didn't show up in Delta).
    -- thin green = all legs, thick bright yellow = the leg being driven.
    local dbgParts = {}
    local function dbgShow(tr, map, at)
        pcall(function()
            local drawY = tr:GetPivot().Position.Y + 0.6 -- hover over soil
            local pts = { at }
            for _, leg in ipairs(map) do pts[#pts + 1] = leg[1] end
            for i = 1, #pts - 1 do
                local a = Vector3.new(pts[i].X, drawY, pts[i].Z)
                local b = Vector3.new(pts[i + 1].X, drawY, pts[i + 1].Z)
                local len = (b - a).Magnitude
                if len < 0.5 then continue end
                local bar = Instance.new("Part")
                bar.Anchored = true
                bar.CanCollide = false bar.CanQuery = false bar.CanTouch = false
                bar.CastShadow = false
                bar.Material = Enum.Material.Neon
                bar.Size = Vector3.new(0.35, 0.1, len)
                bar.CFrame = CFrame.lookAt((a + b) / 2, b)
                bar.Color = Color3.fromRGB(90, 220, 120)
                bar.Transparency = 0.45
                bar.Parent = workspace
                dbgParts[i] = bar
            end
        end)
    end
    local function dbgLeg(i)
        for j, bar in ipairs(dbgParts) do
            if j == i then
                bar.Color = Color3.fromRGB(255, 220, 60)
                bar.Transparency = 0
            else
                bar.Color = Color3.fromRGB(90, 220, 120)
                bar.Transparency = 0.45
            end
        end
    end
    local function dbgClear()
        for _, bar in ipairs(dbgParts) do pcall(function() bar:Destroy() end) end
        table.clear(dbgParts)
    end

    -- ▸ SELL WHEN FULL (user: "when the harvester is full it will go to
    --   (position showed in dump) … it does not need to pour the contents it
    --   just needs to sell and go back to the loop"). The load comes from the
    --   game's OWN Configurations on the harvester (Capacity / MaxCapacity —
    --   the same pattern the seeder and the trailer use; never a HUD label),
    --   and the sale is the game's OWN drive-on pad: nothing is called by
    --   hand. Park the full harvester, wait for the game to sell, VERIFY with
    --   Capacity + the coin balance, then drive back and carry on sweeping.
    local function harvesterLoad(ride)
        local ok, cur, max = pcall(function()
            local conf = ride:FindFirstChild("Configurations")
            if not conf then return nil end
            local c = conf:FindFirstChild("Capacity")
            if not (c and c:IsA("IntValue")) then return nil end
            local m = conf:FindFirstChild("MaxCapacity")
            return c.Value, (m and m:IsA("IntValue")) and m.Value or nil
        end)
        if not ok then return nil end
        return cur, max
    end

    -- the sell pads, found live and never hardcoded (same rule as the shop):
    -- the GameplayVisuals.SellArea pad first, then the store DropOff parts.
    -- Every candidate is logged, so the first run names the real one.
    local function findSellSpots()
        local out = {}
        local function add(p, what)
            if not p then return end
            for _, q in ipairs(out) do
                if (q.p - p).Magnitude < 12 then return end
            end
            out[#out + 1] = { p = p, what = what }
        end
        pcall(function()
            local gv = workspace:FindFirstChild("GameplayVisuals")
            local sa = gv and gv:FindFirstChild("SellArea")
            if not sa then return end
            local best, area
            for _, d in ipairs(sa:GetDescendants()) do
                if d:IsA("BasePart") then
                    local a = d.Size.X * d.Size.Z
                    if not area or a > area then best, area = d, a end
                end
            end
            if best then add(best.Position, "SellArea." .. best.Name) end
        end)
        pcall(function()
            local stores = workspace:FindFirstChild("Stores")
            local dr = stores and stores:FindFirstChild("DropOffs")
            if not dr then return end
            local ps = {}
            for _, d in ipairs(dr:GetChildren()) do
                if d:IsA("BasePart") then ps[#ps + 1] = d end
            end
            -- biggest first: the drive-on pads are the big ones
            table.sort(ps, function(a, b) return a.Size.X * a.Size.Z > b.Size.X * b.Size.Z end)
            for i = 1, math.min(#ps, 2) do
                add(ps[i].Position, "DropOffs." .. ps[i].Name)
            end
        end)
        return out
    end

    -- park and wait for the game to sell: true once the load drops
    local function trySellAt(ride, what)
        local cap0 = harvesterLoad(ride)
        local coins0 = coinBalance()
        local deadline = os.clock() + 8
        while os.clock() < deadline do
            if stopping() then return false end
            local cur = harvesterLoad(ride)
            if cur and cap0 and cur < cap0 then
                log(string.format("sold at %s — load %d → %d, coins %s → %s",
                    what, cap0, cur, tostring(coins0), tostring(coinBalance())))
                return true
            end
            task.wait(0.4)
        end
        log(string.format("no sale at %s after 8 s (load %s, coins %s → %s) — next pad",
            what, tostring(cap0), tostring(coins0), tostring(coinBalance())))
        return false
    end

    -- the whole trip: drive to a pad, sell, drive back to the field
    local function sellHarvester(ride, seat, field)
        local cur, max = harvesterLoad(ride)
        if not cur then
            log("harvester load unreadable — sell trip skipped")
            return false
        end
        log(string.format("harvester FULL (%d/%s) — going to sell", cur, tostring(max)))
        local spots = findSellSpots()
        if #spots == 0 then
            log("⚠ no sell pad found (GameplayVisuals.SellArea / Stores.DropOffs) — sell skipped")
            return false
        end
        for i, s in ipairs(spots) do
            if stopping() then return false end
            log(string.format("sell point %d/%d: %s at (%.0f, %.0f)", i, #spots,
                s.what, s.p.X, s.p.Z))
            local ok, why = driveRoute(ride, seat, s.p, ride)
            if not ok then
                log("couldn't reach " .. s.what .. " (" .. tostring(why) .. ")")
            elseif trySellAt(ride, s.what) then
                if field and field.Parent then
                    log("back to " .. field.Name .. " to finish the harvest")
                    driveToField(ride, field, seat, ride)
                end
                return true
            end
        end
        log("⚠ still full — none of the pads sold the load")
        return false
    end

    local function sweepField(tr, field, seat, job)
        local baseCF, baseSize = fieldFrame(field)
        if not baseCF then return false, "no bounds" end
        local c = baseCF.Position
        local rx = Vector3.new(baseCF.RightVector.X, 0, baseCF.RightVector.Z).Unit
        local rz = Vector3.new(baseCF.LookVector.X, 0, baseCF.LookVector.Z).Unit
        local alongX = baseSize.X >= baseSize.Z
        -- passes run along the LONG axis (user: fewer turns = more stable)
        local driveDir = alongX and rx or rz   -- unit world dir of the pass axis
        local stepDir  = alongX and rz or rx   -- unit world dir of the step
        -- +12 run-out past the field ends (user: turn too tight → doubled
        -- the old +6): the turns happen off the field in open grass, and
        -- the trailing plow still covers the edge cells
        local driveHalf = (alongX and baseSize.X or baseSize.Z) / 2 + 12
        local rowSpan   = (alongX and baseSize.Z or baseSize.X)
        -- THE SPIRAL (user's drawing): concentric rectangular laps from
        -- the OUTSIDE IN — each lap's long sides cover their step band
        -- over the whole length, each lap steps 10 studs inward, and the
        -- last ring (step inset to the center line) is one full pass down
        -- the middle. On a 5-wide field: laps at ±20, ±10, 0 = 3 rings.
        local rowHalf = rowSpan / 2 - 5 -- step half-extent of the outer lap (cell centers)
        local rings   = math.max(math.floor(rowHalf / 10) + 1, 1)
        local function pt(along, step) -- field-local (along, step) → world
            return c + driveDir * along + stepDir * step
        end
        local st0 = countStages(field)
        local need0 = st0 and whichNeed(job, st0) or nil
        log(string.format("%s: %d-ring spiral, outside-in  (%s)", job.verb, rings,
            st0 and string.format("%d/%d cells still need %s", need0, st0.total, job.prog)
                or "cell read unavailable"))
        local realDrive -- nil = not probed yet; true = seat driving; false = glide
        local sellTries = 0
        -- field driving starts on the ALIGN mover: binary WASD hunts across the
        -- line, the mover holds it. One fallback per sweep if it gets stuck.
        local useAlign = true
        local lineStats = { worst = 0, flips = 0 }
        local function doLeg(from, goal, tol)
            if stopping() then return nil end
            -- never accept more than half a leg early (the short step onto
            -- the next ring would get cut otherwise)
            tol = math.min(tol or 7, (goal - from).Magnitude * 0.5)
            if useAlign then
                local res = alignDriveLeg(tr, from, goal, tol, lineStats)
                if res == nil then return nil end
                if res then
                    task.wait(0.05)
                    return true
                end
                useAlign = false
                log("align mover couldn't finish a field leg — keys take over for this sweep")
            end
            if realDrive ~= false then
                local res = driveLegKeys(tr, seat, from, goal, tol)
                if res == nil then return nil end
                if realDrive == nil then
                    realDrive = res == true
                    if realDrive then
                        log("real driving ON (held WASD — true physics)")
                    else
                        log("keys didn't drive the tractor — falling back to glide")
                    end
                end
            end
            if realDrive == false then glideTractor(tr, goal) end
            task.wait(0.1)
            return true
        end
        -- precompute the whole spiral ONCE, then just FOLLOW the list
        local at = tr:GetPivot().Position
        local rel0 = at - c -- sides picked along the PLATE's axes, not world
        local E = rel0:Dot(driveDir) >= 0 and 1 or -1 -- which end I arrived at
        local S = rel0:Dot(stepDir) >= 0 and 1 or -1  -- which step side
        -- each full lap = side, far end, side, entry end (closed), then a
        -- short diagonal step inward onto the next lap; the final ring
        -- slides down the entry-end line and drives ONE center pass that
        -- reaches back to that end line (so the half-cell strip between
        -- the pass end and the end band is covered too — no gaps).
        local map = {}
        for k = 0, rings - 1 do
            local ax = driveHalf - 10 * k -- along half-extent of this lap
            local sx = rowHalf - 10 * k   -- step half-extent (20, 10, ...)
            -- tol 10 on the lap legs (user: the harvester swings wide at
            -- corners) = the end counts as reached 10 studs early, so the
            -- turn starts sooner and the arc stays inside the lap. The
            -- short step onto the next ring is capped back down by doLeg.
            if sx > 0 then -- full closed lap
                map[#map + 1] = { pt( E * ax,  S * sx), 10, nil }   -- side +
                map[#map + 1] = { pt(-E * ax,  S * sx), 10, nil }   -- far end
                map[#map + 1] = { pt(-E * ax, -S * sx), 10, nil }   -- side -
                map[#map + 1] = { pt( E * ax, -S * sx), 10, nil }   -- near end
                map[#map + 1] = { pt( E * ax,  S * sx), 10, k + 1 } -- lap closed
            else -- final ring: one center-line pass from the entry end
                map[#map + 1] = { pt( E * (ax + 10), 0), 10, nil }
                map[#map + 1] = { pt(-E * ax, 0), 10, rings }
            end
        end
        dbgShow(tr, map, at) -- glowing bars on the field; bright = active leg
        for i, leg in ipairs(map) do
            dbgLeg(i)
            -- full harvester: sell and come back (the user's loop). The spiral
            -- is already computed, so after the trip the sweep just resumes at
            -- THIS leg — from where the vehicle actually is now.
            if job.selfPropelled and sellTries < 2 then
                local cur, max = harvesterLoad(tr)
                if cur and max and max > 0 and cur >= max then
                    sellTries += 1
                    if sellHarvester(tr, seat, field) then at = tr:GetPivot().Position end
                end
            end
            if not doLeg(at, leg[1], leg[2]) then dbgClear() return nil end
            at = leg[1]
            if leg[3] then log(string.format("ring %d/%d done", leg[3], rings)) end
        end
        dbgClear()
        if stopping() then return nil end
        -- ▸ TOUCH-UP (user: "if it missed anything during the plow/
        --   cultivating make it go to that cube and then stop so nothing is
        --   missed"): every cube still at the job's stage gets a visit,
        --   nearest first — TRANSIT to one side, then THROUGH the cube on
        --   the plate's own axis so the trailing tool sweeps its full
        --   width (a diagonal crossing can miss the corners of a 10×10
        --   cell). Then stop and recount — verdict below stays honest.
        local missed = whichCells(job, field, baseCF, baseSize)
        if missed == nil then
            log("touch-up: cell read unavailable — can't locate missed cubes")
        elseif #missed > 0 then
            log(string.format("touch-up: %d cube(s) missed by the spiral — going to each", #missed))
            local function flat(p) return Vector3.new(p.X, 0, p.Z) end
            local route, pool, cur = {}, table.clone(missed), at
            while #pool > 0 do
                local bi, bd
                for i, p in ipairs(pool) do
                    local d = (flat(p) - flat(cur)).Magnitude
                    if not bd or d < bd then bi, bd = i, d end
                end
                local cube = table.remove(pool, bi)
                local c = Vector3.new(cube.X, cube.Y, cube.Z)
                -- enter from the side I'm on, exit out the far side (±15)
                local s = (flat(cur) - flat(c)):Dot(driveDir) >= 0 and 15 or -15
                route[#route + 1] = { goal = c + driveDir * s,     cx = cube.X, cz = cube.Z, kind = "transit" }
                route[#route + 1] = { goal = c + driveDir * (-s),  cx = cube.X, cz = cube.Z, kind = "through" }
                cur = c + driveDir * (-s)
            end
            local barMap = {}
            for i, r in ipairs(route) do barMap[i] = { r.goal, 6, nil } end
            dbgShow(tr, barMap, at)
            local through = 0
            for i, r in ipairs(route) do
                dbgLeg(i)
                if not doLeg(at, r.goal, 6) then dbgClear() return nil end
                at = r.goal
                if r.kind == "through" then
                    through += 1
                    log(string.format("touch-up %d/%d: drove through cube (%.0f, %.0f)",
                        through, #missed, r.cx, r.cz))
                end
                task.wait(0.15)
            end
            dbgClear()
            task.wait(1) -- let the server register the drive-overs before recounting
            if stopping() then return nil end
        end
        if lineStats.flips > 0 or lineStats.worst > 0 then
            log(string.format("field line: %d crossings, worst %.1f studs off%s",
                lineStats.flips, lineStats.worst, useAlign and "" or " (keys after the fallback)"))
        end
        local st1 = countStages(field)
        if st1 then
            local need1 = whichNeed(job, st1) or 0
            log(string.format("sweep done: %d/%d cells still need %s", need1, st1.total, job.prog))
            if st1.total > 0 and need1 == 0 then
                log("✅ the whole field is " .. job.past)
            elseif need0 and need1 >= need0 then
                log(string.format("cell count did NOT change — drive-over isn't %s (dump: %s would be next)",
                    job.prog, job.remote))
            else
                log("some cells left — run the loop again (tool may be narrower than one cell)")
            end
        else
            log("sweep done — cell read unavailable, check the field visually")
        end
        return true
    end

    -- ▸ WHEN IT'S DONE — PUT THE TOOLS AWAY (user: "it should despawn any
    --   unused tools when it's done (when i say despawn i mean store ok)"):
    --   the tools that are OUT in the world go back into the Equipment
    --   Manager's storage, through the SAME proven card + action path the
    --   respawn uses (no guessed remote, no mouse). Every store is VERIFIED
    --   (InStorage flips true) — a card whose Store is refused while the tool
    --   is out simply won't flip it, and that shows up in the log instead of
    --   being claimed as done.
    -- ▸ PUT ONE TOOL AWAY (user: "i want it to have the tool opend ONLY when
    --   the tool is used just for the pathfinding to be better"): this is the
    --   one verified store call, reused right after each pass so a finished
    --   tool stops standing in the way. Refuses the vehicle the player is
    --   sitting in, and says so instead of claiming it worked.
    local function storeOne(m)
        if not m or not m.Parent then return false end
        if m:GetAttribute("InStorage") then return true end
        local char = LocalPlayer.Character
        local hum2 = char and char:FindFirstChildOfClass("Humanoid")
        if hum2 and hum2.SeatPart and hum2.SeatPart:IsDescendantOf(m) then
            log("store: you're sitting in the " .. m.Name .. " — not storing it from the seat")
            return false
        end
        log("store: putting the " .. m.Name .. " back in storage…")
        -- ▸ RETRY (user: "can you make it retry to put it in storage 5 times
        --   then give up to the next"): each attempt re-opens the manager,
        --   asks the same card to Store and waits ~5 s for InStorage to flip.
        --   After 5 refused attempts it stops trying THIS tool and returns —
        --   the caller moves on to the next one.
        for attempt = 1, 5 do
            if stopping() then return false end
            if attempt > 1 then
                log(string.format("store: retrying the %s (%d/5)…", m.Name, attempt))
            end
            managerAction(m.Name, "Store")
            for _ = 1, 10 do -- ~5 s for the store to land
                if stopping() then return false end
                if m:GetAttribute("InStorage") then
                    log("✅ " .. m.Name .. " is back in storage")
                    return true
                end
                task.wait(0.5)
            end
        end
        log("couldn't store the " .. m.Name .. " after 5 tries — giving up on it and moving to the next (its card's Store button may refuse while the tool is out)")
        return false
    end

    local function storeUnusedTools()
        if stopping() then
            log("store: the loop was stopped by hand — leaving the tools where they are")
            return
        end
        local folder = equipmentFolder()
        if not folder then log("store: Objects.Equipment not found") return end
        local hitched = hitchedImplementName()
        local out = {}
        for _, m in ipairs(folder:GetChildren()) do
            if not m:GetAttribute("InStorage") then out[#out + 1] = m end
        end
        if #out == 0 then
            log("store: nothing is out — every tool is already in storage")
            return
        end
        for _, m in ipairs(out) do
            if stopping() then
                log("store: stopped by hand — leaving the rest out")
                return
            end
            if hitched and hitched == m.Name then
                log("store: " .. m.Name .. " is still hitched — not storing it from under the hitch")
            else
                storeOne(m) -- also refuses the seat, with its own line
            end
        end
    end

    -- the actual farming loop, run on its own thread by the toggle below.
    -- stopping() is checked at every wait/step so switching the toggle off
    -- kills the loop at its next step instead of letting it run on.
    local function runFarmingBody()
        seedShopTried = false -- each run gets at most one seed-shop trip
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then log("no character") return end
        local tr, dist, seat = findTractor()
        if not tr then log("tractor (ZM80) not found") return end

        -- ▸ SAFETY (user: "when a vehicle is not within 1000 studs it
        --   will use the equipment manager to respawn it"): a tractor
        --   1000+ studs away can't be walked to — respawn it through the
        --   Equipment Manager instead. ONE attempt; the respawn may
        --   REBUILD the model, so the tractor/seat are re-found after-
        --   wards, and if it's still that far away the run stops
        --   honestly rather than walking the whole map (a player far
        --   from their farm gets an honest stop, never a respawn loop).
        if dist and dist > RESPAWN_RANGE then
            log(string.format("tractor is %.0f studs away (>%d) — respawning it via the Equipment Manager",
                dist, RESPAWN_RANGE))
            managerAction(tr.Name)
            local back = false
            for _ = 1, 30 do -- ~15 s for the respawn to land
                if stopping() then return end
                local tr2, dist2, seat2 = findTractor()
                if tr2 and dist2 and dist2 <= RESPAWN_RANGE then
                    tr, dist, seat = tr2, dist2, seat2
                    back = true
                    break
                end
                task.wait(0.5)
            end
            if not back then
                local tr2, dist2 = findTractor()
                log(string.format("respawn didn't bring the tractor back (%s) — are you far from the farm? not walking that",
                    tr2 and string.format("still %.0f studs away", dist2) or "it's gone"))
                return
            end
            log(string.format("✅ tractor respawned — %.0f studs away now", dist))
        end

        -- ▸ THE SEEDER, FIRST THING — REPORT ONLY. This used to BUY here, so
        --   every run with an empty seeder teleported to FarmCo before any
        --   field work (user: "it should only buy seeds when it is at the
        --   planting loop"). Buying now happens in seedPasses, the PLANT
        --   stage, and only when a field actually has cells waiting.
        seedCheck(tr, hum)
        if stopping() then return end

        -- ▸ step 0: what work is left? (ALL of my fields are scanned —
        --   including fields placed on my plots — and each field's real
        --   state is logged). Checked BEFORE mount so an idle run never
        --   even walks to the tractor. Failed counts never skip (unknown
        --   = work to try).
        local needPlow, needCult, needSeed, needHarv =
            probeWork(tr:GetPivot().Position)
        if not needPlow and not needCult and not needSeed and not needHarv then
            -- truly idle: nothing bare, nothing plowed, everything seeded
            -- — but a FULL seeder is still the step-2 rule (hitch it), so
            -- the seed check still decides
            if not seedCheck(tr, hum) then
                if stopping() then return end
                log("✅ every field is plowed, cultivated and seeded, and nothing is standing — nothing to do")
                return
            end
            if stopping() then return end
            if not mountTractor(char, hum, tr, seat, dist) then return end
            logEquipment()
            seedHitchStep(tr)
            return
        end
        if stopping() then return end

        -- ▸ THE HARVESTER — SPAWN IT, THEN TRAVEL TO IT AND GET IN
        --   (user: "the harvester is a seperate tool from the tractor.
        --   just make it spawn and we will work from there." → "now make
        --   it travel and get into the harvester"): only when there is
        --   actually something standing to harvest (needHarv above) — a
        --   run with nothing to harvest never walks to it at all. The
        --   tool is brought out of storage through the proven Equipment
        --   Manager path, then the player walks to it and sits in its
        --   driver seat with the SAME proven mount sequence the tractor
        --   uses (moveTo → F → seated check; it gets out of any other ride
        --   first). Already out and near → it just walks over and climbs
        --   in.
        local hv, hseat
        if needHarv then
            hv = ensureToolNearby(tr, "Harvester", "harvester")
            if stopping() then return end
            if hv then
                hseat = hv:FindFirstChildWhichIsA("VehicleSeat", true)
                    or hv:FindFirstChildWhichIsA("Seat", true)
                if not hseat then
                    log("the harvester has no driver seat — can't get in")
                elseif hum.SeatPart and hum.SeatPart:IsDescendantOf(hv) then
                    log("already in the harvester (" .. hv.Name .. ")")
                else
                    local root = char:FindFirstChild("HumanoidRootPart")
                    local hdist = root
                        and (hseat.Position - root.Position).Magnitude or 0
                    log(string.format("traveling to the harvester (%s, %.0f studs)…",
                        hv.Name, hdist))
                    if not mountTractor(char, hum, hv, hseat, hdist, "harvester") then
                        log("couldn't get into the harvester — carrying on without it")
                    end
                end
            end
            if stopping() then return end
        end

        -- ONE implement pass: the nearest field still at the job's stage,
        -- hitch THAT job's implement (tug-verified, origin remembered),
        -- drive there, spiral sweep, then unhitch the tool WHERE IT CAME
        -- FROM. Used twice below: the plow (bare -> Plowed), then the
        -- cultivator (Plowed -> Cultivated) — same proven machinery.
        -- ▸ `ride` = the vehicle that DRIVES the tour and `rideSeat` = the
        --   seat its drive keys go to. Default = the tractor. The HARVEST
        --   job passes the harvester instead: it is self-propelled, so it
        --   IS the tool — nothing is hitched and nothing is dropped.
        local function runPass(job, ride, rideSeat)
            ride = ride or tr
            rideSeat = rideSeat or hum.SeatPart
            -- ▸ the TOUR (user request: “combine A+B+C to make the most
            --   eficient path then check back after”): ONE flat route over
            --   EVERY field of mine, nearest-neighbour (see tourOrder) —
            --   work the fields that still need this job, log-and-skip the
            --   rest. One hitch for the whole tour; the tour is only driven
            --   when at least ONE field still needs the job.
            local tour = tourOrder(ride:GetPivot().Position)
            -- kept in the same {fields=…} shape the two loops below use, but
            -- it is now ONE list in one order: the whole farm in one go
            local groups = { { typeName = "my fields", fields = tour } }
            local anyNeed = false
            for _, grp in ipairs(groups) do
                for _, m in ipairs(grp.fields) do
                    local st = countStages(m.d)
                    -- unknown counts stay eligible (never skip on unknown)
                    if not st or st.total == 0
                        or (whichNeed(job, st) or 0) > 0 then
                        anyNeed = true
                    end
                end
            end
            if not anyNeed then
                log("no field needs " .. job.verb .. " — pass skipped")
                return false
            end
            local impl, origin
            if job.selfPropelled then
                -- the ride IS the tool — nothing to hitch, nothing to
                -- unhitch, no Equipment Manager trip either (the harvester
                -- step already made sure it is out and near)
                impl = ride
                origin = ride:GetPivot().Position
                log(string.format("%s: driving the %s itself (self-propelled — nothing to hitch)",
                    job.verb, ride.Name))
            else
                -- safety for every tool: in storage or >1000 studs away =
                -- respawn it via the Equipment Manager (same rule as the
                -- tractor gate), then re-find the fresh model
                local idist, basis
                impl, idist, basis =
                    ensureToolNearby(tr, job.typeName, job.verb)
                if not impl then return false end
                -- remember WHERE the tool was found: after the sweep it gets
                -- unhitched back at THIS spot (user: "unhitch the tools where
                -- they came from")
                origin = impl:GetPivot().Position
                log(string.format("hitch target: %s (%.0f studs, by %s)",
                    impl.Name, idist or 0, basis or "?"))
            end

            -- the proven hitch sequence (stale-HUD tug-verify, wrong-tool
            -- guard, line-up/creep retries) — extracted as hitchTool so
            -- the seeder hitch (step 2) reuses the exact same code
            if not job.selfPropelled and not hitchTool(tr, impl) then
                return false
            end

            -- ▸ the tour: every field, in order — skip the finished ones,
            --   sweep the rest; the tool stays hitched across the whole
            --   tour and goes home at the end
            -- the whole path, logged once: this is the order it will drive
            local tourNames = {}
            for _, m in ipairs(tour) do tourNames[#tourNames + 1] = m.d.Name end
            log(string.format("tour (%d field(s), one go): %s", #tour,
                table.concat(tourNames, " → ")))
            for _, grp in ipairs(groups) do
                for _, m in ipairs(grp.fields) do
                    if stopping() then return false end
                    local st = countStages(m.d)
                    local need = st and whichNeed(job, st) or nil
                    if st and st.total > 0 and need == 0 then
                        log(string.format("SKIP %s — nothing needs %s (%d cells)",
                            m.d.Name, job.verb, st.total))
                    else
                        log(string.format("%s %s (%s land, %s)",
                            job.verb, m.d.Name, m.typeName,
                            need and (need .. " cells need it") or "state unknown"))
                        local arrived, how =
                            driveToField(ride, m.d, rideSeat, impl)
                        if stopping() then return false end
                        if not arrived then
                            log("couldn't reach " .. m.d.Name .. " (" .. tostring(how) .. ")")
                            return false
                        end
                        log("✅ reached " .. m.d.Name)
                        -- honest end-state: did the tool come along? (only
                        -- meaningful when something is HITCHED to the ride)
                        if not job.selfPropelled then
                            local tH, pH =
                                findHitchPart(ride), findHitchPart(impl)
                            if tH and pH then
                                log(string.format("hitch gap at arrival: %.1f studs",
                                    (tH.Position - pH.Position).Magnitude))
                            end
                        end
                        -- the spiral sweep — the game stages cells over as
                        -- the tool passes over them (same for every job)
                        local swept, why = sweepField(ride, m.d, rideSeat, job)
                        if stopping() then return false end
                        if not swept then
                            log(job.verb .. " pass aborted (" .. tostring(why) .. ")")
                            return false
                        end
                    end
                end
            end

            -- unhitch the tool WHERE IT CAME FROM (the tour is done and
            -- it is still attached — an aborted pass leaves it hitched).
            -- A self-propelled ride (the harvester) is never dropped.
            if not job.selfPropelled and impl:IsDescendantOf(workspace) then
                dropImplementAtOrigin(tr, impl, origin)
                -- ▸ OUT ONLY WHILE USED (user: "i want it to have the tool
                --   opend ONLY when the tool is used just for the pathfinding
                --   to be better"): its pass is over and it is parked, so it
                --   goes straight back into storage instead of standing in the
                --   way of the next pass.
                storeOne(impl)
            end
            return true
        end

        -- ▸ THE HARVEST PASS (user: "once it's in the harvester it does the
        --   same loop at the tractor to harvest the crops, goes back and
        --   re does it if any missed"): the SAME field tour + outside-in
        --   spiral + touch-up/missed-cell visits as the tractor passes —
        --   driven IN THE HARVESTER (self-propelled, nothing hitched) and
        --   aimed at every cell with a crop standing. If cells are still
        --   standing after a pass it goes BACK to those fields, with the
        --   same honest guards as the re-seed rule: stop when nothing is
        --   left, when a pass changed nothing, or after 4 rounds.
        local function grownLeft()
            local crops = findMyFields(tr:GetPivot().Position)
            local cells, fields = 0, 0
            for _, m in ipairs(crops) do
                local n = whichNeed(JOBS[4], countStages(m.d))
                if n and n > 0 then
                    cells += n
                    fields += 1
                end
            end
            return cells, fields
        end
        if needHarv and hv and hseat then
            local rounds = 0
            while true do
                rounds += 1
                local before = grownLeft()
                runPass(JOBS[4], hv, hseat)
                if stopping() then return end
                local after, afields = grownLeft()
                if not after or after == 0 then
                    log("✅ nothing is standing in the fields any more")
                    break
                end
                if rounds >= 4 then
                    log(string.format("harvested %d time(s) and %d cell(s) across %d field(s) are still standing — stopping instead of looping",
                        rounds, after, afields))
                    break
                end
                if before and before > 0 and after >= before then
                    log(string.format("the harvest pass didn't change the fields (%d cell(s) still standing) — stopping instead of looping",
                        after))
                    break
                end
                log(string.format("%d cell(s) across %d field(s) still standing — going back to harvest them",
                    after, afields))
            end
        elseif needHarv then
            log("crops are standing but the harvester couldn't be entered — skipping the harvest pass")
        end
        if stopping() then return end

        -- ▸ step 1: mount the tractor (it SWITCHES out of the harvester
        --   when needed; skipped when already in the tractor)
        if not mountTractor(char, hum, tr, seat, dist) then return end

        -- ▸ the harvester's pass is over and we are OUT of it now: back into
        --   storage, so it stops being a parked obstacle for the tractor
        --   passes (user: the tool is out only while it is being used).
        if hv and hv.Parent
            and not (hum.SeatPart and hum.SeatPart:IsDescendantOf(hv)) then
            storeOne(hv)
        end

        logEquipment() -- always show the names so we can confirm the pick

        -- ▸ steps 3-6: the plow pass (bare cells -> Plowed). Called
        --   unconditionally (like the cultivate pass): runPass re-reads the
        --   fields itself and logs "pass skipped" when nothing is bare —
        --   so cells the HARVEST just turned bare are picked up in the
        --   SAME run instead of waiting for the next one.
        runPass(JOBS[1])
        if stopping() then return end
        -- ▸ steps 7-10: the cultivate pass (Plowed -> Cultivated) — usually
        --   the same field the plow pass just finished
        runPass(JOBS[2])
        if stopping() then return end
        -- ▸ SEED CHECK (user: "check everytime after the cultivating") +
        --   SEEDER STEP 2 (user: "if the seeder is full make the tractor
        --   go hitch to the seeder") + SEEDER STEP 3 (user: "make it seed
        --   in the same fields that plow and cultivate did in the same
        --   pattern") — full → hitch, then the seeding pass: the SAME
        --   field tour + SAME outside-in spiral + touch-up, Cultivated →
        --   Seeded on drive-over (the game fires it, never spoofed).
        --   Empty/unreadable → F out (step 1), no pass.
        --   Pulled into one call because the check-back below reuses it.
        local function seedPasses()
            if stopping() then return end
            -- ▸ THE ONLY PLACE COINS ARE SPENT: the planting stage, and only
            --   when a field really has Cultivated cells waiting (the same
            --   count the pass is about to work). An empty seeder with
            --   nothing to plant never sends the run shopping.
            local needCells = seedNeedLeft(tr:GetPivot().Position)
            if not seedCheck(tr, hum, needCells > 0) then return end
            -- ▸ the user's RE-SEED rule: "if the seeder has seeds in it and
            --   the fields are missing some seeding i want it to go back
            --   and seed on that plot of field" — so after a seeding pass,
            --   if any field STILL has cells at Cultivated AND the seeder
            --   still holds seeds, hitch it again and go back to those
            --   fields. Stops when: nothing is left to seed · the seeder
            --   ran empty (logged honestly — it needs a refill) · a pass
            --   changed nothing (so it can never ping-pong) · 6 rounds.
            local rounds = 0
            while true do
                rounds += 1
                if stopping() then return end
                seedHitchStep(tr)
                if stopping() then return end
                local before = seedNeedLeft(tr:GetPivot().Position)
                runPass(JOBS[3])
                if stopping() then return end
                local after, afields = seedNeedLeft(tr:GetPivot().Position)
                if after == 0 then
                    log("✅ seeding complete — no field is missing seed any more")
                    break
                end
                local seeds = seederSeeds(tr)
                if not seeds or seeds <= 0 then
                    log(string.format("seeder is EMPTY and %d cell(s) across %d field(s) still need seeding — refill it (Fill Seeder), then run the loop again", after, afields))
                    break
                end
                if rounds >= 6 then
                    log(string.format("re-seeded %d times and %d cell(s) still need seed — stopping instead of looping", rounds, after))
                    break
                end
                if before and after >= before then
                    log(string.format("the seeding pass didn't change the fields (%d cell(s) still need it) — stopping instead of looping", after))
                    break
                end
                log(string.format("seeder still has %d seed(s) and %d cell(s) across %d field(s) still need seeding — going back to seed them", seeds, after, afields))
            end
        end
        seedPasses()
        if stopping() then return end

        -- ▸ CHECK BACK (user: "then check back after"): after the whole tour,
        --   re-read every field and run whatever is STILL missing once more —
        --   two bounded rounds, and the log says what was left instead of
        --   pretending the farm is finished.
        for round = 1, 2 do
            if stopping() then return end
            local np, nc, ns = probeWork(tr:GetPivot().Position)
            if not (np or nc or ns) then
                log("✅ check-back: every field is plowed, cultivated and seeded")
                break
            end
            log(string.format("check-back %d: still to do — plow:%s cultivate:%s seed:%s",
                round, np and "yes" or "no", nc and "yes" or "no", ns and "yes" or "no"))
            if np then runPass(JOBS[1]) end
            if stopping() then return end
            if nc then runPass(JOBS[2]) end
            if stopping() then return end
            if ns then seedPasses() end
        end

        -- ▸ STAND UP: the tractor's work is done, but nothing can be stored
        --   from the seat — get out so the end-of-run store can actually put
        --   the tractor away (user: the tool is out only while it is used).
        if hum.SeatPart then
            local ride = hum.SeatPart.Parent
            log("done driving — getting out of the " ..
                (ride and ride.Name or "vehicle") .. " so it can be stored")
            pressKey(Enum.KeyCode.F) -- dump: ExitEquipment = F
            for _ = 1, 8 do
                if stopping() then return end
                if not hum.SeatPart then break end
                task.wait(0.25)
            end
            if hum.SeatPart then
                pcall(function() hum.Sit = false end)
                task.wait(0.6)
            end
        end
    end

    -- ▸ the run's wrapper: the whole pass chain above, then the tools go
    --   back in storage ("when it's done"). A wrapper rather than a call at
    --   the end of the body, so EVERY exit of the body — a finished run or
    --   an honest stop — gets the cleanup.
    local function runFarmingLoop()
        -- ▸ AN ERROR STILL CLEANS UP. A crash inside the body used to kill
        --   the thread with the toggle frozen ON and every tool left
        --   standing in the world; now the tools go back to storage and the
        --   caller clears the thread id.
        local okRun, errRun = pcall(runFarmingBody)
        if not okRun then
            log("⚠ farming loop error: " .. tostring(errRun))
        end
        storeUnusedTools()
    end

    -- ▸ SEED PICKER (user: "in the farming section i want a dropdown menu
    --   with all the seeds in the game, this will be used for buying seeds
    --   also. let's start with that"). This step is ONLY the picker —
    --   nothing reads the choice yet. The list is read from the GAME
    --   (FieldHelper.SEED_TYPE — dump §26: 76 entries, bidirectional
    --   id↔name) instead of being hardcoded, so it can never drift from the
    --   game's own vocabulary; "None" is dropped (not a seed you can buy or
    --   plant). If the module can't be read, the picker is simply not
    --   created and the console says so instead of inventing a list.
    --   (seedChoice itself is declared up at the seed-shop block: the seed
    --   check reads it when the seeder is empty.)
    do
        local ok, names = pcall(function()
            local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            local F = mods and mods:FindFirstChild("FieldHelper")
            assert(F, "FieldHelper missing")
            F = require(F)
            local t = F.SEED_TYPE
            assert(type(t) == "table", "SEED_TYPE missing")
            local set = {}
            for k, v in pairs(t) do -- bidirectional: names live on both sides
                if type(k) == "string" then set[k] = true end
                if type(v) == "string" then set[v] = true end
                -- keep the id ↔ name pairs so a crate tagged with the numeric
                -- SeedType can still be named (the shop search)
                if type(k) == "string" and type(v) == "number" then seedIdOf[k] = v end
                if type(k) == "number" and type(v) == "string" then seedNameOf[k] = v end
            end
            set.None = nil
            local out = {}
            for n in pairs(set) do out[#out + 1] = n end
            table.sort(out)
            return out
        end)
        local list = ok and names or nil
        if list and #list > 0 then
            -- ▸ DEFAULT (user: "it went to the store like before but not to a
            --   crate"): the alphabetically first name is an EVENT seed
            --   ("Alien Tentacle") that FarmCo doesn't sell, so the shop trip
            --   found no crate at all. Default to the game's FIRST crop
            --   instead — the lowest SEED_TYPE id (Wheat=2) in its own
            --   vocabulary. A pick from the dropdown always wins.
            local bestName, bestId
            for name2, id2 in pairs(seedIdOf) do
                if not bestId or id2 < bestId then bestName, bestId = name2, id2 end
            end
            local defaultName = bestName or list[1]
            seedChoice = defaultName
            log("seed default: " .. defaultName
                .. " (the game's first crop) — change it in the Farm tab's Seed dropdown")
            log("seed list: " .. #list .. " seed(s) read from the game — "
                .. table.concat(list, ", "))
            Tabs.Farm:CreateDropdown("seedChoice", {
                Title = "Seed",
                Values = list,
                Multi = false,
                Default = defaultName,
                Callback = function(v)
                    seedChoice = v
                    log("seed: " .. tostring(v))
                end,
            })
        else
            log("seed list: FieldHelper.SEED_TYPE unreadable (" .. tostring(names)
                .. ") — no seed picker this session")
        end
    end

    -- ON = spawn the loop on its own thread; OFF = clear the thread id so
    -- stopping() flips true everywhere and the loop dies at its next step.
    -- (coroutine identity, not a bool: a zombie loop can never be revived
    -- by turning the toggle back on for a NEW loop)
    local farmingToggle
    farmingToggle = Tabs.Farm:CreateToggle("farmingLoop", {
        Title = "farming loop",
        Default = false,
        Callback = function(on)
            if on then
                if loopThread then return end -- already running
                log("farming loop: on")
                task.spawn(function()
                    loopThread = coroutine.running()
                    -- ▸ AN ERROR MUST NEVER LEAVE loopThread SET: that froze
                    --   the toggle ON with nothing running (and the toggle
                    --   handler refuses to start a new loop while it is set).
                    local okRun, errRun = pcall(runFarmingLoop)
                    if not okRun then
                        log("⚠ farming loop crashed during cleanup: " .. tostring(errRun))
                    end
                    if loopThread == coroutine.running() then
                        -- ended on its own (success or honest failure)
                        loopThread = nil
                        log("farming loop: ended")
                        pcall(function()
                            (Fluent.Options and Fluent.Options.farmingLoop
                                or farmingToggle):SetValue(false)
                        end)
                    end
                    -- else: user killed it — they already flipped the UI
                end)
            else
                if not loopThread then return end -- already off (echo-safe)
                loopThread = nil
                log("farming loop: off — stopped")
            end
        end,
    })

    -- Settings: reload + unload
    local function destroyUI()
        pcall(function() Fluent:Destroy() end)
        pcall(function() -- fallback: Fluent's own ScreenGui, in case Destroy doesn't exist
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            for _, g in ipairs(pg:GetChildren()) do
                if g:IsA("ScreenGui") and tostring(g.Name):lower():find("fluent") then
                    g:Destroy()
                end
            end
        end)
    end

    Tabs.Settings:CreateDropdown("MoveMode", {
        Title = "Movement",
        Values = { "VFly", "Tween" },
        Multi = false,
        Default = "Tween",
        Callback = function(v)
            Move.Mode = v
            log("movement mode: " .. tostring(v))
        end,
    })

    Tabs.Settings:CreateButton({
        Title = "🔄 Reload latest update",
        Callback = function()
            log("fetching latest build…")
            local ok, src = pcall(function() return game:HttpGet(SCRIPT_URL, true) end)
            if not ok or type(src) ~= "string" or #src < 100 then
                log("ERROR fetch failed — staying on current version")
                Fluent:Notify({ Title = "SPUD FARM", Content = "Update fetch failed — keeping current version", Duration = 5 })
                return
            end
            log("running latest build…")
            loopThread = nil -- stop the old loop before the new build starts
            destroyUI()
            local ok2, err2 = pcall(function()
                local chunk, lerr = loadstring(src)
                if not chunk then error(lerr or "loadstring failed") end
                chunk()
            end)
            if not ok2 then warn("[spud] reload error: " .. tostring(err2)) end
        end,
    })

    Tabs.Settings:CreateButton({
        Title = "⏏ Unload",
        Callback = function()
            loopThread = nil -- stopping() flips true → a running loop dies
            destroyUI()
            print("[spud] unloaded")
        end,
    })

    -- start
    Window:SelectTab(1)
    Fluent:Notify({
        Title = "SPUD FARM",
        Content = "farming loop ready",
        Duration = 6,
    })
    log("loaded — " .. VERSION)
    log("GUI: Fluent Renewed · RIGHT SHIFT hides the window")

    -- FIELD WATCH (user request): scan at launch and re-scan every 15
    -- minutes so newly placed fields get discovered. The farming loop
    -- already re-picks its field per pass — this only REPORTS changes.
    local fieldsKnown, fieldsScanned = {}, false
    local function scanFieldsReport()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        for _, m in ipairs(findMyFields(root and root.Position or Vector3.new(0, 0, 0))) do
            if not fieldsKnown[m.d] then
                fieldsKnown[m.d] = true
                log(string.format("field %s: %s (%s, %.0f studs)",
                    fieldsScanned and "NEW" or "found", m.d.Name, m.typeName, m.dist))
            end
        end
        fieldsScanned = true
    end
    scanFieldsReport()
    task.spawn(function()
        while task.wait(900) do
            log("field re-scan (every 15 min)")
            scanFieldsReport()
        end
    end)
end)

if not okBuild then
    warn("[spud] GUI build error: " .. tostring(errBuild))
    plainNotify("SPUD FARM", "GUI build error: " .. tostring(errBuild):sub(1, 130))
end
