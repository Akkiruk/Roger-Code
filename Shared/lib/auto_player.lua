-- auto_player.lua
-- Bot decision engine for automated blackjack testing.
-- Supports threshold-based strategies and a basic strategy lookup.

local cards = require("lib.cards")
local m_random = math.random

-----------------------------------------------------
-- Named strategies (threshold-based, for stress testing)
-----------------------------------------------------
local STRATEGIES = {
  { name = "conservative", standAt = 17 },
  { name = "moderate",     standAt = 16 },
  { name = "aggressive",   standAt = 18 },
  { name = "risky",        standAt = 15 },
  { name = "reckless",     standAt = 14 },
}

-----------------------------------------------------
-- Simplified basic strategy lookup
-- Returns "hit", "stand", "double", "split", or "surrender"
-----------------------------------------------------
local function basicStrategy(handTotal, isSoft, cardCount, dealerUp, canDouble, canSplit, pairValue)
  -- Split decisions
  if canSplit and pairValue then
    if pairValue == 11 or pairValue == 8 then return "split" end
    if pairValue == 10 or pairValue == 5 then
      -- never split tens or fives, fall through
    elseif pairValue == 4 then
      if dealerUp >= 5 and dealerUp <= 6 then return "split" end
    elseif pairValue == 9 then
      if dealerUp ~= 7 and dealerUp ~= 10 and dealerUp ~= 11 then return "split" end
    else
      if dealerUp >= 2 and dealerUp <= 7 then return "split" end
    end
  end

  -- Soft hand strategy
  if isSoft then
    if handTotal >= 19 then return "stand" end
    if handTotal == 18 then
      if canDouble and cardCount == 2 and dealerUp >= 3 and dealerUp <= 6 then return "double" end
      if dealerUp >= 9 then return "hit" end
      return "stand"
    end
    if handTotal == 17 and canDouble and cardCount == 2 and dealerUp >= 3 and dealerUp <= 6 then
      return "double"
    end
    if handTotal >= 15 and handTotal <= 16 and canDouble and cardCount == 2
       and dealerUp >= 4 and dealerUp <= 6 then
      return "double"
    end
    if handTotal >= 13 and handTotal <= 14 and canDouble and cardCount == 2
       and dealerUp >= 5 and dealerUp <= 6 then
      return "double"
    end
    return "hit"
  end

  -- Hard hand strategy
  if handTotal >= 17 then return "stand" end
  if handTotal >= 13 and handTotal <= 16 then
    if dealerUp >= 2 and dealerUp <= 6 then return "stand" end
    return "hit"
  end
  if handTotal == 12 then
    if dealerUp >= 4 and dealerUp <= 6 then return "stand" end
    return "hit"
  end
  if handTotal == 11 then
    if canDouble and cardCount == 2 then return "double" end
    return "hit"
  end
  if handTotal == 10 then
    if canDouble and cardCount == 2 and dealerUp <= 9 then return "double" end
    return "hit"
  end
  if handTotal == 9 then
    if canDouble and cardCount == 2 and dealerUp >= 3 and dealerUp <= 6 then return "double" end
    return "hit"
  end
  return "hit"
end

-----------------------------------------------------
-- Main decision function
-----------------------------------------------------

--- Decide the best action for the current hand state.
-- @param hand          table   Array of card ID strings
-- @param dealerUpCard  string  Dealer's visible card ID
-- @param canDouble     boolean Can the player double down?
-- @param canSplit      boolean Can the player split?
-- @param strategyIdx   number  1-5 = threshold, 6 = basic strategy
-- @return string  "hit", "stand", "double", or "split"
local function decide(hand, dealerUpCard, canDouble, canSplit, strategyIdx)
  local handTotal, isSoft = cards.blackjackValue(hand)
  local cardCount = #hand

  -- Basic strategy mode (index 6 or 0)
  if strategyIdx == 6 or strategyIdx == 0 then
    local dealerVal = cards.FACE_VALUES[dealerUpCard:sub(1, 1)]
    local pairValue = nil
    if canSplit and cardCount == 2 then
      local v1 = cards.FACE_VALUES[hand[1]:sub(1, 1)]
      local v2 = cards.FACE_VALUES[hand[2]:sub(1, 1)]
      if v1 == v2 then pairValue = v1 end
    end
    local action = basicStrategy(handTotal, isSoft, cardCount, dealerVal, canDouble, canSplit, pairValue)
    if action == "double" and not canDouble then return "stand" end
    if action == "split" and not canSplit then
      return basicStrategy(handTotal, isSoft, cardCount, dealerVal, canDouble, false, nil)
    end
    return action
  end

  -- Threshold-based strategies (1-5)
  local strategy = STRATEGIES[strategyIdx] or STRATEGIES[1]
  local threshold = strategy.standAt

  if handTotal < threshold then
    return "hit"
  elseif canDouble and cardCount == 2 and handTotal >= 9 and handTotal <= 11 then
    return "double"
  elseif canSplit and cardCount == 2 then
    local v1 = cards.FACE_VALUES[hand[1]:sub(1, 1)]
    local v2 = cards.FACE_VALUES[hand[2]:sub(1, 1)]
    if v1 == v2 and (v1 == 11 or v1 == 8) then return "split" end
    return "stand"
  else
    return "stand"
  end
end

--- Pick a random threshold-based strategy index (1-5).
local function randomStrategy()
  return m_random(1, #STRATEGIES)
end

return {
  decide          = decide,
  randomStrategy  = randomStrategy,
  basicStrategy   = basicStrategy,
  STRATEGIES      = STRATEGIES,
}
