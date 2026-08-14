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

    Under "default" training mode (no training trait picked -- the only
    mode an already-existing character can be in, since a training trait
    can only be chosen at character creation), starting levels only ever
    RAISE a skill, never lower it: if this mod is added to a server with
    already-playing characters, their genuinely earned progress is never
    reset down to the formula-derived start level.

    Under any explicitly-picked training mode (boosted/normal/half/none),
    the level is instead SET exactly, in either direction. Picking a
    training trait only ever happens on a brand-new life with nothing
    earned yet to protect, and Unfinished Education / Blank Slate
    specifically need to be able to pull a skill DOWN below whatever
    vanilla's own inherent starting bump from profession/trait pips already
    granted (confirmed live: picking a profession alone already starts a
    character above level 0 in its relevant skills, before this mod ever
    runs) -- otherwise "you don't start off with the skills" never actually
    holds for those two traits.
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

    --[[ Which training mode applies: use player:hasTrait() against the real
    registered CharacterTrait object, the same way vanilla itself always
    calls hasTrait() (e.g. client/BuildingObjects/TimedActions/
    ISBuildAction.lua:269 `character:hasTrait(CharacterTrait.HANDY)`,
    shared/Foraging/forageSystem.lua:1719 `_character:hasTrait(characterTrait)`
    where characterTrait comes from CharacterTrait.get(...)) -- always a real
    object, never a plain string. This replaces an earlier approach that
    compared traitObj:getName() strings against SkillDefs.TRAINING_TRAIT_IDS,
    which depended on assuming the exact string format :getName() returns
    for a custom JOST:-namespaced trait -- never actually confirmed live, so
    switched to the type-safe check instead of relying on that guess.
    JOST.traits (the bare-name-keyed table of registered CharacterTrait
    objects) is a global set by media/registries.lua, which runs before any
    Lua/script content loads, so it's guaranteed populated here.

    These traits do use MutuallyExclusiveTraits (see JOST_traits.txt) so the
    character-creation screen should already stop a player picking more than
    one. Checked here in a fixed, most-conservative-wins order ("none" >
    "half" > "normal" > "boosted") anyway -- cheap defense-in-depth against a
    multi-pick reaching this code some other way (e.g. debug/admin trait
    grants bypassing the creation screen), so it can never be gamed for a
    better outcome than the worst picked trait alone would give. ]]
    local MODE_PRIORITY = { "none", "half", "normal", "boosted" }
    local pickedModes = {}
    for modeKey, traitId in pairs(SkillDefs.TRAINING_TRAIT_IDS) do
        local bareName = traitId:match("^JOST:(.+)$")
        local traitObj = bareName and JOST and JOST.traits and JOST.traits[bareName]
        if traitObj then
            local okHas, has = pcall(function() return player:hasTrait(traitObj) end)
            if okHas and has then
                pickedModes[modeKey] = true
            end
        end
    end
    local trainingMode = "default"
    for _, modeKey in ipairs(MODE_PRIORITY) do
        if pickedModes[modeKey] then
            trainingMode = modeKey
            break
        end
    end
    local pickedCount = 0
    for _ in pairs(pickedModes) do pickedCount = pickedCount + 1 end
    if pickedCount > 1 then
        print("[JOST] WARNING: " .. tostring(player:getUsername()) ..
            " has more than one training trait picked -- falling back to the most conservative, trainingMode=" .. trainingMode)
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
        if startLevel ~= nil then
            local perkType = Perks.FromString(perk)
            if perkType then
                local currentLevel = player:getPerkLevel(perkType)
                if trainingMode == "default" then
                    if currentLevel < startLevel then
                        setPerkLevel(player, perkType, startLevel)
                    end
                elseif currentLevel ~= startLevel then
                    setPerkLevel(player, perkType, startLevel)
                end
            end
        end
    end
end

--[[
    Effective cap for a skill on this player: being an admin (when
    JOST.AdminCapExempt is on, the default) beats everything, then the
    exempt flag, then an admin cap override for this specific skill, then
    the computed snapshot cap.
]]
local function getEffectiveCap(player, perkName)
    if SkillDefs.isAdminCapExempt() and isAdmin(player) then return SkillDefs.VANILLA_MAX_LEVEL end
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
    event handler itself is a plausible re-entrancy risk
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
    initialized player, queuing a clamp for anything over. 
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
    Not implemented yet: Admin override command surface, reached via the standard client -> server
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
