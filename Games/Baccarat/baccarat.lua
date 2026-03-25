-- baccarat.lua
-- Baccarat card game for ComputerCraft casino.
-- Standard punto banco rules with Player, Banker, and Tie bets.
-- Uses shared libraries from Games/lib/.

-----------------------------------------------------
-- Configuration & Caching
-----------------------------------------------------
local cfg = require("baccarat_config")

local BET  = cfg.BET_TYPES
local OUT  = cfg.OUTCOMES
local LO   = cfg.LAYOUT

local ostime       = os.time
local settings_get = settings.get
local r_getInput   = redstone.getInput
local epoch        = os.epoch

settings.define("baccarat.debug", {
  description = "Enable debug messages for the Baccarat game.",
  type        = "boolean",
  default     = false,
})

local DEBUG = settings_get("baccarat.debug")
local function dbg(msg)
  if DEBUG then print(ostime(), "[BAC] " .. msg) end
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
  hands       = 0,
  playerWins  = 0,
  bankerWins  = 0,
  ties        = 0,
  playerBets  = 0,
  bankerBets  = 0,
  tieBets     = 0,
  totalBet    = 0,
  totalWon    = 0,
  netProfit   = 0,
  biggestWin  = 0,
  streak      = 0,
  streakType  = nil,
  bestStreak  = 0,
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
local function ensureDeck()
  if #deck < cfg.MIN_CARDS_RESHUFFLE then
    dbg("Reshuffling shoe")
    deck = cards.buildDeck(cfg.DECK_COUNT)
    cards.shuffle(deck)
    -- Burn cards
    for _ = 1, cfg.BURN_CARDS do
      cards.deal(deck)
    end
  end
end

local function dealOne()
  ensureDeck()
  return cards.deal(deck)
end

-----------------------------------------------------
-- Baccarat card value (0-9 per card, hand total mod 10)
-----------------------------------------------------
local BACC_VALUES = {
  A = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  T = 0, J = 0, Q = 0, K = 0,
}

local function baccaratCardValue(cardID)
  local val = cardID:sub(1, 1)
  return BACC_VALUES[val] or 0
end

local function baccaratHandTotal(hand)
  local total = 0
  for _, c in ipairs(hand) do
    total = total + baccaratCardValue(c)
  end
  return total % 10
end

-----------------------------------------------------
-- Standard punto banco third-card rules
-----------------------------------------------------
local function playerDrawsThird(playerTotal)
  -- Player draws on 0-5, stands on 6-7
  return playerTotal <= 5
end

local function bankerDrawsThird(bankerTotal, playerThirdValue)
  -- If player stood (no third card), banker draws on 0-5
  if playerThirdValue == nil then
    return bankerTotal <= 5
  end

  -- Standard banker tableau based on player's third card value
  if bankerTotal <= 2 then
    return true
  elseif bankerTotal == 3 then
    return playerThirdValue ~= 8
  elseif bankerTotal == 4 then
    return playerThirdValue >= 2 and playerThirdValue <= 7
  elseif bankerTotal == 5 then
    return playerThirdValue >= 4 and playerThirdValue <= 7
  elseif bankerTotal == 6 then
    return playerThirdValue == 6 or playerThirdValue == 7
  else
    return false -- 7 stands
  end
end

-----------------------------------------------------
-- Layout (computed once from screen dimensions)
-----------------------------------------------------
local cardSpacing = scale:scaledX(LO.CARD_SPACING, 1, 6)
local deltaX   = cardBack.width + cardSpacing
local centerX  = math.floor(width / 2)
local statusY  = scale:ratioY(0.50, LO.STATUS_Y_OFFSET or 0, scale.subtitleY, height - scale.lineHeight - scale.edgePad)

-- Player hand on left side, Banker hand on right side
local playerAreaX = math.floor(width * 0.25)
local bankerAreaX = math.floor(width * 0.75)

