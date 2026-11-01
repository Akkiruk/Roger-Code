-- games/tron/rules.lua
-- Light cycles for two players, first to five rounds. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Each cycle leaves a solid wall on every cell it has been on. Both move on the same step, faster as a round goes on.
-- A round runs: count (the countdown), run, crash (the burst), then the next round or the end of the match.
-- Only the tick's pace is uneven: at 100 ms a step, a pace of 67 moves on two steps of three, which averages 150 ms a cell.

local M = { COLS = 39, ROWS = 33, WIN_ROUNDS = 5 }

local COLS, ROWS = M.COLS, M.ROWS
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local LEFT_OF = { up = "left", left = "down", down = "right", right = "up" }
local RIGHT_OF = { up = "right", right = "down", down = "left", left = "up" }
-- Opposite corners of the middle, each a half-turn of the other, so it's fair and nobody starts on a collision course.
local START_X = { 8, 32 }
local START_Y = { 11, 23 }
local START_DIR = { "right", "left" }

local COUNT_TICKS = 30      -- three seconds of 3, 2, 1 at the top of a round
local TICKS_PER_NUMBER = 10
local CRASH_TICKS = 16      -- how long the burst shows before the next round
local PACE_START = 67       -- out of 100, the share of a cell a cycle moves each step of the clock: about one every 150 ms
local PACE_TOP = 90         -- about one cell every 110 ms: steering by the wall is hard enough without going any faster
local RAMP_TICKS = 20       -- steps of the clock for each point of pace: a gentle rise over about 45 seconds
local MAX_TURNS = 2         -- taps held for the next moves, so a quick hairpin isn't lost
local BOT_ERROR = 0.04      -- the chance the bot picks any safe way, not the best one
local STRAIGHT_BONUS = 24   -- what going straight is worth to the bot, so it does not weave for a few cells of ground
local CONTESTED = 100000    -- the bot takes any other way before it risks a head-on, or two bots would draw for ever

M.DIRECTIONS = DIRECTIONS
M.COUNT_TICKS, M.TICKS_PER_NUMBER, M.CRASH_TICKS = COUNT_TICKS, TICKS_PER_NUMBER, CRASH_TICKS
M.PACE_START, M.PACE_TOP, M.RAMP_TICKS = PACE_START, PACE_TOP, RAMP_TICKS

local function emptyWalls()
  local walls = {}
  for y = 1, ROWS do
    local row = {}
    for x = 1, COLS do row[x] = 0 end
    walls[y] = row
  end
  return walls
end

--- A cycle on its start line, with its first cell of wall under it.
local function placeCycle(s, player)
  local x, y = START_X[player], START_Y[player]
  s.walls[y][x] = player
  return { x = x, y = y, dir = START_DIR[player], turns = {}, trail = { { x, y } } }
end

--- A clean arena and a countdown.
local function startRound(s)
  s.round = s.round + 1
  s.walls = emptyWalls()
  s.phase, s.wait, s.pace, s.budget, s.ticks = "count", COUNT_TICKS, PACE_START, 0, 0
  s.bursts, s.roundWinner = {}, nil
  s.cycles = { placeCycle(s, 1), placeCycle(s, 2) }
end

--- A fresh match. The arena is the same every round, so nothing here is left to chance. The shell counts in a match, so the
-- first round goes straight to run, and only the rounds after it count themselves in.
function M.new()
  local s = { score = { 0, 0 }, round = 0, over = false, winner = nil }
  startRound(s)
  s.phase, s.wait = "run", 0
  return s
end

