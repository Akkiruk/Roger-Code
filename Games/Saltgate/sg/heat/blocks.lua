-- heat/blocks.lua
-- Roadblocks and spike strips. A roadblock is put on the road ahead of you: from the road you are on, the Patrol walks
-- the graph forward along your heading (taking the straightest exit at each junction) to a spot 105 to 150 units on,
-- and puts two or three cruisers across the road there with officers standing behind them. From level 4 a spike strip
-- lies on the approach, covering most of the road with a gap on one side. Cruisers on the way there plan round the edge
-- (their A* takes a price for crossing it). Blocks are put away when you are past them or far off. Hit a strip and the
-- tyres go: top speed halves and the car wobbles until the heat is off.
--
--   local B = blocks.new(ctx, peds)
--   B:update(dt, wanted, avoid)      avoid: a table cruisers' A* reads; it is filled with the blocked edge ids
--   B:clear()    B:list()
--   blocks.ahead(roads, x, z, h, distance, rng) -> edge, s, dir, x, z | nil   (the walk, exposed for tests)
--   blocks.limp(ctx, dt)  blocks.mend(ctx)                                    (burst tyres)

local lane = require("sg.ai.lane")
local fleet = require("sg.ai.fleet")
local vehicle = require("sg.vehicle")
local wantedLib = require("sg.heat.wanted")
local util = require("sg.util")

local M = {}
local B = {}
B.__index = B

local cos, sin, abs, min = math.cos, math.sin, math.abs, math.min
local atan2 = math.atan2 or math.atan

M.MIN_DISTANCE = 75
M.GAP = 70 -- blocks keep this far from each other

function M.new(ctx, peds, seed)
  return setmetatable({ ctx = ctx, peds = peds, rng = util.rng(seed or 71), blocks = {}, cool = 3, nextId = 0 }, B)
end

--- Walk the graph forward from the road nearest (x, z) along heading h for distance units, straight on at junctions.
function M.ahead(roads, x, z, h, distance, rng)
  local e, s, _, _, _, _, tx, tz = roads:nearest(x, z, 14, lane.DRIVABLE)
  if not e then return nil end
  local dir = (tx * cos(h) + tz * sin(h)) >= 0 and 1 or -1
  if e.lanes == 1 then dir = 1 end
  local cur, pos, remain = e, s, distance
  for _ = 1, 10 do
    local rest = dir == 1 and (cur.length - pos) or pos
    if remain <= rest then
      local at = pos + dir * remain
      -- not in a junction: keep 14 units from the ends when the edge is long enough
      if cur.length > 32 then at = util.clamp(at, 14, cur.length - 14) else at = cur.length / 2 end
      local px, _, pz = roads:pointAt(cur, at, 0)
      return cur, at, dir, px, pz
    end
    remain = remain - rest
    local node = dir == 1 and cur.b or cur.a
    local _, _, _, dx, dz = roads:pointAt(cur, dir == 1 and cur.length or 0, 0)
    dx, dz = dx * dir, dz * dir
    local best, bestDot = nil, -2
    for _, nx in ipairs(roads:exits(node, cur)) do
      if lane.DRIVABLE[nx.kind] and nx ~= cur then
        local ndir = (nx.a == node) and 1 or -1
        local _, _, _, ex, ez = roads:pointAt(nx, ndir == 1 and 0 or nx.length, 0)
        local dot = ex * ndir * dx + ez * ndir * dz + (rng and rng() * 0.05 or 0)
        if dot > bestDot then best, bestDot = nx, dot end
      end
    end
    if not best then return nil end
    cur, dir = best, (best.a == node) and 1 or -1
    pos = dir == 1 and 0 or best.length
  end
  return nil
end

function B:list() return self.blocks end

local function removeBlock(self, b)
  local ctx = self.ctx
  for _, car in ipairs(b.cars) do fleet.remove(ctx, car) end
  for _, o in ipairs(b.officers) do
    if not o.removed then self.peds:remove(o) end
  end
  if b.strip then ctx.world:remove(b.strip) end
  for i, x in ipairs(self.blocks) do
    if x == b then table.remove(self.blocks, i) break end
  end
end

function B:clear()
  for i = #self.blocks, 1, -1 do removeBlock(self, self.blocks[i]) end
end

