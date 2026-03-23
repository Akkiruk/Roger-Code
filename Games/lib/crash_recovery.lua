-- crash_recovery.lua  (v3)
-- Crash-safe bet tracking for any casino game.
-- Atomic writes, backup files, crash audit log, rich metadata.
-- With transfer-at-end economy, no money moves during the game,
-- so crash recovery only needs to audit-log the interruption and clear state.
--
-- Usage:
--   local recovery = require("lib.crash_recovery")
--   recovery.configure("blackjack_recovery.dat")
--   recovery.setGame("blackjack")
--   recovery.setPlayer("Steve")
--   recovery.saveBet(45)
--   recovery.saveSnapshot(90, { phase = "player_turn", hands = ... })
--   recovery.clearBet()
--   recovery.recoverBet(true)

-----------------------------------------------------
-- Internal state
-----------------------------------------------------
local SCHEMA_VERSION = 3
local RECOVERY_FILE = "game_recovery.dat"
local LOG_FILE = "crash_recovery.log"
local ERROR_LOG = "crash_recovery_error.log"
local MAX_LOG_ENTRIES = 200

local gameName = nil    -- set by setGame()
local playerName = nil  -- set by setPlayer()

local DEBUG = settings.get("casino.debug") or false

-----------------------------------------------------
-- Helpers
-----------------------------------------------------

--- Debug print with real-time timestamp.
local function dbg(msg)
  if DEBUG then
    print("[" .. os.epoch("local") .. "] [recovery] " .. tostring(msg))
  end
end

--- Append a line to a log file with timestamp.
-- @param path string  Log file path
-- @param msg  string  Message to log
local function logToFile(path, msg)
  local ok, err = pcall(function()
    local f = fs.open(path, "a")
    if f then
      f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
      f.close()
    end
  end)
  if not ok and DEBUG then
    print("[recovery] log write failed: " .. tostring(err))
  end
end

--- Log an error to the error log file.
local function logError(msg)
  logToFile(ERROR_LOG, msg)
  dbg("ERROR: " .. msg)
end

--- Atomic file write: writes to a temp file then moves it over the target.
-- Prevents corruption from mid-write crashes or reboots.
-- @param path string
-- @param content string
-- @return boolean success
local function atomicWrite(path, content)
  local tmpPath = path .. ".tmp"
  local ok, writeErr = pcall(function()
    local f = fs.open(tmpPath, "w")
    if not f then
      error("failed to open temp file: " .. tmpPath)
    end
    f.write(content)
    f.close()
  end)
  if not ok then
    logError("atomicWrite: temp write failed for " .. path .. ": " .. tostring(writeErr))
    -- Cleanup failed temp
    if fs.exists(tmpPath) then
      pcall(fs.delete, tmpPath)
    end
    return false
  end
  -- Backup existing file before overwrite
  local bakPath = path .. ".bak"
  local moveOk, moveErr = pcall(function()
    if fs.exists(bakPath) then fs.delete(bakPath) end
    if fs.exists(path) then fs.copy(path, bakPath) end
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmpPath, path)
  end)
  if not moveOk then
    logError("atomicWrite: move failed for " .. path .. ": " .. tostring(moveErr))
    -- Try direct write as last resort
    pcall(function()
      if fs.exists(tmpPath) then fs.delete(tmpPath) end
      local f = fs.open(path, "w")
      if f then f.write(content); f.close() end
    end)
    return false
  end
  return true
end

--- Read and parse a recovery file, falling back to .bak on corruption.
-- @param path string
-- @return table|nil  Parsed data table, or nil if unreadable
local function readRecoveryFile(path)
  local function tryRead(p)
    if not fs.exists(p) then return nil end
    local f = fs.open(p, "r")
    if not f then return nil end
    local raw = f.readAll()
    f.close()
    if not raw or raw == "" then return nil end
    local ok, data = pcall(textutils.unserialize, raw)
    if ok and type(data) == "table" then return data end
    return nil
  end

  -- Try main file first
  local data = tryRead(path)
  if data then return data end

  -- Main file missing or corrupt — try backup
  local bakPath = path .. ".bak"
  if fs.exists(bakPath) then
    logError("Main recovery file corrupt/missing, trying backup: " .. bakPath)
    data = tryRead(bakPath)
    if data then
      -- Restore backup to main
      pcall(function()
        if fs.exists(path) then fs.delete(path) end
        fs.copy(bakPath, path)
      end)
      return data
    end
    logError("Backup also corrupt: " .. bakPath)
  end

  return nil
