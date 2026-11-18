local ADDON, ns = ...

-- Range zone icon next to the target's nameplate: melee / dead zone / shoot / too far.
local ZONES = {
    melee = { "Interface\\Icons\\Ability_MeleeDamage", 1, 0.55, 0.2, "MELEE" },
    dead  = { "Interface\\Icons\\Spell_Shadow_Teleport", 1, 0.15, 0.15, "TOO CLOSE" },
    shoot = { "Interface\\Icons\\Ability_Marksmanship", 0.3, 1, 0.3, "SHOOT" },
    far   = { "Interface\\Icons\\Ability_Rogue_Sprint", 0.6, 0.6, 0.6, "TOO FAR" },
}
ns.ZONES = ZONES

local f = CreateFrame("Frame", "ForeverRotationZoneIcon", UIParent, "BackdropTemplate")
f:SetSize(22, 22)
f:SetFrameStrata("MEDIUM")
f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
f.tex = f:CreateTexture(nil, "ARTWORK")
f.tex:SetPoint("TOPLEFT", 2, -2)
f.tex:SetPoint("BOTTOMRIGHT", -2, 2)
f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
f.label:SetPoint("RIGHT", f, "LEFT", -3, 0)
f:Hide()

local function anchorToPlate()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and ns.safe(C_NamePlate.GetNamePlateForUnit, "target")
    if not plate then return false end
    f:ClearAllPoints()
    -- forbidden nameplates (some instances) refuse anchors: pcall
    local ok = pcall(f.SetPoint, f, "RIGHT", plate, "LEFT", -2, 0)
    return ok
end

local elapsed = 0
f:SetScript("OnUpdate", nil)
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.2 then return end
    elapsed = 0
    if not ns.db or not ns.db.zonePlate or not ns.RangeZone then f:Hide(); return end
    local z = ns.RangeZone()
    local d = z and ZONES[z]
    if d and anchorToPlate() then
        f.tex:SetTexture(d[1])
        f:SetBackdropBorderColor(d[2], d[3], d[4], 1)
        f.label:SetText((ns.zoneText and ns.zoneText[z]) or d[5])
        f.label:SetTextColor(d[2], d[3], d[4])
        f:Show()
    else
        f:Hide()
    end
end)
