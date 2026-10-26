--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD REMOTE PROBE — what does the game actually SEND? (READ-ONLY)
═══════════════════════════════════════════════════════════════════════════
  Why: "make it EXTRA fast with remotes". To call a remote directly the script
       must know its exact name AND its exact arguments. Guessing either one
       either does nothing or fires garbage at the server, so this probe just
       WATCHES the calls the game itself makes while you do the job by hand.
       It never fires, repeats or alters anything: it only records.

  HOW TO USE (MuMu + Delta):
    1. Spawn in, go to the plot with milk jugs and a liquid truck/trailer.
    2. Execute this file. It starts recording immediately and prints a banner.
    3. Do these BY HAND, in this order, pausing a second between them:
         a) pick up ONE milk jug            (Carry / E)
         b) walk to the truck, press Fill   (V), once
         c) milk ONE cow                    (whatever key the game shows)
         d) drop/put back whatever you hold
       Optional: run  spudRemoteMark("carry")  /  spudRemoteMark("fill")  /
       spudRemoteMark("milk")  right before each step so the report is grouped.
    4. Run  spudRemoteStop()  in the executor.
       → it stops recording, prints the report, uploads it and copies the link
         to your clipboard. Send the link back.

  If the executor has no http request the whole report is copied to the
  clipboard instead. The report contains public game structure + your
  username: treat the link like the dump itself.
═══════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local records = {}      -- chronological: {kind="call"|"mark", ...}
local MAXREC = 1500
local hooked, hookHow, hookErr = false, "none", nil
local original      -- the namecall we replaced (for the restore)
local gui, guiStatus -- the little panel

function spudRemoteClosePanel()
    if gui then pcall(function() gui:Destroy() end) end
    gui, guiStatus = nil, nil
end

