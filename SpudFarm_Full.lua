-- Spud Farm — REBUILD v1.1: Fluent Renewed GUI shell (STILL NO game features)
-- GUI = Fluent Renewed (open source, no telemetry). NOTE: Renewed uses the
-- Create* API (CreateTab/CreateParagraph/CreateButton), not the old Add* one.
-- Features come back ONE AT A TIME, tested in-game before the next one lands.
-- This build only: window + tabs + console + 🔄 reload. Touches NOTHING in-game.

local LIB_URL    = "https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"
local SCRIPT_URL = "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua"
local VERSION    = "rebuild v1.6 · fluent gui"

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    -- GetPlayerAdded does NOT exist: that typo used to kill the whole load
    -- before a single pixel was drawn
    local okWait, who = pcall(function() return Players.PlayerAdded:Wait() end)
    LocalPlayer = okWait and who or nil
end
if not LocalPlayer then
    warn("[spud] no LocalPlayer yet - aborting before the GUI")
    return
end

print("[spud] start " .. VERSION)

local function plainNotify(title, text) -- used before/outside the library
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
    end)
end

------------------------------------------------------------
-- load the GUI library
------------------------------------------------------------
local okLib, Fluent
local libErr
for attempt = 1, 3 do
    okLib, Fluent = pcall(function()
        local src = game:HttpGet(LIB_URL, true)
        assert(type(src) == "string" and #src > 1000, "HttpGet returned " .. tostring(src and #src))
        return assert(loadstring(src))()
    end)
    if okLib and type(Fluent) == "table" then break end
    libErr = Fluent
    warn(string.format("[spud] GUI library attempt %d failed: %s", attempt, tostring(Fluent)))
    task.wait(2)
end
if not okLib or type(Fluent) ~= "table" then
    warn("[spud] GUI library failed for good: " .. tostring(libErr))
    plainNotify("SPUD FARM", "GUI library failed: " .. tostring(libErr):sub(1, 90))
    return
end
print("[spud] library loaded")

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
    print("[spud] window created")

    local Tabs = {
        Home     = Window:CreateTab({ Title = "Home", Icon = "house" }),
        -- ▸ its own tab, second from the left: the report is a diagnostic, not
        --   a farm control, and it must be findable in one look
        Doctor   = Window:CreateTab({ Title = "Doctor", Icon = "stethoscope" }),
        Farm     = Window:CreateTab({ Title = "Farm", Icon = "wheat" }),
        -- ▸ MILK (user: "is is a feature, im preparing the dump. it will be a
        --   section called 'Milk' that will go on my friends plot, find a cow
        --   at 300% then tell it to go to the barn then it will milk the cow,
        --   send it back to the feild and repeat"). GUI SHELL ONLY for now.
        Milk     = Window:CreateTab({ Title = "Milk", Icon = "droplet" }),
        Player   = Window:CreateTab({ Title = "Player", Icon = "user" }),
        Console  = Window:CreateTab({ Title = "Console", Icon = "terminal" }),
        Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" }),
    }

    -- console log (also printed to the executor console)
    print("[spud] gui: window + tabs ok") -- log() exists a few lines below

    local LOG = {}
    local logPara = Tabs.Console:CreateParagraph("ConsoleLog", {
        Title = "Console",
        Content = "loaded",
    })

    ------------------------------------------------------------
    -- ▸ WEBHOOK SINK (user: "i also want a webhook now please, it
    --   sends everything to the webhook"). EVERY line log() prints
    --   is queued and posted to a Discord webhook in batches, so the
    --   console exists outside the game: a run can be read on a
    --   phone, or pasted straight to me, with no copy-paste.
    --   The URL is NOT hard-coded in the public repo (anyone could
    --   spam it): paste it once in Settings → "webhook url", and it
    --   is remembered in a local file when the executor allows it.
    ------------------------------------------------------------
    local HOOK_FILE = "spudfarm_webhook.txt"
    local HOOK_URL_HARDCODED = "" -- optional: paste a URL here instead of the box
    local hookQueue, hookURL, hookDropped, hookFails = {}, "", 0, 0
    local hookHealthy = true

    local function hookLoadURL()
        if HOOK_URL_HARDCODED ~= "" then return (HOOK_URL_HARDCODED:gsub("%s+", "")) end
        local ok, v = pcall(function() return readfile(HOOK_FILE) end)
        if ok and type(v) == "string" then
            v = v:gsub("%s+", "")
            if #v > 20 then return v end
        end
        return ""
    end
    local function hookSaveURL(u)
        pcall(function() writefile(HOOK_FILE, u) end)
    end
    local function hookHTTP(payload)
        local fn = (syn and syn.request) or (http and http.request)
            or (fluxus and fluxus.request) or http_request or request
        if type(fn) ~= "function" then
            return false, "this executor has no HTTP request function"
        end
        local ok, res = pcall(fn, {
            Url = hookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload,
        })
        if not ok then return false, tostring(res) end
        -- ▸ A DISCORD REJECTION IS NOT A DELIVERY. 429 (rate limit) and 5xx
        --   used to count as "sent" because the request itself succeeded, so a
        --   burst quietly vanished and the console looked complete. Any 4xx/5xx
        --   now fails the post, and the batch is put back in the queue.
        if type(res) == "table" then
            local code = tonumber(res.StatusCode or res.status or res.statusCode)
            if code and (code == 429 or code >= 400) then
                return false, "HTTP " .. tostring(code)
            end
        end
        return true
    end
    -- one batch = as many queued lines as fit in one Discord message
    local function hookFlush()
        if hookURL == "" or not hookHealthy or #hookQueue == 0 then return end
        local batch, size = {}, 0
        while #hookQueue > 0 do
            local line = hookQueue[1]
            if size + #line + 1 > 1700 then break end
            table.remove(hookQueue, 1)
            size += #line + 1
            batch[#batch + 1] = line
        end
        if #batch == 0 then return end
        local body = table.concat(batch, "\n")
        if hookDropped > 0 then
            body = body .. string.format("\n… %d earlier line(s) dropped (offline)", hookDropped)
            hookDropped = 0
        end
        local ok, err = hookHTTP(game:GetService("HttpService"):JSONEncode({
            username = "spud farm",
            content = body,
        }))
        if ok then
            hookFails = 0
        else
            -- put the batch back at the FRONT: a rate limit must not eat logs
            for i = #batch, 1, -1 do
                table.insert(hookQueue, 1, batch[i])
            end
            while #hookQueue > 300 do
                table.remove(hookQueue)
                hookDropped += 1
            end
            hookFails += 1
            if hookFails >= 5 then
                hookHealthy = false
                print("[spud] webhook disabled after 5 failed posts: " .. tostring(err))
            end
        end
    end
    local function hookPush(line)
        if hookURL == "" then return end
        hookQueue[#hookQueue + 1] = line
        if #hookQueue > 300 then
            table.remove(hookQueue, 1)
            hookDropped += 1
        end
    end
    local function setHookURL(u)
        u = tostring(u or ""):gsub("%s+", "")
        if u ~= "" and not u:lower():find("discord") then
            return false, "that doesn't look like a Discord webhook url"
        end
        hookURL, hookFails, hookHealthy = u, 0, true
        hookQueue = {}
        if u ~= "" then hookSaveURL(u) end
        return true
    end
    hookURL = hookLoadURL()
    -- the pump runs for the whole session; it is a no-op until a URL is set
    task.spawn(function()
        while true do
            task.wait(2.5) -- 24 posts/min max, under Discord's 30/min
            pcall(hookFlush)
        end
    end)
    do
        local g = (getgenv and getgenv()) or _G
        if g then
            g.spudWebhook = function(url)
                -- ▸ never echo the URL itself: it is a live credential and the
                --   console gets screenshotted into reports.
                local function mask(u)
                    u = tostring(u or "")
                    if #u < 24 then return "set (hidden)" end
                    return u:sub(1, 33) .. "…" .. u:sub(-6)
                end
                if url == nil then
                    print("[spud] webhook: " .. (hookURL == "" and "not set" or mask(hookURL)))
                    return hookURL
                end
                local ok, why = setHookURL(url)
                print(ok and "[spud] webhook: set" or ("[spud] webhook: " .. tostring(why)))
                return ok
            end
        end
    end

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
        -- ▸ and OUT of the game: every line goes to the webhook queue too
        hookPush(tostring(msg))
    end

    -- ▸ the webhook says hello if a URL was remembered from last session, so
    --   the first message proves the pipe works before anything else happens
    if hookURL ~= "" then
        log(string.format("webhook: on · %s · place %d", VERSION, game.PlaceId))
        task.spawn(function() task.wait(0.5) pcall(hookFlush) end)
    else
        log("webhook: off — paste a url in Settings to mirror this console there")
    end

    -- ▸ STAGE (user: "sometimes it just end with this" + "it looks to stay
    --   on but does nothing"): a stalled run and a dead run looked
    --   IDENTICAL — toggle still ON, console silent. runStage names where
    --   the loop last was, and one watcher thread prints it every 10 s
    --   while the body runs, so the console can never just go quiet:
    --     · the line keeps coming = alive and stuck in THAT stage
    --     · it stops coming       = the thread died (a body error prints
    --       its own ⚠ line first; stopping by hand is silent on purpose)
    local runStage = "not started yet"
    local function setStage(s)
        runStage = s
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

    -- ▸ REGISTER BUDGET. The whole GUI build used to be ONE function, and the
    --   executor's Luau caps a function at 200 local variables (total decla-
    --   rations, not live ones) - the milk tab pushed it over and the script
    --   died at load with "Out of local registers ... exceeded limit 200".
    --   so the feature code now lives in its own do-block and only the names
    --   the rest of the file needs stay at this level.
    local stopping, loopThread, pressKey, Move, invokeHandlers
    local findMyFields, runDoctor, milkThread, milkStopping, farmResting, farmTookBody
    do

    -- ▸ AUTO-FARM STEP 1 (and nothing more): mount the tractor
    local VIM = game:GetService("VirtualInputManager")
    pressKey = function(key)
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.08)
        VIM:SendKeyEvent(false, key, false, game)
    end

    -- the live farming-loop thread (nil = no loop running). Every movement /
    -- creep / hitch helper checks stopping(), so switching the toggle OFF
    -- kills the loop at its next step instead of letting it keep going.
    -- coroutine identity (not just a bool) so a zombie loop can never be
    -- revived by turning the toggle back on for a NEW loop.
    loopThread = nil -- the live farming-loop thread (nil = no loop running)
    stopping = function()
        if not loopThread then return true end
        return coroutine.running() ~= loopThread
    end

    -- ▸ THE 1-SECOND HARVEST WATCH (user: "check every second when it's in the
    --   harvester to check if it's full and then sell"). Every field-drive
    --   loop calls this on each step; it reads the game's own
    --   Capacity/MaxCapacity at most once a second, and ONLY for a vehicle
    --   whose EquipmentType is Harvester, so no other pass pays anything.
    --   When it fires, the leg stops where it is and the sweep sells before
    --   doing anything else. sellingNow mutes it during the sell trip itself
    --   (the tank is still full while driving to the pad).
    local watchLast, watchHit, sellingNow = 0, false, false
    -- ▸ SELL COOLDOWN. The watch and the retry cap used to multiply: a pad
    --   that wouldn't sell got re-triggered one second after every failed
    --   trip, so six attempts × four pads × 16 s could eat six minutes of a
    --   sweep with the tank full. A failed trip now parks the whole idea for
    --   a minute and the harvesting carries on.
    local sellCooldownUntil = 0
    -- ▸ WHICH MODEL IS THE HARVESTER? The attribute is the game's own answer,
    --   but ONE missing attribute used to switch off BOTH behaviours that
    --   depend on it — the 10 studs/s swath tween and the 1-second full-tank
    --   watch — and the two failures look unrelated in game (the harvester
    --   steers itself off the row; a full tank never sells). The dump's own
    --   model name and the caller's intent are fallbacks, and the first
    --   decision is logged so one line says which one matched.
    local HARVEST_MODEL_NAMES = { SRC6 = true }
    local harvestDetectLogged = false
    local function isHarvester(tr, impl)
        if not tr then return false end
        local how
        if impl and impl == tr then
            how = "this pass drives the tool itself"
        else
            local okT, etype = pcall(function() return tr:GetAttribute("EquipmentType") end)
            if okT and etype ~= nil then
                -- ▸ THE ATTRIBUTE IS THE ANSWER, EVEN WHEN IT SAYS NO. The old
                --   chain fell through to the name table whenever the value
                --   wasn't "Harvester", and that table listed ZM80 — the
                --   TRACTOR (dump: ZM80=Tractor, SRC6=Harvester). So every
                --   tractor route ran on the harvester's PivotTo tween: the
                --   align mover was never started, nothing followed the A*
                --   line, and the tractor (with the plow towed behind it)
                --   was swept straight through gear and barns.
                if etype == "Harvester" then how = "EquipmentType attribute" end
            elseif HARVEST_MODEL_NAMES[tostring(tr.Name)] then
                -- attribute missing entirely — fall back to the dump's model
                how = "model name " .. tostring(tr.Name)
            end
        end
        if how and not harvestDetectLogged then
            harvestDetectLogged = true
            log("harvest ride: " .. tostring(tr.Name) .. " recognised by " .. how)
        end
        return how ~= nil
    end
    local function driveWatchTick(tr)
        if watchHit then return true end
        if sellingNow or not tr then return false end
        if os.clock() < sellCooldownUntil then return false end
        if os.clock() - watchLast < 1 then return false end
        watchLast = os.clock()
        if not isHarvester(tr) then return false end
        local ok, cur, max = pcall(function()
            local conf = tr:FindFirstChild("Configurations")
            if not conf then return nil end
            local c = conf:FindFirstChild("Capacity")
            local m = conf:FindFirstChild("MaxCapacity")
            return (c and c:IsA("IntValue")) and c.Value or nil,
                (m and m:IsA("IntValue")) and m.Value or nil
        end)
        if ok and cur and max and max > 0 and cur >= max then
            watchHit = true
            log(string.format("harvester hit capacity (%d/%d) while driving — stopping this leg to sell",
                cur, max))
        end
        return watchHit
    end

    -- ▸ AUTO-FARM STEP 2: movement (Tween = fly-over ARC — up, across at
    --   altitude, down onto the target; the player carries nothing so
    --   nothing smashes. VFly = legacy BodyVelocity steps.)
    Move = { Mode = "Tween", Speed = 200 }
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
    -- - so the game's logic can't run twice.
    invokeHandlers = function(btn)
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
            -- ▸ IS THE CARD ACTUALLY ON SCREEN (user: "it calls the card before
            --   they are even visible")? A card object exists in the tree as
            --   soon as the list is built, but the menu populates LATE and each
            --   card is laid out / made visible a moment later — clicking the
            --   handler of a card that hasn't been shown yet does nothing, and
            --   the old code clicked once and gave up.
            local function onScreen(o)
                local hop = o
                while hop and hop ~= menu do
                    if hop:IsA("GuiObject") and not hop.Visible then return false end
                    hop = hop.Parent
                end
                return o.AbsoluteSize.X > 1 and o.AbsoluteSize.Y > 1
            end
            local card
            for _ = 1, 40 do -- ~10 s for the card list to populate and lay out
                if stopping() then break end
                card = findCard()
                if card and onScreen(card) then break end
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
            if not onScreen(card) then
                log("equipment manager: the " .. vehicleName .. " card exists but never became visible — using it anyway")
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
            -- ▸ CLICK THE CARD UNTIL THE DETAIL VIEW OPENS (user: "it calls the
            --   card before they are even visible"). One click was the whole
            --   story: if the card had just been created its handler ran
            --   against an empty ExpandedCard and nothing happened. Three
            --   tries, re-finding the card each time (the list can be rebuilt
            --   while it populates).
            local opened = false
            for i = 1, 3 do
                if stopping() then break end
                card = findCard() or card
                clickEffect(card, expandedShows)
                if expandedShows() then opened = true break end
                log(string.format("equipment manager: card click %d/3 didn't open the detail view (it shows '%s') — retrying",
                    i, (expandedName() or "nothing")))
                task.wait(0.6)
            end
            if not opened then
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

    -- ▸ RESPAWN A TOOL, WITH RETRIES (user: "it's not retrying 5 times").
    --   ONE Spawn click used to be the whole story, and it was judged by
    --   "is it close to the player" — but a respawn always lands in front of
    --   YOUR PLOT, so a player who is not standing at their own farm could
    --   never see that test pass even when the spawn worked. The test is now
    --   the MODEL MOVING: a stored / desynced vehicle sits in the void at
    --   tens of thousands of studs (the dump showed ~±100k), so any real
    --   move of a few hundred studs means it came out. Up to 5 attempts.
    --   Returns the new position, or nil after every attempt failed.
    local function respawnTool(name, getPos, attempts)
        attempts = attempts or 5
        local uiFails = 0
        local p0 = getPos()
        for i = 1, attempts do
            if stopping() then return nil end
            log(string.format("respawn %s: attempt %d/%d (Equipment Manager → Spawn)",
                name, i, attempts))
            -- if the MANAGER itself won't open/drive (not the vehicle), 5
            -- attempts just burn 40 s of the run
            if managerAction(name, "Spawn") == false then
                uiFails += 1
                if uiFails >= 2 then
                    log(string.format("%s: the Equipment Manager wouldn't drive for this vehicle — giving up for now", name))
                    return nil
                end
            end
            if stopping() then return nil end
            for _ = 1, 16 do -- ~8 s for THIS attempt to land
                if stopping() then return nil end
                local p1 = getPos()
                if p1 and (not p0 or (p1 - p0).Magnitude > 200) then
                    log(string.format("✅ %s respawned — it moved %s", name,
                        p0 and string.format("%.0f studs", (p1 - p0).Magnitude) or "into the world"))
                    return p1
                end
                task.wait(0.5)
            end
            local p1 = getPos()
            log(string.format("respawn %s: attempt %d didn't move it (%s)", name, i,
                (p1 and p0) and string.format("still %.0f studs from where it was", (p1 - p0).Magnitude)
                    or "position unreadable"))
            p0 = p1 or p0
        end
        log(string.format("⚠ %s didn't respawn after %d attempts — spawn it once by hand from the Equipment Manager, then start the loop",
            name, attempts))
        return nil
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
        setStage("Equipment Manager: respawning " .. impl.Name)
        local moved = respawnTool(impl.Name, function()
            local i2 = findImplement(typeName, tr:GetPivot().Position, tr)
            return i2 and i2:GetPivot().Position or nil
        end, 5)
        if not moved then
            log(string.format("respawn didn't bring the %s back — skipping this pass", verb))
            return nil
        end
        setStage("waiting for " .. impl.Name .. " to be usable")
        local impl2, dist2, basis2 =
            findImplement(typeName, tr:GetPivot().Position, tr)
        if impl2 then
            log(string.format("✅ %s is out — %.0f studs away now", impl2.Name, dist2 or 0))
            if dist2 and dist2 > RESPAWN_RANGE then
                log(string.format("⚠ it spawned %.0f studs from the tractor (>%d) — hitching may still fail from here",
                    dist2, RESPAWN_RANGE))
            end
        end
        return impl2, dist2, basis2
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
            if driveWatchTick(tr) then return end
            local t = i / steps
            local ease = 1 - (1 - t) * (1 - t) -- ease-out: quick start, soft landing
            local p = Vector3.new(pos.X, y, pos.Z) + flat * ease
            tr:PivotTo(CFrame.lookAt(p, p + flat)) -- face travel direction
            task.wait(0.05)
        end
    end

    -- ▸ THE HARVESTER IS TWEENED, NOT STEERED (user: "make the harvester
    --   force the angle that it harvests at and not turn, so instead of
    --   using WASD it uses tween but slow like 10 studs/sec"). WASD drives
    --   by pushing a physics body: the nose wobbles, the turn overshoots the
    --   row, and the swath ends up crooked. A harvester leg is now a plain
    --   positional tween down the leg at a SET heading — the angle is
    --   written every step, never steered — at 10 studs/s.
    local HARVEST_TWEEN_SPEED = 10 -- studs per second (user's number)

    -- ▸ THE SEAT'S OWN THROTTLE (user: "manipulate it, it is bugging out").
    --   Holding W made the game's controller and the position tween fight: the
    --   engine pushed while the tween pulled the chassis back every tick. The
    --   fix is to stop moving the chassis ourselves: write the SEAT's Throttle
    --   (the property the local vehicle controller already reads), let the GAME
    --   drive — which is what registers the crop pickup — and only re-assert
    --   the row heading plus a lateral snap when it drifts past ~2 studs.
    local function setThrottle(seat, v)
        pcall(function()
            seat.Throttle = v
            seat.ThrottleFloat = v
            -- hold the wheel straight too: if the game's controller is still
            -- feeding Steer from input, a leftover value curves the row
            seat.Steer = 0
            seat.SteerFloat = 0
        end)
    end

    local function tweenDriveLeg(tr, from, goal, speed)
        speed = speed or HARVEST_TWEEN_SPEED
        local startCF = tr:GetPivot()
        local y = startCF.Position.Y -- stay on the field plane: no hopping
        local a = Vector3.new(from.X, y, from.Z)
        local b = Vector3.new(goal.X, y, goal.Z)
        local delta = b - a
        local dist = delta.Magnitude
        if dist < 0.5 then return true end
        local dir = delta / dist
        local rot = CFrame.lookAt(Vector3.zero, dir) -- the fixed heading
        local travelled, tick = 0, 0.1
        while travelled < dist do
            if stopping() then return nil end
            -- the 1-second full-tank watch works here too
            if driveWatchTick(tr) then return false end
            travelled = math.min(dist, travelled + speed * tick)
            local p = a + dir * travelled
            tr:PivotTo(CFrame.new(p) * rot)
            task.wait(tick)
        end
        tr:PivotTo(CFrame.new(b) * rot) -- land exactly on the leg end
        return true
    end

    -- ▸ THROTTLE-DRIVEN ROW, NO SNAPS (user: "the feild pathfinding is kinda
    --   fucked up … it snaps/teleports at row ends, goes off the field and past
    --   the specified field"). Three rules:
    --   1. TURN FIRST, SMOOTHLY — the nose is eased onto the row at TURN_RATE
    --      with the throttle shut, so a row never starts with a CFrame snap and
    --      a 180° row reversal is a visible turn, not a teleport.
    --   2. NO POSITION SNAPS — drift is corrected at most 0.4 studs per tick,
    --      and the row end is ACCEPTED where the vehicle is (never PivotTo'd
    --      onto the target point, which was a multi-stud jump every row).
    --   3. BRAKE EARLY — throttle off ~10 studs before the row end and accept at
    --      4, so momentum cannot carry it past the plot edge and into a fence.
    --   Returns true/false like the tween (false = the full-tank watch fired),
    --   nil = stopped. If the throttle produces no movement the row falls back
    --   to the tween, so it can never stall.
    local function throttleRow(tr, seat, from, goal)
        if not seat then return tweenDriveLeg(tr, from, goal, HARVEST_TWEEN_SPEED) end
        local y0 = tr:GetPivot().Position.Y
        local A = Vector3.new(from.X, y0, from.Z)
        local B = Vector3.new(goal.X, y0, goal.Z)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 1 then return true end
        local dir = leg / legLen
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        local TURN_RATE = math.rad(150) -- per second
        local BRAKE, ACCEPT = 10, 4
        local deadline = os.clock() + 15 + legLen / 3 + 2
        local prox0 = tr:GetPivot().Position
        local throttleSince
        local coastPrev, coastClock = tr:GetPivot().Position, os.clock()
        local okRun, res = pcall(function()
            while os.clock() < deadline do
                if stopping() then return nil end
                if driveWatchTick(tr) then return false end
                local cf = tr:GetPivot()
                local p = cf.Position
                local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
                flat = flat.Magnitude > 0.1 and flat.Unit or dir
                local rel = Vector3.new(p.X, 0, p.Z) - A
                local along, cross = rel:Dot(dir), rel:Dot(perp)
                local remaining = legLen - along
                local ang = math.acos(math.clamp(flat:Dot(dir), -1, 1))
                if ang > math.rad(3) then
                    -- turning: no throttle, eased heading, position untouched
                    setThrottle(seat, 0)
                    throttleSince = nil
                    local step = math.min(ang, TURN_RATE * 0.1)
                    local axis = flat:Cross(dir)
                    local signed = CFrame.fromAxisAngle(Vector3.yAxis,
                        (axis.Y >= 0 and 1 or -1) * step)
                    local nd = signed * flat
                    nd = Vector3.new(nd.X, 0, nd.Z)
                    if nd.Magnitude > 0.01 then
                        tr:PivotTo(CFrame.new(p) * CFrame.lookAt(Vector3.zero, nd.Unit))
                    end
                else
                    if remaining <= ACCEPT then return true end -- accept HERE: no snap
                    if remaining <= BRAKE then
                        -- braking: accept once the coast really stopped (a short
                        -- row or heavy soil stops it before ACCEPT, and waiting
                        -- for the deadline would stall the whole sweep)
                        setThrottle(seat, 0)
                        local now = os.clock()
                        if (p - coastPrev).Magnitude > 0.3 then
                            coastPrev, coastClock = p, now
                        elseif now - coastClock > 0.6 then
                            return true
                        end
                    else
                        setThrottle(seat, 1)
                        throttleSince = throttleSince or os.clock()
                        -- gentle lane keep: never a multi-stud jump
                        if math.abs(cross) > 1 then
                            local shift = math.clamp(cross, -0.4, 0.4)
                            local q = Vector3.new(p.X, p.Y, p.Z) - perp * shift
                            tr:PivotTo(CFrame.new(q) * CFrame.lookAt(Vector3.zero, dir))
                        end
                        if throttleSince and os.clock() - throttleSince > 2.5 and
                            (Vector3.new(p.X, 0, p.Z) - Vector3.new(prox0.X, 0, prox0.Z)).Magnitude < 1.5 then
                            return "nothrottle"
                        end
                    end
                end
                task.wait(0.1)
            end
            return false
        end)
        setThrottle(seat, 0)
        if not okRun or res == nil then return nil end
        if res == "nothrottle" then
            log("harvester: the seat throttle didn't move it — tweening this row instead")
            return tweenDriveLeg(tr, from, goal, HARVEST_TWEEN_SPEED)
        end
        return res
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
    findMyFields = function(nearPos)
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
        local function scan(container)
            if not container then return end
            for _, m in ipairs(container:GetChildren()) do
                if m ~= ignore1 and m ~= ignore2 then
                    if m:IsA("BasePart") then
                        if m.CanCollide then -- a sign can't stop a wheel
                            counter.n += 1
                            markPart(m)
                        end
                    elseif m:IsA("Model") or m:IsA("Folder") then
                        -- ▸ ALL THE WAY DOWN, not two levels (regression: the
                        --   depth cap stopped at Model/Folder, and a tractor's
                        --   parts sit at Equipment.ZM80.Body.SkinGroups.Other
                        --   — three deep — so almost nothing solid got marked
                        --   and the route cut straight through parked gear and
                        --   buildings. A barn is not a child-level Model.)
                        scan(m)
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
                -- 2 clear cells to anything the mapper marked. The two ENDS
                -- are exempt — we are already standing on the start cell and
                -- the goal is the target, so demanding clearance there made
                -- lineClear fail on every hop whenever the ride was parked
                -- beside a tool, and the route collapsed into 6-stud steps.
                if i > 0 and i < steps and (clearDist[k] or 0) < 2 then return false end
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

        -- ▸ CURVES, NOT SQUARES (user: "use curves not squares"). A chamfer
        --   cut at most 10 studs off a corner — a ~45° kink that the nose has
        --   to swing in one go, with the towed tool swinging wider still. Each
        --   sharp vertex is now a QUINTIC BEZIER blend (q1 → q → q2) sampled
        --   every ~1.4 studs, and the radius is grown until the blend's own
        --   samples are all free: try 22 studs, then 14, then 8, else keep the
        --   vertex sharp. Long straights stay single segments, so the tween
        --   driver still works leg by leg.
        --   ▸ WHY QUINTIC AND NOT THE OLD QUADRATIC: a circular/quadratic arc
        --     is only G1 — the curvature jumps from 0 to 1/R the instant the
        --     nose enters it, which is the visible "swings wide then jerks".
        --     A degree-5 blend with its curvature forced to ZERO at both ends
        --     (B''(0)=B''(1)=0 → P2 = 2P1 − P0, P4 = (P3+P5)/2) is G2: the
        --     steering rate is continuous, so it can be driven faster without
        --     the wheels snapping (Brezak 2011 measured up to 25% higher
        --     trackable speed and a fraction of the cross-track error vs arcs).
        local function freeAt(x, z)
            local ix, iz = cellOf(x, x0), cellOf(z, z0)
            if ix < 0 or iz < 0 or ix >= nx or iz >= nz then return false end
            return not blocked[ix * 100000 + iz]
        end
        local out = { pts[1] }
        for i = 2, #pts - 1 do
            local p, q, r = pts[i - 1], pts[i], pts[i + 1]
            local d1x, d1z = q[1] - p[1], q[2] - p[2]
            local d2x, d2z = r[1] - q[1], r[2] - q[2]
            local l1 = math.sqrt(d1x * d1x + d1z * d1z)
            local l2 = math.sqrt(d2x * d2x + d2z * d2z)
            local curved = false
            if l1 > 6 and l2 > 6 then
                local cosang = (d1x * d2x + d1z * d2z) / (l1 * l2)
                if cosang < 0.94 then -- anything past ~20° of turn
                    local u1x, u1z = d1x / l1, d1z / l1 -- incoming direction
                    local u2x, u2z = d2x / l2, d2z / l2 -- outgoing direction
                    for _, want in ipairs({ 22, 14, 8 }) do
                        local d = math.min(want, l1 * 0.45, l2 * 0.45)
                        -- quintic control points: enter at q0, leave at q5,
                        -- curvature zero at both ends, so it joins the straight
                        -- legs with no steering-rate step
                        local p0x, p0z = q[1] - u1x * d, q[2] - u1z * d
                        local p5x, p5z = q[1] + u2x * d, q[2] + u2z * d
                        local a = 0.55 * d
                        local p1x, p1z = p0x + u1x * a, p0z + u1z * a
                        local p2x, p2z = p0x + u1x * 2 * a, p0z + u1z * 2 * a
                        local p4x, p4z = p5x - u2x * a, p5z - u2z * a
                        local p3x, p3z = p5x - u2x * 2 * a, p5z - u2z * 2 * a
                        local n = math.max(6, math.ceil(d / 1.4))
                        local okArc = freeAt(p0x, p0z) and freeAt(p5x, p5z)
                        local samples = {}
                        for k = 1, n - 1 do
                            local t = k / n
                            local u = 1 - t
                            local b0 = u ^ 5
                            local b1 = 5 * u ^ 4 * t
                            local b2 = 10 * u ^ 3 * t * t
                            local b3 = 10 * u * u * t ^ 3
                            local b4 = 5 * u * t ^ 4
                            local b5 = t ^ 5
                            local sx = b0 * p0x + b1 * p1x + b2 * p2x
                                + b3 * p3x + b4 * p4x + b5 * p5x
                            local sz = b0 * p0z + b1 * p1z + b2 * p2z
                                + b3 * p3z + b4 * p4z + b5 * p5z
                            samples[k] = { sx, sz }
                            if okArc and not freeAt(sx, sz) then okArc = false end
                        end
                        if okArc then
                            out[#out + 1] = { p0x, p0z }
                            for _, sp in ipairs(samples) do out[#out + 1] = sp end
                            out[#out + 1] = { p5x, p5z }
                            curved = true
                            break
                        end
                    end
                end
            end
            if not curved then out[#out + 1] = q end
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
    -- ▸ NETWORK OWNERSHIP (Roblox docs, "Network ownership": the DRIVER should
    --   own the vehicle). A vehicle left server-owned answers input several
    --   network cycles late — that is the mushiness you feel on mobile. Claim
    --   the assembly for the local player so the game's own controller answers
    --   on this frame instead of three later. Harmless where the executor
    --   refuses it (pcall).
    local function claimOwnership(tr)
        local part = tr.PrimaryPart or tr:FindFirstChildWhichIsA("BasePart", true)
        if not part then return end
        pcall(function() part:SetNetworkOwner(LocalPlayer) end)
    end

    local function alignDriveStart(tr)
        claimOwnership(tr)
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
        -- ▸ RESPONSIVENESS IS THE TWITCH KNOB (user: "it's twitching the wheels
        --   a lot when working on the field"). At 30 the servo was stiff enough
        --   to answer every physics jolt of the soil in one tick, and the whole
        --   chassis buzzed. 12 still reaches the top speed instantly (the
        --   velocity clamp does that) but rides out the bumps. Raise it toward
        --   20 only if the line starts lagging; lower it toward 6 if it buzzes.
        pos.Responsiveness = 12
        pos.Parent = part
        local ori = Instance.new("AlignOrientation")
        ori.Name = "SpudAlignOri"
        ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ori.Attachment0 = a0
        ori.MaxTorque = mass * 6
        ori.MaxAngularVelocity = math.rad(ALIGN_YAW * 1.5)
        ori.Responsiveness = 8
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
    -- ▸ AIM AT ONE POINT (pure pursuit). Steering only: the nose eases toward
    --   the aim at ALIGN_YAW, thrust is always along the nose, and the speed
    --   drops while the nose is still turning. alignDriveStep calls it with a
    --   point on a straight leg; the route follower calls it with a point a
    --   LOOKAHEAD ahead along the whole path — aiming at a point ahead, not at
    --   the next leg end, is what turns a Bezier corner into one continuous
    --   arc instead of "drive to the corner, then rotate".
    local function alignDriveAim(h, tr, aimX, aimZ, dt)
        local p = tr:GetPivot().Position
        local want = Vector3.new(aimX - p.X, 0, aimZ - p.Z)
        local dist = want.Magnitude
        if dist < 0.5 then return 0 end
        want = want / dist
        -- ▸ SMOOTH THE AIM, DON'T CHASE NOISE (user: "it's twitching the wheels
        --   a lot when working on the field"). The aim point sits ~14 studs
        --   ahead, so a 0.25-stud jolt in position is a whole degree of heading
        --   — and re-aiming at that on every tick made the front wheels visibly
        --   vibrate. The aim direction is now low-passed, and a change under
        --   ~0.8° is ignored outright: that is physics noise, not steering.
        local prev = h.aim
        if prev then
            if prev:Dot(want) > 0.9999 then want = prev end
            h.aim = (prev * 0.75 + want * 0.25).Unit
        else
            h.aim = want
        end
        want = h.aim
        local ang = math.acos(math.clamp(h.dir:Dot(want), -1, 1))
        if ang > 1e-4 then
            local t = math.min(1, math.rad(ALIGN_YAW) * (dt or 0.12) / ang)
            h.dir = (h.dir * (1 - t) + want * t).Unit
        end
        -- creep while the nose is still turning (the key driver's rule)
        local cap = h.cap or ALIGN_MAXVEL
        h.pos.MaxVelocity = math.clamp(cap * (1 - ang / 1.6), cap * 0.2, cap)
        h.ori.CFrame = CFrame.lookAt(Vector3.zero, h.dir)
        local goal = p + h.dir * math.clamp(dist, 2, ALIGN_AIM)
        h.pos.Position = Vector3.new(goal.X, p.Y, goal.Z)
        return ang
    end

    local function alignDriveStep(h, tr, ax, az, bx, bz, dt)
        local p = tr:GetPivot().Position
        local A = Vector3.new(ax, 0, az)
        local B = Vector3.new(bx, 0, bz)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 0.5 then return end
        local dir = leg / legLen
        local along = (Vector3.new(p.X, 0, p.Z) - A):Dot(dir)
        -- ▸ the aim is NEVER clamped onto the leg end: pinning it there made the
        --   aim point collapse onto the tractor over the last 14 studs, and the
        --   moment it drifted past the end the "steer to the aim" angle flipped
        --   toward 180° — a visible wiggle/twitch right where a row ends. It
        --   now runs past the end (and never behind the leg start), so the
        --   heading target stays steady all the way in.
        local aim = A + dir * math.max(along + ALIGN_AIM, ALIGN_AIM)
        alignDriveAim(h, tr, aim.X, aim.Z, dt)
    end

    -- ▸ ONE STRAIGHT LEG ON THE ALIGN MOVER (user: "we got to change the way
    --   the harvester moves on the feild. it needs to stay on the line not
    --   wiggle everywhere"): the same pure-pursuit mover that drives to the
    --   field now drives the sweep — one leg at a time, so a stuck corner
    --   only costs that leg. Returns true = arrived, false = gave up (caller
    --   drives this leg with keys), nil = user stopped. `stats` collects how
    --   far off the line it got and how often it crossed it, so a run says
    --   whether it really held the line.
    local function alignDriveLeg(tr, from, goal, tol, stats, speed)
        local A = Vector3.new(from.X, 0, from.Z)
        local B = Vector3.new(goal.X, 0, goal.Z)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 1 then return true end
        local dir = leg / legLen
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        local h = alignDriveStart(tr)
        if not h then return false end
        -- ▸ FIELD LEGS RUN AT THE SWATH SPEED, not the travel speed (user: "it's
        --   twitching the wheels a lot when working on the field"). The mover
        --   was allowed its full 24 studs/s travel speed with a plow in the
        --   dirt — 2.4× the harvester's swath speed — so the implement snagged
        --   the soil, the chassis hopped and the front wheels buzzed. A leg now
        --   uses the caller's speed (10 studs/s for passes); travel legs still
        --   use ALIGN_MAXVEL.
        h.cap = speed or ALIGN_MAXVEL
        local mark, markT = tr:GetPivot().Position, os.clock()
        local deadline = os.clock() + 8 + legLen / 6
        local t0 = os.clock()
        local ok, prevSide = false, nil
        while os.clock() < deadline do
            if stopping() then alignDriveStop(h) return nil end
            -- the 1-second harvest watch: a full tank stops the leg here
            if driveWatchTick(tr) then break end
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
    -- forward declaration: the route preview lives with the other visual debug
    -- helpers further down, but driveRoute needs it here
    local dbgRoute, dbgRouteClear

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
            log(string.format("path: %d point(s) (corners are arcs), %d obstacle part(s) mapped (tool margin %d)",
                #legs, info, hull))
        end
        -- draw the route we are about to follow (studs on the real path)
        dbgRoute(legs, startPos.Y + 0.9)
        local dbgClock = os.clock()
        local useKeys = driveLegKeys ~= nil
        -- ▸ the HARVESTER never uses the align mover or WASD here either: the
        --   A* path already avoids the obstacles, and the physics drivers
        --   kept failing to execute it (live log: "align driver stalled",
        --   "sharp turn (100°)", legs accepted 600–1 170 studs short — 15 s
        --   wasted per leg, and the harvester never reached the field). Its
        --   route legs are tweened instead, at a faster rate than the 10
        --   studs/s swath speed because these legs are travel, not harvest.
        local TRAVEL_TWEEN_SPEED = 60
        local isHarvestRide = isHarvester(tr, impl)
        local ah, alignWhy
        if isHarvestRide then
            -- NO align constraints at all on a tweened ride: AlignPosition
            -- would pin the harvester where it started and fight every
            -- PivotTo step of the tween.
            log(string.format("route: tween driver for the harvester (%d studs/s travel, %d studs/s swath)",
                TRAVEL_TWEEN_SPEED, HARVEST_TWEEN_SPEED))
        else
            ah, alignWhy = alignDriveStart(tr)
        end
        local useAlign = ah ~= nil
        if useAlign then
            log(string.format("route: ALIGN driver on (mass %.0f, maxvel %d, aim %d, resp %d/%d) — physics follows the line",
                ah.mass, ALIGN_MAXVEL, ALIGN_AIM, ah.pos.Responsiveness, ah.ori.Responsiveness))
        elseif not isHarvestRide then
            log("route: align driver unavailable (" .. tostring(alignWhy) .. ") — driving with keys")
        end
        local alignClock, alignMark = os.clock(), tr:GetPivot().Position
        -- telemetry: measured with the game's own positions, not our intent —
        -- the first run then says WHICH number is wrong instead of guessing
        local teleClock = os.clock()
        local teleMax, teleSum, teleN = 0, 0, 0
        local li, lastPlan, pass = 2, 0, 0
        -- ▸ ARC LENGTH + PURE PURSUIT (user: "use curves not squares"). Every
        --   point is measured along the path, and the driver aims at the point
        --   LOOKAHEAD studs FURTHER ALONG IT instead of at the next leg end.
        --   With the Bézier corner samples that turns a squared corner into one
        --   continuous arc: the aim point slides around the corner while the
        --   nose eases in, and the lookahead grows with speed so a fast leg is
        --   entered smoothly instead of snapped into.
        local cum = {}
        local function remeasure()
            cum = { 0 }
            for i = 2, #legs do
                local dx, dz = legs[i][1] - legs[i - 1][1], legs[i][2] - legs[i - 1][2]
                cum[i] = cum[i - 1] + math.sqrt(dx * dx + dz * dz)
            end
        end
        remeasure()
        local function pointAt(s)
            local last = #legs
            if last < 2 or s <= 0 then return legs[1][1], legs[1][2] end
            if s >= cum[last] then
                -- keep the aim moving past the goal (up to 30 studs) instead of
                -- parking it on the final point: a collapsed aim is a twitch
                local ax, az = legs[last - 1][1], legs[last - 1][2]
                local bx, bz = legs[last][1], legs[last][2]
                local dx, dz = bx - ax, bz - az
                local l = math.sqrt(dx * dx + dz * dz)
                if l < 1e-3 then return bx, bz end
                local over = math.min(s - cum[last], 30)
                return bx + dx / l * over, bz + dz / l * over
            end
            local lo, hi = 1, last
            while hi - lo > 1 do
                local mid = math.floor((lo + hi) / 2)
                if cum[mid] <= s then lo = mid else hi = mid end
            end
            local seg = cum[lo + 1] - cum[lo]
            local t = seg > 1e-6 and (s - cum[lo]) / seg or 0
            return legs[lo][1] + (legs[lo + 1][1] - legs[lo][1]) * t,
                legs[lo][2] + (legs[lo + 1][2] - legs[lo][2]) * t
        end
        -- ▸ CURVATURE AWARE PURSUIT (research: with a speed-only lookahead pure
        --   pursuit CUTS THE INSIDE of every corner — "lookahead too far =
        --   corner cutting, too near = oscillation", and every practical fix
        --   shrinks the lookahead as curvature rises). Three samples ~8 studs
        --   apart give the turn rate in rad per stud at s.
        local function curvatureAt(s)
            local ax, az = pointAt(s)
            local bx, bz = pointAt(s + 4)
            local cx, cz = pointAt(s + 8)
            local ux, uz = bx - ax, bz - az
            local vx, vz = cx - bx, cz - bz
            local lu = math.sqrt(ux * ux + uz * uz)
            local lv = math.sqrt(vx * vx + vz * vz)
            if lu < 1e-3 or lv < 1e-3 then return 0 end
            local cosang = math.clamp((ux * vx + uz * vz) / (lu * lv), -1, 1)
            return math.acos(cosang) / ((lu + lv) / 2)
        end
        -- ▸ SPEED PROFILE (forward/backward pass): the fastest we may be at s is
        --   set by the sideways grip through the tightest corner within braking
        --   distance (v² = a_lat / κ), and we may be faster HERE only if we can
        --   still brake down to it: v ≤ √(vκ² + 2·a_brake·d). That is what
        --   stops the "arrive too hot, overshoot, jam" pattern.
        local ALIGN_LAT = 42   -- studs/s² of sideways grip
        local ALIGN_BRAKE = 55 -- studs/s² of braking
        local function speedLimitAt(s)
            local vmax = ALIGN_MAXVEL
            for d = 0, 40, 5 do
                local k = curvatureAt(s + d)
                local vk = math.sqrt(ALIGN_LAT / math.max(k, 0.008))
                vmax = math.min(vmax, math.sqrt(vk * vk + 2 * ALIGN_BRAKE * d))
            end
            return math.max(vmax, 6)
        end
        -- nearest point on the path, searched in a window around the cursor so
        -- a path that crosses itself cannot steal the cursor
        local function project(px, pz, hint)
            if #legs < 2 then return 0, 0, hint end
            local bestD, bestS, bestI = math.huge, 0, hint
            local from = math.max(1, hint - 2)
            local to = math.min(#legs - 1, hint + 30)
            for i = from, to do
                local ax, az = legs[i][1], legs[i][2]
                local dx, dz = legs[i + 1][1] - ax, legs[i + 1][2] - az
                local ll = dx * dx + dz * dz
                local t = 0
                if ll > 1e-6 then
                    t = math.clamp(((px - ax) * dx + (pz - az) * dz) / ll, 0, 1)
                end
                local ex, ez = px - (ax + dx * t), pz - (az + dz * t)
                local dd = math.sqrt(ex * ex + ez * ez)
                if dd < bestD then
                    bestD, bestS, bestI = dd, cum[i] + t * math.sqrt(ll), i + 1
                end
            end
            return bestS, bestD, bestI
        end
        local spdPrev, spdClock, spdEma = tr:GetPivot().Position, os.clock(), 0
        local deadline = os.clock() + 120
        while os.clock() < deadline do
            pass += 1
            if stopping() then alignDriveStop(ah) dbgRouteClear() return nil end
            -- ▸ the tank filled ON THE WAY: stop the route here and report
            --   arrival-ish, so the sweep's own check sells before the route
            --   plan wastes seconds driving a full harvester around.
            if driveWatchTick(tr) then
                if ah then alignDriveStop(ah) dbgRouteClear() end
                log("route: stopping here — the harvester is full, selling next")
                return true, pass
            end
            local p = tr:GetPivot().Position
            -- stuck probe: 3 s without 3 studs of progress = the constraint is
            -- losing to the game's controller (or we are jammed) — hand back
            -- to the key driver instead of grinding
            if useAlign then
                if (p - alignMark).Magnitude >= 3 then
                    alignMark, alignClock = p, os.clock()
                elseif os.clock() - alignClock > 3 then
                    useAlign = false
                    alignDriveStop(ah) dbgRouteClear()
                    log("align driver stalled (3 s without progress) — falling back to keys")
                end
            end
            -- re-plan ~once a second: parked tools shift around, and the
            -- fresh A* always re-picks the quickest current route
            if os.clock() - lastPlan > 1 then
                lastPlan = os.clock()
                local newLegs, n = pathfindAround(p, goal, tr, impl, hull)
                if stopping() then alignDriveStop(ah) dbgRouteClear() return nil end
                if newLegs then
                    if info ~= n then
                        log(string.format("re-routed: %d point(s), %d obstacle part(s) mapped", #newLegs, n))
                    end
                    legs, info = newLegs, n
                    remeasure()
                    -- follow the FRESH path from here (legs[1] = now). On a
                    -- failed replan the old legs keep their old first point,
                    -- so the cursor must not be reset to it.
                    li = 2
                    -- redraw the preview at most every 3 s: a full clear and
                    -- redraw of ~120 studs every second is a visible hitch on
                    -- mobile, and the path barely moves in one second
                    if os.clock() - dbgClock > 3 then
                        dbgRoute(legs, p.Y + 0.9)
                        dbgClock = os.clock()
                    end
                else
                    log("re-plan failed (" .. tostring(n) .. ") — keeping the last path")
                end
            end
            if useAlign then
                -- ▸ PURE PURSUIT on the whole path.
                local now = os.clock()
                local dt2 = now - spdClock
                if dt2 > 0.05 then
                    spdEma = spdEma * 0.6 + ((p - spdPrev).Magnitude / dt2) * 0.4
                    spdPrev, spdClock = p, now
                end
                local s, off, seg = project(p.X, p.Z, li)
                li = math.min(seg, #legs)
                teleMax = math.max(teleMax, off)
                teleSum, teleN = teleSum + off, teleN + 1
                if cum[#legs] - s <= 8 then
                    local dg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                    if dg <= 12 then
                        log(string.format("route: arrived in %d ticks — worst line error %.1f studs",
                            pass, teleMax))
                        alignDriveStop(ah) dbgRouteClear()
                        return true, pass
                    end
                end
                -- ▸ lookahead: grows with speed BUT SHRINKS IN THE CORNERS
                --   (was speed-only → it aimed 30 studs past a corner and cut
                --   the inside of it). 0.10 rad/stud is a ~90° corner over
                --   ~15 studs: there the lookahead drops to ~45% of nominal.
                local kNow = curvatureAt(s)
                local Ld = math.clamp(
                    (10 + spdEma * 0.45) * (1 - 0.55 * math.clamp(kNow / 0.10, 0, 1)),
                    8, 30)
                -- ▸ and the SPEED comes from the corner ahead, not from hope
                ah.cap = speedLimitAt(s)
                local axp, azp = pointAt(s + Ld)
                if now - teleClock >= 1 then
                    local nose = seat and seat.CFrame.LookVector or Vector3.new(0, 0, 1)
                    local want = Vector3.new(axp - p.X, 0, azp - p.Z)
                    local n2 = Vector3.new(nose.X, 0, nose.Z)
                    local ang = 0
                    if n2.Magnitude > 0.1 and want.Magnitude > 0.5 then
                        ang = math.deg(math.acos(math.clamp(n2.Unit:Dot(want.Unit), -1, 1)))
                    end
                    log(string.format("route: line %.1f studs off · %.0f studs/s · nose %.0f° off · point %d/%d",
                        teleSum / math.max(teleN, 1), spdEma, ang, li, #legs))
                    teleClock = now
                    teleSum, teleN = 0, 0
                end
                alignDriveAim(ah, tr, axp, azp, 0.12)
            elseif isHarvestRide then
                local g = legs[math.min(li, #legs)]
                local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(g[1], 0, g[2])).Magnitude
                if d <= 6 then
                    if li < #legs then
                        li += 1
                        g = legs[li]
                    else
                        local dg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                        if dg <= 8 then
                            alignDriveStop(ah) dbgRouteClear()
                            return true, pass
                        end
                    end
                end
                -- one A* leg per tween: land on the waypoint, the loop then
                -- advances the cursor exactly as the driven path does
                local okT = tweenDriveLeg(tr, p, Vector3.new(g[1], p.Y, g[2]), TRAVEL_TWEEN_SPEED)
                if okT == nil then alignDriveStop(ah) dbgRouteClear() return nil end
                local np = tr:GetPivot().Position
                local dgNow = (Vector3.new(np.X, 0, np.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                if li >= #legs and dgNow > 8 then
                    -- last waypoint and still not on the goal: accept it. A
                    -- tween back to the same point returns instantly, which
                    -- would spin this loop with no yield at all.
                    log(string.format("route: tween accepted %.0f studs short of the goal", dgNow))
                    return true, pass
                end
                task.wait(0.05) -- always yield, even on a zero-length leg
            else
                local g = legs[math.min(li, #legs)]
                local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(g[1], 0, g[2])).Magnitude
                if d <= 6 then
                    if li < #legs then
                        li += 1
                        g = legs[li]
                    else
                        local dg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                        if dg <= 8 then
                            alignDriveStop(ah) dbgRouteClear()
                            return true, pass
                        end
                    end
                end
                if useKeys then
                    local res = driveLegKeys(tr, seat, p, Vector3.new(g[1], p.Y, g[2]), 6)
                    if res == nil then alignDriveStop(ah) dbgRouteClear() return nil end
                    -- a leg cut short by the harvest watch is not "keys failed"
                    if res == false and not watchHit then
                        useKeys = false
                        log("keys didn't drive to the field — falling back to glide")
                    end
                end
                if not useKeys then
                    glideTractor(tr, Vector3.new(g[1], p.Y, g[2]))
                end
            end
            task.wait(0.12)
        end
        alignDriveStop(ah) dbgRouteClear()
        local p = tr:GetPivot().Position
        local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
        if d <= 8 then return true, pass end
        return false, "still " .. math.floor(d) .. " studs short"
    end

    -- the corner of a field's plate to aim at (4 studs inside), from wherever
    -- the vehicle is now — the same point driveToField uses, so the harvester
    -- can ARC there instead of pathfinding
    local function fieldCornerTarget(field, fromPos)
        local baseCF, baseSize = fieldFrame(field)
        if not baseCF then return nil end
        local c = baseCF.Position
        local rx = Vector3.new(baseCF.RightVector.X, 0, baseCF.RightVector.Z).Unit
        local rz = Vector3.new(baseCF.LookVector.X, 0, baseCF.LookVector.Z).Unit
        local p0 = fromPos - c
        return c
            + rx * math.max(baseSize.X / 2 - 4, 2) * (p0:Dot(rx) >= 0 and 1 or -1)
            + rz * math.max(baseSize.Z / 2 - 4, 2) * (p0:Dot(rz) >= 0 and 1 or -1)
    end

    local function driveToField(tr, field, seat, impl)
        local goal = fieldCornerTarget(field, tr:GetPivot().Position)
        if not goal then return false, "no bounds" end
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
    --   The trip, stage by stage (user's latest: "you can just take the box,
    --   talk to the guy, then buy it like that. no need to place it on the
    --   countser"): find the crate labelled with that seed → tp to it → E
    --   (carry) → tp to the owner STILL HOLDING IT → F (buy; the menu's Buy
    --   button is called through its OWN handlers if there is one — never a
    --   mouse, never a spoofed remote) → VERIFY with the balance → tp to the
    --   seeder → V (FillSeeder) → VERIFY the seeder's seed count. No put-down,
    --   no counter. Every stage logs the game's own context-action list, and a
    --   miss logs the shelf / the menu's buttons, so nothing fails silently.
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
        setStage("searching the town for a " .. tostring(seedName) .. " crate")
        log("seed crate: searching the town for a " .. tostring(seedName) .. " crate…")
        -- ▸ SHELVES FIRST (live dump): every seed crate in the game sits in
        --   Objects.DraggableObjects or GameplayVisuals.LockedDraggables —
        --   60 of them, a couple of hundred instances total. Walking ALL of
        --   workspace (16k+ instances) before anything printed was the
        --   silent multi-second pause that made the shop trip look dead;
        --   the whole-map walk is now only the fallback for a layout the
        --   dump hasn't shown.
        local function scanCrates(container)
            if not container then return end
            for _, d in ipairs(container:GetDescendants()) do
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
        end
        local objFolder = workspace:FindFirstChild("Objects")
        local visFolder = workspace:FindFirstChild("GameplayVisuals")
        scanCrates(objFolder and objFolder:FindFirstChild("DraggableObjects"))
        scanCrates(visFolder and visFolder:FindFirstChild("LockedDraggables"))
        if next(models) == nil then
            log("seed crate: neither shelf folder had a crate — walking all of workspace as a fallback")
            scanCrates(workspace)
        end
        for m in pairs(tagged) do models[m] = true end
        -- ▸ DIAGNOSTIC (user: "it isnt going to the crate"): the walk itself
        --   says what it saw, so a streamed-out shelf or an unreadable tag is
        --   visible in the console instead of guessed at.
        local nTag, nMod = 0, 0
        for _ in pairs(tagged) do nTag += 1 end
        for _ in pairs(models) do nMod += 1 end
        log(string.format("seed crate: scanned %d instance(s) (shelves first) — %d crate-like model(s), %d with a seed tag",
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
        setStage("shop trip: tp to FarmCo")
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
        setStage("shop trip: tp to the " .. tostring(seedName) .. " crate")
        tpChar(hit.pos)
        task.wait(1.0)
        if stopping() then return false end
        local acts = contextActions()
        log("seed crate: E at the crate to pick it up — the game offers: "
            .. (acts and (#acts > 0 and table.concat(acts, " · ") or "nothing") or "unreadable"))
        setStage("shop trip: picking the crate up (E)")
        if not carryCrate("seed crate") then
            log("seed crate: couldn't pick it up after 3 tries — stopping the shop trip here (nothing bought)")
            return false
        end
        -- ▸ STAGE 2 — TALK TO THE GUY WITH THE CRATE STILL IN HAND (user: "you
        --   can just take the box, talk to the guy, then buy it like that. no
        --   need to place it on the countser"). The put-down (X) stage is gone.
        if oPart then
            setStage("shop trip: taking the crate to the FarmCo Owner")
            tpChar(oPart.Position)
            task.wait(1.2)
            if stopping() then return false end
            root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or root
            local cPart = hit.m:FindFirstChildWhichIsA("BasePart", true)
            local cD = cPart and (cPart.Position - root.Position).Magnitude or -1
            log(string.format("seed crate: at the %s — the crate is %.0f studs away (%s), still in hand",
                owner.Name, cD,
                cD >= 0 and (cD < 15 and "it came with us" or "it did NOT follow the tp")))
        else
            log("seed shop: the FarmCo Owner NPC isn't in the workspace yet — pressing F anyway")
        end
        -- open the owner's menu
        local before = coinBalance()
        setStage("shop trip: talking to the FarmCo Owner (F)")
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
                -- ▸ A CLOSED SCREEN GUI IS NOT ON SCREEN. This only checked
                --   Visible, and a ScreenGui is not a GuiObject — so the seed
                --   row and the Buy/Close buttons were happily matched inside
                --   a menu that was never opened (StoreMenu/SellMenu/TradeMenu
                --   all live under GuiViews with Enabled=false), the click
                --   went to an invisible button, and the purchase silently did
                --   nothing.
                if p:IsA("LayerCollector") and not p.Enabled then return false end
                if p:IsA("GuiObject") and not p.Visible then return false end
                p = p.Parent
            end
            return true
        end
        -- ▸ THE REAL BUY UI (user's screenshot of the FarmCo menu): talking to
        --   the owner with the crate in hand opens a CONFIRM POPUP — "Are you
        --   sure you want to buy 1 item?", the item tile with its price and ONE
        --   green "Purchase" button (qty is already 1). There is no list to
        --   choose from and nothing to put on a counter: the popup is already
        --   for the crate in hand, so the only action is Purchase.
        -- ▸ GUARD + CLICK LOOP REWRITTEN (user: "in the menu to buy the seed it
        --   does not buy the seed it just stares at the menu and does not
        --   purchase it"). The old guard refused to click unless the popup TEXT
        --   contained the seed's name — but the real confirm popup says only
        --   "Are you sure you want to buy 1 item?" with the crate as an ICON.
        --   So it found the right button, logged it, and never pressed it.
        --   Now: the popup may name nothing (it is for the crate IN HAND — that
        --   is the whole flow), and the guard only refuses when it names a
        --   DIFFERENT seed.
        local want = (seedName:lower():gsub("%s+", ""))
        local function otherSeedIn(text)
            local flat = tostring(text or ""):lower():gsub("%s+", "")
            if flat:find(want, 1, true) then return nil end
            for name in pairs(seedIdOf) do
                local n = name:lower():gsub("%s+", "")
                if #n > 2 and flat:find(n, 1, true) then return name end
            end
            return nil
        end
        -- never click these, whatever the menu calls them
        local function forbidden(t)
            for _, bad in ipairs({ "robux", "premium", "gems", "gem", "sell",
                "cancel", "close", "back", "exit" }) do
                if t:find(bad, 1, true) then return true end
            end
            return false
        end
        local function isPurchase(t)
            return t:find("purchase", 1, true)
                or t:find("confirm", 1, true)
                or t:find("buy", 1, true)
                or t:find("^yes") ~= nil
                or t:find("^ok") ~= nil
        end
        -- every VISIBLE button of the open menu + its readable text. `top` is
        -- GuiViews normally, but the whole PlayerGui when the popup is parented
        -- somewhere else (a menu that never shows up in the GuiViews tree used
        -- to read as "nothing on screen" while it sat right there).
        local function harvestMenu(top)
            local out, labels = {}, {}
            for _, g in ipairs(top:GetDescendants()) do
                local shown = true
                local p = g
                while p and p ~= top do
                    if p:IsA("LayerCollector") and not p.Enabled then shown = false break end
                    if p:IsA("GuiObject") and not p.Visible then shown = false break end
                    p = p.Parent
                end
                if shown then
                    if g:IsA("GuiButton") then
                        out[#out + 1] = {
                            btn = g,
                            text = ((guiTextOf(g) .. " " .. g.Name):lower()),
                        }
                    elseif g:IsA("TextLabel") then
                        local tx = guiTextOf(g)
                        if tx and tx ~= "" then labels[#labels + 1] = tx end
                    end
                end
            end
            return out, labels
        end
        -- a NEW crate of the chosen seed next to us = the purchase landed. It
        -- is a COUNT, not a "is one there": the crate we carried INTO the shop
        -- is already next to us, so presence proves nothing — an increase does.
        local function crateCount()
            local objects = workspace:FindFirstChild("Objects")
            local dobjs = objects and objects:FindFirstChild("DraggableObjects")
            if not dobjs or not root then return 0 end
            local n = 0
            for _, m in ipairs(dobjs:GetChildren()) do
                local p = m:FindFirstChildWhichIsA("BasePart", true)
                if p and (p.Position - root.Position).Magnitude < 80 then
                    local s2 = crateSeedType(m)
                    if s2 and s2:lower() == seedName:lower() then n += 1 end
                end
            end
            return n
        end

        local buttons, labels
        for _ = 1, 12 do -- up to ~6 s: the popup animates in
            if stopping() then return false end
            buttons, labels = harvestMenu(views)
            if #buttons == 0 then buttons, labels = harvestMenu(pg) end
            if #buttons > 0 then break end
            task.wait(0.5)
        end
        local popupText = (labels and #labels > 0)
            and table.concat(labels, " | ") or "nothing readable"
        if #buttons == 0 then
            log("seed shop: no menu buttons are on screen — the visible text was: " .. popupText)
            log("seed shop: nothing clicked (check the shop by hand once)")
            return false
        end
        log("seed shop: buy popup — " .. popupText)
        -- ▸ only judge a DIALOG by its text. A store LIST names every seed in
        --   the game, so "it names another seed" means nothing there — the
        --   length test keeps a catalogue from being mistaken for a wrong popup.
        local wrong = #popupText < 220 and otherSeedIn(popupText) or nil
        if wrong then
            log(string.format("seed shop: ⚠ that popup is for '%s', not '%s' — NOT clicking Purchase",
                wrong, seedName))
            return false
        end

        -- ▸ CLICK LOOP: up to 3 attempts, RE-READING the menu each time. The
        --   Purchase button is clicked with every Click-handler the game itself
        --   connected (no mouse events, no remotes). If the popup is one of
        --   those "pick the tile first" menus, attempt 2 finds the Purchase
        --   button the first click revealed — that is why the menu is re-read.
        local bought, clickedAny = false, false
        local after, box, lastBtns
        local cratesBefore = crateCount()
        setStage("shop trip: waiting for the " .. tostring(seedName) .. " purchase to land")
        for attempt = 1, 3 do
            if stopping() then return false end
            local btns, lb = harvestMenu(views)
            if #btns == 0 then btns, lb = harvestMenu(pg) end
            lastBtns = btns
            if #btns == 0 then break end
            -- a tile click can change what the popup is FOR: re-judge it
            local txt = (lb and #lb > 0) and table.concat(lb, " | ") or ""
            if #txt > 0 and #txt < 220 then
                local bad = otherSeedIn(txt)
                if bad then
                    log(string.format("seed shop: ⚠ the popup now says '%s', not '%s' — stopping before a wrong buy",
                        bad, seedName))
                    return false
                end
            end
            local target, why
            for _, b in ipairs(btns) do
                if not forbidden(b.text) and isPurchase(b.text) then
                    target, why = b, "the Purchase button"
                    break
                end
            end
            if not target then
                for _, b in ipairs(btns) do
                    if not forbidden(b.text) and b.text:find(want, 1, true) then
                        target, why = b, "the " .. seedName .. " tile"
                        break
                    end
                end
            end
            if not target then
                for _, b in ipairs(btns) do
                    if not forbidden(b.text) then
                        target, why = b, "the first usable control"
                        break
                    end
                end
            end
            if not target then break end
            clickedAny = true
            log(string.format("seed shop: clicking %s ('%s') — %s%s",
                target.btn:GetFullName(), guiTextOf(target.btn), why,
                attempt > 1 and (" (attempt " .. attempt .. ")") or ""))
            local called = invokeHandlers(target.btn)
            if not called then
                log("seed shop: no readable handler on it — trying firesignal / :Activate()")
                pcall(function()
                    if type(firesignal) == "function" then
                        firesignal(target.btn.MouseButton1Click)
                    end
                end)
                pcall(function() target.btn:Activate() end)
            end
            -- did that ONE click land? poll the balance, then the crate count
            for _ = 1, 5 do
                if stopping() then return false end
                task.wait(0.4)
                after = coinBalance()
                if before and after and after < before then bought = true break end
                local n = crateCount()
                if n > cratesBefore then
                    bought = true
                    box = string.format("%s crate count %d → %d", seedName, cratesBefore, n)
                    break
                end
            end
            if bought then break end
        end
        -- final settle + one last read of both signals
        task.wait(0.4)
        after = after or coinBalance()
        if not box and crateCount() > cratesBefore then
            box = string.format("%s crate count %d → %d", seedName, cratesBefore, crateCount())
            bought = true
        end
        if not bought and clickedAny then
            log("seed shop: the menu is still showing after " .. (lastBtns and #lastBtns or 0)
                .. " visible control(s) — nothing bought.")
            local names = {}
            for _, b in ipairs(lastBtns or {}) do
                names[#names + 1] = string.format("'%s'", guiTextOf(b.btn))
            end
            log("seed shop: buttons on screen were: " .. table.concat(names, ", "))
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
        if not closed then
            -- the confirm popup closes itself on Purchase, so only press F when
            -- a menu is actually still on screen (F would re-open the owner)
            local stillOpen = false
            for _, g in ipairs(views:GetDescendants()) do
                if g:IsA("GuiButton") and isShown(g) then stillOpen = true break end
            end
            if stillOpen then pressKey(Enum.KeyCode.F)
            else log("seed shop: the popup closed itself — no F needed") end
        end
        task.wait(0.6)
        if not bought then
            log("⚠ the " .. seedName .. " purchase could NOT be confirmed (the balance didn't move) — check the shop by hand")
            return false
        end
        log("✅ " .. seedName .. " bought (balance " .. tostring(before) .. " → " .. tostring(after) .. ")")
        -- ▸ STAGE 3 — the crate is ALREADY IN HAND (nothing was put down), so
        --   only pick something up if the game swapped it out during the buy
        if carrying() then
            log("seed crate: still carrying the crate — straight to the seeder")
        elseif not carryCrate("bought crate") then
            log("seed crate: the bought crate didn't come to hand — pick it up by hand (E) and the seeder fill is next time")
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
        setStage("shop trip: tp to the seeder to pour the crate in")
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
            log(string.format("✅ seeder now holds %d%s seeds%s — the planting pass takes it from here",
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
        setStage(seated and "getting out of the tractor to go seed shopping"
            or "shop trip: the seeder is empty")
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
        setStage("bringing the seeder out of storage before buying")
        local seederOut = ensureToolNearby(tr, "Planter", "seeder")
        if stopping() then return false end
        if not seederOut then
            log("the seeder couldn't be brought out of storage — not buying a crate it can't be poured into")
            return false
        end
        setStage("shop trip: buying " .. tostring(seedChoice) .. " seeds")
        local bought = buySeedAndFill(seedChoice)
        if stopping() then return false end
        -- ▸ GET BACK IN AND SEED (user's step list ends with it: "get back in
        --   and seed"). The shop trip leaves the character on foot next to
        --   the seeder; walk back, sit down, and the check-back re-enters the
        --   planting stage in THIS run now that the seeder is full.
        setStage("getting back in the tractor after the shop trip")
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
        -- ▸ RETURN TRUE WHEN THE TRIP ACTUALLY WORKED (user's step list ends
        --   with "get back in and seed"): an empty seeder used to return
        --   false no matter what, so the planting pass only ever ran if the
        --   check-back round happened to notice the new seed. If the seeder
        --   really holds seed now, say so — seedPasses then hitches it and
        --   seeds in THIS run, which is the whole point of the trip.
        local held = seederSeeds(tr)
        if held and held > 0 then
            log(string.format("✅ the seeder holds %d seed(s) now — seeding this run (no second run needed)", held))
            return true
        end
        log(bought
            and "the crate is with you but the seeder still reads empty — fill it by hand (V); the planting stage runs on the next run"
            or "no seed was bought this run (the shop lines above say why) — the planting stage can't run until the seeder has seed")
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

    -- ▸ THE HARVEST ROW IS DRIVEN BY REAL W (wiki: "drive forward within the
    --   field to harvest the drop — (W - Keyboard)"). The combine only credits a
    --   harvest while its OWN controller is driving it, and writing
    --   seat.Throttle is overwritten from player input every frame (proven on
    --   the tractor), so this holds W for real: no tween, no seat write, no
    --   position edits — the game drives, physics happens, the crops register.
    --   The only thing the script does is ease the NOSE back onto the line
    --   (small yaw, position untouched) and lift off W before the row end.
    --   Returns true = row done, false = W didn't move it (caller falls back to
    --   the seat throttle), nil = stopped.
    local function keyRow(tr, seat, from, goal)
        local y0 = tr:GetPivot().Position.Y
        local A = Vector3.new(from.X, y0, from.Z)
        local B = Vector3.new(goal.X, y0, goal.Z)
        local leg = B - A
        local legLen = leg.Magnitude
        if legLen < 1 then return true end
        local dir = leg / legLen
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        -- ▸ THE LEG SCALES ITS OWN BRAKE ZONE. A fixed BRAKE = 20 meant W was
        --   never pressed on any leg shorter than ~25 studs — and the skip-row
        --   Ω turns are 8–20 studs — so the harvester sat still, the brake-zone
        --   timer called the leg "done", and every following leg was measured
        --   from a point it never reached. Here: 40 % of the leg, 4–20 studs,
        --   and the tolerance shrinks with it so a turn leg isn't "finished"
        --   5 studs early.
        local BRAKE = math.clamp(legLen * 0.4, 4, 20)
        local ACCEPT = math.clamp(legLen * 0.25, 2, 5)
        local stallP, stallT = tr:GetPivot().Position, os.clock()
        local startP, startT = stallP, stallT
        local turnSince, stalls = nil, 0
        local deadline = os.clock() + 12 + legLen / 4
        releaseDriveKeys()
        claimOwnership(tr)
        while os.clock() < deadline do
            if stopping() then releaseDriveKeys() return nil end
            -- ▸ "full" is its OWN signal. It used to return false, which the
            --   caller read as "holding W moved nothing" and answered with the
            --   seat throttle — driving a full tank around the field.
            if driveWatchTick(tr) then releaseDriveKeys() return "full" end
            local cf = tr:GetPivot()
            local p = cf.Position
            local rel = Vector3.new(p.X, 0, p.Z) - A
            local along, cross = rel:Dot(dir), rel:Dot(perp)
            local remaining = legLen - along
            -- movement bookkeeping happens EVERY tick, whatever phase we are in
            if (p - stallP).Magnitude > 0.6 then
                stallP, stallT = p, os.clock()
            end
            local stoppedFor = os.clock() - stallT
            if remaining <= ACCEPT then break end
            local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
            flat = flat.Magnitude > 0.1 and flat.Unit or dir
            local ang = math.acos(math.clamp(flat:Dot(dir), -1, 1))
            if ang > math.rad(8) then
                -- ▸ KEEP GOING THROUGH THE CORNER (user: "instead of making it
                --   stop at corners just make it keep going on the angle"):
                --   W stays down and the nose is eased around, so the combine
                --   swings through the turn instead of stopping, pivoting and
                --   pulling away. Only the brake zone at the very end of a row
                --   lifts off W.
                stallT = os.clock() -- turning is not a stall
                turnSince = turnSince or os.clock()
                if os.clock() - turnSince > 6 then
                    log("harvester: can't swing onto this row (6 s) — finishing it with the tween")
                    releaseDriveKeys()
                    return "jammed"
                end
                setKey(KEY_W, remaining > BRAKE)
                local turnT = os.clock() - turnSince
                local crossY = flat:Cross(dir).Y -- > 0 = the aim is to our LEFT
                if turnT < 2.0 then
                    -- ▸ REAL STEERING. Rotating the chassis with PivotTo turns
                    --   the BODY, not the velocity: physics keeps the old
                    --   momentum, so the combine slides sideways through the
                    --   corner. Holding W and pressing A/D instead makes the
                    --   game's own controller turn the wheels — the arc is real,
                    --   the harvest keeps counting, and W stays down so it never
                    --   stops (user: "keep going on the angle").
                    setKey(KEY_A, crossY > 0)
                    setKey(KEY_D, crossY < 0)
                else
                    -- keys aren't bringing it round (fence, or the game ignored
                    -- the steer input): finish the swing by hand
                    setKey(KEY_A, false) setKey(KEY_D, false)
                    local step = math.min(ang, math.rad(120) * 0.1)
                    local axis = flat:Cross(dir)
                    local signed = CFrame.fromAxisAngle(Vector3.yAxis,
                        (axis.Y >= 0 and 1 or -1) * step)
                    local nd = signed * flat
                    nd = Vector3.new(nd.X, 0, nd.Z)
                    if nd.Magnitude > 0.01 then
                        tr:PivotTo(CFrame.new(p) * CFrame.lookAt(Vector3.zero, nd.Unit))
                    end
                end
            else
                turnSince = nil
                setKey(KEY_A, false) setKey(KEY_D, false)
                local wantW = remaining > BRAKE
                if wantW then
                    -- W ignored entirely (from a standstill)? fall back
                    if os.clock() - startT > 3 and (p - startP).Magnitude < 1.5 then
                        releaseDriveKeys()
                        return false
                    end
                    -- ▸ STALL = W DOWN AND NO MOVEMENT (user: "now it's stalled
                    --   on the corner"). Back off and retry; after three tries
                    --   hand the row to the tween.
                    if stoppedFor > 1.8 then
                        stalls += 1
                        if stalls > 2 then
                            releaseDriveKeys()
                            log("harvester: jammed on this row (3 tries) — tweening the rest of it")
                            return "jammed"
                        end
                        log(string.format("harvester: stuck for 1.8 s — backing off and retrying (try %d/2)", stalls))
                        setKey(KEY_W, false)
                        setKey(KEY_S, true)
                        task.wait(0.8)
                        setKey(KEY_S, false)
                        stallP, stallT = tr:GetPivot().Position, os.clock()
                    end
                else
                    -- BRAKE ZONE: no W, just coasting. If it has stopped short of
                    -- the row end, that IS the row end — never sit here waiting
                    -- for the deadline (that was the silent stall).
                    if stoppedFor > 1.2 then
                        log("harvester: rolled to a stop before the row end — counting the row as done")
                        break
                    end
                end
                setKey(KEY_W, wantW)
            end
            task.wait(0.1)
        end
        releaseDriveKeys()
        return true
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
            if driveWatchTick(tr) then releaseDriveKeys() return false end
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

    -- ▸ ROUTE PREVIEW: THE REAL PATH, drawn stud by stud (user: "make the
    --   display studs show the real path instead of the blocky path"). The bars
    --   above are the sweep rings, which are straight by design; this draws the
    --   A* route the bot will actually drive — Bézier corner arcs included — as
    --   small studs every 5 studs of path, so what you see is what it follows.
    --   Redrawn at most every 3 s on a re-plan, cleared when the drive ends.
    local routeParts = {}
    function dbgRouteClear()
        for _, s in ipairs(routeParts) do pcall(function() s:Destroy() end) end
        table.clear(routeParts)
    end
    function dbgRoute(legs, y)
        pcall(function()
            dbgRouteClear()
            if not legs or #legs < 2 then return end
            local STEP, MAX = 5, 300
            local function stud(x, z)
                if #routeParts >= MAX then return end
                local s = Instance.new("Part")
                s.Anchored = true
                s.CanCollide = false s.CanQuery = false s.CanTouch = false
                s.CastShadow = false
                s.Material = Enum.Material.Neon
                s.Shape = Enum.PartType.Ball
                s.Size = Vector3.new(0.55, 0.55, 0.55)
                s.Position = Vector3.new(x, y, z)
                s.Color = Color3.fromRGB(255, 190, 60)
                s.Transparency = 0.2
                s.Parent = workspace
                routeParts[#routeParts + 1] = s
            end
            stud(legs[1][1], legs[1][2])
            local since = 0
            for i = 2, #legs do
                local ax, az = legs[i - 1][1], legs[i - 1][2]
                local bx, bz = legs[i][1], legs[i][2]
                local dx, dz = bx - ax, bz - az
                local len = math.sqrt(dx * dx + dz * dz)
                if len > 1e-6 then
                    local d = STEP - since
                    while d <= len do
                        stud(ax + dx / len * d, az + dz / len * d)
                        d += STEP
                    end
                    since = len - (d - STEP)
                end
            end
        end)
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

    -- ▸ THE SELL PAD FOR CROPS. The harvester sells at FARMCO, so the right
    --   pad is the one at FarmCo — not whichever part of
    --   GameplayVisuals.SellArea happens to be biggest or highest (the world
    --   has three sell stores: FarmCo crops, AnimalCo animals, LumberCo
    --   logs). That is how the trip ended up at the wrong spot. Ranking:
    --   1) is it at the CROP store at all (nearest store anchor), 2) how
    --   close to the FarmCo waypoint, 3) a name match (sell/pad/platform/
    --   drop/load/ramp), 4) higher = the elevated platform. Every candidate
    --   is logged with its distance, so a wrong pick is visible instead of
    --   guessed at.
    local STORE_MARKERS = { "FarmCo", "AnimalCo", "LumberStore", "LumberCo" }
    local function storeAnchors()
        local a = {}
        pcall(function()
            local markers = workspace:FindFirstChild("Markers")
            local gotos = markers and markers:FindFirstChild("GotoLocations")
            if not gotos then return end
            for _, nm in ipairs(STORE_MARKERS) do
                local g = gotos:FindFirstChild(nm)
                if g and g:IsA("BasePart") then a[nm] = g.Position end
            end
        end)
        return a
    end

    local function findSellSpots()
        local anchors = storeAnchors()
        local farm = anchors.FarmCo
        local cands = {}
        local function consider(d, what)
            if not (d and d:IsA("BasePart")) then return end
            local n = d.Name:lower()
            local named = n:find("sell", 1, true) or n:find("platform", 1, true)
                or n:find("pad", 1, true) or n:find("drop", 1, true)
                or n:find("load", 1, true) or n:find("ramp", 1, true)
            -- aim at the pad's TOP surface: a platform's centre can sit
            -- below the deck the vehicle has to be standing on
            local top = d.Position + Vector3.new(0, d.Size.Y / 2, 0)
            local nearest, nd = nil, nil
            for nm, ap in pairs(anchors) do
                local dd = (top - ap).Magnitude
                if not nd or dd < nd then nearest, nd = nm, dd end
            end
            cands[#cands + 1] = {
                p = top, what = what, named = named and true or false,
                store = nearest, dist = farm and (top - farm).Magnitude or 1e9,
                y = top.Y, area = d.Size.X * d.Size.Z,
            }
        end
        pcall(function()
            local gv = workspace:FindFirstChild("GameplayVisuals")
            local sa = gv and gv:FindFirstChild("SellArea")
            if not sa then return end
            for _, d in ipairs(sa:GetDescendants()) do
                consider(d, "SellArea." .. d.Name)
            end
        end)
        pcall(function()
            local stores = workspace:FindFirstChild("Stores")
            local dr = stores and stores:FindFirstChild("DropOffs")
            if not dr then return end
            for _, d in ipairs(dr:GetChildren()) do consider(d, "DropOffs." .. d.Name) end
        end)
        -- the crop store's own markers are pads too (a parking-lot style Pad)
        pcall(function()
            local stores = workspace:FindFirstChild("Stores")
            local am = stores and stores:FindFirstChild("AreaMarkers")
            if not am then return end
            for _, d in ipairs(am:GetChildren()) do
                local n = d.Name:lower()
                if n:find("farmco", 1, true) then
                    consider(d, "AreaMarkers." .. d.Name)
                end
            end
        end)
        -- ▸ THE SELL BOARDS (live dump: Markers.GotoLocations.SellBoardSeeds /
        --   SellBoardAnimal / SellBoardLumber). Stores.DropOffs,
        --   SellValueBoards and BoostSellValues are EMPTY in the dump, and the
        --   only AreaMarker is FarmCoParkingLot — so the crop sell pad had no
        --   real candidate and the trip parked at the parking lot, where
        --   nothing sells. The crop board is the harvester's sell point.
        pcall(function()
            local markers = workspace:FindFirstChild("Markers")
            local gotos = markers and markers:FindFirstChild("GotoLocations")
            local g = gotos and gotos:FindFirstChild("SellBoardSeeds")
            if not (g and g:IsA("BasePart")) then return end
            local top = g.Position + Vector3.new(0, g.Size.Y / 2, 0)
            cands[#cands + 1] = {
                p = top, what = "SellBoardSeeds (crop sell board)", named = true,
                board = true, store = "FarmCo",
                dist = farm and (top - farm).Magnitude or 1e9,
                y = top.Y, area = g.Size.X * g.Size.Z,
            }
        end)
        if #cands == 0 then return {} end        -- only pads whose NEAREST store is the crop store; if that filter
        -- empties the list, keep everything rather than refusing to sell
        local atFarm = {}
        for _, c in ipairs(cands) do
            if c.store == nil or c.store == "FarmCo" then
                atFarm[#atFarm + 1] = c
            end
        end
        local pool = #atFarm > 0 and atFarm or cands
        table.sort(pool, function(a, b)
            -- the named crop sell board outranks every unnamed pad
            if a.board ~= b.board then return a.board and true or false end
            -- 40-stud buckets, so tiny differences don't reorder the list
            local ad, bd = math.floor(a.dist / 40), math.floor(b.dist / 40)
            if ad ~= bd then return ad < bd end
            if a.named ~= b.named then return a.named end
            if math.abs(a.y - b.y) > 5 then return a.y > b.y end
            return a.area > b.area
        end)
        local out, lines = {}, {}
        for _, c in ipairs(pool) do
            if #lines < 10 then
                lines[#lines + 1] = string.format("%s @(%.0f,%.0f,%.0f) %.0f studs from FarmCo, y=%.0f%s",
                    c.what, c.p.X, c.p.Y, c.p.Z, c.dist, c.y,
                    c.named and ", named" or "")
            end
            if #out < 4 then
                local near = false
                for _, q in ipairs(out) do
                    if (q.p - c.p).Magnitude < 25 then near = true break end
                end
                if not near then out[#out + 1] = {
                    p = c.p, what = c.what, store = c.store, dist = c.dist,
                    board = c.board } end
            end
        end
        log(string.format("sell pads: %d candidate(s), %d at the crop store — nearest FarmCo first: %s",
            #cands, #atFarm, table.concat(lines, " · ")))
        if out[1] then
            log(string.format("sell pad picked: %s at (%.0f, %.0f, %.0f)",
                out[1].what, out[1].p.X, out[1].p.Y, out[1].p.Z))
        end
        return out
    end

    -- ▸ THE MENU THAT ACTUALLY SELLS (live dump): GuiViews.Menus.SellMenu,
    --   Enabled=false while closed. Its state is readable, so the trip can
    --   TELL whether the pad opened it instead of guessing.
    local function sellMenuGui()
        local ok, m = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local menus = gv and gv:FindFirstChild("Menus")
            return menus and menus:FindFirstChild("SellMenu")
        end)
        if ok then return m end
        return nil
    end

    local function sellMenuOpen()
        local m = sellMenuGui()
        return m ~= nil and m.Enabled == true
    end

    -- the confirm inside the sell menu (user: "a Sell/Confirm button in the
    -- menu" completes the sale — not a key), clicked the way a player clicks
    -- it: call the game's OWN handler, with :Activate() as the fallback the
    -- equipment manager already proved. The old version called the handler
    -- and returned true even when there was NO readable handler, so it could
    -- report a confirm that never happened.
    local SELL_WORDS = { "sell", "confirm", "pour", "unload", "accept", "yes" }
    local CLOSE_WORDS = { "close", "exit", "back", "cancel" }

    local function shownButton(d)
        if not d:IsA("GuiButton") then return false end
        local o = d
        while o and not o:IsA("ScreenGui") do
            if o:IsA("GuiObject") and not o.Visible then return false end
            o = o.Parent
        end
        return true
    end

    local function pressButton(d)
        if not d then return false end
        if invokeHandlers(d) then
            log(string.format("sell menu: called the game's own handler on '%s'", guiTextOf(d)))
            return true
        end
        local ok = pcall(function() d:Activate() end)
        log(string.format("sell menu: no readable handler on '%s' — :Activate() %s",
            guiTextOf(d), ok and "sent" or "failed"))
        return ok
    end

    local function findMenuButton(words)
        local m = sellMenuGui()
        if not (m and m.Enabled) then return nil end
        local hidden
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("GuiButton") then
                local t = (guiTextOf(d) .. " " .. d.Name):lower()
                for _, w in ipairs(words) do
                    if t:find(w, 1, true) then
                        if shownButton(d) then return d end
                        hidden = hidden or d
                        break
                    end
                end
            end
        end
        return hidden
    end

    local function confirmSellMenu()
        return pressButton(findMenuButton(SELL_WORDS))
    end

    local function closeSellMenu()
        local b = findMenuButton(CLOSE_WORDS)
        if b then pressButton(b) task.wait(0.5) end
        return not sellMenuOpen()
    end

    -- ▸ PARK, THEN ACTUALLY SELL (README mechanic: onto the elevated
    --   platform → Q opens the sell menu → E confirms). The old version only
    --   PARKED and watched for 8 s — it pressed nothing at all, so a full
    --   harvester sat on the pad for ever and the sweep carried on filling a
    --   tank that could not fill. The load dropping is still the only judge;
    --   Q/menu/E are just the ways to make it happen.
    local function trySellAt(ride, what)
        local cap0 = harvesterLoad(ride)
        local coins0 = coinBalance()
        task.wait(0.8) -- the pad needs a beat to register the vehicle
        if stopping() then return false end
        local deadline = os.clock() + 16
        local opened, blind = 0, 0
        while os.clock() < deadline do
            if stopping() then return false end
            local cur = harvesterLoad(ride)
            if cur and cap0 and cur < cap0 then
                log(string.format("✅ sold at %s — load %d → %d, coins %s → %s",
                    what, cap0, cur, tostring(coins0), tostring(coinBalance())))
                -- leave the menu closed so the drive back isn't blocked by it
                if sellMenuOpen() then closeSellMenu() end
                return true
            end
            -- 1) Q opens the sell menu (the documented key for the pad)
            if not sellMenuOpen() and opened < 4 then
                opened += 1
                log(string.format("sell pad %s: Q (open the sell menu) — try %d", what, opened))
                pressKey(Enum.KeyCode.Q)
                task.wait(0.9)
                if stopping() then return false end
            end
            -- 2) confirm inside the menu with its own handler (no mouse);
            --    E is the documented confirm key and the fallback when no
            --    menu shows up at all
            if sellMenuOpen() then
                if not confirmSellMenu() then
                    log("sell menu is up but has no sell/confirm button — pressing E")
                    pressKey(Enum.KeyCode.E)
                end
            elseif blind < 3 then
                blind += 1
                log("sell pad " .. what .. ": no menu yet — pressing E (confirm)")
                pressKey(Enum.KeyCode.E)
            end
            task.wait(1.0)
        end
        log(string.format("no sale at %s after 16 s (load %s, coins %s → %s, sell menu %s)",
            what, tostring(cap0), tostring(coins0), tostring(coinBalance()),
            sellMenuOpen() and "OPEN" or "never opened"))
        -- ▸ SAY WHAT THE MENU ACTUALLY OFFERS. If the confirm button is named
        --   something this filter doesn't know, this line names it instead of
        --   leaving the trip a mystery.
        if sellMenuOpen() then
            local m = sellMenuGui()
            local names = {}
            if m then
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("GuiButton") and shownButton(d) and #names < 12 then
                        names[#names + 1] = "'" .. guiTextOf(d) .. "'"
                    end
                end
            end
            log("sell menu buttons on screen: "
                .. (#names > 0 and table.concat(names, " · ") or "none visible"))
        end
        return false
    end

    -- ▸ STRAIGHT HOP (user: "it went to the right spot and sold, just make it
    --   tween or tp there bro"). The sell trip no longer pathfinds: the
    --   harvester is self-propelled and tweened anyway, so it is one smooth
    --   PivotTo slide along the straight line — fast enough to read as a
    --   teleport, still smooth — keeping the heading it had, and it lands on
    --   the pad's own height instead of the field's.
    local SELL_HOP_SPEED = 140 -- studs/s (the arc makes it read as a jump, not a blur)
    -- ▸ THE ARC HOP (user: "make the harvester use arch tween thing to go to and
    --   back from the sell"). A flat slide reads as a teleport glued to the
    --   ground; this lifts the ride on a sine arc — zero at both ends, highest
    --   in the middle — while it covers the distance, so the trip reads as a
    --   jump that lands exactly on the target (Y is the ride's own Y at both
    --   ends, so it never sinks into the ground or the pad).
    local function hopTo(tr, target, speed)
        speed = speed or SELL_HOP_SPEED
        local cf = tr:GetPivot()
        local from = cf.Position
        local to = Vector3.new(target.X, from.Y, target.Z)
        local rot = cf - cf.Position -- heading only, zero position
        local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
        local dist = flat.Magnitude
        if dist < 1 then
            tr:PivotTo(CFrame.new(to) * rot)
            return true
        end
        local dir = flat / dist
        -- the arc grows with the trip but is capped: a 400-stud errand must not
        -- leave the map. 0.25 × distance, 18…70 studs of lift.
        local lift = math.clamp(dist * 0.25, 18, 70)
        log(string.format("arc hop: %.0f studs, lifting %.0f studs", dist, lift))
        local travelled, tick = 0, 0.03
        while travelled < dist do
            if stopping() then return nil end
            travelled = math.min(dist, travelled + speed * tick)
            local t = travelled / dist
            local p = from + dir * travelled
            p = Vector3.new(p.X, from.Y + lift * math.sin(math.pi * t), p.Z)
            tr:PivotTo(CFrame.new(p) * rot)
            task.wait(tick)
        end
        tr:PivotTo(CFrame.new(to) * rot)
        return true
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
        -- the 1-second watch is muted for the whole trip: the tank is STILL
        -- full while driving to the pad, and it must not abort that drive
        sellingNow = true
        -- where it left the rows: the trip back is ONE arc hop to this exact
        -- spot (user: "use arch tween thing to go to and back from the sell")
        local back = ride:GetPivot().Position
        for i, s in ipairs(spots) do
            if stopping() then sellingNow = false return false end
            log(string.format("sell point %d/%d: %s at (%.0f, %.0f) — arc hop, no pathfinding", i, #spots,
                s.what, s.p.X, s.p.Z))
            local ok = hopTo(ride, s.p, SELL_HOP_SPEED)
            if not ok then
                log("couldn't hop to " .. s.what .. " (hop interrupted)")
            elseif trySellAt(ride, s.what) then
                if field and field.Parent then
                    log("arc back to " .. field.Name .. " to finish the harvest")
                    hopTo(ride, back, SELL_HOP_SPEED)
                end
                sellingNow = false
                watchHit = false
                return true
            end
        end
        sellingNow = false
        log("⚠ still full — none of the pads sold the load (the log above says which pad was tried and whether its sell menu opened; if it stayed closed, do the trip once by hand — Q then E — and tell me where the vehicle was parked)")
        return false
    end

    -- ▸ "CHECK IF IT'S FULL, THEN GO SELL" (user) — ONE rule, called at every
    --   point the load can reach the cap: before a field's first leg, before
    --   each leg, before the touch-up, and at the end of the sweep. The old
    --   code only looked at the start of a spiral LEG, so a tank that filled
    --   during the last leg or in the touch-up stayed full until the next
    --   run — which is exactly "it doesn't go and sell".
    --   Returns tried (it WAS full, so the caller counts an attempt) and sold.
    local function harvestSellIfFull(ride, seat, field, note)
        if os.clock() < sellCooldownUntil then return false, false end
        local cur, max = harvesterLoad(ride)
        if not (cur and max and max > 0) then return false, false end
        if cur < max then return false, false end
        log(string.format("harvester is FULL (%d/%d%s) — going to sell", cur, max,
            note and (", " .. note) or ""))
        local sold = sellHarvester(ride, seat, field)
        if not sold then
            sellCooldownUntil = os.clock() + 60
            log("no sale landed — backing off for 60 s instead of hammering the pads (the harvest carries on with the load it has)")
        end
        return true, sold
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
        -- ▸ the HARVESTER gets NO run-out: it turns in place between rows, and
        --   driving 12 studs past the plot is exactly the user's "it goes past
        --   the specified field" — straight through the fence. It now keeps
        --   rolling through the corners (user: "keep going on the angle"), so
        --   the rows end 4 studs INSIDE the plot: that is the room the swing
        --   needs, and the end cells are still entered by the blade.
        local runOut = job.selfPropelled and -4 or 12
        local driveHalf = (alongX and baseSize.X or baseSize.Z) / 2 + runOut
        local rowSpan   = (alongX and baseSize.Z or baseSize.X)
        -- ▸ HEADLAND + SKIP-ROW (research, not guesswork). A combine cannot
        --   turn inside a 10-stud row gap — its turning circle is two to three
        --   passes wide — so the old "concentric laps 10 studs apart" was a
        --   geometrically IMPOSSIBLE path, and every row end jammed because of
        --   it. Real fields are cut the other way round (Biosystems
        --   Engineering 2023: cut the periphery first, it is the headland the
        --   turns need; ICARA 2022: SKIP-ROW the interior when the working
        --   width is narrower than the turning circle): one lap around the
        --   edge, then rows 1,3,5 … and 2,4,6 … so each turn is a wide Ω
        --   across a skipped row instead of a 180 in a 10-stud gap. Rows stay
        --   dead straight; only the turns use the headland band.
        -- ▸ SMALL FIELDS. The old constants could put the turn lane OUTSIDE the
        --   fence when driveHalf < 14, and build two identical rows when the
        --   field was too narrow to hold a headland band (inner = 0). Both are
        --   clamped to the field now.
        local rowHalf = math.max(rowSpan / 2 - 5, 2) -- step half-extent of the headland lap
        local HEAD_BAND = 10             -- one perimeter lap before the rows
        local axRow = math.min(math.max(driveHalf - 12, 8), math.max(driveHalf - 6, 4))
        local lane = math.min(math.max(driveHalf - 4, 10), math.max(driveHalf - 2, 3))
        local inner = math.max(rowHalf - HEAD_BAND, 0)
        local lines = {}
        do
            if inner <= 1 then
                lines[1] = 0 -- too narrow for rows: one centre pass, not two
            else
                local n = math.max(math.floor(inner * 2 / 10 + 0.5), 1)
                for i = 0, n do lines[#lines + 1] = inner - i * (2 * inner / n) end
            end
        end
        local function pt(along, step) -- field-local (along, step) → world
            return c + driveDir * along + stepDir * step
        end
        local st0 = countStages(field)
        local need0 = st0 and whichNeed(job, st0) or nil
        log(string.format("%s: 1 headland lap + %d skip-row pass(es)  (%s)", job.verb, #lines,
            st0 and string.format("%d/%d cells still need %s", need0, st0.total, job.prog)
                or "cell read unavailable"))
        local realDrive -- nil = not probed yet; true = seat driving; false = glide
        -- ▸ THE TANK, BEFORE AND AFTER THIS FIELD (diagnostic): "the harvester is
        --   still not harvesting" needs ONE fact — does the game count the
        --   movement we produce? If the tank is identical after a whole field,
        --   the row drive is what has to change, not the sell trip.
        local tank0 = job.selfPropelled and harvesterLoad(tr) or nil
        if job.selfPropelled then
            log(string.format("harvest: driving %s (EquipmentType=%s) — tank %s",
                tr.Name, tostring(tr:GetAttribute("EquipmentType")), tostring(tank0)))
            if tank0 == nil then
                log("⚠ harvest: the tank isn't readable on " .. tr.Name
                    .. " (no Configurations.Capacity) — the fill and the sell both depend on it")
            end
        end
        local sellTries = 0
        -- field driving starts on the ALIGN mover: binary WASD hunts across the
        -- line, the mover holds it. One fallback per sweep if it gets stuck.
        local useAlign = true
        local lineStats = { worst = 0, flips = 0 }
        local function doLeg(from, goal, tol)
            if stopping() then return nil end
            -- ▸ a harvest leg is DRIVEN on real W (the game only credits a
            --   harvest while its own controller drives — see keyRow). If W
            --   doesn't move it, the seat throttle is tried, and that still
            --   falls back to the plain tween.
            if job.selfPropelled then
                local okT = keyRow(tr, seat, from, goal)
                if okT == nil then return nil end
                if okT == "full" then
                    -- the tank filled mid-leg; the sweep sells and resumes.
                    -- Never treat this as "the keys don't work".
                    return "full"
                end
                if okT == false then
                    log("harvester: holding W moved nothing — trying the seat throttle for this row")
                    okT = throttleRow(tr, seat, from, goal)
                    if okT == nil then return nil end
                elseif okT == "jammed" then
                    okT = tweenDriveLeg(tr, from, goal, HARVEST_TWEEN_SPEED)
                    if okT == nil then return nil end
                end
                return okT
            end
            -- never accept more than half a leg early (the short step onto
            -- the next ring would get cut otherwise)
            tol = math.min(tol or 7, (goal - from).Magnitude * 0.5)
            if useAlign then
                local res = alignDriveLeg(tr, from, goal, tol, lineStats, HARVEST_TWEEN_SPEED)
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
                -- a leg stopped by the harvest watch says nothing about
                -- whether the keys work — never flip the driver on that
                if realDrive == nil and not watchHit then
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
        watchHit = false -- a fresh sweep starts with a clear 1-second watch
        -- ▸ the tank can already be full on arrival (it filled on the way in)
        if job.selfPropelled and sellTries < 6 then
            local tried, sold = harvestSellIfFull(tr, seat, field, "on arrival")
            if tried then sellTries += 1 end
            if sold then at = tr:GetPivot().Position end
        end
        local rel0 = at - c -- sides picked along the PLATE's axes, not world
        local E = rel0:Dot(driveDir) >= 0 and 1 or -1 -- which end I arrived at
        local S = rel0:Dot(stepDir) >= 0 and 1 or -1  -- which step side
        -- each leg entry = { target, tolerance, label }
        local map = {}
        -- 1) THE HEADLAND: one closed lap around the field edge. This is the
        --    band the Ω turns later use, so it is cut first and never again.
        map[#map + 1] = { pt( E * driveHalf,  S * rowHalf), 10, "headland" }
        map[#map + 1] = { pt(-E * driveHalf,  S * rowHalf), 10, "headland" }
        map[#map + 1] = { pt(-E * driveHalf, -S * rowHalf), 10, "headland" }
        map[#map + 1] = { pt( E * driveHalf, -S * rowHalf), 10, "headland" }
        map[#map + 1] = { pt( E * driveHalf,  S * rowHalf), 10, "headland" }
        -- 2) THE INTERIOR, SKIP-ROW: odd lines first, then even, serpentine.
        --    Consecutive rows are then two passes apart, and the turn between
        --    them is a Ω through the headland lane instead of an impossible
        --    180° inside a 10-stud gap.
        local order = {}
        for i = 1, #lines, 2 do order[#order + 1] = i end
        for i = 2, #lines, 2 do order[#order + 1] = i end
        local rdir = E
        for n, idx in ipairs(order) do
            local s = lines[idx]
            -- tol 10 = the end counts as reached 10 studs early, so the turn
            -- starts sooner and the swing stays inside the field
            map[#map + 1] = { pt(-rdir * axRow, s), 10, "row " .. n }
            map[#map + 1] = { pt( rdir * axRow, s), 10, "row " .. n }
            local nxt = order[n + 1]
            if nxt then
                -- Ω: run out into the headland lane, cross to the next row's
                -- line, then the next row pulls back in (its first point).
                map[#map + 1] = { pt(rdir * lane, s), 8, "turn" }
                map[#map + 1] = { pt(rdir * lane, lines[nxt]), 8, "turn" }
            end
            rdir = -rdir
        end
        dbgShow(tr, map, at) -- glowing bars on the field; bright = active leg
        for i, leg in ipairs(map) do
            dbgLeg(i)
            -- full harvester: sell and come back (the user's loop). The spiral
            -- is already computed, so after the trip the sweep just resumes at
            -- THIS leg — from where the vehicle actually is now.
            if job.selfPropelled and sellTries < 6 then
                local tried, sold = harvestSellIfFull(tr, seat, field, "before leg " .. i)
                if tried then sellTries += 1 end
                if sold then at = tr:GetPivot().Position end
            end
            local okLeg = doLeg(at, leg[1], leg[2])
            if job.selfPropelled and watchHit then
                -- ▸ the tank filled DURING this leg (the 1-second watch
                --   stopped it where it was): sell now, then carry on with
                --   the spiral from the vehicle's real position. The cell
                --   strip this leg didn't finish is the touch-up's job.
                watchHit = false
                sellTries += 1
                harvestSellIfFull(tr, seat, field, "mid leg " .. i)
                at = tr:GetPivot().Position
            elseif not okLeg then
                dbgClear() return nil
            else
                -- ▸ MEASURE THE NEXT LEG FROM WHERE THE VEHICLE ACTUALLY IS.
                --   This used to be `at = leg[1]`, the point the leg was aiming
                --   at — but a leg can end early (tank full, brake-zone stop,
                --   tween assist), and every following leg then inherited the
                --   error: directions, lengths, turn lane, all shifted. Reading
                --   the pivot makes each leg honest, whatever ended the last.
                at = tr:GetPivot().Position
                if leg[3] == "headland" and okLeg == true then
                    log("headland lap done — interior rows next (skip-row)")
                end
            end
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
            -- the touch-up drives the whole field again, so it can fill the
            -- tank just as easily as the spiral did
            if job.selfPropelled and sellTries < 6 then
                local tried, sold = harvestSellIfFull(tr, seat, field, "before the touch-up")
                if tried then sellTries += 1 end
                if sold then at = tr:GetPivot().Position end
            end
            local through = 0
            for i, r in ipairs(route) do
                dbgLeg(i)
                local okLeg = doLeg(at, r.goal, 6)
                if job.selfPropelled and watchHit then
                    watchHit = false
                    sellTries += 1
                    harvestSellIfFull(tr, seat, field, "mid touch-up")
                    at = tr:GetPivot().Position
                elseif not okLeg then
                    dbgClear() return nil
                else
                    at = r.goal
                end
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
        -- ▸ END OF THE SWEEP: an empty tank is the honest end state — a full
        --   one just carries the load into the next run.
        if job.selfPropelled and sellTries < 6 then
            harvestSellIfFull(tr, seat, field, "end of the sweep")
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
        if tank0 ~= nil then
            local tank1 = harvesterLoad(tr)
            log(string.format("harvest: tank %s → %s after this field", tostring(tank0), tostring(tank1)))
            if tank1 == tank0 then
                log("⚠ the tank did NOT move while driving the rows — the game isn't counting this movement as harvesting")
            end
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
        setStage("starting the run")
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
            setStage("Equipment Manager: respawning " .. tr.Name)
            local moved = respawnTool(tr.Name, function()
                local t2 = findTractor()
                return t2 and t2:GetPivot().Position or nil
            end, 5)
            if not moved then
                log("respawn didn't bring the tractor back after 5 attempts — not walking 18k studs; spawn it once by hand and start the loop again")
                return
            end
            local tr2, dist2, seat2 = findTractor()
            if tr2 then tr, dist, seat = tr2, dist2 or dist, seat2 end
            log(string.format("✅ tractor is out — %.0f studs away now%s", dist or 0,
                (dist and dist > RESPAWN_RANGE)
                    and " (it spawned at your plot, not next to you — the route drives from here)"
                    or ""))
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
        setStage("checking what work is left on the fields")
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
            setStage(job.verb .. " pass")
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
                        -- ▸ THE HARVESTER ARCS EVERYWHERE (user: "the harvester
                        --   is not using the arc tween bro, make it use it to
                        --   and back"): the self-propelled ride does not need a
                        --   path — it hops, so the trip to the field and every
                        --   sell trip are the same visible arc.
                        local arrived, how
                        if job.selfPropelled then
                            local goal = fieldCornerTarget(m.d, ride:GetPivot().Position)
                            if goal then
                                log("arc hop to the " .. m.d.Name .. " corner")
                                arrived = hopTo(ride, goal, SELL_HOP_SPEED) and true or false
                                how = "arc hop"
                            end
                        end
                        if arrived == nil then
                            arrived, how = driveToField(ride, m.d, rideSeat, impl)
                        end
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

        -- ▸ EVERY STAGE CHECKS ITSELF (user: "make it see if it missed anything
        --   on every stage bro"). When a pass ends the fields are re-read: any
        --   cell still at this stage's own "before" state means a strip was
        --   missed — the sweep's touch-up handles single cubes, this catches a
        --   whole leg that never registered — and the pass runs again. Bounded
        --   to 3 rounds, and it stops when a round changed nothing, so it can
        --   never ping-pong.
        local function needLeft(job)
            local cells, fields = 0, 0
            for _, m in ipairs(findMyFields(tr:GetPivot().Position)) do
                local n = whichNeed(job, countStages(m.d))
                if n and n > 0 then cells += n fields += 1 end
            end
            return cells, fields
        end

        local function passCheck(job, ride, rideSeat)
            local before = needLeft(job)
            if not before or before == 0 then
                log(job.verb .. ": nothing left to do (checked before the pass)")
                return true
            end
            for round = 1, 3 do
                runPass(job, ride, rideSeat)
                if stopping() then return false end
                local after, afields = needLeft(job)
                if not after or after == 0 then
                    log(string.format("✅ %s: every cell is done (%d needed it at the start)",
                        job.verb, before))
                    return true
                end
                log(string.format("%s: %d cell(s) across %d field(s) still need it after round %d — going back",
                    job.verb, after, afields, round))
                if round >= 3 or after >= before then
                    log(string.format("%s: clean-up stops at %d cell(s) — a round changed nothing (check-back retries at the end)",
                        job.verb, after))
                    return false
                end
                before = after
            end
            return false
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
        --   Every stage now re-checks its own misses (passCheck) instead of
        --   leaving them all to the end-of-run check-back.
        passCheck(JOBS[1])
        if stopping() then return end
        -- ▸ steps 7-10: the cultivate pass (Plowed -> Cultivated) — usually
        --   the same field the plow pass just finished
        passCheck(JOBS[2])
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

    -- ▸ WAIT FOR THE CROPS (user: "once it's done seeding i want it to wait
    --   for all the crops to be done growning and then it restarts the loop").
    --   Reads the game's own FieldHelper.GetCells per field — the same read the
    --   harvest pass uses — until NO cell is left in the Seeded stage, i.e.
    --   every planted cell has moved on to a grown stage. Tools are already
    --   back in storage at this point (the run stored them), so the wait is
    --   clean: nothing of ours is standing in the world while the farm grows.
    --   Logs progress once a minute, never fails silently, and returns true
    --   when the crops are done (false = user stopped).
    local growthQuiet = false -- the heartbeat stays out of the way while waiting
    local GROWTH_CAP = 60 * 60 -- give up waiting after an hour
    local GROWTH_SOAK = 90     -- s: never believe "nothing is seeded" sooner
    local function waitForGrowth()
        local t0 = os.clock()
        local lastLog = -60
        -- ▸ A FAILED (OR STILL SETTLING) PLANT PASS USED TO READ AS "GROWN".
        --   `seeded == 0` on the very first poll — planting failed, or the game
        --   hadn't written the stage yet — matched "all done growing", so the
        --   loop restarted instantly, forever, over an empty field. Now "done"
        --   needs either one Seeded cell actually seen during this wait, or the
        --   soak window to pass.
        local sawSeeded = false
        growthQuiet = true
        farmResting = true -- the milk loop's green light (it steps in here)
        setStage("waiting for the crops to grow")
        log("🌱 waiting for the crops to finish growing — reading every field once a minute")
        while true do
            if stopping() then growthQuiet = false farmResting = false return false end
            local ch = LocalPlayer.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            local crops = findMyFields(root and root.Position or Vector3.zero)
            local seeded, grown, total, seen = 0, 0, 0, {}
            for _, m in ipairs(crops) do
                local st = countStages(m.d)
                if st and st.total > 0 then
                    total += st.total
                    seeded += (st.Seeded or 0)
                    grown += (whichNeed(JOBS[4], st) or 0)
                    for name, n in pairs(st) do
                        if name ~= "total" then seen[name] = (seen[name] or 0) + n end
                    end
                end
            end
            local elapsed = os.clock() - t0
            if seeded > 0 then sawSeeded = true end
            if total > 0 and seeded == 0 then
                if sawSeeded or elapsed >= GROWTH_SOAK then
                    log(string.format("🌱 all %d cell(s) are done growing (%d standing) after %dm %ds — restarting the loop",
                        total, grown, math.floor(elapsed / 60), math.floor(elapsed % 60)))
                    growthQuiet = false
                    farmResting = false
                    return true
                end
                -- nothing has read as Seeded yet: this is a failed plant or a
                -- stage the game hasn't written. Wait the soak out, then say so.
                if elapsed - lastLog >= 60 then
                    lastLog = elapsed
                    log(string.format("🌱 no cell reads as Seeded yet (%d cell(s), %d grown) — waiting %ds before believing the field is done",
                        total, grown, math.ceil(GROWTH_SOAK - elapsed)))
                end
            end
            if elapsed - lastLog >= 60 then
                lastLog = elapsed
                local parts = {}
                for name, n in pairs(seen) do parts[#parts + 1] = string.format("%s=%d", name, n) end
                table.sort(parts)
                if total == 0 then
                    log("🌱 no field readable yet — retrying in a minute")
                else
                    log(string.format("🌱 growing: %d/%d cell(s) still Seeded, %d grown · %s · waiting",
                        seeded, total, grown, table.concat(parts, " ")))
                end
            end
            if elapsed >= GROWTH_CAP then
                log("🌱 still not grown after an hour — restarting the loop anyway instead of waiting forever")
                growthQuiet = false
                farmResting = false
                return true
            end
            for _ = 1, 120 do -- 60 s in 0.5 s slices: STOP reacts at once
                if stopping() then growthQuiet = false farmResting = false return false end
                task.wait(0.5)
            end
        end
    end

    -- ▸ the run's wrapper: the whole pass chain above, then the tools go
    --   back in storage ("when it's done"). A wrapper rather than a call at
    --   the end of the body, so EVERY exit of the body — a finished run or
    --   an honest stop — gets the cleanup.
    local function runFarmingLoop()
        -- ▸ HEARTBEAT — the run can no longer go quiet without saying where
        --   it is. NOTE: stopping() is false only on the loop thread itself,
        --   so the watcher uses its own flag.
        local beat = true
        task.spawn(function()
            while beat do
                task.wait(10)
                if beat then
                    log("… still working (" .. runStage .. ")")
                end
            end
        end)
        -- ▸ AN ERROR STILL CLEANS UP. A crash inside the body used to kill
        --   the thread with the toggle frozen ON and every tool left
        --   standing in the world; now the tools go back to storage and the
        --   caller clears the thread id.
        -- ▸ the run no longer ends after one chain: it waits for the crops and
        --   goes again (user: "wait for all the crops to be done growning and
        --   then it restarts the loop"). Every cycle starts with the tools in
        --   storage, so the restart hitches them fresh — the same state a clean
        --   start would have.
        local cycle = 0
        while not stopping() do
            cycle += 1
            if cycle > 1 then
                log("🔁 loop restart #" .. cycle .. " — the crops are done growing")
            end
            local okRun, errRun = pcall(runFarmingBody)
            if not okRun then
                log("⚠ farming loop error: " .. tostring(errRun))
                storeUnusedTools()
                break
            end
            log("run ended — the last stage it reached was: " .. runStage)
            storeUnusedTools()
            if stopping() then break end
            if not waitForGrowth() then break end
        end
        beat = false
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

    -- ▸🩺 DOCTOR REPORT (read-only). After a run of patches where each fix
    --   exposed the next weak spot, the answer is not another feature: too
    --   many bug reports needed a 10-minute run to answer questions the game
    --   can answer in one frame. This prints what exists, where it is,
    --   whether it is stored or in the void, what its Configurations say,
    --   which field plates are readable and which pads exist with their real
    --   store. It CLICKS NOTHING, PRESSES NO KEY AND MOVES NOTHING — reads
    --   only, so it is safe to press in the middle of a run.
    -- ▸ THE UI PART IS BEST-EFFORT. If this library version refuses the
    --   paragraph, the error used to abort the whole GUI build pcall — the
    --   window and tabs appeared with NOTHING in them (no loop toggle, no
    --   settings buttons). Each piece now fails alone and says so, and the
    --   report is reachable without any button at all.
    local doctorReport
    local doctorPara
    local okPanel, errPanel = pcall(function()
        doctorPara = Tabs.Doctor:CreateParagraph("DoctorReport", {
            Title = "Diagnostics",
            Content = "not run yet",
        })
    end)
    if okPanel then
        log("gui: diagnostics panel ok")
    else
        log("doctor: the Diagnostics panel didn't build (" .. tostring(errPanel)
            .. ") — run spudDoctor() in the executor instead")
    end
    -- the dump put stored/desynced equipment ~±100,000 studs out, so a model
    -- this far from the origin is not on the map at all
    local function voidish(p)
        if not p then return false end
        return math.abs(p.X) > 10000 or math.abs(p.Z) > 10000 or p.Y < -1000
    end
    local function equipmentLine(m, here, problem)
        local etype = tostring(m:GetAttribute("EquipmentType") or "?")
        local stored = m:GetAttribute("InStorage") and "stored" or "spawned"
        local okP, p = pcall(function() return m:GetPivot().Position end)
        if not (okP and p) then
            problem(m.Name .. ": position unreadable")
            return string.format("· %s [%s · %s] — position unreadable", m.Name, etype, stored)
        end
        local caps = {}
        pcall(function()
            local conf = m:FindFirstChild("Configurations")
            if not conf then return end
            for _, v in ipairs(conf:GetChildren()) do
                local n = v.Name:lower()
                if v:IsA("IntValue")
                    and (n:find("cap", 1, true) or n:find("seed", 1, true)) then
                    caps[#caps + 1] = string.format("%s=%d", v.Name, v.Value)
                end
            end
        end)
        local flags = {}
        if voidish(p) then
            flags[#flags + 1] = "⚠VOID"
            problem(string.format("%s (%s) is in the void at (%.0f, %.0f, %.0f) — it needs a respawn",
                m.Name, etype, p.X, p.Y, p.Z))
        end
        return string.format("· %s [%s · %s] (%.0f, %.0f, %.0f) · %.0f studs from you%s%s",
            m.Name, etype, stored, p.X, p.Y, p.Z, (p - here).Magnitude,
            #flags > 0 and (" · " .. table.concat(flags, " ")) or "",
            #caps > 0 and (" · " .. table.concat(caps, " ")) or "")
    end
    doctorReport = function(mirror)
        local lines, problems = {}, {}
        local function add(s) lines[#lines + 1] = s end
        local function problem(s) problems[#problems + 1] = s end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local here = (root and root.Position) or Vector3.zero
        add("🩺 DOCTOR — " .. VERSION)
        add(string.format("loop: %s · stage: %s",
            loopThread and "RUNNING" or "idle", tostring(runStage)))
        add(string.format("you: %s at (%.0f, %.0f, %.0f)%s", LocalPlayer.Name,
            here.X, here.Y, here.Z, char and "" or " — NO CHARACTER"))
        if not char then problem("no character — every distance below is measured from 0,0,0") end
        -- vehicles
        local folder = equipmentFolder()
        add("equipment (Objects.Equipment):")
        local nEq = 0
        for _, m in ipairs(folder and folder:GetChildren() or {}) do
            if m:IsA("Model") then
                nEq += 1
                add("  " .. equipmentLine(m, here, problem))
            end
        end
        if nEq == 0 then
            add("  (none — the folder is missing or empty)")
            problem("no equipment models under Objects.Equipment")
        end
        -- fields (mine only, same rule the tour uses: Configurations.Owner)
        add("fields (yours):")
        local nf = 0
        local function considerField(d)
            if not d:IsA("Model") then return end
            local cfg = d:FindFirstChild("Configurations")
            local owner = cfg and cfg:FindFirstChild("Owner")
            if not (owner and owner.Value == LocalPlayer) then return end
            nf += 1
            local cf, sz = fieldFrame(d)
            local ft = cfg:FindFirstChild("FieldType")
            local p = d:GetPivot().Position
            local flat = (Vector3.new(p.X, 0, p.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude
            add(string.format("  · %s [%s] %s · %.0f studs", d.Name,
                ft and tostring(ft.Value) or "?",
                sz and string.format("%.0f×%.0f plate", sz.X, sz.Z) or "NO READABLE PLATE",
                flat))
            if not sz then problem(d.Name .. ": no readable plate — the sweep can't plan a spiral") end
        end
        pcall(function()
            local objects = workspace:FindFirstChild("Objects")
            local fields = objects and objects:FindFirstChild("Fields")
            for _, d in ipairs(fields and fields:GetChildren() or {}) do considerField(d) end
            local plots = workspace:FindFirstChild("Plots")
            for _, plot in ipairs(plots and plots:GetChildren() or {}) do
                if plot:IsA("Model") then
                    for _, d in ipairs(plot:GetChildren()) do considerField(d) end
                end
            end
        end)
        if nf == 0 then
            add("  (none owned by you)")
            problem("no field is owned by you — the tour has nothing to work")
        end
        -- pads
        add("sell pads (ranked, crop store first):")
        local spots = findSellSpots()
        for i, s in ipairs(spots) do
            if i > 6 then
                add(string.format("  … %d more", #spots - 6))
                break
            end
            add(string.format("  %d. %s · store %s · %.0f from FarmCo · %.0f from you",
                i, s.what, tostring(s.store or "?"), s.dist, (s.p - here).Magnitude))
        end
        if #spots == 0 then
            add("  (none found)")
            problem("no sell pads found — selling cannot work at all")
        end
        local cool = sellCooldownUntil - os.clock()
        if cool > 0 then
            add(string.format("sell: cooling down %.0f s (the last trip didn't land)", cool))
        end
        -- the only part that needs a human
        if #problems > 0 then
            add(string.format("⚠ %d thing(s) to look at:", #problems))
            for _, p in ipairs(problems) do add("  · " .. p) end
        else
            add("✅ nothing obviously wrong in this snapshot")
        end
        if doctorPara then
            pcall(function() doctorPara:SetValue(table.concat(lines, "\n")) end)
        end
        for _, l in ipairs(lines) do print("[spud doc] " .. l) end
        if mirror then
            -- the startup run puts itself where it will be seen without a click
            for _, l in ipairs(lines) do log("doc: " .. l) end
        end
        if not doctorPara then
            -- no panel to read: put the report where the player can see it
            for _, l in ipairs(lines) do log("doc: " .. l) end
        end
        log(string.format("doctor: %d lines — Doctor tab", #lines))
        return #problems > 0
            and string.format("%d thing(s) to look at — see the Doctor tab", #problems)
            or "nothing obviously wrong in this snapshot"
    end

    -- ▸ A CLICK MUST ALWAYS VISIBLY DO SOMETHING. The first version only wrote
    --   into the panel, so a failure inside the report — or a panel that never
    --   built — made the button look dead, with the reason hidden in the
    --   executor console. Every path now ends in a notification: the summary,
    --   or the actual error text.
    runDoctor = function(mirror)
        local ok, res = pcall(doctorReport, mirror)
        if ok then
            local summary = tostring(res)
            if not doctorPara then
                summary = summary .. " (panel unavailable — full report is in the Console tab)"
            end
            pcall(function()
                Fluent:Notify({ Title = "SPUD DOCTOR", Content = summary, Duration = 8 })
            end)
            return summary
        end
        local msg = "doctor failed: " .. tostring(res)
        if doctorPara then pcall(function() doctorPara:SetValue(msg) end) end
        log(msg)
        pcall(function()
            Fluent:Notify({ Title = "SPUD DOCTOR", Content = msg, Duration = 10 })
        end)
        return msg
    end

    -- ▸ REACHABLE WITHOUT THE BUTTON. If the tab refuses to render it, the
    --   report is one line in the executor: spudDoctor(). Same code either way.
    local genv = (getgenv and getgenv()) or _G
    if genv then
        genv.spudDoctor = function()
            local res = runDoctor()
            print("[spud doc] " .. tostring(res))
            return "[spud doc] " .. tostring(res)
        end
    end

    local okBtn, errBtn = pcall(function()
        Tabs.Doctor:CreateButton({
            Title = "🩺 Doctor report (read-only)",
            Callback = function() runDoctor() end,
        })
    end)
    if okBtn then
        log("gui: doctor button ok")
    else
        log("doctor: the button didn't build (" .. tostring(errBtn)
            .. ") — run spudDoctor() in the executor instead")
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

    log("gui: farming toggle ok")

    ------------------------------------------------------------
    -- MILK TAB — SHELL ONLY
    -- user: "to know the users feild there will be a dropdown asking wich user
    -- it is. it's a loop like the farming loop build that but nothing inside,
    -- only gui". So: the user picker, the loop toggle, and the thread
    -- plumbing that makes ON/OFF honest — and NOTHING in the body. The Milk
    -- steps (cow at 300 %, barn, milk, back to the field) land one at a time
    -- once the dump says what those things actually are.
    ------------------------------------------------------------
    do -- ▸ MILK TAB IN ITS OWN SCOPE: these 34 locals die at the end of this
       --   block, which keeps the executor's 200-locals-per-function budget
       --   healthy (see REGISTER BUDGET above).
    local milkUser -- the picked player's name (nil = nothing picked)
    -- own thread id + own stop test: stopping() belongs to the FARMING loop,
    -- and a milk thread would read it as "stopped" on its very first tick.
    milkThread = nil
    milkStopping = function()
        if not milkThread then return true end
        return coroutine.running() ~= milkThread
    end
    end -- ▸ end of the do-block above: its 128 locals die here and the
        --   executor's 200-locals-per-function budget never blows again

    -- everyone but me — the farm loop already owns MY plot
    local function milkUserChoices()
        local out = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then out[#out + 1] = p.Name end
        end
        table.sort(out)
        if #out == 0 then out[1] = "(nobody else is here)" end
        return out
    end

    local milkChoices0 = milkUserChoices()
    milkUser = milkChoices0[1]
    local milkDrop = Tabs.Milk:CreateDropdown("milkUser", {
        Title = "User",
        Values = milkChoices0,
        Multi = false,
        Default = milkUser,
        Callback = function(v)
            milkUser = v
            log("milk: user = " .. tostring(v))
        end,
    })
    log("milk: users — " .. table.concat(milkChoices0, ", "))

    -- ▸ the tab SHOWS what the loop sees (user: "it should show cows and a
    --   dirty stall"): the plot it picked, every cow and its production %, and
    --   the stall verdict. The console keeps the same text.
    local milkPara = Tabs.Milk:CreateParagraph("MilkStatus", {
        Title = "Status",
        Content = "idle",
    })

    -- players join and leave mid-session: keep the picker true. Fluent's
    -- refreshing method differs between builds, so both names are tried and
    -- the failure is SAID once instead of pretending the list is live.
    local milkRefreshWorks = true
    local function refreshMilkUsers()
        if not milkRefreshWorks then return end
        local list = milkUserChoices()
        local ok = pcall(function() milkDrop:SetValues(list) end)
        if not ok then ok = pcall(function() milkDrop:Refresh(list) end) end
        if not ok then
            milkRefreshWorks = false
            log("milk: this build's dropdown can't be refilled — reload the script to see players who joined later")
            return
        end
        local found = false
        for _, n in ipairs(list) do
            if n == milkUser then found = true break end
        end
        if not found then
            milkUser = list[1]
            log("milk: the picked user left — now on " .. tostring(milkUser))
            pcall(function() Fluent.Options.milkUser:SetValue(milkUser) end)
        end
    end
    Players.PlayerAdded:Connect(function(p)
        if p ~= LocalPlayer then refreshMilkUsers() end
    end)
    Players.PlayerRemoving:Connect(function(p)
        if p ~= LocalPlayer then refreshMilkUsers() end
    end)

    ------------------------------------------------------------
    -- MILK - STEP 1: SEE, THEN CLEAN
    -- user: "it should show cows and a dirty stall. if there is a dirty stall
    -- EVER in the milk loop IT MUST clean it IMEDIATLY before doing anything.
    -- it should also see food for the animals, we save that for later tho"
    --
    -- The dump names the pieces: Objects.Animals holds the Cow models, every
    -- stall has an "Adornee_BarnStallMenu" billboard (12 of them), the animal
    -- menu exposes Herd / Pet / Rename, the production number is the "(45%)"
    -- text on ...ProductionVisual.ProgressLabel, and cleaning is the game's
    -- OWN prompt: CleanAnimalContainer, bound to V.
    --
    -- Nothing here invents state and nothing fires a remote: a stall is DIRTY
    -- when the game itself offers Clean at it, and cleaning is the V press the
    -- game itself asks for. Cows are attributed through Configurations.Owner
    -- (the same tag the fields use), with a distance fallback to the picked
    -- plot for anything the game leaves untagged.
    ------------------------------------------------------------
    local function milkSetStatus(txt)
        pcall(function() milkPara:SetValue(txt) end)
    end

    -- the game's "what can I do right now" billboards, the same tree the
    -- farming loop reads for FillSeeder / Hitch
    local function promptUp(name)
        local ok, b = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local hud = gv and gv:FindFirstChild("HUD")
            local gw = hud and hud:FindFirstChild("MainHUD")
            local cpa = (gw and gw:FindFirstChild("PCGP_ContextActions"))
                or (hud and hud:FindFirstChild("PCGP_ContextActions"))
            local bills = cpa and cpa:FindFirstChild("Billboards")
            return bills and bills:FindFirstChild(name)
        end)
        if ok and b then
            if b:IsA("LayerCollector") then return b.Enabled == true end
            if b:IsA("GuiObject") then return b.Visible == true end
        end
        return nil -- unreadable: never guess
    end

    -- Configurations.Owner, walked up a few parents (plot / field / vehicle /
    -- animal all carry it in the dump)
    local function milkOwnerOf(inst)
        local p = inst
        for _ = 1, 8 do
            if not p then break end
            local conf = p:FindFirstChild("Configurations")
            local o = conf and conf:FindFirstChild("Owner")
            if o and o:IsA("ObjectValue") and o.Value then return o.Value.Name end
            p = p.Parent
        end
        return nil
    end

    local function milkPlotOf(ownerName)
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil, "Workspace.Plots is missing" end
        local seen = {}
        for _, m in ipairs(plots:GetChildren()) do
            if m:IsA("Model") then
                local who = milkOwnerOf(m)
                -- the billboard carries the DISPLAY name ("Simba"), the Owner
                -- value carries the account: accept either, case-insensitive
                local bill = m:FindFirstChild("PlotBillboard")
                local lab = bill and bill:FindFirstChild("Owner")
                local txt = (lab and lab:IsA("TextLabel")) and lab.Text or nil
                seen[#seen + 1] = string.format("%s=%s", m.Name, tostring(who or txt or "?"))
                local hit = (who and who:lower() == ownerName:lower())
                    or (txt and txt ~= "" and txt:lower():find(ownerName:lower(), 1, true) ~= nil)
                if hit then return m, table.concat(seen, " ") end
            end
        end
        return nil, table.concat(seen, " ")
    end

    local function milkInBox(pos, cf, size, pad)
        if not pos or not cf or not size then return false end
        local rel = cf:PointToObjectSpace(pos)
        return math.abs(rel.X) <= size.X / 2 + pad
            and math.abs(rel.Z) <= size.Z / 2 + pad
    end

    -- ▸ THE "300%" lives ON THE COW (dump 21: every Cow model has
    --   Configurations.Production = 300 and Configurations.Mood). So the whole
    --   read costs nothing: no menu, no teleport, no waiting.
    local function milkPercentOf(m)
        local conf = m:FindFirstChild("Configurations")
        local prod = conf and conf:FindFirstChild("Production")
        if prod and prod:IsA("NumberValue") then
            return math.floor(prod.Value + 0.5)
        end
        for _, a in ipairs({ "Production", "ProductionPercent", "Milk" }) do
            local v = m:GetAttribute(a)
            if type(v) == "number" then return math.floor(v + 0.5) end
        end
        return nil
    end

    -- "Wander" = out in the field, "IdleLocked" = parked in a barn stall
    local function milkStateOf(m)
        local conf = m:FindFirstChild("Configurations")
        local st = conf and conf:FindFirstChild("AnimoidState")
        if st and st:IsA("StringValue") and st.Value ~= "" then return st.Value end
        return nil
    end

    -- ▸ THE "300%" (user: "find a cow at 300%"). It is NOT on the cow model:
    --   the game prints it on the shared animal menu
    --   GuiViews.Animal.AnimalInteractions.AnimalInteractionGuis.
    --   AnimalInteractionMenu.QuickInfo.AnimalLabel.ProductionFrame.
    --   ProductionVisual.ProgressLabel  =  "[PROD_TYPE] (45%)"
    --   and that menu only fills in while you stand next to the animal. So we
    --   go there and read it; the slider fill is the fallback when the label
    --   still shows its template text.
    local function milkMenuRead()
        local ok, pct, label, shown = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local g = gv and gv:FindFirstChild("Animal")
            local ai = g and g:FindFirstChild("AnimalInteractions")
            local ag = ai and ai:FindFirstChild("AnimalInteractionGuis")
            local menu = ag and ag:FindFirstChild("AnimalInteractionMenu")
            if not menu then return nil end
            local qi = menu:FindFirstChild("QuickInfo")
            local al = qi and qi:FindFirstChild("AnimalLabel")
            local pf = al and al:FindFirstChild("ProductionFrame")
            local pv = pf and pf:FindFirstChild("ProductionVisual")
            local lab = pv and pv:FindFirstChild("ProgressLabel")
            local txt = (lab and lab:IsA("TextLabel")) and lab.Text or ""
            local n = tonumber(tostring(txt):match("(%d+)%%"))
            if not n then
                local sb = pv and pv:FindFirstChild("SliderBackground")
                local sf = pv and pv:FindFirstChild("SliderForeground")
                if sb and sf and sb:IsA("GuiObject") and sf:IsA("GuiObject")
                    and sb.AbsoluteSize.X > 0 then
                    n = math.floor(sf.AbsoluteSize.X / sb.AbsoluteSize.X * 100 + 0.5)
                end
            end
            local on
            if menu:IsA("LayerCollector") then
                on = menu.Enabled == true
            elseif menu:IsA("GuiObject") then
                on = menu.Visible == true
            end
            return n, txt, on
        end)
        if not ok then return nil, "menu unreadable", nil end
        return pct, label, shown
    end

    -- ▸ A DIRTY STALL shows a "Stain" part at that spot (dump 21: a Stain sits
    --   beside the one dirty stall and NOT beside the clean ones). The Filth /
    --   FilthEffect parts are always present and always visible, so counting
    --   them marked all 12 stalls dirty - they are not a dirt signal.
    local function milkStain(spot)
        if not spot then return 0 end
        local n = 0
        for _, d in ipairs(spot:GetDescendants()) do
            if d.Name == "Stain" and d:IsA("BasePart") and d.Transparency < 0.95 then
                n += 1
            end
        end
        return n
    end

    -- the game only offers Clean when you stand in the stall's own trigger
    -- volume (Spot.ProximityPart), NOT at the menu adornee panel - standing at
    -- the panel is why the prompt never lit.
    local function milkTrigger(spot)
        if not spot then return nil end
        local ok, part = pcall(function()
            local t = spot:FindFirstChild("ProximityPart", true)
            return (t and t:IsA("BasePart")) and t or nil
        end)
        return ok and part or nil
    end

    local function milkStalls(wantOwner, cf, size)
        local out, skipped = {}, 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "Adornee_BarnStallMenu" then
                -- dump: 12 parts carry this name (the ADORNEE targets), so a
                -- BasePart IS the stall position; the billboard variant reads
                -- its Adornee. Both shapes are covered.
                local pos
                pcall(function()
                    if d:IsA("BasePart") then
                        pos = d.Position
                    elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
                        local ad = d.Adornee
                        if ad and ad:IsA("BasePart") then pos = ad.Position end
                    end
                end)
                -- the numbered folder above it ("Spots.2") holds that stall's
                -- ProximityPart / Filth / Hay / Occupant
                local par = d.Parent
                local spot = (par and par.Parent and par.Parent.Name == "Spots") and par or nil
                local owner = milkOwnerOf(d)
                local mine = owner and wantOwner and owner:lower() == wantOwner:lower()
                local near = (owner == nil) and cf and pos and milkInBox(pos, cf, size, 80)
                if mine or near then
                    out[#out + 1] = {
                        pos = pos,
                        owner = owner,
                        part = d,
                        spot = spot,
                        trigger = milkTrigger(spot),
                    }
                else
                    skipped += 1
                end
            end
        end
        return out, skipped
    end

    local function milkCows(wantOwner, cf, size, stalls)
        local objects = workspace:FindFirstChild("Objects")
        local folder = objects and objects:FindFirstChild("Animals")
        if not folder then return {}, "Objects.Animals is missing" end
        local out, seen = {}, {}
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") and m.Name:lower():find("cow", 1, true) then
                local owner = milkOwnerOf(m)
                local p = m:GetPivot().Position
                local mine = owner and wantOwner and owner:lower() == wantOwner:lower()
                local near = (owner == nil) and cf and milkInBox(p, cf, size, 80)
                if mine or near then
                    local c = {
                        index = #out + 1,
                        model = m,
                        pos = p,
                        percent = milkPercentOf(m),
                        state = milkStateOf(m),
                    }
                    seen[m] = c
                    out[#out + 1] = c
                end
            end
        end

        -- ▸ COWS IN A BARN ARE TAKEN OUT OF Objects.Animals (user: "it does not
        --   see when a cow is in the barn"). The stall's Occupant is the truth;
        --   a parked cow that is not linked to a spot yet is found under the
        --   barn's AnimalContainer. They keep their stall so the milk step can
        --   walk straight to the right door.
        local function add(m, spot)
            if not m or not m:IsA("Model") then return end
            local hit = seen[m]
            if hit then
                hit.stall = hit.stall or spot
                hit.inBarn = true
                hit.state = hit.state or "IdleLocked"
                return
            end
            local c = {
                index = #out + 1,
                model = m,
                pos = m:GetPivot().Position,
                percent = milkPercentOf(m),
                state = milkStateOf(m) or "IdleLocked",
                stall = spot,
                inBarn = true,
            }
            seen[m] = c
            out[#out + 1] = c
        end
        local containers = {}
        for _, s in ipairs(stalls or {}) do
            local o = s.spot and s.spot:FindFirstChild("Occupant")
            if o and o:IsA("ObjectValue") and o.Value then add(o.Value, s.spot) end
            local cont = s.spot and s.spot.Parent and s.spot.Parent.Parent
            if cont and not containers[cont] then
                containers[cont] = true
                for _, ch in ipairs(cont:GetChildren()) do
                    if ch:IsA("Model") and ch.Name:lower():find("cow", 1, true) then
                        add(ch, nil)
                    end
                end
            end
        end
        return out
    end

    -- ▸ TELEPORT (user: "with the milk loop you can make it tp, no tools will
    --   be used"). One CFrame write, then a short beat so the game's own
    --   prompts catch up with the new position. Still refuses from a vehicle
    --   seat: the milk loop works on foot and no tool is ever equipped.
    local function milkTp(target)
        local ch = LocalPlayer.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then return false end
        if (target - root.Position).Magnitude > 4 then
            root.CFrame = CFrame.new(target) * (root.CFrame - root.CFrame.Position)
            task.wait(0.2)
        end
        return true
    end

    -- ▸ HERD (user: "go to the cow click the herd button then bring them to
    --   the barn"). Herd = stand on the cow, press the menu's OWN Herd button,
    --   then LEAD it in (the cow follows the player, and the barn's stall then
    --   takes it in).
    local function milkMenuPointsAt(menu, model)
        local ok, ad = pcall(function() return menu.Adornee end)
        if not ok or not ad then return false end
        if ad == model then return true end
        local okHit, hit = pcall(function() return model:FindFirstChild("Hitbox", true) end)
        if okHit and hit and ad == hit then return true end
        local okIn, inside = pcall(function()
            return ad:IsDescendantOf(model) or model:IsDescendantOf(ad)
        end)
        return okIn and inside == true
    end

    -- ▸ THE RIGHT MENU, BY ANIMAL (dump 25): AnimalInteractionGuis holds ONE
    --   AnimalInteractionMenu per animal, each adorned to that animal's own
    --   Hitbox, and only the one you stand at is Enabled. FindFirstChild got a
    --   disabled stranger's menu every time, so the Herd click went nowhere and
    --   the cow never entered herd mode.
    --   GLOBAL on purpose: the build closure is at the executor's 200-local
    --   ceiling, and more locals there kill the whole GUI.
    function milkMenuFor(model)
        local ok, best, total, ready = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local an = gv and gv:FindFirstChild("Animal")
            local ai = an and an:FindFirstChild("AnimalInteractions")
            local gs = ai and ai:FindFirstChild("AnimalInteractionGuis")
            if not gs then return nil, 0, 0 end
            local n, on, hit = 0, 0, nil
            for _, m in ipairs(gs:GetChildren()) do
                if m.Name == "AnimalInteractionMenu" then
                    n += 1
                    if m:IsA("BillboardGui") and m.Enabled then
                        on += 1
                        if not hit and milkMenuPointsAt(m, model) then hit = m end
                    end
                end
            end
            return hit, n, on
        end)
        if not ok then return nil, 0, 0 end
        return best, total, ready
    end

    -- herd mode is real module state (HerdingMode.IsOpen), so ask it instead of
    -- guessing from the UI. Read only. GLOBAL for the same slot-budget reason.
    function milkHerdOn()
        local ok, on = pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local m = rs:FindFirstChild("Modules")
            local g = m and m:FindFirstChild("GuiModels")
            local h = g and g:FindFirstChild("HerdingMode")
            if not h then return nil end
            return require(h).IsOpen
        end)
        if not ok then return nil end
        return on
    end

    -- leave herd mode between cows, otherwise the next Herd press just toggles
    -- the mode the previous cow left open. Read/write on the module's own API.
    function milkHerdOff()
        local ok = pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local h = rs.Modules.GuiModels.HerdingMode
            require(h).Close()
        end)
        return ok
    end

    -- what the game offers as a CLICKABLE thing right now (the herd/lasso icon
    -- only exists while a cow is herded, so this is how we learn its name)
    local function milkLogButtons(tag)
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local found = 0
        for _, d in ipairs(pg:GetDescendants()) do
            if found >= 20 then break end
            if d:IsA("GuiButton") and d.Visible then
                local vis, o = true, d
                while o and not o:IsA("ScreenGui") do
                    if o:IsA("GuiObject") and not o.Visible then vis = false break end
                    o = o.Parent
                end
                if vis and o and o:IsA("ScreenGui") and not o.Enabled then vis = false end
                local bill, b = nil, d
                for _ = 1, 6 do
                    b = b.Parent
                    if not b then break end
                    if b:IsA("BillboardGui") then bill = b break end
                end
                if vis and (bill == nil or bill.Enabled) then
                    found += 1
                    log(string.format("milk: [%s] button %s '%s'%s", tag, d.Name,
                        d:IsA("TextButton") and d.Text or "",
                        bill and (" -> adornee " .. tostring(bill.Adornee and bill.Adornee.Name))
                            or ""))
                end
            end
        end
        if found == 0 then log("milk: [" .. tag .. "] no visible button in PlayerGui") end
    end

    -- the lasso: herd mode puts HerdTarget billboards on the spots a herded
    -- animal can be sent to (dump 26 = ...GuiViews.Animal.HerdingMode.
    -- HerdingVisuals.<HerdTarget>.Trigger). The barn one is whichever target
    -- stands nearest the barn, so pick by geometry - the names are $0/GateLarge.
    function milkHerdTargets()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local vis = pg and pg:FindFirstChild("HerdingVisuals", true)
        local barn = workspace:FindFirstChild("AutoWoodenBarn", true)
        local bp = barn and barn:GetPivot().Position
        local out = {}
        for _, b in ipairs(vis and vis:GetChildren() or {}) do
            if b:IsA("BillboardGui") and b.Name == "HerdTarget" then
                local ad, pos = b.Adornee, nil
                if ad then
                    local okp, p = pcall(function() return ad:GetPivot().Position end)
                    if okp then pos = p end
                end
                out[#out + 1] = {
                    trig = b:FindFirstChild("Trigger"),
                    pos = pos,
                    label = ad and ad.Name or "?",
                    dist = (pos and bp) and math.floor((pos - bp).Magnitude) or nil,
                }
            end
        end
        table.sort(out, function(a, b) return (a.dist or 1e9) < (b.dist or 1e9) end)
        return out
    end

    -- ▸ YIELD TO THE FARM LOOP MID-CYCLE. A cycle started while the farm was
    --   resting can outlive that rest, and two drivers on one body fight.
    --   Every long milk step bails the moment the farm loop starts moving.
    --   NOT a local function: it is used ABOVE this point too (milkHerdArm /
    --   milkHerdSend / milkCowInStall / milkClean), and a forward local reference silently
    --   becomes a nil GLOBAL - that crashed the first milk cycle.
    farmTookBody = function()
        return loopThread ~= nil and farmResting ~= true
    end

    -- herd mode is module state, so ask it who is already in the herd instead
    -- of guessing from the UI. Read only. GLOBAL: no local slots left here.
    function milkInHerd(model)
        local ok, yes = pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            return require(rs.Modules.GuiModels.HerdingMode).IsAnimalInHerd(model)
        end)
        if not ok then return nil end -- signature unknown: caller treats it as "unread"
        return yes == true
    end

    -- ▸ ARM ONE COW (user: "click 5 cows in ONE herding, that's what i meant by
    --   herd 5 cows at a time"). The first press opens herd mode, the later ones
    --   ADD to the herd that is already open, so all five ride one lasso.
    --   Already-herded cows are skipped: pressing Herd again would toggle them
    --   back out. GLOBAL because the build closure is out of local slots.
    function milkHerdArm(cow, first)
        local model, name = cow.model, string.format("cow %d", cow.index or 0)
        if milkInHerd(model) == true then
            log(string.format("milk: %s is already in the herd - no press needed", name))
            return true
        end
        milkTp(model:GetPivot().Position + Vector3.new(0, 3, 0))
        task.wait(0.6)
        local menu, howMany, howOn = milkMenuFor(model)
        for _ = 1, 12 do -- up to 3 s for the game to light up THAT cow's menu
            if milkStopping() or farmTookBody() or menu then break end
            task.wait(0.25)
            menu, howMany, howOn = milkMenuFor(model)
        end
        if not menu then
            log(string.format("milk: %s - no enabled animal menu on it (%d menu(s), %d enabled)",
                name, howMany or 0, howOn or 0))
            return false
        end
        local list = menu:FindFirstChild("Interactions")
        list = list and list:FindFirstChild("InteractionsList")
        local btn = list and list:FindFirstChild("Herd")
        if not btn then
            log(string.format("milk: %s - its menu has no Herd button", name))
            return false
        end
        local clicked, how = invokeHandlers(btn)
        if not clicked then
            pcall(function() btn:Activate() end)
            how = "activate()"
        end
        task.wait(1.0)
        local on = milkHerdOn()
        log(string.format("milk: %s - Herd pressed on its own menu (%s) - herd mode %s",
            name, tostring(how), on == nil and "unknown" or (on and "ON" or "did NOT turn on")))
        if first then milkLogButtons("after Herd") end
        if on == false then
            log(string.format("milk: %s - the game refused herd mode, leaving it in the field", name))
            return false
        end
        local inside = milkInHerd(model)
        for _ = 1, 4 do -- the selection animates, so give it a beat before a miss
            if inside ~= nil or milkStopping() then break end
            task.wait(0.5)
            inside = milkInHerd(model)
        end
        if inside == false then
            log(string.format("milk: %s - not in the herd after the press", name))
            return false
        end
        log(string.format("milk: %s - %s", name,
            inside == nil and "herd press sent (membership unreadable)" or "added to the herd"))
        return true
    end

    -- ▸ ONE LASSO FOR THE WHOLE HERD. Every cow is armed and herd mode is still
    --   open, so a single press of the barn's HerdTarget sends the lot. We then
    --   just count the stalls that fill up instead of guessing per cow.
    function milkHerdSend(picks)
        if #picks == 0 then return 0 end
        local stall = picks[1].spot
        local trig = stall:FindFirstChild("ProximityPart", true)
        local centre = stall:FindFirstChild("Center", true)
        local dest = (trig and trig.Position) or (centre and centre.Position)
        if not dest then
            log("milk: the stall has no readable spot to stand on")
            return 0
        end
        milkTp(dest + Vector3.new(0, 3, 0))
        task.wait(1.8) -- herd mode re-draws the targets where we land, not before
        local targets = milkHerdTargets()
        for _ = 1, 6 do -- up to 3 s for the targets to appear
            if #targets > 0 or milkStopping() or farmTookBody() then break end
            task.wait(0.5)
            targets = milkHerdTargets()
        end
        for i, t in ipairs(targets) do
            log(string.format("milk: herd target %d '%s' @ %s (%s from barn)", i, t.label,
                t.pos and string.format("%d,%d,%d", t.pos.X, t.pos.Y, t.pos.Z) or "?",
                t.dist and (tostring(t.dist) .. " studs") or "?"))
        end
        local function landed()
            local n = 0
            for _, p in ipairs(picks) do
                local o = p.spot:FindFirstChild("Occupant")
                if o and o:IsA("ObjectValue") and o.Value then n += 1 end
            end
            return n
        end
        local got = 0
        for attempt = 1, 2 do
            local t = milkHerdTargets()[1]
            if not (t and t.trig) then
                log("milk: herd mode offered no HerdTarget to press")
                break
            end
            local c, how = invokeHandlers(t.trig)
            if not c then pcall(function() t.trig:Activate() end) end
            log(string.format("milk: lasso pressed on '%s' (%s) - %d cow(s) armed", t.label,
                tostring(how or "activate()"), #picks))
            task.wait(2.0) -- let the herd actually take the order
            local t0 = os.clock()
            while os.clock() - t0 < 25 do
                if milkStopping() or farmTookBody() then break end
                got = landed()
                if got >= #picks then break end
                task.wait(0.5)
            end
            if got > 0 or attempt == 2 then break end
            log("milk: no cow moved - one more lasso press")
        end
        for _, p in ipairs(picks) do
            local o = p.spot:FindFirstChild("Occupant")
            local v = o and o:IsA("ObjectValue") and o.Value
            log(string.format("milk: cow %d -> stall %s %s", p.cow.index or 0, p.spot.Name,
                v and "OCCUPIED" or "still empty"))
        end
        return got
    end

    -- ▸ ONE HERDING RUN = UP TO 5 COWS (user: "herd 5 cows per herding and milk
    --   them all then do the checks then restart"): arm them all into one herd,
    --   one lasso, then hand the body back so the caller can milk the batch.
    function milkHerdBatch(stalls, cows)
        local free, parked = {}, 0
        for _, s in ipairs(stalls or {}) do
            if s.spot then
                local o = s.spot:FindFirstChild("Occupant")
                if o and o:IsA("ObjectValue") and o.Value then
                    parked += 1
                else
                    free[#free + 1] = s
                end
            end
        end
        if parked >= 5 or #free == 0 then return 0, 0, parked end
        local picks, tried = {}, 0
        for _, c in ipairs(cows or {}) do
            if #picks >= 5 - parked or #free == 0 then break end
            if not c.inBarn and not c.stall and c.state ~= "IdleLocked"
                and (c.percent or 0) >= 300 then
                tried += 1
                local slot = table.remove(free, 1)
                if milkHerdArm(c, tried == 1) then
                    picks[#picks + 1] = { spot = slot.spot, cow = c }
                else
                    free[1] = slot -- it stayed in the field, so keep its stall
                end
                task.wait(1.0) -- gap between Herd presses, the menu animates
                if milkStopping() or farmTookBody() then break end
            end
        end
        local done = 0
        if #picks > 0 then
            done = milkHerdSend(picks)
            task.wait(1.0) -- let the stalls settle before herd mode closes
            milkHerdOff()
            task.wait(1.5) -- and before the next cycle opens its own herd
        end
        return done, tried, parked + done
    end

    -- ▸ THE MILK STEP (wiki: "go inside the barn to the stall the cow is in and
    --   press the Milk button"). Nothing in the dumps names that action yet, so
    --   the first run PRINTS everything the stall offers (its prompts + visible
    --   buttons) and then takes the best shot: a visible milk-ish button, then
    --   the stall's own milk prompt key. Only a real change counts as done -
    --   Production dropping or a MilkContainer appearing.
    local function milkNearPrompts(spot)
        local set, list = {}, {}
        local roots = {}
        if spot then
            roots[1] = spot
            if spot.Parent then
                roots[2] = spot.Parent
                if spot.Parent.Parent then roots[3] = spot.Parent.Parent end
            end
        end
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ProximityPrompt") and not set[d] then
                    set[d] = true
                    list[#list + 1] = d
                end
            end
        end
        return list
    end

    local function milkFindButton(word)
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local nm = (d.Name .. " " .. (d:IsA("TextButton") and d.Text or "")):lower()
                if nm:find(word, 1, true) then
                    local vis, o, mine = true, d, false
                    while o and not o:IsA("ScreenGui") do
                        if o:IsA("GuiObject") and not o.Visible then vis = false break end
                        -- never touch this script's own Fluent window: its
                        -- "milk loop" toggle would match the word "milk"
                        local low = tostring(o.Name):lower()
                        if low:find("fluent", 1, true) or low:find("spud", 1, true) then
                            mine = true
                            break
                        end
                        o = o.Parent
                    end
                    if o and o:IsA("ScreenGui") then
                        local low = tostring(o.Name):lower()
                        if low:find("fluent", 1, true) or low:find("spud", 1, true) then mine = true end
                        if not o.Enabled then vis = false end
                    end
                    if vis and not mine then return d end
                end
            end
        end
    end

    -- ▸ THE GAME'S OWN CONTEXT ACTIONS (PCGP_ContextActions.Billboards): the
    --   Clean action shows up here, so a Milk action must too - and each
    --   billboard prints its own key as a one-letter label, so this names the
    --   action AND the key without guessing either.
    local function milkActions()
        local out = {}
        local ok = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gv = pg and pg:FindFirstChild("GuiViews")
            local hud = gv and gv:FindFirstChild("HUD")
            local gw = hud and hud:FindFirstChild("MainHUD")
            local cpa = (gw and gw:FindFirstChild("PCGP_ContextActions"))
                or (hud and hud:FindFirstChild("PCGP_ContextActions"))
            local bills = cpa and cpa:FindFirstChild("Billboards")
            if not bills then return end
            for _, b in ipairs(bills:GetChildren()) do
                local on
                if b:IsA("LayerCollector") then
                    on = b.Enabled == true
                elseif b:IsA("GuiObject") then
                    on = b.Visible == true
                else
                    on = false
                end
                local texts, key = {}, nil
                for _, d in ipairs(b:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text ~= "" then
                        texts[#texts + 1] = d.Text
                        if not key and d.Text:match("^%u$") then key = d.Text end
                    end
                end
                out[#out + 1] = {
                    name = b.Name,
                    on = on,
                    key = key,
                    text = table.concat(texts, " "),
                }
            end
        end)
        if not ok then return nil end
        return out
    end

    -- ▸ THE STALL'S OWN MENU (dump §24): the game shows a SurfaceGui named
    --   "BarnStallMenu" in PlayerGui.GuiViews.Animal.AnimalInteractions
    --   .AnimalContainerGuis, adorned to that stall's Adornee_BarnStallMenu
    --   part, and its text reads "Milk | 300% | Cow | 🤢 | 26%". Only the
    --   stall that is open is Enabled, so the Adornee is the exact match and
    --   Enabled is the fallback. This is the Milk button - not a prompt, not a
    --   context action.
    --   GLOBAL on purpose (not "local function"): the build closure is at the
    --   executor's 200-local ceiling, and two more declarations there killed
    --   the whole GUI. A global costs a temp register, not a permanent slot.
    function milkStallGui(spot)
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local holder
        pcall(function()
            holder = pg.GuiViews.Animal.AnimalInteractions.AnimalContainerGuis
        end)
        if not holder then return nil end
        local adn = spot:FindFirstChild("Adornee_BarnStallMenu", true)
        local open
        for _, g in ipairs(holder:GetChildren()) do
            if g.Name == "BarnStallMenu" and (g:IsA("SurfaceGui") or g:IsA("BillboardGui")) then
                local ok, ad = pcall(function() return g.Adornee end)
                if ok and adn and ad == adn then return g end
                if g.Enabled then open = open or g end
            end
        end
        return open
    end

    -- the clickable "Milk" inside that menu: a GuiButton whose own name or any
    -- label under it says milk, else the production trigger, else anything
    -- named collect. Nothing else in this menu is touched.
    -- GLOBAL for the same slot-budget reason as milkStallGui above.
    function milkStallButton(gui)
        local best, score = nil, 0
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("GuiButton") then
                local txt = tostring(d.Name)
                if d:IsA("TextButton") then txt ..= " " .. tostring(d.Text) end
                for _, c in ipairs(d:GetDescendants()) do
                    if c:IsA("TextLabel") or c:IsA("TextButton") then
                        txt ..= " " .. tostring(c.Text)
                    end
                end
                local low = txt:lower()
                local s2 = 0
                if low:find("milk", 1, true) then s2 = 3
                elseif low:find("production", 1, true) then s2 = 2
                elseif low:find("collect", 1, true) then s2 = 1 end
                if s2 > score then best, score = d, s2 end
            end
        end
        return best
    end

    -- ▸ LET THE COW OUT (user: "now it aint letting the cows out the barn").
    --   Nothing in this loop ever opened the stall gate, so a milked cow stayed
    --   parked until the barn filled up and herding blocked itself. The game
    --   prints "E | Open" on the BarnDoorInteract billboard only while the
    --   player stands at THAT stall's gate (Adornee = Gate.ProximityPart), so
    --   we stand there and press the key the billboard itself names.
    --   GLOBAL for the same slot-budget reason as milkStallGui above.
    function milkGateOpen(spot, cow)
        local gatePart
        pcall(function()
            local g = spot and spot:FindFirstChild("Gate")
            local p = g and g:FindFirstChild("ProximityPart")
            if p and p:IsA("BasePart") then gatePart = p end
        end)
        local name = tostring(spot and spot.Name or "?")
        if not gatePart then
            log("milk: " .. name .. " has no Gate.ProximityPart - the cow cannot be let out")
            return false
        end

        local function doorBill()
            local ok, b = pcall(function()
                local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local hud = pg and pg.GuiViews and pg.GuiViews:FindFirstChild("HUD")
                local gw = hud and hud:FindFirstChild("MainHUD")
                local cpa = (gw and gw:FindFirstChild("PCGP_ContextActions"))
                    or (hud and hud:FindFirstChild("PCGP_ContextActions"))
                local bills = cpa and cpa:FindFirstChild("Billboards")
                return bills and bills:FindFirstChild("BarnDoorInteract")
            end)
            if not (ok and b) then return nil end
            local okAd, ad = pcall(function() return b.Adornee end)
            if not okAd or ad ~= gatePart then return nil end
            return b
        end

        local stand = gatePart.Position + Vector3.new(0, 3, 0)
        milkTp(stand)
        task.wait(0.9)

        for attempt = 1, 3 do
            if milkStopping() then return false end
            local b = doorBill()
            if not b then
                log(string.format("milk: %s gate - the game is not offering the door action (try %d)",
                    name, attempt))
                milkTp(stand)
                task.wait(0.4)
            else
                local key, txt = nil, {}
                for _, d in ipairs(b:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text ~= "" then
                        txt[#txt + 1] = d.Text
                        if not key and d.Text:match("^%u$") then key = d.Text end
                    end
                end
                local joined = table.concat(txt, " ")
                local kc = (key and Enum.KeyCode[key]) or Enum.KeyCode.E
                if joined:lower():find("close", 1, true) then
                    -- pressing again would SHUT the gate on the cow
                    log(string.format("milk: %s gate is already open (%s) - waiting for cow %d",
                        name, joined:sub(1, 30), cow and cow.index or 0))
                else
                    log(string.format("milk: %s gate '%s' enabled=%s - pressing %s", name,
                        joined:sub(1, 30), tostring(b.Enabled), kc.Name))
                    pressKey(kc)
                end
            end
            -- the cow left when the game clears the stall Occupant or flips its
            -- own state off "IdleLocked"
            for _ = 1, 8 do
                task.wait(0.5)
                local o = spot:FindFirstChild("Occupant")
                local still = (o and o:IsA("ObjectValue") and cow and cow.model
                    and o.Value == cow.model) and true or false
                local st = cow and cow.model and milkStateOf(cow.model)
                if not still or st ~= "IdleLocked" then
                    log(string.format("OK milk: %s gate open - cow %d is out (%s)",
                        name, cow and cow.index or 0, st or "no state"))
                    return true
                end
            end
            log(string.format("milk: %s gate pressed (try %d) but the cow is still inside", name, attempt))
        end
        log(string.format("milk: %s - the gate never opened for cow %d", name, cow and cow.index or 0))
        return false
    end

    local function milkDrops()
        local objs = workspace:FindFirstChild("Objects")
        local box = objs and objs:FindFirstChild("DraggableObjects")
        local n = 0
        if box then
            for _, ch in ipairs(box:GetChildren()) do
                if ch.Name:lower():find("milk", 1, true) then n += 1 end
            end
        end
        return n
    end

    local function milkCowInStall(cow)
        local spot, model = cow.stall, cow.model
        if not (spot and model) then return false end
        local trig = milkTrigger(spot)
        local stand = (trig and trig.Position) or cow.pos
        if not stand then
            log("milk: that stall has no readable position")
            return false
        end
        milkTp(stand + Vector3.new(0, 3, 0))
        task.wait(1.0)

        local label = string.format("cow %d", cow.index or 0)
        local before, dropsBefore = milkPercentOf(model), milkDrops()
        for _, p in ipairs(milkNearPrompts(spot)) do
            local okKey, key = pcall(function() return p.KeyboardKeyCode.Name end)
            log(string.format("milk: %s prompt %s '%s' key=%s on=%s", spot.Name, p.Name,
                tostring(p.ActionText), tostring(okKey and key or "?"), tostring(p.Enabled)))
        end
        milkLogButtons("milking " .. spot.Name)

        -- the game's own action list at this stall: an enabled milk/collect
        -- action here is the real thing, and it prints its own key
        local acts = milkActions()
        local shown = 0
        for _, a in ipairs(acts or {}) do
            local nm = (a.name .. " " .. a.text):lower()
            if (a.on or nm:find("milk") or nm:find("collect") or nm:find("clean"))
                and shown < 12 then
                shown += 1
                log(string.format("milk: action %s%s%s '%s'", a.name,
                    a.on and "" or " [off]", a.key and (" key=" .. a.key) or "",
                    a.text:sub(1, 40)))
            end
        end

        local used
        -- 1. the stall's own menu (the real Milk button)
        local sGui = milkStallGui(spot)
        if sGui then
            local txt = {}
            for _, d in ipairs(sGui:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
                    txt[#txt + 1] = d.Text
                end
            end
            log(string.format("milk: %s - stall menu enabled=%s '%s'", label,
                tostring(sGui.Enabled), table.concat(txt, " | "):sub(1, 70)))
            local b = milkStallButton(sGui)
            if b then
                local okC, how = invokeHandlers(b)
                if not okC then
                    pcall(function() b:Activate() end)
                    how = "activate()"
                end
                used = string.format("stall menu %s (%s)", b.Name, tostring(how))
            else
                log("milk: " .. label .. " - the stall menu has no clickable button")
            end
        else
            log("milk: " .. label .. " - no BarnStallMenu for " .. spot.Name)
        end

        -- 2. any other visible milk-ish button
        for _, word in ipairs({ "milk", "collect", "production" }) do
            if used then break end
            local b = milkFindButton(word)
            if b then
                local okC, how = invokeHandlers(b)
                if not okC then
                    pcall(function() b:Activate() end)
                    how = "activate()"
                end
                used = string.format("button %s (%s)", b.Name, tostring(how))
                break
            end
        end
        if not used then
            for _, a in ipairs(acts or {}) do
                local nm = (a.name .. " " .. a.text):lower()
                if a.on and a.key and (nm:find("milk") or nm:find("collect")
                    or nm:find("production")) then
                    local okK = pcall(function() pressKey(Enum.KeyCode[a.key]) end)
                    if okK then
                        used = string.format("action %s (%s)", a.name, a.key)
                        break
                    end
                end
            end
        end
        if not used then
            for _, p in ipairs(milkNearPrompts(spot)) do
                local txt = (tostring(p.ActionText) .. " "
                    .. tostring(p.Parent and p.Parent.Name or "")):lower()
                if p.Enabled and txt:find("milk", 1, true) then
                    local okKey, key = pcall(function() return p.KeyboardKeyCode end)
                    if okKey and key then
                        pressKey(key)
                        used = "key " .. key.Name
                        break
                    end
                end
            end
        end
        log(string.format("milk: %s in %s - %s", label, spot.Name,
            used and ("sent " .. used) or "no milk action visible, nothing sent"))

        local milked = false
        for _ = 1, 20 do -- 10 s for the game to answer
            if milkStopping() or farmTookBody() then return false end
            local now = milkPercentOf(model)
            local drops = milkDrops()
            if (before and now and now < before) or drops > dropsBefore then
                milked = true
                log(string.format("OK milk: %s milked (%s%% -> %s%%, %d new drop(s) in the world)",
                    label, tostring(before or "?"), tostring(now or "?"), drops - dropsBefore))
                break
            end
            task.wait(0.5)
        end
        if not milked then
            log(string.format("milk: %s still %s%% in %s after the action - no milk seen",
                label, tostring(milkPercentOf(model) or "?"), spot.Name))
        end

        -- ▸ the cow goes back to the field whatever the milk did: a cow that
        --   cannot be milked must never clog a stall (that is what blocked the
        --   loop - "it aint letting the cows out the barn").
        milkGateOpen(spot, cow)
        return milked
    end

    -- ▸ OLD: visit every cow to let the shared menu fill in. The production
    --   number is on the cow itself now, so this is just the honest summary of
    --   what the game currently holds (no teleports, no waiting, no guesses).
    local function milkCowScan(cows)
        for _, c in ipairs(cows) do
            if c.percent == nil then
                c.label = "no Production value"
            else
                c.label = (c.percent >= 300) and "READY" or nil
            end
        end
    end

    -- ▸ IS *THIS* STALL DIRTY? The game's Clean billboard carries
    --   Adornee = the stall's own "Center" part (dump §24), so a match means
    --   the answer is about this stall. No match = the billboard is pointing at
    --   some other stall, so this one gets "unknown", never a guess.
    local function milkCleanUp(spot)
        local ok, b = pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local hud = pg and pg.GuiViews and pg.GuiViews:FindFirstChild("HUD")
            local gw = hud and hud:FindFirstChild("MainHUD")
            local cpa = (gw and gw:FindFirstChild("PCGP_ContextActions"))
                or (hud and hud:FindFirstChild("PCGP_ContextActions"))
            return cpa and cpa:FindFirstChild("Billboards")
                and cpa.Billboards:FindFirstChild("CleanAnimalContainer")
        end)
        if not (ok and b) then return nil end
        local centre = spot:FindFirstChild("Center", true)
        if not centre then return nil end
        local okAd, ad = pcall(function() return b.Adornee end)
        if not okAd or ad ~= centre then return nil end
        return b.Enabled == true
    end

    -- THE RULE: a dirty stall is cleaned BEFORE anything else happens.
    -- We stand IN the stall (on its Center part - the thing the Clean action is
    -- adorned to) and let the GAME answer: Clean enabled = dirty. A Stain part
    -- with no Clean action is logged, never guessed, never counted as cleaned.
    local function milkClean(stalls)
        local dirty, cleaned, unknown = 0, 0, 0
        for i, s in ipairs(stalls) do
            if milkStopping() then break end
            if farmTookBody() then
                log("milk: the farm loop took the body back - cleaning stops mid-way")
                break
            end
            local stains = milkStain(s.spot)
            local centre = s.spot:FindFirstChild("Center", true)
            local stand = (centre and centre.Position)
                or (s.trigger and s.trigger.Position) or s.pos
            if not stand then
                unknown += 1
                log(string.format("milk: stall %d has no readable position", i))
            else
                milkTp(stand + Vector3.new(0, 3, 0))
                task.wait(0.8)
                local up = milkCleanUp(s.spot)
                if up == nil then
                    unknown += 1
                    if stains > 0 then
                        log(string.format("milk: stall %d - %d filth part(s), the game's Clean action is not pointing here",
                            i, stains))
                    end
                elseif up == false then
                    if stains > 0 then
                        unknown += 1
                        log(string.format("milk: stall %d - %d stain(s) present but the game offers no Clean here",
                            i, stains))
                    end
                else
                    dirty += 1
                    log(string.format("milk: stall %d is DIRTY (%d stain(s)) - cleaning it now (the game's own V)",
                        i, stains))
                    local done = false
                    for attempt = 1, 3 do
                        if milkStopping() then break end
                        pressKey(Enum.KeyCode.V)
                        task.wait(1.3)
                        if milkCleanUp(s.spot) == false then
                            done = true
                            break
                        end
                        log(string.format("milk: stall %d still dirty after %d press(es)", i, attempt))
                    end
                    if done then
                        cleaned += 1
                        log(string.format("OK milk: stall %d cleaned (%d stain(s) -> %d)",
                            i, stains, milkStain(s.spot)))
                    else
                        log(string.format("milk: stall %d would not clean - next cycle tries again", i))
                    end
                end
            end
        end
        return dirty, cleaned, unknown
    end

    -- milk EVERY ready cow standing in a stall (one batch, user's order: herd 5,
    -- then milk them all). Unreadable parked cows still get one honest attempt.
    function milkAllParked(cows)
        local done, tried = 0, 0
        for pass = 1, 2 do
            for _, c in ipairs(cows or {}) do
                local want = pass == 1 and c.stall and (c.percent or 0) >= 300
                    or pass == 2 and c.stall and c.percent == nil
                if want then
                    tried += 1
                    if milkCowInStall(c) then done += 1 end
                    if milkStopping() or farmTookBody() then return done, tried end
                    if pass == 2 and tried >= 3 then return done, tried end
                end
            end
            if tried > 0 then return done, tried end
        end
        return done, tried
    end

    local function milkCycle()
        -- ▸ SHARE THE BODY (user: "when the milk loop is on the farm loop can
        --   still run"). They move the SAME character, so they can never work
        --   at the same second - the milk step only takes the body while the
        --   farm loop is RESTING (waiting for the crops to grow, where it
        --   doesn't move anything) or switched off. While the farm drives,
        --   milk stands by, and even the CLEAN step waits: nothing here may
        --   touch the character mid-pass.
        if loopThread and not farmResting then
            milkSetStatus("farm loop busy — milk stands by")
            return true, 0, 0, false, "defer"
        end
        local owner = milkUser
        if not owner or owner:sub(1, 1) == "(" then
            milkSetStatus("no user picked")
            log("milk: no user picked - the dropdown above names whose plot to work on")
            return false
        end
        local plot, plotsSeen = milkPlotOf(owner)
        local cf, size
        if plot then cf, size = plot:GetBoundingBox() end
        local stalls, skipped = milkStalls(owner, cf, size)

        -- ▸ 1. CLEAN FIRST. The user's rule is absolute: a dirty stall is
        --   cleaned before the loop does anything else at all.
        local dirty, cleaned, unknown = 0, 0, 0
        if #stalls > 0 then
            local trig = 0
            for _, s in ipairs(stalls) do if s.trigger then trig += 1 end end
            log(string.format("milk: %d stall(s) - checking them before anything else (%d with a trigger volume)",
                #stalls, trig))
            dirty, cleaned, unknown = milkClean(stalls)
        end

        -- ▸ 2. cows + their production number (field ones AND the ones parked
        --   in a barn stall, which the game has moved out of Objects.Animals)
        local cows = milkCows(owner, cf, size, stalls)
        milkCowScan(cows)

        -- ▸ 2b. MILK FIRST (it's the only step that pays, and it's the one the
        --   user needs): one cow that is ALREADY parked in a stall. A parked
        -- ▸ 2b. HERD A BATCH OF 5 (user: "herd 5 cows per herding and milk them
        --   all then do the checks then restart"). One run fills the barn to 5
        --   parked cows instead of one cow per cycle.
        local herdLine, herded = nil, false
        do
            local done, tried, parkedNow = milkHerdBatch(stalls, cows)
            herded = done > 0
            if tried == 0 then
                herdLine = string.format("herd: %d cow(s) already in the barn - no ready cow left to herd", parkedNow)
            else
                herdLine = string.format("herd: %d of %d cow(s) into the barn (%d parked now)",
                    done, tried, parkedNow)
            end
        end

        -- ▸ 2c. MILK THE WHOLE BATCH, then the checks run on the fresh numbers.
        --   The herd moved cows, so re-read them instead of trusting the snapshot.
        local milkLine, milked = nil, false
        do
            cows = milkCows(owner, cf, size, stalls)
            local done, tried = milkAllParked(cows)
            milked = done > 0
            milkLine = tried == 0 and "milk: no ready cow parked in a stall"
                or string.format("milk: %d of %d parked cow(s) milked", done, tried)
        end

        -- ▸ 3. show it
        local lines = {}
        local parked = 0
        for _, c in ipairs(cows) do if c.inBarn then parked += 1 end end
        lines[#lines + 1] = string.format("%s - plot %s - %d stall(s) - %d cow(s), %d in a barn", owner,
            plot and plot.Name or ("NOT FOUND [" .. tostring(plotsSeen) .. "]"), #stalls, #cows, parked)
        for i, c in ipairs(cows) do
            local where = c.stall and (" [barn " .. tostring(c.stall.Name) .. "]")
                or (c.state == "IdleLocked") and " [barn]"
                or (c.state and (" [" .. c.state:lower() .. "]") or "")
            lines[#lines + 1] = string.format("cow %d: %s%s%s", i,
                c.percent and (tostring(c.percent) .. "%") or "?%",
                c.percent and ((c.percent >= 300) and " READY" or "")
                    or (" (" .. tostring(c.label or "unread") .. ")"),
                where)
        end
        if #cows == 0 then
            lines[#lines + 1] = "no cow attributed to this plot yet"
        end
        if #stalls == 0 then
            lines[#lines + 1] = "no stall found for this plot - nothing to clean"
                .. (skipped > 0 and (" (" .. skipped .. " belong to someone else)") or "")
        else
            lines[#lines + 1] = string.format("stalls: %d dirty, %d cleaned, %d unreadable",
                dirty, cleaned, unknown)
        end
        if herdLine then lines[#lines + 1] = herdLine end
        if milkLine then lines[#lines + 1] = milkLine end
        milkSetStatus(table.concat(lines, "\n"))
        log("milk: " .. table.concat(lines, " | "))
        return true, dirty, unknown, (herded or milked)
    end

    -- the loop: see + clean every 30 s (cows / herd / milk land next). The
    -- body stops the instant the toggle goes off.
    local function runMilkLoop()
        log("milk loop: on - user " .. tostring(milkUser))
        while not milkStopping() do
            local okCycle, ran, dirty, unknown, herded, deferred = pcall(milkCycle)
            if not okCycle then
                log("milk cycle failed: " .. tostring(ran))
            end
            -- the farm loop owns the body while it drives: peek every 5 s and
            -- do nothing. Otherwise a successful herd means "go again at
            -- once", an issue means retry soon, nothing means once a minute.
            local busy = ((tonumber(dirty) or 0) + (tonumber(unknown) or 0)) > 0
            local idle = 60
            if deferred == "defer" then idle = 5
            elseif herded == true then idle = 2
            elseif busy then idle = 6 end
            if deferred ~= "defer" then
                log(string.format("milk: %s - next barn check in %d s",
                    busy and "issues found"
                        or (herded and "one barn job done" or "no dirty stall seen"), idle))
            end
            for _ = 1, idle * 2 do -- half-second slices so OFF reacts at once
                if milkStopping() then break end
                task.wait(0.5)
            end
        end
        milkSetStatus("idle")
    end

    local milkToggle
    milkToggle = Tabs.Milk:CreateToggle("milkLoop", {
        Title = "milk loop",
        Default = false,
        Callback = function(on)
            if on then
                if milkThread then return end -- already running
                -- ▸ SHARED BODY (user: "when the milk loop is on the farm loop
                --   can still run"). Both are allowed on at once: milkCycle
                --   defers while the farm loop is driving and works in its
                --   rest windows (waiting for the crops to grow). A loop
                --   already ON is refused at its OWN toggle below.
                if not milkUser or milkUser:sub(1, 1) == "(" then
                    log("milk loop: pick a user first — the dropdown names whose plot to work on")
                    pcall(function()
                        (Fluent.Options and Fluent.Options.milkLoop
                            or milkToggle):SetValue(false)
                    end)
                    return
                end
                log("milk loop: starting"
                    .. (loopThread and " — the farm loop is driving, milk works in its rest windows" or ""))
                task.spawn(function()
                    milkThread = coroutine.running()
                    local okRun, errRun = pcall(runMilkLoop)
                    if not okRun then
                        log("⚠ milk loop crashed: " .. tostring(errRun))
                    end
                    if milkThread == coroutine.running() then
                        milkThread = nil
                        pcall(function()
                            (Fluent.Options and Fluent.Options.milkLoop
                                or milkToggle):SetValue(false)
                        end)
                    end
                end)
            else
                if not milkThread then return end -- already off (echo-safe)
                milkThread = nil
                log("milk loop: off — stopped")
            end
        end,
    })

    log("gui: milk tab ok (shell only)")
    end -- ▸ end of the milk-tab scope

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

    -- ▸ the webhook URL lives here, not in the public repo (user: "i also want
    --   a webhook now please, it sends everything to the webhook"). Paste it
    --   once; the pump then posts the console in batches. Blank = off.
    local okHookUI, errHookUI = pcall(function()
        Tabs.Settings:CreateInput("WebhookURL", {
            Title = "webhook url (sends the console there)",
            Placeholder = "https://discord.com/api/webhooks/…",
            Value = hookURL ~= "" and hookURL or "",
            Callback = function(text)
                local ok, why = setHookURL(text)
                if not ok then
                    log("webhook: " .. tostring(why))
                    return
                end
                if hookURL == "" then
                    log("webhook: off")
                    return
                end
                log("webhook: set — everything from now on is posted there")
                log(string.format("webhook test · %s · place %d · %s",
                    VERSION, game.PlaceId, tostring(game.JobId)))
                task.spawn(function() task.wait(0.2) pcall(hookFlush) end)
            end,
        })
    end)
    if not okHookUI then
        log("webhook: the settings box didn't build (" .. tostring(errHookUI)
            .. ') — run spudWebhook("your url") in the executor')
    end

    Tabs.Settings:CreateButton({
        Title = "🔄 Reload latest update",
        Callback = function()
            log("fetching latest build…")
            -- ▸ CACHE BUSTER. GitHub's raw CDN holds a branch URL for a few
            --   minutes, so a fresh push could reload as the OLD build and
            --   look like "the button isn't there". A unique query string
            --   makes the executor fetch the current file instead.
            local bust = string.format("%s?t=%d&r=%d", SCRIPT_URL,
                math.floor(os.time()), math.random(1, 999999))
            local ok, src = pcall(function() return game:HttpGet(bust, true) end)
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

    log("gui: settings ok")

    -- ▸ IT ALSO RUNS ITSELF. The button proved easy to look past (or to click
    --   with nothing visible happening), so the snapshot is taken once a few
    --   seconds after load and written into BOTH the Doctor panel and the
    --   Console tab — no click needed to see the state of the farm.
    task.delay(3, function()
        pcall(function() runDoctor(true) end)
    end)

    -- start
    Window:SelectTab(1)
    Fluent:Notify({
        Title = "SPUD FARM",
        Content = "farming loop ready",
        Duration = 6,
    })
    log("loaded — " .. VERSION)
    log("GUI: Fluent Renewed · RIGHT SHIFT hides the window")
    log("🩺 doctor: its own DOCTOR tab (2nd tab) — or run spudDoctor() in the executor")

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
else
    print("[spud] GUI ready")
end
