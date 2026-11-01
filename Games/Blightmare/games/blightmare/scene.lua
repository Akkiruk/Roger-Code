-- games/blightmare/scene.lua
-- The first-person view of any map in maps.DATA, built on Dungeon's. The camera stands at the back of its square, so the wall
-- in front is about two thirds of the height of the wall of the monitor. A square at distance z is TILE_W / z cells wide and
-- TILE_H / z tall: a cell is 2 wide to 3 tall, which is why these differ. Each face that shows is baked once into a flat list
-- of fills, for each place in the view it can stand, the first time it's seen, so a theme nobody has visited costs nothing.
-- Painting is far to near, so a turn is only a short walk down those lists.
--
-- A face can stand taller than its square: "up" is its height over a plain wall. That's all the roofs of the town and the great
-- wall need, since nearer faces simply paint over the foot of whatever rises behind them.

local art = require("games.blightmare.art")
local ui = require("lib.arcade.ui")
local world = require("games.blightmare.world")

local C = ui.C
local abs, floor, max, min, sin = math.abs, math.floor, math.max, math.min, math.sin

local M = {}

local VIEW_W, VIEW_H = 121, 72
local CX, CY = VIEW_W / 2, VIEW_H / 2
local TILE_W, TILE_H = 80, 160 / 3
local FARTHEST = 5                  -- the last row of squares drawn
local ROOF_UP = 1.5                 -- a house's ridge, over the height of its wall
local GREAT_UP = 3.6                -- the pandemic wall: it blocks out the sky, and it's meant to
M.VIEW_W, M.VIEW_H = VIEW_W, VIEW_H

-- plaster, its stain, timber, thatch, and the thatch's shadow, near to far. A town fades into its haze, not into the dark.
local TOWN = {
  { C.line, C.tie, C.redTint, C.hiTint, C.panel },
  { C.line, C.tie, C.redTint, C.hiTint, C.panel },
  { C.tie, C.panel, C.redTint, C.hiTint, C.panel },
  { C.tie, C.panel, C.panel, C.panel, C.panel },
  { C.panel, C.panel, C.panel, C.panel, C.panel },
  { C.panel, C.panel, C.panel, C.panel, C.panel },
}
-- main, darker, mortar, and the lit top of a block, for the great wall
local GREAT = {
  { C.line, C.tie, C.panel, C.text },
  { C.line, C.tie, C.panel, C.text },
  { C.tie, C.tie, C.panel, C.line },
  { C.tie, C.panel, C.panel, C.line },
  { C.tie, C.panel, C.panel, C.tie },
  { C.panel, C.panel, C.panel, C.tie },
}
-- rock: the seams of it, from dark to the lit edge, and the warm streak of lantern light on it
local ROCK = {
  { C.tie, C.panel, C.redTint, C.line },
  { C.tie, C.panel, C.redTint, C.line },
  { C.panel, C.redTint, C.bg, C.tie },
  { C.panel, C.bg, C.bg, C.tie },
  { C.bg, C.bg, C.bg, C.panel },
  { C.bg, C.bg, C.bg, C.bg },
}
-- timber: face, gap between planks, and the catch of the light
local WOOD = {
  { C.redTint, C.bg, C.warn },
  { C.redTint, C.bg, C.warn },
  { C.redTint, C.bg, C.redTint },
  { C.panel, C.bg, C.panel },
  { C.panel, C.bg, C.panel },
  { C.bg, C.bg, C.panel },
}
local IRON = { C.line, C.line, C.tie, C.tie, C.panel, C.bg }

-- Floor by distance: two colours, in a checker that moves as you walk. A mine has a roof over it as well.
local THEME_GROUND = {
  town = { { C.tie, C.panel }, { C.tie, C.panel }, { C.panel, C.hiTint }, { C.panel, C.hiTint }, { C.panel, C.panel } },
  mine = { { C.redTint, C.panel }, { C.panel, C.redTint }, { C.panel, C.bg }, { C.bg, C.panel }, { C.bg, C.bg } },
}
local COBBLES = { town = 4, mine = 1 }   -- paving stones to a square along each way
local MINE_ROOF = { { C.panel, C.bg }, { C.bg, C.panel }, { C.bg, C.panel }, { C.bg, C.bg }, { C.bg, C.bg } }
-- A low dirty sky, top row down: the morning never quite gets going in the Heart.
local SKY = {
  { C.blueTint, 7 }, { C.panel, 9 }, { C.tie, 11 }, { C.line, 9 },
}