-- ▸ INSIDE THE HOOK: PROPERTY READS ONLY. GetFullName, FindFirstChild and
--   GetChildren are themselves NAMECALLS, and calling one while a namecall is
--   being intercepted can leave the executor's cached method name on the
--   wrong call — that is what made every button in the game stop responding.
--   Name/Parent are plain property reads, so they are safe here.
local function pathOfInst(v)
    local parts = {}
    local cur = v
    for _ = 1, 14 do
        if not cur or cur == game then break end
        parts[#parts + 1] = tostring(cur.Name)
        cur = cur.Parent
    end
    local out = {}
    for i = #parts, 1, -1 do out[#out + 1] = parts[i] end
    return table.concat(out, ".")
end

local function short(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        local s = v
        if #s > 90 then s = s:sub(1, 87) .. "…" end
        return string.format("%q", s)
    elseif t == "Instance" then
        return pathOfInst(v)
    elseif t == "table" then
        if depth >= 2 then return "{…}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 6 then parts[#parts + 1] = "…" break end
            parts[#parts + 1] = tostring(k) .. "=" .. short(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Vector3" then
        return string.format("Vector3(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
    elseif t == "number" then
        return tostring(v)
    else
        local s = tostring(v)
        if #s > 90 then s = s:sub(1, 87) .. "…" end
        return s
    end
end

local function here()
    local ch = LP.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local links = ch and ch:FindFirstChild("CarryLinks")
    local held = links and #links:GetChildren() or 0
    local p = root and root.Position
    if not p then return "pos=? held=" .. tostring(held) end
    return string.format("pos=(%.0f, %.0f, %.0f) held=%d", p.X, p.Y, p.Z, held)
end

local function pushCall(self, method, ...)
    if #records >= MAXREC then return end
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do parts[i] = short(args[i]) end
    local nm = (typeof(self) == "Instance") and pathOfInst(self) or tostring(self)
    records[#records + 1] = {
        kind = "call", name = nm, method = method,
        args = table.concat(parts, ", "),
        n = args.n, at = os.clock(),
    }
end

--------------------------------------------------------------- hooks
local function installRaw()
    local gm = getrawmetatable(game)
    if not gm then error("getrawmetatable(game) returned nil") end
    local old = gm.__namecall
    if type(old) ~= "function" then error("__namecall is not a function") end
    local wrap = newcclosure or function(f) return f end
    local function hook(self, ...)
        -- read the method FIRST, then record with property reads only, then
        -- hand the call straight to the original: a hook that does anything
        -- else can swallow the call and freeze every button in the game
        local method = getnamecallmethod and getnamecallmethod() or nil
        if method == "FireServer" or method == "InvokeServer" then
            pcall(pushCall, self, method, ...)
        end
        return old(self, ...)
    end
    pcall(function() setreadonly(gm, false) end)
    gm.__namecall = wrap(hook)
    pcall(function() setreadonly(gm, true) end)
    original = { kind = "raw", mt = gm, old = old }
end

local function installHookMeta()
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or nil
        if method == "FireServer" or method == "InvokeServer" then
            pcall(pushCall, self, method, ...)
        end
        return old(self, ...)
    end)
    original = { kind = "hookmeta", old = old }
end

if type(getnamecallmethod) ~= "function" then
    hookErr = "this executor has no getnamecallmethod — the call list will be empty, the remote INVENTORY below still works"
else
    local ok = pcall(installRaw)
    if ok then
        hooked, hookHow = true, "getrawmetatable"
    else
        local ok2, err2 = pcall(installHookMeta)
        if ok2 then
            hooked, hookHow = true, "hookmetamethod"
        else
            hookErr = tostring(err2)
        end
    end
end

local function restore()
    if not hooked then return end
    pcall(function()
        if original.kind == "raw" then
            pcall(function() setreadonly(original.mt, false) end)
            original.mt.__namecall = original.old
            pcall(function() setreadonly(original.mt, true) end)
        else
            -- hookmetamethod has no restore helper on most executors; putting
            -- the original back by hand is the best that can be done safely
            pcall(function()
                local gm = getrawmetatable(game)
                if gm then gm.__namecall = original.old end
            end)
        end
    end)
    hooked = false
end

--------------------------------------------------------------- report
local function remoteList()
    local out = {}
    pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        for _, d in ipairs(rs:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction")
                or d:IsA("UnreliableRemoteEvent") then
                out[#out + 1] = string.format("  %s [%s]", d:GetFullName(), d.ClassName)
            end
        end
    end)
    table.sort(out)
    return out
end

local function buildReport()
    local L = {}
    local function w(s) L[#L + 1] = tostring(s) end
    w("══════ SPUD REMOTE REPORT ══════")
    w(string.format("place %d · job %s · player %s",
        game.PlaceId, tostring(game.JobId), LP.Name))
    w(string.format("hook: %s%s", hooked and ("ACTIVE via " .. hookHow) or "off",
        hookErr and (" · " .. hookErr) or ""))
    local calls = 0
    for _, r in ipairs(records) do if r.kind == "call" then calls += 1 end end
    w(string.format("recorded calls: %d", calls))

    -- ▸ THE ONES THIS PROBE EXISTS FOR. The inventory already named them
    --   (EVTFillLiquidCarrier, EVTRequestToCarry/Drop, EVTAnimalInteraction,
    --   EVTCollectAnimalProduction), so the report now puts their calls FIRST
    --   instead of making them a needle in a busy session.
    w("")
    w("══════ MILK CALLS (the ones that matter) ══════")
    local suspects = { "FillLiquidCarrier", "RequestToCarry", "RequestToDrop",
        "AnimalInteraction", "CollectAnimalProduction", "LiquidSiloVisual",
        "HarvesterPourAnimation", "EquipmentCarryInfo", "Juicery" }
    local seen, missing = 0, {}
    for _, s in ipairs(suspects) do
        local fired = false
        for _, r in ipairs(records) do
            if r.kind == "call" and r.name:lower():find(s:lower(), 1, true) then
                fired = true
                seen += 1
                w(string.format("  %s:%s(%s)", r.name, r.method, r.args))
            end
        end
        if not fired then missing[#missing + 1] = s end
    end
    if seen == 0 then
        w("  NONE — nothing was recorded. The jug/Fill/cow steps have to be done")
        w("  WHILE the panel is counting: the number must go up after each one.")
    end
    if #missing > 0 then
        w("  not seen: " .. table.concat(missing, ", "))
    end

    w("")
    w("══════ REMOTE INVENTORY (ReplicatedStorage) ══════")
    local list = remoteList()
    if #list == 0 then
        w("  (none — the game may keep them elsewhere)")
    else
        for _, line in ipairs(list) do w(line) end
    end

    w("")
    w("══════ CALLS, IN ORDER ══════")
    if #records == 0 then
        w("  (nothing recorded)")
    end
    local t0 = records[1] and records[1].at or os.clock()
    for _, r in ipairs(records) do
        if r.kind == "mark" then
            w(string.format("  -- MARK: %s  (%s)", r.text, r.where))
        else
            w(string.format("  [%6.1fs] %s:%s(%s)   <%s>",
                r.at - t0, r.name, r.method, r.args, r.where))
        end
    end

    w("")
    w("══════ GROUPED BY REMOTE ══════")
    local by = {}
    for _, r in ipairs(records) do
        if r.kind == "call" then
            local key = r.name .. ":" .. r.method
            by[key] = (by[key] or 0) + 1
        end
    end
    local keys = {}
    for k in pairs(by) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then w("  (none)") end
    for _, k in ipairs(keys) do w(string.format("  %3d × %s", by[k], k)) end

    w("")
    w("══════ END ══════")
    return table.concat(L, "\n")
end

--------------------------------------------------------------- upload
local function httpPost(url, body)
    local fn = nil
    if type(request) == "function" then fn = request end
    if not fn and type(http_request) == "function" then fn = http_request end
    if not fn and type(http) == "table" and type(http.request) == "function" then fn = http.request end
    if not fn then return nil end
    local okRes, res = pcall(fn, {
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "text/plain; charset=utf-8",
            ["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64)",
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

--------------------------------------------------------------- public api
function spudRemoteMark(label)
    records[#records + 1] = { kind = "mark", text = tostring(label or "mark"), where = here() }
    print("[spud-remote] mark: " .. tostring(label))
end

function spudRemoteShow()
    print(buildReport())
end

-- a way out that does NOT upload: restores the game's own call path at once
function spudRemoteRestore()
    restore()
    spudRemoteClosePanel()
    print("[spud-remote] hook removed — the game's own calls are untouched again")
end

function spudRemoteStop()
    restore()
    local text = buildReport()
    print(text)
    local link = nil
    if #text < 900000 then
        link = urlFrom(httpPost("https://paste.rs/", text), 201)
            or urlFrom(httpPost("https://0x0.st", text))
    end
    pcall(function() setclipboard(link or text) end)
    print("════════════════════════════════════════")
    if link then
        print("✔ UPLOADED — send this link back:")
        print("   " .. link)
    else
        print("✔ upload blocked — the whole report is on your clipboard, paste it in a notes app and send it")
    end
    print("════════════════════════════════════════")
    spudRemoteClosePanel()
    return link
end

--------------------------------------------------------------- the panel
-- ▸ SMALL CONTROL PANEL (user: "give it a small gui please so i can copy and
--   stop it"). Plain Roblox GUI on purpose — no library, no hooking of its
--   own — so the copy/stop buttons keep working even when the game's own UI
--   is the thing acting up.
local function buildGui()
    local parent
    pcall(function() if gethui then parent = gethui() end end)
    if not parent then
        pcall(function() parent = LP:FindFirstChildOfClass("PlayerGui") end)
    end
    if not parent then
        pcall(function() parent = game:GetService("CoreGui") end)
    end
    if not parent then return false end

    local sg = Instance.new("ScreenGui")
    sg.Name = "SpudRemotePanel"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999
    sg.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(200, 156)
    frame.Position = UDim2.fromOffset(16, 16)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(72, 72, 84)
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
    title.Text = "SPUD REMOTE PROBE"
    title.Parent = frame

    guiStatus = Instance.new("TextLabel")
    guiStatus.Size = UDim2.new(1, -16, 0, 16)
    guiStatus.Position = UDim2.fromOffset(8, 25)
    guiStatus.BackgroundTransparency = 1
    guiStatus.Font = Enum.Font.Gotham
    guiStatus.TextSize = 11
    guiStatus.TextXAlignment = Enum.TextXAlignment.Left
    guiStatus.TextColor3 = Color3.fromRGB(170, 200, 170)
    guiStatus.Text = "starting…"
    guiStatus.Parent = frame

    local function mkButton(text, y, color, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -16, 0, 26)
        b.Position = UDim2.fromOffset(8, y)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.AutoButtonColor = true
        b.Font = Enum.Font.Gotham
        b.TextSize = 12
        b.TextColor3 = Color3.fromRGB(245, 245, 250)
        b.Text = text
        b.Parent = frame
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 5)
        c.Parent = b
        b.MouseButton1Click:Connect(function()
            local okRun, errRun = pcall(onClick)
            if not okRun then print("[spud-remote] panel button error: " .. tostring(errRun)) end
        end)
        return b
    end

    mkButton("Copy report", 50, Color3.fromRGB(52, 52, 64), function()
        local text = buildReport()
        local okCopy = pcall(function() setclipboard(text) end)
        print(okCopy and "[spud-remote] report copied to the clipboard"
            or "[spud-remote] no setclipboard in this executor")
        if guiStatus then
            guiStatus.Text = okCopy and "copied — paste it to me" or "clipboard unavailable"
        end
    end)

    mkButton("Upload & stop", 82, Color3.fromRGB(38, 108, 64), function()
        spudRemoteStop()
    end)

    mkButton("Stop (no upload)", 114, Color3.fromRGB(118, 54, 54), function()
        spudRemoteRestore()
    end)

    gui = sg
    return true
end

local okPanel, panelRes = pcall(buildGui)
if not okPanel then
    print("[spud-remote] the panel errored (" .. tostring(panelRes) .. ") — the console commands still work")
elseif not panelRes then
    print("[spud-remote] the panel didn't build — the console commands still work")
end

task.spawn(function()
    while gui do
        task.wait(0.5)
        if guiStatus and gui then
            local n = 0
            for _, r in ipairs(records) do if r.kind == "call" then n += 1 end end
            guiStatus.Text = string.format("%d call(s) · %s", n,
                hooked and "recording" or "stopped")
        end
    end
end)

-- safety net: a forgotten probe must never leave the hook installed
if hooked then
    task.delay(600, function()
        if hooked then
            restore()
            spudRemoteClosePanel()
            print("[spud-remote] 10 minutes passed — recording stopped and the game's own call path was restored")
        end
    end)
end

print("════════════════════════════════════════")
print("[spud-remote] recording: " .. (hooked and ("yes (" .. hookHow .. ")") or "NO — " .. tostring(hookErr)))
print("if ANY button stops responding: run  spudRemoteRestore()  (or rejoin)")
print("1) pick up a milk jug (Carry/E)")
print("2) walk to the truck and press Fill (V) once")
print("3) milk one cow")
print("4) press  Copy report  on the little panel (or run spudRemoteStop()) and send it")
print("   (spudRemoteMark(\"carry\") / (\"fill\") / (\"milk\") between steps if you like)")
print("   the panel number MUST rise after each action — 0 means nothing was captured")
print("════════════════════════════════════════")
