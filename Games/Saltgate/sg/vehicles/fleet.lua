-- vehicles/fleet.lua
-- Making vehicles and keeping them looking right: spawn any vehicle by id (with its paint, tune and trailer), keep
-- each car's colour string in step with its damage stage, and put the rider down when a bike throws them. The shops
-- and garage (stream E) and the traffic (stream C) use ctx.fleet.
--
--   local fleet = fleet.new(ctx)
--   fleet:spawn(kind, x, z, h, { paint = "red", stripe = "white", tune = { engine = 2 }, trailer = "t_flat",
--                                detached = true (do not add to ctx.cars) }) -> car | nil, reason
--   fleet:sync(car)          bring car.stage and car.colour up to date (done for every car by update)
--   fleet:update(dt)         once a frame: damage looks, trailers pulled, thrown riders
--   fleet:stage(car) -> 0..3 (a wreck is 3)
--   fleet:snapshot(car) -> garage data     fleet:build(data, x, z, h) -> car      fleet:hitch(cab, trailerId) -> trailer

local vehicleLib = require("sg.vehicle")
local custom = require("sg.vehicles.custom")
local physics = require("sg.vehicles.physics")

local M = {}
local F = {}
F.__index = F

function M.new(ctx)
  return setmetatable({ ctx = ctx, clock = 0 }, F)
end

--- Damage stage 0 (clean) .. 3 (burning), by the health left against the definition's thresholds. A wreck is 3.
function F:stage(car)
  if car.wrecked then return 3 end
  local def = self.ctx.vehicles.get(car.kind) or car.spec
  local frac = car.health / math.max(1, car.spec.health)
  return self.ctx.vehicles.stage(def, frac)
end

function F:sync(car)
  local stage = self:stage(car)
  -- somebody else (a shop, a mission) may have set the colour directly: take that as the new paint
  if car.colour ~= car.composed then
    local body, stripe = custom.parse(car.colour)
    car.paint = { body = body, stripe = stripe }
  end
  car.paint = car.paint or { body = car.spec.body or "red" }
  if stage ~= car.stage or car.colour ~= car.composed then
    car.stage = stage
    car.composed = custom.compose(car.paint, stage)
    car.colour = car.composed
  end
end

function F:hitch(cab, trailerId)
  local def = self.ctx.vehicles.get(trailerId or cab.spec.trailer)
  if not def or def.class ~= "trailer" then return nil end
  local tr = physics.hitch(def, cab, self.ctx.stream)
  tr.paint = { body = def.body, stripe = def.stripe }
  tr.colour = custom.compose(tr.paint, 0)
  return tr
end

function F:spawn(kind, x, z, h, opts)
  opts = opts or {}
  local ctx = self.ctx
  local def = ctx.vehicles.get(kind)
  if not def then return nil, "no such vehicle " .. tostring(kind) end
  if def.class == "trailer" or def.class == "heli" then return nil, def.class .. "s are not driven" end
  local car = vehicleLib.new(kind, x, z, h or 0, opts.paint or def.body)
  if def.class == "boat" then
    local level = physics.waterOK(ctx.stream, x, z)
    if not level then return nil, "no water there" end
    car.y = level
  else
    car.y = ctx.stream:groundAt(x, z, opts.y) or 0
  end
  car.vy, car.pitch, car.roll = 0, 0, 0
  car.paint = { body = opts.paint or def.body, stripe = opts.stripe or def.stripe }
  if opts.tune then custom.apply(car, { tune = opts.tune }) end
  car.colour = custom.compose(car.paint, 0)
  car.composed = car.colour
  car.stage = 0
  if def.class == "truck" and (opts.trailer or def.trailer) and opts.trailer ~= false then
    self:hitch(car, opts.trailer or def.trailer)
  end
  if not opts.detached then ctx.cars[#ctx.cars + 1] = car end
  return car
end

function F:snapshot(car) return custom.snapshot(car) end

--- A car built again from garage data (see custom.snapshot).
function F:build(data, x, z, h)
  local car, why = self:spawn(data.kind, x, z, h, { paint = data.paint and data.paint.body, stripe = data.paint and data.paint.stripe,
    tune = data.tune, detached = true })
  if not car then return nil, why end
  if data.health then car.health = car.spec.health * math.max(0.05, math.min(1, data.health)) end
  self:sync(car)
  return car
end

--- A bike threw its rider: if it is the player's, they are put on the ground beside it, knocked down.
local function thrownRider(self, car)
  local ctx = self.ctx
  car.thrown = nil
  local p = ctx.player
  if p and p.car == car then
    local rx, rz = -math.sin(car.h), math.cos(car.h)
    p.car = nil
    p.x, p.z, p.y, p.h, p.v = car.x + rx * 1.4, car.z + rz * 1.4, car.y, car.h, 0
    if ctx.combat then ctx.combat:knockPlayer("ko") end
  end
end

function F:update(dt)
  local ctx = self.ctx
  self.clock = self.clock + dt
  for _, car in ipairs(ctx.cars) do
    self:sync(car)
    if car.thrown then thrownRider(self, car) end
    if car.trailer then physics.trailer(car.trailer, car, dt, ctx.stream) end
  end
end

return M
