local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "WARRIOR" then return end

local R, first = ns.R, ns.first

local BATTLE_SHOUT, CHARGE, REND, HEROIC_STRIKE, THUNDER_CLAP = 6673, 100, 772, 78, 6343
local HAMSTRING, OVERPOWER, EXECUTE, SUNDER, DEMO_SHOUT = 1715, 7384, 5308, 7386, 1160
local BLOODRAGE, REVENGE, SHIELD_BASH, CLEAVE, WHIRLWIND = 2687, 6572, 72, 845, 1680
local MORTAL_STRIKE, BLOODTHIRST, DEATH_WISH, SWEEPING, SHIELD_SLAM = 12294, 23881, 12292, 12328, 23922
local PUMMEL, INTERCEPT, SLAM = 6552, 20252, 1464
local DEF_STANCE, TAUNT, SHIELD_BLOCK, MOCKING_BLOW = 71, 355, 2565, 694

--[[ Priority, from the Forever warrior guides (Maxroll, Mobalytics, Wowhead, 11/2026):
  Pull: Battle Shout, Charge. Victory Rush whenever it lights up (baseline in Forever).
  Overpower / Revenge / Execute when they light up. Arms: Mortal Strike on cooldown,
  Rend on mobs that live, Spearing Strike. Fury: Bloodrage on cooldown in combat, Death Wish
  on hard targets, Bloodthirst and Whirlwind on cooldown, Execute under 20 %. Thunder Clap /
  Sweeping Strikes / Cleave / Whirlwind for packs, Demoralizing Shout and Sunder Armor (to 5)
  on elites, Heroic Strike / Cleave with spare rage (any rage before you have a big strike).
  Pummel / Shield Bash on casts.
  Tank (Defensive Stance, or a shield in a group): Taunt / Mocking Blow when the mob leaves
  you, Revenge, Shield Slam, Shield Block on hard hitters, Thunder Clap / Demoralizing Shout
  on packs, Sunder Armor as the threat filler, Heroic Strike / Cleave with spare rage.
  Nothing affordable: show the next strike to wait for (tinted blue on the square). ]]
local MELEE = { REND, HEROIC_STRIKE, HAMSTRING, SUNDER }
local MAIN = { MORTAL_STRIKE, BLOODTHIRST, SHIELD_SLAM, "Spearing Strike" }

local function rage() return ns.Power(Enum.PowerType.Rage or 1) end

-- the big cooldown strike of your spec is waiting: spend rage on it, not Heroic Strike
local function mainStrikeReady()
    for _, s in ipairs(MAIN) do
        if ns.Known(s) then
            local n = ns.N(s); local id = ns.known[n]
            if id and not ns.OnCooldown(id) then return true end
        end
    end
    return false
end

local function hasMainStrike()
    for _, s in ipairs(MAIN) do
        if ns.Known(s) then return true end
    end
    return false
end

local function shieldOn()
    local id = GetInventoryItemID and ns.safe(GetInventoryItemID, "player", 17)
    if not id then return false end
    local _, _, _, loc = ns.safe(C_Item.GetItemInfoInstant, id)
    return loc == "INVTYPE_SHIELD"
end

-- Defensive Stance, or a shield while in a group (the stance can be hidden in combat)
local function tanking()
    local form = ns.Form()
    if form ~= nil and form ~= "" and form == ns.N(DEF_STANCE) then return true end
    return shieldOn() and IsInGroup and IsInGroup() or false
end

local function tankRotation(casting, tough, enemies, r)
    local spare = (r and r >= 40) or r == nil
    local onMe = ns.TargetOnMe()
    local grouped = IsInGroup and IsInGroup()
    return first(
        function() if casting then return R(SHIELD_BASH, true) end end,
        function() if casting then return R(PUMMEL, true) end end,
        function() if grouped and onMe == false then return R(TAUNT, true) end end,
        function() if grouped and onMe == false then return R(MOCKING_BLOW, true) end end,
        function() return R("Victory Rush", true) end,
        function() return R(BLOODRAGE) end,
        function() if ns.BuffMissing(BATTLE_SHOUT) then return R(BATTLE_SHOUT) end end,
        function() return R(REVENGE, true) end, -- after a block / dodge / parry
        function() return R(SHIELD_SLAM, true) end,
        function() if tough and onMe ~= false then return R(SHIELD_BLOCK) end end,
        function() return R(EXECUTE, true) end,
        function() if enemies >= 2 and not ns.DebuffUp(ns.N(THUNDER_CLAP)) then return R(THUNDER_CLAP) end end,
        function() if (tough or enemies >= 2) and not ns.DebuffUp(ns.N(DEMO_SHOUT)) then return R(DEMO_SHOUT) end end,
        function() return R(SUNDER, true) end,
        function() if spare and enemies >= 2 then return R(CLEAVE, true) end end,
        function() if spare then return R(HEROIC_STRIKE, true) end end,
        -- short of rage: what to press when it comes
        function() return ns.Pool(SHIELD_SLAM, true) end,
        function() return ns.Pool(SUNDER, true) end
    )
