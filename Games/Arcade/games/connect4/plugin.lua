-- games/connect4/plugin.lua
-- Connect Four as an Arcade game.

local base = require("lib.arcade.base")
local rules = require("games.connect4.rules")
local search = require("games.search")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS = rules.COLS, rules.ROWS

local LEVELS = {
  easy = { depth = 2, blunder = 0.3 },
  medium = { depth = 4 },
  hard = { depth = 9 },
}

-- Every run of four cells on the board, for scoring a position.
local WINDOWS = {}
for c = 1, COLS do
  for r = 1, ROWS do
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
      local ex, ey = c + 3 * d[1], r + 3 * d[2]
      if ex >= 1 and ex <= COLS and ey >= 1 and ey <= ROWS then
        WINDOWS[#WINDOWS + 1] = { c, r, d[1], d[2] }
      end
    end
  end
end

--- A run counts only while one player alone can still finish it.
local function eval(s, seat)
  local total = 0
  local cells = s.cells
  for _, w in ipairs(WINDOWS) do
    local mine, theirs = 0, 0
    for i = 0, 3 do
      local v = cells[w[1] + i * w[3]][w[2] + i * w[4]]
      if v == seat then mine = mine + 1 elseif v then theirs = theirs + 1 end
    end
    if theirs == 0 then
      total = total + (mine == 3 and 50 or (mine == 2 and 10 or mine))
    elseif mine == 0 then
      total = total - (theirs == 3 and 50 or (theirs == 2 and 10 or theirs))
    end
  end
  return total
end

local view = { scoreName = "FOURS" }

function view.layout(W, H)
  local L = base.grid(W, H, COLS, ROWS)
  L.debug = { cols = COLS, rows = ROWS }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end

function view.drawBoard(L, match)
  local s = match.state
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.panel)
  local onLine = {}
  for _, cell in ipairs(s.line or {}) do onLine[cell[1] * 10 + cell[2]] = true end
  local hint = match.hint and os.epoch("local") < match.hintUntil and match.hint.col
  local falling = match.anim
  for c = 1, COLS do
    if hint == c then ui.frame(L.colX[c], L.y0, L.cw, L.bh, C.ok, 1) end
    for r = 1, ROWS do
      local x, y = L.colX[c] + 1, L.rowY[ROWS - r + 1] + 1
      local v = s.cells[c][r]
      if onLine[c * 10 + r] then ui.fill(x - 1, y - 1, L.cw, L.ch, C.hi) end
      if falling and falling.col == c and falling.row == r then v = nil end
      base.disc(x, y, L.cw - 2, L.ch - 2, v and seatColor(v) or C.bg)
      if s.last and s.last[1] == c and s.last[2] == r and not s.line then
        ui.fill(x + floor((L.cw - 2) / 2) - 1, y + floor((L.ch - 2) / 2), 2, 1, C.text)
      end
    end
  end
  if falling then
    -- it speeds up as it falls, then sits in its slot
    local t = base.animT(match) or 1
    local land = L.rowY[ROWS - falling.row + 1] + 1
    base.disc(L.colX[falling.col] + 1, floor(L.y0 + (land - L.y0) * t * t), L.cw - 2, L.ch - 2, seatColor(falling.seat))
  end
end

function view.actionAt(L, _, px, py)
  local c = base.cellAt(L, px, py)
  if not c then return nil end
  return { kind = "drop", col = c }
end

function view.hintText(action) return "Hint: column " .. action.col end

function view.finalLine(match)
  local s = match.state
  if s.winner == 3 then return "DRAW - the board is full", C.hi end
  local w = s.winner == 1 and match.red or match.blue
  if s.forfeit then return w.name .. " WINS by forfeit", seatColor(s.winner) end
  return w.name .. " connects four!", seatColor(s.winner)
end

function view.howLine(r, duration)
  local how = r.forfeit and "BY FORFEIT" or (r.winner == 3 and "BOARD FULL" or "FOUR IN A ROW")
  return string.format("%s  -  %d moves  -  %s", how, r.state.moves, duration)
end

function view.scoreLine(match) return "move " .. match.state.moves end

function view.onEvents(app, match, events)
  for _, ev in ipairs(events) do
    if ev.type == "drop" then
      app.audio.play("disc_drop")
      base.animate(match, 90 * (ROWS - ev.row + 2), { col = ev.col, row = ev.row, seat = ev.seat })
    end
  end
end

local M = {
  id = "connect4", title = "Connect Four", short = "Connect 4", chatTag = "FOUR", blurb = "Four in a row wins",
  color = "info", accent = 0x3CD3E6, minSize = { w = 60, h = 40 },
  cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Take turns dropping a piece into a column. It falls to the lowest free slot.",
    "",
    "Line up four of your pieces, across, up or on a diagonal, to win. If the board fills first, the game is a draw.",
    "",
    "Tap a column to drop your piece.",
  },
  badges = {
    quick = { name = "Speed Four", text = "Win in 11 moves or fewer", test = function(m, _, _, won)
      return won and not m.forfeit and m.moves <= 11
    end },
    full = { name = "To The Top", text = "Finish a game on a full board", test = function(m)
      return m.moves >= COLS * ROWS
    end },
  },
}

function M.chooseAction(state, level, opts)
  return search.best(rules, state, eval, LEVELS[level] or LEVELS.medium, opts)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = (s.winner == 1 and not s.forfeit) and 1 or 0, boardsBlue = (s.winner == 2 and not s.forfeit) and 1 or 0 }
end

return base.fill(M)
