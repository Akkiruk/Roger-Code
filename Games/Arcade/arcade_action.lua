-- arcade_action.lua
-- Classic games: one player, in real time, playing for a high score. See "Classics" in games/README.md.
-- A run has three phases: ready (the score table and START), play, and over (the final board, until someone taps).
-- Runs are not journaled: a reboot ends one, and nothing is at stake but a score.

local config = require("arcade_constants")
local hw = require("arcade_hw")
local journal = require("arcade_journal")
local scores = require("arcade_scores")
local ui = require("arcade_ui")

local M = {}
local C = ui.C
local floor = math.floor

local MAX_CATCH_UP = 3   -- a late frame runs at most this many steps, so a stall can't kill the player
local LEFT_LIMIT_MS = 20000 -- a player the detector has lost for this long has walked away

local app, S, env

function M.bind(appTable)
  app, S, env = appTable, appTable.S, appTable.env
end

local function nowMs() return os.epoch("local") end

--- The ready screen for the current game.
function M.open(who)
  S.action = { phase = "ready", player = who, scores = scores.open(app.plugin.id) }
  S.view = "action"
  S.lastTouch = nowMs()
  S.dirty = true
end

function M.start(who)
  local a = S.action
  local plugin = app.plugin
  a.player = who or a.player or "Player"
  a.seed = math.random(1, 2147483646)
  a.rng = journal.rng(a.seed)
  a.state = plugin.rules.new({ rng = a.rng })
  a.phase, a.place, a.awaySince = "play", nil, nil
  a.nextAt = nowMs() + (plugin.tickMs or 150)
  app.audio.cue("start")
  S.dirty = true
end

local function finish()
  local a = S.action
  local s = a.state
  a.phase = "over"
  a.place = a.scores:add(a.player, s.score, s.level)
  app.audio.cue(a.place == 1 and "win" or "lose")
  S.lastTouch = nowMs()
  S.dirty = true
end

--- End the run where it stands: the score still counts.
function M.quit()
  if S.action and S.action.phase == "play" then finish() end
end

function M.leave()
  S.action, S.view = nil, "idle"
  S.dirty = true
end

--- May this touch play? A named player's run answers only to them.
local function isPlayer(who)
  local player = S.action.player
  return who == nil or player == "Player" or who == player
end

function M.mayPlay(who)
  if isPlayer(who) then return true end
  app.setToast(S.action.player .. " is playing", C.warn, 1500)
  return false
end

--- A touch on the game itself.
function M.touch(px, py, who)
  local a = S.action
  if not a or a.phase ~= "play" or not M.mayPlay(who) then return end
  local action = app.plugin.view.actionAt(env.L, a.state, px, py)
  if action then app.plugin.rules.input(a.state, action) end
end

function M.press(index, who)
  local a = S.action
  if not a or a.phase ~= "play" or not M.mayPlay(who) then return end
  local control = app.plugin.view.controls(env.L, a.state)[index]
  if control then app.plugin.rules.input(a.state, control.action) end
end

local function checkPresence(a, t)
  local player = a.player
  if player == "Player" or hw.isNear(player) then
    a.awaySince = nil
  else
    a.awaySince = a.awaySince or t
    if t - a.awaySince > LEFT_LIMIT_MS then finish() end
  end
end

--- Run the game's clock. Called on every tick of the shell.
function M.tick(t)
  local a = S.action
  if not a then return end
  if a.phase == "ready" and t - S.lastTouch > config.LOBBY_IDLE * 1000 then
    M.leave()
    return
  end
  if a.phase ~= "play" then return end
  local plugin = app.plugin
  local step = plugin.tickMs or 150
  local steps = 0
  while t >= a.nextAt and steps < MAX_CATCH_UP and a.phase == "play" do
    steps = steps + 1
    a.nextAt = a.nextAt + step
    local events = plugin.rules.tick(a.state, a.rng)
    plugin.view.onEvents(app, a.state, events or {})
    if a.state.over then finish() end
  end
  if t >= a.nextAt then a.nextAt = t + step end -- too far behind to catch up: carry on from now
  if steps > 0 then S.dirty = true end
  checkPresence(a, t)
