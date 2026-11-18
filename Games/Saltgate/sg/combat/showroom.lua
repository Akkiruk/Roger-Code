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
  -- boats on the water off the shore (away from the middle of the island)
  local sp = testbed.spawn
  local cx, cz = testbed.N * 88 / 2, testbed.N * 88 / 2
  local dx, dz = sp.x - cx, sp.z - cz
  local len = math.sqrt(dx * dx + dz * dz)
  dx, dz = dx / len, dz / len
  local found
  for d = 4, 140, 3 do
    local x, z = sp.x + dx * d, sp.z + dz * d
    if physics.waterOK(ctx.stream, x, z) and physics.waterOK(ctx.stream, x + dx * 14, z + dz * 14)
      and physics.waterOK(ctx.stream, x + dx * 14 - dz * 22, z + dz * 14 + dx * 22) then
      found = { x + dx * 8, z + dz * 8 }
      break
    end
  end
  if found then
    local px, pz = -dz, dx
    local h = atan2(-dz, -dx)
    for i, def in ipairs(ctx.vehicles.list("boat")) do
      fleet:spawn(def.id, found[1] + px * (i - 3) * 8 + dx * (i % 2) * 6, found[2] + pz * (i - 3) * 8 + dz * (i % 2) * 6, h)
    end
    ctx.log("showroom: boats at " .. floor(found[1]) .. "," .. floor(found[2]))
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
