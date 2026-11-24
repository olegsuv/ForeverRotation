local ADDON, ns = ...

ns.DEFAULTS = {
    labels = true,     -- damage-per-second numbers on action buttons
    glow = true,       -- highlight the suggested spell on your bars
    icon = true,       -- separate "next spell" square
    iconMode = "center", -- "center" = between player and target frames, "free" = drag it
    iconScale = 1,
    locked = true,
    potions = true,
    potionMana = 15,   -- suggest a mana potion below this % mana (in combat)
    potionHealth = 30, -- suggest a healing potion below this % health (in combat)
    zone = false,      -- range zone (melee / dead zone / shoot / too far) under the square (not for pure melee)
    zonePlate = true,  -- the same zone as an icon next to the target's nameplate (not for pure melee)
    moveArrow = true,  -- big arrow on the square instead of the spell: step back / step closer
    selfHeal = 35,     -- healers / hybrids: suggest a self-heal below this % health
    trace = true,      -- keep a short log of rotation decisions in SavedVariables (debug)
    aggroLog = true,   -- log at what distance / level mobs aggro on you (data for an aggro indicator)
    brag = true,       -- party chat line when you top the damage in a dungeon (once per run, after a boss)
}

local GetTime, pcall, ipairs, pairs, type = GetTime, pcall, ipairs, pairs, type

---------------------------------------------------------------------------
-- Secret-value helpers (the Forever client hides some values in combat)
---------------------------------------------------------------------------
local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end
ns.isSecret = isSecret

function ns.safe(f, ...)
    if not f then return nil end
    local ok, a, b, c, d, e, g, h, i, j = pcall(f, ...)
    if ok then return a, b, c, d, e, g, h, i, j end
end

-- true / false / nil (unknown or hidden)
function ns.flag(v)
    if v == nil or isSecret(v) then return nil end
    if type(v) == "number" then return v ~= 0 end -- old-style 1/0 answers (0 is truthy in Lua)
    return v and true or false
end

function ns.num(v)
    if type(v) ~= "number" or isSecret(v) then return nil end
    return v
end

function ns.Print(msg)
    print("|cff66ccffForever Rotation|r: " .. tostring(msg))
end

function ns.Percent(unit, powerType)
    local cur, max
    if powerType then
        cur, max = ns.safe(UnitPower, unit, powerType), ns.safe(UnitPowerMax, unit, powerType)
    else
        cur, max = ns.safe(UnitHealth, unit), ns.safe(UnitHealthMax, unit)
    end
    cur, max = ns.num(cur), ns.num(max)
    if not cur or not max or max == 0 then return nil end
    return cur / max * 100
end

---------------------------------------------------------------------------
-- Spellbook: highest known rank by name
---------------------------------------------------------------------------
ns.known = {} -- [name] = highest spellID in the spellbook

function ns.ScanSpellbook()
    wipe(ns.known)
    if not (C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo) then return end
    local line = 1
    while true do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not info then break end
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if item and item.spellID and not item.isPassive then
                local name = C_Spell.GetSpellName(item.spellID)
                if name then ns.known[name] = item.spellID end -- later entries are higher ranks
            end
        end
        line = line + 1
    end
end

-- base spellID -> { name, id } of the rank you actually have (nil if unknown)
function ns.Spell(baseID)
    local name = C_Spell.GetSpellName(baseID)
    if not name then return nil end
    local id = ns.known[name]
    if not id then return nil end
    return name, id
end

---------------------------------------------------------------------------
-- Cooldowns / usability
---------------------------------------------------------------------------
local GCD = 1.5
ns.GCD = GCD

local scratch
local function durationShown(durObj)
    if not durObj then return false end
    if not scratch then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        scratch = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    end
    if not scratch.SetCooldownFromDurationObject then return false end
    scratch:SetCooldownFromDurationObject(durObj)
    local shown = scratch:IsShown()
    scratch:SetCooldown(0, 0)
    return shown and true or false
end

-- on a real cooldown (the global cooldown does not count)
function ns.OnCooldown(id)
    local info = ns.safe(C_Spell.GetSpellCooldown, id)
    if type(info) == "table" and ns.num(info.startTime) and ns.num(info.duration) then
        if info.duration <= GCD + 0.01 then return false end
        return info.startTime + info.duration - GetTime() > 0.1
    end
    if C_Spell.GetSpellCooldownDuration then
        return durationShown(ns.safe(C_Spell.GetSpellCooldownDuration, id, true))
    end
    return false
end

function ns.Usable(id)
    local usable, noMana = ns.safe(C_Spell.IsSpellUsable, id)
    if ns.flag(usable) == false then return false, ns.flag(noMana) end
    return true
end

-- the spell as you know it (highest rank), by base id or by name; nil when not known
function ns.ID(spell)
    local n = type(spell) == "string" and spell or C_Spell.GetSpellName(spell)
    return n and ns.known[n] or nil
end

-- known + usable + off cooldown (+ target not out of range when checkRange)
function ns.Ready(spell, checkRange)
    local id = ns.ID(spell)
    if not id then return false end
    if not ns.Usable(id) then return false end
    if ns.OnCooldown(id) then return false end
    if ns.Immune(id) then return false end
    if checkRange and ns.InRange(id) == false then return false end
    return true, id
end
ns.ReadyName = ns.Ready
ns.R = ns.Ready

