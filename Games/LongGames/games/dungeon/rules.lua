-- games/dungeon/rules.lua
-- A first-person dungeon crawl, one character, ten depths. It works in steps: a monster acts when the player acts, so the
-- clock only runs a queue of taps. Turning takes no time, which keeps a potion within reach in a fight.
-- The state is plain data, so it can be saved: map rows are strings, and every table appears once.

local M = {}

local floor, max, min = math.floor, math.max, math.min

local WIDTH, HEIGHT = 21, 21
local DEPTHS = 10
local WALL, OPEN, DOOR, LOCKED, STAIRS = "#", ".", "+", "L", ">"

M.WIDTH, M.HEIGHT, M.DEPTHS = WIDTH, HEIGHT, DEPTHS
M.WALL, M.OPEN, M.DOOR, M.LOCKED, M.STAIRS = WALL, OPEN, DOOR, LOCKED, STAIRS

-- Facings run clockwise from north: x grows east and y grows south.
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
M.DIRS = DIRS

local START_HP, START_ATTACK = 32, 4
local HIT_CHANCE, BAT_HIT_CHANCE, MONSTER_HIT_CHANCE = 85, 70, 78 -- percent
local POTION_HEAL = 18
local HEAL_EVERY = 3          -- steps walked for each HP back
local WAKE_RANGE = 7          -- how many steps away a monster notices the player
local SIGHT = 5               -- squares of corridor the player can see ahead
local QUEUE_LONGEST = 2       -- taps waiting for the clock
local TIRED_AFTER = 170       -- steps on a level before the bot heads for the stairs
local FLASH_TICKS, HURT_TICKS, BANNER_TICKS = 2, 3, 12
local DEPTH_SCORE, KILL_SCORE, WIN_SCORE = 100, 5, 5000

-- hp, attack, defence and xp at the depth a monster first shows up. move: "chase", "flit" or "slow", and "drift" passes doors.
local MONSTERS = {
  rat = { name = "GIANT RAT", hp = 6, attack = 2, defence = 0, xp = 3, gold = 2, first = 1, move = "chase" },
  bat = { name = "CAVE BAT", hp = 5, attack = 2, defence = 0, xp = 3, gold = 1, first = 1, move = "flit" },
  slime = { name = "SLIME", hp = 15, attack = 4, defence = 1, xp = 7, gold = 5, first = 2, move = "slow" },
  skeleton = { name = "SKELETON", hp = 19, attack = 5, defence = 1, xp = 12, gold = 8, first = 3, move = "chase" },
  orc = { name = "ORC", hp = 30, attack = 9, defence = 2, xp = 20, gold = 14, first = 5, move = "chase" },
  ghost = { name = "GHOST", hp = 28, attack = 11, defence = 3, xp = 28, gold = 10, first = 6, move = "drift" },
  dragon = { name = "THE DRAGON", hp = 150, attack = 14, defence = 5, xp = 300, gold = 500, first = 10, move = "chase" },
}
M.MONSTERS = MONSTERS

-- Who lives where: each name is one chance in that depth's draw.
local DENIZENS = {
  { "rat", "rat", "rat", "bat" },
  { "rat", "bat", "slime", "slime" },
  { "bat", "slime", "skeleton" },
  { "slime", "skeleton", "skeleton" },
  { "skeleton", "orc", "orc" },
  { "skeleton", "orc", "ghost" },
  { "orc", "orc", "ghost" },
  { "orc", "ghost", "ghost" },
  { "ghost", "ghost", "orc" },
  { "ghost", "orc", "orc" },
}

local SWORDS = {
  { name = "DAGGER", bonus = 0 }, { name = "SHORT SWORD", bonus = 2 }, { name = "LONG SWORD", bonus = 4 },
  { name = "BROADSWORD", bonus = 7 }, { name = "RUNE BLADE", bonus = 11 },
}
local ARMOURS = {
  { name = "RAGS", bonus = 0 }, { name = "LEATHER", bonus = 1 }, { name = "CHAIN MAIL", bonus = 3 },
  { name = "PLATE", bonus = 5 }, { name = "DRAGON PLATE", bonus = 7 },
}
M.SWORDS, M.ARMOURS = SWORDS, ARMOURS

-- ---------------------------------------------------------------- the map

local function inside(x, y) return x >= 1 and x <= WIDTH and y >= 1 and y <= HEIGHT end

--- The tile at x, y. Everything off the map is wall.
local function tileAt(s, x, y)
  if not inside(x, y) then return WALL end
  return s.tiles[y]:sub(x, x)
end
M.tileAt = tileAt

local function setRow(rows, x, y, c)
  local row = rows[y]
  rows[y] = row:sub(1, x - 1) .. c .. row:sub(x + 1)
end

local function setTile(s, x, y, c) setRow(s.tiles, x, y, c) end

