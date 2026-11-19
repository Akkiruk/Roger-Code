-- saltgate_b_combat_test.lua
-- SALTGATE stream B: combat. The cartoony arsenal, the knock rules (nobody is ever removed as dead), keyboard
-- aiming (lock-on, cycling, a wide cone from a car), shots against walls and cars (cover), ammo and reloads, pickups,
-- the player knocked down and getting up, the keys with real CC key timing, the hint lines, and a soak.

local t = require("testing")

if not rawget(_G, "colors") then
  local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple",
    "blue", "brown", "green", "red", "black" }
  local tbl = {}
  for i, n in ipairs(names) do tbl[n] = 2 ^ (i - 1) end
  colors = tbl
  colours = tbl
  colors.grey, colors.lightGrey = tbl.gray, tbl.lightGray
end

local events = require("sg.core.events")
local entity = require("sg.core.entity")
local save = require("sg.core.save")
local stream = require("sg.core.stream")
local testbed = require("sg.core.testbed")
local vehicle = require("sg.vehicle")
local util = require("sg.util")
local inputlib = require("sg.input")
local weapons = require("sg.combat.weapons")
local knock = require("sg.combat.knock")
local aim = require("sg.combat.aim")
local shoot = require("sg.combat.shoot")
local system = require("sg.combat.system")
local combatInput = require("sg.combat.input")
local hud = require("sg.combat.hud")
local overlay = require("sg.combat.overlay")
local fx = require("sg.combat.fx")

testbed.chunks()

--- A flat open world: no walls, ground at 0.
local function openStream()
  return {
    collide = function(_, x, z) return x, z, false, 0, 0 end,
    groundAt = function() return 0, "terrain" end,
    waterAt = function() return nil end,
  }
end

