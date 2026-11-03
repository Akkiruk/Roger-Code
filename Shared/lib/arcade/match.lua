-- arcade_match.lua
-- A match from first move to recorded result, for any game. Everything goes through plugin.rules.step, so rules stay
-- pure; what happened comes back as events for the game's view. Every action is in the journal before it is shown.

local audio = require("lib.arcade.audio")
local config = require("lib.arcade.constants")
local hw = require("lib.arcade.hw")
local journal = require("lib.arcade.journal")
local net = require("lib.arcade.net")
local track = require("lib.arcade.track")
local replay = require("lib.arcade.replay")
local seats = require("lib.arcade.seats")
local tournament = require("lib.arcade.tournament")
local ui = require("lib.arcade.ui")

local M = {}

local AI_THINK_MS = 700       -- minimum "thinking" time so a computer move does not feel instant

local app, S

function M.bind(appTable)
  app, S = appTable, appTable.S
end

local function nowMs() return os.epoch("local") end
local function utcMs() return os.epoch("utc") end
local function log(msg) app.log(msg) end

local function pack(...) return { n = select("#", ...), ... } end

--- Whisper a message to each human in the list, once per name. Nothing is ever sent to public chat.
local function tellPlayers(slots, text)
  local seen = {}
  for _, slot in ipairs(slots) do
    if seats.isHuman(slot) and not seen[slot.name] then
      seen[slot.name] = true
      hw.tell(slot.name, text)
    end
  end
end

local function moverSlot(g)
  return g.state.turn == 1 and g.red or g.blue
end
M.moverSlot = moverSlot

local function otherSlot(g)
  return g.state.turn == 1 and g.blue or g.red
end

local function elapsed(g)
  return g.elapsed + (nowMs() - g.resumedAt) / 1000
end

local function entryOf(g, stage)
  return {
    id = g.id, game = app.plugin.id, stage = stage, red = g.red, blue = g.blue, first = g.first, seed = g.seed,
    options = g.options, actions = g.actions, elapsed = elapsed(g), timer = g.timer, timeouts = g.timeouts,
    hints = g.hints, extras = g.extras, reason = g.reason, spots = g.spots, pauses = g.pauses,
  }
end

local function newRecord(red, blue, opts)
  local now = nowMs()
  return {
    id = opts.id or journal.newId(), red = red, blue = blue, first = opts.first or 1, seed = opts.seed or math.random(1, 2147483647),
    options = opts.options, actions = opts.actions or {}, timer = opts.timer or 0,
    state = nil, extras = opts.extras or app.plugin.newExtras(),
    startedAt = now, resumedAt = now, elapsed = opts.elapsed or 0, moveStart = now, deadline = nil,
    timeouts = opts.timeouts or { 0, 0 }, hints = opts.hints or { 0, 0 }, spots = opts.spots or {}, covered = { false, false }, pauses = opts.pauses or 0,
    hint = nil, hintUntil = 0, paused = false, nudged = false, awaySince = nil, aiAt = nil, thinking = false,
    confirmResign = false, abandonBy = nil,
  }
end

local function rulesOptions(g)
  local options = {}
  for k, v in pairs(g.options or {}) do options[k] = v end
  options.first = g.first
  return options
end

local function armTurn(g)
  g.moveStart = nowMs()
  g.nudged = false
  g.hint = nil
  local slot = moverSlot(g)
  if slot.cpu then
    g.aiAt = nowMs() + AI_THINK_MS
    g.deadline = nil
  else
    g.aiAt = nil
    g.deadline = (g.timer > 0) and (nowMs() + g.timer * 1000) or nil
  end
  hw.lamps(g.state.turn == 1, g.state.turn == 2)
end

