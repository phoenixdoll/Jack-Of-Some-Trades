--[[
    Jack of Some Trades - server-side snapshot, grant, and cap enforcement.

    Note on hooking character creation: Events.OnCreatePlayer only ever
    fires client-side in vanilla (confirmed: zero server-side registrations
    anywhere in the installed game, and the community Lua docs mark it
    "(Client)"). There is no dedicated server-side "character just created"
    event. Uses a throttled Events.OnTick counter sweeping getOnlinePlayers())
    and that vanilla's own XpUpdate.lua uses for its periodic per-player 
    maintenance (Events.EveryTenMinutes + getOnlinePlayers()). Checked every 
    ~30 ticks (roughly once a second) rather than every single tick. 
]]

print("[JOST] JOST_SkillServer.lua file loaded, isServer()=" .. tostring(isServer()) .. " isClient()=" .. tostring(isClient()))

local SkillDefs = require("JOST_SkillDefs")
local SkillCalc = require("JOST_SkillCalc")

print("[JOST] requires resolved, SkillDefs=" .. tostring(SkillDefs) .. " SkillCalc=" .. tostring(SkillCalc))

local SkillServer = {}

local MOD_DATA_KEY = "JOST"

-- Same technique as TAZC_Core.isAdmin: PZ's access level string isn't
-- reliably lowercase ("Admin" observed live), so normalize before compare.
local function isAdmin(player)
    if not player then return false end
    local ok, accessLevel = pcall(function() return player:getAccessLevel() end)
    if not ok or not accessLevel then return false end
    return tostring(accessLevel):lower() == "admin"
end

local function getModData(player)
    local modData = player:getModData()
    modData[MOD_DATA_KEY] = modData[MOD_DATA_KEY] or {}
    return modData[MOD_DATA_KEY]
end

--[[
    Force a perk to an exact level, in either direction.
]]
local function setPerkLevel(player, perkType, level)
    player:setPerkLevelDebug(perkType, level)
    player:getXp():setXPToLevel(perkType, level)
end

