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

-- an action button holding this spell is lit as active (aspects, auto shot...)
function ns.ButtonActive(name)
    for _, b in ipairs(buttons) do
        local slot = slotOf(b)
        if slot then
            local id = spellOf(b)
            if id and C_Spell.GetSpellName(id) == name then
                if ns.flag(ns.safe(IsCurrentAction, slot)) then return true end
                if IsAutoRepeatAction and ns.flag(ns.safe(IsAutoRepeatAction, slot)) then return true end
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
                if enemies == nil then enemies = ns.EnemyCount(ns.aoeRange) end
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

-- also returns the key and the texture of the first such button (the button shows the
-- potion's item icon, Auto Shot's weapon icon...), nil when none holds it
local function glowButtons(spellID, noGlow)
    local name = spellID and C_Spell.GetSpellName(spellID)
    local key, tex
    for _, b in ipairs(buttons) do
        local match = false
        if name and b:IsVisible() then
            local id = spellOf(b)
            match = id and C_Spell.GetSpellName(id) == name or false
            if match and not tex then
                key = hotkeyOf(b)
                local slot = slotOf(b)
                tex = slot and ns.safe(GetActionTexture, slot)
            end
        end
        local on = match and ns.db.glow and not noGlow
        if on and not b.frGlow:IsShown() then
            b.frGlow:Show(); b.frGlow.anim:Play()
        elseif not on and b.frGlow:IsShown() then
            b.frGlow.anim:Stop(); b.frGlow:Hide()
        end
    end
    return key, tex
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

local ARROW = "Interface\\AddOns\\ForeverRotation\\media\\arrow"
local PLACEHOLDER = "Interface\\AddOns\\ForeverRotation\\media\\icon"

-- spells that do the moving for you: they stay on the square instead of the arrow
local MOVERS = { 100, 20252, 16979, 36554, 781 } -- Charge, Intercept, Feral Charge, Shadowstep, Disengage

local function isMover(spellID)
    local n = spellID and C_Spell.GetSpellName(spellID)
    if not n then return false end
    for _, id in ipairs(MOVERS) do
        if C_Spell.GetSpellName(id) == n then return true end
    end
    return false
end

-- "back" / "closer" whenever you have to move (too far, or in the hunter's dead zone with
-- ammo), whatever the rotation would press; a gap closer shows as the spell instead
local function moveWanted()
    if not (ns.db.moveArrow and ns.db.icon and ns.MoveHint) then return nil end
    local hint = ns.MoveHint()
    if not hint then return nil end
    if isMover(ns.suggestion) and ns.InRange(ns.suggestion) ~= false then return nil end
    return hint
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
    icon.arrow = icon:CreateTexture(nil, "ARTWORK")
    icon.arrow:SetPoint("TOPLEFT", 2, -2)
    icon.arrow:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.arrow:SetTexture(ARROW)
    icon.arrow:Hide()
    icon.elapsed, icon.tint = 0, 0
    icon:SetScript("OnUpdate", function(self, e)
        self.tint = self.tint + e
        if self.tint > 0.15 then -- blue while you wait for rage / energy / mana, like the action bars
            self.tint = 0
            local _, noMana
            if ns.suggestion then _, noMana = ns.Usable(ns.suggestion) end
            if noMana then self.tex:SetVertexColor(0.5, 0.5, 1) else self.tex:SetVertexColor(1, 1, 1) end
        end
        self.elapsed = self.elapsed + e
        if self.elapsed > 1 then -- unit frames can move (EasyFrames etc.)
            self.elapsed = 0
            if ns.db.iconMode == "center" then ns.PlaceIcon() end
        end
    end)
    icon:Hide()

    -- range zone line under the square (only while the square shows something)
    local zone = CreateFrame("Frame", nil, UIParent)
    zone:SetSize(120, 16)
    zone:SetPoint("TOP", icon, "BOTTOM", 0, -3)
    zone.text = zone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zone.text:SetPoint("CENTER")
    zone.elapsed = 0
    local ZONES = {
        melee = { "Melee", 1, 0.5, 0.2 },
        dead  = { "Too close", 1, 0.15, 0.15 },
        shoot = { "Shoot", 0.3, 1, 0.3 },
        far   = { "Too far", 0.6, 0.6, 0.6 },
    }
    zone:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        -- only under a square that shows something: no caption on its own
        local shown = ns.db.icon and ns.HostileTarget() and (ns.move or ns.suggestion)
        local z = shown and ns.db.zone and ns.zoneUseful and ns.Zone()
        local d = z and ZONES[z]
        local s = ns.suggestion
        if shown and s and ns.itemSpells[s] and not ns.move then
            -- a potion on the square: say what to do with it, not where the target is
            self.text:SetText("Use")
            self.text:SetTextColor(0.3, 1, 0.3)
            self.text:Show()
        elseif d then
            self.text:SetText((ns.zoneText and ns.zoneText[z]) or d[1])
            self.text:SetTextColor(d[2], d[3], d[4])
            self.text:Show()
        else
            self.text:Hide()
        end
        self:SetScale(ns.db.iconScale or 1)
    end)

    -- every 0.1 s: nothing on the square or the buttons without a live hostile target, and a
    -- big arrow in place of the spell when you have to step back / closer. A new arrow state
    -- has to hold for 0.3 s before it shows, so it doesn't flicker at the edge of a range.
    local driver = CreateFrame("Frame")
    local elapsed, pending, since, shownLive = 0, nil, 0, nil
    driver:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        local live = ns.HostileTarget()
        local want = live and moveWanted() or nil
        local now = GetTime()
        if want ~= pending then pending, since = want, now end
        local move = ns.move
        if not live then move = nil
        elseif want ~= move and now - since >= 0.3 then move = want end
        if move ~= ns.move or live ~= shownLive then
            ns.move, shownLive = move, live
            ns.ShowSuggestion(ns.suggestion)
        end
    end)

    ns.UpdateIconLock()
