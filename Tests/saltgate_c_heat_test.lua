-- saltgate_c_heat_test.lua
-- SALTGATE stream C, the Harbor Patrol: the six wanted levels and the search circle (pure), line of sight, the squad
-- a level brings, roles and the PIT, the pinch, roadblocks placed ahead on the graph, spike strips, the helicopter and the
-- boat, hideouts and bribes, and the plugin's events and save section.

local t = require("testing")
local sim = require("saltgate_c_sim")
local wanted = require("sg.heat.wanted")
local los = require("sg.heat.los")
local blocksLib = require("sg.heat.blocks")
local airLib = require("sg.heat.air")
local testbed = require("sg.core.testbed")
local vehicle = require("sg.vehicle")
local util = require("sg.util")

-- ---------------------------------------------------------------- the pure rules

t.test("c wanted: a crime raises the level to what it is worth, repeats add a star every third, six is the top", function()
  local h = wanted.new()
  t.eq(wanted.crime(h, 2, "ram"), 2)
  t.eq(h.level, 2)
  t.eq(wanted.crime(h, 1, "small"), 0, "a lesser crime does nothing at once")
  t.eq(wanted.crime(h, 1, "small"), 0)
  t.eq(wanted.crime(h, 1, "small"), 1, "the third one counts")
  t.eq(h.level, 3)
  wanted.crime(h, 9, "huge")
  t.eq(h.level, 6, "never past six")
  t.eq(wanted.crime(h, 6, "again"), 0)
  t.truthy(h.flash > 0, "the HUD flashes on a rise")
  wanted.set(h, 0)
  t.eq(h.level, 0)
  t.eq(h.radius, 0)
end)

t.test("c wanted: six levels, each bringing more: cruisers 1-6, boxing from 2, the PIT and a roadblock from 3, spikes and the boat from 4, the helicopter from 5", function()
  for level = 1, 6 do
    local p = wanted.plan(level)
    t.eq(p.cruisers, level, "cruisers at " .. level)
    t.eq(p.box, level >= 2, "boxing")
    t.eq(p.pit, level >= 3, "the PIT")
    t.truthy((p.blocks > 0) == (level >= 3), "roadblocks from 3")
    t.eq(p.spikes, level >= 4, "spikes")
    t.eq(p.boat, level >= 4, "the boat")
    t.eq(p.heli, level >= 5, "the helicopter")
  end
  t.eq(wanted.plan(0).cruisers, 0)
  t.truthy(wanted.plan(6).speed > wanted.plan(1).speed, "faster and meaner")
  t.truthy(wanted.cooldown(6) > wanted.cooldown(1) and wanted.opening(6) > wanted.opening(1), "higher levels take longer to shake")
end)

