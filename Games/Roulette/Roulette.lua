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
  return colors.gray
end

local function getNumberTextColor(n)
  if n == 0 then return colors.black end
  return colors.white
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

-----------------------------------------------------
-- Rendering helpers
-----------------------------------------------------
local function drawWheelCell(x, y, n, w, h, highlight)
  local bg = getNumberColor(n)
  if highlight then
    screen:fillRect(x, y, w, h, colors.yellow)
    screen:fillRect(x + 1, y + 1, w - 2, h - 2, bg)
  else
    screen:fillRect(x, y, w, h, bg)
  end

  local numStr = tostring(n)
  local tw = ui.getTextSize(numStr)
  local tx = x + floor((w - tw) / 2)
  local ty = y + floor((h - 7) / 2)
  ui.safeDrawText(screen, numStr, font, tx, ty, getNumberTextColor(n))
end

local function drawWheelStrip(centerIdx, y, cellW, cellH, visibleCount)
  local half = floor(visibleCount / 2)
  local totalW = visibleCount * (cellW + 1) - 1
  local startX = floor((width - totalW) / 2)

  for i = -half, half do
    local idx = ((centerIdx - 1 + i) % WHEEL_SIZE) + 1
    local n = WHEEL[idx]
    local x = startX + (i + half) * (cellW + 1)
    local isCenter = (i == 0)
    drawWheelCell(x, y, n, cellW, cellH, isCenter)
  end

  -- Pointer arrow above center cell
  local arrowX = startX + half * (cellW + 1) + floor(cellW / 2)
  screen:fillRect(arrowX - 1, y - 2, 3, 2, colors.yellow)
end

local function drawNumberDisplay(number, y)
  local numStr = tostring(number)
  local bg = getNumberColor(number)
  local fg = getNumberTextColor(number)

  local boxW = 20
  local boxH = 12
  local boxX = floor((width - boxW) / 2)

  screen:fillRect(boxX - 1, y - 1, boxW + 2, boxH + 2, colors.yellow)
  screen:fillRect(boxX, y, boxW, boxH, bg)

  local tw = ui.getTextSize(numStr)
  local tx = floor((width - tw) / 2)
  local ty = y + floor((boxH - 7) / 2)
  ui.safeDrawText(screen, numStr, font, tx, ty, fg)
end

-----------------------------------------------------
-- Main screen rendering
-----------------------------------------------------
local STRIP_Y = 11
local CELL_W  = 8
local CELL_H  = 8
local VISIBLE_CELLS = 7

