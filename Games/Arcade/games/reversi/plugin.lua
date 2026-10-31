-- games/reversi/plugin.lua
-- Reversi as an Arcade game.

local base = require("games.base")
local rules = require("games.reversi.rules")
local search = require("games.search")
local ui = require("arcade_ui")

local C = ui.C
local floor = math.floor
local SIZE = rules.SIZE

local LEVELS = {
  easy = { depth = 1, blunder = 0.35 },
  medium = { depth = 3 },
  hard = { depth = 8 },
}

-- What each square is worth: corners cannot be flipped, and the squares beside them hand a corner over.
local WEIGHTS = {
  { 100, -25, 10, 5, 5, 10, -25, 100 },
  { -25, -50, -2, -2, -2, -2, -50, -25 },
  { 10, -2, 3, 1, 1, 3, -2, 10 },
  { 5, -2, 1, 0, 0, 1, -2, 5 },
  { 5, -2, 1, 0, 0, 1, -2, 5 },
  { 10, -2, 3, 1, 1, 3, -2, 10 },
  { -25, -50, -2, -2, -2, -2, -50, -25 },
  { 100, -25, 10, 5, 5, 10, -25, 100 },
}

local function eval(s, seat)
  local other = 3 - seat
  -- with the board nearly full only the discs matter
  if s.score[1] + s.score[2] >= 56 then return (s.score[seat] - s.score[other]) * 10 end
  local total = 0
  for y = 1, SIZE do
    local row, weights = s.board[y], WEIGHTS[y]
    for x = 1, SIZE do
      local v = row[x]
      if v == seat then total = total + weights[x] elseif v == other then total = total - weights[x] end
    end
  end
  return total
end

local view = { scoreName = "DISCS" }

function view.layout(W, H)
  local L = base.grid(W, H, SIZE, SIZE)
  L.debug = { size = SIZE }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end

function view.score(state) return state.score[1], state.score[2] end

function view.drawBoard(L, match)
  local s = match.state
  base.boardGrid(L, function(c, r) return (c + r) % 2 == 0 and C.panel or C.pink end)
  local legal = {}
  if s.winner == 0 then
    for _, a in ipairs(rules.legalActions(s)) do legal[a.y * 10 + a.x] = true end
  end
  local hint = match.hint and os.epoch("local") < match.hintUntil and match.hint
  for y = 1, SIZE do
    for x = 1, SIZE do
      local cx, cy = L.colX[x], L.rowY[y]
      local v = s.board[y][x]
      if v ~= 0 then
        base.disc(cx + 1, cy, L.cw - 2, L.ch - 1, seatColor(v))
        if s.last and s.last[1] == x and s.last[2] == y then
          ui.fill(cx + floor(L.cw / 2) - 1, cy + floor(L.ch / 2), 2, 1, C.text)
        end
      elseif legal[y * 10 + x] then
        ui.fill(cx + floor(L.cw / 2) - 1, cy + floor(L.ch / 2), 2, 1, C.hi)
      end
      if hint and hint.x == x and hint.y == y then ui.frame(cx, cy, L.cw, L.ch, C.ok, 1) end
    end
  end
end

function view.actionAt(L, _, px, py)
  local x, y = base.cellAt(L, px, py)
  if not x then return nil end
  return { kind = "place", x = x, y = y }
end

function view.hintText(action) return string.format("Hint: column %d, row %d", action.x, action.y) end

function view.finalLine(match)
  local s = match.state
  if s.forfeit then
    return (s.winner == 1 and match.red or match.blue).name .. " WINS by forfeit", seatColor(s.winner)
  end
  if s.winner == 3 then return string.format("DRAW - %d discs each", s.score[1]), C.hi end
  local w = s.winner == 1 and match.red or match.blue
  return string.format("%s WINS %d-%d", w.name, s.score[s.winner], s.score[3 - s.winner]), seatColor(s.winner)
end

function view.howLine(r, duration)
  return string.format("%s  -  %d moves  -  %s  -  discs %d-%d", r.forfeit and "BY FORFEIT" or "BOARD DECIDED", r.state.moves, duration,
    r.state.score[1], r.state.score[2])
end

function view.scoreLine(match)
  local s = match.state
  return string.format("move %d - discs %d-%d", s.moves, s.score[1], s.score[2])
end

function view.historyLine(h) return string.format("%dmv %d-%d", h.moves or 0, h.boardsRed or 0, h.boardsBlue or 0) end

function view.onEvents(app, match, events)
  for _, ev in ipairs(events) do
    if ev.type == "place" then
      app.audio.play(ev.seat == 2 and "placeBlue" or "placeRed")
      if ev.flipped >= 6 then app.audio.later("capture", 110, 0.6, ev.seat == 2 and 0.8 or 1.2) end
    elseif ev.type == "pass" then
      app.setToast((ev.seat == 1 and match.red or match.blue).name .. " has no move and passes", C.warn, 2500)
    end
  end
end

local M = {
  id = "reversi", title = "Reversi", blurb = "Flip them all", color = "ok", accent = 0x35D07F,
  minSize = { w = 60, h = 40 }, cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  badges = {
    wipeout = { name = "Wipeout", text = "Win with nothing left for your opponent", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.other == 0
    end },
    landslide = { name = "Landslide", text = "Win by 30 discs or more", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.boards - sd.other >= 30
    end },
  },
}

function M.chooseAction(state, level, opts)
  return search.best(rules, state, eval, LEVELS[level] or LEVELS.medium, opts)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = s.score[1], boardsBlue = s.score[2] }
end

return base.fill(M)
