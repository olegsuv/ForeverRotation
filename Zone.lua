local ADDON, ns = ...

-- Range zone icon to the right of the target's nameplate (past the level; the elite icon and
-- raid marks sit on the left): the zone colour, the distance in yards beside it and the zone
-- word on the name's line.
local ZONES = {
    melee = { "Interface\\Icons\\Ability_MeleeDamage", 1, 0.55, 0.2, "Melee" },
    dead  = { "Interface\\Icons\\Spell_Shadow_Teleport", 1, 0.15, 0.15, "Too close" },
    shoot = { "Interface\\Icons\\Ability_Marksmanship", 0.3, 1, 0.3, "Shoot" },
    far   = { "Interface\\Icons\\Ability_Rogue_Sprint", 0.6, 0.6, 0.6, "Too far" },
}

-- styled like the plate's level box: dark fill, thin rounded border (zone colour instead of the
-- game's yellow), texts in the plate's name font with its shadow. Parented to the plate so it
-- scales with it.
local f = CreateFrame("Frame", "ForeverRotationZoneIcon", UIParent, "BackdropTemplate")
f:SetSize(20, 20)
f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
f:SetBackdropColor(0, 0, 0, 0.75)
f.tex = f:CreateTexture(nil, "ARTWORK")
f.tex:SetPoint("TOPLEFT", 3, -3)
f.tex:SetPoint("BOTTOMRIGHT", -3, 3)
f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
f.dist:SetPoint("LEFT", f, "RIGHT", 4, 0)
f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 1, 2)
f:Hide()

-- "12-15 yd", "<5 yd", ">35 yd" from the range bracket (Aggro.lua probes spells, items, interact)
local function distanceText()
    if not ns.DistanceBracket then return "" end
    local lo, hi = ns.DistanceBracket("target")
    if lo and hi then return ("%d-%d yd"):format(lo, hi) end
    if hi then return ("<%d yd"):format(hi) end
    if lo then return (">%d yd"):format(lo) end
    return ""
end

-- the plate's level text: a font string showing the target's level (or ?? for skulls)
local function levelText(uf)
    local lvl = ns.num(ns.safe(UnitLevel, "target"))
    local want = (lvl and lvl > 0) and tostring(lvl) or "??"
    local function scan(frame)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                local t = r:GetText()
                if t and not ns.isSecret(t) and t == want then return r end
            end
        end
    end
    local found = scan(uf)
    if found then return found end
    for _, child in ipairs({ uf:GetChildren() }) do
        found = scan(child)
        if found then return found end
    end
end

-- the plate's name text: a font string showing the target's name
local function nameText(uf)
    if uf.name and uf.name.GetFont then return uf.name end
    local want = ns.safe(UnitName, "target")
    if not want or ns.isSecret(want) then return nil end
    for _, r in ipairs({ uf:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            local t = r:GetText()
            if t and not ns.isSecret(t) and t == want then return r end
        end
    end
end

-- both texts in the plate's own name font and shadow (only the colour differs)
local fontFrom
local function matchNameFont(uf)
    local name = nameText(uf)
    if not name or name == fontFrom then return end
    local font, size, flags = name:GetFont()
    if not font then return end
    for _, fs in ipairs({ f.label, f.dist }) do
        fs:SetFont(font, size, flags)
        fs:SetShadowOffset(name:GetShadowOffset())
        fs:SetShadowColor(name:GetShadowColor())
    end
    fontFrom = name
end

local function anchorToPlate()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and ns.safe(C_NamePlate.GetNamePlateForUnit, "target")
    if not plate then return false end
    -- forbidden nameplates (some instances) refuse parents, anchors and reads: pcall
    if f:GetParent() ~= plate and not pcall(f.SetParent, f, plate) then return false end
    f:SetFrameLevel(plate:GetFrameLevel() + 10)
    f:ClearAllPoints()
    -- past the level box (the elite icon and raid marks sit on the left), as tall as the box
    local uf = plate.UnitFrame
    if uf then pcall(matchNameFont, uf) end
    local okLevel, level = false, nil
    if uf then okLevel, level = pcall(levelText, uf) end
    local bar = uf and (uf.healthBar or uf.HealthBar)
    local box = okLevel and level and level:GetParent()
    local h = box and box ~= uf and box:GetHeight()
    if not h or h < 12 or h > 40 then h = bar and bar:GetHeight() + 8 or 20 end
    f:SetSize(h, h)
    if okLevel and level then
        return pcall(f.SetPoint, f, "LEFT", level, "RIGHT", 8, 0)
    elseif bar then
        return pcall(f.SetPoint, f, "LEFT", bar, "RIGHT", 30, 0)
    end
    return pcall(f.SetPoint, f, "LEFT", plate, "RIGHT", 2, 0)
end

local elapsed = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.2 then return end
    elapsed = 0
    if not ns.db or not ns.db.zonePlate or not ns.zoneUseful then f:Hide(); return end
    local z = ns.Zone()
    local d = z and ZONES[z]
    if d and anchorToPlate() then
        f.tex:SetTexture(d[1])
        f:SetBackdropBorderColor(d[2], d[3], d[4], 1)
        f.label:SetText((ns.zoneText and ns.zoneText[z]) or d[5])
        f.label:SetTextColor(d[2], d[3], d[4])
        f.dist:SetText(distanceText())
        f.dist:SetTextColor(d[2], d[3], d[4])
        f:Show()
    else
        f:Hide()
    end
end)
