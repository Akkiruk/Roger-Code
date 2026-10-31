-- games/reversi/rules.lua
-- Reversi (Othello). Pure: no screen, sound or files. board[y][x] is 0, 1 or 2, with y = 1 at the top.

local M = { SIZE = 8 }

local SIZE = M.SIZE
local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function M.new(opts)
  local first = opts.first or 1
  local other = 3 - first
  local s = { turn = first, winner = 0, moves = 0, board = {}, score = { 2, 2 } }
  for y = 1, SIZE do
    s.board[y] = {}
    for x = 1, SIZE do s.board[y][x] = 0 end
  end
  s.board[5][4], s.board[4][5] = first, first
  s.board[4][4], s.board[5][5] = other, other
  return s
end

--- How many discs a line from (x, y) would flip, walking in direction (dx, dy).
local function lineFlips(board, x, y, dx, dy, p)
  local other, n = 3 - p, 0
  local cx, cy = x + dx, y + dy
  while cx >= 1 and cx <= SIZE and cy >= 1 and cy <= SIZE do
    local v = board[cy][cx]
    if v == other then
      n = n + 1
    elseif v == p then
      return n
    else
      return 0
    end
    cx, cy = cx + dx, cy + dy
  end
  return 0
end

local function canPlace(board, x, y, p)
  if board[y][x] ~= 0 then return false end
  for _, d in ipairs(DIRECTIONS) do
    if lineFlips(board, x, y, d[1], d[2], p) > 0 then return true end
  end
  return false
end

local function hasMove(board, p)
  for y = 1, SIZE do
    for x = 1, SIZE do
      if canPlace(board, x, y, p) then return true end
    end
  end
  return false
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= "place" or not s.board[a.y] or not s.board[a.y][a.x] then return false, "no such square" end
  if s.board[a.y][a.x] ~= 0 then return false, "That square is taken" end
  if not canPlace(s.board, a.x, a.y, s.turn) then return false, "That flips nothing" end
  return true
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p, other, board = s.turn, 3 - s.turn, s.board
  local flipped, cells = 0, {}
  board[a.y][a.x] = p
  for _, d in ipairs(DIRECTIONS) do
    local n = lineFlips(board, a.x, a.y, d[1], d[2], p)
    for i = 1, n do
      board[a.y + d[2] * i][a.x + d[1] * i] = p
      cells[#cells + 1] = { a.x + d[1] * i, a.y + d[2] * i }
    end
    flipped = flipped + n
  end
  s.score[p] = s.score[p] + flipped + 1
  s.score[other] = s.score[other] - flipped
  s.moves = s.moves + 1
  s.last = { a.x, a.y }
  local events = { { type = "place", seat = p, x = a.x, y = a.y, flipped = flipped, cells = cells } }
  if hasMove(board, other) then
    s.turn = other
  elseif hasMove(board, p) then
    events[#events + 1] = { type = "pass", seat = other }
  else
    local a1, a2 = s.score[1], s.score[2]
    s.winner = a1 > a2 and 1 or (a2 > a1 and 2 or 3)
  end
  return s, events
end

function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  for y = 1, SIZE do
    for x = 1, SIZE do
      if canPlace(s.board, x, y, s.turn) then out[#out + 1] = { kind = "place", x = x, y = y } end
    end
  end
  return out
end

function M.key(a) return a.x .. "," .. a.y end

function M.snapshot(s)
  local board = {}
  for y = 1, SIZE do
    local row = {}
    for x = 1, SIZE do row[x] = s.board[y][x] == 0 and "." or tostring(s.board[y][x]) end
    board[y] = table.concat(row)
  end
  return { board = board, score = { s.score[1], s.score[2] } }
end

return M
