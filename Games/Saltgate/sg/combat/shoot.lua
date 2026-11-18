-- combat/shoot.lua
-- One shot, found by walking a ray: the first of a person, a car (cover), or a wall along it. A car stops a shot that
-- passes lower than its roof, so a person crouched behind a car is not hit; a shooter standing higher (a bridge)
-- shoots over it. Pure: it works on lists and a world with collide(x, z, r, y).
--
--   shoot.cast(opts, ox, oy, oz, angle, range) -> { kind = "target" | "car" | "wall" | "none", e, x, z, y, dist }
--   opts: targets (people, with x, z, radius, knocked), cars, stream, ignore (the shooter), ignoreCar, assist (extra
--         reach for a lock-on, in units), feet (the shooter's ground height, for walls)

local M = {}

M.STEP = 1.0

local cos, sin, abs = math.cos, math.sin, math.abs

function M.cast(opts, ox, oy, oz, angle, range)
  local dx, dz = cos(angle), sin(angle)
  local bestS, bestE = range, nil
  local assist = opts.assist or 0
  for _, e in ipairs(opts.targets or {}) do
    if e ~= opts.ignore and not e.knocked then
      local rx, rz = e.x - ox, e.z - oz
      local s = rx * dx + rz * dz
      if s > 0.2 and s < bestS then
        local perp = abs(rx * dz - rz * dx)
        if perp <= (e.radius or 0.55) + assist then bestS, bestE = s, e end
      end
    end
  end
  local cars = opts.cars
  local stream = opts.stream
  local feet = opts.feet or (oy - 1.2)
  local s = M.STEP
  while s < bestS do
    local x, z = ox + dx * s, oz + dz * s
    if stream then
      local _, _, hit = stream:collide(x, z, 0.1, feet)
      if hit then return { kind = "wall", x = x, z = z, y = oy, dist = s } end
    end
    if cars then
      for i = 1, #cars do
        local c = cars[i]
        if c ~= opts.ignoreCar then
          local rx, rz = x - c.x, z - c.z
          local reach = c.spec.radius + 1
          if rx * rx + rz * rz < reach * reach and oy < (c.y or 0) + c.spec.height then
            local ch, sh = cos(c.h), sin(c.h)
            local lx, lz = rx * ch + rz * sh, -rx * sh + rz * ch
            if abs(lx) <= c.spec.length / 2 and abs(lz) <= c.spec.width / 2 then
              return { kind = "car", e = c, x = x, z = z, y = oy, dist = s }
            end
          end
        end
      end
    end
    s = s + M.STEP
  end
  if bestE then
    return { kind = "target", e = bestE, x = ox + dx * bestS, z = oz + dz * bestS, y = (bestE.y or 0) + 1.1, dist = bestS }
  end
  return { kind = "none", x = ox + dx * range, z = oz + dz * range, y = oy, dist = range }
end

return M
