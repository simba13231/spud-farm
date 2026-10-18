--------------------------------------------------------------------
-- SpudCapture — RESPAWN REMOTE ARGS (§29, standalone)
--
-- WHY: the menu flow (open manager -> card -> Spawn) takes ~8-10 s of
-- mouse work. The game must be firing a REMOTE to do the respawn
-- (dump §28 found FNCRespawnEquipment / FNCForceRespawnEquipment).
-- If we know that remote's EXACT arguments, the farming script can
-- fire it directly — no menu, no clicks, instant.
--
-- USER APPROVED THIS PATH: "hook + capture args first".
-- The dump's §27/§28 namecall hooks (hookmetamethod + summarize) are
-- PROVEN in Delta — this reuses that exact pattern, standalone.
--
-- RUN: paste + execute this, THEN do your video's 3 clicks ONCE by
-- hand:  (1) open the Equipment Manager  (2) click the ZM80 card
-- (3) click Spawn.  Every equipment-ish remote call prints to the
-- EXECUTOR CONSOLE as [SPAWNWATCH …] lines. Paste those back.
-- This changes NO game state by itself — it only watches.
-- It CHAINS over any earlier dump hook (each hook calls the
-- previous one), so running it after the dump is fine too.
--------------------------------------------------------------------

local function summarize(prefix, ...)
    local parts = {}
    for i, v in ipairs({...}) do
        local t = typeof(v)
        local s
        if t == "table" then
            local n = 0
            for _ in pairs(v) do n += 1 end
            s = "table{" .. n .. "}: "
            local shown = 0
            for k, val in pairs(v) do
                shown += 1
                if shown > 8 then s = s .. "…"; break end
                s = s .. tostring(k) .. "=" .. tostring(val) .. " "
            end
        elseif t == "string" then
            s = string.format("string(%d) %q", #v, string.sub(v, 1, 200))
        elseif t == "Instance" then
            s = "Instance " .. v:GetFullName()
        else
            s = t .. "=" .. tostring(v)
        end
        parts[#parts + 1] = "[" .. i .. "] " .. s
    end
    warn(prefix .. " " .. table.concat(parts, "  "))
end

-- remotes the menu flow plausibly calls by NAME (respawn / spawn /
-- store / select / equipment / garage / manager / hitch), plus any
-- call whose STRING args mention a known model (catches an oddly
-- named remote carrying "ZM80" or its card id text)
local KEYS = { "respawn", "spawn", "store", "equip", "garage",
    "manager", "select", "hitch" }
local MODELS = { "ZM80", "KADL", "KQF3000", "SRC6", "R150", "S4204", "Trailer" }

local function interesting(nm, ...)
    local nml = nm:lower()
    for _, k in ipairs(KEYS) do
        if nml:find(k, 1, true) then return true end
    end
    for _, a in ipairs({...}) do
        if type(a) == "string" then
            for _, m in ipairs(MODELS) do
                if a:find(m, 1, true) then return true end
            end
        end
    end
    return false
end

local ok, err = pcall(function()
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local nm, meth = tostring(self.Name), getnamecallmethod()
        if (meth == "FireServer" or meth == "InvokeServer")
            and interesting(nm, ...) then
            pcall(summarize, "[SPAWNWATCH " .. meth .. " " .. nm .. "]", ...)
        end
        return old(self, ...)
    end))
end)

print("══════ SPAWN ARGS CAPTURE (§29) ══════")
if ok then
    print("✔ capture ON — now do the 3 clicks by hand, ONCE:")
    print("   1) open the Equipment Manager")
    print("   2) click the ZM80 card")
    print("   3) click Spawn")
    print("then paste every [SPAWNWATCH …] line from the executor console.")
    print("(the farming loop should be OFF while capturing)")
else
    print("✘ hook FAILED: " .. tostring(err))
end
print("══════════════════════════════════════")
