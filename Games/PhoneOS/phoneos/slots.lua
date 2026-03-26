local currency = require("lib.currency")
local sound    = require("lib.sound")
local alert    = require("lib.alert")
local recovery = require("lib.crash_recovery")

local M = {}

local function symbolBox(ui, x, y, width, label, bg, fg)
  ui.writeAt(x, y, "+" .. string.rep("-", width - 2) .. "+", fg or colors.white, bg)
  ui.writeAt(x, y + 1, "|" .. string.rep(" ", width - 2) .. "|", fg or colors.white, bg)
  ui.writeAt(x, y + 2, "|" .. string.rep(" ", width - 2) .. "|", fg or colors.white, bg)
  ui.writeAt(x, y + 3, "+" .. string.rep("-", width - 2) .. "+", fg or colors.white, bg)

  local shown = tostring(label or ""):sub(1, width - 2)
  local textX = x + math.floor((width - #shown) / 2)
  ui.writeAt(textX, y + 1, shown, fg or colors.white, bg)
end

local function drawMachine(env, result, statusText, bet, opts)
  opts = opts or {}
  local ui = env.ui
  local theme = ui.theme or {}
  local session = env.refreshSession()
  local width = select(1, term.getSize())
  local reelWidth = 7
  local gap = 1
  local totalWidth = reelWidth * 3 + gap * 2
  local startX = math.max(1, math.floor((width - totalWidth) / 2) + 1)

  ui.clear(colors.black)
  ui.header("Slots", "Bet " .. currency.formatTokens(bet), session.status)

  symbolBox(ui, startX, 6, reelWidth, result[1].label, theme.chromeBg or colors.gray, colors.white)
  symbolBox(ui, startX + reelWidth + gap, 6, reelWidth, result[2].label, theme.chromeBg or colors.gray, colors.white)
  symbolBox(ui, startX + (reelWidth + gap) * 2, 6, reelWidth, result[3].label, theme.chromeBg or colors.gray, colors.white)

  if statusText then
    local lines = {}

    local function appendStatus(entry)
      if type(entry) == "table" then
        local wrapped = ui.wrap(entry.text or "", 22)
        for _, line in ipairs(wrapped) do
          lines[#lines + 1] = {
            text = line,
            color = entry.color or colors.white,
            bg = entry.bg,
          }
        end
      else
        local wrapped = ui.wrap(entry or "", 22)
        for _, line in ipairs(wrapped) do
          lines[#lines + 1] = {
            text = line,
            color = colors.white,
          }
        end
      end
    end

    if type(statusText) == "table" then
      for _, entry in ipairs(statusText) do
        appendStatus(entry)
      end
    else
      appendStatus(statusText)
    end

    local statusY = opts.statusY or 12
    for i, line in ipairs(lines) do
      ui.writeAt(2, statusY + i - 1, line.text, line.color, line.bg)
    end
  end

  if opts.centerBanners then
    for _, banner in ipairs(opts.centerBanners) do
      local shown = " " .. tostring(banner.text or "") .. " "
      ui.center(banner.y or 15, shown, banner.color or colors.white, banner.bg)
    end
  end

  ui.writeAt(2, 17, opts.primaryAction or "Enter spin", opts.primaryColor or colors.lime)
  ui.writeAt(14, 17, opts.secondaryAction or "Back exit", opts.secondaryColor or colors.white)
  ui.footer(opts.footer or (session.selfPlay and "Self-pay mode" or (env.isLiveSession(session) and "Live mode" or "Wallet locked")))
end

local function buildReel(symbols)
  local reel = {}
  for _, symbol in ipairs(symbols) do
    for _ = 1, symbol.weight do
      reel[#reel + 1] = symbol
    end
  end
  for i = #reel, 2, -1 do
    local j = math.random(i)
    reel[i], reel[j] = reel[j], reel[i]
  end
  return reel
end

local function spinReel(reel)
  return reel[math.random(1, #reel)]
end

local function evaluateResult(cfg, result, bet)
  local one = result[1].id
  local two = result[2].id
  local three = result[3].id

  if one == two and two == three then
    local mult = cfg.PAYOUTS[one] or 2
    return math.max(0, bet * (mult - 1)), "Triple " .. result[1].label, one == "7", mult == 1
  end

  local pairs = {}
  if one == two then pairs[#pairs + 1] = one end
  if one == three then pairs[#pairs + 1] = one end
  if two == three then pairs[#pairs + 1] = two end

  if #pairs > 0 then
    local symbolId = pairs[1]
    local mult = (cfg.TWO_OF_A_KIND_PAYOUTS or {})[symbolId] or 0
    if mult > 0 then
      local winnings = math.max(0, bet * (mult - 1))
      return winnings, "Two " .. symbolId .. "s!", false, mult == 1
    end
  end

  local cherries = 0
  if one == "cherry" then cherries = cherries + 1 end
  if two == "cherry" then cherries = cherries + 1 end
  if three == "cherry" then cherries = cherries + 1 end
  if cherries >= 2 and cfg.ANY_TWO_CHERRY_MULT > 0 then
    return math.max(0, bet * (cfg.ANY_TWO_CHERRY_MULT - 1)), "Cherries!", false, cfg.ANY_TWO_CHERRY_MULT == 1
  end

  return 0, nil, false, false
end

local function getHostMaxBet(env, session)
  local hostBalance = session.hostBalance or currency.getHostBalance()
  local maxBet = math.floor((hostBalance or 0) * env.slotsConfig.MAX_BET_PERCENT)
  if env.slotsConfig.HOST_COVERAGE_MULT > 1 then
    maxBet = math.min(maxBet, math.floor((hostBalance or 0) / (env.slotsConfig.HOST_COVERAGE_MULT - 1)))
  end
  return math.max(0, maxBet)
end

local function getReplayCap(env, session)
  return math.max(0, math.min(getHostMaxBet(env, session), session.playerBalance or 0))
end

local function promptSlotsBet(env, initial)
  local session = env.refreshSession()
  return env.promptBet({
    title = "Slots Bet",
    subtitle = session.selfPlay and "Self-pay spin" or "Live spin",
    maxBet = getHostMaxBet(env, session),
    liveMode = env.isLiveSession(session),
    initial = initial,
  })
end

local function waitForReplayKeyRelease()
  local releaseTimer = os.startTimer(0.2)

  while true do
    local event, key = os.pullEvent()
    if event == "key_up" and key == keys.r then
      return
    end
    if event == "timer" and key == releaseTimer then
      return
    end
  end
end

local function waitForReplay(env, result, summary, bet, outcomeState)
  local ui = env.ui
  local theme = ui.theme or {}
  local summaryColor = colors.red
  if outcomeState == "win" then
    summaryColor = colors.lime
  elseif outcomeState == "push" then
    summaryColor = theme.rule or colors.lightBlue
  end

  drawMachine(env, result, {
    {
      text = summary,
      color = summaryColor,
    },
    {
      text = "Result: " .. result[1].label .. " | " .. result[2].label .. " | " .. result[3].label,
      color = theme.subtitle or colors.lightGray,
    },
  }, bet, {
    centerBanners = {
      {
        y = 15,
        text = "PRESS R TO",
        color = colors.white,
        bg = theme.rule or colors.lightBlue,
      },
      {
        y = 16,
        text = "ROLL AGAIN",
        color = colors.white,
        bg = theme.accent or colors.magenta,
      },
    },
    primaryAction = "R replay",
    primaryColor = theme.accent or colors.magenta,
    secondaryAction = "Back exit",
    secondaryColor = colors.white,
    footer = "R roll again  Back exit",
  })

  while true do
    local _, key = os.pullEvent("key")
    if key == keys.r then
      waitForReplayKeyRelease()
      return "replay"
    elseif key == keys.backspace or key == keys.h then
      return "exit"
    end
  end
end

function M.run(env)
  local function runInternal()
    recovery.configure(fs.combine(env.dataDir, "phone_slots_recovery.dat"))
    recovery.recoverBet(false)

    if not env.ensureAuthenticated("Slots needs wallet approval.") then
      return
    end

    local session = env.refreshSession()
    recovery.setGame("Pocket Slots")
    recovery.setPlayer(session.playerName or "Unknown")

    local currentBet = promptSlotsBet(env)
    if not currentBet or currentBet <= 0 then
      return
    end

    local instantReplay = false
    local openingDisplay = nil

    while currentBet and currentBet > 0 do
      session = env.refreshSession()
      local liveMode = env.isLiveSession(session)
      if not liveMode then
        env.showMessage("Slots Locked", {
          "This wallet session is no longer approved for another spin.",
        }, { status = session.status })
        return
      end

      recovery.saveBet(currentBet, "spin")

      local reels = {
        buildReel(env.slotsConfig.SYMBOLS),
        buildReel(env.slotsConfig.SYMBOLS),
        buildReel(env.slotsConfig.SYMBOLS),
      }

      local display = openingDisplay or {
        env.slotsConfig.SYMBOLS[1],
        env.slotsConfig.SYMBOLS[2],
        env.slotsConfig.SYMBOLS[3],
      }
      openingDisplay = nil

      if not instantReplay then
        drawMachine(env, display, "Press Enter to spin the reels.", currentBet)
        while true do
          local _, key = os.pullEvent("key")
          if key == keys.backspace or key == keys.h then
            recovery.clearBet()
            return
          elseif key == keys.enter then
            break
          end
        end
      end
      instantReplay = false

      local result = {
        spinReel(reels[1]),
        spinReel(reels[2]),
        spinReel(reels[3]),
      }

      if env.settings.animations then
        for tick = 1, env.slotsConfig.REEL_SPIN_TICKS[3] do
          for reelIndex = 1, 3 do
            if tick < env.slotsConfig.REEL_SPIN_TICKS[reelIndex] then
              display[reelIndex] = spinReel(reels[reelIndex])
            else
              display[reelIndex] = result[reelIndex]
            end
          end
          drawMachine(env, display, "Spinning...", currentBet)
          os.sleep(env.slotsConfig.SPIN_FRAME_DELAY)
        end
      end

      local winAmount, label, isJackpot, isPush = evaluateResult(env.slotsConfig, result, currentBet)
      local summary
      local outcomeState

      if isPush then
        summary = "Push: " .. tostring(label or "Pair")
        outcomeState = "push"
        env.playSound(sound.SOUNDS.PUSH, 0.5)
      elseif winAmount > 0 then
        if liveMode then
          local okPayout = currency.payout(winAmount, session.selfPlay and "phone slots self-pay win" or (isJackpot and "phone slots jackpot" or "phone slots win"))
          if not okPayout then
            error("Failed to pay slot winnings")
          end
        end
        summary = "Win: " .. currency.formatTokens(winAmount) .. " (" .. label .. ")"
        outcomeState = "win"
        env.playSound(sound.SOUNDS.SUCCESS, isJackpot and 1.0 or 0.6)
      else
        if liveMode then
          local okCharge = currency.charge(currentBet, session.selfPlay and "phone slots self-pay loss" or "phone slots loss")
          if not okCharge then
            error("Failed to charge slot loss")
          end
        end
        summary = "Loss: no payout"
        outcomeState = "loss"
        env.playSound(sound.SOUNDS.FAIL, 0.5)
      end

      recovery.clearBet()

      local modeTag = session.selfPlay and "self-pay" or "live"
      local messageLevel = outcomeState == "loss" and "warn" or "info"
      env.addMessage("Slots", summary .. " (" .. modeTag .. ")", messageLevel)

      if waitForReplay(env, result, summary, currentBet, outcomeState) ~= "replay" then
        return
      end

      local replaySession = env.refreshSession()
      local replayCap = getReplayCap(env, replaySession)
      if replayCap >= currentBet then
        instantReplay = true
        openingDisplay = result
      elseif replayCap > 0 then
        env.showMessage("Replay Adjusted", {
          "That bet is no longer available.",
          "Pick a new bet to keep spinning.",
        }, { status = replaySession.status })
        currentBet = promptSlotsBet(env, replayCap)
      else
        env.showMessage("Replay Locked", {
          "There is not enough balance for another spin right now.",
        }, { status = replaySession.status })
        return
      end
    end
  end

  local ok, err = pcall(runInternal)
  if not ok then
    alert.log("Pocket slots error: " .. tostring(err))
    recovery.recoverBet(false)
    env.addMessage("Slots Error", tostring(err), "error")
    env.showMessage("Slots Error", {
      tostring(err),
    }, { status = env.refreshSession().status })
  end
end

return M
