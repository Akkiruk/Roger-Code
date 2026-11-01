-- games/bomberman/rules.lua
-- Bomberman, two players head to head. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The arena is 13x11 tiles, and every tile is an index into flat lists, so the computer can search it quickly.
-- It's the same turned half way round, bricks and hidden powerups too, so neither corner is the lucky one.
-- A tap sets a direction, which stays set. A turn that can't be made yet waits for one more tile, so a tap needn't be timed
-- to the gap between two pillars, and if it still can't be made the bomber stops. That's also how to stop without a bomb.
-- Bombers move as Dig Dug's digger does: they bank speed each step, and a tile costs 100. x and y are the tile they're entering.

local M = { COLS = 13, ROWS = 11, TICK_MS = 140, WINS = 3 }

local COLS, ROWS = M.COLS, M.ROWS
local TILES = COLS * ROWS
local FLOOR, PILLAR, BRICK, WALL = 0, 1, 2, 3
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local ORDER = { "up", "left", "down", "right" }

local BOMB_TICKS = 18         -- two and a half seconds
local FIRE_TICKS = 4
local SLIDE_TICKS = 2         -- a kicked bomb moves a tile this often
local WALK_SPEED = 30         -- about two tiles a second, under arcade pace: steering by the wall is hard enough
local BOOT_SPEED = 7          -- added by each pair of boots
local MAX_BOOTS = 3
local MAX_BOMBS, MAX_FLAME = 6, 7
local START_FLAME = 2
local BRICK_SHARE = 0.8       -- of the tiles that could hold one, so no two arenas are quite alike
local READY_TICKS = 14
local SETTLE_TICKS = 9        -- the winner of a round has to live this long, or it's a draw
local NEXT_TICKS = 18         -- the result of a round stays up this long
local SUDDEN_TICKS = 860      -- two minutes
local CLOSE_TICKS = 4         -- sudden death fills a tile at each end of the spiral this often

-- Hidden under the bricks of each half of the arena.
local LOOT = {
  "bomb", "bomb", "bomb", "bomb", "bomb", "flame", "flame", "flame", "flame", "flame", "boots", "boots", "boots", "kick", "kick",
}

-- The computer.
local THINK_TICKS = 3         -- it looks up this often, which is about what a quick hand can tap
local LOOK_AHEAD = 50         -- how far off it minds a tile about to be walled in
local ITEM_PULL = 24          -- how many steps of walking a powerup is worth
local BRICK_PULL = 7
local FOE_PULL = 9            -- for each tile nearer the other player, halved
local SIT_SHARE = 0.85        -- how often it takes a good chance to bomb, so it isn't a machine
local TRAP_RANGE = 7          -- tiles from the foe at which it tries to work out a trap

M.FLOOR, M.PILLAR, M.BRICK, M.WALL = FLOOR, PILLAR, BRICK, WALL
M.DIRECTIONS, M.OPPOSITE = DIRECTIONS, OPPOSITE
M.BOMB_TICKS, M.FIRE_TICKS, M.SLIDE_TICKS, M.START_FLAME = BOMB_TICKS, FIRE_TICKS, SLIDE_TICKS, START_FLAME
M.WALK_SPEED, M.BOOT_SPEED, M.MAX_BOOTS, M.MAX_BOMBS, M.MAX_FLAME = WALK_SPEED, BOOT_SPEED, MAX_BOOTS, MAX_BOMBS, MAX_FLAME
M.READY_TICKS, M.SETTLE_TICKS, M.NEXT_TICKS = READY_TICKS, SETTLE_TICKS, NEXT_TICKS
M.SUDDEN_TICKS, M.CLOSE_TICKS = SUDDEN_TICKS, CLOSE_TICKS

local function indexOf(x, y)
  return (y - 1) * COLS + x
end

local function tileOf(i)
  return (i - 1) % COLS + 1, math.floor((i - 1) / COLS) + 1
end

--- The same tile, with the arena turned half way round.
local function mirror(i)
  return TILES + 1 - i
