--[[
  SPUD SELL PROBE — focused, one job.

  HOW TO RUN: sit in the HARVESTER, drive it onto the sell pad by hand,
  stop, then run this. It prints:
    1. every Markers.GotoLocations entry, nearest first (the sell spots)
    2. your ride, its EquipmentType and its load
    3. the collidable parts under/around you (the pad)
    4. context actions + which menus are open
    5. ONE Q press, then the menus and the load again
  Output goes to the console AND the clipboard.
]]

local out = {}
local function w(s) out[#out + 1] = s; print(s) end
local function finish()
    local text = table.concat(out, "\n")
    pcall(function() setclipboard(text) end)
    w("")
    w("Copied to clipboard. Paste it to me.")
end

pcall(function()
    local lp = game:GetService("Players").LocalPlayer
    local vim = game:GetService("VirtualInputManager")
    local ch = lp.Character
    local r0 = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not r0 then w("no HumanoidRootPart — respawn and try again") return end
    local pos = r0.Position

    w("=== 1. YOUR PLACE ===")
    w(string.format("you are at (%.0f, %.0f, %.0f)  seated=%s",
        pos.X, pos.Y, pos.Z, tostring(hum and hum.SeatPart ~= nil)))

    w("")
    w("=== 2. ALL GOTO MARKERS (nearest first) ===")
    local markers = workspace:FindFirstChild("Markers")
    local gotos = markers and markers:FindFirstChild("GotoLocations")
    if gotos then
        local list = {}
        for _, m in ipairs(gotos:GetChildren()) do
            local mp = m:IsA("BasePart") and m.Position or nil
            if mp then
                list[#list + 1] = { m.Name, mp, (mp - pos).Magnitude }
            end
        end
        table.sort(list, function(a, b) return a[3] < b[3] end)
        for _, e in ipairs(list) do
            w(string.format("  %-28s (%.0f, %.0f, %.0f)   %.0f studs",
                e[1], e[2].X, e[2].Y, e[2].Z, e[3]))
        end
    else
        w("  Markers.GotoLocations missing")
    end

    w("")
    w("=== 3. YOUR RIDE ===")
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
        w(string.format("  %s — EquipmentType=%s — load %s/%s",
            ride.Name, tostring(ride:GetAttribute("EquipmentType")),
            tostring(cur0), tostring(max0)))
    else
        w("  NOT SEATED. Sit in the harvester, park it on the pad, run again.")
    end

    w("")
    w("=== 4. PARTS AROUND YOU (the pad) ===")
    local parts, n = {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and (d.Position - pos).Magnitude < 30 then
            n += 1
            if #parts < 12 and d.CanCollide then
                parts[#parts + 1] = string.format("  %-26s %-9s (%.0f, %.0f, %.0f)  %.0fx%.0fx%.0f",
                    d.Name, d.ClassName, d.Position.X, d.Position.Y, d.Position.Z,
                    d.Size.X, d.Size.Y, d.Size.Z)
            end
        end
    end
    for _, l in ipairs(parts) do w(l) end
    w("  parts within 30 studs: " .. n)

    w("")
    w("=== 5. ACTIONS AND MENUS ===")
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    local views = pg and pg:FindFirstChild("GuiViews")
    local menus = views and views:FindFirstChild("Menus")
    local stores = views and views:FindFirstChild("Stores")
    local sellMenu = menus and menus:FindFirstChild("SellMenu")
    local depMenu = menus and menus:FindFirstChild("DepositMenu")
    local storeMenu = stores and stores:FindFirstChild("StoreMenu")
    local function st(g, nm)
        return string.format("%s=%s", nm, g and tostring(g.Enabled) or "missing")
    end
    local acts = {}
    pcall(function()
        for _, b in ipairs(pg.GuiViews.HUD.PCGP_ContextActions.Buttons:GetChildren()) do
            if b:IsA("GuiObject") and b.Visible then acts[#acts + 1] = b.Name end
        end
    end)
    w("  context actions: " .. (#acts > 0 and table.concat(acts, " · ") or "NONE"))
    w("  menus: " .. st(sellMenu, "SellMenu") .. "  " .. st(depMenu, "DepositMenu")
        .. "  " .. st(storeMenu, "StoreMenu"))

    w("")
    w("=== 6. ONE Q PRESS ===")
    vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
    task.wait(0.08)
    vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    task.wait(1.5)
    local cur1 = loadNow()
    w("  menus after Q: " .. st(sellMenu, "SellMenu") .. "  " .. st(depMenu, "DepositMenu"))
    w(string.format("  load %s -> %s", tostring(cur0), tostring(cur1)))
    w("  (a DROP means the pad sells on Q alone; no change means Q is not the sell)")
    if sellMenu and sellMenu.Enabled then
        local btns = {}
        for _, d in ipairs(sellMenu:GetDescendants()) do
            if d:IsA("GuiButton") and #btns < 14 then
                local t = ""
                pcall(function() t = d.Text end)
                if t ~= "" then btns[#btns + 1] = "'" .. t .. "'" end
            end
        end
        w("  SellMenu buttons: " .. (#btns > 0 and table.concat(btns, " · ") or "none"))
    end
    w("")
    w("=== 7. SAY THIS ===")
    w("  if no menu opened: what does the pad look like on screen?")
    w("  and what did you do to sell by hand the last time?")
end)

finish()
