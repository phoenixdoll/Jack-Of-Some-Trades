--[[
    Jack of Some Trades - skill cap preview on the character creation
    "SELECT OCCUPATION AND TRAITS" screen.

    Replaces CharacterCreationProfession's "Major Skills" list (previously:
    only the trait/profession-boosted skills, each shown as N colored bars
    + a flat "+75/100/125%" label) with every JOST trade skill, each drawn
    as a full 10-square row:
      - squares 1..startLevel : green  -- the level you'll actually spawn
                                          with (SkillCalc.getStartLevel)
      - squares startLevel+1..cap : yellow -- reachable later through play
      - squares cap+1..10 : red -- unreachable, past the skill's cap
    with a tooltip per row explaining the same three numbers. Boosted
    skills (pips > 0) sort to the top; everything else (0 pips, capped at
    JOST.BaseCap0Pips) sorts below.

    checkXPBoost/drawXpBoostMap are plain functions on the class table
    (CharacterCreationProfession.lua itself assigns
    listboxXpBoost.doDrawItem = CharacterCreationProfession.drawXpBoostMap
    at listbox-creation time, which runs well after this file loads), so
    replacing them here at load time is enough -- no need to also hook the
    listbox-creation function itself. Inside drawXpBoostMap, `self` is the
    listbox instance, not the screen (ISScrollingListBox calls
    self:doDrawItem(...)), matching vanilla's own code and
    JOST_CharCreationInfo.lua's existing prerender hook style.
]]

local SkillDefs = require("JOST_SkillDefs")
local SkillCalc = require("JOST_SkillCalc")

-- Matches CharacterCreationProfession.lua's own local UI_BORDER_SPACING
-- (10) and FONT_HGT_SMALL -- file-locals there, not globals, so they
-- aren't visible here. Same workaround JOST_CharCreationInfo.lua uses.
local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local COLOR_YELLOW = { r = 1, g = 0.8, b = 0.1 }
local COLOR_RED = { r = 0.85, g = 0.15, b = 0.15 }

--[[
    Which of SkillDefs.TRAINING_TRAIT_IDS (if any) is currently selected on
    the trait-selection screen, by comparing each selected trait's
    CharacterTraitDefinition against the four JOST training traits'
    definitions (JOST.traits[bareName], the registered raw CharacterTrait
    objects, converted the same way JOST_SkillServer.lua's own trait
    checks do). Mirrors that file's "most conservative wins" priority
    order. Falls back to "default" on absolutely any failure, same as
    picking no training trait -- this is a preview only, never
    authoritative (JOST_SkillServer.lua decides for real at spawn).
]]
local function detectTrainingMode(screen)
    if not SkillDefs.isTrainingTraitsEnabled() then return "default" end
    if not (screen.listboxTraitSelected and screen.listboxTraitSelected.items) then return "default" end

    local MODE_PRIORITY = { "none", "half", "normal", "boosted" }
    local pickedModes = {}
    for _, v in pairs(screen.listboxTraitSelected.items) do
        local traitDef = v.item
        if traitDef then
            for modeKey, traitId in pairs(SkillDefs.TRAINING_TRAIT_IDS) do
                local bareName = traitId:match("^JOST:(.+)$")
                local rawTrait = bareName and JOST and JOST.traits and JOST.traits[bareName]
                if rawTrait then
                    local ok, rawDef = pcall(function() return CharacterTraitDefinition.getCharacterTraitDefinition(rawTrait) end)
                    if ok and rawDef == traitDef then
                        pickedModes[modeKey] = true
                    end
                end
            end
        end
    end
    for _, modeKey in ipairs(MODE_PRIORITY) do
        if pickedModes[modeKey] then return modeKey end
    end
    return "default"
end

--[[
    Boosted skills (pips > 0) first, highest pips first; 0-pip skills
    below, alphabetical.
]]
local function sortSkillRows(a, b)
    local aBoosted = a.item.pips > 0
    local bBoosted = b.item.pips > 0
    if aBoosted ~= bBoosted then return aBoosted end
    if a.item.pips ~= b.item.pips then return a.item.pips > b.item.pips end
    return a.text < b.text
end

