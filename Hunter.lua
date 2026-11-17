local ADDON, ns = ...

local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

local SERPENT_STING, HUNTERS_MARK, ARCANE_SHOT, MULTI_SHOT = 1978, 1130, 3044, 2643
local AIMED_SHOT, RAPID_FIRE, RAPTOR_STRIKE, MONGOOSE_BITE = 19434, 3045, 2973, 1495
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

local function rotation()
    local mana = ns.Percent("player", Enum.PowerType.Mana)

    -- potions first when it matters
    if ns.db.potions and ns.flag(UnitAffectingCombat("player")) then
        local hp = ns.Percent("player")
        if hp and hp < ns.db.potionHealth then
            local s = ns.ReadyItem(HEAL_POTIONS); if s then return s end
        end
        if mana and mana < ns.db.potionMana then
            local s = ns.ReadyItem(MANA_POTIONS); if s then return s end
        end
    end

    -- too close to shoot: melee
    local _, arcaneID = ns.Spell(ARCANE_SHOT)
    local _, raptorID = ns.Spell(RAPTOR_STRIKE)
    local shootRange = arcaneID and ns.InRange(arcaneID)
    if raptorID and ns.InRange(raptorID) == true and shootRange ~= true then
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
        local ok, id = ns.Ready(MULTI_SHOT); if ok then return id end
    end

    local hp = ns.Percent("target")
    local tough = ns.TargetIsTough()

    -- Hunter's Mark on targets that will live a while
    if not ns.DebuffUp(name(HUNTERS_MARK)) and (not hp or hp >= 50 or tough) then
        local ok, id = ns.Ready(HUNTERS_MARK); if ok then return id end
    end

    -- Serpent Sting
    if manaOk and stingWorthIt() and not ns.DebuffUp(name(SERPENT_STING)) then
        local ok, id = ns.Ready(SERPENT_STING); if ok then return id end
    end

    do local ok, id = ns.Ready(RAPID_FIRE); if ok and (tough or enemies >= 2) then return id end end

    -- Aimed Shot and Multi-Shot share a cooldown in Forever: take the bigger one
    local okAimed, aimedID = ns.Ready(AIMED_SHOT)
    local okMulti, multiID = ns.Ready(MULTI_SHOT)
    if okAimed and (not okMulti or dps(AIMED_SHOT, 1) >= dps(MULTI_SHOT, enemies)) then return aimedID end
    do local ok, id = ns.Ready(SNIPER_SHOT); if ok and tough then return id end end
    do local ok, id = ns.Ready(SUMMON_HAWK); if ok then return id end end
    if manaOk then
        local ok, id = ns.Ready(ARCANE_SHOT); if ok then return id end
        if okMulti then return multiID end
    end
    return nil -- just let Auto Shot work
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
