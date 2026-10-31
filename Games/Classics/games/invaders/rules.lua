-- games/invaders/rules.lua
-- Space Invaders. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The board is in monitor cells, so a sprite is drawn cell for cell. Nothing can be held on a monitor, so a tap only ever
-- sets where the cannon is heading, it slides there, and it fires by itself. The player's whole job is aiming.

local M = {
  COLS = 117, ROWS = 64,
  INVADER_W = 9, INVADER_H = 5,
  CANNON_W = 9, CANNON_Y = 61, CANNON_H = 3,
  BASE_W = 13, BASE_Y = 50, BASE_H = 5,
  UFO_W = 11, UFO_Y = 2, UFO_H = 3,
}

local COLS = M.COLS
local INVADER_W, INVADER_H = M.INVADER_W, M.INVADER_H
local CANNON_Y, CANNON_H = M.CANNON_Y, M.CANNON_H
local CANNON_HALF = math.floor(M.CANNON_W / 2)
local BASE_W, BASE_Y = M.BASE_W, M.BASE_Y
local UFO_W, UFO_Y, UFO_H = M.UFO_W, M.UFO_Y, M.UFO_H

local RACK_COLS, PITCH_X, PITCH_Y = 9, 11, 6
local ROW_POINTS = { 30, 20, 20, 10, 10 }  -- top row first
local TOTAL = RACK_COLS * #ROW_POINTS
local START_Y = 7
local WAVE_LOWER, MOST_LOWER = 2, 14       -- rows each wave starts lower, and how far that can go
local MARCH_STEP, DROP_STEP = 2, 2         -- cells across on a step, rows down at a wall

local CANNON_SPEED = 4                     -- cells a step: quick, but it does have to travel
local SHOT_SPEED = 4                       -- rows a step
local FIRE_EVERY = 8                       -- steps between shots: a steady pace, whatever the player does

local UFO_SPEED = 2
local UFO_POINTS = { 50, 100, 150, 300 }
local UFO_LEAST_INVADERS = 8               -- no mystery ship over a nearly empty board

local START_PAUSE, WAVE_PAUSE, LOST_PAUSE = 8, 14, 16
local BLAST_STEPS, LABEL_STEPS = 3, 12
local BOT_EVERY = 3                        -- the bot taps this many steps apart, about what a person can do
local BOT_LOOK = 16                        -- rows above the cannon the bot watches for bombs
local BOT_SLIP = 0.3                       -- how often it is slow to react to one

-- The dome of a base, with an arch in its foot. "#" is a part that can wear away.
local BASE_SHAPE = {
  "..#########..",
  ".###########.",
  "#############",
  "#############",
  "####.....####",
}

local function clamp(x)
  return math.max(1 + CANNON_HALF, math.min(COLS - CANNON_HALF, x))
end

local function newRack(s)
  s.invaders = {}
  local top = START_Y + math.min(MOST_LOWER, (s.level - 1) * WAVE_LOWER)
  local left = 1 + math.floor((COLS - (RACK_COLS * PITCH_X - 2)) / 2)
  for row, points in ipairs(ROW_POINTS) do
    for col = 1, RACK_COLS do
      s.invaders[#s.invaders + 1] = {
        x = left + (col - 1) * PITCH_X, y = top + (row - 1) * PITCH_Y, points = points,
      }
    end
  end
  s.dir, s.frame = 1, 1
end

--- The bases: each row is a map of the columns still standing.
local function newBases(s)
  s.bases = {}
  for i = 1, 4 do
    local left = math.floor(COLS * (2 * i - 1) / 8 - BASE_W / 2) + 1
    for row, line in ipairs(BASE_SHAPE) do
      local y = BASE_Y + row - 1
      s.bases[y] = s.bases[y] or {}
      for col = 1, BASE_W do
        if line:sub(col, col) == "#" then s.bases[y][left + col - 1] = true end
      end
    end
  end
end

