-- core/budget.lua
-- Where each frame's time goes, how much memory Lua holds, and a quality level that steps down when frames run long
-- and back up when there is room. Every computer on the server shares one Lua thread, so a slow frame here is a slow
-- frame for everyone. Pure apart from the clock it is given.
--
--   local b = budget.new({ clock = fn_ms, target = 5 })
--   b:time("render", function() ... end)     -- or b:start("ai") ... b:stop("ai")
--   b:frame()                                -- at the end of each frame: averages, quality
--   b.quality                                -- 0 (best) .. 3 (lightest); listen to "quality" on the bus to follow it
--   b:lines() -> text lines for the F3 overlay
--   b:report() -> { frameAvg, frameP90, heapKB, heapMaxKB, systems = { name = avgMs } }

local M = {}
local B = {}
B.__index = B

M.TARGET_MS = 5 -- the emulator's ms a frame on 51x19
M.MAX_QUALITY = 3

local function defaultClock()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") end
  return os.clock() * 1000
end

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    clock = opts.clock or defaultClock,
    target = opts.target or M.TARGET_MS,
    bus = opts.bus,
    quality = 0,
    systems = {}, -- name -> { ms (this frame), avg }
    running = {},
    frameStart = nil,
    frameAvg = 0,
    samples = {},
    over = 0, under = 0,
    heapKB = 0, heapMaxKB = 0,
    frames = 0,
  }, B)
end

function B:start(name)
  self.running[name] = self.clock()
  if not self.frameStart then self.frameStart = self.running[name] end
end

function B:stop(name)
  local t0 = self.running[name]
  if not t0 then return end
  self.running[name] = nil
  local s = self.systems[name]
  if not s then
    s = { ms = 0, avg = 0 }
    self.systems[name] = s
  end
  s.ms = s.ms + (self.clock() - t0)
end

function B:time(name, fn)
  self:start(name)
  local ok, err = pcall(fn)
  self:stop(name)
  if not ok then error(err, 0) end
end

local function setQuality(self, q)
  if q == self.quality then return end
  local prev = self.quality
  self.quality = q
  if self.bus then self.bus:emit("quality", { level = q, previous = prev }) end
end

--- The frame is over. frameMs: the whole frame's time if the caller measured it (else the sum of the systems).
function B:frame(frameMs)
  local total = 0
  for _, s in pairs(self.systems) do
    s.avg = s.avg * 0.9 + s.ms * 0.1
    total = total + s.ms
    s.ms = 0
  end
  frameMs = frameMs or total
  self.frameStart = nil
  self.frames = self.frames + 1
  self.frameAvg = self.frames == 1 and frameMs or (self.frameAvg * 0.9 + frameMs * 0.1)
  self.samples[#self.samples + 1] = frameMs
  if #self.samples > 200 then table.remove(self.samples, 1) end
  -- CC:Tweaked has no collectgarbage: the heap is only known under desktop Lua (the desk harness measures it)
  local gc = rawget(_G, "collectgarbage")
  if gc then
    self.heapKB = gc("count")
    if self.heapKB > self.heapMaxKB then self.heapMaxKB = self.heapKB end
  end
  -- quality: a second over budget steps down, five seconds well under steps back up
  if self.frameAvg > self.target * 1.25 then
    self.over, self.under = self.over + 1, 0
    if self.over >= 20 and self.quality < M.MAX_QUALITY then
      setQuality(self, self.quality + 1)
      self.over = 0
    end
  elseif self.frameAvg < self.target * 0.6 then
    self.under, self.over = self.under + 1, 0
    if self.under >= 100 and self.quality > 0 then
      setQuality(self, self.quality - 1)
      self.under = 0
    end
  else
    self.over, self.under = 0, 0
  end
end

function B:p90()
  local copy = {}
  for i, v in ipairs(self.samples) do copy[i] = v end
  table.sort(copy)
  return copy[math.max(1, math.floor(#copy * 0.9))] or 0
end

function B:report()
  local sys = {}
  for k, s in pairs(self.systems) do sys[k] = s.avg end
  return { frameAvg = self.frameAvg, frameP90 = self:p90(), heapKB = self.heapKB, heapMaxKB = self.heapMaxKB,
    quality = self.quality, systems = sys }
end

function B:lines()
  local heap = self.heapKB > 0 and (math.floor(self.heapKB) .. " KB") or "n/a"
  local out = { string.format("%4.1f ms (p90 %.0f)  heap %s  q%d", self.frameAvg, self:p90(), heap, self.quality) }
  local names = {}
  for k in pairs(self.systems) do names[#names + 1] = k end
  table.sort(names, function(a, b) return self.systems[a].avg > self.systems[b].avg end)
  local row = {}
  for i = 1, math.min(4, #names) do row[#row + 1] = string.format("%s %.1f", names[i], self.systems[names[i]].avg) end
  out[2] = table.concat(row, "  ")
  return out
end

return M
