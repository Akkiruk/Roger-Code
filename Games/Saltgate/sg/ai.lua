-- ai.lua
-- Who drives the other cars. Traffic keeps to its right-hand lane from junction to junction and brakes for what is
-- ahead; the Harbor Patrol drives the roads toward you and, once it can see you, comes straight at you. Each returns a
-- driving input for vehicle.update, so every car obeys the same physics. Pure.

local util = require("sg.util")
local city = require("sg.city")

local M = {}

local cos, sin, abs = math.cos, math.sin, math.abs

M.CRUISE = 13
M.COP_CRUISE = 27

--- Start a car driving along direction d toward node (k, l).
function M.init(car, mode, k, l, d)
  car.ai = { mode = mode, k = k, l = l, d = d, stage = "approach", stuck = 0, rev = 0, los = false, losT = 0 }
  car.ai.wx, car.ai.wz = city.lanePoint(k, l, d, -(city.HALF + 1))
end

local function chooseExit(g, ai, toward)
  local exits = city.exits(ai.k, ai.l)
  local back = (ai.d + 2) % 4
  local options = {}
  for _, d in ipairs(exits) do
    if d ~= back then options[#options + 1] = d end
  end
  if #options == 0 then return back end
  if toward then
    local best, bestD = options[1], math.huge
    for _, d in ipairs(options) do
      local dir = city.DIRS[d + 1]
      local nx, nz = city.nodePos(ai.k + dir[1], ai.l + dir[2])
      local dd = util.dist2(nx, nz, toward[1], toward[2]) + g.rng() * 40
      if dd < bestD then best, bestD = d, dd end
    end
    return best
  end
  return options[g.rng(#options)]
end

--- Follow the lanes: move the waypoint along when it is reached.
local function followRoad(g, car, toward)
  local ai = car.ai
  if util.dist2(car.x, car.z, ai.wx, ai.wz) < 3.2 * 3.2 then
    if ai.stage == "approach" then
      local d2 = chooseExit(g, ai, toward)
      ai.turning = d2 ~= ai.d
      ai.d = d2
      ai.stage = "exit"
      ai.wx, ai.wz = city.lanePoint(ai.k, ai.l, d2, city.HALF + 1)
    else
      local dir = city.DIRS[ai.d + 1]
      ai.k, ai.l = ai.k + dir[1], ai.l + dir[2]
      ai.stage = "approach"
      ai.turning = false
      ai.wx, ai.wz = city.lanePoint(ai.k, ai.l, ai.d, -(city.HALF + 1))
    end
  end
end

--- How fast it may go given what is in front of it (cars, and you on foot).
local function clearAhead(g, car, want)
  local fx, fz = cos(car.h), sin(car.h)
  local limit = want
  local function consider(x, z, v)
    local rx, rz = x - car.x, z - car.z
    local along = rx * fx + rz * fz
    if along > 0 and along < 12 then
      local lateral = abs(rx * fz - rz * fx)
      if lateral < 2.6 then
        local allowed = along < 6.5 and 0 or math.max(0, v or 0)
        if allowed < limit then limit = allowed end
      end
    end
  end
  for _, other in ipairs(g.cars) do
    if other ~= car then consider(other.x, other.z, other.v) end
  end
  if not g.player.car then consider(g.player.x, g.player.z, 0) end
  return limit
end

local function steerTo(car, x, z)
  local want = util.headingTo(car.x, car.z, x, z)
  local diff = util.wrap(want - car.h)
  return util.clamp(diff * 2.5, -1, 1), diff
end

local function unstick(car, dt, wantSpeed, input)
  local ai = car.ai
  if ai.rev > 0 then
    ai.rev = ai.rev - dt
    input.throttle = -1
    input.steer = -(ai.revSteer or 1)
    return true
  end
  if wantSpeed > 3 and abs(car.v) < 0.8 then
    ai.stuck = ai.stuck + dt
    if ai.stuck > 2.2 then
      ai.stuck = 0
      ai.rev = 1.2
      ai.revSteer = input.steer >= 0 and 1 or -1
    end
  else
    ai.stuck = 0
  end
  return false
end

--- A traffic car's input for this step.
function M.traffic(g, car, dt)
  local ai = car.ai
  followRoad(g, car, nil)
  local steer, diff = steerTo(car, ai.wx, ai.wz)
  local want = M.CRUISE
  if ai.stage == "exit" and ai.turning then want = 7 end
  if abs(diff) > 0.6 then want = math.min(want, 6) end
  want = clearAhead(g, car, want)
  local input = { throttle = util.clamp((want - car.v) * 0.4, -1, 1), steer = steer }
  if want <= 0.1 and car.v < 1 then input.throttle = 0 end
  unstick(car, dt, want, input)
  return input
end

--- Can this cruiser see you? (cached a quarter second at a time)
function M.copSees(g, car, dt, sight)
  local ai = car.ai
  local p = g.player
  local d2 = util.dist2(car.x, car.z, p.x, p.z)
  if d2 > sight * sight then
    ai.los = false
    return false
  end
  ai.losT = ai.losT - dt
  if ai.losT <= 0 then
    ai.losT = 0.25
    ai.los = not city.blocked(g.city, car.x, car.z, p.x, p.z)
  end
  return ai.los
end

--- A cruiser's input for this step. heatLevel 0 sends it back to patrolling.
function M.cop(g, car, dt, heatLevel)
  local ai = car.ai
  local p = g.player
  local input
  if heatLevel <= 0 then
    followRoad(g, car, nil)
    local steer = steerTo(car, ai.wx, ai.wz)
    local want = clearAhead(g, car, M.CRUISE)
    input = { throttle = util.clamp((want - car.v) * 0.4, -1, 1), steer = steer }
    unstick(car, dt, want, input)
    return input
  end
  local pv = p.car and p.car.v or 0
  local ph = p.car and p.car.h or p.h
  local dist = util.dist(car.x, car.z, p.x, p.z)
  local wanted = 5
  if ai.los and dist < 34 then
    ai.direct = true
    local lead = util.clamp(dist / 30, 0, 0.6)
    local tx = p.x + cos(ph) * pv * lead
    local tz = p.z + sin(ph) * pv * lead
    local steer = steerTo(car, tx, tz)
    local want = car.spec.top
    if abs(pv) < 4 then want = util.clamp((dist - 4) * 1.3, 0, car.spec.top) end
    input = { throttle = util.clamp((want - car.v) * 0.5, -1, 1), steer = steer }
    if dist < 5 and abs(pv) < 4 then input.throttle = car.v > 0.5 and -1 or 0; want = 0 end
    wanted = want
  else
    if ai.direct then
      -- lost sight: back onto the road graph from wherever it is
      ai.direct = false
      local k, l = city.nearestNode(car.x, car.z)
      local d = math.floor(((car.h + math.pi / 4) % util.TAU) / (math.pi / 2)) % 4
      ai.k, ai.l, ai.d, ai.stage = k, l, d, "approach"
      ai.wx, ai.wz = city.nodePos(k, l)
    end
    followRoad(g, car, { p.x, p.z })
    local steer, diff = steerTo(car, ai.wx, ai.wz)
    local want = M.COP_CRUISE
    if ai.stage == "exit" and ai.turning then want = 11 end
    if abs(diff) > 0.7 then want = math.min(want, 9) end
    input = { throttle = util.clamp((want - car.v) * 0.5, -1, 1), steer = steer }
  end
  unstick(car, dt, wanted, input)
  return input
end

return M
