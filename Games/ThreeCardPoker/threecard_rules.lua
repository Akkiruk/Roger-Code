-- threecard_rules.lua
-- Three Card Poker against the dealer. Pure: no screen, no sound, no money.
-- A wager is { ante = n, side = n }, side being the Pair Plus bet or 0. A plain number is an ante with no side bet.
-- tools/casinotest/threecard-oracle.mjs reads the tables below and enumerates every deal for the exact returns.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")

local M = {
  HAND_SIZE = 3,
  -- Paid on the Ante when you play, whatever the dealer holds
  ANTE_BONUS = {
    { id = "straightFlush", name = "Straight Flush", pays = 5 },
    { id = "trips", name = "Three of a Kind", pays = 4 },
    { id = "straight", name = "Straight", pays = 1 },
  },
  -- Paid on your hand alone, even if you fold
  PAIR_PLUS = {
    { id = "straightFlush", name = "Straight Flush", pays = 40 },
    { id = "trips", name = "Three of a Kind", pays = 30 },
    { id = "straight", name = "Straight", pays = 6 },
    { id = "flush", name = "Flush", pays = 3 },
    { id = "pair", name = "Pair", pays = 1 },
  },
  QUALIFY_RANK = 12,    -- the dealer needs Queen high or better
  ANTE_RETURN = 0.9663, -- exact returns, proved by the oracle above
  SIDE_RETURN = 0.9272,
}

local CATEGORY_IDS = {
  [poker.T_STRAIGHT_FLUSH] = "straightFlush",
  [poker.T_TRIPS] = "trips",
  [poker.T_STRAIGHT] = "straight",
  [poker.T_FLUSH] = "flush",
  [poker.T_PAIR] = "pair",
}

--- The lowest hand worth playing: Queen, 6, 4.
M.PLAY_FLOOR = poker.three({ deck.card(12, 0), deck.card(6, 1), deck.card(4, 2) })

--- What a table of pays gives this category, 0 if nothing.
function M.pays(paytable, category)
  local id = CATEGORY_IDS[category]
  for _, line in ipairs(paytable) do
    if line.id == id then return line.pays end
  end
  return 0
end

local function parts(wager)
  if type(wager) == "table" then return wager.ante, wager.side or 0 end
  return wager, 0
end

--- The most a wager can win: a straight flush that takes every bet. A plain number counts the side bet as on.
function M.maxWin(wager)
  local ante, side = parts(wager)
  if type(wager) ~= "table" then side = ante end
  return ante * 2 + ante * M.ANTE_BONUS[1].pays + side * M.PAIR_PLUS[1].pays
end

function M.qualifies(value)
  return poker.threeCategory(value) > poker.T_HIGH or math.floor(value / 225) % 15 >= M.QUALIFY_RANK
end

function M.new(wager, rng, _, _)
  local ante, side = parts(wager)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local state = { ante = ante, side = side, cards = cards, player = {}, dealer = {}, over = false, folded = false }
  local events = {}
  for i = 1, M.HAND_SIZE do
    state.player[i] = deck.draw(cards)
    events[#events + 1] = { type = "deal", who = "player", i = i, card = state.player[i] }
  end
  for i = 1, M.HAND_SIZE do
    state.dealer[i] = deck.draw(cards)
    events[#events + 1] = { type = "deal", who = "dealer", i = i }
  end
  return state, events
end

function M.actions(state)
  return {
    { id = "fold", label = "FOLD", color = "red", sub = "Lose the Ante" },
    { id = "play", label = "PLAY", color = "win", textColor = "ink", cost = state.ante, sub = "Bet " .. state.ante },
  }
end

--- Work out every bet once, when the hand is over.
local function settle(state)
  local mine, category = poker.three(state.player)
  local theirs = poker.three(state.dealer)
  local outcome = { ante = 0, play = 0, bonus = 0, side = 0 }
  state.playerScore, state.dealerScore = mine, theirs
  state.qualified = M.qualifies(theirs)
  if state.side > 0 then
    local pays = M.pays(M.PAIR_PLUS, category)
    outcome.side = pays > 0 and state.side * pays or -state.side
  end
  if state.folded then
    outcome.ante = -state.ante
  else
    outcome.bonus = state.ante * M.pays(M.ANTE_BONUS, category)
    if not state.qualified then
      outcome.ante = state.ante
    elseif mine > theirs then
      outcome.ante, outcome.play = state.ante, state.ante
    elseif mine < theirs then
      outcome.ante, outcome.play = -state.ante, -state.ante
    end
  end
  state.outcome = outcome
  state.over = true
end

function M.act(state, id, _)
  if state.over or (id ~= "play" and id ~= "fold") then return {} end
  local events = {}
  if id == "play" then
    state.played = true
    events[1] = { type = "bet" }
  else
    state.folded = true
    events[1] = { type = "fold" }
  end
  for i = 1, M.HAND_SIZE do
    events[#events + 1] = { type = "reveal", i = i, card = state.dealer[i] }
  end
  settle(state)
  events[#events + 1] = { type = "final" }
  return events
end

--- Nobody at the table: fold anything below Queen, 6, 4, the rule that gives the best return.
function M.auto(state)
  return poker.three(state.player) >= M.PLAY_FLOOR and "play" or "fold"
end

function M.done(state)
  return state.over == true
end

--- What the player already has at stake.
function M.risk(state)
  return state.ante + state.side + (state.played and state.ante or 0)
end

function M.net(state)
  local outcome = state.outcome
  return outcome.ante + outcome.play + outcome.bonus + outcome.side
end

function M.result(state)
  local total = M.net(state)
  local kind = total > 0 and "win" or total == 0 and "push" or "lose"
  local mine = poker.describeThree(state.playerScore)
  local theirs = poker.describeThree(state.dealerScore)
  if state.folded then
    return { kind = kind, title = "FOLDED", detail = "Dealer held " .. theirs }
  end
  if not state.qualified then
    return { kind = kind, title = "DEALER PASSES", detail = theirs .. " does not qualify" }
  end
  if state.playerScore > state.dealerScore then
    return { kind = kind, title = "YOU WIN", detail = mine .. " beats " .. theirs }
  end
  if state.playerScore < state.dealerScore then
    return { kind = kind, title = "DEALER WINS", detail = theirs .. " beats " .. mine }
  end
  return { kind = kind, title = "TIE", detail = "Both hold " .. mine }
end

function M.finish()
end

return M
