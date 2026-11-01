-- games/blocks/rules.lua
-- Blocks, the falling-blocks classic. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- The well is a table of rows, and a cell holds a piece's letter or false. Rows -1 and 0 sit out of sight above the top,
-- so a piece can turn up there. A tap sets an aim, a column the piece keeps sliding to until it lands, so the order of
-- the taps doesn't matter and a repeated tap can't overshoot.

local M = { COLS = 10, ROWS = 20 }

local COLS, ROWS = M.COLS, M.ROWS
local TOP = -1           -- the highest row, out of sight
local PER_LEVEL = 10     -- lines for each level
local LINE_SCORE = { 100, 300, 500, 800 }
local LOCK_TICKS = 3     -- steps a landed piece waits before it locks, however fast the fall
local DROP_GUARD = 2     -- steps a new piece ignores DROP, so a double tap can't throw it down too
local FALL_STEPS = { 8, 6, 5, 4, 3, 2, 2, 1 } -- steps between falls, by level: the NES game's curve, 0.8 s a row to 0.1 s
local ENDING_TICKS = 12  -- steps the full well stays up after a top-out, before the run ends
local MAX_INPUTS = 4     -- taps kept for the next step
local KICKS = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { -2, 0 }, { 2, 0 } } -- where a turn may land, tried in order
local LETTERS = { "I", "J", "L", "O", "S", "T", "Z" }

-- Each piece in its box, as { column, row } from the box's top left. A box is 4 wide for I, 2 for O, otherwise 3.
local PIECES = {
  I = { size = 4, cells = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } } },
  J = { size = 3, cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  L = { size = 3, cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  O = { size = 2, cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } },
  S = { size = 3, cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } } },
  T = { size = 3, cells = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  Z = { size = 3, cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } } },
}

M.LETTERS = LETTERS

--- One quarter turn clockwise inside a box.
local function turned(cells, size)
  local out = {}
  for i, c in ipairs(cells) do out[i] = { size - 1 - c[2], c[1] } end
  return out
end

--- The columns a set of cells covers, as offsets from the box.
local function span(cells)
  local lo, hi = COLS, -COLS
  for _, c in ipairs(cells) do
    lo, hi = math.min(lo, c[1]), math.max(hi, c[1])
  end
  return lo, hi
end

-- SHAPES[letter][rot] is the four cells at that turn, 0 to 3, with the columns they cover.
local SHAPES = {}
for letter, piece in pairs(PIECES) do
  local cells = piece.cells
  SHAPES[letter] = {}
  for rot = 0, 3 do
    local lo, hi = span(cells)
    SHAPES[letter][rot] = { cells = cells, lo = lo, hi = hi }
    cells = turned(cells, piece.size)
  end
end

local function emptyRow()
  local row = {}
  for x = 1, COLS do row[x] = false end
  return row
end

--- Would a piece fit here? Only the sides, the floor and the stack stop it.
local function fits(s, letter, rot, x, y)
  for _, c in ipairs(SHAPES[letter][rot].cells) do
    local cx, cy = x + c[1], y + c[2]
    if cx < 1 or cx > COLS or cy < TOP or cy > ROWS or s.board[cy][cx] then return false end
  end
  return true
end

local function settle(s, letter, rot, x, y, value)
  for _, c in ipairs(SHAPES[letter][rot].cells) do
    s.board[y + c[2]][x + c[1]] = value
  end
end

--- The row a piece would come to rest on, falling straight down from y.
local function landingRow(s, letter, rot, x, y)
  while fits(s, letter, rot, x, y + 1) do y = y + 1 end
  return y
end

--- The cells of a piece, as { column, row } in the well. The view draws these.
function M.cells(letter, rot, x, y)
  local out = {}
  for i, c in ipairs(SHAPES[letter][rot].cells) do out[i] = { x + c[1], y + c[2] } end
  return out
end

--- The row the falling piece would land on, for the ghost.
function M.landing(s)
  local p = s.piece
  return landingRow(s, p.letter, p.rot, p.x, p.y)
end

