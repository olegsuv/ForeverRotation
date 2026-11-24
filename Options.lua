local ADDON, ns = ...

local ICON = "Interface\\AddOns\\ForeverRotation\\media\\icon"
local win, mini

local function pct(v) return ("%d%%"):format(v) end

local function build()
    local db = ns.db
    win = ns.UI.Window("ForeverRotationOptions", "Forever Rotation", 340)

    win:AddHeader("Numbers")
    win:AddCheck("Damage per second on action buttons", function() return db.labels end,
        function(v) db.labels = v; ns.labelsDirty = true; ns.ShowSuggestion(ns.suggestion) end)

    win:AddHeader("Next spell")
    win:AddCheck("Highlight it on the action bars", function() return db.glow end,
        function(v) db.glow = v; ns.ShowSuggestion(ns.suggestion) end)
    win:AddCheck("Show a separate square", function() return db.icon end,
        function(v) db.icon = v; ns.UpdateIconLock() end)
    win:AddCheck("Put it between player and target frames", function() return db.iconMode == "center" end,
        function(v) db.iconMode = v and "center" or "free"; ns.UpdateIconLock() end,
        function() return db.icon end)
    win:AddCheck("Unlock to drag it (when not between frames)", function() return not db.locked end,
        function(v) db.locked = not v; ns.UpdateIconLock() end,
        function() return db.icon and db.iconMode ~= "center" end)
    win:AddCheck("Range zone under it (melee / too close / shoot)", function() return db.zone end,
        function(v) db.zone = v end, function() return db.icon end)
    win:AddCheck("Range zone icon by the target's nameplate", function() return db.zonePlate end,
        function(v) db.zonePlate = v end)
    win:AddCheck("Big arrow instead of the spell when you have to step back or closer",
        function() return db.moveArrow end, function(v) db.moveArrow = v end, function() return db.icon end)
    win:AddSlider("Square size", 0.5, 2, 0.1, function() return db.iconScale end,
        function(v) db.iconScale = v; ns.UpdateIconLock() end, function(v) return ("%.1fx"):format(v) end)

    win:AddHeader("Potions and self-heals")
    win:AddCheck("Suggest a potion when low", function() return db.potions end,
        function(v) db.potions = v end)
    win:AddSlider("Mana potion below", 5, 50, 5, function() return db.potionMana end,
        function(v) db.potionMana = v end, pct)
    win:AddSlider("Healing potion below", 10, 60, 5, function() return db.potionHealth end,
        function(v) db.potionHealth = v end, pct)
    win:AddSlider("Self-heal spell below (healers, hybrids)", 10, 70, 5, function() return db.selfHeal end,
        function(v) db.selfHeal = v end, pct)

    win:AddHeader("Other")
    win:AddCheck("Collect aggro data (distance and level when mobs aggro)", function() return db.aggroLog end,
        function(v) db.aggroLog = v end)
    win:AddCheck("Offer a party chat line when you top the damage in a dungeon (one click posts it; once per run, after a boss)",
        function() return db.brag end, function(v) db.brag = v end)
    win:AddCheck("Minimap button", function() return not db.minimapHide end,
        function(v) db.minimapHide = not v; mini:UpdateShown() end)
    win:AddButtons({
        { "Debug to chat", function() ns.Debug() end },
        { "Reset square", function() db.iconPos = nil; db.iconScale = 1; ns.UpdateIconLock(); win:Refresh() end },
    })
    win:Finish()
end

function ns.ToggleOptions()
    if not win then build() end
    win:Toggle()
end

function ns.InitOptions()
    mini = ns.UI.MinimapButton({
        name = "ForeverRotationMinimapButton",
        icon = ICON,
        db = ns.db,
        angle = 215,
        title = "Forever Rotation",
        lines = function()
            return {
                "Left-click: settings",
                "Right-click: numbers on buttons on/off",
                "Drag: move around the minimap",
            }
        end,
        onLeft = ns.ToggleOptions,
        onRight = function()
            ns.db.labels = not ns.db.labels
            ns.labelsDirty = true
            ns.Print("numbers on buttons: " .. (ns.db.labels and "on" or "off"))
            if win and win:IsShown() then win:Refresh() end
        end,
    })
end

-- Addon compartment (the addons button by the minimap)
function ForeverRotation_OnAddonCompartmentClick()
    ns.ToggleOptions()
end
