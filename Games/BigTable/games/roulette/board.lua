-- games/roulette/board.lua
-- The layout on a 78x52 seat: Games/Roulette's board cut down to a cell of 4 by 4. One table of geometry gives every spot's marker and
-- tap target, so what is drawn is what a touch hits. A cell only has room for the amount on a straight bet. Any other bet is a mark
-- on the line it sits on, and the line under the board says what the last tap was.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wheel = require("games.roulette.wheel")

local C = theme.C
local M = {}

local ZERO_X, ZERO_W = 2, 6          -- the zero, spanning all three rows
local CELL_X, PITCH_X, CELL_W = 9, 5, 4   -- the first number column, the column spacing, and a cell inside that
local PITCH_Y, CELL_H = 5, 4         -- the same down the board
local COLUMN_X, COLUMN_W = 69, 8     -- the 2:1 bets
local BOARD_H = PITCH_Y * 3
local OUT_H = 3                      -- outside row spacing. Two rows drawn, one gap
local DOZEN_W, EVEN_W = PITCH_X * 4, PITCH_X * 2
local NUMBER_ROW, STAKE_ROW = 1, 3   -- rows inside a cell
local MARK_W, CHIP_W = 2, 4

M.HEIGHT = BOARD_H + OUT_H * 2

local TAB_LABELS = { straight = "STRAIGHT 35:1", split = "SPLIT 17:1", street = "STREET 11:1", corner = "CORNER 8:1", line = "LINE 5:1" }
local TAB_X, TAB_W, TAB_H = 2, 14, 3

local HINTS = {
  straight = "Tap a number",
  split = "Tap the line between two numbers",
  street = "Tap a column for its three numbers",
  corner = "Tap where four numbers meet",
  line = "Tap the line between two columns",
}

local EVEN_ROW = {
  { id = "low", label = "1-18" },
  { id = "even", label = "EVEN" },
  { id = "red", label = "RED", bg = "red" },
  { id = "black", label = "BLACK", bg = "ink" },
  { id = "odd", label = "ODD" },
  { id = "high", label = "19-36" },
}

local function cellX(column)
  return CELL_X + (column - 1) * PITCH_X
end

local function cellY(row)
  return (3 - row) * PITCH_Y
end

local function columnOf(n)
  return math.ceil(n / 3)
end

local function rowOf(n)
  return (n - 1) % 3 + 1
end

--- Where a spot's mark sits, relative to the board's top. Inside bets only.
local function markSpot(id)
  local spot = wheel.spot(id)
  local nums, kind = spot.nums, spot.kind
  local a, b = nums[1], nums[2]
  local edgeX, gapY = CELL_X - 2, CELL_H
  if kind == "split" then
    if a == 0 then return edgeX, cellY(b) + NUMBER_ROW end
    if b == a + 3 then return cellX(columnOf(a)) + 3, cellY(rowOf(a)) + NUMBER_ROW end
    return cellX(columnOf(a)) + 1, cellY(rowOf(b)) + gapY
  elseif kind == "street" then
    if a == 0 then return edgeX, cellY(nums[3]) + gapY end
    return cellX(columnOf(a)) + 1, cellY(1) + gapY
  elseif kind == "corner" then
    if a == 0 then return edgeX, cellY(1) + gapY end
    return cellX(columnOf(a)) + 3, cellY(rowOf(a) + 1) + gapY
  end
  return cellX(columnOf(a)) + 3, cellY(1) + gapY -- a line
end

M.markSpot = markSpot

