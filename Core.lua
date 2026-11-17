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

-- known + usable + off cooldown
function ns.Ready(baseID)
    local _, id = ns.Spell(baseID)
    if not id then return false end
    if not ns.Usable(id) then return false end
    return not ns.OnCooldown(id), id
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

local function onCast(spellID)
    local name = ns.safe(C_Spell.GetSpellName, spellID)
    if not name or isSecret(name) then return end
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
        if s ~= ns.suggestion then
            ns.suggestion = s
            ns.ShowSuggestion(s)
        end
    end
    if elapsedLabels >= (ns.labelsDirty and 0.3 or 1.0) then
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
    elseif event == "PLAYER_LOGIN" then
        ns.ScanSpellbook()
        if ns.InitClass then ns.InitClass() end
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
        ns.labelsDirty = true
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        plates[arg1] = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[arg1] = nil
    elseif event == "PLAYER_DEAD" then
        wipe(applied)
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
    if cmd == "labels" or cmd == "glow" or cmd == "icon" or cmd == "potions" then
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
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleOptions then ns.ToggleOptions() end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end
