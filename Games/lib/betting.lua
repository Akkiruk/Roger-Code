-- betting.lua
-- Shared betting interface for all casino games.
-- Renders denomination buttons, ALL IN, CLEAR, and a configurable confirm button.
-- Uses CCVault token economy via currency module.
-- Usage:
--   local betting = require("lib.betting")
--   local bet = betting.runBetScreen(screen, {
--     maxBet = 1000,
--     confirmLabel = "DEAL",
--     title = "PLACE YOUR BET",
--     inactivityTimeout = 30000,
--   })

local currency = require("lib.currency")
local sound    = require("lib.sound")
local ui       = require("lib.ui")

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[betting] " .. msg) end
end

--- Run the full betting screen loop. Returns the confirmed bet in tokens.
-- Chips are tracked locally (no transfers until the game round resolves).
-- On confirm, validates the player has sufficient balance.
-- @param screen     surface   The screen surface to draw on
-- @param opts       table     Options:
--   maxBet              number   Maximum bet in tokens (required)
--   gameName            string   Game name for transaction reasons (e.g. "Blackjack")
--   confirmLabel        string   Label for the deal/play button (default "DEAL")
--   title               string   Header text (default "PLACE YOUR BET")
--   inactivityTimeout   number   Milliseconds before auto-exit with no bet (default 30000)
--   onTimeout           function Called on inactivity timeout (default: error)
--   hostBalance         number?  Override for host balance limit calculations
--   hostCoverageMultiplier number? Total payout multiple including the returned wager;
--                                  transfers settle net at round end, so this module
--                                  subtracts 1 internally when checking coverage.
--   onQuit              function Called when the player presses QUIT (default: error("player_quit"))
-- @return number bet  Confirmed bet amount (0 if timed out)
local function runBetScreen(screen, opts)
  opts = opts or {}
  local maxBet             = opts.maxBet or error("maxBet is required")
  local gameName           = opts.gameName or "Casino"
  local confirmLabel       = opts.confirmLabel or "DEAL"
  local title              = opts.title or "PLACE YOUR BET"
  local inactivityTimeout  = opts.inactivityTimeout or 30000
  local onTimeout          = opts.onTimeout or function()
    sound.play(sound.SOUNDS.TIMEOUT)
    os.sleep(0.5)
    error("inactivity_timeout")
  end
  local hostBalance        = opts.hostBalance
  local hostCoverageMult   = opts.hostCoverageMultiplier or 3
  local onQuit             = opts.onQuit or function()
    error("player_quit")
  end

  -- Session lock: capture the authenticated player so others can't play on their dime
  local sessionPlayer = currency.getAuthenticatedPlayerName() or currency.getPlayerName()

  local bet = 0
  local selecting = true
  local lastActivityTime = os.epoch("local")
  local timerID = nil

  while selecting do
    screen:clear(colors.green)

    -- Check inactivity when no bet placed
    local idleMs = 0
    if bet == 0 then
      local now = os.epoch("local")
      idleMs = now - lastActivityTime
      if idleMs > inactivityTimeout then
        onTimeout()
        return 0
      end
    end

    -- Header
    local titleSize = ui.getTextSize(title)
    ui.safeDrawText(screen, title, ui.getFont(), ui.round((screen.width - titleSize) / 2), 1, colors.white)

    -- Inactivity countdown warning (last 10 seconds)
    if bet == 0 then
      local warnThreshold = inactivityTimeout - 10000
      if idleMs >= warnThreshold then
        local secsLeft = math.ceil((inactivityTimeout - idleMs) / 1000)
        local warnMsg = "Auto-exit in " .. secsLeft .. "s..."
        local warnSize = ui.getTextSize(warnMsg)
        ui.safeDrawText(screen, warnMsg, ui.getFont(), ui.round((screen.width - warnSize) / 2), 10, colors.orange)
      end
    end

    -- Current bet display
    local betStr = "Bet: " .. currency.formatTokens(bet)
    local betStrSize = ui.getTextSize(betStr)
    ui.safeDrawText(screen, betStr, ui.getFont(), ui.round((screen.width - betStrSize) / 2), 6, colors.yellow)

    -- Buttons
    ui.clearButtons()
    local btnStartY = 15
    local btnSpacing = 7
    local btnX = ui.round(screen.width / 2)

    -- Measure widest button to make all uniform
    local buttonTexts = {}
    for _, denom in ipairs(currency.DENOMINATIONS) do
      table.insert(buttonTexts, denom.name)
    end
    table.insert(buttonTexts, "ALL IN")
    table.insert(buttonTexts, "CLEAR")
    table.insert(buttonTexts, confirmLabel)

    local maxWidth = 0
    for _, txt in ipairs(buttonTexts) do
      local w = ui.getTextSize(txt) + 6
      if w > maxWidth then maxWidth = w end
    end
    if maxWidth % 2 == 1 then maxWidth = maxWidth + 1 end

    -- Add-bet callbacks: counter-based, no transfers until confirm
    local function addBet(denomination)
      return function()
        local amt = denomination.value
        local playerBal = currency.getPlayerBalance()
        local available = playerBal - bet
        if available < amt then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "Insufficient funds!", colors.red)
          return
        end
        if bet + amt > maxBet then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "Maximum bet reached!", colors.red)
          return
        end
        if hostBalance then
          local totalBet = bet + amt
          local needed = totalBet * (hostCoverageMult - 1)
          if hostBalance < needed then
            sound.play(sound.SOUNDS.ERROR)
            ui.displayCenteredMessage(screen, "Maximum wagering threshold exceeded!", colors.red)
            return
          end
        end
        bet = bet + amt
        sound.play(denomination.sound)
      end
    end

    -- Denomination buttons
    for i, denom in ipairs(currency.DENOMINATIONS) do
      ui.fixedWidthButton(screen, denom.name, denom.color,
        btnX, btnStartY + btnSpacing * (i - 1), addBet(denom), true, maxWidth)
    end

    -- ALL IN button
    local allInY = btnStartY + btnSpacing * #currency.DENOMINATIONS
    ui.fixedWidthButton(screen, "ALL IN", colors.orange, btnX, allInY, function()
      local playerBal = currency.getPlayerBalance()
      local available = playerBal - bet
      if available <= 0 then
        sound.play(sound.SOUNDS.ERROR)
        ui.displayCenteredMessage(screen, "No tokens!", colors.red)
        return
      end
      local remainingAllowable = maxBet - bet
      if hostBalance and hostCoverageMult > 1 then
        local coverageCap = math.floor(hostBalance / (hostCoverageMult - 1)) - bet
        remainingAllowable = math.min(remainingAllowable, coverageCap)
      end
      local amountToBet = math.min(available, remainingAllowable)
      if amountToBet <= 0 then
        sound.play(sound.SOUNDS.ERROR)
        ui.displayCenteredMessage(screen, "Maximum bet reached!", colors.red)
        return
      end
      bet = bet + amountToBet
      sound.play(sound.SOUNDS.ALL_IN)
      if amountToBet < available then
        ui.displayCenteredMessage(screen, "Maximum allowable bet!", colors.yellow, 0.8)
      end
    end, true, maxWidth)

    -- QUIT button (below ALL IN, full width)
    local quitY = allInY + btnSpacing
    ui.fixedWidthButton(screen, "QUIT", colors.gray, btnX, quitY, function()
      bet = 0
      sound.play(sound.SOUNDS.TIMEOUT)
      onQuit()
    end, true, maxWidth)

    -- CLEAR and DEAL/CONFIRM side by side
    local ctrlY = quitY + btnSpacing
    local clearWidth = ui.getTextSize("CLEAR") + 4
    local dealWidth  = ui.getTextSize(confirmLabel) + 4
    local controlSpacing = 1
    local totalCtrlWidth = clearWidth + dealWidth + controlSpacing
    local clearX = math.floor(btnX - totalCtrlWidth / 2)
    local dealX  = clearX + clearWidth + controlSpacing

    -- CLEAR: just resets counter, no refund transfer needed
    ui.fixedWidthButton(screen, "CLEAR", colors.red, clearX, ctrlY, function()
      if bet > 0 then
        bet = 0
        sound.play(sound.SOUNDS.CLEAR)
      end
    end, false, clearWidth)

    -- DEAL/CONFIRM: validate balance and start game
    ui.fixedWidthButton(screen, confirmLabel, colors.magenta, dealX, ctrlY, function()
      if bet > 0 then
        -- Final balance check before starting
        local playerBal = currency.getPlayerBalance()
        if playerBal < bet then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "Insufficient funds!", colors.red)
          bet = 0
          return
        end
        sound.play(sound.SOUNDS.START)
        selecting = false
      else
        ui.displayCenteredMessage(screen, "Place a bet first!", colors.red)
      end
    end, false, dealWidth)

    screen:output()

    -- Wait for touch or timeout
    if timerID then os.cancelTimer(timerID) end
    timerID = os.startTimer(0.5)
    while true do
      local event, side, px, py = os.pullEvent()
      if event == "monitor_touch" then
        -- Session lock: reject touches from other players
        if sessionPlayer then
          local sessionInfo = currency.getSessionInfo and currency.getSessionInfo() or nil
          local currentPlayer = (currency.getLivePlayerName and currency.getLivePlayerName())
            or ((sessionInfo and sessionInfo.playerName) or nil)
          if currentPlayer and currentPlayer ~= sessionPlayer then
            ui.displayCenteredMessage(screen, "Game in use by " .. sessionPlayer, colors.red, 1.5)
            break
          end
        end
        lastActivityTime = os.epoch("local")
        if px and py then
          local cb = ui.checkButtonHit(px, py)
          if cb then
            cb()
            break
          end
        end
      elseif event == "timer" and side == timerID then
        -- Check timeout
        if bet == 0 and (os.epoch("local") - lastActivityTime) > inactivityTimeout then
          onTimeout()
          return 0
        end
        break  -- redraw
      end
    end
  end

  return bet
end

return {
  runBetScreen = runBetScreen,
}
