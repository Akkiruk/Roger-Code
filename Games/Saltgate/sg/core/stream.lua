-- core/stream.lua
-- Keeps the chunks round the camera loaded and the rest out of memory, a little work each frame, and answers
-- questions about the world (ground height, what is where, collisions, the road graph) from what is loaded. Pure: the
-- chunk source and the model builder are given to it.
--
--   local s = stream.new({
--     source = function(cx, cz) return chunkOrNil end,      -- may coroutine.yield() to spread its work
--     build = function(chunk, lod) return handle end,        -- models for a chunk; may yield; lod "full" | "low"
--     drop = function(chunk, handle) end,                    -- a chunk leaves (handle from build)
--     full = 1, low = 2,                                     -- rings: full detail within 1 chunk, low within 2
--     budgetMs = 2, clock = function() return ms end,        -- most work per update, and the clock to measure it
--     cache = 12,                                            -- chunk data kept after its models go
--     bus = events,                                          -- optional: chunk_loaded / chunk_unloaded
--   })
--   s:update(x, z)                    -- each frame: queue what is wanted, load (nearest first) within the budget
--   s:loadAll(x, z)                   -- load everything wanted now (at the start, behind a loading screen)
--   s:loaded() -> { [key] = { chunk, lod, handle } }
--   s:groundAt(x, z, y) -> height, kind      s:surface(x, z) -> kind      s:waterAt(x, z) -> level or nil
--   s:collide(x, z, r, y) -> x, z, hit, nx, nz      s:chunkAt(x, z) -> chunk or nil (nil: not loaded)
--   s.roads                           -- the roadgraph of what is loaded
--
-- Jobs must not pull events: a yield inside source or build hands control back to the streamer, not to CC.

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")
local roadgraph = require("sg.core.roadgraph")

local M = {}
local S = {}
S.__index = S

local floor = math.floor

local function defaultClock()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") end
  return os.clock() * 1000
end

function M.new(opts)
  local s = setmetatable({
    source = assert(opts.source, "stream needs a source"),
    build = opts.build or function() return true end,
    drop = opts.drop or function() end,
    full = opts.full or 1,
    low = opts.low or 2,
    budgetMs = opts.budgetMs or 2,
    clock = opts.clock or defaultClock,
    cacheSize = opts.cache or 12,
    bus = opts.bus,
    live = {}, -- key -> { chunk, lod, handle }
    cache = {}, -- key -> { chunk, used }
    jobs = {}, -- key -> { co, cx, cz, lod }
    missing = {}, -- key -> true: the source has no chunk there
    useCount = 0,
    roads = roadgraph.new(),
    stats = { loads = 0, drops = 0, maxLive = 0 },
  }, S)
  return s
end

local function ringOf(s, cx, cz, ccx, ccz)
  local d = math.max(math.abs(cx - ccx), math.abs(cz - ccz))
  if d <= s.full then return "full" end
  if d <= s.low then return "low" end
  return nil
end

local function cacheGet(s, key)
  local e = s.cache[key]
  if e then
    s.useCount = s.useCount + 1
    e.used = s.useCount
    return e.chunk
  end
  return nil
end

local function cachePut(s, key, c)
  s.useCount = s.useCount + 1
  s.cache[key] = { chunk = c, used = s.useCount }
  local n, oldestKey, oldest = 0, nil, math.huge
  for k, e in pairs(s.cache) do
    n = n + 1
    if not s.live[k] and e.used < oldest then oldestKey, oldest = k, e.used end
  end
  if n > s.cacheSize and oldestKey then s.cache[oldestKey] = nil end
end

local function unload(s, key)
  local l = s.live[key]
  if not l then return end
  s.live[key] = nil
  s.drop(l.chunk, l.handle)
  s.roads:removeChunk(l.chunk)
  s.stats.drops = s.stats.drops + 1
  if s.bus then s.bus:emit("chunk_unloaded", { cx = l.chunk.cx, cz = l.chunk.cz }) end
end

local function startJob(s, key, cx, cz, lod)
  local job = { cx = cx, cz = cz, lod = lod }
  job.co = coroutine.create(function()
    local c = cacheGet(s, key)
    if not c then
      c = s.source(cx, cz)
      if c then cachePut(s, key, c) end
    end
    if not c then return nil end
    return c, s.build(c, lod)
  end)
  s.jobs[key] = job
end

local function finishJob(s, key, job, c, handle)
  s.jobs[key] = nil
  if not c then
    s.missing[key] = true
    return
  end
  local old = s.live[key]
  if old then
    s.drop(old.chunk, old.handle)
    s.roads:removeChunk(old.chunk)
  end
  s.live[key] = { chunk = c, lod = job.lod, handle = handle }
  s.roads:addChunk(c)
  s.stats.loads = s.stats.loads + 1
  local n = 0
  for _ in pairs(s.live) do n = n + 1 end
  if n > s.stats.maxLive then s.stats.maxLive = n end
  if s.bus then s.bus:emit("chunk_loaded", { cx = c.cx, cz = c.cz, lod = job.lod }) end
