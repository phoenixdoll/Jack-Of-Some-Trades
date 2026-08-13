--[[
    Jack of Some Trades - skill/tier/link data.

    Everything here is plain data so it can be retuned without touching the
    calc/server logic. Perk names below are the real B42 Perks.* identifiers
    (verified against the installed game's media/lua and media/scripts),
    which differ from their in-game display names in several cases (e.g.
    Perks.Woodwork displays as "Carpentry", Perks.Doctor as "First Aid",
    Perks.PlantScavenging as "Foraging" -- this last one bit us live: it was
    originally listed here as "Foraging", which isn't a real Perks.* member,
    so Perks.FromString("Foraging") silently returned nil and the skill went
    completely unenforced with zero errors anywhere. Any future skill added
    here should be double-checked against actual Perks.* usage in the
    installed game source, not assumed from its in-game display name.).
]]

local SkillDefs = {}

-- Trade/crafting skills this mod caps and boosts. Combat/physical skills
-- (Strength, Fitness, Sprinting, Lightfooted, Nimble, Sneaking, Aiming,
-- Reloading, Guard, and all melee weapon perks) are deliberately absent --
-- those train from raw practice, not backstory.
SkillDefs.TRADE_SKILLS = {
    -- Farming
    "Farming",      -- Agriculture
    "Husbandry",    -- Animal Care
    "Butchering",
    -- Crafting
    "Woodwork",     -- Carpentry
    "Blacksmith",   -- Blacksmithing
    "Carving",
    "Cooking",
    "Electricity",  -- Electrical
    "Glassmaking",
    "FlintKnapping",-- Knapping
    "Masonry",
    "Pottery",
    "Tailoring",
    "MetalWelding", -- Welding
    "Mechanics",
    "Maintenance",
    -- Survival
    "Doctor",       -- First Aid
    "Fishing",
    "PlantScavenging", -- Foraging (confirmed via server/XpSystem/XPSystem_SkillBook.lua:84,
                       -- SkillBook["Foraging"].perk = Perks.PlantScavenging -- "Foraging" is
                       -- display-only, Perks.Foraging isn't a real perk and FromString("Foraging")
                       -- silently returned nil, which is why this skill went completely unenforced)
    "Tracking",
    "Trapping",
}

-- Fast lookup: SkillDefs.TRADE_SKILL_SET[perkName] == true for capped skills.
SkillDefs.TRADE_SKILL_SET = {}
for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
    SkillDefs.TRADE_SKILL_SET[perk] = true
end

SkillDefs.VANILLA_MAX_LEVEL = 10

--[[
    Sandbox-overridable numbers. Read live every call (not cached at load
    time) -- MP's sandbox sync can complete after this file's require(),
    same lesson TAZC_Config already learned the hard way, see its
    getSandboxVar/liveSandbox comments.
]]
local function getSandboxVar(name, default)
    if SandboxVars and SandboxVars.JOST then
        local val = SandboxVars.JOST[name]
        if val ~= nil then return val end
    end
    return default
end
SkillDefs.getSandboxVar = getSandboxVar

function SkillDefs.isEnabled()
    return getSandboxVar("Enabled", true)
end

function SkillDefs.isSynergyEnabled()
    return getSandboxVar("SynergyEnabled", true)
end

-- When on (default), players with Admin access level are exempt from all
-- skill caps automatically -- no manual admin command needed. Starting
-- levels are unaffected; only cap enforcement is skipped for them.
function SkillDefs.isAdminCapExempt()
    return getSandboxVar("AdminCapExempt", true)
end

--[[
    Which of several pips->starting-level tables applies is a per-character
    choice via one of the four JOST:*Training traits below (module JOST) --
    picking none gives the DEFAULT table, which is deliberately weaker than
    the old single fixed table (now the "boosted" mode, gated behind a
    2-cost trait instead of being free for everyone). The skill CAP is
    ALWAYS computed from actual pips regardless of which mode applies --
    these traits only ever affect the one-time starting-level grant, never
    the cap. See JOST_traits.txt for the trait definitions themselves.
]]
SkillDefs.TRAINING_TRAIT_IDS = {
    boosted = "JOST:BoostedTraining", -- 2-cost positive trait
    normal = "JOST:NormalTraining",   -- +2 negative trait
    half = "JOST:HalfTraining",       -- +6 negative trait
    none = "JOST:NoTraining",         -- +10 negative trait
}

-- Pips -> starting level, granted once at spawn for a genuinely new
-- character. `mode` is one of "default" (no training trait picked),
-- "boosted", "normal", "half", "none" -- see TRAINING_TRAIT_IDS above.
function SkillDefs.getStartLevel(pips, mode)
    mode = mode or "default"

    if mode == "none" then
        return 0
    end

    if mode == "half" then
        -- Half of the "normal" (no-bonus) level, rounded down. "Normal" is
        -- just the pip count itself, so this is floor(pips / 2).
        return math.floor(pips / 2)
    end

    if mode == "normal" then
        -- No bonus at all: starting level literally equals the pip count,
        -- uncapped (pips are already clamped 0-10 upstream).
        return pips
    end

    if mode == "boosted" then
        if pips >= 4 then return getSandboxVar("StartLevel4PlusPips", 9) end
        local byPips = {
            [0] = getSandboxVar("StartLevel0Pips", 0),
            [1] = getSandboxVar("StartLevel1Pip", 3),
            [2] = getSandboxVar("StartLevel2Pips", 5),
            [3] = getSandboxVar("StartLevel3Pips", 7),
        }
        return byPips[pips] or 0
    end

    -- "default": nobody picked a training trait. Weaker than "boosted".
    if pips >= 4 then return getSandboxVar("StartLevelDefault4PlusPips", 7) end
    local byPips = {
        [0] = getSandboxVar("StartLevelDefault0Pips", 0),
        [1] = getSandboxVar("StartLevelDefault1Pip", 2),
        [2] = getSandboxVar("StartLevelDefault2Pips", 4),
        [3] = getSandboxVar("StartLevelDefault3Pips", 6),
    }
    return byPips[pips] or 0
end

-- Pips -> base cap, before any linked-skill synergy bonus.
function SkillDefs.getBaseCap(pips)
    if pips >= 4 then return getSandboxVar("BaseCap4PlusPips", 10) end
    local byPips = {
        [0] = getSandboxVar("BaseCap0Pips", 3),
        [1] = getSandboxVar("BaseCap1Pip", 5),
        [2] = getSandboxVar("BaseCap2Pips", 7),
        [3] = getSandboxVar("BaseCap3Pips", 9),
    }
    return byPips[pips] or byPips[0]
end

-- Linked-skill synergy graph: each pair listed once, both directions apply.
-- A linked skill with >=1 pip grants this skill a flat +1 to its cap.
SkillDefs.LINKED_PAIRS = {
    { "MetalWelding", "Blacksmith" },
    { "Blacksmith", "Glassmaking" },
    { "Masonry", "Pottery" },
    { "Tailoring", "Blacksmith" },
    { "Tailoring", "Carving" },
    { "Woodwork", "Carving" },
    { "Electricity", "Mechanics" },
    { "Cooking", "Butchering" },
    { "Doctor", "Tailoring" },
    { "Butchering", "Fishing" },
    { "PlantScavenging", "Tracking" },
    { "Trapping", "PlantScavenging" },
    { "Trapping", "Tracking" },
    { "Farming", "Husbandry" },
    { "Butchering", "Husbandry" },
    { "Cooking", "Doctor" },
    { "Cooking", "Fishing" },
    { "PlantScavenging", "Farming" },
    { "FlintKnapping", "Carving" },
    { "FlintKnapping", "Trapping" },
    { "Masonry", "Woodwork" },
    { "Glassmaking", "Pottery" },
    { "Mechanics", "MetalWelding" },
    { "Electricity", "Woodwork" },
    { "Electricity", "MetalWelding" },
    { "FlintKnapping", "Masonry" },
    { "Mechanics", "Farming" },
    { "Doctor", "Husbandry" },
    { "Fishing", "Tracking" },
    { "Glassmaking", "Farming" },
    { "Pottery", "Husbandry" },
    { "Maintenance", "Woodwork" },
    { "Maintenance", "MetalWelding" },
    { "Maintenance", "Blacksmith" },
    { "Maintenance", "Tailoring" },
    { "Maintenance", "Carving" },
}

-- Built from LINKED_PAIRS at load time: SkillDefs.LINKS[perkName] is an
-- array of the perk names directly linked to it (both directions of every
-- pair above).
SkillDefs.LINKS = {}
for _, perk in ipairs(SkillDefs.TRADE_SKILLS) do
    SkillDefs.LINKS[perk] = {}
end
for _, pair in ipairs(SkillDefs.LINKED_PAIRS) do
    local a, b = pair[1], pair[2]
    table.insert(SkillDefs.LINKS[a], b)
    table.insert(SkillDefs.LINKS[b], a)
end

return SkillDefs