-- Colours fade with distance, each one a step darker.
local FADE = {
  [C.text] = C.line, [C.line] = C.tie, [C.tie] = C.panel, [C.panel] = C.bg, [C.red] = C.redTint, [C.warn] = C.redTint,
  [C.hi] = C.warn, [C.ok] = C.hiTint, [C.soft] = C.ok, [C.accent] = C.blueTint, [C.info] = C.blueTint, [C.blue] = C.blueTint,
  [C.redTint] = C.panel, [C.hiTint] = C.panel, [C.blueTint] = C.panel,
}
local FLASH = {}
for from in pairs(FADE) do FLASH[from] = C.text end
FLASH[C.text] = C.red

local function round(v) return floor(v + 0.5) end

--- A rectangle into a list, trimmed to the view.
local function add(list, x, y, w, h, color)
  local x2, y2 = min(x + w, VIEW_W), min(y + h, VIEW_H)
  x, y = max(x, 0), max(y, 0)
  if x2 <= x or y2 <= y then return end
  local n = #list
  list[n + 1], list[n + 2], list[n + 3], list[n + 4], list[n + 5] = x, y, x2 - x, y2 - y, color
end

--- A number from 0 to 99 that's always the same for the same block.
local function hash(a, b, c) return (a * 37 + b * 101 + c * 59 + a * b * 13) % 100 end

-- ---------------------------------------------------------------- faces square-on to the camera

--- A rising brace in the frame of a house, as a stair of short beams.
local function brace(list, x, y, w, h, ink, thick, flip)
  for i = 0, h - 1 do
    local at = round((w - thick * 3) * i / max(h - 1, 1))
    add(list, flip and x + w - at - thick * 3 or x + at, y + h - i - 1, thick * 3, 1, ink)
  end
end

--- Timber and plaster under a gable. look: 0 and 1 plain, 2 a lit window, 3 boarded up, with the Clinic's cross on the boards.
local function houseFront(list, x1, y1, x2, y2, shade, look)
  local ramp = TOWN[shade]
  local w, h = x2 - x1, y2 - y1
  local beam = max(1, round(h / 16))
  -- the gable and the eave. A row of them makes a street.
  local rise = round(h * (ROOF_UP - 1) / 2)
  for i = 1, rise do
    local inset = round(w * 0.56 * (rise - i + 1) / rise) - round(w * 0.06)
    add(list, x1 + inset, y1 - rise + i - 1, w - inset * 2, 1, i <= 2 and ramp[5] or ramp[4])
  end
  add(list, x1, y1, w, h, ramp[1])
  if h < 5 then return end
  add(list, x1, y1, w, beam + 1, ramp[3])
  add(list, x1, y2 - beam - 1, w, beam + 1, ramp[3])
  add(list, x1, y1 + round(h * 0.48), w, beam, ramp[3])
  add(list, x1, y1, beam * 2, h, ramp[3])
  add(list, x2 - beam * 2, y1, beam * 2, h, ramp[3])
  if h >= 12 then
    add(list, x1 + round(w * 0.5) - beam, y1, beam * 2, h, ramp[3])
    brace(list, x1 + beam * 2, y1 + round(h * 0.48) + beam, round(w * 0.5) - beam * 3, round(h * 0.52) - beam * 2, ramp[3], beam, look == 1)
    brace(list, x1 + round(w * 0.5) + beam, y1 + round(h * 0.48) + beam, round(w * 0.5) - beam * 3, round(h * 0.52) - beam * 2, ramp[3], beam, look ~= 1)
  end
  if h >= 8 and look >= 2 then
    local wx1, wx2 = x1 + round(w * 0.2), x1 + round(w * 0.8)
    local wy1, wy2 = y1 + round(h * 0.13), y1 + round(h * 0.42)
    if look == 2 then
      add(list, wx1 - beam, wy1 - beam, wx2 - wx1 + beam * 2, wy2 - wy1 + beam * 2, ramp[3])
      add(list, wx1, wy1, wx2 - wx1, wy2 - wy1, shade <= 3 and C.warn or C.redTint)
      add(list, wx1, round((wy1 + wy2) / 2), wx2 - wx1, beam, ramp[3])
      add(list, round((wx1 + wx2) / 2), wy1, beam, wy2 - wy1, ramp[3])
      if h >= 16 then add(list, wx1 + 1, wy1 + 1, round((wx2 - wx1) / 3), 2, C.hi) end
    else
      add(list, wx1, wy1, wx2 - wx1, wy2 - wy1, C.bg)
      for i = 0, 2 do add(list, wx1 - 1, wy1 + round((wy2 - wy1) * (i + 0.2) / 3), wx2 - wx1 + 2, max(1, round(h * 0.06)), WOOD[shade][1]) end
      if h >= 16 then
        local n = wx2 - wx1
        for i = 0, n - 1, 2 do
          local dy = round((wy2 - wy1) * i / n)
          add(list, wx1 + i, wy1 + dy, 2, 2, C.red)
          add(list, wx2 - i - 2, wy1 + dy, 2, 2, C.red)
        end
      end
    end
  end
