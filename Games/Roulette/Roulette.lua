-- roulette.lua
-- European Roulette with a single-screen felt UI and multi-bet support.

local cfg = require("roulette_config")

local currency = require("lib.currency")
local sound = require("lib.sound")
local ui = require("lib.ui")
local alert = require("lib.alert")
local recovery = require("lib.crash_recovery")
local gameSetup = require("lib.game_setup")
local replayPrompt = require("lib.replay_prompt")
local safeRunner = require("lib.safe_runner")
local settlement = require("lib.round_settlement")

local rouletteModel = require("roulette_model")
local rouletteLayout = require("roulette_layout")
local rouletteRender = require("roulette_render")

local epoch = os.epoch
local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local random = math.random
local randomseed = math.randomseed
local r_getInput = redstone.getInput
local settings_get = settings.get
local insert = table.insert

settings.define("roulette.debug", {
  description = "Enable debug messages for Roulette.",
  type = "boolean",
  default = false,
})

local DEBUG = settings_get("roulette.debug")

local function dbg(message)
  if DEBUG then
    print("[" .. epoch("local") .. "] [roulette] " .. tostring(message))
  end
end

local AUTO_PLAY = false
local sessionPlayer = nil
local renderCurrent = nil

recovery.configure(cfg.RECOVERY_FILE)
recovery.setGame(cfg.GAME_NAME)

local roulettePalette = {}
for colorID, hex in pairs(gameSetup.DEFAULT_PALETTE) do
  roulettePalette[colorID] = hex
end
if cfg.PALETTE then
  for colorID, hex in pairs(cfg.PALETTE) do
    roulettePalette[colorID] = hex
  end
end

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount = 1,
  gameName = cfg.GAME_NAME,
  logFile = cfg.LOG_FILE,
  skipAuth = false,
  palette = roulettePalette,
})

alert.addPlannedExits({
  cfg.EXIT_CODES.INACTIVITY_TIMEOUT,
  cfg.EXIT_CODES.MAIN_MENU,
  cfg.EXIT_CODES.USER_TERMINATED,
  cfg.EXIT_CODES.PLAYER_QUIT,
})

