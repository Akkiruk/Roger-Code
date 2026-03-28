local constants = require("lib.vaultgear.constants")
local util = require("lib.vaultgear.util")

local M = {}

local preset_index = nil

local function allSupportedTypes()
  return util.deepCopy(constants.SUPPORTED_TYPES)
end

local function makeRule()
  return util.deepCopy(constants.DEFAULT_RULE)
end

local function setTypes(rule, itemTypes)
  rule.item_types = util.deepCopy(itemTypes or {})
end

local function applyGeneralGear(rule, strictness)
  setTypes(rule, { "Gear", "Tool" })
  if strictness == "strict" then
    rule.identified_mode = "identified"
  end
end

local function applyHighValueGear(rule, strictness)
  setTypes(rule, { "Gear", "Tool" })
  rule.identified_mode = "identified"

  if strictness == "broad" then
    rule.min_rarity = "COMMON"
  elseif strictness == "strict" then
    rule.min_rarity = "EPIC"
    rule.min_crafting_potential = 20
  else
    rule.min_rarity = "RARE"
    rule.min_crafting_potential = 10
  end
end

local function applyUnidentifiedGear(rule)
  setTypes(rule, allSupportedTypes())
  rule.identified_mode = "unidentified"
end

local function applyJewelStorage(rule, strictness)
  setTypes(rule, { "Jewel" })
  if strictness == "strict" then
    rule.identified_mode = "identified"
  end
end

local function applySmallJewels(rule, strictness)
  setTypes(rule, { "Jewel" })
  rule.identified_mode = "identified"
  if strictness == "broad" then
    rule.max_jewel_size = 35
  elseif strictness == "strict" then
    rule.max_jewel_size = 15
  else
    rule.max_jewel_size = 25
  end
end

local function applyTrinkets(rule, strictness)
  setTypes(rule, { "Trinket" })
  if strictness == "normal" then
    rule.min_uses = 2
  elseif strictness == "strict" then
    rule.min_uses = 4
  end
end

local function applyCharms(rule, strictness)
  setTypes(rule, { "Charm" })
  if strictness == "normal" then
    rule.min_uses = 2
  elseif strictness == "strict" then
    rule.min_uses = 4
    rule.min_rarity = "COMMON"
  end
end

local function applyEtchings(rule, strictness)
  setTypes(rule, { "Etching" })
  if strictness == "normal" then
    rule.min_rarity = "COMMON"
  elseif strictness == "strict" then
    rule.min_rarity = "RARE"
    rule.identified_mode = "identified"
  end
end

local function applyOverflow(rule)
  setTypes(rule, allSupportedTypes())
end

local presets = {
  {
    id = "general_gear",
    label = "General Gear",
    short_label = "Gear",
    description = "Broad home for most gear and tools.",
    apply = applyGeneralGear,
  },
  {
    id = "high_value_gear",
    label = "High-Value Gear",
    short_label = "Value",
    description = "Higher rarity gear and tools first.",
    apply = applyHighValueGear,
  },
  {
    id = "unidentified_gear",
    label = "Unidentified Gear",
    short_label = "Unid",
    description = "Parking spot for unidentified vault items.",
    apply = applyUnidentifiedGear,
  },
  {
    id = "jewel_storage",
    label = "Jewel Storage",
    short_label = "Jewels",
    description = "General home for all jewels.",
    apply = applyJewelStorage,
  },
  {
    id = "small_jewels",
    label = "Small Jewels",
    short_label = "Small",
    description = "Selective home for low-size jewels.",
    apply = applySmallJewels,
  },
  {
    id = "trinkets",
    label = "Trinkets",
    short_label = "Trinkets",
    description = "Home for trinkets with optional use filtering.",
    apply = applyTrinkets,
  },
  {
    id = "charms",
    label = "Charms",
    short_label = "Charms",
    description = "Home for charms with optional use filtering.",
    apply = applyCharms,
  },
  {
    id = "etchings",
    label = "Etchings",
    short_label = "Etchings",
    description = "Home for etchings.",
    apply = applyEtchings,
  },
  {
    id = "overflow",
    label = "Overflow",
    short_label = "Overflow",
    description = "Catch-all home for supported vault items.",
    apply = applyOverflow,
  },
}

local function presetIndex()
  if preset_index ~= nil then
    return preset_index
  end

  preset_index = {}
  for _, entry in ipairs(presets) do
    preset_index[entry.id] = entry
  end
  return preset_index
end

function M.list()
  return presets
end

function M.find(presetId)
  return presetIndex()[presetId]
end

function M.label(presetId)
  local preset = M.find(presetId)
  if preset then
    return preset.label
  end
  return tostring(presetId or "Preset")
end

function M.shortLabel(presetId)
  local preset = M.find(presetId)
  if preset then
    return preset.short_label or preset.label
  end
  return tostring(presetId or "Preset")
end