end

local function timberFront(list, x1, y1, x2, y2, shade)
  local ramp = WOOD[shade]
  add(list, x1, y1, x2 - x1, y2 - y1, ramp[1])
  local w = x2 - x1
  if w < 6 then return end
  for plank = 0, 7 do
    local x = x1 + round(w * plank / 8)
    add(list, x, y1, 1, y2 - y1, ramp[2])
    if shade <= 2 then add(list, x + 1, y1 + (plank % 3) * 2, 1, y2 - y1 - plank % 3, ramp[1]) end
    if shade <= 2 and plank % 2 == 0 then add(list, x + 2, y1 + 3, 1, 1, ramp[3]) end
  end
  local rail = max(1, round((y2 - y1) / 18))
  add(list, x1, y1 + round((y2 - y1) * 0.18), w, rail, ramp[2])
  add(list, x1, y1 + round((y2 - y1) * 0.78), w, rail, ramp[2])
end

--- Poured and piled in a hurry, and stained where the rain comes down it. It doesn't look like anything meant to last. It has.
local function greatFront(list, x1, y1, x2, y2, shade, variant)
  local ramp = GREAT[shade]
  add(list, x1, y1, x2 - x1, y2 - y1, ramp[1])
  local tall = (y2 - y1) / 14
  if tall < 1.5 then return end
  for course = 0, 13 do
    local top, bottom = y1 + round(tall * course), y1 + round(tall * (course + 1))
    local shift = (course + variant) % 2 == 0 and 0 or 0.5
    for block = -1, 2 do
      local from = max(x1, x1 + round((block + shift) / 2 * (x2 - x1)))
      local to = min(x2, x1 + round((block + 1 + shift) / 2 * (x2 - x1)))
      if to > from then
        if hash(course, block, variant) < 34 then add(list, from, top, to - from, bottom - top, ramp[2]) end
        add(list, to - 1, top, 1, bottom - top, ramp[3])
      end
    end
    add(list, x1, top, x2 - x1, 1, ramp[3])
  end
  -- streaks down from the top, and the rust of the Clinic's wire along it
  local w = x2 - x1
  for i = 0, 5 do
    local x = x1 + round(w * (i + 0.5) / 6)
    local long = (y2 - y1) * (0.2 + hash(i, variant, 3) / 140)
    add(list, x, y1, max(1, round(w / 40)), round(long), i % 2 == 0 and ramp[3] or C.redTint)
  end
  for x = x1, x2 - 1, 2 do add(list, x, y1 - 1, 1, 1, C.redTint) end
end

--- Rock laid down in seams that wander, with a lit edge here and there. Painted in short columns, so it's never a grid.
local function rockFront(list, x1, y1, x2, y2, shade, variant)
  local ramp = ROCK[shade]
  add(list, x1, y1, x2 - x1, y2 - y1, ramp[1])
  local w, h = x2 - x1, y2 - y1
  if h < 4 then return end
  local step = max(1, floor(w / 26))
  local seams = 7
  local wide = h / seams
  for col = x1, x2 - 1, step do
    local v = (col - x1) / w
    for seam = 0, seams - 1 do
      local wander = sin(v * 7 + seam * 1.9 + variant) * wide * 0.5 + sin(v * 17 + seam) * wide * 0.2
      local y = y1 + round(wide * seam + wander)
      local look = hash(seam, floor(v * 5 + seam * 0.5), variant)
      if look < 34 then add(list, col, y, step, max(1, round(wide * 0.6)), ramp[2]) end
      if look > 80 then add(list, col, y, step, max(1, round(wide * 0.4)), ramp[3]) end
      add(list, col, y, step, 1, look % 3 == 0 and ramp[4] or C.bg)
    end
  end
end

