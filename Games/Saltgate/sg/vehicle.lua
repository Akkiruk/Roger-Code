-- vehicle.lua
-- Saltgate's cars and how they drive. Pure: a car is a plain table, update() moves it for dt seconds under an input
-- of throttle (-1..1), steer (-1..1, positive turns right) and handbrake, on the flat; core/drive.lua puts it on the
-- streamed world (ground, walls), so the same physics serve the player, traffic and the Harbor Patrol.

local util = require("sg.util")

local M = {}

local cos, sin, abs = math.cos, math.sin, math.abs

-- speeds in units (about a metre) a second. value is what Rusty pays for a clean one.
M.TYPES = {
  pipit = { name = "Pipit", top = 24, accel = 12, brake = 26, turn = 2.8, grip = 6, health = 80, value = 90,
    length = 3.6, width = 1.8, height = 1.5, body = "orange", cabin = "black", radius = 1.7 },
  marlin = { name = "Marlin", top = 29, accel = 11, brake = 24, turn = 2.6, grip = 5, health = 100, value = 160,
    length = 4.4, width = 2.0, height = 1.5, body = "blue", cabin = "black", radius = 2.0 },
  kestrel = { name = "Kestrel Cab", top = 28, accel = 11, brake = 24, turn = 2.6, grip = 5, health = 100, value = 140,
    length = 4.4, width = 2.0, height = 1.6, body = "yellow", cabin = "black", radius = 2.0, sign = true },
  tidewater = { name = "Tidewater Van", top = 22, accel = 8, brake = 20, turn = 2.3, grip = 4.5, health = 150, value = 120,
    length = 5.0, width = 2.2, height = 2.4, body = "white", cabin = "black", radius = 2.3, van = true },
  sovereign = { name = "Gilt Sovereign", top = 42, accel = 19, brake = 30, turn = 3.0, grip = 7, health = 90, value = 900,
    length = 4.6, width = 2.0, height = 1.2, body = "yellow", cabin = "black", radius = 2.0, low = true, special = true },
  cruiser = { name = "Gull Cruiser", top = 35, accel = 15, brake = 28, turn = 2.8, grip = 6.5, health = 170, value = 0,
    length = 4.6, width = 2.0, height = 1.5, body = "white", cabin = "blue", radius = 2.0, police = true },
}

M.TRAFFIC_TYPES = { "pipit", "marlin", "marlin", "kestrel", "tidewater", "pipit" }
M.BODY_COLOURS = { "orange", "blue", "red", "lightGray", "green", "white", "purple", "cyan" }

M.CORNER_SCRUB = 9 -- speed lost a second while steering hard above half speed

local nextId = 0

--- A new car of type kind at (x, z) facing h.
function M.new(kind, x, z, h, colour)
  local spec = assert(M.TYPES[kind], "no such car " .. tostring(kind))
  nextId = nextId + 1
  return {
    id = nextId,
    kind = kind,
    spec = spec,
    colour = colour or spec.body,
    x = x, z = z, h = h or 0,
    v = 0, -- forward speed
    side = 0, -- sideways slide, decays with grip
    steer = 0,
    health = spec.health,
    wrecked = false,
    hitTimer = 0,
  }
end

