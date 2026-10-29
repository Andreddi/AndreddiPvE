local _, ns = ...
local UI = ns.UI

-- Statistics tab: headline tiles, runs per period and per instance, a 14-day
-- chart, and the players and guilds you play with most and rate best/worst.

local DONE = UI.colors.kill
local OTHER = { 0.25, 0.66, 0.96 }

local function Panel(parent, title)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetBackdrop(p, UI.colors.panel)
    p.title = UI.Text(p, "GameFontNormalSmall", title)
    p.title:SetPoint("TOPLEFT", 8, -7)
    return p
end

local function Tile(parent, label)
    local t = Panel(parent, label)
    t.title:SetFontObject("GameFontDisableSmall")
    t.value = UI.Text(t, "GameFontHighlightLarge")
    t.value:SetPoint("BOTTOMLEFT", 8, 8)
    return t
end

-- A grid of font strings: rows x columns, columns = { {width, justify} }.
local function TextTable(parent, rows, columns, rowHeight)
    local tbl = { rows = {} }
    for r = 1, rows do
        local row = {}
        local x = 8
        for c, col in ipairs(columns) do
            local fs = UI.Text(parent, r == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall", "", col[2])
            fs:SetPoint("TOPLEFT", x, -24 - (r - 1) * rowHeight)
            fs:SetWidth(col[1])
            fs:SetWordWrap(false)
            row[c] = fs
            x = x + col[1] + 4
        end
        tbl.rows[r] = row
    end
    function tbl:Set(r, values)
        local row = self.rows[r]
        if not row then return end
        for c, fs in ipairs(row) do fs:SetText(values and values[c] or "") end
    end
    return tbl
end

local function Percent(part, whole)
    if not whole or whole == 0 then return "-" end
    return math.floor(part / whole * 100 + 0.5) .. "%"
end

local function Build(page)
    local scopeMe = false

    ----------------------------------------------------------------------------
    -- Scope toggle
    ----------------------------------------------------------------------------
    local allBtn, meBtn
    allBtn = UI.Button(page, "All characters", 100, 20, function()
        scopeMe = false
        page:Refresh()
    end)
    allBtn:SetPoint("TOPRIGHT", -106, 0)
    meBtn = UI.Button(page, "This character", 100, 20, function()
        scopeMe = true
        page:Refresh()
    end)
    meBtn:SetPoint("TOPRIGHT", 0, 0)

    ----------------------------------------------------------------------------
    -- Headline tiles
    ----------------------------------------------------------------------------
    local tiles = {}
    local tileDefs = { "Runs", "Completed", "Keys timed", "Players met", "Average rating given", "Runs per week (avg)" }
    local tileW = (876 - 5 * 6) / 6
    for i, label in ipairs(tileDefs) do
        local t = Tile(page, label)
        t:SetSize(tileW, 50)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + 6), -26)
        tiles[i] = t
    end

    ----------------------------------------------------------------------------
    -- Periods
    ----------------------------------------------------------------------------
    local periods = Panel(page, "By period")
    periods:SetPoint("TOPLEFT", 0, -84)
    periods:SetSize(270, 224)
    local periodTable = TextTable(periods, 6, { { 90, "LEFT" }, { 50, "RIGHT" }, { 50, "RIGHT" }, { 50, "RIGHT" } }, 18)
    periodTable:Set(1, { "", "Runs", "Done", "M+" })
    local averages = UI.Text(periods, "GameFontDisableSmall")
    averages:SetPoint("BOTTOMLEFT", 8, 8)
    averages:SetPoint("RIGHT", -8, 0)
    averages:SetSpacing(2)

    ----------------------------------------------------------------------------
    -- Instances
    ----------------------------------------------------------------------------
    local instances = Panel(page, "By instance")
    instances:SetPoint("TOPLEFT", periods, "TOPRIGHT", 6, 0)
    instances:SetSize(270, 224)
    local INSTANCE_ROWS = 14
    local instanceTable = TextTable(instances, INSTANCE_ROWS, { { 118, "LEFT" }, { 36, "RIGHT" }, { 40, "RIGHT" }, { 40, "RIGHT" } }, 14)
    instanceTable:Set(1, { "Instance", "Runs", "Done", "Best" })

    ----------------------------------------------------------------------------
    -- Top lists
    ----------------------------------------------------------------------------
    local tops = {}
    local topDefs = {
        { key = "partners", title = "Played with most", kind = "player" },
        { key = "topRated", title = "Highest rated",    kind = "player" },
        { key = "guilds",   title = "Guilds played with most", kind = "guild" },
        { key = "lowRated", title = "Lowest rated",     kind = "player" },
    }
    local topW = 876 - 270 * 2 - 12
    for i, def in ipairs(topDefs) do
        local p = Panel(page, def.title)
        p:SetSize((topW - 6) / 2, 109)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        p:SetPoint("TOPLEFT", instances, "TOPRIGHT", 6 + col * ((topW - 6) / 2 + 6), -row * 115)
        p.lines = {}
        for l = 1, 5 do
            local b = CreateFrame("Button", nil, p)
            b:SetHeight(16)
            b:SetPoint("TOPLEFT", 6, -22 - (l - 1) * 17)
            b:SetPoint("RIGHT", -6, 0)
            b.left = UI.Text(b, "GameFontHighlightSmall")
            b.left:SetPoint("LEFT", 2, 0)
            b.left:SetPoint("RIGHT", -60, 0)
            b.left:SetWordWrap(false)
            b.right = UI.Text(b, "GameFontHighlightSmall", "", "RIGHT")
            b.right:SetPoint("RIGHT", -2, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(self)
                if self.key then ns:ShowMainWindow(def.kind == "guild" and "guilds" or "players", self.key) end
            end)
            p.lines[l] = b
        end
        p.def = def
        tops[i] = p
    end

    ----------------------------------------------------------------------------
    -- 14 day chart: one bar per day, completed runs at the bottom in green and
    -- the rest stacked on top in blue.
    ----------------------------------------------------------------------------
    local chart = Panel(page, "Last 14 days")
    chart:SetPoint("TOPLEFT", periods, "BOTTOMLEFT", 0, -6)
    chart:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    local legend = UI.Text(chart, "GameFontHighlightSmall", "", "RIGHT")
    legend:SetPoint("TOPRIGHT", -8, -7)
    legend:SetText(("|cff%02x%02x%02x\226\150\160|r Completed   |cff%02x%02x%02x\226\150\160|r Other runs"):format(
        DONE[1] * 255, DONE[2] * 255, DONE[3] * 255, OTHER[1] * 255, OTHER[2] * 255, OTHER[3] * 255))

    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", 8, -26)
    plot:SetPoint("BOTTOMRIGHT", -8, 22)

    local baseline = plot:CreateTexture(nil, "ARTWORK")
    baseline:SetColorTexture(1, 1, 1, 0.25)
    baseline:SetHeight(1)
    baseline:SetPoint("BOTTOMLEFT")
    baseline:SetPoint("BOTTOMRIGHT")

    local scaleText = UI.Text(chart, "GameFontDisableSmall", "", "LEFT")
    scaleText:SetPoint("BOTTOMLEFT", 8, 6)

    local bars = {}
    for i = 1, 14 do
        local slot = CreateFrame("Frame", nil, plot)
        slot:EnableMouse(true)
        slot.done = slot:CreateTexture(nil, "ARTWORK")
        slot.done:SetColorTexture(DONE[1], DONE[2], DONE[3], 0.9)
        slot.other = slot:CreateTexture(nil, "ARTWORK")
        slot.other:SetColorTexture(OTHER[1], OTHER[2], OTHER[3], 0.9)
        slot.hl = slot:CreateTexture(nil, "BACKGROUND")
        slot.hl:SetAllPoints()
        slot.hl:SetColorTexture(1, 1, 1, 0.06)
        slot.hl:Hide()
        slot.label = UI.Text(chart, "GameFontDisableSmall", "", "CENTER")
        slot:SetScript("OnEnter", function(self)
            self.hl:Show()
            if not self.day then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(date("%A %d %B", self.day.from))
            GameTooltip:AddDoubleLine("Runs", self.day.runs, 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Completed", self.day.completed, 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        bars[i] = slot
    end

    local function DrawChart(daily)
        local w, h = plot:GetWidth(), plot:GetHeight()
        if w <= 0 or h <= 0 then return end
        local maxV = 0
        for _, d in ipairs(daily) do maxV = math.max(maxV, d.runs) end
        local scale = maxV > 0 and (h - 2) / maxV or 0

        local slotW = w / #daily
        local barW = math.max(3, math.min(16, slotW - 8))
        for i, d in ipairs(daily) do
            local slot = bars[i]
            slot.day = d
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", (i - 1) * slotW, 0)
            slot:SetSize(slotW, h)

            local other = d.runs - d.completed
            slot.done:ClearAllPoints()
            slot.done:SetSize(barW, math.max(0.01, d.completed * scale))
            slot.done:SetPoint("BOTTOM", slot, "BOTTOMLEFT", slotW / 2, 1)
            slot.done:SetShown(d.completed > 0)

            slot.other:ClearAllPoints()
            slot.other:SetSize(barW, math.max(0.01, other * scale))
            slot.other:SetPoint("BOTTOM", slot, "BOTTOMLEFT", slotW / 2, 1 + d.completed * scale)
            slot.other:SetShown(other > 0)

            slot.label:ClearAllPoints()
            slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -3)
            slot.label:SetText(i == #daily and "Today" or date("%a %d", d.from))
        end
        scaleText:SetText(maxV > 0 and ("peak " .. maxV .. " runs in a day") or "")
    end

    ----------------------------------------------------------------------------
    -- Refresh
    ----------------------------------------------------------------------------
    function page:Refresh()
        allBtn:SetActive(not scopeMe)
        meBtn:SetActive(scopeMe)
        local s = ns:ComputeStats(scopeMe and ns:MyKey() or nil)
        local t = s.total

        tiles[1].value:SetText(t.runs)
        tiles[2].value:SetText(t.completed .. " |cff999999(" .. Percent(t.completed, t.tracked) .. ")|r")
        tiles[3].value:SetText(t.timed .. " |cff999999of " .. t.mplus .. "|r")
        tiles[4].value:SetText(s.playersMet)
        tiles[5].value:SetText(s.ratingAvg and ns:RatingText(math.floor(s.ratingAvg * 10 + 0.5) / 10) or "-")
        tiles[6].value:SetText(s.averages and ("%.1f"):format(s.averages.perWeek) or "-")

        for i, p in ipairs(s.periods) do
            periodTable:Set(i + 1, { p.label, p.runs, p.completed, p.mplus })
        end
        if s.averages then
            averages:SetText(("Average runs: %.1f a day, %.1f a week, %.1f a month\nTracking since %s"):format(
                s.averages.perDay, s.averages.perWeek, s.averages.perMonth, date("%Y-%m-%d", s.firstT)))
        else
            averages:SetText("")
        end

        for r = 2, INSTANCE_ROWS do
            local inst = s.instances[r - 1]
            if inst then
                instanceTable:Set(r, { inst.name, inst.runs, inst.completed, inst.bestKey and ("+" .. inst.bestKey) or "" })
            else
                instanceTable:Set(r, r == 2 and { "|cff777777No data yet|r" } or nil)
            end
        end

        for _, p in ipairs(tops) do
            local list = s[p.def.key]
            for l, b in ipairs(p.lines) do
                local item = list[l]
                if item then
                    b.key = item.key
                    if p.def.kind == "guild" then
                        local g = ns:GetGuild(item.key)
                        b.left:SetText("|cffd4a017" .. (g and g.name or ns:ShortName(item.key)) .. "|r")
                        b.right:SetText(item.runs)
                    else
                        b.left:SetText(ns:ColoredName(item.key, item.class))
                        if p.def.key == "partners" then
                            b.right:SetText(item.runs)
                        else
                            b.right:SetText(ns:RatingText(math.floor(item.rating * 10 + 0.5) / 10)
                                .. " |cff777777(" .. item.ratingN .. ")|r")
                        end
                    end
                    b:Show()
                elseif l == 1 then
                    b.key = nil
                    b.left:SetText("|cff777777None yet|r")
                    b.right:SetText("")
                    b:Show()
                else
                    b:Hide()
                end
            end
        end

        DrawChart(s.daily)
    end

    page:SetScript("OnShow", function(self) self:Refresh() end)
    plot:SetScript("OnSizeChanged", function() if page:IsShown() then page:Refresh() end end)
end

ns:RegisterPage("stats", Build)
