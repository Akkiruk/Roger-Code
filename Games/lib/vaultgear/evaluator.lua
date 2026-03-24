local constants = require("lib.vaultgear.constants")

local M = {}

local function addReason(reasons, text)
  reasons[#reasons + 1] = text
end

local function hasMatchingModifier(item, entries)
  if type(entries) ~= "table" or #entries == 0 then
    return true, {}
  end

  local matched = {}
  for _, entry in ipairs(entries) do
    if item.modifier_lookup[entry.key] then
      matched[#matched + 1] = entry.label or entry.key
    end
  end

  return #matched > 0, matched
end

local function hasAllMatchingModifiers(item, entries)
  if type(entries) ~= "table" or #entries == 0 then
    return true, {}
  end

  local matched = {}
  for _, entry in ipairs(entries) do
    if item.modifier_lookup[entry.key] then
      matched[#matched + 1] = entry.label or entry.key
    else
      return false, matched
    end
  end

  return true, matched
end

local function activeFilters(profile)
  if not profile then
    return false
  end

  if profile.min_rarity and profile.min_rarity ~= "ANY" then return true end
  if profile.min_level ~= nil then return true end
  if profile.max_level ~= nil then return true end
  if profile.min_crafting_potential ~= nil then return true end
  if profile.min_free_repair_slots ~= nil then return true end
  if profile.min_durability_percent ~= nil then return true end
  if profile.max_jewel_size ~= nil then return true end
  if profile.min_uses ~= nil then return true end
  if profile.wanted_modifiers and #profile.wanted_modifiers > 0 then return true end
  if profile.blocked_modifiers and #profile.blocked_modifiers > 0 then return true end
  return false
end

local function passRarity(profile, item)
  if not profile.min_rarity or profile.min_rarity == "ANY" then
    return true
  end
  local itemRank = constants.RARITY_ORDER[item.rarity] or 0
  local requiredRank = constants.RARITY_ORDER[profile.min_rarity] or 0
  return itemRank >= requiredRank
end

function M.evaluate(item, config)
  local reasons = {}

  if not item.vault then
    addReason(reasons, "Non-vault fallback")
    return {
      action = config.safety.non_vault_action,
      reasons = reasons,
      matched = false,
    }
  end

  if not item.supported_type then
    addReason(reasons, "Unsupported vault type: " .. tostring(item.item_type))
    return {
      action = config.safety.unsupported_vault_action,
      reasons = reasons,
      matched = false,
    }
  end

  if item.detail_error then
    addReason(reasons, "Detail read failed")
    return {
      action = config.safety.detail_error_action,
      reasons = reasons,
      matched = false,
    }
  end

  local profile = config.type_profiles[item.item_type]
  if not profile or profile.enabled == false then
    addReason(reasons, "Profile disabled")
    return {
      action = config.safety.unsupported_vault_action,
      reasons = reasons,
      matched = false,
    }
  end

  if item.is_soulbound and profile.keep_soulbound then
    addReason(reasons, "Soulbound safety keep")
    return {
      action = "keep",
      reasons = reasons,
      matched = true,
    }
  end

  if not item.identified then
    if profile.unidentified_mode == "keep" then
      addReason(reasons, "Unidentified -> keep")
      return {
        action = "keep",
        reasons = reasons,
        matched = true,
      }
    end
    if profile.unidentified_mode == "discard" then
      addReason(reasons, "Unidentified -> discard")
      return {
        action = "discard",
        reasons = reasons,
        matched = false,
      }
    end
    addReason(reasons, "Unidentified basic eval")
  end

  local blocked = false
  if profile.blocked_modifiers and #profile.blocked_modifiers > 0 then
    local matched, blockMatches = hasMatchingModifier(item, profile.blocked_modifiers)
    if matched then
      blocked = true
      addReason(reasons, "Blocked mod: " .. table.concat(blockMatches, ", "))
    end
  end

  if blocked then
    return {
      action = "discard",
      reasons = reasons,
      matched = false,
    }
  end

  if item.is_unique and profile.keep_unique then
    addReason(reasons, "Unique keep")
    return {
      action = "keep",
      reasons = reasons,
      matched = true,
    }
  end

  if item.is_legendary and profile.keep_legendary then
    addReason(reasons, "Legendary keep")
    return {
      action = "keep",
      reasons = reasons,
      matched = true,
    }
  end

  if not passRarity(profile, item) then
    addReason(reasons, "Below rarity floor")
  end

  if profile.min_level ~= nil and (type(item.level) ~= "number" or item.level < profile.min_level) then
    addReason(reasons, "Below min level")
  end

  if profile.max_level ~= nil and (type(item.level) ~= "number" or item.level > profile.max_level) then
    addReason(reasons, "Above max level")
  end

  if profile.min_crafting_potential ~= nil then
    if type(item.crafting_potential_current) ~= "number" or item.crafting_potential_current < profile.min_crafting_potential then
      addReason(reasons, "Below CP floor")
    end
  end

  if profile.min_free_repair_slots ~= nil then
    if type(item.repair_free) ~= "number" or item.repair_free < profile.min_free_repair_slots then
      addReason(reasons, "Not enough repair slots")
    end
  end

  if profile.min_durability_percent ~= nil then
    if type(item.durability_percent) ~= "number" or item.durability_percent < profile.min_durability_percent then
      addReason(reasons, "Durability too low")
    end
  end

  if profile.max_jewel_size ~= nil then
    if type(item.jewel_size) ~= "number" or item.jewel_size > profile.max_jewel_size then
      addReason(reasons, "Jewel size too large")
    end
  end

  if profile.min_uses ~= nil then
    if type(item.uses) ~= "number" or item.uses < profile.min_uses then
      addReason(reasons, "Uses too low")
    end
  end

  local wantedMatched = true
  if profile.wanted_modifiers and #profile.wanted_modifiers > 0 then
    if profile.wanted_modifier_mode == "all" then
      wantedMatched = hasAllMatchingModifiers(item, profile.wanted_modifiers)
    else
      wantedMatched = hasMatchingModifier(item, profile.wanted_modifiers)
    end

    if not wantedMatched then
      addReason(reasons, "Wanted modifiers missing")
    else
      addReason(reasons, "Wanted modifiers matched")
    end
  end

  local matched = #reasons == 0 or (#reasons == 1 and reasons[1] == "Wanted modifiers matched")
  if not activeFilters(profile) then
    matched = false
    addReason(reasons, "No active keep filters")
  end

  if matched then
    addReason(reasons, "Profile matched")
    return {
      action = "keep",
      reasons = reasons,
      matched = true,
    }
  end

  addReason(reasons, "Miss -> " .. profile.miss_action)
  return {
    action = profile.miss_action,
    reasons = reasons,
    matched = false,
  }
end

function M.profileHasActiveFilters(profile)
  return activeFilters(profile)
end

return M
