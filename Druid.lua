local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "DRUID" then return end

local R, first = ns.R, ns.first

local WRATH, MOONFIRE, REJUV, HEALING_TOUCH, REGROWTH, MOTW, THORNS = 5176, 8921, 774, 5185, 8936, 1126, 467
local STARFIRE, INSECT_SWARM, FAERIE_FIRE, FF_FERAL, BEAR, CAT = 2912, 5570, 770, 16857, 5487, 768
local CLAW, RAKE, RIP, SHRED, BITE, MAUL, SWIPE, DEMO_ROAR, ENRAGE = 1082, 1822, 1079, 5221, 22568, 6807, 779, 99, 5229
local MOONKIN, HURRICANE, RAVAGE, POUNCE, PROWL, BASH = 24858, 16914, 6785, 9005, 5215, 5211

--[[ Priority, from the Forever druid guides (Maxroll, Mobalytics, Wowhead, 11/2026):
  Cat (Feral leveling): Faerie Fire (Feral) up (free in cat), Rake (24) on mobs that live 9+ s,
  Claw to build (Shred on a Clearcasting proc), Rip at 4-5 points on long fights, Ferocious Bite at
  4-5 points or to finish, Shifting Power (new: mana into 40 energy) when energy is low.
  Tiger's Fury is gone. Bear for 2+ mobs: Maul, Swipe, Demoralizing Roar, Enrage.
  Caster / Moonkin: Moonfire and Insect Swarm up, Starfire on elites, Wrath filler.
  Mark of the Wild / Thorns up; heal yourself in caster form when low. ]]

local function up(s) return ns.DebuffUp(ns.N(s)) end
local function inForm(s) local f = ns.Form(); return f and f == ns.N(s) end

local function cat()
    local cp = ns.ComboPoints()
    local lives = ns.Lives(35, 9)
    local tough = ns.TargetIsTough()
    local dying = ns.Dying(25, 4)
    local stealthed = IsStealthed and ns.flag(ns.safe(IsStealthed))
    if stealthed then
        return first(
            function() return R(RAVAGE, true) end,
            function() if tough then return R(POUNCE, true) end end,
            function() return R(CLAW, true) end
        )
    end
    return first(
        function() if ns.TargetCasting() then return R(BASH, true) end end,
        function() if lives and not up(FF_FERAL) and not up(FAERIE_FIRE) then return R(FF_FERAL, true) end end,
        function() if cp >= 4 and ns.Lives(60, 12) and ns.CanBleed() and not up(RIP) then return R(RIP, true) end end,
        -- Clearcasting: a free Shred first, the Bite waits a second
        function() if ns.Proc(SHRED) then return R(SHRED, true) end end,
        function() if cp >= 4 or (cp >= 2 and dying) then return R(BITE, true) end end,
        function() if lives and ns.CanBleed() and not up(RAKE) then return R(RAKE, true) end end,
        function() if ns.NoResource(CLAW) then return R("Shifting Power") end end,
        function() return R("Mangle (Cat)", true) end,
        function() return R(CLAW, true) end
    )
end

local function bear()
    local enemies = ns.EnemyCount()
    return first(
        function() if ns.TargetCasting() then return R(BASH, true) end end,
        function() return R(ENRAGE) end,
        function() if not up(DEMO_ROAR) and (enemies >= 2 or ns.TargetIsTough()) then return R(DEMO_ROAR) end end,
        function() if not up(FF_FERAL) and not up(FAERIE_FIRE) then return R(FF_FERAL, true) end end,
        function() if enemies >= 2 then return R(SWIPE, true) end end,
        function() return R("Mangle (Bear)", true) end,
        function() return R("Primal Bite", true) end,
        function() if ns.Lives(35, 8) and not ns.DebuffUp("Lacerate") then return R("Lacerate", true) end end,
        function() return R(MAUL, true) end,
        function() return R("Lacerate", true) end
    )
end

local function caster()
    local lives = ns.Lives(35, 8)
    local tough = ns.TargetIsTough()
    local enemies = ns.EnemyCount()
    return first(
        function() if ns.ManaShort(20, WRATH) then return R("Innervate") end end,
        function() if ns.LowHealth() then return R(REGROWTH) end end,
        function() if ns.LowHealth() then return R(HEALING_TOUCH) end end,
        function() if ns.LowHealth(60) and ns.RecentCasts(ns.N(REJUV) or "", 12) == 0 then return R(REJUV) end end,
        function() if enemies >= 3 then return R(HURRICANE) end end,
        function() if lives and not up(MOONFIRE) then return R(MOONFIRE, true) end end,
        function() if lives and not up(INSECT_SWARM) then return R(INSECT_SWARM, true) end end,
        function() if ns.Proc(STARFIRE) then return R(STARFIRE, true) end end,
        function() if ns.Proc(WRATH) then return R(WRATH, true) end end,
        function() if tough or inForm(MOONKIN) then return R(STARFIRE, true) end end,
        function() return R(WRATH, true) end
    )
end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local form = ns.Form()
    local inCaster = form == "" or (form and form == ns.N(MOONKIN))
    if not fighting and inCaster then
        local r = first(
            function() if ns.BuffMissing(MOTW) then return R(MOTW) end end,
            function() if ns.BuffMissing(THORNS) then return R(THORNS) end end
        )
        if r then return r end
    end
    if form and form == ns.N(CAT) then return cat() end
    if form and (form == ns.N(BEAR) or form == "Dire Bear Form") then return bear() end
    if inCaster then return caster() end
end

function ns.InitClass()
    local n, d = ns.N, ns.durations
    ns.selfBuffs[n(MOTW) or "Mark of the Wild"] = 1800
    ns.selfBuffs[n(THORNS) or "Thorns"] = 600
    for _, s in ipairs({ CLAW, RAKE, SHRED, RAVAGE, "Mangle (Cat)" }) do
        if n(s) then ns.cpBuilders[n(s)] = 1 end
    end
    if n(POUNCE) then ns.cpBuilders[n(POUNCE)] = 1 end
    for _, s in ipairs({ RIP, BITE }) do
        if n(s) then ns.cpFinishers[n(s)] = true end
    end
    d[n(MOONFIRE) or "Moonfire"] = 12
    d[n(INSECT_SWARM) or "Insect Swarm"] = 12
    d[n(RAKE) or "Rake"] = 9
    d[n(RIP) or "Rip"] = 12
    d["Lacerate"] = 15
    d[n(FF_FERAL) or "Faerie Fire (Feral)"] = 40
    d[n(FAERIE_FIRE) or "Faerie Fire"] = 40
    d[n(DEMO_ROAR) or "Demoralizing Roar"] = 30
    ns.meleeProbes = { CLAW, MAUL, RAKE }
    ns.rangeProbes = { WRATH, MOONFIRE }
    ns.zoneText = { shoot = "In range" }
    ns.traceSpells = { WRATH, MOONFIRE, CLAW, RAKE, BITE, MAUL }
    ns.rotation = rotation
end
