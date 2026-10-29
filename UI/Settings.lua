local _, ns = ...
local UI = ns.UI

-- Settings tab in the main window, plus a stub in the game's AddOns options
-- that opens it.

local function Section(parent, title, x, y, width)
    local t = UI.Text(parent, "GameFontNormal", title)
    t:SetPoint("TOPLEFT", x, y)
    local line = UI.Divider(parent)
    line:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
    line:SetWidth(width)
    return t
end

local function Build(page)
    local controls = {}
    local S = function() return ns.db.settings end

    -- Column layout helpers
    local cursor = {}
    local function Column(x, title, width)
        Section(page, title, x, cursor[x] or 0, width)
        cursor[x] = (cursor[x] or 0) - 26
    end
    local function Gap(x) cursor[x] = cursor[x] - 10 end

    local function Check(x, label, key, tooltip)
        local cb = UI.Checkbox(page, label, function(on)
            S()[key] = on
            ns:Fire("SETTINGS_CHANGED", key)
        end)
        cb:SetPoint("TOPLEFT", x, cursor[x])
        if tooltip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        cursor[x] = cursor[x] - 22
        table.insert(controls, function() cb:SetChecked(S()[key]) end)
        return cb
    end

    local function Choice(x, label, key, options, width, extra)
        local l = UI.Text(page, "GameFontHighlightSmall", label)
        l:SetPoint("TOPLEFT", x, cursor[x] - 3)
        local cy = UI.Cycler(page, width or 150, options, function(v)
            S()[key] = v
            ns:Fire("SETTINGS_CHANGED", key)
            if extra then extra(v) end
        end)
        cy:SetPoint("TOPLEFT", x + 130, cursor[x])
        cursor[x] = cursor[x] - 26
        table.insert(controls, function() cy:SetValue(S()[key]) end)
        return cy
    end

    local function Seconds(list, unit)
        local out = {}
        for _, v in ipairs(list) do
            local label
            if v == 0 then label = "Off"
            elseif unit == "min" then label = (v / 60) .. " min"
            else label = v .. " s" end
            table.insert(out, { v, label })
        end
        return out
    end

    ----------------------------------------------------------------------------
    -- Column 1: tracking + tooltip
    ----------------------------------------------------------------------------
    local X1, X2, X3 = 0, 300, 600
    local W = 280

    Column(X1, "Tracking", W)
    Check(X1, "Track Mythic+ keys", "trackMythicPlus")
    Check(X1, "Track dungeons", "trackDungeons", "Normal, heroic and mythic dungeons with a group.")
    Check(X1, "Track raids", "trackRaids")
    Check(X1, "Rate the group after a dungeon", "popupAfterDungeon",
        "Opens the group popup when a dungeon or key is completed. Never for raids; "
        .. "use Rate group... in the Runs tab for those.")
    Check(X1, "Also when a dungeon ends unfinished", "popupOnLeave",
        "Opens the popup when you leave the group or the dungeon without completing it.")
    Gap(X1)
    Choice(X1, "Popup auto-close", "popupAutoClose", Seconds({ 0, 30, 60, 120, 300 }), 120)
    Gap(X1)

    Column(X1, "Tooltips and menus", W)
    Check(X1, "Add history to player tooltips", "tooltipEnabled")
    Check(X1, "Show notes in tooltips", "tooltipShowNote")
    Check(X1, "Group finder tooltips", "lfgTooltips", "History for group leaders and applicants (retail).")
    Check(X1, "Add options to player right-click menus", "menuEnabled")

    ----------------------------------------------------------------------------
    -- Column 2: alerts
    ----------------------------------------------------------------------------
    Column(X2, "Alerts", W)
    Check(X2, "When a known player joins your group", "groupAlerts")
    Check(X2, "When a known player applies to your group", "lfgAlerts", "Group finder applicants (retail).")
    Check(X2, "When a known player is nearby", "proximityAlerts",
        "Nameplates, target, focus and mouseover, outside your group.")
    Check(X2, "Nearby alerts inside instances", "alertInInstances")
    Gap(X2)
    Check(X2, "Alert for Kick on sight", "alertKick")
    Check(X2, "Alert for Always invite", "alertInvite")
    Check(X2, "Alert for others you've played with", "alertHistory",
        "Players you've done runs with or written a note about, who are on no list.")
    Check(X2, "Also print alerts in chat", "alertChat")
    Gap(X2)
    Choice(X2, "Repeat after", "alertCooldown", Seconds({ 60, 120, 300, 600, 1800, 3600 }, "min"), 120)
    Choice(X2, "Show for", "alertDuration", Seconds({ 5, 10, 15, 30, 60 }), 120)
    Choice(X2, "Max at once", "alertMax", { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" } }, 120)
    Gap(X2)
    local test = UI.Button(page, "Test alerts", 100, 22, function() ns:TestAlert() end)
    test:SetPoint("TOPLEFT", X2, cursor[X2])
    local move = UI.Button(page, "Move alerts", 100, 22, function() ns:ToggleAlertAnchor() end)
    move:SetPoint("LEFT", test, "RIGHT", 6, 0)
    move.tooltip = "Toggle the draggable alert anchor"

    ----------------------------------------------------------------------------
    -- Column 3: sounds + data
    ----------------------------------------------------------------------------
    Column(X3, "Sounds", W - 4)
    Check(X3, "Play alert sounds", "soundsEnabled")
    Gap(X3)

    local soundOptions = {}
    for _, s in ipairs(ns.sounds) do table.insert(soundOptions, { s.key, s.label }) end

    local function SoundChoice(label, key)
        local l = UI.Text(page, "GameFontHighlightSmall", label)
        l:SetPoint("TOPLEFT", X3, cursor[X3] - 3)
        local cy = UI.Cycler(page, 150, soundOptions, function(v)
            S()[key] = v
            ns:PlayAlertSound(v)
        end)
        cy:SetPoint("TOPLEFT", X3 + 80, cursor[X3])
        local play = UI.Button(page, "Play", 40, 20, function() ns:PlayAlertSound(S()[key]) end)
        play:SetPoint("LEFT", cy, "RIGHT", 4, 0)
        cursor[X3] = cursor[X3] - 26
        table.insert(controls, function() cy:SetValue(S()[key]) end)
    end
    SoundChoice("|c" .. ns.LIST_INFO.kick.hex .. "Kick|r", "soundKick")
    SoundChoice("|c" .. ns.LIST_INFO.invite.hex .. "Invite|r", "soundInvite")
    SoundChoice(ns.pveColor .. "Played with|r", "soundHistory")

    local l = UI.Text(page, "GameFontHighlightSmall", "Channel")
    l:SetPoint("TOPLEFT", X3, cursor[X3] - 3)
    local channel = UI.Cycler(page, 150, {
        { "Master", "Master" }, { "SFX", "Effects" }, { "Dialog", "Dialog" }, { "Ambience", "Ambience" },
    }, function(v) S().soundChannel = v end)
    channel:SetPoint("TOPLEFT", X3 + 80, cursor[X3])
    cursor[X3] = cursor[X3] - 26
    table.insert(controls, function() channel:SetValue(S().soundChannel) end)
    Gap(X3)

    Column(X3, "Data", W - 4)
    local info = UI.Text(page, "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", X3, cursor[X3])
    info:SetWidth(W - 4)
    cursor[X3] = cursor[X3] - 34

    local reset = UI.ConfirmButton(page, "Delete all data", 120, 22, function()
        wipe(ns.db.players)
        wipe(ns.db.guilds)
        wipe(ns.db.runs)
        ns.activeRun = nil
        ns.db.activeRunID = nil
        ns:Fire("DATA_CHANGED", "reset")
        ns:Print("All history deleted.")
        page:Refresh()
    end)
    reset:SetPoint("TOPLEFT", X3, cursor[X3])
    reset.tooltip = "Deletes every player, guild and run. Settings are kept. Click twice."

    local footer = UI.Text(page, "GameFontDisableSmall",
        "Slash commands: /apve help   ·   Version " .. ns.version, "LEFT")
    footer:SetPoint("BOTTOMLEFT", 0, 0)

    function page:Refresh()
        for _, fn in ipairs(controls) do fn() end
        local players, guilds = 0, 0
        for _ in pairs(ns.db.players) do players = players + 1 end
        for _ in pairs(ns.db.guilds) do guilds = guilds + 1 end
        info:SetText(("%d players, %d guilds and %d runs stored."):format(players, guilds, #ns.db.runs))
    end
    page:SetScript("OnShow", function(self) self:Refresh() end)
end

ns:RegisterPage("settings", Build)

-- Entry in Esc > Options > AddOns that points at the real settings.
ns:Listen("LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = UI.Text(panel, "GameFontNormalLarge", "AndreddiPvE")
    title:SetPoint("TOPLEFT", 16, -16)
    local text = UI.Text(panel, "GameFontHighlight", "All settings live in the AndreddiPvE window.")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local b = UI.Button(panel, "Open settings", 140, 24, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns:ShowMainWindow("settings")
    end)
    b:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    pcall(function()
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AndreddiPvE")
        Settings.RegisterAddOnCategory(category)
    end)
end)
