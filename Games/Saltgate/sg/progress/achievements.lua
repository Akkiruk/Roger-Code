-- progress/achievements.lua
-- The 40 achievements (content/activities/achievements.lua): each one fires exactly once. Their conditions are data:
-- a stat reaches a number, a set (districts, radio stations) reaches a size, a part of the 100% tracker reaches a count or
-- is complete, the story finishes, completion reaches 100. Unlocked ones are kept in save.progress.achievements
-- (id = the stat "playSeconds" when it happened) and paid once. Pure: it needs the stats, a way to ask the tracker, a
-- way to pay and a way to announce.
--
--   local a = achievements.new({ defs = list, stats = stats, done = function(category) -> done, total end,
--                                completion = function() -> percent, story = function() -> finished, section = save.progress,
--                                announce = function(def) end, pay = function(n, reason) end })
--   a:check()                every unlock that has come true fires now (returns how many)
--   a:unlock(id) -> true the first time, false after
--   a:count()  a:total()  a:list() -> defs with .unlocked

local M = {}
local A = {}
A.__index = A

function M.new(opts)
  local self = setmetatable({
    defs = opts.defs, stats = opts.stats, doneFn = opts.done, completionFn = opts.completion, storyFn = opts.story,
    section = opts.section, announce = opts.announce, pay = opts.pay, byId = {}, order = {}, busy = false,
  }, A)
  for i, d in ipairs(self.defs) do
    self.byId[d.id] = d
    self.order[i] = d.id
  end
  self.section.achievements = self.section.achievements or {}
  return self
end

function A:use(section)
  section.achievements = section.achievements or {}
  self.section = section
end

function A:def(id) return self.byId[id] end

function A:has(id) return self.section.achievements[id] ~= nil end

function A:count()
  local n = 0
  for id in pairs(self.section.achievements) do
    if self.byId[id] then n = n + 1 end
  end
  return n
end

function A:total() return #self.defs end

--- How many count toward the 100% tracker: all but the one for the tracker itself.
function A:trackerCounts()
  local done, total = 0, 0
  for _, d in ipairs(self.defs) do
    if not d.completion then
      total = total + 1
      if self:has(d.id) then done = done + 1 end
    end
  end
  return done, total
end

function A:unlock(id)
  local d = self.byId[id]
  if not d or self:has(id) then return false end
  self.section.achievements[id] = math.floor(self.stats:get("playSeconds"))
  if d.reward and d.reward > 0 and self.pay then self.pay(d.reward, "achievement: " .. d.name) end
  if self.announce then self.announce(d) end
  return true
end

local function met(self, d)
  if d.stat then return self.stats:get(d.stat) >= d.at end
  if d.set then return self.stats:count(d.set) >= d.at end
  if d.done then
    local done, total = self.doneFn(d.done)
    if d.at == "all" then return total > 0 and done >= total end
    -- a city with fewer of them than the achievement asks for makes it "all of them"
    return total > 0 and done >= math.min(d.at, total)
  end
  if d.story then return self.storyFn() == true end
  if d.completion then return self.completionFn() >= d.completion end
  return false
end

--- Fire every achievement whose condition is true now. Returns how many fired.
function A:check()
  if self.busy then return 0 end
  self.busy = true
  local n = 0
  for _, id in ipairs(self.order) do
    local d = self.byId[id]
    if not self:has(id) and met(self, d) then
      if self:unlock(id) then n = n + 1 end
    end
  end
  self.busy = false
  return n
end

function A:list()
  local out = {}
  for i, id in ipairs(self.order) do
    local d = self.byId[id]
    out[i] = { id = d.id, name = d.name, desc = d.desc, reward = d.reward, unlocked = self:has(id) }
  end
  return out
end

return M
