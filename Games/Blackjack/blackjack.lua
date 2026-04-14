-- blackjack.lua
-- Blackjack card game for ComputerCraft casino.
-- State-machine architecture with split, insurance, and surrender support.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("blackjack_config")

local ACT = cfg.ACTIONS
local OUT = cfg.OUTCOMES
local LO  = cfg.LAYOUT

local ostime       = os.time
local settings_get = settings.get
local epoch        = os.epoch

-- Forward declarations
local buildAndRecordResult = nil
local waitForReplayChoice = nil

settings.define("blackjack.debug", {
  description = "Enable debug messages for the Blackjack game.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("blackjack.debug")
local function dbg(msg)
  if DEBUG then print(ostime(), "[BJ] " .. msg) end
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
local settlement = require("lib.round_settlement")
local pages      = require("lib.casino_pages")

recovery.configure(cfg.RECOVERY_FILE)

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount   = cfg.DECK_COUNT,
  gameName    = cfg.GAME_NAME,
  logFile     = cfg.LOG_FILE,
})

alert.addPlannedExits({
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
  local hostLimit = currency.getMaxBetLimit(hostBankBalance, cfg.MAX_BET_PERCENT, cfg.HOST_COVERAGE_MULT)
  return math.min(hostLimit, cfg.MAX_BET_TOKENS or hostLimit)
end

-----------------------------------------------------
-- Player detection (shared via game_setup)
-----------------------------------------------------
local function refreshPlayer()
  return env.refreshPlayer()
end

local function drawPlayerOverlay()
  env.drawPlayerOverlay()
end

-----------------------------------------------------
-- Host win notification
-----------------------------------------------------
local function notifyHostOfWin(playerName, amount, reason)
  local hostName = currency.getHostName()
  if not hostName or hostName == "" then return end
  if hostName == playerName then return end
  local msg = playerName .. " won " .. amount .. " tokens (" .. reason .. ")"
  alert.notifyPlayer(hostName, msg)
end

-----------------------------------------------------
-- Card helpers
-----------------------------------------------------
local function ensureDeck()
  local reshuffleAt = cfg.MIN_CARDS_RESHUFFLE or 20
  if #deck < reshuffleAt then
    dbg("Reshuffling deck")
    deck = cards.buildDeck(cfg.DECK_COUNT)
    cards.shuffle(deck)
  end
end

local function dealOne()
  ensureDeck()
  return cards.deal(deck)
end

local function drawHand(hand, startX, y, hideFirst)
  local handDeltaX = cardBack.width + scale:scaledX(LO.CARD_SPACING, 1, 6)
  for i, cardID in ipairs(hand) do
    local img
    if hideFirst and i == 1 then
      img = cardBack
    else
      img = cards.renderCard(cardID)
    end
    screen:drawSurface(img, startX + (i - 1) * handDeltaX, y)
  end
end

-----------------------------------------------------
-- Layout (computed once from config + screen dimensions)
-----------------------------------------------------
local cardSpacing = scale:scaledX(LO.CARD_SPACING, 1, 6)
local deltaX  = cardBack.width + cardSpacing
local layout  = {
  dealerY      = scale:scaledY(LO.DEALER_Y, scale.edgePad + scale.smallGap, scale:ratioY(0.18)),
  playerY      = height - cardBack.height - scale:scaledY(LO.PLAYER_Y_OFFSET, 2, 8),
  buttonY      = height - cardBack.height - scale:scaledY(LO.BUTTON_Y_OFFSET, 10, 26),
  scoreYOff    = scale:scaledY(LO.SCORE_Y_OFFSET, 4, 10),
  statusY      = scale:ratioY(0.50, 0, scale.subtitleY, height - scale.lineHeight - scale.edgePad),
  centerX      = math.floor(width / 2),
}
layout.dealerScoreY = layout.dealerY + cardBack.height + scale.smallGap

-----------------------------------------------------
-- Render
-----------------------------------------------------
local function renderTableBase(ctx, hideDealer, statusText)
  screen:clear(LO.TABLE_COLOR)

  -- Bet display
  local totalBet = 0
  for _, h in ipairs(ctx.hands) do totalBet = totalBet + h.bet end
  local betStr = "Bet: " .. currency.formatTokens(totalBet)
  ui.safeDrawText(screen, betStr, font, 1, 0, colors.white)

  if ctx.insuranceBet > 0 then
    ui.safeDrawText(screen, "Ins: " .. currency.formatTokens(ctx.insuranceBet), font, 1, scale.lineHeight - scale.smallGap, colors.cyan)
  end

  -- Dealer hand
  local dealerX = math.floor((width - (#ctx.dealerHand * deltaX)) / 2)
  drawHand(ctx.dealerHand, dealerX, layout.dealerY, hideDealer)
  if not hideDealer then
    local dTotal = cards.blackjackValue(ctx.dealerHand)
    ui.safeDrawText(screen, tostring(dTotal), font, dealerX - scale:scaledX(10, 8, 14), layout.dealerScoreY, colors.white)
  end

  -- Player hand(s)
  if #ctx.hands == 1 then
    local hand = ctx.hands[1]
    local px = math.floor((width - (#hand.cards * deltaX)) / 2)
    drawHand(hand.cards, px, layout.playerY, false)
    local pTotal = cards.blackjackValue(hand.cards)
    ui.safeDrawText(screen, tostring(pTotal), font, px - scale:scaledX(10, 8, 14), layout.playerY + layout.scoreYOff, colors.white)
  else
    for i, hand in ipairs(ctx.hands) do
      local baseX
      if i == 1 then
        baseX = math.floor(width / 4) - math.floor((#hand.cards * deltaX) / 2)
      else
        baseX = math.floor(width * 3 / 4) - math.floor((#hand.cards * deltaX) / 2)
      end
      drawHand(hand.cards, baseX, layout.playerY, false)
      local pTotal = cards.blackjackValue(hand.cards)
      local clr = (i == ctx.currentHandIdx) and colors.yellow or colors.white
      ui.safeDrawText(screen, tostring(pTotal), font, baseX - scale:scaledX(10, 8, 14), layout.playerY + layout.scoreYOff, clr)
      if i == ctx.currentHandIdx and #ctx.hands > 1 then
        ui.safeDrawText(screen, ">>", font, baseX - scale:scaledX(18, 14, 24), layout.playerY + layout.scoreYOff, colors.yellow)
      end
    end
  end

  if statusText then
    local tw = ui.getTextSize(statusText)
    ui.safeDrawText(screen, statusText, font, math.floor((width - tw) / 2), layout.statusY, colors.yellow)
  end
end

local function renderTable(ctx, hideDealer, statusText)
  renderTableBase(ctx, hideDealer, statusText)
  screen:output()
end

-----------------------------------------------------
-- Pre-round help screens
-----------------------------------------------------
local function showPayoutTable()
  local lines = {
    { text = "Blackjack pays +" .. tostring(cfg.BLACKJACK_PAYOUT) .. "x", color = colors.yellow },
    { text = "Regular win pays +1x", color = colors.white },
    { text = "Push returns your bet", color = colors.lightGray },
    { spacer = true },
    { text = "Current max bet: " .. currency.formatTokens(getMaxBet()), color = colors.cyan },
  }

  if cfg.ALLOW_SURRENDER then
    lines[#lines + 1] = { text = "Surrender returns half", color = colors.orange }
  else
    lines[#lines + 1] = { text = "Surrender is off", color = colors.orange }
  end

  if cfg.ALLOW_INSURANCE then
    lines[#lines + 1] = { text = "Insurance is available", color = colors.lightBlue }
  else
    lines[#lines + 1] = { text = "Insurance is off", color = colors.lightBlue }
  end

  pages.showStatsScreen(screen, font, scale, LO.TABLE_COLOR, "PAYOUTS", lines, {
    centerX = layout.centerX,
  })
end

local TUTORIAL_PAGES = {
  {
    title = "HOW TO PLAY",
    lines = {
      { text = "Beat the dealer", color = colors.white },
      { text = "without going over 21.", color = colors.white },
      { text = "Aces count as 1 or 11.", color = colors.cyan },
      { text = "Face cards count as 10.", color = colors.cyan },
      { text = "Dealer starts with one", color = colors.lightGray },
      { text = "hidden card.", color = colors.lightGray },
    },
  },
  {
    title = "TABLE RULES",
    lines = {
      { text = cfg.DEALER_HIT_SOFT_17 and "Dealer hits soft 17." or "Dealer stands on all 17s.", color = colors.yellow },
      { text = cfg.ALLOW_DOUBLE and ("Double: hard " .. tostring(cfg.DOUBLE_MIN_TOTAL) .. " only") or "Double is off.", color = colors.white },
      { text = cfg.ALLOW_SPLIT and ("Split pairs up to " .. tostring(cfg.MAX_SPLITS + 1) .. " hands") or "Split is off.", color = colors.white },
      { text = cfg.RESTRICT_SPLIT_ACES and "Split aces get one card." or "Split aces play normally.", color = colors.lightGray },
      { text = cfg.ALLOW_DOUBLE_AFTER_SPLIT and "Double after split is on." or "Double after split is off.", color = colors.lightGray },
      { text = cfg.ALLOW_INSURANCE and "Insurance is on." or "Insurance is off.", color = colors.lightBlue },
      { text = cfg.ALLOW_SURRENDER and "Surrender is on." or "Surrender is off.", color = colors.lightBlue },
    },
  },
  {
    title = "ACTIONS",
    lines = {
      { text = "HIT: take one more card", color = colors.white },
      { text = "STAND: keep your total", color = colors.white },
      { text = cfg.ALLOW_DOUBLE and "DOUBLE: one card, double bet" or "DOUBLE: unavailable here", color = colors.cyan },
      { text = cfg.ALLOW_SPLIT and "SPLIT: turn a pair into 2 hands" or "SPLIT: unavailable here", color = colors.cyan },
      { text = "Natural blackjack wins", color = colors.yellow },
      { text = "immediately unless dealer", color = colors.yellow },
      { text = "also has blackjack.", color = colors.yellow },
    },
  },
}

local function showTutorial()
  pages.showPagedLines(screen, font, scale, LO.TABLE_COLOR, TUTORIAL_PAGES, {
    centerX = layout.centerX,
  })
end

local function preRoundMenu()
  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "BLACKJACK"
    local tw = ui.getTextSize(title)
    ui.safeDrawText(screen, title, font, math.floor((width - tw) / 2), scale.titleY, colors.yellow)

    local subtitle = "Configured house rules"
    local sw = ui.getTextSize(subtitle)
    ui.safeDrawText(screen, subtitle, font, math.floor((width - sw) / 2), scale.subtitleY, colors.lightGray)

    ui.clearButtons()
    local chosen = nil

    ui.layoutButtonGrid(screen, {
      {
        { text = "PLAY", color = colors.lime, func = function() chosen = "play" end },
      },
      {
        { text = "PAYOUTS", color = colors.yellow, func = function() chosen = "payouts" end },
        { text = "HOW TO PLAY", color = colors.lightBlue, func = function() chosen = "tutorial" end },
      },
    }, layout.centerX, scale.menuY, scale.buttonRowSpacing, scale.buttonColGap)

    screen:output()

    ui.waitForButton(0, 0)

    if chosen == "play" then
      return
    elseif chosen == "payouts" then
      showPayoutTable()
    elseif chosen == "tutorial" then
      showTutorial()
    end
  end
end

local function doDeal(ctx)
  -- Pre-deal all 4 cards
  local p1 = dealOne()
  local d1 = dealOne()
  local p2 = dealOne()
  local d2 = dealOne()

  -- Animated deal: slide each card in one at a time
  -- Precompute final positions (2 cards each, centered)
  local playerStartX = math.floor((width - (2 * deltaX)) / 2)
  local dealerStartX = math.floor((width - (2 * deltaX)) / 2)

  -- Track which cards are visible for the background render
  local visiblePlayer = {}
  local visibleDealer = {}

  local betStr = "Bet: " .. currency.formatTokens(ctx.hands[1].bet)
  local function bgRender()
    screen:clear(LO.TABLE_COLOR)
    ui.safeDrawText(screen, betStr, font, 1, 0, colors.white)
    for i, cid in ipairs(visiblePlayer) do
      screen:drawSurface(cards.renderCard(cid), playerStartX + (i - 1) * deltaX, layout.playerY)
    end
    for i, cid in ipairs(visibleDealer) do
      local img = (i == 1) and cardBack or cards.renderCard(cid)
      screen:drawSurface(img, dealerStartX + (i - 1) * deltaX, layout.dealerY)
    end
  end

  -- Deal order: player1, dealer1 (face-down), player2, dealer2 (face-up)
  cardAnim.slideIn(cards.renderCard(p1), playerStartX, layout.playerY, bgRender)
  table.insert(visiblePlayer, p1)

  cardAnim.slideIn(cardBack, dealerStartX, layout.dealerY, bgRender)
  table.insert(visibleDealer, d1)

  cardAnim.slideIn(cards.renderCard(p2), playerStartX + deltaX, layout.playerY, bgRender)
  table.insert(visiblePlayer, p2)

  cardAnim.slideIn(cards.renderCard(d2), dealerStartX + deltaX, layout.dealerY, bgRender)
  table.insert(visibleDealer, d2)

  -- Set final hand state
  ctx.hands[1].cards = { p1, p2 }
  ctx.dealerHand = { d1, d2 }

  -- Record initial hand total (for houdini check)
  local initTotal = cards.blackjackValue(ctx.hands[1].cards)
  ctx.initialHandTotal = initTotal

  renderTable(ctx, true, nil)
  os.sleep(0.3)

  -- Check dealer up-card for insurance
  local dealerUp = ctx.dealerHand[2]:sub(1, 1)
  if dealerUp == "A" and cfg.ALLOW_INSURANCE then
    return "insurance"
  end

  return "check_naturals"
end

local function totalAtRisk(ctx)
  local atRisk = 0
  for _, hand in ipairs(ctx.hands or {}) do
    atRisk = atRisk + (hand.bet or 0)
  end
  atRisk = atRisk + (ctx.insuranceBet or 0)
  return atRisk
end

local function availableBalance(ctx)
  local bal = currency.getPlayerBalance()
  return math.max(0, bal - totalAtRisk(ctx))
end

local function currentHouseExposure(ctx)
  local exposure = 0
  for _, hand in ipairs(ctx.hands or {}) do
    exposure = exposure + (hand.bet or 0)
  end
  return exposure
end

local function hasHostCapacityForAdditionalBet(ctx, additionalBet)
  additionalBet = additionalBet or 0
  local protectedHostBalance = currency.getProtectedHostBalance(currency.getHostBalance())
  return protectedHostBalance >= (currentHouseExposure(ctx) + additionalBet)
end

local function bestLivePlayerTotal(ctx)
  local bestTotal = 0
  for _, hand in ipairs(ctx.hands or {}) do
    if not hand.busted and not hand.surrendered then
      local total = cards.blackjackValue(hand.cards)
      if total <= 21 and total > bestTotal then
        bestTotal = total
      end
    end
  end
  return bestTotal
end

local function dealerTargetTotal(ctx)
  local standTotal = cfg.DEALER_STAND
  local chaseTotal = tonumber(cfg.DEALER_CHASE_TOTAL)
  if not chaseTotal or chaseTotal < standTotal then
    return standTotal
  end

  local bestPlayerTotal = bestLivePlayerTotal(ctx)
  local chaseCeiling = chaseTotal + 1
  if bestPlayerTotal > 0 then
    return math.max(standTotal, math.min(bestPlayerTotal, chaseCeiling))
  end
  return standTotal
end

local function dealerMustHit(ctx)
  local dealerTotal, isSoft = cards.blackjackValue(ctx.dealerHand)
  local targetTotal = dealerTargetTotal(ctx)
  return dealerTotal < targetTotal
    or (cfg.DEALER_HIT_SOFT_17 and dealerTotal == 17 and isSoft)
end

local function canDoubleHand(ctx, hand)
  if not cfg.ALLOW_DOUBLE then return false end
  if #hand.cards ~= 2 then return false end
  if hand.fromSplit and not cfg.ALLOW_DOUBLE_AFTER_SPLIT then return false end

  local handTotal, isSoft = cards.blackjackValue(hand.cards)
  if isSoft and not cfg.ALLOW_SOFT_DOUBLE then return false end
  if handTotal < cfg.DOUBLE_MIN_TOTAL or handTotal > cfg.DOUBLE_MAX_TOTAL then return false end
  if availableBalance(ctx) < hand.bet then return false end
  if not hasHostCapacityForAdditionalBet(ctx, hand.bet) then return false end

  return true
end

local function canSplitHand(ctx, hand)
  if not cfg.ALLOW_SPLIT then return false end
  if #hand.cards ~= 2 then return false end
  if #ctx.hands >= (cfg.MAX_SPLITS + 1) then return false end

  local firstRank = cards.parseCard(hand.cards[1])
  local secondRank = cards.parseCard(hand.cards[2])
  if firstRank ~= secondRank then return false end

  if availableBalance(ctx) < hand.bet then return false end
  if not hasHostCapacityForAdditionalBet(ctx, hand.bet) then return false end

  return true
end

local function settleNetChange(netChange, reason)
  return settlement.applyNetChange(netChange, {
    winReason = reason,
    lossReason = reason,
    failurePrefix = "CRITICAL",
  })
end

-----------------------------------------------------
-- State: INSURANCE
-----------------------------------------------------
local function doInsurance(ctx)
  local maxIns = math.floor(ctx.hands[1].bet / 2)
  local playerBalance = availableBalance(ctx)

  if playerBalance < 1 then
    return "check_naturals"
  end

  local insBet = math.min(maxIns, playerBalance)

  -- Show insurance offer
  renderTable(ctx, true, "Insurance?")
  ui.clearButtons()
  local chosen = nil
  ui.layoutButtonGrid(screen, {{
    { text = "YES (" .. currency.formatTokens(insBet) .. ")", color = colors.cyan,
      func = function() chosen = true end },
    { text = "NO", color = colors.red,
      func = function() chosen = false end },
  }}, layout.centerX, layout.buttonY, scale.buttonRowSpacing, scale.buttonColGap)
  screen:output()
  ui.waitForButton(0, 0)

  if chosen then
    if insBet > 0 then
      ctx.insuranceBet = insBet
      ctx.insurancePaid = insBet
    end
  end

  return "check_naturals"
end

-----------------------------------------------------
-- State: CHECK_NATURALS
-----------------------------------------------------
local function doCheckNaturals(ctx)
  local playerBJ = cards.isBlackjack(ctx.hands[1].cards)
  local dealerBJ = cards.isBlackjack(ctx.dealerHand)
  local dTotal   = cards.blackjackValue(ctx.dealerHand)

  if playerBJ and dealerBJ then
    renderTable(ctx, false, nil)
    ui.displayCenteredMessage(screen, "Double Blackjack Push!", colors.yellow, 1.5)
    sound.play(sound.SOUNDS.PUSH)
    -- Push on main hand, insurance pays 2:1 when dealer has blackjack
    if ctx.insuranceBet > 0 then
      ctx.insuranceWon = ctx.insuranceBet * 2
    end
    ctx.outcome = OUT.PUSH
    ctx.netChange = (ctx.insuranceWon or 0)
    settleNetChange(ctx.netChange, "Blackjack: round settlement")
    recovery.clearBet()
    buildAndRecordResult(ctx, dTotal, false)
    ctx.summaryMessage = "Double Blackjack Push!"
    ctx.postRoundChoice = waitForReplayChoice(ctx, ctx.summaryMessage)
    return nil  -- round over
  end

  if playerBJ then
    renderTable(ctx, false, nil)
    ui.displayCenteredMessage(screen, "Blackjack!", colors.yellow, 1.5)
    sound.play(sound.SOUNDS.SUCCESS)
    local bonus = math.floor(ctx.hands[1].bet * cfg.BLACKJACK_PAYOUT)
    ctx.outcome = OUT.BLACKJACK
    ctx.netChange = bonus - (ctx.insuranceBet or 0)
    settleNetChange(ctx.netChange, "Blackjack: natural settlement")
    notifyHostOfWin(env.currentPlayer, bonus, "Blackjack: natural")
    recovery.clearBet()
    buildAndRecordResult(ctx, dTotal, false)
    ctx.summaryMessage = "Blackjack!"
    ctx.postRoundChoice = waitForReplayChoice(ctx, ctx.summaryMessage)
    return nil
  end

  if dealerBJ then
    renderTable(ctx, false, nil)
    ui.displayCenteredMessage(screen, "Dealer Blackjack!", colors.red, 1.5)
    sound.play(sound.SOUNDS.FAIL)
    if ctx.insuranceBet > 0 then
      ctx.insuranceWon = ctx.insuranceBet * 2
    end
    ctx.outcome = OUT.DEALER_WIN
    ctx.netChange = -ctx.hands[1].bet + (ctx.insuranceWon or 0)
    settleNetChange(ctx.netChange, "Blackjack: dealer natural settlement")
    recovery.clearBet()
    buildAndRecordResult(ctx, dTotal, false)
    ctx.summaryMessage = "Dealer Blackjack!"
    ctx.postRoundChoice = waitForReplayChoice(ctx, ctx.summaryMessage)
    return nil
  end

  -- No naturals — insurance remains a tracked side bet and is settled in doResolve.

  return "player_turn"
end

-----------------------------------------------------
-- Action executors
-----------------------------------------------------
local function executeHit(hand, ctx, handIdx)
  table.insert(hand.cards, dealOne())
  hand.hitCount = hand.hitCount + 1
  hand.lastAction = ACT.HIT
  table.insert(ctx.actionLog, { action = ACT.HIT, handIdx = handIdx, time = epoch("local") })

  -- Animate the new card sliding in
  local nCards = #hand.cards
  local toX, toY
  if #ctx.hands == 1 then
    local startX = math.floor((width - (nCards * deltaX)) / 2)
    toX = startX + (nCards - 1) * deltaX
  else
    local baseX
    if handIdx == 1 then
      baseX = math.floor(width / 4) - math.floor((nCards * deltaX) / 2)
    else
      baseX = math.floor(width * 3 / 4) - math.floor((nCards * deltaX) / 2)
    end
    toX = baseX + (nCards - 1) * deltaX
  end
  toY = layout.playerY
  local newCard = hand.cards[nCards]
  local savedCard = table.remove(hand.cards)
  cardAnim.slideIn(cards.renderCard(newCard), toX, toY, function()
    renderTableBase(ctx, true, nil)
  end)
  table.insert(hand.cards, savedCard)

  local t = cards.blackjackValue(hand.cards)
  if t > 21 then hand.busted = true; return true end
  if t == 21 then return true end
  return false
end

local function executeStand(hand, ctx, handIdx)
  if hand.lastAction ~= ACT.HIT then hand.lastAction = ACT.STAND end
  table.insert(ctx.actionLog, { action = ACT.STAND, handIdx = handIdx, time = epoch("local") })
  return true
end

local function executeDouble(hand, ctx, handIdx)
  if not canDoubleHand(ctx, hand) then
    sound.play(sound.SOUNDS.ERROR)
    ui.displayCenteredMessage(screen, "Double not allowed", colors.red, 0.8)
    return false
  end

  hand.bet = hand.bet * 2
  hand.doubled = true
  hand.lastAction = ACT.DOUBLE
  table.insert(ctx.actionLog, { action = ACT.DOUBLE, handIdx = handIdx, time = epoch("local") })
  table.insert(hand.cards, dealOne())

  local nCards = #hand.cards
  local startX = math.floor((width - (nCards * deltaX)) / 2)
  local toX = startX + (nCards - 1) * deltaX
  local newCard = hand.cards[nCards]
  local savedCard = table.remove(hand.cards)
  cardAnim.slideIn(cards.renderCard(newCard), toX, layout.playerY, function()
    renderTableBase(ctx, true, nil)
  end)
  table.insert(hand.cards, savedCard)

  local t = cards.blackjackValue(hand.cards)
  if t > 21 then hand.busted = true end
  return true
end

local function executeSplit(hand, ctx, handIdx)
  if not canSplitHand(ctx, hand) then
    sound.play(sound.SOUNDS.ERROR)
    ui.displayCenteredMessage(screen, "Split not allowed", colors.red, 0.8)
    return false
  end

  local splitBet = hand.bet
  local splitCard = table.remove(hand.cards, 2)
  local isSplitAces = (hand.cards[1]:sub(1, 1) == "A")
  local newHand = {
    cards = { splitCard }, bet = splitBet, doubled = false,
    fromSplit = true, busted = false, hitCount = 0, lastAction = ACT.STAND,
    splitAces = isSplitAces,
  }
  table.insert(hand.cards, dealOne())
  table.insert(newHand.cards, dealOne())
  hand.fromSplit = true
  hand.splitAces = isSplitAces
  ctx.splitCount = (ctx.splitCount or 0) + 1
  table.insert(ctx.actionLog, { action = ACT.SPLIT, handIdx = handIdx, time = epoch("local") })
  table.insert(ctx.hands, handIdx + 1, newHand)

  -- Animate the two new cards dealt to each split hand
  -- Hand 1 (left): second card slides in
  local h1Cards = hand.cards
  local base1 = math.floor(width / 4) - math.floor((#h1Cards * deltaX) / 2)
  local saved1 = table.remove(hand.cards)
  cardAnim.slideIn(cards.renderCard(saved1), base1 + (#hand.cards) * deltaX, layout.playerY, function()
    renderTableBase(ctx, true, nil)
  end)
  table.insert(hand.cards, saved1)

  -- Hand 2 (right): second card slides in
  local h2Cards = newHand.cards
  local base2 = math.floor(width * 3 / 4) - math.floor((#h2Cards * deltaX) / 2)
  local saved2 = table.remove(newHand.cards)
  cardAnim.slideIn(cards.renderCard(saved2), base2 + (#newHand.cards) * deltaX, layout.playerY, function()
    renderTableBase(ctx, true, nil)
  end)
  table.insert(newHand.cards, saved2)

  if cfg.RESTRICT_SPLIT_ACES and isSplitAces then
    hand.lastAction = ACT.STAND
    newHand.lastAction = ACT.STAND
    return true
  end

  return false -- stay on current hand
end

local function executeSurrender(ctx, handIdx)
  ctx.surrendered = true
  table.insert(ctx.actionLog, { action = ACT.SURRENDER, handIdx = handIdx, time = epoch("local") })
  return true
end

-----------------------------------------------------
-- State: PLAYER_TURN (supports split)
-----------------------------------------------------
local function doPlayerTurn(ctx)
  local handIdx = 1
  ctx.currentHandIdx = handIdx

  while handIdx <= #ctx.hands do
    local hand = ctx.hands[handIdx]
    ctx.currentHandIdx = handIdx
    local handDone = false

    -- Split aces: one card only, auto-stand
    if cfg.RESTRICT_SPLIT_ACES and hand.splitAces then
      hand.lastAction = ACT.STAND
      table.insert(ctx.actionLog, { action = ACT.STAND, handIdx = handIdx, time = epoch("local") })
      handDone = true
    end

    while not handDone do
      renderTable(ctx, true, nil)

      local actionStart = epoch("local")
      ui.clearButtons()
      local rows = {}
      local row1 = {}
      local row2 = {}

      table.insert(row1, {
        text = "HIT", color = colors.lightBlue,
        func = function()
          table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
          handDone = executeHit(hand, ctx, handIdx)
        end,
      })

      table.insert(row1, {
        text = "STAND", color = colors.yellow,
        func = function()
          table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
          handDone = executeStand(hand, ctx, handIdx)
        end,
      })

      if canDoubleHand(ctx, hand) then
        table.insert(row2, {
          text = "DOUBLE", color = colors.orange,
          func = function()
            table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
            handDone = executeDouble(hand, ctx, handIdx)
          end,
        })
      end

      if canSplitHand(ctx, hand) then
        table.insert(row2, {
          text = "SPLIT", color = colors.purple,
          func = function()
            table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
            handDone = executeSplit(hand, ctx, handIdx)
          end,
        })
      end

      if cfg.ALLOW_SURRENDER and hand.hitCount == 0 and not hand.fromSplit and #ctx.actionLog == 0 then
        table.insert(row2, {
          text = "SURRENDER", color = colors.gray,
          func = function()
            table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
            handDone = executeSurrender(ctx, handIdx)
          end,
        })
      end

      table.insert(rows, row1)
      if #row2 > 0 then table.insert(rows, row2) end
      local startY = scale:buttonBlockTop(layout.buttonY, #rows, scale.buttonRowSpacing)
      ui.layoutButtonGrid(screen, rows, layout.centerX, startY, scale.buttonRowSpacing, scale.buttonColGap)
      screen:output()
      ui.waitForButton(0, 0)
    end

    if ctx.surrendered then
      return "resolve"
    end

    handIdx = handIdx + 1
  end

  local allBusted = true
  for _, h in ipairs(ctx.hands) do
    if not h.busted then allBusted = false; break end
  end

  if allBusted then
    return "resolve"
  end

  return "dealer_turn"
end

-----------------------------------------------------
-- State: DEALER_TURN
-----------------------------------------------------
local function doDealerTurn(ctx)
  renderTable(ctx, false, nil)
  os.sleep(0.5)

  while dealerMustHit(ctx) do
    table.insert(ctx.dealerHand, dealOne())

    local nCards = #ctx.dealerHand
    local dealerStartX = math.floor((width - (nCards * deltaX)) / 2)
    local toX = dealerStartX + (nCards - 1) * deltaX
    local newCard = ctx.dealerHand[nCards]
    local savedCard = table.remove(ctx.dealerHand)
    cardAnim.slideIn(cards.renderCard(newCard), toX, layout.dealerY, function()
      renderTableBase(ctx, false, nil)
    end)
    table.insert(ctx.dealerHand, savedCard)
    renderTable(ctx, false, nil)
    os.sleep(0.3)
  end

  return "resolve"
end

-----------------------------------------------------
-- Resolve helpers
-----------------------------------------------------
local function resolveHandOutcomes(ctx, dealerTotal, dealerBusted)
  local totalNetChange = 0
  for _, hand in ipairs(ctx.hands) do
    local pTotal = cards.blackjackValue(hand.cards)
    if hand.busted then
      hand.outcome = OUT.BUST
      totalNetChange = totalNetChange - hand.bet
    elseif dealerBusted then
      hand.outcome = OUT.PLAYER_WIN
      totalNetChange = totalNetChange + hand.bet
    elseif pTotal > dealerTotal then
      hand.outcome = OUT.PLAYER_WIN
      totalNetChange = totalNetChange + hand.bet
    elseif pTotal < dealerTotal then
      hand.outcome = OUT.DEALER_WIN
      totalNetChange = totalNetChange - hand.bet
    else
      hand.outcome = OUT.PUSH
    end
  end
  return totalNetChange
end

local function displayRoundResult(ctx, dealerBusted)
  local primary = ctx.hands[1]
  local msg, msgClr, snd
  if primary.busted then
    msg = "Bust!"; msgClr = colors.red; snd = sound.SOUNDS.FAIL
  elseif primary.outcome == OUT.PLAYER_WIN then
    if dealerBusted then msg = "Dealer Busts! You Win!" else msg = "You Win!" end
    msgClr = colors.yellow; snd = sound.SOUNDS.SUCCESS
  elseif primary.outcome == OUT.DEALER_WIN then
    msg = "Dealer Wins"; msgClr = colors.red; snd = sound.SOUNDS.FAIL
  else
    msg = "Push"; msgClr = colors.white; snd = sound.SOUNDS.PUSH
  end

  if #ctx.hands > 1 then
    local handLabels = {}
    for i, h in ipairs(ctx.hands) do
      if h.busted then handLabels[i] = "Bust"
      elseif h.outcome == OUT.PLAYER_WIN then handLabels[i] = "Win"
      elseif h.outcome == OUT.DEALER_WIN then handLabels[i] = "Loss"
      else handLabels[i] = "Push" end
    end

    for i, h in ipairs(ctx.hands) do
      ctx.currentHandIdx = i
      renderTable(ctx, false, nil)
      local hClr = (h.outcome == OUT.PLAYER_WIN) and colors.yellow
                    or (h.busted or h.outcome == OUT.DEALER_WIN) and colors.red
                    or colors.white
      ui.displayCenteredMessage(screen, "Hand " .. i .. ": " .. handLabels[i], hClr, 0.8)
    end

    msg = "Hand 1: " .. handLabels[1] .. "  |  Hand 2: " .. handLabels[2]
    local anyWin = false
    for _, h in ipairs(ctx.hands) do
      if h.outcome == OUT.PLAYER_WIN then anyWin = true; break end
    end
    msgClr = anyWin and colors.yellow or colors.red
    snd = anyWin and sound.SOUNDS.SUCCESS or sound.SOUNDS.FAIL
  end

  renderTable(ctx, false, nil)
  ui.displayCenteredMessage(screen, msg, msgClr, 1.5)
  sound.play(snd)
  ctx.summaryMessage = msg
end

-----------------------------------------------------
-- State: RESOLVE + PAYOUT
-----------------------------------------------------
local function doResolve(ctx)
  local dealerTotal = cards.blackjackValue(ctx.dealerHand)
  local dealerBusted = dealerTotal > 21

  -- Surrender shortcut
  if ctx.surrendered then
    local hand = ctx.hands[1]
    local halfBet = math.floor(hand.bet / 2)
    ctx.outcome = OUT.DEALER_WIN
    ctx.netChange = -hand.bet + halfBet
    settleNetChange(ctx.netChange, "Blackjack: surrender settlement")
    renderTable(ctx, false, nil)
    ui.displayCenteredMessage(screen, "Surrendered", colors.gray, 1.5)
    sound.play(sound.SOUNDS.FAIL)
    recovery.clearBet()
    buildAndRecordResult(ctx, dealerTotal, dealerBusted)
    ctx.summaryMessage = "Surrendered"
    ctx.postRoundChoice = waitForReplayChoice(ctx, ctx.summaryMessage)
    return
  end

  -- Resolve each hand outcome and process payouts
  local totalNetChange = resolveHandOutcomes(ctx, dealerTotal, dealerBusted)

  -- Display result
  displayRoundResult(ctx, dealerBusted)

  -- Determine overall outcome
  local primary = ctx.hands[1]
  if primary.busted then
    ctx.outcome = OUT.BUST
  elseif primary.outcome == OUT.PLAYER_WIN then
    ctx.outcome = OUT.PLAYER_WIN
  elseif primary.outcome == OUT.DEALER_WIN then
    ctx.outcome = OUT.DEALER_WIN
  else
    ctx.outcome = OUT.PUSH
  end

  -- Subtract insurance loss
  totalNetChange = totalNetChange - (ctx.insuranceBet or 0)
  ctx.netChange = totalNetChange
  settleNetChange(totalNetChange, "Blackjack: round settlement")

  -- Notify host if player won
  if totalNetChange > 0 then
    notifyHostOfWin(env.currentPlayer, totalNetChange, ctx.outcome or "win")
  end

  recovery.clearBet()

  buildAndRecordResult(ctx, dealerTotal, dealerBusted)
  ctx.postRoundChoice = waitForReplayChoice(ctx, ctx.summaryMessage or "Round complete")
end

-- Legacy statistics hook
-----------------------------------------------------
buildAndRecordResult = function(ctx, dealerTotal, dealerBusted)
  return nil
end

-----------------------------------------------------
-- Round runner (state machine)
-----------------------------------------------------
local function blackjackRound(currentBet)
  recovery.saveBet(currentBet)

  local ctx = {
    hands = {
      {
        cards      = {},
        bet        = currentBet,
        doubled    = false,
        fromSplit  = false,
        busted     = false,
        hitCount   = 0,
        lastAction = ACT.STAND,
        outcome    = nil,
        netChange  = 0,
      },
    },
    currentHandIdx   = 1,
    dealerHand       = {},
    insuranceBet     = 0,
    insurancePaid    = 0,
    insuranceWon     = 0,
    surrendered      = false,
    splitCount       = 0,
    outcome          = nil,
    netChange        = 0,
    handStartTime    = epoch("local"),
    initialHandTotal = 0,
    actionLog        = {},
    decisionTimes    = {},
  }

  local state = "deal"
  local transitions = {
    deal           = doDeal,
    insurance      = doInsurance,
    check_naturals = doCheckNaturals,
    player_turn    = doPlayerTurn,
    dealer_turn    = doDealerTurn,
    resolve        = doResolve,
  }

  while state do
    local handler = transitions[state]
    if not handler then
      dbg("Unknown state: " .. tostring(state))
      break
    end
    state = handler(ctx)
    -- Save snapshot after each phase so crash recovery knows the game state
    if state then
      recovery.saveSnapshot(ctx.hands[1].bet, { phase = state })
    end
  end

  return ctx.postRoundChoice
end

-----------------------------------------------------
-- Bet selection
-----------------------------------------------------
local function betSelection()
  return betting.runBetScreen(screen, {
    maxBet                 = getMaxBet(),
    gameName               = "Blackjack",
    confirmLabel           = "DEAL",
    title                  = "PLACE YOUR BET",
    hostBalance            = currency.getProtectedHostBalance(hostBankBalance),
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
  })
end

local function canReplayBet(betAmount)
  if not betAmount or betAmount <= 0 then
    return false, "Choose a new bet first."
  end

  if currency.getPlayerBalance() < betAmount then
    return false, "Lower the bet before playing again."
  end

  if getMaxBet() < betAmount then
    if getMaxBet() <= 0 then
      return false, "House limit is too low to replay right now."
    end
    return true, "House limit changed. Next round will use " .. currency.formatTokens(getMaxBet()) .. "."
  end

  return true
end

local function getReplayBetAmount(betAmount)
  if not betAmount or betAmount <= 0 then
    return nil
  end

  if currency.getPlayerBalance() < betAmount then
    return nil
  end

  local maxBet = getMaxBet()
  if maxBet <= 0 then
    return nil
  end

  return math.min(betAmount, maxBet)
end

waitForReplayChoice = function(ctx, statusText)
  local choiceHintY = math.max(scale.subtitleY, layout.buttonY - scale.buttonRowSpacing - scale.lineHeight - 2)

  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderTable(ctx, false, statusText)
    end,
    hint = function()
      local replayAvailable, replayHint = canReplayBet(ctx.hands[1].bet)
      if replayAvailable then
        return nil
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
            return canReplayBet(ctx.hands[1].bet)
          end,
          disabled_message = "Pick a new bet before playing again.",
        },
        {
          id = "bet",
          text = "CHANGE BET",
          color = colors.orange,
        },
      },
    },
    center_x = layout.centerX,
    button_y = layout.buttonY,
    row_spacing = scale.buttonRowSpacing,
    col_spacing = scale.buttonColGap,
  })
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
    refreshPlayer()
    drawPlayerOverlay()

    local bet = nil
    if replayBetAmount and canReplayBet(replayBetAmount) then
      bet = getReplayBetAmount(replayBetAmount)
      replayBetAmount = nil
    else
      replayBetAmount = nil
      preRoundMenu()
      bet = betSelection()
    end

    if bet and bet > 0 then
      local roundChoice = blackjackRound(bet)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
      replayBetAmount = (roundChoice == "play_again") and bet or nil
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
