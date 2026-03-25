-- slots.lua
-- Slot Machine game for ComputerCraft casino.
-- Three spinning reels with weighted symbols, animated spin,
-- and payouts for matching combinations.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("slots_config")

local LO = cfg.LAYOUT

local epoch        = os.epoch
local r_getInput   = redstone.getInput
local settings_get = settings.get
local floor        = math.floor
local max          = math.max
local min          = math.min
local random       = math.random

settings.define("slots.debug", {
  description = "Enable debug messages for Slots.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("slots.debug")
local function dbg(msg)
  if DEBUG then print(os.time(), "[SLOTS] " .. msg) end
end

-----------------------------------------------------
-- Shared library imports
-----------------------------------------------------
local currency   = require("lib.currency")
local sound      = require("lib.sound")
local ui         = require("lib.ui")
local alert      = require("lib.alert")
local recovery   = require("lib.crash_recovery")
local gameSetup  = require("lib.game_setup")
local betting    = require("lib.betting")

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

-- Merge custom palette with defaults
local slotsPalette = {}
for k, v in pairs(gameSetup.DEFAULT_PALETTE) do slotsPalette[k] = v end
if cfg.PALETTE then
  for k, v in pairs(cfg.PALETTE) do slotsPalette[k] = v end
end

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount   = 1,
  gameName    = cfg.GAME_NAME,
  logFile     = cfg.LOG_FILE,
  skipAuth    = false,
  palette     = slotsPalette,
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
local scale  = env.scale

-----------------------------------------------------
-- Host balance tracking
-----------------------------------------------------
local hostBankBalance  = currency.getHostBalance()
local openingBankValue = hostBankBalance
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
-- Reel building (weighted symbol pool)
-----------------------------------------------------
local SYMBOLS = cfg.SYMBOLS
local PAYOUTS = cfg.PAYOUTS
local TWO_OF_A_KIND_PAYOUTS = cfg.TWO_OF_A_KIND_PAYOUTS or {}
local surfaceLib = env.surface
local maxArtW = 0
local maxArtH = 0

-- Pre-load pixel art for each symbol
for _, sym in ipairs(SYMBOLS) do
  if sym.art then
    local ok, art = pcall(surfaceLib.load, sym.art)
    if ok and art then
      sym.artSurface = art
      maxArtW = max(maxArtW, art.width)
      maxArtH = max(maxArtH, art.height)
      dbg("Loaded art: " .. sym.art .. " (" .. art.width .. "x" .. art.height .. ")")
    else
      dbg("Could not load art: " .. sym.art .. " - " .. tostring(art))
    end
  end
end

local function buildReel()
  local reel = {}
  for _, sym in ipairs(SYMBOLS) do
    for _ = 1, sym.weight do
      reel[#reel + 1] = sym
    end
  end
  -- Shuffle
  for i = #reel, 2, -1 do
    local j = random(1, i)
    reel[i], reel[j] = reel[j], reel[i]
  end
  return reel
end

local reels = { buildReel(), buildReel(), buildReel() }

-----------------------------------------------------
-- Layout calculations
-----------------------------------------------------
local TITLE_Y    = scale:scaledY(LO.TITLE_Y, scale.edgePad, scale.lineHeight)
local TITLE_BAR_H = max(scale.buttonHeight, scale.lineHeight + scale.smallGap + 1)
local REEL_GAP   = scale:scaledX(LO.REEL_SPACING, 1, 8)
local desiredReelW = scale:scaledX(LO.REEL_WIDTH, 10, 32)
local availableReelW = width - (scale.edgePad * 2) - (REEL_GAP * 2)
local REEL_W = max(10, floor(availableReelW / 3))
REEL_W = min(REEL_W, max(maxArtW + (scale.buttonPadX * 2) + 2, desiredReelW))
local minReelH = max(12, maxArtH + scale.lineHeight + 4)
local desiredReelH = scale:scaledY(LO.REEL_HEIGHT, minReelH, height)
local availableReelH = max(minReelH, height - TITLE_BAR_H - scale.messageLineHeight - (scale.edgePad * 4))
local REEL_H = min(availableReelH, max(minReelH, desiredReelH))
local TOTAL_W    = REEL_W * 3 + REEL_GAP * 2
local REEL_START_X = max(0, floor((width - TOTAL_W) / 2))
local REEL_Y     = max(TITLE_BAR_H + scale.sectionGap, min(scale:scaledY(LO.REEL_Y, TITLE_BAR_H + scale.smallGap, height - REEL_H - scale.messageLineHeight - scale.edgePad), height - REEL_H - scale.messageLineHeight - scale.edgePad))

-----------------------------------------------------
-- Spin a random result from a reel
-----------------------------------------------------
local function spinReel(reel)
  return reel[random(1, #reel)]
end

-----------------------------------------------------
-- Draw a single reel cell
-----------------------------------------------------
local function drawReelCell(x, y, sym, highlight)
  local bg = highlight and colors.white or LO.REEL_BG
  screen:fillRect(x, y, REEL_W, REEL_H, bg)

  -- Border
  local borderClr = highlight and colors.yellow or colors.gray
  screen:fillRect(x, y, REEL_W, 1, borderClr)
  screen:fillRect(x, y + REEL_H - 1, REEL_W, 1, borderClr)
  screen:fillRect(x, y, 1, REEL_H, borderClr)
  screen:fillRect(x + REEL_W - 1, y, 1, REEL_H, borderClr)

  -- Interior area (inside border)
  local ix = x + 1
  local iy = y + 1
  local iw = REEL_W - 2
  local ih = REEL_H - 2

  if sym.artSurface then
    -- Draw pixel art centered, with label text below
    local art = sym.artSurface
    local labelH = max(6, scale.lineHeight - 1)
    local artSpace = max(1, ih - labelH)
    local ax = ix + floor((iw - art.width) / 2)
    local ay = iy + floor((artSpace - art.height) / 2)
    screen:drawSurface(art, ax, ay)

    -- Label text below the art area
    local label = sym.label
    local tw = ui.getTextSize(label)
    local tx = x + floor((REEL_W - tw) / 2)
    local ty = iy + artSpace
    local textClr = highlight and colors.black or sym.color
    ui.safeDrawText(screen, label, font, tx, ty, textClr)
  else
    -- Fallback: text only
    local label = sym.label
    local tw = ui.getTextSize(label)
    local tx = x + floor((REEL_W - tw) / 2)
    local ty = y + floor((REEL_H - scale.fontHeight) / 2)
    local textClr = highlight and colors.black or sym.color
    ui.safeDrawText(screen, label, font, tx, ty, textClr)
  end
end

-----------------------------------------------------
-- Draw the full machine frame
-----------------------------------------------------
local function drawMachine(result, highlights, statusText, currentBet)
  screen:clear(LO.TABLE_COLOR)

  -- Title bar background
  screen:fillRect(0, 0, width, TITLE_BAR_H, colors.black)
  local title = "SLOT MACHINE"
  local ttw = ui.getTextSize(title)
  ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), TITLE_Y, colors.yellow)

  -- Bet display
  if currentBet then
    local betStr = "Bet: " .. currency.formatTokens(currentBet)
    ui.safeDrawText(screen, betStr, font, scale.edgePad, TITLE_Y, colors.lightGray)
  end

  -- Decorative gold trim below title
  screen:fillRect(0, TITLE_BAR_H, width, 1, colors.yellow)

  -- Machine outer frame (gold border > gray > inner black)
  local frameInset = max(2, scale.edgePad + 1)
  local frameX = REEL_START_X - frameInset
  local frameY = REEL_Y - frameInset
  local frameW = TOTAL_W + (frameInset * 2)
  local frameH = REEL_H + (frameInset * 2)
  screen:fillRect(frameX, frameY, frameW, frameH, colors.yellow)
  screen:fillRect(frameX + 1, frameY + 1, frameW - 2, frameH - 2, colors.gray)
  screen:fillRect(frameX + 2, frameY + 2, frameW - 4, frameH - 4, colors.black)

  -- Draw 3 reels
  for i = 1, 3 do
    local x = REEL_START_X + (i - 1) * (REEL_W + REEL_GAP)
    local sym = result[i]
    local hl = highlights and highlights[i]
    drawReelCell(x, REEL_Y, sym, hl)
  end

  -- Pay line arrows (left and right of the reels)
  local payLineY = REEL_Y + floor(REEL_H / 2)
  screen:fillRect(frameX - scale.edgePad, payLineY - 1, scale.edgePad, 3, colors.red)
  screen:fillRect(frameX + frameW, payLineY - 1, scale.edgePad, 3, colors.red)

  -- Status text below machine frame
  if statusText then
    local stw = ui.getTextSize(statusText.text)
    ui.safeDrawText(screen, statusText.text, font, floor((width - stw) / 2),
                    frameY + frameH + scale.sectionGap, statusText.color)
  end

  screen:output()
end

-----------------------------------------------------
-- Spin animation
-----------------------------------------------------
local function animateSpin(finalResult, currentBet)
  local spinTicks = cfg.REEL_SPIN_TICKS
  local maxTicks = spinTicks[3]
  local display = { SYMBOLS[1], SYMBOLS[1], SYMBOLS[1] }

  for tick = 1, maxTicks do
    for i = 1, 3 do
      if tick <= spinTicks[i] then
        -- Still spinning: pick random symbol
        display[i] = SYMBOLS[random(1, #SYMBOLS)]
      else
        -- Stopped: show final
        display[i] = finalResult[i]
      end
    end

    drawMachine(display, nil, nil, currentBet)

    -- Play a tick sound for the last few frames of each reel stopping
    for i = 1, 3 do
      if tick == spinTicks[i] then
        sound.play(sound.SOUNDS.CARD_PLACE, 0.5)
      end
    end

    os.sleep(cfg.SPIN_FRAME_DELAY)
  end

  -- Brief pause before showing result
  os.sleep(0.2)
end

-----------------------------------------------------
-- Evaluate payout
-----------------------------------------------------
local function evaluateResult(result, bet)
  local s1, s2, s3 = result[1].id, result[2].id, result[3].id

  -- Three of a kind
  if s1 == s2 and s2 == s3 then
    local mult = PAYOUTS[s1] or 2
    local winnings = max(0, bet * (mult - 1))
    local label = s1 == "7" and "!!! JACKPOT !!!" or "THREE " .. result[1].label .. " !!!"
    return winnings, label, true, mult == 1
  end

  -- Two of a kind (any position)
  local pairs = {}
  if s1 == s2 then pairs[#pairs + 1] = s1 end
  if s1 == s3 then pairs[#pairs + 1] = s1 end
  if s2 == s3 then pairs[#pairs + 1] = s2 end

  if #pairs > 0 then
    local sym = pairs[1]
    local mult = TWO_OF_A_KIND_PAYOUTS[sym] or 0
    if mult > 0 then
      local winnings = max(0, bet * (mult - 1))
      return winnings, "Two " .. sym .. "s!", false, mult == 1
    end
  end

  -- Any two cherries
  local cherryCount = 0
  if s1 == "cherry" then cherryCount = cherryCount + 1 end
  if s2 == "cherry" then cherryCount = cherryCount + 1 end
  if s3 == "cherry" then cherryCount = cherryCount + 1 end
  if cherryCount >= 2 and cfg.ANY_TWO_CHERRY_MULT > 0 then
    local winnings = max(0, bet * (cfg.ANY_TWO_CHERRY_MULT - 1))
    return winnings, "Cherries!", false, cfg.ANY_TWO_CHERRY_MULT == 1
  end

  return 0, nil, false, false
end

-----------------------------------------------------
-- Result helpers
-----------------------------------------------------
local function buildResultHighlights(result)
  local highlights = { false, false, false }
  local s1, s2, s3 = result[1].id, result[2].id, result[3].id

  if s1 == s2 then
    highlights[1], highlights[2] = true, true
  end
  if s1 == s3 then
    highlights[1], highlights[3] = true, true
  end
  if s2 == s3 then
    highlights[2], highlights[3] = true, true
  end

  if highlights[1] or highlights[2] or highlights[3] then
    return highlights
  end

  return nil
end

local function canReplayCurrentBet(currentBet)
  if currentBet <= 0 then
    return false, "Place a new bet."
  end

  if currency.getPlayerBalance() < currentBet then
    return false, "Lower the bet to spin again."
  end

  if hostBankBalance and cfg.HOST_COVERAGE_MULT and cfg.HOST_COVERAGE_MULT > 1 then
    local needed = currentBet * (cfg.HOST_COVERAGE_MULT - 1)
    if hostBankBalance < needed then
      return false, "House limit changed. Pick a new bet."
    end
  end

  if getMaxBet() < currentBet then
    return false, "House limit changed. Pick a new bet."
  end

  return true
end

local function waitForReplayChoice(result, highlights, statusText, currentBet)
  local metrics = ui.getMetrics()
  local centerX = floor(width / 2)
  local buttonY = metrics.footerButtonY
  local sessionPlayer = currency.getAuthenticatedPlayerName() or currency.getPlayerName()
  local lastActivityTime = epoch("local")
  local timerID = nil
  local choice = nil

  local buttonTexts = {
    ui.getTextSize("ROLL AGAIN"),
    ui.getTextSize("CHANGE BET"),
  }
  local buttonWidth = metrics:fixedButtonWidth(buttonTexts, 4)

  while not choice do
    local replayAvailable, replayHint = canReplayCurrentBet(currentBet)
    local hintText = replayAvailable and "Touch ROLL AGAIN to spin the same bet." or replayHint
    local hintColor = replayAvailable and colors.lightGray or colors.orange
    local hintWidth = ui.getTextSize(hintText)
    local hintY = max(TITLE_BAR_H + scale.smallGap, buttonY - metrics.lineHeight - metrics.smallGap)

    drawMachine(result, highlights, statusText, currentBet)
    ui.safeDrawText(screen, hintText, font, max(0, floor((width - hintWidth) / 2)), hintY, hintColor)

    ui.clearButtons()
    ui.layoutButtonGrid(screen, {
      {
        {
          text = "ROLL AGAIN",
          color = replayAvailable and colors.magenta or colors.gray,
          width = buttonWidth,
          func = function()
            if replayAvailable then
              choice = "replay"
              return
            end
            sound.play(sound.SOUNDS.ERROR)
            ui.displayCenteredMessage(screen, replayHint, colors.orange, 1)
            choice = "bet"
          end,
        },
        {
          text = "CHANGE BET",
          color = colors.orange,
          width = buttonWidth,
          func = function()
            choice = "bet"
          end,
        },
      },
    }, centerX, buttonY)
    screen:output()

    if timerID then
      os.cancelTimer(timerID)
    end
    timerID = os.startTimer(0.5)

    while not choice do
      local event, side, px, py = os.pullEvent()
      if event == "monitor_touch" then
        if sessionPlayer then
          local sessionInfo = currency.getSessionInfo and currency.getSessionInfo() or nil
          local currentPlayer = (currency.getLivePlayerName and currency.getLivePlayerName())
            or ((sessionInfo and sessionInfo.playerName) or nil)
          if currentPlayer and currentPlayer ~= sessionPlayer then
            ui.displayCenteredMessage(screen, "Game in use by " .. sessionPlayer, colors.red, 1.5)
            break
          end
        end

        lastActivityTime = epoch("local")
        if px and py then
          local cb = ui.checkButtonHit(px, py)
          if cb then
            cb()
            break
          end
        end
      elseif event == "timer" and side == timerID then
        if (epoch("local") - lastActivityTime) > cfg.INACTIVITY_TIMEOUT then
          choice = "bet"
        end
        break
      end
    end
  end

  if timerID then
    os.cancelTimer(timerID)
  end
  ui.clearButtons()

  return choice == "replay"
end

-----------------------------------------------------
-- Win display
-----------------------------------------------------
local function displayWin(result, winAmount, label, isJackpot, currentBet)
  local highlights = buildResultHighlights(result)
  local clr = isJackpot and colors.red or colors.lime
  local winText = label .. "  +" .. currency.formatTokens(winAmount)
  local status = {
    text = winText,
    color = clr,
  }

  -- Flash effect
  local flashes = isJackpot and 8 or 4
  for flash = 1, flashes do
    local showHighlight = (flash % 2 == 1)
    local flashStatus = {
      text = winText,
      color = showHighlight and clr or colors.yellow,
    }
    drawMachine(result, showHighlight and highlights or nil, flashStatus, currentBet)
    if isJackpot then
      sound.play(sound.SOUNDS.SUCCESS, 1.0)
    elseif flash == 1 then
      sound.play(sound.SOUNDS.SUCCESS, 0.8)
    end
    os.sleep(isJackpot and 0.35 or 0.25)
  end

  -- Hold final result
  drawMachine(result, highlights, status, currentBet)
  return highlights, status
end

local function displayLoss(result, currentBet)
  local status = {
    text = "No match... Try again!",
    color = colors.lightGray,
  }
  drawMachine(result, nil, status, currentBet)
  sound.play(sound.SOUNDS.FAIL, 0.4)
  return nil, status
end

local function displayPush(result, label, currentBet)
  local highlights = buildResultHighlights(result)
  local status = {
    text = label .. "  PUSH",
    color = colors.cyan,
  }
  drawMachine(result, highlights, status, currentBet)
  sound.play(sound.SOUNDS.PUSH, 0.5)
  return highlights, status
end

-----------------------------------------------------
-- One round of slots
-----------------------------------------------------
local function slotsRound(currentBet, immediateSpin)
  recovery.saveBet(currentBet)

  -- Show idle machine then spin
  local idleResult = { SYMBOLS[random(1, #SYMBOLS)], SYMBOLS[random(1, #SYMBOLS)], SYMBOLS[random(1, #SYMBOLS)] }

  if not AUTO_PLAY and not immediateSpin then
    drawMachine(idleResult, nil, {
      text = ">>> Touch to SPIN! <<<",
      color = colors.lime,
    }, currentBet)

    -- Wait for any touch on the monitor
    ui.waitForMonitorTouch()
  else
    os.sleep(cfg.AUTO_PLAY_DELAY)
  end

  -- Determine result
  local result = { spinReel(reels[1]), spinReel(reels[2]), spinReel(reels[3]) }

  -- Play spin sound
  sound.play(sound.SOUNDS.START, 0.6)

  -- Animate
  animateSpin(result, currentBet)

  -- Evaluate
  local winAmount, label, isJackpot, isPush = evaluateResult(result, currentBet)
  local resultHighlights = nil
  local resultStatus = nil

  if isPush then
    resultHighlights, resultStatus = displayPush(result, label or "Pair", currentBet)
    dbg("PUSH: " .. tostring(label))
  elseif winAmount > 0 then
    if not currency.payout(winAmount, isJackpot and "Slots: jackpot payout" or "Slots: payout") then
      alert.send("CRITICAL: Failed to pay " .. winAmount .. " tokens (slots)")
    end
    resultHighlights, resultStatus = displayWin(result, winAmount, label, isJackpot, currentBet)
    dbg("WIN: " .. label .. " net=" .. winAmount)
  else
    local charged = currency.charge(currentBet, "Slots: loss")
    if not charged then
      alert.send("CRITICAL: Failed to charge " .. currentBet .. " tokens (slots)")
    end
    resultHighlights, resultStatus = displayLoss(result, currentBet)
    dbg("LOSS")
  end

  -- Update host balance
  hostBankBalance = currency.getHostBalance()

  recovery.clearBet()

  if not AUTO_PLAY then
    return waitForReplayChoice(result, resultHighlights, resultStatus, currentBet)
  end

  return false
end

-----------------------------------------------------
-- Bet selection
-----------------------------------------------------
local function betSelection()
  return betting.runBetScreen(screen, {
    maxBet                 = getMaxBet(),
    gameName               = "Slots",
    confirmLabel           = "SPIN",
    title                  = "PLACE YOUR BET",
    inactivityTimeout      = cfg.INACTIVITY_TIMEOUT,
    hostBalance            = hostBankBalance,
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
  })
end

-----------------------------------------------------
-- Main game loop
-----------------------------------------------------
local function main()
  dbg("Slots starting up")
  refreshPlayer()
  drawPlayerOverlay()

  -- Recover from crash if needed
  recovery.recoverBet(true)

  while true do
    updateAutoPlay()
    refreshPlayer()

    local currentBet = nil
    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      currentBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if currentBet <= 0 then
        dbg("Auto-play: insufficient funds, pausing")
        os.sleep(2)
      else
        slotsRound(currentBet)
      end
    else
      drawPlayerOverlay()
      local selectedBet = betSelection()
      if selectedBet and selectedBet > 0 then
        local currentBet = selectedBet
        local immediateSpin = false
        repeat
          updateAutoPlay()
          if AUTO_PLAY then
            break
          end
          immediateSpin = slotsRound(currentBet, immediateSpin)
        until not immediateSpin
      end
    end

    os.sleep(0)
  end
end

-----------------------------------------------------
-- Entry point with safe runner
-----------------------------------------------------
local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
