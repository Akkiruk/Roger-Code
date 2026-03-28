local constants = require("lib.vaultgear.constants")
local util = require("lib.vaultgear.util")

local M = {}

local function routeId(index)
  return "route_" .. tostring(index)
end

local function defaultActionForIndex(index)
  if index == 1 then
    return "keep"
  end
  if index == 2 then
    return "discard"
  end
  return "keep"
end

local function defaultRoute(index, action)
  return {
    id = routeId(index),
    inventory = nil,
    enabled = true,
    match_action = action or defaultActionForIndex(index),
    type_mode = "all",
    match_types = {},
  }
end

local function hasAction(action)
  for _, value in ipairs(constants.ROUTE_ACTIONS) do
    if value == action then
      return true
    end
  end
  return false
end

local function normalizeMatchTypes(matchTypes)
  local filtered = {}
  local seen = {}

  if type(matchTypes) ~= "table" then
    return filtered
  end

  for _, itemType in ipairs(matchTypes) do
    if constants.SUPPORTED_TYPE_SET[itemType] and not seen[itemType] then
      filtered[#filtered + 1] = itemType
      seen[itemType] = true
    end
  end

  return filtered
end

local function normalizeTypeMode(typeMode)
  if typeMode == "selected" then
    return "selected"
  end
  return "all"
end

function M.buildDefaultDestinations()
  return {
    defaultRoute(1, "keep"),
    defaultRoute(2, "discard"),
  }
end

function M.migrateLegacyRouting(routing)
  if type(routing) ~= "table" then
    return nil
  end

  if type(routing.destinations) == "table" then
    return routing
  end

  local migrated = {
    input = routing.input,
    destinations = M.buildDefaultDestinations(),
  }

  migrated.destinations[1].inventory = routing.keep
  migrated.destinations[2].inventory = routing.trash
  return migrated
end

function M.normalizeDestination(destination, index)
  local base = defaultRoute(index, destination and destination.match_action)
  local merged = util.mergeDefaults(base, destination)

  if type(merged.id) ~= "string" or merged.id == "" then
    merged.id = routeId(index)
  end

  if type(merged.inventory) ~= "string" or merged.inventory == "" then
    merged.inventory = nil
  end

  if not hasAction(merged.match_action) then
    merged.match_action = base.match_action
  end

  merged.enabled = merged.enabled ~= false
  merged.type_mode = normalizeTypeMode(merged.type_mode)
  merged.match_types = normalizeMatchTypes(merged.match_types)
  return merged
end

function M.normalizeRouting(routing)
  local normalized = {
    input = nil,
    destinations = {},
  }

  if type(routing) == "table" and type(routing.input) == "string" and routing.input ~= "" then
    normalized.input = routing.input
  end

  local routes = nil
  if type(routing) == "table" and type(routing.destinations) == "table" then
    routes = routing.destinations
  end

  if type(routes) ~= "table" or #routes == 0 then
    routes = M.buildDefaultDestinations()
  end

  for index, destination in ipairs(routes) do
    normalized.destinations[#normalized.destinations + 1] = M.normalizeDestination(destination, index)
  end

  return normalized
end

function M.generateRouteId(destinations)
  local used = {}
  for _, destination in ipairs(destinations or {}) do
    if type(destination.id) == "string" and destination.id ~= "" then
      used[destination.id] = true
    end
  end

  local index = 1
  while used[routeId(index)] do
    index = index + 1
  end
  return routeId(index)
end

function M.newDestination(destinations)
  local nextIndex = #(destinations or {}) + 1
  local destination = defaultRoute(nextIndex, "keep")
  destination.id = M.generateRouteId(destinations)
  return destination
end

function M.findDestination(destinations, id)
  for index, destination in ipairs(destinations or {}) do
    if destination.id == id then
      return destination, index
    end
  end
  return nil, nil
end

function M.destinationMatches(destination, item, decision)
  if type(destination) ~= "table" or destination.enabled == false then
    return false
  end

  if type(destination.inventory) ~= "string" or destination.inventory == "" then
    return false
  end

  if destination.match_action ~= "any" and destination.match_action ~= decision.action then
    return false
  end

  if destination.type_mode ~= "selected" then
    return true
  end

  if type(destination.match_types) ~= "table" or #destination.match_types == 0 then
    return true
  end

  if not constants.SUPPORTED_TYPE_SET[item.item_type] then
    return false
  end

  for _, itemType in ipairs(destination.match_types) do
    if itemType == item.item_type then
      return true
    end
  end

  return false
end

function M.resolveDestination(config, item, decision)
  local destinations = config and config.routing and config.routing.destinations or nil
  for index, destination in ipairs(destinations or {}) do
    if M.destinationMatches(destination, item, decision) then
      return destination, index
    end
  end
  return nil, nil
end

function M.typeSummary(destination)
  if destination and destination.type_mode ~= "selected" then
    return "all items"
  end

  local matchTypes = destination and destination.match_types or nil
  if type(matchTypes) ~= "table" or #matchTypes == 0 then
    return "all vault types"
  end
  if #matchTypes == 1 then
    return matchTypes[1]
  end
  return table.concat(matchTypes, "/")
end

function M.actionSummary(destination)
  local action = destination and destination.match_action or "keep"
  if action == "discard" then
    return "Trash"
  end
  if action == "any" then
    return "Any"
  end
  return "Keep"
end

return M
