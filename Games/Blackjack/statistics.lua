-- statistics.lua
-- Blackjack Statistics — thin wrapper.
-- Delegates persistence to lib/player_stats, achievement checks to lib/achievements,
-- and UI screens to stats_ui.  This file owns processGameResult / recordGameResult
-- and the module init glue.
--
-- Module return API is unchanged:
--   { version, init, getActivePlayer, loadPlayerStats, savePlayerStats,
--     recordGameResult, ACHIEVEMENTS, showAchievementsBrowser, showStatisticsMenu }

local version = "2.0.0"
print("Blackjack Statistics v" .. version .. " starting...")

-----------------------------------------------------
-- Shared library imports
-----------------------------------------------------
local peripheralsLib = require("lib.peripherals")
local alertLib       = require("lib.alert")
local playerDetLib   = require("lib.player_detection")
local pStats         = require("lib.player_stats")
local achLib         = require("lib.achievements")
local cfg            = require("blackjack_config")
local OUT            = cfg.OUTCOMES

-- Lazy-load stats_ui only when actually needed
local statsUI = nil
local function getStatsUI()
  if not statsUI then statsUI = require("stats_ui") end
  return statsUI
end

-----------------------------------------------------
-- Alert / logging
-----------------------------------------------------
alertLib.configure({
  gameName  = "Blackjack Stats",
  logFile   = "statistics_error.log",
})
alertLib.addPlannedExits({
  "inactivity_timeout", "main_menu", "user_terminated", "keyboard_interrupt",
})
-- playerDet.init() is called by game_setup when used via blackjack.lua;
-- standalone launches should call playerDetLib.init(10) in their own setup.

local LOG_FILE = "statistics_log.txt"
local function writeLog(message)
  local file = fs.open(LOG_FILE, "a")
  if file then
    file.writeLine(os.date() .. ": " .. message)
    file.close()
  end
end

local function sendAdminAlert(errorMsg)
  writeLog("ERROR: " .. errorMsg)
  alertLib.send(errorMsg)
end

-----------------------------------------------------
-- Player detection (delegates to shared library)
-----------------------------------------------------
local getActivePlayer = playerDetLib.getActive



-----------------------------------------------------
-- Init
-----------------------------------------------------
local function init()
  pStats.init()
  writeLog("Statistics module initialized successfully")
  return true
end

-----------------------------------------------------
-- Convenience re-exports
-----------------------------------------------------
local loadPlayerStats   = pStats.loadPlayerStats
local savePlayerStats   = pStats.savePlayerStats
local ACHIEVEMENTS      = achLib.ACHIEVEMENTS
local checkAchievements = achLib.checkAchievements

