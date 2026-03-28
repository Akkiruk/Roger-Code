local M = {}

M.APP_NAME = "Vault Gear Sorter"
M.CONFIG_SCHEMA_VERSION = 1
M.STATE_SCHEMA_VERSION = 1

M.CONFIG_FILE = "vaultgear_config.lua"
M.STATE_FILE = "vaultgear_state_settings.lua"
M.LOG_FILE = "vaultgear_error.log"

M.MIN_MONITOR_WIDTH = 52
M.MIN_MONITOR_HEIGHT = 18
M.PREVIEW_LIMIT = 24
M.RECENT_LIMIT = 14

M.TABS = {
  { id = "dashboard", label = "Dashboard" },
  { id = "rules", label = "Rules" },
  { id = "modifiers", label = "Modifiers" },
  { id = "setup", label = "Setup" },
}

M.ROUTING_ROLES = {
  { id = "input", label = "Input" },
  { id = "keep", label = "Keep" },
  { id = "trash", label = "Trash" },
}

M.ACTIONS = { "keep", "discard" }
M.WANTED_MODES = { "any", "all" }
M.UNIDENTIFIED_MODES = { "keep", "discard", "evaluate_basic" }

M.RARITIES = {
  "ANY",
  "SCRAPPY",
  "COMMON",
  "RARE",
  "EPIC",
  "OMEGA",
  "UNIQUE",
  "SPECIAL",
  "CHAOTIC",
}

M.RARITY_ORDER = {
  SCRAPPY = 1,
  COMMON = 2,
  RARE = 3,
  EPIC = 4,
  OMEGA = 5,
  UNIQUE = 6,
  SPECIAL = 7,
  CHAOTIC = 8,
}

M.SUPPORTED_TYPES = {
  "Gear",
  "Tool",
  "Jewel",
  "Trinket",
  "Charm",
  "Etching",
}

M.SUPPORTED_TYPE_SET = {}
for _, itemType in ipairs(M.SUPPORTED_TYPES) do
  M.SUPPORTED_TYPE_SET[itemType] = true
end

M.DEFAULT_RUNTIME = {
  enabled = false,
  scan_interval = 2,
  batch_size = 4,
}

M.DEFAULT_SAFETY = {
  non_vault_action = "keep",
  unsupported_vault_action = "keep",
  detail_error_action = "keep",
}

M.PROFILE_LABELS = {
  enabled = "Profile",
  miss_action = "Misses Go To",
  unidentified_mode = "Unidentified",
  min_rarity = "Min Rarity",
  min_level = "Min Level",
  max_level = "Max Level",
  min_crafting_potential = "Min CP",
  min_free_repair_slots = "Free Repair",
  min_durability_percent = "Durability%",
  max_jewel_size = "Max Jewel Size",
  min_uses = "Min Uses",
  keep_legendary = "Always Keep Legendary",
  keep_soulbound = "Always Keep Soulbound",
  keep_unique = "Always Keep Unique",
  wanted_modifier_mode = "Wanted Mode",
}

M.PROFILE_PRESETS = {
  Gear = {
    { id = "keep_all", label = "Keep All" },
    { id = "common_plus", label = "Common+" },
    { id = "rare_plus", label = "Rare+" },
    { id = "trash_unid", label = "Unid Trash" },
  },
  Tool = {
    { id = "keep_all", label = "Keep All" },
    { id = "common_plus", label = "Common+" },
    { id = "rare_plus", label = "Rare+" },
    { id = "trash_unid", label = "Unid Trash" },
  },
  Jewel = {
    { id = "keep_all", label = "Keep All" },
    { id = "common_plus", label = "Common+" },
    { id = "rare_plus", label = "Rare+" },
    { id = "trash_unid", label = "Unid Trash" },
  },
  Trinket = {
    { id = "keep_all", label = "Keep All" },
    { id = "uses_2", label = "2+ Uses" },
    { id = "uses_5", label = "5+ Uses" },
    { id = "trash_unid", label = "Unid Trash" },
  },
  Charm = {
    { id = "keep_all", label = "Keep All" },
    { id = "common_plus", label = "Common+" },
    { id = "uses_3", label = "3+ Uses" },
    { id = "trash_unid", label = "Unid Trash" },
  },
  Etching = {
    { id = "keep_all", label = "Keep All" },
    { id = "common_plus", label = "Common+" },
    { id = "rare_plus", label = "Rare+" },
    { id = "trash_unid", label = "Unid Trash" },
  },
}

M.PROFILE_FIELDS = {
  Gear = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_rarity",
    "min_level",
    "max_level",
    "min_crafting_potential",
    "min_free_repair_slots",
    "min_durability_percent",
    "keep_legendary",
    "keep_soulbound",
    "keep_unique",
    "wanted_modifier_mode",
  },
  Tool = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_rarity",
    "min_level",
    "max_level",
    "min_free_repair_slots",
    "min_durability_percent",
    "wanted_modifier_mode",
  },
  Jewel = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_rarity",
    "min_level",
    "max_level",
    "max_jewel_size",
    "wanted_modifier_mode",
  },
  Trinket = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_uses",
    "wanted_modifier_mode",
  },
  Charm = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_rarity",
    "min_uses",
    "wanted_modifier_mode",
  },
  Etching = {
    "enabled",
    "miss_action",
    "unidentified_mode",
    "min_rarity",
    "min_level",
    "max_level",
    "keep_legendary",
    "wanted_modifier_mode",
  },
}

return M
