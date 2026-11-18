local ADDON, ns = ...

local BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local buttons = {}

local function slotOf(b)
    local s = b.action
    if type(s) ~= "number" and b.GetAttribute then s = b:GetAttribute("action") end
    if type(s) == "number" and s > 0 then return s end
end

-- spellID on a button (spells, spell macros, usable items)
local function spellOf(b)
    local slot = slotOf(b)
    if not slot then return nil end
    local kind, id = GetActionInfo(slot)
    if kind == "spell" then
        return id
    elseif kind == "macro" then
        return ns.safe(GetMacroSpell, id)
    elseif kind == "item" then
        local _, spellID = ns.safe(C_Item.GetItemSpell, id)
        return spellID
    end
end
ns.ButtonSpell = spellOf

-- an action button holding this spell is lit as active (aspects, auto shot...)
function ns.ButtonActive(name)
    for _, b in ipairs(buttons) do
        local slot = slotOf(b)
        if slot then
            local id = spellOf(b)
            if id and C_Spell.GetSpellName(id) == name then
                if ns.flag(ns.safe(IsCurrentAction, slot)) then return true end
            end
        end
    end
    return false
end

-- the game's proc glow on a button with this spell
function ns.ButtonGlow(name)
    for _, b in ipairs(buttons) do
        local id = spellOf(b)
        if id and C_Spell.GetSpellName(id) == name then
            local alert = b.SpellActivationAlert or b.overlay
            if alert and alert.IsShown and alert:IsShown() then return true end
        end
    end
    return false
end

local function makeGlow(b)
    local g = CreateFrame("Frame", nil, b)
    g:SetPoint("TOPLEFT", -2, 2)
    g:SetPoint("BOTTOMRIGHT", 2, -2)
    g:SetFrameLevel(b:GetFrameLevel() + 5)
    local function edge(p1, p2, w, h)
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.2, 1, 0.3, 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 3)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
    edge("TOPLEFT", "BOTTOMLEFT", 3, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.45)
    g.anim = ag
    g:Hide()
    return g
end

function ns.InitButtons()
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then
                local label = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                label:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2) -- top-right is the key bind
                label:SetTextColor(1, 0.85, 0.2)
                b.frLabel = label
                b.frGlow = makeGlow(b)
                buttons[#buttons + 1] = b
            end
        end
    end
    if ns.InitDamage then ns.InitDamage() end
end

-- what is on the bars (saved, for remote debugging)
function ns.Census()
    local out = {}
    for _, b in ipairs(buttons) do
        if b:IsVisible() then
            local id = spellOf(b)
            if id then
                out[#out + 1] = ("%s %s(%d)"):format(b:GetName() or "?", tostring(C_Spell.GetSpellName(id)), id)
            end
        end
    end
    ns.db.bars = out
end

function ns.RefreshLabels()
    local enemies
    for _, b in ipairs(buttons) do
        local text = ""
        if ns.db.labels and b:IsVisible() then
            local id = spellOf(b)
            if id and ns.Model(id) then
                if enemies == nil then enemies = ns.EnemyCount(2643) end
                local dps = ns.DPS(id, enemies)
                if dps then text = ns.Short(dps) end
            end
        end
        b.frLabel:SetText(text)
    end
end

-- glow buttons holding the suggested spell (matched by name, any rank)
local function hotkeyOf(b)
    local hk = b.HotKey or (b.GetName and _G[b:GetName() .. "HotKey"])
    local t = hk and hk:GetText()
    if not t or t == "" or t == RANGE_INDICATOR then return nil end
    return t
end

local function glowButtons(spellID)
    local name = spellID and C_Spell.GetSpellName(spellID)
    local key
    for _, b in ipairs(buttons) do
        local match = false
        if name and b:IsVisible() then
            local id = spellOf(b)
            match = id and C_Spell.GetSpellName(id) == name or false
            if match and not key then key = hotkeyOf(b) end
        end
        local on = match and ns.db.glow
        if on and not b.frGlow:IsShown() then
            b.frGlow:Show(); b.frGlow.anim:Play()
        elseif not on and b.frGlow:IsShown() then
            b.frGlow.anim:Stop(); b.frGlow:Hide()
        end
    end
    return key
end

---------------------------------------------------------------------------
-- Next-spell square: spell icon + key bind + damage, like an action button.
-- Either free (drag it) or centred between the player and target frames.
---------------------------------------------------------------------------
local icon

local function placeBetweenFrames()
    local pf, tf = PlayerFrame, TargetFrame
    if not (pf and tf) then return false end
    local pr, tl = pf:GetRight(), tf:GetLeft()
    local pb, pt = pf:GetBottom(), pf:GetTop()
    if not (pr and tl and pb and pt) then return false end
    local ps, ts, us = pf:GetEffectiveScale(), tf:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local x = (pr * ps + tl * ts) / 2 / us
    local y = (pb + pt) / 2 * ps / us
    local s = icon:GetScale()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    return true
end

function ns.PlaceIcon()
    if not icon then return end
    if ns.db.iconMode == "center" and placeBetweenFrames() then return end
    icon:ClearAllPoints()
    local p = ns.db.iconPos
    if p then
        icon:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        icon:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
end

function ns.InitIcon()
    icon = CreateFrame("Frame", "ForeverRotationIcon", UIParent, "BackdropTemplate")
    icon:SetSize(40, 40)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:SetFrameStrata("MEDIUM")
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function(self)
        if not ns.db.locked and ns.db.iconMode ~= "center" then self:StartMoving() end
    end)
    icon:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.iconPos = { p, rp, x, y }
    end)
    icon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    icon:SetBackdropBorderColor(0, 0, 0, 1)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", 1, -1)
    icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.key = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    icon.key:SetPoint("TOPRIGHT", -2, -3)
    icon.dmg = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.dmg:SetPoint("BOTTOMLEFT", 2, 2)
    icon.dmg:SetTextColor(1, 0.85, 0.2)
    icon.elapsed = 0
    icon:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed > 1 then -- unit frames can move (EasyFrames etc.)
            self.elapsed = 0
            if ns.db.iconMode == "center" then ns.PlaceIcon() end
        end
    end)
    icon:Hide()

    -- range zone line under the square (shown whenever there is a hostile target)
    local zone = CreateFrame("Frame", nil, UIParent)
    zone:SetSize(120, 16)
    zone:SetPoint("TOP", icon, "BOTTOM", 0, -3)
    zone.text = zone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zone.text:SetPoint("CENTER")
    zone.elapsed = 0
    local ZONES = {
        melee = { "MELEE", 1, 0.5, 0.2 },
        dead  = { "TOO CLOSE", 1, 0.15, 0.15 },
        shoot = { "SHOOT", 0.3, 1, 0.3 },
        far   = { "TOO FAR", 0.6, 0.6, 0.6 },
    }
    zone:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        local z = ns.db.zone and ns.db.icon and ns.RangeZone and ns.RangeZone()
        local d = z and ZONES[z]
        if d then
            self.text:SetText(d[1])
            self.text:SetTextColor(d[2], d[3], d[4])
            self.text:Show()
        else
            self.text:Hide()
        end
        self:SetScale(ns.db.iconScale or 1)
    end)
    ns.zoneFrame = zone
    ns.UpdateIconLock()
