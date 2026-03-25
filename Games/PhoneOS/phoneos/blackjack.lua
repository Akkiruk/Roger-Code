local cards    = require("lib.cards")
local currency = require("lib.currency")
local sound    = require("lib.sound")
local alert    = require("lib.alert")
local recovery = require("lib.crash_recovery")

local M = {}
local RECOVERY_FILE_NAME = "phone_blackjack_recovery.dat"
local RECOVERY_GAME_NAME = "Pocket Blackjack"
local ROUND_SNAPSHOT_KIND = "phone_blackjack_round"
local ROUND_SCHEMA_VERSION = 1
local SETTLEMENT_REASON_PREFIX = "phbj:"
local SETTLEMENT_HISTORY_LIMIT = 40

local SUIT_SHORT = {
  heart = "H",
  diamond = "D",
  club = "C",
  spade = "S",
}

local function cardLabel(card)
  return cards.displayValue(card) .. (SUIT_SHORT[cards.getSuit(card)] or "?")
end

local function handLabel(hand)
  local parts = {}
  for i, card in ipairs(hand) do
    parts[i] = cardLabel(card)
  end
  return table.concat(parts, " ")
end

local function drawWrapped(ui, x, y, width, text, color)
  local lines = ui.wrap(text, width)
  for i, line in ipairs(lines) do
    ui.writeAt(x, y + i - 1, line, color or colors.white)
  end
  return #lines
end

local function currentWager(ctx)
  local total = ctx.insuranceBet or 0
  for _, hand in ipairs(ctx.hands) do
    total = total + (hand.bet or 0)
  end
  return total
end

local function recoveryPath(env)
  return fs.combine(env.dataDir, RECOVERY_FILE_NAME)
end

local function configureRecovery(env, playerName)
  recovery.configure(recoveryPath(env))
  recovery.setGame(RECOVERY_GAME_NAME)
  recovery.setPlayer(playerName or "Unknown")
end

local function makeRoundId()
  return tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("local"))
end

local function cloneSequential(list)
  local copy = {}
  for i, value in ipairs(list or {}) do
    copy[i] = value
  end
  return copy
end

local function cloneHand(hand)
  return {
    cards = cloneSequential(hand.cards),
    bet = hand.bet or 0,
    hitCount = hand.hitCount or 0,
    fromSplit = hand.fromSplit == true,
    doubled = hand.doubled == true,
    busted = hand.busted == true,
    splitAces = hand.splitAces == true,
    surrendered = hand.surrendered == true,
    result = hand.result,
  }
end

local function buildSnapshot(ctx, phase)
  local hands = {}
  for i, hand in ipairs(ctx.hands or {}) do
    hands[i] = cloneHand(hand)
  end

  return {
    kind = ROUND_SNAPSHOT_KIND,
    schema = ROUND_SCHEMA_VERSION,
    phase = phase,
    roundId = ctx.roundId,
    playerName = ctx.playerName,
    selfPlay = ctx.selfPlay == true,
    deck = cloneSequential(ctx.deck),
    dealerHand = cloneSequential(ctx.dealerHand),
    hands = hands,
    currentHandIdx = ctx.currentHandIdx or 1,
    insuranceBet = ctx.insuranceBet or 0,
    insuranceResult = ctx.insuranceResult,
    netChange = ctx.netChange or 0,
    resultLines = cloneSequential(ctx.resultLines),
    autoResolved = ctx.autoResolved == true,
    settlement = {
      applied = ctx.settlement and ctx.settlement.applied == true or false,
      reason = ctx.settlement and ctx.settlement.reason or nil,
      txId = ctx.settlement and ctx.settlement.txId or nil,
    },
  }
end

local function persistRound(env, ctx, phase)
  ctx.phase = phase
  recovery.saveSnapshot(currentWager(ctx), buildSnapshot(ctx, phase))
end

