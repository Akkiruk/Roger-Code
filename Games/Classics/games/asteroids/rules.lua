-- games/asteroids/rules.lua
-- Asteroids. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Everything lives in world units, which are the same size across and down. A monitor cell is 2 units wide and 3 tall,
-- so the board of 117 x 60 cells is a 234 x 180 world. Only the plugin knows about cells.

local M = { WIDTH = 234, HEIGHT = 180, CELL_W = 2, CELL_H = 3 }

local WIDTH, HEIGHT = M.WIDTH, M.HEIGHT
local TAU = math.pi * 2
local atan2, cos, floor, min, sin, sqrt = math.atan2, math.cos, math.floor, math.min, math.sin, math.sqrt

M.SIZES = {
  { radius = 6, score = 100, speed = 3.6 },  -- small
  { radius = 10, score = 50, speed = 2.6 },  -- medium
  { radius = 16, score = 20, speed = 1.8 },  -- large
}
M.LOOKS = 4              -- rock outlines, for the plugin to pick from
local LARGE = #M.SIZES
local SIZES = M.SIZES

local START_LIVES = 3
local EXTRA_LIFE = 10000
local SHIP_RADIUS = 6
local HOLD_TICKS = 50     -- the board waits this long at the start for a first tap, after the walk from START
local SAFE_TICKS = 25     -- the safe moment after a respawn
local DEAD_TICKS = 15     -- the wreck stays on the board this long, so a player sees what hit them
local BURN_PER_TAP = 5    -- one THRUST tap burns for this many steps, since nothing can be held
local BURN_MOST = 10
local THRUST = 0.7
local DRAG = 0.975        -- the ship coasts, then settles, so a player isn't left chasing it round the wall
local TOP_SPEED = 7
local MAX_SHOTS = 5
local SHOT_SPEED = 15
local SHOT_LIFE = 17
local SHOT_STEPS = 3      -- a shot checks for hits this many times a step, so it can't jump over a small rock
local TAP_REACH = 5       -- a tap this close to a target counts as a tap on it
local WARP_TICKS = 6
local WARP_COOL = 40
local WAVE_BREATHER = 20
local MOST_ROCKS = 9
local CLEAR_START = 70    -- a new rock starts at least this far from the ship
local BLAST_TICKS = 6
local SAUCER_SPEED = 2.4
local SAUCER_TURN = 25
local BOMB_SPEED = 6
local BOMB_LIFE = 30
local SMALL_SAUCER_AT = 5000
local SAUCERS = {
  large = { radius = 8, score = 200, fire = 20 },
  small = { radius = 5, score = 1000, fire = 12 },
}
local BOT_EVERY = 4       -- steps between the bot's taps: about what a person can do
local BOT_SLIP = 0.3      -- how often the bot taps wide of its target
local BOT_LOOK = 10       -- steps ahead the bot watches for a crash

--- The shortest way across one wrapped axis.
local function across(d, span)
  if d > span / 2 then return d - span end
  if d < -span / 2 then return d + span end
  return d
end

--- From a to b the shortest way round the wrapped board.
local function towards(a, b)
  return across(b.x - a.x, WIDTH), across(b.y - a.y, HEIGHT)
end

local function distance(a, b)
  local dx, dy = towards(a, b)
  return sqrt(dx * dx + dy * dy)
end

local function move(o)
  o.x = (o.x + o.vx) % WIDTH
  o.y = (o.y + o.vy) % HEIGHT
end

local function alive(s)
  return s.dead == 0 and s.gone == 0
end