--- Build a roadblock on edge e at s, for a target coming along it in direction dir.
function B:build(e, s, dir, plan)
  local ctx = self.ctx
  local px, py, pz, dx, dz = ctx.roads:pointAt(e, s, 0)
  dx, dz = dx * dir, dz * dir -- the way the target is travelling
  local th = atan2(dz, dx)
  local w = e.width
  self.nextId = self.nextId + 1
  local b = { id = self.nextId, edge = e, s = s, dir = dir, x = px, y = py, z = pz, h = th, w = w, cars = {}, officers = {}, born = ctx.time or 0 }
  -- cruisers across the road: left and right (and a middle one on a wide road), nose in, a little askew
  local slots = { -0.26, 0.26 }
  if w > 9.5 then slots = { -0.33, 0, 0.33 } end
  for i, k in ipairs(slots) do
    local lat = k * w
    local cx, cz = px - dz * lat, pz + dx * lat -- lat is to the right of the way the target is going
    local a = th + ((i % 2 == 0) and -1 or 1) * (math.pi / 2 - 0.25) + (self.rng() - 0.5) * 0.2
    local car = vehicle.new("cruiser", cx, cz, a)
    car.y = py
    car.v = 0
    car.roadblock = b
    fleet.add(ctx, car, { tags = { blockcar = true }, parked = true })
    b.cars[#b.cars + 1] = car
  end
  -- officers behind the cars, further along the target's way
  for k = -1, 1, 2 do
    local ox, oz = px + dx * 4.5 - dz * (k * w * 0.18), pz + dz * 4.5 + dx * (k * w * 0.18)
    local o = self.peds:spawnOfficer(ox, oz, th + math.pi, py)
    o.keep = true
    b.officers[#b.officers + 1] = o
  end
  -- a spike strip on the approach, covering most of the road, a gap on one side
  if plan.spikes then
    local sw = w * 0.72
    local gapSide = self.rng() < 0.5 and 1 or -1
    local lat = -gapSide * (w - sw) / 2
    local sx, sz = px - dx * 9 - dz * lat, pz - dz * 9 + dx * lat
    local sy = ctx.stream:groundAt(sx, sz, py + 1) or py
    b.strip = ctx.world:add({ kind = "spikes", tags = { spikes = true }, x = sx, y = sy, z = sz, h = th, w = sw, radius = 1 })
  end
  self.blocks[#self.blocks + 1] = b
  return b
end

--- Try to put a roadblock ahead of the target. Returns it, or nil.
function B:place(tgt, plan)
  local ctx = self.ctx
  local speed = tgt.v or 0
  if abs(speed) < 5 then return nil end
  local e, s, dir = M.ahead(ctx.roads, tgt.x, tgt.z, (speed >= 0) and tgt.h or tgt.h + math.pi, 105 + self.rng() * 45, self.rng)
  if not e then return nil end
  local px, _, pz = ctx.roads:pointAt(e, s, 0)
  local d2 = (px - tgt.x) ^ 2 + (pz - tgt.z) ^ 2
  if d2 < M.MIN_DISTANCE ^ 2 or d2 > 170 ^ 2 then return nil end
  for _, b in ipairs(self.blocks) do
    if (b.x - px) ^ 2 + (b.z - pz) ^ 2 < M.GAP ^ 2 then return nil end
  end
  return self:build(e, s, dir, plan)
end

--- Pop the tyres of whoever drives over a strip.
local function strips(self, dt)
  local ctx = self.ctx
  for _, b in ipairs(self.blocks) do
    local st = b.strip
    if st then
      local tx, tz = cos(st.h), sin(st.h)
      for _, car in ipairs(ctx.cars) do
        if not car.flat and not car.fleet then
          local dx, dz = car.x - st.x, car.z - st.z
          if dx * dx + dz * dz < 144 then
            local along = dx * tx + dz * tz
            local lat = -dx * tz + dz * tx
            if abs(along) < 1.2 + abs(car.v or 0) * dt and abs(lat) < st.w / 2 + 0.8 and abs((car.y or 0) - st.y) < 2.5 then
              car.flat, car.flatT = true, 0
              if car == ctx.player.car then ctx.bus:emit("player_hurt", { amount = 0, by = "spikes" }) end
            end
          end
        end
      end
    end
  end
end

--- Cars with burst tyres: slow, wobbling.
function M.limp(ctx, dt)
  for _, car in ipairs(ctx.cars) do
    if car.flat then
      car.flatT = (car.flatT or 0) + dt
      local cap = car.spec.top * 0.42
      if car.v > cap then car.v = car.v - (car.v - cap) * min(1, dt * 3) end
      car.h = util.wrap(car.h + sin(car.flatT * 9) * 0.012 * min(1, abs(car.v) / 8))
    end
  end
end

function M.mend(ctx)
  for _, car in ipairs(ctx.cars) do car.flat, car.flatT = nil, nil end
end

function B:update(dt, w, avoid)
  local ctx = self.ctx
  local plan = wantedLib.plan(w.level)
  local tgt = ctx.player.car or ctx.player
  for k in pairs(avoid) do avoid[k] = nil end
  -- put away: left behind, far off, or more than the level asks for
  for i = #self.blocks, 1, -1 do
    local b = self.blocks[i]
    local d2 = (b.x - tgt.x) ^ 2 + (b.z - tgt.z) ^ 2
    if d2 < 60 * 60 then b.near = true end
    local past = (b.near and d2 > 90 * 90) or false
    if w.level == 0 or d2 > 200 * 200 or past or #self.blocks > plan.blocks or ctx.roads:edge(b.edge.id) ~= b.edge then
      removeBlock(self, b)
    else
      avoid[b.edge.id] = true
    end
  end
  if w.level > 0 and plan.blocks > #self.blocks then
    self.cool = self.cool - dt
    if self.cool <= 0 then
      self.cool = 5
      local b = self:place(tgt, plan)
      if b then avoid[b.edge.id] = true end
    end
  end
  strips(self, dt)
  M.limp(ctx, dt)
end

return M
