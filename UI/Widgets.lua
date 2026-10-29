local _, ns = ...

-- Small widget kit shared by every window. Flat dark style, built only from
-- plain frames and textures so it does not depend on Blizzard templates that
-- move around between client versions.

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"

UI.colors = {
    bg      = { 0.05, 0.05, 0.07, 0.96 },
    panel   = { 0.09, 0.09, 0.12, 1 },
    border  = { 0, 0, 0, 1 },
    accent  = { 0.83, 0.63, 0.09, 1 },
    button  = { 0.16, 0.16, 0.20, 1 },
    hover   = { 0.24, 0.24, 0.30, 1 },
    row     = { 1, 1, 1, 0.03 },
    rowSel  = { 0.83, 0.63, 0.09, 0.22 },
    kill    = { 0.30, 0.95, 0.35 },
    death   = { 1.00, 0.30, 0.30 },
}
local C = UI.colors

function UI.SetBackdrop(frame, bg, border)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bg = bg or C.bg
    border = border or C.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function UI.Text(parent, font, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if text then fs:SetText(text) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function UI.Divider(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 0.08)
    t:SetHeight(1)
    return t
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------

local function SavePosition(frame)
    if not frame.saveKey or not ns.db then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.frames[frame.saveKey] = { point = point, relPoint = relPoint, x = x, y = y }
end

function UI.RestorePosition(frame, default)
    local pos = frame.saveKey and ns.db and ns.db.frames[frame.saveKey]
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint(unpack(default or { "CENTER" }))
    end
end

-- Movable window with title bar and close button. Closes on Escape.
function UI.CreateWindow(globalName, title, width, height, saveKey)
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f.saveKey = saveKey
    UI.SetBackdrop(f)
    f:Hide()

    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(2)

    f.title = UI.Text(f, "GameFontNormal", title)
    f.title:SetPoint("TOPLEFT", 12, -10)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    if globalName then table.insert(UISpecialFrames, globalName) end
    return f
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function ButtonColors(b)
    local c = b.active and b.activeColor or (b.hovered and C.hover or C.button)
    b:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
end

-- Flat button. activeColor is used when :SetActive(true).
function UI.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 80, height or 20)
    UI.SetBackdrop(b, C.button)
    b.text = UI.Text(b, "GameFontHighlightSmall", text, "CENTER")
    b.text:SetPoint("CENTER")
    b:SetFontString(b.text)
    b.activeColor = { C.accent[1] * 0.6, C.accent[2] * 0.6, C.accent[3] * 0.6, 1 }
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        ButtonColors(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        ButtonColors(self)
        if self.tooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    function b:SetActive(on)
        self.active = on and true or false
        ButtonColors(self)
    end
    hooksecurefunc(b, "Disable", function(self) self.text:SetTextColor(0.5, 0.5, 0.5) end)
    hooksecurefunc(b, "Enable", function(self) self.text:SetTextColor(1, 1, 1) end)
    return b
end

-- A button that needs a second click within 3 seconds to fire. Used for deletes.
function UI.ConfirmButton(parent, text, width, height, onConfirm)
    local b
    b = UI.Button(parent, text, width, height, function(self)
        if self.armed then
            self.armed = false
            self:SetText(text)
            onConfirm(self)
        else
            self.armed = true
            self:SetText("|cffff5050Sure?|r")
            C_Timer.After(3, function()
                if self.armed then
                    self.armed = false
                    self:SetText(text)
                end
            end)
        end
    end)
    return b
end

-- Row of buttons for choosing a list (Invite / Kick / Ignore / None).
-- onSelect(list) gets nil for "None".
function UI.ListSelector(parent, onSelect, buttonWidth)
    local sel = CreateFrame("Frame", nil, parent)
    buttonWidth = buttonWidth or 62
    sel:SetSize(buttonWidth * 4 + 9, 20)
    sel.buttons = {}
    local entries = { "invite", "kick", "ignore", "none" }
    for i, list in ipairs(entries) do
        local info = ns.LIST_INFO[list]
        local b = UI.Button(sel, info and info.short or "None", buttonWidth, 20, function()
            local value = list ~= "none" and list or nil
            sel:SetValue(value)
            onSelect(value)
        end)
        b:SetPoint("LEFT", (i - 1) * (buttonWidth + 3), 0)
        if info then
            b.activeColor = { info.color[1] * 0.55, info.color[2] * 0.55, info.color[3] * 0.55, 1 }
        end
        b.list = list
        sel.buttons[i] = b
    end
    function sel:SetValue(value)
        for _, b in ipairs(self.buttons) do
            b:SetActive(b.list == (value or "none"))
        end
    end
    return sel
end

-- Ten buttons for a 1-10 rating, filled up to the chosen value. Clicking the
-- current value clears it. onSelect(value) gets nil when cleared.
function UI.RatingBar(parent, onSelect, size)
    size = size or 18
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(size * 10 + 9, size)
    bar.buttons = {}
    for i = 1, 10 do
        local b = UI.Button(bar, tostring(i), size, size, function()
            local value = bar.value ~= i and i or nil
            bar:SetValue(value)
            onSelect(value)
        end)
        b:SetPoint("LEFT", (i - 1) * (size + 1), 0)
        local r, g, bl = ns:RatingColor(i)
        b.activeColor = { r * 0.6, g * 0.6, bl * 0.6, 1 }
        b.tooltip = "Rate " .. i .. "/10 (click again to clear)"
        bar.buttons[i] = b
    end
    function bar:SetValue(value)
        self.value = value
        for i, b in ipairs(self.buttons) do b:SetActive(value ~= nil and i <= value) end
    end
    return bar
end

--------------------------------------------------------------------------------
-- Inputs
--------------------------------------------------------------------------------

-- Single-line edit box. onCommit(text) runs on Enter and when focus is lost.
function UI.EditBox(parent, width, height, onCommit, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, height or 22)
    UI.SetBackdrop(e, { 0, 0, 0, 0.6 }, { 0.3, 0.3, 0.35, 1 })
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or 255)
    e:SetScript("OnEscapePressed", function(self)
        self.skipCommit = true
        self:ClearFocus()
    end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self)
        self.skipCommit = false
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        self:HighlightText(0, 0)
        if not self.skipCommit and onCommit then onCommit(self:GetText()) end
        self.skipCommit = false
    end)

    e.placeholder = UI.Text(e, "GameFontDisableSmall")
    e.placeholder:SetPoint("LEFT", 7, 0)
    e:HookScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)
    function e:SetPlaceholder(text) self.placeholder:SetText(text) end
    return e
