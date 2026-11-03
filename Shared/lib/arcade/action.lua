-- arcade_action.lua
-- Classic games: one player, in real time, playing for a high score. See "Classics" in games/README.md.
-- A run has three phases: ready (the score table and START), play, and over (the final board, until someone taps).
-- Runs are not journaled: a reboot ends one, and nothing is at stake but a score.
-- A plugin with saves = true is a long game: its run is kept in a file for its player (saves.lua). Walking away or SAVE &
-- QUIT pauses the run and frees the wall, and only `over` ends it. A plugin without saves takes none of those paths.

local base = require("lib.arcade.base")
local config = require("lib.arcade.constants")
local hw = require("lib.arcade.hw")
local journal = require("lib.arcade.journal")
local saves = require("lib.arcade.saves")
local scores = require("lib.arcade.scores")
local ui = require("lib.arcade.ui")

local M = {}
local C = ui.C
local floor = math.floor

local MAX_CATCH_UP = 3   -- a late frame runs at most this many steps, so a stall can't kill the player
local LEFT_LIMIT_MS = 20000 -- a player the detector has lost for this long has walked away
local QUIT_WINDOW_MS = 3000 -- how long QUIT waits for its second tap
local SPLIT_HINT_MS = 4000 -- how long a game steered by the whole wall shows how
local FINAL_HOLD_MS = 1500 -- taps this soon after the end were aimed at the game, not at the final board

local app, S, env

function M.bind(appTable)
  app, S, env = appTable, appTable.S, appTable.env
end

local function nowMs() return os.epoch("local") end

--- This player's save, if it's one this game can show. A file can be sound and still not suit the game as it is now, so
-- it's tried here rather than on the player's first frame. The line is what the ready screen says about it.
local function readSave(owner)
  local plugin = app.plugin
  local save = saves.read(plugin.id, owner)
  if not save then return nil end
  local ok, summary = pcall(function()
    plugin.view.draw(env.L, save.state)
    plugin.view.controls(env.L, save.state)
    return plugin.view.saveSummary and plugin.view.saveSummary(save.state)
  end)
  if not ok then
    app.log("save for " .. tostring(owner) .. " on " .. plugin.id .. " can't be shown: " .. tostring(summary))
    return nil
  end
  save.line = owner .. ": " .. (summary and tostring(summary):gsub("%c", " ") or "your game is saved")
  return save
end

--- The ready screen speaks to whoever tapped it last, and shows them their own save and nobody else's.
local function offerSave(a, owner)
  a.saveOwner, a.saved, a.newUntil = owner, readSave(owner), nil
  S.dirty = true
end

--- Keep this run's place on disk. Returns false if it couldn't, which never stops the run.
local function saveRun(a)
  if a.phase ~= "play" or a.midRules or a.state.over then return false end
  local ok, why = saves.write(app.plugin.id, a.player, a.state, a.rngAt())
  if not ok then
    app.log("could not save " .. app.plugin.id .. " for " .. tostring(a.player) .. ": " .. tostring(why))
    app.setToast("Could not save your game", C.warn, 2500)
  end
  return ok
end

--- A tap that came with no name: if one person is here, it's them.
local function nearestName(who)
  if who then return who end
  local list = hw.nearby()
  return #list == 1 and list[1] or nil
end

--- The ready screen for the current game. A game whose idle screen is its opening (view.intro) carries on with it from
-- the idle demo, heard now and with a SKIP, and the ready screen comes after it.
function M.open(who, demo)
  who = nearestName(who)
  local hook = app.plugin.view.intro
  local run = demo and hook and hook.from(demo, nowMs(), app) or nil
  S.action = { phase = run and "intro" or "ready", player = who, scores = scores.open(app.plugin.id), intro = run }
  if app.plugin.saves and not run then offerSave(S.action, who or "Player") end
  S.view = "action"
  S.lastTouch = nowMs()
  S.dirty = true
end

--- The opening is over, played out or skipped: on to the ready screen.
local function introDone(a)
  app.plugin.view.intro.stop(app)
  a.phase, a.intro = "ready", nil
  if app.plugin.saves then offerSave(a, a.player or "Player") end
  S.lastTouch = nowMs()
  S.dirty = true
end