end

--- What should be loaded round (x, z): queue it, drop what is too far, then work within the budget.
function S:update(x, z, unlimited)
  local ccx, ccz = chunkLib.at(x, z)
  self.centreX, self.centreZ = ccx, ccz
  -- drop: past the low ring by more than one (so walking on a chunk edge does not load and drop over and over)
  for key, l in pairs(self.live) do
    local d = math.max(math.abs(l.chunk.cx - ccx), math.abs(l.chunk.cz - ccz))
    if d > self.low + 1 then unload(self, key) end
  end
  for key, job in pairs(self.jobs) do
    if not ringOf(self, job.cx, job.cz, ccx, ccz) then self.jobs[key] = nil end
  end
  -- wanted, nearest first
  local wanted = {}
  for dz = -self.low, self.low do
    for dx = -self.low, self.low do
      local cx, cz = ccx + dx, ccz + dz
      local key = chunkLib.key(cx, cz)
      if not self.missing[key] then
        local lod = ringOf(self, cx, cz, ccx, ccz)
        local l = self.live[key]
        local job = self.jobs[key]
        if (not l or l.lod ~= lod) and not (job and job.lod == lod) then
          wanted[#wanted + 1] = { key = key, cx = cx, cz = cz, lod = lod, d = dx * dx + dz * dz }
        end
      end
    end
  end
  table.sort(wanted, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.key < b.key
  end)
  for _, w in ipairs(wanted) do startJob(self, w.key, w.cx, w.cz, w.lod) end
  -- work: resume jobs, nearest first, until the budget is spent
  local start = self.clock()
  local order = {}
  for key, job in pairs(self.jobs) do
    order[#order + 1] = { key = key, job = job, d = (job.cx - ccx) ^ 2 + (job.cz - ccz) ^ 2 }
  end
  table.sort(order, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.key < b.key
  end)
  for _, o in ipairs(order) do
    if not unlimited and self.clock() - start >= self.budgetMs then break end
    -- inJob: a source or builder may yield (to spread its work over frames) only while one of these jobs runs; anywhere
    -- else a bare coroutine.yield under CC is os.pullEventRaw and would swallow the next event (the frame timer)
    M.inJob = true
    local ok, c, handle = coroutine.resume(o.job.co)
    M.inJob = false
    if not ok then
      self.jobs[o.key] = nil
      error("loading chunk " .. o.key .. ": " .. tostring(c), 0)
    end
    if coroutine.status(o.job.co) == "dead" then finishJob(self, o.key, o.job, c, handle) end
  end
end

--- Load everything wanted round (x, z) now.
function S:loadAll(x, z, onProgress)
  local guard = 0
  repeat
    self:update(x, z, true)
    guard = guard + 1
    if onProgress then onProgress() end
  until next(self.jobs) == nil or guard > 1000
end

function S:pending()
  local n = 0
  for _ in pairs(self.jobs) do n = n + 1 end
  return n
end

function S:loaded()
  return self.live
end

function S:liveCount()
  local n = 0
  for _ in pairs(self.live) do n = n + 1 end
  return n
end

--- The loaded chunk a point is in, or nil.
function S:chunkAt(x, z)
  local cx, cz = chunkLib.at(x, z)
  local l = self.live[chunkLib.key(cx, cz)]
  return l and l.chunk
end

local function eachNear(s, x, z, fn)
  local cx, cz = chunkLib.at(x, z)
  for dz = -1, 1 do
    for dx = -1, 1 do
      local l = s.live[chunkLib.key(cx + dx, cz + dz)]
      if l then fn(l.chunk, dx == 0 and dz == 0) end
    end
  end
end

--- The surface something at height y stands on (see chunk.groundAt), across chunk edges. Unloaded: nil.
function S:groundAt(x, z, y)
  local own = self:chunkAt(x, z)
  if not own then return nil, "unloaded" end
  local list = { { y = chunkLib.terrainY(own, x, z), kind = "terrain" } }
  local ground = list[1].y
  eachNear(self, x, z, function(c) chunkLib.extraSurfaces(c, x, z, list, ground) end)
  if #list == 1 then return list[1].y, "terrain" end
  -- in a tunnel (at its floor's height), the hill above is its roof, not ground: without this the hill rose gently
  -- from the mouth and a car drove up over it instead of through
  if y ~= nil then
    local floorY
    for _, s in ipairs(list) do
      if s.kind == "tunnel" and y < s.y + M.TUNNEL_HEAD and (not floorY or s.y > floorY) then floorY = s.y end
    end
    if floorY then
      for i = #list, 1, -1 do
        local s = list[i]
        if (s.kind == "terrain" or s.kind == "shoulder") and s.y > floorY + chunkLib.STEP then table.remove(list, i) end
      end
      if #list == 0 then return floorY, "tunnel" end
    end
  end
  table.sort(list, function(a, b) return a.y > b.y end)
  if y == nil then return list[1].y, list[1].kind end
  for _, s in ipairs(list) do
    if s.y <= y + chunkLib.STEP then return s.y, s.kind end
  end
  return list[#list].y, list[#list].kind
end

--- What is drawn at a point: the first answer that is not plain land from the 3x3 chunks (its own chunk first).
function S:surface(x, z)
  local own = self:chunkAt(x, z)
  if not own then return "unloaded" end
  local kind = chunkLib.surface(own, x, z)
  if kind ~= "land" then return kind end
  local found = "land"
  eachNear(self, x, z, function(c, isOwn)
    if not isOwn and found == "land" then
      local k = chunkLib.surface(c, x, z)
      if k ~= "land" then found = k end
    end
  end)
  return found
end

function S:waterAt(x, z)
  local level = nil
  eachNear(self, x, z, function(c)
    if level == nil then level = chunkLib.waterAt(c, x, z) end
  end)
  return level
end

--- Push a circle at height y out of the buildings round it (an unloaded chunk is a wall: nobody leaves the
-- loaded world). Returns x, z, hit, nx, nz.
function S:collide(x, z, r, y)
  if not self:chunkAt(x, z) then return x, z, true, 0, 0 end
  local hit, nx, nz = false, 0, 0
  eachNear(self, x, z, function(c)
    local h, hnx, hnz
    x, z, h, hnx, hnz = chunkLib.collide(c, x, z, r, y)
    if h then
      hit = true
      nx, nz = nx + hnx, nz + hnz
    end
  end)
  -- rails along bridges and overpasses: on a deck you stay on it, and drive on and off at its ends. Across chunk edges
  -- a deck comes in pieces (often joined on a bend), so: inside any piece at your height is fine; otherwise you are held
  -- by the nearest piece you are beside, or past a bend of (a corner, or an end that meets another piece); only an end
  -- that meets nothing is open
  if y then
    local decks = {}
    eachNear(self, x, z, function(c)
      for _, rb in ipairs(c.ribbons) do
        if rb[1] == "bridge" or rb[1] == "overpass" then decks[#decks + 1] = rb end
      end
    end)
    local inside, push = false, nil
    local function joined(px, pz, me)
      for _, o in ipairs(decks) do
        if o ~= me then
          local p = o[3]
          if (p[1] - px) ^ 2 + (p[3] - pz) ^ 2 < 1 or (p[#p - 2] - px) ^ 2 + (p[#p] - pz) ^ 2 < 1 then return true end
        end
      end
      return false
    end
    for _, rb in ipairs(decks) do
      local hw = rb[2] / 2
      local pts = rb[3]
      local d, dy, seg, t, qx, qz, dx, dz = geom.polylineNearest(pts, x, z)
      if d < hw + r + 1.5 and math.abs(y - dy) < M.RAIL_REACH then
        if d <= hw - r * 0.5 then
          inside = true
        else
          local ox, oz = x - qx, z - qz
          local lon = math.abs(ox * dx + oz * dz)
          local held = lon < 0.5 -- beside it
          if not held then
            local nseg = #pts / 3 - 1
            local first, last = seg == 1 and t <= 0, seg == nseg and t >= 1
            if not first and not last then
              held = true -- past the outside of a bend
            else
              local px, pz = first and pts[1] or pts[#pts - 2], first and pts[3] or pts[#pts]
              held = joined(px, pz, rb) -- an end that meets another piece is a bend too
            end
          end
          if held and (not push or d < push.d) then
            push = { d = d, qx = qx, qz = qz, hw = hw, ox = ox, oz = oz }
          end
        end
      end
    end
    if push and not inside then
      local len = math.sqrt(push.ox * push.ox + push.oz * push.oz)
      if len > 1e-6 then
        local ux, uz = push.ox / len, push.oz / len
        local keep = math.max(0, push.hw - r)
        x, z = push.qx + ux * keep, push.qz + uz * keep
        nx, nz = nx - ux, nz - uz
        hit = true
        local l2 = math.sqrt(nx * nx + nz * nz)
        if l2 > 0 then nx, nz = nx / l2, nz / l2 end
      end
    end
  end
  return x, z, hit, nx, nz
end

M.TUNNEL_HEAD = 5 -- under this height above a tunnel floor you are in the tunnel (the hill above is its roof)
M.RAIL_REACH = 2.5 -- a deck's rails hold what is within this height of it (a car under the bridge drives on)

return M