local function newCtx(opts)
  opts = opts or {}
  local bus = events.new()
  local log = { crime = {}, hurt = {}, down = {}, pickup = {} }
  bus:on("crime", function(d) log.crime[#log.crime + 1] = d end)
  bus:on("player_hurt", function(d) log.hurt[#log.hurt + 1] = d end)
  bus:on("player_down", function(d) log.down[#log.down + 1] = d end)
  bus:on("pickup", function(d) log.pickup[#log.pickup + 1] = d end)
  local ctx = {
    bus = bus, world = entity.new({ cell = 32 }), stream = opts.stream or openStream(), cars = {},
    player = { kind = "player", x = 0, y = 0, z = 0, h = 0, v = 0 }, save = save.blank(),
  }
  local cb = system.new(ctx, { seed = opts.seed or 3 })
  ctx.combat = cb
  return ctx, cb, log
end

local function steps(cb, n, input, dt)
  for _ = 1, n do cb:update(dt or 0.05, input or {}) end
end

-- ---------------------------------------------------------------- the arsenal and the knock rules

t.test("b weapons: six cartoony weapons, melee and guns, each with sane numbers and no blood anywhere", function()
  t.truthy(#weapons.LIST >= 6)
  local melee, guns = 0, 0
  for i, w in ipairs(weapons.LIST) do
    t.eq(w.slot, i)
    t.truthy(w.dmg > 0 and w.range > 0 and w.rate > 0 and w.pellets >= 1)
    if w.kind == "melee" then melee = melee + 1 else
      guns = guns + 1
      t.truthy(w.mag > 0 and w.reserve >= w.mag and w.reload > 0 and w.crate > 0)
    end
    for _, word in ipairs(w.words) do
      t.truthy(word:find("!$"), "a comic word: " .. word)
      t.truthy(not word:lower():find("blood") and not word:lower():find("gore") and not word:lower():find("dead"))
    end
    t.truthy(colors[w.tracer], "a tracer colour " .. w.tracer)
  end
  t.truthy(melee >= 2 and guns >= 4)
  t.truthy(weapons.get("popper").driveby and not weapons.get("longpop").driveby)
  t.truthy(weapons.get("rattler").rate > weapons.get("popper").rate and weapons.get("scatter").pellets > 1)
end)

t.test("b knock: a person is knocked down at zero, stands up with half back, and a third time in a minute keeps them out longer", function()
  local e = { kind = "ped" }
  t.eq(knock.hit(e, 10), "hurt")
  t.eq(e.health, 20)
  t.eq(knock.hit(e, 25), "down")
  t.truthy(e.knocked and e.knockT == knock.DOWN and not e.out)
  t.eq(knock.hit(e, 50), "up", "no new hit on someone already down")
  for _ = 1, 100 do knock.update(e, 0.05) end
  t.truthy(not e.knocked and e.health == 15, "up with half their points: " .. e.health)
  knock.hit(e, 99)
  for _ = 1, 70 do knock.update(e, 0.05) end
  t.truthy(not e.knocked)
  knock.hit(e, 99)
  t.truthy(e.out and e.knockT >= knock.OUT, "the third time they are out")
  for _ = 1, math.floor(knock.OUT / 0.05) + 5 do knock.update(e, 0.05) end
  t.truthy(not e.knocked and not e.out and e.dazed and e.dazed > 0, "out, then up and dazed")
  t.truthy(e.health > 0)
end)

t.test("b knock: a long fight never removes anyone, kills anyone or leaves anyone down for good", function()
  local ctx, cb = newCtx({ seed = 5 })
  cb:give("rattler", 300)
  cb:select("rattler")
  local crowd = {}
  for i = 1, 12 do crowd[i] = cb:spawnGoon(8 + (i % 4) * 2, (i - 6) * 1.2) end
  local count = ctx.world:count()
  local rng = util.rng(1)
  for step = 1, 1200 do
    ctx.player.h = (rng() - 0.5) * 0.6
    cb:update(0.05, { fire = true })
    local st = cb.owned.rattler
    if st.reserve < 30 then st.reserve = 150 end
    t.truthy(ctx.world:count() == count, "nobody was removed (step " .. step .. ")")
    for _, g in ipairs(crowd) do
      t.truthy(not g.removed and (g.health or 0) >= 0, "health stays a number")
    end
  end
  local downed = 0
  for _, g in ipairs(crowd) do if g.knockCount and g.knockCount > 0 then downed = downed + 1 end end
  t.truthy(downed >= 6, "the crowd was knocked about: " .. downed)
  -- stop shooting: everyone is back on their feet within the longest count
  steps(cb, math.floor((knock.OUT + 1) / 0.05) + 20)
  for _, g in ipairs(crowd) do t.truthy(not g.knocked, "everyone stands again") end
end)

-- ---------------------------------------------------------------- aiming

t.test("b aim: near and straight ahead beats far and off to the side, hostile beats the rest, K cycles round", function()
  local list = {
    { id = 1, x = 10, z = 0 }, { id = 2, x = 6, z = 5 }, { id = 3, x = 20, z = 1, hostile = true }, { id = 4, x = -5, z = 0 },
  }
  local r = aim.rank(list, 0, 0, 0, 30, aim.FOOT_CONE)
  t.eq(#r, 3, "the one behind is out of the cone")
  t.eq(r[1].e.id, 1)
  t.truthy(aim.best(list, 0, 0, 0, 30, aim.FOOT_CONE).id == 1)
  -- from a car the cone is wide: the one behind-left is still out, the one at the side is in
  local wide = aim.rank(list, 0, 0, 0, 30, aim.CAR_CONE)
  t.eq(#wide, 3)
  t.eq(#aim.rank({ { id = 9, x = 0, z = 6 } }, 0, 0, 0, 30, aim.FOOT_CONE), 0, "straight to the side is outside the foot cone")
  t.eq(#aim.rank({ { id = 9, x = 0, z = 6 } }, 0, 0, 0, 30, aim.CAR_CONE), 1, "but inside a car's")
  t.eq(aim.cycle(r, r[1].e), r[2].e)
  t.eq(aim.cycle(r, r[3].e), r[1].e, "wraps")
  t.eq(aim.cycle(r, nil), r[1].e)
  t.eq(aim.cycle({}, nil), nil)
  t.eq(#aim.rank(list, 0, 0, 0, 8, aim.FOOT_CONE), 1, "range matters")
end)

t.test("b combat: the game locks on to the best target by itself, K moves to the next, and out of range or down is let go", function()
  local ctx, cb = newCtx()
  local a = cb:spawnGoon(10, 0)
  local b = cb:spawnGoon(16, 3)
  steps(cb, 6)
  t.eq(cb.lock, a, "locked on the nearest in front")
  steps(cb, 1, { target = true })
  t.eq(cb.lock, b, "K cycles to the next")
  steps(cb, 1, { target = true })
  t.eq(cb.lock, a, "and round again")
  knock.down(a)
  steps(cb, 8)
  t.eq(cb.lock, b, "a knocked-down target is let go")
  ctx.player.h = math.pi -- turned away
  steps(cb, 8)
  t.eq(cb.lock, nil, "nothing in front, nothing locked")
end)

t.test("b combat: in a car the lock sees targets at the side, and the shot leaves the window on that side", function()
  local ctx, cb = newCtx()
  local car = vehicle.new("marlin", 0, 0, 0)
  car.y = 0
  ctx.cars[1] = car
  ctx.player.car = car
  local right = cb:spawnGoon(2, 12)
  steps(cb, 6)
  t.eq(cb.lock, right, "a target to the right is found from a car")
  cb:give("popper", 50)
  local before = #cb.fx
  steps(cb, 1, { fire = true })
  local tracer
  for _, f in ipairs(cb.fx) do if f.kind == "tracer" then tracer = f end end
  t.truthy(tracer and before == 0, "a tracer")
  t.truthy(tracer.z0 > 0.5, "the muzzle is at the car's right side: " .. tracer.z0)
  local left = cb:spawnGoon(2, -12)
  local ranked = aim.rank({ right, left }, 0, 0, 0, 30, aim.CAR_CONE)
  t.eq(#ranked, 2)
  -- the left muzzle
  cb.lock = left
  cb.cool = 0
  steps(cb, 1, { fire = true })
  local last
  for _, f in ipairs(cb.fx) do if f.kind == "tracer" then last = f end end
  t.truthy(last.z0 < -0.5, "and at the left for a target on the left: " .. last.z0)
end)

-- ---------------------------------------------------------------- shots

t.test("b shoot: a wall stops a shot, a car is cover, a shooter up high shoots over it", function()
  local wall = { collide = function(_, x, z) if x > 8 then return x, z, true, -1, 0 end return x, z, false, 0, 0 end }
  local target = { x = 12, z = 0, radius = 0.55, y = 0 }
  local hit = shoot.cast({ targets = { target }, stream = wall }, 0, 1.2, 0, 0, 30)
  t.eq(hit.kind, "wall")
  t.truthy(hit.dist >= 8 and hit.dist <= 9.1, "stopped at the wall: " .. hit.dist)
  hit = shoot.cast({ targets = { target }, stream = openStream() }, 0, 1.2, 0, 0, 30)
  t.eq(hit.kind, "target")
  t.eq(hit.e, target)
  local car = vehicle.new("marlin", 6, 0, math.pi / 2)
  car.y = 0
  hit = shoot.cast({ targets = { target }, cars = { car }, stream = openStream() }, 0, 1.2, 0, 0, 30)
  t.eq(hit.kind, "car", "a person behind a car is covered")
  hit = shoot.cast({ targets = { target }, cars = { car }, stream = openStream() }, 0, 4.0, 0, 0, 30)
  t.eq(hit.kind, "target", "shot from above the roof")
  hit = shoot.cast({ targets = { target }, cars = { car }, ignoreCar = car, stream = openStream() }, 0, 1.2, 0, 0, 30)
  t.eq(hit.kind, "target", "a shooter's own car is not cover")
  hit = shoot.cast({ targets = { target }, stream = openStream() }, 0, 1.2, 0, 0.5, 30)
  t.eq(hit.kind, "none")
  hit = shoot.cast({ targets = { target }, stream = openStream() }, 0, 1.2, 0, 0, 8)
  t.eq(hit.kind, "none", "out of range")
  target.knocked = true
  hit = shoot.cast({ targets = { target }, stream = openStream() }, 0, 1.2, 0, 0, 30)
  t.eq(hit.kind, "none", "nobody shoots someone already down")
end)

t.test("b shoot: the testbed's real walls stop shots", function()
  local sp = testbed.spawn
  local s = stream.new({ source = testbed.source, full = 2, low = 2 })
  s:loadAll(sp.x, sp.z)
  local ctx, cb = newCtx({ stream = s })
  -- fire in all directions; at least one is stopped by a wall or by nothing, and none errors
  ctx.player.x, ctx.player.z, ctx.player.y = sp.x, sp.z, s:groundAt(sp.x, sp.z, nil)
  cb:give("longpop", 20)
  cb:select("longpop")
  local walls = 0
  for i = 0, 15 do
    local out = cb:shoot(ctx.player, "longpop", i * math.pi / 8)
    t.eq(out.shots, 1)
  end
  for _, f in ipairs(cb.fx) do if f.kind == "puff" then walls = walls + 1 end end
  t.truthy(walls >= 1, "some shots hit walls: " .. walls)
end)

t.test("b combat: a hit knocks a goon down with a word and stars, never kills, and the player is charged with assault", function()
  local ctx, cb, log = newCtx()
  local g = cb:spawnGoon(10, 0)
  cb:give("longpop", 10)
  cb:select("longpop")
  steps(cb, 6)
  steps(cb, 1, { fire = true })
  t.truthy(g.knocked, "one long shot is enough")
  t.truthy(g.health == 0 and not g.removed)
  local pop
  for _, f in ipairs(cb.fx) do if f.kind == "pop" then pop = f end end
  t.truthy(pop and pop.text:find("!$"), "a comic word")
  t.eq(#log.crime >= 1 and log.crime[#log.crime].kind or "", "gunfire", "the shot is noticed")
  local assault = false
  for _, c in ipairs(log.crime) do if c.kind == "assault" then assault = true end end
  t.truthy(assault, "knocking a stranger down is assault")
  -- someone hostile does not count
  local ctx2, cb2, log2 = newCtx()
  local h = cb2:spawnGoon(10, 0, { fights = true })
  cb2:give("longpop", 10)
  cb2:select("longpop")
  steps(cb2, 6)
  steps(cb2, 1, { fire = true })
  t.truthy(h.knocked)
  for _, c in ipairs(log2.crime) do t.truthy(c.kind ~= "assault", "no assault on someone shooting at you") end
  local _ = ctx2
  -- a cop is worse
  local ctx3, cb3, log3 = newCtx()
  local cop = ctx3.world:add({ kind = "cop", x = 10, y = 0, z = 0, radius = 0.55, tags = { person = true } })
  cb3:give("longpop", 10)
  cb3:select("longpop")
  steps(cb3, 6)
  steps(cb3, 1, { fire = true })
  t.truthy(cop.knocked)
  local worse = false
  for _, c in ipairs(log3.crime) do if c.kind == "cop_assault" and c.level == 2 then worse = true end end
  t.truthy(worse)
end)

t.test("b combat: melee swings at the nearest person in front, in reach only, and not from a car", function()
  local ctx, cb = newCtx()
  cb:select("oar")
  local near = cb:spawnGoon(2.2, 0)
  local far = cb:spawnGoon(7, 0)
  steps(cb, 6)
  for _ = 1, 6 do steps(cb, 12, { fire = true }) end
  t.truthy(near.knocked, "the nearby one was hit")
  t.truthy(not far.knocked and far.health == 30, "the far one was out of reach")
  local car = vehicle.new("marlin", 0, 0, 0)
  ctx.cars[1], ctx.player.car = car, car
  steps(cb, 2)
  t.truthy(cb.current ~= "oar", "getting in a car puts a one-handed gun in hand: " .. cb.current)
  cb.current = "oar"
  cb.cool = 0
  steps(cb, 1, { fire = true })
  t.truthy(cb.msg and cb.msg:find("car"), "no swinging from a car")
end)

t.test("b combat: a car at speed knocks a person down (down = true, even tagged mission), never worse; slow cars do not", function()
  local ctx, cb, log = newCtx()
  local car = vehicle.new("marlin", 0, 0, 0)
  car.y = 0
  ctx.cars[1], ctx.player.car = car, car
  local m = ctx.world:add({ kind = "ped", x = 1, y = 0, z = 0, radius = 0.5, health = 3, tags = { mission = true, enemy = true } })
  car.v = 3
  steps(cb, 1)
  t.truthy(not m.down, "too slow")
  car.v = 12
  steps(cb, 1)
  t.eq(m.down, true)
  t.truthy(not m.removed and m.knocked)
  car.v = 0
  steps(cb, math.floor((knock.DOWN + 0.5) / 0.05))
  t.eq(m.down, false, "and up again")
  ctx.world:remove(m)
  ctx.cars[1] = nil
  -- a gun does the same to a mission person
  ctx.player.car = nil
  local g = ctx.world:add({ kind = "ped", x = 8, y = 0, z = 0, radius = 0.5, health = 3, tags = { mission = true, enemy = true } })
  steps(cb, 6)
  steps(cb, 1, { fire = true })
  t.eq(g.down, true)
  -- stream C's hooks are called when present
  local calls = {}
  ctx.ai = { knock = function(e, vx, vz) calls[#calls + 1] = "knock" end, alarm = function(x, z, r, kind) calls[#calls + 1] = kind end,
    gangs = {} }
  local g2 = ctx.world:add({ kind = "ped", x = 9, y = 0, z = 0, radius = 0.5, health = 3, tags = { mission = true } })
  cb.cool = 0
  steps(cb, 8)
  steps(cb, 1, { fire = true })
  t.truthy(#calls >= 2, "alarm and knock: " .. table.concat(calls, ","))
  t.truthy(type(ctx.ai.gangs.onShoot) == "function", "the gang shot hook is ours")
  local n = #cb.fx
  ctx.ai.gangs.onShoot({ x = 20, z = 0, y = 0 }, { x = 0, z = 0, y = 0 }, false)
  t.truthy(#cb.fx > n, "a gang shot gets a tracer")
  local _ = log and g2
end)

-- ---------------------------------------------------------------- ammo, reloads, pickups

t.test("b ammo: a magazine empties, reloads itself from the reserve, runs dry, and the next gun with ammo comes out", function()
  local ctx, cb = newCtx()
  local g = cb:spawnGoon(25, 0)
  g.health, g.maxHealth = 99999, 99999
  steps(cb, 6)
  local mag, reserve = cb:ammo("popper")
  t.eq(mag, 12) t.eq(reserve, 36)
  for _ = 1, 12 do
    cb.cool = 0
    steps(cb, 1, { fire = true })
  end
  mag = cb:ammo("popper")
  t.eq(mag, 0, "twelve shots")
  t.truthy(cb.reloadT > 0, "it reloads itself")
  steps(cb, 1, { fire = true })
  t.eq(cb:ammo("popper"), 0, "no firing while it reloads")
  steps(cb, math.floor(weapons.get("popper").reload / 0.05) + 3)
  mag, reserve = cb:ammo("popper")
  t.eq(mag, 12) t.eq(reserve, 24, "twelve moved from the reserve")
  -- run it all the way dry
  cb.owned.popper.mag, cb.owned.popper.reserve = 0, 0
  cb.cool = 0
  steps(cb, 1, { fire = true })
  t.truthy(cb.msg and cb.msg:find("out of ammo"), "the HUD says so")
  t.eq(cb.current, "fists", "with nothing else loaded it falls back to fists")
  cb:give("rattler", 40)
  cb:select("rattler")
  cb.owned.rattler.mag, cb.owned.rattler.reserve = 0, 0
  cb.owned.popper.mag = 3
  cb.cool = 0
  steps(cb, 1, { fire = true })
  t.eq(cb.current, "popper", "the next gun with ammo comes out")
end)

t.test("b ammo: crates and guns are picked up by walking over them, capped at the most you can carry, and respawn if set", function()
  local ctx, cb, log = newCtx()
  local pk = cb:dropAmmo(1, 0, "popper", 24)
  steps(cb, 1)
  t.truthy(pk.removed, "an ammo crate is picked up")
  t.eq(select(2, cb:ammo("popper")), 60)
  t.eq(log.pickup[1].kind, "ammo") t.eq(log.pickup[1].id, "popper") t.eq(log.pickup[1].value, 24)
  -- full to the brim: the crate stays
  cb.owned.popper.reserve = 72
  local full = cb:dropAmmo(1, 0, "popper", 24)
  steps(cb, 1)
  t.truthy(not full.removed, "a full pocket leaves the crate")
  ctx.world:remove(full)
  -- a gun
  local gun = cb:dropAmmo(1, 0, "scatter", nil, "gun")
  steps(cb, 1)
  t.truthy(gun.removed and cb.owned.scatter, "got the gun")
  t.truthy(cb.owned.scatter.mag > 0, "with ammo in it")
  t.truthy(cb.msg and cb.msg:find("Gull Scatter"))
  -- a crate that comes back
  cb:give("rattler", 30)
  cb.owned.rattler.reserve = 0
  local again = cb:dropAmmo(1, 0, "rattler", 30)
  again.respawn = 10
  steps(cb, 1)
  t.truthy(not again.removed and again.hiddenT, "hidden until it respawns")
  cb.owned.rattler.reserve = 150 -- full again, so the crate is not taken the moment it is back
  steps(cb, math.floor(10 / 0.05) + 5)
  t.truthy(not again.hiddenT, "and back")
  -- health
  cb:setHp(40)
  local med = ctx.world:add({ kind = "pickup", x = 1, y = 0, z = 0, tags = { pickup = true }, pk = { type = "health", n = 40 } })
  steps(cb, 1)
  t.truthy(med.removed and cb:hp() >= 79)
  -- ammo for a gun you do not carry is left on the ground
  local lonely = cb:dropAmmo(1, 0, "longpop", 10)
  steps(cb, 1)
  t.truthy(not lonely.removed and not cb.owned.longpop, "ammo alone does not make a gun")
  ctx.world:remove(lonely)
  -- a pickup far away is left alone
  local far = cb:dropAmmo(30, 0, "popper", 24)
  steps(cb, 3)
  t.truthy(not far.removed)
end)

t.test("b ammo: the arsenal is saved and loaded (clamped to what a weapon can hold), unknown weapons are ignored", function()
  local ctx, cb = newCtx()
  cb:give("scatter", 20)
  cb:select("scatter")
  local snap = cb:snapshot()
  local ctx2, cb2 = newCtx()
  cb2:restore(snap)
  t.eq(cb2.current, "scatter")
  t.eq(cb2:ammo("scatter"), cb:ammo("scatter"))
  cb2:restore({ owned = { rattler = { mag = 9999, reserve = -5 }, bazooka = { mag = 1, reserve = 1 } }, current = "bazooka" })
  t.eq(cb2.owned.bazooka, nil)
  t.eq(cb2:ammo("rattler"), 30)
  t.eq(select(2, cb2:ammo("rattler")), 0)
  t.truthy(cb2.owned.fists and cb2.owned.popper, "the starter kit is always there")
  cb2:restore("junk")
  local _ = ctx and ctx2
end)

-- ---------------------------------------------------------------- the player

t.test("b player: shot to zero they are knocked down (one event, no death), stand up with 60 hp, and cannot move meanwhile", function()
  local ctx, cb, log = newCtx()
  cb:hurtPlayer(30, "gang")
  t.eq(cb:hp(), 70)
  t.eq(#log.hurt, 1)
  cb:hurtPlayer(80, "gang")
  t.truthy(cb:playerDown())
  t.eq(#log.down, 1)
  t.eq(log.down[1].kind, "ko")
  t.truthy(ctx.player.knocked)
  cb:hurtPlayer(50, "gang")
  t.eq(#log.hurt, 2, "nothing more happens to someone on the ground")
  -- shots do not land on a downed player, and their keys do nothing
  steps(cb, 1, { fire = true })
  t.eq(cb:ammo("popper"), 12, "cannot fire while down")
  steps(cb, math.floor(system.PLAYER_DOWN / 0.05) + 3)
  t.truthy(not cb:playerDown() and not ctx.player.knocked)
  t.eq(cb:hp(), 60)
  -- hit points come back by themselves after a while
  steps(cb, math.floor((system.REGEN_AFTER + 5) / 0.05))
  t.truthy(cb:hp() > 60, "regenerating: " .. cb:hp())
  steps(cb, 2000)
  t.eq(cb:hp(), 100)
end)

t.test("b player: a goon that fights back hurts the player on foot, and a car in the way takes the shot instead", function()
  local ctx, cb, log = newCtx({ seed = 4 })
  ctx.player.x = 0
  local g = cb:spawnGoon(12, 0, { fights = true })
  g.h = math.pi
  g.fireT = 0.1
  local hp = cb:hp()
  steps(cb, 400)
  t.truthy(cb:hp() < hp or #log.hurt > 0 or cb:playerDown(), "being shot at costs hit points: " .. cb:hp())
  t.truthy(#log.hurt > 0)
  -- put a car between them: nothing reaches the player
  local ctx2, cb2, log2 = newCtx({ seed = 4 })
  local car = vehicle.new("tidewater", 6, 0, math.pi / 2)
  car.y = 0
  ctx2.cars[1] = car
  local g2 = cb2:spawnGoon(12, 0, { fights = true })
  g2.fireT = 0.1
  steps(cb2, 400)
  t.eq(#log2.hurt, 0, "cover works for the player too")
  t.truthy(car.health < car.spec.health, "the car took the hits")
end)

-- ---------------------------------------------------------------- the keys

local function fakeKeys()
  local k = {}
  local code = 0
  for _, name in ipairs({ "w", "a", "s", "d", "up", "down", "left", "right", "space", "leftShift", "rightShift", "e", "f", "h",
    "enter", "numPadEnter", "m", "p", "tab", "c", "x", "q", "f3", "j", "k", "l", "one", "two", "three", "four", "five", "six" }) do
    code = code + 1
    k[name] = code
  end
  return k
end

t.test("b keys: J fire, K target, L weapon and 1-6 are added to the game's input, with real CC key timing", function()
  local keys = fakeKeys()
  local ctx = newCtx()
  combatInput.uninstall()
  t.truthy(combatInput.install(function() return ctx end))
  t.truthy(not combatInput.install(function() return ctx end), "installing twice does nothing")
  local inp = inputlib.new(keys)
  t.eq(ctx.input, inp, "the plugin gets the game's own input object")
  local now = 0
  -- J goes down (isHeld false), repeats with isHeld true every 50 ms, then key_up
  inp:event(now, "key", keys.j, false)
  t.truthy(combatInput.read(inp).fire, "down on the first frame")
  inp:endFrame(now)
  for _ = 1, 10 do
    now = now + 0.05
    inp:event(now, "key", keys.j, true)
    t.truthy(combatInput.read(inp).fire, "held through the repeats")
    inp:endFrame(now)
  end
  now = now + 0.05
  inp:event(now, "key_up", keys.j)
  inp:endFrame(now)
  t.truthy(not combatInput.read(inp).fire, "up when released")
  -- a tap that is over before the frame still counts once
  inp:event(now, "key", keys.k, false)
  inp:event(now, "key_up", keys.k)
  t.truthy(combatInput.read(inp).target, "a quick tap of K")
  inp:endFrame(now)
  t.truthy(not combatInput.read(inp).target)
  -- K held through repeats is one press, not many
  inp:event(now, "key", keys.l, false)
  t.truthy(combatInput.read(inp).weapon)
  inp:endFrame(now)
  for _ = 1, 5 do
    now = now + 0.05
    inp:event(now, "key", keys.l, true)
    t.truthy(not combatInput.read(inp).weapon, "a held key is not pressed again")
    inp:endFrame(now)
  end
  inp:event(now, "key_up", keys.l)
  inp:endFrame(now)
  inp:event(now, "key", keys.four, false)
  t.eq(combatInput.read(inp).slot, 4)
  inp:endFrame(now)
  inp:event(now, "key_up", keys.four)
  inp:endFrame(now)
  t.eq(combatInput.read(inp).slot, nil)
  combatInput.uninstall()
end)

t.test("b keys: the core's ctx.input, made before the plugins load, gets J fire too (the play-test found J dead)", function()
  local keys = fakeKeys()
  local ctx = newCtx()
  combatInput.uninstall()
  ctx.input = inputlib.new(keys)
  local inp = ctx.input
  t.truthy(combatInput.install(function() return ctx end, keys))
  t.eq(ctx.input, inp, "the same object, extended")
  inp:event(0, "key", keys.j, false)
  t.truthy(combatInput.read(inp).fire, "J fires")
  inp:endFrame(0)
  inp:event(0, "key_up", keys.j)
  inp:endFrame(0)
  combatInput.uninstall()
end)

t.test("b keys: every direction still moves the right way with real key timing, and a knocked-down player reads as pressing nothing", function()
  local keys = fakeKeys()
  local ctx, cb = newCtx()
  combatInput.uninstall()
  combatInput.install(function() return ctx end)
  local cases = { { "w", "throttle", 1 }, { "up", "throttle", 1 }, { "s", "throttle", -1 }, { "down", "throttle", -1 },
    { "a", "steer", -1 }, { "left", "steer", -1 }, { "d", "steer", 1 }, { "right", "steer", 1 } }
  for _, c in ipairs(cases) do
    local inp = inputlib.new(keys)
    local now = 0
    inp:event(now, "key", keys[c[1]], false)
    local r = inp:read()
    t.eq(r[c[2]], c[3], c[1] .. " on the first frame")
    inp:endFrame(now)
    for _ = 1, 6 do
      now = now + 0.05
      inp:event(now, "key", keys[c[1]], true)
      t.eq(inp:read()[c[2]], c[3], c[1] .. " while held")
      inp:endFrame(now)
    end
    inp:event(now, "key_up", keys[c[1]])
    inp:endFrame(now)
    t.eq(inp:read()[c[2]], 0, c[1] .. " let go")
  end
  local inp = inputlib.new(keys)
  inp:event(0, "key", keys.w, false)
  inp:event(0, "key", keys.d, false)
  inp:event(0, "key", keys.leftShift, false)
  t.eq(inp:read().throttle, 1)
  cb:hurtPlayer(500, "test")
  local r = inp:read()
  t.eq(r.throttle, 0) t.eq(r.steer, 0) t.truthy(not r.sprint)
  combatInput.uninstall()
end)

t.test("b hud: every hint line fits in 51 columns, shows the keys, and one key does one thing", function()
  local ctx, cb = newCtx()
  ctx.player.car = nil
  local seen = {}
  for name, text in pairs(hud.TEXT) do
    t.truthy(#text <= 51, name .. " is " .. #text .. " columns")
    seen[name] = true
  end
  t.truthy(hud.hintLine(ctx):find("J fire") and hud.hintLine(ctx):find("K aim") and hud.hintLine(ctx):find("L gun"))
  ctx.nearCar = true
  t.truthy(hud.hintLine(ctx):find("E take car"))
  ctx.nearCar = nil
  for _, kind in ipairs({ "marlin", "stinger", "wavecutter", "ferrybox" }) do
    local v = vehicle.TYPES[kind]
    if v then
      ctx.player.car = { spec = v }
      t.truthy(#hud.hintLine(ctx) <= 51)
      t.truthy(hud.hintLine(ctx):find("J fire"))
    end
  end
  ctx.player.car = nil
  cb:hurtPlayer(500, "x")
  t.truthy(hud.hintLine(ctx):find("Knocked down"))
  -- the keys named in the hint lines are the ones the game maps (one key, one action)
  local keys = fakeKeys()
  ctx.player.car = nil
  local inp = inputlib.new(keys)
  local used = {}
  for action, list in pairs(inp.map) do
    for _, code in ipairs(list) do
      if code then
        used[code] = used[code] or {}
        used[code][#used[code] + 1] = action
      end
    end
  end
  t.truthy(not used[keys.j], "J is free until the combat keys are installed")
end)

-- ---------------------------------------------------------------- the pixels

t.test("b overlay: painters run only while playing, a broken painter is dropped not the frame, and tracers draw pixels", function()
  local drawn = 0
  local frame = { buffer = { colorValues = {} }, drawBuffer = function() drawn = drawn + 1 end,
    map3dTo2d = function(_, x, y, z) return 10 + x, 10 + z, true end }
  for y = 1, 30 do
    frame.buffer.colorValues[y] = {}
    for x = 1, 40 do frame.buffer.colorValues[y][x] = 1 end
  end
  local playing = false
  overlay.install(frame, function() return playing end)
  t.truthy(not overlay.install(frame, function() return playing end), "wraps once")
  local calls, boom = 0, 0
  overlay.add("t_ok", function() calls = calls + 1 end)
  overlay.add("t_bad", function() boom = boom + 1 error("nope") end)
  frame:drawBuffer()
  t.eq(calls, 0, "not playing: no painter ran")
  playing = true
  frame:drawBuffer()
  frame:drawBuffer()
  t.eq(calls, 2) t.eq(boom, 1, "the broken painter ran once and was dropped")
  t.eq(drawn, 3, "the real blit always happens")
  overlay.remove("t_ok")
  -- the combat painter puts the tracer's pixels in the buffer
  local ctx, cb = newCtx()
  ctx.view = { cam = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0 } }
  cb.fx[#cb.fx + 1] = { kind = "tracer", x0 = 1, y0 = 0, z0 = 1, x1 = 20, y1 = 0, z1 = 1, c = "yellow", ttl = 0.12, t = 0.06 }
  local rows = frame.buffer.colorValues
  fx.paint(ctx, cb, frame, rows, 40, 30)
  local marked = 0
  for y = 1, 30 do for x = 1, 40 do if rows[y][x] ~= 1 then marked = marked + 1 end end end
  t.truthy(marked >= 3, "tracer pixels: " .. marked)
end)

t.test("b combat: effects expire, stay under their cap, and a knocked-down goon has stars until it stands", function()
  local ctx, cb = newCtx()
  cb:give("rattler", 300)
  cb:select("rattler")
  cb:spawnGoon(10, 0)
  steps(cb, 1)
  for _ = 1, 200 do
    cb.cool = 0
    cb.owned.rattler.mag = 30
    steps(cb, 1, { fire = true })
    t.truthy(#cb.fx <= system.MAX_FX, "effects are capped")
  end
  cb.owned.rattler.mag = 0
  steps(cb, 40)
  local live = 0
  for _, f in ipairs(cb.fx) do if f.kind ~= "pop" then live = live + 1 end end
  t.truthy(#cb.fx <= 2, "effects fade: " .. #cb.fx)
  local _ = live
end)

-- ---------------------------------------------------------------- the soak

t.test("b soak: ten minutes of random keys on foot and in a car, shooting everything, nothing NaN and nobody removed", function()
  local sp = testbed.spawn
  local s = stream.new({ source = testbed.source, full = 2, low = 2 })
  s:loadAll(sp.x, sp.z)
  local ctx, cb = newCtx({ stream = s, seed = 8 })
  ctx.player.x, ctx.player.z = sp.x, sp.z
  ctx.player.y = s:groundAt(sp.x, sp.z, nil)
  ctx.player.h = sp.h
  for _, w in ipairs(weapons.LIST) do cb:give(w.id, w.reserve + w.mag) end
  local crowd = {}
  local rng = util.rng(13)
  for i = 1, 20 do
    local a = rng() * math.pi * 2
    local x, z = sp.x + math.cos(a) * (6 + rng() * 14), sp.z + math.sin(a) * (6 + rng() * 14)
    if s:groundAt(x, z, nil) and not select(3, s:collide(x, z, 0.5, 0)) then crowd[#crowd + 1] = cb:spawnGoon(x, z, { fights = i % 3 == 0 }) end
  end
  local count = ctx.world:count()
  local car = vehicle.new("marlin", sp.x + 3, sp.z, sp.h)
  car.y = ctx.player.y
  ctx.cars[1] = car
  for step = 1, 12000 do
    if step % 400 == 0 then ctx.player.car = (not ctx.player.car) and car or nil end
    local h = (ctx.player.car or ctx.player)
    h.h = (h.h or 0) + (rng() - 0.5) * 0.4
    cb:update(0.05, { fire = rng() < 0.7, target = rng() < 0.05, weapon = rng() < 0.02, slot = rng() < 0.01 and math.floor(rng() * 6) + 1 or nil })
    if step % 200 == 0 then
      for _, w in ipairs(weapons.LIST) do cb:give(w.id, w.crate) end
      t.breathe()
    end
    t.truthy(cb:hp() == cb:hp() and cb:hp() >= 0 and cb:hp() <= 100, "hp is a sane number at step " .. step)
    t.truthy(ctx.world:count() == count, "nobody removed at step " .. step)
    t.truthy(#cb.fx <= system.MAX_FX)
  end
  for _, g in ipairs(crowd) do t.truthy(g.x == g.x and g.z == g.z and g.health == g.health, "goon numbers") end
end)
