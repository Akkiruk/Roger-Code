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
local AUTH_POLL_INTERVAL = 0.2
local authWaitScreen = require("lib.auth_wait_screen")
local function dbg(msg)
  if DEBUG then print(os.epoch("local"), "[currency] " .. msg) end
end

-- Player identity for the currently authenticated session.
-- All financial operations are guarded against this lock to avoid cross-player charges.
local AUTH_PLAYER = nil

-- Token denomination table used by betting UI
-- "value" is in tokens (the base unit in CCVault)
local DENOMINATIONS = {
  { name = "1 Token",    value = 1,    color = colors.white,   sound = "quark:ambient.clock" },
  { name = "5 Tokens",   value = 5,    color = colors.yellow,  sound = "the_vault:coin_single_place" },
  { name = "25 Tokens",  value = 25,   color = colors.cyan,    sound = "lightmanscurrency:coins_clinking" },
  { name = "100 Tokens", value = 100,  color = colors.magenta, sound = "the_vault:coin_pile_break" },
}

local HOST_BALANCE_RESERVE = 2000
local TRANSACTION_AUDIT_FILE = "casino_transactions.log"

local function writeTransactionAudit(entry)
  local handle = fs.open(TRANSACTION_AUDIT_FILE, "a")
  if not handle then
    return
  end

  handle.writeLine(textutils.serialize(entry))
  handle.close()
end

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
  if AUTH_PLAYER and AUTH_PLAYER ~= "" then
    local info = nil
    if ccvault.getSessionInfo then
      info = ccvault.getSessionInfo()
    end
    local currentPlayer = (info and info.playerName) or (ccvault.getPlayerName and ccvault.getPlayerName()) or nil
    if (not currentPlayer) or currentPlayer == "" then
      return false, "no active player session"
    end
    if currentPlayer ~= AUTH_PLAYER then
      return false, "session player changed from " .. AUTH_PLAYER .. " to " .. tostring(currentPlayer)
    end
  end
  return true, nil
end

--- Run the authentication flow. Blocks until authenticated or timeout.
-- @param timeout number?  Seconds to wait (default 60)
-- @param opts table?  Optional keys: monitorName, monitorTextScale, surfacePath,
--                     fontPath, palette, title
-- @return boolean  true if authenticated
local function authenticate(timeout, opts)
  timeout = timeout or 60
  opts = opts or {}

  local waitScreen = nil
  local function closeWaitScreen()
    if waitScreen then
      local ok, err = pcall(function()
        authWaitScreen.close(waitScreen)
      end)
      if not ok then
        dbg("Auth wait screen close failed: " .. tostring(err))
      end
      waitScreen = nil
    end
  end

  local function renderWaitScreen(state)
    if not opts.monitorName then
      return
    end
    if not waitScreen then
      local created, result = pcall(function()
        return authWaitScreen.create({
          monitorName = opts.monitorName,
          monitorTextScale = opts.monitorTextScale,
          surfacePath = opts.surfacePath,
          fontPath = opts.fontPath,
          palette = opts.palette,
          title = opts.title,
          computerId = (ccvault and ccvault.getComputerId and ccvault.getComputerId()) or os.getComputerID(),
        })
      end)
      if not created then
        dbg("Auth wait screen unavailable: " .. tostring(result))
        opts.monitorName = nil
        return
      end
      waitScreen = result
    end

    local ok, err = pcall(function()
      authWaitScreen.render(waitScreen, state)
    end)
    if not ok then
      dbg("Auth wait screen render failed: " .. tostring(err))
      closeWaitScreen()
      opts.monitorName = nil
    end
  end

  if not ccvault or not ccvault.isAvailable() then
    print("Economy system is not available on this server.")
    return false
  end

  -- Wait for a player to interact
  print("Waiting for player...")
  renderWaitScreen({
    stage = "waiting_player",
    playerName = nil,
    secondsRemaining = timeout,
  })
  while not ccvault.getPlayerName() do
    renderWaitScreen({
      stage = "waiting_player",
      playerName = nil,
      secondsRemaining = timeout,
    })
    os.sleep(1)
  end

  local targetPlayer = ccvault.getPlayerName()
  if targetPlayer and targetPlayer ~= "" then
    print("Player detected: " .. targetPlayer)
  end

  -- Always request a fresh approval so this terminal binds to the active tester/player.
  -- If the session is already valid for the same player, we allow that fast path below.
  local pcallOk, ok, err = pcall(function()
    return ccvault.requestAuth()
  end)
  if not pcallOk or not ok then
    local alreadyAuthed = ccvault.isAuthenticated()
    local currentPlayer = ccvault.getPlayerName and ccvault.getPlayerName() or nil
    if not (alreadyAuthed and currentPlayer and currentPlayer == targetPlayer) then
      if not pcallOk then
        print("Auth request error: " .. tostring(ok))
      else
        print("Auth request failed: " .. (err or "unknown"))
      end
      closeWaitScreen()
      return false
    end
  end

  local compId = ccvault.getComputerId and ccvault.getComputerId() or os.getComputerID()
  print("Approve Computer #" .. tostring(compId) .. " in chat.")

  local authStartedAt = os.epoch("local")
  local timer = os.startTimer(timeout)
  local pollTimer = os.startTimer(AUTH_POLL_INTERVAL)
  renderWaitScreen({
    stage = "awaiting_approval",
    playerName = targetPlayer,
    computerId = compId,
    secondsRemaining = timeout,
  })
  while not ccvault.isAuthenticated() do
    local event, id = os.pullEvent()
    if event == "timer" and id == timer then
      if pollTimer then
        os.cancelTimer(pollTimer)
      end
      renderWaitScreen({
        stage = "timed_out",
        playerName = targetPlayer,
        computerId = compId,
        secondsRemaining = 0,
      })
      print("Auth timed out.")
      return false
    end
    if event == "timer" and id == pollTimer then
      local elapsedSeconds = (os.epoch("local") - authStartedAt) / 1000
      local secondsRemaining = math.ceil(timeout - elapsedSeconds)
      renderWaitScreen({
        stage = "awaiting_approval",
        playerName = targetPlayer,
        computerId = compId,
        secondsRemaining = secondsRemaining,
      })
      pollTimer = os.startTimer(AUTH_POLL_INTERVAL)
    end
  end
  if pollTimer then
    os.cancelTimer(pollTimer)
  end
  os.cancelTimer(timer)

  local authedPlayer = ccvault.getPlayerName and ccvault.getPlayerName() or nil
  if targetPlayer and authedPlayer and targetPlayer ~= authedPlayer then
    closeWaitScreen()
    print("Authentication player changed from " .. targetPlayer .. " to " .. authedPlayer .. ".")
    print("Please interact again and retry.")
    return false
  end

  renderWaitScreen({
    stage = "approved",
    playerName = authedPlayer or targetPlayer,
    computerId = compId,
    secondsRemaining = 0,
  })
  os.sleep(0.5)
  closeWaitScreen()

  AUTH_PLAYER = authedPlayer or targetPlayer
  dbg("Authenticated as " .. tostring(AUTH_PLAYER or "?"))
  return true
