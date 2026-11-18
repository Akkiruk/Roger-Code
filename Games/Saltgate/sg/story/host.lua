-- story/host.lua
-- The story's mission manager: starts the next mission when you reach its giver, runs the script (core/script.lua) with
-- the hooks the script needs, keeps the checkpoint, the timer, the failure rules and the dialogue, and saves where you
-- are. It never touches the game directly: everything goes through a world adapter (see sg/story/world.lua for what one
-- has to do), so the same host runs in the game and in the tests against a made-up world.
--
--   local host = hostLib.new({ bus, world, list, script = function(id) -> fn, music = function(cue), log })
--   host:bind(storyTable)            the save's `story` section (done, flags, mission, phone ...)
--   host:update(dt)                  once a frame while playing (not while a modal screen is up)
--   host:start(id [, state])         begin a mission (state: a checkpoint to resume)
--   host.state                       "idle" | "running" | "failed" | "passed"
--   host:retry("checkpoint" | "restart")   after a failure          host:giveUp()
--   host:export()                    write the running mission's checkpoint into the story section
--   host:objectiveInfo()             what the HUD shows

local scriptLib = require("sg.core.script")
local talkLib = require("sg.story.talk")
local cutsceneLib = require("sg.story.cutscene")
local kitLib = require("sg.story.kit")

local M = {}
local H = {}
H.__index = H

M.GIVER_RADIUS = 6 -- how close you have to be to a giver (on foot or in a car) to be offered the job
M.COOLDOWN = 25 -- seconds after giving up before the same giver speaks to you again

function M.new(opts)
  local h = setmetatable({
    bus = opts.bus,
    world = opts.world,
    list = opts.list,
    loadScript = opts.script,
    musicCue = opts.music or function() end,
    log = opts.log or function() end,
    talk = talkLib.new(),
    state = "idle",
    story = nil,
    actors = {},
    stepOpts = {},
    watches = {},
    timer = nil,
    cool = 0,
    fast = false,
    cut = nil,
    cutDone = true,
    objective = nil,
    hint = nil,
    cards = {}, -- title cards and toasts waiting to show: { kind, text, sub }
    onPhone = opts.onPhone, -- function(from, text) when a text arrives
    onSave = opts.onSave, -- function() when a checkpoint or an end is a good moment to write the save
  }, H)
  return h
end

-- ---------------------------------------------------------------- the save

local function blankStory(s)
  s.done = s.done or {}
  s.flags = s.flags or {}
  s.tally = s.tally or {}
  s.phone = s.phone or {}
  s.phone.unlocked = s.phone.unlocked or {}
  s.phone.texts = s.phone.texts or {}
  return s
end