--- With hidden pieces, follow where the two players stand so a wall can cover up when the opponent walks round to it.
local function followPlayers(g)
  local names = {}
  if app.plugin.private then
    if seats.isHuman(g.red) then names[#names + 1] = g.red.name end
    if seats.isHuman(g.blue) then names[#names + 1] = g.blue.name end
  end
  hw.watch(names)
end

--- Remember where a seated player stands at their own wall.
function M.noteWallTouch(g, wall, who)
  local seat = seats.wallSeat(g, wall)
  local slot = seat and (seat == 1 and g.red or g.blue)
  if slot and seats.isHuman(slot) and slot.name == who then
    g.spots[wall] = hw.position(who) or g.spots[wall]
  end
end

--- Cover a wall while the opposing player stands on its side of the divider.
local function guardWalls(g)
  for seat = 1, 2 do
    local slot, opponent = seat == 1 and g.red or g.blue, seat == 1 and g.blue or g.red
    local covered = false
    if slot.wall and seats.isHuman(opponent) then
      covered = seats.peeking(hw.position(opponent.name), g.spots[slot.wall], g.spots[opponent.wall])
    end
    if covered ~= g.covered[seat] then
      g.covered[seat] = covered
      S.dirty = true
    end
  end
end

--- Start a match. first is the seat to move first.
function M.start(red, blue, opts)
  local plugin = app.plugin
  local g = newRecord(red, blue, {
    first = opts and opts.first or 1, options = plugin.matchOptions(app.store), timer = plugin.moveTimer(app.store),
  })
  g.rng = journal.rng(g.seed)
  g.state = plugin.rules.new(rulesOptions(g))
  S.match = g
  S.result = nil
  S.view = "game"
  S.demo = {}
  -- where each player stood to tap their name is their wall's spot, from the very first move
  for _, slot in ipairs({ red, blue }) do
    if plugin.private and seats.isHuman(slot) then g.spots[slot.wall] = hw.position(slot.name) end
  end
  followPlayers(g)
  audio.cue("start")
  g.track = track.start(plugin.id, plugin.title, { red.name, blue.name })
  armTurn(g)
  log(string.format("match %s start: %s red=%s(%s) blue=%s(%s) first=%d timer=%d", g.id, plugin.id, red.name, tostring(red.cpu),
    blue.name, tostring(blue.cpu), g.first, g.timer))
  journal.save(entryOf(g, "playing"))
  if app.prefs.announce and (seats.isHuman(red) or seats.isHuman(blue)) then
    tellPlayers({ red, blue }, string.format("%s (Red) vs %s (Blue) - %s is on!", red.name, blue.name, plugin.title))
  end
  S.dirty = true
end

local function rankOf(name)
  return (app.store:rank(name, "elo"))
end

local function unrecordedSummary(g)
  return { ranked = false, achievements = {}, red = { name = g.red.name }, blue = { name = g.blue.name } }
end

--- Put a finished match in the records, then close its journal entry. A repeat after a reboot changes nothing.
local function settle(g, reason)
  local s = g.state
  local winner = s.winner
  local seconds = elapsed(g)
  local anyGuest = g.red.guest or g.blue.guest
  local counts = (seats.isHuman(g.red) or seats.isHuman(g.blue)) and not anyGuest
  local before = {
    red = seats.isHuman(g.red) and rankOf(g.red.name) or nil,
    blue = seats.isHuman(g.blue) and rankOf(g.blue.name) or nil,
  }
  local summary
  if counts then
    local m = app.plugin.summarize(g)
    m.matchId, m.red, m.blue, m.redCpu, m.blueCpu = g.id, g.red.name, g.blue.name, g.red.cpu, g.blue.cpu
    m.winner, m.seconds, m.forfeit = winner, seconds, s.forfeit
    summary = app.store:record(m)
    app.store:save()
  end
  summary = summary or unrecordedSummary(g)
  local after = {
    red = seats.isHuman(g.red) and not anyGuest and rankOf(g.red.name) or nil,
    blue = seats.isHuman(g.blue) and not anyGuest and rankOf(g.blue.name) or nil,
  }
  journal.clear()
  if #g.actions >= 4 and not s.forfeit then
    replay.add(app.plugin.id, {
      red = g.red.name, blue = g.blue.name, first = g.first, seed = g.seed, options = g.options, actions = g.actions, winner = winner,
    })
  end
  net.result(app.plugin.id, app.plugin.title, g.red.name, g.blue.name, winner, #g.actions, summary.ranked)
  track.stop(g.track, { winner = winner == 1 and g.red.name or winner == 2 and g.blue.name or "draw", moves = #g.actions })
  -- in a knockout a result moves the bracket. A draw moves nothing, so the same pair play again
  if S.tour and tournament.next(S.tour) and winner ~= 3 then
    local name = (winner == 1 and g.red or g.blue).name
    S.tourChampion = tournament.report(S.tour, name)
    tournament.save(S.tour)
    if S.tourChampion then
      local p = app.store:ensure(S.tourChampion)
      p.titles = (p.titles or 0) + 1
      app.store:save()
    end
  end
  local rivalry
  if summary.ranked and winner ~= 3 then
    rivalry = app.store:rivalry((winner == 1 and g.red or g.blue).name, (winner == 1 and g.blue or g.red).name)
  end
  S.result = {
    rivalry = rivalry, id = g.id,
    red = g.red, blue = g.blue, winner = winner, moves = app.plugin.summarize(g).moves, seconds = seconds,
    forfeit = s.forfeit, summary = summary, rankBefore = before, rankAfter = after, reason = reason, state = s,
    ranked = summary.ranked, guest = anyGuest, at = utcMs(),
  }
  return summary, before, after
end

local function celebrate(g, summary, before, after)
  local s = g.state
  local winner = s.winner
  hw.lamps(winner == 1, winner == 2)
  hw.celebrate(winner == 1 or winner == 2)
  S.celebrateUntil = nowMs() + 4000

  -- sound: the winner's side decides the cue; against a computer, the human's result decides
  local human = seats.isHuman(g.red) and 1 or (seats.isHuman(g.blue) and 2 or nil)
  if winner == 3 then
    audio.cue("draw")
  elseif human and not (seats.isHuman(g.red) and seats.isHuman(g.blue)) then
    audio.cue(winner == human and "win" or "lose")
  else
    audio.cue("win")
  end
  if #(summary.achievements or {}) > 0 then audio.later("achievement", 1600, 1, 1) end
  if summary.ranked and (after.red or after.blue) then
    local moved = (before.red and after.red and after.red < before.red) or (before.blue and after.blue and after.blue < before.blue)
    if moved then audio.later("rank", 2000, 0.8, 1.1) end
  end

  if app.prefs.announce and (seats.isHuman(g.red) or seats.isHuman(g.blue)) then
    local text
    if winner == 3 then
      text = string.format("%s and %s drew %s!", g.red.name, g.blue.name, app.plugin.title)
    else
      text = app.plugin.view.announceWin(g, summary, app.signed)
    end
    tellPlayers({ g.red, g.blue }, text)
    for _, a in ipairs(summary.achievements or {}) do
      hw.tell(a.player, "You unlocked '" .. a.name .. "'!")
    end
  end
end

--- The match is over: journal it as finished, record it, and show the final board.
local function finish(g, reason)
  g.reason = reason
  journal.save(entryOf(g, "finished"))
  local summary, before, after = settle(g, reason)
  S.finalMatch = g -- it stays up until someone taps, so the players can go over how it ended
  S.view = "final"
  S.toast = nil
  S.lastTouch = nowMs()
  celebrate(g, summary, before, after)
  local s = g.state
  log(string.format("match %s end: winner=%d forfeit=%s ranked=%s reason=%s", g.id, s.winner, tostring(s.forfeit), tostring(summary.ranked), tostring(reason)))
  S.match = nil
  hw.watch({})
  S.dirty = true
end

--- Apply an action through the rules: journal, then events, then whatever comes next.
-- @return boolean, reason
function M.apply(g, action, why)
  local stepped, events = app.plugin.rules.step(g.state, action, g.rng)
  if not stepped then return false, events end
  g.actions[#g.actions + 1] = action
  journal.save(entryOf(g, "playing"))
  app.plugin.view.onEvents(app, g, events)
  if g.state.winner ~= 0 then
    finish(g, why or "played")
    return true
  end
  armTurn(g)
  S.dirty = true
  return true
end

--- Any legal action, for a missed move timer or a computer that failed.
local function randomAction(g)
  local actions = app.plugin.rules.legalActions(g.state)
  return actions[math.random(#actions)]
end

--- Yield to the event loop while the computer thinks, keeping other events for later. A touch is dropped: kept, it would
-- land on the board after the computer's move, as a move the player never saw.
local function aiYield()
  local saved = {}
  os.queueEvent("arcade_yield")
  while true do
    local ev = pack(os.pullEventRaw())
    if ev[1] == "arcade_yield" then break end
    if ev[1] == "terminate" then error("Terminated", 0) end
    if ev[1] ~= "monitor_touch" and ev[1] ~= "vhcc_touch" then saved[#saved + 1] = ev end
  end
  for _, ev in ipairs(saved) do os.queueEvent(unpack(ev, 1, ev.n)) end
end

local function doAiMove(g)
  local slot = moverSlot(g)
  local t0 = nowMs()
  log(string.format("ai %s thinking", tostring(slot.cpu)))
  local ok, action, info = pcall(app.plugin.chooseAction, app.seen(g.state), slot.cpu or "medium", { yield = aiYield })
  if not ok then
    if tostring(action):find("Terminated", 1, true) then error(action, 0) end
    log("ai error, playing a random move: " .. tostring(action))
    action, info = nil, nil
  end
  if not action then action = randomAction(g) end
  log(string.format("ai %s moved depth=%s nodes=%s score=%s in %dms", tostring(slot.cpu), tostring(info and info.depth),
    tostring(info and info.nodes), tostring(info and info.score), nowMs() - t0))
  M.apply(g, action)
end

--- End the match with no result.
function M.abandon(g, why)
  log("match abandoned: " .. tostring(why))
  track.stop(g.track, { abandoned = true })
  hw.allOff()
  hw.watch({})
  S.match = nil
  journal.clear()
  S.view = S.tour and "bracket" or "idle" -- a knockout match that stops can simply be played again
  S.lobby = nil
  app.setToast("Game abandoned - no rating change", ui.C.warn)
  S.dirty = true
end

--- Forfeit a seat: a real result, which is what keeps walking away from costing a rating.
function M.forfeit(g, seat, reason)
  return M.apply(g, { kind = "forfeit", seat = seat }, reason)
end

--- The mover has gone, or gone quiet. With the other named player present, that is a forfeit, and otherwise nobody can
-- claim the win, so the match is called off.
local function endForAbsence(g, why)
  local mover, other = moverSlot(g), otherSlot(g)
  local _, ok, detected = hw.nearby()
  local otherHere = false
  for _, n in ipairs(detected) do if n == other.name then otherHere = true end end
  if seats.isRated(g) and ok and otherHere then
    tellPlayers({ g.red, g.blue }, mover.name .. " left the game, so it counts as a forfeit.")
    M.forfeit(g, g.state.turn, why)
  else
    tellPlayers({ g.red, g.blue }, mover.name .. " left the game, so it was called off.")
    M.abandon(g, why)
  end
end

local lastPresence = 0

local function checkPresence(g)
  if g.paused then g.awaySince = nil; return end
  local mover = moverSlot(g)
  if not seats.isHuman(mover) then g.awaySince = nil; return end
  local _, ok, detected = hw.nearby()
  if not ok then g.awaySince = nil; return end
  local here = false
  for _, n in ipairs(detected) do if n == mover.name then here = true end end
  if here then
    g.awaySince = nil
    g.warnedAway = false
    return
  end
  if not g.awaySince then g.awaySince = nowMs() end
  local away = (nowMs() - g.awaySince) / 1000
  if away > config.PRESENCE_LIMIT then
    endForAbsence(g, "walked away")
  elseif away > config.PRESENCE_WARN and not g.warnedAway then
    g.warnedAway = true
    audio.play("presence")
    hw.tell(mover.name, "Your " .. app.plugin.title .. " game is waiting!")
  end
end

--- Carry on from a pause with the clocks where they stopped, so a pause never buys time. Past the limit they never stopped.
function M.resume(g)
  local stopped = nowMs() - (g.pausedAt or nowMs())
  if g.pauses > config.MAX_PAUSES then stopped = 0 end
  g.paused = false
  g.pausedAt = nil
  g.moveStart = g.moveStart + stopped
  if g.deadline then g.deadline = g.deadline + stopped end
  S.dirty = true
end

--- A two-wall match with a wall missing stops: nobody can lose a game on a screen that went dark. True while it waits.
local function waitForWall(g, t)
  if #app.env.walls >= 2 then
    if g.wallGone then
      if g.paused then
        g.pausedAt = g.pausedAt + (t - g.wallGone) -- the players' own pause carries on
        g.wallGone = nil
      else
        g.pausedAt, g.wallGone = g.wallGone, nil
        M.resume(g)
      end
      app.setToast("Both walls are back", ui.C.info, 2000)
    end
    return false
  end
  g.wallGone = g.wallGone or t
  if t - g.wallGone > config.WALL_GONE * 1000 then
    M.abandon(g, "a wall went dark")
  elseif not S.toast then
    app.setToast("A wall is missing - waiting for it", ui.C.warn, 3000)
  end
  return true
end

--- The clock for the match in progress.
function M.tick(g, t)
  track.beat(g.track)
  if app.plugin.view.tick(g, t) then S.dirty = true end
  if app.plugin.private then
    if waitForWall(g, t) then return end
    guardWalls(g)
  end
  if g.confirmResign and t > (g.confirmUntil or 0) then g.confirmResign = false; S.dirty = true end
  if g.hint and t > g.hintUntil then g.hint = nil; S.dirty = true end
  if g.paused then
    if t - (g.pausedAt or t) > config.PAUSE_LIMIT * 1000 then
      M.resume(g)
      app.setToast("Back to the game", ui.C.info, 2000)
    end
  else
    if t - g.moveStart > config.GAME_IDLE * 1000 then
      endForAbsence(g, "idle")
      return
    end
    local mover = moverSlot(g)
    if mover.cpu and g.aiAt and t >= g.aiAt then
      g.thinking = true
      app.render()
      g.thinking = false
      g.aiAt = nil
      doAiMove(g)
      S.dirty = true
    elseif g.deadline then
      local left = g.deadline - t
      local sec = math.floor(left / 1000)
      if sec ~= g.lastSec then
        g.lastSec = sec
        S.dirty = true
        if sec >= 0 and sec < 5 then audio.play("tick", 1, 1 + (5 - sec) * 0.08) end
      end
      if left <= 0 then
        -- out of time: a random legal move is played, and too many of those forfeit the match
        local n = g.state.turn
        g.timeouts[n] = g.timeouts[n] + 1
        audio.play("timeout")
        if g.timeouts[n] >= config.MAX_TIMEOUTS then
          app.setToast(mover.name .. " ran out of time - forfeit", ui.C.warn, 3000)
          M.forfeit(g, n, "timeout")
        else
          app.setToast(string.format("%s timed out (%d/%d) - random move", mover.name, g.timeouts[n], config.MAX_TIMEOUTS), ui.C.warn, 3000)
          M.apply(g, randomAction(g), "timeout")
        end
      end
    end
    if S.match == g and not g.nudged and seats.isHuman(mover) and t - g.moveStart > config.NUDGE_AFTER * 1000 then
      g.nudged = true
      hw.tell(mover.name, "It's your move in " .. app.plugin.title .. "!")
    end
  end
  if S.match == g and t - lastPresence > 2000 then
    lastPresence = t
    checkPresence(g)
    S.dirty = true
  end
end

--- A finished match set up to play back. It looks like a match to the views, with replay set.
function M.newReplay(entry)
  local g = newRecord({ name = entry.red }, { name = entry.blue }, { first = entry.first, seed = entry.seed, options = entry.options })
  g.script, g.replay, g.step = entry.actions, true, 0
  g.rng = journal.rng(g.seed)
  g.state = app.plugin.rules.new(rulesOptions(g))
  return g
end

--- One action of a replay. Returns false once there are no more.
function M.replayStep(g)
  g.step = g.step + 1
  local action = g.script[g.step]
  if not action then return false end
  local stepped, events = app.plugin.rules.step(g.state, action, g.rng)
  if not stepped then return false end
  app.plugin.view.onEvents(app, g, events)
  return true
end

--- Rebuild a match from its journal: the seed and the actions give back the exact state.
local function rebuild(entry, plugin)
  local g = newRecord(entry.red, entry.blue, entry)
  g.options = entry.options
  g.rng = journal.rng(g.seed)
  g.state = plugin.rules.new(rulesOptions(g))
  for i, action in ipairs(entry.actions or {}) do
    if not plugin.rules.step(g.state, action, g.rng) then
      return nil, "action " .. i .. " no longer applies"
    end
  end
  plugin.view.onResume(g)
  return g
end

--- Pick up whatever the journal left: a match to carry on, or a result still to record.
-- @return boolean  true when a match or result is now on screen
function M.recover()
  local entry = journal.load()
  if not entry then return false end
  local plugin = app.pluginById(entry.game)
  if not plugin or type(entry.red) ~= "table" or type(entry.blue) ~= "table" then
    log("journal entry for an unknown game cleared: " .. tostring(entry.game))
    journal.clear()
    return false
  end
  if not app.fits(plugin) then
    -- a wall can attach a moment after boot, so keep the match until one does
    log("match waiting: this cabinet cannot play " .. tostring(entry.game) .. " right now")
    S.recoverLater = true
    return false
  end
  app.selectGame(plugin)
  local g, why = rebuild(entry, plugin)
  if not g then
    log("journal entry cleared: " .. tostring(why))
    journal.clear()
    return false
  end
  if g.state.winner ~= 0 then
    -- the result was reached before the reboot; the match id stops it counting twice
    S.match = g
    finish(g, entry.reason or "played")
    log("recovered finished match " .. g.id)
    return true
  end
  S.match = g
  S.view = "game"
  followPlayers(g)
  armTurn(g)
  app.setToast("Game resumed", ui.C.info, 3000)
  log("resumed match " .. g.id .. " after " .. #g.actions .. " actions")
  return true
end

return M
