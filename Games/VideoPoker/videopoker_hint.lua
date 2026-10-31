-- videopoker_hint.lua
-- The hold the HINT button advises: the one of the 32 with the best expected return. Pure, and it reads only the five cards.
-- Trying every draw would mean up to 1.5 million hands for one hold, far too much for a table that must keep its frames,
-- so each hold is priced by simple counting instead, and all 32 take about 0.2 ms on Lua 5.1, against a frame of 100 ms:
--   royals, straight flushes, flushes and straights are counted exactly, from the cards still out;
--   pairs and better come from the rows below, which depend on the shape of the hold and on what it throws away.
-- The rows were fitted to this paytable's exact values: `hint-oracle.mjs fit` in craftos-agent's tools/casinotest prints them.
-- That tool also plays this against the exact best hold on every deal, so a change to the paytable fails there.

local deck = require("lib.casino.deck")

local M = {}

local HIGH = 11               -- Jacks and up pay as a pair
local ROYAL_WINDOW = 10
local HAND_SIZE = 5
local WAYS = { [0] = 1, 47, 1081, 16215, 178365, 1533939 } -- ways to draw 0 to 5 cards from the 47 left

-- What pairs and better return for each token, per hold: the base, then what each discarded card takes off, if it is
-- a card of a held high rank, a card of a held low rank, or another high card.
local DRAWS = {               -- no two held cards share a rank: by how many are held, then how many of those are high
  [0] = { [0] = { 0.3337, 0, 0, -0.0171 } },
  [1] = { [0] = { 0.2888, 0, -0.0551, -0.0111 }, { 0.4459, -0.109, 0, -0.0111 } },
  [2] = { [0] = { 0.2074, 0, -0.0374, -0.0065 }, { 0.335, -0.0807, -0.031, -0.0065 }, { 0.4625, -0.0743, 0, -0.0065 } },
  [3] = {
    [0] = { 0.097, 0, -0.0163, -0.0027 }, { 0.197, -0.0498, -0.0136, -0.0027 },
    { 0.2969, -0.0471, -0.0109, -0.0027 }, { 0.3968, -0.0444, 0, -0.0027 },
  },
  [4] = {
    [0] = { 0, 0, 0, 0 }, { 0.0638, -0.0213, 0, 0 }, { 0.1277, -0.0213, 0, 0 }, { 0.1915, -0.0213, 0, 0 }, { 0.2553, -0.0213, 0, 0 },
  },
}
local NOTHING_MORE = { 0, 0, 0, 0 } -- five cards held: nothing is drawn
local LOW_PAIR = { 0.8248, 0, -0.2405, 0 }
local HIGH_PAIR = { 1.5372, -0.1907, 0, 0 }
local TWO_PAIR = { 2.5957, -0.1489, -0.1489, 0 }
local TRIPS = { 4.3029, -0.9199, -0.9199, 0 }
local FULL_HOUSE = { 9, 0, 0, 0 }
local QUADS = { 25, 0, 0, 0 }

local WINDOWS = { { 14, 2, 3, 4, 5 } } -- the ranks of each straight, the wheel first and the royal last
for high = 6, 14 do WINDOWS[high - 4] = { high - 4, high - 3, high - 2, high - 1, high } end

