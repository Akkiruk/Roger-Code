-- roulette_view.lua
-- The layout and the wheel. The layout is one drawing used twice, on the bet scene and under the result, and one
-- table of geometry: every spot's stake marker and tap target come from the same numbers, so what is drawn is
-- what a touch hits. Each mode lays its own targets over the whole board, so a tap can never mean another bet.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("roulette_rules")

local C = theme.C
local M = {}

-- ------------------------------------------------------------------ layout geometry

local ZERO_X, ZERO_W = 2, 5          -- the zero, spanning all three rows
local CELL_X, PITCH_X = 8, 9         -- first number column, and column spacing; each cell has a gap column after it
local PITCH_Y = 9                    -- row spacing; each cell has a gap row after it
local COLUMN_X, COLUMN_W = 116, 5    -- the 2:1 bets
local BOARD_H = PITCH_Y * 3          -- the numbers, down to the rail under the bottom row
local OUT_H = 7                      -- the rows of outside bets
local CHIP_W = 4

M.HEIGHT = BOARD_H + OUT_H * 2
M.MODES = { "straight", "split", "street", "corner", "line" }

local HINTS = {
  straight = "Tap a number",
  split = "Tap a dot between two numbers",
  street = "Tap a column for its three numbers",
  corner = "Tap a dot where four numbers meet",
  line = "Tap a dot between two columns",
}

