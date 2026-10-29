local _, ns = ...
local SafeCall = ns.SafeCall

-- Adds an AndreddiPvE section to the right-click menu of players: portraits,
-- party and raid frames, chat names, guild and community rosters. Your own
-- portrait gets the group actions only.

local TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_RAID", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_CHAT_ROSTER",
}

--------------------------------------------------------------------------------
-- Note dialog
--------------------------------------------------------------------------------

local function EditBoxOf(dialog)
    return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

StaticPopupDialogs.ANDREDDIPVE_NOTE = {
    text = "AndreddiPvE note for %s",
    button1 = SAVE or ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 280,
    maxLetters = 255,
    OnShow = function(self, data)
        local key = data or self.data
        local p = ns:GetPlayer(key)
        local box = EditBoxOf(self)
        box:SetText(p and p.note or "")
        box:HighlightText()
    end,
    OnAccept = function(self, data)
        ns:SetPlayerNote(data or self.data, EditBoxOf(self):GetText())
    end,
    EditBoxOnEnterPressed = function(box, data)
        local dialog = box:GetParent()
        ns:SetPlayerNote(data or dialog.data, box:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns:EditNote(info)
    ns:TouchPlayer(info)
    StaticPopup_Show("ANDREDDIPVE_NOTE", ns:ShortName(info.key), nil, info.key)
end

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------

-- Player info for the clicked entry. Returns info, isSelf.
local function Resolve(contextData)
    if not contextData then return nil end
    local unit = contextData.unit
    if unit and SafeCall(UnitExists, unit) then
        if not SafeCall(UnitIsPlayer, unit) then return nil end
        if SafeCall(UnitIsUnit, unit, "player") then return nil, true end
        local info = ns:ReadUnit(unit)
        return info and ns:Remember(info)
    end
    local name = contextData.name
    if not name or name == "" then return nil end
    local text = name
    if ns:UsesSurnames() then
        text = ns:NameAndRealm(name, contextData.server)
    elseif contextData.server and contextData.server ~= "" and not name:find("-", 1, true) then
        text = name .. "-" .. contextData.server
    end
    local key = text and ns:FindPlayerKey(text)
    if not key then return nil end
    if key == ns:MyKey() then return nil, true end
    return ns:SeenByKey(key) or { key = key }
end

local function AddGroupButton(root)
    if not IsInGroup() then return end
    root:CreateButton(ns.activeRun and "Rate this group..." or "Log this group as a run", function()
        ns:LogGroup()
    end)
end

local function AddItems(_, root, contextData)
    if not ns.db or not ns.db.settings.menuEnabled then return end
    local info, isSelf = Resolve(contextData)
    if not info and not isSelf then return end

    root:CreateDivider()
    root:CreateTitle(ns.title)

    if isSelf then
        AddGroupButton(root)
        root:CreateButton("Open history", function() ns:ShowMainWindow("runs") end)
        return
    end

    local key = info.key
    local p = ns:GetPlayer(key)

    local list = p and p.list
    local listMenu = root:CreateButton("List" .. (list and (": " .. ns:ListTag(list)) or "..."))
    for _, l in ipairs(ns.LISTS) do
        local li = ns.LIST_INFO[l]
        listMenu:CreateRadio("|c" .. li.hex .. li.label .. "|r",
            function()
                local r = ns:GetPlayer(key)
                return r ~= nil and r.list == l
            end,
            function()
                ns:TouchPlayer(info)
                ns:SetPlayerList(key, l)
            end)
    end
    listMenu:CreateRadio("None",
        function()
            local r = ns:GetPlayer(key)
            return not (r and r.list)
        end,
        function()
            if ns:GetPlayer(key) then ns:SetPlayerList(key, nil) end
        end)

    local run = ns:LastRunWith(key)
    if run then
        local m = run.members[key]
        local rateMenu = root:CreateButton("Rate" .. (m.rating and (": " .. ns:RatingText(m.rating)) or "..."))
        rateMenu:CreateTitle(ns:RunTitle(run))
        for i = 1, 10 do
            rateMenu:CreateRadio(ns:RatingText(i),
                function()
                    local mm = run.members[key]
                    return mm ~= nil and mm.rating == i
                end,
                function() ns:SetRunRating(run, key, i) end)
        end
        rateMenu:CreateButton("Clear rating", function() ns:SetRunRating(run, key, nil) end)
    end

    root:CreateButton((p and p.note) and "Edit note..." or "Add note...", function() ns:EditNote(info) end)

    local active = ns.activeRun
    if not (active and active.members[key]) then
        root:CreateButton(active and "Add to current run" or "Add to history", function()
            local r = ns:AddToHistory(info)
            ns:Print(ns:ShortName(key), "added to", ns:RunTitle(r))
        end)
    end

    local unit = contextData.unit
    if unit and ns:InGroupWith(unit) then AddGroupButton(root) end

    root:CreateButton("Show history", function()
        ns:TouchPlayer(info)
        ns:ShowMainWindow("players", key)
    end)
end

local function Safely(owner, root, contextData)
    local ok, err = pcall(AddItems, owner, root, contextData)
    if not ok then ns:Debug("Menu error: " .. tostring(err)) end
end

ns:Listen("LOGIN", function()
    if not (Menu and Menu.ModifyMenu) then
        ns:Debug("No Menu.ModifyMenu on this client; right-click options are unavailable.")
        return
    end
    Menu.ModifyMenu("MENU_UNIT_SELF", Safely)
    for _, tag in ipairs(TAGS) do Menu.ModifyMenu(tag, Safely) end
end)
