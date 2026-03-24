local catalog = require("lib.vaultgear.catalog")
local constants = require("lib.vaultgear.constants")
local evaluator = require("lib.vaultgear.evaluator")
local logger = require("lib.vaultgear.logger")
local peripherals = require("lib.vaultgear.peripherals")
local service = require("lib.vaultgear.service")
local store = require("lib.vaultgear.store")
local ui = require("lib.vaultgear.ui")
local util = require("lib.vaultgear.util")

local M = {}

local function recentEvent(app, level, message)
  util.pushRecent(app.recent, {
    at = os.epoch("local"),
    level = level,
    message = message,
  }, 10)
  if level == "error" then
    logger.error(message)
  else
    logger.info(message)
  end
end

local function bindMonitor(app)
  local bound, err = peripherals.bindMonitor(app.discovery, app.config.monitor.name, app.config.monitor.text_scale)
  if not bound then
    app.monitor = nil
    app.health.monitor_ok = false
    app.health.monitor_error = err
    return false
  end

  app.monitor = bound
  if not app.config.monitor.name then
    app.config.monitor.name = bound.name
    app.dirty_config = true
  end
  return true
end

local function profileSupportsField(itemType, field)
  local fields = constants.PROFILE_FIELDS[itemType] or {}
  for _, entry in ipairs(fields) do
    if entry == field then
      return true
    end
  end
  return false
end

local function overlappingModifierLabel(profile)
  local blocked = {}
  for _, entry in ipairs(profile.blocked_modifiers or {}) do
    blocked[entry.key] = entry.label or entry.key
  end

  for _, entry in ipairs(profile.wanted_modifiers or {}) do
    if blocked[entry.key] then
      return entry.label or blocked[entry.key] or entry.key
    end
  end

  return nil
end

