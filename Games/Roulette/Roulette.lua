-- roulette.lua
-- European Roulette for ComputerCraft casino.
-- Single-zero wheel, visual spin animation, inside + outside bets.
-- Uses shared casino libraries for economy, UI, crash recovery, etc.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("roulette_config")

local LO = cfg.LAYOUT

local epoch        = os.epoch
local r_getInput   = redstone.getInput
local settings_get = settings.get
local floor        = math.floor
local random       = math.random

settings.define("roulette.debug", {
  description = "Enable debug messages for Roulette.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("roulette.debug")
local function dbg(msg)
  if DEBUG then print(os.time(), "[ROUL] " .. msg) end
end

-----------------------------------------------------
-- Shared library imports
-----------------------------------------------------
local currency  = require("lib.currency")
local sound     = require("lib.sound")
local ui        = require("lib.ui")
local alert     = require("lib.alert")
local recovery  = require("lib.crash_recovery")
local gameSetup = require("lib.game_setup")
local betting   = require("lib.betting")

-----------------------------------------------------
-- Auto-play state
-----------------------------------------------------
local AUTO_PLAY = false

local function updateAutoPlay()
  local powered = r_getInput(cfg.REDSTONE)
  if powered ~= AUTO_PLAY then
    AUTO_PLAY = powered
    dbg("Auto-play " .. (AUTO_PLAY and "ON" or "OFF"))
  end
  return AUTO_PLAY
end

-----------------------------------------------------
-- Initialize game environment
-----------------------------------------------------
recovery.configure(cfg.RECOVERY_FILE)

local roulettePalette = {}
for k, v in pairs(gameSetup.DEFAULT_PALETTE) do roulettePalette[k] = v end
if cfg.PALETTE then
  for k, v in pairs(cfg.PALETTE) do roulettePalette[k] = v end
end

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount   = 1,
  gameName    = cfg.GAME_NAME,
  logFile     = cfg.LOG_FILE,
  skipAuth    = false,
  palette     = roulettePalette,
})

alert.addPlannedExits({
  cfg.EXIT_CODES.INACTIVITY_TIMEOUT,
  cfg.EXIT_CODES.MAIN_MENU,
  cfg.EXIT_CODES.USER_TERMINATED,
  cfg.EXIT_CODES.PLAYER_QUIT,
})

local screen = env.screen
local width  = env.width
local height = env.height
local font   = env.font

-----------------------------------------------------
-- Host balance tracking
-----------------------------------------------------
local hostBankBalance = currency.getHostBalance()
dbg("Initial host balance: " .. hostBankBalance .. " tokens")

local function getMaxBet()
  return floor(hostBankBalance * cfg.MAX_BET_PERCENT)
end

-----------------------------------------------------
-- Player detection
-----------------------------------------------------
local function refreshPlayer()
  return gameSetup.refreshPlayer(env)
end

local function drawPlayerOverlay()
  gameSetup.drawPlayerOverlay(env)
end

-----------------------------------------------------
-- Roulette lookup tables
-----------------------------------------------------
local WHEEL = cfg.WHEEL_ORDER
local WHEEL_SIZE = #WHEEL

local redSet = {}
for _, n in ipairs(cfg.RED_NUMBERS) do
  redSet[n] = true
end

local function isRed(n)
  return redSet[n] == true
end

local function isBlack(n)
  return n > 0 and not redSet[n]
end

local function getNumberColor(n)
  if n == 0 then return colors.lime end
  if isRed(n) then return colors.red end
  return colors.black
end

local function getNumberTextColor(n)
  if n == 0 then return colors.black end
  if isRed(n) then return colors.black end
  return colors.lightGray
end

local function getColorName(n)
  if n == 0 then return "GREEN" end
  if isRed(n) then return "RED" end
  return "BLACK"
end

-----------------------------------------------------
-- Bet type helpers
-----------------------------------------------------
local function getBetTypeLabel(betType, straightNum)
  for _, bt in ipairs(cfg.BET_TYPES) do
    if bt.id == betType then
      if betType == "straight" and straightNum then
        return bt.label .. " (" .. straightNum .. ")"
      end
      return bt.label
    end
  end
  return betType:upper()
end

local function getPayoutMultiplier(betType)
  for _, bt in ipairs(cfg.BET_TYPES) do
    if bt.id == betType then
      return bt.payout
    end
  end
  return 0
