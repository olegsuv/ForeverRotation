local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

local SERPENT_STING, HUNTERS_MARK, ARCANE_SHOT, MULTI_SHOT = 1978, 1130, 3044, 2643
local AIMED_SHOT, RAPID_FIRE, RAPTOR_STRIKE, MONGOOSE_BITE = 19434, 3045, 2973, 1495
local WING_CLIP, CONCUSSIVE_SHOT, AUTO_SHOT = 2974, 5116, 75
local DISENGAGE, IMMOLATION_TRAP, EXPLOSIVE_TRAP = 781, 13795, 13813
local SUMMON_HAWK, SNIPER_SHOT = 1293241, 1310687
local VOLLEY, BESTIAL_WRATH, INTIMIDATION = 1510, 19574, 19577
local ASPECT_HAWK, ASPECT_MONKEY, ASPECT_CHEETAH, ASPECT_PACK, ASPECT_BEAST, ASPECT_WILD = 13165, 13163, 5118, 13159, 13161, 20043

-- Serpent Sting does nothing to these (enUS / ruRU creature types)
local NO_STING = { ["Mechanical"] = true, ["Механизм"] = true }

local function stingWorthIt()
    local ctype = ns.safe(UnitCreatureType, "target")
    if ctype and not ns.isSecret(ctype) and NO_STING[ctype] then return false end
    return ns.Lives(30, 8) -- dies before it ticks
end

local function name(id) return C_Spell.GetSpellName(id) end

local function dps(baseID, targets)
    local _, id = ns.Spell(baseID)
    return id and ns.DPS(id, targets) or 0
end

local function petAlive()
    if not UnitExists("pet") then return false end
    return ns.flag(ns.safe(UnitIsDead, "pet")) ~= true
end

-- nothing to shoot: no ranged weapon, or a bow / gun with the ammo slot empty (thrown needs none)
local RANGED_SLOT, AMMO_SLOT = 18, 0
local function noAmmo()
    local ranged = ns.safe(GetInventoryItemID, "player", RANGED_SLOT)
    if not ranged then return true end
    local _, _, _, loc = ns.safe(C_Item.GetItemInfoInstant, ranged)
    if loc == "INVTYPE_THROWN" then return false end
    local ammo = ns.safe(GetInventoryItemID, "player", AMMO_SLOT)
    local count = ns.num(ns.safe(GetInventoryItemCount, "player", AMMO_SLOT))
    return not ammo or count == 0
end

-- Survival-style melee weaving: Strider Kick / Lacerate learned or Aspect of the Beast on
local function meleeSpec()
    if ns.known["Strider Kick"] or ns.known["Lacerate"] then return true end
    local beast = name(ASPECT_BEAST)
    return beast and ns.known[beast] and ns.PlayerBuff(beast) or false
end

local first = ns.first

--[[ Priority, from the Forever leveling and spec guides (Maxroll, Mobalytics, Method, Icy Veins, 11/2026):
  Opener: Hunter's Mark (not on mobs that die fast), pet in, Serpent Sting (same), Aimed Shot (baseline
  at 20, hardest hit; shares its 6 s cooldown with Multi-Shot), Summon Hawk (keep 2 out; shares its
  cooldown with Arcane Shot), Arcane Shot when 2 hawks are out, mana is low or the mob dies fast.
  2+ enemies: Multi-Shot instead of Aimed Shot; big packs: Volley (40, no cooldown).
  Melee (Survival weave): Mongoose Bite when lit, Raptor Strike (no global cooldown), Strider Kick,
  Lacerate when not ticking, Immolation Trap on a mob that lives 15 s (traps work in combat, 30 s shared).
  Melee for ranged specs: hand the mob to the pet (Disengage), trap, Raptor, Wing Clip and step back.
  Out of ammo: Aspect of the Monkey (dodge) and the melee strikes, no shots, no stepping back. ]]
