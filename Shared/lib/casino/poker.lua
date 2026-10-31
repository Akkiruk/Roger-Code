-- poker.lua
-- What a poker hand is worth. Pure: cards are deck.lua numbers, and nothing here touches a screen or money.
--
-- evaluate(cards) takes 5 to 7 cards and scores the best five of them; three(cards) scores a 3-card poker hand.
-- A score is one plain number, so comparing hands is comparing numbers: higher wins, equal ties.
-- Tests/poker_test.lua proves this over every 5-card and 3-card hand; tools/casinotest/poker7.mjs over every 7-card hand.

local M = {}

M.HIGH_CARD, M.PAIR, M.TWO_PAIR, M.TRIPS, M.STRAIGHT = 1, 2, 3, 4, 5
M.FLUSH, M.FULL_HOUSE, M.QUADS, M.STRAIGHT_FLUSH, M.ROYAL = 6, 7, 8, 9, 10

M.NAMES = {
  "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight",
  "Flush", "Full House", "Four of a Kind", "Straight Flush", "Royal Flush",
}

-- A score is category, then up to five ranks, as digits in base 15
local D1, D2, D3, D4, D5 = 50625, 3375, 225, 15, 1
local CATEGORY = 759375
local floor = math.floor

local function score(category, a, b, c, d, e)
  return category * CATEGORY + (a or 0) * D1 + (b or 0) * D2 + (c or 0) * D3 + (d or 0) * D4 + (e or 0) * D5
end

function M.category(value)
  return floor(value / CATEGORY)
end

--- The first rank in a score: the pair's rank in a pair, the high card in a high card hand.
function M.topRank(value)
  return floor(value / D1) % 15
end

-- Reused between calls: this runs millions of times in the proofs, and it never yields part way through
local ranks, inSuit, suits, kick = {}, {}, {}, {}

--- The top card of the best straight in a table of rank -> count, or nil.
local function straightHigh(counts)
  for high = 14, 6, -1 do
    if counts[high] > 0 and counts[high - 1] > 0 and counts[high - 2] > 0
      and counts[high - 3] > 0 and counts[high - 4] > 0 then
      return high
    end
  end
  if counts[14] > 0 and counts[2] > 0 and counts[3] > 0 and counts[4] > 0 and counts[5] > 0 then return 5 end
  return nil
end

--- Fill kick with the highest ranks present, leaving out skipA and skipB.
local function kickers(skipA, skipB, want)
  local found = 0
  for rank = 14, 2, -1 do
    if ranks[rank] > 0 and rank ~= skipA and rank ~= skipB then
      found = found + 1
      kick[found] = rank
      if found == want then return end
    end
  end
end

--- Score the best five of 5 to 7 cards. Returns the score and its category.
function M.evaluate(cards)
  local n = #cards
  for rank = 2, 14 do ranks[rank] = 0 end
  suits[0], suits[1], suits[2], suits[3] = 0, 0, 0, 0
  for i = 1, n do
    local card = cards[i]
    local rank, suit = floor(card / 4) + 2, card % 4
    ranks[rank] = ranks[rank] + 1
    suits[suit] = suits[suit] + 1
  end

  local flushSuit = nil
  for suit = 0, 3 do
    if suits[suit] >= 5 then flushSuit = suit end
  end
  if flushSuit then
    for rank = 2, 14 do inSuit[rank] = 0 end
    for i = 1, n do
      if cards[i] % 4 == flushSuit then inSuit[floor(cards[i] / 4) + 2] = 1 end
    end
    local high = straightHigh(inSuit)
    if high == 14 then return score(M.ROYAL, 14), M.ROYAL end
    if high then return score(M.STRAIGHT_FLUSH, high), M.STRAIGHT_FLUSH end
  end

  local quad, trip, trip2, pair1, pair2 = 0, 0, 0, 0, 0
  for rank = 14, 2, -1 do
    local count = ranks[rank]
    if count == 4 then
      quad = rank
    elseif count == 3 then
      if trip == 0 then trip = rank elseif trip2 == 0 then trip2 = rank end
    elseif count == 2 then
      if pair1 == 0 then pair1 = rank elseif pair2 == 0 then pair2 = rank end
    end
  end

  if quad > 0 then
    kickers(quad, 0, 1)
    return score(M.QUADS, quad, kick[1]), M.QUADS
  end
  if trip > 0 and (trip2 > 0 or pair1 > 0) then
    -- Two sets of three fill the higher one with the lower; otherwise the best pair fills it
    return score(M.FULL_HOUSE, trip, math.max(trip2, pair1)), M.FULL_HOUSE
  end
  if flushSuit then
    local found = 0
    for rank = 14, 2, -1 do
      if inSuit[rank] > 0 then
        found = found + 1
        kick[found] = rank
        if found == 5 then break end
      end
    end
    return score(M.FLUSH, kick[1], kick[2], kick[3], kick[4], kick[5]), M.FLUSH
  end
  local high = straightHigh(ranks)
  if high then return score(M.STRAIGHT, high), M.STRAIGHT end
  if trip > 0 then
    kickers(trip, 0, 2)
    return score(M.TRIPS, trip, kick[1], kick[2]), M.TRIPS
  end
  if pair2 > 0 then
    kickers(pair1, pair2, 1)
    return score(M.TWO_PAIR, pair1, pair2, kick[1]), M.TWO_PAIR
  end
  if pair1 > 0 then
    kickers(pair1, 0, 3)
    return score(M.PAIR, pair1, kick[1], kick[2], kick[3]), M.PAIR
  end
  kickers(0, 0, 5)
  return score(M.HIGH_CARD, kick[1], kick[2], kick[3], kick[4], kick[5]), M.HIGH_CARD
