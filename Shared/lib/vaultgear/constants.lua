local M = {}

M.APP_NAME = "Vault Storage Manager"
M.CONFIG_SCHEMA_VERSION = 3
M.STATE_SCHEMA_VERSION = 3

M.CONFIG_FILE = "vaultgear_config.lua"
M.STATE_FILE = "vaultgear_state_settings.lua"
M.LOG_FILE = "vaultgear_error.log"

M.MIN_MONITOR_WIDTH = 52
M.MIN_MONITOR_HEIGHT = 18
M.INSPECT_LIMIT = 12
M.RECENT_LIMIT = 18
M.WORK_INTERVAL = 0.1
M.INSPECT_INTERVAL_ACTIVE = 0.75
M.INSPECT_INTERVAL_BACKGROUND = 3
M.SAVE_INTERVAL = 1
M.WORK_SCAN_BUDGET = 8

M.TABS = {
  { id = "overview", label = "Overview" },
  { id = "storages", label = "Storages" },
  { id = "live", label = "Live" },
}

M.STORAGE_ROLES = {
  { id = "inbox", label = "Inbox" },
  { id = "home", label = "Home" },
}

M.STRICTNESS = {
  { id = "broad", label = "Broad" },
  { id = "normal", label = "Normal" },
  { id = "strict", label = "Strict" },
}

M.IDENTIFIED_MODES = {
  { id = "any", label = "Any" },
  { id = "identified", label = "Identified" },
  { id = "unidentified", label = "Unidentified" },
}

M.RARITIES = {
  "ANY",
  "NONE",
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
  scan_interval = 0.75,
}

M.DEFAULT_RULE = {
  item_types = {},
  identified_mode = "any",
  min_rarity = "ANY",
  min_level = nil,
  max_level = nil,
  min_crafting_potential = nil,
  min_free_repair_slots = nil,
  min_durability_percent = nil,
  max_jewel_size = nil,
  min_uses = nil,
  allow_legendary = true,
  allow_soulbound = false,
  allow_unique = true,
  allow_chaotic = false,
}

M.NUMERIC_FIELDS = {
  min_level = {
    label = "Min Level",
    step = 1,
    min = 1,
    max = 999,
  },
  max_level = {
    label = "Max Level",
    step = 1,
    min = 1,
    max = 999,
  },
  min_crafting_potential = {
    label = "Min CP",
    step = 5,
    min = 0,
    max = 1000,
  },
  min_free_repair_slots = {
    label = "Free Repairs",
    step = 1,
    min = 0,
    max = 50,
  },
  min_durability_percent = {
    label = "Durability %",
    step = 5,
    min = 0,
    max = 100,
  },
  max_jewel_size = {
    label = "Max Jewel Size",
    step = 1,
    min = 1,
    max = 100,
  },
  min_uses = {
    label = "Min Uses",
    step = 1,
    min = 1,
    max = 100,
  },
}

M.NUMERIC_FIELD_ORDER = {
  "min_level",
  "max_level",
  "min_crafting_potential",
  "min_free_repair_slots",
  "min_durability_percent",
  "max_jewel_size",
  "min_uses",
}

return M
