-- games/pacman/rules.lua
-- Pac-Man. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Everything lives on a grid of tiles. A tap sets s.want, which stays set until a junction lets Pac-Man take it.
-- Pac-Man moves a tile a step, but every few steps is a rest when nobody moves: fewer rests make a level faster.
-- A ghost's speed is percent of Pac-Man's: it banks its speed each moving step and moves a tile for every 100 banked.

local M = { COLS = 29, ROWS = 22 }

local COLS, ROWS = M.COLS, M.ROWS
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local ORDER = { "up", "left", "down", "right" } -- ghosts break ties this way, as in the arcade game

local DOT_SCORE, PELLET_SCORE = 10, 50
local GHOST_SCORES = { 200, 400, 800, 1600 }
local FRUITS = { 100, 300, 500, 700, 1000, 2000, 3000, 5000 } -- by level, the last one for good
local FRUIT_TICKS = 60        -- nine seconds at 150 ms a step
local FRUIT_SHARE = { 0.3, 0.7 } -- how much of the board is eaten when each fruit comes out
local READY_TICKS = 9
local DEATH_TICKS = 8
local CLEAR_TICKS = 10
local EAT_TICKS = 2           -- the short freeze when a ghost is eaten
local POPUP_TICKS = 7
local REVIVE_TICKS = 6        -- eyes rest this long at home before coming back out
local CLYDE_RANGE = 8         -- closer than this, Clyde loses his nerve and heads for his corner

local START = { 15, 14 }
local HOME = { 15, 10 }       -- inside the pen
local EXIT = { 15, 8 }        -- just above the pen's door
local FRUIT_AT = { 15, 12 }
local TUNNEL_ROW, TUNNEL_REACH = 10, 6 -- ghosts crawl through this many tiles at each end of this row

M.DIRECTIONS, M.OPPOSITE, M.FRUIT_AT, M.START = DIRECTIONS, OPPOSITE, FRUIT_AT, START

-- Steps of scatter and chase in turn, starting with scatter. After the last, the ghosts chase for good.
local PHASES = { 47, 133, 47, 133, 33, 133, 33 }

local GHOSTS = {
  { name = "blinky", x = 15, y = 8, mode = "roam", wait = 0, corner = { 28, 0 } },
  { name = "pinky", x = 15, y = 10, mode = "house", wait = 6, corner = { 2, 0 } },
  { name = "inky", x = 13, y = 10, mode = "house", wait = 40, corner = { 28, 23 } },
  { name = "clyde", x = 17, y = 10, mode = "house", wait = 80, corner = { 2, 23 } },
}

-- The left half of the maze and the middle column. The right half is its mirror.
-- # wall, . dot, o power pellet, - the pen's door, space an empty corridor.
local LEFT = {
  "###############",
  "#.............#",
  "#.####.######.#",
  "#o####.######.#",
  "#..............",
  "#.####.##.#####",
  "#.####.##.#####",
  "#......##      ",
  "######.## ####-",
  "      .   #    ",
  "######.## #####",
  "#......##      ",
  "#.####.##.#####",
  "#o..##........ ",
  "###.##.##.#####",
  "#......##.....#",
  "#.####.##.###.#",
  "#.####.##.###.#",
  "#..............",
  "#.###########.#",
  "#..............",
  "###############",
}

