local floor = math.floor
local sort = table.sort

local M = {}

local BACC_VALUES = {
  A = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 0, J = 0, Q = 0, K = 0,
}

local HILO_VALUES = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 10, J = 11, Q = 12, K = 13, A = 14,
}

local POKER_RANKS = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 10, J = 11, Q = 12, K = 13, A = 14,
}

function M.baccaratCardValue(cardID)
  local value = tostring(cardID or ""):sub(1, 1)
  return BACC_VALUES[value] or 0
end

function M.baccaratHandTotal(hand)
  local total = 0
  for _, cardID in ipairs(hand or {}) do
    total = total + M.baccaratCardValue(cardID)
  end
  return total % 10
end

function M.hiloValue(cardID)
  local value = tostring(cardID or ""):sub(1, 1)
  return HILO_VALUES[value] or 0
end

function M.roundedPayout(betAmount, multiplier)
  return floor(((betAmount or 0) * (multiplier or 0)) + 0.5)
end

function M.pokerRank(cardID)
  local value = tostring(cardID or ""):sub(1, 1)
  return POKER_RANKS[value] or 0
end

function M.pokerSuit(cardID)
  return tostring(cardID or ""):sub(2)
end

function M.evaluateJacksOrBetter(hand)
  assert(type(hand) == "table" and #hand == 5, "Hand must have exactly 5 cards")

  local rankCounts = {}
  local suitCounts = {}
  local ranks = {}

  for _, cardID in ipairs(hand) do
    local rank = M.pokerRank(cardID)
    local suit = M.pokerSuit(cardID)
    rankCounts[rank] = (rankCounts[rank] or 0) + 1
    suitCounts[suit] = (suitCounts[suit] or 0) + 1
    ranks[#ranks + 1] = rank
  end

  sort(ranks)

  local isFlush = false
  for _, count in pairs(suitCounts) do
    if count == 5 then
      isFlush = true
      break
    end
  end

  local uniqueRanks = {}
  local seen = {}
  for _, rank in ipairs(ranks) do
    if not seen[rank] then
      uniqueRanks[#uniqueRanks + 1] = rank
      seen[rank] = true
    end
  end

  local isStraight = false
  if #uniqueRanks == 5 then
    if ranks[5] - ranks[1] == 4 then
      isStraight = true
    elseif ranks[1] == 2 and ranks[2] == 3 and ranks[3] == 4 and ranks[4] == 5 and ranks[5] == 14 then
      isStraight = true
    end
  end

  local isRoyal = ranks[1] == 10 and ranks[2] == 11 and ranks[3] == 12 and ranks[4] == 13 and ranks[5] == 14

  local pairCount = 0
  local trips = 0
  local quads = 0
  local pairRanks = {}

  for rank, count in pairs(rankCounts) do
    if count == 2 then
      pairCount = pairCount + 1
      pairRanks[#pairRanks + 1] = rank
    elseif count == 3 then
      trips = 1
    elseif count == 4 then
      quads = 1
    end
  end

  if isRoyal and isFlush then
    return "Royal Flush", 1
  end
  if isStraight and isFlush then
    return "Straight Flush", 2
  end
  if quads == 1 then
    return "Four of a Kind", 3
  end
  if trips == 1 and pairCount == 1 then
    return "Full House", 4
  end
  if isFlush then
    return "Flush", 5
  end
  if isStraight then
    return "Straight", 6
  end
  if trips == 1 then
    return "Three of a Kind", 7
  end
  if pairCount == 2 then
    return "Two Pair", 8
  end
  if pairCount == 1 and pairRanks[1] and pairRanks[1] >= 11 then
    return "Jacks or Better", 9
  end

  return "No Win", nil
end

return M
