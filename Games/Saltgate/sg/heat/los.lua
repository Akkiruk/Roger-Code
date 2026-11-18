-- heat/los.lua
-- Can one place see another? A ray over the streamed world, sampled every few units: a building stops it, so does ground
-- that rises above the ray. Seen from the air (the helicopter) only a roof over the target hides it. Pure but for the
-- stream it is given (surface, groundAt).
--
--   los.clear(stream, x0, y0, z0, x1, y1, z1 [, step]) -> bool
--   los.covered(stream, x, y, z) -> bool          something solid over (x, z) above y: a bridge, a car park level, a tunnel

local M = {}

local sqrt = math.sqrt

function M.clear(stream, x0, y0, z0, x1, y1, z1, step)
  step = step or 5
  local dx, dz = x1 - x0, z1 - z0
  local dist = sqrt(dx * dx + dz * dz)
  local n = math.floor(dist / step)
  for i = 1, n - 1 do
    local t = i / n
    local x, z = x0 + dx * t, z0 + dz * t
    local y = y0 + (y1 - y0) * t
    if stream:surface(x, z) == "building" then return false end
    local gy = stream:groundAt(x, z, y + 1)
    if gy and gy > y + 0.6 then return false end
  end
  return true
end

function M.covered(stream, x, y, z)
  local gy = stream:groundAt(x, z, y + 40)
  return gy ~= nil and gy > y + 3
end

return M