--- One step of driving. Returns how hard it hit something (speed lost), 0 if nothing.
function M.update(car, input, dt)
  local spec = car.spec
  local throttle = input and input.throttle or 0
  local steerIn = input and input.steer or 0
  local handbrake = input and input.handbrake or false
  if car.wrecked then throttle, steerIn = 0, 0 end

  -- engine and brakes
  local v = car.v
  if throttle > 0 then
    if v < 0 then v = v + spec.brake * throttle * dt
    else v = v + spec.accel * throttle * (1 - v / spec.top) * dt end
  elseif throttle < 0 then
    if v > 0 then v = v + spec.brake * throttle * dt
    else v = v + spec.accel * 0.6 * throttle * (1 + v / (spec.top * 0.35)) * dt end
  else
    -- rolling: ease toward a stop
    local roll = 3 * dt
    if v > roll then v = v - roll elseif v < -roll then v = v + roll else v = 0 end
  end
  if handbrake then
    local hb = spec.brake * 0.55 * dt
    if v > hb then v = v - hb elseif v < -hb then v = v + hb else v = 0 end
  end
  v = v - v * 0.02 * dt -- air
  car.v = v

  -- steering: the wheel turns quickly, the car turns by speed (less at the very top, none standing still)
  car.steer = util.approach(car.steer, steerIn, 6 * dt)
  local speedFactor = util.clamp(abs(v) / 6, 0, 1) * (1 - 0.2 * util.clamp(abs(v) / spec.top, 0, 1))
  local turn = spec.turn * (handbrake and 1.6 or 1)
  local sign = v >= 0 and 1 or -1
  local dh = car.steer * turn * speedFactor * sign * dt
  car.h = util.wrap(car.h + dh)
  -- turning hard at speed scrubs some off, so a corner taken flat out still makes the corner
  if abs(car.steer) > 0.5 and abs(v) > spec.top * 0.5 then
    car.v = v - sign * M.CORNER_SCRUB * abs(car.steer) * dt
    v = car.v
  end

  -- slide: turning hard at speed (or on the handbrake) lets the back step out
  local slip = handbrake and 0.6 or 0.18
  car.side = car.side + dh * v * slip
  local grip = handbrake and spec.grip * 0.3 or spec.grip
  car.side = car.side - car.side * util.clamp(grip * dt, 0, 1)

  local fx, fz = cos(car.h), sin(car.h)
  local rx, rz = -fz, fx
  local nx = car.x + (fx * v + rx * car.side) * dt
  local nz = car.z + (fz * v + rz * car.side) * dt

  -- (walls and ground are core/motion.lua's, through core/drive.lua: this moves the car on the flat)
  local impact = 0
  car.x, car.z = nx, nz
  if car.hitTimer > 0 then car.hitTimer = car.hitTimer - dt end
  return impact
end

--- The car ran into a wall whose push-out direction is (hx, hz): speed into it is lost, the rest scrapes along, a
-- glancing hit turns it along the wall, and only hard hits hurt. Returns the speed into the wall (0 if moving away).
function M.hitWall(car, hx, hz)
  local v = car.v
  local fx, fz = cos(car.h), sin(car.h)
  local impact = 0
  local into = -(fx * hx + fz * hz) * v
  if into > 0 then
    impact = into
    car.v = v * (1 - util.clamp(into / (abs(v) + 0.001), 0, 1) * 0.85)
    if into > 12 then
      car.v = -car.v * 0.25
    elseif into < abs(v) * 0.75 then
      -- a glancing hit: turn along the wall instead of grinding into it
      local tx, tz = -hz, hx
      if tx * fx + tz * fz < 0 then tx, tz = -tx, -tz end
      if v < 0 then tx, tz = -tx, -tz end
      car.h = util.turnToward(car.h, math.atan2(tz, tx), 0.35)
    end
  end
  car.side = car.side * 0.3
  if impact > 8 then M.damage(car, (impact - 8) * 1.6) end
  return impact
end

function M.damage(car, amount)
  if car.wrecked or amount <= 0 then return end
  car.health = car.health - amount
  car.hitTimer = 0.4
  if car.health <= 0 then
    car.health = 0
    car.wrecked = true
    car.v = car.v * 0.3
  end
end

--- Two cars that overlap are pushed apart and trade some speed. Returns the closing speed (0 if they do not touch).
function M.bump(a, b)
  local dx, dz = b.x - a.x, b.z - a.z
  local d = math.sqrt(dx * dx + dz * dz)
  local reach = (a.spec.radius + b.spec.radius) * 0.85
  if d >= reach or d < 0.0001 then return 0 end
  local nx, nz = dx / d, dz / d
  local push = (reach - d) / 2
  a.x, a.z = a.x - nx * push, a.z - nz * push
  b.x, b.z = b.x + nx * push, b.z + nz * push
  local avx, avz = cos(a.h) * a.v, sin(a.h) * a.v
  local bvx, bvz = cos(b.h) * b.v, sin(b.h) * b.v
  local closing = (avx - bvx) * nx + (avz - bvz) * nz
  if closing > 0 then
    a.v = a.v * 0.55
    b.v = b.v * 0.55 + closing * 0.35 * (cos(b.h) * nx + sin(b.h) * nz)
    if closing > 8 then
      M.damage(a, (closing - 8) * 1.6)
      M.damage(b, (closing - 8) * 1.6)
    end
    return closing
  end
  return 0
end

--- Where the driver steps out: the left-hand side.
function M.doorPoint(car)
  local rx, rz = -sin(car.h), cos(car.h)
  local off = car.spec.width / 2 + 1.1
  return car.x - rx * off, car.z - rz * off
end

--- What Rusty pays for this car as it is.
function M.chopValue(car)
  local spec = car.spec
  if spec.police then return 0 end
  return math.floor(spec.value * (0.3 + 0.7 * car.health / spec.health) + 0.5)
end

--- km/h-ish for the speedometer.
function M.speedo(car)
  return math.floor(abs(car.v) * 3.6 + 0.5)
end

return M
