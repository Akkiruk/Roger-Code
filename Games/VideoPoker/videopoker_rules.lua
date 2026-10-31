-- videopoker_rules.lua
-- Jacks or Better from one deck, shuffled fresh for every hand. Pure: no screen, no sound, no money.
-- Pay lines are the TOTAL returned per token bet, so a pair of Jacks gives the bet back and nothing more.
-- tools/casinotest/videopoker-oracle.mjs reads the lines below and fails if the exact return leaves its target.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")

local M = {
  HAND_SIZE = 5,
  PAYS = {
    { id = "royal", name = "Royal Flush", multiple = 250 },
    { id = "straightFlush", name = "Straight Flush", multiple = 50 },
    { id = "quads", name = "Four of a Kind", multiple = 25 },
    { id = "fullHouse", name = "Full House", multiple = 9 },
    { id = "flush", name = "Flush", multiple = 6 },
    { id = "straight", name = "Straight", multiple = 4 },
    { id = "trips", name = "Three of a Kind", multiple = 3 },
    { id = "twoPair", name = "Two Pair", multiple = 2 },
    { id = "jacks", name = "Jacks or Better", multiple = 1 },
  },
  RETURN = 0.98373,     -- the exact return with perfect holds, proved by the oracle above
}

--- The pay line for a tier id.
function M.line(tier)
  for _, line in ipairs(M.PAYS) do
    if line.id == tier then return line end
  end
  return nil
end

local function payout(state)
  local line = state.tier and M.line(state.tier)
  return line and state.bet * line.multiple or 0
end

function M.maxWin(bet)
  return bet * (M.PAYS[1].multiple - 1)
end

function M.new(bet, rng, _, _)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local state = { bet = bet, cards = cards, hand = {}, held = {}, over = false, tier = false }
  local events = {}
  for i = 1, M.HAND_SIZE do
    state.hand[i] = deck.draw(cards)
    state.held[i] = false
    events[i] = { type = "deal", i = i, card = state.hand[i] }
  end
  return state, events
end

local function heldCount(state)
  local count = 0
  for i = 1, M.HAND_SIZE do
    if state.held[i] then count = count + 1 end
  end
  return count
end

function M.actions(state)
  local kept = heldCount(state)
  local sub = kept == M.HAND_SIZE and "Stand on all five" or ("New cards: " .. (M.HAND_SIZE - kept))
  return { { id = "draw", label = "DRAW", color = "win", textColor = "ink", sub = sub } }
end

local function draw(state)
  local events = {}
  if heldCount(state) < M.HAND_SIZE then events[1] = { type = "discard" } end
  for i = 1, M.HAND_SIZE do
    if not state.held[i] then
      state.hand[i] = deck.draw(state.cards)
      events[#events + 1] = { type = "flip", i = i, card = state.hand[i] }
    end
  end
  state.tier = poker.jacksOrBetter(state.hand) or false
  state.over = true
  events[#events + 1] = { type = "final", tier = state.tier }
  return events
end

--- With no holds chosen, keep the cards that already pay, so walking away never throws a win away.
local function holdPaying(state)
  if heldCount(state) > 0 or not poker.jacksOrBetter(state.hand) then return end
  local marks = poker.scoring(state.hand)
  for i = 1, M.HAND_SIZE do state.held[i] = marks[i] end
end

function M.act(state, id, _)
  if state.over then return {} end
  local slot = tonumber(tostring(id):match("^hold(%d)$"))
  if slot then
    if slot >= 1 and slot <= M.HAND_SIZE then state.held[slot] = not state.held[slot] end
    return {}
  end
  if id == "auto" then holdPaying(state) end
  return draw(state)
end

--- Nobody at the table: draw to the holds already made, keeping any hand that pays.
function M.auto(_)
  return "auto"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.bet
end

function M.net(state)
  return payout(state) - state.bet
end

function M.result(state)
  local line = state.tier and M.line(state.tier)
  if not line then
    return { kind = "lose", title = "NO WIN", detail = poker.describe((poker.evaluate(state.hand))) }
  end
  if line.multiple == 1 then
    return { kind = "push", title = line.name:upper(), detail = "Your bet comes back" }
  end
  return { kind = "win", title = line.name:upper(), detail = ("Pays %d for 1"):format(line.multiple) }
end

function M.finish()
end

return M
