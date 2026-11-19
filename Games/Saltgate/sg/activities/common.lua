-- activities/common.lua
-- What every activity shares: the save section's shape, where the player is, small geometry. Pure.

local M = {}

--- Fill in the activities section's fields (a blank or older save has none of them).
function M.ensure(a)
  a.found = a.found or {}
  a.found.totem = a.found.totem or {}
  a.found.postcard = a.found.postcard or {}
  a.jumps = a.jumps or {}
  a.races = a.races or {}
  a.jobs = a.jobs or {}
  a.jobs.fares = a.jobs.fares or 0
  a.jobs.deliveries = a.jobs.deliveries or 0
  a.jobs.best = a.jobs.best or {}
  a.property = a.property or {}
  a.rent = a.rent or { hours = 0, days = 0 }
  a.goals = a.goals or {}
  a.outfits = a.outfits or { deckhand = true }
  a.tune = a.tune or {}
  return a
end

--- x, y, z, car of whoever the player is now (the car if driving).
function M.where(ctx)
  local p = ctx.player
  local car = p.car
  local a = car or p
  return a.x, a.y or p.y or 0, a.z, car
end

function M.dist(ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  return math.sqrt(dx * dx + dz * dz)
end

--- Speed of the player's car (units a second), 0 on foot.
function M.speed(ctx)
  local car = ctx.player.car
  return car and math.abs(car.v or 0) or 0
end

--- Give a sorted list of the things within r of (x, z) from items ({ x, z, ... }), nearest first, at most max.
function M.near(items, x, z, r, max)
  local out = {}
  local r2 = r * r
  for _, it in ipairs(items) do
    local dx, dz = it.x - x, it.z - z
    local d2 = dx * dx + dz * dz
    if d2 <= r2 then out[#out + 1] = { item = it, d2 = d2 } end
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  if max and #out > max then for i = #out, max + 1, -1 do out[i] = nil end end
  return out
end

return M
