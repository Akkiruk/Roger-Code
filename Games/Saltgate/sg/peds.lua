-- peds.lua
-- People on the sidewalks. They walk round their block, jump out of the way of a car coming at them, and go down if
-- they are too slow. A driver pulled out of a car runs off. Pure.

local util = require("sg.util")
local city = require("sg.city")

local M = {}

local cos, sin, abs = math.cos, math.sin, math.abs

M.SHIRTS = { "red", "blue", "lime", "magenta", "white", "cyan", "purple", "yellow", "green", "orange" }

function M.new(g, i, j, s, dir)
  local ped = {
    i = i, j = j, s = s, dir = dir,
    ox = 0, oz = 0, -- sidestep from the ring
    state = "walk", t = 0,
    speed = 1.3 + g.rng() * 0.7,
    shirt = M.SHIRTS[g.rng(#M.SHIRTS)],
  }
  local x, z, h = city.ringPoint(i, j, s)
  ped.x, ped.z, ped.h = x, z, dir < 0 and h + math.pi or h
  return ped
end

--- A ped that just runs from (x, z) along h, then is gone.
function M.runner(g, x, z, h)
  return { x = x, z = z, h = h, state = "run", t = 5, speed = 5.5, shirt = M.SHIRTS[g.rng(#M.SHIRTS)], ox = 0, oz = 0 }
end

--- The car most likely to run this ped over, and which side to jump to.
local function threat(g, ped)
  for _, car in ipairs(g.cars) do
    local v = car.v
    if abs(v) > 5 then
      local rx, rz = ped.x - car.x, ped.z - car.z
      local d2 = rx * rx + rz * rz
      if d2 < 100 then
        local fx, fz = cos(car.h), sin(car.h)
        if v < 0 then fx, fz = -fx, -fz end
        local along = rx * fx + rz * fz
        local lateral = rx * fz - rz * fx
        if along > 0 and abs(lateral) < 3 then
          return car, lateral >= 0 and 1 or -1, fx, fz
        end
      end
    end
  end
  return nil
end

--- Move one ped dt seconds. Returns "hit" and the car when it was run over.
function M.update(g, ped, dt)
  if ped.state == "down" then
    ped.t = ped.t - dt
    return nil
  end
  if ped.state == "run" then
    ped.t = ped.t - dt
    local nx, nz = ped.x + cos(ped.h) * ped.speed * dt, ped.z + sin(ped.h) * ped.speed * dt
    local cx, cz, hit = city.collide(g.city, nx, nz, 0.4)
    if hit then ped.h = ped.h + 1.3 end
    ped.x, ped.z = cx, cz
  else
    -- walk round the block, easing back from any sidestep
    ped.s = ped.s + ped.dir * ped.speed * dt
    local x, z, h = city.ringPoint(ped.i, ped.j, ped.s)
    local car, side, fx, fz = threat(g, ped)
    if car then
      -- dive away from the car's path
      local px, pz = fz * side, -fx * side
      ped.ox = ped.ox + px * 7 * dt
      ped.oz = ped.oz + pz * 7 * dt
      ped.scared = 1
    else
      local ease = util.clamp(dt * 0.8, 0, 1)
      ped.ox, ped.oz = ped.ox * (1 - ease), ped.oz * (1 - ease)
      if ped.scared then
        ped.scared = ped.scared - dt
        if ped.scared <= 0 then ped.scared = nil end
      end
    end
    local tx, tz = x + ped.ox, z + ped.oz
    local cx, cz = city.collide(g.city, tx, tz, 0.4)
    ped.ox, ped.oz = cx - x, cz - z
    ped.x, ped.z = cx, cz
    ped.h = car and util.headingTo(0, 0, ped.ox, ped.oz) or (ped.dir < 0 and h + math.pi or h)
  end
  for _, car in ipairs(g.cars) do
    if abs(car.v) > 3 then
      local reach = car.spec.radius * 0.75 + 0.4
      if util.dist2(car.x, car.z, ped.x, ped.z) < reach * reach then
        ped.state = "down"
        ped.t = 7
        ped.h = car.h
        car.v = car.v * 0.85
        return "hit", car
      end
    end
  end
  return nil
end

return M
