-- games/uno/cards.lua
-- The UNO deck and what a card is. A card is a two-letter string, so a state saves plainly and a card is easy to compare:
--   the colour r y g b, or w for a wild, then the kind: 0-9, S skip, R reverse, D draw two, W wild, F wild draw four.
-- 108 cards: in each colour one 0, two of each 1-9, two Skips, two Reverses and two Draw Twos, then four Wilds and four Wild Draw Fours.

local M = {}

M.COLORS = { "r", "y", "g", "b" }
M.COLOR_NAME = { r = "red", y = "yellow", g = "green", b = "blue", w = "wild" }
M.COLOR_WORD = { r = "RED", y = "YELLOW", g = "GREEN", b = "BLUE" }
M.KIND_NAME = { S = "Skip", R = "Reverse", D = "Draw Two", W = "Wild", F = "Wild Draw Four" }
-- What a card says in a corner, and on a small card
M.LABEL = { S = "SKIP", R = "REV", D = "+2", W = "WILD", F = "+4" }

local COLOR_ORDER = { r = 1, y = 2, g = 3, b = 4, w = 5 }
local KIND_ORDER = { ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  S = 10, R = 11, D = 12, W = 13, F = 14 }

--- A fresh deck in order: 108 cards.
function M.deck()
  local list = {}
  for _, c in ipairs(M.COLORS) do
    list[#list + 1] = c .. "0"
    for n = 1, 9 do
      list[#list + 1] = c .. n
      list[#list + 1] = c .. n
    end
    for _, k in ipairs({ "S", "R", "D" }) do
      list[#list + 1] = c .. k
      list[#list + 1] = c .. k
    end
  end
  for _ = 1, 4 do
    list[#list + 1] = "wW"
    list[#list + 1] = "wF"
  end
  return list
end

function M.color(card)
  return card:sub(1, 1)
end

function M.kind(card)
  return card:sub(2, 2)
end

function M.isWild(card)
  return card:sub(1, 1) == "w"
end

function M.isNumber(card)
  return tonumber(card:sub(2, 2)) ~= nil
end

--- Points a card is worth to whoever goes out: the face for a number, 20 for an action, 50 for a wild.
function M.points(card)
  local n = tonumber(card:sub(2, 2))
  if n then return n end
  if M.isWild(card) then return 50 end
  return 20
end

function M.handPoints(hand)
  local sum = 0
  for _, card in ipairs(hand) do sum = sum + M.points(card) end
  return sum
end

--- Whether a card may go on top: a wild always, otherwise the colour in play or the same number or symbol.
function M.playable(card, top, color)
  if M.isWild(card) then return true end
  if M.color(card) == color then return true end
  if top and not M.isWild(top) and M.kind(card) == M.kind(top) then return true end
  return false
end

--- "red 7", "blue Skip", "Wild Draw Four".
function M.name(card)
  if not card or card == "" then return "?" end
  if M.isWild(card) then return M.KIND_NAME[M.kind(card)] end
  local kind = M.kind(card)
  return M.COLOR_NAME[M.color(card)] .. " " .. (M.KIND_NAME[kind] or kind)
end

--- The short word on a card: "7", "SKIP", "+2", "WILD".
function M.label(card)
  local kind = M.kind(card)
  return M.LABEL[kind] or kind
end

function M.before(a, b)
  local ca, cb = COLOR_ORDER[M.color(a)] or 9, COLOR_ORDER[M.color(b)] or 9
  if ca ~= cb then return ca < cb end
  return (KIND_ORDER[M.kind(a)] or 99) < (KIND_ORDER[M.kind(b)] or 99)
end

--- A hand in order: by colour, then number, then symbol, the wilds last.
function M.sort(hand)
  table.sort(hand, M.before)
  return hand
end

--- How many of each colour a hand holds, wilds not counted.
function M.colorCounts(hand)
  local out = { r = 0, y = 0, g = 0, b = 0 }
  for _, card in ipairs(hand) do
    local c = M.color(card)
    if out[c] then out[c] = out[c] + 1 end
  end
  return out
end

--- The colour a hand holds most of, for a wild. Ties go to the higher points held, then the order r y g b.
function M.bestColor(hand)
  local counts = M.colorCounts(hand)
  local points = { r = 0, y = 0, g = 0, b = 0 }
  for _, card in ipairs(hand) do
    local c = M.color(card)
    if points[c] then points[c] = points[c] + M.points(card) end
  end
  local best, bestCount, bestPoints = "r", -1, -1
  for _, c in ipairs(M.COLORS) do
    if counts[c] > bestCount or (counts[c] == bestCount and points[c] > bestPoints) then
      best, bestCount, bestPoints = c, counts[c], points[c]
    end
  end
  return best
end

function M.isColor(value)
  return value == "r" or value == "y" or value == "g" or value == "b"
end

return M
