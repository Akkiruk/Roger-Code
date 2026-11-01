-- games/duckhunt/rules.lua
-- Duck Hunt. Pure: no screen, sound or files. See "Classics" in Games/Arcade/games/README.md.
-- The board is measured in monitor cells, x across and y down, with the sky above y = GRASS_Y. A cell is 2 wide by 3 tall
-- on screen, so a row counts ASPECT columns: that keeps diagonals looking diagonal. A duck's x, y is its middle.
-- A tap can't land where the player saw the duck: it arrives late. So a shot counts against the duck's last few places too.
-- A run goes round these phases: intro (the round's banner), fly (the only one that takes shots), settle (ducks fall or leave),
-- dog (he fetches or laughs), then fly again, or tally (the round's result) once all ten have flown.

local M = { WIDTH = 118, HEIGHT = 74, GRASS_Y = 50, ASPECT = 1.5, DUCKS = 10, SHOTS = 3 }

local WIDTH, GRASS_Y, ASPECT, DUCKS, SHOTS = M.WIDTH, M.GRASS_Y, M.ASPECT, M.DUCKS, M.SHOTS
local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

-- Three kinds by colour: the rarer the faster, and the faster the more it pays.
local KINDS = {
  { name = "black", points = 500, pace = 1 },
  { name = "blue", points = 1000, pace = 1.25 },
  { name = "red", points = 1500, pace = 1.5 },
}

local HIT_W, HIT_H = 9, 6     -- a shot hits this far from a duck's middle, across and down. The sprite is 6 and 4
local BASE_SPEED = 1.1        -- columns a step for a black duck on round 1, about ten seconds across the wall
local SPEED_STEP = 0.1        -- added each round
local MAX_SPEED = 3           -- no duck goes faster: a tap 4 steps late must still land, and it does up to here
local FLIGHT_STEPS = 80       -- steps before a release flies away, on round 1
local FLIGHT_STEP = 3         -- that many fewer each round
local MIN_FLIGHT = 50
local FIRST_QUOTA, MAX_QUOTA, QUOTA_EVERY = 6, 9, 3 -- hits needed: up by one every QUOTA_EVERY rounds
local PERFECT_BONUS = 10000
local START_Y = GRASS_Y + 6   -- ducks start here, hidden in the grass, and fall back to here
local FLOOR = GRASS_Y - 5     -- the lowest a duck flies once it's out
local CEILING = 5
local MARGIN = 7              -- how near a duck's middle gets to the sides
local STOP_STEPS = 5          -- a hit duck hangs in the air this long
local FALL_SPEED, FALL_GAIN = 1, 0.25 -- rows a step as it starts to fall, and the gain each step
local AWAY_SPEED = 2.5        -- rows a step for a duck leaving
local INTRO_STEPS = 20
local DOG_RISE = 5            -- steps for the dog to come up, and to go down again
local DOG_HOLD = 8            -- steps he holds the duck up
local DOG_LAUGH = 10          -- steps he laughs
local TALLY_STEPS = 22        -- the pause on a round's result
local DOG_EDGE = 16           -- how near the sides the dog comes up
local BOT_GAP = 13            -- steps between its shots
local BOT_LAG = 3             -- how many steps behind the duck it aims
local BOT_SPREAD_X, BOT_SPREAD_Y = 18, 11 -- how far off it can be, either way

M.KINDS, M.HIT_W, M.HIT_H, M.PERFECT_BONUS = KINDS, HIT_W, HIT_H, PERFECT_BONUS
M.DOG_RISE, M.INTRO_STEPS = DOG_RISE, INTRO_STEPS

--- Hits needed to pass a round.
local function quota(round)
  return min(MAX_QUOTA, FIRST_QUOTA + floor((round - 1) / QUOTA_EVERY))
end
M.quota = quota

--- How fast a kind flies on a round, in columns a step.
local function speedOf(kind, round)
  return min(MAX_SPEED, (BASE_SPEED + SPEED_STEP * (round - 1)) * KINDS[kind].pace)
end
M.speedOf = speedOf

--- Steps a release has before it flies away.
local function flightOf(round)
  return max(MIN_FLIGHT, FLIGHT_STEPS - FLIGHT_STEP * (round - 1))
end
M.flightOf = flightOf

--- The chance a release is two ducks.
local function doubleChance(round)
  return min(0.7, 0.2 * (round - 1))
end

--- The chance a flying duck changes its mind on any one step.
local function turnChance(round)
  return min(0.05, 0.008 * (round - 1))
end

local function pickKind(round, rng)
  local red = min(0.4, 0.1 + 0.03 * (round - 1))
  local roll = rng()
  if roll < red then return 3 end
  return roll < red + 0.3 and 2 or 1
end

--- Send a duck off at speed: up if it's rising, either way otherwise. Steep or shallow, it looks the same speed.
local function setCourse(d, rng, up)
  local across = up and 0.6 or (0.5 + 0.1 * rng(4))
  local down = sqrt(1 - across * across)
  d.vx = across * d.speed * (rng(2) == 1 and 1 or -1)
  d.vy = down * d.speed / ASPECT * ((up or rng(2) == 1) and -1 or 1)
end

local function newDuck(s, slot, rng)
  local kind = pickKind(s.level, rng)
  local x = MARGIN + 8 + rng(WIDTH - 2 * (MARGIN + 8))
  local d = {
    kind = kind, slot = slot, state = "fly", rising = true, speed = speedOf(kind, s.level), frame = rng(4),
    x = x, y = START_Y, x1 = x, y1 = START_Y, x2 = x, y2 = START_Y,
  }
  setCourse(d, rng, true)
  return d
end

local function startRound(s)
  s.tally, s.released, s.hits, s.result = {}, 0, 0, nil
  s.quota = quota(s.level)
  s.phase, s.wait = "intro", INTRO_STEPS
end

--- One or two ducks up, three shots, and the clock running.
local function release(s, rng, events)
  local left = DUCKS - s.released
  local count = (left >= 2 and rng() < doubleChance(s.level)) and 2 or 1
  s.ducks = {}
  for i = 1, count do
    local slot = s.released + i
    s.ducks[i] = newDuck(s, slot, rng)
    s.tally[slot] = "fly"
  end
  s.released = s.released + count
  s.shots, s.flight, s.aloft, s.fled = SHOTS, flightOf(s.level), 0, false
  s.phase = "fly"
  events[#events + 1] = { type = "release", count = count }
end

--- A fresh game. opts.rng is the only source of chance, and nothing here needs it yet.
function M.new()
  local s = {
    score = 0, level = 1, over = false, clock = 0, phase = "intro", wait = 0,
    ducks = {}, caught = {}, taps = {}, shots = 0, flight = 0, aloft = 0, fled = false,
  }
  startRound(s)
  return s
end

--- A player's input: the gun, at a spot on the board. The next step resolves it. A tap on the grass, or at any time
--- but when ducks are in the air, fires nothing and costs nothing.
function M.input(s, action)
  if action.kind ~= "shoot" or s.over or s.phase ~= "fly" then return end
  local x, y = tonumber(action.x), tonumber(action.y)
  if not x or not y or x < 0 or x >= WIDTH or y < 0 or y >= GRASS_Y then return end
  s.taps[#s.taps + 1] = { x = x, y = y }
end

local function within(x, y, tap)
  return math.abs(tap.x - x) <= HIT_W and math.abs(tap.y - y) <= HIT_H
end

--- Does a tap land on this duck, where it is or where it was one or two steps ago?
local function struck(d, tap)
  return within(d.x, d.y, tap) or within(d.x1, d.y1, tap) or within(d.x2, d.y2, tap)
end

--- The flying duck a tap landed on, the nearest if it could be either.
local function targetOf(s, tap)
  local best, bestDistance
  for _, d in ipairs(s.ducks) do
    if d.state == "fly" and struck(d, tap) then
      local distance = (d.x - tap.x) ^ 2 + (d.y - tap.y) ^ 2
      if not best or distance < bestDistance then best, bestDistance = d, distance end
    end
  end
  return best
end

local function flyingCount(s)
  local n = 0
  for _, d in ipairs(s.ducks) do
    if d.state == "fly" then n = n + 1 end
  end
  return n
end

--- Points go on as the duck is hit, so a shot pays at once.
local function knockDown(s, d, events)
  local points = KINDS[d.kind].points
  d.state, d.stop, d.points, d.fall = "hit", STOP_STEPS, points, FALL_SPEED
  s.tally[d.slot] = "hit"
  s.hits = s.hits + 1
  s.score = s.score + points
  events[#events + 1] = { type = "hit", kind = d.kind, points = points }
end

--- One tap goes off. Spends a shot either way.
local function fire(s, tap, events)
  s.shots = s.shots - 1
  local d = targetOf(s, tap)
  s.flash = { x = tap.x, y = tap.y, at = s.clock, hit = d ~= nil }
  events[#events + 1] = { type = "shot", hit = d ~= nil }
  if d then knockDown(s, d, events) end
end

local function resolveTaps(s, events)
  local taps = s.taps
  s.taps = {}
  for _, tap in ipairs(taps) do
    if s.shots > 0 and flyingCount(s) > 0 then fire(s, tap, events) end
  end
end

--- Everything still flying leaves, straight up and a little sideways.
local function escape(s, events)
  for _, d in ipairs(s.ducks) do
    if d.state == "fly" then
      d.state = "away"
      d.vx = d.vx > 0 and 0.8 or -0.8
      s.tally[d.slot] = "miss"
    end
  end
  s.fled = true
  events[#events + 1] = { type = "flyaway" }
end

local function moveFlying(s, d, rng)
  d.x2, d.y2, d.x1, d.y1 = d.x1, d.y1, d.x, d.y
  d.x, d.y = d.x + d.vx, d.y + d.vy
  if d.rising then
    if d.y <= FLOOR then
      d.rising = false
      setCourse(d, rng, true)
    end
  elseif rng() < turnChance(s.level) then
    setCourse(d, rng)
  end
  if d.x < MARGIN or d.x > WIDTH - 1 - MARGIN then
    d.x = max(MARGIN, min(WIDTH - 1 - MARGIN, d.x))
    d.vx = -d.vx
  end
  if d.y < CEILING then
    d.y, d.vy = CEILING, -d.vy
  elseif d.y > FLOOR and not d.rising then
    d.y, d.vy = FLOOR, -d.vy
  end
end

--- Move one duck. Returns true when it has gone: into the grass, or out of the top of the sky.
local function moveDuck(s, d, rng)
  d.frame = d.frame + 1
  if d.state == "fly" then
    moveFlying(s, d, rng)
  elseif d.state == "hit" then
    d.stop = d.stop - 1
    if d.stop <= 0 then d.state = "fall" end
  elseif d.state == "fall" then
    d.y = d.y + d.fall
    d.fall = d.fall + FALL_GAIN
    if d.y >= START_Y then
      s.caught[#s.caught + 1] = { x = d.x, kind = d.kind }
      return true
    end
  else
    d.x, d.y = d.x + d.vx, d.y - AWAY_SPEED
    return d.y < -8
  end
  return false
end

local function moveDucks(s, rng)
  for i = #s.ducks, 1, -1 do
    if moveDuck(s, s.ducks[i], rng) then table.remove(s.ducks, i) end
  end
end

--- The dog's turn: up with what fell, or up to laugh if nothing did. With two, he comes up between them.
local function startDog(s, events)
  local count = #s.caught
  local dog = { t = 0, x = floor(WIDTH / 2) }
  if count > 0 then
    local sum = 0
    for _, duck in ipairs(s.caught) do sum = sum + duck.x end
    dog.kind, dog.ducks, dog.steps = "hold", s.caught, 2 * DOG_RISE + DOG_HOLD
    dog.x = max(DOG_EDGE, min(WIDTH - 1 - DOG_EDGE, floor(sum / count)))
    events[#events + 1] = { type = "fetch", count = count }
  else
    dog.kind, dog.steps = "laugh", 2 * DOG_RISE + DOG_LAUGH
    events[#events + 1] = { type = "laugh" }
  end
  s.dog, s.caught, s.fled = dog, {}, false
  s.phase = "dog"
end

--- All ten have flown: pay a perfect round, and say whether the quota was met.
local function endRound(s, events)
  local passed = s.hits >= s.quota
  local perfect = s.hits == DUCKS
  if perfect then s.score = s.score + PERFECT_BONUS end
  s.result = { passed = passed, perfect = perfect, hits = s.hits, quota = s.quota }
  s.phase, s.wait = "tally", TALLY_STEPS
  if perfect then events[#events + 1] = { type = "perfect", bonus = PERFECT_BONUS } end
  events[#events + 1] = { type = passed and "clear" or "short" }
end

local function runIntro(s, rng, events)
  s.wait = s.wait - 1
  if s.wait <= 0 then release(s, rng, events) end
end

local function runFly(s, rng, events)
  resolveTaps(s, events)
  s.flight, s.aloft = s.flight - 1, s.aloft + 1
  local flying = flyingCount(s)
  if flying > 0 and (s.shots <= 0 or s.flight <= 0) then
    escape(s, events)
    flying = 0
  end
  moveDucks(s, rng)
  if flying == 0 then s.phase = "settle" end
end

local function runSettle(s, rng, events)
  moveDucks(s, rng)
  if #s.ducks == 0 then startDog(s, events) end
end

local function runDog(s, rng, events)
  s.dog.t = s.dog.t + 1
  if s.dog.t < s.dog.steps then return end
  s.dog = nil
  if s.released >= DUCKS then endRound(s, events) else release(s, rng, events) end
end

--- The pause on the result. It ends with the next round, or with the run: missing the quota is the only way it ends.
local function runTally(s, _, events)
  s.wait = s.wait - 1
  if s.wait > 0 then return end
  if s.result.passed then
    s.level = s.level + 1
    startRound(s)
  else
    s.over = true
    events[#events + 1] = { type = "over" }
  end
end

local PHASES = { intro = runIntro, fly = runFly, settle = runSettle, dog = runDog, tally = runTally }

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  PHASES[s.phase](s, rng, events)
  return events
end

--- A fair human-looking player for the idle screen and tests: it waits to see a duck, takes a shot every so often, aims
--- a moment behind it and a little off, so it gets both hits and laughs.
function M.bot(s, rng)
  if s.phase ~= "fly" then return nil end
  for _, d in ipairs(s.ducks) do
    if d.state == "fly" and not d.rising and s.aloft % BOT_GAP == 0 then
      local x = d.x - d.vx * BOT_LAG + (rng() * 2 - 1) * BOT_SPREAD_X
      local y = d.y - d.vy * BOT_LAG + (rng() * 2 - 1) * BOT_SPREAD_Y
      return { kind = "shoot", x = max(0, min(WIDTH - 1, floor(x))), y = max(0, min(GRASS_Y - 1, floor(y))) }
    end
  end
  return nil
end

return M
