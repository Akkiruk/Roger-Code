-- poker_test.lua
-- The evaluator against every 5-card and 3-card hand there is. Every 7-card hand is proved by
-- tools/casinotest/poker7.mjs, which needs a few minutes of real Lua; here a sample checks best-of-seven.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local t = require("testing")

local function cards(text)
  local list = {}
  for name in text:gmatch("%S+") do list[#list + 1] = deck.parse(name) end
  return list
end

--- A hand's score by the slow road: try all 21 ways of choosing five from seven.
local function bestOfFive(seven)
  local best, five = -1, {}
  for skipA = 1, 6 do
    for skipB = skipA + 1, 7 do
      local n = 0
      for i = 1, 7 do
        if i ~= skipA and i ~= skipB then
          n = n + 1
          five[n] = seven[i]
        end
      end
      local value = poker.evaluate(five)
      if value > best then best = value end
    end
  end
  return best
end

t.test("every 2,598,960 five card hand lands in the right class", function()
  local counts, tiers, seen, distinct = {}, {}, {}, 0
  local hand = {}
  local total = 0
  for a = 0, 47 do
    hand[1] = a
    for b = a + 1, 48 do
      hand[2] = b
      for c = b + 1, 49 do
        hand[3] = c
        for d = c + 1, 50 do
          hand[4] = d
          for e = d + 1, 51 do
            hand[5] = e
            local value, category = poker.evaluate(hand)
            counts[category] = (counts[category] or 0) + 1
            if not seen[value] then
              seen[value] = true
              distinct = distinct + 1
            end
            local rank = poker.topRank(value)
            if category == poker.PAIR and rank >= 11 then tiers.jacks = (tiers.jacks or 0) + 1 end
            total = total + 1
          end
        end
        if total % 100000 < 48 then t.breathe() end
      end
    end
  end
  t.eq(total, 2598960, "hands")
  t.eq(counts[poker.ROYAL], 4, "royal flushes")
  t.eq(counts[poker.STRAIGHT_FLUSH], 36, "straight flushes")
  t.eq(counts[poker.QUADS], 624, "four of a kind")
  t.eq(counts[poker.FULL_HOUSE], 3744, "full houses")
  t.eq(counts[poker.FLUSH], 5108, "flushes")
  t.eq(counts[poker.STRAIGHT], 10200, "straights")
  t.eq(counts[poker.TRIPS], 54912, "three of a kind")
  t.eq(counts[poker.TWO_PAIR], 123552, "two pair")
  t.eq(tiers.jacks, 337920, "jacks or better")
  t.eq(counts[poker.PAIR], 1098240, "pairs")
  t.eq(counts[poker.HIGH_CARD], 1302540, "high cards")
  t.eq(distinct, 7462, "distinct hand strengths")
end)

t.test("every 22,100 three card hand lands in the right class", function()
  local counts, seen, distinct = {}, {}, 0
  local hand = {}
  for a = 0, 49 do
    hand[1] = a
    for b = a + 1, 50 do
      hand[2] = b
      for c = b + 1, 51 do
        hand[3] = c
        local value, category = poker.three(hand)
        counts[category] = (counts[category] or 0) + 1
        if not seen[value] then
          seen[value] = true
          distinct = distinct + 1
        end
      end
    end
  end
  t.eq(counts[poker.T_STRAIGHT_FLUSH], 48, "straight flushes")
  t.eq(counts[poker.T_TRIPS], 52, "three of a kind")
  t.eq(counts[poker.T_STRAIGHT], 720, "straights")
  t.eq(counts[poker.T_FLUSH], 1096, "flushes")
  t.eq(counts[poker.T_PAIR], 3744, "pairs")
  t.eq(counts[poker.T_HIGH], 16440, "high cards")
  -- 12 straights, 13 sets, 12*13 pairs, and C(13,3)-12 high hands which also come as flushes
  t.eq(distinct, 12 + 13 + 156 + 274 + 274 + 12, "distinct hand strengths")
end)

t.test("three card ranks run the right way", function()
  local function score(text) return (poker.three(cards(text))) end
  t.truthy(score("2C 3D 4H") > score("AC KD JH"), "a straight beats ace high")
  t.truthy(score("2C 3D 4H") > score("AC KC JC"), "a straight beats a flush")
  t.truthy(score("2C 2D 2H") > score("QC KD AH"), "three of a kind beats a straight")
  t.truthy(score("2C 3C 4C") > score("AC AD AH"), "a straight flush beats three aces")
  t.truthy(score("QC KD AH") > score("JC QD KH"), "Q-K-A is the top straight")
  t.truthy(score("2C 3D 4H") > score("AC 2D 3H"), "A-2-3 is the bottom straight")
  t.truthy(score("QC KC AC") > score("AD 2D 3D"), "and the same among straight flushes")
  t.truthy(score("5C 5D AH") > score("4C 4D KH"), "the pair counts before the odd card")
  t.truthy(score("5C 5D AH") > score("5H 5S KH"), "then the odd card")
  t.truthy(score("AC 5D 3H") > score("KC QD 10S"), "high cards compare in order")
  t.eq(score("AC KD 9H"), score("AD KS 9C"), "suits never split a tie")
  t.eq(poker.describeThree(score("QC 6D 4H")), "Queen High")
  t.eq(poker.describeThree(score("10C 10D 4H")), "Pair of Tens")
end)

t.test("the five card order breaks ties the way a table does", function()
  local function beats(a, b, what) t.eq(poker.compare(cards(a), cards(b)), 1, what) end
  beats("10S JS QS KS AS", "9S 10S JS QS KS", "royal over a straight flush")
  beats("AS 2S 3S 4S 5S", "AC KD QH JS 10C", "a steel wheel over Broadway")
  beats("2S 3S 4S 5S 6S", "AS 2S 3S 4S 5S", "the wheel is the lowest straight flush")
  beats("9C 9D 9H 9S 3C", "8C 8D 8H 8S AS", "quads by rank")
  beats("9C 9D 9H 9S 4C", "9C 9D 9H 9S 3D", "then kicker")
  beats("9C 9D 9H 2S 2C", "8C 8D 8H AS AC", "a full house by its three")
  beats("9C 9D 9H AS AC", "9C 9D 9H KS KC", "then its pair")
  beats("AC 9C 7C 3C 2C", "KC QC JC 10C 8C", "flush by top card")
  beats("AC KC 7C 3C 2C", "AD KD 6D 5D 4D", "then down the five")
  beats("2C 3D 4H 5S 6C", "AC 2D 3H 4S 5C", "the wheel is the lowest straight")
  beats("AC AD 3H 3S 2C", "KC KD QH QS AC", "two pair by the top pair")
  beats("AC AD 4H 4S 2C", "AH AS 3H 3S KC", "then the second pair")
  beats("AC AD 4H 4S KC", "AH AS 4D 4C QC", "then the kicker")
  beats("7C 7D AH 3S 2C", "7H 7S KH QS JC", "pair then kickers")
  beats("AC KD 9H 5S 3C", "AD KS 9C 5H 2D", "high card to the fifth card")
  t.eq(poker.compare(cards("AC KD 9H 5S 3C"), cards("AD KS 9C 5H 3D")), 0, "a true tie")
end)

t.test("seven cards play their best five", function()
  local function name(text) return poker.NAMES[poker.category((poker.evaluate(cards(text))))] end
  t.eq(name("AS KS QS JS 10S 2C 3D"), "Royal Flush")
  t.eq(name("AS 2S 3S 4S 5S KD KC"), "Straight Flush", "a wheel in the suit")
  t.eq(name("9S 8S 7S 6S 5H 4S 3S"), "Flush", "a straight and a flush that are not one hand")
  t.eq(name("9C 9D 9H 8C 8D 8H 2S"), "Full House", "two sets")
  t.eq(name("9C 9D 9H 8C 8D 7H 7S"), "Full House", "a set and two pairs")
  t.eq(name("9C 9D 9H 9S 8D 8H 8S"), "Four of a Kind", "quads over a set")
  t.eq(name("AC KD QH JS 10C 10D 10H"), "Straight", "a straight over a set")
  t.eq(name("AC AD KH KS QC QD 2H"), "Two Pair", "three pairs still play two")
  t.eq(poker.compare(cards("AC AD KH KS QC QD 2H"), cards("AH AS KC KD JC 10D 2H")), 1, "the third pair is the kicker")
  t.eq(poker.compare(cards("KC KD QH QS JC JD 2H"), cards("KH KS QC QD JS 8D 7H")), 0, "the odd card plays the same")
  t.eq(poker.compare(cards("7C 8D 9H 10S JC QD KH"), cards("7H 8S 9C 10D JH QS 2C")), 1, "the highest of a long straight")
  t.eq(poker.compare(cards("AC 2C 9C 8C 7C 3D 4D"), cards("AD 2D 9D 8D 7D 3C 5H")), 0, "only five of the suit count")
  t.eq(#poker.bestFive(cards("AC 2C 9C 8C 7C 3D 4D")), 5)
end)

t.test("best of seven matches trying all 21 fives", function()
  local rng = t.fastRng(77)
  local seven = {}
  for i = 1, 30000 do
    local cardsLeft = deck.fresh(1)
    for k = 1, 7 do
      local j = rng:below(#cardsLeft) + 1
      seven[k] = cardsLeft[j]
      cardsLeft[j] = cardsLeft[#cardsLeft]
      cardsLeft[#cardsLeft] = nil
    end
    local value = poker.evaluate(seven)
    t.eq(value, bestOfFive(seven), "seven cards")
    t.eq(value, (poker.evaluate(poker.bestFive(seven))), "the five it names")
    if i % 2000 == 0 then t.breathe() end
  end
end)

t.test("scoring marks the cards that make the hand", function()
  local function marks(text)
    local out = {}
    for i, mark in ipairs(poker.scoring(cards(text))) do out[i] = mark and "1" or "0" end
    return table.concat(out)
  end
  t.eq(marks("JC JD 4H 7S 9C"), "11000", "a pair")
  t.eq(marks("JC JD 4H 4S 9C"), "11110", "two pair")
  t.eq(marks("JC JD JH 4S 9C"), "11100", "three of a kind")
  t.eq(marks("JC JD JH JS 9C"), "11110", "four of a kind")
  t.eq(marks("JC JD JH 9S 9C"), "11111", "a full house")
  t.eq(marks("2C 4C 6C 8C 10C"), "11111", "a flush")
  t.eq(marks("2C 3D 4H 5S 6C"), "11111", "a straight")
  t.eq(marks("2C 4D 6H 8S 10C"), "00000", "nothing")
end)

t.test("hands read as a table would say them", function()
  local function say(text) return poker.describe((poker.evaluate(cards(text)))) end
  t.eq(say("KC KD 4H 7S 9C"), "Pair of Kings")
  t.eq(say("6C 6D 4H 7S 9C"), "Pair of Sixes")
  t.eq(say("AC QD 4H 7S 9C"), "Ace High")
  t.eq(say("6C 6D 6H 7S 9C"), "Three of a Kind")
end)
