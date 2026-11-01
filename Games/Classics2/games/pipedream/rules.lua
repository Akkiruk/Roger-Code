-- games/pipedream/rules.lua
-- Pipe Dream, after the 1989 original. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- s.grid[y][x] is false for an empty square, or a table: { piece, wet } for a pipe, { start, dir, wet } for the start piece,
-- { block } for an obstacle. wet says which of a pipe's sides the flooz has used, so a cross can be filled both ways.
-- s.flow is the head of the flooz, nil until the countdown runs out. Its side `from` is where it came in and `to` where it
-- leaves. When it can't go on the level ends, and s.pipes against s.need says whether the run does too.

local M = { TICK_MS = 100, COLS = 10, ROWS = 7, QUEUE = 5 }

local max, min, abs = math.max, math.min, math.abs

local UP, RIGHT, DOWN, LEFT = 1, 2, 3, 4
M.UP, M.RIGHT, M.DOWN, M.LEFT = UP, RIGHT, DOWN, LEFT

local DX = { 0, 1, 0, -1 }
local DY = { -1, 0, 1, 0 }
local OPPOSITE = { DOWN, LEFT, UP, RIGHT }

-- every piece the dispenser can give, and the sides each is open on
M.PIECES = { "h", "v", "ne", "nw", "se", "sw", "x" }
M.OPEN = {
  h = { [LEFT] = true, [RIGHT] = true },
  v = { [UP] = true, [DOWN] = true },
  ne = { [UP] = true, [RIGHT] = true },
  nw = { [UP] = true, [LEFT] = true },
  se = { [DOWN] = true, [RIGHT] = true },
  sw = { [DOWN] = true, [LEFT] = true },
  x = { [UP] = true, [RIGHT] = true, [DOWN] = true, [LEFT] = true },
}

local PIPE_POINTS = 50     -- for each pipe filled, and for the second pass through a cross
local RUSH_POINTS = 50     -- on top, for each pipe filled while rushing
local LENGTH_POINTS = 50   -- level bonus, for each pipe filled
local UNUSED_COST = 25     -- off the level bonus, for each pipe left dry on the board
local REPLACE_COST = 25    -- off the level bonus, for each piece blown up
local REPLACE_STEPS = 6    -- how long a blown up piece keeps the next one waiting
local RUSH_STEPS = 2       -- steps a tile takes when rushing
local PAUSE_STEPS = 35     -- how long LEVEL CLEAR stays up
local ENDING_STEPS = 25    -- the leak stays in view this long before the final board
local NEED_START, NEED_STEP, NEED_CAP = 12, 2, 40
local COUNTDOWN_START, COUNTDOWN_STEP, COUNTDOWN_MIN = 150, 12, 40
local FLOW_START, FLOW_STEP, FLOW_MIN = 25, 2, 4
local OBSTACLE_STEP, OBSTACLE_CAP = 2, 16
local BOT_EVERY = 5        -- steps between the bot's moves
local BOT_SPARE = 2        -- pipes it lays past the minimum before it stops and rushes

--- The length of pipe a level demands.
function M.need(level) return min(NEED_CAP, NEED_START + (level - 1) * NEED_STEP) end

--- Steps before the flooz starts.
function M.countdown(level) return max(COUNTDOWN_MIN, COUNTDOWN_START - (level - 1) * COUNTDOWN_STEP) end

--- Steps the flooz takes over one tile.
function M.flowSteps(level) return max(FLOW_MIN, FLOW_START - (level - 1) * FLOW_STEP) end

--- How many obstacles a level starts with.
function M.obstacles(level) return min(OBSTACLE_CAP, (level - 1) * OBSTACLE_STEP) end

--- The side flooz leaves by, having come in by this one. Crosses go straight over.
function M.exit(piece, side)
  if piece == "x" then return OPPOSITE[side] end
  for dir in pairs(M.OPEN[piece]) do
    if dir ~= side then return dir end
  end
  return nil
end

--- The square at x, y: false if empty, nil if off the board.
local function at(s, x, y)
  local row = s.grid[y]
  return row and row[x]
end

local function isWet(cell) return next(cell.wet) ~= nil end

--- Can flooz come into this square by this side?
local function accepts(cell, side)
  return cell and cell.piece and M.OPEN[cell.piece][side] and not cell.wet[side] or false
end

