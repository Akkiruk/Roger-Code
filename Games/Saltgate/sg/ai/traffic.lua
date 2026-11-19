-- ai/traffic.lua
-- The city's cars. They are born out of sight on the roads round the player, drive the road graph in their lane
-- (ai/lane.lua), and are put away again when they are far behind or have been stuck too long. How many depends on the
-- district, the hour and the budget's quality. A few of them are Harbor Patrol cruisers on patrol (the police plugin turns
-- those on when you are wanted). Pure but for the context it is given.
--
--   local T = traffic.new(ctx)       T:update(dt)       T:count()       T:clear()       T:alarm(x, z, r)

local lane = require("sg.ai.lane")
local fleet = require("sg.ai.fleet")
local vehicle = require("sg.vehicle")
local util = require("sg.util")

local M = {}

local TRAFFIC_PAINTS = { "orange", "blue", "red", "lightGray", "green", "white", "cyan", "yellow", "gray", "brown" }
local T = {}
T.__index = T

M.BASE = 16 -- cars at a busy hour in a busy district with the budget at its best
M.SPAWN_MIN, M.SPAWN_MAX = 70, 150
M.DESPAWN = 175
M.IDLE_GO = 6 -- a car that has not got this far from where it was ...
M.IDLE_OUT_OF_VIEW = 25 -- ... in this many seconds, 30 or more units from you, is put away
M.IDLE_MAX = 40 -- ... and this many anywhere
M.QUALITY = { 1, 0.85, 0.7, 0.6 }

-- how busy the roads are by district and time: { night 22-5, morning 5-10, day 10-17, evening 17-22 }
M.DENSITY = {
  gilt = { 0.3, 0.8, 1.0, 1.0 },
  lantern = { 0.7, 0.5, 0.8, 1.0 },
  cinder = { 0.2, 1.0, 0.8, 0.5 },
  brine = { 0.2, 0.8, 0.7, 0.4 },
  mid = { 0.3, 0.9, 0.9, 0.9 },
}

local function block(hour)
  if hour >= 22 or hour < 5 then return 1 end
  if hour < 10 then return 2 end
  if hour < 17 then return 3 end
  return 4
end

function M.new(ctx, seed)
  local self = setmetatable({
    ctx = ctx, rng = util.rng(seed or 91), cars = {}, dirty = true, edges = nil, timer = 0, filled = false,
    env = { roads = ctx.roads, world = ctx.world, time = 0, peds = true, player = nil },
  }, T)
  ctx.bus:on("chunk_loaded", function() self.dirty = true end, "c_traffic")
  ctx.bus:on("chunk_unloaded", function() self.dirty = true end, "c_traffic")
  return self
end

function T:hour()
  return self.ctx.hour or 17
end

