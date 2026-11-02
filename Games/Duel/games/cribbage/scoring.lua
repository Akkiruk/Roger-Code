-- games/cribbage/scoring.lua
-- What cards are worth in cribbage, on its own so a test can pin it down. Pure: cards in, points and a breakdown out.
-- A breakdown is a list of { label, points }, in the order a player would count it aloud. Aces are low and always worth 1: a run can
-- start A-2-3 and Q-K-A is no run.

local deck = require("lib.casino.deck")

local M = {}

M.FIFTEEN = 15
M.THIRTY_ONE = 31

local KINDS = { [3] = "Three", [4] = "Four" }

--- 1 for an ace up to 13 for a king.
function M.low(card)
  local rank = deck.rank(card)
  return rank == deck.ACE and 1 or rank
end

--- What a card adds to a fifteen or a count.
function M.value(card)
  return math.min(10, M.low(card))
end

local function rankWord(low)
  if low == 1 then return "As" end
  if low > 10 then return ({ "Js", "Qs", "Ks" })[low - 10] end
  return low .. "s"
end

--- How many subsets of the cards add up to fifteen.
local function fifteens(cards)
  local found = 0
  local function step(index, total)
    if total == M.FIFTEEN then found = found + 1 end
    for at = index, #cards do
      local sum = total + M.value(cards[at])
      if sum <= M.FIFTEEN then step(at + 1, sum) end
    end
  end
  step(1, 0)
  return found
end

local function addRuns(items, counts)
  local low = 1
  while low <= 13 do
    local stop, ways = low, 1
    while (counts[stop] or 0) > 0 do
      ways = ways * counts[stop]
      stop = stop + 1
    end
    local length = stop - low
    if length >= 3 then
      local label = "Run of " .. length
      if ways > 1 then label = label .. " x" .. ways end
      items[#items + 1] = { label = label, points = length * ways }
    end
    low = math.max(stop, low + 1)
  end
end

local function addPairs(items, counts)
  for low = 1, 13 do
    local count = counts[low] or 0
    if count == 2 then
      items[#items + 1] = { label = "Pair of " .. rankWord(low), points = 2 }
    elseif count > 2 then
      items[#items + 1] = { label = KINDS[count] .. " " .. rankWord(low), points = count * (count - 1) }
    end
  end
end

local function addFlush(items, hand, starter, isCrib)
  local suit = deck.suit(hand[1])
  for _, card in ipairs(hand) do
    if deck.suit(card) ~= suit then return end
  end
  if starter and deck.suit(starter) == suit then
    items[#items + 1] = { label = "Flush of 5", points = 5 }
  elseif not isCrib then
    items[#items + 1] = { label = "Flush of " .. #hand, points = #hand }
  end
end

local function addNobs(items, hand, starter)
  if not starter then return end
  for _, card in ipairs(hand) do
    if deck.rank(card) == 11 and deck.suit(card) == deck.suit(starter) then
      items[#items + 1] = { label = "Nobs", points = 1 }
    end
  end
end

--- A hand at the show. The starter may be nil, for weighing a hand before it is cut. Returns points, breakdown.
function M.hand(hand, starter, isCrib)
  local all, counts = {}, {}
  for index, card in ipairs(hand) do all[index] = card end
  if starter then all[#all + 1] = starter end
  for _, card in ipairs(all) do
    local low = M.low(card)
    counts[low] = (counts[low] or 0) + 1
  end
  local items = {}
  local count = fifteens(all)
  if count == 1 then
    items[1] = { label = "Fifteen", points = 2 }
  elseif count > 1 then
    items[1] = { label = "Fifteens x" .. count, points = count * 2 }
  end
  addPairs(items, counts)
  addRuns(items, counts)
  addFlush(items, hand, starter, isCrib)
  addNobs(items, hand, starter)
  local total = 0
  for _, item in ipairs(items) do total = total + item.points end
  return total, items
end

--- The longest run the last cards of a count end on, in any order, or nil.
local function pegRun(cards)
  for length = #cards, 3, -1 do
    local seen, lowest, highest, clean = {}, 99, 0, true
    for index = #cards - length + 1, #cards do
      local low = M.low(cards[index])
      if seen[low] then clean = false end
      seen[low] = true
      lowest, highest = math.min(lowest, low), math.max(highest, low)
    end
    if clean and highest - lowest + 1 == length then return length end
  end
  return nil
end

--- How many cards at the end of a count share a rank.
local function pegPair(cards)
  local last = #cards
  local count = 1
  while last - count >= 1 and M.low(cards[last - count]) == M.low(cards[last]) do count = count + 1 end
  return count
end

--- What the last card of a count scores. cards are the count so far in the order played, that card last. Returns points, breakdown.
function M.peg(cards)
  local total, items = 0, {}
  for _, card in ipairs(cards) do total = total + M.value(card) end
  if total == M.FIFTEEN then items[#items + 1] = { label = "Fifteen", points = 2 } end
  if total == M.THIRTY_ONE then items[#items + 1] = { label = "Thirty-one", points = 2 } end
  local same = pegPair(cards)
  if same == 2 then
    items[#items + 1] = { label = "Pair", points = 2 }
  elseif same > 2 then
    items[#items + 1] = { label = same == 3 and "Three of a kind" or "Four of a kind", points = same * (same - 1) }
  end
  local run = pegRun(cards)
  if run then items[#items + 1] = { label = "Run of " .. run, points = run } end
  local points = 0
  for _, item in ipairs(items) do points = points + item.points end
  return points, items
end

return M
