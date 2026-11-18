-- saltgate_d_story_test.lua
-- SALTGATE's story (stream D): every mission plays start to finish by script, every choice path of every mission
-- finishes, every mission can be failed and retried from its checkpoint, a save made at any checkpoint comes back at it,
-- every line fits 51 columns, and the whole story reaches each of its three endings.

local t = require("testing")
local sim = require("saltgate_d_sim")
local text = require("sg.story.text")
local cutscene = require("sg.story.cutscene")

local idx = sim.index()
local only = rawget(_G, "STORY_ONLY")

local function eachMission(fn)
  for _, def in ipairs(idx.missions) do
    if not only or only[def.id] then fn(def) end
  end
end

--- A host that has finished everything before def (so its flags and tallies are the story's), playing def.
local function hostAt(def, story)
  local host, w = sim.newHost(idx, { story = story })
  host:start(def.id)
  return host, w
end

local function fresh() return { done = {}, flags = {}, tally = {}, phone = { unlocked = {}, texts = {} } } end

--- Play the whole story in order with one policy for choices; returns the story table and the last host.
local function playStory(pick)
  local story = fresh()
  local host, w
  for _, def in ipairs(idx.missions) do
    host, w = sim.newHost(idx, { story = story })
    local ok, err = host:start(def.id)
    t.truthy(ok, def.id .. " starts: " .. tostring(err))
    local state, seen = sim.play(host, w, { rng = pick })
    t.eq(state, "passed", def.id .. " ends")
    host:acknowledge()
    local _ = seen
  end
  return story
end

-- ---------------------------------------------------------------- the content

t.test("story content: 24 or more missions in three acts, each with a script, a giver and a reward", function()
  t.truthy(#idx.missions >= 24, "24+ missions, have " .. #idx.missions)
  local acts, seen = {}, {}
  for _, def in ipairs(idx.missions) do
    t.truthy(not seen[def.id], "unique id " .. def.id)
    seen[def.id] = true
    acts[def.act] = (acts[def.act] or 0) + 1
    t.truthy(idx.places[def.giver], def.id .. " giver place " .. tostring(def.giver))
    t.truthy(type(def.reward) == "number" and def.reward > 0, def.id .. " reward")
    t.truthy(text.fits(def.title, text.TITLE, 1), def.id .. " title fits")
    t.truthy(text.fits(def.summary, text.SCREEN - 4, 2), def.id .. " summary fits")
    local fn, err = idx.script(def.id)
    t.truthy(fn, def.id .. " script: " .. tostring(err))
    for _, who in ipairs(def.unlocks or {}) do
      t.truthy(idx.phone.contacts[who], def.id .. " unlocks a contact that exists: " .. who)
    end
  end
  t.eq(#idx.acts, 3)
  t.truthy(acts[1] >= 5 and acts[2] >= 8 and acts[3] >= 8, "each act is a full act")
  t.eq(idx.missions[#idx.missions].id, "king_tide")
  t.truthy(idx.missions[#idx.missions].final)
  -- today's five jobs keep their ids and order, so a save from today's game carries over
  local old = { "fresh_air", "hot_broth", "gulls", "gilded", "low_tide" }
  local at = 0
  for _, id in ipairs(old) do
    local def = idx.byId[id]
    t.truthy(def and def.index > at, "today's job " .. id .. " keeps its place in the order")
    at = def.index
  end
  t.eq(idx.actEnd[1], "low_tide")
end)

t.test("story content: every place a mission names exists, every cast member has a colour that is a colour", function()
  local colours = { white = 1, orange = 1, magenta = 1, lightBlue = 1, yellow = 1, lime = 1, pink = 1, gray = 1, lightGray = 1,
    cyan = 1, purple = 1, blue = 1, brown = 1, green = 1, red = 1, black = 1 }
  for name, c in pairs(idx.cast) do
    t.truthy(colours[c.colour], name .. " has a real colour")
    t.truthy(#name <= 14, name .. " fits the name plate")
  end
  for name, p in pairs(idx.places) do
    t.truthy(type(p.x) == "number" and type(p.z) == "number" and p.r > 0, name .. " has a position")
    t.truthy(p.district, name .. " has a district")
    t.truthy(#p.label <= 36, name .. " label fits")
  end
  for id, c in pairs(idx.phone.contacts) do
    t.truthy(idx.cast[c.name] or idx.cast[id], id .. " is in the cast")
    for _, call in ipairs(c.calls) do
      for _, l in ipairs(call.say) do
        t.truthy(idx.cast[l[1]], id .. " call speaker " .. l[1])
        t.truthy(text.fits(l[2], text.TEXT, text.ROWS), id .. " call line fits: " .. l[2])
      end
      t.truthy(not call.after or idx.byId[call.after], id .. " call after a real mission")
    end
  end
end)

-- ---------------------------------------------------------------- every mission, start to finish

t.test("story: every mission plays start to finish with the first choice every time", function()
  eachMission(function(def)
    local story = fresh()
    local host, w = hostAt(def, story)
    local state, seen = sim.play(host, w, {})
    t.eq(state, "passed", def.id .. " passes (" .. tostring(host.failed and host.failed.reason) .. ")")
    t.truthy(story.done[def.id], def.id .. " is marked done")
    t.truthy(w.money >= def.reward, def.id .. " pays")
    t.truthy(#seen.says >= 4, def.id .. " has talk")
    local started, ended = false, false
    for _, e in ipairs(host.events) do
      if e[1] == "mission_start" and e[2].id == def.id then started = true end
      if e[1] == "mission_end" and e[2].id == def.id and e[2].result == "pass" then ended = true end
    end
    t.truthy(started and ended, def.id .. " sends mission_start and mission_end")
    t.truthy(host.cues[1] ~= nil, def.id .. " cues music")
  end)
end)

t.test("story: every line fits 51 columns (talk, choices, objectives, texts, cutscenes)", function()
  local bad, said = {}, {}
  local function check(ok, msg)
    if not ok and not said[msg] and #bad < 40 then
      said[msg] = true
      bad[#bad + 1] = msg
    end
  end
  eachMission(function(def)
    -- try the first, middle and last answer everywhere
    for _, pickMode in ipairs({ 1, 2, 3, 9 }) do
      local host, w = hostAt(def, fresh())
      local state, seen = sim.play(host, w, { rng = function(n) return math.min(pickMode, n) end })
      t.eq(state, "passed", def.id)
      for _, s in ipairs(seen.says) do
        check(idx.cast[s[1]], def.id .. ": '" .. tostring(s[1]) .. "' is not in the cast")
        check(text.fits(s[2], text.TEXT, text.ROWS), def.id .. ": line does not fit: " .. s[2])
      end
      local prompts = {}
      for _, c in ipairs(seen.choices) do
        check(text.fits(c[1], text.TEXT, 2), def.id .. ": prompt does not fit: " .. c[1])
        check(not prompts[c[1]], def.id .. ": the same prompt twice: " .. c[1])
        prompts[c[1]] = true
        check(#c[2] >= 2 and #c[2] <= 4, def.id .. ": 2-4 options: " .. c[1])
        for _, o in ipairs(c[2]) do
          check(#o <= text.OPTION, def.id .. ": option too long: " .. o)
        end
      end
      for _, o in ipairs(seen.objectives) do
        check(#o <= text.OBJECTIVE, def.id .. ": objective too long: " .. o)
      end
      for _, m in ipairs(seen.texts) do
        check(idx.phone.contacts[m[1]], def.id .. ": text from a contact: " .. m[1])
        check(text.fits(m[2], 44, 3), def.id .. ": text too long: " .. m[2])
      end
      for _, shots in ipairs(seen.cutscenes) do
        local ok, err = cutscene.validate(shots)
        check(ok, def.id .. ": cutscene: " .. tostring(err))
      end
    end
  end)
  t.eq(table.concat(bad, " ## "), "", "lines that do not fit")
end)

-- ---------------------------------------------------------------- choices

--- Every combination of answers a mission can be played with, by walking the tree of choices.
local function allPaths(def, limit)
  local paths, count = {}, 0
  local stack = { {} }
  while #stack > 0 and count < limit do
    local picks = table.remove(stack)
    local host, w = hostAt(def, fresh())
    local state, seen = sim.play(host, w, { picks = picks })
    t.eq(state, "passed", def.id .. " with answers " .. table.concat(picks, ","))
    count = count + 1
    local made = seen.picked or {}
    -- the choices beyond the ones we fixed: branch on each alternative
    for i = #picks + 1, #made do
      for alt = 2, made[i][1] do
        local np = {}
        for j = 1, i - 1 do np[j] = made[j][2] end
        np[i] = alt
        stack[#stack + 1] = np
      end
    end
    t.breathe()
  end
  return count
end

t.test("story: every choice path of every mission finishes", function()
  local total, branching = 0, 0
  eachMission(function(def)
    local n = allPaths(def, 400)
    t.truthy(n >= 1, def.id)
    total = total + n
    if n > 1 then branching = branching + 1 end
  end)
  if not only then
    t.truthy(branching >= 24, "choices branch in every mission (" .. branching .. ")")
    t.truthy(total >= 200, "many paths were played (" .. total .. ")")
  end
end)

-- ---------------------------------------------------------------- failing, retrying, saving

t.test("story: every mission can be failed at every step and retried from its checkpoint", function()
  local failedRuns, steps = 0, 0
  eachMission(function(def)
    -- find this mission's checkpoints from a clean run
    local host, w = hostAt(def, fresh())
    local state, seen = sim.play(host, w, {})
    t.eq(state, "passed", def.id)
    local names = {}
    for name in pairs(seen.checkpoints) do names[#names + 1] = name end
    table.sort(names)
    t.truthy(#names >= 1, def.id .. " has steps")
    for _, name in ipairs(names) do
      local h2, w2 = hostAt(def, fresh())
      local st = sim.play(h2, w2, { failAt = name, stopAt = nil, maxTicks = 3000, spoilOnly = true })
      -- spoiled at `name` only if it ever waits on the game there; a step that only talks cannot fail
      steps = steps + 1
      if h2.state == "failed" then
        failedRuns = failedRuns + 1
        t.eq(h2.failed.checkpoint, name, def.id .. " fails in " .. name)
        t.truthy(h2.failed.reason and #h2.failed.reason > 0, def.id .. " has a reason")
        t.truthy(w2.suspended, "the world waits on the failure screen")
        t.truthy(h2:retry("checkpoint"), "retry")
        local st2 = sim.play(h2, w2, {})
        t.eq(st2, "passed", def.id .. " passes after a retry from " .. name)
        t.truthy(w2.restored and w2.restored >= 1, def.id .. " put the player back")
        -- and the other way: a restart
        local h3, w3 = hostAt(def, fresh())
        sim.play(h3, w3, { failAt = name })
        if h3.state == "failed" then
          t.truthy(h3:retry("restart"))
          t.eq(sim.play(h3, w3, {}), "passed", def.id .. " passes after a restart")
        end
      else
        t.eq(st, "passed", def.id .. " ran on")
      end
    end
  end)
  if not only then t.truthy(failedRuns >= 80, "failed and retried at " .. failedRuns .. " of " .. steps .. " steps") end
end)

t.test("story: a save made at any checkpoint resumes there, with its flags, and finishes", function()
  local resumed = 0
  eachMission(function(def)
    local host, w = hostAt(def, fresh())
    local _, seen = sim.play(host, w, {})
    local names = {}
    for name in pairs(seen.checkpoints) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local story = fresh()
      local h1, w1 = hostAt(def, story)
      local st = sim.play(h1, w1, { stopAt = name })
      if st == "stopped" then
        h1:export()
        local saved = story.mission
        t.truthy(saved and saved.checkpoint == name, def.id .. " saved at " .. name)
        -- a new session: load the same story table
        local h2, w2 = sim.newHost(idx, { story = story })
        t.truthy(h2:resume(), def.id .. " resumes")
        t.eq(h2.state, "running")
        local st2 = sim.play(h2, w2, {})
        resumed = resumed + 1
        t.eq(st2, "passed", def.id .. " finishes after loading at " .. name)
        t.truthy(story.done[def.id])
        t.truthy(story.mission == nil, "the checkpoint is cleared when the job is done")
      end
    end
  end)
  if not only then t.truthy(resumed >= 100, "resumed " .. resumed .. " saves") end
end)

-- ---------------------------------------------------------------- the endings

t.test("story: the whole story, start to ending, with answers all first, all last and at random", function()
  local policies = {
    function() return 1 end,
    function(n) return n end,
    function(n) return 2 > n and n or 2 end,
  }
  local endings = {}
  for _, pick in ipairs(policies) do
    local story = playStory(pick)
    t.truthy(story.finished, "the story is finished")
    t.truthy(story.ending, "an ending was reached")
    endings[story.ending] = true
    t.truthy(story.flags.act1Done and story.flags.act2Done, "both acts closed")
  end
  local seed = 7
  for round = 1, 12 do
    local state = seed + round * 31
    local story = playStory(function(n)
      state = (state * 1103515245 + 12345) % 2147483648
      return (math.floor(state / 65536) % n) + 1
    end)
    t.truthy(story.ending == "leave" or story.ending == "stay" or story.ending == "crown", "a known ending: " .. tostring(story.ending))
    endings[story.ending] = true
    t.breathe()
  end
  t.truthy(endings.leave and endings.stay and endings.crown, "all three endings can be reached")
end)
