-- saltgate_d_sim.lua
-- A made-up world for the story's tests (not a test itself): the same adapter the game's sg/story/world.lua is, with a
-- player, a few actors and a heat level, and an autopilot that plays whatever the mission is waiting on: it makes the
-- goal come true (drive there, knock them all down, land the jump) or, for the failure tests, spoils it.

local contentLib = require("sg.core.content")
local eventsLib = require("sg.core.events")
local indexLib = require("sg.story.index")
local hostLib = require("sg.story.host")

local S = {}

--- Where the repo's Games/Saltgate folder is, from desktop Lua or from the emulator.
local function root()
  local candidates = { "Games/Saltgate/", "/repo/Games/Saltgate/", "../Games/Saltgate/", "repo/Games/Saltgate/" }
  for _, c in ipairs(candidates) do
    local f = io.open(c .. "content/story/list.lua", "r")
    if f then
      f:close()
      return c
    end
  end
  error("cannot find Games/Saltgate/content/story/list.lua")
end

--- A read-only fs over the real content folder (io), shaped like CC's.
local function realfs()
  local base = root()
  local fs = {}
  function fs.exists(p)
    local f = io.open(base .. p, "r")
    if f then f:close() return true end
    return false
  end
  function fs.open(p, mode)
    local f = io.open(base .. p, "r")
    if not f then return nil end
    return { readAll = function() return f:read("*a") end, close = function() f:close() end }
  end
  function fs.list() return {} end
  return fs
end

function S.content()
  return contentLib.new({ fs = realfs(), root = "content", cache = 64 })
end

function S.index()
  local idx, err = indexLib.load(S.content())
  if not idx then error(err) end
  return idx
end

-- ---------------------------------------------------------------- the world

local W = {}
W.__index = W

function S.world(places)
  local w = setmetatable({
    places = places,
    p = { x = 0, z = 0, car = nil, down = false, speed = 0 },
    level = 0, money = 0, actors = {}, flightInfo = nil, suspended = false, log = {},
  }, W)
  return w
end

function W:player() return self.p end
function W:place(name) return self.places[name] end
function W:speed() return self.p.speed end

function W:pos(target)
  if target == "player" then return self.p.x, self.p.z end
  if type(target) == "string" then
    local pl = self.places[target]
    if pl then return pl.x, pl.z end
    return nil
  end
  if type(target) == "table" then return target.x or target[1], target.z or target[2] end
end

function W:distTo(target)
  local a = target
  if type(target) == "table" and target.gap then return target.gap end
  local x, z = self:pos(a)
  if not x then return 9999 end
  return math.sqrt((x - self.p.x) ^ 2 + (z - self.p.z) ^ 2)
end

function W:inPlace(name, opts)
  local pl = self.places[name]
  if not pl then return false end
  local d = math.sqrt((pl.x - self.p.x) ^ 2 + (pl.z - self.p.z) ^ 2)
  if d > pl.r + (opts.radius or 0) then return false end
  if opts.car and not self.p.car then return false end
  if opts.actor and self.p.car ~= opts.actor then return false end
  if opts.speed and self.p.speed > opts.speed then return false end
  return true
end

