-- games/moag/rules.lua
-- MOAG: two tanks shelling each other across ground that doesn't stay put. Pure: no screen, sound or files.
-- See "Classics" in games/README.md for the idea; a versus game has a player on every call.
-- Everything lives in world units, the same size across and down. A monitor cell is 2 units wide and 3 tall, and y grows
-- downward. The ground is a height for each column of cells. A hole cut under a column leaves what was above it as a slab,
-- which falls and lands, so an overhang can't last and a tank can be sheltered or buried by what comes down.
-- Player 1's tank starts on the left of the world and player 2's on the right. Only the plugin knows about mirrors.

local M = {
  WIDTH = 240, HEIGHT = 198, CELL_W = 2, CELL_H = 3, COLS = 120,
  ROUNDS_TO_WIN = 5, HP = 100,
  GRAVITY = 0.35,
  WIND_MOST = 0.07,
  FLIGHT_BASE = 12, FLIGHT_PACE = 8, FLIGHT_MOST = 40, -- ticks in the air: the base, then one more for each so many units
  RELOAD = 20,
  PREVIEW = 12,               -- ticks the arc stays up after a tap
  TANK_HALF = 7, TANK_H = 9,  -- from the centre to the side, and from the tracks to the roof
  TURRET_H = 7, BARREL = 6,
  DRIVE_TICKS = 8, DRIVE_MOST = 24, SPEED = 1.5,
  MAX_RISE = 1.3,             -- the steepest step a tank climbs from one column to the next
  REPOSE = 1.1,               -- the steepest loose dirt lies: gentle enough to drive out of a crater
  DRIVE_REACH = 26,           -- how far either side of a tank a tap means drive, not aim
  BURY = 9,                   -- this much dirt over the tracks and the tank can't shake it off
  REACH = 1.5,                -- a blast hurts out to this many times the size of its crater
  BEDROCK = 192,              -- nothing digs below this
  SUDDEN = 600,               -- ticks into a round when both tanks start to fail
  SUDDEN_EVERY = 3,           -- ticks for each hit point lost after that
  DIG_MOST = 70, DIG_SPEED = 4, DIG_BORE = 5,
  CRATE_MOST = 2,
  DRAWS_MOST = 3,             -- this many level rounds in a row and the match stops
}

-- What each weapon does. radius is the crater, damage is what a direct hit costs, ammo is how many shots a crate holds.
M.WEAPONS = {
  shell = { name = "SHELL", radius = 11, damage = 34, reload = 20 },
  big = { name = "BIG SHELL", radius = 18, damage = 48, reload = 26, ammo = 2 },
  cluster = { name = "CLUSTER", radius = 8, damage = 18, reload = 24, ammo = 2, count = 5, spread = 1.1 },
  dirt = { name = "DIRT BOMB", radius = 22, damage = 0, reload = 20, ammo = 2 },
  tunneller = { name = "TUNNELLER", radius = 10, damage = 36, reload = 24, ammo = 2 },
  nuke = { name = "NUKE", radius = 36, damage = 85, reload = 40, ammo = 1 },
}
-- What a crate can hold. The nuke is rarer than the rest.
M.LOOT = { "big", "cluster", "dirt", "tunneller", "big", "cluster", "dirt", "tunneller", "nuke" }

local WIDTH, HEIGHT, CELL_W, COLS = M.WIDTH, M.HEIGHT, M.CELL_W, M.COLS
local GRAVITY, BEDROCK, WEAPONS = M.GRAVITY, M.BEDROCK, M.WEAPONS
local TANK_HALF, TANK_H, SPEED = M.TANK_HALF, M.TANK_H, M.SPEED
local abs, ceil, floor, max, min, pi, sin, sqrt = math.abs, math.ceil, math.floor, math.max, math.min, math.pi, math.sin, math.sqrt

