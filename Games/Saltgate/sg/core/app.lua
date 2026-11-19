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
local sound = require("sg.sound")
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
local floor = math.floor

-- the core's own screens (their keys are handled in the loop); a plugin's screens get input and update calls
local CORE_SCREENS = { play = true, pause = true, map = true }

--- The part of the day an hour is in.
function M.phase(hour)
  if hour >= 5 and hour < 8 then return "dawn" end
  if hour >= 8 and hour < 18 then return "day" end
  if hour >= 18 and hour < 21 then return "dusk" end
  return "night"
end

-- districts the soundtrack knows; any other plays the old town's arrangement
M.MUSIC_DISTRICTS = { gilt = "gilt", lantern = "lantern", cinder = "cinder", brine = "brine", mid = "mid" }

-- the soundtrack (music/), if installed: every call guarded, a failure logged once and then left alone
local musicMod = nil
local musicBroken = {}
local function music(name, ...)
  if not musicMod then return end
  local f = musicMod[name]
  if type(f) ~= "function" or musicBroken[name] then return end
  local ok, err = pcall(f, ...)
  if not ok then
    musicBroken[name] = true
    log("music." .. name .. ": " .. tostring(err))
  end
end
M.music = function(...) return music(...) end

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
    input = inputlib.new(keys), -- plugins bind their own keys here at init: ctx.input:bind(action, { keys.x })
    coreSendsVehicleEvents = true, -- vehicle_enter and vehicle_exit come from the core
    routesScreenInput = true, -- the core calls each plugin's input and the top plugin screen's input and update
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
  ui.screen({ name = "map", modal = true, draw = function(c)
    local w = c.worldDef
    if w and w.drawMap then w.drawMap(c) else c.view:drawMap(c, (w and w.chunks or testbed.chunks)()) end
  end })
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
  -- where to go: an arrow (from where the camera looks) and the distance, then the words. Anyone sets ctx.objective
  -- (a table, or a function returning one: { text, x, z, kind, colour }); the story's target is the fallback.
  ui.widget({ name = "core_objective", slot = "objective", priority = 10, draw = function(c, t)
    local o = viewLib.objective(c)
    if not o then
      -- nowhere to go: the line stays empty
      return
    end
    local x = 1
    if o.x and o.z then
      local p = c.player
      local at = p.car or p
      local yaw = c.view.cam and c.view.cam.yaw or at.h
      local word, dist = hints.direction(at.x, at.z, yaw, o.x, o.z)
      local head = " " .. hints.ARROWS[word] .. " " .. floor(dist + 0.5) .. "m "
      put(t, 1, 2, head, colours.black, colours.yellow)
      x = #head + 1
    end
    if o.text then
      local w = c.screen.getSize()
      local room = math.max(8, w - x - 15)
      put(t, x, 2, " " .. tostring(o.text):sub(1, room) .. " ", colours.white, colours.black)
    end
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
  if p.swimming then want = want * 0.45 end
  p.v = util.approach(p.v or 0, want, 25 * dt)
  local nx, nz = p.x + math.cos(p.h) * p.v * dt, p.z + math.sin(p.h) * p.v * dt
  local r = motion.move(p, ctx.stream, nx, nz, dt, { radius = 0.45, speed = p.v, swims = false, length = 0.6, width = 0.6 })
  -- deep water: swim at the surface (slowly), never walk on the sea floor. A swimmer held at the surface is above the
  -- WADE line, so motion stops reporting water: still swimming while the ground under them is deep under the level
  local level = r.water
  if not level and p.swimming then
    local l = ctx.stream:waterAt(p.x, p.z)
    local g = l and ctx.stream:groundAt(p.x, p.z, p.y)
    if l and (not g or g < l - motion.WADE) then level = l end
  end
  if level then
    p.swimming = true
    p.y = math.max(p.y, level - 0.5)
    p.airborne, p.vy = false, 0
  else
    p.swimming = false
  end
end
M.walk = walk

--- A land vehicle in deep water (its physics said r.water): it stalls and floods. After SINK_TIME it is a wreck and
--- whoever drove it swims out at the surface (vehicle_exit, then vehicle_sunk). Boats' physics never report water.
M.SINK_TIME = 1.2
local function sink(ctx, c, r, dt)
  if not (type(r) == "table" and r.water) then
    c.sinkT = nil
    return false
  end
  c.sinkT = (c.sinkT or 0) + dt
  c.v = (c.v or 0) * math.max(0, 1 - 4 * dt)
  if c.sinkT >= M.SINK_TIME and not c.sunk then
    c.sunk, c.wrecked, c.health, c.v = true, true, 0, 0
    c.follow, c.brain = nil, nil
    local p = ctx.player
    if p.car == c then
      p.car = nil
      p.x, p.z, p.h, p.v = c.x, c.z, c.h, 0
      p.y = r.water - 0.5
      p.swimming, p.airborne, p.vy = true, false, 0
      ctx.bus:emit("vehicle_exit", { vehicle = c, sunk = true })
      music("cue", "free_roam")
    end
    ctx.bus:emit("vehicle_sunk", { vehicle = c })
  end
  return true
end
M.sink = sink

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
  -- no title screen over a bench or an autopilot run (saltgate_notitle.flag does the same by hand)
  ctx.noTitle = bench or fs.exists("saltgate_notitle.flag")
  local note
  ctx.save, note = loadSave()
  if not ctx.save then
    ctx.save = saveLib.blank()
    log("save refused: " .. tostring(note))
  elseif note then
    log(note)
  end
  -- the clock: saved with the world; 1/60 of a game hour a real second (a day in 24 minutes)
  ctx.clock = { hour = tonumber(ctx.save.world.time) or 18, rate = 1 / 60 }
  -- the soundtrack, as the live game loads it (sound off, or no speaker: it stays silent by itself)
  if not bench and (fs.exists("music/init.lua") or fs.exists("music.lua")) then
    local ok, m = pcall(require, "music")
    if ok and type(m) == "table" then musicMod = m else log("music did not load: " .. tostring(m)) end
  end
  music("init", {})
  -- sound effects: ctx.sfx(name) plays one of sg/sound.lua's cues; with the soundtrack loaded they keep to 2 notes a
  -- tick, so the speaker's 8 hold both
  local soundOn = true
  if fs.exists("saltgate_settings.lua") then
    local ok, s = pcall(dofile, "saltgate_settings.lua")
    if ok and type(s) == "table" and s.sound == false then soundOn = false end
  end
  local speaker = (soundOn and not bench) and peripheral.find("speaker") or nil
  ctx.sfxState = sound.new(speaker, musicMod and 2 or 7)
  ctx.sfx = function(name) sound.play(ctx.sfxState, name) end
  ctx.music = {
    cue = function(name) music("cue", name) end,
    setDistrict = function(d) music("setDistrict", d) end,
    loaded = musicMod ~= nil,
  }

  -- stream E's loading card (sg/ui/loading.lua) if it is installed, else a plain line; steps count up the bar
  local okCard, card = pcall(require, "sg.ui.loading")
  if not okCard or type(card) ~= "table" or type(card.draw) ~= "function" then card = nil end
  local loadStep = 0
  local function loading(text)
    loadStep = loadStep + 1
    if card then
      local tips = card.TIPS
      local tip = tips and #tips > 0 and tips[(loadStep % #tips) + 1] or nil
      local ok = pcall(card.draw, screen, text, math.min(1, loadStep / 4), tip)
      if ok then return end
    end
    local w, h = screen.getSize()
    put(screen, 1, math.floor(h / 2), string.rep(" ", w))
    put(screen, math.max(1, math.floor((w - #text) / 2)), math.floor(h / 2), text, colours.yellow)
  end
  local function breathe()
    os.queueEvent("saltgate_yield")
    os.pullEvent("saltgate_yield")
  end
  ctx.view = viewLib.new(screen)

  --- Set colours: pal = { colourName = 0xRRGGBB, ... } (any subset). Sets the screen AND the 3D frame's window: a
  -- window keeps a palette of its own and pushes it to the screen every time it is drawn, so setting only the screen
  -- is undone at the next frame. Then tells the pixel mixer how alike the new colours look.
  function ctx.setPalette(pal)
    local targets = { screen }
    local win = ctx.view and ctx.view.r and ctx.view.r.buffer and ctx.view.r.buffer.blitWin
    if win then targets[#targets + 1] = win end
    for _, t in ipairs(targets) do
      if t.setPaletteColour then
        for name, rgb in pairs(pal) do
          local c = colours[name] or colors[name]
          if c then t.setPaletteColour(c, rgb) end
        end
      end
    end
    local blittle = require("pine3d.betterblittle")
    pcall(blittle.recomputeColorDistances, win or screen)
  end
  ctx.setPalette(render.PALETTE)
  -- the streamer exists from the start (plugins may hold it); what it streams is set by ctx.setWorld
  ctx.stream = streamLib.new({
    source = function() return nil end, build = ctx.view:builder(), drop = ctx.view:dropper(),
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
  ctx.bus:on("save", function(d) d.data.world.worldId = ctx.worldDef and ctx.worldDef.id end, "core")

  -- you and your car exist before the world does (plugins see them at init); setWorld puts you in it
  ctx.player = { kind = "player", x = 0, z = 0, h = 0, v = 0, y = 0 }
  local car = vehicle.new("marlin", 0, 0, 0, "red")
  car.y = 0
  ctx.cars[1] = car
  ctx.player.car = car
  local rng = util.rng(7)
  local where = args[3]

  --- Put the game in a world. def:
  --   id            "testbed", "city", ... (a save made in one world restores your place only in the same world)
  --   source        function(cx, cz) -> chunk or nil
  --   spawn         { x, z, h } where a new game starts
  --   view          optional: a view to draw with instead of the core's (keeps the core view's interface)
  --   build, drop   optional: chunk model builder and dropper (default: the view's)
  --   chunks        optional: function() -> every chunk, for the city map
  --   drawMap       optional: function(ctx) drawing the map screen itself
  --   at            optional: { x, z, h } to start at instead (debug, benches)
  -- Clears what the streamer holds, loads round the start, and moves you (and your car) there.
  function ctx.setWorld(def)
    if def.view then
      def.view.mode = ctx.view and ctx.view.mode or def.view.mode
      def.view.drawDistance = ctx.view and ctx.view.drawDistance or def.view.drawDistance
      ctx.view = def.view
    end
    local s = ctx.stream
    for key, l in pairs(s.live) do
      s.drop(l.chunk, l.handle)
      s.roads:removeChunk(l.chunk)
      s.live[key] = nil
    end
    s.cache, s.jobs, s.missing = {}, {}, {}
    s.source = def.source
    s.build = def.build or ctx.view:builder()
    s.drop = def.drop or ctx.view:dropper()
    ctx.worldDef = def
    -- where to start: the saved place in this same world, else the world's start
    local sp = def.at or def.spawn
    local saved = ctx.save.player
    if not def.at and not bench and ctx.save.world.worldId == def.id and saved.x and saved.z then
      sp = { x = saved.x, z = saved.z, h = saved.h or def.spawn.h }
    end
    loading("Loading Saltgate...")
    s:loadAll(sp.x, sp.z, breathe)
    local gy = s:groundAt(sp.x, sp.z, nil)
    if not gy then
      sp = def.spawn
      s:loadAll(sp.x, sp.z, breathe)
      gy = s:groundAt(sp.x, sp.z, nil) or 0
    end
    local p = ctx.player
    p.x, p.z, p.h, p.y, p.v = sp.x, sp.z, sp.h or 0, gy, 0
    local c = p.car or ctx.cars[1]
    if c then
      c.x, c.z, c.h, c.y, c.v = sp.x, sp.z, sp.h or 0, gy, 0
      c.vy, c.airborne, c.pitch, c.roll = 0, false, 0, 0
      if bench then c.follow = follow.new(ctx.roads, c.x, c.z, rng) end
    end
    ctx.camReset = true
    ctx.view.camYaw, ctx.view.camY = nil, nil
    return true
  end

  -- with the city installed, its plugin calls setWorld at init; without it, the step 0 testbed island
  local cityInstalled = fs.exists("content/world")
  local function useTestbed()
    loading("Raising the island...")
    testbed.chunks(breathe)
    local at = nil
    local f = testbed.FEATURES
    -- bench extras: start somewhere that shows off (args[3] = overpass | hill | jump), or end on the map (map)
    if bench and where == "overpass" then
      at = { x = f.overpass.x - 45, z = f.overpass.z - 2, h = 0.02 }
    elseif bench and where == "hill" then
      for _, c in pairs(testbed.chunks()) do
        for _, rd in ipairs(c.roads) do
          if rd[2] == f.hairpins[2] or rd[3] == f.hairpins[2] then
            local p = rd[8]
            at = { x = p[1], z = p[3], h = math.atan2(p[6] - p[3], p[4] - p[1]) }
          end
        end
      end
    elseif bench and where == "jump" then
      at = { x = f.jump.x - math.cos(f.jump.h) * 26, z = f.jump.z - math.sin(f.jump.h) * 26, h = f.jump.h }
    end
    ctx.setWorld({ id = "testbed", source = testbed.source, spawn = testbed.spawn, at = at, chunks = testbed.chunks })
    spawnTraffic(ctx, bench and 4 or 6, rng)
    if bench and where == "jump" then
      car.follow = nil
      car.v = 32
    end
  end
  if not cityInstalled then useTestbed() end


  coreScreens(ctx)
  local found = plugins.discover(fs, "sg/plugins")
  local loaded, failed = plugins.load(found, ctx)
  for _, f in ipairs(failed) do log("plugin " .. f.name .. " left out: " .. f.err) end
  ctx.plugins = loaded
  if not ctx.worldDef then
    -- the city's files are there but no plugin put the game in it (its plugin failed: see the log): the testbed
    if cityInstalled then log("content/world is installed but no plugin called ctx.setWorld: using the testbed") end
    useTestbed()
  end
  ctx.ui.push("play")
  ctx.bus:emit("load", { data = ctx.save })
  if not ctx.clock.owner then ctx.bus:emit("time_of_day", { hour = ctx.clock.hour, phase = M.phase(ctx.clock.hour) }) end
  music("cue", ctx.player.car and "driving" or "free_roam")

  local inp = ctx.input
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
    ctx.save.world.time = ctx.clock.hour
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
      -- the ui contract: every plugin sees the keys (the phone), the top screen a plugin added gets its input and
      -- update (talk, the failure screen, the phone); the core's own screens are handled above
      for _, pl in ipairs(ctx.plugins) do
        if pl.input then ctx.budget:time(pl.name, function() pl.input(ctx, inp) end) end
      end
      top = ctx.ui.top()
      if top and not CORE_SCREENS[top.name] then
        if top.input then top.input(ctx, inp, dt) end
        if top.update then top.update(ctx, dt) end
      end
      -- the clock (stream A's sky follows it): one game hour a real minute, time_of_day once a game minute
      -- (a plugin that runs the day itself, stream A's sky, sets ctx.clock.owner and keeps ctx.clock.hour; then the
      -- core neither moves the clock nor sends time_of_day)
      if not ctx.clock.owner then
        local before = floor(ctx.clock.hour * 60)
        ctx.clock.hour = (ctx.clock.hour + dt * ctx.clock.rate) % 24
        if floor(ctx.clock.hour * 60) ~= before then
          ctx.bus:emit("time_of_day", { hour = ctx.clock.hour, phase = M.phase(ctx.clock.hour) })
        end
      end
      music("update", dt)
      sound.update(ctx.sfxState, dt, false)

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
            ctx.bus:emit("vehicle_exit", { vehicle = c })
            music("cue", "free_roam")
          elseif ctx.nearCar then
            local c = ctx.nearCar
            local stolen = c.follow ~= nil or c.brain ~= nil
            p.car = c
            c.follow, c.brain = nil, nil
            ctx.bus:emit("vehicle_enter", { vehicle = c, stolen = stolen })
            music("cue", "driving")
          end
        end
        ctx.budget:time("physics", function()
          for _, c in ipairs(ctx.cars) do
            local carInput
            if c == p.car then
              carInput = (bench and c.follow) and follow.input(c.follow, c, dt) or input
              if bench and where == "jump" then carInput = { throttle = 1, steer = 0 } end
            elseif c.brain then
              -- a plugin's driver (stream C's traffic and Patrol): car.brain(ctx, car, dt) -> input
              carInput = c.brain(ctx, c, dt)
            elseif c.follow then
              carInput = follow.input(c.follow, c, dt)
            end
            local physics = vehicles.physicsForCar(c) or drive.step
            if c.sunk then carInput = nil end
            local r = physics(c, carInput, dt, ctx.stream, { tilt = c == p.car })
            sink(ctx, c, r, dt)
          end
          -- cars against cars (only those at about the same height: a bridge over a road does not collide)
          local cars = ctx.cars
          for a = 1, #cars - 1 do
            for b = a + 1, #cars do
              if math.abs((cars[a].y or 0) - (cars[b].y or 0)) < 2 then (ctx.bump or vehicle.bump)(cars[a], cars[b]) end
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
          music("setDistrict", M.MUSIC_DISTRICTS[c.district] or "mid")
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
