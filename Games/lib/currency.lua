-- currency.lua
-- Shared currency management for all casino games.
-- Backend: CCVault server-authoritative token economy.
-- All money operations go through ccvault.transfer() and ccvault.getBalance().
-- Usage:
--   local currency = require("lib.currency")
--   local tokens = currency.getPlayerBalance()
--   currency.charge(50, "blackjack bet")
--   currency.payout(100, "blackjack win")

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[currency] " .. msg) end
end

-- Token denomination table used by betting UI
-- "value" is in tokens (the base unit in CCVault)
local DENOMINATIONS = {
  { name = "1 Token",    value = 1,    color = colors.white,   sound = "quark:ambient.clock" },
  { name = "5 Tokens",   value = 5,    color = colors.yellow,  sound = "the_vault:coin_single_place" },
  { name = "25 Tokens",  value = 25,   color = colors.cyan,    sound = "lightmanscurrency:coins_clinking" },
  { name = "100 Tokens", value = 100,  color = colors.magenta, sound = "the_vault:coin_pile_break" },
}

--- Apply configuration overrides.
-- @param cfg table  Keys: denominations
local function configure(cfg)
  assert(type(cfg) == "table", "configure expects a table")
  if cfg.denominations then DENOMINATIONS = cfg.denominations end
end

--- Check that ccvault is available and authenticated.
-- @return boolean, string|nil  true if ready, false + error message if not
local function isReady()
  if not ccvault or not ccvault.isAvailable() then
    return false, "economy system not available"
  end
  if not ccvault.isAuthenticated() then
    return false, "not authenticated"
  end
  return true, nil
end

--- Run the authentication flow. Blocks until authenticated or timeout.
-- @param timeout number?  Seconds to wait (default 60)
-- @return boolean  true if authenticated
local function authenticate(timeout)
  timeout = timeout or 60

  if not ccvault or not ccvault.isAvailable() then
    print("Economy system is not available on this server.")
    return false
  end

  -- Wait for a player to interact
  print("Waiting for player...")
  while not ccvault.getPlayerName() do
    os.sleep(1)
  end

  if ccvault.isAuthenticated() then
    dbg("Already authenticated as " .. (ccvault.getPlayerName() or "?"))
    return true
  end

  -- requestAuth() throws (not returns nil) if no player is present,
  -- so pcall-wrap it in case the player walks away between the name check and here.
  local pcallOk, ok, err = pcall(ccvault.requestAuth)
  if not pcallOk then
    print("Auth request error: " .. tostring(ok))
    return false
  end
  if not ok then
    print("Auth request failed: " .. (err or "unknown"))
    return false
  end

  local compId = ccvault.getComputerId and ccvault.getComputerId() or os.getComputerID()
  print("Approve Computer #" .. tostring(compId) .. " in chat.")

  local timer = os.startTimer(timeout)
  while not ccvault.isAuthenticated() do
    local event, id = os.pullEvent()
    if event == "timer" and id == timer then
      print("Auth timed out.")
      return false
    end
    os.sleep(0.5)
  end

  dbg("Authenticated as " .. (ccvault.getPlayerName() or "?"))
  return true
end

--- Get the currently interacting player's name.
-- @return string|nil
local function getPlayerName()
  if ccvault and ccvault.getPlayerName then
    return ccvault.getPlayerName()
  end
  return nil
end

--- Get the host (computer owner) name.
-- @return string|nil
local function getHostName()
  if ccvault and ccvault.getHostName then
    local name = ccvault.getHostName()
    return name
  end
  return nil
end

--- Get this computer's CCVault / CC ID.
-- Useful for telling the player which terminal to revoke.
-- @return number
local function getComputerId()
  if ccvault and ccvault.getComputerId then
    return ccvault.getComputerId()
  end
  return os.getComputerID()
end

--- Get the player's token balance.
-- @return number  Token count (0 if unavailable)
local function getPlayerBalance()
  local ready, err = isReady()
  if not ready then
    dbg("getPlayerBalance failed: " .. (err or "unknown"))
    return 0
  end
  local bal, balErr = ccvault.getBalance("player")
  if bal then return bal end
  dbg("getBalance(player) error: " .. (balErr or "unknown"))
  return 0
end

--- Get the host's token balance.
-- @return number  Token count (0 if unavailable)
local function getHostBalance()
  local ready, err = isReady()
  if not ready then
    dbg("getHostBalance failed: " .. (err or "unknown"))
    return 0
  end
  local bal, balErr = ccvault.getBalance("host")
  if bal then return bal end
  dbg("getBalance(host) error: " .. (balErr or "unknown"))
  return 0
