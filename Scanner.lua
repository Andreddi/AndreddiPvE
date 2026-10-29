local _, ns = ...
local SafeCall = ns.SafeCall

-- Watches the units the client exposes (nameplates, target, focus, mouseover)
-- to keep records fresh and to raise proximity alerts for known players.

--------------------------------------------------------------------------------
-- Recently seen players (in memory only)
--------------------------------------------------------------------------------

ns.seen = {}        -- guid -> info (with .t)
ns.seenByKey = {}   -- key  -> info

local SEEN_TTL = 1800

-- Merges b into a, keeping fields a already has unless b has them too.
local function Merge(a, b)
    if not b then return a end
    if not a then return b end
    for k, v in pairs(b) do
        if v ~= nil then a[k] = v end
    end
    return a
end

function ns:Remember(info)
    if not info or not info.key then return info end
    local prev = (info.guid and ns.seen[info.guid]) or ns.seenByKey[info.key]
    local merged = Merge(prev and CopyTable(prev) or {}, info)
    merged.t = GetTime()
    if merged.guid then ns.seen[merged.guid] = merged end
    ns.seenByKey[merged.key] = merged
    return merged
end

function ns:SeenByKey(key)
    return key and ns.seenByKey[key]
end

local function PruneSeen()
    local now = GetTime()
    for guid, info in pairs(ns.seen) do
        if now - info.t > SEEN_TTL then ns.seen[guid] = nil end
    end
    for key, info in pairs(ns.seenByKey) do
        if now - info.t > SEEN_TTL then ns.seenByKey[key] = nil end
    end
end

--------------------------------------------------------------------------------
-- Units
--------------------------------------------------------------------------------

local plates = {} -- active nameplate unit tokens

-- Reads a unit and feeds every module that cares. Returns the info.
function ns:ScanUnit(unit, source)
    local info = ns:ReadUnit(unit)
    if not info then return nil end
    info = ns:Remember(info)
    ns:UpdateKnownPlayer(info)
    -- Group members get their alert when they join, not when seen.
    if not ns:InGroupWith(unit) then
        ns:MaybeAlert(info, "nearby", source)
    end
    return info
end

ns:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    plates[unit] = true
    -- Forever can fire this before the unit is populated; look again shortly.
    if not ns:ScanUnit(unit, "nameplate") then
        C_Timer.After(0.3, function()
            if plates[unit] then ns:ScanUnit(unit, "nameplate") end
        end)
    end
end)

ns:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    plates[unit] = nil
end)

ns:On("PLAYER_TARGET_CHANGED", function() ns:ScanUnit("target", "target") end)
ns:On("PLAYER_FOCUS_CHANGED", function() ns:ScanUnit("focus", "focus") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function() ns:ScanUnit("mouseover", "mouseover") end)

-- Periodic sweep: guild info often arrives a moment after the nameplate.
local sweeps = 0
local function Sweep()
    for unit in pairs(plates) do
        if SafeCall(UnitExists, unit) then
            ns:ScanUnit(unit, "nameplate")
        else
            plates[unit] = nil
        end
    end
    sweeps = sweeps + 1
    if sweeps % 60 == 0 then PruneSeen() end
end

ns:Listen("LOGIN", function()
    C_Timer.NewTicker(1, Sweep)
end)