-- Vertical positioning: labels at top, cards below, scores below cards
local labelY   = scale:scaledY(LO.PLAYER_LABEL_Y, 1, scale.titleY)
local cardsY   = scale:scaledY(LO.PLAYER_CARDS_Y, scale.subtitleY, scale:ratioY(0.30))
local scoreY   = cardsY + cardBack.height + scale.smallGap

-----------------------------------------------------
-- Rendering
-----------------------------------------------------
local function drawHand(hand, centerHandX, y)
  local totalWidth = #hand * deltaX - cardSpacing
  local startX = centerHandX - math.floor(totalWidth / 2)
  for i, cardID in ipairs(hand) do
    local img = cards.renderCard(cardID)
    screen:drawSurface(img, startX + (i - 1) * deltaX, y)
  end
end

local function renderTableBase(playerHand, bankerHand, betType, betAmount, statusText)
  screen:clear(LO.TABLE_COLOR)

  -- Bet display
  local betLabel = "Bet: " .. currency.formatTokens(betAmount) .. " on " .. string.upper(betType)
  ui.safeDrawText(screen, betLabel, font, 1, 0, colors.white)

  -- "PLAYER" and "BANKER" labels
  local playerLabel = "PLAYER"
  local bankerLabel = "BANKER"
  local plW = ui.getTextSize(playerLabel)
  local blW = ui.getTextSize(bankerLabel)
  ui.safeDrawText(screen, playerLabel, font, playerAreaX - math.floor(plW / 2), labelY, colors.cyan)
  ui.safeDrawText(screen, bankerLabel, font, bankerAreaX - math.floor(blW / 2), labelY, colors.red)

  -- Draw hands
  if #playerHand > 0 then
    drawHand(playerHand, playerAreaX, cardsY)
    local pTotal = baccaratHandTotal(playerHand)
    local pStr = tostring(pTotal)
    local pW = ui.getTextSize(pStr)
    ui.safeDrawText(screen, pStr, font, playerAreaX - math.floor(pW / 2), scoreY, colors.white)
  end

  if #bankerHand > 0 then
    drawHand(bankerHand, bankerAreaX, cardsY)
    local bTotal = baccaratHandTotal(bankerHand)
    local bStr = tostring(bTotal)
    local bW = ui.getTextSize(bStr)
    ui.safeDrawText(screen, bStr, font, bankerAreaX - math.floor(bW / 2), scoreY, colors.white)
  end

  -- Status text (centered)
  if statusText then
    local tw = ui.getTextSize(statusText)
    ui.safeDrawText(screen, statusText, font, math.floor((width - tw) / 2), statusY, colors.yellow)
  end
end

local function renderTable(playerHand, bankerHand, betType, betAmount, statusText)
  renderTableBase(playerHand, bankerHand, betType, betAmount, statusText)
  screen:output()
end

-----------------------------------------------------
-- Session stats update
-----------------------------------------------------
local function updateSessionStats(outcome, betType, betAmount, netChange)
  sessionStats.hands = sessionStats.hands + 1
  sessionStats.totalBet = sessionStats.totalBet + betAmount
  sessionStats.netProfit = sessionStats.netProfit + netChange

  if netChange > sessionStats.biggestWin then
    sessionStats.biggestWin = netChange
  end
  if netChange > 0 then
    sessionStats.totalWon = sessionStats.totalWon + netChange
  end

  -- Track bet type counts
  if betType == BET.PLAYER then
    sessionStats.playerBets = sessionStats.playerBets + 1
  elseif betType == BET.BANKER then
    sessionStats.bankerBets = sessionStats.bankerBets + 1
  elseif betType == BET.TIE then
    sessionStats.tieBets = sessionStats.tieBets + 1
  end

  -- Track outcome counts
  if outcome == OUT.PLAYER_WIN then
    sessionStats.playerWins = sessionStats.playerWins + 1
  elseif outcome == OUT.BANKER_WIN then
    sessionStats.bankerWins = sessionStats.bankerWins + 1
  else
    sessionStats.ties = sessionStats.ties + 1
  end

  -- Streak tracking
  if sessionStats.streakType == outcome then
    sessionStats.streak = sessionStats.streak + 1
  else
    sessionStats.streak = 1
    sessionStats.streakType = outcome
  end
  if sessionStats.streak > sessionStats.bestStreak then
    sessionStats.bestStreak = sessionStats.streak
  end
