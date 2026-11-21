local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "MAGE" then return end

local R, first = ns.R, ns.first

local FIREBALL, FROSTBOLT, MISSILES, FIRE_BLAST, FROST_NOVA = 133, 116, 5143, 2136, 122
local ARCANE_EXPLOSION, CONE_OF_COLD, BLIZZARD, FLAMESTRIKE = 1449, 120, 10, 2120
local PYROBLAST, SCORCH, FROST_ARMOR, ICE_ARMOR, MAGE_ARMOR = 11366, 2948, 168, 7302, 6117
local ARCANE_INTELLECT, COUNTERSPELL, EVOCATION, ICE_BARRIER = 1459, 2139, 12051, 11426
local ARCANE_POWER, PRESENCE_OF_MIND, COMBUSTION, BLAST_WAVE, COLD_SNAP = 12042, 12043, 11129, 11113, 12472
local MANA_SHIELD = 1463

--[[ Priority, from the Forever mage guides (Maxroll, Mobalytics, Wowhead, 11/2026):
  Frost leveling: Frostbolt main nuke; Ice Lance (new, 8 s cooldown, triple damage on frozen
  targets and with Fingers of Frost); Frost Nova + step back when a mob reaches you, Cone of Cold
  on packs in melee. Fire: Fireball; Heating Up / Hot Streak -> instant Pyroblast; Fire Blast on
  cooldown. Arcane: Arcane Blast, Arcane Missiles on Missile Barrage. Keep an armor and Arcane
  Intellect up, Evocation when dry, Counterspell casts, wand when out of mana. ]]

local function spec()
    if ns.Known(PYROBLAST) or ns.Known(COMBUSTION) or ns.Known(BLAST_WAVE) then return "fire" end
    if ns.Known(ARCANE_POWER) or ns.Known(PRESENCE_OF_MIND) or ns.Known("Arcane Blast") then return "arcane" end
    return "frost"
end

local function frozen()
    return ns.DebuffUp(ns.N(FROST_NOVA)) or ns.DebuffUp("Frostbite")
end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local s = spec()
    local close = ns.flag(ns.safe(CheckInteractDistance, "target", 3))
    local onMe = ns.TargetOnMe()
    local enemies = ns.EnemyCount()
    local tough = ns.TargetIsTough()
    local dying = ns.Dying(15, 3)
    local main = s == "fire" and FIREBALL or FROSTBOLT
    if not ns.Known(main) then main = FIREBALL end
    local dry = ns.ManaShort(10, main)

    if not fighting then
        local armor = first(
            function() if ns.Known(MAGE_ARMOR) and s == "arcane" then return true, MAGE_ARMOR end end,
            function() if ns.Known(ICE_ARMOR) then return true, ICE_ARMOR end end,
            function() if ns.Known(FROST_ARMOR) then return true, FROST_ARMOR end end
        )
        local anyArmor = ns.SelfBuff(FROST_ARMOR) or ns.SelfBuff(ICE_ARMOR) or ns.SelfBuff(MAGE_ARMOR) or ns.SelfBuff("Molten Armor")
        local r = first(
            function() if armor and anyArmor == false then return R(armor) end end,
            function() if ns.BuffMissing(ARCANE_INTELLECT) then return R(ARCANE_INTELLECT) end end
        )
        if r then return r end
    end

    return first(
        function() if ns.TargetCasting() then return R(COUNTERSPELL, true) end end,
        -- it reached you: freeze it and step back
        function() if close and onMe ~= false and not frozen() then return R(FROST_NOVA) end end,
        function() if close and onMe == true and ns.LowHealth(50) then return R(ICE_BARRIER) end end,
        function() if dry then return R(EVOCATION) end end,
        -- packs
        function() if enemies >= 2 and close then return R(BLAST_WAVE) end end,
        function() if enemies >= 3 and close then return R(ARCANE_EXPLOSION) end end,
        function() if enemies >= 2 and close then return R(CONE_OF_COLD) end end,
        function() if enemies >= 3 and s == "fire" then return R(FLAMESTRIKE) end end,
        function() if enemies >= 3 then return R(BLIZZARD) end end,
        -- procs
        function() if ns.Proc(PYROBLAST) then return R(PYROBLAST, true) end end,
        function() if ns.Proc("Ice Lance") or frozen() then return R("Ice Lance", true) end end,
        function() if ns.Proc(MISSILES) then return R(MISSILES, true) end end,
        -- cooldowns on elites
        function() if tough and ns.Lives(35, 15) then return R(COMBUSTION) end end,
        function() if tough then return R(ARCANE_POWER) end end,
        function() if tough then return R(PRESENCE_OF_MIND) end end,
        function() if tough then return R("Icy Veins") end end,
        -- finish a dying mob with an instant
        function() if dying then return R(FIRE_BLAST, true) end end,
        function() if dying then return R("Ice Lance", true) end end,
        function() if dry then return ns.Wand() end end,
        -- spec nukes
        function() if s == "fire" then return R(FIRE_BLAST, true) end end,
        function() if s == "fire" then return R(FIREBALL, true) end end,
        function() if s == "arcane" then return R("Arcane Blast", true) end end,
        function() if s == "arcane" then return R(MISSILES, true) end end,
        function() if s == "frost" and ns.Better("Ice Lance", FROSTBOLT) then return R("Ice Lance", true) end end,
        function() return R(FROSTBOLT, true) end,
        function() return R(FIREBALL, true) end,
        function() return ns.Wand() end
    )
end

function ns.InitClass()
    local n = ns.N
    for _, a in ipairs({ FROST_ARMOR, ICE_ARMOR, MAGE_ARMOR }) do
        if n(a) then ns.selfBuffs[n(a)] = 1800; ns.buffGroups[n(a)] = "armor" end
    end
    ns.selfBuffs["Molten Armor"] = 1800; ns.buffGroups["Molten Armor"] = "armor"
    ns.selfBuffs[n(ARCANE_INTELLECT) or "Arcane Intellect"] = 1800
    ns.durations[n(FROST_NOVA) or "Frost Nova"] = 8
    ns.rangeProbes = { FROSTBOLT, FIREBALL }
    ns.zoneText = { shoot = "In range" }
    ns.traceSpells = { FROSTBOLT, FIREBALL, FIRE_BLAST, "Ice Lance", PYROBLAST, FROST_NOVA }
    ns.rotation = rotation
end
