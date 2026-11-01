-- arcade_versus.lua
-- Two players in real time, one wall each. See "Versus" in games/README.md.
-- A match has four phases: ready (who is playing), count (3-2-1), play, and over (the final board, then wins and REMATCH).
-- The seats belong to walls: a wall's taps go to that wall's player and nobody else's, and each wall is drawn for its own
-- player. On one wall, or by choice, the computer takes seat 2. Matches are not journaled: a reboot ends one.

local base = require("lib.arcade.base")
local config = require("lib.arcade.constants")
local hw = require("lib.arcade.hw")
local journal = require("lib.arcade.journal")
local screens = require("lib.arcade.screens")
local ui = require("lib.arcade.ui")

local M = {}
local C = ui.C
local floor = math.floor

local MAX_CATCH_UP = 3      -- a late frame runs at most this many steps, so a stall can't decide a match
local LEFT_LIMIT_MS = 20000 -- a player gone from their wall this long forfeits
local QUIT_WINDOW_MS = 3000 -- how long QUIT waits for its second tap
local SPLIT_HINT_MS = 4000  -- how long a game steered by the whole wall shows how
local FINAL_HOLD_MS = 1500  -- taps this soon after the end were aimed at the game, not at the final board
local COUNT_MS = 3000       -- the 3-2-1
local TOAST_MS = 1500
local PLAYER_COLOR = { C.red, C.blue }

local app, S, env

local function nowMs() return os.epoch("local") end

-- ---------------------------------------------------------------- wins and losses

local Wins = {}
Wins.__index = Wins

