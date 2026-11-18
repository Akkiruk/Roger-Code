-- heat/air.lua
-- The Harbor Patrol's helicopter and patrol boat. The helicopter (level 5 and 6) flies in high, circles you while you
-- are seen and sweeps its searchlight over the search circle while you are not; a roof, a bridge or a tunnel over you hides
-- you from it. The boat (level 4 up) keeps to deep water near you, runs along the shore beside where you are and sees you
-- across the water. Both are entities (tags heli, boat) moved here with no physics; scene layers in the police plugin
-- draw them. Pure but for the context.
--
--   local A = air.new(ctx)
--   A:update(dt, wanted) -> seen (the helicopter's light is on you, or the boat has a line to you)
--   A:clear()    A.heli    A.boat    A.spot {x, z, y} where the searchlight lands (or nil)
--   air.deep(stream, x, z) -> bool   is there deep water here

local los = require("sg.heat.los")
local wantedLib = require("sg.heat.wanted")
local util = require("sg.util")

local M = {}
local A = {}
A.__index = A

local cos, sin, sqrt, abs, min, max = math.cos, math.sin, math.sqrt, math.abs, math.min, math.max
local atan2 = math.atan2 or math.atan

M.ALTITUDE = 22
M.HELI_SPEED = 30
M.BOAT_SPEED = 15

function M.new(ctx, seed)
  return setmetatable({ ctx = ctx, rng = util.rng(seed or 29), t = 0, orbit = 0, boatT = 0 }, A)
end

function M.deep(stream, x, z)
  local level = stream:waterAt(x, z)
  if not level then return false end
  local gy = stream:groundAt(x, z, level + 5)
  return gy ~= nil and gy < level - 1.5
end

function A:clear()
  local world = self.ctx.world
  if self.heli then world:remove(self.heli) end
  if self.boat then world:remove(self.boat) end
  self.heli, self.boat, self.spot = nil, nil, nil
end

-- ---------------------------------------------------------------- the helicopter

local function spawnHeli(self, tgt)
  local a = self.rng() * math.pi * 2
  local x, z = tgt.x + cos(a) * 170, tgt.z + sin(a) * 170
  self.heli = self.ctx.world:add({
    kind = "heli", tags = { heli = true, air = true }, x = x, z = z, y = (tgt.y or 0) + M.ALTITUDE + 10, h = a + math.pi,
    vx = 0, vz = 0, spin = 0, radius = 3, ground = tgt.y or 0,
  })
  self.spot = nil
end

local function updateHeli(self, dt, w, tgt, want)
  local ctx = self.ctx
  local hel = self.heli
  if not hel then
    if want then spawnHeli(self, tgt) end
    return false
  end
  if not want then
    -- stand down: climb away, gone when far
    hel.y = hel.y + 6 * dt
    hel.vx, hel.vz = hel.vx + cos(hel.h) * 20 * dt, hel.vz + sin(hel.h) * 20 * dt
    ctx.world:move(hel, hel.x + hel.vx * dt, hel.z + hel.vz * dt)
    hel.spin = hel.spin + dt * 20
    self.spot = nil
    if (hel.x - tgt.x) ^ 2 + (hel.z - tgt.z) ^ 2 > 230 ^ 2 or hel.y > (hel.ground or 0) + 70 then
      ctx.world:remove(hel)
      self.heli = nil
    end
    return false
  end
  -- where to be: circling you while you are seen, over the search circle's middle otherwise
  local cx, cz
  if w.seen then
    self.orbit = self.orbit + dt * 0.5
    cx, cz = tgt.x + (tgt.v or 0) * cos(tgt.h or 0) * 0.5 + cos(self.orbit) * 15, tgt.z + (tgt.v or 0) * sin(tgt.h or 0) * 0.5 + sin(self.orbit) * 15
  else
    self.orbit = self.orbit + dt * 0.3
    cx, cz = w.cx + cos(self.orbit) * w.radius * 0.5, w.cz + sin(self.orbit) * w.radius * 0.5
  end
  local dx, dz = cx - hel.x, cz - hel.z
  local d = sqrt(dx * dx + dz * dz)
  local sp = min(M.HELI_SPEED, d * 1.3)
  local vx, vz = dx / max(d, 0.1) * sp, dz / max(d, 0.1) * sp
  local k = min(1, dt * 1.6)
  hel.vx, hel.vz = hel.vx + (vx - hel.vx) * k, hel.vz + (vz - hel.vz) * k
  ctx.world:move(hel, hel.x + hel.vx * dt, hel.z + hel.vz * dt)
  local speed = sqrt(hel.vx ^ 2 + hel.vz ^ 2)
  -- it faces its way of travel, and the light when it is nearly still
  local fh = speed > 3 and atan2(hel.vz, hel.vx) or atan2(tgt.z - hel.z, tgt.x - hel.x)
  hel.h = util.turnToward(hel.h, fh, 2.2 * dt)
  hel.spin = hel.spin + dt * 22
  -- stay above the ground under it
  self.altT = (self.altT or 0) - dt
  if self.altT <= 0 then
    self.altT = 0.5
    local gy = ctx.stream:groundAt(hel.x, hel.z, (tgt.y or 0) + 80) or (tgt.y or 0)
    hel.ground = max(gy, tgt.y or 0)
  end
  hel.y = hel.y + ((hel.ground + M.ALTITUDE) - hel.y) * min(1, dt * 0.8)
  -- the searchlight
  local covered = los.covered(ctx.stream, tgt.x, tgt.y or 0, tgt.z)
  local near = (tgt.x - hel.x) ^ 2 + (tgt.z - hel.z) ^ 2 < 80 * 80
  local sx, sz
  if near and not covered and (w.seen or (tgt.x - w.cx) ^ 2 + (tgt.z - w.cz) ^ 2 < (w.radius + 12) ^ 2) then
    sx, sz = tgt.x, tgt.z
  else
    self.sweep = (self.sweep or 0) + dt
    local r = max(10, w.radius * 0.6)
    sx, sz = w.cx + cos(self.sweep * 0.7) * r, w.cz + sin(self.sweep * 0.53) * r
  end
  local spot = self.spot
  if not spot then
    spot = { x = hel.x, z = hel.z, y = 0 }
    self.spot = spot
  end
  local lag = min(1, dt * 3.2)
  spot.x, spot.z = spot.x + (sx - spot.x) * lag, spot.z + (sz - spot.z) * lag
  spot.y = (ctx.stream:groundAt(spot.x, spot.z, (hel.ground or 0) + 6) or 0) + 0.15
  local on = (spot.x - tgt.x) ^ 2 + (spot.z - tgt.z) ^ 2 < 8 * 8 and not covered
  local overhead = (tgt.x - hel.x) ^ 2 + (tgt.z - hel.z) ^ 2 < 38 * 38 and not covered
  return on or overhead
end

-- ---------------------------------------------------------------- the boat

--- The nearest deep water to (x, z) within reach, by sampling rings round it.
local function deepNear(self, x, z)
  local best, bd = nil, 1e9
  for r = 12, 120, 12 do
    for k = 0, 11 do
      local a = k / 12 * math.pi * 2 + r * 0.1
      local px, pz = x + cos(a) * r, z + sin(a) * r
      if M.deep(self.ctx.stream, px, pz) then
        if r < bd then best, bd = { x = px, z = pz }, r end
      end
    end
    if best then return best end
  end
  return nil
end

local function updateBoat(self, dt, w, tgt, want)
  local ctx = self.ctx
  local boat = self.boat
  if not boat then
    if not want then return false end
    self.boatT = self.boatT - dt
    if self.boatT > 0 then return false end
    self.boatT = 2
    local spot = deepNear(self, tgt.x, tgt.z)
    if spot then
      -- born a way off along the water
      local a = self.rng() * math.pi * 2
      local x, z = spot.x + cos(a) * 30, spot.z + sin(a) * 30
      if not M.deep(ctx.stream, x, z) then x, z = spot.x, spot.z end
      self.boat = ctx.world:add({ kind = "boat", tags = { boat = true }, x = x, z = z, y = 0, h = a, radius = 2.5, v = 0, goal = spot, goalT = 0 })
    end
    return false
  end
  if not want then
    self.boatT = self.boatT + dt
    if self.boatT > 8 or (boat.x - tgt.x) ^ 2 + (boat.z - tgt.z) ^ 2 > 220 ^ 2 then
      ctx.world:remove(boat)
      self.boat, self.boatT = nil, 0
    end
    boat.v = max(0, boat.v - 6 * dt)
    ctx.world:move(boat, boat.x + cos(boat.h) * boat.v * dt, boat.z + sin(boat.h) * boat.v * dt)
    return false
  end
  boat.goalT = boat.goalT - dt
  if boat.goalT <= 0 then
    boat.goalT = 1.5
    boat.goal = deepNear(self, tgt.x, tgt.z) or boat.goal
  end
  local g = boat.goal
  local want_h = atan2(g.z - boat.z, g.x - boat.x)
  local dist = sqrt((g.x - boat.x) ^ 2 + (g.z - boat.z) ^ 2)
  local speed = min(M.BOAT_SPEED, dist * 0.8 + 2)
  -- feelers: no shallows ahead
  local h = util.turnToward(boat.h, want_h, 1.6 * dt)
  for i = 0, 6 do
    local try = h + ((i % 2 == 0) and 1 or -1) * math.ceil(i / 2) * 0.45
    if M.deep(ctx.stream, boat.x + cos(try) * 9, boat.z + sin(try) * 9) then
      h = try
      if i > 0 then speed = speed * 0.6 end
      break
    elseif i == 6 then
      speed = 0
    end
  end
  boat.h = util.turnToward(boat.h, h, 2.4 * dt)
  boat.v = util.approach(boat.v, speed, 8 * dt)
  local nx, nz = boat.x + cos(boat.h) * boat.v * dt, boat.z + sin(boat.h) * boat.v * dt
  if M.deep(ctx.stream, nx, nz) then ctx.world:move(boat, nx, nz) else boat.v = 0 end
  boat.y = (ctx.stream:waterAt(boat.x, boat.z) or 0) + 0.1 + 0.08 * sin(self.t * 2.3)
  -- it sees you across the water
  local d2 = (tgt.x - boat.x) ^ 2 + (tgt.z - boat.z) ^ 2
  if d2 < 58 * 58 then
    boat.losT = (boat.losT or 0) - dt
    if boat.losT <= 0 then
      boat.losT = 0.35
      boat.sees = los.clear(ctx.stream, boat.x, boat.y + 2, boat.z, tgt.x, (tgt.y or 0) + 1, tgt.z, 5)
    end
    return boat.sees
  end
  boat.sees = false
  return false
end

function A:update(dt, w)
  local ctx = self.ctx
  self.t = self.t + dt
  local plan = wantedLib.plan(w.level)
  local tgt = ctx.player.car or ctx.player
  local seenH = updateHeli(self, dt, w, tgt, plan.heli)
  local seenB = updateBoat(self, dt, w, tgt, plan.boat)
  return seenH or seenB
end

return M
