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
local REEL_INNER_W = REEL_W - 2
local REEL_INNER_H = REEL_H - 2
local symbolSurfaceCache = {}

-----------------------------------------------------
-- Spin a random result from a reel
-----------------------------------------------------
local function spinReel(reel)
  return reel[random(1, #reel)]
end

local function renderSymbolSurface(target, sym, highlight)
  local bg = highlight and colors.white or LO.REEL_BG
  local textClr = highlight and colors.black or sym.color

  target:fillRect(0, 0, REEL_INNER_W, REEL_INNER_H, bg)

  if sym.artSurface then
    local art = sym.artSurface
    local labelH = max(6, scale.lineHeight - 1)
    local artSpace = max(1, REEL_INNER_H - labelH)
    local ax = floor((REEL_INNER_W - art.width) / 2)
    local ay = floor((artSpace - art.height) / 2)
    target:drawSurface(art, ax, ay)

    local label = sym.label
    local tw = ui.getTextSize(label)
    local tx = floor((REEL_W - tw) / 2) - 1
    local ty = artSpace
    ui.safeDrawText(target, label, font, tx, ty, textClr)
  else
    local label = sym.label
    local tw = ui.getTextSize(label)
    local tx = floor((REEL_W - tw) / 2) - 1
    local ty = floor((REEL_H - scale.fontHeight) / 2) - 1
    ui.safeDrawText(target, label, font, tx, ty, textClr)
  end
end

local function getSymbolSurface(sym, highlight)
  local key = sym.id .. (highlight and "#hl" or "#base")
  local cached = symbolSurfaceCache[key]
  if cached then
    return cached
  end

  local surf = surfaceLib.create(REEL_INNER_W, REEL_INNER_H)
  renderSymbolSurface(surf, sym, highlight)
  symbolSurfaceCache[key] = surf
  return surf
end

local function drawReelShell(target, x, y, highlight)
  local bg = highlight and colors.white or LO.REEL_BG
  local borderClr = highlight and colors.yellow or colors.gray
  target:fillRect(x, y, REEL_W, REEL_H, bg)
  target:fillRect(x, y, REEL_W, 1, borderClr)
  target:fillRect(x, y + REEL_H - 1, REEL_W, 1, borderClr)
  target:fillRect(x, y, 1, REEL_H, borderClr)
  target:fillRect(x + REEL_W - 1, y, 1, REEL_H, borderClr)
end

local function drawReelGlass(target, x, y, highlight)
  local innerX = x + 1
  local innerY = y + 1
  local sheen = highlight and colors.lightGray or colors.gray
  local shadow = highlight and colors.gray or colors.black

  target:fillRect(innerX, innerY, REEL_INNER_W, 1, sheen)
  target:fillRect(innerX, innerY + REEL_INNER_H - 1, REEL_INNER_W, 1, shadow)
  if REEL_INNER_H > 6 then
    target:fillRect(innerX, innerY + 1, REEL_INNER_W, 1, sheen)
  end
end

-----------------------------------------------------
-- Draw a single reel cell
-----------------------------------------------------
local function drawReelCell(x, y, sym, highlight)
  drawReelShell(screen, x, y, highlight)
  screen:drawSurface(getSymbolSurface(sym, highlight), x + 1, y + 1)
  drawReelGlass(screen, x, y, highlight)
end

local function drawAnimatedReel(x, y, state)
  local offset = max(0, min(REEL_INNER_H - 1, state.offset or 0))
  local currentSurface = getSymbolSurface(state.current, false)
  local nextSurface = getSymbolSurface(state.next or state.current, false)
  local visibleCurrent = REEL_INNER_H - offset

  drawReelShell(screen, x, y, false)

  if visibleCurrent > 0 then
    screen:drawSurface(currentSurface, x + 1, y + 1, REEL_INNER_W, visibleCurrent, 0, offset, REEL_INNER_W, visibleCurrent)
  end
  if offset > 0 then
    screen:drawSurface(nextSurface, x + 1, y + 1 + visibleCurrent, REEL_INNER_W, offset, 0, 0, REEL_INNER_W, offset)
  end

  drawReelGlass(screen, x, y, false)
end

-----------------------------------------------------
-- Draw the full machine frame
-----------------------------------------------------
local function drawMachine(result, highlights, statusText, currentBet, animationState)
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
    local reelAnim = animationState and animationState[i]
    if reelAnim then
      drawAnimatedReel(x, REEL_Y, reelAnim)
    else
      local sym = result[i]
      local hl = highlights and highlights[i]
      drawReelCell(x, REEL_Y, sym, hl)
    end
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
local function pickDifferentSymbol(previous, avoid)
  local candidate = nil

  for _ = 1, #SYMBOLS * 2 do
    candidate = SYMBOLS[random(1, #SYMBOLS)]
    if candidate ~= previous and candidate ~= avoid then
      return candidate
    end
  end

  return avoid or previous or SYMBOLS[1]
end

local function buildSpinSequence(startSym, finalSym, totalSteps)
  local sequence = { startSym or pickDifferentSymbol(nil, finalSym) }
  local previous = sequence[1]

  for step = 2, totalSteps - 1 do
    local avoid = step >= totalSteps - 2 and finalSym or nil
    local nextSym = pickDifferentSymbol(previous, avoid)
    sequence[#sequence + 1] = nextSym
    previous = nextSym
  end

  sequence[#sequence + 1] = finalSym
  return sequence
end

local function easeOutCubic(progress)
  local inverse = 1 - progress
  return 1 - (inverse * inverse * inverse)
end

local function animateSpin(finalResult, currentBet, initialDisplay)
  local spinTicks = cfg.REEL_SPIN_TICKS
  local startDisplay = initialDisplay or { SYMBOLS[1], SYMBOLS[1], SYMBOLS[1] }
  local frameDelay = min(0.03, max(0.02, cfg.SPIN_FRAME_DELAY * 0.75))
  local startTime = epoch("local")
  local animationState = {}
  local reelPlans = {}
  local allComplete = false

  for i = 1, 3 do
    local durationMs = max(450, floor(spinTicks[i] * cfg.SPIN_FRAME_DELAY * 1000 * 1.45))
    local totalSteps = max(12, spinTicks[i] + 10)
    reelPlans[i] = {
      durationMs = durationMs,
      totalSteps = totalSteps,
      sequence = buildSpinSequence(startDisplay[i], finalResult[i], totalSteps),
      lastIndex = 1,
      stopped = false,
    }
  end

  while not allComplete do
    allComplete = true
    local elapsed = epoch("local") - startTime

    for i = 1, 3 do
      local plan = reelPlans[i]
      local progress = min(1, elapsed / plan.durationMs)
      local eased = easeOutCubic(progress)
      local stepFloat = eased * (plan.totalSteps - 1)
      local baseIndex = floor(stepFloat)
      local currentIndex = min(plan.totalSteps, baseIndex + 1)
      local nextIndex = min(plan.totalSteps, currentIndex + 1)
      local fraction = stepFloat - baseIndex
      local offset = floor(fraction * REEL_INNER_H)

      if currentIndex >= plan.totalSteps then
        nextIndex = plan.totalSteps
        offset = 0
      else
        allComplete = false
      end

      animationState[i] = {
        current = plan.sequence[currentIndex],
        next = plan.sequence[nextIndex],
        offset = offset,
      }

      if currentIndex ~= plan.lastIndex then
        if currentIndex >= plan.totalSteps - 3 then
          sound.play(sound.SOUNDS.CARD_PLACE, 0.35)
        elseif currentIndex % 4 == 0 then
          sound.play(sound.SOUNDS.BOOT, 0.1)
        end
        plan.lastIndex = currentIndex
      end

      if progress >= 1 and not plan.stopped then
        sound.play(sound.SOUNDS.CARD_PLACE, 0.5)
        plan.stopped = true
      end
    end

    drawMachine(finalResult, nil, nil, currentBet, animationState)

    if not allComplete then
      os.sleep(frameDelay)
    end
  end

  -- Brief pause before showing result
  drawMachine(finalResult, nil, nil, currentBet)
  os.sleep(0.15)
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

local function drainHeldMonitorTouches(duration)
  local timerID = os.startTimer(duration or 0.25)

  while true do
    local event, side = os.pullEvent()
    if event == "timer" and side == timerID then
      return
    end
  end
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
              drainHeldMonitorTouches(0.25)
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
  animateSpin(result, currentBet, idleResult)

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
