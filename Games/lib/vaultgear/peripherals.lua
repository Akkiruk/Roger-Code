local constants = require("lib.vaultgear.constants")
local monitorScale = require("lib.monitor_scale")

local M = {}

local function safeWrap(name)
  local ok, wrapped = pcall(peripheral.wrap, name)
  if ok then
    return wrapped
  end
  return nil
end

local function isMeBridgeType(peripheralType)
  return peripheralType == "meBridge" or peripheralType == "me_bridge"
end

local function inventoryEntry(name, wrapped)
  local peripheralType = peripheral.getType(name) or "unknown"
  local meBridge = isMeBridgeType(peripheralType)
  local canList = type(wrapped.list) == "function"
  local canGetItems = type(wrapped.getItems) == "function" or type(wrapped.listItems) == "function"
  local canPush = type(wrapped.pushItems) == "function"
  local canPull = type(wrapped.pullItems) == "function"
  local canExport = type(wrapped.exportItem) == "function" or type(wrapped.exportItemToPeripheral) == "function"
  local canImport = type(wrapped.importItem) == "function" or type(wrapped.importItemFromPeripheral) == "function"

  local entry = {
    name = name,
    type = peripheralType,
    is_me_bridge = meBridge,
    can_list = canList,
    can_scan = canList or (meBridge and canGetItems),
    can_detail = type(wrapped.getItemDetail) == "function",
    can_push = canPush,
    can_pull = canPull,
    can_export = canPush or (meBridge and canExport),
    can_import = canPull or (meBridge and canImport),
  }

  if not meBridge and type(wrapped.size) == "function" then
    local ok, size = pcall(function()
      return wrapped.size()
    end)
    if ok then
      entry.size = size
    end
  end

  entry.label = name .. " [" .. (meBridge and "ME Bridge" or entry.type) .. "]"
  return entry
end

function M.discover()
  local monitors = {}
  local inventories = {}
  local names = peripheral.getNames()
  table.sort(names)

  for _, name in ipairs(names) do
    local wrapped = safeWrap(name)
    if wrapped then
      local pType = peripheral.getType(name)
      if pType == "monitor" then
        monitors[#monitors + 1] = {
          name = name,
          type = "monitor",
          label = name,
        }
      end

      if type(wrapped.list) == "function" or isMeBridgeType(pType) then
        inventories[#inventories + 1] = inventoryEntry(name, wrapped)
      end
    end
  end

  return {
    monitors = monitors,
    inventories = inventories,
  }
end

function M.findInventory(discovery, name)
  for _, entry in ipairs((discovery and discovery.inventories) or {}) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

function M.findMonitor(discovery, name)
  for _, entry in ipairs((discovery and discovery.monitors) or {}) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

function M.bindMonitor(discovery, preferredName, textScale)
  local entry = nil
  if preferredName then
    entry = M.findMonitor(discovery, preferredName)
  end
  if not entry then
    entry = discovery.monitors[1]
  end
  if not entry then
    return nil, "No monitor found"
  end

  local monitor = safeWrap(entry.name)
  if not monitor then
    return nil, "Monitor could not be wrapped: " .. entry.name
  end

  local chosenScale = textScale
  if type(monitor.setTextScale) == "function" then
    if chosenScale ~= nil then
      pcall(function()
        monitor.setTextScale(chosenScale)
      end)
    else
      chosenScale = select(1, monitorScale.pickTextScale(monitor, {
        minWidth = constants.MIN_MONITOR_WIDTH,
        minHeight = constants.MIN_MONITOR_HEIGHT,
        maxScale = 2,
        fallback = 0.5,
      }))
    end
  end

  local width, height = monitor.getSize()
  return {
    name = entry.name,
    peripheral = monitor,
    width = width,
    height = height,
    text_scale = chosenScale,
  }
end

return M
