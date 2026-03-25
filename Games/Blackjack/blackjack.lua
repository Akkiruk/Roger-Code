-- blackjack.lua
-- Blackjack card game for ComputerCraft casino.
-- State-machine architecture with split, insurance, and surrender support.
-- Complete GameResult population for all 102 achievements.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("blackjack_config")

local ACT = cfg.ACTIONS
local OUT = cfg.OUTCOMES
local LO  = cfg.LAYOUT

local ostime       = os.time
local settings_get = settings.get
local r_getInput   = redstone.getInput
local epoch        = os.epoch

-- Forward declarations
local buildAndRecordResult = nil

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
local autoPlayer = require("lib.auto_player")
local cardAnim   = require("lib.card_anim")

-----------------------------------------------------
-- Auto-play state
-----------------------------------------------------
local AUTO_PLAY          = false
local AUTO_PLAY_COUNTER  = 0
local AUTO_PLAY_STRATEGY = 1

local function updateAutoPlayFromRedstone()
  local powered = r_getInput(cfg.REDSTONE)
  if powered ~= AUTO_PLAY then
    AUTO_PLAY = powered
    if AUTO_PLAY then
      AUTO_PLAY_COUNTER  = 0
      AUTO_PLAY_STRATEGY = autoPlayer.randomStrategy()
      dbg("Auto-play ON, strategy " .. AUTO_PLAY_STRATEGY)
    else
      dbg("Auto-play OFF")
    end
  end
  return AUTO_PLAY
end

-----------------------------------------------------
-- Initialize game environment
-----------------------------------------------------
recovery.configure(cfg.RECOVERY_FILE)

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount   = cfg.DECK_COUNT,
  gameName    = cfg.GAME_NAME,
  logFile     = cfg.LOG_FILE,
  initPlayerStats = true,
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
local openingBankValue = hostBankBalance
dbg("Initial host balance: " .. hostBankBalance .. " tokens")

local function getMaxBet()
  return math.floor(hostBankBalance * cfg.MAX_BET_PERCENT)
end

-----------------------------------------------------
-- Statistics module (optional)
-----------------------------------------------------
local statistics = nil
local function loadStatistics()
  local ok, result = pcall(require, "statistics")
  if ok then
    statistics = result
    pcall(statistics.init)
    return true
  end
  dbg("Statistics module unavailable: " .. tostring(result))
  statistics = {
    init             = function() return true end,
    getActivePlayer  = function() return "Unknown" end,
    loadPlayerStats  = function() return {} end,
    recordGameResult = function() return {} end,
  }
  return false
end

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
-- Card analysis helpers (for GameResult)
-----------------------------------------------------
local function analyzeHand(hand)
  local allBlack, allRed = true, true
  local clubCount, aceCount = 0, 0
  local hasSeven = false
  local suitSet = {}

  for _, c in ipairs(hand) do
    if not cards.isBlack(c) then allBlack = false end
    if not cards.isRed(c)   then allRed   = false end
    local suit = cards.getSuit(c)
    suitSet[suit] = true
    if suit == "club" then clubCount = clubCount + 1 end
    if c:sub(1, 1) == "A" then aceCount = aceCount + 1 end
    if c:sub(1, 1) == "7" then hasSeven = true end
  end

  local suitCount = 0
  for _ in pairs(suitSet) do suitCount = suitCount + 1 end

  return {
    allBlack  = allBlack,
    allRed    = allRed,
    clubCount = clubCount,
    aceCount  = aceCount,
    hasSeven  = hasSeven,
    allSuits  = suitCount >= 4,
  }
end

-----------------------------------------------------
-- State: DEAL
-----------------------------------------------------
local function doDeal(ctx)
  -- Pre-deal all 4 cards
  local p1 = dealOne()
  local d1 = dealOne()
  local p2 = dealOne()
  local d2 = dealOne()

  if not AUTO_PLAY then
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
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

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
  if dealerUp == "A" and cfg.ALLOW_INSURANCE and not AUTO_PLAY then
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
  return currency.getHostBalance() >= (currentHouseExposure(ctx) + additionalBet)
end

local function settleNetChange(netChange, reason)
  if netChange > 0 then
    if not currency.payout(netChange, reason) then
      alert.send("CRITICAL: Failed to pay " .. netChange .. " tokens")
      return false
    end
    return true
  elseif netChange < 0 then
    local chargeAmt = -netChange
    local ok = currency.charge(chargeAmt, reason)
    if not ok then
      alert.send("CRITICAL: Failed to charge " .. chargeAmt .. " tokens")
      return false
    end
  end
  return true
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
    return nil
  end

  -- No naturals — insurance remains a tracked side bet and is settled in doResolve.

  return "player_turn"
end

