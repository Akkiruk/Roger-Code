local constants = require("lib.vaultgear.constants")
local planner = require("lib.vaultgear.planner")
local presets = require("lib.vaultgear.presets")
local util = require("lib.vaultgear.util")

local M = {}

function M.buildDefaultConfig()
  return {
    schema_version = constants.CONFIG_SCHEMA_VERSION,
    monitor = {
      name = nil,
      text_scale = 0.5,
    },
    runtime = util.deepCopy(constants.DEFAULT_RUNTIME),
    storages = {},
  }
end

function M.buildDefaultState()
  return {
    schema_version = constants.STATE_SCHEMA_VERSION,
    ui = {
      page = "overview",
      selected_inventory = nil,
      advanced = false,
    },
    runtime = {
      inbox_cursor = 1,
      inbox_slot = 0,
      repair_cursor = 1,
      repair_slot = 0,
      unresolved_scan = 0,
      current_mode = "idle",
      current_target = nil,
      last_summary = "Idle",
      last_reason = nil,
      route_failures = {},
      bridge_skip = {},
    },
    catalog = {},
  }
end

local function serializeTable(data)
  return "return " .. textutils.serialize(data)
end

local function readLuaTable(path)
  if not fs.exists(path) then
    return nil
  end

  local ok, data = pcall(dofile, path)
  if not ok or type(data) ~= "table" then
    return nil
  end

  return data
end

local function readRawFile(path)
  if not fs.exists(path) then
    return nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end

  local content = handle.readAll()
  handle.close()
  return content
end

local function atomicWrite(path, content)
  local tempPath = path .. ".tmp"
  local handle = fs.open(tempPath, "w")
  if not handle then
    return false, "Could not open temp file for " .. path
  end

  handle.write(content)
  handle.close()

  if fs.exists(path) then
    fs.delete(path)
  end
  fs.move(tempPath, path)
  return true
end

local function saveLuaTable(path, data)
  return atomicWrite(path, serializeTable(data))
end

local function migrateLegacyConfig(loaded)
  local migrated = M.buildDefaultConfig()
  if type(loaded) ~= "table" then
    return migrated
  end

  if type(loaded.monitor) == "table" then
    migrated.monitor = util.mergeDefaults(migrated.monitor, loaded.monitor)
  end

  if type(loaded.runtime) == "table" then
    migrated.runtime.enabled = loaded.runtime.enabled == true
    migrated.runtime.scan_interval = tonumber(loaded.runtime.scan_interval) or migrated.runtime.scan_interval
  end

  local storages = {}
  local routing = loaded.routing
  if type(routing) == "table" then
    if type(routing.input) == "string" and routing.input ~= "" then
      storages[#storages + 1] = planner.createStorage(storages, routing.input, "inbox", nil, nil)
    end

    for _, destination in ipairs(routing.destinations or {}) do
      if type(destination.inventory) == "string" and destination.inventory ~= "" then
        local storage = planner.createStorage(storages, destination.inventory, "home", "overflow", "broad")
        storage.priority = destination.match_action == "keep" and 20 or (destination.match_action == "discard" and 90 or storage.priority)
        storage.rescan = destination.enabled ~= false
        storage.enabled = destination.enabled ~= false
        storages[#storages + 1] = planner.normalizeStorage(storage, #storages + 1)
      end
    end
  end

  migrated.storages = planner.normalizeStorages(storages)
  return migrated
end

local function normalizeLoadedConfig(loaded)
  if type(loaded) ~= "table" then
    return M.buildDefaultConfig()
  end

  if tonumber(loaded.schema_version) == constants.CONFIG_SCHEMA_VERSION and type(loaded.storages) == "table" then
    local normalized = util.mergeDefaults(M.buildDefaultConfig(), loaded)
    normalized.storages = planner.normalizeStorages(normalized.storages)
    return normalized
  end

  return migrateLegacyConfig(loaded)
end

local function loadConfigInternal(allowDefaultOnInvalid)
  local loaded = readLuaTable(constants.CONFIG_FILE)
  if loaded == nil then
    if fs.exists(constants.CONFIG_FILE) and not allowDefaultOnInvalid then
      return nil, "Invalid config file"
    end
    loaded = nil
  end

  local normalized = normalizeLoadedConfig(loaded)
  normalized.runtime = util.mergeDefaults(constants.DEFAULT_RUNTIME, normalized.runtime)
  normalized.runtime.move_batch = nil
  normalized.runtime.repair_batch = nil
  normalized.storages = planner.normalizeStorages(normalized.storages)
  return normalized, nil
end

local function normalizeLoadedState(loaded)
  if type(loaded) ~= "table" then
    return M.buildDefaultState()
  end

  local normalized = util.mergeDefaults(M.buildDefaultState(), loaded)
  if type(normalized.ui.selected_inventory) ~= "string" or normalized.ui.selected_inventory == "" then
    normalized.ui.selected_inventory = nil
  end
  normalized.ui.advanced = normalized.ui.advanced == true
  normalized.runtime.inbox_cursor = tonumber(normalized.runtime.inbox_cursor) or 1
  normalized.runtime.inbox_slot = tonumber(normalized.runtime.inbox_slot) or 0
  normalized.runtime.repair_cursor = tonumber(normalized.runtime.repair_cursor) or 1
  normalized.runtime.repair_slot = tonumber(normalized.runtime.repair_slot) or 0
  normalized.runtime.unresolved_scan = tonumber(normalized.runtime.unresolved_scan) or 0
  normalized.runtime.current_mode = tostring(normalized.runtime.current_mode or "idle")
  normalized.runtime.current_target = normalized.runtime.current_target and tostring(normalized.runtime.current_target) or nil
  normalized.runtime.last_summary = tostring(normalized.runtime.last_summary or "Idle")
  normalized.runtime.last_reason = normalized.runtime.last_reason and tostring(normalized.runtime.last_reason) or nil
  if type(normalized.runtime.route_failures) ~= "table" then
    normalized.runtime.route_failures = {}
  end
  if type(normalized.runtime.bridge_skip) ~= "table" then
    normalized.runtime.bridge_skip = {}
  end
  return normalized
end

function M.loadConfig()
  local normalized = loadConfigInternal(true)
  return normalized
end

function M.tryLoadConfig()
  return loadConfigInternal(false)
end

function M.saveConfig(config)
  config.schema_version = constants.CONFIG_SCHEMA_VERSION
  if type(config.runtime) == "table" then
    config.runtime.move_batch = nil
    config.runtime.repair_batch = nil
  end
  config.storages = planner.normalizeStorages(config.storages)
  return saveLuaTable(constants.CONFIG_FILE, config)
end

function M.loadState()
  return normalizeLoadedState(readLuaTable(constants.STATE_FILE))
end

function M.readConfigSnapshot()
  return readRawFile(constants.CONFIG_FILE)
end

function M.saveState(state)
  state.schema_version = constants.STATE_SCHEMA_VERSION
  return saveLuaTable(constants.STATE_FILE, state)
end

function M.applyPreset(storage, presetId, strictness)
  if not storage then
    return
  end
  storage.preset_id = presetId
  storage.strictness = strictness or storage.strictness or "normal"
  storage.rule = presets.apply(storage.preset_id, storage.strictness)
end

return M
