--[[
    Jack of Some Trades - hides the four training traits from character
    creation entirely when JOST.TrainingTraitsEnabled is off, instead of
    leaving them selectable-but-inert.

    Wraps CharacterCreationProfession:isTraitEnabled, the one existing
    filter vanilla itself already calls from both populateTraitList
    (positive-cost traits) and populateBadTraitList (negative-cost traits)
    before adding a trait to either listbox, so filtering here removes
    JOST's traits from both lists at once without touching either
    population function directly.

    `trait` here is a CharacterTraitDefinition, not the raw CharacterTrait
    objects JOST.traits holds (same distinction JOST_CharCreationSkillCaps.
    lua's detectTrainingMode already deals with), so each raw trait is
    converted once via CharacterTraitDefinition.getCharacterTraitDefinition
    at load time and cached in a lookup set.
]]

local SkillDefs = require("JOST_SkillDefs")

local JOST_TRAIT_DEFS = {}
for _, traitId in pairs(SkillDefs.TRAINING_TRAIT_IDS) do
    local bareName = traitId:match("^JOST:(.+)$")
    local rawTrait = bareName and JOST and JOST.traits and JOST.traits[bareName]
    if rawTrait then
        local ok, traitDef = pcall(function() return CharacterTraitDefinition.getCharacterTraitDefinition(rawTrait) end)
        if ok and traitDef then
            JOST_TRAIT_DEFS[traitDef] = true
        end
    end
end

local originalIsTraitEnabled = CharacterCreationProfession.isTraitEnabled
CharacterCreationProfession.isTraitEnabled = function(self, trait)
    if not originalIsTraitEnabled(self, trait) then return false end
    if JOST_TRAIT_DEFS[trait] and not SkillDefs.isTrainingTraitsEnabled() then
        return false
    end
    return true
end
