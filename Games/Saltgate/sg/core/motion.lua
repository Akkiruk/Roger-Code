-- core/motion.lua
-- Moving something over real ground: it follows the height of the surface it is on (terrain, a bridge, a car park
-- level), pitches and rolls with the slope, leaves the ground when the ground falls away faster than it can follow
-- (cresting a hill at speed, a ramp, a cliff), flies, and lands. A rise too steep to climb is a wall. Pure: the world
-- is anything with groundAt(x, z, y), collide(x, z, r, y) and waterAt(x, z) (core/stream.lua has all three).
--
-- The mover keeps on e: x, y, z, h (heading), vy, airborne, pitch, roll, and reads its forward speed from the caller.
--
--   local r = motion.move(e, world, nx, nz, dt, { radius = 1.6, speed = car.v, swims = false })
--   r.hit, r.nx, r.nz      it ran into something (a building, a wall of rock, the edge of the loaded world)
--   r.landed, r.impact     it came down this step, this hard (vertical speed)
--   r.airborne             it is in the air now
--   r.water                it is in water deeper than WADE (the caller sinks a car, swims a person, floats a boat)
--   r.surface              what it stands on: "terrain", "bridge", "deck", ...

local M = {}

M.GRAVITY = 26
M.STEP = 1.1 -- a rise it can take in one step (a kerb, a ramp's start)
M.WADE = 0.6
M.STICK = 0.35 -- how far the ground may fall away below the path before it counts as leaving the ground

local atan2 = math.atan2 or math.atan

local function ground(world, x, z, y)
  local gy, kind = world:groundAt(x, z, y)
  return gy, kind
end

--- The slope under something facing h at (x, z): pitch (nose up positive) and roll (right side up positive).
function M.slope(world, x, z, y, h, len, wid)
  len, wid = len or 3, wid or 2
  local fx, fz = math.cos(h), math.sin(h)
  local rx, rz = -fz, fx
  local front = ground(world, x + fx * len / 2, z + fz * len / 2, y) or y
  local back = ground(world, x - fx * len / 2, z - fz * len / 2, y) or y
  local right = ground(world, x + rx * wid / 2, z + rz * wid / 2, y) or y
  local left = ground(world, x - rx * wid / 2, z - rz * wid / 2, y) or y
  return atan2(front - back, len), atan2(right - left, wid)
end

--- Move e to (nx, nz) over the world for dt seconds. See the top of the file for what comes back.
function M.move(e, world, nx, nz, dt, opts)
  opts = opts or {}
  local r = opts.radius or 0.5
  local out = { hit = false, landed = false, impact = 0 }
  e.y = e.y or (ground(world, e.x, e.z, nil) or 0)
  e.vy = e.vy or 0

  -- walls: buildings at this height
  local x, z, hit, hnx, hnz = world:collide(nx, nz, r, e.y)
  if hit then out.hit, out.nx, out.nz = true, hnx, hnz end

  -- the ground where it would be
  local gy, kind = ground(world, x, z, e.y)
  if gy == nil then
    -- the edge of the loaded world: stay put
    return { hit = true, nx = 0, nz = 0, landed = false, impact = 0, airborne = e.airborne, surface = "unloaded" }
  end
  if not e.airborne and gy > e.y + M.STEP then
    -- a rise too steep to climb: a wall of rock or a high kerb
    local bx, bz = e.x - x, e.z - z
    local len = math.sqrt(bx * bx + bz * bz)
    out.hit, out.nx, out.nz = true, len > 0 and bx / len or 0, len > 0 and bz / len or 0
    x, z = e.x, e.z
    gy, kind = ground(world, x, z, e.y)
  end
  e.x, e.z = x, z

  if e.airborne then
    e.vy = e.vy - M.GRAVITY * dt
    e.y = e.y + e.vy * dt
    if e.y <= gy then
      out.landed, out.impact = true, -e.vy
      e.y, e.vy, e.airborne = gy, 0, false
    end
  else
    -- on the ground: follow it, unless it falls away faster than the path we are on
    local rise = (gy - e.y) / math.max(dt, 0.001)
    local carried = e.groundVy or 0
    local pathY = e.y + carried * dt - 0.5 * M.GRAVITY * dt * dt
    if gy < pathY - M.STICK and (opts.speed or 0) ~= 0 or gy < e.y - M.STEP * 2 then
      e.airborne = true
      e.vy = math.max(carried, 0)
      e.y = e.y + e.vy * dt
    else
      e.y = gy
      e.groundVy = rise * 0.5 + carried * 0.5
    end
  end
  if not e.airborne then e.groundVy = e.groundVy or 0 else e.groundVy = 0 end

  -- tilt with the ground (in the air it keeps the tilt it left with, easing level)
  if e.airborne then
    e.pitch = (e.pitch or 0) * 0.98
    e.roll = (e.roll or 0) * 0.95
  elseif opts.tilt == false then
    -- nobody is looking closely: skip the four extra ground samples
    e.pitch, e.roll = 0, 0
  else
    local p, ro = M.slope(world, e.x, e.z, e.y, e.h or 0, opts.length, opts.width)
    e.pitch, e.roll = p, ro
  end

  local level = world:waterAt(e.x, e.z)
  if level and e.y < level - M.WADE and not opts.swims then out.water = level end
  out.airborne = e.airborne
  out.surface = kind
  return out
end

return M
