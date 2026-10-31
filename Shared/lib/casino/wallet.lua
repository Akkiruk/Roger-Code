-- wallet.lua
-- Every ccvault call the casino makes. Nothing here can throw: ccvault errors come back as a reason.
-- Stakes are never taken up front. A round moves money once, when its result is known (see settle).
-- Transfers name the seated player, so someone else tapping the monitor cannot get in the way.

local M = {}

local MAX_REASON = 64
local AUDIT_FILE = "casino_transactions.log"
local AUDIT_MAX_BYTES = 200000

M.HOST_RESERVE = 2000

local function vault()
  return ccvault
end

local function guarded(fn, ...)
  if type(fn) ~= "function" then return nil, "ccvault function missing" end
  local result = table.pack(pcall(fn, ...))
  if not result[1] then return nil, tostring(result[2]) end
  return table.unpack(result, 2, result.n)
end

local function audit(entry)
  if fs.exists(AUDIT_FILE) and fs.getSize(AUDIT_FILE) > AUDIT_MAX_BYTES then
    if fs.exists(AUDIT_FILE .. ".bak") then fs.delete(AUDIT_FILE .. ".bak") end
    fs.move(AUDIT_FILE, AUDIT_FILE .. ".bak")
  end
  local handle = fs.open(AUDIT_FILE, "a")
  if handle then
    entry.at = os.epoch("utc")
    handle.writeLine(textutils.serialize(entry, { compact = true }))
    handle.close()
  end
end

function M.available()
  local api = vault()
  if not api then return false end
  return guarded(api.isAvailable) == true
end

--- Who last right-clicked, by name.
function M.livePlayer()
  local api = vault()
  if not api then return nil end
  return guarded(api.getPlayerName)
end

function M.hostName()
  local api = vault()
  if not api then return nil end
  return guarded(api.getHostName)
end

--- The host's name, or their UUID while offline. getPlayerBalance takes either.
local function balanceOf(who)
  local api = vault()
  if not api or not who then return nil, "no such player" end
  for _ = 1, 2 do
    local balance, err = guarded(api.getPlayerBalance, who)
    if balance then return balance end
    if not tostring(err):find("try again", 1, true) then return nil, err end
  end
  return nil, "still looking up " .. tostring(who)
end

--- A player's balance. Read-only: it needs no approval and no fresh touch, so it is safe at any moment.
function M.balance(name)
  return balanceOf(name)
end

function M.hostBalance()
  return balanceOf(M.hostName())
end

function M.isApproved()
  local api = vault()
  if not api then return false end
  return guarded(api.isAuthenticated) == true
end

function M.requestApproval()
  local api = vault()
  if not api then return nil, "economy offline" end
  return guarded(api.requestAuth)
end

function M.isSelfPlay(name)
  return name ~= nil and M.hostName() == name
end

--- Owners keep other people out of a table's terminal. Called with the owner at the monitor.
function M.lockTerminal()
  local api = vault()
  if not api or not api.setTerminalLock then return end
  if guarded(api.isTerminalLocked) ~= true then
    guarded(api.setTerminalLock, true)
  end
end

--- Whether a transfer with this tag already happened, for a reboot that landed in the middle of one.
function M.wasSettled(tag)
  if not fs.exists(AUDIT_FILE) then return false end
  local handle = fs.open(AUDIT_FILE, "r")
  if not handle then return false end
  local text = handle.readAll() or ""
  handle.close()
  for line in text:gmatch("[^\n]+") do
    if line:find(tag, 1, true) and line:find("ok=true", 1, true) then return true end
  end
  return false
end

--- Whether a failure may heal by itself: the player only has to come back and touch the table.
local function isRetryable(reason)
  reason = tostring(reason)
  return reason:find("recently", 1, true) ~= nil
    or reason:find("not online", 1, true) ~= nil
    or reason:find("approved", 1, true) ~= nil
    or reason:find("interact", 1, true) ~= nil
    or reason:find("authenticated", 1, true) ~= nil
    or reason:find("reboot it", 1, true) ~= nil
end
M.isRetryable = isRetryable

local function transfer(from, to, amount, reason, name)
  local api = vault()
  if not api then return nil, "economy offline" end
  local result, err = guarded(api.transfer, from, to, amount, reason)
  if not result and tostring(err):find("yourself", 1, true) then
    -- The owner playing their own table: a real pass through the ledger that moves nothing
    result, err = guarded(api.transferSelf, amount, reason)
  end
  audit({ from = from, to = to, amount = amount, reason = reason, player = name, ok = result ~= nil,
    txId = result and result.txId, err = err })
  if result then return result.txId end
  return nil, err
end

--- Move one round's net result. Whatever cannot move now comes back as `left`, which the caller keeps as owed.
-- A player who wins is paid in full or not at all. A player who owes more than they hold pays what they have.
-- @param name string  the seated player
-- @param net number   tokens to the player when positive, from them when negative
-- @param reason string
-- @return moved number, left number, err string|nil
function M.settle(name, net, reason)
  net = math.floor(net + 0.5)
  if net == 0 then return 0, 0, nil end
  reason = tostring(reason):sub(1, MAX_REASON)
  local target = "player:" .. name

  if net > 0 then
    local txId, err = transfer("host", target, net, reason, name)
    if txId then return net, 0, nil end
    return 0, net, err
  end

  local owes = -net
  local have = balanceOf(name) or owes
  local take = math.min(owes, have)
  if take <= 0 then return 0, net, "insufficient balance" end
  local txId, err = transfer(target, "host", take, reason, name)
  if txId then
    local left = owes - take
    return -take, -left, left > 0 and "insufficient balance" or nil
  end
  return 0, net, err
end

return M
