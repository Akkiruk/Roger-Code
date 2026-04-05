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
local replayPrompt = require("lib.replay_prompt")
local settlement = require("lib.round_settlement")

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

-----------------------------------------------------
-- Engagement feature config & state
-----------------------------------------------------
local GAMBLE_CFG    = cfg.GAMBLE or {}
local NEAR_MISS_CFG = cfg.NEAR_MISS or {}

local function getMaxBet()
  return currency.getMaxBetLimit(hostBankBalance, cfg.MAX_BET_PERCENT, cfg.HOST_COVERAGE_MULT)
end

-----------------------------------------------------
-- Player detection
-----------------------------------------------------
local function refreshPlayer()
  return env.refreshPlayer()
end

local function drawPlayerOverlay()
  env.drawPlayerOverlay()
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
local BET_Y      = TITLE_Y + scale.lineHeight + scale.smallGap
local HEADER_BAR_H = max(scale.buttonHeight, BET_Y + scale.lineHeight + scale.smallGap)
local REEL_GAP   = scale:scaledX(LO.REEL_SPACING, 1, 8)
local desiredReelW = scale:scaledX(LO.REEL_WIDTH, 10, 32)
local availableReelW = width - (scale.edgePad * 2) - (REEL_GAP * 2)
local REEL_W = max(10, floor(availableReelW / 3))
REEL_W = min(REEL_W, max(maxArtW + (scale.buttonPadX * 2) + 2, desiredReelW))
local minReelH = max(12, maxArtH + scale.lineHeight + 4)
local desiredReelH = scale:scaledY(LO.REEL_HEIGHT, minReelH, height)
local availableReelH = max(minReelH, height - HEADER_BAR_H - scale.messageLineHeight - (scale.edgePad * 4))
local REEL_H = min(availableReelH, max(minReelH, desiredReelH))
local TOTAL_W    = REEL_W * 3 + REEL_GAP * 2
local REEL_START_X = max(0, floor((width - TOTAL_W) / 2))
local REEL_INNER_W = REEL_W - 2
local REEL_INNER_H = REEL_H - 2
local symbolSurfaceCache = {}

local function getMachineLayout(showStatus, showFooterControls)
  local metrics = ui.getMetrics()
  local frameInset = max(2, scale.edgePad + 1)
  local frameH = REEL_H + (frameInset * 2)
  local buttonY = metrics.footerButtonY
  local hintY = nil
  local statusY = nil
  local machineBottom = height - scale.edgePad

  if showFooterControls then
    hintY = max(HEADER_BAR_H + scale.sectionGap, buttonY - scale.lineHeight - scale.smallGap)
    machineBottom = hintY - scale.smallGap
  end

  if showStatus then
    statusY = machineBottom - scale.lineHeight
    machineBottom = statusY - scale.smallGap
  end

  local minFrameY = HEADER_BAR_H + scale.sectionGap
  local maxFrameY = max(minFrameY, machineBottom - frameH)
  local frameY = floor((minFrameY + maxFrameY) / 2)
  local reelY = frameY + frameInset

  return {
    buttonY = buttonY,
    frameH = frameH,
    frameInset = frameInset,
    frameW = TOTAL_W + (frameInset * 2),
    frameX = REEL_START_X - frameInset,
    frameY = frameY,
    hintY = hintY,
    reelY = reelY,
    statusY = statusY,
  }
