-- net.lua
-- What tables tell each other and the casino hub over rednet. All of it is optional: with no modem a table runs alone.
--   exposure  each table says what its open round could still cost its host, so tables owned by one host
--             do not promise the same tokens twice
--   round     each finished round goes to the hub for leaderboards and history
--   state     the hub answers with the shared jackpot and leaderboard
--   claim     a table about to pay the shared pot asks the hub what it may pay, and grant is the answer, so
--             two tables working from the same broadcast figure cannot both pay the same pot

local M = {}

M.PROTOCOL = "casino.v2"
M.HUB_STALE_MS = 30000
M.CLAIM_WAIT_MS = 1500

local EXPOSURE_STALE_MS = 30000
local BEACON_MS = 10000

local opened = false
local others = {}          -- computer id -> { host, amount, at }
local mine = { host = nil, amount = 0 }
local lastBeacon = 0
local hub = nil            -- { jackpot, leaders, at }
local grants = {}          -- claim id -> tokens the hub granted

local function now()
  return os.epoch("utc")
end

function M.open()
  if opened then return true end
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      rednet.open(name)
      opened = true
    end
  end
  return opened
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
-- @param claim table  { id, game, player, amount }
-- @return number|nil  what may be paid, or nil if the hub did not answer
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

--- Rednet runs beside the game in its own coroutine.
function M.worker()
  while true do
    local _, sender, message, protocol = os.pullEvent("rednet_message")
    if protocol == M.PROTOCOL and type(message) == "table" then
      if message.kind == "exposure" and type(message.amount) == "number" then
        others[sender] = { host = message.host, amount = message.amount, at = now() }
      elseif message.kind == "state" then
        hub = { jackpot = message.jackpot, leaders = message.leaders, at = now() }
      elseif message.kind == "grant" and message.to == os.getComputerID() and type(message.amount) == "number" then
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
