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

local function isMeBridge(name)
  return peripheral.hasType(name, "me_bridge") == true
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
    lines[#lines + 1] = "Vault item gets read in the ME and routed to its home."
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

-- one page of bridge entries; filter and opts go straight to bridge.list
local function loadBridgePage(inventoryName, filter, opts)
  local bridge = safeWrap(inventoryName)
  if not bridge then
    return nil, nil, "Inventory missing: " .. tostring(inventoryName)
  end
  if not isMeBridge(inventoryName) then
    return bridge, nil, "ME Bridge missing: " .. tostring(inventoryName)
  end

  local ok, page, code = pcall(bridge.list, filter, opts)
  if not ok then
    return bridge, nil, tostring(page), nil
  end
  if type(page) ~= "table" then
    return bridge, nil, "Could not list ME Bridge " .. tostring(inventoryName) .. ": " .. tostring(code), code
  end

  return bridge, page, nil
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

  if isMeBridge(inventoryName) then
    local sampleLimit = math.max(1, tonumber(limit) or constants.INSPECT_LIMIT)
    local _, page, err = loadBridgePage(inventoryName, { minCount = 1 }, { limit = sampleLimit, names = true })
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

    for slot, basic in ipairs(page.items) do
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

-- ids name an exact NBT state, which is what the bridge moves by
local function bridgeIdentityKey(item)
  if type(item) ~= "table" or type(item.id) ~= "string" then
    return ""
  end
  return item.id
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

local function bridgeExport(bridge, id, targetName)
  local ok, result = pcall(bridge.export, id, targetName, { count = 1 })
  if not ok then
    return 0, tostring(result)
  end
  if result.moved < 1 then
    return 0, "ME Bridge export to " .. tostring(targetName) .. " failed: " .. tostring(result.reason)
  end
  return result.moved, nil
end

-- getDetail reads vaultData straight off the ME key, so nothing has to leave the ME until we know where it goes
local function routeBridgeItem(report, bridgeStorage, bridge, entry, homes, runtimeState, catalog, catalogLib)
  local ok, detail, code = pcall(bridge.getDetail, entry.id)
  if not ok or type(detail) ~= "table" then
    -- gone since the list, nothing to do
    if ok and code == "NOT_FOUND" then
      return
    end
    report.errors[#report.errors + 1] = "Could not read " .. tostring(entry.name) .. " in the ME: " .. tostring(ok and code or detail)
    return
  end

  local item = model.normalize(nil, { name = entry.name, count = 1 }, detail, nil)
  report.catalog_changed = observeItem(catalog, catalogLib, item) or report.catalog_changed

  local picked = planner.pickDestination(homes, item, bridgeStorage.inventory)
  if not picked or not picked.storage or picked.storage.inventory == bridgeStorage.inventory then
    if item.supported_type then
      report.unresolved = report.unresolved + 1
    end
    rememberBridgeSkip(runtimeState, bridgeStorage.inventory, entry)
    return
  end

  local moved, moveError = bridgeExport(bridge, entry.id, picked.storage.inventory)
  if moved < 1 then
    report.errors[#report.errors + 1] = moveError
    local routeFailure = classifyMoveFailure(bridgeStorage.inventory, picked.storage.inventory, moveError)
    if routeFailure then
      report.route_failures[#report.route_failures + 1] = routeFailure
    end
    return
  end

  report.kind = "routing"
  report.moved_stacks = report.moved_stacks + 1
  report.moved_items = report.moved_items + moved
  report.action = buildMoveAction("route", bridgeStorage.inventory, picked.storage, item, picked.reasons and picked.reasons[1], moved)
  clearBridgeSkip(runtimeState, bridgeStorage.inventory, entry)
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

local function processBridgeInboxStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
  report.target_inventory = storage.inventory

  local bridge, page, err, code = loadBridgePage(storage.inventory, { mod = "the_vault", minCount = 1 },
    { limit = budget, after = runtimeState.bridge_after })
  if code == "INDEXING" then
    -- the bridge is still hashing a fresh grid, try again next step
    return true, false, 0
  end
  if err then
    report.errors[#report.errors + 1] = err
    runtimeState.bridge_after = nil
    return true, true, 0
  end

  local inspected = 0
  local prev = runtimeState.bridge_after

  for _, entry in ipairs(page.items) do
    if not shouldSkipBridgeItem(runtimeState, storage.inventory, entry) then
      inspected = inspected + 1
      local priorMoves = report.moved_stacks
      local priorErrors = #report.errors
      local priorUnresolved = report.unresolved
      routeBridgeItem(report, storage, bridge, entry, homes, runtimeState, catalog, catalogLib)

      if report.unresolved > priorUnresolved then
        runtimeState.unresolved_scan = runtimeState.unresolved_scan + (report.unresolved - priorUnresolved)
        report.unresolved = priorUnresolved
      end

      if report.moved_stacks > priorMoves or #report.errors > priorErrors then
        -- come back to this key, there may be more of it
        runtimeState.bridge_after = prev
        return true, false, inspected
      end
    end
    prev = entry.id
  end

  runtimeState.bridge_after = page.next
  return false, page.next == nil, inspected
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

    local yielded, exhausted, inspected
    if isMeBridge(storage.inventory) then
      yielded, exhausted, inspected = processBridgeInboxStep(report, storage, homes, runtimeState, catalog, catalogLib, budget)
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
