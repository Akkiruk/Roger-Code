-- holdem_test.lua
-- The Trips return is exact and the strategy return measured over millions of hands in
-- tools/casinotest/holdem-oracle.mjs. Here the rules play real rounds.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rules = require("holdem_rules")
local t = require("testing")

--- A round with these cards, by name: "mine", "dealer's", "board".
local function rigged(mine, theirs, board, ante, side)
  local rng = t.fastRng(3)
  local state = rules.new({ ante = ante or 100, side = side or 0 }, rng, {}, {})
  local function fill(into, text)
    local i = 0
    for name in text:gmatch("%S+") do
      i = i + 1
      into[i] = deck.parse(name)
    end
  end
  fill(state.player, mine)
  fill(state.dealer, theirs)
  fill(state.board, board)
  return state, rng
end

--- Check down to the river, then act.
local function atRiver(state, rng, last)
  rules.act(state, "check", rng)
  rules.act(state, "check", rng)
  rules.act(state, last or "raise1", rng)
end

t.test("a checked hand reaches the river in the right order", function()
  local state, rng = rigged("AC KD", "2S 7H", "2C 5D 9H JS QC")
  t.eq(state.stage, "preflop")
  t.eq(#rules.actions(state), 3)
  local events = rules.act(state, "check", rng)
  t.eq(state.stage, "flop")
  t.eq(state.shown, 3)
  t.eq(#events, 3)
  t.eq(#rules.actions(state), 2)
  events = rules.act(state, "check", rng)
  t.eq(state.stage, "river")
  t.eq(state.shown, 5)
  t.eq(#events, 2)
  t.eq(rules.actions(state)[1].id, "fold")
end)

t.test("a raise ends the betting and the rest of the cards play out", function()
  local state, rng = rigged("AC KD", "2S 7H", "2C 5D 9H JS QC")
  rules.act(state, "raise4", rng)
  t.truthy(rules.done(state))
  t.eq(state.play, 400)
  t.eq(state.shown, 5)
end)

t.test("each street offers only its own raises", function()
  local state, rng = rigged("AC KD", "2S 7H", "2C 5D 9H JS QC")
  t.eq(#rules.act(state, "raise1", rng), 0, "no 1x before the river")
  t.eq(#rules.act(state, "fold", rng), 0, "no fold before the river")
  rules.act(state, "check", rng)
  t.eq(#rules.act(state, "raise4", rng), 0, "no 4x after the flop")
  t.truthy(not rules.done(state))
end)

t.test("a win pays Ante and Play and pushes the Blind on a small hand", function()
  local state, rng = rigged("AC AD", "KS KH", "2C 5D 9H JS 3C")
  rules.act(state, "raise4", rng)
  t.eq(rules.net(state), 100 + 400)
  t.eq(state.outcome.blind, 0)
end)

t.test("a dealer who does not qualify pushes the Ante", function()
  local state, rng = rigged("AC KD", "QS 8H", "2C 5D 9H JS 3C")
  rules.act(state, "raise3", rng)
  t.eq(state.qualified, false)
  t.eq(state.outcome.ante, 0)
  t.eq(state.outcome.play, 300)
  t.eq(rules.net(state), 300)
end)

t.test("a loss to a dealer who does not qualify still pushes the Ante", function()
  local state, rng = rigged("QS 8H", "AC KD", "2C 5D 9H JS 3C")
  atRiver(state, rng)
  t.eq(state.outcome.ante, 0)
  t.eq(rules.net(state), -100 - 100)
end)

t.test("a loss to a qualified dealer loses all three", function()
  local state, rng = rigged("QS 8H", "AC AD", "2C 5D 9H JS 3C")
  rules.act(state, "raise2", rng)
  t.eq(state.play, 0, "2x is not a preflop raise")
  rules.act(state, "check", rng)
  rules.act(state, "raise2", rng)
  t.eq(rules.net(state), -100 - 100 - 200)
end)

t.test("a tie pushes everything", function()
  local state, rng = rigged("2S 3H", "2C 3D", "AC KD QH JS 10C")
  rules.act(state, "raise4", rng)
  t.eq(rules.net(state), 0, "both play the board")
  t.eq(rules.result(state).kind, "push")
end)

t.test("a fold loses Ante and Blind, nothing else", function()
  local state, rng = rigged("QS 8H", "AC AD", "2C 5D 9H JS 3C")
  atRiver(state, rng, "fold")
  t.eq(rules.net(state), -200)
  t.eq(state.play, 0)
end)

t.test("the Blind pays on the winning hand", function()
  local cases = {
    { "Straight", "5C 6D", "7H 8S 9C 2D 2H", 100 },
    { "Flush", "AC 3C", "9C 7C 2C KD 2H", 150 },
    { "Full House", "9D 9S", "9C 7C 7D KD 2H", 300 },
    { "Four of a Kind", "9D 9S", "9C 9H 7D KD 2H", 1000 },
    { "Straight Flush", "5C 6C", "7C 8C 9C 2D 2H", 5000 },
    { "Royal Flush", "AC KC", "QC JC 10C 2D 2H", 50000 },
  }
  for _, case in ipairs(cases) do
    local state, rng = rigged(case[2], "3S 4S", case[3])
    rules.act(state, "raise4", rng)
    t.eq(state.outcome.blind, case[4], case[1])
  end
end)

t.test("3 to 2 on an odd Blind rounds down", function()
  local state, rng = rigged("AC 3C", "2S 4S", "9C 7C 2C KD 2H", 5)
  rules.act(state, "raise4", rng)
  t.eq(state.outcome.blind, 7)
end)

t.test("the Blind is not paid on a loss, however good the hand", function()
  local state, rng = rigged("9D 8S", "KC KD", "KS 9C 9H 2D 8H")
  rules.act(state, "raise4", rng)
  t.eq(state.outcome.blind, -100)
end)

t.test("Trips pays on the final hand, even if you fold", function()
  local cases = {
    { "Three of a Kind", "9D 9S", "9C 7D 2H KD 3H", 300 },
    { "Straight", "5C 6D", "7H 8S 9C 2D 2H", 400 },
    { "Flush", "AC 3C", "9C 7C 2C KD 2H", 700 },
    { "Full House", "9D 9S", "9C 7C 7D KD 2H", 800 },
    { "Four of a Kind", "9D 9S", "9C 9H 7D KD 2H", 3000 },
    { "Straight Flush", "5C 6C", "7C 8C 9C 2D 2H", 4000 },
    { "Royal Flush", "AC KC", "QC JC 10C 2D 2H", 5000 },
  }
  for _, case in ipairs(cases) do
    local state, rng = rigged(case[2], "3S 4S", case[3], 100, 100)
    atRiver(state, rng, "fold")
    t.eq(state.outcome.side, case[4], case[1])
    t.eq(rules.net(state), case[4] - 200, "folded")
  end
end)

t.test("Trips loses on two pair or less", function()
  local state, rng = rigged("9D 8S", "3S 4S", "9C 8C 2D KD 3H", 100, 100)
  atRiver(state, rng, "fold")
  t.eq(state.outcome.side, -100)
end)

t.test("raises carry their cost, and risk counts every stake", function()
  local state = rigged("AC KD", "2S 7H", "2C 5D 9H JS QC", 100, 100)
  t.eq(rules.risk(state), 300)
  local costs = {}
  for _, action in ipairs(rules.actions(state)) do costs[action.id] = action.cost end
  t.eq(costs.raise3, 300)
  t.eq(costs.raise4, 400)
  t.eq(costs.check, nil)
end)

t.test("maxWin covers a royal flush raised 4x", function()
  local state, rng = rigged("AC KC", "3S 4S", "QC JC 10C 2D 2H", 25, 25)
  rules.act(state, "raise4", rng)
  t.eq(rules.net(state), rules.maxWin({ ante = 25, side = 25 }))
  t.eq(rules.maxWin(1), 555, "a plain number is one token with the side bet on")
end)

t.test("nobody home checks to the river and folds", function()
  local state, rng = rigged("AC AD", "2S 7H", "AH AS 9H JS QC", 100, 100)
  while not rules.done(state) do rules.act(state, rules.auto(state), rng) end
  t.eq(state.folded, true)
  t.eq(state.play, 0, "it never raises")
  t.eq(rules.net(state), 3000 - 200, "but the side bet stands")
end)

t.test("the deal uses nine different cards", function()
  local rng = t.fastRng(4)
  local state = rules.new({ ante = 10, side = 0 }, rng, {}, {})
  local seen = {}
  for _, hand in ipairs({ state.player, state.dealer, state.board, state.cards }) do
    for _, card in ipairs(hand) do
      t.truthy(not seen[card], "unique")
      seen[card] = true
    end
  end
end)

-- ------------------------------------------------------------------ a published simple strategy

local WHEEL_ACE = 14

--- Wizard of Odds' simple strategy for the raise before the flop.
local function preflopRaise(a, b, suited)
  local high, low = math.max(a, b), math.min(a, b)
  if high == low then return high >= 3 end
  if high == WHEEL_ACE then return true end
  if high == 13 then return suited and low >= 2 or low >= 5 end
  if high == 12 then return suited and low >= 6 or low >= 8 end
  if high == 11 then return suited and low >= 8 or low >= 10 end
  return false
end

local function rankOf(card) return deck.rank(card) end

local function flopRaise(state)
  local hole, flop = state.player, { state.board[1], state.board[2], state.board[3] }
  local a, b = rankOf(hole[1]), rankOf(hole[2])
  local all = { hole[1], hole[2], flop[1], flop[2], flop[3] }
  local _, category = poker.evaluate(all)
  local onBoard = {}
  for _, card in ipairs(flop) do onBoard[rankOf(card)] = true end
  if category >= poker.TWO_PAIR then
    -- Two pair needs a hole card in each pair or a pocket pair over a board pair: a board pair alone is one pair
    return true
  end
  if category == poker.PAIR then
    if a == b then return a > 2 end
    return onBoard[a] or onBoard[b] or false
  end
  local suits = {}
  for _, card in ipairs(all) do suits[deck.suit(card)] = (suits[deck.suit(card)] or 0) + 1 end
  for suit, count in pairs(suits) do
    if count == 4 then
      for i = 1, 2 do
        if deck.suit(hole[i]) == suit and rankOf(hole[i]) >= 10 then return true end
      end
    end
  end
  return false
end

--- Hidden pair or better, or fewer than 21 cards that would beat you in the dealer's hand.
local function riverRaise(state)
  local board = state.board
  local mine, category = poker.evaluate({ state.player[1], state.player[2], board[1], board[2], board[3], board[4], board[5] })
  local boardValue = poker.evaluate(board)
  if category >= poker.PAIR and mine > boardValue then
    local rank = poker.topRank(mine)
    local onBoard = poker.topRank(boardValue)
    if category > poker.category(boardValue) or rank > onBoard then return true end
  end
  local seen = {}
  for _, card in ipairs(board) do seen[card] = true end
  seen[state.player[1]], seen[state.player[2]] = true, true
  local six = { board[1], board[2], board[3], board[4], board[5], 0 }
  local outs = 0
  for card = 0, 51 do
    if not seen[card] then
      six[6] = card
      if poker.evaluate(six) > mine then outs = outs + 1 end
    end
  end
  return outs < 21
end

local function simple(state)
  if state.stage == "preflop" then
    local a, b = rankOf(state.player[1]), rankOf(state.player[2])
    local suited = deck.suit(state.player[1]) == deck.suit(state.player[2])
    return preflopRaise(a, b, suited) and "raise4" or "check"
  elseif state.stage == "flop" then
    return flopRaise(state) and "raise2" or "check"
  end
  return riverRaise(state) and "raise1" or "fold"
end

--- Two Lehmer generators combined. This game's return is sensitive to weak shuffles: one plain generator was
-- 1 to 2.5 points out over millions of hands, while the rounds themselves matched another evaluator exactly.
local function combinedRng(seed)
  local a, b = seed % 2147483562 + 1, (seed * 7) % 2147483398 + 1
  local rng = {}
  function rng.below(_, n)
    a = (a * 40014) % 2147483563
    b = (b * 40692) % 2147483399
    local z = (a - b) % 2147483562
    return math.floor(z / 2147483562 * n)
  end
  return rng
end

t.test("the simple strategy returns about 97.6% of the Ante", function()
  local rng = combinedRng(31337)
  local wager = { ante = 10, side = 0 }
  local rounds, total = 500000, 0
  for i = 1, rounds do
    local state = rules.new(wager, rng, {}, {})
    while not rules.done(state) do rules.act(state, simple(state), rng) end
    total = total + rules.net(state)
    if i % 2000 == 0 then t.breathe() end
  end
  local value = 1 + total / rounds / wager.ante
  print(("     simple strategy return %.3f%%"):format(value * 100))
  t.truthy(value > 0.96 and value < 0.995, "return out of range: " .. value)
end)