-----------------------------------------------------
-- Action executors (shared by auto-play and human)
-----------------------------------------------------
local function executeHit(hand, ctx, handIdx)
  table.insert(hand.cards, dealOne())
  hand.hitCount = hand.hitCount + 1
  hand.lastAction = ACT.HIT
  table.insert(ctx.actionLog, { action = ACT.HIT, handIdx = handIdx, time = epoch("local") })

  if not AUTO_PLAY then
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
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

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
  local additionalBet = hand.bet
  if availableBalance(ctx) < additionalBet then
    if not AUTO_PLAY then
      sound.play(sound.SOUNDS.ERROR)
      ui.displayCenteredMessage(screen, "Insufficient funds!", colors.red, 0.8)
    end
    return false
  end
  if not hasHostCapacityForAdditionalBet(ctx, additionalBet) then
    if not AUTO_PLAY then
      sound.play(sound.SOUNDS.ERROR)
      ui.displayCenteredMessage(screen, "House limit reached!", colors.red, 0.8)
    end
    return false
  end
  hand.bet = hand.bet * 2
  hand.doubled = true
  hand.lastAction = ACT.DOUBLE
  table.insert(ctx.actionLog, { action = ACT.DOUBLE, handIdx = handIdx, time = epoch("local") })
  table.insert(hand.cards, dealOne())

  if not AUTO_PLAY then
    local nCards = #hand.cards
    local startX = math.floor((width - (nCards * deltaX)) / 2)
    local toX = startX + (nCards - 1) * deltaX
    local newCard = hand.cards[nCards]
    local savedCard = table.remove(hand.cards)
    cardAnim.slideIn(cards.renderCard(newCard), toX, layout.playerY, function()
      renderTableBase(ctx, true, nil)
    end)
    table.insert(hand.cards, savedCard)
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  local t = cards.blackjackValue(hand.cards)
  if t > 21 then hand.busted = true end
  return true
end

local function executeSplit(hand, ctx, handIdx)
  local splitBet = hand.bet
  if availableBalance(ctx) < splitBet then
    if not AUTO_PLAY then
      sound.play(sound.SOUNDS.ERROR)
      ui.displayCenteredMessage(screen, "Insufficient funds!", colors.red, 0.8)
    end
    return false
  end
  if not hasHostCapacityForAdditionalBet(ctx, splitBet) then
    if not AUTO_PLAY then
      sound.play(sound.SOUNDS.ERROR)
      ui.displayCenteredMessage(screen, "House limit reached!", colors.red, 0.8)
    end
    return false
  end
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

  if not AUTO_PLAY then
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
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
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

      if AUTO_PLAY then
        os.sleep(cfg.AUTO_PLAY_DELAY)
        local canDbl = #hand.cards == 2
                       and availableBalance(ctx) >= hand.bet
                       and hasHostCapacityForAdditionalBet(ctx, hand.bet)
        local canSpl = #hand.cards == 2 and cfg.ALLOW_SPLIT
                       and #ctx.hands < (cfg.MAX_SPLITS + 1)
                       and cards.FACE_VALUES[hand.cards[1]:sub(1, 1)] == cards.FACE_VALUES[hand.cards[2]:sub(1, 1)]
                       and availableBalance(ctx) >= hand.bet
                       and hasHostCapacityForAdditionalBet(ctx, hand.bet)
        local action = autoPlayer.decide(hand.cards, ctx.dealerHand[2], canDbl, canSpl, AUTO_PLAY_STRATEGY)

        if action == ACT.HIT then       handDone = executeHit(hand, ctx, handIdx)
        elseif action == ACT.DOUBLE then handDone = executeDouble(hand, ctx, handIdx)
        elseif action == ACT.SPLIT then  handDone = executeSplit(hand, ctx, handIdx)
        else                             handDone = executeStand(hand, ctx, handIdx)
        end

      else
        -- Human player
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

        if #hand.cards == 2
           and availableBalance(ctx) >= hand.bet
           and hasHostCapacityForAdditionalBet(ctx, hand.bet) then
          table.insert(row2, {
            text = "DOUBLE", color = colors.orange,
            func = function()
              table.insert(ctx.decisionTimes, (epoch("local") - actionStart) / 1000)
              handDone = executeDouble(hand, ctx, handIdx)
            end,
          })
        end

        if #hand.cards == 2 and cfg.ALLOW_SPLIT
           and #ctx.hands < (cfg.MAX_SPLITS + 1)
           and cards.FACE_VALUES[hand.cards[1]:sub(1, 1)] == cards.FACE_VALUES[hand.cards[2]:sub(1, 1)]
            and availableBalance(ctx) >= hand.bet
            and hasHostCapacityForAdditionalBet(ctx, hand.bet) then
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

  while true do
    local dealerTotal, isSoft = cards.blackjackValue(ctx.dealerHand)
    local mustHit = dealerTotal < cfg.DEALER_STAND
                    or (cfg.DEALER_HIT_SOFT_17 and dealerTotal == 17 and isSoft)
    if not mustHit then break end
    table.insert(ctx.dealerHand, dealOne())

    if not AUTO_PLAY then
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
    else
      sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
      renderTable(ctx, false, nil)
      os.sleep(0.5)
    end
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
    return
  end

  -- Resolve each hand outcome and process payouts
  local totalNetChange = resolveHandOutcomes(ctx, dealerTotal, dealerBusted)

  -- Display result
  displayRoundResult(ctx, dealerBusted)

  -- Determine overall outcome for stats
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

  -- Record stats
  buildAndRecordResult(ctx, dealerTotal, dealerBusted)
