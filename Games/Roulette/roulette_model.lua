local cfg = require("roulette_config")

local floor = math.floor
local insert = table.insert
local max = math.max

local WHEEL_ORDER = cfg.WHEEL_ORDER
local WHEEL_INDEX = {}
local RED_SET = {}

local function cloneNumberList(numbers)
  local out = {}
  for i, value in ipairs(numbers) do
    out[i] = value
  end
  return out
end

local function buildLookup(numbers)
  local lookup = {}
  for _, value in ipairs(numbers) do
    lookup[value] = true
  end
  return lookup
end

for index, value in ipairs(WHEEL_ORDER) do
  WHEEL_INDEX[value] = index
end

for _, value in ipairs(cfg.RED_NUMBERS) do
  RED_SET[value] = true
end

local function isRed(number)
  return RED_SET[number] == true
end

local function isBlack(number)
  return number > 0 and not isRed(number)
end

local function getNumberColor(number)
  if number == 0 then
    return colors.lime
  end
  if isRed(number) then
    return colors.red
  end
  return colors.black
end

local function getNumberTextColor(number)
  if number == 0 then
    return colors.black
  end
  if isRed(number) then
    return colors.white
  end
  return colors.lightGray
end

local function getColorName(number)
  if number == 0 then
    return "GREEN"
  end
  if isRed(number) then
    return "RED"
  end
  return "BLACK"
end

local function getNumberAt(row, column)
  return ((row - 1) * 3) + column
end

local function getRowNumbers(row)
  return {
    getNumberAt(row, 1),
    getNumberAt(row, 2),
    getNumberAt(row, 3),
  }
end

local function getColumnNumbers(column)
  local numbers = {}
  local row = 1
  while row <= 12 do
    insert(numbers, getNumberAt(row, column))
    row = row + 1
  end
  return numbers
end

local function getDozenNumbers(dozenIndex)
  local startValue = ((dozenIndex - 1) * 12) + 1
  local numbers = {}
  local value = startValue
  while value <= startValue + 11 do
    insert(numbers, value)
    value = value + 1
  end
  return numbers
end