local screen = env.screen
local width = env.width
local height = env.height
local font = env.font
local scale = env.scale
local layout = rouletteLayout.build(width, height, #currency.DENOMINATIONS, scale)
local spinFullRotations = cfg.SPIN_FULL_ROTATIONS or 4
local spinMinDelay = cfg.SPIN_MIN_DELAY or cfg.SPIN_FRAME_DELAY or 0.018
local spinMaxDelay = cfg.SPIN_MAX_DELAY or cfg.SPIN_FRAME_DELAY or 0.120
local spinSettleDelay = cfg.SPIN_SETTLE_DELAY or cfg.SPIN_FRAME_DELAY or 0.045
local spinFastSubframes = max(1, cfg.SPIN_FAST_SUBFRAMES or 1)
local spinSlowSubframes = max(spinFastSubframes, cfg.SPIN_SLOW_SUBFRAMES or 2)
local spinSlowdownAt = cfg.SPIN_SLOWDOWN_AT or 0.78

sound.addSounds(cfg.SOUND_IDS or {})

sessionPlayer = currency.getAuthenticatedPlayerName() or currency.getPlayerName()
recovery.setPlayer(sessionPlayer or "Unknown")

local state = {
  autoPlay = false,
  phase = "betting",
  currentPlayer = sessionPlayer or env.currentPlayer or "Unknown",
  statusText = "Pick a chip, then tap the table.",
  statusTone = "neutral",
  statusUntil = 0,
  selectedChipIndex = min(2, #currency.DENOMINATIONS),
  denominations = currency.DENOMINATIONS,
  bets = {},
  betActions = {},
  history = {},
  playerBalance = 0,
  hostBalance = 0,
  totalStake = 0,
  maxExposure = 0,
  wheelOffset = 0,
  ballAngle = -math.pi / 2,
  resultNumber = nil,
  highlightKeys = nil,
  sessionProfit = 0,
  sessionProfitText = "0",
  sessionProfitTone = "neutral",
  betActionCount = 0,
  lastBalanceRefresh = 0,
}

local function formatSignedTokens(amount)
  if amount > 0 then
    return "+" .. currency.formatTokens(amount)
  elseif amount < 0 then
    return "-" .. currency.formatTokens(-amount)
  end
  return "even"
end

local function getRouletteSound(name, fallback)
  local soundId = sound.SOUNDS[name]
  if soundId then
    return soundId
  end
  return fallback
end

local function playRouletteSound(name, fallback, volume)
  sound.play(getRouletteSound(name, fallback), volume)
end

local function playSpinPointerClick(progress)
  local fallback = getRouletteSound("SPIN_TICK", sound.SOUNDS.CARD_PLACE)
  local volume = 0.15 + (min(1, max(0, progress or 0)) * 0.10)
  playRouletteSound("SPIN_POINTER", fallback, volume)
end

local function getBetPlacementSound(region)
  if not region or not region.kind then
    return getRouletteSound("BET_OUTSIDE", sound.SOUNDS.CARD_PLACE)
  end

  if region.kind == "straight"
    or region.kind == "split"
    or region.kind == "corner"
    or region.kind == "street"
    or region.kind == "line" then
    return getRouletteSound("BET_INSIDE", sound.SOUNDS.CARD_PLACE)
  end

  return getRouletteSound("BET_OUTSIDE", sound.SOUNDS.ALL_IN)
end

local function setStatus(text, tone, stickyMs)
  state.statusText = text
  state.statusTone = tone or "neutral"
  state.statusUntil = epoch("local") + (stickyMs or 1600)
end

local function refreshDerivedState()
  state.autoPlay = AUTO_PLAY
  state.denominations = currency.DENOMINATIONS
  state.totalStake = rouletteModel.getTotalStake(state.bets)
  state.maxExposure = rouletteModel.getMaxExposure(state.bets)
  state.betActionCount = #state.betActions

  if state.sessionProfit > 0 then
    state.sessionProfitText = "+" .. currency.formatTokens(state.sessionProfit)
    state.sessionProfitTone = "success"
  elseif state.sessionProfit < 0 then
    state.sessionProfitText = "-" .. currency.formatTokens(-state.sessionProfit)
    state.sessionProfitTone = "error"
  else
    state.sessionProfitText = "0"
    state.sessionProfitTone = "neutral"
  end
end

local function refreshAutoPlay()
  local powered = r_getInput(cfg.REDSTONE)
  if powered ~= AUTO_PLAY then
    AUTO_PLAY = powered
    dbg("Auto-play " .. (AUTO_PLAY and "enabled" or "disabled"))
    if AUTO_PLAY then
      setStatus("Auto play enabled.", "accent", 1200)
    else
      setStatus("Manual play restored.", "accent", 1200)
    end
  end
  return AUTO_PLAY
end

local function refreshPlayerState(forceBalances)
  local detectedPlayer = env.refreshPlayer()
  local sessionInfo = currency.getSessionInfo and currency.getSessionInfo() or nil
  local currentSessionPlayer = (sessionInfo and sessionInfo.playerName) or currency.getPlayerName()

  if sessionPlayer == nil or sessionPlayer == "" then
    sessionPlayer = currentSessionPlayer or detectedPlayer
  end

  state.currentPlayer = currentSessionPlayer or detectedPlayer or sessionPlayer or "Unknown"
  recovery.setPlayer(state.currentPlayer)

  local now = epoch("local")
  if forceBalances or (now - state.lastBalanceRefresh) > 1000 then
    state.playerBalance = currency.getPlayerBalance()
    state.hostBalance = currency.getProtectedHostBalance(currency.getHostBalance())
    state.lastBalanceRefresh = now
  end
end

local function validateCurrentSession()
  local sessionInfo = currency.getSessionInfo and currency.getSessionInfo() or nil
  local currentSessionPlayer = (currency.getLivePlayerName and currency.getLivePlayerName())
    or ((sessionInfo and sessionInfo.playerName) or nil)

  if sessionPlayer and currentSessionPlayer and currentSessionPlayer ~= sessionPlayer then
    return false, "Game in use by " .. sessionPlayer .. "."
  end

  return true, nil
end

local function validateBetSet(candidateBets)
  local totalStake = rouletteModel.getTotalStake(candidateBets)
  local exposure = rouletteModel.getMaxExposure(candidateBets)

  if totalStake <= 0 then
    return false, "Tap a number or color first.", totalStake, exposure
  end
  if totalStake > (state.playerBalance or 0) then
    return false, "You do not have enough tokens.", totalStake, exposure
  end
  local limitedBet, stakeCap = rouletteModel.findStakeLimitViolation(
    candidateBets,
    state.hostBalance or 0,
    cfg.MAX_BET_PERCENT
  )
  if limitedBet then
    return false, limitedBet.label .. " limit is " .. currency.formatTokens(stakeCap) .. ".", totalStake, exposure
  end
  if exposure > (state.hostBalance or 0) then
    return false, "House coverage limit exceeded.", totalStake, exposure
  end
  return true, nil, totalStake, exposure
end

local function buildChangesFromBets(bets)
  local changes = {}
  for _, bet in ipairs(bets or {}) do
    local region = layout.regionByKey[bet.key]
    if region then
      insert(changes, {
        region = region,
        amount = bet.stake or 0,
      })
    end
  end
  return changes
end

local function copyReplayChanges(changes)
  local copied = {}

  for _, change in ipairs(changes or {}) do
    copied[#copied + 1] = {
      region = change.region,
      amount = change.amount,
    }
  end

  return copied
end

local function rebuildBetsFromChanges(changes)
  local bets = {}

  for _, change in ipairs(changes or {}) do
    if change.region and change.amount then
      rouletteModel.addStake(bets, change.region, change.amount)
    end
  end

  return bets
end

local function canReplayChanges(changes)
  if #(changes or {}) == 0 then
    return false, "Place a fresh bet to keep going."
  end

  local ok, err = validateBetSet(rebuildBetsFromChanges(changes))
  if not ok then
    return false, err or "Adjust the bet before playing again."
  end

  return true
end

local function waitForReplayChoice(replayChanges)
  local metrics = ui.getMetrics()
  local choiceHintY = math.max(scale.subtitleY, metrics.footerButtonY - metrics.buttonRowSpacing - scale.lineHeight - 2)

  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderCurrent(nil)
    end,
    hint = function()
      local replayAvailable, replayHint = canReplayChanges(replayChanges)
      if replayAvailable then
        return "Touch PLAY AGAIN to restore the last layout.", colors.lightGray
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
            return canReplayChanges(replayChanges)
          end,
          disabled_message = "Set a new wager before spinning again.",
        },
        {
          id = "new_bet",
          text = "NEW BET",
          color = colors.orange,
        },
      },
    },
    center_x = floor(width / 2),
    button_y = metrics.footerButtonY,
    row_spacing = metrics.buttonRowSpacing,
    col_spacing = metrics.buttonColGap,
    inactivity_timeout = cfg.INACTIVITY_TIMEOUT,
    onTimeout = function()
      return "new_bet"
    end,
  })
