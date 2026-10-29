local _, ns = ...

-- Database layout (AndreddiPvEDB, account wide):
--   players[key]  = { name, realm, guid, class, race, level, faction, guild, guildKey,
--                     firstSeen, lastSeen, list, note }
--   guilds[gkey]  = { name, realm, list, note, firstSeen, lastSeen, members = { [key] = true } }
--   runs[i]       = { id, t, ended, kind = "mplus"|"dungeon"|"raid"|"manual",
--                     instance, instanceID, difficulty, difficultyID, mapID, keyLevel,
--                     completed, timed, upgrade, duration, bosses = { { id, name, t } },
--                     bossTotal, wipes, myDeaths, myRole, me, popped,
--                     members = { [key] = { class, role, level, guildKey, joined, left,
--                                           deaths, rating } } }
-- Runs are stored oldest first. Ourselves are never a member.

function ns:GetPlayer(key)
    return key and ns.db.players[key]
end

function ns:GetGuild(gkey)
    return gkey and ns.db.guilds[gkey]
end

local function SplitKey(key)
    return ns:SplitKey(key)
end

-- Key for a name the user typed. Matches an existing record (or a recently
-- seen player) regardless of capitalisation, so "first surname" finds
-- "First Surname".
function ns:FindPlayerKey(text)
    local key = ns:PlayerKey(text, nil)
    if not key or ns.db.players[key] or (ns.seenByKey and ns.seenByKey[key]) then return key end
    local lower = key:lower()
    for k in pairs(ns.db.players) do
        if k:lower() == lower then return k end
    end
    for k in pairs(ns.seenByKey or {}) do
        if k:lower() == lower then return k end
    end
    return key
end

function ns:TouchGuild(gkey)
    if not gkey then return nil end
    local g = ns.db.guilds[gkey]
    if not g then
        local name, realm = SplitKey(gkey)
        g = { name = name, realm = realm, members = {}, firstSeen = time() }
        ns.db.guilds[gkey] = g
    end
    g.lastSeen = time()
    return g
end

-- Copies whatever is known from info into the record. Guild membership is only
-- changed when info actually carries guild data, because units out of inspect
-- range often report no guild.
local function ApplyInfo(p, key, info)
    if info.guid then p.guid = info.guid end
    if info.class then p.class = info.class end
    if info.race then p.race = info.race end
    if info.level then p.level = info.level end
    if info.faction then p.faction = info.faction end
    if info.guildKey and info.guildKey ~= p.guildKey then
        local old = ns:GetGuild(p.guildKey)
        if old and old.members then old.members[key] = nil end
        p.guildKey = info.guildKey
        p.guild = info.guild
    end
    if p.guildKey then
        local g = ns:GetGuild(p.guildKey)
        if g then
            g.members = g.members or {}
            g.members[key] = true
        end
    end
end

-- Creates or updates a player record. info needs at least .key (or .name).
function ns:TouchPlayer(info)
    local key = info.key or ns:PlayerKey(info.name, info.realm)
    if not key then return nil end
    info.key = key
    local p = ns.db.players[key]
    if not p then
        local name, realm = SplitKey(key)
        p = { name = name, realm = realm, firstSeen = time() }
        ns.db.players[key] = p
    end
    if info.guildKey then ns:TouchGuild(info.guildKey) end
    ApplyInfo(p, key, info)
    p.lastSeen = time()
    return p
end

-- Refreshes an existing record from a sighting without creating new ones.
function ns:UpdateKnownPlayer(info)
    local p = info.key and ns.db.players[info.key]
    if not p then return nil end
    if info.guildKey and ns.db.guilds[info.guildKey] == nil and info.guildKey ~= p.guildKey then
        ns:TouchGuild(info.guildKey)
    end
    ApplyInfo(p, info.key, info)
    p.lastSeen = time()
    return p
end

--------------------------------------------------------------------------------
-- Lists and notes
--------------------------------------------------------------------------------

function ns:SetPlayerList(key, list)
    local p = ns.db.players[key] or ns:TouchPlayer({ key = key })
    p.list = list
    ns:Fire("DATA_CHANGED", "player", key)
