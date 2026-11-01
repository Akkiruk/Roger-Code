-- games/druaga/rules.lua
-- The Tower of Druaga. Pure: no screen, sound or files. See "Classics" in Games/Arcade/games/README.md.
-- The tower is twenty floors of cells with thin walls between them. Each floor comes from its own seed, drawn when the run
-- starts, so a floor is the same every time it is made: after a death, or after being zapped back down to it.
-- A tap sets s.want, which waits for a turning and is forgotten when a wall stops him. The middle of the wall draws or
-- sheathes the sword, standing in for the original's held button. Drawn, he fights and nothing can walk into him, but any
-- spell kills him. Sheathed, his shield stops spells from the front, but anything that touches him kills him.
-- State is plain data, whole numbers and no shared tables, because a run is saved with textutils.serialise between visits.
-- Actors bank their speed each step and move a cell for every 100 banked.

local journal = require("lib.arcade.journal")

local M = { COLS = 15, ROWS = 11, TOP = 20 }

local COLS, ROWS, TOP = M.COLS, M.ROWS, M.TOP
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local CLOCKWISE = { up = "right", right = "down", down = "left", left = "up" }
local ORDER = { "up", "left", "down", "right" }

local SECOND = 7              -- steps of the clock in a second, at 140 ms a step
local MAX_HP = 40             -- what a floor's duels can cost him; it fills again on every floor
local WALK, JET = 40, 56      -- his speed, and in jet boots
local SWING_TICKS = 2         -- steps between sword strokes
local SWORD_DAMAGE = { 1, 2, 3 }
local CLASH_TICKS = 4         -- how often something in reach of him strikes
local PICK_USES = 2           -- walls a pick-axe breaks on one floor
local MAX_POTIONS = 3
local SAFE_TICKS = 18         -- the moments after a potion, when nothing can kill him
local SPELL_SPEED = 60
local FIRE_SPEED = 80
local FIRE_REACH = 6
local CAST_TICKS = 7          -- a mage glows this long, and that is your warning
local REST_TICKS = 6          -- it stays to be hit this long after casting
local WINDUP_TICKS = 8        -- a dragon's breath
local SPIT_TICKS = 40
local SPIT_REACH = 7
local ROPER_REACH = 2
local SWARM_TICKS = 10        -- once time is up, another wisp comes this often
local SWARM_MOST = 10
local READY_TICKS = 26        -- long enough to read the riddle
local DEATH_TICKS = 10
local CLEAR_TICKS = 12
local POPUP_TICKS = 7
local BURST_TICKS = 3
local NOTE_TICKS = 18
local KEY_SIGHT = 2           -- how close he must be to see a key on a dark floor

local KEY_SCORE, CHEST_SCORE, CLEAR_SCORE, BLOCK_SCORE, GEM_SCORE = 100, 500, 1000, 20, 1500
local SECOND_SCORE = 10       -- for each second left on the timer
local WIN_SCORE = 50000       -- for carrying Ki out

-- class says how it behaves. hp and power are per hit, speed and chase (percent) for how it walks.
-- Speeds sit under the arcade's on purpose: only a late wisp is ever quicker than he walks, and never than jet boots.
local KINDS = {
  green = { class = "slime", name = "Green slime", hp = 2, speed = 11, chase = 10, points = 30 },
  black = { class = "slime", name = "Black slime", hp = 3, speed = 15, chase = 25, points = 60 },
  red = { class = "slime", name = "Red slime", hp = 3, speed = 18, chase = 30, points = 120, spits = true },
  blueKnight = { class = "knight", name = "Blue knight", hp = 4, power = 3, speed = 16, chase = 40, points = 200 },
  greenKnight = { class = "knight", name = "Green knight", hp = 6, power = 4, speed = 18, chase = 45, points = 400 },
  redKnight = { class = "knight", name = "Red knight", hp = 9, power = 5, speed = 22, chase = 55, points = 800 },
  blackKnight = { class = "knight", name = "Black knight", hp = 14, power = 5, speed = 26, chase = 65, points = 1500 },
  mage = { class = "mage", name = "Mage", hp = 2, every = 30, points = 300 },
  ghost = { class = "mage", name = "Ghost mage", hp = 3, every = 22, points = 600, fades = true },
  wisp = { class = "wisp", name = "Wisp", speed = 28 },
  hunter = { class = "wisp", name = "Red wisp", speed = 38, hunts = true },
  roper = { class = "roper", name = "Roper", hp = 6, power = 7, speed = 7, chase = 50, points = 700 },
  dragon = { class = "dragon", name = "Dragon", hp = 18, power = 8, speed = 14, chase = 50, points = 3000 },
  silverDragon = { class = "dragon", name = "Silver dragon", hp = 27, power = 8, speed = 18, chase = 60, points = 6000 },
  druaga = { class = "druaga", name = "Druaga", hp = 30, power = 7, points = 20000, size = 2, needsSword = 3 },
}

-- What a chest can hold. sword and shield are the level it brings them up to.
local ITEMS = {
  pick = { name = "PICK-AXE" },
  boots = { name = "JET BOOTS" },
  sword2 = { name = "SILVER SWORD", sword = 2 },
  sword3 = { name = "EXCALIBUR", sword = 3 },
  shield2 = { name = "HYPER SHIELD", shield = 2 },
  balance = { name = "THE BALANCE" },
  potion = { name = "POTION" },
  gem = { name = "A JEWEL", points = GEM_SCORE },
}

local function corner(x, y) return { type = "spot", x = x, y = y } end

