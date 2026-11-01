-- games/minesweeper/rules.lua
-- Minesweeper. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- s.grid[y][x] is a square: mine, count (the mines touching it), open and flag. Mines are laid by the first dig of a
-- board, away from that square, so it always opens a zero. Open every safe square to clear the board; one mine ends the run.

local M = { TICK_MS = 100 }

local floor, max, min = math.floor, math.max, math.min

local MODE_FLIP = { dig = "flag", flag = "dig" }
local MINES_PER_LEVEL = 6   -- on the 16x16 boards
local MINE_CAP = 58         -- a little past expert density: any more and most of a board is guessing
local PAUSE_STEPS = 20      -- how long BOARD CLEAR stays up
local ENDING_STEPS = 20     -- the mines stay in plain view this long, because the final board's banner covers the middle
local CLEAR_BONUS = 50      -- for each level
local TIME_BONUS = 10       -- for each mine, on a board cleared in no time
local PAR_SECONDS = 6       -- for each mine, the time at which the time bonus has run out
local BOT_EVERY = 6         -- steps between the bot's moves

--- Width, height and mines of a level's board.
function M.board(level)
  if level == 1 then return 9, 9, 10 end
  if level == 2 then return 12, 12, 22 end
  return 16, 16, min(MINE_CAP, 40 + (level - 3) * MINES_PER_LEVEL)
end

local function startBoard(s)
  s.cols, s.rows, s.mines = M.board(s.level)
  s.grid = {}
  for y = 1, s.rows do
    s.grid[y] = {}
    for x = 1, s.cols do s.grid[y][x] = { mine = false, count = 0, open = false, flag = false } end
  end
  s.mode, s.placed, s.opened, s.flags, s.clock = "dig", false, 0, 0, 0
  s.queue, s.banner = {}, nil
end

--- A fresh game. Nothing needs chance until the first dig.
function M.new()
  local s = { score = 0, level = 1, over = false, steps = 0, pause = 0, ending = 0 }
  startBoard(s)
  return s
end