--[[
    One-time setup for a freshly spawned character: snapshot the traits/
    profession that were actually chosen, compute pips/caps/start levels
    from them, and grant the starting levels.

    Starting levels only ever RAISE a skill, never lower it -- if this mod
    is added to a server with already-playing characters, their genuinely
    earned progress is never reset down to the formula-derived start level.
]]
local function initializeCharacter(player)
    local data = getModData(player)
    if data.initialized then return end

    --[[ CharacterTraitDefinition.getCharacterTraitDefinition() wants the raw
    CharacterTrait-typed object (same requirement as the profession lookup
    below), confirmed by vanilla itself never converting it before passing
    it in (shared/Items/SpawnItems.lua:264, client/XpSystem/ISUI/
    ISCharacterScreen.lua:579). so `traitObjects` (raw, passed to
     computeSnapshot) is kept separate from `traitNames` (stringified via
    :getName(), confirmed real at client/LastStand/LastStandSetup.lua:128,
    used only for the ModData/log-friendly display copy). Storing the raw
    objects directly in ModData was the actual bug behind "traits=[null,...]"
    in the log. They don't stringify to anything meaningful, and raw Java
    object references don't belong in persisted save data anyway.]]
    local traitObjects = {}
    local traitNames = {}
    local ok, knownTraits = pcall(function() return player:getCharacterTraits():getKnownTraits() end)
    if ok and knownTraits then
        for i = 0, knownTraits:size() - 1 do
            local traitObj = knownTraits:get(i)
            table.insert(traitObjects, traitObj)
            local okName, name = pcall(function() return traitObj:getName() end)
            table.insert(traitNames, okName and name or "?")
        end
    end

    --[[ CharacterProfessionDefinition.getCharacterProfessionDefinition() wants
        the raw CharacterProfession-typed object, NOT a string. 
        Keep `profession` as the raw object for the actual lookup; store a separate
        stringified copy in ModData since that's what's safe/sensible to persist.]]
    local profession = nil
    local okProf, prof = pcall(function() return player:getDescriptor():getCharacterProfession() end)
    if okProf and prof then
        profession = prof
    end

    --[[ Which training mode applies: check the stringified trait names
    (already proven correct via :getName(), see above) against
    SkillDefs.TRAINING_TRAIT_IDS. "default" if none of the four training
    traits is present. Logged explicitly (not just inferred from the
    startLevel numbers) because the exact string :getName() returns for a
    JOST:-namespaced custom trait hasn't been confirmed live yet -- if
    detection is silently failing, this print is what will show it. ]]
    local trainingMode = "default"
    for modeKey, traitId in pairs(SkillDefs.TRAINING_TRAIT_IDS) do
        for _, name in ipairs(traitNames) do
            if name == traitId then
                trainingMode = modeKey
            end
        end
    end

    local snapshot = SkillCalc.computeSnapshot(traitObjects, profession, trainingMode)
    print("[JOST] initialized " .. tostring(player:getUsername()) ..
        " traits=[" .. table.concat(traitNames, ",") .. "] profession=" .. tostring(profession) ..
        " trainingMode=" .. trainingMode)
    for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
        print("[JOST]   " .. perk .. ": pips=" .. tostring(snapshot.pips[perk]) ..
            " startLevel=" .. tostring(snapshot.startLevels[perk]) .. " cap=" .. tostring(snapshot.caps[perk]))
    end

    data.traits = traitNames
    data.profession = profession and tostring(profession) or nil
    data.pips = snapshot.pips
    data.caps = snapshot.caps
    data.exempt = data.exempt or false
    data.capOverrides = data.capOverrides or {}
    data.initialized = true

    for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
        local startLevel = snapshot.startLevels[perk]
        if startLevel and startLevel > 0 then
            local perkType = Perks.FromString(perk)
            if perkType then
                local currentLevel = player:getPerkLevel(perkType)
                if currentLevel < startLevel then
                    setPerkLevel(player, perkType, startLevel)
                end
            end
        end
    end
end

--[[
    Effective cap for a skill on this player: the exempt flag beats
    everything (unlimited), then an admin cap override for this specific
    skill, then the computed snapshot cap.
]]
local function getEffectiveCap(player, perkName)
    local data = getModData(player)
    if data.exempt then return SkillDefs.VANILLA_MAX_LEVEL end
    if data.capOverrides and data.capOverrides[perkName] then
        return data.capOverrides[perkName]
    end
    if data.caps and data.caps[perkName] then
        return data.caps[perkName]
    end
    return SkillDefs.VANILLA_MAX_LEVEL
end

local TICK_INTERVAL = 30 -- ~1 second throttle
local tickCounter = 0
local jostLoggedFirstTick = false

--[[
    Cap clamps are never applied synchronously inside onLevelPerk. Forcing a
    level change (setPerkLevelDebug/setXPToLevel) from inside the LevelPerk
    event handler itself is a plausible re-entrancy risk: that forced change
    is itself a level change, which could re-fire Events.LevelPerk (calling
    back into this same handler while the engine is still mid-way through
    processing the original level-up, including the expensive
    getScriptManager():checkAutoLearn() recipe check) -- a same-tick chain
    reaction that's a reasonable suspect for a live crash observed when a
    skill crossed its cap.
]]
local pendingClamps = {}

local function processPendingClamps()
    if #pendingClamps == 0 then return end
    local queue = pendingClamps
    pendingClamps = {}
    for _, entry in ipairs(queue) do
        local player = entry.player
        if player and not player:isDead() then
            local perkType = Perks.FromString(entry.perkName)
            if perkType then
                local currentLevel = player:getPerkLevel(perkType)
                local cap = getEffectiveCap(player, entry.perkName)
                if currentLevel > cap then
                    setPerkLevel(player, perkType, cap)
                    local resultLevel = player:getPerkLevel(perkType)
                    if resultLevel ~= cap then
                        print("[JOST] WARNING: clamped " .. entry.perkName .. " to cap " .. tostring(cap) ..
                            " but getPerkLevel now reads " .. tostring(resultLevel) .. " -- setPerkLevel did not land exactly on the cap")
                    end
                end
            end
        end
    end
end

--[[
    Sweep every trade skill's CURRENT level against its cap for an already-
    initialized player, queuing a clamp for anything over. This is a safety
    net alongside onLevelPerk, not a replacement for it -- confirmed live
    that Foraging can reach a level with zero trace of Events.LevelPerk ever
    firing for it (no WARNING log, no onLevelPerk activity at all), while
    every other trade skill enforced correctly through the event. Foraging
    levels through the Search Mode system rather than standard crafting XP
    gain, which apparently doesn't reliably raise LevelPerk the same way.
    Catching it here means enforcement no longer depends on LevelPerk firing
    at all -- worst case it's caught within one checkAllPlayers sweep
    (~1 second) instead of instantly, same latency the queued clamp from
    onLevelPerk already has anyway.
]]
local function checkCapsForPlayer(player)
    local data = getModData(player)
    if not data.initialized then return end
    for _, perkName in ipairs(SkillDefs.TRADE_SKILLS) do
        local perkType = Perks.FromString(perkName)
        if perkType then
            local currentLevel = player:getPerkLevel(perkType)
            local cap = getEffectiveCap(player, perkName)
            if currentLevel > cap then
                table.insert(pendingClamps, { player = player, perkName = perkName })
            end
        end
    end
end

local function checkAllPlayers()
    if not SkillDefs.isEnabled() then return end
    local players = getOnlinePlayers()
    if not players then return end
    local count = isServer() and players:size() - 1 or getNumActivePlayers() - 1
    for i = 0, count do
        local player = isServer() and players:get(i) or getSpecificPlayer(i)
        if player and not player:isDead() then
            local data = getModData(player)
            if not data.initialized then
                initializeCharacter(player)
            else
                checkCapsForPlayer(player)
            end
        end
    end
end

local function onTick()
    if not jostLoggedFirstTick then
        jostLoggedFirstTick = true
        print("[JOST] onTick fired at least once, isServer()=" .. tostring(isServer()) .. " isClient()=" .. tostring(isClient()))
    end
    processPendingClamps() -- every tick (cheap when empty); keeps clamp latency low without clamping from inside LevelPerk

    tickCounter = tickCounter + 1
    if tickCounter < TICK_INTERVAL then return end
    tickCounter = 0
    checkAllPlayers()
end

local function onLevelPerk(owner, perk, level, addBuffer)
    if not owner or not perk then return end
    if not SkillDefs.isEnabled() then return end
    local perkName = tostring(perk:getType())
    if not SkillDefs.TRADE_SKILL_SET[perkName] then return end

    local data = getModData(owner)
    if not data.initialized then return end

    local cap = getEffectiveCap(owner, perkName)
    if level > cap then
        table.insert(pendingClamps, { player = owner, perkName = perkName })
    end
end

--[[
    Admin override command surface, reached via the standard client -> server
    RPC pattern (sendClientCommand / Events.OnClientCommand -- the same
    mechanism vanilla itself uses for e.g. server/ClientCommands.lua).
    Actions:
      ExemptPlayer  { target = username, exempt = true|false }
      SetCapOverride{ target = username, skill = perkName, cap = number }
]]
local function onClientCommand(module, command, player, args)
    if module ~= "JOST" then return end
    if not isAdmin(player) then return end

    local target = args and args.target and getPlayerFromUsername(args.target)
    if not target then return end

    if command == "ExemptPlayer" then
        local data = getModData(target)
        data.exempt = (args.exempt ~= false)
    elseif command == "SetCapOverride" then
        if not args.skill or not SkillDefs.TRADE_SKILL_SET[args.skill] or not args.cap then return end
        local data = getModData(target)
        data.capOverrides = data.capOverrides or {}
        data.capOverrides[args.skill] = args.cap
    end
end

Events.OnTick.Add(onTick)
Events.LevelPerk.Add(onLevelPerk)
Events.OnClientCommand.Add(onClientCommand)

SkillServer.isAdmin = isAdmin
SkillServer.getEffectiveCap = getEffectiveCap

return SkillServer
