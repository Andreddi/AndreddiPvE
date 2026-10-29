local _, ns = ...
local UI = ns.UI

-- Alerts: a toast (plus optional sound and chat line) when a player from your
-- history or lists joins your group, applies to your listed group, or shows up
-- nearby.

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------

-- kit: SOUNDKIT constant name, id: fallback sound kit id, file: a sound file
-- path. Add your own entries here, e.g.
--   { key = "mine", label = "My sound", file = "Interface\\AddOns\\AndreddiPvE\\Sounds\\mine.ogg" },
local SOUND_CATALOG = {
    { key = "none",          label = "No sound" },
    { key = "raidwarning",   label = "Raid warning",       kit = "RAID_WARNING", id = 8959 },
    { key = "bosswhisper",   label = "Boss whisper alarm", kit = "UI_RAID_BOSS_WHISPER_WARNING", id = 37881 },
    { key = "alarm",         label = "Alarm clock",        kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
    { key = "readycheck",    label = "Ready check",        kit = "READY_CHECK", id = 8960 },
    { key = "questfailed",   label = "Quest failed",       kit = "IG_QUEST_FAILED", id = 847 },
    { key = "lfgrole",       label = "Dungeon ready",      kit = "LFG_ROLE_CHECK" },
    { key = "friendtoast",   label = "Friend online chime", kit = "UI_BNET_TOAST", id = 18019 },
    { key = "tell",          label = "Whisper",            kit = "TELL_MESSAGE", id = 3081 },
    { key = "mapping",       label = "Map ping",           kit = "MAP_PING", id = 3175 },
    { key = "questcomplete", label = "Quest complete",     kit = "IG_QUEST_LIST_COMPLETE" },
    { key = "coin",          label = "Coins",              kit = "LOOT_WINDOW_COIN_SOUND", id = 120 },
    { key = "levelup",       label = "Level up",           kit = "LEVEL_UP" },
}

ns.sounds = {}
ns.soundByKey = {}

local function BuildSoundList()
    wipe(ns.sounds)
    for _, s in ipairs(SOUND_CATALOG) do
        local entry = { key = s.key, label = s.label, file = s.file }
        if s.kit and SOUNDKIT and SOUNDKIT[s.kit] then
            entry.id = SOUNDKIT[s.kit]
        elseif s.id then
            entry.id = s.id
        end
        if s.key == "none" or entry.id or entry.file then
            table.insert(ns.sounds, entry)
            ns.soundByKey[s.key] = entry
        end
    end
end

function ns:PlayAlertSound(key)
    local s = ns.soundByKey[key]
    if not s or s.key == "none" then return end
    local channel = ns.db.settings.soundChannel or "Master"
    if s.file then
        pcall(PlaySoundFile, s.file, channel)
    elseif s.id then
        pcall(PlaySound, s.id, channel)
    end
end

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

local anchor
local toasts = {}   -- visible, newest first
local pool = {}
local TOAST_WIDTH = 300

local CATEGORY = {
    kick    = { title = "Kick on sight",      color = ns.LIST_INFO.kick.color },
    invite  = { title = "Always invite",      color = ns.LIST_INFO.invite.color },
    history = { title = "Played with before", color = { 0.25, 0.66, 0.96 } },
}

-- Where the player was spotted: the setting that enables it and the toast text.
local CHANNELS = {
    group     = { setting = "groupAlerts",     text = "joined your group" },
    applicant = { setting = "lfgAlerts",       text = "applied to your group" },
    nearby    = { setting = "proximityAlerts", text = "nearby" },
}

local function Layout()
    local prev
    for _, t in ipairs(toasts) do
        t:ClearAllPoints()
        if prev then
            t:SetPoint("TOP", prev, "BOTTOM", 0, -4)
        else
            t:SetPoint("TOP", anchor, "TOP", 0, 0)
        end
        prev = t
    end
end

local function Release(t)
    for i, v in ipairs(toasts) do
        if v == t then table.remove(toasts, i) break end
    end
    t:Hide()
    t.key = nil
    table.insert(pool, t)
    Layout()
end

local function CreateToast()
    local t = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    t:SetWidth(TOAST_WIDTH)
    t:SetFrameStrata("HIGH")
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UI.SetBackdrop(t)

    t.stripe = t:CreateTexture(nil, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 1, -1)
    t.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    t.stripe:SetWidth(4)

    t.header = UI.Text(t, "GameFontNormalSmall")
    t.header:SetPoint("TOPLEFT", 12, -7)
    t.tag = UI.Text(t, "GameFontNormalSmall", "", "RIGHT")
    t.tag:SetPoint("TOPRIGHT", -8, -7)

    t.name = UI.Text(t, "GameFontNormalLarge")
    t.name:SetPoint("TOPLEFT", t.header, "BOTTOMLEFT", 0, -3)
    t.name:SetPoint("RIGHT", -8, 0)

    t.body = UI.Text(t, "GameFontHighlightSmall")
    t.body:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
    t.body:SetPoint("RIGHT", -8, 0)
    t.body:SetSpacing(2)
    t.body:SetWordWrap(true)

    -- Left-click opens the player's history, right-click dismisses.
    t:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.key and ns:GetPlayer(self.key) then
            ns:ShowMainWindow("players", self.key)
        end
        Release(self)
    end)
    t:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then
            self:SetAlpha(1)
            return
        end
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            Release(self)
        elseif self.remaining < 1 then
            self:SetAlpha(self.remaining)
        end
    end)
    return t
