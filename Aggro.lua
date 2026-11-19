local ADDON, ns = ...

---------------------------------------------------------------------------
-- Aggro log: a data set for a future aggro-range indicator.
-- While a mob is out of combat we keep estimating how far it is (a range bracket from
-- spells and items with a known range). When it turns on you by itself we save mob level,
-- your level, elite or not and the distance just before. Mobs you (or your pet) hit in the
-- last seconds are left out. A mob that came close and never aggroed is saved too
-- (its closest distance): that is the lower bound of the radius.
---------------------------------------------------------------------------
local GetTime, pairs, ipairs = GetTime, pairs, ipairs
local MAX_ENTRIES = 1000
local PULL_WINDOW = 6   -- seconds after you hit a mob that its aggro counts as your pull
local TICK = 0.2
local NEAR = 45         -- only "came close, no aggro" within this many yards is worth saving
local VERSION = 2       -- entries from older logger builds are dropped (v1 kept duplicates, missed group flags)
local GONE = 30         -- a nameplate that blinks out and back is the same sighting

-- classic items with a known range that answer IsItemInRange (as LibRangeCheck uses them)
-- (items the client does not know just answer nil and are skipped)
local RANGE_ITEMS = {
    { 5, 8149 },   -- Voodoo Charm
    { 8, 34368 },  -- Attuned Crystal Cores
    { 10, 32321 }, -- Sparrowhawk Net
    { 15, 33069 }, -- Sturdy Rope
    { 20, 10645 }, -- Gnomish Death Ray
    { 25, 24268 }, -- Netherweave Net
    { 30, 835 },   -- Large Rope Net
    { 35, 18904 }, -- Zorbin's Ultra-Shrinker
    { 40, 28767 }, -- The Decapitator
    { 45, 23836 }, -- Goblin Rocket Launcher
}

local probes -- sorted by range: { range, spell = id } / { range, item = id } / { range, interact = n }
local function buildProbes()
    probes = {}
    local seen = {}
    local function add(p)
        if p.range and p.range > 0 and not seen[p.range] then
            seen[p.range] = true
            probes[#probes + 1] = p
        end
    end
    for _, id in pairs(ns.known) do
        local info = C_Spell.GetSpellInfo and ns.safe(C_Spell.GetSpellInfo, id)
        local harmful = C_Spell.IsSpellHarmful and ns.flag(ns.safe(C_Spell.IsSpellHarmful, id))
        -- spells with a minimum range (Auto Shot) say "out of range" when too close: no use here
        if type(info) == "table" and harmful and (info.minRange or 0) == 0 then
            add({ range = info.maxRange, spell = id })
        end
    end
    add({ range = 10, interact = 3 }) -- duel distance
    add({ range = 28, interact = 4 }) -- follow distance
    for _, it in ipairs(RANGE_ITEMS) do
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it[2]) end
        add({ range = it[1], item = it[2] })
    end
    table.sort(probes, function(a, b) return a.range < b.range end)
end

local function inRange(p, unit)
    if p.spell then return ns.InRange(p.spell, unit) end
    if p.interact then return ns.flag(ns.safe(CheckInteractDistance, unit, p.interact)) end
    if p.item and C_Item.IsItemInRange then return ns.flag(ns.safe(C_Item.IsItemInRange, p.item, unit)) end
end

-- distance bracket: farther than lo, at most hi (nil = unknown side)
local function bracket(unit)
    local lo, hi
    for _, p in ipairs(probes) do
        local r = inRange(p, unit)
        if r == true then
            if not hi or p.range < hi then hi = p.range end
        elseif r == false then
            if not lo or p.range > lo then lo = p.range end
        end
    end
    if lo and hi and lo >= hi then return nil end -- probes disagree (bad data)
    return lo, hi
end

local function guidOf(unit)
    local g = ns.safe(UnitGUID, unit)
    if g and not ns.isSecret(g) then return g end
end