--- Everyone's saved games on this cabinet, and how far each has got: a game with view.progress offers it from the ready
-- screen. Only for looking at; BACK returns to the ready screen.
function M.showPlayers()
  local a = S.action
  if not a or a.phase ~= "ready" then return end
  local rows = {}
  for _, save in ipairs(saves.list(app.plugin.id)) do
    local ok, p = pcall(app.plugin.view.progress, save.state)
    if ok and p then
      p.player, p.at = save.player, save.at
      rows[#rows + 1] = p
    end
  end
  table.sort(rows, function(x, y)
    if x.percent ~= y.percent then return x.percent > y.percent end
    return (x.at or 0) > (y.at or 0)
  end)
  a.phase, a.players = "players", rows
  S.lastTouch = nowMs()
  S.dirty = true
end

function M.hidePlayers()
  local a = S.action
  if a and a.phase == "players" then
    a.phase, a.players = "ready", nil
    S.dirty = true
  end
end

function M.skipIntro()
  local a = S.action
  if a and a.phase == "intro" then introDone(a) end
end

--- Into play, on a new run or a saved one.
local function begin(a)
  a.phase, a.place, a.awaySince, a.reviewed, a.quitUntil = "play", nil, nil, false, nil
  a.nextAt = nowMs() + (app.plugin.tickMs or 150)
  a.startedAt = nowMs()
  a.touchedAt, a.saveAt = a.startedAt, a.startedAt + saves.AUTOSAVE_MS
  app.audio.cue("start")
  S.dirty = true
end

function M.start(who)
  local a = S.action
  local plugin = app.plugin
  if plugin.saves then
    local owner = nearestName(who) or a.player or "Player"
    -- START and AGAIN must not write over a game: this tapper's save may not be what the screen was showing
    if readSave(owner) then
      M.open(owner)
      return
    end
    saves.delete(plugin.id, owner)
  end
  a.player = nearestName(who) or a.player or "Player"
  a.seed = math.random(1, 2147483646)
  a.rng, a.rngAt = journal.trackedRng(a.seed)
  a.state = plugin.rules.new({ rng = a.rng, player = a.player })
  begin(a)
  if plugin.saves then saveRun(a) end
end

--- If this tap is someone else's, the ready screen turns to them and the tap has done its job.
local function readyForOther(a, who)
  if not who or who == a.saveOwner then return false end
  offerSave(a, who)
  return true
end

--- CONTINUE: the save carries on from where its numbers left off.
function M.continue(who)
  local a = S.action
  if not a or a.phase ~= "ready" or not a.saved or readyForOther(a, who) then return end
  local save = a.saved
  a.player, a.state, a.saved = save.player, save.state, nil
  a.rng, a.rngAt = journal.trackedRng(save.rng - 1)
  begin(a)
end

--- NEW GAME takes two taps: the second one loses the save.
function M.newGame(who)
  local a = S.action
  if not a or a.phase ~= "ready" or not a.saved or readyForOther(a, who) then return end
  if a.newUntil and nowMs() < a.newUntil then
    saves.delete(app.plugin.id, a.saved.player)
    a.saved, a.newUntil = nil, nil
    M.start(who)
  else
    a.newUntil = nowMs() + QUIT_WINDOW_MS
    app.audio.play("tap")
  end
end

local function finish()
  local a = S.action
  local s = a.state
  if a.phase == "over" then return end
  a.phase = "over"
  a.overAt = nowMs()
  if app.plugin.saves then saves.delete(app.plugin.id, a.player) end
  a.place = a.scores:add(a.player, s.score, s.level)
  app.audio.cue(a.place == 1 and "win" or "lose")
  S.lastTouch = nowMs()
  S.dirty = true
end

--- A long game stops without ending: save it and free the wall.
local function pause(a)
  saveRun(a)
  app.audio.play("back")
  M.leave()
end

--- A player told their save failed can still go, but they get told first.
local function saveAndQuit(a)
  if saveRun(a) or a.leaveUnsaved then
    app.audio.play("back")
    M.leave()
    return
  end
  a.leaveUnsaved, a.quitUntil = true, nil
  app.setToast("Not saved! SAVE & QUIT again to leave anyway", C.warn, 4000)
end

--- QUIT sits close to the game, so it takes two taps: a stray one can't end a run.
function M.askToQuit()
  local a = S.action
  if not a or a.phase ~= "play" then return end
  if a.quitUntil and nowMs() < a.quitUntil then
    if app.plugin.saves then saveAndQuit(a) else finish() end
  else
    a.quitUntil = nowMs() + QUIT_WINDOW_MS
    app.audio.play("tap")
  end
end

--- The final board has been looked at: on to the score table. Returns true if it moved on.
function M.seen()
  local a = S.action
  if not a or nowMs() - (a.overAt or 0) < FINAL_HOLD_MS then return false end
  a.reviewed = true
  return true
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

--- Hand an action to the rules. A long game's clock may be slow or stopped, so nothing else is coming to show the result
-- of a tap, or to notice that it ended the game.
local function applyInput(a, action)
  local plugin = app.plugin
  if not plugin.saves then
    plugin.rules.input(a.state, action)
    return
  end
  a.midRules = true
  plugin.rules.input(a.state, action)
  a.midRules = nil
  if a.state.over then finish() end
  S.dirty = true
end

--- A touch on the game itself.
function M.touch(px, py, who)
  local a = S.action
  if a and a.phase == "intro" then
    -- a tap turns the page; the opening's last page turned leaves it
    if app.plugin.view.intro.tap(a.intro, nowMs(), app) then introDone(a) end
    S.dirty = true
    return
  end
  if a and a.phase == "ready" and app.plugin.saves then readyForOther(a, who) end
  if not a or a.phase ~= "play" or not M.mayPlay(who) then return end
  a.touchedAt = nowMs()
  local action = app.plugin.view.actionAt(env.L, a.state, px, py)
  a.lastAction = action
  if action then applyInput(a, action) end
end

function M.press(index, who)
  local a = S.action
  if not a or a.phase ~= "play" or not M.mayPlay(who) then return end
  a.touchedAt = nowMs()
  local control = app.plugin.view.controls(env.L, a.state)[index]
  if control then applyInput(a, control.action) end
end

local function checkPresence(a, t)
  local player = a.player
  if player == "Player" or hw.isNear(player) then
    a.awaySince = nil
  else
    a.awaySince = a.awaySince or t
    if t - a.awaySince > LEFT_LIMIT_MS then
      if app.plugin.saves then pause(a) else finish() end
    end
  end
end

--- A question on the wall has to clear itself: in a long game, nothing else may redraw it.
local function clearLapsed(a, t)
  if a.newUntil and t >= a.newUntil then a.newUntil, S.dirty = nil, true end
  if a.phase ~= "play" then return end
  if a.quitUntil and t >= a.quitUntil then a.quitUntil, S.dirty = nil, true end
  if app.plugin.split and not a.hintDone and t - a.startedAt >= SPLIT_HINT_MS then a.hintDone, S.dirty = true, true end
end

--- A long game's own clock: autosave, and a player who has stopped playing gives the wall back, even if the detector
-- still sees them or there's no detector to ask.
local function keepRun(a, t)
  if t >= a.saveAt then
    a.saveAt = t + saves.AUTOSAVE_MS
    saveRun(a)
  end
  if t - a.touchedAt > config.GAME_IDLE * 1000 then
    pause(a)
    return false
  end
  return true
end

--- Save the run in play, if there is one, before something closes it. Not with the rules part way through a step: the
-- last autosave is better than a state that's half changed.
function M.saveNow()
  local a = S.action
  if a and app.plugin and app.plugin.saves then saveRun(a) end
end

--- Run the game's clock. Called on every tick of the shell.
function M.tick(t)
  local a = S.action
  if not a then return end
  local plugin = app.plugin
  if a.phase == "intro" then
    local changed, done = plugin.view.intro.step(a.intro, t, app)
    if done then introDone(a) elseif changed then S.dirty = true end
    return
  end
  if plugin.saves then clearLapsed(a, t) end
  if (a.phase == "ready" or a.phase == "players") and t - S.lastTouch > config.LOBBY_IDLE * 1000 then
    M.leave()
    return
  end
  if a.phase ~= "play" then return end
  local step = plugin.tickMs or 150
  local steps = 0
  a.midRules = true
  while t >= a.nextAt and steps < MAX_CATCH_UP and a.phase == "play" do
    steps = steps + 1
    a.nextAt = a.nextAt + step
    local events = plugin.rules.tick(a.state, a.rng)
    plugin.view.onEvents(app, a.state, events or {})
    if a.state.over then finish() end
  end
  a.midRules = nil
  if t >= a.nextAt then a.nextAt = t + step end -- too far behind to catch up: carry on from now
  if steps > 0 then S.dirty = true end
  if plugin.saves and (a.phase ~= "play" or not keepRun(a, t)) then return end
  checkPresence(a, t)
end

local function drawHeader(a)
  local W = env.W
  local s = a.state
  ui.small(a.player, 2, 1, C.line, C.bg, "left", 24)
  ui.small("BEST " .. math.max(a.scores:best(), s.score), 2, 3, C.line, C.bg, "left", 24)
  ui.text(s.score, floor(W / 2), 1, C.hi, "center")
  ui.small("LEVEL " .. (s.level or 1), W - 2, 1, C.line, C.bg, "right")
  if s.lives then
    ui.small((app.plugin.livesName or "LIVES") .. " " .. s.lives, W - 2, 3, s.lives <= 1 and C.warn or C.text, C.bg, "right")
  end
end

local function drawControls(a)
  local controls = app.plugin.view.controls(env.L, a.state)
  -- one size for the whole set, or some labels shout and the rest whisper
  local small = false
  for _, control in ipairs(controls) do
    small = small or ui.textWidth(control.label) > control.w - 2
  end
  for i, control in ipairs(controls) do
    ui.button("act", control.x, control.y, control.w, control.h, control.label, C.panel, { data = i, small = small })
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
  if not app.plugin.story then drawTable(a, 15) end
  local y = H - 22
  if a.saved then
    local asking = a.newUntil and nowMs() < a.newUntil
    local line = asking and "Tap again to lose your saved game" or a.saved.line
    ui.small(line, floor(W / 2), y - 3, asking and C.warn or C.text, C.bg, "center", W - 4)
    ui.button("actContinue", floor(W / 2) - 44, y, 50, 11, "CONTINUE", C.ok)
    ui.button("actNew", floor(W / 2) + 8, y, 36, 11, asking and "SURE?" or "NEW GAME", asking and C.warn or C.panel)
  else
    ui.button("actStart", floor(W / 2) - 25, y, 50, 11, "START", C.ok)
  end
  ui.button("back", 2, 1, 16, 7, "BACK", C.panel, { small = true })
  ui.button("rules", W - 18, 1, 16, 7, "HOW TO PLAY", C.panel, { small = true })
  if not app.oneGame then ui.button("actBoards", 2, H - 9, 24, 7, "OTHER GAMES", C.panel, { small = true }) end
  if app.plugin.saves and app.plugin.view.progress then
    ui.button("actPlayers", W - 18, H - 9, 16, 7, "PLAYERS", C.panel, { small = true })
  end
  app.drawToast()
end

--- "3 days ago", from a save's time.
local function ago(at)
  if not at then return "" end
  local mins = floor((os.epoch("utc") - at) / 60000)
  if mins < 2 then return "just now" end
  if mins < 60 then return mins .. " min ago" end
  local hours = floor(mins / 60)
  if hours < 24 then return hours .. (hours == 1 and " hour ago" or " hours ago") end
  local days = floor(hours / 24)
  return days .. (days == 1 and " day ago" or " days ago")
end

local function played(minutes)
  if minutes < 60 then return minutes .. " min" end
  return floor(minutes / 60) .. "h " .. (minutes % 60) .. "m"
end

local PLAYER_ROW_H = 6

local function drawPlayers(a)
  local W, H = env.W, env.H
  ui.text("PLAYERS", floor(W / 2), 2, C[app.plugin.color] or C.hi, "center")
  ui.small("Everyone's saved game on this cabinet", floor(W / 2), 10, C.line, C.bg, "center", W - 4)
  ui.button("actPlayersBack", 2, 1, 16, 7, "BACK", C.panel, { small = true })
  local rows = a.players or {}
  if #rows == 0 then
    ui.small("Nobody has a saved game here yet.", floor(W / 2), 20, C.text, C.bg, "center", W - 4)
    return
  end
  local fits = floor((H - 16) / PLAYER_ROW_H)
  for i, p in ipairs(rows) do
    if i > fits then
      ui.small("and " .. (#rows - fits) .. " more", floor(W / 2), H - 3, C.line, C.bg, "center")
      break
    end
    local y = 14 + (i - 1) * PLAYER_ROW_H
    ui.fill(2, y, W - 4, PLAYER_ROW_H - 1, C.panel)
    local name = p.player .. ((p.hero and p.hero ~= p.player) and (" (" .. p.hero .. ")") or "")
    ui.small(name, 4, y + 1, C.text, C.panel, "left", 46)
    ui.small("LV " .. p.level, 52, y + 1, C.hi, C.panel, "left")
    ui.small(p.percent .. "%", 62, y + 1, p.ended and C.ok or C.hi, C.panel, "left")
    ui.small(played(p.minutes or 0) .. " played", 70, y + 1, C.line, C.panel, "left")
    ui.small(ago(p.at), W - 4, y + 1, C.line, C.panel, "right")
    -- the share of the story as a bar, and where they are
    local barW = W - 8
    ui.fill(4, y + 3, barW, 1, C.bg)
    ui.fill(4, y + 3, floor(barW * p.percent / 100), 1, p.ended and C.ok or C.hi)
    local where = p.goal and (p.goal .. (p.place and (" - " .. p.place) or "")) or (p.place or "")
    ui.small(where, 4, y + 4, C.line, C.panel, "left", W - 8)
  end
end

--- What the end of a run says. A game that can be won sets s.won.
local function endLine(s)
  return s.won and "YOU WON!" or "GAME OVER"
end

local function drawOver(a)
  local W, H = env.W, env.H
  local s = a.state
  ui.text(endLine(s), floor(W / 2), 2, s.won and C.ok or C.warn, "center")
  ui.text(s.score, floor(W / 2), 11, C.hi, "center")
  local line = a.place == 1 and "A NEW HIGH SCORE!" or (a.place and ("Number " .. a.place .. " on the table") or (a.player .. ", level " .. (s.level or 1)))
  ui.small(line, floor(W / 2), 20, a.place and C.ok or C.line, C.bg, "center", W - 4)
  drawTable(a, 23)
  local y = H - 14
  ui.button("actStart", floor(W / 2) - 42, y, 40, 11, "AGAIN", C.ok)
  ui.button("actDone", floor(W / 2) + 2, y, 40, 11, "DONE", C.panel)
end

--- The last moment of the game, kept up until someone taps, so it can be looked over.
local function drawFinalBoard(a)
  local W = env.W
  drawHeader(a)
  app.plugin.view.draw(env.L, a.state)
  local y = floor(env.H / 2) - 6
  ui.fill(4, y, W - 8, 13, C.panel)
  ui.frame(4, y, W - 8, 13, C.warn, 1)
  ui.text(endLine(a.state), floor(W / 2), y + 2, a.state.won and C.ok or C.warn, "center")
  ui.small("TAP TO SEE THE SCORES", floor(W / 2), y + 10, C.text, C.panel, "center")
  ui.region("actSeen", 0, 0, W, env.H)
end

--- Draw whatever phase the run is in.
function M.draw()
  local a = S.action
  ui.screen():clear(C.bg, nil, " ")
  ui.clearButtons()
  if a.phase == "intro" then
    app.plugin.view.intro.draw(env.W, env.H, a.intro)
    ui.button("actSkip", env.W - 18, 1, 16, 7, "SKIP", C.panel, { small = true })
    app.drawToast()
  elseif a.phase == "ready" then
    drawReady(a)
  elseif a.phase == "players" then
    drawPlayers(a)
    app.drawToast()
  elseif a.phase == "over" then
    if a.reviewed then drawOver(a) else drawFinalBoard(a) end
  else
    if not app.plugin.story then drawHeader(a) end -- a story game has the whole wall, and no score to show
    app.plugin.view.draw(env.L, a.state)
    drawControls(a)
    if app.plugin.split and nowMs() - a.startedAt < SPLIT_HINT_MS then
      base.drawSplit(env.W, env.H, app.plugin.splitMiddle)
    end
    local asking = a.quitUntil and nowMs() < a.quitUntil
    local quit = app.plugin.saves and "SAVE & QUIT" or "QUIT"
    ui.button("actQuit", env.W - 14, env.H - 8, 12, 7, asking and "SURE?" or quit, asking and C.warn or C.panel, { small = true })
    app.drawToast()
  end
end

--- What the debug dump shows of a run, for tests.
function M.debug()
  local a = S.action
  local s = a.state
  return {
    phase = a.phase, reviewed = a.reviewed, player = a.player, place = a.place, best = a.scores:best(), table = #a.scores.rows,
    score = s and s.score, lives = s and s.lives, level = s and s.level, over = s and s.over,
    lastAction = a.lastAction, saveFor = a.saveOwner, saveLine = a.saved and a.saved.line,
  }
end

return M
