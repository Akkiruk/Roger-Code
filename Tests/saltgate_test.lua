-- saltgate_test.lua
-- SALTGATE's game logic without a screen: the city's geometry, car physics, heat, the five jobs, money and services,
-- the traffic and Patrol drivers, and a long random session that must not break.

local t = require("testing")
local util = require("sg.util")
local city = require("sg.city")
local vehicle = require("sg.vehicle")
local heat = require("sg.heat")
local missions = require("sg.missions")
local gamelib = require("sg.game")
local ai = require("sg.ai")

local function quietGame(seed)
  return gamelib.new({ seed = seed or 7, quiet = true })
end

--- Step a game for seconds with one input.
local function run(g, seconds, input, dt)
  dt = dt or 0.05
  local steps = math.floor(seconds / dt + 0.5)
  for _ = 1, steps do g:update(dt, input or {}) end
end

local function talkThrough(g)
  local guard = 0
  while g.talk and guard < 50 do
    g:update(0.05, { advance = true })
    guard = guard + 1
  end
end

local function putPlayer(g, place, inCar)
  local p = g.city.places[place]
  g.player.x, g.player.z = p.x, p.z
  if inCar then
    inCar.x, inCar.z, inCar.v = p.x, p.z, 0
  end
end

local function giveCar(g, kind)
  local car = g:spawnCar(kind or "marlin", g.player.x, g.player.z, 0)
  g.player.car = car
  return car
end

local function removeParked(g)
  for i = #g.cars, 1, -1 do
    if g.cars[i].parked then table.remove(g.cars, i) end
  end
end

-- ---------------------------------------------------------------- the city

