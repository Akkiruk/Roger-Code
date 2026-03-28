-- vaultgear_config.lua
-- Preserved across installer updates. Edited by the monitor UI at runtime.

return {
  schema_version = 3,
  monitor = {
    name = nil,
    text_scale = 0.5,
  },
  runtime = {
    enabled = false,
    scan_interval = 2,
    move_batch = 4,
    repair_batch = 2,
  },
  storages = {},
}