--- A lantern on a hook. The light on the rock around it is the only warm thing down here.
local function lanternOn(list, x1, y1, x2, y2)
  local h = y2 - y1
  local cx, top = round((x1 + x2) / 2), y1 + round(h * 0.3)
  local size = max(1, round(h / 26))
  add(list, cx - size * 5, top - size * 3, size * 10, size * 11, C.redTint)
  add(list, cx - size * 7, top - size, size * 14, size * 6, C.redTint)
  add(list, cx - size * 2, top - size * 4, size * 3, size, C.line)
  add(list, cx, top - size * 4, size, size * 2, C.line)
  add(list, cx - size * 2, top - size * 2, size * 4, size, C.bg)
  add(list, cx - size * 2, top - size, size * 4, size * 4, C.warn)
  add(list, cx - size, top, size * 2, size * 2, C.hi)
  add(list, cx - size * 2, top + size * 3, size * 4, size, C.bg)
end

--- Pit props: two posts and a cap, holding up the rock, with boards behind them. Some have started to bow.
local function propFront(list, x1, y1, x2, y2, shade, variant)
  rockFront(list, x1, y1, x2, y2, shade, variant)
  local ramp = WOOD[shade]
  local w, h = x2 - x1, y2 - y1
  local post, cap = max(1, round(w * 0.12)), max(1, round(h * 0.11))
  add(list, x1 + post, y1 + cap, w - post * 2, h - cap, ramp[2])
  for i = 1, 4 do
    local y = y1 + cap + round((h - cap) * (i - 0.5) / 4)
    add(list, x1 + post, y, w - post * 2, max(1, round(h / 13)), ramp[1])
  end
  add(list, x1, y1 + cap, post, h - cap, ramp[1])
  add(list, x2 - post, y1 + cap, post, h - cap, ramp[1])
  add(list, x1, y1, w, cap, ramp[1])
  add(list, x1, y1 + cap - 1, w, 1, ramp[2])
  if shade <= 3 then
    add(list, x1, y1, w, 1, ramp[3])
    add(list, x1, y1 + cap, 1, h - cap, ramp[3])
    add(list, x2 - post, y1 + cap, 1, h - cap, ramp[3])
  end
end

local PAINT_WALL = {
  house0 = function(l, a, b, c, d, s) houseFront(l, a, b, c, d, s, 0) end,
  house1 = function(l, a, b, c, d, s) houseFront(l, a, b, c, d, s, 1) end,
  houseLit = function(l, a, b, c, d, s) houseFront(l, a, b, c, d, s, 2) end,
  houseShut = function(l, a, b, c, d, s) houseFront(l, a, b, c, d, s, 3) end,
  timber = function(l, a, b, c, d, s) timberFront(l, a, b, c, d, s) end,
  rock0 = function(l, a, b, c, d, s) rockFront(l, a, b, c, d, s, 0) end,
  rock1 = function(l, a, b, c, d, s) rockFront(l, a, b, c, d, s, 2) end,
  lantern = function(l, a, b, c, d, s)
    rockFront(l, a, b, c, d, s, 1)
    if s <= 4 then lanternOn(l, a, b, c, d) end
  end,
  prop = function(l, a, b, c, d, s) propFront(l, a, b, c, d, s, 1) end,
}

--- A plank door in its frame, set in whichever wall the theme has. A locked one has red bands and a padlock you can see from
-- down the street.
local function doorFront(list, wall, x1, y1, x2, y2, shade, locked)
  PAINT_WALL[wall](list, x1, y1, x2, y2, shade)
  local w, h = x2 - x1, y2 - y1
  local inX, top = round(w * 0.18), round(h * 0.12)
  local dx1, dx2, dy1 = x1 + inX, x2 - inX, y1 + top
  local wood = WOOD[shade]
  add(list, dx1 - 1, dy1 - 1, dx2 - dx1 + 2, y2 - dy1 + 1, wood[2])
  add(list, dx1, dy1, dx2 - dx1, y2 - dy1, wood[1])
  for plank = 1, 3 do add(list, dx1 + round((dx2 - dx1) * plank / 4), dy1, 1, y2 - dy1, wood[2]) end
  local band = locked and (shade <= 3 and C.red or C.redTint) or IRON[shade]
  local bandH = max(1, round(h * 0.05))
  add(list, dx1, dy1 + round(h * 0.16), dx2 - dx1, bandH, band)
  add(list, dx1, dy1 + round(h * 0.62), dx2 - dx1, bandH, band)
  if h >= 12 then
    local cx = round((dx1 + dx2) / 2)
    local cy = dy1 + round(h * 0.42)
    if locked then
      local size = max(2, round(h * 0.08))
      add(list, cx - size, cy - size, size * 2, size * 2, C.hi)
      add(list, cx - round(size / 2), cy - size * 2, size, size, C.line)
      add(list, cx, cy - round(size / 2), 1, size, C.bg)
    else
      add(list, dx2 - round(w * 0.1), cy, max(1, round(w * 0.04)), max(1, round(h * 0.05)), C.hi)
    end
  end
