-- uttt.lua
-- Ultimate Tic-Tac-Toe on a monitor wall (built for 6x6 at text scale 0.5; adapts to other sizes).
-- Peripherals: monitor (play + touch), speaker, playerDetector (who is nearby, who walked away), chatBox
-- (announcements and turn reminders), redstone (turn lamps, celebration), a second monitor as scoreboard.
-- Players are Red (X) and Blue (O). Ratings, leaderboards, head-to-head and achievements persist.

local config = require("uttt_config")
local rules = require("uttt_rules")
local ai = require("uttt_ai")
local Store = require("uttt_store")
local audio = require("uttt_audio")
local hw = require("uttt_hw")
local ui = require("uttt_ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local TICK = 0.1
local AI_THINK_MS = 700       -- minimum "thinking" time so a computer move does not feel instant
local FLASH_MS = 350
local TOAST_MS = 4000
local FINAL_HOLD_MS = 3500    -- how long the finished board stays up before the results page

-- ------------------------------------------------------------------ logging

local function nowMs() return os.epoch("local") end
local function utcMs() return os.epoch("utc") end

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

local store = Store.new({ path = config.DATA_FILE, log = log })

local S = {
  view = "idle",
  dirty = true,
  lastTouch = nowMs(),
  toast = nil,           -- { text, color, until }
  lobby = nil,
  game = nil,
  result = nil,
  stats = { metric = "elo", page = 1, mode = "leaders", player = nil },
  demo = nil,
  confirm = nil,         -- { id, until } for two-tap actions
  debug = false,
}

local env = { W = 0, H = 0 }
local screen, surfaceApi, font
local board2 -- scoreboard surface info
local nextScoreboardAt = 0

-- ------------------------------------------------------------------ helpers

local function setToast(text, color, ms)
  S.toast = { text = text, color = color or C.text, untilAt = nowMs() + (ms or TOAST_MS) }
  S.dirty = true
end

local function fmtDuration(sec)
  sec = floor(sec or 0)
  if sec >= 3600 then return string.format("%dh%02dm", floor(sec / 3600), floor(sec % 3600 / 60)) end
  return string.format("%d:%02d", floor(sec / 60), sec % 60)
end

local function signed(n)
  if n > 0 then return "+" .. n end
  return tostring(n)
end

local function slotLabel(slot)
  return slot and slot.name or "?"
end

local function isHuman(slot) return slot and not slot.cpu and not slot.guest end

--- Whisper a message to each human in the list, once per name. Nothing is ever sent to public chat.
local function tellPlayers(slots, text)
  local seen = {}
  for _, slot in ipairs(slots) do
    if isHuman(slot) and not seen[slot.name] then
      seen[slot.name] = true
      hw.tell(slot.name, text)
    end
  end
end

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
  env.L = ui.layout(env.W, env.H)

  -- optional scoreboard monitor
  local sb, sbName = hw.scoreboard()
  board2 = nil
  if sb then
    if sb.setTextScale then sb.setTextScale(config.TEXT_SCALE) end
    for name, hex in pairs(config.PALETTE) do
      if colors[name] then sb.setPaletteColor(colors[name], hex) end
    end
    local w, h = sb.getSize()
    board2 = { mon = sb, name = sbName, W = w, H = h, surf = surfaceApi.create(w, h) }
  end
  return true
end

-- ------------------------------------------------------------------ persistence of the running game

local function saveGame()
  local g = S.game
  if not g then
    if fs.exists(config.SAVE_FILE) then fs.delete(config.SAVE_FILE) end
    return
  end
  local data = {
    red = g.red, blue = g.blue, moves = rules.moveList(g.state), tiebreak = g.state.tiebreak, first = g.first,
    elapsed = g.elapsed + (nowMs() - g.resumedAt) / 1000, timeouts = g.timeouts, trailed = g.trailed, timer = g.timer,
    hints = g.hints,
  }
  local tmp = config.SAVE_FILE .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return end
  h.write(textutils.serialise(data))
  h.close()
  if fs.exists(config.SAVE_FILE) then fs.delete(config.SAVE_FILE) end
  fs.move(tmp, config.SAVE_FILE)
end

local function clearSavedGame()
  if fs.exists(config.SAVE_FILE) then fs.delete(config.SAVE_FILE) end
end

-- ------------------------------------------------------------------ game flow

local startGame, finishGame, applyMove, afterMove

local function newGameRecord(red, blue, opts)
  opts = opts or {}
  local first = opts.first or 1
  local state = rules.new({ tiebreak = store:setting("tiebreak"), first = first })
  return {
    red = red, blue = blue, state = state, first = first, timer = store:setting("timer") or 0,
    startedAt = nowMs(), resumedAt = nowMs(), elapsed = 0,
    moveStart = nowMs(), deadline = nil, timeouts = { 0, 0 }, trailed = { 0, 0 }, hints = { 0, 0 },
    last = nil, flash = nil, hint = nil, hintUntil = 0, paused = false, nudged = false,
    awaySince = nil, aiAt = nil, thinking = false, confirmResign = false,
  }
end

local function moverSlot(g)
  return g.state.turn == 1 and g.red or g.blue
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

startGame = function(red, blue, opts)
  opts = opts or {}
  local first = opts.first or 1
  S.game = newGameRecord(red, blue, { first = first })
  S.result = nil
  S.view = "game"
  S.demo = nil
  audio.cue("start")
  armTurn(S.game)
  log(string.format("game start: red=%s(%s) blue=%s(%s) first=%d timer=%d tiebreak=%s", red.name, tostring(red.cpu), blue.name,
    tostring(blue.cpu), first, S.game.timer, tostring(S.game.state.tiebreak)))
  saveGame()
  if store:setting("announce") and (isHuman(red) or isHuman(blue)) then
    tellPlayers({ red, blue }, string.format("%s (Red) vs %s (Blue) - Ultimate Tic-Tac-Toe is on!", red.name, blue.name))
  end
  S.dirty = true
end

local function rankText(name)
  local rank, total = store:rank(name, "elo")
  if rank then return "#" .. rank end
  return "-"
end

finishGame = function(reason)
  local g = S.game
  local s = g.state
  local winner = s.winner
  local seconds = g.elapsed + (nowMs() - g.resumedAt) / 1000
  local ranked = isHuman(g.red) or isHuman(g.blue)
  local anyGuest = g.red.guest or g.blue.guest
  local before = {
    red = isHuman(g.red) and store:rank(g.red.name, "elo") or nil,
    blue = isHuman(g.blue) and store:rank(g.blue.name, "elo") or nil,
  }
  local summary
  if ranked and not anyGuest then
    summary = store:record({
      red = g.red.name, blue = g.blue.name, redCpu = g.red.cpu, blueCpu = g.blue.cpu, winner = winner,
      moves = s.moves, seconds = seconds, boardsRed = s.boards[1], boardsBlue = s.boards[2],
      trailed = winner == 1 and g.trailed[1] or g.trailed[2], forfeit = s.forfeit,
    })
    store:save()
  else
    summary = { ranked = false, achievements = {}, red = { name = g.red.name }, blue = { name = g.blue.name } }
  end
  local after = {
    red = isHuman(g.red) and not anyGuest and store:rank(g.red.name, "elo") or nil,
    blue = isHuman(g.blue) and not anyGuest and store:rank(g.blue.name, "elo") or nil,
  }
  S.result = {
    red = g.red, blue = g.blue, winner = winner, moves = s.moves, seconds = seconds, boards = { s.boards[1], s.boards[2] },
    forfeit = s.forfeit, summary = summary, rankBefore = before, rankAfter = after, reason = reason, state = s,
    ranked = summary.ranked, guest = anyGuest, at = utcMs(),
  }
  -- show the finished board and the winning line first, then the results page
  S.finalGame = g
  S.finalUntil = nowMs() + FINAL_HOLD_MS
  S.view = "final"
  S.toast = nil
  S.lastTouch = nowMs()
  clearSavedGame()
  hw.lamps(winner == 1, winner == 2)
  hw.celebrate(winner == 1 or winner == 2)
  S.celebrateUntil = nowMs() + 4000

  -- sound: the winner's side decides the cue; against a computer, the human's result decides
  local human = isHuman(g.red) and 1 or (isHuman(g.blue) and 2 or nil)
  if winner == 3 then
    audio.cue("draw")
  elseif human and not (isHuman(g.red) and isHuman(g.blue)) then
    audio.cue(winner == human and "win" or "lose")
  else
    audio.cue("win")
  end
  for _, a in ipairs(summary.achievements or {}) do
    audio.later("achievement", 1600, 1, 1)
    break
  end
  if summary.ranked and (after.red or after.blue) then
    local moved = (before.red and after.red and after.red < before.red) or (before.blue and after.blue and after.blue < before.blue)
    if moved then audio.later("rank", 2000, 0.8, 1.1) end
  end

  if store:setting("announce") and (isHuman(g.red) or isHuman(g.blue)) then
    local text
    if winner == 3 then
      text = string.format("%s and %s drew Ultimate Tic-Tac-Toe!", g.red.name, g.blue.name)
    else
      local w, l = winner == 1 and g.red or g.blue, winner == 1 and g.blue or g.red
      text = string.format("%s beat %s at Ultimate Tic-Tac-Toe in %d moves (%d-%d boards)%s", w.name, l.name, s.moves,
        s.boards[winner], s.boards[3 - winner], s.forfeit and " by forfeit" or "")
      local sw = summary[winner == 1 and "red" or "blue"]
      if summary.ranked and sw and sw.elo then text = text .. string.format(" [%d %s]", sw.elo, signed(sw.delta or 0)) end
    end
    tellPlayers({ g.red, g.blue }, text)
    for _, a in ipairs(summary.achievements or {}) do
      hw.tell(a.player, "You unlocked '" .. a.name .. "'!")
    end
  end
  log(string.format("game end: winner=%d moves=%d boards=%d-%d forfeit=%s ranked=%s", winner, s.moves, s.boards[1], s.boards[2], tostring(s.forfeit), tostring(summary.ranked)))
  S.game = nil
  S.dirty = true
end

afterMove = function(g, b, c, mover)
  local s = g.state
  g.last = { b, c }
  g.flash = { b = b, c = c, on = true, untilAt = nowMs() + FLASH_MS }
  -- track the largest deficit each player has been in (for the comeback achievement)
  g.trailed[1] = max(g.trailed[1], s.boards[2] - s.boards[1])
  g.trailed[2] = max(g.trailed[2], s.boards[1] - s.boards[2])

  local captured = s.sub[b] == mover
  if s.winner ~= 0 then return end
  if captured then
    audio.cue("capture", mover)
    setToast(string.format("%s takes board %d!", slotLabel(mover == 1 and g.red or g.blue), b), mover == 1 and C.red or C.blue, 2500)
  else
    audio.cue("move", mover)
  end
  if s.forced == nil then
    audio.later("freeMove", 160)
  else
    audio.later("force", 140)
    -- warn when the mover is sent to a board the opponent... or themselves can take
    if rules.canWinBoard(s, s.forced, s.turn) then audio.later("threat", 320) end
  end
end

applyMove = function(g, b, c, why)
  local s = g.state
  local mover = s.turn
  local ok, err = rules.play(s, b, c)
  if not ok then return false, err end
  afterMove(g, b, c, mover)
  if s.winner ~= 0 then
    saveGame()
    finishGame(why or "played")
    return true
  end
  armTurn(g)
  saveGame()
  S.dirty = true
  return true
end

local function randomLegal(s)
  local moves = rules.legalMoves(s)
  local idx = moves[math.random(#moves)]
  return rules.boardOf(idx), rules.cellOf(idx)
end

local function pack(...) return { n = select("#", ...), ... } end

--- Yield to the event loop while the computer thinks, keeping every other event (touches, timers) for later.
local function aiYield()
  local saved = {}
  os.queueEvent("uttt_yield")
  while true do
    local ev = pack(os.pullEventRaw())
    if ev[1] == "uttt_yield" then break end
    if ev[1] == "terminate" then error("Terminated", 0) end
    saved[#saved + 1] = ev
  end
  for _, ev in ipairs(saved) do os.queueEvent(unpack(ev, 1, ev.n)) end
end

local function doAiMove(g)
  local slot = moverSlot(g)
  local t0 = nowMs()
  log(string.format("ai %s thinking (move %d, forced %s)", tostring(slot.cpu), g.state.moves + 1, tostring(g.state.forced)))
  local ok, b, c, info = pcall(ai.choose, g.state, slot.cpu or "medium", { yield = aiYield })
  if not ok then
    if tostring(b):find("Terminated", 1, true) then error(b, 0) end
    log("ai error, playing a random move: " .. tostring(b))
    b, c, info = nil, nil, nil
  end
  if not b then
    b, c = randomLegal(g.state)
  end
  log(string.format("ai %s plays %d-%d depth=%s nodes=%s score=%s in %dms", tostring(slot.cpu), b, c, tostring(info and info.depth),
    tostring(info and info.nodes), tostring(info and info.score), nowMs() - t0))
  applyMove(g, b, c)
end

--- Whose turn is it on this screen, and may the live player (if known) move for them?
local function touchAllowed(g)
  local live = hw.livePlayer()
  if not live then return true end
  local mover = moverSlot(g)
  local other = g.state.turn == 1 and g.blue or g.red
  -- Only two named players guard their turns from each other. A guest has no identity of their own, so whoever is at
  -- the screen plays for them: that is how one person plays hot seat against a guest.
  if isHuman(mover) and isHuman(other) and live == other.name and live ~= mover.name then
    return false, string.format("%s - it is %s's turn", live, mover.name)
  end
  return true
end

local function resign(g)
  local num = g.state.turn
  -- the person at the screen resigns for the side to move
  rules.forfeit(g.state, num)
  audio.cue("resign")
  finishGame("resign")
end

local function abandon(g, why)
  log("game abandoned: " .. tostring(why))
  hw.allOff()
  S.game = nil
  clearSavedGame()
  S.view = "idle"
  S.lobby = nil
  setToast("Game abandoned - no rating change", C.warn)
  S.dirty = true
end

-- ------------------------------------------------------------------ lobby

local function lobbyDefaults()
  local live = hw.livePlayer()
  local lobby = {
    red = nil, blue = nil, picking = "red", first = store:setting("first") or "red", page = 1,
  }
  if live then
    lobby.red = { name = live }
    lobby.picking = "blue"
  end
  return lobby
end

local function openLobby()
  S.lobby = S.lobby or lobbyDefaults()
  S.view = "lobby"
  S.lastTouch = nowMs()
  S.dirty = true
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
  startGame(red, blue, { first = first })
end

-- ------------------------------------------------------------------ drawing: shared pieces

local function clearScreen(color)
  screen:clear(color or C.bg, nil, " ")
end

local function flush()
  if env.monitor then screen:output(env.monitor, 0, 0) end
end

--- Name with the pixel font if it fits, otherwise native text.
local function nameText(name, x, y, maxW, color, align, bg)
  align = align or "left"
  if ui.textWidth(name) <= maxW then
    ui.text(name, x, y, color, align)
    return font.height
  end
  ui.small(name, x, y + floor((font.height - 1) / 2), color, bg or C.bg, align, maxW)
  return 1
end

local function paintBackground()
  clearScreen(C.bg)
end

local function drawToast()
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

local function playerCard(num, slot, x, w, active, boardsWon)
  local color = num == 1 and C.red or C.blue
  local hdr = env.L.hdr
  ui.fill(x, 0, w, hdr, C.panel)
  ui.fill(num == 1 and x or x + w - 2, 0, 2, hdr, color)
  local tx = num == 1 and x + 4 or x + w - 4
  local align = num == 1 and "left" or "right"
  nameText(slot.name, tx, 1, w - 8, active and C.text or C.line, align, C.panel)
  local sub
  if slot.cpu then
    sub = "COMPUTER"
  elseif slot.guest then
    sub = "GUEST - UNRANKED"
  else
    local p = store:get(slot.name)
    sub = p and string.format("%d ELO  %s  W%d L%d", p.elo, rankText(slot.name), p.wins, p.losses) or "NEW PLAYER"
  end
  ui.small(sub, tx, hdr - 3, active and color or C.line, C.panel, align, w - 8)
  if active then
    ui.fill(x, hdr - 1, w, 1, color)
  end
end

-- ------------------------------------------------------------------ drawing: idle (attract)

local function demoStep()
  local d = S.demo
  local t = nowMs()
  if not d or (d.finishedAt and t - d.finishedAt > 5000) then
    S.demo = { state = rules.new({ tiebreak = false, first = math.random(2) }), nextAt = t + 1200, last = nil, finishedAt = nil }
    d = S.demo
    S.dirty = true
  end
  if d.finishedAt then return end
  if t >= d.nextAt then
    local s = d.state
    local b, c = ai.choose(s, "easy", { ms = 0, maxNodes = 200 })
    if not b then b, c = randomLegal(s) end
    rules.play(s, b, c)
    d.last = { b, c }
    d.nextAt = t + 900
    if s.winner ~= 0 then d.finishedAt = t end
    S.dirty = true
  end
end

local function topLine(i, row, x, y, w)
  local color = i == 1 and C.hi or (i == 2 and C.text or C.line)
  ui.small(string.format("%d. %s", row.rank, row.name), x, y, color, C.bg, "left", w - 6)
  ui.small(tostring(row.value), x + w, y, color, C.bg, "right")
end

local function drawIdle()
  paintBackground()
  local W, H = env.W, env.H
  -- title
  ui.text("ULTIMATE", floor(W / 2), 2, C.hi, "center")
  local tw1 = ui.textWidth("TIC-")
  local tw2 = ui.textWidth("TAC-")
  local tw3 = ui.textWidth("TOE")
  local total = tw1 + tw2 + tw3 + 2
  local tx = floor((W - total) / 2)
  ui.text("TIC-", tx, 11, C.red, "left")
  ui.text("TAC-", tx + tw1 + 1, 11, C.text, "left")
  ui.text("TOE", tx + tw1 + tw2 + 2, 11, C.blue, "left")

  -- demo board
  local cw = max(3, floor((W - 44) / 9 / 1.0))
  cw = min(cw, 7)
  local ch = max(2, min(floor(cw * 2 / 3 + 0.5), floor((H - 21 - 17) / 9)))
  local bw, bh = 9 * cw + 4, 9 * ch + 2
  local bx = floor((W - bw) / 2)
  local by = 21
  local Ld = ui.layoutAt(bx, by, cw, ch, 2, 1)
  if S.demo then ui.board(Ld, { state = S.demo.state, last = S.demo.last }) end

  -- side panels
  local sideW = bx - 3
  local rows = store:leaderboard("elo", 5)
  if sideW >= 14 then
    ui.small("TOP RATED", 2, by, C.hi, C.bg, "left")
    if #rows == 0 then
      ui.small("No games yet", 2, by + 2, C.line, C.bg, "left")
    end
    for i, row in ipairs(rows) do topLine(i, row, 2, by + 1 + i * 2, sideW) end
    local t = store.data.totals
    local rx = bx + bw + 3
    ui.small("TONIGHT", rx, by, C.hi, C.bg, "left")
    ui.small(t.games .. " games", rx, by + 3, C.text, C.bg, "left")
    ui.small(t.moves .. " moves", rx, by + 5, C.text, C.bg, "left")
    ui.small(t.draws .. " draws", rx, by + 7, C.text, C.bg, "left")
    local recent = store:recent(1)[1]
    if recent then
      ui.small("LAST GAME", rx, by + 11, C.hi, C.bg, "left")
      local line1 = recent.winner == 3 and "Draw" or ((recent.winner == 1 and recent.red or recent.blue) .. " won")
      ui.small(line1, rx, by + 13, recent.winner == 1 and C.red or (recent.winner == 2 and C.blue or C.text), C.bg, "left", W - rx - 1)
      ui.small(recent.moves .. " moves", rx, by + 15, C.line, C.bg, "left")
    end
  else
    local champ = rows[1]
    if champ then ui.small("Champion: " .. champ.name .. " (" .. champ.value .. ")", floor(W / 2), by - 1, C.hi, C.bg, "center", W - 2) end
  end

  -- prompt
  local blink = floor(nowMs() / 700) % 2 == 0
  local py = by + bh + 3
  if blink then ui.text("TOUCH TO PLAY", floor(W / 2), py, C.text, "center") end
  local near = hw.nearby()
  local line = #near > 0 and (#near .. " player" .. (#near == 1 and "" or "s") .. " nearby") or "Two players or play the computer"
  ui.small(line, floor(W / 2), py + font.height + 2, C.line, C.bg, "center", W - 2)
  ui.region("play", 0, 0, W, H)
end

-- ------------------------------------------------------------------ drawing: lobby

local function drawLobby()
  paintBackground()
  ui.clearButtons()
  local W, H = env.W, env.H
  local l = S.lobby
  -- a short wall (5 blocks high) gets the same screen with tighter rows
  local compact = H < 78
  local titleY, slotY, slotH, nameDy, subDy = 1, 10, 15, 5, 13
  local listY, rowH, rowGap, utilGap = 27, 9, 10, 10
  if compact then
    titleY, slotY, slotH, nameDy, subDy = 0, 8, 12, 3, 10
    listY, rowH, rowGap, utilGap = 21, 7, 8, 8
  end
  ui.text("WHO IS PLAYING?", floor(W / 2), titleY, C.text, "center")

  -- the two colour slots
  local sw = floor((W - 8) / 2)
  local function slotPanel(num, x)
    local slot = num == 1 and l.red or l.blue
    local color = num == 1 and C.red or C.blue
    local key = num == 1 and "red" or "blue"
    local y = slotY
    ui.fill(x, y, sw, slotH, C.panel)
    ui.fill(x, y, 3, slotH, color)
    if l.picking == key then ui.frame(x, y, sw, slotH, C.hi, 1) end
    ui.small(num == 1 and "RED  (X)" or "BLUE  (O)", x + 5, y + 1, color, C.panel, "left")
    if slot then
      nameText(slot.name, x + 5, y + nameDy, sw - 8, C.text, "left", C.panel)
      local sub = slot.cpu and "COMPUTER" or (slot.guest and "GUEST - UNRANKED" or nil)
      if not sub then
        local p = store:get(slot.name)
        sub = p and string.format("%d ELO  W%d L%d D%d", p.elo, p.wins, p.losses, p.draws) or "NEW PLAYER"
      end
      ui.small(sub, x + 5, y + subDy, C.line, C.panel, "left", sw - 7)
    else
      ui.small(l.picking == key and "Tap your name below" or "Waiting...", x + 5, y + nameDy + 2, l.picking == key and C.hi or C.line, C.panel, "left", sw - 7)
    end
  end
  ui.region("redSlot", 4, slotY, sw, slotH)
  ui.region("blueSlot", 4 + sw, slotY, sw, slotH)
  slotPanel(1, 4)
  slotPanel(2, 4 + sw)
  ui.button("back", 2, compact and 0 or 1, 16, compact and 6 or 7, "BACK", C.panel, { small = true })

  -- nearby players
  local near, ok = hw.nearby()
  local label
  if ok or #near > 0 then label = "NEARBY PLAYERS (" .. #near .. ")" else label = "NO PLAYER DETECTED - USE GUEST OR COMPUTER" end
  ui.small(label, 4, listY, C.hi, C.bg, "left")
  local cols = 3
  local bw = floor((W - 8 - (cols - 1) * 2) / cols)
  local perPage = 6
  local pages = max(1, math.ceil(#near / perPage))
  if l.page > pages then l.page = pages end
  local first = (l.page - 1) * perPage
  for i = 1, perPage do
    local name = near[first + i]
    local col = (i - 1) % cols
    local row = floor((i - 1) / cols)
    local x = 4 + col * (bw + 2)
    local y = listY + 2 + row * rowGap
    if name then
      local taken = (l.red and l.red.name == name and not l.red.cpu) or (l.blue and l.blue.name == name and not l.blue.cpu)
      local p = store:get(name)
      local label2 = name .. (p and (" " .. p.elo) or "")
      local color = C.panel
      if l.red and l.red.name == name then color = C.redTint elseif l.blue and l.blue.name == name then color = C.blueTint end
      ui.button("player", x, y, bw, rowH, label2, color, { small = true, data = name, fg = taken and C.text or C.text })
    else
      ui.fill(x, y, bw, rowH, C.bg)
      ui.frame(x, y, bw, rowH, C.panel, 1)
    end
  end
  if pages > 1 then
    ui.button("page", W - 22, listY - 1, 18, 7, "MORE " .. l.page .. "/" .. pages, C.panel, { small = true })
  end

  -- computer opponents
  local cpuY = listY + 2 + 2 * rowGap + 1
  ui.button("cpu", 4, cpuY, bw, rowH, "CPU EASY", C.panel, { small = true, data = "easy" })
  ui.button("cpu", 4 + (bw + 2), cpuY, bw, rowH, "CPU MEDIUM", C.panel, { small = true, data = "medium" })
  ui.button("cpu", 4 + 2 * (bw + 2), cpuY, bw, rowH, "CPU HARD", C.panel, { small = true, data = "hard" })

  -- utilities
  local utilY = cpuY + utilGap
  ui.button("guest", 4, utilY, bw, rowH, "GUEST", C.panel, { small = true })
  ui.button("swap", 4 + (bw + 2), utilY, bw, rowH, "SWAP COLORS", C.panel, { small = true })
  ui.button("stats", 4 + 2 * (bw + 2), utilY, bw, rowH, "STATS", C.panel, { small = true })

  -- options line and start
  local startY = utilY + utilGap + (compact and 0 or 1)
  local firstText = l.first == "random" and "RANDOM" or (l.first == "blue" and "BLUE" or "RED")
  local timer = store:setting("timer")
  local info = string.format("%s FIRST  /  TIMER %s  /  %s", firstText, timer > 0 and (timer .. "s") or "OFF",
    store:setting("tiebreak") and "MOST-BOARDS RULE" or "STANDARD DRAW")
  local half = floor((W - 8) * 0.55)
  ui.button("options", 4, startY, half, rowH, info, C.panel, { small = true })
  local ready = l.red ~= nil and l.blue ~= nil
  ui.button("start", 4 + half + 2, startY, W - 8 - half - 2, rowH, ready and "START" or "PICK 2", ready and C.ok or C.panel, { small = true, enabled = ready })
  drawToast()
end

-- ------------------------------------------------------------------ drawing: game

local function statusLine(g)
  local s = g.state
  local mover = moverSlot(g)
  if g.paused then return "PAUSED", C.warn end
  if g.awaySince and nowMs() - g.awaySince > config.PRESENCE_WARN * 1000 and isHuman(mover) then
    return "Waiting for " .. mover.name .. " to come back...", C.warn
  end
  if g.thinking then return mover.name .. " is thinking...", C.info end
  if s.forced then
    return string.format("%s: play in board %d (lit)", mover.name, s.forced), s.turn == 1 and C.red or C.blue
  end
  return string.format("%s: FREE MOVE - anywhere!", mover.name), C.hi
end

local function drawSideButtons(g, L)
  -- left: menu, hint, mini map; right: resign, sound
  local bx1, bx2 = 1, L.x0 + L.bw + 1
  local bw = L.sideW - 1
  if L.side and bw >= 10 then
    local y = L.y0
    ui.button("menu", bx1, y, bw, 7, "MENU", C.panel, { small = true })
    ui.button("hint", bx1, y + 9, bw, 7, "HINT", C.panel, { small = true, enabled = not moverSlot(g).cpu })
    ui.button("resign", bx2, y, bw, 7, g.confirmResign and "SURE?" or "RESIGN", g.confirmResign and C.warn or C.panel, { small = true })
    ui.button("sound", bx2, y + 9, bw, 7, store:setting("sound") and "SOUND ON" or "SOUND OFF", C.panel, { small = true })
    -- meta mini map in the left margin
    local mx, my = bx1 + floor((bw - 11) / 2), L.y0 + L.bh - 12
    ui.small("BOARDS", bx1 + floor(bw / 2), my - 2, C.line, C.bg, "center")
    for b = 1, 9 do
      local x = mx + ((b - 1) % 3) * 4
      local y = my + floor((b - 1) / 3) * 3
      local o = g.state.sub[b]
      local col = o == 1 and C.red or (o == 2 and C.blue or (o == 3 and C.tie or C.panel))
      if o == 0 and (g.state.forced == nil or g.state.forced == b) then col = C.hiTint end
      ui.fill(x, y, 3, 2, col)
    end
    -- recent moves on the right
    local hist = g.state.history
    local ry = L.y0 + 19
    ui.small("MOVES", bx2 + floor(bw / 2), ry, C.line, C.bg, "center")
    for i = 0, 4 do
      local h = hist[#hist - i]
      if h then
        ui.small(string.format("%d %s%d-%d", #hist - i, h.p == 1 and "X" or "O", h.b, h.c), bx2, ry + 2 + i * 2, h.p == 1 and C.red or C.blue, C.bg, "left", bw)
      end
    end
  else
    local y = L.footY
    local w = floor((env.W - 10) / 4)
    ui.button("menu", 2, y, w, 7, "MENU", C.panel, { small = true })
    ui.button("hint", 2 + (w + 2), y, w, 7, "HINT", C.panel, { small = true, enabled = not moverSlot(g).cpu })
    ui.button("resign", 2 + 2 * (w + 2), y, w, 7, g.confirmResign and "SURE?" or "RESIGN", g.confirmResign and C.warn or C.panel, { small = true })
    ui.button("sound", 2 + 3 * (w + 2), y, w, 7, store:setting("sound") and "SOUND ON" or "SOUND OFF", C.panel, { small = true })
  end
end

local function drawPause(g)
  local W, H = env.W, env.H
  local w, h = min(W - 10, 60), 36
  local x, y = floor((W - w) / 2), floor((H - h) / 2)
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.hi, 1)
  ui.text("PAUSED", floor(W / 2), y + 3, C.hi, "center")
  ui.button("resume", x + 3, y + 13, w - 6, 8, "RESUME", C.ok, { small = true })
  ui.button("abandon", x + 3, y + 23, w - 6, 8, "ABANDON (NO RATING CHANGE)", C.warn, { small = true })
end

--- The headline under the final board: who won and exactly why (which boards formed the line).
local function finalLine(g)
  local s = g.state
  local r = S.result
  if s.winner == 3 then return "DRAW - no boards left to play", C.hi end
  local w = s.winner == 1 and g.red or g.blue
  local color = s.winner == 1 and C.red or C.blue
  if s.forfeit then return w.name .. " WINS by forfeit", color end
  if s.metaLine then
    local l = rules.LINES[s.metaLine]
    return string.format("%s WINS - boards %d, %d, %d in a line", w.name, l[1], l[2], l[3]), color
  end
  return string.format("%s WINS - most boards (%d-%d)", w.name, s.boards[s.winner], s.boards[3 - s.winner]), color
end

local function drawGame(gameArg, final)
  local g = gameArg or S.game
  local s = g.state
  local L = env.L
  paintBackground()
  ui.clearButtons()
  local W = env.W
  local cardW = floor((W - 30) / 2)
  playerCard(1, g.red, 0, cardW, s.turn == 1 and s.winner == 0, s.boards[1])
  playerCard(2, g.blue, W - cardW, cardW, s.turn == 2 and s.winner == 0, s.boards[2])
  -- centre: small-board score and the move timer
  local cx = floor(W / 2)
  ui.fill(cardW, 0, W - 2 * cardW, L.hdr, C.bg)
  ui.text(s.boards[1], cx - 4, 1, C.red, "right")
  ui.text("-", cx, 1, C.line, "center")
  ui.text(s.boards[2], cx + 4, 1, C.blue, "left")
  ui.small("MOVE " .. (s.moves + 1), cx, L.hdr - 3, C.line, C.bg, "center")
  if g.deadline and not g.paused then
    local left = max(0, g.deadline - nowMs()) / 1000
    local frac = min(1, left / g.timer)
    local bw = (W - 2 * cardW) - 2
    ui.fill(cardW + 1, L.hdr - 1, bw, 1, C.panel)
    ui.fill(cardW + 1, L.hdr - 1, floor(bw * frac), 1, left < 5 and C.warn or C.ok)
  end

  local flash = g.flash and g.flash.on and g.flash or nil
  local hint = (g.hint and nowMs() < g.hintUntil) and g.hint or nil
  ui.board(L, { state = s, last = g.last, hint = hint, flash = flash })

  local text, color
  if final then
    text, color = finalLine(g)
  else
    text, color = statusLine(g)
    if S.toast and nowMs() <= S.toast.untilAt then text, color = S.toast.text, S.toast.color end
  end
  ui.fill(0, L.statusY, env.W, L.statusH, C.bg)
  if ui.textWidth(text) <= env.W - 2 then
    ui.text(text, floor(env.W / 2), L.statusY, color, "center")
  else
    ui.small(text, floor(env.W / 2), L.statusY + 3, color, C.bg, "center", env.W - 2)
  end

  if final then
    ui.small("TOUCH FOR RESULTS", floor(env.W / 2), L.statusY + L.statusH, C.line, C.bg, "center")
    ui.region("skipFinal", 0, 0, env.W, env.H)
    return
  end
  drawSideButtons(g, L)
  if g.paused then drawPause(g) end
end

-- ------------------------------------------------------------------ drawing: result

local function drawResult()
  paintBackground()
  ui.clearButtons()
  local r = S.result
  local W, H = env.W, env.H
  local winnerColor = r.winner == 1 and C.red or (r.winner == 2 and C.blue or C.hi)
  local title
  if r.winner == 3 then
    title = "DRAW"
  else
    local w = r.winner == 1 and r.red or r.blue
    title = w.name .. " WINS!"
  end
  local howY = 11
  if ui.textWidth(title) > W - 4 then
    ui.text("WINNER", floor(W / 2), 1, winnerColor, "center")
    ui.small(r.winner == 1 and r.red.name or r.blue.name, floor(W / 2), 9, C.text, C.bg, "center")
    howY = 12
  else
    ui.text(title, floor(W / 2), 2, winnerColor, "center")
  end
  local how = r.forfeit and "BY FORFEIT" or (r.winner == 3 and "NOTHING LEFT TO PLAY" or "THREE BOARDS IN A LINE")
  if not r.forfeit and r.winner ~= 3 and r.state.metaLine == nil then how = "MOST BOARDS WINS" end
  ui.small(string.format("%s  -  %d moves  -  %s  -  boards %d-%d", how, r.moves, fmtDuration(r.seconds), r.boards[1], r.boards[2]),
    floor(W / 2), howY, C.line, C.bg, "center", W - 2)

  -- two player panels (a short wall keeps the facts and drops the streak line)
  local compact = H < 78
  local panelH = compact and 20 or 24
  local pw = floor((W - 10) / 2)
  local function panel(num, x)
    local slot = num == 1 and r.red or r.blue
    local sum = r.summary[num == 1 and "red" or "blue"]
    local color = num == 1 and C.red or C.blue
    local won = r.winner == num
    ui.fill(x, 15, pw, panelH, C.panel)
    ui.fill(x, 15, 3, panelH, color)
    if won then ui.frame(x, 15, pw, panelH, C.hi, 1) end
    nameText(slot.name, x + 6, 17, pw - 10, C.text, "left", C.panel)
    ui.small(num == 1 and "RED  X" or "BLUE  O", x + 6, 26, color, C.panel, "left")
    if r.ranked and sum and sum.elo then
      local d = sum.delta or 0
      ui.small(string.format("RATING %d  (%s)", sum.elo, signed(d)), x + 6, 29, d > 0 and C.ok or (d < 0 and C.warn or C.line), C.panel, "left", pw - 8)
      local rb, ra = r.rankBefore[num == 1 and "red" or "blue"], r.rankAfter[num == 1 and "red" or "blue"]
      local rk = ra and ("RANK #" .. ra) or "UNRANKED"
      if rb and ra and ra < rb then rk = rk .. "  UP" elseif rb and ra and ra > rb then rk = rk .. "  DOWN" end
      ui.small(rk, x + 6, 31, C.text, C.panel, "left", pw - 8)
      local st = sum.streak or 0
      if not compact then
        ui.small(string.format("STREAK %s   GAMES %d", st > 0 and ("W" .. st) or (st < 0 and ("L" .. -st) or "-"), sum.games or 0), x + 6, 33, C.line, C.panel, "left", pw - 8)
      end
    else
      ui.small(slot.cpu and "COMPUTER" or (slot.guest and "GUEST" or "UNRANKED GAME"), x + 6, 29, C.line, C.panel, "left")
      if not r.ranked and not r.guest then ui.small("vs computer: no rating change", x + 6, 31, C.line, C.panel, "left", pw - 8) end
    end
  end
  panel(1, 3)
  panel(2, 3 + pw + 4)

  -- achievements
  local y = 15 + panelH + 2
  local ach = r.summary.achievements or {}
  for i, a in ipairs(ach) do
    if i <= (compact and 1 or 3) then
      ui.small("* " .. a.player .. " unlocked " .. a.name, floor(W / 2), y, C.accent, C.bg, "center", W - 2)
      y = y + 2
    end
  end
  if #ach == 0 and r.ranked then
    local h2h = store:headToHead(r.red.name, r.blue.name)
    ui.small(string.format("%s vs %s: %d - %d - %d", r.red.name, r.blue.name, h2h.w, h2h.l, h2h.d), floor(W / 2), y, C.line, C.bg, "center", W - 2)
    y = y + 2
  end

  -- leaderboard strip
  local rows = store:leaderboard("elo", 5)
  ui.small("TOP RATED", 4, y + 2, C.hi, C.bg, "left")
  for i, row in ipairs(rows) do
    local ry = y + 3 + i * 2
    local color = (row.name == r.red.name or row.name == r.blue.name) and C.text or C.line
    ui.small(string.format("%d. %s", row.rank, row.name), 4, ry, color, C.bg, "left", 30)
    ui.small(tostring(row.value), 40, ry, color, C.bg, "right")
  end

  -- buttons
  local bx = 52
  local bw = W - bx - 4
  local by = y + 2
  local bh = compact and 5 or 7
  local step = bh + 1
  ui.button("rematch", bx, by, bw, bh, "REMATCH (SWAP COLORS)", C.ok, { small = true })
  ui.button("newgame", bx, by + step, bw, bh, "NEW GAME", C.panel, { small = true })
  ui.button("stats", bx, by + 2 * step, bw, bh, "STATS", C.panel, { small = true })
  ui.button("done", bx, by + 3 * step, bw, bh, "DONE", C.panel, { small = true })
  drawToast()
end

-- ------------------------------------------------------------------ drawing: stats

local METRIC_LABEL = { elo = "RATING", wins = "WINS", rate = "WIN %", streak = "STREAK", boards = "BOARDS" }

local function drawLeaders()
  local W = env.W
  ui.text("LEADERBOARD", floor(W / 2), 1, C.hi, "center")
  local tabW = floor((W - 8 - 4 * 2) / 5)
  for i, key in ipairs(Store.BOARD_ORDER) do
    local active = S.stats.metric == key
    ui.button("metric", 4 + (i - 1) * (tabW + 2), 10, tabW, 7, METRIC_LABEL[key], active and C.hi or C.panel, { small = true, data = key })
  end
  local rows, total = store:leaderboard(S.stats.metric)
  local perPage = max(3, floor((env.H - 38) / 6))
  local pages = max(1, math.ceil(#rows / perPage))
  if S.stats.page > pages then S.stats.page = pages end
  local first = (S.stats.page - 1) * perPage
  local def = Store.BOARDS[S.stats.metric]
  if #rows == 0 then
    ui.small("No ranked players yet - finish a game to appear here", floor(W / 2), 30, C.line, C.bg, "center", W - 2)
  end
  for i = 1, perPage do
    local row = rows[first + i]
    local y = 19 + (i - 1) * 6
    if row then
      local color = row.rank == 1 and C.hi or (row.rank <= 3 and C.text or C.line)
      ui.button("player", 4, y, W - 8, 5, nil, i % 2 == 0 and C.panel or C.bg, { data = row.name })
      ui.small("#" .. row.rank, 6, y + 2, color, i % 2 == 0 and C.panel or C.bg, "left")
      ui.small(row.name, 14, y + 2, color, i % 2 == 0 and C.panel or C.bg, "left", 24)
      local p = row.player
      ui.small(string.format("%dW %dL %dD", p.wins, p.losses, p.draws), 62, y + 2, C.line, i % 2 == 0 and C.panel or C.bg, "left")
      ui.small(row.value .. (def.suffix or ""), W - 6, y + 2, color, i % 2 == 0 and C.panel or C.bg, "right")
    end
  end
  if pages > 1 then
    ui.button("prevPage", W - 44, env.H - 18, 20, 7, "< PREV", C.panel, { small = true })
    ui.button("nextPage", W - 22, env.H - 18, 20, 7, "NEXT >", C.panel, { small = true })
  end
  ui.small(total .. " ranked players", 4, env.H - 16, C.line, C.bg, "left")
end

local function drawHistory()
  local W = env.W
  ui.text("RECENT GAMES", floor(W / 2), 1, C.hi, "center")
  local rows = store:recent(floor((env.H - 26) / 6))
  if #rows == 0 then ui.small("No games recorded yet", floor(W / 2), 30, C.line, C.bg, "center") end
  for i, h in ipairs(rows) do
    local y = 11 + (i - 1) * 6
    local bg = i % 2 == 0 and C.panel or C.bg
    ui.fill(4, y, W - 8, 5, bg)
    local when = os.date("%m/%d %H:%M", floor((h.at or 0) / 1000))
    ui.small(when, 6, y + 2, C.line, bg, "left")
    local rn = h.red .. (h.redCpu and " (CPU)" or "")
    local bn = h.blue .. (h.blueCpu and " (CPU)" or "")
    local label
    if h.winner == 3 then
      label = rn .. " drew " .. bn
    else
      label = (h.winner == 1 and rn or bn) .. " beat " .. (h.winner == 1 and bn or rn)
    end
    ui.small(label, 24, y + 2, h.winner == 1 and C.red or (h.winner == 2 and C.blue or C.text), bg, "left", 56)
    ui.small(string.format("%dmv %d-%d", h.moves or 0, h.boardsRed or 0, h.boardsBlue or 0), W - 6, y + 2, C.line, bg, "right")
  end
  local t = store.data.totals
  ui.small(string.format("%d games, %d moves, %d draws", t.games, t.moves, t.draws), 4, env.H - 14, C.line, C.bg, "left")
end

local function drawPlayerCard()
  local W = env.W
  local p = store:get(S.stats.player)
  if not p then
    ui.small("Unknown player", floor(W / 2), 30, C.line, C.bg, "center")
    return
  end
  nameText(p.name, floor(W / 2), 1, W - 6, C.hi, "center")
  local rank, total = store:rank(p.name, "elo")
  ui.small(string.format("RATING %d   PEAK %d   RANK %s", p.elo, p.peak, rank and ("#" .. rank .. " of " .. total) or "unranked"),
    floor(W / 2), 10, C.text, C.bg, "center", W - 2)

  -- W / L / D bar
  local bx, bw = 6, W - 12
  local gm = max(1, p.games)
  local wW, wD = floor(bw * p.wins / gm), floor(bw * p.draws / gm)
  ui.fill(bx, 13, bw, 3, C.panel)
  ui.fill(bx, 13, wW, 3, C.ok)
  ui.fill(bx + wW, 13, wD, 3, C.line)
  ui.fill(bx + wW + wD, 13, bw - wW - wD, 3, p.games > 0 and C.warn or C.panel)
  ui.small(string.format("%d W    %d L    %d D    %d%% win rate", p.wins, p.losses, p.draws, floor(Store.winRate(p) * 100 + 0.5)),
    floor(W / 2), 17, C.text, C.bg, "center")

  local col1, col2 = 6, floor(W / 2) + 2
  local function stat(x, y, name, value)
    ui.small(name, x, y, C.line, C.bg, "left")
    ui.small(tostring(value), x + 26, y, C.text, C.bg, "left")
  end
  local avg = p.games > 0 and floor(p.moves / p.games * 10) / 10 or 0
  stat(col1, 21, "STREAK", p.streak > 0 and ("W" .. p.streak) or (p.streak < 0 and ("L" .. -p.streak) or "-"))
  stat(col1, 23, "BEST", p.bestStreak)
  stat(col1, 25, "BOARDS", p.boardsWon .. " won / " .. p.boardsLost .. " lost")
  stat(col1, 27, "FASTEST", p.fastestWin and (p.fastestWin .. " moves") or "-")
  stat(col1, 29, "LONGEST", p.longest .. " moves")
  stat(col2, 21, "AS RED", p.asRed.wins .. "/" .. p.asRed.games .. " won")
  stat(col2, 23, "AS BLUE", p.asBlue.wins .. "/" .. p.asBlue.games .. " won")
  stat(col2, 25, "PLAYED", fmtDuration(p.seconds))
  stat(col2, 27, "AVG MOVES", avg)
  stat(col2, 29, "GAMES", p.games)

  -- versus the computer
  local y = 33
  ui.small("VS COMPUTER", col1, y, C.hi, C.bg, "left")
  local x = col1 + 14
  for _, lvl in ipairs({ "easy", "medium", "hard" }) do
    local r = p.vsCpu[lvl] or { w = 0, l = 0, d = 0 }
    ui.small(string.format("%s %d-%d-%d", lvl:sub(1, 1):upper() .. lvl:sub(2), r.w, r.l, r.d), x + 4, y, C.text, C.bg, "left")
    x = x + 26
  end

  -- rivals: most-played opponents
  local rivals = {}
  for name, r in pairs(p.h2h) do
    local other = store:get(name)
    rivals[#rivals + 1] = { name = other and other.name or name, r = r, n = r.w + r.l + r.d }
  end
  table.sort(rivals, function(a, b) return a.n > b.n end)
  ui.small("RIVALS", col1, 37, C.hi, C.bg, "left")
  for i = 1, 3 do
    local rv = rivals[i]
    if rv then ui.small(string.format("%s  %d-%d-%d", rv.name, rv.r.w, rv.r.l, rv.r.d), col1 + 8, 37 + i * 2, C.text, C.bg, "left", 40) end
  end

  -- achievements
  ui.small("BADGES", col2, 37, C.hi, C.bg, "left")
  local ach = store:achievements(p.name)
  if #ach == 0 then ui.small("none yet", col2 + 8, 39, C.line, C.bg, "left") end
  for i, a in ipairs(ach) do
    if i <= 5 then ui.small("* " .. a.name, col2 + 8, 37 + i * 2, C.accent, C.bg, "left", 24) end
  end

  -- recent form: the last 12 games as coloured blocks, newest on the left
  ui.small("FORM", col1, 51, C.hi, C.bg, "left")
  local key = string.lower(p.name)
  local x = col1 + 8
  local shown = 0
  local hist = store.data.history
  for i = #hist, 1, -1 do
    local h = hist[i]
    local side = (not h.redCpu and string.lower(h.red) == key) and 1 or ((not h.blueCpu and string.lower(h.blue) == key) and 2 or nil)
    if side and shown < 12 then
      local color = h.winner == 3 and C.line or (h.winner == side and C.ok or C.warn)
      ui.fill(x, 51, 6, 3, color)
      x = x + 8
      shown = shown + 1
    end
  end
  if shown == 0 then ui.small("no recent games", col1 + 8, 51, C.line, C.bg, "left") end
end

local function drawStats()
  paintBackground()
  ui.clearButtons()
  local W, H = env.W, env.H
  if S.stats.mode == "leaders" then drawLeaders()
  elseif S.stats.mode == "history" then drawHistory()
  else drawPlayerCard() end
  local y = H - 9
  local bw = floor((W - 10) / 4)
  ui.button("tab", 2, y, bw, 7, "LEADERS", S.stats.mode == "leaders" and C.hi or C.panel, { small = true, data = "leaders" })
  ui.button("tab", 2 + (bw + 2), y, bw, 7, "HISTORY", S.stats.mode == "history" and C.hi or C.panel, { small = true, data = "history" })
  ui.button("settings", 2 + 2 * (bw + 2), y, bw, 7, "SETTINGS", C.panel, { small = true })
  ui.button("back", 2 + 3 * (bw + 2), y, bw, 7, "BACK", C.panel, { small = true })
  drawToast()
end

-- ------------------------------------------------------------------ drawing: settings

local TIMERS = { 0, 15, 30, 60 }
local LEVELS = { "easy", "medium", "hard" }

local function cycle(list, current)
  for i, v in ipairs(list) do
    if v == current then return list[i % #list + 1] end
  end
  return list[1]
end

local function drawSettings()
  paintBackground()
  ui.clearButtons()
  local W, H = env.W, env.H
  ui.text("SETTINGS", floor(W / 2), 1, C.hi, "center")
  local bw = floor((W - 10) / 2)
  local rowStep = H < 78 and 8 or 10
  local hwY = 10 + 4 * rowStep + 2
  local function onoff(v) return v and "ON" or "OFF" end
  local rows = {
    { "sound", "SOUND: " .. onoff(store:setting("sound")) },
    { "vol", "VOLUME: " .. floor(store:setting("volume") * 100) .. "%" },
    { "timer", "MOVE TIMER: " .. (store:setting("timer") > 0 and (store:setting("timer") .. "s") or "OFF") },
    { "tiebreak", "NO MOVES LEFT: " .. (store:setting("tiebreak") and "MOST BOARDS WINS (HOUSE)" or "DRAW") },
    { "ai", "DEFAULT CPU: " .. string.upper(store:setting("ai")) },
    { "announce", "CHAT ANNOUNCE: " .. onoff(store:setting("announce")) },
    { "redstone", "REDSTONE LAMPS: " .. onoff(store:setting("redstone")) },
    { "testsound", "TEST SOUNDS" },
  }
  for i, row in ipairs(rows) do
    local col = (i - 1) % 2
    local r = floor((i - 1) / 2)
    ui.button(row[1], 4 + col * (bw + 2), 10 + r * rowStep, bw, rowStep - 2, row[2], C.panel, { small = true })
  end
  -- attached hardware
  local rep = hw.report()
  ui.small("HARDWARE", 4, hwY, C.hi, C.bg, "left")
  local lines = {
    "monitor: " .. tostring(rep.monitor) .. " (" .. env.W .. "x" .. env.H .. ")",
    "scoreboard: " .. tostring(rep.scoreboard or "none"),
    "speaker: " .. tostring(rep.speaker or "none"),
    "player detector: " .. tostring(rep.detector or "none"),
    "chat box: " .. tostring(rep.chat or "none") .. "   redstone: " .. tostring(rep.redstone),
  }
  for i, l in ipairs(lines) do ui.small(l, 4, hwY + i * 2, C.text, C.bg, "left", W - 6) end
  local wipe = S.confirm and S.confirm.id == "wipe" and nowMs() < S.confirm.untilAt
  ui.button("wipe", 4, H - 9, 50, 7, wipe and "TAP AGAIN TO WIPE" or "RESET ALL STATS", wipe and C.warn or C.panel, { small = true })
  ui.button("back", W - 24, H - 9, 20, 7, "BACK", C.panel, { small = true })
  drawToast()
end

-- ------------------------------------------------------------------ scoreboard monitor

local function drawScoreboard()
  if not board2 then return end
  local sc = board2.surf
  local prev = screen
  ui.setScreen(sc)
  sc:clear(C.bg, nil, " ")
  local W, H = board2.W, board2.H
  ui.text("LEADERBOARD", floor(W / 2), 1, C.hi, "center")
  local rows = store:leaderboard("elo", 8)
  if #rows == 0 then ui.small("Play a game to get on the board", floor(W / 2), 14, C.line, C.bg, "center") end
  for i, row in ipairs(rows) do
    local y = 10 + (i - 1) * 4
    local color = i == 1 and C.hi or (i <= 3 and C.text or C.line)
    local bg = i % 2 == 0 and C.panel or C.bg
    ui.fill(2, y, W - 4, 3, bg)
    ui.small("#" .. row.rank, 4, y + 1, color, bg, "left")
    ui.small(row.name, 10, y + 1, color, bg, "left", W - 28)
    ui.small(row.value .. "", W - 4, y + 1, color, bg, "right")
  end
  local y = 10 + 8 * 4 + 1
  if y < H - 8 then
    local g = S.game
    ui.fill(2, y, W - 4, 1, C.panel)
    if g then
      ui.small("NOW PLAYING", 4, y + 2, C.hi, C.bg, "left")
      ui.small(g.red.name .. " vs " .. g.blue.name, 4, y + 4, C.text, C.bg, "left", W - 6)
      ui.small(string.format("move %d - boards %d-%d", g.state.moves, g.state.boards[1], g.state.boards[2]), 4, y + 6, C.line, C.bg, "left", W - 6)
    else
      local r = store:recent(1)[1]
      ui.small("LAST GAME", 4, y + 2, C.hi, C.bg, "left")
      if r then
        ui.small(r.winner == 3 and (r.red .. " drew " .. r.blue) or ((r.winner == 1 and r.red or r.blue) .. " won"), 4, y + 4, C.text, C.bg, "left", W - 6)
      else
        ui.small("none yet", 4, y + 4, C.line, C.bg, "left")
      end
    end
  end
  sc:output(board2.mon, 0, 0)
  ui.setScreen(prev)
end

-- ------------------------------------------------------------------ render + debug dump

local function writeDebug()
  if not fs.exists("uttt_debug.flag") then return end
  local g = S.game
  local d = {
    view = S.view, W = env.W, H = env.H,
    buttons = {}, layout = env.L and { x0 = env.L.x0, y0 = env.L.y0, cw = env.L.cw, ch = env.L.ch, colX = env.L.colX, rowY = env.L.rowY, side = env.L.side } or nil,
  }
  for _, b in ipairs(ui.buttons()) do
    d.buttons[#d.buttons + 1] = { id = b.id, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label, enabled = b.enabled, data = b.data }
  end
  if g then
    d.game = {
      turn = g.state.turn, forced = g.state.forced, winner = g.state.winner, moves = g.state.moves, boards = g.state.boards,
      red = g.red.name, blue = g.blue.name, redCpu = g.red.cpu, blueCpu = g.blue.cpu, history = rules.moveList(g.state),
      deadline = g.deadline, paused = g.paused,
    }
  end
  if S.result then d.result = { winner = S.result.winner, moves = S.result.moves, ranked = S.result.ranked } end
  d.players = {}
  for _, p in pairs(store.data.players) do
    d.players[#d.players + 1] = {
      name = p.name, elo = p.elo, games = p.games, wins = p.wins, losses = p.losses, draws = p.draws, streak = p.streak,
      cpu = p.vsCpu, achievements = p.achievements, h2h = p.h2h,
    }
  end
  d.history = #store.data.history
  d.settings = store.data.settings
  d.toast = S.toast and S.toast.text or nil
  d.ticks, d.tickAt, d.now = S.ticks, S.tickAt, nowMs()
  d.awaySince = g and g.awaySince or nil
  d.sound = audio.isAvailable()
  local h = fs.open("uttt_ui.tmp", "w")
  if h then
    h.write(textutils.serialiseJSON(d))
    h.close()
    if fs.exists("uttt_ui.dat") then fs.delete("uttt_ui.dat") end
    fs.move("uttt_ui.tmp", "uttt_ui.dat")
  end
end

local function render()
  S.dirty = false
  ui.setScreen(screen)
  if S.view == "idle" then
    ui.clearButtons()
    drawIdle()
  elseif S.view == "lobby" then drawLobby()
  elseif S.view == "game" then drawGame()
  elseif S.view == "final" then drawGame(S.finalGame, true)
  elseif S.view == "result" then drawResult()
  elseif S.view == "stats" then drawStats()
  elseif S.view == "settings" then drawSettings()
  end
  flush()
  writeDebug()
  if nowMs() >= nextScoreboardAt then
    nextScoreboardAt = nowMs() + 2000
    drawScoreboard()
  end
end

-- ------------------------------------------------------------------ input

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

local function handleBoardTouch(px, py)
  local g = S.game
  local L = env.L
  if not g or g.paused or g.state.winner ~= 0 then return end
  local mover = moverSlot(g)
  if mover.cpu then
    audio.play("error")
    setToast("The computer is thinking...", C.info, 1200)
    return
  end
  local b, c = ui.cellAt(L, px, py)
  if not b then return end
  local allowed, msg = touchAllowed(g)
  if not allowed then
    audio.play("error")
    setToast(msg, C.warn, 2500)
    return
  end
  local ok, why = rules.isLegal(g.state, b, c)
  if not ok then
    audio.play("error")
    local text = why
    if why == "cell taken" then text = "That square is taken"
    elseif why == "that board is already decided" then text = "That board is already decided"
    elseif g.state.forced then text = string.format("You must play in board %d", g.state.forced) end
    setToast(text, C.warn, 2000)
    return
  end
  g.confirmResign = false
  applyMove(g, b, c)
end

local handlers = {}

handlers.play = function() openLobby() end

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
handlers.player = function(b)
  if S.view == "stats" then
    audio.play("page")
    toStats("player", b.data)
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
  -- cycle who moves first; the timer and tiebreak live in settings
  local l = S.lobby
  l.first = cycle({ "red", "blue", "random" }, l.first)
  store:setting("first", l.first)
  audio.play("tap")
  S.dirty = true
end
handlers.back = function()
  audio.play("back")
  if S.view == "stats" then backFromStats()
  elseif S.view == "settings" then
    store:save()
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

handlers.menu = function() if S.game then S.game.paused = true; audio.play("tap"); S.dirty = true end end
handlers.resume = function()
  local g = S.game
  if g then
    g.paused = false
    g.moveStart = nowMs()
    if g.deadline then g.deadline = nowMs() + g.timer * 1000 end
    audio.play("select"); S.dirty = true
  end
end
handlers.abandon = function() if S.game then abandon(S.game, "menu") end end
handlers.hint = function()
  local g = S.game
  if not g or g.paused then return end
  if moverSlot(g).cpu then return end
  local b, c = ai.choose(g.state, "hard", { ms = 600 })
  if b then
    g.hint, g.hintUntil = { b, c }, nowMs() + 4000
    g.hints[g.state.turn] = g.hints[g.state.turn] + 1
    audio.play("hint")
    setToast(string.format("Hint: board %d, square %d", b, c), C.ok, 3000)
  end
end
handlers.resign = function()
  local g = S.game
  if not g or g.paused then return end
  if not g.confirmResign then
    g.confirmResign = true
    g.confirmUntil = nowMs() + 4000
    audio.play("tap")
    S.dirty = true
    return
  end
  resign(g)
end
handlers.sound = function()
  local on = not store:setting("sound")
  store:setting("sound", on)
  audio.setEnabled(on)
  if on then audio.play("select") end
  S.dirty = true
end

-- settings buttons
handlers.vol = function()
  local v = store:setting("volume")
  v = (v >= 2 and 0.25) or (v + 0.25)
  store:setting("volume", v)
  audio.setVolume(v)
  audio.play("tap")
  S.dirty = true
end
handlers.timer = function()
  store:setting("timer", cycle(TIMERS, store:setting("timer")))
  audio.play("tap"); S.dirty = true
end
handlers.tiebreak = function() store:setting("tiebreak", not store:setting("tiebreak")); audio.play("tap"); S.dirty = true end
handlers.ai = function() store:setting("ai", cycle(LEVELS, store:setting("ai"))); audio.play("tap"); S.dirty = true end
handlers.announce = function() store:setting("announce", not store:setting("announce")); audio.play("tap"); S.dirty = true end
handlers.redstone = function()
  store:setting("redstone", not store:setting("redstone"))
  hw.setRedstone(store:setting("redstone"))
  hw.allOff()
  audio.play("tap"); S.dirty = true
end
handlers.testsound = function()
  audio.play("start")
  audio.later("placeRed", 300); audio.later("placeBlue", 520); audio.later("captureRed", 760)
  audio.later("win", 1100); audio.later("lose", 2400)
  setToast("Playing sound test", C.info, 2000)
end
handlers.wipe = function()
  if S.confirm and S.confirm.id == "wipe" and nowMs() < S.confirm.untilAt then
    store:reset()
    store:save()
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
  startGame(r.blue, r.red, { first = first })
end
handlers.newgame = function()
  S.result = nil
  S.lobby = nil
  hw.allOff()
  openLobby()
end
handlers.done = function()
  S.result = nil
  S.lobby = nil
  hw.allOff()
  S.view = "idle"
  S.dirty = true
end

local function onTouch(side, x, y)
  S.lastTouch = nowMs()
  if side ~= env.monitorName then return end
  local px, py = x - 1, y - 1
  if S.view == "idle" then
    audio.play("select")
    openLobby()
    return
  end
  local b = ui.hit(px, py)
  if b and handlers[b.id] then
    -- two-tap confirmations expire
    if b.id ~= "resign" and S.game then S.game.confirmResign = false end
    handlers[b.id](b)
    S.dirty = true
    return
  end
  if S.view == "game" then handleBoardTouch(px, py) end
end

-- ------------------------------------------------------------------ periodic work

local lastPresence = 0

local function checkPresence(g)
  if g.paused then g.awaySince = nil; return end
  local mover = moverSlot(g)
  if not isHuman(mover) then g.awaySince = nil; return end
  local _, ok, detected = hw.nearby()
  if not ok then g.awaySince = nil; return end
  local here = false
  for _, n in ipairs(detected) do if n == mover.name then here = true end end
  if here then
    g.awaySince = nil
  else
    if not g.awaySince then g.awaySince = nowMs() end
    local away = (nowMs() - g.awaySince) / 1000
    if away > config.PRESENCE_ABANDON then
      tellPlayers({ g.red, g.blue }, mover.name .. " left the game, so it was called off.")
      abandon(g, "player left")
    elseif away > config.PRESENCE_WARN and not g.warnedAway then
      g.warnedAway = true
      audio.play("presence")
      hw.tell(mover.name, "Your Ultimate Tic-Tac-Toe game is waiting!")
    end
  end
  if here then g.warnedAway = false end
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
    demoStep()
    if floor(t / 700) ~= S.blinkPhase then S.blinkPhase = floor(t / 700); S.dirty = true end
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
  elseif S.view == "game" and S.game then
    local g = S.game
    if g.flash and g.flash.on and t > g.flash.untilAt then g.flash.on = false; S.dirty = true end
    if g.confirmResign and t > (g.confirmUntil or 0) then g.confirmResign = false; S.dirty = true end
    if g.hint and t > g.hintUntil then g.hint = nil; S.dirty = true end
    if not g.paused then
      if t - g.moveStart > config.GAME_IDLE * 1000 then
        abandon(g, "idle")
        return
      end
      local mover = moverSlot(g)
      if mover.cpu and g.aiAt and t >= g.aiAt then
        g.thinking = true
        render()
        g.thinking = false
        g.aiAt = nil
        doAiMove(g)
        S.dirty = true
      elseif g.deadline then
        local left = g.deadline - t
        local sec = floor(left / 1000)
        if sec ~= g.lastSec then
          g.lastSec = sec
          S.dirty = true
          if sec >= 0 and sec < 5 then audio.play("tick", 1, 1 + (5 - sec) * 0.08) end
        end
        if left <= 0 then
          -- out of time: a random legal move is played, and too many of those forfeit the game
          local n = g.state.turn
          g.timeouts[n] = g.timeouts[n] + 1
          audio.play("timeout")
          if g.timeouts[n] >= config.MAX_TIMEOUTS then
            setToast(mover.name .. " ran out of time - forfeit", C.warn, 3000)
            rules.forfeit(g.state, n)
            finishGame("timeout")
          else
            local b, c = randomLegal(g.state)
            setToast(string.format("%s timed out (%d/%d) - random move", mover.name, g.timeouts[n], config.MAX_TIMEOUTS), C.warn, 3000)
            applyMove(g, b, c, "timeout")
          end
        end
      end
      if S.game == g and not g.nudged and isHuman(mover) and t - g.moveStart > config.NUDGE_AFTER * 1000 then
        g.nudged = true
        hw.tell(mover.name, "It's your move in Ultimate Tic-Tac-Toe!")
      end
    end
    if S.game == g and t - lastPresence > 2000 then
      lastPresence = t
      checkPresence(g)
      S.dirty = true
    end
  end
end

-- ------------------------------------------------------------------ startup

local function resumeSavedGame()
  if not fs.exists(config.SAVE_FILE) then return false end
  local h = fs.open(config.SAVE_FILE, "r")
  if not h then return false end
  local text = h.readAll()
  h.close()
  local ok, data = pcall(textutils.unserialise, text)
  if not ok or type(data) ~= "table" or not data.red or not data.blue then
    clearSavedGame()
    return false
  end
  local state = rules.replay(data.moves or {}, { tiebreak = data.tiebreak == true, first = data.first or 1 })
  if not state or state.winner ~= 0 then
    clearSavedGame()
    return false
  end
  local g = newGameRecord(data.red, data.blue, { first = data.first or 1 })
  g.state = state
  g.elapsed = data.elapsed or 0
  g.timeouts = data.timeouts or { 0, 0 }
  g.trailed = data.trailed or { 0, 0 }
  g.hints = data.hints or { 0, 0 }
  g.timer = data.timer or 0
  local hist = state.history[#state.history]
  if hist then g.last = { hist.b, hist.c } end
  S.game = g
  S.view = "game"
  armTurn(g)
  setToast("Game resumed", C.info, 3000)
  log("resumed saved game at move " .. state.moves)
  return true
end

local function shutdown()
  hw.allOff()
  if env.monitor then
    env.monitor.setBackgroundColor(colors.black)
    env.monitor.clear()
  end
  store:save()
end

local function main()
  local okLoad, how = store:load()
  log("store " .. tostring(how))
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
  audio.init(rep.speaker)
  audio.setEnabled(store:setting("sound"))
  audio.setVolume(store:setting("volume"))
  hw.setRedstone(store:setting("redstone"))
  audio.play("boot")
  hw.allOff()
  S.debug = fs.exists("uttt_debug.flag")
  if not resumeSavedGame() then
    S.view = "idle"
  end

  -- The game clock is a timer, and a lost timer stops it for good (the computer opponent then never moves). Timers are
  -- lost to server-thread peripheral calls, which is why those live in hw.worker. As a second line of defence there
  -- are two timers, any other event runs an overdue tick, and a gap of more than 1.5 s is logged.
  local tickA, tickB
  local lastTickAt = nowMs()
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
    elseif ev == "monitor_touch" then
      onTouch(a, b, c)
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
  pcall(function() store:save() end)
  pcall(hw.allOff)
  error(err, 0)
end
