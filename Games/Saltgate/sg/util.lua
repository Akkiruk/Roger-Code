-- util.lua
-- Small helpers shared by every Saltgate module: maths, a seeded random source, angles.

local M = {}

local floor, sqrt, atan2, pi = math.floor, math.sqrt, math.atan2 or math.atan, math.pi
M.TAU = pi * 2

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.dist(ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  return sqrt(dx * dx + dz * dz)
end

function M.dist2(ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  return dx * dx + dz * dz
end

--- Angle a wrapped to (-pi, pi].
function M.wrap(a)
  a = a % M.TAU
  if a > pi then a = a - M.TAU end
  return a
end

--- Heading (radians) from a to b. Forward for heading h is (cos h, sin h) in (x, z).
function M.headingTo(ax, az, bx, bz)
  return atan2(bz - az, bx - ax)
end

--- Step a plain number a toward b by at most step. (For angles use turnToward, which wraps.)
function M.approach(a, b, step)
  if b > a then return math.min(b, a + step) end
  return math.max(b, a - step)
end

--- Step an angle a toward angle b by at most step, along the short way round. Only for angles: it wraps.
function M.turnToward(a, b, step)
  local d = M.wrap(b - a)
  if d > step then d = step elseif d < -step then d = -step end
  return a + d
end

--- A seeded random source (Park-Miller), so a run can be replayed. rng() is in [0,1); rng(n) in 1..n; rng(a, b) in a..b.
function M.rng(seed)
  local state = floor(seed or 1) % 2147483646
  if state <= 0 then state = state + 2147483646 end
  return function(a, b)
    state = (state * 16807) % 2147483647
    local r = (state - 1) / 2147483646
    if a == nil then return r end
    if b == nil then return floor(r * a) + 1 end
    return floor(r * (b - a + 1)) + a
  end
end

--- "$1,250"
function M.money(n)
  local s = tostring(floor(n + 0.5))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (neg and "-$" or "$") .. out
end

function M.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Tell the Roger supervisor (Shared/lib/roger_supervisor.lua) the game is alive, and whether a game is in progress
-- (an update then waits). Without "roger_alive" a game install with no monitor touches is taken for hung and rebooted
-- every 60 s. Call it every frame: it sends once every M.ALIVE_SECONDS of the given clock (seconds).
M.ALIVE_SECONDS = 5
local aliveAt = -1e9
function M.rogerAlive(nowSeconds, busy)
  if nowSeconds - aliveAt < M.ALIVE_SECONDS then return false end
  aliveAt = nowSeconds
  local q = rawget(_G, "os") and os.queueEvent
  if not q then return false end
  q("roger_alive")
  q("roger_busy", busy and true or false)
  return true
end

return M