end

-----------------------------------------------------
-- Tutorial / How to play screens
-----------------------------------------------------
local LINE_H = scale.lineHeight

local function drawCenteredLine(text, y, color)
  local tw = ui.getTextSize(text)
  ui.safeDrawText(screen, text, font, math.floor((width - tw) / 2), y, color or colors.white)
end

local TUTORIAL_PAGES = {
  {
    title = "THE BASICS",
    lines = {
      { text = "Pick PLAYER, BANKER", color = colors.white },
      { text = "or TIE before the",   color = colors.white },
      { text = "cards are dealt.",    color = colors.white },
      { text = "",                     color = colors.white },
      { text = "Closest to 9 wins!",  color = colors.yellow },
      { text = "You just bet on",     color = colors.yellow },
      { text = "the outcome.",        color = colors.yellow },
    },
  },
  {
    title = "CARD VALUES",
    lines = {
      { text = "Ace = 1 point",      color = colors.cyan },
      { text = "2-9 = face value",   color = colors.white },
      { text = "10,J,Q,K = 0",       color = colors.lightGray },
      { text = "",                    color = colors.white },
      { text = "Only ones digit",    color = colors.yellow },
      { text = "counts: 7+8=15->5",  color = colors.yellow },
    },
  },
  {
    title = "NATURALS",
    lines = {
      { text = "8 or 9 on the",      color = colors.lime },
      { text = "first 2 cards is",   color = colors.lime },
      { text = "a Natural - best",   color = colors.lime },
      { text = "possible hand!",     color = colors.lime },
      { text = "",                    color = colors.white },
      { text = "No extra cards",     color = colors.white },
      { text = "are drawn.",         color = colors.white },
    },
  },
  {
    title = "PAYOUTS",
    lines = {
      { text = "PLAYER: 1:1",        color = colors.cyan },
      { text = "BANKER: 1:1",        color = colors.red },
      { text = " minus 5% fee",      color = colors.red },
      { text = "TIE: 8:1",           color = colors.yellow },
      { text = " (risky-rare!)",     color = colors.yellow },
      { text = "",                    color = colors.white },
      { text = "Tip: BANKER has",    color = colors.lime },
      { text = "the best odds!",     color = colors.lime },
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
  local statsSpacing = math.min(LINE_H, math.floor((height - y - 10) / 10))
  local function statLine(label, value, color)
    drawCenteredLine(label .. ": " .. tostring(value), y, color or colors.white)
    y = y + statsSpacing
  end

  statLine("Hands", sessionStats.hands, colors.white)

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
  drawCenteredLine("-- OUTCOMES --", y, colors.yellow)
  y = y + statsSpacing
  statLine("Player", sessionStats.playerWins, colors.cyan)
  statLine("Banker", sessionStats.bankerWins, colors.red)
  statLine("Ties", sessionStats.ties, colors.yellow)

  if sessionStats.bestStreak > 1 then
    statLine("Best Streak", sessionStats.bestStreak, colors.lime)
  end

  ui.clearButtons()
  ui.layoutButtonGrid(screen, {
    {{ text = "BACK", color = colors.red, func = function() end }},
  }, centerX, scale.footerButtonY, scale.buttonRowSpacing, scale.buttonColGap)
  screen:output()
  ui.waitForButton(0, 0)
end

-----------------------------------------------------
-- Bet type selection (Player / Banker / Tie)
-----------------------------------------------------
local function selectBetType()
  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "CHOOSE YOUR BET"
    local tw = ui.getTextSize(title)
    ui.safeDrawText(screen, title, font, math.floor((width - tw) / 2), scale.titleY, colors.yellow)

    -- Brief hint for new players
    local hint = "Closest to 9 wins!"
    local hw = ui.getTextSize(hint)
    ui.safeDrawText(screen, hint, font, math.floor((width - hw) / 2), scale.subtitleY, colors.lightGray)

    ui.clearButtons()
    local chosen = nil
    local action = nil

    ui.layoutButtonGrid(screen, {
      {
        { text = "PLAYER 1:1", color = colors.cyan,
          func = function() chosen = BET.PLAYER end },
        { text = "BANKER 1:1", color = colors.red,
          func = function() chosen = BET.BANKER end },
      },
      {
        { text = "TIE 8:1", color = colors.yellow,
          func = function() chosen = BET.TIE end },
      },
      {
        { text = "HOW TO PLAY", color = colors.lightBlue,
          func = function() action = "tutorial" end },
        { text = "STATS", color = colors.lightGray,
          func = function() action = "stats" end },
      },
    }, centerX, scale.menuY, scale.buttonRowSpacing, scale.buttonColGap)

    screen:output()

    if AUTO_PLAY then
      -- Bot: random bet type weighted toward banker (best odds)
      local r = math.random(100)
      if r <= 50 then
        chosen = BET.BANKER
      elseif r <= 90 then
        chosen = BET.PLAYER
      else
        chosen = BET.TIE
      end
      os.sleep(cfg.AUTO_PLAY_DELAY)
      return chosen
    end

    ui.waitForButton(0, 0)

    if chosen then return chosen end
    if action == "tutorial" then showTutorial() end
    if action == "stats" then showStats() end
    -- If tutorial/stats was shown, loop redraws the bet selection
  end
end

-----------------------------------------------------
-- Baccarat round
-----------------------------------------------------
local function baccaratRound(betAmount, betType)
  recovery.saveBet(betAmount)

  local playerHand = {}
  local bankerHand = {}
  local roundStart = epoch("local")

  -- Pre-deal all 4 cards
  local p1 = dealOne()
  local b1 = dealOne()
  local p2 = dealOne()
  local b2 = dealOne()

  if not AUTO_PLAY then
    -- Animated deal: slide each card in one at a time
    -- Precompute final card positions (2 cards each, centered on their area)
    local pTotalW = 2 * deltaX - cardSpacing
    local pStartX = playerAreaX - math.floor(pTotalW / 2)
    local bStartX = bankerAreaX - math.floor(pTotalW / 2)

    -- Track visible cards for the background
    local visPlayer = {}
    local visBanker = {}

    local betLabel = "Bet: " .. currency.formatTokens(betAmount) .. " on " .. string.upper(betType)
    local plW = ui.getTextSize("PLAYER")
    local blW = ui.getTextSize("BANKER")

    local function bgRender()
      screen:clear(LO.TABLE_COLOR)
      ui.safeDrawText(screen, betLabel, font, 1, 0, colors.white)
      ui.safeDrawText(screen, "PLAYER", font, playerAreaX - math.floor(plW / 2), labelY, colors.cyan)
      ui.safeDrawText(screen, "BANKER", font, bankerAreaX - math.floor(blW / 2), labelY, colors.red)
      for i, cid in ipairs(visPlayer) do
        screen:drawSurface(cards.renderCard(cid), pStartX + (i - 1) * deltaX, cardsY)
      end
      for i, cid in ipairs(visBanker) do
        screen:drawSurface(cards.renderCard(cid), bStartX + (i - 1) * deltaX, cardsY)
      end
    end

    -- Deal order: player1, banker1, player2, banker2
    cardAnim.slideIn(cards.renderCard(p1), pStartX, cardsY, bgRender)
    table.insert(visPlayer, p1)

    cardAnim.slideIn(cards.renderCard(b1), bStartX, cardsY, bgRender)
    table.insert(visBanker, b1)

    cardAnim.slideIn(cards.renderCard(p2), pStartX + deltaX, cardsY, bgRender)
    table.insert(visPlayer, p2)

    cardAnim.slideIn(cards.renderCard(b2), bStartX + deltaX, cardsY, bgRender)
    table.insert(visBanker, b2)
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  -- Set final hands
  playerHand = { p1, p2 }
  bankerHand = { b1, b2 }

  renderTable(playerHand, bankerHand, betType, betAmount, nil)
  os.sleep(0.4)

  local playerTotal = baccaratHandTotal(playerHand)
  local bankerTotal = baccaratHandTotal(bankerHand)

  -- Check for naturals (8 or 9)
  local isNatural = (playerTotal >= 8 or bankerTotal >= 8)

  local playerThirdValue = nil

  if not isNatural then
    -- Player third card rule
    if playerDrawsThird(playerTotal) then
      local third = dealOne()
      table.insert(playerHand, third)
      playerThirdValue = baccaratCardValue(third)

      if not AUTO_PLAY then
        -- Animate the third card
        local nCards = #playerHand
        local totalW = nCards * deltaX - cardSpacing
        local startX = playerAreaX - math.floor(totalW / 2)
        local toX = startX + (nCards - 1) * deltaX
        local savedCard = table.remove(playerHand)
        cardAnim.slideIn(cards.renderCard(savedCard), toX, cardsY, function()
          renderTableBase(playerHand, bankerHand, betType, betAmount, nil)
        end)
        table.insert(playerHand, savedCard)
      else
        sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
      end

      renderTable(playerHand, bankerHand, betType, betAmount, nil)
      os.sleep(0.4)
      playerTotal = baccaratHandTotal(playerHand)
    end

    -- Banker third card rule
    if bankerDrawsThird(bankerTotal, playerThirdValue) then
      table.insert(bankerHand, dealOne())

      if not AUTO_PLAY then
        local nCards = #bankerHand
        local totalW = nCards * deltaX - cardSpacing
        local startX = bankerAreaX - math.floor(totalW / 2)
        local toX = startX + (nCards - 1) * deltaX
        local savedCard = table.remove(bankerHand)
        cardAnim.slideIn(cards.renderCard(savedCard), toX, cardsY, function()
          renderTableBase(playerHand, bankerHand, betType, betAmount, nil)
        end)
        table.insert(bankerHand, savedCard)
      else
        sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
      end

      renderTable(playerHand, bankerHand, betType, betAmount, nil)
      os.sleep(0.4)
      bankerTotal = baccaratHandTotal(bankerHand)
    end
  end

  -- Determine outcome
  local outcome = nil
  if playerTotal > bankerTotal then
    outcome = OUT.PLAYER_WIN
  elseif bankerTotal > playerTotal then
    outcome = OUT.BANKER_WIN
  else
    outcome = OUT.TIE
  end

  -- Calculate payout
  local netChange = 0
  local payout = 0
  local msg = nil
  local msgClr = nil
  local snd = nil

  if outcome == OUT.TIE then
    if betType == BET.TIE then
      -- Tie bet wins: pay tie payout + return original bet
      payout = betAmount + (betAmount * cfg.TIE_PAYOUT)
      netChange = betAmount * cfg.TIE_PAYOUT
      msg = "Tie! " .. playerTotal .. " - " .. bankerTotal .. "  +" .. currency.formatTokens(netChange)
      msgClr = colors.yellow
      snd = sound.SOUNDS.SUCCESS
    else
      -- Player/banker bets push on tie (bet returned)
      payout = betAmount
      netChange = 0
      msg = "Tie! " .. playerTotal .. " - " .. bankerTotal .. "  Push"
      msgClr = colors.white
      snd = sound.SOUNDS.PUSH
    end
  elseif outcome == OUT.PLAYER_WIN then
    if betType == BET.PLAYER then
      payout = betAmount * 2  -- 1:1 + original
      netChange = betAmount
      msg = "Player Wins! " .. playerTotal .. " - " .. bankerTotal .. "  +" .. currency.formatTokens(netChange)
      msgClr = colors.yellow
      snd = sound.SOUNDS.SUCCESS
    else
      -- Lost
      netChange = -betAmount
      msg = "Player Wins! " .. playerTotal .. " - " .. bankerTotal
      msgClr = colors.red
      snd = sound.SOUNDS.FAIL
    end
  else -- BANKER_WIN
    if betType == BET.BANKER then
      -- Banker wins pay 1:1 minus 5% commission (minimum 1 token)
      local commission = math.max(1, math.floor(betAmount * cfg.BANKER_COMMISSION))
      payout = betAmount * 2 - commission
      netChange = betAmount - commission
      msg = "Banker Wins! " .. bankerTotal .. " - " .. playerTotal .. "  +" .. currency.formatTokens(netChange)
      msgClr = colors.yellow
      snd = sound.SOUNDS.SUCCESS
    else
      netChange = -betAmount
      msg = "Banker Wins! " .. bankerTotal .. " - " .. playerTotal
      msgClr = colors.red
      snd = sound.SOUNDS.FAIL
    end
  end

  -- Transfer-at-end settlement
  if netChange > 0 then
    local payOk = currency.payout(netChange, "Baccarat: payout")
    if not payOk then
      alert.send("CRITICAL: Failed to pay " .. netChange .. " tokens to player!")
      alert.log("Payout failure: " .. netChange .. " tokens, outcome=" .. outcome)
      msg = "ERROR: Payout failed! Contact admin."
      msgClr = colors.red
      snd = sound.SOUNDS.ERROR
    end
  elseif netChange < 0 then
    local chargeAmt = -netChange
    local chargeOk = currency.charge(chargeAmt, "Baccarat: loss")
    if not chargeOk then
      alert.send("CRITICAL: Failed to charge " .. chargeAmt .. " tokens from player!")
      alert.log("Charge failure: " .. chargeAmt .. " tokens, outcome=" .. outcome)
      msg = "ERROR: Charge failed! Contact admin."
      msgClr = colors.red
      snd = sound.SOUNDS.ERROR
    end
  end

  -- Update session statistics
  updateSessionStats(outcome, betType, betAmount, netChange)

  -- Show result with beginner-friendly explanation
  local naturalTag = isNatural and " (Natural)" or ""
  local explanation = ""
  if isNatural then
    explanation = " Natural = 8 or 9 on first deal"
  elseif playerThirdValue ~= nil and #bankerHand == 3 then
    explanation = " Both sides drew a third card"
  elseif playerThirdValue ~= nil then
    explanation = " Player drew a third card"
  elseif #bankerHand == 3 then
    explanation = " Banker drew a third card"
  end
  renderTable(playerHand, bankerHand, betType, betAmount, nil)
  ui.displayCenteredMessage(screen, msg .. naturalTag, msgClr, LO.RESULT_PAUSE)
  if explanation ~= "" then
    -- Brief explanation overlay
    drawCenteredLine(explanation, height - 12, colors.lightGray)
    screen:output()
    os.sleep(1.0)
  end
  sound.play(snd)

  recovery.clearBet()
  dbg("Round: " .. outcome .. " P:" .. playerTotal .. " B:" .. bankerTotal
      .. " bet=" .. betType .. " net=" .. netChange)
end

-----------------------------------------------------
-- Bet selection (amount)
-----------------------------------------------------
local function betSelection()
  return betting.runBetScreen(screen, {
    maxBet                 = getMaxBet(),
    gameName               = "Baccarat",
    confirmLabel           = "CONFIRM",
    title                  = "PLACE YOUR WAGER",
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
refreshPlayer()

local function main()
  while true do
    updateAutoPlayFromRedstone()
    refreshPlayer()
    drawPlayerOverlay()

    local betAmount = nil
    local betType = nil

    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      local autoBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if autoBet > 0 then
        betAmount = autoBet
        betType = selectBetType()
        os.sleep(cfg.AUTO_PLAY_DELAY)
      else
        os.sleep(1)
      end
    else
      -- Step 1: Choose bet type (Player / Banker / Tie)
      betType = selectBetType()
      if not betType then
        os.sleep(0.1)
      else
        -- Step 2: Choose bet amount
        local selectedBet = betSelection()
        if selectedBet and selectedBet > 0 then
          betAmount = selectedBet
        end
      end
    end

    if betAmount and betAmount > 0 and betType then
      baccaratRound(betAmount, betType)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