end

--- An arch with steps going down into the dark, and a warm light at its rim so it reads from far off.
local function stairsFront(list, wall, x1, y1, x2, y2, shade)
  PAINT_WALL[wall](list, x1, y1, x2, y2, shade)
  local w, h = x2 - x1, y2 - y1
  local inX, top = round(w * 0.1), round(h * 0.08)
  local ax1, ax2, ay1 = x1 + inX, x2 - inX, y1 + top
  add(list, ax1 - 1, ay1 - 1, ax2 - ax1 + 2, y2 - ay1 + 1, shade <= 4 and C.hi or C.warn)
  add(list, ax1, ay1, ax2 - ax1, y2 - ay1, C.bg)
  local ramp = { C.text, C.line, C.tie, C.panel, C.bg }
  if shade > 2 then ramp = { C.line, C.tie, C.panel, C.bg, C.bg } end
  if shade > 3 then ramp = { C.tie, C.panel, C.bg, C.bg, C.bg } end
  local steps = #ramp
  for step = 1, steps do
    local share = (steps - step) / steps
    local inset = round((ax2 - ax1) * 0.32 * (1 - share))
    local y = ay1 + round((y2 - ay1) * (0.38 + 0.62 * share))
    local bottom = ay1 + round((y2 - ay1) * (0.38 + 0.62 * (share + 1 / steps)))
    add(list, ax1 + inset, y, ax2 - ax1 - inset * 2, max(1, bottom - y), ramp[steps - step + 1])
    add(list, ax1 + inset, y, ax2 - ax1 - inset * 2, 1, C.bg)
  end
end

-- ---------------------------------------------------------------- faces running away from the camera

--- paint(col, top, bottom, u, shade, half) for each column of a face at an offset of edge from the camera's line. top and
-- bottom are those of a plain wall there, and u runs along the face from its near end.
local function columns(edge, nearZ, farZ, paint)
  local xNear, xFar = CX + edge * TILE_W / nearZ, CX + edge * TILE_W / farZ
  local from, to = round(min(xNear, xFar)), round(max(xNear, xFar)) - 1
  for col = max(from, 0), min(to, VIEW_W - 1) do
    local z = edge * TILE_W / (col + 0.5 - CX)
    local half = TILE_H / 2 / z
    local depth = z + 0.55
    local shade = min(6, floor(depth + ((col % 2 == 0) and 0.3 or 0)))
    paint(col, round(CY - half), round(CY + half), (z - nearZ) / (farZ - nearZ), shade, half)
  end
end

local SIDE = {}

function SIDE.house(list, edge, nearZ, farZ, door)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade, half)
    local ramp = TOWN[shade]
    local tall = bottom - top
    add(list, col, round(CY - half * ROOF_UP), 1, top - round(CY - half * ROOF_UP), ramp[4])
    add(list, col, top - 1, 1, 1, ramp[5])
    local post = (u < 0.05 or u > 0.95 or abs(u - 0.5) < 0.03)
    add(list, col, top, 1, tall, post and ramp[3] or ramp[1])
    if tall >= 8 then
      add(list, col, top, 1, max(1, round(tall / 14)), ramp[3])
      add(list, col, top + round(tall * 0.48), 1, max(1, round(tall / 18)), ramp[3])
      add(list, col, bottom - max(1, round(tall / 14)), 1, max(1, round(tall / 14)), ramp[3])
    end
    if door and u > 0.2 and u < 0.8 then
      local wood = WOOD[shade]
      add(list, col, top + round(tall * 0.12), 1, tall - round(tall * 0.12), (u < 0.26 or u > 0.74) and wood[2] or wood[1])
    end
  end)
end

function SIDE.timber(list, edge, nearZ, farZ)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
    local ramp = WOOD[shade]
    local gap = (u * 8) % 1 < 0.12
    add(list, col, top, 1, bottom - top, gap and ramp[2] or ramp[1])
  end)
end

function SIDE.great(list, edge, nearZ, farZ, door)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade, half)
    local ramp = GREAT[shade]
    local high = round(CY - half * GREAT_UP)
    add(list, col, high, 1, bottom - high, ramp[1])
    local tall = (bottom - high) / 14
    if tall >= 1.5 then
      for course = 0, 13 do
        local y = high + round(tall * course)
        local block = floor(u * 2 + (course % 2 == 0 and 0 or 0.5))
        if hash(course, block, nearZ * 3) < 34 then add(list, col, y, 1, round(tall * (course + 1)) - round(tall * course), ramp[2]) end
        add(list, col, y, 1, 1, ramp[3])
      end
    end
    if door and u > 0.25 and u < 0.75 then add(list, col, top + round((bottom - top) * 0.2), 1, bottom - top, C.bg) end
  end)
