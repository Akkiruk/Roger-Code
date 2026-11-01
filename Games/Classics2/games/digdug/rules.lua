-- games/digdug/rules.lua
-- Dig Dug. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Everything lives on a grid of tiles. Row 1 is the surface, and every row below it starts as dirt.
-- A tap sets s.want, which stays set: the digger keeps going until PUMP stops him or something is in the way.
-- Actors bank their speed each step and move a tile for every 100 banked, so a level can be quicker without a shorter tick.
-- PUMP fires a short harpoon. Each further tap inflates what it hooked, and the original's held button is gone for good.

local M = { COLS = 15, ROWS = 13 }

local COLS, ROWS = M.COLS, M.ROWS
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local ORDER = { "up", "left", "down", "right" }

local START = { 8, 6 }        -- the bottom of the shaft, and where the bonus vegetable grows
local DIG_SCORE = 10
local PLAYER_SPEED = 50       -- a tile every two steps
local GHOST_SHARE, FLEE_SHARE = 0.8, 1.3 -- speed through dirt, and the last enemy's speed, as shares of its own
local HARPOON_REACH = 3       -- tiles, one a step
local MAX_TAPS = 2            -- pumps kept for later steps, so a fast tap isn't lost
local STAGES = 4              -- inflations that pop an enemy
local DEFLATE_TICKS = 12      -- a hooked enemy left alone loses a stage this often, and gets free from stage 0
local DAZED_TICKS = 4         -- an enemy just free stands still this long, to make up for a slow touch
local WOBBLE_TICKS = 10
local CRUMBLE_TICKS = 4
local WINDUP_TICKS = 7        -- a Fygar stands and glows this long before the fire comes
local FIRE_TICKS = 5
local FIRE_REACH = 3
local FIRE_SPOT = 4           -- how far along a row a Fygar sees the digger
local GHOST_MIN = 3           -- moves as a ghost before a tunnel can end it
local VEG_TICKS = 100
local VEG_ROCKS = 2           -- rocks dropped that bring out the vegetable
local READY_TICKS = 12
local DEATH_TICKS = 12
local CLEAR_TICKS = 14
local POPUP_TICKS = 9
local BURST_TICKS = 3

local LAYER = { 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4 } -- by row
local POP_SCORES = { 200, 300, 400, 500 }         -- by layer
local CRUSH_SCORES = { 1000, 2500, 4000, 6000, 8000, 10000, 12000, 15000 } -- by how many one rock takes
local VEGETABLES = { 400, 600, 800, 1000, 1000, 2000, 2000, 3000, 3000, 4000, 5000, 6000, 7000, 8000 } -- by level

M.DIRECTIONS, M.OPPOSITE, M.START = DIRECTIONS, OPPOSITE, START
M.STAGES, M.HARPOON_REACH, M.DEFLATE_TICKS, M.WOBBLE_TICKS = STAGES, HARPOON_REACH, DEFLATE_TICKS, WOBBLE_TICKS
M.WINDUP_TICKS, M.FIRE_REACH, M.FIRE_TICKS, M.DIG_SCORE = WINDUP_TICKS, FIRE_REACH, FIRE_TICKS, DIG_SCORE
M.READY_TICKS, M.DEATH_TICKS, M.CLEAR_TICKS, M.DAZED_TICKS = READY_TICKS, DEATH_TICKS, CLEAR_TICKS, DAZED_TICKS
M.CRUSH_SCORES = CRUSH_SCORES

local function inBounds(x, y)
  return x >= 1 and x <= COLS and y >= 1 and y <= ROWS
end

local function ahead(x, y, dir)
  local d = DIRECTIONS[dir]
  return x + d[1], y + d[2]
end

local function isDirt(s, x, y)
  local row = s.dirt[y]
  return row ~= nil and row[x] == true
end

local function rockAt(s, x, y)
  for _, r in ipairs(s.rocks) do
    if r.x == x and r.y == y then return r end
  end
end

--- Can something that doesn't dig stand here?
local function open(s, x, y)
  return inBounds(x, y) and not isDirt(s, x, y) and not rockAt(s, x, y)
