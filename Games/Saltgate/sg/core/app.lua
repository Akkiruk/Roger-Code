-- core/app.lua
-- SALTGATE's v2 engine: the core (events, entities, streaming, the road graph, 3D driving, save v2, plugins, screens and
-- widgets, the budget) running the step 0 testbed island. Behind a flag while the city is built: saltgate.lua starts
-- this instead of today's game when saltgate_v2.flag exists or saltgate_settings.lua says engine = "v2".
--   saltgate              (with the flag) play the testbed
--   saltgate bench [n]    (with the flag) the autopilot drives n frames; times and memory go to saltgate_bench.log
--
-- Saves go to saltgate_save2.dat (read first from today's saltgate_save.dat, migrated), so switching the flag off
-- leaves today's save exactly as it was.

local eventsLib = require("sg.core.events")
local entityLib = require("sg.core.entity")
local streamLib = require("sg.core.stream")
local contentLib = require("sg.core.content")
local uiLib = require("sg.core.ui")
local saveLib = require("sg.core.save")
local vehicles = require("sg.core.vehicles")
local budgetLib = require("sg.core.budget")
local plugins = require("sg.core.plugins")
local drive = require("sg.core.drive")
local motion = require("sg.core.motion")
local follow = require("sg.core.follow")
local testbed = require("sg.core.testbed")
local viewLib = require("sg.core.view")
local chunkLib = require("sg.core.chunk")
local vehicle = require("sg.vehicle")
local render = require("sg.render")
local inputlib = require("sg.input")
local hints = require("sg.hints")
local util = require("sg.util")

local M = {}

M.SAVE = "saltgate_save2.dat"
M.OLD_SAVE = "saltgate_save.dat"
local LOG = "saltgate.log"
local BENCH_LOG = "saltgate_bench.log"

local function log(msg)
  local h = fs.open(LOG, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " [v2] " .. tostring(msg))
    h.close()
  end
end

local function now() return os.epoch("utc") end

--- Is the v2 engine switched on?
function M.enabled(settings)
  return fs.exists("saltgate_v2.flag") or (type(settings) == "table" and settings.engine == "v2")
end

--- The context every plugin gets.
local function makeContext(screen)
  local bus = eventsLib.new()
  local ctx = {
    bus = bus,
    world = entityLib.new({ cell = 32 }),
    content = contentLib.new({ root = "content" }),
    ui = uiLib.new(bus),
    vehicles = vehicles,
    budget = budgetLib.new({ bus = bus }),
    cars = {},
    log = log,
    screen = screen,
    perf = false,
  }
  vehicles.registerLegacy()
  return ctx
end

local function loadSave()
  if fs.exists(M.SAVE) then return saveLib.read(fs, M.SAVE) end
  local data, note = saveLib.read(fs, M.OLD_SAVE)
  return data, note
end

local function put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColour(fg or colours.white)
  t.setBackgroundColour(bg or colours.black)
  t.write(text)
end

--- The core's own screens and widgets (plugins add theirs the same way).
local function coreScreens(ctx)
  local ui = ctx.ui
  ui.screen({ name = "play", draw = function(c, dt) c.view:draw(c, dt) end })
  ui.screen({ name = "map", modal = true, draw = function(c) c.view:drawMap(c, testbed.chunks()) end })
  ui.screen({ name = "pause", modal = true, draw = function(c)
    c.view.r:panel({ { "PAUSED (v2 testbed)", colours.yellow }, { "" }, { "P back   M map   Q save and quit", colours.white },
      { "F3 frame times   C camera", colours.lightGrey } })
  end })

  local W = function(c) return (c.screen.getSize()) end
  ui.widget({ name = "core_topbar", slot = "top-left", priority = 100, draw = function(c, t)
    local w = W(c)
    put(t, 1, 1, string.rep(" ", w))
    put(t, 2, 1, util.money(c.save.player.money or 0), colours.lime)
    put(t, 14, 1, (c.districtName or ""):sub(1, w - 30), colours.lightGrey)
  end })
  ui.widget({ name = "core_status", slot = "status", priority = 50, draw = function(c, t)
    local _, h = c.screen.getSize()
    local car = c.player.car
    put(t, 1, h - 1, string.rep(" ", 30))
    if car then
      put(t, 2, h - 1, car.spec.name .. " " .. vehicle.speedo(car) .. " km/h" .. (car.airborne and "  AIR!" or ""), colours.white)
    else
      put(t, 2, h - 1, "Wren", colours.orange)
    end
  end })
  ui.widget({ name = "core_hints", slot = "hints", priority = 50, draw = function(c, t)
    local w, h = c.screen.getSize()
    put(t, 1, h, string.rep(" ", w))
    local text = c.player.car and hints.DRIVING or (c.nearCar and hints.NEAR_CAR or hints.FOOT)
    local x = 2
    for word, gap in text:gmatch("(%S+)(%s*)") do
      if x + #word - 1 > w then break end
      put(t, x, h, word, hints.isKey(word) and colours.yellow or colours.lightGrey)
      x = x + #word + #gap
    end
  end })
  ui.widget({ name = "core_objective", slot = "objective", priority = 10, draw = function(c, t)
    put(t, 1, 2, " Step 0 testbed: hills, hairpins, bridge ", colours.white, colours.black)
  end })
  ui.widget({ name = "core_budget", slot = "centre", priority = 100, visible = function(c) return c.perf end, draw = function(c, t)
    for i, line in ipairs(c.budget:lines()) do put(t, 1, 3 + i, " " .. line .. " ", colours.white, colours.black) end
    put(t, 1, 6, string.format(" chunks %d (pending %d)  tris %d ", c.stream:liveCount(), c.stream:pending(), c.tris or 0),
      colours.lightGrey, colours.black)
  end })
end

--- Walking on foot over the 3D world.
local function walk(ctx, input, dt)
  local p = ctx.player
  p.h = util.wrap(p.h + (input.steer or 0) * 2.2 * dt)
  local want = (input.throttle or 0) * (input.sprint and 7.5 or 4.2)
  if (input.throttle or 0) < 0 then want = (input.throttle or 0) * 2.5 end
  p.v = util.approach(p.v or 0, want, 25 * dt)
  local nx, nz = p.x + math.cos(p.h) * p.v * dt, p.z + math.sin(p.h) * p.v * dt
  motion.move(p, ctx.stream, nx, nz, dt, { radius = 0.45, speed = p.v, swims = true, length = 0.6, width = 0.6 })
end

local function nearestCar(ctx, reach)
  local p = ctx.player
  local best, bd = nil, reach * reach
  for _, car in ipairs(ctx.cars) do
    local d = (car.x - p.x) ^ 2 + (car.z - p.z) ^ 2
    if d < bd and not car.wrecked then best, bd = car, d end
  end
  return best
end

local function spawnTraffic(ctx, n, rng)
  local edges = {}
  for _, e in pairs(ctx.stream.roads.edges) do
    if e.kind ~= "path" then edges[#edges + 1] = e end
  end
  table.sort(edges, function(a, b) return a.id < b.id end)
  local kinds = { "pipit", "marlin", "kestrel", "tidewater" }
  for i = 1, math.min(n, #edges) do
    local e = edges[math.floor(rng() * #edges) + 1]
    local x, y, z, dx, dz = ctx.stream.roads:pointAt(e, e.length * 0.5, follow.LANE)
    local car = vehicle.new(kinds[(i % #kinds) + 1], x, z, math.atan2(dz, dx), vehicle.BODY_COLOURS[(i % #vehicle.BODY_COLOURS) + 1])
    car.y = y
    car.v = 6
    car.follow = follow.new(ctx.stream.roads, x, z, rng)
    if car.follow then ctx.cars[#ctx.cars + 1] = car end
  end
end

function M.main(args)
  args = args or {}
  local bench = args[1] == "bench"
  local benchFrames = tonumber(args[2]) or 300
  local screen = term.current()
  render.applyPalette(screen)
  screen.setBackgroundColour(colours.black)
  screen.clear()
  local ctx = makeContext(screen)
  local note
  ctx.save, note = loadSave()
  if not ctx.save then
    ctx.save = saveLib.blank()
    log("save refused: " .. tostring(note))
  elseif note then
    log(note)
  end

  local function loading(text)
    local w, h = screen.getSize()
    put(screen, 1, math.floor(h / 2), string.rep(" ", w))
    put(screen, math.max(1, math.floor((w - #text) / 2)), math.floor(h / 2), text, colours.yellow)
  end
  local function breathe()
    os.queueEvent("saltgate_yield")
    os.pullEvent("saltgate_yield")
  end

  loading("Raising the island...")
  testbed.chunks(breathe)
  ctx.view = viewLib.new(screen)
  ctx.stream = streamLib.new({
    source = testbed.source, build = ctx.view:builder(), drop = ctx.view:dropper(),
    full = 1, low = 2, budgetMs = 3, bus = ctx.bus,
  })
  ctx.roads = ctx.stream.roads
  -- when frames run long the budget lowers the quality: draw less far, keep fewer chunks at full detail
  ctx.bus:on("quality", function(d)
    local q = d.level
    ctx.stream.full = q >= 2 and 0 or 1
    ctx.stream.low = q >= 3 and 1 or 2
    ctx.view.drawDistance = ({ 260, 200, 160, 120 })[q + 1]
  end, "core")
  local spawn = testbed.spawn
  local saved = ctx.save.player
  local sx, sz, sh = spawn.x, spawn.z, spawn.h
  if saved.x and saved.z and not bench then sx, sz, sh = saved.x, saved.z, saved.h or sh end
  -- bench extras: start somewhere that shows off (args[3] = overpass | hill | jump), or end on the map (map)
  local where = args[3]
  local f = testbed.FEATURES
  if bench and where == "overpass" then
    sx, sz, sh = f.overpass.x - 45, f.overpass.z - 2, 0.02
  elseif bench and where == "hill" then
    local e = nil
    for _, c in pairs(testbed.chunks()) do
      for _, rd in ipairs(c.roads) do
        if rd[2] == f.hairpins[2] or rd[3] == f.hairpins[2] then e = rd end
      end
    end
    if e then
      local p = e[8]
      sx, sz = p[1], p[3]
      sh = math.atan2(p[6] - p[3], p[4] - p[1])
    end
  elseif bench and where == "jump" then
    sx, sz, sh = f.jump.x - math.cos(f.jump.h) * 26, f.jump.z - math.sin(f.jump.h) * 26, f.jump.h
  end
  loading("Loading Saltgate...")
  ctx.stream:loadAll(sx, sz, breathe)

  ctx.player = { kind = "player", x = sx, z = sz, h = sh, v = 0 }
  local car = vehicle.new("marlin", sx, sz, sh, "red")
  car.y = ctx.stream:groundAt(sx, sz, nil)
  ctx.player.y = car.y
  ctx.cars[1] = car
  ctx.player.car = car
  local rng = util.rng(7)
  spawnTraffic(ctx, bench and 4 or 6, rng)
  if bench and where ~= "jump" then car.follow = follow.new(ctx.roads, car.x, car.z, rng) end
  if bench and where == "jump" then car.v = 32 end

  coreScreens(ctx)
  local found = plugins.discover(fs, "sg/plugins")
  local loaded, failed = plugins.load(found, ctx)
  for _, f in ipairs(failed) do log("plugin " .. f.name .. " left out: " .. f.err) end
  ctx.plugins = loaded
  ctx.ui.push("play")
  ctx.bus:emit("load", { data = ctx.save })

  local inp = inputlib.new(keys)
  local timer = os.startTimer(0.05)
  local last = now()
  local saveT = 30
  local district = nil
  local benchTimes = {}
  local running = true

  local function doSave()
    local p = ctx.player
    local at = p.car or p
    ctx.save.player.x, ctx.save.player.z, ctx.save.player.h = at.x, at.z, at.h
    ctx.bus:emit("save", { data = ctx.save })
    local ok, err = saveLib.write(fs, M.SAVE, ctx.save)
    if not ok then log("save failed: " .. tostring(err)) end
  end

  while running do
    local ev = { os.pullEventRaw() }
    local name = ev[1]
    if name == "terminate" then
      if not bench then doSave() end
      running = false
    elseif name == "key" or name == "key_up" then
      inp:event(now() / 1000, name, ev[2], ev[3])
    elseif name == "timer" and ev[2] == timer then
      local t0 = now()
      local dt = util.clamp((t0 - last) / 1000, 0, 0.25)
      last = t0
      timer = os.startTimer(0.05)
      local top = ctx.ui.top()
      local screenName = top and top.name
      -- screens
      if screenName == "play" then
        if inp:pressedAction("pause") then ctx.ui.push("pause") end
        if inp:pressedAction("map") then ctx.ui.push("map") end
        if inp:pressedAction("camera") then
          local order = { chase = "far", far = "hood", hood = "chase" }
          ctx.view.mode = order[ctx.view.mode]
        end
      elseif screenName == "pause" then
        if inp:pressedAction("pause") then ctx.ui.pop() end
        if inp:pressedAction("map") then ctx.ui.pop() ctx.ui.push("map") end
        if inp:pressedAction("quit") then doSave() running = false end
      elseif screenName == "map" then
        if inp:pressedAction("map") or inp:pressedAction("pause") or inp:pressedAction("advance") then ctx.ui.pop() end
      end
      if inp:pressedAction("perf") then ctx.perf = not ctx.perf end

      if not ctx.ui.modal() then
        local input = inp:read()
        local p = ctx.player
        -- in and out
        ctx.nearCar = not p.car and nearestCar(ctx, 4) or nil
        if input.enter then
          if p.car then
            local c = p.car
            p.car = nil
            local dx, dz = vehicle.doorPoint(c)
            p.x, p.z, p.h, p.v, p.y = dx, dz, c.h, 0, c.y
          elseif ctx.nearCar then
            p.car = ctx.nearCar
            p.car.follow = nil
          end
        end
        ctx.budget:time("physics", function()
          for _, c in ipairs(ctx.cars) do
            local carInput
            if c == p.car then
              carInput = (bench and c.follow) and follow.input(c.follow, c, dt) or input
              if bench and where == "jump" then carInput = { throttle = 1, steer = 0 } end
            elseif c.follow then
              carInput = follow.input(c.follow, c, dt)
            end
            drive.step(c, carInput, dt, ctx.stream, { tilt = c == p.car })
          end
          -- cars against cars (only those at about the same height: a bridge over a road does not collide)
          local cars = ctx.cars
          for a = 1, #cars - 1 do
            for b = a + 1, #cars do
              if math.abs((cars[a].y or 0) - (cars[b].y or 0)) < 2 then vehicle.bump(cars[a], cars[b]) end
            end
          end
          if p.car then
            p.x, p.y, p.z, p.h = p.car.x, p.car.y, p.car.z, p.car.h
          else
            walk(ctx, input, dt)
          end
        end)
        ctx.world:focus(p.x, p.z)
        ctx.budget:time("world", function() ctx.world:update(dt) end)
        ctx.budget:time("stream", function() ctx.stream:update(p.x, p.z) end)
        -- the district you are in (music and plugins listen)
        local c = ctx.stream:chunkAt(p.x, p.z)
        if c and c.district ~= district then
          ctx.bus:emit("district_enter", { district = c.district, previous = district })
          district = c.district
          ctx.districtName = c.district
        end
        for _, pl in ipairs(ctx.plugins) do
          if pl.update then ctx.budget:time(pl.name, function() pl.update(ctx, dt) end) end
        end
        saveT = saveT - dt
        if saveT <= 0 and not bench then
          saveT = 30
          doSave()
        end
      end

      -- draw the screen on top of the stack
      local s = ctx.ui.top()
      if s then
        ctx.budget:time("render", function()
          s.draw(ctx, dt)
          for _, pl in ipairs(ctx.plugins) do
            if pl.draw then pl.draw(ctx) end
          end
        end)
      end
      local frameMs = now() - t0
      ctx.budget:frame(frameMs)
      if bench then
        benchTimes[#benchTimes + 1] = frameMs
        if #benchTimes >= benchFrames then running = false end
      end
      inp:endFrame(now() / 1000)
    end
  end

  if bench then
    table.sort(benchTimes)
    local n = #benchTimes
    local sum = 0
    for _, v in ipairs(benchTimes) do sum = sum + v end
    local rep = ctx.budget:report()
    local tris = 0
    for _, l in pairs(ctx.stream:loaded()) do tris = tris + ((l.handle and l.handle.tris) or 0) end
    local w, h = screen.getSize()
    local line = string.format(
      "v2 bench %dx%d: %d frames, mean %.1f ms, median %.1f, p90 %.1f, max %.1f; heap max %d KB; chunks loaded %d (max %d, %d loads); tris %d; render %.1f, physics %.1f, stream %.1f",
      w, h, n, sum / math.max(1, n), benchTimes[math.max(1, math.floor(n / 2))] or 0, benchTimes[math.max(1, math.floor(n * 0.9))] or 0,
      benchTimes[n] or 0, math.floor(rep.heapMaxKB), ctx.stream:liveCount(), ctx.stream.stats.maxLive, ctx.stream.stats.loads,
      tris, rep.systems.render or 0, rep.systems.physics or 0, rep.systems.stream or 0)
    local names = {}
    for k in pairs(rep.systems) do names[#names + 1] = k end
    table.sort(names)
    local parts = {}
    for _, k in ipairs(names) do parts[#parts + 1] = string.format("%s %.1f", k, rep.systems[k]) end
    line = line .. "; " .. table.concat(parts, ", ") .. "; quality " .. rep.quality
    local bl = fs.open(BENCH_LOG, "a")
    if bl then
      bl.writeLine(line .. (where and (" [" .. where .. "]") or "") .. (ctx.player.car and ctx.player.car.airborne and " (in the air)" or ""))
      bl.close()
    end
    if where == "map" then
      ctx.ui.push("map")
      ctx.ui.top().draw(ctx, 0)
    end
    return
  end
  render.resetPalette(screen)
  screen.setBackgroundColour(colours.black)
  screen.clear()
  screen.setCursorPos(1, 1)
  print("Thanks for driving in Saltgate (v2 testbed).")
  local _ = chunkLib
end

return M