end

local function ShowToast(data)
    -- Replace an existing toast for the same player.
    for _, t in ipairs(toasts) do
        if t.key == data.key then Release(t) break end
    end
    local t = table.remove(pool) or CreateToast()
    local cat = CATEGORY[data.category]
    t.key = data.key
    t.stripe:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
    t.header:SetText(data.header or cat.title)
    t.header:SetTextColor(cat.color[1], cat.color[2], cat.color[3])
    t.tag:SetText(data.tag or "")
    t.name:SetText(data.name)
    t.body:SetText(data.body)
    t:SetHeight(7 + t.header:GetStringHeight() + 3 + t.name:GetStringHeight() + 3 + t.body:GetStringHeight() + 9)
    t.remaining = ns.db.settings.alertDuration or 10
    t:SetAlpha(1)
    t:Show()

    table.insert(toasts, 1, t)
    local max = ns.db.settings.alertMax or 3
    while #toasts > max do Release(toasts[#toasts]) end
    Layout()
end

--------------------------------------------------------------------------------
-- Alert logic
--------------------------------------------------------------------------------

local lastAlert = { group = {}, applicant = {}, nearby = {} }

-- Builds the toast text for a player. Returns nil if there is nothing to say.
function ns:BuildAlert(info, channel)
    local key = info.key
    local p = ns:GetPlayer(key)
    local gkey = info.guildKey or (p and p.guildKey)
    local g = ns:GetGuild(gkey)
    local list, source = ns:EffectiveList(key, gkey)
    local category = list or "history"
    if category == "ignore" then return nil end

    local class = info.class or (p and p.class)
    local level = info.level or (p and p.level)
    local name = ns:ColoredName(key, class)
    if level then name = name .. " |cffbbbbbb" .. level .. "|r" end

    local lines = {}
    local who = {}
    if class then table.insert(who, ns:ClassName(class)) end
    local guildName = info.guild or (g and g.name)
    if guildName then table.insert(who, "|cffd4a017<" .. guildName .. ">|r") end
    if #who > 0 then table.insert(lines, table.concat(who, "  ")) end

    local count, last = ns:PriorRuns(key)
    if count > 0 then
        local s = ns:PlayerSummary(key)
        local line = "Runs together: |cffffffff" .. count .. "|r"
        if s.rating then line = line .. "   Rating: " .. ns:RatingText(s.rating) .. " |cff999999(" .. s.ratingN .. ")|r" end
        table.insert(lines, line)
        table.insert(lines, "|cff999999Last:|r " .. ns:RunLine(last))
    end
    if p and p.note then table.insert(lines, "|cffffd100Note:|r " .. p.note) end
    if g and g.note then table.insert(lines, "|cffffd100Guild note:|r " .. g.note) end

    local tag = list and ns:ListTag(list) or nil
    if tag and source == "guild" then tag = tag .. " |cff999999guild|r" end

    local ch = CHANNELS[channel]
    return {
        key = key,
        category = category,
        header = CATEGORY[category].title .. (ch and (" |cffbbbbbb" .. ch.text .. "|r") or ""),
        name = name,
        tag = tag,
        body = table.concat(lines, "\n"),
    }
end

