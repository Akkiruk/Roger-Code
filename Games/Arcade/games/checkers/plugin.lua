-- games/checkers/plugin.lua
-- Checkers as an Arcade game. Tap a piece, then tap where it goes.

local base = require("games.base")
local rules = require("games.checkers.rules")
local search = require("games.search")
local ui = require("arcade_ui")

local C = ui.C
local floor = math.floor
local SIZE, KING = rules.SIZE, rules.KING

local LEVELS = {
  easy = { depth = 2, blunder = 0.25 },
  medium = { depth = 4 },
  hard = { depth = 10 },
}

--- Material first, then men that have come further and pieces nearer the middle.
local function eval(s, seat)
  local total = 0
  for y = 1, SIZE do
    local row = s.board[y]
    for x = 1, SIZE do
      local v = row[x]
      if v ~= 0 then
        local owner = v % KING
        local worth
        if v > KING then
          worth = 165 - math.abs(x - 4.5) - math.abs(y - 4.5)
        else
          worth = 100 + 2 * (owner == 1 and 8 - y or y - 1)
        end
        total = total + (owner == seat and worth or -worth)
      end
    end
  end
  return total
end

local view = { scoreName = "CAPTURES" }

function view.layout(W, H)
  local L = base.grid(W, H, SIZE, SIZE)
  L.debug = { size = SIZE }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end

function view.score(state) return 12 - state.pieces[2], 12 - state.pieces[1] end

function view.moveNumber(state) return state.moves + 1 end

