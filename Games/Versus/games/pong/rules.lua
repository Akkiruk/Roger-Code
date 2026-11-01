-- games/pong/rules.lua
-- Pong, two players head to head. Pure: no screen, sound or files. See "Versus" in games/README.md.
-- The court is COLS x ROWS square units, with y growing down. Player 1's paddle is at the low x end, player 2's at the high
-- end, and each wall draws its own player on the left. The ball is a box of BALL_R either side of its centre, and it moves
-- in short hops, so it can't pass through a paddle at any speed.
-- As in the original, the ball's speed is measured across the court, so a steep ball covers more ground in the same time.

local M = { COLS = 40, ROWS = 33, TOP = 1, BOTTOM = 32 }

local COLS, ROWS, TOP, BOTTOM = M.COLS, M.ROWS, M.TOP, M.BOTTOM

local BALL_R = 0.5
local PADDLE_H = 6
local PADDLE_W = 1
local PADDLE_X = 2         -- from the end of the court to the back of a paddle
local PADDLE_SPEED = 3     -- units a step: top to bottom in under a second
local HALF = PADDLE_H / 2

local START_SPEED = 1.6    -- units across the court a step: end to end in about two seconds
local SPEED_PER_HIT = 0.2
local MAX_SPEED = 5        -- end to end in about two thirds of a second, which a paddle at the far wall can't catch
local MOVE_STEP = 0.25     -- the longest single move: less than a paddle is thick

-- The paddle is cut into eight, as in the original. Each zone sends the ball off at its own slope, in units down for each
-- unit across. Even the middle two are not flat, so no ball can go back and forth for ever on one line.
local SLOPES = { -1.3, -0.85, -0.45, -0.15, 0.15, 0.45, 0.85, 1.3 }
local STEEPEST = 1.3

local WIN_SCORE = 11
local SERVE_WAIT = 16      -- steps from a point to the next serve
local SERVE_SPREAD = 8     -- how far from the middle of the court a serve can start
local SERVE_SLOPES = { 0.2, 0.6 }

local BOT_SPEED = 1.5      -- how fast the bot will move its paddle: a steep ball outruns it
local BOT_ERROR = 1        -- units of aim error on a slow ball
local BOT_ERROR_PER_HIT = 0.25 -- more for each hit of the rally, so it gets sloppier as the ball gets faster

M.BALL_R, M.PADDLE_H, M.PADDLE_W, M.PADDLE_X = BALL_R, PADDLE_H, PADDLE_W, PADDLE_X
M.PADDLE_SPEED, M.START_SPEED, M.SPEED_PER_HIT, M.MAX_SPEED = PADDLE_SPEED, START_SPEED, SPEED_PER_HIT, MAX_SPEED
M.SLOPES, M.WIN_SCORE, M.SERVE_WAIT, M.BOT_SPEED = SLOPES, WIN_SCORE, SERVE_WAIT, BOT_SPEED

local function clamp(v, low, high)
  return math.max(low, math.min(high, v))
end

--- Halfway down the court.
local function midY() return ROWS / 2 end

--- Put the ball on the centre line, ready to go to this player, at the starting speed.
local function setServe(s, receiver, rng)
  local slope = SERVE_SLOPES[1] + rng() * (SERVE_SLOPES[2] - SERVE_SLOPES[1])
  if rng() < 0.5 then slope = -slope end
  s.wait, s.hits, s.speed, s.receiver = SERVE_WAIT, 0, START_SPEED, receiver
  s.ball = {
    x = COLS / 2, y = midY() + (rng() * 2 - 1) * SERVE_SPREAD,
    dir = receiver == 1 and -1 or 1, slope = slope,
  }
end

--- A fresh match. Who gets the first serve is left to chance.
function M.new(opts)
  local s = {
    score = { 0, 0 }, over = false,
    paddles = { { y = midY(), target = midY() }, { y = midY(), target = midY() } },
  }
  setServe(s, opts.rng(2), opts.rng)
  return s
end

--- A player's input: the height their paddle should slide to. It stays set until their next tap.
function M.input(s, player, action)
  local paddle = s.paddles[player]
  if paddle and action.kind == "aim" and type(action.y) == "number" then
    paddle.target = clamp(action.y, TOP + HALF, BOTTOM - HALF)
  end
end

local function glide(paddle)
  paddle.y = paddle.y + clamp(paddle.target - paddle.y, -PADDLE_SPEED, PADDLE_SPEED)
