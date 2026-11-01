-- games/blackjack/seatView.lua
-- A player's own screen: the dealer on the left, their hand on the right, one hand or the two of a split, and whose turn it is below.
-- Everyone's hands are on the dealer's wall, so a seat keeps to what this player has to decide on. Cards and totals end at row 28, above
-- the result banner.

local look = require("games.blackjack.look")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local LABEL_Y = 10
local CARD_Y = 11
local TOTAL_Y = 24
local TURN_Y = 31
local LEGEND_Y = 38
local DEALER_X, DEALER_W = 2, 28
local HAND_X, HAND_W = 31, 46
local SPLIT_DEALER_W = 20
local SPLIT_X, SPLIT_W = 23, 27         -- two hands of this width, side by side
local SPLIT_GAP = 1

local function drawDealer(c, view, anim, x, w)
  local cards, total = look.dealerNow(view, anim)
  local cx = x + math.floor(w / 2)
  c:textCenter(cx, LABEL_Y, "DEALER", C.text)
  look.row(c, cx, CARD_Y, w, cards, false)
  if total then c:bigCenter(cx, TOTAL_Y, tostring(total), look.totalColor(total), 1) end
end

--- One hand: its label, its cards, its total, and its word.
local function drawHand(c, x, w, label, hand, cards, playing, judged)
  local cx = x + math.floor(w / 2)
  c:text(x + 1, LABEL_Y, label, playing and C.gold or C.text)
  local word, color
  if judged then word, color = look.outcome(hand) else word, color = look.tag(hand) end
  if word then c:text(x + w - #word, LABEL_Y, word, color) end
  look.row(c, cx, CARD_Y, w - 1, cards, false)
  if #cards == #hand.cards then c:bigCenter(cx, TOTAL_Y, tostring(hand.total), look.totalColor(hand.total), 1) end
end

local function find(view)
  for position, seat in ipairs(view.seats) do
    if seat.seat == view.me then return seat, position end
  end
  return nil
end

local function drawTurn(c, view, cx, mine)
  if view.turn and mine and view.turn == mine.seat then
    local words = #mine.hands > 1 and ("HAND " .. view.turnHand) or "YOUR TURN"
    c:bigCenter(cx, TURN_Y, words, C.gold, 1)
  elseif view.turn then
    c:textCenter(cx, TURN_Y + 2, "Waiting for " .. seatui.short(view.turnName, 20), C.text)
  elseif view.phase == "dealer" then
    c:textCenter(cx, TURN_Y + 2, "The dealer plays", C.text)
  end
end

function M.draw(c, view, anim)
  if type(view) ~= "table" or type(view.seats) ~= "table" then return end
  local cx = math.floor(c.w / 2) + 1
  local mine, position = find(view)
  local judged = look.judged(view, anim)

  if mine and #mine.hands > 1 then
    drawDealer(c, view, anim, DEALER_X, SPLIT_DEALER_W)
    for number, hand in ipairs(mine.hands) do
      local playing = view.turn == mine.seat and view.turnHand == number
      drawHand(c, SPLIT_X + (number - 1) * (SPLIT_W + SPLIT_GAP), SPLIT_W, "HAND " .. number, hand, hand.cards, playing, judged)
    end
  else
    drawDealer(c, view, anim, DEALER_X, DEALER_W)
    if mine then
      local hand = mine.hands[1]
      local cards = look.handNow(view, position, hand.cards, anim)
      drawHand(c, HAND_X, HAND_W, "YOU  Bet " .. ui.group(hand.bet), hand, cards, view.turn == mine.seat, judged)
    else
      c:textCenter(HAND_X + math.floor(HAND_W / 2), CARD_Y + 4, "You are not in this round", C.text)
    end
  end

  drawTurn(c, view, cx, mine)
  c:textCenter(cx, LEGEND_Y, "Blackjack pays 3 to 2. Dealer hits soft 17.", C.text)
end

return M