end

--- The dirt layer of a row, 1 to 4. The surface counts as the top layer.
function M.layerOf(y)
  return math.max(1, LAYER[y] or 4)
end

--- What a pop is worth: more the deeper it is, and a Fygar is worth double when pumped from the side.
function M.popScore(kind, y, sideways)
  local points = POP_SCORES[M.layerOf(y)]
  if kind == "fygar" and sideways then points = points * 2 end
  return points
end

--- Enemies on a level. Always under the digger's speed, so a clean run can pull away.
function M.enemySpeed(level)
  return math.min(46, 28 + 2 * level)
end

function M.enemyCount(level)
  return math.min(8, 3 + level)
end

local function fygarCount(level)
  return math.floor(M.enemyCount(level) / 3)
end

function M.rockCount(level)
  return math.min(6, 3 + math.floor(level / 3))
end

local function vegetablePoints(level)
  return VEGETABLES[math.min(level, #VEGETABLES)]
end

local function ghostDelay(s, rng)
  local least = math.max(25, 60 - 5 * s.level)
  return least + rng(50)
end

local function fireDelay(s, rng)
  return math.max(12, 30 - 2 * s.level) + rng(15)
end

local function newEnemy(s, kind, x, y, rng)
  return {
    kind = kind, x = x, y = y, px = x, py = y, homeX = x, homeY = y, dir = "left", face = "left", mode = "walk",
    budget = 0, wait = 0, t = 0, inflate = 0, hooked = false, deflate = 0, carried = false,
    ghostIn = ghostDelay(s, rng), fireIn = fireDelay(s, rng), ghostMoves = 0,
  }
end

M.newEnemy = newEnemy

--- Is every tile of this pocket, and the tiles around it, still dirt and clear of the shaft?
local function pocketFits(s, x, y, w, h, margin)
  if x < 1 or y < 3 or x + w - 1 > COLS or y + h - 1 > ROWS then return false end
  if x + w - 1 >= START[1] - 2 and x <= START[1] + 2 and y <= START[2] + 2 then return false end
  for ty = y - margin, y + h - 1 + margin do
    for tx = x - margin, x + w - 1 + margin do
      if inBounds(tx, ty) and ty >= 2 and not isDirt(s, tx, ty) then return false end
    end
  end
  return true
end

--- Dig a pocket with an enemy in the middle. A tighter fit is allowed if the board has filled up.
local function placePocket(s, kind, rng)
  for try = 1, 300 do
    local wide = kind == "fygar" or rng(3) > 1
    local w, h = wide and 3 + rng(2) - 1 or 1, wide and 1 or 3
    local x, y = rng(COLS - w + 1), 2 + rng(ROWS - h)
    if pocketFits(s, x, y, w, h, try <= 200 and 1 or 0) then
      for ty = y, y + h - 1 do
        for tx = x, x + w - 1 do s.dirt[ty][tx] = nil end
      end
      s.enemies[#s.enemies + 1] = newEnemy(s, kind, x + math.floor(w / 2), y + math.floor(h / 2), rng)
      return
    end
  end
end

--- Rocks sit in solid dirt, and never over the shaft or a pocket, so nothing falls until the digger makes it.
local function placeRocks(s, rng)
  local wanted = M.rockCount(s.level)
  local placed = 0
  for _ = 1, 400 do
    if placed >= wanted then return end
    local x, y = rng(COLS), 2 + rng(ROWS - 3)
    local spaced = true
    for _, r in ipairs(s.rocks) do
      if math.abs(r.x - x) < 2 and math.abs(r.y - y) < 3 then spaced = false end
    end
    if spaced and x ~= START[1] and isDirt(s, x, y) and isDirt(s, x, y + 1) and isDirt(s, x, y - 1) then
      s.dirt[y][x] = nil
      s.rocks[#s.rocks + 1] = { x = x, y = y, state = "still", t = 0, carried = {} }
      placed = placed + 1
    end
  end
end

--- A new board: solid dirt, the shaft, then pockets and rocks.
local function buildLevel(s, rng)
  s.dirt = {}
  for y = 2, ROWS do
    s.dirt[y] = {}
    for x = 1, COLS do s.dirt[y][x] = true end
  end
  for y = 2, START[2] do s.dirt[y][START[1]] = nil end
  s.rocks, s.enemies, s.dropped = {}, {}, 0
  local count, fygars = M.enemyCount(s.level), fygarCount(s.level)
  for i = 1, count do placePocket(s, i <= fygars and "fygar" or "pooka", rng) end
  placeRocks(s, rng)
end

--- Everyone back to the start, for a new life or a new board. Tunnels stay dug.
local function resetActors(s, rng)
  s.player = { x = START[1], y = START[2], px = START[1], py = START[2], dir = "right", budget = 100, speed = PLAYER_SPEED }
  s.want, s.taps, s.pump, s.veg = nil, 0, nil, nil
  for _, g in ipairs(s.enemies) do
    g.x, g.y, g.px, g.py = g.homeX, g.homeY, g.homeX, g.homeY
    g.mode, g.budget, g.wait, g.inflate, g.hooked, g.carried = "walk", 0, 0, 0, false, false
    g.ghostIn, g.fireIn = ghostDelay(s, rng), fireDelay(s, rng)
  end
  for i = #s.rocks, 1, -1 do
    local r = s.rocks[i]
    if r.state == "wobble" then
      r.state = "still"
    elseif r.state ~= "still" then
      table.remove(s.rocks, i)
    end
  end
  s.popups, s.bursts = {}, {}
  s.pause, s.ready = READY_TICKS, true
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = { score = 0, level = 1, lives = 3, over = false, frame = 0 }
  buildLevel(s, opts.rng)
  resetActors(s, opts.rng)
  return s
end

--- A player's input. A direction stays set; PUMP stops the digger where he stands and fires, or inflates.
function M.input(s, action)
  if action.kind == "turn" and DIRECTIONS[action.dir] then
    s.want = action.dir
    s.player.dir = action.dir
  elseif action.kind == "pump" then
    s.want = nil
    s.taps = math.min(MAX_TAPS, s.taps + 1)
  end
end

--- Can this enemy hurt the digger right now?
local function harmful(g)
  return not g.hooked and g.inflate == 0 and not g.carried
end

local function enemyOn(s, x, y)
  for _, g in ipairs(s.enemies) do
    if g.x == x and g.y == y and not g.carried then return g end
  end
end

local function popup(s, x, y, text)
  s.popups[#s.popups + 1] = { x = x, y = y, text = tostring(text), left = POPUP_TICKS }
end

local function award(s, points, x, y)
  s.score = s.score + points
  popup(s, x, y, points)
end

local function removeEnemy(s, g)
  for i, other in ipairs(s.enemies) do
    if other == g then
      table.remove(s.enemies, i)
      return
    end
  end
end

--- Let the harpoon go. Whatever it held keeps deflating by itself.
local function release(s)
  local pump = s.pump
  s.pump = nil
  if not (pump and pump.hook) then return end
  local g = pump.hook
  g.hooked = false
  if g.inflate == 0 then g.wait = DAZED_TICKS end
end

local function popEnemy(s, g, events)
  local pump = s.pump
  local sideways = pump.dir == "left" or pump.dir == "right"
  local points = M.popScore(g.kind, g.y, sideways)
  award(s, points, g.x, g.y)
  s.bursts[#s.bursts + 1] = { x = g.x, y = g.y, kind = g.kind, left = BURST_TICKS }
  removeEnemy(s, g)
  s.pump, s.taps = nil, 0
  events[#events + 1] = { type = "pop", points = points, kind = g.kind, sideways = sideways }
end

local function hookEnemy(s, g, events)
  s.pump.hook = g
  g.hooked, g.deflate = true, DEFLATE_TICKS
  if g.mode == "windup" or g.mode == "fire" then g.mode, g.fireIn = "walk", FIRE_TICKS * 4 end
  events[#events + 1] = { type = "hook", kind = g.kind }
end

--- The harpoon's next tile, and anything now on the line. Dirt or a rock stops it, but a ghost in that dirt can be hit.
local function extendHarpoon(s, events)
  local pump = s.pump
  pump.len = pump.len + 1
  local x, y = s.player.x, s.player.y
  for i = 1, pump.len do
    x, y = ahead(x, y, pump.dir)
    local g = enemyOn(s, x, y)
    if g then
      pump.len = i
      hookEnemy(s, g, events)
      return
    end
    if not open(s, x, y) then
      s.pump = nil
      events[#events + 1] = { type = "miss" }
      return
    end
  end
  if pump.len >= HARPOON_REACH then
    s.pump = nil
    events[#events + 1] = { type = "miss" }
  end
end

local function stepPump(s, events)
  if s.want then
    s.taps = 0
    release(s)
    return
  end
  local pump = s.pump
  if pump and pump.hook then
    if s.taps > 0 then
      local g = pump.hook
      s.taps = s.taps - 1
      g.inflate, g.deflate = g.inflate + 1, DEFLATE_TICKS
      events[#events + 1] = { type = "inflate", stage = g.inflate }
      if g.inflate >= STAGES then popEnemy(s, g, events) end
    end
  elseif pump then
    extendHarpoon(s, events)
  elseif s.taps > 0 then
    s.taps = s.taps - 1
    s.pump = { dir = s.player.dir, len = 0 }
    events[#events + 1] = { type = "fire" }
    extendHarpoon(s, events)
  end
end

--- Left alone, an enemy shrinks a stage at a time, and then it's free.
local function deflateEnemies(s, events)
  for _, g in ipairs(s.enemies) do
    if g.hooked or g.inflate > 0 then
      g.deflate = g.deflate - 1
      if g.deflate <= 0 then
        g.deflate = DEFLATE_TICKS
        if g.inflate > 0 then
          g.inflate = g.inflate - 1
          if g.inflate == 0 and not g.hooked then g.wait = DAZED_TICKS end
        else
          if s.pump and s.pump.hook == g then s.pump = nil end
          g.hooked, g.wait = false, DAZED_TICKS
          events[#events + 1] = { type = "free" }
        end
      end
    end
  end
end

local function die(s, events, cause)
  s.lives = s.lives - 1
  s.after, s.pause, s.want = "life", DEATH_TICKS, nil
  s.killedBy = cause
  events[#events + 1] = { type = "death", cause = cause }
end

--- Enemies meet the digger on a tile, or by swapping tiles as they pass.
local function checkContact(s, events)
  if s.after then return end
  local p = s.player
  for _, g in ipairs(s.enemies) do
    if harmful(g) then
      local swapped = g.px == p.x and g.py == p.y and g.x == p.px and g.y == p.py
      if (g.x == p.x and g.y == p.y) or swapped then
        die(s, events, g.kind)
        return
      end
    end
  end
end

--- The tiles a Fygar's fire covers now. It grows a tile a step, and dirt or a rock stops it.
function M.flameTiles(s, g)
  local list = {}
  if g.mode ~= "fire" then return list end
  local x, y = g.x, g.y
  local reach = math.min(FIRE_REACH, FIRE_TICKS - g.t + 1)
  for _ = 1, reach do
    x, y = ahead(x, y, g.face)
    if not open(s, x, y) then break end
    list[#list + 1] = { x, y }
  end
  return list
end

local function checkFire(s, events)
  if s.after then return end
  local p = s.player
  for _, g in ipairs(s.enemies) do
    for _, at in ipairs(M.flameTiles(s, g)) do
      if at[1] == p.x and at[2] == p.y then
        die(s, events, "fire")
        return
      end
    end
  end
end

local function eatVegetable(s, events)
  local p = s.player
  if s.veg and p.x == START[1] and p.y == START[2] then
    award(s, s.veg.points, p.x, p.y)
    events[#events + 1] = { type = "veg", points = s.veg.points }
    s.veg = nil
  end
end

--- The digger moves when he has banked a tile, into dirt or a tunnel. He stops short of an enemy rather than walk into it.
local function stepPlayer(s, events)
  local p = s.player
  p.budget = math.min(100, p.budget + p.speed)
  if s.pump or not s.want or p.budget < 100 then return end
  p.dir = s.want
  local x, y = ahead(p.x, p.y, p.dir)
  if not inBounds(x, y) or rockAt(s, x, y) then return end
  local g = enemyOn(s, x, y)
  if g and harmful(g) then return end
  p.px, p.py, p.x, p.y = p.x, p.y, x, y
  p.budget = 0
  if isDirt(s, x, y) then
    s.dirt[y][x] = nil
    s.score = s.score + DIG_SCORE
    events[#events + 1] = { type = "dig" }
  end
  eatVegetable(s, events)
end

local function toward(g, tx, ty, canEnter)
  local dx, dy = tx - g.x, ty - g.y
  local across = dx < 0 and "left" or "right"
  local along = dy < 0 and "up" or "down"
  local first, second = across, along
  if math.abs(dy) > math.abs(dx) then first, second = along, across end
  for i, dir in ipairs({ first, second }) do
    local gap = dir == across and dx or dy
    if (gap ~= 0 or i == 2) and canEnter(ahead(g.x, g.y, dir)) then return dir end
  end
  for _, dir in ipairs(ORDER) do
    if canEnter(ahead(g.x, g.y, dir)) then return dir end
  end
end

local function moveEnemy(g, dir)
  g.px, g.py = g.x, g.y
  g.dir = dir
  if dir == "left" or dir == "right" then g.face = dir end
  g.x, g.y = ahead(g.x, g.y, dir)
end

--- Along the tunnels: on at a dead end, back only when there's no other way, and a leaning towards the digger.
local function walkOnce(s, g, rng)
  local exits = {}
  for _, dir in ipairs(ORDER) do
    if dir ~= OPPOSITE[g.dir] and open(s, ahead(g.x, g.y, dir)) then exits[#exits + 1] = dir end
  end
  if #exits == 0 then
    if not open(s, ahead(g.x, g.y, OPPOSITE[g.dir])) then return end
    exits[1] = OPPOSITE[g.dir]
  end
  local dir = exits[rng(#exits)]
  if #exits > 1 and rng() < 0.6 then
    local best
    for _, option in ipairs(exits) do
      local x, y = ahead(g.x, g.y, option)
      local distance = math.abs(x - s.player.x) + math.abs(y - s.player.y)
      if not best or distance < best then best, dir = distance, option end
    end
  end
  moveEnemy(g, dir)
end

local function ghostOnce(s, g, rng)
  local p = s.player
  local function usable(x, y) return inBounds(x, y) and not rockAt(s, x, y) end
  local dir = toward(g, p.x, p.y, usable)
  if dir then moveEnemy(g, dir) end
  g.ghostMoves = g.ghostMoves + 1
  if g.ghostMoves >= GHOST_MIN and open(s, g.x, g.y) then
    g.mode, g.ghostIn = "walk", ghostDelay(s, rng)
  end
end

--- Straight up through anything but rocks, then off the nearer end of the surface.
local function fleeOnce(s, g)
  if g.y == 1 and (g.x == 1 or g.x == COLS) then
    g.gone = true
    return
  end
  local side = g.x <= (COLS + 1) / 2 and "left" or "right"
  if g.y == 1 then
    moveEnemy(g, side)
  elseif not rockAt(s, g.x, g.y - 1) then
    moveEnemy(g, "up")
  elseif not rockAt(s, ahead(g.x, g.y, side)) and inBounds(ahead(g.x, g.y, side)) then
    moveEnemy(g, side)
  else
    moveEnemy(g, OPPOSITE[side])
  end
end

--- Is the digger along this Fygar's row, close, with clear air between them?
local function canSeeAlong(s, g)
  local p = s.player
  if g.y ~= p.y or g.x == p.x or math.abs(g.x - p.x) > FIRE_SPOT then return false end
  local step = g.x < p.x and 1 or -1
  for x = g.x + step, p.x - step, step do
    if not open(s, x, g.y) then return false end
  end
  return true
end

local function speedOf(s, g)
  local speed = M.enemySpeed(s.level)
  if g.mode == "ghost" then return speed * GHOST_SHARE end
  if g.mode == "flee" then return speed * FLEE_SHARE end
  return speed
end

local function moveOnce(s, g, rng)
  if g.mode == "walk" then
    walkOnce(s, g, rng)
  elseif g.mode == "ghost" then
    ghostOnce(s, g, rng)
  else
    fleeOnce(s, g)
  end
end

--- A walking enemy's clocks: when to go ghost, and for a Fygar when to wind up. Returns true if it stops to breathe.
local function startSomething(s, g, events)
  g.ghostIn = g.ghostIn - 1
  if g.kind == "fygar" then
    g.fireIn = g.fireIn - 1
    if g.fireIn <= 0 and canSeeAlong(s, g) then
      g.face = g.x < s.player.x and "right" or "left"
      g.mode, g.t, g.px, g.py = "windup", WINDUP_TICKS, g.x, g.y
      events[#events + 1] = { type = "windup" }
      return true
    end
  end
  if g.ghostIn <= 0 then
    g.mode, g.ghostMoves = "ghost", 0
    events[#events + 1] = { type = "ghost" }
  end
  return false
end

local function stepFire(s, g, events, rng)
  g.t = g.t - 1
  if g.t > 0 then return end
  if g.mode == "windup" then
    g.mode, g.t = "fire", FIRE_TICKS
    events[#events + 1] = { type = "flame" }
  else
    g.mode, g.fireIn = "walk", fireDelay(s, rng)
  end
end

local function stepEnemy(s, g, events, rng)
  if g.carried or g.hooked or g.inflate > 0 then return end
  if g.wait > 0 then
    g.wait = g.wait - 1
    return
  end
  if #s.enemies == 1 and g.mode ~= "flee" then
    g.mode = "flee"
    events[#events + 1] = { type = "flee" }
  end
  if g.mode == "windup" or g.mode == "fire" then
    stepFire(s, g, events, rng)
    return
  end
  if g.mode == "walk" and startSomething(s, g, events) then return end
  g.budget = g.budget + speedOf(s, g)
  while g.budget >= 100 and not g.gone do
    g.budget = g.budget - 100
    moveOnce(s, g, rng)
  end
end

local function stepEnemies(s, events, rng)
  local list = {}
  for i, g in ipairs(s.enemies) do list[i] = g end
  for _, g in ipairs(list) do
    stepEnemy(s, g, events, rng)
    if g.gone then
      removeEnemy(s, g)
      events[#events + 1] = { type = "escape" }
    end
  end
end

local function dropVegetable(s, events)
  s.dropped = s.dropped + 1
  if s.dropped == VEG_ROCKS then
    s.veg = { points = vegetablePoints(s.level), left = VEG_TICKS }
    events[#events + 1] = { type = "vegOut" }
  end
end

--- A rock that has come to rest breaks up, and everything it carried counts together.
local function landRock(s, r, events)
  r.state, r.t = "crumble", CRUMBLE_TICKS
  events[#events + 1] = { type = "land" }
  local n = #r.carried
  if n == 0 then return end
  local points = CRUSH_SCORES[math.min(n, #CRUSH_SCORES)]
  for _, g in ipairs(r.carried) do
    s.bursts[#s.bursts + 1] = { x = r.x, y = r.y, kind = g.kind, left = BURST_TICKS }
    removeEnemy(s, g)
  end
  award(s, points, r.x, r.y)
  events[#events + 1] = { type = "crush", count = n, points = points }
  r.carried = {}
end

--- Whatever is on the rock's tile now rides down under it. An enemy dies when it lands; the digger dies at once.
local function catchUnderRock(s, r, events)
  for _, g in ipairs(s.enemies) do
    if g.x == r.x and g.y == r.y and not g.carried then
      g.carried = true
      if s.pump and s.pump.hook == g then s.pump = nil end
      g.hooked, g.inflate = false, 0
      r.carried[#r.carried + 1] = g
    end
  end
  local p = s.player
  if p.x == r.x and p.y == r.y and not s.after then die(s, events, "rock") end
end

local function fallRock(s, r, events)
  local below = r.y + 1
  if below > ROWS or isDirt(s, r.x, below) or rockAt(s, r.x, below) then
    landRock(s, r, events)
    return
  end
  r.y = below
  for _, g in ipairs(r.carried) do
    g.px, g.py, g.y = g.x, g.y, below
  end
  catchUnderRock(s, r, events)
end

--- A rock with nothing under it wobbles once the digger is out from under it, and then it goes.
local function stepRock(s, r, events)
  if r.state == "still" then
    local p = s.player
    local under = p.x == r.x and p.y == r.y + 1
    if r.y < ROWS and not isDirt(s, r.x, r.y + 1) and not rockAt(s, r.x, r.y + 1) and not under then
      r.state, r.t = "wobble", WOBBLE_TICKS
      events[#events + 1] = { type = "wobble" }
    end
  elseif r.state == "wobble" then
    r.t = r.t - 1
    if r.t <= 0 then
      r.state = "fall"
      dropVegetable(s, events)
      events[#events + 1] = { type = "drop" }
    end
  elseif r.state == "fall" then
    fallRock(s, r, events)
  end
end

local function stepRocks(s, events)
  for _, r in ipairs(s.rocks) do stepRock(s, r, events) end
  for i = #s.rocks, 1, -1 do
    local r = s.rocks[i]
    if r.state == "crumble" then
      r.t = r.t - 1
      if r.t <= 0 then table.remove(s.rocks, i) end
    end
  end
end

--- Short notes on the board, and the vegetable's clock.
local function runClocks(s)
  for _, list in ipairs({ s.popups, s.bursts }) do
    for i = #list, 1, -1 do
      list[i].left = list[i].left - 1
      if list[i].left <= 0 then table.remove(list, i) end
    end
  end
  if s.veg then
    s.veg.left = s.veg.left - 1
    if s.veg.left <= 0 then s.veg = nil end
  end
end

--- What comes after a pause: the next life, the next board or the end.
local function endPause(s, events, rng)
  local after = s.after
  s.after, s.ready = nil, false
  if after == "life" then
    if s.lives <= 0 then
      s.over = true
      events[#events + 1] = { type = "over" }
    else
      resetActors(s, rng)
    end
  elseif after == "level" then
    s.level = s.level + 1
    buildLevel(s, rng)
    resetActors(s, rng)
    events[#events + 1] = { type = "level" }
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  local events = {}
  s.frame = s.frame + 1
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause == 0 then endPause(s, events, rng) end
    return events
  end
  runClocks(s)
  stepPump(s, events)
  deflateEnemies(s, events)
  stepPlayer(s, events)
  checkContact(s, events)
  stepEnemies(s, events, rng)
  checkContact(s, events)
  checkFire(s, events)
  stepRocks(s, events)
  if not s.after and #s.enemies == 0 then
    s.after, s.pause = "level", CLEAR_TICKS
    s.want, s.pump = nil, nil
    events[#events + 1] = { type = "clear" }
  end
  return events
end

-- ---------------------------------------------------------------- the bot

local BOT_LAPSE = 0.05  -- how often it stops looking, so its runs come to an end
local BOT_CARE = 2      -- tiles of room it wants from an enemy it isn't facing
local BOT_ROCK = 9      -- how far it will go to undermine a rock
local BOT_ROCK_SAFE = 3 -- it only plays with rocks with no enemy this close

local function distance(ax, ay, bx, by)
  return math.abs(ax - bx) + math.abs(ay - by)
end

local function nearestEnemy(s)
  local p = s.player
  local best, bestDistance
  for _, g in ipairs(s.enemies) do
    local d = distance(p.x, p.y, g.x, g.y)
    if harmful(g) and (not best or d < bestDistance) then best, bestDistance = g, d end
  end
  return best, bestDistance
end

--- Which way along a row or column to the enemy, if a harpoon could reach it from here.
local function shotAt(s, g)
  local p = s.player
  local dir
  if g.x == p.x then dir = g.y < p.y and "up" or "down" end
  if g.y == p.y then dir = g.x < p.x and "left" or "right" end
  if not dir or distance(p.x, p.y, g.x, g.y) > HARPOON_REACH then return nil end
  local x, y = ahead(p.x, p.y, dir)
  while not (x == g.x and y == g.y) do
    if not open(s, x, y) then return nil end
    x, y = ahead(x, y, dir)
  end
  return dir
end

--- Could he stand here for a moment?
local function roomy(s, x, y)
  if not inBounds(x, y) or rockAt(s, x, y) then return false end
  for _, g in ipairs(s.enemies) do
    if harmful(g) and distance(x, y, g.x, g.y) < BOT_CARE then return false end
  end
  return true
end

--- A rock is coming down on this column, or a Fygar is about to fire along this row.
local function underThreat(s, x, y)
  for _, r in ipairs(s.rocks) do
    if (r.state == "wobble" or r.state == "fall") and r.x == x and r.y < y then return true end
  end
  for _, g in ipairs(s.enemies) do
    if (g.mode == "windup" or g.mode == "fire") and g.y == y and math.abs(g.x - x) <= FIRE_REACH + 1 then return true end
  end
  return false
end

--- A way out of trouble: the neighbouring tile that is safe and furthest from every enemy.
local function dodge(s)
  local p = s.player
  local best, bestRoom = nil, -1
  for _, dir in ipairs(ORDER) do
    local x, y = ahead(p.x, p.y, dir)
    if roomy(s, x, y) and not underThreat(s, x, y) then
      local room = 99
      for _, g in ipairs(s.enemies) do room = math.min(room, distance(x, y, g.x, g.y)) end
      if room > bestRoom then best, bestRoom = dir, room end
    end
  end
  return best
end

--- The tile beneath the nearest rock it could undermine, for a show on the idle screen.
local function rockGoal(s)
  local p = s.player
  local best, bestDistance
  for _, r in ipairs(s.rocks) do
    local d = distance(p.x, p.y, r.x, r.y + 1)
    if r.state == "still" and isDirt(s, r.x, r.y + 1) and d <= BOT_ROCK and (not best or d < bestDistance) then
      best, bestDistance = r, d
    end
  end
  return best
end

--- A step that closes on a tile, lining up on the shorter side first so the harpoon gets a straight shot.
local function stepTowards(s, tx, ty)
  local p = s.player
  local dx, dy = tx - p.x, ty - p.y
  local across = dx < 0 and "left" or "right"
  local along = dy < 0 and "up" or "down"
  local order = { across, along }
  if dx == 0 or (dy ~= 0 and math.abs(dy) <= math.abs(dx)) then order = { along, across } end
  for i, dir in ipairs(order) do
    local gap = dir == across and dx or dy
    local x, y = ahead(p.x, p.y, dir)
    if (gap ~= 0 or i == 2) and roomy(s, x, y) and not underThreat(s, x, y) then return dir end
  end
  return dodge(s)
end

--- A good but human player for the idle screen and tests: hunt, pump, undermine a rock now and then, unless it lapses.
function M.bot(s, rng)
  if s.pause > 0 or s.after then return nil end
  if rng() < BOT_LAPSE then return nil end
  local p = s.player
  if s.pump then
    if s.pump.hook and s.frame % 2 == 0 then return { kind = "pump" } end
    return nil
  end
  local g, gap = nearestEnemy(s)
  if underThreat(s, p.x, p.y) then
    local dir = dodge(s)
    if dir then return { kind = "turn", dir = dir } end
  end
  if not g then return nil end
  local shot = shotAt(s, g)
  if shot then
    if shot == p.dir then return { kind = "pump" } end
    return { kind = "turn", dir = shot }
  end
  if gap < BOT_CARE then
    local dir = dodge(s)
    if dir then return { kind = "turn", dir = dir } end
  end
  local tx, ty = g.x, g.y
  local rock = gap > BOT_ROCK_SAFE and rockGoal(s)
  if rock then tx, ty = rock.x, rock.y + 1 end
  local dir = stepTowards(s, tx, ty)
  return dir and { kind = "turn", dir = dir } or nil
end

return M