local function drawScreen(result, resultIdx, betType, straightNum, betAmount, statusText, spinIdx)
  screen:clear(LO.TABLE_COLOR)

  -- Title bar
  screen:fillRect(0, 0, width, 8, colors.black)
  local title = "ROULETTE"
  local ttw = ui.getTextSize(title)
  ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), LO.TITLE_Y, colors.yellow)

  -- Bet amount (top-left)
  if betAmount and betAmount > 0 then
    local betStr = "Bet: " .. currency.formatTokens(betAmount)
    ui.safeDrawText(screen, betStr, font, 2, LO.TITLE_Y, colors.lightGray)
  end

  -- Bet type + payout (top-right)
  if betType then
    local betLabel = getBetTypeLabel(betType, straightNum)
    local payoutStr = getPayoutMultiplier(betType) .. ":1"
    betLabel = betLabel .. " " .. payoutStr
    local blw = ui.getTextSize(betLabel)
    ui.safeDrawText(screen, betLabel, font, width - blw - 2, LO.TITLE_Y, colors.cyan)
  end

  -- Separator
  screen:fillRect(0, 8, width, 1, colors.yellow)

  -- Wheel strip or result
  if spinIdx then
    -- Animating spin
    drawWheelStrip(spinIdx, STRIP_Y, CELL_W, CELL_H, VISIBLE_CELLS)
  elseif result ~= nil then
    -- Showing result
    drawWheelStrip(resultIdx, STRIP_Y, CELL_W, CELL_H, VISIBLE_CELLS)
    -- Big number display (adaptive: only if there's room)
    local numY = STRIP_Y + CELL_H + 3
    if numY + 14 < height - 10 then
      drawNumberDisplay(result, numY)
    end
  else
    -- Idle / pre-spin
    drawWheelStrip(1, STRIP_Y, CELL_W, CELL_H, VISIBLE_CELLS)
  end

  -- Status text at bottom
  if statusText then
    local stw = ui.getTextSize(statusText.text)
    local sy = height - 10
    ui.safeDrawText(screen, statusText.text, font, floor((width - stw) / 2), sy, statusText.color)
  end

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
local function animateSpin(finalIdx, betType, straightNum, betAmount)
  local totalTicks = cfg.SPIN_TICKS
  local startIdx = random(1, WHEEL_SIZE)

  -- Multiple full rotations + landing position
  local fullRotations = 3
  local totalPositions = fullRotations * WHEEL_SIZE + ((finalIdx - startIdx) % WHEEL_SIZE)

  for tick = 1, totalTicks do
    -- Ease-out: decelerates toward the end
    local progress = tick / totalTicks
    local easedProgress = 1 - (1 - progress) * (1 - progress)
    local posOffset = floor(easedProgress * totalPositions)
    local currentIdx = ((startIdx - 1 + posOffset) % WHEEL_SIZE) + 1

    drawScreen(nil, nil, betType, straightNum, betAmount, {
      text = "Spinning...",
      color = colors.yellow,
    }, currentIdx)

    -- Variable delay: faster at start, slower near the end
    local delay = cfg.SPIN_FRAME_DELAY
    if progress > 0.7 then
      delay = delay + (progress - 0.7) * 0.3
    end
    os.sleep(delay)
  end

  -- Landing click
  sound.play(sound.SOUNDS.CARD_PLACE, 0.8)
  os.sleep(0.3)
end

-----------------------------------------------------
-- One round of roulette
-----------------------------------------------------
local function rouletteRound(betAmount, betType, straightNum)
  recovery.saveBet(betAmount)

  -- Pre-spin confirmation screen with bet summary
  local betLabel = getBetTypeLabel(betType, straightNum)
  local payoutStr = getPayoutMultiplier(betType) .. ":1"

  drawScreen(nil, nil, betType, straightNum, betAmount, {
    text = betLabel .. " " .. payoutStr .. "  Touch to SPIN!",
    color = colors.lime,
  }, nil)

  if not AUTO_PLAY then
    os.pullEvent("monitor_touch")
  else
    os.sleep(cfg.AUTO_PLAY_DELAY)
  end

  -- Spin the wheel
  sound.play(sound.SOUNDS.START, 0.6)
  local winNumber, winIdx = spinWheel()

  -- Animate the spin
  animateSpin(winIdx, betType, straightNum, betAmount)

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
      drawScreen(winNumber, winIdx, betType, straightNum, betAmount, {
        text = winMsg,
        color = showHighlight and colors.yellow or colors.lime,
      }, nil)
      if isJackpot then
        sound.play(sound.SOUNDS.SUCCESS, 1.0)
      elseif flash == 1 then
        sound.play(sound.SOUNDS.SUCCESS, 0.8)
      end
      os.sleep(isJackpot and 0.35 or 0.25)
    end

    -- Hold the result on screen
    drawScreen(winNumber, winIdx, betType, straightNum, betAmount, {
      text = winMsg,
      color = colors.lime,
    }, nil)
    os.sleep(cfg.RESULT_PAUSE)

    dbg("WIN: " .. betType .. " number=" .. winNumber .. " payout=" .. (betAmount + winnings))
  else
    local charged = currency.charge(betAmount, "Roulette: " .. betType .. " loss")
    if not charged then
      alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (roulette)")
    end

    -- Loss display
    drawScreen(winNumber, winIdx, betType, straightNum, betAmount, {
      text = resultLabel .. " - Better luck next time!",
      color = colors.lightGray,
    }, nil)
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