function M.defaultRule()
  local rule = makeRule()
  setTypes(rule, allSupportedTypes())
  return rule
end

function M.apply(presetId, strictness)
  local preset = M.find(presetId) or M.find("overflow")
  local rule = M.defaultRule()
  rule.identified_mode = "any"
  rule.min_rarity = "ANY"
  rule.min_level = nil
  rule.max_level = nil
  rule.min_crafting_potential = nil
  rule.min_free_repair_slots = nil
  rule.min_durability_percent = nil
  rule.max_jewel_size = nil
  rule.min_uses = nil
  rule.allow_legendary = true
  rule.allow_soulbound = true
  rule.allow_unique = true
  preset.apply(rule, strictness or "normal")
  return rule
end

function M.summaryLines(storage)
  if not storage then
    return {
      "No storage selected.",
    }
  end

  if storage.role == "inbox" then
    return {
      "Inbox",
      "Watches this storage for new items and routes them into homes.",
    }
  end

  local rule = storage.rule or M.defaultRule()
  local types = rule.item_types or {}
  local typeText = #types > 0 and table.concat(types, "/") or "All supported types"
  local lines = {
    string.format("%s | %s | Priority %d", M.label(storage.preset_id), storage.strictness or "normal", storage.priority or 50),
    typeText,
  }

  if rule.identified_mode == "identified" then
    lines[#lines + 1] = "Identified only"
  elseif rule.identified_mode == "unidentified" then
    lines[#lines + 1] = "Unidentified only"
  end

  if rule.min_rarity and rule.min_rarity ~= "ANY" then
    lines[#lines + 1] = "Rarity " .. tostring(rule.min_rarity) .. "+"
  elseif rule.max_jewel_size then
    lines[#lines + 1] = "Jewel size <= " .. tostring(rule.max_jewel_size)
  elseif rule.min_uses then
    lines[#lines + 1] = "Uses >= " .. tostring(rule.min_uses)
  end

  return lines
end

function M.suggest(items)
  local supported = 0
  local counts = {}
  local unidentified = 0
  local rarityScore = 0
  local jewelCount = 0
  local jewelSizeSum = 0

  for _, entry in ipairs(items or {}) do
    local item = entry.item or entry
    if item and item.supported_type and item.item_type then
      supported = supported + 1
      counts[item.item_type] = (counts[item.item_type] or 0) + 1
      rarityScore = rarityScore + (constants.RARITY_ORDER[item.rarity] or 0)
      if item.identified == false then
        unidentified = unidentified + 1
      end
      if item.item_type == "Jewel" then
        jewelCount = jewelCount + 1
        if type(item.jewel_size) == "number" then
          jewelSizeSum = jewelSizeSum + item.jewel_size
        end
      end
    end
  end

  if supported == 0 then
    return {
      preset_id = "overflow",
      strictness = "broad",
      reason = "No supported vault items detected yet.",
    }
  end

  local bestType = nil
  local bestCount = 0
  for itemType, count in pairs(counts) do
    if count > bestCount then
      bestType = itemType
      bestCount = count
    end
  end

  if unidentified >= math.ceil(supported * 0.6) then
    return {
      preset_id = "unidentified_gear",
      strictness = "normal",
      reason = "Most sampled items are unidentified.",
    }
  end

  if bestType == "Jewel" then
    local averageSize = jewelCount > 0 and (jewelSizeSum / jewelCount) or 0
    if averageSize > 0 and averageSize <= 24 then
      return {
        preset_id = "small_jewels",
        strictness = averageSize <= 16 and "strict" or "normal",
        reason = "Most sampled items are smaller jewels.",
      }
    end
    return {
      preset_id = "jewel_storage",
      strictness = "normal",
      reason = "Most sampled items are jewels.",
    }
  end

  if bestType == "Trinket" then
    return {
      preset_id = "trinkets",
      strictness = "normal",
      reason = "Most sampled items are trinkets.",
    }
  end

  if bestType == "Charm" then
    return {
      preset_id = "charms",
      strictness = "normal",
      reason = "Most sampled items are charms.",
    }
  end

  if bestType == "Etching" then
    return {
      preset_id = "etchings",
      strictness = "normal",
      reason = "Most sampled items are etchings.",
    }
  end

  local averageRarity = supported > 0 and (rarityScore / supported) or 0
  if bestType == "Gear" or bestType == "Tool" then
    if averageRarity >= constants.RARITY_ORDER.RARE then
      return {
        preset_id = "high_value_gear",
        strictness = averageRarity >= constants.RARITY_ORDER.EPIC and "strict" or "normal",
        reason = "Sampled gear looks higher value.",
      }
    end
    return {
      preset_id = "general_gear",
      strictness = "normal",
      reason = "Sampled items look like general gear and tools.",
    }
  end

  return {
    preset_id = "overflow",
    strictness = "broad",
    reason = "Use this as a safe catch-all home.",
  }
end

return M
