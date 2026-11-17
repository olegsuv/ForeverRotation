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
                label:SetPoint("TOP", b, "TOP", 0, -2)
                label:SetTextColor(1, 0.85, 0.2)
                b.frLabel = label
                b.frGlow = makeGlow(b)
                buttons[#buttons + 1] = b
            end
        end
    end
    if ns.InitDamage then ns.InitDamage() end
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
local function glowButtons(spellID)
    local name = spellID and C_Spell.GetSpellName(spellID)
    for _, b in ipairs(buttons) do
        local on = false
        if name and ns.db.glow and b:IsVisible() then
            local id = spellOf(b)
            on = id and C_Spell.GetSpellName(id) == name or false
        end
        if on and not b.frGlow:IsShown() then
            b.frGlow:Show(); b.frGlow.anim:Play()
        elseif not on and b.frGlow:IsShown() then
            b.frGlow.anim:Stop(); b.frGlow:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Next-spell icon
---------------------------------------------------------------------------
local icon

function ns.InitIcon()
    icon = CreateFrame("Frame", "ForeverRotationIcon", UIParent, "BackdropTemplate")
    icon:SetSize(44, 44)
    icon:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    icon:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.iconPos = { p, rp, x, y }
    end)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.text = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.text:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    if ns.db.iconPos then
        local p = ns.db.iconPos
        icon:ClearAllPoints()
        icon:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    ns.UpdateIconLock()
    icon:Hide()
end

function ns.UpdateIconLock()
    if not icon then return end
    icon:SetScale(ns.db.iconScale or 1)
    icon:EnableMouse(not ns.db.locked)
    if not ns.db.locked then
        icon:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        icon:Show()
        if not ns.suggestion then icon.tex:SetTexture(134400) end
    else
        icon:SetBackdrop(nil)
        ns.ShowSuggestion(ns.suggestion)
    end
end

function ns.ShowSuggestion(spellID)
    glowButtons(spellID)
    if not icon then return end
    if spellID and ns.db.icon then
        icon.tex:SetTexture(C_Spell.GetSpellTexture(spellID))
        local dps = ns.db.labels and ns.DPS(spellID, ns.EnemyCount(2643))
        icon.text:SetText(dps and ns.Short(dps) or "")
        icon:Show()
    elseif ns.db.locked then
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
