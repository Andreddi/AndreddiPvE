local _, ns = ...
local UI = ns.UI

-- Main window: Runs / Players / Guilds / Statistics / Settings tabs.
-- The first three share a table layout with a detail panel on the right.

local win
local pages = {}
local pageBuilders = {}
local currentTab

local WIDTH, HEIGHT = 900, 540
local DETAIL_WIDTH = 300

local TABS = {
    { key = "runs",     label = "Runs" },
    { key = "players",  label = "Players" },
    { key = "guilds",   label = "Guilds" },
    { key = "stats",    label = "Statistics", width = 90 },
    { key = "settings", label = "Settings" },
}

-- Other files register full-width pages (stats, settings) here.
function ns:RegisterPage(key, builder)
    pageBuilders[key] = builder
end

local function Lower(s) return s and s:lower() or "" end

local function Matches(search, ...)
    if search == "" then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and Lower(v):find(search, 1, true) then return true end
    end
    return false
end

local function ListText(list)
    return list and ns:ListTag(list) or ""
end

--------------------------------------------------------------------------------
-- Detail panel (player, guild or run)
--------------------------------------------------------------------------------

local detail

local function BuildRecordDetail(d)
    local c = CreateFrame("Frame", nil, d)
    c:SetPoint("TOPLEFT", 10, -10)
    c:SetPoint("BOTTOMRIGHT", -10, 10)

    c.name = UI.Text(c, "GameFontNormalLarge")
    c.name:SetPoint("TOPLEFT")
    c.name:SetPoint("RIGHT")
    c.sub = UI.Text(c, "GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.sub:SetPoint("RIGHT")

    c.guildButton = UI.Button(c, "", 200, 18, function(self)
        if self.guildKey then ns:ShowMainWindow("guilds", self.guildKey) end
    end)
    c.guildButton:SetPoint("TOPLEFT", c.sub, "BOTTOMLEFT", 0, -6)
    c.guildButton.tooltip = "Open guild"

    c.record = UI.Text(c, "GameFontHighlight")
    c.record:SetPoint("TOPLEFT", c.guildButton, "BOTTOMLEFT", 0, -10)
    c.record:SetPoint("RIGHT")
    c.seen = UI.Text(c, "GameFontDisableSmall")
    c.seen:SetPoint("TOPLEFT", c.record, "BOTTOMLEFT", 0, -4)
    c.seen:SetPoint("RIGHT")
    c.seen:SetSpacing(2)

    c.listLabel = UI.Text(c, "GameFontNormalSmall", "List")
    c.listLabel:SetPoint("TOPLEFT", c.seen, "BOTTOMLEFT", 0, -12)
    c.list = UI.ListSelector(c, function(list)
        if d.kind == "player" then ns:SetPlayerList(d.key, list) else ns:SetGuildList(d.key, list) end
    end, 66)
    c.list:SetPoint("TOPLEFT", c.listLabel, "BOTTOMLEFT", 0, -4)
    c.inherited = UI.Text(c, "GameFontDisableSmall")
    c.inherited:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 0, -3)

    c.noteLabel = UI.Text(c, "GameFontNormalSmall", "Note")
    c.noteLabel:SetPoint("TOPLEFT", c.list, "BOTTOMLEFT", 0, -18)
    c.note = UI.EditBox(c, DETAIL_WIDTH - 20, 22, function(text)
        if not d.key then return end
        if d.kind == "player" then ns:SetPlayerNote(d.key, text) else ns:SetGuildNote(d.key, text) end
    end)
    c.note:SetPlaceholder("Something to remember (Enter to save)")
    c.note:SetPoint("TOPLEFT", c.noteLabel, "BOTTOMLEFT", 0, -4)

    -- Player only: rating for the last run together.
    c.rateLabel = UI.Text(c, "GameFontNormalSmall", "")
    c.rateLabel:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -12)
    c.rateLabel:SetPoint("RIGHT")
    c.rateLabel:SetWordWrap(false)
    c.rating = UI.RatingBar(c, function(value)
        if d.kind == "player" and c.rating.run then ns:SetRunRating(c.rating.run, d.key, value) end
    end, 20)
    c.rating:SetPoint("TOPLEFT", c.rateLabel, "BOTTOMLEFT", 0, -4)

    c.recentLabel = UI.Text(c, "GameFontNormalSmall", "Recent runs")
    c.recent = UI.Text(c, "GameFontHighlightSmall")
    c.recent:SetPoint("TOPLEFT", c.recentLabel, "BOTTOMLEFT", 0, -4)
    c.recent:SetPoint("RIGHT")
    c.recent:SetSpacing(3)
    c.recent:SetJustifyV("TOP")

    c.delete = UI.ConfirmButton(c, "Delete", 80, 20, function()
        if d.kind == "player" then ns:DeletePlayer(d.key) else ns:DeleteGuild(d.key) end
        ns:ShowDetail(nil)
    end)
    c.delete:SetPoint("BOTTOMRIGHT")
    return c
