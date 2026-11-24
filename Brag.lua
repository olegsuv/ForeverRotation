local ADDON, ns = ...

---------------------------------------------------------------------------
-- A line in the party chat when you are the group's top damage in a dungeon, the way
-- Questie announces quest progress. Once per run, right after a boss dies, and only when at
-- least three people dealt damage. Pets count for their owner. Settings: "Tell the party...".
---------------------------------------------------------------------------
local band = bit.band
local AFF_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_PET = (COMBATLOG_OBJECT_TYPE_PET or 0x1000) + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40

local inside = false     -- in a dungeon / raid instance
local instanceName
local damage = {}        -- player GUID -> damage this run
local owners = {}        -- pet GUID -> owner GUID
local bosses = {}        -- GUID -> name of the bosses seen (target, nameplates)
local said = false       -- one line per run

local function reset()
    damage, owners, bosses, said = {}, {}, {}, false
end

-- pets of the group: their damage goes to the owner
local function scanPets()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        local owner = UnitGUID(u)
        local pet = owner and UnitGUID(u .. "pet")
        if pet then owners[pet] = owner end
    end
end

local function isBoss(unit)
    if ns.safe(UnitClassification, unit) == "worldboss" then return true end
    if ns.flag(ns.safe(UnitIsBossMob, unit)) == true then return true end
    return ns.num(ns.safe(UnitLevel, unit)) == -1
end

local function noteBoss(unit)
    if not inside or not UnitExists(unit) or not isBoss(unit) then return end
    local guid = UnitGUID(unit)
    if guid then bosses[guid] = UnitName(unit) or "the boss" end
end

local function announce(bossName)
    if said or not ns.db.brag then return end
    local me = UnitGUID("player")
    local mine = me and damage[me]
    if not mine or mine <= 0 then return end
    local total, n, top = 0, 0, true
    for guid, d in pairs(damage) do
        if d > 0 then
            n = n + 1
            total = total + d
            if guid ~= me and d >= mine then top = false end
        end
    end
    if n < 3 or not top then return end
    said = true
    local share = math.floor(mine / total * 100 + 0.5)
    local msg = ("Forever Rotation helped me keep the top damage in %s: %d%% of the group's, %s down."):format(
        instanceName or "this dungeon", share, bossName)
    local channel = "PARTY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
    elseif IsInRaid() then channel = "RAID" end
    pcall(SendChatMessage, msg, channel)
end

local function onCombatLog()
    local ok, _, sub, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags, _, a12, _, _, a15 = pcall(CombatLogGetCurrentEventInfo)
    if not ok or type(sub) ~= "string" then return end
    if sub == "UNIT_DIED" then
        local name = dstGUID and bosses[dstGUID]
        if name then announce(name) end
        return
    end
    if not sub:find("_DAMAGE", 1, true) or sub == "ENVIRONMENTAL_DAMAGE" then return end
    srcFlags, dstFlags = ns.num(srcFlags), ns.num(dstFlags)
    if not srcFlags or not dstFlags then return end
    if band(dstFlags, REACTION_HOSTILE) == 0 then return end
    if band(srcFlags, AFF_GROUP) == 0 then return end
    local owner
    if band(srcFlags, TYPE_PLAYER) ~= 0 then
        owner = srcGUID
    elseif band(srcFlags, TYPE_PET) ~= 0 then
        owner = owners[srcGUID]
        if not owner then scanPets(); owner = owners[srcGUID] end
    end
    if not owner then return end
    local amount = ns.num(sub == "SWING_DAMAGE" and a12 or a15)
    if not amount or amount <= 0 then return end
    damage[owner] = (damage[owner] or 0) + amount
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        local _, kind = IsInInstance()
        local now = kind == "party" or kind == "raid"
        if now ~= inside then
            inside = now
            reset()
            if inside then
                instanceName = GetInstanceInfo()
                scanPets()
                f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            else
                f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "PLAYER_TARGET_CHANGED" then
        noteBoss("target")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg1 then noteBoss(arg1) end
    elseif inside then
        scanPets()
    end
end)
