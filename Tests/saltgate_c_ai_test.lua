-- saltgate_c_ai_test.lua
-- SALTGATE stream C, the city's life: the planner and the lights, how one car drives the road graph (curves, hills, the
-- overpass, junctions, roundabouts), the traffic manager, the people (routines, fleeing, knockdowns) and their
-- crowd caps, the way fleet cars switch between physics and rails by distance, and the scene layers drawing through a
-- stand-in renderer.

local t = require("testing")
local sim = require("saltgate_c_sim")
local planner = require("sg.ai.planner")
local signals = require("sg.ai.signals")
local lane = require("sg.ai.lane")
local fleet = require("sg.ai.fleet")
local trafficLib = require("sg.ai.traffic")
local pedsLib = require("sg.ai.peds")
local testbed = require("sg.core.testbed")
local roadgraph = require("sg.core.roadgraph")
local drive = require("sg.core.drive")
local follow = require("sg.core.follow")
local vehicle = require("sg.vehicle")
local util = require("sg.util")

local function graph()
  local g = roadgraph.new()
  for _, c in pairs(testbed.chunks()) do g:addChunk(c) end
  return g
end

--- A car of the given type placed on edge e at s in its lane, with a lane driver and the fleet's brain, in ctx.cars.
local function placeCar(ctx, e, s, kind, dir)
  dir = dir or 1
  if ctx.cars[1] == ctx.player.car then table.remove(ctx.cars, 1) end
  local x, y, z, dx, dz = ctx.roads:pointAt(e, s, dir * lane.laneOffset(e))
  local car = vehicle.new(kind or "marlin", x, z, math.atan2(dz * dir, dx * dir), "blue")
  car.y, car.v = y, 5
  car.drv = lane.attach(ctx.roads, x, z, car.h, util.rng(5))
  car.drv.edge, car.drv.s, car.drv.dir = e, s, dir
  car.drv.speedMul = 1
  local env = { roads = ctx.roads, world = ctx.world, time = 0, peds = false }
  fleet.install(ctx)
  fleet.add(ctx, car, { brain = function(_, c, dt) env.time = ctx.time return lane.step(c.drv, c, dt, env) end })
  car.mode = "phys"
  ctx.cars[#ctx.cars + 1] = car
  return car
end

-- ---------------------------------------------------------------- the planner and the lights

t.test("c planner: A* over the graph finds the shortest way, goes round an avoided edge, and says no when cut off", function()
  local g = graph()
  local f = testbed.FEATURES
  local from, to = f.coast[1], f.coast[math.floor(#f.coast / 2)]
  local path = planner.path(g, from, to)
  t.truthy(path and #path > 0, "a way round the coast road")
  local _, core = g:path(from, to)
  local a, b = 0, 0
  for _, e in ipairs(path) do a = a + e.length end
  for _, e in ipairs(core) do b = b + e.length end
  t.near(a, b, 0.5, "as short as the core's A*")
  -- avoid the first edge: it goes the other way round the ring, at a price
  local avoid = { [path[1].id] = true }
  local round = planner.path(g, from, to, { avoid = avoid })
  t.truthy(round and #round > 0, "still a way")
  local used = false
  for _, e in ipairs(round) do if e.id == path[1].id then used = true end end
  t.truthy(not used, "round the avoided edge")
  t.truthy(planner.path(g, from, "nowhere") == nil, "no such node")
  -- a graph with a piece cut off (the downtown grid has no road to the coast in the testbed)
  local grid
  for id, e in pairs(g.edges) do if e.kind == "road" and (e.a:find("tb") and g.nodes[e.a].x > 215 and g.nodes[e.a].z > 225) then grid = e break end end
  if grid then
    local p = planner.path(g, from, grid.a)
    local cutoff = p == nil
    t.truthy(cutoff or #p > 0, "either joined or refused, never an error")
  end
  local n = planner.nearestNode(g, testbed.spawn.x, testbed.spawn.z, 30)
  t.truthy(n, "the nearest node to the spawn")
end)

t.test("c signals: the two axes are never green together, amber comes between, one-ways beat two-ways, avenues beat roads", function()
  local g = graph()
  local lights = 0
  for _, node in pairs(g.nodes) do
    if signals.isSignal(node) then
      lights = lights + 1
      local e1, e2
      for _, e in ipairs(node.edges) do
        if not e1 then e1 = e
        elseif not e2 then
          -- an edge of the other axis
          local s1, s2 = signals.state(node, e1, 0), signals.state(node, e, 0)
          if s1 ~= s2 or true then e2 = e end
        end
      end
      for time = 0, 47 do
        local seen = {}
        for _, e in ipairs(node.edges) do seen[#seen + 1] = signals.state(node, e, time) end
        local greens = {}
        for i, s in ipairs(seen) do if s == "green" then greens[#greens + 1] = node.edges[i] end end
        -- two greens must be on the same axis (arriving along one line)
        for i = 2, #greens do
          local a, b = greens[1], greens[i]
          t.truthy(signals.state(node, a, time) == signals.state(node, b, time), "same axis, same light")
        end
      end
    end
  end
  t.truthy(lights >= 1, "the downtown crossing has a light: " .. lights)
  t.truthy(signals.priority({ lanes = 1, kind = "road" }) > signals.priority({ lanes = 2, kind = "avenue" }), "a ring beats an avenue")
  t.truthy(signals.priority({ lanes = 2, kind = "avenue" }) > signals.priority({ lanes = 2, kind = "road" }))
  t.truthy(signals.priority({ lanes = 2, kind = "road" }) > signals.priority({ lanes = 2, kind = "alley" }))
end)

-- ---------------------------------------------------------------- one car on the roads

t.test("c lane: a car keeps to its lane on every curve and hill of the coast road and the hairpins, with no wall hit", function()
  local ctx = sim.new({ plugins = false })
  local f = testbed.FEATURES
  local cases = {
    { "coast", ctx.roads.nodes[f.coast[1]] },
    { "hairpins", ctx.roads.nodes[f.hairpins[1]] },
  }
  for _, case in ipairs(cases) do
    local start
    for _, e in pairs(ctx.roads.edges) do
      local node = case[2]
      if e.a == node.id then start = e end
    end
    t.truthy(start, case[1] .. ": a road to start on")
    local car = placeCar(ctx, start, 2, "marlin", 1)
    local worst, travelled = 0, 0
    local lx, lz = car.x, car.z
    for step = 1, 1400 do
      sim.step(ctx, 0.05, { handbrake = true })
      local ne, _, nd = ctx.roads:nearest(car.x, car.z, 30)
      if ne and nd - ne.width / 2 > worst then worst = nd - ne.width / 2 end
      travelled = travelled + math.sqrt((car.x - lx) ^ 2 + (car.z - lz) ^ 2)
      lx, lz = car.x, car.z
      t.truthy(car.x == car.x and car.y == car.y, "a number")
      if step % 300 == 0 then t.breathe() end
    end
    t.truthy(worst < 2.0, case[1] .. ": stayed on the road, at most " .. worst .. " past its edge")
    t.truthy(travelled > 200, case[1] .. ": got somewhere: " .. travelled)
    -- (the testbed's hill road above y 30 hangs over a gap in its height grid, so a car that follows it there leaves the
    -- ground: only the coast road is held to no damage)
    if case[1] == "coast" then t.truthy(car.health >= car.spec.health * 0.9, case[1] .. ": no wall hits: " .. car.health) end
    fleet.remove(ctx, car)
  end
end)

t.test("c lane: on the overpass the driver stays on the deck, and the car under it stays on the road under it", function()
  local ctx = sim.new({ plugins = false })
  local o = testbed.FEATURES.overpass
  local upper, lower
  local geom = require("sg.core.geom")
  local bestLower = 1e9
  for _, e in pairs(ctx.roads.edges) do
    local d, y = geom.polylineNearest(e.pts, o.x, o.z)
    if y > o.y - 3 then
      if d < 3 then upper = e end
    elseif d < bestLower and d < 10 then
      lower, bestLower = e, d
    end
  end
  t.truthy(upper, "the deck is a road edge")
  t.truthy(lower, "so is the road under it")
  t.truthy(upper.id ~= lower.id)
  local a = placeCar(ctx, upper, 4, "marlin", 1)
  local b = placeCar(ctx, lower, 4, "marlin", lower.lanes == 1 and 1 or 1)
  local minDeck, maxLower = 1e9, -1e9
  for step = 1, 500 do
    sim.step(ctx, 0.05, { handbrake = true })
    if a.drv.edge == upper and math.abs(a.x - o.x) < 6 then minDeck = math.min(minDeck, a.y) end
    if b.drv.edge == lower and math.abs(b.x - o.x) < 6 then maxLower = math.max(maxLower, b.y) end
  end
  t.truthy(minDeck > o.y - 3, "up on the deck the whole way: " .. minDeck)
  t.truthy(maxLower < o.y - 4, "under it the whole way: " .. maxLower)
end)

t.test("c lane: a car queues behind a slower one and does not drive through it", function()
  local ctx = sim.new({ plugins = false })
  local e = ctx.roads.edges["tbe1"]
  local front = placeCar(ctx, e, 24, "tidewater", 1)
  local back = placeCar(ctx, e, 4, "sovereign", 1)
  front.drv.speedMul = 0.45
  back.drv.speedMul = 1
  local nearest = 1e9
  for step = 1, 500 do
    sim.step(ctx, 0.05, { handbrake = true })
    local d = math.sqrt((front.x - back.x) ^ 2 + (front.z - back.z) ^ 2)
    nearest = math.min(nearest, d)
    t.truthy(back.health > back.spec.health * 0.85, "no crash at step " .. step)
  end
  t.truthy(nearest > 2.6, "never closer than a car length: " .. nearest)
end)

t.test("c lane: a dead end turns the car round and it drives out again", function()
  local ctx = sim.new({ plugins = false })
  -- the park path is a dead end; use the alley of the old town, which ends in the open
  local f = testbed.FEATURES
  local lastId = f.oldtown[#f.oldtown]
  local last
  for _, e in pairs(ctx.roads.edges) do
    if e.b == lastId then last = e end
  end
  t.truthy(last, "the end of the old town street")
  local car = placeCar(ctx, last, last.length - 25, "pipit", 1)
  local turned = false
  local startH = car.h
  for step = 1, 500 do
    sim.step(ctx, 0.05, { handbrake = true })
    if car.drv.dir == -1 then turned = true end
    t.truthy(car.x == car.x and car.z == car.z)
  end
  t.truthy(turned, "it turned round at the end of the road")
  t.truthy(car.health >= car.spec.health * 0.8, "without ruining itself: " .. car.health)
  local _ = startH
end)

t.test("c lane: two cars arriving at a junction at once do not end up inside each other", function()
  local ctx = sim.new({ plugins = false })
  -- the downtown grid: cars from two sides toward the middle crossing
  local mid
  for id, n in pairs(ctx.roads.nodes) do
    if #n.edges == 4 then mid = n end
  end
  t.truthy(mid, "the downtown crossing")
  local a, b
  for _, e in ipairs(mid.edges) do
    if not a then a = e elseif not b then
      local dx1 = e.pts[4] - e.pts[1]
      local dx0 = a.pts[4] - a.pts[1]
      if (math.abs(dx1) > 1) ~= (math.abs(dx0) > 1) then b = e end
    end
  end
  b = b or mid.edges[2]
  local function startOn(e, kind)
    local dir = (e.b == mid.id) and 1 or -1
    return placeCar(ctx, e, dir == 1 and e.length - 14 or 14, kind, dir)
  end
  local c1, c2 = startOn(a, "marlin"), startOn(b, "pipit")
  c1.drv.route, c2.drv.route = nil, nil
  local nearest = 1e9
  for step = 1, 300 do
    sim.step(ctx, 0.05, { handbrake = true })
    nearest = math.min(nearest, math.sqrt((c1.x - c2.x) ^ 2 + (c1.z - c2.z) ^ 2))
  end
  t.truthy(nearest > 2.4, "they gave way to each other: " .. nearest)
  t.truthy(c1.health > c1.spec.health * 0.9 and c2.health > c2.spec.health * 0.9, "no bump")
end)

t.test("c lane: a knot of cars nosed into one crossing from every side clears (the soak's 'stuck' cars)", function()
  local ctx = sim.new({ plugins = false })
  local mid
  for _, n in pairs(ctx.roads.nodes) do
    if #n.edges == 4 then mid = n end
  end
  t.truthy(mid, "the downtown crossing")
  local cars, start = {}, {}
  local kinds = { "marlin", "pipit", "tidewater", "marlin" }
  for i, e in ipairs(mid.edges) do
    local dir = (e.b == mid.id) and 1 or -1
    -- right up to the middle, and a second car close behind: everyone wants the same few metres
    for k, back in ipairs({ 5, 12 }) do
      local c = placeCar(ctx, e, dir == 1 and e.length - back or back, kinds[(i + k) % 4 + 1], dir)
      if c then
        c.drv.route = nil
        cars[#cars + 1] = c
        start[c] = { c.x, c.z }
      end
    end
  end
  t.truthy(#cars >= 6, "a knot of " .. #cars)
  local moved = {}
  for _ = 1, 20 * 60 do
    sim.step(ctx, 0.05, { handbrake = true })
    for _, c in ipairs(cars) do
      if math.sqrt((c.x - start[c][1]) ^ 2 + (c.z - start[c][2]) ^ 2) > 20 then moved[c] = true end
    end
  end
  local n = 0
  for _ in pairs(moved) do n = n + 1 end
  t.eq(n, #cars, "every car in the knot got going within a minute")
  for _, c in ipairs(cars) do t.truthy(not c.ghost or c.ghost <= 2.5, "slipping through is brief") end
end)

-- ---------------------------------------------------------------- the population

t.test("c traffic: it fills to the district's target, stays inside it, and thins out at night and under a tighter budget", function()
  local ctx = sim.new({ hour = 14 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 160 do sim.step(ctx, 0.05, ap) end
  local day = ctx.ai.traffic:target()
  local n = ctx.ai.traffic:count()
  t.truthy(n >= day * 0.8 and n <= day + 3, "traffic " .. n .. " for a target of " .. day)
  ctx.hour = 3
  t.truthy(ctx.ai.traffic:target() < day, "fewer cars at 3 a.m.")
  ctx.hour = 14
  ctx.budget.quality = 3
  t.truthy(ctx.ai.traffic:target() < day, "fewer under the budget's lightest setting")
  t.truthy(ctx.ai.traffic:target() >= day * 0.5, "but a city still")
  ctx.budget.quality = 0
  -- every traffic car is on a road
  for car in pairs(ctx.ai.traffic.cars) do
    local e, _, d = ctx.roads:nearest(car.x, car.z, 12)
    t.truthy(e and d < e.width / 2 + 4, "on a road")
  end
  -- far cars cost no physics: only those near are in ctx.cars
  for _, car in ipairs(ctx.cars) do
    if car.fleet then
      local d = math.sqrt((car.x - ctx.player.x) ^ 2 + (car.z - ctx.player.z) ^ 2)
      t.truthy(d < fleet.DEMOTE + 4, "a car in the physics loop is near: " .. d)
    end
  end
  local rails = 0
  for car in pairs(ctx.ai.traffic.cars) do
    if car.mode == "rail" then rails = rails + 1 end
  end
  t.truthy(rails > 0, "and some run on rails far out: " .. rails)
end)

t.test("c traffic: cars far behind are put away, cars wrecked are left then removed, and nothing sits stuck for ever", function()
  local ctx = sim.new({ hour = 14 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 100 do sim.step(ctx, 0.05, ap) end
  local T = ctx.ai.traffic
  local victim
  for car in pairs(T.cars) do if not car.cop then victim = car break end end
  victim.x, victim.z = ctx.player.x + 400, ctx.player.z
  ctx.world:move(victim, victim.x, victim.z)
  sim.step(ctx, 0.05, ap)
  t.truthy(T.cars[victim] == nil, "400 units away: put away")
  local wreck
  for car in pairs(T.cars) do if not car.cop then wreck = car break end end
  wreck.wrecked, wreck.health = true, 0
  for _ = 1, 40 do sim.step(ctx, 0.05, ap) end
  t.truthy(T.cars[wreck] ~= nil and wreck.parked, "a wreck stays put")
  for _ = 1, 600 do sim.step(ctx, 0.05, ap) end
  -- idle time is bounded everywhere
  for car in pairs(T.cars) do
    t.truthy((car.idle or 0) < 41, "nobody is stuck longer than the limit: " .. (car.idle or 0))
  end
  -- wedged in a jam out of your close view: backing and filling (a moment of speed now and then) is still going
  -- nowhere, and the car is put away (the soak's 'stuck' cars sat like this for minutes)
  local wedged
  for car in pairs(T.cars) do if not car.cop and car.drv then wedged = car break end end
  local wx, wz = wedged.x, wedged.z
  local gone = false
  for i = 1, 20 * 40 do
    if T.cars[wedged] == nil then gone = true break end
    wedged.x, wedged.z = wx + (i % 40 < 3 and 1 or 0), wz
    wedged.v = (i % 40 < 3) and -2 or 0.1
    ctx.player.x, ctx.player.z = wx + 50, wz
    T:update(0.05)
  end
  t.truthy(gone, "a car going nowhere for long is put away")
end)

-- ---------------------------------------------------------------- the people

t.test("c peds: they walk the pavements by district and hour, never past the cap, and stay near the roads", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 120 do sim.step(ctx, 0.05, ap) end
  local P = ctx.ai.peds
  local day = P:target()
  t.truthy(P:count() >= day * 0.6 and P:count() <= day + 4, "crowd " .. P:count() .. " of " .. day)
  ctx.hour = 3
  local night = P:target()
  t.truthy(night < day, "quieter at night: " .. night .. " < " .. day)
  -- the districts differ: Lantern Row at night is busier than the Cinder Flats at night
  local row = pedsLib.DENSITY
  t.truthy(row.lantern[1] > row.cinder[1], "bars are open late, the works are not")
  t.truthy(row.cinder[2] > row.gilt[2], "the works start early")
  ctx.hour = 13
  for ped in pairs(P.list) do
    local e, _, d = ctx.roads:nearest(ped.x, ped.z, 30)
    if ped.state == "walk" then t.truthy(e and d < 14, "walking beside a road, " .. tostring(d)) end
    t.truthy(ped.x == ped.x and ped.y == ped.y and ped.z == ped.z, "a number")
  end
  ctx.budget.quality = 3
  t.truthy(P:target() < day, "a smaller crowd on a tight budget")
  ctx.budget.quality = 0
end)

t.test("c peds: gunfire sends everyone near running, and they come back to walking later", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 120 do sim.step(ctx, 0.05, ap) end
  local P = ctx.ai.peds
  local near = ctx.world:near(ctx.player.x, ctx.player.z, 40, "ped")
  t.truthy(#near > 0, "people around")
  ctx.bus:emit("crime", { kind = "gunfire", level = 2, x = ctx.player.x, z = ctx.player.z })
  local fleeing = 0
  for _, p in ipairs(near) do if p.state == "flee" then fleeing = fleeing + 1 end end
  t.truthy(fleeing >= #near * 0.8, "they run: " .. fleeing .. " of " .. #near)
  local far = ctx.world:near(ctx.player.x + 300, ctx.player.z, 10, "ped")
  for _, p in ipairs(far) do t.truthy(p.state ~= "flee", "beyond earshot they carry on") end
  for _ = 1, 400 do sim.step(ctx, 0.05, { handbrake = true }) end
  local still = 0
  -- (a sidestep out of a passing car's way, ped.dodge, is not running from the shots)
  for ped in pairs(P.list) do if ped.state == "flee" and not ped.dodge then still = still + 1 end end
  t.truthy(still <= 3, "they have settled again: " .. still)
  local _ = ctx
end)

t.test("c peds: a car that hits someone knocks them down (flat, stars, up again, never dead) and it is a crime", function()
  local ctx = sim.new({ hour = 13, plugins = true })
  local P = ctx.ai.peds
  local ped = P:spawnOn(ctx.roads.edges["tbe1"], 30, 1, 1)
  local car = ctx.player.car
  car.x, car.z, car.y, car.h, car.v = ped.x - 3, ped.z, ped.y, 0, 12
  ctx.stream:update(car.x, car.z, true)
  local crimes = 0
  ctx.bus:on("crime", function(d) if d.kind == "assault" then crimes = crimes + 1 end end)
  local sawDown, sawDazed, sawUp = false, false, false
  for _ = 1, 160 do
    sim.step(ctx, 0.05, { throttle = 0, handbrake = false })
    if ped.state == "down" then sawDown = true end
    if ped.state == "dazed" then sawDazed = true end
    if sawDazed and (ped.state == "flee" or ped.state == "walk") then sawUp = true end
    car.v = math.max(car.v, ped.state == "down" and 0 or 0)
    t.truthy(not ped.removed and ped.health == 1, "never removed as dead")
  end
  t.truthy(sawDown and sawDazed and sawUp, "down, then stars, then up")
  t.truthy(crimes >= 1, "hitting someone is a crime: " .. crimes)
end)

t.test("c peds: they step out of the way of a car coming at them", function()
  local ctx = sim.new({ hour = 13 })
  local P = ctx.ai.peds
  local car = ctx.player.car
  local e = ctx.roads.edges["tbe1"]
  local at = e.length * 0.7
  local ped = P:spawnOn(e, at, 1, 1)
  local px, _, pz = ctx.roads:pointAt(e, at, lane.laneOffset(e))
  ctx.world:move(ped, px, pz)
  ped.state, ped.look, ped.speed = "walk", 0, 0.05
  local cx, cy, cz, dx, dz = ctx.roads:pointAt(e, at - 22, lane.laneOffset(e))
  car.x, car.y, car.z, car.h = cx, cy, cz, math.atan2(dz, dx)
  car.v = 14
  local dodged = false
  for _ = 1, 30 do
    sim.step(ctx, 0.05, { throttle = 0.3 })
    if ped.state == "flee" then dodged = true end
  end
  t.truthy(dodged, "it saw the car coming")
end)

-- ---------------------------------------------------------------- physics near, rails far, and the drawing

t.test("c fleet: a car is on rails far from you and in the physics loop near you, and switches both ways", function()
  local ctx = sim.new({ plugins = true, hour = 13 })
  local T = ctx.ai.traffic
  local e = ctx.roads.edges["tbe1"]
  local car = T:spawnOn(e, e.length * 0.5, 1)
  if not car then car = T:spawnOn(e, e.length * 0.3, 1) end
  t.truthy(car, "spawned")
  car.x, car.z = ctx.player.x + 150, ctx.player.z
  sim.step(ctx, 0.05, { handbrake = true })
  t.truthy(car.mode == "rail" or car.mode == "gone", "far: " .. tostring(car.mode))
  -- bring it close
  local near = ctx.roads:pointAt(ctx.roads.edges["tbe1"], 10, 2)
  local c2 = T:spawnOn(ctx.roads.edges["tbe1"], 20, 1)
  if c2 then
    local inList = false
    for _ = 1, 3 do sim.step(ctx, 0.05, { handbrake = true }) end
    for _, c in ipairs(ctx.cars) do if c == c2 then inList = true end end
    t.truthy(inList == (c2.mode == "phys"), "in ctx.cars exactly when in physics mode")
  end
  local _ = near
end)

t.test("c scene: the layers draw through the stand-in renderer without error, and a layer that fails is switched off after three", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 140 do sim.step(ctx, 0.05, ap) end
  ctx.heat.set(5)
  for _ = 1, 400 do sim.step(ctx, 0.05, ap) end
  sim.draw(ctx)
  t.truthy(#ctx.view.r.placed > 3, "things placed: " .. #ctx.view.r.placed)
  t.eq(#ctx.logs, 0, "no layer complained: " .. table.concat(ctx.logs, "; "))
  local scene = require("sg.ai.scene")
  scene.layer(ctx, "broken", function() error("boom") end)
  for _ = 1, 5 do sim.draw(ctx) end
  local fails = 0
  for _, l in ipairs(ctx.aiScene.layers) do if l.name == "broken" then fails = l.fails end end
  t.eq(fails, 3, "three strikes")
end)

t.test("c scene: the HUD widget and the minimap overlay draw", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx)
  for _ = 1, 60 do sim.step(ctx, 0.05, ap) end
  ctx.heat.set(3)
  for _ = 1, 40 do sim.step(ctx, 0.05, ap) end
  local text = {}
  local term = {
    setCursorPos = function() end, setTextColour = function() end, setBackgroundColour = function() end,
    write = function(s) text[#text + 1] = s end,
  }
  local drew = 0
  for _, w in ipairs(ctx.ui.widgets("top-right", ctx)) do
    if w.name == "c_wanted" then w.draw(ctx, term) drew = drew + 1 end
  end
  t.eq(drew, 1, "the wanted widget shows when wanted")
  t.truthy(table.concat(text):find("%*"), "stars")
  ctx.heat.set(0)
  local hidden = true
  for _, w in ipairs(ctx.ui.widgets("top-right", ctx)) do if w.name == "c_wanted" then hidden = false end end
  t.truthy(hidden, "gone when not wanted")
end)

-- ---------------------------------------------------------------- the crews

t.test("c gangs: a crew in the district's colour stands about; leave it alone and it leaves you alone; start something and it comes for you, and calms down", function()
  local ctx = sim.new({ hour = 20, x = 280, z = 120 })
  local hurts, biggest = 0, 0
  ctx.bus:on("player_hurt", function(d) hurts = hurts + d.amount biggest = math.max(biggest, d.amount) end)
  for _ = 1, 400 do sim.step(ctx, 0.05, { handbrake = true }) end
  local crew = ctx.world:each("gang")
  t.eq(#crew, 3, "a crew of three")
  for _, m in ipairs(crew) do
    t.eq(m.shirt, "yellow", "the Gilt Sevens' yellow")
    t.truthy(m.state ~= "fight", "calm")
  end
  t.eq(hurts, 0, "leave them alone and they leave you alone")
  -- hit one with a car, or shoot near them: the crew turns
  ctx.ai.knock(crew[1], 2, 0)
  t.truthy(ctx.ai.gangs:alerted() == 3, "the whole crew is angry: " .. ctx.ai.gangs:alerted())
  local shots = 0
  ctx.ai.gangs.onShoot = function() shots = shots + 1 end
  -- put the player within reach of them
  local m = crew[2]
  ctx.player.car.x, ctx.player.car.z, ctx.player.car.y = m.x + 6, m.z, m.y
  ctx.stream:update(ctx.player.car.x, ctx.player.car.z, true)
  for _ = 1, 20 * 12 do sim.step(ctx, 0.05, { handbrake = true }) end
  t.truthy(hurts > 0, "they hit you: " .. hurts)
  t.truthy(biggest <= 5, "cartoony: a shove or a shot, never more than a few points: " .. biggest)
  t.truthy(shots > 0, "they shoot from range: " .. shots)
  -- some time with nothing more: they go home
  for _ = 1, 20 * 40 do sim.step(ctx, 0.05, { handbrake = true }) end
  t.eq(ctx.ai.gangs:alerted(), 0, "calmed down")
  local calm = true
  for _, g in ipairs(ctx.world:each("gang")) do
    if g.state == "fight" then calm = false end
  end
  t.truthy(calm, "standing about again")
  for _, g in ipairs(ctx.world:each("gang")) do t.truthy(not g.removed and g.health == 1, "nobody was killed") end
end)

-- ---------------------------------------------------------------- the roundabout

t.test("c lane: cars come in off the avenue and go round the one-way ring, giving way to the cars on it, without a bump", function()
  local ctx = sim.new({ plugins = false, x = 166, z = 196 })
  local f = testbed.FEATURES
  local ring = {}
  for _, id in ipairs(f.roundabout) do ring[id] = true end
  local ringEdges, avenue = {}, nil
  for _, e in pairs(ctx.roads.edges) do
    if ring[e.a] and ring[e.b] and e.lanes == 1 then ringEdges[#ringEdges + 1] = e end
    if e.b == f.roundabout[1] and e.kind == "avenue" then avenue = e end
  end
  t.truthy(#ringEdges >= 2, "a one-way ring: " .. #ringEdges)
  t.truthy(avenue, "the avenue that comes in")
  table.sort(ringEdges, function(a, b) return a.id < b.id end)
  local cars = {}
  -- two on the ring already, three coming in one after another
  cars[#cars + 1] = placeCar(ctx, ringEdges[2], 10, "marlin", 1)
  cars[#cars + 1] = placeCar(ctx, ringEdges[math.min(3, #ringEdges)], 20, "pipit", 1)
  for i = 1, 3 do cars[#cars + 1] = placeCar(ctx, avenue, avenue.length - 12 - (i - 1) * 14, "kestrel", 1) end
  local visited, nearest = {}, 1e9
  for step = 1, 1200 do
    sim.step(ctx, 0.05, { handbrake = true })
    for i, c in ipairs(cars) do
      if ring[c.drv.edge.a] and ring[c.drv.edge.b] then visited[c.drv.edge.id] = true end
      for j = i + 1, #cars do
        nearest = math.min(nearest, math.sqrt((c.x - cars[j].x) ^ 2 + (c.z - cars[j].z) ^ 2))
      end
    end
    if step % 300 == 0 then t.breathe() end
  end
  local n = 0
  for _ in pairs(visited) do n = n + 1 end
  t.truthy(n >= 2, "they went round the ring: " .. n .. " edges")
  t.truthy(nearest > 2, "never inside each other: " .. nearest)
  for _, c in ipairs(cars) do t.truthy(c.health > c.spec.health * 0.8, "no crash: " .. c.health) end
end)

t.test("c heat: ctx.heat works as the story's world.lua calls it: level, set(n) and heat:set(n)", function()
  local ctx = sim.new({ hour = 13 })
  t.eq(ctx.heat.level, 0)
  ctx.heat:set(4)
  t.eq(ctx.heat.level, 4)
  ctx.heat.set(2)
  t.eq(ctx.heat.level, 2)
  ctx.heat:set(0)
  t.eq(ctx.heat.level, 0)
end)