end

local function BuildRunDetail(d)
    local r = CreateFrame("Frame", nil, d)
    r:SetPoint("TOPLEFT", 10, -10)
    r:SetPoint("BOTTOMRIGHT", -10, 10)

    r.name = UI.Text(r, "GameFontNormalLarge")
    r.name:SetPoint("TOPLEFT")
    r.name:SetPoint("RIGHT")
    r.sub = UI.Text(r, "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT")
    r.result = UI.Text(r, "GameFontHighlight")
    r.result:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -8)
    r.result:SetPoint("RIGHT")
    r.bosses = UI.Text(r, "GameFontDisableSmall")
    r.bosses:SetPoint("TOPLEFT", r.result, "BOTTOMLEFT", 0, -4)
    r.bosses:SetPoint("RIGHT")
    r.bosses:SetSpacing(2)
    if r.bosses.SetMaxLines then r.bosses:SetMaxLines(4) end

    r.groupLabel = UI.Text(r, "GameFontNormalSmall", "Group")
    r.groupLabel:SetPoint("TOPLEFT", r.bosses, "BOTTOMLEFT", 0, -12)

    r.members = UI.ScrollList(r, 18, function(row)
        row.name = UI.Text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetWidth(150)
        row.name:SetWordWrap(false)
        row.extra = UI.Text(row, "GameFontDisableSmall")
        row.extra:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
        row.extra:SetPoint("RIGHT", -34, 0)
        row.extra:SetWordWrap(false)
        row.rating = UI.Text(row, "GameFontHighlightSmall", "", "RIGHT")
        row.rating:SetPoint("RIGHT", -4, 0)
    end, function(row, item)
        local m = item.m
        local icon = ns:RoleIcon(m.role)
        local list = ns:EffectiveList(item.key, m.guildKey)
        row.name:SetText((icon ~= "" and (icon .. " ") or "") .. ns:ColoredName(item.key, m.class)
            .. (list and (" " .. ns:ListTag(list)) or ""))
        local bits = {}
        if (m.deaths or 0) > 0 then table.insert(bits, m.deaths .. "x dead") end
        if ns:LeftEarly(item.run, m) then table.insert(bits, "|cffff8040left|r") end
        row.extra:SetText(table.concat(bits, " "))
        row.rating:SetText(m.rating and ns:RatingText(m.rating) or "")
    end, function(_, item)
        ns:ShowMainWindow("players", item.key)
    end)
    r.members:SetPoint("TOPLEFT", r.groupLabel, "BOTTOMLEFT", 0, -4)
    r.members:SetPoint("BOTTOMRIGHT", 0, 28)
    r.members:SetEmptyText("Nobody recorded")

    r.rate = UI.Button(r, "Rate group...", 100, 20, function()
        local run = ns:GetRun(d.key)
        if run then ns:QueueRunPopup(run) end
    end)
    r.rate:SetPoint("BOTTOMLEFT")
    r.rate.tooltip = "Rate everyone in this run, set lists and notes"

    r.delete = UI.ConfirmButton(r, "Delete run", 90, 20, function()
        local run = ns:GetRun(d.key)
        if run then ns:DeleteRun(run) end
        ns:ShowDetail(nil)
    end)
    r.delete:SetPoint("BOTTOMRIGHT")
    r.delete.tooltip = "Delete this run. Players and their notes and lists are kept."
    return r
