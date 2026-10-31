-- roulette_rules.lua
-- European single-zero roulette. Pure: no screen, no sound, no money.
-- A wager is a table of spots: { [spotId] = tokens }. Every spot the table offers is in M.SPOTS, built once from
-- the layout below, so a bet that is not on that list cannot exist. The number is picked once, as the round opens,
-- and a spin needs no decision, so new() returns a finished round and the wheel only shows it.
--
-- The layout has 12 columns of 3 rows. Column c, row r holds 3 * (c - 1) + r, with row 1 nearest the player.

local M = {
  COLUMNS = 12,
  ROWS = 3,
  POCKETS = 37,
  RECENT_KEPT = 14,
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

--- Numbers a spot covers, as a set. nil for a spot that does not exist.
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

--- The biggest net result any one number can give this wager, never below zero.
function M.maxWin(wager)
  if type(wager) == "number" then return wager * 35 end -- the engine's per-token figure
  local best = 0
  for n = 0, 36 do
    best = math.max(best, M.netOn(wager, n))
  end
  return best
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

--- A round is decided the moment it opens. The events only show what already happened.
function M.new(wager, rng, keep, _)
  local recent = {}
  for i, n in ipairs(keep and keep.recent or {}) do recent[i] = n end
  local spots = M.copyWager(wager)
  local number = rng:below(M.POCKETS)
  local state = {
    spots = spots,
    stake = M.stakeOf(spots),
    number = number,
    win = M.netOn(spots, number),
    recent = recent,
    over = true,
  }
  return state, {
    { type = "spin", number = number, net = state.win },
    { type = "landed", number = number },
    { type = "payout", number = number },
  }
end

function M.actions()
  return {}
end

function M.act()
  return {}
end

function M.auto()
  return "none"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.stake
end

function M.net(state)
  return state.win
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

function M.result(state)
  local wins = M.winners(state.spots, state.number)
  local title = M.numberName(state.number)
  if state.win > 0 then
    local names = {}
    for i, id in ipairs(wins) do
      if i <= 4 then names[i] = M.describe(id) end
    end
    if #wins > 4 then names[#names + 1] = "and " .. (#wins - 4) .. " more" end
    return { kind = "win", title = title, detail = table.concat(names, ", ") }
  end
  if state.win == 0 then return { kind = "push", title = title, detail = "Your winners cover your losers" } end
  if #wins > 0 then return { kind = "lose", title = title, detail = #wins .. " winning spot" .. (#wins > 1 and "s" or "") .. ", not enough to cover the rest" } end
  return { kind = "lose", title = title, detail = "No bet on " .. state.number }
end

function M.finish(state, keep)
  local recent = { state.number }
  for _, n in ipairs(keep.recent or {}) do
    if #recent < M.RECENT_KEPT then recent[#recent + 1] = n end
  end
  keep.recent = recent
end

return M
