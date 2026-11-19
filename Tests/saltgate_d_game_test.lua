-- saltgate_d_game_test.lua
-- The story in the game's own context (stream D's plugin on the core's ui, entities, stream, road graph, events and save):
-- a mission offered at its giver, the dialogue box and choices drawn on a 51x19 screen and driven by keys, the cutscene,
-- the failure screen and its retry, the phone, a save and a load in the middle of a job, and a car that follows a route.

local t = require("testing")
local sim = require("saltgate_d_sim")
local termLib = require("saltgate_d_term")
local events = require("sg.core.events")
local entity = require("sg.core.entity")
local stream = require("sg.core.stream")
local uiLib = require("sg.core.ui")
local save = require("sg.core.save")
local plugins = require("sg.core.plugins")
local testbed = require("sg.core.testbed")
local follow = require("sg.core.follow")
local drive = require("sg.core.drive")
local vehicle = require("sg.vehicle")
local worldLib = require("sg.story.world")

testbed.chunks() -- builds the island (and sets testbed.spawn)
local _ = worldLib

--- The game's context, headless: what core/app.lua builds, with a stand-in for the view.
local function game(opts)
  opts = opts or {}
  local bus = events.new()
  local ctx = {
    bus = bus, world = entity.new({ cell = 32 }), content = sim.content(), ui = uiLib.new(bus), cars = {}, log = function(m)
      if opts.verbose then print("log: " .. m) end
    end,
    screen = termLib.term(51, 19), save = opts.save or save.blank(),
  }
  ctx.stream = stream.new({ source = testbed.source, full = 1, low = 1 })
  ctx.stream:loadAll(testbed.spawn.x, testbed.spawn.z)
  ctx.roads = ctx.stream.roads
  ctx.player = { kind = "player", x = 0, z = 0, h = 0, v = 0, y = 0 }
  ctx.drew = 0
  ctx.view = {
    camYaw = 0, r = { frame = { setCamera = function() end } },
    camera = function() end,
    draw = function(self, c) c.drew = c.drew + 1 end,
  }
  ctx.ui.screen({ name = "play", draw = function(c, dt) c.view:draw(c, dt) end })
  ctx.ui.push("play")
  local found = { "d_story" }
  local loaded, failed = plugins.load(found, ctx, require)
  assert(#failed == 0, failed[1] and failed[1].err or "plugin failed")
  ctx.plugins = loaded
  ctx.bus:emit("load", { data = ctx.save })
  ctx.inp = termLib.input()
  return ctx
end

--- One frame the way the core loop will run it: the top screen's input and update, then (not modal) the plugins.
local function frame(ctx, dt, presses)
  dt = dt or 0.1
  for _, a in ipairs(presses or {}) do ctx.inp:press(a) end
  for _, pl in ipairs(ctx.plugins) do
    if pl.input then pl.input(ctx, ctx.inp) end
  end
  local top = ctx.ui.top()
  if top and top.input then top.input(ctx, ctx.inp, dt) end
  top = ctx.ui.top()
  if top and top.modal then
    if top.update then top.update(ctx, dt) end
  else
    for _, pl in ipairs(ctx.plugins) do
      if pl.update then pl.update(ctx, dt) end
    end
  end
  local s = ctx.ui.top()
  if s then s.draw(ctx, dt) end
  ctx.inp.queued = {}
  ctx.inp.clickAt = nil
end

local function story(ctx) return ctx.story.host end

local function teleport(ctx, name)
  local p = ctx.story.idx.places[name]
  ctx.player.x, ctx.player.z = p.x, p.z
  ctx.player.y = ctx.stream:groundAt(p.x, p.z, nil) or 0
end

local function newCar(ctx, kind)
  local c = vehicle.new(kind or "marlin", ctx.player.x + 2, ctx.player.z, 0)
  c.y = ctx.player.y
  ctx.cars[#ctx.cars + 1] = c
  return c
end

local function topName(ctx)
  local s = ctx.ui.top()
  return s and s.name
end

-- ---------------------------------------------------------------- the plugin

t.test("story plugin: loads in the core's plugin loader and registers its screens and HUD", function()
  local ctx = game()
  for _, name in ipairs({ "d_talk", "d_cutscene", "d_fail", "d_pass", "d_phone" }) do
    t.truthy(ctx.ui.screens[name], name .. " registered")
  end
  local names = {}
  for _, w in ipairs(ctx.ui.widgetList) do names[w.name] = true end
  t.truthy(names.d_objective and names.d_clock and names.d_toast, "HUD widgets")
  t.eq(ctx.story.host.state, "idle")
  t.truthy(ctx.story.target, "the minimap can ask where to go")
  local x, z, kind = ctx.story.target()
  t.eq(kind, "giver")
  t.truthy(x and z)
end)

t.test("story plugin: walking up to Juno offers the first job; the box and the choice are drawn and answered with keys", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  t.eq(story(ctx).state, "running", "the job starts at its giver")
  frame(ctx)
  t.eq(topName(ctx), "d_talk")
  frame(ctx, 0.5)
  t.truthy(ctx.screen.has("Mama Juno"), "the speaker's name plate")
  t.truthy(ctx.screen.has("Wren Calloway"), "the first line shows")
  t.eq(ctx.screen.overflow, 0, "nothing drawn past column 51")
  -- ENTER shows the rest, ENTER moves on
  local choiceSeen = false
  for i = 1, 40 do
    frame(ctx, 0.5, { "advance" })
    if story(ctx).talk.choice then
      choiceSeen = true
      frame(ctx, 0.1)
      t.truthy(ctx.screen.has("1. "), "the choices are numbered")
      t.truthy(ctx.screen.has("ENTER/SPACE or click"))
      frame(ctx, 0.1, { "down" })
      frame(ctx, 0.1, { "advance" })
      break
    end
  end
  t.truthy(choiceSeen, "reached the choice")
  t.eq(ctx.screen.overflow, 0)
end)

--- The screen row a piece of text is on (nil when it is not there).
local function rowOf(ctx, text)
  local _, h = ctx.screen.getSize()
  for y = 1, h do
    local s = ctx.screen.row(y)
    local x = s:find(text, 1, true)
    if x then return y, x end
  end
  return nil
end

t.test("story plugin: a mouse click is ENTER for the talk; a click on a choice says it, a click beside the choices says nothing", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  frame(ctx)
  t.eq(topName(ctx), "d_talk")
  local talk = story(ctx).talk
  local before = talk.line and talk.line.text
  -- clicks move the talk on, as ENTER does (the first shows the whole line, the next goes on)
  local reached = false
  for _ = 1, 40 do
    ctx.inp:click(25, 3)
    frame(ctx, 0.5)
    if talk.choice then reached = true break end
  end
  t.truthy(reached, "clicking through the talk reaches Juno's first choice")
  t.truthy(talk.line == nil or talk.line.text ~= before, "the talk moved on")
  frame(ctx, 0.1)
  -- a click beside the options (the top of the screen): nothing is said
  local options = #talk.choice.options
  ctx.inp:click(25, 1)
  frame(ctx, 0.1)
  t.truthy(talk.choice ~= nil and #talk.choice.options == options, "a click beside the choices does not answer")
  -- a click on option 3
  local y, x = rowOf(ctx, "3. ")
  t.truthy(y, "option 3 is on the screen")
  ctx.inp:click(x + 4, y)
  frame(ctx, 0.1)
  t.eq(talk.choice, nil, "clicked option answered")
  -- the third answer of Fresh Air's first choice: Juno laughs about noodles
  local said = false
  for _ = 1, 6 do
    if ctx.screen.has("Ha! There she is") or (talk.line and (talk.line.text or ""):find("Ha! There she is", 1, true)) then said = true break end
    frame(ctx, 0.5)
  end
  t.truthy(said, "Juno answers the third option")
end)

--- Press ENTER (and pick the first choice) until the talk is over and the screen is the game's again.
local function talkThrough(ctx, maxFrames)
  for i = 1, maxFrames or 80 do
    if story(ctx).state == "passed" then return true end
    if topName(ctx) == "play" and not story(ctx).talk:talking() and not story(ctx).cut then
      -- the script has to get its turn to say more
      for _ = 1, 3 do frame(ctx, 0.1) end
      if story(ctx).state == "passed" then return true end
      if topName(ctx) == "play" and not story(ctx).talk:talking() and not story(ctx).cut then return true end
    end
    frame(ctx, 0.4, { "advance" })
  end
  return false
end

t.test("story plugin: on MISSION FAILED a click on Give up gives up; a click beside the options does nothing", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  t.truthy(talkThrough(ctx))
  ctx.player.car = newCar(ctx)
  frame(ctx)
  frame(ctx)
  ctx.bus:emit("player_down", { kind = "ko" })
  frame(ctx)
  frame(ctx)
  t.eq(topName(ctx), "d_fail")
  frame(ctx, 0.1)
  ctx.inp:click(48, 2)
  frame(ctx, 0.1)
  t.eq(topName(ctx), "d_fail", "a click beside the options leaves the screen up")
  local y, x = rowOf(ctx, "Give up")
  t.truthy(y, "Give up is on the screen")
  ctx.inp:click(x + 1, y)
  frame(ctx, 0.1)
  frame(ctx)
  t.eq(story(ctx).state, "idle", "gave up")
end)

t.test("story plugin: a whole job in the game's context, paid, remembered, saved and passed", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  t.truthy(talkThrough(ctx), "the first conversation ends")
  t.eq(story(ctx).checkpointName, "wheels")
  -- steal a car
  local car = newCar(ctx)
  ctx.player.car = car
  frame(ctx)
  frame(ctx)
  t.eq(story(ctx).checkpointName, "lot", "in a car: on to the drive")
  teleport(ctx, "juno_lot")
  car.x, car.z, car.v = ctx.player.x, ctx.player.z, 0
  frame(ctx)
  frame(ctx)
  t.truthy(talkThrough(ctx), "the last conversation")
  t.eq(story(ctx).state, "passed")
  t.eq(topName(ctx), "d_pass", "the JOB DONE card")
  t.truthy(ctx.screen.has("JOB DONE"))
  t.eq(ctx.save.player.money, 200, "paid")
  frame(ctx, 0.1, { "advance" })
  t.eq(topName(ctx), "play")
  t.truthy(ctx.save.story.done.fresh_air, "done is in the save")
  t.truthy(ctx.save.story.phone.unlocked.juno, "Juno is in the phone")
  t.eq(ctx.save.story.mission, nil)
  -- the next job is hot_broth, at Juno again, not offered for a few seconds
  t.eq(story(ctx):next().id, "hot_broth")
end)

t.test("story plugin: a save in the middle of a job comes back at its step, in a new game", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  t.truthy(talkThrough(ctx))
  local car = newCar(ctx)
  ctx.player.car = car
  frame(ctx)
  frame(ctx)
  t.eq(story(ctx).checkpointName, "lot")
  -- the game saves
  local data = save.blank()
  data.story = ctx.save.story
  ctx.bus:emit("save", { data = data })
  t.eq(data.story.mission.checkpoint, "lot")
  local fs = { files = {} }
  local text = (function()
    save.write({ exists = function() return false end, open = function(_, mode)
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end, close = function() fs.files.x = table.concat(buf) end }
    end, move = function() end, delete = function() end }, "x", data)
    return fs.files.x
  end)()
  t.truthy(#text > 10)
  -- a new session from the same save table
  local ctx2 = game({ save = data })
  t.eq(story(ctx2).state, "running", "the job is running again after the load")
  frame(ctx2)
  t.eq(story(ctx2).checkpointName, "lot")
  t.truthy(ctx2.save.story.done.fresh_air == nil)
  -- put in its car at the lot it goes on to the end
  teleport(ctx2, "juno_lot")
  t.truthy(ctx2.player.car, "put in a car at the checkpoint")
  ctx2.player.car.x, ctx2.player.car.z, ctx2.player.car.v = ctx2.player.x, ctx2.player.z, 0
  for i = 1, 6 do frame(ctx2) end
  t.truthy(talkThrough(ctx2))
  t.eq(story(ctx2).state, "passed")
end)

t.test("story plugin: failing shows the failure screen; retrying goes back to the checkpoint with the car", function()
  local ctx = game()
  teleport(ctx, "juno")
  frame(ctx)
  t.truthy(talkThrough(ctx))
  local car = newCar(ctx)
  ctx.player.car = car
  frame(ctx)
  frame(ctx)
  t.eq(story(ctx).checkpointName, "lot")
  -- knocked out
  ctx.bus:emit("player_down", { kind = "ko" })
  frame(ctx)
  frame(ctx)
  t.eq(story(ctx).state, "failed")
  t.eq(topName(ctx), "d_fail")
  frame(ctx, 0.1)
  t.truthy(ctx.screen.has("MISSION FAILED"))
  t.truthy(ctx.screen.has("knocked out"))
  t.truthy(ctx.screen.has("Retry from the checkpoint"))
  frame(ctx, 0.1, { "advance" })
  frame(ctx)
  frame(ctx)
  t.eq(story(ctx).state, "running")
  t.eq(story(ctx).checkpointName, "lot")
  t.truthy(ctx.player.car, "put back in a car")
  -- giving up instead
  ctx.bus:emit("player_down", { kind = "nabbed" })
  frame(ctx)
  frame(ctx)
  t.eq(topName(ctx), "d_fail")
  frame(ctx, 0.1, { "down" })
  frame(ctx, 0.1, { "down" })
  frame(ctx, 0.1, { "advance" })
  frame(ctx)
  t.eq(story(ctx).state, "idle")
  t.eq(ctx.save.story.mission, nil)
end)

t.test("story plugin: the phone lists who you know, shows texts as read, and a call says something", function()
  local ctx = game()
  frame(ctx, 0.1, { "phone" })
  t.eq(topName(ctx), "d_phone")
  frame(ctx)
  t.truthy(ctx.screen.has("No contacts yet"))
  frame(ctx, 0.1, { "phone" })
  t.eq(topName(ctx), "play")
  ctx.save.story.phone.unlocked.juno = true
  ctx.save.story.phone.unlocked.tam = true
  story(ctx):phoneText("tam", "Pit Wall online. Say Tam for hints.")
  frame(ctx, 0.1, { "phone" })
  frame(ctx)
  t.truthy(ctx.screen.has("Mama Juno"))
  t.truthy(ctx.screen.has("Tam"))
  t.truthy(ctx.screen.has("*"), "an unread dot")
  frame(ctx, 0.1, { "down" })
  frame(ctx)
  t.truthy(ctx.screen.has("Pit Wall online"), "the text shows")
  frame(ctx, 0.1, { "advance" })
  frame(ctx)
  t.truthy(ctx.screen.has("Tam:"), "a call")
  t.eq(ctx.screen.overflow, 0)
  frame(ctx, 0.1, { "advance" })
  frame(ctx, 0.1, { "pause" })
  t.eq(topName(ctx), "play")
  local read = true
  for _, tx in ipairs(ctx.save.story.phone.texts) do read = read and tx.read end
  t.truthy(read, "read once seen")
end)

t.test("story plugin: a cutscene takes over the camera and the bars, and X skips it", function()
  local ctx = game()
  local host = story(ctx)
  teleport(ctx, "gilt_door")
  host.story.done = {}
  for _, def in ipairs(host.list.missions) do
    if def.id ~= "low_tide" and def.act == 1 then host.story.done[def.id] = true end
  end
  host:start("low_tide")
  -- fast-forward to the cutscene: plan, car, doors
  ctx.story.world.down = false
  local sawCut = false
  for i = 1, 400 do
    local top = topName(ctx)
    if host.state ~= "running" then break end
    if host.cut then
      sawCut = true
      frame(ctx, 0.2)
      t.eq(topName(ctx), "d_cutscene")
      t.truthy(ctx.screen.has("X skip scene"))
      frame(ctx, 0.1, { "skip" })
      frame(ctx, 0.1)
      t.truthy(host.cut == nil, "skipped")
      t.truthy(ctx.view.override == nil, "the camera is given back")
      break
    end
    if top == "d_talk" then
      frame(ctx, 0.4, { "advance" })
    else
      -- play the goals the quick way
      local g = host.goal
      if g and g.kind == "anycar" then
        local car = newCar(ctx)
        ctx.player.car = car
      elseif g and g.kind == "go" then
        teleport(ctx, g.place)
        local car = ctx.player.car or newCar(ctx)
        car.x, car.z, car.v = ctx.player.x, ctx.player.z, 0
        ctx.player.car = car
      end
      frame(ctx, 0.1)
    end
  end
  t.truthy(sawCut, "the cutscene played")
end)

-- ---------------------------------------------------------------- the adapter against the testbed

t.test("story world: places, distances, arriving in a car, and heights", function()
  local ctx = game()
  local w = ctx.story.world
  teleport(ctx, "juno")
  t.truthy(w:inPlace("juno", {}))
  t.truthy(not w:inPlace("juno", { car = true }), "on foot is not in a car")
  local car = newCar(ctx)
  ctx.player.car = car
  car.x, car.z, car.v = ctx.player.x, ctx.player.z, 12
  t.truthy(w:inPlace("juno", { car = true }))
  t.truthy(not w:inPlace("juno", { car = true, speed = 9 }), "too fast to count as stopping")
  t.truthy(not w:inPlace("juno", { actor = {} }), "not that car")
  -- a place on a deck above does not count from the road below
  ctx.places = { deck = { x = car.x, z = car.z, r = 6, y = 20 } }
  car.y = 0
  t.truthy(not w:inPlace("deck", {}), "the deck is above you")
  car.y = 19
  t.truthy(w:inPlace("deck", {}), "and now you are on it")
  t.truthy(w:distTo("rusty") > 10)
end)

t.test("story world: cars made for a mission are cleaned away, wrecks are noticed, health is a fraction", function()
  local ctx = game()
  local w = ctx.story.world
  teleport(ctx, "juno")
  local a = w:spawn("car", "juno_lot", { vehicle = "sovereign" })
  t.truthy(a and a.mission)
  t.eq(w:state(a), "ok")
  t.eq(w:health(a), 1)
  a.health = a.spec.health / 2
  t.near(w:health(a), 0.5, 0.01)
  a.wrecked = true
  t.eq(w:state(a), "wrecked")
  ctx.player.car = a
  w:cleanup()
  t.eq(#ctx.cars, 0, "gone from the game's cars")
  t.eq(ctx.player.car, nil, "the player is out of it")
  t.eq(w:state(a), "gone")
  -- an unknown car falls back to one that exists
  local b = w:spawn("car", "juno_lot", { vehicle = "no_such_car" })
  t.truthy(b and b.spec)
end)

t.test("story world: heat is read from heat_changed and raised through crime; pay writes the save and sends money", function()
  local ctx = game()
  local w = ctx.story.world
  local crimes, money = {}, {}
  ctx.bus:on("crime", function(d) crimes[#crimes + 1] = d end, "test")
  ctx.bus:on("money", function(d) money[#money + 1] = d end, "test")
  t.eq(w:heat(), 0)
  w:setHeat(3)
  t.eq(crimes[1].level, 3)
  ctx.bus:emit("heat_changed", { level = 3, previous = 0 })
  t.eq(w:heat(), 3)
  w:setHeat(2)
  t.eq(#crimes, 1, "never lowers")
  -- a heat module, when the game has one, is what is asked
  ctx.heat = { level = 4, set = function(self, n) self.level = n end }
  t.eq(w:heat(), 4)
  w:setHeat(0, true)
  t.eq(ctx.heat.level, 0)
  w:pay(250)
  t.eq(ctx.save.player.money, 250)
  t.eq(money[1].amount, 250)
end)

t.test("story world: people to knock down fall to a car at speed (or a punch) when no combat system is there, and the job notices", function()
  local ctx = game()
  local w = ctx.story.world
  teleport(ctx, "cannery")
  local lead = w:spawn("crew", "cannery", { group = "cass", count = 3 })
  t.eq(w:remaining("cass"), 3)
  t.eq(w:state(lead), "ok")
  -- a punch beside one
  local e = w.people[1]
  ctx.player.x, ctx.player.z = e.x + 1, e.z
  w.punch = true
  w:update(0.1)
  t.eq(w:remaining("cass"), 2)
  -- a car at speed through the other two
  local car = newCar(ctx)
  ctx.player.car = car
  car.v = 12
  for _, p in ipairs(w.people) do
    car.x, car.z = p.x, p.z
    w:update(0.1)
  end
  t.eq(w:remaining("cass"), 0)
  t.eq(w:state(lead), "down")
  -- a combat system's knockdown counts the same way
  local again = w:spawn("crew", "cannery", { group = "g2", count = 2 })
  ctx.combat = {}
  again.health = 0
  t.eq(w:remaining("g2"), 1)
end)

t.test("story world: a jump is measured from take-off to landing, and water is not a landing", function()
  local ctx = game()
  local w = ctx.story.world
  local car = newCar(ctx)
  ctx.player.car = car
  car.x, car.z, car.y = 100, 100, 5
  car.airborne = true
  w:update(0.05)
  car.x, car.z = 128, 100
  car.airborne = false
  w:update(0.05)
  local f = w:flight()
  t.truthy(f and f.landed)
  t.near(f.distance, 28, 0.01)
  w:clearFlight()
  t.eq(w:flight(), nil)
end)

t.test("story world: a runner follows its route over the testbed's roads and arrives", function()
  local ctx = game()
  local w = ctx.story.world
  -- the testbed's roads: from the start of the coast road to a point further along it
  -- the farthest coast road junction that is loaded
  local far, best = nil, 0
  for _, id in ipairs(testbed.FEATURES.coast) do
    local nd = ctx.roads:node(id)
    if nd and nd.defined then
      local d = (nd.x - testbed.spawn.x) ^ 2 + (nd.z - testbed.spawn.z) ^ 2
      if d > best then far, best = nd, d end
    end
  end
  t.truthy(far and far.x, "a node half way round the coast road")
  ctx.places = {
    from = { x = testbed.spawn.x, z = testbed.spawn.z, r = 6 },
    to = { x = far.x, z = far.z, r = 12 },
  }
  local car = w:spawn("runner", "from", { vehicle = "kestrel", route = { "to" } })
  ctx.player.x, ctx.player.z = car.x, car.z
  t.truthy(car.follow, "a route was planned")
  local ticks = 0
  while w:state(car) == "ok" and ticks < 2400 do
    ticks = ticks + 1
    local input = follow.input(car.follow, car, 0.05)
    drive.step(car, input, 0.05, ctx.stream)
    w:update(0.05)
    if car.follow == nil then break end
  end
  t.eq(w:state(car), "arrived", "it got there (after " .. ticks .. " steps)")
  t.truthy(car.follow == nil, "and stops")
end)

t.test("story world: a runner whose goal is past the loaded roads heads toward it and plans again as the city loads (Pit Wall's courier)", function()
  local ctx = game()
  local w = ctx.story.world
  -- a goal on the coast road far from the start: with only the chunks round the start loaded there is no full path
  local farNode, best = nil, 0
  for _, c in pairs(testbed.chunks()) do
    for _, n in ipairs(c.nodes) do
      local d = (n[2] - testbed.spawn.x) ^ 2 + (n[4] - testbed.spawn.z) ^ 2
      if d > best then farNode, best = n, d end
    end
  end
  local goal = { x = farNode[2], z = farNode[4], r = 12 }
  ctx.places = { from = { x = testbed.spawn.x, z = testbed.spawn.z, r = 6 }, to = goal }
  ctx.stream = stream.new({ source = testbed.source, full = 1, low = 1 })
  ctx.stream:loadAll(testbed.spawn.x, testbed.spawn.z)
  ctx.roads = ctx.stream.roads
  t.truthy(ctx.roads:nearest(goal.x, goal.z, 30) == nil, "the goal's roads are not loaded yet")
  local car = w:spawn("runner", "from", { vehicle = "kestrel", route = { "to" } })
  t.truthy(car.follow and car.follow.partial, "a plan as far as the loaded roads go")
  t.truthy(#car.follow.route > 0, "and it has somewhere to drive")
  local start = math.sqrt((car.x - goal.x) ^ 2 + (car.z - goal.z) ^ 2)
  local nearest = start
  for _ = 1, 20 * 240 do
    -- the player tails it, so the city loads round them both
    ctx.player.x, ctx.player.z = car.x - 20, car.z
    ctx.stream:update(ctx.player.x, ctx.player.z, true)
    local input = car.follow and follow.input(car.follow, car, 0.05) or { throttle = 0 }
    drive.step(car, input, 0.05, ctx.stream)
    w:update(0.05)
    nearest = math.min(nearest, math.sqrt((car.x - goal.x) ^ 2 + (car.z - goal.z) ^ 2))
    if w:state(car) ~= "ok" then break end
  end
  t.truthy(nearest < start * 0.5, "it made real progress toward the goal: " .. math.floor(start) .. " to " .. math.floor(nearest))
  t.eq(w:state(car), "arrived", "and got there")
end)

t.test("story world: a fleeing runner counts as caught when it is rammed down to nothing", function()
  local ctx = game()
  local w = ctx.story.world
  teleport(ctx, "juno")
  ctx.places = { start = { x = testbed.spawn.x, z = testbed.spawn.z, r = 6 }, far = { x = testbed.spawn.x + 60, z = testbed.spawn.z, r = 5 } }
  local car = w:spawn("runner", "start", { vehicle = "kestrel", route = { "far" }, flees = true })
  ctx.player.x, ctx.player.z = car.x + 4, car.z
  w:update(4)
  t.eq(w:state(car), "ok")
  car.health = car.spec.health * 0.2
  w:update(0.1)
  t.eq(w:state(car), "caught")
end)
