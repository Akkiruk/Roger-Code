-- saltgate_e_activities_test.lua
-- SALTGATE stream E, the side activities, on the real plugins: the layout the city gives (and that the file in content/ is
-- the one the generator makes), gull totems and postcards, street races to the hundredth of a second with ghosts, taxi
-- shifts and parcel runs, stunt jumps, shops, property income over game days, the garage, and the 100% tracker adding up
-- to exactly 100 when every activity has been done.

local t = require("testing")
local kit = require("sg.ui.testkit")
local layoutLib = require("sg.activities.layout")
local raceLib = require("sg.activities.race")
local jobLib = require("sg.activities.job")
local testbed = require("sg.core.testbed")
local vehicle = require("sg.vehicle")
local wallet = require("sg.progress.wallet")

local function game(opts)
  local ctx = kit.game(opts)
  -- no title screen: straight to play
  ctx.eui.titleShown = true
  ctx.hud.hidden = false
  return ctx
end

local function put(ctx, x, z, v, y)
  local p = ctx.player
  p.x, p.z = x, z
  if y then p.y = y end
  if p.car then
    p.car.x, p.car.z, p.car.v = x, z, v or 0
    if y then p.car.y = y end
  end
end

local function giveCar(ctx, x, z)
  local car = vehicle.new("marlin", x or 0, z or 0, 0, "red")
  car.y = 0
  ctx.cars[#ctx.cars + 1] = car
  ctx.player.car = car
  return car
end

local function press(ctx, name)
  ctx.eui.keys:feed("key", kit.KEYS[name], false)
  ctx.eui.keys:feed("key_up", kit.KEYS[name])
end

local function tick(ctx, dt)
  ctx.activities:update(dt or 0.05, ctx.eui.keys)
  ctx.eui.keys:flush()
end

-- ---------------------------------------------------------------- the layout

--- The chunks the game plays in: stream A's city when content/world is installed, else the step 0 testbed.
local function cityChunks()
  local ctx = kit.game()
  local world = ctx.content:data("world/world.lua")
  if not world then return testbed.chunks() end
  local out = {}
  for i = 0, math.ceil(world.bounds[3] / world.block) - 1 do
    for j = 0, math.ceil(world.bounds[4] / world.block) - 1 do
      local c = ctx.content:chunks("world/w_" .. i .. "_" .. j .. ".sgc")
      if c then for k, v in pairs(c) do out[k] = v end end
    end
  end
  return out
end
local cityCache
local function city()
  cityCache = cityCache or cityChunks()
  return cityCache
end

t.test("layout: the city gives 50 totems, 10 postcards, races, ranks, shops, garages and homes, the same every time", function()
  local chunks = city()
  local a, warn = layoutLib.generate(chunks, { seed = 1 })
  local b = layoutLib.generate(chunks, { seed = 1 })
  t.eq(layoutLib.serialise(a), layoutLib.serialise(b), "deterministic")
  local n = layoutLib.counts(a)
  t.eq(n.totems, 50)
  t.eq(n.postcards, 10)
  t.truthy(n.races >= 4, "races: " .. n.races)
  t.truthy(n.jumps >= 1)
  t.eq(n.taxi, 3)
  t.eq(n.depots, 3)
  t.eq(n.shops, 6)
  t.eq(n.garages, 3)
  t.truthy(n.properties >= 4, "properties")
  t.truthy(n.spots >= 20, "fare and parcel spots")
  t.eq(#layoutLib.check(a, chunks), 0, "everything is on the map and every race follows a road")
  t.truthy(type(warn) == "table")
  -- no two totems on top of each other, and none in a building or the sea
  for i = 1, #a.totems do
    for j = i + 1, #a.totems do
      local d = math.sqrt((a.totems[i].x - a.totems[j].x) ^ 2 + (a.totems[i].z - a.totems[j].z) ^ 2)
      t.truthy(d > 10, "totems " .. i .. " and " .. j .. " too close")
    end
    t.truthy(a.totems[i].y > 0.5, "a totem in the sea")
  end
end)

t.test("layout: the races climb, bend and follow real roads (elevation and curves count)", function()
  local l = layoutLib.generate(city(), { seed = 1 })
  local bends, rises = 0, 0
  for _, r in ipairs(l.races) do
    t.truthy(r.length >= 250, r.id .. " is long enough")
    t.truthy(r.gold < r.silver and r.silver < r.bronze, "medal times ascend")
    if r.turn > 1.5 then bends = bends + 1 end
    if r.rise > 3 then rises = rises + 1 end
  end
  t.truthy(bends >= 3, "most races bend")
  t.truthy(rises >= 2, "some races change height")
end)

t.test("layout: the file in content/ is good for the city as it is (run genlayout.lua when the city changes)", function()
  local ctx = game()
  local onDisk = ctx.content:data("activities/layout.lua")
  t.truthy(onDisk, "content/activities/layout.lua exists")
  -- the file is good for the city as it is now: everything on the map and in the open, every race on its roads, the counts
  local n = layoutLib.counts(onDisk)
  t.eq(n.totems, 50)
  t.eq(n.postcards, 10)
  t.truthy(n.races >= 4 and n.shops == 6 and n.garages == 3 and n.taxi == 3 and n.depots == 3 and n.properties >= 4)
  local problems = layoutLib.check(onDisk, city())
  t.eq(table.concat(problems, "; "), "", "run lua sg/activities/genlayout.lua content/world/w_*.sgc after the city changes")
end)

-- ---------------------------------------------------------------- collectibles

t.test("collect: every totem and postcard is found by walking up to it, once, and pays once", function()
  local ctx = game({ money = 0 })
  local c = ctx.activities.collect
  local totems = ctx.activities.layout.totems
  local seen = 0
  ctx.bus:on("pickup", function(d) if d.kind == "totem" then seen = seen + 1 end end, "test")
  t.eq(select(2, c:counts("totem")), 50)
  for _, it in ipairs(totems) do
    put(ctx, it.x + 1, it.z, 0, it.y)
    tick(ctx)
    tick(ctx) -- a second visit pays nothing
  end
  t.eq(seen, 50, "one pickup event each")
  t.eq(c:counts("totem"), 50)
  t.eq(wallet.balance(ctx), 50 * 40, "40 dollars a totem, once")
  for _, it in ipairs(ctx.activities.layout.postcards) do
    put(ctx, it.x, it.z, 0, it.y)
    tick(ctx)
  end
  t.eq(c:counts("postcard"), 10)
  t.eq(wallet.balance(ctx), 50 * 40 + 10 * 120)
  t.eq(ctx.progress.stats:get("moneyEarned"), 50 * 40 + 10 * 120, "the stats heard every payment")
end)

t.test("collect: a totem on another floor is not picked up from below", function()
  local ctx = game()
  local it = ctx.activities.layout.totems[1]
  put(ctx, it.x, it.z, 0)
  ctx.player.y = it.y - 9
  tick(ctx)
  t.eq(ctx.activities.collect:counts("totem"), 0)
end)

-- ---------------------------------------------------------------- races

local function straight(n, step)
  local pts = {}
  for i = 0, n - 1 do pts[#pts + 1] = i * step pts[#pts + 1] = 0 pts[#pts + 1] = 0 end
  return { id = "straight", name = "Test Straight", cp = 4, pts = pts, gold = 12.5, silver = 14, bronze = 18, pay = { gold = 100, silver = 60, bronze = 30 } }
end

--- Run a race along the straight at speed v with a frame time dt until it ends. Returns the manager's result.
local function runStraight(ctx, def, v, dt)
  local mgr = ctx.activities
  local car = ctx.player.car
  put(ctx, 0, 0, 0)
  car.h = 0
  mgr:startRace(def)
  local guard = 0
  -- the count-in: standing on the line
  while mgr.active and mgr.active.phase == "count" and guard < 1000 do tick(ctx, dt) guard = guard + 1 end
  local ghostGaps = {}
  while mgr.active and guard < 4000 do
    car.x = car.x + v * dt
    car.v = v
    tick(ctx, dt)
    if mgr.active and mgr.active.phase == "run" then ghostGaps[#ghostGaps + 1] = mgr.active:gap() end
    guard = guard + 1
  end
  return mgr.section.races[def.id], ghostGaps
end

t.test("race: times are exact whatever the frame time (20 u/s over 240 units is 12.00 s)", function()
  for _, dt in ipairs({ 0.05, 0.02, 1 / 30, 0.2, 0.125 }) do
    local ctx = game()
    giveCar(ctx)
    local def = straight(21, 12)
    local store = runStraight(ctx, def, 20, dt)
    t.truthy(store and store.best, "finished at dt " .. dt)
    t.near(store.best, 12.0, 0.011, "time at dt " .. dt)
  end
end)

t.test("race: medals by the par times, paid once at their best, and the stats and tracker hear it", function()
  local ctx = game({ money = 0 })
  giveCar(ctx)
  local def = straight(21, 12)
  local store = runStraight(ctx, def, 20, 0.05) -- 12.0 s: gold
  t.eq(store.medal, "gold")
  t.eq(wallet.balance(ctx), 100)
  t.eq(ctx.progress.stats:get("racesRun"), 1)
  t.eq(ctx.progress.stats:get("racesGold"), 1)
  runStraight(ctx, def, 20, 0.05) -- the same again pays nothing more
  t.eq(wallet.balance(ctx), 100)
  t.eq(ctx.progress.stats:get("racesRun"), 2)
  -- a silver-pace run first on a fresh game pays the silver, then gold pays the difference
  local ctx2 = game({ money = 0 })
  giveCar(ctx2)
  runStraight(ctx2, def, 17.5, 0.05) -- 13.7 s: silver
  t.eq(ctx2.activities.section.races.straight.medal, "silver")
  t.eq(wallet.balance(ctx2), 60)
  runStraight(ctx2, def, 20, 0.05)
  t.eq(ctx2.activities.section.races.straight.medal, "gold")
  t.eq(wallet.balance(ctx2), 100, "gold tops it up to the gold prize")
  -- slower than bronze: finished, no medal, no money, but it counts as run
  local ctx3 = game({ money = 0 })
  giveCar(ctx3)
  local s3 = runStraight(ctx3, def, 12.5, 0.05) -- 19.2 s
  t.eq(s3.medal, "none")
  t.eq(wallet.balance(ctx3), 0)
  t.truthy(s3.best, "a finish is recorded")
end)

t.test("race: your best run is the ghost, the gap is ahead or behind in seconds, a slower run does not replace it", function()
  local ctx = game()
  giveCar(ctx)
  local def = straight(21, 12)
  runStraight(ctx, def, 20, 0.05) -- 12 s sets the ghost
  local store = ctx.activities.section.races.straight
  t.truthy(store.ghost and #store.ghost > 40, "the ghost was kept")
  local _, gaps = runStraight(ctx, def, 24, 0.05) -- faster: ahead of the ghost the whole way
  local ahead = 0
  for _, g in ipairs(gaps) do if g and g < 0 then ahead = ahead + 1 end end
  t.truthy(ahead > #gaps * 0.8, "ahead of the ghost most of the run")
  t.near(ctx.activities.section.races.straight.best, 10.0, 0.011, "the faster run is the new best")
  runStraight(ctx, def, 16, 0.05) -- 15 s, slower
  t.near(ctx.activities.section.races.straight.best, 10.0, 0.011, "a slower run keeps the best")
  -- the ghost's car is drawn: a marker with the player's car model
  local r = raceLib.new(ctx, def, 10, store.ghost)
  r.phase, r.t = "run", 5
  local items = r:markers({}, ctx.player.car.spec)
  local found = false
  for _, m in ipairs(items) do if m.kind == "ghost" then found = true end end
  t.truthy(found, "a ghost marker")
end)

t.test("race: leaving the car, wrecking it, running out of time or pressing X ends it with no prize", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx)
  local def = straight(21, 12)
  local mgr = ctx.activities
  put(ctx, 0, 0, 0)
  mgr:startRace(def)
  for _ = 1, 80 do tick(ctx) end
  press(ctx, "x")
  tick(ctx)
  t.truthy(mgr.active == nil, "X abandons")
  mgr:startRace(def)
  for _ = 1, 80 do tick(ctx) end
  car.wrecked = true
  tick(ctx)
  t.truthy(mgr.active == nil, "wrecked ends it")
  car.wrecked = false
  mgr:startRace(def)
  ctx.player.car = nil
  for _ = 1, 200 do tick(ctx) end
  t.truthy(mgr.active == nil, "on foot for long ends it")
  ctx.player.car = car
  mgr:startRace(def)
  for _ = 1, 1500 do tick(ctx) end -- standing still: too slow
  t.truthy(mgr.active == nil, "the clock runs out")
  t.eq(wallet.balance(ctx), 0)
  t.eq(ctx.progress.stats:get("racesRun"), 0)
end)

t.test("race: every race in the city can be driven to the end, along its curves and hills, and a gate can be missed once", function()
  local ctx = game()
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local done = 0
  for _, def in ipairs(mgr.layout.races) do
    local route = raceLib.route(def)
    put(ctx, def.pts[1], def.pts[3], 0)
    car.y = def.pts[2]
    mgr:startRace(def)
    local guard = 0
    while mgr.active and mgr.active.phase == "count" do tick(ctx) guard = guard + 1 end
    local s = 0
    while mgr.active and guard < 4000 do
      s = s + 20 * 0.05
      local x, y, z, h = raceLib.pointAt(route, s)
      car.x, car.y, car.z, car.h, car.v = x, y, z, h, 20
      tick(ctx)
      guard = guard + 1
    end
    local store = mgr.section.races[def.id]
    t.truthy(store and store.best, def.id .. " finished")
    t.near(store.best, route.total / 20, 0.6, def.id .. " time matches the route length")
    done = done + 1
  end
  t.eq(done, #mgr.layout.races)
  t.eq(select(1, mgr:counts("races")), #mgr.layout.races)
  -- missing one gate by cutting wide still lets you carry on
  local def = straight(21, 12)
  local r = raceLib.new(ctx, def, nil, nil)
  r.phase, r.t, r.prev = "run", 0, { x = 0, z = 0 }
  car.x, car.z = 0, 0
  put(ctx, 0, 0, 0)
  r.next = 1
  -- cut wide of gate 1 and go through gate 2 in one step
  local g1, g2 = r.route.gates[1], r.route.gates[2]
  r.prev = { x = g1.x - 1, z = 20 }
  ctx.player.car.x, ctx.player.car.z = g2.x + 1, 0
  r:update(0.05)
  t.eq(r.next, 3, "gates 1 and 2 both counted")
end)

-- ---------------------------------------------------------------- taxi and parcels

t.test("taxi: ENTER at a rank starts a shift; fares pay by distance and time, damage cuts the pay, streaks add", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local rank = mgr.layout.taxi[1]
  put(ctx, rank.x, rank.z, 0)
  tick(ctx)
  local prompt = mgr:prompt()
  t.truthy(prompt and prompt.key == "ENTER" and prompt.text:find("taxi"), "the rank offers a shift")
  press(ctx, "enter")
  tick(ctx)
  t.eq(mgr.kind, "taxi")
  local job = mgr.active
  local startMoney = wallet.balance(ctx)
  -- pick up and drop off three fares
  for fare = 1, 3 do
    t.eq(job.stage, "pickup")
    put(ctx, job.stop.x, job.stop.z, 0)
    tick(ctx)
    t.eq(job.stage, "ride", "passenger aboard")
    put(ctx, job.stop.x, job.stop.z, 0)
    tick(ctx)
    t.eq(job.count, fare)
  end
  t.truthy(wallet.balance(ctx) > startMoney + 3 * 40, "paid")
  t.eq(ctx.progress.stats:get("fares"), 3)
  t.eq(mgr.section.jobs.fares, 3)
  -- the pay formula: distance, time left, damage, streak
  t.truthy(jobLib.farePay(300, 20, 0, 0) > jobLib.farePay(100, 20, 0, 0))
  t.truthy(jobLib.farePay(300, 30, 0, 0) > jobLib.farePay(300, 0, 0, 0))
  t.truthy(jobLib.farePay(300, 20, 0.3, 0) < jobLib.farePay(300, 20, 0, 0))
  t.truthy(jobLib.farePay(300, 20, 0, 3) > jobLib.farePay(300, 20, 0, 0))
  -- you must stop: driving through the pickup does not count
  put(ctx, job.stop.x, job.stop.z, 20)
  tick(ctx)
  t.eq(job.stage, "pickup", "no stop, no passenger")
  press(ctx, "x")
  tick(ctx)
  t.truthy(mgr.active == nil, "X ends the shift")
  car.health = car.health
end)

t.test("taxi: a passenger who waits too long gets out, and the shift ends", function()
  local ctx = game({ money = 0 })
  giveCar(ctx)
  local mgr = ctx.activities
  local rank = mgr.layout.taxi[1]
  put(ctx, rank.x, rank.z, 0)
  press(ctx, "enter")
  tick(ctx)
  local job = mgr.active
  put(ctx, job.stop.x, job.stop.z, 0)
  tick(ctx)
  t.eq(job.stage, "ride")
  put(ctx, job.stop.x + 500, job.stop.z, 0)
  for _ = 1, math.ceil((job.limit + 2) / 0.05) do tick(ctx) end
  t.truthy(mgr.active == nil, "the shift ended")
  t.eq(wallet.balance(ctx), 0, "no pay for a fare that walked")
end)

t.test("parcels: a run from a depot is three timed drops with a bonus when all are on time", function()
  local ctx = game({ money = 0 })
  giveCar(ctx)
  local mgr = ctx.activities
  local depot = mgr.layout.depots[1]
  put(ctx, depot.x, depot.z, 0)
  press(ctx, "enter")
  tick(ctx)
  t.eq(mgr.kind, "delivery")
  local job = mgr.active
  t.eq(job.total, 3)
  local drops = 0
  while mgr.active and drops < 5 do
    put(ctx, job.stop.x, job.stop.z, 0)
    tick(ctx)
    drops = drops + 1
  end
  t.eq(drops, 3)
  t.eq(ctx.progress.stats:get("deliveries"), 3)
  t.eq(mgr.section.jobs.deliveries, 3)
  t.truthy(wallet.balance(ctx) >= 3 * 70 + 150, "three drops and the on-time bonus")
  -- a taxi needs a car
  ctx.player.car = nil
  put(ctx, depot.x, depot.z, 0)
  press(ctx, "enter")
  tick(ctx)
  t.truthy(mgr.active == nil)
end)

-- ---------------------------------------------------------------- stunt jumps

t.test("jumps: every stunt jump can be landed; the jump event carries the distance; each pays the first time only", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local events = {}
  ctx.bus:on("jump", function(d) events[#events + 1] = d end, "test")
  for _, j in ipairs(mgr.layout.jumps) do
    put(ctx, j.x - math.cos(j.h) * 6, j.z - math.sin(j.h) * 6, 20)
    car.h, car.airborne, car.roll, car.pitch = j.h, false, 0, 0
    tick(ctx)
    car.airborne = true
    for i = 1, 30 do
      car.x, car.z = car.x + math.cos(j.h) * 20 * 0.05, car.z + math.sin(j.h) * 20 * 0.05
      tick(ctx)
    end
    car.airborne = false
    tick(ctx)
  end
  local done, total = mgr.jumps:counts()
  t.eq(done, total, "all landed")
  t.truthy(total >= 1)
  t.eq(#events, total, "a jump event for each")
  t.truthy(events[1].landed and events[1].distance > 10, "the distance")
  local paid = wallet.balance(ctx)
  t.truthy(paid >= total * 200)
  -- again: no more money
  local j = mgr.layout.jumps[1]
  put(ctx, j.x - math.cos(j.h) * 6, j.z - math.sin(j.h) * 6, 20)
  car.h = j.h
  tick(ctx)
  car.airborne = true
  for _ = 1, 30 do car.x, car.z = car.x + math.cos(j.h) * 1, car.z + math.sin(j.h) * 1 tick(ctx) end
  car.airborne = false
  tick(ctx)
  t.eq(wallet.balance(ctx), paid, "no second payment")
  t.eq(ctx.progress.stats:get("jumps") >= total, true)
end)

t.test("jumps: a hop that is too short, a crash landing and taking off facing the wrong way do not count", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local j = mgr.layout.jumps[1]
  local function jump(distance, wrecked, facing)
    put(ctx, j.x, j.z, 20)
    car.h, car.airborne, car.wrecked = facing or j.h, false, wrecked
    tick(ctx)
    car.airborne = true
    for _ = 1, 20 do
      car.x, car.z = car.x + math.cos(j.h) * distance / 20, car.z + math.sin(j.h) * distance / 20
      tick(ctx)
    end
    car.airborne = false
    tick(ctx)
    car.wrecked = false
  end
  jump(3, false)
  t.eq((mgr.jumps:counts()), 0, "too short")
  jump(30, true)
  t.eq((mgr.jumps:counts()), 0, "wrecked on landing")
  jump(30, false, j.h + 3)
  t.eq((mgr.jumps:counts()), 0, "wrong way round")
  jump(30, false)
  t.eq((mgr.jumps:counts()), 1)
end)

-- ---------------------------------------------------------------- shops, property, garage

t.test("shops: respray, tune tiers and clothes cost money, change the car, and say no when you are broke", function()
  local ctx = game({ money = 100 })
  local car = giveCar(ctx)
  local shops = ctx.activities.shops
  local ok, why = shops:respray("blue")
  t.truthy(not ok and why:find("Not enough"), "too poor for a respray")
  wallet.add(ctx, 5000, "test")
  local before = wallet.balance(ctx)
  t.truthy(shops:respray("blue"))
  t.eq(car.colour, "blue")
  t.eq(wallet.balance(ctx), before - 150)
  t.truthy(not shops:respray("blue"), "already that colour")
  -- tune: tiers in order, the top is the top
  for tier = 1, 3 do t.truthy(shops:buyTune("engine"), "tier " .. tier) end
  t.eq(car.tune.engine, 3)
  t.truthy(not shops:buyTune("engine"), "no tier 4")
  t.eq(ctx.progress.stats:get("tuneMax"), 3)
  -- clothes
  t.truthy(shops:buyOutfit("cinder"))
  t.eq(ctx.save.player.outfit, "cinder")
  t.eq(ctx.player.outfit.shirt, "red")
  t.truthy(shops:buyOutfit("deckhand"), "an owned outfit is just worn")
  t.eq(ctx.progress.stats:get("outfits"), 1)
  local g = ctx.activities.section.goals
  t.truthy(g.respray and g.tune and g.tunemax and g.outfit)
  -- no car, no respray
  ctx.player.car = nil
  t.truthy(not shops:respray("green"))
end)

t.test("property: buying costs the price, rent comes every 24 game hours from time_of_day, and from a wall clock without one", function()
  local ctx = game({ money = 0 })
  local mgr = ctx.activities
  local p = mgr.layout.properties[1]
  local prop = mgr.property
  t.truthy(not prop:buy(p.id), "too poor")
  wallet.add(ctx, p.price + 1000, "test")
  local after = wallet.balance(ctx)
  t.truthy(prop:buy(p.id))
  t.eq(wallet.balance(ctx), after - p.price)
  t.truthy(prop:owned(p.id))
  t.truthy(not prop:buy(p.id), "once")
  -- the world's clock: from 18:00 around midnight to 18:00 again is one day
  local money = wallet.balance(ctx)
  for _, h in ipairs({ 18, 21, 23.5, 2, 6, 12, 17.9 }) do ctx.bus:emit("time_of_day", { hour = h, phase = "day" }) end
  t.eq(wallet.balance(ctx), money, "not a day yet")
  ctx.bus:emit("time_of_day", { hour = 18.2, phase = "dusk" })
  t.eq(wallet.balance(ctx), money + p.income, "a day passed")
  t.eq(mgr.section.rent.days, 1)
  -- three more days, in steps
  for day = 1, 3 do
    for _, h in ipairs({ 22, 3, 9, 15, 19 }) do ctx.bus:emit("time_of_day", { hour = h, phase = "day" }) end
  end
  t.eq(mgr.section.rent.days, 4)
  t.eq(wallet.balance(ctx), money + 4 * p.income)
  t.eq(ctx.progress.stats:get("rentEarned"), 4 * p.income)
  -- two homes pay twice
  local q = mgr.layout.properties[2]
  wallet.add(ctx, q.price, "test")
  prop:buy(q.id)
  t.eq(prop:dailyIncome(), p.income + q.income)
  -- once the world has a clock (it sent time_of_day), the wall clock is not also counted
  local ctx3 = game({ money = 0 })
  local m3 = ctx3.activities
  wallet.add(ctx3, m3.layout.properties[1].price, "test")
  m3.property:buy(m3.layout.properties[1].id)
  ctx3.bus:emit("time_of_day", { hour = 10, phase = "day" })
  local bal3 = wallet.balance(ctx3)
  for _ = 1, math.ceil(2500 / 0.5) do m3:update(0.5, ctx3.eui.keys) end
  t.eq(wallet.balance(ctx3), bal3, "no rent from a wall clock when the world keeps its own")
  -- no clock from the world: a day is twenty minutes
  local ctx2 = game({ money = 0 })
  local m2 = ctx2.activities
  local p2 = m2.layout.properties[1]
  wallet.add(ctx2, p2.price, "test")
  m2.property:buy(p2.id)
  local bal = wallet.balance(ctx2)
  for _ = 1, math.ceil(1300 / 0.5) do m2:update(0.5, ctx2.eui.keys) end
  t.truthy(wallet.balance(ctx2) >= bal + p2.income, "a day of wall clock pays rent")
end)

t.test("garage: store the car you drive, take it out again with its paint and tune, capacity grows with property", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx, 10, 10)
  car.colour = "green"
  car.tune = { engine = 2 }
  local mgr = ctx.activities
  local gar = mgr.layout.garages[1]
  t.eq(mgr.garage:capacity(), 3)
  t.truthy(mgr.garage:store(gar))
  t.truthy(ctx.player.car == nil)
  t.eq(#ctx.cars, 0, "the car left the street")
  t.eq(mgr.garage:count(), 1)
  t.truthy(mgr.section.goals.storecar)
  t.truthy(mgr.garage:takeOut(1, gar))
  local out = ctx.player.car
  t.truthy(out and out.colour == "green" and out.tune.engine == 2, "paint and tune kept")
  t.eq(#ctx.cars, 1)
  t.eq(mgr.garage:count(), 0)
  -- full
  for i = 1, 3 do
    ctx.player.car = vehicle.new("pipit", 0, 0, 0, "red")
    ctx.cars[#ctx.cars + 1] = ctx.player.car
    t.truthy(mgr.garage:store(gar), "car " .. i)
  end
  ctx.player.car = vehicle.new("pipit", 0, 0, 0, "red")
  local ok, why = mgr.garage:store(gar)
  t.truthy(not ok and why:find("full"))
  -- a home adds places
  wallet.add(ctx, 1e6, "test")
  mgr.property:buy(mgr.layout.properties[1].id)
  t.eq(mgr.garage:capacity(), 5)
  t.truthy(mgr.garage:store(gar))
  -- the police do not park here
  local cop = vehicle.new("cruiser", 0, 0, 0)
  ctx.player.car = cop
  t.truthy(not mgr.garage:store(gar))
end)

t.test("places: the prompt names what ENTER does, and ENTER opens the shop, garage and property screens", function()
  local ctx = game({ money = 50000 })
  giveCar(ctx)
  local mgr = ctx.activities
  for _, kind in ipairs({ "shop", "garage", "property" }) do
    for _, p in ipairs(mgr.places) do
      if p.kind == kind and (kind ~= "shop" or p.shop == "respray") then
        put(ctx, p.x, p.z, 0)
        tick(ctx)
        local prompt = mgr:prompt()
        t.truthy(prompt and prompt.text:find(p.name, 1, true), kind .. " prompt: " .. tostring(prompt and prompt.text))
        press(ctx, "enter")
        tick(ctx)
        local top = ctx.ui.top()
        t.eq(top.name, "e_menu", kind .. " opened its screen")
        kit.frame(ctx)
        t.eq(ctx.screen.overflow, 0, kind .. " screen stays inside 51x19")
        press(ctx, "backspace")
        kit.frame(ctx)
        t.eq(ctx.ui.top().name, "play", kind .. " closes with BACKSPACE")
        break
      end
    end
  end
end)

-- ---------------------------------------------------------------- 100%

t.test("100%: every activity done adds up to exactly 100, each achievement fired once, and nothing less does", function()
  local ctx = game({ money = 0 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local comp = ctx.progress.completion
  t.eq(comp:weightSum(), 100)
  t.eq(comp:percent(), 0)
  local fired = {}
  ctx.bus:on("achievement", function(d) fired[d.id] = (fired[d.id] or 0) + 1 end, "test")
  wallet.add(ctx, 1e7, "test")
  -- the story (24 jobs)
  for i = 1, 24 do ctx.save.story.done["m" .. i] = true end
  ctx.save.story.finished = true
  t.truthy(comp:percent() > 29.9 and comp:percent() < 30.1, "the story is worth 30")
  -- totems and postcards
  for _, kind in ipairs({ "totems", "postcards" }) do
    for _, it in ipairs(mgr.layout[kind]) do
      put(ctx, it.x, it.z, 0, it.y)
      tick(ctx)
    end
  end
  -- jumps
  for _, j in ipairs(mgr.layout.jumps) do
    put(ctx, j.x, j.z, 20)
    car.h, car.airborne = j.h, false
    tick(ctx)
    car.airborne = true
    for _ = 1, 30 do car.x, car.z = car.x + math.cos(j.h) , car.z + math.sin(j.h) tick(ctx) end
    car.airborne = false
    tick(ctx)
  end
  -- races
  for _, def in ipairs(mgr.layout.races) do
    local route = raceLib.route(def)
    put(ctx, def.pts[1], def.pts[3], 0)
    mgr:startRace(def)
    while mgr.active and mgr.active.phase == "count" do tick(ctx) end
    local s = 0
    while mgr.active do
      s = s + 1
      local x, y, z = raceLib.pointAt(route, s)
      car.x, car.y, car.z, car.v = x, y, z, 20
      tick(ctx)
    end
  end
  -- taxi fares and parcels
  local rank, depot = mgr.layout.taxi[1], mgr.layout.depots[1]
  for _ = 1, 9 do
    put(ctx, rank.x, rank.z, 0)
    mgr:update(0.05, ctx.eui.keys)
    press(ctx, "enter")
    tick(ctx)
    for _ = 1, 3 do
      put(ctx, mgr.active.stop.x, mgr.active.stop.z, 0) tick(ctx)
      put(ctx, mgr.active.stop.x, mgr.active.stop.z, 0) tick(ctx)
    end
    press(ctx, "x")
    tick(ctx)
    put(ctx, depot.x, depot.z, 0)
    tick(ctx)
    press(ctx, "enter")
    tick(ctx)
    while mgr.active do put(ctx, mgr.active.stop.x, mgr.active.stop.z, 0) tick(ctx) end
  end
  -- property
  for _, p in ipairs(mgr.layout.properties) do t.truthy(mgr.property:buy(p.id)) end
  -- the garage and shops
  mgr.shops:respray("cyan")
  for i = 1, 3 do mgr.shops:buyTune("engine") end
  mgr.shops:buyOutfit("gull")
  mgr.garage:store(mgr.layout.garages[1])
  -- stats that no activity gives: the rest of the achievements
  local st = ctx.progress.stats
  st:set("distance", 20000) st:set("onFoot", 3000) st:set("topSpeed", 160) st:set("airtime", 30) st:set("carsStolen", 12)
  st:set("maxHeat", 6) st:set("heatCleared", 4) st:set("longestJump", 50)
  for _, d in ipairs({ "gilt", "lantern", "cinder", "brine", "mid" }) do ctx.bus:emit("district_enter", { district = d }) end
  for _, s in ipairs({ "gull", "gilt", "lantern", "iron" }) do st:member("stations", s) end
  for i = 1, 8 do ctx.bus:emit("mission_end", { id = "x" .. i, result = "pass" }) end
  ctx.progress.achievements:check()
  ctx.progress.achievements:check()
  local res = comp:compute()
  local missing = {}
  for _, p in ipairs(res.parts) do
    if p.done < p.total then missing[#missing + 1] = p.id .. " " .. p.done .. "/" .. p.total end
  end
  for _, a in ipairs(ctx.progress.achievements:list()) do
    if not a.unlocked and a.id ~= "completionist" then missing[#missing + 1] = "ach " .. a.id end
  end
  t.eq(table.concat(missing, ", "), "", "every part complete")
  t.eq(res.percent, 100)
  t.eq(comp:display(), "100")
  t.eq(ctx.progress.achievements:count(), 40, "all 40 achievements")
  local twice = {}
  for id, n in pairs(fired) do if n ~= 1 then twice[#twice + 1] = id end end
  t.eq(#twice, 0, "each achievement fired exactly once")
  local n = 0
  for _ in pairs(fired) do n = n + 1 end
  t.eq(n, 40)
end)

-- ---------------------------------------------------------------- with stream B's customization and fleet

local function gameWithFleet(money)
  local ctx = kit.game({ money = money or 0, names = { "e_progress", "e_ui", "e_activities", "e_radio", "e_zlast", "b_vehicles" },
    stream = { groundAt = function() return 0 end, surface = function() return "land" end } })
  ctx.eui.titleShown = true
  t.truthy(ctx.fleet, "stream B's fleet is there: " .. table.concat((function()
    local out = {}
    for _, f in ipairs(ctx.failed or {}) do out[#out + 1] = f.name .. ": " .. f.err end
    return out
  end)(), "; "))
  local car = ctx.fleet:spawn("marlin", 0, 0, 0, { paint = "red", detached = true })
  ctx.cars[#ctx.cars + 1] = car
  ctx.player.car = car
  return ctx, car
end

t.test("shops with B's data: paint and stripes priced from the car's value, tune tiers named and priced by the data, applied through custom.apply", function()
  local snap = kit.snapshot()
  local ctx, car = gameWithFleet(20000)
  local shops = ctx.activities.shops
  local custom = require("sg.vehicles.custom")
  local paints, price = shops:paints()
  t.eq(#paints, 12, "B's twelve paints (none on the sky's slots)")
  t.eq(price, custom.paintPrice(car.spec), "a coat costs a share of the car's value")
  local before = wallet.balance(ctx)
  t.truthy(shops:respray("cyan"))
  t.eq(wallet.balance(ctx), before - price)
  t.eq(car.paint.body, "cyan")
  t.truthy(car.colour:find("^cyan"), "the colour string the models read: " .. car.colour)
  t.truthy(not shops:respray("cyan"), "same colour again")
  local stripes, sprice = shops:stripes()
  t.truthy(stripes and #stripes >= 5 and sprice > 0)
  t.truthy(shops:stripe("white"))
  t.eq(car.paint.stripe, "white")
  t.truthy(car.colour:find("cyan:white", 1, true), car.colour)
  t.truthy(not shops:stripe("white"))
  -- tune: B's tier names and prices, and the car's numbers change
  local tier, max, name, tprice = shops:tuneInfo("engine")
  t.eq(tier, 0)
  t.eq(max, 3)
  t.truthy(name and tprice == custom.price(car.spec.base or car.spec, "engine", 1), tostring(name) .. " " .. tostring(tprice))
  local topBefore = car.spec.top
  t.truthy(shops:buyTune("engine"))
  t.eq(car.tune.engine, 1)
  t.truthy(car.spec.top > topBefore, "the tune raised the top speed")
  for _ = 1, 2 do t.truthy(shops:buyTune("engine")) end
  t.truthy(not shops:buyTune("engine"), "no fourth tier")
  t.eq(ctx.progress.stats:get("tuneMax"), 3)
  t.truthy(ctx.activities.section.goals.tunemax)
  local slots = shops:slots()
  t.eq(#slots, 4)
  -- the menu rows name the next tier and its price
  local menus = require("sg.activities.menus").new(ctx, ctx.activities, ctx.eui.screens)
  for _, p in ipairs(ctx.activities.places) do
    if p.kind == "shop" and p.shop == "tune" then menus.open("shop", p) break end
  end
  kit.frame(ctx)
  t.truthy(ctx.screen.find("Engine") and ctx.screen.find("MAX"), ctx.screen.text())
  t.eq(ctx.screen.overflow, 0)
  kit.restore(snap)
end)

t.test("garage with B's fleet: the stored car keeps its paint, stripe, tune and damage, and comes back as a built car in the street", function()
  local snap = kit.snapshot()
  local ctx, car = gameWithFleet(50000)
  local mgr = ctx.activities
  mgr.shops:respray("purple")
  mgr.shops:stripe("yellow")
  mgr.shops:buyTune("brakes")
  car.health = car.spec.health * 0.5
  local gar = mgr.layout.garages[1]
  t.truthy(mgr.garage:store(gar))
  local e = mgr.garage:cars()[1]
  t.eq(e.paint.body, "purple")
  t.eq(e.paint.stripe, "yellow")
  t.eq(e.tune.brakes, 1)
  t.near(e.health, 0.5, 0.02)
  t.eq(#ctx.cars, 0)
  t.truthy(mgr.garage:takeOut(1, gar))
  local out = ctx.player.car
  t.truthy(out ~= car and out.paint.body == "purple" and out.paint.stripe == "yellow" and out.tune.brakes == 1)
  t.near(out.health / out.spec.health, 0.5, 0.05, "the damage stayed")
  t.eq(#ctx.cars, 1, "it is in the street list exactly once")
  t.eq(ctx.cars[1], out)
  -- the garage list shows the car by its definition's name and its paint
  t.truthy(mgr.garage:store(gar))
  local menus = require("sg.activities.menus").new(ctx, mgr, ctx.eui.screens)
  menus.open("garage", gar)
  kit.frame(ctx)
  t.truthy(ctx.screen.find("Take out: Marlin"), ctx.screen.text())
  kit.restore(snap)
end)
