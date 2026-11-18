-- core/vehicles.lua
-- Every vehicle the game knows, as definitions checked against one schema, and the physics each class uses.
-- Today's cars (sg/vehicle.lua TYPES) are registered here as class "car". Pure.
--
-- A definition:
--   id          "marlin"            (unique)
--   class       "car" | "bike" | "truck" | "trailer" | "boat" | "heli"
--   name        "Marlin"            (shown to the player)
--   top, accel, brake, turn, grip   handling (units a second, radians a second)
--   mass        1 = a sedan         (bumps and rams)
--   health      hit points
--   length, width, height, radius   size
--   seats       1+                  (passengers for missions)
--   value       what Rusty pays when it is clean
--   paint       { "body", ... }     slots the respray changes
--   tune        { "engine", "brakes", "grip", "armour" }  slots the tune shop may raise (0-3 each)
--   damage      { 0.66, 0.33, 0.1 } health fractions where it looks worse (dents, smoke, fire)
--   police, special, traffic (bool) and weight (how often traffic picks it)
--   model       a model builder key for the renderer (default: the class's)
--
--   vehicles.define(def)  vehicles.get(id)  vehicles.list(class)  vehicles.validate(def) -> ok, err
--   vehicles.physics(class, fn)  vehicles.physicsFor(def) -> fn(entity, input, dt, world) -> impact
--   vehicles.traffic() -> { def, ... } weighted list for traffic

local M = {}

M.CLASSES = { car = true, bike = true, truck = true, trailer = true, boat = true, heli = true }
local REQUIRED = { "top", "accel", "brake", "turn", "grip", "health", "length", "width" }

local defs, order, physics = {}, {}, {}

function M.validate(def)
  if type(def) ~= "table" then return false, "a vehicle definition must be a table" end
  if type(def.id) ~= "string" or def.id == "" then return false, "no id" end
  if not M.CLASSES[def.class] then return false, def.id .. ": unknown class " .. tostring(def.class) end
  if type(def.name) ~= "string" then return false, def.id .. ": no name" end
  for _, k in ipairs(REQUIRED) do
    if type(def[k]) ~= "number" or def[k] <= 0 or def[k] ~= def[k] then return false, def.id .. ": " .. k .. " must be a positive number" end
  end
  if def.damage then
    for i, f in ipairs(def.damage) do
      if type(f) ~= "number" or f <= 0 or f >= 1 then return false, def.id .. ": damage stage " .. i .. " must be between 0 and 1" end
    end
  end
  return true
end

--- Add a definition (filling the defaults). A second definition with the same id is an error.
function M.define(def)
  local ok, err = M.validate(def)
  if not ok then error(err, 2) end
  if defs[def.id] then error("vehicle '" .. def.id .. "' is defined twice", 2) end
  def.mass = def.mass or 1
  def.height = def.height or 1.5
  def.radius = def.radius or math.max(def.length, def.width) / 2 * 0.9
  def.seats = def.seats or 2
  def.value = def.value or 0
  def.paint = def.paint or { "body" }
  def.tune = def.tune or { "engine", "brakes", "grip", "armour" }
  def.damage = def.damage or { 0.66, 0.33, 0.1 }
  def.weight = def.weight or (def.traffic and 1 or 0)
  defs[def.id] = def
  order[#order + 1] = def.id
  return def
end

function M.get(id) return defs[id] end

function M.list(class)
  local out = {}
  for _, id in ipairs(order) do
    if not class or defs[id].class == class then out[#out + 1] = defs[id] end
  end
  return out
end

function M.physics(class, fn)
  if not M.CLASSES[class] then error("unknown class " .. tostring(class), 2) end
  physics[class] = fn
end

function M.physicsFor(def)
  return physics[def.class]
end

--- Which damage stage (0 clean .. #damage) a health fraction is in.
function M.stage(def, fraction)
  local s = 0
  for i, f in ipairs(def.damage) do
    if fraction <= f then s = i end
  end
  return s
end

function M.traffic()
  local out = {}
  for _, id in ipairs(order) do
    local d = defs[id]
    for _ = 1, d.weight do out[#out + 1] = d end
  end
  return out
end

--- For tests: forget everything.
function M.reset()
  defs, order, physics = {}, {}, {}
end

--- Today's cars, as class "car" definitions, with today's physics.
function M.registerLegacy()
  local vehicle = require("sg.vehicle")
  local trafficSet = {}
  for _, k in ipairs(vehicle.TRAFFIC_TYPES) do trafficSet[k] = (trafficSet[k] or 0) + 1 end
  local keys = {}
  for k in pairs(vehicle.TYPES) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local t = vehicle.TYPES[k]
    if not defs[k] then
      M.define({
        id = k, class = "car", name = t.name, top = t.top, accel = t.accel, brake = t.brake, turn = t.turn, grip = t.grip,
        health = t.health, length = t.length, width = t.width, height = t.height, radius = t.radius, value = t.value,
        police = t.police, special = t.special, traffic = trafficSet[k] ~= nil, weight = trafficSet[k],
        legacy = t, model = "car",
      })
    end
  end
  if not physics.car then
    M.physics("car", function(car, input, dt, world) return vehicle.update(car, input, dt, world) end)
  end
end

return M