end

local function inBounds(x, y)
  return x >= 1 and x <= COLS and y >= 1 and y <= ROWS
end

local function isPillar(x, y)
  return x % 2 == 0 and y % 2 == 0
end

M.indexOf, M.tileOf, M.mirror = indexOf, tileOf, mirror

-- The order sudden death fills the arena: round the edge and inwards, from two opposite corners at once. A pillar is
-- solid already, so it takes no time. CLOSE_ORDER is one end of the spiral, and the other end is its mirror.
local CLOSE_ORDER, CLOSE_STEP = {}, {}
do
  local function add(x, y)
    local i = indexOf(x, y)
    if not CLOSE_STEP[i] and not isPillar(x, y) then
      CLOSE_ORDER[#CLOSE_ORDER + 1] = i
      CLOSE_STEP[i], CLOSE_STEP[mirror(i)] = #CLOSE_ORDER, #CLOSE_ORDER
    end
  end
  for ring = 0, math.floor(ROWS / 2) do
    for x = 1 + ring, COLS - ring do add(x, 1 + ring) end
    for y = 2 + ring, ROWS - ring - 1 do add(COLS - ring, y) end
  end
end
M.CLOSE_ORDER, M.CLOSE_STEP = CLOSE_ORDER, CLOSE_STEP

-- Each player's corner and the two tiles along each edge from it, always clear, so the first bomb has somewhere to go.
local START = { { 1, 1 }, { COLS, ROWS } }
local CLEAR = {}
for _, at in ipairs({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 1, 2 }, { 1, 3 } }) do
  local i = indexOf(at[1], at[2])
  CLEAR[i], CLEAR[mirror(i)] = true, true
end
M.START = START

