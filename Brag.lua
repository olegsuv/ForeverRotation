local ADDON, ns = ...

---------------------------------------------------------------------------
-- A line in the party chat when you are the group's top damage in a dungeon, the way
-- Questie announces quest progress. Once per run, right after a boss dies, and only when at
-- least three people dealt damage. The numbers come from Details! (its current segment,
-- the boss fight): Forever does not let addons read the combat log, so without Details
-- this does nothing. Forever also treats chat from an addon as a protected action, so the
-- line is not sent by the addon: a small panel offers it and one click on its (secure
-- macro) button posts it.
---------------------------------------------------------------------------
local inside = false     -- in a dungeon / raid instance
local instanceName
local bosses = {}        -- GUID -> name of the bosses seen (target, nameplates)
local said = false       -- one line per run

local function reset()
    bosses, said = {}, false
end

local function isBoss(unit)
    local cls = ns.safe(UnitClassification, unit)
    if cls and not ns.isSecret(cls) and cls == "worldboss" then return true end
    if ns.flag(ns.safe(UnitIsBossMob, unit)) == true then return true end
    return ns.num(ns.safe(UnitLevel, unit)) == -1
end

local function noteBoss(unit)
    if not inside or not UnitExists(unit) or not isBoss(unit) then return end
    local guid = ns.GUID(unit)
    if guid then
        local n = ns.safe(UnitName, unit)
        bosses[guid] = (type(n) == "string" and not ns.isSecret(n)) and n or "the boss"
    end
end

-- damage per group member in Details' current segment: name -> total (pets are already
-- added to their owner by Details), nil without Details
local function detailsDamage()
    if not Details or not Details.GetCurrentCombat then return nil end
    local ok, combat = pcall(Details.GetCurrentCombat, Details)
    if not ok or type(combat) ~= "table" or not combat.GetContainer then return nil end
    local ok2, container = pcall(combat.GetContainer, combat, DETAILS_ATTRIBUTE_DAMAGE or 1)
    if not ok2 or type(container) ~= "table" or type(container._ActorTable) ~= "table" then return nil end
    local totals = {}
    for _, actor in ipairs(container._ActorTable) do
        if type(actor) == "table" and actor.grupo and not actor.owner and type(actor.nome) == "string" then
            local total = tonumber(actor.total) or 0
            if total > 0 then totals[actor.nome] = total end
        end
    end
    return totals
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
    local totals = detailsDamage()
    if not totals then return end
    local me = ns.safe(UnitName, "player")
    if type(me) ~= "string" or ns.isSecret(me) then return end
    local mine = totals[me]
    if not mine or mine <= 0 then return end
    local total, n, top = 0, 0, true
    for name, d in pairs(totals) do
        n = n + 1
        total = total + d
        if name ~= me and d >= mine then top = false end
    end
    if n < 3 or not top then return end
    said = true
    local share = math.floor(mine / total * 100 + 0.5)
    local msg = ("Forever Rotation helped me keep the top damage in %s: %d%% of the group's on %s."):format(
        instanceName or "this dungeon", share, bossName)
    offer(msg)
end

-- a boss you have seen reads as dead on the target (no combat log on Forever)
local function checkDead(unit)
    local guid = ns.GUID(unit)
    local name = guid and bosses[guid]
    if not name then return end
    if ns.flag(ns.safe(UnitIsDeadOrGhost, unit)) == true then
        bosses[guid] = nil
        C_Timer.After(0.5, function() announce(name) end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterUnitEvent("UNIT_HEALTH", "target")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then offer(pending) end
        checkDead("target")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, kind = IsInInstance()
        local now = kind == "party" or kind == "raid"
        if now ~= inside then
            inside = now
            reset()
            if inside then instanceName = GetInstanceInfo() end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        noteBoss("target")
        checkDead("target")
    elseif event == "UNIT_HEALTH" then
        if inside then checkDead("target") end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg1 then noteBoss(arg1) end
    end
end)