-- Every hold, as the positions kept
local HOLDS = {}
for mask = 0, 31 do
  local slots = {}
  for i = 1, HAND_SIZE do
    if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then slots[#slots + 1] = i end
  end
  HOLDS[#HOLDS + 1] = slots
end

local function choose(n, k)
  if k > n then return 0 end
  local ways = 1
  for i = 1, k do ways = ways * (n - i + 1) / i end
  return ways
end

--- The row for a hold with a pair or better in it, or nil for one that keeps a useless kicker as well.
local function madeRow(count, pairs, trips, quads, highPair)
  if quads == 1 then return count == 4 and QUADS or nil end
  if trips == 1 then
    if count == 3 then return TRIPS end
    return (count == 5 and pairs == 1) and FULL_HOUSE or nil
  end
  if pairs == 2 then return count == 4 and TWO_PAIR or nil end
  if count ~= 2 then return nil end
  return highPair and HIGH_PAIR or LOW_PAIR
end

--- Every held rank is in this window, and this is how many ways the draw can fill the rest of it.
local function straightWays(window, held, count, left)
  local inside, ways = 0, 1
  for i = 1, HAND_SIZE do
    local rank = window[i]
    if held[rank] then inside = inside + 1 else ways = ways * left[rank] end
  end
  return inside == count and ways or 0
end

--- Whether a window's missing cards are all still out in this suit.
local function suitedOut(window, held, count, suit, dealt)
  local inside = 0
  for i = 1, HAND_SIZE do
    local rank = window[i]
    if held[rank] then
      inside = inside + 1
    elseif dealt[deck.card(rank, suit)] then
      return false
    end
  end
  return inside == count
end

--- What a hold with no two ranks the same can make beyond pairs: the total paid over all its draws.
local function paysDrawing(count, held, left, dealt, inSuit, suits, pay)
  local straights, flushes, straightFlushes, royals = 0, 0, 0, 0
  for w = 1, #WINDOWS do straights = straights + straightWays(WINDOWS[w], held, count, left) end
  for _, suit in ipairs(suits) do
    flushes = flushes + choose(13 - inSuit[suit], HAND_SIZE - count)
    for w = 1, #WINDOWS do
      if suitedOut(WINDOWS[w], held, count, suit, dealt) then
        if w == ROYAL_WINDOW then royals = royals + 1 else straightFlushes = straightFlushes + 1 end
      end
    end
  end
  local suited = royals + straightFlushes
  return royals * pay.royal + straightFlushes * pay.straightFlush + (flushes - suited) * pay.flush + (straights - suited) * pay.straight
end

local ALL_SUITS = { deck.CLUBS, deck.DIAMONDS, deck.HEARTS, deck.SPADES }

--- What one hold is worth. Returns nil for a hold no sensible player would make.
local function worth(hand, slots, left, dealt, inSuit, pay)
  local count = #slots
  local held = {}
  local suit, oneSuit = nil, true
  local high, highPair, pairs, trips, quads = 0, false, 0, 0, 0
  for i = 1, count do
    local card = hand[slots[i]]
    local rank = deck.rank(card)
    local copies = (held[rank] or 0) + 1
    held[rank] = copies
    if copies == 1 and rank >= HIGH then high = high + 1 end
    if copies == 2 then
      pairs = pairs + 1
      if rank >= HIGH then highPair = true end
    elseif copies == 3 then
      pairs, trips = pairs - 1, trips + 1
    elseif copies == 4 then
      trips, quads = trips - 1, quads + 1
    end
    suit = suit or deck.suit(card)
    if deck.suit(card) ~= suit then oneSuit = false end
  end

  local plain = pairs + trips + quads == 0
  local row = plain and (count == HAND_SIZE and NOTHING_MORE or DRAWS[count][high]) or madeRow(count, pairs, trips, quads, highPair)
  if not row then return nil end
  local value = row[1]
  local kept = {}
  for i = 1, count do kept[slots[i]] = true end
  for i = 1, HAND_SIZE do
    if not kept[i] then
      local rank = deck.rank(hand[i])
      if held[rank] then
        value = value + (rank >= HIGH and row[2] or row[3])
      elseif rank >= HIGH then
        value = value + row[4]
      end
    end
  end
  if plain then
    local suits = count == 0 and ALL_SUITS or (oneSuit and { suit } or {})
    value = value + paysDrawing(count, held, left, dealt, inSuit, suits, pay) / WAYS[HAND_SIZE - count]
  end
  return value
end

--- The best hold for five cards. pay maps a pay line's id to its multiple. Returns true or false for each position.
function M.best(hand, pay)
  local left, dealt, inSuit = {}, {}, { [0] = 0, 0, 0, 0 }
  for rank = 2, 14 do left[rank] = 4 end
  for i = 1, HAND_SIZE do
    local card = hand[i]
    left[deck.rank(card)] = left[deck.rank(card)] - 1
    dealt[card] = true
    inSuit[deck.suit(card)] = inSuit[deck.suit(card)] + 1
  end

  local best, bestValue = HOLDS[1], -1
  for _, slots in ipairs(HOLDS) do
    local value = worth(hand, slots, left, dealt, inSuit, pay)
    if value and value > bestValue then best, bestValue = slots, value end
  end
  local keep = {}
  for i = 1, HAND_SIZE do keep[i] = false end
  for _, slot in ipairs(best) do keep[slot] = true end
  return keep
end

return M
