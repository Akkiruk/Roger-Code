-- core/script.lua
-- Running a mission script: a coroutine with a small, safe API. A script is a list of named steps; each step starts a
-- checkpoint, so a save made in the middle of a mission comes back at the step it was in, with the flags it had.
-- Pure: everything it does to the game goes through the hooks it is given.
--
-- A mission file (content/story/<id>.lua):
--   return function(api)
--     api.step("meet", function()
--       api.say("Mama Juno", "There you are.")
--       local pick = api.choose("How do you answer?", { "Cool", "Late again" })
--       api.flag("rude", pick == 2)
--     end)
--     api.step("drive", function()
--       api.goTo("ferry", { car = true, text = "Get to the ferry." })
--     end)
--     api.step("pay", function() api.reward(500) end)
--   end
--
-- The api (every call that waits yields; the runner resumes it when the wait is over):
--   step(name, fn)                 a checkpoint and the work after it
--   say(who, text)                 a line of talk; waits until it is read
--   choose(prompt, options)        options are strings; waits; returns the index picked
--   objective(text, target)        what the HUD says to do; target { x, z } or a place name, or nil
--   waitUntil(fn, timeout)         waits until fn() is true; returns false on timeout (seconds)
--   wait(seconds)
--   goTo(place, opts)              objective + wait until there (opts.car: in a vehicle; opts.radius; opts.text;
--                                  opts.timeout: fails the mission when the clock runs out)
--   spawn(kind, at, opts)          returns what the game made (at: a place name or { x, z })
--   cutscene(shots)                waits until it has played (or been skipped)
--   setHeat(level)  reward(money)  flag(name [, value]) -> value  var(name [, value]) -> value
--   fail(reason)                   ends the mission as failed
--   time()                         seconds since the mission started (this run)
--
-- Hooks (given by the game): say(who, text), talking() -> bool, choose(prompt, options), chosen() -> index or nil,
-- objective(text, target), at(place, opts) -> bool, spawn(kind, at, opts), cutscene(shots), cutsceneDone() -> bool,
-- setHeat(level), reward(money), emit(name, data) (optional).

local M = {}
local R = {}
R.__index = R

local FAIL = {}

--- A runner for one mission. state: what a save kept ({ checkpoint, flags, vars }), or nil for a fresh start.
function M.new(id, fn, hooks, state)
  state = state or {}
  local r = setmetatable({
    id = id,
    fn = fn,
    hooks = hooks,
    checkpoint = state.checkpoint,
    flags = state.flags or {},
    vars = state.vars or {},
    status = "running", -- "running" | "pass" | "fail"
    reason = nil,
    clock = 0,
    wait = nil, -- function() -> done
  }, R)
  r.api = r:makeApi()
  r.co = coroutine.create(function()
    r.fn(r.api)
  end)
  return r
end

function R:makeApi()
  local r = self
  local hooks = self.hooks
  local api = {}
  local skipping = self.checkpoint ~= nil

  local function waitFor(done)
    r.wait = done
    coroutine.yield()
  end

  function api.step(name, fn)
    if skipping then
      if name ~= r.checkpoint then return end
      skipping = false
    end
    r.checkpoint = name
    if hooks.emit then hooks.emit("checkpoint", { id = r.id, name = name }) end
    fn()
  end
  function api.say(who, text)
    hooks.say(who, text)
    waitFor(function() return not hooks.talking() end)
  end
  function api.choose(prompt, options)
    hooks.choose(prompt, options)
    local pick
    waitFor(function()
      pick = hooks.chosen()
      return pick ~= nil
    end)
    if hooks.emit then hooks.emit("choice", { id = r.id, key = prompt, pick = pick }) end
    return pick
  end
  function api.objective(text, target)
    hooks.objective(text, target)
  end
  function api.waitUntil(fn, timeout)
    local start = r.clock
    local ok = false
    waitFor(function()
      if fn() then
        ok = true
        return true
      end
      return timeout ~= nil and r.clock - start >= timeout
    end)
    return ok
  end
  function api.wait(seconds)
    local start = r.clock
    waitFor(function() return r.clock - start >= seconds end)
  end
  function api.goTo(place, opts)
    opts = opts or {}
    hooks.objective(opts.text or ("Go to " .. tostring(place)), place)
    local ok = api.waitUntil(function() return hooks.at(place, opts) end, opts.timeout)
    if not ok then api.fail(opts.failText or "out of time") end
    return true
  end
  function api.spawn(kind, at, opts)
    return hooks.spawn(kind, at, opts or {})
  end
  function api.cutscene(shots)
    hooks.cutscene(shots)
    waitFor(function() return hooks.cutsceneDone() end)
  end
  function api.setHeat(level) hooks.setHeat(level) end
  function api.reward(money) hooks.reward(money) end
  function api.flag(name, value)
    if value ~= nil then r.flags[name] = value end
    return r.flags[name]
  end
  function api.var(name, value)
    if value ~= nil then r.vars[name] = value end
    return r.vars[name]
  end
  function api.fail(reason)
    r.status, r.reason = "fail", reason
    error(FAIL, 0)
  end
  function api.time() return r.clock end
  return api
end

--- Advance dt seconds: resume the script if what it waits for is done. Returns the status.
function R:update(dt)
  if self.status ~= "running" then return self.status end
  self.clock = self.clock + (dt or 0)
  if self.wait and not self.wait() then return self.status end
  self.wait = nil
  local ok, err = coroutine.resume(self.co)
  if not ok then
    if err == FAIL then return self.status end
    self.status, self.reason = "fail", "script error"
    error("mission " .. tostring(self.id) .. ": " .. tostring(err), 0)
  end
  if coroutine.status(self.co) == "dead" and self.status == "running" then self.status = "pass" end
  return self.status
end

--- What a save keeps of this mission.
function R:saveState()
  return { id = self.id, checkpoint = self.checkpoint, flags = self.flags, vars = self.vars }
end

return M
