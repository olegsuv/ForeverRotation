local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "SHAMAN" then return end

local R, first = ns.R, ns.first

local LIGHTNING_BOLT, EARTH_SHOCK, FLAME_SHOCK, FROST_SHOCK, LIGHTNING_SHIELD = 403, 8042, 8050, 8056, 324
local ROCKBITER, FLAMETONGUE, WINDFURY, FROSTBRAND = 8017, 8024, 8232, 8033
local SEARING_TOTEM, MAGMA_TOTEM, FIRE_NOVA_TOTEM, STRENGTH_TOTEM = 3599, 8190, 1535, 8075
local HEALING_WAVE, LESSER_HW, CHAIN_LIGHTNING, STORMSTRIKE, ELEMENTAL_MASTERY = 331, 8004, 421, 17364, 16166

--[[ Priority, from the Forever shaman guides (Maxroll, Mobalytics, Wowhead, 11/2026):
  Enhancement leveling: weapon imbue (Windfury > Flametongue > Rockbiter) and Lightning Shield up,
  Searing Totem on mobs that live, Stormstrike (25) on cooldown, Rage of the Farseer (51) on
  cooldown, Lightning Bolt when Maelstrom lights it up (5 stacks), Flame Shock on long fights,
  Earth Shock with spare mana (and to interrupt). Elemental / casting from range: Flame Shock,
  Lava Burst, Chain Lightning on packs, Lightning Bolt filler. Heal yourself when low. ]]
local MELEE = { STORMSTRIKE, "Primal Strike" }

local function totemOut(s, window) return ns.RecentCasts(ns.N(s) or "", window) > 0 end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local melee = ns.InMelee(MELEE)
    local lives = ns.Lives(35)
    local tough = ns.TargetIsTough()
    local enemies = ns.EnemyCount()
    local fsUp = ns.DebuffUp(ns.N(FLAME_SHOCK))
    local manaOk = not ns.ManaShort(30, LIGHTNING_BOLT)

    -- weapon imbue
    if ns.WeaponEnchanted() == false then
        for _, s in ipairs({ WINDFURY, FLAMETONGUE, ROCKBITER }) do
            if ns.Known(s) then local ok, id = R(s); if ok then return id end; break end
        end
    end
    if ns.BuffMissing(LIGHTNING_SHIELD) then
        local ok, id = R(LIGHTNING_SHIELD); if ok then return id end
    end

    -- pull from range
    if not fighting and melee ~= true then
        return first(
            function() return R(LIGHTNING_BOLT, true) end
        )
    end

    return first(
        function() if ns.LowHealth() then return R(LESSER_HW) end end,
        function() if ns.LowHealth() then return R(HEALING_WAVE) end end,
        function() if ns.TargetCasting() then return R("Wind Shear", true) end end,
        function() if ns.TargetCasting() then return R(EARTH_SHOCK, true) end end,
        function() if ns.Proc(LIGHTNING_BOLT) then return R(LIGHTNING_BOLT, true) end end, -- Maelstrom
        function() if tough then return R(ELEMENTAL_MASTERY) end end,
        function() if melee ~= false then return R("Rage of the Farseer", true) end end,
        function() if melee ~= false then return R(STORMSTRIKE, true) end end,
        function() if melee ~= false then return R("Primal Strike", true) end end,
        -- totems
        function() if enemies >= 3 and melee ~= false and not totemOut(MAGMA_TOTEM, 20) then return R(MAGMA_TOTEM) end end,
        function() if enemies >= 3 and melee ~= false and not totemOut(FIRE_NOVA_TOTEM, 10) then return R(FIRE_NOVA_TOTEM) end end,
        function() if lives and enemies < 3 and not totemOut(SEARING_TOTEM, 30) and not totemOut(MAGMA_TOTEM, 20) then return R(SEARING_TOTEM) end end,
        -- shocks (shared cooldown)
        function() if lives and not fsUp then return R(FLAME_SHOCK, true) end end,
        function() if fsUp then return R("Lava Burst", true) end end,
        function() if enemies >= 2 and manaOk then return R(CHAIN_LIGHTNING, true) end end,
        function() if manaOk or not lives then return R(EARTH_SHOCK, true) end end,
        -- casting from range (elemental, or the mob isn't here yet)
        function() if melee == false or not ns.Known(STORMSTRIKE) and ns.Known(ELEMENTAL_MASTERY) then return R(LIGHTNING_BOLT, true) end end
    )
end

function ns.InitClass()
    local n, d = ns.N, ns.durations
    ns.selfBuffs[n(LIGHTNING_SHIELD) or "Lightning Shield"] = 600
    d[n(FLAME_SHOCK) or "Flame Shock"] = 12
    ns.meleeProbes = MELEE
    ns.rangeProbes = { LIGHTNING_BOLT, EARTH_SHOCK }
    ns.zoneText = { shoot = "In range" }
    ns.traceSpells = { LIGHTNING_BOLT, EARTH_SHOCK, FLAME_SHOCK, STORMSTRIKE, SEARING_TOTEM, "Lava Burst" }
    ns.rotation = rotation
end
