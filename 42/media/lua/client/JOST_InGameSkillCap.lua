--[[
    Jack of Some Trades - draws the skill cap on the in-game skills panel.

    Squares from the player's effective cap through level 10 render red
    instead of vanilla's plain dark-grey "not available", with a tooltip
    explaining why when one of those squares is hovered. Display only --
    SkillCalc.getStoredEffectiveCap reads the player's own already-synced
    ModData, it never enforces anything (that stays JOST_SkillServer.lua's
    job).

    Wraps ISSkillProgressBar.renderPerkRect/updateTooltip (client/XpSystem/
    ISUI/ISSkillProgressBar.lua) the same way JOST_CharCreationInfo.lua
    wraps CharacterCreationProfession.prerender: save the original, call
    it, then draw/append on top.
]]

local SkillDefs = require("JOST_SkillDefs")
local SkillCalc = require("JOST_SkillCalc")

-- Matches ISSkillProgressBar.lua's own file-local geometry exactly (that's
-- a file-local there, not a global, so it isn't visible here).
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local SKILL_POINT_HGT = math.floor((FONT_HGT_SMALL + 6) / 2)
local SKILL_POINT_SPACING = getCore():getOptionFontSizeReal()

local CAP_R, CAP_G, CAP_B = 0.85, 0.15, 0.15

local originalRenderPerkRect = ISSkillProgressBar.renderPerkRect
ISSkillProgressBar.renderPerkRect = function(self)
    originalRenderPerkRect(self)

    if not SkillDefs.isEnabled() then return end
    local perkName = tostring(self.perk:getType())
    if not SkillDefs.TRADE_SKILL_SET[perkName] then return end

    local cap = SkillCalc.getStoredEffectiveCap(self.char, perkName)
    if cap >= SkillDefs.VANILLA_MAX_LEVEL then return end
    if cap < 0 then cap = 0 end

    -- Square index k (0-based) sits at x = k*(SKILL_POINT_HGT+SKILL_POINT_SPACING)
    -- and represents level k+1 -- same layout renderPerkRect's own three
    -- loops already use. The first unreachable square is level cap+1, i.e.
    -- k = cap.
    local x = cap * (SKILL_POINT_HGT + SKILL_POINT_SPACING)
    for i = cap, 9 do
        self:drawTextureScaled(self.SkillUnitFilled, x, 0, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, CAP_R, CAP_G, CAP_B)
        self:drawTextureScaled(self.SkillUnitBorder, x, 0, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, CAP_R, CAP_G, CAP_B)
        x = x + SKILL_POINT_HGT + SKILL_POINT_SPACING
    end
end

local originalUpdateTooltip = ISSkillProgressBar.updateTooltip
ISSkillProgressBar.updateTooltip = function(self, lvlSelected)
    originalUpdateTooltip(self, lvlSelected)

    if not SkillDefs.isEnabled() then return end
    local perkName = tostring(self.perk:getType())
    if not SkillDefs.TRADE_SKILL_SET[perkName] then return end

    local cap = SkillCalc.getStoredEffectiveCap(self.char, perkName)
    if cap < SkillDefs.VANILLA_MAX_LEVEL and lvlSelected >= cap then
        self.message = self.message .. " <LINE> SKILL CAP (" .. tostring(cap) .. ")"
    end
end