t.test("saltgate: the city is the same for the same seed", function()
  local a, b = city.new(1), city.new(1)
  for i = 0, city.N - 1 do
    for j = 0, city.N - 1 do
      t.eq(#a.tiles[i][j].buildings, #b.tiles[i][j].buildings, "buildings in " .. i .. "," .. j)
      for k, bld in ipairs(a.tiles[i][j].buildings) do
        t.eq(bld.h, b.tiles[i][j].buildings[k].h, "height")
      end
    end
  end
end)

t.test("saltgate: every named place is on land, outside buildings and reachable by car", function()
  local c = city.new(1)
  for name, p in pairs(c.places) do
    t.truthy(city.onLand(p.x, p.z), name .. " on land")
    t.truthy(not city.buildingAt(c, p.x, p.z), name .. " not inside a building")
    local x, z = city.collide(c, p.x, p.z, 1.6)
    t.truthy(util.dist(x, z, p.x, p.z) < p.r, name .. " has room for a car (moved " .. util.dist(x, z, p.x, p.z) .. ")")
  end
end)

t.test("saltgate: collide pushes a circle out of a building and keeps it out of the sea", function()
  local c = city.new(1)
  local bld = c.tiles[4][1].buildings[1]
  local cx, cz = (bld.x0 + bld.x1) / 2, (bld.z0 + bld.z1) / 2
  local x, z, hit = city.collide(c, cx, cz, 1)
  t.truthy(hit, "hit")
  t.truthy(not city.buildingAt(c, x, z), "outside now")
  local sx, sz, shit = city.collide(c, -40, 100, 1)
  t.truthy(shit, "sea hit")
  t.truthy(city.onLand(sx, sz), "back on land")
  -- the pier reaches out past the shore
  local px = (city.pier.x0 + city.pier.x1) / 2
  local qx, qz, phit = city.collide(c, px, city.pier.z1 - 5, 1)
  t.truthy(not phit, "the pier holds a car")
  t.near(qz, city.pier.z1 - 5, 0.001, "on the pier")
  local _ = qx
end)

t.test("saltgate: lanes keep to the right and sidewalks go all the way round", function()
  -- driving east (d = 0), the right-hand lane is to the south (+z)
  local x, z = city.lanePoint(2, 2, 0, 10)
  t.near(x, 2 * city.P + 10, 0.001)
  t.near(z, 2 * city.P + city.LANE, 0.001)
  t.eq(city.surface(city.new(1), x, z), "road")
  local len = city.ringLength()
  local x0, z0 = city.ringPoint(3, 3, 0)
  local x1, z1 = city.ringPoint(3, 3, len)
  t.near(x0, x1, 0.001)
  t.near(z0, z1, 0.001)
  for s = 0, len, 1 do
    local px, pz = city.ringPoint(3, 3, s)
    t.eq(city.surface(city.new(1), px, pz), "walk", "sidewalk at s=" .. s)
    if s > 10 then break end
  end
end)

-- ---------------------------------------------------------------- cars

t.test("saltgate: a car speeds up toward its top speed and never past it", function()
  local car = vehicle.new("marlin", 0, 0, 0)
  for _ = 1, 400 do vehicle.update(car, { throttle = 1 }, 0.05, nil) end
  t.truthy(car.v > car.spec.top * 0.85, "near top: " .. car.v)
  t.truthy(car.v <= car.spec.top, "not past top")
  for _ = 1, 60 do vehicle.update(car, { throttle = -1 }, 0.05, nil) end
  t.truthy(car.v <= 0, "the brakes stop it, then it reverses")
  t.truthy(car.v > -car.spec.top * 0.5, "reverse is slow")
end)

t.test("saltgate: steering needs speed, and right is a positive turn", function()
  local car = vehicle.new("pipit", 0, 0, 0)
  for _ = 1, 20 do vehicle.update(car, { steer = 1 }, 0.05, nil) end
  t.near(car.h, 0, 0.0001, "no turn standing still")
  for _ = 1, 30 do vehicle.update(car, { throttle = 1, steer = 0 }, 0.05, nil) end
  local before = car.h
  for _ = 1, 10 do vehicle.update(car, { throttle = 1, steer = 1 }, 0.05, nil) end
  t.truthy(car.h > before, "turned right")
end)

t.test("saltgate: hitting a wall at speed costs speed and health", function()
  local c = city.new(1)
  local bld = c.tiles[4][1].buildings[1]
  local car = vehicle.new("marlin", bld.x0 - 8, (bld.z0 + bld.z1) / 2, 0)
  car.v = 25
  local hardest = 0
  for _ = 1, 40 do hardest = math.max(hardest, vehicle.update(car, { throttle = 1 }, 0.05, c)) end
  t.truthy(hardest > 10, "an impact was reported: " .. hardest)
  t.truthy(car.health < car.spec.health, "damaged")
  t.truthy(car.x < bld.x0, "did not go through")
end)

t.test("saltgate: a car at no health is wrecked and cars that touch are pushed apart", function()
  local car = vehicle.new("pipit", 0, 0, 0)
  vehicle.damage(car, 1000)
  t.truthy(car.wrecked)
  t.eq(car.health, 0)
  local a, b = vehicle.new("marlin", 0, 0, 0), vehicle.new("marlin", 1, 0, math.pi)
  a.v = 20
  local closing = vehicle.bump(a, b)
  t.truthy(closing > 0, "they met")
  t.truthy(util.dist(a.x, a.z, b.x, b.z) > 1, "pushed apart")
  t.truthy(a.v < 20, "a lost speed")
end)

t.test("saltgate: Rusty pays by condition and never for a cruiser", function()
  local car = vehicle.new("sovereign", 0, 0, 0)
  t.eq(vehicle.chopValue(car), 900)
  car.health = car.spec.health / 2
  t.eq(vehicle.chopValue(car), 585)
  t.eq(vehicle.chopValue(vehicle.new("cruiser", 0, 0, 0)), 0)
end)

-- ---------------------------------------------------------------- heat

t.test("saltgate: heat rises to five, cools while unseen, and holds while seen", function()
  local h = heat.new()
  heat.add(h, 9, "test")
  t.eq(h.level, 5)
  for _ = 1, 100 do heat.update(h, 0.5, true, false) end
  t.eq(h.level, 5, "seen: no cooling")
  local secs = 0
  while h.level == 5 and secs < 100 do
    heat.update(h, 0.1, false, false)
    secs = secs + 0.1
  end
  t.near(secs, heat.cooldown(5), 0.15, "one level after the cooldown")
  for _ = 1, 2000 do heat.update(h, 0.1, false, false) end
  t.eq(h.level, 0, "cools all the way")
  t.eq(heat.copsFor(0), 0)
  for lvl = 1, 5 do t.truthy(heat.copsFor(lvl) >= heat.copsFor(lvl - 1), "more cops at higher heat") end
end)

t.test("saltgate: being stopped beside a cruiser long enough is a pinch", function()
  local h = heat.new()
  heat.add(h, 2)
  local result
  local secs = 0
  repeat
    result = heat.update(h, 0.1, true, true)
    secs = secs + 0.1
  until result or secs > 10
  t.eq(result, "pinched")
  t.near(secs, heat.PINCH_TIME, 0.15)
  heat.add(h, 1)
  heat.update(h, 1.5, true, true)
  heat.update(h, 1, true, false)
  t.truthy(h.pinch < 1.5, "the pinch drains when you get away")
end)

-- ---------------------------------------------------------------- the story

t.test("saltgate: Fresh Air plays from Juno's door to her back lot and pays", function()
  local g = quietGame()
  removeParked(g)
  putPlayer(g, "juno")
  g:update(0.05, {})
  t.truthy(g.talk, "Juno talks")
  talkThrough(g)
  t.truthy(g.mission and g.mission.def.id == "fresh_air", "the job started")
  t.eq(missions.objective(g), missions.LIST[1].steps[1].text)
  local car = g:spawnCar("pipit", g.player.x + 2, g.player.z, 0)
  g:update(0.05, { enter = true })
  t.eq(g.player.car, car, "in the car")
  g:update(0.05, {})
  t.eq(g.mission.index, 2, "on to the drive")
  putPlayer(g, "juno_lot", car)
  g:update(0.05, {})
  talkThrough(g)
  t.truthy(g.progress.done.fresh_air, "done")
  t.eq(g.money, 200)
  t.eq(missions.nextMission(g.progress).id, "hot_broth")
end)

t.test("saltgate: Hot Broth fails when the clock runs out", function()
  local g = quietGame()
  g.progress.done.fresh_air = true
  putPlayer(g, "juno")
  g:update(0.05, {})
  talkThrough(g)
  giveCar(g)
  g:update(0.05, {})
  t.truthy(missions.timeLeft(g), "on the clock")
  run(g, 90, {})
  t.truthy(not g.mission, "failed")
  t.truthy(not g.progress.done.hot_broth)
  t.eq(g.money, 0)
end)

t.test("saltgate: Gulls on the Roof brings the Patrol and Rusty waits until they are gone", function()
  local g = quietGame()
  g.progress.done.fresh_air, g.progress.done.hot_broth = true, true
  putPlayer(g, "juno")
  g:update(0.05, {})
  talkThrough(g)
  local car = giveCar(g)
  putPlayer(g, "crane", car)
  g:update(0.05, {})
  t.truthy(g.heat.level >= 2, "the crate is tagged")
  t.eq(g.mission.def.steps[g.mission.index].kind, "loseheat")
  -- drive to Rusty's with the heat still on: not yet
  g.mission.index = 3
  putPlayer(g, "rusty", car)
  g:update(0.05, {})
  t.truthy(g.mission, "Rusty does not open with heat on")
  t.truthy(missions.objective(g):find("Lose the Patrol"), "says why")
  g.heat.level = 0
  for i = #g.cars, 1, -1 do if g.cars[i].kind == "cruiser" then table.remove(g.cars, i) end end
  g:update(0.05, {})
  talkThrough(g)
  t.truthy(g.progress.done.gulls, "delivered")
  t.eq(g.money, 600)
end)

t.test("saltgate: Gilded puts the Sovereign on the plaza, stealing it brings heat 3, wrecking it fails", function()
  local g = quietGame()
  for _, id in ipairs({ "fresh_air", "hot_broth", "gulls" }) do g.progress.done[id] = true end
  putPlayer(g, "rusty_door")
  g:update(0.05, {})
  t.truthy(g.talk, "Rusty talks")
  talkThrough(g)
  local sov = g.mission.car
  t.truthy(sov and sov.kind == "sovereign", "the Sovereign is there")
  local lot = g.city.places.gilt_lot
  t.truthy(util.dist(sov.x, sov.z, lot.x, lot.z) < 1, "on the plaza")
  local tx, tz, kind = missions.target(g)
  t.eq(kind, "car")
  g.player.x, g.player.z = sov.x + 2, sov.z
  g:update(0.05, { enter = true })
  g:update(0.05, {})
  t.eq(g.player.car, sov)
  t.truthy(g.heat.level >= 3, "the Gilts called it in")
  vehicle.damage(sov, 1000)
  g:update(0.05, {})
  t.truthy(not g.mission, "failed when wrecked")
  local _ = tx and tz
end)

t.test("saltgate: Low Tide needs the wait at the doors before the ferry", function()
  local g = quietGame()
  for _, id in ipairs({ "fresh_air", "hot_broth", "gulls", "gilded" }) do g.progress.done[id] = true end
  putPlayer(g, "juno")
  g:update(0.05, {})
  talkThrough(g)
  local car = giveCar(g, "sovereign")
  g:update(0.05, {})
  putPlayer(g, "gilt_door", car)
  g:update(0.05, {})
  t.eq(g.mission.def.steps[g.mission.index].kind, "wait")
  run(g, 3, {})
  local door = g.city.places.gilt_door
  car.x, car.z = door.x + 30, door.z
  g:update(0.05, {})
  t.truthy(g.mission.away, "away from the doors")
  local waited = g.mission.waited
  run(g, 2, {})
  t.near(g.mission.waited, waited, 0.001, "the count pauses while away")
  car.x, car.z = door.x, door.z
  run(g, 3.5, {})
  t.truthy(g.heat.level >= 4, "the tower lights up")
  t.eq(g.mission.def.steps[g.mission.index].place, "ferry")
  g.heat.level = 0
  putPlayer(g, "ferry", car)
  g:update(0.05, {})
  talkThrough(g)
  t.truthy(g.progress.finished, "the story is over")
  t.eq(g.money, 5000)
  t.eq(missions.nextMission(g.progress), nil)
end)

t.test("saltgate: no job starts with heat on you", function()
  local g = quietGame()
  heat.add(g.heat, 1)
  putPlayer(g, "juno")
  g:update(0.05, {})
  t.truthy(not g.talk and not g.mission, "Juno waits")
end)

-- ---------------------------------------------------------------- money and services

t.test("saltgate: Paint & Pray clears heat for $150, or tells you to come back", function()
  local g = quietGame()
  local car = giveCar(g)
  heat.add(g.heat, 3)
  putPlayer(g, "respray", car)
  g:update(0.05, {})
  t.truthy(g.heat.level > 0, "no cash, no respray")
  g.money = 400
  for i = #g.cars, 1, -1 do if g.cars[i].kind == "cruiser" then table.remove(g.cars, i) end end
  g:update(0.05, {})
  t.eq(g.heat.level, 0, "fresh coat")
  t.eq(g.money, 250)
end)

t.test("saltgate: Rusty buys a clean car that is stopped in his yard", function()
  local g = quietGame()
  local car = giveCar(g, "marlin")
  putPlayer(g, "rusty", car)
  car.v = 0
  g:update(0.05, {})
  t.eq(g.player.car, nil, "out of the car")
  t.eq(g.money, 160)
  for _, c in ipairs(g.cars) do t.truthy(c ~= car, "the car is gone") end
end)

t.test("saltgate: getting nabbed costs a tenth (at least $50) and ends at the precinct", function()
  local g = quietGame()
  g.money = 1000
  heat.add(g.heat, 2)
  local cop = g:spawnCar("cruiser", g.player.x + 3, g.player.z, 0)
  ai.init(cop, "cop", 0, 0, 0)
  local guard = 0
  while not g.overlay and guard < 200 do
    cop.x, cop.z, cop.v = g.player.x + 3, g.player.z, 0
    g:update(0.05, {})
    guard = guard + 1
  end
  t.truthy(g.overlay and g.overlay.kind == "nabbed", "nabbed")
  t.eq(g.money, 900)
  run(g, 4, {})
  t.eq(g.heat.level, 0)
  local pc = g.city.places.precinct
  t.truthy(util.dist(g.player.x, g.player.z, pc.x, pc.z) < 3, "at the precinct")
end)

t.test("saltgate: running out of health is a knock-out and a trip to St. Gull's", function()
  local g = quietGame()
  g.money = 60
  g:hurt(500)
  g:update(0.05, {})
  t.truthy(g.overlay and g.overlay.kind == "ko")
  t.eq(g.money, 0)
  run(g, 4, {})
  t.eq(g.player.health, 100)
  local h = g.city.places.hospital
  t.truthy(util.dist(g.player.x, g.player.z, h.x, h.z) < 3)
end)

t.test("saltgate: pulling a driver out of traffic in front of a cruiser is heat", function()
  local g = quietGame()
  removeParked(g)
  local car = g:spawnCar("marlin", g.player.x + 2, g.player.z, 0)
  ai.init(car, "traffic", 0, 0, 0)
  local cop = g:spawnCar("cruiser", g.player.x + 10, g.player.z, 0)
  ai.init(cop, "cop", 0, 0, 0)
  cop.ai.los = true
  g:update(0.05, { enter = true })
  t.eq(g.player.car, car)
  t.eq(g.heat.level, 1, "a cruiser saw it")
  local runners = 0
  for _, ped in ipairs(g.peds) do if ped.state == "run" then runners = runners + 1 end end
  t.eq(runners, 1, "the driver runs")
end)

t.test("saltgate: saves keep money and jobs, and a bad save is ignored", function()
  local g = quietGame()
  g.money = 1234
  g.progress.done.fresh_air = true
  local data = g:saveData()
  local g2 = gamelib.new({ seed = 3, quiet = true, save = data })
  t.eq(g2.money, 1234)
  t.truthy(g2.progress.done.fresh_air)
  local g3 = gamelib.new({ seed = 3, quiet = true, save = { money = "lots", done = { "nope" } } })
  t.eq(g3.money, 0)
  t.truthy(not g3.progress.done.nope)
end)

t.test("saltgate: cars you leave behind do not pile up, and wrecks burn out", function()
  local g = quietGame()
  for k = 1, 20 do
    local car = g:spawnCar("pipit", g.player.x + k * 6, g.player.z, 0)
    car.parked = true
  end
  local wreck = g:spawnCar("marlin", g.player.x - 6, g.player.z, 0)
  wreck.parked = true
  vehicle.damage(wreck, 1000)
  run(g, 16, {})
  local parked = 0
  for _, c in ipairs(g.cars) do
    if c.parked then parked = parked + 1 end
    t.truthy(c ~= wreck, "the wreck is cleared")
  end
  t.truthy(parked <= gamelib.PARKED_MAX, "at most " .. gamelib.PARKED_MAX .. " parked, got " .. parked)
end)

-- ---------------------------------------------------------------- the drivers

t.test("saltgate: traffic keeps to the roads for a long drive", function()
  local g = quietGame(11)
  removeParked(g)
  local k, l, d = 1, 1, 0
  local x, z = city.lanePoint(k, l, d, 10)
  local car = g:spawnCar("marlin", x, z, 0)
  ai.init(car, "traffic", k + 1, l, d)
  local samples, onRoad, minX, maxX = 0, 0, math.huge, -math.huge
  for step = 1, 2400 do
    g.player.x, g.player.z = car.x, car.z + 30 -- keep it in range, out of its way
    local input = ai.traffic(g, car, 0.05)
    vehicle.update(car, input, 0.05, g.city)
    if step % 10 == 0 then
      samples = samples + 1
      if city.roadDistance(car.x, car.z) <= city.HALF + 1.5 then onRoad = onRoad + 1 end
      minX, maxX = math.min(minX, car.x), math.max(maxX, car.x)
    end
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(onRoad / samples > 0.95, "on the road " .. onRoad .. "/" .. samples)
  t.truthy(maxX - minX > 60, "it went somewhere")
end)

t.test("saltgate: the Patrol finds a player who sits still on a road", function()
  local g = quietGame(5)
  removeParked(g)
  local x, z = city.lanePoint(4, 4, 0, 20)
  g.player.x, g.player.z = x, z
  heat.add(g.heat, 3)
  local seconds = 0
  while not g.overlay and seconds < 120 do
    g:update(0.05, {})
    seconds = seconds + 0.05
    if math.floor(seconds * 20) % 200 == 0 then t.breathe() end
  end
  t.truthy(g.overlay and g.overlay.kind == "nabbed", "caught within " .. seconds .. " s")
end)

t.test("saltgate: twenty minutes of random play breaks nothing", function()
  local g = gamelib.new({ seed = 99 })
  local r = util.rng(1234)
  local input = {}
  for step = 1, 24000 do
    if step % 20 == 1 then
      input = { throttle = r(3) - 2, steer = r(3) - 2, handbrake = r() < 0.1, sprint = r() < 0.5 }
    end
    input.enter = r() < 0.01
    input.advance = r() < 0.05
    g:update(0.05, input)
    t.truthy(city.onLand(g.player.x, g.player.z), "on land at step " .. step)
    t.truthy(#g.cars < 40 and #g.peds < 40, "bounded crowds")
    if step % 400 == 0 then t.breathe() end
  end
end)

-- ---------------------------------------------------------------- controls: keys as CC sends them

local inputlib = require("sg.input")
local hints = require("sg.hints")

-- the CC:Tweaked 1.101.3 key codes (GLFW)
local KEYS = { w = 87, a = 65, s = 83, d = 68, e = 69, f = 70, x = 88, h = 72, m = 77, p = 80, c = 67, q = 81,
  up = 265, down = 264, left = 263, right = 262, space = 32, leftShift = 340, rightShift = 344, enter = 257,
  numPadEnter = 335, tab = 258, f3 = 292 }

--- Hold a key for some frames the way CC does: key (not held), then a repeat (held) each frame, then key_up.
local function holdFrames(inp, code, frames, each)
  local clock = inp.now
  inp:event(clock, "key", code, false)
  for i = 1, frames do
    if i > 1 then inp:event(clock, "key", code, true) end
    each(inp:read())
    clock = clock + 0.05
    inp:endFrame(clock)
  end
  inp:event(clock, "key_up", code)
end

t.test("saltgate input: a held key counts every frame, repeats are not new presses, key_up stops it at once", function()
  local inp = inputlib.new(KEYS)
  local frames, uses = 0, 0
  holdFrames(inp, KEYS.w, 30, function(i)
    if i.throttle == 1 then frames = frames + 1 end
  end)
  t.eq(frames, 30, "W held all 30 frames")
  t.eq(inp:read().throttle, 1, "the frame of the key_up still feels the tap")
  inp:endFrame(inp.now + 0.05)
  t.eq(inp:read().throttle, 0, "let go: nothing next frame")
  holdFrames(inp, KEYS.e, 20, function(i) if i.enter then uses = uses + 1 end end)
  t.eq(uses, 1, "holding E is one press, not twenty")
end)

t.test("saltgate input: a tap shorter than a frame still moves, and two keys at once both count", function()
  local inp = inputlib.new(KEYS)
  inp:event(0, "key", KEYS.a, false)
  inp:event(0.01, "key_up", KEYS.a)
  t.eq(inp:read().steer, -1, "the tap is felt for one frame")
  inp:endFrame(0.05)
  t.eq(inp:read().steer, 0)
  inp:event(0.06, "key", KEYS.w, false)
  inp:event(0.07, "key", KEYS.d, false)
  inp:event(0.08, "key", KEYS.d, true) -- only the last key repeats, as in Minecraft; W stays held
  local i = inp:read()
  t.eq(i.throttle, 1)
  t.eq(i.steer, 1)
  inp:endFrame(0.1)
  i = inp:read()
  t.eq(i.throttle, 1, "W still held without its own repeats")
end)

t.test("saltgate input: E and F are one action, arrows are WASD, X skips, a lost key_up does not stick forever", function()
  local inp = inputlib.new(KEYS)
  inp:event(0, "key", KEYS.e, false)
  inp:event(0, "key", KEYS.f, false)
  t.truthy(inp:read().enter)
  inp:endFrame(0.05)
  t.truthy(not inp:read().enter, "once")
  inp:event(0.1, "key", KEYS.up, false)
  inp:event(0.1, "key", KEYS.left, false)
  t.eq(inp:read().throttle, 1)
  t.eq(inp:read().steer, -1)
  inp:event(0.1, "key", KEYS.x, false)
  t.truthy(inp:read().skip)
  inp:endFrame(0.1 + inputlib.STALE + 0.5)
  t.eq(inp:read().throttle, 0, "no key_up came, but the key went quiet")
  inp:event(1, "key_up", KEYS.s) -- a key_up for a key never seen down changes nothing
  t.eq(inp:read().throttle, 0)
end)

t.test("saltgate controls: on foot W walks the way you face, S backs up, D turns right, A left", function()
  local g = quietGame()
  removeParked(g)
  local p = g.player
  p.x, p.z = city.lanePoint(4, 4, 0, 20)
  p.h = 0
  local x0 = p.x
  run(g, 1, { throttle = 1 })
  t.truthy(p.x - x0 > 3, "forward along +x (the way it faces)")
  local x1 = p.x
  run(g, 0.5, { throttle = -1 })
  t.truthy(p.x < x1, "S walks backward")
  local h0 = p.h
  run(g, 0.3, { steer = 1 })
  t.truthy(util.wrap(p.h - h0) > 0.3, "D turns right (toward +z when facing +x)")
  local fx, fz = math.cos(h0), math.sin(h0)
  local rx, rz = -fz, fx
  t.truthy(math.cos(p.h) * rx + math.sin(p.h) * rz > 0, "now facing more to the right of before")
  h0 = p.h
  run(g, 0.3, { steer = -1 })
  t.truthy(util.wrap(p.h - h0) < -0.3, "A turns left")
  t.truthy(gamelib.FOOT_TURN <= 2.5, "a turn slow enough to watch")
end)

t.test("saltgate controls: W walks forward at walking speed and SHIFT runs, never backward (the wrapped-speed bug)", function()
  -- speeds once went through the angle helper, which wraps: 4.2 became -2.08 (W walked backward) and 7.5 became 1.22
  t.eq(util.approach(0, 4.2, 100), 4.2)
  t.eq(util.approach(0, 7.5, 100), 7.5)
  t.eq(util.approach(5, -3, 2), 3)
  local g = quietGame()
  removeParked(g)
  local p = g.player
  p.x, p.z = city.lanePoint(4, 4, 0, 10)
  p.h = 0
  run(g, 0.5, { throttle = 1 })
  t.near(p.v, gamelib.WALK, 0.001, "walking speed, forward")
  run(g, 0.5, { throttle = 1, sprint = true })
  t.near(p.v, gamelib.RUN, 0.001, "running speed, forward")
  run(g, 0.5, { throttle = -1 })
  t.truthy(p.v < 0, "S backs up")
  run(g, 0.5, {})
  t.eq(p.v, 0, "let go: stop")
end)

t.test("saltgate controls: in a car W drives, letting go coasts, S brakes then reverses, D steers right", function()
  local g = quietGame()
  removeParked(g)
  local p = g.player
  local x, z = city.lanePoint(1, 4, 0, 4)
  p.x, p.z = x, z
  local car = giveCar(g, "marlin")
  car.x, car.z, car.h = x, z, 0
  run(g, 2, { throttle = 1 })
  local v = car.v
  t.truthy(v > 12, "up to speed: " .. v)
  run(g, 0.5, {})
  t.truthy(car.v > v * 0.85 and car.v < v, "coasting, not stopping: " .. car.v)
  local h0 = car.h
  run(g, 0.3, { throttle = 1, steer = 1 })
  t.truthy(util.wrap(car.h - h0) > 0.2, "D steers right")
  car.h = 0
  run(g, 1.2, { throttle = -1 })
  t.truthy(car.v < 0, "S stopped it and now reverses: " .. car.v)
end)

t.test("saltgate driving: right turns at every junction with W held never hit a wall, for every car", function()
  local c = city.new(1)
  for _, kind in ipairs({ "pipit", "marlin", "kestrel", "tidewater", "sovereign", "cruiser" }) do
    local x, z = city.lanePoint(2, 2, 0, 8)
    local car = vehicle.new(kind, x, z, 0)
    local d, k, l, turning, hits = 0, 3, 2, false, 0
    for _ = 1, 1600 do
      local nx, nz = city.nodePos(k, l)
      local dir = city.DIRS[d + 1]
      local ahead = (nx - car.x) * dir[1] + (nz - car.z) * dir[2]
      local input = { throttle = 1, steer = 0 }
      if not turning and ahead < 9 then turning = true end
      if turning then
        input.steer = 1
        if math.abs(util.wrap(city.DIR_HEADING[(d + 1) % 4 + 1] - car.h)) < 0.12 then
          turning = false
          d = (d + 1) % 4
          local nd = city.DIRS[d + 1]
          k, l = k + nd[1], l + nd[2]
        end
      end
      if vehicle.update(car, input, 0.05, c) > 2 then hits = hits + 1 end
    end
    t.eq(hits, 0, kind .. " wall hits")
    t.eq(car.health, car.spec.health, kind .. " undamaged")
  end
end)

t.test("saltgate driving: a glancing hit slides along the wall instead of stopping dead", function()
  local c = city.new(1)
  local bld = c.tiles[4][1].buildings[1]
  -- running south along the building's west face, angled 20 degrees into it
  local car = vehicle.new("marlin", bld.x0 - 3, bld.z0 - 4, math.pi / 2 - math.rad(20))
  car.v = 25
  local hit = 0
  for _ = 1, 20 do hit = math.max(hit, vehicle.update(car, { throttle = 1 }, 0.05, c)) end
  t.truthy(hit > 0, "it did touch the wall")
  t.truthy(car.v > 10, "still moving: " .. car.v)
  t.truthy(not car.wrecked and car.health > 70, "a scrape, not a wreck: " .. car.health)
end)

t.test("saltgate driving: no NaN from zero time steps, stacked cars or a car dead centre in a building", function()
  local c = city.new(1)
  local a = vehicle.new("marlin", 100, 100, 0)
  local b = vehicle.new("marlin", 100, 100, 0)
  vehicle.update(a, { throttle = 1, steer = 1 }, 0, c)
  vehicle.bump(a, b)
  local bld = c.tiles[4][1].buildings[1]
  local inside = vehicle.new("pipit", (bld.x0 + bld.x1) / 2, (bld.z0 + bld.z1) / 2, 0)
  inside.v = 30
  vehicle.update(inside, { throttle = 1 }, 0.05, c)
  for _, car in ipairs({ a, b, inside }) do
    for _, key in ipairs({ "x", "z", "h", "v", "side", "health" }) do
      t.truthy(car[key] == car[key] and math.abs(car[key]) < 1e6, key .. " is a number")
    end
  end
  t.truthy(not city.buildingAt(c, inside.x, inside.z), "pushed out")
end)

t.test("saltgate hints: the arrow points where the target is from the camera", function()
  -- facing east (yaw 0): +z is to the right
  t.eq((hints.direction(0, 0, 0, 50, 0)), "ahead")
  t.eq((hints.direction(0, 0, 0, 0, 50)), "right")
  t.eq((hints.direction(0, 0, 0, 0, -50)), "left")
  t.eq((hints.direction(0, 0, 0, -50, 0)), "behind")
  -- facing south (yaw pi/2): west (-x) is to the right
  t.eq((hints.direction(0, 0, math.pi / 2, -50, 0)), "right")
  local _, d = hints.direction(0, 0, 0, 30, 40)
  t.near(d, 50, 0.001)
end)

t.test("saltgate hints: the key line changes with what you are doing", function()
  local g = quietGame()
  removeParked(g)
  t.eq(hints.line(g), hints.FOOT)
  t.truthy(hints.FOOT:find("WASD") and hints.FOOT:find("SHIFT") and hints.FOOT:find("E enter car"))
  local car = g:spawnCar("pipit", g.player.x + 2, g.player.z, 0)
  t.eq(hints.line(g), hints.NEAR_CAR)
  t.truthy(hints.NEAR_CAR:find("E steal car"))
  g.player.car = car
  t.eq(hints.line(g), hints.DRIVING)
  for _, k in ipairs({ "W gas", "S brake", "A/D steer", "SPACE handbrake", "E out" }) do
    t.truthy(hints.DRIVING:find(k, 1, true), "driving hint has " .. k)
  end
  g:dialogue({ { "Mama Juno", "Hi." } })
  t.eq(hints.line(g), "ENTER next")
  for _, line in ipairs({ hints.FOOT, hints.NEAR_CAR, hints.DRIVING, hints.TALK }) do
    t.truthy(#line <= 50, "fits a 51-wide screen: " .. line)
    t.truthy(not line:find("F "), "one key per action: no F in " .. line)
  end
end)

t.test("saltgate tutorial: walk to the red car, E, drive to the marker; each step waits; the save remembers", function()
  local g = gamelib.new({ seed = 4, quiet = true, tutorial = true })
  t.eq(g.tutorial.step, "walk")
  local car = g.tutorial.car
  t.truthy(car and car.parked, "a parked car to walk to")
  run(g, 3, {})
  t.eq(g.tutorial.step, "walk", "waits for you")
  local tx, tz, kind = hints.target(g)
  t.eq(kind, "car")
  t.near(tx, car.x, 0.001)
  t.near(tz, car.z, 0.001)
  g.player.x, g.player.z = car.x - 3, car.z
  g:update(0.05, {})
  t.eq(g.tutorial.step, "enter")
  g:update(0.05, { enter = true })
  g:update(0.05, {})
  t.eq(g.tutorial.step, "drive")
  t.eq(g.player.car, car)
  local _, _, k2 = hints.target(g)
  t.eq(k2, "giver")
  local j = g.city.places.juno
  car.x, car.z, car.v = j.x, j.z, 0
  g:update(0.05, {})
  t.eq(g.tutorial, nil, "done at Juno's")
  t.truthy(g.talk, "and Fresh Air starts")
  t.truthy(g:saveData().tutorialDone)
  local again = gamelib.new({ seed = 4, quiet = true, tutorial = true, save = g:saveData() })
  t.eq(again.tutorial, nil, "not again")
end)

t.test("saltgate tutorial: X skips it", function()
  local g = gamelib.new({ seed = 4, quiet = true, tutorial = true })
  g:update(0.05, { skip = true })
  t.eq(g.tutorial, nil)
  t.truthy(g.tutorialDone)
end)

t.test("saltgate music: a cue for every state, in the right order of importance", function()
  local g = quietGame()
  t.eq(hints.music(g, "title"), "title")
  t.eq(hints.music(g, "play"), "free_roam")
  giveCar(g)
  t.eq(hints.music(g, "play"), "driving")
  missions.start(g, missions.BY_ID.hot_broth)
  t.eq(hints.music(g, "play"), "job_hot_broth")
  heat.add(g.heat, 2)
  t.eq(hints.music(g, "play"), "heat_low")
  heat.add(g.heat, 1)
  t.eq(hints.music(g, "play"), "heat_high")
  g.overlay = { kind = "nabbed", t = 3 }
  t.eq(hints.music(g, "play"), "cuffed")
  g.overlay = { kind = "ko", t = 3 }
  t.eq(hints.music(g, "play"), "wasted")
  g.overlay = nil
  heat.clear(g.heat)
  g.mission = nil
  missions.start(g, missions.BY_ID.low_tide)
  t.eq(hints.music(g, "play"), "finale")
  local all = {}
  for _, name in ipairs(hints.MUSIC_STATES) do all[name] = true end
  for _, def in ipairs(missions.LIST) do
    t.truthy(all[def.final and "finale" or ("job_" .. def.id)], "a cue for " .. def.id)
  end
end)

-- ---------------------------------------------------------------- music: districts, credits, sharing the speaker

local soundlib = require("sg.sound")

t.test("saltgate music: the district under you, for the roaming tune", function()
  local g = quietGame()
  local function at(i, j)
    g.player.x, g.player.z = i * city.P + city.P / 2, j * city.P + city.P / 2
    return hints.district(g)
  end
  t.eq(at(6, 1), "gilt")
  t.eq(at(1, 3), "lantern")
  t.eq(at(7, 4), "cinder")
  t.eq(at(3, 7), "brine")
  t.eq(at(4, 4), "mid")
  t.eq(at(3, 4), "mid", "the park plays the old town's")
  g.player.x, g.player.z = (city.pier.x0 + city.pier.x1) / 2, city.pier.z1 - 2
  t.eq(hints.district(g), "brine", "the pier is the docks'")
  g.player.x, g.player.z = -100, -100
  t.truthy(hints.district(g), "off the map still has one")
  local names = { gilt = true, lantern = true, cinder = true, brine = true, mid = true }
  for i = 0, city.N - 1 do
    for j = 0, city.N - 1 do t.truthy(names[at(i, j)], "a known district at " .. i .. "," .. j) end
  end
end)

t.test("saltgate music: the credits roll after Low Tide's last words, until the Patrol or the clock ends them", function()
  local g = quietGame()
  for _, id in ipairs({ "fresh_air", "hot_broth", "gulls", "gilded" }) do g.progress.done[id] = true end
  missions.start(g, missions.BY_ID.low_tide)
  local car = giveCar(g, "sovereign")
  g.mission.index = 4
  putPlayer(g, "ferry", car)
  g:update(0.05, {})
  t.truthy(g.talk, "the outro")
  t.eq(hints.music(g, "play"), "driving", "no credits during the talk")
  talkThrough(g)
  t.truthy(g.progress.finished)
  t.eq(hints.music(g, "play"), "credits")
  local all = {}
  for _, name in ipairs(hints.MUSIC_STATES) do all[name] = true end
  t.truthy(all.credits, "credits is a cue")
  heat.add(g.heat, 1)
  t.eq(hints.music(g, "play"), "heat_low", "the Patrol cuts in")
  heat.clear(g.heat)
  run(g, missions.CREDITS_SECONDS + 1, {})
  t.eq(hints.music(g, "play"), "driving", "and they end")
end)

t.test("saltgate sound: effects keep to their share of the speaker, and wait rather than vanish", function()
  local calls = 0
  local speaker = { playNote = function() calls = calls + 1 return true end }
  local s = soundlib.new(speaker, 2)
  soundlib.play(s, "pass") -- several notes at once
  soundlib.play(s, "cash")
  local most = 0
  for _ = 1, 40 do
    local before = calls
    soundlib.update(s, 0.05, false)
    most = math.max(most, calls - before)
  end
  t.truthy(most <= 2, "never more than 2 at once: " .. most)
  local total = #soundlib.CUES.pass + #soundlib.CUES.cash
  t.eq(calls, total, "every note played, a little later if need be")
  local free = soundlib.new(speaker)
  t.eq(free.cap, 7, "without music the effects may use 7")
end)
