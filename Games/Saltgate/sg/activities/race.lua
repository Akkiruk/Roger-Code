-- activities/race.lua
-- A street race: a count-in, then gates along a curved, hilly route of the road graph, timed to the hundredth of a second.
-- The clock is the sum of the frames' dt; a gate's time is where inside its frame the car crossed the gate's line, so a
-- frame that is long or short never changes a time. Your best run is kept as a ghost (progress along the route every
-- quarter second): the ghost's car races beside you, and the HUD shows how many seconds you are ahead or behind it.
--
--   local route = race.route(def)                       { n, pts, cum, total, gates = { { x, y, z, fx, fz } } }
--   local r = race.new(ctx, def, best, ghost)            best: seconds or nil; ghost: { s, s, ... } or nil
--   r:update(dt) -> "count" | "run" | "done" | "failed"
--   r.t  r.next  r.result = { time, medal, new }  r.reason  r:hud()  r:markers()  r:ghostAt(t) -> s

local common = require("sg.activities.common")

local M = {}
local R = {}
R.__index = R

M.COUNTDOWN = 3
M.GATE = 13 -- half the gate's width: wide enough for a road and its verges
M.SAMPLE = 0.25 -- ghost sample interval, seconds
M.SLACK = 1.6 -- the bronze time times this is the time limit
M.LEFT_CAR = 4 -- seconds out of a car before the race is off
M.MEDALS = { "gold", "silver", "bronze" }

