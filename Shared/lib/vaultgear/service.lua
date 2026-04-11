local constants = require("lib.vaultgear.constants")
local model = require("lib.vaultgear.model")
local planner = require("lib.vaultgear.planner")

local M = {}
local unpackArgs = table.unpack or unpack

local function isVaultRegistryName(registryName)
  return type(registryName) == "string" and registryName:find("the_vault:", 1, true) == 1
end

local function safeWrap(name)
  local ok, wrapped = pcall(peripheral.wrap, name)
  if ok then
    return wrapped
  end
  return nil
end

local function safeCall(methodOwner, methodName, ...)
  if not methodOwner or type(methodOwner[methodName]) ~= "function" then
    return false, "Missing method: " .. tostring(methodName)
  end

  local args = { ... }
  return pcall(function()
    return methodOwner[methodName](unpackArgs(args))
  end)
end

local function safeCallAny(methodOwner, methodNames, ...)
  if not methodOwner then
    return false, nil, nil, "Missing method owner"
  end

  local args = { ... }
  for _, methodName in ipairs(methodNames or {}) do
    if type(methodOwner[methodName]) == "function" then
      local ok, first, second = pcall(function()
        return methodOwner[methodName](unpackArgs(args))
      end)
      if not ok then
        return false, nil, nil, tostring(first)
      end
      return true, first, second, nil
    end
  end

  return false, nil, nil, "Missing method: " .. table.concat(methodNames or {}, " or ")
end

local function isMeBridge(name, wrapped)
  local peripheralType = peripheral.getType(name)
  if peripheralType == "meBridge" or peripheralType == "me_bridge" then
    return true
  end

  return wrapped
    and (type(wrapped.getItems) == "function" or type(wrapped.listItems) == "function")
    and (type(wrapped.exportItem) == "function" or type(wrapped.exportItemToPeripheral) == "function")
end

