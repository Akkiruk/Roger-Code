-- games/connect4/rules.lua
-- Connect Four. Pure: no screen, sound or files. cells[col][row] counts rows from the bottom.

local M = { COLS = 7, ROWS = 6 }

local COLS, ROWS = M.COLS, M.ROWS
local CENTRE_FIRST = { 4, 3, 5, 2, 6, 1, 7 }
local DIRECTIONS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

function M.new(opts)
  local s = { turn = opts.first or 1, winner = 0, moves = 0, cells = {} }
  for c = 1, COLS do s.cells[c] = {} end
  return s
end

--- The four or more cells in a line through (c, r), or nil.
local function winningLine(s, c, r, p)
  for _, d in ipairs(DIRECTIONS) do
    local line = { { c, r } }
    for sign = -1, 1, 2 do
      local x, y = c + d[1] * sign, r + d[2] * sign
      while s.cells[x] and s.cells[x][y] == p do
        line[#line + 1] = { x, y }
        x, y = x + d[1] * sign, y + d[2] * sign
      end
    end
    if #line >= 4 then return line end
  end
  return nil
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= "drop" or not s.cells[a.col] then return false, "no such column" end
  if #s.cells[a.col] >= ROWS then return false, "That column is full" end
  return true
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p, col = s.turn, s.cells[a.col]
  col[#col + 1] = p
  s.moves = s.moves + 1
  s.last = { a.col, #col }
  local line = winningLine(s, a.col, #col, p)
  if line then
    s.winner, s.line = p, line
  elseif s.moves == COLS * ROWS then
    s.winner = 3
  end
  s.turn = 3 - p
  return s, { { type = "drop", seat = p, col = a.col, row = #col } }
end

--- Centre columns first, which is what lets the search cut off early.
function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  for _, c in ipairs(CENTRE_FIRST) do
    if #s.cells[c] < ROWS then out[#out + 1] = { kind = "drop", col = c } end
  end
  return out
end

function M.key(a) return tostring(a.col) end

--- The position as plain data, for tests.
function M.snapshot(s)
  local board = {}
  for r = ROWS, 1, -1 do
    local row = {}
    for c = 1, COLS do row[c] = s.cells[c][r] and tostring(s.cells[c][r]) or "." end
    board[#board + 1] = table.concat(row)
  end
  return { board = board }
end

return M
