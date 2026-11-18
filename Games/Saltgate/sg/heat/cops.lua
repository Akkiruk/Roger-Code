-- heat/cops.lua
-- The Harbor Patrol's cruisers. At level 0 they are ordinary traffic that happens to be police. Wanted, they hear about
-- it, drive to where you were last seen by the road graph (their own A* that goes round roadblocks), and once they see
-- you they come straight at you with roles: a chaser behind, flankers either side, a blocker ahead that slows to box you
-- in, and (level 3 up) a PIT that noses into your rear quarter and spins you. Stopped with cruisers around you for
-- long enough is a pinch. Cartoony: nobody is hurt but the paint.
--
--   local C = cops.new(ctx, traffic)
--   C:update(dt, wanted)  -> seen (bool: a cruiser sees you), nabbed (bool)
--   C:input(car, dt, env) the brain of a cruiser in the physics loop
--   C:speed(car) the speed a cruiser on a rail keeps
--   C.chasers() the cruisers that are after you

local lane = require("sg.ai.lane")
local planner = require("sg.ai.planner")
local los = require("sg.heat.los")
local wantedLib = require("sg.heat.wanted")
local vehicle = require("sg.vehicle")
local util = require("sg.util")

local M = {}
local C = {}
C.__index = C

local cos, sin, abs, sqrt, min, max = math.cos, math.sin, math.abs, math.sqrt, math.min, math.max
local atan2 = math.atan2 or math.atan

M.SIGHT = 62
M.SIGHT_NIGHT = 46
M.PINCH = 2.5

function M.new(ctx, traffic, seed)
  local self = setmetatable({
    ctx = ctx, traffic = traffic, rng = util.rng(seed or 17), wanted = nil, spawnT = 0, roleT = 0, planned = 0,
    pinch = 0, avoid = {}, nabbed = false, pitCool = 0,
  }, C)
  traffic.copBrain = function(car, dt, env) return self:input(car, dt, env) end
  traffic.copSpeed = function(car) return self:speed(car) end
  return self
end

--- The thing being chased: your car, or you on foot.
function C:target()
  local p = self.ctx.player
  if p.car then return p.car end
  return p
end