local function slotKeys(slotMap)
  local keys = {}
  for slot in pairs(slotMap or {}) do
    keys[#keys + 1] = slot
  end
  table.sort(keys)
  return keys
end

local function readDetail(inventory, slot, basic)
  if not basic or not isVaultRegistryName(basic.name) then
    return nil, nil
  end

  local ok, detailOrErr = safeCall(inventory, "getItemDetail", slot)
  if not ok then
    return nil, tostring(detailOrErr)
  end
  return detailOrErr, nil
end

local function normalizeSlot(inventory, slot, basic)
  local detail, detailError = readDetail(inventory, slot, basic)
  return model.normalize(slot, basic, detail, detailError)
end

local function summarizeBridgeItem(slot, basic)
  local item = model.normalize(slot, {
    name = basic.name,
    count = basic.count,
  }, {
    name = basic.name,
    displayName = basic.displayName,
  }, nil)

  local lines = {
    tostring(basic.displayName or basic.name or "Unknown item"),
    "ME Bridge | Count " .. tostring(basic.count or 0),
  }

  if isVaultRegistryName(basic.name) then
    lines[#lines + 1] = "Vault item will be inspected through a physical inbox when routed."
  else
    lines[#lines + 1] = "Non-vault items stay in the ME system."
  end

  return item, lines
end

local function loadSlotMap(inventoryName)
  local inventory = safeWrap(inventoryName)
  if not inventory then
    return nil, nil, "Inventory missing: " .. tostring(inventoryName)
  end

  local ok, slotMap = safeCall(inventory, "list")
  if not ok or type(slotMap) ~= "table" then
    return inventory, nil, "Could not list inventory: " .. tostring(inventoryName)
  end

  return inventory, slotMap, nil
end

local function loadBridgeItems(inventoryName)
  local bridge = safeWrap(inventoryName)
  if not bridge then
    return nil, nil, "Inventory missing: " .. tostring(inventoryName)
  end
  if not isMeBridge(inventoryName, bridge) then
    return bridge, nil, "ME Bridge missing: " .. tostring(inventoryName)
  end

  local ok, items, apiError, callError = safeCallAny(bridge, { "getItems", "listItems" }, {})
  if not ok then
    return bridge, nil, callError or "Could not list ME Bridge: " .. tostring(inventoryName)
  end
  if type(items) ~= "table" then
    return bridge, nil, tostring(apiError or "Could not list ME Bridge: " .. tostring(inventoryName))
  end

  return bridge, items, nil
end

local function observeItem(catalog, catalogLib, item)
  if catalogLib then
    return catalogLib.observe(catalog, item) == true
  end
  return false
end

local function inspectWrappedInventory(inventoryName, inventory, slotMap, catalog, catalogLib, limit)
  local result = {
    inventory = inventoryName,
    items = {},
    total_slots = 0,
    supported_items = 0,
    vault_items = 0,
    catalog_changed = false,
    error = nil,
  }

  local sampleLimit = math.max(1, tonumber(limit) or constants.INSPECT_LIMIT)

  for _, slot in ipairs(slotKeys(slotMap)) do
    local basic = slotMap[slot]
    local item = normalizeSlot(inventory, slot, basic)
    result.total_slots = result.total_slots + 1
    if item.vault then
      result.vault_items = result.vault_items + 1
    end
    if item.supported_type then
      result.supported_items = result.supported_items + 1
    end
    result.catalog_changed = observeItem(catalog, catalogLib, item) or result.catalog_changed
    result.items[#result.items + 1] = {
      slot = slot,
      item = item,
      lines = model.summaryLines(item),
    }

    if #result.items >= sampleLimit then
      break
    end
  end

  return result
end

function M.inspectInventory(inventoryName, catalog, catalogLib, limit)
  if not inventoryName or inventoryName == "" then
    return {
      inventory = inventoryName,
      items = {},
      error = "No inventory selected.",
      catalog_changed = false,
      total_slots = 0,
      supported_items = 0,
      vault_items = 0,
    }
  end

  local wrapped = safeWrap(inventoryName)
  if wrapped and isMeBridge(inventoryName, wrapped) then
    local _, items, err = loadBridgeItems(inventoryName)
    if err then
      return {
        inventory = inventoryName,
        items = {},
        error = err,
        catalog_changed = false,
        total_slots = 0,
        supported_items = 0,
        vault_items = 0,
      }
    end

    local result = {
      inventory = inventoryName,
      items = {},
      error = nil,
      catalog_changed = false,
      total_slots = 0,
      supported_items = 0,
      vault_items = 0,
    }
    local sampleLimit = math.max(1, tonumber(limit) or constants.INSPECT_LIMIT)

    for slot, basic in ipairs(items) do
      if type(basic) == "table" then
        result.total_slots = result.total_slots + 1
        if isVaultRegistryName(basic.name) then
          result.vault_items = result.vault_items + 1
        end

        local item, lines = summarizeBridgeItem(slot, basic)
        result.items[#result.items + 1] = {
          slot = slot,
          item = item,
          lines = lines,
        }

        if #result.items >= sampleLimit then
          break
        end
      end
    end

    return result
  end

  local inventory, slotMap, err = loadSlotMap(inventoryName)
  if err then
    return {
      inventory = inventoryName,
      items = {},
      error = err,
      catalog_changed = false,
      total_slots = 0,
      supported_items = 0,
      vault_items = 0,
    }
  end

  return inspectWrappedInventory(inventoryName, inventory, slotMap, catalog, catalogLib, limit)
end

local function moveItem(sourceInventory, destinationName, slot, count)
  local ok, movedOrErr = safeCall(sourceInventory, "pushItems", destinationName, slot, count)
  if not ok then
    return nil, tostring(movedOrErr)
  end
  return movedOrErr, nil
end

local function classifyMoveFailure(sourceName, destinationName, moveError)
  local message = tostring(moveError or "Unknown move failure")
  local missingTarget = "Target '" .. tostring(destinationName) .. "' does not exist"
  local normalized = message:lower()
  if message:find(missingTarget, 1, true)
    or normalized:find("inventory_not_found", 1, true)
    or normalized:find("peripheral_not_found", 1, true)
    or normalized:find("does not exist", 1, true) then
    return {
      code = "missing_target",
      source = sourceName,
      destination = destinationName,
      error = message,
    }
  end
  return nil
end

local function buildMoveAction(kind, sourceName, destination, item, reason, moved)
  return {
    kind = kind,
    source = sourceName,
    destination = destination and destination.inventory or nil,
    destination_id = destination and destination.id or nil,
    item = item,
    moved = moved or 0,
    reason = reason,
  }
end

local function buildBridgeFilter(item, count)
  local filter = {
    name = item and item.name or nil,
    count = count or (item and item.count) or 1,
  }

  if item and item.fingerprint ~= nil then
    filter.fingerprint = item.fingerprint
  end
  if item and item.components ~= nil then
    filter.components = item.components
  elseif item and item.nbt ~= nil then
    filter.nbt = item.nbt
  end

  return filter
end

local function bridgeIdentityPart(value)
  if type(value) == "table" then
    return textutils.serialize(value)
  end
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function bridgeIdentityKey(item)
  if type(item) ~= "table" then
    return ""
  end

  return table.concat({
    tostring(item.name or ""),
    bridgeIdentityPart(item.fingerprint),
    bridgeIdentityPart(item.components),
    bridgeIdentityPart(item.nbt),
  }, "|")
end

local function bridgeSkipBucket(runtimeState, inventoryName, create)
  if type(runtimeState.bridge_skip) ~= "table" then
    runtimeState.bridge_skip = {}
  end

  local key = tostring(inventoryName or "")
  local bucket = runtimeState.bridge_skip[key]
  if bucket == nil and create then
    bucket = {}
    runtimeState.bridge_skip[key] = bucket
  end
  return bucket
end

local function clearBridgeSkip(runtimeState, inventoryName, item)
  local bucket = bridgeSkipBucket(runtimeState, inventoryName, false)
  if not bucket then
    return
  end

  local key = bridgeIdentityKey(item)
  if key ~= "" then
    bucket[key] = nil
  end

  if next(bucket) == nil then
    runtimeState.bridge_skip[tostring(inventoryName or "")] = nil
  end
end

local function rememberBridgeSkip(runtimeState, inventoryName, item)
  local key = bridgeIdentityKey(item)
  if key == "" then
    return
  end

  local bucket = bridgeSkipBucket(runtimeState, inventoryName, true)
  bucket[key] = {
    count = tonumber(item and item.count) or 0,
    retry_after = os.epoch("local") + (math.max(1, tonumber(constants.BRIDGE_RETRY_COOLDOWN) or 1) * 1000),
  }
end

local function shouldSkipBridgeItem(runtimeState, inventoryName, item)
  local bucket = bridgeSkipBucket(runtimeState, inventoryName, false)
  if not bucket then
    return false
  end

  local key = bridgeIdentityKey(item)
  if key == "" then
    return false
  end

  local cached = bucket[key]
  if type(cached) ~= "table" then
    return false
  end

  local currentCount = tonumber(item and item.count) or 0
  local cachedCount = tonumber(cached.count) or 0
  local retryAfter = tonumber(cached.retry_after) or 0
  if currentCount ~= cachedCount or os.epoch("local") >= retryAfter then
    bucket[key] = nil
    if next(bucket) == nil then
      runtimeState.bridge_skip[tostring(inventoryName or "")] = nil
    end
    return false
  end

  return true
end

local function bridgeExportItem(bridge, filter, targetName)
  local ok, moved, apiError, callError = safeCallAny(bridge, { "exportItem", "exportItemToPeripheral" }, filter, targetName)
  if not ok then
    return nil, callError
  end
  if type(moved) ~= "number" or moved < 1 then
    return moved or 0, tostring(apiError or "ME Bridge export failed")
  end
  return moved, nil
end

local function bridgeImportItem(bridge, filter, sourceName)
  local ok, moved, apiError, callError = safeCallAny(bridge, { "importItem", "importItemFromPeripheral" }, filter, sourceName)
  if not ok then
    return nil, callError
  end
  if type(moved) ~= "number" or moved < 1 then
    return moved or 0, tostring(apiError or "ME Bridge import failed")
  end
  return moved, nil
end

local function changedSlot(beforeMap, afterMap, itemName)
  for _, slot in ipairs(slotKeys(afterMap)) do
    local current = afterMap[slot]
    if current and current.name == itemName then
      local previous = beforeMap and beforeMap[slot] or nil
      local previousCount = previous and tonumber(previous.count) or 0
      local currentCount = tonumber(current.count) or 0
      if currentCount > previousCount then
        return slot, current
      end
    end
  end
  return nil, nil
end

local function findBridgeInspectionInbox(storages, connectedSet, sourceInventory)
  for _, storage in ipairs(planner.listInboxes(storages, connectedSet)) do
    if storage.inventory ~= sourceInventory then
      local inventory = safeWrap(storage.inventory)
      if inventory
        and type(inventory.list) == "function"
        and type(inventory.getItemDetail) == "function"
        and type(inventory.pushItems) == "function" then
        return storage, inventory
      end
    end
  end
  return nil, nil
end

local function routeBridgeItem(report, bridgeStorage, bridge, bridgeItem, homes, stagingStorage, stagingInventory, runtimeState, catalog, catalogLib)
  local baselineInventory, baselineSlots, baselineError = loadSlotMap(stagingStorage.inventory)
  if baselineError then
    report.errors[#report.errors + 1] = baselineError
    return
  end

  local singleFilter = buildBridgeFilter(bridgeItem, 1)
  local exported, exportError = bridgeExportItem(bridge, singleFilter, stagingStorage.inventory)
  if type(exported) ~= "number" or exported < 1 then
    report.errors[#report.errors + 1] = exportError or ("ME Bridge export failed from " .. tostring(bridgeStorage.inventory))
    local routeFailure = classifyMoveFailure(bridgeStorage.inventory, stagingStorage.inventory, exportError)
    if routeFailure then
      report.route_failures[#report.route_failures + 1] = routeFailure
    end
    return
  end

  local _, stagedSlots, stagedError = loadSlotMap(stagingStorage.inventory)
  if stagedError then
    report.errors[#report.errors + 1] = stagedError
    return
  end

  local slot, basic = changedSlot(baselineSlots, stagedSlots, bridgeItem.name)
  if not slot or not basic then
    report.errors[#report.errors + 1] = "ME Bridge exported an item, but the inspection inbox could not locate it."
    local restored, restoreError = bridgeImportItem(bridge, singleFilter, stagingStorage.inventory)
    if type(restored) ~= "number" or restored < 1 then
      report.errors[#report.errors + 1] = restoreError or "Could not return staged ME Bridge item to the system."
    end
    return
  end

  local item = normalizeSlot(stagingInventory or baselineInventory, slot, basic)
  report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

  local picked = planner.pickDestination(homes, item, bridgeStorage.inventory)
  if not picked or not picked.storage or picked.storage.inventory == bridgeStorage.inventory then
    if item.supported_type then
      report.unresolved = report.unresolved + 1
    end

    local restored, restoreError = bridgeImportItem(bridge, singleFilter, stagingStorage.inventory)
    if type(restored) ~= "number" or restored < 1 then
      report.errors[#report.errors + 1] = restoreError or "Could not return unresolved ME Bridge item to the system."
    end
    rememberBridgeSkip(runtimeState, bridgeStorage.inventory, bridgeItem)
    return
  end

  local movedFromStage, moveError = moveItem(stagingInventory or baselineInventory, picked.storage.inventory, slot, 1)
  if type(movedFromStage) ~= "number" or movedFromStage < 1 then
    report.errors[#report.errors + 1] = moveError or ("Move failed from " .. tostring(stagingStorage.inventory))
    local routeFailure = classifyMoveFailure(bridgeStorage.inventory, picked.storage.inventory, moveError)
    if routeFailure then
      report.route_failures[#report.route_failures + 1] = routeFailure
    end

    local restored, restoreError = bridgeImportItem(bridge, singleFilter, stagingStorage.inventory)
    if type(restored) ~= "number" or restored < 1 then
      report.errors[#report.errors + 1] = restoreError or "Could not return staged ME Bridge item to the system."
    end
    return
  end

  report.kind = "routing"
  report.moved_stacks = report.moved_stacks + 1
  report.moved_items = report.moved_items + movedFromStage
  report.action = buildMoveAction("route", bridgeStorage.inventory, picked.storage, item, picked.reasons and picked.reasons[1], movedFromStage)
  clearBridgeSkip(runtimeState, bridgeStorage.inventory, bridgeItem)
end

local function ensureRuntimeState(runtimeState)
  if type(runtimeState) ~= "table" then
    runtimeState = {}
  end

  runtimeState.inbox_cursor = tonumber(runtimeState.inbox_cursor) or 1
  runtimeState.inbox_slot = tonumber(runtimeState.inbox_slot) or 0
  runtimeState.repair_cursor = tonumber(runtimeState.repair_cursor) or 1
  runtimeState.repair_slot = tonumber(runtimeState.repair_slot) or 0
  runtimeState.unresolved_scan = tonumber(runtimeState.unresolved_scan) or 0
  if type(runtimeState.bridge_skip) ~= "table" then
    runtimeState.bridge_skip = {}
  end
  return runtimeState
end

local function nextCursorIndex(index, count)
  if count < 1 then
    return 1
  end
  return (index % count) + 1
end

local function nextSlotPosition(slots, cursorSlot)
  if #slots == 0 then
    return nil
  end

  local current = tonumber(cursorSlot) or 0
  if current < 1 then
    return 1
  end

  for position, slot in ipairs(slots) do
    if slot > current then
      return position
    end
  end

  return 1
end

local function processStandardInboxStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
  report.target_inventory = storage.inventory

  local inventory, slotMap, err = loadSlotMap(storage.inventory)
  if err then
    report.errors[#report.errors + 1] = err
    runtimeState.inbox_slot = 0
    return true, true, 0
  end

  local slots = slotKeys(slotMap)
  if #slots == 0 then
    runtimeState.inbox_slot = 0
    return false, true, 0
  end

  local startPosition = nextSlotPosition(slots, runtimeState.inbox_slot)
  local visited = 0
  local inspected = 0

  while visited < #slots and inspected < budget do
    local position = ((startPosition - 1 + visited) % #slots) + 1
    local slot = slots[position]
    local basic = slotMap[slot]
    runtimeState.inbox_slot = slot
    inspected = inspected + 1
    visited = visited + 1

    local item = normalizeSlot(inventory, slot, basic)
    report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

    local picked = planner.pickDestination(homes, item, storage.inventory)
    if picked and picked.storage and picked.storage.inventory ~= storage.inventory then
      local moved, moveError = moveItem(inventory, picked.storage.inventory, slot, 1)
      if type(moved) ~= "number" or moved < 1 then
        report.errors[#report.errors + 1] = moveError or ("Move failed from " .. tostring(storage.inventory))
        local routeFailure = classifyMoveFailure(storage.inventory, picked.storage.inventory, moveError)
        if routeFailure then
          report.route_failures[#report.route_failures + 1] = routeFailure
        end
      else
        report.kind = "routing"
        report.moved_stacks = report.moved_stacks + 1
        report.moved_items = report.moved_items + moved
        report.action = buildMoveAction("route", storage.inventory, picked.storage, item, picked.reasons and picked.reasons[1], moved)
      end

      runtimeState.inbox_slot = math.max(0, slot - 1)
      return true, false, inspected
    end

    if item.supported_type then
      runtimeState.unresolved_scan = runtimeState.unresolved_scan + 1
    end
  end

  if visited >= #slots then
    runtimeState.inbox_slot = 0
    return false, true, inspected
  end

  return false, false, inspected
end

local function processBridgeInboxStep(report, storage, storages, connectedSet, homes, runtimeState, catalog, catalogLib, budget)
  report.target_inventory = storage.inventory

  local bridge, items, err = loadBridgeItems(storage.inventory)
  if err then
    report.errors[#report.errors + 1] = err
    runtimeState.inbox_slot = 0
    return true, true, 0
  end

  local stagingStorage, stagingInventory = findBridgeInspectionInbox(storages, connectedSet, storage.inventory)
  if not stagingStorage or not stagingInventory then
    report.errors[#report.errors + 1] = "ME Bridge inboxes need another connected inbox with getItemDetail() so Vault items can be inspected before routing."
    runtimeState.inbox_slot = 0
    return true, true, 0
  end

  local totalItems = #items
  if totalItems == 0 then
    runtimeState.inbox_slot = 0
    return false, true, 0
  end

  local startIndex = tonumber(runtimeState.inbox_slot) or 0
  if startIndex < 1 or startIndex > totalItems then
    startIndex = 1
  else
    startIndex = nextCursorIndex(startIndex, totalItems)
  end

  local visited = 0
  local inspected = 0

  while visited < totalItems and inspected < budget do
    local index = ((startIndex - 1 + visited) % totalItems) + 1
    local bridgeItem = items[index]
    runtimeState.inbox_slot = index
    visited = visited + 1

    if type(bridgeItem) == "table"
      and isVaultRegistryName(bridgeItem.name)
      and not shouldSkipBridgeItem(runtimeState, storage.inventory, bridgeItem) then
      inspected = inspected + 1
      local priorMoves = report.moved_stacks
      local priorErrors = #report.errors
      local priorUnresolved = report.unresolved
      routeBridgeItem(report, storage, bridge, bridgeItem, homes, stagingStorage, stagingInventory, runtimeState, catalog, catalogLib)

      if report.unresolved > priorUnresolved then
        runtimeState.unresolved_scan = runtimeState.unresolved_scan + (report.unresolved - priorUnresolved)
        report.unresolved = priorUnresolved
      end

      if report.moved_stacks > priorMoves or #report.errors > priorErrors then
        runtimeState.inbox_slot = math.max(0, index - 1)
        return true, false, inspected
      end
    end
  end

  if visited >= totalItems then
    runtimeState.inbox_slot = 0
    return false, true, inspected
  end

  return false, false, inspected
end

function M.processInboxes(storages, connectedSet, runtimeState, catalog, catalogLib)
  runtimeState = ensureRuntimeState(runtimeState)

  local report = {
    kind = "idle",
    moved_stacks = 0,
    moved_items = 0,
    unresolved = 0,
    errors = {},
    route_failures = {},
    action = nil,
    target_inventory = nil,
    catalog_changed = false,
    inbox_pass_complete = false,
  }

  local homes = planner.listHomes(storages, connectedSet)
  local inboxes = planner.listInboxes(storages, connectedSet)
  if #homes == 0 or #inboxes == 0 then
    runtimeState.unresolved_scan = 0
    report.inbox_pass_complete = true
    return report
  end

  local cursorIndex = math.min(math.max(tonumber(runtimeState.inbox_cursor) or 1, 1), #inboxes)
  local budget = math.max(1, tonumber(constants.WORK_SCAN_BUDGET) or 1)

  for offset = 0, #inboxes - 1 do
    local storageIndex = ((cursorIndex - 1 + offset) % #inboxes) + 1
    local storage = inboxes[storageIndex]
    runtimeState.inbox_cursor = storageIndex

    local wrapped = safeWrap(storage.inventory)
    local yielded, exhausted, inspected
    if wrapped and isMeBridge(storage.inventory, wrapped) then
      yielded, exhausted, inspected = processBridgeInboxStep(report, storage, storages, connectedSet, homes, runtimeState, catalog, catalogLib, budget)
    else
      yielded, exhausted, inspected = processStandardInboxStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
    end

    budget = budget - (inspected or 0)

    if report.action or #report.errors > 0 or yielded then
      return report
    end

    if exhausted then
      runtimeState.inbox_cursor = nextCursorIndex(storageIndex, #inboxes)
      runtimeState.inbox_slot = 0
    end

    if budget < 1 then
      return report
    end
  end

  report.unresolved = runtimeState.unresolved_scan
  runtimeState.unresolved_scan = 0
  report.inbox_pass_complete = true
  return report
end

local function processRepairStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
  report.kind = "repair_scan"
  report.target_inventory = storage.inventory

  local inventory, slotMap, err = loadSlotMap(storage.inventory)
  if err then
    report.errors[#report.errors + 1] = err
    runtimeState.repair_slot = 0
    return true, true, 0
  end

  local slots = slotKeys(slotMap)
  if #slots == 0 then
    runtimeState.repair_slot = 0
    return false, true, 0
  end

  local startPosition = nextSlotPosition(slots, runtimeState.repair_slot)
  local visited = 0
  local inspected = 0

  while visited < #slots and inspected < budget do
    local position = ((startPosition - 1 + visited) % #slots) + 1
    local slot = slots[position]
    local basic = slotMap[slot]
    runtimeState.repair_slot = slot
    inspected = inspected + 1
    visited = visited + 1

    local item = normalizeSlot(inventory, slot, basic)
    report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

    local picked = planner.pickDestination(homes, item, storage.inventory)
    if picked and picked.storage and picked.storage.inventory ~= storage.inventory then
      local moved, moveError = moveItem(inventory, picked.storage.inventory, slot, 1)
      if type(moved) ~= "number" or moved < 1 then
        report.errors[#report.errors + 1] = moveError or ("Repair move failed from " .. tostring(storage.inventory))
        local routeFailure = classifyMoveFailure(storage.inventory, picked.storage.inventory, moveError)
        if routeFailure then
          report.route_failures[#report.route_failures + 1] = routeFailure
        end
      else
        report.kind = "repair"
        report.moved_stacks = report.moved_stacks + 1
        report.moved_items = report.moved_items + moved
        report.action = buildMoveAction("repair", storage.inventory, picked.storage, item, picked.reasons and picked.reasons[1], moved)
      end

      runtimeState.repair_slot = math.max(0, slot - 1)
      return true, false, inspected
    end
  end

  if visited >= #slots then
    runtimeState.repair_slot = 0
    return false, true, inspected
  end

  return false, false, inspected
end

function M.processRepair(storages, connectedSet, runtimeState, catalog, catalogLib)
  runtimeState = ensureRuntimeState(runtimeState)

  local report = {
    kind = "idle",
    moved_stacks = 0,
    moved_items = 0,
    errors = {},
    route_failures = {},
    action = nil,
    target_inventory = nil,
    catalog_changed = false,
  }

  local homes = {}
  for _, storage in ipairs(planner.listHomes(storages, connectedSet)) do
    if storage.rescan ~= false then
      homes[#homes + 1] = storage
    end
  end

  if #homes == 0 then
    return report
  end

  local cursorIndex = math.min(math.max(tonumber(runtimeState.repair_cursor) or 1, 1), #homes)
  local budget = math.max(1, tonumber(constants.WORK_SCAN_BUDGET) or 1)

  for offset = 0, #homes - 1 do
    local storageIndex = ((cursorIndex - 1 + offset) % #homes) + 1
    local storage = homes[storageIndex]
    runtimeState.repair_cursor = storageIndex

    local yielded, exhausted, inspected = processRepairStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
    budget = budget - (inspected or 0)

    if report.action or #report.errors > 0 or yielded then
      return report
    end

    if exhausted then
      runtimeState.repair_cursor = nextCursorIndex(storageIndex, #homes)
      runtimeState.repair_slot = 0
    end

    if budget < 1 then
      return report
    end
  end

  report.kind = "repair_scan"
  report.target_inventory = homes[cursorIndex] and homes[cursorIndex].inventory or nil
  return report
end

return M
