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
    local Move = { Mode = "VFly", Speed = 200 }

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
        -- VFly
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.zero
        bv.Parent = root
        local arrived = false
        for _ = 1, 200 do -- ~10s max
            local off = target - root.Position
            if off.Magnitude < 2.5 then arrived = true break end
            bv.Velocity = off.Unit * math.min(Move.Speed, off.Magnitude * 8)
            root.CFrame = CFrame.lookAt(
                root.Position,
                Vector3.new(target.X, root.Position.Y, target.Z))
            task.wait(0.05)
        end
        bv:Destroy()
        return arrived
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

    Tabs.Farm:CreateButton({
        Title = "🚜 Mount tractor",
        Callback = function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then log("no character") return end
            if hum.SeatPart then log("already seated") return end
            local tr, dist, seat = findTractor()
            if not tr then log("tractor (ZM80) not found") return end
            if dist > 10 then
                log(string.format("moving to tractor (%.0f studs)…", dist))
                if not moveTo(seat.Position + Vector3.new(0, 3, 0)) then
                    log("couldn't reach the tractor")
                    return
                end
                _, dist = findTractor()
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
        Default = "VFly",
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
