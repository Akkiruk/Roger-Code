-- player_stats.lua
-- Player statistics persistence and leaderboard management.
-- Extracted from statistics.lua for modularity.

local STATS_DIR        = "player_stats"
local LEADERBOARD_FILE = "leaderboard.dat"

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[player_stats] " .. msg) end
end

local LOG_FILE = "statistics_log.txt"
local function writeLog(message)
  local file = fs.open(LOG_FILE, "a")
  if file then
    file.writeLine(os.date() .. ": " .. message)
    file.close()
  end
end

-----------------------------------------------------
-- Initialization
-----------------------------------------------------
local function init()
  if not fs.exists(STATS_DIR) then
    fs.makeDir(STATS_DIR)
    dbg("Created stats directory")
  end
  if not fs.exists(LEADERBOARD_FILE) then
    local lb = {
      lastUpdated   = os.epoch("local"),
      topWins       = {},
      topProfit     = {},
      topBets       = {},
      topBlackjacks = {},
    }
    local f = fs.open(LEADERBOARD_FILE, "w")
    if f then
      f.write(textutils.serialize(lb))
      f.close()
    end
  end
  writeLog("Player stats module initialized")
  return true
end

-----------------------------------------------------
-- Default stats template (full schema)
-----------------------------------------------------
local function defaultStats(playerName)
  return {
    playerName           = playerName,
    gamesPlayed          = 0,
    wins                 = 0,
    losses               = 0,
    pushes               = 0,
    blackjacks           = 0,
    busts                = 0,
    totalBet             = 0,
    totalWinnings        = 0,
    totalLosses          = 0,
    biggestWin           = 0,
    biggestBet           = 0,
    netProfit            = 0,
    achievements         = {},
    -- Streaks
    winStreak            = 0,
    loseStreak           = 0,
    consecutiveBlackjacks = 0,
    sameBetStreak        = 0,
    -- Session
    sessionHandsPlayed   = 0,
    sessionBlackjacks    = 0,
    sessionStartTime     = nil,
    sessionAchievementRewards = 0,
    sessionTime          = 0,
    -- Special counters
    betDoublingWins      = 0,
    fiveCard21s          = 0,
    doubleBlackjacks     = 0,
    tripleHitSuccess     = 0,
    softHandWins         = 0,
    dealerBustWins       = 0,
    wonWithSeven         = 0,
    lost666              = 0,
    blackCardWins        = 0,
    redCardWins          = 0,
    fourClubWins         = 0,
    maxBetWins           = 0,
    uniqueDaysPlayed     = 0,
    playedOnWeekend      = 0,
    totalPlayTime        = 0,
    averageBet           = 0,
    lowestNetProfit      = 0,
    lastBet              = nil,
    lastOutcome          = nil,
    -- New feature counters
    sevenCardCharlies    = 0,
    rainbowWins          = 0,
    soft21Wins           = 0,
    edgeOutWins          = 0,
    fiveClubWins         = 0,
    houdiniWins          = 0,
    shutoutWins          = 0,
    riskyDoubleWins      = 0,
    overkillWins         = 0,
    snapDecisionWins     = 0,
    slowBurnWins         = 0,
    stonewallPushes      = 0,
    quickHandWins        = 0,
    redCardsLoss         = 0,
    mirrorMatches        = 0,
    streakBreakers       = 0,
    perfectPairs         = 0,
    twinBlackjacks       = 0,
    bankBuster           = 0,
    comebackKidWins      = 0,
    quadAceWins          = 0,
    precisionSplits      = 0,
    lowBetWinStreak      = 0,
    -- Split / insurance / surrender
    splitCount           = 0,
    insuranceCount       = 0,
    surrenderCount       = 0,
    splitWins            = 0,
    insurancePaid        = 0,
    insuranceWon         = 0,
    -- Action tracking
    actions = {
      hit    = { total = 0, outcomes = {} },
      stand  = { total = 0, outcomes = {} },
      double = { total = 0, outcomes = {} },
      split  = { total = 0, outcomes = {} },
    },
    -- Dealer up-card outcomes
    dealer = {
      upCardOutcomes = {},
    },
    -- Card combination tracking
    cards = {
      twentyOneWith = {
        ["3cards"]  = 0,
        ["4cards"]  = 0,
        ["5+cards"] = 0,
      },
    },
    -- Timing
    timing = {
      startTimes    = {},
      decisionTimes = {},
    },
    -- Day tracking
    days = {},
  }
