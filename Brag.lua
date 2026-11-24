local ADDON, ns = ...

---------------------------------------------------------------------------
-- A line in the party chat when you are the group's top damage in a dungeon, the way
-- Questie announces quest progress. Once per run, right after a boss dies, and only when at
-- least three people dealt damage. Pets count for their owner. Settings: "Tell the party...".
-- Forever treats chat from an addon as a protected action, so the line is not sent by the
-- addon: a small panel offers it and one click on its (secure macro) button posts it.
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

-- the offer: text + a secure button whose macro posts it (addons can't post chat on Forever)
local panel, pending
local function buildPanel()
    panel = CreateFrame("Frame", "ForeverRotationBrag", UIParent, "BackdropTemplate")
    panel:SetSize(380, 70)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -140)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    panel:SetBackdropBorderColor(1, 0.55, 0.1, 1)
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT", 10, -8)
    panel.text:SetPoint("TOPRIGHT", -26, -8)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetWordWrap(true)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)
    local btn = CreateFrame("Button", "ForeverRotationBragSend", panel, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetPoint("BOTTOM", 0, 6)
    btn:SetText("Tell the party")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "macro")
    btn:HookScript("OnClick", function() panel:Hide() end)
    panel.btn = btn
    panel:Hide()
end

local function offer(msg)
    if InCombatLockdown() then pending = msg; return end -- the button's macro can't change in combat
    pending = nil
    if not panel then buildPanel() end
    local slash = "/p "
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then slash = "/i "
    elseif IsInRaid() then slash = "/raid " end
    panel.btn:SetAttribute("macrotext", slash .. msg)
    panel.text:SetText(msg)
    panel:Show()
    C_Timer.After(90, function() if panel.text:GetText() == msg then panel:Hide() end end)
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
    offer(msg)
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
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then offer(pending) end
    elseif event == "PLAYER_ENTERING_WORLD" then
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