end

local function BuildDetail(parent)
    local d = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetBackdrop(d, UI.colors.panel)
    d:SetWidth(DETAIL_WIDTH)
    d:SetPoint("TOPRIGHT", -12, -62)
    d:SetPoint("BOTTOMRIGHT", -12, 12)

    d.empty = UI.Text(d, "GameFontDisable", "Select a run, player or guild", "CENTER")
    d.empty:SetPoint("CENTER")

    d.content = BuildRecordDetail(d)
    d.runContent = BuildRunDetail(d)
    d.kind, d.key = nil, nil
    return d
end

local function RecentRunLines(key, max)
    local out = {}
    local runs = ns:PlayerSummary(key).runs
    for i = #runs, math.max(1, #runs - max + 1), -1 do
        local run = runs[i]
        local m = run.members[key]
        local line = date("%m-%d", run.t) .. "  " .. ns:RunTitle(run) .. "  " .. ns:RunResult(run)
        if m and m.rating then line = line .. "  " .. ns:RatingText(m.rating) end
        if m and ns:LeftEarly(run, m) then line = line .. "  |cffff8040left|r" end
        table.insert(out, line)
    end
    return out
end

local function ShowRun(run)
    local r = detail.runContent
    r.name:SetText(ns.pveColor .. ns:RunTitle(run) .. "|r")
    local kind = ns.KIND_INFO[run.kind]
    local bits = { kind and kind.label or run.kind, ns:FormatTime(run.t) }
    local len = ns:RunLength(run)
    if len then table.insert(bits, ns:Duration(len)) end
    if run.me then table.insert(bits, "|cff999999" .. ns:ShortName(run.me) .. "|r") end
    r.sub:SetText(table.concat(bits, "   "))

    local res = { ns:RunResult(run) }
    if run.kind ~= "manual" then
        table.insert(res, ns:BossText(run))
        if (run.wipes or 0) > 0 then table.insert(res, run.wipes .. (run.wipes == 1 and " wipe" or " wipes")) end
        if (run.myDeaths or 0) > 0 then table.insert(res, "you died " .. run.myDeaths .. "x") end
    end
    r.result:SetText(table.concat(res, "  ·  "))

    local names = {}
    for _, b in ipairs(run.bosses) do table.insert(names, b.name or "?") end
    r.bosses:SetText(#names > 0 and table.concat(names, ", ") or "")

    r.members:SetData(ns:SortedMembers(run))
end

function ns:ShowDetail(kind, key)
    if not detail then return end
    local c, r = detail.content, detail.runContent
    -- Commit a half-typed note to the record it belongs to before switching.
    if c.note:HasFocus() then c.note:ClearFocus() end
    detail.kind, detail.key = kind, key
    local rec
    if kind == "player" then rec = ns:GetPlayer(key)
    elseif kind == "guild" then rec = ns:GetGuild(key)
    elseif kind == "run" then rec = ns:GetRun(key) end
    if not rec then
        detail.kind, detail.key = nil, nil
        c:Hide()
        r:Hide()
        detail.empty:Show()
        return
    end
    detail.empty:Hide()
    c:SetShown(kind ~= "run")
    r:SetShown(kind == "run")

    if kind == "run" then
        ShowRun(rec)
    elseif kind == "player" then
        local _, _, _, hex = ns:ClassColor(rec.class)
        c.name:SetText("|c" .. hex .. ns:ShortName(key) .. "|r")
        local bits = {}
        if rec.level then table.insert(bits, "Level " .. rec.level) end
        if rec.race then table.insert(bits, rec.race) end
        if rec.class then table.insert(bits, ns:ClassName(rec.class)) end
        if rec.faction then table.insert(bits, "|cff999999" .. rec.faction .. "|r") end
        c.sub:SetText(#bits > 0 and table.concat(bits, " ") or "|cff999999Unknown level and class|r")
        local g = ns:GetGuild(rec.guildKey)
        if rec.guildKey then
            c.guildButton:SetText("<" .. (rec.guild or ns:ShortName(rec.guildKey)) .. ">" .. (g and g.list and (" " .. ns:ListTag(g.list)) or ""))
            c.guildButton.guildKey = rec.guildKey
            c.guildButton:Show()
            c.guildButton:SetHeight(18)
        else
            c.guildButton:Hide()
            c.guildButton:SetHeight(1)
        end
        local s = ns:PlayerSummary(key)
        local rating = s.rating and ("   Rating " .. ns:RatingText(s.rating) .. " |cff999999(" .. s.ratingN .. ")|r") or ""
        c.record:SetText("Runs together: " .. #s.runs .. rating)
        local last = s.runs[#s.runs]
        c.seen:SetText(("Completed %d   Deaths in your runs %d\nFirst seen %s   Last run %s"):format(
            s.completed, s.deaths, date("%Y-%m-%d", rec.firstSeen or time()), last and ns:Ago(last.t) or "never"))
        c.list:SetValue(rec.list)
        if not rec.list and g and g.list then
            c.inherited:SetText("Inherits " .. ns.LIST_INFO[g.list].label .. " from guild")
        else
            c.inherited:SetText("")
        end
        c.note:SetText(rec.note or "")

        c.rating.run = last
        c.rateLabel:SetShown(last ~= nil)
        c.rating:SetShown(last ~= nil)
        if last then
            c.rateLabel:SetText("Rating for " .. ns:RunTitle(last))
            c.rating:SetValue(last.members[key] and last.members[key].rating)
            c.recentLabel:SetPoint("TOPLEFT", c.rating, "BOTTOMLEFT", 0, -14)
        else
            c.recentLabel:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -12)
        end
        c.recentLabel:SetText("Recent runs")
        local lines = RecentRunLines(key, 8)
        c.recent:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff777777None yet. Right-click them and choose Add to history.|r")
        c.delete.tooltip = "Delete this player and remove them from every run"
    else
        c.name:SetText("|cffd4a017<" .. rec.name .. ">|r")
        local members = 0
        for _ in pairs(rec.members or {}) do members = members + 1 end
        c.sub:SetText((rec.realm or "") .. "   " .. members .. " known members")
        c.guildButton:Hide()
        c.guildButton:SetHeight(1)
        local gs = ns:GuildSummary(key)
        local rating = gs.rating and ("   Rating " .. ns:RatingText(gs.rating) .. " |cff999999(" .. gs.ratingN .. ")|r") or ""
        c.record:SetText("Runs with members: " .. gs.runs .. rating)
        c.seen:SetText("First seen " .. ns:FormatTime(rec.firstSeen or time()) .. "\nLast run " .. (gs.last and ns:Ago(gs.last.t) or "never"))
        c.list:SetValue(rec.list)
        c.inherited:SetText(rec.list and "Applies to every member without their own list" or "")
        c.note:SetText(rec.note or "")
        c.rateLabel:Hide()
        c.rating:Hide()
        c.recentLabel:SetPoint("TOPLEFT", c.note, "BOTTOMLEFT", 0, -12)

        -- Members ranked by runs together.
        local ranked = {}
        for mkey in pairs(rec.members or {}) do
            local p = ns:GetPlayer(mkey)
            if p then table.insert(ranked, { key = mkey, p = p, s = ns:PlayerSummary(mkey) }) end
        end
        table.sort(ranked, function(a, b)
            if #a.s.runs ~= #b.s.runs then return #a.s.runs > #b.s.runs end
            return a.key < b.key
        end)
        local lines = {}
        for i = 1, math.min(8, #ranked) do
            local m = ranked[i]
            table.insert(lines, ns:ColoredName(m.key, m.p.class) .. "  " .. #m.s.runs .. " runs  "
                .. (m.s.rating and ns:RatingText(m.s.rating) or "") .. " " .. ListText(m.p.list))
        end
        c.recentLabel:SetText("Members you've played with")
        c.recent:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff777777None yet|r")
        c.delete.tooltip = "Delete the guild record (list, note). Players and runs are kept."
    end

    for _, page in pairs(pages) do
        if page.list then page.list:Refresh() end
    end
end

--------------------------------------------------------------------------------
-- Table pages
--------------------------------------------------------------------------------

-- spec: { columns = { {title, width, justify} }, rows = fn(search, filter, sort) -> items,
--         cells = fn(item) -> { strings }, select = fn(item), isSelected = fn(item),
--         filters = { {key,label,width} }, sorts = { {key,label} }, footer = fn(page) }
local function BuildTablePage(parent, spec)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 12, -62)
    page:SetPoint("BOTTOMRIGHT", -(12 + DETAIL_WIDTH + 8), 12)
    page.filter = spec.filters and spec.filters[1][1] or nil
    page.sort = spec.sorts and spec.sorts[1][1] or nil

    page.search = UI.EditBox(page, 150, 22)
    page.search:SetPlaceholder("Search...")
    page.search:SetPoint("TOPLEFT")
    page.search:HookScript("OnTextChanged", function() page:Refresh() end)

    local x = 158
    if spec.filters then
        page.filterButtons = {}
        for _, f in ipairs(spec.filters) do
            local b = UI.Button(page, f[2], f[3] or 58, 22, function()
                page.filter = f[1]
                page:Refresh()
            end)
            b:SetPoint("TOPLEFT", x, 0)
            b.key = f[1]
            x = x + (f[3] or 58) + 3
            table.insert(page.filterButtons, b)
        end
    end
    if spec.sorts then
        page.sorter = UI.Cycler(page, 110, spec.sorts, function(v)
            page.sort = v
            page:Refresh()
        end)
        page.sorter:SetPoint("TOPRIGHT", 0, -1)
        page.sorter:SetValue(page.sort)
    end

    -- Column header
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", 0, -28)
    header:SetPoint("TOPRIGHT", 0, -28)
    header:SetHeight(18)
    local hx = 6
    for _, col in ipairs(spec.columns) do
        local t = UI.Text(header, "GameFontNormalSmall", col[1], col[3])
        t:SetPoint("LEFT", hx, 0)
        if col[2] then t:SetWidth(col[2]) else t:SetPoint("RIGHT", -14, 0) end
        hx = hx + (col[2] or 0) + 4
    end

    local function BuildRow(row)
        row.cells = {}
        local cx = 4
        for i, col in ipairs(spec.columns) do
            local t = UI.Text(row, "GameFontHighlightSmall", "", col[3])
            t:SetPoint("LEFT", cx, 0)
            if col[2] then t:SetWidth(col[2]) else t:SetPoint("RIGHT", -4, 0) end
            t:SetWordWrap(false)
            row.cells[i] = t
            cx = cx + (col[2] or 0) + 4
        end
    end
    local function UpdateRow(row, item)
        local cells = spec.cells(item)
        for i, t in ipairs(row.cells) do t:SetText(cells[i] or "") end
    end

    page.list = UI.ScrollList(page, 18, BuildRow, UpdateRow, function(_, item)
        spec.select(item)
    end)
    page.list:SetPoint("TOPLEFT", 0, -48)
    page.list:SetPoint("BOTTOMRIGHT", 0, spec.footer and 32 or 0)
    page.list.isSelected = spec.isSelected
    page.list:SetEmptyText(spec.emptyText or "Nothing here yet")

    page.count = UI.Text(page, "GameFontDisableSmall", "", "RIGHT")
    page.count:SetPoint("BOTTOMRIGHT", page.list, "TOPRIGHT", -4, 4)

    function page:Refresh()
        local search = Lower(strtrim(self.search:GetText() or ""))
        local items = spec.rows(search, self.filter, self.sort)
        self.list:SetData(items)
        self.count:SetText(#items .. " shown")
        if self.filterButtons then
            for _, b in ipairs(self.filterButtons) do b:SetActive(b.key == self.filter) end
        end
    end

    if spec.footer then spec.footer(page) end
    return page
end

--------------------------------------------------------------------------------
-- Runs page
--------------------------------------------------------------------------------

local function GroupText(run)
    local names = {}
    for _, item in ipairs(ns:SortedMembers(run)) do
        table.insert(names, ns:ColoredName(item.key, item.m.class))
    end
    return table.concat(names, " ")
end

local function BuildRuns(parent)
    return BuildTablePage(parent, {
        columns = {
            { "When", 84 }, { "Type", 46 }, { "Instance", 150 }, { "Result", 76 }, { "Group", nil },
        },
        filters = {
            { "all", "All", 36 }, { "mplus", "M+", 34 }, { "dungeon", "Dungeons", 64 },
            { "raid", "Raids", 46 }, { "manual", "Logged", 52 }, { "me", "This char", 64 },
        },
        emptyText = "No runs yet. Join a group and head into a dungeon!",
        rows = function(search, filter)
            local out = {}
            local me = ns:MyKey()
            local runs = ns.db.runs
            for i = #runs, 1, -1 do
                local run = runs[i]
                if filter == "all" or run.kind == filter or (filter == "me" and run.me == me) then
                    local ok = search == "" or Matches(search, run.instance, run.difficulty)
                    if not ok then
                        for key in pairs(run.members) do
                            if Matches(search, key) then ok = true break end
                        end
                    end
                    if ok then table.insert(out, run) end
                end
            end
            return out
        end,
        cells = function(run)
            local kind = ns.KIND_INFO[run.kind]
            return {
                date("%y-%m-%d %H:%M", run.t),
                kind and kind.short or "",
                ns:RunTitle(run),
                ns:RunResult(run),
                GroupText(run),
            }
        end,
        select = function(run) ns:ShowDetail("run", run.id) end,
        isSelected = function(run) return detail.kind == "run" and detail.key == run.id end,
        footer = function(page)
            local log = UI.Button(page, "Log current group", 130, 22, function() ns:LogGroup() end)
            log:SetPoint("BOTTOMLEFT")
            log.tooltip = "Save your current group as a run (or rate the run being tracked)"
            local hint = UI.Text(page, "GameFontDisableSmall",
                "Right-click a player's portrait for lists, ratings and notes", "RIGHT")
            hint:SetPoint("BOTTOMRIGHT", 0, 6)
        end,
    })
end

--------------------------------------------------------------------------------
-- Players page
--------------------------------------------------------------------------------

local LIST_FILTERS = {
    { "all", "All", 36 }, { "invite", "Invite", 50 }, { "kick", "Kick", 40 }, { "ignore", "Ignore", 50 },
}

-- items: { key, rec, s (summary with .runs list or count, .rating, .last) }
local function SortRecords(out, sort)
    local function Count(s) return type(s.runs) == "table" and #s.runs or s.runs end
    local function Last(item)
        local s = item.s
        local last = type(s.runs) == "table" and s.runs[#s.runs] or s.last
        return last and last.t or 0
    end
    table.sort(out, function(a, b)
        if sort == "runs" and Count(a.s) ~= Count(b.s) then return Count(a.s) > Count(b.s) end
        if sort == "best" or sort == "worst" then
            local ra, rb = a.s.rating, b.s.rating
            if ra and not rb then return true end
            if rb and not ra then return false end
            if ra and rb and ra ~= rb then
                if sort == "best" then return ra > rb end
                return ra < rb
            end
        end
        if sort == "name" then return a.key < b.key end
        local la, lb = Last(a), Last(b)
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
end

local SORTS = {
    { "recent", "Last run" }, { "runs", "Most runs" }, { "best", "Best rated" },
    { "worst", "Worst rated" }, { "name", "Name" },
}

local function AddByNameFooter(page, label, placeholder, onAdd)
    local box = UI.EditBox(page, 180, 22)
    box:SetPlaceholder(placeholder)
    box:SetPoint("BOTTOMLEFT")
    local function Add()
        local text = strtrim(box:GetText() or "")
        if text == "" then return end
        onAdd(text)
        box:SetText("")
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Add)
    local b = UI.Button(page, label, 90, 22, Add)
    b:SetPoint("LEFT", box, "RIGHT", 4, 0)
    return box
end

local function BuildPlayers(parent)
    return BuildTablePage(parent, {
        columns = {
            { "Player", 126 }, { "Lvl", 24, "CENTER" }, { "Guild", 96 }, { "Runs", 34, "CENTER" },
            { "Rating", 40, "CENTER" }, { "List", 48 }, { "Last run", nil },
        },
        filters = LIST_FILTERS,
        sorts = SORTS,
        emptyText = "No players yet",
        rows = function(search, filter, sort)
            local out = {}
            for key, p in pairs(ns.db.players) do
                local list = ns:EffectiveList(key, p.guildKey)
                if (filter == "all" or list == filter) and Matches(search, key, p.guild, p.note, ns:ClassName(p.class)) then
                    table.insert(out, { key = key, rec = p, s = ns:PlayerSummary(key) })
                end
            end
            SortRecords(out, sort)
            return out
        end,
        cells = function(item)
            local p, s = item.rec, item.s
            local list, source = ns:EffectiveList(item.key, p.guildKey)
            local listText = ListText(list)
            if source == "guild" then listText = listText .. "|cff777777*|r" end
            local last = s.runs[#s.runs]
            return {
                ns:ColoredName(item.key, p.class) .. (p.note and " |cffffd100*|r" or ""),
                p.level and tostring(p.level) or "",
                p.guild or "",
                tostring(#s.runs),
                s.rating and ns:RatingText(s.rating) or "",
                listText,
                last and ns:Ago(last.t) or "|cff777777never|r",
            }
        end,
        select = function(item) ns:ShowDetail("player", item.key) end,
        isSelected = function(item) return detail.kind == "player" and detail.key == item.key end,
        footer = function(page)
            AddByNameFooter(page, "Add player", ns:UsesSurnames() and "First and last name" or "Name or Name-Realm", function(text)
                local key = ns:FindPlayerKey(text)
                ns:TouchPlayer(ns:SeenByKey(key) or { key = key })
                ns:Fire("DATA_CHANGED", "player", key)
                ns:ShowDetail("player", key)
            end)
            local hint = UI.Text(page, "GameFontDisableSmall", "* note    |cff777777*|r list from guild", "RIGHT")
            hint:SetPoint("BOTTOMRIGHT", 0, 6)
        end,
    })
end

--------------------------------------------------------------------------------
-- Guilds page
--------------------------------------------------------------------------------

local function BuildGuilds(parent)
    return BuildTablePage(parent, {
        columns = {
            { "Guild", 150 }, { "List", 52 }, { "Runs", 40, "CENTER" }, { "Rating", 44, "CENTER" },
            { "Members", 54, "CENTER" }, { "Last run", nil },
        },
        filters = LIST_FILTERS,
        sorts = SORTS,
        emptyText = "No guilds yet",
        rows = function(search, filter, sort)
            local out = {}
            for key, g in pairs(ns.db.guilds) do
                if (filter == "all" or g.list == filter) and Matches(search, g.name, g.note) then
                    table.insert(out, { key = key, rec = g, s = ns:GuildSummary(key) })
                end
            end
            SortRecords(out, sort)
            return out
        end,
        cells = function(item)
            local g, s = item.rec, item.s
            local members = 0
            for _ in pairs(g.members or {}) do members = members + 1 end
            return {
                "|cffd4a017" .. g.name .. "|r" .. (g.note and " |cffffd100*|r" or ""),
                ListText(g.list),
                tostring(s.runs),
                s.rating and ns:RatingText(s.rating) or "",
                tostring(members),
                s.last and ns:Ago(s.last.t) or "|cff777777never|r",
            }
        end,
        select = function(item) ns:ShowDetail("guild", item.key) end,
        isSelected = function(item) return detail.kind == "guild" and detail.key == item.key end,
        footer = function(page)
            AddByNameFooter(page, "Add guild", "Exact guild name", function(text)
                local gkey = ns:GuildKey(text, nil)
                ns:TouchGuild(gkey)
                ns:Fire("DATA_CHANGED", "guild", gkey)
                ns:ShowDetail("guild", gkey)
            end)
        end,
    })
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function Build()
    win = UI.CreateWindow("AndreddiPvEMainWindow", "AndreddiPvE", WIDTH, HEIGHT, "main")
    win.title:SetText(ns.title .. "  |cff777777dungeon and raid history|r")

    win.summary = UI.Text(win, "GameFontHighlightSmall", "", "RIGHT")
    win.summary:SetPoint("TOPRIGHT", -36, -12)

    win.tabs = UI.TabBar(win, TABS, function(key) ns:ShowMainWindow(key) end)
    win.tabs:SetPoint("TOPLEFT", 12, -32)

    detail = BuildDetail(win)
    pages.runs = BuildRuns(win)
    pages.players = BuildPlayers(win)
    pages.guilds = BuildGuilds(win)
    for key, builder in pairs(pageBuilders) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", 12, -62)
        page:SetPoint("BOTTOMRIGHT", -12, 12)
        builder(page)
        pages[key] = page
    end
    for _, page in pairs(pages) do page:Hide() end
    ns:ShowDetail(nil)

    win:SetScript("OnShow", function() ns:RefreshMainWindow() end)
    UI.RestorePosition(win, { "CENTER" })
end

function ns:RefreshMainWindow()
    if not win or not win:IsShown() then return end
    local players = 0
    for _ in pairs(ns.db.players) do players = players + 1 end
    local text = #ns.db.runs .. " runs   " .. players .. " players"
    if ns.activeRun then text = ns.pveColor .. "Tracking " .. ns:RunTitle(ns.activeRun) .. "|r   " .. text end
    win.summary:SetText(text)
    local page = pages[currentTab]
    if page and page.Refresh then page:Refresh() end
    if detail.kind then ns:ShowDetail(detail.kind, detail.key) end
end

-- key: a player key, guild key or run id, for the tab's detail panel.
function ns:ShowMainWindow(tab, key)
    if not win then Build() end
    tab = tab or currentTab or "runs"
    currentTab = tab
    for k, page in pairs(pages) do page:SetShown(k == tab) end
    detail:SetShown(tab == "runs" or tab == "players" or tab == "guilds")
    win.tabs:SetSelected(tab)
    win:Show()
    if key then
        if tab == "guilds" then ns:ShowDetail("guild", key)
        elseif tab == "runs" then ns:ShowDetail("run", key)
        else ns:ShowDetail("player", key) end
    end
    ns:RefreshMainWindow()
end

function ns:ToggleMainWindow(tab)
    if win and win:IsShown() then
        win:Hide()
    else
        ns:ShowMainWindow(tab)
    end
end

-- Coalesce bursts of data changes into one refresh.
local pending = false
ns:Listen("DATA_CHANGED", function()
    if pending or not win or not win:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        -- Don't wipe the note the user is typing.
        if detail and detail.content.note:HasFocus() then
            local page = pages[currentTab]
            if page and page.Refresh then page:Refresh() end
            return
        end
        ns:RefreshMainWindow()
    end)
end)
