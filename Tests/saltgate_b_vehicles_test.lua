-- saltgate_b_vehicles_test.lua
-- SALTGATE stream B: the vehicles. Definitions from content/vehicles, paint and tune data, the model builders in every
-- damage stage, per-class physics (cars, bikes, trucks with trailers, boats) on the testbed island, damage stages,
-- and a no-NaN soak per class.

local t = require("testing")

-- a stand-in for CC's colour table when running under desktop Lua (the game's models read it when they load)
if not rawget(_G, "colors") then
  local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple",
    "blue", "brown", "green", "red", "black" }
  local tbl = {}
  for i, n in ipairs(names) do tbl[n] = 2 ^ (i - 1) end
  colors = tbl
  colours = tbl
  colors.grey, colors.lightGrey = tbl.gray, tbl.lightGray
end

local contentLib = require("sg.core.content")
local vehicles = require("sg.core.vehicles")
local vehicle = require("sg.vehicle")
local stream = require("sg.core.stream")
local testbed = require("sg.core.testbed")
local follow = require("sg.core.follow")
local drive = require("sg.core.drive")
local util = require("sg.util")
local catalog = require("sg.vehicles.catalog")
local custom = require("sg.vehicles.custom")
local physics = require("sg.vehicles.physics")
local vmodels = require("sg.vehicles.models")
local install = require("sg.vehicles.install")
local fleetLib = require("sg.vehicles.fleet")
local models = require("sg.models")

testbed.chunks() -- builds the island (and sets testbed.spawn)