end

-----------------------------------------------------
-- Bet evaluation
-----------------------------------------------------
local function doesBetWin(betType, number, straightNum)
  if betType == "straight" then
    return number == straightNum
  elseif betType == "red" then
    return isRed(number)
  elseif betType == "black" then
    return isBlack(number)
  elseif betType == "odd" then
    return number > 0 and number % 2 == 1
  elseif betType == "even" then
    return number > 0 and number % 2 == 0
  elseif betType == "low" then
    return number >= 1 and number <= 18
  elseif betType == "high" then
    return number >= 19 and number <= 36
  elseif betType == "dozen1" then
    return number >= 1 and number <= 12
  elseif betType == "dozen2" then
    return number >= 13 and number <= 24
  elseif betType == "dozen3" then
    return number >= 25 and number <= 36
  elseif betType == "col1" then
    return number > 0 and number % 3 == 1
  elseif betType == "col2" then
    return number > 0 and number % 3 == 2
  elseif betType == "col3" then
    return number > 0 and number % 3 == 0
  end
  return false
end

-----------------------------------------------------
-- Spin the wheel
-----------------------------------------------------
local function spinWheel()
  local idx = random(1, WHEEL_SIZE)
  return WHEEL[idx], idx
end

-- Rendering helpers
-----------------------------------------------------
local function drawNumberDisplay(number, y)
  local numStr = tostring(number)
  local bg = getNumberColor(number)
  local fg = getNumberTextColor(number)

  local boxW = 12
  local boxH = 8
  local boxX = floor((width - boxW) / 2)

  screen:fillRect(boxX - 1, y - 1, boxW + 2, boxH + 2, colors.yellow)
  screen:fillRect(boxX, y, boxW, boxH, bg)

  local tw = ui.getTextSize(numStr)
  local tx = floor((width - tw) / 2)
  local ty = y + floor((boxH - 7) / 2)
  ui.safeDrawText(screen, numStr, font, tx, ty, fg)
end

local function drawBoardCell(x, y, n, w, h, isSelected, isGold)
  local bg = getNumberColor(n)

  if isGold then
    screen:fillRect(x - 2, y - 2, w + 4, h + 4, colors.yellow)
    screen:fillRect(x - 1, y - 1, w + 2, h + 2, colors.orange)
  elseif isSelected then
    screen:fillRect(x - 1, y - 1, w + 2, h + 2, colors.yellow)
  end

  screen:fillRect(x, y, w, h, bg)

  local numStr = tostring(n)
  local tw = ui.getTextSize(numStr)
  local tx = x + floor((w - tw) / 2)
  local ty = y + floor((h - 7) / 2)
  ui.safeDrawText(screen, numStr, font, tx, ty, getNumberTextColor(n))
end

local function drawNumberBoard(activeNumber, finalNumber)
  local cellW = (width >= 100) and 11 or 10
  local cellH = (height >= 100) and 8 or 7
  local gap = 1
  local cols = 6

  local zeroY = 31
  local zeroX = floor((width - cellW) / 2)

  local totalGridW = cols * (cellW + gap) - gap
  local gridX = floor((width - totalGridW) / 2)
  local gridY = zeroY + cellH + gap + 2

  drawBoardCell(zeroX, zeroY, 0, cellW, cellH, activeNumber == 0, finalNumber == 0)

  for n = 1, 36 do
    local row = floor((n - 1) / cols)
    local col = (n - 1) % cols
    local x = gridX + col * (cellW + gap)
    local y = gridY + row * (cellH + gap)
    drawBoardCell(x, y, n, cellW, cellH, activeNumber == n, finalNumber == n)
  end
end

