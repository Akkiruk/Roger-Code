-- games/flappy/rules.lua
-- Flappy Bird. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The board is WIDTH x HEIGHT monitor cells, with y growing down, so a square on the wall is 3 wide by 2 tall.
-- The bird keeps its x and the pipes come to it. A tap has a real delay behind it, so the bird is slow and floaty:
-- see "Prove fairness" in tools/arcadetest/tests/flappy.test.lua before changing a number here.

local M = { WIDTH = 116, HEIGHT = 66, GROUND = 61, BIRD_X = 26, BIRD_W = 6, BIRD_H = 4, PIPE_W = 10, PER_LEVEL = 10 }

local WIDTH, GROUND = M.WIDTH, M.GROUND
local BIRD_X, BIRD_W, BIRD_H, PIPE_W, PER_LEVEL = M.BIRD_X, M.BIRD_W, M.BIRD_H, M.PIPE_W, M.PER_LEVEL

local GRAVITY = 0.5         -- cells a step, each step
local FLAP = 2              -- the upward speed a flap sets, whatever the bird was doing
local MAX_FALL = 2          -- so a long fall can still be caught
local SPEED = 1.25          -- cells a step the pipes move

local START_GAP = 28        -- the opening in the first pipes
local MIN_GAP = 22          -- the fair limit: see the fairness test
local GAP_STEP = 1          -- taken off the opening each level
local START_SPACING = 46    -- from one pipe to the next
local MIN_SPACING = 38
local SPACING_STEP = 2

local MARGIN = 6            -- an opening stays this far from the ceiling and the ground
local MAX_SWING = 16        -- the most one opening's middle sits from the last, so the climb can always be made
local FIRST_PIPE = 96       -- where the first pipe waits for the first tap
local START_Y = 26
local BOB_HEIGHT = 1        -- how far the waiting bird drifts
local BOB_BEAT = 4          -- steps between its moves: the wall rests in between, as it should with nobody playing
local WING_STEPS = 3        -- steps the wing stays up after a flap

local BOT_WAIT = 15         -- steps of bobbing the idle screen shows
local BOT_MARGIN = 9        -- how high over the opening's lower lip the bot flaps
local BOT_SLOP = 0.7        -- cells of error per pipe passed: its luck runs out, so the idle screen moves on

M.GRAVITY, M.FLAP, M.MAX_FALL, M.SPEED, M.WING_STEPS = GRAVITY, FLAP, MAX_FALL, SPEED, WING_STEPS
M.START_GAP, M.MIN_GAP, M.START_SPACING, M.MIN_SPACING = START_GAP, MIN_GAP, START_SPACING, MIN_SPACING
M.MARGIN, M.MAX_SWING, M.START_Y, M.BOB_BEAT = MARGIN, MAX_SWING, START_Y, BOB_BEAT

--- The opening for a pipe placed at this level.
local function gapFor(level)
  return math.max(MIN_GAP, START_GAP - GAP_STEP * (level - 1))
end

--- The distance from one pipe to the next, at this level.
local function spacingFor(level)
  return math.max(MIN_SPACING, START_SPACING - SPACING_STEP * (level - 1))
end

M.gapFor, M.spacingFor = gapFor, spacingFor

--- A pipe at x, with its opening somewhere within reach of the middle of the last one.
local function newPipe(s, x, rng)
  local gap = gapFor(s.level)
  local low, high = MARGIN + gap / 2, GROUND - MARGIN - gap / 2
  local mid = s.lastMid + (rng() * 2 - 1) * MAX_SWING
  mid = math.max(low, math.min(high, mid))
  s.lastMid = mid
  s.pipes[#s.pipes + 1] = { x = x, top = mid - gap / 2, bottom = mid + gap / 2, passed = false }
end

--- A fresh game. The bird waits, and nothing falls or scrolls in until the first tap.
function M.new(opts)
  local s = {
    score = 0, level = 1, over = false, started = false, flap = false,
    y = START_Y, vy = 0, wing = 0, clock = 0, scroll = 0, pipes = {}, lastMid = GROUND / 2,
  }
  newPipe(s, FIRST_PIPE, opts.rng)
  return s
end

--- A player's input: one flap, on the next step. Two taps in one step are one flap.
function M.input(s, action)
  if action.kind == "flap" and not s.over then s.flap = true end
end

--- The first pipe the bird hasn't got past yet.
local function nextPipe(s)
  for _, p in ipairs(s.pipes) do
    if not p.passed then return p end
  end
  return nil
end

M.nextPipe = nextPipe

--- Keep the pipes coming: a new one out of sight once the last has room, and the old ones dropped.
local function movePipes(s, rng)
  for _, p in ipairs(s.pipes) do p.x = p.x - SPEED end
  if s.pipes[1].x + PIPE_W < 0 then table.remove(s.pipes, 1) end
  local last = s.pipes[#s.pipes]
  local spacing = spacingFor(s.level)
  if last.x + spacing <= WIDTH then newPipe(s, last.x + spacing, rng) end
end

local function score(s, events)
  for _, p in ipairs(s.pipes) do
    if not p.passed and p.x + PIPE_W <= BIRD_X then
      p.passed = true
      s.score = s.score + 1
      s.level = math.floor(s.score / PER_LEVEL) + 1
      events[#events + 1] = { type = "point" }
    end
  end
end

--- What the bird has run into, or nil.
local function touching(s)
  if s.y <= 0 then return "ceiling" end
  if s.y + BIRD_H >= GROUND then return "ground" end
  for _, p in ipairs(s.pipes) do
    if BIRD_X + BIRD_W > p.x and BIRD_X < p.x + PIPE_W and (s.y < p.top or s.y + BIRD_H > p.bottom) then return "pipe" end
  end
  return nil
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  s.clock = s.clock + 1
  local flapped = s.flap
  s.flap = false
  if not s.started and not flapped then
    s.y = START_Y + math.sin(math.floor(s.clock / BOB_BEAT) * math.pi / 2) * BOB_HEIGHT
    return {}
  end
  s.started = true
  s.scroll = s.scroll + SPEED
  local events = {}
  s.wing = math.max(0, s.wing - 1)
  if flapped then
    s.vy, s.wing = -FLAP, WING_STEPS
    events[1] = { type = "flap" }
  else
    s.vy = math.min(MAX_FALL, s.vy + GRAVITY)
  end
  s.y = s.y + s.vy
  movePipes(s, rng)
  score(s, events)
  local hit = touching(s)
  if hit then
    s.over = true
    s.y = math.max(0, math.min(GROUND - BIRD_H, s.y))
    events[#events + 1] = { type = "crash", on = hit }
  end
  return events
end

--- A plain player for the idle screen and tests. It flaps when it's sinking too near the lower lip, and a new error
-- for each pipe grows with the score, so sooner or later it misses and the idle screen moves on.
function M.bot(s, rng)
  if not s.started then
    if s.clock >= BOT_WAIT then return { kind = "flap" } end
    return nil
  end
  if s.slipFor ~= s.score then
    s.slipFor = s.score
    s.slip = (rng() * 2 - 1) * BOT_SLOP * s.score
  end
  local p = nextPipe(s)
  local floor = p.bottom - BOT_MARGIN + (s.slip or 0)
  if s.vy >= 0 and s.y + BIRD_H + s.vy * 2 > floor then return { kind = "flap" } end
  return nil
end

return M
