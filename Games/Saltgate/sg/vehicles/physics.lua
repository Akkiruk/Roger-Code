-- vehicles/physics.lua
-- How each class of vehicle moves over the streamed 3D world (core/motion.lua keeps the height, tilt, jumps and
-- falls; this decides speed and heading):
--   car, truck   today's driving model with each car's own slip, stability, hill-climbing and landing toughness,
--                heavier cars losing less speed and the cab pulling its trailer's weight
--   bike         leans into corners (a visual lean, limited by speed so it never flips); a hard hit throws the rider
--   trailer      follows its cab's hitch like a rod: a hard turn swings it wide, reversing folds it, and a fold past
--                75 degrees jams the cab (a jackknife) instead of going further
--   boat         floats on the water, bobs, planes with its bow up, slides in a turn, and stops at the shore
--
--   physics.step(car, input, dt, world, opts) -> { impact, airborne, landed, landImpact, water, surface }
--     (the same shape as core/drive.lua's step; the plugin routes drive.step here for any spec with a class)
--   physics.trailer(tr, cab, dt, world)      physics.bump(a, b) -> closing speed (0 if apart)
--   physics.waterOK(world, x, z) -> level or nil     the water a boat may be on: deep enough and in a water polygon
-- Pure: the world is anything with groundAt, collide and waterAt (core/stream.lua).

local util = require("sg.util")
local motion = require("sg.core.motion")
local vehicle = require("sg.vehicle")

local M = {}

local cos, sin, abs, min, max, sqrt = math.cos, math.sin, math.abs, math.min, math.max, math.sqrt
local atan2 = math.atan2 or math.atan
local clamp, approach, wrap = util.clamp, util.approach, util.wrap

M.LAND_HURT = 14 -- landing harder than this (vertical units a second) dents the car
M.GRAVITY_ALONG = 5.4 -- how hard a slope pulls a car along it, per unit of sine
M.THROW_SPEED = 11 -- hitting something this hard on a bike throws the rider
M.JACKKNIFE = 1.3 -- radians between cab and trailer before it jams
M.DEPTH = 0.45 -- how deep the water must be for a boat

local function result(r)
  return { impact = 0, airborne = r.airborne, landed = r.landed, landImpact = r.impact, water = r.water, surface = r.surface }
end

--- Move over the ground to (nx, nz) with the shared wall and landing rules.
local function settle(car, world, nx, nz, dt, spec, opts)
  local r = motion.move(car, world, nx, nz, dt, { radius = spec.radius * 0.8, speed = car.v, length = spec.length,
    width = spec.width, tilt = not (opts and opts.tilt == false) })
  local out = result(r)
  if r.hit then out.impact = vehicle.hitWall(car, r.nx or 0, r.nz or 0) end
  if r.landed and r.impact > M.LAND_HURT then vehicle.damage(car, (r.impact - M.LAND_HURT) * 2 * (spec.rugged or 1)) end
  return out
end

--- Throttle and brakes: the same model as today's cars (sg/vehicle.lua), with a load factor on pull.
local function engine(car, spec, throttle, handbrake, dt, load)
  local v = car.v
  local accel, top = spec.accel * load, spec.top * (0.6 + 0.4 * load)
  if throttle > 0 then
    if v < 0 then v = v + spec.brake * throttle * dt
    else v = v + accel * throttle * max(0, 1 - v / top) * dt end
  elseif throttle < 0 then
    if v > 0 then v = v + spec.brake * throttle * dt
    else v = v + accel * 0.6 * throttle * (1 + v / (top * 0.35)) * dt end
  else
    local roll = 3 * dt
    if v > roll then v = v - roll elseif v < -roll then v = v + roll else v = 0 end
  end
  if handbrake then
    local hb = spec.brake * 0.55 * dt
    if v > hb then v = v - hb elseif v < -hb then v = v + hb else v = 0 end
  end
  return v - v * 0.02 * dt
end

-- ---------------------------------------------------------------- cars and trucks

function M.car(car, input, dt, world, opts)
  input = input or {}
  local spec = car.spec
  local air = car.airborne
  local throttle, steerIn, hb = input.throttle or 0, input.steer or 0, input.handbrake or false
  if air then throttle, hb, steerIn = 0, false, steerIn * 0.3 end
  if car.wrecked then throttle, steerIn, hb = 0, 0, false end
  local load = car.trailer and 0.8 or 1
  local v = engine(car, spec, throttle, hb, dt, load)
  -- a slope pulls along it: up slows (less for a car that climbs well), down speeds up
  if not air then
    v = v - M.GRAVITY_ALONG * sin(car.pitch or 0) / (spec.climb or 1) * dt
  end
  -- a jackknifed trailer holds the cab back
  if car.jammed then v = v * (1 - 2.5 * dt) end
  car.v = v

  car.steer = approach(car.steer or 0, steerIn, 6 * dt)
  local topFrac = clamp(abs(v) / spec.top, 0, 1)
  local speedFactor = clamp(abs(v) / 6, 0, 1) * (1 - (0.2 + (spec.stab or 0)) * topFrac)
  local sign = v >= 0 and 1 or -1
  local turn = spec.turn * (hb and 1.6 or 1) * (car.trailer and 0.85 or 1)
  local dh = car.steer * turn * speedFactor * sign * dt
  car.h = wrap(car.h + dh)
  if abs(car.steer) > 0.5 and abs(v) > spec.top * 0.5 then
    car.v = v - sign * vehicle.CORNER_SCRUB * abs(car.steer) * dt / max(0.7, spec.mass or 1) ^ 0.5
    v = car.v
  end
  local slip = hb and 0.6 or (spec.slip or 0.18)
  car.side = (car.side or 0) + dh * v * slip
  local grip = hb and spec.grip * 0.3 or spec.grip
  car.side = car.side - car.side * clamp(grip * dt, 0, 1)

  local fx, fz = cos(car.h), sin(car.h)
  local nx = car.x + (fx * v - fz * car.side) * dt
  local nz = car.z + (fz * v + fx * car.side) * dt
  local out = settle(car, world, nx, nz, dt, spec, opts)
  if car.hitTimer and car.hitTimer > 0 then car.hitTimer = car.hitTimer - dt end
  if out.water then
    -- driven into the sea: it sinks (the plugin shows it and the wreck stays)
    car.v = car.v * (1 - 1.5 * dt)
    car.sunk = (car.sunk or 0) + dt
    vehicle.damage(car, 28 * dt)
  end
  return out
end

-- ---------------------------------------------------------------- bikes

function M.bike(car, input, dt, world, opts)
  input = input or {}
  local spec = car.spec
  local air = car.airborne
  local throttle, steerIn, hb = input.throttle or 0, input.steer or 0, input.handbrake or false
  if air then throttle, hb, steerIn = 0, false, steerIn * 0.2 end
  if (car.fall or 0) > 0 then
    -- on its side after throwing the rider: it slides to a stop and stays down for a moment
    car.fall = car.fall - dt
    throttle, steerIn, hb = 0, 0, true
  end
  if car.wrecked then throttle, steerIn, hb = 0, 0, false end
  local v = engine(car, spec, throttle, hb, dt, 1)
  if not air then v = v - M.GRAVITY_ALONG * sin(car.pitch or 0) / (spec.climb or 1) * dt end
  car.v = v
  car.steer = approach(car.steer or 0, steerIn, 7 * dt)
  local topFrac = clamp(abs(v) / spec.top, 0, 1)
  -- the faster, the less it can lean and turn: no flipping it over by steering hard at the top
  local leanMax = spec.lean * (1 - 0.55 * topFrac)
  local sign = v >= 0 and 1 or -1
  local speedFactor = clamp(abs(v) / 5, 0, 1) * (1 - 0.5 * topFrac)
  local dh = car.steer * spec.turn * speedFactor * sign * dt
  car.h = wrap(car.h + dh)
  car.lean = approach(car.lean or 0, car.steer * leanMax * clamp(abs(v) / 4, 0, 1), 3.5 * dt)
  car.side = (car.side or 0) + dh * v * (spec.slip or 0.07)
  car.side = car.side - car.side * clamp(spec.grip * dt, 0, 1)
  local fx, fz = cos(car.h), sin(car.h)
  local nx = car.x + (fx * v - fz * car.side) * dt
  local nz = car.z + (fz * v + fx * car.side) * dt
  local before = car.v
  local out = settle(car, world, nx, nz, dt, spec, opts)
  if out.impact > M.THROW_SPEED and (car.fall or 0) <= 0 then
    car.fall = 1.8
    car.thrown = out.impact -- the plugin knocks the rider down
    car.v = before * 0.1
  end
  if car.fall and car.fall > 0 then car.lean = (car.lean or 0) + (1.2 - (car.lean or 0)) * min(1, dt * 6) end
  if not car.airborne then car.roll = (car.roll or 0) - (car.lean or 0) end
  if out.water then car.v = car.v * (1 - 1.5 * dt) vehicle.damage(car, 28 * dt) end
  return out
end

-- ---------------------------------------------------------------- trailers

--- Pull a trailer (tr, a table with spec, x, z, h, rx, rz) behind its cab for dt seconds.
function M.trailer(tr, cab, dt, world)
  local cs, ts = cab.spec, tr.spec
  local back = cs.hitch or cs.length * 0.45
  local hx, hz = cab.x - cos(cab.h) * back, cab.z - sin(cab.h) * back
  local axle = ts.length / 2 - 1.0
  local rod = (ts.hitch or ts.length * 0.45) + axle
  if not tr.rx then
    tr.rx, tr.rz = hx - cos(cab.h) * rod, hz - sin(cab.h) * rod
    tr.h = cab.h
  end
  local dx, dz = hx - tr.rx, hz - tr.rz
  local d = sqrt(dx * dx + dz * dz)
  local h = d > 1e-3 and atan2(dz, dx) or cab.h
  local rel = wrap(h - cab.h)
  cab.jammed = false
  if abs(rel) > M.JACKKNIFE then
    h = wrap(cab.h + (rel > 0 and 1 or -1) * M.JACKKNIFE)
    cab.jammed = true
  end
  tr.h = h
  tr.fold = rel
  tr.rx, tr.rz = hx - cos(h) * rod, hz - sin(h) * rod
  local cx, cz = tr.rx + cos(h) * axle, tr.rz + sin(h) * axle
  tr.v = cab.v
  if world then
    tr.x, tr.z = tr.x or cx, tr.z or cz
    local r = motion.move(tr, world, cx, cz, dt, { radius = 1.4, speed = cab.v, length = ts.length, width = ts.width, tilt = false })
    if r.hit then
      -- the rear swung into something: the trailer is held where it is and the rig is slowed
      cab.v = cab.v * (1 - 3 * dt)
      tr.rx, tr.rz = tr.x - cos(h) * axle, tr.z - sin(h) * axle
    end
  else
    tr.x, tr.z = cx, cz
  end
  tr.y = tr.y or cab.y
  return tr
end

--- A new trailer of def (a trailer definition), hitched behind cab.
function M.hitch(def, cab, world)
  local tr = { kind = def.id, spec = def, colour = def.body, health = def.health, x = cab.x, z = cab.z, h = cab.h, v = 0,
    isTrailer = true, cab = cab }
  M.trailer(tr, cab, 0.05, nil)
  if world then
    local gy = world:groundAt(tr.x, tr.z, cab.y)
    tr.y = gy or cab.y
  else
    tr.y = cab.y
  end
  cab.trailer = tr
  return tr
end

-- ---------------------------------------------------------------- boats

--- The level of the water at (x, z) if a boat may float there (a water polygon, with the bottom well below it).
function M.waterOK(world, x, z)
  local lv = world:waterAt(x, z)
  if lv == nil then return nil end
  local gy = world:groundAt(x, z, lv - M.DEPTH)
  if gy ~= nil and gy > lv - M.DEPTH then return nil end
  return lv
end

local function boatOK(world, spec, x, z, h)
  local lv = M.waterOK(world, x, z)
  if not lv then return nil end
  local hl = spec.length / 2
  if not M.waterOK(world, x + cos(h) * hl, z + sin(h) * hl) then return nil end
  if not M.waterOK(world, x - cos(h) * hl, z - sin(h) * hl) then return nil end
  return lv
end

function M.boat(car, input, dt, world, opts)
  input = input or {}
  local spec = car.spec
  local throttle, steerIn, hb = input.throttle or 0, input.steer or 0, input.handbrake or false
  if car.wrecked then throttle, steerIn = 0, 0 end
  car.clock = (car.clock or 0) + dt
  local v = car.v
  if throttle > 0 then
    v = v + spec.accel * throttle * max(0, 1 - max(v, 0) / spec.top) * dt
  elseif throttle < 0 then
    if v > 0 then v = v + spec.brake * throttle * dt else v = v + spec.accel * 0.4 * throttle * (1 + v / (spec.top * 0.3)) * dt end
  end
  -- water drags: under power the hull just reaches its top speed, coasting slows a lot, the brake slows more
  local drag = 0.06 + (throttle == 0 and (0.25 + 0.012 * abs(v)) or 0) + (hb and 0.9 or 0)
  v = v - v * min(1, drag * dt)
  if abs(v) < 0.03 and throttle == 0 then v = 0 end
  car.v = v
  car.steer = approach(car.steer or 0, steerIn, 3 * dt)
  local authority = clamp(abs(v) / 3, 0, 1)
  if throttle ~= 0 then authority = max(authority, 0.45) end
  local sign = v >= -0.5 and 1 or -1
  local dh = car.steer * spec.turn * authority * sign * dt
  car.h = wrap(car.h + dh)
  car.side = (car.side or 0) + dh * v * 0.6
  car.side = car.side - car.side * clamp(spec.grip * dt, 0, 1)
  local fx, fz = cos(car.h), sin(car.h)
  local ox, oz = car.x, car.z
  local nx = ox + (fx * v - fz * car.side) * dt
  local nz = oz + (fz * v + fx * car.side) * dt
  local out = { impact = 0, airborne = false, landed = false, landImpact = 0, water = nil, surface = "water" }
  local level = boatOK(world, spec, nx, nz, car.h)
  if not level then
    -- the shore: try sliding along it, else stop and bounce back a little
    level = boatOK(world, spec, nx, oz, car.h)
    if level then nz = oz else
      level = boatOK(world, spec, ox, nz, car.h)
      if level then nx = ox else nx, nz = ox, oz end
    end
    local into = abs(car.v)
    out.impact = into
    car.v = car.v * -0.25
    car.side = car.side * 0.3
    if into > 7 then vehicle.damage(car, (into - 7) * 1.2) end
  end
  car.x, car.z = nx, nz
  -- hulls and piers: the world's walls at water height
  local lv = level or boatOK(world, spec, ox, oz, car.h) or 0
  local cx, cz, hit, hnx, hnz = world:collide(car.x, car.z, spec.radius * 0.8, lv + 0.5)
  if hit then
    car.x, car.z = cx, cz
    out.impact = max(out.impact, vehicle.hitWall(car, hnx, hnz))
  end
  local bob = (spec.bob or 0.12)
  local wave = sin(car.clock * 2.1 + car.x * 0.21) * bob + sin(car.clock * 3.3 + car.z * 0.17) * bob * 0.5
  car.y = lv + wave - 0.15
  car.vy, car.airborne, car.groundVy = 0, false, 0
  local planing = clamp(abs(car.v) / spec.top, 0, 1)
  car.pitch = planing * 0.14 + sin(car.clock * 2.1 + car.x * 0.21) * bob * 0.3
  car.roll = -car.steer * planing * 0.25 + sin(car.clock * 1.6) * bob * 0.2
  if car.wrecked then car.pitch = car.pitch + 0.25 end -- a wreck sits low by the bow
  return out
end

-- ---------------------------------------------------------------- the class switch

local byClass = { car = M.car, truck = M.car, bike = M.bike, boat = M.boat }

--- True when this physics drives the car (a spec with a class that has physics here).
function M.handles(car)
  local class = car.spec and car.spec.class
  return class ~= nil and byClass[class] ~= nil
end

function M.step(car, input, dt, world, opts)
  return byClass[car.spec.class](car, input, dt, world, opts)
end

-- ---------------------------------------------------------------- bumping, with weight

--- Two vehicles that overlap are pushed apart in proportion to their weight and trade speed: a van shoves a scooter
-- aside, and the scooter takes the damage. Returns the closing speed (0 if apart).
function M.bump(a, b)
  local dx, dz = b.x - a.x, b.z - a.z
  local d = sqrt(dx * dx + dz * dz)
  local reach = (a.spec.radius + b.spec.radius) * 0.85
  if d >= reach or d < 0.0001 then return 0 end
  local ma, mb = a.spec.mass or 1, b.spec.mass or 1
  local tot = ma + mb
  local nx, nz = dx / d, dz / d
  local push = reach - d
  a.x, a.z = a.x - nx * push * mb / tot, a.z - nz * push * mb / tot
  b.x, b.z = b.x + nx * push * ma / tot, b.z + nz * push * ma / tot
  local avx, avz = cos(a.h) * a.v, sin(a.h) * a.v
  local bvx, bvz = cos(b.h) * b.v, sin(b.h) * b.v
  local closing = (avx - bvx) * nx + (avz - bvz) * nz
  if closing > 0 then
    a.v = a.v * (1 - 0.9 * mb / tot)
    b.v = b.v * (1 - 0.9 * ma / tot) + closing * 0.7 * ma / tot * (cos(b.h) * nx + sin(b.h) * nz)
    if closing > 8 then
      vehicle.damage(a, (closing - 8) * 3.2 * mb / tot)
      vehicle.damage(b, (closing - 8) * 3.2 * ma / tot)
    end
    -- a bike that is rammed hard loses its rider
    if closing > M.THROW_SPEED then
      if a.spec.class == "bike" and (a.fall or 0) <= 0 then a.fall, a.thrown = 1.8, closing end
      if b.spec.class == "bike" and (b.fall or 0) <= 0 then b.fall, b.thrown = 1.8, closing end
    end
    return closing
  end
  return 0
end

return M
