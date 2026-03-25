local cards    = require("lib.cards")
local currency = require("lib.currency")
local sound    = require("lib.sound")
local alert    = require("lib.alert")
local recovery = require("lib.crash_recovery")

local M = {}

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
  local session = env.refreshSession()
  local hand = ctx.hands[ctx.currentHandIdx or 1]
  local handTotal, handSoft = cards.blackjackValue(hand.cards)
  local dealerTotal, dealerSoft = cards.blackjackValue(ctx.dealerHand)
  local _, h = term.getSize()

  ui.clear(colors.black)
  ui.header("Blackjack", "Bet " .. currency.formatTokens(currentWager(ctx)), session.status)

  ui.writeAt(2, 5, "Dealer", colors.yellow)
  local dealerText
  if revealDealer then
    dealerText = handLabel(ctx.dealerHand)
  else
    dealerText = "?? " .. cardLabel(ctx.dealerHand[2])
  end
  drawWrapped(ui, 2, 6, 22, dealerText, colors.white)
  ui.writeAt(2, 7, "Total: " .. (revealDealer and tostring(dealerTotal) or "?") ..
    ((revealDealer and dealerSoft) and " soft" or ""), colors.lightGray)

  if ctx.insuranceBet and ctx.insuranceBet > 0 then
    ui.writeAt(2, 8, "Insurance: " .. currency.formatTokens(ctx.insuranceBet), colors.cyan)
  end

  ui.writeAt(2, 10, "Hand " .. tostring(ctx.currentHandIdx or 1) .. "/" .. tostring(#ctx.hands), colors.yellow)
  drawWrapped(ui, 2, 11, 22, handLabel(hand.cards), colors.white)
  ui.writeAt(2, 12, "Total: " .. tostring(handTotal) .. (handSoft and " soft" or ""), colors.lightGray)

  local otherSummary = summaryForOtherHands(ctx)
  if otherSummary then
    drawWrapped(ui, 2, 13, 22, otherSummary, colors.lightGray)
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

local function placeEscrow(ctx, amount, reason, tag)
  if not amount or amount <= 0 then
    return nil
  end
  return "reserved-" .. tostring(tag or "bet") .. "-" .. tostring(os.epoch("local"))
end

local function safeResolveToHost(ctx, escrowId, reason)
  return
end

local function safeResolveToPlayer(ctx, escrowId, reason)
  return
end

local function safeCancelEscrow(ctx, escrowId, reason)
  return
end

local function safePayout(ctx, amount, reason)
  return
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

  local escrowId = placeEscrow(ctx, insuranceBet, "phone blackjack insurance", "insurance")
  if not escrowId then
    env.showMessage("Insurance Failed", {
      "The insurance escrow could not be created.",
    }, { status = env.refreshSession().status })
    return
  end

  ctx.insuranceBet = insuranceBet
  ctx.insuranceEscrowId = escrowId
end

local function resolveInsuranceWin(ctx)
  if not ctx.insuranceBet or ctx.insuranceBet <= 0 then
    return
  end
  safeResolveToPlayer(ctx, ctx.insuranceEscrowId, "phone blackjack insurance win")
  safePayout(ctx, ctx.insuranceBet * 2, "phone blackjack insurance payout")
  ctx.insuranceResult = "win"
end

local function resolveInsuranceLoss(ctx)
  if not ctx.insuranceBet or ctx.insuranceBet <= 0 then
    return
  end
  safeResolveToHost(ctx, ctx.insuranceEscrowId, "phone blackjack insurance loss")
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

local function settlePlayerWin(ctx, hand, reason)
  for _, escrowId in ipairs(hand.escrowIds or {}) do
    safeResolveToPlayer(ctx, escrowId, reason)
  end
  safePayout(ctx, hand.bet, reason)
end

local function settleHouseWin(ctx, hand, reason)
  for _, escrowId in ipairs(hand.escrowIds or {}) do
    safeResolveToHost(ctx, escrowId, reason)
  end
end

local function settlePush(ctx, hand, reason)
  for _, escrowId in ipairs(hand.escrowIds or {}) do
    safeCancelEscrow(ctx, escrowId, reason)
  end
end

local function playRound(env, ctx)
  ctx.hands[1].cards = { dealOne(ctx), dealOne(ctx) }
  ctx.dealerHand = { dealOne(ctx), dealOne(ctx) }

  local dealerUp = ctx.dealerHand[2]:sub(1, 1)
  if dealerUp == "A" and ctx.cfg.ALLOW_INSURANCE then
    doInsurance(env, ctx)
  end

  local playerBJ = cards.isBlackjack(ctx.hands[1].cards)
  local dealerBJ = cards.isBlackjack(ctx.dealerHand)

  if playerBJ and dealerBJ then
    settlePush(ctx, ctx.hands[1], "phone blackjack push")
    resolveInsuranceWin(ctx)
    ctx.resultLines = {
      "Double blackjack.",
      "Push on the main hand.",
    }
    ctx.netChange = insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.PUSH
    return
  elseif playerBJ then
    settlePush(ctx, ctx.hands[1], "phone blackjack natural")
    resolveInsuranceLoss(ctx)
    local bonus = math.floor(ctx.hands[1].bet * ctx.cfg.BLACKJACK_PAYOUT)
    safePayout(ctx, bonus, "phone blackjack natural")
    ctx.resultLines = {
      "Blackjack!",
      "Natural paid " .. currency.formatTokens(bonus) .. ".",
    }
    ctx.netChange = bonus + insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.BLACKJACK
    return
  elseif dealerBJ then
    settleHouseWin(ctx, ctx.hands[1], "phone blackjack dealer blackjack")
    resolveInsuranceWin(ctx)
    ctx.resultLines = {
      "Dealer blackjack.",
      "House takes the main bet.",
    }
    ctx.netChange = -ctx.hands[1].bet + insuranceNetChange(ctx)
    ctx.hands[1].result = ctx.cfg.OUTCOMES.DEALER_WIN
    return
  else
    resolveInsuranceLoss(ctx)
  end

  local handIndex = 1
  while handIndex <= #ctx.hands do
    local hand = ctx.hands[handIndex]
    ctx.currentHandIdx = handIndex

    if hand.splitAces and ctx.cfg.RESTRICT_SPLIT_ACES then
      hand.result = "stand"
    else
      while not hand.result do
        local total = cards.blackjackValue(hand.cards)
        if total >= 21 then
          if total > 21 then
            hand.busted = true
          end
          hand.result = "stand"
          break
        end

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
          local extraEscrow = placeEscrow(ctx, hand.bet, "phone blackjack double", "double")
          if extraEscrow then
            hand.bet = hand.bet * 2
            hand.doubled = true
            hand.escrowIds[#hand.escrowIds + 1] = extraEscrow
            hand.cards[#hand.cards + 1] = dealOne(ctx)
            if cards.blackjackValue(hand.cards) > 21 then
              hand.busted = true
            end
            hand.result = "stand"
          end
        elseif action == "split" then
          local splitEscrow = placeEscrow(ctx, hand.bet, "phone blackjack split", "split")
          if splitEscrow then
            local movedCard = table.remove(hand.cards)
            local splitAces = hand.cards[1]:sub(1, 1) == "A"
            local newHand = {
              cards = { movedCard, dealOne(ctx) },
              bet = hand.bet,
              escrowIds = { splitEscrow },
              hitCount = 0,
              fromSplit = true,
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
          end
        elseif action == "surrender" then
          hand.surrendered = true
          hand.result = "surrender"
        end
      end

      if hand.surrendered then
        break
      end
    end

    handIndex = handIndex + 1
  end

  if ctx.hands[1].surrendered then
    settleHouseWin(ctx, ctx.hands[1], "phone blackjack surrender")
    local refund = math.floor(ctx.hands[1].bet / 2)
    safePayout(ctx, refund, "phone blackjack surrender refund")
    ctx.hands[1].result = ctx.cfg.OUTCOMES.DEALER_WIN
    ctx.netChange = -ctx.hands[1].bet + refund + insuranceNetChange(ctx)
    ctx.resultLines = {
      "Surrendered.",
      "Half the bet was returned.",
    }
    return
  end

  local allBusted = true
  for _, hand in ipairs(ctx.hands) do
    if not hand.busted then
      allBusted = false
      break
    end
  end

  if not allBusted then
    while true do
      local dealerTotal, dealerSoft = cards.blackjackValue(ctx.dealerHand)
      local mustHit = dealerTotal < ctx.cfg.DEALER_STAND
        or (ctx.cfg.DEALER_HIT_SOFT_17 and dealerTotal == 17 and dealerSoft)
      if not mustHit then
        break
      end
      ctx.dealerHand[#ctx.dealerHand + 1] = dealOne(ctx)
      if env.settings.animations then
        drawTable(env, ctx, true, { "Dealer draws..." }, nil)
        os.sleep(0.4)
      end
    end
  end

  local dealerTotal = cards.blackjackValue(ctx.dealerHand)
  local dealerBusted = dealerTotal > 21
  local net = insuranceNetChange(ctx)
  local summaries = {}

  for index, hand in ipairs(ctx.hands) do
    local handTotal = cards.blackjackValue(hand.cards)
    if hand.busted then
      hand.result = ctx.cfg.OUTCOMES.BUST
      settleHouseWin(ctx, hand, "phone blackjack bust")
      net = net - hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " busted."
    elseif dealerBusted or handTotal > dealerTotal then
      hand.result = ctx.cfg.OUTCOMES.PLAYER_WIN
      settlePlayerWin(ctx, hand, "phone blackjack win")
      net = net + hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " wins."
    elseif handTotal < dealerTotal then
      hand.result = ctx.cfg.OUTCOMES.DEALER_WIN
      settleHouseWin(ctx, hand, "phone blackjack loss")
      net = net - hand.bet
      summaries[#summaries + 1] = "Hand " .. index .. " loses."
    else
      hand.result = ctx.cfg.OUTCOMES.PUSH
      settlePush(ctx, hand, "phone blackjack push")
      summaries[#summaries + 1] = "Hand " .. index .. " pushes."
    end
  end

  ctx.netChange = net
  ctx.resultLines = summaries
end

local function buildSummary(ctx)
  if ctx.netChange > 0 then
    return "Won " .. currency.formatTokens(ctx.netChange)
  elseif ctx.netChange < 0 then
    return "Lost " .. currency.formatTokens(math.abs(ctx.netChange))
  end
  return "Push"
end

local function settleNetChange(ctx)
  if not ctx.liveMode or not ctx.netChange or ctx.netChange == 0 then
    return
  end

  local reason
  if ctx.netChange > 0 then
    reason = ctx.selfPlay and "phone blackjack self-pay win" or "phone blackjack payout"
    local ok = currency.payout(ctx.netChange, reason)
    if not ok then
      error("Failed blackjack settlement payout")
    end
  else
    reason = ctx.selfPlay and "phone blackjack self-pay loss" or "phone blackjack loss"
    local ok = currency.charge(math.abs(ctx.netChange), reason)
    if not ok then
      error("Failed blackjack settlement charge")
    end
  end
end

function M.run(env)
  local function runInternal()
    recovery.configure(fs.combine(env.dataDir, "phone_blackjack_recovery.dat"))
    recovery.recoverBet(false)

    if not env.ensureAuthenticated("Blackjack needs wallet approval.") then
      return
    end

    local session = env.refreshSession()
    local liveMode = env.isLiveSession(session)
    recovery.setGame("Pocket Blackjack")
    recovery.setPlayer(session.playerName or "Unknown")

    local hostBalance = session.hostBalance or currency.getHostBalance()
    local maxBet = math.floor((hostBalance or 0) * env.blackjackConfig.MAX_BET_PERCENT)
    if env.blackjackConfig.HOST_COVERAGE_MULT > 1 then
      maxBet = math.min(maxBet, math.floor((hostBalance or 0) / (env.blackjackConfig.HOST_COVERAGE_MULT - 1)))
    end
    maxBet = math.max(0, maxBet)

    local bet = env.promptBet({
      title = "Blackjack Bet",
      subtitle = session.selfPlay and "Self-pay round" or "Live round",
      maxBet = maxBet,
      liveMode = liveMode,
    })

    if not bet or bet <= 0 then
      return
    end
    recovery.saveBet(bet, "deal")

    local ctx = {
      cfg = env.blackjackConfig,
      liveMode = liveMode,
      selfPlay = session.selfPlay,
      deck = cards.buildDeck(env.blackjackConfig.DECK_COUNT),
      dealerHand = {},
      hands = {
        {
          cards = {},
          bet = bet,
          escrowIds = {},
          hitCount = 0,
          fromSplit = false,
          doubled = false,
          busted = false,
          splitAces = false,
        },
      },
      currentHandIdx = 1,
      insuranceBet = 0,
      insuranceEscrowId = nil,
      insuranceResult = nil,
      playerBalanceBase = session.playerBalance or 0,
      netChange = 0,
    }
    cards.shuffle(ctx.deck)

    playRound(env, ctx)
    settleNetChange(ctx)
    recovery.clearBet()

    local summary = buildSummary(ctx)
    local resultLines = {}
    for _, line in ipairs(ctx.resultLines or {}) do
      resultLines[#resultLines + 1] = line
    end
    resultLines[#resultLines + 1] = summary

    drawResult(env, ctx, resultLines, ctx.netChange < 0 and colors.red or colors.lime)
    env.showMessage("Blackjack", resultLines, { status = env.refreshSession().status })

    local modeTag = session.selfPlay and "self-pay" or "live"
    env.addMessage("Blackjack", summary .. " (" .. modeTag .. ")", ctx.netChange < 0 and "warn" or "info")
  end

  local ok, err = pcall(runInternal)
  if not ok then
    alert.log("Pocket blackjack error: " .. tostring(err))
    recovery.recoverBet(false)
    env.addMessage("Blackjack Error", tostring(err), "error")
    env.showMessage("Blackjack Error", {
      tostring(err),
    }, { status = env.refreshSession().status })
  end
end

return M