end

function SIDE.rock(list, edge, nearZ, farZ, door, row)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
    local ramp = ROCK[shade]
    local tall = bottom - top
    add(list, col, top, 1, tall, ramp[1])
    if tall >= 5 then
      local seams = 7
      local wide = tall / seams
      for seam = 0, seams - 1 do
        local y = top + round(wide * seam + sin(u * 5 + seam * 1.9 + row) * wide * 0.5)
        local look = hash(seam, floor(u * 4 + seam * 0.5), row)
        if look < 34 then add(list, col, y, 1, max(1, round(wide * 0.6)), ramp[2]) end
        if look > 80 then add(list, col, y, 1, max(1, round(wide * 0.4)), ramp[3]) end
        add(list, col, y, 1, 1, look % 3 == 0 and ramp[4] or C.bg)
      end
    end
    if door and u > 0.2 and u < 0.8 then
      local wood = WOOD[shade]
      add(list, col, top + round(tall * 0.12), 1, tall - round(tall * 0.12), (u < 0.26 or u > 0.74) and wood[2] or wood[1])
    end
  end)
end

function SIDE.prop(list, edge, nearZ, farZ, door, row)
  SIDE.rock(list, edge, nearZ, farZ, door, row)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
    local ramp = WOOD[shade]
    local tall = bottom - top
    add(list, col, top, 1, max(1, round(tall * 0.11)), ramp[1])
    if u < 0.14 or u > 0.86 then add(list, col, top, 1, tall, ramp[1]) end
  end)
end

--- A lantern hung on a corridor wall, in its pool of light. Most of a mine is seen side-on, so this is where the warmth shows.
function SIDE.lantern(list, edge, nearZ, farZ, door, row)
  SIDE.rock(list, edge, nearZ, farZ, door, row)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
    if shade > 4 or u < 0.28 or u > 0.72 then return end
    local tall = bottom - top
    add(list, col, top + round(tall * 0.14), 1, round(tall * 0.42), C.redTint)
    if u > 0.42 and u < 0.58 then
      add(list, col, top + round(tall * 0.2), 1, max(1, round(tall * 0.03)), C.line)
      add(list, col, top + round(tall * 0.24), 1, max(1, round(tall * 0.14)), shade <= 2 and C.hi or C.warn)
      add(list, col, top + round(tall * 0.38), 1, max(1, round(tall * 0.03)), C.bg)
    end
  end)
end

-- ---------------------------------------------------------------- themes

-- What each tile of a map looks like. wall is the plain kind of this theme, for the frames of doors and arches.
local THEMES = {
  town = {
    wall = "house0", sky = true, reachAll = true,
    -- In a town h is what the houses are built of, and # is the plank palisade round the edge of it.
    side = { ["#"] = "timber", h = "house", W = "great", ["+"] = "house", L = "house", [">"] = "house" },
    pick = function(c, x, y)
      if c == "#" then return "timber" end
      if c == "W" then return "great" end
      local n = (x * 7 + y * 13) % 5
      if n == 0 then return "houseLit" end
      if n == 2 then return "houseShut" end
      return "house" .. (x + y) % 2
    end,
  },
  mine = {
    wall = "rock0",
    side = { ["#"] = "rock", h = "prop", W = "rock", ["+"] = "rock", L = "rock", [">"] = "rock" },
    -- every few squares the rock has been shored up, or has a light on it
    sidePick = function(c, x, y)
      if c ~= "#" then return nil end
      if (x * 7 + y * 13) % 5 == 0 then return "lantern" end
      if (x + y * 2) % 3 == 0 then return "prop" end
      return nil
    end,
    pick = function(c, x, y)
      if c == "h" then return "prop" end
      if (x * 7 + y * 13) % 5 == 0 then return "lantern" end
      return "rock" .. (x + y) % 2
    end,
  },
}
M.THEMES = THEMES

local function themeOf(mapId)
  local map = world.map(mapId)
  return THEMES[map and map.theme] or THEMES.mine
end

