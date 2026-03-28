local constants = require("lib.vaultgear.constants")
local routing = require("lib.vaultgear.routing")
local util = require("lib.vaultgear.util")

local M = {}

local function buildBaseProfile()
  return {
    enabled = true,
    miss_action = "keep",
    unidentified_mode = "keep",
    min_rarity = "ANY",
    min_level = nil,
    max_level = nil,
    min_crafting_potential = nil,
    min_free_repair_slots = nil,
    min_durability_percent = nil,
    max_jewel_size = nil,
    min_uses = nil,
    keep_legendary = false,
    keep_soulbound = false,
    keep_unique = false,
    wanted_modifier_mode = "any",
    wanted_modifiers = {},
    blocked_modifiers = {},
  }
end

function M.buildDefaultConfig()
  local profiles = {}

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    profiles[itemType] = buildBaseProfile()
  end

  profiles.Gear.keep_legendary = true
  profiles.Gear.keep_soulbound = true
  profiles.Gear.keep_unique = true
  profiles.Etching.keep_legendary = true

  return {
    schema_version = constants.CONFIG_SCHEMA_VERSION,
    monitor = {
      name = nil,
      text_scale = 0.5,
    },
    runtime = util.deepCopy(constants.DEFAULT_RUNTIME),
    routing = routing.normalizeRouting(nil),
    safety = util.deepCopy(constants.DEFAULT_SAFETY),
    type_profiles = profiles,
  }
end

function M.buildDefaultState()
  return {
    schema_version = constants.STATE_SCHEMA_VERSION,
    ui = {
      page = "dashboard",
      selected_type = "Gear",
      preview_selected = 1,
      selected_modifier_key = nil,
      selected_keep_key = nil,
      selected_block_key = nil,
      selected_destination_id = "route_1",
    },
    catalog = {},
  }
end

local function normalizeLoadedConfig(loaded)
  if type(loaded) ~= "table" then
    return nil
  end

  local normalized = util.deepCopy(loaded)
  normalized.routing = routing.normalizeRouting(routing.migrateLegacyRouting(normalized.routing))
  return normalized
end

local function normalizeLoadedState(loaded)
  if type(loaded) ~= "table" then
    return nil
  end

  local normalized = util.deepCopy(loaded)
  if type(normalized.ui) ~= "table" then
    normalized.ui = {}
  end
  if type(normalized.ui.selected_destination_id) ~= "string" or normalized.ui.selected_destination_id == "" then
    normalized.ui.selected_destination_id = "route_1"
  end
  return normalized
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

function M.loadConfig()
  local loaded = normalizeLoadedConfig(readLuaTable(constants.CONFIG_FILE))
  local merged = util.mergeDefaults(M.buildDefaultConfig(), loaded)
  merged.routing = routing.normalizeRouting(merged.routing)
  return merged
end

function M.saveConfig(config)
  config.schema_version = constants.CONFIG_SCHEMA_VERSION
  return saveLuaTable(constants.CONFIG_FILE, config)
end

function M.loadState()
  local loaded = normalizeLoadedState(readLuaTable(constants.STATE_FILE))
  return util.mergeDefaults(M.buildDefaultState(), loaded)
end

function M.saveState(state)
  state.schema_version = constants.STATE_SCHEMA_VERSION
  return saveLuaTable(constants.STATE_FILE, state)
end

return M
