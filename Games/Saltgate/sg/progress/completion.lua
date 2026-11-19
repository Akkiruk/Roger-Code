-- progress/completion.lua
-- The 100% tracker. Ten parts (content/activities/progress.lua) with weights that add up to exactly 100; each part's
-- share is its weight times done / total of its own kind, so everything done is exactly 100 points whatever the city
-- holds. Parts get their counts from providers: the story and the achievements are built in, the activities register
-- the rest. Pure.
--
--   local c = completion.new(config)               config: the content file's table
--   c:provide("totems", function() return done, total end)
--   c:compute() -> { percent = 41.5, parts = { { id, name, weight, done, total, points }, ... } }
--   c:percent()   c:display() -> "41.5"  (never shows 100 until it is 100)

local M = {}
local P = {}
P.__index = P

function M.new(config)
  local self = setmetatable({ config = config, providers = {} }, P)
  return self
end

--- The sum of the weights: must be 100.
function P:weightSum()
  local s = 0
  for _, c in ipairs(self.config.categories) do s = s + c.weight end
  return s
end

function P:provide(id, fn)
  self.providers[id] = fn
end

function P:compute()
  local parts, total = {}, 0
  for _, c in ipairs(self.config.categories) do
    local fn = self.providers[c.id]
    local done, all = 0, 0
    if fn then done, all = fn() end
    done, all = done or 0, all or 0
    if all < 1 then all = 1 end -- a part with nothing in it counts as not started, never as a division by zero
    if done > all then done = all end
    local points = c.weight * done / all
    total = total + points
    parts[#parts + 1] = { id = c.id, name = c.name, weight = c.weight, done = done, total = all, points = points }
  end
  -- the parts are sums of exact fractions: snap sums within a hair of 100 so full completion reads exactly 100
  if math.abs(total - self:weightSum()) < 1e-9 then total = self:weightSum() end
  return { percent = total, parts = parts }
end

function P:percent()
  return self:compute().percent
end

--- "41.5": one decimal, rounded down, so 99.96 is never shown as 100.0.
function P:display()
  local p = self:percent()
  if p >= 100 then return "100" end
  return string.format("%.1f", math.floor(p * 10 + 1e-9) / 10)
end

return M