local function restoreContext(env, snapshot)
  if type(snapshot) ~= "table" or snapshot.kind ~= ROUND_SNAPSHOT_KIND then
    return nil
  end

  local hands = {}
  for i, hand in ipairs(snapshot.hands or {}) do
    hands[i] = cloneHand(hand)
  end
  if #hands == 0 then
    return nil
  end

  local settlement = type(snapshot.settlement) == "table" and snapshot.settlement or {}

  return {
    cfg = env.blackjackConfig,
    liveMode = false,
    selfPlay = snapshot.selfPlay == true,
    roundId = snapshot.roundId or makeRoundId(),
    playerName = snapshot.playerName or "Unknown",
    deck = cloneSequential(snapshot.deck),
    dealerHand = cloneSequential(snapshot.dealerHand),
    hands = hands,
    currentHandIdx = math.max(1, math.min(snapshot.currentHandIdx or 1, #hands)),
    insuranceBet = snapshot.insuranceBet or 0,
    insuranceResult = snapshot.insuranceResult,
    playerBalanceBase = 0,
    netChange = snapshot.netChange or 0,
    resultLines = cloneSequential(snapshot.resultLines),
    settlement = {
      applied = settlement.applied == true,
      reason = settlement.reason,
      txId = settlement.txId,
    },
    autoResolved = snapshot.autoResolved == true,
    phase = snapshot.phase or "player_turn",
  }
end

local function getPendingRecovery(env)
  configureRecovery(env)
  local data = recovery.getRecoveryData()
  if not data or type(data.snapshot) ~= "table" then
    return nil, data
  end

  local ctx = restoreContext(env, data.snapshot)
  return ctx, data
end

local function availableBalance(ctx, env)
  local session = env.refreshSession()
  local balance = session.playerBalance
  if type(balance) ~= "number" then
    balance = ctx.playerBalanceBase or 0
  end
  return math.max(0, balance - currentWager(ctx))
end

local function ensureDeck(ctx)
  if #ctx.deck < 20 then
    ctx.deck = cards.buildDeck(ctx.cfg.DECK_COUNT)
    cards.shuffle(ctx.deck)
  end
end

local function dealOne(ctx)
  ensureDeck(ctx)
  return cards.deal(ctx.deck)
end

local function insuranceNetChange(ctx)
  if ctx.insuranceResult == "win" then
    return (ctx.insuranceBet or 0) * 2
  elseif ctx.insuranceResult == "lose" then
    return -(ctx.insuranceBet or 0)
  end
  return 0
end

local function summaryForOtherHands(ctx)
  if #ctx.hands <= 1 then
    return nil
  end

  local parts = {}
  for i, hand in ipairs(ctx.hands) do
    local total = cards.blackjackValue(hand.cards)
    local result = hand.result or "PLAY"
    if hand.busted then
      result = "BUST"
    elseif result == ctx.cfg.OUTCOMES.PLAYER_WIN then
      result = "WIN"
    elseif result == ctx.cfg.OUTCOMES.DEALER_WIN then
      result = "LOSS"
    elseif result == ctx.cfg.OUTCOMES.PUSH then
      result = "PUSH"
    end
    parts[#parts + 1] = "H" .. i .. ":" .. total .. " " .. result
  end

  return table.concat(parts, "  ")
end

local function drawTable(env, ctx, revealDealer, statusLines, actionLines)
  local ui = env.ui
  local theme = ui.theme or {}
  local session = env.refreshSession()
  local hand = ctx.hands[ctx.currentHandIdx or 1]
  local handTotal, handSoft = cards.blackjackValue(hand.cards)
  local dealerTotal, dealerSoft = cards.blackjackValue(ctx.dealerHand)
  local _, h = term.getSize()

  ui.clear(colors.black)
  ui.header("Blackjack", "Bet " .. currency.formatTokens(currentWager(ctx)), session.status)

  ui.writeAt(2, 5, "Dealer", theme.accent or colors.magenta)
  local dealerText
  if revealDealer then
    dealerText = handLabel(ctx.dealerHand)
  else
    dealerText = "?? " .. cardLabel(ctx.dealerHand[2])
  end
  drawWrapped(ui, 2, 6, 22, dealerText, colors.white)
  ui.writeAt(2, 7, "Total: " .. (revealDealer and tostring(dealerTotal) or "?") ..
    ((revealDealer and dealerSoft) and " soft" or ""), theme.subtitle or colors.lightGray)

  if ctx.insuranceBet and ctx.insuranceBet > 0 then
    ui.writeAt(2, 8, "Insurance: " .. currency.formatTokens(ctx.insuranceBet), theme.rule or colors.lightBlue)
  end

  ui.writeAt(2, 10, "Hand " .. tostring(ctx.currentHandIdx or 1) .. "/" .. tostring(#ctx.hands), theme.accent or colors.magenta)
  drawWrapped(ui, 2, 11, 22, handLabel(hand.cards), colors.white)
  ui.writeAt(2, 12, "Total: " .. tostring(handTotal) .. (handSoft and " soft" or ""), theme.subtitle or colors.lightGray)

  local otherSummary = summaryForOtherHands(ctx)
  if otherSummary then
    drawWrapped(ui, 2, 13, 22, otherSummary, theme.subtitle or colors.lightGray)
  end

  local statusY = otherSummary and 15 or 14
  if statusLines then
    for i, line in ipairs(statusLines) do
      ui.writeAt(2, statusY + i - 1, line, colors.white)
    end
  end

  if actionLines then
    local footerStart = h - #actionLines
    for i, line in ipairs(actionLines) do
      ui.writeAt(2, footerStart + i - 1, line, colors.white)
    end
  end

  ui.footer(ctx.selfPlay and "Self-pay round" or "Live round")
end

local function waitForBooleanChoice(env, ctx, title, yesText, noText)
  while true do
    drawTable(env, ctx, false, {
      title,
      "1 " .. yesText,
      "2 " .. noText,
    }, {
      "1 accept  2 skip",
    })

    local _, key = os.pullEvent("key")
    if key == keys.one or key == keys.y or key == keys.enter then
      return true
    elseif key == keys.two or key == keys.n or key == keys.backspace then
      return false
    end
  end
end

local function doInsurance(env, ctx)
  local maxInsurance = math.floor(ctx.hands[1].bet / 2)
  local available = availableBalance(ctx, env)
  local insuranceBet = math.min(maxInsurance, available)

  if insuranceBet < 1 then
    return
  end

  local accept = waitForBooleanChoice(
    env,
    ctx,
    "Insurance available for " .. currency.formatTokens(insuranceBet),
    "Take insurance",
    "Skip insurance"
  )

  if not accept then
    return
  end

  ctx.insuranceBet = insuranceBet
end

local function resolveInsuranceWin(ctx)
  if not ctx.insuranceBet or ctx.insuranceBet <= 0 then
    return
  end
  ctx.insuranceResult = "win"
end

local function resolveInsuranceLoss(ctx)
  if not ctx.insuranceBet or ctx.insuranceBet <= 0 then
    return
  end
  ctx.insuranceResult = "lose"
end

local function drawResult(env, ctx, lines, color)
  drawTable(env, ctx, true, lines, nil)
  env.playSound(color == colors.red and sound.SOUNDS.FAIL or sound.SOUNDS.SUCCESS, 0.5)
  os.sleep(env.settings.animations and 1.2 or 0.2)
end

local function chooseAction(env, ctx, hand)
  while true do
    local actions = {
      { key = keys.one, action = "hit", label = "1 HIT" },
      { key = keys.two, action = "stand", label = "2 STAND" },
    }

    local available = availableBalance(ctx, env)
    local actionLines = {
      "1 Hit   2 Stand",
    }

    if #hand.cards == 2 and available >= hand.bet then
      actions[#actions + 1] = { key = keys.three, action = "double", label = "3 DOUBLE" }
      actionLines[#actionLines + 1] = "3 Double"
    end

    local splitAllowed = #hand.cards == 2
      and ctx.cfg.ALLOW_SPLIT
      and #ctx.hands < (ctx.cfg.MAX_SPLITS + 1)
      and cards.FACE_VALUES[hand.cards[1]:sub(1, 1)] == cards.FACE_VALUES[hand.cards[2]:sub(1, 1)]
      and available >= hand.bet

    if splitAllowed then
      actions[#actions + 1] = { key = keys.four, action = "split", label = "4 SPLIT" }
      actionLines[#actionLines + 1] = "4 Split"
    end

    if ctx.cfg.ALLOW_SURRENDER and hand.hitCount == 0 and not hand.fromSplit and #ctx.hands == 1 then
      actions[#actions + 1] = { key = keys.five, action = "surrender", label = "5 SURRENDER" }
      actionLines[#actionLines + 1] = "5 Surrender"
    end

    drawTable(env, ctx, false, {
      "Choose your move.",
    }, actionLines)

    local _, key = os.pullEvent("key")
    for _, entry in ipairs(actions) do
      if key == entry.key then
        return entry.action
      end
    end
  end
end

local function buildSummary(ctx)
  if ctx.netChange > 0 then
    return "Won " .. currency.formatTokens(ctx.netChange)
  elseif ctx.netChange < 0 then
    return "Lost " .. currency.formatTokens(math.abs(ctx.netChange))
  end
  return "Push"
end

local function buildResultLines(ctx, opts)
  opts = opts or {}

  local lines = {}
  if opts.recovered then
    lines[#lines + 1] = "Recovered saved round."
    if ctx.autoResolved then
      lines[#lines + 1] = "Unfinished hands stood automatically."
    end
    lines[#lines + 1] = ""
  end

  for _, line in ipairs(ctx.resultLines or {}) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = buildSummary(ctx)

  return lines
end

local function settlementReason(ctx)
  if not ctx or not ctx.netChange or ctx.netChange == 0 then
    return nil
  end

  local suffix = ctx.netChange > 0 and "w" or "l"
  return SETTLEMENT_REASON_PREFIX .. tostring(ctx.roundId or makeRoundId()) .. ":" .. suffix
end

local function rememberSettlement(ctx, applied, reason, txId)
  ctx.settlement = ctx.settlement or {}
  ctx.settlement.applied = applied == true
  ctx.settlement.reason = reason
  ctx.settlement.txId = txId
end

local function findSettlementTransaction(reason)
  if type(reason) ~= "string" or reason == "" then
    return nil
  end

  local history = currency.getTransactionHistory(SETTLEMENT_HISTORY_LIMIT) or {}
  for _, tx in pairs(history) do
    if type(tx) == "table" and tx.reason == reason then
      return tx
    end
  end

  return nil
end

local function getRecordedSettlement(ctx)
  if type(ctx) ~= "table" or type(ctx.settlement) ~= "table" then
    return nil
  end

  if type(ctx.settlement.txId) == "string" and ctx.settlement.txId ~= "" then
    local tx = currency.verifyTransaction(ctx.settlement.txId)
    if tx then
      return tx
    end
  end

  return findSettlementTransaction(ctx.settlement.reason)
end

local function resolveInitialOutcome(ctx)
  local playerBJ = cards.isBlackjack(ctx.hands[1].cards)
  local dealerBJ = cards.isBlackjack(ctx.dealerHand)

  if playerBJ and dealerBJ then
    resolveInsuranceWin(ctx)
    ctx.resultLines = {
      "Double blackjack.",
      "Push on the main hand.",
    }
    ctx.netChange = insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.PUSH
    return true
  elseif playerBJ then
    resolveInsuranceLoss(ctx)
    local bonus = math.floor(ctx.hands[1].bet * ctx.cfg.BLACKJACK_PAYOUT)
    ctx.resultLines = {
      "Blackjack!",
      "Natural paid " .. currency.formatTokens(bonus) .. ".",
    }
    ctx.netChange = bonus + insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.BLACKJACK
    return true
  elseif dealerBJ then
    resolveInsuranceWin(ctx)
    ctx.resultLines = {
      "Dealer blackjack.",
      "House takes the main bet.",
    }
    ctx.netChange = -ctx.hands[1].bet + insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.DEALER_WIN
    return true
  end

  resolveInsuranceLoss(ctx)
  return false
end

local function allHandsBusted(ctx)
  for _, hand in ipairs(ctx.hands) do
    if not hand.busted then
      return false
    end
  end
  return true
end

local function resolveSurrender(ctx)
  local refund = math.floor(ctx.hands[1].bet / 2)
  ctx.hands[1].result = ctx.cfg.OUTCOMES.DEALER_WIN
  ctx.netChange = -ctx.hands[1].bet + refund + insuranceNetChange(ctx)
  ctx.resultLines = {
    "Surrendered.",
    "Half the bet was returned.",
  }
end

local function autoStandPendingHands(ctx)
  local changed = false

  for _, hand in ipairs(ctx.hands) do
    if not hand.result then
      local total = cards.blackjackValue(hand.cards)
      if total > 21 then
        hand.busted = true
      end
      hand.result = "stand"
      changed = true
    end
  end

  if changed then
    ctx.autoResolved = true
  end

  return changed
end

local function playDealerTurn(env, ctx, animate)
  if allHandsBusted(ctx) then
    return
  end

  persistRound(env, ctx, "dealer_turn")

  while true do
    local dealerTotal, dealerSoft = cards.blackjackValue(ctx.dealerHand)
    local mustHit = dealerTotal < ctx.cfg.DEALER_STAND
      or (ctx.cfg.DEALER_HIT_SOFT_17 and dealerTotal == 17 and dealerSoft)

    if not mustHit then
      break
    end

    ctx.dealerHand[#ctx.dealerHand + 1] = dealOne(ctx)
    persistRound(env, ctx, "dealer_turn")

    if animate and env.settings.animations then
      drawTable(env, ctx, true, { "Dealer draws..." }, nil)
      os.sleep(0.4)
    end
  end
end

local function scoreResolvedRound(ctx)
  local dealerTotal = cards.blackjackValue(ctx.dealerHand)
  local dealerBusted = dealerTotal > 21
  local net = insuranceNetChange(ctx)
  local summaries = {}

  for index, hand in ipairs(ctx.hands) do
    local handTotal = cards.blackjackValue(hand.cards)
    if hand.busted then
      hand.result = ctx.cfg.OUTCOMES.BUST
      net = net - hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " busted."
    elseif dealerBusted or handTotal > dealerTotal then
      hand.result = ctx.cfg.OUTCOMES.PLAYER_WIN
      net = net + hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " wins."
    elseif handTotal < dealerTotal then
      hand.result = ctx.cfg.OUTCOMES.DEALER_WIN
      net = net - hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " loses."
    else
      hand.result = ctx.cfg.OUTCOMES.PUSH
      summaries[#summaries + 1] = "Hand " .. index .. " pushes."
    end
  end

  ctx.netChange = net
  ctx.resultLines = summaries
end

local function playRound(env, ctx)
  ctx.hands[1].cards = { dealOne(ctx), dealOne(ctx) }
  ctx.dealerHand = { dealOne(ctx), dealOne(ctx) }
  persistRound(env, ctx, "initial_deal")

  local dealerUp = ctx.dealerHand[2]:sub(1, 1)
  if dealerUp == "A" and ctx.cfg.ALLOW_INSURANCE then
    persistRound(env, ctx, "insurance_offer")
    doInsurance(env, ctx)
    persistRound(env, ctx, "initial_deal")
  end

  if resolveInitialOutcome(ctx) then
    return
  end

  persistRound(env, ctx, "player_turn")

  local handIndex = 1
  while handIndex <= #ctx.hands do
    local hand = ctx.hands[handIndex]
    ctx.currentHandIdx = handIndex

    if hand.splitAces and ctx.cfg.RESTRICT_SPLIT_ACES then
      hand.result = "stand"
      persistRound(env, ctx, "player_turn")
    else
      while not hand.result do
        local total = cards.blackjackValue(hand.cards)
        if total >= 21 then
          if total > 21 then
            hand.busted = true
          end
          hand.result = "stand"
          persistRound(env, ctx, "player_turn")
          break
        end

        persistRound(env, ctx, "player_turn")
        local action = chooseAction(env, ctx, hand)
        if action == "hit" then
          hand.cards[#hand.cards + 1] = dealOne(ctx)
          hand.hitCount = (hand.hitCount or 0) + 1
          if cards.blackjackValue(hand.cards) > 21 then
            hand.busted = true
            hand.result = "stand"
          end
        elseif action == "stand" then
          hand.result = "stand"
        elseif action == "double" then
          hand.bet = hand.bet * 2
          hand.doubled = true
          hand.hitCount = (hand.hitCount or 0) + 1
          hand.cards[#hand.cards + 1] = dealOne(ctx)
          if cards.blackjackValue(hand.cards) > 21 then
            hand.busted = true
          end
          hand.result = "stand"
        elseif action == "split" then
          local movedCard = table.remove(hand.cards)
          local splitAces = hand.cards[1]:sub(1, 1) == "A"
          local newHand = {
            cards = { movedCard, dealOne(ctx) },
            bet = hand.bet,
            hitCount = 0,
            fromSplit = true,
            doubled = false,
            splitAces = splitAces,
            busted = false,
          }
          hand.cards[#hand.cards + 1] = dealOne(ctx)
          hand.fromSplit = true
          hand.splitAces = splitAces
          table.insert(ctx.hands, handIndex + 1, newHand)
          if splitAces and ctx.cfg.RESTRICT_SPLIT_ACES then
            hand.result = "stand"
          end
        elseif action == "surrender" then
          hand.surrendered = true
          hand.result = "surrender"
        end

        persistRound(env, ctx, "player_turn")
      end

      if hand.surrendered then
        break
      end
    end

    handIndex = handIndex + 1
  end

  if ctx.hands[1].surrendered then
    resolveSurrender(ctx)
    return
  end

  playDealerTurn(env, ctx, true)
  scoreResolvedRound(ctx)
end

local function recoverSavedRound(env, ctx)
  if ctx.phase == "settled" or ctx.phase == "settlement_pending" then
    return
  end

  if resolveInitialOutcome(ctx) then
    return
  end

  if ctx.phase == "insurance_offer" or ctx.phase == "initial_deal" or ctx.phase == "player_turn" then
    autoStandPendingHands(ctx)
    if ctx.hands[1].surrendered then
      resolveSurrender(ctx)
      return
    end
  end

  playDealerTurn(env, ctx, false)
  scoreResolvedRound(ctx)
end

local function settleNetChange(env, ctx)
  if not ctx.liveMode then
    rememberSettlement(ctx, true, nil, nil)
    persistRound(env, ctx, "settled")
    return
  end

  local recordedTx = getRecordedSettlement(ctx)
  if recordedTx then
    rememberSettlement(ctx, true, recordedTx.reason or ctx.settlement.reason, recordedTx.txId)
    persistRound(env, ctx, "settled")
    return
  end

  if ctx.netChange == 0 then
    rememberSettlement(ctx, true, nil, nil)
    persistRound(env, ctx, "settled")
    return
  end

  local reason = (ctx.settlement and ctx.settlement.reason) or settlementReason(ctx)
  rememberSettlement(ctx, false, reason, nil)
  persistRound(env, ctx, "settlement_pending")

  local ok, txId
  if ctx.netChange > 0 then
    ok, txId = currency.payout(ctx.netChange, reason)
  else
    ok, txId = currency.charge(math.abs(ctx.netChange), reason)
  end

  if not ok then
    recordedTx = findSettlementTransaction(reason)
    if recordedTx then
      rememberSettlement(ctx, true, recordedTx.reason or reason, recordedTx.txId)
      persistRound(env, ctx, "settled")
      return
    end
    error("Failed blackjack settlement")
  end

  rememberSettlement(ctx, true, reason, txId)
  persistRound(env, ctx, "settled")
end

local function finishRound(env, ctx, opts)
  opts = opts or {}

  settleNetChange(env, ctx)

  local resultLines = buildResultLines(ctx, {
    recovered = opts.recovered,
  })

  if opts.showTable then
    drawResult(env, ctx, resultLines, ctx.netChange < 0 and colors.red or colors.lime)
  end

  recovery.clearBet()

  local title = opts.recovered and "Blackjack Recovery" or "Blackjack"
  if opts.showMessage ~= false then
    env.showMessage(title, resultLines, { status = env.refreshSession().status })
  end

  local summary = buildSummary(ctx)
  local modeTag = ctx.selfPlay and "self-pay" or "live"
  env.addMessage(title, summary .. " (" .. modeTag .. ")", ctx.netChange < 0 and "warn" or "info")
end

local function maxBetForSession(env, session)
  local hostBalance = session.hostBalance or currency.getHostBalance()
  local maxBet = math.floor((hostBalance or 0) * env.blackjackConfig.MAX_BET_PERCENT)
  if env.blackjackConfig.HOST_COVERAGE_MULT > 1 then
    maxBet = math.min(maxBet, math.floor((hostBalance or 0) / (env.blackjackConfig.HOST_COVERAGE_MULT - 1)))
  end
  return math.max(0, maxBet)
end

local function createRoundContext(env, session, bet)
  local ctx = {
    cfg = env.blackjackConfig,
    liveMode = env.isLiveSession(session),
    selfPlay = session.selfPlay == true,
    roundId = makeRoundId(),
    playerName = session.playerName or "Unknown",
    deck = cards.buildDeck(env.blackjackConfig.DECK_COUNT),
    dealerHand = {},
    hands = {
      {
        cards = {},
        bet = bet,
        hitCount = 0,
        fromSplit = false,
        doubled = false,
        busted = false,
        splitAces = false,
      },
    },
    currentHandIdx = 1,
    insuranceBet = 0,
    insuranceResult = nil,
    playerBalanceBase = session.playerBalance or 0,
    netChange = 0,
    resultLines = {},
    autoResolved = false,
    settlement = {
      applied = false,
      reason = nil,
      txId = nil,
    },
    phase = "initial_deal",
  }

  cards.shuffle(ctx.deck)
  return ctx
end

local function ensureRecoverySession(env, ctx)
  if not env.ensureAuthenticated("Finish the saved Blackjack round first.") then
    env.showMessage("Saved Blackjack Round", {
      "This phone has an unfinished Blackjack round for " .. tostring(ctx.playerName or "Unknown") .. ".",
      "Approve that wallet session to settle it.",
    }, { status = env.refreshSession().status })
    return nil
  end

  local session = env.refreshSession()
  if not env.isLiveSession(session) then
    env.showMessage("Saved Blackjack Round", {
      "The wallet session is not ready yet.",
      "Approve the phone again, then retry.",
    }, { status = session.status })
    return nil
  end

  if session.playerName ~= ctx.playerName then
    env.showMessage("Saved Blackjack Round", {
      "This saved round belongs to " .. tostring(ctx.playerName or "Unknown") .. ".",
      "The current wallet user is " .. tostring(session.playerName or "Unknown") .. ".",
      "Reopen the phone with the original player approved.",
    }, { status = session.status })
    return nil
  end

  return session
end

function M.recoverPending(env)
  local ctx, data = getPendingRecovery(env)
  if not ctx then
    if data and data.bet and data.bet > 0 then
      recovery.clearBet()
    end
    return true
  end

  local session = ensureRecoverySession(env, ctx)
  if not session then
    return false
  end

  ctx.liveMode = env.isLiveSession(session)
  ctx.selfPlay = session.selfPlay == true
  ctx.playerName = session.playerName or ctx.playerName
  ctx.playerBalanceBase = session.playerBalance or ctx.playerBalanceBase or 0

  configureRecovery(env, ctx.playerName)
  recoverSavedRound(env, ctx)
  finishRound(env, ctx, {
    recovered = true,
    showTable = false,
    showMessage = true,
  })

  return true
end

function M.run(env)
  local function runInternal()
    if not env.ensureAuthenticated("Blackjack needs wallet approval.") then
      return
    end

    local session = env.refreshSession()
    local liveMode = env.isLiveSession(session)
    configureRecovery(env, session.playerName or "Unknown")

    local bet = env.promptBet({
      title = "Blackjack Bet",
      subtitle = session.selfPlay and "Self-pay round" or "Live round",
      maxBet = maxBetForSession(env, session),
      liveMode = liveMode,
    })

    if not bet or bet <= 0 then
      return
    end

    local ctx = createRoundContext(env, session, bet)
    playRound(env, ctx)
    finishRound(env, ctx, {
      recovered = false,
      showTable = true,
      showMessage = true,
    })
  end

  local ok, err = pcall(runInternal)
  if not ok then
    alert.log("Pocket blackjack error: " .. tostring(err))
    if tostring(err) == "Terminated" then
      env.addMessage("Blackjack Paused", "Saved the round state. Reopen the phone to finish it.", "warn")
      return
    end
    env.addMessage("Blackjack Error", tostring(err), "error")
    env.showMessage("Blackjack Error", {
      tostring(err),
      "",
      "Any saved round will be resumed on the next startup.",
    }, { status = env.refreshSession().status })
  end
end

return M
