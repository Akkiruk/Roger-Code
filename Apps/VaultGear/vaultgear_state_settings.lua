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
    inbox_cursor = 1,
    inbox_slot = 0,
    repair_cursor = 1,
    repair_slot = 0,
    unresolved_scan = 0,
    current_mode = "idle",
    current_target = nil,
    last_summary = "Idle",
    last_reason = nil,
  },
  catalog = {},
}
