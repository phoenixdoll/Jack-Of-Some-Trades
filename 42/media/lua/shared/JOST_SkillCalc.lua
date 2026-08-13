--[[
    Jack of Some Trades - pure pip/cap/start-level calculations.

    No side effects, no player mutation -- everything here just takes
    trait/profession data in and returns numbers out, so it's easy to test
    and reuse from both the server enforcement code and (later) any client
    UI that wants to display a character's caps.
]]

local SkillDefs = require("JOST_SkillDefs")

local SkillCalc = {}

--[[
    A Java HashMap<PerkFactory.Perk, Integer> (what both
    CharacterTraitDefinition/CharacterProfessionDefinition:getXpBoosts()
    and, per the engine's Javadocs, Xp:getXpBoosts()/getXPBoostMap() return)
    comes back from transformIntoKahluaTable keyed by Perk-typed objects,
    NOT plain strings -- confirmed via shared/NPCs/MainCreationMethods.lua:
    `PerkFactory.getPerkName(perk)` is called directly on the loop key,
    which only makes sense if `perk` is a Perk object. Convert each key to
    the plain skill-name string (e.g. "Woodwork") via :getType(), the same
    conversion already proven correct elsewhere (server/JOST_SkillServer.lua,
    vanilla's shared/Logs/ISPerkLog.lua:14).

    Adds every entry in `xpBoosts` into `totals` (a { [perkName] = number }
    table, mutated in place). Skills outside SkillDefs.TRADE_SKILL_SET are
    ignored.
]]
local function addBoostsInto(totals, xpBoosts)
    if not xpBoosts then return end
    local boostTable = transformIntoKahluaTable(xpBoosts)
    for perkKey, value in pairs(boostTable) do
        local ok, perkName = pcall(function() return tostring(perkKey:getType()) end)
        if ok and perkName and totals[perkName] ~= nil then
            totals[perkName] = totals[perkName] + value:intValue()
        end
    end
end

local function clamp(totals)
    for perk, value in pairs(totals) do
        if value < 0 then
            totals[perk] = 0
        elseif value > SkillDefs.VANILLA_MAX_LEVEL then
            totals[perk] = SkillDefs.VANILLA_MAX_LEVEL
        end
    end
    return totals
end

local function zeroedTotals()
    local totals = {}
    for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
        totals[perk] = 0
    end
    return totals
end

--[[
    NOTE: player:getXp():getXpBoosts()/getXPBoostMap() (documented in the
    engine's Javadocs on the Xp class) turned out NOT to be safely callable
    from Lua -- confirmed live: calling it throws a java.lang.RuntimeException
    from inside Kahlua's OWN pcall implementation (KahluaUtil.fail), meaning
    even a pcall wrapper around the call doesn't catch it, and it escapes to
    crash whatever called in. Removed entirely; SkillCalc only ever uses
    computeAllPipsFromDefinitions below. Confirmed as a hard "don't do this",
    not just "unverified" -- see the getPerkBoost/getXpBoosts investigation
    in project history for why this was worth trying in the first place
    (mainly: automatic compatibility with modded traits).
]]

--[[
    Fallback: sums a profession's + a list of traits' declared XPBoosts for
    every trade skill -- exactly how vanilla computes "pips" for the
    character-creation screen (CharacterCreationProfession:checkXPBoost,
    client/OptionScreens/CharacterCreationProfession.lua:405-431), just
    without the UI parts. Used when computeAllPipsFromLiveXp can't get a
    live-computed map.

    traitObjects: array of the RAW CharacterTrait-typed objects (e.g.
    straight from playerObj:getCharacterTraits():getKnownTraits(), each
    element passed through as-is) -- NOT name strings.
    CharacterTraitDefinition.getCharacterTraitDefinition() wants the raw
    object, same requirement as the profession lookup below (confirmed by
    how vanilla itself calls it, never converting first).
    profession: the RAW CharacterProfession-typed object (e.g. straight from
    playerObj:getDescriptor():getCharacterProfession()), or nil for none --
    NOT a string. CharacterProfessionDefinition.getCharacterProfessionDefinition()
    throws "expected argument of type CharacterProfession, got String" if
    handed a stringified version (confirmed live), so this must stay the
    original typed object.

    Returns a table: { [perkName] = pips, ... } covering every skill in
    SkillDefs.TRADE_SKILLS.
]]
function SkillCalc.computeAllPipsFromDefinitions(traitObjects, profession)
    local totals = zeroedTotals()

    if profession then
        local professionDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(profession)
        if professionDef then
            addBoostsInto(totals, professionDef:getXpBoosts())
        end
    end

    if traitObjects then
        for _, traitObj in ipairs(traitObjects) do
            local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitObj)
            if traitDef then
                addBoostsInto(totals, traitDef:getXpBoosts())
            end
        end
    end

    return clamp(totals)
end

-- Pips -> one-time starting level granted at spawn. `mode` selects which
-- of JOST's training-trait tables applies -- see SkillDefs.getStartLevel.
function SkillCalc.getStartLevel(pips, mode)
    return SkillDefs.getStartLevel(pips, mode)
end

-- Pips -> base cap, before any linked-skill synergy bonus. Sandbox-
-- overridable, see SkillDefs.getBaseCap.
function SkillCalc.computeBaseCap(pips)
    return SkillDefs.getBaseCap(pips)
end

--[[
    Effective cap for `perk`: base cap (from its own pips) plus a flat +1
    for every skill directly linked to it (SkillDefs.LINKS) that has >=1
    pip, clamped to the vanilla max. `allPips` is the table returned by
    computeAllPips. Skips the linked-skill bonus entirely when the
    JOST.SynergyEnabled sandbox option is off.
]]
function SkillCalc.computeEffectiveCap(perk, allPips)
    local cap = SkillCalc.computeBaseCap(allPips[perk] or 0)

    if SkillDefs.isSynergyEnabled() then
        local links = SkillDefs.LINKS[perk]
        if links then
            for _, linkedPerk in ipairs(links) do
                if (allPips[linkedPerk] or 0) >= 1 then
                    cap = cap + 1
                end
            end
        end
    end

    if cap > SkillDefs.VANILLA_MAX_LEVEL then
        cap = SkillDefs.VANILLA_MAX_LEVEL
    end
    return cap
end

--[[
    One-shot convenience: computes pips, start levels, and effective caps
    for every trade skill for a character, from their traits/profession
    (SkillCalc.computeAllPipsFromDefinitions).

    traitObjects: raw CharacterTrait objects, e.g. from
    player:getCharacterTraits():getKnownTraits() -- not name strings.
    profession: the raw CharacterProfession object, e.g. straight from
    player:getDescriptor():getCharacterProfession() -- not a string.
    trainingMode: which pips->starting-level table applies (see
    SkillDefs.getStartLevel) -- "default" if omitted. Never affects caps.

    Returns { pips = {...}, startLevels = {...}, caps = {...} }.
]]
function SkillCalc.computeSnapshot(traitObjects, profession, trainingMode)
    local pips = SkillCalc.computeAllPipsFromDefinitions(traitObjects, profession)

    local startLevels = {}
    local caps = {}
    for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
        startLevels[perk] = SkillCalc.getStartLevel(pips[perk], trainingMode)
        caps[perk] = SkillCalc.computeEffectiveCap(perk, pips)
    end
    return { pips = pips, startLevels = startLevels, caps = caps }
end

return SkillCalc
