-- games/moag/rules.lua
-- MOAG: two tanks taking turns to shell each other across ground that doesn't stay put. Pure: no screen, sound or files.
-- See "Versus" in games/README.md; a versus game has a player on every call.
-- A turn: drive a little on the fuel the turn gives, set the barrel's angle and the power, pick a weapon, FIRE. The shot
-- plays out to the end, dirt and all, before the other tank's turn. The wind changes every turn and is shown before you aim.
-- Everything lives in world units, the same size across and down. A monitor cell is 2 units wide and 3 tall, and y grows
-- downward. The ground is a height for each column of cells. A hole cut under a column leaves what was above it as a slab,
-- which falls and lands, so an overhang can't last and a tank can be sheltered or buried by what comes down.
-- Player 1's tank starts on the left of the world and player 2's on the right, and each faces the other: an angle is
-- measured from straight ahead, towards the other tank, so 0 is flat forward, 90 is straight up and 180 is flat back.
-- Only the plugin knows about mirrors.

local M = {
  WIDTH = 240, HEIGHT = 171, CELL_W = 2, CELL_H = 3, COLS = 120,
  ROUNDS_TO_WIN = 3, HP = 100,
  GRAVITY = 0.5,
  POWER_SPEED = 0.12,         -- launch speed for each point of power, so 100 is 12 units a tick
  WIND_STEP = 0.012,          -- the push of one point of wind, in units a tick per tick
  WIND_MOST = 10,             -- the strongest wind, in points
  TURN_TICKS = 450,           -- a turn's time: 45 seconds at 100 ms a tick
  HURRY = 100,                -- ticks left when the clock warns
  FUEL = 40,                  -- units of driving a turn gives
  DRIVE_TICKS = 6, DRIVE_MOST = 24, SPEED = 1.5,
  AIM_REACH = 100,            -- a tap this far from the barrel's root is full power
  ANGLE = 45, POWER = 60,     -- where a barrel starts
  TANK_HALF = 7, TANK_H = 9,  -- from the centre to the side, and from the tracks to the roof
  TURRET_H = 7, BARREL = 8,
  MAX_RISE = 1.3,             -- the steepest step a tank climbs from one column to the next
  REPOSE = 1.1,               -- the steepest loose dirt lies: gentle enough to drive out of a crater
  BURY = 9,                   -- this much dirt over the tracks and the tank can't shake it off
  REACH = 1.5,                -- a blast hurts out to this many times the size of its crater
  BEDROCK = 165,              -- nothing digs below this
  SUDDEN_TURNS = 16,          -- turns into a round when both tanks start to fail
  SUDDEN_HP = 15,             -- what each turn after that costs both
  DIG_MOST = 70, DIG_SPEED = 4, DIG_BORE = 5,
  CRATE_MOST = 2, CRATE_CHANCE = 0.4, CRATE_REACH = 10,
  DRAWS_MOST = 3,             -- this many level rounds in a row and the match stops
  PREVIEW_TICKS = 12,         -- how much of the flight the dotted start of the arc shows
}

-- What each weapon does. radius is the crater, damage is what a direct hit costs, ammo is how many shots a crate holds.
M.WEAPONS = {
  shell = { name = "SHELL", short = "SHELL", radius = 11, damage = 30 },
  big = { name = "BIG SHELL", short = "BIG", radius = 16, damage = 45, ammo = 2 },
  cluster = { name = "CLUSTER", short = "CLUSTER", radius = 7, damage = 16, ammo = 2, count = 5, spread = 1.1 },
  dirt = { name = "DIRT BOMB", short = "DIRT", radius = 20, damage = 0, ammo = 2 },
  tunneller = { name = "TUNNELLER", short = "TUNNEL", radius = 10, damage = 34, ammo = 2 },
  nuke = { name = "NUKE", short = "NUKE", radius = 32, damage = 80, ammo = 1 },
}
-- The order the weapon button goes through them.
M.ORDER = { "shell", "big", "cluster", "dirt", "tunneller", "nuke" }
-- What a crate can hold. The nuke is rarer than the rest.
M.LOOT = { "big", "cluster", "dirt", "tunneller", "big", "cluster", "dirt", "tunneller", "nuke" }

local WIDTH, HEIGHT, CELL_W, COLS = M.WIDTH, M.HEIGHT, M.CELL_W, M.COLS
local GRAVITY, BEDROCK, WEAPONS = M.GRAVITY, M.BEDROCK, M.WEAPONS
local TANK_HALF, TANK_H, SPEED = M.TANK_HALF, M.TANK_H, M.SPEED
local abs, ceil, floor, max, min, pi, sin, cos, sqrt = math.abs, math.ceil, math.floor, math.max, math.min, math.pi, math.sin,
  math.cos, math.sqrt

