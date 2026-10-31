-- games/dots/rules.lua
-- Dots and Boxes on five boxes by five. Pure: no screen, sound or files.
-- h[y][x] joins dot (x, y) to (x + 1, y); v[y][x] joins dot (x, y) to (x, y + 1). Each holds the seat that drew it, or 0.

local M = { SIZE = 5 }

local SIZE = M.SIZE
local LINES = 2 * SIZE * (SIZE + 1)

function M.new(opts)
  local s = { turn = opts.first or 1, winner = 0, moves = 0, h = {}, v = {}, boxes = {}, score = { 0, 0 } }
  for y = 1, SIZE + 1 do
    s.h[y] = {}
    for x = 1, SIZE do s.h[y][x] = 0 end
  end
  for y = 1, SIZE do
    s.v[y], s.boxes[y] = {}, {}
    for x = 1, SIZE + 1 do s.v[y][x] = 0 end
    for x = 1, SIZE do s.boxes[y][x] = 0 end
  end
  return s
end

local function lineTable(s, dir) return dir == "h" and s.h or s.v end
M.lineTable = lineTable

--- How many sides of a box are drawn.
local function sides(s, x, y)
  local n = 0
  if s.h[y][x] ~= 0 then n = n + 1 end
  if s.h[y + 1][x] ~= 0 then n = n + 1 end
  if s.v[y][x] ~= 0 then n = n + 1 end
  if s.v[y][x + 1] ~= 0 then n = n + 1 end
  return n
end
M.sides = sides

--- The one or two boxes a line borders.
local function neighbours(a)
  local out = {}
  if a.dir == "h" then
    if a.y > 1 then out[#out + 1] = { a.x, a.y - 1 } end
    if a.y <= SIZE then out[#out + 1] = { a.x, a.y } end
  else
    if a.x > 1 then out[#out + 1] = { a.x - 1, a.y } end
    if a.x <= SIZE then out[#out + 1] = { a.x, a.y } end
  end
  return out
end
M.neighbours = neighbours

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= "line" then return false, "no such line" end
  local row = lineTable(s, a.dir)[a.y]
  if not row or row[a.x] == nil then return false, "no such line" end
  if row[a.x] ~= 0 then return false, "That line is already drawn" end
  return true
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p = s.turn
  lineTable(s, a.dir)[a.y][a.x] = p
  s.moves = s.moves + 1
  s.last = { dir = a.dir, x = a.x, y = a.y }
  local scored = 0
  for _, box in ipairs(neighbours(a)) do
    if sides(s, box[1], box[2]) == 4 then
      s.boxes[box[2]][box[1]] = p
      scored = scored + 1
    end
  end
  s.score[p] = s.score[p] + scored
  if s.moves == LINES then
    s.winner = s.score[1] > s.score[2] and 1 or (s.score[2] > s.score[1] and 2 or 3)
  end
  if scored == 0 then s.turn = 3 - p end
  return s, { { type = "line", seat = p, scored = scored } }
end

function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  for y = 1, SIZE + 1 do
    for x = 1, SIZE do
      if s.h[y][x] == 0 then out[#out + 1] = { kind = "line", dir = "h", x = x, y = y } end
    end
  end
  for y = 1, SIZE do
    for x = 1, SIZE + 1 do
      if s.v[y][x] == 0 then out[#out + 1] = { kind = "line", dir = "v", x = x, y = y } end
    end
  end
  return out
end

function M.key(a) return a.dir .. "," .. a.x .. "," .. a.y end

function M.snapshot(s)
  local function rows(t, chars)
    local out = {}
    for y, row in ipairs(t) do
      local line = {}
      for x, v in ipairs(row) do line[x] = chars(v) end
      out[y] = table.concat(line)
    end
    return out
  end
  local function drawn(v) return v ~= 0 and "1" or "0" end
  return {
    h = rows(s.h, drawn), v = rows(s.v, drawn),
    boxes = rows(s.boxes, function(v) return v == 0 and "." or tostring(v) end),
    score = { s.score[1], s.score[2] },
  }
end

return M
