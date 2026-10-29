local _, ns = ...
local Safe = ns.Safe
local SafeCall = ns.SafeCall

-- Group finder (retail): an alert when someone you know applies to your listed
-- group, and history lines in applicant and search result tooltips. Clients
-- without C_LFGList skip all of this.

local function KeyFromName(name)
    name = Safe(name)
    if not name or name == "" then return nil end
    return ns:FindPlayerKey(name)
end

--------------------------------------------------------------------------------
-- Applicant alerts
--------------------------------------------------------------------------------

local function CheckApplicant(applicantID)
    if not ns.db or not ns.db.settings.lfgAlerts or not C_LFGList then return end
    local info = SafeCall(C_LFGList.GetApplicantInfo, applicantID)
    if type(info) ~= "table" then return end
    local status = Safe(info.applicationStatus)
    if status and status ~= "applied" then return end
    for i = 1, Safe(info.numMembers) or 1 do
        local name, class, _, level = SafeCall(C_LFGList.GetApplicantMemberInfo, applicantID, i)
        local key = KeyFromName(name)
        if key then
            local data = { key = key, class = class, level = level and level > 0 and level or nil }
            ns:UpdateKnownPlayer(data)
            ns:MaybeAlert(data, "applicant")
        end
    end
end

ns:On("LFG_LIST_APPLICANT_UPDATED", function(_, applicantID)
    CheckApplicant(applicantID)
end)

ns:On("LFG_LIST_APPLICANT_LIST_UPDATED", function()
    local ids = C_LFGList and SafeCall(C_LFGList.GetApplicants)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do CheckApplicant(id) end
end)

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

-- Search results only expose the leader's name.
local function OnSearchEntryTooltip(tooltip, resultID)
    if not ns.db or not ns.db.settings.lfgTooltips then return end
    local info = SafeCall(C_LFGList.GetSearchResultInfo, resultID)
    local key = type(info) == "table" and KeyFromName(info.leaderName)
    if key and ns:AddPlayerTooltip(tooltip, key, nil, "(leader " .. ns:ShortName(key) .. ")") then
        tooltip:Show()
    end
end

local function OnApplicantMemberEnter(member)
    if not ns.db or not ns.db.settings.lfgTooltips then return end
    local parent = member and member:GetParent()
    local applicantID = parent and parent.applicantID
    if not applicantID or not member.memberIdx then return end
    local key = KeyFromName((SafeCall(C_LFGList.GetApplicantMemberInfo, applicantID, member.memberIdx)))
    if key and ns:AddPlayerTooltip(GameTooltip, key) then GameTooltip:Show() end
end

local hooked = {}
local function TryHooks()
    if not C_LFGList then return end
    if not hooked.search and LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(...)
            local ok, err = pcall(OnSearchEntryTooltip, ...)
            if not ok then ns:Debug("LFG tooltip error: " .. tostring(err)) end
        end)
        hooked.search = true
    end
    if not hooked.applicant and LFGListApplicantMember_OnEnter then
        hooksecurefunc("LFGListApplicantMember_OnEnter", function(...)
            local ok, err = pcall(OnApplicantMemberEnter, ...)
            if not ok then ns:Debug("LFG tooltip error: " .. tostring(err)) end
        end)
        hooked.applicant = true
    end
end

-- The group finder UI may load after us.
ns:Listen("LOGIN", TryHooks)
ns:On("ADDON_LOADED", TryHooks)
