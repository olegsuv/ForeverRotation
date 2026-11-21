local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "ROGUE" then return end

local R, first = ns.R, ns.first

local SINISTER, EVISCERATE, BACKSTAB, SND, KICK, RUPTURE = 1752, 2098, 53, 5171, 1766, 1943
local EXPOSE, AMBUSH, CHEAP_SHOT, GARROTE, RIPOSTE = 8647, 8676, 1833, 703, 14251
local ADRENALINE, FLURRY, COLD_BLOOD, HEMO, GHOSTLY = 13750, 13877, 14177, 16511, 14278
local EVASION, KIDNEY = 5277, 408

--[[ Priority, from the Forever rogue guides (Maxroll, Mobalytics, Icy Veins, 11/2026), Combat leveling:
  Stealth opener: Ambush (dagger) / Cheap Shot / Garrote. Keep Slice and Dice up, Shank (new in
  Forever) on cooldown, Sinister Strike to 5 combo points, Eviscerate at 5 (earlier to finish a
  dying mob). No Rupture while leveling. Expose Armor on long fights, Adrenaline Rush after Slice
  and Dice, Blade Flurry on 2+, Cold Blood before a 5-point Eviscerate, Riposte after a parry,
  Kick on casts, Evasion when you're low. ]]
local MELEE = { SINISTER, EVISCERATE, BACKSTAB, KICK }

local function rotation()
    local p = ns.PotionCheck(false); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local melee = ns.InMelee(MELEE)
    if melee == false then return nil end
    local tough = ns.TargetIsTough()
    local lives = ns.Lives(35, 8)
    local enemies = ns.EnemyCount()
    local cp = ns.ComboPoints()
    local stealthed = IsStealthed and ns.flag(ns.safe(IsStealthed))

    if stealthed then
        return first(
            function() return R(AMBUSH, true) end,
            function() if tough or ns.flag(ns.safe(UnitIsPlayer, "target")) then return R(CHEAP_SHOT, true) end end,
            function() if lives and ns.CanBleed() then return R(GARROTE, true) end end,
            function() return R(CHEAP_SHOT, true) end,
            function() return R(SINISTER, true) end
        )
    end

    local sndUp = ns.SelfBuff(SND)
    local dying = ns.Dying(20, 4)
    return first(
        function() if ns.TargetCasting() then return R(KICK, true) end end,
        function() if fighting and ns.LowHealth(35) and ns.TargetOnMe() ~= false then return R(EVASION) end end,
        function() return R(RIPOSTE, true) end, -- after a parry
        -- finishers
        function() if cp >= 1 and lives and sndUp == false and not dying then return R(SND) end end,
        function() if cp >= 5 and tough then return R(COLD_BLOOD) end end,
        function() if cp >= 5 and tough and not ns.DebuffUp(ns.N(EXPOSE)) and ns.RecentCasts(ns.N(EXPOSE) or "", 30) == 0 then return R(EXPOSE, true) end end,
        function() if cp >= 5 or (cp >= 2 and dying) then return R(EVISCERATE, true) end end,
        -- cooldowns
        function() if tough and sndUp ~= false then return R(ADRENALINE) end end,
        function() if enemies >= 2 then return R(FLURRY) end end,
        -- builders
        function() return R("Shank", true) end,
        function() return R(GHOSTLY, true) end,
        function() return R("Mutilate", true) end, -- daggers
        function() return R(HEMO, true) end,
        function() return R(SINISTER, true) end
    )
end

function ns.InitClass()
    local n = ns.N
    ns.selfBuffs[n(SND) or "Slice and Dice"] = function() return 6 + 3 * math.max(1, ns.ComboPoints()) end
    for _, s in ipairs({ SINISTER, BACKSTAB, GHOSTLY, HEMO, AMBUSH, GARROTE }) do
        if n(s) then ns.cpBuilders[n(s)] = 1 end
    end
    ns.cpBuilders["Shank"] = 1
    ns.cpBuilders["Mutilate"] = 2
    if n(CHEAP_SHOT) then ns.cpBuilders[n(CHEAP_SHOT)] = 2 end
    for _, s in ipairs({ EVISCERATE, SND, RUPTURE, EXPOSE, KIDNEY }) do
        if n(s) then ns.cpFinishers[n(s)] = true end
    end
    ns.durations[n(EXPOSE) or "Expose Armor"] = 30
    ns.meleeProbes = MELEE
    ns.traceSpells = { SINISTER, EVISCERATE, SND, "Shank", RIPOSTE, KICK }
    ns.rotation = rotation
end
