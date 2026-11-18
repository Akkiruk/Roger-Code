-- ai/fleet.lua
-- Every vehicle stream C owns (traffic, patrol cruisers, roadblock cars) lives here as an entity in the world and in one
-- of two modes. Near the player (inside PROMOTE) it is "phys": it is in ctx.cars, the core's physics loop drives it
-- (hills, bumps, walls) with the input its brain gives. Further out it is "rail": it is not in ctx.cars, costs no
-- physics, and moves along its edge by lane.rail (every frame out to 125 units, twice a second beyond); the scene
-- layer draws rail cars that are in sight. The core steps ctx.cars with follow.input(car.follow, car, dt), so a fleet
-- car carries a stub follow table and follow.input is told, once, to ask the car's brain when it sees the stub.
--
--   fleet.install(ctx)                  patch follow.input (once) and register the scene layer
--   fleet.add(ctx, car, opts)           opts: tags {..}, brain(ctx, car, dt) -> input, rail(ctx, car, dt), parked
--   fleet.remove(ctx, car)
--   fleet.update(ctx, dt)               promote and demote by distance, keep the entity grid right
--   fleet.count(ctx [, tag])

local follow = require("sg.core.follow")
local scene = require("sg.ai.scene")

local M = {}

M.PROMOTE, M.DEMOTE = 50, 62
M.SHOWN = 130
M.FAR = 125

local function removeFrom(list, x)
  for i = #list, 1, -1 do
    if list[i] == x then table.remove(list, i) return true end
  end
  return false
end

function M.install(ctx)
  if not follow._saltgateC then
    follow._saltgateC = true
    local orig = follow.input
    follow.input = function(f, car, dt)
      if f and f.fleet then return f.fleet(car, dt) end
      return orig(f, car, dt)
    end
  end
  if ctx.fleetInstalled then return end
  ctx.fleetInstalled = true
  scene.layer(ctx, "fleet", function(c, view, list, cam)
    local r = view.r
    local models = require("sg.models")
    local fx, fz = math.cos(cam.yaw), math.sin(cam.yaw)
    local maxD2 = M.SHOWN * M.SHOWN
    for _, car in ipairs(c.world:each("fleet")) do
      if car.mode == "rail" then
        local dx, dz = car.x - cam.x, car.z - cam.z
        if dx * dx + dz * dz < maxD2 and (dx * fx + dz * fz) > -8 then
          local spec, colour, wrecked = car.spec, car.colour, car.wrecked
          local key = "car:" .. car.kind .. ":" .. colour .. (wrecked and ":w" or "")
          r:place(list, r:variant(key, car.h, function() return models.car(spec, colour, wrecked) end), car.x, car.y or 0, car.z)
        end
      end
    end
  end)
end

function M.add(ctx, car, opts)
  opts = opts or {}
  car.id = nil
  car.tags = { vehicle = true, fleet = true }
  for k in pairs(opts.tags or {}) do car.tags[k] = true end
  car.brain, car.railFn, car.parked = opts.brain, opts.rail, opts.parked
  car.fleet = true
  car.mode = "rail"
  car.railT = 0
  car.follow = { fleet = function(c, dt)
    if c.parked or not c.brain then return { throttle = 0, steer = 0, handbrake = true } end
    return c.brain(ctx, c, dt)
  end }
  ctx.world:add(car)
  return car
end

function M.remove(ctx, car)
  removeFrom(ctx.cars, car)
  ctx.world:remove(car)
  car.mode = "gone"
end

function M.count(ctx, tag)
  return ctx.world:count(tag or "fleet")
end

function M.update(ctx, dt)
  local p = ctx.player
  local px, pz = p.x, p.z
  local promote, demote = M.PROMOTE ^ 2, M.DEMOTE ^ 2
  local far2 = M.FAR ^ 2
  for _, car in ipairs(ctx.world:each("fleet")) do
    local dx, dz = car.x - px, car.z - pz
    local d2 = dx * dx + dz * dz
    if car.mode == "rail" then
      if d2 < promote and not car.parked_static_far then
        car.mode = "phys"
        car.pitch, car.roll, car.vy, car.airborne = 0, 0, 0, false
        ctx.cars[#ctx.cars + 1] = car
      elseif car.railFn then
        if d2 < far2 then
          car.railFn(ctx, car, dt)
        else
          car.railT = car.railT + dt
          if car.railT >= 0.5 then
            car.railFn(ctx, car, car.railT)
            car.railT = 0
          end
        end
      end
    elseif car.mode == "phys" and d2 > demote then
      removeFrom(ctx.cars, car)
      car.mode = "rail"
      car.speedCarry = car.v
    end
    ctx.world:move(car, car.x, car.z)
  end
end

return M