local HOLD = 15             -- ticks a new round waits, for a look at the ground
local PAUSE = 30            -- ticks the result of a round stays up
local STRIDE = 1.5          -- the furthest a shell goes between looks at what it's hitting
local ARM = 4               -- ticks before a shell can hit the tank that fired it
local OUT = 60              -- how far past the sides a shell can go and still come back
local PATH_MOST = 90        -- the most ticks of flight a preview follows
local PATH_DOT = 2          -- ticks between the dots of a preview
local FOOT = 2              -- columns either side of the centre that a tank rests on
local TOP_MOST = 6          -- dirt piles no higher than this
local TANK_FALL, SLAB_FALL = 3, 5
local SHAKE = 1             -- how fast a tank climbs out of dirt it can shake off
local CRATE_FALL, CRATE_DROP = 1.2, 3
local CRATE_REACH = 10
local CRATE_MIN, CRATE_MAX = 50, 110
local WIND_MIN, WIND_MAX = 60, 120
local WIND_SHIFT = 0.03
local SLIDE_TICKS, SLIDE_PASSES, SLIDE_MARGIN = 30, 4, 8
local DIG_OUT = 12          -- the size of the hole a buried tank blows above itself
local BLAST_TICKS = 4
-- the ground
local HILL_LEVEL, HILL_RANGE = 128, 22
local HILL_MIDDLE = 44      -- how much higher the middle of the field stands than the ends
local HILL_TOP, HILL_LOW = 62, 180
local JAG = 11              -- the most a stretch of ground strays from the smooth hills
local SPAWN_NEAR, SPAWN_RANGE = 22, 32
local PAD = 6               -- columns either side of a tank that start out level
-- the bot
local BOT_EVERY = 3         -- least ticks between its taps, and it adds a few more: about what a person can do
local BOT_LOBS, BOT_LOB_STEP = 5, 26 -- how many ever higher arcs it tries, and how much higher each one is
local BOT_TRIES = 4         -- how many times it corrects an arc
local BOT_SCATTER = 26      -- how far it can miss on a first shot
local BOT_LEARN = 0.62      -- what each shot at a target that stayed put leaves of that
local BOT_SETTLED = 3       -- the steadiest it gets, however long a target sits still
local BOT_WIND_READ = 0.35  -- how far out its reading of the wind can be, as a share
local BOT_MOVED = 12        -- a target that shifts this far has to be found again
local BOT_DODGE = 0.55      -- the chance it spots a shell coming and moves
local BOT_DANGER = 24       -- how near a landing has to be to worry it
local BOT_CRATE_RANGE = 110 -- how far it will go for a crate
local BOT_FAR, BOT_NEAR = 130, 56 -- it closes in past the first and backs off inside the second
local BOT_WANDER = 0.25     -- the chance it shifts anyway, to be harder to hit
local BOT_GIVE_UP = 40      -- ticks it won't drive for after meeting a slope it can't climb

local function clamp(v, low, high)
  return min(high, max(low, v))
end

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
    local y = level + sin(at * 2 * pi * countA + waveA) * 16 + sin(at * 2 * pi * countB + waveB) * 8 - rise * rise * middle
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

--- Ticks in the air for a shot this long: a longer shot hangs longer, up to a limit, in whole ticks.
function M.flightTicks(dist)
  return min(M.FLIGHT_MOST, M.FLIGHT_BASE + floor(dist / M.FLIGHT_PACE))
end

--- The speed that takes a shell from one point to another in this many ticks, with no wind.
local function solve(x, y, tx, ty, ticks)
  return (tx - x) / ticks, (ty - y) / ticks - GRAVITY * (ticks + 1) / 2
end

--- The shot a tank makes at a spot. The barrel lies along the launch, and the shell leaves from its end.
function M.aimFrom(t, tx, ty)
  local px, py = t.x, t.y - M.TURRET_H
  local ticks = M.flightTicks(sqrt((tx - px) ^ 2 + (ty - py) ^ 2))
  local vx, vy = solve(px, py, tx, ty, ticks)
  local speed = sqrt(vx * vx + vy * vy)
  local ux, uy = 0, -1
  if speed > 0 then ux, uy = vx / speed, vy / speed end
  local x, y = px + ux * M.BARREL, py + uy * M.BARREL
  vx, vy = solve(x, y, tx, ty, ticks)
  return { x = x, y = y, vx = vx, vy = vy, ticks = ticks, ux = ux, uy = uy }
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

