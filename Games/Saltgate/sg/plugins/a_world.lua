-- plugins/a_world.lua
-- Stream A: the real city. When content/world/ is installed this plugin takes the v2 engine over from the step 0
-- testbed: it points the streamer at the city's chunks, swaps in the world view (sg/world/view.lua), moves the player
-- to the city's start, and then runs the day and the weather, the districts, the doors into interiors and the map.
-- Without content/world/ it does nothing and the testbed keeps running.
--
-- Works only through the core's public tables (ctx.stream, ctx.view, ctx.cars, ctx.ui, ctx.bus); the things the core
-- would do itself once it knows about the city are listed in Games/Saltgate/sg/world/CORE-NEEDS.txt.
--
--   ctx.a_world = {
--     city, view,
--     hour() -> game hour, setHour(h), weather() -> kind, setWeather(kind),
--     districtAt(x, z), enter(id), leave(), inside() -> interior id or nil,
--   }
--   ctx.places[name] = { x, z, r, y, label, district }   the named places missions point at (content/world/world.lua places)
--   (api table above:
--   }
-- Debug: a file saltgate_a_debug.lua ("return { hour = 12, weather = 'rain', x =, z =, h = , interior = 'noodle' }")
-- sets the start of a run (the screenshot tool uses it).

local cityLib = require("sg.world.city")
local viewLib = require("sg.world.view")
local sky = require("sg.world.sky")
local mapview = require("sg.world.mapview")
local chunkLib = require("sg.core.chunk")
local follow = require("sg.core.follow")
local vehicle = require("sg.vehicle")
local models = require("sg.models")
local util = require("sg.util")

local P = { name = "a_world", order = 5 }

local floor = math.floor

local function breathe()
  os.queueEvent("a_world_yield")
  os.pullEvent("a_world_yield")
end

local function readDebug()
  if not fs.exists("saltgate_a_debug.lua") then return nil end
  local h = fs.open("saltgate_a_debug.lua", "r")
  local text = h.readAll()
  h.close()
  local fn = load(text, "=debug", "t", {})
  if not fn then return nil end
  local ok, t = pcall(fn)
  return ok and type(t) == "table" and t or nil
end

--- Forget everything the streamer holds: the testbed's chunks use the same keys as the city's.
local function resetStream(ctx)
  local s = ctx.stream
  for key, l in pairs(s.live) do
    s.drop(l.chunk, l.handle)
    s.roads:removeChunk(l.chunk)
    s.live[key] = nil
  end
  s.cache, s.jobs, s.missing = {}, {}, {}
end

local function clockText(hour)
  local h = floor(hour) % 24
  local m = floor((hour - floor(hour)) * 60)
  return string.format("%02d:%02d", h, m)
end

local NPC_SHIRTS = { "yellow", "cyan", "red", "lime", "white", "blue", "brown", "orange" }

