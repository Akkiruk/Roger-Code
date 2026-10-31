-- games/breakout/rules.lua
-- Breakout. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The board is COLS x ROWS square units, with y growing down. The ball is a box of BALL_R either side of its centre.
-- It moves in short steps, one axis at a time, so it can't pass through a brick or the paddle at any speed.

local M = { COLS = 30, ROWS = 32, BRICK_COLS = 10, BRICK_ROWS = 6, BRICK_W = 3, BRICK_H = 2, TOP = 4, CEILING = 1 }

local COLS, ROWS = M.COLS, M.ROWS
local BRICK_COLS, BRICK_ROWS, BRICK_W, BRICK_H, TOP = M.BRICK_COLS, M.BRICK_ROWS, M.BRICK_W, M.BRICK_H, M.TOP
local CEILING = M.CEILING  -- the underside of the top wall
local ROW_SCORE = { 60, 50, 40, 30, 20, 10 } -- top row first

local BALL_R = 0.5
local PADDLE_Y = 30        -- the top of the paddle
local PADDLE_H = 1
local PADDLE_LONG = 8
local PADDLE_SHORT = 5     -- after the ball has reached the top wall
local PADDLE_SPEED = 1.6   -- units a step: it beats the ball sideways at top speed

local START_SPEED = 0.6    -- units a step
local SPEED_PER_BRICK = 0.015
local SPEED_PER_LEVEL = 0.1
local LEVEL_SPEED_CAP = 1.1
local MAX_SPEED = 1.4
local MOVE_STEP = 0.25     -- the longest single move: less than the thinnest brick or paddle

local MAX_ANGLE = math.rad(60) -- from straight up, at the very end of the paddle
local MIN_ANGLE = math.rad(8)  -- so no ball bounces straight up and down for ever
local SERVE_ANGLES = { math.rad(15), math.rad(35) }
local SERVE_WAIT = 12      -- steps the ball sits on the paddle before it goes

M.BALL_R, M.PADDLE_Y, M.PADDLE_H, M.PADDLE_SPEED = BALL_R, PADDLE_Y, PADDLE_H, PADDLE_SPEED
M.PADDLE_LONG, M.PADDLE_SHORT, M.MAX_SPEED, M.ROW_SCORE = PADDLE_LONG, PADDLE_SHORT, MAX_SPEED, ROW_SCORE

local function clamp(v, low, high)
  return math.max(low, math.min(high, v))
end

--- Half the paddle's width.
local function reach(s)
  return (s.short and PADDLE_SHORT or PADDLE_LONG) / 2
end

M.reach = reach

local function buildWall(s)
  s.bricks = {}
  for r = 1, BRICK_ROWS do
    s.bricks[r] = {}
    for c = 1, BRICK_COLS do s.bricks[r][c] = true end
  end
  s.left = BRICK_ROWS * BRICK_COLS
end

local function levelSpeed(s)
  return math.min(LEVEL_SPEED_CAP, START_SPEED + SPEED_PER_LEVEL * (s.level - 1))
end

--- Put the ball back on the paddle, ready to go.
local function nextServe(s)
  s.wait = SERVE_WAIT
  s.speed = levelSpeed(s)
  s.miss = nil
  s.ball = { x = s.paddle, y = PADDLE_Y - BALL_R, dx = 0, dy = -1 }
end

--- A fresh game. Nothing here is left to chance: the first serve happens on the clock.
function M.new()
  local s = {
    score = 0, level = 1, lives = 3, over = false, short = false,
    paddle = COLS / 2, target = COLS / 2, goal = COLS / 2,
  }
  buildWall(s)
  nextServe(s)
  return s
end

--- A player's input: the spot the paddle should slide to. It stays set until the next tap.
function M.input(s, action)
  if action.kind == "aim" and type(action.x) == "number" then s.target = action.x end
end

--- Slide the paddle toward its target, as far as one step allows. The target keeps the tap as it was, so a paddle
-- that shrinks against a side wall still goes right up to it.
local function glide(s)
  local half = reach(s)
  s.goal = clamp(s.target, half, COLS - half)
  s.paddle = clamp(s.paddle, half, COLS - half)
  s.paddle = s.paddle + clamp(s.goal - s.paddle, -PADDLE_SPEED, PADDLE_SPEED)
end

--- Send the ball off the paddle, a little to one side.
local function serve(s, rng)
  local angle = SERVE_ANGLES[1] + rng() * (SERVE_ANGLES[2] - SERVE_ANGLES[1])
  if rng() < 0.5 then angle = -angle end
  s.ball.dx, s.ball.dy = math.sin(angle), -math.cos(angle)
end

--- The row and column of a live brick at this point, or nil.
local function brickAt(s, x, y)
  local r, c = math.floor((y - TOP) / BRICK_H) + 1, math.floor(x / BRICK_W) + 1
  if s.bricks[r] and s.bricks[r][c] then return r, c end
  return nil