end

function ns:SetGuildList(gkey, list)
    local g = ns:TouchGuild(gkey)
    g.list = list
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

local function CleanNote(text)
    text = text and strtrim(text) or ""
    if text == "" then return nil end
    return text
end

function ns:SetPlayerNote(key, text)
    local p = ns.db.players[key] or ns:TouchPlayer({ key = key })
    p.note = CleanNote(text)
    ns:Fire("DATA_CHANGED", "player", key)
end

function ns:SetGuildNote(gkey, text)
    local g = ns:TouchGuild(gkey)
    g.note = CleanNote(text)
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

-- The list that applies to a player: their own list wins over their guild's.
-- Returns list, source ("player" or "guild").
function ns:EffectiveList(key, guildKey)
    local p = ns.db.players[key]
    if p and p.list then return p.list, "player" end
    local g = ns:GetGuild(guildKey or (p and p.guildKey))
    if g and g.list then return g.list, "guild" end
    return nil
end

function ns:DeletePlayer(key)
    local p = ns.db.players[key]
    if not p then return end
    local g = ns:GetGuild(p.guildKey)
    if g and g.members then g.members[key] = nil end
    ns.db.players[key] = nil
    for _, run in ipairs(ns.db.runs) do run.members[key] = nil end
    ns:Fire("DATA_CHANGED", "player", key)
end

-- Removes the guild record (list, note). Member players and runs stay.
function ns:DeleteGuild(gkey)
    ns.db.guilds[gkey] = nil
    ns:Fire("DATA_CHANGED", "guild", gkey)
end

--------------------------------------------------------------------------------
-- Run index: per player and per guild totals, rebuilt lazily after any change
--------------------------------------------------------------------------------

local index
local EMPTY = { runs = {}, ratingN = 0, deaths = 0, completed = 0 }

local function BuildIndex()
    local players, guilds = {}, {}
    for _, run in ipairs(ns.db.runs) do
        local guildSeen = {}
        for key, m in pairs(run.members) do
            local s = players[key]
            if not s then
                s = { runs = {}, ratingSum = 0, ratingN = 0, deaths = 0, completed = 0 }
                players[key] = s
            end
            table.insert(s.runs, run)
            if m.rating then
                s.ratingSum = s.ratingSum + m.rating
                s.ratingN = s.ratingN + 1
            end
            s.deaths = s.deaths + (m.deaths or 0)
            if run.completed then s.completed = s.completed + 1 end

            local gk = m.guildKey
            if gk then
                local gs = guilds[gk]
                if not gs then
                    gs = { runs = 0, ratingSum = 0, ratingN = 0 }
                    guilds[gk] = gs
                end
                if not guildSeen[gk] then
                    guildSeen[gk] = true
                    gs.runs = gs.runs + 1
                    gs.last = run
                end
                if m.rating then
                    gs.ratingSum = gs.ratingSum + m.rating
                    gs.ratingN = gs.ratingN + 1
                end
            end
        end
    end
    for _, s in pairs(players) do
        s.rating = s.ratingN > 0 and s.ratingSum / s.ratingN or nil
    end
    for _, gs in pairs(guilds) do
        gs.rating = gs.ratingN > 0 and gs.ratingSum / gs.ratingN or nil
    end
    index = { players = players, guilds = guilds }
end

-- Registered before any UI listener, so the index is stale before they redraw.
ns:Listen("DATA_CHANGED", function() index = nil end)
ns:Listen("DB_READY", function() index = nil end)

-- { runs = { run, ... oldest first }, rating, ratingN, deaths, completed }
function ns:PlayerSummary(key)
    if not index then BuildIndex() end
    return index.players[key] or EMPTY
end

-- { runs (count), rating, ratingN, last }
function ns:GuildSummary(gkey)
    if not index then BuildIndex() end
    return index.guilds[gkey] or { runs = 0, ratingN = 0 }
end