end

--- 1 when hand a beats hand b, -1 when it loses, 0 on a tie.
function M.compare(a, b)
  local scoreA, scoreB = M.evaluate(a), M.evaluate(b)
  if scoreA > scoreB then return 1 end
  if scoreA < scoreB then return -1 end
  return 0
end

--- The five cards a score of 5 to 7 cards is made from, by trying every way of choosing them.
function M.bestFive(cards)
  local n = #cards
  local bestScore, best = -1, nil
  local pick, chosen = {}, {}
  local function choose(from, depth)
    if depth > 5 then
      for i = 1, 5 do chosen[i] = cards[pick[i]] end
      local value = M.evaluate(chosen)
      if value > bestScore then
        bestScore, best = value, { chosen[1], chosen[2], chosen[3], chosen[4], chosen[5] }
      end
      return
    end
    for i = from, n - (5 - depth) do
      pick[depth] = i
      choose(i + 1, depth + 1)
    end
  end
  choose(1, 1)
  return best
end

local RANK_WORDS = {
  [2] = "Two", [3] = "Three", [4] = "Four", [5] = "Five", [6] = "Six", [7] = "Seven", [8] = "Eight",
  [9] = "Nine", [10] = "Ten", [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace",
}

function M.rankWord(rank)
  return RANK_WORDS[rank]
end

function M.rankPlural(rank)
  return rank == 6 and "Sixes" or RANK_WORDS[rank] .. "s"
end

--- A hand's name as a table would say it: "Pair of Kings", "Ace High".
function M.describe(value)
  local category = M.category(value)
  local rank = M.topRank(value)
  if category == M.HIGH_CARD then return RANK_WORDS[rank] .. " High" end
  if category == M.PAIR then return "Pair of " .. M.rankPlural(rank) end
  return M.NAMES[category]
end

-- ------------------------------------------------------------------ Jacks or Better

--- A five card hand as a video poker pay line, or nil when it pays nothing.
function M.jacksOrBetter(cards)
  local value, category = M.evaluate(cards)
  if category == M.ROYAL then return "royal" end
  if category == M.STRAIGHT_FLUSH then return "straightFlush" end
  if category == M.QUADS then return "quads" end
  if category == M.FULL_HOUSE then return "fullHouse" end
  if category == M.FLUSH then return "flush" end
  if category == M.STRAIGHT then return "straight" end
  if category == M.TRIPS then return "trips" end
  if category == M.TWO_PAIR then return "twoPair" end
  if category == M.PAIR and M.topRank(value) >= 11 then return "jacks" end
  return nil
end

--- Which of five cards make their hand: true at each position that counts, kickers false.
function M.scoring(cards)
  local _, category = M.evaluate(cards)
  local marks = {}
  local whole = category >= M.STRAIGHT and category ~= M.QUADS
  local counts = {}
  for i = 1, #cards do
    local rank = floor(cards[i] / 4)
    counts[rank] = (counts[rank] or 0) + 1
  end
  for i = 1, #cards do
    marks[i] = whole or counts[floor(cards[i] / 4)] >= 2
  end
  return marks
end

-- ------------------------------------------------------------------ 3 card poker

-- Three cards rank differently from five: a straight beats a flush, because it is the rarer hand
M.T_HIGH, M.T_PAIR, M.T_FLUSH, M.T_STRAIGHT, M.T_TRIPS, M.T_STRAIGHT_FLUSH = 1, 2, 3, 4, 5, 6
M.THREE_NAMES = { "High Card", "Pair", "Flush", "Straight", "Three of a Kind", "Straight Flush" }

local T_CATEGORY = 3375

--- Score three cards. Returns the score and its category. A-2-3 is the lowest straight and A-K-Q the highest.
function M.three(cards)
  local x, y, z = cards[1], cards[2], cards[3]
  local a, b, c = floor(x / 4) + 2, floor(y / 4) + 2, floor(z / 4) + 2
  if a < b then a, b = b, a end
  if b < c then b, c = c, b end
  if a < b then a, b = b, a end
  local flush = x % 4 == y % 4 and y % 4 == z % 4
  local high = nil
  if a == b + 1 and b == c + 1 then high = a end
  if a == 14 and b == 3 and c == 2 then high = 3 end

  local category
  if high and flush then
    category = M.T_STRAIGHT_FLUSH
  elseif a == c then
    category = M.T_TRIPS
  elseif high then
    category = M.T_STRAIGHT
  elseif flush then
    category = M.T_FLUSH
  elseif a == b or b == c then
    -- The pair first, then the odd card
    if b == c then a, c = b, a end
    category = M.T_PAIR
  else
    category = M.T_HIGH
  end
  if high then return category * T_CATEGORY + high * D3, category end
  return category * T_CATEGORY + a * D3 + b * D4 + c, category
end

function M.threeCategory(value)
  return floor(value / T_CATEGORY)
end

--- A 3 card hand's name: "Queen High", "Pair of Tens", "Straight".
function M.describeThree(value)
  local category = M.threeCategory(value)
  local rank = floor(value / D3) % 15
  if category == M.T_HIGH then return RANK_WORDS[rank] .. " High" end
  if category == M.T_PAIR then return "Pair of " .. M.rankPlural(rank) end
  return M.THREE_NAMES[category]
end

return M