-----------------------------------------------------
-- processGameResult — the core stat update engine
-----------------------------------------------------
local function processGameResult(playerName, gameResult)
  if not playerName or not gameResult then
    writeLog("Invalid parameters to processGameResult")
    return nil
  end

  -- Validate required GameResult fields before touching stats
  local outcome = gameResult.outcome
  if type(outcome) ~= "string" or outcome == "" then
    writeLog("Rejected GameResult: missing or empty outcome")
    return nil
  end

  local VALID_OUTCOMES = {
    [OUT.PLAYER_WIN] = true, [OUT.DEALER_WIN] = true,
    [OUT.BLACKJACK]  = true, [OUT.BUST]       = true, [OUT.PUSH] = true,
  }
  if not VALID_OUTCOMES[outcome] then
    writeLog("Rejected GameResult: unknown outcome '" .. tostring(outcome) .. "'")
    return nil
  end

  if type(gameResult.bet) ~= "number" or gameResult.bet < 0 then
    writeLog("Rejected GameResult: invalid bet '" .. tostring(gameResult.bet) .. "'")
    return nil
  end

  local stats = loadPlayerStats(playerName)
  if not stats then
    stats = pStats.defaultStats(playerName)
  end

  -- Ensure sub-tables exist (forward-compat for old save files)
  if not stats.actions then
    stats.actions = {
      hit = { total = 0, outcomes = {} },
      stand = { total = 0, outcomes = {} },
      double = { total = 0, outcomes = {} },
      split = { total = 0, outcomes = {} },
    }
  end
  if not stats.dealer then stats.dealer = { upCardOutcomes = {} } end
  if not stats.cards  then stats.cards  = { twentyOneWith = { ["3cards"] = 0, ["4cards"] = 0, ["5+cards"] = 0 } } end
  if not stats.timing then stats.timing = { startTimes = {}, decisionTimes = {} } end
  if not stats.timing.startTimes then stats.timing.startTimes = {} end
  if not stats.timing.decisionTimes then stats.timing.decisionTimes = {} end
  if not stats.achievements then stats.achievements = {} end

  stats.lastUpdated = os.epoch("local")
  stats.gamesPlayed = (stats.gamesPlayed or 0) + 1
  stats.sessionHandsPlayed = (stats.sessionHandsPlayed or 0) + 1

  -- Hour tracking
  local currentHour = tonumber(os.date("%H"))
  stats.timing.startTimes[currentHour] = (stats.timing.startTimes[currentHour] or 0) + 1

  -- Weekend
  local dayOfWeek = os.date("*t").wday
  if dayOfWeek == 1 or dayOfWeek == 7 or (dayOfWeek == 6 and os.date("*t").hour >= 18) then
    stats.playedOnWeekend = 1
  end

  -- Unique days
  local today = os.day()
  if not stats.days then stats.days = {} end
  if not stats.days[today] then
    stats.days[today] = true
    stats.uniqueDaysPlayed = (stats.uniqueDaysPlayed or 0) + 1
  end

  -- Decision time
  if gameResult.decisionTime and gameResult.decisionTime > 0 then
    table.insert(stats.timing.decisionTimes, gameResult.decisionTime / 1000)
  end

  -- Session time
  local currentTime = os.epoch("local")
  if stats.sessionStartTime then
    stats.totalPlayTime = (stats.totalPlayTime or 0) + ((currentTime - stats.sessionStartTime) / 1000)
  end
  stats.sessionStartTime = currentTime
  if gameResult.handDuration then
    stats.sessionTime = (stats.sessionTime or 0) + gameResult.handDuration
  end

  -----------------------------------------------
  -- Outcome processing
  -----------------------------------------------
  local isWin  = outcome == OUT.PLAYER_WIN or outcome == OUT.BLACKJACK
  local isLoss = outcome == OUT.DEALER_WIN  or outcome == OUT.BUST
  local isPush = outcome == OUT.PUSH

  -- Capture previous streak state BEFORE updating (for comeback/streak-break checks)
  local prevLoseStreak = stats.loseStreak or 0
  local prevWinStreak  = stats.winStreak  or 0

  if outcome == OUT.PLAYER_WIN then
    stats.wins = (stats.wins or 0) + 1
    stats.winStreak = (stats.winStreak or 0) + 1
    stats.loseStreak = 0
    stats.consecutiveBlackjacks = 0

    if gameResult.dealerBusted       then stats.dealerBustWins      = (stats.dealerBustWins or 0) + 1 end
    if gameResult.hasSoftHand        then stats.softHandWins        = (stats.softHandWins or 0) + 1 end
    if gameResult.hasSevenCard       then stats.wonWithSeven        = (stats.wonWithSeven or 0) + 1 end
    if gameResult.allBlackCards      then stats.blackCardWins       = (stats.blackCardWins or 0) + 1 end
    if gameResult.allRedCards        then stats.redCardWins         = (stats.redCardWins or 0) + 1 end
    if gameResult.clubCount == 4     then stats.fourClubWins        = (stats.fourClubWins or 0) + 1 end
    if gameResult.isMaxBet           then stats.maxBetWins          = (stats.maxBetWins or 0) + 1 end

    if stats.lastOutcome == "loss" and gameResult.bet == (stats.lastBet or 0) * 2 then
      stats.betDoublingWins = (stats.betDoublingWins or 0) + 1
    end

  elseif outcome == OUT.BLACKJACK then
    stats.wins = (stats.wins or 0) + 1
    stats.blackjacks = (stats.blackjacks or 0) + 1
    stats.sessionBlackjacks = (stats.sessionBlackjacks or 0) + 1
    stats.winStreak = (stats.winStreak or 0) + 1
    stats.loseStreak = 0
    stats.consecutiveBlackjacks = (stats.consecutiveBlackjacks or 0) + 1
    if gameResult.allBlackCards then stats.blackCardWins = (stats.blackCardWins or 0) + 1 end
    if gameResult.allRedCards   then stats.redCardWins   = (stats.redCardWins or 0) + 1 end
    if gameResult.isMaxBet      then stats.maxBetWins    = (stats.maxBetWins or 0) + 1 end

  elseif outcome == OUT.DEALER_WIN then
    stats.losses = (stats.losses or 0) + 1
    stats.loseStreak = (stats.loseStreak or 0) + 1
    stats.winStreak = 0
    stats.consecutiveBlackjacks = 0
    if gameResult.lost666 then stats.lost666 = (stats.lost666 or 0) + 1 end

  elseif outcome == OUT.BUST then
    stats.losses = (stats.losses or 0) + 1
    stats.busts = (stats.busts or 0) + 1
    stats.loseStreak = (stats.loseStreak or 0) + 1
    stats.winStreak = 0
    stats.consecutiveBlackjacks = 0

  elseif outcome == OUT.PUSH then
    stats.pushes = (stats.pushes or 0) + 1
    stats.consecutiveBlackjacks = 0

    -- Double blackjack
    local hs = gameResult.handScore or 0
    local cc = gameResult.cardCount or 0
    local ds = gameResult.dealerScore or 0
    local dc = gameResult.dealerCardCount or 0
    if hs == 21 and cc == 2 and ds == 21 and dc == 2 then
      stats.doubleBlackjacks = (stats.doubleBlackjacks or 0) + 1
    end
  end

  -----------------------------------------------
  -- Achievement-flag population (table-driven)
  -----------------------------------------------
  local FLAG_TO_STAT = {
    isSevenCardCharlie = "sevenCardCharlies",
    isRainbowWin       = "rainbowWins",
    isSoft21Win        = "soft21Wins",
    isEdgeOutWin       = "edgeOutWins",
    isFiveClubWin      = "fiveClubWins",
    isHoudini          = "houdiniWins",
    isShutout          = "shutoutWins",
    isRiskyDouble      = "riskyDoubleWins",
    isOverkill         = "overkillWins",
    isSnapDecision     = "snapDecisionWins",
    isSlowBurn         = "slowBurnWins",
    isStonewall        = "stonewallPushes",
    isQuickHand        = "quickHandWins",
    isAllRedLoss       = "redCardsLoss",
    isMirrorMatch      = "mirrorMatches",
    isQuadAce          = "quadAceWins",
    isBankBuster       = "bankBuster",
    isPerfectPair      = "perfectPairs",
    isTwinBlackjack    = "twinBlackjacks",
    isPrecisionSplit   = "precisionSplits",
  }
  for grKey, statKey in pairs(FLAG_TO_STAT) do
    if gameResult[grKey] then
      stats[statKey] = (stats[statKey] or 0) + 1
    end
  end

  -- Streak-dependent flags (use PREVIOUS streaks captured above)
  if gameResult.isStreakBreaker == nil then
    -- Auto-compute: push that ended a 4+ win or loss streak
    if isPush and (prevWinStreak >= 4 or prevLoseStreak >= 4) then
      stats.streakBreakers = (stats.streakBreakers or 0) + 1
    end
  elseif gameResult.isStreakBreaker then
    stats.streakBreakers = (stats.streakBreakers or 0) + 1
  end

  if gameResult.isComebackKid == nil then
    -- Auto-compute: win immediately after 3+ straight losses
    if isWin and prevLoseStreak >= 3 then
      stats.comebackKidWins = (stats.comebackKidWins or 0) + 1
    end
  elseif gameResult.isComebackKid then
    stats.comebackKidWins = (stats.comebackKidWins or 0) + 1
  end

  -- Split stats (isPerfectPair, isTwinBlackjack, isPrecisionSplit handled by FLAG_TO_STAT above)
  if gameResult.splitCount and gameResult.splitCount > 0 then
    stats.splitCount = (stats.splitCount or 0) + gameResult.splitCount
  end
  if gameResult.splitWins then stats.splitWins = (stats.splitWins or 0) + gameResult.splitWins end

  -- Insurance / surrender
  if gameResult.insurancePaid and gameResult.insurancePaid > 0 then
    stats.insuranceCount = (stats.insuranceCount or 0) + 1
    stats.insurancePaid  = (stats.insurancePaid or 0) + gameResult.insurancePaid
  end
  if gameResult.insuranceWon and gameResult.insuranceWon > 0 then
    stats.insuranceWon = (stats.insuranceWon or 0) + gameResult.insuranceWon
  end
  if gameResult.surrendered then
    stats.surrenderCount = (stats.surrenderCount or 0) + 1
  end

  -- Low-bet win streak
  if isWin and gameResult.bet and gameResult.bet <= 1 then
    stats.lowBetWinStreak = (stats.lowBetWinStreak or 0) + 1
  else
    stats.lowBetWinStreak = 0
  end

  -----------------------------------------------
  -- Bet tracking
  -----------------------------------------------
  local bet = gameResult.bet or 0
  stats.totalBet = (stats.totalBet or 0) + bet

  if not stats.lastBet then
    stats.sameBetStreak = 1; stats.lastBet = bet
  elseif stats.lastBet == bet then
    stats.sameBetStreak = (stats.sameBetStreak or 1) + 1
  else
    stats.sameBetStreak = 1; stats.lastBet = bet
  end

  stats.averageBet = stats.totalBet / stats.gamesPlayed
  if bet > (stats.biggestBet or 0) then stats.biggestBet = bet end

  -----------------------------------------------
  -- Money tracking
  -----------------------------------------------
  local netChange = gameResult.netChange or 0
  if netChange > (stats.biggestWin or 0) then stats.biggestWin = netChange end
  if netChange > 0 then
    stats.totalWinnings = (stats.totalWinnings or 0) + netChange
  elseif netChange < 0 then
    stats.totalLosses = (stats.totalLosses or 0) - netChange
  end
  stats.netProfit = (stats.netProfit or 0) + netChange
  if not stats.lowestNetProfit or stats.netProfit < stats.lowestNetProfit then
    stats.lowestNetProfit = stats.netProfit
  end

  -- Leaderboard
  pStats.updateLeaderboard(playerName, stats)

  -----------------------------------------------
  -- Action-outcome matrix
  -----------------------------------------------
  local action   = gameResult.actions
  local handScore = gameResult.handScore

  if action and action ~= "" then
    if not stats.actions[action] then
      stats.actions[action] = { total = 0, outcomes = {} }
    end
    stats.actions[action].total = (stats.actions[action].total or 0) + 1

    local scoreKey = tostring(handScore)
    if not stats.actions[action].outcomes[scoreKey] then
      stats.actions[action].outcomes[scoreKey] = { win = 0, loss = 0, push = 0 }
    end
    local bucket = stats.actions[action].outcomes[scoreKey]
    if isWin  then bucket.win  = (bucket.win or 0) + 1
    elseif isLoss then bucket.loss = (bucket.loss or 0) + 1
    elseif isPush then bucket.push = (bucket.push or 0) + 1 end
  end

  -- Dealer up-card matrix
  local dealerUpCard = gameResult.dealerUpCard
  if dealerUpCard and dealerUpCard ~= "" then
    if not stats.dealer.upCardOutcomes[dealerUpCard] then
      stats.dealer.upCardOutcomes[dealerUpCard] = { win = 0, loss = 0, push = 0 }
    end
    local dBucket = stats.dealer.upCardOutcomes[dealerUpCard]
    if isWin  then dBucket.win  = (dBucket.win or 0) + 1
    elseif isLoss then dBucket.loss = (dBucket.loss or 0) + 1
    elseif isPush then dBucket.push = (dBucket.push or 0) + 1 end
  end

  -----------------------------------------------
  -- Card-count specials
  -----------------------------------------------
  if not stats.cards.twentyOneWith then stats.cards.twentyOneWith = {} end
  if (handScore or 0) == 21 then
    local cc = gameResult.cardCount or 0
    if cc == 3 then
      stats.cards.twentyOneWith["3cards"] = (stats.cards.twentyOneWith["3cards"] or 0) + 1
    elseif cc == 4 then
      stats.cards.twentyOneWith["4cards"] = (stats.cards.twentyOneWith["4cards"] or 0) + 1
    elseif cc >= 5 then
      stats.cards.twentyOneWith["5+cards"] = (stats.cards.twentyOneWith["5+cards"] or 0) + 1
      if gameResult.isFiveCard21 then stats.fiveCard21s = (stats.fiveCard21s or 0) + 1 end
    end
  end

  if gameResult.tripleHitSuccess then
    stats.tripleHitSuccess = (stats.tripleHitSuccess or 0) + 1
  end

  -- Remember last outcome for martingale tracking
  if isWin  then stats.lastOutcome = "win"
  elseif isLoss then stats.lastOutcome = "loss"
  else stats.lastOutcome = "push" end

  -----------------------------------------------
  -- Save + check achievements
  -----------------------------------------------
  savePlayerStats(playerName, stats)
  local newAchievements = checkAchievements(stats)

  -- Track session achievement rewards
  if newAchievements and #newAchievements > 0 then
    local reward = 0
    for _, ach in ipairs(newAchievements) do
      reward = reward + (ach.rewardGold or 0) * 9
    end
    stats.sessionAchievementRewards = (stats.sessionAchievementRewards or 0) + reward
    savePlayerStats(playerName, stats)
  end

  return { stats = stats, newAchievements = newAchievements }
