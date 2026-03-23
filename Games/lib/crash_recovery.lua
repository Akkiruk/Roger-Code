-- crash_recovery.lua
-- Crash-safe bet recovery for any casino game.
-- Saves active bets to a file so they can be returned on restart.
-- Uses CCVault token economy for refunds.
-- Usage:
--   local recovery = require("lib.crash_recovery")
--   recovery.configure("blackjack_recovery.dat")
--   recovery.saveBet(45)
--   recovery.clearBet()
--   recovery.recoverBet()

local currency = require("lib.currency")

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[recovery] " .. msg) end
end

local RECOVERY_FILE = "game_recovery.dat"

--- Set the recovery file path (each game should use its own).
-- @param path string
local function configure(path)
  assert(type(path) == "string", "path must be a string")
  RECOVERY_FILE = path
end

--- Save an active bet amount (and optional phase) to the recovery file.
-- @param betAmount number
-- @param phase     string|nil  Optional game phase for debugging
local function saveBet(betAmount, phase)
  assert(type(betAmount) == "number", "betAmount must be a number")
  local file = fs.open(RECOVERY_FILE, "w")
  if file then
    file.write(textutils.serialize({ bet = betAmount, phase = phase }))
    file.close()
    dbg("Saved active bet of " .. betAmount .. (phase and (" phase=" .. phase) or ""))
  end
end

--- Save an active bet with escrow IDs for crash-safe recovery.
-- @param betAmount number  Total bet at risk
-- @param escrows   table   Array of {id=string, amount=number, tag=string}
-- @param phase     string|nil  Optional game phase
local function saveEscrowBet(betAmount, escrows, phase)
  assert(type(betAmount) == "number", "betAmount must be a number")
  local data = { bet = betAmount, escrows = escrows or {}, phase = phase }
  local file = fs.open(RECOVERY_FILE, "w")
  if file then
    file.write(textutils.serialize(data))
    file.close()
    dbg("Saved escrow bet: " .. betAmount .. " with " .. #(escrows or {}) .. " escrows")
  end
end

--- Add an escrow to the existing recovery data (for doubles/splits mid-round).
-- Updates the total bet and appends the escrow entry.
-- @param id     string  Escrow ID
-- @param amount number  Token amount held
-- @param tag    string  Label (e.g. "double", "split", "insurance")
local function addEscrow(id, amount, tag)
  if not fs.exists(RECOVERY_FILE) then return end
  local file = fs.open(RECOVERY_FILE, "r")
  if not file then return end
  local raw = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, raw)
  if not ok or type(data) ~= "table" then
    data = { bet = 0, escrows = {} }
  end
  if not data.escrows then data.escrows = {} end
  table.insert(data.escrows, { id = id, amount = amount, tag = tag })
  data.bet = (data.bet or 0) + amount
  local wf = fs.open(RECOVERY_FILE, "w")
  if wf then
    wf.write(textutils.serialize(data))
    wf.close()
    dbg("Added escrow " .. id .. " (" .. tag .. "), total bet now " .. data.bet)
  end
end

--- Save a full round snapshot (bet + hand state) so crashes can be audited.
-- Preserves any escrow IDs already saved in the recovery file.
-- @param betAmount number
-- @param snapshot  table  Serializable subset of game ctx (hands, dealer visible cards, phase)
local function saveSnapshot(betAmount, snapshot)
  assert(type(betAmount) == "number", "betAmount must be a number")
  local data = { bet = betAmount, snapshot = snapshot }
  -- Preserve existing escrow IDs
  if fs.exists(RECOVERY_FILE) then
    local rf = fs.open(RECOVERY_FILE, "r")
    if rf then
      local raw = rf.readAll()
      rf.close()
      local ok, existing = pcall(textutils.unserialize, raw)
      if ok and type(existing) == "table" and existing.escrows then
        data.escrows = existing.escrows
      end
    end
  end
  local file = fs.open(RECOVERY_FILE, "w")
  if file then
    file.write(textutils.serialize(data))
    file.close()
    dbg("Saved snapshot, bet=" .. betAmount)
  end
end

--- Clear the recovery file (call when a bet is resolved normally).
local function clearBet()
  if fs.exists(RECOVERY_FILE) then
    fs.delete(RECOVERY_FILE)
    dbg("Cleared bet recovery file")
  end
end

