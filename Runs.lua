local _, ns = ...
local Safe = ns.Safe
local SafeCall = ns.SafeCall

-- Automatic run tracking. A run starts when you are in a dungeon or raid with a
-- group, and records who was in it (with role, deaths and whether they left),
-- the bosses killed, wipes, and the key level and timer for Mythic+.
--
-- A run ends when you leave the group, enter another instance, or stay outside
-- the instance for GRACE seconds (so corpse runs and repair trips don't end it).
-- Completion comes from CHALLENGE_MODE_COMPLETED (keys), LFG_COMPLETION_REWARD
-- (finder groups) or a full clear of the instance lockout. Every event here is
-- optional: clients that lack one simply don't report that part.

local GRACE = 900    -- seconds outside the instance before a run ends
local MIN_RUN = 120  -- shorter runs without a boss, completion or rating are dropped

ns.activeRun = nil

local dead = {}      -- key -> was dead at the last check ("player" for ourselves)

local function MyRole()
    local role = SafeCall(UnitGroupRolesAssigned, "player")
    if role == "NONE" or role == "" then return nil end
    return role
end

local function KeystoneActive()
    if not C_ChallengeMode then return false end
    if C_ChallengeMode.IsChallengeModeActive then
        return SafeCall(C_ChallengeMode.IsChallengeModeActive) and true or false
    end
    local level = SafeCall(C_ChallengeMode.GetActiveKeystoneInfo)
    return (level or 0) > 0
end

-- What we're in, or nil outside dungeons and raids.
local function CurrentInstance()
    local inInstance, instanceType = SafeCall(IsInInstance)
    if not inInstance then return nil end
    local name, itype, difficultyID, difficultyName, _, _, _, instanceID = SafeCall(GetInstanceInfo)
    itype = itype or instanceType
    local kind
    if itype == "party" then
        kind = "dungeon"
    elseif itype == "raid" then
        kind = "raid"
    else
        return nil
    end
    if kind == "dungeon" and (difficultyID == 8 or KeystoneActive()) then kind = "mplus" end
    return {
        kind = kind,
        name = name,
        difficulty = difficultyName,
        difficultyID = difficultyID,
        instanceID = instanceID,
    }
end

local function Tracked(kind)
    local s = ns.db.settings
    if kind == "mplus" then return s.trackMythicPlus end
    if kind == "dungeon" then return s.trackDungeons end
    if kind == "raid" then return s.trackRaids end
    return false
end

local function ApplyKeystone(run)
    if not C_ChallengeMode then return end
    local level = SafeCall(C_ChallengeMode.GetActiveKeystoneInfo)
    if level and level > 0 then run.keyLevel = level end
    local mapID = SafeCall(C_ChallengeMode.GetActiveChallengeMapID)
    if mapID then
        run.mapID = mapID
        local name = SafeCall(C_ChallengeMode.GetMapUIInfo, mapID)
        if name and name ~= "" then run.instance = name end
    end
end

local function HasRatings(run)
    for _, m in pairs(run.members) do
        if m.rating then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Roster
--------------------------------------------------------------------------------

-- Adds everyone in the group to the run and marks those who are gone.
local function SyncRoster(run)
    local present = {}
    local changed = false
    for _, unit in ipairs(ns:GroupUnits()) do
        local info = ns:ReadUnit(unit)
        if info then
            present[info.key] = true
            info = ns:Remember(info)
            if ns:AddRunMember(run, info, SafeCall(UnitGroupRolesAssigned, unit), true) then changed = true end
        end
    end
    -- While names are still loading nobody can be read; don't mark everyone gone.
    if next(present) or not IsInGroup() then
        for key, m in pairs(run.members) do
            if not present[key] and not m.left then
                m.left = time()
                changed = true
            end
        end
    end
    local role = MyRole()
    if role and run.myRole ~= role then run.myRole = role end
    if changed then ns:Fire("DATA_CHANGED", "run", run.id) end
end

--------------------------------------------------------------------------------
-- Start / end
--------------------------------------------------------------------------------

local function MaybePopup(run)
    local s = ns.db.settings
    if run.popped or run.kind == "raid" or run.kind == "manual" or not s.popupAfterDungeon then return end
    if not next(run.members) then return end
    if not run.completed and not s.popupOnLeave then return end
    run.popped = true
    ns:QueueRunPopup(run)
end

local function StartRun(inst)
    local run = ns:NewRun({
        kind = inst.kind,
        instance = inst.name,
        instanceID = inst.instanceID,
        difficulty = inst.difficulty,
        difficultyID = inst.difficultyID,
        myRole = MyRole(),
    })
    if inst.kind == "mplus" then ApplyKeystone(run) end
    run.lastActive = time()
    ns.activeRun = run
    ns.db.activeRunID = run.id
    wipe(dead)
    ns:Debug("Run started:", ns:RunTitle(run))
    return run
end

-- quiet: no popup (used for runs found stale at login).
function ns:EndRun(run, quiet)
    run = run or ns.activeRun
    if not run or run.ended then return end
    run.ended = run.away or time()
    run.away = nil
    if ns.activeRun == run then
        ns.activeRun = nil
        ns.db.activeRunID = nil
    end
    wipe(dead)
    ns:Debug("Run ended:", ns:RunTitle(run))
    if #run.bosses == 0 and not run.completed and not HasRatings(run) and run.ended - run.t < MIN_RUN then
        ns:DeleteRun(run)
        return
    end
    ns:Fire("DATA_CHANGED", "run", run.id)
    if not quiet then MaybePopup(run) end
end

local function Complete(run)
    if run.completed then return end
    run.completed = true
    ns:Fire("DATA_CHANGED", "run", run.id)
    -- Let the loot and completion banners settle first.
    C_Timer.After(2, function() MaybePopup(run) end)
end

-- Decides whether a run should start, continue or end, given where we are.
local function Evaluate()
    if not ns.db then return end
    local inst = CurrentInstance()
    local grouped = IsInGroup()
    local run = ns.activeRun

    if run then
        if inst and inst.instanceID == run.instanceID and grouped then
            run.away = nil
            SyncRoster(run)
            return
        end
        if grouped and not inst then
            -- Outside, still grouped: corpse run, repairs, or done. Wait.
            run.away = run.away or time()
            return
        end
        ns:EndRun(run)
    end

    if inst and grouped and Tracked(inst.kind) then
        SyncRoster(StartRun(inst))
    end
end

--------------------------------------------------------------------------------
-- Deaths (polled: Forever has no combat log, and Midnight hides it in instances)
--------------------------------------------------------------------------------

local function CheckDeaths(run)
    local changed = false
    for _, unit in ipairs(ns:GroupUnits()) do
        local raw, second = SafeCall(UnitName, unit)
        if raw and raw ~= "" and raw ~= UNKNOWNOBJECT and not SafeCall(UnitIsUnit, unit, "player") then
            local name, realm = ns:NameAndRealm(raw, second)
            local key = name .. "-" .. realm
            local m = run.members[key]
            local isDead = SafeCall(UnitIsDeadOrGhost, unit)
            if m and isDead ~= nil then
                -- The first look only sets a baseline, so a reload doesn't count
                -- people who are already dead.
                if isDead and dead[key] == false then
                    m.deaths = (m.deaths or 0) + 1
                    changed = true
                end
                dead[key] = isDead and true or false
            end
        end
    end
    local meDead = SafeCall(UnitIsDeadOrGhost, "player")
    if meDead ~= nil then
        if meDead and dead.player == false then
            run.myDeaths = (run.myDeaths or 0) + 1
            changed = true
        end
        dead.player = meDead and true or false
    end
    if changed then ns:Fire("DATA_CHANGED", "run", run.id) end
end

local ticks = 0
local function Tick()
    local run = ns.activeRun
    ticks = ticks + 1
    if run then
        if run.away then
            if time() - run.away >= GRACE then ns:EndRun(run) end
        else
            run.lastActive = time()
            CheckDeaths(run)
        end
    end
    -- Catch names that were still loading and groups formed inside an instance.
    if ticks % 5 == 0 then Evaluate() end
end

--------------------------------------------------------------------------------
-- Bosses and completion
--------------------------------------------------------------------------------

local function CheckFullClear(run)
    if run.kind == "mplus" or run.completed then return end
    local _, _, total, done = SafeCall(GetInstanceLockTimeRemaining)
    if total and total > 0 then
        run.bossTotal = total
        if done and done >= total then Complete(run) end
    end
end

local function BossKilled(encounterID, name)
    local run = ns.activeRun
    if not run or run.away then return end
    encounterID, name = Safe(encounterID), Safe(name)
    -- ENCOUNTER_END and BOSS_KILL both report the same kill.
    for _, b in ipairs(run.bosses) do
        if (encounterID and b.id == encounterID) or (name and b.name == name) then return end
    end
    table.insert(run.bosses, { id = encounterID, name = name, t = time() })
    ns:Fire("DATA_CHANGED", "run", run.id)
    -- The lockout updates a moment after the kill.
    C_Timer.After(3, function()
        if ns.activeRun == run then CheckFullClear(run) end
    end)
end

ns:On("ENCOUNTER_END", function(_, encounterID, name, _, _, success)
    success = Safe(success)
    if success == 1 then
        BossKilled(encounterID, name)
    elseif success == 0 then
        local run = ns.activeRun
        if run and not run.away then
            run.wipes = (run.wipes or 0) + 1
            ns:Fire("DATA_CHANGED", "run", run.id)
        end
    end
end)

ns:On("BOSS_KILL", function(_, encounterID, name)
    BossKilled(encounterID, name)
end)

ns:On("LFG_COMPLETION_REWARD", function()
    if ns.activeRun then Complete(ns.activeRun) end
end)

ns:On("CHALLENGE_MODE_START", function()
    -- Difficulty and key info update just after the event.
    C_Timer.After(0.5, function()
        local run = ns.activeRun
        if run and run.completed then
            ns:EndRun(run)
            run = nil
        end
        if run then
            if not ns.db.settings.trackMythicPlus then
                run.popped = true
                ns:EndRun(run)
                return
            end
            if run.kind ~= "mplus" then
                -- The run so far was the walk-in; the key starts it properly.
                run.kind = "mplus"
                run.t = time()
                wipe(run.bosses)
                run.wipes = 0
                run.myDeaths = 0
                for _, m in pairs(run.members) do m.deaths = 0 end
            end
            ApplyKeystone(run)
            ns:Fire("DATA_CHANGED", "run", run.id)
        else
            Evaluate()
        end
    end)
end)

ns:On("CHALLENGE_MODE_COMPLETED", function()
    local run = ns.activeRun
    if not run then
        Evaluate()
        run = ns.activeRun
    end
    if not run or not C_ChallengeMode then return end

    local level, timeMs, onTime, upgrade
    if C_ChallengeMode.GetChallengeCompletionInfo then
        local info = SafeCall(C_ChallengeMode.GetChallengeCompletionInfo)
        if type(info) == "table" then
            level, timeMs = Safe(info.level), Safe(info.time)
            onTime, upgrade = Safe(info.onTime), Safe(info.keystoneUpgradeLevels)
        end
    elseif C_ChallengeMode.GetCompletionInfo then
        local _
        _, level, timeMs, onTime, upgrade = SafeCall(C_ChallengeMode.GetCompletionInfo)
    end

    run.kind = "mplus"
    if level and level > 0 then run.keyLevel = level end
    if timeMs then run.duration = math.floor(timeMs / 1000) end
    run.timed = onTime and true or false
    run.upgrade = upgrade
    Complete(run)
end)

--------------------------------------------------------------------------------
-- Zone and group changes
--------------------------------------------------------------------------------

ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, Evaluate) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(0.5, Evaluate) end)