end

local function drawHeader(a)
  local W = env.W
  local s = a.state
  ui.small(a.player, 2, 1, C.line, C.bg, "left", 24)
  ui.small("BEST " .. math.max(a.scores:best(), s.score), 2, 3, C.line, C.bg, "left", 24)
  ui.text(s.score, floor(W / 2), 1, C.hi, "center")
  ui.small("LEVEL " .. (s.level or 1), W - 2, 1, C.line, C.bg, "right")
  if s.lives then ui.small("LIVES " .. s.lives, W - 2, 3, s.lives <= 1 and C.warn or C.text, C.bg, "right") end
end

local function drawControls(a)
  for i, control in ipairs(app.plugin.view.controls(env.L, a.state)) do
    ui.button("act", control.x, control.y, control.w, control.h, control.label, C.panel, { small = true, data = i })
  end
end

local function drawTable(a, y)
  local W = env.W
  ui.small("HIGH SCORES", floor(W / 2), y, C.hi, C.bg, "center")
  if #a.scores.rows == 0 then
    ui.small("Nobody yet. Be the first!", floor(W / 2), y + 2, C.line, C.bg, "center")
  end
  for i, row in ipairs(a.scores.rows) do
    local color = i == a.place and C.hi or (i == 1 and C.text or C.line)
    local line = y + i * 2
    ui.small(i .. ".", 34, line, color, C.bg, "right")
    ui.small(row.name, 36, line, color, C.bg, "left", 30)
    ui.small(tostring(row.score), W - 34, line, color, C.bg, "right")
  end
end

local function drawReady(a)
  local W, H = env.W, env.H
  ui.text(app.plugin.title, floor(W / 2), 2, C[app.plugin.color] or C.hi, "center", W - 4)
  if app.plugin.blurb then ui.small(app.plugin.blurb, floor(W / 2), 12, C.line, C.bg, "center", W - 4) end
  drawTable(a, 15)
  local y = H - 22
  ui.button("actStart", floor(W / 2) - 25, y, 50, 11, "START", C.ok)
  ui.button("back", 2, 1, 16, 7, "BACK", C.panel, { small = true })
  ui.button("rules", W - 18, 1, 16, 7, "HOW TO PLAY", C.panel, { small = true })
  ui.button("actBoards", 2, H - 9, 24, 7, "OTHER GAMES", C.panel, { small = true })
  app.drawToast()
end

local function drawOver(a)
  local W, H = env.W, env.H
  local s = a.state
  ui.text("GAME OVER", floor(W / 2), 2, C.warn, "center")
  ui.text(s.score, floor(W / 2), 11, C.hi, "center")
  local line = a.place == 1 and "A NEW HIGH SCORE!" or (a.place and ("Number " .. a.place .. " on the table") or (a.player .. ", level " .. (s.level or 1)))
  ui.small(line, floor(W / 2), 20, a.place and C.ok or C.line, C.bg, "center", W - 4)
  drawTable(a, 23)
  local y = H - 14
  ui.button("actStart", floor(W / 2) - 42, y, 40, 11, "PLAY AGAIN", C.ok)
  ui.button("actDone", floor(W / 2) + 2, y, 40, 11, "DONE", C.panel)
end

--- Draw whatever phase the run is in.
function M.draw()
  local a = S.action
  ui.screen():clear(C.bg, nil, " ")
  ui.clearButtons()
  if a.phase == "ready" then
    drawReady(a)
  elseif a.phase == "over" then
    drawOver(a)
  else
    drawHeader(a)
    app.plugin.view.draw(env.L, a.state)
    drawControls(a)
    ui.button("actQuit", env.W - 14, env.H - 8, 12, 7, "QUIT", C.panel, { small = true })
    app.drawToast()
  end
end

--- What the debug dump shows of a run, for tests.
function M.debug()
  local a = S.action
  local s = a.state
  return {
    phase = a.phase, player = a.player, place = a.place, best = a.scores:best(), table = #a.scores.rows,
    score = s and s.score, lives = s and s.lives, level = s and s.level, over = s and s.over,
  }
end

return M