--- A player's tap. The next turns wait in a short line, and each is checked against the one before it, not just the way the
-- cycle faces now. Turning back on yourself does nothing.
function M.input(s, player, action)
  local c = s.cycles[player]
  if s.over or s.phase == "crash" or not c or action.kind ~= "turn" or not DIRECTIONS[action.dir] then return end
  local last = c.turns[#c.turns] or c.dir
  if action.dir ~= last and action.dir ~= OPPOSITE[last] and #c.turns < MAX_TURNS then
    c.turns[#c.turns + 1] = action.dir
  end
end

--- What stops a cycle at x, y, or nil if the way is clear.
local function hit(s, player, x, y)
  if x < 1 or x > COLS or y < 1 or y > ROWS then return "edge" end
  local wall = s.walls[y][x]
  if wall == 0 then return nil end
  return wall == player and "own" or "other"
end

--- The round ends here: score it, and show the burst.
local function endRound(s, crashes, events)
  s.bursts = {}
  for _, crash in ipairs(crashes) do
    s.bursts[#s.bursts + 1] = { x = crash.x, y = crash.y, player = crash.player }
    events[#events + 1] = { type = "crash", player = crash.player, kind = crash.kind, x = crash.x, y = crash.y }
  end
  local winner = #crashes == 2 and 0 or 3 - crashes[1].player
  if winner ~= 0 then s.score[winner] = s.score[winner] + 1 end
  s.roundWinner = winner
  s.phase, s.wait = "crash", CRASH_TICKS
  events[#events + 1] = { type = "round", winner = winner }
end

--- Both cycles move one cell, together. Each is judged on the arena as it stood before the step, so neither gets to go first.
local function moveCycles(s, events)
  local targets, crashes = {}, {}
  for p, c in ipairs(s.cycles) do
    if #c.turns > 0 then
      c.dir = table.remove(c.turns, 1)
      events[#events + 1] = { type = "turn", player = p, dir = c.dir }
    end
    local d = DIRECTIONS[c.dir]
    targets[p] = { c.x + d[1], c.y + d[2] }
  end
  local a, b = s.cycles[1], s.cycles[2]
  local sameCell = targets[1][1] == targets[2][1] and targets[1][2] == targets[2][2]
  local swapped = targets[1][1] == b.x and targets[1][2] == b.y and targets[2][1] == a.x and targets[2][2] == a.y
  for p, c in ipairs(s.cycles) do
    local kind = (sameCell or swapped) and "head" or hit(s, p, targets[p][1], targets[p][2])
    if kind then crashes[#crashes + 1] = { player = p, kind = kind, x = c.x, y = c.y } end
  end
  for p, c in ipairs(s.cycles) do
    local crashed = false
    for _, crash in ipairs(crashes) do crashed = crashed or crash.player == p end
    if not crashed then
      c.x, c.y = targets[p][1], targets[p][2]
      s.walls[c.y][c.x] = p
      c.trail[#c.trail + 1] = { c.x, c.y }
    end
  end
  if #crashes > 0 then endRound(s, crashes, events) end
end

local function countStep(s, events)
  if s.wait % TICKS_PER_NUMBER == 0 then events[#events + 1] = { type = "count", n = s.wait / TICKS_PER_NUMBER } end
  s.wait = s.wait - 1
  if s.wait == 0 then
    s.phase = "run"
    events[#events + 1] = { type = "go" }
  end
end

local function paceAt(ticks)
  return math.min(PACE_TOP, PACE_START + math.floor(ticks / RAMP_TICKS))
end

local function runStep(s, events)
  s.ticks = s.ticks + 1
  s.pace = paceAt(s.ticks)
  s.budget = s.budget + s.pace
  if s.budget >= 100 then
    s.budget = s.budget - 100
    moveCycles(s, events)
  end
end

--- The burst has played: the match ends here if the round settled it, so the last crash still gets seen.
local function crashStep(s, events)
  s.wait = s.wait - 1
  if s.wait > 0 then return end
  for p = 1, 2 do
    if s.score[p] >= M.WIN_ROUNDS then
      s.over, s.winner = true, p
      events[#events + 1] = { type = "over", winner = p }
      return
    end
  end
  startRound(s)
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s)
  local events = {}
  if s.over then return events end
  if s.phase == "count" then
    countStep(s, events)
  elseif s.phase == "crash" then
    crashStep(s, events)
  else
    runStep(s, events)
  end
  return events
end

-- ---------------------------------------------------------------- the bot

-- Cells get one number, with a gap at the end of each row, so stepping off the arena lands on nothing.
local PAD = COLS + 2
local NEIGHBOURS = { 1, -1, PAD, -PAD }

local function freeCells(s)
  local free = {}
  for y = 1, ROWS do
    local row = s.walls[y]
    for x = 1, COLS do
      if row[x] == 0 then free[y * PAD + x] = true end
    end
  end
  return free
end

--- Add the cells next to a front that nobody holds yet, and return them. Returns how many were taken as well.
local function spread(free, held, front)
  local nextFront, n = {}, 0
  for _, k in ipairs(front) do
    for _, step in ipairs(NEIGHBOURS) do
      local to = k + step
      if free[to] and not held[to] then
        held[to] = true
        n = n + 1
        nextFront[n] = to
      end
    end
  end
  return nextFront, n
end

--- A flood fill from both cycles at once: how many open cells would the one at mine reach before the one at theirs? A cell
-- they would both reach on the same step counts as theirs, which is the careful way to see it.
local function territory(free, mine, theirs)
  local held = { [mine] = true }
  local myFront, theirFront = { mine }, { theirs }
  local total = 1
  while #myFront > 0 do
    theirFront = spread(free, held, theirFront)
    local n
    myFront, n = spread(free, held, myFront)
    total = total + n
  end
  return total
end

--- How many ways on from a cell. Fewer is better once a cycle is alone: it hugs the wall and uses up its space slowly.
local function exits(free, k)
  local n = 0
  for _, step in ipairs(NEIGHBOURS) do
    if free[k + step] then n = n + 1 end
  end
  return n
end

local function nextTo(k, other)
  for _, step in ipairs(NEIGHBOURS) do
    if k + step == other then return true end
  end
  return false
end

--- The ways a cycle can go without hitting something at once, each with how much of the arena that leaves it.
local function options(s, player)
  local c, foe = s.cycles[player], s.cycles[3 - player]
  local free = freeCells(s)
  local foeAt = foe.y * PAD + foe.x
  local out = {}
  for _, dir in ipairs({ c.dir, LEFT_OF[c.dir], RIGHT_OF[c.dir] }) do
    local d = DIRECTIONS[dir]
    local k = (c.y + d[2]) * PAD + c.x + d[1]
    if free[k] then
      free[k] = nil
      local value = territory(free, k, foeAt) * 4 - exits(free, k)
      free[k] = true
      if dir == c.dir then value = value + STRAIGHT_BONUS end
      if nextTo(k, foeAt) then value = value - CONTESTED end
      out[#out + 1] = { dir = dir, value = value }
    end
  end
  return out, c.dir
end

--- Looks only on a step when it is about to move: it floods the arena for each way on and takes the best. Now and then it
-- takes any safe way instead, which is what makes it beatable.
function M.bot(s, rng, player)
  local c = s.cycles[player]
  if s.over or s.phase ~= "run" or #c.turns > 0 or s.budget + paceAt(s.ticks + 1) < 100 then return nil end
  local ways, straight = options(s, player)
  if #ways == 0 then return nil end
  local best = ways[1]
  for _, way in ipairs(ways) do
    if way.value > best.value then best = way end
  end
  if rng() < BOT_ERROR then best = ways[rng(#ways)] end
  if best.dir == straight then return nil end
  return { kind = "turn", dir = best.dir }
end

return M