local function nextBomb(s, rng)
  return math.max(4, 16 - s.level) + rng(12)
end

local function nextUfo(rng)
  return 150 + rng(150)
end

--- Steps between marches. The fewer invaders are left the faster they go, and later waves start quicker.
local function marchDelay(s)
  local thinned = 2 + math.floor(8 * #s.invaders / TOTAL)
  return math.max(1, thinned - math.floor((s.level - 1) / 2))
end

M.marchDelay = marchDelay

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local rng = opts.rng
  local mid = math.floor(COLS / 2) + 1
  local s = {
    score = 0, level = 1, lives = 3, over = false,
    clock = 0, pause = START_PAUSE, wreck = false,
    x = mid, target = mid, fireWait = FIRE_EVERY,
    shots = {}, bombs = {}, blasts = {},
  }
  newRack(s)
  newBases(s)
  s.marchWait = marchDelay(s)
  s.bombWait = nextBomb(s, rng)
  s.ufoWait = nextUfo(rng)
  return s
end

--- A player's input: the column to slide to. It stays set, so one tap is enough.
function M.input(s, action)
  if action.kind == "aim" and type(action.x) == "number" then s.target = clamp(math.floor(action.x)) end
end

local function blast(s, x, y, points)
  local steps = points and LABEL_STEPS or BLAST_STEPS
  s.blasts[#s.blasts + 1] = { x = x, y = y, steps = steps, points = points }
end

local function ageBlasts(s)
  for i = #s.blasts, 1, -1 do
    local b = s.blasts[i]
    b.steps = b.steps - 1
    if b.steps <= 0 then table.remove(s.blasts, i) end
  end
end

local function slideCannon(s)
  local gap = s.target - s.x
  if gap > 0 then s.x = s.x + math.min(gap, CANNON_SPEED) end
  if gap < 0 then s.x = s.x - math.min(-gap, CANNON_SPEED) end
end

--- Bite a small piece out of a base at a hit: the cells beside and below it always, the corners by chance.
-- A base takes a dozen bombs or so, enough to last most of a wave.
local function erode(s, x, y, rng)
  for dy = 0, 1 do
    local row = s.bases[y + dy]
    for dx = -1, 1 do
      if row and row[x + dx] and (math.abs(dx) + math.abs(dy) <= 1 or rng(2) == 1) then row[x + dx] = nil end
    end
  end
end

--- Invaders walk straight through a base and take it with them.
local function trample(s)
  for _, inv in ipairs(s.invaders) do
    if inv.y + INVADER_H > BASE_Y then
      for y = inv.y, inv.y + INVADER_H - 1 do
        local row = s.bases[y]
        for x = inv.x, inv.x + INVADER_W - 1 do
          if row then row[x] = nil end
        end
      end
    end
  end
end

local function nextWave(s, rng, events)
  s.level = s.level + 1
  s.shots, s.bombs, s.ufo = {}, {}, nil
  newRack(s)
  newBases(s)
  s.marchWait = marchDelay(s)
  s.fireWait = FIRE_EVERY
  s.bombWait = nextBomb(s, rng)
  s.ufoWait = nextUfo(rng)
  s.pause = WAVE_PAUSE
  events[#events + 1] = { type = "wave", level = s.level }
end

--- Does this shot, at its present spot, hit anything? Shots pass over the player's own bases.
local function strike(s, shot, events)
  local u = s.ufo
  if u and shot.y >= UFO_Y and shot.y < UFO_Y + UFO_H and shot.x >= u.x and shot.x < u.x + UFO_W then
    s.score = s.score + u.points
    blast(s, u.x + 2, UFO_Y, u.points)
    s.ufo = nil
    s.ufoWait = s.ufoNext
    events[#events + 1] = { type = "mystery", points = u.points }
    return true
  end
  for i, inv in ipairs(s.invaders) do
    if shot.x >= inv.x and shot.x < inv.x + INVADER_W and shot.y >= inv.y and shot.y < inv.y + INVADER_H then
      s.score = s.score + inv.points
      blast(s, inv.x, inv.y)
      table.remove(s.invaders, i)
      events[#events + 1] = { type = "hit", points = inv.points }
      return true
    end
  end
  return false
end

local function moveShots(s, events)
  for i = #s.shots, 1, -1 do
    local shot = s.shots[i]
    local gone = false
    for _ = 1, SHOT_SPEED do
      shot.y = shot.y - 1
      gone = shot.y < 1 or strike(s, shot, events)
      if gone then break end
    end
    if gone then table.remove(s.shots, i) end
  end
end

local function loseLife(s, events)
  s.lives = s.lives - 1
  s.bombs, s.shots = {}, {}
  events[#events + 1] = { type = "lost" }
  if s.lives <= 0 then
    s.over = true
  else
    s.pause, s.wreck = LOST_PAUSE, true
  end
end

--- Rows a bomb falls this step: about one and a half to begin with, two from wave five.
local function bombStep(s)
  return (s.level >= 5 or s.clock % 2 == 0) and 2 or 1
end

--- Move one bomb down a row. True once it's spent; the second answer is true if it hit the cannon.
local function fall(s, bomb, rng)
  bomb.y = bomb.y + 1
  local row = s.bases[bomb.y]
  if row and row[bomb.x] then
    erode(s, bomb.x, bomb.y, rng)
    return true
  end
  if bomb.y >= CANNON_Y and bomb.y < CANNON_Y + CANNON_H and math.abs(bomb.x - s.x) <= CANNON_HALF then
    return true, true
  end
  return bomb.y >= M.ROWS
end

local function moveBombs(s, rng, events)
  local rows = bombStep(s)
  for i = #s.bombs, 1, -1 do
    local bomb = s.bombs[i]
    for _ = 1, rows do
      local spent, hit = fall(s, bomb, rng)
      if hit then
        loseLife(s, events)
        return
      end
      if spent then
        table.remove(s.bombs, i)
        break
      end
    end
  end
end

local function fire(s)
  s.fireWait = s.fireWait - 1
  if s.fireWait <= 0 then
    s.fireWait = FIRE_EVERY
    s.shots[#s.shots + 1] = { x = s.x, y = CANNON_Y }
  end
end

--- The lowest invader in each column of the rack, in a fixed order.
local function frontRow(s)
  local list, at = {}, {}
  for _, inv in ipairs(s.invaders) do
    if at[inv.x] then
      if inv.y > list[at[inv.x]].y then list[at[inv.x]] = inv end
    else
      list[#list + 1] = inv
      at[inv.x] = #list
    end
  end
  return list
end

local function nearestTo(list, x)
  local best = list[1]
  for _, inv in ipairs(list) do
    if math.abs(inv.x - x) < math.abs(best.x - x) then best = inv end
  end
  return best
end

--- Half the bombs come from the invader above the cannon, the rest from any column.
local function dropBomb(s, rng)
  s.bombWait = s.bombWait - 1
  local most = math.min(6, 2 + math.ceil(s.level / 2))
  if s.bombWait > 0 or #s.bombs >= most then return end
  s.bombWait = nextBomb(s, rng)
  local front = frontRow(s)
  local inv = rng(2) == 1 and nearestTo(front, s.x - CANNON_HALF) or front[rng(#front)]
  s.bombs[#s.bombs + 1] = { x = inv.x + math.floor(INVADER_W / 2), y = inv.y + INVADER_H - 1 }
end

local function moveUfo(s, rng, events)
  local u = s.ufo
  if u then
    u.x = u.x + u.dir * UFO_SPEED
    if u.x > COLS or u.x + UFO_W < 1 then
      s.ufo = nil
      s.ufoWait = s.ufoNext
    end
    return
  end
  s.ufoWait = s.ufoWait - 1
  if s.ufoWait > 0 or #s.invaders < UFO_LEAST_INVADERS then return end
  local dir = rng(2) == 1 and 1 or -1
  s.ufo = { x = dir == 1 and 1 - UFO_W or COLS, dir = dir, points = UFO_POINTS[rng(#UFO_POINTS)] }
  s.ufoNext = nextUfo(rng)
  events[#events + 1] = { type = "ufo" }
end

local function lowestRow(s)
  local lowest = 0
  for _, inv in ipairs(s.invaders) do lowest = math.max(lowest, inv.y + INVADER_H - 1) end
  return lowest
end

local function step(s, dx, dy)
  for _, inv in ipairs(s.invaders) do
    inv.x, inv.y = inv.x + dx, inv.y + dy
  end
end

--- One step of the rack: across, or down and back at a wall. Reaching the cannon ends the game, whatever lives are left.
local function march(s, events)
  s.marchWait = s.marchWait - 1
  if s.marchWait > 0 then return end
  s.marchWait = marchDelay(s)
  s.frame = 3 - s.frame
  local left, right = COLS, 1
  for _, inv in ipairs(s.invaders) do
    left, right = math.min(left, inv.x), math.max(right, inv.x + INVADER_W - 1)
  end
  local dx = s.dir * MARCH_STEP
  if left + dx < 1 or right + dx > COLS then
    s.dir = -s.dir
    step(s, 0, DROP_STEP)
  else
    step(s, dx, 0)
  end
  trample(s)
  events[#events + 1] = { type = "march", frame = s.frame }
  if lowestRow(s) >= CANNON_Y then
    s.lives, s.over = 0, true
    events[#events + 1] = { type = "landed" }
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  ageBlasts(s)
  if not s.wreck then slideCannon(s) end
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause == 0 then s.wreck = false end
    return events
  end
  moveShots(s, events)
  if #s.invaders == 0 then
    nextWave(s, rng, events)
    return events
  end
  moveBombs(s, rng, events)
  if s.pause > 0 or s.over then return events end
  fire(s)
  dropBomb(s, rng)
  moveUfo(s, rng, events)
  march(s, events)
  return events
end

--- Is a bomb about to land on this column?
local function bombOver(s, x)
  for _, bomb in ipairs(s.bombs) do
    if bomb.y >= CANNON_Y - BOT_LOOK and math.abs(bomb.x - x) <= CANNON_HALF + 1 then return true end
  end
  return false
end

--- The nearest column with no bomb over it.
local function dodge(s)
  for gap = 3, COLS, 3 do
    for _, x in ipairs({ clamp(s.x - gap), clamp(s.x + gap) }) do
      if not bombOver(s, x) then return x end
    end
  end
  return nil
end

--- Where to stand to hit the nearest of the lowest invaders, allowing for how far it moves while the shot climbs.
local function aimPoint(s)
  local deepest = lowestRow(s) - INVADER_H + 1
  local best, bestCost
  for _, inv in ipairs(frontRow(s)) do
    local cost = math.abs(inv.x - s.x) + (deepest - inv.y) * 8
    if not best or cost < bestCost then best, bestCost = inv, cost end
  end
  if not best then return s.x end
  local flight = (CANNON_Y - best.y) / SHOT_SPEED
  local drift = math.floor(flight / marchDelay(s)) * MARCH_STEP * s.dir
  return clamp(best.x + math.floor(INVADER_W / 2) + drift)
end

--- A plain player for the idle screen and tests: dodge what it notices, otherwise pick off the lowest invaders.
-- It taps at a person's pace and is sometimes slow to react, so it scores well and still loses in the end.
function M.bot(s, rng)
  if s.pause > 0 or s.clock % BOT_EVERY ~= 0 then return nil end
  if bombOver(s, s.x) then
    if rng() < BOT_SLIP then return nil end
    local x = dodge(s)
    return x and { kind = "aim", x = x } or nil
  end
  local x = aimPoint(s)
  if bombOver(s, x) or x == s.target then return nil end
  return { kind = "aim", x = x }
end

return M
