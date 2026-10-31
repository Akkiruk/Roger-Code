-- games/checkers/rules.lua
-- English draughts. Pure: no screen, sound or files. y = 1 is the top; dark squares are those with x + y odd.
-- Seat 1 starts at the bottom and moves up the board; seat 2 starts at the top. board[y][x] is 0, a seat for a man, or
-- that seat + KING for a king. A multi-jump is one action per jump: the turn stays, and s.chain names the piece.

local M = { SIZE = 8, KING = 10, DRAW_AFTER = 80 }

local SIZE, KING = M.SIZE, M.KING

function M.new(opts)
  local s = { turn = opts.first or 1, winner = 0, moves = 0, quiet = 0, board = {}, pieces = { 12, 12 } }
  for y = 1, SIZE do
    s.board[y] = {}
    for x = 1, SIZE do
      local dark = (x + y) % 2 == 1
      s.board[y][x] = (dark and y <= 3) and 2 or ((dark and y >= 6) and 1 or 0)
    end
  end
  return s
end

local function seatOf(v) return v % KING end
local function isKing(v) return v > KING end

local function directions(v)
  if isKing(v) then return { -1, 1 } end
  return seatOf(v) == 1 and { -1 } or { 1 }
end

local function onBoard(x, y) return x >= 1 and x <= SIZE and y >= 1 and y <= SIZE end

--- Every jump the piece at (x, y) can make, added to out.
local function addJumps(s, x, y, out)
  local v = s.board[y][x]
  local other = 3 - seatOf(v)
  for _, dy in ipairs(directions(v)) do
    for dx = -1, 1, 2 do
      local tx, ty = x + 2 * dx, y + 2 * dy
      if onBoard(tx, ty) and s.board[ty][tx] == 0 then
        local mid = s.board[y + dy][x + dx]
        if mid ~= 0 and seatOf(mid) == other then
          out[#out + 1] = { kind = "move", fx = x, fy = y, tx = tx, ty = ty }
        end
      end
    end
  end
end

local function addSteps(s, x, y, out)
  for _, dy in ipairs(directions(s.board[y][x])) do
    for dx = -1, 1, 2 do
      local tx, ty = x + dx, y + dy
      if onBoard(tx, ty) and s.board[ty][tx] == 0 then
        out[#out + 1] = { kind = "move", fx = x, fy = y, tx = tx, ty = ty }
      end
    end
  end
end

--- Every legal action. A capture must be taken, and a jump that can carry on must.
function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  if s.chain then
    addJumps(s, s.chain[1], s.chain[2], out)
    return out
  end
  local mine = {}
  for y = 1, SIZE do
    for x = 1, SIZE do
      local v = s.board[y][x]
      if v ~= 0 and seatOf(v) == s.turn then
        mine[#mine + 1] = { x, y }
        addJumps(s, x, y, out)
      end
    end
  end
  if #out > 0 then return out end
  for _, p in ipairs(mine) do addSteps(s, p[1], p[2], out) end
  return out
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= "move" then return false, "no such move" end
  local legal = M.legalActions(s)
  for _, m in ipairs(legal) do
    if m.fx == a.fx and m.fy == a.fy and m.tx == a.tx and m.ty == a.ty then return true end
  end
  if s.chain then return false, "keep jumping" end
  if legal[1] and math.abs(legal[1].fx - legal[1].tx) == 2 then return false, "must jump" end
  return false, "cannot move"
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p, other = s.turn, 3 - s.turn
  local v = s.board[a.fy][a.fx]
  local jumped = math.abs(a.tx - a.fx) == 2
  s.board[a.fy][a.fx] = 0
  if jumped then
    s.board[(a.fy + a.ty) / 2][(a.fx + a.tx) / 2] = 0
    s.pieces[other] = s.pieces[other] - 1
  end
  local crowned = not isKing(v) and a.ty == (p == 1 and 1 or SIZE)
  s.board[a.ty][a.tx] = crowned and v + KING or v
  s.quiet = (jumped or not isKing(v)) and 0 or s.quiet + 1
  s.moves = s.moves + 1
  s.last = { a.fx, a.fy, a.tx, a.ty }
  s.chain = nil
  local events = { { type = jumped and "jump" or "step", seat = p, crowned = crowned } }
  if jumped and not crowned then
    local more = {}
    addJumps(s, a.tx, a.ty, more)
    if #more > 0 then
      s.chain = { a.tx, a.ty }
      return s, events
    end
  end
  s.turn = other
  if #M.legalActions(s) == 0 then
    s.winner = p
  elseif s.quiet >= M.DRAW_AFTER then
    s.winner = 3
  end
  return s, events
end

function M.key(a) return a.fx .. "," .. a.fy .. ">" .. a.tx .. "," .. a.ty end

local LETTERS = { [0] = ".", [1] = "r", [2] = "b", [11] = "R", [12] = "B" }

function M.snapshot(s)
  local board = {}
  for y = 1, SIZE do
    local row = {}
    for x = 1, SIZE do row[x] = LETTERS[s.board[y][x]] end
    board[y] = table.concat(row)
  end
  return { board = board, chain = s.chain and (s.chain[1] .. "," .. s.chain[2]) or nil, quiet = s.quiet }
end

return M
