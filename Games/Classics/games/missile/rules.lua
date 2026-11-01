-- games/missile/rules.lua
-- Missile Command. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The board is measured in monitor cells, x across and y down, with the ground at y = GROUND. A cell is 2 wide by 3 tall
-- on screen, so distance counts ASPECT columns as one row: that keeps blasts round and speeds the same in every direction.

local M = { WIDTH = 118, HEIGHT = 71, GROUND = 65, ASPECT = 1.5 }

local WIDTH, GROUND, ASPECT = M.WIDTH, M.GROUND, M.ASPECT
local BASES = { 18, 59, 100 }
local CITIES = { 29, 39, 49, 69, 79, 89 }

local ROCKETS = 10          -- rockets at each base, every wave
local FLOOR = GROUND - 4    -- the lowest a rocket can be aimed
local HIT_Y = GROUND - 3    -- how low a missile gets before it lands
local SHOT_SPEED = 5        -- rows a rocket climbs each step
local BLAST = 5             -- a blast's widest radius, in rows
local CHAIN_BLAST = 4       -- the same for a blast set off by a kill, one less with each link in a chain
local GROW, HOLD, SHRINK = 6, 4, 6 -- steps a blast spends on each
local LAND_BLAST = 4        -- the flash where a missile lands
local KILL, BOMBER_KILL = 25, 100
local CITY_BONUS, ROCKET_BONUS = 100, 5
local NEW_CITY_EVERY = 10000
local BANNER_STEPS = 30     -- the pause for the wave's result
local START_STEPS = 16      -- the pause before the first wave
local ENDING_STEPS = 12     -- how long the last city burns before the game ends
local BOMBER_SPEED = 0.9
local BOMBER_FROM_WAVE = 3
local MIN_AIM = 10          -- the bot leaves missiles alone until they are this low

M.BLAST = BLAST

--- A distance in rows, the way it looks on screen.
local function distance(dx, dy)
  return math.sqrt((dx / ASPECT) ^ 2 + dy ^ 2)
end

--- The score multiplier for a wave: up by one every second wave, up to 6.
local function multiplier(wave)
  return math.min(6, math.ceil(wave / 2))
end

local function missileSpeed(wave)
  return math.min(3.5, 0.55 + 0.2 * wave)
end

local function salvoSize(wave)
  return math.min(10, 2 + math.ceil(wave / 2))
end

local function salvoGap(wave)
  return math.max(10, 26 - 3 * wave)
end

--- More than thirty rockets can stop for long: this is what makes it a game you lose.
local function waveSize(wave)
  return 12 + 4 * wave
end

local function citiesLeft(s)
  local n = 0
  for _, site in ipairs(s.sites) do
    if site.city and site.alive then n = n + 1 end
  end
  return n
end

