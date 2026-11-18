-- saltgate_d_kit_test.lua
-- The story's machinery on small made-up missions: the dialogue box, the cutscene camera, the mission verbs (timers, tails,
-- chases, escorts, shootouts, holds, jumps) and every way each one fails, the host's save rules, retries and old saves,
-- and the phone. The real missions are tested in saltgate_d_story_test.lua.

local t = require("testing")
local sim = require("saltgate_d_sim")
local talkLib = require("sg.story.talk")
local textLib = require("sg.story.text")
local cutsceneLib = require("sg.story.cutscene")
local phoneLib = require("sg.story.phone")
local hostLib = require("sg.story.host")
local events = require("sg.core.events")

local idx = sim.index()

--- A host over a made-up world playing one inline mission.
local function mission(fn, opts)
  opts = opts or {}
  local list = { missions = { { id = "m", act = 1, title = "M", giver = "juno", reward = 100, music = "job" } },
    byId = {}, actEnd = { [1] = "m" }, places = idx.places, cast = idx.cast, phone = idx.phone }
  list.byId.m = list.missions[1]
  local bus = events.new()
  local w = sim.world(idx.places)
  w.p.x, w.p.z = idx.places.juno.x, idx.places.juno.z
  local cues = {}
  local host = hostLib.new({ bus = bus, world = w, list = list, script = function() return fn end,
    music = function(c) cues[#cues + 1] = c end })
  host:bind(opts.story or { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} } })
  host.cues = cues
  return host, w, bus
end

--- Run ticks of dt; stop early at a state.
local function run(host, seconds, dt, each)
  dt = dt or 0.1
  for _ = 1, math.floor(seconds / dt) do
    if host.state ~= "running" then break end
    if each then each() end
    host:update(dt)
  end
end

local function ends(host) return host.state end

-- ---------------------------------------------------------------- text, talk, cutscene

t.test("story text: wrap breaks on spaces, cuts a word that is too long, and fits says whether it fits", function()
  local rows = textLib.wrap("one two three four", 9)
  t.eq(#rows, 3)
  t.eq(rows[1], "one two")
  t.eq(rows[2], "three")
  t.eq(rows[3], "four")
  t.eq(#textLib.wrap("abcdefghijkl", 5), 3)
  t.truthy(textLib.fits(string.rep("word ", 30), 47, 4))
  t.truthy(not textLib.fits(string.rep("word ", 50), 47, 4))
  t.truthy(not textLib.fits("abcdefghijkl", 5, 4), "a word wider than the box")
  t.eq(textLib.clip("abcdefghij", 6), "abcd..")
  t.eq(#textLib.centre("hi", 9), 9)
end)

t.test("story talk: letters appear over time, ENTER finishes then moves on, choices wrap round and take number keys", function()
  local tk = talkLib.new()
  tk:say("Wren", "Hello there, this is a line of talk that takes a moment.")
  t.truthy(tk:talking())
  tk:update(0.1)
  t.truthy(tk.line.shown > 0 and not tk.line.full)
  t.eq(tk:advance(), "reveal")
  t.truthy(tk.line.full)
  t.eq(table.concat(tk:visibleRows(), " "), "Hello there, this is a line of talk that takes a moment.")
  t.eq(tk:advance(), "next")
  t.truthy(not tk:talking())
  tk:choose("Which?", { "a", "b", "c" })
  t.eq(tk.choice.sel, 1)
  tk:move(-1)
  t.eq(tk.choice.sel, 3, "wraps")
  tk:move(1)
  tk:move(1)
  t.eq(tk.choice.sel, 2)
  t.eq(tk:advance(), "picked")
  t.eq(tk:chosen(), 2)
  t.eq(tk:chosen(), nil, "only once")
  tk:choose("Again?", { "x", "y" })
  tk:pick(2)
  t.eq(tk:chosen(), 2, "number key")
  -- X skips the lines but not a choice
  tk:say("A", "line one")
  tk:say("A", "line two")
  tk:choose("Must answer", { "p", "q" })
  tk:skipAll()
  t.truthy(tk.choice, "the choice is still to be made")
  t.eq(tk.history[#tk.history][2], "line one")
end)

t.test("story cutscene: shots in order, a fade, a camera looking at its target, drift and orbit, skip and next", function()
  local positions = { a = { 0, 0, 0 }, b = { 10, 0, 0 } }
  local resolve = function(spec)
    local p = type(spec) == "string" and positions[spec] or spec
    return p[1], p[2] or 0, p[3] or p[2]
  end
  local c = cutsceneLib.new({
    { at = { 0, 0 }, look = { 10, 0 }, seconds = 2, height = 5, fade = "in", caption = "hello" },
    { at = { 10, 0 }, look = { 0, 0 }, seconds = 2, drift = { 4, 0, 0 } },
  }, function(spec) return spec[1], 0, spec[2] end)
  t.near(c:fade(), 1, 0.01, "starts black when it fades in")
  c:update(1)
  t.near(c:fade(), 0, 0.01)
  local cam = c:camera()
  t.near(cam.x, 0, 0.01)
  t.near(cam.y, 5, 0.01)
  t.near(cam.yaw, 0, 0.01, "looking along +x")
  t.truthy(cam.pitch < 0, "looking down at something below the camera (the view's pitch is negative down)")
  c:update(1.5)
  t.eq(c.index, 2)
  c:update(1)
  local cam2 = c:camera()
  t.near(cam2.x, 12, 0.01, "dollied half way along its drift")
  t.near(math.abs(cam2.yaw), math.pi, 0.01, "looking back along -x")
  c:next()
  t.truthy(c.done)
  local d = cutsceneLib.new({ { at = { 0, 0 }, look = { 1, 0 } } }, resolve)
  d:skip()
  t.truthy(d.done and d.skipped)
  -- validate
  t.truthy(cutsceneLib.validate({ { at = "a" } }))
  t.truthy(not cutsceneLib.validate({}))
  t.truthy(not cutsceneLib.validate({ { at = "a", seconds = 99 } }))
  t.truthy(not cutsceneLib.validate({ { at = "a", say = { "Who" } } }))
  t.truthy(cutsceneLib.validate({ { black = true, title = "Card" } }))
  -- an orbit moves the camera round what it looks at, keeping its distance
  local o = cutsceneLib.new({ { at = { 10, 0 }, look = { 0, 0 }, seconds = 4, orbit = 90 } }, function(spec) return spec[1], 0, spec[2] end)
  o:update(2)
  local oc = o:camera()
  t.near(math.sqrt(oc.x ^ 2 + oc.z ^ 2), 10, 0.01)
  t.truthy(math.abs(oc.z) > 1, "swung round")
end)

-- ---------------------------------------------------------------- the verbs and how they fail

t.test("kit: a timer shows, counts only while you play, and fails the job with its reason at zero", function()
  local host, w = mission(function(api)
    api.step("go", function()
      api.timer(5, "TIME", "the broth went cold")
      api.drive("ferry", { text = "Go." })
    end)
  end)
  host:start("m")
  run(host, 2)
  t.truthy(host.timer and host.timer.left < 4)
  -- a conversation stops the clock
  host.talk:say("A", "talking")
  local left = host.timer.left
  run(host, 3)
  t.near(host.timer.left, left, 0.01, "frozen while talking")
  host.talk:clear()
  run(host, 6)
  t.eq(host.state, "failed")
  t.eq(host.failed.reason, "the broth went cold")
end)

t.test("kit: a drive is not done in the wrong car, too fast, with heat on (when noHeat), or without a car", function()
  local host, w = mission(function(api)
    api.step("a", function()
      api.car("marlin", "juno", { name = "mine" })
      api.drive("ferry", { name = "mine", noHeat = true, minHealth = 0.5, failText = "too damaged" })
    end)
  end)
  host:start("m")
  run(host, 1)
  local car = host.actors.mine
  local f = idx.places.ferry
  w.p.x, w.p.z = f.x, f.z
  run(host, 1)
  t.eq(host.state, "running", "on foot is not in the car")
  w.p.car = { state = "ok" }
  run(host, 1)
  t.eq(host.state, "running", "someone else's car")
  w.p.car = car
  w.level = 2
  run(host, 1)
  t.eq(host.state, "running", "heat on")
  t.truthy(host:objectiveInfo().text:find("Patrol"), "the HUD says why")
  w.level = 0
  w.p.speed = 15
  run(host, 1)
  t.eq(host.state, "running", "too fast to count as arriving")
  w.p.speed = 0
  car.health = 0.3
  run(host, 1)
  t.eq(host.state, "failed")
  t.eq(host.failed.reason, "too damaged")
end)

t.test("kit: a mission car that is wrecked fails the job at once, by name", function()
  local host, w = mission(function(api)
    api.step("a", function()
      api.car("sovereign", "juno", { name = "gold", label = "Sovereign" })
      api.getIn("gold", "Steal it.")
    end)
  end)
  host:start("m")
  run(host, 1)
  host.actors.gold.state = "wrecked"
  run(host, 1)
  t.eq(host.state, "failed")
  t.eq(host.failed.reason, "the Sovereign is wrecked")
end)

t.test("kit: tail fails when you lose them, when you crowd them, and when they are gone, and passes when they arrive", function()
  local function tailing(setup)
    local host, w = mission(function(api)
      api.step("t", function()
        api.actor("runner", "juno", { name = "x", route = { "ferry" } })
        api.tail("x", { min = 7, max = 70, grace = 3, spot = 2 })
      end)
    end)
    host:start("m")
    run(host, 0.5)
    setup(host, host.actors.x, w)
    return host
  end
  local far = tailing(function(h, a) a.gap = 120 end)
  run(far, 5)
  t.eq(far.failed.reason, "you lost them")
  local near = tailing(function(h, a) a.gap = 3 end)
  run(near, 4)
  t.eq(near.failed.reason, "they spotted you")
  local gone = tailing(function(h, a) a.state = "wrecked" end)
  run(gone, 1)
  t.eq(gone.failed.reason, "the target is gone")
  local good = tailing(function(h, a) a.gap = 30 end)
  t.truthy(good.holdNote == nil)
  run(good, 5)
  t.eq(good.state, "running")
  good.actors.x.state = "arrived"
  run(good, 1)
  t.eq(good.state, "passed")
  local hint = tailing(function(h, a) a.gap = 60 end)
  run(hint, 1)
  t.truthy(hint:objectiveInfo().text:find("Closer"), "told to close up before they are lost")
end)

t.test("kit: chase ends caught or wrecked, and fails when they escape or arrive", function()
  local function chasing(final)
    local host = mission(function(api)
      api.step("c", function()
        api.actor("runner", "juno", { name = "x", route = { "ferry" }, flees = true })
        api.chase("x", { failText = "they got away" })
      end)
    end)
    host:start("m")
    run(host, 0.5)
    host.actors.x.state = final
    run(host, 1)
    return host
  end
  t.eq(chasing("caught").state, "passed")
  t.eq(chasing("wrecked").state, "passed")
  t.eq(chasing("escaped").failed.reason, "they got away")
  t.eq(chasing("arrived").failed.reason, "they got away")
end)

t.test("kit: escort needs them to arrive alive and not too far behind", function()
  local function escorting(final, gap)
    local host = mission(function(api)
      api.step("e", function()
        api.actor("runner", "juno", { name = "pip", route = { "ferry" } })
        api.escort("pip", "safehouse", { max = 50, failText = "they didn't make it" })
      end)
    end)
    host:start("m")
    run(host, 0.5)
    if gap then host.actors.pip.gap = gap end
    host.actors.pip.state = final
    return host
  end
  local ok = escorting("arrived")
  run(ok, 1)
  t.eq(ok.state, "passed")
  local dead = escorting("wrecked")
  run(dead, 1)
  t.eq(dead.failed.reason, "they didn't make it")
  local behind = escorting("ok", 200)
  run(behind, 12)
  t.eq(behind.failed.reason, "you left them behind")
end)

t.test("kit: defeat counts the people still up in the HUD and passes when all are down; a timeout fails", function()
  local host, w = mission(function(api)
    api.step("d", function()
      api.actor("crew", "juno", { group = "g", count = 4 })
      api.defeat("g", { text = "Knock them down.", timeout = 20 })
    end)
  end)
  host:start("m")
  run(host, 0.5)
  t.truthy(host:objectiveInfo().text:find("4 left"))
  w.actors[1].state = "down"
  run(host, 0.5)
  t.truthy(host:objectiveInfo().text:find("left"))
  w.actors[1].state = "down"
  run(host, 25)
  t.eq(host.failed.reason, "out of time")
  local h2, w2 = mission(function(api)
    api.step("d", function()
      api.actor("crew", "juno", { group = "g", count = 2 })
      api.defeat("g")
    end)
  end)
  h2:start("m")
  run(h2, 0.5)
  for _, a in ipairs(w2.actors) do a.state = "down" end
  run(h2, 0.5)
  t.eq(h2.state, "passed")
end)

t.test("kit: a hold counts only the seconds you are there, and says so when you are away", function()
  local host, w = mission(function(api)
    api.step("h", function() api.hold("ferry", 5, { away = "Get back!" }) end)
  end)
  host:start("m")
  run(host, 2)
  t.eq(host:objectiveInfo().text, "Get back!")
  local f = idx.places.ferry
  w.p.x, w.p.z = f.x, f.z
  run(host, 3)
  t.eq(host.state, "running", "3 seconds in")
  run(host, 3)
  t.eq(host.state, "passed")
end)

t.test("kit: a jump has to be landed far enough; a miss fails, a short hop tries again", function()
  local function jumping(info)
    local host, w = mission(function(api)
      api.step("j", function() api.jump({ min = 14 }) end)
    end)
    host:start("m")
    run(host, 0.5)
    w.flightInfo = info
    run(host, 0.5)
    return host, w
  end
  t.eq(jumping({ landed = true, distance = 20 }).state, "passed")
  local short, w = jumping({ landed = true, distance = 6 })
  t.eq(short.state, "running", "too short to count")
  t.eq(w.flightInfo, nil, "forgotten so the next try counts")
  t.eq(jumping({ landed = false, distance = 30 }).failed.reason, "you missed the landing")
end)

t.test("kit: loseHeat waits for the Patrol to give up, and a timeout fails it; heat only goes up", function()
  local host, w = mission(function(api)
    api.step("l", function()
      api.heat(3)
      api.heat(2)
      api.loseHeat("Lose them.", { timeout = 10 })
    end)
  end)
  host:start("m")
  run(host, 0.5)
  t.eq(w.level, 3)
  run(host, 12)
  t.eq(host.failed.reason, "the Patrol is still on you")
  local h2, w2 = mission(function(api)
    api.step("l", function()
      api.heat(3)
      api.loseHeat("Lose them.")
    end)
  end)
  h2:start("m")
  run(h2, 1)
  w2.level = 0
  run(h2, 1)
  t.eq(h2.state, "passed")
end)

t.test("kit: watch and guard fail the job for any rule a script gives; goTo is the drive on foot", function()
  local host, w = mission(function(api)
    api.step("w", function()
      api.actor("runner", "juno", { name = "friend", route = { "ferry" } })
      api.guard("friend", "your friend was hurt")
      api.watch(function() return api.var("bad") and "a custom rule broke" end)
      api.goTo("ferry", { text = "Walk to the ferry." })
    end)
  end)
  host:start("m")
  run(host, 0.5)
  t.truthy(host.actors.friend)
  host.actors.friend.state = "down"
  run(host, 0.5)
  t.eq(host.failed.reason, "your friend was hurt")
  host:retry("restart")
  run(host, 0.5)
  host.runner.vars.bad = true
  run(host, 0.5)
  t.eq(host.failed.reason, "a custom rule broke")
  host:retry("restart")
  run(host, 0.5)
  local f = idx.places.ferry
  w.p.x, w.p.z = f.x, f.z
  run(host, 1)
  t.eq(host.state, "passed", "on foot is enough for goTo")
end)

t.test("kit: the player going down fails the job with who did it; the clock does not matter", function()
  local host, w = mission(function(api)
    api.step("a", function() api.drive("ferry", {}) end)
  end)
  host:start("m")
  run(host, 0.5)
  w.p.down = "nabbed"
  run(host, 0.5)
  t.eq(host.failed.reason, "the Patrol nabbed you")
  host:retry("checkpoint")
  t.eq(w.p.down, false, "the retry stands you up")
  run(host, 0.5)
  w.p.down = "ko"
  run(host, 0.5)
  t.eq(host.failed.reason, "you were knocked out")
end)

-- ---------------------------------------------------------------- the host

t.test("host: a retry from the checkpoint skips the talk it already played but asks a choice it has no answer for", function()
  local asked = 0
  local host, w = mission(function(api)
    api.step("one", function()
      api.say("Wren", "intro line")
      local first = api.choose("First?", { "a", "b" })
      api.flag("first", first)
    end)
    api.step("two", function()
      api.say("Wren", "second step talk")
      api.choose("Second?", { "c", "d" })
      asked = asked + 1
      api.drive("ferry", {})
    end, { at = "juno" })
  end)
  host:start("m")
  local said = {}
  host.record = function(kind, a, b) if kind == "say" then said[#said + 1] = b end end
  local function press()
    if host.talk.line then
      local r = host.talk:advance()
      if r == "reveal" then host.talk:advance() end
    elseif host.talk.choice then
      host.talk:pick(2)
    end
  end
  run(host, 30, 0.1, press)
  t.eq(host.checkpointName, "two")
  w.p.down = "ko"
  run(host, 1)
  t.eq(host.state, "failed")
  said = {}
  host:retry("checkpoint")
  run(host, 3, 0.1, press)
  t.eq(#said, 0, "no talk repeated after the retry")
  t.eq(asked, 2, "the choice in the retried step was answered from memory, not asked again")
  t.eq(host.runner.flags.first, 2, "the flag from before is still there")
  -- a restart plays it all again
  w.p.down = "ko"
  run(host, 1)
  host:retry("restart")
  run(host, 3, 0.1, press)
  t.truthy(#said >= 1, "a restart replays the talk")
end)

t.test("host: the next job is offered at its giver, not before, and not for a while after giving up", function()
  local host, w = sim.newHost(idx)
  w.p.x, w.p.z = idx.places.ferry.x, idx.places.ferry.z
  host:update(0.1)
  t.eq(host.state, "idle", "not at Juno yet")
  w.p.x, w.p.z = idx.places.juno.x, idx.places.juno.z
  w.p.speed = 20
  host:update(0.1)
  t.eq(host.state, "idle", "driving past at speed does not start it")
  w.p.speed = 0
  host:update(0.1)
  t.eq(host.state, "running")
  t.eq(host.def.id, "fresh_air")
  host:giveUp()
  t.eq(host.state, "idle")
  host:update(0.1)
  t.eq(host.state, "idle", "a cool-down after giving up")
  host:update(30)
  host:update(0.1)
  t.eq(host.state, "running", "and again once it has passed")
end)

t.test("host: a save from today's game carries over; finished means Act 1 is done; jobs before one you did count as done", function()
  local story = { done = { gilded = true }, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} } }
  local host = sim.newHost(idx, { story = story })
  for _, id in ipairs({ "fresh_air", "hot_broth", "gulls", "pit_wall", "gilded" }) do
    t.truthy(story.done[id], id .. " counts as done")
  end
  t.truthy(not story.done.low_tide)
  t.eq(host:next().id, "static")
  t.truthy(story.phone.unlocked.rusty and story.phone.unlocked.tam, "the friends those jobs made are in the phone")
  -- today's finished story
  local fin = { done = { fresh_air = true, hot_broth = true, gulls = true, gilded = true, low_tide = true }, flags = { act1Done = true },
    tally = {}, phone = { unlocked = {}, texts = {} } }
  local h2 = sim.newHost(idx, { story = fin })
  t.eq(h2:next().id, "no_ferry", "the story goes on with Act 2")
  for _, def in ipairs(idx.missions) do
    if def.act == 1 then t.truthy(fin.done[def.id], def.id) end
  end
  -- the core's own migration puts act1Done in
  local saveLib = require("sg.core.save")
  local migrated = saveLib.migrate({ version = 1, money = 100, done = { "fresh_air", "hot_broth", "gulls", "gilded", "low_tide" }, finished = true })
  t.truthy(migrated.story.flags.act1Done)
  local h3 = sim.newHost(idx, { story = migrated.story })
  t.eq(h3:next().id, "no_ferry")
end)

t.test("host: the mission in the save resumes at its checkpoint and a finished mission's leftover is dropped", function()
  local story = { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} },
    mission = { id = "hot_broth", checkpoint = "run", flags = { x = 1 }, vars = {} } }
  local host = sim.newHost(idx, { story = story })
  host:bind(story)
  t.truthy(host:resume())
  t.eq(host.state, "running")
  host:update(0.1)
  t.eq(host.checkpointName, "run")
  t.eq(host.runner.flags.x, 1)
  local stale = { done = { hot_broth = true }, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} },
    mission = { id = "hot_broth", checkpoint = "run", flags = {}, vars = {} } }
  local h2 = sim.newHost(idx, { story = stale })
  t.truthy(not h2:resume())
  t.eq(stale.mission, nil)
  local bad = { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} }, mission = { id = "no_such_job" } }
  t.truthy(not sim.newHost(idx, { story = bad }):resume())
end)

t.test("host: a script that errors fails the job with a clear reason and logs it; the game goes on", function()
  local host = mission(function(api)
    api.step("a", function() error("boom") end)
  end)
  local logged
  host.log = function(m) logged = m end
  host:start("m")
  run(host, 0.5)
  t.eq(host.state, "failed")
  t.eq(host.failed.reason, "script error")
  t.truthy(logged and logged:find("boom"))
end)

t.test("host: music follows the job: its own cue, 'wasted' on failure, 'job_complete' on success, 'credits' after the last", function()
  local host, w = mission(function(api)
    api.step("a", function() api.music("heat_high") api.wait(1) end)
  end)
  host:start("m")
  run(host, 2)
  t.eq(host.cues[1], "job")
  t.eq(host.cues[2], "heat_high")
  t.eq(host.cues[#host.cues], "job_complete")
  local h2, w2 = mission(function(api) api.step("a", function() api.drive("ferry", {}) end) end)
  h2:start("m")
  run(h2, 0.5)
  w2.p.down = "ko"
  run(h2, 0.5)
  t.eq(h2.cues[#h2.cues], "wasted")
  h2:giveUp()
  t.eq(h2.cues[#h2.cues], "free_roam")
end)

t.test("host: events: mission_start once, checkpoint at each step, choice with its pick, mission_end with the result and reason", function()
  local host, w, bus = mission(function(api)
    api.step("one", function()
      api.choose("Which?", { "a", "b" })
    end)
    api.step("two", function() api.drive("ferry", {}) end)
  end)
  local seen = {}
  for _, name in ipairs({ "mission_start", "checkpoint", "choice", "mission_end" }) do
    bus:on(name, function(d) seen[#seen + 1] = { name, d } end, "t")
  end
  host:start("m")
  run(host, 30, 0.1, function()
    if host.talk.choice then host.talk:pick(2) end
  end)
  w.p.down = "ko"
  run(host, 1)
  local names = {}
  for _, e in ipairs(seen) do names[#names + 1] = e[1] end
  t.eq(table.concat(names, ","), "mission_start,checkpoint,choice,checkpoint,mission_end")
  t.eq(seen[3][2].pick, 2)
  t.eq(seen[5][2].result, "fail")
  t.eq(seen[5][2].reason, "you were knocked out")
end)

t.test("host: story memory: remember and recall, tallies, and ending are kept in the story table for good", function()
  local story = { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} } }
  local host, w = mission(function(api)
    api.step("a", function()
      api.remember("x", "yes")
      api.tally("juno", 2)
      api.tally("juno")
      api.ending("stay")
    end)
  end, { story = story })
  host:start("m")
  run(host, 1)
  t.eq(story.flags.x, "yes")
  t.eq(story.tally.juno, 3)
  t.eq(story.ending, "stay")
  t.truthy(story.finished)
  t.eq(host.cues[#host.cues], "job_complete", "credits only after the final mission passes")
end)

-- ---------------------------------------------------------------- the phone

t.test("phone: contacts appear when unlocked, unread counts, a call picks the newest line you have earned, Tam gives the hint", function()
  local story = { done = {}, flags = {}, tally = {}, phone = { unlocked = { juno = true, tam = true }, texts = {
    { from = "tam", text = "hi", read = false }, { from = "tam", text = "again", read = false }, { from = "juno", text = "hello", read = true } } } }
  local list = phoneLib.contacts(story, idx)
  t.eq(#list, 2)
  t.eq(list[1].id, "juno")
  t.eq(list[2].unread, 2)
  t.eq(phoneLib.unread(story), 2)
  t.eq(#phoneLib.thread(story, "tam"), 2)
  phoneLib.markRead(story, "tam")
  t.eq(phoneLib.unread(story), 0)
  local first = phoneLib.call(story, idx, "juno")
  t.eq(first[1][1], "Mama Juno")
  story.done.low_tide = true
  local later = phoneLib.call(story, idx, "juno")
  t.truthy(later[1][2] ~= first[1][2], "she says something different after Low Tide")
  story.done.riptide = true
  t.truthy(phoneLib.call(story, idx, "juno")[1][2]:find("Three days"), "and again after Riptide")
  t.eq(phoneLib.call(story, idx, "tam", "Brake early.")[1][2], "Brake early.")
  t.eq(phoneLib.call(story, idx, "nobody")[1][2], "No answer.")
end)

t.test("phone: every text a mission sends comes from a contact, and every contact has a call for the start of the story", function()
  for id, c in pairs(idx.phone.contacts) do
    local fallback = false
    for _, call in ipairs(c.calls) do
      if not call.after then fallback = true end
    end
    t.truthy(fallback, id .. " has a call for before anything has happened")
  end
  for _, id in ipairs(idx.phone.order) do t.truthy(idx.phone.contacts[id], id .. " is in the book") end
end)
