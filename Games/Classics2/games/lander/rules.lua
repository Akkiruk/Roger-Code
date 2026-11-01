-- games/lander/rules.lua
-- Lunar Lander, after the 1979 arcade game. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Everything lives in world units, the same size across and down. A monitor cell is 2 units wide and 3 tall, so the board
-- of 96 x 60 cells is a 192 x 180 world, and y grows downward. Only the plugin knows about cells.
-- A run is a string of sites. Each is a fresh moonscape; fuel carries from one to the next, and the run ends with it.

local M = {
  WIDTH = 192, HEIGHT = 180, CELL_W = 2, CELL_H = 3, COLS = 96,
  TILT_STEP = 15, TILT_MOST = 90,
  BURN_PER_TAP = 10, BURN_MOST = 25,
  THRUST = 0.02,
  GRAVITY = 0.006, GRAVITY_RISE = 0.0003, GRAVITY_MOST = 0.008,
  START_FUEL = 450, LAND_FUEL = 40, CRASH_FUEL = 200,
  SAFE_VY = 0.24, SAFE_VX = 0.14,
  GOOD_VY = 0.17, GOOD_VX = 0.09,
  SOFT_VY = 0.11, SOFT_VX = 0.05,
  SAFE_TILT = 15,
  LAND_POINTS = 100, SOFT_POINTS = 50, ROUGH_POINTS = 40,
  FOOT_W = 5, FOOT_H = 6,     -- from the craft's centre to its feet
  SPAWN_Y = 14,
  PAD_WIDTHS = { [2] = 34, [3] = 28, [4] = 22, [5] = 16 }, -- by multiplier: a smaller pad is worth more
  PAD_SHRINK_MOST = 4,
  PAD_NARROWEST = 16,
  BOT_EVERY = 8,              -- steps between the bot's taps: about what a person can do
}

local WIDTH, COLS, CELL_W, CELL_H = M.WIDTH, M.COLS, M.CELL_W, M.CELL_H
local THRUST, FOOT_W, FOOT_H = M.THRUST, M.FOOT_W, M.FOOT_H
local abs, cos, floor, max, min, rad, sin, sqrt = math.abs, math.cos, math.floor, math.max, math.min, math.rad, math.sin, math.sqrt

local FUEL_PER_STEP = 1
local SITE_HOLD = 20        -- a new site waits this long for a look at the pads, or until the first tap
local FIRST_HOLD = 50       -- the first one waits longer, for the walk from START
local RESULT_PAUSE = 30     -- steps the result stays up before the next site
local CEILING = 6           -- nothing can loiter out of sight above the board
local GROUND_TOP, GROUND_LOW = 90, 172
local GROUND_JUMP = 30      -- the most one stretch of moonscape can climb or drop
local PAD_TOP, PAD_LOW = 115, 165
local PAD_COUNT = 4
local EDGE = 2              -- columns kept clear of pads at each side
local WALL = 3              -- columns of rock either side of a pad, for the pads that have walls
local BLAST_MOST = 12
-- the bot
local BOT_BRAKE = 0.0035    -- how hard it plans to slow down, well inside what thrust can do
local BOT_CRUISE = 0.6      -- the fastest it wants to fall or drift
local BOT_TOUCH = 0.13      -- the speed it wants to arrive at
local BOT_CLEAR = 16        -- how far above the rocks it stays until it's over the pad
local BOT_DRIFT = 0.007     -- drift wanted for each unit away from the pad
local BOT_CREEP = 0.08      -- the slowest it will drift toward the pad: one burn at the smallest tilt is about 0.05
local BOT_SLACK = 0.03      -- drift error it lets go on the way across
local BOT_FINE = 0.027      -- drift error it lets go over the pad: half what one burn at the smallest tilt changes
local BOT_TRIM = 100        -- over the pad and lower than this, it will burn just to trim its drift
local BOT_LOW = 8           -- over the pad and this low, it stops steering and gets upright
local BOT_MARGIN = 0.5      -- how far inside the pad's edge the feet must stay
local BOT_DESCENT = 0.15    -- its usual fall near the end, for guessing how long is left
local BOT_SOON = 40         -- the least time it ever thinks is left
local BOT_SHORT = 200       -- with less fuel than this at the start of a site, it takes the nearest pad
local BOT_GREED = 20        -- how much further it will go, in world units, for each step of multiplier
local BOT_BOOST = 0.08      -- how far a sideways burn may push it upward

local function clamp(v, low, high)
  return min(high, max(low, v))
end

--- The column a world x falls in.
local function column(x)
  return clamp(floor(x / CELL_W) + 1, 1, COLS)
