-- videopoker_test.lua
-- The exact return, over every deal with perfect holds, is proved by tools/casinotest/videopoker-oracle.mjs.
-- Here a simple strategy plays real rounds through the rules: if a paytable slips, this fails first.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rules = require("videopoker_rules")
local t = require("testing")

--- A round dealt exactly these cards, then these draws.
local function rigged(names, bet)
  local rng = t.fastRng(9)
  local state = rules.new(bet or 100, rng, {}, {})
  state.cards = deck.stack(deck.fresh(1), names)
  for i = 1, 5 do state.hand[i] = deck.draw(state.cards) end
  return state, rng
end

local function hold(state, rng, slots)
  for _, slot in ipairs(slots) do rules.act(state, "hold" .. slot, rng) end
end

t.test("the paytable is the agreed table of total returns", function()
  local want = { 250, 50, 25, 9, 6, 4, 3, 2, 1 }
  for i, line in ipairs(rules.PAYS) do t.eq(line.multiple, want[i], line.name) end
end)

t.test("a pair of Jacks gives the bet back and nothing more", function()
  local state, rng = rigged({ "JC", "JD", "2H", "7S", "9C", "3C", "4D", "6S" })
  hold(state, rng, { 1, 2 })
  rules.act(state, "draw", rng)
  t.eq(state.tier, "jacks")
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
end)

t.test("every line pays bet times its multiple less the bet", function()
  local hands = {
    royal = { "10S", "JS", "QS", "KS", "AS" }, straightFlush = { "5H", "6H", "7H", "8H", "9H" },
    quads = { "9C", "9D", "9H", "9S", "2C" }, fullHouse = { "9C", "9D", "9H", "2S", "2C" },
    flush = { "2H", "6H", "9H", "JH", "KH" }, straight = { "5C", "6D", "7H", "8S", "9C" },
    trips = { "9C", "9D", "9H", "2S", "3C" }, twoPair = { "9C", "9D", "2H", "2S", "3C" },
    jacks = { "QC", "QD", "2H", "5S", "9C" },
  }
  for _, line in ipairs(rules.PAYS) do
    local state, rng = rigged(hands[line.id])
    hold(state, rng, { 1, 2, 3, 4, 5 })
    rules.act(state, "draw", rng)
    t.eq(state.tier, line.id)
    t.eq(rules.net(state), 100 * line.multiple - 100, line.name)
    t.truthy(rules.maxWin(100) >= rules.net(state), "maxWin covers " .. line.name)
  end
end)

t.test("nothing paying loses the bet, and low pairs do not pay", function()
  local state, rng = rigged({ "10C", "10D", "2H", "7S", "9C" })
  hold(state, rng, { 1, 2, 3, 4, 5 })
  rules.act(state, "draw", rng)
  t.eq(state.tier, false)
  t.eq(rules.net(state), -100)
  local result = rules.result(state)
  t.eq(result.kind, "lose")
  t.eq(result.detail, "Pair of Tens")
end)

t.test("holds toggle, and only unheld cards are replaced", function()
  local state, rng = rigged({ "KC", "JD", "2H", "7S", "9C", "3C", "4D", "5S" })
  hold(state, rng, { 1, 3, 3, 4, 5 })
  t.eq(state.held[3], false, "a second tap lets go")
  local keepA, keepD, keepE = state.hand[1], state.hand[4], state.hand[5]
  local events = rules.act(state, "draw", rng)
  t.eq(state.hand[1], keepA)
  t.eq(state.hand[4], keepD)
  t.eq(state.hand[5], keepE)
  t.eq(state.hand[2], deck.parse("3C"), "the next card in")
  t.eq(state.hand[3], deck.parse("4D"), "and the next")
  t.eq(#events, 4, "discard, two flips, the final")
  t.truthy(rules.done(state))
end)

t.test("the deal has five different cards and leaves 47", function()
  local rng = t.fastRng(4)
  local state = rules.new(10, rng, {}, {})
  local seen = {}
  for _, card in ipairs(state.hand) do
    t.truthy(not seen[card], "unique")
    seen[card] = true
  end
  for _, card in ipairs(state.cards) do t.truthy(not seen[card], "not in the deck too") end
  t.eq(#state.cards, 47)
end)

t.test("walking away keeps any hand that pays", function()
  local state, rng = rigged({ "JC", "JD", "2H", "7S", "9C", "3C", "4D", "6S" })
  rules.act(state, rules.auto(state), rng)
  t.truthy(state.held[1] and state.held[2], "the pair stays")
  t.eq(state.held[3], false, "the rest are drawn to")
  t.truthy(rules.net(state) >= 0, "the win was not thrown away")
  t.eq(state.hand[3], deck.parse("3C"))
end)

t.test("walking away stands on a made flush", function()
  local state, rng = rigged({ "2H", "6H", "9H", "JH", "KH" })
  rules.act(state, rules.auto(state), rng)
  t.eq(state.tier, "flush")
  t.eq(rules.net(state), 500)
end)

t.test("walking away respects the player's own holds", function()
  local state, rng = rigged({ "JC", "JD", "2H", "7S", "9C", "AH", "3D", "4D", "6S" })
  hold(state, rng, { 2 })
  rules.act(state, rules.auto(state), rng)
  t.eq(state.held[1], false, "the player's choice stands")
end)

t.test("state survives being written out and read back", function()
  if not rawget(_G, "textutils") then return end -- only the emulator has the serializer the journal uses
  local state, rng = rigged({ "JC", "JD", "2H", "7S", "9C", "3C", "4D", "6S" })
  rules.act(state, "hold1", rng)
  local restored = textutils.unserialize(textutils.serialize(state, { compact = true }))
  t.eq(restored.held[1], true)
  t.eq(restored.held[2], false)
  t.eq(#restored.cards, #state.cards)
  rules.act(restored, "draw", rng)
  t.truthy(rules.done(restored))
end)

--- A simple strategy: keep made hands, four to a flush, four to an outside straight, high pairs, high cards.
local function simple(state)
  local hand = state.hand
  if poker.jacksOrBetter(hand) then
    local marks = poker.scoring(hand)
    for i = 1, 5 do
      if marks[i] ~= state.held[i] then return "hold" .. i end
    end
    return "draw"
  end
  local suitCount, rankCount = {}, {}
  for i = 1, 5 do
    local s, r = deck.suit(hand[i]), deck.rank(hand[i])
    suitCount[s] = (suitCount[s] or 0) + 1
    rankCount[r] = (rankCount[r] or 0) + 1
  end
  local want = {}
  local pairRank = nil
  for r, n in pairs(rankCount) do
    if n == 2 then pairRank = r end
  end
  local flushSuit = nil
  for s, n in pairs(suitCount) do
    if n == 4 then flushSuit = s end
  end
  for i = 1, 5 do
    local r = deck.rank(hand[i])
    if flushSuit then
      want[i] = deck.suit(hand[i]) == flushSuit
    elseif pairRank then
      want[i] = r == pairRank
    else
      want[i] = r >= 11
    end
  end
  for i = 1, 5 do
    if want[i] ~= state.held[i] then return "hold" .. i end
  end
  return "draw"
end

t.test("a simple strategy returns less than 100%", function()
  local total = t.simulate(rules, 150000, 1000, simple, 2024)
  print(("     simple strategy return %.3f%%"):format(total * 100))
  t.truthy(total < 1, "the house must keep an edge, got " .. total)
  t.truthy(total > 0.93, "a sane strategy should not lose this much: " .. total)
end)
