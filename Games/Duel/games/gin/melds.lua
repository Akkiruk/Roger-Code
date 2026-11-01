-- games/gin/melds.lua
-- Everything about what a gin hand is worth, with no game in it. Cards are deck.lua's numbers. Ace is low and only low: A-2-3 is a
-- run and Q-K-A is not. Aces count 1, faces 10.
--
-- A hand has few melds, so this looks at every way of laying them down rather than being clever. Tests/group_gin_test.lua proves it
-- against a second method on every small hand.

local deck = require("lib.casino.deck")

local M = {}

--- Rank with the ace low: 1 to 13.
function M.low(card)
  local rank = deck.rank(card)
  return rank == deck.ACE and 1 or rank
end

--- What a card counts as deadwood.
function M.value(card)
  return math.min(10, M.low(card))
end

local function cardAt(low, suit)
  return deck.card(low == 1 and deck.ACE or low, suit)
end

--- Hand order: by rank with the ace low, then suit.
local function before(a, b)
  local rankA, rankB = M.low(a), M.low(b)
  if rankA ~= rankB then return rankA < rankB end
  return a < b
end

--- A sorted copy.
function M.sorted(cards)
  local list = {}
  for i, card in ipairs(cards) do list[i] = card end
  table.sort(list, before)
  return list
end

function M.deadwood(cards)
  local total = 0
  for _, card in ipairs(cards) do total = total + M.value(card) end
  return total
end

