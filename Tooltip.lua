local _, ns = ...
local Safe = ns.Safe
local SafeCall = ns.SafeCall

-- Adds run history, list and note lines to player tooltips. LFG.lua uses the
-- same lines for group finder tooltips.

-- who: optional text after the header, e.g. "leader". Returns true if lines
-- were added.
function ns:AddPlayerTooltip(tooltip, key, guildKey, who)
    if not ns.db or not ns.db.settings.tooltipEnabled or not key then return false end
    local p = ns:GetPlayer(key)
    local gkey = guildKey or (p and p.guildKey)
    local g = ns:GetGuild(gkey)
    if not ns:IsInteresting(key, gkey) then return false end

    local list, source = ns:EffectiveList(key, gkey)
    local header = ns.title
    if who then header = header .. " |cff999999" .. who .. "|r" end
    if list then
        header = header .. " " .. ns:ListTag(list)
        if source == "guild" then header = header .. " |cff999999(guild)|r" end
    end
    tooltip:AddLine(header)

    local count, last = ns:PriorRuns(key)
    if count > 0 then
        local s = ns:PlayerSummary(key)
        local right = tostring(count)
        if s.rating then right = right .. "  |cffbbbbbbrated|r " .. ns:RatingText(s.rating) end
        tooltip:AddDoubleLine("Runs together", right, 0.8, 0.8, 0.8, 1, 1, 1)
        tooltip:AddLine("Last: " .. ns:RunLine(last), 0.7, 0.7, 0.7)
    end
    if g and g.list and source ~= "guild" then
        tooltip:AddLine("Guild: " .. ns:ListTag(g.list), 0.7, 0.7, 0.7)
    end
    if ns.db.settings.tooltipShowNote then
        if p and p.note then tooltip:AddLine("Note: " .. p.note, 1, 0.82, 0, true) end
        if g and g.note then tooltip:AddLine("Guild note: " .. g.note, 1, 0.82, 0, true) end
    end
    return true
end

local function AddLines(tooltip, unit)
    if not unit then return end
    local info = ns:ReadUnit(unit)
    if not info then return end
    ns:Remember(info)
    if ns:AddPlayerTooltip(tooltip, info.key, info.guildKey) then tooltip:Show() end
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Safe(unit) or nil
    if not unit then
        -- Some tooltips (e.g. world units under the cursor) report no token.
        if SafeCall(UnitExists, "mouseover") then unit = "mouseover" end
    end
    local okAdd, err = pcall(AddLines, tooltip, unit)
    if not okAdd then ns:Debug("Tooltip error: " .. tostring(err)) end
end

ns:Listen("DB_READY", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
    end
end)