end

--- Build metadata fields for the current state.
local function buildMeta()
  return {
    game = gameName,
    player = playerName,
    computerID = os.getComputerID(),
    updatedAt = os.epoch("local"),
  }
end

--- Migrate v1 data (or raw numbers) to current schema.
-- @param data table|nil   Parsed data from file
-- @param raw  string|nil  Raw file contents (for bare number fallback)
-- @return table  formatted state data
local function migrateToV2(data, raw)
  -- Bare number (ancient format)
  if not data and raw then
    local num = tonumber(raw)
    if num then
      return {
        version = SCHEMA_VERSION,
        bet = num,

        phase = nil,
        snapshot = nil,
        createdAt = os.epoch("local"),
        updatedAt = os.epoch("local"),
      }
    end
    return nil
  end
  if not data then return nil end
  -- Already v2
  if data.version and data.version >= SCHEMA_VERSION then return data end
  -- v1 table: has bet but no version field
  local migrated = {
    version   = SCHEMA_VERSION,
    bet       = data.bet or 0,

    phase     = data.phase,
    snapshot  = data.snapshot,
    game      = data.game,
    player    = data.player,
    computerID = data.computerID or os.getComputerID(),
    createdAt = data.createdAt or os.epoch("local"),
    updatedAt = os.epoch("local"),
  }
  return migrated
end

-----------------------------------------------------
-- Crash audit log
-----------------------------------------------------

--- Append an entry to the persistent crash audit log.
-- @param entry table  {event, game, player, bet, outcome, detail}
local function auditLog(entry)
  entry.timestamp = os.epoch("local")
  entry.computerID = os.getComputerID()
  entry.game = entry.game or gameName
  entry.player = entry.player or playerName

  -- Read existing log
  local log = {}
  local existing = readRecoveryFile(LOG_FILE)
  if existing and existing.entries then
    log = existing.entries
  end

  table.insert(log, entry)

  -- Trim to max size (keep newest)
  while #log > MAX_LOG_ENTRIES do
    table.remove(log, 1)
  end

  atomicWrite(LOG_FILE, textutils.serialize({ entries = log }))
  dbg("Audit: " .. (entry.event or "?") .. " — " .. (entry.outcome or "?"))
end

-----------------------------------------------------
-- Internal state read/write
-----------------------------------------------------

--- Read the current recovery state from disk.
-- Handles v1 migration and backup fallback automatically.
-- @return table|nil  v2 state, or nil if no active bet
local function loadState()
  -- Try structured read first
  local data = readRecoveryFile(RECOVERY_FILE)
  if data then return migrateToV2(data) end

  -- Try bare number fallback (ancient format)
  if fs.exists(RECOVERY_FILE) then
    local f = fs.open(RECOVERY_FILE, "r")
    if f then
      local raw = f.readAll()
      f.close()
      return migrateToV2(nil, raw)
    end
  end

  return nil
end

--- Write the full state to disk atomically.
-- @param state table  v2 state table
-- @return boolean success
local function writeState(state)
  state.version = SCHEMA_VERSION
  state.updatedAt = os.epoch("local")
  local content = textutils.serialize(state)
  local ok = atomicWrite(RECOVERY_FILE, content)
  if not ok then
    logError("writeState: failed to save recovery data")
  end
  return ok
end

-----------------------------------------------------
-- Public API — Configuration
-----------------------------------------------------

--- Set the recovery file path (each game should use its own).
-- @param path string
local function configure(path)
  assert(type(path) == "string", "path must be a string")
  RECOVERY_FILE = path
  dbg("Configured recovery file: " .. path)
end

--- Set the game name for metadata/logging.
-- @param name string
local function setGame(name)
  assert(type(name) == "string", "game name must be a string")
  gameName = name
  dbg("Game set: " .. name)
end

--- Set the current player name for metadata/logging.
-- @param name string
local function setPlayer(name)
  assert(type(name) == "string", "player name must be a string")
  playerName = name
  dbg("Player set: " .. name)
