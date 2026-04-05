local currency = require("lib.currency")
local pokerLog = require("lib.poker_log")
local pokerStore = require("lib.poker_store")

local M = {}

local STATE_FILE = "pokertable_bank_state.dat"
local logger = pokerLog.new("pokertable_bank.log", false)

local function loadState()
  local state = pokerStore.load(STATE_FILE, {
    settlements = {},
    activeSession = nil,
    buyIns = {},
  })

  if type(state) ~= "table" then
    state = {
      settlements = {},
      activeSession = nil,
      buyIns = {},
    }
  end

  state.settlements = state.settlements or {}
  state.buyIns = state.buyIns or {}
  return state
end

local function saveState(state)
  local ok, err = pokerStore.save(STATE_FILE, state)
  if not ok then
    logger.write("Failed to save bank state: " .. tostring(err))
  end
  return ok, err
end

local function trimReason(reason)
  local text = tostring(reason or "")
  if #text > 64 then
    return text:sub(1, 64)
  end
  return text
end

function M.authenticate(timeout)
  local authOk = currency.authenticate(timeout or 60)
  if not authOk then
    return nil, "authentication_failed"
  end

  local info = currency.getSessionInfo() or {}
  local identity = {
    playerName = currency.getAuthenticatedPlayerName() or currency.getPlayerName(),
    hostName = currency.getHostName(),
    computerId = currency.getComputerId(),
    authenticated = info.authenticated == true,
    isSelfPlay = info.isSelfPlay == true,
  }

  if not identity.playerName or identity.playerName == "" then
    return nil, "missing_player_name"
  end

  if not identity.hostName or identity.hostName == "" then
    return nil, "missing_host_name"
  end

  return identity
end

function M.getIdentity()
  local info = currency.getSessionInfo() or {}
  return {
    playerName = currency.getAuthenticatedPlayerName() or currency.getPlayerName(),
    hostName = currency.getHostName(),
    computerId = currency.getComputerId(),
    authenticated = info.authenticated == true,
    isSelfPlay = info.isSelfPlay == true,
  }
end

function M.ensureHost(expectedHostName)
  assert(type(expectedHostName) == "string", "expectedHostName must be a string")
  local actualHostName = currency.getHostName()

  if actualHostName ~= expectedHostName then
    return false, "Seat host " .. tostring(actualHostName) .. " does not match table host " .. tostring(expectedHostName)
  end

  return true
end

function M.beginSession(session)
  assert(type(session) == "table", "session must be a table")
  local state = loadState()
  state.activeSession = session
  saveState(state)
  return true
end

function M.getActiveSession()
  local state = loadState()
  return state.activeSession
end

function M.updateSession(fields)
  assert(type(fields) == "table", "fields must be a table")

  local state = loadState()
  if type(state.activeSession) ~= "table" then
    return false, "no_active_session"
  end

  for key, value in pairs(fields) do
    state.activeSession[key] = value
  end

  saveState(state)
  return true
end

function M.clearSession()
  local state = loadState()
  state.activeSession = nil
  saveState(state)
  return true
end

function M.buyIn(tableId, amount)
  assert(type(tableId) == "string", "tableId must be a string")

  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return false, nil, "amount must be positive"
  end

  local reason = trimReason("poker buyin " .. tableId)
  local ok, txId = currency.charge(amount, reason)
  if not ok then
    return false, nil, "buyin_transfer_failed"
  end

  local state = loadState()
  state.buyIns[txId or (tableId .. "-" .. tostring(amount))] = {
    tableId = tableId,
    amount = amount,
    txId = txId,
    createdAt = os.epoch("local"),
  }
  saveState(state)

  logger.write("Buy-in recorded for table " .. tableId .. ": " .. tostring(amount) .. " tokens")
  return true, txId
end

function M.cashOut(tableId, settlementId, amount)
  assert(type(tableId) == "string", "tableId must be a string")
  assert(type(settlementId) == "string" and settlementId ~= "", "settlementId must be a string")

  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then
    return false, nil, false, "amount must not be negative"
  end

  local state = loadState()
  local existing = state.settlements[settlementId]
  if existing and existing.status == "paid" then
    logger.write("Cash-out settlement replay detected for " .. settlementId)
    return true, existing.txId, true
  end

  if amount == 0 then
    state.settlements[settlementId] = {
      tableId = tableId,
      amount = 0,
      txId = nil,
      status = "paid",
      paidAt = os.epoch("local"),
    }
    saveState(state)
    return true, nil, false
  end

  local hostBalance = currency.getHostBalance()
  if hostBalance < amount then
    return false, nil, false, "host balance is below requested cash-out"
  end

  local reason = trimReason("poker cashout " .. tableId)
  local ok, txId = currency.payout(amount, reason)
  if not ok then
    return false, nil, false, "cashout_transfer_failed"
  end

  state.settlements[settlementId] = {
    tableId = tableId,
    amount = amount,
    txId = txId,
    status = "paid",
    paidAt = os.epoch("local"),
  }
  saveState(state)

  logger.write("Cash-out recorded for table " .. tableId .. ": " .. tostring(amount) .. " tokens")
  return true, txId, false
end

return M