end

-- icon for a suggestion that sits on no action button: a potion shows the item itself (on
-- Forever the use-spell of an item has no icon of its own, just the game's logo)
local function suggestionTexture(spellID)
    local itemID = ns.itemSpells[spellID]
    if itemID then
        local tex = ns.safe(C_Item.GetItemIconByID, itemID)
        if tex then return tex end
    end
    return C_Spell.GetSpellTexture(spellID) or 134400
end

-- green frame while the free square can be dragged, black otherwise
local function borderColor()
    if not ns.db.locked and ns.db.iconMode ~= "center" then
        icon:SetBackdropBorderColor(0.2, 1, 0.3, 1)
    else
        icon:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

function ns.UpdateIconLock()
    if not icon then return end
    icon:SetScale(ns.db.iconScale or 1)
    ns.PlaceIcon()
    local movable = not ns.db.locked and ns.db.iconMode ~= "center"
    icon:EnableMouse(movable)
    borderColor()
    if movable then
        if not ns.suggestion then icon.tex:SetTexture("Interface\\AddOns\\ForeverRotation\\media\\icon") end
        icon:Show()
    end
    ns.ShowSuggestion(ns.suggestion)
end

function ns.ShowSuggestion(spellID)
    local live = ns.HostileTarget()
    local move = live and ns.move or nil
    -- Auto Shot already shooting: show it, but don't make it glow (a press would stop it)
    local name = spellID and C_Spell.GetSpellName(spellID)
    local idle = name and ns.idleSpell and name == C_Spell.GetSpellName(ns.idleSpell) and ns.ButtonActive(name)
    local key, btnTex = glowButtons((live and not move) and spellID or nil, idle)
    if not icon then return end
    if live and ns.db.icon and (move or spellID) then
        if move then
            -- step closer: green arrow up; step back: red arrow down
            local back = move == "back"
            icon.tex:Hide()
            icon:SetBackdropBorderColor(0, 0, 0, 0) -- the arrow stands on its own, no frame
            icon.arrow:SetTexCoord(0, 1, back and 1 or 0, back and 0 or 1)
            if back then icon.arrow:SetVertexColor(1, 0.3, 0.25) else icon.arrow:SetVertexColor(0.3, 1, 0.35) end
            icon.arrow:Show()
            icon.key:SetText("")
            icon.dmg:SetText("")
        else
            icon.arrow:Hide()
            borderColor()
            icon.tex:SetTexture(btnTex or suggestionTexture(spellID))
            icon.tex:Show()
            icon.key:SetText(key or "")
            local dps = ns.db.labels and ns.DPS(spellID, ns.EnemyCount(ns.aoeRange))
            icon.dmg:SetText(dps and ns.Short(dps) or "")
        end
        icon:Show()
    elseif ns.db.locked or ns.db.iconMode == "center" or not ns.db.icon then
        icon:Hide()
    else -- unlocked free square: the addon icon, so you can drag it
        icon.arrow:Hide()
        borderColor()
        icon.tex:SetTexture(PLACEHOLDER)
        icon.tex:Show()
        icon.key:SetText("")
        icon.dmg:SetText("")
        icon:Show()
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
        local dps, dmg, exec, note = ns.DPS(id, ns.EnemyCount(ns.aoeRange))
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
    add(("enemies: %d, suggestion: %s"):format(ns.EnemyCount(ns.aoeRange), tostring(ns.suggestion and C_Spell.GetSpellName(ns.suggestion))))
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