end

-----------------------------------------------------
-- Public API — Saving state
-----------------------------------------------------

--- Save an active bet amount (and optional phase) to the recovery file.
-- @param betAmount number
-- @param phase     string|nil  Optional game phase for debugging
local function saveBet(betAmount, phase)
  assert(type(betAmount) == "number", "betAmount must be a number")
  local state = loadState() or {}
  state.bet = betAmount
  state.phase = phase

  state.createdAt = state.createdAt or os.epoch("local")
  local meta = buildMeta()
  state.game = meta.game or state.game
  state.player = meta.player or state.player
  state.computerID = meta.computerID
  writeState(state)
  dbg("Saved bet: " .. betAmount .. (phase and (" phase=" .. phase) or ""))
end

--- Save a full round snapshot (bet + hand state) so crashes can be audited.

-- @param betAmount number
-- @param snapshot  table  Serializable game state for auditing
local function saveSnapshot(betAmount, snapshot)
  assert(type(betAmount) == "number", "betAmount must be a number")
  local state = loadState() or {}
  state.bet = betAmount
  state.snapshot = snapshot
  state.createdAt = state.createdAt or os.epoch("local")
  local meta = buildMeta()
  state.game = meta.game or state.game
  state.player = meta.player or state.player
  state.computerID = meta.computerID

  writeState(state)
  dbg("Saved snapshot, bet=" .. betAmount)
end

--- Partial update — merge fields into the existing recovery state.
-- Only writes fields you pass; everything else is preserved.
-- @param fields table  e.g. { phase = "dealer_turn", bet = 90 }
local function update(fields)
  assert(type(fields) == "table", "fields must be a table")
  local state = loadState()
  if not state then
    logError("update: no active state to update")
    return false
  end
  for k, v in pairs(fields) do
    state[k] = v
  end
  return writeState(state)
end

-----------------------------------------------------
-- Public API — Clearing state
-----------------------------------------------------

--- Clear the recovery file (call when a bet is resolved normally).
local function clearBet()
  local existed = fs.exists(RECOVERY_FILE)
  -- Remove main, tmp, and bak files
  for _, suffix in ipairs({"", ".tmp", ".bak"}) do
    local p = RECOVERY_FILE .. suffix
    if fs.exists(p) then
      pcall(fs.delete, p)
    end
  end
  if existed then
    dbg("Cleared recovery file: " .. RECOVERY_FILE)
  end
end

-----------------------------------------------------
-- Public API — Recovery
-----------------------------------------------------

--- Check for and handle an unresolved bet from a previous session.
-- With transfer-at-end, no money moved during the game, so nothing needs refunding.
-- Logs the interruption to the crash audit log and clears the recovery file.
-- @param verbose boolean?  If true, print messages even when no bet is found
-- @return boolean  true if a crashed bet was found (and cleared)
local function recoverBet(verbose)
  local state = loadState()

  if not state then
    if verbose then
      print("No unresolved bets found.")
    end
    return false
  end

  local betAmount = state.bet or 0
  local stateGame = state.game or gameName or "unknown"
  local statePlayer = state.player or playerName or "unknown"
  local age = state.createdAt and (os.epoch("local") - state.createdAt) or nil
  local ageStr = age and string.format("%.1fs ago", age / 1000) or "unknown age"

  dbg("Recovery check: game=" .. stateGame .. " player=" .. statePlayer
      .. " bet=" .. betAmount .. " (" .. ageStr .. ")")

  if betAmount > 0 then
    -- No money moved (transfer-at-end), so no refund needed — just inform and log
    print("Previous game interrupted (no tokens were charged).")
    print("  Game: " .. stateGame .. "  Bet: " .. betAmount .. " tokens  (" .. ageStr .. ")")

    auditLog({
      event = "crash_cleared",
      game = stateGame,
      player = statePlayer,
      bet = betAmount,
      outcome = "no_refund_needed",
      detail = "transfer-at-end: no money moved during game",
      age = age,
      phase = state.phase,
    })

    clearBet()
    return true
  end

  -- State file existed but bet was 0 or missing
  if verbose then
    print("Recovery file found but no active bet. Cleaning up.")
  end
  clearBet()
  return false
end

