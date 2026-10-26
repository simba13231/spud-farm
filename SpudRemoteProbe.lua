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

local function short(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        local s = v
        if #s > 90 then s = s:sub(1, 87) .. "…" end
        return string.format("%q", s)
    elseif t == "Instance" then
        local ok, n = pcall(function() return v:GetFullName() end)
        return ok and n or tostring(v)
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
    local nm
    local ok, full = pcall(function()
        if typeof(self) == "Instance" then return self:GetFullName() end
        return tostring(self)
    end)
    nm = ok and full or tostring(self)
    records[#records + 1] = {
        kind = "call", name = nm, method = method,
        args = table.concat(parts, ", "),
        n = args.n, where = here(), at = os.clock(),
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
    return link
end

print("════════════════════════════════════════")
print("[spud-remote] recording: " .. (hooked and ("yes (" .. hookHow .. ")") or "NO — " .. tostring(hookErr)))
print("1) pick up a milk jug (Carry/E)")
print("2) walk to the truck and press Fill (V) once")
print("3) milk one cow")
print("4) run  spudRemoteStop()  and send the link")
print("   (spudRemoteMark(\"carry\") / (\"fill\") / (\"milk\") between steps if you like)")
print("════════════════════════════════════════")
