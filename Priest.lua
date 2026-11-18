local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "PRIEST" then return end

local R, first = ns.R, ns.first

local SMITE, SWP, MIND_BLAST, PWS, RENEW, LESSER_HEAL, HEAL, FLASH_HEAL = 585, 589, 8092, 17, 139, 2050, 2054, 2061
local INNER_FIRE, FORTITUDE, HOLY_FIRE, MIND_FLAY, VE, SHADOWFORM = 588, 1243, 14914, 15407, 15286, 15473
local DEVOURING, SCREAM, FADE = 2944, 8122, 586

--[[ Priority, from the Forever priest guides (Maxroll, Mobalytics, Wowhead, 11/2026), Shadow leveling:
  Power Word: Shield before the mob reaches you, Shadow Word: Pain, Mind Blast on cooldown,
  Devouring Plague (baseline in Forever) on mobs that live, Vampiric Embrace, Shadow Word: Death
  on cooldown / to finish, Mind Flay as the filler (Smite / Holy Fire before you have it),
  Shadowform at 40. Inner Fire and Fortitude up; heal yourself when low; wand when dry. ]]

local function up(s) return ns.DebuffUp(ns.N(s)) end
local function shieldedRecently() return ns.RecentCasts(ns.N(PWS) or "", 15) > 0 end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local lives = ns.Lives(35)
    local onMe = ns.TargetOnMe()
    local hp = ns.Percent("target")
    local enemies = ns.EnemyCount()
    local shadow = ns.Known(MIND_FLAY)
    local dry = ns.ManaShort(10, MIND_BLAST)

    if not fighting then
        local r = first(
            function() if ns.BuffMissing(INNER_FIRE) then return R(INNER_FIRE) end end,
            function() if ns.BuffMissing(FORTITUDE) then return R(FORTITUDE) end end,
            function() if ns.Known(SHADOWFORM) and ns.SelfBuff(SHADOWFORM) == false and ns.Form() == "" then return R(SHADOWFORM) end end
        )
        if r then return r end
    end

    return first(
        -- keep yourself alive
        function() if ns.LowHealth() and not shieldedRecently() then return R(PWS) end end,
        function() if ns.LowHealth(25) and enemies >= 2 then return R(SCREAM) end end,
        function() if ns.LowHealth() then return R(FLASH_HEAL) end end,
        function() if ns.LowHealth() then return R(HEAL) end end,
        function() if ns.LowHealth() then return R(LESSER_HEAL) end end,
        function() if ns.LowHealth(60) and ns.RecentCasts(ns.N(RENEW) or "", 15) == 0 then return R(RENEW) end end,
        -- the mob runs at you: shield first
        function() if onMe == true and lives and not shieldedRecently() then return R(PWS) end end,
        function() if ns.Known(SHADOWFORM) and ns.Form() == "" then return R(SHADOWFORM) end end,
        function() if hp and hp < 25 then return R("Shadow Word: Death", true) end end,
        function() if dry then return ns.Wand() end end,
        -- DoTs on mobs that live
        function() if lives and not up(VE) then return R(VE, true) end end,
        function() if lives and not up(SWP) then return R(SWP, true) end end,
        function() if lives and not up(DEVOURING) then return R(DEVOURING, true) end end,
        function() return R(MIND_BLAST, true) end,
        function() return R("Shadow Word: Death", true) end,
        function() if not shadow and lives and not up(HOLY_FIRE) then return R(HOLY_FIRE, true) end end,
        function() if shadow then return R(MIND_FLAY, true) end end,
        function() return R(SMITE, true) end,
        function() return ns.Wand() end
    )
end

function ns.InitClass()
    local n, d = ns.N, ns.durations
    ns.selfBuffs[n(INNER_FIRE) or "Inner Fire"] = 600
    ns.selfBuffs[n(FORTITUDE) or "Power Word: Fortitude"] = 1800
    d[n(SWP) or "Shadow Word: Pain"] = 18
    d[n(DEVOURING) or "Devouring Plague"] = 24
    d[n(VE) or "Vampiric Embrace"] = 60
    d[n(HOLY_FIRE) or "Holy Fire"] = 10
    ns.rangeProbes = { SMITE, SWP, MIND_BLAST }
    ns.zoneText = { shoot = "IN RANGE" }
    ns.traceSpells = { SWP, MIND_BLAST, MIND_FLAY, SMITE, PWS, DEVOURING }
    ns.rotation = rotation
end