--- The squares around one, as { x, y } pairs.
local function neighbours(s, x, y)
  local list = {}
  for ny = max(1, y - 1), min(s.rows, y + 1) do
    for nx = max(1, x - 1), min(s.cols, x + 1) do
      if nx ~= x or ny ~= y then list[#list + 1] = { nx, ny } end
    end
  end
  return list
end

--- Lay mines on the listed { x, y } squares and work out every count.
function M.setMines(s, squares)
  for _, at in ipairs(squares) do
    s.grid[at[2]][at[1]].mine = true
    for _, n in ipairs(neighbours(s, at[1], at[2])) do
      local other = s.grid[n[2]][n[1]]
      other.count = other.count + 1
    end
  end
  s.placed = true
end

--- Pick the mines from everywhere but the first square and those touching it, so it opens a zero.
local function layMines(s, x, y, rng)
  local spots, picked = {}, {}
  for sy = 1, s.rows do
    for sx = 1, s.cols do
      if math.abs(sx - x) > 1 or math.abs(sy - y) > 1 then spots[#spots + 1] = { sx, sy } end
    end
  end
  for i = 1, s.mines do
    local j = i + rng(#spots - i + 1) - 1
    spots[i], spots[j] = spots[j], spots[i]
    picked[i] = spots[i]
  end
  M.setMines(s, picked)
end

--- Open a square and, from a zero, everything around it. Flagged squares stay shut. Returns how many opened.
local function flood(s, x, y)
  local stack, opened = { { x, y } }, 0
  while #stack > 0 do
    local at = table.remove(stack)
    local cell = s.grid[at[2]][at[1]]
    if not cell.open and not cell.flag then
      cell.open = true
      opened = opened + 1
      if cell.count == 0 then
        for _, n in ipairs(neighbours(s, at[1], at[2])) do stack[#stack + 1] = n end
      end
    end
  end
  return opened
end

--- How the time bonus falls: all of it at no time, none of it at the par time. Only ever paid, so it can't cost a point.
local function timeBonus(s)
  local seconds = s.clock * M.TICK_MS / 1000
  return max(0, floor(s.mines * TIME_BONUS * (1 - seconds / (s.mines * PAR_SECONDS))))
end

local function clearBoard(s, events)
  local clear, time = CLEAR_BONUS * s.level, timeBonus(s)
  s.score = s.score + clear + time
  s.banner = { clear = clear, time = time }
  s.pause = PAUSE_STEPS
  s.flags = s.mines
  for y = 1, s.rows do
    for x = 1, s.cols do
      local cell = s.grid[y][x]
      if cell.mine then cell.flag = true end
    end
  end
  events[#events + 1] = { type = "clear" }
end

--- Open these squares together. Any mine among them ends the run before the rest open.
local function open(s, squares, events)
  for _, at in ipairs(squares) do
    if s.grid[at[2]][at[1]].mine then
      s.hit = { at[1], at[2] }
      s.ending = ENDING_STEPS
      events[#events + 1] = { type = "boom" }
      return
    end
  end
  local opened = 0
  for _, at in ipairs(squares) do opened = opened + flood(s, at[1], at[2]) end
  s.opened = s.opened + opened
  s.score = s.score + opened
  events[#events + 1] = { type = "open", count = opened }
  if s.opened == s.cols * s.rows - s.mines then clearBoard(s, events) end
end

--- A tap on an open number: if its flags match its count, open the rest around it, whatever the flags say.
local function chord(s, x, y, events)
  local flags, shut = 0, {}
  for _, n in ipairs(neighbours(s, x, y)) do
    local other = s.grid[n[2]][n[1]]
    if other.flag then
      flags = flags + 1
    elseif not other.open then
      shut[#shut + 1] = n
    end
  end
  if flags == s.grid[y][x].count and #shut > 0 then open(s, shut, events) end
end

local function tap(s, x, y, rng, events)
  local cell = s.grid[y][x]
  if cell.open then
    chord(s, x, y, events)
  elseif s.mode == "flag" then
    cell.flag = not cell.flag
    s.flags = s.flags + (cell.flag and 1 or -1)
    events[#events + 1] = { type = cell.flag and "flag" or "unflag" }
  elseif not cell.flag then
    if not s.placed then layMines(s, x, y, rng) end
    open(s, { { x, y } }, events)
  end
end

--- The board has stopped taking taps, for BOARD CLEAR or a mine.
local function waiting(s)
  return s.over or s.pause > 0 or s.ending > 0
end

--- A player's input: { kind = "mode" } or { kind = "tap", x, y }. Every tap counts, so they queue for the next step.
function M.input(s, action)
  if waiting(s) then return end
  local onBoard = action.kind == "tap" and s.grid[action.y] and s.grid[action.y][action.x]
  if action.kind == "mode" or onBoard then s.queue[#s.queue + 1] = action end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  s.steps = s.steps + 1
  if s.ending > 0 then
    s.ending = s.ending - 1
    s.over = s.ending == 0
    return {}
  end
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause > 0 then return {} end
    s.level = s.level + 1
    startBoard(s)
    return { { type = "board" } }
  end
  local events, queue = {}, s.queue
  s.queue = {}
  for _, action in ipairs(queue) do
    if waiting(s) then break end
    if action.kind == "mode" then
      s.mode = MODE_FLIP[s.mode]
      events[#events + 1] = { type = "mode" }
    else
      tap(s, action.x, action.y, rng, events)
    end
  end
  if s.placed and not waiting(s) then s.clock = s.clock + 1 end
  return events
end

function M.minesLeft(s)
  return s.mines - s.flags
end

--- Seconds on this board's clock.
function M.seconds(s)
  return floor(s.clock * M.TICK_MS / 1000)
end

-- ---------------------------------------------------------------- the bot: it sees only what a player sees

--- What an open number still says: the shut squares around it, and how many of those are mines. Nil if it says nothing.
local function clue(s, x, y)
  local cell = s.grid[y][x]
  if not cell.open or cell.count == 0 then return nil end
  local hidden, flags = {}, 0
  for _, n in ipairs(neighbours(s, x, y)) do
    local other = s.grid[n[2]][n[1]]
    if other.flag then
      flags = flags + 1
    elseif not other.open then
      hidden[#hidden + 1] = n
    end
  end
  if #hidden == 0 then return nil end
  return { x = x, y = y, hidden = hidden, need = cell.count - flags }
end

local function allClues(s)
  local clues = {}
  for y = 1, s.rows do
    for x = 1, s.cols do clues[#clues + 1] = clue(s, x, y) end
  end
  return clues
end

--- A tap in the mode it needs, or the mode button first. A player has to do the same.
local function inMode(s, mode, at)
  if s.mode ~= mode then return { kind = "mode" } end
  return { kind = "tap", x = at[1], y = at[2] }
end

--- If one clue's squares are all among another's, the difference holds exactly the difference of their mines.
local function subsetMove(s, clues)
  for _, small in ipairs(clues) do
    local inside = {}
    for _, at in ipairs(small.hidden) do inside[at[2] * 100 + at[1]] = true end
    for _, big in ipairs(clues) do
      if #big.hidden > #small.hidden and math.abs(big.x - small.x) <= 2 and math.abs(big.y - small.y) <= 2 then
        local rest = {}
        for _, at in ipairs(big.hidden) do
          if not inside[at[2] * 100 + at[1]] then rest[#rest + 1] = at end
        end
        if #big.hidden - #rest == #small.hidden then
          local mines = big.need - small.need
          if mines == 0 then return inMode(s, "dig", rest[1]) end
          if mines == #rest then return inMode(s, "flag", rest[1]) end
        end
      end
    end
  end
  return nil
end

--- Nothing is certain: dig where a mine is least likely, as best the clues can say.
local function guess(s, clues, rng)
  local risk, shut = {}, 0
  for y = 1, s.rows do
    for x = 1, s.cols do
      local cell = s.grid[y][x]
      if not cell.open and not cell.flag then shut = shut + 1 end
    end
  end
  local spread = M.minesLeft(s) / max(1, shut)
  for _, c in ipairs(clues) do
    for _, at in ipairs(c.hidden) do
      local key = at[2] * 100 + at[1]
      risk[key] = max(risk[key] or 0, c.need / #c.hidden)
    end
  end
  local best, lowest = {}, math.huge
  for y = 1, s.rows do
    for x = 1, s.cols do
      local cell = s.grid[y][x]
      if not cell.open and not cell.flag then
        local here = risk[y * 100 + x] or spread
        if here < lowest then best, lowest = {}, here end
        if here == lowest then best[#best + 1] = { x, y } end
      end
    end
  end
  if #best == 0 then return nil end
  return inMode(s, "dig", best[rng(#best)])
end

--- A real player for the idle screen and tests, at a human pace: open what a satisfied number proves safe, flag what must
--- be a mine, reason across two numbers, and only then guess.
function M.bot(s, rng)
  if waiting(s) or s.steps % BOT_EVERY ~= 0 then return nil end
  local clues = allClues(s)
  for _, c in ipairs(clues) do
    if c.need == 0 then return { kind = "tap", x = c.x, y = c.y } end
  end
  for _, c in ipairs(clues) do
    if c.need == #c.hidden then return inMode(s, "flag", c.hidden[1]) end
  end
  return subsetMove(s, clues) or guess(s, clues, rng)
end

return M
