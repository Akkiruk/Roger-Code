local catalog = require("lib.vaultgear.catalog")
local constants = require("lib.vaultgear.constants")
local logger = require("lib.vaultgear.logger")
local peripherals = require("lib.vaultgear.peripherals")
local planner = require("lib.vaultgear.planner")
local presets = require("lib.vaultgear.presets")
local quickSetup = require("lib.vaultgear.quick_setup")
local service = require("lib.vaultgear.service")
local store = require("lib.vaultgear.store")
local ui = require("lib.vaultgear.ui")
local util = require("lib.vaultgear.util")

local M = {}

local function routeFailureKey(sourceName, destinationName)
  return tostring(sourceName or "?") .. "->" .. tostring(destinationName or "?")
end

local function clearRouteFailures(runtimeState)
  if runtimeState then
    runtimeState.route_failures = {}
  end
end

local function rememberRouteFailure(runtimeState, failure)
  if type(runtimeState) ~= "table" or type(failure) ~= "table" then
    return nil
  end

  if type(runtimeState.route_failures) ~= "table" then
    runtimeState.route_failures = {}
  end

  local key = routeFailureKey(failure.source, failure.destination)
  local existing = runtimeState.route_failures[key]
  runtimeState.route_failures[key] = {
    source = failure.source,
    destination = failure.destination,
    code = failure.code or "move_failed",
    error = failure.error,
    seen = existing and ((existing.seen or 0) + 1) or 1,
    last_seen = os.epoch("local"),
  }
  return existing == nil, runtimeState.route_failures[key]
end

local function routeFailureSummary(failure)
  return string.format(
    "Route blocked: %s cannot push to %s. Refresh peripherals or reconfigure that storage.",
    tostring(failure.source or "?"),
    tostring(failure.destination or "?")
  )
end

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

local function connectedInventorySet(app)
  local map = {}
  for _, entry in ipairs(app.discovery.inventories or {}) do
    map[entry.name] = true
  end
  return map
end

