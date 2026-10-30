-- uttt_rules.lua
-- Pure rules of Ultimate Tic-Tac-Toe (no peripherals, no I/O), shared by the game, the AI and the tests.
--
-- Board: 9 small boards (b = 1..9, row-major) of 9 cells (c = 1..9, row-major). A cell is addressed as
-- idx = (b - 1) * 9 + c. Players are 1 (Red) and 2 (Blue); 0 means empty.
-- Rules: a move in cell c sends the opponent to small board c. If that board is already decided (won or
-- full) the opponent may play in any open board. Three small boards in a row win the game. When no move is
-- left and nobody has a line, the game is a draw (the standard rule). Optional house rule "tiebreak": the player with more small boards wins.

local M = {}

local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
  { 1, 5, 9 }, { 3, 5, 7 },
}
M.LINES = LINES

-- Lines through each position, so a move only re-checks the lines that contain it.
local LINES_OF = {}
for pos = 1, 9 do
  LINES_OF[pos] = {}
  for li = 1, #LINES do
    local l = LINES[li]
    if l[1] == pos or l[2] == pos or l[3] == pos then
      LINES_OF[pos][#LINES_OF[pos] + 1] = li
    end
  end
end

M.EMPTY, M.RED, M.BLUE = 0, 1, 2
M.DRAW = 3 -- value of a full small board nobody won, and of a drawn game

function M.idx(b, c) return (b - 1) * 9 + c end
function M.boardOf(idx) return math.floor((idx - 1) / 9) + 1 end
function M.cellOf(idx) return (idx - 1) % 9 + 1 end

--- Global column and row (1..9) of a cell.
function M.toXY(b, c)
  local bx, by = (b - 1) % 3, math.floor((b - 1) / 3)
  local cx, cy = (c - 1) % 3, math.floor((c - 1) / 3)
  return bx * 3 + cx + 1, by * 3 + cy + 1
end

--- Board and cell for a global column and row (1..9).
function M.fromXY(x, y)
  local bx, cx = math.floor((x - 1) / 3), (x - 1) % 3
  local by, cy = math.floor((y - 1) / 3), (y - 1) % 3
  return by * 3 + bx + 1, cy * 3 + cx + 1
end

function M.other(p) return 3 - p end

--- New game. opts.tiebreak (default false = standard draw): true lets most small boards win a full board; opts.first: 1 or 2.
function M.new(opts)
  opts = opts or {}
  local s = {
    cells = {}, sub = {}, subLine = {}, turn = opts.first or 1, forced = nil, winner = 0, metaLine = nil,
    moves = 0, history = {}, tiebreak = opts.tiebreak == true, boards = { 0, 0, 0 },
  }
  for i = 1, 81 do s.cells[i] = 0 end
  for b = 1, 9 do s.sub[b] = 0 end
  return s
end

function M.copy(s)
  local n = {
    cells = {}, sub = {}, subLine = {}, turn = s.turn, forced = s.forced, winner = s.winner, metaLine = s.metaLine,
    moves = s.moves, history = {}, tiebreak = s.tiebreak, boards = { s.boards[1], s.boards[2], s.boards[3] },
  }
  for i = 1, 81 do n.cells[i] = s.cells[i] end
  for b = 1, 9 do n.sub[b] = s.sub[b]; n.subLine[b] = s.subLine[b] end
  for i = 1, #s.history do n.history[i] = s.history[i] end
  return n
end

--- Is (b, c) a legal move for the player to move?
function M.isLegal(s, b, c)
  if s.winner ~= 0 then return false, "game over" end
  if type(b) ~= "number" or type(c) ~= "number" or b < 1 or b > 9 or c < 1 or c > 9 then return false, "off board" end
  if s.sub[b] ~= 0 then return false, "that board is already decided" end
  if s.forced and s.forced ~= b then return false, "must play in board " .. s.forced end
  if s.cells[(b - 1) * 9 + c] ~= 0 then return false, "cell taken" end
  return true
end

--- Legal moves as a list of idx values, in board then cell order.
function M.legalMoves(s)
  local out = {}
  if s.winner ~= 0 then return out end
  local lo, hi = 1, 9
  if s.forced then lo, hi = s.forced, s.forced end
  for b = lo, hi do
    if s.sub[b] == 0 then
      local base = (b - 1) * 9
      for c = 1, 9 do
        if s.cells[base + c] == 0 then out[#out + 1] = base + c end
      end
    end
  end
  return out
end

local function lineOwner(values, li)
  local l = LINES[li]
  local a = values[l[1]]
  if (a == 1 or a == 2) and values[l[2]] == a and values[l[3]] == a then return a end
  return nil
end

local function subBoardCells(s, b)
  local base = (b - 1) * 9
  return { s.cells[base + 1], s.cells[base + 2], s.cells[base + 3], s.cells[base + 4], s.cells[base + 5],
    s.cells[base + 6], s.cells[base + 7], s.cells[base + 8], s.cells[base + 9] }
end

--- Result of the whole game from the current small-board state: 0 running, 1/2 winner, 3 draw.
local function evaluateGame(s)
  for li = 1, #LINES do
    local o = lineOwner(s.sub, li)
    if o then return o, li end
  end
  for b = 1, 9 do
    if s.sub[b] == 0 then return 0 end
  end
  if s.tiebreak then
    if s.boards[1] > s.boards[2] then return 1 end
    if s.boards[2] > s.boards[1] then return 2 end
  end
  return 3
end

--- Play (b, c) for the player to move. Mutates the state. Returns true, or false plus a reason.
function M.play(s, b, c)
  local ok, why = M.isLegal(s, b, c)
  if not ok then return false, why end
  local p = s.turn
  local base = (b - 1) * 9
  local rec = {
    b = b, c = c, p = p, forced = s.forced, sub = s.sub[b], subLine = s.subLine[b],
    winner = s.winner, metaLine = s.metaLine, boards1 = s.boards[1], boards2 = s.boards[2], boards3 = s.boards[3],
  }
  s.cells[base + c] = p
  s.moves = s.moves + 1

  local lines = LINES_OF[c]
  local won
  for i = 1, #lines do
    local l = LINES[lines[i]]
    if s.cells[base + l[1]] == p and s.cells[base + l[2]] == p and s.cells[base + l[3]] == p then
      won = lines[i]
      break
    end
  end
  if won then
    s.sub[b] = p
    s.subLine[b] = won
    s.boards[p] = s.boards[p] + 1
  else
    local full = true
    for i = 1, 9 do
      if s.cells[base + i] == 0 then full = false; break end
    end
    if full then
      s.sub[b] = 3
      s.boards[3] = s.boards[3] + 1
    end
  end

  s.history[#s.history + 1] = rec
  s.turn = 3 - p
  if s.sub[c] == 0 then s.forced = c else s.forced = nil end

  local result, line = evaluateGame(s)
  if result ~= 0 then
    s.winner = result
    s.metaLine = line
    s.forced = nil
  end
  return true
end

--- Undo the last move.
function M.undo(s)
  local rec = s.history[#s.history]
  if not rec then return false end
  s.history[#s.history] = nil
  s.cells[(rec.b - 1) * 9 + rec.c] = 0
  s.moves = s.moves - 1
  s.turn = rec.p
  s.forced = rec.forced
  s.sub[rec.b] = rec.sub
  s.subLine[rec.b] = rec.subLine
  s.winner = rec.winner
  s.metaLine = rec.metaLine
  s.boards[1], s.boards[2], s.boards[3] = rec.boards1, rec.boards2, rec.boards3
  return true
end

--- The player wins by resignation or forfeit. Sets the winner without a board line.
function M.forfeit(s, loser)
  if s.winner ~= 0 then return false end
  s.winner = 3 - loser
  s.forfeit = loser
  s.forced = nil
  return true
end

--- True when the board's three cells in line li belong to p (used by the AI and the renderer).
function M.cellsOwner(s, b)
  return subBoardCells(s, b)
end

--- Would p complete a line in small board b by playing cell c? (b must be open and c empty.)
function M.wouldWinBoard(s, b, c, p)
  local base = (b - 1) * 9
  local lines = LINES_OF[c]
  for i = 1, #lines do
    local l = LINES[lines[i]]
    local ok = true
    for k = 1, 3 do
      local pos = l[k]
      if pos ~= c and s.cells[base + pos] ~= p then ok = false; break end
    end
    if ok then return true end
  end
  return false
end

--- Does p have any move that wins small board b right now?
function M.canWinBoard(s, b, p)
  if s.sub[b] ~= 0 then return false end
  local base = (b - 1) * 9
  for c = 1, 9 do
    if s.cells[base + c] == 0 and M.wouldWinBoard(s, b, c, p) then return true end
  end
  return false
end

--- Replay a list of {b, c} pairs from a fresh game (used for save/resume and tests).
function M.replay(moves, opts)
  local s = M.new(opts)
  for i = 1, #moves do
    local ok, why = M.play(s, moves[i][1], moves[i][2])
    if not ok then return nil, "move " .. i .. ": " .. tostring(why) end
  end
  return s
end

--- The moves played so far as {b, c} pairs.
function M.moveList(s)
  local out = {}
  for i = 1, #s.history do out[i] = { s.history[i].b, s.history[i].c } end
  return out
end

--- A one-line text board for logs and tests: rows of 9 characters, '.' empty, 'X' Red, 'O' Blue.
function M.dump(s)
  local rows = {}
  for y = 1, 9 do
    local r = {}
    for x = 1, 9 do
      local b, c = M.fromXY(x, y)
      local v = s.cells[(b - 1) * 9 + c]
      r[#r + 1] = v == 1 and "X" or v == 2 and "O" or "."
    end
    rows[#rows + 1] = table.concat(r)
  end
  return table.concat(rows, "\n")
end

return M