local rosterPending = false
ns:On("GROUP_ROSTER_UPDATE", function()
    if rosterPending then return end
    rosterPending = true
    C_Timer.After(0.5, function()
        rosterPending = false
        Evaluate()
    end)
end)

ns:Listen("LOGIN", function()
    -- Pick up a run that was in progress before a reload or disconnect.
    local id = ns.db.activeRunID
    local run = id and ns:GetRun(id)
    if run and not run.ended then
        ns.activeRun = run
        if time() - (run.lastActive or run.t) > GRACE then
            run.away = run.lastActive or run.t
            ns:EndRun(run, true)
        end
    else
        ns.db.activeRunID = nil
    end
    C_Timer.NewTicker(1, Tick)
end)

--------------------------------------------------------------------------------
-- Manual logging (right-click menu, slash commands, Runs tab)
--------------------------------------------------------------------------------

-- Opens the rating popup for the group. Without a tracked run, the group is
-- saved as a "Logged" run first.
function ns:LogGroup()
    local run = ns.activeRun
    if run then
        SyncRoster(run)
        ns:QueueRunPopup(run)
        return run
    end
    if not IsInGroup() then
        ns:Print("You're not in a group.")
        return nil
    end
    local inst = CurrentInstance()
    local zone = ns:ZoneInfo()
    run = ns:NewRun({
        kind = "manual",
        instance = inst and inst.name or zone,
        difficulty = inst and inst.difficulty,
        instanceID = inst and inst.instanceID,
        myRole = MyRole(),
    })
    run.ended = run.t
    SyncRoster(run)
    ns:Print("Logged your group as a run:", ns:RunTitle(run))
    ns:QueueRunPopup(run)
    return run
end

-- Adds one player to the run in progress, or to a "Logged" run for this zone
-- (reused for an hour, so several adds end up in one run).
function ns:AddToHistory(info)
    local run = ns.activeRun
    if not run then
        local zone = ns:ZoneInfo()
        local last = ns.db.runs[#ns.db.runs]
        if last and last.kind == "manual" and last.instance == zone and last.me == ns:MyKey()
            and time() - last.t < 3600 then
            run = last
        else
            run = ns:NewRun({ kind = "manual", instance = zone })
            run.ended = run.t
        end
    end
    ns:AddRunMember(run, info)
    return run
end