local function npcID(guid)
    local id = guid and select(6, strsplit("-", guid))
    return tonumber(id)
end

local function num(v) return ns.num(v) end

---------------------------------------------------------------------------
local plates = {}  -- [unit] = guid
local mobs = {}    -- [guid] = { lo, hi, t, closeLo, closeHi, closeBusy, closeGroup, aggro, engaged, gone, info }
local hit = {}     -- [guid] = last time you (or your pet) attacked it

local function markHit(unit)
    local g = guidOf(unit)
    if g then hit[g] = GetTime() end
end

local function pulledByMe(guid, unit)
    local t = hit[guid]
    if t and GetTime() - t <= PULL_WINDOW then return true end
    if ns.flag(ns.safe(UnitIsUnit, "pettarget", unit)) then return true end
    if ns.flag(ns.safe(UnitIsUnit, unit .. "target", "pet")) then return true end
    return false
end

-- the mob has turned on you: in its threat list, or targeting you while in combat
local function aggroed(unit)
    local threat = num(ns.safe(UnitThreatSituation, "player", unit))
    if threat ~= nil then return true end
    local onMe = ns.flag(ns.safe(UnitIsUnit, unit .. "target", "player"))
    local fighting = ns.flag(ns.safe(UnitAffectingCombat, unit))
    return onMe == true and fighting == true
end

local function describe(unit, guid)
    local cls = ns.safe(UnitClassification, unit)
    local ctype = ns.safe(UnitCreatureType, unit)
    local name = ns.safe(UnitName, unit)
    return {
        npc = npcID(guid),
        name = (name and not ns.isSecret(name)) and name or nil,
        mobLevel = num(ns.safe(UnitLevel, unit)),
        class = (cls and not ns.isSecret(cls)) and cls or nil,
        type = (ctype and not ns.isSecret(ctype)) and ctype or nil,
    }
end

