-- core/drive.lua
-- A car over the streamed 3D world: today's handling (sg/vehicle.lua) for speed and steering, core/motion.lua for
-- ground height, slopes, jumps and falls, the shared wall response for hits. Pure.
--
--   local r = drive.step(car, input, dt, world)
--   r.impact (wall), r.landed, r.landImpact, r.airborne, r.water, r.surface
-- The car table is a sg/vehicle.lua car with y, vy, airborne, pitch, roll added by motion.

local vehicle = require("sg.vehicle")
local motion = require("sg.core.motion")

local M = {}

M.LAND_HURT = 14 -- landing harder than this (vertical units a second) dents the car

function M.step(car, input, dt, world, opts)
  input = input or {}
  if car.airborne then
    -- in the air the wheels do nothing; a little steering still turns the body
    input = { throttle = 0, steer = (input.steer or 0) * 0.3, handbrake = false }
  end
  local ox, oz = car.x, car.z
  vehicle.update(car, input, dt) -- speed and heading on the flat
  local nx, nz = car.x, car.z
  car.x, car.z = ox, oz
  local spec = car.spec
  local r = motion.move(car, world, nx, nz, dt, { radius = spec.radius * 0.8, speed = car.v, length = spec.length,
    width = spec.width, tilt = not (opts and opts.tilt == false) })
  local out = { impact = 0, airborne = r.airborne, landed = r.landed, landImpact = r.impact, water = r.water,
    surface = r.surface }
  if r.hit then out.impact = vehicle.hitWall(car, r.nx or 0, r.nz or 0) end
  if r.landed and r.impact > M.LAND_HURT then vehicle.damage(car, (r.impact - M.LAND_HURT) * 2) end
  return out
end

return M
