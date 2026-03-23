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

-- Pre-load pixel art for each symbol
for _, sym in ipairs(SYMBOLS) do
  if sym.art then
    local ok, art = pcall(surfaceLib.load, sym.art)
    if ok and art then
      sym.artSurface = art
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
local REEL_W     = LO.REEL_WIDTH
local REEL_H     = LO.REEL_HEIGHT
local REEL_GAP   = LO.REEL_SPACING
local TOTAL_W    = REEL_W * 3 + REEL_GAP * 2
local REEL_START_X = floor((width - TOTAL_W) / 2)
local REEL_Y     = LO.REEL_Y

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
    local labelH = 6
    local artSpace = ih - labelH
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
    local ty = y + floor((REEL_H - 7) / 2)
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
  screen:fillRect(0, 0, width, 7, colors.black)
  local title = "SLOT MACHINE"
  local ttw = ui.getTextSize(title)
  ui.safeDrawText(screen, title, font, floor((width - ttw) / 2), LO.TITLE_Y, colors.yellow)

  -- Bet display
  if currentBet then
    local betStr = "Bet: " .. currency.formatTokens(currentBet)
    ui.safeDrawText(screen, betStr, font, 2, LO.TITLE_Y, colors.lightGray)
  end

  -- Decorative gold trim below title
  screen:fillRect(0, 7, width, 1, colors.yellow)

  -- Machine outer frame (gold border > gray > inner black)
  local frameX = REEL_START_X - 3
  local frameY = REEL_Y - 3
  local frameW = TOTAL_W + 6
  local frameH = REEL_H + 6
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
  screen:fillRect(frameX - 2, payLineY - 1, 2, 3, colors.red)
  screen:fillRect(frameX + frameW, payLineY - 1, 2, 3, colors.red)

  -- Status text below machine frame
  if statusText then
    local stw = ui.getTextSize(statusText.text)
    ui.safeDrawText(screen, statusText.text, font, floor((width - stw) / 2),
                    frameY + frameH + 2, statusText.color)
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
    local winnings = bet * mult
    local label = s1 == "7" and "!!! JACKPOT !!!" or "THREE " .. result[1].label .. " !!!"
    return winnings, label, true
  end

  -- Two of a kind (any position)
  local pairs = {}
  if s1 == s2 then pairs[#pairs + 1] = s1 end
  if s1 == s3 then pairs[#pairs + 1] = s1 end
  if s2 == s3 then pairs[#pairs + 1] = s2 end

  if #pairs > 0 then
    local sym = pairs[1]
    local mult = TWO_OF_A_KIND_PAYOUTS[sym] or 0
    local winnings = bet * mult
    if winnings > 0 then
      return winnings, "Two " .. sym .. "s!", false
    end
  end

  -- Any two cherries
  local cherryCount = 0
  if s1 == "cherry" then cherryCount = cherryCount + 1 end
  if s2 == "cherry" then cherryCount = cherryCount + 1 end
  if s3 == "cherry" then cherryCount = cherryCount + 1 end
  if cherryCount >= 2 and cfg.ANY_TWO_CHERRY_MULT > 0 then
    return bet * cfg.ANY_TWO_CHERRY_MULT, "Cherries!", false
  end

  return 0, nil, false
end

-----------------------------------------------------
-- Win display
-----------------------------------------------------
local function displayWin(result, winAmount, label, isJackpot, currentBet)
  local highlights = {}
  local s1, s2, s3 = result[1].id, result[2].id, result[3].id
  if s1 == s2 and s2 == s3 then
    highlights = { true, true, true }
  elseif s1 == s2 then highlights = { true, true, false }
  elseif s1 == s3 then highlights = { true, false, true }
  elseif s2 == s3 then highlights = { false, true, true }
  end

  local clr = isJackpot and colors.red or colors.lime
  local winText = label .. "  +" .. currency.formatTokens(winAmount)

  -- Flash effect
  local flashes = isJackpot and 8 or 4
  for flash = 1, flashes do
    local showHighlight = (flash % 2 == 1)
    local status = {
      text = winText,
      color = showHighlight and clr or colors.yellow,
    }
    drawMachine(result, showHighlight and highlights or nil, status, currentBet)
    if isJackpot then
      sound.play(sound.SOUNDS.SUCCESS, 1.0)
    elseif flash == 1 then
      sound.play(sound.SOUNDS.SUCCESS, 0.8)
    end
    os.sleep(isJackpot and 0.35 or 0.25)
  end

  -- Hold final result
  drawMachine(result, highlights, {
    text = winText,
    color = clr,
  }, currentBet)
  os.sleep(1.5)
end

local function displayLoss(result, currentBet)
  drawMachine(result, nil, {
    text = "No match... Try again!",
    color = colors.lightGray,
  }, currentBet)
  sound.play(sound.SOUNDS.FAIL, 0.4)
  os.sleep(1.0)
end

-----------------------------------------------------
-- One round of slots
-----------------------------------------------------
local function slotsRound(currentBet)
  recovery.saveBet(currentBet)

  -- Show idle machine then spin
  local idleResult = { SYMBOLS[random(1, #SYMBOLS)], SYMBOLS[random(1, #SYMBOLS)], SYMBOLS[random(1, #SYMBOLS)] }

  if not AUTO_PLAY then
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
  local winAmount, label, isJackpot = evaluateResult(result, currentBet)

  if winAmount > 0 then
    if not currency.payout(winAmount, isJackpot and "Slots: jackpot payout" or "Slots: payout") then
      alert.send("CRITICAL: Failed to pay " .. winAmount .. " tokens (slots)")
    end
    displayWin(result, winAmount, label, isJackpot, currentBet)
    dbg("WIN: " .. label .. " payout=" .. (currentBet + winAmount))
  else
    local charged = currency.charge(currentBet, "Slots: loss")
    if not charged then
      alert.send("CRITICAL: Failed to charge " .. currentBet .. " tokens (slots)")
    end
    displayLoss(result, currentBet)
    dbg("LOSS")
  end

  recovery.clearBet()

  -- Update host balance
  hostBankBalance = currency.getHostBalance()
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
        slotsRound(selectedBet)
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