end

--- Which of the eight zones a ball at this height hits, 1 at the top of the paddle. The ball's own width counts.
function M.zoneAt(paddleY, y)
  local place = (y - paddleY + HALF + BALL_R) / (PADDLE_H + 2 * BALL_R)
  return clamp(math.floor(place * #SLOPES) + 1, 1, #SLOPES)
end

local function bounce(s, b, player, events)
  local zone = M.zoneAt(s.paddles[player].y, b.y)
  b.dir, b.slope = -b.dir, SLOPES[zone]
  b.x = player == 1 and PADDLE_X + PADDLE_W + BALL_R or COLS - PADDLE_X - PADDLE_W - BALL_R
  s.hits = s.hits + 1
  s.speed = math.min(MAX_SPEED, START_SPEED + s.hits * SPEED_PER_HIT)
  events[#events + 1] = { type = "paddle", player = player, zone = zone }
end

--- Is the ball's leading edge inside the thickness of the paddle it's heading for, level with it?
local function meetsPaddle(s, b)
  local player = b.dir < 0 and 1 or 2
  local depth = player == 1 and PADDLE_X + PADDLE_W - (b.x - BALL_R) or (b.x + BALL_R) - (COLS - PADDLE_X - PADDLE_W)
  if depth >= 0 and depth <= PADDLE_W and math.abs(b.y - s.paddles[player].y) <= HALF + BALL_R then return player end
  return nil
end

local function scorePoint(s, scorer, rng, events)
  s.score[scorer] = s.score[scorer] + 1
  events[#events + 1] = { type = "point", player = scorer }
  if s.score[scorer] >= WIN_SCORE then
    s.over, s.winner = true, scorer
    events[#events + 1] = { type = "over", winner = scorer }
  else
    setServe(s, 3 - scorer, rng)
  end
end

--- One hop of the ball. Off the top or bottom wall it folds back, so the distance is kept and a landing can be worked out.
local function hop(s, distance, rng, events)
  local b = s.ball
  b.x = b.x + b.dir * distance
  b.y = b.y + b.slope * distance
  local high, low = TOP + BALL_R, BOTTOM - BALL_R
  if b.y < high or b.y > low then
    b.y = b.y < high and 2 * high - b.y or 2 * low - b.y
    b.slope = -b.slope
    events[#events + 1] = { type = "wall" }
  end
  local player = meetsPaddle(s, b)
  if player then
    bounce(s, b, player, events)
  elseif b.x + BALL_R < 0 then
    scorePoint(s, 2, rng, events)
  elseif b.x - BALL_R > COLS then
    scorePoint(s, 1, rng, events)
  end
end

--- Move the ball one step's worth, a short hop at a time. Stops if a point is scored.
local function fly(s, rng, events)
  local hops = math.ceil(s.speed * STEEPEST / MOVE_STEP)
  local distance = s.speed / hops
  for _ = 1, hops do
    hop(s, distance, rng, events)
    if s.wait > 0 or s.over then return end
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  glide(s.paddles[1])
  glide(s.paddles[2])
  local events = {}
  if s.wait > 0 then
    s.wait = s.wait - 1
    if s.wait == 0 then events[#events + 1] = { type = "serve", to = s.receiver } end
    return events
  end
  fly(s, rng, events)
  return events
end

--- A plain player for the idle screen and one-player games. It follows the ball's height rather than working out where the
-- ball will land, at no more than BOT_SPEED, and sets its aim off by a little each time the ball comes its way. A steep
-- ball outruns it, and the longer the rally the worse its aim. With the ball going away it drifts back to the middle.
function M.bot(s, rng, player)
  if s.over then return nil end
  local b, paddle = s.ball, s.paddles[player]
  local goal = midY()
  if s.wait == 0 and (b.dir < 0) == (player == 1) then
    if not paddle.miss then
      paddle.miss = (rng() * 2 - 1) * (BOT_ERROR + s.hits * BOT_ERROR_PER_HIT)
    end
    goal = b.y + paddle.miss
  else
    paddle.miss = nil
  end
  return { kind = "aim", y = paddle.y + clamp(goal - paddle.y, -BOT_SPEED, BOT_SPEED) }
end

--- What the tests read through the shell's debug dump.
function M.snapshot(s)
  return { paddle1 = s.paddles[1].y, paddle2 = s.paddles[2].y, hits = s.hits, speed = s.speed, wait = s.wait, ball = s.ball }
end

return M