end

-----------------------------------------------------
-- Achievement flag computation (extracted for clarity)
-----------------------------------------------------
local function computeAchievementFlags(ctx, dealerTotal, dealerBusted)
  local primary = ctx.hands[1]
  local pTotal, pSoft = cards.blackjackValue(primary.cards)
  local analysis = analyzeHand(primary.cards)
  local isWin  = ctx.outcome == OUT.PLAYER_WIN or ctx.outcome == OUT.BLACKJACK
  local isLoss = ctx.outcome == OUT.DEALER_WIN or ctx.outcome == OUT.BUST
  local isPush = ctx.outcome == OUT.PUSH
  local cardCount = #primary.cards
  local hitCount  = primary.hitCount or 0
  local handDuration = (epoch("local") - ctx.handStartTime) / 1000

  local f = {}

  f.isSevenCardCharlie = isWin and cardCount >= 7
  f.isRainbowWin       = isWin and analysis.allSuits
  f.isSoft21Win        = isWin and pTotal == 21 and pSoft
  f.isEdgeOutWin       = isWin and not dealerBusted and (pTotal - dealerTotal) == 1
  f.isFiveClubWin      = isWin and analysis.clubCount >= 5
  f.isHoudini          = isWin and (ctx.initialHandTotal or 99) <= 12 and hitCount >= 3 and pTotal == 21
  f.isShutout          = isWin and dealerBusted and pTotal <= 12
  f.isRiskyDouble      = isWin and primary.doubled and ctx.initialHandTotal == 9
  f.isQuickHand        = isWin and handDuration < 6
  f.isStonewall        = isPush and pTotal <= 12 and (primary.lastAction == ACT.STAND or hitCount == 0)
  f.isAllRedLoss       = isLoss and analysis.allRed
  f.isMirrorMatch      = isPush and pTotal == dealerTotal and cardCount == #ctx.dealerHand
  f.isQuadAce          = isWin and analysis.aceCount >= 4

  -- Overkill: hit on 20, drew Ace, made 21, won
  f.isOverkill = false
  if isWin and pTotal == 21 and hitCount > 0 then
    local preHitTotal, aces = 0, 0
    for j = 1, cardCount - 1 do
      local v = primary.cards[j]:sub(1, 1)
      preHitTotal = preHitTotal + cards.FACE_VALUES[v]
      if v == "A" then aces = aces + 1 end
    end
    while preHitTotal > 21 and aces > 0 do preHitTotal = preHitTotal - 10; aces = aces - 1 end
    if preHitTotal == 20 and primary.cards[cardCount]:sub(1, 1) == "A" then f.isOverkill = true end
  end

  -- Snap decision: all decisions < 0.5s, won
  f.isSnapDecision = false
  if isWin and #ctx.decisionTimes > 0 then
    f.isSnapDecision = true
    for _, dt in ipairs(ctx.decisionTimes) do
      if dt >= 0.5 then f.isSnapDecision = false; break end
    end
  end

  -- Slow burn: all decisions > 15s, won
  f.isSlowBurn = false
  if isWin and #ctx.decisionTimes > 0 then
    f.isSlowBurn = true
    for _, dt in ipairs(ctx.decisionTimes) do
      if dt <= 15 then f.isSlowBurn = false; break end
    end
  end

  -- Bank buster
  local bankAfter = currency.getHostBalance()
  f.isBankBuster = isWin and openingBankValue > 0 and bankAfter < (openingBankValue * 0.1)

  -- Split-specific flags
  f.isPerfectPair, f.isTwinBlackjack, f.isPrecisionSplit = false, false, false
  f.splitWins = 0
  if #ctx.hands > 1 then
    local allSplitWin = true
    for _, h in ipairs(ctx.hands) do
      if h.outcome == OUT.PLAYER_WIN then f.splitWins = f.splitWins + 1
      else allSplitWin = false end
    end
    f.isPerfectPair = allSplitWin and #ctx.hands == 2

    if ctx.hands[1].fromSplit and #ctx.hands == 2 then
      local bj1 = cards.isBlackjack(ctx.hands[1].cards)
      local bj2 = cards.isBlackjack(ctx.hands[2].cards)
      f.isTwinBlackjack = bj1 and bj2
    end

    if f.isPerfectPair then
      local t1 = cards.blackjackValue(ctx.hands[1].cards)
      local t2 = cards.blackjackValue(ctx.hands[2].cards)
      local wasEightPair = ctx.initialHandTotal == 16
      f.isPrecisionSplit = wasEightPair and t1 == 21 and t2 == 21
    end
  end

  return f
