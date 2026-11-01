-- games/roulette/tableView.lua
-- The dealer's wall: the wheel on the left, and on the right the last numbers, every seat's bet and where the chips lie. The wheel is
-- Games/Roulette's, a little smaller, so its rim stays clear of the result banner along the bottom of the wall's area.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local board = require("games.roulette.board")
local wheel = require("games.roulette.wheel")

local C = theme.C
local M = {}

local TWO_PI = math.pi * 2
local STEP = TWO_PI / wheel.POCKETS
local BALL_TURNS, WHEEL_TURNS = 7, 3
local TRACK_R, POCKET_R = 0.885, 0.66
-- Bands of the wheel as shares of its radius
local RIM, TRACK, RING, CONE, HUB = 1, 0.955, 0.82, 0.6, 0.22
local CENTER_X, CENTER_Y, RADIUS = 37, 34, 69 -- RADIUS in half-column units: a column is 2 wide, a row 3 tall
local IDLE_ROTATION = -math.pi / 2

local PANEL_X = 75                   -- everything right of the wheel
local MINI_PITCH_X, MINI_PITCH_Y = 3, 3
local MINI_ZERO_W = 3
local WORDS_Y = 60                   -- the big line under the wheel, where the result banner goes once there is a result

local pocketIndex = {}
for i, n in ipairs(wheel.WHEEL) do pocketIndex[n] = i end

--- The wheel turned so the winning pocket stops at the top.
local function finalRotation(number)
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
  return finalRotation(number) - WHEEL_TURNS * TWO_PI * (1 - easeOut(t))
end

