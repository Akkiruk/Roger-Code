-- games/roulette/wheel.lua
-- The wheel and the layout: the same 37 pockets and the same bets as Games/Roulette, kept here because a Big Table only ships its own
-- folder. Pure tables and sums. Tests/group_roulette_test.lua compares every spot and every payout with roulette_rules, so the two
-- cannot drift.
--
-- A wager is a table of spots: { [spotId] = tokens }. The layout has 12 columns of 3 rows. Column c, row r holds 3 * (c - 1) + r,
-- with row 1 nearest the player.

local M = {
  COLUMNS = 12,
  ROWS = 3,
  POCKETS = 37,
  RECENT_KEPT = 14,
  MODES = { "straight", "split", "street", "corner", "line" }, -- the inside bets. A tap on the layout means one of these
}

-- The order of the pockets round a European wheel, clockwise from zero
M.WHEEL = { 0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26 }

-- Every kind of bet, in the order the help lists them. pay is net profit per token.
M.KINDS = {
  { id = "straight", label = "Straight", pay = 35, covers = 1, how = "one number, 0 included" },
  { id = "split", label = "Split", pay = 17, covers = 2, how = "two numbers side by side, or 0 with 1, 2 or 3" },
  { id = "street", label = "Street", pay = 11, covers = 3, how = "one column of three, or the trios 0-1-2 and 0-2-3" },
  { id = "corner", label = "Corner", pay = 8, covers = 4, how = "four numbers that meet, or the first four 0-1-2-3" },
  { id = "line", label = "Line", pay = 5, covers = 6, how = "two columns side by side" },
  { id = "column", label = "Column", pay = 2, covers = 12, how = "a whole row of the layout, marked 2:1" },
  { id = "dozen", label = "Dozen", pay = 2, covers = 12, how = "1-12, 13-24 or 25-36" },
  { id = "red", label = "Red", pay = 1, covers = 18, how = "the 18 red numbers" },
  { id = "black", label = "Black", pay = 1, covers = 18, how = "the 18 black numbers" },
  { id = "odd", label = "Odd", pay = 1, covers = 18, how = "the 18 odd numbers" },
  { id = "even", label = "Even", pay = 1, covers = 18, how = "the 18 even numbers, not 0" },
  { id = "low", label = "Low", pay = 1, covers = 18, how = "1 to 18" },
  { id = "high", label = "High", pay = 1, covers = 18, how = "19 to 36" },
}

local PAY = {}
for _, kind in ipairs(M.KINDS) do PAY[kind.id] = kind.pay end

local REDS = { 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }
local IS_RED = {}
for _, n in ipairs(REDS) do IS_RED[n] = true end

--- "red", "black", or "green" for zero.
function M.color(n)
  if n == 0 then return "green" end
  return IS_RED[n] and "red" or "black"
end

local SPOTS, BY_ID, order = {}, {}, 0

local function addSpot(id, kind, label, nums)
  local covered = {}
  for _, n in ipairs(nums) do covered[n] = true end
  order = order + 1
  local spot = { id = id, kind = kind, label = label, nums = nums, covered = covered, pay = PAY[kind], order = order }
  SPOTS[#SPOTS + 1] = spot
  BY_ID[id] = spot
end

--- A spot named by the numbers it covers, lowest first: "split:14-17".
local function inside(kind, nums)
  table.sort(nums)
  local name = table.concat(nums, "-")
  return kind .. ":" .. name, name
end

local function addInside(kind, nums)
  local id, name = inside(kind, nums)
  addSpot(id, kind, name, nums)
end

local function buildSpots()
  for n = 0, 36 do addSpot("straight:" .. n, "straight", tostring(n), { n }) end

  for n = 1, 36 do
    if n % 3 ~= 0 then addInside("split", { n, n + 1 }) end
    if n <= 33 then addInside("split", { n, n + 3 }) end
  end
  for n = 1, 3 do addInside("split", { 0, n }) end

  for column = 1, 12 do
    local first = 3 * (column - 1) + 1
    addInside("street", { first, first + 1, first + 2 })
  end
  addInside("street", { 0, 1, 2 })
  addInside("street", { 0, 2, 3 })

  for column = 1, 11 do
    local first = 3 * (column - 1) + 1
    addInside("corner", { first, first + 1, first + 3, first + 4 })
    addInside("corner", { first + 1, first + 2, first + 4, first + 5 })
  end
  addInside("corner", { 0, 1, 2, 3 })

  for column = 1, 11 do
    local first = 3 * (column - 1) + 1
    addInside("line", { first, first + 1, first + 2, first + 3, first + 4, first + 5 })
  end

  for row = 1, 3 do
    local nums = {}
    for column = 1, 12 do nums[column] = 3 * (column - 1) + row end
    addSpot("column:" .. row, "column", "Column " .. row, nums)
  end
  for dozen = 1, 3 do
    local nums = {}
    for i = 1, 12 do nums[i] = 12 * (dozen - 1) + i end
    addSpot("dozen:" .. dozen, "dozen", ({ "1st 12", "2nd 12", "3rd 12" })[dozen], nums)
  end

  local reds, blacks, odds, evens, lows, highs = {}, {}, {}, {}, {}, {}
  for n = 1, 36 do
    local colorList = IS_RED[n] and reds or blacks
    local parityList = n % 2 == 1 and odds or evens
    local sideList = n <= 18 and lows or highs
    colorList[#colorList + 1] = n
    parityList[#parityList + 1] = n
    sideList[#sideList + 1] = n
  end
  addSpot("red", "red", "Red", reds)
  addSpot("black", "black", "Black", blacks)
  addSpot("odd", "odd", "Odd", odds)
  addSpot("even", "even", "Even", evens)
  addSpot("low", "low", "1-18", lows)
  addSpot("high", "high", "19-36", highs)
end

buildSpots()

M.SPOTS = SPOTS
M.spot = function(id) return BY_ID[id] end

--- Whether a spot covers a number. False for a spot that does not exist.
function M.covers(id, n)
  local spot = BY_ID[id]
  return spot ~= nil and spot.covered[n] == true
end

--- The id of the inside bet of a kind that covers exactly these numbers.
function M.insideId(kind, nums)
  local copy = {}
  for i, n in ipairs(nums) do copy[i] = n end
  return (inside(kind, copy))
end

--- The total on a wager.
function M.stakeOf(wager)
  local total = 0
  for _, amount in pairs(wager) do total = total + amount end
  return total
end

--- The net result of a wager if the ball lands on n.
function M.netOn(wager, n)
  local total = 0
  for id, amount in pairs(wager) do
    local spot = BY_ID[id]
    if spot.covered[n] then
      total = total + amount * spot.pay
    else
      total = total - amount
    end
  end
  return total
end

--- The spots of a wager that win on n, in layout order.
function M.winners(wager, n)
  local list = {}
  for id in pairs(wager) do
    if BY_ID[id].covered[n] then list[#list + 1] = id end
  end
  table.sort(list, function(a, b) return BY_ID[a].order < BY_ID[b].order end)
  return list
end

function M.copyWager(wager)
  local copy = {}
  for id, amount in pairs(wager) do copy[id] = amount end
  return copy
end

--- "17 BLACK", or "0 GREEN".
function M.numberName(n)
  return n .. " " .. M.color(n):upper()
end

--- A spot in words, for the result line: "Split 14-17".
function M.describe(id)
  local spot = BY_ID[id]
  if spot.kind == "column" or spot.kind == "dozen" or #spot.nums == 18 then return spot.label end
  return spot.kind:sub(1, 1):upper() .. spot.kind:sub(2) .. " " .. spot.label
end

return M