end

-----------------------------------------------------
-- GameResult builder + stat recording
-----------------------------------------------------
buildAndRecordResult = function(ctx, dealerTotal, dealerBusted)
  if not statistics then return end

  local primary = ctx.hands[1]
  local pTotal, pSoft = cards.blackjackValue(primary.cards)
  local analysis = analyzeHand(primary.cards)
  local cardCount = #primary.cards
  local hitCount  = primary.hitCount or 0

  local handDuration = (epoch("local") - ctx.handStartTime) / 1000
  local totalDecisionMs = 0
  for _, dt in ipairs(ctx.decisionTimes) do totalDecisionMs = totalDecisionMs + dt end

  local flags = computeAchievementFlags(ctx, dealerTotal, dealerBusted)

  -- Determine primary action for stats
  local primaryAction = primary.lastAction or ACT.STAND
  if primary.doubled then primaryAction = ACT.DOUBLE end
  if ctx.splitCount and ctx.splitCount > 0 and not primary.doubled then primaryAction = ACT.SPLIT end

  -- Start from achievement flags, overlay game data
  local gr = flags
  gr.outcome          = ctx.outcome
  gr.bet              = primary.bet
  gr.netChange        = ctx.netChange
  gr.handScore        = pTotal
  gr.cardCount        = cardCount
  gr.dealerScore      = dealerTotal
  gr.dealerCardCount  = #ctx.dealerHand
  gr.dealerUpCard     = cards.displayValue(ctx.dealerHand[2])
  gr.dealerBusted     = dealerBusted
  gr.actions          = primaryAction
  gr.hitCount         = hitCount
  gr.decisionTime     = totalDecisionMs * 1000
  gr.decisionTimes    = ctx.decisionTimes
  gr.handDuration     = handDuration

  -- Card analysis
  gr.hasSoftHand      = pSoft
  gr.hasSevenCard     = analysis.hasSeven
  gr.allBlackCards    = analysis.allBlack
  gr.allRedCards       = analysis.allRed
  gr.clubCount        = analysis.clubCount
  gr.aceCount         = analysis.aceCount
  gr.hasAllSuits      = analysis.allSuits
  gr.isMaxBet         = primary.bet >= getMaxBet()
  gr.isFiveCard21     = cardCount >= 5 and pTotal == 21
  gr.is21With3Cards   = cardCount == 3 and pTotal == 21
  gr.tripleHitSuccess = hitCount >= 3 and not primary.busted
  gr.lost666          = ctx.netChange == -666

  -- Split
  gr.isSplitHand      = #ctx.hands > 1
  gr.splitCount       = ctx.splitCount or 0

  -- Insurance / surrender
  gr.insurancePaid    = ctx.insurancePaid or 0
  gr.insuranceWon     = ctx.insuranceWon or 0
  gr.surrendered      = ctx.surrendered or false

  pcall(statistics.recordGameResult, env.currentPlayer, gr)
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
-- Main loop
-----------------------------------------------------
sound.play(sound.SOUNDS.BOOT)
recovery.recoverBet(true)
loadStatistics()
refreshPlayer()

local function main()
  while true do
    updateAutoPlayFromRedstone()
    refreshPlayer()
    drawPlayerOverlay()

    local bet = nil
    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      local autoBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if autoBet > 0 then
        if playerBalance >= autoBet then
          bet = autoBet
          os.sleep(cfg.AUTO_PLAY_DELAY)
        else
          os.sleep(1)
        end
      else
        os.sleep(1)
      end
      AUTO_PLAY_COUNTER = AUTO_PLAY_COUNTER + 1
      if AUTO_PLAY_COUNTER % cfg.STRATEGY_CHANGE_FREQ == 0 then
        AUTO_PLAY_STRATEGY = autoPlayer.randomStrategy()
        dbg("Strategy changed to " .. AUTO_PLAY_STRATEGY)
      end
    else
      bet = betSelection()
    end

    if bet and bet > 0 then
      blackjackRound(bet)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