end

function ns.UpdateIconLock()
    if not icon then return end
    icon:SetScale(ns.db.iconScale or 1)
    ns.PlaceIcon()
    local movable = not ns.db.locked and ns.db.iconMode ~= "center"
    icon:EnableMouse(movable)
    if movable then
        icon:SetBackdropBorderColor(0.2, 1, 0.3, 1)
        if not ns.suggestion then icon.tex:SetTexture("Interface\\AddOns\\ForeverRotation\\media\\icon") end
        icon:Show()
    else
        icon:SetBackdropBorderColor(0, 0, 0, 1)
    end
    ns.ShowSuggestion(ns.suggestion)
end

function ns.ShowSuggestion(spellID)
    local key = glowButtons(spellID)
    if not icon then return end
    if spellID and ns.db.icon then
        icon.tex:SetTexture(C_Spell.GetSpellTexture(spellID))
        icon.key:SetText(key or "")
        local dps = ns.db.labels and ns.DPS(spellID, ns.EnemyCount(2643))
        icon.dmg:SetText(dps and ns.Short(dps) or "")
        icon:Show()
    elseif ns.db.locked or ns.db.iconMode == "center" or not ns.db.icon then
        icon:Hide()
    end
end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------
function ns.InitTooltip()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
        if not ns.db.labels or not data or not data.id then return end
        local id = data.id
        if ns.isSecret(id) then return end
        local dps, dmg, exec, note = ns.DPS(id, ns.EnemyCount(2643))
        if not dps then return end
        tt:AddLine(("|cffffd633~%s per sec|r  (%s dmg / %.1fs%s)"):format(
            ns.Short(dps), ns.Short(dmg), exec, note and (", " .. note) or ""), 1, 1, 1)
    end)
end

---------------------------------------------------------------------------
-- Debug dump (chat + SavedVariables)
---------------------------------------------------------------------------
function ns.Debug()
    ns.ScanSpellbook()
    ns.ResetModels()
    local s = ns.ReadStats()
    local out = {}
    local function add(line) out[#out + 1] = line; ns.Print(line) end
    add(("stats: ranged avg %s speed %s RAP %s rCrit %s melee avg %s"):format(
        tostring(s.rAvg), tostring(s.rSpeed), tostring(s.rap), tostring(s.rCrit), tostring(s.mAvg)))
    add(("enemies: %d, suggestion: %s"):format(ns.EnemyCount(2643), tostring(ns.suggestion and C_Spell.GetSpellName(ns.suggestion))))
    local seen = {}
    for _, b in ipairs(buttons) do
        local id = spellOf(b)
        if id and not seen[id] then
            seen[id] = true
            local m = ns.Model(id)
            local dps, dmg, exec = ns.DPS(id, 1)
            add(("%s (%d): %s base=%s dmg=%s exec=%s dps=%s | %s"):format(
                tostring(C_Spell.GetSpellName(id)), id, m and m.kind or "-", m and tostring(m.base) or "-",
                dmg and ("%.0f"):format(dmg) or "-", exec and ("%.1f"):format(exec) or "-",
                dps and ("%.0f"):format(dps) or "-",
                tostring(ns.safe(C_Spell.GetSpellDescription, id))))
        end
    end
    ns.db.lastDebug = out
end
