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
    moveArrow = true,  -- arrow by the square: step back (too close to shoot) / step closer (out of reach)
    selfHeal = 35,     -- healers / hybrids: suggest a self-heal below this % health
    trace = true,      -- keep a short log of rotation decisions in SavedVariables (debug)
    aggroLog = true,   -- log at what distance / level mobs aggro on you (data for an aggro indicator)
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
    local ok, a, b, c, d, e, g, h = pcall(f, ...)
    if ok then return a, b, c, d, e, g, h end
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

-- known + usable + off cooldown (+ target not out of range when checkRange)
function ns.Ready(baseID, checkRange)
    local _, id = ns.Spell(baseID)
    if not id then return false end
    if not ns.Usable(id) then return false end
    if ns.OnCooldown(id) then return false end
    if checkRange and ns.InRange(id) == false then return false end
    return true, id
end

-- Trace: why the rotation picked what it picked (saved, for remote debugging)
function ns.Trace(line)
    if not ns.db or not ns.db.trace then return end
    local t = ns.db.traceLog or {}
    ns.db.traceLog = t
    t[#t + 1] = ("%.1f %s"):format(GetTime(), line)
    while #t > 300 do table.remove(t, 1) end
end

-- same as Ready, by spell name (for Forever-only spells whose ids we don't hard-code)
function ns.ReadyName(spellName, checkRange)
    local id = ns.known[spellName]
    if not id then return false end
    if not ns.Usable(id) then return false end
    if ns.OnCooldown(id) then return false end
    if checkRange and ns.InRange(id) == false then return false end
    return true, id
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
                    if ns.db then ns.db.lastAspect = name end
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
function ns.first(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        local ok, id = f()
        if ok then return id end
    end
end

-- R(id or name [, checkRange]): ready by base spell id (any rank) or by name
function ns.R(spell, checkRange)
    if type(spell) == "number" then return ns.Ready(spell, checkRange) end
    return ns.ReadyName(spell, checkRange)
end

-- name of a base spell id (Forever renames some: Curse of Agony -> Bane of Agony)
function ns.N(spell)
    if type(spell) == "string" then return spell end
    return ns.safe(C_Spell.GetSpellName, spell)
end

-- do we know this spell (id or name)?
function ns.Known(spell)
    local n = ns.N(spell)
    return n and ns.known[n] and true or false
end

-- raw power value, nil when hidden
function ns.Power(powerType)
    local v = ns.num(ns.safe(UnitPower, "player", powerType))
    return v
end

-- the spell's own resource is short (rage, energy, mana): true / false
function ns.NoResource(spell)
    local n = ns.N(spell)
    local id = n and ns.known[n]
    if not id then return false end
    local _, noMana = ns.Usable(id)
    return noMana == true
end

-- known and off cooldown, only short of its resource: the spell to wait for (rage, energy)
function ns.Pool(spell, checkRange)
    local n = ns.N(spell)
    local id = n and ns.known[n]
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

-- the target is hitting you: true / false / nil (hidden)
function ns.TargetOnMe()
    local onMe = ns.flag(ns.safe(UnitIsUnit, "targettarget", "player"))
    if onMe ~= nil then return onMe end
    local threat = ns.num(ns.safe(UnitThreatSituation, "player", "target"))
    if threat then return threat >= 2 end
    return nil
end

-- creature type of the target, nil when hidden
function ns.TargetType()
    local t = ns.safe(UnitCreatureType, "target")
    if t and not isSecret(t) then return t end
end

local BLEED_IMMUNE = { Mechanical = true, Elemental = true, ["Механизм"] = true, ["Элементаль"] = true }
function ns.CanBleed()
    local t = ns.TargetType()
    return not (t and BLEED_IMMUNE[t])
end

-- the mob lives long enough for a DoT / buildup: not low, or elite / player
function ns.Lives(threshold)
    local hp = ns.Percent("target")
    return not hp or hp >= (threshold or 40) or ns.TargetIsTough()
end

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
    buffExp = buffExp or (ns.db and ns.db.buffExp) or {}
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
    buffExp = buffExp or (ns.db and ns.db.buffExp) or {}
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
function ns.PotionCheck(usesMana)
    if not ns.db.potions then return nil end
    if not ns.flag(UnitAffectingCombat("player")) then return nil end
    local hp = ns.Percent("player")
    if hp and hp < ns.db.potionHealth then
        local s = ns.ReadyItem(ns.HEAL_POTIONS); if s then return s end
    end
    if usesMana then
        local mana = ns.Percent("player", Enum.PowerType.Mana)
        if mana and mana < ns.db.potionMana then
            local s = ns.ReadyItem(ns.MANA_POTIONS); if s then return s end
        end
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

-- which way to step: "back" (too close to shoot), "closer" (out of reach) or nil
function ns.MoveHint()
    local z = ns.RangeZone and ns.RangeZone()
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
    out[#out + 1] = ("en=%d"):format(ns.EnemyCount())
    for _, s in ipairs(ns.traceSpells) do
        local n = ns.N(s)
        local id = n and ns.known[n]
        if id then
            local u = ns.Usable(id)
            local r = ns.InRange(id)
            out[#out + 1] = ("%s:u%s/cd%s/r%s"):format(n:sub(1, 6), u and 1 or 0, ns.OnCooldown(id) and 1 or 0,
                r == nil and "?" or (r and 1 or 0))
        end
    end
    out[#out + 1] = "zone=" .. tostring(ns.RangeZone())
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
        if ns.db then ns.db.lastAspect = name end
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

function ns.EnemyCount(rangeSpellID)
    local n = 0
    for unit in pairs(plates) do
        local hostile = ns.flag(ns.safe(UnitCanAttack, "player", unit))
        local dead = ns.flag(ns.safe(UnitIsDead, unit))
        local fighting = ns.flag(ns.safe(UnitAffectingCombat, unit))
        local inRange = rangeSpellID and ns.InRange(rangeSpellID, unit)
        if hostile ~= false and dead ~= true and fighting ~= false and inRange ~= false then
            n = n + 1
        end
    end
    return n
end

function ns.TargetIsTough()
    local cls = ns.safe(UnitClassification, "target")
    if cls and not isSecret(cls) and (cls == "elite" or cls == "rareelite" or cls == "worldboss") then
        return true
    end
    return ns.flag(ns.safe(UnitIsPlayer, "target")) == true
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

-- first item from the list you carry that is off cooldown -> its use-spellID, itemID
function ns.ReadyItem(list)
    for _, itemID in ipairs(list) do
        local count = ns.num(ns.safe(C_Item.GetItemCount, itemID))
        if count and count > 0 and itemReady(itemID) then
            local _, spellID = ns.safe(C_Item.GetItemSpell, itemID)
            if spellID then return spellID, itemID end
        end
    end
end

---------------------------------------------------------------------------
-- Rotation registry
---------------------------------------------------------------------------
ns.rotation = nil -- function() -> spellID or nil; set by a class module
ns.suggestion = nil

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
        local s
        if ns.rotation and ns.HostileTarget() then
            local ok, res = pcall(ns.rotation)
            if ok then s = res elseif ns.db.debug then ns.Print("rotation error: " .. tostring(res)) end
        end
        if ns.db.trace and ns.TraceState and ns.HostileTarget() then
            local now = GetTime()
            local fighting = ns.flag(UnitAffectingCombat("player"))
            if s ~= ns.suggestion or (fighting and now - (ns.lastTrace or 0) > 1) then
                ns.lastTrace = now
                local ok, state = pcall(ns.TraceState)
                ns.Trace(("%s | %s"):format(s and C_Spell.GetSpellName(s) or "-", ok and state or ("err " .. tostring(state))))
            end
        end
        if s ~= ns.suggestion then
            ns.suggestion = s
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
        ns.db.buffExp = ns.db.buffExp or {}
        lastExclusive = ns.db.lastAspect
        if not ns.db.migratedZoneText then -- 0.2.6: zone text under the square off, icon by the nameplate instead
            ns.db.zone = false
            ns.db.migratedZoneText = true
        end
    elseif event == "PLAYER_LOGIN" then
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
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        plates[arg1] = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[arg1] = nil
    elseif event == "PLAYER_DEAD" then
        wipe(applied)
        lastExclusive = nil
        ns.db.lastAspect = nil
        wipe(ns.db.buffExp)
    else
        ns.labelsDirty = true
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
    "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_DEAD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_LEVEL_UP",
}) do
    pcall(frame.RegisterEvent, frame, e)
end
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for _, e in ipairs({ "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_RANGEDDAMAGE", "UNIT_DAMAGE", "UNIT_STATS", "UNIT_AURA" }) do
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
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleOptions then ns.ToggleOptions() end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end