function C:cruisers()
  local out = {}
  for car in pairs(self.traffic.cars) do
    if car.cop and not car.wrecked then out[#out + 1] = car end
  end
  return out
end

function C:chasers()
  local out = {}
  for _, car in ipairs(self:cruisers()) do
    if car.cop.state ~= "patrol" then out[#out + 1] = car end
  end
  return out
end

function C:sight()
  local night = self.ctx.hour and (self.ctx.hour >= 21 or self.ctx.hour < 5)
  return night and M.SIGHT_NIGHT or M.SIGHT
end

--- Does this cruiser see the target? Cached a third of a second.
local function sees(self, car, tgt, dt)
  local c = car.cop
  c.losT = (c.losT or 0) - dt
  if c.losT > 0 then return c.los end
  c.losT = 0.3 + (car.id % 5) * 0.03
  local dx, dz = tgt.x - car.x, tgt.z - car.z
  local d2 = dx * dx + dz * dz
  local s = self:sight()
  if d2 > s * s then
    c.los = false
  else
    c.los = los.clear(self.ctx.stream, car.x, (car.y or 0) + 1.2, car.z, tgt.x, (tgt.y or 0) + 1.0, tgt.z, 5)
  end
  return c.los
end

--- A route for a cruiser to a place: its lane driver's route is a list of edges from the end of the one it is on.
function C:plan(car, gx, gz)
  local d = car.drv
  if not d or not self.ctx.roads:edge(d.edge.id) then return false end
  local goal = planner.nearestNode(self.ctx.roads, gx, gz, 60)
  if not goal then return false end
  local at = d.dir == 1 and d.edge.b or d.edge.a
  local route = planner.path(self.ctx.roads, at, goal, { avoid = self.avoid, kinds = lane.DRIVABLE })
  self.planned = self.planned + 1
  d.route = route
  return route ~= nil
end

--- Put a cruiser's lane driver back on the road from wherever it is.
local function reattach(self, car)
  local d = lane.attach(self.ctx.roads, car.x, car.z, car.h, self.rng)
  if d then
    d.emergency = true
    car.drv = d
  end
  return d
end

--- The speed a cruiser keeps when it is far away and on a rail.
function C:speed(car)
  local plan = wantedLib.plan(self.wanted and self.wanted.level or 0)
  if car.cop and car.cop.state ~= "patrol" and car.drv then return car.drv.edge.speed * 1.5 * plan.speed end
  return nil
end

-- ---------------------------------------------------------------- driving at the target

--- Steer at a point, turning away from a wall a few units ahead.
local function steerAt(self, car, ax, az)
  local want = atan2(az - car.z, ax - car.x)
  local diff = util.wrap(want - car.h)
  local ahead = 7 + abs(car.v) * 0.25
  local fx, fz = cos(car.h + diff * 0.4), sin(car.h + diff * 0.4)
  local _, _, hit, hnx, hnz = self.ctx.stream:collide(car.x + fx * ahead, car.z + fz * ahead, car.spec.radius * 0.9, car.y)
  local blocked = false
  if hit then
    blocked = true
    -- turn along the wall: the side its normal leans toward
    local side = (hnx * -sin(car.h) + hnz * cos(car.h)) >= 0 and 1 or -1
    diff = util.clamp(diff + side * 0.9, -1.4, 1.4)
  end
  return util.clamp(diff * 2.3, -1, 1), diff, blocked
end

--- The aim point and the speed for a cruiser in its role.
local function aim(self, car, c, tgt, plan)
  local pv = tgt.v or 0
  local ph = tgt.h or 0
  local fx, fz = cos(ph), sin(ph)
  local rx, rz = -fz, fx
  local dx, dz = car.x - tgt.x, car.z - tgt.z
  local along = dx * fx + dz * fz -- + ahead of the target, - behind
  local lat = dx * rx + dz * rz
  local dist = sqrt(dx * dx + dz * dz)
  local top = car.spec.top * plan.speed
  local role = c.role or "chaser"
  local lead = util.clamp(dist / 28, 0, 0.7)
  local ax, az = tgt.x + fx * pv * lead, tgt.z + fz * pv * lead
  local want = top
  if role == "blocker" then
    -- get in front, then slow so the others close in
    ax, az = tgt.x + fx * (9 + pv * 0.7), tgt.z + fz * (9 + pv * 0.7)
    if along > 3 then
      want = util.clamp(pv * 0.75 + (along - 6) * 0.3, 0, top)
      if along < 11 and pv < 9 then want = 0 end
      if along > 3 and along < 16 then want = min(want, max(pv * 0.55, 0)) end
    end
  elseif role == "flank" then
    local sgn = c.side or (lat >= 0 and 1 or -1)
    ax, az = tgt.x + fx * pv * 0.3 + rx * sgn * 0.5, tgt.z + fz * pv * 0.3 + rz * sgn * 0.5
    want = min(top, pv + 4)
  elseif role == "pit" then
    local sgn = c.side or (lat >= 0 and 1 or -1)
    ax, az = tgt.x - fx * 1.7 + rx * sgn * 0.9, tgt.z - fz * 1.7 + rz * sgn * 0.9
    want = min(top, pv + 6)
  else
    -- chaser: stay on the tail; ease off when right behind a slow target so it is not rammed to a stop
    if dist < 9 and pv < 6 then want = max(0, pv) end
  end
  if abs(pv) < 4 and role ~= "blocker" then want = util.clamp((dist - 4.5) * 1.4, 0, top) end
  return ax, az, want, along, lat, dist
end

--- A cruiser's input this step.
function C:input(car, dt, env)
  local ctx = self.ctx
  local c = car.cop
  local w = self.wanted
  local plan = wantedLib.plan(w and w.level or 0)
  if not c then return lane.step(car.drv, car, dt, env) end
  if (w and w.level or 0) == 0 or c.state == "patrol" then
    if car.drv then car.drv.emergency = nil end
    car.drv = car.drv or reattach(self, car)
    if not car.drv then return { throttle = 0, steer = 0, handbrake = true } end
    return lane.step(car.drv, car, dt, env)
  end
  if car.wrecked then return { throttle = 0, steer = 0 } end
  local tgt = self:target()
  if c.recoil and c.recoil > 0 then
    c.recoil = c.recoil - dt
    return { throttle = -0.6, steer = 0 }
  end
  local seen = sees(self, car, tgt, dt)
  local dist = sqrt((tgt.x - car.x) ^ 2 + (tgt.z - car.z) ^ 2)
  c.ban = max(0, (c.ban or 0) - dt)
  local direct = seen and dist < 80 and c.ban <= 0
  if direct then
    if c.state ~= "pursue" then c.state = "pursue" end
    car.drv = nil
    -- reversing out of a wedge
    if c.rev and c.rev > 0 then
      c.rev = c.rev - dt
      return { throttle = -1, steer = -(c.revSteer or 1) }
    end
    local ax, az, want, along, lat, d = aim(self, car, c, tgt, plan)
    local steer, diff, blocked = steerAt(self, car, ax, az)
    if abs(diff) > 0.9 then want = min(want, 8) end
    if blocked then want = min(want, 12) end
    -- other cars in the way (not the target)
    local fx, fz = cos(car.h), sin(car.h)
    for _, o in ipairs(ctx.world:near(car.x + fx * 6, car.z + fz * 6, 6, "vehicle")) do
      if o ~= car then
        local ox, oz = o.x - car.x, o.z - car.z
        if ox * fx + oz * fz > 0 and abs(ox * fz - oz * fx) < 2.4 and (o.v or 0) < car.v - 3 then
          want = min(want, max(0, (o.v or 0) * 0.8))
        end
      end
    end
    local input = { throttle = util.clamp((want - car.v) * 0.6, -1, 1), steer = steer }
    if want <= 0.1 and abs(car.v) < 1 then input.throttle, input.handbrake = 0, true end
    -- wedged: wanting to go, not going
    if want > 4 and abs(car.v) < 0.7 then
      c.stuck = (c.stuck or 0) + dt
      if c.stuck > 1.4 then
        c.stuck, c.rev, c.revSteer = 0, 1.0, steer >= 0 and 1 or -1
        c.wedges = (c.wedges or 0) + 1
        if c.wedges >= 2 then c.ban, c.wedges = 7, 0 end -- use the roads for a while
      end
    else
      c.stuck = max(0, (c.stuck or 0) - dt)
    end
    c.along, c.lat, c.dist = along, lat, d
    return input
  end
  -- not seeing you (or too far): on the roads, toward where you were last seen
  c.state = "respond"
  if not car.drv or not ctx.roads:edge(car.drv.edge.id) or not car.drv.emergency then
    if not reattach(self, car) then return { throttle = -0.4, steer = 0 } end
  end
  local d = car.drv
  d.speedMul = 1.5 * plan.speed
  return lane.step(d, car, dt, env)
end

-- ---------------------------------------------------------------- roles and tactics

function C:assignRoles(tgt, plan)
  local list = self:chasers()
  local pursuing = {}
  for _, car in ipairs(list) do
    if car.cop.state == "pursue" then pursuing[#pursuing + 1] = car end
  end
  table.sort(pursuing, function(a, b)
    return (a.x - tgt.x) ^ 2 + (a.z - tgt.z) ^ 2 < (b.x - tgt.x) ^ 2 + (b.z - tgt.z) ^ 2
  end)
  local slot = 0
  for _, car in ipairs(pursuing) do
    local c = car.cop
    slot = slot + 1
    local role = "chaser"
    if plan.box then
      if slot == 2 then role = "flank" c.side = 1
      elseif slot == 3 then role = "flank" c.side = -1
      elseif slot >= 4 then
        -- one ahead of the target blocks; the rest chase
        if (c.along or 0) > 4 or slot == 4 then role = "blocker" end
      end
    end
    if plan.pit and slot == 1 and self.pitCool <= 0 and abs(tgt.v or 0) > 8 then role = "pit" end
    c.role = role
    c.pit = role == "pit"
    c.side = c.side or (((c.lat or 0) >= 0) and 1 or -1)
  end
end

--- The PIT: the cruiser's nose meets the target's rear quarter and the target is turned round.
function C:pit(dt, tgt)
  self.pitCool = max(0, self.pitCool - dt)
  if self.pitCool > 0 or not self.ctx.player.car then return end
  local plan = wantedLib.plan(self.wanted.level)
  if not plan.pit then return end
  local car = self.ctx.player.car
  for _, cop in ipairs(self:chasers()) do
    local c = cop.cop
    if c.pit and c.state == "pursue" then
      local dx, dz = cop.x - car.x, cop.z - car.z
      local d = sqrt(dx * dx + dz * dz)
      local reach = (cop.spec.radius + car.spec.radius) * 0.85 + 0.9
      if d < reach and abs(tgt.v or 0) > 6 then
        local fx, fz = cos(car.h), sin(car.h)
        local along = dx * fx + dz * fz
        local lat = dx * -fz + dz * fx
        if along < 1.2 then
          local sgn = lat >= 0 and 1 or -1
          car.h = util.wrap(car.h - sgn * 0.85)
          car.side = (car.side or 0) - sgn * 6
          car.v = car.v * 0.78
          vehicle.damage(car, 3)
          cop.v = cop.v * 0.6
          c.recoil, c.role, c.pit = 0.9, "chaser", false
          self.pitCool = max(2.5, 8 - self.wanted.level)
          self.ctx.bus:emit("player_hurt", { amount = 0, by = "pit" })
          return
        end
      end
    end
  end
end

--- Cruisers round a stopped target: a pinch.
function C:squeeze(dt, tgt)
  local n = 0
  for _, cop in ipairs(self:cruisers()) do
    if cop.cop.state ~= "patrol" then
      local d2 = (cop.x - tgt.x) ^ 2 + (cop.z - tgt.z) ^ 2
      local r = self.ctx.player.car and 7.5 or 4
      if d2 < r * r then n = n + 1 end
    end
  end
  local need = self.ctx.player.car and (self.wanted.level >= 3 and 2 or 1) or 1
  local slow = abs(tgt.v or 0) < (self.ctx.player.car and 5 or 1.5)
  if n >= need and slow then
    self.pinch = self.pinch + dt * (1 + 0.3 * (n - need))
  else
    self.pinch = max(0, self.pinch - dt * 2)
  end
  return self.pinch >= M.PINCH
end

-- ---------------------------------------------------------------- the whole squad

--- Turn the patrol cruisers on when you are wanted; bring more up to the plan; send extras home when it is over.
function C:update(dt, w)
  local ctx = self.ctx
  self.wanted = w
  self.planned = 0
  local tgt = self:target()
  local plan = wantedLib.plan(w.level)
  local seen = false
  local count = 0
  for _, car in ipairs(self:cruisers()) do
    local c = car.cop
    if w.level > 0 then
      if c.state == "patrol" then
        local d2 = (car.x - tgt.x) ^ 2 + (car.z - tgt.z) ^ 2
        if d2 < 170 * 170 then
          c.state = "respond"
          c.replan = 0
          if car.drv then car.drv.emergency = true end
        end
      end
      if c.state ~= "patrol" then count = count + 1 end
      if c.los and c.state == "pursue" then seen = true end
      -- replan a route now and then (one plan a frame at most)
      if c.state == "respond" and self.planned < 1 and car.drv then
        c.replan = (c.replan or 0) - dt
        if c.replan <= 0 then
          c.replan = 3 + self.rng() * 2
          local gx, gz
          if w.seen then
            gx, gz = tgt.x, tgt.z
          else
            -- somewhere in the search circle, the same place for a while so the cruiser gets there
            local g = c.goal
            if not g or (ctx.time or 0) > g.expires or (car.x - g.x) ^ 2 + (car.z - g.z) ^ 2 < 25 * 25 then
              local ang = self.rng() * math.pi * 2
              local r = w.radius * 0.8 * self.rng()
              g = { x = w.cx + cos(ang) * r, z = w.cz + sin(ang) * r, expires = (ctx.time or 0) + 10 }
              c.goal = g
            end
            gx, gz = g.x, g.z
          end
          self:plan(car, gx, gz)
        end
      end
    else
      if c.state ~= "patrol" then
        c.state = "patrol"
        c.role, c.pit = nil, false
        if car.drv then car.drv.emergency, car.drv.speedMul, car.drv.route = nil, 0.95, nil end
      end
    end
  end
  -- sightings count for any cruiser with a clear line, whatever it is doing
  if w.level > 0 then
    for _, car in ipairs(self:cruisers()) do
      if car.cop.state ~= "patrol" and car.cop.los then seen = true end
    end
    self.roleT = self.roleT - dt
    if self.roleT <= 0 then
      self.roleT = 0.5
      self:assignRoles(tgt, plan)
    end
    -- bring the squad up to strength
    self.spawnT = self.spawnT - dt
    if count < plan.cruisers and self.spawnT <= 0 then
      self.spawnT = 2.2
      local e, s, dir = self.traffic:randomSpot(85, 140, 14, self.traffic:playerComp())
      if e then
        local car = self.traffic:spawnOn(e, s, dir, true)
        if car then
          car.cop.state, car.cop.replan = "respond", 0
          car.drv.emergency = true
          car.drv.speedMul = 1.5 * plan.speed
        end
      end
    end
    self:pit(dt, tgt)
    self.nabbed = self:squeeze(dt, tgt)
  else
    self.pinch = 0
    self.nabbed = false
    -- the squad goes home: cruisers far out of sight are put away
    for _, car in ipairs(self:cruisers()) do
      local d2 = (car.x - tgt.x) ^ 2 + (car.z - tgt.z) ^ 2
      if d2 > 120 * 120 and (car.cop.sent or 0) > 6 then self.traffic:remove(car) end
      car.cop.sent = (car.cop.sent or 0) + dt
    end
  end
  return seen, self.nabbed
end

--- Everyone's off the case (busted or lost): back to patrol.
function C:release()
  for _, car in ipairs(self:cruisers()) do
    car.cop.state, car.cop.role, car.cop.pit, car.cop.sent = "patrol", nil, false, 0
    if car.drv then car.drv.emergency, car.drv.route = nil, nil end
  end
  self.pinch = 0
end

return M
