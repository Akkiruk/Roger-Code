-- saltgate_c_sim.lua
-- A headless copy of the v2 engine's frame for stream C's tests: the testbed island streamed in, the entity world,
-- the same physics loop as sg/core/app.lua (every car in ctx.cars is driven by follow.input, bumped against the rest),
-- and stream C's plugins loaded from sg/plugins the way the game loads them. No screen: ctx.view is a stand-in whose
-- renderer records what the plugins asked it to draw.

local M = {}

-- CC's colour names, as numbers, for the model files when desktop Lua runs them
if not rawget(_G, "colors") then
  local c = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128, lightGray = 256,
    cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768 }
  _G.colors = c
  _G.colours = c
end

local events = require("sg.core.events")
local entity = require("sg.core.entity")
local stream = require("sg.core.stream")
local budgetLib = require("sg.core.budget")
local uiLib = require("sg.core.ui")
local saveLib = require("sg.core.save")
local vehicles = require("sg.core.vehicles")
local plugins = require("sg.core.plugins")
local drive = require("sg.core.drive")
local follow = require("sg.core.follow")
local testbed = require("sg.core.testbed")
local vehicle = require("sg.vehicle")
local util = require("sg.util")
local testing = require("testing")

--- Stand-in for the renderer: place() counts, variant() builds the model once so a model that errors is found.
local function fakeRenderer()
  local r = { placed = {}, built = {}, buffer = { colorValues = setmetatable({}, { __index = function(t, k) local row = setmetatable({}, { __index = function() return 0 end }) rawset(t, k, row) return row end }) } }
  function r:variant(key, h, make)
    if not self.built[key] then
      self.built[key] = make()
    end
    return { 1, 2, 3, 4, 5, 6, 0, 0 }
  end
  function r:place(list, template, x, y, z)
    list[#list + 1] = { x, y, z }
    self.placed[#self.placed + 1] = { x, y, z }
  end
  r.frame = { newObject = function() return {} end }
  return r
end

--- A world with the testbed streamed in around (x, z). opts: seed, plugins (default true), x, z, hour.
function M.new(opts)
  opts = opts or {}
  math.randomseed(opts.seed or 11) -- the lane drivers' fallback random source
  local bus = events.new()
  local ctx = {
    bus = bus,
    world = entity.new({ cell = 32 }),
    ui = uiLib.new(bus),
    vehicles = vehicles,
    budget = budgetLib.new({ bus = bus }),
    cars = {},
    logs = {},
    time = 0,
  }
  ctx.log = function(m) ctx.logs[#ctx.logs + 1] = tostring(m) end
  vehicles.registerLegacy()
  ctx.save = saveLib.blank()
  ctx.stream = stream.new({ source = testbed.source, full = 1, low = 2, budgetMs = 3, bus = bus })
  ctx.roads = ctx.stream.roads
  testbed.chunks()
  local sp = testbed.spawn
  local x, z, h = opts.x or sp.x, opts.z or sp.z, opts.h or sp.h
  ctx.stream:loadAll(x, z)
  ctx.player = { kind = "player", x = x, z = z, h = h, v = 0 }
  local car = vehicle.new("marlin", x, z, h, "red")
  car.y = ctx.stream:groundAt(x, z, nil)
  ctx.player.y = car.y
  ctx.cars[1] = car
  ctx.player.car = car
  local r = fakeRenderer()
  ctx.view = { r = r, cam = { x = x, y = 4, z = z, yaw = h, pitch = 0 }, screen = { getSize = function() return 51, 19 end } }
  function ctx.view:scene() return {} end
  function ctx.view:minimap() end
  ctx.view.minimapBox = { x0 = 30, y0 = 4, w = 24, h = 19 }
  ctx.screen = ctx.view.screen
  ctx.districtName = "mid"
  ctx.rng = util.rng(opts.seed or 11)
  if opts.hour then bus:emit("time_of_day", { hour = opts.hour, phase = "day" }) end
  if opts.plugins ~= false then
    local names = opts.names or { "c_traffic", "c_peds", "c_police" }
    local loaded, failed = plugins.load(names, ctx)
    ctx.plugins, ctx.failed = loaded, failed
    for _, f in ipairs(failed) do error("plugin " .. f.name .. ": " .. f.err) end
  else
    ctx.plugins = {}
  end
  bus:emit("load", { data = ctx.save })
  return ctx
end

--- One frame the way app.lua does it. input: the player's input table (or a function(car) -> table), nil to coast.
-- Returns the seconds the plugins took.
function M.step(ctx, dt, input)
  dt = dt or 0.05
  local p = ctx.player
  for _, c in ipairs(ctx.cars) do
    local ci
    if c == p.car then
      ci = type(input) == "function" and input(c) or input
    elseif c.follow then
      ci = follow.input(c.follow, c, dt)
    end
    drive.step(c, ci, dt, ctx.stream, { tilt = c == p.car })
  end
  local cars = ctx.cars
  for a = 1, #cars - 1 do
    for b = a + 1, #cars do
      if math.abs((cars[a].y or 0) - (cars[b].y or 0)) < 2 and not cars[a].ghost and not cars[b].ghost then vehicle.bump(cars[a], cars[b]) end
    end
  end
  if p.car then p.x, p.y, p.z, p.h = p.car.x, p.car.y, p.car.z, p.car.h end
  ctx.time = ctx.time + dt
  ctx.world:focus(p.x, p.z)
  ctx.world:update(dt)
  ctx.stream:update(p.x, p.z, true)
  local t0 = os.clock()
  for _, pl in ipairs(ctx.plugins) do
    if pl.update then ctx.budget:time(pl.name, function() pl.update(ctx, dt) end) end
  end
  ctx.budget:frame(4)
  -- CC stops code that runs 7 s (wall time) without yielding: on a busy machine a long test loop got there, so every
  -- step breathes (testing.breathe yields at most every half second, and only under CC)
  local cost = os.clock() - t0
  testing.breathe()
  return cost
end

--- Draw one frame's worth through the stand-in renderer (to prove the draw hooks run).
function M.draw(ctx)
  ctx.view.r.placed = {}
  local list = ctx.view:scene(ctx)
  ctx.view:minimap(ctx)
  for _, pl in ipairs(ctx.plugins) do
    if pl.draw then pl.draw(ctx) end
  end
  return list
end

--- A player input that follows the road graph (the core's reference driver), for soaks. When the car has been stuck
-- for four seconds (or wrecked) it is set back on a road somewhere else, as a player would reset.
function M.autopilot(ctx, seed)
  local rng = util.rng(seed or 5)
  local f = follow.new(ctx.roads, ctx.player.car.x, ctx.player.car.z, rng)
  local stuck = 0
  local resets = 0
  local fn
  fn = function(car)
    if math.abs(car.v) < 0.8 then stuck = stuck + 0.05 else stuck = 0 end
    if stuck > 4 or car.wrecked then
      local list = {}
      for _, e in pairs(ctx.roads.edges) do
        if e.kind == "road" or e.kind == "avenue" then list[#list + 1] = e end
      end
      table.sort(list, function(a, b) return a.id < b.id end)
      local e = list[rng(#list)]
      local x, y, z, dx, dz = ctx.roads:pointAt(e, e.length / 2, 2)
      car.x, car.y, car.z, car.h, car.v, car.side = x, y, z, math.atan2(dz, dx), 0, 0
      car.health, car.wrecked, car.flat = car.spec.health, false, nil
      f = follow.new(ctx.roads, x, z, rng)
      stuck = 0
      resets = resets + 1
      M.resets = resets
    end
    return follow.input(f, car, 0.05)
  end
  M.resets = 0
  return fn
end

return M