end

--- Get the live CCVault-reported player name without applying the auth lock.
-- @return string|nil
local function getLivePlayerName()
  if ccvault and ccvault.getPlayerName then
    return ccvault.getPlayerName()
  end
  return nil
end

--- Get the player name for this terminal session.
-- Returns the authenticated player when one is locked, otherwise the live CCVault player.
-- @return string|nil
local function getPlayerName()
  if AUTH_PLAYER and AUTH_PLAYER ~= "" then
    return AUTH_PLAYER
  end
  return getLivePlayerName()
end

--- Get the player bound to the current authenticated session.
-- This is pinned at auth time to avoid identity drift between players.
-- @return string|nil
local function getAuthenticatedPlayerName()
  return AUTH_PLAYER
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

local function getProtectedHostBalance(balance)
  local rawBalance = balance
  if rawBalance == nil then
    rawBalance = getHostBalance()
  end
  rawBalance = tonumber(rawBalance) or 0
  return math.max(0, math.floor(rawBalance) - HOST_BALANCE_RESERVE)
end

local function getMaxBetLimit(balance, maxBetPercent, hostCoverageMultiplier)
  local protectedBalance = getProtectedHostBalance(balance)
  local percent = tonumber(maxBetPercent) or 0
  local maxBet = math.floor(protectedBalance * percent)

  if hostCoverageMultiplier and hostCoverageMultiplier > 1 then
    maxBet = math.min(maxBet, math.floor(protectedBalance / (hostCoverageMultiplier - 1)))
  end

  return math.max(0, maxBet)
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
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "charge",
      amount = amount,
      reason = reason,
      success = false,
      error = err or "not_ready",
      player = getPlayerName(),
      host = getHostName(),
      computerId = getComputerId(),
    })
    return false, nil
  end
  dbg("Charging player " .. amount .. " tokens: " .. reason)
  local result, txErr = ccvault.transfer("player", "host", amount, reason)
  if result then
    dbg("Charge OK, TX: " .. (result.txId or "?"))
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "charge",
      amount = amount,
      reason = reason,
      success = true,
      txId = result.txId,
      player = getPlayerName(),
      host = getHostName(),
      selfPlay = isSelfPlay(),
      computerId = getComputerId(),
    })
    return true, result.txId
  end
  -- Self-play: transfer() blocks same-account transfers, use transferSelf()
  if isSelfPlay() and ccvault.transferSelf then
    dbg("Self-play fallback for charge")
    local selfResult, selfErr = ccvault.transferSelf(amount, reason)
    if selfResult then
      dbg("Charge (self) OK, TX: " .. (selfResult.txId or "?"))
      writeTransactionAudit({
        timestamp = os.epoch("local"),
        kind = "charge",
        amount = amount,
        reason = reason,
        success = true,
        txId = selfResult.txId,
        player = getPlayerName(),
        host = getHostName(),
        selfPlay = true,
        computerId = getComputerId(),
      })
      return true, selfResult.txId
    end
    dbg("Charge (self) failed: " .. (selfErr or "unknown"))
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "charge",
      amount = amount,
      reason = reason,
      success = false,
      error = selfErr or "self_transfer_failed",
      player = getPlayerName(),
      host = getHostName(),
      selfPlay = true,
      computerId = getComputerId(),
    })
    return false, nil
  end
  dbg("Charge failed: " .. (txErr or "unknown"))
  writeTransactionAudit({
    timestamp = os.epoch("local"),
    kind = "charge",
    amount = amount,
    reason = reason,
    success = false,
    error = txErr or "transfer_failed",
    player = getPlayerName(),
    host = getHostName(),
    selfPlay = isSelfPlay(),
    computerId = getComputerId(),
  })
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
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "payout",
      amount = amount,
      reason = reason,
      success = false,
      error = err or "not_ready",
      player = getPlayerName(),
      host = getHostName(),
      computerId = getComputerId(),
    })
    return false, nil
  end
  dbg("Paying player " .. amount .. " tokens: " .. reason)
  local result, txErr = ccvault.transfer("host", "player", amount, reason)
  if result then
    dbg("Payout OK, TX: " .. (result.txId or "?"))
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "payout",
      amount = amount,
      reason = reason,
      success = true,
      txId = result.txId,
      player = getPlayerName(),
      host = getHostName(),
      selfPlay = isSelfPlay(),
      computerId = getComputerId(),
    })
    return true, result.txId
  end
  -- Self-play: transfer() blocks same-account transfers, use transferSelf()
  if isSelfPlay() and ccvault.transferSelf then
    dbg("Self-play fallback for payout")
    local selfResult, selfErr = ccvault.transferSelf(amount, reason)
    if selfResult then
      dbg("Payout (self) OK, TX: " .. (selfResult.txId or "?"))
      writeTransactionAudit({
        timestamp = os.epoch("local"),
        kind = "payout",
        amount = amount,
        reason = reason,
        success = true,
        txId = selfResult.txId,
        player = getPlayerName(),
        host = getHostName(),
        selfPlay = true,
        computerId = getComputerId(),
      })
      return true, selfResult.txId
    end
    dbg("Payout (self) failed: " .. (selfErr or "unknown"))
    writeTransactionAudit({
      timestamp = os.epoch("local"),
      kind = "payout",
      amount = amount,
      reason = reason,
      success = false,
      error = selfErr or "self_transfer_failed",
      player = getPlayerName(),
      host = getHostName(),
      selfPlay = true,
      computerId = getComputerId(),
    })
    return false, nil
  end
  dbg("Payout failed: " .. (txErr or "unknown"))
  writeTransactionAudit({
    timestamp = os.epoch("local"),
    kind = "payout",
    amount = amount,
    reason = reason,
    success = false,
    error = txErr or "transfer_failed",
    player = getPlayerName(),
    host = getHostName(),
    selfPlay = isSelfPlay(),
    computerId = getComputerId(),
  })
  return false, nil
end

--- Format a token amount for display.
-- @param tokens number
-- @return string  e.g. "50 tokens"
local function formatTokens(tokens)
  if tokens == 1 then return "1 token" end
  return tostring(tokens) .. " tokens"
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
  getLivePlayerName = getLivePlayerName,
  getAuthenticatedPlayerName = getAuthenticatedPlayerName,
  getHostName      = getHostName,
  getComputerId    = getComputerId,
  getPlayerBalance = getPlayerBalance,
  getHostBalance   = getHostBalance,
  getProtectedHostBalance = getProtectedHostBalance,
  getMaxBetLimit   = getMaxBetLimit,
  charge           = charge,
  payout           = payout,
  formatTokens     = formatTokens,
  DENOMINATIONS    = DENOMINATIONS,
  HOST_BALANCE_RESERVE = HOST_BALANCE_RESERVE,
  -- Session / verification
  getSessionInfo   = getSessionInfo,
  isSelfPlay       = isSelfPlay,
  verifyTransaction     = verifyTransaction,
  getTransactionHistory = getTransactionHistory,
}