--- The drivable edges of what is loaded.
function T:refresh()
  local list = {}
  for _, e in pairs(self.ctx.roads.edges) do
    if lane.DRIVABLE[e.kind] and e.length >= 10 and e.width >= 3 then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  self.edges = list
  self.dirty = false
  -- which pieces of the road network join up (so a cruiser is never born where it cannot get to you)
  local at = {}
  for _, e in ipairs(list) do
    at[e.a] = at[e.a] or {}
    at[e.b] = at[e.b] or {}
    table.insert(at[e.a], e)
    table.insert(at[e.b], e)
  end
  local comp, n = {}, 0
  for _, e in ipairs(list) do
    if not comp[e.a] then
      n = n + 1
      local stack = { e.a }
      comp[e.a] = n
      while #stack > 0 do
        local id = table.remove(stack)
        for _, x in ipairs(at[id] or {}) do
          for _, o in ipairs({ x.a, x.b }) do
            if not comp[o] then
              comp[o] = n
              stack[#stack + 1] = o
            end
          end
        end
      end
    end
  end
  self.comp = comp
end

--- The id of the road network piece the player is on (nil when no road is near).
function T:playerComp()
  local p = self.ctx.player
  local e = self.ctx.roads:nearest(p.x, p.z, 60, lane.DRIVABLE)
  return e and self.comp and self.comp[e.a] or nil
end

--- How many cars the player's district wants right now.
function T:target()
  local ctx = self.ctx
  local c = ctx.stream:chunkAt(ctx.player.x, ctx.player.z)
  local row = M.DENSITY[c and c.district or "mid"] or M.DENSITY.mid
  local q = M.QUALITY[(ctx.budget and ctx.budget.quality or 0) + 1] or 1
  return math.floor(M.BASE * row[block(self:hour())] * q + 0.5)
end

function T:count()
  local n = 0
  for car in pairs(self.cars) do
    if not car.cop then n = n + 1 end
  end
  return n
end

local function pickKind(self)
  local pool = self.ctx.vehicles.traffic()
  if #pool == 0 then return "marlin" end
  local def = pool[self.rng(#pool)]
  return def.id
end

--- A car on edge e at s, in its lane (or nil when something is there already).
function T:spawnOn(e, s, dir, cop)
  local ctx = self.ctx
  local side = dir * lane.laneOffset(e)
  local x, y, z, dx, dz = ctx.roads:pointAt(e, s, side)
  for _, o in ipairs(ctx.world:near(x, z, 9, "vehicle")) do
    if math.abs((o.y or 0) - y) < 3 then return nil end
  end
  local p = ctx.player
  if (p.x - x) ^ 2 + (p.z - z) ^ 2 < 35 * 35 and (ctx.view and ctx.view.cam) then
    -- never appear in front of the player's eyes
    local cam = ctx.view.cam
    local ddx, ddz = x - cam.x, z - cam.z
    local d = math.sqrt(ddx * ddx + ddz * ddz) + 0.001
    if (ddx * math.cos(cam.yaw) + ddz * math.sin(cam.yaw)) / d > 0.3 then return nil end
  end
  local kind = cop and "cruiser" or pickKind(self)
  -- paints off the sky's slots (purple, magenta, pink, lightBlue change with the hour in the city)
  local colour = TRAFFIC_PAINTS[self.rng(#TRAFFIC_PAINTS)]
  local h = math.atan2(dz * dir, dx * dir)
  local car
  if vehicle.TYPES[kind] then
    car = vehicle.new(kind, x, z, h, (not cop) and colour or nil)
  else
    car = vehicle.new("marlin", x, z, h, colour)
    local def = ctx.vehicles.get(kind)
    car.kind, car.spec, car.health = kind, def, def.health
  end
  car.y = y
  car.v = math.min(e.speed or 10, 9) * 0.8
  local d = lane.attach(ctx.roads, x, z, h, self.rng)
  if not d then return nil end
  d.edge, d.s, d.dir = e, s, dir
  if cop then d.speedMul = 1.1 end
  car.drv = d
  local env = self.env
  local isCop = cop
  local me = self
  fleet.add(ctx, car, {
    tags = isCop and { cop = true } or { traffic = true },
    brain = function(_, c, dt)
      if isCop and me.copBrain then return me.copBrain(c, dt, env) end
      return lane.step(c.drv, c, dt, env)
    end,
    rail = function(_, c, dt)
      if not c.drv then
        -- a cruiser that was coming straight at you and has been left behind: back onto the roads
        c.drv = lane.attach(ctx.roads, c.x, c.z, c.h, me.rng)
        if not c.drv then c.lostRail = true return end
        c.drv.emergency = c.cop and c.cop.state ~= "patrol" or nil
      end
      local speed = nil
      if isCop and me.copSpeed then speed = me.copSpeed(c) end
      if not lane.rail(c.drv, c, dt, env, speed) then c.lostRail = true end
    end,
  })
  car.born = ctx.time or 0
  car.cop = isCop and { state = "patrol" } or nil
  self.cars[car] = true
  return car
end

--- A random spot on a random edge, between lo and hi units from the player.
function T:randomSpot(lo, hi, tries, connected)
  local p = self.ctx.player
  local edges = self.edges
  if not edges or #edges == 0 then return nil end
  for _ = 1, tries do
    local e = edges[self.rng(#edges)]
    local s = e.length * (0.1 + 0.8 * self.rng())
    local x, _, z = self.ctx.roads:pointAt(e, s, 0)
    local d2 = (x - p.x) ^ 2 + (z - p.z) ^ 2
    if d2 >= lo * lo and d2 <= hi * hi and (not connected or not self.comp or self.comp[e.a] == connected) then
      local dir = (e.lanes == 1 or self.rng() < 0.5) and 1 or -1
      return e, s, dir
    end
  end
  -- few roads in the band (out on the water, at the city's edge): look at every road once, from a random start, so
  -- whoever is coming still comes. Half-way along each road, the connected ones first, then any
  for pass = 1, (connected and self.comp) and 2 or 1 do
    local n = #edges
    local start = self.rng(n)
    for i = 0, n - 1 do
      local e = edges[(start + i - 1) % n + 1]
      if pass == 2 or not connected or not self.comp or self.comp[e.a] == connected then
        local s = e.length * 0.5
        local x, _, z = self.ctx.roads:pointAt(e, s, 0)
        local d2 = (x - p.x) ^ 2 + (z - p.z) ^ 2
        if d2 >= lo * lo and d2 <= hi * hi then
          return e, s, (e.lanes == 1 or self.rng() < 0.5) and 1 or -1
        end
      end
    end
  end
  return nil
end

function T:remove(car)
  self.cars[car] = nil
  fleet.remove(self.ctx, car)
end

function T:clear()
  for car in pairs(self.cars) do fleet.remove(self.ctx, car) end
  self.cars = {}
end

--- Frighten drivers near a place: they floor it for a few seconds.
function T:alarm(x, z, r)
  for car in pairs(self.cars) do
    if (car.x - x) ^ 2 + (car.z - z) ^ 2 < r * r and car.drv then car.drv.panic = 6 end
  end
end

function T:update(dt)
  local ctx = self.ctx
  local p = ctx.player
  self.env.time = ctx.time or 0
  self.env.player = p.car
  if self.dirty or not self.edges then self:refresh() end
  -- who goes
  local now = ctx.time or 0
  local limit2 = M.DESPAWN ^ 2
  for car in pairs(self.cars) do
    local gone = false
    local dx, dz = car.x - p.x, car.z - p.z
    local d2 = dx * dx + dz * dz
    if car.mode == "gone" or car.removed then
      gone = true
    elseif d2 > limit2 or car.lostRail then
      gone = true
    elseif car.wrecked then
      car.wreckT = (car.wreckT or 0) + dt
      car.parked = true
      if car.cop and car.cop.state ~= "wrecked" then car.cop.state = "wrecked" end
      if car.wreckT > 25 and d2 > 30 * 30 then gone = true end
    else
      local d = car.drv
      if d then
        if d.panic then
          d.panic = d.panic - dt
          if d.panic <= 0 then d.panic = nil end
        end
        if (d.lost or 0) > 4 then gone = true end
        -- getting nowhere: idle counts until the car is IDLE_GO units from where it last was, so backing and filling in
        -- a jam (a moment of speed, then stopped again) still counts. Wedged long enough, it is put away (traffic
        -- refills the street): sooner out of your close view, later in it; a cruiser on your case is left alone
        local a = car.anchor
        if not a or (car.x - a.x) ^ 2 + (car.z - a.z) ^ 2 > M.IDLE_GO * M.IDLE_GO then
          car.anchor = { x = car.x, z = car.z }
          car.idle = 0
        else
          car.idle = (car.idle or 0) + dt
        end
        local chasing = car.cop and car.cop.state ~= "patrol"
        if not chasing and not car.parked and (car.idle > M.IDLE_MAX or (car.idle > M.IDLE_OUT_OF_VIEW and d2 > 30 * 30)) then gone = true end
      end
    end
    if gone then self:remove(car) end
  end
  -- who comes
  local want = self:target()
  local have = self:count()
  if have < want then
    local burst = self.filled and 1 or math.min(want - have, 12)
    for _ = 1, burst do
      local lo, hi = M.SPAWN_MIN, M.SPAWN_MAX
      if not self.filled then lo, hi = 30, M.SPAWN_MAX end
      local e, s, dir = self:randomSpot(lo, hi, 8)
      if e then self:spawnOn(e, s, dir, self.rng() < 0.07 and (ctx.heat == nil or ctx.heat.level == 0)) end
    end
    if not self.filled and have + burst >= want then self.filled = true end
  elseif have > want + 3 then
    -- fewer wanted (a quieter district, or the budget cut back): put away the furthest one out of sight
    local worst, wd = nil, 0
    for car in pairs(self.cars) do
      local d2 = (car.x - p.x) ^ 2 + (car.z - p.z) ^ 2
      if d2 > wd and d2 > 90 * 90 and not (car.cop and car.cop.state ~= "patrol") then worst, wd = car, d2 end
    end
    if worst then self:remove(worst) end
  end
  fleet.update(ctx, dt)
  local _ = now
end

return M
