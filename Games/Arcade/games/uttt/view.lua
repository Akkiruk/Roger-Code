-- games/uttt/view.lua
-- What the Arcade asks of Ultimate Tic-Tac-Toe's screen. The shell draws everything around the board.

local board = require("games.uttt.board")
local rules = require("games.uttt.rules")
local ui = require("lib.arcade.ui")

local M = {}
local C = ui.C
local floor, max, min = math.floor, math.max, math.min
local FLASH_MS = 350

M.seatLabels = { "RED  (X)", "BLUE  (O)" }
M.seatMarks = { "RED  X", "BLUE  O" }
M.scoreName = "BOARDS"

local function nowMs() return os.epoch("local") end

function M.layout(W, H)
  return board.layout(W, H)
end

--- The score between the two player cards.
function M.score(state)
  return state.boards[1], state.boards[2]
end

function M.moveNumber(state)
  return state.moves + 1
end

--- Draw the board. match may be a live match or the finished one.
function M.drawBoard(L, match)
  local s = match.state
  local x = match.extras
  local flash = x.flash and x.flash.on and x.flash or nil
  local hint = (match.hint and nowMs() < match.hintUntil) and { match.hint.b, match.hint.c } or nil
  board.board(L, { state = s, last = x.last, hint = hint, flash = flash })
end