-----------------------------------------------------
-- Main screen rendering
-----------------------------------------------------
local function drawScreen(result, betType, straightNum, betAmount, statusText, activeNumber, finalNumber)
  screen:clear(LO.TABLE_COLOR)

  -- Title bar
  screen:fillRect(0, 0, width, 16, colors.black)
  local title = "ROULETTE"
  local titleW = ui.getTextSize(title)

  local betStr = nil
  if betAmount and betAmount > 0 then
    betStr = "Bet: " .. currency.formatTokens(betAmount)
  end

  local rightStr = nil
  if betType then
    local betLabel = getBetTypeLabel(betType, straightNum)
    local payoutStr = getPayoutMultiplier(betType) .. ":1"
    rightStr = betLabel .. " " .. payoutStr
  end

  ui.safeDrawText(screen, title, font, floor((width - titleW) / 2), 1, colors.yellow)

  -- Bet amount (top-left)
  if betStr then
    ui.safeDrawText(screen, betStr, font, 2, 9, colors.lightGray)
  end

  -- Bet type + payout (top-right)
  if rightStr then
    local rsw = ui.getTextSize(rightStr)
    local rightX = width - rsw - 2

    if betStr then
      local leftW = ui.getTextSize(betStr)
      if (2 + leftW + 3) > rightX then
        betStr = "Bet:" .. tostring(betAmount)
        ui.safeDrawText(screen, string.rep(" ", leftW), font, 2, 9, colors.black)
        ui.safeDrawText(screen, betStr, font, 2, 9, colors.lightGray)
      end

      leftW = ui.getTextSize(betStr)
      rightX = width - rsw - 2
      if (2 + leftW + 3) > rightX then
        rightStr = getPayoutMultiplier(betType) .. ":1"
        rsw = ui.getTextSize(rightStr)
        rightX = width - rsw - 2
      end
    end

    ui.safeDrawText(screen, rightStr, font, rightX, 9, colors.cyan)
  end

  -- Separator
  screen:fillRect(0, 16, width, 1, colors.yellow)

  local boardTitle = "PICK A NUMBER 35:1"
  local lineText = boardTitle
  local lineColor = colors.yellow
  if statusText then
    lineText = statusText.text
    lineColor = statusText.color
  end
  local ltw = ui.getTextSize(lineText)
  ui.safeDrawText(screen, lineText, font, floor((width - ltw) / 2), 19, lineColor)

  local shownNumber = activeNumber
  if shownNumber == nil then
    shownNumber = result
  end
  if shownNumber == nil then
    shownNumber = (betType == "straight" and straightNum) or 0
  end

  drawNumberDisplay(shownNumber, 22)
  drawNumberBoard(shownNumber, finalNumber)

  screen:output()
end

-----------------------------------------------------
-- Bet type selection screen
-----------------------------------------------------
local function selectBetType()
  local selectedType = nil
  local straightNum = nil
  local page = 1

  while not selectedType do
    screen:clear(LO.TABLE_COLOR)
    ui.clearButtons()

    if page == 1 then
      -- Outside bets + navigation to number picker
      local title = "CHOOSE YOUR BET"
      local ttw = ui.getTextSize(title)
      ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), 1, colors.yellow)

      local centerX = floor(width / 2)
      local btnY = 10
      local btnSpacing = 8

      ui.layoutButtonGrid(screen, {
        {
          { text = "RED 1:1", color = colors.red,
            func = function() selectedType = "red" end },
          { text = "BLACK 1:1", color = colors.gray,
            func = function() selectedType = "black" end },
        },
        {
          { text = "ODD 1:1", color = colors.orange,
            func = function() selectedType = "odd" end },
          { text = "EVEN 1:1", color = colors.lightBlue,
            func = function() selectedType = "even" end },
        },
        {
          { text = "1-18 1:1", color = colors.brown,
            func = function() selectedType = "low" end },
          { text = "19-36 1:1", color = colors.purple,
            func = function() selectedType = "high" end },
        },
        {
          { text = "1ST 12 2:1", color = colors.cyan,
            func = function() selectedType = "dozen1" end },
          { text = "2ND 12 2:1", color = colors.cyan,
            func = function() selectedType = "dozen2" end },
          { text = "3RD 12 2:1", color = colors.cyan,
            func = function() selectedType = "dozen3" end },
        },
        {
          { text = "COL 1 2:1", color = colors.lime,
            func = function() selectedType = "col1" end },
          { text = "COL 2 2:1", color = colors.lime,
            func = function() selectedType = "col2" end },
          { text = "COL 3 2:1", color = colors.lime,
            func = function() selectedType = "col3" end },
        },
      }, centerX, btnY, btnSpacing, 4)

      -- Navigation to straight-up number picker
      local pickY = btnY + 5 * btnSpacing
      ui.button(screen, "PICK A NUMBER 35:1", colors.magenta, centerX, pickY, function()
        page = 2
      end, true)

    elseif page == 2 then
      -- Straight-up number picker grid (6 columns for readability)
      local title = "PICK A NUMBER 35:1"
      local ttw = ui.getTextSize(title)
      ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), 1, colors.yellow)

      local startY = 10
      local cellW = 12
      local cellH = 8
      local gap = 1
      local cols = 6

      -- Zero button (centered, special green)
      local zeroW = cellW
      ui.fixedWidthButton(screen, "0", colors.lime,
        floor((width - zeroW) / 2), startY, function()
          selectedType = "straight"
          straightNum = 0
        end, false, zeroW)

      -- Numbers 1-36 in a 6-column grid (6 rows of 6)
      local totalGridW = cols * (cellW + gap) - gap
      local gridX = floor((width - totalGridW) / 2)
      local numStartY = startY + cellH + gap + 2

      for n = 1, 36 do
        local row = floor((n - 1) / cols)
        local col = (n - 1) % cols
        local x = gridX + col * (cellW + gap)
        local y = numStartY + row * (cellH + gap)

        local bg = getNumberColor(n)
        ui.fixedWidthButton(screen, tostring(n), bg, x, y, function()
          selectedType = "straight"
          straightNum = n
        end, false, cellW)
      end

      -- Back button below the grid
      local backY = numStartY + 6 * (cellH + gap) + 2
      ui.button(screen, "< BACK", colors.red, floor(width / 2), backY, function()
        page = 1
      end, true)
    end

    screen:output()
    ui.waitForButton(0, 0)
  end

  -- Confirm sound on selection
  sound.play(sound.SOUNDS.START, 0.4)
  return selectedType, straightNum