end

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
local function drawMachine(result, highlights, statusText, currentBet, animationState, opts)
  opts = opts or {}
  local machineLayout = getMachineLayout(statusText ~= nil, opts.showFooterControls == true)

  screen:clear(LO.TABLE_COLOR)

  -- Title bar background
  screen:fillRect(0, 0, width, HEADER_BAR_H, colors.black)
  local title = "SLOT MACHINE"
  local ttw = ui.getTextSize(title)
  ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), TITLE_Y, colors.yellow)

  -- Bet display
  if currentBet then
    local betStr = "Bet: " .. currency.formatTokens(currentBet)
    ui.safeDrawText(screen, betStr, font, scale.edgePad, BET_Y, colors.lightGray)
  end

  -- Decorative gold trim below title
  screen:fillRect(0, HEADER_BAR_H, width, 1, colors.yellow)

  -- Machine outer frame (gold border > gray > inner black)
  local frameX = machineLayout.frameX
  local frameY = machineLayout.frameY
  local frameW = machineLayout.frameW
  local frameH = machineLayout.frameH
  screen:fillRect(frameX, frameY, frameW, frameH, colors.yellow)
  screen:fillRect(frameX + 1, frameY + 1, frameW - 2, frameH - 2, colors.gray)
  screen:fillRect(frameX + 2, frameY + 2, frameW - 4, frameH - 4, colors.black)

  -- Draw 3 reels
  for i = 1, 3 do
    local x = REEL_START_X + (i - 1) * (REEL_W + REEL_GAP)
    local reelAnim = animationState and animationState[i]
    if reelAnim then
      drawAnimatedReel(x, machineLayout.reelY, reelAnim)
    else
      local sym = result[i]
      local hl = highlights and highlights[i]
      drawReelCell(x, machineLayout.reelY, sym, hl)
    end
  end

  -- Pay line arrows (left and right of the reels)
  local payLineY = machineLayout.reelY + floor(REEL_H / 2)
  screen:fillRect(frameX - scale.edgePad, payLineY - 1, scale.edgePad, 3, colors.red)
  screen:fillRect(frameX + frameW, payLineY - 1, scale.edgePad, 3, colors.red)

  -- Status text below machine frame
  if statusText then
    local stw = ui.getTextSize(statusText.text)
    ui.safeDrawText(screen, statusText.text, font, floor((width - stw) / 2), machineLayout.statusY, statusText.color)
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

  local protectedHostBalance = currency.getProtectedHostBalance(hostBankBalance)
  if protectedHostBalance and cfg.HOST_COVERAGE_MULT and cfg.HOST_COVERAGE_MULT > 1 then
    local needed = currentBet * (cfg.HOST_COVERAGE_MULT - 1)
    if protectedHostBalance < needed then
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

  local buttonTexts = {
    ui.getTextSize("ROLL AGAIN"),
    ui.getTextSize("CHANGE BET"),
  }
  local buttonWidth = metrics:fixedButtonWidth(buttonTexts, 4)
  local machineLayout = getMachineLayout(statusText ~= nil, true)
  buttonY = machineLayout.buttonY

  local choice = replayPrompt.waitForChoice(screen, {
    render = function()
      drawMachine(result, highlights, statusText, currentBet, nil, {
        showFooterControls = true,
      })
    end,
    hint = function()
      local replayAvailable, replayHint = canReplayCurrentBet(currentBet)
      if replayAvailable then
        return "Touch ROLL AGAIN to spin the same bet.", colors.lightGray
      end
      return replayHint, colors.orange
    end,
    hint_y = machineLayout.hintY,
    buttons = {
      {
        {
          id = "replay",
          text = "ROLL AGAIN",
          color = colors.magenta,
          width = buttonWidth,
          enabled = function()
            return canReplayCurrentBet(currentBet)
          end,
          onChoose = function()
            drainHeldMonitorTouches(0.25)
          end,
          onDisabled = function()
            sound.play(sound.SOUNDS.ERROR)
          end,
          disabled_message = "Lower the bet or change it before spinning again.",
        },
        {
          id = "bet",
          text = "CHANGE BET",
          color = colors.orange,
          width = buttonWidth,
        },
      },
    },
    center_x = centerX,
    button_y = buttonY,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    poll_seconds = 0.5,
    onTimeout = function()
      return "bet"
    end,
  })

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
-- Engagement: near-miss detection
-----------------------------------------------------
local function detectNearMiss(result)
  if not NEAR_MISS_CFG.ENABLED then return nil end
  local lookup = {}
  for _, id in ipairs(NEAR_MISS_CFG.SYMBOLS or {}) do
    lookup[id] = true
  end
  local s1, s2, s3 = result[1].id, result[2].id, result[3].id
  if s1 == s2 and s1 ~= s3 and lookup[s1] then return result[1] end
  if s1 == s3 and s1 ~= s2 and lookup[s1] then return result[1] end
  if s2 == s3 and s2 ~= s1 and lookup[s2] then return result[2] end
  return nil
end