local function buildGrid()
  local grid = {}
  for y, half in ipairs(LEFT) do
    local row = half .. half:sub(1, COLS - #half):reverse()
    grid[y] = {}
    for x = 1, COLS do grid[y][x] = row:sub(x, x) end
  end
  return grid
end

local GRID = buildGrid()
M.GRID = GRID

--- The tile one step from x, y. Only the tunnel runs off the edge, and it comes back on the other side.
local function ahead(x, y, dir)
  local d = DIRECTIONS[dir]
  x = x + d[1]
  if x < 1 then x = COLS elseif x > COLS then x = 1 end
  return x, y + d[2]
end

local function tile(x, y)
  local row = GRID[y]
  return row and row[x] or "#"
end

--- Can Pac-Man stand here? Roaming ghosts go the same places.
local function open(x, y)
  local c = tile(x, y)
  return c ~= "#" and c ~= "-"
end

local function key(x, y) return y * 100 + x end

--- Spread out from some tiles along the corridors. Returns reached tiles in order of distance, and distance by tile.
local function flood(starts, limit, blocked, doors)
  local list, dist = {}, {}
  for _, at in ipairs(starts) do
    dist[key(at[1], at[2])] = 0
    list[#list + 1] = { x = at[1], y = at[2], d = 0 }
  end
  local i = 1
  while i <= #list do
    local cur = list[i]
    i = i + 1
    if cur.d < limit then
      for _, dir in ipairs(ORDER) do
        local x, y = ahead(cur.x, cur.y, dir)
        local k = key(x, y)
        local passable = open(x, y) or (doors and tile(x, y) == "-")
        if passable and not dist[k] and not (blocked and blocked[k]) then
          dist[k] = cur.d + 1
          list[#list + 1] = { x = x, y = y, d = cur.d + 1, first = cur.first or dir }
        end
      end
    end
  end
  return list, dist
end

local _, HOME_FIELD = flood({ HOME }, 999, nil, true)
local _, EXIT_FIELD = flood({ EXIT }, 999, nil, true)

local function countDots()
  local total = 0
  for y = 1, ROWS do
    for x = 1, COLS do
      if GRID[y][x] == "." or GRID[y][x] == "o" then total = total + 1 end
    end
  end
  return total
end

M.TOTAL_DOTS = countDots()

--- How often a level rests: every 4th step on level 1, and rarer from there, down to every 12th.
function M.restEvery(level)
  return math.min(12, 3 + level)
end

--- A ghost's ordinary speed on a level. Always below Pac-Man's 100, so a clean run can pull away.
function M.ghostSpeed(level)
  return math.min(98, 84 + 2 * level)
end

--- Steps that ghosts stay frightened on a level.
function M.frightTicks(level)
  return math.max(8, 40 - 5 * (level - 1))
end

local function fruitPoints(level)
  return FRUITS[math.min(level, #FRUITS)]
end

local function fillDots(s)
  s.dots = {}
  for y = 1, ROWS do
    s.dots[y] = {}
    for x = 1, COLS do
      local c = GRID[y][x]
      if c == "." or c == "o" then s.dots[y][x] = c end
    end
  end
  s.dotsLeft = M.TOTAL_DOTS
end

local function newGhost(spec, level)
  return {
    name = spec.name, x = spec.x, y = spec.y, px = spec.x, py = spec.y, dir = "left", mode = spec.mode,
    wait = math.floor(spec.wait / level), corner = spec.corner, scared = false, reverse = false, budget = 0,
  }
end

--- Everyone back to the start, for a new life or a new board. The dots stay as they are.
local function resetActors(s)
  s.pac = { x = START[1], y = START[2], px = START[1], py = START[2], dir = "left" }
  s.want, s.beat = "left", 0
  s.ghosts = {}
  for i, spec in ipairs(GHOSTS) do s.ghosts[i] = newGhost(spec, s.level) end
  s.phase, s.phaseLeft = 1, PHASES[1]
  s.frightLeft, s.combo = 0, 0
  s.fruit, s.popup = nil, nil
  s.pause, s.ready = READY_TICKS, true
end

--- A fresh game.
function M.new()
  local s = { score = 0, level = 1, lives = 3, over = false, frame = 0, boardEaten = 0 }
  fillDots(s)
  resetActors(s)
  return s
end

--- A player's input. It stays set: Pac-Man takes it at the first tile that allows it.
function M.input(s, action)
  if action.kind == "turn" and DIRECTIONS[action.dir] then s.want = action.dir end
end

--- True while ghosts are in a scatter phase.
function M.scattering(s)
  return s.phase % 2 == 1 and PHASES[s.phase] ~= nil
end

local function byName(s, name)
  for _, g in ipairs(s.ghosts) do
    if g.name == name then return g end
  end
end

--- The tile n steps in front of Pac-Man, walls or not.
local function inFront(s, n)
  local d = DIRECTIONS[s.pac.dir]
  return s.pac.x + d[1] * n, s.pac.y + d[2] * n
end

local CHASE = {}

--- Blinky chases: he heads straight for Pac-Man.
function CHASE.blinky(s)
  return s.pac.x, s.pac.y
end

--- Pinky ambushes: she heads four tiles in front of Pac-Man.
function CHASE.pinky(s)
  return inFront(s, 4)
end

--- Inky flanks: he takes the line from Blinky through the spot two tiles in front of Pac-Man, and doubles it.
function CHASE.inky(s)
  local x, y = inFront(s, 2)
  local blinky = byName(s, "blinky")
  return 2 * x - blinky.x, 2 * y - blinky.y
end

--- Clyde wanders: he chases from afar, and turns for his corner once he gets close.
function CHASE.clyde(s, g)
  local dx, dy = s.pac.x - g.x, s.pac.y - g.y
  if dx * dx + dy * dy < CLYDE_RANGE * CLYDE_RANGE then return g.corner[1], g.corner[2] end
  return s.pac.x, s.pac.y
end

--- The tile a ghost is aiming for right now.
function M.target(s, g)
  if M.scattering(s) then return g.corner[1], g.corner[2] end
  return CHASE[g.name](s, g)
end

local function exitsFor(g)
  local list = {}
  for _, dir in ipairs(ORDER) do
    if dir ~= OPPOSITE[g.dir] and open(ahead(g.x, g.y, dir)) then list[#list + 1] = dir end
  end
  return list
end

--- The exit that ends nearest the target, in a straight line.
local function towards(g, exits, tx, ty)
  local best, bestDistance
  for _, dir in ipairs(exits) do
    local x, y = ahead(g.x, g.y, dir)
    local distance = (x - tx) * (x - tx) + (y - ty) * (y - ty)
    if not best or distance < bestDistance then best, bestDistance = dir, distance end
  end
  return best
end

--- Follow a field of distances downhill, for eyes going home and ghosts leaving the pen.
local function downhill(g, field)
  for _, dir in ipairs(ORDER) do
    local x, y = ahead(g.x, g.y, dir)
    if field[key(x, y)] == field[key(g.x, g.y)] - 1 then return dir end
  end
end

local function moveTile(g, dir)
  g.dir = dir
  g.x, g.y = ahead(g.x, g.y, dir)
end

local function chooseRoam(s, g, rng)
  if g.reverse then
    g.reverse = false
    if open(ahead(g.x, g.y, OPPOSITE[g.dir])) then return OPPOSITE[g.dir] end
  end
  local exits = exitsFor(g)
  if #exits == 0 then return OPPOSITE[g.dir] end
  if g.scared then return exits[rng(#exits)] end
  return towards(g, exits, M.target(s, g))
end

local function moveOnce(s, g, rng)
  if g.mode == "roam" then
    moveTile(g, chooseRoam(s, g, rng))
  elseif g.mode == "leave" then
    moveTile(g, downhill(g, EXIT_FIELD))
    if g.x == EXIT[1] and g.y == EXIT[2] then g.mode, g.dir = "roam", "left" end
  elseif g.mode == "eyes" then
    moveTile(g, downhill(g, HOME_FIELD))
    if g.x == HOME[1] and g.y == HOME[2] then g.mode, g.wait = "house", REVIVE_TICKS end
  end
end

local function inTunnel(g)
  return g.y == TUNNEL_ROW and (g.x <= TUNNEL_REACH or g.x > COLS - TUNNEL_REACH)
end

local function speedOf(s, g)
  if g.mode == "eyes" then return 200 end
  if inTunnel(g) then return 55 end
  if g.scared then return 65 end
  if g.mode == "leave" then return 80 end
  return M.ghostSpeed(s.level)
end

local function stepGhost(s, g, rng)
  g.px, g.py = g.x, g.y
  if g.mode == "house" then
    g.wait = g.wait - 1
    if g.wait <= 0 then g.mode = "leave" end
    return
  end
  g.budget = g.budget + speedOf(s, g)
  while g.budget >= 100 do
    g.budget = g.budget - 100
    moveOnce(s, g, rng)
  end
end

local function frighten(s)
  s.frightLeft, s.combo = M.frightTicks(s.level), 0
  for _, g in ipairs(s.ghosts) do
    if g.mode ~= "eyes" then
      g.scared = true
      g.reverse = g.mode == "roam"
    end
  end
end

local function calm(s)
  for _, g in ipairs(s.ghosts) do g.scared = false end
end

local function eatGhost(s, g, events)
  s.combo = s.combo + 1
  local points = GHOST_SCORES[math.min(s.combo, #GHOST_SCORES)]
  s.score = s.score + points
  g.mode, g.scared, g.budget = "eyes", false, 0
  s.popup = { x = g.x, y = g.y, text = tostring(points), left = POPUP_TICKS }
  s.pause = EAT_TICKS
  events[#events + 1] = { type = "ghost", points = points, combo = s.combo }
end

local function die(s, events)
  s.lives = s.lives - 1
  s.after, s.pause = "life", DEATH_TICKS
  events[#events + 1] = { type = "death" }
end

--- Pac-Man and a ghost meet on one tile, or by swapping tiles as they pass.
local function meets(p, g)
  if g.x == p.x and g.y == p.y then return true end
  return g.px == p.x and g.py == p.y and g.x == p.px and g.y == p.py
end

local function checkGhosts(s, events)
  for _, g in ipairs(s.ghosts) do
    if g.mode ~= "eyes" and g.mode ~= "house" and meets(s.pac, g) then
      if g.scared then
        eatGhost(s, g, events)
      else
        die(s, events)
        return
      end
    end
  end
end

local function dropFruit(s, events)
  for _, share in ipairs(FRUIT_SHARE) do
    if s.boardEaten == math.floor(M.TOTAL_DOTS * share) then
      s.fruit = { points = fruitPoints(s.level), left = FRUIT_TICKS }
      events[#events + 1] = { type = "fruitOut" }
    end
  end
end

local function eatTile(s, events)
  local p = s.pac
  local c = s.dots[p.y][p.x]
  if c then
    s.dots[p.y][p.x] = nil
    s.dotsLeft = s.dotsLeft - 1
    s.boardEaten = s.boardEaten + 1
    s.score = s.score + (c == "o" and PELLET_SCORE or DOT_SCORE)
    if c == "o" then frighten(s) end
    events[#events + 1] = { type = c == "o" and "pellet" or "dot" }
    dropFruit(s, events)
  end
  if s.fruit and p.x == FRUIT_AT[1] and p.y == FRUIT_AT[2] then
    s.score = s.score + s.fruit.points
    s.popup = { x = p.x, y = p.y, text = tostring(s.fruit.points), left = POPUP_TICKS }
    s.fruit = nil
    events[#events + 1] = { type = "fruit" }
  end
end

local function stepPac(s, events)
  local p = s.pac
  p.px, p.py = p.x, p.y
  if open(ahead(p.x, p.y, s.want)) then p.dir = s.want end
  if not open(ahead(p.x, p.y, p.dir)) then return end
  p.x, p.y = ahead(p.x, p.y, p.dir)
  eatTile(s, events)
  if s.dotsLeft == 0 then
    s.after, s.pause = "level", CLEAR_TICKS
    events[#events + 1] = { type = "clear" }
  end
end

local function nextPhase(s)
  s.phase = s.phase + 1
  s.phaseLeft = PHASES[s.phase] or 0
  for _, g in ipairs(s.ghosts) do g.reverse = g.mode == "roam" end
end

--- Scatter and chase run only while nobody is frightened.
local function runClocks(s)
  if s.popup then
    s.popup.left = s.popup.left - 1
    if s.popup.left <= 0 then s.popup = nil end
  end
  if s.fruit then
    s.fruit.left = s.fruit.left - 1
    if s.fruit.left <= 0 then s.fruit = nil end
  end
  if s.frightLeft > 0 then
    s.frightLeft = s.frightLeft - 1
    if s.frightLeft == 0 then calm(s) end
  elseif s.phaseLeft > 0 then
    s.phaseLeft = s.phaseLeft - 1
    if s.phaseLeft == 0 then nextPhase(s) end
  end
end

--- What comes after a pause: the next life, the next board or the end. A short freeze needs nothing.
local function endPause(s, events)
  local after = s.after
  s.after, s.ready = nil, false
  if after == "life" then
    if s.lives <= 0 then
      s.over = true
      events[#events + 1] = { type = "over" }
    else
      resetActors(s)
    end
  elseif after == "level" then
    s.level = s.level + 1
    s.boardEaten = 0
    fillDots(s)
    resetActors(s)
    events[#events + 1] = { type = "level" }
  end
end

--- Is this a rest step? The screen holds still on one too, because frame stands still with everyone else.
local function resting(s)
  s.beat = s.beat % M.restEvery(s.level) + 1
  return s.beat == M.restEvery(s.level)
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  if s.pause > 0 then
    s.frame = s.frame + 1
    s.pause = s.pause - 1
    if s.pause == 0 then endPause(s, events) end
    return events
  end
  runClocks(s)
  if resting(s) then return events end
  s.frame = s.frame + 1
  stepPac(s, events)
  if s.after then return events end
  checkGhosts(s, events)
  if s.after then return events end
  for _, g in ipairs(s.ghosts) do stepGhost(s, g, rng) end
  checkGhosts(s, events)
  return events
end

-- ---------------------------------------------------------------- the bot

local BOT_CARE = 3      -- tiles of room the bot keeps from a ghost
local BOT_HUNT = 9      -- how far it will go after a frightened ghost
local BOT_LAPSE = 0.04  -- how often it stops looking, so its runs come to an end

local function threats(s)
  local list = {}
  for _, g in ipairs(s.ghosts) do
    if not g.scared and (g.mode == "roam" or g.mode == "leave") then list[#list + 1] = { g.x, g.y } end
  end
  return list
end

local function dangerZone(s)
  local _, dist = flood(threats(s), 999, nil, true)
  local zone = {}
  for k, d in pairs(dist) do
    if d <= BOT_CARE then zone[k] = true end
  end
  return zone, dist
end

local function isFood(s, t)
  if s.dots[t.y][t.x] then return true end
  return s.fruit and t.x == FRUIT_AT[1] and t.y == FRUIT_AT[2]
end

local function scaredAt(s, t)
  for _, g in ipairs(s.ghosts) do
    if g.scared and g.mode ~= "eyes" and g.x == t.x and g.y == t.y then return true end
  end
  return false
end

--- The first step to a frightened ghost in reach, or else to the nearest food.
local function firstStep(s, reached)
  local food
  for _, t in ipairs(reached) do
    if t.first then
      if t.d <= BOT_HUNT and scaredAt(s, t) then return t.first end
      food = food or (isFood(s, t) and t.first)
    end
  end
  return food
end

--- With nowhere safe to go, take the neighbouring tile furthest from any ghost.
local function flee(s, dist)
  local best, bestDistance = nil, -1
  for _, dir in ipairs(ORDER) do
    local x, y = ahead(s.pac.x, s.pac.y, dir)
    local distance = dist[key(x, y)]
    if open(x, y) and distance and distance > bestDistance then best, bestDistance = dir, distance end
  end
  return best
end

--- A decent but human player for the idle screen and tests: go for food, and keep clear of ghosts unless it lapses.
function M.bot(s, rng)
  if s.pause > 0 then return nil end
  local zone, dist = dangerZone(s)
  if rng() < BOT_LAPSE then zone = {} end
  local dir = firstStep(s, (flood({ { s.pac.x, s.pac.y } }, 999, zone))) or flee(s, dist)
  return dir and { kind = "turn", dir = dir } or nil
end

return M