--- Where the ball is at t: it runs against the wheel, drops, and is carried in its pocket.
local function ballAngle(number, t)
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
        ring[#ring + 1] = { CENTER_X + dx, CENTER_Y + dy, math.atan2(dy * 3, dx * 2) }
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
    local pocket = math.floor(f * wheel.POCKETS)
    -- A thin gold fret between pockets
    local inPocket = f * wheel.POCKETS - pocket
    local color = (inPocket < 0.08) and C.gold or board.numberBg(wheel.WHEEL[pocket + 1])
    c:rect(cell[1], cell[2], 1, 1, color)
  end
  -- The turret's arms turn with the wheel
  for arm = 0, 3 do
    local a = rotation + arm * math.pi / 2
    for r = HUB, CONE - 0.02, 0.02 do
      c:rect(CENTER_X + math.floor(math.cos(a) * r * RADIUS / 2 + 0.5), CENTER_Y + math.floor(math.sin(a) * r * RADIUS / 3 + 0.5), 2, 1, C.line)
    end
  end
  for i, n in ipairs(wheel.WHEEL) do
    local a = rotation + (i - 0.5) * STEP
    local x = CENTER_X + math.cos(a) * RADIUS * 0.72 / 2
    local y = CENTER_Y + math.sin(a) * RADIUS * 0.72 / 3
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

--- A number in the hub of the wheel.
local function drawHub(c, number)
  local bg = board.numberBg(number)
  c:rect(CENTER_X - 11, CENTER_Y - 7, 22, 15, bg)
  c:frame(CENTER_X - 11, CENTER_Y - 7, 22, 15, C.gold)
  c:bigCenter(CENTER_X, CENTER_Y - 5, tostring(number), number == 0 and C.ink or C.text, 2)
end

--- The last numbers, in two rows of pills.
local function drawRecent(c, y, recent)
  c:text(PANEL_X, y, "LAST NUMBERS", C.mute)
  if #recent == 0 then
    c:text(PANEL_X, y + 2, "This wheel has not spun yet", C.mute)
    return
  end
  board.recentRow(c, PANEL_X, y + 2, recent, 10)
  local rest = {}
  for i = 11, #recent do rest[#rest + 1] = recent[i] end
  board.recentRow(c, PANEL_X, y + 4, rest, 10)
end

--- One line a seat. The money only shows once the ball has stopped.
local function drawSeats(c, y, view, info, stopped)
  c:text(PANEL_X, y, "BETS", C.mute)
  local total = 0
  for index, seat in ipairs(view.seats or {}) do
    local row = y + 1 + index
    total = total + seat.placed
    local amount = ui.group(seat.placed)
    c:text(PANEL_X, row, seatui.short(seat.name, 16), C.text)
    c:text(PANEL_X + 18, row, amount, seat.placed > 0 and C.gold or C.mute)
    local word, color = "", C.mute
    if stopped and seat.placed > 0 and seat.net then
      word, color = (seat.net > 0 and "+" or "") .. ui.group(seat.net), seat.net > 0 and C.win or (seat.net < 0 and C.red or C.text)
    elseif not view.over and seat.done then
      word, color = "DONE", C.win
    elseif not view.over and info and info.waiting and info.waiting[seat.seat] then
      word = "betting"
    end
    c:text(PANEL_X + 32, row, word, color)
  end
  local row = y + 11
  c:text(PANEL_X, row, "ON THE TABLE", C.mute)
  c:text(PANEL_X + 18, row, ui.group(total), C.gold)
end

--- Every number with a bet that covers it is lit, and the winner shows white. Bets too small to read on the wall are still seen.
local function drawMini(c, y, view, number)
  local covered = {}
  for id in pairs(view.board or {}) do
    local spot = wheel.spot(id)
    if spot then
      for _, n in ipairs(spot.nums) do covered[n] = true end
    end
  end
  local function fill(n, x, top, w, h)
    local bg = board.numberBg(n)
    if n == number then bg = C.card elseif covered[n] then bg = C.gold end
    c:rect(x, top, w, h, bg)
  end
  fill(0, PANEL_X, y, MINI_ZERO_W - 1, MINI_PITCH_Y * 3 - 1)
  for n = 1, 36 do
    local column, row = math.ceil(n / 3), (n - 1) % 3
    fill(n, PANEL_X + MINI_ZERO_W + (column - 1) * MINI_PITCH_X, y + (2 - row) * MINI_PITCH_Y, MINI_PITCH_X - 1, MINI_PITCH_Y - 1)
  end
end

--- The big line under the wheel, on the felt the result banner takes over.
local function drawWords(c, text, color)
  local _, _, w = seatui.tableArea(c)
  local cx = math.floor(w / 2) + 1
  local scale = c:bigWidth(text, 2) <= w - 4 and 2 or 1
  c:bigCenter(cx, WORDS_Y, text, color, scale)
end

function M.draw(c, view, anim, info)
  local spinning = view.over and anim ~= nil and anim.ev.type == "spin"
  local stopped = view.over and not spinning

  if spinning then
    drawWheel(c, wheelAngle(view.number, anim.t))
    drawBall(c, ballAngle(view.number, anim.t), ballRadius(anim.t))
  elseif stopped then
    drawWheel(c, finalRotation(view.number))
    drawBall(c, -math.pi / 2, POCKET_R)
    drawHub(c, view.number)
  else
    drawWheel(c, IDLE_ROTATION)
    if view.recent and view.recent[1] then drawHub(c, view.recent[1]) end
  end

  local recent = {}
  if stopped then recent[1] = view.number end
  for _, n in ipairs(view.recent or {}) do
    if #recent < wheel.RECENT_KEPT then recent[#recent + 1] = n end
  end
  drawRecent(c, ui.TOP + 2, recent)
  drawSeats(c, ui.TOP + 9, view, info, stopped)
  c:text(PANEL_X, ui.TOP + 23, "NUMBERS WITH A BET ON THEM", C.mute)
  drawMini(c, ui.TOP + 25, view, stopped and view.number or nil)

  if stopped then
    drawWords(c, wheel.numberName(view.number), C.gold)
  elseif spinning then
    drawWords(c, "NO MORE BETS", C.text)
  elseif info and info.waiting and next(info.waiting) then
    drawWords(c, "PLACE YOUR BETS", C.gold)
  else
    drawWords(c, "NO MORE BETS", C.text)
  end
end

return M
