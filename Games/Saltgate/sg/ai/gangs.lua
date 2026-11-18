-- ai/gangs.lua
-- The rival crews. Each of four districts has its own crew in its own colour (Gilt Sevens in yellow, Lantern Kites in
-- magenta, Cinder Hounds in red, Brine Crows in cyan) standing about at a turf spot on the pavement. Leave them alone and
-- they leave you alone. Start something near one (an assault, gunfire, hit one with a car) and the whole crew turns on you
-- for a while: they run at you, shove you down if they reach you, and take shots at a car or a runner from range. It is all
-- cartoony: a shove is a knockdown and a few points of health, never death, and they get knocked down the same way (and
-- get back up). The shots are a hook so stream B's tracers can draw them: set ctx.ai.gangs.onShoot = function(member,
-- target, hit) end. Pure but for the context.
--
--   local G = gangs.new(ctx, peds)    G:update(dt)    G:provoke(x, z, radius)    G:clear()    G:alerted() -> count

local util = require("sg.util")
local los = require("sg.heat.los")

local M = {}
local G = {}
G.__index = G

local cos, sin, sqrt, abs = math.cos, math.sin, math.sqrt, math.abs
local atan2 = math.atan2 or math.atan

M.CREWS = {
  gilt = { name = "Gilt Sevens", shirt = "yellow" },
  lantern = { name = "Lantern Kites", shirt = "magenta" },
  cinder = { name = "Cinder Hounds", shirt = "red" },
  brine = { name = "Brine Crows", shirt = "cyan" },
}
M.SIZE = 3
M.ALERT = 25 -- seconds a crew stays angry after the last provocation
M.SHOVE = 4 -- health points a shove costs
M.SHOT = 3

function M.new(ctx, peds, seed)
  local self = setmetatable({ ctx = ctx, peds = peds, rng = util.rng(seed or 301), crews = {}, spawnT = 2, onShoot = nil }, G)
  return self
end

function G:members()
  return self.ctx.world:each("gang")
end

function G:alerted()
  local n = 0
  for _, m in ipairs(self:members()) do
    local crew = self.crews[m.gang.crew]
    if crew and (crew.alert or 0) > 0 then n = n + 1 end
  end
  return n
end

function G:clear()
  for _, m in ipairs(self:members()) do self.peds:remove(m) end
  self.crews = {}
end

--- Something happened at (x, z): any crew with a member within radius turns on the player.
function G:provoke(x, z, radius)
  local hit = false
  for _, m in ipairs(self.ctx.world:near(x, z, radius, "gang")) do
    local crew = self.crews[m.gang.crew]
    if crew then
      crew.alert = M.ALERT
      hit = true
    end
  end
  return hit
end