end

local function applyChanges(candidateBets, changes)
  for _, change in ipairs(changes) do
    rouletteModel.addStake(candidateBets, change.region, change.amount)
  end
end

local function tryApplyAction(changes, successText, soundID)
  if not changes or #changes == 0 then
    sound.play(sound.SOUNDS.ERROR, 0.4)
    setStatus("Tap a number or color first.", "warning")
    return false
  end

  refreshPlayerState(true)

  local candidateBets = rouletteModel.cloneBetList(state.bets)
  applyChanges(candidateBets, changes)

  local ok, err = validateBetSet(candidateBets)
  if not ok then
    sound.play(sound.SOUNDS.ERROR, 0.4)
    setStatus(err, "error", 1800)
    return false
  end

  state.bets = candidateBets
  insert(state.betActions, { changes = changes })
  refreshDerivedState()
  setStatus(successText, "accent", 1200)
  sound.play(soundID or sound.SOUNDS.CARD_PLACE, 0.45)
  return true
end

local function undoLastAction()
  local lastAction = state.betActions[#state.betActions]
  if not lastAction then
    sound.play(sound.SOUNDS.ERROR, 0.4)
    setStatus("Nothing to undo.", "warning")
    return
  end

  local candidateBets = rouletteModel.cloneBetList(state.bets)
  local index = #lastAction.changes
  while index >= 1 do
    local change = lastAction.changes[index]
    rouletteModel.removeStake(candidateBets, change.region.key, change.amount)
    index = index - 1
  end

  state.bets = candidateBets
  table.remove(state.betActions)
  refreshDerivedState()
  sound.play(sound.SOUNDS.CLEAR, 0.45)
  setStatus("Removed the last placement.", "warning", 1200)
end

local function clearBets()
  if #state.bets == 0 then
    sound.play(sound.SOUNDS.ERROR, 0.4)
    setStatus("No chips to clear.", "warning")
    return
  end

  state.bets = {}
  state.betActions = {}
  refreshDerivedState()
  sound.play(sound.SOUNDS.CLEAR, 0.5)
  setStatus("Cleared the table.", "warning", 1200)
end

local function updatePassiveStatus(idleMs)
  local now = epoch("local")
  if now < (state.statusUntil or 0) then
    return
  end

  if state.phase == "spinning" then
    state.statusText = "Wheel spinning..."
    state.statusTone = "warning"
    return
  end

  if state.totalStake > 0 then
    state.statusText = "Press SPIN when you are ready."
    state.statusTone = "accent"
    return
  end

  local warningStart = cfg.INACTIVITY_TIMEOUT - 10000
  if idleMs and idleMs >= warningStart then
    local remainingMs = max(0, cfg.INACTIVITY_TIMEOUT - idleMs)
    local remainingSec = ceil(remainingMs / 1000)
    state.statusText = "Auto-exit in " .. tostring(remainingSec) .. "s."
    state.statusTone = "warning"
    return
  end

  state.statusText = "Pick a chip, then tap the table."
  state.statusTone = "neutral"
end

renderCurrent = function(idleMs)
  refreshDerivedState()
  updatePassiveStatus(idleMs)
  rouletteRender.draw(screen, font, layout, state)
end

local function hitRect(px, py, rect)
  return px >= rect.x and px <= (rect.x + rect.w - 1)
    and py >= rect.y and py <= (rect.y + rect.h - 1)
end

local function findTarget(px, py)
  for _, button in ipairs(layout.chipButtons) do
    if hitRect(px, py, button) then
      return "chip", button
    end
  end

  for _, button in ipairs(layout.actionButtons) do
    if hitRect(px, py, button) then
      return "action", button
    end
  end

  for _, region in ipairs(layout.hitRegions) do
    if hitRect(px, py, region) then
      return "region", region
    end
  end

  return nil, nil
end

local function buildHighlightKeys(bets, winningNumber)
  local keys = rouletteModel.getWinningKeysForOutcome(winningNumber)
  for _, bet in ipairs(bets) do
    if rouletteModel.doesBetWin(bet, winningNumber) then
      keys[bet.key] = true
    end
  end
  return keys
end

local function pushHistory(number)
  table.insert(state.history, 1, number)
  while #state.history > (cfg.HISTORY_LENGTH or 10) do
    table.remove(state.history)
  end
end

local function animateSpin(finalNumber)
  local wheelSize = #rouletteModel.WHEEL_ORDER
  local startOffset = state.wheelOffset or random(0, wheelSize - 1)
  local startIndex = floor(startOffset) % wheelSize
  local targetIndex = (rouletteModel.getWheelIndex(finalNumber) or 1) - 1
  local topAngle = -math.pi / 2
  local totalBallArc = (spinFullRotations + 5) * math.pi * 2
  local diff = targetIndex - startIndex
  while diff <= 0 do
    diff = diff + wheelSize
  end

  local totalSteps = diff + (wheelSize * spinFullRotations)
  local currentOffset = startOffset
  local step = 1
  local finalBounce = { 0.32, -0.14, 0.08, 0 }
  local lastPointedNumber = rouletteRender.getTrackPointedNumber(startOffset)

  state.phase = "spinning"
  state.highlightKeys = nil
  state.resultNumber = nil
  setStatus("Wheel spinning. Bets locked.", "warning", 900)

  while step <= totalSteps do
    local progress = step / totalSteps
    local delay = spinMinDelay + ((progress * progress) * (spinMaxDelay - spinMinDelay))
    local subframes = progress < spinSlowdownAt and spinFastSubframes or spinSlowSubframes
    local nextOffset = currentOffset + 1
    local subframe = 1

    while subframe <= subframes do
      local overallProgress = ((step - 1) + (subframe / subframes)) / totalSteps
      local remainingBallTravel = (1 - overallProgress) ^ 1.35
      local blended = currentOffset + (subframe / subframes)
      local pointedNumber = rouletteRender.getTrackPointedNumber(blended)
      if pointedNumber ~= nil and pointedNumber ~= lastPointedNumber then
        playSpinPointerClick(progress)
        lastPointedNumber = pointedNumber
      end
      state.wheelOffset = blended
      state.ballAngle = topAngle + (remainingBallTravel * totalBallArc)
      renderCurrent(nil)
      os.sleep(delay / subframes)
      subframe = subframe + 1
    end

    currentOffset = nextOffset

    if step >= totalSteps then
      playRouletteSound("SPIN_FINAL", sound.SOUNDS.START, 0.65)
    end

    step = step + 1
  end

  for _, bounceOffset in ipairs(finalBounce) do
    local bouncedOffset = targetIndex + bounceOffset
    local pointedNumber = rouletteRender.getTrackPointedNumber(bouncedOffset)
    if pointedNumber ~= nil and pointedNumber ~= lastPointedNumber then
      playSpinPointerClick(1)
      lastPointedNumber = pointedNumber
    end
    state.wheelOffset = bouncedOffset
    state.ballAngle = topAngle + (bounceOffset * 0.20)
    renderCurrent(nil)
    os.sleep(spinSettleDelay)
  end

  state.wheelOffset = targetIndex
  state.ballAngle = topAngle
  renderCurrent(nil)
end

local function settleRound()
  refreshPlayerState(true)
  local ok, err = validateBetSet(state.bets)
  if not ok then
    sound.play(sound.SOUNDS.ERROR, 0.4)
    setStatus(err, "error")
    return
  end

  local roundBets = rouletteModel.cloneBetList(state.bets)
  local totalStake = rouletteModel.getTotalStake(roundBets)
  state.phase = "spinning"
  recovery.saveSnapshot(totalStake, {
    phase = "spinning",
    bets = roundBets,
  })

  playRouletteSound("SPIN_START", sound.SOUNDS.START, 0.55)
  local winningNumber = rouletteModel.WHEEL_ORDER[random(1, #rouletteModel.WHEEL_ORDER)]
  animateSpin(winningNumber)

  local summary = rouletteModel.settleBets(roundBets, winningNumber)
  local reasonBase = "Roulette: " .. tostring(winningNumber) .. " " .. string.lower(summary.winningColor)

  if summary.net > 0 then
    local paid = settlement.applyNetChange(summary.net, {
      winReason = reasonBase .. " payout",
      failurePrefix = "CRITICAL",
    })
    if not paid then
      alert.send("CRITICAL: Roulette payout failed for " .. tostring(summary.net) .. " tokens")
      setStatus("Payout failed. Admin alerted.", "error", 3000)
    end
    playRouletteSound("RESULT_WIN", sound.SOUNDS.SUCCESS, 0.8)
  elseif summary.net < 0 then
    local charged = settlement.applyNetChange(summary.net, {
      lossReason = reasonBase .. " loss",
      failurePrefix = "CRITICAL",
    })
    if not charged then
      alert.send("CRITICAL: Roulette charge failed for " .. tostring(-summary.net) .. " tokens")
      setStatus("Charge failed. Admin alerted.", "error", 3000)
    end
    playRouletteSound("RESULT_LOSS", sound.SOUNDS.FAIL, 0.45)
  else
    playRouletteSound("RESULT_PUSH", sound.SOUNDS.PUSH or sound.SOUNDS.START, 0.4)
  end

  state.sessionProfit = state.sessionProfit + summary.net
  state.phase = "result"
  state.resultNumber = winningNumber
  state.highlightKeys = buildHighlightKeys(roundBets, winningNumber)
  pushHistory(winningNumber)
  refreshPlayerState(true)
  refreshDerivedState()

  if summary.net > 0 then
    setStatus(
      tostring(winningNumber) .. " " .. summary.winningColor .. "  " .. formatSignedTokens(summary.net),
      "success",
      floor(cfg.RESULT_PAUSE * 1000)
    )
  elseif summary.net < 0 then
    setStatus(
      tostring(winningNumber) .. " " .. summary.winningColor .. "  " .. formatSignedTokens(summary.net),
      "error",
      floor(cfg.RESULT_PAUSE * 1000)
    )
  else
    setStatus(
      tostring(winningNumber) .. " " .. summary.winningColor .. "  " .. formatSignedTokens(summary.net),
      "accent",
      floor(cfg.RESULT_PAUSE * 1000)
    )
  end

  renderCurrent(nil)
  os.sleep(cfg.RESULT_PAUSE)

  local replayChanges = copyReplayChanges(buildChangesFromBets(state.bets))
  local nextChoice = AUTO_PLAY and "play_again" or waitForReplayChoice(replayChanges)

  recovery.clearBet()
  if nextChoice == "play_again" and canReplayChanges(replayChanges) then
    state.bets = rebuildBetsFromChanges(replayChanges)
    state.betActions = {
      {
        changes = replayChanges,
      },
    }
    setStatus("Previous layout restored.", "accent", 1200)
  else
    state.bets = {}
    state.betActions = {}
  end
  state.highlightKeys = nil
  state.phase = "betting"
  refreshDerivedState()
end

local function handleActionButton(actionKey)
  if actionKey == "spin" then
    refreshPlayerState(true)
    local ok, err = validateBetSet(state.bets)
    if not ok then
      sound.play(sound.SOUNDS.ERROR, 0.4)
      setStatus(err, "error")
      return nil
    end
    return "spin"
  end

  if actionKey == "undo" then
    undoLastAction()
    return nil
  end

  if actionKey == "clear" then
    clearBets()
    return nil
  end

  if actionKey == "double" then
    if #state.bets == 0 then
      sound.play(sound.SOUNDS.ERROR, 0.4)
      setStatus("Place a bet before DOUBLE.", "warning")
      return nil
    end
    tryApplyAction(buildChangesFromBets(state.bets), "Added the same bets again.", sound.SOUNDS.ALL_IN)
    return nil
  end

  if actionKey == "quit" then
    sound.play(sound.SOUNDS.TIMEOUT, 0.45)
    os.sleep(0.3)
    error(cfg.EXIT_CODES.PLAYER_QUIT)
  end

  return nil
end

local function handleTouch(px, py)
  local sessionOk, sessionErr = validateCurrentSession()
  if not sessionOk then
    sound.play(sound.SOUNDS.ERROR, 0.45)
    setStatus(sessionErr, "error", 2000)
    return nil
  end

  local targetType, target = findTarget(px, py)
  if not targetType then
    return nil
  end

  if targetType == "chip" then
    local chipIndex = tonumber(string.match(target.key, "^chip:(%d+)$"))
    if chipIndex and currency.DENOMINATIONS[chipIndex] then
      state.selectedChipIndex = chipIndex
      playRouletteSound("CHIP_SELECT", currency.DENOMINATIONS[chipIndex].sound, 0.35)
      setStatus("Chip set to " .. currency.formatTokens(currency.DENOMINATIONS[chipIndex].value) .. ".", "accent", 900)
    end
    return nil
  end

  if targetType == "action" then
    return handleActionButton(target.key)
  end

  if targetType == "region" then
    local denomination = currency.DENOMINATIONS[state.selectedChipIndex] or currency.DENOMINATIONS[1]
    tryApplyAction({
      {
        region = target,
        amount = denomination.value,
      },
    }, "Placed " .. currency.formatTokens(denomination.value) .. " on " .. target.label .. ".", getBetPlacementSound(target))
  end

  return nil
end

local function runBettingLoop()
  local lastActivity = epoch("local")

  while true do
    refreshAutoPlay()
    refreshPlayerState(false)
    refreshDerivedState()

    if AUTO_PLAY then
      return "auto"
    end

    local idleMs = epoch("local") - lastActivity
    if idleMs > cfg.INACTIVITY_TIMEOUT then
      sound.play(sound.SOUNDS.TIMEOUT, 0.45)
      os.sleep(0.5)
      if state.totalStake > 0 then
        alert.log("Roulette timeout: auto-spin with " .. currency.formatTokens(state.totalStake) .. " on the table")
        return "spin"
      end
      error(cfg.EXIT_CODES.INACTIVITY_TIMEOUT)
    end

    state.phase = "betting"
    state.wheelOffset = (state.wheelOffset + 0.03) % #rouletteModel.WHEEL_ORDER
    renderCurrent(idleMs)

    local timerID = os.startTimer(0.20)
    local continueLoop = false

    while true do
      local event, param1, param2, param3 = os.pullEvent()

      if event == "monitor_touch" then
        local action = handleTouch(param2, param3)
        lastActivity = epoch("local")
        continueLoop = true
        if timerID then
          pcall(os.cancelTimer, timerID)
          timerID = nil
        end
        if action == "spin" then
          return "spin"
        end
        break
      end

      if event == "timer" and param1 == timerID then
        timerID = nil
        break
      end

      if event == "term_resize" then
        continueLoop = true
        if timerID then
          pcall(os.cancelTimer, timerID)
          timerID = nil
        end
        break
      end
    end

    if continueLoop then
      os.sleep(0)
    end
  end
end

local function runAutoRound()
  refreshPlayerState(true)
  refreshDerivedState()

  state.phase = "betting"
  state.bets = {}
  state.betActions = {}
  refreshDerivedState()

  local autoStake = min(cfg.AUTO_PLAY_BET, state.playerBalance)
  if autoStake <= 0 then
    setStatus("Auto play waiting for tokens.", "warning", 1200)
    renderCurrent(nil)
    os.sleep(1)
    return
  end

  local attempt = 1
  while attempt <= 25 do
    local region = layout.regions[random(1, #layout.regions)]
    local candidateBets = {}
    rouletteModel.addStake(candidateBets, region, autoStake)
    local ok = validateBetSet(candidateBets)
    if ok then
      state.bets = candidateBets
      state.betActions = {
        {
          changes = {
            {
              region = region,
              amount = autoStake,
            },
          },
        },
      }
      refreshDerivedState()
      setStatus("Auto: " .. region.label .. " for " .. currency.formatTokens(autoStake) .. ".", "accent", 900)
      renderCurrent(nil)
      os.sleep(cfg.AUTO_PLAY_DELAY)
      settleRound()
      return
    end
    attempt = attempt + 1
  end

  setStatus("Auto play found no safe table.", "warning", 1200)
  renderCurrent(nil)
  os.sleep(1)
end

local function main()
  dbg("Roulette starting")
  randomseed(epoch("local"))
  state.wheelOffset = random(0, #rouletteModel.WHEEL_ORDER - 1)

  refreshPlayerState(true)
  refreshDerivedState()
  recovery.recoverBet(true)

  while true do
    refreshAutoPlay()
    if AUTO_PLAY then
      runAutoRound()
    else
      local action = runBettingLoop()
      if action == "spin" then
        settleRound()
      end
    end
    os.sleep(0)
  end
end

sound.play(sound.SOUNDS.BOOT, 0.5)
safeRunner.run(main)
