--[[
═══════════════════════════════════════════════════════════════════════════
  SPUD FARM — FULL MERGED SCRIPT + STEALTH  (Farming and Friends / Roblox)
═══════════════════════════════════════════════════════════════════════════
  Merges:
    • SPUD farm stage cycle   (PLOW > CULTIVATE > PLANT > GROW > HARVEST > SELL)
    • Presets: Chocolate Milk, Cake & Eggs, Wool Run (LOOP / STOP)
    • Full GUI: movement, teleports, anti-AFK, FPS boost, notifications
    • WIKI DATA (2026): all 12 crop growth times confirmed, per-crop
      profit sheet (seed cost / avg $/hr), equipment requirements,
      recipe-accurate presets (cake batter → oven, 5-wool spindel bundles)
    • Discord webhook panel (📡) with live feed + 🥔 minimize-all button
    • STEALTH SYSTEM (see below)

  ── HOW DETECTION ACTUALLY WORKS (researched, 2026) ──────────────────────
  There are three separate layers. No Luau script can affect layer 1:

  1. HYPERION / BYFRON (client integrity)
     Detects the EXECUTOR (injection, unsigned modules, memory hooks, VMs).
     It does not read your script's logic. Whether you are "undetected"
     here depends entirely on your executor being currently patched —
     a permanent cat-and-mouse. Nothing inside this script changes that.

  2. SERVER-SIDE MOVEMENT VALIDATION
     Games compare your position over time (e.g. "max ~50 studs per 0.2s").
     Instant CFrame teleports, huge WalkSpeed and flight get rubber-banded
     or kicked. Movement modes (Settings > Movement):
       • VFly (default) — BodyVelocity fly + snap teleport. Fast, simple.
       • Tween — slow stepped glide under server thresholds. Safer.
     Other mitigations built in here:
       • Walkspeed/Jump clamped to human-ish caps while Stealth is ON
       • NoClip auto-disables while Stealth is ON (walking through walls
         triggers the HumanoidState "StrafingNoPhysics" check in many games)
       • All interactions go through the game's OWN context-key system
          (zero ProximityPrompts exist in this game — dump-confirmed:
          stand in range, press the bound key E/X/V/F like a player)
         (the server sees exactly what a real player press produces; no
         RemoteEvent guessing = no honeypot risk)

  3. BEHAVIORAL / ML SCORING (live since 2025, expanding 2026)
     Flags robotic patterns: identical action intervals, 24/7 sessions,
     pathfinding-perfect movement, no idle time. Mitigation built in here:
       • Jitter — every delay randomized ±40% (slider)
       • Micro-pauses — occasional 1–3s human "hesitations"
       • Session limiter — auto-pause after N minutes (default 45)

  HONEST LIMITS: these reduce risk, they do not make you invisible. Use a
  private server (this game has FREE VIP servers), keep sessions short,
  and consider an alt account. Running 24/7 in public servers is the
  fastest way to get reported and reviewed regardless of any of this.

  HOW TO USE: paste into your executor → Execute → RIGHT SHIFT for menu.
  📡 = webhook window · 🥔 = hide/show all windows · Settings tab fixes
  any in-game name without code edits.
═══════════════════════════════════════════════════════════════════════════
]]

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local StarterGui         = game:GetService("StarterGui")
local VirtualUser        = game:GetService("VirtualUser")
local VirtualInputManager= game:GetService("VirtualInputManager")
local Lighting           = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local UIS = UserInputService

-- raw URL of THIS file on GitHub — the 🔄 Reload button in Settings
-- downloads it, so updates never need a new paste
local SCRIPT_URL = "https://raw.githubusercontent.com/simba13231/spud-farm/main/SpudFarm_Full.lua"

------------------------------------------------------------
-- EXECUTOR COMPATIBILITY
------------------------------------------------------------
local function try(f, ...)
    return pcall(f, ...)
end

local function realRef(obj)
    if cloneref then
        local ok, ref = try(cloneref, obj)
        if ok and ref then return ref end
    end
    return obj
end

local function guiParent()
    if gethui then
        local ok, p = try(gethui)
        if ok and p then return p end
    end
    return game:GetService("CoreGui")
end

------------------------------------------------------------
-- CHARACTER STATE
------------------------------------------------------------
local Character, Humanoid, RootPart

local function hookCharacter(char)
    Character = realRef(char)
    RootPart  = Character:WaitForChild("HumanoidRootPart", 10)
    Humanoid  = Character:WaitForChild("Humanoid", 10)
end
if LocalPlayer.Character then hookCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    hookCharacter(char)
end)

------------------------------------------------------------
-- CONFIG — game names (editable live from the Settings tab)
-- Real equipment names from the wiki: ZM80 tractor, SRC6 combine,
-- S4204 plow, KADL cultivator, KGF 3000 planter, AED300 seeder.
------------------------------------------------------------
local CONFIG = {
    -- Farm cycle (implements are hitched to the tractor with E)
    fieldNames    = { "Plot", "Field", "Soil", "Farm" },
    tractorName   = "ZM80",          -- starter tractor (substring)
    plowTool      = "S4204",         -- plow implement
    cultivateTool = "KADL",          -- cultivator implement
    plantTool     = "KQF, KGF",       -- planter (IN-GAME: "KQF3000" — wiki "KGF 3000" was wrong; dump-confirmed)
    harvestTool   = "SRC6",          -- combine harvester
    growWait      = 8 * 60,          -- seconds (crop selection / slider sets this)
    shopName      = "FarmCo",        -- crop sell store
    sellKey       = "Q",             -- Q opens sell menu on the platform
    confirmKey    = "E",             -- E confirms the sell popup
    sellPlatformNames = { "Platform", "LoadInPlatform", "SellBoard", "SellPlatform", "Sell Pad", "SellPad" },
    leverPrompt   = "Lever",         -- factory interior levers
    stallMarker   = "Adornee_BarnStallMenu", -- barn stall points (dump: 16 across the barns)

    -- What the farm cycle plants (set from the Farm tab crop dropdown)
    crop = "Wheat",
    -- growth times in seconds — all wiki-confirmed (no more guesses)
    cropGrowTimes = {
        ["Wheat"]      = 60,     -- 1 min
        ["Corn"]       = 150,    -- 2 min 30 s
        ["Rice"]       = 480,    -- 8 min
        ["Oat"]        = 480,    -- 8 min
        ["Sugar Cane"] = 1320,   -- 22 min
        ["Soybeans"]   = 2160,   -- 36 min
        ["Tomatoes"]   = 2178,   -- 36 min 18 s
        ["Cabbage"]    = 3600,   -- 60 min
        ["Carrots"]    = 2400,   -- 40 min
        ["Potatoes"]   = 2400,   -- 40 min
        ["Cocoa"]      = 1920,   -- 32 min (forestry)
        ["Grape"]      = 990,    -- 16 min 30 s (trellis)
    },
    -- wiki profit sheet: one seed box = 50 crops, AVERAGE prices.
    -- FarmCo prices rotate every ~5 min — rainbow board = peak value.
    cropProfit = {
        ["Wheat"]      = { cost = 100,    sell = 150,    perHr = 3000  },
        ["Corn"]       = { cost = 250,    sell = 450,    perHr = 4800  },
        ["Rice"]       = { cost = 2000,   sell = 2600,   perHr = 4500  },
        ["Oat"]        = { cost = 2200,   sell = 2850,   perHr = 4875  },
        ["Sugar Cane"] = { cost = 8400,   sell = 9900,   perHr = 4091  },
        ["Soybeans"]   = { cost = 24000,  sell = 27200,  perHr = 5333  },
        ["Tomatoes"]   = { cost = 26400,  sell = 31050,  perHr = 7686  }, -- best field $/hr
        ["Cabbage"]    = { cost = 57600,  sell = 64100,  perHr = 6500  },
        ["Carrots"]    = { cost = 85000,  sell = 88500,  perHr = 5250  },
        ["Potatoes"]   = { cost = 120000, sell = 125000, perHr = 7500  },
        ["Cocoa"]      = { cost = 70000,  sell = 73000,  perHr = 5625  }, -- raw logs; pods → choc milk (S-tier)
        ["Grape"]      = { cost = 105000, sell = nil,     perHr = nil   }, -- no published average
    },
    -- requirements the wiki puts on certain crops (shown in the Farm tab)
    cropNotes = {
        ["Soybeans"]   = "needs lvl 2+ seeder (AED300)",
        ["Tomatoes"]   = "needs lvl 2+ seeder (AED300)",
        ["Carrots"]    = "needs lvl 3–5 seeder & harvester",
        ["Potatoes"]   = "needs lvl 4 equipment",
        ["Cocoa"]      = "forest soil · lvl 2+ seeder · LumberCo · licenses",
        ["Grape"]      = "trellis field · lvl 3 equipment",
    },

    -- Chocolate Milk: 25 cocoa + 10 regular milk (or 5 free-range, 2:1)
    -- = 1 jug, ~20-23k coins, max 60 jugs per run. Spoiled milk (cow
    -- happiness < 60%) cannot be used. Both drop on the elevated platform.
    presets = {
        chocolateMilk = {
            cowName        = "Cow",              -- confirmed: models named "Cow"
            milkerTool     = "Milker, Stall, Barn, Udder",  -- barn stalls = "Adornee_BarnStallMenu" (dump)
            milkDrop       = "Milk",
            factoryName    = "Chocolate Milk",
            milkDeposit    = "Milk",
            cocoaDeposit   = "Cocoa",
            cocoaTree      = "Cocoa",
            cocoaHarvester = "Oxbo",        -- Oxbo3220 cocoa harvester
            cocoaDrop      = "Cocoa",
            productName    = "Chocolate",
            shopName       = "FarmCo",      -- one-stop/platform sell
            processWait    = 45,
        },
        -- Cake & Eggs: 1 cake = 100 Wheat + 1 egg box (12 eggs) + 1 milk.
        -- Wheat + Milk go on the LEFT side (storage display), eggs go INSIDE
        -- onto the conveyor. Levers: right → opposite → below conveyor →
        -- upstairs right. Factory outputs Cake BATTER; the Oven building
        -- bakes batter into Cake.
        cakeEggs = {
            coopName     = "Coop",
            eggDrop      = "Egg",
            cowName      = "Cow",
            milkerTool   = "Milker",
            milkDrop     = "Milk",
            factoryName  = "Cake",
            eggDeposit   = "Egg",
            milkDeposit  = "Milk",
            wheatDeposit = "Wheat",
            batterDrop   = "Batter",
            ovenName     = "Oven",
            productName  = "Cake",
            shopName     = "FarmCo",
            processWait  = 45,
            bakeWait     = 60,
        },
        -- Wool Run: shear sheep (shears bought at AnimalCo) → 5 raw wool
        -- per bundle at the spindel → sell bundles at the AnimalCo drop-off.
        -- Sheep need the Sheep License (~7,200 XP on the Animals track).
        wool = {
            sheepName    = "Sheep",
            shearsTool   = "Shear",
            woolDrop     = "Wool",
            spindelName  = "Spindel",
            bundleDrop   = "Bundle",
            shopName     = "Animal",        -- AnimalCo animal drop-off
        },
    },

    -- Teleport destinations (substrings, first match wins).
    -- Names confirmed by in-game dump (2026 map): store parts are literally
    -- named VehicleStore / LumberStore / BulkStore / AnimalCo / AnimalCoDrive.
    teleports = {
        { label = "FarmCo",     names = { "FarmCo", "SellBoardSeeds", "Farm Co" } },
        { label = "AnimalCo",   names = { "AnimalCo", "AnimalCoDrive", "Animal Co" } },
        { label = "TractorCo",  names = { "VehicleStore", "TractorCo", "Vehicle Store" } },
        { label = "LumberCo",   names = { "LumberStore", "LumberCo", "Lumber Co" } },
        { label = "Bulk Store", names = { "BulkStore", "OneStop", "One Stop", "SellPoint" } },
        { label = "Warehouse",  names = { "TrainTimerPart", "WarehouseArea", "Warehouse" } },
        { label = "My Farm",    names = { "PlotBillboard", "FrontPlot" } },
        { label = "Spawn",      names = { "SpawnLocation", "SpawnPoint", "Spawn" } },
    },
}

