-- vaultgear_state_settings.lua
-- Preserved runtime state for the storage manager monitor UI.

return {
  schema_version = 3,
  ui = {
    page = "overview",
    selected_inventory = nil,
    advanced = false,
  },
  runtime = {
    repair_cursor = 1,
    current_mode = "idle",
    current_target = nil,
    last_summary = "Idle",
    last_reason = nil,
  },
  catalog = {},
}
