local model = require("lib.vaultgear.model")
local planner = require("lib.vaultgear.planner")

local M = {}
local unpackArgs = table.unpack or unpack

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

local function slotKeys(slotMap)
  local keys = {}
  for slot in pairs(slotMap or {}) do
    keys[#keys + 1] = slot
  end
  table.sort(keys)
  return keys
end

local function readDetail(inventory, slot, basic)
  if not basic or not basic.name or basic.name:find("the_vault:", 1, true) ~= 1 then
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
  if message:find(missingTarget, 1, true) then
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