end

-----------------------------------------------------
-- Spin animation
-----------------------------------------------------
local function animateSpin(finalNumber, betType, straightNum, betAmount)
  local totalTicks = cfg.SPIN_TICKS
  local currentNumber = random(0, 36)

  for tick = 1, totalTicks do
    local progress = tick / totalTicks

    if tick >= totalTicks - 2 then
      currentNumber = finalNumber
    else
      local nextNumber = currentNumber
      while nextNumber == currentNumber do
        nextNumber = random(0, 36)
      end
      currentNumber = nextNumber
    end

    drawScreen(nil, betType, straightNum, betAmount, {
      text = "Spinning...",
      color = colors.yellow,
    }, currentNumber, nil)

    -- Slight slowdown near the end for readability.
    local delay = cfg.SPIN_FRAME_DELAY + (progress * 0.08)
    os.sleep(delay)
  end

  -- Landing click
  sound.play(sound.SOUNDS.CARD_PLACE, 0.8)
  os.sleep(0.2)
end

-----------------------------------------------------
-- One round of roulette
-----------------------------------------------------
local function rouletteRound(betAmount, betType, straightNum)
  recovery.saveBet(betAmount)

  -- Pre-spin confirmation screen with bet summary
  local betLabel = getBetTypeLabel(betType, straightNum)
  local payoutStr = getPayoutMultiplier(betType) .. ":1"

  drawScreen(nil, betType, straightNum, betAmount, {
    text = betLabel .. " " .. payoutStr .. "  Touch to SPIN!",
    color = colors.lime,
  }, straightNum, nil)

  if not AUTO_PLAY then
    os.pullEvent("monitor_touch")
  else
    os.sleep(cfg.AUTO_PLAY_DELAY)
  end

  -- Spin the wheel
  sound.play(sound.SOUNDS.START, 0.6)
  local winNumber = spinWheel()

  -- Animate the spin
  animateSpin(winNumber, betType, straightNum, betAmount)

  -- Evaluate result
  local won = doesBetWin(betType, winNumber, straightNum)
  local colorName = getColorName(winNumber)
  local resultLabel = winNumber .. " " .. colorName

  if won then
    local multiplier = getPayoutMultiplier(betType)
    local winnings = betAmount * multiplier

    if not currency.payout(winnings, "Roulette: " .. betType .. " payout") then
      alert.send("CRITICAL: Failed to pay " .. winnings .. " tokens (roulette)")
    end

    local winMsg = resultLabel .. "! +" .. currency.formatTokens(winnings)
    local isJackpot = (betType == "straight")

    -- Win flash animation
    local flashes = isJackpot and 8 or 4
    for flash = 1, flashes do
      local showHighlight = (flash % 2 == 1)
      drawScreen(winNumber, betType, straightNum, betAmount, {
        text = winMsg,
        color = showHighlight and colors.yellow or colors.lime,
      }, winNumber, winNumber)
      if isJackpot then
        sound.play(sound.SOUNDS.SUCCESS, 1.0)
      elseif flash == 1 then
        sound.play(sound.SOUNDS.SUCCESS, 0.8)
      end
      os.sleep(isJackpot and 0.35 or 0.25)
    end

    -- Hold the result on screen
    drawScreen(winNumber, betType, straightNum, betAmount, {
      text = winMsg,
      color = colors.lime,
    }, winNumber, winNumber)
    os.sleep(cfg.RESULT_PAUSE)

    dbg("WIN: " .. betType .. " number=" .. winNumber .. " payout=" .. (betAmount + winnings))
  else
    local charged = currency.charge(betAmount, "Roulette: " .. betType .. " loss")
    if not charged then
      alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (roulette)")
    end

    -- Loss display
    drawScreen(winNumber, betType, straightNum, betAmount, {
      text = resultLabel .. " - Better luck next time!",
      color = colors.lightGray,
    }, winNumber, winNumber)
    sound.play(sound.SOUNDS.FAIL, 0.4)
    os.sleep(cfg.RESULT_PAUSE)

    dbg("LOSS: " .. betType .. " number=" .. winNumber)
  end

  recovery.clearBet()
  hostBankBalance = currency.getHostBalance()
