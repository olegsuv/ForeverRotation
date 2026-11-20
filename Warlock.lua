local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "WARLOCK" then return end

local R, first = ns.R, ns.first

local SHADOW_BOLT, IMMOLATE, CORRUPTION, AGONY, WEAKNESS, DOOM = 686, 348, 172, 980, 702, 603
local LIFE_TAP, DRAIN_LIFE, DRAIN_SOUL, SIPHON_LIFE, SHADOWBURN = 1454, 689, 1120, 18265, 17877
local CONFLAGRATE, SEARING_PAIN, HELLFIRE, RAIN_OF_FIRE, DEATH_COIL = 17962, 5676, 1949, 5740, 6789
local DEMON_SKIN, DEMON_ARMOR, SOUL_FIRE, AMPLIFY = 687, 706, 6353, 18288
local ELEMENTS, TONGUES, EXHAUSTION = 1490, 1714, 18223

--[[ Priority, from the Forever warlock guides (Maxroll, Mobalytics, Wowhead, Icy Veins, 11/2026):
  Curses are Banes in Forever (Bane of Agony / Doom / Havoc) plus one utility Curse, and DoTs crit.
  Affliction: Bane of Agony + Corruption (+ Siphon Life at 31), Wrack (channel, 40) once the DoTs
  tick, Drain Life as the filler that keeps you topped up, Shadow Bolt on Shadow Trance.
  Destruction: Immolate first, Conflagrate (25) while it burns, Shadowburn under 20 % with a shard,
  Incinerate (40) / Shadow Bolt as the main nuke. Life Tap when mana is low and health is fine,
  Death Coil when a mob is on you and you're low, Drain Soul on a dying mob for a shard. ]]

local function spec()
    if ns.Known(CONFLAGRATE) or ns.Known(SHADOWBURN) or ns.Known("Incinerate") then return "destro" end
    if ns.Known(SIPHON_LIFE) or ns.Known(AMPLIFY) or ns.Known("Wrack") then return "affli" end
    return "any"
end

local function bane()
    -- Forever renames Curse of Agony to Bane of Agony: same spell, the game gives the name
    if ns.Known(AGONY) then return AGONY end
    if ns.Known("Bane of Agony") then return "Bane of Agony" end
end

local function up(s) return ns.DebuffUp(ns.N(s)) end

-- Doom is renamed Bane of Doom too: by id, or by the Forever name
local function doom()
    if ns.Known(DOOM) then return DOOM end
    if ns.Known("Bane of Doom") then return "Bane of Doom" end
end

-- one Bane and one Curse of yours fit on a target: is any of them on it already?
local BANES = { AGONY, DOOM, "Bane of Agony", "Bane of Doom", "Bane of Havoc" }
local CURSES = { ELEMENTS, WEAKNESS, TONGUES, EXHAUSTION, "Curse of the Elements", "Curse of Weakness",
                 "Curse of Tongues", "Curse of Exhaustion", "Curse of Recklessness" }
local function anyUp(list)
    for _, s in ipairs(list) do
        if ns.Known(s) and up(s) then return true end
    end
    return false
end

-- the curse worth a global cooldown, on elites, rares and players only: the Elements (more
-- damage from all your spells), else Weakness when it is hitting you
local function curse(onMe)
    if ns.Known(ELEMENTS) then return ELEMENTS end
    if ns.Known("Curse of the Elements") then return "Curse of the Elements" end
    if onMe ~= false then
        if ns.Known(WEAKNESS) then return WEAKNESS end
        if ns.Known("Curse of Weakness") then return "Curse of Weakness" end
    end
end

local function rotation()
    local p = ns.PotionCheck(true); if p then return p end
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local s = spec()
    local lives = ns.Lives(35)
    local tough = ns.TargetIsTough()
    local enemies = ns.EnemyCount()
    local onMe = ns.TargetOnMe()
    local hp = ns.Percent("target")
    local myHp = ns.Percent("player")
    local lowMana = ns.ManaShort(25, SHADOW_BOLT)
    local agony = bane()
    -- Doom (one big tick a minute) only on a tough mob near full health: it lives that long
    local myBane = agony
    if tough and (hp == nil or hp >= 80) and doom() then myBane = doom() end
    local myCurse = tough and curse(onMe) or nil

    if not fighting then
        local armor = ns.Known(DEMON_ARMOR) and DEMON_ARMOR or DEMON_SKIN
        local anyArmor = ns.SelfBuff(DEMON_SKIN) or ns.SelfBuff(DEMON_ARMOR) or ns.SelfBuff("Fel Armor")
        if ns.Known(armor) and anyArmor == false then
            local ok, id = R(armor); if ok then return id end
        end
        if lowMana and (myHp == nil or myHp > 50) then
            local ok, id = R(LIFE_TAP); if ok then return id end
        end
    end

    return first(
        function() if onMe == true and ns.LowHealth(35) then return R(DEATH_COIL, true) end end,
        function() if lowMana and (myHp == nil or myHp > 60) then return R(LIFE_TAP) end end,
        function() if ns.LowHealth(40) then return R(DRAIN_LIFE, true) end end,
        -- packs
        function() if enemies >= 3 and ns.flag(ns.safe(CheckInteractDistance, "target", 3)) and not ns.LowHealth(60) then return R(HELLFIRE) end end,
        function() if enemies >= 3 then return R(RAIN_OF_FIRE) end end,
        -- execute / procs
        function() if hp and hp < 20 then return R(SHADOWBURN, true) end end,
        function() if ns.Proc(SHADOW_BOLT) then return R(SHADOW_BOLT, true) end end,
        function() if up(IMMOLATE) then return R(CONFLAGRATE, true) end end,
        -- DoTs on mobs that live
        function() if lives and s == "destro" and not up(IMMOLATE) then return R(IMMOLATE, true) end end,
        function() if lives and myBane and not anyUp(BANES) then return R(myBane, true) end end,
        function() if tough and myCurse and not anyUp(CURSES) then return R(myCurse, true) end end,
        function() if lives and not up(CORRUPTION) then return R(CORRUPTION, true) end end,
        function() if lives and not up(SIPHON_LIFE) then return R(SIPHON_LIFE, true) end end,
        function() if lives and s ~= "affli" and not up(IMMOLATE) then return R(IMMOLATE, true) end end,
        function() if lives and up(CORRUPTION) then return R("Wrack", true) end end,
        -- dying mob: grab a shard
        function() if hp and hp < 20 and not tough and (ns.num(ns.safe(C_Item.GetItemCount, 6265)) or 0) < 5 then return R(DRAIN_SOUL, true) end end,
        function() if lowMana then return ns.Wand() end end,
        -- filler
        function() if s == "affli" and myHp and myHp < 80 then return R(DRAIN_LIFE, true) end end,
        function() if up(IMMOLATE) then return R("Incinerate", true) end end,
        function() return R(SHADOW_BOLT, true) end,
        function() return R(SEARING_PAIN, true) end,
        function() return ns.Wand() end
    )
end

function ns.InitClass()
    local n, d = ns.N, ns.durations
    for _, a in ipairs({ DEMON_SKIN, DEMON_ARMOR }) do
        if n(a) then ns.selfBuffs[n(a)] = 1800; ns.buffGroups[n(a)] = "armor" end
    end
    d[n(IMMOLATE) or "Immolate"] = 15
    d[n(CORRUPTION) or "Corruption"] = 18
    d[n(AGONY) or "Bane of Agony"] = 24
    d["Bane of Agony"] = 24
    d[n(DOOM) or "Bane of Doom"] = 60
    d["Bane of Doom"] = 60
    d[n(ELEMENTS) or "Curse of the Elements"] = 300
    d[n(WEAKNESS) or "Curse of Weakness"] = 120
    d[n(SIPHON_LIFE) or "Siphon Life"] = 30
    ns.rangeProbes = { SHADOW_BOLT, IMMOLATE, CORRUPTION }
    ns.zoneText = { shoot = "In range" }
    ns.traceSpells = { SHADOW_BOLT, IMMOLATE, CORRUPTION, AGONY, LIFE_TAP, DRAIN_LIFE }
    ns.rotation = rotation
end
