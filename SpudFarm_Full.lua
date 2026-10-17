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

    -- ▸ AUTO-FARM STEP 2: movement (VFly = BodyVelocity fly + snap,
    --   Tween = stepped glide). Nothing else uses this yet.
    local Move = { Mode = "Tween", Speed = 200 }

    local function moveTo(target)
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        if Move.Mode == "Tween" then
            local dur = math.clamp((root.Position - target).Magnitude / Move.Speed, 0.05, 8)
            local tween = game:GetService("TweenService"):Create(
                root,
                TweenInfo.new(dur, Enum.EasingStyle.Linear),
                { CFrame = CFrame.new(target) })
            tween:Play()
            local deadline = os.clock() + dur + 1
            while tween.Playing and os.clock() < deadline do
                if stopping() then
                    tween:Cancel()
                    return false
                end
                task.wait(0.05)
            end
            return true
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
    -- attribute (Tractor/Plow/Planter/Cultivator/Harvester/Truck/Transport).
    -- The plow = the one with EquipmentType "Plow" (S4204 for this user, but
    -- match by TYPE so it survives selling/buying different models).
    local function findPlow(nearPos, tractorModel)
        local folder = equipmentFolder()
        local best, bestDist
        for _, d in ipairs(folder and folder:GetChildren() or {}) do
            if d:IsA("Model") and d ~= tractorModel
                and d:GetAttribute("EquipmentType") == "Plow" then
                local dist = (d:GetPivot().Position - nearPos).Magnitude
                if not bestDist or dist < bestDist then
                    best, bestDist = d, dist
                end
            end
        end
        return best, bestDist
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
    -- part, rotating with the plow — physical line-up, no stand-off guessing
    local function lineUpHitch(tr, plow)
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
        for _ = 1, 6 do -- multi-pass glide if far (never snap whole-map)
            local cur = tr:GetPivot().Position
            local tgt = newPivot.Position
            if (Vector3.new(cur.X, 0, cur.Z) - Vector3.new(tgt.X, 0, tgt.Z)).Magnitude < 1 then
                break
            end
            glideTractor(tr, tgt)
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

    -- dump §24: fields live in Objects.Fields — Configurations.Owner marks
    -- whose each is; Configurations.FieldType says WHAT kind ("Field" =
    -- crop field; other types exist). Pick ONLY a crop field of MY OWN
    -- (nearest), warn if my only field is another type, NEVER a stranger's.
    -- Every candidate is logged so a wrong pick is visible, not silent.
    local function findMyField(nearPos)
        local objects = workspace:FindFirstChild("Objects")
        local fields = objects and objects:FindFirstChild("Fields")
        local seen, mine = {}, {}
        for _, d in ipairs(fields and fields:GetChildren() or {}) do
            if d:IsA("Model") then
                local cfg = d:FindFirstChild("Configurations")
                local owner = cfg and cfg:FindFirstChild("Owner")
                local ftype = cfg and cfg:FindFirstChild("FieldType")
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
        if #seen > 0 then
            log("fields here: " .. table.concat(seen, "; "))
        end
        local best, bestDist, bestType
        for _, m in ipairs(mine) do -- my CROP fields first (nearest wins)
            if m.typeName == "Field" and (not bestDist or m.dist < bestDist) then
                best, bestDist, bestType = m.d, m.dist, m.typeName
            end
        end
        if not best then -- none of mine is type Field: fall back to my nearest
            for _, m in ipairs(mine) do
                if not bestDist or m.dist < bestDist then
                    best, bestDist, bestType = m.d, m.dist, m.typeName
                end
            end
            if best then
                log("⚠ none of your fields is type Field — using your nearest, type " .. bestType)
            end
        end
        return best, bestType
    end

    -- forward-declared so driveToField below can use it (defined later)
    local driveLegKeys

    -- to the NEAREST CORNER of the field (user: start at a corner, not the
    -- center) — 4 studs inside the edge; arrive within 6 studs of it. Drives
    -- with REAL keys now: the old glide (PivotTo steps at ~30 studs/s) WHIPPED
    -- the hitched plow — video showed it bouncing/tumbling the whole transit.
    -- Glide stays only as the fallback if keys can't move the tractor.
    local function driveToField(tr, field, seat)
        local okB, cf, sz = pcall(function() return field:GetBoundingBox() end)
        if not (okB and cf) then return false, "no bounds" end
        local cx, cz = cf.Position.X, cf.Position.Z
        local hx, hz = math.max(sz.X / 2 - 4, 2), math.max(sz.Z / 2 - 4, 2)
        local p0 = tr:GetPivot().Position
        local goal = Vector3.new(
            cx + (p0.X >= cx and hx or -hx), 0,  -- nearest corner,
            cz + (p0.Z >= cz and hz or -hz))      -- 4 studs inside
        log(string.format("field corner target: (%.0f, %.0f)", goal.X, goal.Z))
        local useKeys = driveLegKeys ~= nil
        for pass = 1, 8 do
            if stopping() then return nil end
            local p = tr:GetPivot().Position
            local d = (Vector3.new(p.X, 0, p.Z) - goal).Magnitude
            if d <= 6 then return true, pass end
            if useKeys then
                local res = driveLegKeys(tr, seat, goal, 6)
                if res == nil then return nil end
                if res == true then return true, pass end
                useKeys = false
                log("keys didn't drive to the field — falling back to glide")
            end
            glideTractor(tr, Vector3.new(goal.X, p.Y, goal.Z))
            task.wait(0.2)
        end
        local p = tr:GetPivot().Position
        local d = (Vector3.new(p.X, 0, p.Z) - goal).Magnitude
        if d <= 6 then return true, 8 end
        return false, "still " .. math.floor(d) .. " studs short"
    end

    -- honest per-cell read via the game's OWN FieldHelper module (dump §26:
    -- require() works even though Source is blocked) — returns how many
    -- cells currently have Stage == "Plowed", out of the field's total.
    local function countPlowedCells(field)
        local ok, plowed, total = pcall(function()
            local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            local F = mods and mods:FindFirstChild("FieldHelper")
            assert(F, "FieldHelper missing")
            F = require(F)
            assert(type(F.GetCells) == "function", "GetCells missing")
            local cells = F.GetCells(field)
            assert(type(cells) == "table", "GetCells returned no table")
            local pl, tot = 0, 0
            for _, cell in pairs(cells) do
                tot += 1
                if type(cell) == "table" and cell.Stage == "Plowed" then
                    pl += 1
                end
            end
            return pl, tot
        end)
        if ok then return plowed, total end
        return nil
    end

    -- "actual driving": HOLD REAL KEYS (WASD via VirtualInputManager) while
    -- seated — the game's own vehicle controller reads them through its
    -- normal input pipeline, so the tractor accelerates and swings through
    -- turns with true physics. (Setting seat.Throttle directly was PROVEN
    -- ignored: the seat's control script overwrites those properties from
    -- player input every frame.)
    -- v4 anti-orbit steering (v3 circled forever at row ends: full-speed
    -- turn radius > arrival tolerance → orbit around the goal):
    --   · turn strength scales with how far off-heading we are (full turn
    --     past 0.5, 2/3 duty past 0.28, feather otherwise) — no overshoot
    --     oscillation, no wheel chatter
    --   · throttle duty cut to a creep while turning and near the goal
    --   · close-enough acceptance: within 16 studs after ~15 s = done
    --     (plow overlap covers the shortfall; the cell counter is truth)
    -- Forward = low-pass-smoothed travel direction (seat facing only as
    -- the startup fallback) so jitter can't flip the steering.
    -- v5: NO REVERSE EVER — backing with a trailed implement JACKKNIFES it
    -- into the tractor (video: plow wedged sideways against the tractor,
    -- then the tractor could only wander). Turnarounds are wide forward
    -- arcs at creep speed. Cruise duty cut to 1/2 overall.
    -- Returns true=arrived/accepted, false=keys didn't drive (caller falls
    -- back to the glide), nil=killed.
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

    driveLegKeys = function(tr, seat, goal, tol)
        if not seat then return false end -- not seated: keys would do nothing
        tol = tol or 7
        local startPos = tr:GetPivot().Position
        local prevPos, fwd = startPos, nil
        for tick = 1, 350 do -- ~42 s cap per leg (0.12 s ticks)
            if stopping() then releaseDriveKeys() return nil end
            local pos = tr:GetPivot().Position
            local to = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
            local dist = to.Magnitude
            if dist <= tol then break end
            -- smoothed travel direction (low-pass: jitter can't flip steering)
            local move = Vector3.new(pos.X - prevPos.X, 0, pos.Z - prevPos.Z)
            if move.Magnitude > 0.5 then
                local m = move.Unit
                fwd = fwd and (fwd * 0.7 + m * 0.3).Unit or m
            end
            prevPos = pos
            if not fwd then
                local look = seat.CFrame.LookVector
                fwd = Vector3.new(look.X, 0, look.Z)
                fwd = fwd.Magnitude > 0.1 and fwd.Unit or Vector3.new(0, 0, -1)
            end
            local right = Vector3.new(-fwd.Z, 0, fwd.X)
            local d = to.Unit
            local side = d:Dot(right) -- >0 = goal is off to the right
            local sharp = math.abs(side) > 0.5
            local turnSlot, thrSlot = tick % 3, tick % 3
            -- goal BEHIND = wide forward U-turn at creep (never reverse)
            -- proportional steering: hard turn far off-heading, feather near
            local want = side > 0.18 and 1 or (side < -0.18 and -1 or 0)
            local duty = sharp and 3 or (math.abs(side) > 0.28 and 2 or 1)
            setKey(KEY_D, want == 1 and turnSlot < duty)
            setKey(KEY_A, want == -1 and turnSlot < duty)
            -- throttle: gentle cruise far out, creep in turns and up close
            local tDuty = (sharp or dist <= 14) and 1 or 2
            setKey(KEY_W, thrSlot < tDuty)
            task.wait(0.12)

            if tick == 15 then -- ~1.8 s probe: keys must produce motion
                local moved = (Vector3.new(pos.X, 0, pos.Z)
                    - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
                if moved < 1 and dist > tol + 4 then
                    releaseDriveKeys()
                    return false
                end
            elseif tick == 125 and dist < 16 then -- ~15 s: close enough
                if dist > 10 then
                    log(string.format("row end ~%.0f studs short — accepting (plow overlap covers it)", dist))
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
    local function plowTheField(tr, field, seat)
        local okB, cf, sz = pcall(function() return field:GetBoundingBox() end)
        if not (okB and cf) then return false, "no bounds" end
        local c = cf.Position
        local alongX = sz.X <= sz.Z
        local driveHalf = (alongX and sz.X or sz.Z) / 2 + 6 -- +6: plow trails
        local rowSpan   = (alongX and sz.Z or sz.X)
        local rows = math.max(math.floor(rowSpan / 10 + 0.5), 1)
        local function pt(along, step)
            if alongX then return Vector3.new(c.X + along, 0, c.Z + step) end
            return Vector3.new(c.X + step, 0, c.Z + along)
        end
        local before, total = countPlowedCells(field)
        log(string.format("plowing: %d rows × %d studs  (%s)", rows, driveHalf * 2,
            before and string.format("%d/%d cells already Plowed", before, total)
                or "cell read unavailable"))
        local realDrive -- nil = not probed yet; true = seat driving; false = glide
        local function doLeg(goal, tol)
            if stopping() then return nil end
            if realDrive ~= false then
                local res = driveLegKeys(tr, seat, goal, tol or 7)
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
        -- snake: start on the tractor's OWN end and row, alternate ends each
        -- row. Every leg is aligned with the field — a short crossover at the
        -- row end, then the full row drive. (v4 cut diagonals between far
        -- ends → triangular unplowed gaps, video-confirmed.)
        local p0 = tr:GetPivot().Position
        local endSide = ((alongX and p0.X or p0.Z) >= (alongX and c.X or c.Z)) and 1 or -1
        local rowSide = ((alongX and p0.Z or p0.X) >= (alongX and c.Z or c.X)) and 1 or -1
        for r = 1, rows do
            local row = rowSide * (rowSpan / 2 - 5) - rowSide * (r - 1) * 10
            if not doLeg(pt(endSide * driveHalf, row), 4) then return nil end -- crossover/start
            if not doLeg(pt(-endSide * driveHalf, row)) then return nil end   -- the row itself
            endSide = -endSide
        end
        if stopping() then return nil end
        local after, tot2 = countPlowedCells(field)
        if after then
            log(string.format("sweep done: %d/%d cells Plowed", after, tot2))
            if tot2 > 0 and after >= tot2 then
                log("✅ the whole field is plowed")
            elseif before and after <= before then
                log("cell count did NOT change — drive-over isn't plowing (next: the plow remote)")
            else
                log("some cells left — run the loop again (plow may be narrower than one cell)")
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

        -- ▸ step 3: hitch the plow (or PROVE it's already hitched)
        logEquipment() -- always show the names so we can confirm the pick
        local tractorPos = tr:GetPivot().Position
        local plow, pdist = findPlow(tractorPos, tr)

        if not plow then
            log("no equipment with EquipmentType=Plow found — see list above")
            return
        end
        if plow:GetAttribute("InStorage") then
            log(plow.Name .. " (the plow) is IN STORAGE — can't hitch it")
            log("pull it out of the Equipment Manager in-game first, then run again")
            return
        end
        log("hitch target: " .. plow.Name .. string.format(" (%.0f studs)", pdist or 0))

        -- the HUD label alone can be stale (dump-proven: it said "S4204"
        -- while the hitch points sat 9.5 studs apart) — if it claims a
        -- hitch, PROVE it with a tug: plow must follow. Pass → skip
        -- straight to drive. Fail → treat as unhitched, hitch normally.
        local didHitch = false
        local attached = hitchedImplementName()
        if attached then
            log("HUD says hitched (" .. attached .. ") — tug-verifying…")
            local before = plow:GetPivot().Position
            local pivot = tr:GetPivot()
            local fwd = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
            if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
            glideTractor(tr, pivot.Position + fwd.Unit * 4)
            task.wait(0.4)
            if stopping() then return end
            local followed = (plow:GetPivot().Position - before).Magnitude
            if followed > 2 then
                log(string.format("✅ tug passed (%.1f studs) — plow is attached, skipping hitch", followed))
                didHitch = true
            else
                log(string.format("label stale — plow didn't follow (%.1f studs) — hitching first", followed))
            end
        end

        if not didHitch then
            -- user's plan: physical line-up of the hitch PARTS (fallback:
            -- align+creep), then the game's Hitch prompt gates the X press.
            -- Retry until the tug-test passes.
            local attempt, forceCreep = 0, false
            while not stopping() do
                attempt += 1
                if not (plow and plow:IsDescendantOf(workspace)) then
                    log("plow disappeared (despawned?) — stopping retries")
                    return
                end
                local backOff = math.min((attempt - 1) * 1.5, 6) -- widen stance on retries
                local lined = false
                if not forceCreep then
                    lined = lineUpHitch(tr, plow)
                end
                if stopping() then return end
                if not lined then
                    alignToPlow(tr, plow, backOff)
                end
                if stopping() then return end
                local crept = creepUntilPrompt(tr, 20, 1) -- up to 20 studs forward
                if stopping() then return end
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
                    local hooked, moved = attemptHitch(tr, plow)
                    if stopping() then return end
                    if hooked then
                        log(string.format("✅ hitched the plow (attempt %d)", attempt))
                        didHitch = true
                        break
                    end
                    log(string.format("attempt %d: X pressed but plow didn't follow (%.1f studs) — retrying",
                        attempt, moved))
                end
            end
            if not didHitch then return end -- killed (toggle off) or dead-ended
        end

        -- ▸ step 4: drive to the field (dump §24: Objects.Fields.Field,
        --   Configurations.Owner = oksimba_1, bounds 50×100 near my plot)
        local field, ftype = findMyField(tr:GetPivot().Position)
        if not field then
            log("no field of yours in Objects.Fields — nothing to drive to")
            return
        end
        log("driving to field: " .. field.Name .. " (type " .. tostring(ftype) .. ")")
        local arrived, how = driveToField(tr, field, hum.SeatPart)
        if stopping() then return end
        if arrived then
            log("✅ reached the field" .. (type(how) == "number"
                and string.format(" (pass %d)", how) or ""))
        else
            log("couldn't reach the field (" .. tostring(how) .. ")")
            return
        end
        -- honest end-state: did the plow come along?
        local tH, pH = findHitchPart(tr), findHitchPart(plow)
        if tH and pH then
            log(string.format("hitch gap at arrival: %.1f studs", (tH.Position - pH.Position).Magnitude))
        end

        -- ▸ step 5: plow the field — serpentine sweep of every cell
        --   (the game's client plows cells the implement passes over)
        local plowed, why = plowTheField(tr, field, hum.SeatPart)
        if stopping() then return end
        if not plowed then
            log("plow pass aborted (" .. tostring(why) .. ")")
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
        Content = "rebuilt on Fluent — skeleton only (no game features yet)",
        Duration = 6,
    })
    log("loaded — " .. VERSION)
    log("GUI: Fluent Renewed · RIGHT SHIFT hides the window")
    log("no game features yet; they return one at a time")
end)

if not okBuild then
    warn("[spud] GUI build error: " .. tostring(errBuild))
    plainNotify("SPUD FARM", "GUI build error: " .. tostring(errBuild):sub(1, 130))
end