-----------------------------------------------------
-- Public API — Queries
-----------------------------------------------------

--- Check if there's an active recovery file.
-- @return number|nil, string|nil, table|nil  betAmount, phase, snapshot
local function getActiveBet()
  local state = loadState()
  if not state then return nil, nil, nil end
  return state.bet, state.phase, state.snapshot
end

--- Get full recovery data.
-- @return table|nil  Full v2 state, or nil
local function getRecoveryData()
  return loadState()
end

--- Check if the recovery file exists but is corrupt/unreadable.
-- @return boolean
local function isCorrupt()
  if not fs.exists(RECOVERY_FILE) then return false end
  local data = readRecoveryFile(RECOVERY_FILE)
  return data == nil
end

--- Get the age of the current recovery file in milliseconds.
-- @return number|nil  Age in ms, or nil if no active bet
local function getAge()
  local state = loadState()
  if not state or not state.createdAt then return nil end
  return os.epoch("local") - state.createdAt
end

--- Read the crash audit log.
-- @param limit number|nil  Max entries to return (newest first), default all
-- @return table  Array of audit log entries (newest first)
local function getCrashLog(limit)
  local data = readRecoveryFile(LOG_FILE)
  if not data or not data.entries then return {} end
  local entries = data.entries
  -- Return newest first
  local reversed = {}
  for i = #entries, 1, -1 do
    table.insert(reversed, entries[i])
    if limit and #reversed >= limit then break end
  end
  return reversed
end

--- Get summary statistics from the crash audit log.
-- @return table  { totalCrashes, totalRefunded, totalFailed, byGame={}, byPlayer={} }
local function getCrashStats()
  local entries = getCrashLog()
  local stats = {
    totalCrashes = #entries,
    totalRefunded = 0,
    totalFailed = 0,
    byGame = {},
    byPlayer = {},
  }
  for _, e in ipairs(entries) do
    stats.totalRefunded = stats.totalRefunded + (e.refunded or e.bet or 0)
    if e.outcome == "failed" or e.outcome == "partial" then
      stats.totalFailed = stats.totalFailed + 1
    end
    local g = e.game or "unknown"
    stats.byGame[g] = (stats.byGame[g] or 0) + 1
    local p = e.player or "unknown"
    stats.byPlayer[p] = (stats.byPlayer[p] or 0) + 1
  end
  return stats
end

--- Print a human-readable crash recovery report to the terminal.
local function printReport()
  local stats = getCrashStats()
  print("=== Crash Recovery Report ===")
  print("Total recoveries: " .. stats.totalCrashes)
  print("Total refunded:   " .. stats.totalRefunded .. " tokens")
  print("Failed attempts:  " .. stats.totalFailed)
  if next(stats.byGame) then
    print("By game:")
    for g, n in pairs(stats.byGame) do
      print("  " .. g .. ": " .. n)
    end
  end
  if next(stats.byPlayer) then
    print("By player:")
    for p, n in pairs(stats.byPlayer) do
      print("  " .. p .. ": " .. n)
    end
  end
  local recent = getCrashLog(5)
  if #recent > 0 then
    print("Recent (last " .. #recent .. "):")
    for _, e in ipairs(recent) do
      local ts = e.timestamp and os.date("%H:%M:%S",
        math.floor(e.timestamp / 1000)) or "?"
      print("  [" .. ts .. "] " .. (e.event or "?")
            .. " " .. (e.game or "?")
            .. " " .. (e.player or "?")
            .. " " .. (e.bet or 0) .. " tokens"
            .. " -> " .. (e.outcome or "?"))
    end
  end
end

return {
  -- Configuration
  configure       = configure,
  setGame         = setGame,
  setPlayer       = setPlayer,
  -- Saving state
  saveBet         = saveBet,
  saveSnapshot    = saveSnapshot,
  update          = update,
  -- Clearing
  clearBet        = clearBet,
  -- Recovery
  recoverBet      = recoverBet,
  -- Queries
  getActiveBet    = getActiveBet,
  getRecoveryData = getRecoveryData,
  isCorrupt       = isCorrupt,
  getAge          = getAge,
  -- Audit log
  getCrashLog     = getCrashLog,
  getCrashStats   = getCrashStats,
  printReport     = printReport,
}
