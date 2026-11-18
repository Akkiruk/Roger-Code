-- heat/wanted.lua
-- How badly the Harbor Patrol wants you, in six levels, and how it lets go. Crimes raise the level; while any patrol
-- can see you it holds. When none can, the place you were last seen becomes a search circle that shrinks as time passes
-- (twice as fast if you are outside it, much faster in a hideout); when the circle closes the level drops by one and a
-- smaller circle opens, until the Patrol has lost you altogether. Pure: the caller says whether you are seen.
--
--   local h = wanted.new()
--   wanted.crime(h, level, kind) -> levels gained     (a crime worth `level` stars: max with what you have; repeats of an
--                                                      equal or lesser crime add a star every third time)
--   wanted.update(h, dt, seen, x, z, hidden) -> nil | "cooled" | "lost"
--   wanted.plan(level) -> what the Patrol does at this level
--   h.level, h.seen, h.cx, h.cz (the circle's middle), h.radius, h.unseen, h.total (seconds to close the circle)

local M = {}

M.MAX = 6

-- what the Patrol brings, by level
M.PLANS = {
  [0] = { cruisers = 0, box = false, pit = false, blocks = 0, spikes = false, heli = false, boat = false, speed = 1 },
  { cruisers = 1, box = false, pit = false, blocks = 0, spikes = false, heli = false, boat = false, speed = 0.85 },
  { cruisers = 2, box = true, pit = false, blocks = 0, spikes = false, heli = false, boat = false, speed = 0.92 },
  { cruisers = 3, box = true, pit = true, blocks = 1, spikes = false, heli = false, boat = false, speed = 1.0 },
  { cruisers = 4, box = true, pit = true, blocks = 2, spikes = true, heli = false, boat = true, speed = 1.05 },
  { cruisers = 5, box = true, pit = true, blocks = 2, spikes = true, heli = true, boat = true, speed = 1.1 },
  { cruisers = 6, box = true, pit = true, blocks = 3, spikes = true, heli = true, boat = true, speed = 1.15 },
}

function M.plan(level)
  return M.PLANS[math.max(0, math.min(M.MAX, level))]
end

--- Seconds the circle takes to close, by level.
function M.cooldown(level)
  return 30 + level * 8
end

--- How wide the circle opens, by level.
function M.opening(level)
  return 60 + level * 18
end

function M.new()
  return { level = 0, seen = false, unseen = 0, total = 0, cx = 0, cz = 0, radius = 0, repeats = 0, flash = 0, crimes = 0, lastKind = nil }
end

--- A crime worth `level` stars. Returns how many levels it added.
function M.crime(h, level, kind)
  local before = h.level
  level = math.max(1, math.min(M.MAX, math.floor(level or 1)))
  h.crimes = h.crimes + 1
  h.lastKind = kind
  if level > h.level then
    h.level = level
    h.repeats = 0
  elseif h.level < M.MAX then
    h.repeats = h.repeats + 1
    if h.repeats >= 3 then
      h.level = h.level + 1
      h.repeats = 0
    end
  end
  if h.level > before then
    h.flash = 2.5
    h.unseen = 0
    h.total = M.cooldown(h.level)
    h.radius = M.opening(h.level)
  end
  return h.level - before
end

--- Set the level outright (a mission's alarm, a bribe, the Paint & Pray). 0 ends it.
function M.set(h, level)
  level = math.max(0, math.min(M.MAX, level))
  h.level, h.repeats, h.unseen = level, 0, 0
  if level == 0 then
    h.seen, h.radius, h.total, h.flash = false, 0, 0, 0
  else
    h.total = M.cooldown(level)
    h.radius = M.opening(level)
  end
end

function M.update(h, dt, seen, x, z, hidden)
  if h.flash > 0 then h.flash = math.max(0, h.flash - dt) end
  if h.level <= 0 then
    h.seen = false
    return nil
  end
  h.seen = seen and true or false
  if seen then
    h.cx, h.cz = x, z
    h.unseen = 0
    h.total = M.cooldown(h.level)
    h.radius = M.opening(h.level)
    return nil
  end
  local rate = 1
  if hidden then
    rate = 4
  else
    local dx, dz = x - h.cx, z - h.cz
    if dx * dx + dz * dz > h.radius * h.radius then rate = 2 end
  end
  h.unseen = h.unseen + dt * rate
  h.radius = M.opening(h.level) * math.max(0, 1 - h.unseen / h.total)
  if h.unseen >= h.total then
    h.level = h.level - 1
    h.unseen, h.repeats = 0, 0
    if h.level <= 0 then
      h.level, h.radius, h.total = 0, 0, 0
      return "lost"
    end
    h.total = M.cooldown(h.level)
    h.radius = M.opening(h.level)
    return "cooled"
  end
  return nil
end

--- 0..1, how much of the search is done (for the HUD bar).
function M.progress(h)
  if h.level <= 0 or h.total <= 0 then return 0 end
  return math.max(0, math.min(1, h.unseen / h.total))
end

return M
