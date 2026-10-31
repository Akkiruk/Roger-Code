-- arcade.lua
-- One computer, every free game, on a monitor wall (built for 6x6 at text scale 0.5; adapts to other sizes).
-- The shell owns the wall: idle screen, game menu, lobby, match flow, results, stats and settings. Each game is a
-- plugin under games/ that brings its rules, computer player and board. One match runs at a time.
-- Peripherals: monitor (play + touch), speaker, playerDetector (who is nearby, who walked away), chatBox
-- (whispered results and reminders), redstone (turn lamps, celebration), a second monitor as scoreboard.

local audio = require("arcade_audio")
local config = require("arcade_config")
local hw = require("arcade_hw")
local matches = require("arcade_match")
local play = require("arcade_play")
local screens = require("arcade_screens")
local seats = require("arcade_seats")
local ui = require("arcade_ui")
local registry = require("games.registry")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local TICK = 0.1
local TOAST_MS = 4000

-- ------------------------------------------------------------------ logging

local function nowMs() return os.epoch("local") end

local function log(msg)
  local line = os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg)
  local h = fs.open(config.LOG_FILE, "a")
  if h then
    h.writeLine(line)
    h.close()
  end
  if fs.exists(config.LOG_FILE) and fs.getSize(config.LOG_FILE) > 60000 then
    if fs.exists(config.LOG_FILE .. ".bak") then fs.delete(config.LOG_FILE .. ".bak") end
    fs.move(config.LOG_FILE, config.LOG_FILE .. ".bak")
  end
end

-- ------------------------------------------------------------------ state

local S = {
  view = "idle",
  dirty = true,
  lastTouch = nowMs(),
  toast = nil,           -- { text, color, until }
  lobby = nil,
  match = nil,
  result = nil,
  stats = { metric = "elo", page = 1, mode = "leaders", player = nil },
  demo = {},
  confirm = nil,         -- { id, until } for two-tap actions
  debug = false,
}

local env = { W = 0, H = 0 }
local surfaceApi, font, screen
local stores = {}
local nextScoreboardAt = 0
local attractAt, attractIndex = 0, 1

local app = { S = S, env = env, log = log, audio = audio, signed = screens.signed }

local function setToast(text, color, ms)
  S.toast = { text = text, color = color or C.text, untilAt = nowMs() + (ms or TOAST_MS) }
  S.dirty = true
end
app.setToast = setToast