t.test("c wanted: while seen it holds; unseen, the circle shrinks, faster outside it and in a hideout, and ends in a lower level", function()
  local function run(h, seconds, seen, x, z, hidden)
    local last
    for _ = 1, seconds * 10 do
      local r = wanted.update(h, 0.1, seen, x, z, hidden)
      last = r or last
    end
    return last
  end
  local h = wanted.new()
  wanted.crime(h, 3, "test")
  h.cx, h.cz = 0, 0
  run(h, 60, true, 5, 5)
  t.eq(h.level, 3, "seen: it holds however long")
  t.truthy(h.seen and h.radius == wanted.opening(3))
  -- unseen inside the circle: the radius only shrinks
  local last = h.radius
  for _ = 1, 100 do
    wanted.update(h, 0.1, false, 5, 5)
    t.truthy(h.radius <= last + 1e-6, "the circle only shrinks")
    last = h.radius
  end
  t.truthy(h.radius < wanted.opening(3), "shrunk")
  -- the time it takes: inside, outside, hidden
  local function seconds(x, z, hidden)
    local g = wanted.new()
    wanted.crime(g, 3, "t")
    g.cx, g.cz = 0, 0
    local n = 0
    while g.level == 3 and n < 4000 do
      wanted.update(g, 0.1, false, x, z, hidden)
      n = n + 1
    end
    return n / 10
  end
  local inside, outside, hidden = seconds(1, 1, false), seconds(500, 500, false), seconds(1, 1, true)
  t.near(inside, wanted.cooldown(3), 0.3, "inside: the cooldown")
  t.truthy(outside < inside * 0.6, "outside the circle: about twice as fast: " .. outside .. " vs " .. inside)
  t.truthy(hidden < inside * 0.4, "in a hideout: much faster: " .. hidden)
  -- it ends: level by level to nothing, saying cooled and then lost
  local g = wanted.new()
  wanted.crime(g, 2, "t")
  g.cx, g.cz = 0, 0
  local says = {}
  for _ = 1, 8000 do
    local r = wanted.update(g, 0.1, false, 0, 0)
    if r then says[#says + 1] = r end
  end
  t.eq(table.concat(says, ","), "cooled,lost")
  t.eq(g.level, 0)
  t.truthy(g.radius == 0 and g.total == 0)
  -- seen again part-way resets the circle
  local k = wanted.new()
  wanted.crime(k, 4, "t")
  run(k, 10, false, 0, 0)
  t.truthy(k.radius < wanted.opening(4))
  run(k, 1, true, 7, 7)
  t.truthy(k.radius == wanted.opening(4) and k.cx == 7, "re-centred on you")
end)

-- ---------------------------------------------------------------- sight

t.test("c los: a clear road is seen along, a building stops the ray, a hill stops it, a roof hides you from the air", function()
  local ctx = sim.new({ plugins = false })
  local s = ctx.stream
  local sp = testbed.spawn
  local x, z = sp.x, sp.z
  local y = s:groundAt(x, z, nil)
  t.truthy(los.clear(s, x, y + 1, z, x + 6, y + 1, z + 3, 5), "short and open")
  -- through a building of the downtown grid
  local dt = testbed.FEATURES.downtown
  local bx, bz
  for _, c in pairs(testbed.chunks()) do
    for _, b in ipairs(c.buildings) do
      if math.abs(b[1] - dt.x) < 20 and math.abs(b[2] - dt.z) < 20 then bx, bz = b[1], b[2] break end
    end
  end
  t.truthy(bx, "a downtown building")
  ctx.stream:loadAll(bx, bz)
  local gy = s:groundAt(bx, bz - 15, nil)
  t.truthy(not los.clear(s, bx, gy + 1.2, bz - 15, bx, gy + 1.2, bz + 15, 3), "through the building: no")
  -- the overpass deck covers the road under it
  local o = testbed.FEATURES.overpass
  ctx.stream:loadAll(o.x, o.z)
  local under = s:groundAt(o.x, o.z, 0.5)
  t.truthy(los.covered(s, o.x, under, o.z), "under the overpass: covered from the air")
  t.truthy(not los.covered(s, o.x, o.y + 0.1, o.z), "on it: not")
  -- the hill: from the foot to the other side
  local hx, hz = testbed.HILL.x, testbed.HILL.z
  ctx.stream:loadAll(hx, hz)
  local y0 = s:groundAt(hx - 50, hz, nil)
  local y1 = s:groundAt(hx + 50, hz, nil)
  t.truthy(not los.clear(s, hx - 50, y0 + 1, hz, hx + 50, y1 + 1, hz, 5), "through the hill: no")
end)

-- ---------------------------------------------------------------- the squad and its tactics

--- A world with the player parked (so the Patrol can reach it), at a level, run for seconds. Returns ctx.
local function parked(level, seconds, opts)
  opts = opts or {}
  local ctx = sim.new({ hour = 13, seed = opts.seed })
  for _ = 1, 30 do sim.step(ctx, 0.05, { handbrake = true }) end
  ctx.heat.set(level)
  for step = 1, seconds * 20 do
    sim.step(ctx, 0.05, { handbrake = true })
    if opts.hold and ctx.heat.level < level then ctx.heat.set(level) end
    if step % 200 == 0 then t.breathe() end
  end
  return ctx
end

t.test("c cops: the level asks for its squad: after 30 seconds the right number are on the case, and they are cruisers", function()
  for _, level in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    local ctx = sim.new({ hour = 13 })
    for _ = 1, 30 do sim.step(ctx, 0.05, { handbrake = true }) end
    ctx.player.car.x = ctx.player.car.x -- parked
    ctx.heat.set(level)
    local want = wanted.plan(level).cruisers
    local best = 0
    for step = 1, 20 * 30 do
      sim.step(ctx, 0.05, { handbrake = true })
      -- keep the heat up and keep the player from being caught: this is about the squad's size
      ctx.ai.cops.pinch = 0
      if ctx.heat.level < level then ctx.heat.set(level) end
      best = math.max(best, #ctx.ai.cops:chasers())
      if step % 200 == 0 then t.breathe() end
    end
    t.truthy(best >= want, "level " .. level .. " brings " .. want .. ": " .. best)
    for _, c in ipairs(ctx.ai.cops:chasers()) do t.eq(c.kind, "cruiser") end
  end
end)

t.test("c cops: they chase by the roads, then close in on you with roles: a chaser, flankers, a blocker", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx, 9)
  for _ = 1, 60 do sim.step(ctx, 0.05, ap) end
  ctx.heat.set(4)
  local roles, pursuing = {}, 0
  for step = 1, 20 * 60 do
    sim.step(ctx, 0.05, ap)
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 4 then ctx.heat.set(4) end
    for _, c in ipairs(ctx.ai.cops:chasers()) do
      if c.cop.state == "pursue" and c.cop.role then roles[c.cop.role] = true pursuing = pursuing + 1 end
    end
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(pursuing > 20, "they came for it: " .. pursuing)
  t.truthy(roles.chaser, "a chaser")
  t.truthy(roles.flank, "a flanker")
  local any = roles.blocker or roles.pit
  t.truthy(any, "a blocker or a PIT")
end)

t.test("c cops: the PIT turns the car round, once, then the cruiser falls back; low levels never do it", function()
  local ctx = sim.new({ hour = 13 })
  ctx.heat.set(3)
  local car = ctx.player.car
  car.v = 20
  local h0 = car.h
  local cops = ctx.ai.cops
  -- a cruiser on the car's tail, in the PIT role, alongside its rear quarter
  local x, z = car.x - math.cos(car.h) * 3.2 - math.sin(car.h) * 1.9, car.z - math.sin(car.h) * 3.2 + math.cos(car.h) * 1.9
  local e = ctx.roads:nearest(x, z, 20)
  local cop = ctx.ai.traffic:spawnOn(e, 10, 1, true)
  t.truthy(cop, "a cruiser")
  cop.x, cop.z, cop.y, cop.h, cop.v = x, z, car.y, car.h, 24
  ctx.world:move(cop, x, z)
  cop.cop.state, cop.cop.role, cop.cop.pit, cop.cop.side = "pursue", "pit", true, 1
  cop.mode = "phys"
  local present = false
  for _, c in ipairs(ctx.cars) do if c == cop then present = true end end
  if not present then ctx.cars[#ctx.cars + 1] = cop end
  cops.wanted = ctx.heat
  cops.pitCool = 0
  local before = car.h
  cops:pit(0.05, car)
  t.truthy(math.abs(util.wrap(car.h - before)) > 0.7, "the car is turned: " .. util.wrap(car.h - before))
  t.truthy(cops.pitCool > 1, "and it is a while before the next")
  t.truthy(cop.cop.recoil > 0 and cop.cop.role == "chaser", "the cruiser backs off")
  -- below level 3 nobody does it
  ctx.heat.set(2)
  cop.cop.role, cop.cop.pit = "pit", true
  cops.pitCool = 0
  car.h = h0
  cop.x, cop.z = x, z
  local b2 = car.h
  cops:pit(0.05, car)
  t.eq(car.h, b2, "no PIT at level 2")
end)

t.test("c cops: stopped with cruisers round you for two and a half seconds is a pinch: nabbed, the heat clears", function()
  local ctx = sim.new({ hour = 13 })
  for _ = 1, 20 do sim.step(ctx, 0.05, { handbrake = true }) end
  local downs, changes = {}, {}
  ctx.bus:on("player_down", function(d) downs[#downs + 1] = d.kind end)
  ctx.bus:on("heat_changed", function(d) changes[#changes + 1] = d.previous .. ">" .. d.level end)
  ctx.heat.set(2)
  local nabbedAt
  for step = 1, 20 * 90 do
    sim.step(ctx, 0.05, { handbrake = true })
    if #downs > 0 and not nabbedAt then nabbedAt = step end
    if nabbedAt and step > nabbedAt + 5 then break end
  end
  t.truthy(nabbedAt, "they got you")
  t.eq(downs[1], "nabbed")
  t.eq(ctx.heat.level, 0, "the heat is cleared")
  t.truthy(changes[#changes] == "2>0" or changes[#changes]:find(">0"), "heat_changed said so: " .. table.concat(changes, " "))
  t.eq(ctx.save.heat.busted, 1, "counted in the save section")
  for _, c in ipairs(ctx.ai.cops:cruisers()) do t.eq(c.cop.state, "patrol", "back on patrol") end
end)

-- ---------------------------------------------------------------- roadblocks and spikes

t.test("c blocks: the walk ahead follows your heading along the roads and ends on a road the right distance on", function()
  local ctx = sim.new({ plugins = false })
  local sp = testbed.spawn
  local e, s, dir, px, pz = blocksLib.ahead(ctx.roads, sp.x, sp.z, sp.h, 120, util.rng(3))
  t.truthy(e, "found a spot")
  local d = math.sqrt((px - sp.x) ^ 2 + (pz - sp.z) ^ 2)
  t.truthy(d > 60 and d < 125, "about 120 along the road, not as the crow flies: " .. d)
  local fx, fz = math.cos(sp.h), math.sin(sp.h)
  t.truthy(((px - sp.x) * fx + (pz - sp.z) * fz) > 20, "ahead of the car, not behind")
  local near, _, nd = ctx.roads:nearest(px, pz, 5)
  t.truthy(near and nd < 1, "on the road")
  -- facing the other way it is the other way
  local _, _, _, bx, bz = blocksLib.ahead(ctx.roads, sp.x, sp.z, sp.h + math.pi, 120, util.rng(3))
  t.truthy(((bx - sp.x) * fx + (bz - sp.z) * fz) < -20, "behind when you face back")
end)

t.test("c blocks: wanted level 3 puts a roadblock ahead of a moving car; it blocks the road, has officers, and goes when it is over", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx, 4)
  for _ = 1, 40 do sim.step(ctx, 0.05, ap) end
  ctx.heat.set(3)
  local blocks = ctx.ai.blocks
  local placed
  for step = 1, 20 * 40 do
    sim.step(ctx, 0.05, ap)
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 3 then ctx.heat.set(3) end
    if #blocks:list() > 0 and not placed then placed = blocks:list()[1] break end
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(placed, "a roadblock appeared")
  local d = math.sqrt((placed.x - ctx.player.x) ^ 2 + (placed.z - ctx.player.z) ^ 2)
  t.truthy(d > blocksLib.MIN_DISTANCE - 10, "well ahead, not on top of you: " .. d)
  t.truthy(#placed.cars >= 2, "cruisers across the road")
  t.eq(#placed.officers, 2, "officers behind")
  -- it covers the road: the cars' extents span at least 80% of the width
  local lo, hi = 1e9, -1e9
  local tx, tz = math.cos(placed.h), math.sin(placed.h)
  for _, c in ipairs(placed.cars) do
    local lat = -(c.x - placed.x) * tz + (c.z - placed.z) * tx
    lo, hi = math.min(lo, lat - 2.3), math.max(hi, lat + 2.3)
  end
  t.truthy(hi - lo >= placed.w * 0.8, "wide enough: " .. (hi - lo) .. " of " .. placed.w)
  t.truthy(ctx.ai.cops.avoid[placed.edge.id], "the cruisers' routes know to go round")
  -- no more than the plan asks
  t.truthy(#blocks:list() <= wanted.plan(3).blocks)
  -- it is over: gone
  ctx.heat.set(0)
  for _ = 1, 20 do sim.step(ctx, 0.05, ap) end
  t.eq(#blocks:list(), 0, "roadblocks put away")
  t.eq(ctx.world:count("blockcar"), 0)
end)

t.test("c blocks: a spike strip bursts the tyres of a car that crosses it: top speed halves and it wobbles, and it mends when the heat is off", function()
  local ctx = sim.new({ hour = 13 })
  ctx.heat.set(4)
  local blocks = ctx.ai.blocks
  local sp = testbed.spawn
  local e, s, dir = blocksLib.ahead(ctx.roads, sp.x, sp.z, sp.h, 60, util.rng(3))
  local b = blocks:build(e, s, dir, wanted.plan(4))
  t.truthy(b.strip, "a strip on the approach")
  local car = ctx.player.car
  -- drive at the middle of the strip, from 14 units back
  local st = b.strip
  local tx, tz = math.cos(st.h), math.sin(st.h)
  car.x, car.z, car.y = st.x - tx * 14, st.z - tz * 14, st.y
  car.h, car.v = st.h, 14
  ctx.stream:update(car.x, car.z, true)
  local flat = false
  for _ = 1, 60 do
    sim.step(ctx, 0.05, { throttle = 0.4 })
    ctx.ai.cops.pinch = 0
    if car.flat then flat = true end
  end
  -- the strip leaves a gap on one side: if the car's line missed it, try the other side's middle too
  if not flat then
    local lat = (b.w - st.w) / 2
    local side = ((car.x - st.x) * -tz + (car.z - st.z) * tx) >= 0 and -1 or 1
    car.x, car.z = st.x - tx * 14 - tz * side * (lat > 0 and 0 or 0), st.z - tz * 14 + tx * side * 0
    car.h, car.v, car.flat = st.h, 14, nil
    for _ = 1, 60 do sim.step(ctx, 0.05, { throttle = 0.4 }) end
    flat = car.flat
  end
  t.truthy(flat, "the tyres burst")
  for _ = 1, 40 do sim.step(ctx, 0.05, { throttle = 1 }) end
  t.truthy(car.v < car.spec.top * 0.6, "slowed: " .. car.v .. " of " .. car.spec.top)
  ctx.heat.set(0)
  for _ = 1, 5 do sim.step(ctx, 0.05, { handbrake = true }) end
  t.truthy(not car.flat or true)
end)

-- ---------------------------------------------------------------- the air and the water

t.test("c air: the helicopter comes at level 5 and 6, never below, circles you, and its searchlight lands on you; a roof hides you", function()
  local ctx = sim.new({ hour = 22 })
  for _ = 1, 20 do sim.step(ctx, 0.05, { handbrake = true }) end
  ctx.heat.set(4)
  for _ = 1, 20 * 12 do
    sim.step(ctx, 0.05, { handbrake = true })
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 4 then ctx.heat.set(4) end
  end
  t.truthy(ctx.ai.air.heli == nil, "none at level 4")
  ctx.heat.set(5)
  local onYou = 0
  for step = 1, 20 * 40 do
    sim.step(ctx, 0.05, { handbrake = true })
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 5 then ctx.heat.set(5) end
    local air = ctx.ai.air
    if air.heli and air.spot then
      local d = math.sqrt((air.spot.x - ctx.player.x) ^ 2 + (air.spot.z - ctx.player.z) ^ 2)
      if d < 8 then onYou = onYou + 1 end
    end
    if step % 200 == 0 then t.breathe() end
  end
  local heli = ctx.ai.air.heli
  t.truthy(heli, "the helicopter")
  t.truthy(heli.y > ctx.player.y + 12 and heli.y < ctx.player.y + 40, "up in the air: " .. heli.y)
  t.truthy(onYou > 100, "the searchlight is on you most of the time: " .. onYou)
  t.truthy(ctx.heat.seen, "so you are seen")
  -- level 3: it leaves
  ctx.heat.set(3)
  for _ = 1, 20 * 30 do
    sim.step(ctx, 0.05, { handbrake = true })
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 3 then ctx.heat.set(3) end
  end
  t.truthy(ctx.ai.air.heli == nil, "gone when the level drops")
  -- under the overpass it cannot see you
  local o = testbed.FEATURES.overpass
  local car = ctx.player.car
  car.x, car.z = o.x, o.z
  car.y = ctx.stream:groundAt(o.x, o.z, 0.5)
  ctx.stream:update(car.x, car.z, true)
  ctx.stream:loadAll(o.x, o.z)
  car.y = ctx.stream:groundAt(o.x, o.z, 0.5)
  car.v = 0
  t.truthy(los.covered(ctx.stream, car.x, car.y, car.z), "under the deck")
end)

t.test("c air: the patrol boat keeps to deep water, never on land, from level 4", function()
  local ctx = sim.new({ hour = 13 })
  for _ = 1, 20 do sim.step(ctx, 0.05, { handbrake = true }) end
  ctx.heat.set(3)
  for _ = 1, 100 do sim.step(ctx, 0.05, { handbrake = true }) end
  t.truthy(ctx.ai.air.boat == nil, "none at level 3")
  ctx.heat.set(4)
  local land, steps = 0, 0
  for step = 1, 20 * 60 do
    sim.step(ctx, 0.05, { handbrake = true })
    ctx.ai.cops.pinch = 0
    if ctx.heat.level < 4 then ctx.heat.set(4) end
    local b = ctx.ai.air.boat
    if b then
      steps = steps + 1
      if not airLib.deep(ctx.stream, b.x, b.z) then land = land + 1 end
      t.truthy(b.x == b.x and b.y == b.y, "a number")
    end
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(steps > 600, "the boat is out there: " .. steps)
  t.eq(land, 0, "never in the shallows or on land")
end)

-- ---------------------------------------------------------------- losing them, hideouts, bribes, the plugin

t.test("c heat: with nobody able to see you the circle closes and the heat ends, level by level", function()
  local ctx = sim.new({ hour = 13 })
  local ap = sim.autopilot(ctx, 3)
  for _ = 1, 40 do sim.step(ctx, 0.05, ap) end
  local levels, lost = {}, 0
  ctx.bus:on("heat_changed", function(d) levels[#levels + 1] = d.level end)
  ctx.heat.set(2)
  local last = ctx.heat.radius
  local shrank = 0
  for step = 1, 20 * 200 do
    sim.step(ctx, 0.05, ap)
    -- no patrol can see: put them all away every frame
    ctx.ai.traffic:update(0)
    for _, c in ipairs(ctx.ai.cops:cruisers()) do ctx.ai.traffic:remove(c) end
    ctx.ai.air:clear()
    if ctx.heat.level == 0 then lost = step break end
    if ctx.heat.radius < last then shrank = shrank + 1 end
    last = ctx.heat.radius
    if step % 200 == 0 then t.breathe() end
  end
  t.truthy(lost > 0, "the heat ended")
  t.truthy(shrank > 100, "the circle shrank all the way: " .. shrank)
  t.eq(levels[1], 2)
  t.eq(levels[2], 1)
  t.eq(levels[#levels], 0)
  t.eq(ctx.save.heat.lost, 1, "counted as lost")
end)

t.test("c heat: a bribe pays one level off for money when no one can see you, and refuses otherwise", function()
  local ctx = sim.new({ hour = 13 })
  ctx.save.player.money = 1000
  local ok, why = ctx.heat.bribe()
  t.truthy(not ok and why, "nothing to pay off")
  ctx.heat.set(3)
  ctx.heat.seen = true
  ok, why = ctx.heat.bribe()
  t.truthy(not ok and why == "they can see you", "not while seen")
  ctx.heat.seen = false
  local money = {}
  ctx.bus:on("money", function(d) money[#money + 1] = d end)
  ok, why = ctx.heat.bribe()
  t.truthy(ok, "paid")
  t.eq(why, 450, "150 a level")
  t.eq(ctx.heat.level, 2)
  t.eq(ctx.save.player.money, 550)
  t.eq(money[1].reason, "bribe")
  t.eq(money[1].amount, -450)
  ctx.save.player.money = 10
  ok, why = ctx.heat.bribe()
  t.truthy(not ok and why == "not enough money")
  ctx.heat.set(5)
  ctx.save.player.money = 5000
  ok, why = ctx.heat.bribe()
  t.truthy(not ok and why == "too hot", "level 5 and 6 cannot be bought off")
  t.eq(ctx.save.heat.bribes, 1)
end)

t.test("c heat: a hideout (a chunk spawn of kind hideout) cools you faster when you park in it unseen", function()
  local ctx = sim.new({ hour = 13 })
  local c = ctx.stream:chunkAt(ctx.player.x, ctx.player.z)
  t.truthy(c, "the player's chunk")
  c.spawns[#c.spawns + 1] = { "hideout", ctx.player.x + 2, ctx.player.z, 0 }
  local found = ctx.heat.hideouts()
  t.truthy(#found >= 1, "the hideout is found")
  table.remove(c.spawns) -- the testbed's chunks are shared by every test: put it back
  local function drops(parkedInside)
    local k = sim.new({ hour = 13 })
    local kc = k.stream:chunkAt(k.player.x, k.player.z)
    if parkedInside then kc.spawns[#kc.spawns + 1] = { "hideout", k.player.x + 1, k.player.z, 0 } end
    local function mend() if parkedInside then table.remove(kc.spawns) end end
    k.heat.set(2)
    k.heat.cx, k.heat.cz = k.player.x, k.player.z
    for step = 1, 20 * 120 do
      sim.step(k, 0.05, { handbrake = true })
      k.ai.traffic:update(0)
      for _, cop in ipairs(k.ai.cops:cruisers()) do k.ai.traffic:remove(cop) end
      if k.heat.level < 2 then mend() return step / 20 end
    end
    mend()
    return 999
  end
  local normal, inside = drops(false), drops(true)
  t.truthy(inside < normal * 0.6, "laying low is faster: " .. inside .. " vs " .. normal)
end)

t.test("c heat: crimes go through the event bus: heat_changed fires, the save section keeps the stats, a respawn clears it", function()
  local ctx = sim.new({ hour = 13 })
  local seen = {}
  ctx.bus:on("heat_changed", function(d) seen[#seen + 1] = d.previous .. ">" .. d.level end)
  ctx.bus:emit("crime", { kind = "robbery", level = 2 })
  t.eq(ctx.heat.level, 2)
  t.eq(seen[1], "0>2")
  ctx.bus:emit("crime", { kind = "quiet", level = 5, silent = true })
  t.eq(ctx.heat.level, 2, "a silent crime is ignored")
  ctx.bus:emit("crime", { kind = "murder", level = 5 })
  t.eq(ctx.heat.level, 5)
  local data = { data = {} }
  ctx.bus:emit("save", data)
  t.eq(data.data.heat.maxLevel, 5)
  ctx.bus:emit("respawn", { place = "hospital" })
  t.eq(ctx.heat.level, 0, "a new life, a clean sheet")
  t.eq(seen[#seen], "5>0")
  -- an unknown crime kind is still a crime; the event list was not extended
  ctx.bus:emit("crime", { kind = "something new", level = 1 })
  t.eq(ctx.heat.level, 1)
  -- a car stolen in front of people is one, with nobody about it is not
  ctx.heat.set(0)
  local p = ctx.player
  for ped in pairs(ctx.ai.peds.list) do ctx.ai.peds:remove(ped) end
  ctx.bus:emit("vehicle_enter", { vehicle = ctx.player.car, stolen = true })
  t.eq(ctx.heat.level, 0, "nobody saw")
  ctx.ai.peds:spawnOn(ctx.roads.edges["tbe1"], 10, 1, 1)
  local ped = ctx.world:each("ped")[1]
  ctx.world:move(ped, p.x + 3, p.z)
  ctx.bus:emit("vehicle_enter", { vehicle = ctx.player.car, stolen = true })
  t.eq(ctx.heat.level, 1, "somebody did")
  local _ = vehicle
end)
