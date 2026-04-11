local constants = require("lib.vaultgear.constants")
local presets = require("lib.vaultgear.presets")
local util = require("lib.vaultgear.util")

local M = {}

local function contains(list, value)
  for _, entry in ipairs(list or {}) do
    if entry == value then
      return true
    end
  end
  return false
end

local function sortStorages(storages)
  table.sort(storages, function(a, b)
    local aPriority = tonumber(a.priority) or 999
    local bPriority = tonumber(b.priority) or 999
    if aPriority == bPriority then
      return tostring(a.inventory or a.id or "") < tostring(b.inventory or b.id or "")
    end
    return aPriority < bPriority
  end)
  return storages
end

function M.normalizeRule(rule)
  local normalized = util.mergeDefaults(constants.DEFAULT_RULE, rule or {})
  local types = {}
  local seen = {}

  for _, itemType in ipairs(normalized.item_types or {}) do
    if constants.SUPPORTED_TYPE_SET[itemType] and not seen[itemType] then
      types[#types + 1] = itemType
      seen[itemType] = true
    end
  end

  if #types == 0 then
    for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
      types[#types + 1] = itemType
    end
  end

  normalized.item_types = types

  if normalized.identified_mode ~= "identified" and normalized.identified_mode ~= "unidentified" then
    normalized.identified_mode = "any"
  end
  if normalized.min_rarity == nil or normalized.min_rarity == "" then
    normalized.min_rarity = "ANY"
  elseif normalized.min_rarity ~= "NONE" and not constants.RARITY_ORDER[normalized.min_rarity] then
    normalized.min_rarity = "ANY"
  end

  normalized.allow_legendary = normalized.allow_legendary == true
  normalized.allow_soulbound = normalized.allow_soulbound == true
  normalized.allow_unique = normalized.allow_unique == true
  normalized.allow_chaotic = normalized.allow_chaotic == true

  return normalized
end

function M.normalizeStorage(storage, index)
  local base = {
    id = "storage_" .. tostring(index or 1),
    inventory = nil,
    role = "home",
    enabled = true,
    preset_id = "overflow",
    strictness = "normal",
    priority = (index or 1) * 10,
    rescan = true,
    rule = presets.apply("overflow", "normal"),
  }

  local normalized = util.mergeDefaults(base, storage or {})
  if type(normalized.id) ~= "string" or normalized.id == "" then
    normalized.id = base.id
  end
  if type(normalized.inventory) ~= "string" or normalized.inventory == "" then
    normalized.inventory = nil
  end
  if normalized.role ~= "inbox" then
    normalized.role = "home"
  end
  normalized.enabled = normalized.enabled ~= false
  if normalized.strictness ~= "broad" and normalized.strictness ~= "strict" and normalized.strictness ~= "normal" then
    normalized.strictness = "normal"
  end
  normalized.priority = tonumber(normalized.priority) or base.priority
  normalized.rescan = normalized.role == "home" and normalized.rescan ~= false or false

  if normalized.role == "home" then
    if presets.find(normalized.preset_id) == nil then
      normalized.preset_id = "overflow"
    end
    normalized.rule = M.normalizeRule(normalized.rule or presets.apply(normalized.preset_id, normalized.strictness))
  else
    normalized.preset_id = nil
    normalized.rule = M.normalizeRule(normalized.rule or presets.defaultRule())
  end

  return normalized
end

function M.normalizeStorages(storages)
  local normalized = {}
  local seenInventory = {}

  for index, storage in ipairs(storages or {}) do
    local entry = M.normalizeStorage(storage, index)
    if entry.inventory and not seenInventory[entry.inventory] then
      normalized[#normalized + 1] = entry
      seenInventory[entry.inventory] = true
    end
  end

  return sortStorages(normalized)
end

function M.findStorageByInventory(storages, inventoryName)
  for index, storage in ipairs(storages or {}) do
    if storage.inventory == inventoryName then
      return storage, index
    end
  end
  return nil, nil
end

function M.findStorageById(storages, storageId)
  for index, storage in ipairs(storages or {}) do
    if storage.id == storageId then
      return storage, index
    end
  end
  return nil, nil
end

function M.nextStorageId(storages)
  local used = {}
  for _, storage in ipairs(storages or {}) do
    used[storage.id] = true
  end

  local index = 1
  while used["storage_" .. tostring(index)] do
    index = index + 1
  end
  return "storage_" .. tostring(index)
end

function M.nextHomePriority(storages)
  local maxPriority = 0
  for _, storage in ipairs(storages or {}) do
    if storage.role == "home" and storage.priority and storage.priority > maxPriority then
      maxPriority = storage.priority
    end
  end
  return maxPriority + 10
end

function M.createStorage(storages, inventoryName, role, presetId, strictness)
  local storage = {
    id = M.nextStorageId(storages),
    inventory = inventoryName,
    role = role == "inbox" and "inbox" or "home",
    enabled = true,
    priority = M.nextHomePriority(storages),
    rescan = role ~= "inbox",
  }

  if storage.role == "home" then
    storage.preset_id = presetId or "overflow"
    storage.strictness = strictness or "normal"
    storage.rule = presets.apply(storage.preset_id, storage.strictness)
  end

  return M.normalizeStorage(storage, #storages + 1)
end

function M.listHomes(storages, connectedSet)
  local homes = {}
  for _, storage in ipairs(storages or {}) do
    if storage.role == "home" and storage.enabled ~= false then
      if connectedSet == nil or connectedSet[storage.inventory] then
        homes[#homes + 1] = storage
      end
    end
  end
  return sortStorages(homes)
end

function M.listInboxes(storages, connectedSet)
  local inboxes = {}
  for _, storage in ipairs(storages or {}) do
    if storage.role == "inbox" and storage.enabled ~= false then
      if connectedSet == nil or connectedSet[storage.inventory] then
        inboxes[#inboxes + 1] = storage
      end
    end
  end
  return sortStorages(inboxes)
end

local function ruleHasThreshold(rule)
  if rule.min_rarity and rule.min_rarity ~= "ANY" then
    return true
  end
  return rule.min_level ~= nil
    or rule.max_level ~= nil
    or rule.min_crafting_potential ~= nil
    or rule.min_free_repair_slots ~= nil
    or rule.min_durability_percent ~= nil
    or rule.max_jewel_size ~= nil
    or rule.min_uses ~= nil
end

function M.matchStorage(storage, item)
  local rule = storage and storage.rule or nil
  if storage == nil or storage.role ~= "home" or storage.enabled == false then
    return false, { "Storage not active." }
  end
  if storage.inventory == nil or storage.inventory == "" then
    return false, { "Storage has no inventory." }
  end
  if not item or not item.vault or not item.supported_type then
    return false, { "Not a supported vault item." }
  end
  if not contains(rule and rule.item_types or {}, item.item_type) then
    return false, { "Wrong item type." }
  end
  if rule.identified_mode == "identified" and item.identified ~= true then
    return false, { "Needs identified items." }
  end
  if rule.identified_mode == "unidentified" and item.identified ~= false then
    return false, { "Needs unidentified items." }
  end

  if item.is_soulbound and rule.allow_soulbound then
    return true, { "Soulbound override." }
  end
  if item.is_unique and rule.allow_unique then
    return true, { "Unique override." }
  end
  if item.is_legendary and rule.allow_legendary then
    return true, { "Legendary override." }
  end
  if item.is_chaotic and rule.allow_chaotic then
    return true, { "Chaotic override." }
  end

  if rule.min_rarity and rule.min_rarity ~= "ANY" then
    if rule.min_rarity == "NONE" then
      return false, { "Normal rarity matching disabled." }
    end
    local itemRank = constants.RARITY_ORDER[item.rarity] or 0
    local requiredRank = constants.RARITY_ORDER[rule.min_rarity] or 0
    if itemRank < requiredRank then
      return false, { "Below rarity floor." }
    end
  end
  if rule.min_level ~= nil and (type(item.level) ~= "number" or item.level < rule.min_level) then
    return false, { "Below min level." }
  end
  if rule.max_level ~= nil and (type(item.level) ~= "number" or item.level > rule.max_level) then
    return false, { "Above max level." }
  end
  if rule.min_crafting_potential ~= nil then
    if type(item.crafting_potential_current) ~= "number" or item.crafting_potential_current < rule.min_crafting_potential then
      return false, { "Below CP floor." }
    end
  end
  if rule.min_free_repair_slots ~= nil then
    if type(item.repair_free) ~= "number" or item.repair_free < rule.min_free_repair_slots then
      return false, { "Not enough repair slots." }
    end
  end
  if rule.min_durability_percent ~= nil then
    if type(item.durability_percent) ~= "number" or item.durability_percent < rule.min_durability_percent then
      return false, { "Durability too low." }
    end
  end
  if rule.max_jewel_size ~= nil then
    if type(item.jewel_size) ~= "number" or item.jewel_size > rule.max_jewel_size then
      return false, { "Jewel size too large." }
    end
  end
  if rule.min_uses ~= nil then
    if type(item.uses) ~= "number" or item.uses < rule.min_uses then
      return false, { "Uses too low." }
    end
  end

  if not ruleHasThreshold(rule) and rule.identified_mode == "any" then
    return true, { "Matches preset home." }
  end

  return true, { "Matches home rules." }
end

function M.pickDestination(storages, item, currentInventory)
  local matches = {}
  for _, storage in ipairs(storages or {}) do
    local matched, reasons = M.matchStorage(storage, item)
    if matched then
      matches[#matches + 1] = {
        storage = storage,
        reasons = reasons,
      }
    end
  end

  table.sort(matches, function(a, b)
    local aPriority = tonumber(a.storage.priority) or 999
    local bPriority = tonumber(b.storage.priority) or 999
    if aPriority == bPriority then
      return tostring(a.storage.inventory or "") < tostring(b.storage.inventory or "")
    end
    return aPriority < bPriority
  end)

  if #matches == 0 then
    return nil
  end

  if currentInventory then
    local currentMatch = nil
    for _, match in ipairs(matches) do
      if match.storage.inventory == currentInventory then
        currentMatch = match
        break
      end
    end
    if currentMatch then
      local bestPriority = tonumber(matches[1].storage.priority) or 999
      local currentPriority = tonumber(currentMatch.storage.priority) or 999
      if currentPriority == bestPriority then
        return currentMatch
      end
    end
  end

  return matches[1]
end

function M.summaryLine(storage)
  if not storage then
    return "No storage selected."
  end

  if storage.role == "inbox" then
    return "Inbox for newly dropped items."
  end

  local lines = presets.summaryLines(storage)
  return table.concat(lines, " | ")
end

return M