--- A base or city at random, a standing one if there is one.
local function pickSite(s, rng)
  local standing = {}
  for _, site in ipairs(s.sites) do
    if site.alive then standing[#standing + 1] = site end
  end
  local list = #standing > 0 and standing or s.sites
  return list[rng(#list)]
end

--- Add a missile heading from x, y to a site.
local function launchFrom(s, x, y, rng, noSplit)
  local site = pickSite(s, rng)
  local dx, dy = site.x - x, HIT_Y - y
  local d = distance(dx, dy)
  local speed = missileSpeed(s.level)
  local missile = {
    fromX = x, fromY = y, x = x, y = y, site = site,
    vx = dx / d * speed, vy = dy / d * speed,
  }
  if not noSplit and s.level >= 2 and rng() < math.min(0.5, 0.1 * s.level) then
    missile.splitAt = 12 + rng(26)
  end
  s.missiles[#s.missiles + 1] = missile
end

local function startWave(s)
  s.budget = waveSize(s.level)
  s.nextSalvo = 1
  s.banner = nil
  for _, site in ipairs(s.sites) do
    if not site.city then site.alive, site.rockets = true, ROCKETS end
  end
end

--- A fresh game. opts.rng is the only source of chance, and nothing here needs it yet.
function M.new()
  local s = {
    score = 0, level = 1, lives = #CITIES, over = false, clock = 0, sites = {}, taps = {},
    missiles = {}, bombers = {}, shots = {}, blasts = {},
    budget = 0, nextSalvo = 0, spare = 0, nextCity = NEW_CITY_EVERY, pause = START_STEPS,
  }
  for _, x in ipairs(BASES) do s.sites[#s.sites + 1] = { x = x, alive = true, rockets = ROCKETS } end
  for _, x in ipairs(CITIES) do s.sites[#s.sites + 1] = { x = x, alive = true, city = true } end
  s.banner = { first = true }
  return s
end

--- A player's input: aim a rocket at a spot. It fires on the next step, and a spot in the ground means just above it.
function M.input(s, action)
  if action.kind ~= "fire" or s.over or s.ending or s.pause > 0 then return end
  s.taps[#s.taps + 1] = {
    x = math.max(0, math.min(WIDTH - 1, action.x)),
    y = math.max(0, math.min(FLOOR, action.y)),
  }
end

--- The closest base with a rocket to a spot, or nil. Ties go to the leftmost.
local function nearestBase(s, x, y)
  local best, bestDistance
  for _, site in ipairs(s.sites) do
    if site.alive and (site.rockets or 0) > 0 then
      local d = distance(site.x - x, GROUND - y)
      if not best or d < bestDistance then best, bestDistance = site, d end
    end
  end
  return best
end

local function fire(s, tap, events)
  local base = nearestBase(s, tap.x, tap.y)
  if not base then
    events[#events + 1] = { type = "empty" }
    return
  end
  base.rockets = base.rockets - 1
  s.shots[#s.shots + 1] = { fromX = base.x, fromY = HIT_Y, x = base.x, y = HIT_Y, toX = tap.x, toY = tap.y }
  events[#events + 1] = { type = "fire" }
end

local function addBlast(s, x, y, peak, chain)
  s.blasts[#s.blasts + 1] = { x = x, y = y, peak = peak, chain = chain, age = 0, r = 0 }
end

--- A bomber crosses the sky, dropping missiles from what is left of the wave.
local function launchBomber(s, rng)
  local fromLeft = rng(2) == 1
  s.bombers[#s.bombers + 1] = {
    x = fromLeft and 0 or WIDTH - 1, y = 7 + rng(14), vx = fromLeft and BOMBER_SPEED or -BOMBER_SPEED,
    nextDrop = 15 + rng(25),
  }
end

local function launchSalvo(s, rng)
  s.nextSalvo = s.nextSalvo - 1
  if s.nextSalvo > 0 or s.budget <= 0 then return end
  s.nextSalvo = salvoGap(s.level)
  for _ = 1, math.min(s.budget, salvoSize(s.level)) do
    launchFrom(s, rng(WIDTH) - 1, 0, rng)
    s.budget = s.budget - 1
  end
  if s.level >= BOMBER_FROM_WAVE and #s.bombers == 0 and s.budget > 0 and rng(3) == 1 then launchBomber(s, rng) end
end

local function moveBombers(s, rng)
  for i = #s.bombers, 1, -1 do
    local b = s.bombers[i]
    b.x = b.x + b.vx
    b.nextDrop = b.nextDrop - 1
    if b.nextDrop <= 0 and s.budget > 0 then
      b.nextDrop = 30 + rng(20)
      s.budget = s.budget - 1
      launchFrom(s, b.x, b.y, rng)
    end
    if b.x < 0 or b.x >= WIDTH then table.remove(s.bombers, i) end
  end
end

--- A missile comes apart into one or two more, out of what is left of the wave. Those don't split again.
local function split(s, m, rng)
  m.splitAt = nil
  for _ = 1, math.min(s.budget, rng(2)) do
    launchFrom(s, m.x, m.y, rng, true)
    s.budget = s.budget - 1
  end
end

local function land(s, m, events)
  addBlast(s, m.x, GROUND - 2, LAND_BLAST, nil)
  s.blasts[#s.blasts].harmless = true
  local site = m.site
  if not site.alive then return end
  site.alive = false
  if site.city then
    s.lives = citiesLeft(s)
    events[#events + 1] = { type = "city" }
  else
    site.rockets = 0
    events[#events + 1] = { type = "base" }
  end
end

local function moveMissiles(s, rng, events)
  for i = #s.missiles, 1, -1 do
    local m = s.missiles[i]
    m.x, m.y = m.x + m.vx, m.y + m.vy
    if m.y >= HIT_Y then
      table.remove(s.missiles, i)
      land(s, m, events)
    elseif m.splitAt and m.y >= m.splitAt then
      split(s, m, rng)
    end
  end
end

local function moveShots(s)
  for i = #s.shots, 1, -1 do
    local shot = s.shots[i]
    local dx, dy = shot.toX - shot.x, shot.toY - shot.y
    local d = distance(dx, dy)
    if d <= SHOT_SPEED then
      table.remove(s.shots, i)
      addBlast(s, shot.toX, shot.toY, BLAST, 0)
    else
      shot.x, shot.y = shot.x + dx / d * SHOT_SPEED, shot.y + dy / d * SHOT_SPEED
    end
  end
end

--- A blast's radius at its age: out to its peak, held there, and back to nothing.
local function radiusAt(b)
  if b.age <= GROW then return b.peak * b.age / GROW end
  if b.age <= GROW + HOLD then return b.peak end
  return b.peak * (GROW + HOLD + SHRINK - b.age) / SHRINK
end

local function growBlasts(s)
  for i = #s.blasts, 1, -1 do
    local b = s.blasts[i]
    b.age = b.age + 1
    b.r = radiusAt(b)
    if b.age >= GROW + HOLD + SHRINK then table.remove(s.blasts, i) end
  end
end

--- Points go on here, so that every 10,000 banks a new city.
local function award(s, points, events)
  s.score = s.score + points
  while s.score >= s.nextCity do
    s.nextCity = s.nextCity + NEW_CITY_EVERY
    s.spare = s.spare + 1
    events[#events + 1] = { type = "bonus" }
  end
end

local function caught(b, thing)
  return distance(thing.x - b.x, thing.y - b.y) <= b.r
end

local function catchIn(s, list, b, points, events)
  for i = #list, 1, -1 do
    local thing = list[i]
    if caught(b, thing) then
      table.remove(list, i)
      award(s, points * multiplier(s.level), events)
      local peak = CHAIN_BLAST - b.chain
      if peak >= 2 then addBlast(s, thing.x, thing.y, peak, b.chain + 1) end
      events[#events + 1] = { type = "kill", chain = b.chain + 1, bomber = points == BOMBER_KILL }
    end
  end
end

--- Anything inside a blast is destroyed, and goes up in a smaller blast of its own that can catch more.
local function catchAll(s, events)
  for i = 1, #s.blasts do
    local b = s.blasts[i]
    if not b.harmless and b.r > 0 then
      catchIn(s, s.missiles, b, KILL, events)
      catchIn(s, s.bombers, b, BOMBER_KILL, events)
    end
  end
end

local function rebuildCity(s, rng)
  local ruins = {}
  for _, site in ipairs(s.sites) do
    if site.city and not site.alive then ruins[#ruins + 1] = site end
  end
  if #ruins == 0 then return false end
  ruins[rng(#ruins)].alive = true
  return true
end

local function rocketsLeft(s)
  local n = 0
  for _, site in ipairs(s.sites) do n = n + (site.rockets or 0) end
  return n
end

--- Pay for what's left, then put back any cities the score has earned.
local function endWave(s, rng, events)
  local mult = multiplier(s.level)
  local cities, rockets = citiesLeft(s), rocketsLeft(s)
  local bonus = (cities * CITY_BONUS + rockets * ROCKET_BONUS) * mult
  award(s, bonus, events)
  local rebuilt = 0
  while s.spare > 0 and rebuildCity(s, rng) do
    s.spare = s.spare - 1
    rebuilt = rebuilt + 1
  end
  s.lives = citiesLeft(s)
  s.banner = { cities = cities, rockets = rockets, bonus = bonus, mult = mult, rebuilt = rebuilt }
  s.pause = BANNER_STEPS
  events[#events + 1] = { type = "wave", bonus = bonus }
end

local function waveDone(s)
  return s.budget == 0 and #s.missiles == 0 and #s.bombers == 0 and #s.shots == 0 and #s.blasts == 0
end

--- With the cities gone, the last blast plays out and the game ends. A city banked at the last moment saves it.
local function countDownEnding(s, events)
  s.ending = s.ending - 1
  if s.ending > 0 then return end
  if s.spare > 0 then
    s.ending = nil
    return
  end
  s.over = true
  events[#events + 1] = { type = "over" }
end

--- The wait between waves. It ends with the next wave, or with wave 1 when the game has just begun.
local function runPause(s)
  s.pause = s.pause - 1
  if s.pause > 0 then return end
  if not s.banner.first then s.level = s.level + 1 end
  startWave(s)
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.clock = s.clock + 1
  if s.pause > 0 then
    runPause(s)
    return events
  end
  local taps = s.taps
  s.taps = {}
  for _, tap in ipairs(taps) do fire(s, tap, events) end
  if not s.ending then launchSalvo(s, rng) end
  moveBombers(s, rng)
  moveMissiles(s, rng, events)
  moveShots(s)
  growBlasts(s)
  catchAll(s, events)
  if s.ending then
    countDownEnding(s, events)
  elseif s.lives == 0 and s.spare == 0 then
    s.ending = ENDING_STEPS
  elseif waveDone(s) then
    endWave(s, rng, events)
  end
  return events
end

--- Where to aim so a blast meets this thing: a rocket's flight, and a blast starting to open. Nil if no base can reach.
local function leadOf(s, thing)
  local x, y = thing.x, thing.y
  for _ = 1, 3 do
    local base = nearestBase(s, x, y)
    if not base then return nil end
    local steps = distance(base.x - x, HIT_Y - y) / SHOT_SPEED + GROW / 2
    x, y = thing.x + thing.vx * steps, thing.y + (thing.vy or 0) * steps
  end
  return x, y
end

--- Is a rocket or a blast already seeing to this spot?
local function covered(s, x, y)
  for _, shot in ipairs(s.shots) do
    if distance(shot.toX - x, shot.toY - y) <= BLAST - 1 then return true end
  end
  for _, b in ipairs(s.blasts) do
    if not b.harmless and b.age <= GROW + HOLD and distance(b.x - x, b.y - y) <= b.peak - 1 then return true end
  end
  return false
end

--- The lowest thing that matters and isn't dealt with yet, and where to aim at it.
local function pickTarget(s)
  local bestY, aimX, aimY
  local function consider(thing, urgency)
    local x, y = leadOf(s, thing)
    if x and thing.y >= MIN_AIM and y <= FLOOR and x >= 0 and x < WIDTH and not covered(s, x, y) then
      if not bestY or urgency > bestY then bestY, aimX, aimY = urgency, x, y end
    end
  end
  for _, m in ipairs(s.missiles) do
    if m.site.alive then consider(m, m.y) end
  end
  for _, b in ipairs(s.bombers) do consider(b, b.y) end
  return aimX, aimY
end

--- A fair human-looking player for the idle screen and tests: a shot every 0.6 seconds, aimed ahead, and a little off.
function M.bot(s, rng)
  if s.pause > 0 or s.ending or s.clock % 6 ~= 0 then return nil end
  local x, y = pickTarget(s)
  if not x then return nil end
  return { kind = "fire", x = math.floor(x + rng() * 10 - 5), y = math.floor(y + rng() * 6 - 3) }
end

return M
