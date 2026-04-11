local constants = require("lib.vaultgear.constants")
local util = require("lib.vaultgear.util")

local M = {}

local function canonicalModifierKey(modifier)
  if type(modifier.group) == "string" and modifier.group ~= "" then
    return modifier.group:lower()
  end
  if type(modifier.identifier) == "string" and modifier.identifier ~= "" then
    return modifier.identifier:lower()
  end
  return "name:" .. util.normalizeKey(modifier.name or "unknown_modifier")
end

local function normalizeModifier(modifier, affixType)
  local value = modifier.value
  local numericValue = nil
  if type(value) == "number" then
    numericValue = value
  end

  local entry = {
    key = canonicalModifierKey(modifier),
    label = tostring(modifier.name or modifier.group or modifier.identifier or "Unknown Modifier"),
    affix_type = affixType,
    value = value,
    numeric_value = numericValue,
    tier = modifier.tier,
    group = modifier.group,
    identifier = modifier.identifier,
    legendary = modifier.legendary == true,
    crafted = modifier.crafted == true,
    frozen = modifier.frozen == true,
    greater = modifier.greater == true,
    abyssal = modifier.abyssal == true,
    corrupted = modifier.corrupted == true,
    imbued = modifier.imbued == true,
    ability_enhancement = modifier.abilityEnhancement == true,
  }
  entry.normalized_label = util.normalizeKey(entry.label)
  return entry
end