local function emptyGrid(s)
  s.grid = {}
  for y = 1, s.rows do
    s.grid[y] = {}
    for x = 1, s.cols do s.grid[y][x] = false end
  end
end

--- A clean board with the start piece here, facing dir, and obstacles on the listed { x, y } squares.
function M.setBoard(s, x, y, dir, blocks)
  emptyGrid(s)
  s.start = { x = x, y = y, dir = dir }
  s.grid[y][x] = { start = true, dir = dir, wet = {} }
  for _, spot in ipairs(blocks or {}) do s.grid[spot[2]][spot[1]] = { block = true } end
end

--- How many empty squares can be reached from this one.
local function roomFrom(s, x, y)
  local seen, stack, count = { [y * 100 + x] = true }, { { x, y } }, 0
  while #stack > 0 do
    local spot = table.remove(stack)
    count = count + 1
    for dir = 1, 4 do
      local nx, ny = spot[1] + DX[dir], spot[2] + DY[dir]
      local key = ny * 100 + nx
      if at(s, nx, ny) == false and not seen[key] then
        seen[key] = true
        stack[#stack + 1] = { nx, ny }
      end
    end
  end
  return count
end

--- Scatter obstacles, keeping the start's way out clear and never walling off part of the board.
local function layObstacles(s, rng)
  local first = { x = s.start.x + DX[s.start.dir], y = s.start.y + DY[s.start.dir] }
  local spots = {}
  for y = 1, s.rows do
    for x = 1, s.cols do
      local nearStart = abs(x - s.start.x) + abs(y - s.start.y) <= 1
      local nearWay = abs(x - first.x) + abs(y - first.y) <= 1
      if not nearStart and not nearWay then spots[#spots + 1] = { x, y } end
    end
  end
  local free = s.cols * s.rows - 1
  local laid = 0
  for i = 1, #spots do
    if laid >= M.obstacles(s.level) then break end
    local j = i + rng(#spots - i + 1) - 1
    spots[i], spots[j] = spots[j], spots[i]
    local x, y = spots[i][1], spots[i][2]
    s.grid[y][x] = { block = true }
    if roomFrom(s, first.x, first.y) == free - laid - 1 then
      laid = laid + 1
    else
      s.grid[y][x] = false
    end
  end
end

local function nextPiece(s, rng)
  local piece = table.remove(s.queue, 1)
  s.queue[#s.queue + 1] = M.PIECES[rng(#M.PIECES)]
  return piece
end

local function startLevel(s, rng)
  s.queue = {}
  for i = 1, M.QUEUE do s.queue[i] = M.PIECES[rng(#M.PIECES)] end
  M.setBoard(s, rng(s.cols - 2) + 1, rng(s.rows - 2) + 1, rng(4))
  layObstacles(s, rng)
  s.need, s.pipes, s.replaced = M.need(s.level), 0, 0
  s.clock, s.clockFull = M.countdown(s.level), M.countdown(s.level)
  s.taps, s.flow, s.rushing, s.askRush = {}, nil, false, false
  s.blast, s.banner, s.leak = nil, nil, nil
end

--- A fresh game.
function M.new(opts)
  local s = { score = 0, level = 1, over = false, steps = 0, pause = 0, ending = 0, cols = M.COLS, rows = M.ROWS }
  startLevel(s, opts.rng)
  return s
end

--- The board has stopped taking taps, for LEVEL CLEAR or the end of the run.
local function waiting(s)
  return s.over or s.pause > 0 or s.ending > 0
end

--- Pipes on the board that never saw flooz.
function M.unused(s)
  local count = 0
  for y = 1, s.rows do
    for x = 1, s.cols do
      local cell = s.grid[y][x]
      if cell and cell.piece and not isWet(cell) then count = count + 1 end
    end
  end
  return count
end

--- The flooz has nowhere to go: pay for the level, or end the run.
local function endLevel(s, events)
  local head = s.flow
  s.leak = { x = head.x, y = head.y, dir = head.to }
  if s.pipes < s.need then
    s.ending = ENDING_STEPS
    events[#events + 1] = { type = "leak" }
    return
  end
  local length, unused = s.pipes * LENGTH_POINTS, M.unused(s)
  local bonus = max(0, length - unused * UNUSED_COST - s.replaced * REPLACE_COST)
  s.score = s.score + bonus
  s.banner = { length = length, unused = unused, replaced = s.replaced, bonus = bonus }
  s.pause = PAUSE_STEPS
  events[#events + 1] = { type = "clear" }
end

--- The flooz leaves its tile for the next, if the next will have it.
local function advance(s, events)
  local head = s.flow
  local x, y = head.x + DX[head.to], head.y + DY[head.to]
  local cell, side = at(s, x, y), OPPOSITE[head.to]
  if not accepts(cell, side) then
    endLevel(s, events)
    return
  end
  local to = M.exit(cell.piece, side)
  cell.wet[side], cell.wet[to] = true, true
  s.flow = { x = x, y = y, from = side, to = to, t = 0 }
  s.pipes = s.pipes + 1
  s.score = s.score + PIPE_POINTS + (s.rushing and RUSH_POINTS or 0)
  events[#events + 1] = { type = "flow", pipes = s.pipes, rush = s.rushing }
  if s.pipes == s.need then events[#events + 1] = { type = "enough" } end
end

--- Run the countdown, or move the flooz.
local function runWater(s, events)
  if not s.flow then
    s.clock = s.clock - 1
    if s.clock > 0 then return end
    local start = s.start
    s.grid[start.y][start.x].wet[start.dir] = true
    s.flow = { x = start.x, y = start.y, to = start.dir, t = 0 }
    events[#events + 1] = { type = "go" }
    return
  end
  local steps = M.flowSteps(s.level)
  s.flow.t = s.flow.t + (s.rushing and math.ceil(steps / RUSH_STEPS) or 1)
  if s.flow.t >= steps then advance(s, events) end
end

--- A tap on a square. An empty one takes the next piece; a dry pipe blows up, and the next piece lands when the smoke clears.
local function tap(s, x, y, rng, events)
  local cell = s.grid[y][x]
  if not cell then
    s.grid[y][x] = { piece = nextPiece(s, rng), wet = {} }
    events[#events + 1] = { type = "place" }
  elseif cell.piece and not isWet(cell) then
    s.grid[y][x] = false
    s.blast = { x = x, y = y, left = REPLACE_STEPS }
    s.replaced = s.replaced + 1
    events[#events + 1] = { type = "replace" }
  else
    events[#events + 1] = { type = "refused" }
  end
end

local function runBlast(s, rng, events)
  local blast = s.blast
  blast.left = blast.left - 1
  if blast.left > 0 then return end
  s.grid[blast.y][blast.x] = { piece = nextPiece(s, rng), wet = {} }
  s.blast = nil
  events[#events + 1] = { type = "place" }
end

--- A player's input: { kind = "tap", x, y }. The start piece rushes the flooz once it's flowing, and any other tap waits its turn.
function M.input(s, action)
  if waiting(s) or action.kind ~= "tap" or at(s, action.x, action.y) == nil then return end
  local blast = s.blast
  if action.x == s.start.x and action.y == s.start.y then
    s.askRush = s.flow ~= nil
  elseif not (blast and blast.x == action.x and blast.y == action.y) then
    s.taps[#s.taps + 1] = action
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  s.steps = s.steps + 1
  if s.ending > 0 then
    s.ending = s.ending - 1
    s.over = s.ending == 0
    return {}
  end
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause > 0 then return {} end
    s.level = s.level + 1
    startLevel(s, rng)
    return { { type = "level" } }
  end
  local events = {}
  if s.askRush and not s.rushing then
    s.rushing = true
    events[#events + 1] = { type = "rush" }
  end
  if s.blast then runBlast(s, rng, events) end
  while #s.taps > 0 and not s.blast do
    local action = table.remove(s.taps, 1)
    tap(s, action.x, action.y, rng, events)
  end
  runWater(s, events)
  return events
end

--- Pipes still wanted to reach this level's minimum.
function M.left(s)
  return max(0, s.need - s.pipes)
end

-- ---------------------------------------------------------------- the bot: it sees only what a player sees

--- Follow the pipes from the flooz to where they stop. Returns how many tiles are laid ahead of it, and that stopping place:
--- x, y and side are the square it wants to go into next, and last and lastSide the dry pipe before it, if there is one.
local function route(s)
  local head = s.flow
  local x, y, dir = s.start.x, s.start.y, s.start.dir
  if head then x, y, dir = head.x, head.y, head.to end
  local ahead, seen, used, last, lastSide = 0, {}, {}, nil, nil
  while true do
    local nx, ny, side = x + DX[dir], y + DY[dir], OPPOSITE[dir]
    local cell, key = at(s, nx, ny), ny * 1000 + nx * 10 + side
    if not accepts(cell, side) or seen[key] then
      return { ahead = ahead, x = nx, y = ny, side = side, last = last, lastSide = lastSide, used = used }
    end
    dir = M.exit(cell.piece, side)
    seen[key], seen[ny * 1000 + nx * 10 + dir] = true, true
    used[ny * 100 + nx] = true
    x, y = nx, ny
    ahead = ahead + 1
    last, lastSide = not isWet(cell) and { x, y } or nil, side
  end
end

--- Could a pipe go here? Empty squares can, and so can a parked pipe, by blowing it up. The route's own pipes are spoken for.
local function buildable(s, r, x, y)
  local cell = at(s, x, y)
  if r.used[y * 100 + x] then return false end
  return cell == false or (cell and cell.piece and not isWet(cell))
end

--- Squares that could still be built on, reached from this one without crossing x, y.
local function reach(s, r, fromX, fromY, x, y)
  local seen, stack, count = { [y * 100 + x] = true, [fromY * 100 + fromX] = true }, { { fromX, fromY } }, 0
  while #stack > 0 do
    local spot = table.remove(stack)
    count = count + 1
    for dir = 1, 4 do
      local nx, ny = spot[1] + DX[dir], spot[2] + DY[dir]
      local key = ny * 100 + nx
      if not seen[key] and buildable(s, r, nx, ny) then
        seen[key] = true
        stack[#stack + 1] = { nx, ny }
      end
    end
  end
  return count
end

--- Does this piece carry on the route at x, y, coming in by side, without leading it into a wall or a pocket?
local function fits(s, r, piece, x, y, side, wanted)
  if not M.OPEN[piece][side] then return false end
  local dir = M.exit(piece, side)
  local nx, ny = x + DX[dir], y + DY[dir]
  if wanted <= 1 then return true end
  return buildable(s, r, nx, ny) and reach(s, r, nx, ny, x, y) >= min(wanted - 1, 5)
end

--- A piece that doesn't fit the end of the pipe may fit further on, where the pieces after it will take the route.
local function further(s, r, piece, wanted)
  local x, y, side = r.x, r.y, r.side
  for i = 2, 3 do
    local following = s.queue[i]
    if at(s, x, y) ~= false or not M.OPEN[following][side] then return nil end
    local dir = M.exit(following, side)
    x, y, side = x + DX[dir], y + DY[dir], OPPOSITE[dir]
    if at(s, x, y) == false and fits(s, r, piece, x, y, side, wanted - i + 1) then return { kind = "tap", x = x, y = y } end
  end
  return nil
end

--- Somewhere out of the way for a piece that doesn't fit: an empty square as far as can be from where the route is going.
local function park(s, r, rng)
  local best, farthest = {}, 2
  for y = 1, s.rows do
    for x = 1, s.cols do
      if s.grid[y][x] == false then
        local far = abs(x - r.x) + abs(y - r.y)
        if far > farthest then best, farthest = {}, far end
        if far == farthest then best[#best + 1] = { x, y } end
      end
    end
  end
  if #best == 0 then return nil end
  local spot = best[rng(#best)]
  return { kind = "tap", x = spot[1], y = spot[2] }
end

--- A real player for the idle screen and tests, at a quick human pace: run the pipe on from its end with each piece that fits,
--- blow up whatever is in the way, park what doesn't fit, and hit the start piece once the pipe is long enough.
function M.bot(s, rng)
  if waiting(s) or s.blast or s.steps % BOT_EVERY ~= 0 then return nil end
  local r = route(s)
  local wanted = s.need + BOT_SPARE - s.pipes - r.ahead
  if wanted <= 0 then
    if s.flow and not s.rushing then return { kind = "tap", x = s.start.x, y = s.start.y } end
    return nil
  end
  local piece = s.queue[1]
  if buildable(s, r, r.x, r.y) then
    if fits(s, r, piece, r.x, r.y, r.side, wanted) then return { kind = "tap", x = r.x, y = r.y } end
    local spot = further(s, r, piece, wanted)
    if spot then return spot end
  elseif not r.last then
    return nil -- the flooz is in the last pipe and it leads nowhere: nothing left to save
  elseif fits(s, r, piece, r.last[1], r.last[2], r.lastSide, wanted + 1) then
    return { kind = "tap", x = r.last[1], y = r.last[2] }
  end
  return park(s, r, rng)
end

return M