function W:spawn(kind, at, opts)
  local x, z = self:pos(at or "player")
  local a = { kind = kind, vehicle = opts.vehicle, group = opts.group, name = opts.name, x = x or 0, z = z or 0,
    state = "ok", health = 1, gap = 30, route = opts.route, count = opts.count }
  self.actors[#self.actors + 1] = a
  if kind == "crew" or kind == "thugs" or kind == "guards" then a.count = opts.count or 3 end
  return a
end

function W:remove(a)
  for i, x in ipairs(self.actors) do
    if x == a then table.remove(self.actors, i) return end
  end
end

function W:state(a) return a.state end
function W:health(a) return a.health end
function W:inCar(a) return self.p.car == a end
function W:route(a, dest) a.dest = dest end
function W:heat() return self.level end
function W:setHeat(n, force)
  if force then self.level = n else self.level = math.max(self.level, n) end
end
function W:pay(n) self.money = self.money + n end

function W:remaining(group)
  local n = 0
  for _, a in ipairs(self.actors) do
    if a.group == group and a.state ~= "down" then n = n + (a.count or 1) end
  end
  return n
end

function W:clearFlight() self.flightInfo = nil end
function W:flight() return self.flightInfo end

function W:cleanup()
  self.actors = {}
  self.p.car = nil
end
function W:suspend() self.suspended = true end
function W:resume()
  self.suspended = false
  self.p.down = false
end

function W:restore(opts)
  self.restored = (self.restored or 0) + 1
  if opts.at then
    local pl = self.places[opts.at]
    self.p.x, self.p.z = pl.x, pl.z
  end
  self.p.down = false
  if opts.give then
    local a = self:spawn("car", opts.at, { vehicle = opts.give.kind, name = opts.give.name })
    self.p.car = a
    return a
  end
end

function W:camAt(spec)
  local x, z = self:pos(spec)
  return x, 0, z
end

-- ---------------------------------------------------------------- the autopilot

local function standIn(w, place)
  local pl = w.places[place]
  if pl then
    w.p.x, w.p.z = pl.x, pl.z
  end
end

--- Make the mission's goal come true.
function S.satisfy(w, host)
  local g = host.goal
  if not g then return false end
  local kind = g.kind
  w.p.speed = 0
  if kind == "go" then
    w.level = 0
    standIn(w, g.place)
    local actor = g.name and host.actors[g.name]
    if actor then
      w.p.car = actor
    elseif not w.p.car and host.objective and g.name == nil then
      w.p.car = w.p.car or { kind = "stand-in", state = "ok", health = 1 }
    end
  elseif kind == "enter" then
    w.p.car = host.actors[g.name]
  elseif kind == "anycar" then
    w.p.car = { kind = "stand-in", state = "ok", health = 1 }
  elseif kind == "hold" then
    standIn(w, g.place)
  elseif kind == "loseheat" then
    w.level = 0
  elseif kind == "tail" then
    local a = host.actors[g.name]
    if a then a.state = "arrived" end
  elseif kind == "chase" then
    local a = host.actors[g.name]
    if a then a.state = "caught" end
  elseif kind == "escort" then
    local a = host.actors[g.name]
    if a then a.state = "arrived" end
  elseif kind == "defeat" then
    for _, a in ipairs(w.actors) do
      if a.group == g.group then a.state = "down" end
    end
  elseif kind == "jump" then
    w.flightInfo = { landed = true, distance = (g.min or 8) + 6 }
  end
  return true
end

--- Spoil the goal: the player goes down.
function S.spoil(w)
  w.p.down = "ko"
end

-- ---------------------------------------------------------------- playing a mission

--- A host over a fresh world. opts.story: an existing story table (a save's).
function S.newHost(idx, opts)
  opts = opts or {}
  local bus = eventsLib.new()
  local w = S.world(idx.places)
  w.p.x, w.p.z = idx.places.start.x, idx.places.start.z
  local cues = {}
  local host = hostLib.new({
    bus = bus, world = w, list = idx, script = idx.script,
    music = function(c) cues[#cues + 1] = c end,
    log = function(m) if opts.verbose then print("log: " .. m) end end,
  })
  host:bind(opts.story or { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} } })
  host.cues = cues
  host.events = {}
  for name in pairs(eventsLib.NAMES) do
    bus:on(name, function(d) host.events[#host.events + 1] = { name, d } end, "test")
  end
  return host, w
end

--- Play host (running a mission) until it ends. picks: a list of choice numbers (then 1s); stopAt: a checkpoint name
-- to stop at (returns "stopped"); failAt: a checkpoint to spoil the first goal in. Returns the state and what was seen.
function S.play(host, w, opts)
  opts = opts or {}
  local picks = opts.picks or {}
  local pi = 0
  local seen = { says = {}, choices = {}, objectives = {}, cutscenes = {}, texts = {}, checkpoints = {} }
  host.record = function(kind, a, b)
    if kind == "say" then seen.says[#seen.says + 1] = { a, b }
    elseif kind == "choose" then seen.choices[#seen.choices + 1] = { a, b }
    elseif kind == "objective" then seen.objectives[#seen.objectives + 1] = a
    elseif kind == "cutscene" then seen.cutscenes[#seen.cutscenes + 1] = a
    elseif kind == "text" then seen.texts[#seen.texts + 1] = { a, b } end
  end
  local ticks = 0
  local spoiled = false
  local rng = opts.rng
  while host.state == "running" and ticks < (opts.maxTicks or 6000) do
    ticks = ticks + 1
    if opts.stopAt and host.checkpointName == opts.stopAt and not host.talk:talking() then
      return "stopped", seen
    end
    if host.talk.line then
      local r = host.talk:advance()
      if r == "reveal" then host.talk:advance() end
    elseif host.talk.choice then
      local c = host.talk.choice
      pi = pi + 1
      local pick = picks[pi] or (rng and (rng(#c.options)) or 1)
      if pick > #c.options then pick = #c.options end
      seen.picked = seen.picked or {}
      seen.picked[#seen.picked + 1] = { #c.options, pick }
      host.talk:pick(pick)
    elseif host.cut then
      host.cut:skip()
    elseif host.goal then
      if opts.failAt and host.checkpointName == opts.failAt and not spoiled then
        spoiled = true
        S.spoil(w)
      else
        S.satisfy(w, host)
      end
    end
    host:update(0.1)
    if host.checkpointName then seen.checkpoints[host.checkpointName] = true end
  end
  seen.ticks = ticks
  return host.state, seen
end

return S
