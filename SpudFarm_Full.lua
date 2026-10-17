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

    -- ▸ PATHFINDER (user request): A* on a coarse 10-stud grid over the
    --   area between here and the goal, avoiding everything parked on the
    --   farm — equipment, buildings, draggables and plot trees. The old
    --   single far-side corridor waypoint "kind of struggled"; this finds
    --   the genuinely quickest way around and re-plans while moving.
    --   Marks grid cells covered by each obstacle's fat bounding square.
    local function obstacleCells(x0, z0, x1, z1, cell, blocked, ignore1, ignore2, counter)
        local pad = 6 -- keep at least THIS far from any equipment/building
        local function scan(folder)
            if not folder then return end
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m ~= ignore1 and m ~= ignore2 then
                    local ok, cf, sz = pcall(function() return m:GetBoundingBox() end)
                    if ok and cf then
                        local r = math.max(sz.X, sz.Z) / 2 + pad
                        local minX, maxX = cf.Position.X - r, cf.Position.X + r
                        local minZ, maxZ = cf.Position.Z - r, cf.Position.Z + r
                        if maxX >= x0 and minX <= x1 and maxZ >= z0 and minZ <= z1 then
                            counter.n += 1
                            for ix = math.floor((minX - x0) / cell), math.floor((maxX - x0) / cell) do
                                for iz = math.floor((minZ - z0) / cell), math.floor((maxZ - z0) / cell) do
                                    blocked[ix * 100000 + iz] = true
                                end
                            end
                        end
                    end
                end
            end
        end
        local objects = workspace:FindFirstChild("Objects")
        scan(objects and objects:FindFirstChild("Equipment"))
        scan(objects and objects:FindFirstChild("Buildings"))
        scan(objects and objects:FindFirstChild("DraggableObjects"))
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
        while #open > 0 do
            guard += 1
            if guard > 8000 then return nil end -- give up on absurd areas
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

    -- plan a route around everything: trip bbox + 50 studs margin, A* on
    -- the grid, then string-pulled (only direction changes survive). The
    -- first point is where we stand, the last is the exact goal. Returns
    -- world waypoints { {x,z}, ... } + obstacle count, or nil + reason.
    local function pathfindAround(startPos, goalPos, ignore1, ignore2)
        local cell, margin = 6, 50 -- 6-stud grid: shaves no corners around gear
        local x0 = math.min(startPos.X, goalPos.X) - margin
        local x1 = math.max(startPos.X, goalPos.X) + margin
        local z0 = math.min(startPos.Z, goalPos.Z) - margin
        local z1 = math.max(startPos.Z, goalPos.Z) + margin
        local nx = math.floor((x1 - x0) / cell) + 1
        local nz = math.floor((z1 - z0) / cell) + 1
        if nx * nz > 12000 then return nil, "area too big" end
        local blocked, counter = {}, { n = 0 }
        obstacleCells(x0, z0, x1, z1, cell, blocked, ignore1, ignore2, counter)
        local function cellOf(v, o) return math.floor((v - o) / cell) end
        local sx, sz = cellOf(startPos.X, x0), cellOf(startPos.Z, z0)
        local gx, gz = cellOf(goalPos.X, x0), cellOf(goalPos.Z, z0)
        -- we're standing at the start and the goal must be enterable even
        -- when their cells got inflated-marked by a nearby obstacle
        blocked[sx * 100000 + sz] = nil
        blocked[gx * 100000 + gz] = nil
        local clearDist = clearanceField(nx, nz, blocked) -- AFTER the force-clears
        local grid = astarPath(cell, nx, nz, blocked, clearDist, sx, sz, gx, gz)
        if not grid then return nil, "no path" end
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
        return pts, counter.n
    end

    -- to the NEAREST CORNER of the field (user: start at a corner, not the
    -- center) — 4 studs inside the edge; arrive within 8 studs of it. The
    -- route comes from A* around everything parked on the farm and is
    -- RE-PLANNED about once a second while moving (user request: "find the
    -- most useful and quickest path every second"). REAL keys drive it
    -- (true physics — the old glide WHIPPED the towed tool); the glide
    -- stays only as the fallback when keys can't move the tractor.
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
        local startPos = tr:GetPivot().Position
        local legs, info = pathfindAround(startPos, goal, tr, impl)
        if not legs then
            log("⚠ pathfinding failed (" .. tostring(info) .. ") — driving straight at the corner")
            legs = { { goal.X, goal.Z } }
            info = 0
        else
            log(string.format("path: %d legs around %d obstacles", #legs - 1, info))
        end
        local useKeys = driveLegKeys ~= nil
        local li, lastPlan = 2, 0
        for pass = 1, 40 do
            if stopping() then return nil end
            local p = tr:GetPivot().Position
            -- re-plan ~once a second: parked tools shift around, and the
            -- fresh A* always re-picks the quickest current route
            if os.clock() - lastPlan > 1 then
                lastPlan = os.clock()
                local newLegs, n = pathfindAround(p, goal, tr, impl)
                if stopping() then return nil end
                if newLegs then
                    if info ~= n then
                        log(string.format("re-routed: %d legs around %d obstacles", #newLegs - 1, n))
                    end
                    legs, info = newLegs, n
                else
                    log("re-plan failed (" .. tostring(n) .. ") — keeping the last path")
                end
                li = 2 -- follow the fresh path from here (legs[1] = now)
            end
            local g = legs[math.min(li, #legs)]
            local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(g[1], 0, g[2])).Magnitude
            if d <= 6 then
                if li < #legs then
                    li += 1
                    g = legs[li]
                else
                    local dg = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
                    if dg <= 8 then return true, pass end
                end
            end
            if useKeys then
                local res = driveLegKeys(tr, seat, p, Vector3.new(g[1], p.Y, g[2]), 6)
                if res == nil then return nil end
                if res == false then
                    useKeys = false
                    log("keys didn't drive to the field — falling back to glide")
                end
            end
            if not useKeys then
                glideTractor(tr, Vector3.new(g[1], p.Y, g[2]))
            end
            task.wait(0.2)
        end
        local p = tr:GetPivot().Position
        local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude
        if d <= 8 then return true, 40 end
        return false, "still " .. math.floor(d) .. " studs short"
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
                        if tostring(cell.Stage or "?") == stage then
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

    -- scan every field of mine ONCE (nearest-first) and say what work is
    -- left: any bare cells (the PLOW's job) and any Plowed cells (the
    -- CULTIVATOR's job). Every field's real state is logged. A failed
    -- count read never disqualifies a field (unknown = work to try).
    local function probeWork(nearPos)
        local crops = findMyFields(nearPos)
        if #crops == 0 then return false, false end
        local needPlow, needCult = false, false
        for _, m in ipairs(crops) do
            local st = countStages(m.d)
            if st and st.total > 0 then
                local bare, plowedN = st.Empty or 0, st.Plowed or 0
                log(string.format("%s: %d bare, %d plowed, %d total cells",
                    m.d.Name, bare, plowedN, st.total))
                if bare > 0 then needPlow = true end
                if plowedN > 0 then needCult = true end
            else
                log(m.d.Name .. ": cell count unavailable — treating as needing work")
                needPlow, needCult = true, true
            end
        end
        return needPlow, needCult
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

    -- ▸ SEEDER STEP 1 — the seed check (user: "first thing from the seeder:
    --   we need to know if it has seeds in it or not. if it does stay in
    --   tractor. if it does not get out of the tractor"). Runs on EVERY
    --   loop run (user: "check everytime after the cultivating") — right
    --   after the cultivate pass AND on the idle path, with no field-need
    --   gate. Read-only: it never hitches/fills/drives (later steps, each
    --   when asked). Unreadable seed state counts as EMPTY (user's answer)
    --   → get out. F = ExitEquipment (context-key dump), pressed ONLY while
    --   seated — on foot the honest log is all it does (F next to the
    --   tractor would MOUNT it, the opposite of the intent).
    local function seedCheck(tr, hum)
        if stopping() then return end
        log("— seed check —")
        local seated = hum.SeatPart ~= nil
        local seeder, _, basis =
            findImplement("Planter", tr:GetPivot().Position, tr)
        local count, cap, kind
        if seeder then count, cap, kind = seederSeedState(seeder) end
        local exitIntent = seated and "getting out of the tractor"
            or "already out of the tractor"
        if seeder and count then
            local label = string.format("%d%s seeds%s%s", count,
                cap and ("/" .. cap) or "",
                kind and kind ~= "" and (" (" .. kind .. ")") or "",
                seeder:GetAttribute("InStorage") and ", in storage" or "")
            if count > 0 then
                log("seeder has " .. label .. (seated
                    and " — staying in the tractor"
                    or " — staying put (not in the tractor)"))
                return
            end
            log("seeder is EMPTY: " .. label .. " — " .. exitIntent)
        elseif not seeder then
            log("no seeder (Planter/KADL) found — seed state unknown — " ..
                exitIntent)
        else
            log("seed state unreadable (" .. tostring(basis) ..
                ") — treating as empty — " .. exitIntent)
        end
        if not seated then return end
        pressKey(Enum.KeyCode.F)
        task.wait(0.8)
        if stopping() then return end
        if hum.SeatPart then
            pressKey(Enum.KeyCode.F) -- context can take a beat
            task.wait(0.8)
            if stopping() then return end
        end
        log(hum.SeatPart and "⚠ F didn't exit — press F manually"
            or "✅ out of the tractor")
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
    local KEY_W, KEY_A, KEY_D =
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.D
    local keyHeld = {}
    local function setKey(key, down)
        if keyHeld[key] == down then return end
        keyHeld[key] = down
        VIM:SendKeyEvent(down, key, false, game)
    end
    local function releaseDriveKeys()
        setKey(KEY_W, false) setKey(KEY_A, false) setKey(KEY_D, false)
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
        local need0 = st0 and (st0[job.stage] or 0) or nil
        log(string.format("%s: %d-ring spiral, outside-in  (%s)", job.verb, rings,
            st0 and string.format("%d/%d cells still need %s", need0, st0.total, job.prog)
                or "cell read unavailable"))
        local realDrive -- nil = not probed yet; true = seat driving; false = glide
        local function doLeg(from, goal, tol)
            if stopping() then return nil end
            if realDrive ~= false then
                local res = driveLegKeys(tr, seat, from, goal, tol or 7)
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
            if sx > 0 then -- full closed lap
                map[#map + 1] = { pt( E * ax,  S * sx), 7, nil }   -- side +
                map[#map + 1] = { pt(-E * ax,  S * sx), 7, nil }   -- far end
                map[#map + 1] = { pt(-E * ax, -S * sx), 7, nil }   -- side -
                map[#map + 1] = { pt( E * ax, -S * sx), 7, nil }   -- near end
                map[#map + 1] = { pt( E * ax,  S * sx), 7, k + 1 } -- lap closed
            else -- final ring: one center-line pass from the entry end
                map[#map + 1] = { pt( E * (ax + 10), 0), 7, nil }
                map[#map + 1] = { pt(-E * ax, 0), 7, rings }
            end
        end
        dbgShow(tr, map, at) -- glowing bars on the field; bright = active leg
        for i, leg in ipairs(map) do
            dbgLeg(i)
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
        local missed = cellsAtStage(field, job.stage, baseCF, baseSize)
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
        local st1 = countStages(field)
        if st1 then
            local need1 = st1[job.stage] or 0
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

    -- the actual farming loop, run on its own thread by the toggle below.
    -- stopping() is checked at every wait/step so switching the toggle off
    -- kills the loop at its next step instead of letting it run on.
    local function runFarmingLoop()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then log("no character") return end
        local tr, dist, seat = findTractor()
        if not tr then log("tractor (ZM80) not found") return end

        -- ▸ step 0: what work is left? (ALL of my fields are scanned —
        --   including fields placed on my plots — and each field's real
        --   state is logged). Checked BEFORE mount so an idle run never
        --   even walks to the tractor. Failed counts never skip (unknown
        --   = work to try).
        local needPlow, needCult = probeWork(tr:GetPivot().Position)
        if not needPlow and not needCult then
            log("✅ every field is plowed and cultivated — nothing to do")
            -- the seed check runs EVERY loop run (user: "everytime") —
            -- even an idle run reports the seeder's seed load (read-only;
            -- the F press only ever happens while seated)
            seedCheck(tr, hum)
            return
        end
        if stopping() then return end

        -- ▸ step 1: mount (skipped when already in the tractor)
        if hum.SeatPart and not hum.SeatPart:IsDescendantOf(tr) then
            log("seated in another vehicle — stand up first")
            return
        end
        if not hum.SeatPart then
            if dist > 10 then
                log(string.format("moving to tractor (%.0f studs)…", dist))
                local reached = moveTo(seat.Position + Vector3.new(0, 3, 0))
                if stopping() then return end
                if not reached then
                    log("couldn't reach the tractor")
                    return
                end
                local root = char:FindFirstChild("HumanoidRootPart")
                dist = root and (seat.Position - root.Position).Magnitude or 0
            end
            if stopping() then return end
            if dist > 10 then log("still too far after moving") return end
            log("pressing F to mount…")
            pressKey(Enum.KeyCode.F)
            task.wait(0.7)
            if stopping() then return end
            if not (hum.SeatPart and hum.SeatPart:IsDescendantOf(tr)) then
                pressKey(Enum.KeyCode.F) -- context can take a moment to register
                task.wait(0.7)
            end
            if stopping() then return end
            if hum.SeatPart and hum.SeatPart:IsDescendantOf(tr) then
                log("✅ mounted " .. tr.Name)
            else
                log("F pressed but not seated — game didn't accept the enter")
                return
            end
        end

        logEquipment() -- always show the names so we can confirm the pick

        -- ONE implement pass: the nearest field still at the job's stage,
        -- hitch THAT job's implement (tug-verified, origin remembered),
        -- drive there, spiral sweep, then unhitch the tool WHERE IT CAME
        -- FROM. Used twice below: the plow (bare -> Plowed), then the
        -- cultivator (Plowed -> Cultivated) — same proven machinery.
        local function runPass(job)
            -- ▸ the TOUR (user request): walk EVERY field of mine, grouped
            --   by land type, nearest-first per group — work the fields
            --   that still need this job, log-and-skip the rest. One
            --   hitch for the whole tour; only mount-hitch when at least
            --   ONE field still needs the job.
            local groups = fieldTour(tr:GetPivot().Position)
            local anyNeed = false
            for _, grp in ipairs(groups) do
                for _, m in ipairs(grp.fields) do
                    local st = countStages(m.d)
                    -- unknown counts stay eligible (never skip on unknown)
                    if not st or st.total == 0 or (st[job.stage] or 0) > 0 then
                        anyNeed = true
                    end
                end
            end
            if not anyNeed then
                log("no field needs " .. job.verb .. " — pass skipped")
                return false
            end
            local impl, idist, basis = findImplement(job.typeName, tr:GetPivot().Position, tr)
            if not impl then
                log("no equipment with EquipmentType=" .. job.typeName .. " found — see list above")
                return false
            end
            if impl:GetAttribute("InStorage") then
                log(impl.Name .. " (the " .. job.verb .. ") is IN STORAGE — can't hitch it")
                log("pull it out of the Equipment Manager in-game first, then run again")
                return false
            end
            -- remember WHERE the tool was found: after the sweep it gets
            -- unhitched back at THIS spot (user: "unhitch the tools where
            -- they came from")
            local origin = impl:GetPivot().Position
            log(string.format("hitch target: %s (%.0f studs, by %s)",
                impl.Name, idist or 0, basis or "?"))

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

            -- ▸ the tour: every field, in order — skip the finished ones,
            --   sweep the rest; the tool stays hitched across the whole
            --   tour and goes home at the end
            for _, grp in ipairs(groups) do
                log("— " .. grp.typeName .. " land —")
                for _, m in ipairs(grp.fields) do
                    if stopping() then return false end
                    local st = countStages(m.d)
                    local need = st and (st[job.stage] or 0) or nil
                    if st and st.total > 0 and need == 0 then
                        log(string.format("SKIP %s — nothing needs %s (%d cells)",
                            m.d.Name, job.verb, st.total))
                    else
                        log(string.format("%s %s (%s land, %s)",
                            job.verb, m.d.Name, m.typeName,
                            need and (need .. " cells need it") or "state unknown"))
                        local arrived, how = driveToField(tr, m.d, hum.SeatPart, impl)
                        if stopping() then return false end
                        if not arrived then
                            log("couldn't reach " .. m.d.Name .. " (" .. tostring(how) .. ")")
                            return false
                        end
                        log("✅ reached " .. m.d.Name)
                        -- honest end-state: did the tool come along?
                        local tH, pH = findHitchPart(tr), findHitchPart(impl)
                        if tH and pH then
                            log(string.format("hitch gap at arrival: %.1f studs",
                                (tH.Position - pH.Position).Magnitude))
                        end
                        -- the spiral sweep — the game stages cells over as
                        -- the tool passes over them (same for every job)
                        local swept, why = sweepField(tr, m.d, hum.SeatPart, job)
                        if stopping() then return false end
                        if not swept then
                            log(job.verb .. " pass aborted (" .. tostring(why) .. ")")
                            return false
                        end
                    end
                end
            end

            -- unhitch the tool WHERE IT CAME FROM (the tour is done and
            -- it is still attached — an aborted pass leaves it hitched)
            if impl:IsDescendantOf(workspace) then
                dropImplementAtOrigin(tr, impl, origin)
            end
            return true
        end

        -- ▸ steps 3-6: the plow pass (bare cells -> Plowed)
        if needPlow then
            runPass(JOBS[1])
            if stopping() then return end
        end
        -- ▸ steps 7-10: the cultivate pass (Plowed -> Cultivated) — usually
        --   the same field the plow pass just finished
        runPass(JOBS[2])
        if stopping() then return end
        -- ▸ SEED CHECK (user: "check everytime after the cultivating") —
        --   has seeds → stay seated; empty/unreadable → F out. Read-only
        --   step 1: no fill, no hitch, no drive yet (later steps, asked
        --   for one at a time)
        seedCheck(tr, hum)
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
                    runFarmingLoop()
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
