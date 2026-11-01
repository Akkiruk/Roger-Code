-- games/draw/cards.lua
-- What both pictures of the game share: the names of the phases, and a hand of small cards fanned to fit.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local RANK_STEP = 7        -- a narrower strip of a card cannot show a big rank
local SUIT_CHARS = { [0] = 5, [1] = 4, [2] = 3, [3] = 6 } -- clubs, diamonds, hearts, spades

M.PHASES = {
  bet1 = "FIRST BETTING ROUND",
  draw = "THE DRAW",
  bet2 = "FINAL BETTING ROUND",
  over = "SHOWDOWN",
}

--- A shown hand, fanned. Strips of a fan lose the corner pip, so the suit moves under the rank, in the monitor font's own suit
-- characters, and a strip too thin for the big rank has the rank in those characters too. As on the Poker Table wall.
function M.fan(c, cx, y, hand, maxW)
  local xs = ui.fan(cx, #hand, ui.SMALL_W, maxW, 1)
  for i, card in ipairs(hand) do
    ui.card(c, xs[i], y, card, true)
    local step = xs[i + 1] and xs[i + 1] - xs[i] or ui.SMALL_W
    if step < ui.SMALL_W then
      local color = deck.isRed(card) and C.red or C.ink
      local tight = step < RANK_STEP or c:bigWidth(deck.rankName(card), 1) >= step
      c:rect(xs[i] + 1, y + (tight and 1 or 6), step - 1, tight and 10 or 5, C.card)
      c:rect(xs[i] + step - 1, y + 1, 1, ui.SMALL_H - 2, C.mute)
      if tight then c:text(xs[i] + 1, y + 3, deck.rankName(card):sub(1, step - 2), color, C.card) end
      c:text(xs[i] + 1, y + (tight and 6 or 8), string.char(SUIT_CHARS[deck.suit(card)]), color, C.card)
    end
  end
end

--- A name that fits in a small space.
function M.short(name, room)
  name = tostring(name)
  if #name <= room then return name end
  return name:sub(1, room - 1) .. "."
end

--- What a player did last, for a seat's line.
function M.status(player)
  if player.folded then return "folded" end
  if player.allin then return "ALL-IN " .. player.total end
  if player.last then return player.last .. (player.bet > 0 and (" " .. player.bet) or "") end
  if player.bet > 0 then return "in for " .. player.bet end
  return nil
end

--- Whose turn it is, in words. nil when it is nobody's.
function M.turnLine(view, room)
  if not view.actor then return nil end
  local name = M.short(view.actor, room or 14)
  if view.phase == "draw" then return name .. " to draw" end
  if (view.toCall or 0) > 0 then return name .. " to call " .. view.toCall end
  return name .. " to act"
end

return M
