local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "PALADIN" then return end

local R, first = ns.R, ns.first

local SOR, SOTC, SOC, SOL, SOW, SOJ = 21084, 21082, 20375, 20165, 20166, 20164
local JUDGEMENT, HOLY_LIGHT, FLASH_OF_LIGHT, HOJ = 20271, 635, 19750, 853
local MIGHT, WISDOM, DEVOTION, RETRIBUTION_AURA = 19740, 19742, 465, 7294
local CONSECRATION, EXORCISM, HOLY_WRATH, HAMMER_OF_WRATH = 26573, 879, 2812, 24275
local DIVINE_SHIELD, DIVINE_PROTECTION, LAY_ON_HANDS = 642, 498, 633

--[[ Priority, from the Forever paladin guides (Maxroll, Mobalytics, Wowhead, 11/2026), Retribution:
  Seal of the Crusader -> Judgement once on elites, then Seal of Command / Righteousness; in Forever
  Judgement keeps the seal and is off the global cooldown: use it on cooldown. Holy Strike (6, 10 s
  cooldown) on cooldown, Hammer of Wrath under 20 %, Exorcism / Holy Wrath on Undead and Demons,
  Consecration on packs, Hammer of Justice to stop casts. Blessing of Might and Retribution Aura
  up; Divine Protection / Lay on Hands / Holy Light when it goes wrong. ]]
local MELEE = { "Holy Strike", "Crusader Strike", JUDGEMENT, HOJ }
local UNDEAD = { Undead = true, Demon = true, ["Нежить"] = true, ["Демон"] = true }
local SEALS = { SOC, SOR, SOTC, SOL, SOW, SOJ, "Seal of Vengeance", "Seal of Blood" }

local function anySeal()
    local unknown = false
    for _, s in ipairs(SEALS) do
        local st = ns.Known(s) and ns.SelfBuff(s)
        if st == true then return true end
        if st == nil and ns.Known(s) then unknown = true end
    end
    if unknown then return nil end
    return false
end

local shieldOn = ns.ShieldOn

local function bestSeal()
    for _, s in ipairs({ SOC, "Seal of Vengeance", "Seal of Blood", SOR }) do
        if ns.Known(s) then return s end
    end
end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local melee = ns.InMelee(MELEE)
    local tough = ns.TargetIsTough()
    local lives = ns.Lives(35, 8)
    local enemies = ns.EnemyCount()
    local ctype = ns.TargetType()
    local seal = anySeal()
    local sotcUp = ns.Known(SOTC) and ns.SelfBuff(SOTC) == true
    local judged = ns.RecentCasts(ns.N(JUDGEMENT) or "Judgement", 8) > 0
    local crusaderOn = ns.DebuffUp("Judgement of the Crusader") or (sotcUp and judged)

    -- aura: the stance bar shows none
    local aura = ns.Known(RETRIBUTION_AURA) and RETRIBUTION_AURA or DEVOTION
    if ns.Known(aura) and ns.Form() == "" and ns.SelfBuff(aura) == false then
        local ok, id = R(aura); if ok then return id end
    end
    if ns.BuffMissing(MIGHT) then
        local ok, id = R(MIGHT); if ok then return id end
    end

    return first(
        -- it goes wrong
        function() if fighting and ns.LowHealth(15) then return R(DIVINE_SHIELD) end end,
        function() if fighting and ns.LowHealth(15) then return R(LAY_ON_HANDS) end end,
        function() if fighting and ns.LowHealth(25) then return R(DIVINE_PROTECTION) end end,
        function() if ns.LowHealth() then return R(FLASH_OF_LIGHT) end end,
        function() if ns.LowHealth() then return R(HOLY_LIGHT) end end,
        function() if ns.TargetCasting() then return R(HOJ, true) end end,
        -- seal: Crusader for the first Judgement on elites, then the damage seal
        function()
            if tough and not crusaderOn and ns.Known(SOTC) and ns.SelfBuff(SOTC) == false then return R(SOTC) end
        end,
        function() if seal == false then local b = bestSeal(); if b then return R(b) end end end,
        -- Crusader did its job (or it's a weak mob): back to the damage seal
        function()
            if sotcUp and (crusaderOn or not tough) then
                local b = bestSeal(); if b and b ~= SOTC then return R(b) end
            end
        end,
        function() if seal ~= false and melee ~= false then return R(JUDGEMENT, true) end end,
        function() return R(HAMMER_OF_WRATH, true) end, -- under 20 %
        function() if melee ~= false then return R("Crusader Strike", true) end end,
        function() if melee ~= false then return R("Holy Strike", true) end end,
        function() return R("Holy Shock", true) end,
        -- with a shield on, a hard hitter or a pack on you
        function() if shieldOn() and melee ~= false and (tough or enemies >= 2) and ns.TargetOnMe() ~= false then return R("Holy Shield") end end,
        function() if ctype and UNDEAD[ctype] then return R(EXORCISM, true) end end,
        function() if ctype and UNDEAD[ctype] and enemies >= 2 then return R(HOLY_WRATH) end end,
        function() if enemies >= 2 and melee ~= false then return R(CONSECRATION) end end,
        function() if tough and lives and melee ~= false then return R(CONSECRATION) end end
    )
end

function ns.InitClass()
    local n = ns.N
    for _, s in ipairs(SEALS) do
        local name = n(s)
        if name then ns.selfBuffs[name] = 30; ns.buffGroups[name] = "seal" end
    end
    ns.selfBuffs[n(MIGHT) or "Blessing of Might"] = 300
    ns.durations["Judgement of the Crusader"] = 10
    ns.meleeProbes = MELEE
    ns.traceSpells = { JUDGEMENT, SOR, SOC, "Holy Strike", "Crusader Strike", CONSECRATION }
    ns.rotation = rotation
end