end

--- Charge the player (player pays host).
-- @param amount number  Tokens to charge (rounded to whole tokens)
-- @param reason string  Audit log reason (max 64 chars)
-- @return boolean success, string|nil txId
local function charge(amount, reason)
  amount = math.floor(amount)
  if amount <= 0 then return true, nil end
  assert(type(reason) == "string" and #reason > 0, "reason is required")
  local ready, err = isReady()
  if not ready then
    dbg("charge failed: " .. (err or "unknown"))
    return false, nil
  end
  dbg("Charging player " .. amount .. " tokens: " .. reason)
  local result, txErr = ccvault.transfer("player", "host", amount, reason)
  if result then
    dbg("Charge OK, TX: " .. (result.txId or "?"))
    return true, result.txId
  end
  -- Self-play: transfer() blocks same-account transfers, use transferSelf()
  if isSelfPlay() and ccvault.transferSelf then
    dbg("Self-play fallback for charge")
    local selfResult, selfErr = ccvault.transferSelf(amount, reason)
    if selfResult then
      dbg("Charge (self) OK, TX: " .. (selfResult.txId or "?"))
      return true, selfResult.txId
    end
    dbg("Charge (self) failed: " .. (selfErr or "unknown"))
    return false, nil
  end
  dbg("Charge failed: " .. (txErr or "unknown"))
  return false, nil
end

--- Pay the player (host pays player).
-- @param amount number  Tokens to pay out (rounded to whole tokens)
-- @param reason string  Audit log reason (max 64 chars)
-- @return boolean success, string|nil txId
local function payout(amount, reason)
  amount = math.floor(amount)
  if amount <= 0 then return true, nil end
  assert(type(reason) == "string" and #reason > 0, "reason is required")
  local ready, err = isReady()
  if not ready then
    dbg("payout failed: " .. (err or "unknown"))
    return false, nil
  end
  dbg("Paying player " .. amount .. " tokens: " .. reason)
  local result, txErr = ccvault.transfer("host", "player", amount, reason)
  if result then
    dbg("Payout OK, TX: " .. (result.txId or "?"))
    return true, result.txId
  end
  -- Self-play: transfer() blocks same-account transfers, use transferSelf()
  if isSelfPlay() and ccvault.transferSelf then
    dbg("Self-play fallback for payout")
    local selfResult, selfErr = ccvault.transferSelf(amount, reason)
    if selfResult then
      dbg("Payout (self) OK, TX: " .. (selfResult.txId or "?"))
      return true, selfResult.txId
    end
    dbg("Payout (self) failed: " .. (selfErr or "unknown"))
    return false, nil
  end
  dbg("Payout failed: " .. (txErr or "unknown"))
  return false, nil
end

--- Format a token amount for display.
-- @param tokens number
-- @return string  e.g. "50 tokens"
local function formatTokens(tokens)
  if tokens == 1 then return "1 token" end
  return tostring(tokens) .. " tokens"
end

-----------------------------------------------------
-- Escrow API wrappers
-----------------------------------------------------

--- Check if the escrow API is available on this server.
-- @return boolean
local function hasEscrow()
  return ccvault and type(ccvault.escrow) == "function"
end

--- Create an escrow hold (deducts from player, holds server-side).
-- Tokens are NOT given to the host until resolveEscrow() is called.
-- On server crash or timeout, tokens auto-refund to player.
-- @param amount number  Tokens to escrow (rounded to whole tokens)
-- @param reason string  Audit log reason
-- @return boolean success, string|nil escrowId
local function escrow(amount, reason)
  amount = math.floor(amount)
  if amount <= 0 then return true, nil end
  assert(type(reason) == "string" and #reason > 0, "reason is required")
  local ready, err = isReady()
  if not ready then
    dbg("escrow failed: " .. (err or "unknown"))
    return false, nil
  end
  if not ccvault.escrow then
    dbg("escrow not available, falling back to charge")
    return charge(amount, reason)
  end
  dbg("Escrowing " .. amount .. " tokens: " .. reason)
  local result, escErr = ccvault.escrow(amount, reason)
  if result and result.escrowId then
    dbg("Escrow OK: " .. result.escrowId)
    return true, result.escrowId
  end
  dbg("Escrow failed: " .. (escErr or "unknown"))
  return false, nil
end

--- Resolve an escrow by sending held tokens to "host" or "player".
-- @param escrowId string
-- @param recipient string  "host" or "player"
-- @param reason string
-- @return boolean success, string|nil txId
local function resolveEscrow(escrowId, recipient, reason)
  assert(type(escrowId) == "string", "escrowId must be a string")
  assert(recipient == "host" or recipient == "player",
         "recipient must be 'host' or 'player'")
  assert(type(reason) == "string" and #reason > 0, "reason is required")
  local ready, err = isReady()
  if not ready then
    dbg("resolveEscrow failed: " .. (err or "unknown"))
    return false, nil
  end
  dbg("Resolving escrow " .. escrowId .. " -> " .. recipient .. ": " .. reason)
  local result, resErr = ccvault.resolveEscrow(escrowId, recipient, reason)
  if result then
    dbg("Resolve OK, TX: " .. (result.txId or "?"))
    return true, result.txId
  end
  dbg("Resolve failed: " .. (resErr or "unknown"))
  return false, nil
end

--- Cancel an escrow (refunds held tokens to player).
-- @param escrowId string
-- @param reason string
-- @return boolean success
local function cancelEscrow(escrowId, reason)
  assert(type(escrowId) == "string", "escrowId must be a string")
  assert(type(reason) == "string" and #reason > 0, "reason is required")
  local ready, err = isReady()
  if not ready then
    dbg("cancelEscrow failed: " .. (err or "unknown"))
    return false
  end
  dbg("Cancelling escrow " .. escrowId .. ": " .. reason)
  local result, canErr = ccvault.cancelEscrow(escrowId, reason)
  if result then
    dbg("Cancel OK")
    return true
  end
  dbg("Cancel failed: " .. (canErr or "unknown"))
  return false
end

--- Get info about an escrow hold.
-- @param escrowId string
-- @return table|nil  {escrowId, amount, status, timeRemaining, reason}
local function getEscrowInfo(escrowId)
  assert(type(escrowId) == "string", "escrowId must be a string")
  local ready, err = isReady()
  if not ready then return nil end
  if not ccvault.getEscrowInfo then return nil end
  local info = ccvault.getEscrowInfo(escrowId)
  return info
end

-----------------------------------------------------
-- Session / verification API wrappers
-----------------------------------------------------

--- Get session info from CCVault (no auth required).
-- @return table|nil  {playerName, hostName, isSelfPlay, authenticated, transfersRemaining, ...}
local function getSessionInfo()
  if not ccvault or not ccvault.getSessionInfo then
    return nil
  end
  local info = ccvault.getSessionInfo()
  return info
end

--- Check if the current session is self-play (player == host).
-- @return boolean
local function isSelfPlay()
  local info = getSessionInfo()
  return info and info.isSelfPlay or false
end

--- Verify a transaction by ID in the server ledger.
-- Only returns transactions where the current player was involved.
-- @param txId string  The transaction ID to look up
-- @return table|nil tx  {txId, amount, reason, timestamp, ...}
local function verifyTransaction(txId)
  assert(type(txId) == "string", "txId must be a string")
  local ready, err = isReady()
  if not ready then return nil end
  if not ccvault.verifyTransaction then return nil end
  local tx, txErr = ccvault.verifyTransaction(txId)
  return tx
end

--- Get recent transaction history for the current player.
-- @param limit number?  Max entries (default 10, server-capped)
-- @return table|nil entries
local function getTransactionHistory(limit)
  local ready, err = isReady()
  if not ready then return nil end
  if not ccvault.getTransactionHistory then return nil end
  local txs = ccvault.getTransactionHistory(limit or 10)
  return txs
end

return {
  -- Core
  configure        = configure,
  isReady          = isReady,
  authenticate     = authenticate,
  getPlayerName    = getPlayerName,
  getHostName      = getHostName,
  getComputerId    = getComputerId,
  getPlayerBalance = getPlayerBalance,
  getHostBalance   = getHostBalance,
  charge           = charge,
  payout           = payout,
  formatTokens     = formatTokens,
  DENOMINATIONS    = DENOMINATIONS,
  -- Escrow
  hasEscrow        = hasEscrow,
  escrow           = escrow,
  resolveEscrow    = resolveEscrow,
  cancelEscrow     = cancelEscrow,
  getEscrowInfo    = getEscrowInfo,
  -- Session / verification
  getSessionInfo   = getSessionInfo,
  isSelfPlay       = isSelfPlay,
  verifyTransaction     = verifyTransaction,
  getTransactionHistory = getTransactionHistory,
}