local function legalFrom(s, x, y)
  local out = {}
  for _, a in ipairs(rules.legalActions(s)) do
    if a.fx == x and a.fy == y then out[#out + 1] = a end
  end
  return out
end

local function drawPiece(L, x, y, v)
  base.disc(x + 1, y + 1, L.cw - 2, L.ch - 2, seatColor(v % KING))
  if v > KING then ui.fill(x + floor(L.cw / 2) - 1, y + floor(L.ch / 2) - 1, 3, 2, C.hi) end
end

function view.drawBoard(L, match)
  local s = match.state
  local sel = match.extras.sel
  local slide = match.anim
  base.boardGrid(L, function(c, r) return (c + r) % 2 == 1 and C.panel or C.bg end)
  local legal = {}
  local hint = match.hint and os.epoch("local") < match.hintUntil and match.hint
  if s.winner == 0 then
    for _, a in ipairs(rules.legalActions(s)) do legal[#legal + 1] = a end
  end
  local function mark(x, y, color) ui.fill(L.colX[x], L.rowY[y], L.cw, L.ch, color) end
  local last = s.last
  if last then mark(last[3], last[4], C.pink) end
  for _, a in ipairs(legal) do
    if not sel then mark(a.fx, a.fy, C.hiTint) end
  end
  if sel then mark(sel[1], sel[2], C.hi) end
  if hint then
    mark(hint.fx, hint.fy, C.ok)
    mark(hint.tx, hint.ty, C.ok)
  end
  for y = 1, SIZE do
    for x = 1, SIZE do
      local v = s.board[y][x]
      if v ~= 0 and not (slide and slide.tx == x and slide.ty == y) then
        drawPiece(L, L.colX[x], L.rowY[y], v)
      end
    end
  end
  if slide then
    local t = base.animT(match) or 1
    local fromX, fromY = L.colX[slide.fx], L.rowY[slide.fy]
    if slide.taken and floor(t * 6) % 2 == 0 then
      drawPiece(L, L.colX[(slide.fx + slide.tx) / 2], L.rowY[(slide.fy + slide.ty) / 2], slide.taken)
    end
    drawPiece(L, floor(fromX + (L.colX[slide.tx] - fromX) * t), floor(fromY + (L.rowY[slide.ty] - fromY) * t), s.board[slide.ty][slide.tx])
  end
  for _, a in ipairs(legal) do
    if sel and a.fx == sel[1] and a.fy == sel[2] then
      ui.fill(L.colX[a.tx] + floor(L.cw / 2) - 1, L.rowY[a.ty] + floor(L.ch / 2), 2, 1, C.hi)
    end
  end
end

--- A tap on your own piece picks it up; a tap on one of its landing squares moves it.
function view.actionAt(L, match, px, py)
  local x, y = base.cellAt(L, px, py)
  if not x then return nil end
  local s = match.state
  local sel = match.extras.sel
  local v = s.board[y][x]
  if v ~= 0 and v % KING == s.turn then
    if #legalFrom(s, x, y) > 0 then return { kind = "select", x = x, y = y } end
    return { kind = "move", fx = x, fy = y, tx = x, ty = y } -- no such move: the rules say why it cannot go
  end
  if sel then return { kind = "move", fx = sel[1], fy = sel[2], tx = x, ty = y } end
  return nil
end

function view.onSelect(match, action)
  match.extras.sel = { action.x, action.y }
end

function view.refusal(_, why)
  if why == "must jump" then return "You must jump" end
  if why == "keep jumping" then return "Keep jumping with the same piece" end
  if why == "cannot move" then return "That piece cannot go there" end
  return why
end

function view.hintText(a) return string.format("Hint: from %d,%d to %d,%d", a.fx, a.fy, a.tx, a.ty) end

function view.prompt(state, name)
  if state.chain then return name .. " must jump again", C.hi end
  return name .. " to move", state.turn == 1 and C.red or C.blue
end

function view.finalLine(match)
  local s = match.state
  if s.winner == 3 then return "DRAW - no progress for 40 moves each", C.hi end
  local w = s.winner == 1 and match.red or match.blue
  if s.forfeit then return w.name .. " WINS by forfeit", seatColor(s.winner) end
  local why = s.pieces[3 - s.winner] == 0 and "took every piece" or "left no move"
  return w.name .. " WINS - " .. why, seatColor(s.winner)
end

function view.howLine(r, duration)
  local s = r.state
  local how = r.forfeit and "BY FORFEIT" or (r.winner == 3 and "NO PROGRESS" or "NO MOVES LEFT")
  return string.format("%s  -  %d moves  -  %s  -  pieces %d-%d", how, s.moves, duration, s.pieces[1], s.pieces[2])
end

function view.scoreLine(match)
  local s = match.state
  return string.format("move %d - pieces %d-%d", s.moves, s.pieces[1], s.pieces[2])
end

function view.historyLine(h) return string.format("%dmv %d-%d", h.moves or 0, h.boardsRed or 0, h.boardsBlue or 0) end

function view.onEvents(app, match, events)
  match.extras.sel = match.state.chain and { match.state.chain[1], match.state.chain[2] } or nil
  for _, ev in ipairs(events) do
    if ev.fx then
      base.animate(match, ev.type == "jump" and 420 or 260, {
        fx = ev.fx, fy = ev.fy, tx = ev.tx, ty = ev.ty, taken = ev.type == "jump" and (3 - ev.seat) or nil,
      })
    end
    if ev.type == "jump" then
      app.audio.play(ev.seat == 2 and "captureBlue" or "captureRed")
    elseif ev.type == "step" then
      app.audio.play(ev.seat == 2 and "placeBlue" or "placeRed")
    end
    if ev.crowned then
      app.audio.later("capture", 150, 0.7, 1.4)
      app.setToast((ev.seat == 1 and match.red or match.blue).name .. " has a king!", seatColor(ev.seat), 2000)
    end
  end
end

function view.onResume(match)
  local chain = match.state.chain
  match.extras.sel = chain and { chain[1], chain[2] } or nil
end

local M = {
  id = "checkers", title = "Checkers", blurb = "Jump, crown, clear the board", color = "warn", accent = 0xFF9F43,
  minSize = { w = 60, h = 40 }, cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Pieces move one square diagonally forward. Tap a piece, then tap where it goes.",
    "",
    "Jump over an enemy piece to an empty square behind it to capture it. If you can jump, you must, and a jump that can carry on must carry on with the same piece.",
    "",
    "A piece that reaches the far row becomes a king, marked in yellow, and its turn ends there. Kings move and jump both forwards and backwards.",
    "",
    "Take every enemy piece, or leave your opponent with no move, to win. " .. (rules.DRAW_AFTER / 2) .. " moves each with no capture and no ordinary piece moved is a draw.",
  },
  badges = {
    perfect = { name = "Untouched", text = "Win without losing a piece", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.other == 0
    end },
    long = { name = "Long Game", text = "Finish a game of 80+ moves", test = function(m) return m.moves >= 80 end },
  },
}

function M.chooseAction(state, level, opts)
  return search.best(rules, state, eval, LEVELS[level] or LEVELS.medium, opts)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = 12 - s.pieces[2], boardsBlue = 12 - s.pieces[1] }
end

return base.fill(M)
