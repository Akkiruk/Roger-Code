-- games/blackjack/look.lua
-- What the wall and the seats draw alike: a row of cards at whatever size fits, and how much of the view an event still holds back.
-- Pure functions of the view. Nothing here reads the state.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local READ_STEP = 6           -- a fan closer than this hides the rank of the card under it
local MINI_W, MINI_H = 5, 3   -- a card as a line of text, for when a fan cannot be read
local MINI_STEP = 6
local SUIT_MARK = { [0] = "\5", [1] = "\4", [2] = "\3", [3] = "\6" }  -- clubs, diamonds, hearts, spades, in deck.suit's order

M.MINI_H = MINI_H

local function mini(c, x, y, card)
  if card then
    local ink = deck.isRed(card) and C.red or C.ink
    c:rect(x, y, MINI_W, MINI_H, C.card)
    c:text(x + 1, y + 1, deck.rankName(card) .. SUIT_MARK[deck.suit(card)], ink, C.card)
  else
    c:rect(x, y, MINI_W, MINI_H, C.accent)
  end
end

--- A row of the smallest cards, overlapping only when it must.
function M.miniRow(c, cx, y, maxW, cards)
  local count = #cards
  if count == 0 then return end
  local step = MINI_STEP
  if count > 1 and step * (count - 1) + MINI_W > maxW then step = math.floor((maxW - MINI_W) / (count - 1)) end
  local x = cx - math.floor((step * (count - 1) + MINI_W) / 2)
  for index = 1, count do mini(c, x + (index - 1) * step, y, cards[index]) end
end

local function fanStep(count, cardW, maxW)
  if count < 2 then return cardW end
  return math.floor((maxW - cardW) / (count - 1))
end

--- A hand centred on cx, at the size that can still be read: full, small, then minis. false in the list is a card face down.
-- big lets it use full-size cards.
function M.row(c, cx, y, maxW, cards, big)
  local count = #cards
  if count == 0 then return end
  local small = not big or fanStep(count, ui.CARD_W, maxW) < READ_STEP
  local w, h = small and ui.SMALL_W or ui.CARD_W, small and ui.SMALL_H or ui.CARD_H
  if fanStep(count, w, maxW) < READ_STEP then
    M.miniRow(c, cx, y + math.floor((h - MINI_H) / 2), maxW, cards)
    return
  end
  local xs = ui.fan(cx, count, w, maxW, 1)
  for index = 1, count do
    ui.card(c, xs[index], y, cards[index] or nil, small)
    -- White on white runs together when a fan overlaps, so each card gets an edge
    if index > 1 and xs[index] - xs[index - 1] < w then c:rect(xs[index], y + 1, 1, h - 2, C.mute) end
  end
end

--- A deal event holds back the cards that have not landed yet. Returns how many of the deal's cards are down, or nil for all of them.
local function dealt(anim)
  if anim and anim.ev.step then return anim.ev.step end
  return nil
end

--- The dealer's cards as they stand during this event, false for the hole card, and their total, or nil with no card up.
function M.dealerNow(view, anim)
  local up = #view.dealer
  local cards = {}
  local showing = up
  if anim and anim.ev.shown then
    showing = math.min(anim.ev.shown, up)
    if anim.ev.type == "reveal" and anim.t < 0.5 then showing = 1 end
  end
  for index = 1, showing do cards[index] = view.dealer[index] end
  if view.down or (anim and anim.ev.type == "reveal" and anim.t < 0.5) then cards[#cards + 1] = false end
  local total = view.runs[showing]

  local step = dealt(anim)
  if step then
    local seats = #view.seats + 1
    local landed = math.floor(step / seats)
    for index = #cards, landed + 1, -1 do cards[index] = nil end
    if landed < 1 then total = nil end
  end
  return cards, total
end

--- A seat's first cards as they stand during the deal. position is where the seat is in view.seats.
function M.handNow(view, position, cards, anim)
  local step = dealt(anim)
  if not step then return cards end
  local seats = #view.seats + 1
  local out = {}
  for index = 1, math.min(#cards, 2) do
    if step >= (index - 1) * seats + position then out[index] = cards[index] end
  end
  return out
end

--- Whether the hands have been judged in this picture yet, or the dealer's cards are still turning.
function M.judged(view, anim)
  if view.phase ~= "over" then return false end
  if anim and (anim.ev.type == "reveal" or anim.ev.type == "draw") then return false end
  return true
end

local OUTCOME = {
  blackjack = { "BLACKJACK", "gold" }, win = { "WIN", "win" }, push = { "PUSH", "text" },
  lose = { "LOSE", "red" }, bust = { "BUST", "red" },
}

--- The word for a judged hand, and its colour.
function M.outcome(hand)
  local look = OUTCOME[hand.result] or OUTCOME.push
  local word = look[1]
  if hand.net and hand.net ~= 0 then word = word .. " " .. ui.signed(hand.net) end
  return word, C[look[2]]
end

--- The word on a hand still being played, and its colour. Nil when the number alone says it.
function M.tag(hand)
  if hand.total > 21 then return "BUST", C.red end
  if hand.natural then return "BLACKJACK", C.gold end
  if hand.doubled then return "DOUBLED", C.gold end
  if hand.soft and hand.total < 21 then return "soft", C.text end
  return nil
end

function M.totalColor(total)
  if total > 21 then return C.red end
  if total == 21 then return C.gold end
  return C.text
end

return M
