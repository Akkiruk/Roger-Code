-- ai/peds.lua
-- The people. They walk the pavements beside the roads and the winding paths of the park (edges of the road graph, an
-- offset from the centre line), stop to look in windows or stand about by district and hour, cross at junctions, step
-- out of the way of cars, run from gunfire and crashes, and are knocked down (never killed) when a car hits them: they
-- lie there a few seconds, see stars, get up and run. Update rates drop with distance (the entity world's lod): near
-- every frame, mid at 5 Hz. Pure but for the context.
--
--   local P = peds.new(ctx)      P:update(dt)      P:count()      P:clear()
--   P:scare(x, z, radius, kind)  everyone near runs from (x, z)
--   P:knock(ped, vx, vz, byPlayer)   a ped is hit: down, then stars, then up and away (a crew turns on you if byPlayer)
--   P:spawnOfficer(x, z, h, y)   a standing officer (roadblocks) who dives if a car comes at them

local util = require("sg.util")

local M = {}
local P = {}
P.__index = P

local cos, sin, abs, sqrt = math.cos, math.sin, math.abs, math.sqrt
local atan2 = math.atan2 or math.atan

M.BASE = 26
M.SPAWN_MIN, M.SPAWN_MAX = 18, 72
M.DESPAWN = 95
M.QUALITY = { 1, 0.85, 0.7, 0.6 }
M.SHIRTS = { "red", "blue", "lime", "magenta", "white", "cyan", "purple", "yellow", "green", "orange" }
M.WALKABLE = { road = true, avenue = true, alley = true, path = true }

-- how many people are out by district, and how likely one is to stop and stand about at a corner: { night, morning, day, evening }
M.DENSITY = {
  gilt = { 0.15, 0.5, 1.0, 0.8 },
  lantern = { 0.9, 0.3, 0.6, 1.0 },
  cinder = { 0.1, 0.9, 0.6, 0.2 },
  brine = { 0.2, 0.9, 0.7, 0.3 },
  mid = { 0.2, 0.7, 0.8, 0.7 },
}
M.LINGER = {
  gilt = { 0.1, 0.15, 0.4, 0.3 },
  lantern = { 0.5, 0.1, 0.25, 0.5 },
  cinder = { 0.05, 0.05, 0.2, 0.1 },
  brine = { 0.1, 0.1, 0.3, 0.15 },
  mid = { 0.1, 0.15, 0.3, 0.25 },
}

local function block(hour)
  if hour >= 22 or hour < 5 then return 1 end
  if hour < 10 then return 2 end
  if hour < 17 then return 3 end
  return 4
end

function M.new(ctx, seed)
  return setmetatable({ ctx = ctx, rng = util.rng(seed or 53), list = {}, edges = nil, dirty = true, last = 0, hitDebounce = 0 }, P)
end

function P:hour() return self.ctx.hour or 17 end

function P:count()
  local n = 0
  for _ in pairs(self.list) do n = n + 1 end
  return n
end

function P:refresh()
  local list = {}
  for _, e in pairs(self.ctx.roads.edges) do
    if M.WALKABLE[e.kind] and e.length >= 8 then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  self.edges = list
  self.dirty = false
end

local function sideOffset(e, lat)
  if e.kind == "path" then return lat * 0.5 end
  return lat * (e.width / 2 + 1.4)
end

--- Put a person on edge e at s, walking dir, on the pavement side lat (-1 or 1).
function P:spawnOn(e, s, dir, lat)
  local ctx = self.ctx
  local x, y, z = ctx.roads:pointAt(e, s, sideOffset(e, lat))
  local ped = ctx.world:add({
    kind = "ped", tags = { ped = true }, x = x, y = y, z = z, h = 0, radius = 0.4, health = 1,
    edge = e, s = s, dir = dir, lat = lat, speed = 1.2 + self.rng() * 0.9, state = "walk", t = 0, acc = 0,
    shirt = M.SHIRTS[self.rng(#M.SHIRTS)], born = ctx.time or 0, wob = self.rng() * 6,
  })
  self.list[ped] = true
  return ped
end

function P:spawnOfficer(x, z, h, y)
  local ped = self.ctx.world:add({
    kind = "ped", tags = { ped = true, officer = true }, x = x, y = y or 0, z = z, h = h or 0, radius = 0.4, health = 1,
    speed = 1.4, state = "stand", t = 0, acc = 0, shirt = "blue", officer = true, born = self.ctx.time or 0, wob = 0,
  })
  self.list[ped] = true
  return ped
end

function P:remove(ped)
  self.list[ped] = nil
  self.ctx.world:remove(ped)
end

function P:clear()
  for ped in pairs(self.list) do self.ctx.world:remove(ped) end
  self.list = {}
end

function P:target()
  local ctx = self.ctx
  local c = ctx.stream:chunkAt(ctx.player.x, ctx.player.z)
  local row = M.DENSITY[c and c.district or "mid"] or M.DENSITY.mid
  local q = M.QUALITY[(ctx.budget and ctx.budget.quality or 0) + 1] or 1
  return math.floor(M.BASE * row[block(self:hour())] * q + 0.5)
end

--- Everyone within radius of (x, z) runs away from it.
function P:scare(x, z, radius, kind)
  local n = 0
  for _, ped in ipairs(self.ctx.world:near(x, z, radius, "ped")) do
    if ped.state ~= "down" and ped.state ~= "dazed" and not ped.gang then
      local away = atan2(ped.z - z, ped.x - x) + (self.rng() - 0.5) * 0.9
      ped.state = (ped.officer and kind ~= "gunfire") and "stand" or "flee"
      if ped.state == "flee" then
        ped.fleeH = away
        ped.t = 4 + self.rng() * 3
        ped.cower = (self.rng() < 0.18) and 2.5 or nil
        n = n + 1
      end
    end
  end
  return n
end

--- A person is hit and knocked down: flat on the ground with stars, then up and running.
function P:knock(ped, vx, vz, byPlayer)
  if ped.state == "down" then return end
  if self.onKnock then self.onKnock(ped, byPlayer) end
  ped.state, ped.t = "down", 3.2 + self.rng() * 1.5
  ped.fleeH = atan2(vz or 0, vx or 1)
  ped.slide = { (vx or 0) * 0.5, (vz or 0) * 0.5 }
end

local function pushOut(ctx, ped, nx, nz)
  local x, z = ctx.stream:collide(nx, nz, 0.4, ped.y)
  return x, z
end

--- At the end of an edge: another one from the node, preferring to carry on, crossing over some of the time.
local function nextEdge(self, ped)
  local e = ped.edge
  local at = ped.dir == 1 and e.b or e.a
  local node = self.ctx.roads.nodes[at]
  local pool = {}
  if node then
    for _, x in ipairs(node.edges) do
      if M.WALKABLE[x.kind] and x ~= e then pool[#pool + 1] = x end
    end
  end
  local nxt = #pool > 0 and pool[self.rng(#pool)] or e
  ped.edge = nxt
  if nxt == e then
    ped.dir = -ped.dir
  elseif nxt.a == at then
    ped.dir, ped.s = 1, 0
  else
    ped.dir, ped.s = -1, nxt.length
  end
  if self.rng() < 0.4 then ped.lat = -ped.lat end
  -- a stop at a corner by district and hour
  local c = self.ctx.stream:chunkAt(ped.x, ped.z)
  local row = M.LINGER[c and c.district or "mid"] or M.LINGER.mid
  if self.rng() < row[block(self:hour())] then
    ped.state, ped.t = "idle", 3 + self.rng() * 9
  end
end

local function stepWalk(self, ped, dt)
  local ctx = self.ctx
  local e = ctx.roads.edges[ped.edge.id]
  if e ~= ped.edge then
    local ne, s = ctx.roads:nearest(ped.x, ped.z, 25)
    if not ne then self:remove(ped) return end
    ped.edge, ped.s = ne, s
    e = ne
  end
  ped.s = ped.s + ped.dir * ped.speed * dt
  if ped.s >= e.length or ped.s <= 0 then
    ped.s = ped.dir == 1 and e.length or 0
    nextEdge(self, ped)
    e = ped.edge
  end
  -- walk toward a point a little ahead on the pavement (crossing smoothly where the side changes)
  local tx, ty, tz = ctx.roads:pointAt(e, util.clamp(ped.s + ped.dir * 1.2, 0, e.length), sideOffset(e, ped.lat))
  local dx, dz = tx - ped.x, tz - ped.z
  local d = sqrt(dx * dx + dz * dz)
  if d > 0.01 then
    local step = math.min(d, ped.speed * 1.15 * dt)
    ctx.world:move(ped, ped.x + dx / d * step, ped.z + dz / d * step)
    ped.h = atan2(dz, dx)
  end
  ped.y = ty
end

local function stepFlee(self, ped, dt)
  local ctx = self.ctx
  if ped.cower and ped.cower > 0 then
    ped.cower = ped.cower - dt
    return
  end
  local nx = ped.x + cos(ped.fleeH) * 5.4 * dt
  local nz = ped.z + sin(ped.fleeH) * 5.4 * dt
  local x, z, hit = ctx.stream:collide(nx, nz, 0.4, ped.y)
  if hit then ped.fleeH = ped.fleeH + 1.4 end
  local gy = ctx.stream:groundAt(x, z, ped.y + 1)
  if gy and gy < (ctx.stream:waterAt(x, z) or -1e9) - 0.8 then
    ped.fleeH = ped.fleeH + 2.5 -- not into the sea
  elseif gy and abs(gy - ped.y) < 1.3 then
    ctx.world:move(ped, x, z)
    ped.y = gy
  else
    ped.fleeH = ped.fleeH + 1.2
  end
  ped.h = ped.fleeH
end

--- Move one person dt seconds.
local function update(self, ped, dt)
  local ctx = self.ctx
  local st = ped.state
  if st == "walk" then
    stepWalk(self, ped, dt)
    -- step out of the way of a fast car coming at us (checked a few times a second)
    ped.look = (ped.look or 0) - dt
    if ped.look <= 0 then
      ped.look = 0.25
      local cars = ctx.world:near(ped.x, ped.z, 10, "vehicle")
      if ctx.player.car then cars[#cars + 1] = ctx.player.car end
      for _, c in ipairs(cars) do
        if abs(c.v or 0) > 6 then
          local rx, rz = ped.x - c.x, ped.z - c.z
          local fx, fz = cos(c.h), sin(c.h)
          local along = rx * fx + rz * fz
          local lateral = rx * fz - rz * fx
          if along > 0 and abs(lateral) < 3.2 then
            ped.state, ped.t = "flee", 1.6
            -- sidestep: across the car's line, away from it
            local sgn = lateral >= 0 and 1 or -1
            ped.fleeH = atan2(-fx * sgn, fz * sgn)
            break
          end
        end
      end
    end
  elseif st == "idle" then
    ped.t = ped.t - dt
    if ped.t <= 0 then ped.state = "walk" end
  elseif st == "flee" then
    ped.t = ped.t - dt
    stepFlee(self, ped, dt)
    if ped.t <= 0 then
      local ne, s = ctx.roads:nearest(ped.x, ped.z, 30)
      if ne then
        ped.edge, ped.s, ped.state, ped.lat = ne, s, ped.officer and "stand" or "walk", (self.rng() < 0.5) and 1 or -1
        ped.dir = self.rng() < 0.5 and 1 or -1
      else
        self:remove(ped)
      end
    end
  elseif st == "down" then
    ped.t = ped.t - dt
    if ped.slide then
      local k = math.min(1, dt * 4)
      ctx.world:move(ped, ped.x + ped.slide[1] * k, ped.z + ped.slide[2] * k)
      ped.slide[1], ped.slide[2] = ped.slide[1] * (1 - k), ped.slide[2] * (1 - k)
    end
    if ped.t <= 0 then ped.state, ped.t, ped.slide = "dazed", 1.4, nil end
  elseif st == "dazed" then
    ped.t = ped.t - dt
    if ped.t <= 0 then
      ped.state, ped.t, ped.fleeH = "flee", 3 + self.rng() * 2, (ped.fleeH or 0) + math.pi + (self.rng() - 0.5)
    end
  end
end

--- Cars run into people: knocked down, not killed. Returns the cars that hit somebody (the player's included).
function P:carHits(dt)
  local ctx = self.ctx
  self.hitDebounce = math.max(0, self.hitDebounce - dt)
  for _, car in ipairs(ctx.cars) do
    if abs(car.v or 0) > 3 then
      local reach = (car.spec.radius or 2) * 0.75 + 0.4
      for _, ped in ipairs(ctx.world:near(car.x, car.z, reach + 0.5, "ped")) do
        if ped.state ~= "down" and ped.state ~= "dazed" and abs((ped.y or 0) - (car.y or 0)) < 2 then
          local dx, dz = ped.x - car.x, ped.z - car.z
          if dx * dx + dz * dz < reach * reach then
            self:knock(ped, cos(car.h) * math.max(2, car.v * 0.4), sin(car.h) * math.max(2, car.v * 0.4), car == ctx.player.car)
            car.v = car.v * 0.9
            if car == ctx.player.car and self.hitDebounce <= 0 then
              self.hitDebounce = 2.5
              ctx.bus:emit("crime", { kind = "assault", level = 1, x = ped.x, z = ped.z })
            end
          end
        end
      end
    end
  end
end

function P:update(dt)
  local ctx = self.ctx
  local p = ctx.player
  if self.dirty or not self.edges then self:refresh() end
  self.last = self.last + dt
  -- the people themselves, near ones every frame
  for ped in pairs(self.list) do
    local lod = ped.lod or "near"
    local step = dt
    local run = true
    if lod ~= "near" then
      ped.acc = ped.acc + dt
      run = ped.acc >= 0.2
      step = ped.acc
      if run then ped.acc = 0 end
    end
    if run then update(self, ped, step) end
    if ped.removed then self.list[ped] = nil end
  end
  self:carHits(dt)
  -- who goes, who comes
  local limit2 = M.DESPAWN ^ 2
  local n = 0
  for ped in pairs(self.list) do
    n = n + 1
    if (ped.x - p.x) ^ 2 + (ped.z - p.z) ^ 2 > limit2 and not ped.keep then self:remove(ped) end
  end
  local want = self:target()
  if n < want and self.edges and #self.edges > 0 then
    local burst = self.filled and 2 or math.min(want - n, 14)
    for _ = 1, burst do
      for _ = 1, 5 do
        local e = self.edges[self.rng(#self.edges)]
        local s = e.length * self.rng()
        local x, _, z = ctx.roads:pointAt(e, s, 0)
        local d2 = (x - p.x) ^ 2 + (z - p.z) ^ 2
        local lo = self.filled and M.SPAWN_MIN or 10
        if d2 >= lo * lo and d2 <= M.SPAWN_MAX ^ 2 then
          self:spawnOn(e, s, self.rng() < 0.5 and 1 or -1, self.rng() < 0.5 and 1 or -1)
          break
        end
      end
    end
    self.filled = true
  end
end

return M
