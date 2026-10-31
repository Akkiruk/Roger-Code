-- demo.lua
-- The idle screen's show: a real round played through a game's real rules and view, with nobody at the table.
-- A demo has nothing to do with a live round. It gets its own random source from a fresh seed, and a keep made new for each
-- round and thrown away after it, so it can never see or touch the table's keep, and a live shoe stays exactly as it was. It
-- never calls rules.finish, and it has no wallet, journal, stats or hub to reach: everything it knows is in this object. Its
-- view gets a context of its own too, because some views write to theirs. It plays no sound.
--
-- A game can steer its demo with game.demo (optional), or turn it off with game.demo = false:
--   wager(stream) -> the wager, for a game whose wager is not a plain number. 100 otherwise.
--   action(state, stream) -> an action id, where rules.auto would make a poor show, such as Baccarat's, which cancels.
-- Anything else that plays a hand, such as PokerTable, passes a script of its own to M.new. See M.forGame for the shape.

local rng = require("lib.casino.rng")

local M = {}
local Demo = {}
Demo.__index = Demo

local THINK_SECONDS = 1.2    -- a pause between decisions, so a demo looks played
local HOLD_SECONDS = 4       -- the result stays up this long
local MAX_STEPS = 40         -- a round this long is dropped, in case a game's auto can go round for ever

--- A demo over a script: start(stream) -> state, events; act(state, stream) -> events; done(state); event(model, ev) -> seconds;
-- commit(model, ev); model() -> a new view model; sync(model, state).
function M.new(script)
  return setmetatable({ script = script, rounds = 0 }, Demo)
end

--- The script for a table game. ctx is the demo's own context, with its canvas in ctx.c.
function M.forGame(game, ctx)
  local rules, view = game.rules, game.view
  local steer = game.demo or {}
  return {
    start = function(stream)
      local wager = steer.wager and steer.wager(stream) or 100
      return rules.new(wager, stream, {}, { pot = ctx.jackpot })
    end,
    act = function(state, stream)
      local id = steer.action and steer.action(state, stream) or rules.auto(state)
      return rules.act(state, id, stream)
    end,
    done = rules.done,
    model = function() return view.new(ctx) end,
    sync = view.sync,
    event = view.event,
    commit = view.commit,
  }
end

--- A game.demo action: any move on offer, for a game where any of them makes a fair show.
function M.anyAction(rules)
  return function(state, stream)
    local list = rules.actions(state)
    return list[stream:below(#list) + 1].id
  end
end

function Demo:start()
  local script = self.script
  self.stream = rng.new(rng.freshSeed("demo"))
  self.state, self.queue = script.start(self.stream)
  self.queue = self.queue or {}
  self.model = script.model()
  script.sync(self.model, self.state)
  self.playing, self.steps = nil, 0
  self.think, self.hold = THINK_SECONDS, nil
  self.rounds = self.rounds + 1
end

--- The current round is over and the wall has shown all of it.
function Demo:finished()
  return self.hold ~= nil
end

--- Move the show on by dt seconds.
function Demo:tick(dt)
  if not self.state then self:start() end
  local script = self.script
  if self.playing then
    self.playing.t = self.playing.t + dt / self.playing.duration
    if self.playing.t >= 1 then
      script.commit(self.model, self.playing.ev)
      self.playing = nil
    end
  end
  if self.playing then return end
  local ev = table.remove(self.queue, 1)
  if ev then
    local seconds = script.event(self.model, ev)
    self.playing = { ev = ev, t = 0, duration = math.max(seconds or 0, 0.01) }
    return
  end
  if script.done(self.state) then
    self.hold = (self.hold or HOLD_SECONDS) - dt
    if self.hold <= 0 then self.state = nil end
    return
  end
  self.think = self.think - dt
  if self.think > 0 then return end
  self.think = THINK_SECONDS
  self.steps = self.steps + 1
  if self.steps > MAX_STEPS then
    self.state = nil
    return
  end
  for _, event in ipairs(script.act(self.state, self.stream)) do self.queue[#self.queue + 1] = event end
end

return M
