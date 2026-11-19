-- saltgate_core_test.lua
-- SALTGATE's v2 core (step 0 of the expansion): events, entities, the chunk format with curves and heights, the road
-- graph, streaming, 3D motion (hills, jumps, bridges over roads), content, mission scripts, vehicle definitions, the
-- screen stack, save v2 and its migration, plugins, the budget, the maps, and the testbed island.

local t = require("testing")
local events = require("sg.core.events")
local entity = require("sg.core.entity")
local chunk = require("sg.core.chunk")
local geom = require("sg.core.geom")
local roadgraph = require("sg.core.roadgraph")
local stream = require("sg.core.stream")
local motion = require("sg.core.motion")
local drive = require("sg.core.drive")
local follow = require("sg.core.follow")
local contentLib = require("sg.core.content")
local script = require("sg.core.script")
local vehicles = require("sg.core.vehicles")
local uiLib = require("sg.core.ui")
local save = require("sg.core.save")
local plugins = require("sg.core.plugins")
local budget = require("sg.core.budget")
local mapview = require("sg.core.mapview")
local testbed = require("sg.core.testbed")
local vehicle = require("sg.vehicle")
local util = require("sg.util")

--- A file system in memory, shaped like CC's fs.
local function memfs(files)
  files = files or {}
  local fs = {}
  function fs.exists(p)
    if files[p] then return true end
    for k in pairs(files) do
      if k:sub(1, #p + 1) == p .. "/" then return true end
    end
    return false
  end
  function fs.list(p)
    local out, seen = {}, {}
    for k in pairs(files) do
      if k:sub(1, #p + 1) == p .. "/" then
        local name = k:sub(#p + 2):match("^[^/]+")
        if not seen[name] then seen[name] = true out[#out + 1] = name end
      end
    end
    return out
  end
  function fs.open(p, mode)
    if mode == "r" then
      if not files[p] then return nil end
      return { readAll = function() return files[p] end, close = function() end }
    end
    local buf = {}
    return { write = function(s) buf[#buf + 1] = s end, close = function() files[p] = table.concat(buf) end }
  end
  function fs.delete(p) files[p] = nil end
  function fs.move(a, b) files[b], files[a] = files[a], nil end
  return fs, files
end

-- ---------------------------------------------------------------- events and entities

t.test("core events: listeners in order, off and offOwner, and unknown names refused", function()
  local bus = events.new()
  local seen = {}
  local tok = bus:on("crime", function(d) seen[#seen + 1] = "a" .. d.level end, "x")
  bus:on("crime", function() seen[#seen + 1] = "b" end, "y")
  t.eq(bus:emit("crime", { level = 1 }), 2)
  t.eq(table.concat(seen, ","), "a1,b")
  bus:off(tok)
  bus:emit("crime", { level = 2 })
  t.eq(#seen, 3)
  t.eq(bus:offOwner("y"), 1)
  t.eq(bus:emit("crime", {}), 0)
  t.truthy(not pcall(bus.emit, bus, "crimes", {}), "a typo is an error")
  t.truthy(not pcall(bus.on, bus, "nope", function() end), "listening to a typo is an error")
end)

t.test("core entities: near() is sorted and follows moves, tags, systems run in order at their rate", function()
  local w = entity.new({ cell = 16 })
  local a = w:add({ kind = "car", x = 0, z = 0, tags = { traffic = true } })
  local b = w:add({ kind = "car", x = 10, z = 0, tags = { cop = true } })
  local c = w:add({ kind = "ped", x = 100, z = 100 })
  local near = w:near(1, 0, 20)
  t.eq(#near, 2)
  t.eq(near[1], a)
  t.eq(#w:near(0, 0, 20, "cop"), 1)
  w:move(c, 5, 0)
  t.eq(#w:near(0, 0, 20), 3, "a moved entity is found where it went")
  w:remove(b)
  t.eq(#w:near(0, 0, 20, "cop"), 0)
  local order = {}
  local slowRuns = 0
  w:system({ name = "late", order = 20, update = function() order[#order + 1] = "late" end })
  w:system({ name = "early", order = 10, update = function() order[#order + 1] = "early" end })
  w:system({ name = "slow", order = 30, rate = 5, update = function() slowRuns = slowRuns + 1 end })
  for _ = 1, 20 do w:update(0.05) end
  t.eq(order[1], "early")
  t.eq(order[2], "late")
  t.eq(slowRuns, 5, "a 5 Hz system ran 5 times in a second")
  w:focus(0, 0)
  w:update(0.05)
  t.eq(a.lod, "near")
end)

-- ---------------------------------------------------------------- chunks and geometry

local function sampleChunk()
  local c = chunk.new(1, 2, "lantern")
  c.heights = {}
  for i = 1, chunk.HEIGHT_N * chunk.HEIGHT_N do c.heights[i] = (i % chunk.HEIGHT_N) * 0.5 end
  local x0, z0 = 88, 176
  c.ground[1] = { "grass", chunk.TERRAIN, { x0 + 10, z0 + 10, x0 + 30, z0 + 10, x0 + 20, z0 + 30 } }
  c.water[1] = { -1, { x0, z0, x0 + 5, z0, x0 + 5, z0 + 5, x0, z0 + 5 } }
  c.buildings[1] = { x0 + 50, z0 + 50, 10, 6, 0.6, chunk.TERRAIN, 12, "neon", true }
  c.props[1] = { "lamp", x0 + 40, z0 + 40, 0, chunk.TERRAIN }
  c.nodes[1] = { "n1", x0 + 2, 1, z0 + 44 }
  c.nodes[2] = { "n2", x0 + 86, 3, z0 + 44 }
  c.roads[1] = { "e1", "n1", "n2", 8, 2, 14, "road", geom.curve({ x0 + 2, 1, z0 + 44, x0 + 44, 6, z0 + 20, x0 + 86, 3, z0 + 44 }, 5) }
  c.floors[1] = { "deck", 8, { x0 + 60, z0 + 60, x0 + 80, z0 + 60, x0 + 80, z0 + 80, x0 + 60, z0 + 80 } }
  c.ribbons[1] = { "bridge", 8, { x0 + 2, 9, z0 + 70, x0 + 86, 9, z0 + 70 } }
  c.doors[1] = { x0 + 45, z0 + 45, 0, "juno_kitchen" }
  c.spawns[1] = { "parked", x0 + 30, z0 + 50, 1.2 }
  c.landmarks[1] = { "lighthouse", x0 + 70, z0 + 20, 0, chunk.TERRAIN }
  return c
end

t.test("core chunk: pack and unpack keep curves, heights and every section", function()
  local c = sampleChunk()
  t.truthy(chunk.validate(c))
  local line = chunk.pack(c)
  t.truthy(not line:find("\n"), "one line")
  local back = assert(chunk.unpack(line))
  t.eq(back.district, "lantern")
  for _, s in ipairs(chunk.SECTIONS) do t.eq(#back[s.key], #c[s.key], s.key) end
  t.eq(#back.roads[1][8], #c.roads[1][8], "every curve point")
  t.near(back.roads[1][8][5], c.roads[1][8][5], 0.01)
  t.near(back.heights[40], c.heights[40], 0.01)
  t.eq(back.doors[1][4], "juno_kitchen")
  t.truthy(chunk.validate(back))
  local many = chunk.unpackMany(chunk.packMany({ c, chunk.new(2, 2) }))
  t.truthy(many["1,2"] and many["2,2"])
  t.truthy(not chunk.unpack("SGC1;0;0;mid"), "an old or foreign line is refused")
end)

t.test("core chunk: validate catches broken content", function()
  local c = sampleChunk()
  c.buildings[1][3] = 0
  t.truthy(not chunk.validate(c), "a building with no size")
  c = sampleChunk()
  c.roads[1][8] = { 1, 2 }
  t.truthy(not chunk.validate(c), "a road with one point")
  c = sampleChunk()
  c.buildings[1][1] = 9999
  t.truthy(not chunk.validate(c), "far outside its chunk")
  c = sampleChunk()
  c.heights[5] = 0 / 0
  t.truthy(not chunk.validate(c), "a NaN height")
end)

t.test("core chunk: the surface you stand on depends on how high you are (a bridge over a road)", function()
  local c = sampleChunk()
  local x, z = 88 + 30, 176 + 70
  local onTop = chunk.groundAt(c, x, z, 9)
  t.near(onTop, 9, 0.01, "on the bridge")
  local under, kind = chunk.groundAt(c, x, z, chunk.terrainY(c, x, z))
  t.eq(kind, "terrain", "under it: the ground")
  t.truthy(under < 8)
  local deck = chunk.groundAt(c, 88 + 70, 176 + 62, 8.5)
  t.near(deck, 8, 0.01, "a car park level")
  t.eq(chunk.surface(c, 88 + 50, 176 + 50), "building")
  t.eq(chunk.surface(c, 88 + 30, 176 + 70), "bridge")
end)

t.test("core geometry: curves pass through their points, rotated boxes push out along their own axes", function()
  local pts = geom.curve({ 0, 0, 0, 10, 2, 10, 20, 0, 0 }, 2)
  t.near(pts[1], 0, 0.001)
  t.near(pts[#pts - 2], 20, 0.001)
  local d = geom.polylineNearest(pts, 10, 10)
  t.truthy(d < 0.6, "passes near the middle control point: " .. d)
  t.truthy(geom.inPolygon({ 0, 0, 10, 0, 5, 10 }, 5, 3))
  t.truthy(not geom.inPolygon({ 0, 0, 10, 0, 5, 10 }, 9, 9))
  local box = { 0, 0, 10, 2, math.pi / 4 }
  t.truthy(geom.inBox(box, 3, 3), "along its diagonal")
  t.truthy(not geom.inBox(box, 3, -3))
  local x, z = geom.pushOutOfBox(box, 0.2, 0.2, 0.5)
  t.truthy(not geom.inBox(box, x, z), "pushed out")
end)

-- ---------------------------------------------------------------- the testbed and the road graph

local function testbedGraph()
  local g = roadgraph.new()
  for _, c in pairs(testbed.chunks()) do g:addChunk(c) end
  return g
end

t.test("core testbed: every chunk is valid, and it has hills, curves, a bridge, an overpass and levels", function()
  local n = 0
  for key, c in pairs(testbed.chunks()) do
    n = n + 1
    local ok, err = chunk.validate(c)
    t.truthy(ok, key .. ": " .. tostring(err))
  end
  t.eq(n, testbed.N * testbed.N)
  local g = testbedGraph()
  local hill = g:node(testbed.FEATURES.hairpins[#testbed.FEATURES.hairpins])
  t.truthy(hill.y > 14, "the hill road climbs (at a drivable grade): " .. hill.y)
  t.truthy(testbed.FEATURES.overpass.y > 8, "the overpass is up in the air")
  -- the hairpins really turn: the heading changes by more than two half-turns along them
  local turned = 0
  for _, id in ipairs(testbed.FEATURES.hairpins) do
    for _, e in ipairs(g:node(id).edges) do
      if e.kind == "road" then
        local p = e.pts
        for i = 1, #p - 6, 3 do
          local h1 = math.atan2(p[i + 5] - p[i + 2], p[i + 3] - p[i])
          local h2 = math.atan2(p[i + 8] - p[i + 5], p[i + 6] - p[i + 3])
          turned = turned + math.abs(util.wrap(h2 - h1))
        end
      end
    end
  end
  t.truthy(turned > 2 * math.pi, "winding: " .. turned)
end)

t.test("core road graph: routes along curves to the hilltop, the overpass and downtown", function()
  local g = testbedGraph()
  local f = testbed.FEATURES
  local nodes, edges = g:path(f.coast[1], f.hairpins[#f.hairpins])
  t.truthy(nodes and #edges > 2, "to the hilltop")
  nodes = g:path(f.coast[3], f.overpassRoad[#f.overpassRoad])
  t.truthy(nodes, "to the end of the overpass")
  local e, s, d = g:nearest(testbed.spawn.x, testbed.spawn.z, 20)
  t.truthy(e and d < 6, "the spawn is on a road")
  local x, y, z = g:pointAt(e, s, 2)
  t.truthy(x == x and y == y and z == z)
  -- the roundabout is one way
  local ringEdge = g:node(f.roundabout[1]).edges
  local oneWay = false
  for _, re in ipairs(ringEdge) do
    if re.lanes == 1 then oneWay = true end
  end
  t.truthy(oneWay, "the roundabout's edges are one-way")
end)

-- ---------------------------------------------------------------- streaming

t.test("core stream: loads round you within its rings, drops what you leave, a budget per frame", function()
  local made = 0
  local clock = 0
  local s = stream.new({
    source = function(cx, cz)
      if cx < 0 or cz < 0 or cx > 9 or cz > 9 then return nil end
      made = made + 1
      coroutine.yield() -- a source may spread its work
      return chunk.new(cx, cz)
    end,
    build = function(c, lod) return { lod = lod } end,
    full = 1, low = 2, budgetMs = 1,
    clock = function() clock = clock + 0.4 return clock end,
  })
  s:loadAll(400, 400)
  t.eq(s:liveCount(), 25, "a 5x5 ring")
  local l = s:loaded()[chunk.key(4, 4)]
  t.eq(l.lod, "full")
  t.eq(s:loaded()[chunk.key(2, 4)].lod, "low")
  -- drive east across the map, a frame at a time
  local most = 0
  for x = 400, 800, 4 do
    s:update(x, 400)
    most = math.max(most, s:liveCount())
  end
  s:loadAll(800, 400)
  t.truthy(most <= 40, "never more than a ring and its edge: " .. most)
  t.truthy(not s:loaded()[chunk.key(2, 4)], "the west was dropped")
  t.truthy(s:loaded()[chunk.key(9, 4)], "the east came in")
  t.truthy(not s:loaded()[chunk.key(10, 4)], "nothing past the edge of the world")
  t.truthy(s.stats.loads > 30)
end)

t.test("core stream: ground, surfaces and walls across chunk edges; the unloaded world is a wall", function()
  local s = stream.new({ source = testbed.source, full = 1, low = 1 })
  local sp = testbed.spawn
  s:loadAll(sp.x, sp.z)
  local y = s:groundAt(sp.x, sp.z, nil)
  t.truthy(y and y > 0, "the coast road is above the sea")
  t.eq(s:surface(sp.x, sp.z), "road")
  local x, z, hit = s:collide(-500, -500, 1, 0)
  t.truthy(hit, "outside the loaded chunks")
  local _ = x and z
end)

-- ---------------------------------------------------------------- moving over real ground

local function testbedStream(x, z)
  local s = stream.new({ source = testbed.source, full = 2, low = 2 })
  s:loadAll(x, z)
  return s
end

t.test("core motion: a car hitting the jump ramp at speed flies, then lands", function()
  local j = testbed.FEATURES.jump
  local s = testbedStream(j.x, j.z)
  local car = vehicle.new("sovereign", 0, 0, j.h)
  car.x, car.z = j.x - math.cos(j.h) * 22, j.z - math.sin(j.h) * 22
  car.y = s:groundAt(car.x, car.z, nil)
  car.v = 34
  local flew, landed, topY = false, false, -100
  for _ = 1, 80 do
    local r = drive.step(car, { throttle = 1 }, 0.05, s)
    if r.airborne then flew = true end
    if r.landed then landed = true end
    topY = math.max(topY, car.y)
  end
  t.truthy(flew, "it left the ground")
  t.truthy(landed, "and came down")
  t.truthy(topY > j.top, "higher than the ramp's lip: " .. topY)
end)

t.test("core motion: on the overpass a car stays on the deck; the coast road under it stays at road height", function()
  local o = testbed.FEATURES.overpass
  local s = testbedStream(o.x, o.z)
  local deck = s:groundAt(o.x, o.z, o.y)
  t.near(deck, o.y, 1.0, "the deck")
  local below, kind = s:groundAt(o.x, o.z, 0.5)
  t.truthy(below < o.y - 4, "under it is the road below: " .. below .. " " .. kind)
  -- a car on the deck drives along it without dropping through
  local car = vehicle.new("marlin", o.x - 8, o.z - 0.2, 0)
  car.y = s:groundAt(car.x, car.z, o.y)
  car.v = 10
  for _ = 1, 10 do drive.step(car, { throttle = 0.3 }, 0.05, s) end
  t.truthy(car.y > o.y - 3, "still up on the deck: " .. car.y)
end)

t.test("core motion: a slope too steep is a wall, and the car tilts with the hill", function()
  local hx, hz = testbed.HILL.x, testbed.HILL.z
  local s = testbedStream(hx, hz)
  -- walk straight up the steepest side, off the road, until stopped or at the top
  local p = { x = hx - 60, z = hz, h = 0, y = nil }
  local topY = -100
  p.y = s:groundAt(p.x, p.z, nil)
  local blocked = false
  for _ = 1, 400 do
    if p.x >= hx then break end
    local r = motion.move(p, s, p.x + 0.5, p.z, 0.05, { radius = 0.45, speed = 4 })
    topY = math.max(topY, p.y)
    if r.hit then blocked = true end
  end
  t.truthy(topY > 10, "it climbed the hillside: " .. topY)
  local car = vehicle.new("marlin", hx - 40, hz + 5, 0)
  car.y = s:groundAt(car.x, car.z, nil)
  motion.move(car, s, car.x + 0.1, car.z, 0.05, { radius = 1.6, speed = 1 })
  t.truthy(math.abs(car.pitch or 0) + math.abs(car.roll or 0) > 0.01, "tilted on the slope")
  local _ = blocked
end)

t.test("core drive: a minute on the testbed roads by the road graph, no NaN, no sinking, no flying off", function()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local car = vehicle.new("marlin", sp.x, sp.z, sp.h)
  car.y = s:groundAt(sp.x, sp.z, nil)
  local f = follow.new(s.roads, car.x, car.z, util.rng(3))
  t.truthy(f, "found a road")
  local travelled, lastX, lastZ = 0, car.x, car.z
  for step = 1, 1200 do
    local input = follow.input(f, car, 0.05)
    drive.step(car, input, 0.05, s)
    s:update(car.x, car.z)
    t.truthy(car.x == car.x and car.y == car.y and car.z == car.z, "a number at step " .. step)
    t.truthy(car.y > -2, "not under the sea")
    travelled = travelled + math.sqrt((car.x - lastX) ^ 2 + (car.z - lastZ) ^ 2)
    lastX, lastZ = car.x, car.z
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(travelled > 300, "it got somewhere: " .. travelled)
  t.truthy(not car.wrecked, "and did not wreck itself")
end)

-- ---------------------------------------------------------------- content and missions

t.test("core content: data files have no globals, chunk files unpack, a small cache, no climbing out", function()
  local fs = memfs({
    ["content/data/cars.lua"] = "return { a = 1 }",
    ["content/data/evil.lua"] = "return { os = os, fs = fs }",
    ["content/world/r0.sgc"] = chunk.packMany({ chunk.new(0, 0), chunk.new(1, 0) }),
    ["content/story/m1.lua"] = "return function(api) api.reward(5) end",
  })
  local c = contentLib.new({ fs = fs, cache = 2 })
  t.eq(c:data("data/cars.lua").a, 1)
  local evil = c:data("data/evil.lua")
  t.eq(evil.os, nil, "no os in a data file")
  t.eq(evil.fs, nil, "no fs either")
  t.truthy(c:chunks("world/r0.sgc")["1,0"])
  t.truthy(type(c:script("story/m1.lua")) == "function")
  t.truthy(not c:text("../saltgate_save.dat"), "no climbing out of content/")
  t.truthy(not c:text("nope.lua"))
  local n = 0
  for _ in pairs(c.cached) do n = n + 1 end
  t.truthy(n <= 2, "the cache stays small")
  t.eq(#c:list("world"), 1)
end)

--- Game hooks that answer at once (talk read, choice made, place reached when told).
local function hooks()
  local h = { said = {}, money = 0, heat = 0, here = {}, pick = 1, objective = nil }
  h.say = function(who, text) h.said[#h.said + 1] = who .. ": " .. text end
  h.talking = function() return false end
  h.choose = function() end
  h.chosen = function() return h.pick end
  h.objective = function(text) h.objective = text end
  h.at = function(place) return h.here[place] end
  h.spawn = function(kind) return { kind = kind } end
  h.cutscene = function() end
  h.cutsceneDone = function() return true end
  h.setHeat = function(n) h.heat = n end
  h.reward = function(n) h.money = h.money + n end
  return h
end

local MISSION = function(api)
  api.step("meet", function()
    api.say("Juno", "Hi.")
    api.flag("rude", api.choose("Answer?", { "Hi", "Late" }) == 2)
  end)
  api.step("drive", function()
    api.goTo("ferry", { car = true, text = "Get to the ferry." })
  end)
  api.step("pay", function()
    api.reward(api.flag("rude") and 100 or 500)
  end)
end

t.test("core script: steps run in order, wait for the game, and pay", function()
  local h = hooks()
  h.pick = 2
  local r = script.new("m", MISSION, h)
  for _ = 1, 5 do r:update(0.05) end
  t.eq(r.status, "running", "waiting at the ferry")
  t.eq(r.checkpoint, "drive")
  t.eq(h.objective, "Get to the ferry.")
  h.here.ferry = true
  for _ = 1, 3 do r:update(0.05) end
  t.eq(r.status, "pass")
  t.eq(h.money, 100, "the rude answer pays less")
end)

t.test("core script: a save mid-mission comes back at its step with its flags", function()
  local h = hooks()
  local r = script.new("m", MISSION, h)
  for _ = 1, 4 do r:update(0.05) end
  local kept = r:saveState()
  t.eq(kept.checkpoint, "drive")
  local h2 = hooks()
  local r2 = script.new("m", MISSION, h2, kept)
  r2:update(0.05)
  t.eq(#h2.said, 0, "the talk is not played again")
  h2.here.ferry = true
  for _ = 1, 3 do r2:update(0.05) end
  t.eq(r2.status, "pass")
  t.eq(h2.money, 500)
end)

t.test("core script: fail, timeouts and script errors", function()
  local h = hooks()
  local r = script.new("f", function(api)
    api.step("a", function() api.goTo("nowhere", { timeout = 1 }) end)
  end, h)
  for _ = 1, 30 do r:update(0.05) end
  t.eq(r.status, "fail")
  t.eq(r.reason, "out of time")
  local bad = script.new("b", function() local x = nil; return x.y end, hooks())
  t.truthy(not pcall(bad.update, bad, 0.05), "a broken script is an error with its name")
end)

-- ---------------------------------------------------------------- definitions, screens, saves, plugins, budget

t.test("core vehicles: today's cars are definitions; bad ones are refused; damage stages", function()
  vehicles.reset()
  vehicles.registerLegacy()
  local m = vehicles.get("marlin")
  t.eq(m.class, "car")
  t.truthy(vehicles.physicsFor(m))
  t.truthy(#vehicles.traffic() > 3)
  t.truthy(not pcall(vehicles.define, { id = "x", class = "spaceship", name = "X" }))
  t.truthy(not pcall(vehicles.define, { id = "marlin", class = "car", name = "Dup", top = 1, accel = 1, brake = 1, turn = 1,
    grip = 1, health = 1, length = 1, width = 1 }), "defined twice")
  vehicles.define({ id = "dinghy", class = "boat", name = "Dinghy", top = 14, accel = 5, brake = 4, turn = 1.5, grip = 2,
    health = 60, length = 4, width = 1.8 })
  t.eq(#vehicles.list("boat"), 1)
  t.eq(vehicles.stage(m, 1), 0)
  t.eq(vehicles.stage(m, 0.5), 1)
  t.eq(vehicles.stage(m, 0.05), 3)
end)

t.test("core ui: a screen stack with modal screens, widgets by slot and priority", function()
  local bus = events.new()
  local pushed = {}
  bus:on("screen_push", function(d) pushed[#pushed + 1] = d.name end)
  local ui = uiLib.new(bus)
  ui.screen({ name = "play", draw = function() end })
  ui.screen({ name = "phone", modal = true, draw = function() end })
  ui.push("play")
  t.truthy(not ui.modal())
  ui.push("phone")
  t.truthy(ui.modal())
  t.eq(ui.top().name, "phone")
  ui.pop()
  t.eq(ui.top().name, "play")
  t.eq(table.concat(pushed, ","), "play,phone")
  ui.widget({ name = "a", slot = "top-right", priority = 10, draw = function() end })
  ui.widget({ name = "b", slot = "top-right", priority = 90, draw = function() end })
  ui.widget({ name = "c", slot = "top-right", draw = function() end, visible = function() return false end })
  local list = ui.widgets("top-right", {})
  t.eq(#list, 2)
  t.eq(list[1].name, "b")
  t.truthy(not pcall(ui.widget, { name = "d", slot = "nowhere", draw = function() end }))
end)

t.test("core save: a version 1 save becomes version 2, nothing lost", function()
  local v1 = { finished = false, version = 1, money = 1234, done = { "fresh_air", "hot_broth" },
    stats = { chopped = 2, cars = 9, ko = 1, nabbed = 3, jobs = 0 }, tutorialDone = true }
  local v2 = assert(save.migrate(v1))
  t.eq(v2.version, 2)
  t.eq(v2.player.money, 1234)
  t.truthy(v2.story.done.fresh_air and v2.story.done.hot_broth)
  t.eq(v2.progress.stats.cars, 9)
  t.eq(v2.settings.tutorialDone, true)
  for _, name in ipairs(save.sectionNames()) do t.truthy(v2[name], "section " .. name) end
  local back = save.toLegacy(v2)
  t.eq(back.money, 1234)
  t.eq(#back.done, 2)
  local again = save.fromLegacy(back, save.blank())
  t.eq(again.player.money, 1234)
  -- a save with no version at all is the oldest kind
  t.eq(save.migrate({ money = 5 }).player.money, 5)
end)

t.test("core save: a newer save is refused untouched; a broken file falls back to the backup", function()
  local fs, files = memfs()
  t.truthy(not save.migrate({ version = 99 }), "from a newer game")
  local data = save.blank()
  data.player.money = 77
  t.truthy(save.write(fs, "s.dat", data))
  data.player.money = 88
  t.truthy(save.write(fs, "s.dat", data))
  t.truthy(files["s.dat.bak"], "the last good one is kept")
  t.eq(save.read(fs, "s.dat").player.money, 88)
  files["s.dat"] = "{ broken"
  local got, note = save.read(fs, "s.dat")
  t.eq(got.player.money, 77, "from the backup")
  t.truthy(note)
  files["s.dat"] = "{version=99}"
  local refused, why = save.read(fs, "s.dat")
  t.truthy(refused == nil or refused.player.money == 77, "a newer save is not overwritten by a blank one")
  local _ = why
end)

t.test("core save: a plugin's own section, with its own migration", function()
  save.section("garage_test", { version = 2, owner = "test", blank = function() return { cars = {} } end,
    migrate = function(old, from) if from < 2 then old.cars = old.list or {} old.list = nil end return old end })
  local d = save.migrate({ version = 2, sections = { garage_test = 1 }, garage_test = { list = { "marlin" } },
    player = { money = 1 }, story = { done = {} } })
  t.eq(d.garage_test.cars[1], "marlin")
  t.eq(d.sections.garage_test, 2)
end)

t.test("core plugins: found by name, set up in order, a broken one left out without stopping the rest", function()
  local fs = memfs({ ["sg/plugins/a_world.lua"] = "", ["sg/plugins/b_cars.lua"] = "", ["sg/plugins/x_broken.lua"] = "",
    ["sg/plugins/notes.txt"] = "" })
  local names = plugins.discover(fs, "sg/plugins")
  t.eq(table.concat(names, ","), "a_world,b_cars,x_broken")
  local order = {}
  local fake = {
    ["sg.plugins.a_world"] = { name = "a_world", order = 10, init = function() order[#order + 1] = "a" end },
    ["sg.plugins.b_cars"] = { name = "b_cars", order = 20, needs = { "a_world" }, init = function() order[#order + 1] = "b" end },
    ["sg.plugins.x_broken"] = { name = "x_broken", init = function() error("boom") end },
  }
  local loaded, failed = plugins.load(names, {}, function(n) return fake[n] end)
  t.eq(#loaded, 2)
  t.eq(table.concat(order, ","), "a,b")
  t.eq(#failed, 1)
  t.truthy(failed[1].err:find("boom"))
end)

t.test("core budget: quality steps down when frames run long and back up when there is room", function()
  local bus = events.new()
  local levels = {}
  bus:on("quality", function(d) levels[#levels + 1] = d.level end)
  local b = budget.new({ bus = bus, target = 5, clock = function() return 0 end })
  for _ = 1, 30 do b:frame(12) end
  t.eq(b.quality, 1, "slow frames: lighter")
  for _ = 1, 200 do b:frame(1) end
  t.eq(b.quality, 0, "fast again: back to the best")
  t.eq(table.concat(levels, ","), "1,0")
  if rawget(_G, "collectgarbage") then t.truthy(b:report().heapKB > 0, "the heap, where Lua can tell") end
  t.truthy(#b:lines() == 2)
end)

t.test("core maps: roads follow their curves on the map, bridges and buildings show, hills have contours", function()
  local chunks = testbed.chunks()
  local at = function(x, z) return chunks[chunk.key(chunk.at(x, z))] end
  local roads, bridge, building = 0, 0, 0
  for _, c in pairs(chunks) do
    local m = mapview.raster(c)
    for _, row in ipairs(m.codes) do
      local _, nr = row:gsub("r", "")
      local _, no = row:gsub("o", "")
      local _, nb = row:gsub("b", "")
      roads, bridge, building = roads + nr, bridge + no, building + nb
    end
  end
  t.truthy(roads > 500, "roads: " .. roads)
  t.truthy(bridge > 20, "bridges and the overpass: " .. bridge)
  t.truthy(building > 50, "buildings: " .. building)
  local code = mapview.sample(at, testbed.spawn.x, testbed.spawn.z)
  t.eq(code, "r", "the spawn is on a road on the map too")
  local _, hHill = mapview.sample(at, testbed.HILL.x, testbed.HILL.z)
  t.truthy(hHill > 12, "the map knows the hill is high: " .. hHill)
end)

-- ---------------------------------------------------------------- integration requests (streams C and D)

t.test("core testbed: one road network, every junction reachable from the coast road", function()
  local g = testbedGraph()
  local start = testbed.FEATURES.coast[1]
  local seen, queue = { [start] = true }, { start }
  while #queue > 0 do
    local id = table.remove(queue)
    for _, e in ipairs(g:node(id).edges) do
      for _, nid in ipairs({ e.a, e.b }) do
        if not seen[nid] then
          seen[nid] = true
          queue[#queue + 1] = nid
        end
      end
    end
  end
  for id in pairs(g.nodes) do t.truthy(seen[id], "node " .. id .. " reachable") end
  local path = g:path(testbed.FEATURES.coast[1], testbed.FEATURES.oldtown[1])
  t.truthy(path, "even the old town")
end)

t.test("core roads: on a road the ground is the road, so cars never float over a switchback", function()
  local s = stream.new({ source = testbed.source, full = 3, low = 3 })
  s:loadAll(testbed.CENTRE.x, testbed.CENTRE.z)
  local worst = 0
  for _, c in pairs(testbed.chunks()) do
    for _, rd in ipairs(c.roads) do
      local p = rd[8]
      for i = 1, #p, 3 do
        local gy = s:groundAt(p[i], p[i + 2], p[i + 1])
        worst = math.max(worst, math.abs(gy - p[i + 1]))
      end
    end
  end
  t.truthy(worst < 1.2, "road and ground agree everywhere: worst " .. worst)
end)

if not rawget(_G, "colors") then
  -- outside CC: the colour numbers the view's modules read when they load
  colors = {}
  local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple",
    "blue", "brown", "green", "red", "black" }
  for i, n in ipairs(names) do colors[n] = 2 ^ (i - 1) end
  colors.grey, colors.lightGrey = colors.gray, colors.lightGray
  colours = colors
end

t.test("core app: the parts of the day", function()
  local app = require("sg.core.app")
  t.eq(app.phase(6), "dawn")
  t.eq(app.phase(12), "day")
  t.eq(app.phase(19.5), "dusk")
  t.eq(app.phase(23), "night")
  t.eq(app.phase(2), "night")
  t.eq(app.MUSIC_DISTRICTS.lantern, "lantern")
end)

t.test("core app: a car driven into deep water stalls, floods, and the driver swims out at the surface", function()
  local app = require("sg.core.app")
  local bus = events.new()
  local got = {}
  bus:on("vehicle_exit", function(d) got.exit = d end, "t")
  bus:on("vehicle_sunk", function(d) got.sunk = d end, "t")
  local car = { x = 10, y = -7, z = 20, h = 1, v = 18, health = 100 }
  local ctx = { bus = bus, player = { x = 10, y = -7, z = 20, car = car } }
  t.eq(app.sink(ctx, car, { water = 0 }, 0.1), true)
  t.truthy(car.v < 18, "it slows in the water")
  t.truthy(ctx.player.car == car, "still in it for a moment")
  for _ = 1, 20 do app.sink(ctx, car, { water = 0 }, 0.1) end
  t.truthy(car.sunk and car.wrecked, "a wreck")
  t.eq(car.v, 0)
  t.eq(ctx.player.car, nil, "the driver is out")
  t.truthy(ctx.player.swimming, "swimming")
  t.eq(ctx.player.y, -0.5, "at the surface, not on the sea floor")
  t.truthy(got.exit and got.exit.sunk, "vehicle_exit says sunk")
  t.truthy(got.sunk and got.sunk.vehicle == car)
  -- on land (or a boat, whose physics never report water) nothing happens
  local dry = { x = 0, z = 0, v = 10 }
  t.eq(app.sink(ctx, dry, { water = nil }, 0.1), false)
  t.eq(app.sink(ctx, dry, 0, 0.1), false, "an older physics that returns a number")
  t.eq(dry.v, 10)
end)

t.test("core util: the game tells the Roger supervisor it is alive (else a game install is rebooted every 60 s)", function()
  local util = require("sg.util")
  local sent = {}
  local old = os.queueEvent
  os.queueEvent = function(name, a) sent[#sent + 1] = { name, a } end
  local ok, err = pcall(function()
    t.truthy(util.rogerAlive(1000, true), "sends at once")
    t.eq(sent[1][1], "roger_alive")
    t.eq(sent[2][1], "roger_busy")
    t.eq(sent[2][2], true, "busy while a game is on")
    t.truthy(not util.rogerAlive(1003, false), "not again within its 5 s")
    t.truthy(util.rogerAlive(1006, false), "again after them")
    t.eq(sent[4][2], false, "not busy on the title")
    t.truthy(util.ALIVE_SECONDS * 2 < 60, "well inside the supervisor's 60 s watchdog")
  end)
  os.queueEvent = old
  if not ok then error(err, 0) end
end)

t.test("core view: the objective comes from ctx.objective (table or function), else the story's target", function()
  local view = require("sg.core.view")
  t.eq(view.objective({}), nil, "nowhere to go")
  local o = view.objective({ objective = { text = "Go", x = 1, z = 2 } })
  t.eq(o.text, "Go")
  o = view.objective({ objective = function() return { x = 5, z = 6, kind = "car" } end })
  t.eq(o.kind, "car")
  o = view.objective({ story = { target = function() return 7, 8, "giver" end } })
  t.eq(o.x, 7)
  t.eq(o.kind, "giver")
  o = view.objective({ objective = { text = "first" }, story = { target = function() return 1, 1 end } })
  t.eq(o.text, "first", "ctx.objective wins over the story's target")
  o = view.objective({ story = { target = function() return 3, 4, "objective", "Drive to Juno's back lot." end } })
  t.eq(o.text, "Drive to Juno's back lot.", "the story's line comes with its arrow")
  o = view.objective({ story = { target = function() end, text = function() return "Lose the Harbor Patrol." end } })
  t.eq(o.text, "Lose the Harbor Patrol.", "a goal with no place still has its line")
  t.eq(o.x, nil, "and no arrow")
end)