--- A crew of three round a turf spot on a walkable edge in the player's district.
function G:spawnCrew(district)
  local ctx = self.ctx
  local info = M.CREWS[district]
  if not info or self.crews[district] then return end
  local peds = self.peds
  local p = ctx.player
  if not peds.edges then return end
  for _ = 1, 10 do
    local e = peds.edges[self.rng(#peds.edges)]
    local s = e.length * (0.2 + 0.6 * self.rng())
    local x, y, z = ctx.roads:pointAt(e, s, e.kind == "path" and 0.8 or (e.width / 2 + 1.6))
    local d2 = (x - p.x) ^ 2 + (z - p.z) ^ 2
    local chunk = ctx.stream:chunkAt(x, z)
    if d2 > 40 * 40 and d2 < 90 * 90 and chunk and chunk.district == district then
      local crew = { name = info.name, district = district, x = x, z = z, y = y, alert = 0, members = {} }
      self.crews[district] = crew
      for i = 1, M.SIZE do
        local a = i / M.SIZE * math.pi * 2
        local m = peds:spawnOfficer(x + cos(a) * 1.6, z + sin(a) * 1.6, a + math.pi, y)
        ctx.world:tag(m, "officer", false)
        ctx.world:tag(m, "gang", true)
        m.officer, m.keep = nil, true
        m.shirt = info.shirt
        m.state = "stand"
        m.gang = { crew = district, home = { x = x + cos(a) * 1.6, z = z + sin(a) * 1.6 }, alert = 0, shoveT = 0, shootT = 0 }
        crew.members[#crew.members + 1] = m
      end
      return crew
    end
  end
end

local function fight(self, m, dt, tgt, dist)
  local ctx = self.ctx
  local g = m.gang
  g.shoveT = g.shoveT - dt
  g.shootT = g.shootT - dt
  if m.state == "down" or m.state == "dazed" then return end
  m.state = "fight"
  local want = atan2(tgt.z - m.z, tgt.x - m.x)
  m.h = util.turnToward(m.h or want, want, 6 * dt)
  if dist > 2.0 then
    local speed = dist > 8 and 4.6 or 3.4
    local nx, nz = m.x + cos(m.h) * speed * dt, m.z + sin(m.h) * speed * dt
    local x, z = ctx.stream:collide(nx, nz, 0.4, m.y)
    local gy = ctx.stream:groundAt(x, z, m.y + 1)
    if gy and abs(gy - m.y) < 1.3 then
      ctx.world:move(m, x, z)
      m.y = gy
    end
  end
  if dist < 2.4 and g.shoveT <= 0 then
    -- a shove: the player is knocked about (a few points), never worse
    g.shoveT = 1.4
    ctx.bus:emit("player_hurt", { amount = M.SHOVE, by = "gang" })
    local p = ctx.player
    if not p.car then
      p.v = 0
      p.x, p.z = p.x + cos(m.h) * 0.8, p.z + sin(m.h) * 0.8
    end
  elseif dist >= 4 and dist < 24 and g.shootT <= 0 then
    g.shootT = 1.7 + self.rng() * 0.8
    if los.clear(ctx.stream, m.x, (m.y or 0) + 1.2, m.z, tgt.x, (tgt.y or 0) + 1, tgt.z, 5) then
      local hit = self.rng() < (tgt.car and 0.18 or 0.3)
      if self.onShoot then self.onShoot(m, tgt, hit) end
      if hit then ctx.bus:emit("player_hurt", { amount = M.SHOT, by = "gang" }) end
    end
  end
end

function G:update(dt)
  local ctx = self.ctx
  local p = ctx.player
  local tgt = p.car or p
  -- crews appear in the district you are in, one at a time, every so often
  self.spawnT = self.spawnT - dt
  if self.spawnT <= 0 then
    self.spawnT = 6
    local c = ctx.stream:chunkAt(p.x, p.z)
    if c and M.CREWS[c.district] and not self.crews[c.district] and self.peds:count() < 60 then self:spawnCrew(c.district) end
  end
  for key, crew in pairs(self.crews) do
    local alive = 0
    for _, m in ipairs(crew.members) do
      if not m.removed then alive = alive + 1 end
    end
    local far = (crew.x - p.x) ^ 2 + (crew.z - p.z) ^ 2 > 150 * 150
    if alive == 0 then
      self.crews[key] = nil
    elseif far then
      for _, m in ipairs(crew.members) do
        if not m.removed then self.peds:remove(m) end
      end
      self.crews[key] = nil
    else
      crew.alert = math.max(0, (crew.alert or 0) - dt)
      -- they lose interest when you get away
      local d2 = (crew.x - p.x) ^ 2 + (crew.z - p.z) ^ 2
      if crew.alert > 0 and d2 > 120 * 120 then crew.alert = 0 end
      for _, m in ipairs(crew.members) do
        if not m.removed then
          m.gang.alert = crew.alert
          local dist = sqrt((tgt.x - m.x) ^ 2 + (tgt.z - m.z) ^ 2)
          if crew.alert > 0 and (m.state == "stand" or m.state == "fight" or m.state == "return") then
            fight(self, m, dt, tgt, dist)
          elseif m.state == "fight" or m.state == "return" then
            -- calm again: back to the spot
            m.state = "return"
            local h = m.gang.home
            local want = atan2(h.z - m.z, h.x - m.x)
            local d = sqrt((h.x - m.x) ^ 2 + (h.z - m.z) ^ 2)
            if d < 0.6 then
              m.state = "stand"
            else
              m.h = want
              ctx.world:move(m, m.x + cos(want) * 2.4 * dt, m.z + sin(want) * 2.4 * dt)
            end
          elseif m.state == "flee" and (m.t or 0) <= 0 then
            m.state = "return"
          end
        end
      end
    end
  end
end

return M