local function read(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local ok, value = pcall(textutils.unserialise, h.readAll() or "")
  h.close()
  if ok and type(value) == "table" then return value end
  return nil
end

--- The wins table for one game, kept on disk with a good copy through every save.
function M.wins(id)
  local self = setmetatable({ path = "arcade_versus_" .. id .. ".dat" }, Wins)
  self.rows = read(self.path) or read(self.path .. ".tmp") or read(self.path .. ".bak") or {}
  return self
end

function Wins:save()
  local tmp, bak = self.path .. ".tmp", self.path .. ".bak"
  local h = fs.open(tmp, "w")
  if not h then return end
  h.write(textutils.serialise(self.rows))
  h.close()
  if fs.exists(bak) then fs.delete(bak) end
  if fs.exists(self.path) then fs.move(self.path, bak) end
  fs.move(tmp, self.path)
end

function Wins:row(name)
  for _, row in ipairs(self.rows) do
    if row.name == name then return row end
  end
  local row = { name = name, wins = 0, losses = 0 }
  self.rows[#self.rows + 1] = row
  return row
end

--- Count one finished match, most wins first.
function Wins:record(winner, loser)
  local w, l = self:row(winner), self:row(loser)
  w.wins, l.losses = w.wins + 1, l.losses + 1
  table.sort(self.rows, function(a, b)
    if a.wins ~= b.wins then return a.wins > b.wins end
    if a.losses ~= b.losses then return a.losses < b.losses end
    return a.name < b.name
  end)
  self:save()
end

-- ---------------------------------------------------------------- seats

--- The seat this wall belongs to, or nil.
local function seatOf(a, side)
  for p = 1, 2 do
    local seat = a.seats[p]
    if seat and seat.wall == side then return p, seat end
  end
  return nil
end

local function otherWall(side)
  for _, wall in ipairs(env.walls) do
    if wall.name ~= side then return wall.name end
  end
  return nil
end

local function wallAttached(side)
  for _, wall in ipairs(env.walls) do
    if wall.name == side then return true end
  end
  return false
end

--- May this touch speak for this seat? With no name to go on, the wall is all there is.
local function mayUse(seat, who)
  return not seat.cpu and (seat.anon or who == nil or who == seat.name)
end

--- Has this seat's player gone? An empty seat, and the computer, have not.
local function seatGone(seat)
  return seat ~= nil and not seat.cpu and not seat.anon and not hw.isNear(seat.name)
end

--- PLAY THE COMPUTER is there until someone has joined, or if whoever joined has gone again.
local function cpuOffered(a)
  return a.seats[2] == nil or seatGone(a.seats[2])
end

--- A toast for one wall only: the other player is busy, and their game mustn't be covered.
local function refuse(side, text)
  app.audio.play("error")
  app.setToast(text, C.warn, TOAST_MS)
  S.toast.wall = side
end

local function note(side, text)
  app.setToast(text, C.info, 3000)
  S.toast.wall = side
end

local function drawToast(side)
  if S.toast and (S.toast.wall == nil or S.toast.wall == side) then app.drawToast() end
end

-- ---------------------------------------------------------------- the match

function M.bind(appTable, registry)
  app, S, env = appTable, appTable.S, appTable.env
  app.versus = M
  for _, plugin in ipairs(registry or {}) do
    if plugin.versus then M.dress(plugin) end
  end
end

--- The ready screen for the current game. Whoever picked it, on the wall they picked it from, is player 1.
function M.open(who, side)
  S.versus = {
    phase = "ready", wins = M.wins(app.plugin.id), reading = {}, seen = {}, rematch = {},
    seats = { { name = who or "Player", anon = who == nil, wall = side or env.walls[1].name, ready = false } },
    level = app.plugin.cpuLevels[1],
  }
  S.view = "versus"
  S.lastTouch = nowMs()
  S.dirty = true
end

--- A fresh game on the same seats, starting with the 3-2-1.
local function startCount(a)
  local plugin = app.plugin
  a.seed = math.random(1, 2147483646)
  a.rng = journal.rng(a.seed)
  a.state = plugin.rules.new({ rng = a.rng })
  a.phase, a.countUntil = "count", nowMs() + COUNT_MS
  a.reading, a.seen, a.rematch, a.quit, a.away, a.forfeit = {}, {}, {}, {}, {}, nil
  a.inputs, a.last, a.frames = { 0, 0 }, {}, { n = 0, total = 0, worst = 0, late = 0 }
  app.audio.play("select")
  S.dirty = true
end

local function startPlay(a)
  local t = nowMs()
  a.phase, a.startedAt, a.nextAt = "play", t, t + app.plugin.tickMs
  app.audio.cue("start")
  S.dirty = true
end

--- The match is over. forfeit is the player who gave it up, if one did.
local function finish(a, forfeit)
  local s = a.state
  if forfeit then
    s.over, s.winner = true, 3 - forfeit
    a.forfeit = forfeit
  end
  a.phase, a.overAt = "over", nowMs()
  local w = s.winner
  if w == 1 or w == 2 then
    if not a.vsCpu then a.wins:record(a.seats[w].name, a.seats[3 - w].name) end
    app.audio.cue(forfeit and "lose" or "win")
  else
    app.audio.play("draw")
  end
  S.lastTouch = nowMs()
  S.dirty = true
end

function M.leave()
  S.versus, S.view = nil, "idle"
  S.dirty = true
end

--- During a match, an update has to wait.
function M.busy()
  local a = S.versus
  return a ~= nil and (a.phase == "count" or a.phase == "play")
end

local function askToQuit(a, p)
  local t = nowMs()
  if a.quit[p] and t < a.quit[p] then
    finish(a, p)
  else
    a.quit[p] = t + QUIT_WINDOW_MS
    app.audio.play("tap")
    S.dirty = true
  end
end

local function askRematch(a, p, side)
  local other = a.seats[3 - p]
  a.rematch[p] = true
  if other.cpu or a.rematch[3 - p] then
    startCount(a)
  elseif seatGone(other) then
    a.rematch[p] = nil
    refuse(side, other.name .. " has gone")
  else
    app.audio.play("tap")
    note(other.wall, a.seats[p].name .. " wants a rematch")
    S.dirty = true
  end
end

local function join(a, side, who)
  local first = a.seats[1]
  if who ~= nil and who == first.name then
    refuse(side, "This wall is for the other player")
    return
  end
  a.seats[2] = { name = who or "Player 2", anon = who == nil, wall = side, ready = false }
  app.audio.play("select")
  S.dirty = true
end

local function playComputer(a)
  local level = a.level
  a.vsCpu = true
  local name = level and ("CPU " .. string.upper(level)) or "COMPUTER"
  a.seats[2] = { name = name, cpu = true, wall = otherWall(a.seats[1].wall) }
  startCount(a)
end

-- ---------------------------------------------------------------- touch

local onPhase = {}

function onPhase.ready(a, p, seat, id, b)
  if id == "vsReady" then
    seat.ready = not seat.ready
    app.audio.play("tap")
    if a.seats[1].ready and a.seats[2] and a.seats[2].ready then startCount(a) end
  elseif id == "vsCpu" and p == 1 and cpuOffered(a) then
    playComputer(a)
  elseif id == "vsLevel" and p == 1 then
    a.level = b.data
    app.audio.play("tap")
  elseif id == "vsBack" then
    app.audio.play("back")
    if p == 1 then M.leave() else a.seats[2] = nil end
  end
  S.dirty = true
end

function onPhase.play(a, p, _, id, _, _, px, py)
  if id == "vsQuit" then
    askToQuit(a, p)
    return
  end
  local plugin = app.plugin
  local action = plugin.view.actionAt(env.L, a.state, px, py, p)
  a.last[p] = action
  if action then
    a.inputs[p] = a.inputs[p] + 1
    plugin.rules.input(a.state, p, action)
  end
end

function onPhase.over(a, p, _, id, _, side)
  if id == "vsRematch" then
    askRematch(a, p, side)
  elseif id == "vsDone" then
    app.audio.play("back")
    M.leave()
  end
end

--- A touch on a wall during a match screen. Nothing here reads the other wall's seat: a tap speaks for its own wall or
-- for nobody.
function M.touch(side, index, px, py, who)
  local a = S.versus
  ui.setButtons(env.walls[index].buttons)
  local b = ui.hit(px, py)
  local id = b and b.id
  if a.reading[side] then
    if id == "rulesDone" then
      a.reading[side] = nil
      app.audio.play("select")
      S.dirty = true
    end
    return
  end
  if id == "rules" then
    a.reading[side] = true
    app.audio.play("page")
    S.dirty = true
    return
  end
  -- the final board is only ever looked at, so it listens to anybody: a player who walked off mustn't leave it stuck
  if a.phase == "over" and not a.seen[side] then
    if nowMs() - a.overAt >= FINAL_HOLD_MS then
      a.seen[side] = true
      -- nobody stands at the computer's wall to move it on
      for p = 1, 2 do
        local seat = a.seats[p]
        if seat.cpu and seat.wall then a.seen[seat.wall] = true end
      end
      app.audio.play("tap")
      S.dirty = true
    end
    return
  end
  local p, seat = seatOf(a, side)
  if not seat then
    if id == "vsJoin" then join(a, side, who) end
    return
  end
  if not mayUse(seat, who) then
    local holder = seat.cpu and a.seats[3 - p] or seat
    refuse(side, holder.name .. " is playing")
    return
  end
  local act = onPhase[a.phase]
  if act then act(a, p, seat, id, b, side, px, py) end
end

-- ---------------------------------------------------------------- the clock

local function checkPresence(a, t)
  for p = 1, 2 do
    local seat = a.seats[p]
    if not seat.cpu then
      if wallAttached(seat.wall) and not seatGone(seat) then
        a.away[p] = nil
      else
        a.away[p] = a.away[p] or t
        if t - a.away[p] > LEFT_LIMIT_MS then
          finish(a, p)
          return
        end
      end
    end
  end
end

local function step(a)
  local plugin = app.plugin
  local s = a.state
  for p = 1, 2 do
    if a.seats[p].cpu then
      local action = plugin.rules.bot(s, a.rng, p, a.level)
      if action then plugin.rules.input(s, p, action) end
    end
  end
  plugin.view.onEvents(app, s, plugin.rules.tick(s, a.rng) or {})
  if s.over then finish(a) end
end

--- Run the match's one clock. Called on every tick of the shell.
function M.tick(t)
  local a = S.versus
  if not a then return end
  if a.phase == "ready" or (a.phase == "over" and next(a.seen)) then
    if t - S.lastTouch > config.LOBBY_IDLE * 1000 then
      M.leave()
      return
    end
  end
  if a.phase == "ready" and floor(t / 2000) ~= a.nearPhase then
    a.nearPhase = floor(t / 2000) -- someone who joined may have gone, which brings PLAY THE COMPUTER back
    S.dirty = true
  elseif a.phase == "count" then
    if t >= a.countUntil then
      startPlay(a)
    elseif math.ceil((a.countUntil - t) / 1000) ~= a.shownCount then
      S.dirty = true
    end
  elseif a.phase == "play" then
    local tickMs = app.plugin.tickMs
    local steps = 0
    while t >= a.nextAt and steps < MAX_CATCH_UP and a.phase == "play" do
      steps = steps + 1
      a.nextAt = a.nextAt + tickMs
      step(a)
    end
    if steps > 1 then a.frames.late = a.frames.late + 1 end
    if t >= a.nextAt then a.nextAt = t + tickMs end -- too far behind to catch up: carry on from now
    if steps > 0 then S.dirty = true end
    if a.phase == "play" then checkPresence(a, t) end
  end
end

-- ---------------------------------------------------------------- drawing

local function secondsAway(a, p, t)
  return a.away and a.away[p] and math.max(0, math.ceil((a.away[p] + LEFT_LIMIT_MS - t) / 1000))
end

--- Both names and the score, this wall's player on the left.
local function drawHeader(a, p)
  local W = env.W
  local cx = floor(W / 2)
  local s, t = a.state, nowMs()
  local mine, theirs = p, 3 - p
  ui.small(a.seats[mine].name, 2, 1, PLAYER_COLOR[mine], C.bg, "left", cx - 12)
  ui.small(a.seats[theirs].name, W - 2, 1, PLAYER_COLOR[theirs], C.bg, "right", cx - 12)
  ui.text(s.score[mine], cx - 4, 1, PLAYER_COLOR[mine], "right")
  ui.text("-", cx, 1, C.line, "center")
  ui.text(s.score[theirs], cx + 4, 1, PLAYER_COLOR[theirs], "left")
  local gone = secondsAway(a, mine, t)
  if gone then ui.small("COME BACK " .. gone, 2, 3, C.warn, C.bg, "left", cx - 12) end
  gone = secondsAway(a, theirs, t)
  if gone then ui.small("LEAVING " .. gone, W - 2, 3, C.warn, C.bg, "right", cx - 12) end
end

local function drawTable(a, y, limit)
  local W = env.W
  local rows = a.wins.rows
  ui.small("WINS AND LOSSES", floor(W / 2), y, C.hi, C.bg, "center")
  if #rows == 0 then ui.small("Nobody yet. Be the first!", floor(W / 2), y + 2, C.line, C.bg, "center") end
  for i = 1, math.min(#rows, limit) do
    local row, line = rows[i], y + i * 2
    local playing = (a.seats[1].name == row.name) or (a.seats[2] ~= nil and a.seats[2].name == row.name)
    local color = playing and C.hi or (i == 1 and C.text or C.line)
    ui.small(i .. ".", 26, line, color, C.bg, "right")
    ui.small(row.name, 28, line, color, C.bg, "left", 34)
    ui.small(row.wins .. "W", W - 36, line, color, C.bg, "right")
    ui.small(row.losses .. "L", W - 26, line, color, C.bg, "right")
  end
end

local function drawTitle()
  local W = env.W
  local plugin = app.plugin
  ui.text(plugin.title, floor(W / 2), 2, C[plugin.color] or C.hi, "center", W - 38)
  ui.small(plugin.blurb or "", floor(W / 2), 12, C.line, C.bg, "center", W - 4)
  ui.button("rules", W - 18, 1, 16, 7, "HOW TO PLAY", C.panel, { small = true })
end

local function readyLine(a, p, seat)
  local other = a.seats[3 - p]
  if not other then
    if #env.walls < 2 then return "This cabinet has one wall: play the computer", C.line end
    return seat.ready and "You're ready. Waiting for the other wall" or "Waiting for someone at the other wall", C.line
  end
  if other.ready then return other.name .. " is ready", C.ok end
  return "Waiting for " .. other.name, C.line
end

--- A wall nobody has taken yet.
local function drawJoin(a)
  local W, H = env.W, env.H
  drawTitle()
  ui.region("vsJoin", 0, 14, W, H - 14)
  local y = floor(H / 2) - 6
  ui.text("TAP TO JOIN", floor(W / 2), y, C.hi, "center", W - 4)
  ui.small(a.seats[1].name .. " wants a game", floor(W / 2), y + 10, C.text, C.bg, "center", W - 4)
end

local function drawSeated(a, p, seat)
  local W, H = env.W, env.H
  local cx = floor(W / 2)
  drawTitle()
  ui.button("vsBack", 2, 1, 16, 7, "BACK", C.panel, { small = true })
  ui.small("PLAYER " .. p, cx, 15, PLAYER_COLOR[p], C.bg, "center")
  ui.name(seat.name, cx, 17, W - 8, C.text, "center")
  local line, color = readyLine(a, p, seat)
  ui.small(line, cx, 25, color, C.bg, "center", W - 4)
  local y = H - 37
  drawTable(a, 27, floor((y - 30) / 2))
  if #env.walls > 1 then
    ui.button("vsReady", cx - 25, y, 50, 11, seat.ready and "READY!" or "READY", seat.ready and C.panel or C.ok,
      { frame = seat.ready and C.ok or nil })
  end
  if p == 1 and cpuOffered(a) then
    ui.button("vsCpu", cx - 30, y + 13, 60, 9, "PLAY THE COMPUTER", #env.walls > 1 and C.panel or C.ok, { small = true })
    local levels = app.plugin.cpuLevels
    local w = floor(60 / math.max(#levels, 1))
    for i, level in ipairs(levels) do
      ui.button("vsLevel", cx - 30 + (i - 1) * w, y + 24, w - 1, 7, string.upper(level), level == a.level and C.hi or C.panel,
        { small = true, data = level })
    end
  end
end

--- The game as this wall's player sees it, under whatever stands over it.
local function drawGame(a, p)
  drawHeader(a, p)
  app.plugin.view.draw(env.L, a.state, p)
end

local function drawBox(y, h, color)
  ui.fill(4, y, env.W - 8, h, C.panel)
  ui.frame(4, y, env.W - 8, h, color, 1)
end

local function drawCount(a, p)
  local left = math.max(1, math.ceil((a.countUntil - nowMs()) / 1000))
  a.shownCount = left
  drawGame(a, p)
  local cx, y = floor(env.W / 2), floor(env.H / 2) - 6
  ui.fill(cx - 12, y, 24, 13, C.panel)
  ui.frame(cx - 12, y, 24, 13, C.hi, 1)
  ui.text(left, cx, y + 4, C.hi, "center")
end

local function drawPlay(a, p, seat)
  local W, H = env.W, env.H
  drawGame(a, p)
  local plugin = app.plugin
  if plugin.split and nowMs() - a.startedAt < SPLIT_HINT_MS then base.drawSplit(W, H, plugin.splitMiddle) end
  if seat.name and not seat.cpu then
    local asking = a.quit[p] and nowMs() < a.quit[p]
    ui.button("vsQuit", W - 14, H - 8, 12, 7, asking and "SURE?" or "QUIT", asking and C.warn or C.panel, { small = true })
  end
end

local function headline(a)
  local w = a.state.winner
  if w ~= 1 and w ~= 2 then return "DRAW", C.hi end
  return a.seats[w].name .. " WINS", PLAYER_COLOR[w]
end

--- The last moment of the match, kept up until someone taps.
local function drawFinal(a, p)
  local W = env.W
  drawGame(a, p)
  local y = floor(env.H / 2) - 6
  local text, color = headline(a)
  drawBox(y, 13, color)
  ui.text(text, floor(W / 2), y + 2, color, "center", W - 12)
  local why = a.forfeit and (a.seats[a.forfeit].name .. " forfeits - tap to go on") or "TAP TO SEE THE SCORES"
  ui.small(why, floor(W / 2), y + 10, C.text, C.panel, "center", W - 12)
  ui.region("vsSeen", 0, 0, W, env.H)
end

local function drawTableScreen(a, p, seat)
  local W, H = env.W, env.H
  local cx = floor(W / 2)
  local s = a.state
  local text, color = headline(a)
  ui.text(text, cx, 2, color, "center", W - 4)
  local me, them = a.seats[p], a.seats[3 - p]
  ui.small(string.format("%s %d - %d %s", me.name, s.score[p], s.score[3 - p], them.name), cx, 11, C.text, C.bg, "center", W - 4)
  if a.vsCpu then ui.small("Games against the computer aren't counted", cx, 13, C.line, C.bg, "center", W - 4) end
  local y = H - 14
  drawTable(a, 16, floor((y - 19) / 2))
  if seat.cpu then
    ui.small(them.name .. " plays at the other wall", cx, y + 4, C.line, C.bg, "center", W - 4)
    return
  end
  local mine, theirs = a.rematch[p], a.rematch[3 - p]
  local label = "REMATCH"
  if mine then label = "WAITING" elseif theirs then label = "AGREE" end
  ui.button("vsRematch", cx - 42, y, 40, 11, label, mine and C.panel or C.ok)
  ui.button("vsDone", cx + 2, y, 40, 11, "DONE", C.panel)
end

--- One wall, for the player it belongs to.
local function drawWall(a, side)
  ui.screen():clear(C.bg, nil, " ")
  ui.clearButtons()
  if a.reading[side] then
    screens.drawRules()
    return
  end
  local p, seat = seatOf(a, side)
  if a.phase == "ready" then
    if seat then drawSeated(a, p, seat) else drawJoin(a) end
  else
    -- a wall attached partway through has no seat: it just shows player 2's side
    p, seat = p or 2, seat or {}
    if a.phase == "count" then drawCount(a, p)
    elseif a.phase == "play" then drawPlay(a, p, seat)
    elseif a.seen[side] then drawTableScreen(a, p, seat)
    else drawFinal(a, p) end
  end
  drawToast(side)
end

--- Draw both walls, each for its own player. Rows that haven't changed never reach the monitor.
function M.drawWalls()
  local a = S.versus
  local started = os.epoch("utc")
  for _, wall in ipairs(env.walls) do
    ui.setScreen(wall.surf)
    drawWall(a, wall.name)
    wall.buttons = ui.buttons()
    wall.surf:output(wall.out, 0, 0)
  end
  if a.phase == "play" then
    local f, ms = a.frames, os.epoch("utc") - started
    f.n, f.total, f.worst = f.n + 1, f.total + ms, math.max(f.worst, ms)
  end
end

--- The small scoreboard monitor: the match in progress, then the wins table.
function M.drawScoreboard(W, H)
  local a = S.versus
  local cx = floor(W / 2)
  ui.text(app.plugin.short or app.plugin.title, cx, 1, C.hi, "center", W - 2)
  local y = 9
  if a and a.state then
    ui.small(string.format("%s %d - %d %s", a.seats[1].name, a.state.score[1], a.state.score[2], a.seats[2].name), cx, y, C.text, C.bg, "center", W - 2)
    y = y + 2
  end
  local rows = (a and a.wins or M.wins(app.plugin.id)).rows
  if #rows == 0 then ui.small("Nobody yet. Be the first!", cx, y + 2, C.line, C.bg, "center", W - 2) end
  for i, row in ipairs(rows) do
    local line = y + i * 2
    if line < H then
      ui.small(i .. ". " .. row.name, 3, line, i == 1 and C.hi or C.text, C.bg, "left", W - 14)
      ui.small(row.wins .. "-" .. row.losses, W - 3, line, i == 1 and C.hi or C.text, C.bg, "right")
    end
  end
end

-- ---------------------------------------------------------------- the idle screen

local function demoRng(n)
  if n then return math.random(n) end
  return math.random()
end

--- One step of a live demo: both bots playing.
local function demoStep(plugin, demo, t)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 5000) then
    demo.state, demo.nextAt, demo.finishedAt = plugin.rules.new({ rng = demoRng }), t + 800, nil
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  demo.nextAt = t + plugin.tickMs
  local level = plugin.cpuLevels[#plugin.cpuLevels]
  for p = 1, 2 do
    local action = plugin.rules.bot(demo.state, demoRng, p, level)
    if action then plugin.rules.input(demo.state, p, action) end
  end
  plugin.rules.tick(demo.state, demoRng)
  if demo.state.over then demo.finishedAt = t end
  return true
end

--- Give a game the idle screen every Versus game has. wall says which player's side this wall shows.
function M.dress(plugin)
  local view = plugin.view
  view.demoStep = function(demo, t) return demoStep(plugin, demo, t) end
  view.drawAttract = function(W, H, demo, _, wall)
    demo.L = demo.L or view.layout(W, H)
    local title = plugin.title
    if ui.textWidth(title) > W - 2 then title = plugin.short or title end
    ui.text(title, floor(W / 2), 1, C[plugin.color] or C.hi, "center", W - 2)
    if demo.state then view.draw(demo.L, demo.state, wall == 2 and 2 or 1) end
    return math.min(demo.L.statusY or H, H - 2 * ui.fontHeight() - 3)
  end
end

-- ---------------------------------------------------------------- tests

--- What the debug dump shows of a match, for tests.
function M.debug()
  local a = S.versus
  local s = a.state
  local seats = {}
  for p = 1, 2 do
    local seat = a.seats[p]
    seats[p] = seat and { name = seat.name, wall = seat.wall or "", ready = seat.ready == true, cpu = seat.cpu == true } or { name = "" }
  end
  local plugin = app.plugin
  return {
    phase = a.phase, seats = seats, level = a.level, vsCpu = a.vsCpu == true, seen = a.seen,
    rematch1 = a.rematch[1] == true, rematch2 = a.rematch[2] == true, forfeit = a.forfeit,
    score = s and s.score, over = s and s.over, winner = s and s.winner,
    inputs = a.inputs, last1 = a.last and a.last[1], last2 = a.last and a.last[2],
    snapshot = s and plugin.rules.snapshot and plugin.rules.snapshot(s) or nil,
    wins = a.wins.rows, frames = a.frames,
    quit1 = a.quit and a.quit[1] ~= nil, quit2 = a.quit and a.quit[2] ~= nil,
    away1 = a.away and a.away[1], away2 = a.away and a.away[2],
  }
end

return M