end

-----------------------------------------------------
-- Bet amount selection (dynamic coverage per bet type)
-----------------------------------------------------
local function betSelection(betType, straightNum)
  -- Calculate max payout multiplier for this bet type
  -- Host must be able to cover: bet * (payout + 1) for the return + winnings
  local payoutMult = getPayoutMultiplier(betType) + 1

  -- Cap the bet by both percentage and actual host coverage
  local percentCap = getMaxBet()
  local coverageCap = floor(hostBankBalance / payoutMult)
  local effectiveMax = math.min(percentCap, coverageCap)
  if effectiveMax <= 0 then
    effectiveMax = 1
  end

  local betLabel = getBetTypeLabel(betType, straightNum)

  return betting.runBetScreen(screen, {
    maxBet                 = effectiveMax,
    gameName               = "Roulette",
    confirmLabel           = "SPIN",
    title                  = "BET: " .. betLabel:upper(),
    inactivityTimeout      = cfg.INACTIVITY_TIMEOUT,
    hostBalance            = hostBankBalance,
    hostCoverageMultiplier = payoutMult,
    onTimeout              = function()
      sound.play(sound.SOUNDS.TIMEOUT)
      os.sleep(0.5)
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end,
  })
end

-----------------------------------------------------
-- Main game loop
-----------------------------------------------------
local function main()
  dbg("Roulette starting up")
  refreshPlayer()
  drawPlayerOverlay()

  while true do
    updateAutoPlay()
    refreshPlayer()

    local currentBet = nil
    local betType = nil
    local straightNum = nil

    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      currentBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if currentBet <= 0 then
        dbg("Auto-play: insufficient funds, pausing")
        os.sleep(2)
      else
        -- Auto-play picks a random bet type
        local types = { "red", "black", "odd", "even", "low", "high",
                        "dozen1", "dozen2", "dozen3", "col1", "col2", "col3", "straight" }
        betType = types[random(1, #types)]
        if betType == "straight" then
          straightNum = random(0, 36)
        end
        rouletteRound(currentBet, betType, straightNum)
      end
    else
      -- Step 1: Choose bet type
      drawPlayerOverlay()
      betType, straightNum = selectBetType()

      -- Step 2: Choose bet amount (dynamically capped per bet type)
      drawPlayerOverlay()
      local selectedBet = betSelection(betType, straightNum)

      if selectedBet and selectedBet > 0 then
        rouletteRound(selectedBet, betType, straightNum)
      end
    end

    os.sleep(0)
  end
end

-----------------------------------------------------
-- Entry point with safe runner
-----------------------------------------------------
sound.play(sound.SOUNDS.BOOT)
recovery.recoverBet(true)

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
