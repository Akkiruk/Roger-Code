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
  }, constants.RECENT_LIMIT)

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

  app.preview = service.buildPreview(input, app.config, app.state.catalog, catalog, constants.PREVIEW_LIMIT)
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

local function normalizePage(page)
  if page == "run" then
    return "dashboard"
  end
  if page == "routing" then
    return "setup"
  end
  if page == "profiles" then
    return "rules"
  end
  if page == "modifiers" then
    return "modifiers"
  end

  for _, tab in ipairs(constants.TABS) do
    if tab.id == page then
      return page
    end
  end

  return "dashboard"
end

local function initializeUiState(app)
  app.ui.page = normalizePage(app.ui.page)

  if not constants.SUPPORTED_TYPE_SET[app.ui.selected_type] then
    app.ui.selected_type = "Gear"
    app.dirty_state = true
  end

  if app.ui.preview_selected == nil then
    app.ui.preview_selected = 1
    app.dirty_state = true
  end
  if app.ui.selected_modifier_key == nil then
    app.ui.selected_modifier_key = nil
  end
  if app.ui.selected_keep_key == nil then
    app.ui.selected_keep_key = nil
    app.dirty_state = true
  end
  if app.ui.selected_block_key == nil then
    app.ui.selected_block_key = nil
    app.dirty_state = true
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

local function setSelectedType(app, itemType)
  if not constants.SUPPORTED_TYPE_SET[itemType] then
    return
  end

  app.ui.selected_type = itemType
  app.ui.selected_modifier_key = nil
  app.ui.selected_keep_key = nil
  app.ui.selected_block_key = nil
  app.dirty_state = true
  refreshCatalogEntries(app)
end

