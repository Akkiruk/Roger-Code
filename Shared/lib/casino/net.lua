-- net.lua
-- What tables tell each other and the casino hub over rednet. All of it is optional: with no modem a table runs alone.
--   exposure  each table says what its open round could still cost its host, so tables owned by one host
--             do not promise the same tokens twice
--   round     each finished round goes to the hub for leaderboards and history
--   state     the hub answers with the shared jackpot and leaderboard
--   claim     a table about to pay the shared pot asks the hub what it may pay, and grant is the answer, so
--             two tables working from the same broadcast figure cannot both pay the same pot
-- Anyone on the network can say anything, and anti-cheat stays light: there is no signing here. Every message is only
-- checked for being the right shape and a believable size, so nonsense cannot stop a table or lift its limits.

local M = {}

M.PROTOCOL = "casino.v2"
M.HUB_STALE_MS = 30000
M.CLAIM_WAIT_MS = 1500
M.MAX_TOKENS = 1e9         -- no one amount on the network can honestly be this big: a thousand of the biggest transfers
M.MAX_POT = 1e7            -- the hub stops the pool here (casino_hub_rules.lua has the same figure)

local EXPOSURE_STALE_MS = 30000
local BEACON_MS = 10000
local MAX_LEADERS = 32
local MAX_NAME = 32

local opened = false
local others = {}          -- computer id -> { host, amount, at }
local mine = { host = nil, amount = 0 }
local lastBeacon = 0
local hub = nil            -- { jackpot, leaders, at }
local grants = {}          -- claim id -> tokens the hub granted

local function now()
  return os.epoch("utc")
end

--- Open every modem there is. Safe to call again whenever the peripherals change.
function M.open()
  opened = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      if not rednet.isOpen(name) then rednet.open(name) end
      opened = true
    end
  end
  return opened
end

local function isFinite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--- A count of tokens that could be real.
local function isAmount(value, limit)
  return isFinite(value) and value >= 0 and value <= limit
end

local function isId(value)
  return (type(value) == "string" and value ~= "" and #value <= MAX_NAME) or isFinite(value)
end

local function isLeader(entry)
  return type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" and #entry.name <= MAX_NAME
    and isFinite(entry.net) and math.abs(entry.net) <= M.MAX_TOKENS
end

function M.validExposure(message)
  return isAmount(message.amount, M.MAX_TOKENS) and type(message.host) == "string"
end

--- A hub's state has both parts in good order, or none of it is believed.
function M.validState(message)
  local leaders = message.leaders
  if not isAmount(message.jackpot, M.MAX_POT) or type(leaders) ~= "table" or #leaders > MAX_LEADERS then return false end
  for key, entry in pairs(leaders) do
    if type(key) ~= "number" or not isLeader(entry) then return false end
  end
  return true
end

function M.validGrant(message)
  return isId(message.id) and isAmount(message.amount, M.MAX_POT)
end

function M.send(kind, payload)
  if not opened then return end
  payload = payload or {}
  payload.kind = kind
  pcall(rednet.broadcast, payload, M.PROTOCOL)
end

--- Say what this table has at risk.
function M.setExposure(host, amount)
  mine.host, mine.amount = host, amount
  lastBeacon = now()
  M.send("exposure", { host = host, amount = amount })
end

--- What the host's other tables have at risk.
function M.otherExposure(host)
  local total, time = 0, now()
  for id, entry in pairs(others) do
    if time - entry.at > EXPOSURE_STALE_MS then
      others[id] = nil
    elseif entry.host == host then
      total = total + entry.amount
    end
  end
  return total
end

--- The hub's latest state, when it is alive.
function M.hub()
  if hub and now() - hub.at < M.HUB_STALE_MS then return hub end
  return nil
end

--- Ask the hub for part of the shared pot. Waits briefly, with worker running beside it, and swallows events meanwhile.
-- The hub answers the same id the same way, so a claim can be asked again until it answers (see Table:chaseClaims).
-- @param claim table  { id, game, player, amount }
-- @return number|nil  what may be paid, or nil if the hub did not answer in time
function M.claim(claim)
  if not opened then return nil end
  M.send("claim", claim)
  local timer = os.startTimer(M.CLAIM_WAIT_MS / 1000)
  while not grants[claim.id] do
    local event, id = os.pullEvent()
    if event == "timer" and id == timer then break end
  end
  return grants[claim.id]
end

--- What the hub has granted a claim so far, if it has answered.
function M.granted(id)
  return grants[id]
end

--- Rednet runs beside the game in its own coroutine.
function M.worker()
  while true do
    local _, sender, message, protocol = os.pullEvent("rednet_message")
    if protocol == M.PROTOCOL and type(message) == "table" then
      if message.kind == "exposure" and M.validExposure(message) then
        others[sender] = { host = message.host, amount = message.amount, at = now() }
      elseif message.kind == "state" and M.validState(message) then
        hub = { jackpot = message.jackpot, leaders = message.leaders, at = now() }
      elseif message.kind == "grant" and message.to == os.getComputerID() and M.validGrant(message) then
        grants[message.id] = message.amount
      end
    end
  end
end

--- Call now and then, so other tables keep seeing an open round.
function M.tick()
  if opened and mine.amount > 0 and now() - lastBeacon > BEACON_MS then
    M.setExposure(mine.host, mine.amount)
  end
end

return M
