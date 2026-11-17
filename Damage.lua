local ADDON, ns = ...

-- Rough expected damage of one press, from the spell's own tooltip text plus
-- your current weapon damage, attack power and crit. Numbers are estimates:
-- no hit/armor/resist, crits counted as x2.

local GCD = ns.GCD
local pcall, tonumber = pcall, tonumber

local AUTO_SHOT = 75

-- Known Forever attack-power shares not shown in tooltips (spell name -> share of ranged AP).
-- Arcane Shot: 0.15 per Blizzard's 2 Nov 2026 notes. Extend when more is known.
local RAP_SHARE = {}
local function addShare(baseID, share)
    local n = C_Spell.GetSpellName(baseID)
    if n then RAP_SHARE[n] = share end
end

local function n(s)
    return s and tonumber((s:gsub(",", ""))) or nil
end

-- returns a "model" describing how the spell deals damage, or nil
local cache = {}
function ns.Model(spellID)
    if cache[spellID] ~= nil then return cache[spellID] or nil end
    local m = false
    if spellID == AUTO_SHOT then
        m = { kind = "auto" }
    else
        local desc = ns.safe(C_Spell.GetSpellDescription, spellID)
        if not desc or ns.isSecret(desc) or desc == "" then
            -- text not loaded yet: ask the client and try again later (do not cache)
            ns.safe(C_Spell.RequestLoadSpellData, spellID)
            return nil
        end
        do
            local d = desc:lower()
            local a, b, sec
            -- damage over time: "X to Y <school> damage over Z sec" / "X damage over Z sec"
            a, b, sec = d:match("(%d[%d,]*) to (%d[%d,]*) [%a ]-damage over (%d+) sec")
            if a then
                m = { kind = "dot", base = (n(a) + n(b)) / 2, duration = tonumber(sec) }
            else
                a, sec = d:match("(%d[%d,]*) [%a ]-damage over (%d+) sec")
                if a then m = { kind = "dot", base = n(a), duration = tonumber(sec) } end
            end
            if not m then
                a, sec = d:match("bleed for (%d[%d,]*) damage over (%d+) sec")
                if a then m = { kind = "dot", base = n(a), duration = tonumber(sec) } end
            end
            -- weapon based
            if not m then
                a = d:match("ranged weapon damage plus (%d[%d,]*)") or d:match("increases ranged damage by (%d[%d,]*)")
                    or d:match("ranged damage plus (%d[%d,]*)")
                if a then m = { kind = "ranged", base = n(a) } end
            end
            if not m then
                a = d:match("melee weapon damage plus (%d[%d,]*)") or d:match("increases melee damage by (%d[%d,]*)")
                    or d:match("weapon damage plus (%d[%d,]*)")
                if a then m = { kind = "melee", base = n(a) } end
            end
            if not m then
                a = d:match("hitting (%d+) targets")
                if a then
                    local bonus = d:match("additional (%d[%d,]*) damage")
                    m = { kind = "ranged", base = n(bonus) or 0, targets = tonumber(a) }
                end
            end
            -- direct: "X to Y <school> damage" / "X <school> damage"
            if not m then
                a, b = d:match("(%d[%d,]*) to (%d[%d,]*) [%a ]-damage")
                if a then
                    m = { kind = "direct", base = (n(a) + n(b)) / 2 }
                else
                    a = d:match("(%d[%d,]*) [%a ]-damage")
                    if a then m = { kind = "direct", base = n(a) } end
                end
            end
            if m then
                local pct = d:match("plus (%d+)%% of your ranged attack power")
                if pct then m.rapShare = tonumber(pct) / 100 end
                if m.kind == "dot" then
                    local name = C_Spell.GetSpellName(spellID)
                    if name then ns.durations[name] = m.duration end
                end
            end
        end
    end
    cache[spellID] = m
    return m or nil
end

function ns.ResetModels()
    wipe(cache)
end

-- stats (kept from the last readable value when the game hides them)
local last = { rap = 0, rCrit = 0, mCrit = 0 }

local function readStats()
    local now = GetTime()
    if last.t == now then return last end
    last.t = now
    local speed, minD, maxD = ns.safe(UnitRangedDamage, "player")
    speed, minD, maxD = ns.num(speed), ns.num(minD), ns.num(maxD)
    if speed and speed > 0 and minD and maxD then
        last.rSpeed, last.rAvg = speed, (minD + maxD) / 2
    end
    local mMin, mMax = ns.safe(UnitDamage, "player")
    mMin, mMax = ns.num(mMin), ns.num(mMax)
    if mMin and mMax then last.mAvg = (mMin + mMax) / 2 end
    local base, pos, neg = ns.safe(UnitRangedAttackPower, "player")
    base, pos, neg = ns.num(base), ns.num(pos) or 0, ns.num(neg) or 0
    if base then last.rap = base + pos + neg end
    local rc = ns.num(ns.safe(GetRangedCritChance))
    if rc then last.rCrit = rc end
    local mc = ns.num(ns.safe(GetCritChance))
    if mc then last.mCrit = mc end
    return last
end
ns.ReadStats = readStats

local function castTime(spellID)
    local info = ns.safe(C_Spell.GetSpellInfo, spellID)
    local ct = info and ns.num(info.castTime)
    return ct and ct / 1000 or 0
end

-- expected damage of one press, seconds of your time it costs, extra info
function ns.Estimate(spellID, targets)
    local m = ns.Model(spellID)
    if not m then return nil end
    local s = readStats()
    local name = C_Spell.GetSpellName(spellID)
    local share = m.rapShare or (name and RAP_SHARE[name]) or 0

    if m.kind == "auto" then
        if not s.rAvg or not s.rSpeed then return nil end
        local dmg = s.rAvg * (1 + s.rCrit / 100)
        return dmg, s.rSpeed, "per shot"
    end

    local dmg, crit
    if m.kind == "ranged" then
        if not s.rAvg then return nil end
        dmg, crit = s.rAvg + m.base, s.rCrit
    elseif m.kind == "melee" then
        if not s.mAvg then return nil end
        dmg, crit = s.mAvg + m.base, s.mCrit
    elseif m.kind == "dot" then
        dmg, crit = m.base, 0
    else -- direct
        dmg, crit = m.base, s.rCrit
    end
    dmg = dmg + share * s.rap
    dmg = dmg * (1 + (crit or 0) / 100)

    local hits = 1
    if m.targets then
        hits = math.max(1, math.min(m.targets, targets or 1))
        dmg = dmg * hits
    end

    local exec = math.max(castTime(spellID), GCD)
    local note
    if m.kind == "dot" then note = ("over %d sec"):format(m.duration) end
    if hits > 1 then note = ("%d targets"):format(hits) end
    return dmg, exec, note
end

-- damage per second of your time (instants count as one global cooldown)
function ns.DPS(spellID, targets)
    local dmg, exec, note = ns.Estimate(spellID, targets)
    if not dmg or not exec or exec <= 0 then return nil end
    return dmg / exec, dmg, exec, note
end

function ns.Short(v)
    if v >= 10000 then return ("%.0fk"):format(v / 1000) end
    if v >= 1000 then return ("%.1fk"):format(v / 1000) end
    return ("%d"):format(v + 0.5)
end

function ns.InitDamage()
    addShare(3044, 0.15) -- Arcane Shot
end
