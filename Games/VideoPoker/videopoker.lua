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
  totalBet    = 0,
  totalWon    = 0,
  netProfit   = 0,
  biggestWin  = 0,
  handCounts  = {},  -- keyed by hand name
}

-- Initialize hand counts
for _, p in ipairs(PAYOUTS) do
  sessionStats.handCounts[p.name] = 0
end
sessionStats.handCounts["No Win"] = 0

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
local RANK_MAP = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  ["T"] = 10, ["J"] = 11, ["Q"] = 12, ["K"] = 13, ["A"] = 14,
}

local function getRank(cardID)
  return RANK_MAP[cardID:sub(1, 1)] or 0
end

local function getSuit(cardID)
  return cardID:sub(2)
end

--- Evaluate a 5-card hand. Returns the hand name and payout index (1-based into PAYOUTS, nil if no win).
-- @param hand table  Array of 5 card ID strings
-- @return string handName, number|nil payoutIndex
local function evaluateHand(hand)
  assert(#hand == 5, "Hand must have exactly 5 cards")

  -- Count ranks and suits
  local rankCounts = {}  -- rank -> count
  local suitCounts = {}  -- suit -> count
  local ranks = {}       -- sorted list of numeric ranks

  for _, cardID in ipairs(hand) do
    local r = getRank(cardID)
    local s = getSuit(cardID)
    rankCounts[r] = (rankCounts[r] or 0) + 1
    suitCounts[s] = (suitCounts[s] or 0) + 1
    table.insert(ranks, r)
  end

  table.sort(ranks)

  -- Check for flush (all same suit)
  local isFlush = false
  for _, count in pairs(suitCounts) do
    if count == 5 then isFlush = true end
  end

  -- Check for straight (5 consecutive ranks)
  local isStraight = false
  local uniqueRanks = {}
  local seen = {}
  for _, r in ipairs(ranks) do
    if not seen[r] then
      table.insert(uniqueRanks, r)
      seen[r] = true
    end
  end

  if #uniqueRanks == 5 then
    local span = ranks[5] - ranks[1]
    if span == 4 then
      isStraight = true
    end
    -- Special case: A-2-3-4-5 (wheel)
    if ranks[1] == 2 and ranks[2] == 3 and ranks[3] == 4 and ranks[4] == 5 and ranks[5] == 14 then
      isStraight = true
    end
  end

  -- Check for royal (T-J-Q-K-A)
  local isRoyal = (ranks[1] == 10 and ranks[2] == 11 and ranks[3] == 12
                   and ranks[4] == 13 and ranks[5] == 14)

  -- Count pairs, trips, quads
  local pairCount = 0
  local trips = 0
  local quads = 0
  local pairRanks = {}

  for rank, count in pairs(rankCounts) do
    if count == 2 then
      pairCount = pairCount + 1
      table.insert(pairRanks, rank)
    elseif count == 3 then
      trips = 1
    elseif count == 4 then
      quads = 1
    end
  end

  -- Evaluate from best to worst
  if isRoyal and isFlush then
    return "Royal Flush", 1
  end

  if isStraight and isFlush then
    return "Straight Flush", 2
  end

  if quads == 1 then
    return "Four of a Kind", 3
  end

  if trips == 1 and pairCount == 1 then
    return "Full House", 4
  end

  if isFlush then
    return "Flush", 5
  end

  if isStraight then
    return "Straight", 6
  end

  if trips == 1 then
    return "Three of a Kind", 7
  end

  if pairCount == 2 then
    return "Two Pair", 8
  end

  if pairCount == 1 then
    -- Jacks or Better: pair must be J, Q, K, or A
    local pairRank = pairRanks[1]
    if pairRank >= 11 then  -- J=11, Q=12, K=13, A=14
      return "Jacks or Better", 9
    end
  end

  return "No Win", nil
end

-----------------------------------------------------
-- Layout (computed once from screen dimensions)
-----------------------------------------------------
local centerX = math.floor(width / 2)
local deltaX  = cardBack.width + LO.CARD_SPACING
local totalHandWidth = 5 * deltaX - LO.CARD_SPACING
local handStartX = centerX - math.floor(totalHandWidth / 2)
local cardY = LO.CARD_Y

-----------------------------------------------------
-- Rendering helpers
-----------------------------------------------------
local LINE_H = 9

local function drawCenteredLine(text, y, color)
  local tw = ui.getTextSize(text)
  screen:drawText(text, font, math.floor((width - tw) / 2), y, color or colors.white)
end

local function renderHand(hand, held, betAmount, statusText, showHoldLabels)
  screen:clear(LO.TABLE_COLOR)

  -- Bet display
  local betLabel = "Bet: " .. currency.formatTokens(betAmount)
  screen:drawText(betLabel, font, 1, 0, colors.white)

  -- Draw cards
  for i, cardID in ipairs(hand) do
    local x = handStartX + (i - 1) * deltaX
    local img = cards.renderCard(cardID)
    screen:drawSurface(img, x, cardY)

    -- HOLD label above held cards
    if showHoldLabels and held[i] then
      local holdLabel = "HOLD"
      local hw = ui.getTextSize(holdLabel)
      screen:drawText(holdLabel, font,
        x + math.floor((cardBack.width - hw) / 2),
        cardY - LINE_H - LO.HOLD_Y_OFFSET,
        colors.lime)
    end
  end

  -- Status text
  if statusText then
    local statusY = cardY + cardBack.height + 6
    drawCenteredLine(statusText, statusY, colors.yellow)
  end
end

-----------------------------------------------------
-- Payout table display
-----------------------------------------------------
local function showPayoutTable()
  screen:clear(LO.TABLE_COLOR)
  drawCenteredLine("PAYOUT TABLE", 1, colors.yellow)
  drawCenteredLine("Jacks or Better", 1 + LINE_H, colors.lightGray)

  local payStartY = 1 + LINE_H * 2 + 2
  local paySpacing = math.min(LINE_H, math.floor((height - payStartY - 10) / #PAYOUTS))
  local y = payStartY
  for _, p in ipairs(PAYOUTS) do
    local line = p.name
    local dots = ""
    local nameW = ui.getTextSize(p.name)
    local multStr = tostring(p.multiplier) .. "x"
    local multW = ui.getTextSize(multStr)
    local totalW = nameW + multW + 8

    local color = colors.white
    if p.multiplier >= 25 then
      color = colors.yellow
    elseif p.multiplier >= 4 then
      color = colors.cyan
    end

    screen:drawText(p.name, font, 4, y, color)
    screen:drawText(multStr, font, width - multW - 4, y, color)
    y = y + paySpacing
  end

  ui.clearButtons()
  ui.layoutButtonGrid(screen, {
    {{ text = "BACK", color = colors.red, func = function() end }},
  }, centerX, height - 10, 8, 4)
  screen:output()
  ui.waitForButton(0, 0)
end

-----------------------------------------------------
-- Tutorial / How to play screens
-----------------------------------------------------
local TUTORIAL_PAGES = {
  {
    title = "HOW TO PLAY",
    lines = {
      { text = "You get 5 cards.",       color = colors.white },
      { text = "Choose which to",        color = colors.white },
      { text = "HOLD and which to",      color = colors.lime },
      { text = "discard.",               color = colors.white },
      { text = "",                        color = colors.white },
      { text = "New cards replace",      color = colors.yellow },
      { text = "the discards.",          color = colors.yellow },
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
      { text = "Hold 4 to a flush",      color = colors.cyan },
      { text = "or straight.",           color = colors.cyan },
      { text = "",                        color = colors.white },
      { text = "Royal Flush = 250x!",    color = colors.yellow },
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
    local btnY = height - 9
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
    ui.layoutButtonGrid(screen, { navRow }, centerX, btnY, 8, 4)

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
  local statsSpacing = math.min(LINE_H, math.floor((height - y - 10) / 12))
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

  -- Show top winning hands
  y = y + 2
  drawCenteredLine("-- HANDS HIT --", y, colors.yellow)
  y = y + statsSpacing
  for _, p in ipairs(PAYOUTS) do
    local count = sessionStats.handCounts[p.name] or 0
    if count > 0 then
      statLine(p.name, count, colors.cyan)
    end
  end

  ui.clearButtons()
  ui.layoutButtonGrid(screen, {
    {{ text = "BACK", color = colors.red, func = function() end }},
  }, centerX, height - 10, 8, 4)
  screen:output()
  ui.waitForButton(0, 0)
end

-----------------------------------------------------
-- Pre-round menu
-----------------------------------------------------
local function preRoundMenu()
  while true do
    screen:clear(LO.TABLE_COLOR)

    local title = "VIDEO POKER"
    local tw = ui.getTextSize(title)
    screen:drawText(title, font, math.floor((width - tw) / 2), math.floor(height * 0.10), colors.yellow)

    local subtitle = "Jacks or Better"
    local sw = ui.getTextSize(subtitle)
    screen:drawText(subtitle, font, math.floor((width - sw) / 2), math.floor(height * 0.20), colors.lightGray)

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
      {
        { text = "STATS", color = colors.lightGray,
          func = function() chosen = "stats" end },
      },
    }, centerX, math.floor(height * 0.35), 8, 4)

    screen:output()

    if AUTO_PLAY then return end

    ui.waitForButton(0, 0)

    if chosen == "play" then return end
    if chosen == "payouts" then showPayoutTable() end
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
    gameName               = "VideoPoker",
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
-- Auto-play hold strategy (simple: keep pairs and high cards)
-----------------------------------------------------
local function autoSelectHolds(hand)
  local held = { false, false, false, false, false }
  local rankCounts = {}

  for i, cardID in ipairs(hand) do
    local r = getRank(cardID)
    rankCounts[r] = (rankCounts[r] or 0) + 1
  end

  for i, cardID in ipairs(hand) do
    local r = getRank(cardID)
    -- Hold any pair or better, or high cards (J+)
    if rankCounts[r] >= 2 or r >= 11 then
      held[i] = true
    end
  end

  return held
end

-----------------------------------------------------
-- Video Poker round
-----------------------------------------------------
local function pokerRound(betAmount, escrowId)
  recovery.saveEscrowBet(betAmount, {{ id = escrowId, amount = betAmount, tag = "initial" }})

  -- Fresh deck each hand
  freshDeck()

  -- Deal 5 cards
  local hand = {}
  for i = 1, cfg.HAND_SIZE do
    hand[i] = dealOne()
  end

  local held = { false, false, false, false, false }

  -- Animate initial deal
  if not AUTO_PLAY then
    local visCards = {}
    for i, cardID in ipairs(hand) do
      local x = handStartX + (i - 1) * deltaX
      local img = cards.renderCard(cardID)
      cardAnim.slideIn(img, x, cardY, function()
        screen:clear(LO.TABLE_COLOR)
        screen:drawText("Bet: " .. currency.formatTokens(betAmount), font, 1, 0, colors.white)
        for j, cid in ipairs(visCards) do
          screen:drawSurface(cards.renderCard(cid), handStartX + (j - 1) * deltaX, cardY)
        end
      end)
      table.insert(visCards, cardID)
    end
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end

  -- Hold/discard phase
  if AUTO_PLAY then
    held = autoSelectHolds(hand)
    os.sleep(cfg.AUTO_PLAY_DELAY)
  else
    local confirmed = false

    while not confirmed do
      renderHand(hand, held, betAmount, "Tap cards to HOLD", true)

      ui.clearButtons()

      -- Card touch areas (toggle hold via labeled buttons below each card)
      for i = 1, cfg.HAND_SIZE do
        local x = handStartX + (i - 1) * deltaX
        local idx = i
        local lblY = cardY + cardBack.height + 1
        local label = held[i] and "HELD" or ("Card" .. i)
        local lblColor = held[i] and colors.lime or colors.gray
        ui.fixedWidthButton(screen, label, lblColor,
          x + math.floor(cardBack.width / 2), lblY, function()
            held[idx] = not held[idx]
          end, true, cardBack.width)
      end

      -- Draw button
      local drawBtnY = cardY + cardBack.height + LINE_H + 6
      ui.fixedWidthButton(screen, "DRAW", colors.lime,
        centerX, drawBtnY, function()
          confirmed = true
        end, true, nil)

      screen:output()
      ui.waitForButton(0, 0)
    end
  end

  -- Replace non-held cards
  local replaced = false
  for i = 1, cfg.HAND_SIZE do
    if not held[i] then
      hand[i] = dealOne()
      replaced = true
    end
  end

  -- Animate replacement cards
  if replaced and not AUTO_PLAY then
    for i = 1, cfg.HAND_SIZE do
      if not held[i] then
        local x = handStartX + (i - 1) * deltaX
        local img = cards.renderCard(hand[i])
        cardAnim.slideIn(img, x, cardY, function()
          screen:clear(LO.TABLE_COLOR)
          screen:drawText("Bet: " .. currency.formatTokens(betAmount), font, 1, 0, colors.white)
          for j, cid in ipairs(hand) do
            local cx = handStartX + (j - 1) * deltaX
            if j < i or held[j] then
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

  if multiplier > 0 then
    -- Win
    totalPayout = betAmount * (multiplier + 1)  -- bet * multiplier + original bet back
    netChange = betAmount * multiplier

    -- Resolve escrow to player + pay profit
    currency.resolveEscrow(escrowId, "player", "VideoPoker: " .. handName)
    if netChange > 0 then
      local payOk = currency.payout(netChange, "VideoPoker: " .. handName .. " payout")
      if not payOk then
        alert.send("CRITICAL: Failed to pay " .. netChange .. " tokens to player!")
        alert.log("Payout failure: " .. netChange .. " tokens, hand=" .. handName)
      end
    end

    sound.play(sound.SOUNDS.SUCCESS)
    renderHand(hand, held, betAmount, nil, false)
    ui.displayCenteredMessage(screen,
      handName .. "! +" .. currency.formatTokens(netChange),
      colors.lime, LO.RESULT_PAUSE)
  else
    -- Loss
    netChange = -betAmount
    currency.resolveEscrow(escrowId, "host", "VideoPoker: no win")

    sound.play(sound.SOUNDS.FAIL)
    renderHand(hand, held, betAmount, nil, false)
    ui.displayCenteredMessage(screen, handName, colors.red, LO.RESULT_PAUSE)
  end

  -- Update session stats
  sessionStats.hands = sessionStats.hands + 1
  sessionStats.totalBet = sessionStats.totalBet + betAmount
  sessionStats.netProfit = sessionStats.netProfit + netChange
  if netChange > 0 then
    sessionStats.totalWon = sessionStats.totalWon + netChange
    if netChange > sessionStats.biggestWin then
      sessionStats.biggestWin = netChange
    end
  end
  sessionStats.handCounts[handName] = (sessionStats.handCounts[handName] or 0) + 1

  recovery.clearBet()
  dbg("Hand: " .. handName .. " mult=" .. multiplier .. " net=" .. netChange)
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
    local escrowId = nil

    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      local autoBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if autoBet > 0 then
        local ok, eid = currency.escrow(autoBet, "VideoPoker: auto-play bet")
        if ok and eid then
          betAmount = autoBet
          escrowId = eid
          os.sleep(cfg.AUTO_PLAY_DELAY)
        else
          os.sleep(1)
        end
      else
        os.sleep(1)
      end
    else
      preRoundMenu()

      local selectedBet, selEscrow = betSelection()
      if selectedBet and selectedBet > 0 and selEscrow then
        betAmount = selectedBet
        escrowId = selEscrow
      end
    end

    if betAmount and betAmount > 0 and escrowId then
      pokerRound(betAmount, escrowId)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