local function inventoryNames(app)
  local names = {}
  local seen = {}

  for _, entry in ipairs(app.discovery.inventories or {}) do
    if not seen[entry.name] then
      names[#names + 1] = entry.name
      seen[entry.name] = true
    end
  end

  for _, storage in ipairs(app.config.storages or {}) do
    if storage.inventory and not seen[storage.inventory] then
      names[#names + 1] = storage.inventory
      seen[storage.inventory] = true
    end
  end

  table.sort(names)
  return names
end

local function selectedStorage(app)
  return planner.findStorageByInventory(app.config.storages, app.ui.selected_inventory)
end

local function pendingRelinkStorage(app)
  local storageId = app.session and app.session.pending_relink_storage_id or nil
  if not storageId then
    return nil, nil
  end

  return planner.findStorageById(app.config.storages, storageId)
end

local function clearPendingRelink(app)
  if app and app.session then
    app.session.pending_relink_storage_id = nil
  end
end

local function ensureSelectedInventory(app)
  local names = inventoryNames(app)
  if app.ui.selected_inventory then
    for _, name in ipairs(names) do
      if name == app.ui.selected_inventory then
        return
      end
    end
  end

  app.ui.selected_inventory = names[1]
  app.dirty_state = true
end

local function summarizeWork(report)
  if not report then
    return "Idle", nil
  end

  if report.kind == "routing" and report.action then
    return "Routing from " .. tostring(report.action.source), report.action.reason
  end
  if report.kind == "repair" and report.action then
    return "Repairing " .. tostring(report.action.source), report.action.reason
  end
  if report.kind == "repair_scan" then
    return "Repair scan complete", nil
  end
  return "Idle", nil
end

local function refreshInspector(app)
  ensureSelectedInventory(app)
  app.inspector = service.inspectInventory(
    app.ui.selected_inventory,
    app.state.catalog,
    catalog,
    constants.INSPECT_LIMIT
  )
  app.suggestion = presets.suggest(app.inspector.items or {})
  if app.inspector.catalog_changed then
    app.dirty_state = true
  end
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

  app.connected = connectedInventorySet(app)

  local inboxes = planner.listInboxes(app.config.storages, app.connected)
  local homes = planner.listHomes(app.config.storages, app.connected)

  if #inboxes == 0 then
    app.health.errors[#app.health.errors + 1] = "Add at least one connected inbox."
  end
  if #homes == 0 then
    app.health.errors[#app.health.errors + 1] = "Add at least one connected home."
  end

  local priorityUse = {}

  for _, storage in ipairs(app.config.storages or {}) do
    if storage.inventory == nil then
      app.health.errors[#app.health.errors + 1] = "A managed storage is missing its inventory."
    elseif not app.connected[storage.inventory] then
      app.health.warnings[#app.health.warnings + 1] = "Missing storage: " .. tostring(storage.inventory)
    else
      local entry = peripherals.findInventory(app.discovery, storage.inventory)
      if entry and not entry.can_list then
        app.health.errors[#app.health.errors + 1] = storage.inventory .. " cannot be scanned with list()."
      end
      if entry and not entry.can_push then
        app.health.errors[#app.health.errors + 1] = storage.inventory .. " cannot move items with pushItems()."
      end
      if entry and not entry.can_detail then
        app.health.warnings[#app.health.warnings + 1] = storage.inventory .. " does not support detailed Vault reads."
      end
    end

    if storage.role == "home" then
      local priority = tonumber(storage.priority) or 0
      priorityUse[priority] = (priorityUse[priority] or 0) + 1
    end
  end

  for _, failure in pairs(app.state.runtime.route_failures or {}) do
    app.health.errors[#app.health.errors + 1] = routeFailureSummary(failure)
  end

  for priority, count in pairs(priorityUse) do
    if count > 1 then
      app.health.warnings[#app.health.warnings + 1] = "Multiple homes share priority " .. tostring(priority) .. "."
    end
  end
end

local function refreshDiscovery(app)
  app.discovery = peripherals.discover()
  clearRouteFailures(app.state.runtime)
  app.dirty_state = true
  bindMonitor(app)
  refreshHealth(app)
  local pendingStorage = pendingRelinkStorage(app)
  if pendingStorage and app.connected[pendingStorage.inventory] then
    clearPendingRelink(app)
  end
  refreshInspector(app)
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

local function normalizePage(page)
  for _, tab in ipairs(constants.TABS) do
    if tab.id == page then
      return page
    end
  end
  return "overview"
end

local function initializeState(app)
  app.config.storages = planner.normalizeStorages(app.config.storages)
  app.ui.page = normalizePage(app.ui.page)
  app.ui.advanced = app.ui.advanced == true
  if type(app.state.runtime.route_failures) ~= "table" then
    app.state.runtime.route_failures = {}
  end
end

local function sortStorages(app)
  app.config.storages = planner.normalizeStorages(app.config.storages)
end

local function updateRuntimeState(app, report)
  local summary, reason = summarizeWork(report)
  app.state.runtime.current_mode = report and report.kind or "idle"
  app.state.runtime.current_target = report and report.target_inventory or nil
  app.state.runtime.last_summary = summary
  app.state.runtime.last_reason = reason
  app.last_cycle_at = os.epoch("local")
  app.dirty_state = true
end

local function processWork(app, allowPaused)
  if not app.config.runtime.enabled and allowPaused ~= true then
    updateRuntimeState(app, {
      kind = "idle",
      target_inventory = nil,
    })
    return
  end

  if #app.health.errors > 0 then
    updateRuntimeState(app, {
      kind = "idle",
      target_inventory = nil,
    })
    return
  end

  local report = service.processInboxes(
    app.config.storages,
    app.connected,
    app.state.catalog,
    catalog
  )

  if report.catalog_changed then
    app.dirty_state = true
  end

  if report.moved_stacks == 0 then
    report = service.processRepair(
      app.config.storages,
      app.connected,
      app.state.runtime,
      app.state.catalog,
      catalog
    )

    if report.catalog_changed then
      app.dirty_state = true
    end
  end

  if report.action then
    app.session.moves = app.session.moves + report.moved_stacks
    app.session.moved_items = app.session.moved_items + report.moved_items
    if report.action.kind == "route" then
      app.session.routed = app.session.routed + report.moved_stacks
    else
      app.session.repaired = app.session.repaired + report.moved_stacks
    end

    recentEvent(
      app,
      "info",
      string.format(
        "%s -> %s: %s",
        tostring(report.action.source),
        tostring(report.action.destination or "?"),
        tostring(report.action.item and report.action.item.display_name or "Item")
      )
    )
  end

  if report.unresolved and report.unresolved > 0 then
    app.session.unresolved = report.unresolved
  end

  for _, failure in ipairs(report.route_failures or {}) do
    local isNew, remembered = rememberRouteFailure(app.state.runtime, failure)
    app.dirty_state = true
    if isNew and remembered then
      recentEvent(app, "error", routeFailureSummary(remembered))
    end
  end

  for _, message in ipairs(report.errors or {}) do
    app.session.errors = app.session.errors + 1
    recentEvent(app, "error", message)
  end

  updateRuntimeState(app, report)
  refreshHealth(app)
  refreshInspector(app)
end

local function ensureStorage(app, role, presetId, strictness)
  local storage, index = selectedStorage(app)
  if not app.ui.selected_inventory then
    return nil
  end

  if not storage then
    storage = planner.createStorage(app.config.storages, app.ui.selected_inventory, role, presetId, strictness)
    app.config.storages[#app.config.storages + 1] = storage
  else
    storage.role = role == "inbox" and "inbox" or "home"
    storage.enabled = true
    storage.inventory = app.ui.selected_inventory
    if storage.role == "home" then
      storage.strictness = strictness or storage.strictness or "normal"
      storage.preset_id = presetId or storage.preset_id or "overflow"
      storage.rule = presets.apply(storage.preset_id, storage.strictness)
      storage.rescan = storage.rescan ~= false
      storage.priority = tonumber(storage.priority) or planner.nextHomePriority(app.config.storages)
    else
      storage.preset_id = nil
      storage.rescan = false
    end
    app.config.storages[index] = planner.normalizeStorage(storage, index)
  end

  sortStorages(app)
  app.dirty_config = true
  app.dirty_state = true
  refreshHealth(app)
  refreshInspector(app)
  return planner.findStorageByInventory(app.config.storages, app.ui.selected_inventory)
end

local function configureSelectedHomeQuick(app, spec)
  if not app.ui.selected_inventory then
    return nil
  end

  local normalizedSpec = quickSetup.normalizeConfig(spec, planner.nextHomePriority(app.config.storages))
  local storage, index = selectedStorage(app)
  local existingEnabled = storage and storage.enabled ~= false or true
  local existingRescan = storage and storage.rescan ~= false or true

  if not storage then
    storage = planner.createStorage(
      app.config.storages,
      app.ui.selected_inventory,
      "home",
      quickSetup.presetForType(normalizedSpec.item_type),
      "normal"
    )
    app.config.storages[#app.config.storages + 1] = storage
    storage, index = selectedStorage(app)
  end

  storage.role = "home"
  storage.inventory = app.ui.selected_inventory
  storage.enabled = existingEnabled
  storage.rescan = existingRescan
  storage.priority = normalizedSpec.priority
  storage.preset_id = quickSetup.presetForType(normalizedSpec.item_type)
  storage.strictness = "normal"
  storage.rule = quickSetup.buildRule(normalizedSpec)

  app.config.storages[index] = planner.normalizeStorage(storage, index)
  sortStorages(app)
  app.dirty_config = true
  app.dirty_state = true
  refreshHealth(app)
  refreshInspector(app)
  return planner.findStorageByInventory(app.config.storages, app.ui.selected_inventory)
end

local function refreshUi(app, mode)
  local controller = app.controller
  if not controller then
    return
  end

  controller:rebindTerm()

  if mode == "header" then
    controller:refreshHeader()
  elseif mode == "live" then
    controller:refreshLive()
  elseif mode == "storages" then
    controller:refreshSetup()
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
      moves = 0,
      moved_items = 0,
      routed = 0,
      repaired = 0,
      errors = 0,
      unresolved = 0,
      pending_relink_storage_id = nil,
    },
    recent = {},
    inspector = {
      items = {},
      error = nil,
    },
    suggestion = nil,
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
  initializeState(app)
  refreshDiscovery(app)

  local actions = {}

  local function syncAll(context)
    sortStorages(app)
    refreshHealth(app)
    refreshInspector(app)
    refreshUi(app)
    saveAll(app, context)
  end

  local function notify(level, title, message)
    if app.controller then
      app.controller:notify(level, title, message)
    end
  end

  function actions.setPage(page)
    app.ui.page = normalizePage(page)
    app.dirty_state = true
    refreshUi(app)
    saveAll(app, "page switch")
  end

  function actions.selectInventory(inventoryName)
    app.ui.selected_inventory = inventoryName
    app.dirty_state = true
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "inventory select")
  end

  function actions.toggleAdvanced()
    app.ui.advanced = not app.ui.advanced
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "advanced toggle")
  end

  function actions.toggleRuntime()
    app.config.runtime.enabled = not app.config.runtime.enabled
    app.dirty_config = true
    app.dirty_state = true

    if app.config.runtime.enabled then
      recentEvent(app, "info", "Storage manager enabled")
      notify("success", "Manager enabled", "Inbox routing and idle repair are live.")
    else
      recentEvent(app, "info", "Storage manager paused")
      notify("warning", "Manager paused", "Automatic routing is paused until you resume it.")
    end

    refreshUi(app)
    saveAll(app, "runtime toggle")
  end

  function actions.scanNow()
    processWork(app, true)
    refreshUi(app, "live")
    saveAll(app, "manual work cycle")
    notify("info", "Cycle complete", app.state.runtime.last_summary or "Manual cycle finished.")
  end

  function actions.refreshPeripherals(showToast)
    refreshDiscovery(app)
    refreshUi(app)
    saveAll(app, "peripheral refresh")
    if showToast ~= false then
      notify("info", "Peripherals refreshed", "Connected inventories and monitors were rescanned.")
    end
  end

  function actions.manageSelectedAsHome(presetId, strictness)
    local storage = ensureStorage(app, "home", presetId, strictness)
    if storage then
      notify("success", "Home configured", presets.label(storage.preset_id))
      refreshUi(app, "storages")
      saveAll(app, "home configure")
    end
  end

  function actions.manageSelectedAsInbox()
    local storage = ensureStorage(app, "inbox", nil, nil)
    if storage then
      notify("success", "Inbox configured", tostring(storage.inventory))
      refreshUi(app, "storages")
      saveAll(app, "inbox configure")
    end
  end

  function actions.stopManagingSelected()
    local _, index = selectedStorage(app)
    if not index then
      return
    end

    table.remove(app.config.storages, index)
    local pendingStorage = pendingRelinkStorage(app)
    if pendingStorage == nil then
      clearPendingRelink(app)
    end
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "storage remove")
    notify("warning", "Stopped managing", tostring(app.ui.selected_inventory))
  end

  function actions.beginRelinkSelected()
    local storage = selectedStorage(app)
    if not storage or app.connected[storage.inventory] then
      return
    end

    app.session.pending_relink_storage_id = storage.id
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "begin relink")
    notify("info", "Pick replacement", "Select the live inventory that should take over this storage, then confirm.")
  end

  function actions.cancelRelink()
    if not pendingRelinkStorage(app) then
      return
    end

    clearPendingRelink(app)
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "cancel relink")
    notify("info", "Relink cancelled", "The current storage plan was left unchanged.")
  end

  function actions.applyRelinkToSelected()
    local storage, index = pendingRelinkStorage(app)
    if not storage or not index then
      return
    end

    if not app.ui.selected_inventory or not app.connected[app.ui.selected_inventory] then
      notify("warning", "Select a live inventory", "Choose a connected inventory before applying the replacement.")
      return
    end

    local selected, selectedIndex = selectedStorage(app)
    if selected and selected.id ~= storage.id then
      notify("warning", "Inventory already managed", "Pick an open connected inventory so the missing storage can be rebound cleanly.")
      return
    end

    local previousInventory = storage.inventory
    storage.inventory = app.ui.selected_inventory
    app.config.storages[index] = planner.normalizeStorage(storage, index)

    if selectedIndex and selectedIndex ~= index then
      app.config.storages[selectedIndex] = planner.normalizeStorage(selected, selectedIndex)
    end

    clearPendingRelink(app)
    clearRouteFailures(app.state.runtime)
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "apply relink")

    recentEvent(
      app,
      "info",
      string.format("Relinked %s -> %s", tostring(previousInventory or "?"), tostring(storage.inventory or "?"))
    )
    notify("success", "Storage rebound", tostring(storage.inventory))
  end

  function actions.applySuggestion()
    if not app.suggestion then
      return
    end
    actions.manageSelectedAsHome(app.suggestion.preset_id, app.suggestion.strictness)
  end

  function actions.setSelectedRole(role)
    if role == "inbox" then
      actions.manageSelectedAsInbox()
    else
      local storage = selectedStorage(app)
      local quickSpec = storage and quickSetup.fromStorage(storage) or quickSetup.fromSuggestion(
        app.suggestion,
        planner.nextHomePriority(app.config.storages)
      )
      local configured = configureSelectedHomeQuick(app, quickSpec)
      if configured then
        notify("success", "Home configured", presets.label(configured.preset_id))
        refreshUi(app, "storages")
        saveAll(app, "role change")
      end
    end
  end

  function actions.configureSelectedHomeQuick(spec)
    local storage = configureSelectedHomeQuick(app, spec)
    if storage then
      notify("success", "Home configured", presets.label(storage.preset_id))
      refreshUi(app, "storages")
      saveAll(app, "quick home configure")
    end
  end

  function actions.setSelectedQuickType(itemType)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    local nextSpec = quickSetup.defaultConfig(itemType, storage.priority)
    actions.configureSelectedHomeQuick(nextSpec)
  end

  function actions.setSelectedPreset(presetId)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    storage.preset_id = presetId
    storage.rule = presets.apply(storage.preset_id, storage.strictness)
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "preset change")
  end

  function actions.setSelectedStrictness(strictness)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    storage.strictness = strictness
    storage.rule = presets.apply(storage.preset_id, storage.strictness)
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "strictness change")
  end

  function actions.adjustSelectedPriority(delta)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    storage.priority = math.max(1, (tonumber(storage.priority) or 1) + delta)
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshUi(app, "storages")
    saveAll(app, "priority change")
  end

  function actions.setSelectedEnabled(value)
    local storage = selectedStorage(app)
    if not storage then
      return
    end

    storage.enabled = value == true
    sortStorages(app)
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshUi(app, "storages")
    saveAll(app, "storage enabled")
  end

  function actions.setSelectedRescan(value)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    storage.rescan = value == true
    app.dirty_config = true
    app.dirty_state = true
    refreshHealth(app)
    refreshUi(app, "storages")
    saveAll(app, "storage rescan")
  end

  function actions.setSelectedRuleChoice(field, value)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    storage.rule[field] = value
    storage.rule = planner.normalizeRule(storage.rule)
    app.dirty_config = true
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "rule choice")
  end

  function actions.adjustSelectedRuleNumber(field, delta)
    local storage = selectedStorage(app)
    local meta = constants.NUMERIC_FIELDS[field]
    if not storage or storage.role ~= "home" or not meta then
      return
    end

    local current = storage.rule[field]
    if current == nil then
      if delta < 0 then
        return
      end
      storage.rule[field] = meta.min
    else
      local nextValue = current + (delta * meta.step)
      if nextValue < meta.min then
        storage.rule[field] = nil
      else
        storage.rule[field] = util.clamp(nextValue, meta.min, meta.max)
      end
    end

    storage.rule = planner.normalizeRule(storage.rule)
    app.dirty_config = true
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "rule number")
  end

  function actions.toggleSelectedType(itemType)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" or not constants.SUPPORTED_TYPE_SET[itemType] then
      return
    end

    local nextTypes = {}
    local removed = false
    for _, current in ipairs(storage.rule.item_types or {}) do
      if current == itemType then
        removed = true
      else
        nextTypes[#nextTypes + 1] = current
      end
    end

    if not removed then
      nextTypes[#nextTypes + 1] = itemType
    elseif #nextTypes == 0 then
      nextTypes[#nextTypes + 1] = itemType
    end

    storage.rule.item_types = nextTypes
    storage.rule = planner.normalizeRule(storage.rule)
    app.dirty_config = true
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "rule types")
  end

  function actions.setSelectedFlag(field, value)
    local storage = selectedStorage(app)
    if not storage or storage.role ~= "home" then
      return
    end

    if field ~= "allow_legendary" and field ~= "allow_soulbound" and field ~= "allow_unique" then
      return
    end

    storage.rule[field] = value == true
    storage.rule = planner.normalizeRule(storage.rule)
    app.dirty_config = true
    app.dirty_state = true
    refreshUi(app, "storages")
    saveAll(app, "rule flag")
  end

  function actions.onInspectTimer()
    refreshInspector(app)
    refreshUi(app, "storages")
    saveAll(app, "inspect refresh")
  end

  function actions.onWorkTimer()
    processWork(app, false)
    refreshUi(app, "live")
    saveAll(app, "work cycle")
  end

  function actions.onSaveTimer()
    if app.dirty_config or app.dirty_state then
      saveAll(app, "periodic backup")
    end
    refreshUi(app, "header")
  end

  function actions.onPeripheralEvent(kind)
    refreshDiscovery(app)
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