-----------------------------------------------------
-- Engagement: gamble / double-up
-----------------------------------------------------
local function waitForGambleChoice(result, highlights, gambleStake, currentBet, round)
  local metrics = ui.getMetrics()
  local centerX = floor(width / 2)
  local machineLayout = getMachineLayout(true, true)
  local stakeStr = currency.formatTokens(gambleStake)
  local doubleStr = currency.formatTokens(gambleStake * 2)
  local statusText = {
    text = "Gamble " .. stakeStr .. " to win " .. doubleStr .. "?",
    color = colors.yellow,
  }

  local sizeList = { ui.getTextSize("GAMBLE"), ui.getTextSize("COLLECT") }
  local buttonWidth = metrics:fixedButtonWidth(sizeList, 4)

  local choice = replayPrompt.waitForChoice(screen, {
    render = function()
      drawMachine(result, highlights, statusText, currentBet, nil, {
        showFooterControls = true,
      })
    end,
    hint = function()
      return "Double or nothing! Round " .. round .. "/" .. (GAMBLE_CFG.MAX_ROUNDS or 3), colors.yellow
    end,
    hint_y = machineLayout.hintY,
    buttons = {
      {
        {
          id = "gamble",
          text = "GAMBLE",
          color = colors.red,
          width = buttonWidth,
        },
        {
          id = "collect",
          text = "COLLECT",
          color = colors.lime,
          width = buttonWidth,
        },
      },
    },
    center_x = centerX,
    button_y = machineLayout.buttonY,
    inactivity_timeout = GAMBLE_CFG.TIMEOUT or 15000,
    onTimeout = function()
      return "collect"
    end,
  })

  return choice
end

local function animateGambleFlip(result, highlights, currentBet, won, gambleStake)
  local winText  = "WIN +" .. currency.formatTokens(gambleStake)
  local loseText = "LOSE -" .. currency.formatTokens(gambleStake)
  local frames = 12

  for i = 1, frames do
    local delay = 0.08 + (i / frames) * 0.15
    local showWin = (i % 2 == 1)
    if i == frames then showWin = won end
    local status = showWin
      and { text = winText, color = colors.lime }
      or  { text = loseText, color = colors.red }
    drawMachine(result, highlights, status, currentBet)
    sound.play(sound.SOUNDS.BOOT, 0.15)
    os.sleep(delay)
  end

  if won then
    drawMachine(result, highlights, {
      text = "GAMBLE WIN! +" .. currency.formatTokens(gambleStake),
      color = colors.lime,
    }, currentBet)
    sound.play(sound.SOUNDS.SUCCESS, 0.9)
  else
    drawMachine(result, highlights, {
      text = "GAMBLE LOST!",
      color = colors.red,
    }, currentBet)
    sound.play(sound.SOUNDS.FAIL, 0.6)
  end
  os.sleep(1.0)
end

local function runGamble(result, highlights, currentBet, winAmount)
  if not GAMBLE_CFG.ENABLED then return end
  if winAmount <= 0 then return end

  local gambleStake = winAmount

  for round = 1, (GAMBLE_CFG.MAX_ROUNDS or 3) do
    hostBankBalance = currency.getHostBalance()
    local protectedHost = currency.getProtectedHostBalance(hostBankBalance)
    if not protectedHost or protectedHost < gambleStake then
      break
    end

    local choice = waitForGambleChoice(result, highlights, gambleStake, currentBet, round)
    if choice ~= "gamble" then
      break
    end

    drainHeldMonitorTouches(0.15)
    local won = random(1, 100) <= (GAMBLE_CFG.WIN_CHANCE or 50)
    animateGambleFlip(result, highlights, currentBet, won, gambleStake)

    if won then
      if not settlement.applyNetChange(gambleStake, {
        winReason = "Slots: gamble win",
        failurePrefix = "CRITICAL",
      }) then
        alert.send("CRITICAL: Failed to pay gamble win " .. gambleStake)
        break
      end
      gambleStake = gambleStake * 2
    else
      settlement.applyNetChange(-gambleStake, {
        lossReason = "Slots: gamble loss",
        failurePrefix = "CRITICAL",
      })
      break
    end

    hostBankBalance = currency.getHostBalance()
  end
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
    -- Near-miss annotation (2-of-a-kind close to a triple)
    local nearMissSym = detectNearMiss(result)
    if nearMissSym then
      local tripleVal = currentBet * ((PAYOUTS[nearMissSym.id] or 2) - 1)
      label = label .. "  Almost " .. currency.formatTokens(tripleVal) .. "!"
    end

    if not settlement.applyNetChange(winAmount, {
      winReason = isJackpot and "Slots: jackpot payout" or "Slots: payout",
      failurePrefix = "CRITICAL",
    }) then
      alert.send("CRITICAL: Failed to pay " .. winAmount .. " tokens (slots)")
    end
    resultHighlights, resultStatus = displayWin(result, winAmount, label, isJackpot, currentBet)

    if not AUTO_PLAY then
      runGamble(result, resultHighlights, currentBet, winAmount)
    end

    dbg("WIN: " .. label .. " net=" .. winAmount)
  else
    local charged = settlement.applyNetChange(-currentBet, {
      lossReason = "Slots: loss",
      failurePrefix = "CRITICAL",
    })
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
    hostBalance            = currency.getProtectedHostBalance(hostBankBalance),
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