-- channel: "group", "applicant" or "nearby". source: extra detail for chat.
function ns:MaybeAlert(info, channel, source)
    local s = ns.db.settings
    local ch = CHANNELS[channel]
    if not ch or not s[ch.setting] or not info or not info.key then return end
    if channel == "nearby" and not s.alertInInstances and ns:InAnyInstance() then return end
    if not ns:IsInteresting(info.key, info.guildKey) then return end

    local list = ns:EffectiveList(info.key, info.guildKey)
    if list == "ignore" then return end
    if list == "kick" and not s.alertKick then return end
    if list == "invite" and not s.alertInvite then return end
    if not list and not s.alertHistory then return end

    local now = GetTime()
    local last = lastAlert[channel]
    if last[info.key] and now - last[info.key] < (s.alertCooldown or 300) then return end
    last[info.key] = now

    local data = ns:BuildAlert(info, channel)
    if not data then return end
    ShowToast(data)

    if s.soundsEnabled then
        local soundKey = (list == "kick" and s.soundKick) or (list == "invite" and s.soundInvite) or s.soundHistory
        ns:PlayAlertSound(soundKey)
    end
    if s.alertChat then
        local tag = data.tag and (data.tag .. " ") or ""
        ns:Print(tag .. data.name .. " " .. ch.text .. (source and (" |cff777777(" .. source .. ")|r") or ""))
    end
end

--------------------------------------------------------------------------------
-- Anchor and test
--------------------------------------------------------------------------------

local function BuildAnchor()
    anchor = CreateFrame("Frame", "AndreddiPvEAlertAnchor", UIParent, "BackdropTemplate")
    anchor:SetSize(TOAST_WIDTH, 30)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.db.frames.alertAnchor = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    anchor.saveKey = "alertAnchor"
    UI.RestorePosition(anchor, { "TOP", UIParent, "TOP", -280, -180 })
    anchor.label = UI.Text(anchor, "GameFontNormalSmall", "AndreddiPvE alerts. Drag me, then type /apve lock", "CENTER")
    anchor.label:SetPoint("CENTER")
    anchor.label:Hide()
    anchor:EnableMouse(false)
end

-- force: true = unlock, false = lock, nil = toggle.
function ns:ToggleAlertAnchor(force)
    local unlocked = not anchor.unlocked
    if force ~= nil then unlocked = force end
    anchor.unlocked = unlocked
    anchor:EnableMouse(unlocked)
    anchor.label:SetShown(unlocked)
    if unlocked then
        UI.SetBackdrop(anchor, { 0.25, 0.66, 0.96, 0.3 }, { 0.25, 0.66, 0.96, 1 })
    else
        anchor:SetBackdrop(nil)
    end
    ns:Print(unlocked and "Alert anchor unlocked. Drag it, then /apve lock." or "Alert anchor locked.")
end

function ns:TestAlert()
    local key = ns:PlayerKey("Testgnome", nil)
    ShowToast({
        key = "test:kick",
        category = "kick",
        header = "Kick on sight |cffbbbbbbjoined your group|r",
        name = ns:ColoredName(key, "WARRIOR") .. " |cffbbbbbb80|r",
        tag = ns:ListTag("kick"),
        body = "Warrior  |cffd4a017<Example Guild>|r\nRuns together: |cffffffff2|r   Rating: " .. ns:RatingText(2)
            .. " |cff999999(2)|r\n|cff999999Last:|r Example Dungeon +10 · |cffff4040Abandoned|r |cff999999· 3 days ago|r"
            .. "\n|cffffd100Note:|r Left after the first wipe.",
    })
    ShowToast({
        key = "test:invite",
        category = "invite",
        header = "Always invite |cffbbbbbbapplied to your group|r",
        name = ns:ColoredName(key, "PRIEST") .. " |cffbbbbbb80|r",
        tag = ns:ListTag("invite"),
        body = "Priest\nRuns together: |cffffffff6|r   Rating: " .. ns:RatingText(9.5) .. " |cff999999(6)|r"
            .. "\n|cffffd100Note:|r Great healer, knows every route.",
    })
    ShowToast({
        key = "test:history",
        category = "history",
        header = "Played with before |cffbbbbbbjoined your group|r",
        name = ns:ColoredName(key, "MAGE") .. " |cffbbbbbb80|r",
        body = "Mage\nRuns together: |cffffffff1|r\n|cff999999Last:|r Example Raid (Normal) · "
            .. "|cff40ff40Completed|r |cff999999· 2 weeks ago|r",
    })
    if ns.db.settings.soundsEnabled then ns:PlayAlertSound(ns.db.settings.soundKick) end
end

ns:Listen("DB_READY", function()
    BuildSoundList()
    BuildAnchor()
end)