local HOLD = 15             -- ticks a new round waits, for a look at the ground
local PAUSE = 30            -- ticks the result of a round stays up
local AFTER = 8             -- ticks a turn's end waits once all is still, to see what the shot did
local FLY_MOST = 300        -- a shot still going after this long is given up on
local STRIDE = 1.5          -- the furthest a shell goes between looks at what it's hitting
local ARM = 4               -- ticks before a shell can hit the tank that fired it
local OUT = 60              -- how far past the sides a shell can go and still come back
local PATH_MOST = 120       -- the most ticks of flight a path follows
local PATH_DOT = 2          -- ticks between the dots of a path
local FOOT = 2              -- columns either side of the centre that a tank rests on
local TOP_MOST = 6          -- dirt piles no higher than this
local TANK_FALL, SLAB_FALL = 3, 5
local SHAKE = 1             -- how fast a tank climbs out of dirt it can shake off
local CRATE_FALL, CRATE_DROP = 2.5, 3
local SLIDE_TICKS, SLIDE_PASSES, SLIDE_MARGIN = 30, 4, 8
local DIG_OUT = 12          -- the size of the hole a buried tank blows above itself
local BLAST_TICKS = 4
local POP_TICKS = 20        -- how long a hit's number floats over the tank
-- the ground
local HILL_LEVEL, HILL_RANGE = 108, 18
local HILL_MIDDLE = 40      -- how much higher the middle of the field stands than the ends
local HILL_TOP, HILL_LOW = 50, 152
local JAG = 10              -- the most a stretch of ground strays from the smooth hills
local SPAWN_NEAR, SPAWN_RANGE = 22, 32
local PAD = 6               -- columns either side of a tank that start out level
-- the computer
local BOT_ANGLES = { 15, 80, 5 } -- the angles it tries, from, to and step: one a tick, so the barrel sweeps as it thinks
local BOT_HALVES = 9        -- how many times it halves the power it's looking for at each angle
local BOT_MOVED = 12        -- a target that shifts this far has to be found again
local BOT_LEARN = 0.7       -- what each shot at a target that stayed put leaves of its error
local BOT_STEADIEST = 0.4   -- the least of its error it ever gets down to
-- How good the computer is: how far its angle and power stray, how well it reads the wind, and how long it looks first.
M.SKILL = {
  easy = { angle = 5, power = 7, wind = 0.6, think = 16 },
  normal = { angle = 2.5, power = 3.5, wind = 0.3, think = 12 },
  hard = { angle = 1, power = 1.2, wind = 0.08, think = 8 },
}

local function clamp(v, low, high)
  return min(high, max(low, v))
end

local function round(v) return floor(v + 0.5) end

--- Which way a player's tank faces in the world: player 1 looks right, player 2 left.
local function facing(player) return player == 2 and -1 or 1 end
M.facing = facing

--- The column a world x falls in, or nil off the field.
local function columnAt(x)
  local c = floor(x / CELL_W) + 1
  if c < 1 or c > COLS then return nil end
  return c
end

--- The height of the ground at a world x. Off the field there's none, so a shell carries on.
function M.groundAt(s, x)
  local c = columnAt(x)
  return c and s.ground[c] or math.huge
end

--- Where a tank's tracks come to rest at this x: on the highest of the columns under the middle of it.
function M.restY(s, x)
  local c = clamp(floor(x / CELL_W) + 1, 1, COLS)
  local top = math.huge
  for i = max(1, c - FOOT), min(COLS, c + FOOT) do top = min(top, s.ground[i]) end
  return top
end

-- ---------------------------------------------------------------- the ground

--- A stretch of jagged offsets: straight runs of a few columns between random heights.
local function jagged(rng)
  local out = {}
  local c, y = 1, (rng() - 0.5) * 2 * JAG
  out[1] = y
  while c < COLS do
    local run = 2 + rng(6)
    local nextY = (rng() - 0.5) * 2 * JAG
    for i = 1, run do
      if c + i <= COLS then out[c + i] = y + (nextY - y) * i / run end
    end
    c, y = c + run, nextY
  end
  return out
end

--- Level a tank's start, and ease the ground back into the hills either side of it.
local function levelPad(ground, x)
  local c = columnAt(x)
  local level = ground[c]
  for i = -PAD * 2, PAD * 2 do
    local at = c + i
    if at >= 1 and at <= COLS then
      local share = clamp(2 - abs(i) / PAD, 0, 1)
      ground[at] = level * share + ground[at] * (1 - share)
    end
  end
end

--- New hills: two rolling waves, a rise in the middle to shell over, and jags on top of that.
local function hills(rng, x1, x2)
  local ground = {}
  local jag = jagged(rng)
  local level = HILL_LEVEL + rng() * HILL_RANGE
  local waveA, waveB = rng() * 2 * pi, rng() * 2 * pi
  local countA, countB = 1 + rng() * 1.5, 3 + rng() * 2.5
  local middle = HILL_MIDDLE * (0.5 + rng() * 0.75)
  for c = 1, COLS do
    local at = c / COLS
    local rise = sin(at * pi)
    local y = level + sin(at * 2 * pi * countA + waveA) * 14 + sin(at * 2 * pi * countB + waveB) * 7 - rise * rise * middle
    ground[c] = clamp(y + jag[c], HILL_TOP, HILL_LOW)
  end
  levelPad(ground, x1)
  levelPad(ground, x2)
  return ground
end