--- Use story (the save's story section) from now on.
function H:bind(story)
  self.story = blankStory(story)
  self:settleOldSaves()
end

--- A mission is done if one that comes after it in the list is (a save from before it existed), and a story finished
-- in today's game counts Act 1 as done.
function H:settleOldSaves()
  local s, list = self.story, self.list
  if s.flags.act1Done then
    for _, def in ipairs(list.missions) do
      if def.act == 1 then self:markDone(def, true) end
    end
  end
  local last = 0
  for i, def in ipairs(list.missions) do
    if s.done[def.id] then last = i end
  end
  for i = 1, last - 1 do self:markDone(list.missions[i], true) end
end

function H:markDone(def, quiet)
  local s = self.story
  if s.done[def.id] then return end
  s.done[def.id] = true
  for _, who in ipairs(def.unlocks or {}) do s.phone.unlocked[who] = true end
  if def.id == self.list.actEnd[1] then s.flags.act1Done = true end
  if def.id == self.list.actEnd[2] then s.flags.act2Done = true end
  if not quiet then self.log("story: " .. def.id .. " done") end
end

--- The next mission not yet done, or nil.
function H:next()
  for _, def in ipairs(self.list.missions) do
    if not self.story.done[def.id] then return def end
  end
  return nil
end

--- Put the running mission's checkpoint into the story section (the save event calls it).
function H:export()
  local s = self.story
  if not s then return end
  if self.state == "running" and self.runner then
    s.mission = self.runner:saveState()
  elseif self.state == "failed" and self.failed then
    s.mission = { id = self.def.id, checkpoint = self.failed.checkpoint, flags = self.runner.flags, vars = self.runner.vars }
  else
    s.mission = nil
  end
end

-- ---------------------------------------------------------------- starting and ending

function H:clearWorld()
  self.world:cleanup()
  self.actors = {}
  self.watches = {}
  self.timer = nil
  self.goal = nil
  self.objective = nil
  self.cut, self.cutDone = nil, true
  self.talk:clear()
  self.holdNote = nil
end

function H:emit(name, data)
  if self.bus then self.bus:emit(name, data) end
end

--- Begin mission id. state: { checkpoint, flags, vars } to resume from a save.
function H:start(id, state)
  local def = self.list.byId[id]
  if not def then return false, "no mission " .. tostring(id) end
  local fn, err = self.loadScript(id)
  if not fn then
    self.log("story: " .. tostring(err))
    return false, err
  end
  self:clearWorld()
  self.def = def
  self.fn = fn
  self.stepOpts = {}
  self.retries = 0
  self.failed = nil
  self.state = "running"
  self.restoring = state ~= nil and state.checkpoint ~= nil
  self.fast = false -- a load plays the step's talk again (a retry after a failure skips it)
  self:makeRunner(state)
  self.story.mission = nil
  self:emit("mission_start", { id = id })
  self:music(def.music or "job")
  return true
end

--- Pick up a mission the save was in the middle of. Returns true if there was one.
function H:resume()
  local m = self.story and self.story.mission
  if type(m) ~= "table" or not m.id or not self.list.byId[m.id] then return false end
  if self.story.done[m.id] then
    self.story.mission = nil
    return false
  end
  local state = { checkpoint = m.checkpoint, flags = m.flags or {}, vars = m.vars or {} }
  return self:start(m.id, state)
end

function H:makeRunner(state)
  local host = self
  local hooks = {
    say = function(who, text)
      if host.record then host.record("say", who, text) end
      host.talk:say(who, text)
    end,
    talking = function() return host.talk:talking() end,
    choose = function(prompt, options)
      if host.record then host.record("choose", prompt, options) end
      host.talk:choose(prompt, options)
    end,
    chosen = function() return host.talk:chosen() end,
    objective = function(text, target)
      if host.record then host.record("objective", text, target) end
      host.objective = { text = text, target = target }
    end,
    at = function(place, opts) return host.world:inPlace(place, opts or {}) end,
    spawn = function(kind, at, opts) return host:spawn(kind, at, opts) end,
    cutscene = function(shots) host:playCutscene(shots) end,
    cutsceneDone = function() return host.cutDone end,
    setHeat = function(n) host.world:setHeat(n) end,
    reward = function(n) host.world:pay(n) end,
    emit = function(name, data)
      if name == "checkpoint" then host:stepStarted(data.name) end
      host:emit(name, data)
    end,
  }
  self.hooks = hooks
  local fn = self.fn
  self.runner = scriptLib.new(self.def.id, function(api)
    fn(kitLib.extend(api, host))
  end, hooks, state)
end

function H:spawn(kind, at, opts)
  opts = opts or {}
  local actor = self.world:spawn(kind, at, opts)
  if actor and opts.name then self.actors[opts.name] = actor end
  return actor
end

--- A step has begun: a save point, and (after a retry or a load) the player is put where the step starts.
function H:stepStarted(name)
  self.goal = nil
  self.watches = {}
  self.timer = nil
  self.hint = nil
  self.holdNote = nil
  self.checkpointName = name
  local so = self.stepOpts[name]
  if self.restoring then
    self.restoring = false
    self.world:cleanup()
    self.actors = {}
    if so then
      local given = self.world:restore(so)
      if given and so.give and so.give.name then self.actors[so.give.name] = given end
    end
    self.world:setHeat(0, true)
  end
  self:export()
  if self.onSave then self.onSave() end
end

function H:failNow(reason)
  local r = self.runner
  if r and r.status == "running" then
    r.status, r.reason = "fail", reason or "failed"
  end
end

function H:playCutscene(shots)
  if self.fast then
    self.cutDone = true
    return
  end
  if self.record then self.record("cutscene", shots) end
  if not cutsceneLib.validate(shots) then
    self.cutDone = true
    return
  end
  local world = self.world
  self.cut = cutsceneLib.new(shots, function(spec) return world:camAt(spec) end)
  self.cutDone = false
end

function H:music(cue)
  self.musicWanted = cue
  self.musicCue(cue)
end

-- ---------------------------------------------------------------- phone and cards

function H:phoneText(from, text)
  if self.record then self.record("text", from, text) end
  local s = self.story
  s.phone.unlocked[from] = true
  s.phone.texts[#s.phone.texts + 1] = { from = from, text = text, read = false, mission = self.def and self.def.id }
  while #s.phone.texts > 60 do table.remove(s.phone.texts, 1) end
  self.cards[#self.cards + 1] = { kind = "text", text = text, sub = from }
  if self.onPhone then self.onPhone(from, text) end
end

function H:unlock(who)
  self.story.phone.unlocked[who] = true
end

function H:card(kind, text, sub)
  self.cards[#self.cards + 1] = { kind = kind, text = text, sub = sub }
end

-- ---------------------------------------------------------------- each frame

--- Offer the next mission when the player reaches its giver.
function H:offer(dt)
  if self.cool > 0 then
    self.cool = self.cool - dt
    return
  end
  local def = self:next()
  if not def or not def.giver then return end
  local p = self.world:player()
  if not p or p.down then return end
  if self.world:inPlace(def.giver, { speed = 9 }) then
    self:start(def.id)
  end
end

function H:finish()
  local def = self.def
  self.state = "passed"
  self:clearWorld()
  self.story.mission = nil
  self:markDone(def)
  if def.reward and def.reward > 0 then self.world:pay(def.reward) end
  self:emit("mission_end", { id = def.id, result = "pass" })
  self:card("pass", def.title, def.reward and ("$" .. def.reward) or nil)
  self:music(def.final and "credits" or "job_complete")
  if self.onSave then self.onSave() end
end

function H:fail(reason)
  local def = self.def
  self.state = "failed"
  self.failed = { reason = reason, checkpoint = self.checkpointName }
  self.world:suspend()
  self.talk:clear()
  self.cut, self.cutDone = nil, true
  self.timer = nil
  self:export()
  self:emit("mission_end", { id = def.id, result = "fail", reason = reason })
  self:music("wasted")
end

--- After a failure: "checkpoint" goes back to the step the player was on, "restart" to the first.
function H:retry(mode)
  if self.state ~= "failed" then return false end
  local def = self.def
  local cp = self.failed and self.failed.checkpoint
  if mode == "restart" then cp = nil end
  self.retries = (self.retries or 0) + 1
  local state = nil
  if cp then
    local old = self.runner
    state = { checkpoint = cp, flags = old.flags, vars = old.vars }
  end
  self.state = "running"
  self.failed = nil
  self:clearWorld()
  self.restoring = cp ~= nil
  self.fast = cp ~= nil
  self.world:resume()
  self.world:setHeat(0, true)
  if not cp then self.world:restore({ at = def.giver }) end
  self:makeRunner(state)
  self:emit("mission_start", { id = def.id })
  self:music(def.music or "job")
  return true
end

function H:giveUp()
  if self.state ~= "failed" and self.state ~= "running" then return end
  self.state = "idle"
  self.failed = nil
  self:clearWorld()
  self.world:resume()
  self.story.mission = nil
  self.cool = M.COOLDOWN
  self:music("free_roam")
  if self.onSave then self.onSave() end
end

--- Close the "passed" state once the card has been shown.
function H:acknowledge()
  if self.state == "passed" then
    self.state = "idle"
    self.cool = 4
    self:music("free_roam")
  end
end

--- The talk and the cutscene move on (the modal screens call this; update does too).
function H:tickUI(dt)
  self.talk:update(dt)
  local cut = self.cut
  if cut then
    cut:update(dt)
    if cut.done then self.cut, self.cutDone = nil, true end
  end
end

function H:update(dt)
  if self.state == "idle" then
    if self.story then self:offer(dt) end
    return
  end
  if self.state ~= "running" then return end
  self:tickUI(dt)
  local frozen = self.talk:talking() or self.cut ~= nil
  if not frozen then self:checkWatches(dt) end
  local r = self.runner
  if r.status == "running" then
    local ok, err = pcall(r.update, r, frozen and 0 or dt)
    if not ok then
      self.log("story: " .. tostring(err))
      self:failNow("script error")
    end
  end
  -- a fast pass (after a retry or a load) ends as soon as the script waits on the game
  if self.fast and self.goal then self.fast = false end
  if r.status == "pass" then
    self:finish()
  elseif r.status == "fail" then
    self:fail(r.reason)
  end
end

function H:checkWatches(dt)
  local t = self.timer
  if t and not t.paused then
    t.left = t.left - dt
    if t.left <= 0 then
      self.timer = nil
      self:failNow(t.reason or "out of time")
      return
    end
  end
  for _, w in ipairs(self.watches) do
    local reason = w.fn()
    if reason then
      self:failNow(type(reason) == "string" and reason or w.reason)
      return
    end
  end
  local p = self.world:player()
  if p and p.down then
    self:failNow(p.down == "nabbed" and "the Patrol nabbed you" or "you were knocked out")
  end
end

-- ---------------------------------------------------------------- what the screens read

--- { text, target, timer, timerText, hint } for the HUD, or nil.
function H:objectiveInfo()
  if self.state ~= "running" or not self.objective then return nil end
  local t = self.timer
  return { text = self.holdNote or self.objective.text, target = self.objective.target, timer = t and t.left,
    timerText = t and t.text, hint = self.hint }
end

return M