function app.drawToast()
  local t = S.toast
  if not t then return end
  if nowMs() > t.untilAt then S.toast = nil; return end
  local w = min(env.W - 4, #t.text + 6)
  local x = floor((env.W - w) / 2)
  local y = env.H - 9
  ui.fill(x, y, w, 7, C.panel)
  ui.frame(x, y, w, 7, t.color, 1)
  ui.small(t.text, floor(env.W / 2), y + 3, t.color, C.panel, "center", w - 2)
end

function app.pluginById(id)
  for _, plugin in ipairs(registry) do
    if plugin.id == id then return plugin end
  end
  return nil
end

local function storeFor(plugin)
  local store = stores[plugin.id]
  if not store then
    store = plugin.newStore({ log = log })
    store:load()
    stores[plugin.id] = store
  end
  return store
end

--- Make a game the current one: its records, sounds, accent and board layout.
function app.selectGame(plugin)
  app.plugin = plugin
  app.store = storeFor(plugin)
  audio.addSounds(plugin.sounds)
  hw.setChatTag(plugin.chatTag or config.NAME)
  local mon = env.monitor
  if mon then mon.setPaletteColor(colors.yellow, plugin.accent) end
  if env.W > 0 then env.L = plugin.view.layout(env.W, env.H) end
end

-- ------------------------------------------------------------------ preferences

local PREF_DEFAULTS = { sound = true, volume = 1.0, announce = true, redstone = true }

--- Preferences for the whole computer. On a wall that ran the old package, they start from what it saved.
local function loadPrefs()
  local prefs = {}
  for k, v in pairs(PREF_DEFAULTS) do prefs[k] = v end
  local saved
  if fs.exists(config.PREFS_FILE) then
    local h = fs.open(config.PREFS_FILE, "r")
    if h then
      local ok, value = pcall(textutils.unserialise, h.readAll() or "")
      h.close()
      if ok then saved = value end
    end
  end
  saved = saved or (app.store and app.store.data.settings) or {}
  for k in pairs(PREF_DEFAULTS) do
    if saved[k] ~= nil then prefs[k] = saved[k] end
  end
  return prefs
end

local function savePrefs()
  local tmp = config.PREFS_FILE .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return end
  h.write(textutils.serialise(app.prefs))
  h.close()
  if fs.exists(config.PREFS_FILE) then fs.delete(config.PREFS_FILE) end
  fs.move(tmp, config.PREFS_FILE)
end

-- ------------------------------------------------------------------ display

local function setupDisplay()
  local mon, monName = hw.monitor()
  if not mon then return false, "no monitor attached" end
  if mon.setTextScale then mon.setTextScale(config.TEXT_SCALE) end
  for name, hex in pairs(config.PALETTE) do
    if colors[name] then mon.setPaletteColor(colors[name], hex) end
  end
  mon.setBackgroundColor(colors.black)
  mon.clear()
  env.W, env.H = mon.getSize()
  env.monitor, env.monitorName = mon, monName
  surfaceApi = surfaceApi or dofile("surface")
  font = font or surfaceApi.loadFont(surfaceApi.load("font"))
  screen = surfaceApi.create(env.W, env.H)
  ui.init(surfaceApi, font, screen)
  if app.plugin then app.selectGame(app.plugin) end

  -- optional scoreboard monitor
  local sb, sbName = hw.scoreboard()
  env.board2 = nil
  if sb then
    if sb.setTextScale then sb.setTextScale(config.TEXT_SCALE) end
    for name, hex in pairs(config.PALETTE) do
      if colors[name] then sb.setPaletteColor(colors[name], hex) end
    end
    local w, h = sb.getSize()
    env.board2 = { mon = sb, name = sbName, W = w, H = h, surf = surfaceApi.create(w, h) }
  end
  return true
end

-- ------------------------------------------------------------------ lobby

local function lobbyDefaults(who)
  local lobby = { red = nil, blue = nil, picking = "red", first = app.store:setting("first") or "red", page = 1 }
  if who then
    lobby.red = { name = who }
    lobby.picking = "blue"
  end
  return lobby
end

local function openLobby(who)
  S.lobby = S.lobby or lobbyDefaults(who)
  S.view = "lobby"
  S.lastTouch = nowMs()
  S.dirty = true
end

--- Past the idle screen: the game menu when there is a choice, otherwise straight to the lobby.
local function openFront(who)
  if #registry > 1 then
    -- the menu belongs to no game, so it wears the Arcade's own accent
    if env.monitor then env.monitor.setPaletteColor(colors.yellow, config.PALETTE.yellow) end
    S.view = "menu"
    S.lastTouch = nowMs()
    S.dirty = true
  else
    openLobby(who)
  end
end

local function assignSlot(slot)
  local l = S.lobby
  local picking = l.picking
  -- the same person cannot hold both colours
  if slot.name and not slot.cpu and not slot.guest then
    local other = picking == "red" and l.blue or l.red
    if other and other.name == slot.name then
      if picking == "red" then l.blue = nil else l.red = nil end
    end
  end
  l[picking] = slot
  if picking == "red" then
    l.picking = (not l.blue) and "blue" or "red"
  else
    l.picking = (not l.red) and "red" or "blue"
  end
  audio.play("select")
  S.dirty = true
end

local function startFromLobby()
  local l = S.lobby
  if not (l.red and l.blue) then
    audio.play("error")
    setToast("Pick both players first", C.warn)
    return
  end
  local first
  if l.first == "random" then first = math.random(2) elseif l.first == "blue" then first = 2 else first = 1 end
  local red, blue = l.red, l.blue
  S.lobby = nil
  matches.start(red, blue, { first = first })
end

-- ------------------------------------------------------------------ idle and menu

--- A computer's action for the demo game, or any legal one.
local function demoChoose(state, level, opts)
  local action = app.plugin.chooseAction(state, level, opts)
  if action then return action end
  local actions = app.plugin.rules.legalActions(state)
  return actions[math.random(#actions)]
end

local function drawIdle()
  screen:clear(C.bg, nil, " ")
  local W, H = env.W, env.H
  local py = app.plugin.view.drawAttract(W, H, S.demo, app.store)
  if floor(nowMs() / 700) % 2 == 0 then ui.text("TOUCH TO PLAY", floor(W / 2), py, C.text, "center") end
  local near = hw.nearby()
  local line = #near > 0 and (#near .. " player" .. (#near == 1 and "" or "s") .. " nearby") or "Two players or play the computer"
  ui.small(line, floor(W / 2), py + font.height + 2, C.line, C.bg, "center", W - 2)
  ui.region("play", 0, 0, W, H)
end

local function drawMenu()
  screen:clear(C.bg, nil, " ")
  ui.clearButtons()
  local W, H = env.W, env.H
  ui.text(config.NAME, floor(W / 2), 2, C.hi, "center")
  ui.small("Free to play - pick a game", floor(W / 2), 10, C.line, C.bg, "center", W - 2)
  ui.button("back", 2, 1, 16, 7, "BACK", C.panel, { small = true })
  local rows = #registry
  local rowH = max(7, min(14, floor((H - 24) / rows) - 2))
  for i, plugin in ipairs(registry) do
    local y = 13 + (i - 1) * (rowH + 2)
    local size = plugin.minSize
    local fits = not size or (W >= size.w and H >= size.h)
    local color = C[plugin.color] or C.hi
    ui.button("game", 6, y, W - 12, rowH, fits and plugin.title or (plugin.title .. " (wall too small)"), C.panel,
      { data = plugin.id, enabled = fits, frame = fits and color or nil, small = rowH < font.height + 2 })
    if plugin.blurb and rowH >= font.height + 4 then
      ui.small(plugin.blurb, floor(W / 2), y + rowH - 2, C.line, C.panel, "center", W - 14)
    end
  end
  app.drawToast()
end

-- ------------------------------------------------------------------ render + debug dump

local function writeDebug()
  if not fs.exists(config.DEBUG_FLAG) then return end
  local g = S.match
  local L = env.L
  local d = {
    view = S.view, W = env.W, H = env.H, game_id = app.plugin and app.plugin.id,
    buttons = {}, layout = L and { x0 = L.x0, y0 = L.y0, cw = L.cw, ch = L.ch, colX = L.colX, rowY = L.rowY, side = L.side, L = L.debug } or nil,
  }
  for _, b in ipairs(ui.buttons()) do
    d.buttons[#d.buttons + 1] = { id = b.id, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label, enabled = b.enabled, data = b.data }
  end
  if g then
    d.game = app.plugin.view.debug(g)
    d.game.red, d.game.blue, d.game.redCpu, d.game.blueCpu = g.red.name, g.blue.name, g.red.cpu, g.blue.cpu
    d.game.redGuest, d.game.blueGuest = g.red.guest, g.blue.guest
    d.game.deadline, d.game.paused, d.game.id, d.game.abandonBy = g.deadline, g.paused, g.id, g.abandonBy
  end
  if S.result then d.result = { winner = S.result.winner, moves = S.result.moves, ranked = S.result.ranked } end
  if S.lobby then d.lobby = { red = S.lobby.red and S.lobby.red.name, blue = S.lobby.blue and S.lobby.blue.name } end
  d.players = {}
  for _, p in pairs(app.store.data.players) do
    d.players[#d.players + 1] = {
      name = p.name, elo = p.elo, games = p.games, wins = p.wins, losses = p.losses, draws = p.draws, streak = p.streak,
      cpu = p.vsCpu, achievements = p.achievements, h2h = p.h2h,
    }
  end
  d.history = #app.store.data.history
  d.settings = {}
  for k, v in pairs(app.store.data.settings) do d.settings[k] = v end
  for k, v in pairs(app.prefs) do d.settings[k] = v end
  d.toast = S.toast and S.toast.text or nil
  d.ticks, d.tickAt, d.now = S.ticks, S.tickAt, nowMs()
  d.awaySince = g and g.awaySince or nil
  d.sound = audio.isAvailable()
  local h = fs.open("arcade_ui.tmp", "w")
  if h then
    h.write(textutils.serialiseJSON(d))
    h.close()
    if fs.exists("arcade_ui.dat") then fs.delete("arcade_ui.dat") end
    fs.move("arcade_ui.tmp", "arcade_ui.dat")
  end
end

local function render()
  S.dirty = false
  ui.setScreen(screen)
  if S.view == "idle" then
    ui.clearButtons()
    drawIdle()
  elseif S.view == "menu" then drawMenu()
  elseif S.view == "lobby" then screens.drawLobby()
  elseif S.view == "game" then play.draw(S.match)
  elseif S.view == "final" then play.draw(S.finalMatch, true)
  elseif S.view == "result" then screens.drawResult()
  elseif S.view == "stats" then screens.drawStats()
  elseif S.view == "settings" then screens.drawSettings()
  end
  if env.monitor then screen:output(env.monitor, 0, 0) end
  writeDebug()
  if nowMs() >= nextScoreboardAt then
    nextScoreboardAt = nowMs() + 2000
    screens.drawScoreboard()
  end
end
app.render = render

-- ------------------------------------------------------------------ input

local function cycle(list, current)
  for i, v in ipairs(list) do
    if v == current then return list[i % #list + 1] end
  end
  return list[1]
end

local function toStats(mode, player)
  S.stats.mode = mode or "leaders"
  S.stats.player = player
  S.stats.page = 1
  S.prevView = S.view ~= "stats" and S.view or S.prevView
  S.view = "stats"
  S.dirty = true
end

local function backFromStats()
  local v = S.prevView
  S.prevView = nil
  if v == "result" and S.result then S.view = "result"
  elseif v == "lobby" and S.lobby then S.view = "lobby"
  else S.view = "idle" end
  S.dirty = true
end

local function refuse(text, ms)
  audio.play("error")
  setToast(text, C.warn, ms or 2500)
end

local function handleBoardTouch(px, py, who)
  local g = S.match
  local L = env.L
  if not g or g.paused or g.state.winner ~= 0 then return end
  local mover = matches.moverSlot(g)
  if mover.cpu then
    audio.play("error")
    setToast("The computer is thinking...", C.info, 1200)
    return
  end
  local plugin = app.plugin
  local action = plugin.view.actionAt(L, g, px, py)
  if not action then return end
  local allowed, msg = seats.mayMove(g, mover, who)
  if not allowed then
    refuse(msg)
    return
  end
  local ok, why = plugin.rules.checkAction(g.state, action)
  if not ok then
    refuse(plugin.view.refusal(g.state, why), 2000)
    return
  end
  g.confirmResign = false
  matches.apply(g, action)
end

--- May this touch use a match control? Says why not on the wall.
local function controlAllowed(g, who)
  local allowed, msg = seats.mayControl(g, who)
  if not allowed then refuse(msg) end
  return allowed
end

local handlers = {}

handlers.play = function(_, who) openFront(who) end

handlers.game = function(b, who)
  local plugin = app.pluginById(b.data)
  if not plugin then return end
  audio.play("select")
  app.selectGame(plugin)
  S.demo = {}
  S.lobby = nil
  openLobby(who)
end

handlers.skipFinal = function()
  S.view = "result"
  S.lastTouch = nowMs()
  audio.play("tap")
  S.dirty = true
end

handlers.redSlot = function()
  S.lobby.picking = "red"; S.lobby.red = nil; audio.play("tap"); S.dirty = true
end
handlers.blueSlot = function()
  S.lobby.picking = "blue"; S.lobby.blue = nil; audio.play("tap"); S.dirty = true
end
handlers.player = function(b, who)
  if S.view == "stats" then
    audio.play("page")
    toStats("player", b.data)
    return
  end
  local allowed, msg = seats.maySit(b.data, who)
  if not allowed then
    refuse(msg)
    return
  end
  assignSlot({ name = b.data })
end
handlers.cpu = function(b)
  assignSlot({ name = "CPU " .. string.upper(b.data:sub(1, 1)) .. b.data:sub(2), cpu = b.data })
end
handlers.guest = function()
  local l = S.lobby
  local n = 1
  local taken = {}
  if l.red then taken[l.red.name] = true end
  if l.blue then taken[l.blue.name] = true end
  while taken["Guest " .. n] do n = n + 1 end
  assignSlot({ name = "Guest " .. n, guest = true })
end
handlers.swap = function()
  local l = S.lobby
  l.red, l.blue = l.blue, l.red
  audio.play("tap")
  S.dirty = true
end
handlers.page = function()
  local l = S.lobby
  local pages = max(1, math.ceil(#hw.nearby() / 6))
  l.page = l.page % pages + 1
  audio.play("page")
  S.dirty = true
end
handlers.start = function() startFromLobby() end
handlers.options = function()
  -- cycle who moves first; everything else lives in settings
  local l = S.lobby
  l.first = cycle({ "red", "blue", "random" }, l.first)
  app.store:setting("first", l.first)
  audio.play("tap")
  S.dirty = true
end
handlers.back = function()
  audio.play("back")
  if S.view == "stats" then backFromStats()
  elseif S.view == "settings" then
    app.store:save()
    savePrefs()
    S.view = "stats"; S.dirty = true
  else
    S.view = "idle"; S.lobby = nil; S.dirty = true
  end
end
handlers.stats = function() audio.play("select"); toStats("leaders") end
handlers.tab = function(b) audio.play("page"); S.stats.mode = b.data; S.stats.page = 1; S.dirty = true end
handlers.metric = function(b) audio.play("page"); S.stats.metric = b.data; S.stats.page = 1; S.dirty = true end
handlers.prevPage = function() audio.play("page"); S.stats.page = max(1, S.stats.page - 1); S.dirty = true end
handlers.nextPage = function() audio.play("page"); S.stats.page = S.stats.page + 1; S.dirty = true end
handlers.settings = function() audio.play("select"); S.view = "settings"; S.dirty = true end

handlers.menu = function(_, who)
  local g = S.match
  if g and controlAllowed(g, who) then
    g.paused = true
    g.pausedAt = nowMs()
    g.abandonBy = nil
    audio.play("tap")
    S.dirty = true
  end
end
handlers.resume = function(_, who)
  local g = S.match
  if g and controlAllowed(g, who) then
    matches.resume(g)
    audio.play("select")
  end
end
handlers.abandon = function(_, who)
  local g = S.match
  if not g or not controlAllowed(g, who) then return end
  -- A rated match only ends for free if both agree: otherwise stopping would be a way out of a losing game.
  if seats.isRated(g) and who ~= nil and g.abandonBy ~= nil and g.abandonBy ~= who then
    matches.abandon(g, "both agreed")
  elseif seats.isRated(g) and who ~= nil then
    g.abandonBy = who
    audio.play("tap")
    setToast("The other player taps to agree", C.info, 3000)
  else
    matches.abandon(g, "menu")
  end
end
handlers.hint = function(_, who)
  local g = S.match
  if not g or g.paused or matches.moverSlot(g).cpu then return end
  if not controlAllowed(g, who) then return end
  local action = app.plugin.chooseAction(g.state, "hard", { ms = 600 })
  if action then
    g.hint, g.hintUntil = action, nowMs() + 4000
    g.hints[g.state.turn] = g.hints[g.state.turn] + 1
    audio.play("hint")
    setToast(app.plugin.view.hintText(action), C.ok, 3000)
  end
end
handlers.resign = function(_, who)
  local g = S.match
  if not g or g.paused or not controlAllowed(g, who) then return end
  if not g.confirmResign then
    g.confirmResign = true
    g.confirmUntil = nowMs() + 4000
    audio.play("tap")
    S.dirty = true
    return
  end
  audio.cue("resign")
  matches.forfeit(g, seats.resigner(g, who, g.state.turn), "resign")
end
handlers.sound = function()
  app.prefs.sound = not app.prefs.sound
  savePrefs()
  audio.setEnabled(app.prefs.sound)
  if app.prefs.sound then audio.play("select") end
  S.dirty = true
end

-- settings buttons
handlers.vol = function()
  local v = app.prefs.volume
  v = (v >= 2 and 0.25) or (v + 0.25)
  app.prefs.volume = v
  audio.setVolume(v)
  audio.play("tap")
  S.dirty = true
end
handlers.announce = function() app.prefs.announce = not app.prefs.announce; audio.play("tap"); S.dirty = true end
handlers.redstone = function()
  app.prefs.redstone = not app.prefs.redstone
  hw.setRedstone(app.prefs.redstone)
  hw.allOff()
  audio.play("tap"); S.dirty = true
end
handlers.testsound = function()
  audio.play("start")
  audio.later("tap", 300); audio.later("select", 520); audio.later("win", 1100); audio.later("lose", 2400)
  setToast("Playing sound test", C.info, 2000)
end
handlers.wipe = function()
  if S.confirm and S.confirm.id == "wipe" and nowMs() < S.confirm.untilAt then
    app.store:reset()
    app.store:save()
    S.confirm = nil
    audio.play("resign")
    setToast("All records wiped", C.warn)
  else
    S.confirm = { id = "wipe", untilAt = nowMs() + 5000 }
    audio.play("tap")
  end
  S.dirty = true
end

-- result screen
handlers.rematch = function()
  local r = S.result
  if not r then return end
  -- colours swap, and whoever lost moves first (the old Red losing means they are now Blue)
  local first = (r.winner == 2) and 2 or 1
  S.result = nil
  matches.start(r.blue, r.red, { first = first })
end
handlers.newgame = function(_, who)
  S.result = nil
  S.lobby = nil
  hw.allOff()
  openFront(who)
end
handlers.done = function()
  S.result = nil
  S.lobby = nil
  hw.allOff()
  S.view = "idle"
  S.dirty = true
end

local function onTouch(side, x, y, who)
  S.lastTouch = nowMs()
  if side ~= env.monitorName then return end
  local px, py = x - 1, y - 1
  if S.view == "idle" then
    audio.play("select")
    openFront(who)
    return
  end
  local b = ui.hit(px, py)
  if b and handlers[b.id] then
    -- two-tap confirmations expire
    if b.id ~= "resign" and S.match then S.match.confirmResign = false end
    handlers[b.id](b, who)
    S.dirty = true
    return
  end
  if b and S.view == "settings" then
    app.plugin.changeSetting(app.store, b.id, cycle)
    audio.play("tap")
    S.dirty = true
    return
  end
  if S.view == "game" then handleBoardTouch(px, py, who) end
end

-- ------------------------------------------------------------------ periodic work

local function attractStep(t)
  if #registry > 1 and t >= attractAt then
    attractAt = t + config.ATTRACT_SWAP * 1000
    attractIndex = attractIndex % #registry + 1
    app.selectGame(registry[attractIndex])
    S.demo = {}
    S.dirty = true
  end
  if app.plugin.view.demoStep(S.demo, t, demoChoose) then S.dirty = true end
  if floor(t / 700) ~= S.blinkPhase then S.blinkPhase = floor(t / 700); S.dirty = true end
end

local function onTick()
  local t = nowMs()
  audio.pump()
  if S.toast and t > S.toast.untilAt then S.toast = nil; S.dirty = true end
  if S.celebrateUntil and t > S.celebrateUntil then
    S.celebrateUntil = nil
    hw.celebrate(false)
  end

  if S.view == "final" then
    if t > (S.finalUntil or 0) then
      S.view = "result"
      S.lastTouch = t
      S.dirty = true
    end
  elseif S.view == "idle" then
    attractStep(t)
  elseif S.view == "menu" then
    if t - S.lastTouch > config.LOBBY_IDLE * 1000 then
      S.view = "idle"; S.dirty = true
    end
  elseif S.view == "lobby" then
    if t - S.lastTouch > config.LOBBY_IDLE * 1000 then
      S.view = "idle"; S.lobby = nil; S.dirty = true
    end
    if floor(t / 2000) ~= S.nearPhase then S.nearPhase = floor(t / 2000); S.dirty = true end
  elseif S.view == "result" then
    if t - S.lastTouch > config.RESULT_IDLE * 1000 then
      S.result = nil; hw.allOff(); S.view = "idle"; S.dirty = true
    end
  elseif S.view == "stats" or S.view == "settings" then
    if t - S.lastTouch > config.LOBBY_IDLE * 1000 then
      S.view = "idle"; S.lobby = nil; S.dirty = true
    end
  elseif S.view == "game" and S.match then
    matches.tick(S.match, t)
  end
end

-- ------------------------------------------------------------------ startup

local function shutdown()
  hw.allOff()
  if env.monitor then
    env.monitor.setBackgroundColor(colors.black)
    env.monitor.clear()
  end
  app.store:save()
  savePrefs()
end

local function main()
  screens.bind(app)
  matches.bind(app)
  play.bind(app)
  local rep = hw.init()
  -- peripherals can attach a moment after the computer boots; give the optional ones a short window
  for _ = 1, 8 do
    if rep.monitor and rep.speaker and (rep.detector or rep.chat) then break end
    os.sleep(0.1)
    rep = hw.init()
  end
  log("hardware: monitor=" .. tostring(rep.monitor) .. " scoreboard=" .. tostring(rep.scoreboard) .. " speaker=" .. tostring(rep.speaker)
    .. " detector=" .. tostring(rep.detector) .. " chat=" .. tostring(rep.chat))
  local ok, err = setupDisplay()
  if not ok then error(err, 0) end
  app.selectGame(registry[1])
  app.prefs = loadPrefs()
  audio.init(rep.speaker)
  audio.setEnabled(app.prefs.sound)
  audio.setVolume(app.prefs.volume)
  hw.setRedstone(app.prefs.redstone)
  audio.play("boot")
  hw.allOff()
  S.debug = fs.exists(config.DEBUG_FLAG)
  if not matches.recover() then
    S.view = "idle"
  end

  -- The clock is a timer, and a lost timer stops it for good (the computer opponent then never moves). Timers are lost
  -- to server-thread peripheral calls, which is why those live in hw.worker. As a second line of defence there are two
  -- timers, any other event runs an overdue tick, and a gap of more than 1.5 s is logged.
  local tickA, tickB
  local lastTickAt = nowMs()
  local toucher = nil -- vhcc_touch always comes just before the monitor_touch it belongs to
  local function armTicks()
    if tickA then os.cancelTimer(tickA) end
    if tickB then os.cancelTimer(tickB) end
    tickA = os.startTimer(TICK)
    tickB = os.startTimer(TICK * 4)
  end
  local function runTick(why)
    local now = nowMs()
    local gap = now - lastTickAt
    if gap > 1500 then log(string.format("tick gap %d ms (resumed by %s)", gap, why)) end
    lastTickAt = now
    S.ticks = (S.ticks or 0) + 1
    S.tickAt = now
    armTicks()
    local okTick, errTick = pcall(onTick)
    if not okTick then log("tick error: " .. tostring(errTick)); error(errTick, 0) end
  end
  hw.pollDetector() -- nothing to lose yet: the game loop has not started
  armTicks()
  render()
  local function gameLoop()
   while true do
    local ev, a, b, c = os.pullEventRaw()
    if ev == "terminate" then
      shutdown()
      error("Terminated", 0)
    elseif ev == "timer" then
      if a == tickA or a == tickB then runTick(a == tickA and "timer" or "spare timer") end
    elseif ev == "vhcc_touch" then
      toucher = a
      hw.noteToucher(a)
    elseif ev == "monitor_touch" then
      local who = toucher
      toucher = nil
      onTouch(a, b, c, who)
    elseif ev == "monitor_resize" then
      if a == env.monitorName then
        setupDisplay()
        S.dirty = true
      end
    elseif ev == "peripheral" or ev == "peripheral_detach" then
      hw.init()
      local sp = hw.speakerName()
      if sp then audio.init(sp) end
      if ev == "peripheral_detach" and a == env.monitorName then
        setupDisplay()
      end
      S.dirty = true
    end
    if nowMs() - lastTickAt > 400 then runTick("event " .. tostring(ev)) end
    if S.dirty then render() end
   end
  end
  parallel.waitForAny(gameLoop, hw.worker)
end

local ok, err = pcall(main)
if not ok then
  log("fatal: " .. tostring(err))
  pcall(function() if app.store then app.store:save() end end)
  pcall(hw.allOff)
  error(err, 0)
end
