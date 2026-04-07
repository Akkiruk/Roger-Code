-- videopoker.lua
-- Video Poker (Jacks or Better) for ComputerCraft casino.
-- Deal 5 cards, hold/discard, draw replacements, evaluate poker hand.
-- Uses shared libraries from Games/lib/.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("videopoker_config")

local LO = cfg.LAYOUT
local PAYOUTS = cfg.PAYOUTS

local ostime       = os.time
local settings_get = settings.get
local r_getInput   = redstone.getInput
local epoch        = os.epoch

settings.define("videopoker.debug", {
  description = "Enable debug messages for the Video Poker game.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("videopoker.debug")
local function dbg(msg)
  if DEBUG then print(ostime(), "[VP] " .. msg) end
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
local replayPrompt = require("lib.replay_prompt")
local cardRules  = require("lib.card_rules")
local pages      = require("lib.casino_pages")
local settlement = require("lib.round_settlement")

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
-- Deck helpers (reshuffle every hand for video poker)
-----------------------------------------------------
local function freshDeck()
  deck = cards.buildDeck(cfg.DECK_COUNT)
  cards.shuffle(deck)
  return deck
end

local function dealOne()
  return cards.deal(deck)
end

-----------------------------------------------------
-- Poker hand evaluation
-----------------------------------------------------

--- Get numeric rank for a card value character (2=2, ..., A=14)
local function getRank(cardID)
  return cardRules.pokerRank(cardID)
end

local function getSuit(cardID)
  return cardRules.pokerSuit(cardID)
end

--- Evaluate a 5-card hand. Returns the hand name and payout index (1-based into PAYOUTS, nil if no win).
-- @param hand table  Array of 5 card ID strings
-- @return string handName, number|nil payoutIndex
local function evaluateHand(hand)
  return cardRules.evaluateJacksOrBetter(hand)
end

-----------------------------------------------------
-- Layout (computed once from screen dimensions)
-----------------------------------------------------
local centerX = math.floor(width / 2)
local selectionOutline = scale:scaledX(1, 1, 2)
local handOuterPad = scale:scaledX(8, 5, 14)
local handEdgePad = math.max(scale.edgePad, selectionOutline, handOuterPad)
local cardBottomGap = scale:scaledY(LO.CARD_BOTTOM_GAP or 18, scale.edgePad + scale.smallGap, scale:ratioY(0.24))
local cardY = scale:bottom(cardBack.height + selectionOutline, cardBottomGap)
local handUsableWidth = math.max(0, width - (handEdgePad * 2) - cardBack.width)
local handStep = 0

if cfg.HAND_SIZE > 1 then
  handStep = handUsableWidth / (cfg.HAND_SIZE - 1)
end

local function roundToNearest(value)
  return math.floor(value + 0.5)
end

local function getCardX(index)
  if cfg.HAND_SIZE <= 1 then
    return math.floor((width - cardBack.width) / 2)
  end
  return handEdgePad + roundToNearest((index - 1) * handStep)
end

-----------------------------------------------------
-- Rendering helpers
-----------------------------------------------------
local LINE_H = scale.lineHeight
local statusTextWidth = math.max(1, width - (scale.edgePad * 2))
local selectionLabelY = cardY - LINE_H - scale.smallGap

local function drawCenteredLine(text, y, color)
  local tw = ui.getTextSize(text)
  ui.safeDrawText(screen, text, font, math.floor((width - tw) / 2), y, color or colors.white)
end

local function triggerInactivityTimeout()
  sound.play(sound.SOUNDS.TIMEOUT)
  os.sleep(0.5)
  error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
end

local function wrapStatusText(text)
  local words = {}
  local current = ""

  for word in tostring(text or ""):gmatch("%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    if ui.getTextSize(candidate) <= statusTextWidth then
      current = candidate
    else
      if current ~= "" then
        words[#words + 1] = current
      end
      current = word
    end
  end

  if current ~= "" then
    words[#words + 1] = current
  end

  if #words == 0 then
    words[1] = ""
  end

  return words
end

local function renderHand(hand, discardSelected, betAmount, statusText, showSelectionState)
  screen:clear(LO.TABLE_COLOR)

  -- Bet display
  local betLabel = "Bet: " .. currency.formatTokens(betAmount)
  ui.safeDrawText(screen, betLabel, font, 1, 0, colors.white)

  -- Draw cards
  for i, cardID in ipairs(hand) do
    local x = getCardX(i)
    local y = cardY
    local label = discardSelected[i] and "Trash" or "Keep"
    local labelColor = discardSelected[i] and colors.red or colors.lime
    if discardSelected[i] then
      y = cardY + scale:scaledY(LO.DISCARD_CARD_DROP or 0, 0, 3)
    end
    if showSelectionState then
      local labelWidth = ui.getTextSize(label)
      ui.safeDrawText(
        screen,
        label,
        font,
        x + math.floor((cardBack.width - labelWidth) / 2),
        selectionLabelY,
        labelColor
      )
      screen:fillRect(
        x - selectionOutline,
        y - selectionOutline,
        cardBack.width + (selectionOutline * 2),
        cardBack.height + (selectionOutline * 2),
        labelColor
      )
    end
    local img = cards.renderCard(cardID)
    screen:drawSurface(img, x, y)
  end

  -- Status text
  if statusText then
    local statusY = cardY + cardBack.height + scale.sectionGap + scale.smallGap
    local statusLines = wrapStatusText(statusText)
    for i, line in ipairs(statusLines) do
      drawCenteredLine(line, statusY + ((i - 1) * LINE_H), colors.yellow)
    end
    return statusY + (#statusLines * LINE_H) - 1
  end

  return cardY + cardBack.height - 1
end

-----------------------------------------------------
-- Payout table display
-----------------------------------------------------
local function showPayoutTable()
  local lines = {
    { text = "Jacks or Better", color = colors.lightGray },
    { spacer = true },
  }
  for _, p in ipairs(PAYOUTS) do
    local color = colors.white
    if p.multiplier >= 25 then
      color = colors.yellow
    elseif p.multiplier >= 4 then
      color = colors.cyan
    end
    lines[#lines + 1] = { text = p.name .. " - " .. tostring(p.multiplier) .. "x", color = color }
  end
  pages.showStatsScreen(screen, font, scale, LO.TABLE_COLOR, "PAYOUT TABLE", lines, {
    centerX = centerX,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    onTimeout = triggerInactivityTimeout,
  })
end

-----------------------------------------------------
-- Tutorial / How to play screens
-----------------------------------------------------
local TUTORIAL_PAGES = {
  {
    title = "HOW TO PLAY",
    lines = {
      { text = "You get 5 cards.",       color = colors.white },
      { text = "Tap cards to",           color = colors.white },
      { text = "MARK for discard",       color = colors.red },
      { text = "and redraw.",            color = colors.white },
      { text = "",                        color = colors.white },
      { text = "Tap DRAW for new",       color = colors.yellow },
      { text = "cards in those slots.",  color = colors.yellow },
    },
  },
  {
    title = "WINNING HANDS",
    lines = {
      { text = "Pair of J,Q,K,A",       color = colors.white },
      { text = "Two Pair",               color = colors.white },
      { text = "Three of a Kind",        color = colors.cyan },
      { text = "Straight / Flush",       color = colors.cyan },
      { text = "Full House",             color = colors.yellow },
      { text = "Four of a Kind",         color = colors.yellow },
      { text = "Straight/Royal Flush",   color = colors.lime },
    },
  },
  {
    title = "TIPS",
    lines = {
      { text = "Always hold pairs",      color = colors.white },
      { text = "of Jacks or better!",    color = colors.white },
      { text = "",                        color = colors.white },
      { text = "Leave 4 to a flush",     color = colors.cyan },
      { text = "or straight alone.",     color = colors.cyan },
      { text = "",                        color = colors.white },
      { text = "Royal Flush = 250x!",    color = colors.yellow },
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

-----------------------------------------------------
-- Pre-round menu
-----------------------------------------------------
local function preRoundMenu()
  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "VIDEO POKER"
    local tw = ui.getTextSize(title)
    ui.safeDrawText(screen, title, font, math.floor((width - tw) / 2), scale.titleY, colors.yellow)

    local subtitle = "Jacks or Better"
    local sw = ui.getTextSize(subtitle)
    ui.safeDrawText(screen, subtitle, font, math.floor((width - sw) / 2), scale.subtitleY, colors.lightGray)

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

    if AUTO_PLAY then return end

    ui.waitForButton(0, 0, {
      inactivityTimeout = cfg.INACTIVITY_TIMEOUT,
      onTimeout = triggerInactivityTimeout,
    })

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
    gameName               = "VideoPoker",
    confirmLabel           = "DEAL",
    title                  = "PLACE YOUR BET",
    inactivityTimeout      = cfg.INACTIVITY_TIMEOUT,
    hostBalance            = currency.getProtectedHostBalance(hostBankBalance),
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
    onTimeout              = triggerInactivityTimeout,
  })
end

local function canReplayBet(betAmount)
  if not betAmount or betAmount <= 0 then
    return false, "Place a new bet."
  end

  if currency.getPlayerBalance() < betAmount then
    return false, "Lower the bet before playing again."
  end

  local protectedHostBalance = currency.getProtectedHostBalance(hostBankBalance)
  if protectedHostBalance and cfg.HOST_COVERAGE_MULT and cfg.HOST_COVERAGE_MULT > 1 then
    local needed = betAmount * (cfg.HOST_COVERAGE_MULT - 1)
    if protectedHostBalance < needed then
      return false, "House limit changed. Visit the menu."
    end
  end

  if getMaxBet() < betAmount then
    return false, "House limit changed. Visit the menu."
  end

  return true
end

local function waitForReplayChoice(hand, discardSelected, betAmount, statusText)
  local choiceHintY = math.max(scale.subtitleY, scale.footerButtonY - scale.buttonRowSpacing - LINE_H - 2)

  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderHand(hand, discardSelected, betAmount, statusText, false)
    end,
    hint = function()
      local replayAvailable, replayHint = canReplayBet(betAmount)
      if replayAvailable then
        return "Touch PLAY AGAIN to deal the same bet.", colors.lightGray
      end
      return replayHint, colors.orange
    end,
    hint_y = choiceHintY,
    buttons = {
      {
        {
          id = "play_again",
          text = "PLAY AGAIN",
          color = colors.lime,
          enabled = function()
            return canReplayBet(betAmount)
          end,
          disabled_message = "Visit the menu to set a new bet.",
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
    onTimeout = triggerInactivityTimeout,
    auto_choice = AUTO_PLAY and "play_again" or nil,
    auto_delay = cfg.AUTO_PLAY_DELAY,
  })
end

-----------------------------------------------------
-- Auto-play discard strategy (simple: keep pairs and high cards)
-----------------------------------------------------
local function autoSelectDiscards(hand)
  local discardSelected = { true, true, true, true, true }
  local rankCounts = {}

  for i, cardID in ipairs(hand) do
    local r = getRank(cardID)
    rankCounts[r] = (rankCounts[r] or 0) + 1
  end

  for i, cardID in ipairs(hand) do
    local r = getRank(cardID)
    -- Keep any pair or better, or high cards (J+); everything else is discarded.
    if rankCounts[r] >= 2 or r >= 11 then
      discardSelected[i] = false
    end
  end

  return discardSelected
end

-----------------------------------------------------
-- Video Poker round
-----------------------------------------------------
local function pokerRound(betAmount)
  recovery.saveBet(betAmount)

  -- Fresh deck each hand
  freshDeck()

  -- Deal 5 cards
  local hand = {}
  for i = 1, cfg.HAND_SIZE do
    hand[i] = dealOne()
  end

  local discardSelected = { false, false, false, false, false }

  -- Animate initial deal
  if not AUTO_PLAY then
    local visCards = {}
    for i, cardID in ipairs(hand) do
      local x = getCardX(i)
      local img = cards.renderCard(cardID)
      cardAnim.slideIn(img, x, cardY, function()
        screen:clear(LO.TABLE_COLOR)
        ui.safeDrawText(screen, "Bet: " .. currency.formatTokens(betAmount), font, 1, 0, colors.white)
        for j, cid in ipairs(visCards) do
          screen:drawSurface(cards.renderCard(cid), getCardX(j), cardY)
        end
      end)
      table.insert(visCards, cardID)
    end
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  -- Hold/discard phase
  if AUTO_PLAY then
    discardSelected = autoSelectDiscards(hand)
    os.sleep(cfg.AUTO_PLAY_DELAY)
  else
    local confirmed = false
    local lastActivityTime = epoch("local")

    while not confirmed do
      renderHand(hand, discardSelected, betAmount, nil, true)

      local promptText = "Tap cards you want to replace, then tap DRAW."
      local promptLines = wrapStatusText(promptText)
      local promptHeight = #promptLines * LINE_H
      local maxDrawBtnY = selectionLabelY - scale.sectionGap - scale.buttonHeight
      local promptY = math.max(
        scale.subtitleY,
        maxDrawBtnY - scale.sectionGap - promptHeight
      )

      for i, line in ipairs(promptLines) do
        drawCenteredLine(line, promptY + ((i - 1) * LINE_H), colors.yellow)
      end

      ui.clearButtons()
      -- Draw button
      local drawBtnY = math.min(
        maxDrawBtnY,
        promptY + promptHeight + scale.smallGap
      )
      ui.fixedWidthButton(screen, "DRAW", colors.lime,
        centerX, drawBtnY, function()
          confirmed = true
        end, true, nil)

      screen:output()

      local _, px, py, activityTime = ui.waitForMonitorTouch({
        inactivityTimeout = cfg.INACTIVITY_TIMEOUT,
        onTimeout = function()
          alert.log("Video Poker timeout: auto-draw with current holds")
          confirmed = true
        end,
        lastActivityTime = lastActivityTime,
      })
      if confirmed then
        break
      end
      lastActivityTime = activityTime
      local buttonCb = ui.checkButtonHit(px, py)
      if buttonCb then
        buttonCb()
      else
        for i = 1, cfg.HAND_SIZE do
          local x = getCardX(i)
          local cardTop = cardY
          if discardSelected[i] then
            cardTop = cardY + scale:scaledY(LO.DISCARD_CARD_DROP or 0, 0, 3)
          end
          if px >= x and px <= x + cardBack.width - 1
             and py >= cardTop and py <= cardTop + cardBack.height - 1 then
            discardSelected[i] = not discardSelected[i]
            sound.play(sound.SOUNDS.CARD_PLACE, 0.5)
            break
          end
        end
      end
    end
  end

  -- Replace selected discard cards
  local replaced = false
  for i = 1, cfg.HAND_SIZE do
    if discardSelected[i] then
      hand[i] = dealOne()
      replaced = true
    end
  end

  -- Animate replacement cards
  if replaced and not AUTO_PLAY then
    for i = 1, cfg.HAND_SIZE do
      if discardSelected[i] then
        local x = getCardX(i)
        local img = cards.renderCard(hand[i])
        cardAnim.slideIn(img, x, cardY, function()
          screen:clear(LO.TABLE_COLOR)
          ui.safeDrawText(screen, "Bet: " .. currency.formatTokens(betAmount), font, 1, 0, colors.white)
          for j, cid in ipairs(hand) do
            local cx = getCardX(j)
            if j < i or not discardSelected[j] then
              screen:drawSurface(cards.renderCard(cid), cx, cardY)
            end
          end
        end)
      end
    end
  elseif replaced then
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  -- Evaluate final hand
  local handName, payoutIdx = evaluateHand(hand)
  local multiplier = 0
  if payoutIdx then
    multiplier = PAYOUTS[payoutIdx].multiplier
  end

  local netChange = 0
  local totalPayout = 0
  local resultPromptText = handName

  if multiplier > 0 then
    -- Win
    totalPayout = betAmount * (multiplier + 1)  -- bet * multiplier + original bet back
    netChange = betAmount * multiplier

    if netChange > 0 then
      local payOk = settlement.applyNetChange(netChange, {
        winReason = "VideoPoker: " .. handName .. " payout",
        failurePrefix = "CRITICAL",
        logFailure = function(message)
          alert.log(message .. ", hand=" .. tostring(handName))
        end,
      })
      if not payOk then
        alert.send("CRITICAL: Failed to pay " .. netChange .. " tokens to player!")
      end
    end

    sound.play(sound.SOUNDS.SUCCESS)
    renderHand(hand, discardSelected, betAmount, nil, false)
    ui.displayCenteredMessage(screen,
      handName .. "! +" .. currency.formatTokens(netChange),
      colors.lime, LO.RESULT_PAUSE)
    resultPromptText = handName .. "! +" .. currency.formatTokens(netChange)
  else
    -- Loss
    netChange = -betAmount
    local charged = settlement.applyNetChange(-betAmount, {
      lossReason = "VideoPoker: no win",
      failurePrefix = "CRITICAL",
      logFailure = function(message)
        alert.log(message .. ", hand=" .. tostring(handName))
      end,
    })
    if not charged then
      alert.send("CRITICAL: Failed to charge " .. betAmount .. " tokens (video poker)")
    end

    sound.play(sound.SOUNDS.FAIL)
    renderHand(hand, discardSelected, betAmount, nil, false)
    ui.displayCenteredMessage(screen, handName, colors.red, LO.RESULT_PAUSE)
  end

  recovery.clearBet()
  dbg("Hand: " .. handName .. " mult=" .. multiplier .. " net=" .. netChange)
  if AUTO_PLAY then
    return "play_again"
  end
  return waitForReplayChoice(hand, discardSelected, betAmount, resultPromptText)
end

-----------------------------------------------------
-- Main loop
-----------------------------------------------------
sound.play(sound.SOUNDS.BOOT)
recovery.recoverBet(true)
refreshPlayer()

local function main()
  local replayBetAmount = nil

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
      if replayBetAmount and canReplayBet(replayBetAmount) then
        betAmount = replayBetAmount
        replayBetAmount = nil
      else
        replayBetAmount = nil
        preRoundMenu()

        local selectedBet = betSelection()
        if selectedBet and selectedBet > 0 then
          betAmount = selectedBet
        end
      end
    end

    if betAmount and betAmount > 0 then
      local roundChoice = pokerRound(betAmount)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
      replayBetAmount = (roundChoice == "play_again") and betAmount or nil
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