--- Whether these cards are a set or a run by themselves.
function M.isMeld(cards)
  if #cards < 3 then return false end
  local list = M.sorted(cards)
  local sameRank, sameRun = true, true
  for i = 2, #list do
    if M.low(list[i]) ~= M.low(list[1]) then sameRank = false end
    if deck.suit(list[i]) ~= deck.suit(list[1]) or M.low(list[i]) ~= M.low(list[i - 1]) + 1 then sameRun = false end
  end
  return sameRun or (sameRank and #list <= 4)
end

--- Every meld the hand can make, cards overlapping or not.
local function candidates(hand)
  local have, list = {}, {}
  for _, card in ipairs(hand) do have[card] = true end
  for suit = 0, 3 do
    for first = 1, 11 do
      local run = {}
      local low = first
      while low <= 13 and have[cardAt(low, suit)] do
        run[#run + 1] = cardAt(low, suit)
        if #run >= 3 then
          local meld = {}
          for i, card in ipairs(run) do meld[i] = card end
          list[#list + 1] = meld
        end
        low = low + 1
      end
    end
  end
  for low = 1, 13 do
    local same = {}
    for suit = 0, 3 do
      if have[cardAt(low, suit)] then same[#same + 1] = cardAt(low, suit) end
    end
    if #same >= 3 then
      list[#list + 1] = same
      if #same == 4 then
        for skip = 1, 4 do
          local three = {}
          for i, card in ipairs(same) do
            if i ~= skip then three[#three + 1] = card end
          end
          list[#list + 1] = three
        end
      end
    end
  end
  return list
end

--- Call visit(melds, loose) for every way of laying down melds that do not share a card, laying nothing included. The lists are
-- reused between calls, so a visitor keeps a copy of what it wants.
local function walk(hand, visit)
  local cards = M.sorted(hand)
  local order = {}
  for i, card in ipairs(cards) do order[card] = i end
  -- Each meld is tried only at its first card in hand order, so no arrangement comes up twice
  local byFirst = {}
  for _, meld in ipairs(candidates(cards)) do
    local first = #cards + 1
    for _, card in ipairs(meld) do first = math.min(first, order[card]) end
    byFirst[first] = byFirst[first] or {}
    table.insert(byFirst[first], meld)
  end
  local used, melds, loose = {}, {}, {}
  local function step(index)
    while index <= #cards and used[index] do index = index + 1 end
    if index > #cards then
      visit(melds, loose)
      return
    end
    for _, meld in ipairs(byFirst[index] or {}) do
      local free = true
      for _, card in ipairs(meld) do
        if used[order[card]] then free = false end
      end
      if free then
        for _, card in ipairs(meld) do used[order[card]] = true end
        melds[#melds + 1] = meld
        step(index + 1)
        melds[#melds] = nil
        for _, card in ipairs(meld) do used[order[card]] = nil end
      end
    end
    loose[#loose + 1] = cards[index]
    step(index + 1)
    loose[#loose] = nil
  end
  step(1)
end

local function copyList(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

local function copyMelds(melds)
  local out = {}
  for i, meld in ipairs(melds) do out[i] = M.sorted(meld) end
  return out
end

--- Every arrangement with the least deadwood: a list of { melds, loose, deadwood }.
function M.allBest(hand)
  local best, list = math.huge, {}
  walk(hand, function(melds, loose)
    local total = M.deadwood(loose)
    if total < best then best, list = total, {} end
    if total == best then
      list[#list + 1] = { melds = copyMelds(melds), loose = M.sorted(loose), deadwood = total }
    end
  end)
  return list
end

--- The arrangement with the least deadwood. A tie goes to the fewest melds, then to the first found, so it is always the same one.
function M.best(hand)
  local found = nil
  for _, option in ipairs(M.allBest(hand)) do
    if not found or #option.melds < #found.melds then found = option end
  end
  return found
end

--- What these loose cards can lay off on another hand's melds. Runs come first and until nothing more fits, because a laid card can
-- open the way for the next and a set never can. A card that fits both is always at least as good on the run.
-- @return laid, rest
function M.layoffs(melds, loose)
  local runs, sets = {}, {}
  for _, meld in ipairs(melds) do
    local list = M.sorted(meld)
    if M.low(list[1]) == M.low(list[#list]) then
      if #list == 3 then sets[M.low(list[1])] = true end
    else
      runs[#runs + 1] = { suit = deck.suit(list[1]), first = M.low(list[1]), last = M.low(list[#list]) }
    end
  end
  local laid, rest = {}, M.sorted(loose)
  local moved = true
  while moved do
    moved = false
    for i = #rest, 1, -1 do
      local card, fits = rest[i], false
      for _, run in ipairs(runs) do
        if not fits and deck.suit(card) == run.suit then
          if M.low(card) == run.first - 1 then
            run.first, fits = run.first - 1, true
          elseif M.low(card) == run.last + 1 then
            run.last, fits = run.last + 1, true
          end
        end
      end
      if fits then
        laid[#laid + 1] = table.remove(rest, i)
        moved = true
      end
    end
  end
  for i = #rest, 1, -1 do
    if sets[M.low(rest[i])] then
      sets[M.low(rest[i])] = nil
      laid[#laid + 1] = table.remove(rest, i)
    end
  end
  return M.sorted(laid), rest
end

--- The defender's best answer to a knock, breaking their own melds if laying off pays better.
-- @return { melds, laid, loose, deadwood }
function M.defend(hand, knockMelds)
  local found = nil
  walk(hand, function(melds, loose)
    local laid, rest = M.layoffs(knockMelds, loose)
    local total = M.deadwood(rest)
    if not found or total < found.deadwood or (total == found.deadwood and #melds > #found.melds) then
      found = { melds = copyMelds(melds), laid = laid, loose = copyList(rest), deadwood = total }
    end
  end)
  return found
end

--- The card that leaves the least deadwood, leaving locked in the hand. A tie throws the higher card.
-- @return card, deadwood left
function M.bestThrow(hand, locked)
  local bestCard, bestLeft = nil, math.huge
  -- A card in no meld at all is deadwood however the hand is laid, so throwing it only takes its value off. This runs every turn
  local whole, melded = M.best(hand).deadwood, {}
  for _, meld in ipairs(candidates(hand)) do
    for _, card in ipairs(meld) do melded[card] = true end
  end
  for i, card in ipairs(hand) do
    if card ~= locked then
      local left = whole - M.value(card)
      if melded[card] then
        local rest = copyList(hand)
        table.remove(rest, i)
        left = M.best(rest).deadwood
      end
      local better = left < bestLeft
      if left == bestLeft then
        local value, held = M.value(card), M.value(bestCard)
        better = value > held or (value == held and card > bestCard)
      end
      if better then bestCard, bestLeft = card, left end
    end
  end
  return bestCard, bestLeft
end

--- A knock laid out for the knocker. Of the arrangements with the least deadwood, the one that leaves the defender worst off.
-- @return the knocker's { melds, laid, loose, deadwood }, the defender's the same
function M.showdown(knockHand, defendHand)
  local bestKnock, bestDefend = nil, nil
  for _, option in ipairs(M.allBest(knockHand)) do
    local answer = option.deadwood == 0 and M.defend(defendHand, {}) or M.defend(defendHand, option.melds)
    if not bestDefend or answer.deadwood > bestDefend.deadwood then bestKnock, bestDefend = option, answer end
  end
  bestKnock.laid = {}
  return bestKnock, bestDefend
end

return M
