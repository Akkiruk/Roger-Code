-- hilo.lua
-- Hi-Lo card game for ComputerCraft casino.
-- A card is shown; guess whether the next card is HIGHER or LOWER.
-- Correct guesses build a multiplier; cash out any time or risk it all.
-- Uses shared libraries from Games/lib/.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("hilo_config")

local LO = cfg.LAYOUT
local MULTIPLIERS = cfg.MULTIPLIERS

local ostime       = os.time
local settings_get = settings.get
local r_getInput   = redstone.getInput
local epoch        = os.epoch
local max          = math.max
local min          = math.min
local ceil         = math.ceil

settings.define("hilo.debug", {
  description = "Enable debug messages for the Hi-Lo game.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("hilo.debug")
local function dbg(msg)
  if DEBUG then print(ostime(), "[HILO] " .. msg) end
end

-----------------------------------------------------
-- Shared library imports
-----------------------------------------------------
local cards      = require("lib.cards")
local currency   = require("lib.currency")
local sound      = require("lib.sound")
local ui         = require("lib.ui")
local alert      = require("lib.alert")
local recovery   = require("lib.crash_recovery")
local gameSetup  = require("lib.game_setup")
local betting    = require("lib.betting")
local cardAnim   = require("lib.card_anim")

-----------------------------------------------------
-- Auto-play state
-----------------------------------------------------
local AUTO_PLAY = false

local function updateAutoPlayFromRedstone()
  local powered = r_getInput(cfg.REDSTONE)
  if powered ~= AUTO_PLAY then
    AUTO_PLAY = powered
    dbg(AUTO_PLAY and "Auto-play ON" or "Auto-play OFF")
  end
  return AUTO_PLAY
end

-----------------------------------------------------
-- Initialize game environment
-----------------------------------------------------
recovery.configure(cfg.RECOVERY_FILE)

local env = gameSetup.init({
  monitorName     = cfg.MONITOR,
  deckCount       = cfg.DECK_COUNT,
  gameName        = cfg.GAME_NAME,
  logFile         = cfg.LOG_FILE,
  initPlayerStats = false,
})

alert.addPlannedExits({
  cfg.EXIT_CODES.INACTIVITY_TIMEOUT,
  cfg.EXIT_CODES.MAIN_MENU,
  cfg.EXIT_CODES.USER_TERMINATED,
  cfg.EXIT_CODES.PLAYER_QUIT,
})

local screen   = env.screen
local deck     = env.deck
local width    = env.width
local height   = env.height
local cardBack = env.cardBack
local font     = env.font
local scale    = env.scale

cardAnim.init(screen, cardBack)

-----------------------------------------------------
-- Host balance tracking
-----------------------------------------------------
local hostBankBalance = currency.getHostBalance()
dbg("Initial host balance: " .. hostBankBalance .. " tokens")

local function getMaxBet()
  return math.floor(hostBankBalance * cfg.MAX_BET_PERCENT)
end

-----------------------------------------------------
-- Session statistics
-----------------------------------------------------
local sessionStats = {
  rounds       = 0,
  totalBet     = 0,
  totalWon     = 0,
  netProfit    = 0,
  biggestWin   = 0,
  bestStreak   = 0,
  cashOuts     = 0,
  busts        = 0,
  sameValueLosses = 0,
}

-----------------------------------------------------
-- Player detection (shared via game_setup)
-----------------------------------------------------
local function refreshPlayer()
  return gameSetup.refreshPlayer(env)
end

local function drawPlayerOverlay()
  gameSetup.drawPlayerOverlay(env)
end

-----------------------------------------------------
-- Deck helpers
-----------------------------------------------------
local function freshDeck()
  deck = cards.buildDeck(cfg.DECK_COUNT)
  cards.shuffle(deck)
  return deck
end

local function ensureDeck()
  if #deck < cfg.MIN_CARDS_RESHUFFLE then
    dbg("Reshuffling deck")
    freshDeck()
  end
end

local function dealOne()
  ensureDeck()
  return cards.deal(deck)
end

-----------------------------------------------------
-- Card numeric value for comparison (A=14 high for Hi-Lo)
-----------------------------------------------------
local HILO_VALUES = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  ["T"] = 10, ["J"] = 11, ["Q"] = 12, ["K"] = 13, ["A"] = 14,
}

local function cardValue(cardID)
  local val = cardID:sub(1, 1)
  return HILO_VALUES[val] or 0
end

local function roundedPayout(betAmount, multiplier)
  return math.floor((betAmount * multiplier) + 0.5)
end

-----------------------------------------------------
-- Layout (computed once from screen dimensions)
-----------------------------------------------------
local deltaX   = cardBack.width + scale.cardSpacing
local centerX  = math.floor(width / 2)

-- Card positions: current card on left, next card on right
local leftCardX  = centerX - deltaX - scale.smallGap
local rightCardX = centerX + (scale.smallGap * 2)
local cardY      = scale:scaledY(LO.CARD_Y, scale.subtitleY, scale:ratioY(0.35))

-----------------------------------------------------
-- Rendering helpers
-----------------------------------------------------
local LINE_H = scale.lineHeight

local function drawCenteredLine(text, y, color)
  local tw = ui.getTextSize(text)
  ui.safeDrawText(screen, text, font, math.floor((width - tw) / 2), y, color or colors.white)
end

local function getChoiceStatusY()
  return min(height - LINE_H - scale.edgePad, cardY + cardBack.height + (scale.sectionGap * 2))
end

local function getChoiceButtonY(rowCount)
  local rows = math.max(1, rowCount or 1)
  local preferredY = getChoiceStatusY() + LINE_H + scale.sectionGap
  local footerTop = scale:buttonBlockTop(scale.footerButtonY, rows, scale.buttonRowSpacing)
  return min(preferredY, footerTop)
end

local function renderBase(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  screen:clear(LO.TABLE_COLOR)

  -- Bet and multiplier display
  local betLabel = "Bet: " .. currency.formatTokens(betAmount)
  ui.safeDrawText(screen, betLabel, font, 1, 0, colors.white)

  if round > 0 then
    local multLabel = "x" .. tostring(multiplier)
    local mw = ui.getTextSize(multLabel)
    ui.safeDrawText(screen, multLabel, font, width - mw - 1, 0, colors.yellow)
  end

  -- Round indicator
  if round > 0 then
    local roundLabel = "Round " .. round .. "/" .. cfg.MAX_ROUNDS
    drawCenteredLine(roundLabel, 0, colors.lightGray)
  end

  -- Current card (always visible)
  if currentCard then
    local img = cards.renderCard(currentCard)
    screen:drawSurface(img, leftCardX, cardY)
  end

  -- Show trail of revealed cards as value labels above
  if #revealedCards > 1 then
    local trailY = cardY - LINE_H
    local trail = ""
    for i = 1, #revealedCards - 1 do
      if i > 1 then trail = trail .. " > " end
      trail = trail .. cards.displayValue(revealedCards[i])
    end
    local tw = ui.getTextSize(trail)
    if tw < width - 4 then
      ui.safeDrawText(screen, trail, font, math.floor((width - tw) / 2), trailY, colors.lightGray)
    end
  end

  -- Status text
  if statusText then
    local statusY = getChoiceStatusY()
    drawCenteredLine(statusText, statusY, colors.yellow)
  end
end

local function renderScreen(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  renderBase(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  screen:output()
end

-----------------------------------------------------
-- Tutorial / How to play screens
-----------------------------------------------------
local TUTORIAL_PAGES = {
  {
    title = "HOW TO PLAY",
    lines = {
      { text = "A card is shown.",       color = colors.white },
      { text = "Guess if the next",      color = colors.white },
      { text = "card is HIGHER",         color = colors.cyan },
      { text = "or LOWER.",              color = colors.red },
      { text = "",                        color = colors.white },
      { text = "Correct = bigger",       color = colors.yellow },
      { text = "multiplier!",            color = colors.yellow },
    },
  },
  {
    title = "CASH OUT",
    lines = {
      { text = "After each correct",     color = colors.white },
      { text = "guess, you can:",        color = colors.white },
      { text = "",                        color = colors.white },
      { text = "CASH OUT to keep",       color = colors.lime },
      { text = "your winnings, or",      color = colors.lime },
      { text = "KEEP GOING for a",       color = colors.yellow },
      { text = "bigger payout!",         color = colors.yellow },
    },
  },
  {
    title = "CARD ORDER",
    lines = {
      { text = "2 is lowest",            color = colors.lightGray },
      { text = "Ace is highest",         color = colors.cyan },
      { text = "",                        color = colors.white },
      { text = "Equal cards lose",       color = colors.yellow },
      { text = "(streak ends)",          color = colors.yellow },
      { text = "",                        color = colors.white },
      { text = "Up to x15 payout!",      color = colors.lime },
    },
  },
}

local function showTutorial()
  local page = 1
  while true do
    screen:clear(LO.TABLE_COLOR)
    local pg = TUTORIAL_PAGES[page]

    drawCenteredLine(pg.title, 1, colors.yellow)

    local indicator = "Page " .. page .. "/" .. #TUTORIAL_PAGES
    drawCenteredLine(indicator, 1 + LINE_H, colors.lightGray)

    -- Count non-empty content lines
    local contentLines = 0
    for _, ln in ipairs(pg.lines) do
      contentLines = contentLines + 1
    end

    -- Compute spacing to fit between header and buttons
    local contentY = 1 + LINE_H * 2 + 2
    local btnY = scale.footerButtonY
    local availH = btnY - contentY - 2
    local lineSpacing = math.min(LINE_H, math.floor(availH / math.max(contentLines, 1)))

    local lineIdx = 0
    for _, ln in ipairs(pg.lines) do
      if ln.text ~= "" then
        drawCenteredLine(ln.text, contentY + lineIdx * lineSpacing, ln.color)
      end
      lineIdx = lineIdx + 1
    end

    ui.clearButtons()
    local navRow = {}
    if page > 1 then
      table.insert(navRow, { text = "PREV", color = colors.lightGray,
        func = function() page = page - 1 end })
    end
    table.insert(navRow, { text = "BACK", color = colors.red,
      func = function() page = nil end })
    if page < #TUTORIAL_PAGES then
      table.insert(navRow, { text = "NEXT", color = colors.lime,
        func = function() page = page + 1 end })
    end
    ui.layoutButtonGrid(screen, { navRow }, centerX, btnY, scale.buttonRowSpacing, scale.buttonColGap)

    screen:output()
    ui.waitForButton(0, 0)
    if not page then return end
  end
end

-----------------------------------------------------
-- Stats display
-----------------------------------------------------
local function showStats()
  screen:clear(LO.TABLE_COLOR)
  drawCenteredLine("SESSION STATS", 1, colors.yellow)

  local y = 1 + LINE_H + 2
  local statsSpacing = math.min(LINE_H, math.floor((height - y - 10) / 9))
  local function statLine(label, value, color)
    drawCenteredLine(label .. ": " .. tostring(value), y, color or colors.white)
    y = y + statsSpacing
  end

  statLine("Rounds", sessionStats.rounds, colors.white)

  local profitColor = colors.white
  if sessionStats.netProfit > 0 then
    profitColor = colors.lime
  elseif sessionStats.netProfit < 0 then
    profitColor = colors.red
  end
  statLine("Profit", currency.formatTokens(sessionStats.netProfit), profitColor)
  statLine("Wagered", currency.formatTokens(sessionStats.totalBet), colors.white)

  if sessionStats.biggestWin > 0 then
    statLine("Best Win", currency.formatTokens(sessionStats.biggestWin), colors.lime)
  end

  y = y + 2
  statLine("Cash Outs", sessionStats.cashOuts, colors.lime)
  statLine("Busts", sessionStats.busts, colors.red)
  statLine("Same-Value Losses", sessionStats.sameValueLosses, colors.yellow)

  if sessionStats.bestStreak > 1 then
    statLine("Best Streak", sessionStats.bestStreak, colors.cyan)
  end

  ui.clearButtons()
  ui.layoutButtonGrid(screen, {
    {{ text = "BACK", color = colors.red, func = function() end }},
  }, centerX, scale.footerButtonY, scale.buttonRowSpacing, scale.buttonColGap)
  screen:output()
  ui.waitForButton(0, 0)
end

-----------------------------------------------------
-- Pre-round menu: PLAY, HOW TO PLAY, STATS
-----------------------------------------------------
local function preRoundMenu()
  local menuTimeout = cfg.PRE_ROUND_MENU_TIMEOUT or 10000
  local warningThreshold = max(0, menuTimeout - 10000)
  local lastActivityTime = epoch("local")

  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "HI-LO"
    local tw = ui.getTextSize(title)
    ui.safeDrawText(screen, title, font, math.floor((width - tw) / 2), scale.titleY, colors.yellow)

    local subtitle = "Higher or Lower?"
    local sw = ui.getTextSize(subtitle)
    ui.safeDrawText(screen, subtitle, font, math.floor((width - sw) / 2), scale.subtitleY, colors.lightGray)

    local idleMs = epoch("local") - lastActivityTime
    if idleMs > menuTimeout then
      sound.play(sound.SOUNDS.TIMEOUT)
      os.sleep(0.5)
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end

    if idleMs >= warningThreshold then
      local secondsLeft = max(1, ceil((menuTimeout - idleMs) / 1000))
      local timeoutLabel = "Auto-exit in " .. secondsLeft .. "s"
      local timeoutWidth = ui.getTextSize(timeoutLabel)
      ui.safeDrawText(screen, timeoutLabel, font, math.floor((width - timeoutWidth) / 2), height - LINE_H - scale.edgePad, colors.orange)
    end

    ui.clearButtons()
    local chosen = nil

    ui.layoutButtonGrid(screen, {
      {
        { text = "PLAY", color = colors.lime,
          func = function() chosen = "play" end },
      },
      {
        { text = "HOW TO PLAY", color = colors.lightBlue,
          func = function() chosen = "tutorial" end },
        { text = "STATS", color = colors.lightGray,
          func = function() chosen = "stats" end },
      },
    }, centerX, scale.menuY, scale.buttonRowSpacing, scale.buttonColGap)

    screen:output()

    if AUTO_PLAY then return end

    local timerID = os.startTimer(0.25)
    while true do
      local event, side, px, py = os.pullEvent()
      if event == "monitor_touch" then
        lastActivityTime = epoch("local")
        local cb = ui.checkButtonHit(px, py)
        if cb then
          cb()
          break
        end
      elseif event == "timer" and side == timerID then
        break
      end
    end

    if chosen == "play" then return end
    if chosen == "tutorial" then showTutorial() end
    if chosen == "stats" then showStats() end
  end
end

-----------------------------------------------------
-- Bet selection (amount)
-----------------------------------------------------
local function betSelection()
  return betting.runBetScreen(screen, {
    maxBet                 = getMaxBet(),
    gameName               = "HiLo",
    confirmLabel           = "DEAL",
    title                  = "PLACE YOUR BET",
    inactivityTimeout      = cfg.INACTIVITY_TIMEOUT,
    hostBalance            = hostBankBalance,
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
    onTimeout              = function()
      sound.play(sound.SOUNDS.TIMEOUT)
      os.sleep(0.5)
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end,
  })
end

-----------------------------------------------------
-- Hi-Lo round
-----------------------------------------------------
local function hiloRound(betAmount)
  if cfg.RESHUFFLE_EACH_ROUND then
    dbg("Starting round with a fresh deck")
    freshDeck()
  end

  recovery.saveBet(betAmount)

  local revealedCards = {}
  local currentCard = dealOne()
  table.insert(revealedCards, currentCard)
  local round = 0
  local multiplier = 1

  -- Show initial card with animation
  if not AUTO_PLAY then
    local img = cards.renderCard(currentCard)
    cardAnim.slideIn(img, leftCardX, cardY, function()
      renderBase(nil, revealedCards, betAmount, round, multiplier, nil)
    end)
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  renderScreen(currentCard, revealedCards, betAmount, round, multiplier, "Higher or Lower?")

  while round < cfg.MAX_ROUNDS do
    -- Player chooses HIGHER, LOWER, or CASH OUT (if round > 0)
    local choice = nil
    ui.clearButtons()

    local btnRows = {
      {
        { text = "HIGHER", color = colors.cyan,
          func = function() choice = "higher" end },
        { text = "LOWER", color = colors.red,
          func = function() choice = "lower" end },
      },
    }

    if round > 0 then
      -- Can cash out after first correct guess
      local winnings = roundedPayout(betAmount, multiplier) - betAmount
      local cashLabel = "CASH OUT +" .. currency.formatTokens(winnings)
      table.insert(btnRows, {
        { text = cashLabel, color = colors.lime,
          func = function() choice = "cashout" end },
      })
    end

    local btnY = getChoiceButtonY(#btnRows)
    ui.layoutButtonGrid(screen, btnRows, centerX, btnY, scale.buttonRowSpacing, scale.buttonColGap)
    screen:output()

    if AUTO_PLAY then
      -- Bot: random choice, cash out after 3 correct guesses 50% of the time
      if round >= 3 and math.random(100) <= 50 then
        choice = "cashout"
      else
        choice = math.random(2) == 1 and "higher" or "lower"
      end
      os.sleep(cfg.AUTO_PLAY_DELAY)
    else
      ui.waitForButton(0, 0)
    end

    if choice == "cashout" then
      -- Cash out: player wins current multiplier
      local totalPayout = roundedPayout(betAmount, multiplier)
      local profit = totalPayout - betAmount

      if profit > 0 then
        local payOk = currency.payout(profit, "HiLo: cash out profit")
        if not payOk then
          alert.send("CRITICAL: Failed to pay " .. profit .. " tokens to player!")
          alert.log("Payout failure: " .. profit .. " tokens, round=" .. round)
        end
      end

      sessionStats.cashOuts = sessionStats.cashOuts + 1
      sessionStats.rounds = sessionStats.rounds + 1
      sessionStats.totalBet = sessionStats.totalBet + betAmount
      local netChange = profit
      sessionStats.netProfit = sessionStats.netProfit + netChange
      sessionStats.totalWon = sessionStats.totalWon + netChange
      if netChange > sessionStats.biggestWin then
        sessionStats.biggestWin = netChange
      end
      if round > sessionStats.bestStreak then
        sessionStats.bestStreak = round
      end

      sound.play(sound.SOUNDS.SUCCESS)
      renderScreen(currentCard, revealedCards, betAmount, round, multiplier, nil)
      ui.displayCenteredMessage(screen,
        "Cashed Out! +" .. currency.formatTokens(profit),
        colors.lime, LO.RESULT_PAUSE)

      recovery.clearBet()
      dbg("Cash out: round=" .. round .. " mult=" .. multiplier .. " profit=" .. profit)
      return
    end

    -- Deal next card
    local nextCard = dealOne()
    table.insert(revealedCards, nextCard)
    round = round + 1

    -- Animate next card
    if not AUTO_PLAY then
      local img = cards.renderCard(nextCard)
      cardAnim.slideIn(img, rightCardX, cardY, function()
        renderBase(currentCard, revealedCards, betAmount, round, multiplier, nil)
      end)
    else
      sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
    end

    local currentVal = cardValue(currentCard)
    local nextVal = cardValue(nextCard)

    -- Evaluate guess
    local correct = false
    local sameValueLoss = (currentVal == nextVal)

    if choice == "higher" and nextVal > currentVal then
      correct = true
    elseif choice == "lower" and nextVal < currentVal then
      correct = true
    end

    if sameValueLoss then
      sessionStats.sameValueLosses = sessionStats.sameValueLosses + 1
      sessionStats.busts = sessionStats.busts + 1
      sessionStats.rounds = sessionStats.rounds + 1
      sessionStats.totalBet = sessionStats.totalBet + betAmount
      sessionStats.netProfit = sessionStats.netProfit - betAmount
      if round - 1 > sessionStats.bestStreak then
        sessionStats.bestStreak = round - 1
      end

      sound.play(sound.SOUNDS.FAIL)
      renderScreen(nextCard, revealedCards, betAmount, round, multiplier, nil)
      ui.displayCenteredMessage(screen,
        "Same value loses! " .. cards.displayValue(currentCard) .. " = " .. cards.displayValue(nextCard),
        colors.red, LO.RESULT_PAUSE)

      recovery.clearBet()
      dbg("Same-value loss: round=" .. round
          .. " current=" .. cards.displayValue(currentCard)
          .. " next=" .. cards.displayValue(nextCard))
      return
    elseif correct then
      -- Correct guess: increase multiplier
      multiplier = MULTIPLIERS[round] or MULTIPLIERS[#MULTIPLIERS]
      sound.play(sound.SOUNDS.CARD_PLACE, 0.7)

      currentCard = nextCard

      if round >= cfg.MAX_ROUNDS then
        -- Max streak reached: auto cash out
        local totalPayout = roundedPayout(betAmount, multiplier)
        local profit = totalPayout - betAmount

        if profit > 0 then
          local payOk = currency.payout(profit, "HiLo: max streak profit")
          if not payOk then
            alert.send("CRITICAL: Failed to pay " .. profit .. " tokens to player!")
          end
        end

        sessionStats.cashOuts = sessionStats.cashOuts + 1
        sessionStats.rounds = sessionStats.rounds + 1
        sessionStats.totalBet = sessionStats.totalBet + betAmount
        local netChange = profit
        sessionStats.netProfit = sessionStats.netProfit + netChange
        sessionStats.totalWon = sessionStats.totalWon + netChange
        if netChange > sessionStats.biggestWin then
          sessionStats.biggestWin = netChange
        end
        sessionStats.bestStreak = cfg.MAX_ROUNDS

        sound.play(sound.SOUNDS.SUCCESS)
        renderScreen(currentCard, revealedCards, betAmount, round, multiplier, nil)
        ui.displayCenteredMessage(screen,
          "MAX STREAK! +" .. currency.formatTokens(profit),
          colors.yellow, LO.RESULT_PAUSE + 1)

        recovery.clearBet()
        dbg("Max streak: mult=" .. multiplier .. " profit=" .. profit)
        return
      end

      -- Show updated state and let player choose again
      renderScreen(currentCard, revealedCards, betAmount, round, multiplier, "Correct! x" .. tostring(multiplier))
      os.sleep(0.8)
    else
      -- Wrong guess: player loses
      local charged = currency.charge(betAmount, "HiLo: wrong guess round " .. round)
      if not charged then
        alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (HiLo)")
      end

      sessionStats.busts = sessionStats.busts + 1
      sessionStats.rounds = sessionStats.rounds + 1
      sessionStats.totalBet = sessionStats.totalBet + betAmount
      sessionStats.netProfit = sessionStats.netProfit - betAmount
      if round - 1 > sessionStats.bestStreak then
        sessionStats.bestStreak = round - 1
      end

      sound.play(sound.SOUNDS.FAIL)
      renderScreen(currentCard, revealedCards, betAmount, round, multiplier, nil)
      ui.displayCenteredMessage(screen,
        "Wrong! " .. cards.displayValue(currentCard) .. " vs " .. cards.displayValue(nextCard),
        colors.red, LO.RESULT_PAUSE)

      recovery.clearBet()
      dbg("Bust: round=" .. round .. " guess=" .. choice
          .. " current=" .. cards.displayValue(currentCard)
          .. " next=" .. cards.displayValue(nextCard))
      return
    end
  end
end

-----------------------------------------------------
-- Main loop
-----------------------------------------------------
sound.play(sound.SOUNDS.BOOT)
recovery.recoverBet(true)
refreshPlayer()

local function main()
  while true do
    updateAutoPlayFromRedstone()
    refreshPlayer()
    drawPlayerOverlay()

    local betAmount = nil

    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      local autoBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if autoBet > 0 then
        betAmount = autoBet
        os.sleep(cfg.AUTO_PLAY_DELAY)
      else
        os.sleep(1)
      end
    else
      -- Show pre-round menu (PLAY / HOW TO PLAY / STATS)
      preRoundMenu()

      -- Run bet screen
      local selectedBet = betSelection()
      if selectedBet and selectedBet > 0 then
        betAmount = selectedBet
      end
    end

    if betAmount and betAmount > 0 then
      hiloRound(betAmount)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