--- The tap targets of the outside bets, the same in every mode.
local function outsideTargets(top, list)
  local y = top + BOARD_H
  for d = 1, 3 do
    list[#list + 1] = { id = "spot", value = "dozen:" .. d, x = cellX(1) + (d - 1) * DOZEN_W, y = y, w = DOZEN_W, h = OUT_H }
  end
  local x = cellX(1)
  for _, part in ipairs(EVEN_ROW) do
    list[#list + 1] = { id = "spot", value = part.id, x = x, y = y + OUT_H, w = EVEN_W, h = OUT_H }
    x = x + EVEN_W
  end
  for row = 1, 3 do
    list[#list + 1] = { id = "spot", value = "column:" .. row, x = COLUMN_X, y = top + cellY(row), w = COLUMN_W, h = PITCH_Y }
  end
end

--- Every tappable part of the board in a mode. Between them they tile the numbers, so no tap falls in a dead gap.
function M.targets(top, mode)
  local list = {}
  local function add(id, x, y, w, h)
    list[#list + 1] = { id = "spot", value = id, x = x, y = top + y, w = w, h = h }
  end
  local half = math.floor(BOARD_H / 2)
  local zeroW = CELL_X - ZERO_X

  if mode == "split" then
    -- Bands round the gaps between columns take the side-by-side splits, and the rest of each column takes the others
    for row = 1, 3 do
      add(wheel.insideId("split", { 0, row }), ZERO_X, cellY(row), zeroW, PITCH_Y)
      for column = 1, 11 do
        local n = 3 * (column - 1) + row
        add(wheel.insideId("split", { n, n + 3 }), cellX(column) + 3, cellY(row), 2, PITCH_Y)
      end
    end
    for column = 1, 12 do
      local w = column == 12 and PITCH_X or 3
      local first = 3 * (column - 1) + 1
      add(wheel.insideId("split", { first + 1, first + 2 }), cellX(column), 0, w, half)
      add(wheel.insideId("split", { first, first + 1 }), cellX(column), half, w, BOARD_H - half)
    end
  elseif mode == "street" then
    add(wheel.insideId("street", { 0, 2, 3 }), ZERO_X, 0, zeroW, half)
    add(wheel.insideId("street", { 0, 1, 2 }), ZERO_X, half, zeroW, BOARD_H - half)
    for column = 1, 12 do
      local first = 3 * (column - 1) + 1
      add(wheel.insideId("street", { first, first + 1, first + 2 }), cellX(column), 0, PITCH_X, BOARD_H)
    end
  elseif mode == "line" or mode == "corner" then
    if mode == "corner" then add(wheel.insideId("corner", { 0, 1, 2, 3 }), ZERO_X, 0, zeroW, BOARD_H) end
    for column = 1, 11 do
      local first = 3 * (column - 1) + 1
      -- The end columns reach the edges of the board
      local x = column == 1 and cellX(1) or cellX(column) + 2
      local right = column == 11 and cellX(12) + PITCH_X or cellX(column) + 7
      if mode == "line" then
        add(wheel.insideId("line", { first, first + 1, first + 2, first + 3, first + 4, first + 5 }), x, 0, right - x, BOARD_H)
      else
        add(wheel.insideId("corner", { first + 1, first + 2, first + 4, first + 5 }), x, 0, right - x, half)
        add(wheel.insideId("corner", { first, first + 1, first + 3, first + 4 }), x, half, right - x, BOARD_H - half)
      end
    end
  else
    add("straight:0", ZERO_X, 0, zeroW, BOARD_H)
    for n = 1, 36 do add("straight:" .. n, cellX(columnOf(n)), cellY(rowOf(n)), PITCH_X, PITCH_Y) end
  end
  outsideTargets(top, list)
  return list
end

--- The tabs along the top that choose what a tap on the numbers means.
function M.tabs(y)
  local list = {}
  for i, mode in ipairs(wheel.MODES) do
    list[i] = { id = "mode", value = mode, x = TAB_X + (i - 1) * (TAB_W + 1), y = y, w = TAB_W, h = TAB_H }
  end
  return list
end

function M.drawTabs(c, y, active)
  for _, tab in ipairs(M.tabs(y)) do
    local on = tab.value == active
    local bg = on and C.gold or C.panel2
    c:rect(tab.x, tab.y, tab.w, tab.h, bg)
    c:textCenter(tab.x + math.floor(tab.w / 2), tab.y + 1, TAB_LABELS[tab.value], on and C.ink or C.text, bg)
  end
end

function M.hint(mode)
  return HINTS[mode]
end

--- A stake in at most four characters: 250, 1.2K, 12K. Rounds down, so a marker never overstates.
function M.short(amount)
  if amount < 1000 then return tostring(amount) end
  if amount < 10000 then
    local tenths = math.floor(amount / 100)
    if tenths % 10 == 0 then return (tenths / 10) .. "K" end
    return ("%d.%dK"):format(math.floor(tenths / 10), tenths % 10)
  end
  return math.floor(amount / 1000) .. "K"
end

function M.numberBg(n)
  local color = wheel.color(n)
  return color == "red" and C.red or color == "black" and C.ink or C.win
end

--- The last numbers, newest first, as a row of coloured pills.
function M.recentRow(c, x, y, numbers, count)
  for i = 1, math.min(#numbers, count) do
    local n = numbers[i]
    local bg = M.numberBg(n)
    c:rect(x, y, 3, 1, bg)
    c:text(x + (n < 10 and 1 or 0), y, tostring(n), n == 0 and C.ink or C.text, bg)
    x = x + 4
  end
end

local function lookOf(id, number)
  if number == nil then return nil end
  return wheel.covers(id, number) and "won" or "lost"
end

local function chipBg(look)
  return look == "won" and C.win or look == "lost" and C.panel2 or C.gold
end

local function chip(c, x, y, amount, look)
  local bg = chipBg(look)
  local text = M.short(amount)
  c:rect(x, y, CHIP_W, 1, bg)
  c:text(x + math.floor((CHIP_W - #text) / 2), y, text, look == "lost" and C.mute or C.ink, bg)
end

local function drawNumber(c, top, n, look)
  local x, y, w, h
  if n == 0 then
    x, y, w, h = ZERO_X, top, ZERO_W, BOARD_H - 1
  else
    x, y, w, h = cellX(columnOf(n)), top + cellY(rowOf(n)), CELL_W, CELL_H
  end
  local bg, fg = M.numberBg(n), n == 0 and C.ink or C.text
  if look == "hot" then bg, fg = C.gold, C.ink end
  if look == "winner" then bg, fg = C.card, C.ink end
  c:rect(x, y, w, h, bg)
  if n == 0 then
    c:textCenter(x + 2, top + cellY(2) + NUMBER_ROW, "0", fg, bg)
  else
    c:textCenter(x + 1, y + NUMBER_ROW, tostring(n), fg, bg)
  end
end

local function drawOutside(c, x, y, w, id, label, bg, opts)
  local number = opts.number
  local on = (number ~= nil and wheel.covers(id, number)) or opts.litSpot == id
  local fill = on and C.gold or bg
  c:rect(x, y, w - 1, OUT_H - 1, fill)
  c:textCenter(x + math.floor((w - 1) / 2), y, label, on and C.ink or C.text, fill)
  local amount = opts.spots and opts.spots[id]
  if amount then chip(c, x + math.floor((w - 1 - CHIP_W) / 2), y + 1, amount, lookOf(id, number)) end
end

--- Draw the whole layout from row top. opts: spots (the wager), mode (shows its targets), lit (a set of numbers), litSpot (a spot id),
-- number (the winner, which also marks every bet won or lost).
function M.draw(c, top, opts)
  local lit, number, spots = opts.lit or {}, opts.number, opts.spots or {}
  c:rect(ZERO_X - 1, top - 1, COLUMN_X + COLUMN_W - ZERO_X + 2, M.HEIGHT + 1, C.feltDark)

  for n = 0, 36 do
    local look = lit[n] and "hot" or nil
    if number == n then look = "winner" end
    drawNumber(c, top, n, look)
  end

  for row = 1, 3 do
    local id = "column:" .. row
    local on = (number ~= nil and wheel.covers(id, number)) or opts.litSpot == id
    local bg = on and C.gold or C.panel
    local y = top + cellY(row)
    c:rect(COLUMN_X, y, COLUMN_W, CELL_H, bg)
    c:textCenter(COLUMN_X + 4, y + NUMBER_ROW, "2:1", on and C.ink or C.text, bg)
    if spots[id] then chip(c, COLUMN_X + 2, y + STAKE_ROW, spots[id], lookOf(id, number)) end
  end

  for d = 1, 3 do
    drawOutside(c, cellX(1) + (d - 1) * DOZEN_W, top + BOARD_H, DOZEN_W, "dozen:" .. d, ({ "1ST 12", "2ND 12", "3RD 12" })[d], C.panel, opts)
  end
  local x = cellX(1)
  for _, part in ipairs(EVEN_ROW) do
    drawOutside(c, x, top + BOARD_H + OUT_H, EVEN_W, part.id, part.label, part.bg and C[part.bg] or C.panel, opts)
    x = x + EVEN_W
  end

  -- Where each target of this mode lies, then the bets over them
  if opts.mode and opts.mode ~= "straight" then
    for _, spot in ipairs(wheel.SPOTS) do
      if spot.kind == opts.mode then
        local mx, my = markSpot(spot.id)
        c:rect(mx, top + my, MARK_W, 1, C.mute)
      end
    end
  end
  for id, amount in pairs(spots) do
    local spot = wheel.spot(id)
    if spot then
      local look = lookOf(id, number)
      if spot.kind == "straight" then
        local n = spot.nums[1]
        if n == 0 then
          chip(c, ZERO_X + 1, top + cellY(2) + STAKE_ROW, amount, look)
        else
          chip(c, cellX(columnOf(n)), top + cellY(rowOf(n)) + STAKE_ROW, amount, look)
        end
      elseif spot.kind == "split" or spot.kind == "street" or spot.kind == "corner" or spot.kind == "line" then
        local mx, my = markSpot(id)
        c:rect(mx, top + my, MARK_W, 1, chipBg(look))
      end
    end
  end
end

return M