-- Twenty floors. foes are { kind, how many, guards }: guards stand on the way to the key and have to be fought.
-- cond is what brings out the chest, riddle is how the floor hints at it, and needs lists the floors whose chests must be
-- open before this floor's door will lead up: without them it zaps you back to the lowest one, as the original did.
local FLOORS = {
  { riddle = "Green things hide it. Leave none alive.", cond = { type = "slimes" }, item = "pick",
    foes = { { "green", 6 } } },
  { riddle = "Stand in the corner where the sun climbs.", cond = corner(COLS, 1), item = "boots",
    foes = { { "green", 4 }, { "black", 3 }, { "blueKnight", 1, 1 } } },
  { riddle = "The green knight keeps it. Cut him down.", cond = { type = "kill", kind = "greenKnight" }, item = "potion",
    foes = { { "black", 3 }, { "blueKnight", 2 }, { "greenKnight", 1 }, { "wisp", 1 } } },
  { riddle = "Turn two spells upon your shield.", cond = { type = "block", count = 2 }, item = "sword2",
    foes = { { "green", 3 }, { "mage", 2 }, { "blueKnight", 2 } } },
  { riddle = "Hold the key within twenty heartbeats.", cond = { type = "swift", seconds = 20 }, item = "gem", needs = { 1 },
    foes = { { "black", 4 }, { "mage", 2 }, { "blueKnight", 2, 1 }, { "wisp", 1 } } },
  { riddle = "Steel hides it. Fell every knight.", cond = { type = "knights" }, item = "potion",
    foes = { { "red", 3 }, { "blueKnight", 2 }, { "greenKnight", 2, 1 }, { "wisp", 1 } } },
  { riddle = "Stand in the corner where the sun sets.", cond = corner(1, 1), item = "shield2", needs = { 4 },
    foes = { { "red", 2 }, { "mage", 3 }, { "greenKnight", 2 }, { "wisp", 2 } } },
  { riddle = "Turn three spells upon your shield.", cond = { type = "block", count = 3 }, item = "balance",
    foes = { { "black", 3 }, { "ghost", 2 }, { "mage", 2 }, { "greenKnight", 2 } } },
  { riddle = "In the dark, red things hide it. End them.", cond = { type = "slimes" }, item = "potion", dark = true,
    foes = { { "red", 4 }, { "mage", 2 }, { "redKnight", 2 }, { "wisp", 2 } } },
  { riddle = "A roper sits upon it. Kill the thing.", cond = { type = "kill", kind = "roper" }, item = "gem",
    foes = { { "roper", 2 }, { "greenKnight", 3, 1 }, { "ghost", 1 }, { "wisp", 1 } } },
  { riddle = "Hold the key within fifteen heartbeats.", cond = { type = "swift", seconds = 15 }, item = "potion",
    foes = { { "roper", 2 }, { "redKnight", 3 }, { "mage", 2 }, { "wisp", 2 } } },
  { riddle = "Knock on the door before you hold the key.", cond = { type = "knock" }, item = "gem", needs = { 7 },
    foes = { { "red", 3 }, { "ghost", 3 }, { "redKnight", 2, 1 }, { "wisp", 2 } } },
  { riddle = "The dragon sleeps on it. Wake it for good.", cond = { type = "kill", kind = "dragon" }, item = "potion",
    foes = { { "dragon", 1 }, { "redKnight", 2 }, { "mage", 2 }, { "wisp", 2 } } },
  { riddle = "Stand in the dark at the tower's heart.", cond = corner(8, 6), item = "gem", dark = true,
    foes = { { "red", 3 }, { "roper", 2 }, { "ghost", 2 }, { "blackKnight", 1 }, { "wisp", 2 } } },
  { riddle = "Turn four spells upon your shield.", cond = { type = "block", count = 4 }, item = "potion",
    foes = { { "mage", 4 }, { "ghost", 2 }, { "redKnight", 2 }, { "wisp", 3 } } },
  { riddle = "Fell every knight, then break the wall.", cond = { type = "knights" }, item = "sword3", sealed = true,
    foes = { { "blackKnight", 2, 1 }, { "redKnight", 2 }, { "roper", 2 }, { "wisp", 2 } } },
  { riddle = "A ghost mage keeps it. Catch one.", cond = { type = "kill", kind = "ghost" }, item = "potion",
    foes = { { "ghost", 3 }, { "blackKnight", 2 }, { "dragon", 1 }, { "wisp", 3 } } },
  { riddle = "Stand in the last corner, in the dark.", cond = corner(COLS, ROWS), item = "gem", dark = true,
    foes = { { "dragon", 2 }, { "roper", 2 }, { "mage", 3 }, { "wisp", 3 } } },
  { riddle = "The silver dragon keeps it. No other.", cond = { type = "kill", kind = "silverDragon" }, item = "potion", needs = { 16 },
    foes = { { "silverDragon", 1 }, { "blackKnight", 2, 1 }, { "ghost", 2 }, { "wisp", 2 } } },
  { riddle = "Only Excalibur cuts him. Free Ki.", cond = { type = "kill", kind = "druaga" }, item = "gem", boss = true,
    foes = { { "wisp", 2 } } },
}

-- The room at the top. Druaga jumps between these, and each is the top left of the two cells square he fills.
local ARENA = { x0 = 5, y0 = 3, x1 = 11, y1 = 8 }
local DRUAGA_SPOTS = { { 6, 4 }, { 9, 4 }, { 6, 6 }, { 9, 6 } }

M.DIRECTIONS, M.OPPOSITE, M.KINDS, M.ITEMS, M.FLOORS = DIRECTIONS, OPPOSITE, KINDS, ITEMS, FLOORS
M.MAX_HP, M.READY_TICKS, M.DEATH_TICKS, M.CLEAR_TICKS = MAX_HP, READY_TICKS, DEATH_TICKS, CLEAR_TICKS
M.CAST_TICKS, M.WINDUP_TICKS, M.CLASH_TICKS, M.SAFE_TICKS = CAST_TICKS, WINDUP_TICKS, CLASH_TICKS, SAFE_TICKS
M.REST_TICKS, M.PICK_USES, M.SECOND_SCORE, M.CLEAR_SCORE = REST_TICKS, PICK_USES, SECOND_SCORE, CLEAR_SCORE
M.WIN_SCORE, M.ROPER_REACH, M.FIRE_REACH, M.SWARM_TICKS = WIN_SCORE, ROPER_REACH, FIRE_REACH, SWARM_TICKS
M.SECOND, M.WALK = SECOND, WALK

--- Ticks on a floor's timer: 75 seconds at the bottom, 56 at the top.
function M.floorTicks(level)
  return (76 - level) * SECOND
end

local function ahead(x, y, dir)
  local d = DIRECTIONS[dir]
  return x + d[1], y + d[2]
end

--- Is there a wall on this side of this cell?
local function walled(s, x, y, dir)
  if dir == "up" then return y <= 1 or s.below[y - 1][x] end
  if dir == "down" then return y >= ROWS or s.below[y][x] end
  if dir == "left" then return x <= 1 or s.right[y][x - 1] end
  return x >= COLS or s.right[y][x]
end

M.walled = walled

--- Knock a wall out, or put one up.
local function setWall(s, x, y, dir, value)
  if dir == "up" then s.below[y - 1][x] = value end
  if dir == "down" then s.below[y][x] = value end
  if dir == "left" then s.right[y][x - 1] = value end
  if dir == "right" then s.right[y][x] = value end
end

M.setWall = setWall