end

--- The highest ground (smallest y) anywhere between two world x.
local function highestGround(s, x1, x2)
  local top = math.huge
  for c = column(min(x1, x2)), column(max(x1, x2)) do top = min(top, s.ground[c]) end
  return top
end

--- Gravity at a level: it grows gently, and stops where thrust can still win comfortably.
function M.gravityAt(level)
  return min(M.GRAVITY_MOST, M.GRAVITY + (level - 1) * M.GRAVITY_RISE)
end

--- A pad's width at a level. Never so small that the feet can't fit with room to spare.
function M.padWidth(mult, level)
  return max(M.PAD_NARROWEST, M.PAD_WIDTHS[mult] - min(M.PAD_SHRINK_MOST, level - 1))
end

--- Bare jagged moonscape: straight stretches of a few columns between random heights.
local function roughGround(rng)
  local ground = {}
  local y = GROUND_TOP + rng() * (GROUND_LOW - GROUND_TOP)
  local c = 1
  ground[1] = y
  while c < COLS do
    local run = 1 + rng(4)
    local nextY = clamp(y + (rng() - 0.5) * 2 * GROUND_JUMP, GROUND_TOP, GROUND_LOW)
    for i = 1, run do
      if c + i <= COLS then ground[c + i] = y + (nextY - y) * i / run end
    end
    c, y = c + run, nextY
  end
  return ground
end

--- Flatten a pad into the ground, on a whole row so it draws dead level. The dearer pads sit between walls of rock.
local function carvePad(s, first, cols, mult, rng)
  local row = floor((PAD_TOP + rng() * (PAD_LOW - PAD_TOP)) / CELL_H)
  local y = row * CELL_H
  for c = first, first + cols - 1 do s.ground[c] = y end
  if mult >= 4 then
    local rise = (mult - 3) * 10 + rng(8)
    for step = 1, WALL do
      local top = y - rise * (WALL - step + 1) / WALL
      local left, right = first - step, first + cols - 1 + step
      s.ground[left], s.ground[right] = min(s.ground[left], top), min(s.ground[right], top)
    end
  end
  local x0 = (first - 1) * CELL_W
  return { left = x0, right = x0 + cols * CELL_W, x = x0 + cols * CELL_W / 2, y = y, mult = mult, width = cols * CELL_W }
end

--- One pad to each stretch of the moon, so they can't overlap. The further from the craft, the more it's worth.
local function placePads(s, spawnX, rng)
  local slotCols = floor((COLS - 2 * EDGE) / PAD_COUNT)
  local slots = {}
  for i = 1, PAD_COUNT do
    local start = EDGE + (i - 1) * slotCols + 1
    slots[i] = { start = start, gap = abs(start + slotCols / 2 - spawnX / CELL_W) }
  end
  table.sort(slots, function(a, b) return a.gap < b.gap end)
  s.pads = {}
  for rank, slot in ipairs(slots) do
    local mult = rank + 1
    local cols = floor(M.padWidth(mult, s.level) / CELL_W)
    local first = slot.start + WALL + rng(slotCols - cols - 2 * WALL + 1) - 1
    s.pads[rank] = carvePad(s, first, cols, mult, rng)
  end
end

--- A new moonscape and a fresh approach, with the sideways drift the arcade game starts on.
local function newSite(s, rng)
  local x = WIDTH * (0.25 + rng() * 0.5)
  local drift = (0.12 + rng() * 0.14) * (rng() < 0.5 and -1 or 1)
  s.site = s.site + 1
  s.spawnX, s.siteFuel = x, s.fuel
  s.gravity = M.gravityAt(s.level)
  s.craft = { x = x, y = M.SPAWN_Y, vx = drift, vy = 0 }
  s.tilt, s.burn = 0, 0
  s.pushes, s.turns = 0, 0
  s.hold, s.pause = s.site == 1 and FIRST_HOLD or SITE_HOLD, 0
  s.result, s.blast = nil, nil
  s.ground = roughGround(rng)
  placePads(s, x, rng)
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = { score = 0, level = 1, over = false, clock = 0, site = 0, lastTap = -M.BOT_EVERY, fuel = M.START_FUEL }
  newSite(s, opts.rng)
  return s
end

--- A player's input. Applied at the next step. Tapping counts every tap, so none is lost between steps.
function M.input(s, action)
  if action.kind == "thrust" then
    s.pushes = s.pushes + 1
  elseif action.kind == "tilt" and (action.dir == 1 or action.dir == -1) then
    s.turns = s.turns + action.dir
  end
end

local function tapped(s)
  return s.pushes > 0 or s.turns ~= 0
