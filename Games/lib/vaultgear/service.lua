local constants = require("lib.vaultgear.constants")
local evaluator = require("lib.vaultgear.evaluator")
local model = require("lib.vaultgear.model")

local M = {}
local unpackArgs = table.unpack or unpack

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

local function moveFromInput(inputInventory, destinationName, slot, count)
  local ok, movedOrErr = safeCall(inputInventory, "pushItems", destinationName, slot, count)
  if not ok then
    return nil, tostring(movedOrErr)
  end
  return movedOrErr
end

local function readDetail(inputInventory, slot)
  local ok, detailOrErr = safeCall(inputInventory, "getItemDetail", slot)
  if not ok then
    return nil, tostring(detailOrErr)
  end
  return detailOrErr
end

function M.buildPreview(inputInventory, config, catalog, catalogLib, limit)
  limit = limit or constants.PREVIEW_LIMIT

  local ok, slotMap = safeCall(inputInventory, "list")
  if not ok or type(slotMap) ~= "table" then
    return {
      items = {},
      error = "Could not list input inventory",
    }
  end

  local preview = { items = {}, scanned = 0, catalog_changed = false }
  for _, slot in ipairs(slotKeys(slotMap)) do
    if #preview.items >= limit then
      break
    end

    local basic = slotMap[slot]
    local detail = nil
    local detailError = nil
    if basic and basic.name and basic.name:find("the_vault:", 1, true) == 1 then
      detail, detailError = readDetail(inputInventory, slot)
    end

    local item = model.normalize(slot, basic, detail, detailError)
    local decision = evaluator.evaluate(item, config)
    if catalogLib then
      preview.catalog_changed = catalogLib.observe(catalog, item) or preview.catalog_changed
    end

    preview.items[#preview.items + 1] = {
      slot = slot,
      item = item,
      decision = decision,
      lines = model.summaryLines(item),
    }
    preview.scanned = preview.scanned + 1
    os.sleep(0)
  end

  return preview
end

function M.processCycle(inputInventory, config, catalog, catalogLib)
  local result = {
    processed = 0,
    moved_keep = 0,
    moved_discard = 0,
    errors = {},
    last_decision = nil,
    catalog_changed = false,
  }

  local ok, slotMap = safeCall(inputInventory, "list")
  if not ok or type(slotMap) ~= "table" then
    result.errors[#result.errors + 1] = "Could not list input inventory"
    return result
  end

  local batchLimit = config.runtime.batch_size or 1

  for _, slot in ipairs(slotKeys(slotMap)) do
    if result.processed >= batchLimit then
      break
    end

    local basic = slotMap[slot]
    local detail = nil
    local detailError = nil
    if basic and basic.name and basic.name:find("the_vault:", 1, true) == 1 then
      detail, detailError = readDetail(inputInventory, slot)
    end

    local item = model.normalize(slot, basic, detail, detailError)
    local decision = evaluator.evaluate(item, config)
    if catalogLib then
      result.catalog_changed = catalogLib.observe(catalog, item) or result.catalog_changed
    end

    local destination = config.routing.keep
    if decision.action == "discard" then
      destination = config.routing.trash
    end

    local moved, moveError = moveFromInput(inputInventory, destination, slot, basic.count or 1)
    if type(moved) ~= "number" then
      result.errors[#result.errors + 1] = moveError or ("Move failed for slot " .. tostring(slot))
    elseif moved < 1 then
      result.errors[#result.errors + 1] = "Destination blocked for slot " .. tostring(slot)
    else
      result.processed = result.processed + 1
      if decision.action == "discard" then
        result.moved_discard = result.moved_discard + moved
      else
        result.moved_keep = result.moved_keep + moved
      end
      result.last_decision = {
        item = item,
        decision = decision,
        moved = moved,
      }
    end

    os.sleep(0)
  end

  return result
end

return M