--- The sky and the ground together, in runs along each row. parity flips as you step, which is what shows you moving.
local function bakeGround(theme, name, parity)
  local list = {}
  local paintFloor = THEME_GROUND[name] or THEME_GROUND.mine
  local cobble = COBBLES[name] or 1
  for row = 0, VIEW_H - 1 do
    local below = row + 0.5 > CY
    local z = (TILE_H / 2) / abs(row + 0.5 - CY)
    local band = min(FARTHEST, max(1, floor(z)))
    local paint = below and paintFloor[band] or MINE_ROOF[band]
    if not below and theme.sky then
      local upTo, ink = 0, C.line
      for _, part in ipairs(SKY) do
        upTo = upTo + part[2]
        ink = part[1]
        if row < upTo then break end
      end
      add(list, 0, row, VIEW_W, 1, ink)
    elseif z >= FARTHEST then
      add(list, 0, row, VIEW_W, 1, theme.sky and C.panel or C.bg)
    else
      local from = 0
      local inkOf = function(col)
        local lateral = (col + 0.5 - CX) * z / TILE_W
        return paint[(floor(lateral * cobble + 0.5) + floor(z * cobble) + parity) % 2 + 1]
      end
      local ink = inkOf(0)
      for col = 1, VIEW_W do
        local here = col < VIEW_W and inkOf(col) or nil
        if here ~= ink then
          add(list, from, row, col - from, 1, ink)
          from, ink = col, here
        end
      end
    end
  end
  -- banks of cloud, and the smoke of the Clinic's burning, low on the sky
  if theme.sky then
    for i, cloud in ipairs({ { 12, 5, 34, 2 }, { 58, 9, 40, 3 }, { 86, 3, 26, 2 }, { 24, 14, 46, 2 }, { 76, 19, 30, 2 } }) do
      local ink = i % 2 == 0 and C.tie or C.panel
      add(list, cloud[1], cloud[2], cloud[3], cloud[4], ink)
      add(list, cloud[1] + 6, cloud[2] - 1, cloud[3] - 14, 1, ink)
    end
  end
  return list
end

--- How many squares either side of the middle a row can show.
local function lateralsOf(row) return floor(0.75 * row + 1) end

local function bakeFront(theme, kind, row, l)
  local list = {}
  local z = row
  local shade = min(6, row)
  local x1 = round(CX + (l - 0.5) * TILE_W / z)
  local x2 = round(CX + (l + 0.5) * TILE_W / z)
  local half = TILE_H / 2 / z
  local y1, y2 = round(CY - half), round(CY + half)
  if kind == "great" then
    greatFront(list, x1, round(CY - half * GREAT_UP), x2, y2, shade, (l + row) % 2)
  elseif kind == "stairs" then
    stairsFront(list, theme.wall, x1, y1, x2, y2, shade)
  elseif kind == "door" or kind == "locked" then
    doorFront(list, theme.wall, x1, y1, x2, y2, shade, kind == "locked")
  else
    PAINT_WALL[kind](list, x1, y1, x2, y2, shade)
  end
  return list
end

local fronts, sides, grounds = {}, {}, {}

local function frontOf(theme, kind, row, l)
  local key = theme.wall .. kind .. ":" .. row .. ":" .. l
  local list = fronts[key]
  if not list then
    list = bakeFront(theme, kind, row, l)
    fronts[key] = list
  end
  return list
end

local function sideOf(kind, row, l, door)
  local key = kind .. (door and "+" or "") .. ":" .. row .. ":" .. l
  local list = sides[key]
  if not list then
    list = {}
    local edge = l < 0 and l + 0.5 or l - 0.5
    SIDE[kind](list, edge, max(row, 0.3), row + 1, door, row)
    sides[key] = list
  end
  return list
end

local function blit(ox, oy, list)
  local fill = ui.fill
  for i = 1, #list, 5 do fill(ox + list[i], oy + list[i + 1], list[i + 2], list[i + 3], list[i + 4]) end
end

--- A sprite standing on the floor at a place in the view. Its colours fade with distance.
local function drawSprite(ox, oy, name, row, l, flash)
  name = art.spriteName(name)
  local sprite = art.SPRITES[name]
  local z = row + sprite.near
  local tileW, tileH = TILE_W / z, TILE_H / z
  local w, h = round(tileW * sprite.size), round(tileH * sprite.size)
  if w < 2 or h < 2 then return end
  local x = round(CX + l * tileW - w / 2)
  local y = round(CY + tileH / 2 - h)
  local remap, look
  if flash then
    remap, look = FLASH, "flash"
  elseif row >= 4 then
    remap, look = FADE, "fade"
  end
  -- runs past the edge of the view are cut, so the side of the wall never shows a sprite's elbow
  local runs = art.bake(name, w, h, remap, look)
  local fill = ui.fill
  for i = 1, #runs, 4 do
    local cx, cy, cw = x + runs[i], y + runs[i + 1], runs[i + 2]
    if cx < 0 then cx, cw = 0, cw + cx end
    cw = min(cw, VIEW_W - cx)
    if cy >= 0 and cy < VIEW_H and cw > 0 then fill(ox + cx, oy + cy, cw, 1, runs[i + 3]) end
  end