end

function UI.Checkbox(parent, label, onToggle)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    UI.SetBackdrop(cb, { 0, 0, 0, 0.6 }, { 0.35, 0.35, 0.4, 1 })
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    cb:SetCheckedTexture(check)
    cb.label = UI.Text(cb, "GameFontHighlightSmall", label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 8), 0, 0)
    cb:SetScript("OnClick", function(self) onToggle(self:GetChecked() and true or false) end)
    return cb
end

-- "< value >" picker. options = { { value, label }, ... }. onChange(value).
function UI.Cycler(parent, width, options, onChange)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width, 20)
    UI.SetBackdrop(f, { 0, 0, 0, 0.4 }, { 0.25, 0.25, 0.3, 1 })
    f.options = options
    f.index = 1
    f.text = UI.Text(f, "GameFontHighlightSmall", "", "CENTER")
    f.text:SetPoint("LEFT", 22, 0)
    f.text:SetPoint("RIGHT", -22, 0)

    local function Show()
        local o = f.options[f.index]
        f.text:SetText(o and o[2] or "")
    end
    local function Step(d)
        local n = #f.options
        if n == 0 then return end
        f.index = (f.index - 1 + d) % n + 1
        Show()
        onChange(f.options[f.index][1])
    end
    local prev = UI.Button(f, "<", 20, 20, function() Step(-1) end)
    prev:SetPoint("LEFT")
    local nextB = UI.Button(f, ">", 20, 20, function() Step(1) end)
    nextB:SetPoint("RIGHT")

    function f:SetValue(value)
        for i, o in ipairs(self.options) do
            if o[1] == value then self.index = i break end
        end
        Show()
    end
    return f