--- Where a shot goes, as the wind stands: dots along the way, and the spot it meets the ground.
function M.path(s, x, y, vx, vy, wind)
  local b = { x = x, y = y, vx = vx, vy = vy }
  local dots = {}
  for tick = 1, PATH_MOST do
    if fly(s, b, wind, inGround) then break end
    if tick % PATH_DOT == 0 then dots[#dots + 1] = { x = b.x, y = b.y } end
  end
  return dots, b.x, b.y
end

-- ---------------------------------------------------------------- blasts

--- How far a point is from a tank's hull. Inside it, that's nothing.
local function hullGap(t, x, y)
  local dx = max(abs(x - t.x) - TANK_HALF, 0)
  local dy = max(t.y - TANK_H - y, y - t.y, 0)
  return sqrt(dx * dx + dy * dy)
end
M.hullGap = hullGap

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
    if cost > 0 then
      t.hp = max(0, t.hp - cost)
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
  local w = WEAPONS.dirt
  M.pile(s, b.x, w.radius)
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

--- The tank a shell has hit, if any. Its own tank is safe from it for the first moments of the flight.
local function tankAt(s, b)
  for i, t in ipairs(s.tanks) do
    if (i ~= b.owner or b.age > ARM) and hullGap(t, b.x, b.y) == 0 then return t end
  end
  return nil
end

local function meetsAnything(s, b)
  return tankAt(s, b) ~= nil or inGround(s, b)
end

--- A cluster comes apart halfway, into a fan of small bombs.
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
  elseif b.splitAt and b.age >= b.splitAt then
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

--- Fire what's loaded. The last round of a crate falls back to plain shells.
local function fire(s, t, a, player, events)
  local kind = t.weapon
  local w = WEAPONS[kind]
  s.shells[#s.shells + 1] = {
    kind = kind, owner = player, x = a.x, y = a.y, vx = a.vx, vy = a.vy, age = 0,
    splitAt = w.count and floor(a.ticks / 2) or nil,
  }
  t.reload, t.reloadFull = w.reload, w.reload
  if kind ~= "shell" then
    t.ammo = t.ammo - 1
    if t.ammo <= 0 then t.weapon, t.ammo = "shell", 0 end
  end
  events[#events + 1] = { type = "fire", player = player, kind = kind }
end

--- A buried tank can't shoot out: it blows the dirt off itself instead, and that takes the same reload.
local function digOut(s, t, player, events)
  M.carve(s, t.x, t.y - DIG_OUT, DIG_OUT)
  t.reload, t.reloadFull = M.RELOAD, M.RELOAD
  events[#events + 1] = { type = "dig", player = player }
end

--- Act on the latest tap at the sky. A tap while reloading is only a sighting: it shows the arc and fires nothing.
local function takeAim(s, t, player, events)
  local tap = t.tap
  if not tap then return end
  t.tap = nil
  if t.buried then
    if t.reload == 0 then digOut(s, t, player, events) end
    return
  end
  local a = M.aimFrom(t, tap.x, tap.y)
  local dots, landX, landY = M.path(s, a.x, a.y, a.vx, a.vy, s.wind)
  t.ux, t.uy = a.ux, a.uy
  t.aim = { x = tap.x, y = tap.y, dots = dots, landX = landX, landY = landY, left = M.PREVIEW, fired = t.reload == 0 }
  if t.reload > 0 then
    events[#events + 1] = { type = "sight", player = player }
  else
    fire(s, t, a, player, events)
  end
end

--- One tick of driving. A slope too steep or the other tank stops it dead, and a drop it simply goes over.
local function drive(s, t, other, events)
  if t.drive == 0 or t.buried then return end
  local dir = t.drive > 0 and 1 or -1
  t.drive = t.drive - dir
  local x = clamp(t.x + dir * SPEED, TANK_HALF, WIDTH - TANK_HALF)
  if abs(x - other.x) < TANK_HALF * 2 + 2 then
    t.drive = 0
    return
  end
  local rest = M.restY(s, x)
  if t.y - rest > M.MAX_RISE then
    t.drive, t.blocked = 0, true
    events[#events + 1] = { type = "stuck", player = t.seat }
    return
  end
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

local function pickUp(s, t, player, events)
  local kept = {}
  for _, crate in ipairs(s.crates) do
    if crate.landed and abs(crate.x - t.x) <= CRATE_REACH and abs(crate.y - t.y) <= CRATE_REACH then
      if t.weapon == crate.kind then
        t.ammo = t.ammo + WEAPONS[crate.kind].ammo
      else
        t.weapon, t.ammo = crate.kind, WEAPONS[crate.kind].ammo
      end
      events[#events + 1] = { type = "pickup", player = player, kind = crate.kind }
    else
      kept[#kept + 1] = crate
    end
  end
  s.crates = kept
end

local function stepCrates(s, rng, events)
  s.crateIn = s.crateIn - 1
  if s.crateIn <= 0 then
    s.crateIn = CRATE_MIN + rng(CRATE_MAX - CRATE_MIN)
    if #s.crates < M.CRATE_MOST then
      local kind = M.LOOT[rng(#M.LOOT)]
      s.crates[#s.crates + 1] = { x = 30 + rng() * (WIDTH - 60), y = 0, kind = kind, landed = false }
      events[#events + 1] = { type = "crate" }
    end
  end
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
end

local function stepWind(s, rng)
  s.windIn = s.windIn - 1
  if s.windIn > 0 then return end
  s.windIn = WIND_MIN + rng(WIND_MAX - WIND_MIN)
  s.wind = clamp(s.wind + (rng() - 0.5) * 2 * WIND_SHIFT, -M.WIND_MOST, M.WIND_MOST)
end

--- A round that drags on wears both tanks down, so it always ends.
local function stepSudden(s, events)
  s.roundClock = s.roundClock + 1
  if s.roundClock < M.SUDDEN then return end
  if s.roundClock == M.SUDDEN then
    s.sudden = true
    events[#events + 1] = { type = "sudden" }
  end
  if s.roundClock % M.SUDDEN_EVERY == 0 then
    for _, t in ipairs(s.tanks) do t.hp = max(0, t.hp - 1) end
  end
end

-- ---------------------------------------------------------------- rounds

local function newTank(s, x, seat)
  return {
    seat = seat, x = x, y = M.restY(s, x), hp = M.HP, weapon = "shell", ammo = 0, reload = 0, reloadFull = M.RELOAD, drive = 0,
    ux = seat == 1 and 0.7 or -0.7, uy = -0.7, buried = false, blocked = false,
  }
end

local function newRound(s, rng)
  local x1, x2 = SPAWN_NEAR + rng() * SPAWN_RANGE, WIDTH - SPAWN_NEAR - rng() * SPAWN_RANGE
  s.round = s.round + 1
  s.ground, s.bare = hills(rng, x1, x2), {}
  s.rev = s.rev + 1
  s.shells, s.slabs, s.slides, s.crates, s.blasts = {}, {}, {}, {}, {}
  s.tanks = { newTank(s, x1, 1), newTank(s, x2, 2) }
  s.wind = (rng() - 0.5) * 2 * M.WIND_MOST
  s.windIn = WIND_MIN + rng(WIND_MAX - WIND_MIN)
  s.crateIn = CRATE_MIN + rng(CRATE_MAX - CRATE_MIN)
  s.hold, s.pause, s.roundClock, s.sudden, s.result = HOLD, 0, 0, false, nil
end

--- A tank with nothing left goes up, and the round goes to whoever's still there. Both at once and nobody scores.
local function checkRound(s, events)
  local a, b = s.tanks[1], s.tanks[2]
  if a.hp > 0 and b.hp > 0 then return end
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
  s.shells, s.pause, s.result = {}, PAUSE, { winner = winner }
  events[#events + 1] = { type = "round", winner = winner, round = s.round }
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
  for _, t in ipairs(s.tanks) do
    if t.aim then
      t.aim.left = t.aim.left - 1
      if t.aim.left <= 0 then t.aim = nil end
    end
  end
end

--- Nothing can be done between rounds, but the dirt still comes down.
local function wait(s)
  for _, t in ipairs(s.tanks) do t.tap, t.drive = nil, 0 end
  settleDirt(s)
  for _, t in ipairs(s.tanks) do settle(s, t) end
end

--- A fresh match. opts.rng is the only source of chance.
function M.new(opts)
  local s = {
    over = false, winner = nil, score = { 0, 0 }, round = 0, rev = 0, clock = 0, drawn = 0, tanks = {},
  }
  newRound(s, opts.rng)
  return s
end

--- A player's action: { kind = "aim", x, y } in world units, or { kind = "drive", dir = 1 or -1 }, which is across the
--- world and not across the wall. Aim takes effect on the next step; the latest one wins.
function M.input(s, player, action)
  local t = s.tanks[player]
  if s.over or not t then return end
  if action.kind == "aim" and action.x and action.y then
    t.tap = { x = action.x, y = action.y }
  elseif action.kind == "drive" and (action.dir == 1 or action.dir == -1) then
    if t.drive ~= 0 and (t.drive > 0) ~= (action.dir > 0) then
      t.drive = 0 -- a tap the other way stops it
    else
      t.drive = clamp(t.drive + action.dir * M.DRIVE_TICKS, -M.DRIVE_MOST, M.DRIVE_MOST)
    end
  end
end

--- What a tap at a world spot means: drive if it's beside this player's own tank or below it, otherwise aim.
function M.tapAction(s, player, x, y)
  local t = s.tanks[player]
  local gap = x - t.x
  if abs(gap) <= M.DRIVE_REACH and y >= t.y - TANK_H - 6 then
    return { kind = "drive", dir = gap < 0 and -1 or 1 }
  end
  return { kind = "aim", x = x, y = max(0, y) }
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  ageMarks(s)
  if s.pause > 0 then
    wait(s)
    s.pause = s.pause - 1
    if s.pause == 0 then endPause(s, rng, events) end
    return events
  end
  if s.hold > 0 then
    wait(s)
    s.hold = s.hold - 1
    return events
  end
  for i, t in ipairs(s.tanks) do
    if t.reload > 0 then t.reload = t.reload - 1 end
    takeAim(s, t, i, events)
    drive(s, t, s.tanks[3 - i], events)
  end
  stepShells(s, events)
  settleDirt(s)
  for i, t in ipairs(s.tanks) do
    settle(s, t)
    pickUp(s, t, i, events)
  end
  stepCrates(s, rng, events)
  stepWind(s, rng)
  stepSudden(s, events)
  checkRound(s, events)
  return events
end

--- The part of a match that tests read through the shell.
function M.snapshot(s)
  local tanks = {}
  for i, t in ipairs(s.tanks) do
    tanks[i] = { x = t.x, y = t.y, hp = t.hp, reload = t.reload, weapon = t.weapon, drive = t.drive, buried = t.buried }
  end
  return { round = s.round, hold = s.hold, pause = s.pause, wind = s.wind, shells = #s.shells, crates = #s.crates, tanks = tanks }
end

-- ---------------------------------------------------------------- the bot

--- Where a tap at this spot would come down, in the wind as the bot reads it.
local function landingOf(s, me, x, y, wind)
  local a = M.aimFrom(me, x, y)
  local _, landX, landY = M.path(s, a.x, a.y, a.vx, a.vy, wind)
  return landX, landY
end

--- The tap that comes down nearest a spot: it shoots the sum, flatter first, then higher to get over what's in the way.
local function solveTap(s, me, goalX, goalY, wind)
  local best, bestMiss
  for lob = 0, BOT_LOBS - 1 do
    local x, y = goalX, max(0, goalY - lob * BOT_LOB_STEP)
    for _ = 1, BOT_TRIES do
      local landX, landY = landingOf(s, me, x, y, wind)
      local miss = abs(landX - goalX) + max(0, abs(landY - goalY) - 12)
      if not best or miss < bestMiss then
        best, bestMiss = { x = x, y = y, landX = landX }, miss
      end
      x = x - (landX - goalX)
    end
    if bestMiss < 3 then break end
  end
  return best
end

--- A shot at the other tank, with the error a person makes: wide at first, closing in while the target stays put.
local function botShot(s, me, foe, rng, mem)
  local read = s.wind * (1 + (rng() - 0.5) * 2 * BOT_WIND_READ)
  local goalX = foe.x
  if foe.drive ~= 0 then
    goalX = goalX + clamp(foe.drive, -M.DRIVE_MOST, M.DRIVE_MOST) * SPEED
  end
  if not mem.seenX or abs(mem.seenX - foe.x) > BOT_MOVED then
    mem.seenX, mem.scatter = foe.x, BOT_SCATTER
  end
  local tap = solveTap(s, me, goalX, foe.y - TANK_H / 2, read)
  -- it won't drop anything on itself, unless all it can do is bury the two of them
  local w = WEAPONS[me.weapon]
  if w.damage > 0 and abs(tap.landX - me.x) < w.radius * M.REACH + TANK_HALF then return nil end
  local err = (rng() + rng() - 1) * mem.scatter
  mem.scatter = max(BOT_SETTLED, mem.scatter * BOT_LEARN)
  return { kind = "aim", x = tap.x + err, y = tap.y }
end

--- A shell coming down near this tank, if it has seen one: the way to go to get clear of it.
local function dodgeFrom(s, me, rng)
  for _, b in ipairs(s.shells) do
    if b.owner ~= me.seat and not b.boring then
      local _, landX = M.path(s, b.x, b.y, b.vx, b.vy, s.wind)
      if abs(landX - me.x) < BOT_DANGER and rng() < BOT_DODGE then
        return landX > me.x and -1 or 1
      end
    end
  end
  return nil
end

--- Which way a crate lies, if one is on the ground and near enough to be worth it.
local function crateDir(s, me)
  local best
  for _, crate in ipairs(s.crates) do
    local gap = crate.x - me.x
    if crate.landed and abs(gap) <= BOT_CRATE_RANGE and (not best or abs(gap) < abs(best)) then best = gap end
  end
  if not best then return nil end
  return best < 0 and -1 or 1
end

--- Which way to go next: out of trouble, then to a crate, then to a good range for a fight.
local function botMove(s, me, foe, rng, mem)
  if me.blocked then
    me.blocked = false
    mem.stayUntil = s.clock + BOT_GIVE_UP
  end
  local dodge = dodgeFrom(s, me, rng)
  if dodge then return dodge end
  if s.clock < (mem.stayUntil or 0) or me.drive ~= 0 then return nil end
  local crate = crateDir(s, me)
  if crate then return crate end
  local toward = foe.x > me.x and 1 or -1
  local gap = abs(foe.x - me.x)
  if gap > BOT_FAR then return toward end
  if gap < BOT_NEAR then return -toward end
  if rng() < BOT_WANDER then return rng() < 0.5 and 1 or -1 end
  return nil
end

--- A computer player. It sees what a player sees, and taps at a person's pace.
function M.bot(s, rng, player)
  if s.over or s.hold > 0 or s.pause > 0 then return nil end
  local me, foe = s.tanks[player], s.tanks[3 - player]
  local mem = me.bot
  if not mem then
    mem = { nextAt = 0 }
    me.bot = mem
  end
  if s.clock < mem.nextAt then return nil end
  mem.nextAt = s.clock + BOT_EVERY + rng(4)
  if me.reload == 0 then
    if me.buried then return { kind = "aim", x = me.x, y = 0 } end
    local shot = botShot(s, me, foe, rng, mem)
    if shot then return shot end
  end
  local dir = botMove(s, me, foe, rng, mem)
  if dir then return { kind = "drive", dir = dir } end
  return nil
end

return M