function CharacterCreationProfession:checkXPBoost()
    self.listboxXpBoost:clear()

    -- Same XpBoosts-summing vanilla itself used here (see
    -- JOST_SkillCalc.computeAllPipsFromDefinitions's comment) -- kept
    -- as-is rather than re-deriving it through that function, since the
    -- character-creation screen's own selected-trait items are already
    -- CharacterTraitDefinition objects (not the raw CharacterTrait
    -- objects that function expects).
    local levels = {}
    if self.listboxTraitSelected and self.listboxTraitSelected.items then
        for _, v in pairs(self.listboxTraitSelected.items) do
            if v.item:getXpBoosts() then
                local boostTable = transformIntoKahluaTable(v.item:getXpBoosts())
                for perk, level in pairs(boostTable) do
                    levels[perk] = (levels[perk] or 0) + level:intValue()
                end
            end
        end
    end
    if self.profession and self.profession:getXpBoosts() then
        local boostTable = transformIntoKahluaTable(self.profession:getXpBoosts())
        for perk, level in pairs(boostTable) do
            levels[perk] = (levels[perk] or 0) + level:intValue()
        end
    end

    -- Convert the Perk-object-keyed totals above into a perkName-keyed
    -- pips table covering every JOST trade skill (0 for anything not
    -- boosted at all).
    local pipsByName = {}
    for _, perkName in ipairs(SkillDefs.TRADE_SKILLS) do
        pipsByName[perkName] = 0
    end
    for perkObj, pipsValue in pairs(levels) do
        local ok, perkName = pcall(function() return tostring(perkObj:getType()) end)
        if ok and perkName and pipsByName[perkName] ~= nil then
            if pipsValue < 0 then
                pipsValue = 0
            elseif pipsValue > SkillDefs.VANILLA_MAX_LEVEL then
                pipsValue = SkillDefs.VANILLA_MAX_LEVEL
            end
            pipsByName[perkName] = pipsValue
        end
    end

    local trainingMode = detectTrainingMode(self)

    for _, perkName in ipairs(SkillDefs.TRADE_SKILLS) do
        local perkType = Perks.FromString(perkName)
        if perkType then
            local pips = pipsByName[perkName]
            local startLevel = SkillCalc.getStartLevel(pips, trainingMode)
            local cap = SkillCalc.computeEffectiveCap(perkName, pipsByName)
            local displayName = PerkFactory.getPerkName(perkType)

            local tooltip = "STARTING LEVEL: " .. startLevel ..
                " <LINE> CAN TRAIN TO " .. cap .. " IN " .. displayName

            self.listboxXpBoost:addItem(
                displayName,
                { pips = pips, startLevel = startLevel, cap = cap },
                tooltip
            )
        end
    end

    self.listboxXpBoost:sort(sortSkillRows)
end

function CharacterCreationProfession:drawXpBoostMap(y, item, alt)
    local dy = (self.itemheight - self.fontHgt) / 2
    local hc = getCore():getGoodHighlitedColor()
    local scrollBarWidth = 13
    self:drawText(item.text, UI_BORDER_SPACING, y + dy, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)

    local blitH = FONT_HGT_SMALL
    local blitW = math.floor(blitH / (10 / 3))
    local blitGap = math.floor(blitW / 4)
    local greenBlitsX = self.width - (scrollBarWidth + 11 * (blitW + blitGap))
    local yy = y

    local startLevel = item.item.startLevel
    local cap = item.item.cap
    for i = 1, SkillDefs.VANILLA_MAX_LEVEL do
        local r, g, b
        if i <= startLevel then
            r, g, b = hc:getR(), hc:getG(), hc:getB()
        elseif i <= cap then
            r, g, b = COLOR_YELLOW.r, COLOR_YELLOW.g, COLOR_YELLOW.b
        else
            r, g, b = COLOR_RED.r, COLOR_RED.g, COLOR_RED.b
        end
        self:drawTextureScaled(CharacterCreationProfession.instance.whiteBar,
            greenBlitsX + (i * (blitW + blitGap)), yy + dy, blitW, blitH, 1, r, g, b)
    end

    yy = yy + self.itemheight

    self:drawRectBorder(0, y, self:getWidth(), yy - y, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    return yy
end