local function rotation()
    local mana = ns.Percent("player", Enum.PowerType.Mana)
    local fighting = ns.flag(UnitAffectingCombat("player"))
    local p = ns.PotionCheck(true, { ARCANE_SHOT, SERPENT_STING }); if p then return p end

    local zone = ns.Zone()
    local tough = ns.TargetIsTough()
    local lives = ns.Lives(50, 10) -- worth a DoT / mark / hawk
    local melee = meleeSpec()
    local onMe = ns.TargetOnMe()
    local dry = noAmmo()

    -- aspect: Monkey with nothing to shoot, Beast for melee weaving, Hawk for shooting
    if dry then
        local monkey = name(ASPECT_MONKEY)
        if monkey and ns.known[monkey] and not ns.PlayerBuff(monkey) then
            local ok, id = ns.Ready(ASPECT_MONKEY); if ok then return id end
        end
    elseif melee then
        local beast = name(ASPECT_BEAST)
        if beast and ns.known[beast] and not ns.PlayerBuff(beast) then
            local ok, id = ns.Ready(ASPECT_BEAST); if ok then return id end
        end
    else
        local hawk = name(ASPECT_HAWK)
        local falcon = "Aspect of the Falcon" -- Hawk's attack power for melee too, counts as fine
        if hawk and ns.known[hawk] and not ns.PlayerBuff(hawk) and not (ns.known[falcon] and ns.PlayerBuff(falcon)) then
            local ok, id = ns.Ready(ASPECT_HAWK); if ok then return id end
        end
    end

    -- ===== out of ammo: fight in melee (the arrow says "step closer" until you are there) =====
    -- no Hunter's Mark: it only adds ranged attack power
    if dry then
        local lacerate = "Lacerate"
        if zone ~= "melee" then return nil end
        return first(
            function() return ns.Ready(MONGOOSE_BITE) end,
            function() return ns.Ready(RAPTOR_STRIKE) end,
            function() return ns.ReadyName("Strider Kick", true) end,
            function() if ns.known[lacerate] and lives and not ns.DebuffUp(lacerate) then return ns.ReadyName(lacerate, true) end end,
            function() if lives then return ns.Ready(IMMOLATION_TRAP) end end,
            function() if lives then return ns.Ready(EXPLOSIVE_TRAP) end end,
            function() return ns.ReadyName("Counterattack", true) end,
            function() if ns.flag(ns.safe(UnitIsPlayer, "target")) and not ns.DebuffUp(name(WING_CLIP)) then return ns.Ready(WING_CLIP) end end
        )
    end

    -- ===== melee range =====
    if zone == "melee" then
        local lacerate = "Lacerate"
        return first(
            function() return ns.Ready(MONGOOSE_BITE) end,
            function() return ns.Ready(RAPTOR_STRIKE) end, -- replaces the next swing, no global cooldown
            function() return ns.ReadyName("Strider Kick", true) end,
            function() if ns.known[lacerate] and lives and not ns.DebuffUp(lacerate) then return ns.ReadyName(lacerate, true) end end,
            function() if not melee and onMe == true and petAlive() then return ns.Ready(DISENGAGE) end end,
            function() if lives then return ns.Ready(EXPLOSIVE_TRAP) end end,
            function() if lives then return ns.Ready(IMMOLATION_TRAP) end end,
            function() if not melee and onMe ~= false then return ns.Ready(WING_CLIP) end end,
            function() return ns.ReadyName("Counterattack", true) end
        )
    end

    local manaOk = mana == nil or mana >= 30
    local enemies = ns.EnemyCount(MULTI_SHOT)

    -- ===== shooting range =====
    local okAimed, aimedID = ns.Ready(AIMED_SHOT, true)
    local okMulti, multiID = ns.Ready(MULTI_SHOT, true)
    local hawks = ns.RecentCasts(name(SUMMON_HAWK) or "Summon Hawk", 18)

    return first(
        -- the mob runs at you (not the pet): slow it before it reaches you
        function() if onMe == true and zone == "shoot" then return ns.Ready(CONCUSSIVE_SHOT, true) end end,
        -- packs
        function() if enemies >= 3 then return ns.Ready(VOLLEY, true) end end,
        function() if enemies >= 2 then return okMulti, multiID end end,
        -- marks and DoTs on mobs that will live
        function() if lives and not ns.DebuffUp(name(HUNTERS_MARK)) then return ns.Ready(HUNTERS_MARK, true) end end,
        function() if manaOk and stingWorthIt() and lives and not ns.DebuffUp(name(SERPENT_STING)) then return ns.Ready(SERPENT_STING, true) end end,
        -- cooldowns on elites and players
        function() if tough then return ns.Ready(BESTIAL_WRATH) end end,
        function() if tough then return ns.Ready(INTIMIDATION, true) end end,
        function() if tough or enemies >= 2 then return ns.Ready(RAPID_FIRE) end end,
        -- dying mob: an instant Arcane Shot, not a 2 s cast
        function() if not lives then return ns.Ready(ARCANE_SHOT, true) end end,
        -- Aimed Shot: hardest hit (Multi-Shot instead when it hits more)
        function() if okAimed and (not okMulti or dps(AIMED_SHOT, 1) >= dps(MULTI_SHOT, enemies)) then return okAimed, aimedID end end,
        function() if tough then return ns.Ready(SNIPER_SHOT, true) end end,
        -- Summon Hawk (keep 2 out on mobs that live) or Arcane Shot (same cooldown)
        function() if hawks < 2 and lives and manaOk then return ns.Ready(SUMMON_HAWK, true) end end,
        function() if manaOk or not lives then return ns.Ready(ARCANE_SHOT, true) end end,
        -- Multi-Shot as a filler only on your own pack: it hits the next party's mob too
        function() if manaOk and enemies >= 2 then return okMulti, multiID end end,
        -- nothing to cast and Auto Shot not running: start it (its button's weapon icon)
        function()
            if zone ~= "shoot" then return end
            local n, id = ns.Spell(AUTO_SHOT)
            if not id then return end
            if C_Spell.IsCurrentSpell and ns.flag(ns.safe(C_Spell.IsCurrentSpell, id)) then return end
            if ns.ButtonActive(n) then return end
            return true, id
        end
    )
end

-- hunter-only trace fields, after the generic state
function ns.TraceExtra()
    local out = {}
    out[#out + 1] = "near=" .. tostring(ns.flag(ns.safe(CheckInteractDistance, "target", 3)))
    local _, wc = ns.Spell(WING_CLIP)
    out[#out + 1] = "wing=" .. tostring(wc and ns.InRange(wc))
    out[#out + 1] = "stingUp=" .. tostring(ns.DebuffUp(name(SERPENT_STING)))
    out[#out + 1] = "hawkUp=" .. tostring(ns.PlayerBuff(name(ASPECT_HAWK)))
    return table.concat(out, " ")
end

-- Where the target is for a hunter: melee (~5 yd), dead zone (5-8 yd, no shots),
-- shoot (8-35 yd) or too far. nil when unknown or no hostile target.
local function firstAnswer(list)
    for _, b in ipairs(list) do
        local _, id = ns.Spell(b)
        if id then
            local r = ns.InRange(id)
            if r ~= nil then return r end
        end
    end
    return nil
end

local function rangeZone()
    if not ns.HostileTarget() then return nil end
    local melee = firstAnswer({ WING_CLIP, MONGOOSE_BITE })
    local near = ns.flag(ns.safe(CheckInteractDistance, "target", 3)) -- about 10 yd
    if melee == nil and near == false then melee = false end
    if melee == true then return "melee" end
    local shoot = firstAnswer({ ARCANE_SHOT, SERPENT_STING, CONCUSSIVE_SHOT })
    if shoot == nil then shoot = ns.InRange(AUTO_SHOT) end
    if shoot == true then return "shoot" end
    if near == true then
        -- inside 10 yd but no shot: dead zone, or melee when we had no melee probe
        if melee == nil then return "melee" end -- no melee probe learned yet: close enough to hit
        return "dead"
    end
    if shoot == false then return "far" end
    return nil
end

-- out of ammo the only place to fight is melee: anything farther is "too far"
function ns.RangeZone()
    local z = rangeZone()
    if z and z ~= "melee" and noAmmo() then return "far" end
    return z
end

function ns.InitClass()
    ns.durations["Lacerate"] = ns.durations["Lacerate"] or 21
    for _, id in ipairs({ ASPECT_HAWK, ASPECT_MONKEY, ASPECT_CHEETAH, ASPECT_PACK, ASPECT_BEAST, ASPECT_WILD }) do
        local n = name(id)
        if n then ns.exclusiveBuffs[n] = true end
    end
    ns.exclusiveBuffs["Aspect of the Falcon"] = true
    local mark = name(HUNTERS_MARK)
    if mark then ns.durations[mark] = 120 end
    local sting = name(SERPENT_STING)
    if sting then ns.durations[sting] = 15 end
    ns.zoneUseful = true
    ns.aoeRange = MULTI_SHOT -- enemies counted within shooting range
    ns.traceSpells = { HUNTERS_MARK, SERPENT_STING, ARCANE_SHOT, MULTI_SHOT, AIMED_SHOT, RAPTOR_STRIKE }
    ns.idleSpell = AUTO_SHOT
    ns.rotation = rotation
end
