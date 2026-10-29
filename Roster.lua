local _, ns = ...

-- Group join alerts: a toast when someone you have history with (or who is on
-- a list) joins your group, or when you join theirs.

local roster = {}     -- key -> true for the members at the last check
local seeded = false  -- the first check after login is silent (no alerts for a /reload)

local function Check()
    if not ns.db then return end
    local now = {}
    for _, unit in ipairs(ns:GroupUnits()) do
        local info = ns:ReadUnit(unit)
        if info then now[info.key] = ns:Remember(info) end
    end
    if seeded then
        for key, info in pairs(now) do
            if not roster[key] then ns:MaybeAlert(info, "group") end
        end
    end
    roster = now
    seeded = true
end

local pending = false
ns:On("GROUP_ROSTER_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Check()
    end)
end)

ns:Listen("LOGIN", function()
    C_Timer.After(3, Check)
    -- Names of new members can arrive after the roster event.
    C_Timer.NewTicker(3, function()
        if IsInGroup() then Check() end
    end)
end)