local function makeBetDefinition(key, kind, label, payout, numbers, accentColor)
  assert(type(key) == "string" and key ~= "", "bet key is required")
  assert(type(kind) == "string" and kind ~= "", "bet kind is required")
  assert(type(label) == "string" and label ~= "", "bet label is required")
  assert(type(payout) == "number" and payout >= 0, "bet payout must be a number")
  assert(type(numbers) == "table" and #numbers > 0, "bet numbers are required")

  local copy = {
    key = key,
    kind = kind,
    label = label,
    payout = payout,
    numbers = cloneNumberList(numbers),
    accentColor = accentColor or colors.yellow,
  }
  copy.lookup = buildLookup(copy.numbers)
  return copy
end

local function cloneBet(bet)
  local copy = makeBetDefinition(
    bet.key,
    bet.kind,
    bet.label,
    bet.payout,
    bet.numbers,
    bet.accentColor
  )
  copy.stake = bet.stake or 0
  return copy
end

local function cloneBetList(bets)
  local copy = {}
  for _, bet in ipairs(bets) do
    insert(copy, cloneBet(bet))
  end
  return copy
end

local function findBetIndex(bets, key)
  for index, bet in ipairs(bets) do
    if bet.key == key then
      return index
    end
  end
  return nil
end

local function addStake(bets, region, amount)
  assert(type(bets) == "table", "bets must be a table")
  assert(type(region) == "table", "region must be a table")
  assert(type(amount) == "number" and amount > 0, "amount must be positive")

  local betIndex = findBetIndex(bets, region.key)
  if betIndex then
    bets[betIndex].stake = bets[betIndex].stake + amount
    return bets[betIndex]
  end

  local bet = cloneBet(region)
  bet.stake = amount
  insert(bets, bet)
  return bet
end

local function removeStake(bets, key, amount)
  assert(type(bets) == "table", "bets must be a table")
  assert(type(key) == "string" and key ~= "", "bet key is required")
  assert(type(amount) == "number" and amount > 0, "amount must be positive")

  local betIndex = findBetIndex(bets, key)
  if not betIndex then
    return false
  end

  local bet = bets[betIndex]
  bet.stake = bet.stake - amount
  if bet.stake <= 0 then
    table.remove(bets, betIndex)
  end
  return true
end

local function getTotalStake(bets)
  local total = 0
  for _, bet in ipairs(bets) do
    total = total + (bet.stake or 0)
  end
  return total
end

local function doesBetWin(bet, number)
  return bet.lookup[number] == true
end

local function computeNetForNumber(bets, number)
  local net = 0
  for _, bet in ipairs(bets) do
    local stake = bet.stake or 0
    if doesBetWin(bet, number) then
      net = net + (stake * bet.payout)
    else
      net = net - stake
    end
  end
  return net
end

local function getMaxExposure(bets)
  local highest = 0
  local number = 0
  while number <= 36 do
    highest = max(highest, computeNetForNumber(bets, number))
    number = number + 1
  end
  return highest
end

local function getWinningKeysForOutcome(number)
  local keys = {}
  keys["straight:" .. tostring(number)] = true

  if number == 0 then
    return keys
  end

  if isRed(number) then
    keys.red = true
  else
    keys.black = true
  end

  if number % 2 == 0 then
    keys.even = true
  else
    keys.odd = true
  end

  if number <= 18 then
    keys.low = true
  else
    keys.high = true
  end

  keys["dozen:" .. tostring(floor((number - 1) / 12) + 1)] = true
  keys["column:" .. tostring(((number - 1) % 3) + 1)] = true
  keys["street:" .. tostring(floor((number - 1) / 3) + 1)] = true

  return keys
end

local function settleBets(bets, winningNumber)
  local summary = {
    totalStake = 0,
    totalWinnings = 0,
    totalLosses = 0,
    net = 0,
    winningBets = {},
    losingBets = {},
    result = "push",
    winningNumber = winningNumber,
    winningColor = getColorName(winningNumber),
  }

  for _, bet in ipairs(bets) do
    local stake = bet.stake or 0
    summary.totalStake = summary.totalStake + stake

    if doesBetWin(bet, winningNumber) then
      local payout = stake * bet.payout
      summary.totalWinnings = summary.totalWinnings + payout
      summary.net = summary.net + payout
      insert(summary.winningBets, {
        bet = cloneBet(bet),
        amount = payout,
      })
    else
      summary.totalLosses = summary.totalLosses + stake
      summary.net = summary.net - stake
      insert(summary.losingBets, {
        bet = cloneBet(bet),
        amount = stake,
      })
    end
  end

  if summary.net > 0 then
    summary.result = "win"
  elseif summary.net < 0 then
    summary.result = "loss"
  end

  return summary
end

local function getWheelIndex(number)
  return WHEEL_INDEX[number]
end

return {
  WHEEL_ORDER = WHEEL_ORDER,
  makeBetDefinition = makeBetDefinition,
  cloneBet = cloneBet,
  cloneBetList = cloneBetList,
  addStake = addStake,
  removeStake = removeStake,
  getTotalStake = getTotalStake,
  getMaxExposure = getMaxExposure,
  doesBetWin = doesBetWin,
  settleBets = settleBets,
  getWheelIndex = getWheelIndex,
  getWinningKeysForOutcome = getWinningKeysForOutcome,
  isRed = isRed,
  isBlack = isBlack,
  getNumberColor = getNumberColor,
  getNumberTextColor = getNumberTextColor,
  getColorName = getColorName,
  getNumberAt = getNumberAt,
  getRowNumbers = getRowNumbers,
  getColumnNumbers = getColumnNumbers,
  getDozenNumbers = getDozenNumbers,
}