end
M.drawSprite = drawSprite

--- The map square at a place in the view: row squares ahead, and l to the right. Row 0 is the player's own.
local function squareAt(s, row, l)
  local d = world.DIRS[s.dir]
  return s.x + d[1] * row - d[2] * l, s.y + d[2] * row + d[1] * l
end

local WALLISH = { ["#"] = true, h = true, W = true, ["+"] = true, L = true, [">"] = true }

--- Does the eye stop here? An open door is a gap, and stairs are a face though you can walk into them.
local function blocksEye(s, x, y)
  local c = world.tileAt(s.map, x, y)
  if c == "+" or c == "L" then return world.solid(s.map, x, y, s) end
  return WALLISH[c] == true
end

local FACE_OF = { ["+"] = "door", L = "locked", [">"] = "stairs" }

local function paintSquare(ox, oy, s, theme, row, l, things)
  local x, y = squareAt(s, row, l)
  if blocksEye(s, x, y) then
    local c = world.tileAt(s.map, x, y)
    if l ~= 0 and row <= FARTHEST then
      local door = c == "+" or c == "L" or c == ">"
      local kind = theme.sidePick and theme.sidePick(c, x, y)
      blit(ox, oy, sideOf(kind or theme.side[c] or "rock", row, l, door))
    end
    if row > 0 then blit(ox, oy, frontOf(theme, FACE_OF[c] or theme.pick(c, x, y), row, l)) end
  end
  if row > 0 and row < FARTHEST then
    local list = things[y * 1000 + x]
    if list then
      for _, one in ipairs(list) do
        drawSprite(ox, oy, one.sprite, row, l, one.foe and s.fx and (s.fx.flash or 0) > 0 and row == 1 and l == 0)
      end
    end
  end
end

local function passes(s, thing)
  local flags = s.flags or {}
  if thing.when and not flags[thing.when] then return false end
  if thing.unless and flags[thing.unless] then return false end
  return true
end

--- Index what's on the map by square, so a frame doesn't search a list for each place in the view.
local function indexThings(s, map)
  local things = {}
  local function put(x, y, thing)
    local key = y * 1000 + x
    local list = things[key]
    if not list then
      list = {}
      things[key] = list
    end
    list[#list + 1] = thing
  end
  for _, c in ipairs(map.chests or {}) do
    put(c.x, c.y, { sprite = (s.opened or {})[s.map .. ":" .. c.id] and "openChest" or "chest" })
  end
  for _, n in ipairs(map.npcs or {}) do
    if passes(s, n) then put(n.x, n.y, { sprite = n.sprite }) end
  end
  local sprites = {}
  for _, f in ipairs(map.foes or {}) do sprites[f.id] = f.sprite end
  for _, f in ipairs(s.foes or {}) do put(f.x, f.y, { sprite = sprites[f.id], foe = true }) end
  return things
end

--- How far the corridor runs ahead before a solid square stops the eye: nothing behind that can show. A town's roofs and the
-- great wall stand above what's in front of them, so there the eye always goes the whole way.
local function reach(s, theme)
  if theme.reachAll then return FARTHEST end
  for row = 1, FARTHEST do
    local x, y = squareAt(s, row, 0)
    if blocksEye(s, x, y) then return row end
  end
  return FARTHEST
end

--- Paint the map's view into the rectangle at ox, oy.
function M.draw(ox, oy, s)
  local map = world.map(s.map) or { rows = {} }
  local name = map.theme or "mine"
  local theme = themeOf(s.map)
  local parity = (s.x + s.y) % 2 + 1
  local key = name .. parity
  local ground = grounds[key]
  if not ground then
    ground = bakeGround(theme, name, parity - 1)
    grounds[key] = ground
  end
  blit(ox, oy, ground)
  local things = indexThings(s, map)
  for row = reach(s, theme), 0, -1 do
    local span = lateralsOf(row)
    for l = span, 1, -1 do
      paintSquare(ox, oy, s, theme, row, -l, things)
      paintSquare(ox, oy, s, theme, row, l, things)
    end
    paintSquare(ox, oy, s, theme, row, 0, things)
  end
end

return M