local function blast(s, x, y, size)
  s.blasts[#s.blasts + 1] = { x = x, y = y, size = size, age = 0 }
end

--- Add to the score, and hand out any extra life it passes.
local function award(s, points, events)
  s.score = s.score + points
  while s.score >= s.nextLife do
    s.nextLife = s.nextLife + EXTRA_LIFE
    s.lives = s.lives + 1
    events[#events + 1] = { type = "life" }
  end
end

local function newRock(x, y, size, rng)
  local heading = rng() * TAU
  local speed = SIZES[size].speed * (0.7 + rng() * 0.6)
  return {
    x = x, y = y, vx = cos(heading) * speed, vy = sin(heading) * speed, size = size, radius = SIZES[size].radius,
    look = rng(M.LOOKS), angle = rng() * TAU, spin = (rng() - 0.5) * 0.3,
  }
end

--- A new rock starts anywhere on the board that's well clear of the ship.
local function clearSpot(s, rng)
  local spot
  repeat
    spot = { x = rng() * WIDTH, y = rng() * HEIGHT }
  until distance(spot, s.ship) >= CLEAR_START
  return spot
end

--- A wave: one more rock each time, up to a limit, and a little quicker.
local function startWave(s, rng)
  local pace = min(1.5, 1 + (s.level - 1) * 0.05)
  for _ = 1, min(MOST_ROCKS, 3 + s.level) do
    local spot = clearSpot(s, rng)
    local rock = newRock(spot.x, spot.y, LARGE, rng)
    rock.vx, rock.vy = rock.vx * pace, rock.vy * pace
    s.rocks[#s.rocks + 1] = rock
  end
end

local function saucerWait(s, rng)
  return 220 + rng(200) - min(100, s.level * 10)
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = {
    score = 0, level = 1, lives = START_LIVES, over = false, nextLife = EXTRA_LIFE, clock = 0,
    ship = { x = WIDTH / 2, y = HEIGHT / 2, vx = 0, vy = 0, angle = -math.pi / 2 },
    rocks = {}, shots = {}, bombs = {}, blasts = {},
    hold = HOLD_TICKS, dead = 0, safe = SAFE_TICKS, burn = 0, gone = 0, cool = 0, breather = 0,
    push = false, warp = false,
  }
  s.saucerIn = saucerWait(s, opts.rng)
  startWave(s, opts.rng)
  return s
end

--- A player's input. Applied at the next step.
function M.input(s, action)
  if action.kind == "aim" and type(action.x) == "number" and type(action.y) == "number" then
    s.want = { x = action.x, y = action.y }
  elseif action.kind == "thrust" then
    s.push = true
  elseif action.kind == "hyper" then
    s.warp = true
  end
end

--- The rock or saucer a tap landed on, or nil.
local function tappedTarget(s, tap)
  local best, bestGap
  local function try(target)
    local gap = distance(tap, target) - target.radius
    if gap <= TAP_REACH and (not best or gap < bestGap) then best, bestGap = target, gap end
  end
  for _, rock in ipairs(s.rocks) do try(rock) end
  if s.saucer then try(s.saucer) end
  return best
end

--- Where a shot must go to meet a target that keeps moving. It starts from the copy the player tapped.
local function leadPoint(ship, target, tap)
  local dx, dy = towards(tap, target)
  local x, y = tap.x + dx, tap.y + dy
  local time = 0
  for _ = 1, 3 do
    local gapX, gapY = x + target.vx * time - ship.x, y + target.vy * time - ship.y
    time = sqrt(gapX * gapX + gapY * gapY) / SHOT_SPEED
  end
  return x + target.vx * time, y + target.vy * time
end

--- Turn to face a tap and fire. A tap on a target leads it; a tap on empty space goes exactly there.
local function aimAndFire(s, tap, events)
  local ship = s.ship
  local x, y = tap.x, tap.y
  local target = tappedTarget(s, tap)
  if target then x, y = leadPoint(ship, target, tap) end
  local dx, dy = x - ship.x, y - ship.y
  if dx == 0 and dy == 0 then return end
  ship.angle = atan2(dy, dx)
  if #s.shots >= MAX_SHOTS then return end
  -- a shot ignores the ship's drift: it has to go where the player tapped
  s.shots[#s.shots + 1] = {
    x = ship.x, y = ship.y, vx = cos(ship.angle) * SHOT_SPEED, vy = sin(ship.angle) * SHOT_SPEED, life = SHOT_LIFE,
  }
  events[#events + 1] = { type = "shot" }
end

local function warpAway(s, events)
  if s.cool > 0 then return end
  s.gone, s.cool, s.burn = WARP_TICKS, WARP_COOL, 0
  events[#events + 1] = { type = "hyper" }
end

--- Land somewhere at random, at rest. Nothing makes the spot safe: that's the price of the button.
local function warpLand(s, rng)
  local ship = s.ship
  ship.x, ship.y, ship.vx, ship.vy = rng() * WIDTH, rng() * HEIGHT, 0, 0
end

local function applyInput(s, events)
  if alive(s) then
    if s.want then aimAndFire(s, s.want, events) end
    if s.push then s.burn = min(BURN_MOST, s.burn + BURN_PER_TAP) end
    if s.warp then warpAway(s, events) end
  end
  s.want, s.push, s.warp = nil, false, false
end

local function moveShip(s)
  local ship = s.ship
  if s.burn > 0 then
    s.burn = s.burn - 1
    ship.vx = ship.vx + cos(ship.angle) * THRUST
    ship.vy = ship.vy + sin(ship.angle) * THRUST
  end
  ship.vx, ship.vy = ship.vx * DRAG, ship.vy * DRAG
  local speed = sqrt(ship.vx * ship.vx + ship.vy * ship.vy)
  if speed > TOP_SPEED then
    ship.vx, ship.vy = ship.vx * TOP_SPEED / speed, ship.vy * TOP_SPEED / speed
  end
  move(ship)
end

--- Break a rock into two of the next size down. A small one is simply gone.
local function breakRock(s, index, rng, events)
  local rock = table.remove(s.rocks, index)
  award(s, SIZES[rock.size].score, events)
  blast(s, rock.x, rock.y, rock.size)
  events[#events + 1] = { type = "rock", size = rock.size }
  if rock.size == 1 then return end
  for _ = 1, 2 do
    local piece = newRock(rock.x, rock.y, rock.size - 1, rng)
    piece.vx, piece.vy = piece.vx + rock.vx / 2, piece.vy + rock.vy / 2
    s.rocks[#s.rocks + 1] = piece
  end
end

local function destroySaucer(s, events)
  local saucer = s.saucer
  s.saucer = nil
  s.saucerIn = s.saucerNext
  award(s, SAUCERS[saucer.kind].score, events)
  blast(s, saucer.x, saucer.y, 2)
  events[#events + 1] = { type = "saucerHit" }
end

--- Has this shot hit anything where it is now?
local function shotLands(s, shot, rng, events)
  for i, rock in ipairs(s.rocks) do
    if distance(shot, rock) <= rock.radius + 1 then
      breakRock(s, i, rng, events)
      return true
    end
  end
  if s.saucer and distance(shot, s.saucer) <= s.saucer.radius + 1 then
    destroySaucer(s, events)
    return true
  end
  return false
end

local function moveShot(s, shot, rng, events)
  for _ = 1, SHOT_STEPS do
    shot.x = (shot.x + shot.vx / SHOT_STEPS) % WIDTH
    shot.y = (shot.y + shot.vy / SHOT_STEPS) % HEIGHT
    if shotLands(s, shot, rng, events) then return true end
  end
  shot.life = shot.life - 1
  return shot.life <= 0
end

local function moveShots(s, rng, events)
  for i = #s.shots, 1, -1 do
    if moveShot(s, s.shots[i], rng, events) then table.remove(s.shots, i) end
  end
end

local function moveBombs(s)
  for i = #s.bombs, 1, -1 do
    local bomb = s.bombs[i]
    move(bomb)
    bomb.life = bomb.life - 1
    if bomb.life <= 0 then table.remove(s.bombs, i) end
  end
end

local function crash(s, events)
  s.lives = s.lives - 1
  s.dead, s.burn = DEAD_TICKS, 0
  blast(s, s.ship.x, s.ship.y, LARGE)
  events[#events + 1] = { type = "crash" }
end

--- Did anything reach the ship? Whatever hit it breaks too, and still scores.
local function checkShip(s, rng, events)
  if not alive(s) or s.safe > 0 then return end
  local ship = s.ship
  for i, rock in ipairs(s.rocks) do
    if distance(ship, rock) <= rock.radius + SHIP_RADIUS then
      crash(s, events)
      breakRock(s, i, rng, events)
      return
    end
  end
  for i, bomb in ipairs(s.bombs) do
    if distance(ship, bomb) <= SHIP_RADIUS + 1 then
      table.remove(s.bombs, i)
      crash(s, events)
      return
    end
  end
  if s.saucer and distance(ship, s.saucer) <= s.saucer.radius + SHIP_RADIUS then
    crash(s, events)
    destroySaucer(s, events)
  end
end

local function launchSaucer(s, rng, events)
  local big = s.score < SMALL_SAUCER_AT and rng() < 0.7
  local kind = big and "large" or "small"
  local dir = rng() < 0.5 and 1 or -1
  s.saucer = {
    x = dir > 0 and 0 or WIDTH - 1, y = rng() * HEIGHT, vx = dir * SAUCER_SPEED, vy = 0, kind = kind,
    radius = SAUCERS[kind].radius, left = floor(WIDTH / SAUCER_SPEED), fire = SAUCERS[kind].fire,
  }
  s.saucerNext = saucerWait(s, rng)
  events[#events + 1] = { type = "saucer" }
end

--- A large saucer fires anywhere. A small one aims at the ship, a little off.
local function saucerFires(s, rng)
  local saucer, ship = s.saucer, s.ship
  saucer.fire = SAUCERS[saucer.kind].fire
  local heading = rng() * TAU
  if saucer.kind == "small" and alive(s) then
    local dx, dy = towards(saucer, ship)
    heading = atan2(dy, dx) + (rng() - 0.5) * 0.5
  end
  s.bombs[#s.bombs + 1] = {
    x = saucer.x, y = saucer.y, vx = cos(heading) * BOMB_SPEED, vy = sin(heading) * BOMB_SPEED, life = BOMB_LIFE,
  }
end

local function moveSaucer(s, rng)
  local saucer = s.saucer
  saucer.left = saucer.left - 1
  if saucer.left <= 0 then
    s.saucer, s.saucerIn = nil, s.saucerNext
    return
  end
  if saucer.left % SAUCER_TURN == 0 then saucer.vy = (rng(3) - 2) * 1.2 end
  saucer.x = saucer.x + saucer.vx
  saucer.y = (saucer.y + saucer.vy) % HEIGHT
  saucer.fire = saucer.fire - 1
  if saucer.fire <= 0 then saucerFires(s, rng) end
end

local function runSaucer(s, rng, events)
  if s.saucer then
    moveSaucer(s, rng)
  elseif #s.rocks > 0 then
    s.saucerIn = s.saucerIn - 1
    if s.saucerIn <= 0 then launchSaucer(s, rng, events) end
  end
end

local function respawn(s)
  local ship = s.ship
  ship.x, ship.y, ship.vx, ship.vy = WIDTH / 2, HEIGHT / 2, 0, 0
  s.safe = SAFE_TICKS
end

--- Count down whatever is running out this step.
local function runTimers(s, rng)
  if s.safe > 0 then s.safe = s.safe - 1 end
  if s.cool > 0 then s.cool = s.cool - 1 end
  if s.gone > 0 then
    s.gone = s.gone - 1
    if s.gone == 0 then warpLand(s, rng) end
  end
  if s.dead > 0 then
    s.dead = s.dead - 1
    if s.dead == 0 then
      if s.lives <= 0 then s.over = true else respawn(s) end
    end
  end
  for i = #s.blasts, 1, -1 do
    local b = s.blasts[i]
    b.age = b.age + 1
    if b.age > BLAST_TICKS then table.remove(s.blasts, i) end
  end
end

--- A cleared board gets a short breather, then the next wave.
local function runWaves(s, rng, events)
  if #s.rocks > 0 or s.over then return end
  if s.breather == 0 then s.breather = WAVE_BREATHER end
  s.breather = s.breather - 1
  if s.breather == 0 then
    s.level = s.level + 1
    startWave(s, rng)
    events[#events + 1] = { type = "level" }
  end
end

--- Is the board still waiting at the start? Any tap, or the time running out, sets it going.
local function holding(s)
  if s.hold == 0 then return false end
  if s.want or s.push or s.warp then
    s.hold = 0
    return false
  end
  s.hold = s.hold - 1
  return true
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  if holding(s) then return events end
  applyInput(s, events)
  if alive(s) then moveShip(s) end
  for _, rock in ipairs(s.rocks) do
    move(rock)
    rock.angle = rock.angle + rock.spin
  end
  moveShots(s, rng, events)
  moveBombs(s)
  runSaucer(s, rng, events)
  checkShip(s, rng, events)
  runTimers(s, rng)
  runWaves(s, rng, events)
  return events
end

-- ---------------------------------------------------------------- the bot

--- Steps until an object touches the ship on their present courses, or nil.
local function impact(ship, o, radius)
  local dx, dy = towards(ship, o)
  local vx, vy = o.vx - ship.vx, o.vy - ship.vy
  local speed2 = vx * vx + vy * vy
  if speed2 < 0.001 then return nil end
  local time = -(dx * vx + dy * vy) / speed2
  if time < 0 or time > BOT_LOOK then return nil end
  local x, y = dx + vx * time, dy + vy * time
  if x * x + y * y > radius * radius then return nil end
  return time
end

--- The next thing about to hit the ship, and how soon.
local function nextThreat(s)
  local ship = s.ship
  local threat, soonest
  local function try(o, radius)
    local time = impact(ship, o, radius + SHIP_RADIUS + 2)
    if time and (not threat or time < soonest) then threat, soonest = o, time end
  end
  for _, rock in ipairs(s.rocks) do try(rock, rock.radius) end
  for _, bomb in ipairs(s.bombs) do try(bomb, 1) end
  if s.saucer then try(s.saucer, s.saucer.radius) end
  return threat, soonest
end

local function nearestTarget(s)
  local best, bestGap
  for _, rock in ipairs(s.rocks) do
    local gap = distance(s.ship, rock)
    if not best or gap < bestGap then best, bestGap = rock, gap end
  end
  -- a saucer is worth going after first
  return s.saucer or best
end

--- Face away from a threat, or burn if already facing that way.
local function runFrom(s, threat)
  local ship = s.ship
  local dx, dy = towards(threat, ship)
  local away = atan2(dy, dx)
  local turn = across(away - ship.angle, TAU)
  if turn > -1 and turn < 1 and s.burn == 0 then return { kind = "thrust" } end
  return { kind = "aim", x = (ship.x + cos(away) * 40) % WIDTH, y = (ship.y + sin(away) * 40) % HEIGHT }
end

--- A plain player for the idle screen and tests. It taps at a person's pace and is not a perfect shot.
function M.bot(s, rng)
  if not alive(s) then return nil end
  local threat, soon = nextThreat(s)
  if threat and soon <= 2 and s.safe == 0 and s.cool == 0 then return { kind = "hyper" } end
  if s.clock % BOT_EVERY ~= 0 then return nil end
  if threat and (not threat.radius or #s.shots >= MAX_SHOTS) then return runFrom(s, threat) end
  local target = threat or nearestTarget(s)
  if not target then return nil end
  if rng() < BOT_SLIP then
    local heading = rng() * TAU
    return { kind = "aim", x = (target.x + cos(heading) * 30) % WIDTH, y = (target.y + sin(heading) * 30) % HEIGHT }
  end
  return { kind = "aim", x = target.x, y = target.y }
end

return M
