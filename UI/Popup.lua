local _, ns = ...
local UI = ns.UI

-- Group popup: shown after a dungeon or key (and on demand for any run). Lists
-- every member with a 1-10 rating for this run, their list and a note. Runs
-- queue up when several finish close together.

local queue = {}
local popup
local WIDTH = 560
local ROW_HEIGHT = 50
local MAX_ROWS = 6
local HEADER, FOOTER = 52, 40

local function CurrentRun() return queue[1] end

-- Commits a note being typed before rows are reused or the popup closes.
local function CommitNotes()
    for _, row in ipairs(popup.list.rows) do
        if row.note:HasFocus() then row.note:ClearFocus() end
    end
end

local function AnyNoteFocused()
    for _, row in ipairs(popup.list.rows) do
        if row.note:HasFocus() then return true end
    end
    return false
end

local function Touch()
    local run = CurrentRun()
    if run then popup.touched = true end
end

local function BuildRow(row)
    row.name = UI.Text(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 6, -6)
    row.name:SetWidth(170)
    row.name:SetWordWrap(false)

    row.info = UI.Text(row, "GameFontDisableSmall")
    row.info:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.info:SetPoint("RIGHT", -214, 0)
    row.info:SetWordWrap(false)

    row.list = UI.ListSelector(row, function(list)
        if row.item then ns:SetPlayerList(row.item.key, list) end
        Touch()
    end, 48)
    row.list:SetPoint("TOPRIGHT", -4, -4)

    row.rating = UI.RatingBar(row, function(value)
        if row.item then ns:SetRunRating(row.item.run, row.item.key, value) end
        Touch()
    end, 18)
    row.rating:SetPoint("BOTTOMLEFT", 6, 5)

    -- The note belongs to whoever the row showed when typing started.
    row.note = UI.EditBox(row, 200, 20, function(text)
        if row.note.editingKey then ns:SetPlayerNote(row.note.editingKey, text) end
    end)
    row.note:SetPlaceholder("Note about this player (Enter to save)")
    row.note:SetPoint("LEFT", row.rating, "RIGHT", 8, 0)
    row.note:SetPoint("RIGHT", -4, 0)
    row.note:HookScript("OnEditFocusGained", function(self)
        self.editingKey = row.item and row.item.key
        Touch()
    end)
end

local function UpdateRow(row, item)
    local m, run = item.m, item.run
    local p = ns:GetPlayer(item.key) or {}
    local icon = ns:RoleIcon(m.role)
    row.name:SetText((icon ~= "" and (icon .. " ") or "") .. ns:ColoredName(item.key, m.class or p.class))

    local bits = {}
    if (m.deaths or 0) > 0 then table.insert(bits, m.deaths == 1 and "1 death" or (m.deaths .. " deaths")) end
    if ns:LeftEarly(run, m) then table.insert(bits, "|cffff8040left early|r") end
    local before = 0
    for _, r in ipairs(ns:PlayerSummary(item.key).runs) do
        if r ~= run and r.t < run.t then before = before + 1 end
    end
    if before > 0 then table.insert(bits, "|cffd4a017" .. before .. " runs before|r") end
    local list, source = ns:EffectiveList(item.key, m.guildKey)
    if list and source == "guild" then table.insert(bits, ns:ListTag(list) .. " |cff777777guild|r") end
    row.info:SetText(table.concat(bits, "  "))

    row.list:SetValue(p.list)
    row.rating:SetValue(m.rating)
    if not row.note:HasFocus() then row.note:SetText(p.note or "") end
end

