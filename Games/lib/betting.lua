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

local ceil  = math.ceil
local floor = math.floor
local max   = math.max
local min   = math.min

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[betting] " .. msg) end
end

local function appendGridRows(rows, buttons, columns)
  local index = 1
  while index <= #buttons do
    local row = {}
    local column = 1
    while column <= columns and index <= #buttons do
      row[#row + 1] = buttons[index]
      index = index + 1
      column = column + 1
    end
    rows[#rows + 1] = row
  end
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

    local metrics = ui.getMetrics()
    local titleY = metrics.titleY
    local warnY = titleY + metrics.messageLineHeight
    local betY = warnY + metrics.lineHeight

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
    ui.safeDrawText(screen, title, ui.getFont(), ui.round((screen.width - titleSize) / 2), titleY, colors.white)

    -- Inactivity countdown warning (last 10 seconds)
    if bet == 0 then
      local warnThreshold = inactivityTimeout - 10000
      if idleMs >= warnThreshold then
        local secsLeft = ceil((inactivityTimeout - idleMs) / 1000)
        local warnMsg = "Auto-exit in " .. secsLeft .. "s..."
        local warnSize = ui.getTextSize(warnMsg)
        ui.safeDrawText(screen, warnMsg, ui.getFont(), ui.round((screen.width - warnSize) / 2), warnY, colors.orange)
      end
    end

    -- Current bet display
    local betStr = "Bet: " .. currency.formatTokens(bet)
    local betStrSize = ui.getTextSize(betStr)
    ui.safeDrawText(screen, betStr, ui.getFont(), ui.round((screen.width - betStrSize) / 2), betY, colors.yellow)

    -- Buttons
    ui.clearButtons()
    local btnX = ui.round(screen.width / 2)

    -- Measure widest button to make all uniform
    local buttonTexts = {}
    for _, denom in ipairs(currency.DENOMINATIONS) do
      buttonTexts[#buttonTexts + 1] = denom.name
    end
    buttonTexts[#buttonTexts + 1] = "ALL IN"
    buttonTexts[#buttonTexts + 1] = "CLEAR"
    buttonTexts[#buttonTexts + 1] = "QUIT"
    buttonTexts[#buttonTexts + 1] = confirmLabel

    local textWidths = {}
    for _, txt in ipairs(buttonTexts) do
      textWidths[#textWidths + 1] = ui.getTextSize(txt)
    end
    local maxWidth = metrics:fixedButtonWidth(textWidths, 2)

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

    local allInButton = {
      text = "ALL IN",
      color = colors.orange,
      width = maxWidth,
      func = function()
        local playerBal = currency.getPlayerBalance()
        local available = playerBal - bet
        if available <= 0 then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "No tokens!", colors.red)
          return
        end
        local remainingAllowable = maxBet - bet
        if hostBalance and hostCoverageMult > 1 then
          local coverageCap = floor(hostBalance / (hostCoverageMult - 1)) - bet
          remainingAllowable = min(remainingAllowable, coverageCap)
        end
        local amountToBet = min(available, remainingAllowable)
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
      end,
    }

    local quitButton = {
      text = "QUIT",
      color = colors.gray,
      width = maxWidth,
      func = function()
        bet = 0
        sound.play(sound.SOUNDS.TIMEOUT)
        onQuit()
      end,
    }

    local clearButton = {
      text = "CLEAR",
      color = colors.red,
      width = maxWidth,
      func = function()
        if bet > 0 then
          bet = 0
          sound.play(sound.SOUNDS.CLEAR)
        end
      end,
    }

    local confirmButton = {
      text = confirmLabel,
      color = colors.magenta,
      width = maxWidth,
      func = function()
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
      end,
    }

    local availableWidth = screen.width - (metrics.edgePad * 2)
    local availableHeight = screen.height - betY - metrics.messageLineHeight - metrics.edgePad
    local maxColumns = min(3, #currency.DENOMINATIONS)
    local denomColumns = 1
    local widestFit = 1
    local controlRowWidth = (maxWidth * 2) + metrics.buttonColGap
    local controlsCanPair = controlRowWidth <= availableWidth

    for columns = 1, maxColumns do
      local rowWidth = (columns * maxWidth) + ((columns - 1) * metrics.buttonColGap)
      if rowWidth <= availableWidth then
        widestFit = columns
        local denomRows = ceil(#currency.DENOMINATIONS / columns)
        local controlRows = controlsCanPair and 2 or 3
        local totalRows = denomRows + controlRows
        local neededHeight = metrics.buttonHeight + ((totalRows - 1) * metrics.buttonRowSpacing)
        if neededHeight <= availableHeight then
          denomColumns = columns
          break
        end
      end
    end
    if denomColumns == 1 and widestFit > 1 then
      denomColumns = widestFit
    end

    local rows = {}
    local denominationButtons = {}
    for _, denom in ipairs(currency.DENOMINATIONS) do
      denominationButtons[#denominationButtons + 1] = {
        text = denom.name,
        color = denom.color,
        width = maxWidth,
        func = addBet(denom),
      }
    end
    appendGridRows(rows, denominationButtons, denomColumns)

    if controlsCanPair then
      rows[#rows + 1] = { allInButton, quitButton }
    else
      rows[#rows + 1] = { allInButton }
      rows[#rows + 1] = { quitButton }
    end
    rows[#rows + 1] = { clearButton, confirmButton }

    local totalRows = #rows
    local blockHeight = metrics.buttonHeight + ((totalRows - 1) * metrics.buttonRowSpacing)
    local minStartY = betY + metrics.messageLineHeight + metrics.sectionGap
    local latestStartY = max(metrics.edgePad, screen.height - blockHeight - metrics.edgePad)
    local btnStartY = max(minStartY, floor((screen.height - blockHeight) / 2))
    if btnStartY > latestStartY then
      btnStartY = latestStartY
    end

    ui.layoutButtonGrid(screen, rows, btnX, btnStartY)

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