--- Steps between falls, down to one.
local function delay(s)
  return FALL_STEPS[math.min(s.level, #FALL_STEPS)]
end

--- The next letter from the bag: all seven, shuffled, then a new bag.
local function draw(s, rng)
  if #s.bag == 0 then
    for i, letter in ipairs(LETTERS) do
      local j = rng(i)
      s.bag[i] = s.bag[j]
      s.bag[j] = letter
    end
  end
  return table.remove(s.bag)
end

--- The run is over, but the full well stays up for a moment so the player can see what happened.
local function topOut(s, events)
  s.ending = ENDING_TICKS
  s.inputs = {}
  events[#events + 1] = { type = "topout" }
end

local function spawn(s, rng, events)
  local letter = s.next
  local size = PIECES[letter].size
  s.next = draw(s, rng)
  s.pieces = s.pieces + 1
  s.piece = { letter = letter, rot = 0, x = math.floor((COLS - size) / 2) + 1, y = size == 4 and 0 or 1 }
  s.aim, s.age, s.wait, s.settling = nil, 0, delay(s), false
  if not fits(s, letter, 0, s.piece.x, s.piece.y) then topOut(s, events) end
end

--- A fresh game. opts.rng is the only source of chance.
function M.new(opts)
  local s = { score = 0, level = 1, over = false, lines = 0, pieces = 0, board = {}, bag = {}, inputs = {} }
  for y = TOP, ROWS do s.board[y] = emptyRow() end
  s.next = draw(s, opts.rng)
  spawn(s, opts.rng, {})
  return s
end

--- A player's input: { kind = "turn", dir = 1 or -1 }, { kind = "aim", col = n } or { kind = "drop" }.
-- Applied in order at the next step.
function M.input(s, action)
  if not s.over and not s.ending and #s.inputs < MAX_INPUTS then s.inputs[#s.inputs + 1] = action end
end

local function isFull(row)
  for x = 1, COLS do
    if not row[x] then return false end
  end
  return true
end

--- Take out every full row, and let the rest fall. Returns how many went.
local function clearRows(s)
  local write, count = ROWS, 0
  for read = ROWS, TOP, -1 do
    if isFull(s.board[read]) then
      count = count + 1
    else
      s.board[write] = s.board[read]
      write = write - 1
    end
  end
  for y = write, TOP, -1 do s.board[y] = emptyRow() end
  return count
end

local function addLines(s, count, events)
  if count == 0 then return end
  s.score = s.score + LINE_SCORE[count] * s.level
  s.lines = s.lines + count
  local level = math.floor(s.lines / PER_LEVEL) + 1
  if level > s.level then
    s.level = level
    events[#events + 1] = { type = "level" }
  end
end

local function aboveTheTop(s)
  for y = TOP, 0 do
    for x = 1, COLS do
      if s.board[y][x] then return true end
    end
  end
  return false
end

local function lock(s, rng, events)
  local p = s.piece
  settle(s, p.letter, p.rot, p.x, p.y, p.letter)
  s.piece = nil
  local count = clearRows(s)
  addLines(s, count, events)
  events[#events + 1] = { type = "lock", lines = count }
  if aboveTheTop(s) then topOut(s, events) else spawn(s, rng, events) end
end

--- The column a piece's middle sits on, as an offset from its box.
local function middle(shape)
  return math.floor((shape.lo + shape.hi) / 2)
end

--- Where a piece's box goes for its middle to sit on a column, kept inside the well.
local function boxFor(letter, rot, col)
  local shape = SHAPES[letter][rot]
  return math.max(1 - shape.lo, math.min(COLS - shape.hi, col - middle(shape)))
end

--- Slide toward the aim, as far as the stack allows. The aim stays set, so a piece slips in when the way opens.
local function slide(s)
  local p = s.piece
  if not s.aim then return end
  local target = boxFor(p.letter, p.rot, s.aim)
  while p.x ~= target do
    local step = target > p.x and 1 or -1
    if not fits(s, p.letter, p.rot, p.x + step, p.y) then return end
    p.x = p.x + step
  end
end

--- A quarter turn, nudged aside or up if it has to be. A turn with nowhere to go does nothing.
local function turn(s, dir, events)
  local p = s.piece
  local rot = (p.rot + dir) % 4
  for _, kick in ipairs(KICKS) do
    if fits(s, p.letter, rot, p.x + kick[1], p.y + kick[2]) then
      p.rot, p.x, p.y = rot, p.x + kick[1], p.y + kick[2]
      events[#events + 1] = { type = "turn" }
      return
    end
  end
end

local function drop(s, rng, events)
  local p = s.piece
  p.y = landingRow(s, p.letter, p.rot, p.x, p.y)
  lock(s, rng, events)
end

local function apply(s, action, rng, events)
  if action.kind == "turn" then
    turn(s, action.dir, events)
  elseif action.kind == "aim" then
    s.aim = action.col
  elseif action.kind == "drop" and s.age >= DROP_GUARD then
    drop(s, rng, events)
  end
  if not s.ending then slide(s) end
end

local function takeInputs(s, rng, events)
  local inputs = s.inputs
  s.inputs = {}
  for _, action in ipairs(inputs) do
    if s.ending then return end
    apply(s, action, rng, events)
  end
end

--- Gravity. A piece that can't fall waits a moment, then locks.
local function fall(s, rng, events)
  s.age = s.age + 1
  s.wait = s.wait - 1
  if s.wait > 0 then return end
  local p = s.piece
  if fits(s, p.letter, p.rot, p.x, p.y + 1) then
    p.y = p.y + 1
    s.wait, s.settling = delay(s), false
  elseif s.settling then
    lock(s, rng, events)
  else
    s.wait, s.settling = LOCK_TICKS, true
  end
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  if s.ending then
    s.ending = s.ending - 1
    s.over = s.ending <= 0
    return {}
  end
  local events = {}
  takeInputs(s, rng, events)
  if not s.ending then
    slide(s)
    fall(s, rng, events)
  end
  return events
end

-- ---------------------------------------------------------------- the bot

local BOT_PACE = 3  -- the bot acts on one step in this many, so the idle screen can be followed

--- How good a well looks: the usual measures of height, holes and a rough surface, with credit for full rows.
local function rate(s)
  local height, holes, rough, full, last = 0, 0, 0, 0, nil
  for x = 1, COLS do
    local top
    for y = TOP, ROWS do
      if s.board[y][x] then
        top = top or y
      elseif top then
        holes = holes + 1
      end
    end
    local h = top and (ROWS - top + 1) or 0
    height = height + h
    if last then rough = rough + math.abs(h - last) end
    last = h
  end
  for y = TOP, ROWS do
    if isFull(s.board[y]) then full = full + 1 end
  end
  return 0.76 * full - 0.51 * height - 0.36 * holes - 0.18 * rough
end

--- Every place the piece could be dropped from where it is, scored, and the best of them.
local function bestPlace(s)
  local p = s.piece
  local best, bestScore
  for rot = 0, 3 do
    local shape = SHAPES[p.letter][rot]
    for x = 1 - shape.lo, COLS - shape.hi do
      if fits(s, p.letter, rot, x, p.y) then
        local y = landingRow(s, p.letter, rot, x, p.y)
        settle(s, p.letter, rot, x, y, p.letter)
        local score = rate(s)
        settle(s, p.letter, rot, x, y, false)
        if not best or score > bestScore then
          best, bestScore = { rot = rot, col = x + middle(shape) }, score
        end
      end
    end
  end
  return best
end

--- How often the bot slips. It gets more careless as the game speeds up, so it clears lines but loses in the end.
local function slips(s, rng)
  return rng() < 0.04 + 0.02 * s.level
end

--- The bot's plan for this piece, kept in the state so the search runs once a piece.
local function planFor(s, rng)
  if s.plan and s.plan.piece == s.pieces then return s.plan end
  local plan = bestPlace(s) or {}
  if not plan.rot or slips(s, rng) then plan = { rot = rng(4) - 1, col = rng(COLS) } end
  plan.piece = s.pieces
  s.plan = plan
  return plan
end

--- A plain player for the idle screen and tests: turn the piece, aim it, drop it.
function M.bot(s, rng)
  if s.over or s.ending or s.age % BOT_PACE ~= 0 then return nil end
  local plan = planFor(s, rng)
  local turns = (plan.rot - s.piece.rot) % 4
  if turns ~= 0 then return { kind = "turn", dir = turns == 3 and -1 or 1 } end
  if s.aim ~= plan.col then return { kind = "aim", col = plan.col } end
  return { kind = "drop" }
end

return M