--- Mini map on one side, recent moves on the other. Only when the layout has side columns.
function M.drawSides(L, match, leftX, rightX, w)
  local mx, my = leftX + floor((w - 11) / 2), L.y0 + L.bh - 12
  ui.small("BOARDS", leftX + floor(w / 2), my - 2, C.line, C.bg, "center")
  local s = match.state
  for b = 1, 9 do
    local x = mx + ((b - 1) % 3) * 4
    local y = my + floor((b - 1) / 3) * 3
    local o = s.sub[b]
    local col = o == 1 and C.red or (o == 2 and C.blue or (o == 3 and C.tie or C.panel))
    if o == 0 and (s.forced == nil or s.forced == b) then col = C.hiTint end
    ui.fill(x, y, 3, 2, col)
  end
  local hist = s.history
  local ry = L.y0 + 19
  ui.small("MOVES", rightX + floor(w / 2), ry, C.line, C.bg, "center")
  for i = 0, 4 do
    local h = hist[#hist - i]
    if h then
      ui.small(string.format("%d %s%d-%d", #hist - i, h.p == 1 and "X" or "O", h.b, h.c), rightX, ry + 2 + i * 2, h.p == 1 and C.red or C.blue, C.bg, "left", w)
    end
  end
end

--- The action a touch on the board means, or nil.
function M.actionAt(L, _match, px, py)
  local b, c = board.cellAt(L, px, py)
  if not b then return nil end
  return { kind = "move", b = b, c = c }
end

--- Why an illegal action was refused, for the wall.
function M.refusal(state, why)
  if why == "cell taken" then return "That square is taken" end
  if why == "that board is already decided" then return "That board is already decided" end
  if state.forced then return string.format("You must play in board %d", state.forced) end
  return why
end

--- The status line while a human is to move.
function M.prompt(state, moverName)
  if state.forced then
    return string.format("%s: play in board %d (lit)", moverName, state.forced), state.turn == 1 and C.red or C.blue
  end
  return string.format("%s: FREE MOVE - anywhere!", moverName), C.hi
end

function M.hintText(action)
  return string.format("Hint: board %d, square %d", action.b, action.c)
end

--- The headline under the final board: who won and exactly why.
function M.finalLine(match)
  local s = match.state
  if s.winner == 3 then return "DRAW - no boards left to play", C.hi end
  local w = s.winner == 1 and match.red or match.blue
  local color = s.winner == 1 and C.red or C.blue
  if s.forfeit then return w.name .. " WINS by forfeit", color end
  if s.metaLine then
    local l = rules.LINES[s.metaLine]
    return string.format("%s WINS - boards %d, %d, %d in a line", w.name, l[1], l[2], l[3]), color
  end
  return string.format("%s WINS - most boards (%d-%d)", w.name, s.boards[s.winner], s.boards[3 - s.winner]), color
end

--- One line on the results page: how the match ended.
function M.howLine(r, duration)
  local s = r.state
  local how = r.forfeit and "BY FORFEIT" or (r.winner == 3 and "NOTHING LEFT TO PLAY" or "THREE BOARDS IN A LINE")
  if not r.forfeit and r.winner ~= 3 and s.metaLine == nil then how = "MOST BOARDS WINS" end
  return string.format("%s  -  %d moves  -  %s  -  boards %d-%d", how, s.moves, duration, s.boards[1], s.boards[2])
end

--- The whisper to both players after a match.
function M.announceWin(match, summary, signed)
  local s = match.state
  local w, l = s.winner == 1 and match.red or match.blue, s.winner == 1 and match.blue or match.red
  local text = string.format("%s beat %s at Ultimate Tic-Tac-Toe in %d moves (%d-%d boards)%s", w.name, l.name, s.moves,
    s.boards[s.winner], s.boards[3 - s.winner], s.forfeit and " by forfeit" or "")
  local sw = summary[s.winner == 1 and "red" or "blue"]
  if summary.ranked and sw and sw.elo then text = text .. string.format(" [%d %s]", sw.elo, signed(sw.delta or 0)) end
  return text
end

--- A short line for the scoreboard monitor while a match runs.
function M.scoreLine(match)
  local s = match.state
  return string.format("move %d - boards %d-%d", s.moves, s.boards[1], s.boards[2])
end

function M.historyLine(h)
  return string.format("%dmv %d-%d", h.moves or 0, h.boardsRed or 0, h.boardsBlue or 0)
end

--- Turn what the rules reported into sound, toasts and marks on the board. Nothing here blocks, so touches stay live.
function M.onEvents(app, match, events)
  local s = match.state
  local x = match.extras
  for _, ev in ipairs(events) do
    if ev.type == "placed" then
      x.last = { ev.b, ev.c }
      x.flash = { b = ev.b, c = ev.c, on = true, untilAt = nowMs() + FLASH_MS }
      -- the largest deficit each player has been in, for the comeback achievement
      x.trailed[1] = max(x.trailed[1], s.boards[2] - s.boards[1])
      x.trailed[2] = max(x.trailed[2], s.boards[1] - s.boards[2])
      if s.winner == 0 then
        if ev.captured then
          app.audio.play(ev.seat == 2 and "captureBlue" or "captureRed")
          app.audio.later("capture", 110, 0.6, ev.seat == 2 and 0.8 or 1.2)
          local name = (ev.seat == 1 and match.red or match.blue).name
          app.setToast(string.format("%s takes board %d!", name, ev.b), ev.seat == 1 and C.red or C.blue, 2500)
        else
          app.audio.play(ev.seat == 2 and "placeBlue" or "placeRed")
        end
      end
    elseif ev.type == "free" then
      app.audio.later("freeMove", 160)
    elseif ev.type == "sent" then
      app.audio.later("force", 140)
      if ev.threat then app.audio.later("threat", 320) end
    end
  end
end

--- Things that fade by themselves. Returns true when the screen needs redrawing.
function M.tick(match, t)
  local flash = match.extras.flash
  if flash and flash.on and t > flash.untilAt then
    flash.on = false
    return true
  end
  return false
end

--- Rebuild what is drawn on the board after a resume.
function M.onResume(match)
  local hist = match.state.history
  local h = hist[#hist]
  if h then match.extras.last = { h.b, h.c } end
end

-- ------------------------------------------------------------------ attract

--- One step of the demo game on the idle screen. Returns true when it changed.
function M.demoStep(demo, t, choose)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 5000) then
    demo.state, demo.nextAt, demo.last, demo.finishedAt = rules.new({ tiebreak = false, first = math.random(2) }), t + 1200, nil, nil
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  local s = demo.state
  local action = choose(s, "easy", { ms = 0, maxNodes = 200 })
  rules.play(s, action.b, action.c)
  demo.last = { action.b, action.c }
  demo.nextAt = t + 900
  if s.winner ~= 0 then demo.finishedAt = t end
  return true
end

local function topLine(i, row, x, y, w)
  local color = i == 1 and C.hi or (i == 2 and C.text or C.line)
  ui.small(string.format("%d. %s", row.rank, row.name), x, y, color, C.bg, "left", w - 6)
  ui.small(tostring(row.value), x + w, y, color, C.bg, "right")
end

--- The idle screen's title, demo board and side panels. Returns the y for the prompt below it all.
function M.drawAttract(W, H, demo, store)
  ui.text("ULTIMATE", floor(W / 2), 2, C.hi, "center")
  local tw1 = ui.textWidth("TIC-")
  local tw2 = ui.textWidth("TAC-")
  local tw3 = ui.textWidth("TOE")
  local total = tw1 + tw2 + tw3 + 2
  local tx = floor((W - total) / 2)
  ui.text("TIC-", tx, 11, C.red, "left")
  ui.text("TAC-", tx + tw1 + 1, 11, C.text, "left")
  ui.text("TOE", tx + tw1 + tw2 + 2, 11, C.blue, "left")

  local cw = max(3, floor((W - 44) / 9 / 1.0))
  cw = min(cw, 7)
  local ch = max(2, min(floor(cw * 2 / 3 + 0.5), floor((H - 21 - 17) / 9)))
  local bw, bh = 9 * cw + 4, 9 * ch + 2
  local bx = floor((W - bw) / 2)
  local by = 21
  local Ld = board.layoutAt(bx, by, cw, ch, 2, 1)
  if demo.state then board.board(Ld, { state = demo.state, last = demo.last }) end

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
  return by + bh + 3
end

--- What the debug dump shows of a match, for tests.
function M.debug(match)
  local s = match.state
  return { turn = s.turn, forced = s.forced, winner = s.winner, moves = s.moves, boards = s.boards, history = rules.moveList(s) }
end

return M