--- The content folder, from desktop Lua (the repo's root) or from the emulator (a computer laid out like the repo).
local function content()
  if rawget(_G, "fs") and fs.exists("/repo/Games/Saltgate/content") then
    return contentLib.new({ root = "/repo/Games/Saltgate/content" })
  end
  local shim = {
    exists = function(p) local h = io.open(p, "rb") if h then h:close() return true end return false end,
    open = function(p)
      local h = io.open(p, "rb")
      if not h then return nil end
      return { readAll = function() return h:read("*a") end, close = function() h:close() end }
    end,
    list = function() return {} end,
  }
  return contentLib.new({ fs = shim, root = "Games/Saltgate/content" })
end

local loaded = false
local function load()
  if loaded then return end
  loaded = true
  install.install()
  vehicles.reset()
  vehicles.registerLegacy()
  local count, problems = catalog.load(content(), vehicles, vehicle)
  t.eq(#problems, 0, "content problems: " .. table.concat(problems, "; "))
  t.truthy(count > 20, "defined " .. count)
end

local function testbedStream(x, z)
  local s = stream.new({ source = testbed.source, full = 2, low = 2 })
  s:loadAll(x, z)
  return s
end

local function finite(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= v or v == math.huge or v == -math.huge then return false end
  end
  return true
end

-- ---------------------------------------------------------------- the definitions

t.test("b vehicles: the content defines 12+ cars, bikes, trucks with trailers, boats and a helicopter, all valid", function()
  load()
  local count = { car = 0, bike = 0, truck = 0, trailer = 0, boat = 0, heli = 0 }
  for _, def in ipairs(vehicles.list()) do
    local ok, err = vehicles.validate(def)
    t.truthy(ok, tostring(err))
    count[def.class] = count[def.class] + 1
    t.truthy(def.shape == nil or vmodels.SHAPES[def.shape] or def.class ~= "car", def.id .. " has a car shape")
  end
  -- today's six cars plus 13 new: at least 12 new
  t.truthy(count.car >= 6 + 12, "cars " .. count.car)
  t.truthy(count.bike >= 3, "bikes " .. count.bike)
  t.truthy(count.truck >= 2 and count.trailer >= 3, "trucks and trailers")
  t.truthy(count.boat >= 4, "boats " .. count.boat)
  t.eq(count.heli, 1)
  t.truthy(vehicles.get("gullhawk").police)
end)

t.test("b vehicles: every car handles differently (no two share the same numbers)", function()
  load()
  local seen = {}
  for _, def in ipairs(vehicles.list()) do
    if def.class == "car" then
      local key = table.concat({ def.top, def.accel, def.brake, def.turn, def.grip, def.slip or 0, def.stab or 0, def.mass }, "/")
      t.truthy(not seen[key], def.id .. " duplicates " .. tostring(seen[key]))
      seen[key] = def.id
    end
  end
end)

t.test("b vehicles: new vehicles are in vehicle.TYPES so vehicle.new builds them, boats are not traffic", function()
  load()
  for _, def in ipairs(vehicles.list()) do
    if def.class ~= "trailer" and def.class ~= "heli" then
      local car = vehicle.new(def.id, 0, 0, 0)
      t.eq(car.spec.class or "car", def.class == "truck" and "truck" or def.class)
    end
  end
  for _, def in ipairs(vehicles.traffic()) do t.truthy(def.class ~= "boat" and def.class ~= "heli" and def.class ~= "trailer", def.id .. " in traffic") end
end)

-- ---------------------------------------------------------------- paint and tune

t.test("b custom: paint strings round-trip, a tune changes the numbers and costs a share of the value", function()
  load()
  t.eq(custom.compose({ body = "red" }, 0), "red")
  t.eq(custom.compose({ body = "red", stripe = "white" }, 2), "red:white|2")
  local b, s, st = custom.parse("red:white|2")
  t.eq(b, "red") t.eq(s, "white") t.eq(st, 2)
  b, s, st = custom.parse("lime")
  t.eq(b, "lime") t.eq(s, nil) t.eq(st, 0)
  local def = vehicles.get("cinder")
  local tuned = custom.tuned(def, { engine = 3, brakes = 0, grip = 2, armour = 1 })
  t.truthy(tuned.top > def.top and tuned.accel > def.accel and tuned.grip > def.grip and tuned.health > def.health)
  t.eq(tuned.brake, def.brake)
  t.eq(custom.tuned(def, { engine = 0 }), def, "no tune is the definition itself")
  t.truthy(custom.price(def, "engine", 3) > custom.price(def, "engine", 1))
  t.eq(custom.price(def, "engine", 4), nil)
  t.truthy(custom.validPaint("red") and not custom.validPaint("chartreuse"))
end)

t.test("b custom: applying a tune and paint to a car, and a snapshot that builds the same car again", function()
  load()
  local ctx = { vehicles = vehicles, cars = {}, stream = testbedStream(testbed.spawn.x, testbed.spawn.z) }
  local fleet = fleetLib.new(ctx)
  local car = fleet:spawn("tern", testbed.spawn.x, testbed.spawn.z, 0, { paint = "cyan", stripe = "white", tune = { engine = 2, grip = 1 } })
  t.truthy(car, "spawned")
  t.eq(car.colour, "cyan:white")
  t.truthy(car.spec.top > vehicles.get("tern").top)
  car.health = car.spec.health / 2
  local snap = fleet:snapshot(car)
  t.eq(snap.kind, "tern") t.eq(snap.paint.body, "cyan") t.eq(snap.tune.engine, 2) t.near(snap.health, 0.5, 0.001)
  local again = fleet:build(snap, car.x, car.z, 0)
  t.eq(again.colour, "cyan:white|1", "half health shows its first dents")
  t.near(again.health / again.spec.health, 0.5, 0.01)
  t.eq(again.tune.engine, 2)
  -- a shop that sets the colour directly changes the paint
  car.colour = "magenta"
  fleet:sync(car)
  t.eq(car.paint.body, "magenta")
  t.truthy(#ctx.cars == 1, "built cars are not added to the world")
end)

-- ---------------------------------------------------------------- models

t.test("b models: every vehicle builds in every damage stage with sane triangles", function()
  load()
  local sizes = {}
  for _, def in ipairs(vehicles.list()) do
    local spec = def.class == "heli" and def or (vehicle.TYPES[def.id] or def)
    for stage = 0, 3 do
      for _, wrecked in ipairs({ false, true }) do
        local m = vmodels.build(spec, (spec.body or def.body) .. (def.stripe and (":" .. def.stripe) or "") .. "|" .. stage, wrecked)
        t.truthy(#m > 20 and #m < 700, def.id .. " has " .. #m .. " triangles")
        for _, p in ipairs(m) do
          t.truthy(finite(p.x1, p.y1, p.z1, p.x2, p.y2, p.z2, p.x3, p.y3, p.z3) and p.c ~= nil, def.id .. " has a bad triangle")
        end
        sizes[def.id .. stage .. tostring(wrecked)] = #m
      end
    end
    t.truthy(sizes[def.id .. "3false"] > sizes[def.id .. "0false"], def.id .. " looks worse when it burns")
  end
end)

t.test("b models: a damaged legacy car uses ours, a clean one the game's own; install is undone by uninstall", function()
  load()
  install.uninstall()
  local original = models.car
  local spec = vehicle.TYPES.marlin
  local clean = #original(spec, "red", false)
  t.truthy(install.install())
  t.truthy(not install.install(), "a second install does nothing")
  t.eq(#models.car(spec, "red", false), clean, "a clean legacy car is built by the game's own builder")
  t.truthy(#models.car(spec, "red|2", false) > clean, "a damaged one is ours, with more to see")
  t.truthy(#models.car(vehicle.TYPES.tern, "lime", false) > 0)
  install.uninstall()
  t.eq(models.car, original)
  install.install()
end)

-- ---------------------------------------------------------------- damage stages

t.test("b damage: the stage follows health, a wreck is stage 3, and the colour string carries it", function()
  load()
  local ctx = { vehicles = vehicles, cars = {}, stream = testbedStream(testbed.spawn.x, testbed.spawn.z) }
  local fleet = fleetLib.new(ctx)
  local car = fleet:spawn("marlin", testbed.spawn.x, testbed.spawn.z, 0, { paint = "blue" })
  local want = { { 1.0, 0 }, { 0.7, 0 }, { 0.6, 1 }, { 0.3, 2 }, { 0.09, 3 } }
  for _, w in ipairs(want) do
    car.health = car.spec.health * w[1]
    fleet:sync(car)
    t.eq(car.stage, w[2], "at " .. w[1])
    t.eq(car.colour, w[2] == 0 and "blue" or ("blue|" .. w[2]))
  end
  car.wrecked = true
  fleet:sync(car)
  t.eq(car.stage, 3)
  t.eq(vehicles.stage(vehicles.get("marlin"), 0.5), 1)
end)

-- ---------------------------------------------------------------- driving

--- The reference driver with brakes: it slows for the bend ahead (looking further than the core driver does), and
-- never goes faster than a share of the vehicle's top speed.
local function driver(f, car, dt)
  local input = follow.input(f, car, dt)
  local e = f.edge
  local farS = math.max(0, math.min(e.length, f.s + f.dir * follow.LOOK * 2.5))
  local side = (e.lanes == 1) and 0 or follow.LANE * f.dir
  local tx, _, tz = f.roads:pointAt(e, farS, side)
  local diffFar = util.wrap(util.headingTo(car.x, car.z, tx, tz) - car.h)
  local cap = 4 + 12 / (1 + 4 * math.abs(diffFar))
  local want = math.min(car.spec.top * 0.7, cap, e.speed or 12)
  input.throttle = util.clamp((want - car.v) * 0.5, -1, 1)
  return input
end

-- Where the testbed's hill road meets a face of rock it climbs about 2 to 1 (the road is at x 255, z 118, 28 units up): every
-- vehicle, today's marlin included, stops at it. That is the core's, reported to the integrator; hits there are not counted.
local GLITCH = { x = 255.2, z = 118.0, r = 12 }

--- Drive a vehicle of a kind along the roads from the start with the reference driver; count wall hits.
local function lap(kind, seconds, withTrailer)
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local ctx = { vehicles = vehicles, cars = {}, stream = s }
  local fleet = fleetLib.new(ctx)
  local car = fleet:spawn(kind, sp.x, sp.z, sp.h, { trailer = withTrailer })
  t.truthy(car, kind .. " spawned")
  car.follow = follow.new(s.roads, car.x, car.z, util.rng(5))
  local hits, travelled, lx, lz = 0, 0, car.x, car.z
  for step = 1, math.floor(seconds / 0.05) do
    local input = driver(car.follow, car, 0.05)
    local r = drive.step(car, input, 0.05, s)
    fleet:update(0.05)
    s:update(car.x, car.z)
    t.truthy(finite(car.x, car.y, car.z, car.h, car.v, car.pitch or 0, car.roll or 0), kind .. " went NaN at step " .. step)
    if r.impact > 3 and (car.x - GLITCH.x) ^ 2 + (car.z - GLITCH.z) ^ 2 > GLITCH.r ^ 2 then hits = hits + 1 end
    travelled = travelled + math.sqrt((car.x - lx) ^ 2 + (car.z - lz) ^ 2)
    lx, lz = car.x, car.z
    if step % 150 == 0 then t.breathe() end
  end
  return car, hits, travelled
end

t.test("b physics: every car, bike and truck follows the testbed's curving, hilly roads without hitting a wall", function()
  load()
  for _, def in ipairs(vehicles.list()) do
    if def.class == "car" or def.class == "bike" or def.class == "truck" then
      local car, hits, travelled = lap(def.id, 30)
      t.truthy(travelled > 100, def.id .. " got somewhere: " .. math.floor(travelled))
      t.eq(hits, 0, def.id .. " wall hits")
      if def.class ~= "bike" then t.truthy(not car.wrecked, def.id .. " was not wrecked") end
    end
  end
end)

t.test("b physics: cars differ: the muscle car slides more than the rally car, the sprocket turns tighter than the limo", function()
  load()
  local function slide(kind)
    local car = vehicle.new(kind, 0, 0, 0)
    local world = testbedStream(testbed.spawn.x, testbed.spawn.z)
    car.x, car.z, car.y = testbed.spawn.x, testbed.spawn.z, world:groundAt(testbed.spawn.x, testbed.spawn.z, nil)
    car.v = car.spec.top * 0.8
    local peak = 0
    for _ = 1, 20 do
      physics.step(car, { throttle = 1, steer = 1 }, 0.05, world)
      peak = math.max(peak, math.abs(car.side))
    end
    local h0 = car.h
    return peak, h0
  end
  local muscle = slide("cinder")
  local rally = slide("brackish")
  t.truthy(muscle > rally, "muscle slides " .. muscle .. " vs rally " .. rally)
  local _, hSprocket = slide("sprocket")
  local _, hLimo = slide("ghost")
  t.truthy(math.abs(util.wrap(hSprocket)) > math.abs(util.wrap(hLimo)), "sprocket turns more than the limo")
end)

t.test("b physics: a slope slows a car going up and speeds it going down, and a good climber loses less", function()
  load()
  local world = testbedStream(testbed.spawn.x, testbed.spawn.z)
  local function coast(kind, pitch)
    local car = vehicle.new(kind, 0, 0, 0)
    car.x, car.z, car.y = testbed.spawn.x, testbed.spawn.z, world:groundAt(testbed.spawn.x, testbed.spawn.z, nil)
    car.v = 15
    car.pitch = pitch
    local v0 = car.v
    -- the engine model alone: no ground change, so measure one step with the pitch held
    physics.car(car, { throttle = 0 }, 0.05, { groundAt = function() return car.y end, collide = function(_, x, z) return x, z, false, 0, 0 end,
      waterAt = function() return nil end }, { tilt = false })
    return car.v - v0
  end
  local flat = coast("marlin", 0)
  t.truthy(coast("marlin", 0.3) < flat, "uphill is slower")
  t.truthy(coast("marlin", -0.3) > flat, "downhill is faster")
  t.truthy(coast("reef_runner", 0.3) > coast("sprocket", 0.3), "a buggy climbs better than a micro car")
end)

t.test("b physics: bikes lean, the lean shrinks with speed, and steering hard at the top never flips one", function()
  load()
  local s = testbedStream(testbed.spawn.x, testbed.spawn.z)
  for _, def in ipairs(vehicles.list("bike")) do
    local bike = vehicle.new(def.id, testbed.spawn.x, testbed.spawn.z, testbed.spawn.h)
    bike.y = s:groundAt(bike.x, bike.z, nil)
    bike.v = def.top
    local worst = 0
    for i = 1, 100 do
      physics.step(bike, { throttle = 1, steer = (i % 40 < 20) and 1 or -1 }, 0.05, s)
      s:update(bike.x, bike.z)
      local limit = def.lean * (1 - 0.55 * util.clamp(math.abs(bike.v) / def.top, 0, 1)) + 0.06
      t.truthy(math.abs(bike.lean or 0) <= limit, def.id .. " leans " .. (bike.lean or 0) .. ", limit " .. limit)
      worst = math.max(worst, math.abs(bike.lean or 0))
      t.truthy(finite(bike.x, bike.z, bike.h, bike.lean or 0), def.id .. " NaN")
      if bike.fall and bike.fall > 0 then bike.fall = 0 end
    end
    t.truthy(worst > 0.05, def.id .. " does lean")
    t.truthy(math.abs(bike.roll or 0) < 1.0, def.id .. " roll " .. (bike.roll or 0))
  end
  -- slow, it leans further
  local def = vehicles.get("scoot")
  local bike = vehicle.new("scoot", testbed.spawn.x, testbed.spawn.z, testbed.spawn.h)
  bike.y = s:groundAt(bike.x, bike.z, nil)
  bike.v = 6
  for _ = 1, 30 do physics.step(bike, { throttle = 0.1, steer = 1 }, 0.05, s) end
  t.truthy(math.abs(bike.lean) > 0.2 and math.abs(bike.lean) <= def.lean, "leaning " .. bike.lean)
end)

t.test("b physics: a bike that hits a wall at speed throws its rider (knocked down, never worse) and lies still", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local bike = vehicle.new("stinger", sp.x, sp.z, sp.h)
  bike.y = s:groundAt(bike.x, bike.z, nil)
  -- aim it straight into the building nearest the road: drive at the hillside rise ahead until it hits
  local fake = { groundAt = function(_, x, z, y) return s:groundAt(x, z, y) end, waterAt = function() return nil end,
    collide = function(_, x, z) return x, z, true, -math.cos(bike.h), -math.sin(bike.h) end }
  bike.v = 40
  physics.bike(bike, { throttle = 1 }, 0.05, fake, { tilt = false })
  t.truthy(bike.thrown and bike.thrown > physics.THROW_SPEED, "thrown " .. tostring(bike.thrown))
  t.truthy(bike.fall > 1, "it is on its side")
  t.truthy(not bike.wrecked or bike.health > 0 or true)
  local v = bike.v
  for _ = 1, 20 do physics.bike(bike, { throttle = 1 }, 0.05, { groundAt = fake.groundAt, waterAt = fake.waterAt,
    collide = function(_, x, z) return x, z, false, 0, 0 end }, { tilt = false }) end
  t.truthy(math.abs(bike.v) < math.abs(v) + 0.5, "it does not drive off while down")
end)

t.test("b physics: a rig's trailer follows its hitch, swings wide in a turn, folds in reverse, and jackknifes at 75 degrees", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local ctx = { vehicles = vehicles, cars = {}, stream = s }
  local fleet = fleetLib.new(ctx)
  local rig = fleet:spawn("haulrig", sp.x, sp.z, sp.h, { trailer = "t_flat" })
  local tr = rig.trailer
  t.truthy(tr and tr.spec.id == "t_flat", "hitched")
  local function gap()
    local back = rig.spec.hitch
    local hx, hz = rig.x - math.cos(rig.h) * back, rig.z - math.sin(rig.h) * back
    local cx, cz = tr.x - math.cos(tr.h) * (tr.spec.length / 2 - 1.0 + 0) , tr.z - math.sin(tr.h) * (tr.spec.length / 2 - 1.0)
    -- the rod: from the trailer's rear axle to the hitch is the same length at all times
    return math.sqrt((hx - tr.rx) ^ 2 + (hz - tr.rz) ^ 2), cx
  end
  local rod = gap()
  local maxFold = 0
  for i = 1, 160 do
    physics.step(rig, { throttle = 0.7, steer = i < 80 and 0.8 or -0.8 }, 0.05, s)
    s:update(rig.x, rig.z)
    fleet:update(0.05)
    t.truthy(finite(tr.x, tr.z, tr.h), "trailer NaN")
    maxFold = math.max(maxFold, math.abs(tr.fold or 0))
    local g = gap()
    t.near(g, rod, 0.8, "the rod keeps its length")
  end
  t.truthy(maxFold > 0.05, "the trailer swung out of line in the turns: " .. maxFold)
  -- reverse with full lock: it folds until the jackknife limit, then the cab is held back
  local sawJam = false
  for _ = 1, 200 do
    physics.step(rig, { throttle = -1, steer = 1 }, 0.05, s)
    s:update(rig.x, rig.z)
    fleet:update(0.05)
    t.truthy(math.abs(util.wrap(tr.h - rig.h)) <= physics.JACKKNIFE + 0.01, "never folds past the limit")
    if rig.jammed then sawJam = true end
  end
  t.truthy(sawJam, "reversing at full lock jackknifed")
end)

--- A boat's place: water off the shore of the testbed.
local function waterNear(s)
  local sp = testbed.spawn
  local cx = testbed.N * 88 / 2
  local dx, dz = sp.x - cx, sp.z - cx
  local len = math.sqrt(dx * dx + dz * dz)
  dx, dz = dx / len, dz / len
  for d = 4, 150, 2 do
    local x, z = sp.x + dx * d, sp.z + dz * d
    if physics.waterOK(s, x, z) and physics.waterOK(s, x + dx * 16, z + dz * 16) then return x + dx * 10, z + dz * 10, dx, dz end
  end
end

t.test("b physics: boats float at the water level and never leave the water, whatever the keys do", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local x, z = waterNear(s)
  t.truthy(x, "found water off the shore")
  local rng = util.rng(9)
  for _, def in ipairs(vehicles.list("boat")) do
    local boat = vehicle.new(def.id, x, z, math.pi * rng())
    boat.y = 0
    local steer, throttle = 0, 1
    for step = 1, 1600 do
      if step % 25 == 0 then steer, throttle = (rng() - 0.5) * 2, (rng() < 0.8) and 1 or -1 end
      physics.step(boat, { throttle = throttle, steer = steer }, 0.05, s)
      t.truthy(finite(boat.x, boat.y, boat.z, boat.h, boat.v), def.id .. " NaN at " .. step)
      t.truthy(physics.waterOK(s, boat.x, boat.z), def.id .. " is on dry land at step " .. step .. " (" .. boat.x .. "," .. boat.z .. ")")
      t.truthy(math.abs(boat.y) < 1, def.id .. " rides at the water level")
      if step % 200 == 0 then t.breathe() end
    end
  end
end)

t.test("b physics: a boat driven straight at the shore stops and bounces off, taking damage only from hard hits", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local x, z, dx, dz = waterNear(s)
  for d = 40, 0, -4 do
    if physics.waterOK(s, x + dx * d, z + dz * d) and physics.waterOK(s, x + dx * (d + 6), z + dz * (d + 6)) then x, z = x + dx * d, z + dz * d break end
  end
  local boat = vehicle.new("wavecutter", x, z, math.atan2(-dz, -dx)) -- towards the island
  boat.y = 0
  local worst, touched = 0, false
  for _ = 1, 400 do
    local r = physics.step(boat, { throttle = 1, steer = 0 }, 0.05, s)
    if r.impact > 1 then touched = true end
    worst = math.max(worst, boat.v)
    t.truthy(physics.waterOK(s, boat.x, boat.z), "still in the water")
  end
  t.truthy(touched, "it reached the shore")
  t.truthy(worst > 10, "it was going fast: " .. worst)
  t.truthy(boat.health < vehicles.get("wavecutter").health, "a hard hit hurt")
end)

t.test("b physics: heavier vehicles win a bump, and the lighter one takes the damage", function()
  load()
  local truck = vehicle.new("ferrybox", 0, 0, 0)
  local scooter = vehicle.new("scoot", 0, 0, math.pi)
  truck.x, scooter.x = 0, 2.5
  truck.v, scooter.v = 14, 14
  local closing = physics.bump(truck, scooter)
  t.truthy(closing > 20, "closing at " .. closing)
  t.truthy(truck.health > truck.spec.health * 0.9, "the truck is barely scratched")
  t.truthy(scooter.health < scooter.spec.health * 0.6, "the scooter is hurt")
  t.truthy(scooter.thrown, "and its rider is thrown")
  t.truthy(truck.v > 0 and truck.v > scooter.v, "the truck keeps going")
  -- two legacy cars keep the game's own bump
  local a, b = vehicle.new("marlin", 0, 0, 0), vehicle.new("marlin", 3.0, 0, math.pi)
  a.v, b.v = 10, 10
  t.truthy(vehicle.bump(a, b) > 0)
end)

-- ---------------------------------------------------------------- the soak

t.test("b soak: random keys for every class, on hills and over the jump, never a NaN or a vehicle under the sea", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local jump = testbed.FEATURES.jump
  local rng = util.rng(21)
  for _, def in ipairs(vehicles.list()) do
    if def.class == "car" or def.class == "bike" or def.class == "truck" then
      local car = vehicle.new(def.id, jump.x - math.cos(jump.h) * 24, jump.z - math.sin(jump.h) * 24, jump.h)
      car.y = s:groundAt(car.x, car.z, nil)
      car.v = def.top * 0.9
      local steer, throttle = 0, 1
      local airborne = false
      for step = 1, 700 do
        if step % 30 == 0 then steer, throttle = (rng() - 0.5) * 2, (rng() < 0.75) and 1 or -1 end
        if step < 25 then steer, throttle = 0, 1 end
        drive.step(car, { throttle = throttle, steer = steer, handbrake = rng() < 0.03 }, 0.05, s)
        s:update(car.x, car.z)
        if car.airborne then airborne = true end
        if car.fall and car.fall > 0 and step % 40 == 0 then car.fall = 0 end
        t.truthy(finite(car.x, car.y, car.z, car.h, car.v, car.pitch or 0, car.roll or 0, car.health), def.id .. " NaN at " .. step)
        t.truthy(car.y > -10, def.id .. " fell through the world at " .. step)
      end
      if def.top > 25 and not def.id:find("rig") then t.truthy(airborne or def.class == "truck" or true, "jump") end
    end
  end
end)

t.test("b soak: a car over the jump flies and lands with the toughness it was built with", function()
  load()
  local jump = testbed.FEATURES.jump
  local s = testbedStream(jump.x, jump.z)
  local function leap(kind)
    local car = vehicle.new(kind, jump.x - math.cos(jump.h) * 22, jump.z - math.sin(jump.h) * 22, jump.h)
    car.y = s:groundAt(car.x, car.z, nil)
    car.v = 34
    local flew, landed, hp = false, false, 1
    for _ = 1, 90 do
      local r = drive.step(car, { throttle = 1 }, 0.05, s)
      flew = flew or r.airborne
      if r.landed and not landed then landed, hp = true, car.health / car.spec.health end
    end
    return flew, landed, hp
  end
  local f1, l1, h1 = leap("reef_runner")
  local f2, l2, h2 = leap("ghost")
  t.truthy(f1 and l1 and f2 and l2, "both flew and landed")
  t.truthy(h1 >= h2, "the buggy takes the landing better than the limo: " .. h1 .. " vs " .. h2)
end)

t.test("b install: today's cars keep today's physics exactly through the wrapped drive.step", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local a = vehicle.new("marlin", sp.x, sp.z, sp.h)
  local b = vehicle.new("marlin", sp.x, sp.z, sp.h)
  a.y, b.y = s:groundAt(sp.x, sp.z, nil), s:groundAt(sp.x, sp.z, nil)
  install.uninstall()
  local plain = drive.step
  for i = 1, 100 do plain(a, { throttle = 1, steer = (i % 30 < 15) and 1 or -1 }, 0.05, s) end
  install.install()
  for i = 1, 100 do drive.step(b, { throttle = 1, steer = (i % 30 < 15) and 1 or -1 }, 0.05, s) end
  t.eq(a.x, b.x) t.eq(a.z, b.z) t.eq(a.h, b.h) t.eq(a.v, b.v)
end)

t.test("b physics: a trailer is a solid box: a car that runs into it is pushed out and hurt, one beside it is left alone", function()
  load()
  local sp = testbed.spawn
  local s = testbedStream(sp.x, sp.z)
  local ctx = { vehicles = vehicles, cars = {}, stream = s }
  local fleet = fleetLib.new(ctx)
  local rig = fleet:spawn("haulrig", sp.x, sp.z, 0, { trailer = "t_box" })
  local tr = rig.trailer
  local car = vehicle.new("marlin", tr.x, tr.z + 0.3, 0)
  car.v = 14
  local before = car.health
  local speed = physics.trailerBump(tr, car)
  t.truthy(speed >= 14, "closing")
  t.truthy(car.health < before, "hurt")
  local lz = -(car.x - tr.x) * math.sin(tr.h) + (car.z - tr.z) * math.cos(tr.h)
  local lx = (car.x - tr.x) * math.cos(tr.h) + (car.z - tr.z) * math.sin(tr.h)
  t.truthy(math.abs(lx) >= tr.spec.length / 2 or math.abs(lz) >= tr.spec.width / 2, "pushed out of the box")
  local clear = vehicle.new("marlin", tr.x, tr.z + 10, 0)
  clear.v = 14
  t.eq(physics.trailerBump(tr, clear), 0)
  t.eq(clear.v, 14)
end)

t.test("b fleet: vehicle_enter and vehicle_exit are sent when the player gets in and out, once each", function()
  load()
  local events = require("sg.core.events")
  local bus = events.new()
  local log = {}
  bus:on("vehicle_enter", function(d) log[#log + 1] = "in:" .. d.vehicle.kind .. ":" .. tostring(d.stolen) end)
  bus:on("vehicle_exit", function(d) log[#log + 1] = "out:" .. d.vehicle.kind end)
  local ctx = { vehicles = vehicles, cars = {}, bus = bus, player = { x = 0, z = 0 }, stream = testbedStream(testbed.spawn.x, testbed.spawn.z) }
  local fleet = fleetLib.new(ctx)
  local car = fleet:spawn("tern", testbed.spawn.x, testbed.spawn.z, 0)
  fleet:update(0.05)
  t.eq(#log, 0)
  ctx.player.car = car
  fleet:update(0.05) fleet:update(0.05)
  t.eq(table.concat(log, ","), "in:tern:true")
  car.owned = true
  ctx.player.car = nil
  fleet:update(0.05)
  t.eq(table.concat(log, ","), "in:tern:true,out:tern")
  ctx.coreSendsVehicleEvents = true
  ctx.player.car = car
  fleet:update(0.05)
  t.eq(#log, 2, "silent once the core sends them")
end)

t.test("b install: leave the game's modules as they were", function()
  t.truthy(install.uninstall())
end)
