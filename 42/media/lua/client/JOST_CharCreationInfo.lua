--[[
    Jack of Some Trades - character creation warning label.

    Draws "SKILL CAP MOD IN USE" in red directly below the
    "SELECT OCCUPATION AND TRAITS" title on CharacterCreationProfession.
    Function-hooked onto prerender() (wrap, call the original, then draw on
    top)
]]

local originalPrerender = CharacterCreationProfession.prerender

-- Matches CharacterCreationProfession.lua's own local UI_BORDER_SPACING (10)
-- that's a file-local there, not a global, so it isn't visible here.
local UI_BORDER_SPACING = 10

CharacterCreationProfession.prerender = function(self)
    originalPrerender(self)
    self:drawTextCentre("SKILL CAP MOD IN USE. SEE DISCORD FOR DETAILS", self.width / 2,
        UI_BORDER_SPACING + 1 + getTextManager():getFontHeight(UIFont.Large),
        1, 0, 0, 1, UIFont.Medium)
end