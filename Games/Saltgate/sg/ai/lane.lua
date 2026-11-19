-- ai/lane.lua
-- A driver on the road graph. It owns which edge it is on, how far along, which way, and the route it has been given; it
-- keeps to its lane on the curve (a lane is an offset from the edge's centre line), looks ahead along the polyline
-- (onto the next edge when the end is near), slows for bends, for what is in front, for red lights and for cross
-- traffic, gives way at junctions and roundabouts, overtakes a crawler when the oncoming lane is clear and gets itself
-- out of a jam. Because it follows the edge it is on and not the nearest road, a car on a bridge stays on the bridge and
-- the road under it is another edge entirely. Pure: the world comes in through a context table.
--
--   local d = lane.attach(roads, x, z, h, rng [, kinds])       -- nil when no road is near
--   local input = lane.step(d, car, dt, env)                   -- { throttle, steer, handbrake }
--   lane.rail(d, car, dt, env, speed)                          -- no physics: move along the edge, set the car's pose
--   d.route = { edge, ... }                                    -- optional: take these edges at the next junctions
--   d.lane = false                                             -- (cops) drive the centre line
--
-- env: { roads, world (entity world, for near()), player (a car or nil), time (seconds), peds (bool) }.
-- Anything with a .drv is another driver (cross traffic and roundabouts look at its edge).

local geom = require("sg.core.geom")
local signals = require("sg.ai.signals")
local util = require("sg.util")

local M = {}

local sqrt, abs, cos, sin, min, max = math.sqrt, math.abs, math.cos, math.sin, math.min, math.max
local atan2 = math.atan2 or math.atan

M.LOOK = 6
M.KNOT = 3 -- jams in a row (backing out, blocked again) before a car slips through the cars it is wedged among
M.GHOST_SECONDS = 2.5
M.SKIP = { path = true, rail = true }
M.DRIVABLE = { road = true, avenue = true, alley = true, highway = true }

local n_ = 0

-- distance along the edge of the nearest point to (x, z), and how far off the line it is
local function project(e, x, z)
  local d, _, seg, t = geom.polylineNearest(e.pts, x, z)
  local c = e._cum
  if not c then
    c = { 0 }
    local pts = e.pts
    for i = 1, #pts - 3, 3 do
      local dx, dz = pts[i + 3] - pts[i], pts[i + 5] - pts[i + 2]
      c[#c + 1] = c[#c] + sqrt(dx * dx + dz * dz)
    end
    e._cum = c
  end
  local len = c[seg + 1] - c[seg]
  return c[seg] + len * t, d
end
M.project = project

local function laneOffset(e)
  if e.lanes == 1 then return 0 end
  return min(e.width / 4, 2.6)
end
M.laneOffset = laneOffset

function M.attach(roads, x, z, h, rng, kinds)
  local e, s, d, _, _, _, tx, tz = roads:nearest(x, z, 30, kinds or M.DRIVABLE)
  if not e then return nil end
  local dir = (tx * cos(h) + tz * sin(h)) >= 0 and 1 or -1
  if e.lanes == 1 then dir = 1 end
  n_ = n_ + 1
  local _ = d
  return { roads = roads, edge = e, s = s, dir = dir, rng = rng or math.random, speedMul = 0.85 + 0.15 * (rng or math.random)(),
    wait = 0, stuck = 0, rev = 0, lat = 0, latWant = 0, lane = true, over = 0, id = n_ }
end

--- The next edge from the end of the one it is on. The route first, else a random exit that is not a turn back.
function M.choose(d)
  local e = d.edge
  local at = d.dir == 1 and e.b or e.a
  local route = d.route
  while route and route[1] do
    local r = route[1]
    if (r.a == at or r.b == at) and (r.lanes ~= 1 or r.a == at) and d.roads:edge(r.id) == r then
      table.remove(route, 1)
      return r, at
    end
    -- off the route (a replan, a loaded chunk changed): drop it
    d.route = nil
    break
  end
  local exits = d.roads:exits(at, e)
  local pool, w = {}, 0
  for i, x in ipairs(exits) do
    local ok = not M.SKIP[x.kind]
    if ok and i == #exits and x == e and #exits > 1 then ok = false end -- the way back is last
    if ok then
      local wt = (x.kind == e.kind and 2 or 1)
      pool[#pool + 1] = { x, wt }
      w = w + wt
    end
  end
  if #pool == 0 then
    -- a dead end: turn round
    return e, at
  end
  local r = d.rng() * w
  for _, p in ipairs(pool) do
    r = r - p[2]
    if r <= 0 then return p[1], at end
  end
  return pool[#pool][1], at
end

local function enter(d, nxt, at)
  d.edge = nxt
  if nxt.a == at and (nxt.b ~= at or d.dir == 1) then
    d.dir, d.s = 1, 0
  else
    d.dir, d.s = -1, nxt.length
  end
  if nxt.lanes == 1 then d.dir, d.s = 1, 0 end
  d.nxt, d.nxtAt = nil, nil
end

--- Where the driver's next waypoint is: look units ahead in its lane, across the end of the edge if need be.
local function target(d, look)
  local e, roads = d.edge, d.roads
  local side = d.lane and (d.dir * (laneOffset(e) - d.lat)) or 0
  local st = d.s + d.dir * look
  if st >= 0 and st <= e.length then
    local x, _, z = roads:pointAt(e, st, side)
    return x, z
  end
  local nxt = d.nxt
  if not nxt then return roads:pointAt(e, max(0, min(e.length, st)), side) end
  local rem = d.dir == 1 and (st - e.length) or (-st)
  local at = d.nxtAt
  local ns, ndir
  if nxt.a == at or nxt.lanes == 1 then ns, ndir = min(rem, nxt.length), 1 else ns, ndir = max(0, nxt.length - rem), -1 end
  local nside = d.lane and (ndir * laneOffset(nxt)) or 0
  local x, _, z = roads:pointAt(nxt, ns, nside)
  return x, z
end

--- The speed a bend allows: look at how much the road turns over the next stretch.
local function bendSpeed(d, base, v)
  local e = d.edge
  local ahead = 8 + v * 0.7
  local _, y0, _, dx0, dz0 = geom.polylineAt(e.pts, d.s)
  local s2 = max(0, min(e.length, d.s + d.dir * ahead))
  local _, y1, _, dx1, dz1 = geom.polylineAt(e.pts, s2)
  local turn = abs(util.wrap(atan2(dz1, dx1) - atan2(dz0, dx0)))
  local want = base * (1 - util.clamp(turn / 1.1, 0, 0.62))
  -- a steep way down: slow enough that the car stays on it instead of leaving the ground at every step
  local sl = max(0, y0 - y1) / max(abs(s2 - d.s), 1)
  if sl > 0.35 then want = min(want, max(4, 6 / sl)) end
  return want
end

--- The slowest speed that any vehicle or person in front allows. Others: entities from env.world.
local function leader(d, car, env, fx, fz, reach)
  local limit, who = 1e9, nil
  local spec = car.spec
  local function consider(o, isPed)
    local dx, dz = o.x - car.x, o.z - car.z
    local along = dx * fx + dz * fz
    if along > 0.5 and along < reach then
      local lateral = abs(dx * fz - dz * fx)
      local ospec = o.spec
      local ow = ospec and ospec.width or 0.8
      local ol = ospec and ospec.length or 0.8
      if lateral < (spec.width + ow) / 2 + 0.55 and abs((o.y or car.y or 0) - (car.y or 0)) < 2.5 then
        local gap = along - (spec.length + ol) / 2
        local ov = 0
        if ospec and cos((o.h or 0) - car.h) < -0.3 and lateral > 1.2 then return end
        if ospec then
          -- how fast it moves along our heading
          ov = max(0, (o.v or 0) * (cos(o.h or 0) * fx + sin(o.h or 0) * fz))
        end
        local allowed
        if gap < 1.5 then allowed = 0 else allowed = ov + (gap - 1.5) * 0.9 end
        if isPed and gap > 7 then allowed = 1e9 end
        if allowed < limit then limit, who = allowed, o end
      end
    end
  end
  for _, o in ipairs(env.world:near(car.x, car.z, reach + 3, "vehicle")) do
    if o ~= car then consider(o, false) end
  end
  if env.peds then
    for _, o in ipairs(env.world:near(car.x, car.z, 12, "ped")) do consider(o, true) end
  end
  local p = env.player
  if p and p ~= car then consider(p, false) end
  return limit, who
end

local function stoppingSpeed(rem, brake)
  if rem <= 0 then return 0 end
  return sqrt(2 * brake * rem) * 0.8
end

--- A junction ahead: should this car stop at the line? Returns the speed it may carry (nil = no constraint).
local function junction(d, car, env, rem)
  local e = d.edge
  local at = d.dir == 1 and e.b or e.a
  local node = d.roads:node(at)
  if not node or #node.edges < 3 or d.emergency then return nil end
  local brake = car.spec.brake * 0.6
  local line = rem - 3.2
  if signals.isSignal(node) then
    local st = signals.state(node, e, env.time or 0)
    if st == "red" then return stoppingSpeed(line, brake) end
    if st == "amber" and stoppingSpeed(line, brake) > car.v + 1 then return stoppingSpeed(line, brake) end
    return nil
  end
  -- no light: give way to what has the right of way and is about to be in the junction
  if (d.pushy and d.pushy > 0) or d.emergency then return nil end
  local myP = signals.priority(e)
  local myEta = rem / max(car.v, 2)
  local p = env.player
  local nx, nz = node.x, node.z
  local function conflict(o)
    local dx, dz = o.x - nx, o.z - nz
    local dist = sqrt(dx * dx + dz * dz)
    if dist > 22 or abs((o.y or 0) - (node.y or 0)) > 3 then return false end
    local od = o.drv
    if od then
      if od.edge == e then return false end
      local dest = od.dir == 1 and od.edge.b or od.edge.a
      if dest ~= at and dist > 7 then return false end -- going somewhere else
      local oP = signals.priority(od.edge)
      if dest ~= at then
        -- already in the junction and leaving: it clears the way for us
        return dist < 5 and oP >= myP
      end
      local oEta = dist / max(o.v or 0, 2)
      if oP ~= myP then return oP > myP end
      if abs(oEta - myEta) < 0.4 then return (o.drv.id or 0) < d.id end
      return oEta < myEta
    end
    -- a person driving (or standing in the road): they go first when they are in the junction
    return dist < 8 and abs(o.v or 0) > 1
  end
  local blocked = false
  for _, o in ipairs(env.world:near(nx, nz, 22, "vehicle")) do
    if o ~= car and conflict(o) then blocked = true break end
  end
  if not blocked and p and p ~= car and conflict(p) then blocked = true end
  if blocked then
    return stoppingSpeed(line, brake)
  end
  return nil
end

--- Is the oncoming lane clear for a pass? Looks 45 units ahead for anything coming the other way.
local function oncomingClear(d, car, env)
  local fx, fz = cos(car.h), sin(car.h)
  for _, o in ipairs(env.world:near(car.x + fx * 25, car.z + fz * 25, 32, "vehicle")) do
    if o ~= car then
      local dx, dz = o.x - car.x, o.z - car.z
      local along = dx * fx + dz * fz
      if along > -6 and along < 52 then
        if (o.v or 0) > 1 or abs(dx * fz - dz * fx) < 6 then
          if cos((o.h or 0) - car.h) < 0.2 or along < 8 then return false end
        end
      end
    end
  end
  return true
end

--- One step of driving: the throttle, steer and handbrake for this frame.
function M.step(d, car, dt, env)
  local roads = d.roads
  local e = d.edge
  if roads:edge(e.id) ~= e then
    local again = M.attach(roads, car.x, car.z, car.h, d.rng)
    if not again then
      d.lost = (d.lost or 0) + dt
      return { throttle = -0.3, steer = 0 }
    end
    d.edge, d.s, d.dir, d.nxt = again.edge, again.s, again.dir, nil
    e = d.edge
  end
  d.lost = nil
  d.pushy = d.pushy and d.pushy > 0 and d.pushy - dt or nil
  if car.ghost then car.ghost = car.ghost > dt and car.ghost - dt or nil end
  local s, off = project(e, car.x, car.z)
  d.s = s
  d.off = off
  local v = car.v
  local rem = d.dir == 1 and (e.length - s) or s
  if not d.nxt and rem < M.LOOK + 14 + abs(v) * 1.2 then d.nxt, d.nxtAt = M.choose(d) end
  local nxt = d.nxt
  if nxt and nxt ~= e and rem < 14 then
    -- the next edge takes over once the car is nearer to it (a right turn cuts the corner before the end of this one)
    local s2, d2 = project(nxt, car.x, car.z)
    if rem < 1.2 or d2 < off - 0.3 then
      enter(d, nxt, d.nxtAt)
      e = d.edge
      d.s = s2
      s = s2
      off = d2
      d.off = d2
      rem = d.dir == 1 and (e.length - s) or s
      if not d.nxt and rem < M.LOOK + 14 + abs(v) * 1.2 then d.nxt, d.nxtAt = M.choose(d) end
    end
  end

  -- a dead end: round the bend in one sweep, then back the way it came
  if d.nxt == e and rem < 4.5 and not d.uturn then d.uturn = car.h end
  if d.uturn then
    if abs(util.wrap(car.h - d.uturn)) > 2.6 or d.rev > 0 then
      d.uturn, d.dir, d.nxt, d.nxtAt = nil, -d.dir, nil, nil
    else
      return { throttle = util.clamp((3.2 - v) * 0.6, -1, 1), steer = -1 }
    end
  end

  -- backing out of a jam
  if d.rev > 0 then
    d.rev = d.rev - dt
    return { throttle = -1, steer = -(d.revSteer or 1) }
  end

  -- where to aim
  local look = M.LOOK + abs(v) * 0.35
  local tx, tz = target(d, look)
  local diff = util.wrap(atan2(tz - car.z, tx - car.x) - car.h)
  local steer = util.clamp(diff * 2.4, -1, 1)

  -- how fast
  local base = (e.speed or 12) * d.speedMul * (d.panic and 1.35 or 1)
  local want = bendSpeed(d, base, abs(v))
  if abs(diff) > 0.55 then want = min(want, 6) end
  if d.nxt and rem < 20 and d.nxt.speed and d.nxt.speed < want then want = max(d.nxt.speed, 5) end
  if d.nxt == e then want = min(want, 3.5 + rem * 0.6) end
  local fx, fz = cos(car.h), sin(car.h)
  local limit, who = leader(d, car, env, fx, fz, 14 + abs(v) * 0.6)
  if d.pushy and d.pushy > 0 then limit = 1e9 end
  if limit <= 0.1 and abs(v) < 0.5 then
    d.blocked = (d.blocked or 0) + dt
    if d.blocked > 5 then d.blocked, d.pushy, d.knot = 0, 3, (d.knot or 0) + 1 end -- two cars waiting for each other: one goes
  else
    d.blocked = max(0, (d.blocked or 0) - dt)
  end
  if limit < want then want = limit end
  local yielding = false
  -- (a driver who has waited long enough goes: pushy beats the junction's right of way too, or a knot of cars all
  -- giving way to each other never clears)
  if rem < 16 + abs(v) * 0.8 and not (d.pushy and d.pushy > 0) then
    local jl = junction(d, car, env, rem)
    if jl and jl < want then want = jl yielding = true end
  end

  -- overtaking: a slow leader, a two-lane road, a clear oncoming lane and no junction near
  if d.lane and e.lanes ~= 1 and e.width >= 6 then
    if who and who.spec and limit < base * 0.55 and d.over <= 0 and rem > 40 and abs(who.v or 0) < base * 0.5 then
      d.slow = (d.slow or 0) + dt
      if d.slow > 2.5 and oncomingClear(d, car, env) then d.over, d.slow = 3.5, 0 end
    else
      d.slow = max(0, (d.slow or 0) - dt)
    end
    if d.over > 0 then
      d.over = d.over - dt
      if rem < 14 or not oncomingClear(d, car, env) and d.over < 2.5 then d.over = min(d.over, 0.2) end
      d.latWant = d.over > 0 and laneOffset(e) * 2 or 0
    else
      d.latWant = 0
    end
    d.lat = util.approach(d.lat, d.latWant, 3 * dt)
    if d.over > 0 and limit < want then want = max(limit, want * 0.6) end
  else
    d.lat = util.approach(d.lat, 0, 4 * dt)
  end

  if env.debug then d.dbg = string.format('want=%.1f limit=%.1f base=%.1f yielding=%s who=%s', want, limit, base, tostring(yielding), who and tostring(who.id) or 'nil') end
  local input = { throttle = util.clamp((want - v) * 0.5, -1, 1), steer = steer }
  if want <= 0.1 and v < 1 then input.throttle = 0 input.handbrake = true end

  -- stuck: wanting to go, not going
  if want > 2.5 and abs(v) < 0.6 and not yielding and d.over <= 0 then
    d.stuck = d.stuck + dt
    if d.stuck > 2.4 then
      d.stuck = 0
      d.jams = (d.jams or 0) + 1
      d.knot = (d.knot or 0) + 1
      if d.knot >= M.KNOT then
        -- backed out and run into the same cars three times: wedged in a knot with them. Slip through for a moment
        -- (car.ghost: no car-to-car bumps) and go, rather than sit there for ever
        d.knot = 0
        car.ghost = M.GHOST_SECONDS
        d.pushy = M.GHOST_SECONDS
      else
        d.rev = 1.1
        d.revSteer = steer >= 0 and 1 or -1
      end
    end
  elseif want > 2.5 then
    d.stuck = max(0, d.stuck - dt)
  end
  if v > 4 then d.knot = 0 end -- going (backing out at speed is not getting anywhere)
  if yielding and abs(v) < 0.8 then
    d.wait = d.wait + dt
    if d.wait > 5 then d.wait, d.pushy = 0, 3 end -- nobody moves: go anyway
  else
    d.wait = max(0, d.wait - dt)
  end
  return input
end

--- Move a car along its edge without physics: far from the player, only its place matters. Keeps to the lane, slows
-- behind the car in front (only looks along its own edge), sets x, y, z, h, v on the car and moves nothing else.
function M.rail(d, car, dt, env, speed)
  local roads = d.roads
  local e = d.edge
  if roads:edge(e.id) ~= e then
    local again = M.attach(roads, car.x, car.z, car.h, d.rng)
    if not again then return false end
    d.edge, d.s, d.dir = again.edge, again.s, again.dir
    e = d.edge
  end
  local v = min(speed or (e.speed * d.speedMul), e.speed * d.speedMul)
  -- headway: something on this edge just ahead of us along it
  for _, o in ipairs(env.world:near(car.x, car.z, 16, "vehicle")) do
    if o ~= car and o.drv and o.drv.edge == e and o.drv.dir == d.dir then
      local gap = (o.drv.s - d.s) * d.dir
      if gap > 0 and gap < 12 then v = min(v, max(0, (o.v or 0) * 0.9 + (gap - 6) * 0.5)) end
    end
  end
  local move = v * dt
  local guard = 0
  while move > 0 and guard < 4 do
    guard = guard + 1
    local rem = d.dir == 1 and (e.length - d.s) or d.s
    if move < rem then
      d.s = d.s + d.dir * move
      move = 0
    else
      move = move - rem
      d.s = d.dir == 1 and e.length or 0
      local nxt, at = M.choose(d)
      enter(d, nxt, at)
      e = d.edge
    end
  end
  local side = d.lane and d.dir * laneOffset(e) or 0
  local x, y, z, dx, dz = roads:pointAt(e, d.s, side)
  car.x, car.y, car.z = x, y, z
  car.h = atan2(dz * d.dir, dx * d.dir)
  car.v = v
  car.pitch, car.roll = 0, 0
  return true
end

return M