--- Parse recovery file contents (supports plain number, phase table, and full snapshot).
-- @param raw string  Raw file contents
-- @return number|nil, string|nil, table|nil  betAmount, phase, snapshot
local function parseRecoveryData(raw)
  local num = tonumber(raw)
  if num then return num, nil, nil end
  local ok, data = pcall(textutils.unserialize, raw)
  if ok and type(data) == "table" and data.bet then
    return tonumber(data.bet), data.phase, data.snapshot
  end
  return nil, nil, nil
end

--- Check for and recover an unresolved bet from a previous session.
-- Escrow-aware: cancels any held escrows first (instant refund).
-- Falls back to legacy payout refund for old recovery files.
-- @param verbose    boolean?    If true, print messages even when no bet is found
-- @return boolean  true if a bet was recovered
local function recoverBet(verbose)
  if fs.exists(RECOVERY_FILE) then
    local file = fs.open(RECOVERY_FILE, "r")
    if file then
      local betStr = file.readAll()
      file.close()

      -- Try escrow-aware recovery first
      local parseOk, data = pcall(textutils.unserialize, betStr)
      if parseOk and type(data) == "table" and data.escrows and #data.escrows > 0 then
        dbg("Escrow recovery: found " .. #data.escrows .. " escrows")
        print("Checking unresolved escrows from previous session...")
        local anyRecovered = false
        for _, esc in ipairs(data.escrows) do
          local info = currency.getEscrowInfo(esc.id)
          if info and info.status == "held" then
            print("  Cancelling escrow (" .. (esc.amount or "?") .. " tokens)...")
            if currency.cancelEscrow(esc.id, "crash recovery") then
              print("  Refunded " .. (esc.amount or "?") .. " tokens.")
              anyRecovered = true
            else
              print("  ERROR: Failed to cancel escrow!")
              local ef = fs.open("recovery_error.log", "a")
              if ef then
                ef.writeLine("[" .. os.epoch("local") .. "] Failed to cancel escrow " .. esc.id)
                ef.close()
              end
            end
          elseif info then
            dbg("  Escrow " .. esc.id .. " status: " .. (info.status or "?"))
          else
            dbg("  Escrow " .. esc.id .. " not found (expired/auto-refunded)")
            anyRecovered = true
          end
        end
        if anyRecovered then
          print("Escrow recovery complete.")
        elseif verbose then
          print("All escrows were already resolved.")
        end
        clearBet()
        return anyRecovered
      end

      -- Legacy recovery (no escrow data)
      local recoveredBet, phase, snapshot = parseRecoveryData(betStr)
      if recoveredBet and recoveredBet > 0 then
        dbg("Legacy recovery: " .. recoveredBet .. " tokens" .. (phase and (" phase=" .. phase) or ""))
        if snapshot then
          dbg("Snapshot found — hand state was saved for audit")
        end
        print("Detected unresolved bet from previous session.")
        print("Returning " .. recoveredBet .. " tokens to player...")

        if currency.payout(recoveredBet, "crash recovery refund") then
          print("Successfully returned " .. recoveredBet .. " tokens.")
          clearBet()
          return true
        else
          print("ERROR: Failed to return " .. recoveredBet .. " tokens!")
          print("Please contact an admin for assistance.")
          local ef = fs.open("recovery_error.log", "a")
          if ef then
            ef.writeLine("[" .. os.epoch("local") .. "] Legacy recovery failed: " .. recoveredBet .. " tokens")
            ef.close()
          end
          return false
        end
      end
    end
  elseif verbose then
    print("No unresolved bets found.")
  end

  return false
end

--- Check if there's an active recovery file.
-- @return number|nil, string|nil, table|nil  The bet amount, phase, and snapshot or nil
local function getActiveBet()
  if not fs.exists(RECOVERY_FILE) then return nil, nil end
  local file = fs.open(RECOVERY_FILE, "r")
  if not file then return nil, nil end
  local betStr = file.readAll()
  file.close()
  return parseRecoveryData(betStr)
end

--- Get full recovery data including escrow IDs (for escrow-aware recovery).
-- @return table|nil  {bet=N, escrows={...}, phase=S, snapshot=T} or nil
local function getRecoveryData()
  if not fs.exists(RECOVERY_FILE) then return nil end
  local file = fs.open(RECOVERY_FILE, "r")
  if not file then return nil end
  local raw = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, raw)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

return {
  configure       = configure,
  saveBet         = saveBet,
  saveEscrowBet   = saveEscrowBet,
  addEscrow       = addEscrow,
  saveSnapshot    = saveSnapshot,
  clearBet        = clearBet,
  recoverBet      = recoverBet,
  getActiveBet    = getActiveBet,
  getRecoveryData = getRecoveryData,
}
