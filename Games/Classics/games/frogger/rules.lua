-- games/frogger/rules.lua
-- Frogger. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The board is 13 rows: the home row on top, five rows of river, a safe median, five rows of road, and the start bank.
-- Across, a row is measured in steps a sixth of a tile wide. A hop is one whole tile.
-- Every lane is a ring of things that turns past the board and comes round again.
-- The clock ticks fast so a hop answers at once, but the world moves on a slower beat: everything shifts together, then
-- holds still. That spares the monitors a full redraw at every tick.

local M = { COLS = 16, ROWS = 13, TILE = 6 }

local TILE = M.TILE
local WIDTH = M.COLS * TILE
local HOME_ROW, MEDIAN_ROW, START_ROW = 1, 7, 13
local START_X = (WIDTH - TILE) / 2
local LIVES = 3
local BEAT = 3              -- ticks between moves of the world
local FROG_TICKS = 300      -- the countdown per frog: 30 seconds at one tick per 100 ms
local DEAD_TICKS = 8        -- how long a lost frog's splat stays before the next frog
local HOP_SCORE = 10
local HOME_SCORE = 50
local SECOND_SCORE = 5      -- for each second left on the countdown when a frog gets home
local LEVEL_SCORE = 500
local LEVEL_SPEEDUP = 0.15  -- each level runs this much faster than the first
local MOST_SPEEDUP = 2      -- and traffic never goes more than this many times as fast
local BAY_COUNT = 5
local BAY_W = 2 * TILE
local BAY_STEP = 3 * TILE   -- the first bay starts one tile in, then there's a tile of hedge between bays

-- A turtle's dive, in beats: up, then sinking as a warning, then under, then coming back.
local DIVE_UP, DIVE_SINKING, DIVE_UNDER, DIVE_RISING = 17, 5, 7, 3
local DIVE_CYCLE = DIVE_UP + DIVE_SINKING + DIVE_UNDER + DIVE_RISING

-- rate is steps per 100 beats. Each ring is at least one thing longer than the board, so nothing shows twice at once.
-- A turtle lane with dive = n has every nth group diving.
local LANES = {
  { row = 2, kind = "log", dir = 1, rate = 135, len = 24, gap = 18, count = 3 },
  { row = 3, kind = "turtle", dir = -1, rate = 180, len = 12, gap = 15, count = 4, dive = 2 },
  { row = 4, kind = "log", dir = 1, rate = 225, len = 36, gap = 18, count = 3 },
  { row = 5, kind = "log", dir = 1, rate = 105, len = 18, gap = 18, count = 3 },
  { row = 6, kind = "turtle", dir = -1, rate = 150, len = 18, gap = 12, count = 4, dive = 2 },
  { row = 8, kind = "car", dir = -1, rate = 150, len = 14, gap = 22, count = 3 },
  { row = 9, kind = "car", dir = 1, rate = 300, len = 8, gap = 46, count = 2 },
  { row = 10, kind = "car", dir = -1, rate = 165, len = 7, gap = 29, count = 3 },
  { row = 11, kind = "car", dir = 1, rate = 135, len = 7, gap = 23, count = 4 },
  { row = 12, kind = "car", dir = -1, rate = 105, len = 7, gap = 29, count = 3 },
}

M.WIDTH, M.HOME_ROW, M.MEDIAN_ROW, M.START_ROW = WIDTH, HOME_ROW, MEDIAN_ROW, START_ROW
M.BAY_COUNT, M.BAY_W, M.FROG_TICKS, M.BEAT = BAY_COUNT, BAY_W, FROG_TICKS, BEAT
M.DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local DIRECTIONS = M.DIRECTIONS
local floor = math.floor

--- The left edge of bay i.
function M.bayLeft(i)
  return TILE + (i - 1) * BAY_STEP
end

--- The bay a point on the home row falls in, or nil for hedge.
local function bayAt(x)
  for i = 1, BAY_COUNT do
    local left = M.bayLeft(i)
    if x >= left and x < left + BAY_W then return i end
  end
  return nil
end

--- Where a frog's middle is, across the row.
local function centre(x)
  return x + TILE / 2
end

local function buildLane(def, rng)
  local lane = {
    row = def.row, kind = def.kind, dir = def.dir, rate = def.rate, acc = 0,
    ring = def.count * (def.len + def.gap), items = {},
  }
  lane.shift = rng(lane.ring) - 1
  for i = 1, def.count do
    local item = { at = (i - 1) * (def.len + def.gap), len = def.len }
    if def.dive and i % def.dive == 0 then item.phase = rng(DIVE_CYCLE) - 1 end
    lane.items[i] = item
  end
  return lane
end