local function shuffle(list, rng)
  for i = #list, 2, -1 do
    local j = rng(i)
    list[i], list[j] = list[j], list[i]
  end
end

local function emptyGrid()
  local grid = {}
  for y = 1, HEIGHT do
    grid[y] = {}
    for x = 1, WIDTH do grid[y][x] = WALL end
  end
  return grid
end

--- Rooms sit on even squares with odd sizes, so a maze between them lines up. A wanted room goes first if there is one.
local function placeRooms(grid, depth, rng, regions)
  local rooms = {}
  local wanted = 4 + rng(3)
  local function fits(room)
    for _, o in ipairs(rooms) do
      if room.x <= o.x + o.w and o.x <= room.x + room.w and room.y <= o.y + o.h and o.y <= room.y + room.h then return false end
    end
    return true
  end
  for try = 1, 60 do
    if #rooms >= wanted then break end
    local big = depth == DEPTHS and try == 1
    local w, h = big and 7 or rng(3) * 2 + 1, big and 7 or rng(3) * 2 + 1
    local room = { x = 2 * rng((WIDTH - w) / 2), y = 2 * rng((HEIGHT - h) / 2), w = w, h = h }
    if fits(room) then
      rooms[#rooms + 1] = room
      for y = room.y, room.y + h - 1 do
        for x = room.x, room.x + w - 1 do
          grid[y][x] = OPEN
          regions[y * WIDTH + x] = #rooms
        end
      end
    end
  end
  return rooms
end

--- Fill every even square the rooms left with winding corridors, one region for each separate maze.
local function carveMazes(grid, rng, regions, region)
  for sy = 2, HEIGHT - 1, 2 do
    for sx = 2, WIDTH - 1, 2 do
      if grid[sy][sx] == WALL then
        region = region + 1
        grid[sy][sx] = OPEN
        regions[sy * WIDTH + sx] = region
        local stack = { { sx, sy } }
        while #stack > 0 do
          local at = stack[#stack]
          local ways = { 1, 2, 3, 4 }
          shuffle(ways, rng)
          local moved = false
          for _, way in ipairs(ways) do
            local d = DIRS[way]
            local nx, ny = at[1] + d[1] * 2, at[2] + d[2] * 2
            if nx >= 2 and nx < WIDTH and ny >= 2 and ny < HEIGHT and grid[ny][nx] == WALL then
              grid[at[2] + d[2]][at[1] + d[1]] = OPEN
              grid[ny][nx] = OPEN
              regions[(at[2] + d[2]) * WIDTH + at[1] + d[1]] = region
              regions[ny * WIDTH + nx] = region
              stack[#stack + 1] = { nx, ny }
              moved = true
              break
            end
          end
          if not moved then stack[#stack] = nil end
        end
      end
    end
  end
  return region
end

--- Knock through the wall between regions until they are all one, as doors where they meet a room, with a loop or two.
local function connect(grid, rng, regions, roomCount, regionCount)
  local joined = {}
  for i = 1, regionCount do joined[i] = i end
  local function root(i)
    while joined[i] ~= i do i = joined[i] end
    return i
  end
  local links = {}
  for y = 2, HEIGHT - 1 do
    for x = 2, WIDTH - 1 do
      if grid[y][x] == WALL then
        local a, b
        if grid[y][x - 1] == OPEN and grid[y][x + 1] == OPEN then
          a, b = regions[y * WIDTH + x - 1], regions[y * WIDTH + x + 1]
        elseif grid[y - 1][x] == OPEN and grid[y + 1][x] == OPEN then
          a, b = regions[(y - 1) * WIDTH + x], regions[(y + 1) * WIDTH + x]
        end
        if a and a ~= b then links[#links + 1] = { x = x, y = y, a = a, b = b } end
      end
    end
  end
  shuffle(links, rng)
  for _, link in ipairs(links) do
    local ra, rb = root(link.a), root(link.b)
    local room = link.a <= roomCount or link.b <= roomCount
    if ra ~= rb then
      joined[ra] = rb
      grid[link.y][link.x] = (room and rng(4) > 1) and DOOR or OPEN
    elseif rng(14) == 1 then
      grid[link.y][link.x] = room and DOOR or OPEN
    end
  end
end

local function isOpenCell(c) return c == OPEN or c == DOOR end

local function openNeighbours(grid, x, y)
  local count = 0
  for _, d in ipairs(DIRS) do
    local row = grid[y + d[2]]
    if row and isOpenCell(row[x + d[1]]) then count = count + 1 end
  end
  return count
end

--- Cut back the dead ends for a few rounds, so the maze is corridors and not a thicket. A dead end has one way out, so
-- this can't cut anything off.
local function prune(grid, rounds)
  for _ = 1, rounds do
    local ends = {}
    for y = 2, HEIGHT - 1 do
      for x = 2, WIDTH - 1 do
        if isOpenCell(grid[y][x]) and openNeighbours(grid, x, y) <= 1 then ends[#ends + 1] = { x, y } end
      end
    end
    for _, at in ipairs(ends) do grid[at[2]][at[1]] = WALL end
  end
end

--- A door with no wall on both sides looks wrong in the first-person view, so it becomes plain floor.
local function tidyDoors(grid)
  for y = 2, HEIGHT - 1 do
    for x = 2, WIDTH - 1 do
      if grid[y][x] == DOOR then
        local across = grid[y][x - 1] == WALL and grid[y][x + 1] == WALL
        local along = grid[y - 1][x] == WALL and grid[y + 1][x] == WALL
        if not (across or along) then grid[y][x] = OPEN end
      end
    end
  end
end

--- Steps from x, y to every tile that can be walked to. blocked(tile, x, y) stops a tile; the default stops walls.
-- Returns a distance by square key, and the squares in the order they were reached.
local function flood(grid, x, y, blocked)
  local dist = { [y * WIDTH + x] = 0 }
  local order = { { x, y } }
  local head = 1
  while order[head] do
    local at = order[head]
    head = head + 1
    local steps = dist[at[2] * WIDTH + at[1]]
    for _, d in ipairs(DIRS) do
      local nx, ny = at[1] + d[1], at[2] + d[2]
      local key = ny * WIDTH + nx
      local row = grid[ny]
      local c = row and row[nx]
      if c and not dist[key] and c ~= WALL and c ~= STAIRS and not (blocked and blocked(c, nx, ny)) then
        dist[key] = steps + 1
        order[#order + 1] = { nx, ny }
      end
    end
  end
  return dist, order
end

--- Set the stairs into a wall beside the far end of the walk, where they take nothing from the maze.
local function placeStairs(grid, order)
  for i = #order, 1, -1 do
    local at = order[i]
    if grid[at[2]][at[1]] == OPEN then
      for _, d in ipairs(DIRS) do
        local x, y = at[1] + d[1], at[2] + d[2]
        if x > 1 and x < WIDTH and y > 1 and y < HEIGHT and grid[y][x] == WALL and openNeighbours(grid, x, y) == 1 then
          grid[y][x] = STAIRS
          return x, y
        end
      end
    end
  end
end

--- Lock one door that really shuts something off, leaving plenty of the level on the near side for its key.
-- Returns the near side as a list of squares, or nil with no such door.
local function lockDoor(grid, startX, startY, rng)
  local doors = {}
  for y = 2, HEIGHT - 1 do
    for x = 2, WIDTH - 1 do
      if grid[y][x] == DOOR then doors[#doors + 1] = { x, y } end
    end
  end
  shuffle(doors, rng)
  local _, all = flood(grid, startX, startY)
  for _, at in ipairs(doors) do
    local _, near = flood(grid, startX, startY, function(_, x, y) return x == at[1] and y == at[2] end)
    if #near >= 20 and #near < #all - 1 then
      grid[at[2]][at[1]] = LOCKED
      return near
    end
  end
  return nil
end

local function roomCentre(room)
  return room.x + floor(room.w / 2), room.y + floor(room.h / 2)
end

-- ---------------------------------------------------------------- filling a level

local function newMonster(kind, x, y, depth)
  local def = MONSTERS[kind]
  local growth = 1 + (depth - def.first) * 0.15
  local hp = kind == "dragon" and def.hp or floor(def.hp * growth + 0.5)
  return {
    kind = kind, x = x, y = y, hp = hp, maxHp = hp, attack = floor(def.attack * growth + 0.5), defence = def.defence,
    xp = floor(def.xp * growth + 0.5), awake = kind == "dragon", turns = 0,
  }
end
M.newMonster = newMonster

--- What a chest holds. Better gear turns up as the depths go on: below the first, one chest on a level always has some.
local function chestLoot(depth, rng, gear)
  local loot = {}
  local roll = rng(100)
  if gear then
    loot.kind = depth % 2 == 0 and "sword" or "armour"
    loot.tier = min(1 + floor(depth / 2), 5)
  elseif roll <= 45 then
    loot.kind, loot.amount = "gold", 15 + rng(20) * depth
  elseif roll <= 65 then
    loot.kind = "potion"
  else
    loot.kind = rng(2) == 1 and "sword" or "armour"
    loot.tier = min(1 + max(1, floor((depth + rng(3) - 1) / 2)), 5)
  end
  if rng(6) == 1 then loot.trap = 2 + depth end
  return loot
end

local function addObject(level, x, y, fields)
  fields.x, fields.y = x, y
  level.objs[#level.objs + 1] = fields
end

--- Scatter everything over the squares far enough from the start to be fair. spots holds them in random order.
local function furnish(level, grid, depth, startX, startY, near, rng)
  local dist, order = flood(grid, startX, startY)
  local spots = {}
  for _, at in ipairs(order) do
    if grid[at[2]][at[1]] == OPEN and dist[at[2] * WIDTH + at[1]] >= 3 then spots[#spots + 1] = at end
  end
  shuffle(spots, rng)
  local taken = {}
  local function take(from)
    while from[#from] do
      local at = from[#from]
      from[#from] = nil
      if not taken[at[2] * WIDTH + at[1]] then
        taken[at[2] * WIDTH + at[1]] = true
        return at[1], at[2]
      end
    end
  end
  if near then
    local nearSpots = {}
    for _, at in ipairs(near) do
      if grid[at[2]][at[1]] == OPEN and not (at[1] == startX and at[2] == startY) then nearSpots[#nearSpots + 1] = at end
    end
    shuffle(nearSpots, rng)
    local x, y = take(nearSpots)
    addObject(level, x, y, { kind = "key" })
  end
  for i = 1, 3 + rng(2) do
    local x, y = take(spots)
    if not x then break end
    addObject(level, x, y, { kind = "chest", loot = chestLoot(depth, rng, i == 1 and depth > 1) })
  end
  for _ = 1, 3 + rng(3) do
    local x, y = take(spots)
    if not x then break end
    addObject(level, x, y, { kind = "gold", amount = 5 + rng(10) * depth })
  end
  for _ = 1, rng(2) do
    local x, y = take(spots)
    if not x then break end
    addObject(level, x, y, { kind = "potion" })
  end
  for _ = 1, 1 + floor(depth / 3) + rng(2) do
    local x, y = take(spots)
    if not x then break end
    addObject(level, x, y, { kind = "trap", damage = 2 + depth + rng(3) })
  end
  local names = DENIZENS[depth]
  for _ = 1, 5 + floor(depth / 2) do
    local x, y = take(spots)
    if not x then break end
    level.mons[#level.mons + 1] = newMonster(names[rng(#names)], x, y, depth)
  end
end

--- One whole depth: { tiles, seen, mons, objs, x, y, dir }. tiles and seen are rows of characters.
local function buildLevel(depth, rng)
  local grid, regions = emptyGrid(), {}
  local rooms = placeRooms(grid, depth, rng, regions)
  local regionCount = carveMazes(grid, rng, regions, #rooms)
  connect(grid, rng, regions, #rooms, regionCount)
  prune(grid, 4)
  tidyDoors(grid)
  -- the boss room is the first one placed, so the walk starts from the last
  local startX, startY = roomCentre(rooms[depth == DEPTHS and #rooms or 1])
  local level = { mons = {}, objs = {}, tiles = {}, seen = {} }
  local _, order = flood(grid, startX, startY)
  if depth < DEPTHS then
    level.stairsX, level.stairsY = placeStairs(grid, order)
  end
  local near = depth > 1 and rng(5) > 1 and lockDoor(grid, startX, startY, rng) or nil
  furnish(level, grid, depth, startX, startY, near, rng)
  if depth == DEPTHS then
    local x, y = roomCentre(rooms[1])
    for i = #level.mons, 1, -1 do
      if level.mons[i].x == x and level.mons[i].y == y then table.remove(level.mons, i) end
    end
    for i = #level.objs, 1, -1 do
      if level.objs[i].x == x and level.objs[i].y == y then table.remove(level.objs, i) end
    end
    level.mons[#level.mons + 1] = newMonster("dragon", x, y, depth)
  end
  for y = 1, HEIGHT do
    level.tiles[y] = table.concat(grid[y])
    level.seen[y] = string.rep("0", WIDTH)
  end
  level.x, level.y, level.dir = startX, startY, rng(4)
  return level
end

-- ---------------------------------------------------------------- looking around

local function monsterAt(s, x, y)
  for _, m in ipairs(s.mons) do
    if m.x == x and m.y == y then return m end
  end
  return nil
end
M.monsterAt = monsterAt

local function chestAt(s, x, y)
  for _, o in ipairs(s.objs) do
    if o.kind == "chest" and o.x == x and o.y == y and not o.opened then return o end
  end
  return nil
end
M.chestAt = chestAt

--- The square ahead of the player.
local function ahead(s)
  local d = DIRS[s.dir]
  return s.x + d[1], s.y + d[2]
end
M.ahead = ahead

local function walkable(s, x, y)
  return tileAt(s, x, y) == OPEN and not monsterAt(s, x, y) and not chestAt(s, x, y)
end

--- What ACT would do right now: "attack", "door", "locked", "chest", "stairs", or nil with nothing ahead.
function M.target(s)
  local x, y = ahead(s)
  if monsterAt(s, x, y) then return "attack" end
  local c = tileAt(s, x, y)
  if c == DOOR then return "door" end
  if c == LOCKED then return "locked" end
  if c == STAIRS then return "stairs" end
  if chestAt(s, x, y) then return "chest" end
  return nil
end

local function see(s, x, y)
  if inside(x, y) and s.seen[y]:sub(x, x) == "0" then setRow(s.seen, x, y, "1") end
end

local function seeThrough(s, x, y) return tileAt(s, x, y) == OPEN end

--- Mark what's in view on the automap: straight ahead, and out to each side of that until a wall stops the eye.
local function reveal(s)
  local d = DIRS[s.dir]
  local sideX, sideY = -d[2], d[1]
  for _, n in ipairs(DIRS) do see(s, s.x + n[1], s.y + n[2]) end
  for r = 0, SIGHT do
    local cx, cy = s.x + d[1] * r, s.y + d[2] * r
    see(s, cx, cy)
    if not seeThrough(s, cx, cy) then break end
    for way = -1, 1, 2 do
      for l = 1, min(r + 1, 4) do
        local x, y = cx + sideX * l * way, cy + sideY * l * way
        see(s, x, y)
        if not seeThrough(s, x, y) then break end
      end
    end
  end
end

local function say(s, text)
  s.msg = text
end

local function changed(s) s.rev = s.rev + 1 end

local function loadLevel(s, depth, rng)
  local level = buildLevel(depth, rng)
  s.level, s.tiles, s.seen, s.mons, s.objs = depth, level.tiles, level.seen, level.mons, level.objs
  s.x, s.y, s.dir = level.x, level.y, level.dir
  s.moves = 0
  s.fx.banner = BANNER_TICKS
  reveal(s)
end

-- ---------------------------------------------------------------- the player

--- XP needed to leave a character level.
local function xpFor(lvl) return 10 * lvl * lvl + 12 * lvl end
M.xpFor = xpFor

local function gainXp(s, amount, events)
  local p = s.p
  p.xp = p.xp + amount
  while p.xp >= xpFor(p.lvl) do
    p.xp = p.xp - xpFor(p.lvl)
    p.lvl = p.lvl + 1
    p.maxHp = p.maxHp + 8
    p.hp = min(p.maxHp, p.hp + 12)
    p.attack = p.attack + 1
    say(s, "You reach level " .. p.lvl .. "! You feel stronger.")
    events[#events + 1] = { type = "levelup", lvl = p.lvl }
  end
end

local function addScore(s, points) s.score = s.score + points end

local function hurt(s, amount, why, events)
  local p = s.p
  p.hp = max(0, p.hp - amount)
  s.fx.hurt = HURT_TICKS
  if p.hp == 0 then
    s.over = true
    s.killer = why
    say(s, "You die on depth " .. s.level .. ", killed by " .. why .. ".")
    events[#events + 1] = { type = "death" }
  end
end

local function takeGold(s, amount, events)
  s.p.gold = s.p.gold + amount
  addScore(s, amount)
  events[#events + 1] = { type = "gold", amount = amount }
end

local function takeGear(s, o, events)
  local p = s.p
  local list = o.kind == "sword" and SWORDS or ARMOURS
  local have = o.kind == "sword" and p.sword or p.armour
  local item = list[o.tier]
  if o.tier > have then
    if o.kind == "sword" then p.sword = o.tier else p.armour = o.tier end
    say(s, "You find the " .. item.name .. "!")
    events[#events + 1] = { type = "gear", kind = o.kind }
  else
    say(s, "You find a " .. item.name .. ", no better than yours. Sold.")
    takeGold(s, 10 * o.tier, events)
  end
end

--- Put a found thing in the pack.
local function collect(s, o, events)
  local p = s.p
  if o.kind == "gold" then
    takeGold(s, o.amount, events)
    say(s, "You find " .. o.amount .. " gold.")
  elseif o.kind == "potion" then
    p.potions = p.potions + 1
    say(s, "You find a healing potion.")
    events[#events + 1] = { type = "potion" }
  elseif o.kind == "key" then
    p.keys = p.keys + 1
    say(s, "You find a key.")
    events[#events + 1] = { type = "key" }
  else
    takeGear(s, o, events)
  end
end

--- Pick up what lies on the player's square. A trap goes off once.
local function pickUp(s, events)
  for i = #s.objs, 1, -1 do
    local o = s.objs[i]
    if o.x == s.x and o.y == s.y and not (o.kind == "chest") then
      table.remove(s.objs, i)
      if o.kind == "trap" then
        say(s, "A trap! Spikes spring from the floor for " .. o.damage .. ".")
        events[#events + 1] = { type = "trap" }
        hurt(s, o.damage, "a trap", events)
        if s.over then return end
      else
        collect(s, o, events)
      end
    end
  end
end

local function attackPower(p) return p.attack + SWORDS[p.sword].bonus end
local function armourOf(p) return ARMOURS[p.armour].bonus end
M.attackPower, M.armourOf = attackPower, armourOf

-- ---------------------------------------------------------------- monsters

--- Steps from the player to everything a monster can walk to, as far as a monster could care about.
local function chaseField(s)
  local dist = { [s.y * WIDTH + s.x] = 0 }
  local order = { { s.x, s.y } }
  local head = 1
  while order[head] do
    local at = order[head]
    head = head + 1
    local steps = dist[at[2] * WIDTH + at[1]]
    if steps < WAKE_RANGE + 3 then
      for _, d in ipairs(DIRS) do
        local nx, ny = at[1] + d[1], at[2] + d[2]
        local key = ny * WIDTH + nx
        if not dist[key] and tileAt(s, nx, ny) == OPEN then
          dist[key] = steps + 1
          order[#order + 1] = { nx, ny }
        end
      end
    end
  end
  return dist
end

local function monsterHit(s, m, rng, events)
  local def = MONSTERS[m.kind]
  local p = s.p
  if rng(100) > MONSTER_HIT_CHANCE then
    say(s, "The " .. def.name .. " misses you.")
    events[#events + 1] = { type = "dodge" }
    return
  end
  local damage = max(1, m.attack + rng(3) - 2 - armourOf(p))
  say(s, "The " .. def.name .. " hits you for " .. damage .. ".")
  events[#events + 1] = { type = "hurt", amount = damage }
  hurt(s, damage, "a " .. def.name, events)
end

local function canEnter(s, m, x, y)
  if x == s.x and y == s.y then return false end
  if monsterAt(s, x, y) or chestAt(s, x, y) then return false end
  local c = tileAt(s, x, y)
  return c == OPEN or (m.kind == "ghost" and c == DOOR)
end

--- Move one square closer to the player, or anywhere for a bat that lost its way.
local function moveMonster(s, m, field, rng)
  local here = field[m.y * WIDTH + m.x]
  local bestX, bestY, best
  local flit = MONSTERS[m.kind].move == "flit" and rng(2) == 1
  local start = rng(4)
  for i = 0, 3 do
    local d = DIRS[(start + i) % 4 + 1]
    local x, y = m.x + d[1], m.y + d[2]
    if canEnter(s, m, x, y) then
      local steps = field[y * WIDTH + x]
      if m.kind == "ghost" then steps = math.abs(x - s.x) + math.abs(y - s.y) end
      if flit then steps = i end
      if steps and (not best or steps < best) and (flit or not here or steps < here or m.kind == "ghost") then
        bestX, bestY, best = x, y, steps
      end
    end
  end
  if bestX then m.x, m.y = bestX, bestY end
end

local function nextTo(s, m) return math.abs(m.x - s.x) + math.abs(m.y - s.y) == 1 end

--- The dragon breathes down a clear straight line, every third turn.
local function breathes(s, m)
  if m.kind ~= "dragon" or m.turns % 3 ~= 0 then return false end
  local dx, dy = s.x - m.x, s.y - m.y
  if (dx ~= 0 and dy ~= 0) or math.abs(dx) + math.abs(dy) > 4 then return false end
  local stepX, stepY = dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1)
  local x, y = m.x + stepX, m.y + stepY
  while x ~= s.x or y ~= s.y do
    if tileAt(s, x, y) ~= OPEN then return false end
    x, y = x + stepX, y + stepY
  end
  return true
end

local function breathe(s, m, rng, events)
  local damage = max(4, m.attack + rng(4) - armourOf(s.p))
  s.fx.fire = HURT_TICKS
  say(s, "The DRAGON breathes fire for " .. damage .. "!")
  events[#events + 1] = { type = "fire", amount = damage }
  hurt(s, damage, "dragon fire", events)
end

--- Every monster's turn, after anything the player does that takes time.
local function monstersAct(s, rng, events)
  local field = chaseField(s)
  for _, m in ipairs(s.mons) do
    if s.over then break end
    local steps = field[m.y * WIDTH + m.x]
    if not m.awake and steps and steps <= WAKE_RANGE then m.awake = true end
    if m.awake then
      m.turns = m.turns + 1
      local slow = MONSTERS[m.kind].move == "slow" and m.turns % 2 == 0
      if breathes(s, m) then
        breathe(s, m, rng, events)
      elseif not slow then
        if nextTo(s, m) then monsterHit(s, m, rng, events) else moveMonster(s, m, field, rng) end
      end
    end
  end
end

-- ---------------------------------------------------------------- what the player can do

local function win(s, events)
  s.over, s.won = true, true
  addScore(s, WIN_SCORE + s.p.hp * 10)
  say(s, "The dragon is dead. The dungeon is yours!")
  events[#events + 1] = { type = "win" }
end

local function beat(s, m, events)
  local def = MONSTERS[m.kind]
  for i, other in ipairs(s.mons) do
    if other == m then table.remove(s.mons, i) break end
  end
  s.p.kills = s.p.kills + 1
  addScore(s, m.xp * KILL_SCORE)
  say(s, "You defeat the " .. def.name .. "! +" .. m.xp .. " XP")
  events[#events + 1] = { type = "kill", kind = m.kind }
  gainXp(s, m.xp, events)
  if m.kind == "dragon" then
    win(s, events)
  else
    addObject(s, m.x, m.y, { kind = "gold", amount = def.gold + s.level })
  end
end

local function attack(s, m, rng, events)
  local def = MONSTERS[m.kind]
  local chance = def.move == "flit" and BAT_HIT_CHANCE or HIT_CHANCE
  if rng(100) > chance then
    say(s, "You swing at the " .. def.name .. " and miss.")
    events[#events + 1] = { type = "miss" }
  else
    local damage = max(1, attackPower(s.p) + rng(3) - 1 - m.defence)
    m.hp = m.hp - damage
    s.fx.flash = FLASH_TICKS
    say(s, "You hit the " .. def.name .. " for " .. damage .. ".")
    events[#events + 1] = { type = "hit", amount = damage, kind = m.kind }
    if m.hp <= 0 then beat(s, m, events) end
  end
  if not s.over then monstersAct(s, rng, events) end
end

local function descend(s, rng, events)
  local depth = s.level + 1
  loadLevel(s, depth, rng)
  addScore(s, DEPTH_SCORE * depth)
  say(s, "You climb down to depth " .. depth .. ".")
  events[#events + 1] = { type = "descend", depth = depth }
end

local function openChest(s, o, rng, events)
  o.opened = true
  events[#events + 1] = { type = "chest" }
  collect(s, o.loot, events)
  if o.loot.trap then
    say(s, "The chest was trapped! It bites for " .. o.loot.trap .. ".")
    events[#events + 1] = { type = "trap" }
    hurt(s, o.loot.trap, "a trapped chest", events)
  end
  if not s.over then monstersAct(s, rng, events) end
end

local function drink(s, rng, events)
  local p = s.p
  p.potions = p.potions - 1
  local healed = min(p.maxHp - p.hp, POTION_HEAL + p.lvl * 2)
  p.hp = p.hp + healed
  say(s, "You drink a potion and recover " .. healed .. " HP.")
  events[#events + 1] = { type = "drink", amount = healed }
  monstersAct(s, rng, events)
end

--- ACT: whatever is straight ahead, or the choice of a potion with nothing there.
local function act(s, rng, events)
  local x, y = ahead(s)
  local target = M.target(s)
  if target == "attack" then
    attack(s, monsterAt(s, x, y), rng, events)
  elseif target == "door" then
    setTile(s, x, y, OPEN)
    say(s, "The door creaks open.")
    events[#events + 1] = { type = "door" }
    reveal(s)
    monstersAct(s, rng, events)
  elseif target == "locked" then
    if s.p.keys > 0 then
      s.p.keys = s.p.keys - 1
      setTile(s, x, y, OPEN)
      say(s, "Your key turns in the lock.")
      events[#events + 1] = { type = "unlock" }
      reveal(s)
      monstersAct(s, rng, events)
    else
      say(s, "Locked. There must be a key somewhere.")
      events[#events + 1] = { type = "bump" }
    end
  elseif target == "chest" then
    openChest(s, chestAt(s, x, y), rng, events)
  elseif target == "stairs" then
    descend(s, rng, events)
  elseif s.p.potions > 0 then
    s.menu = true
    events[#events + 1] = { type = "menu" }
  else
    say(s, "Nothing here to use, and no potions.")
    events[#events + 1] = { type = "bump" }
  end
end

--- A step the way dx, dy, with the facing left alone.
local function move(s, dx, dy, rng, events)
  local x, y = s.x + dx, s.y + dy
  if not walkable(s, x, y) then
    events[#events + 1] = { type = "bump" }
    return
  end
  s.x, s.y = x, y
  s.moves = s.moves + 1
  if s.moves % HEAL_EVERY == 0 then s.p.hp = min(s.p.maxHp, s.p.hp + 1) end
  events[#events + 1] = { type = "step" }
  say(s, "")
  reveal(s)
  pickUp(s, events)
  if not s.over then monstersAct(s, rng, events) end
end

local function steer(s, dir, rng, events)
  local d = DIRS[s.dir]
  if dir == "up" then
    move(s, d[1], d[2], rng, events)
  elseif dir == "down" then
    move(s, -d[1], -d[2], rng, events)
  else
    s.dir = (s.dir - 1 + (dir == "right" and 1 or 3)) % 4 + 1
    events[#events + 1] = { type = "turn" }
    reveal(s)
  end
end

--- One tap, once the clock reaches it.
local function apply(s, action, rng, events)
  if s.menu then
    s.menu = false
    if action.kind == "act" then drink(s, rng, events) end
  elseif action.kind == "act" then
    act(s, rng, events)
  elseif action.kind == "turn" then
    steer(s, action.dir, rng, events)
  end
end

-- ---------------------------------------------------------------- the contract

function M.new(opts)
  local s = {
    score = 0, level = 1, over = false, won = false, frame = 0, rev = 0, moves = 0, menu = false, queue = {}, msg = "",
    fx = { flash = 0, hurt = 0, fire = 0, banner = 0 },
    p = {
      hp = START_HP, maxHp = START_HP, attack = START_ATTACK, lvl = 1, xp = 0, potions = 1, keys = 0, gold = 0, kills = 0,
      sword = 1, armour = 1,
    },
  }
  loadLevel(s, 1, opts.rng)
  say(s, "Find the stairs down. The dragon waits on depth " .. DEPTHS .. ".")
  return s
end

--- A tap, kept for the next step. A second one while the first waits is kept too, and more than that are dropped.
function M.input(s, action)
  if s.over or #s.queue >= QUEUE_LONGEST then return end
  s.queue[#s.queue + 1] = { kind = action.kind, dir = action.dir }
end

function M.tick(s, rng)
  local events = {}
  if s.over then return events end
  s.frame = s.frame + 1
  local fx = s.fx
  for _, name in ipairs({ "flash", "hurt", "fire", "banner" }) do
    if fx[name] > 0 then
      fx[name] = fx[name] - 1
      if fx[name] == 0 then changed(s) end
    end
  end
  local action = table.remove(s.queue, 1)
  if action then
    apply(s, action, rng, events)
    changed(s)
  end
  return events
end

-- ---------------------------------------------------------------- the bot

--- The way to the nearest thing worth walking to, as a facing, over squares the player has seen. goal(x, y) marks one.
-- Doors count as open: a door ahead gets opened when the bot reaches it.
local function headFor(s, goal, shut)
  local parent = { [s.y * WIDTH + s.x] = 0 }
  local order = { { s.x, s.y, 0 } }
  local head = 1
  while order[head] do
    local at = order[head]
    head = head + 1
    for way, d in ipairs(DIRS) do
      local x, y = at[1] + d[1], at[2] + d[2]
      local key = y * WIDTH + x
      if inside(x, y) and not parent[key] then
        parent[key] = true
        local first = at[3] == 0 and way or at[3]
        if goal(x, y) then return first end
        local c = tileAt(s, x, y)
        local passable = (c == OPEN or c == DOOR or (c == LOCKED and s.p.keys > 0)) and not shut[key]
        if passable and s.seen[y]:sub(x, x) == "1" then order[#order + 1] = { x, y, first } end
      end
    end
  end
  return nil
end

--- Turn to face a way, or set off along it.
local function faceOrGo(s, way)
  if way == s.dir then
    if M.target(s) then return { kind = "act" } end
    return { kind = "turn", dir = "up" }
  end
  return { kind = "turn", dir = (way - s.dir) % 4 == 3 and "left" or "right" }
end

--- Where the bot goes next: anything it can see, then new ground, then the stairs. A level gets only so many of its steps.
local function botGoal(s)
  local wanted, shut = {}, {}
  for _, o in ipairs(s.objs) do
    local key = o.y * WIDTH + o.x
    if o.kind ~= "trap" and not o.opened then wanted[key] = true end
    if o.kind == "chest" and not o.opened then shut[key] = true end
  end
  for _, m in ipairs(s.mons) do wanted[m.y * WIDTH + m.x] = true end
  local function stairs(x, y) return tileAt(s, x, y) == STAIRS end
  if s.moves > TIRED_AFTER then
    local way = headFor(s, stairs, shut)
    if way then return way end
  end
  return headFor(s, function(x, y)
    local c = tileAt(s, x, y)
    if s.seen[y]:sub(x, x) == "0" then return c ~= WALL end
    if c == DOOR or (c == LOCKED and s.p.keys > 0) then return true end
    return wanted[y * WIDTH + x] == true
  end, shut) or headFor(s, stairs, shut)
end

--- Plays for the idle screen: drinks when hurt, fights what's next to it, picks up what it sees, then goes down.
function M.bot(s)
  if s.over then return nil end
  local p = s.p
  local low = p.hp < p.maxHp * 0.45 and p.potions > 0
  if s.menu then
    if low then return { kind = "act" } end
    return { kind = "turn", dir = "left" }
  end
  if low then
    if not M.target(s) then return { kind = "act" } end
    for i = 1, 4 do
      local d = DIRS[i]
      local c = tileAt(s, s.x + d[1], s.y + d[2])
      if (c == OPEN or c == WALL) and not monsterAt(s, s.x + d[1], s.y + d[2]) and not chestAt(s, s.x + d[1], s.y + d[2]) then
        return faceOrGo(s, i)
      end
    end
  end
  for i = 1, 4 do
    local d = DIRS[(s.dir + i - 2) % 4 + 1]
    if monsterAt(s, s.x + d[1], s.y + d[2]) then return faceOrGo(s, (s.dir + i - 2) % 4 + 1) end
  end
  local way = botGoal(s)
  if way then return faceOrGo(s, way) end
  return { kind = "turn", dir = "left" }
end

return M