local Options = {
    Notifications = true,
    MoveMode      = "VFly",   -- "VFly" (fast fly + snap) or "Tween" (slow glide)
    VflySpeed     = 200,      -- studs/sec for vfly travel
    SpeedEnabled  = false,
    WalkSpeed     = 16,
    JumpEnabled   = false,
    JumpPower     = 50,
    InfiniteJump  = false,
    NoClip        = false,
    AntiAFK       = false,
    FPSBoost      = false,
    ClickTeleport = false,
}

------------------------------------------------------------
-- STEALTH SYSTEM (see header for the full explanation)
------------------------------------------------------------
local Stealth = {
    enabled        = true,   -- master: glide + jitter + noclip guard
    jitterAmount   = 0.4,    -- ±40% randomization on every delay
    maxGlide       = 55,     -- studs/second cap for glide movement
    speedCap       = 64,     -- WalkSpeed clamp while stealth on
    jumpCap        = 90,     -- JumpPower clamp while stealth on
    sessionLimitOn = true,   -- auto-break after sessionLimit minutes
    sessionLimit   = 45,     -- minutes of active automation before a break
    breakLength    = 4,      -- minutes of auto-break
}

-- humanized wait: jitter every delay, occasionally "hesitate"
local function hwait(base)
    local j = 1
    if Stealth.enabled then
        j = 1 + (math.random() * 2 - 1) * Stealth.jitterAmount
    end
    task.wait(math.max(0.05, base * j))
    if Stealth.enabled and math.random() < 0.06 then
        task.wait(math.random(10, 30) / 10) -- random 1-3s human pause
    end
end

------------------------------------------------------------
-- NOTIFICATIONS / LOG
------------------------------------------------------------
local function notify(text)
    if not Options.Notifications then return end
    try(function()
        StarterGui:SetCore("SendNotification", {
            Title = "SPUD FARM", Text = tostring(text), Duration = 4,
        })
    end)
end

local function log(text)
    print("[spud] " .. tostring(text))
end

------------------------------------------------------------
-- DISCORD WEBHOOK (Settings tab) — session logs to your own
-- webhook. Rate-limited (Discord: ~2 req / 5s) via a queue.
------------------------------------------------------------
local Webhook = {
    url     = "",
    enabled = false,
    queue   = {},
    lastSent = 0,
}

-- forward-decls: GUI helpers/colors are defined in the GUI section below
local COL, mk, corner

-- settings carried over from the previous instance (🔄 Reload button):
-- applied here so every widget below shows the carried values
if type(_G.SpudCarry) == "table" then
    local c = _G.SpudCarry
    if c.crop then CONFIG.crop = c.crop end
    if c.shopName then CONFIG.shopName = c.shopName end
    if c.moveMode then Options.MoveMode = c.moveMode end
    if c.vflySpeed then Options.VflySpeed = c.vflySpeed end
    if c.webhookUrl then Webhook.url = c.webhookUrl end
    if c.webhookOn ~= nil then Webhook.enabled = c.webhookOn end
end

local function jsonEscape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return s
end

local function httpRequest(opts)
    if type(request) == "function" then return request(opts) end
    if type(http_request) == "function" then return http_request(opts) end
    if type(http) == "table" and type(http.request) == "function" then return http.request(opts) end
    if type(syn) == "table" and type(syn.request) == "function" then return syn.request(opts) end
    return nil
end

-- queue a message; a background worker drains it respecting rate limits
-- Forward-decls: the feed UI is built later; lines append if it exists
local WebhookFeed, WebhookFeedOrder = nil, 0
local function feedLine(text)
    if not WebhookFeed then return end
    local label = mk("TextLabel", {
        Parent = WebhookFeed,
        Size = UDim2.new(1, -6, 0, 14),
        BackgroundTransparency = 1,
        Text = os.date("%H:%M:%S") .. "  " .. tostring(text),
        TextColor3 = COL.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = WebhookFeedOrder,
    })
    WebhookFeedOrder += 1
    -- cap feed at 30 rows (drop oldest)
    local oldest
    local count = 0
    for _, c in ipairs(WebhookFeed:GetChildren()) do
        if c:IsA("TextLabel") then
            count += 1
            if not oldest or c.LayoutOrder < oldest.LayoutOrder then oldest = c end
        end
    end
    if count > 30 and oldest then oldest:Destroy() end
    task.defer(function()
        if WebhookFeed and WebhookFeed.Parent then
            WebhookFeed.CanvasPosition = Vector2.new(0, 99999)
        end
    end)
end

local function webhookSend(text)
    feedLine(text) -- always show locally in the webhook panel feed
    if not Webhook.enabled or Webhook.url == "" then return end
    if #Webhook.queue >= 20 then return end -- drop to avoid flooding
    local msg = tostring(text)
    if #msg > 1900 then msg = msg:sub(1, 1900) .. "…" end
    table.insert(Webhook.queue, msg)
end

task.spawn(function()
    while task.wait(1) do
        if Webhook.enabled and #Webhook.queue > 0 and (os.clock() - Webhook.lastSent) >= 6.5 then
            local url, msg = Webhook.url, table.remove(Webhook.queue, 1)
            local body = "{\"content\":\"" .. jsonEscape(msg) .. "\",\"username\":\"SPUD FARM\"}"
            local ok = pcall(function()
                local resp = httpRequest({
                    Url     = url,
                    Method  = "POST",
                    Headers = {
                        ["Content-Type"]  = "application/json",
                        ["User-Agent"]    = "Mozilla/5.0",
                    },
                    Body = body,
                })
                if resp and resp.StatusCode and resp.StatusCode >= 300 then
                    warn("[spud] webhook HTTP " .. tostring(resp.StatusCode))
                end
            end)
            if not ok then warn("[spud] webhook send failed (executor may lack http.request)") end
            Webhook.lastSent = os.clock()
        end
    end
end)

-- coin balance for profit notes in webhook logs.
-- dump-confirmed: coins live in the HUD balance label
-- (GuiViews.HUD.MainHUD.TopRightBar.CoinsDisplay.Contents.Balance.Text)
local LastCoins = nil
local function getCoins()
    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then
        local bal = pGui:FindFirstChild("Balance", true)
        if bal and bal:IsA("GuiObject") then
            local v = tonumber((tostring(bal.Text):gsub(",", "")))
            if v then return v end
        end
    end
    local function tryValue(v)
        if v and v:IsA("ValueBase") and typeof(v.Value) == "number" then
            return v.Value
        end
        return nil
    end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, name in ipairs({ "Coins", "Money", "Cash", "Gold" }) do
            local val = tryValue(ls:FindFirstChild(name))
            if val then return val end
        end
    end
    for _, name in ipairs({ "Coins", "Money", "Cash" }) do
        local val = tryValue(LocalPlayer:FindFirstChild(name))
        if val then return val end
    end
    return nil
end

local function coinsNote()
    local c = getCoins()
    if not c then return "" end
    local note = " · coins " .. tostring(c)
    if LastCoins and c ~= LastCoins then
        local delta = c - LastCoins
        note = note .. (delta >= 0 and (" (+" .. tostring(delta) .. ")") or (" (" .. tostring(delta) .. ")"))
    end
    LastCoins = c
    return note
end

-- wiki average $/hr for the selected crop (nil-safe)
local function cropProfitNote()
    local p = CONFIG.cropProfit and CONFIG.cropProfit[CONFIG.crop]
    if p and p.perHr then return " · ≈" .. tostring(p.perHr) .. "/hr avg" end
    return ""
end

------------------------------------------------------------
-- CORE HELPERS
------------------------------------------------------------
local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

local function nameMatch(obj, substring)
    local n = obj.Name:lower()
    -- multiple candidates allowed: "Milker, Udder Tool" → any match wins
    for alt in tostring(substring):gmatch("[^,;]+") do
        local sub = alt:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if sub ~= "" and (n == sub or n:find(sub, 1, true) ~= nil) then
            return true
        end
    end
    return false
end