--- Mark a run of columns as disturbed: they lose their grass, and the loose dirt there can slide.
local function disturb(s, from, to)
  from, to = max(1, from - SLIDE_MARGIN), min(COLS, to + SLIDE_MARGIN)
  s.slides[#s.slides + 1] = { from = from, to = to, left = SLIDE_TICKS }
  s.rev = s.rev + 1
end

--- Take a span of a falling slab out, leaving what's left of it above and below.
local function cutSlabs(s, c, top, bottom)
  local kept = {}
  for _, slab in ipairs(s.slabs) do
    local low = slab.top + slab.h
    if slab.c ~= c or low <= top or slab.top >= bottom then
      kept[#kept + 1] = slab
    else
      if slab.top < top then kept[#kept + 1] = { c = c, top = slab.top, h = top - slab.top } end
      if low > bottom then kept[#kept + 1] = { c = c, top = bottom, h = low - bottom } end
    end
  end
  s.slabs = kept
end

--- Cut a round hole. Dirt left hanging over it becomes a slab that falls.
function M.carve(s, x, y, radius)
  local from, to = floor((x - radius) / CELL_W) + 1, floor((x + radius) / CELL_W) + 1
  from, to = max(1, from), min(COLS, to)
  for c = from, to do
    local dx = (c - 0.5) * CELL_W - x
    if abs(dx) < radius then
      local half = sqrt(radius * radius - dx * dx)
      local top, bottom = y - half, min(y + half, BEDROCK)
      local g = s.ground[c]
      if #s.slabs > 0 then cutSlabs(s, c, top, bottom) end
      if bottom > g and top < bottom then
        if top > g then s.slabs[#s.slabs + 1] = { c = c, top = g, h = top - g } end
        s.ground[c] = bottom
        s.bare[c] = true
      end
    end
  end
  disturb(s, from, to)
end

--- Pile dirt up, in a mound as wide as a blast. Whatever's under it stays there. It's packed hard, so it stands as a wall
--- until something hits it.
function M.pile(s, x, radius)
  local from, to = floor((x - radius) / CELL_W) + 1, floor((x + radius) / CELL_W) + 1
  from, to = max(1, from), min(COLS, to)
  for c = from, to do
    local dx = (c - 0.5) * CELL_W - x
    if abs(dx) < radius then
      s.ground[c] = max(TOP_MOST, s.ground[c] - sqrt(radius * radius - dx * dx) * 2)
      s.bare[c] = true
    end
  end
  s.rev = s.rev + 1
end

--- Loose dirt slides until no step is steeper than it can lie. Returns true if anything moved.
local function slide(s, run)
  local ground, moved = s.ground, false
  for c = run.from, run.to - 1 do
    local step = ground[c + 1] - ground[c]
    local over = abs(step) - M.REPOSE
    if over > 0.05 then
      local share = over / 2 * (step > 0 and 1 or -1)
      ground[c] = ground[c] + share
      ground[c + 1] = min(BEDROCK, ground[c + 1] - share)
      s.bare[c], s.bare[c + 1] = true, true
      moved = true
    end
  end
  return moved
end

local function settleDirt(s)
  local kept = {}
  for _, slab in ipairs(s.slabs) do
    slab.top = slab.top + SLAB_FALL
    if slab.top + slab.h >= s.ground[slab.c] then
      s.ground[slab.c] = max(TOP_MOST, s.ground[slab.c] - slab.h)
      s.bare[slab.c] = true
      s.rev = s.rev + 1
    else
      kept[#kept + 1] = slab
    end
  end
  s.slabs = kept
  if #s.slabs > 0 then return end
  -- slopes wait for the dirt above them to come down
  local live = {}
  for _, run in ipairs(s.slides) do
    local moved = false
    for _ = 1, SLIDE_PASSES do moved = slide(s, run) or moved end
    if moved then s.rev = s.rev + 1 end
    run.left = run.left - 1
    if moved and run.left > 0 then live[#live + 1] = run end
  end
  s.slides = live
end

-- ---------------------------------------------------------------- ballistics

--- The barrel's way in the world for an angle: a unit step across and down.
function M.direction(player, angle)
  local a = angle * pi / 180
  return cos(a) * facing(player), -sin(a)
end

--- A shell leaving a tank's barrel at this angle and power: where it starts and how fast it's going.
function M.launch(t, player, angle, power)
  local ux, uy = M.direction(player, angle or t.angle)
  local speed = (power or t.power) * M.POWER_SPEED
  local x, y = t.x + ux * M.BARREL, t.y - M.TURRET_H + uy * M.BARREL
  return { x = x, y = y, vx = ux * speed, vy = uy * speed }
end

--- The angle and power a tap at a world spot means: the barrel points at it, and the further off it is the harder it fires.
function M.aimAt(t, player, x, y)
  local dx, dy = (x - t.x) * facing(player), (t.y - M.TURRET_H) - y
  local angle
  if dy <= 0 then
    angle = dx >= 0 and 0 or 180
  else
    angle = math.atan2(dy, dx) * 180 / pi
  end
  local power = sqrt(dx * dx + dy * dy) / M.AIM_REACH * 100
  return clamp(round(angle), 0, 180), clamp(round(power), 1, 100)
end

--- One tick of flight: wind and gravity change the speed, then it moves in strides, stopping if meets(s, b) says to.
local function fly(s, b, wind, meets)
  b.vx, b.vy = b.vx + wind, b.vy + GRAVITY
  local strides = max(1, ceil(max(abs(b.vx), abs(b.vy)) / STRIDE))
  local dx, dy = b.vx / strides, b.vy / strides
  for _ = 1, strides do
    b.x, b.y = b.x + dx, b.y + dy
    if meets(s, b) then return true end
  end
  return false
end

local function gone(b)
  return b.y >= HEIGHT or b.x < -OUT or b.x > WIDTH + OUT
end

local function inGround(s, b)
  return b.y >= M.groundAt(s, b.x) or gone(b)
end

--- How far a point is from a tank's hull. Inside it, that's nothing.
local function hullGap(t, x, y)
  local dx = max(abs(x - t.x) - TANK_HALF, 0)
  local dy = max(t.y - TANK_H - y, y - t.y, 0)
  return sqrt(dx * dx + dy * dy)
end
M.hullGap = hullGap

--- The tank a shell has hit, if any. Its own tank is safe from it for the first moments of the flight.
local function tankAt(s, b)
  for i, t in ipairs(s.tanks) do
    if t.hp > 0 and (i ~= b.owner or b.age > ARM) and hullGap(t, b.x, b.y) == 0 then return t, i end
  end
  return nil
end

local function meetsAnything(s, b)
  return tankAt(s, b) ~= nil or inGround(s, b)
end

--- Where a shot goes, as the wind stands: dots along the way, where it ends, and the tank it hits if it hits one.
--- most is how many ticks to follow it; it stops sooner if it lands.
function M.path(s, shot, wind, owner, most)
  local b = { x = shot.x, y = shot.y, vx = shot.vx, vy = shot.vy, owner = owner or 0, age = 0 }
  local dots = {}
  local landed = false
  for tick = 1, most or PATH_MOST do
    b.age = b.age + 1
    if fly(s, b, wind, meetsAnything) then
      landed = true
      break
    end
    if tick % PATH_DOT == 0 then dots[#dots + 1] = { x = b.x, y = b.y } end
  end
  local _, hit = tankAt(s, b)
  return dots, b.x, b.y, landed and hit or nil, landed
end

--- The dotted start of a player's arc, as their barrel stands now.
function M.preview(s, player)
  local t = s.tanks[player]
  local dots = M.path(s, M.launch(t, player), s.wind, player, M.PREVIEW_TICKS)
  return dots
end

-- ---------------------------------------------------------------- blasts

--- What a blast costs at this distance from it: all of it on a direct hit, and less the further out, down to nothing.
function M.damageAt(kind, gap)
  local w = WEAPONS[kind]
  local reach = w.radius * M.REACH
  if gap >= reach or w.damage == 0 then return 0 end
  return ceil(w.damage * (1 - gap / reach))
end

--- A shell goes off here: a crater, and a share of the damage to anything near.
function M.blast(s, x, y, kind, owner, events)
  local w = WEAPONS[kind]
  M.carve(s, x, y, w.radius)
  s.blasts[#s.blasts + 1] = { x = x, y = y, r = w.radius, left = BLAST_TICKS }
  events[#events + 1] = { type = "blast", kind = kind, x = x, y = y }
  for i, t in ipairs(s.tanks) do
    local cost = M.damageAt(kind, hullGap(t, x, y))
    if cost > 0 and t.hp > 0 then
      t.hp = max(0, t.hp - cost)
      s.pops[#s.pops + 1] = { player = i, text = "-" .. cost, left = POP_TICKS }
      events[#events + 1] = { type = "hit", player = i, damage = cost, by = owner }
    end
  end
  local kept = {}
  for _, crate in ipairs(s.crates) do
    if abs(crate.x - x) > w.radius or abs(crate.y - y) > w.radius then
      kept[#kept + 1] = crate
    else
      events[#events + 1] = { type = "crateLost" }
    end
  end
  s.crates = kept
end

local function dirtLands(s, b, events)
  M.pile(s, b.x, WEAPONS.dirt.radius)
  s.blasts[#s.blasts + 1] = { x = b.x, y = b.y, r = 5, left = 2 }
  events[#events + 1] = { type = "pile", x = b.x, y = b.y }
end

local function goOff(s, b, events)
  if b.kind == "dirt" then
    dirtLands(s, b, events)
  else
    M.blast(s, b.x, b.y, b.kind, b.owner, events)
  end
end

--- A cluster comes apart at the top of its flight, into a fan of small bombs.
local function splitShell(b, out)
  local w = WEAPONS.cluster
  for i = 1, w.count do
    local fan = (i - (w.count + 1) / 2) * w.spread
    out[#out + 1] = { kind = "cluster", owner = b.owner, x = b.x, y = b.y, vx = b.vx + fan, vy = b.vy, age = b.age }
  end
end

--- A tunneller going straight on through whatever's there, opening it up as it goes, until it runs out of push.
local function bore(s, b, out, events)
  b.x, b.y = b.x + b.vx, b.y + b.vy
  b.dug = b.dug + M.DIG_SPEED
  M.carve(s, b.x, b.y, M.DIG_BORE)
  if b.dug >= M.DIG_MOST or tankAt(s, b) or gone(b) or b.y >= BEDROCK then
    goOff(s, b, events)
  else
    out[#out + 1] = b
  end
end

--- A tunneller meets the ground, and turns its speed into a steady dig along the way it was going.
local function startBoring(b)
  local speed = sqrt(b.vx * b.vx + b.vy * b.vy)
  b.vx, b.vy = b.vx / speed * M.DIG_SPEED, b.vy / speed * M.DIG_SPEED
  b.boring, b.dug = true, 0
end

--- One tick of one shell. Whatever is still flying afterwards goes on out.
local function stepShell(s, b, out, events)
  b.age = b.age + 1
  if b.boring then
    bore(s, b, out, events)
  elseif b.splits and b.vy >= 0 then
    splitShell(b, out)
  elseif not fly(s, b, s.wind, meetsAnything) then
    out[#out + 1] = b
  elseif not gone(b) then
    if b.kind == "tunneller" and not tankAt(s, b) then
      startBoring(b)
      out[#out + 1] = b
    else
      goOff(s, b, events)
    end
  end
end

local function stepShells(s, events)
  local out = {}
  for _, b in ipairs(s.shells) do stepShell(s, b, out, events) end
  s.shells = out
end

-- ---------------------------------------------------------------- tanks

--- The next weapon a tank carries after this one, going round: plain shells are always there.
local function nextWeapon(t, from, step)
  local at = 1
  for i, kind in ipairs(M.ORDER) do
    if kind == from then at = i end
  end
  for n = 1, #M.ORDER do
    local kind = M.ORDER[(at - 1 + n * step) % #M.ORDER + 1]
    if kind == "shell" or (t.ammo[kind] or 0) > 0 then return kind end
  end
  return "shell"
end

--- Fire what's loaded. When a weapon's last round goes, plain shells are loaded again.
local function fire(s, t, player, events)
  local kind = t.weapon
  if kind ~= "shell" and (t.ammo[kind] or 0) <= 0 then kind = "shell" end
  local shot = M.launch(t, player)
  s.shells[#s.shells + 1] = {
    kind = kind, owner = player, x = shot.x, y = shot.y, vx = shot.vx, vy = shot.vy, age = 0,
    splits = WEAPONS[kind].count and true or nil,
  }
  if kind ~= "shell" then
    t.ammo[kind] = t.ammo[kind] - 1
    if t.ammo[kind] <= 0 then t.weapon = "shell" end
  end
  events[#events + 1] = { type = "fire", player = player, kind = kind }
end

--- A buried tank can't shoot out: it blows the dirt off itself instead, and that's its turn.
local function digOut(s, t, player, events)
  M.carve(s, t.x, t.y - DIG_OUT, DIG_OUT)
  events[#events + 1] = { type = "dig", player = player }
end

--- One tick of driving, paid for in fuel. A slope too steep or the other tank stops it dead, and a drop it goes over.
local function drive(s, t, other, player, events)
  if t.drive == 0 then return end
  if t.buried or t.fuel <= 0 then
    if t.fuel <= 0 then events[#events + 1] = { type = "noFuel", player = player } end
    t.drive = 0
    return
  end
  local dir = t.drive > 0 and 1 or -1
  t.drive = t.drive - dir
  local x = clamp(t.x + dir * min(SPEED, t.fuel), TANK_HALF, WIDTH - TANK_HALF)
  if abs(x - other.x) < TANK_HALF * 2 + 2 then
    t.drive = 0
    return
  end
  local rest = M.restY(s, x)
  if t.y - rest > M.MAX_RISE then
    t.drive, t.blocked = 0, true
    events[#events + 1] = { type = "stuck", player = player }
    return
  end
  t.fuel = max(0, t.fuel - abs(x - t.x))
  t.x, t.blocked = x, false
  if rest < t.y then t.y = rest end
end

--- A tank drops to the ground under it. Dirt on top of it, it climbs through if there's little enough, or it's buried.
local function settle(s, t)
  local rest = M.restY(s, t.x)
  local over = t.y - rest
  t.buried = over > M.BURY
  if over < 0 then
    t.y = min(rest, t.y + TANK_FALL)
  elseif over > 0 and not t.buried then
    t.y = max(rest, t.y - SHAKE)
  end
end

local function settled(s, t)
  return t.buried or t.hp <= 0 or abs(t.y - M.restY(s, t.x)) < 0.01
end

--- A tank on a landed crate takes what's in it, on top of what it has.
local function pickUp(s, events)
  local kept = {}
  for _, crate in ipairs(s.crates) do
    local taker
    for i, t in ipairs(s.tanks) do
      if not taker and t.hp > 0 and crate.landed and abs(crate.x - t.x) <= M.CRATE_REACH and abs(crate.y - t.y) <= M.CRATE_REACH then
        taker = i
      end
    end
    if taker then
      local t = s.tanks[taker]
      t.ammo[crate.kind] = (t.ammo[crate.kind] or 0) + WEAPONS[crate.kind].ammo
      events[#events + 1] = { type = "pickup", player = taker, kind = crate.kind }
    else
      kept[#kept + 1] = crate
    end
  end
  s.crates = kept
end

local function stepCrates(s, events)
  for _, crate in ipairs(s.crates) do
    local ground = M.groundAt(s, crate.x)
    if crate.y < ground then
      crate.y = min(ground, crate.y + (crate.landed and CRATE_DROP or CRATE_FALL))
      if crate.y >= ground and not crate.landed then
        crate.landed = true
        events[#events + 1] = { type = "crateDown" }
      end
    else
      crate.y = ground
    end
  end
  pickUp(s, events)
end

--- Sometimes, between turns, a crate comes down on a parachute, never right on a tank.
local function dropCrate(s, rng, events)
  if s.turns < 2 or #s.crates >= M.CRATE_MOST or rng() >= M.CRATE_CHANCE then return end
  local x = 20 + rng() * (WIDTH - 40)
  for _, t in ipairs(s.tanks) do
    if abs(t.x - x) < 24 then return end
  end
  s.crates[#s.crates + 1] = { x = x, y = -6, kind = M.LOOT[rng(#M.LOOT)], landed = false }
  events[#events + 1] = { type = "crate" }
end

-- ---------------------------------------------------------------- turns

--- The wind for a turn, in whole points, mostly light and now and then strong.
local function newWind(s, rng)
  s.windLevel = clamp(round((rng() + rng() - 1) * M.WIND_MOST * 1.3), -M.WIND_MOST, M.WIND_MOST)
  s.wind = s.windLevel * M.WIND_STEP
end

--- The tank whose turn it is gets its fuel and the clock, under a new wind.
local function beginTurn(s, rng, events)
  s.turns, s.turnNo = s.turns + 1, s.turnNo + 1
  newWind(s, rng)
  local t = s.tanks[s.turn]
  t.fuel, t.drive, t.aimed, t.wantFire, t.blocked = M.FUEL, 0, false, false, false
  s.phase, s.timer, s.turnClock = "aim", M.TURN_TICKS, 0
  dropCrate(s, rng, events)
  events[#events + 1] = { type = "turn", player = s.turn, wind = s.windLevel }
end

--- The shot goes, or the buried tank digs: either way the turn now plays out.
local function shoot(s, t, player, events)
  t.wantFire, t.drive = false, 0
  if t.buried then digOut(s, t, player, events) else fire(s, t, player, events) end
  s.phase, s.flyClock, s.after = "fly", 0, AFTER
end

--- Nothing in the air, no dirt on its way down, and the tanks at rest.
local function still(s)
  if #s.shells > 0 or #s.slabs > 0 or #s.slides > 0 then return false end
  for _, t in ipairs(s.tanks) do
    if not settled(s, t) then return false end
  end
  return true
end

-- ---------------------------------------------------------------- rounds

local function newTank(s, x)
  return {
    x = x, y = M.restY(s, x), hp = M.HP, weapon = "shell", ammo = {}, angle = M.ANGLE, power = M.POWER,
    fuel = M.FUEL, drive = 0, buried = false, blocked = false, aimed = false, wantFire = false,
  }
end

local function newRound(s, rng)
  local x1, x2 = SPAWN_NEAR + rng() * SPAWN_RANGE, WIDTH - SPAWN_NEAR - rng() * SPAWN_RANGE
  s.round = s.round + 1
  s.ground, s.bare = hills(rng, x1, x2), {}
  s.rev = s.rev + 1
  s.shells, s.slabs, s.slides, s.crates, s.blasts, s.pops = {}, {}, {}, {}, {}, {}
  s.tanks = { newTank(s, x1), newTank(s, x2) }
  -- who goes first takes turns round by round
  s.first = s.first and 3 - s.first or rng(2)
  s.turn = s.first
  s.windLevel, s.wind = 0, 0
  s.phase, s.hold, s.pause, s.timer, s.turns, s.sudden, s.result = "hold", HOLD, 0, M.TURN_TICKS, 0, false, nil
end

--- A tank with nothing left goes up, and the round goes to whoever's still there. Both at once and nobody scores.
--- Returns true when the round is over.
local function checkRound(s, events)
  local a, b = s.tanks[1], s.tanks[2]
  if a.hp > 0 and b.hp > 0 then return false end
  local winner = 0
  if b.hp > 0 then winner = 2 elseif a.hp > 0 then winner = 1 end
  for i, t in ipairs(s.tanks) do
    if t.hp <= 0 then
      s.blasts[#s.blasts + 1] = { x = t.x, y = t.y - TANK_H / 2, r = 16, left = BLAST_TICKS * 2 }
      events[#events + 1] = { type = "kill", player = i }
    end
  end
  s.drawn = winner == 0 and s.drawn + 1 or 0
  if winner > 0 then s.score[winner] = s.score[winner] + 1 end
  s.shells, s.phase, s.pause, s.result = {}, "pause", PAUSE, { winner = winner }
  events[#events + 1] = { type = "round", winner = winner, round = s.round }
  return true
end

--- A turn is over: a long round costs both tanks, then either the round is decided or the other tank goes.
local function endTurn(s, rng, events)
  if s.turns >= M.SUDDEN_TURNS then
    if not s.sudden then
      s.sudden = true
      events[#events + 1] = { type = "sudden" }
    end
    for i, t in ipairs(s.tanks) do
      t.hp = max(0, t.hp - M.SUDDEN_HP)
      s.pops[#s.pops + 1] = { player = i, text = "-" .. M.SUDDEN_HP, left = POP_TICKS }
    end
  end
  if checkRound(s, events) then return end
  s.turn = 3 - s.turn
  beginTurn(s, rng, events)
end

--- The match is over once someone has their rounds, or the level rounds have gone on too long.
local function matchWinner(s)
  if s.score[1] >= M.ROUNDS_TO_WIN then return 1 end
  if s.score[2] >= M.ROUNDS_TO_WIN then return 2 end
  if s.drawn < M.DRAWS_MOST then return nil end
  if s.score[1] == s.score[2] then return 0 end
  return s.score[1] > s.score[2] and 1 or 2
end

local function endPause(s, rng, events)
  local winner = matchWinner(s)
  if winner then
    s.over, s.winner = true, winner
    events[#events + 1] = { type = "match", winner = winner }
  else
    newRound(s, rng)
    events[#events + 1] = { type = "newRound", round = s.round }
  end
end

local function ageMarks(s)
  local kept = {}
  for _, blast in ipairs(s.blasts) do
    blast.left = blast.left - 1
    if blast.left > 0 then kept[#kept + 1] = blast end
  end
  s.blasts = kept
  kept = {}
  for _, pop in ipairs(s.pops) do
    pop.left = pop.left - 1
    if pop.left > 0 then kept[#kept + 1] = pop end
  end
  s.pops = kept
end

--- The ground and the tanks on it come to rest, whatever else is going on.
local function settleAll(s, events)
  settleDirt(s)
  for _, t in ipairs(s.tanks) do settle(s, t) end
  stepCrates(s, events)
end

--- A fresh match. opts.rng is the only source of chance.
function M.new(opts)
  local s = {
    over = false, winner = nil, score = { 0, 0 }, round = 0, rev = 0, clock = 0, drawn = 0, turnNo = 0, tanks = {},
  }
  newRound(s, opts.rng)
  return s
end

--- A player's action, which only counts on their own turn while they aim:
---   { kind = "aim", x, y }        point the barrel at a world spot, harder the further off it is
---   { kind = "angle", by }        { kind = "power", by }     nudge either
---   { kind = "set", angle, power } both at once (the computer's way)
---   { kind = "weapon", step = 1 or -1 } or { kind = "weapon", id }   the next weapon carried, or that one
---   { kind = "drive", dir = 1 or -1 }   across the world, not across the wall, for as long as the fuel lasts
---   { kind = "fire" }
function M.input(s, player, action)
  if s.over or s.phase ~= "aim" or player ~= s.turn or type(action) ~= "table" then return end
  local t = s.tanks[player]
  local kind = action.kind
  local num = function(v) return type(v) == "number" and v == v and abs(v) < 1e6 end
  if kind == "aim" and num(action.x) and num(action.y) then
    t.angle, t.power = M.aimAt(t, player, action.x, action.y)
    t.aimed = true
  elseif kind == "angle" and num(action.by) then
    t.angle, t.aimed = clamp(round(t.angle + action.by), 0, 180), true
  elseif kind == "power" and num(action.by) then
    t.power, t.aimed = clamp(round(t.power + action.by), 1, 100), true
  elseif kind == "set" and num(action.angle) and num(action.power) then
    t.angle, t.power, t.aimed = clamp(round(action.angle), 0, 180), clamp(round(action.power), 1, 100), true
  elseif kind == "weapon" then
    if WEAPONS[action.id] and (action.id == "shell" or (t.ammo[action.id] or 0) > 0) then
      t.weapon = action.id
    elseif action.step == 1 or action.step == -1 then
      t.weapon = nextWeapon(t, t.weapon, action.step)
    end
  elseif kind == "drive" and (action.dir == 1 or action.dir == -1) then
    if t.drive ~= 0 and (t.drive > 0) ~= (action.dir > 0) then
      t.drive = 0 -- a tap the other way stops it
    else
      t.drive = clamp(t.drive + action.dir * M.DRIVE_TICKS, -M.DRIVE_MOST, M.DRIVE_MOST)
    end
  elseif kind == "fire" then
    t.wantFire = true
  end
end

--- One tick of a turn being aimed: the tank drives, the clock runs, and FIRE or the end of the clock sends the shot.
local function aiming(s, events)
  local p = s.turn
  local t = s.tanks[p]
  s.turnClock = s.turnClock + 1
  drive(s, t, s.tanks[3 - p], p, events)
  settleAll(s, events)
  if t.wantFire then
    shoot(s, t, p, events)
    return
  end
  s.timer = s.timer - 1
  if s.timer == M.HURRY then events[#events + 1] = { type = "hurry", player = p } end
  if s.timer > 0 then return end
  -- time's up: a shot that was lined up goes, and a turn nobody touched goes by
  events[#events + 1] = { type = "timeout", player = p }
  if t.aimed then
    shoot(s, t, p, events)
  else
    t.drive = 0
    events[#events + 1] = { type = "pass", player = p }
    s.phase, s.flyClock, s.after = "fly", 0, AFTER
  end
end

--- One tick of a shot playing out. Once everything is still, a moment to see it, then the turn ends.
local function flying(s, rng, events)
  stepShells(s, events)
  settleAll(s, events)
  s.flyClock = s.flyClock + 1
  if s.flyClock > FLY_MOST then s.shells = {} end
  if not still(s) then return end
  s.after = s.after - 1
  if s.after <= 0 then endTurn(s, rng, events) end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  ageMarks(s)
  if s.phase == "pause" then
    settleAll(s, events)
    s.pause = s.pause - 1
    if s.pause <= 0 then endPause(s, rng, events) end
  elseif s.phase == "hold" then
    settleAll(s, events)
    s.hold = s.hold - 1
    if s.hold <= 0 then beginTurn(s, rng, events) end
  elseif s.phase == "aim" then
    aiming(s, events)
  elseif s.phase == "fly" then
    flying(s, rng, events)
  end
  return events
end

--- The part of a match that tests read through the shell.
function M.snapshot(s)
  local tanks = {}
  for i, t in ipairs(s.tanks) do
    local ammo = {}
    for k, v in pairs(t.ammo) do ammo[k] = v end
    tanks[i] = {
      x = t.x, y = t.y, hp = t.hp, angle = t.angle, power = t.power, weapon = t.weapon, ammo = ammo, fuel = t.fuel,
      drive = t.drive, buried = t.buried,
    }
  end
  return {
    round = s.round, phase = s.phase, turn = s.turn, turns = s.turns, turnNo = s.turnNo, timer = s.timer, wind = s.windLevel,
    shells = #s.shells, crates = #s.crates, tanks = tanks,
  }
end

-- ---------------------------------------------------------------- the computer

--- Where a shot at this angle and power comes down, in the wind as the computer reads it, and how far it is from a tank.
local function trial(s, me, player, angle, power, wind, target)
  local _, x, y, hit = M.path(s, M.launch(me, player, angle, power), wind, player)
  local gap = hit == 3 - player and 0 or hullGap(target, x, y)
  return x, y, gap
end

--- The power at this angle that brings a shot down nearest the other tank: short means more, long means less.
local function solvePower(s, me, player, foe, angle, wind)
  local face = facing(player)
  local goal = (foe.x - me.x) * face
  local lo, hi = 1, 100
  local best
  for _ = 1, BOT_HALVES do
    local power = (lo + hi) / 2
    local x, y, gap = trial(s, me, player, angle, power, wind, foe)
    if not best or gap < best.gap then best = { angle = angle, power = power, gap = gap, x = x, y = y } end
    if gap == 0 then break end
    if (x - me.x) * face < goal then lo = power else hi = power end
  end
  return best
end

--- Which weapon it fires: the biggest it has that won't hurt itself, and dirt now and then to bury the other tank.
local function chooseWeapon(me, foe, rng)
  local gap = abs(foe.x - me.x)
  local has = function(kind) return (me.ammo[kind] or 0) > 0 end
  if has("nuke") and gap > WEAPONS.nuke.radius * M.REACH + TANK_HALF * 2 + 8 then return "nuke" end
  if has("big") then return "big" end
  if has("dirt") and not foe.buried and rng() < 0.5 then return "dirt" end
  if has("cluster") then return "cluster" end
  if has("tunneller") then return "tunneller" end
  return "shell"
end

--- A landed crate the fuel can reach, short of the other tank: the x to drive to.
local function crateInReach(s, me, foe)
  local best
  for _, crate in ipairs(s.crates) do
    local gap = crate.x - me.x
    local between = (crate.x - me.x) * (foe.x - me.x) > 0 and abs(crate.x - me.x) > abs(foe.x - me.x) - TANK_HALF * 3
    if crate.landed and not between and abs(gap) <= me.fuel - 2 and (not best or abs(gap) < abs(best - me.x)) then
      best = crate.x
    end
  end
  return best
end

local function scatter(rng) return rng() + rng() - 1 end

local stages = {}

function stages.start(s, me, foe, player, rng, mem)
  if me.buried then return { kind = "fire" } end
  local goal = crateInReach(s, me, foe)
  if goal then
    mem.stage, mem.goal, mem.tries = "drive", goal, 0
  else
    mem.stage = "weapon"
  end
  return nil
end

function stages.drive(s, me, _, _, _, mem)
  if me.drive ~= 0 then return nil end
  if abs(me.x - mem.goal) <= M.CRATE_REACH - 3 or me.fuel <= 0 or me.blocked or mem.tries >= 8 then
    mem.stage = "weapon"
    return nil
  end
  mem.tries = mem.tries + 1
  return { kind = "drive", dir = mem.goal > me.x and 1 or -1 }
end

function stages.weapon(s, me, foe, _, rng, mem, skill)
  local kind = chooseWeapon(me, foe, rng)
  mem.stage, mem.angle, mem.best = "search", BOT_ANGLES[1], nil
  mem.read = s.wind * (1 + scatter(rng) * skill.wind)
  if kind ~= me.weapon then return { kind = "weapon", id = kind } end
  return nil
end

--- One angle a tick: the barrel sweeps while it looks for the best shot, and it won't pick one that lands on itself.
function stages.search(s, me, foe, player, rng, mem, skill)
  local angle = mem.angle
  local try = solvePower(s, me, player, foe, angle, mem.read)
  local w = WEAPONS[me.weapon]
  if w.damage > 0 and hullGap(me, try.x, try.y) < w.radius * M.REACH + 2 then try.gap = try.gap + 1000 end
  if not mem.best or try.gap < mem.best.gap then mem.best = try end
  mem.angle = angle + BOT_ANGLES[3]
  if mem.angle > BOT_ANGLES[2] then
    -- a person's error: wide at first, closing in while the target stays put
    local learn = me.learn
    if not learn or abs(learn.x - foe.x) > BOT_MOVED then
      learn = { x = foe.x, shots = 0 }
      me.learn = learn
    end
    local err = max(BOT_STEADIEST, BOT_LEARN ^ learn.shots)
    learn.shots = learn.shots + 1
    local best = mem.best
    mem.stage, mem.at = "fire", s.clock + 4 + rng(4)
    return {
      kind = "set",
      angle = clamp(best.angle + scatter(rng) * skill.angle * err * 2, 0, 180),
      power = clamp(best.power + scatter(rng) * skill.power * err * 2, 1, 100),
    }
  end
  return { kind = "set", angle = angle, power = try.power }
end

function stages.fire()
  return { kind = "fire" }
end

--- A computer player. On its turn it waits a moment, maybe drives for a crate, picks a weapon, tries shots at every angle in
--- the wind as it reads it, and fires the best with some error, less on higher levels.
function M.bot(s, rng, player, level)
  if s.over or s.phase ~= "aim" or s.turn ~= player then return nil end
  local me, foe = s.tanks[player], s.tanks[3 - player]
  local skill = M.SKILL[level] or M.SKILL.normal
  local mem = me.bot
  if not mem or mem.turn ~= s.turnNo then
    mem = { turn = s.turnNo, stage = "start", at = s.clock + skill.think + rng(6) }
    me.bot = mem
  end
  if s.clock < mem.at then return nil end
  return stages[mem.stage](s, me, foe, player, rng, mem, skill)
end

return M
