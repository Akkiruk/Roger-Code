-- player_detection.lua (lib version)
-- Shared player detection for casino games.
-- Primary source: ccvault.getPlayerName() (server-authoritative, no peripheral needed).
-- Fallback: playerDetector peripheral for environments without CCVault.
-- Usage:
--   local players = require("lib.player_detection")
--   players.init(10)          -- detection range = 10 blocks
--   local name = players.refresh()
--   local name = players.getCurrent()

local peripherals = require("lib.peripherals")

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[player_detect] " .. msg) end
end

local detector    = nil
local range       = 10
local currentName = nil
local onChange     = nil   -- optional callback(newPlayer, oldPlayer)

--- Update currentName and fire onChange if it changed.
-- @param newName string|nil
-- @return string|nil
local function setIfChanged(newName)
  if newName and newName ~= currentName then
    local old = currentName
    currentName = newName
    dbg("Player changed: " .. tostring(newName) .. " (was " .. tostring(old) .. ")")
    if onChange then
      pcall(onChange, newName, old)
    end
  end
  return currentName
end

--- Initialize the player detection system.
-- CCVault is always checked first; the playerDetector peripheral is optional fallback.
-- @param detectionRange number?  Blocks to scan (default 10)
-- @return boolean  true if at least one detection source is available
local function init(detectionRange)
  range = detectionRange or range

  -- CCVault is always available if the mod is loaded — no init needed.
  local hasCCVault = ccvault and ccvault.getPlayerName

  detector = peripherals.find("playerDetector")
  if detector then
    dbg("Player detector found (fallback)")
  end

  if hasCCVault then
    dbg("CCVault player detection available (primary)")
    return true
  elseif detector then
    dbg("Using playerDetector peripheral only")
    return true
  end

  dbg("No player detection source available")
  return false
end

--- Perform a single detection pass and update the current player.
-- Prefers ccvault.getPlayerName() (knows exactly who right-clicked).
-- Falls back to playerDetector peripheral if CCVault has no player yet.
-- @return string|nil  The detected player name, or nil
local function refresh()
  -- Primary: CCVault knows who authenticated / right-clicked
  if ccvault and ccvault.getPlayerName then
    local name = ccvault.getPlayerName()
    if name then
      return setIfChanged(name)
    end
  end

  -- Fallback: playerDetector peripheral
  if detector then
    local ok, players = pcall(detector.getPlayersInRange, range)
    if ok and players and #players > 0 then
      return setIfChanged(players[1])
    end
  end

  return currentName  -- keep last-known
end

--- Get the current (cached) player name without a new detection pass.
-- @return string|nil
local function getCurrent()
  return currentName
end

--- Set the current player name manually (e.g. "Unknown" fallback).
-- @param name string|nil
local function setCurrent(name)
  currentName = name
end

--- Register a callback for player changes.
-- @param cb function(newPlayer, oldPlayer)
local function onPlayerChanged(cb)
  onChange = cb
end

--- Check if any detection source is available.
-- @return boolean
local function isAvailable()
  local hasCCVault = ccvault and ccvault.getPlayerName
  return hasCCVault or (detector ~= nil)
end

--- Refresh and return the active player, or nil if nobody is detected.
-- Convenience wrapper: calls refresh() and returns nil for empty/missing names.
-- @return string|nil
local function getActive()
  local name = refresh()
  if name and name ~= "" then return name end
  return nil
end

return {
  init             = init,
  refresh          = refresh,
  getCurrent       = getCurrent,
  setCurrent       = setCurrent,
  getActive        = getActive,
  onPlayerChanged  = onPlayerChanged,
  isAvailable      = isAvailable,
}