local DOZEN_W = 36
local EVEN_ROW = {
  { id = "low", w = 17, label = "1-18" },
  { id = "even", w = 17, label = "EVEN" },
  { id = "red", w = 16, label = "RED", bg = "red" },
  { id = "black", w = 21, label = "BLACK", bg = "ink" },
  { id = "odd", w = 16, label = "ODD" },
  { id = "high", w = 21, label = "19-36" },
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

-- Where a spot's stake sits, relative to the board's top. Every cell has two chip rows: one inside it (y + 7) and
-- the gap row under it (y + 8). Chips sit either mid-cell or over the gap column, so no two can ever overlap.
local function chipSpot(id)
  local spot = rules.spot(id)
  local nums, kind = spot.nums, spot.kind
  local a, b = nums[1], nums[2]
  if kind == "straight" then
    if a == 0 then return ZERO_X, cellY(2) + 7 end
    return cellX(columnOf(a)) + 2, cellY(rowOf(a)) + 7
  elseif kind == "split" then
    if a == 0 then return cellX(1) - 2, cellY(b) + 7 end
    if b == a + 3 then return cellX(columnOf(a)) + 7, cellY(rowOf(a)) + 7 end
    return cellX(columnOf(a)) + 2, cellY(rowOf(b)) + 8
  elseif kind == "street" then
    if a == 0 then return cellX(1) - 2, cellY(nums[3]) + 8 end
    return cellX(columnOf(a)) + 2, cellY(1) + 8
  elseif kind == "corner" then
    if a == 0 then return cellX(1) - 2, cellY(1) + 8 end
    return cellX(columnOf(a)) + 7, cellY(rowOf(a) + 1) + 8
  elseif kind == "line" then
    return cellX(columnOf(a)) + 7, cellY(1) + 8
  elseif kind == "column" then
    return COLUMN_X, cellY(rowOf(a)) + 7
  elseif kind == "dozen" then
    return cellX(1) + (columnOf(a + 2) - 1) / 4 * DOZEN_W + 15, BOARD_H + 5
  end
  local x = cellX(1)
  for _, part in ipairs(EVEN_ROW) do
    if part.id == kind then return x + math.floor((part.w - CHIP_W) / 2), BOARD_H + OUT_H + 5 end
    x = x + part.w
  end
  error("no place for " .. id)
end

M.chipSpot = chipSpot

--- The tap targets of the outside bets, the same in every mode.
local function outsideTargets(top, list)
  for d = 1, 3 do
    list[#list + 1] = { id = "spot", value = "dozen:" .. d, x = cellX(1) + (d - 1) * DOZEN_W, y = top + BOARD_H, w = DOZEN_W, h = OUT_H }
  end
  local x = cellX(1)
  for _, part in ipairs(EVEN_ROW) do
    list[#list + 1] = { id = "spot", value = part.id, x = x, y = top + BOARD_H + OUT_H, w = part.w, h = OUT_H }
    x = x + part.w
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

  if mode == "straight" then
    add("straight:0", ZERO_X, 0, CELL_X - ZERO_X, BOARD_H)
    for n = 1, 36 do add("straight:" .. n, cellX(columnOf(n)), cellY(rowOf(n)), PITCH_X, PITCH_Y) end
  elseif mode == "split" then
    -- Bands round the gaps between columns take the side-by-side splits; bands down the middle of a column the rest
    for row = 1, 3 do
      add(rules.insideId("split", { 0, row }), ZERO_X, cellY(row), cellX(1) - ZERO_X + 2, PITCH_Y)
      for column = 1, 11 do
        local n = 3 * (column - 1) + row
        add(rules.insideId("split", { n, n + 3 }), cellX(column) + 6, cellY(row), 5, PITCH_Y)
      end
    end
    for column = 1, 12 do
      local x, w = cellX(column) + 2, column == 12 and 7 or 4
      local first = 3 * (column - 1) + 1
      add(rules.insideId("split", { first + 1, first + 2 }), x, 0, w, half)
      add(rules.insideId("split", { first, first + 1 }), x, half, w, BOARD_H - half)
    end
  elseif mode == "street" then
    add(rules.insideId("street", { 0, 2, 3 }), ZERO_X, 0, CELL_X - ZERO_X, half)
    add(rules.insideId("street", { 0, 1, 2 }), ZERO_X, half, CELL_X - ZERO_X, BOARD_H - half)
    for column = 1, 12 do
      local first = 3 * (column - 1) + 1
      add(rules.insideId("street", { first, first + 1, first + 2 }), cellX(column), 0, PITCH_X, BOARD_H)
    end
  elseif mode == "line" or mode == "corner" then
    if mode == "corner" then add(rules.insideId("corner", { 0, 1, 2, 3 }), ZERO_X, 0, CELL_X - ZERO_X, BOARD_H) end
    for column = 1, 11 do
      local first = 3 * (column - 1) + 1
      -- The end columns reach the edges of the board
      local x = column == 1 and cellX(1) or cellX(column) + 4
      local right = column == 11 and cellX(12) + PITCH_X or cellX(column) + 13
      if mode == "line" then
        add(rules.insideId("line", { first, first + 1, first + 2, first + 3, first + 4, first + 5 }), x, 0, right - x, BOARD_H)
      else
        add(rules.insideId("corner", { first + 1, first + 2, first + 4, first + 5 }), x, 0, right - x, half)
        add(rules.insideId("corner", { first, first + 1, first + 3, first + 4 }), x, half, right - x, BOARD_H - half)
      end
    end
  end
  outsideTargets(top, list)
  return list
end

-- ------------------------------------------------------------------ small pieces

-- Numbers and the words on the layout, narrower than the casino font so two digits sit in one cell
local TINY = {
  ["0"] = { "###", "#.#", "#.#", "#.#", "###" }, ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
  ["2"] = { "###", "..#", "###", "#..", "###" }, ["3"] = { "###", "..#", ".##", "..#", "###" },
  ["4"] = { "#.#", "#.#", "###", "..#", "..#" }, ["5"] = { "###", "#..", "###", "..#", "###" },
  ["6"] = { "###", "#..", "###", "#.#", "###" }, ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
  ["8"] = { "###", "#.#", "###", "#.#", "###" }, ["9"] = { "###", "#.#", "###", "..#", "###" },
  ["-"] = { "...", "...", "###", "...", "..." }, [":"] = { "...", ".#.", "...", ".#.", "..." },
  A = { ".#.", "#.#", "###", "#.#", "#.#" }, B = { "##.", "#.#", "##.", "#.#", "##." },
  C = { ".##", "#..", "#..", "#..", ".##" }, D = { "##.", "#.#", "#.#", "#.#", "##." },
  E = { "###", "#..", "##.", "#..", "###" }, K = { "#.#", "#.#", "##.", "#.#", "#.#" },
  L = { "#..", "#..", "#..", "#..", "###" }, N = { "#.#", "###", "###", "###", "#.#" },
  O = { ".#.", "#.#", "#.#", "#.#", ".#." }, R = { "##.", "#.#", "##.", "#.#", "#.#" },
  S = { ".##", "#..", ".#.", "..#", "##." }, T = { "###", ".#.", ".#.", ".#.", ".#." },
  V = { "#.#", "#.#", "#.#", "#.#", ".#." }, [" "] = { "...", "...", "...", "...", "..." },
}

local function tinyWidth(text)
  return #text * 4 - 1
end

local function tiny(c, x, y, text, color)
  for i = 1, #text do
    local glyph = TINY[text:sub(i, i)]
    for row = 1, 5 do
      for col = 1, 3 do
        if glyph[row]:sub(col, col) == "#" then c:rect(x + (i - 1) * 4 + col - 1, y + row - 1, 1, 1, color) end
      end
    end
  end
end

local function tinyCenter(c, cx, y, text, color)
  tiny(c, cx - math.floor(tinyWidth(text) / 2), y, text, color)
end

--- A stake in at most four characters: 250, 1.2K, 12K, 3.5M. Rounds down, so a marker never overstates.
function M.short(amount)
  if amount < 1000 then return tostring(amount) end
  if amount < 10000 then
    local tenths = math.floor(amount / 100)
    if tenths % 10 == 0 then return (tenths / 10) .. "K" end
    return ("%d.%dK"):format(math.floor(tenths / 10), tenths % 10)
  end
  if amount < 1000000 then return math.floor(amount / 1000) .. "K" end
  if amount < 10000000 then
    local tenths = math.floor(amount / 100000)
    return ("%d.%dM"):format(math.floor(tenths / 10), tenths % 10)
  end
  return math.floor(amount / 1000000) .. "M"
end

--- A stake marker. look is nil, "won" or "lost".
local function chip(c, x, y, amount, look)
  local bg = look == "won" and C.win or look == "lost" and C.panel2 or C.gold
  local fg = look == "lost" and C.mute or C.ink
  local text = M.short(amount)
  c:rect(x, y, CHIP_W, 1, bg)
  c:text(x + math.floor((CHIP_W - #text) / 2), y, text, fg, bg)
end

local function numberBg(n)
  local color = rules.color(n)
  return color == "red" and C.red or color == "black" and C.ink or C.win
end

--- The last numbers, newest first, as a row of coloured pills.
function M.recentRow(c, x, y, numbers, count)
  for i = 1, math.min(#numbers, count) do
    local n = numbers[i]
    local bg = numberBg(n)
    c:rect(x, y, 3, 1, bg)
    c:text(x + (n < 10 and 1 or 0), y, tostring(n), n == 0 and C.ink or C.text, bg)
    x = x + 4
  end
end

-- ------------------------------------------------------------------ drawing the layout

local function drawNumber(c, top, n, look)
  local x, y, w, h
  if n == 0 then
    x, y, w, h = ZERO_X, top, ZERO_W, BOARD_H - 1
  else
    x, y, w, h = cellX(columnOf(n)), top + cellY(rowOf(n)), PITCH_X - 1, PITCH_Y - 1
  end
  local bg, fg = numberBg(n), n == 0 and C.ink or C.text
  if look == "hot" then bg, fg = C.gold, C.ink end
  if look == "winner" then bg, fg = C.card, C.ink end
  if look == "winnerFlash" then bg, fg = C.gold, C.ink end
  c:rect(x, y, w, h, bg)
  if n == 0 then
    tinyCenter(c, x + 2, y + math.floor(h / 2) - 3, "0", fg)
  else
    tinyCenter(c, x + 4, y + 1, tostring(n), fg)
  end
end

local function drawOutside(c, x, y, w, label, bg, lit)
  c:rect(x, y, w - 1, OUT_H - 1, lit and C.gold or bg)
  tinyCenter(c, x + math.floor((w - 1) / 2), y, label, lit and C.ink or C.text)
end

--- Dots that show where each target of the chosen mode lies.
local function drawMarkers(c, top, mode)
  if mode == "straight" then return end
  for _, spot in ipairs(rules.SPOTS) do
    if spot.kind == mode then
      local x, y = chipSpot(spot.id)
      c:rect(x + 1, top + y, 2, 1, C.card)
    end
  end
end

--- Draw the whole layout from row `top`.
-- opts: spots (the wager), mode (shows its targets), lit (set of numbers to light), litSpot (a spot id to light),
-- number (the winner, which also marks every chip won or lost), flash (the winner's pulse).
function M.drawBoard(c, top, opts)
  local lit = opts.lit or {}
  local number = opts.number
  c:rect(ZERO_X - 1, top - 1, COLUMN_X + COLUMN_W - ZERO_X + 2, M.HEIGHT + 1, C.feltDark)

  for n = 0, 36 do
    local look = lit[n] and "hot" or nil
    if number == n then look = opts.flash and "winnerFlash" or "winner" end
    drawNumber(c, top, n, look)
  end

  for row = 1, 3 do
    local on = number ~= nil and rules.covers("column:" .. row, number)
    local bg = on and C.gold or C.panel
    if opts.litSpot == "column:" .. row then bg = C.gold end
    c:rect(COLUMN_X, top + cellY(row), COLUMN_W, PITCH_Y - 1, bg)
    c:textCenter(COLUMN_X + 2, top + cellY(row) + 3, "2:1", bg == C.gold and C.ink or C.text)
  end

  for d = 1, 3 do
    local id = "dozen:" .. d
    local on = (number ~= nil and rules.covers(id, number)) or opts.litSpot == id
    drawOutside(c, cellX(1) + (d - 1) * DOZEN_W, top + BOARD_H, DOZEN_W, ({ "1ST 12", "2ND 12", "3RD 12" })[d], C.panel, on)
  end
  local x = cellX(1)
  for _, part in ipairs(EVEN_ROW) do
    local on = (number ~= nil and rules.covers(part.id, number)) or opts.litSpot == part.id
    drawOutside(c, x, top + BOARD_H + OUT_H, part.w, part.label, part.bg and C[part.bg] or C.panel, on)
    x = x + part.w
  end

  if opts.mode then drawMarkers(c, top, opts.mode) end

  for id, amount in pairs(opts.spots or {}) do
    local cx, cy = chipSpot(id)
    local look = nil
    if number ~= nil then look = rules.covers(id, number) and "won" or "lost" end
    chip(c, math.floor(cx), top + cy, amount, look)
  end
end

--- The mode buttons. Filled in gold for the mode in force, so it is plain which bet a tap will place.
function M.modeRow(c, buttons, y, active, x, w, h)
  for i, mode in ipairs(M.MODES) do
    local kind = rules.KINDS[i]
    local on = mode == active
    ui.button(c, buttons, {
      id = "mode", value = mode, x = x + (i - 1) * (w + 1), y = y, w = w, h = h,
      label = kind.label:upper(), sub = kind.pay .. " to 1",
      color = on and C.gold or C.panel2, textColor = on and C.ink or C.text,
    })
  end
end

function M.hint(mode)
  return HINTS[mode]
end

-- ------------------------------------------------------------------ the wheel

local TWO_PI = math.pi * 2
local STEP = TWO_PI / rules.POCKETS
local SPIN_SECONDS = 3.8
local BALL_TURNS, WHEEL_TURNS = 7, 3
local TRACK_R, POCKET_R = 0.885, 0.66
-- Bands of the wheel as shares of its radius
local RIM, TRACK, RING, CONE, HUB = 1, 0.955, 0.82, 0.6, 0.22
local CENTER_X, CENTER_Y, RADIUS = 61, 39, 87 -- RADIUS in half-column units: a column is 2 wide, a row 3 tall

local pocketIndex = {}
for i, n in ipairs(rules.WHEEL) do pocketIndex[n] = i end

--- The wheel turned so the winning pocket stops at the top.
function M.finalRotation(number)
  return -math.pi / 2 - (pocketIndex[number] - 0.5) * STEP
end

local function easeOut(t)
  local u = 1 - t
  return 1 - u * u * u
end

local function smooth(a, b, t)
  local u = math.max(0, math.min(1, (t - a) / (b - a)))
  return u * u * (3 - 2 * u)
end

local function wheelAngle(number, t)
  return M.finalRotation(number) - WHEEL_TURNS * TWO_PI * (1 - easeOut(t))
end

--- Where the ball is at t: it runs against the wheel, drops, and is carried in its pocket.
function M.ballAngle(number, t)
  local home = -math.pi / 2
  local free = home + BALL_TURNS * TWO_PI * (1 - easeOut(t))
  local carried = wheelAngle(number, t) + (pocketIndex[number] - 0.5) * STEP
  local w = smooth(0.62, 0.86, t)
  return free * (1 - w) + carried * w
end

local function ballRadius(t)
  if t < 0.55 then return TRACK_R end
  if t > 0.86 then return POCKET_R end
  local u = (t - 0.55) / 0.31
  return TRACK_R + (POCKET_R - TRACK_R) * u + math.abs(math.sin(u * math.pi * 3)) * 0.05 * (1 - u)
end

--- The number whose pocket lies at an angle, for a wheel turned to `rotation`.
function M.pocketAt(rotation, angle)
  local f = ((angle - rotation) / TWO_PI) % 1
  return rules.WHEEL[math.floor(f * rules.POCKETS) + 1]
end

-- Polar coordinates for every cell of the wheel, worked out once
local shape = nil

local function buildShape()
  local rows, ring = {}, {}
  local reachY, reachX = math.ceil(RADIUS / 3), math.ceil(RADIUS / 2)
  for dy = -reachY, reachY do
    local spans, span = {}, nil
    for dx = -reachX, reachX do
      local r = math.sqrt((dx * 2) ^ 2 + (dy * 3) ^ 2) / RADIUS
      local band = nil
      if r <= HUB then band = "hub"
      elseif r <= CONE then band = "cone"
      elseif r <= RING then band = "ring"
      elseif r <= TRACK then band = "track"
      elseif r <= RIM then band = "rim" end
      if band == "ring" then
        local a = math.atan2(dy * 3, dx * 2)
        ring[#ring + 1] = { CENTER_X + dx, CENTER_Y + dy, a }
      end
      if band and band ~= "ring" then
        if span and span.band == band and span.x + span.w == CENTER_X + dx then
          span.w = span.w + 1
        else
          span = { band = band, x = CENTER_X + dx, w = 1 }
          spans[#spans + 1] = span
        end
      else
        span = nil
      end
    end
    rows[#rows + 1] = { y = CENTER_Y + dy, spans = spans }
  end
  return { rows = rows, ring = ring }
end

local BAND_COLOR = { rim = "gold", track = "panel", cone = "feltDark", hub = "gold" }

local function drawWheel(c, rotation)
  shape = shape or buildShape()
  for _, row in ipairs(shape.rows) do
    for _, span in ipairs(row.spans) do
      c:rect(span.x, row.y, span.w, 1, C[BAND_COLOR[span.band]])
    end
  end
  for _, cell in ipairs(shape.ring) do
    local f = ((cell[3] - rotation) / TWO_PI) % 1
    local pocket = math.floor(f * rules.POCKETS)
    -- A thin gold fret between pockets
    local inPocket = f * rules.POCKETS - pocket
    local color = (inPocket < 0.08) and C.gold or numberBg(rules.WHEEL[pocket + 1])
    c:rect(cell[1], cell[2], 1, 1, color)
  end
  -- The turret's arms turn with the wheel
  for arm = 0, 3 do
    local a = rotation + arm * math.pi / 2
    for r = HUB, CONE - 0.02, 0.02 do
      c:rect(CENTER_X + math.floor(math.cos(a) * r * RADIUS / 2 + 0.5), CENTER_Y + math.floor(math.sin(a) * r * RADIUS / 3 + 0.5), 2, 1, C.line)
    end
  end
  for i, n in ipairs(rules.WHEEL) do
    local a = rotation + (i - 0.5) * STEP
    local x = CENTER_X + math.cos(a) * RADIUS * 0.755 / 2
    local y = CENTER_Y + math.sin(a) * RADIUS * 0.755 / 3
    c:textCenter(math.floor(x + 0.5), math.floor(y + 0.5), tostring(n), n == 0 and C.ink or C.text)
  end
  c:rect(CENTER_X - 1, CENTER_Y - math.ceil(RADIUS / 3) - 1, 4, 2, C.card) -- the marker at the top
end

local function drawBall(c, angle, radius)
  local x = math.floor(CENTER_X + math.cos(angle) * radius * RADIUS / 2 + 0.5)
  local y = math.floor(CENTER_Y + math.sin(angle) * radius * RADIUS / 3 + 0.5)
  c:rect(x - 1, y, 3, 2, C.card)
  c:rect(x, y - 1, 1, 1, C.card)
end

local function sidePanels(c, state, recent)
  c:text(4, 12, "BET", C.mute)
  c:text(4, 13, ui.group(state.stake), C.gold)
  c:text(4, 15, "SPOTS", C.mute)
  local spots = 0
  for _ in pairs(state.spots) do spots = spots + 1 end
  c:text(4, 16, tostring(spots), C.text)
  c:text(c.w - 9, 12, "LAST", C.mute)
  for i = 1, math.min(#recent, rules.RECENT_KEPT) do
    M.recentRow(c, c.w - 9, 12 + i * 2, { recent[i] }, 1)
  end
end

local function drawWheelScene(c, state, anim)
  c:clear(C.felt)
  sidePanels(c, state, state.recent)
  local number = state.number
  if anim and anim.ev.type == "spin" then
    drawWheel(c, wheelAngle(number, anim.t))
    drawBall(c, M.ballAngle(number, anim.t), ballRadius(anim.t))
    return
  end
  drawWheel(c, M.finalRotation(number))
  drawBall(c, -math.pi / 2, POCKET_R)
  -- The hub shows the number once the ball has stopped
  local t = anim and anim.t or 1
  local bg = numberBg(number)
  if t > 0.15 then
    c:rect(CENTER_X - 11, CENTER_Y - 7, 22, 15, bg)
    c:frame(CENTER_X - 11, CENTER_Y - 7, 22, 15, C.gold)
    c:bigCenter(CENTER_X, CENTER_Y - 5, tostring(number), number == 0 and C.ink or C.text, 2)
  end
end

-- ------------------------------------------------------------------ the engine's view

local RESULT_TOP = 10

function M.new(ctx)
  return { ctx = ctx, phase = "board" }
end

function M.sync(model, _)
  model.phase = "board"
end

function M.event(model, ev)
  if ev.type == "spin" then
    model.phase = "wheel"
    -- The money has moved already. The top bar shows the old balance until the ball has landed
    model.ctx.heldBalance = (model.ctx.balance or 0) - ev.net
    return SPIN_SECONDS, "spin"
  elseif ev.type == "landed" then
    model.phase = "wheel"
    return 1.3, "stop"
  end
  model.phase = "board"
  model.ctx.heldBalance = nil
  return 1.0, "chip"
end

function M.commit(model, ev)
  if ev.type == "payout" then
    model.phase = "board"
    model.ctx.heldBalance = nil
  end
end

--- The idle screen: the wheel's numbers running past in their real order.
function M.attract(c, t)
  local cellW = 13
  local shift = math.floor(t * 9) % (cellW * rules.POCKETS)
  for i = -1, math.ceil(c.w / cellW) do
    local at = (math.floor(shift / cellW) + i) % rules.POCKETS + 1
    local x = i * cellW - shift % cellW + 1
    local n = rules.WHEEL[at]
    c:rect(x, 56, cellW - 1, 12, numberBg(n))
    c:bigCenter(x + 6, 59, tostring(n), C.text, 1)
  end
end

function M.draw(c, model, state, anim)
  if model.phase == "wheel" then
    drawWheelScene(c, state, anim)
    return
  end
  c:clear(C.felt)
  local flash = anim ~= nil and math.floor(anim.t * 6) % 2 == 0
  M.drawBoard(c, RESULT_TOP, { spots = state.spots, number = state.number, flash = flash })
end

return M
