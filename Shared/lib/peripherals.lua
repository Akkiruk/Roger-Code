-- peripherals.lua
-- Shared peripheral discovery and wrapping for all casino games.
-- Usage:
--   local peripherals = require("lib.peripherals")
--   local monitor = peripherals.find("monitor")
--   local barrel  = peripherals.wrap("front")

local DEBUG = settings.get("casino.debug") or false
local function dbg(msg)
  if DEBUG then print(os.time(), "[peripherals] " .. msg) end
end

--- Find a peripheral by type, checking direct connections first, then modems.
-- @param peripheralType string  The peripheral type to search for (e.g. "monitor", "chatBox")
-- @return peripheral|nil
local function findPeripheral(peripheralType)
  assert(type(peripheralType) == "string", "peripheralType must be a string")

  -- Direct connection first
  local direct = peripheral.find(peripheralType)
  if direct then
    dbg("Found direct " .. peripheralType)
    return direct
  end

  -- Search via modem
  local names = peripheral.getNames()
  for _, name in ipairs(names) do
    if peripheral.getType(name) == "modem" then
      dbg("Checking modem: " .. name)
      local ok, remote = pcall(peripheral.call, name, "getNamesRemote")
      if ok and remote then
        for _, remoteName in ipairs(remote) do
          local rType = peripheral.getType(remoteName)
          if rType and rType:find(peripheralType) then
            dbg("Found remote " .. peripheralType .. " at " .. remoteName)
            return peripheral.wrap(remoteName)
          end
        end
      end
    end
  end

  return nil
end

--- Wrap a peripheral on a named side, with an optional fallback to findPeripheral.
-- @param side     string  The side or name to wrap (e.g. "front", "right")
-- @param fallback string? If wrap fails, try findPeripheral with this type
-- @return peripheral|nil
local function safewrap(side, fallback)
  assert(type(side) == "string", "side must be a string")
  local p = peripheral.wrap(side)
  if p then
    dbg("Wrapped peripheral on " .. side)
    return p
  end
  if fallback then
    dbg("Wrap failed on " .. side .. ", falling back to find " .. fallback)
    return findPeripheral(fallback)
  end
  return nil
end

--- Require a peripheral to exist; error if not found.
-- @param side     string  The side or name to wrap
-- @param fallback string? Fallback type for findPeripheral
-- @param label    string? Human-readable label for error messages
-- @return peripheral
local function requirePeripheral(side, fallback, label)
  local p = safewrap(side, fallback)
  if not p then
    error("Required peripheral not found: " .. (label or fallback or side))
  end
  return p
end

return {
  find    = findPeripheral,
  wrap    = safewrap,
  require = requirePeripheral,
}
