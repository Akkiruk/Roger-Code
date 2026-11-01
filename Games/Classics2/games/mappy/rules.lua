-- games/mappy/rules.lua
-- Mappy. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The mansion is measured in wall cells: 120 wide, 66 tall, six floors, with four full-height shafts between three sections.
-- A shaft has a trampoline at the bottom. Walk off a floor and you're in it; a tap of left or right stays set and takes you
-- off at the next floor you pass, and up or down calls that off. On a floor the same taps walk and stop.
-- Walkers bank their speed each step and move a cell for every 100 banked. In a shaft everyone moves row by row at one
-- speed, so nobody can skip a floor, and two actors in step are at a matching height.
-- A closed door stops everyone. It swings one way only, whichever side you open it from, and flattens cats on that side.

local M = { WIDTH = 120, HEIGHT = 66, FLOORS = 6 }

local WIDTH, FLOORS = M.WIDTH, M.FLOORS
local abs, floor, min = math.abs, math.floor, math.min

local DIRS = { left = -1, right = 1 }
local OPPOSITE = { left = "right", right = "left" }

local SHAFT_X = { 0, 37, 74, 111 } -- left edges
local SHAFT_W = 9
local TOP_FLOOR, FLOOR_H = 11, 10  -- the row of the top floor, and from one floor to the next
local TRAMPOLINE_Y = 64
local APEX_Y = 8                   -- the top of a bounce, a little over the top floor
local SLOW_Y = 20                  -- above this row a bounce loses speed, as it does near the top in the original
local AIR_ROWS, SLOW_ROWS = 3, 2   -- rows a step
local START = { floor = 6, x = 60 }

local PLAYER_SPEED = 170           -- cells a step, by 100: about 12 cells a second, on purpose under the arcade's pace
local GORO_SPEED = 85
local STANDOFF = 3                 -- how close a walker gets to a closed door
local CATCH_W, CATCH_H = 4, 3      -- how near a cat has to be, along a floor and in a shaft
local PICK_W, PICK_H = 3, 3        -- how near goods have to be

local BREAK_BOUNCES = 5            -- this landing in a row goes through: four colours, then the floor of the pit
local DOOR_REACH = 12              -- how far ahead a tap reaches a door
local SWING_W = 10                 -- how far a door's swing knocks cats over
local KNOCK_SCORE = 200            -- doubled for each cat in one swing
local STUN_TICKS = 32
local WAVE_SPEED = 6               -- cells a step, each way along the floor
local WAVE_SCORE = 300             -- doubled for each cat one wave takes
local FLY_SPEED = 7
local RETURN_TICKS = 80            -- how long a cat sent flying stays out
local BELL_REACH = 2               -- how near he walks to set a bell off
local BELL_TICKS = 5               -- from the swing to the floor, so it lands on what was behind him
local BELL_W = 6
local BELL_STUN = 80
local BELL_REST = 30
local BELL_SCORE = 500             -- doubled for each cat under one bell
local BELLS = 2
local GORO_BONUS = 1000
local HIDE_TICKS, HIDE_GAP = 60, 50
local THINK_TICKS = 12             -- a cat looks round this often
local BLOCKED_TICKS = 30           -- and this long after a door turns it back
local STRAY = 0.25                 -- how often a bouncing cat goes to some other floor

local HURRY_TICKS = 100            -- the warning before the ghost
local GHOST_X, GHOST_Y = 2.4, 2.0  -- cells a step: faster than he walks
local GHOST_W, GHOST_H = 4, 5

local BONUS_EVERY, BONUS_FIRST = 4, 3 -- rounds 3, 7, 11, as in the original
local BONUS_TICKS = 320
local BALLOONS_ON_FLOORS, BALLOONS_IN_SHAFTS = 8, 4
local BALLOON_SCORE, ALL_BALLOONS = 300, 5000

local READY_TICKS = 12
local DEATH_TICKS = 14
local CLEAR_TICKS = 14
local POPUP_TICKS = 9

local VALUES = { radio = 100, tv = 200, computer = 300, safe = 500 }
local KINDS = { "radio", "tv", "computer", "safe" }

local FLOOR_Y, FLOOR_OF = {}, {} -- the row of each floor, and the floor at a row
for f = 1, FLOORS do
  FLOOR_Y[f] = TOP_FLOOR + (f - 1) * FLOOR_H
  FLOOR_OF[FLOOR_Y[f]] = f
end

