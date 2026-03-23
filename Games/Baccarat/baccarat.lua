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
})

local screen   = env.screen
local deck     = env.deck
local width    = env.width
local height   = env.height
local cardBack = env.cardBack
local font     = env.font

-----------------------------------------------------
-- Host balance tracking
-----------------------------------------------------
local hostBankBalance = currency.getHostBalance()
dbg("Initial host balance: " .. hostBankBalance .. " tokens")

local function getMaxBet()
  return math.floor(hostBankBalance * cfg.MAX_BET_PERCENT)
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
local deltaX   = cardBack.width + LO.CARD_SPACING
local centerX  = math.floor(width / 2)
local statusY  = math.floor(height / 2)

-- Player hand on left side, Banker hand on right side
local playerAreaX = math.floor(width * 0.25)
local bankerAreaX = math.floor(width * 0.75)

-- Vertical positioning: labels at top, cards below, scores below cards
local labelY   = LO.PLAYER_LABEL_Y
local cardsY   = LO.PLAYER_CARDS_Y
local scoreY   = cardsY + cardBack.height + 2

-----------------------------------------------------
-- Rendering
-----------------------------------------------------
local function drawHand(hand, centerHandX, y)
  local totalWidth = #hand * deltaX - LO.CARD_SPACING
  local startX = centerHandX - math.floor(totalWidth / 2)
  for i, cardID in ipairs(hand) do
    local img = cards.renderCard(cardID)
    screen:drawSurface(img, startX + (i - 1) * deltaX, y)
  end
end

local function renderTable(playerHand, bankerHand, betType, betAmount, statusText)
  screen:clear(LO.TABLE_COLOR)

  -- Bet display
  local betLabel = "Bet: " .. currency.formatTokens(betAmount) .. " on " .. string.upper(betType)
  screen:drawText(betLabel, font, 1, 0, colors.white)

  -- "PLAYER" and "BANKER" labels
  local playerLabel = "PLAYER"
  local bankerLabel = "BANKER"
  local plW = ui.getTextSize(playerLabel)
  local blW = ui.getTextSize(bankerLabel)
  screen:drawText(playerLabel, font, playerAreaX - math.floor(plW / 2), labelY, colors.cyan)
  screen:drawText(bankerLabel, font, bankerAreaX - math.floor(blW / 2), labelY, colors.red)

  -- Draw hands
  if #playerHand > 0 then
    drawHand(playerHand, playerAreaX, cardsY)
    local pTotal = baccaratHandTotal(playerHand)
    local pStr = tostring(pTotal)
    local pW = ui.getTextSize(pStr)
    screen:drawText(pStr, font, playerAreaX - math.floor(pW / 2), scoreY, colors.white)
  end

  if #bankerHand > 0 then
    drawHand(bankerHand, bankerAreaX, cardsY)
    local bTotal = baccaratHandTotal(bankerHand)
    local bStr = tostring(bTotal)
    local bW = ui.getTextSize(bStr)
    screen:drawText(bStr, font, bankerAreaX - math.floor(bW / 2), scoreY, colors.white)
  end

  -- Status text (centered)
  if statusText then
    local tw = ui.getTextSize(statusText)
    screen:drawText(statusText, font, math.floor((width - tw) / 2), statusY, colors.yellow)
  end

  screen:output()
end

-----------------------------------------------------
-- Bet type selection (Player / Banker / Tie)
-----------------------------------------------------
local function selectBetType()
  screen:clear(LO.TABLE_COLOR)

  local title = "CHOOSE YOUR BET"
  local tw = ui.getTextSize(title)
  screen:drawText(title, font, math.floor((width - tw) / 2), math.floor(height * 0.2), colors.yellow)

  ui.clearButtons()
  local chosen = nil

  ui.layoutButtonGrid(screen, {{
    { text = "PLAYER (1:1)", color = colors.cyan,
      func = function() chosen = BET.PLAYER end },
    { text = "BANKER (1:1 -5%)", color = colors.red,
      func = function() chosen = BET.BANKER end },
    { text = "TIE (8:1)", color = colors.yellow,
      func = function() chosen = BET.TIE end },
  }}, centerX, math.floor(height * 0.45), 8, 4)

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
  return chosen
end

-----------------------------------------------------
-- Baccarat round
-----------------------------------------------------
local function baccaratRound(betAmount, betType, escrowId)
  recovery.saveEscrowBet(betAmount, {{ id = escrowId, amount = betAmount, tag = "initial" }})

  local playerHand = {}
  local bankerHand = {}
  local roundStart = epoch("local")

  -- Initial deal: 2 cards each, alternating (player, banker, player, banker)
  playerHand[1] = dealOne()
  bankerHand[1] = dealOne()
  playerHand[2] = dealOne()
  bankerHand[2] = dealOne()

  sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  renderTable(playerHand, bankerHand, betType, betAmount, nil)
  os.sleep(0.6)

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
      sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
      renderTable(playerHand, bankerHand, betType, betAmount, nil)
      os.sleep(0.5)
      playerTotal = baccaratHandTotal(playerHand)
    end

    -- Banker third card rule
    if bankerDrawsThird(bankerTotal, playerThirdValue) then
      table.insert(bankerHand, dealOne())
      sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
      renderTable(playerHand, bankerHand, betType, betAmount, nil)
      os.sleep(0.5)
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

  -- Transfer payout via escrow resolution
  if payout > 0 then
    if netChange == 0 then
      -- Push: cancel escrow (refund bet to player)
      currency.cancelEscrow(escrowId, "baccarat push")
    else
      -- Win: resolve escrow to player (bet returned) + payout profit separately
      currency.resolveEscrow(escrowId, "player", "baccarat win")
      local profit = payout - betAmount
      if profit > 0 then
        local payOk = currency.payout(profit, "baccarat win")
        if not payOk then
          alert.send("CRITICAL: Failed to pay " .. profit .. " tokens to player!")
          alert.log("Payout failure: " .. profit .. " tokens, outcome=" .. outcome)
          msg = "ERROR: Payout failed! Contact admin."
          msgClr = colors.red
          snd = sound.SOUNDS.ERROR
        end
      end
    end
  else
    -- Loss: resolve escrow to host
    currency.resolveEscrow(escrowId, "host", "baccarat loss")
  end

  -- Show result
  local naturalTag = isNatural and " (Natural)" or ""
  renderTable(playerHand, bankerHand, betType, betAmount, nil)
  ui.displayCenteredMessage(screen, msg .. naturalTag, msgClr, LO.RESULT_PAUSE)
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
    local escrowId = nil

    if AUTO_PLAY then
      local playerBalance = currency.getPlayerBalance()
      local autoBet = math.min(cfg.AUTO_PLAY_BET, playerBalance, getMaxBet())
      if autoBet > 0 then
        local ok, eid = currency.escrow(autoBet, "baccarat auto-play bet")
        if ok and eid then
          betAmount = autoBet
          escrowId = eid
          betType = selectBetType()
          os.sleep(cfg.AUTO_PLAY_DELAY)
        else
          os.sleep(1)
        end
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
        local selectedBet, selEscrow = betSelection()
        if selectedBet and selectedBet > 0 and selEscrow then
          betAmount = selectedBet
          escrowId = selEscrow
        end
      end
    end

    if betAmount and betAmount > 0 and betType and escrowId then
      baccaratRound(betAmount, betType, escrowId)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. hostBankBalance .. " (" .. currency.formatTokens(getMaxBet()) .. " max bet)")
    end
  end
end

local safeRunner = require("lib.safe_runner")
safeRunner.run(main)
