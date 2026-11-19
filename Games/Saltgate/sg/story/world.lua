-- story/world.lua
-- The story's window on the game. The host (sg/story/host.lua) and the kit (sg/story/kit.lua) only ever call these
-- methods, so a test can stand in a made-up world (Tests/saltgate_d_sim.lua) and the game gets this one, built on the
-- core's context: the player, the cars, the entity world, the stream, the road graph and the event bus.
--
-- The adapter (every method; `a` is an actor this adapter made):
--   player() -> { x, y, z, car (a vehicle or nil), down (false | "nabbed" | "ko") }
--   place(name) -> { x, z, r, y? }        pos(target) -> x, z     target: "player", a place, an actor, { x, z }
--   distTo(target) -> how far the player is from it
--   inPlace(name, { car, actor, radius, speed }) -> are you there (in a car if car, in that car if actor, slower than speed)
--   spawn(kind, at, opts) -> actor        kinds: car, runner (a car with a route), crew (people to knock down)
--   state(a) -> ok | arrived | down | wrecked | caught | escaped | gone      health(a) -> 0..1
--   inCar(a)   route(a, dest)   remaining(group) -> how many of the group are still up
--   heat() -> level     setHeat(n [, force])    n stars at least (force: exactly)
--   pay(n)      flight() -> { landed, distance } | nil      clearFlight()
--   restore({ at, give = { name, kind } }) -> the car given     put the player back for a checkpoint
--   cleanup()   remove everything the story made          suspend() / resume()   (resume also clears the player's `down`)
--   camAt(spec) -> x, y, z      update(dt)      once a frame
--
-- What it needs of the rest of the game (all optional: without them the mission still plays, with less):
--   ctx.places[name]            the real places from the world builder; content/story/places.lua is the fallback
--   ctx.spawnVehicle(kind, x, z, h) -> a vehicle      (default: sg/vehicle.lua)
--   ctx.heat { level, set(n) }  (default: tracks heat_changed and raises `crime` events)
--   people knocked down: any system that sets entity.down = true (or takes health to 0) on an entity tagged `mission`
--   cars driven along a route use core/follow (car.follow), which the game loop already steps

local followLib = require("sg.core.follow")
local vehicle = require("sg.vehicle")

local M = {}
local W = {}
W.__index = W

local sqrt, atan2 = math.sqrt, math.atan2 or math.atan

M.OWNER = "d_story"

--- places: the fallback table from content (name -> { x, z, r, label }).
function M.new(ctx, places)
  local w = setmetatable({
    ctx = ctx, fallback = places or {}, cars = {}, people = {}, runners = {}, down = false, level = 0, flightInfo = nil,
    airFrom = nil, suspended = false,
  }, W)
  if ctx.bus then
    ctx.bus:on("player_down", function(d) w.down = d.kind or "ko" end, "d_story")
    ctx.bus:on("heat_changed", function(d) w.level = d.level or 0 end, "d_story")
  end
  return w
end

local function dist(ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  return sqrt(dx * dx + dz * dz)
end

function W:place(name)
  local ctx = self.ctx
  local p = ctx.places and ctx.places[name]
  if p then return p end
  return self.fallback[name]
end

function W:ground(x, z, y)
  local s = self.ctx.stream
  if s and s.groundAt then
    local ok, gy = pcall(s.groundAt, s, x, z, y)
    if ok and gy then return gy end
  end
  return y or 0
end

function W:player()
  local p = self.ctx.player
  local car = p.car
  local ref = car or p
  return { x = ref.x, y = ref.y or 0, z = ref.z, car = car, down = self.down }
end

function W:pos(target)
  if target == "player" then
    local p = self:player()
    return p.x, p.z
  end
  if type(target) == "string" then
    local pl = self:place(target)
    if pl then return pl.x, pl.z end
    return nil
  end
  if type(target) == "table" then
    if target.d_group then
      return target.x, target.z
    end
    return target.x or target[1], target.z or target[2]
  end
end

function W:distTo(target)
  local x, z = self:pos(target)
  if not x then return 9999 end
  local p = self:player()
  return dist(p.x, p.z, x, z)
end

function W:speed()
  local p = self:player()
  return p.car and math.abs(p.car.v or 0) or 0
end

function W:inPlace(name, opts)
  local pl = self:place(name)
  if not pl then return false end
  local p = self:player()
  if dist(p.x, p.z, pl.x, pl.z) > (pl.r or 5) + (opts.radius or 0) then return false end
  if pl.y and math.abs((p.y or 0) - pl.y) > 4.5 then return false end -- a deck above or below does not count
  if opts.car and not p.car then return false end
  if opts.actor and p.car ~= opts.actor then return false end
  if opts.speed and p.car and math.abs(p.car.v or 0) > opts.speed then return false end
  return true
end

function W:inCar(a) return self.ctx.player.car == a end

-- ---------------------------------------------------------------- making things

local function headingAt(self, x, z)
  local roads = self.ctx.roads
  if roads then
    local e, _, _, _, _, _, dx, dz = roads:nearest(x, z, 30)
    if e and dx then return atan2(dz, dx) end
  end
  return 0
end

local function newCar(self, kind, x, z, h, colour)
  local ctx = self.ctx
  local car
  if ctx.spawnVehicle then
    car = ctx.spawnVehicle(kind, x, z, h, colour)
  end
  if not car then
    if not vehicle.TYPES[kind] then kind = "marlin" end
    car = vehicle.new(kind, x, z, h, colour)
  end
  car.y = self:ground(x, z, nil)
  car.mission = true
  car.owner = M.OWNER
  ctx.cars[#ctx.cars + 1] = car
  self.cars[#self.cars + 1] = car
  return car
end

local function nodeNear(roads, x, z)
  local e, s = roads:nearest(x, z, 60)
  if not e then return nil end
  local nodeId = (s < e.length / 2) and e.a or e.b
  return nodeId, e
end

--- The loaded road node nearest a point (the road graph holds only the chunks round the player).
local function nearestLoadedNode(roads, x, z)
  local best, bd
  for id, n in pairs(roads.nodes or {}) do
    if n.x and n.defined then
      local d = (n.x - x) ^ 2 + (n.z - z) ^ 2
      if not bd or d < bd then best, bd = id, d end
    end
  end
  return best
end

--- Plan a runner's way along the road graph from where it is to the last place of its route. The graph holds only
-- the chunks loaded round the player: when a place is past them, the plan goes as far toward it as the loaded roads
-- reach (f.partial) and the runner plans again as more of the city loads (see W:update). Without that a runner whose
-- goal was past the loaded roads had no route and wandered at random (Pit Wall's courier circled the counting house).
local function plan(self, car, route)
  local roads = self.ctx.roads
  if not roads then return nil end
  local f = followLib.new(roads, car.x, car.z, nil)
  if not f then return nil end
  local list = {}
  local fromId = (f.dir == 1) and f.edge.b or f.edge.a
  for _, name in ipairs(route) do
    local pl = self:place(name)
    if pl and fromId then
      local toId = nodeNear(roads, pl.x, pl.z)
      local edges
      if toId then
        local _, e = roads:path(fromId, toId)
        edges = e
      end
      if edges then
        for _, e in ipairs(edges) do list[#list + 1] = e end
        fromId = toId
      else
        -- past the loaded roads: as near as they go, and plan again later
        local near = nearestLoadedNode(roads, pl.x, pl.z)
        if near and near ~= fromId then
          local _, e = roads:path(fromId, near)
          if e then for _, ed in ipairs(e) do list[#list + 1] = ed end end
        end
        f.partial = true
        break
      end
    end
  end
  f.route = list
  return f
end
M.REPLAN_SECONDS = 3

function W:spawn(kind, at, opts)
  local x, z = self:pos(at or "player")
  if not x then return nil end
  if kind == "car" or kind == "runner" or kind == "boat" then
    local h = opts.heading or headingAt(self, x, z)
    local car = newCar(self, opts.vehicle or "marlin", x, z, h, opts.paint)
    if kind == "runner" then
      car.d_run = { route = opts.route or {}, flees = opts.flees, t = 0, still = 0, state = "ok" }
      car.follow = plan(self, car, car.d_run.route)
      if car.follow then
        car.v = 6
        self.runners[#self.runners + 1] = car
      else
        car.d_run.state = "ok"
        self.runners[#self.runners + 1] = car
      end
    end
    return car
  end
  -- people: crew, thugs, guards
  local n = opts.count or 3
  local first
  for i = 1, n do
    local a = (i / n) * 6.2832
    local e = {
      kind = "ped", look = opts.look or "thug", x = x + math.cos(a) * 3, z = z + math.sin(a) * 3, h = a + 3.14, radius = 0.5,
      health = opts.health or 3, down = false, d_group = opts.group or "crew", tags = { mission = true, enemy = true },
    }
    e.y = self:ground(e.x, e.z, nil)
    if self.ctx.world and self.ctx.world.add then
      local ok, added = pcall(self.ctx.world.add, self.ctx.world, e)
      if ok and added then e = added end
    end
    self.people[#self.people + 1] = e
    first = first or e
  end
  return first
end

function W:remove(a)
  for i, c in ipairs(self.cars) do
    if c == a then table.remove(self.cars, i) break end
  end
  local cars = self.ctx.cars
  for i, c in ipairs(cars) do
    if c == a then table.remove(cars, i) break end
  end
end

function W:cleanup()
  local ctx = self.ctx
  local player = ctx.player
  for i = #self.cars, 1, -1 do
    local c = self.cars[i]
    if player.car == c then
      player.car = nil
      player.x, player.z, player.y = c.x, c.z, c.y
    end
    for j = #ctx.cars, 1, -1 do
      if ctx.cars[j] == c then table.remove(ctx.cars, j) end
    end
  end
  self.cars, self.runners = {}, {}
  for _, e in ipairs(self.people) do
    if ctx.world and ctx.world.remove and e.id then pcall(ctx.world.remove, ctx.world, e) end
  end
  self.people = {}
  self.flightInfo = nil
end

-- ---------------------------------------------------------------- what things are doing

function W:state(a)
  if a == nil then return "gone" end
  if a.d_group then
    if a.down or (a.health or 1) <= 0 then return "down" end
    return "ok"
  end
  local found = false
  for _, c in ipairs(self.ctx.cars) do
    if c == a then found = true break end
  end
  if not found then return "gone" end
  if a.wrecked then return "wrecked" end
  local r = a.d_run
  if r and r.state ~= "ok" then return r.state end
  return "ok"
end

function W:health(a)
  if a.spec then return (a.health or 0) / a.spec.health end
  return (a.health or 0) / 3
end

function W:route(a, dest)
  if not a.d_run then
    a.d_run = { route = {}, t = 0, still = 0, state = "ok" }
    self.runners[#self.runners + 1] = a
  end
  a.d_run.route = type(dest) == "table" and dest or { dest }
  a.follow = plan(self, a, a.d_run.route)
end

function W:remaining(group)
  local n = 0
  for _, e in ipairs(self.people) do
    if e.d_group == group and not (e.down or (e.health or 1) <= 0) then n = n + 1 end
  end
  return n
end

function W:heat()
  local h = self.ctx.heat
  if type(h) == "table" and type(h.level) == "number" then return h.level end
  return self.level
end

function W:setHeat(n, force)
  local ctx = self.ctx
  local h = ctx.heat
  local now = self:heat()
  if type(h) == "table" and type(h.set) == "function" then
    if force or n > now then h:set(n) end
    return
  end
  if force then
    if n < now and ctx.bus then ctx.bus:emit("heat_changed", { level = n, previous = now }) end
    self.level = n
    return
  end
  if n > now and ctx.bus then ctx.bus:emit("crime", { kind = "story", level = n - now }) end
end

function W:pay(n)
  local ctx = self.ctx
  local pl = ctx.save and ctx.save.player
  if not pl then return end
  pl.money = (pl.money or 0) + n
  if ctx.bus then ctx.bus:emit("money", { amount = n, reason = "story", total = pl.money }) end
end

function W:flight() return self.flightInfo end
function W:clearFlight() self.flightInfo = nil end

function W:suspend() self.suspended = true end
function W:resume()
  self.suspended = false
  self.down = false
end

function W:restore(opts)
  local ctx = self.ctx
  local p = ctx.player
  local pl = opts.at and self:place(opts.at)
  if pl then
    p.car = nil
    p.x, p.z, p.v = pl.x, pl.z, 0
    p.y = pl.y or self:ground(pl.x, pl.z, nil)
    p.h = headingAt(self, pl.x, pl.z)
  end
  self.down = false
  if opts.give then
    local x, z = p.x, p.z
    local car = newCar(self, opts.give.kind, x, z, p.h or 0)
    car.v = 0
    p.car = car
    car.follow = nil
    return car
  end
end

function W:camAt(spec)
  local x, z = self:pos(spec)
  if not x then return nil end
  local y = type(spec) == "table" and spec.y or self:ground(x, z, nil)
  if type(spec) == "string" and spec ~= "player" then
    local pl = self:place(spec)
    if pl and pl.y then y = pl.y end
  end
  return x, y, z
end

-- ---------------------------------------------------------------- each frame

function W:update(dt)
  local ctx = self.ctx
  local p = self:player()
  -- runners: arrived, caught, escaped
  for _, c in ipairs(self.runners) do
    local r = c.d_run
    if r and r.state == "ok" then
      r.t = r.t + dt
      -- a plan that stopped at the edge of the loaded roads is made again when it runs out (more of the city has loaded)
      local f = c.follow
      if f and (not f.route or #f.route == 0) and #r.route > 0 then
        r.replan = (r.replan or M.REPLAN_SECONDS) - dt
        if r.replan <= 0 then
          r.replan = M.REPLAN_SECONDS
          local again = plan(self, c, r.route)
          if again and #again.route > 0 then c.follow = again end
        end
      end
      local last = r.route[#r.route] and self:place(r.route[#r.route])
      -- arrived: at the place, or as near as the roads go (a door on a plaza is off the road: the Gilt Tower's is 17
      -- units from the ring road, and the courier went round the ring for ever)
      local reach = last and ((last.r or 6) + 3) or 0
      if last and ctx.roads then
        if not r.offRoad then
          -- how far the place is from the road node a plan ends at (see plan: nodeNear)
          local id = nodeNear(ctx.roads, last.x, last.z)
          local n = id and ctx.roads:node(id)
          r.offRoad = (n and n.x) and dist(n.x, n.z, last.x, last.z) or false
        end
        if r.offRoad then reach = math.max(reach, r.offRoad + 6) end
      end
      if last and dist(c.x, c.z, last.x, last.z) < reach and r.t > 2 then
        r.state = "arrived"
        c.follow = nil
      elseif r.flees then
        local frac = (c.health or 0) / c.spec.health
        if math.abs(c.v or 0) < 2.5 and dist(c.x, c.z, p.x, p.z) < 16 and r.t > 3 then
          r.still = r.still + dt
        else
          r.still = 0
        end
        if frac < 0.4 or r.still > 1.4 then
          r.state = "caught"
          c.follow = nil
          c.v = 0
        end
      end
      if r.state == "ok" and dist(c.x, c.z, p.x, p.z) > 320 then
        r.state = "escaped"
        c.follow = nil
      end
    end
  end
  -- people with no combat system: a car at speed, or a punch, knocks them down
  if not ctx.combat then
    local ref = ctx.player.car or ctx.player
    local fast = ctx.player.car and math.abs(ctx.player.car.v or 0) > 6
    for _, e in ipairs(self.people) do
      if not e.down and dist(e.x, e.z, ref.x, ref.z) < 2.4 and (fast or self.punch) then
        e.down = true
        e.health = 0
      end
    end
  end
  self.punch = false
  -- jumps: leaving the ground in a car and landing again
  local car = ctx.player.car
  if car then
    if car.airborne and not self.airFrom then
      self.airFrom = { x = car.x, z = car.z, y = car.y }
    elseif not car.airborne and self.airFrom then
      local from = self.airFrom
      self.airFrom = nil
      local landedOn = self:ground(car.x, car.z, car.y)
      local s = ctx.stream
      local water = s and s.waterAt and s:waterAt(car.x, car.z)
      local landed = not (water and landedOn <= water + 0.3) and not car.wrecked
      self.flightInfo = { landed = landed, distance = dist(from.x, from.z, car.x, car.z) }
      if ctx.bus then ctx.bus:emit("jump", { id = "story", distance = self.flightInfo.distance, landed = landed }) end
    end
  else
    self.airFrom = nil
  end
end

return M