M.DIRS, M.SHAFT_X, M.SHAFT_W, M.FLOOR_Y, M.START = DIRS, SHAFT_X, SHAFT_W, FLOOR_Y, START
M.TRAMPOLINE_Y, M.APEX_Y, M.BREAK_BOUNCES, M.VALUES = TRAMPOLINE_Y, APEX_Y, BREAK_BOUNCES, VALUES
M.DOOR_REACH, M.SWING_W, M.STUN_TICKS, M.KNOCK_SCORE = DOOR_REACH, SWING_W, STUN_TICKS, KNOCK_SCORE
M.WAVE_SCORE, M.RETURN_TICKS, M.BELL_TICKS, M.BELL_SCORE, M.BELL_STUN = WAVE_SCORE, RETURN_TICKS, BELL_TICKS, BELL_SCORE, BELL_STUN
M.GORO_BONUS, M.HIDE_TICKS, M.HURRY_TICKS, M.BALLOON_SCORE, M.ALL_BALLOONS = GORO_BONUS, HIDE_TICKS, HURRY_TICKS, BALLOON_SCORE, ALL_BALLOONS
M.READY_TICKS, M.DEATH_TICKS, M.CLEAR_TICKS, M.BONUS_TICKS = READY_TICKS, DEATH_TICKS, CLEAR_TICKS, BONUS_TICKS
M.PLAYER_SPEED = PLAYER_SPEED

--- The section of floor at a cell, or nil over a shaft.
local function sectionAt(x)
  for i = 1, #SHAFT_X - 1 do
    if x >= SHAFT_X[i] + SHAFT_W and x < SHAFT_X[i + 1] then return i end
  end
end

local function shaftAt(x)
  for i, left in ipairs(SHAFT_X) do
    if x >= left and x < left + SHAFT_W then return i end
  end
end

--- The first and last cell of a section.
local function sectionEnds(i)
  return SHAFT_X[i] + SHAFT_W, SHAFT_X[i + 1] - 1
end

