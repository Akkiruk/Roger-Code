-- betting.lua
-- Shared betting interface for all casino games.
-- Renders suggested bet presets scaled to each game's max bet, plus CLEAR, QUIT,
-- and a configurable confirm button.
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
local activityTimeout = require("lib.activity_timeout")

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

local function compactAmountLabel(value)
  value = tonumber(value) or 0
  local absValue = math.abs(value)
  if absValue >= 1000000 and absValue % 1000000 == 0 then
    return tostring(value / 1000000) .. "M"
  end
  if absValue >= 1000 and absValue % 1000 == 0 then
    return tostring(value / 1000) .. "K"
  end
  return tostring(value)
end

local function getPresetBetSound(amount)
  local chosenSound = sound.SOUNDS.ALL_IN
  for _, denom in ipairs(currency.DENOMINATIONS) do
    local denomValue = tonumber(denom.value) or 0
    if denomValue > 0 and amount >= denomValue and denom.sound then
      chosenSound = denom.sound
    end
  end
  return chosenSound
end

local function buildPresetBetSpecs(maxBetAmount, compactLabels)
  local maxBetValue = max(0, floor(tonumber(maxBetAmount) or 0))
  local presetSpecs = {}
  local seenAmounts = {}

  local function addPreset(kind, amount, color)
    amount = floor(tonumber(amount) or 0)
    if amount < 1 or amount > maxBetValue or seenAmounts[amount] then
      return
    end

    local label = compactLabels and compactAmountLabel(amount) or currency.formatTokens(amount)
    if kind == "max" then
      label = compactLabels and ("MAX " .. compactAmountLabel(amount)) or ("MAX " .. currency.formatTokens(amount))
    end

    seenAmounts[amount] = true
    presetSpecs[#presetSpecs + 1] = {
      amount = amount,
      color = color,
      label = label,
      sound = getPresetBetSound(amount),
    }
  end

  addPreset("token", 1, colors.white)
  addPreset("quarter", floor(maxBetValue * 0.25), colors.yellow)
  addPreset("half", floor(maxBetValue * 0.50), colors.lime)
  addPreset("three_quarter", floor(maxBetValue * 0.75), colors.cyan)
  addPreset("max", maxBetValue, colors.orange)

  return presetSpecs
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
  local timeoutState = activityTimeout.create(inactivityTimeout)
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
      idleMs = timeoutState and timeoutState:elapsed() or 0
      if timeoutState and timeoutState:isExpired() then
        onTimeout()
        return 0
      end
    end

    -- Header
    local titleSize = ui.getTextSize(title)
    ui.safeDrawText(screen, title, ui.getFont(), ui.round((screen.width - titleSize) / 2), titleY, colors.white)

    -- Inactivity countdown warning (last 10 seconds)
    if bet == 0 and timeoutState and timeoutState:isWarning() then
      local secsLeft = timeoutState:secondsLeft()
      local warnMsg = "Auto-exit in " .. secsLeft .. "s..."
      local warnSize = ui.getTextSize(warnMsg)
      ui.safeDrawText(screen, warnMsg, ui.getFont(), ui.round((screen.width - warnSize) / 2), warnY, colors.orange)
    end

    -- Current bet display
    local betStr = "Bet: " .. currency.formatTokens(bet)
    local betStrSize = ui.getTextSize(betStr)
    ui.safeDrawText(screen, betStr, ui.getFont(), ui.round((screen.width - betStrSize) / 2), betY, colors.yellow)

    -- Buttons
    ui.clearButtons()
    local btnX = ui.round(screen.width / 2)
    local availableWidth = screen.width - (metrics.edgePad * 2)
    local compactLabels = metrics.compact and availableWidth < 120

    local presetSpecs = buildPresetBetSpecs(maxBet, compactLabels)

    local clearLabel = compactLabels and "CLR" or "CLEAR"
    local quitLabel = "QUIT"
    local confirmText = compactLabels and confirmLabel:sub(1, min(#confirmLabel, 4)) or confirmLabel

    -- Measure widest button to make all uniform
    local buttonTexts = {}
    for _, preset in ipairs(presetSpecs) do
      buttonTexts[#buttonTexts + 1] = preset.label
    end
    buttonTexts[#buttonTexts + 1] = clearLabel
    buttonTexts[#buttonTexts + 1] = quitLabel
    buttonTexts[#buttonTexts + 1] = confirmText

    local textWidths = {}
    for _, txt in ipairs(buttonTexts) do
      textWidths[#textWidths + 1] = ui.getTextSize(txt)
    end
    local maxWidth = compactLabels and nil or metrics:fixedButtonWidth(textWidths, 2)

    local function buttonWidthForText(text)
      if maxWidth then
        return maxWidth
      end
      return metrics:buttonWidth(ui.getTextSize(text))
    end

    local widestButton = 0
    for _, txt in ipairs(buttonTexts) do
      widestButton = max(widestButton, buttonWidthForText(txt))
    end

    -- Preset bet callbacks: set the wager directly with no transfers until confirm.
    local function chooseBet(preset)
      return function()
        local amt = preset.amount
        local playerBal = currency.getPlayerBalance()
        if playerBal < amt then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "Insufficient funds!", colors.red)
          return
        end
        if amt > maxBet then
          sound.play(sound.SOUNDS.ERROR)
          ui.displayCenteredMessage(screen, "Maximum bet reached!", colors.red)
          return
        end
        if hostBalance then
          local needed = amt * (hostCoverageMult - 1)
          if hostBalance < needed then
            sound.play(sound.SOUNDS.ERROR)
            ui.displayCenteredMessage(screen, "Maximum wagering threshold exceeded!", colors.red)
            return
          end
        end
        bet = amt
        sound.play(preset.sound)
      end
    end

    local quitButton = {
      text = quitLabel,
      color = colors.gray,
      width = maxWidth,
      func = function()
        bet = 0
        sound.play(sound.SOUNDS.TIMEOUT)
        onQuit()
      end,
    }

    local clearButton = {
      text = clearLabel,
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
      text = confirmText,
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

    local availableHeight = screen.height - betY - metrics.messageLineHeight - metrics.edgePad
    local maxColumns = min(3, max(1, #presetSpecs))
    local presetColumns = 1
    local widestFit = 1
    local controlRowWidth = buttonWidthForText(quitLabel) + buttonWidthForText(clearLabel)
      + buttonWidthForText(confirmText) + (metrics.buttonColGap * 2)
    local controlsSingleRow = controlRowWidth <= availableWidth

    for columns = 1, maxColumns do
      local rowWidth = (columns * widestButton) + ((columns - 1) * metrics.buttonColGap)
      if rowWidth <= availableWidth then
        widestFit = columns
        local presetRows = ceil(max(1, #presetSpecs) / columns)
        if #presetSpecs == 0 then
          presetRows = 0
        end
        local controlRows = controlsSingleRow and 1 or 2
        local totalRows = presetRows + controlRows
        local neededHeight = metrics.buttonHeight + ((totalRows - 1) * metrics.buttonRowSpacing)
        if neededHeight <= availableHeight then
          presetColumns = columns
          break
        end
      end
    end
    if presetColumns == 1 and widestFit > 1 then
      presetColumns = widestFit
    end

    local rows = {}
    local presetButtons = {}
    for _, preset in ipairs(presetSpecs) do
      presetButtons[#presetButtons + 1] = {
        text = preset.label,
        color = preset.color,
        width = maxWidth,
        func = chooseBet(preset),
      }
    end
    appendGridRows(rows, presetButtons, presetColumns)

    if controlsSingleRow then
      rows[#rows + 1] = { quitButton, clearButton, confirmButton }
    else
      rows[#rows + 1] = { quitButton, clearButton }
      rows[#rows + 1] = { confirmButton }
    end

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
        if timeoutState then
          timeoutState:touch()
        end
        if px and py then
          local cb = ui.checkButtonHit(px, py)
          if cb then
            cb()
            break
          end
        end
      elseif event == "timer" and side == timerID then
        -- Check timeout
        if bet == 0 and timeoutState and timeoutState:isExpired() then
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
