local constants = require("lib.vaultgear.constants")
local planner = require("lib.vaultgear.planner")
local presets = require("lib.vaultgear.presets")
local util = require("lib.vaultgear.util")

local M = {}

local field_plans = {
  Gear = {
    { id = "min_rarity", kind = "choice", label = "Rarity" },
    { id = "allow_soulbound", kind = "toggle", label = "Soulbound" },
    { id = "allow_legendary", kind = "toggle", label = "Legendary" },
    { id = "allow_unique", kind = "toggle", label = "Unique" },
    { id = "allow_chaotic", kind = "toggle", label = "Chaotic" },
  },
  Tool = {
    { id = "min_rarity", kind = "choice", label = "Rarity" },
    { id = "allow_soulbound", kind = "toggle", label = "Soulbound" },
    { id = "allow_legendary", kind = "toggle", label = "Legendary" },
    { id = "allow_unique", kind = "toggle", label = "Unique" },
    { id = "allow_chaotic", kind = "toggle", label = "Chaotic" },
  },
  Jewel = {
    { id = "min_rarity", kind = "choice", label = "Rarity" },
    { id = "identified_mode", kind = "choice", label = "Identified" },
    { id = "allow_unique", kind = "toggle", label = "Unique" },
  },
  Trinket = {
    { id = "min_uses", kind = "stepper", label = "Min Uses" },
    { id = "allow_soulbound", kind = "toggle", label = "Soulbound" },
    { id = "allow_legendary", kind = "toggle", label = "Legendary" },
  },
  Charm = {
    { id = "min_rarity", kind = "choice", label = "Rarity" },
    { id = "min_uses", kind = "stepper", label = "Min Uses" },
    { id = "allow_soulbound", kind = "toggle", label = "Soulbound" },
  },
  Etching = {
    { id = "min_rarity", kind = "choice", label = "Rarity" },
    { id = "identified_mode", kind = "choice", label = "Identified" },
    { id = "allow_legendary", kind = "toggle", label = "Legendary" },
  },
}

local function contains(list, value)
  for _, entry in ipairs(list or {}) do
    if entry == value then
      return true
    end
  end
  return false
end

local function normalizeRarity(value)
  if value == nil or value == "" then
    return "ANY"
  end

  if value == "ANY" or value == "NONE" then
    return value
  end

  if constants.RARITY_ORDER[value] then
    return value
  end

  return "ANY"
end

local function normalizeIdentified(value)
  if value == "identified" or value == "unidentified" then
    return value
  end
  return "any"
end

local function normalizeUses(value)
  if value == nil or value == "" then
    return nil
  end

  local numeric = tonumber(value)
  if numeric == nil then
    return nil
  end

  return util.clamp(math.floor(numeric + 0.5), 1, constants.NUMERIC_FIELDS.min_uses.max)
end

local function defaultBooleans()
  return {
    allow_soulbound = false,
    allow_legendary = false,
    allow_unique = false,
    allow_chaotic = false,
  }
end

local function defaultEnabledFields()
  return {
    allow_legendary = true,
    allow_unique = true,
  }
end

local function fieldVisible(itemType, fieldId)
  for _, field in ipairs(field_plans[itemType] or {}) do
    if field.id == fieldId then
      return true
    end
  end
  return false
end

function M.itemTypes()
  return constants.SUPPORTED_TYPES
end

function M.fieldsForType(itemType)
  return field_plans[itemType] or {}
end

function M.primaryTypeFromRule(rule)
  for _, itemType in ipairs(rule and rule.item_types or {}) do
    if constants.SUPPORTED_TYPE_SET[itemType] then
      return itemType
    end
  end
  return "Gear"
end

function M.defaultConfig(itemType, priority)
  local chosenType = constants.SUPPORTED_TYPE_SET[itemType] and itemType or "Gear"
  local config = {
    priority = math.max(1, tonumber(priority) or 10),
    item_type = chosenType,
    min_rarity = "ANY",
    identified_mode = "any",
    min_uses = nil,
  }

  local booleans = defaultBooleans()
  for key, value in pairs(booleans) do
    config[key] = value
  end

  for key, value in pairs(defaultEnabledFields()) do
    if value and fieldVisible(chosenType, key) then
      config[key] = true
    end
  end

  return config
end

function M.normalizeConfig(config, fallbackPriority)
  local itemType = config and config.item_type or nil
  local normalized = util.mergeDefaults(M.defaultConfig(itemType, fallbackPriority), config or {})

  if not constants.SUPPORTED_TYPE_SET[normalized.item_type] then
    normalized.item_type = "Gear"
  end

  normalized.priority = math.max(1, tonumber(normalized.priority) or math.max(1, tonumber(fallbackPriority) or 10))
  normalized.min_rarity = normalizeRarity(normalized.min_rarity)
  normalized.identified_mode = normalizeIdentified(normalized.identified_mode)
  normalized.min_uses = normalizeUses(normalized.min_uses)
  normalized.allow_soulbound = normalized.allow_soulbound == true
  normalized.allow_legendary = normalized.allow_legendary == true
  normalized.allow_unique = normalized.allow_unique == true
  normalized.allow_chaotic = normalized.allow_chaotic == true

  if not contains({ "Trinket", "Charm" }, normalized.item_type) then
    normalized.min_uses = nil
  end

  return normalized