end

--- A brick the ball's leading edge has run into. The middle of the edge wins when it could be either of two.
local function brickAhead(s, x, y, alongX)
  for _, offset in ipairs({ 0, -BALL_R, BALL_R }) do
    local r, c
    if alongX then r, c = brickAt(s, x, y + offset) else r, c = brickAt(s, x + offset, y) end
    if r then return r, c end
  end
  return nil
end

local function nextWall(s, events)
  s.level = s.level + 1
  s.short = false
  buildWall(s)
  nextServe(s)
  events[#events + 1] = { type = "level" }
end

local function breakBrick(s, r, c, events)
  s.bricks[r][c] = false
  s.left = s.left - 1
  s.score = s.score + ROW_SCORE[r]
  s.speed = math.min(MAX_SPEED, s.speed + SPEED_PER_BRICK)
  events[#events + 1] = { type = "brick", row = r }
  if s.left == 0 then nextWall(s, events) end
end

local function loseBall(s, events)
  s.lives = s.lives - 1
  if s.lives <= 0 then
    s.over = true
    events[#events + 1] = { type = "over" }
  else
    nextServe(s)
    events[#events + 1] = { type = "lost" }
  end
end

--- Bounce off the paddle: the farther from its middle, the wider the angle.
local function bounce(s, b)
  local place = clamp((b.x - s.paddle) / (reach(s) + BALL_R), -1, 1)
  local angle = place * MAX_ANGLE
  if math.abs(angle) < MIN_ANGLE then
    local side = place ~= 0 and place or b.dx
    angle = side < 0 and -MIN_ANGLE or MIN_ANGLE
  end
  b.dx, b.dy = math.sin(angle), -math.cos(angle)
  b.y = PADDLE_Y - BALL_R
end

local function moveAcross(s, b, distance, events)
  local x = b.x + b.dx * distance
  if x < BALL_R or x > COLS - BALL_R then
    b.dx = -b.dx
    events[#events + 1] = { type = "wall" }
    return
  end
  local r, c = brickAhead(s, x + (b.dx > 0 and BALL_R or -BALL_R), b.y, true)
  if r then
    b.dx = -b.dx
    breakBrick(s, r, c, events)
  else
    b.x = x
  end
end

local function moveDown(s, b, distance, events)
  local y = b.y + b.dy * distance
  if y < CEILING + BALL_R then
    b.dy = -b.dy
    events[#events + 1] = { type = "wall" }
    if not s.short then
      s.short = true
      events[#events + 1] = { type = "shrink" }
    end
    return
  end
  local r, c = brickAhead(s, b.x, y + (b.dy > 0 and BALL_R or -BALL_R), false)
  if r then
    b.dy = -b.dy
    breakBrick(s, r, c, events)
    return
  end
  local bottom = y + BALL_R
  if b.dy > 0 and bottom >= PADDLE_Y and bottom <= PADDLE_Y + PADDLE_H
    and math.abs(b.x - s.paddle) <= reach(s) + BALL_R then
    bounce(s, b)
    events[#events + 1] = { type = "paddle" }
    return
  end
  b.y = y
  if y - BALL_R > ROWS then loseBall(s, events) end
end

--- Move the ball one step's worth, a short hop at a time. Stops if the ball is lost or a new wall goes up.
local function fly(s, events)
  local hops = math.ceil(s.speed / MOVE_STEP)
  local distance = s.speed / hops
  for _ = 1, hops do
    moveAcross(s, s.ball, distance, events)
    if s.wait > 0 then return end
    moveDown(s, s.ball, distance, events)
    if s.wait > 0 or s.over then return end
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  glide(s)
  local events = {}
  if s.wait > 0 then
    s.wait = s.wait - 1
    s.ball.x = s.paddle
    if s.wait == 0 then serve(s, rng) end
    return events
  end
  fly(s, events)
  return events
end

--- Where a falling ball meets the paddle's height, off the side walls. Bricks don't count.
local function landing(b)
  local span = COLS - 2 * BALL_R
  local x = b.x + b.dx * (PADDLE_Y - BALL_R - b.y) / b.dy - BALL_R
  local folded = x % (2 * span)
  if folded > span then folded = 2 * span - folded end
  return folded + BALL_R
end

--- A plain player for the idle screen and tests. Each fall it picks a spot on the paddle, and it gets sloppier as
-- the ball gets faster, so it hits at different angles for a while and then misses.
function M.bot(s, rng)
  local b = s.ball
  if s.wait > 0 or b.dy < 0 then
    s.miss = nil
    return nil
  end
  if not s.miss then
    local spread = reach(s) * (0.5 + s.speed)
    s.miss = (rng() * 2 - 1) * spread
  end
  return { kind = "aim", x = landing(b) + s.miss }
end

return M
