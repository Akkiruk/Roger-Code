-- wallet.lua
-- Every ccvault call the casino makes. Nothing here can throw: ccvault errors come back as a reason.
-- Stakes are never taken up front. A round moves money once, when its result is known (see books.lua, the only caller of send).
-- Transfers name the seated player, so someone else tapping the monitor cannot get in the way.

local economy = require("lib.casino.economy")
local journal = require("lib.casino.journal")

local M = {}

local MAX_REASON = 64
local AUDIT_FILE = "casino_transactions.log"
local AUDIT_MAX_BYTES = 96000
local HISTORY_LIMIT = 50        -- the most ccvault.getTransactionHistory gives by default
local transferCap = 1000000     -- ccvault's limit on one transfer. lowerCap learns a smaller one from the server's answer

local function vault()
  return ccvault
end

-- Through economy.call, so a call that waits on the economy thread loses no event and cannot be cut short by a terminate
local function guarded(fn, ...)
  if type(fn) ~= "function" then return nil, "ccvault function missing" end
  local result = table.pack(economy.call(fn, ...))
  if not result[1] then return nil, tostring(result[2]) end
  return table.unpack(result, 2, result.n)
end

local function audit(entry)
  entry.at = os.epoch("utc")
  journal.appendLine(AUDIT_FILE, AUDIT_MAX_BYTES, textutils.serialize(entry, { compact = true }))
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

--- Whether this computer's terminal is locked: true, false, or nil when this server cannot say. Read-only.
function M.terminalLocked()
  local api = vault()
  if not api then return nil end
  local locked = guarded(api.isTerminalLocked)
  if type(locked) == "boolean" then return locked end
  return nil
end

--- A locked terminal opens only for its owner, and only the owner's own touch can lock it, so every touch comes here.
-- It does nothing for anyone else, or when there is nothing to do. Returns true when this touch locked the terminal.
function M.lockIfOwner(who)
  if not who or M.terminalLocked() ~= false or who ~= M.hostName() then return false end
  return guarded(vault().setTerminalLock, true) == true
end

--- Whether the attract screen should ask the owner to lock this table.
function M.wantsLock()
  return M.terminalLocked() == false and M.hostName() ~= nil
end

--- What the audit log says about a tag: true it moved, false it was refused, nil if it has no line for it.
-- The whole tag must match, so "#1a" can never be taken for "#1a2".
function M.wasSettled(tag)
  local found = nil
  for _, path in ipairs({ AUDIT_FILE .. ".bak", AUDIT_FILE }) do
    local handle = fs.exists(path) and fs.open(path, "r")
    local text = handle and handle.readAll() or ""
    if handle then handle.close() end
    for line in text:gmatch("[^\n]+") do
      local entry = line:find(tag, 1, true) and textutils.unserialize(line)
      if type(entry) == "table" and entry.reason == tag then found = entry.ok == true end
    end
  end
  return found
end

--- What the server's own ledger says about a tag, for a crash that left no audit line. Only the player in it, or the
-- host, can read it, and only with a fresh touch and an approved session.
-- @return true it moved, false it did not, nil if it cannot be told now. The second result is true when asking again
-- will not help: this server has no history call, or the transfer is older than everything the history reaches.
function M.ledgerShows(name, tag, at)
  local api = vault()
  if not api or type(api.getTransactionHistory) ~= "function" then return nil, true end
  local who = M.livePlayer()
  if not who or (who ~= name and who ~= M.hostName()) then return nil end
  local list = guarded(api.getTransactionHistory, HISTORY_LIMIT)
  if type(list) ~= "table" then return nil end
  for _, entry in ipairs(list) do
    -- A refused transfer is in the history as well, with the same reason. Moving your own money adds a marker to it
    if (entry.reason == tag or entry.reason == "[self-play] " .. tag) and not entry.rejectionReason then return true end
  end
  if #list < HISTORY_LIMIT then return false end
  local oldest = list[1] and list[1].timestamp
  if type(oldest) == "string" and oldest:sub(1, 19) < os.date("!%Y-%m-%dT%H:%M:%S", math.floor(at / 1000)) then return false end
  return nil, who == name
end

--- How many tokens the ledger shows moved under a tag, parts included, for a transfer another computer made. As ledgerShows: nil when
-- that cannot be told yet, and nil, true when it never can. Only the player it names can read it, on a computer they have touched.
function M.ledgerMoved(name, tag, at)
  local shown, never = M.ledgerShows(name, tag, at)
  if shown == nil then return nil, never end
  local list = guarded(vault().getTransactionHistory, HISTORY_LIMIT)
  if type(list) ~= "table" then return nil end
  local total = 0
  for _, entry in ipairs(list) do
    local reason = tostring(entry.reason):gsub("^%[self%-play%] ", "")
    if (reason == tag or reason:sub(1, #tag + 1) == tag .. "/") and not entry.rejectionReason then
      total = total + (tonumber(entry.amount) or 0)
    end
  end
  return total
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

--- The most one transfer can carry.
function M.maxTransfer()
  return transferCap
end

--- A server can set a smaller cap than the default. Returns true if this refusal taught us one, so the rest can go in parts.
function M.lowerCap(reason)
  local cap = tonumber(tostring(reason):match("exceeds maximum %((%d+)%)"))
  if cap and cap > 0 and cap < transferCap then
    transferCap = cap
    return true
  end
  return false
end

--- One transfer, named so nobody else's touch matters. Call this through books.move, which writes it down first.
-- @param name string   the player
-- @param amount number tokens to the player when positive, from them when negative
-- @param reason string a tag no other transfer has used
-- @return true, or nil and the reason
function M.send(name, amount, reason)
  reason = tostring(reason):sub(1, MAX_REASON)
  local target = "player:" .. name
  local txId, err
  if amount > 0 then
    txId, err = transfer("host", target, amount, reason, name)
  else
    txId, err = transfer(target, "host", -amount, reason, name)
  end
  if txId then return true end
  return nil, err
end

return M
