-- combat/showroom.lua
-- A proving ground for stream B on the step 0 testbed, switched on by a file named saltgate_b_demo.flag: every
-- vehicle lined up on the coast road beside the start, boats on the water off the shore, a rig with its trailer,
-- practice goons (two shoot back), and ammo, gun and health crates. Used for screenshots and for trying the keys; the
-- real city places its own pickups through chunk spawns.
--
--   showroom.vehicles(ctx, fleet)      showroom.combat(ctx, cb)

local testbed = require("sg.core.testbed")
local physics = require("sg.vehicles.physics")

local M = {}

local cos, sin, floor, atan2 = math.cos, math.sin, math.floor, math.atan2 or math.atan

--- The road edge at the start and a way to place things along it: (s, side) -> x, z, h.
local function along(ctx)
  local sp = testbed.spawn
  local e, s0 = ctx.roads:nearest(sp.x, sp.z, 40)
  if not e then return nil end
  return function(s, side)
    local ss = math.max(0, math.min(e.length, s0 + s))
    local x, _, z, dx, dz = ctx.roads:pointAt(e, ss, side)
    return x, z, atan2(dz, dx)
  end
end

--- The point with the most open water round it, and how far that goes (stepping out in eight directions).
function M.openWater(stream, size)
  local best, bx, bz = 0, nil, nil
  for gz = 12, size - 12, 14 do
    for gx = 12, size - 12, 14 do
      if physics.waterOK(stream, gx, gz) then
        local r = 60
        for a = 0, 7 do
          local dx, dz = cos(a * math.pi / 4), sin(a * math.pi / 4)
          for d = 6, 60, 6 do
            if not physics.waterOK(stream, gx + dx * d, gz + dz * d) then
              if d < r then r = d end
              break
            end
          end
        end
        if r > best then best, bx, bz = r, gx, gz end
      end
    end
  end
  return bx, bz, best
end

function M.vehicles(ctx, fleet)
  local place = along(ctx)
  if not place then return end
  local list = {}
  for _, class in ipairs({ "car", "bike", "truck" }) do
    for _, def in ipairs(ctx.vehicles.list(class)) do
      if not def.police then list[#list + 1] = def end
    end
  end
  local n = 0
  for i, def in ipairs(list) do
    local side = (i % 2 == 0) and 7.5 or -7.5
    local x, z, h = place(14 + floor((i - 1) / 2) * 7.5, side)
    local car = fleet:spawn(def.id, x, z, h)
    if car then n = n + 1 end
  end
  -- boats on the open water: the widest stretch the island has
  local x, z, room = M.openWater(ctx.stream, testbed.N * 88)
  if x then
    local h = math.pi * 0.5
    for i, def in ipairs(ctx.vehicles.list("boat")) do
      fleet:spawn(def.id, x + (i - 3) * 7.5, z + (i % 2) * 5 - 4, h)
    end
    ctx.log("showroom: boats at " .. floor(x) .. "," .. floor(z) .. " (" .. floor(room) .. " units of water round)")
  else
    ctx.log("showroom: no water found for boats")
  end
  ctx.log("showroom: " .. n .. " road vehicles")
end

function M.combat(ctx, cb)
  local place = along(ctx)
  if not place then return end
  local function ground(x, z) return x, z end
  -- practice goons ahead, two of them armed
  for i = 1, 5 do
    local x, z = place(22 + i * 3.5, (i % 2 == 0) and 4 or -4)
    x, z = ground(x, z)
    local g = cb:spawnGoon(x, z, { fights = i <= 2, shirt = ({ "purple", "cyan", "green", "magenta", "yellow" })[i] })
    g.h = math.pi
  end
  -- crates: ammo for each gun, a gun or two, a health
  local k = 0
  for _, spec in ipairs({ { "ammo", "popper" }, { "ammo", "scatter" }, { "ammo", "rattler" }, { "gun", "longpop" }, { "health", nil } }) do
    k = k + 1
    local x, z = place(8 + k * 2.2, 3.5 + (k % 2) * 2)
    local c = cb:dropAmmo(x, z, spec[2], nil, spec[1])
    c.respawn = 30
  end
end

return M
