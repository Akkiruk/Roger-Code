-- hilo.lua
-- Hi-Lo card game for ComputerCraft casino.
-- A card is shown; guess whether the next card is HIGHER or LOWER.
-- Correct guesses build a multiplier; cash out any time or risk it all.
-- Uses shared libraries from Shared/lib/.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("hilo_config")

local LO = cfg.LAYOUT
local MULTIPLIERS = cfg.MULTIPLIERS

local ostime       = os.time
local settings_get = settings.get
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

local canReplayBet = nil

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
local replayPrompt = require("lib.replay_prompt")
local cardAnim   = require("lib.card_anim")
local cardRules  = require("lib.card_rules")
local pages      = require("lib.casino_pages")
local settlement = require("lib.round_settlement")
local activityTimeout = require("lib.activity_timeout")

recovery.configure(cfg.RECOVERY_FILE)

local env = gameSetup.init({
  monitorName     = cfg.MONITOR,
  deckCount       = cfg.DECK_COUNT,
  gameName        = cfg.GAME_NAME,
  logFile         = cfg.LOG_FILE,
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
  return currency.getMaxBetLimit(hostBankBalance, cfg.MAX_BET_PERCENT, cfg.HOST_COVERAGE_MULT)
end

local function refreshPlayer()
  return env.refreshPlayer()
end

local function drawPlayerOverlay()
  env.drawPlayerOverlay()
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
local function cardValue(cardID)
  return cardRules.hiloValue(cardID)
end

local function roundedPayout(betAmount, multiplier)
  return cardRules.roundedPayout(betAmount, multiplier)
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

local function triggerInactivityTimeout()
  sound.play(sound.SOUNDS.TIMEOUT)
  os.sleep(0.5)
  error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
end

local function timeoutChoiceForCard(currentCard)
  local currentVal = cardValue(currentCard)
  local lowerWins = math.max(0, currentVal - 2)
  local higherWins = math.max(0, 14 - currentVal)

  if higherWins <= lowerWins then
    return "higher"
  end

  return "lower"
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

local function getPostRoundHintY()
  return max(scale.subtitleY, scale.footerButtonY - LINE_H - scale.sectionGap)
end

local function renderBase(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  screen:clear(LO.TABLE_COLOR)

  -- Multiplier display
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

  -- Current bet stays in the footer so it remains visible during play-again/result screens.
  local betLabel = "Current Bet: " .. currency.formatTokens(betAmount)
  local betY = max(0, height - LINE_H - scale.edgePad)
  drawCenteredLine(betLabel, betY, colors.white)
end

local function renderScreen(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  renderBase(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  screen:output()
end

local function waitForPostRoundChoice(currentCard, revealedCards, betAmount, round, multiplier, statusText)
  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderBase(currentCard, revealedCards, betAmount, round, multiplier, statusText)
    end,
    hint = function()
      local replayAvailable, replayHint = canReplayBet(betAmount)
      if replayAvailable then
        return "Touch PLAY AGAIN to keep the same bet.", colors.lightGray
      end
      return replayHint or "Pick a new bet from the menu.", colors.orange
    end,
    hint_y = getPostRoundHintY(),
    buttons = {
      {
        {
          id = "play_again",
          text = "PLAY AGAIN",
          color = colors.lime,
          enabled = function()
            return canReplayBet(betAmount)
          end,
          disabled_message = "Pick a new bet before playing again.",
        },
        {
          id = "menu",
          text = "MAIN MENU",
          color = colors.red,
        },
      },
    },
    center_x = centerX,
    button_y = scale.footerButtonY,
    row_spacing = scale.buttonRowSpacing,
    col_spacing = scale.buttonColGap,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    onTimeout = function()
      sound.play(sound.SOUNDS.TIMEOUT)
      os.sleep(0.5)
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end,
  })
end

-----------------------------------------------------
-- Tutorial / How to play screens
-----------------------------------------------------
local function showPayoutTable()
  local payoutPages = {}
  local roundsPerPage = 5

  for startIndex = 1, #MULTIPLIERS, roundsPerPage do
    local endIndex = math.min(startIndex + roundsPerPage - 1, #MULTIPLIERS)
    local lines = {
      { text = "Cash out after any hit.",  color = colors.lightBlue },
      { text = "Return includes your bet.", color = colors.lightGray },
      { text = "", color = colors.white },
    }

    for roundIndex = startIndex, endIndex do
      local multiplier = MULTIPLIERS[roundIndex]
      local color = (roundIndex == #MULTIPLIERS) and colors.lime or colors.yellow
      lines[#lines + 1] = {
        text = roundIndex .. " CORRECT = x" .. tostring(multiplier),
        color = color,
      }
    end

    payoutPages[#payoutPages + 1] = {
      title = "PAYOUTS",
      lines = lines,
    }
  end

  pages.showPagedLines(screen, font, scale, LO.TABLE_COLOR, payoutPages, {
    centerX = centerX,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    onTimeout = triggerInactivityTimeout,
  })
end

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
  pages.showPagedLines(screen, font, scale, LO.TABLE_COLOR, TUTORIAL_PAGES, {
    centerX = centerX,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    onTimeout = triggerInactivityTimeout,
  })
end

-- Pre-round menu: PLAY, HOW TO PLAY
-----------------------------------------------------
local function preRoundMenu()
  local timeoutState = activityTimeout.create(
    activityTimeout.resolveDuration(cfg.PRE_ROUND_MENU_TIMEOUT, cfg.INACTIVITY_TIMEOUT, 90000)
  )

  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "HI-LO"
    local tw = ui.getTextSize(title)
    ui.safeDrawText(screen, title, font, math.floor((width - tw) / 2), scale.titleY, colors.yellow)

    local subtitle = "Higher or Lower?"
    local sw = ui.getTextSize(subtitle)
    ui.safeDrawText(screen, subtitle, font, math.floor((width - sw) / 2), scale.subtitleY, colors.lightGray)

    if timeoutState and timeoutState:isExpired() then
      triggerInactivityTimeout()
    end

    if timeoutState and timeoutState:isWarning() then
      local secondsLeft = timeoutState:secondsLeft()
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
        { text = "PAYOUTS", color = colors.yellow,
          func = function() chosen = "payouts" end },
        { text = "HOW TO PLAY", color = colors.lightBlue,
          func = function() chosen = "tutorial" end },
      },
    }, centerX, scale.menuY, scale.buttonRowSpacing, scale.buttonColGap)

    screen:output()

    local timerID = os.startTimer(0.25)
    while true do
      local event, side, px, py = os.pullEvent()
      if event == "monitor_touch" then
        if timeoutState then
          timeoutState:touch()
        end
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
    if chosen == "payouts" then showPayoutTable() end
    if chosen == "tutorial" then showTutorial() end
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
    hostBalance            = currency.getProtectedHostBalance(hostBankBalance),
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
    onTimeout              = function()
      sound.play(sound.SOUNDS.TIMEOUT)
      os.sleep(0.5)
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end,
  })