local function save(kind, m, extra)
    local db = ns.db
    if not db or not db.aggroLog then return end
    local log = db.aggroData or {}
    db.aggroData = log
    local e = {
        v = VERSION,
        kind = kind, -- "aggro" or "near" (came close, no aggro)
        npc = m.info.npc, name = m.info.name, mob = m.info.mobLevel, me = num(UnitLevel("player")),
        class = m.info.class, type = m.info.type,
        map = C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit, "player"),
        time = time(),
    }
    for k, v in pairs(extra) do e[k] = v end
    log[#log + 1] = e
    while #log > MAX_ENTRIES do table.remove(log, 1) end
end

local function forget(guid)
    local m = mobs[guid]
    if not m then return end
    -- came within reach and never turned on you (nor fought anyone else): the radius is smaller
    if not m.aggro and not m.engaged and m.closeHi and m.closeHi <= NEAR and m.info then
        save("near", m, { lo = m.closeLo, hi = m.closeHi, busy = m.closeBusy, group = m.closeGroup })
    end
    mobs[guid] = nil
end

local elapsed = 0
local function tick(_, e)
    elapsed = elapsed + e
    if elapsed < TICK then return end
    elapsed = 0
    if not ns.db or not ns.db.aggroLog or not probes then return end
    local now = GetTime()
    local busy = ns.flag(UnitAffectingCombat("player")) == true -- already fighting: links, adds
    local group = IsInGroup and IsInGroup() or false
    for unit, guid in pairs(plates) do
        local m = mobs[guid]
        if m and not m.aggro then
            local dead = ns.flag(ns.safe(UnitIsDead, unit))
            if dead then
                forget(guid)
            elseif aggroed(unit) then
                m.aggro = true
                if not pulledByMe(guid, unit) then
                    -- the bracket from the tick before (this one may already be in combat)
                    save("aggro", m, {
                        lo = m.lo, hi = m.hi, age = m.t and math.floor((now - m.t) * 10 + 0.5) / 10,
                        busy = busy or nil, group = group or nil,
                        moving = (num(ns.safe(GetUnitSpeed, "player")) or 0) > 0 or nil,
                        stealth = IsStealthed and ns.flag(ns.safe(IsStealthed)) or nil,
                    })
                end
            else
                local fighting = ns.flag(ns.safe(UnitAffectingCombat, unit))
                if fighting == true then
                    m.engaged = true -- pulled by someone else: neither "aggro" nor "near"
                elseif fighting == false and not m.engaged then
                    local lo, hi = bracket(unit)
                    if lo or hi then
                        m.lo, m.hi, m.t = lo, hi, now
                        if hi and (not m.closeHi or hi < m.closeHi) then
                            m.closeLo, m.closeHi = lo, hi
                            m.closeBusy, m.closeGroup = busy or nil, group or nil
                        end
                    end
                end
            end
        end
    end
    for g, m in pairs(mobs) do
        if m.gone and now - m.gone > GONE then forget(g) end
    end
    for g, t in pairs(hit) do
        if now - t > 60 then hit[g] = nil end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local guid = guidOf(unit)
        if not guid or not guid:find("^Creature") then return end
        if ns.flag(ns.safe(UnitCanAttack, "player", unit)) ~= true then return end
        if ns.flag(ns.safe(UnitIsDead, unit)) then return end
        local reaction = num(ns.safe(UnitReaction, unit, "player"))
        if reaction and reaction > 2 then return end -- neutral mobs never aggro on their own
        plates[unit] = guid
        if mobs[guid] then
            mobs[guid].gone = nil
        else
            mobs[guid] = { info = describe(unit, guid), aggro = ns.flag(ns.safe(UnitAffectingCombat, unit)) == true }
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local guid = plates[unit]
        plates[unit] = nil
        if guid and mobs[guid] then mobs[guid].gone = GetTime() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "PLAYER_ENTER_COMBAT" then
        -- your attacks (harmful casts, auto attack) count as a pull of your target
        local harmful = event == "PLAYER_ENTER_COMBAT"
            or (C_Spell.IsSpellHarmful and ns.flag(ns.safe(C_Spell.IsSpellHarmful, spellID)))
        if harmful and UnitExists("target") then markHit("target") end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_LOGIN" then
        buildProbes()
        local log = ns.db and ns.db.aggroData
        if event == "PLAYER_LOGIN" and log then
            for i = #log, 1, -1 do
                if log[i].v ~= VERSION then table.remove(log, i) end
            end
        end
    end
end)
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTER_COMBAT")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
frame:SetScript("OnUpdate", tick)

---------------------------------------------------------------------------
-- /frot aggro: what the data says so far (by level difference, mob minus you)
---------------------------------------------------------------------------
function ns.AggroStats()
    local log = ns.db and ns.db.aggroData or {}
    local by = {}
    for _, e in ipairs(log) do
        if e.mob and e.me and e.mob > 0 and not e.busy and not e.group then
            local d = e.mob - e.me
            local b = by[d] or { aggro = 0, near = 0, maxLo = nil, minNear = nil }
            by[d] = b
            if e.kind == "aggro" then
                b.aggro = b.aggro + 1
                if e.lo and (not b.maxLo or e.lo > b.maxLo) then b.maxLo = e.lo end
            elseif e.hi then
                b.near = b.near + 1
                if not b.minNear or e.hi < b.minNear then b.minNear = e.hi end
            end
        end
    end
    local diffs = {}
    for d in pairs(by) do diffs[#diffs + 1] = d end
    table.sort(diffs)
    ns.Print(("aggro log: %d entries (solo, not fighting already)"):format(#log))
    for _, d in ipairs(diffs) do
        local b = by[d]
        ns.Print(("mob %+d lvl: %d aggro (farthest seen > %s yd), %d close without aggro (closest <= %s yd)"):format(
            d, b.aggro, b.maxLo and tostring(b.maxLo) or "?", b.near, b.minNear and tostring(b.minNear) or "?"))
    end
end