end

--- Is the site still waiting? Any tap, or the time running out, sets it going.
local function holding(s)
  if s.hold == 0 then return false end
  if tapped(s) then
    s.hold = 0
    return false
  end
  s.hold = s.hold - 1
  return true
end

local function applyInput(s, events)
  if tapped(s) then s.lastTap = s.clock end
  if s.turns ~= 0 then s.tilt = clamp(s.tilt + s.turns * M.TILT_STEP, -M.TILT_MOST, M.TILT_MOST) end
  if s.pushes > 0 and s.fuel > 0 then
    s.burn = min(M.BURN_MOST, s.burn + s.pushes * M.BURN_PER_TAP)
    events[#events + 1] = { type = "thrust" }
  end
  s.pushes, s.turns = 0, 0
end

--- Gravity always, and thrust along the nose while a burn lasts. A tilt of 0 points straight up.
local function moveCraft(s)
  local c = s.craft
  if s.burn > 0 then
    local angle = rad(s.tilt)
    s.burn = s.burn - 1
    s.fuel = max(0, s.fuel - FUEL_PER_STEP)
    if s.fuel == 0 then s.burn = 0 end
    c.vx = c.vx + sin(angle) * THRUST
    c.vy = c.vy - cos(angle) * THRUST
  end
  c.vy = c.vy + s.gravity
  c.x, c.y = c.x + c.vx, c.y + c.vy
  -- the sides of the board and the sky above it are soft: they stop the craft, and don't hurt it
  if c.x < FOOT_W or c.x > WIDTH - FOOT_W then
    c.x, c.vx = clamp(c.x, FOOT_W, WIDTH - FOOT_W), 0
  end
  if c.y < CEILING then c.y, c.vy = CEILING, max(0, c.vy) end
end

--- The pad under both feet, or nil.
local function padUnder(s)
  local c = s.craft
  for _, pad in ipairs(s.pads) do
    if c.x - FOOT_W >= pad.left and c.x + FOOT_W <= pad.right then return pad end
  end
  return nil
end

--- What's wrong with this touchdown, or nil. The wording shows on the board.
local function fault(s, pad)
  local c = s.craft
  if not pad then return "OFF THE PAD" end
  if abs(s.tilt) > M.SAFE_TILT then return "TILTED" end
  if c.vy > M.SAFE_VY then return "TOO FAST" end
  if abs(c.vx) > M.SAFE_VX then return "SLIDING" end
  return nil
end

--- How good a safe touchdown was: "soft", "good" or "rough".
local function grade(s)
  local c = s.craft
  local vx = abs(c.vx)
  if s.tilt == 0 and c.vy <= M.SOFT_VY and vx <= M.SOFT_VX then return "soft" end
  if s.tilt == 0 and c.vy <= M.GOOD_VY and vx <= M.GOOD_VX then return "good" end
  return "rough"
end

--- Points for a safe touchdown.
function M.pointsFor(rating, mult)
  if rating == "soft" then return (M.LAND_POINTS + M.SOFT_POINTS) * mult end
  if rating == "good" then return M.LAND_POINTS * mult end
  return M.ROUGH_POINTS * mult
end

local function land(s, pad, events)
  local c = s.craft
  local rating = grade(s)
  local points = M.pointsFor(rating, pad.mult)
  s.score = s.score + points
  s.fuel = s.fuel + M.LAND_FUEL
  s.level = s.level + 1
  s.result = { landed = true, grade = rating, mult = pad.mult, points = points, fuel = M.LAND_FUEL }
  c.y, c.vx, c.vy = pad.y - FOOT_H, 0, 0
  events[#events + 1] = { type = "landed", grade = rating, mult = pad.mult, points = points }
end

local function crash(s, why, events)
  local c = s.craft
  local lost = min(s.fuel, M.CRASH_FUEL)
  s.fuel = s.fuel - lost
  s.result = { landed = false, why = why, fuel = lost }
  s.blast = { x = c.x, y = c.y, age = 0 }
  c.vx, c.vy = 0, 0
  events[#events + 1] = { type = "crash", why = why }
end

--- Have the feet reached the ground? Rock under one foot counts just as the pad does under both.
local function checkGround(s, events)
  local c = s.craft
  if c.y + FOOT_H < highestGround(s, c.x - FOOT_W, c.x + FOOT_W) then return end
  local pad = padUnder(s)
  local why = fault(s, pad)
  s.burn, s.pause = 0, RESULT_PAUSE
  if why then crash(s, why, events) else land(s, pad, events) end
end

--- The result is showing: wait, then the next site, or the end if the fuel's gone.
local function runPause(s, rng, events)
  s.pushes, s.turns = 0, 0
  if s.blast and s.blast.age < BLAST_MOST then s.blast.age = s.blast.age + 1 end
  s.pause = s.pause - 1
  if s.pause > 0 then return end
  if s.fuel <= 0 then
    s.over = true
  else
    newSite(s, rng)
    events[#events + 1] = { type = "site" }
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  if s.pause > 0 then
    runPause(s, rng, events)
    return events
  end
  if holding(s) then return events end
  applyInput(s, events)
  moveCraft(s)
  checkGround(s, events)
  return events
end

-- ---------------------------------------------------------------- readouts

--- Height of the feet above the ground right below the craft.
function M.altitude(s)
  local c = s.craft
  return max(0, highestGround(s, c.x - FOOT_W, c.x + FOOT_W) - c.y - FOOT_H)
end

-- ---------------------------------------------------------------- the bot

--- The pad worth the trip: a dearer one if it's not much further, and the nearest once fuel runs short.
-- It's judged from where the site began, so the choice can't flip halfway down.
local function bestPad(s)
  local best, bestWorth
  local spare = s.siteFuel > BOT_SHORT and BOT_GREED or 0
  for _, pad in ipairs(s.pads) do
    local worth = pad.mult * spare - abs(pad.x - s.spawnX)
    if not best or worth > bestWorth then best, bestWorth = pad, worth end
  end
  return best
end

--- The speed it wants to be falling at this height: what it could still brake from, and no more.
local function fallFor(height, slowest)
  if height <= 0 then return slowest end
  return clamp(sqrt(2 * BOT_BRAKE * height), slowest, BOT_CRUISE)
end

--- The tilt that would fix the drift: none when it's near enough, and only as much as the error needs.
local function tiltFor(gap, slack)
  if abs(gap) <= slack then return 0 end
  local size = 15
  if abs(gap) > 0.25 then size = 45 elseif abs(gap) > 0.1 then size = 30 end
  return gap > 0 and size or -size
end

local function turnToward(s, wanted)
  return { kind = "tilt", dir = wanted > s.tilt and 1 or -1 }
end

--- The autopilot, for the idle screen and tests. It sees what a player sees and taps at a person's pace.
-- Sideways first, over the rocks; then upright and down onto the pad, braking along a planned speed for each height.
function M.bot(s)
  if s.pause > 0 or s.fuel <= 0 or s.clock - s.lastTap < M.BOT_EVERY then return nil end
  local c = s.craft
  local pad = bestPad(s)
  local angle = rad(s.tilt)
  -- where the burn already lit will leave it
  local vx = c.vx + s.burn * THRUST * sin(angle)
  local vy = c.vy + s.burn * (s.gravity - THRUST * cos(angle))
  local dx = pad.x - c.x
  local room = pad.width / 2 - FOOT_W - BOT_MARGIN
  local height, slowest = pad.y - FOOT_H - c.y, BOT_TOUCH
  local wanted
  local burnsToSteer = true
  -- nearly down with both feet still on, a wobble toward the edge isn't worth going round again for
  if abs(dx) <= room or (height < BOT_LOW and abs(dx) <= pad.width / 2 - FOOT_W) then
    -- a drift only needs trimming if it would carry the feet off the pad by the time they get there
    local flight = max(BOT_SOON, height / BOT_DESCENT)
    wanted = tiltFor(dx / flight - vx, max(BOT_FINE, room / flight))
    if height < BOT_LOW then wanted = 0 end
    -- high up, the brake burns can do the trimming: a burn just to steer would only hold it up there
    burnsToSteer = height < BOT_TRIM
  else
    local side = dx > 0 and 1 or -1
    height = highestGround(s, c.x - side * (FOOT_W + 2), pad.x - side * (pad.width / 2 - FOOT_W)) - FOOT_H - BOT_CLEAR - c.y
    slowest = height <= 0 and -0.05 or 0.05
    wanted = tiltFor(side * clamp(abs(dx) * BOT_DRIFT, BOT_CREEP, BOT_CRUISE) - vx, BOT_SLACK)
  end
  local fall = fallFor(height, slowest)
  if vy > fall and abs(s.tilt) <= 45 then return { kind = "thrust" } end
  if s.tilt ~= wanted then return turnToward(s, wanted) end
  if burnsToSteer and wanted ~= 0 and s.burn == 0 and vy - M.BURN_PER_TAP * (THRUST * cos(angle) - s.gravity) > -BOT_BOOST then
    return { kind = "thrust" }
  end
  return nil
end

return M