end

canReplayBet = function(betAmount)
  if not betAmount or betAmount <= 0 then
    return false
  end

  if currency.getPlayerBalance() < betAmount then
    return false
  end

  if getMaxBet() < betAmount then
    return false
  end

  return true
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
  local img = cards.renderCard(currentCard)
  cardAnim.slideIn(img, leftCardX, cardY, function()
    renderBase(nil, revealedCards, betAmount, round, multiplier, nil)
  end)

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

    ui.waitForButton(0, 0, {
      inactivityTimeout = cfg.INACTIVITY_TIMEOUT,
      onTimeout = function()
        choice = timeoutChoiceForCard(currentCard)
        alert.log("HiLo timeout: auto-select " .. tostring(choice) .. " on " .. tostring(cards.displayValue(currentCard)))
      end,
    })

    if choice == "cashout" then
      -- Cash out: player wins current multiplier
      local totalPayout = roundedPayout(betAmount, multiplier)
      local profit = totalPayout - betAmount

      if profit > 0 then
        local payOk = settlement.applyNetChange(profit, {
          winReason = "HiLo: cash out profit",
          failurePrefix = "CRITICAL",
          logFailure = function(message)
            alert.log(message .. " tokens, round=" .. tostring(round))
          end,
        })
        if not payOk then
          alert.send("CRITICAL: Failed to pay " .. profit .. " tokens to player!")
          alert.log("Payout failure: " .. profit .. " tokens, round=" .. round)
        end
      end

      sound.play(sound.SOUNDS.SUCCESS)
      renderScreen(currentCard, revealedCards, betAmount, round, multiplier, nil)
      ui.displayCenteredMessage(screen,
        "Cashed Out! +" .. currency.formatTokens(profit),
        colors.lime, LO.RESULT_PAUSE)

      recovery.clearBet()
      dbg("Cash out: round=" .. round .. " mult=" .. multiplier .. " profit=" .. profit)
      return waitForPostRoundChoice(
        currentCard,
        revealedCards,
        betAmount,
        round,
        multiplier,
        "Cashed Out! +" .. currency.formatTokens(profit)
      )
    end

    -- Deal next card
    local nextCard = dealOne()
    table.insert(revealedCards, nextCard)
    round = round + 1

    -- Animate next card
    local img = cards.renderCard(nextCard)
    cardAnim.slideIn(img, rightCardX, cardY, function()
      renderBase(currentCard, revealedCards, betAmount, round, multiplier, nil)
    end)

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
      local charged = settlement.applyNetChange(-betAmount, {
        lossReason = "HiLo: same value loss round " .. round,
        failurePrefix = "CRITICAL",
      })
      if not charged then
        alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (HiLo same-value loss)")
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
      return waitForPostRoundChoice(
        nextCard,
        revealedCards,
        betAmount,
        round,
        multiplier,
        "Same value loses! " .. cards.displayValue(currentCard) .. " = " .. cards.displayValue(nextCard)
      )
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
          local payOk = settlement.applyNetChange(profit, {
            winReason = "HiLo: max streak profit",
            failurePrefix = "CRITICAL",
          })
          if not payOk then
            alert.send("CRITICAL: Failed to pay " .. profit .. " tokens to player!")
          end
        end

        sound.play(sound.SOUNDS.SUCCESS)
        renderScreen(currentCard, revealedCards, betAmount, round, multiplier, nil)
        ui.displayCenteredMessage(screen,
          "MAX STREAK! +" .. currency.formatTokens(profit),
          colors.yellow, LO.RESULT_PAUSE + 1)

        recovery.clearBet()
        dbg("Max streak: mult=" .. multiplier .. " profit=" .. profit)
        return waitForPostRoundChoice(
          currentCard,
          revealedCards,
          betAmount,
          round,
          multiplier,
          "MAX STREAK! +" .. currency.formatTokens(profit)
        )
      end

      -- Show updated state and let player choose again
      renderScreen(currentCard, revealedCards, betAmount, round, multiplier, "Correct! x" .. tostring(multiplier))
      os.sleep(0.8)
    else
      -- Wrong guess: player loses
      local charged = settlement.applyNetChange(-betAmount, {
        lossReason = "HiLo: wrong guess round " .. round,
        failurePrefix = "CRITICAL",
      })
      if not charged then
        alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (HiLo)")
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
      return waitForPostRoundChoice(
        currentCard,
        revealedCards,
        betAmount,
        round,
        multiplier,
        "Wrong! " .. cards.displayValue(currentCard) .. " vs " .. cards.displayValue(nextCard)
      )
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
  local skipPreRoundMenu = false
  local replayBetAmount = nil

  while true do
    refreshPlayer()
    drawPlayerOverlay()

    local betAmount = nil

    if not skipPreRoundMenu then
      -- Show the pre-round menu before opening the bet screen.
      preRoundMenu()
    end

    if skipPreRoundMenu and canReplayBet(replayBetAmount) then
      betAmount = replayBetAmount
    else
      -- Run bet screen
      local selectedBet = betSelection()
      if selectedBet and selectedBet > 0 then
        betAmount = selectedBet
      end
    end
    skipPreRoundMenu = false

    if betAmount and betAmount > 0 then
      local roundChoice = hiloRound(betAmount)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
      skipPreRoundMenu = (roundChoice == "play_again")
      replayBetAmount = betAmount
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
