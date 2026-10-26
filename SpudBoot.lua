--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD BOOT — loads SpudFarm_Full.lua and says what happened ON SCREEN
═══════════════════════════════════════════════════════════════════════════
  Why: the console is not always visible (mobile / MuMu), so a silent failure
  looked like "it's not loading". This little file downloads the real script,
  compiles it and runs it, and puts every step in a small panel:

      downloading…  →  460019 bytes  →  compiling…  →  compiled
      →  running…  →  started (v1.6)   or   ERROR: <the exact message>

  HOW TO USE:
    loadstring(game:HttpGet(
      "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudBoot.lua?t="
      .. os.time()))()

  Paste that ONE line. If something fails, the panel shows the message and also
  copies it to your clipboard, so it can be pasted straight into chat.
  The panel closes itself once the farm script is running.
═══════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
if not LP then
    local okWait, who = pcall(function() return Players.PlayerAdded:Wait() end)
    LP = okWait and who or nil
end

local RAW = "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua"

local function findParent()
    for _ = 1, 20 do
        local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
        if pg then return pg end
        task.wait(0.25)
    end
end

local parent = findParent()
if not parent then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "SPUD BOOT", Text = "no PlayerGui yet — rejoin and run it again", Duration = 8,
        })
    end)
    return
end

local sg = Instance.new("ScreenGui")
sg.Name = "SpudBootPanel"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 2147483000
sg.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300, 150)
frame.Position = UDim2.fromOffset(14, 14)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = sg

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 70, 82)
stroke.Thickness = 1
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 18)
title.Position = UDim2.fromOffset(8, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Text = "SPUD BOOT"
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 16)
status.Position = UDim2.fromOffset(8, 25)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(170, 200, 170)
status.Text = "starting…"
status.Parent = frame

-- the details box doubles as the error surface: selectable text, no scrolling
-- needed for short messages, and long ones still fit when wrapped
local detail = Instance.new("TextBox")
detail.Size = UDim2.new(1, -16, 0, 74)
detail.Position = UDim2.fromOffset(8, 43)
detail.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
detail.BackgroundTransparency = 0
detail.BorderSizePixel = 0
detail.Font = Enum.Font.Code
detail.TextSize = 10
detail.TextWrapped = true
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.TextYAlignment = Enum.TextYAlignment.Top
detail.TextColor3 = Color3.fromRGB(210, 210, 220)
detail.Text = ""
detail.TextEditable = false
detail.ClearTextOnFocus = false
detail.Parent = frame

local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 5)
rc.Parent = detail

local function mkButton(text, x, color, onClick)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(140, 22)
    b.Position = UDim2.fromOffset(8 + x, 120)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(245, 245, 250)
    b.Text = text
    b.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = b
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(onClick)
        if not ok then
            status.Text = "button error"
            detail.Text = tostring(err)
        end
    end)
    return b
end

local boot -- filled in below; the buttons below close over it

local function setStatus(text, color)
    status.Text = tostring(text)
    status.TextColor3 = color or Color3.fromRGB(170, 200, 170)
end

local function complain(text)
    setStatus("FAILED — see the box", Color3.fromRGB(240, 130, 130))
    local copied = pcall(function() setclipboard(tostring(text)) end)
    detail.Text = tostring(text)
    if copied then detail.Text = detail.Text .. "\n\n(copied to clipboard)" end
end

local function fetch(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res > 1000 then return res end
    local why = ok and ("only " .. tostring(#tostring(res)) .. " bytes came back") or tostring(res)
    return nil, why
end

boot = function()
    setStatus("downloading…")
    detail.Text = RAW

    -- the cache-buster first, then the plain URL (some executors strip queries)
    local src, why = fetch(RAW .. "?t=" .. os.time())
    if not src then
        setStatus("retrying without the cache-buster…")
        local src2, why2 = fetch(RAW)
        if src2 then src, why = src2, nil else why = (why or "") .. " / " .. (why2 or "") end
    end
    if not src then
        complain("download failed:\n" .. tostring(why)
            .. "\n\nOpen this in a browser to check it exists:\n" .. RAW)
        return
    end

    local ver = tostring(src):match('VERSION%s*=%s*"([^"]+)"') or "?"
    setStatus(string.format("downloaded %d bytes — compiling…", #src))
    detail.Text = string.format("%d bytes\nbuild: %s", #src, ver)

    local loader = loadstring or load
    if type(loader) ~= "function" then
        complain("this executor has no loadstring/load, so the file cannot be run")
        return
    end
    local fn, err = loader(src)
    if not fn then
        complain("compile error:\n" .. tostring(err)
            .. "\n\n" .. string.format("(%d bytes downloaded)", #src))
        return
    end

    setStatus("compiled — running…")
    local okRun, runErr = pcall(fn)
    if not okRun then
        complain("runtime error:\n" .. tostring(runErr))
        return
    end

    setStatus("started — closing this panel", Color3.fromRGB(150, 230, 150))
    detail.Text = string.format("%d bytes\nbuild: %s\nrunning — panel closes in 4 s", #src, ver)
    task.wait(4)
    pcall(function() sg:Destroy() end)
end

mkButton("Run it again", 0, Color3.fromRGB(46, 92, 138), function()
    boot()
end)

mkButton("Close panel", 148, Color3.fromRGB(72, 72, 84), function()
    pcall(function() sg:Destroy() end)
end)

task.spawn(function()
    local ok, err = pcall(boot)
    if not ok then complain("boot error:\n" .. tostring(err)) end
end)
