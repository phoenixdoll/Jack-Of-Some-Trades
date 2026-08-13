--[[
    Jack of Some Trades - custom CharacterTrait registration.

    Required before media/scripts/JOST_traits.txt's character_trait_definition
    blocks can reference these IDs -- confirmed via the PZ wiki
    ("Creating a trait mod") and the real published SomewhatTraitsSkills mod's
    own media/registries.lua: a custom CharacterTrait must be registered here
    first, or CharacterTraitDefinition's constructor throws a
    NullPointerException (characterTraitType null) for every trait in the
    file, which is a fatal script-load error that crashes the game at boot.
]]

JOST = JOST or {}
JOST.traits = JOST.traits or {}

local traits = {
    "BoostedTraining",
    "NormalTraining",
    "HalfTraining",
    "NoTraining",
}
for i = 1, #traits do
    local trait = traits[i]
    JOST.traits[trait] = CharacterTrait.register("JOST:" .. trait)
end