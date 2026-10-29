local ADDON, ns = ...

ns.name = ADDON
ns.version = "@project-version@"
ns.color = "|cffd4a017"
ns.pveColor = "|cff3fa9f5"
ns.title = ns.color .. "Andreddi|r" .. ns.pveColor .. "PvE|r"

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- ns:On(event, fn) registers fn(event, ...) for a game event. Several modules may
-- listen to the same event.
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            handlers[event] = nil
            return false
        end
    end
    table.insert(handlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then ns:Debug("Error in " .. event .. ": " .. tostring(err)) end
    end
end)

-- Internal message bus so UI can refresh when data changes.
local callbacks = {}
function ns:Listen(msg, fn)
    callbacks[msg] = callbacks[msg] or {}
    table.insert(callbacks[msg], fn)
end

function ns:Fire(msg, ...)
    local list = callbacks[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns:Debug("Error in callback " .. msg .. ": " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Secret values (Forever/Midnight). Any API may hand back an opaque value that
-- throws on comparison or concatenation; treat those as unknown.
--------------------------------------------------------------------------------

local issecretvalue = issecretvalue

function ns.Safe(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local Safe = ns.Safe

-- Calls fn(...) and returns its results with secrets stripped. Returns nothing
-- if the call errors.
local function StripSecrets(ok, ...)
    if not ok then return end
    local n = select("#", ...)
    local out = { ... }
    for i = 1, n do out[i] = Safe(out[i]) end
    return unpack(out, 1, n)
end

function ns.SafeCall(fn, ...)
    if not fn then return end
    return StripSecrets(pcall(fn, ...))
end
local SafeCall = ns.SafeCall

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

function ns:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage(ns.title .. ": " .. msg)
end

function ns:Debug(...)
    if ns.db and ns.db.settings.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[APvE debug]|r " .. strjoin(" ", tostringall(...)))
    end
end

--------------------------------------------------------------------------------
-- Names, realms, classes
--------------------------------------------------------------------------------

function ns:MyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

function ns:NormalizeRealm(realm)
    if not realm or realm == "" then return ns:MyRealm() end
    return (realm:gsub("[%s%-]", ""))
end

-- WoW: Forever characters have a first name and a surname, and the name APIs
-- (UnitName, GetPlayerInfoByGUID, ...) return the surname where retail returns
-- the realm. AndreddiPvE_Forever.toc sets "X-NameStyle: Surname"; the runtime
-- check covers a client that loads the other TOC.
local surnameMode
function ns:UsesSurnames()
    if surnameMode ~= nil then return surnameMode end
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getMeta and SafeCall(getMeta, ADDON, "X-NameStyle") == "Surname" then
        surnameMode = true
        return true
    end
    local full = GetUnitName and SafeCall(GetUnitName, "player", false)
    if full and full ~= "" then
        surnameMode = full:find(" ", 1, true) ~= nil
        return surnameMode
    end
    return false -- player name not known yet; ask again later
end

-- Turns the two values the name APIs return into (full name, realm).
-- Retail: ("Name", "Realm") -> "Name", "Realm"
-- Forever: ("First", "Surname") -> "First Surname", own realm
function ns:NameAndRealm(name, second)
    if not name or name == "" then return nil end
    if ns:UsesSurnames() then
        if second and second ~= "" and not name:find(" ", 1, true)
            and second ~= GetRealmName() and ns:NormalizeRealm(second) ~= ns:MyRealm() then
            name = name .. " " .. second
        end
        return name, ns:MyRealm()
    end
    return name, ns:NormalizeRealm(second)
end

-- Splits a "Name-Realm" key. Realms are stored without hyphens, so the last
-- hyphen is the separator; names with hyphens (Forever surnames) survive.
function ns:SplitKey(key)
    local n, r = key:match("^(.*)%-([^%-]*)$")
    if not n then return key, nil end
    return n, r
end

-- Key from a full name and realm, or from text the user typed. On retail
-- typed text may be "Name-Realm"; on Forever the whole text is the name.
function ns:PlayerKey(name, realm)
    if not name then return nil end
    name = strtrim(name)
    if name == "" then return nil end
    if ns:UsesSurnames() then
        return name .. "-" .. ns:MyRealm()
    end
    local n, r = strsplit("-", name, 2)
    if r and r ~= "" then realm = r end
    return n .. "-" .. ns:NormalizeRealm(realm)
end

function ns:GuildKey(guild, realm)
    if not guild or guild == "" then return nil end
    if ns:UsesSurnames() then realm = nil end
    return guild .. "-" .. ns:NormalizeRealm(realm)
end

function ns:MyKey()
    local name, realm = ns:NameAndRealm(SafeCall(UnitName, "player"))
    return name and (name .. "-" .. realm)
end

-- Display name: strip realm when it matches our own.
function ns:ShortName(key)
    if not key then return "?" end
    local n, r = ns:SplitKey(key)
    if r == nil or r == ns:MyRealm() then return n end
    return n .. "-" .. r
end

function ns:ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b, c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return 0.8, 0.8, 0.8, "ffcccccc"
end

function ns:ClassName(classFile)
    if not classFile then return "Unknown" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
end

function ns:ColoredName(key, classFile)
    local _, _, _, hex = ns:ClassColor(classFile)
    return "|c" .. hex .. ns:ShortName(key) .. "|r"
end

-- Role icon (TANK / HEALER / DAMAGER), or "" for no role.
local ROLE_FALLBACK = { TANK = "|cff6699ff[T]|r", HEALER = "|cff40ff40[H]|r", DAMAGER = "|cffff6060[D]|r" }
function ns:RoleIcon(role)
    if not role or not ROLE_FALLBACK[role] then return "" end
    return _G["INLINE_" .. role .. "_ICON"] or ROLE_FALLBACK[role]
end

ns.ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

--------------------------------------------------------------------------------
-- Lists
--------------------------------------------------------------------------------

ns.LISTS = { "invite", "kick", "ignore" }
ns.LIST_INFO = {
    invite = { label = "Always invite", short = "Invite", color = { 0.30, 0.85, 0.40 }, hex = "ff4dd966" },
    kick   = { label = "Kick on sight", short = "Kick",   color = { 1.00, 0.25, 0.20 }, hex = "ffff4033" },
    ignore = { label = "Ignore",        short = "Ignore", color = { 0.60, 0.60, 0.60 }, hex = "ff999999" },
}

function ns:ListTag(list)
    local info = list and ns.LIST_INFO[list]
    if not info then return "" end
    return "|c" .. info.hex .. "[" .. info.short .. "]|r"
end

--------------------------------------------------------------------------------
-- Ratings (1-10)
--------------------------------------------------------------------------------

-- Red at 1, yellow in the middle, green at 10.
function ns:RatingColor(r)
    local t = (math.max(1, math.min(10, r)) - 1) / 9
    if t < 0.5 then return 1, 0.25 + t * 1.5, 0.25 end
    return 1 - (t - 0.5) * 1.5, 1, 0.25
end

function ns:RatingText(r)
    if not r then return "|cff777777-|r" end
    local red, green, blue = ns:RatingColor(r)
    local s = r == math.floor(r) and tostring(r) or ("%.1f"):format(r)
    return ("|cff%02x%02x%02x%s|r"):format(red * 255, green * 255, blue * 255, s)
end

--------------------------------------------------------------------------------
-- Time helpers
--------------------------------------------------------------------------------

function ns:Ago(t)
    if not t then return "never" end
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    if d < 86400 * 60 then return math.floor(d / 86400) .. " days ago" end
    return date("%Y-%m-%d", t)
end

function ns:FormatTime(t)
    return date("%Y-%m-%d %H:%M", t)
end

-- 1:02:03 or 32:15
function ns:Duration(sec)
    if not sec or sec < 0 then return "" end
    sec = math.floor(sec)
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

--------------------------------------------------------------------------------
-- Unit info
--------------------------------------------------------------------------------

-- Collects what we can learn about a player unit. Returns nil for non-players
-- and for ourselves. Fields that come back secret are left nil.
function ns:ReadUnit(unit)
    if not SafeCall(UnitExists, unit) then return nil end
    if not SafeCall(UnitIsPlayer, unit) then return nil end
    if SafeCall(UnitIsUnit, unit, "player") then return nil end

    local rawName, second = SafeCall(UnitName, unit)
    if not rawName or rawName == "" or rawName == UNKNOWNOBJECT then return nil end
    local name, realm = ns:NameAndRealm(rawName, second)

    local info = {
        guid = SafeCall(UnitGUID, unit),
        name = name,
        realm = realm,
        key = name .. "-" .. realm,
    }
    local _, classFile = SafeCall(UnitClass, unit)
    info.class = classFile
    local _, raceFile = SafeCall(UnitRace, unit)
    info.race = raceFile
    local level = SafeCall(UnitLevel, unit)
    if level and level > 0 then info.level = level end
    local guild, _, _, guildRealm = SafeCall(GetGuildInfo, unit)
    if guild and guild ~= "" then
        info.guild = guild
        info.guildKey = ns:GuildKey(guild, guildRealm)
    end
    info.faction = SafeCall(UnitFactionGroup, unit)
    return info
end

-- Unit tokens of the other group members (raid tokens include ourselves;
-- ns:ReadUnit skips that one).
function ns:GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, 40 do units[i] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, 4 do units[i] = "party" .. i end
    end
    return units
end

function ns:InGroupWith(unit)
    return (SafeCall(UnitInParty, unit) or SafeCall(UnitInRaid, unit)) and true or false
end

function ns:InAnyInstance()
    local inInstance = SafeCall(IsInInstance)
    return inInstance and true or false
end

function ns:ZoneInfo()
    local zone = SafeCall(GetRealZoneText) or SafeCall(GetZoneText) or ""
    local sub = SafeCall(GetSubZoneText) or ""
    return zone, sub
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

ns.defaults = {
    -- Tracking
    trackMythicPlus = true,
    trackDungeons = true,
    trackRaids = true,
    popupAfterDungeon = true,
    popupOnLeave = true,
    popupAutoClose = 0,

    -- Alerts
    groupAlerts = true,
    lfgAlerts = true,
    proximityAlerts = false,
    alertInInstances = false,
    alertKick = true,
    alertInvite = true,
    alertHistory = true,
    alertCooldown = 300,
    alertDuration = 10,
    alertChat = true,
    alertMax = 3,
    soundsEnabled = true,
    soundKick = "raidwarning",
    soundInvite = "friendtoast",
    soundHistory = "tell",
    soundChannel = "Master",

    -- Tooltip and menus
    tooltipEnabled = true,
    tooltipShowNote = true,
    lfgTooltips = true,
    menuEnabled = true,

    debug = false,
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                CopyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
end

local function InitDB()
    AndreddiPvEDB = AndreddiPvEDB or {}
    local db = AndreddiPvEDB
    db.version = db.version or 1
    db.players = db.players or {}
    db.guilds = db.guilds or {}
    db.runs = db.runs or {}
    db.nextRunID = db.nextRunID or 1
    db.settings = db.settings or {}
    db.frames = db.frames or {}
    CopyDefaults(db.settings, ns.defaults)
    ns.db = db
end

ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    InitDB()
    ns:Fire("DB_READY")
end)

ns:On("PLAYER_LOGIN", function()
    ns:Fire("LOGIN")
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function TargetOrName(arg)
    if arg and arg ~= "" then
        local key = ns:FindPlayerKey(arg)
        return key and (ns:SeenByKey(key) or { key = key })
    end
    return ns:ReadUnit("target")
end

local function SetListCommand(list, arg)
    local info = TargetOrName(arg)
    if not info then
        ns:Print("Target a player or give a name, e.g. /apve " .. (list or "clear") .. " Name-Realm")
        return
    end
    ns:TouchPlayer(info)
    ns:SetPlayerList(info.key, list)
    ns:Print(ns:ShortName(info.key), list and ("added to " .. ns.LIST_INFO[list].label) or "removed from lists")
end

local function SetGuildListCommand(list, arg)
    local gkey
    if arg and arg ~= "" then
        gkey = ns:GuildKey(arg, nil)
    else
        local info = ns:ReadUnit("target")
        gkey = info and info.guildKey
    end
    if not gkey then
        ns:Print("Target a guilded player or give a guild name, e.g. /apve gkick Guild Name")
        return
    end
    ns:TouchGuild(gkey)
    ns:SetGuildList(gkey, list)
    ns:Print("Guild <" .. ns:ShortName(gkey) .. ">", list and ("added to " .. ns.LIST_INFO[list].label) or "removed from lists")
end

local function RateCommand(arg)
    local value = tonumber(arg)
    if not value or value < 1 or value > 10 or value ~= math.floor(value) then
        ns:Print("Usage: /apve rate <1-10> (rates your target for your last run together)")
        return
    end
    local info = ns:ReadUnit("target")
    if not info then ns:Print("Target a player first.") return end
    local run = ns:LastRunWith(info.key)
    if not run then
        ns:Print("No runs with", ns:ShortName(info.key), "yet. Right-click them and choose Add to history first.")
        return
    end
    ns:SetRunRating(run, info.key, value)
    ns:Print("Rated", ns:ShortName(info.key), ns:RatingText(value), "for", ns:RunTitle(run))
end

local function Help()
    ns:Print("commands:")
    print("  /apve - open the run history")
    print("  /apve players | guilds | stats | settings")
    print("  /apve invite|kick|ignore|clear [name] - list target or named player")
    print("  /apve ginvite|gkick|gignore|gclear [Guild] - list target's guild or named guild")
    print("  /apve note <text> - set a note on your target")
    print("  /apve rate <1-10> - rate your target for your last run together")
    print("  /apve group - rate your current group (logs it as a run if none is tracked)")
    print("  /apve unlock | lock - move the alert anchor")
    print("  /apve test - show test alerts")
end

SLASH_ANDREDDIPVE1 = "/apve"
SLASH_ANDREDDIPVE2 = "/andreddipve"
SlashCmdList.ANDREDDIPVE = function(input)
    input = input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "runs" or cmd == "history" or cmd == "show" then
        ns:ToggleMainWindow("runs")
    elseif cmd == "players" or cmd == "guilds" or cmd == "stats" or cmd == "settings" then
        ns:ShowMainWindow(cmd)
    elseif cmd == "config" or cmd == "options" then
        ns:ShowMainWindow("settings")
    elseif cmd == "invite" or cmd == "kick" or cmd == "ignore" then
        SetListCommand(cmd, rest)
    elseif cmd == "clear" then
        SetListCommand(nil, rest)
    elseif cmd == "ginvite" or cmd == "gkick" or cmd == "gignore" then
        SetGuildListCommand(cmd:sub(2), rest)
    elseif cmd == "gclear" then
        SetGuildListCommand(nil, rest)
    elseif cmd == "note" then
        local info = ns:ReadUnit("target")
        if not info then ns:Print("Target a player first.") return end
        ns:TouchPlayer(info)
        ns:SetPlayerNote(info.key, rest)
        ns:Print("Note saved for", ns:ShortName(info.key))
    elseif cmd == "rate" then
        RateCommand(rest)
    elseif cmd == "group" or cmd == "log" then
        ns:LogGroup()
    elseif cmd == "unlock" then
        ns:ToggleAlertAnchor(true)
    elseif cmd == "lock" then
        ns:ToggleAlertAnchor(false)
    elseif cmd == "test" then
        ns:TestAlert()
    elseif cmd == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns:Print("debug", ns.db.settings.debug and "on" or "off")
    else
        Help()
    end
end

-- Addon compartment (the addon button next to the minimap).
function AndreddiPvE_OnCompartmentClick(_, button)
    if button == "RightButton" then
        ns:ShowMainWindow("settings")
    else
        ns:ToggleMainWindow("runs")
    end
end

function AndreddiPvE_OnCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("AndreddiPvE")
    if ns.db then
        local players = 0
        for _ in pairs(ns.db.players) do players = players + 1 end
        GameTooltip:AddLine(#ns.db.runs .. " runs, " .. players .. " players", 1, 1, 1)
        if ns.activeRun then
            GameTooltip:AddLine("Tracking: " .. ns:RunTitle(ns.activeRun), 0.25, 0.66, 0.96)
        end
    end
    GameTooltip:AddLine("Left-click: history   Right-click: settings", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function AndreddiPvE_OnCompartmentLeave()
    GameTooltip:Hide()
end
