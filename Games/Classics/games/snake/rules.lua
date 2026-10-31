-- games/snake/rules.lua
-- Snake. Pure: no screen, sound or files. This is the pattern for a classic: see "Classics" in games/README.md.
-- The snake is a list of cells, head first. A step moves it one cell the way it faces.

local M = { COLS = 36, ROWS = 24 }

local COLS, ROWS = M.COLS, M.ROWS
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local PER_LEVEL = 5   -- food eaten for each level
local FOOD_SCORE = 10

M.DIRECTIONS = DIRECTIONS

local function occupied(s, x, y)
  for _, cell in ipairs(s.snake) do
    if cell[1] == x and cell[2] == y then return true end
  end
  return false
end

local function placeFood(s, rng)
  repeat
    s.food = { rng(COLS), rng(ROWS) }
  until not occupied(s, s.food[1], s.food[2])
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local mid = { math.floor(COLS / 2), math.floor(ROWS / 2) }
  local s = {
    score = 0, level = 1, lives = 1, over = false, eaten = 0, grow = 2, wait = 0,
    dir = "right", want = "right",
    snake = { mid, { mid[1] - 1, mid[2] }, { mid[1] - 2, mid[2] } },
  }
  placeFood(s, opts.rng)
  return s
end

--- A player's input. The snake can't turn straight back on itself. Applied at the next step.
function M.input(s, action)
  if action.kind == "turn" and DIRECTIONS[action.dir] and action.dir ~= OPPOSITE[s.dir] then
    s.want = action.dir
  end
end

--- Steps between moves: one fewer every few levels, so the game speeds up.
local function delay(s)
  return math.max(0, 2 - math.floor((s.level - 1) / 2))
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  if s.wait > 0 then
    s.wait = s.wait - 1
    return {}
  end
  s.wait = delay(s)
  s.dir = s.want
  local d = DIRECTIONS[s.dir]
  local head = s.snake[1]
  local x, y = head[1] + d[1], head[2] + d[2]
  -- the tail moves off its cell this step unless the snake is growing
  local tail = s.snake[#s.snake]
  local hitsTail = s.grow == 0 and tail[1] == x and tail[2] == y
  if x < 1 or x > COLS or y < 1 or y > ROWS or (occupied(s, x, y) and not hitsTail) then
    s.over = true
    return { { type = "crash" } }
  end
  table.insert(s.snake, 1, { x, y })
  local events = {}
  if s.food[1] == x and s.food[2] == y then
    s.grow = s.grow + 2
    s.eaten = s.eaten + 1
    s.score = s.score + FOOD_SCORE * s.level
    if s.eaten % PER_LEVEL == 0 then
      s.level = s.level + 1
      events[#events + 1] = { type = "level" }
    end
    events[#events + 1] = { type = "eat" }
    placeFood(s, rng)
  end
  if s.grow > 0 then
    s.grow = s.grow - 1
  else
    table.remove(s.snake)
  end
  return events
end

--- A plain player for the idle screen and tests: head for the food, and don't run into anything.
function M.bot(s)
  local head = s.snake[1]
  local best, bestDistance
  for dir, d in pairs(DIRECTIONS) do
    local x, y = head[1] + d[1], head[2] + d[2]
    if dir ~= OPPOSITE[s.dir] and x >= 1 and x <= COLS and y >= 1 and y <= ROWS and not occupied(s, x, y) then
      local distance = math.abs(x - s.food[1]) + math.abs(y - s.food[2])
      if not best or distance < bestDistance then best, bestDistance = dir, distance end
    end
  end
  return best and { kind = "turn", dir = best } or nil
end

return M