end

-----------------------------------------------------
-- Load / Save Player Stats
-----------------------------------------------------
local function loadPlayerStats(playerName)
  if not playerName then return nil end

  local statsPath = STATS_DIR .. "/" .. string.lower(playerName) .. ".dat"
  if not fs.exists(statsPath) then
    return defaultStats(playerName)
  end

  local file = fs.open(statsPath, "r")
  if not file then
    dbg("Failed to open stats file for " .. playerName)
    return nil
  end

  local content = file.readAll()
  file.close()

  local stats = textutils.unserialize(content)
  if not stats then
    dbg("Failed to deserialize stats for " .. playerName)
    return nil
  end

  return stats
end

local function savePlayerStats(playerName, stats)
  if not playerName then
    writeLog("Error: Attempted to save stats without player name")
    return false
  end

  local statsPath = STATS_DIR .. "/" .. string.lower(playerName) .. ".dat"
  local file = fs.open(statsPath, "w")
  if not file then
    writeLog("Error: Failed to open stats file for writing: " .. statsPath)
    return false
  end

  if not stats.achievements then stats.achievements = {} end
  if not stats.lastUpdated then stats.lastUpdated = os.epoch("local") end

  local serialized = textutils.serialize(stats)
  file.write(serialized)
  file.close()

  return true
end

-----------------------------------------------------
-- Leaderboard
-----------------------------------------------------
local function loadLeaderboard()
  if not fs.exists(LEADERBOARD_FILE) then return {} end
  local ok, data = pcall(function()
    local f = fs.open(LEADERBOARD_FILE, "r")
    if not f then return nil end
    local t = textutils.unserialize(f.readAll())
    f.close()
    return t
  end)
  return (ok and data) or {}
end

local function saveLeaderboard(lb)
  local f = fs.open(LEADERBOARD_FILE, "w")
  if f then
    f.write(textutils.serialize(lb))
    f.close()
  end
end

local function updateLeaderboard(playerName, stats)
  if not playerName or not stats then return end

  local lb = loadLeaderboard()
  if not lb.topWins       then lb.topWins       = {} end
  if not lb.topProfit     then lb.topProfit     = {} end
  if not lb.topBets       then lb.topBets       = {} end
  if not lb.topBlackjacks then lb.topBlackjacks = {} end
  lb.lastUpdated = os.epoch("local")

  local function updateCategory(category, playerKey, playerValue)
    local found = false
    for _, entry in ipairs(category) do
      if entry.player == playerName then
        entry[playerKey] = playerValue
        found = true
        break
      end
    end
    if not found then
      table.insert(category, { player = playerName, [playerKey] = playerValue })
    end
    table.sort(category, function(a, b)
      return (a[playerKey] or 0) > (b[playerKey] or 0)
    end)
    while #category > 10 do
      table.remove(category)
    end
  end

  updateCategory(lb.topWins,       "wins",       stats.wins or 0)
  updateCategory(lb.topProfit,     "netProfit",   stats.netProfit or 0)
  updateCategory(lb.topBets,       "biggestBet",  stats.biggestBet or 0)
  updateCategory(lb.topBlackjacks, "blackjacks",  stats.blackjacks or 0)

  saveLeaderboard(lb)
end

return {
  init              = init,
  defaultStats      = defaultStats,
  loadPlayerStats   = loadPlayerStats,
  savePlayerStats   = savePlayerStats,
  loadLeaderboard   = loadLeaderboard,
  saveLeaderboard   = saveLeaderboard,
  updateLeaderboard = updateLeaderboard,
  writeLog          = writeLog,
  STATS_DIR         = STATS_DIR,
  LEADERBOARD_FILE  = LEADERBOARD_FILE,
}