--- Point bricks and their hidden powerups into a fresh arena, each with its twin on the far side.
local function layArena(s, rng)
  local map, loot = {}, {}
  for i = 1, TILES do
    local x, y = tileOf(i)
    map[i] = isPillar(x, y) and PILLAR or FLOOR
  end
  local spots = {}
  for i = 1, math.ceil(TILES / 2) do
    if map[i] == FLOOR and not CLEAR[i] and rng() < BRICK_SHARE then
      map[i], map[mirror(i)] = BRICK, BRICK
      if i ~= mirror(i) then spots[#spots + 1] = i end
    end
  end
  for _, kind in ipairs(LOOT) do
    if #spots == 0 then break end
    local i = table.remove(spots, rng(#spots))
    loot[i], loot[mirror(i)] = kind, kind
  end
  s.map, s.loot, s.items = map, loot, {}
end

local function newPlayer(n)
  local at = START[n]
  return {
    n = n, x = at[1], y = at[2], px = at[1], py = at[2], dir = nil, face = "down", want = nil, wantLeft = 0, budget = 100,
    drop = false, bombs = 1, flame = START_FLAME, boots = 0, kick = false, alive = true,
  }
end

--- Everything a round starts afresh. Powerups don't carry over.
local function newRound(s, rng)
  layArena(s, rng)
  s.bombs, s.fire, s.fireKind = {}, {}, {}
  s.p = { newPlayer(1), newPlayer(2) }
  s.round = s.round + 1
  s.clock, s.closed = 0, 0
  s.pause, s.settle, s.after, s.roundWinner = READY_TICKS, nil, "start", nil
end

function M.new(opts)
  local s = { score = { 0, 0 }, round = 0, frame = 0, over = false, winner = nil }
  newRound(s, opts.rng)
  s.pause, s.after = 0, nil -- the shell counts in the first round
  return s
end

function M.speedOf(p)
  return WALK_SPEED + p.boots * BOOT_SPEED
end

local function bombAt(s, i)
  for _, b in ipairs(s.bombs) do
    if indexOf(b.x, b.y) == i then return b end
  end
end

local function bombsOut(s, n)
  local count = 0
  for _, b in ipairs(s.bombs) do
    if b.owner == n then count = count + 1 end
  end
  return count
end

M.bombAt, M.bombsOut = bombAt, bombsOut

--- A player's action: { kind = "turn", dir = ... }, or { kind = "bomb" }, which also stops them.
function M.input(s, player, action)
  local p = s.p[player]
  if s.over or not p or not p.alive or not action or s.after == "round" then return end
  if action.kind == "bomb" then
    p.drop, p.dir, p.want = true, nil, nil
  elseif action.kind == "turn" and DIRECTIONS[action.dir] then
    p.want, p.wantLeft = action.dir, 1
    p.face = action.dir
  end
end

--- Can a bomb go onto this tile?
local function bombFits(s, i)
  if s.map[i] ~= FLOOR or bombAt(s, i) then return false end
  for _, p in ipairs(s.p) do
    if p.alive and indexOf(p.x, p.y) == i then return false end
  end
  return true
end

--- What a step this way would do: "walk", "kick", "wait" behind a sliding bomb, or nil if it's blocked.
local function stepKind(s, p, dir)
  local d = DIRECTIONS[dir]
  local x, y = p.x + d[1], p.y + d[2]
  if not inBounds(x, y) then return nil end
  local i = indexOf(x, y)
  if s.map[i] ~= FLOOR then return nil end
  local b = bombAt(s, i)
  if not b then return "walk" end
  if b.dir then return "wait" end
  if p.kick and inBounds(x + d[1], y + d[2]) and bombFits(s, indexOf(x + d[1], y + d[2])) then return "kick" end
  return nil
end

local function pickUp(s, p, events)
  local i = indexOf(p.x, p.y)
  local kind = s.items[i]
  if not kind then return end
  s.items[i] = nil
  if kind == "bomb" then p.bombs = math.min(MAX_BOMBS, p.bombs + 1) end
  if kind == "flame" then p.flame = math.min(MAX_FLAME, p.flame + 1) end
  if kind == "boots" then p.boots = math.min(MAX_BOOTS, p.boots + 1) end
  if kind == "kick" then p.kick = true end
  events[#events + 1] = { type = "powerup", player = p.n, kind = kind, x = p.x, y = p.y }
end

--- The turn asked for, at the moment a bomber is at a tile and free to take it.
local function takeTurn(s, p)
  if not p.want then return end
  if stepKind(s, p, p.want) then
    p.dir, p.want = p.want, nil
  elseif p.dir and p.wantLeft > 0 then
    p.wantLeft = p.wantLeft - 1
  else
    p.dir, p.want = nil, nil
  end
end

local function walk(s, p, events)
  p.budget = p.budget + M.speedOf(p)
  if p.budget < 100 then return end
  takeTurn(s, p)
  local kind = p.dir and stepKind(s, p, p.dir)
  if kind == "walk" then
    local d = DIRECTIONS[p.dir]
    p.px, p.py = p.x, p.y
    p.x, p.y = p.x + d[1], p.y + d[2]
    p.face = p.dir
    p.budget = p.budget - 100
    pickUp(s, p, events)
    return
  end
  if kind == "kick" then
    local d = DIRECTIONS[p.dir]
    local b = bombAt(s, indexOf(p.x + d[1], p.y + d[2]))
    b.dir, b.slide = p.dir, 0
    events[#events + 1] = { type = "kick", player = p.n, x = b.x, y = b.y }
  elseif not kind then
    p.dir = nil
  end
  p.budget = 100
end

local function dropBomb(s, p, events)
  if not p.drop then return end
  p.drop = false
  local i = indexOf(p.x, p.y)
  if bombAt(s, i) or bombsOut(s, p.n) >= p.bombs then return end
  s.bombs[#s.bombs + 1] = { x = p.x, y = p.y, owner = p.n, fuse = BOMB_TICKS, reach = p.flame, dir = nil, slide = 0 }
  events[#events + 1] = { type = "bomb", player = p.n, x = p.x, y = p.y }
end

local function slideBombs(s)
  for _, b in ipairs(s.bombs) do
    if b.dir then
      b.slide = b.slide - 1
      if b.slide <= 0 then
        local d = DIRECTIONS[b.dir]
        local x, y = b.x + d[1], b.y + d[2]
        if inBounds(x, y) and bombFits(s, indexOf(x, y)) then
          b.x, b.y, b.slide = x, y, SLIDE_TICKS
        else
          b.dir = nil
        end
      end
    end
  end
end

--- The four arms of a blast, a tile at a time. visit(i, dir) is told every tile the fire reaches, bricks included, and can
-- return true to end that arm there. Pillars and walls stop it short, and a brick takes the fire but stops it.
local function eachArm(s, x, y, reach, visit)
  for _, dir in ipairs(ORDER) do
    local d = DIRECTIONS[dir]
    for r = 1, reach do
      local ax, ay = x + d[1] * r, y + d[2] * r
      if not inBounds(ax, ay) then break end
      local i = indexOf(ax, ay)
      local tile = s.map[i]
      if tile == PILLAR or tile == WALL then break end
      if visit(i, dir) or tile == BRICK then break end
    end
  end
end

local function setFire(s, i, kind)
  s.fire[i] = FIRE_TICKS
  -- where two arms cross, it's a centre
  local had = s.fireKind[i]
  if had and had ~= kind then kind = "c" end
  s.fireKind[i] = kind
end

--- Every bomb whose time is up goes off, with every bomb the fire reaches. It all counts as one moment: a brick broken here
-- stops the fire of every bomb in the chain, and only shows what it hid once they're all done.
local function explode(s, events)
  local queue, lit = {}, {}
  for _, b in ipairs(s.bombs) do
    if b.fuse <= 0 or s.fire[indexOf(b.x, b.y)] then
      queue[#queue + 1] = b
      lit[b] = true
    end
  end
  local broken = {}
  local head = 1
  while queue[head] do
    local b = queue[head]
    head = head + 1
    local center = indexOf(b.x, b.y)
    setFire(s, center, "c")
    s.items[center] = nil
    events[#events + 1] = { type = "blast", x = b.x, y = b.y, owner = b.owner }
    eachArm(s, b.x, b.y, b.reach, function(i, dir)
      setFire(s, i, (dir == "up" or dir == "down") and "v" or "h")
      if s.map[i] == BRICK then
        broken[#broken + 1] = i
        return false
      end
      s.items[i] = nil
      local other = bombAt(s, i)
      if other then
        if not lit[other] then
          lit[other] = true
          queue[#queue + 1] = other
        end
        return true
      end
      return false
    end)
  end
  for _, i in ipairs(broken) do
    if s.map[i] == BRICK then
      local x, y = tileOf(i)
      s.map[i] = FLOOR
      s.items[i], s.loot[i] = s.loot[i], nil
      events[#events + 1] = { type = "brick", x = x, y = y, kind = s.items[i] }
    end
  end
  local left = {}
  for _, b in ipairs(s.bombs) do
    if not lit[b] then left[#left + 1] = b end
  end
  s.bombs = left
end

--- A tile of sudden death: whatever was there is gone.
local function closeTile(s, i, events)
  s.map[i] = WALL
  s.items[i], s.loot[i], s.fire[i], s.fireKind[i] = nil, nil, nil, nil
  local left = {}
  for _, b in ipairs(s.bombs) do
    if indexOf(b.x, b.y) ~= i then left[#left + 1] = b end
  end
  s.bombs = left
  local x, y = tileOf(i)
  events[#events + 1] = { type = "wall", x = x, y = y }
end

local function closeIn(s, events)
  if s.clock == SUDDEN_TICKS then events[#events + 1] = { type = "sudden" } end
  if s.clock < SUDDEN_TICKS or (s.clock - SUDDEN_TICKS) % CLOSE_TICKS ~= 0 then return end
  local i = CLOSE_ORDER[s.closed + 1]
  if not i then return end
  s.closed = s.closed + 1
  closeTile(s, i, events)
  if mirror(i) ~= i then closeTile(s, mirror(i), events) end
end

--- Who's in the fire, or under a wall.
local function checkDeaths(s, events)
  for _, p in ipairs(s.p) do
    local i = indexOf(p.x, p.y)
    if p.alive and (s.fire[i] or s.map[i] == WALL) then
      p.alive = false
      p.dir, p.want, p.drop = nil, nil, false
      events[#events + 1] = { type = "death", player = p.n, x = p.x, y = p.y, crushed = s.map[i] == WALL }
    end
  end
end

--- A round is over: a win, or a draw that plays again. The match ends at three wins.
local function endRound(s, events)
  local one, two = s.p[1].alive, s.p[2].alive
  local won = (one and not two) and 1 or ((two and not one) and 2 or 0)
  s.settle, s.roundWinner, s.after = nil, won, "round"
  s.pause = NEXT_TICKS
  if won > 0 then s.score[won] = s.score[won] + 1 end
  events[#events + 1] = { type = "round", winner = won, score = { s.score[1], s.score[2] } }
  if won > 0 and s.score[won] >= M.WINS then
    s.over, s.winner, s.pause = true, won, 0
    events[#events + 1] = { type = "match", winner = won }
  end
end

local function settleRound(s, events)
  local alive = (s.p[1].alive and 1 or 0) + (s.p[2].alive and 1 or 0)
  if alive == 0 then
    endRound(s, events)
  elseif alive == 1 then
    s.settle = (s.settle or SETTLE_TICKS) - 1
    if s.settle <= 0 then endRound(s, events) end
  end
end

--- One step of the clock.
function M.tick(s, rng)
  local events = {}
  if s.over then return events end
  s.frame = s.frame + 1
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause == 0 then
      if s.after == "round" then
        newRound(s, rng)
        events[#events + 1] = { type = "ready", round = s.round }
      else
        s.after = nil
        events[#events + 1] = { type = "go", round = s.round }
      end
    end
    return events
  end
  s.clock = s.clock + 1
  for i = 1, TILES do
    if s.fire[i] then
      s.fire[i] = s.fire[i] - 1
      if s.fire[i] <= 0 then s.fire[i], s.fireKind[i] = nil, nil end
    end
  end
  for _, p in ipairs(s.p) do
    if p.alive then
      dropBomb(s, p, events)
      walk(s, p, events)
    end
  end
  slideBombs(s)
  for _, b in ipairs(s.bombs) do b.fuse = b.fuse - 1 end
  explode(s, events)
  closeIn(s, events)
  checkDeaths(s, events)
  settleRound(s, events)
  return events
end

-- ---------------------------------------------------------------- the computer

--- When each tile will burn, as burn[i] to till[i] steps from now: fuses, chains, fire still alight, and sudden death.
-- It sees only what a player can: never the hidden powerups. extra is a bomb it's thinking of dropping.
local function dangerOf(s, extra)
  local list, at = {}, {}
  for _, b in ipairs(s.bombs) do
    local copy = { x = b.x, y = b.y, reach = b.reach, t = b.fuse }
    list[#list + 1] = copy
    at[indexOf(b.x, b.y)] = copy
  end
  if extra then
    list[#list + 1] = extra
    at[indexOf(extra.x, extra.y)] = extra
  end
  local changed = true
  while changed do
    changed = false
    for _, b in ipairs(list) do
      eachArm(s, b.x, b.y, b.reach, function(i)
        local other = at[i]
        if other then
          if other.t > b.t then
            other.t = b.t
            changed = true
          end
          return true
        end
        return false
      end)
    end
  end
  local burn, till = {}, {}
  local function mark(i, from, to)
    if not burn[i] or from < burn[i] then burn[i] = from end
    if not till[i] or to > till[i] then till[i] = to end
  end
  for _, b in ipairs(list) do
    mark(indexOf(b.x, b.y), b.t, b.t + FIRE_TICKS)
    eachArm(s, b.x, b.y, b.reach, function(i)
      mark(i, b.t, b.t + FIRE_TICKS)
      return at[i] ~= nil
    end)
  end
  for i = 1, TILES do
    if s.fire[i] then mark(i, 0, s.fire[i]) end
    if CLOSE_STEP[i] and s.map[i] ~= WALL then
      local closes = SUDDEN_TICKS + (CLOSE_STEP[i] - 1) * CLOSE_TICKS - s.clock
      if closes <= LOOK_AHEAD then mark(i, closes, math.huge) end
    end
  end
  return burn, till, at
end

--- How soon this player can stand on each tile, keeping out of the fire on the way. lag is how long before they set off.
-- Returns arrive[i] and from[i].
local function reach(s, p, burn, till, blocked, lag)
  local stepTicks = math.ceil(100 / M.speedOf(p))
  local start = indexOf(p.x, p.y)
  local arrive, from = { [start] = (lag or 0) + math.ceil(math.max(0, 100 - p.budget) / M.speedOf(p)) }, {}
  local queue, head = { start }, 1
  while queue[head] do
    local c = queue[head]
    head = head + 1
    local x, y = tileOf(c)
    for _, dir in ipairs(ORDER) do
      local d = DIRECTIONS[dir]
      local nx, ny = x + d[1], y + d[2]
      if inBounds(nx, ny) then
        local i = indexOf(nx, ny)
        if not arrive[i] and s.map[i] == FLOOR and not blocked[i] then
          -- a bomber is on a tile from the moment it sets off for it, not from when it gets there
          local enter, leave = arrive[c], arrive[c] + stepTicks
          local burning = burn[i] and leave + 1 >= burn[i] and enter - 1 <= till[i]
          if not burning then
            arrive[i], from[i] = leave, c
            queue[#queue + 1] = i
          end
        end
      end
    end
  end
  return arrive, from
end

--- The first step of the way to a tile, as a direction.
local function firstStep(start, from, goal)
  local i = goal
  while from[i] and from[i] ~= start do i = from[i] end
  if not from[i] then return nil end
  local x, y = tileOf(start)
  local gx, gy = tileOf(i)
  if gx < x then return "left" end
  if gx > x then return "right" end
  return gy < y and "up" or "down"
end

--- How many ways out a tile has. A pocket is a poor place to hide.
local function exitsOf(s, i)
  local x, y = tileOf(i)
  local exits = 0
  for _, dir in ipairs(ORDER) do
    local d = DIRECTIONS[dir]
    local nx, ny = x + d[1], y + d[2]
    if inBounds(nx, ny) and s.map[indexOf(nx, ny)] == FLOOR then exits = exits + 1 end
  end
  return exits
end

--- The best tile that never burns, or nil: soonest, then with the most ways out. The tie has to be broken on the tile
-- itself, not on its place in the list, or one corner plays better than the other.
local function shelter(s, arrive, burn)
  local best, top
  for i = 1, TILES do
    if arrive[i] and not burn[i] then
      local score = arrive[i] * 4 - exitsOf(s, i)
      if not top or score < top or (score == top and math.abs(i - mirror(i)) < math.abs(best - mirror(best))) then
        best, top = i, score
      end
    end
  end
  return best
end

--- Would a bomb dropped here be survivable, and how much would it hurt? Returns ok, trapped, hit.
local function weighBomb(s, me, foe)
  local x, y = me.x, me.y
  local extra = { x = x, y = y, reach = me.flame, t = BOMB_TICKS }
  local burn, till, at = dangerOf(s, extra)
  local mine = reach(s, me, burn, till, at, THINK_TICKS)
  if not shelter(s, mine, burn) then return false end
  local hit = burn[indexOf(foe.x, foe.y)] ~= nil
  if math.abs(foe.x - x) + math.abs(foe.y - y) > TRAP_RANGE then return true, false, hit end
  local theirs = reach(s, foe, burn, till, at)
  return true, not shelter(s, theirs, burn), hit
end

local function hitsBrick(s, me)
  local found = false
  eachArm(s, me.x, me.y, me.flame, function(i)
    found = found or s.map[i] == BRICK
    return false
  end)
  return found
end

--- A tile's worth to the computer, in steps of walking.
local function tileWorth(s, i, foe, spare)
  if s.items[i] then return ITEM_PULL end
  local worth = 0
  local x, y = tileOf(i)
  if spare then
    for _, dir in ipairs(ORDER) do
      local d = DIRECTIONS[dir]
      if inBounds(x + d[1], y + d[2]) and s.map[indexOf(x + d[1], y + d[2])] == BRICK then worth = worth + BRICK_PULL end
    end
  end
  local gap = math.abs(foe.x - x) + math.abs(foe.y - y)
  worth = worth - gap * (foe.alive and FOE_PULL or 0) / 2
  -- in sudden death, the middle is the last to go
  if s.clock + LOOK_AHEAD >= SUDDEN_TICKS then
    worth = worth + (CLOSE_STEP[i] or #CLOSE_ORDER) / 2
  end
  return worth
end

--- How a bomber with no bomb to spare, or nowhere else safe to go, stops where it is.
local function halt(s, me, burn)
  if not me.dir then return nil end
  local d = DIRECTIONS[me.dir]
  local ax, ay = me.x + d[1], me.y + d[2]
  if not inBounds(ax, ay) or s.map[indexOf(ax, ay)] ~= FLOOR or bombAt(s, indexOf(ax, ay)) then return nil end
  if not burn[indexOf(ax, ay)] then return nil end
  if bombsOut(s, me.n) >= me.bombs then return { kind = "bomb" } end
  local bx, by = me.x - d[1], me.y - d[2]
  if inBounds(bx, by) and s.map[indexOf(bx, by)] == FLOOR and not burn[indexOf(bx, by)] then
    return { kind = "turn", dir = OPPOSITE[me.dir] }
  end
  return { kind = "bomb" }
end

local function steer(me, dir)
  if me.dir == dir and not me.want then return nil end
  return { kind = "turn", dir = dir }
end

--- An action for this player, or nil. It looks ahead rather than cheating: a clear path out of every blast it can see, and
-- a bomb only where it can get away. It takes a chance to box the other player in if it sees one.
function M.bot(s, rng, player)
  local me = s.p[player]
  local foe = s.p[3 - player]
  if s.over or s.pause > 0 or not me.alive or (s.frame + player) % THINK_TICKS ~= 0 then return nil end
  local burn, till, at = dangerOf(s)
  local here = indexOf(me.x, me.y)
  local arrive, from = reach(s, me, burn, till, at)
  if burn[here] then
    local goal = shelter(s, arrive, burn)
    if goal then
      local dir = firstStep(here, from, goal)
      if dir then return steer(me, dir) end
    end
    -- nowhere is safe for good, so the last tile to burn will have to do
    local latest, best = -1, nil
    for i = 1, TILES do
      if arrive[i] and from[i] and (burn[i] or math.huge) > latest then latest, best = burn[i] or math.huge, i end
    end
    local dir = best and firstStep(here, from, best)
    return dir and steer(me, dir) or nil
  end
  local spare = bombsOut(s, me.n) < me.bombs and not at[here]
  if spare and foe.alive then
    local ok, trapped, hit = weighBomb(s, me, foe)
    if ok then
      local roll = rng()
      if trapped and roll < 0.9 then return { kind = "bomb" } end
      if hit and roll < 0.6 then return { kind = "bomb" } end
      if hitsBrick(s, me) and roll < SIT_SHARE then return { kind = "bomb" } end
    end
  end
  local goal, best = here, tileWorth(s, here, foe, spare) + 1
  for i = 1, TILES do
    if arrive[i] and not burn[i] and i ~= here then
      local score = tileWorth(s, i, foe, spare) - arrive[i] / 3 + rng()
      if score > best then goal, best = i, score end
    end
  end
  if goal == here then return halt(s, me, burn) end
  local dir = firstStep(here, from, goal)
  if dir then return steer(me, dir) end
  return nil
end

return M