end

--------------------------------------------------------------------------------
-- Scrolling list
--------------------------------------------------------------------------------

-- Virtual list: a fixed pool of rows over an arbitrary data array.
--   buildRow(row)          creates the row's regions once
--   updateRow(row, item)   fills a row
--   onClick(row, item, button)
function UI.ScrollList(parent, rowHeight, buildRow, updateRow, onClick)
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetBackdrop(list, C.panel, { 0, 0, 0, 1 })
    list.rowHeight = rowHeight
    list.rows = {}
    list.data = {}
    list.offset = 0

    local slider = CreateFrame("Slider", nil, list)
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPRIGHT", -2, -2)
    slider:SetPoint("BOTTOMRIGHT", -2, 2)
    slider:SetWidth(8)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    thumb:SetSize(8, 30)
    slider:SetThumbTexture(thumb)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= list.offset then
            list.offset = value
            list:Refresh()
        end
    end)
    list.slider = slider

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local _, max = slider:GetMinMaxValues()
        local step = IsShiftKeyDown() and self:VisibleRows() or 3
        slider:SetValue(math.max(0, math.min(max, self.offset - delta * step)))
    end)

    list.empty = UI.Text(list, "GameFontDisable", "", "CENTER")
    list.empty:SetPoint("CENTER")

    function list:VisibleRows()
        return math.max(1, math.floor((self:GetHeight() - 4) / self.rowHeight))
    end

    local function GetRow(i)
        local row = list.rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, list)
        row:SetHeight(list.rowHeight)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * list.rowHeight)
        row:SetPoint("RIGHT", slider, "LEFT", -2, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        row:SetScript("OnClick", function(self, button)
            if onClick and self.item then onClick(self, self.item, button) end
        end)
        buildRow(row)
        list.rows[i] = row
        return row
    end

    function list:SetData(data)
        self.data = data or {}
        local max = math.max(0, #self.data - self:VisibleRows())
        slider:SetMinMaxValues(0, max)
        slider:SetShown(max > 0)
        if self.offset > max then self.offset = max end
        slider:SetValue(self.offset)
        self:Refresh()
    end

    function list:SetEmptyText(text) self.empty:SetText(text) end

    function list:Refresh()
        local visible = self:VisibleRows()
        for i = 1, visible do
            local row = GetRow(i)
            local item = self.data[self.offset + i]
            row.item = item
            if item then
                local sel = self.isSelected and self.isSelected(item)
                local c = sel and C.rowSel or ((self.offset + i) % 2 == 0 and C.row or { 0, 0, 0, 0 })
                row.bg:SetColorTexture(c[1], c[2], c[3], c[4])
                updateRow(row, item)
                row:Show()
            else
                row:Hide()
            end
        end
        for i = visible + 1, #self.rows do self.rows[i]:Hide() end
        self.empty:SetShown(#self.data == 0)
    end

    list:SetScript("OnSizeChanged", function(self) self:SetData(self.data) end)
    return list
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

function UI.TabBar(parent, tabs, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(22)
    bar.buttons = {}
    local x = 0
    for _, tab in ipairs(tabs) do
        local b = UI.Button(bar, tab.label, tab.width or 80, 22, function() onSelect(tab.key) end)
        b:SetPoint("LEFT", x, 0)
        b.key = tab.key
        x = x + (tab.width or 80) + 3
        table.insert(bar.buttons, b)
    end
    bar:SetWidth(x)
    function bar:SetSelected(key)
        for _, b in ipairs(self.buttons) do b:SetActive(b.key == key) end
    end
    return bar
end
