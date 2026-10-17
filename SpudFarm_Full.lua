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
            tween.Completed:Wait()
            return true
        end
        -- VFly: pure CFrame steps, NO physics objects. (BodyVelocity made the
        -- physics solver fight the humanoid → lag spikes + server rubber-band)
        for _ = 1, 200 do -- ~10s max
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

    local function findPlow(nearPos, tractorModel)
        local folder = equipmentFolder()
        local best, bestDist
        for _, d in ipairs(folder and folder:GetChildren() or {}) do
            if d:IsA("Model") and d ~= tractorModel
                and not d.Name:lower():find("trailer", 1, true) then
                local dist = (d:GetPivot().Position - nearPos).Magnitude
                if not bestDist or dist < bestDist then
                    best, bestDist = d, dist
                end
            end
        end
        return best, bestDist
    end

    -- the VehicleHUD shows the HITCHED implement as Secondary EquipmentName
    local function hitchedImplementName()
        local ok, v = pcall(function()
            return LocalPlayer.PlayerGui
                .GuiViews.HUD.VehicleHUD.HUD.Content
                .EquipmentInfo.Secondary.EquipmentName
        end)
        if ok and v and v:IsA("TextLabel") then
            local t = tostring(v.Text):gsub("^%s+", ""):gsub("%s+$", "")
            if t ~= "" then return t end
        end
        return nil
    end

    local function logEquipment()
        local folder = equipmentFolder()
        if not folder then
            log("Objects.Equipment folder not found")
            return
        end
        log("equipment on your farm:")
        for _, d in ipairs(folder:GetChildren()) do
            if d:IsA("Model") then log("  · " .. d.Name) end
        end
    end

    local function glideTractor(tr, targetPos)
        local startPivot = tr:GetPivot()
        local rot = startPivot - startPivot.Position -- rotation-only CFrame
        local endCF = CFrame.new(targetPos.X, startPivot.Position.Y, targetPos.Z) * rot
        local dist = (Vector3.new(startPivot.Position.X, 0, startPivot.Position.Z)
            - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
        if dist < 0.5 then return end
        local steps = math.clamp(math.floor(dist / 1.5), 3, 40)
        for i = 1, steps do
            tr:PivotTo(startPivot:Lerp(endCF, i / steps))
            task.wait(0.05)
        end
    end

    -- one hitch attempt: press X once → tug forward 5 studs → did the plow follow?
    local function attemptHitch(tr, plow)
        pressKey(Enum.KeyCode.X)
        task.wait(0.6)
        local before = plow:GetPivot().Position
        local pivot = tr:GetPivot()
        local fwd = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
        if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
        glideTractor(tr, pivot.Position + fwd.Unit * 5)
        task.wait(0.5)
        local moved = (plow:GetPivot().Position - before).Magnitude
        return moved > 2.5, moved
    end

    Tabs.Farm:CreateButton({
        Title = "farming loop",
        Callback = function()
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
                    if not moveTo(seat.Position + Vector3.new(0, 3, 0)) then
                        log("couldn't reach the tractor")
                        return
                    end
                    local root = char:FindFirstChild("HumanoidRootPart")
                    dist = root and (seat.Position - root.Position).Magnitude or 0
                end
                if dist > 10 then log("still too far after moving") return end
                log("pressing F to mount…")
                pressKey(Enum.KeyCode.F)
                task.wait(0.7)
                if not (hum.SeatPart and hum.SeatPart:IsDescendantOf(tr)) then
                    pressKey(Enum.KeyCode.F) -- context can take a moment to register
                    task.wait(0.7)
                end
                if hum.SeatPart and hum.SeatPart:IsDescendantOf(tr) then
                    log("✅ mounted " .. tr.Name)
                else
                    log("F pressed but not seated — game didn't accept the enter")
                    return
                end
            end

            -- ▸ step 3: hitch the plow
            local tractorPos = tr:GetPivot().Position
            local plow, pdist = findPlow(tractorPos, tr)

            -- if the HUD already lists a hitched implement, X would UNHITCH it
            local attached = hitchedImplementName()
            if attached then
                log("implement already hitched (HUD: " .. attached .. ") — nothing to do")
                log("press X in-game to unhitch first, then run again")
                return
            end

            if not plow then
                log("plow not found in Objects.Equipment")
                logEquipment()
                return
            end
            log("hitch target: " .. plow.Name .. string.format(" (%.0f studs)", pdist or 0))
            if pdist > 6 then
                local plowPos = plow:GetPivot().Position
                local dir = tractorPos - plowPos
                dir = Vector3.new(dir.X, 0, dir.Z)
                if dir.Magnitude < 0.5 then dir = Vector3.new(0, 0, -1) end
                local standOff = plowPos + dir.Unit * 6
                log(string.format("gliding tractor to plow (%.0f studs)…", pdist))
                glideTractor(tr, standOff)
                task.wait(0.4)
            end

            for attempt = 1, 2 do
                if attempt > 1 then
                    local plowPos = plow:GetPivot().Position
                    local dir = tr:GetPivot().Position - plowPos
                    dir = Vector3.new(dir.X, 0, dir.Z)
                    if dir.Magnitude < 0.5 then dir = Vector3.new(0, 0, -1) end
                    glideTractor(tr, plowPos + dir.Unit * 6) -- failed tug moved us away
                    task.wait(0.4)
                end
                local hooked, moved = attemptHitch(tr, plow)
                if hooked then
                    log("✅ hitched the plow")
                    return
                end
                log(string.format("hitch attempt %d/2: plow didn't follow (%.1f studs)", attempt, moved))
            end
            log("couldn't hitch — send me this line")
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