-- Runs with this player, not counting the run in progress. Returns count, last run.
function ns:PriorRuns(key)
    local runs = ns:PlayerSummary(key).runs
    local active = ns.activeRun
    local count, last = 0, nil
    for i = #runs, 1, -1 do
        if runs[i] ~= active then
            count = count + 1
            last = last or runs[i]
        end
    end
    return count, last
end

-- Latest run (including the one in progress) this player was in.
function ns:LastRunWith(key)
    local runs = ns:PlayerSummary(key).runs
    return runs[#runs]
end

-- Has this player (or their guild) any history or list membership worth
-- telling the user about? The run in progress doesn't count.
function ns:IsInteresting(key, guildKey)
    local p = ns.db.players[key]
    if p and (p.list or p.note) then return true end
    if ns:PriorRuns(key) > 0 then return true end
    local g = ns:GetGuild(guildKey or (p and p.guildKey))
    if g and (g.list or g.note) then return true end
    return false
end

--------------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------------

ns.KIND_INFO = {
    mplus   = { label = "Mythic+",  short = "M+" },
    dungeon = { label = "Dungeon",  short = "Dungeon" },
    raid    = { label = "Raid",     short = "Raid" },
    manual  = { label = "Logged",   short = "Logged" },
}

function ns:GetRun(id)
    local runs = ns.db.runs
    for i = #runs, 1, -1 do
        if runs[i].id == id then return runs[i] end
    end
end

function ns:NewRun(run)
    run.id = ns.db.nextRunID
    ns.db.nextRunID = ns.db.nextRunID + 1
    run.t = run.t or time()
    run.me = ns:MyKey()
    run.members = run.members or {}
    run.bosses = run.bosses or {}
    run.wipes = run.wipes or 0
    run.myDeaths = run.myDeaths or 0
    table.insert(ns.db.runs, run)
    ns:Fire("DATA_CHANGED", "run", run.id)
    return run
end

-- Adds or refreshes a member. Returns true when something visible changed.
-- silent: don't fire DATA_CHANGED (the caller fires once for a batch).
function ns:AddRunMember(run, info, role, silent)
    local p = ns:TouchPlayer(info)
    if not p then return false end
    local key = info.key
    local m = run.members[key]
    local changed = false
    if not m then
        m = { joined = time(), deaths = 0 }
        run.members[key] = m
        changed = true
    end
    if m.left then
        m.left = nil
        changed = true
    end
    m.class = p.class or m.class
    m.level = info.level or m.level or p.level
    m.guildKey = p.guildKey or m.guildKey
    if role and role ~= "NONE" and role ~= "" and m.role ~= role then
        m.role = role
        changed = true
    end
    if changed and not silent then ns:Fire("DATA_CHANGED", "run", run.id) end
    return changed
end

function ns:SetRunRating(run, key, rating)
    local m = run and run.members[key]
    if not m then return end
    m.rating = rating
    ns:Fire("DATA_CHANGED", "run", run.id)
end

function ns:RemoveRunMember(run, key)
    run.members[key] = nil
    ns:Fire("DATA_CHANGED", "run", run.id)
end

function ns:DeleteRun(run)
    local list = ns.db.runs
    for i = #list, 1, -1 do
        if list[i] == run then
            table.remove(list, i)
            break
        end
    end
    if ns.activeRun == run then
        ns.activeRun = nil
        ns.db.activeRunID = nil
    end
    ns:Fire("DATA_CHANGED", "run", run.id)
end

-- "Ara-Kara +12", "Nerub-ar Palace (Heroic)", "Deadmines"
function ns:RunTitle(run)
    local name = run.instance or "Unknown"
    if name == "" then name = "Unknown" end
    if run.kind == "mplus" and run.keyLevel then return name .. " +" .. run.keyLevel end
    if run.difficulty and run.difficulty ~= "" then return name .. " (" .. run.difficulty .. ")" end
    return name
end

function ns:BossText(run)
    local n = #run.bosses
    if run.bossTotal and run.bossTotal > 0 then return n .. "/" .. run.bossTotal .. " bosses" end
    return n == 1 and "1 boss" or (n .. " bosses")
end

-- Coloured one-word outcome.
function ns:RunResult(run)
    if run.kind == "manual" then return "|cff999999Logged|r" end
    if run == ns.activeRun and not run.completed then return "|cff3fa9f5In progress|r" end
    if run.kind == "mplus" then
        if not run.completed then return "|cffff4040Abandoned|r" end
        if run.timed then
            return "|cff40ff40Timed|r" .. ((run.upgrade or 0) > 1 and (" |cff40ff40+" .. run.upgrade .. "|r") or "")
        end
        return "|cffffd100Over time|r"
    end
    if run.completed then return "|cff40ff40Completed|r" end
    if #run.bosses > 0 then return "|cffffd100" .. ns:BossText(run) .. "|r" end
    return "|cffff4040No bosses|r"
end

-- Run length in seconds (the key timer for completed keys).
function ns:RunLength(run)
    if run.duration then return run.duration end
    if run.kind == "manual" then return nil end
    return (run.ended or time()) - run.t
end

-- Left the group more than a minute before the run ended.
function ns:LeftEarly(run, m)
    if not m.left then return false end
    if run.completed and run.kind == "mplus" then return false end
    return m.left < (run.ended or time()) - 60
end

-- Members of a run sorted tank, healer, damage, then name.
function ns:SortedMembers(run)
    local out = {}
    for key, m in pairs(run.members) do table.insert(out, { key = key, m = m, run = run }) end
    table.sort(out, function(a, b)
        local ra, rb = ns.ROLE_ORDER[a.m.role] or 4, ns.ROLE_ORDER[b.m.role] or 4
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)
    return out
end

-- "Ara-Kara +12 · Timed · 3 days ago"
function ns:RunLine(run)
    return ns:RunTitle(run) .. " · " .. ns:RunResult(run) .. " |cff999999· " .. ns:Ago(run.t) .. "|r"
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

local function StartOfDay(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

local function StartOfWeek(t)
    local d = date("*t", t)
    local offset = (d.wday + 5) % 7 -- days since Monday
    d.day = d.day - offset
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

local function StartOfMonth(t)
    local d = date("*t", t)
    d.day, d.hour, d.min, d.sec = 1, 0, 0, 0
    return time(d)
end

local function StartOfYear(t)
    local d = date("*t", t)
    d.month, d.day, d.hour, d.min, d.sec = 1, 1, 0, 0, 0
    return time(d)
end

ns.StartOfDay = StartOfDay

-- Builds every number the statistics tab shows. me: restrict to one character
-- key, or nil for all characters.
function ns:ComputeStats(me)
    local now = time()
    local periods = {
        { label = "Today",      from = StartOfDay(now) },
        { label = "This week",  from = StartOfWeek(now) },
        { label = "This month", from = StartOfMonth(now) },
        { label = "This year",  from = StartOfYear(now) },
        { label = "All time",   from = 0 },
    }
    for _, p in ipairs(periods) do p.runs, p.completed, p.mplus = 0, 0, 0 end

    local DAYS = 14
    local today = StartOfDay(now)
    local daily = {}
    for i = 1, DAYS do
        local d = date("*t", today)
        d.day = d.day - (DAYS - i)
        daily[i] = { from = time(d), runs = 0, completed = 0 }
    end

    local total = { runs = 0, completed = 0, tracked = 0, mplus = 0, timed = 0 }
    local instances, players, guilds = {}, {}, {}
    local ratingSum, ratingN = 0, 0
    local firstT

    for _, run in ipairs(ns.db.runs) do
        if not me or run.me == me then
            total.runs = total.runs + 1
            if run.kind ~= "manual" then total.tracked = total.tracked + 1 end
            if run.completed then total.completed = total.completed + 1 end
            if run.kind == "mplus" then
                total.mplus = total.mplus + 1
                if run.completed and run.timed then total.timed = total.timed + 1 end
            end
            firstT = firstT and math.min(firstT, run.t) or run.t

            for _, p in ipairs(periods) do
                if run.t >= p.from then
                    p.runs = p.runs + 1
                    if run.completed then p.completed = p.completed + 1 end
                    if run.kind == "mplus" then p.mplus = p.mplus + 1 end
                end
            end
            if run.t >= daily[1].from then
                for i = DAYS, 1, -1 do
                    if run.t >= daily[i].from then
                        daily[i].runs = daily[i].runs + 1
                        if run.completed then daily[i].completed = daily[i].completed + 1 end
                        break
                    end
                end
            end

            if run.kind ~= "manual" then
                local name = run.instance or "Unknown"
                local inst = instances[name]
                if not inst then
                    inst = { name = name, runs = 0, completed = 0 }
                    instances[name] = inst
                end
                inst.runs = inst.runs + 1
                if run.completed then inst.completed = inst.completed + 1 end
                if run.kind == "mplus" and run.keyLevel and run.completed and run.timed then
                    inst.bestKey = math.max(inst.bestKey or 0, run.keyLevel)
                end
            end

            local guildSeen = {}
            for key, m in pairs(run.members) do
                local pl = players[key]
                if not pl then
                    pl = { key = key, class = m.class, runs = 0, ratingSum = 0, ratingN = 0 }
                    players[key] = pl
                end
                pl.runs = pl.runs + 1
                pl.class = pl.class or m.class
                if m.rating then
                    pl.ratingSum = pl.ratingSum + m.rating
                    pl.ratingN = pl.ratingN + 1
                    ratingSum = ratingSum + m.rating
                    ratingN = ratingN + 1
                end
                if m.guildKey and not guildSeen[m.guildKey] then
                    guildSeen[m.guildKey] = true
                    guilds[m.guildKey] = guilds[m.guildKey] or { key = m.guildKey, runs = 0 }
                    guilds[m.guildKey].runs = guilds[m.guildKey].runs + 1
                end
            end
        end
    end

    local partners, rated, guildList, instanceList = {}, {}, {}, {}
    local playersMet = 0
    for _, pl in pairs(players) do
        playersMet = playersMet + 1
        table.insert(partners, pl)
        if pl.ratingN > 0 then
            pl.rating = pl.ratingSum / pl.ratingN
            table.insert(rated, pl)
        end
    end
    for _, g in pairs(guilds) do table.insert(guildList, g) end
    for _, inst in pairs(instances) do table.insert(instanceList, inst) end

    table.sort(partners, function(a, b)
        if a.runs ~= b.runs then return a.runs > b.runs end
        return a.key < b.key
    end)
    table.sort(guildList, function(a, b)
        if a.runs ~= b.runs then return a.runs > b.runs end
        return a.key < b.key
    end)
    table.sort(instanceList, function(a, b)
        if a.runs ~= b.runs then return a.runs > b.runs end
        return a.name < b.name
    end)
    local topRated, lowRated = {}, {}
    for i, pl in ipairs(rated) do topRated[i], lowRated[i] = pl, pl end
    table.sort(topRated, function(a, b)
        if a.rating ~= b.rating then return a.rating > b.rating end
        if a.ratingN ~= b.ratingN then return a.ratingN > b.ratingN end
        return a.key < b.key
    end)
    table.sort(lowRated, function(a, b)
        if a.rating ~= b.rating then return a.rating < b.rating end
        if a.ratingN ~= b.ratingN then return a.ratingN > b.ratingN end
        return a.key < b.key
    end)

    -- Averages per day/week/month since the first recorded run.
    local averages
    if firstT then
        local days = math.max(1, (now - firstT) / 86400)
        averages = {
            perDay = total.runs / days,
            perWeek = total.runs / math.max(1, days / 7),
            perMonth = total.runs / math.max(1, days / 30.44),
        }
    end

    return {
        total = total,
        periods = periods,
        daily = daily,
        instances = instanceList,
        partners = partners,
        topRated = topRated,
        lowRated = lowRated,
        guilds = guildList,
        playersMet = playersMet,
        ratingAvg = ratingN > 0 and ratingSum / ratingN or nil,
        averages = averages,
        firstT = firstT,
    }
end