end

-----------------------------------------------------
-- recordGameResult — safe pcall wrapper
-----------------------------------------------------
local function recordGameResult(playerName, gameResult)
  local success, result = pcall(processGameResult, playerName, gameResult)
  if not success then
    writeLog("Error processing game result: " .. tostring(result))
    sendAdminAlert("Error recording game result: " .. tostring(result))
    return nil
  end
  return result
end

-----------------------------------------------------
-- Module interface
-----------------------------------------------------
local module = {
  version                = version,
  init                   = init,
  getActivePlayer        = getActivePlayer,
  loadPlayerStats        = loadPlayerStats,
  savePlayerStats        = savePlayerStats,
  recordGameResult       = recordGameResult,
  ACHIEVEMENTS           = ACHIEVEMENTS,
  showAchievementsBrowser = function() return getStatsUI().showAchievementsBrowser() end,
  showStatisticsMenu      = function() return getStatsUI().showStatisticsMenu() end,
}

-- If loaded as a module, return the interface
if ... then
  return module
end

-- If run directly, show the statistics menu
local ok, err = pcall(function()
  getStatsUI().showStatisticsMenu()
end)

if not ok then
  if err == "Terminated" then
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
  else
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    term.write("Error: " .. tostring(err))
    writeLog("Error running statistics menu: " .. tostring(err))
    sendAdminAlert("Statistics UI crashed: " .. tostring(err))
    print("\nPress any key to exit")
    os.pullEvent("key")
  end
end