-- Trace: why the rotation picked what it picked (saved, for remote debugging)
function ns.Trace(line)
    if not ns.db or not ns.db.trace then return end
    local t = ns.db.traceLog or {}
    ns.db.traceLog = t
    t[#t + 1] = ("%.1f %s"):format(GetTime(), line)
    while #t > 300 do table.remove(t, 1) end
end

function ns.InRange(id, unit)
    return ns.flag(ns.safe(C_Spell.IsSpellInRange, id, unit or "target"))
end

---------------------------------------------------------------------------
-- Own debuffs on the target: read them if the game allows, otherwise remember
-- when we cast them.
---------------------------------------------------------------------------
ns.durations = {} -- [spell name] = seconds (filled by Damage.lua / modules)
local applied = {} -- [targetKey][name] = expire time

local function targetKey()
    local guid = ns.safe(UnitGUID, "target")
    if guid and not isSecret(guid) then return guid end
    return "target"
end

function ns.DebuffUp(name)
    if not name then return false end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local aura = ns.safe(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL|PLAYER")
        if aura ~= nil and not isSecret(aura) then return true end
    end
    local t = applied[targetKey()]
    return t and t[name] and t[name] > GetTime() or false
end

-- Exclusive self-buffs (hunter aspects): remember the last one cast as a fallback
-- when the game hides the player's auras.
ns.exclusiveBuffs = {} -- [name] = true
local lastExclusive

-- Is this self-buff on? The game hides player auras from addons in combat, so we
-- remember the last readable answer for exclusive buffs (aspects) and update it
-- when you cast one. The memory survives /reload.
function ns.PlayerBuff(name)
    if not name then return false end
    local exclusive = ns.exclusiveBuffs[name]
    local id = ns.known[name]
    if id and C_Spell.IsCurrentSpell and ns.flag(ns.safe(C_Spell.IsCurrentSpell, id)) then return true end
    if ns.ButtonActive and ns.ButtonActive(name) then return true end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and not isSecret(aura) then
            if exclusive then
                if aura ~= nil then
                    lastExclusive = name
                    if ns.cdb then ns.cdb.lastAspect = name end
                end
            end
            if aura ~= nil then return true end
            if not exclusive then return false end
        end
    end
    if exclusive then return lastExclusive == name end
    return false
end

---------------------------------------------------------------------------
-- Shared helpers for the class modules
---------------------------------------------------------------------------

-- first function that answers ok, id wins
-- base cooldown in seconds (0 when none / unknown), cached
local baseCD = {}
function ns.BaseCooldown(id)
    local v = baseCD[id]
    if v == nil then
        local ms = GetSpellBaseCooldown and ns.num(ns.safe(GetSpellBaseCooldown, id))
        v = ms and ms / 1000 or 0
        baseCD[id] = v
    end
    return v
end

ns.LONG_CD = 90 -- seconds: from here on a spell goes to the second square, not the first

-- first entry that says yes. A spell with a long cooldown (Rapid Fire, Bestial Wrath, Death
-- Wish...) is held for the second square and the walk goes on: the next spell is still due.
function ns.first(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        local ok, id = f()
        if ok then
            if id and ns.BaseCooldown(id) >= ns.LONG_CD then
                if not ns.cdPick then ns.cdPick = id end
            else
                return id
            end
        end
    end
end


-- name of a base spell id (Forever renames some: Curse of Agony -> Bane of Agony)
function ns.N(spell)
    if type(spell) == "string" then return spell end
    return ns.safe(C_Spell.GetSpellName, spell)
end

-- do we know this spell (id or name)?
function ns.Known(spell)
    return ns.ID(spell) ~= nil
end

-- raw power value, nil when hidden
function ns.Power(powerType)
    local v = ns.num(ns.safe(UnitPower, "player", powerType))
    return v
end

-- the spell's own resource is short (rage, energy, mana): true / false
function ns.NoResource(spell)
    local id = ns.ID(spell)
    if not id then return false end
    local _, noMana = ns.Usable(id)
    return noMana == true
end

-- known and off cooldown, only short of its resource: the spell to wait for (rage, energy)
function ns.Pool(spell, checkRange)
    local id = ns.ID(spell)
    if not id or ns.OnCooldown(id) then return false end
    if checkRange and ns.InRange(id) == false then return false end
    local usable, noMana = ns.Usable(id)
    if not usable and noMana == true then return true, id end
    return false
end

-- the spell glows on your bars (procs: Overpower, Hot Streak, Shadow Trance, Maelstrom...)
function ns.Proc(spell)
    local n = ns.N(spell)
    local id = n and ns.known[n]
    if not id then return false end
    local api = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
    if api and ns.flag(ns.safe(api, id)) then return true end
    return ns.ButtonGlow and ns.ButtonGlow(n) or false
end

-- target is casting something we can interrupt: true / false / nil (hidden)
function ns.TargetCasting()
    if not UnitCastingInfo then return nil end
    local spell, _, _, _, _, _, _, notInterruptible = ns.safe(UnitCastingInfo, "target")
    if spell == nil and UnitChannelInfo then
        local s2, _, _, _, _, _, ni2 = ns.safe(UnitChannelInfo, "target")
        spell, notInterruptible = s2, ni2
    end
    if spell == nil then return false end
    if isSecret(spell) then return nil end
    if notInterruptible ~= nil and not isSecret(notInterruptible) and notInterruptible then return false end
    return true
end

-- a shield in the off hand
function ns.ShieldOn()
    local id = GetInventoryItemID and ns.safe(GetInventoryItemID, "player", 17)
    if not id then return false end
    local _, _, _, loc = ns.safe(C_Item.GetItemInfoInstant, id)
    return loc == "INVTYPE_SHIELD"
end

-- the target is hitting you: true / false / nil (hidden)
function ns.TargetOnMe()
    local onMe = ns.flag(ns.safe(UnitIsUnit, "targettarget", "player"))
    if onMe ~= nil then return onMe end
    local threat = ns.num(ns.safe(UnitThreatSituation, "player", "target"))
    if threat then return threat >= 2 end
    return nil
end

-- npc id out of a creature guid, nil for players and pets
function ns.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- creature type of the target. The game hides it in combat, so it is remembered per npc
-- kind (target, mouseover, nameplate, and what the aggro log saw), for the whole account.
function ns.NoteCreatureType(unit)
    local t = ns.safe(UnitCreatureType, unit)
    if not t or isSecret(t) then return end
    local npc = ns.NpcID(UnitGUID(unit))
    if npc and ns.db then
        ns.db.ctype = ns.db.ctype or {}
        ns.db.ctype[npc] = t
    end
end

-- what the aggro log already knows (it has seen hundreds of mobs with their type)
local function seedCreatureTypes()
    local log = ns.db.aggroData
    if type(log) ~= "table" then return end
    ns.db.ctype = ns.db.ctype or {}
    for _, m in ipairs(log) do
        if type(m) == "table" and m.npc and type(m.type) == "string" and not ns.db.ctype[m.npc] then
            ns.db.ctype[m.npc] = m.type
        end
    end
end

function ns.TargetType()
    local t = ns.safe(UnitCreatureType, "target")
    if t and not isSecret(t) then return t end
    local npc = ns.NpcID(UnitGUID("target"))
    return npc and ns.db and ns.db.ctype and ns.db.ctype[npc] or nil
end

-- Immunities learned from the combat log: a spell of yours that an npc shrugged off
-- ("immune") is not suggested on that npc kind again. /frot immune lists and clears them.
function ns.Immune(id)
    local list = ns.cdb and ns.cdb.immune
    if not list then return false end
    local npc = ns.NpcID(UnitGUID("target"))
    if not npc then return false end
    local n = C_Spell.GetSpellName(id)
    return n ~= nil and list[npc .. ":" .. n] == true
end

local function onCombatLog()
    local ok, _, sub, _, srcGUID, _, _, _, dstGUID, dstName, _, _, _, spellName, _, missType = pcall(CombatLogGetCurrentEventInfo)
    if not ok or sub ~= "SPELL_MISSED" or missType ~= "IMMUNE" then return end
    if not ns.cdb or srcGUID ~= UnitGUID("player") then return end
    local npc = ns.NpcID(dstGUID)
    if not npc or type(spellName) ~= "string" then return end
    ns.cdb.immune = ns.cdb.immune or {}
    local key = npc .. ":" .. spellName
    if not ns.cdb.immune[key] then
        ns.cdb.immune[key] = true
        ns.cdb.immuneNames = ns.cdb.immuneNames or {}
        ns.cdb.immuneNames[key] = tostring(dstName)
    end
end

local BLEED_IMMUNE = { Mechanical = true, Elemental = true, ["Механизм"] = true, ["Элементаль"] = true }
function ns.CanBleed()
    local t = ns.TargetType()
    return not (t and BLEED_IMMUNE[t])
end

---------------------------------------------------------------------------
-- Time to die. The game hides the target's health from addons in combat, so two sources:
-- the health trend while it can be read, else how long your recent kills of this kind took
-- (normal / elite, solo / group, scaled by the level gap) minus how long this fight has run.
-- Kill times are learned as you play and kept in SavedVariables.
---------------------------------------------------------------------------
-- kinds: normal / elite x solo / group / dungeon, and bosses
local KILL_PRIOR = { ns = 15, ng = 9, es = 45, eg = 25, nd = 8, ed = 20, b = 90 } -- seconds, before anything is learned
local fights = {} -- [guid] = { start, samples = { {t, hp} }, seen, done }

local function targetGuid()
    local g = ns.safe(UnitGUID, "target")
    if g and not isSecret(g) then return g end
end

local function isPlayerTarget()
    return ns.flag(ns.safe(UnitIsPlayer, "target")) == true
end

local function killKind()
    local cls = ns.safe(UnitClassification, "target")
    if isSecret(cls) then cls = nil end
    local lvl = ns.num(ns.safe(UnitLevel, "target"))
    local boss = cls == "worldboss" or ns.flag(ns.safe(UnitIsBossMob, "target")) == true
    local _, instance = IsInInstance()
    local dungeon = instance == "party" or instance == "raid"
    if boss or (dungeon and lvl == -1) then return "b" end
    local elite = cls == "elite" or cls == "rareelite"
    local where = dungeon and "d" or ((IsInGroup and IsInGroup()) and "g" or "s")
    return (elite and "e" or "n") .. where
end

-- mobs above you take longer, below you go faster (?? skulls: much longer)
local function levelScale()
    local me = UnitLevel("player") or 1
    local it = ns.num(ns.safe(UnitLevel, "target"))
    if not it or it <= 0 then return 1.6 end
    return math.max(0.5, math.min(1.6, 1 + (it - me) * 0.1))
end

local function learnedKill()
    local kind = killKind()
    local k = ns.cdb and ns.cdb.killTimes and ns.cdb.killTimes[kind]
    return (k and k.avg or KILL_PRIOR[kind]) * levelScale()
end

local function recordKill(f, now)
    local secs = now - f.start
    if secs < 2 or secs > 400 then return end
    local kind = killKind()
    ns.cdb.killTimes = ns.cdb.killTimes or {}
    local k = ns.cdb.killTimes[kind] or { avg = KILL_PRIOR[kind], n = 0 }
    local norm = secs / levelScale()
    k.avg = k.n == 0 and (k.avg + norm) / 2 or k.avg * 0.8 + norm * 0.2
    k.n = k.n + 1
    ns.cdb.killTimes[kind] = k
end

-- every 0.25 s: start the fight clock, sample readable health, learn from the kill
local function sampleTarget()
    local now = GetTime()
    for guid, f in pairs(fights) do
        if now - f.seen > 60 then fights[guid] = nil end
    end
    local guid = targetGuid()
    if not guid or isPlayerTarget() then return end
    if ns.flag(ns.safe(UnitCanAttack, "player", "target")) == false then return end
    local f = fights[guid]
    if ns.flag(ns.safe(UnitIsDead, "target")) == true then
        if f and not f.done then
            f.done = true
            local ours = ns.flag(ns.safe(UnitIsTapDenied, "target")) ~= true
            if ours and ns.cdb then recordKill(f, now) end
        end
        return
    end
    if not f then
        if ns.flag(ns.safe(UnitAffectingCombat, "target")) ~= true then return end
        f = { start = now, samples = {} }
        fights[guid] = f
    end
    f.seen = now
    local hp = ns.Percent("target")
    if hp then
        local s = f.samples
        s[#s + 1] = { now, hp }
        while #s > 0 and now - s[1][1] > 10 do table.remove(s, 1) end
    end
end

-- seconds the target has left (nil for players: they heal, run and trinket)
function ns.TimeToDie()
    if not UnitExists("target") or isPlayerTarget() then return nil end
    local guid = targetGuid()
    local f = guid and fights[guid]
    local now = GetTime()
    local hp = ns.Percent("target")
    if hp then
        local s = f and f.samples
        if s and #s >= 3 and s[#s][1] - s[1][1] >= 2 then
            -- least squares slope of health over the last few seconds
            local n, st, sh, stt, sth = #s, 0, 0, 0, 0
            for _, p in ipairs(s) do
                local t = p[1] - s[1][1]
                st, sh, stt, sth = st + t, sh + p[2], stt + t * t, sth + t * p[2]
            end
            local den = n * stt - st * st
            if den > 0 then
                local slope = (n * sth - st * sh) / den
                if slope >= -0.05 then return 600 end -- not going down
                return hp / -slope
            end
        end
        return learnedKill() * hp / 100
    end
    local elapsed = f and (now - f.start) or 0
    return math.max(0, learnedKill() - elapsed)
end

-- the mob lives long enough for a DoT / buildup: `need` seconds left (default 8). Players
-- always count; without a time estimate it falls back to the health threshold.
function ns.Lives(threshold, need)
    if isPlayerTarget() then return true end
    local ttd = ns.TimeToDie()
    if ttd then return ttd >= (need or 8) end
    local hp = ns.Percent("target")
    return not hp or hp >= (threshold or 40) or ns.TargetIsTough()
end

-- the mob is about to die: under `pct` health when that can be read (not elites), or under
-- `secs` seconds left by the time estimate
function ns.Dying(pct, secs)
    local hp = ns.Percent("target")
    if isPlayerTarget() then return hp ~= nil and hp < (pct or 20) end
    if hp and hp < (pct or 20) and not ns.TargetIsTough() then return true end
    local ttd = ns.TimeToDie()
    return ttd ~= nil and ttd < (secs or 4)
end

local ttdTicker = CreateFrame("Frame")
local ttdElapsed = 0
ttdTicker:SetScript("OnUpdate", function(_, e)
    ttdElapsed = ttdElapsed + e
    if ttdElapsed < 0.25 then return end
    ttdElapsed = 0
    sampleTarget()
end)

-- in melee: first probe spell that answers, else interact distance (~10 yd)
function ns.InMelee(probes)
    for _, p in ipairs(probes or {}) do
        local n = ns.N(p)
        local id = n and ns.known[n]
        if id then
            local r = ns.InRange(id)
            if r ~= nil then return r end
        end
    end
    return ns.flag(ns.safe(CheckInteractDistance, "target", 3))
end

-- current shapeshift / stance / paladin aura: its spell name, "" = none, nil = hidden
function ns.Form()
    local idx = ns.num(ns.safe(GetShapeshiftForm))
    if idx == nil then return nil end
    if idx == 0 then return "" end
    local _, active, _, spellID = ns.safe(GetShapeshiftFormInfo, idx)
    if spellID and not isSecret(spellID) then return ns.safe(C_Spell.GetSpellName, spellID) or "" end
    return nil
end

-- main hand imbue (shaman weapons, rogue poisons): true / false / nil
function ns.WeaponEnchanted()
    if not GetWeaponEnchantInfo then return nil end
    local has = ns.safe(GetWeaponEnchantInfo)
    if has == nil or isSecret(has) then return nil end
    return has and true or false
end

---------------------------------------------------------------------------
-- Timed self-buffs (Battle Shout, Slice and Dice, seals, shields, armors).
-- The game hides player auras in combat: remember what we last read and when
-- we cast them. Answer true / false / nil (we really don't know).
---------------------------------------------------------------------------
ns.selfBuffs = {} -- [name] = duration in seconds
ns.buffGroups = {} -- [name] = group (casting one drops the others: seals, armors)
local buffExp -- [name] = expire time (GetTime based), saved in db
local castExp = {} -- [name] = expire time counted from your own cast

-- the aura by name, else by the spell id (on Forever the aura name can differ from the spell's)
local function playerAura(name, id)
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if not ok or isSecret(aura) then return false, nil end
    if aura == nil and id and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok2, a2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok2 and not isSecret(a2) then aura = a2 end
    end
    return true, aura
end

function ns.SelfBuff(spell)
    local name = ns.N(spell)
    if not name then return nil end
    buffExp = buffExp or (ns.cdb and ns.cdb.buffExp) or {}
    local id = ns.known[name]
    if id and C_Spell.IsCurrentSpell and ns.flag(ns.safe(C_Spell.IsCurrentSpell, id)) then return true end
    if ns.ButtonActive and ns.ButtonActive(name) then return true end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = playerAura(name, id)
        if ok then
            if aura == nil then
                -- you cast it a moment ago and the game finds no such aura: believe the cast
                if (castExp[name] or 0) > GetTime() then return true end
                buffExp[name] = 0
                return false
            end
            local exp = aura.expirationTime
            if exp ~= nil and not isSecret(exp) and exp > 0 then buffExp[name] = exp
            else buffExp[name] = GetTime() + 3600 end
            return true
        end
    end
    local e = buffExp[name]
    if e == nil then return nil end
    return e > GetTime()
end

-- missing for sure (or never seen while it's a buff you keep up)
function ns.BuffMissing(spell)
    if not ns.Known(spell) then return false end
    return ns.SelfBuff(spell) == false
end

---------------------------------------------------------------------------
-- Combo points: the real number when readable, else counted from your casts
---------------------------------------------------------------------------
ns.cpBuilders = {} -- [name] = points it gives
ns.cpFinishers = {} -- [name] = true
local cpEst = 0

function ns.ComboPoints()
    local v = ns.num(ns.safe(UnitPower, "player", (Enum.PowerType and Enum.PowerType.ComboPoints) or 4))
    if v == nil and GetComboPoints then v = ns.num(ns.safe(GetComboPoints, "player", "target")) end
    if v ~= nil then cpEst = v; return v end
    return cpEst
end

local function trackCast(name)
    local now = GetTime()
    buffExp = buffExp or (ns.cdb and ns.cdb.buffExp) or {}
    local dur = ns.selfBuffs[name]
    if dur then
        local g = ns.buffGroups[name]
        if g then
            for other, og in pairs(ns.buffGroups) do
                if og == g and other ~= name then buffExp[other] = 0; castExp[other] = nil end
            end
        end
        if type(dur) == "function" then dur = dur() end
        buffExp[name] = now + dur
        castExp[name] = now + dur
    end
    if ns.cpFinishers[name] then cpEst = 0
    elseif ns.cpBuilders[name] then cpEst = math.min(5, cpEst + ns.cpBuilders[name]) end
end
ns.ResetComboEstimate = function() cpEst = 0 end

---------------------------------------------------------------------------
-- Potions and self-heals shared by the class modules
---------------------------------------------------------------------------
ns.MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }
ns.HEAL_POTIONS = { 13446, 3928, 1710, 929, 858, 118 }

-- usesMana: the class runs on mana
-- usesMana: the class drinks mana potions; probes: basic spells whose "no mana" answer stands
-- in for the mana number when the game hides it
-- healing potion when low: before anything else. The mana potion waits until the rotation
-- has nothing left to cast (ns.ManaPotion, called from the update loop).
function ns.PotionCheck(usesMana, probes)
    ns.usesMana, ns.manaProbes = usesMana, probes
    if not ns.db.potions then return nil end
    if not ns.flag(UnitAffectingCombat("player")) then return nil end
    local hp = ns.Percent("player")
    if hp and hp < ns.db.potionHealth then
        local s = ns.ReadyItem(ns.HEAL_POTIONS); if s then return s end
    end
end

-- mana potion: mana under the threshold (or the probe spells say "no mana" when it is
-- hidden), on a mob that will live, in combat
function ns.ManaPotion()
    if not ns.usesMana or not ns.db.potions then return nil end
    if not ns.flag(UnitAffectingCombat("player")) then return nil end
    local mana = ns.Percent("player", Enum.PowerType.Mana)
    local short = mana and mana < ns.db.potionMana
    if mana == nil and ns.manaProbes then
        for _, p in ipairs(ns.manaProbes) do
            if ns.NoResource(p) then short = true; break end
        end
    end
    if short and ns.Lives(30, 10) then -- not for a mob about to die
        local s = ns.ReadyItem(ns.MANA_POTIONS); if s then return s end
    end
end

-- you are low: true when health readable and under the heal threshold
function ns.LowHealth(pct)
    local hp = ns.Percent("player")
    return hp ~= nil and hp < (pct or ns.db.selfHeal or 40)
end

-- mana (percent) or nil; manaShort: below pct, or the main spell says "no mana"
function ns.ManaShort(pct, mainSpell)
    local mana = ns.Percent("player", Enum.PowerType.Mana)
    if mana then return mana < pct end
    return mainSpell and ns.NoResource(mainSpell) or false
end

-- a hits harder per second than b (instants counted as a global cooldown)
function ns.Better(a, b, targets)
    local na, nb = ns.N(a), ns.N(b)
    local ia, ib = na and ns.known[na], nb and ns.known[nb]
    if not ia then return false end
    if not ib then return true end
    return (ns.DPS(ia, targets) or 0) >= (ns.DPS(ib, targets) or 0)
end

-- wand: Shoot when a wand is equipped
function ns.Wand()
    if HasWandEquipped and not ns.flag(ns.safe(HasWandEquipped)) then return false end
    return ns.R(5019, true)
end

---------------------------------------------------------------------------
-- Defaults that class modules can replace
---------------------------------------------------------------------------
ns.meleeProbes = nil -- spells to test melee range with
ns.rangeProbes = nil -- spells to test casting range with
ns.traceSpells = {}  -- spells to show in the trace log

function ns.RangeZone()
    if not ns.HostileTarget() then return nil end
    if ns.meleeProbes then
        if ns.InMelee(ns.meleeProbes) == true then return "melee" end
    end
    if ns.rangeProbes then
        for _, p in ipairs(ns.rangeProbes) do
            local n = ns.N(p)
            local id = n and ns.known[n]
            if id then
                local r = ns.InRange(id)
                if r == true then return "shoot" end
                if r == false then return "far" end
            end
        end
    end
    if ns.meleeProbes and ns.InMelee(ns.meleeProbes) == false then return "far" end
    return nil
end

-- the range zone once per frame (five readers), and an error in a class override can't
-- spam from an OnUpdate
local zoneAt, zoneVal
function ns.Zone()
    local now = GetTime()
    if zoneAt ~= now then
        zoneAt = now
        local ok, z = pcall(ns.RangeZone)
        zoneVal = ok and z or nil
        if not ok and ns.db and ns.db.debug then ns.Print("zone error: " .. tostring(z)) end
    end
    return zoneVal
end

-- which way to step: "back" (too close to shoot), "closer" (out of reach) or nil
function ns.MoveHint()
    local z = ns.Zone()
    if z == "dead" then return "back" end
    if z == "far" then return "closer" end
    return nil
end

function ns.TraceState()
    local out = {}
    local pt = UnitPowerType and ns.num(ns.safe(UnitPowerType, "player"))
    local p = pt and ns.Percent("player", pt)
    out[#out + 1] = ("pow=%s"):format(p and ("%d"):format(p) or "?")
    if next(ns.cpBuilders) then out[#out + 1] = "cp=" .. tostring(ns.ComboPoints()) end
    out[#out + 1] = "form=" .. tostring(ns.Form())
    out[#out + 1] = ("en=%d"):format(ns.EnemyCount(ns.aoeRange))
    local ttd, thp = ns.TimeToDie(), ns.Percent("target")
    out[#out + 1] = ("ttd=%s hp=%s"):format(ttd and ("%d"):format(ttd) or "?", thp and ("%d"):format(thp) or "?")
    for _, s in ipairs(ns.traceSpells) do
        local n = ns.N(s)
        local id = n and ns.known[n]
        if id then
            local u = ns.Usable(id)
            local r = ns.InRange(id)
            local info = ns.safe(C_Spell.GetSpellCooldown, id)
            local cdText = "?"
            if type(info) == "table" then
                if isSecret(info.duration) or isSecret(info.startTime) then cdText = "S"
                elseif ns.num(info.duration) then cdText = ("%.1f"):format(info.duration) end
            end
            out[#out + 1] = ("%s:u%s/cd%s(%s)/r%s"):format(n:sub(1, 6), u and 1 or 0, ns.OnCooldown(id) and 1 or 0,
                cdText, r == nil and "?" or (r and 1 or 0))
        end
    end
    out[#out + 1] = "zone=" .. tostring(ns.Zone())
    if ns.TraceExtra then out[#out + 1] = ns.TraceExtra() end
    return table.concat(out, " ")
end

-- recent casts by name (to count summons such as Summon Hawk)
local castLog = {}
function ns.RecentCasts(name, window)
    local list = castLog[name]
    if not list then return 0 end
    local now, n = GetTime(), 0
    for i = #list, 1, -1 do
        if now - list[i] <= window then n = n + 1 else break end
    end
    return n
end

local function onCast(spellID)
    local name = ns.safe(C_Spell.GetSpellName, spellID)
    if not name or isSecret(name) then return end
    local list = castLog[name] or {}
    castLog[name] = list
    list[#list + 1] = GetTime()
    if #list > 10 then table.remove(list, 1) end
    trackCast(name)
    if ns.exclusiveBuffs[name] then
        lastExclusive = name
        if ns.cdb then ns.cdb.lastAspect = name end
    end
    local dur = ns.durations[name]
    if not dur then return end
    local key = targetKey()
    applied[key] = applied[key] or {}
    applied[key][name] = GetTime() + dur
    -- drop stale targets
    local now = GetTime()
    for k, spells in pairs(applied) do
        local any = false
        for n, exp in pairs(spells) do
            if exp < now then spells[n] = nil else any = true end
        end
        if not any then applied[k] = nil end
    end
end

---------------------------------------------------------------------------
-- Enemies around: hostile, alive, in-combat nameplates (hidden values count)
---------------------------------------------------------------------------
local plates = {}

-- is this mob in our fight? false when another group tagged it, or it fights someone outside
-- your group while you're not on its threat list (the next party's pull); nil = can't tell
local function ourFight(unit)
    if ns.flag(ns.safe(UnitIsTapDenied, unit)) == true then return false end
    local threat = ns.safe(UnitThreatSituation, "player", unit)
    if isSecret(threat) then threat = "?" end
    if threat ~= nil and threat ~= "?" then return true end
    local tgt = unit .. "target"
    if ns.flag(ns.safe(UnitExists, tgt)) == true then
        if ns.flag(ns.safe(UnitIsUnit, tgt, "player")) or ns.flag(ns.safe(UnitIsUnit, tgt, "pet")) then return true end
        if ns.flag(ns.safe(UnitInParty, tgt)) or ns.flag(ns.safe(UnitInRaid, tgt)) then return true end
        local member = ns.flag(ns.safe(UnitPlayerOrPetInParty, tgt)) or ns.flag(ns.safe(UnitPlayerOrPetInRaid, tgt))
        if member then return true end
        if threat == nil then return false end -- someone else's fight, and the threat list says not ours
    end
    if threat == nil and ns.flag(ns.safe(UnitAffectingCombat, "player")) == true then return false end
    return nil
end
-- cached for a tick: the rotation, the square, the labels and the tooltip all ask
local enemyCache = {} -- [rangeSpellID or 0] = { t, n }
function ns.EnemyCount(rangeSpellID)
    local key = rangeSpellID or 0
    local c = enemyCache[key]
    local now = GetTime()
    if c and now - c[1] < 0.15 then return c[2] end
    local n = 0
    for unit in pairs(plates) do
        local hostile = ns.flag(ns.safe(UnitCanAttack, "player", unit))
        local dead = ns.flag(ns.safe(UnitIsDead, unit))
        local fighting = ns.flag(ns.safe(UnitAffectingCombat, unit))
        local inRange = rangeSpellID and ns.InRange(rangeSpellID, unit)
        if hostile ~= false and dead ~= true and fighting ~= false and inRange ~= false and ourFight(unit) ~= false then
            n = n + 1
        end
    end
    enemyCache[key] = { now, n }
    return n
end

function ns.TargetIsTough()
    local cls = ns.safe(UnitClassification, "target")
    if cls and not isSecret(cls) and (cls == "elite" or cls == "rareelite" or cls == "worldboss") then
        return true
    end
    return ns.flag(ns.safe(UnitIsPlayer, "target")) == true
end

-- a boss: the classification says so, or a ?? mob inside an instance
function ns.TargetIsBoss()
    local cls = ns.safe(UnitClassification, "target")
    if cls == "worldboss" then return true end
    if ns.flag(ns.safe(UnitIsBossMob, "target")) == true then return true end
    local _, instance = IsInInstance()
    if instance == "party" or instance == "raid" then
        return ns.num(ns.safe(UnitLevel, "target")) == -1
    end
    return false
end

-- worth a long cooldown: a boss, or an elite / player that will take a while (dungeon trash is
-- elite too, so being elite alone is not enough)
function ns.BigFight(secs)
    if ns.TargetIsBoss() then return true end
    return ns.TargetIsTough() and ns.Lives(60, secs or 25)
end

function ns.HostileTarget()
    if not UnitExists("target") then return false end
    if ns.flag(ns.safe(UnitIsDead, "target")) == true then return false end
    return ns.flag(ns.safe(UnitCanAttack, "player", "target")) ~= false
end

---------------------------------------------------------------------------
-- Potions
---------------------------------------------------------------------------
local function itemReady(itemID)
    local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCD then return true end
    local start, duration = ns.safe(getCD, itemID)
    start, duration = ns.num(start), ns.num(duration)
    if not start or not duration then return false end
    return start == 0 or start + duration <= GetTime()
end

-- Is the auto-repeat spell (Auto Shot) running? The game reports it as "current" only part
-- of the time between two shots, so a sighting counts for one full shot after it; a new
-- target starts over.
local shotSeen, shotTarget = 0, nil
function ns.AutoShooting(id)
    local now = GetTime()
    local guid = UnitGUID("target")
    if guid ~= shotTarget then shotTarget, shotSeen = guid, 0 end
    local on = false
    if C_Spell.IsCurrentSpell and ns.flag(ns.safe(C_Spell.IsCurrentSpell, id)) then on = true end
    if not on and C_Spell.IsAutoRepeatSpell and ns.flag(ns.safe(C_Spell.IsAutoRepeatSpell, id)) then on = true end
    if not on and ns.ButtonActive and ns.ButtonActive(C_Spell.GetSpellName(id)) then on = true end
    if on then shotSeen = now; return true end
    local speed = ns.num(ns.safe(UnitRangedDamage, "player")) or 0
    return now - shotSeen < math.max(speed, 1) + 0.5
end

-- "blocked from an action only available to the Blizzard UI": what and from where. The
-- event and the popup both lead here; the stack at that moment names the caller.
function ns.NoteBlocked(how, a, b, c)
    local line = ("%s %s: %s %s %s"):format(date("%H:%M:%S"), tostring(how), tostring(a), tostring(b), tostring(c))
    local where = debugstack(3, 8, 0) or "?"
    if a == ADDON or b == ADDON then ns.Print(line) end
    if ns.cdb then
        ns.cdb.blocked = ns.cdb.blocked or {}
        local t = ns.cdb.blocked
        t[#t + 1] = line .. "
" .. where
        while #t > 20 do table.remove(t, 1) end
    end
end

if hooksecurefunc and StaticPopup_Show then
    hooksecurefunc("StaticPopup_Show", function(which, a, b)
        if which == "ADDON_ACTION_FORBIDDEN" or which == "ADDON_ACTION_BLOCKED" then ns.NoteBlocked("popup " .. which, a, b) end
    end)
end

ns.itemSpells = {} -- use-spellID -> itemID of the potions the rotation suggested

-- first item from the list you carry that is off cooldown -> its use-spellID, itemID
function ns.ReadyItem(list)
    for _, itemID in ipairs(list) do
        local count = ns.num(ns.safe(C_Item.GetItemCount, itemID))
        if count and count > 0 and itemReady(itemID) then
            local _, spellID = ns.safe(C_Item.GetItemSpell, itemID)
            if spellID then
                ns.itemSpells[spellID] = itemID -- the square says "Use" and shows the item's icon
                return spellID, itemID
            end
        end
    end
end

---------------------------------------------------------------------------
-- Rotation registry
---------------------------------------------------------------------------
ns.rotation = nil -- function() -> spellID or nil; set by a class module
ns.suggestion = nil
ns.cdSuggestion = nil -- long cooldown for the second square (ns.cdPick while the rotation runs)

---------------------------------------------------------------------------
-- Events / update loop
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame

local elapsedSuggest, elapsedLabels = 0, 0
ns.labelsDirty = true

local function update(_, elapsed)
    elapsedSuggest = elapsedSuggest + elapsed
    elapsedLabels = elapsedLabels + elapsed
    if elapsedSuggest >= 0.15 then
        elapsedSuggest = 0
        local s, cd
        if ns.rotation and ns.HostileTarget() then
            ns.cdPick = nil
            local ok, res = pcall(ns.rotation)
            if ok then s = res elseif ns.db.debug then ns.Print("rotation error: " .. tostring(res)) end
            cd = ns.cdPick
            if not s and ok then s = ns.ManaPotion() end -- nothing to cast: drink
        end
        if ns.db.trace and ns.TraceState and ns.HostileTarget() then
            local now = GetTime()
            local fighting = ns.flag(UnitAffectingCombat("player"))
            if s ~= ns.suggestion or cd ~= ns.cdSuggestion or (fighting and now - (ns.lastTrace or 0) > 1) then
                ns.lastTrace = now
                local ok, state = pcall(ns.TraceState)
                ns.Trace(("%s%s | %s"):format(s and C_Spell.GetSpellName(s) or "-",
                    cd and (" +" .. (C_Spell.GetSpellName(cd) or cd)) or "", ok and state or ("err " .. tostring(state))))
            end
        end
        if s ~= ns.suggestion or cd ~= ns.cdSuggestion then
            ns.suggestion, ns.cdSuggestion = s, cd
            ns.ShowSuggestion(s)
        end
    end
    if elapsedLabels >= (ns.labelsDirty and 0.3 or 1.0) then
        if ns.labelsDirty and ns.Census then pcall(ns.Census) end
        elapsedLabels = 0
        ns.labelsDirty = false
        ns.RefreshLabels()
    end
end

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForeverRotationDB = ForeverRotationDB or {}
        for k, v in pairs(ns.DEFAULTS) do
            if ForeverRotationDB[k] == nil then ForeverRotationDB[k] = v end
        end
        ns.db = ForeverRotationDB
        -- what this character cast, learned kill times: per character (0.7.0; the old
        -- account-wide copies are dropped)
        ForeverRotationCharDB = ForeverRotationCharDB or {}
        ns.cdb = ForeverRotationCharDB
        ns.cdb.buffExp = ns.cdb.buffExp or {}
        lastExclusive = ns.cdb.lastAspect
        ns.db.buffExp, ns.db.lastAspect, ns.db.killTimes = nil, nil, nil
        if not ns.db.migratedZoneText then -- 0.2.6: zone text under the square off, icon by the nameplate instead
            ns.db.zone = false
            ns.db.migratedZoneText = true
        end
    elseif event == "PLAYER_LOGIN" then
        ns.cdb.ctype = nil -- 0.9.3: creature types are kept for the account
        seedCreatureTypes()
        ns.ScanSpellbook()
        if ns.InitClass then ns.InitClass() end
        -- the range zone means something only when you also fight from range (not pure melee)
        if ns.zoneUseful == nil then ns.zoneUseful = ns.rangeProbes ~= nil end
        ns.InitButtons()
        ns.InitIcon()
        ns.InitTooltip()
        if ns.InitOptions then ns.InitOptions() end
        frame:SetScript("OnUpdate", update)
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        ns.ScanSpellbook()
        ns.labelsDirty = true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        onCast(arg3)
    elseif event == "PLAYER_TARGET_CHANGED" then
        applied["target"] = nil
        ns.ResetComboEstimate()
        ns.labelsDirty = true
        ns.NoteCreatureType("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ns.NoteCreatureType("mouseover")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        -- which call the game refused, and from where: printed, and kept for /frot blocked
        ns.NoteBlocked(event, arg1, arg2, arg3)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        plates[arg1] = true
        ns.NoteCreatureType(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[arg1] = nil
    elseif event == "PLAYER_DEAD" then
        wipe(applied)
        lastExclusive = nil
        ns.cdb.lastAspect = nil
        wipe(ns.cdb.buffExp)
    else
        ns.labelsDirty = true
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
    "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_DEAD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_LEVEL_UP", "COMBAT_LOG_EVENT_UNFILTERED",
    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED", "UPDATE_MOUSEOVER_UNIT",
}) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for _, e in ipairs({ "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_RANGEDDAMAGE", "UNIT_DAMAGE", "UNIT_STATS" }) do
    pcall(frame.RegisterUnitEvent, frame, e, "player")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/frot - settings window (also the minimap button)",
    "/frot labels - numbers on buttons on/off",
    "/frot glow - highlight suggested spell on/off",
    "/frot icon - separate next-spell icon on/off",
    "/frot unlock | lock - move the square (free position mode)",
    "/frot scale 1.2 - icon size",
    "/frot potions - potion suggestions on/off",
    "/frot debug - print what the addon reads from your buttons",
    "/frot trace - keep a log of rotation decisions (for bug reports) on/off",
    "/frot aggro - what the aggro log has collected so far",
    "/frot spells - save your spellbook (name and id) for bug reports",
    "/frot immune [clear] - immunities learned from the combat log",
    "/frot blocked - what the game refused the addon, and from where",
}

local function toggle(key)
    ns.db[key] = not ns.db[key]
    ns.Print(key .. ": " .. (ns.db[key] and "|cff00ff00on|r" or "|cffff0000off|r"))
    ns.labelsDirty = true
    ns.ShowSuggestion(ns.suggestion)
end

SLASH_FOREVERROTATION1 = "/frot"
SLASH_FOREVERROTATION2 = "/foreverrotation"
SlashCmdList.FOREVERROTATION = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "labels" or cmd == "glow" or cmd == "icon" or cmd == "potions" or cmd == "trace" then
        toggle(cmd)
    elseif cmd == "unlock" or cmd == "lock" then
        ns.db.locked = (cmd == "lock")
        ns.UpdateIconLock()
        ns.Print(cmd == "lock" and "icon locked" or "icon unlocked - drag it")
    elseif cmd == "scale" and tonumber(arg) then
        ns.db.iconScale = math.max(0.5, math.min(3, tonumber(arg)))
        ns.UpdateIconLock()
    elseif cmd == "debug" then
        ns.Debug()
    elseif cmd == "aggro" then
        if ns.AggroStats then ns.AggroStats() end
    elseif cmd == "blocked" then
        local t = ns.cdb and ns.cdb.blocked
        if not t or #t == 0 then ns.Print("nothing blocked so far") end
        for _, line in ipairs(t or {}) do ns.Print(line) end
    elseif cmd == "immune" then
        local list = ns.cdb and ns.cdb.immune
        if arg == "clear" then
            if ns.cdb then ns.cdb.immune, ns.cdb.immuneNames = nil, nil end
            ns.Print("learned immunities forgotten")
        elseif not list or not next(list) then
            ns.Print("no learned immunities yet (an \"immune\" miss of yours teaches one)")
        else
            local names = ns.cdb.immuneNames or {}
            for key in pairs(list) do
                local npc, spell = key:match("^(%d+):(.+)$")
                ns.Print(("%s (npc %s): %s"):format(names[key] or "?", npc or "?", spell or key))
            end
            ns.Print("/frot immune clear forgets them")
        end
    elseif cmd == "spells" then
        ns.ScanSpellbook()
        local out = {}
        for n, id in pairs(ns.known) do out[#out + 1] = ("%s=%d"):format(n, id) end
        table.sort(out)
        ns.db.spellDump = out
        ns.Print(("%d spells saved (SavedVariables after /reload)"):format(#out))
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleOptions then ns.ToggleOptions() end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end