local function collectModifiers(item, mods, affixType)
  if type(mods) ~= "table" then
    return
  end

  for _, modifier in ipairs(mods) do
    local entry = normalizeModifier(modifier, affixType)
    item.modifiers.all[#item.modifiers.all + 1] = entry
    item.modifiers[affixType][#item.modifiers[affixType] + 1] = entry

    if not item.modifier_lookup[entry.key] then
      item.modifier_lookup[entry.key] = {}
    end
    item.modifier_lookup[entry.key][#item.modifier_lookup[entry.key] + 1] = entry

    if entry.legendary then
      item.has_legendary_modifier = true
    end
  end
end

local function deriveJewelSize(item)
  if item.item_type ~= "Jewel" then
    return nil
  end

  for _, modifier in ipairs(item.modifiers.all) do
    if modifier.numeric_value then
      if modifier.key:find("jewel_size", 1, true) or modifier.normalized_label == "size" then
        return modifier.numeric_value
      end
    end
  end

  return nil
end

local function deriveToolCapacity(item)
  if item.item_type ~= "Tool" then
    return nil
  end

  for _, modifier in ipairs(item.modifiers.all) do
    if modifier.numeric_value then
      if modifier.key:find("tool_capacity", 1, true) or modifier.normalized_label:find("capacity", 1, true) then
        return modifier.numeric_value
      end
    end
  end

  return nil
end

function M.normalize(slot, basic, detail, detailError)
  local registryName = (basic and basic.name) or (detail and detail.name) or "unknown"
  local isVaultItem = type(registryName) == "string" and registryName:find("the_vault:", 1, true) == 1
  local vaultData = detail and detail.vaultData or nil

  local item = {
    slot = slot,
    count = (basic and basic.count) or 1,
    registry_name = registryName,
    display_name = (detail and detail.displayName) or (vaultData and vaultData.name) or registryName,
    vault = isVaultItem and vaultData ~= nil,
    detail_error = detailError,
    detail_ok = detail ~= nil and detailError == nil,
    item_type = vaultData and vaultData.itemType or nil,
    supported_type = false,
    modifiers = {
      all = {},
      implicits = {},
      prefixes = {},
      suffixes = {},
    },
    modifier_lookup = {},
    has_legendary_modifier = false,
  }

  if not vaultData then
    return item
  end

  item.vault = true
  item.supported_type = constants.SUPPORTED_TYPE_SET[item.item_type] == true
  item.level = vaultData.level
  item.rarity = vaultData.rarity
  item.rarity_rank = constants.RARITY_ORDER[vaultData.rarity] or 0
  item.state = vaultData.state
  item.identified = vaultData.identified
  if item.identified == nil then
    item.identified = vaultData.state == "IDENTIFIED"
  end

  item.gear_type = vaultData.gearType
  item.equipment_slot = vaultData.equipmentSlot
  item.uses = vaultData.uses
  item.effect = vaultData.effect
  item.god = vaultData.god
  item.god_reputation = vaultData.godReputation

  item.is_soulbound = vaultData.isSoulbound == true
  item.is_unique = vaultData.uniqueKey ~= nil or vaultData.rarity == "UNIQUE"
  item.is_legendary = vaultData.isLegendary == true
  item.is_chaotic = vaultData.rarity == "CHAOTIC"

  if type(vaultData.repairSlots) == "table" then
    item.repair_total = vaultData.repairSlots.total
    item.repair_used = vaultData.repairSlots.used
    if type(item.repair_total) == "number" and type(item.repair_used) == "number" then
      item.repair_free = item.repair_total - item.repair_used
    end
  end

  if type(vaultData.durability) == "table" then
    item.durability_total = vaultData.durability.total
    item.durability_current = vaultData.durability.current
    if type(item.durability_total) == "number" and item.durability_total > 0 and type(item.durability_current) == "number" then
      item.durability_percent = (item.durability_current / item.durability_total) * 100
    end
  end

  if type(vaultData.craftingPotential) == "table" then
    item.crafting_potential_current = vaultData.craftingPotential.current
    item.crafting_potential_max = vaultData.craftingPotential.max
    if type(item.crafting_potential_current) == "number" and type(item.crafting_potential_max) == "number" and item.crafting_potential_max > 0 then
      item.crafting_potential_percent = (item.crafting_potential_current / item.crafting_potential_max) * 100
    end
  end

  item.prefix_slots = vaultData.prefixSlots
  item.suffix_slots = vaultData.suffixSlots

  collectModifiers(item, vaultData.implicits, "implicits")
  collectModifiers(item, vaultData.prefixes, "prefixes")
  collectModifiers(item, vaultData.suffixes, "suffixes")

  item.implicit_count = #item.modifiers.implicits
  item.prefix_count = #item.modifiers.prefixes
  item.suffix_count = #item.modifiers.suffixes

  if type(item.prefix_slots) == "number" then
    item.open_prefix_slots = item.prefix_slots - item.prefix_count
  end
  if type(item.suffix_slots) == "number" then
    item.open_suffix_slots = item.suffix_slots - item.suffix_count
  end

  item.is_legendary = item.is_legendary or item.has_legendary_modifier
  item.jewel_size = deriveJewelSize(item)
  item.tool_capacity = deriveToolCapacity(item)

  return item
end

function M.summaryLines(item)
  local lines = {}
  lines[#lines + 1] = item.display_name
  lines[#lines + 1] = (item.item_type or "Non-Vault") .. " | " .. (item.rarity or "-") .. " | Lv" .. tostring(item.level or "-")

  if item.item_type == "Gear" or item.item_type == "Tool" or item.item_type == "Etching" then
    if type(item.crafting_potential_current) == "number" and type(item.crafting_potential_max) == "number" then
      lines[#lines + 1] = "CP " .. item.crafting_potential_current .. "/" .. item.crafting_potential_max
    end
    if type(item.repair_free) == "number" and type(item.repair_total) == "number" then
      lines[#lines + 1] = "Repair " .. item.repair_free .. " free of " .. item.repair_total
    end
    if type(item.durability_percent) == "number" then
      lines[#lines + 1] = "Durability " .. util.formatPercent(item.durability_percent)
    end
  elseif item.item_type == "Jewel" and type(item.jewel_size) == "number" then
    lines[#lines + 1] = "Size " .. tostring(item.jewel_size)
  elseif (item.item_type == "Trinket" or item.item_type == "Charm") and type(item.uses) == "number" then
    lines[#lines + 1] = "Uses " .. tostring(item.uses)
  end

  if item.is_soulbound then
    lines[#lines + 1] = "Soulbound"
  elseif item.is_unique then
    lines[#lines + 1] = "Unique"
  elseif item.is_legendary then
    lines[#lines + 1] = "Legendary"
  end

  local shown = 0
  for _, modifier in ipairs(item.modifiers.all) do
    lines[#lines + 1] = modifier.label
    shown = shown + 1
    if shown >= 3 then
      break
    end
  end

  return lines
end

return M