function P.init(ctx)
  local city = cityLib.new(ctx.content)
  if not city then
    ctx.log("a_world: no content/world, the testbed stays")
    return
  end
  local debug = readDebug()
  local data = city.data
  local old = ctx.view
  local view = viewLib.new(ctx.screen, city)
  view.mode = old and old.mode or "chase"
  view.drawDistance = old and old.drawDistance
  ctx.view = view

  -- the streamer now reads the city
  local s = ctx.stream
  resetStream(ctx)
  s.source = function(cx, cz) return city:source(cx, cz) end
  s.build = view:builder()
  s.drop = view:dropper()

  -- the player and the cars start in the city
  local save = ctx.save
  save.world = save.world or {}
  local p = ctx.player
  local sx, sz, sh = data.spawn.x, data.spawn.z, data.spawn.h
  local sp = save.player or {}
  if save.world.city == 1 and sp.x and sp.z and not (ctx.cars[1] and ctx.cars[1].follow) then sx, sz, sh = sp.x, sp.z, sp.h or sh end
  if debug and debug.x then sx, sz, sh = debug.x, debug.z, debug.h or sh end
  local rng = util.rng(11)
  local car = ctx.cars[1]
  local autopilot = car and car.follow ~= nil
  for i = #ctx.cars, 2, -1 do ctx.cars[i] = nil end
  s:loadAll(sx, sz, breathe)
  local gy = s:groundAt(sx, sz, nil)
  if not gy then
    -- a saved place that is not in the city: the start
    sx, sz, sh = data.spawn.x, data.spawn.z, data.spawn.h
    s:loadAll(sx, sz, breathe)
    gy = s:groundAt(sx, sz, nil) or 0
  end
  p.x, p.z, p.h, p.y = sx, sz, sh, gy
  if car then
    car.x, car.z, car.h, car.y, car.v = sx, sz, sh, gy, 0
    car.vy, car.airborne, car.pitch, car.roll = 0, false, 0, 0
    if autopilot then car.follow = follow.new(ctx.roads, sx, sz, rng) end
  end
  -- a little traffic on the city's roads (stream C replaces this with the real thing)
  local edges = {}
  for _, e in pairs(s.roads.edges) do
    if e.kind ~= "path" and e.kind ~= "rail" and e.length > 12 then edges[#edges + 1] = e end
  end
  table.sort(edges, function(a, b) return a.id < b.id end)
  local kinds = { "pipit", "marlin", "kestrel", "tidewater" }
  for i = 1, math.min(autopilot and 4 or 6, #edges) do
    local e = edges[floor(rng() * #edges) + 1]
    local x, y, z, dx, dz = s.roads:pointAt(e, e.length * 0.5, follow.LANE)
    local c = vehicle.new(kinds[(i % #kinds) + 1], x, z, math.atan2(dz, dx), vehicle.BODY_COLOURS[(i % #vehicle.BODY_COLOURS) + 1])
    c.y, c.v = y, 6
    c.follow = follow.new(ctx.roads, x, z, rng)
    if c.follow then ctx.cars[#ctx.cars + 1] = c end
  end

  -- the clock and the weather
  local state = {
    hour = (debug and debug.hour) or save.world.time or 17.5,
    weather = sky.weather.new(rng, (debug and debug.weather) or save.world.weather or "clear"),
    palette = nil, appliedHour = -99, appliedKind = nil, flash = 0, phase = nil, cool = 0,
    inside = nil, back = nil, speed = 1,
  }
  if debug and (debug.hour or debug.weather) then state.weather.forced = true end
  if debug and debug.freeze then state.speed = 0 end
  P.state = state

  --- Set the palette on the screen and on the 3D frame's window: a window keeps a palette of its own and pushes it to the
  -- screen each time it is drawn, so setting only the screen is undone at the next blit.
  local blittle = require("pine3d.betterblittle")
  local function push(pal)
    local n = sky.apply(ctx.screen, pal, state.palette)
    local win = view.r.buffer and view.r.buffer.blitWin
    if win then sky.apply(win, pal, state.palette) end
    if n >= 6 then pcall(blittle.recomputeColorDistances, win or ctx.screen) end
    state.palette = pal
  end
  local function applyPalette(force)
    local kind = state.weather.kind
    local hour = state.hour
    if not force and math.abs(hour - state.appliedHour) < 0.04 and kind == state.appliedKind and state.flash <= 0 and not state.flashed then return end
    push(sky.paletteAt(hour, kind, state.flash))
    state.appliedHour, state.appliedKind = hour, kind
    state.flashed = state.flash > 0
    view.sky.hour, view.sky.kind = hour, kind
  end
  state.push = push
  applyPalette(true)

  -- districts, the clock on the top line, the objective line
  for _, w in ipairs(ctx.ui.widgetList) do
    if w.name == "core_objective" then w.draw = function() end end
  end
  ctx.ui.widget({ name = "a_clock", slot = "top-right", priority = 60, visible = function() return not state.inside end, draw = function(c, t)
    local w = c.screen.getSize()
    local text = clockText(state.hour) .. " " .. state.weather.kind
    t.setCursorPos(1, 1)
    t.setBackgroundColour(colours.black)
    t.setTextColour(colours.lightGrey)
    t.setCursorPos(math.max(1, w - #text), 1)
    t.write(text)
  end })

  -- the whole-city map: the city's chunks rasterised once, when first asked for
  local mapChunks = nil
  local function theMap()
    if mapChunks then return mapChunks end
    mapChunks = {}
    for key, c in pairs(city:chunks()) do
      mapview.raster(c, nil, view.baseAt)
      mapChunks[key] = { cx = c.cx, cz = c.cz, _map = c._map, heights = nil, district = c.district }
      c._map = nil
    end
    return mapChunks
  end
  local mapScreen = ctx.ui.screens.map
  if mapScreen then
    mapScreen.draw = function(c)
      local img = city:mapImage()
      if img then c.view:drawMapImage(c, img) else c.view:drawMap(c, theMap()) end
    end
  end

  -- interiors: a door on foot takes you to a room far from the city, the room's door takes you back
  local api = { city = city, view = view }
  function api.hour() return state.hour end
  function api.setHour(h) state.hour = h % 24 applyPalette(true) end
  function api.weather() return state.weather.kind end
  function api.setWeather(kind)
    if not sky.WEATHER[kind] then return false end
    local prev = state.weather.kind
    state.weather.kind = kind
    state.weather.forced = true
    if prev ~= kind then ctx.bus:emit("weather", { kind = kind, previous = prev }) end
    applyPalette(true)
    return true
  end
  function api.districtAt(x, z) return city:districtAt(x, z) end
  function api.inside() return state.inside end
  function api.enter(id)
    local info = city:interior(id)
    if not info or state.inside then return false end
    if p.car then p.car = nil end
    state.back = { x = p.x, z = p.z, h = p.h }
    state.inside = id
    local ix, iz, ih = info.spawn[1], info.spawn[2], info.spawn[3]
    s:loadAll(ix, iz, breathe)
    p.x, p.z, p.h, p.v = ix, iz, ih, 0
    p.y = s:groundAt(ix, iz, nil) or 0
    view.inside = true
    view.camYaw = ih
    view.camY = nil
    ctx.interior = id
    state.cool = 1
    ctx.bus:emit("interior_enter", { id = id })
    return true
  end
  function api.leave()
    local id = state.inside
    if not id then return false end
    local b = state.back or { x = data.spawn.x, z = data.spawn.z, h = data.spawn.h }
    s:loadAll(b.x, b.z, breathe)
    p.x, p.z, p.h, p.v = b.x, b.z, b.h, 0
    p.y = s:groundAt(b.x, b.z, nil) or 0
    view.inside = false
    view.camYaw = b.h
    view.camY = nil
    state.inside = nil
    ctx.interior = nil
    state.cool = 1.5
    ctx.bus:emit("interior_exit", { id = id })
    return true
  end
  ctx.a_world = api
  -- the story's named places, laid out in the real city (stream D reads ctx.places[name] = { x, z, r, y, label })
  ctx.places = ctx.places or {}
  for name, place in pairs(data.places or {}) do
    local was = ctx.places[name] or {}
    ctx.places[name] = { x = place.x, z = place.z, r = place.r, y = place.y, h = place.h, label = was.label, district = was.district }
  end
  P.api = api

  -- the people in the rooms: stand-ins for the characters the story stream fills in
  view.scenery = view.scenery or {}
  view.scenery[#view.scenery + 1] = function(list, v)
    if not state.inside then return end
    local c = s:chunkAt(p.x, p.z)
    if not c then return end
    local r = v.r
    for _, sp2 in ipairs(c.spawns) do
      local name = sp2[1]:match("^npc:(.+)$")
      if name then
        local shirt = NPC_SHIRTS[(#name % #NPC_SHIRTS) + 1]
        local key = "npc:" .. shirt
        r:place(list, r:variant(key, sp2[4], function() return models.person(shirt, false, "gray") end), sp2[2], (c.heights and 0 or 0) + 0.05, sp2[3])
      end
    end
  end

  ctx.bus:on("save", function(d)
    d.data.world = d.data.world or {}
    d.data.world.time = state.hour
    d.data.world.weather = state.weather.kind
    d.data.world.city = 1
  end, "a_world")
  ctx.bus:on("quality", function(d)
    view.maxParticles = ({ 160, 100, 50, 0 })[d.level + 1]
  end, "a_world")

  if debug and debug.interior then api.enter(debug.interior) end
  ctx.log("a_world: the city is up (" .. #data.districts .. " districts)")
end

--- Doors on foot: walk into a door post to go in; walk to the room's door to come out.
local function doors(ctx, state, api, dt)
  local p = ctx.player
  if state.cool > 0 then state.cool = state.cool - dt return end
  local city = api.city
  if state.inside then
    local info = city:interior(state.inside)
    if info and (p.x - info.exit[1]) ^ 2 + (p.z - info.exit[2]) ^ 2 < 2.2 * 2.2 then api.leave() end
    return
  end
  if p.car then return end
  local cx, cz = chunkLib.at(p.x, p.z)
  for dz = -1, 1 do
    for dx = -1, 1 do
      local l = ctx.stream:loaded()[chunkLib.key(cx + dx, cz + dz)]
      if l then
        for _, d in ipairs(l.chunk.doors) do
          if d[4] ~= "@exit" and (p.x - d[1]) ^ 2 + (p.z - d[2]) ^ 2 < 1.5 * 1.5 and api.enter(d[4]) then return end
        end
      end
    end
  end
end

function P.update(ctx, dt)
  local api = ctx.a_world
  local state = P.state
  if not api then return end
  local view = api.view
  -- the day
  state.hour = (state.hour + dt * sky.HOURS_PER_SECOND * state.speed) % 24
  local kind, previous = sky.weather.update(state.weather, dt)
  if kind then ctx.bus:emit("weather", { kind = kind, previous = previous }) end
  -- storms flash
  if state.weather.kind == "storm" and state.flash <= 0 and ctx.player and math.random() < dt * 0.12 then state.flash = 0.9 end
  if state.flash > 0 then state.flash = math.max(0, state.flash - dt * 4) end
  local phase = sky.phaseOf(state.hour)
  local hourNow = floor(state.hour)
  if phase ~= state.phase or hourNow ~= state.hourSent then
    state.hourSent = hourNow
    state.phase = phase
    ctx.bus:emit("time_of_day", { hour = state.hour, phase = phase })
  end
  local kindNow = state.weather.kind
  if math.abs(state.hour - state.appliedHour) >= 0.04 or kindNow ~= state.appliedKind or state.flash > 0 or state.flashed then
    state.push(sky.paletteAt(state.hour, kindNow, state.flash))
    state.appliedHour, state.appliedKind = state.hour, kindNow
    state.flashed = state.flash > 0
  end
  view.sky.hour, view.sky.kind, view.sky.flash = state.hour, kindNow, state.flash
  -- where we are
  local pl = ctx.player
  if pl then
    local d = api.districtAt(pl.x, pl.z)
    ctx.districtName = state.inside and (api.city:interior(state.inside) or {}).name or d.name
    doors(ctx, state, api, dt)
  end
end

return P
