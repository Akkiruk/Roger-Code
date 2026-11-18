-- heat.lua
-- How badly the Harbor Patrol wants you: a level of 0 to 5. Crimes raise it, and it cools one level at a time while
-- no patrol can see you. Being stopped next to a cruiser for long enough is a pinch (arrest). Pure.

local util = require("sg.util")

local M = {}

M.MAX = 5
M.SIGHT = 42 -- a cruiser sees this far, given a clear line

--- Seconds unseen before one level cools off, by level.
function M.cooldown(level)
  return 7 + level * 3
end

--- How many cruisers chase at a level.
function M.copsFor(level)
  if level <= 0 then return 0 end
  return math.min(6, level + (level >= 4 and 1 or 0))
end

function M.new()
  return { level = 0, unseen = 0, pinch = 0, flash = 0, lastReason = nil, floor = 0 }
end

--- A crime: raise the level by amount (whole levels), up to MAX.
function M.add(h, amount, reason)
  local before = h.level
  h.level = util.clamp(h.level + amount, 0, M.MAX)
  h.unseen = 0
  if h.level > before then
    h.flash = 2
    h.lastReason = reason
  end
  return h.level - before
end

--- At least this level (a mission's alarm).
function M.atLeast(h, level, reason)
  if h.level < level then return M.add(h, level - h.level, reason) end
  return 0
end

--- Gone: the Paint & Pray, a pinch, or a new life.
function M.clear(h)
  h.level, h.unseen, h.pinch, h.flash = 0, 0, 0, 0
end

--- Advance dt seconds. seen: a cruiser can see you now. caught: you are stopped with a cruiser beside you.
-- Returns "pinched" when the pinch completes, "cooled" when a level dropped, else nil.
function M.update(h, dt, seen, caught)
  if h.flash > 0 then h.flash = math.max(0, h.flash - dt) end
  if h.level <= 0 then
    h.pinch = 0
    h.unseen = 0
    return nil
  end
  if caught then
    h.pinch = h.pinch + dt
    if h.pinch >= M.PINCH_TIME then
      h.pinch = 0
      return "pinched"
    end
  else
    h.pinch = math.max(0, h.pinch - dt * 2)
  end
  if seen then
    h.unseen = 0
    return nil
  end
  h.unseen = h.unseen + dt
  if h.unseen >= M.cooldown(h.level) then
    h.unseen = 0
    h.level = h.level - 1
    return "cooled"
  end
  return nil
end

M.PINCH_TIME = 2.5

--- 0..1: how far the current level is from cooling, for the HUD.
function M.coolProgress(h)
  if h.level <= 0 then return 0 end
  return util.clamp(h.unseen / M.cooldown(h.level), 0, 1)
end

return M
