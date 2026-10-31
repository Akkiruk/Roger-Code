-- presence.lua
-- Whether the seated player is still at the table, from a player detector if the computer has one.
-- A detector call waits a server tick and throws away every event that arrives meanwhile, so only M.worker, in a
-- coroutine of its own, ever makes one. The table reads what it found.

local M = {}

M.RANGE = 12          -- blocks around the detector that count as at the table
local POLL_SECONDS = 1

local watched = nil   -- the name being followed
local awayAt = nil    -- when they were first missed
local known = false   -- whether the last poll gave an answer

local function now()
  return os.epoch("utc")
end

local function seen(players, name)
  for _, player in ipairs(players) do
    if player == name then return true end
  end
  return false
end

--- One look at the detector. Only call this from M.worker.
local function poll(name)
  local detector = peripheral.find("playerDetector")
  local ok, players = false, nil
  if detector then ok, players = pcall(detector.getPlayersInRange, M.RANGE) end
  if name ~= watched then
    watched, awayAt, known = name, nil, false
  end
  known = ok and type(players) == "table"
  if not known or seen(players, name) then
    awayAt = nil
  elseif not awayAt then
    awayAt = now()
  end
end

--- How long this player has been gone, in milliseconds: 0 while they are here, nil when nothing can tell.
function M.awayMs(name)
  if name ~= watched or not known then return nil end
  return awayAt and math.max(now() - awayAt, 1) or 0
end

--- Follows whoever seat() names, for as long as the table runs.
function M.worker(seat)
  while true do
    local name = seat()
    if name then poll(name) else watched, awayAt, known = nil, nil, false end
    sleep(POLL_SECONDS)
  end
end

return M