--- Is there a floor on that side of a shaft? The end shafts have a wall on one side.
local function hasSide(shaft, dir)
  return (dir == "left" and shaft > 1) or (dir == "right" and shaft < #SHAFT_X)
end

M.sectionAt, M.shaftAt, M.sectionEnds = sectionAt, shaftAt, sectionEnds

--- Cats on a level, not counting Goro. More every round, and quicker, but never as quick as he is.
function M.catCount(level)
  return min(5, 1 + level)
end

function M.catSpeed(level)
  return min(160, 105 + 8 * level)
end

function M.timeFor(level)
  return math.max(340, 640 - 30 * level)
end

function M.isBonus(level)
  return level >= BONUS_FIRST and (level - BONUS_FIRST) % BONUS_EVERY == 0
end

local function shuffle(list, rng)
  for i = #list, 2, -1 do
    local j = rng(i)
    list[i], list[j] = list[j], list[i]
  end
end

--- Places for goods: two to a stretch of floor, well clear of the door in the middle and of the start.
local function goodSlots()
  local list = {}
  for f = 1, FLOORS do
    for i = 1, #SHAFT_X - 1 do
      local from, to = sectionEnds(i)
      for _, x in ipairs({ from + 5, to - 5 }) do
        if f ~= START.floor or abs(x - START.x) > 12 then list[#list + 1] = { f = f, x = x } end
      end
    end
  end
  return list
end

local function pairCount(level)
  return min(7, 5 + floor(level / 4))
end

local function placeGoods(s, rng)
  local slots = goodSlots()
  shuffle(slots, rng)
  local at = 0
  for _ = 1, pairCount(s.level) do
    local kind = KINDS[rng(#KINDS)]
    for _ = 1, 2 do
      at = at + 1
      s.goods[at] = { kind = kind, floor = slots[at].f, x = slots[at].x }
    end
  end
end

--- Doors stand in the middle of a section. The first two are the flashing ones, and always start shut.
local function placeDoors(s, rng)
  local spots = {}
  for f = 1, FLOORS do
    for i = 1, #SHAFT_X - 1 do
      local from, to = sectionEnds(i)
      if f ~= START.floor or i ~= sectionAt(START.x) then
        spots[#spots + 1] = { f = f, x = floor((from + to) / 2) + rng(7) - 4 }
      end
    end
  end
  shuffle(spots, rng)
  for i = 1, min(#spots, 6 + s.level) do
    local power = i <= 2
    s.doors[i] = {
      x = spots[i].x, floor = spots[i].f, swing = rng(2) == 1 and "left" or "right",
      open = not power and rng() < 0.35, power = power,
    }
  end
end

local function placeBells(s, rng)
  for _ = 1, BELLS do
    local i = rng(#SHAFT_X - 1)
    local from, to = sectionEnds(i)
    local mid = floor((from + to) / 2)
    s.bells[#s.bells + 1] = { x = mid + (rng(2) == 1 and -8 or 8), floor = rng(FLOORS - 1), state = "hang", t = 0 }
  end
end

--- Balloons for a bonus round: along the floors, and some up the shafts to be met on a bounce.
local function placeBalloons(s, rng)
  local slots = goodSlots()
  shuffle(slots, rng)
  for i = 1, BALLOONS_ON_FLOORS do
    s.goods[i] = { kind = "balloon", floor = slots[i].f, x = slots[i].x }
  end
  for i = 1, BALLOONS_IN_SHAFTS do
    local shaft = (i - 1) % #SHAFT_X + 1
    local f = rng(FLOORS - 1)
    s.goods[#s.goods + 1] = { kind = "balloon", shaft = shaft, x = SHAFT_X[shaft] + 4, y = FLOOR_Y[f] + 5 }
  end
end

local function newCat(kind, x, f)
  return {
    kind = kind, x = x, y = FLOOR_Y[f], floor = f, mode = "walk", dir = "left", vdir = 1, budget = 0, wait = 0, stun = 0,
    think = 0, t = 0, hideIn = HIDE_GAP, homeX = x, homeFloor = f,
  }
end

M.newCat = newCat

local function placeCats(s)
  s.cats = {}
  local sections = #SHAFT_X - 1
  for i = 1, M.catCount(s.level) + 1 do
    local from, to = sectionEnds((i - 1) % sections + 1)
    local c = newCat(i == 1 and "goro" or "meowkie", floor((from + to) / 2), 1)
    c.wait = 10 + 25 * (i - 1)
    c.homeWait = c.wait
    s.cats[i] = c
  end
end

local function buildLevel(s, rng)
  s.goods, s.doors, s.bells, s.cats = {}, {}, {}, {}
  s.tramps = {}
  for i = 1, #SHAFT_X do s.tramps[i] = { hits = 0, broken = false } end
  s.bonus = M.isBonus(s.level)
  s.lastKind = nil
  if s.bonus then
    placeBalloons(s, rng)
  else
    placeGoods(s, rng)
    placeDoors(s, rng)
    placeBells(s, rng)
    placeCats(s)
  end
end

--- Everyone back to the start, for a new life or a new round. Goods, doors and bells stay as they are.
local function resetActors(s)
  s.player = {
    x = START.x, y = FLOOR_Y[START.floor], floor = START.floor, mode = "walk", dir = "right", vdir = 1, budget = 0,
  }
  s.want, s.doorTap, s.ghost = nil, false, nil
  s.time, s.timeMax = M.timeFor(s.level), M.timeFor(s.level)
  if s.bonus then s.time, s.timeMax = BONUS_TICKS, BONUS_TICKS end
  for _, c in ipairs(s.cats) do
    if c.good then c.good.goro = nil end
    c.x, c.y, c.floor, c.shaft, c.good = c.homeX, FLOOR_Y[c.homeFloor], c.homeFloor, nil, nil
    c.mode, c.budget, c.stun, c.think, c.dir, c.stray = "walk", 0, 0, 0, "left", nil
    c.wait, c.hideIn = c.homeWait or 0, HIDE_GAP
  end
  for _, t in ipairs(s.tramps) do t.hits, t.broken = 0, false end
  s.waves, s.popups = {}, {}
  s.pause, s.ready = READY_TICKS, true
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = { score = 0, level = 1, lives = 3, over = false, frame = 0 }
  buildLevel(s, opts.rng)
  resetActors(s)
  return s
end

--- A player's input. Left and right stay set. Up and down stop him on a floor and call off a jump in a shaft.
function M.input(s, action)
  if action.kind == "turn" then
    if DIRS[action.dir] then
      s.want = action.dir
      s.player.dir = action.dir
    elseif action.dir == "up" or action.dir == "down" then
      s.want = nil
    end
  elseif action.kind == "door" then
    s.doorTap = true
  end
end

local function popup(s, x, y, text)
  s.popups[#s.popups + 1] = { x = x, y = y, text = tostring(text), left = POPUP_TICKS }
end

local function award(s, points, x, y)
  s.score = s.score + points
  popup(s, x, y, points)
end

--- Can this cat catch him right now?
local function harmful(c)
  return (c.mode == "walk" or c.mode == "air") and c.stun == 0
end

--- Is this cat out on a floor, where a door or a bell can get it?
local function onFloor(c, f)
  return c.mode == "walk" and c.floor == f
end

--- A closed door within a stand-off ahead?
local function doorInWay(s, f, x, dir)
  for _, d in ipairs(s.doors) do
    if d.floor == f and not d.open then
      local gap = (d.x - x) * DIRS[dir]
      if gap > 0 and gap <= STANDOFF then return true end
    end
  end
  return false
end

--- One cell along a floor. Returns "door" if a closed door stops it, or "edge" on stepping off the end of a section.
local function stepAlong(s, a, dir)
  if doorInWay(s, a.floor, a.x, dir) then return "door" end
  a.x = a.x + DIRS[dir]
  if not sectionAt(a.x) then return "edge" end
end

local function enterShaft(a)
  a.shaft = shaftAt(a.x)
  a.mode, a.floor, a.vdir, a.budget = "air", nil, 1, 0
  a.x = SHAFT_X[a.shaft] + 4
end

local function leaveShaft(a, f, dir)
  local shaft = a.shaft
  a.mode, a.floor, a.shaft, a.dir = "walk", f, nil, dir
  a.y = FLOOR_Y[f]
  a.x = dir == "left" and SHAFT_X[shaft] - 1 or SHAFT_X[shaft] + SHAFT_W
end

--- A step up or down a shaft, a row at a time. onRow can take the actor off at a floor; onLand is the trampoline.
-- Either one returns true to end the step.
local function climb(a, onRow, onLand)
  for _ = 1, a.y <= SLOW_Y and SLOW_ROWS or AIR_ROWS do
    a.y = a.y + a.vdir
    if a.y <= APEX_Y then a.vdir = 1 end
    if a.y >= TRAMPOLINE_Y then
      a.y, a.vdir = TRAMPOLINE_Y, -1
      if onLand(a) then return end
    end
    local f = FLOOR_OF[a.y]
    if f and onRow(a, f) then return end
  end
end

local function die(s, events, cause)
  s.lives = s.lives - 1
  s.after, s.pause, s.want = "life", DEATH_TICKS, nil
  s.killedBy = cause
  events[#events + 1] = { type = "death", cause = cause }
end

local function findGoro(s, good)
  for _, c in ipairs(s.cats) do
    if c.good == good then return c end
  end
end

local function collect(s, good, events)
  local p = s.player
  if good.kind == "balloon" then
    award(s, BALLOON_SCORE, p.x, p.y)
    events[#events + 1] = { type = "balloon", points = BALLOON_SCORE }
    if #s.goods == 0 then
      award(s, ALL_BALLOONS, p.x, p.y - 6)
      events[#events + 1] = { type = "allBalloons", points = ALL_BALLOONS }
    end
    return
  end
  local value = VALUES[good.kind]
  local paired = s.lastKind == good.kind
  -- the pair pays double in all, so the second brings three times its value: the first was paid when it was picked up
  local points = paired and value * 3 or value
  s.lastKind = not paired and good.kind or nil
  award(s, points, good.x, FLOOR_Y[good.floor])
  events[#events + 1] = { type = "good", kind = good.kind, points = points, pair = paired }
  if good.goro then
    local c = findGoro(s, good)
    if c then
      c.good, c.mode, c.hideIn, c.stun = nil, "walk", HIDE_GAP, STUN_TICKS
    end
    award(s, GORO_BONUS, good.x, FLOOR_Y[good.floor] - 7)
    events[#events + 1] = { type = "goro", points = GORO_BONUS }
  end
end

local function pickUp(s, events)
  local p = s.player
  for i = #s.goods, 1, -1 do
    local good = s.goods[i]
    local near
    if good.shaft then
      near = p.mode == "air" and p.shaft == good.shaft and abs(p.y - good.y) <= PICK_H
    else
      near = p.mode == "walk" and p.floor == good.floor and abs(p.x - good.x) <= PICK_W
    end
    if near then
      table.remove(s.goods, i)
      collect(s, good, events)
    end
  end
end

--- Walking under a bell sets it off.
local function touchBells(s, events)
  local p = s.player
  if p.mode ~= "walk" then return end
  for _, b in ipairs(s.bells) do
    if b.state == "hang" and b.floor == p.floor and abs(b.x - p.x) <= BELL_REACH then
      b.state, b.t = "fall", BELL_TICKS
      events[#events + 1] = { type = "bell" }
    end
  end
end

local function walkPlayer(s, events)
  local p = s.player
  local dir = s.want
  if not dir then
    p.budget = 0
    return
  end
  p.budget = p.budget + PLAYER_SPEED
  while p.budget >= 100 do
    p.budget = p.budget - 100
    local hit = stepAlong(s, p, dir)
    if hit == "door" then
      p.budget = 0
      return
    elseif hit == "edge" then
      enterShaft(p)
      s.want = nil -- he has to mean the next jump: a tap left over from walking would take him straight across
      events[#events + 1] = { type = "drop" }
      return
    end
    touchBells(s, events)
  end
end

--- In a shaft: off at a floor if a jump is set, and a landing wears the trampoline.
local function bouncePlayer(s, events)
  local p = s.player
  local tramp = s.tramps[p.shaft]
  climb(p, function(_, f)
    if s.want and hasSide(p.shaft, s.want) then
      tramp.hits = 0 -- it heals when he leaves it
      leaveShaft(p, f, s.want)
      events[#events + 1] = { type = "hop", floor = f }
      return true
    end
  end, function()
    tramp.hits = s.bonus and 1 or tramp.hits + 1
    if tramp.hits >= BREAK_BOUNCES then
      tramp.broken = true
      die(s, events, "trampoline")
      return true
    end
    events[#events + 1] = { type = "bounce", hits = tramp.hits }
  end)
end

local function movePlayer(s, events)
  if s.player.mode == "walk" then
    walkPlayer(s, events)
  else
    bouncePlayer(s, events)
  end
  pickUp(s, events)
end

--- The door he's facing: the nearest one ahead on his floor, within reach. Open or closed.
function M.doorAhead(s)
  local p = s.player
  if p.mode ~= "walk" then return nil end
  local best, bestGap
  for _, d in ipairs(s.doors) do
    local gap = (d.x - p.x) * DIRS[p.dir]
    if d.floor == p.floor and gap >= 0 and gap <= DOOR_REACH and (not best or gap < bestGap) then best, bestGap = d, gap end
  end
  return best
end

--- Everything on a door's swing side goes over, and each one in the same swing is worth double.
local function swingDoor(s, d, events)
  local out = DIRS[d.swing]
  local points = KNOCK_SCORE
  for _, c in ipairs(s.cats) do
    local reach = (c.x - d.x) * out
    if onFloor(c, d.floor) and c.stun == 0 and reach >= 0 and reach <= SWING_W then
      c.stun = STUN_TICKS
      award(s, points, c.x, c.y)
      events[#events + 1] = { type = "knock", points = points }
      points = points * 2
    end
  end
end

--- A flashing door fires both ways along its floor, once, and from then on it's a door like any other.
local function fireWave(s, d, events)
  s.waves[#s.waves + 1] = { floor = d.floor, x = d.x, left = d.x, right = d.x, chain = 0 }
  d.power = false
  events[#events + 1] = { type = "wave" }
end

local function useDoor(s, events)
  if not s.doorTap then return end
  s.doorTap = false
  local d = M.doorAhead(s)
  if not d then return end
  d.open = not d.open
  if not d.open then
    events[#events + 1] = { type = "doorShut" }
    return
  end
  events[#events + 1] = { type = "doorOpen" }
  if d.power then
    fireWave(s, d, events)
  else
    swingDoor(s, d, events)
  end
end

--- Off the side of the mansion, whatever it was doing.
local function sendFlying(s, w, c, events)
  if c.good then c.good.goro, c.good = nil, nil end
  c.mode, c.stun, c.wait = "fly", 0, 0
  c.dir = c.x < w.x and "left" or "right"
  local points = WAVE_SCORE * 2 ^ w.chain
  w.chain = w.chain + 1
  award(s, points, c.x, c.y)
  events[#events + 1] = { type = "flying", points = points }
end

local function stepWaves(s, events)
  for i = #s.waves, 1, -1 do
    local w = s.waves[i]
    w.left, w.right = w.left - WAVE_SPEED, w.right + WAVE_SPEED
    for _, c in ipairs(s.cats) do
      local hiding = c.mode == "hide"
      if (onFloor(c, w.floor) or (hiding and c.floor == w.floor)) and c.x >= w.left and c.x <= w.right then
        sendFlying(s, w, c, events)
      end
    end
    if w.left < 0 and w.right >= WIDTH then table.remove(s.waves, i) end
  end
end

--- A bell lands where he set it off, on whatever was behind him. It doesn't hurt him.
local function landBell(s, b, events)
  b.state, b.t = "rest", BELL_REST
  events[#events + 1] = { type = "clang" }
  local points = BELL_SCORE
  for _, c in ipairs(s.cats) do
    if onFloor(c, b.floor) and abs(c.x - b.x) <= BELL_W then
      c.stun = BELL_STUN
      award(s, points, c.x, c.y)
      events[#events + 1] = { type = "belled", points = points }
      points = points * 2
    end
  end
end

local function stepBells(s, events)
  for i = #s.bells, 1, -1 do
    local b = s.bells[i]
    if b.state ~= "hang" then
      b.t = b.t - 1
      if b.t <= 0 then
        if b.state == "fall" then
          landBell(s, b, events)
        else
          table.remove(s.bells, i)
        end
      end
    end
  end
end

--- Which way to him, for a cat at this spot.
local function towardPlayer(s, c)
  return s.player.x < c.x and "left" or "right"
end

--- Looks round: straight at him if he's on this floor, and otherwise mostly his way, to a shaft and up after him.
local function aimCat(s, c, rng)
  local p = s.player
  c.think = THINK_TICKS + rng(6)
  if p.mode == "walk" and p.floor == c.floor then
    c.dir = towardPlayer(s, c)
  elseif rng() < 0.7 then
    c.dir = towardPlayer(s, c)
  else
    c.dir = rng(2) == 1 and "left" or "right"
  end
end

--- Goro ducks into any treasure he walks past, and sits there until he's bored or found.
local function tryHide(s, c)
  if c.kind ~= "goro" or c.hideIn > 0 then return end
  for _, good in ipairs(s.goods) do
    if good.floor == c.floor and not good.goro and abs(good.x - c.x) <= 2 then
      good.goro, c.good, c.mode, c.t = true, good, "hide", HIDE_TICKS
      return
    end
  end
end

local function walkCat(s, c, rng)
  c.think = c.think - 1
  if c.think <= 0 then aimCat(s, c, rng) end
  c.hideIn = c.hideIn - 1
  c.budget = c.budget + (c.kind == "goro" and GORO_SPEED or M.catSpeed(s.level))
  while c.budget >= 100 and c.mode == "walk" do
    c.budget = c.budget - 100
    local hit = stepAlong(s, c, c.dir)
    if hit == "door" then
      c.dir, c.think = OPPOSITE[c.dir], BLOCKED_TICKS
    elseif hit == "edge" then
      enterShaft(c)
      c.stray = rng() < STRAY and rng(FLOORS) or nil
    else
      tryHide(s, c)
    end
  end
end

--- The floor he's on, or the one nearest him in a shaft.
local function floorOfPlayer(s)
  local p = s.player
  if p.mode == "walk" then return p.floor end
  return math.max(1, min(FLOORS, floor((p.y - TOP_FLOOR) / FLOOR_H + 0.5) + 1))
end

--- A cat in a shaft gets off at his floor, on his side, and then walks.
local function bounceCat(s, c, rng)
  climb(c, function(_, f)
    if f == (c.stray or floorOfPlayer(s)) then
      local dir = towardPlayer(s, c)
      if not hasSide(c.shaft, dir) then dir = OPPOSITE[dir] end
      c.stray = nil
      leaveShaft(c, f, dir)
      c.think = THINK_TICKS
      return true
    end
  end, function()
    c.stray = rng() < STRAY and rng(FLOORS) or nil
  end)
end

--- A cat sent flying comes home by the roof, as they all first came.
local function stepFlying(c, rng)
  c.x = c.x + DIRS[c.dir] * FLY_SPEED
  if c.x < -8 or c.x >= WIDTH + 8 then c.mode, c.t = "out", RETURN_TICKS end
  if c.mode == "out" then
    local from, to = sectionEnds(rng(#SHAFT_X - 1))
    c.homeSpot = floor((from + to) / 2)
  end
end

local function stepCat(s, c, rng)
  if c.mode == "fly" then
    stepFlying(c, rng)
  elseif c.mode == "out" then
    c.t = c.t - 1
    if c.t <= 0 then
      c.x, c.y, c.floor, c.mode, c.shaft, c.think = c.homeSpot, FLOOR_Y[1], 1, "walk", nil, 0
    end
  elseif c.wait > 0 then
    c.wait = c.wait - 1
  elseif c.stun > 0 then
    c.stun = c.stun - 1
  elseif c.mode == "hide" then
    c.t = c.t - 1
    if c.t <= 0 then
      if c.good then c.good.goro = nil end
      c.good, c.mode, c.hideIn = nil, "walk", HIDE_GAP
    end
  elseif c.mode == "walk" then
    walkCat(s, c, rng)
  else
    bounceCat(s, c, rng)
  end
end

--- Along a floor they catch him. In a shaft they only catch him at his own height, going his way: passing does nothing.
local function touching(p, c)
  if p.mode == "walk" then return c.mode == "walk" and c.floor == p.floor and abs(c.x - p.x) <= CATCH_W end
  return c.mode == "air" and c.shaft == p.shaft and c.vdir == p.vdir and abs(c.y - p.y) <= CATCH_H
end

local function checkCats(s, events)
  if s.after then return end
  local p = s.player
  for _, c in ipairs(s.cats) do
    if harmful(c) and touching(p, c) then
      die(s, events, c.kind)
      return
    end
  end
end

--- The ghost flies straight at him through floors and doors, and no bounce gets past it.
local function stepGhost(s, events)
  local g = s.ghost
  if not g or s.after then return end
  local p = s.player
  local dx, dy = p.x - g.x, p.y - g.y
  g.x = g.x + math.max(-GHOST_X, min(GHOST_X, dx))
  g.y = g.y + math.max(-GHOST_Y, min(GHOST_Y, dy))
  if abs(p.x - g.x) <= GHOST_W and abs(p.y - g.y) <= GHOST_H then die(s, events, "ghost") end
end

local function endRound(s, events, why)
  s.after, s.pause = "level", CLEAR_TICKS
  s.want, s.ghost = nil, nil
  events[#events + 1] = { type = "clear", why = why }
end

--- The clock: a warning, and then the ghost from the far corner. A bonus round just stops.
local function runClock(s, events)
  s.time = s.time - 1
  if s.time == HURRY_TICKS and not s.bonus then events[#events + 1] = { type = "hurry" } end
  if s.time ~= 0 then return end
  if s.bonus then
    endRound(s, events, "time")
  else
    s.ghost = { x = s.player.x < WIDTH / 2 and WIDTH - 5 or 4, y = 6 }
    events[#events + 1] = { type = "ghost" }
  end
end

local function runPopups(s)
  for i = #s.popups, 1, -1 do
    local n = s.popups[i]
    n.left = n.left - 1
    if n.left <= 0 then table.remove(s.popups, i) end
  end
end

--- What comes after a pause: the next life, the next round or the end.
local function endPause(s, events, rng)
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
    buildLevel(s, rng)
    resetActors(s)
    events[#events + 1] = { type = s.bonus and "bonus" or "level" }
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
  runPopups(s)
  runClock(s, events)
  if s.after then return events end
  useDoor(s, events)
  movePlayer(s, events)
  if s.after then return events end
  for _, c in ipairs(s.cats) do stepCat(s, c, rng) end
  stepWaves(s, events)
  stepBells(s, events)
  checkCats(s, events)
  stepGhost(s, events)
  if not s.after and #s.goods == 0 then endRound(s, events, "goods") end
  return events
end

-- ---------------------------------------------------------------- the bot

local BOT_LAPSE = 0.04   -- how often it stops looking, so its runs come to an end
local BOT_CARE = 13      -- cells of room it wants from a cat on its stretch of floor
local BOT_SHUT = 16      -- how near a cat comes through an open door before it shuts it
local BOT_LANDING = 11   -- cells of clear floor it wants where it jumps off

--- The floor a shaft actor passes next.
local function nextFloor(p)
  if p.vdir < 0 then
    for f = FLOORS, 1, -1 do
      if FLOOR_Y[f] < p.y then return f end
    end
    return 1
  end
  for f = 1, FLOORS do
    if FLOOR_Y[f] > p.y then return f end
  end
  return FLOORS
end

--- The goods that look nearest, by how far and how many floors.
local function nearestGood(s)
  local p = s.player
  local here = floorOfPlayer(s)
  local best, bestCost
  for _, good in ipairs(s.goods) do
    local cost = abs(good.x - p.x) + abs((good.floor or here) - here) * 14
    if not best or cost < bestCost then best, bestCost = good, cost end
  end
  return best
end

--- The nearest cat that could reach it along this stretch of floor, and how far that is, with the sign of the way to it.
local function nearestCat(s)
  local p = s.player
  local section = sectionAt(p.x)
  local best, bestGap
  for _, c in ipairs(s.cats) do
    if harmful(c) and onFloor(c, p.floor) and sectionAt(c.x) == section then
      local blocked = false
      for _, d in ipairs(s.doors) do
        if d.floor == p.floor and not d.open and (d.x - p.x) * (d.x - c.x) < 0 then blocked = true end
      end
      if not blocked and (not best or abs(c.x - p.x) < abs(bestGap)) then best, bestGap = c, c.x - p.x end
    end
  end
  return best, bestGap
end

--- Is a tap on this door a good idea now? beyond says the goods are on the other side of it.
local function doorIsWorthIt(s, d, beyond)
  local p = s.player
  local out, ahead = DIRS[d.swing], DIRS[p.dir]
  local catBehind = false
  for _, c in ipairs(s.cats) do
    if harmful(c) and onFloor(c, p.floor) then
      local swung = (c.x - d.x) * out
      local past = (c.x - d.x) * ahead
      if not d.open and d.power then return true end
      if not d.open and swung >= 0 and swung <= SWING_W then return true end
      if d.open and past > 0 and past <= BOT_SHUT then return true end
      if past > 0 and past <= BOT_SHUT * 2 then catBehind = true end
    end
  end
  return not d.open and beyond and not catBehind and (d.x - p.x) * ahead <= STANDOFF + 2
end

--- Which way along this floor for the goods it wants.
local function wayTo(s, good)
  local p = s.player
  local section = sectionAt(p.x)
  if good.floor == p.floor or sectionAt(good.x) ~= section then
    if good.x == p.x then return nil end
    return good.x < p.x and "left" or "right"
  end
  local from, to = sectionEnds(section)
  return p.x - from < to - p.x and "left" or "right"
end

local function botWalk(s, good)
  local p = s.player
  local way = good and wayTo(s, good)
  local d = M.doorAhead(s)
  if d then
    local beyond = way == p.dir and (good.floor ~= p.floor or (good.x - d.x) * DIRS[p.dir] > 0)
    if doorIsWorthIt(s, d, beyond) then return { kind = "door" } end
  end
  local cat, gap = nearestCat(s)
  if cat and abs(gap) <= BOT_CARE then
    local away = gap < 0 and "right" or "left"
    if s.want ~= away then return { kind = "turn", dir = away } end
    return nil
  end
  if way and s.want ~= way then return { kind = "turn", dir = way } end
  return nil
end

--- Is the floor clear where it would land?
local function clearLanding(s, f, dir)
  local shaft = s.player.shaft
  local x = dir == "left" and SHAFT_X[shaft] - 1 or SHAFT_X[shaft] + SHAFT_W
  for _, c in ipairs(s.cats) do
    if harmful(c) and onFloor(c, f) and abs(c.x - x) <= BOT_LANDING then return false end
  end
  return true
end

local function botAir(s, good)
  local p = s.player
  local coming = nextFloor(p)
  local dir = good and (good.x < p.x and "left" or "right") or "right"
  if not hasSide(p.shaft, dir) then dir = OPPOSITE[dir] end
  local worn = s.tramps[p.shaft].hits >= BREAK_BOUNCES - 1 and p.vdir > 0
  local wanted = good and (good.floor == coming or (good.shaft and good.shaft ~= p.shaft))
  if good and good.shaft == p.shaft then wanted = false end
  if worn or (wanted and clearLanding(s, coming, dir)) then
    if s.want ~= dir then return { kind = "turn", dir = dir } end
    return nil
  end
  if s.want then return { kind = "turn", dir = "up" } end
  return nil
end

--- A good but human player for the idle screen and tests: fetch the nearest goods, work the doors, keep off the cats.
function M.bot(s, rng)
  if s.pause > 0 or s.after then return nil end
  if rng() < BOT_LAPSE then return nil end
  local good = nearestGood(s)
  if s.player.mode == "walk" then return botWalk(s, good) end
  return botAir(s, good)
end

return M