local function refreshUi(app, mode)
  local controller = app.controller
  if not controller then
    return
  end

  controller:rebindTerm()

  if mode == "dashboard" then
    controller:refreshDashboard()
  elseif mode == "modifiers" then
    controller:refreshModifiers()
  elseif mode == "setup" then
    controller:refreshSetup()
  elseif mode == "header" then
    controller:refreshHeader()
  elseif mode == "live" then
    controller:refreshLive()
  else
    controller:refreshAll()
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
    health = {
      monitor_ok = false,
      monitor_error = "Monitor unavailable",
      errors = {},
      warnings = {},
    },
    dirty_config = false,
    dirty_state = false,
    controller = nil,
  }

  app.ui = app.state.ui
  initializeUiState(app)
  refreshDiscovery(app)
  rebuildPreview(app)

  local actions = {}

  local function syncFull(context)
    refreshHealth(app)
    rebuildPreview(app)
    refreshUi(app)
    saveAll(app, context)
  end

  local function notify(level, title, message)
    if app.controller then
      app.controller:notify(level, title, message)
    end
  end

  function actions.setPage(page)
    local nextPage = normalizePage(page)
    if app.ui.page == nextPage then
      return
    end
    app.ui.page = nextPage
    app.dirty_state = true
    saveAll(app, "page switch")
  end

  function actions.toggleRuntime()
    app.config.runtime.enabled = not app.config.runtime.enabled
    app.dirty_config = true

    if app.config.runtime.enabled then
      recentEvent(app, "info", "Sorter enabled")
      notify("success", "Sorting enabled", "The sorter is live and watching the input inventory.")
    else
      recentEvent(app, "info", "Sorter disabled")
      notify("warning", "Sorting paused", "The sorter will keep scanning previews but will not move items.")
    end

    refreshHealth(app)
    refreshUi(app, "header")
    refreshUi(app, "dashboard")
    saveAll(app, "runtime toggle")
  end

  function actions.scanNow()
    rebuildPreview(app)
    refreshUi(app, "live")
    saveAll(app, "manual scan")
    notify("info", "Preview refreshed", "The input inventory was rescanned.")
  end

  function actions.resetSession()
    resetStats(app)
    refreshUi(app, "dashboard")
    notify("info", "Session reset", "Session counters were cleared.")
  end

  function actions.selectPreview(index)
    app.ui.preview_selected = util.clamp(index or 1, 1, math.max(1, #(app.preview.items or {})))
    app.dirty_state = true
    refreshUi(app, "dashboard")
    saveAll(app, "preview select")
  end

  function actions.selectType(itemType)
    setSelectedType(app, itemType)
    refreshUi(app)
    saveAll(app, "type select")
  end

  function actions.refreshPeripherals(showToast)
    refreshDiscovery(app)
    rebuildPreview(app)
    refreshUi(app)
    saveAll(app, "peripheral refresh")
    if showToast ~= false then
      notify("info", "Peripherals refreshed", "Monitor and inventory choices were rescanned.")
    end
  end

  function actions.assignRouting(role, inventoryName)
    if role ~= "input" and role ~= "keep" and role ~= "trash" then
      return
    end

    app.config.routing[role] = inventoryName
    app.dirty_config = true
    app.dirty_state = true

    local nextRole = nextMissingRoutingRole(app.config.routing)
    recentEvent(app, "info", string.format("Assigned %s inventory: %s", role, tostring(inventoryName)))

    syncFull("routing update")
    if nextRole then
      notify("success", role:gsub("^%l", string.upper) .. " set", "Next up: choose the " .. nextRole .. " inventory.")
    else
      notify("success", role:gsub("^%l", string.upper) .. " set", tostring(inventoryName))
    end
  end

  function actions.adjustRuntime(field, delta)
    if field == "scan_interval" then
      app.config.runtime.scan_interval = math.min(30, math.max(1, app.config.runtime.scan_interval + delta))
    elseif field == "batch_size" then
      app.config.runtime.batch_size = math.min(32, math.max(1, app.config.runtime.batch_size + delta))
    else
      return
    end

    app.dirty_config = true
    refreshUi(app, "setup")
    saveAll(app, "runtime tuning")
  end

  function actions.applyPreset(itemType, presetId)
    applyPreset(app, itemType, presetId)
    syncFull("preset")
    notify("success", "Preset applied", tostring(itemType) .. " updated to " .. tostring(presetId))
  end

  function actions.setProfileChoice(itemType, field, value)
    local profile = app.config.type_profiles[itemType]
    if not profile then
      return
    end

    profile[field] = value
    app.dirty_config = true
    app.dirty_state = true
    syncFull("profile choice")
  end

  function actions.setProfileFlag(itemType, field, value)
    local profile = app.config.type_profiles[itemType]
    if not profile then
      return
    end

    profile[field] = value == true
    app.dirty_config = true
    app.dirty_state = true
    syncFull("profile flag")
  end

  function actions.adjustProfileNumber(itemType, field, delta)
    local profile = app.config.type_profiles[itemType]
    if not profile then
      return
    end

    adjustNumericField(profile, field, delta)
    app.dirty_config = true
    app.dirty_state = true
    syncFull("profile number")
  end

  function actions.selectCatalogModifier(key)
    app.ui.selected_modifier_key = key
    app.ui.selected_keep_key = nil
    app.ui.selected_block_key = nil
    app.dirty_state = true
    refreshUi(app, "modifiers")
    saveAll(app, "catalog select")
  end

  function actions.selectKeepRule(key)
    app.ui.selected_keep_key = key
    app.ui.selected_block_key = nil
    app.dirty_state = true
    refreshUi(app, "modifiers")
    saveAll(app, "keep rule select")
  end

  function actions.selectBlockRule(key)
    app.ui.selected_block_key = key
    app.ui.selected_keep_key = nil
    app.dirty_state = true
    refreshUi(app, "modifiers")
    saveAll(app, "block rule select")
  end

  function actions.addRule(listName)
    local key = app.ui.selected_modifier_key
    if not key then
      notify("warning", "Pick a modifier", "Choose a discovered modifier before adding it to Keep or Block.")
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
    if util.findByKey(profile[listName], picked.key) then
      notify("info", "Already added", picked.label)
      return
    end

    profile[listName][#profile[listName] + 1] = {
      key = picked.key,
      label = picked.label,
    }

    if listName == "wanted_modifiers" then
      app.ui.selected_keep_key = picked.key
      notify("success", "Added to Keep", picked.label)
    else
      app.ui.selected_block_key = picked.key
      notify("warning", "Added to Block", picked.label)
    end

    app.dirty_config = true
    app.dirty_state = true
    syncFull("modifier add")
  end

  function actions.removeRule(listName)
    local selectedKey = nil
    if listName == "wanted_modifiers" then
      selectedKey = app.ui.selected_keep_key
    else
      selectedKey = app.ui.selected_block_key
    end

    if not selectedKey then
      notify("warning", "Nothing selected", "Select a saved rule first.")
      return
    end

    local profile = app.config.type_profiles[app.ui.selected_type]
    local entry, index = util.findByKey(profile[listName], selectedKey)
    if not index then
      return
    end

    table.remove(profile[listName], index)
    if listName == "wanted_modifiers" then
      app.ui.selected_keep_key = nil
      notify("info", "Removed keep rule", entry.label or entry.key)
    else
      app.ui.selected_block_key = nil
      notify("info", "Removed block rule", entry.label or entry.key)
    end

    app.dirty_config = true
    app.dirty_state = true
    syncFull("modifier remove")
  end

  function actions.clearRules()
    local profile = app.config.type_profiles[app.ui.selected_type]
    profile.wanted_modifiers = {}
    profile.blocked_modifiers = {}
    app.ui.selected_keep_key = nil
    app.ui.selected_block_key = nil
    app.dirty_config = true
    app.dirty_state = true
    syncFull("modifier clear")
    notify("warning", "Modifier rules cleared", app.ui.selected_type .. " now has no keep/block modifier filters.")
  end

  function actions.onPreviewTimer()
    rebuildPreview(app)
    refreshUi(app, "live")
    saveAll(app, "preview refresh")
  end

  function actions.onSortTimer()
    processSortCycle(app)
    refreshUi(app, "live")
    saveAll(app, "sort cycle")
  end

  function actions.onSaveTimer()
    if app.dirty_config or app.dirty_state then
      saveAll(app, "periodic backup")
    end
    refreshUi(app, "header")
  end

  function actions.onPeripheralEvent(kind)
    refreshDiscovery(app)
    rebuildPreview(app)
    refreshUi(app)
    saveAll(app, kind or "peripheral event")
  end

  function actions.onTerminate()
    saveAll(app, "terminate")
  end

  app.controller = ui.create(app, actions)
  refreshUi(app)
  saveAll(app, "startup")
  app.controller:run()
end

return M