--- Put a new frog on the start bank, with its countdown full and no taps left over.
local function newFrog(s)
  s.frog = { x = START_X, row = START_ROW, facing = "up" }
  s.furthest = START_ROW
  s.time = FROG_TICKS
  s.hops = {}
  s.splat = nil
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = {
    score = 0, level = 1, lives = LIVES, over = false,
    clock = 0, beats = 0, dead = 0, lanes = {}, bays = {}, filled = 0,
  }
  for _, def in ipairs(LANES) do s.lanes[def.row] = buildLane(def, opts.rng) end
  for i = 1, BAY_COUNT do s.bays[i] = false end
  newFrog(s)
  return s
end

--- A player's input. Each tap is one hop, taken in turn at the next steps: unlike Snake's direction, it doesn't stay set.
-- The action is "turn" because that's what base.splitAction sends. A tap while a frog is lost means nothing.
function M.input(s, action)
  if action.kind == "turn" and DIRECTIONS[action.dir] and s.dead == 0 and not s.over then
    s.hops[#s.hops + 1] = action.dir
  end
end

--- Steps per 100 beats for a lane at this level.
local function speed(s, lane)
  return floor(lane.rate * math.min(MOST_SPEEDUP, 1 + (s.level - 1) * LEVEL_SPEEDUP))
end

--- How far a lane will have moved after n more beats, in steps, signed.
local function drift(s, lane, n)
  return floor((lane.acc + speed(s, lane) * n) / 100) * lane.dir
end

--- The left edge of an item, with the lane moved on by extra steps. It may be off the board.
function M.itemLeft(lane, item, extra)
  local left = (item.at + lane.shift + (extra or 0)) % lane.ring
  if left > lane.ring - item.len then left = left - lane.ring end
  return left
end

--- What a diving group is doing at a given beat: "up", "sinking", "under" or "rising". Other turtles and logs stay up.
function M.diveStage(item, beats)
  if not item.phase then return "up" end
  local t = (beats + item.phase) % DIVE_CYCLE
  if t < DIVE_UP then return "up" end
  if t < DIVE_UP + DIVE_SINKING then return "sinking" end
  if t < DIVE_UP + DIVE_SINKING + DIVE_UNDER then return "under" end
  return "rising"
end

--- Does any car in a lane, moved on by extra steps, touch the span from lo up to hi?
local function carIn(lane, lo, hi, extra)
  for _, item in ipairs(lane.items) do
    local left = M.itemLeft(lane, item, extra)
    if left < hi and left + item.len > lo then return true end
  end
  return false
end

--- Is something afloat at a point of a river lane, moved on by extra steps, at a given beat?
local function floats(lane, x, extra, beats)
  for _, item in ipairs(lane.items) do
    local left = M.itemLeft(lane, item, extra)
    if x >= left and x < left + item.len and M.diveStage(item, beats) ~= "under" then return true end
  end
  return false
end

--- Lose this frog. The next one comes after the splat, unless that was the last.
local function lose(s, why, events)
  s.lives = s.lives - 1
  s.dead = DEAD_TICKS
  s.hops = {}
  s.splat = { x = s.frog.x, row = s.frog.row, why = why }
  if s.lives <= 0 then s.over = true end
  events[#events + 1] = { type = "die", why = why }
end

--- A frog reached an empty bay. The fifth one clears the bays and starts a faster level.
local function reachHome(s, bay, events)
  s.bays[bay] = true
  s.filled = s.filled + 1
  s.score = s.score + HOME_SCORE + SECOND_SCORE * math.ceil(s.time / 10)
  events[#events + 1] = { type = "home" }
  if s.filled == BAY_COUNT then
    s.filled = 0
    for i = 1, BAY_COUNT do s.bays[i] = false end
    s.level = s.level + 1
    s.score = s.score + LEVEL_SCORE
    events[#events + 1] = { type = "level" }
  end
  newFrog(s)
end

--- Take one hop. Sideways stops at the edge of the board, and a frog already past it stays where it is.
local function hop(s, dir, events)
  local f = s.frog
  local d = DIRECTIONS[dir]
  f.facing = dir
  if d[1] < 0 then f.x = math.max(f.x - TILE, math.min(f.x, 0)) end
  if d[1] > 0 then f.x = math.min(f.x + TILE, math.max(f.x, WIDTH - TILE)) end
  f.row = math.min(START_ROW, f.row + d[2])
  if f.row < s.furthest then
    s.furthest = f.row
    s.score = s.score + HOP_SCORE
  end
  events[#events + 1] = { type = "hop" }
end

--- See what the frog has landed on, or been carried into.
local function check(s, events)
  local f = s.frog
  local mid = centre(f.x)
  local lane = s.lanes[f.row]
  if mid < 0 or mid >= WIDTH then
    lose(s, "edge", events)
  elseif f.row == HOME_ROW then
    local bay = bayAt(mid)
    if bay and not s.bays[bay] then
      reachHome(s, bay, events)
    else
      lose(s, "hedge", events)
    end
  elseif lane and lane.kind == "car" and carIn(lane, f.x + 1, f.x + TILE - 1, 0) then
    lose(s, "road", events)
  elseif lane and lane.kind ~= "car" and not floats(lane, mid, 0, s.beats) then
    lose(s, "water", events)
  elseif s.time <= 0 then
    lose(s, "time", events)
  end
end

--- Move a lane by this beat's steps, carrying a frog that rides on it.
local function moveLane(s, lane)
  lane.acc = lane.acc + speed(s, lane)
  local steps = floor(lane.acc / 100)
  lane.acc = lane.acc - steps * 100
  local move = steps * lane.dir
  lane.shift = (lane.shift + move) % lane.ring
  if s.dead == 0 and lane.row == s.frog.row and lane.kind ~= "car" then s.frog.x = s.frog.x + move end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s)
  if s.over then return {} end
  s.clock = s.clock + 1
  if s.clock % BEAT == 0 then
    s.beats = s.beats + 1
    s.time = s.time - BEAT
    for row = HOME_ROW, START_ROW do
      if s.lanes[row] then moveLane(s, s.lanes[row]) end
    end
  end
  if s.dead > 0 then
    s.dead = s.dead - 1
    if s.dead == 0 then newFrog(s) end
    return {}
  end
  local events = {}
  local dir = table.remove(s.hops, 1)
  if dir then hop(s, dir, events) end
  check(s, events)
  return events
end

-- ---------------------------------------------------------------- the bot

local LOOK_AHEAD = 4   -- the beats a place must stay safe before the bot hops there
local DANGER = 2       -- the beats of safety it wants where it stands, or it moves
local SLIP = 0.006     -- the chance, each time it could hop, that it hops up without looking

--- Will a frog at this place last the next beats, riding if it's on the river?
local function lasts(s, row, x, beats)
  local lane = s.lanes[row]
  if row == MEDIAN_ROW or row == START_ROW then return true end
  if not lane then return false end
  for n = 0, beats do
    local move = drift(s, lane, n)
    if lane.kind == "car" then
      if carIn(lane, x, x + TILE, move) then return false end
    else
      local mid = centre(x) + move
      if mid < TILE or mid >= WIDTH - TILE then return false end
      if not (floats(lane, mid - 1, move, s.beats + n) and floats(lane, mid + 1, move, s.beats + n)) then return false end
    end
  end
  return true
end

--- The sideways drift of this frog over the next tick, if it's riding and a beat is due.
local function rideNext(s)
  local lane = s.lanes[s.frog.row]
  if lane and lane.kind ~= "car" and (s.clock + 1) % BEAT == 0 then return drift(s, lane, 1) end
  return 0
end

--- Would this hop land somewhere good for the next beats?
local function hopLasts(s, dir, beats)
  local f = s.frog
  local d = DIRECTIONS[dir]
  local x, row = f.x + rideNext(s) + d[1] * TILE, f.row + d[2]
  if row > START_ROW or x < 0 or x > WIDTH - TILE then return false end
  if row == HOME_ROW then
    local bay = bayAt(centre(x))
    return bay ~= nil and not s.bays[bay]
  end
  return lasts(s, row, x, beats)
end

--- On the last river row, a hop along the log toward the nearest empty bay.
local function towardBay(s)
  local mid = centre(s.frog.x)
  local best, bestDistance
  for i = 1, BAY_COUNT do
    local distance = M.bayLeft(i) + TILE - mid
    if not s.bays[i] and (not best or math.abs(distance) < math.abs(bestDistance)) then best, bestDistance = i, distance end
  end
  if not best or math.abs(bestDistance) < TILE then return nil end
  local dir = bestDistance < 0 and "left" or "right"
  return hopLasts(s, dir, LOOK_AHEAD) and dir or nil
end

--- Will the log under the last river row still pass an empty bay? Those logs only run right.
local function bayAhead(s)
  for i = 1, BAY_COUNT do
    if not s.bays[i] and M.bayLeft(i) + BAY_W > centre(s.frog.x) then return true end
  end
  return false
end

--- The bot's calm move: forward if it can. Near the bays, it goes back to the leftward turtles for another pass.
local function calmHop(s, rng)
  local row = s.frog.row
  local last = HOME_ROW + 1
  if row == last then
    if hopLasts(s, "up", LOOK_AHEAD) then return "up" end
    if bayAhead(s) then return towardBay(s) end
    return hopLasts(s, "down", DANGER) and "down" or nil
  end
  if row == last + 1 and not bayAhead(s) then return nil end
  if rng() < SLIP or hopLasts(s, "up", LOOK_AHEAD) then return "up" end
  return nil
end

--- A plain player for the idle screen and tests: hop when the way ahead is clear, get out of trouble, and now and then slip.
function M.bot(s, rng)
  if s.over or s.dead > 0 or #s.hops > 0 then return nil end
  local dir
  if not lasts(s, s.frog.row, s.frog.x, DANGER) then
    for _, way in ipairs({ "up", "left", "right", "down" }) do
      if not dir and hopLasts(s, way, DANGER) then dir = way end
    end
  elseif s.clock % BEAT == 0 then
    dir = calmHop(s, rng)
  end
  return dir and { kind = "turn", dir = dir } or nil
end

return M
