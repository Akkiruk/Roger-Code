-- holdem_rules.lua
-- Ultimate Texas Hold'em against the dealer. Pure: no screen, no sound, no money.
-- A wager is { ante = n, side = n }: the Blind always equals the Ante, and side is the Trips bet or 0.
-- A plain number is an ante with no side bet. tools/casinotest/holdem-oracle.mjs reads the tables below.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")

local M = {
  MAX_ANTE = 25,        -- a 500 to 1 Blind on a bigger bet is more than a table should promise
  BOARD_SIZE = 5,
  HOLE_SIZE = 2,
  -- Paid on the Blind when you win, in tokens per token. Lesser winning hands push it.
  BLIND = {
    { id = "royal", name = "Royal Flush", pays = 500, text = "500 to 1" },
    { id = "straightFlush", name = "Straight Flush", pays = 50, text = "50 to 1" },
    { id = "quads", name = "Four of a Kind", pays = 10, text = "10 to 1" },
    { id = "fullHouse", name = "Full House", pays = 3, text = "3 to 1" },
    { id = "flush", name = "Flush", pays = 1.5, text = "3 to 2" },
    { id = "straight", name = "Straight", pays = 1, text = "1 to 1" },
  },
  -- Paid on your final hand alone, even if you fold
  TRIPS = {
    { id = "royal", name = "Royal Flush", pays = 50 },
    { id = "straightFlush", name = "Straight Flush", pays = 40 },
    { id = "quads", name = "Four of a Kind", pays = 30 },
    { id = "fullHouse", name = "Full House", pays = 8 },
    { id = "flush", name = "Flush", pays = 7 },
    { id = "straight", name = "Straight", pays = 4 },
    { id = "trips", name = "Three of a Kind", pays = 3 },
  },
  ANTE_RETURN = 0.9757,   -- per Ante, by a published simple strategy, over 150 million hands in the oracle above
  SIDE_RETURN = 0.9650,   -- the Trips bet, exact
}

local CATEGORY_IDS = {
  [poker.ROYAL] = "royal",
  [poker.STRAIGHT_FLUSH] = "straightFlush",
  [poker.QUADS] = "quads",
  [poker.FULL_HOUSE] = "fullHouse",
  [poker.FLUSH] = "flush",
  [poker.STRAIGHT] = "straight",
  [poker.TRIPS] = "trips",
}

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

--- The most a wager can win: a royal flush raised 4x. A plain number counts the side bet as on.
function M.maxWin(wager)
  local ante, side = parts(wager)
  if type(wager) ~= "table" then side = ante end
  return ante + ante * 4 + ante * M.BLIND[1].pays + side * M.TRIPS[1].pays
end

function M.new(wager, rng, _, _)
  local ante, side = parts(wager)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local state = {
    ante = ante, blind = ante, side = side, cards = cards,
    player = {}, dealer = {}, board = {},
    stage = "preflop", shown = 0, play = 0, folded = false, over = false,
  }
  local events = {}
  for i = 1, M.HOLE_SIZE do
    state.player[i] = deck.draw(cards)
    events[#events + 1] = { type = "deal", who = "player", i = i, card = state.player[i] }
  end
  for i = 1, M.HOLE_SIZE do
    state.dealer[i] = deck.draw(cards)
    events[#events + 1] = { type = "deal", who = "dealer", i = i }
  end
  for i = 1, M.BOARD_SIZE do state.board[i] = deck.draw(cards) end
  return state, events
end

local function raise(state, times)
  local amount = state.ante * times
  return { id = "raise" .. times, label = "BET " .. times .. "X", color = "win", textColor = "ink",
    cost = amount, sub = "Raise: Play " .. amount }
end

function M.actions(state)
  if state.stage == "preflop" then
    return { { id = "check", label = "CHECK", color = "blue" }, raise(state, 3), raise(state, 4) }
  elseif state.stage == "flop" then
    return { { id = "check", label = "CHECK", color = "blue" }, raise(state, 2) }
  end
  return { { id = "fold", label = "FOLD", color = "red", sub = "Lose Ante and Blind" }, raise(state, 1) }
end

--- A hand's seven cards, for either player.
local function seven(hole, board)
  return { hole[1], hole[2], board[1], board[2], board[3], board[4], board[5] }
end

--- Work out every bet once, when the hand is over.
local function settle(state)
  local mine, category = poker.evaluate(seven(state.player, state.board))
  local theirs, dealerCategory = poker.evaluate(seven(state.dealer, state.board))
  local qualified = dealerCategory >= poker.PAIR
  local outcome = { ante = 0, blind = 0, play = 0, side = 0 }
  state.playerScore, state.dealerScore, state.qualified = mine, theirs, qualified
  if state.side > 0 then
    local pays = M.pays(M.TRIPS, category)
    outcome.side = pays > 0 and state.side * pays or -state.side
  end
  if state.folded then
    outcome.ante, outcome.blind = -state.ante, -state.blind
  elseif mine > theirs then
    outcome.play = state.play
    outcome.ante = qualified and state.ante or 0
    outcome.blind = math.floor(state.blind * M.pays(M.BLIND, category))
  elseif mine < theirs then
    outcome.play, outcome.blind = -state.play, -state.blind
    outcome.ante = qualified and -state.ante or 0
  end
  state.outcome = outcome
  state.over = true
end

--- Turn the board up to count, then show the dealer's cards and close the hand.
local function showdown(state, events)
  for i = state.shown + 1, M.BOARD_SIZE do
    events[#events + 1] = { type = "board", i = i, card = state.board[i] }
  end
  state.shown = M.BOARD_SIZE
  for i = 1, M.HOLE_SIZE do
    events[#events + 1] = { type = "reveal", i = i, card = state.dealer[i] }
  end
  settle(state)
  events[#events + 1] = { type = "final" }
  return events
end

local function turnUp(state, count, events)
  for i = state.shown + 1, count do
    events[#events + 1] = { type = "board", i = i, card = state.board[i] }
  end
  state.shown = count
  return events
end

function M.act(state, id, _)
  if state.over then return {} end
  local times = tonumber(tostring(id):match("^raise(%d)$"))
  local legal = false
  for _, action in ipairs(M.actions(state)) do
    if action.id == id then legal = true end
  end
  if not legal then return {} end
  if times then
    state.play = state.ante * times
    return showdown(state, { { type = "bet", amount = state.play } })
  elseif id == "fold" then
    state.folded = true
    return showdown(state, { { type = "fold" } })
  elseif state.stage == "preflop" then
    state.stage = "flop"
    return turnUp(state, 3, {})
  end
  state.stage = "river"
  return turnUp(state, M.BOARD_SIZE, {})
end

--- Nobody at the table: check to the river, then fold. No raise happens without the player.
function M.auto(state)
  return state.stage == "river" and "fold" or "check"
end

function M.done(state)
  return state.over == true
end

--- What the player already has at stake.
function M.risk(state)
  return state.ante + state.blind + state.side + state.play
end

function M.net(state)
  local outcome = state.outcome
  return outcome.ante + outcome.blind + outcome.play + outcome.side
end

function M.result(state)
  local total = M.net(state)
  local kind = total > 0 and "win" or total == 0 and "push" or "lose"
  local mine = poker.describe(state.playerScore)
  local theirs = poker.describe(state.dealerScore)
  if state.folded then
    return { kind = kind, title = "FOLDED", detail = "Dealer held " .. theirs }
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