--- The route of a race def: points, distance along, and the gates (every def.cp points, and the last point).
function M.route(def)
  local pts = def.pts
  local n = #pts / 3
  local cum = { 0 }
  for i = 2, n do
    local a, b = (i - 2) * 3 + 1, (i - 1) * 3 + 1
    cum[i] = cum[i - 1] + math.sqrt((pts[b] - pts[a]) ^ 2 + (pts[b + 2] - pts[a + 2]) ^ 2)
  end
  local gates = {}
  local function gateAt(i)
    local a, b = math.max(1, i - 1), math.min(n, i + 1)
    local dx, dz = pts[(b - 1) * 3 + 1] - pts[(a - 1) * 3 + 1], pts[(b - 1) * 3 + 3] - pts[(a - 1) * 3 + 3]
    local len = math.sqrt(dx * dx + dz * dz)
    if len == 0 then dx, dz, len = 1, 0, 1 end
    gates[#gates + 1] = { x = pts[(i - 1) * 3 + 1], y = pts[(i - 1) * 3 + 2], z = pts[(i - 1) * 3 + 3], fx = dx / len, fz = dz / len, i = i }
  end
  local i = 1 + (def.cp or 4)
  while i < n do
    gateAt(i)
    i = i + (def.cp or 4)
  end
  gateAt(n)
  return { n = n, pts = pts, cum = cum, total = cum[n], gates = gates }
end

--- Where a distance s along the route is: x, y, z, heading.
function M.pointAt(route, s)
  local n, cum, pts = route.n, route.cum, route.pts
  if s <= 0 then s = 0 end
  if s >= route.total then s = route.total end
  local lo = 1
  while lo < n - 1 and cum[lo + 1] < s do lo = lo + 1 end
  local a, b = (lo - 1) * 3 + 1, lo * 3 + 1
  local seg = cum[lo + 1] - cum[lo]
  local t = seg > 0 and (s - cum[lo]) / seg or 0
  local x, y, z = pts[a] + (pts[b] - pts[a]) * t, pts[a + 1] + (pts[b + 1] - pts[a + 1]) * t, pts[a + 2] + (pts[b + 2] - pts[a + 2]) * t
  return x, y, z, math.atan2(pts[b + 2] - pts[a + 2], pts[b] - pts[a])
end

function M.new(ctx, def, best, ghost)
  local route = M.route(def)
  local self = setmetatable({
    ctx = ctx, def = def, route = route, best = best, ghost = ghost,
    phase = "count", count = M.COUNTDOWN, t = 0, next = 1, s = 0, seg = 1, samples = {}, sampleAcc = 0,
    out = 0, prev = nil, reason = nil, result = nil, lastShown = nil,
  }, R)
  return self
end

--- Progress along the route of a point, searching near the last segment (cheap, and never jumps back across a loop).
function R:project(x, z)
  local route = self.route
  local pts = route.pts
  local bestD, bestS, bestSeg = math.huge, self.s, self.seg
  for seg = math.max(1, self.seg - 1), math.min(route.n - 1, self.seg + 6) do
    local a, b = (seg - 1) * 3 + 1, seg * 3 + 1
    local dx, dz = pts[b] - pts[a], pts[b + 2] - pts[a + 2]
    local len2 = dx * dx + dz * dz
    local t = len2 > 0 and ((x - pts[a]) * dx + (z - pts[a + 2]) * dz) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qz = pts[a] + dx * t, pts[a + 2] + dz * t
    local d = (x - qx) ^ 2 + (z - qz) ^ 2
    if d < bestD then bestD, bestS, bestSeg = d, route.cum[seg] + t * math.sqrt(len2), seg end
  end
  self.seg = bestSeg
  self.s = bestS
  return bestS
end

--- The ghost's distance along the route t seconds into its run (nil without a ghost).
function R:ghostAt(t)
  local g = self.ghost
  if not g or #g == 0 then return nil end
  local f = t / M.SAMPLE + 1
  if f >= #g then return g[#g] end
  if f < 1 then return g[1] * 0 end
  local i = math.floor(f)
  return g[i] + (g[i + 1] - g[i]) * (f - i)
end

--- Seconds the ghost took to reach distance s.
function R:ghostTimeAt(s)
  local g = self.ghost
  if not g or #g < 2 then return nil end
  if s <= 0 then return 0 end
  for i = 2, #g do
    if g[i] >= s then
      local span = g[i] - g[i - 1]
      local f = span > 0 and (s - g[i - 1]) / span or 0
      return ((i - 2) + f) * M.SAMPLE
    end
  end
  return (#g - 1) * M.SAMPLE
end

local function fail(self, reason)
  self.phase = "failed"
  self.reason = reason
end

--- Where in the frame the car crossed a gate's line, and whether inside its width: the fraction, or nil.
local function crossing(gate, px, pz, x, z)
  local s0 = (px - gate.x) * gate.fx + (pz - gate.z) * gate.fz
  local s1 = (x - gate.x) * gate.fx + (z - gate.z) * gate.fz
  if s0 < 0 and s1 >= 0 then
    local f = -s0 / (s1 - s0)
    local cx, cz = px + (x - px) * f, pz + (z - pz) * f
    local lateral = math.abs((cx - gate.x) * -gate.fz + (cz - gate.z) * gate.fx)
    if lateral <= M.GATE then return f end
  end
  return nil
end
M.crossing = crossing

function R:medalFor(time)
  local d = self.def
  if time <= d.gold then return "gold" end
  if time <= d.silver then return "silver" end
  if time <= d.bronze then return "bronze" end
  return "none"
end

function R:update(dt)
  if self.phase == "done" or self.phase == "failed" then return self.phase end
  local x, y, z, car = common.where(self.ctx)
  local _ = y
  if self.phase == "count" then
    self.count = self.count - dt
    if self.count <= 0 then
      self.phase = "run"
      self.t = 0
      self.prev = { x = x, z = z }
      self.samples = { 0 }
      self.sampleAcc = 0
      self:project(x, z)
    end
    return self.phase
  end
  -- running
  local t0 = self.t
  self.t = t0 + dt
  if not car then
    self.out = self.out + dt
    if self.out > M.LEFT_CAR then fail(self, "You left the car.") return self.phase end
  else
    self.out = 0
    if car.wrecked then fail(self, "Your car is wrecked.") return self.phase end
  end
  local gate = self.route.gates[self.next]
  local prev = self.prev
  if gate and prev then
    local f = crossing(gate, prev.x, prev.z, x, z)
    -- one gate may be missed: crossing the one after counts for both
    local skip = false
    if not f and self.route.gates[self.next + 1] then
      f = crossing(self.route.gates[self.next + 1], prev.x, prev.z, x, z)
      skip = f ~= nil
    end
    if f then
      if skip then self.next = self.next + 1 end
      self.next = self.next + 1
      self.lastGateAt = t0 + f * dt
      if self.next > #self.route.gates then
        local time = math.floor((t0 + f * dt) * 100 + 0.5) / 100
        local medal = self:medalFor(time)
        self.samples[#self.samples + 1] = self.route.total
        self.result = { time = time, medal = medal, new = self.best == nil or time < self.best }
        self.phase = "done"
        return self.phase
      end
    end
  end
  self.prev.x, self.prev.z = x, z
  self:project(x, z)
  self.sampleAcc = self.sampleAcc + dt
  while self.sampleAcc >= M.SAMPLE do
    self.sampleAcc = self.sampleAcc - M.SAMPLE
    self.samples[#self.samples + 1] = math.floor(self.s * 10 + 0.5) / 10
  end
  if self.t > self.def.bronze * M.SLACK then fail(self, "Too slow.") end
  return self.phase
end

--- Seconds ahead (negative) or behind (positive) the ghost right now, or nil.
function R:gap()
  if self.phase ~= "run" then return nil end
  local tg = self:ghostTimeAt(self.s)
  if not tg then return nil end
  return self.t - tg
end

function R:hud()
  local d = self.def
  if self.phase == "count" then
    local n = math.ceil(self.count)
    return { title = "RACE  " .. d.name, line = "Get ready on the line.", centre = n >= 1 and tostring(n) or "GO", centreColour = n <= 1 and "lime" or "yellow" }
  end
  local gates = #self.route.gates
  local text = string.format("GATE %d/%d  %s", math.min(self.next, gates), gates, M.clock(self.t))
  local gap = self:gap()
  local sub
  if gap then sub = string.format("%s%.1fs vs ghost", gap > 0 and "+" or "-", math.abs(gap)) end
  if self.phase == "run" and self.t < 1 then return { title = "RACE  " .. d.name, line = text, sub = sub, centre = "GO", centreColour = "lime" } end
  return { title = "RACE  " .. d.name, line = text, sub = sub, gapSign = gap and (gap > 0 and 1 or -1) or nil }
end

function M.clock(seconds)
  local tenths = math.floor(seconds * 10 + 0.5)
  local m = math.floor(tenths / 600)
  return string.format("%d:%04.1f", m, (tenths - m * 600) / 10)
end

--- Markers: the next two gates (the next one bright), the finish, and the ghost's car.
function R:markers(out, spec)
  out = out or {}
  local gates = self.route.gates
  local last = #gates
  for i = self.next, math.min(last, self.next + 1) do
    local g = gates[i]
    local kind = i == last and "gate_finish" or (i == self.next and "gate_next" or "gate")
    out[#out + 1] = { kind = kind, x = g.x, y = g.y, z = g.z, h = math.atan2(g.fz, g.fx) }
  end
  if self.phase == "run" and self.ghost then
    local s = self:ghostAt(self.t)
    if s and s > 0 then
      local gx, gy, gz, gh = M.pointAt(self.route, s)
      out[#out + 1] = { kind = "ghost", x = gx, y = gy, z = gz, h = gh, spec = spec }
    end
  end
  return out
end

--- Pack the run's samples as the ghost to keep.
function R:ghostData()
  local out = {}
  for i, s in ipairs(self.samples) do out[i] = s end
  return out
end

return M