local function refreshHealth(app)
  app.health = {
    monitor_ok = true,
    monitor_error = nil,
    errors = {},
    warnings = {},
  }

  if not app.monitor or not app.monitor.peripheral then
    app.health.monitor_ok = false
    app.health.monitor_error = "No monitor available"
  elseif app.monitor.width < constants.MIN_MONITOR_WIDTH or app.monitor.height < constants.MIN_MONITOR_HEIGHT then
    app.health.monitor_ok = false
    app.health.monitor_error = string.format(
      "Monitor too small: need %dx%d chars, have %dx%d",
      constants.MIN_MONITOR_WIDTH,
      constants.MIN_MONITOR_HEIGHT,
      app.monitor.width,
      app.monitor.height
    )
  end

  local ok, errors = peripherals.validateRouting(app.discovery, app.config.routing)
  if not ok then
    for _, message in ipairs(errors) do
      app.health.errors[#app.health.errors + 1] = message
    end
  end

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local profile = app.config.type_profiles[itemType]
    if profile then
      if profile.enabled and profile.miss_action == "discard" and not evaluator.profileHasActiveFilters(profile) then
        app.health.warnings[#app.health.warnings + 1] = itemType .. " would discard everything"
      end
      if profile.enabled and evaluator.profileHasActiveFilters(profile) and profile.miss_action == "keep" then
        app.health.warnings[#app.health.warnings + 1] = itemType .. " misses still go to Keep"
      end
      if profile.enabled and evaluator.profileHasActiveFilters(profile) and profile.unidentified_mode == "keep" then
        app.health.warnings[#app.health.warnings + 1] = itemType .. " unidentified items bypass filters"
      end

      local overlap = overlappingModifierLabel(profile)
      if profile.enabled and overlap then
        app.health.warnings[#app.health.warnings + 1] = itemType .. " keeps and blocks " .. overlap
      end
    end
  end
end

local function inputInventory(app)
  if not app.config.routing.input then
    return nil
  end
  return peripheral.wrap(app.config.routing.input)
end

local function refreshCatalogEntries(app)
  app.catalog_entries = catalog.listForType(app.state.catalog, app.ui.selected_type)
end

local function refreshDiscovery(app)
  app.discovery = peripherals.discover()
  bindMonitor(app)
  refreshHealth(app)
  refreshCatalogEntries(app)
end

local function rebuildPreview(app)
  app.preview = { items = {} }

  local input = inputInventory(app)
  if not input or #app.health.errors > 0 then
    return
  end

  app.preview = service.buildPreview(input, app.config, app.state.catalog, catalog, 8)
  if (app.ui.preview_selected or 1) > #app.preview.items then
    app.ui.preview_selected = math.max(1, #app.preview.items)
  end
  refreshCatalogEntries(app)
  if app.preview.catalog_changed then
    app.dirty_state = true
  end
end

local function resetStats(app)
  app.session.scanned = 0
  app.session.kept = 0
  app.session.discarded = 0
  app.session.errors = 0
  app.last_cycle_at = nil
end

local function saveAll(app, context)
  local location = context or "update"

  if app.dirty_config then
    local ok, err = store.saveConfig(app.config)
    if ok then
      app.dirty_config = false
    else
      recentEvent(app, "error", "Failed to save config after " .. location .. ": " .. tostring(err))
    end
  end

  if app.dirty_state then
    local ok, err = store.saveState(app.state)
    if ok then
      app.dirty_state = false
    else
      recentEvent(app, "error", "Failed to save state after " .. location .. ": " .. tostring(err))
    end
  end
end

local function resetProfileToDefaults(app, itemType)
  local profile = app.config.type_profiles[itemType]
  local defaults = store.buildDefaultConfig().type_profiles[itemType]
  if not profile or not defaults then
    return
  end

  for key in pairs(profile) do
    if defaults[key] == nil then
      profile[key] = nil
    end
  end

  for key, value in pairs(defaults) do
    profile[key] = util.deepCopy(value)
  end
end

local function applyPreset(app, itemType, presetId)
  local profile = app.config.type_profiles[itemType]
  if not profile then
    return
  end

  resetProfileToDefaults(app, itemType)
  profile = app.config.type_profiles[itemType]

  if presetId == "common_plus" then
    if profileSupportsField(itemType, "min_rarity") then
      profile.min_rarity = "COMMON"
    end
    profile.miss_action = "discard"
    profile.unidentified_mode = "evaluate_basic"
  elseif presetId == "rare_plus" then
    if profileSupportsField(itemType, "min_rarity") then
      profile.min_rarity = "RARE"
    end
    profile.miss_action = "discard"
    profile.unidentified_mode = "evaluate_basic"
  elseif presetId == "trash_unid" then
    profile.unidentified_mode = "discard"
  elseif presetId == "uses_2" then
    if profileSupportsField(itemType, "min_uses") then
      profile.min_uses = 2
    end
    profile.miss_action = "discard"
    profile.unidentified_mode = "evaluate_basic"
  elseif presetId == "uses_3" then
    if profileSupportsField(itemType, "min_uses") then
      profile.min_uses = 3
    end
    profile.miss_action = "discard"
    profile.unidentified_mode = "evaluate_basic"
  elseif presetId == "uses_5" then
    if profileSupportsField(itemType, "min_uses") then
      profile.min_uses = 5
    end
    profile.miss_action = "discard"
    profile.unidentified_mode = "evaluate_basic"
  end

  app.dirty_config = true
  app.dirty_state = true
  refreshHealth(app)
  rebuildPreview(app)
end

local function nextMissingRoutingRole(routing)
  for _, role in ipairs(constants.ROUTING_ROLES) do
    if not routing[role.id] or routing[role.id] == "" then
      return role.id
    end
  end
  return nil
end

local function adjustNumericField(profile, field, delta)
  local current = profile[field]
  local step = 1
  local minValue = 1
  local maxValue = 999

  if field == "min_crafting_potential" then
    step = 5
  elseif field == "min_durability_percent" then
    step = 5
    maxValue = 100
  end

  if current == nil then
    if delta < 0 then
      return
    end
    profile[field] = minValue
    return
  end

  local nextValue = current + (delta * step)
  if nextValue < minValue then
    profile[field] = nil
    return
  end

  profile[field] = util.clamp(nextValue, minValue, maxValue)
end

local function cycleProfileField(app, field, delta)
  local profile = app.config.type_profiles[app.ui.selected_type]

  if field == "enabled" or field == "keep_legendary" or field == "keep_soulbound" or field == "keep_unique" then
    profile[field] = not profile[field]
  elseif field == "miss_action" then
    profile[field] = util.cycleValue(constants.ACTIONS, profile[field], delta)
  elseif field == "unidentified_mode" then
    profile[field] = util.cycleValue(constants.UNIDENTIFIED_MODES, profile[field], delta)
  elseif field == "min_rarity" then
    profile[field] = util.cycleValue(constants.RARITIES, profile[field], delta)
  elseif field == "wanted_modifier_mode" then
    profile[field] = util.cycleValue(constants.WANTED_MODES, profile[field], delta)
  else
    adjustNumericField(profile, field, delta)
  end

  app.dirty_config = true
  app.dirty_state = true
  refreshHealth(app)
  rebuildPreview(app)
end

local function addRule(app, listName)
  local key = app.ui.selected_modifier_key
  if not key then
    return
  end

  local entries = app.catalog_entries or {}
  local picked = nil
  for _, entry in ipairs(entries) do
    if entry.key == key then
      picked = entry
      break
    end
  end
  if not picked then
    return
  end

  local profile = app.config.type_profiles[app.ui.selected_type]
  if not util.findByKey(profile[listName], picked.key) then
    profile[listName][#profile[listName] + 1] = {
      key = picked.key,
      label = picked.label,
    }
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    rebuildPreview(app)
  end
end

local function removeRule(app, listName)
  local key = app.ui.selected_modifier_key
  if not key then
    return
  end

  local profile = app.config.type_profiles[app.ui.selected_type]
  local _, index = util.findByKey(profile[listName], key)
  if index then
    table.remove(profile[listName], index)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    rebuildPreview(app)
  end
end

local function handleZone(app, zone)
  if not zone then
    return
  end

  if zone.id == "tab" then
    app.ui.page = zone.data.tab
    app.dirty_state = true
    return
  end

  if zone.id == "run_toggle" then
    app.config.runtime.enabled = not app.config.runtime.enabled
    app.dirty_config = true
    if app.config.runtime.enabled then
      recentEvent(app, "info", "Sorter enabled")
    else
      recentEvent(app, "info", "Sorter disabled")
    end
    return
  end

  if zone.id == "run_scan_now" then
    rebuildPreview(app)
    return
  end

  if zone.id == "apply_preset" then
    applyPreset(app, zone.data.item_type or app.ui.selected_type, zone.data.preset_id)
    return
  end

  if zone.id == "run_reset_stats" then
    resetStats(app)
    return
  end

  if zone.id == "run_select_preview" then
    app.ui.preview_selected = zone.data.index
    app.dirty_state = true
    return
  end

  if zone.id == "routing_role" then
    app.ui.routing_role = zone.data.role
    app.dirty_state = true
    return
  end

  if zone.id == "routing_refresh" then
    refreshDiscovery(app)
    rebuildPreview(app)
    return
  end

  if zone.id == "routing_assign" then
    app.config.routing[app.ui.routing_role] = zone.data.name
    app.dirty_config = true
    app.dirty_state = true
    local nextRole = nextMissingRoutingRole(app.config.routing)
    if nextRole then
      app.ui.routing_role = nextRole
    end
    refreshHealth(app)
    rebuildPreview(app)
    return
  end

  if zone.id == "routing_inventory_up" then
    app.ui.inventory_scroll = math.max(0, (app.ui.inventory_scroll or 0) - 1)
    app.dirty_state = true
    return
  end

  if zone.id == "routing_inventory_down" then
    app.ui.inventory_scroll = math.min(math.max(0, #app.discovery.inventories - 1), (app.ui.inventory_scroll or 0) + 1)
    app.dirty_state = true
    return
  end

  if zone.id == "runtime_interval_down" then
    app.config.runtime.scan_interval = math.max(1, app.config.runtime.scan_interval - 1)
    app.dirty_config = true
    return
  end

  if zone.id == "runtime_interval_up" then
    app.config.runtime.scan_interval = math.min(30, app.config.runtime.scan_interval + 1)
    app.dirty_config = true
    return
  end

  if zone.id == "runtime_batch_down" then
    app.config.runtime.batch_size = math.max(1, app.config.runtime.batch_size - 1)
    app.dirty_config = true
    return
  end

  if zone.id == "runtime_batch_up" then
    app.config.runtime.batch_size = math.min(32, app.config.runtime.batch_size + 1)
    app.dirty_config = true
    return
  end

  if zone.id == "profiles_type" or zone.id == "modifiers_type" then
    app.ui.selected_type = zone.data.item_type
    app.ui.profile_scroll = 0
    app.ui.catalog_scroll = 0
    app.ui.selected_modifier_key = nil
    app.dirty_state = true
    refreshCatalogEntries(app)
    return
  end

  if zone.id == "profiles_scroll_up" then
    app.ui.profile_scroll = math.max(0, (app.ui.profile_scroll or 0) - 1)
    app.dirty_state = true
    return
  end

  if zone.id == "profiles_scroll_down" then
    app.ui.profile_scroll = (app.ui.profile_scroll or 0) + 1
    app.dirty_state = true
    return
  end

  if zone.id == "profiles_cycle" then
    cycleProfileField(app, zone.data.field, zone.data.delta)
    return
  end

  if zone.id == "modifiers_mode_cycle" then
    local profile = app.config.type_profiles[app.ui.selected_type]
    profile.wanted_modifier_mode = util.cycleValue(constants.WANTED_MODES, profile.wanted_modifier_mode, 1)
    app.dirty_config = true
    refreshHealth(app)
    rebuildPreview(app)
    return
  end

  if zone.id == "modifiers_catalog_up" then
    app.ui.catalog_scroll = math.max(0, (app.ui.catalog_scroll or 0) - 1)
    app.dirty_state = true
    return
  end

  if zone.id == "modifiers_catalog_down" then
    app.ui.catalog_scroll = (app.ui.catalog_scroll or 0) + 1
    app.dirty_state = true
    return
  end

  if zone.id == "modifiers_select_catalog" then
    app.ui.selected_modifier_key = zone.data.key
    app.dirty_state = true
    return
  end

  if zone.id == "modifiers_add_keep" then
    addRule(app, "wanted_modifiers")
    return
  end

  if zone.id == "modifiers_add_block" then
    addRule(app, "blocked_modifiers")
    return
  end

  if zone.id == "modifiers_remove_keep" then
    removeRule(app, "wanted_modifiers")
    return
  end

  if zone.id == "modifiers_remove_block" then
    removeRule(app, "blocked_modifiers")
    return
  end

  if zone.id == "modifiers_clear_all" then
    local profile = app.config.type_profiles[app.ui.selected_type]
    profile.wanted_modifiers = {}
    profile.blocked_modifiers = {}
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    rebuildPreview(app)
    return
  end
end

local function processSortCycle(app)
  if not app.config.runtime.enabled then
    return
  end
  if #app.health.errors > 0 then
    return
  end

  local input = inputInventory(app)
  if not input then
    return
  end

  local report = service.processCycle(input, app.config, app.state.catalog, catalog)
  app.session.scanned = app.session.scanned + report.processed
  app.session.kept = app.session.kept + report.moved_keep
  app.session.discarded = app.session.discarded + report.moved_discard
  app.session.errors = app.session.errors + #report.errors
  app.last_cycle_at = os.epoch("local")
  refreshCatalogEntries(app)

  if report.last_decision then
    local item = report.last_decision.item
    recentEvent(app, "info", report.last_decision.decision.action .. ": " .. tostring(item.display_name))
  end
  for _, message in ipairs(report.errors) do
    recentEvent(app, "error", message)
  end

  rebuildPreview(app)
  if report.catalog_changed then
    app.dirty_state = true
  end
end

function M.run()
  logger.configure(constants.LOG_FILE)

  local app = {
    config = store.loadConfig(),
    state = store.loadState(),
    session = {
      scanned = 0,
      kept = 0,
      discarded = 0,
      errors = 0,
    },
    recent = {},
    preview = { items = {} },
    frame = { zones = {} },
    health = {
      monitor_ok = false,
      monitor_error = "Monitor unavailable",
      errors = {},
      warnings = {},
    },
    dirty_config = false,
    dirty_state = false,
  }

  app.ui = app.state.ui
  if app.ui.page ~= "run" and app.ui.page ~= "routing" and app.ui.page ~= "profiles" and app.ui.page ~= "modifiers" then
    app.ui.page = "run"
    app.dirty_state = true
  end
  if not constants.SUPPORTED_TYPE_SET[app.ui.selected_type] then
    app.ui.selected_type = "Gear"
    app.dirty_state = true
  end
  if app.ui.routing_role ~= "input" and app.ui.routing_role ~= "keep" and app.ui.routing_role ~= "trash" then
    app.ui.routing_role = nextMissingRoutingRole(app.config.routing) or "input"
    app.dirty_state = true
  end

  refreshDiscovery(app)
  rebuildPreview(app)
  saveAll(app, "startup")

  local redrawTimer = os.startTimer(0.2)
  local previewTimer = os.startTimer(2)
  local sortTimer = os.startTimer(app.config.runtime.scan_interval)
  local saveTimer = os.startTimer(10)

  while true do
    app.frame = ui.render(app)
    local event, p1, p2, p3 = os.pullEventRaw()

    if event == "terminate" then
      saveAll(app, "terminate")
      return
    elseif event == "monitor_touch" then
      if app.monitor and p1 == app.monitor.name then
        handleZone(app, ui.hit(app.frame, p2, p3))
        saveAll(app, "monitor touch")
      end
    elseif event == "peripheral" or event == "peripheral_detach" then
      refreshDiscovery(app)
      rebuildPreview(app)
      saveAll(app, "peripheral refresh")
    elseif event == "timer" and p1 == redrawTimer then
      redrawTimer = os.startTimer(0.2)
    elseif event == "timer" and p1 == previewTimer then
      rebuildPreview(app)
      saveAll(app, "preview refresh")
      previewTimer = os.startTimer(2)
    elseif event == "timer" and p1 == sortTimer then
      processSortCycle(app)
      saveAll(app, "sort cycle")
      sortTimer = os.startTimer(app.config.runtime.scan_interval)
    elseif event == "timer" and p1 == saveTimer then
      if app.dirty_config or app.dirty_state then
        saveAll(app, "periodic backup")
      end
      saveTimer = os.startTimer(10)
    end
  end
end

return M
