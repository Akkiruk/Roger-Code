-- games/lander/plugin.lua
-- Lunar Lander as an Arcade classic. Three buttons, all taps: everything is slow enough that a tap is a decision.
-- The rules work in world units; this file turns them into monitor cells, each 2 units wide and 3 tall. The board sits
-- on the left, and the flight readouts have a strip down the right, in large figures a player can read mid-descent.

local base = require("lib.arcade.base")
local rules = require("games.lander.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local CELL_W, CELL_H = rules.CELL_W, rules.CELL_H
local BOARD_W, BOARD_H = rules.WIDTH / CELL_W, rules.HEIGHT / CELL_H
local TAU = math.pi * 2
local abs, cos, floor, max, min, rad, sin = math.abs, math.cos, math.floor, math.max, math.min, math.rad, math.sin

-- The craft, as { across, up } from its centre with the nose up. It turns as one shape.
local BODY = { { -2, 6 }, { 2, 6 }, { 4.5, 3 }, { 4.5, -2.5 }, { -4.5, -2.5 }, { -4.5, 3 } }
local LEGS = { { -4.5, -3.5 }, { 4.5, -3.5 }, { -6, -6 }, { 6, -6 } }
local NOSE = { 0, 9 }
local FLAME = { { -2.5, -3 }, { 0, -11 }, { 2.5, -3 } }
local FLAME_SHORT = 0.7     -- every other step the flame draws this much shorter, so it flickers
local STAR_COUNT = 40
local BLAST_SPOKES = 12
local LOW_FUEL = 150
local SPEED_SCALE = 100     -- speeds show as whole numbers: 32 means 0.32 units a step
local WORDS = { soft = "VERY SOFT", good = "GOOD", rough = "ROUGH" }
local ARROWS = {
  left = { "..#...", ".#....", "######", ".#....", "..#..." },
  right = { "...#..", "....#.", "######", "....#.", "...#.." },
  up = { "..#..", ".###.", "#.#.#", "..#..", "..#..", "..#.." },
  down = { "..#..", "..#..", "..#..", "#.#.#", ".###.", "..#.." },
}

local view = {}

--- The board hard against the left, not centred, to leave a strip for the readouts.
function view.layout(W, H)
  local L = base.actionLayout(W, H, BOARD_W, BOARD_H)
  L.x0 = 1
  L.stripX = L.x0 + L.bw + 1
  L.stripW = W - L.stripX - 1
  return L
end

--- One row of cells, cut off at the edge of the board so nothing lands on the header or the buttons.
local function span(L, row, from, to, color)
  if row < 0 or row >= L.bh then return end
  from, to = max(0, from), min(L.bw - 1, to)
  ui.fill(L.x0 + from, L.y0 + row, to - from + 1, 1, color)
end

--- A filled shape from a list of world points { x, y }.
local function polygon(L, points, color)
  local top, bottom = math.huge, -math.huge
  for _, p in ipairs(points) do
    top, bottom = min(top, p[2]), max(bottom, p[2])
  end
  for row = floor(top / CELL_H), floor(bottom / CELL_H) do
    local y = (row + 0.5) * CELL_H
    local from, to = math.huge, -math.huge
    for i, a in ipairs(points) do
      local b = points[i % #points + 1]
      if (a[2] <= y) ~= (b[2] <= y) then
        local x = a[1] + (y - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
        from, to = min(from, x), max(to, x)
      end
    end
    if to >= from then span(L, row, floor(from / CELL_W), floor(to / CELL_W), color) end
  end
end

--- A bright spot two cells wide, which is about square on the wall.
local function drawSpot(L, x, y, color)
  local col, row = floor(x / CELL_W), floor(y / CELL_H)
  span(L, row, col, col + 1, color)
end

--- A point on the craft, in world units. The centre is snapped to its cell, so the outline stays even as it drifts.
local function locate(c, angle, part)
  local x, y = (floor(c.x / CELL_W) + 0.5) * CELL_W, (floor(c.y / CELL_H) + 0.5) * CELL_H
  return x + part[1] * cos(angle) + part[2] * sin(angle), y + part[1] * sin(angle) - part[2] * cos(angle)
end

local function shape(c, angle, parts, scale)
  local points = {}
  for i, part in ipairs(parts) do
    points[i] = { locate(c, angle, scale and { part[1], part[2] * scale } or part) }
  end
  return points
end

local function drawFlame(L, s, angle)
  local scale = s.clock % 2 == 0 and 1 or FLAME_SHORT
  polygon(L, shape(s.craft, angle, FLAME, scale), C.warn)
end

local function drawCraft(L, s)
  local c = s.craft
  local angle = rad(s.tilt)
  if s.burn > 0 then drawFlame(L, s, angle) end
  polygon(L, shape(c, angle, BODY), C.text)
  for _, leg in ipairs(LEGS) do
    local x, y = locate(c, angle, leg)
    drawSpot(L, x, y, C.line)
  end
  -- the nose marks the way a burn will push
  local x, y = locate(c, angle, NOSE)
  drawSpot(L, x, y, C.warn)
end

local function drawBlast(L, s)
  local b = s.blast
  local reach = (b.age + 1) * 2.2
  for ring = 1, 2 do
    local color = (ring == 1) == (b.age < 6) and C.hi or C.warn
    for i = 1, BLAST_SPOKES do
      local heading = i / BLAST_SPOKES * TAU + ring
      local out = reach * (ring == 1 and 1 or 0.6)
      drawSpot(L, b.x + cos(heading) * out, b.y + sin(heading) * out, color)
    end
  end
end

--- The next number of a small fixed sequence.
local function scatter(n)
  return (n * 1103 + 12345) % 32749
end

--- A fixed scatter of stars for each site: no chance needed, and the sky never twinkles.
local function drawStars(L, s)
  local n = s.site * 31 + 7
  for i = 1, STAR_COUNT do
    n = scatter(n)
    local x = n % L.bw
    n = scatter(n)
    ui.fill(L.x0 + x, L.y0 + n % L.bh, 1, 1, i % 3 == 0 and C.line or C.panel)
  end
end

--- The moon, one column at a time. The top of each column is the lit edge.
local function drawGround(L, s)
  for c = 1, L.bw do
    local row = floor(s.ground[c] / CELL_H)
    ui.fill(L.x0 + c - 1, L.y0 + row, 1, L.bh - row, C.panel)
    ui.fill(L.x0 + c - 1, L.y0 + row, 1, 1, C.line)
  end
end

--- A pad is a bright line, with what it's worth cut into the rock under it.
local function drawPad(L, pad)
  local row = floor(pad.y / CELL_H)
  local from = floor(pad.left / CELL_W)
  ui.fill(L.x0 + from, L.y0 + row, floor(pad.width / CELL_W), 1, C.hi)
  ui.small(pad.mult .. "X", L.x0 + from + floor(pad.width / CELL_W / 2), L.y0 + row + 1, C.hi, C.panel, "center")
end

--- The result over the sky, with room to see the landing below it.
local function drawResult(L, s)
  local r = s.result
  local cx = L.x0 + floor(L.bw / 2)
  local y = L.y0 + 6
  ui.fill(L.x0 + 12, y, L.bw - 24, 13, C.panel)
  ui.frame(L.x0 + 12, y, L.bw - 24, 13, r.landed and C.ok or C.warn, 1)
  if r.landed then
    ui.text("SAFE LANDING", cx, y + 2, C.ok, "center", L.bw - 28)
    ui.small(("%s  %dX  +%d  +%d FUEL"):format(WORDS[r.grade], r.mult, r.points, r.fuel), cx, y + 10, C.text, C.panel, "center")
  else
    ui.text("CRASHED", cx, y + 2, C.warn, "center", L.bw - 28)
    ui.small(("%s  -%d FUEL"):format(r.why, r.fuel), cx, y + 10, C.text, C.panel, "center")
  end
end

local function drawHold(L, s)
  ui.small("SITE " .. s.site, L.x0 + floor(L.bw / 2), L.y0 + 12, C.hi, C.bg, "center")
end

--- One readout: a small label over a large figure.
local function readout(L, y, label, value, color)
  ui.small(label, L.stripX, y, C.line, C.bg, "left")
  ui.text(value, L.stripX, y + 2, color, "left")
end

--- Which way a speed points, by the name of its arrow: { negative, positive }. Nil when it's as good as still.
function view.arrow(speed, names)
  if floor(abs(speed) * SPEED_SCALE + 0.5) == 0 then return nil end
  return speed < 0 and names[1] or names[2]
end

--- An arrow drawn cell by cell, as the pixel font's don't read at a glance. It ends just short of x.
local function drawArrow(name, x, y, color)
  for row, cells in ipairs(ARROWS[name]) do
    for col = 1, #cells do
      if cells:sub(col, col) == "#" then ui.fill(x - #cells + col - 1, y + row - 1, 1, 1, color) end
    end
  end
end

local function fuelColor(fuel)
  if fuel < LOW_FUEL / 3 then return C.red end
  if fuel < LOW_FUEL then return C.warn end
  return C.text
end

local function drawFuel(L, s, y)
  readout(L, y, "FUEL", s.fuel, fuelColor(s.fuel))
  ui.fill(L.stripX, y + 9, L.stripW, 2, C.panel)
  local share = min(1, s.fuel / rules.START_FUEL)
  ui.fill(L.stripX, y + 9, floor(L.stripW * share + 0.5), 2, fuelColor(s.fuel))
end

local function drawTilt(L, s, y)
  local word = "UPRIGHT"
  if s.tilt ~= 0 then word = abs(s.tilt) .. (s.tilt > 0 and " RIGHT" or " LEFT") end
  ui.small("TILT", L.stripX, y, C.line, C.bg, "left")
  ui.small(word, L.stripX, y + 1, abs(s.tilt) <= rules.SAFE_TILT and C.ok or C.text, C.bg, "left")
end

--- A speed readout: green once it's slow enough to land.
local function drawSpeed(L, y, label, speed, limit, names)
  local color = abs(speed) <= limit and C.ok or C.text
  readout(L, y, label, floor(abs(speed) * SPEED_SCALE + 0.5), color)
  local arrow = view.arrow(speed, names)
  if arrow then drawArrow(arrow, L.stripX + L.stripW, y + 2, color) end
end

local function drawStrip(L, s)
  local y = L.y0
  readout(L, y, "ALT", floor(rules.altitude(s) + 0.5), C.text)
  drawSpeed(L, y + 11, "ACROSS", s.craft.vx, rules.SAFE_VX, { "left", "right" })
  drawSpeed(L, y + 22, "DOWN", s.craft.vy, rules.SAFE_VY, { "up", "down" })
  drawTilt(L, s, y + 33)
  drawFuel(L, s, y + 38)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawStars(L, s)
  drawGround(L, s)
  for _, pad in ipairs(s.pads) do drawPad(L, pad) end
  if s.blast then drawBlast(L, s) else drawCraft(L, s) end
  if s.result then drawResult(L, s) elseif s.hold > 0 then drawHold(L, s) end
  drawStrip(L, s)
end

--- Three wide buttons stopping short of the shell's QUIT: tilt either side of THRUST, under the thumbs.
function view.controls(L)
  local x, gap, side = L.x0, 2, 28
  local w = L.W - 16 - x - 2 * side - 2 * gap
  return {
    { label = "LEFT", x = x, y = L.controlY, w = side, h = L.controlH, action = { kind = "tilt", dir = -1 } },
    { label = "THRUST", x = x + side + gap, y = L.controlY, w = w, h = L.controlH, action = { kind = "thrust" } },
    { label = "RIGHT", x = x + side + w + 2 * gap, y = L.controlY, w = side, h = L.controlH, action = { kind = "tilt", dir = 1 } },
  }
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "thrust" then app.audio.play("placeBlue", 0.8, 0.8) end
    if ev.type == "landed" then
      app.audio.play("capture")
      app.audio.later("captureRed", 140)
    end
    if ev.type == "crash" then app.audio.play("captureBlue", 1.4, 0.7) end
  end
end

return base.fill({
  id = "lander", title = "Lunar Lander", blurb = "Down soft and upright, while the fuel lasts", color = "hi", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Bring the lander down on a flat pad, slowly and upright. Gravity never stops, but everything happens slowly, so take your time over each tap.",
    "",
    "THRUST fires the engine for a second, the way the nose points. Tap again to burn for longer. LEFT and RIGHT tilt the craft a notch each. Tilt, burn, then straighten up.",
    "",
    "Watch the readouts. ACROSS and DOWN turn green when you're slow enough to land, and the arrows show which way you're drifting.",
    "",
    "Pads pay 2X to 5X. The smaller and further away, the more it's worth. A very soft touch pays a bonus. A rough one, or tilted a notch, pays less. Too fast, tilted more than that, or off the pad is a crash.",
    "",
    "Fuel is your whole run. A landing gives a little back and moves on to a harder site. A crash costs a lot. When it's gone and you've come down, the run is over.",
  },
})