end

function M.fromStorage(storage)
  if not storage or storage.role ~= "home" then
    return nil
  end

  local rule = storage.rule or {}
  return M.normalizeConfig({
    priority = storage.priority,
    item_type = M.primaryTypeFromRule(rule),
    min_rarity = rule.min_rarity,
    identified_mode = rule.identified_mode,
    min_uses = rule.min_uses,
    allow_soulbound = rule.allow_soulbound == true,
    allow_legendary = rule.allow_legendary == true,
    allow_unique = rule.allow_unique == true,
    allow_chaotic = rule.allow_chaotic == true,
  }, storage.priority)
end

function M.fromSuggestion(suggestion, priority)
  local config = M.defaultConfig("Gear", priority)
  if not suggestion then
    return config
  end

  if suggestion.preset_id == "tools" then
    config.item_type = "Tool"
  elseif suggestion.preset_id == "jewel_storage" or suggestion.preset_id == "small_jewels" then
    config.item_type = "Jewel"
  elseif suggestion.preset_id == "trinkets" then
    config.item_type = "Trinket"
  elseif suggestion.preset_id == "charms" then
    config.item_type = "Charm"
  elseif suggestion.preset_id == "etchings" then
    config.item_type = "Etching"
  else
    config.item_type = "Gear"
  end

  if suggestion.preset_id == "high_value_gear" then
    if suggestion.strictness == "strict" then
      config.min_rarity = "EPIC"
    elseif suggestion.strictness == "broad" then
      config.min_rarity = "COMMON"
    else
      config.min_rarity = "RARE"
    end
  elseif suggestion.preset_id == "unidentified_gear" then
    config.identified_mode = "unidentified"
  elseif suggestion.preset_id == "charms" and suggestion.strictness == "strict" then
    config.min_rarity = "COMMON"
    config.min_uses = 4
  elseif suggestion.preset_id == "charms" then
    config.min_uses = 2
  elseif suggestion.preset_id == "trinkets" and suggestion.strictness == "strict" then
    config.min_uses = 4
  elseif suggestion.preset_id == "trinkets" then
    config.min_uses = 2
  elseif suggestion.preset_id == "etchings" and suggestion.strictness == "strict" then
    config.min_rarity = "RARE"
    config.identified_mode = "identified"
  elseif suggestion.preset_id == "etchings" then
    config.min_rarity = "COMMON"
  end

  return M.normalizeConfig(config, priority)
end

function M.presetForType(itemType)
  return presets.presetForType(itemType)
end

function M.buildRule(config)
  local normalized = M.normalizeConfig(config)
  local rule = presets.apply(M.presetForType(normalized.item_type), "normal")

  rule.item_types = { normalized.item_type }
  rule.min_rarity = normalized.min_rarity
  rule.identified_mode = normalized.identified_mode
  rule.min_uses = normalized.min_uses
  rule.max_jewel_size = nil
  rule.allow_soulbound = normalized.allow_soulbound
  rule.allow_legendary = normalized.allow_legendary
  rule.allow_unique = normalized.allow_unique
  rule.allow_chaotic = normalized.allow_chaotic

  return planner.normalizeRule(rule)
end

function M.summaryLines(config)
  local normalized = M.normalizeConfig(config)
  local lines = {
    string.format("Priority %d | %s", normalized.priority, normalized.item_type),
  }

  if normalized.min_rarity == "NONE" then
    lines[#lines + 1] = "Special only"
  elseif normalized.min_rarity ~= "ANY" then
    lines[#lines + 1] = "Rarity " .. tostring(normalized.min_rarity) .. "+"
  end

  if normalized.identified_mode == "identified" then
    lines[#lines + 1] = "Identified only"
  elseif normalized.identified_mode == "unidentified" then
    lines[#lines + 1] = "Unidentified only"
  end

  if normalized.min_uses ~= nil then
    lines[#lines + 1] = "Uses >= " .. tostring(normalized.min_uses)
  end

  local flags = {}
  if fieldVisible(normalized.item_type, "allow_soulbound") and normalized.allow_soulbound then
    flags[#flags + 1] = "soulbound"
  end
  if fieldVisible(normalized.item_type, "allow_legendary") and normalized.allow_legendary then
    flags[#flags + 1] = "legendary"
  end
  if fieldVisible(normalized.item_type, "allow_unique") and normalized.allow_unique then
    flags[#flags + 1] = "unique"
  end
  if fieldVisible(normalized.item_type, "allow_chaotic") and normalized.allow_chaotic then
    flags[#flags + 1] = "chaotic"
  end

  if #flags > 0 then
    lines[#lines + 1] = "Special: " .. table.concat(flags, ", ")
  end

  return lines
end

return M
