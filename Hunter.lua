local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

local SERPENT_STING, HUNTERS_MARK, ARCANE_SHOT, MULTI_SHOT = 1978, 1130, 3044, 2643
local AIMED_SHOT, RAPID_FIRE, RAPTOR_STRIKE, MONGOOSE_BITE = 19434, 3045, 2973, 1495
local WING_CLIP, CONCUSSIVE_SHOT, AUTO_SHOT = 2974, 5116, 75
local SUMMON_HAWK, SNIPER_SHOT = 1293241, 1310687
local ASPECT_HAWK, ASPECT_MONKEY, ASPECT_CHEETAH, ASPECT_PACK, ASPECT_BEAST, ASPECT_WILD = 13165, 13163, 5118, 13159, 13161, 20043

-- best first
local MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }
local HEAL_POTIONS = { 13446, 3928, 1710, 929, 858, 118 }

-- Serpent Sting does nothing to these (enUS / ruRU creature types)
local NO_STING = { ["Mechanical"] = true, ["Механизм"] = true }

local function stingWorthIt()
    local ctype = ns.safe(UnitCreatureType, "target")
    if ctype and not ns.isSecret(ctype) and NO_STING[ctype] then return false end
    local hp = ns.Percent("target")
    if hp and hp < 30 and not ns.TargetIsTough() then return false end -- dies before it ticks
    return true
end

local function name(id) return C_Spell.GetSpellName(id) end

local function dps(baseID, targets)
    local _, id = ns.Spell(baseID)
    return id and ns.DPS(id, targets) or 0
end

-- not enough mana for a basic shot (the game hides mana numbers in combat)
local function outOfMana()
    for _, b in ipairs({ ARCANE_SHOT, SERPENT_STING }) do
        local _, id = ns.Spell(b)
        if id then
            local _, noMana = ns.Usable(id)
            if noMana == true then return true end
        end
    end
    return false
end

local function rotation()
    local mana = ns.Percent("player", Enum.PowerType.Mana)

    -- potions first when it matters
    if ns.db.potions and ns.flag(UnitAffectingCombat("player")) then
        local hp = ns.Percent("player")
        if hp and hp < ns.db.potionHealth then
            local s = ns.ReadyItem(HEAL_POTIONS); if s then return s end
        end
        if (mana and mana < ns.db.potionMana) or (not mana and outOfMana()) then
            local s = ns.ReadyItem(MANA_POTIONS); if s then return s end
        end
    end

    -- too close to shoot: melee (Raptor Strike's own range answer is always "yes" in Forever,
    -- so the zone comes from Wing Clip / Mongoose Bite / interact distance)
    local zone = ns.RangeZone()
    if zone == "melee" then
        local ok, id = ns.Ready(MONGOOSE_BITE); if ok then return id end
        ok, id = ns.Ready(RAPTOR_STRIKE); if ok then return id end
        return nil
    end

    -- shooting without the damage aspect (Cheetah/Pack/Beast/none): switch to Hawk
    local hawk = name(ASPECT_HAWK)
    local falcon = "Aspect of the Falcon" -- Hawk's attack power for melee too, counts as fine
    if hawk and ns.known[hawk] and not ns.PlayerBuff(hawk) and not (ns.known[falcon] and ns.PlayerBuff(falcon)) then
        local ok, id = ns.Ready(ASPECT_HAWK); if ok then return id end
    end

    local manaOk = mana == nil or mana >= 30
    local enemies = ns.EnemyCount(MULTI_SHOT)

    -- 2+ enemies: Multi-Shot first
    if enemies >= 2 then
        local ok, id = ns.Ready(MULTI_SHOT, true); if ok then return id end
    end

    local hp = ns.Percent("target")
    local tough = ns.TargetIsTough()

    -- Hunter's Mark on targets that will live a while
    if not ns.DebuffUp(name(HUNTERS_MARK)) and (not hp or hp >= 50 or tough) then
        local ok, id = ns.Ready(HUNTERS_MARK, true); if ok then return id end
    end

    -- Serpent Sting
    if manaOk and stingWorthIt() and not ns.DebuffUp(name(SERPENT_STING)) then
        local ok, id = ns.Ready(SERPENT_STING, true); if ok then return id end
    end

    do local ok, id = ns.Ready(RAPID_FIRE); if ok and (tough or enemies >= 2) then return id end end

    -- Aimed Shot and Multi-Shot share a cooldown in Forever: take the bigger one
    local okAimed, aimedID = ns.Ready(AIMED_SHOT, true)
    local okMulti, multiID = ns.Ready(MULTI_SHOT, true)
    if okAimed and (not okMulti or dps(AIMED_SHOT, 1) >= dps(MULTI_SHOT, enemies)) then return aimedID end
    do local ok, id = ns.Ready(SNIPER_SHOT, true); if ok and tough then return id end end
    do local ok, id = ns.Ready(SUMMON_HAWK, true); if ok then return id end end
    if manaOk then
        local ok, id = ns.Ready(ARCANE_SHOT, true); if ok then return id end
        if okMulti then return multiID end
    end
    return nil -- just let Auto Shot work
end

-- compact state for the trace log: name known/usable/cooldown/range
function ns.TraceState()
    local out = {}
    local mana = ns.Percent("player", Enum.PowerType.Mana)
    out[#out + 1] = ("mana=%s"):format(mana and ("%d"):format(mana) or "?")
    out[#out + 1] = ("en=%d"):format(ns.EnemyCount(MULTI_SHOT))
    for _, b in ipairs({ HUNTERS_MARK, SERPENT_STING, ARCANE_SHOT, MULTI_SHOT, AIMED_SHOT, RAPTOR_STRIKE }) do
        local n, id = ns.Spell(b)
        if id then
            local u = ns.Usable(id)
            local info = ns.safe(C_Spell.GetSpellCooldown, id)
            local cdText = "?"
            if type(info) == "table" then
                if ns.isSecret(info.duration) or ns.isSecret(info.startTime) then cdText = "S"
                elseif ns.num(info.duration) then cdText = ("%.1f"):format(info.duration) end
            end
            local r = ns.InRange(id)
            out[#out + 1] = ("%s:%s/u%s/cd%s(%s)/r%s"):format(n:sub(1, 6), id, u and 1 or 0,
                ns.OnCooldown(id) and 1 or 0, cdText, r == nil and "?" or (r and 1 or 0))
        end
    end
    local sting = name(SERPENT_STING)
    out[#out + 1] = "zone=" .. tostring(ns.RangeZone())
    out[#out + 1] = "near=" .. tostring(ns.flag(ns.safe(CheckInteractDistance, "target", 3)))
    local _, wc = ns.Spell(WING_CLIP)
    out[#out + 1] = "wing=" .. tostring(wc and ns.InRange(wc))
    out[#out + 1] = "stingUp=" .. tostring(ns.DebuffUp(sting))
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

function ns.RangeZone()
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

function ns.InitClass()
    for _, id in ipairs({ ASPECT_HAWK, ASPECT_MONKEY, ASPECT_CHEETAH, ASPECT_PACK, ASPECT_BEAST, ASPECT_WILD }) do
        local n = name(id)
        if n then ns.exclusiveBuffs[n] = true end
    end
    ns.exclusiveBuffs["Aspect of the Falcon"] = true
    local mark = name(HUNTERS_MARK)
    if mark then ns.durations[mark] = 120 end
    local sting = name(SERPENT_STING)
    if sting then ns.durations[sting] = 15 end
    ns.rotation = rotation
end
