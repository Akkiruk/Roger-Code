-- games/stud/cards.lua
-- Cards narrow enough for seven in a row. ui.card is 13 wide and hides its suit when cards overlap, so stud draws its own.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

M.SEAT_W, M.SEAT_H = 10, 13     -- a seat's own hand
M.WIDE_W, M.WIDE_H = 7, 12      -- the wall, with room for seven in a row
M.TINY_W, M.TINY_H = 6, 7       -- the wall with up to eight boards

-- The computer's own suit characters, by deck.lua's suit
local GLYPHS = { [0] = "\5", [1] = "\4", [2] = "\3", [3] = "\6" }

--- A card as two or three letters for a line of text, such as K and a spade.
function M.label(card)
  return deck.rankName(card) .. GLYPHS[deck.suit(card)]
end

--- One card on a line of text, on its own white patch. Returns the width it took.
function M.chip(c, x, y, card)
  local text = M.label(card)
  c:text(x, y, text, deck.isRed(card) and C.red or C.ink, C.card)
  return #text
end

local function rankOn(c, x, y, card, w, color)
  local name = deck.rankName(card)
  if name == "10" and w < 10 then
    -- The font's 10 is 8 wide: a bar for the 1 fits it on the narrow cards
    c:rect(x, y, 1, 5, color)
    c:big(x + 2, y, "0", color, 1)
  else
    c:big(x + 1, y, name, color, 1)
  end
end

--- A card w by h, or its back when card is nil.
function M.draw(c, x, y, card, w, h)
  if card == nil then
    c:rect(x, y, w, h, C.card)
    c:rect(x + 1, y + 1, w - 2, h - 2, C.accent)
    return
  end
  c:rect(x, y, w, h, C.card)
  local color = deck.isRed(card) and C.red or C.ink
  rankOn(c, x, y + 1, card, w, color)
  if h >= M.WIDE_H then
    ui.suit(c, x + math.floor((w - ui.SUIT_W) / 2), y + h - ui.SUIT_H - 1, deck.suit(card), color, 1)
  else
    c:text(x + w - 2, y + h - 1, GLYPHS[deck.suit(card)], color, C.card)
  end
end

--- An empty place for a card.
function M.slot(c, x, y, w, h)
  c:frame(x, y, w, h, C.feltLight)
end

return M