--- Steps from this cell to every other, on foot, as a grid. Cells behind walls stay nil.
local function distances(s, x, y)
  local map = {}
  for row = 1, ROWS do map[row] = {} end
  map[y][x] = 0
  local queueX, queueY, head = { x }, { y }, 1
  while queueX[head] do
    local cx, cy = queueX[head], queueY[head]
    head = head + 1
    for i = 1, 4 do
      local dir = ORDER[i]
      if not walled(s, cx, cy, dir) then
        local nx, ny = ahead(cx, cy, dir)
        if not map[ny][nx] then
          map[ny][nx] = map[cy][cx] + 1
          queueX[#queueX + 1], queueY[#queueY + 1] = nx, ny
        end
      end
    end
  end
  return map
end

M.distances = distances

-- ---------------------------------------------------------------- building a floor

local function shuffled(r)
  local list = { "up", "left", "down", "right" }
  for i = 4, 2, -1 do
    local j = r(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

--- A perfect maze: every wall up, then a walk that knocks through into any cell it hasn't seen.
local function carve(s, r)
  s.right, s.below = {}, {}
  local seen = {}
  for y = 1, ROWS do
    s.right[y], s.below[y], seen[y] = {}, {}, {}
    for x = 1, COLS do s.right[y][x], s.below[y][x], seen[y][x] = true, true, false end
  end
  local stackX, stackY = { r(COLS) }, { r(ROWS) }
  seen[stackY[1]][stackX[1]] = true
  while #stackX > 0 do
    local x, y = stackX[#stackX], stackY[#stackY]
    local moved = false
    for _, dir in ipairs(shuffled(r)) do
      local nx, ny = ahead(x, y, dir)
      if nx >= 1 and nx <= COLS and ny >= 1 and ny <= ROWS and not seen[ny][nx] then
        setWall(s, x, y, dir, false)
        seen[ny][nx] = true
        stackX[#stackX + 1], stackY[#stackY + 1] = nx, ny
        moved = true
        break
      end
    end
    if not moved then stackX[#stackX], stackY[#stackY] = nil, nil end
  end
end

local function exitsOf(s, x, y)
  local list = {}
  for _, dir in ipairs(ORDER) do
    if not walled(s, x, y, dir) then list[#list + 1] = dir end
  end
  return list
end

M.exitsOf = exitsOf

--- A cell at a dead end, which can be walled up without cutting any other cell off.
local function pickVault(s, r)
  local list = {}
  for y = 1, ROWS do
    for x = 1, COLS do
      if #exitsOf(s, x, y) == 1 and y < ROWS then list[#list + 1] = { x, y } end
    end
  end
  return list[r(#list)]
end

--- Open up most dead ends: the original's mazes had loops, and a wisp must not be able to pin him in a blind alley.
local function braid(s, r, vault)
  for y = 1, ROWS do
    for x = 1, COLS do
      local isVault = vault and vault[1] == x and vault[2] == y
      if not isVault and #exitsOf(s, x, y) == 1 and r(100) <= 80 then
        local dir = shuffled(r)
        for _, way in ipairs(dir) do
          local nx, ny = ahead(x, y, way)
          local intoVault = vault and vault[1] == nx and vault[2] == ny
          if walled(s, x, y, way) and nx >= 1 and nx <= COLS and ny >= 1 and ny <= ROWS and not intoVault then
            setWall(s, x, y, way, false)
            break
          end
        end
      end
    end
  end
end

--- The room at the top has no walls inside it.
local function openArena(s)
  for y = ARENA.y0, ARENA.y1 do
    for x = ARENA.x0, ARENA.x1 do
      if x < ARENA.x1 then s.right[y][x] = false end
      if y < ARENA.y1 then s.below[y][x] = false end
    end
  end
end

--- A random cell from those at least share percent of the way along the best score.
local function farCell(r, score)
  local best = 0
  for y = 1, ROWS do
    for x = 1, COLS do best = math.max(best, score(x, y) or 0) end
  end
  local list = {}
  for y = 1, ROWS do
    for x = 1, COLS do
      local value = score(x, y)
      if value and value * 10 >= best * 8 then list[#list + 1] = { x, y } end
    end
  end
  return list[r(#list)]
end

--- The way from a cell back to where the map was drawn from, so guards can stand on it.
local function pathOf(s, map, x, y)
  local path = {}
  while map[y][x] > 0 do
    path[#path + 1] = { x, y }
    for _, dir in ipairs(ORDER) do
      if not walled(s, x, y, dir) then
        local nx, ny = ahead(x, y, dir)
        if map[ny][nx] and map[ny][nx] < map[y][x] then
          x, y = nx, ny
          break
        end
      end
    end
  end
  return path
end

M.pathOf = pathOf

local function newEnemy(s, kind, x, y, r)
  local k = KINDS[kind]
  local e = {
    id = s.nextId, kind = kind, x = x, y = y, px = x, py = y, dir = ORDER[r(4)], budget = 0, hp = k.hp or 1,
    mode = "walk", t = 8 + r(24), hit = 0, clash = CLASH_TICKS, guard = false, hidden = false, volleys = 0,
  }
  s.nextId = s.nextId + 1
  if k.class == "mage" or k.class == "druaga" then e.mode, e.hidden = "wait", k.fades == true end
  if k.spits then e.t = SPIT_TICKS + r(20) end
  return e
end

--- An enemy, for tests.
function M.spawn(s, kind, x, y, r)
  local e = newEnemy(s, kind, x, y, r)
  s.enemies[#s.enemies + 1] = e
  return e
end

--- Cells taken as a key = true grid, so nothing lands on the start, key, door or chest.
local function takenCell(taken, x, y)
  return taken[y * 100 + x]
end

local function take(taken, x, y)
  taken[y * 100 + x] = true
end

local function placeEnemies(s, floor, r, map, taken)
  local keyPath = pathOf(s, map, s.key.x, s.key.y)
  for _, foe in ipairs(floor.foes) do
    local kind, count, guards = foe[1], foe[2], foe[3] or 0
    for i = 1, count do
      local x, y
      if i <= guards then
        -- about half way to the key, in a corridor if one is near
        for at = math.floor(#keyPath / 2), #keyPath do
          local cell = keyPath[at]
          if cell and not takenCell(taken, cell[1], cell[2]) then
            x, y = cell[1], cell[2]
            if #exitsOf(s, x, y) == 2 then break end
          end
        end
      end
      local guarding = x ~= nil
      for _ = 1, 200 do
        if x then break end
        local tx, ty = r(COLS), r(ROWS)
        if map[ty][tx] and map[ty][tx] >= 5 and not takenCell(taken, tx, ty) then x, y = tx, ty end
      end
      if x then
        take(taken, x, y)
        local e = newEnemy(s, kind, x, y, r)
        e.guard = guarding
        s.enemies[#s.enemies + 1] = e
      end
    end
  end
end

--- Everything about a floor, made again from its seed, so a floor never changes.
local function buildFloor(s)
  local floor = FLOORS[s.level]
  local r = journal.rng(s.seeds[s.level])
  carve(s, r)
  local vault = floor.sealed and pickVault(s, r) or nil
  if floor.boss then openArena(s) end
  braid(s, r, vault)
  if vault then
    local exits = exitsOf(s, vault[1], vault[2])
    for _, dir in ipairs(exits) do setWall(s, vault[1], vault[2], dir, true) end
  end
  local sx, sy = r(COLS), ROWS
  if floor.boss then sx = 8 end
  local map = distances(s, sx, sy)
  local door = floor.boss and { 8, 1 } or farCell(r, function(x, y) return map[y][x] end)
  local doorMap = distances(s, door[1], door[2])
  local key = floor.boss and { 8, 5 } or farCell(r, function(x, y)
    return map[y][x] and math.min(map[y][x], doorMap[y][x])
  end)
  s.start = { x = sx, y = sy }
  s.door = { x = door[1], y = door[2] }
  s.key = { x = key[1], y = key[2], held = floor.boss == true }
  s.hasKey, s.knocked, s.blocked = false, false, 0
  s.killed = {}
  s.enemies, s.spells, s.popups, s.bursts = {}, {}, {}, {}
  s.chest = nil
  local taken = {}
  take(taken, sx, sy)
  take(taken, door[1], door[2])
  take(taken, key[1], key[2])
  -- the chest's place is drawn even when it's open, so the rest of the floor comes out the same either way
  local chestAt = vault
  while not chestAt do
    local x, y = r(COLS), r(ROWS)
    if map[y][x] and map[y][x] >= 4 and not takenCell(taken, x, y) then chestAt = { x, y } end
  end
  take(taken, chestAt[1], chestAt[2])
  if not s.opened[s.level] then
    s.chest = { x = chestAt[1], y = chestAt[2], item = floor.item, shown = false, sealed = vault ~= nil }
  end
  if floor.boss then
    local spot = DRUAGA_SPOTS[r(#DRUAGA_SPOTS)]
    s.enemies[1] = newEnemy(s, "druaga", spot[1], spot[2], r)
    for x = spot[1], spot[1] + 1 do
      for y = spot[2], spot[2] + 1 do take(taken, x, y) end
    end
  end
  placeEnemies(s, floor, r, map, taken)
end

--- Into a floor, new or again: the timer and his strength start afresh, and the floor is as it was made.
local function enterFloor(s)
  buildFloor(s)
  local x, y = s.start.x, s.start.y
  s.player = { x = x, y = y, px = x, py = y, dir = "up", walk = false, budget = 100, swing = 0 }
  s.want, s.dig, s.toggle = false, false, false
  s.hp, s.picks, s.safe = MAX_HP, PICK_USES, 0
  s.timer, s.swarmIn, s.swarmed = M.floorTicks(s.level), 0, 0
  s.zapTo = false
  s.pause, s.ready, s.after = READY_TICKS, true, false
end

--- A fresh game. opts.rng is the only source of chance, and every floor's seed is drawn from it here.
function M.new(opts)
  local s = {
    score = 0, level = 1, lives = 3, over = false, won = false, frame = 0, nextId = 1, drawn = false, note = false,
    items = { sword = 1, shield = 1, pick = false, boots = false, balance = false, potions = 0 },
    seeds = {}, opened = {},
  }
  for i = 1, TOP do
    s.seeds[i] = opts.rng(2147483646)
    s.opened[i] = false
  end
  enterFloor(s)
  return s
end

--- Move a run on to a floor, for tests and for nothing else.
function M.goTo(s, level)
  s.level = level
  enterFloor(s)
end

--- The riddle for the floor he's on.
function M.riddle(s)
  return FLOORS[s.level].riddle
end

--- Can the key be seen? On a dark floor only the Balance shows it from afar.
function M.keyShown(s)
  if s.hasKey or s.key.held then return false end
  if not FLOORS[s.level].dark or s.items.balance then return true end
  local p = s.player
  return math.abs(p.x - s.key.x) + math.abs(p.y - s.key.y) <= KEY_SIGHT
end

-- ---------------------------------------------------------------- input

--- A player's input. A turn waits for its junction. A second tap into a wall he has stopped at swings the pick-axe.
function M.input(s, action)
  if s.over or (s.pause > 0 and not s.ready) then return end
  local p = s.player
  if action.kind == "sword" then
    s.toggle = not s.toggle
  elseif action.kind == "turn" and DIRECTIONS[action.dir] then
    local dir = action.dir
    if not p.walk and walled(s, p.x, p.y, dir) then
      local nx, ny = ahead(p.x, p.y, dir)
      local inside = nx >= 1 and nx <= COLS and ny >= 1 and ny <= ROWS
      if p.dir == dir and inside and s.items.pick and s.picks > 0 then s.dig = dir end
      p.dir, s.want = dir, false
      return
    end
    if not p.walk then p.dir = dir end
    s.want = dir
  end
end

-- ---------------------------------------------------------------- the small things

local function popup(s, x, y, text)
  s.popups[#s.popups + 1] = { x = x, y = y, text = tostring(text), left = POPUP_TICKS }
end

local function setNote(s, text)
  s.note = { text = text, left = NOTE_TICKS }
end

local function award(s, points, x, y)
  s.score = s.score + points
  popup(s, x, y, points)
end

local function occupies(e, x, y)
  local size = KINDS[e.kind].size or 1
  return x >= e.x and x < e.x + size and y >= e.y and y < e.y + size
end

--- The enemy on a cell. A faded ghost mage isn't there to be hit or to walk into.
local function enemyAt(s, x, y)
  for _, e in ipairs(s.enemies) do
    if not e.hidden and occupies(e, x, y) then return e end
  end
end

M.enemyAt = enemyAt

local function removeEnemy(s, target)
  for i, e in ipairs(s.enemies) do
    if e.id == target.id then
      table.remove(s.enemies, i)
      return
    end
  end
end

local function die(s, events, cause)
  if s.after or s.safe > 0 then return end
  if s.items.potions > 0 then
    s.items.potions = s.items.potions - 1
    s.hp, s.safe = MAX_HP, SAFE_TICKS
    setNote(s, "THE POTION SAVES YOU")
    events[#events + 1] = { type = "potion", cause = cause }
    return
  end
  s.lives = s.lives - 1
  s.after, s.pause, s.want, s.killedBy = "life", DEATH_TICKS, false, cause
  s.player.walk = false
  events[#events + 1] = { type = "death", cause = cause }
end

--- The chest shows itself.
local function reveal(s, events)
  if s.chest and not s.chest.shown then
    s.chest.shown = true
    setNote(s, "A CHEST APPEARS")
    events[#events + 1] = { type = "chest" }
  end
end

local function countClass(s, class)
  local n = 0
  for _, e in ipairs(s.enemies) do
    if KINDS[e.kind].class == class then n = n + 1 end
  end
  return n
end

--- Has the floor's condition been met? The two that depend on a moment are tested where that moment happens.
local function conditionMet(s)
  local cond = FLOORS[s.level].cond
  local p = s.player
  if cond.type == "slimes" then return countClass(s, "slime") == 0 end
  if cond.type == "knights" then return countClass(s, "knight") == 0 end
  if cond.type == "kill" then return (s.killed[cond.kind] or 0) >= 1 end
  if cond.type == "block" then return s.blocked >= cond.count end
  if cond.type == "spot" then return p.x == cond.x and p.y == cond.y end
  if cond.type == "knock" then return s.knocked end
  return false
end

--- A strike has finished something. Druaga drops the key to Ki's chains.
local function killEnemy(s, e, events)
  local k = KINDS[e.kind]
  removeEnemy(s, e)
  s.killed[e.kind] = (s.killed[e.kind] or 0) + 1
  award(s, k.points, e.x, e.y)
  s.bursts[#s.bursts + 1] = { x = e.x, y = e.y, kind = e.kind, left = BURST_TICKS }
  events[#events + 1] = { type = "kill", kind = e.kind, points = k.points }
  if k.class == "druaga" then
    s.key.x, s.key.y, s.key.held = e.x, e.y, false
    setNote(s, "DRUAGA FALLS")
  end
end

--- A stroke of the sword. Druaga's hide turns anything less than Excalibur.
local function strike(s, e, events)
  local k = KINDS[e.kind]
  local p = s.player
  p.swing = SWING_TICKS
  if k.needsSword and s.items.sword < k.needsSword then
    setNote(s, "YOUR SWORD CANNOT CUT HIM")
    events[#events + 1] = { type = "clink" }
    return
  end
  e.hp = e.hp - SWORD_DAMAGE[s.items.sword]
  e.hit = 2
  events[#events + 1] = { type = "hit", kind = e.kind }
  if e.hp <= 0 then killEnemy(s, e, events) end
end

local function breakWall(s, events)
  local p = s.player
  local dir = s.dig
  s.dig = false
  if not walled(s, p.x, p.y, dir) or s.picks <= 0 then return end
  setWall(s, p.x, p.y, dir, false)
  s.picks = s.picks - 1
  events[#events + 1] = { type = "dig" }
end

--- Which way he goes next, or nil. A wanted turn is taken as soon as there's a way, and a wall stops him and forgets it.
local function nextWay(s)
  local p = s.player
  if s.want and not walled(s, p.x, p.y, s.want) then
    p.walk, s.want = s.want, false
    return p.walk
  end
  if p.walk and not walled(s, p.x, p.y, p.walk) then return p.walk end
  p.walk, s.want = false, false
  return nil
end

--- He moves when he has banked a cell. Into an enemy he strikes, or with the sword away he dies.
local function stepPlayer(s, events)
  local p = s.player
  if p.swing > 0 then p.swing = p.swing - 1 end
  if s.dig then breakWall(s, events) end
  if p.budget < 100 then
    p.budget = p.budget + (s.items.boots and JET or WALK)
    if p.budget < 100 then return end
  end
  local dir = nextWay(s)
  if not dir then
    p.budget = 100
    p.px, p.py = p.x, p.y
    return
  end
  p.dir = dir
  local x, y = ahead(p.x, p.y, dir)
  local e = enemyAt(s, x, y)
  if e then
    p.budget = 100
    p.px, p.py = p.x, p.y
    if KINDS[e.kind].class == "wisp" or not s.drawn then
      die(s, events, e.kind)
    elseif p.swing == 0 then
      strike(s, e, events)
    end
    return
  end
  p.px, p.py, p.x, p.y = p.x, p.y, x, y
  p.budget = p.budget - 100
end

--- Does the shield stop this? It needs the sword away and its face to the spell. The Hyper Shield covers his sides as well,
--- and only it can stand a dragon's fire.
local function shieldStops(s, spell)
  if s.drawn then return false end
  local better = s.items.shield >= 2
  if spell.kind == "fire" and not better then return false end
  local coming = OPPOSITE[spell.dir]
  if s.player.dir == coming then return true end
  return better and s.player.dir ~= spell.dir
end

local function spellHits(s, spell, events)
  if shieldStops(s, spell) then
    s.blocked = s.blocked + 1
    s.score = s.score + BLOCK_SCORE
    events[#events + 1] = { type = "block", kind = spell.kind }
  else
    die(s, events, spell.kind)
  end
end

--- A spell's flight: on through open cells until a wall stops it, or he does. Returns false once it's spent.
local function flySpell(s, spell, events)
  local p = s.player
  if spell.x == p.x and spell.y == p.y then
    spellHits(s, spell, events)
    return false
  end
  spell.budget = spell.budget + (spell.kind == "fire" and FIRE_SPEED or SPELL_SPEED)
  while spell.budget >= 100 do
    spell.budget = spell.budget - 100
    if walled(s, spell.x, spell.y, spell.dir) then return false end
    spell.x, spell.y = ahead(spell.x, spell.y, spell.dir)
    spell.left = spell.left - 1
    if spell.x == p.x and spell.y == p.y then
      spellHits(s, spell, events)
      return false
    end
    if spell.left <= 0 then return false end
  end
  return true
end

local function stepSpells(s, events)
  local kept = {}
  for _, spell in ipairs(s.spells) do
    if flySpell(s, spell, events) then kept[#kept + 1] = spell end
  end
  s.spells = kept
end

local function castSpell(s, x, y, dir, kind)
  s.spells[#s.spells + 1] = { x = x, y = y, dir = dir, kind = kind, budget = 0, left = kind == "fire" and FIRE_REACH or 99 }
end

M.castSpell = castSpell

-- ---------------------------------------------------------------- enemies

--- Along a clear row or column to him, the way to go if there is one, within reach cells.
local function lineTo(s, x, y, reach)
  local p = s.player
  local dir
  if x == p.x and y ~= p.y then dir = p.y < y and "up" or "down" end
  if y == p.y and x ~= p.x then dir = p.x < x and "left" or "right" end
  if not dir or math.abs(p.x - x) + math.abs(p.y - y) > reach then return nil end
  while not (x == p.x and y == p.y) do
    if walled(s, x, y, dir) then return nil end
    x, y = ahead(x, y, dir)
  end
  return dir
end

M.lineTo = lineTo

--- The way an enemy strikes him from, if he's in its reach. Druaga reaches from all of the cells he fills.
local function reachOf(s, e, reach)
  local size = KINDS[e.kind].size or 1
  for dy = 0, size - 1 do
    for dx = 0, size - 1 do
      local dir = lineTo(s, e.x + dx, e.y + dy, reach)
      if dir then return dir end
    end
  end
end

--- Face him if there's a straight line, or else the way that's mostly towards him.
local function faceHim(s, e)
  local p = s.player
  local dx, dy = p.x - e.x, p.y - e.y
  if math.abs(dx) >= math.abs(dy) then
    e.dir = dx < 0 and "left" or "right"
  else
    e.dir = dy < 0 and "up" or "down"
  end
end

--- A step for an enemy. Stepping into him kills him unless his sword holds it off; only a wisp comes through a drawn sword.
local function stepInto(s, e, dir, events)
  local x, y = ahead(e.x, e.y, dir)
  local p = s.player
  e.dir = dir
  e.px, e.py = e.x, e.y
  if p.x == x and p.y == y then
    if KINDS[e.kind].class == "wisp" or not s.drawn then die(s, events, e.kind) end
    return
  end
  if KINDS[e.kind].class ~= "wisp" and enemyAt(s, x, y) then return end
  e.px, e.py, e.x, e.y = e.x, e.y, x, y
end

--- On along the corridor, back only at a dead end, and at a junction a leaning towards him.
local function wander(s, e, events, rng)
  local exits = {}
  for _, dir in ipairs(ORDER) do
    if dir ~= OPPOSITE[e.dir] and not walled(s, e.x, e.y, dir) then exits[#exits + 1] = dir end
  end
  if #exits == 0 then
    if walled(s, e.x, e.y, OPPOSITE[e.dir]) then return end
    exits[1] = OPPOSITE[e.dir]
  end
  local dir = exits[rng(#exits)]
  if #exits > 1 and rng(100) <= KINDS[e.kind].chase then
    local p = s.player
    local best
    for _, option in ipairs(exits) do
      local x, y = ahead(e.x, e.y, option)
      local gap = math.abs(x - p.x) + math.abs(y - p.y)
      if not best or gap < best then best, dir = gap, option end
    end
  end
  stepInto(s, e, dir, events)
end

local function speedOf(s, e)
  return KINDS[e.kind].speed + math.floor(s.level / 3)
end

--- Bank speed, and walk when there's a cell in the bank.
local function walkOn(s, e, events, rng)
  e.budget = e.budget + speedOf(s, e)
  while e.budget >= 100 and not s.after do
    e.budget = e.budget - 100
    wander(s, e, events, rng)
  end
end

--- Something with him in reach strikes on a beat. Into a drawn sword it costs him strength, and with it away his life.
local function duel(s, e, events)
  e.px, e.py = e.x, e.y
  e.clash = e.clash - 1
  if e.clash > 0 then return end
  e.clash = CLASH_TICKS
  if not s.drawn then
    die(s, events, e.kind)
    return
  end
  if s.safe > 0 then return end
  s.hp = s.hp - KINDS[e.kind].power
  events[#events + 1] = { type = "clash", kind = e.kind }
  if s.hp <= 0 then
    s.hp = 0
    die(s, events, e.kind)
  end
end

--- Slimes creep and red ones spit along a clear line.
local function stepSlime(s, e, events, rng)
  if KINDS[e.kind].spits then
    e.t = e.t - 1
    local dir = e.t <= 0 and lineTo(s, e.x, e.y, SPIT_REACH)
    if dir then
      castSpell(s, e.x, e.y, dir, "spell")
      e.t = SPIT_TICKS + rng(30)
      events[#events + 1] = { type = "spell" }
    end
  end
  walkOn(s, e, events, rng)
end

--- Knights stop to fight whatever comes in reach. A guard never leaves its post.
local function stepKnight(s, e, events, rng)
  if reachOf(s, e, 1) then
    duel(s, e, events)
    return
  end
  e.clash = CLASH_TICKS
  if not e.guard then walkOn(s, e, events, rng) end
end

--- Ropers creep, and lash further than anything else can.
local function stepRoper(s, e, events, rng)
  if reachOf(s, e, ROPER_REACH) then
    duel(s, e, events)
    return
  end
  e.clash = CLASH_TICKS
  walkOn(s, e, events, rng)
end

--- Dragons walk until he's along a clear line, then stand, breathe in, and breathe out a line of fire.
local function stepDragon(s, e, events, rng)
  if e.mode == "windup" then
    e.t = e.t - 1
    if e.t <= 0 then
      castSpell(s, e.x, e.y, e.dir, "fire")
      e.mode, e.t = "walk", 24 + rng(20)
      events[#events + 1] = { type = "fire" }
    end
    return
  end
  local close = reachOf(s, e, 1)
  if close then
    duel(s, e, events)
    return
  end
  e.clash = CLASH_TICKS
  e.t = e.t - 1
  local dir = e.t <= 0 and lineTo(s, e.x, e.y, FIRE_REACH)
  if dir then
    e.dir, e.mode, e.t, e.px, e.py = dir, "windup", WINDUP_TICKS, e.x, e.y
    events[#events + 1] = { type = "windup" }
    return
  end
  walkOn(s, e, events, rng)
end

--- A free cell for a mage, in line with him if it can find one, and never right beside him.
local function jumpCell(s, rng)
  local p = s.player
  local fallback
  for _ = 1, 40 do
    local x, y = rng(COLS), rng(ROWS)
    local gap = math.abs(x - p.x) + math.abs(y - p.y)
    if gap >= 3 and not enemyAt(s, x, y) then
      if lineTo(s, x, y, 9) then return x, y end
      fallback = fallback or { x, y }
    end
  end
  if fallback then return fallback[1], fallback[2] end
end

--- A mage waits, glows, casts, stays a moment, and jumps. A ghost mage is faded until it glows.
local function stepMage(s, e, events, rng)
  local k = KINDS[e.kind]
  e.t = e.t - 1
  if e.t > 0 then return end
  if e.mode == "wait" then
    e.mode, e.t, e.hidden = "cast", CAST_TICKS, false
    faceHim(s, e)
    events[#events + 1] = { type = "charge" }
  elseif e.mode == "cast" then
    castSpell(s, e.x, e.y, e.dir, "spell")
    e.mode, e.t = "rest", REST_TICKS
    events[#events + 1] = { type = "spell" }
  else
    local x, y = jumpCell(s, rng)
    if x then e.x, e.y, e.px, e.py = x, y, x, y end
    e.mode, e.t, e.hidden = "wait", math.max(10, k.every - s.level) + rng(10), k.fades == true
    events[#events + 1] = { type = "jump" }
  end
end

--- A spell out of each face of the two cell square he fills.
local function volley(s, e)
  castSpell(s, e.x, e.y, "up", "spell")
  castSpell(s, e.x + 1, e.y, "right", "spell")
  castSpell(s, e.x + 1, e.y + 1, "down", "spell")
  castSpell(s, e.x, e.y + 1, "left", "spell")
end

--- Druaga glows and fires all four ways, and after two volleys he moves to another spot in the room.
local function stepDruaga(s, e, events, rng)
  if reachOf(s, e, 1) then duel(s, e, events) else e.clash = CLASH_TICKS end
  if s.after then return end
  e.t = e.t - 1
  if e.t > 0 then return end
  if e.mode == "wait" then
    e.mode, e.t = "cast", CAST_TICKS
    events[#events + 1] = { type = "charge" }
  else
    volley(s, e)
    e.mode, e.t, e.volleys = "wait", 14 + rng(8), e.volleys + 1
    events[#events + 1] = { type = "spell" }
    if e.volleys % 2 == 0 then
      local spot = DRUAGA_SPOTS[rng(#DRUAGA_SPOTS)]
      local p = s.player
      local onHim = p.x >= spot[1] and p.x <= spot[1] + 1 and p.y >= spot[2] and p.y <= spot[2] + 1
      if not onHim then
        e.x, e.y, e.px, e.py = spot[1], spot[2], spot[1], spot[2]
        events[#events + 1] = { type = "jump" }
      end
    end
  end
end

--- Wisps keep a wall on their right hand, and neither sword nor shield can stop one.
local function stepWisp(s, e, events)
  e.budget = e.budget + speedOf(s, e)
  while e.budget >= 100 and not s.after do
    e.budget = e.budget - 100
    local dir = CLOCKWISE[e.dir]
    for _ = 1, 4 do
      if not walled(s, e.x, e.y, dir) then break end
      dir = OPPOSITE[CLOCKWISE[dir]]
    end
    stepInto(s, e, dir, events)
  end
end

--- Red wisps take the shortest way to him.
local function stepHunter(s, e, events, map)
  e.budget = e.budget + speedOf(s, e)
  while e.budget >= 100 and not s.after do
    e.budget = e.budget - 100
    local best, way
    for _, dir in ipairs(ORDER) do
      if not walled(s, e.x, e.y, dir) then
        local x, y = ahead(e.x, e.y, dir)
        if map[y][x] and (not best or map[y][x] < best) then best, way = map[y][x], dir end
      end
    end
    if way then stepInto(s, e, way, events) end
  end
end

local BEHAVIOUR = {
  slime = stepSlime, knight = stepKnight, roper = stepRoper, dragon = stepDragon, mage = stepMage, druaga = stepDruaga,
}

local function stepEnemies(s, events, rng)
  local map
  for _, e in ipairs(s.enemies) do
    if s.after then return end
    local k = KINDS[e.kind]
    if e.hit > 0 then e.hit = e.hit - 1 end
    if k.hunts then
      map = map or distances(s, s.player.x, s.player.y)
      stepHunter(s, e, events, map)
    elseif k.class == "wisp" then
      stepWisp(s, e, events)
    else
      BEHAVIOUR[k.class](s, e, events, rng)
    end
  end
end

--- Time is up: red wisps, one after another, from somewhere not too near.
local function stepSwarm(s, rng)
  s.swarmIn = s.swarmIn - 1
  if s.swarmIn > 0 or s.swarmed >= SWARM_MOST then return end
  s.swarmIn = SWARM_TICKS
  local map = distances(s, s.player.x, s.player.y)
  for _ = 1, 40 do
    local x, y = rng(COLS), rng(ROWS)
    if map[y][x] and map[y][x] >= 6 then
      s.swarmed = s.swarmed + 1
      s.enemies[#s.enemies + 1] = newEnemy(s, "hunter", x, y, rng)
      return
    end
  end
end

local function stepTimer(s, events, rng)
  if s.timer > 0 then
    s.timer = s.timer - 1
    if s.timer == 0 then
      setNote(s, "TIME IS UP")
      events[#events + 1] = { type = "timeUp" }
    end
  else
    stepSwarm(s, rng)
  end
end

-- ---------------------------------------------------------------- what he walks onto

local function giveItem(s, id, events)
  local item = ITEMS[id]
  local got = s.items
  if id == "pick" then got.pick = true end
  if id == "boots" then got.boots = true end
  if id == "balance" then got.balance = true end
  if id == "potion" then got.potions = math.min(MAX_POTIONS, got.potions + 1) end
  if item.sword then got.sword = math.max(got.sword, item.sword) end
  if item.shield then got.shield = math.max(got.shield, item.shield) end
  if item.points then s.score = s.score + item.points end
  setNote(s, item.name)
  events[#events + 1] = { type = "item", item = id }
end

--- The floors whose chests a door wants open, lowest first: the first one still shut is where he's sent back to.
local function zapFloor(s)
  for _, floor in ipairs(FLOORS[s.level].needs or {}) do
    if not s.opened[floor] then return floor end
  end
end

--- Through the door, with the key. On the last floor the door is Ki.
local function leaveFloor(s, events)
  local bonus = math.floor(s.timer / SECOND) * SECOND_SCORE
  s.score = s.score + CLEAR_SCORE + bonus
  s.pause, s.want = CLEAR_TICKS, false
  s.player.walk = false
  if s.level >= TOP then
    s.won, s.after = true, "won"
    s.score = s.score + WIN_SCORE
    events[#events + 1] = { type = "win" }
    return
  end
  s.after = "floor"
  local back = zapFloor(s)
  if back then
    s.zapTo = back
    setNote(s, "ZAP! BACK TO FLOOR " .. back)
    events[#events + 1] = { type = "zap", floor = back }
  else
    events[#events + 1] = { type = "clear", bonus = bonus }
  end
end

local function checkCells(s, events)
  if s.after then return end
  local p = s.player
  local key, door, chest = s.key, s.door, s.chest
  if not s.hasKey and not key.held and p.x == key.x and p.y == key.y then
    s.hasKey = true
    award(s, KEY_SCORE, p.x, p.y)
    events[#events + 1] = { type = "key" }
    local cond = FLOORS[s.level].cond
    if cond.type == "swift" and M.floorTicks(s.level) - s.timer <= cond.seconds * SECOND then reveal(s, events) end
  end
  if chest and chest.shown and p.x == chest.x and p.y == chest.y then
    s.opened[s.level] = true
    s.chest = nil
    s.score = s.score + CHEST_SCORE
    giveItem(s, chest.item, events)
  end
  if p.x == door.x and p.y == door.y then
    if s.hasKey then
      leaveFloor(s, events)
    elseif not s.knocked then
      s.knocked = true
      setNote(s, "THE DOOR IS LOCKED")
      events[#events + 1] = { type = "knock" }
    end
  end
  if s.chest and not s.chest.shown and conditionMet(s) then reveal(s, events) end
end

--- Short notes on the board, and the moments a potion keeps him safe.
local function runClocks(s)
  for _, list in ipairs({ s.popups, s.bursts }) do
    for i = #list, 1, -1 do
      list[i].left = list[i].left - 1
      if list[i].left <= 0 then table.remove(list, i) end
    end
  end
  if s.note then
    s.note.left = s.note.left - 1
    if s.note.left <= 0 then s.note = false end
  end
  if s.safe > 0 then s.safe = s.safe - 1 end
end

--- What comes after a pause: this floor again, the next one, the end.
local function endPause(s, events)
  local after = s.after
  s.after, s.ready = false, false
  if after == "life" then
    if s.lives <= 0 then
      s.over = true
      events[#events + 1] = { type = "over" }
    else
      enterFloor(s)
    end
  elseif after == "floor" then
    s.level = s.zapTo or s.level + 1
    enterFloor(s)
    events[#events + 1] = { type = "floor" }
  elseif after == "won" then
    s.over = true
    events[#events + 1] = { type = "over" }
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.frame = s.frame + 1
  if s.toggle then
    s.toggle, s.drawn = false, not s.drawn
    events[#events + 1] = { type = "sword", drawn = s.drawn }
  end
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause == 0 then
      if s.ready then s.ready = false else endPause(s, events) end
    end
    return events
  end
  runClocks(s)
  stepTimer(s, events, rng)
  stepPlayer(s, events)
  checkCells(s, events)
  stepSpells(s, events)
  stepEnemies(s, events, rng)
  checkCells(s, events)
  return events
end

-- ---------------------------------------------------------------- the bot

local BOT_LAPSE = 0.04     -- how often it stops looking, so its runs come to an end
local BOT_WISP = 3         -- steps from a wisp that make it run
local BOT_HURT = 20        -- strength under which it leaves the riddle and makes for the door
local BOT_SEARCH = 175     -- ticks left on the timer before it gives up on a riddle and goes for the door

--- The way a threat is coming from, and what it is, if a spell or a glowing mage has a clear line to him.
local function incoming(s)
  for _, spell in ipairs(s.spells) do
    if lineTo(s, spell.x, spell.y, 6) == spell.dir then return OPPOSITE[spell.dir], spell.kind end
  end
  for _, e in ipairs(s.enemies) do
    if (e.mode == "cast" or e.mode == "windup") and e.kind ~= "druaga" then
      local dir = reachOf(s, e, 9)
      if dir then return OPPOSITE[dir], e.mode == "windup" and "fire" or "spell" end
    end
  end
end

local function nearWisp(s, map)
  for _, e in ipairs(s.enemies) do
    local d = map[e.y] and map[e.y][e.x]
    if KINDS[e.kind].class == "wisp" and d and d <= BOT_WISP then return e end
  end
end

--- The open neighbouring cell furthest from this enemy, by the map of distances from it.
local function fleeFrom(s, e)
  local p = s.player
  local map = distances(s, e.x, e.y)
  local best, way = map[p.y][p.x] or -1, nil
  for _, dir in ipairs(ORDER) do
    if not walled(s, p.x, p.y, dir) then
      local x, y = ahead(p.x, p.y, dir)
      if (map[y][x] or -1) > best and not enemyAt(s, x, y) then best, way = map[y][x], dir end
    end
  end
  return way
end

--- A side step out of a line of fire.
local function sideStep(s, from)
  local p = s.player
  for _, dir in ipairs(ORDER) do
    if dir ~= from and dir ~= OPPOSITE[from] and not walled(s, p.x, p.y, dir) then return dir end
  end
  return not walled(s, p.x, p.y, OPPOSITE[from]) and OPPOSITE[from] or nil
end

--- Something it can fight, next to it.
local function adjacentFoe(s)
  local p = s.player
  for _, dir in ipairs(ORDER) do
    if not walled(s, p.x, p.y, dir) then
      local x, y = ahead(p.x, p.y, dir)
      local e = enemyAt(s, x, y)
      if e and KINDS[e.kind].class ~= "wisp" then return e, dir end
    end
  end
end

--- The nearest enemy the riddle asks for.
local function riddleFoe(s, cond, map)
  local best, bestDistance
  for _, e in ipairs(s.enemies) do
    local class = KINDS[e.kind].class
    local wanted = (cond.type == "slimes" and class == "slime") or (cond.type == "knights" and class == "knight")
      or (cond.type == "kill" and e.kind == cond.kind) or (class == "druaga")
    local d = map[e.y] and map[e.y][e.x]
    if wanted and d and not e.hidden and (not best or d < bestDistance) then best, bestDistance = e, d end
  end
  return best
end

--- A cell beside a walled up chest, and the way to swing from it.
local function besideVault(s, chest, map)
  local best, bx, by, way
  for _, dir in ipairs(ORDER) do
    local x, y = ahead(chest.x, chest.y, dir)
    if x >= 1 and x <= COLS and y >= 1 and y <= ROWS and map[y][x] and (not best or map[y][x] < best) then
      best, bx, by, way = map[y][x], x, y, OPPOSITE[dir]
    end
  end
  return bx, by, way
end

--- The cell it wants to be on. A riddle comes first while there's time, then the key, then the door.
local function goalOf(s, map)
  local chest = s.chest
  local cond = FLOORS[s.level].cond
  if chest and chest.shown then
    if map[chest.y][chest.x] then return chest.x, chest.y end
    if s.items.pick and s.picks > 0 then return besideVault(s, chest, map) end
  end
  if s.key.held or (chest and not chest.shown and s.timer > BOT_SEARCH and s.hp >= BOT_HURT) then
    local foe = riddleFoe(s, cond, map)
    -- his volleys pinwheel out of his four faces, and the cell left of his top corner is out of all of them
    if foe and foe.kind == "druaga" then return foe.x - 1, foe.y end
    if foe then return foe.x, foe.y end
    if cond.type == "spot" then return cond.x, cond.y end
    if cond.type == "knock" and not s.knocked then return s.door.x, s.door.y end
  end
  if not s.hasKey and not s.key.held then return s.key.x, s.key.y end
  return s.door.x, s.door.y
end

--- A step that closes on a cell, by the map drawn from it.
local function stepToward(s, x, y)
  local p = s.player
  local map = distances(s, x, y)
  local here = map[p.y][p.x]
  if not here then return nil end
  for _, dir in ipairs(ORDER) do
    if not walled(s, p.x, p.y, dir) then
      local nx, ny = ahead(p.x, p.y, dir)
      local e = enemyAt(s, nx, ny)
      local deadly = e and KINDS[e.kind].class == "wisp"
      if map[ny][nx] and map[ny][nx] < here and not deadly then return dir end
    end
  end
end

local function turn(s, dir)
  if not dir or (s.want == dir) or (s.player.walk == dir and not s.want) then return nil end
  return { kind = "turn", dir = dir }
end

--- A good but human player for the idle screen and tests: it answers spells with the shield, and otherwise keeps its sword out.
function M.bot(s, rng)
  if s.pause > 0 or s.after then return nil end
  if rng() < BOT_LAPSE then return nil end
  local p = s.player
  local map = distances(s, p.x, p.y)
  local from, what = incoming(s)
  local foe, dir = adjacentFoe(s)
  if from and not (foe and foe.kind == "druaga") then
    if what == "fire" and s.items.shield < 2 then return turn(s, sideStep(s, from)) end
    if s.drawn then return { kind = "sword" } end
    if p.dir ~= from then
      if walled(s, p.x, p.y, from) then return nil end
      return turn(s, from)
    end
    return nil
  end
  local wisp = nearWisp(s, map)
  if wisp then
    local way = fleeFrom(s, wisp)
    if way then return turn(s, way) end
  end
  if not s.drawn then return { kind = "sword" } end
  if foe then return turn(s, dir) end
  local x, y, swing = goalOf(s, map)
  if swing and p.x == x and p.y == y then
    if p.dir == swing and walled(s, p.x, p.y, swing) then return { kind = "turn", dir = swing } end
    return turn(s, swing)
  end
  return turn(s, stepToward(s, x, y))
end

return M