-- shared ~0.8s cache of workspace BaseParts — nearest/findAll would
-- otherwise re-scan ALL 100k+ instances on every call (the farm sweep
-- calls them constantly; this is the single biggest CPU saver here)
local ScanCache, ScanCacheAt = nil, 0
local function scanAll()
    local now = os.clock()
    if not ScanCache or now - ScanCacheAt > 0.8 then
        local out = {}
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then out[#out + 1] = v end
        end
        ScanCache = out
        ScanCacheAt = now
    end
    return ScanCache
end

-- nearest matching BasePart by name substring (returns the part)
local function nearest(substring, maxDist, nearPos)
    local best, bestDist = nil, math.huge
    local origin = nearPos or (RootPart and RootPart.Position)
    for _, v in ipairs(scanAll()) do
        if v.Parent and nameMatch(v, substring) then
            if not origin then return v end
            local d = (v.Position - origin).Magnitude
            if d <= (maxDist or math.huge) and d < bestDist then
                best, bestDist = v, d
            end
        end
    end
    return best
end

-- all matching BaseParts, sorted by distance
local function findAll(substring, maxDist)
    local out = {}
    if not RootPart then return out end
    for _, v in ipairs(scanAll()) do
        if v.Parent and nameMatch(v, substring) then
            local d = (v.Position - RootPart.Position).Magnitude
            if d <= (maxDist or math.huge) then
                table.insert(out, { part = v, dist = d })
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- glide movement: tiny steps at capped speed instead of instant teleports
-- getCF: returns the current CFrame; setCF: applies a new CFrame
local function glideTo(targetPos, getCF, setCF, speedMult)
    local cf = getCF()
    if not cf then return end
    local dist = (targetPos - cf.Position).Magnitude
    if dist < 0.5 then return end
    local maxStep = Stealth.maxGlide * 0.1 * (speedMult or 1) -- studs per 0.1s tick
    while dist > 0.5 do
        local dt = 0.1 * (1 + (math.random() * 2 - 1) * 0.25)
        local stepLen = math.min(maxStep * (1 + (math.random() * 2 - 1) * 0.2), dist)
        local cur = getCF()
        if not cur then return end
        local pos = cur.Position
        local dir = targetPos - pos
        dist = dir.Magnitude
        if dist < 0.5 then break end
        local nextPos = pos + dir.Unit * math.min(stepLen, dist)
        try(function() setCF(CFrame.new(nextPos) * cur.Rotation) end)
        task.wait(dt)
    end
end

-- vfly movement: BodyVelocity flight toward the target + snap on arrival
-- (classic executor vfly — fast, simple; final CFrame snap acts as the "tp")
local function vflyTo(target)
    local dist = (RootPart.Position - target).Magnitude
    if dist < 8 then
        try(function() RootPart.CFrame = CFrame.new(target) * RootPart.CFrame.Rotation end)
        return
    end
    try(function()
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bv.P = 1e5
        bv.Velocity = Vector3.zero
        bv.Parent = RootPart
        local speed = Options.VflySpeed
        local start = os.clock()
        local timeout = dist / speed + 3
        while (RootPart.Position - target).Magnitude > 2 and os.clock() - start < timeout do
            if not RootPart.Parent then break end
            local dir = target - RootPart.Position
            local m = dir.Magnitude
            bv.Velocity = (m > 0.001 and dir.Unit or Vector3.yAxis) * math.min(speed, m * 5)
            task.wait(0.08)
        end
        bv:Destroy()
    end)
    -- snap-teleport the last bit (also the fallback if BodyVelocity failed)
    try(function() RootPart.CFrame = CFrame.new(target) * RootPart.CFrame.Rotation end)
end

-- move the character (or the seated vehicle) to a position
-- "Tween"  → slow animated glide (stays under server teleport thresholds)
-- "VFly"   → fast velocity fly + snap teleport (fast, more detectable)
local function driveTo(pos, height)
    if not RootPart or not RootPart.Parent then return end
    local target = Vector3.new(pos.X, pos.Y + (height or 3), pos.Z)
    local useTween = (Options.MoveMode == "Tween")

    local seat = (Humanoid and Humanoid.SeatPart) or RootPart:FindFirstChild("SeatPart")
    if seat then
        local model = seat:FindFirstAncestorOfClass("Model")
        if model then
            -- vehicles always GLIDE, never one instant snap: long vehicle
            -- teleports get rubber-banded by the server, which desyncs our
            -- position from the game's — the context system then ignores
            -- keys like Hitch(X) because, server-side, "we aren't there".
            -- VFly = 2.2x glide speed (~120 sps, still fast), Tween = human
            -- slow glide. Rotation is PRESERVED (the old code reset it to
            -- identity every move, swinging the tractor's rear hitch out
            -- of the implement's trigger zone mid-approach).
            local mult = useTween and 1 or 2.2
            glideTo(target,
                function() return model:GetPivot() end,
                function(cf) model:PivotTo(cf) end,
                mult)
            -- settle the last fraction, keeping our heading
            try(function()
                local p = model:GetPivot()
                model:PivotTo(CFrame.new(target) * p.Rotation)
            end)
            return
        end
    end

    if useTween then
        glideTo(target,
            function() return RootPart.CFrame end,
            function(cf) RootPart.CFrame = cf end)
        -- settle the last fraction onto the exact spot
        try(function() RootPart.CFrame = CFrame.new(target) * RootPart.CFrame.Rotation end)
    else
        vflyTo(target)
    end
end

-- throttle: never fire input faster than a human could (anti action-cadence)
local LastInput = 0
local function throttle()
    if Stealth.enabled then
        local gap = 0.35 + math.random() * 0.45
        local since = os.clock() - LastInput
        if since < gap then task.wait(gap - since) end
    end
    LastInput = os.clock()
end

local function pressKey(keyName)
    throttle()
    if VirtualInputManager then
        local code = Enum.KeyCode[string.upper(tostring(keyName))] or Enum.KeyCode.E
        try(function()
            VirtualInputManager:SendKeyEvent(true,  code, false, game)
            task.wait(0.06 + math.random() * 0.06)
            VirtualInputManager:SendKeyEvent(false, code, false, game)
        end)
    end
end

-- interact with a world object. This game has NO ProximityPrompts at all
-- (dump: 0 in 112,531 instances) — it uses a context-key system: stand in
-- range and press the bound key (dump-confirmed binds: E interact/carry/
-- lever/take-from-output, X hitch/drop/place-onto-input, V fill/shear/
-- spindle-deposit, F drive/talk, R pour). So: walk to the target and press
-- the caller's key (default E). A real prompt is still checked first so the
-- script keeps working if a future update adds prompts.
local function interactWith(part, key)
    if not part then return false end
    local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        driveTo(prompt.WorldCFrame.Position, 3)
        hwait(0.5)
        pcall(function() prompt.MaxActivationDistance = 25 end)
        pressKey("E")
        hwait(0.3)
        return true
    end
    driveTo(part.Position, 3)
    hwait(0.5)
    pressKey(key or "E")
    hwait(0.4)
    return true
end

local function getTool(name)
    if not Backpack then Backpack = LocalPlayer:FindFirstChildOfClass("Backpack") end
    if not Backpack then return nil end
    for _, t in ipairs(Backpack:GetChildren()) do
        if t:IsA("Tool") and nameMatch(t, name) then return t end
    end
    -- also check currently equipped
    if Character then
        local held = Character:FindFirstChildOfClass("Tool")
        if held and nameMatch(held, name) then return held end
    end
    return nil
end

local function equip(tool)
    if Humanoid and tool then
        try(function() Humanoid:EquipTool(tool) end)
        hwait(0.3)
    end
end

-- equip a tool by name and activate it for `duration` seconds
local function activate(name, duration)
    local tool = getTool(name)
    if not tool then return false end
    equip(tool)
    local held = Character and Character:FindFirstChildOfClass("Tool")
    if held then
        try(function() held:Activate() end)
        hwait(duration or 1.5)
        try(function() held:Deactivate() end)
        return true
    end
    return false
end

-- walk to drops matching a name and pick them up (context: Carry = E)
local function collectDrops(substring, maxDist, count)
    if not RootPart then return 0 end
    local taken = 0
    for _, item in ipairs(findAll(substring, maxDist or 800)) do
        if taken >= (count or 10) then break end
        -- skip spawn markers (e.g. "EggSpawn" parts are not the eggs)
        if item.part and item.part.Parent and not item.part.Name:lower():find("spawn", 1, true) then
            driveTo(item.part.Position, 2)
            hwait(0.35)
            pressKey("E")
            taken += 1
            hwait(0.45)
        end
    end
    return taken
end

-- drive onto the sell platform at a store and sell (Q opens menu, E confirms)
-- VERIFIED: the HUD balance must go UP before we call it done; if not,
-- confirm once more (menu lag), then report honestly.
local function sellAt(shopName, keyOverride)
    local shop = nearest(shopName, 20000)
    if not shop then log("shop not found: " .. tostring(shopName)) return false end
    -- look for the elevated sell platform near the store
    local platform
    for _, n in ipairs(CONFIG.sellPlatformNames) do
        platform = nearest(n, 400, shop.Position)
        if platform then break end
    end
    local before = getCoins()
    driveTo((platform or shop).Position, platform and 2 or 5)
    hwait(1.2)
    pressKey(keyOverride or CONFIG.sellKey)   -- opens the sell menu
    hwait(1.4)
    pressKey(CONFIG.confirmKey)               -- confirms the popup
    hwait(1.4)
    local after = getCoins()
    if before and after and after > before then
        log("sold - coins " .. before .. " → " .. after)
        return true
    end
    if before and after then
        pressKey(CONFIG.confirmKey)           -- second confirm (menu may lag)
        hwait(1.5)
        after = getCoins()
        if after and after > before then
            log("sold (2nd confirm) - coins " .. before .. " → " .. after)
            return true
        end
        log("sell UNVERIFIED (coins " .. before .. " → " .. tostring(after) .. ")")
        return false
    end
    return true   -- coin label unavailable - cannot verify, don't stall
end

-- pull every factory lever in sequence (chocolate milk / cake factories).
-- No prompts exist — levers are world parts; stand next to one and press E
-- (game's own PullFactoryLever context bind, dump-confirmed).
local function pullLevers(factoryPart, maxPulls)
    local levers = findAll(CONFIG.leverPrompt, 250)
    if #levers == 0 then
        log("no lever parts found (" .. tostring(CONFIG.leverPrompt) .. ") — factory not built?")
        return 0
    end
    log("found " .. #levers .. " lever part(s), pulling…")
    local pulled = 0
    local limit = maxPulls or 8
    for i = 1, limit do
        local lever = levers[((i - 1) % #levers) + 1]
        driveTo(lever.part.Position, 3)
        hwait(0.9)
        pressKey("E")
        pulled += 1
        hwait(3.0) -- levers take a few seconds each, like a player pulling them
    end
    return pulled
end

-- read the live sell-value boards (dump-confirmed: Stores.SellValueBoards
-- → List rows with NameLabel + ValueLabel). Read-only, zero risk.
local function readSellBoards()
    local rows = {}
    local stores = Workspace:FindFirstChild("Stores")
    local sv = stores and stores:FindFirstChild("SellValueBoards")
    if not sv then return rows end
    for _, list in ipairs(sv:GetDescendants()) do
        if list.Name == "List" and list:IsA("GuiObject") then
            for _, row in ipairs(list:GetChildren()) do
                local nl = row:FindFirstChild("NameLabel")
                local vl = row:FindFirstChild("ValueLabel")
                if nl and vl and nl:IsA("GuiObject") and vl:IsA("GuiObject")
                    and nl.Text ~= "" and vl.Text ~= "" then
                    table.insert(rows, { name = nl.Text, value = vl.Text })
                end
            end
        end
    end
    return rows
end

-- find a named piece of equipment (models in Objects.Equipment first —
-- equipment models are named like "KQF3000" but their child parts are not)
local function findEquipmentModel(name)
    local eqRoot = Workspace:FindFirstChild("Objects")
    local eq = eqRoot and eqRoot:FindFirstChild("Equipment")
    if eq then
        for _, v in ipairs(eq:GetChildren()) do
            if nameMatch(v, name) then return v end
        end
    end
    return nearest(name, 5000)
end

-- get into a vehicle seat. First the game's OWN way: context action
-- EnterEquipment = F (dump-confirmed), then weld fallbacks for executors.
-- VERIFIED: every return checks we are in THIS exact seat — if we were
-- still sitting in another vehicle (the tractor), we stand up first.
local function enterSeat(seat)
    if Humanoid and Humanoid.SeatPart then
        if Humanoid.SeatPart == seat then return true end
        try(function() Humanoid.Sit = false end)   -- seated in another vehicle
        hwait(0.7)
    end
    driveTo(seat.Position, 3)
    hwait(0.5)
    pressKey("F")
    hwait(1.2)
    if Humanoid and Humanoid.SeatPart == seat then return true end
    try(function() seat:Sit(Humanoid) end)
    hwait(0.6)
    if Humanoid and Humanoid.SeatPart == seat then return true end
    try(function() Humanoid:Sit(seat) end)
    hwait(0.6)
    return Humanoid and Humanoid.SeatPart == seat
end

-- sit in the tractor (needed for field sweeps to move the vehicle)
local function sitTractor()
    local tractor = findEquipmentModel(CONFIG.tractorName)
    if not tractor then return false end
    local vehicle = tractor:FindFirstAncestorOfClass("Model") or tractor
    local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
        or vehicle:FindFirstChildWhichIsA("Seat", true)
    if not seat then return false end
    return enterSeat(seat)
end

-- sit inside a named piece of equipment (e.g. the SRC6 combine for HARVEST —
-- combines are driven themselves, they are NOT hitched to the tractor)
local function sitInEquipment(name)
    if not name then return false end
    local model = findEquipmentModel(name)
    if not model then return false end
    local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
        or model:FindFirstChildWhichIsA("Seat", true)
    if not seat then return false end
    return enterSeat(seat)
end

-- find MY farm plot: Workspace.Plots.<n> whose PlotBillboard.Owner reads
-- "Your Farm" (own plot) or my display name (dump-confirmed structure)
local function findMyPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            local bb = plot:FindFirstChild("PlotBillboard")
            local owner = bb and bb:FindFirstChild("Owner")
            if owner and owner:IsA("TextLabel") then
                local t = owner.Text
                if t == "Your Farm" or t == LocalPlayer.DisplayName or t == LocalPlayer.Name then
                    return plot
                end
            end
        end
    end
    return nil
end

-- FORCE HITCH — how a real player does it: creep toward the hitch point
-- and press X at each micro-step (the game accepts Hitch the INSTANT the
-- tractor's hitch enters the implement's small trigger zone). X TOGGLES
-- Hitch/Unhitch, so after every press we tug-test (pull 5 studs forward,
-- a hitched implement is dragged along) — a success is caught BEFORE a
-- second press could un-toggle it. If nothing sticks: back away while
-- pressing X (the tractor's REAR sweeps the hitch zone), then rotate the
-- tractor 90° and attack from a new angle (HITCH_TRIES attempts), then
-- return false so the caller restarts the whole loop.
local HITCH_TRIES = 5

local function hitchTo(implementName)
    local imp = findEquipmentModel(implementName)
    if not imp then log("implement not found: " .. tostring(implementName)) return false end
    -- the tractor we're SITTING IN is the reliable handle; name search is
    -- only a fallback (a parked/renamed tractor can't abort hitching now)
    local tractor
    if Humanoid and Humanoid.SeatPart then
        tractor = Humanoid.SeatPart:FindFirstAncestorOfClass("Model") or Humanoid.SeatPart
    else
        tractor = findEquipmentModel(CONFIG.tractorName)
        if tractor and not tractor:IsA("Model") then
            tractor = tractor:FindFirstAncestorOfClass("Model") or tractor
        end
    end
    if not tractor then log("tractor not found: " .. tostring(CONFIG.tractorName)) return false end
    local function pivotCF(m)
        return m:IsA("Model") and m:GetPivot() or m.CFrame
    end
    local function aimPos()
        if imp:IsA("Model") then
            local h = imp:FindFirstChild("HitchRoot", true) or imp:FindFirstChild("Hitch", true)
            return h and h.Position or imp:GetPivot().Position
        end
        return imp.Position
    end
    -- tug-test: pull a few studs — hitched gear comes along, loose gear stays
    local function tugTest()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local t0, i0 = pivotCF(tractor).Position, pivotCF(imp).Position
        driveTo(hrp.Position + hrp.CFrame.LookVector * 5, 1)
        hwait(0.7)
        local tMoved = (pivotCF(tractor).Position - t0).Magnitude
        local iMoved = (pivotCF(imp).Position - i0).Magnitude
        return tMoved > 2.5 and iMoved > tMoved * 0.35
    end
    for attempt = 1, HITCH_TRIES do
        log("force-hitch " .. implementName .. " (attempt " .. attempt .. "/" .. HITCH_TRIES .. ")")
        local target = aimPos()
        driveTo(target, 4)
        hwait(0.9)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            -- creep INTO the hitch point, pressing X every micro-step
            local from = hrp.Position
            for step = 1, 4 do
                driveTo(from:Lerp(target, step / 4), 1.5)
                hwait(0.4)
                pressKey("X")
                hwait(0.6)
                if tugTest() then
                    log("HITCHED " .. implementName .. " (attempt " .. attempt .. ")")
                    return true
                end
            end
            -- back away pressing X — the tractor's REAR sweeps the hitch zone
            for _ = 1, 3 do
                local away = hrp.Position - target
                if away.Magnitude < 1 then away = -hrp.CFrame.LookVector end
                driveTo(hrp.Position + away.Unit * 3, 1.5)
                hwait(0.4)
                pressKey("X")
                hwait(0.6)
                if tugTest() then
                    log("HITCHED " .. implementName .. " (attempt " .. attempt .. ")")
                    return true
                end
            end
        end
        -- still nothing: rotate 90° and attack from a new angle
        log("hitch attempt " .. attempt .. "/" .. HITCH_TRIES .. " missed - rotating 90°")
        pcall(function()
            tractor:PivotTo(pivotCF(tractor) * CFrame.Angles(0, math.rad(90), 0))
        end)
        hwait(0.6)
    end
    return false
end

------------------------------------------------------------
-- FARM CYCLE ENGINE
------------------------------------------------------------
local STAGES = { "PLOW", "CULTIVATE", "PLANT", "GROW", "HARVEST", "SELL" }
local Farm = {
    enabled  = false,
    stage    = 1,
    round    = 0,
    autoSell = true,
    status   = "idle",
}

local function stageImplement(stageName)
    if stageName == "PLOW"      then return CONFIG.plowTool end
    if stageName == "CULTIVATE" then return CONFIG.cultivateTool end
    if stageName == "PLANT"     then return CONFIG.plantTool end
    if stageName == "HARVEST"   then return CONFIG.harvestTool end
    return nil
end

-- crop name candidates for prompt/tool matching: handles the wiki's
-- singular/plural mismatches (crop "Tomatoes" vs in-game "Tomato", etc.)
local function cropNameCandidates(crop)
    local out = { crop }
    if crop:sub(-1) == "s" then
        out[#out + 1] = crop:sub(1, -2)          -- Tomatoes → Tomato
    else
        out[#out + 1] = crop .. "s"              -- Oat → Oats, Grape → Grapes
    end
    if crop == "Sugar Cane" then out[#out + 1] = "Sugarcane" end
    if crop == "Cocoa" then out[#out + 1] = "Cacao" end
    return out
end

-- load the chosen crop's seeds before planting.
-- dump-confirmed: seed boxes are Objects.DraggableObjects.SeedBox models
-- whose Configurations.SeedType (StringValue) names the crop ("Corn").
-- Chain: carry the box (context E) → walk it to the planter/seeder →
-- press V (game's FillSeeder bind) → drop anything left (X).
local function loadSeeds()
    local crop = CONFIG.crop
    if not crop or crop == "Custom" then return end
    local cands = cropNameCandidates(crop)
    local box, seedType
    local dobjs = Workspace:FindFirstChild("Objects")
    dobjs = dobjs and dobjs:FindFirstChild("DraggableObjects")
    if dobjs then
        for _, m in ipairs(dobjs:GetChildren()) do
            if m.Name == "SeedBox" then
                local cfg = m:FindFirstChild("Configurations", true)
                local st = cfg and cfg:FindFirstChild("SeedType")
                local t = (st and st:IsA("StringValue")) and st.Value or nil
                if t then
                    for _, cand in ipairs(cands) do
                        if t:lower() == cand:lower() then box, seedType = m, t break end
                    end
                end
                if box then break end
            end
        end
    end
    if not box then
        log("no SeedBox with SeedType for " .. crop .. " — buy one at FarmCo (seeds are sold per-box)")
        return false
    end
    -- carry the box (context: Carry = E)
    local boxPos = box:IsA("Model") and box:GetPivot().Position or box.Position
    driveTo(boxPos, 3)
    hwait(0.8)
    pressKey("E")
    hwait(1.0)
    -- take it to the planter/seeder and fill (context: Fill = V)
    local seeder = findEquipmentModel(CONFIG.plantTool) or findEquipmentModel("KADL")
    if seeder then
        local sp = seeder:IsA("Model") and seeder:GetPivot().Position or seeder.Position
        driveTo(sp, 4)
        hwait(0.8)
        pressKey("V")   -- FillSeeder (dump-confirmed bind)
        hwait(1.0)
    else
        log("no seeder equipment found to fill (KQF3000 / KADL)")
    end
    pressKey("X")   -- drop the box if still held
    hwait(0.3)
    log("seeder fill attempted with " .. tostring(seedType) .. " seed box")
    return true
end

-- sweep: seat into the stage's machine, hitch the stage's implement
-- (verified + retried, see hitchTo), then drive the tractor over each
-- field tile (implements work by proximity in this game). HARVEST sits
-- in the combine (SRC6) itself — combines are driven, not hitched.
-- Tiles are searched inside MY plot first. Returns false when seating
-- or hitching could NOT be confirmed — the caller restarts the loop.
local function sweepFields(stageName)
    local usedCombine = false
    if stageName == "HARVEST" then
        usedCombine = sitInEquipment(CONFIG.harvestTool)
        if not usedCombine then
            log("could not enter the combine (" .. tostring(CONFIG.harvestTool) .. ") - restarting loop")
            return false
        end
    end
    if not usedCombine then
        if not sitTractor() then
            log("could not enter the tractor seat - restarting loop")
            return false
        end
        local impl = stageImplement(stageName)
        if impl and stageName ~= "HARVEST" and not hitchTo(impl) then
            log("could not hitch " .. tostring(impl) .. " - restarting loop")
            return false
        end
    end
    if stageName == "PLANT" then loadSeeds() end
    local myPlot = findMyPlot()
    if myPlot then log("sweeping plot " .. myPlot.Name .. " (\"Your Farm\")") end
    local hit = 0
    for _, name in ipairs(CONFIG.fieldNames) do
        local items = {}
        if myPlot then
            for _, v in ipairs(myPlot:GetDescendants()) do
                if v:IsA("BasePart") and nameMatch(v, name) then
                    table.insert(items, { part = v })
                end
            end
        end
        if #items == 0 then items = findAll(name, 4000) end
        for _, item in ipairs(items) do
            if not Farm.enabled then return hit end
            Farm.status = stageName .. " tile " .. (hit + 1)
            driveTo(item.part.Position, 4)
            hit += 1
            hwait(0.8)
        end
        if hit > 0 then break end
    end
    if hit == 0 then log("no field tiles found (fix 'field' name in Settings)") end
    return hit
end

local function farmStep()
    local stage = STAGES[Farm.stage]
    if stage == "GROW" then
        Farm.status = "GROW " .. tostring(CONFIG.crop) .. " (" .. math.floor(CONFIG.growWait / 60) .. " min)"
        local waited = 0
        while Farm.enabled and waited < CONFIG.growWait do
            task.wait(1)
            waited += 1
        end
    elseif stage == "SELL" then
        Farm.status = "SELL"
        if Farm.autoSell then
            sellAt(CONFIG.shopName)
        end
        Farm.round += 1
        log("farm round " .. Farm.round .. " complete")
        webhookSend("🌾 Farm round " .. Farm.round .. " complete · " .. tostring(CONFIG.crop) .. cropProfitNote() .. coinsNote())
    else
        local ok = sweepFields(stage)
        if ok == false then
            -- nothing worked (seat / hitch not confirmed) → restart the loop
            log(stage .. " could not run - restarting the loop from PLOW")
            webhookSend("🔁 " .. stage .. " failed - restarting the loop")
            Farm.stage = 1
            hwait(4)
            return
        end
    end
    if Farm.enabled then
        Farm.stage = Farm.stage % #STAGES + 1
    end
end

task.spawn(function()
    while task.wait(0.2) do
        if Farm.enabled then
            local ok, err = pcall(farmStep)
            if not ok then warn("[spud] farm step error: " .. tostring(err)) end
            hwait(1.5)
        else
            Farm.status = "idle"
        end
    end
end)

------------------------------------------------------------
-- PRESET ENGINE
------------------------------------------------------------
local Presets = {}
local PresetOrder = {}
local Active = { name = nil, running = false, loop = false, stop = false }

function Presets.register(name, fn)
    if not Presets[name] then table.insert(PresetOrder, name) end
    Presets[name] = fn
end

function Presets.run(name, loop)
    if not Presets[name] then return false end
    Presets.stop()
    task.wait(0.5)
    Active.name, Active.running, Active.loop, Active.stop = name, true, loop, false
    local myName = name
    task.spawn(function()
        repeat
            local ok, err = pcall(Presets[myName])
            if not ok then warn("[spud] preset error: " .. tostring(err)) end
            hwait(4)
        until Active.stop or not Active.running or Active.name ~= myName or not Active.loop
        Active.running = false
        if Active.name == myName then Active.name = nil end
        log("preset stopped: " .. myName)
    end)
    return true
end

function Presets.stop()
    Active.stop = true
    Active.running = false
end

------------------------------------------------------------
-- BARN STALL CLEANING — dump-confirmed context: CleanAnimalContainer = V
-- Stall points are parts named "Adornee_BarnStallMenu" (16 across the
-- barns). We go to OUR plot first so we never wander into a neighbour's
-- barn, then stand at each stall and press V — the game no-ops on stalls
-- that are already clean. EVTFilthCleaning is the server side of this.
------------------------------------------------------------
local function cleanBarnStalls()
    local plot = findMyPlot()
    if plot then
        driveTo(plot:GetPivot().Position, 5)
        hwait(0.8)
    end
    local stalls = findAll(CONFIG.stallMarker, 700)
    if #stalls == 0 then
        log("no barn stalls near your farm — barn not built yet? (marker: " .. CONFIG.stallMarker .. ")")
        return 0
    end
    log("cleaning " .. #stalls .. " barn stall(s)…")
    local cleaned = 0
    for _, s in ipairs(stalls) do
        if Active and Active.stop then break end
        driveTo(s.part.Position, 3)
        hwait(0.7)
        pressKey("V")   -- CleanAnimalContainer (dump-confirmed bind)
        cleaned += 1
        hwait(1.2)
    end
    pressKey("X")   -- drop anything a stall handed us
    hwait(0.3)
    log("stall cleaning pass done (" .. cleaned .. "/" .. #stalls .. ")")
    return cleaned
end

Presets.register("Barn Care", function()
    log("[Barn] 1/1 cleaning stalls")
    local n = cleanBarnStalls()
    webhookSend("🧹 Barn Care pass · " .. n .. " stall(s) cleaned" .. coinsNote())
end)

------------------------------------------------------------
-- PRESET: CHOCOLATE MILK (8 steps, wiki-accurate)
------------------------------------------------------------
Presets.register("Chocolate Milk", function()
    local C = CONFIG.presets.chocolateMilk

    log("[CM] 0/8 cleaning barn stalls (clean stalls = happier cows)")
    if Active.stop then return end
    cleanBarnStalls()

    log("[CM] 1/8 milking cows")
    local milker = getTool(C.milkerTool)
    for _, c in ipairs(findAll(C.cowName, 1000)) do
        if Active.stop then return end
        if milker then
            equip(milker)
            local t = Character and Character:FindFirstChildOfClass("Tool")
            if t then
                try(function() t:Activate() end)
                hwait(1.4)
                try(function() t:Deactivate() end)
            end
        else
            interactWith(c.part)
        end
    end
    collectDrops(C.milkDrop, 800, 20)

    if Active.stop then return end
    log("[CM] 2/8 depositing milk on the factory platform")
    local mPad = nearest(C.milkDeposit, 2000)
    -- deposit onto the factory input = context key X (dump-confirmed)
    if mPad then driveTo(mPad.Position); hwait(1.0); interactWith(mPad, "X") end

    if Active.stop then return end
    log("[CM] 3/8 harvesting cocoa")
    local tree = nearest(C.cocoaTree, 800)
    if tree then
        activate(C.cocoaHarvester, 2.5)
        collectDrops(C.cocoaDrop, 600, 10)
    end

    if Active.stop then return end
    log("[CM] 4/8 depositing cocoa")
    local cPad = nearest(C.cocoaDeposit, 2000)
    if cPad then driveTo(cPad.Position); hwait(1.0); interactWith(cPad, "X") end

    if Active.stop then return end
    log("[CM] 5/8 pulling factory levers")
    local factory = nearest(C.factoryName, 3000)
    if factory then pullLevers(factory) end

    if Active.stop then return end
    log("[CM] 6/8 processing " .. C.processWait .. "s")
    local waited = 0
    while waited < C.processWait and not Active.stop do
        task.wait(1)
        waited += 1
    end

    if Active.stop then return end
    log("[CM] 7/8 collecting chocolate milk")
    collectDrops(C.productName, 800, 10)

    if Active.stop then return end
    log("[CM] 8/8 selling at the platform")
    sellAt(C.shopName)
    log("[CM] cycle complete")
    webhookSend("🍫 Chocolate Milk cycle complete" .. coinsNote())
end)

------------------------------------------------------------
-- PRESET: CAKE & EGGS
------------------------------------------------------------
Presets.register("Cake & Eggs", function()
    local C = CONFIG.presets.cakeEggs

    log("[Cake] 1/7 collecting eggs (12 = 1 egg box)")
    for _, coop in ipairs(findAll(C.coopName, 1500)) do
        if Active.stop then return end
        interactWith(coop.part)
        hwait(1.0)
    end
    collectDrops(C.eggDrop, 800, 20)

    if Active.stop then return end
    log("[Cake] 2/7 milking cows")
    local milker = getTool(C.milkerTool)
    for _, c in ipairs(findAll(C.cowName, 1000)) do
        if Active.stop then return end
        if milker then
            equip(milker)
            local t = Character and Character:FindFirstChildOfClass("Tool")
            if t then
                try(function() t:Activate() end)
                hwait(1.4)
                try(function() t:Deactivate() end)
            end
        else
            interactWith(c.part)
        end
    end
    collectDrops(C.milkDrop, 800, 20)

    if Active.stop then return end
    log("[Cake] 3/7 depositing ingredients (wheat + milk left side, eggs on conveyor)")
    local wPad = nearest(C.wheatDeposit, 2000)
    if wPad then driveTo(wPad.Position); hwait(1.0); interactWith(wPad, "X") end
    local mPad = nearest(C.milkDeposit, 2000)
    if mPad then driveTo(mPad.Position); hwait(1.0); interactWith(mPad, "X") end
    local ePad = nearest(C.eggDeposit, 2000)
    if ePad then driveTo(ePad.Position); hwait(1.0); interactWith(ePad, "X") end

    if Active.stop then return end
    log("[Cake] 4/7 pulling factory levers (right → opposite → below belt → upstairs)")
    local factory = nearest(C.factoryName, 3000)
    if factory then pullLevers(factory) end

    if Active.stop then return end
    log("[Cake] 5/7 processing " .. C.processWait .. "s")
    local waited = 0
    while waited < C.processWait and not Active.stop do
        task.wait(1)
        waited += 1
    end

    if Active.stop then return end
    log("[Cake] 6/7 loading batter into the oven")
    collectDrops(C.batterDrop, 800, 20)
    local oven = nearest(C.ovenName, 3000)
    if oven then
        driveTo(oven.Position, 3)
        hwait(1.0)
        interactWith(oven, "X") -- PlaceInMachine = X (dump-confirmed)
    end
    local baked = 0
    while baked < C.bakeWait and not Active.stop do
        task.wait(1)
        baked += 1
    end

    if Active.stop then return end
    log("[Cake] 7/7 collecting cakes + selling")
    collectDrops(C.productName, 800, 10)
    sellAt(C.shopName)
    log("[Cake] cycle complete")
    webhookSend("🎂 Cake & Eggs cycle complete" .. coinsNote())
end)

------------------------------------------------------------
-- PRESET: WOOL RUN
------------------------------------------------------------
Presets.register("Wool Run", function()
    local C = CONFIG.presets.wool

    log("[Wool] 1/4 shearing sheep")
    local shears = getTool(C.shearsTool)
    for _, s in ipairs(findAll(C.sheepName, 1000)) do
        if Active.stop then return end
        if shears then
            equip(shears)
            driveTo(s.part.Position, 3)
            hwait(0.8)
            local t = Character and Character:FindFirstChildOfClass("Tool")
            if t then
                try(function() t:Activate() end)
                hwait(1.6)
                try(function() t:Deactivate() end)
            end
        else
            -- UseShears = V (dump-confirmed). V without shears held is a
            -- safe no-op — unlike E, which could carry the sheep away.
            interactWith(s.part, "V")
        end
    end
    collectDrops(C.woolDrop, 800, 20)

    if Active.stop then return end
    log("[Wool] 2/4 bundling at the spindel (5 raw wool → 1 bundle)")
    local spindel = nearest(C.spindelName, 2000)
    if spindel then
        for _ = 1, 3 do
            if Active.stop then return end
            driveTo(spindel.Position, 3)
            hwait(1.0)
            -- Spindle.Deposit = V (dump-confirmed); loop is bounded to 3
            interactWith(spindel, "V")
            hwait(1.5)
        end
    end

    if Active.stop then return end
    log("[Wool] 3/4 collecting bundles")
    collectDrops(C.bundleDrop, 800, 10)

    if Active.stop then return end
    log("[Wool] 4/4 selling at AnimalCo")
    sellAt(C.shopName)
    log("[Wool] cycle complete")
    webhookSend("🐑 Wool Run cycle complete" .. coinsNote())
end)

------------------------------------------------------------
-- SESSION LIMITER + CROWD GUARD (behavioral layer mitigation)
------------------------------------------------------------
local Session = {
    activeMinutes = 0,
    onBreak       = false,
    resumeFarm    = false,
    resumePreset  = nil,
}

task.spawn(function()
    while task.wait(60) do
        local automating = Farm.enabled or Active.running
        if Stealth.enabled and Stealth.sessionLimitOn and not Session.onBreak then
            if automating then
                Session.activeMinutes += 1
                if Session.activeMinutes >= Stealth.sessionLimit then
                    -- take a human-looking break
                    Session.onBreak = true
                    Session.resumeFarm = Farm.enabled
                    Session.resumePreset = Active.loop and Active.name or nil
                    Farm.enabled = false
                    Presets.stop()
                    notify("Stealth break: pausing " .. Stealth.breakLength .. " min (session limit)")
                    log("stealth break started")
                    webhookSend("⏸ Stealth break started (" .. Stealth.breakLength .. " min) · session limit reached")
                    task.wait(Stealth.breakLength * 60)
                    Session.activeMinutes = 0
                    Session.onBreak = false
                    if Session.resumeFarm then Farm.enabled = true end
                    if Session.resumePreset then Presets.run(Session.resumePreset, true) end
                    notify("Break over — resuming")
                    log("stealth break ended")
                    webhookSend("▶ Break over — automation resumed")
                end
            else
                Session.activeMinutes = math.max(0, Session.activeMinutes - 1)
            end
        end
    end
end)

------------------------------------------------------------
-- PLAYER MODS (passive loops)
------------------------------------------------------------
local NcLast = 0
RunService.Stepped:Connect(function()
    if Options.NoClip and Character then
        -- NoClip is high-risk (StrafingNoPhysics check); force it off in stealth
        if Stealth.enabled then
            Options.NoClip = false
            notify("NoClip auto-off: stealth mode blocks wall-walking")
            return
        end
        local now = os.clock()
        if now - NcLast < 0.15 then return end   -- 6-7 Hz is plenty
        NcLast = now
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if Options.InfiniteJump and Humanoid then
        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

LocalPlayer.Idled:Connect(function()
    if Options.AntiAFK then
        try(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- Ctrl + Click teleport
UserInputService.InputBegan:Connect(function(input)
    if Options.ClickTeleport
        and input.UserInputType == Enum.UserInputType.MouseButton1
        and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        and RootPart then
        local cam = Workspace.CurrentCamera
        local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { Character }
        params.FilterType = Enum.RaycastFilterType.Exclude
        local hit = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
        if hit then driveTo(hit.Position, 5) end
    end
end)

-- FPS boost
local function applyFpsBoost(enabled)
    if enabled then
        try(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        for _, obj in ipairs(Lighting:GetDescendants()) do
            if obj:IsA("Atmosphere") or obj:IsA("Sky") then obj.Enabled = false end
        end
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:lower():find("grass") then obj:Destroy() end
        end
        log("FPS boost on")
    else
        try(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
        log("FPS boost off")
    end
end

-- movement application (clamped by stealth caps)
local NotifiedClamp = false
task.spawn(function()
    while task.wait(0.25) do
        if Humanoid and Humanoid.Parent then
            if Options.SpeedEnabled then
                local sp = Options.WalkSpeed
                if Stealth.enabled and sp > Stealth.speedCap then
                    sp = Stealth.speedCap
                    if not NotifiedClamp then
                        NotifiedClamp = true
                        notify("Walkspeed clamped to " .. Stealth.speedCap .. " (stealth)")
                    end
                end
                Humanoid.WalkSpeed = sp
            end
            if Options.JumpEnabled then
                Humanoid.UseJumpPower = true
                local jp = Options.JumpPower
                if Stealth.enabled and jp > Stealth.jumpCap then jp = Stealth.jumpCap end
                Humanoid.JumpPower = jp
            end
        end
    end
end)

------------------------------------------------------------
-- GUI — SPUD palette
------------------------------------------------------------
COL = {
    Bg      = Color3.fromRGB(20, 22, 28),
    Panel   = Color3.fromRGB(30, 33, 41),
    Panel2  = Color3.fromRGB(45, 49, 60),
    Accent  = Color3.fromRGB(255, 184, 66),
    Accent2 = Color3.fromRGB(200, 140, 40),
    Text    = Color3.fromRGB(235, 237, 240),
    Sub     = Color3.fromRGB(150, 155, 165),
    Green   = Color3.fromRGB(80, 220, 100),
    Red     = Color3.fromRGB(150, 60, 60),
}

function mk(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end

function corner(inst, r)
    return mk("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
end

local screen = mk("ScreenGui", {
    Name = "SpudFarmGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = guiParent(),
})

local main = mk("Frame", {
    Parent = screen,
    Size = UDim2.new(0, 540, 0, 400),
    Position = UDim2.new(0.5, -270, 0.5, -200),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corner(main, 10)
mk("UIStroke", { Color = Color3.fromRGB(60, 64, 74), Thickness = 1, Parent = main })

-- title bar
local titleBar = mk("Frame", {
    Parent = main,
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
corner(titleBar, 10)
mk("Frame", {
    Parent = titleBar,
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
mk("TextLabel", {
    Parent = titleBar,
    Size = UDim2.new(1, -150, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "🥔 SPUD FARM",
    TextColor3 = COL.Accent,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local statusDot = mk("Frame", {
    Parent = titleBar,
    Size = UDim2.new(0, 10, 0, 10),
    Position = UDim2.new(1, -134, 0.5, -5),
    BackgroundColor3 = COL.Sub,
    BorderSizePixel = 0,
})
corner(statusDot, 5)

local minimizeBtn = mk("TextButton", {
    Parent = titleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -64, 0.5, -13),
    BackgroundColor3 = COL.Panel2,
    Text = "–",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    AutoButtonColor = false,
})
corner(minimizeBtn, 6)

local webhookBtn = mk("TextButton", {
    Parent = titleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -98, 0.5, -13),
    BackgroundColor3 = COL.Panel2,
    Text = "📡",
    TextColor3 = COL.Text,
    Font = Enum.Font.Gotham,
    TextSize = 13,
    AutoButtonColor = false,
})
corner(webhookBtn, 6)

local closeBtn = mk("TextButton", {
    Parent = titleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -32, 0.5, -13),
    BackgroundColor3 = COL.Red,
    Text = "X",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
})
corner(closeBtn, 6)

-- sidebar + content
local sidebar = mk("Frame", {
    Parent = main,
    Size = UDim2.new(0, 130, 1, -40),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
local content = mk("Frame", {
    Parent = main,
    Size = UDim2.new(1, -130, 1, -40),
    Position = UDim2.new(0, 130, 0, 40),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
})

local tabs = {}
local tabButtons = {}
local selectTab -- forward declaration (used inside makeTab)

local function makeTab(name, icon)
    local page = mk("ScrollingFrame", {
        Parent = content,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COL.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    })
    mk("UIListLayout", {
        Parent = page,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    mk("UIPadding", {
        Parent = page,
        PaddingTop = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    })

    local btn = mk("TextButton", {
        Parent = sidebar,
        Size = UDim2.new(1, -16, 0, 34),
        Position = UDim2.new(0, 8, 0, 10 + #tabButtons * 40),
        BackgroundColor3 = COL.Bg,
        Text = icon .. "  " .. name,
        TextColor3 = COL.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        AutoButtonColor = false,
    })
    corner(btn, 6)

    table.insert(tabButtons, { btn = btn, page = page })
    tabs[name] = page

    btn.Activated:Connect(function()
        selectTab(name)
    end)

    return page
end

function selectTab(name)
    for _, t in ipairs(tabButtons) do
        local isActive = (t.page == tabs[name])
        t.page.Visible = isActive
        t.btn.BackgroundColor3 = isActive and COL.Accent or COL.Bg
        t.btn.TextColor3       = isActive and COL.Bg or COL.Sub
    end
end

------------------------------------------------------------
-- CONTROL BUILDERS
------------------------------------------------------------
local function sectionLabel(parent, text, order)
    return mk("TextLabel", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "— " .. string.upper(text) .. " —",
        TextColor3 = COL.Sub,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function makeToggle(parent, text, default, callback, order)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    })
    corner(row, 6)
    mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local pill = mk("Frame", {
        Parent = row,
        Size = UDim2.new(0, 38, 0, 20),
        Position = UDim2.new(1, -48, 0.5, -10),
        BackgroundColor3 = COL.Bg,
        BorderSizePixel = 0,
    })
    corner(pill, 10)
    local dot = mk("Frame", {
        Parent = pill,
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = Color3.fromRGB(180, 182, 190),
        BorderSizePixel = 0,
    })
    corner(dot, 7)

    local state = default or false
    local function apply(anim)
        local info = TweenInfo.new(anim and 0.15 or 0, Enum.EasingStyle.Quad)
        TweenService:Create(pill, info, { BackgroundColor3 = state and COL.Accent2 or COL.Bg }):Play()
        TweenService:Create(dot, info, {
            Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
            BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(180, 182, 190),
        }):Play()
    end
    apply(false)

    row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            state = not state
            apply(true)
            task.spawn(callback, state)
        end
    end)

    return {
        Set = function(_, v) state = v; apply(false); task.spawn(callback, state) end,
        Get = function(_) return state end,
    }
end

local function makeSlider(parent, text, min, max, default, callback, order, suffix)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
    })
    corner(row, 6)
    mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -70, 0, 20),
        Position = UDim2.new(0, 12, 0, 5),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local valueLabel = mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(0, 64, 0, 20),
        Position = UDim2.new(1, -76, 0, 5),
        BackgroundTransparency = 1,
        Text = tostring(default) .. (suffix or ""),
        TextColor3 = COL.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local bar = mk("Frame", {
        Parent = row,
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 1, -16),
        BackgroundColor3 = COL.Bg,
        BorderSizePixel = 0,
    })
    corner(bar, 3)
    local fill = mk("Frame", {
        Parent = bar,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COL.Accent,
        BorderSizePixel = 0,
    })
    corner(fill, 3)
    local knob = mk("Frame", {
        Parent = bar,
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(0, -6, 0.5, -6),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    })
    corner(knob, 6)

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local val = math.floor(min + (max - min) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -6, 0.5, -6)
        valueLabel.Text = tostring(val) .. (suffix or "")
        callback(val)
    end
    do
        local rel = (default - min) / math.max(max - min, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -6, 0.5, -6)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return {
        Label = valueLabel,
        -- visual set (no callback) — used when the crop dropdown sets grow time
        Set = function(_, val)
            val = math.floor(math.clamp(val, min, max) + 0.5)
            local rel = (val - min) / math.max(max - min, 1)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, -6, 0.5, -6)
            valueLabel.Text = tostring(val) .. (suffix or "")
        end,
    }
end

local function makeButton(parent, text, color, callback, order)
    local btn = mk("TextButton", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = color or COL.Panel2,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
    })
    corner(btn, 6)
    btn.Activated:Connect(function()
        task.spawn(callback)
    end)
    return btn
end

local function makeDropdown(parent, text, options, default, callback, order)
    local container = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 5,
    })
    corner(container, 6)
    mk("TextLabel", {
        Parent = container,
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })
    local selected = default or options[1]
    local btn = mk("TextButton", {
        Parent = container,
        Size = UDim2.new(0, 92, 0, 26),
        Position = UDim2.new(1, -102, 0.5, -13),
        BackgroundColor3 = COL.Bg,
        Text = selected .. " ▾",
        TextColor3 = COL.Accent,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 6,
    })
    corner(btn, 5)

    local list = mk("ScrollingFrame", {
        Parent = container,
        Size = UDim2.new(1, -20, 0, 0),
        Position = UDim2.new(0, 10, 1, 4),
        BackgroundColor3 = COL.Panel2,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, #options * 26),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        MaxCanvasSize = Vector2.new(0, 0, 0, 150),
        ClipsDescendants = true,
    })
    corner(list, 6)
    mk("UIListLayout", { Parent = list, Padding = UDim.new(0, 2) })

    for _, opt in ipairs(options) do
        local item = mk("TextButton", {
            Parent = list,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = COL.Bg,
            Text = opt,
            TextColor3 = COL.Text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            AutoButtonColor = false,
            ZIndex = 21,
        })
        corner(item, 4)
        item.Activated:Connect(function()
            selected = opt
            btn.Text = opt .. " ▾"
            list.Visible = false
            container.ZIndex = 5
            callback(opt)
        end)
    end

    btn.Activated:Connect(function()
        list.Visible = not list.Visible
        container.ZIndex = list.Visible and 50 or 5
    end)

    return { Set = function(_, v) selected = v; btn.Text = v .. " ▾"; callback(v) end }
end

local function makeTextbox(parent, label, default, callback, order)
    local row = mk("Frame", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Panel,
        BorderSizePixel = 0,
    })
    corner(row, 6)
    mk("TextLabel", {
        Parent = row,
        Size = UDim2.new(0.45, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = COL.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local box = mk("TextBox", {
        Parent = row,
        Size = UDim2.new(0.5, -18, 0, 24),
        Position = UDim2.new(0.5, 6, 0.5, -12),
        BackgroundColor3 = COL.Bg,
        Text = default or "",
        PlaceholderText = "type here...",
        PlaceholderColor3 = COL.Sub,
        TextColor3 = COL.Accent,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = false,
    })
    corner(box, 5)
    box.FocusLost:Connect(function()
        if box.Text ~= "" then callback(box.Text) end
    end)
    return box
end

local function makeInfo(parent, text, order)
    return mk("TextLabel", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        AutomaticSize = Enum.AutomaticSize.Y,
    })
end

local function makeStatus(parent, order)
    return mk("TextLabel", {
        Parent = parent,
        LayoutOrder = order or 0,
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = COL.Sub,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
end

------------------------------------------------------------
-- WEBHOOK WINDOW (its own UI) + 🥔 MINIMIZE-ALL HOTKEY
------------------------------------------------------------
local webhookWin = mk("Frame", {
    Parent = screen,
    Size = UDim2.new(0, 310, 0, 400),
    Position = UDim2.new(0.5, -155, 0.5, 215),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
})
corner(webhookWin, 10)
mk("UIStroke", { Color = Color3.fromRGB(60, 64, 74), Thickness = 1, Parent = webhookWin })

local webhookTitleBar = mk("Frame", {
    Parent = webhookWin,
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
corner(webhookTitleBar, 10)
mk("Frame", {
    Parent = webhookTitleBar,
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = COL.Panel,
    BorderSizePixel = 0,
})
mk("TextLabel", {
    Parent = webhookTitleBar,
    Size = UDim2.new(1, -50, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "📡 WEBHOOK",
    TextColor3 = COL.Accent,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local webhookClose = mk("TextButton", {
    Parent = webhookTitleBar,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -32, 0.5, -13),
    BackgroundColor3 = COL.Red,
    Text = "X",
    TextColor3 = COL.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
})
corner(webhookClose, 6)

local webhookContent = mk("Frame", {
    Parent = webhookWin,
    Size = UDim2.new(1, 0, 1, -40),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundTransparency = 1,
})
mk("UIListLayout", {
    Parent = webhookContent,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
mk("UIPadding", {
    Parent = webhookContent,
    PaddingTop = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
    PaddingBottom = UDim.new(0, 8),
})

makeTextbox(webhookContent, "Webhook URL", Webhook.url, function(v)
    Webhook.url = (v:gsub("^%s+", ""):gsub("%s+$", ""))
    notify("Webhook URL saved")
end, 1)
makeToggle(webhookContent, "Send logs to Discord", false, function(v)
    if v and Webhook.url == "" then
        notify("Paste your webhook URL first")
        Webhook.enabled = false
        return
    end
    Webhook.enabled = v
    feedLine(v and "— webhook logging ON —" or "— webhook logging OFF —")
    notify(v and "Webhook logging ON" or "Webhook logging OFF")
end, 2)
makeButton(webhookContent, "📤 Send test message", COL.Panel2, function()
    if Webhook.url == "" then
        notify("Paste your webhook URL first")
        return
    end
    local wasEnabled = Webhook.enabled
    Webhook.enabled = true
    webhookSend("✅ Test message from SPUD FARM" .. coinsNote())
    Webhook.enabled = wasEnabled
    notify("Test queued (check your Discord in a few seconds)")
end, 3)
makeInfo(webhookContent, "Logs: load, farm rounds (crop + coin gains), preset cycles, stealth breaks. Queue is rate-limited for Discord (≈1 msg / 6.5s). Anyone with your webhook URL can post to your Discord — don't share your saved URL.", 4)

mk("TextLabel", {
    Parent = webhookContent,
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = "LIVE FEED",
    TextColor3 = COL.Accent,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
})
WebhookFeed = mk("ScrollingFrame", {
    Parent = webhookContent,
    LayoutOrder = 6,
    Size = UDim2.new(1, 0, 0, 130),
    BackgroundColor3 = COL.Bg,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = COL.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
corner(WebhookFeed, 6)
mk("UIListLayout", {
    Parent = WebhookFeed,
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
mk("UIPadding", {
    Parent = WebhookFeed,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6),
})

local webhookStatus = makeStatus(webhookContent, 7)
task.spawn(function() -- 0.5s ticker (was a per-frame RenderStepped connection)
    while screen.Parent do
        if Webhook.enabled then
            webhookStatus.Text = Webhook.url ~= "" and ("ON · queued " .. #Webhook.queue .. "/20") or "ON · URL MISSING"
        else
            webhookStatus.Text = "OFF · feed only (local)"
        end
        task.wait(0.5)
    end
end)

-- title bar 📡 button toggles this window
webhookBtn.Activated:Connect(function()
    webhookWin.Visible = not webhookWin.Visible
end)
webhookClose.Activated:Connect(function()
    webhookWin.Visible = false
end)

-- drag webhook window by its title bar
do
    local dragging, dragStart, startPos
    webhookTitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = webhookWin.Position
        end
    end)
    webhookTitleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            webhookWin.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- 🥔 potato hotkey: its own ScreenGui so it stays visible when every
-- other window is hidden. Click = hide all / show all. Also draggable.
local hotGui = mk("ScreenGui", {
    Name = "SpudFarmHotkey",
    ResetOnSpawn = false,
    DisplayOrder = 999,
    Parent = guiParent(),
})
local potatoBtn = mk("TextButton", {
    Parent = hotGui,
    Size = UDim2.new(0, 44, 0, 44),
    Position = UDim2.new(0, 10, 0.5, -22),
    BackgroundColor3 = COL.Panel2,
    Text = "🥔",
    TextColor3 = COL.Text,
    Font = Enum.Font.Gotham,
    TextSize = 22,
    AutoButtonColor = false,
})
corner(potatoBtn, 14)
local potatoStroke = mk("UIStroke", { Color = COL.Accent, Thickness = 1.5, Parent = potatoBtn })

local UIState = { hidden = false }
local function setAllVisible(v)
    UIState.hidden = not v
    main.Visible = v
    webhookWin.Visible = v
    potatoBtn.BackgroundColor3 = v and COL.Panel2 or COL.Accent2
    potatoStroke.Color = v and COL.Accent or COL.Text
end
local function toggleAll()
    setAllVisible(UIState.hidden)
end

do
    local dragging, dragStart, startPos, moved
    potatoBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = potatoBtn.Position
            moved = false
        end
    end)
    potatoBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and not moved then
                toggleAll() -- click (no drag) → hide all / show all
            end
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then moved = true end
            potatoBtn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

------------------------------------------------------------
-- TABS
------------------------------------------------------------
local farmTab      = makeTab("Farm", "🌾")
local presetsTab   = makeTab("Presets", "🍫")
local playerTab    = makeTab("Player", "🚶")
local tpTab        = makeTab("Teleport", "🧭")
local stealthTab   = makeTab("Stealth", "🕶")
local settingsTab  = makeTab("Settings", "⚙")

-- FARM TAB
local CROPS = { "Wheat", "Corn", "Rice", "Oat", "Sugar Cane", "Soybeans", "Tomatoes", "Cabbage", "Carrots", "Potatoes", "Cocoa", "Grape", "Custom" }
local growSlider
local cropInfoLbl -- forward decl: label under the crop dropdown

local function cropInfoText(name)
    if name == "Custom" then
        return "Custom crop — set grow time with the slider below"
    end
    local t = CONFIG.cropGrowTimes[name]
    local p = CONFIG.cropProfit[name]
    local note = CONFIG.cropNotes[name]
    local s = name
    if t then
        local mins = t / 60
        local minsStr = (mins == math.floor(mins)) and (mins .. " min") or (string.format("%.1f min", mins))
        s ..= " · grow " .. minsStr
    end
    if p and p.perHr then
        s ..= " · seed " .. p.cost .. "/box · ≈" .. p.perHr .. "/hr avg"
    end
    if note then
        s ..= " · " .. note
    end
    s ..= " · prices rotate ~5 min (rainbow = peak)"
    return s
end

sectionLabel(farmTab, "Farming", 1)
makeToggle(farmTab, "Farming (auto cycle)", false, function(v)
    Farm.enabled = v
    notify(v and ("Farming ON — stage " .. STAGES[Farm.stage]) or "Farming OFF")
end, 2)
makeToggle(farmTab, "Auto-Sell after harvest", true, function(v)
    Farm.autoSell = v
end, 3)
makeDropdown(farmTab, "Crop", CROPS, CONFIG.crop, function(v)
    CONFIG.crop = v
    local t = CONFIG.cropGrowTimes[v]
    if t then
        CONFIG.growWait = t
        if growSlider then growSlider:Set(t / 60) end
        notify(v .. " selected — grow " .. math.floor(t / 60) .. " min")
    else
        notify(v .. " selected — set grow time with the slider")
    end
    if cropInfoLbl then cropInfoLbl.Text = cropInfoText(v) end
end, 4)
cropInfoLbl = makeInfo(farmTab, cropInfoText(CONFIG.crop), 5)
growSlider = makeSlider(farmTab, "Grow time", 1, 60, math.floor(CONFIG.growWait / 60), function(v)
    CONFIG.growWait = v * 60
end, 6, " min")

sectionLabel(farmTab, "Control", 7)
makeButton(farmTab, "Skip Stage", COL.Panel2, function()
    Farm.stage = Farm.stage % #STAGES + 1
    log("skipped to " .. STAGES[Farm.stage])
end, 8)
makeButton(farmTab, "Reset to Plow", COL.Panel2, function()
    Farm.stage = 1
    log("reset to PLOW")
end, 9)

local farmStatus = makeStatus(farmTab, 10)
task.spawn(function() -- 0.5s ticker (was per-frame)
    while screen.Parent do
        if Farm.enabled then
            farmStatus.Text = "stage " .. STAGES[Farm.stage] .. " · round " .. Farm.round .. " · RUNNING"
            statusDot.BackgroundColor3 = COL.Green
        else
            farmStatus.Text = "stage " .. STAGES[Farm.stage] .. " · round " .. Farm.round .. " · PAUSED"
            statusDot.BackgroundColor3 = COL.Red
        end
        task.wait(0.5)
    end
end)

-- live sell prices (read from the in-game SellValueBoards; read-only)
-- selected crop is shown first (⭐) with singular/plural matching
-- (board uses "Tomato", dropdown says "Tomatoes")
local priceStatus = makeStatus(farmTab, 11)
task.spawn(function()
    while screen and screen.Parent do
        local rows = readSellBoards()
        if #rows > 0 then
            local cropKey = tostring(CONFIG.crop):lower()
            local parts, seen = {}, {}
            local function add(r, star)
                local key = r.name .. "=" .. r.value
                if not seen[key] and #parts < 6 then
                    seen[key] = true
                    table.insert(parts, (star and "⭐" or "") .. r.name .. " " .. r.value)
                end
            end
            for _, r in ipairs(rows) do
                local n = r.name:lower()
                if n == cropKey or (n .. "s") == cropKey or n == cropKey:gsub("s$", "") then
                    add(r, true)
                end
            end
            for _, r in ipairs(rows) do add(r, false) end
            priceStatus.Text = "💰 " .. table.concat(parts, " · ")
        else
            priceStatus.Text = "💰 price board not loaded — walk near the stores"
        end
        task.wait(3)
    end
end)

-- PRESETS TAB
sectionLabel(presetsTab, "Presets", 1)
makeInfo(presetsTab, "Click a preset to run it once. Flip LOOP on first to repeat. Click again (or STOP) to halt — stop interrupts mid-chain. Names are wiki-based; fix in Settings if a step misses.", 2)

local presetLoop = false
local presetButtons = {}
for i, name in ipairs(PresetOrder) do
    presetButtons[name] = makeButton(presetsTab, "▶  " .. name, COL.Panel2, function()
        if Active.name == name then
            Presets.stop()
        else
            Presets.run(name, presetLoop)
        end
    end, 2 + i)
end

sectionLabel(presetsTab, "Control", 10)
local loopBtn
loopBtn = makeButton(presetsTab, "LOOP: OFF", COL.Panel2, function()
    presetLoop = not presetLoop
    loopBtn.Text = presetLoop and "LOOP: ON" or "LOOP: OFF"
    loopBtn.BackgroundColor3 = presetLoop and COL.Accent2 or COL.Panel2
end, 11)
makeButton(presetsTab, "STOP", COL.Red, function()
    Presets.stop()
end, 12)

local presetStatus = makeStatus(presetsTab, 13)
task.spawn(function() -- 0.5s ticker (was per-frame)
    while screen.Parent do
        presetStatus.Text = Active.running and ("running: " .. tostring(Active.name)) or "idle"
        for name, b in pairs(presetButtons) do
            local on = (Active.name == name)
            b.BackgroundColor3 = on and COL.Accent2 or COL.Panel2
            b.TextColor3       = on and COL.Accent or COL.Text
        end
        task.wait(0.5)
    end
end)

-- PLAYER TAB
sectionLabel(playerTab, "Movement", 1)
makeToggle(playerTab, "Custom Walkspeed", false, function(v)
    Options.SpeedEnabled = v
    if not v and Humanoid then Humanoid.WalkSpeed = 16 end
end, 2)
makeSlider(playerTab, "Walkspeed", 16, 200, 16, function(v)
    Options.WalkSpeed = v
end, 3)
makeToggle(playerTab, "Custom Jump Power", false, function(v)
    Options.JumpEnabled = v
    if not v and Humanoid then Humanoid.JumpPower = 50 end
end, 4)
makeSlider(playerTab, "Jump Power", 50, 250, 50, function(v)
    Options.JumpPower = v
end, 5)
makeToggle(playerTab, "Infinite Jump", false, function(v)
    Options.InfiniteJump = v
end, 6)
makeToggle(playerTab, "NoClip (high risk — stealth blocks it)", false, function(v)
    if v and Stealth.enabled then
        notify("NoClip blocked: turn Stealth OFF first if you accept the risk")
        return
    end
    Options.NoClip = v
    notify(v and "NoClip ON" or "NoClip OFF")
end, 7)

sectionLabel(playerTab, "Misc", 8)
makeToggle(playerTab, "Anti-AFK", false, function(v)
    Options.AntiAFK = v
end, 9)
makeToggle(playerTab, "FPS Boost", false, function(v)
    Options.FPSBoost = v
    applyFpsBoost(v)
end, 10)
makeInfo(playerTab, "Note: high Walkspeed/Jump values are the easiest thing for a server to flag. Stealth mode clamps them to human-ish caps automatically.", 11)

-- TELEPORT TAB
sectionLabel(tpTab, "Fast Travel", 1)
makeToggle(tpTab, "Ctrl + Click Teleport", false, function(v)
    Options.ClickTeleport = v
    notify(v and "Ctrl+Click to teleport" or "Click TP OFF")
end, 2)
for i, dest in ipairs(CONFIG.teleports) do
    makeButton(tpTab, "📍 " .. dest.label, COL.Panel2, function()
        if dest.label == "My Farm" then
            -- resolve by ownership billboard, not by name search
            local plot = findMyPlot()
            if plot then
                driveTo(plot:GetPivot().Position, 5)
                notify("Teleported to your plot (" .. plot.Name .. ")")
                return
            end
            notify("Your plot not found (plot billboards not loaded yet)")
            return
        end
        for _, n in ipairs(dest.names) do
            local target = nearest(n, 100000)
            if target then
                driveTo(target.Position, 5)
                notify("Teleported to " .. dest.label)
                return
            end
        end
        notify(dest.label .. " not found")
    end, 2 + i)
end
makeInfo(tpTab, "Movement style follows Settings > Movement: VFly (fast fly + teleport) or Tween (slow safe glide). One-Stop accepts mixed loads of crops, lumber and animal goods; FarmCo prices rotate every ~5 min (rainbow board = peak).", 3 + #CONFIG.teleports)

-- STEALTH TAB
sectionLabel(stealthTab, "Stealth System", 1)
makeInfo(stealthTab, "Reduces server + behavioral detection risk. It cannot hide your executor from Hyperion — nothing in a script can. Use a free VIP server, keep sessions short, don't run in packed public servers.", 2)
makeToggle(stealthTab, "Stealth Mode (master)", true, function(v)
    Stealth.enabled = v
    if v and Options.NoClip then Options.NoClip = false end
    notify(v and "Stealth ON" or "Stealth OFF — instant movement, higher risk")
end, 3)
makeSlider(stealthTab, "Timing jitter", 0, 80, 40, function(v)
    Stealth.jitterAmount = v / 100
end, 4, "%")
makeSlider(stealthTab, "Tween glide speed", 20, 120, 55, function(v)
    Stealth.maxGlide = v
end, 5, " sps")
makeSlider(stealthTab, "Walkspeed clamp", 16, 100, 64, function(v)
    Stealth.speedCap = v
end, 6)
makeSlider(stealthTab, "JumpPower clamp", 50, 150, 90, function(v)
    Stealth.jumpCap = v
end, 7)

sectionLabel(stealthTab, "Session Safety", 8)
makeToggle(stealthTab, "Session limiter", true, function(v)
    Stealth.sessionLimitOn = v
end, 9)
makeSlider(stealthTab, "Break after", 15, 120, 45, function(v)
    Stealth.sessionLimit = v
end, 10, " min")
makeSlider(stealthTab, "Break length", 1, 15, 4, function(v)
    Stealth.breakLength = v
end, 11, " min")
local stealthStatus = makeStatus(stealthTab, 12)
task.spawn(function() -- 0.5s ticker (was per-frame; also polled player count each frame)
    while screen.Parent do
        if Session.onBreak then
            stealthStatus.Text = "ON BREAK · resumes automatically"
        elseif Farm.enabled or Active.running then
            stealthStatus.Text = "active " .. Session.activeMinutes .. "/" .. Stealth.sessionLimit .. " min · " .. #Players:GetPlayers() .. " players"
        else
            stealthStatus.Text = "idle · " .. #Players:GetPlayers() .. " players in server"
        end
        task.wait(0.5)
    end
end)

-- SETTINGS TAB
sectionLabel(settingsTab, "Preferences", 1)
makeToggle(settingsTab, "Notifications", true, function(v)
    Options.Notifications = v
end, 2)

sectionLabel(settingsTab, "Movement", 3)
makeDropdown(settingsTab, "Mode", { "VFly", "Tween" }, Options.MoveMode, function(v)
    Options.MoveMode = v
    notify("Movement: " .. v .. (v == "VFly" and " (fast fly+tp)" or " (slow safe glide)"))
end, 4)
makeSlider(settingsTab, "Vfly speed", 50, 500, 200, function(v)
    Options.VflySpeed = v
end, 5, " sps")
makeInfo(settingsTab, "VFly = BodyVelocity fly + snap teleport (fast, best for farming). Tween = slow stepped glide (safer against movement validation). Vehicles always glide smoothly (no instant snaps) so the server can't rubber-band your position and ignore hitch/keys.", 6)

sectionLabel(settingsTab, "Game Names (fix if a feature misses)", 7)
makeTextbox(settingsTab, "Cow name", CONFIG.presets.chocolateMilk.cowName, function(v)
    CONFIG.presets.chocolateMilk.cowName = v
    notify("Cow name: " .. v)
end, 8)
makeTextbox(settingsTab, "Milker tool", CONFIG.presets.chocolateMilk.milkerTool, function(v)
    CONFIG.presets.chocolateMilk.milkerTool = v
    notify("Milker tool: " .. v)
end, 9)
makeTextbox(settingsTab, "Crop shop", CONFIG.shopName, function(v)
    CONFIG.shopName = v
    notify("Shop: " .. v)
end, 10)
makeTextbox(settingsTab, "Factory name", CONFIG.presets.chocolateMilk.factoryName, function(v)
    CONFIG.presets.chocolateMilk.factoryName = v
    notify("Factory: " .. v)
end, 11)
makeTextbox(settingsTab, "Field tile", CONFIG.fieldNames[1], function(v)
    CONFIG.fieldNames = { v }
    notify("Field tiles: " .. v)
end, 12)
makeTextbox(settingsTab, "Sell key", CONFIG.sellKey, function(v)
    CONFIG.sellKey = v
    notify("Sell key: " .. v:upper())
end, 13)
makeTextbox(settingsTab, "Tractor", CONFIG.tractorName, function(v)
    CONFIG.tractorName = v
    notify("Tractor: " .. v)
end, 14)
makeTextbox(settingsTab, "Barn stall", CONFIG.stallMarker, function(v)
    CONFIG.stallMarker = v
    notify("Barn stall marker: " .. v)
end, 15)

sectionLabel(settingsTab, "Tools & Cake chain", 16)
makeTextbox(settingsTab, "Planter tool", CONFIG.plantTool, function(v)
    CONFIG.plantTool = v
    notify("Planter: " .. v)
end, 17)
makeTextbox(settingsTab, "Harvester tool", CONFIG.harvestTool, function(v)
    CONFIG.harvestTool = v
    notify("Harvester: " .. v)
end, 18)
makeTextbox(settingsTab, "Batter drop", CONFIG.presets.cakeEggs.batterDrop, function(v)
    CONFIG.presets.cakeEggs.batterDrop = v
    notify("Batter drop: " .. v)
end, 19)
makeTextbox(settingsTab, "Oven", CONFIG.presets.cakeEggs.ovenName, function(v)
    CONFIG.presets.cakeEggs.ovenName = v
    notify("Oven: " .. v)
end, 20)

sectionLabel(settingsTab, "Info", 21)
makeInfo(settingsTab, "RIGHT SHIFT shows/hides all windows. 📡 in the title bar opens the webhook panel; 🥔 (potato, left edge of screen) hides every window and brings them back when pressed again. Planter defaults to KGF, harvester to SRC6 (both wiki-confirmed). Names marked as guesses — dump real workspace names (explorer) and type them above; you can list several guesses separated by commas (e.g. \"Milker, Udder Tool\"). Join the Dunn Games group (Farmer's Club) for +5% sell value, and prefer FREE VIP servers for farming sessions.", 22)
makeButton(settingsTab, "⏏ Unload Script", COL.Red, function()
    Farm.enabled = false
    Presets.stop()
    Webhook.enabled = false
    if hotGui then hotGui:Destroy() end
    screen:Destroy()
end, 23)

makeButton(settingsTab, "🔄 Reload latest update", COL.Accent2, function()
    -- 1) fetch the newest version FIRST — if this fails, nothing changes
    notify("Downloading the latest version…")
    local ok, src = pcall(function() return game:HttpGet(SCRIPT_URL) end)
    if not ok or type(src) ~= "string" or #src < 100 then
        log("reload fetch failed: " .. tostring(src):sub(1, 120))
        notify("Reload failed — keeping this version")
        return
    end
    -- 2) carry live settings into the next instance
    _G.SpudCarry = {
        crop       = CONFIG.crop,
        shopName   = CONFIG.shopName,
        moveMode   = Options.MoveMode,
        vflySpeed  = Options.VflySpeed,
        webhookUrl = Webhook.url,
        webhookOn  = Webhook.enabled,
    }
    -- 3) shut THIS instance down so no loop or GUI runs twice
    Farm.enabled = false
    Presets.stop()
    Webhook.enabled = false
    Options.NoClip = false
    Options.SpeedEnabled = false
    Options.InfiniteJump = false
    Options.AntiAFK = false
    Options.ClickTeleport = false
    Stealth.sessionLimitOn = false
    if Humanoid then
        try(function() Humanoid.WalkSpeed = 16 end)
        try(function() Humanoid.JumpPower = 50 end)
    end
    if hotGui then hotGui:Destroy() end
    if screen then screen:Destroy() end
    log("reloading latest version…")
    -- 4) run the fresh script (it notifies when loaded)
    local ok2, err2 = pcall(function()
        local chunk, lerr = loadstring(src)
        if not chunk then error(lerr or "loadstring failed") end
        chunk()
    end)
    if not ok2 then warn("[spud] reload error: " .. tostring(err2)) end
end, 24)

------------------------------------------------------------
-- MOBILE FIT — phones/tablets (and MuMu) report TouchEnabled. The UI is
-- designed at 540×400; on touch devices scale both windows to fit the
-- screen, center the main one, start the webhook window hidden (summon
-- it with the 📡 button) and re-fit on rotation/resize. Desktop untouched.
------------------------------------------------------------
if UserInputService.TouchEnabled then
    local mainScale = mk("UIScale", { Parent = main })
    local hookScale = mk("UIScale", { Parent = webhookWin })
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    webhookWin.AnchorPoint = Vector2.new(0.5, 0.5)
    local function mobileFit(recenter)
        if not screen.Parent or not main.Parent then return end  -- old instance after a Reload
        local cam = Workspace.CurrentCamera
        local vp = (cam and cam.ViewportSize.X > 0) and cam.ViewportSize or Vector2.new(1280, 720)
        local s  = math.clamp(math.min(vp.X * 0.97 / 540, vp.Y * 0.93 / 400), 0.5, 1.1)
        local s2 = math.clamp(math.min(vp.X * 0.97 / 310, vp.Y * 0.93 / 400), 0.5, 1.1)
        s2 = math.min(s2, s)   -- webhook never bigger than main; keeps stacking sane
        mainScale.Scale = s
        hookScale.Scale = s2
        if recenter then
            main.Position = UDim2.new(0.5, 0, 0.5, 0)
            if (540 * s + 310 * s2 + 28) <= vp.X then
                webhookWin.Position = UDim2.new(0.5, (540 * s) / 2 + (310 * s2) / 2 + 14, 0.5, 0)
            else
                webhookWin.Position = UDim2.new(0.5, 0, 0.5, (400 * s) / 2 + (400 * s2) / 2 + 10)
            end
        end
    end
    mobileFit(true)
    webhookWin.Visible = false
    local cam = Workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() mobileFit(true) end)
    end
    task.delay(2, function() mobileFit(true) end)  -- settle once loading finishes
end

selectTab("Farm")

------------------------------------------------------------
-- WINDOW DRAG / MINIMIZE / CLOSE / KEYBIND
------------------------------------------------------------
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local minimized = false
local fullSize = main.Size
minimizeBtn.Activated:Connect(function()
    minimized = not minimized
    TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
        Size = minimized and UDim2.new(0, 540, 0, 40) or fullSize
    }):Play()
    minimizeBtn.Text = minimized and "+" or "–"
end)

closeBtn.Activated:Connect(function()
    setAllVisible(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if screen and screen.Parent and hotGui and hotGui.Parent then
            toggleAll()
        end
    end
end)

-- Clean up when unloaded
screen.Destroying:Connect(function()
    Farm.enabled = false
    Presets.stop()
    Options.NoClip = false
    if Humanoid then
        Humanoid.WalkSpeed = 16
        Humanoid.JumpPower = 50
    end
end)

log("full script loaded (stealth ON) — RIGHT SHIFT for menu")
notify("SPUD FARM loaded! Stealth ON. RIGHT SHIFT for menu")
LastCoins = getCoins()
webhookSend("🟢 SPUD FARM loaded · stealth ON · movement " .. Options.MoveMode .. coinsNote())