end

local function rotation()
    local p = ns.PotionCheck(false); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local melee = ns.InMelee(MELEE)
    local tough = ns.TargetIsTough()
    local lives = ns.Lives(40)
    local enemies = ns.EnemyCount()
    local r = rage()

    if not fighting then
        local s = first(
            function() if ns.BuffMissing(BATTLE_SHOUT) then return R(BATTLE_SHOUT) end end,
            function() if melee ~= true then return R(CHARGE, true) end end
        )
        if s or melee ~= true then return s end
        -- already next to it out of combat: open with the fight priority below
    end

    if melee == false then
        return first(
            function() return R(INTERCEPT, true) end,
            function() return R(CHARGE, true) end,
            function() return R(BLOODRAGE) end,
            function() if ns.BuffMissing(BATTLE_SHOUT) then return R(BATTLE_SHOUT) end end
        )
    end

    local casting = ns.TargetCasting()
    if tanking() then return tankRotation(casting, tough, enemies, r) end

    local hasMain = hasMainStrike()
    local spare = not hasMain or (r and r >= 50) or (r == nil and not mainStrikeReady())
    local rendWanted = lives and ns.CanBleed() and not ns.DebuffUp(ns.N(REND))

    return first(
        function() if casting then return R(PUMMEL, true) end end,
        function() if casting then return R(SHIELD_BASH, true) end end,
        function() return R("Victory Rush", true) end,
        function() return R(BLOODRAGE) end, -- off the global cooldown, rage for free
        function() if ns.BuffMissing(BATTLE_SHOUT) then return R(BATTLE_SHOUT) end end,
        function() return R(EXECUTE, true) end, -- only lights up under 20 %
        function() return R(OVERPOWER, true) end, -- after a dodge
        function() return R(REVENGE, true) end, -- after a block / dodge / parry
        function() if tough then return R(DEATH_WISH) end end,
        function() if tough then return R("Reckless Swings") end end,
        function() if enemies >= 2 then return R(SWEEPING) end end,
        function() return R(MORTAL_STRIKE, true) end,
        function() return R(BLOODTHIRST, true) end,
        function() return R(SHIELD_SLAM, true) end,
        function() return R("Spearing Strike", true) end,
        function() if enemies >= 2 or ns.Known(BLOODTHIRST) then return R(WHIRLWIND) end end,
        function() if enemies >= 2 and not ns.DebuffUp(ns.N(THUNDER_CLAP)) then return R(THUNDER_CLAP) end end,
        function() if (tough or enemies >= 2) and not ns.DebuffUp(ns.N(DEMO_SHOUT)) then return R(DEMO_SHOUT) end end,
        function() if rendWanted then return R(REND, true) end end,
        function() if tough and ns.RecentCasts(ns.N(SUNDER) or "", 30) < 5 then return R(SUNDER, true) end end,
        function() if ns.flag(ns.safe(UnitIsPlayer, "target")) and not ns.DebuffUp(ns.N(HAMSTRING)) then return R(HAMSTRING, true) end end,
        function() if spare and enemies >= 2 then return R(CLEAVE, true) end end,
        function() if spare then return R(HEROIC_STRIKE, true) end end,
        function() if spare then return R(SLAM, true) end end,
        -- short of rage: what to press when it comes
        function() return ns.Pool(MORTAL_STRIKE, true) end,
        function() return ns.Pool(BLOODTHIRST, true) end,
        function() return ns.Pool(SHIELD_SLAM, true) end,
        function() return ns.Pool("Spearing Strike", true) end,
        function() if rendWanted then return ns.Pool(REND, true) end end,
        function() if not hasMain then return ns.Pool(HEROIC_STRIKE, true) end end
    )
end

function ns.InitClass()
    ns.selfBuffs[ns.N(BATTLE_SHOUT) or "Battle Shout"] = 120
    local d = ns.durations
    d[ns.N(REND) or "Rend"] = 15
    d[ns.N(THUNDER_CLAP) or "Thunder Clap"] = 10
    d[ns.N(DEMO_SHOUT) or "Demoralizing Shout"] = 30
    d[ns.N(HAMSTRING) or "Hamstring"] = 15
    ns.meleeProbes = MELEE
    ns.traceSpells = { HEROIC_STRIKE, REND, SUNDER, REVENGE, OVERPOWER, EXECUTE, MORTAL_STRIKE, BLOODTHIRST, "Victory Rush" }
    ns.rotation = rotation
end