local function Build()
    popup = UI.CreateWindow("AndreddiPvEPopup", "", WIDTH, 300, "popup")
    popup:SetFrameStrata("DIALOG")
    popup.closeButton:SetScript("OnClick", function() ns:ClosePopup() end)

    popup.counter = UI.Text(popup, "GameFontDisableSmall", "", "RIGHT")
    popup.counter:SetPoint("TOPRIGHT", -30, -12)

    popup.sub = UI.Text(popup, "GameFontHighlightSmall")
    popup.sub:SetPoint("TOPLEFT", 12, -30)
    popup.sub:SetPoint("RIGHT", -12, 0)
    popup.sub:SetWordWrap(false)

    popup.list = UI.ScrollList(popup, ROW_HEIGHT, BuildRow, UpdateRow)
    popup.list:SetPoint("TOPLEFT", 12, -HEADER + 4)
    popup.list:SetPoint("BOTTOMRIGHT", -12, FOOTER)
    popup.list:SetEmptyText("Nobody in this run")
    -- Scrolling reuses rows; save a half-typed note first.
    popup.list:SetScript("OnMouseWheel", function(self, delta)
        CommitNotes()
        local _, max = self.slider:GetMinMaxValues()
        self.slider:SetValue(math.max(0, math.min(max, self.offset - delta)))
    end)

    popup.open = UI.Button(popup, "Open run", 90, 20, function()
        local run = CurrentRun()
        if run then ns:ShowMainWindow("runs", run.id) end
    end)
    popup.open:SetPoint("BOTTOMLEFT", 12, 10)

    popup.dismiss = UI.Button(popup, "Close", 80, 20, function() ns:ClosePopup() end)
    popup.dismiss:SetPoint("BOTTOMRIGHT", -12, 10)

    popup.timer = UI.Text(popup, "GameFontDisableSmall", "", "RIGHT")
    popup.timer:SetPoint("RIGHT", popup.dismiss, "LEFT", -8, 0)

    popup:SetScript("OnUpdate", function(self, elapsed)
        local limit = ns.db.settings.popupAutoClose or 0
        if not CurrentRun() or limit <= 0 or self.touched then
            self.timer:SetText("")
            return
        end
        if self:IsMouseOver() then
            self.touched = true
            self.timer:SetText("")
            return
        end
        self.remaining = (self.remaining or limit) - elapsed
        self.timer:SetText(("closes in %d"):format(math.ceil(self.remaining)))
        if self.remaining <= 0 then ns:ClosePopup() end
    end)

    UI.RestorePosition(popup, { "TOP", UIParent, "TOP", 0, -140 })
end

function ns:RefreshPopup()
    if not popup then return end
    local run = CurrentRun()
    if not run then
        popup:Hide()
        return
    end
    popup.counter:SetText(#queue > 1 and ("1 of " .. #queue) or "")
    popup.title:SetText(ns.pveColor .. ns:RunTitle(run) .. "|r  |cff999999rate your group|r")

    local bits = { ns:RunResult(run) }
    local len = ns:RunLength(run)
    if len then table.insert(bits, ns:Duration(len)) end
    if run.kind ~= "manual" then table.insert(bits, ns:BossText(run)) end
    if (run.wipes or 0) > 0 then table.insert(bits, run.wipes .. (run.wipes == 1 and " wipe" or " wipes")) end
    table.insert(bits, "|cff999999" .. ns:FormatTime(run.t) .. "|r")
    popup.sub:SetText(table.concat(bits, "  ·  "))

    local items = ns:SortedMembers(run)
    local rows = math.max(1, math.min(#items, MAX_ROWS))
    popup:SetHeight(HEADER + rows * ROW_HEIGHT + 4 + FOOTER)
    popup.list:SetData(items)
    popup:Show()
end

function ns:QueueRunPopup(run)
    if not popup then Build() end
    for _, r in ipairs(queue) do
        if r == run then
            ns:RefreshPopup()
            return
        end
    end
    table.insert(queue, run)
    if #queue == 1 then
        popup.touched, popup.remaining = false, nil
        popup.list.offset = 0
    end
    ns:RefreshPopup()
end

function ns:ClosePopup()
    if not popup then return end
    CommitNotes()
    table.remove(queue, 1)
    popup.touched, popup.remaining = false, nil
    popup.list.offset = 0
    ns:RefreshPopup()
end

-- Keep the popup in sync when the data is changed from elsewhere, but leave
-- a note being typed alone.
ns:Listen("DATA_CHANGED", function(kind, id)
    if not popup or not popup:IsShown() or AnyNoteFocused() then return end
    local run = CurrentRun()
    if kind == "run" and run and id == run.id and not ns:GetRun(id) then
        -- The run was deleted.
        ns:ClosePopup()
        return
    end
    ns:RefreshPopup()
end)
