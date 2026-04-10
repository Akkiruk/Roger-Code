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

    if #result.items < (limit or 12) then
      result.items[#result.items + 1] = {
        slot = slot,
        item = item,
        lines = model.summaryLines(item),
      }
    end

    os.sleep(0)
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
    local bridge, items, err = loadBridgeItems(inventoryName)
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

    for slot, basic in ipairs(items) do
      if type(basic) == "table" then
        result.total_slots = result.total_slots + 1
        if isVaultRegistryName(basic.name) then
          result.vault_items = result.vault_items + 1
        end
        if #result.items < (limit or 12) then
          local item, lines = summarizeBridgeItem(slot, basic)
          result.items[#result.items + 1] = {
            slot = slot,
            item = item,
            lines = lines,
          }
        end
      end
      os.sleep(0)
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

local function routeBridgeItem(report, bridgeStorage, bridge, bridgeItem, homes, stagingStorage, stagingInventory, catalog, catalogLib)
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

  local movedTotal = movedFromStage
  local remaining = math.max(0, (tonumber(bridgeItem.count) or 1) - movedFromStage)
  if remaining > 0 then
    local directMoved, directError = bridgeExportItem(bridge, buildBridgeFilter(bridgeItem, remaining), picked.storage.inventory)
    if type(directMoved) == "number" and directMoved > 0 then
      movedTotal = movedTotal + directMoved
    elseif directError then
      report.errors[#report.errors + 1] = directError
      local routeFailure = classifyMoveFailure(bridgeStorage.inventory, picked.storage.inventory, directError)
      if routeFailure then
        report.route_failures[#report.route_failures + 1] = routeFailure
      end
    end
  end

  report.kind = "routing"
  report.moved_stacks = report.moved_stacks + 1
  report.moved_items = report.moved_items + movedTotal
  report.action = buildMoveAction("route", bridgeStorage.inventory, picked.storage, item, picked.reasons and picked.reasons[1], movedTotal)
end

local function processStandardInbox(report, storage, homes, catalog, catalogLib)
  report.target_inventory = storage.inventory
  local inventory, slotMap, err = loadSlotMap(storage.inventory)
  if err then
    report.errors[#report.errors + 1] = err
    return
  end

  for _, slot in ipairs(slotKeys(slotMap)) do
    local basic = slotMap[slot]
    local item = normalizeSlot(inventory, slot, basic)
    report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

    local picked = planner.pickDestination(homes, item, storage.inventory)
    if picked and picked.storage and picked.storage.inventory ~= storage.inventory then
      local moved, moveError = moveItem(inventory, picked.storage.inventory, slot, basic.count or 1)
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
    elseif item.supported_type then
      report.unresolved = report.unresolved + 1
    end

    os.sleep(0)
  end
end

local function processBridgeInbox(report, storage, storages, connectedSet, homes, catalog, catalogLib)
  report.target_inventory = storage.inventory

  local bridge, items, err = loadBridgeItems(storage.inventory)
  if err then
    report.errors[#report.errors + 1] = err
    return
  end

  local stagingStorage, stagingInventory = findBridgeInspectionInbox(storages, connectedSet, storage.inventory)
  if not stagingStorage or not stagingInventory then
    report.errors[#report.errors + 1] = "ME Bridge inboxes need another connected inbox with getItemDetail() so Vault items can be inspected before routing."
    return
  end

  for _, bridgeItem in ipairs(items) do
    if type(bridgeItem) == "table" and isVaultRegistryName(bridgeItem.name) then
      routeBridgeItem(report, storage, bridge, bridgeItem, homes, stagingStorage, stagingInventory, catalog, catalogLib)
      os.sleep(0)
    end
  end
end

function M.processInboxes(storages, connectedSet, catalog, catalogLib)
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
  }

  local homes = planner.listHomes(storages, connectedSet)
  if #homes == 0 then
    return report
  end

  for _, storage in ipairs(planner.listInboxes(storages, connectedSet)) do
    local wrapped = safeWrap(storage.inventory)
    if wrapped and isMeBridge(storage.inventory, wrapped) then
      processBridgeInbox(report, storage, storages, connectedSet, homes, catalog, catalogLib)
    else
      processStandardInbox(report, storage, homes, catalog, catalogLib)
    end
  end

  return report
end

function M.processRepair(storages, connectedSet, runtimeState, catalog, catalogLib)
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

  report.kind = "repair_scan"
  report.target_inventory = homes[1].inventory

  for _, storage in ipairs(homes) do
    report.target_inventory = storage.inventory

    local inventory, slotMap, err = loadSlotMap(storage.inventory)
    if err then
      report.errors[#report.errors + 1] = err
    else
      for _, slot in ipairs(slotKeys(slotMap)) do
        local basic = slotMap[slot]
        local item = normalizeSlot(inventory, slot, basic)
        report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

        local picked = planner.pickDestination(homes, item, storage.inventory)
        if picked and picked.storage and picked.storage.inventory ~= storage.inventory then
          local moved, moveError = moveItem(inventory, picked.storage.inventory, slot, basic.count or 1)
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
        end

        os.sleep(0)
      end
    end
  end

  return report
end

return M
