-- games/blightmare/scene.lua
-- The first-person view of any map in maps.DATA, built on Dungeon's. The camera stands at the back of its square, so the wall
-- in front is about two thirds of the height of the wall of the monitor. A square at distance z is TILE_W / z cells wide and
-- TILE_H / z tall: a cell is 2 wide to 3 tall, which is why these differ. Each face that shows is baked once into a flat list
-- of fills, for each place in the view it can stand, the first time it's seen, so a theme nobody has visited costs nothing.
-- Painting is far to near, so a turn is only a short walk down those lists.
--
-- A face can stand taller than its square: "up" is its height over a plain wall. That's all the roofs of the town and the great
-- wall need, since nearer faces simply paint over the foot of whatever rises behind them.
--
-- The town and the mine are drawn by hand. Every other theme is a rule, tex(u, v, n, near), that says what colour a face is at
-- u across and v down it, the same rule for the faces you meet and the faces that run away from you. v above 0 is over the top of
-- the wall, and a rule can answer nil to leave a hole, which is how the skylines get broken and the eye gets through chains.
-- A rule is sampled once for each cell of a face, once ever, so it's free after the first look.
--
-- ~ is a drop or deep water: nothing stands there, and what's under it is painted on the floor of its square. See bakePit.

local art = require("games.blightmare.art")
local ui = require("lib.arcade.ui")
local world = require("games.blightmare.world")

local C = ui.C
local abs, floor, max, min, sin = math.abs, math.floor, math.max, math.min, math.sin
local atan2, pi, sqrt = math.atan2, math.pi, math.sqrt

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

local RULED = {} -- the ruled walls by name, with their rule. See wallKind.

--- A plank door in its frame, set in whichever wall the theme has. A locked one has red bands and a padlock you can see from
-- down the street.
local function doorFront(list, wall, x1, y1, x2, y2, shade, locked)
  PAINT_WALL[wall](list, x1, y1, x2, y2, shade)
  local w, h = x2 - x1, y2 - y1
  local inX, top = round(w * 0.18), round(h * 0.12)
  local dx1, dx2, dy1 = x1 + inX, x2 - inX, y1 + top
  local wood = (RULED[wall] and RULED[wall].wood or WOOD)[shade]
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

-- ---------------------------------------------------------------- faces painted by rule

local DARKENS = { 0, 0, 1, 2, 3, 4 }  -- how many steps down FADE each shade goes
local SUNLIT = { 0, 0, 0, 1, 1, 2 }   -- in full daylight things keep their colour a long way

local function faded(ink, steps)
  for _ = 1, steps do ink = FADE[ink] or ink end
  return ink
end

--- The runs of one column of a face: y, height, ink, over and over. top and bottom are those of a plain wall there.
local function ruleColumn(spec, u, top, bottom, shade, door)
  local tall = bottom - top
  local runs, n, ink, from = {}, 0, false, 0
  local steps, wood = spec.steps[shade], (spec.wood or WOOD)[shade]
  local near, rule, var = shade <= 3, spec.tex, spec.var
  local haze = shade >= 5 and spec.haze
  local bare = door and u > 0.2 and u < 0.8
  local y1 = max(0, top - round(tall * (spec.up - 1) / 2))
  local y2 = min(VIEW_H, bottom)
  for y = y1, y2 do
    local here = false
    if y < y2 then
      local v = (y + 0.5 - top) / tall
      if bare and v > 0.12 then
        here = (u < 0.26 or u > 0.74) and wood[2] or wood[1]
      else
        here = rule(u, v, var, near)
        if here then
          here = faded(here, steps)
          if haze and here == C.bg then here = haze end
        else
          here = false
        end
      end
    end
    if here ~= ink then
      if ink then
        runs[n + 1], runs[n + 2], runs[n + 3] = from, y - from, ink
        n = n + 3
      end
      from, ink = y, here
    end
  end
  return runs
end

--- Hands columns on to the list, one wide fill for any stretch of columns that came out the same.
local function columnSink(list)
  local held, key, from, wide
  local function flush()
    if not held then return end
    for i = 1, #held, 3 do add(list, from, held[i], wide, held[i + 1], held[i + 2]) end
    held = nil
  end
  return function(col, runs)
    local now = table.concat(runs, ",")
    if held and now == key and col == from + wide then
      wide = wide + 1
    else
      flush()
      held, key, from, wide = runs, now, col, 1
    end
  end, flush
end

local function ruleFront(list, x1, y1, x2, y2, shade, spec)
  local give, flush = columnSink(list)
  local w = max(x2 - x1, 1)
  for col = max(x1, 0), min(x2, VIEW_W) - 1 do
    give(col, ruleColumn(spec, (col + 0.5 - x1) / w, y1, y2, shade))
  end
  flush()
end

--- Name a wall that's painted by a rule, for both ways of seeing it. up: its height over a plain wall, as in the houses' roofs.
-- steps: SUNLIT rather than DARKENS. haze: what black turns into far off, under a sky. wood: the doors in it.
local function wallKind(name, tex, opts)
  opts = opts or {}
  opts.tex, opts.up, opts.steps = tex, opts.up or 1, opts.steps or DARKENS
  opts.var = opts.var or 0
  RULED[name] = opts
  PAINT_WALL[name] = function(l, a, b, c, d, s) ruleFront(l, a, b, c, d, s, opts) end
  SIDE[name] = function(list, edge, nearZ, farZ, door)
    local give, flush = columnSink(list)
    columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
      give(col, ruleColumn(opts, u, top, bottom, shade, door))
    end)
    flush()
  end
end

--- A lumpy line from 0 to about 1, for the top of something broken.
local function lump(u, k) return 0.5 + sin(u * k) * 0.3 + sin(u * k * 2.3 + 1) * 0.2 end

-- ---- Adaphis: the city is a skeleton. Great ribs of pale bone over dark masonry, and steeples thin as needles.
local function boneTex(u, v, n, near)
  if n == 1 and v < 0 then
    local half = 0.26 * (1 + v / 2.1)
    if abs(u - 0.5) > half then return nil end
    if (v * 5) % 1 < 0.1 then return C.tie end
    return u < 0.5 and C.text or C.line
  end
  if v < 0 then
    -- the ribs go on past the wall and come to a point, curling in
    local r = (u * 2) % 1
    local away = r - 0.5 + v * 0.7 * (u < 0.5 and 1 or -1)
    return abs(away) < 0.16 * (1 + v / 0.5) and C.text or nil
  end
  local r = (u * 2) % 1
  local bow = sin(v * pi) * 0.14 * (u < 0.5 and 1 or -1)
  local d = abs(r - 0.5 - bow)
  if d < 0.16 then
    if d > 0.11 then return C.line end
    if near and (v * 7) % 1 < 0.08 then return C.line end
    return C.text
  end
  if n == 2 and abs(u - 0.5) < 0.13 and v > 0.2 then
    -- a slit of a window, and someone's light behind it
    return (abs(u - 0.5) < 0.09 and v > 0.25) and ((v % 0.2 < 0.04) and C.bg or C.warn) or C.bg
  end
  if v > 0.92 then return C.line end
  if (v * 6) % 1 < 0.1 then return C.panel end
  return ((u * 6 + floor(v * 6) * 0.5) % 1 < 0.06) and C.panel or C.tie
end

-- ---- Sindal: everything is clean. White stone, gold lines, tall blue glass, a red ribbon, and gardens cut to the inch.
local function marbleTex(u, v, n, near)
  if v < 0 then
    if n == 1 then
      -- a mast, and a ribbon streaming off it in a wind that never stops
      if abs(u - 0.5) < 0.025 then return C.hi end
      local wave = -0.22 + sin(u * 11) * 0.05
      if u > 0.5 and u < 0.98 and abs(v - wave * (1 + (u - 0.5))) < 0.05 - (u - 0.5) * 0.06 then return C.red end
      return nil
    end
    if (u * 6) % 1 < 0.34 and v > -0.08 then return C.text end
    if abs(u - 0.5) < 0.06 and v > -0.14 then return C.hi end
    return nil
  end
  if v < 0.05 or v > 0.94 then return C.hi end
  if v < 0.08 or v > 0.91 then return C.line end
  if n == 1 and abs(u - 0.5) < 0.17 and v < 0.84 - abs(u - 0.5) * 0.9 then
    if abs(u - 0.5) > 0.14 then return C.hi end
    return (near and (v * 8) % 1 < 0.07) and C.redTint or C.red
  end
  if n == 0 then
    local x, y = (u - 0.5) / 0.22, (v - 0.4) / 0.3
    if abs(x) < 1 and y < 1.2 and (y > 0 or x * x + y * y < 1) then
      if abs(x) > 0.82 or (y < 0 and x * x + y * y > 0.7) or y > 1.05 then return C.hi end
      if abs(x) < 0.07 then return C.hi end
      return (u + v * 0.5) % 0.34 < 0.1 and C.info or C.blue
    end
  end
  if near and (v * 4) % 1 < 0.03 then return C.line end
  if near and (u * 4 + floor(v * 4) * 0.5) % 1 < 0.015 then return C.line end
  return C.text
end

local function hedgeTex(u, v, n, near)
  local top = 0.4 - 0.05 * abs(sin(u * pi * 4))
  if v < top then return nil end
  if v > 0.92 then return C.text end
  if v > 0.88 then return C.hi end
  if near then
    local spot = hash(floor(u * 28), floor(v * 20), n)
    if spot > 90 then return C.red end
    if spot > 82 then return C.hi end
    if spot > 76 then return C.text end
    if spot < 26 then return C.hiTint end
  end
  return C.ok
end

-- ---- the swamp: reeds taller than you, with the sky through them, and huts of logs on the islands of the mud.
local function reedTex(u, v, n, near)
  local i = floor(u * 13)
  local r = (u * 13) % 1
  local tall = hash(i, n, 3) / 100
  local top = -0.26 + tall * 0.5
  if v > 0.92 then return C.blueTint end
  if r > 0.62 or v < top then return nil end
  if v < top + 0.09 and hash(i, n, 5) < 45 then return C.warn end
  if hash(i, n, 7) < 30 then return C.soft end
  return (i + n) % 3 == 0 and C.hiTint or C.ok
end

-- ---- the Verdant Sea: grass over your head, all leaning one way, and nothing to steer by but the sky.
local function grassTex(u, v, n, near)
  local x = u + (0.6 - v) * 0.1
  local i = floor(x * 19)
  local r = (x * 19) % 1
  local top = -0.22 + hash(i, n, 9) / 100 * 0.44
  if v < top then return nil end
  if v < 0.5 and r > 0.68 then return nil end
  if v < top + 0.09 and hash(i, n, 2) < 34 then return C.hi end
  if v > 0.7 then
    if r < 0.3 then return C.bg end
    return hash(i, n, 4) < 50 and C.hiTint or C.ok
  end
  local look = hash(i, n, 7)
  if look < 24 then return C.soft end
  if r < 0.2 then return C.hiTint end
  return C.ok
end

local function logTex(u, v, n, near)
  if v < 0 then
    if abs(u - 0.5) + (-v) * 1.1 > 0.56 then return nil end
    return (u * 13) % 1 < 0.2 and C.panel or C.hiTint
  end
  if n == 1 and abs(u - 0.5) < 0.16 and v > 0.3 and v < 0.6 then
    return abs(u - 0.5) < 0.12 and v > 0.34 and v < 0.56 and C.warn or C.bg
  end
  local band = (v * 6) % 1
  if band < 0.12 then return C.bg end
  if band < 0.34 then return C.warn end
  return (u * 3 + floor(v * 6) * 0.4) % 1 < 0.03 and C.bg or C.redTint
end

-- ---- the old Empire: mage towers snapped off by something, still lit from inside, purple through every crack.
local function ruinTex(u, v, n, near)
  local tall = n == 1 and 1.25 or 0.3
  local top = -tall + lump(u + n, 9) * tall * 0.9
  if v < top then return nil end
  if n == 2 and abs(u - 0.5 - sin(v * 13) * 0.08) < 0.11 * (1 - abs(v - 0.5)) then
    return abs(u - 0.5 - sin(v * 13) * 0.08) < 0.04 and C.text or C.accent
  end
  local band = (v * 5) % 1
  local win = (u * 3) % 1
  if win > 0.34 and win < 0.66 and band > 0.2 and band < 0.75 and (floor(v * 5) + floor(u * 3)) % 2 == 0 then
    return (band < 0.3 or win < 0.42 or win > 0.58) and C.bg or C.accent
  end
  if band < 0.08 then return C.bg end
  local crack = abs(sin(u * 23 + v * 9 + n)) * abs(sin(v * 17 - u * 5))
  if crack > 0.86 then return near and C.accent or C.blueTint end
  return (u * 4 + floor(v * 5) * 0.5) % 1 < 0.05 and C.bg or (hash(floor(u * 4), floor(v * 5), n) < 40 and C.panel or C.tie)
end

-- ---- a natural cave: cold rock, moss, and things that glow on stalks. Nothing like the warm, shored-up mine.
local function caveTex(u, v, n, near)
  if n == 1 then
    for _, m in ipairs({ { 0.24, 0.6, 0.16 }, { 0.64, 0.42, 0.2 }, { 0.86, 0.72, 0.11 } }) do
      local x, y = (u - m[1]) / m[3], (v - m[2]) / (m[3] * 0.8)
      if y < 0 and x * x + y * y < 1 then
        if near and hash(floor(u * 18), floor(v * 18), 2) > 74 then return C.text end
        return y > -0.3 and C.soft or C.info
      end
      if y >= 0 and abs(x) < 0.22 and v < 0.97 then return C.line end
    end
  end
  local drip = 0.1 + 0.16 * abs(sin(u * 19 + n * 3)) + 0.08 * abs(sin(u * 43))
  if v < drip and n ~= 1 then return (u * 7) % 1 < 0.5 and C.ok or C.hiTint end
  local moss = 0.72 + lump(u + n, 8) * 0.2 - 0.1
  if v > moss then
    if near and hash(floor(u * 20), floor(v * 16), n) > 80 then return C.soft end
    return v - moss < 0.05 and C.ok or C.hiTint
  end
  local seam = sin(v * 15 + sin(u * 7 + n) * 2 + n)
  if seam > 0.72 then return C.bg end
  if seam > 0.2 then return C.panel end
  if seam < -0.8 then return C.tie end
  return C.blueTint
end

-- ---- Strathe: the walls are spun. A web across every opening, sheets of silk, and what's been kept in it for later.
local function webTex(u, v, n, near)
  local x, y = u - 0.5, v - 0.5
  if n == 1 then
    local fold = sin(u * 30 + sin(v * 6) * 2.4)
    if fold > 0.55 then return C.text end
    if fold > -0.3 then return C.line end
    return C.tie
  end
  if n == 2 then
    local cx, cy = x / 0.22, (y - 0.04) / 0.36
    if cx * cx + cy * cy < 1 then
      if (v * 14 + sin(u * 11)) % 1 < 0.22 then return C.tie end
      return cx < 0.2 and C.text or C.line
    end
    if abs(x) < 0.015 and y < 0 then return C.text end
  end
  local r = sqrt(x * x + y * y)
  local a = atan2(y, x) / (2 * pi) + 0.5
  if (0.5 - abs((a * 12) % 1 - 0.5)) / 12 * 2 * pi * r < 0.014 then return C.text end
  local ring = (r * (9 + 2 * sin(a * pi * 24))) % 1
  if ring < 0.13 then return near and C.line or C.tie end
  return C.bg
end

-- ---- Crysathula: wet folds like the inside of a skull, and the green light comes up out of the grooves.
local function coralTex(u, v, n, near)
  if n == 1 then
    local x, y = (u - 0.5) / 0.28, (v - 0.46) / 0.34
    local d = x * x + y * y
    if d < 1 then
      if d < 0.22 then return C.text end
      if d < 0.62 then return C.soft end
      return C.ok
    end
  end
  -- one long fold that doubles back on itself, as they do
  local f = sin(u * 15 + 3.4 * sin(v * 6 + n) + 1.6 * sin(v * 15 + u * 4))
  if f > 0.82 then return near and C.text or C.line end
  if f > 0.1 then return C.line end
  if f > -0.45 then return C.tie end
  if f > -0.8 then return C.ok end
  return C.hiTint
end

-- ---- the Nightmare Vault: buildings like lanterns, hung in the dark, and chains as thick as a house.
local function chainAt(u, v, x, wide)
  local d = abs(u - x)
  if d > wide then return nil end
  local link = (v * 3.2) % 1
  if floor(v * 3.2) % 2 == 0 then
    if d < wide * 0.3 then return link < 0.5 and C.line or C.tie end
    return nil
  end
  if d > wide * 0.55 then return d > wide * 0.8 and C.tie or C.line end
  if link < 0.2 or link > 0.8 then return C.line end
  return nil
end

local function lanternTex(u, v, n, near)
  if v < 0 then
    local cap = abs(u - 0.5) + (-v) * 1.25
    if cap < 0.5 then return cap > 0.46 and C.warn or C.panel end
    return chainAt(u, v, 0.5, 0.05)
  end
  if v > 0.9 then
    return (v - 0.9) * 5 + abs(u - 0.5) > 0.5 and nil or C.panel
  end
  if v < 0.05 or v > 0.86 then return C.panel end
  local cell = (u * 3) % 1
  local level = (v * 3) % 1
  if cell < 0.13 or cell > 0.87 or level < 0.1 then return C.bg end
  if n == 2 then
    -- the lamp has gone out in most of them, and it isn't a good sign when one is still lit
    if floor(u * 3) ~= 1 or floor(v * 3) ~= 1 then return C.panel end
    return C.red
  end
  if near and abs(cell - 0.5) < 0.16 and abs(level - 0.55) < 0.2 then return C.text end
  if near and abs(cell - 0.5) < 0.28 and abs(level - 0.55) < 0.32 then return C.hi end
  return C.warn
end

local function chainsTex(u, v)
  return chainAt(u, v, 0.2, 0.09) or chainAt(u, v + 0.15, 0.5, 0.11) or chainAt(u, v + 0.3, 0.8, 0.09)
end

-- ---- the burnt town: frames and chimneys, no roofs, grey sky through all of it, and it's still warm.
local function ashTex(u, v, n, near)
  if n == 2 then
    if v > 0.1 + lump(u + 1, 13) * 0.2 then
      if near and hash(floor(u * 21), floor(v * 15), 4) > 93 then return C.warn end
      if near and hash(floor(u * 21), floor(v * 15), 4) > 89 then return C.red end
      return (u * 7 + v * 3) % 1 < 0.45 and C.bg or C.panel
    end
    return nil
  end
  if n == 1 and abs(u - 0.5) < 0.17 then
    if v < -0.55 then return nil end
    if (v * 8) % 1 < 0.14 then return C.panel end
    return (u * 5 + floor(v * 8) * 0.5) % 1 < 0.1 and C.panel or C.tie
  end
  if v < -0.02 + lump(u + n, 11) * 0.28 then return nil end
  local post = (u * 3 + 0.1) % 1 < 0.2
  local beam = abs(v - 0.46) < 0.05 or v < 0.1 + lump(u, 11) * 0.1
  local cross = abs(((u * 3 + 0.1) % 1) - (v * 2) % 1) < 0.08
  if post or beam or cross then
    if near and hash(floor(u * 18), floor(v * 18), 6) > 92 then return C.warn end
    return (u * 9) % 1 < 0.35 and C.panel or C.bg
  end
  if v > 0.72 and hash(floor(u * 9), 2, n) > 40 then return C.tie end
  return nil
end

-- ---- the dream: nothing here agrees with anything else. Walls lean, the lines don't meet, and something's looking.
local function dreamTex(u, v, n, near)
  if n == 1 then
    local lean = u - 0.5 - (v - 0.2) * 0.55
    if abs(lean) > 0.3 - v * 0.08 then return nil end
    if (v * 7 + lean * 3) % 1 < 0.14 then return C.soft end
    return lean < 0 and C.line or C.tie
  end
  if n == 2 then
    local x, y = (u - 0.5) / 0.4, (v - 0.46) / 0.2
    local lid = 1 - x * x
    if abs(y) < lid * 1.1 and abs(y) > lid * 0.86 then return C.soft end
    if abs(y) < lid * 0.86 then
      local d = x * x * 6 + y * y * 1.4
      if d < 0.12 then return C.bg end
      if d < 0.5 then return C.soft end
      return C.text
    end
  end
  if v < 0 then return nil end
  local x, y = u + sin(v * 4.3) * 0.2, v + sin(u * 3.1) * 0.22
  if (x * 4) % 1 < 0.08 or (y * 5 + x) % 1 < 0.08 then return C.soft end
  if (x * 8 + y) % 1 < 0.05 then return C.tie end
  return C.bg
end

-- ---- the great library: shelves to the ceiling, and no two books alike.
local BOOKS = { C.red, C.blue, C.ok, C.accent, C.warn, C.redTint, C.blueTint, C.tie, C.hi, C.line, C.info }

local function shelfTex(u, v, n, near)
  if u < 0.03 or u > 0.97 then return C.warn end
  local level = floor(v * 5)
  local shelf = (v * 5) % 1
  if shelf < 0.09 then return C.warn end
  if shelf < 0.13 then return C.redTint end
  if n == 1 and abs(u - 0.5) < 0.08 then
    -- a ladder on its rail
    if abs(u - 0.5) > 0.06 or (v * 11) % 1 < 0.2 then return C.hi end
  end
  local i = floor(u * 21)
  local look = hash(i, level, 3)
  local top = 0.14 + look % 5 * 0.06
  if look > 88 or shelf < top then return C.bg end
  if near and shelf > 0.5 and shelf < 0.56 then return C.hi end
  if (u * 21) % 1 < 0.13 then return C.bg end
  return BOOKS[look % #BOOKS + 1]
end

for i = 0, 2 do
  wallKind("bone" .. i, boneTex, { var = i, up = i == 1 and 5.2 or 2, haze = C.panel })
  wallKind("marble" .. i, marbleTex, { var = i, up = i == 1 and 1.9 or 1.3, steps = SUNLIT, haze = C.line,
    wood = { { C.warn, C.redTint, C.hi }, { C.warn, C.redTint, C.hi }, { C.warn, C.redTint, C.hi }, { C.warn, C.redTint, C.hi }, { C.redTint, C.bg, C.warn }, { C.redTint, C.bg, C.warn } } })
  wallKind("reed" .. i, reedTex, { var = i, up = 1.6, steps = SUNLIT, haze = C.tie })
  wallKind("grass" .. i, grassTex, { var = i, up = 1.5, steps = SUNLIT, haze = C.tie })
  wallKind("ruin" .. i, ruinTex, { var = i, up = i == 1 and 3.6 or 1.7, haze = C.blueTint })
  wallKind("cave" .. i, caveTex, { var = i })
  wallKind("web" .. i, webTex, { var = i })
  wallKind("coral" .. i, coralTex, { var = i })
  wallKind("lamp" .. i, lanternTex, { var = i, up = 2.1 })
  wallKind("ash" .. i, ashTex, { var = i, up = i == 1 and 2.2 or 1.6, haze = C.tie })
  wallKind("dream" .. i, dreamTex, { var = i, up = 1.6 })
  wallKind("shelf" .. i, shelfTex, { var = i })
end
wallKind("hedge0", hedgeTex, { steps = SUNLIT, haze = C.line })
wallKind("logs0", logTex, { up = 1.8, steps = SUNLIT, haze = C.tie })
wallKind("logs1", logTex, { up = 1.8, var = 1, steps = SUNLIT, haze = C.tie })
wallKind("chains", chainsTex, { up = 4 })

--- A tile to a kind by place, so a theme needs only say what its # and h are like. The pandemic wall is the same everywhere.
local function spread(x, y, base, odd, rare)
  local n = (x * 7 + y * 13) % 5
  if n == 0 then return rare end
  if (x + y) % 2 == 1 then return odd end
  return base
end

--- A theme from a rule that names the kind for a tile. Both ways of seeing a square agree.
local function ruled(theme)
  local kinds = theme.kinds
  theme.side = {}
  theme.pick = function(c, x, y)
    if c == "W" then return "great" end
    return kinds(c, x, y)
  end
  theme.sidePick = theme.pick
  return theme
end

--- The far skyline of a city or a dead forest, as a row of spikes.
local function skyline(list, base, ink, seed, tall)
  for x = 0, VIEW_W - 1, 3 do
    local high = round(hash(floor(x / 5), seed, 7) / 100 * tall * (0.4 + lump(x / 121 + seed, 13) * 0.6))
    add(list, x, base - high, 3, high, ink)
  end
end

--- A thing with a tall thin point, in the distance.
local function needle(list, x, base, tall, ink)
  for i = 0, tall - 1 do
    local half = floor(i / tall * 3)
    add(list, x - half, base - tall + i, half * 2 + 1, 1, ink)
  end
end

--- A building hung from the roof of the Vault's cavern, far away and still burning.
local function farLantern(list, x, y, size)
  add(list, x, 0, 1, y, C.panel)
  add(list, x - size, y, size * 2 + 1, size * 2, C.panel)
  add(list, x - size + 1, y + 1, size * 2 - 1, size * 2 - 2, size % 2 == 0 and C.warn or C.hi)
  add(list, x, y + 1, 1, size * 2 - 2, C.panel)
  add(list, x - size + 2, y + size * 2, size * 2 - 3, 1, C.panel)
  add(list, x, y + size * 2 + 1, 1, 3, C.panel)
end

--- Stalactites along the top of the view.
local function fangs(list, ink, step, long)
  for x = 0, VIEW_W - 1, step do
    local tall = 3 + hash(x, 3, 5) % long
    for i = 0, tall - 1 do
      local half = floor((1 - i / tall) * step / 2)
      add(list, x - half, i, half * 2 + 1, 1, ink)
    end
  end
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
  -- floor: two colours by distance, as in the town. cobble: paving stones to a square. planks: boards across, not a checker.
  -- warp: the checker bends. bands: rows of sky from the top, or roof for a ceiling. clouds: their two inks, or false.
  -- far: the row where the floor gives out. backdrop: what's painted behind everything. drop: what a ~ shows, see bakePit.
  city = ruled({
    wall = "bone0", sky = true, reachAll = true, cobble = 3,
    kinds = function(c, x, y) return c == "h" and "bone2" or spread(x, y, "bone0", "bone2", "bone1") end,
    floor = { { C.line, C.tie }, { C.line, C.tie }, { C.tie, C.panel }, { C.tie, C.panel }, { C.panel, C.panel } },
    bands = { { C.panel, 8 }, { C.redTint, 12 }, { C.red, 3 }, { C.redTint, 13 } }, clouds = { C.panel, C.bg }, far = C.panel,
    backdrop = function(list)
      skyline(list, 36, C.panel, 2, 12)
      for _, s in ipairs({ { 14, 24 }, { 40, 30 }, { 68, 22 }, { 93, 32 }, { 112, 20 } }) do needle(list, s[1], 36, s[2], C.tie) end
    end,
    drop = { bands = { C.redTint, C.bg, C.redTint, C.bg }, scale = 3, fleck = C.red, lip = C.tie },
  }),
  marble = ruled({
    wall = "marble0", sky = true, reachAll = true, cobble = 2,
    kinds = function(c, x, y) return c == "h" and "hedge0" or spread(x, y, "marble0", "marble2", "marble1") end,
    floor = { { C.text, C.line }, { C.text, C.line }, { C.line, C.text }, { C.line, C.tie }, { C.line, C.line } },
    bands = { { C.blue, 15 }, { C.info, 15 }, { C.text, 6 } }, clouds = { C.text, C.text }, far = C.line,
    backdrop = function(list)
      -- the Spear Citadel on every horizon, with its ribbons out to the other cities
      needle(list, 60, 36, 34, C.line)
      for i = 0, 58, 1 do
        local y = round(5 + i * 0.28 + sin(i * 0.22) * 1.6)
        add(list, 60 + i, y, 1, 1, C.red)
        add(list, 60 - i, y + 1, 1, 1, C.hi)
      end
      skyline(list, 36, C.ok, 3, 5)
    end,
    drop = { bands = { C.blue, C.blueTint, C.blue, C.info }, scale = 3, fleck = C.text, lip = C.text },
  }),
  swamp = ruled({
    wall = "reed0", sky = true, reachAll = true, cobble = 5, planks = true,
    kinds = function(c, x, y)
      if c == "h" then return "logs" .. (x + y) % 2 end
      return "reed" .. (x * 3 + y) % 3
    end,
    floor = { { C.redTint, C.bg }, { C.redTint, C.bg }, { C.redTint, C.bg }, { C.redTint, C.panel }, { C.panel, C.panel } },
    bands = { { C.panel, 8 }, { C.hiTint, 16 }, { C.tie, 12 } }, clouds = { C.hiTint, C.panel }, far = C.hiTint,
    backdrop = function(list)
      skyline(list, 36, C.hiTint, 4, 9)
      for _, x in ipairs({ 22, 71, 104 }) do needle(list, x, 36, 20, C.bg) end
    end,
    drop = { bands = { C.hiTint, C.blueTint, C.blueTint, C.bg }, scale = 3, fleck = C.soft, lip = C.redTint },
  }),
  grass = ruled({
    wall = "grass0", sky = true, reachAll = true, cobble = 2, warp = 1.2,
    kinds = function(c, x, y)
      if c == "h" then return "logs" .. (x + y) % 2 end
      return "grass" .. (x * 3 + y) % 3
    end,
    floor = { { C.hiTint, C.redTint }, { C.hiTint, C.redTint }, { C.hiTint, C.panel }, { C.panel, C.hiTint }, { C.hiTint, C.hiTint } },
    bands = { { C.blueTint, 12 }, { C.blue, 10 }, { C.info, 8 }, { C.line, 6 } }, clouds = { C.text, C.line }, far = C.hiTint,
    backdrop = function(list) skyline(list, 36, C.ok, 6, 4) end,
    drop = { bands = { C.hiTint, C.blueTint, C.blueTint, C.bg }, scale = 3, fleck = C.soft, lip = C.hiTint },
  }),
  ruin = ruled({
    wall = "ruin0", sky = true, reachAll = true, cobble = 2,
    kinds = function(c, x, y) return c == "h" and "ruin2" or spread(x, y, "ruin0", "ruin0", "ruin1") end,
    floor = { { C.tie, C.panel }, { C.panel, C.tie }, { C.panel, C.bg }, { C.panel, C.bg }, { C.bg, C.bg } },
    bands = { { C.bg, 10 }, { C.blueTint, 12 }, { C.accent, 6 }, { C.text, 1 }, { C.accent, 7 } }, clouds = false, far = C.accent,
    backdrop = function(list)
      for _, s in ipairs({ { 8, 20, 9 }, { 34, 27, 7 }, { 60, 16, 11 }, { 84, 30, 8 }, { 110, 22, 9 } }) do
        add(list, s[1] - floor(s[3] / 2), 36 - s[2], s[3], s[2], C.bg)
        for y = 36 - s[2] + 3, 34, 6 do add(list, s[1], y, 1, 2, C.info) end
        for i = 0, s[3] - 1 do add(list, s[1] - floor(s[3] / 2) + i, 36 - s[2] - hash(i, s[1], 1) % 4, 1, 4, C.bg) end
      end
    end,
    drop = { bands = { C.bg, C.blueTint, C.bg, C.bg }, scale = 2, fleck = C.accent, lip = C.tie },
  }),
  cave = ruled({
    wall = "cave0", cobble = 2, warp = 2.6,
    kinds = function(c, x, y) return spread(x, y, "cave0", "cave2", "cave1") end,
    floor = { { C.hiTint, C.panel }, { C.panel, C.hiTint }, { C.panel, C.hiTint }, { C.panel, C.bg }, { C.bg, C.bg } },
    roof = { { C.panel, C.bg }, { C.bg, C.panel }, { C.bg, C.blueTint }, { C.bg, C.bg }, { C.bg, C.bg } },
    backdrop = function(list) fangs(list, C.bg, 9, 9) end,
    drop = { bands = { C.bg, C.bg, C.blueTint, C.bg }, scale = 3, fleck = C.info, lip = C.tie },
  }),
  web = ruled({
    wall = "web0", cobble = 2,
    kinds = function(c, x, y) return spread(x, y, "web1", "web0", "web2") end,
    floor = { { C.line, C.tie }, { C.tie, C.panel }, { C.panel, C.tie }, { C.panel, C.bg }, { C.bg, C.bg } },
    roof = { { C.tie, C.bg }, { C.panel, C.bg }, { C.bg, C.panel }, { C.bg, C.bg }, { C.bg, C.bg } },
    backdrop = function(list)
      for i = 0, 7 do
        for y = 0, 26 do add(list, 60 + round((i - 3.5) * (4 + y * 1.5)), y, 1, 1, C.line) end
      end
    end,
    drop = { bands = { C.bg, C.bg, C.panel, C.bg }, scale = 2, fleck = C.line, lip = C.line },
    rail = { C.text, C.line },
  }),
  coral = ruled({
    wall = "coral0", cobble = 2, warp = 2.2,
    kinds = function(c, x, y) return spread(x, y, "coral0", "coral2", "coral1") end,
    floor = { { C.hiTint, C.bg }, { C.hiTint, C.bg }, { C.bg, C.hiTint }, { C.bg, C.hiTint }, { C.bg, C.bg } },
    roof = { { C.hiTint, C.bg }, { C.bg, C.hiTint }, { C.bg, C.hiTint }, { C.bg, C.bg }, { C.bg, C.bg } },
    backdrop = function(list)
      -- the bubble over the city, from underneath
      for i = 0, 120 do
        local d = (i - 60) / 60
        add(list, i, round(4 + d * d * 26), 1, 1, C.ok)
        add(list, i, round(2 + d * d * 20), 1, 1, C.hiTint)
      end
    end,
    drop = { bands = { C.hiTint, C.blueTint, C.bg, C.hiTint }, scale = 3, fleck = C.ok, lip = C.ok },
  }),
  chain = ruled({
    wall = "lamp0", reachAll = true, cobble = 4, planks = true,
    kinds = function(c, x, y)
      if c == "h" then return "chains" end
      return spread(x, y, "lamp0", "lamp0", "lamp2")
    end,
    floor = { { C.tie, C.bg }, { C.tie, C.bg }, { C.panel, C.bg }, { C.panel, C.bg }, { C.panel, C.bg } },
    roof = { { C.bg, C.bg }, { C.bg, C.bg }, { C.bg, C.bg }, { C.bg, C.bg }, { C.bg, C.bg } },
    far = C.tie,
    backdrop = function(list)
      for _, s in ipairs({ { 9, 16, 3 }, { 27, 4, 5 }, { 47, 20, 2 }, { 66, 9, 4 }, { 88, 18, 3 }, { 106, 3, 6 }, { 117, 24, 2 } }) do
        farLantern(list, s[1], s[2], s[3])
      end
    end,
    drop = { bands = { C.tie, C.line, C.tie, C.panel, C.tie, C.panel }, scale = 2, fleck = C.line, lip = C.bg },
    rail = { C.line, C.tie },
  }),
  ash = ruled({
    wall = "ash0", sky = true, reachAll = true, cobble = 2,
    kinds = function(c, x, y) return c == "h" and "ash2" or spread(x, y, "ash0", "ash2", "ash1") end,
    floor = { { C.tie, C.panel }, { C.panel, C.tie }, { C.tie, C.panel }, { C.panel, C.tie }, { C.tie, C.tie } },
    bands = { { C.panel, 7 }, { C.tie, 11 }, { C.line, 18 } }, clouds = { C.tie, C.panel }, far = C.tie,
    backdrop = function(list)
      skyline(list, 36, C.tie, 5, 7)
      for _, s in ipairs({ { 20, 3 }, { 96, 5 } }) do
        for y = 0, 34 do add(list, s[1] + round(sin(y * 0.3) * 3) + floor((36 - y) / 3), y, s[2] + floor((36 - y) / 6), 1, C.panel) end
      end
    end,
    drop = { bands = { C.panel, C.bg, C.bg, C.panel }, scale = 2, fleck = C.warn, lip = C.tie },
  }),
  dream = ruled({
    wall = "dream0", sky = true, reachAll = true, warp = 1.6,
    kinds = function(c, x, y) return c == "h" and "dream2" or spread(x, y, "dream0", "dream1", "dream2") end,
    floor = { { C.bg, C.panel }, { C.bg, C.panel }, { C.panel, C.bg }, { C.bg, C.tie }, { C.bg, C.soft } },
    bands = { { C.bg, 36 } }, clouds = false, far = C.bg,
    backdrop = function(list)
      for i = 0, 60 do
        local x, y = hash(i, 7, 3) * 1.21, hash(i * 3, 2, i) % 34
        add(list, floor(x), y, 1, 1, i % 3 == 0 and C.soft or C.tie)
      end
      -- a horizon that's been put back wrong
      for i = 0, 120, 6 do add(list, i, round(30 + sin(i * 0.09) * 5 + (i % 12) / 3), 6, 1, C.soft) end
      for i = 0, 11 do add(list, 88 - i * 2, 4 + i * 2, i * 4 + 1, 1, C.tie) end
    end,
    drop = { bands = { C.bg, C.bg, C.bg, C.panel }, scale = 2, fleck = C.soft, lip = C.soft },
  }),
  library = ruled({
    wall = "shelf0", cobble = 2,
    kinds = function(c, x, y) return spread(x, y, "shelf0", "shelf0", "shelf1") end,
    floor = { { C.redTint, C.panel }, { C.redTint, C.panel }, { C.redTint, C.panel }, { C.panel, C.redTint }, { C.bg, C.bg } },
    roof = { { C.redTint, C.bg }, { C.redTint, C.bg }, { C.bg, C.redTint }, { C.bg, C.bg }, { C.bg, C.bg } },
    backdrop = function(list)
      for x = 8, 112, 26 do add(list, x, 0, 8, 2, C.warn) end
    end,
    drop = { bands = { C.bg, C.bg, C.bg, C.bg }, scale = 2, fleck = C.tie, lip = C.warn },
  }),
}
M.THEMES = THEMES

local function themeOf(mapId)
  local map = world.map(mapId)
  return THEMES[map and map.theme] or THEMES.mine
end

--- The sky and the ground together, in runs along each row. parity flips as you step, which is what shows you moving.
local function bakeGround(theme, name, parity)
  local list = {}
  local paintFloor = theme.floor or THEME_GROUND[name] or THEME_GROUND.mine
  local paintRoof = theme.roof or MINE_ROOF
  local cobble = theme.cobble or COBBLES[name] or 1
  local warp, across = theme.warp or 0, theme.planks and 0 or 1
  for row = 0, VIEW_H - 1 do
    local below = row + 0.5 > CY
    local z = (TILE_H / 2) / abs(row + 0.5 - CY)
    local band = min(FARTHEST, max(1, floor(z)))
    local paint = below and paintFloor[band] or paintRoof[band]
    if not below and theme.sky then
      local upTo, ink = 0, C.line
      for _, part in ipairs(theme.bands or SKY) do
        upTo = upTo + part[2]
        ink = part[1]
        if row < upTo then break end
      end
      add(list, 0, row, VIEW_W, 1, ink)
    elseif z >= FARTHEST then
      add(list, 0, row, VIEW_W, 1, theme.far or (theme.sky and C.panel or C.bg))
    else
      local from = 0
      local inkOf = function(col)
        local lateral = (col + 0.5 - CX) * z / TILE_W
        if warp > 0 then lateral = lateral + sin(z * warp) * 0.7 end
        return paint[(floor(lateral * cobble + 0.5) * across + floor(z * cobble) + parity) % 2 + 1]
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
  if theme.sky and theme.clouds ~= false then
    local inks = theme.clouds or { C.tie, C.panel }
    for i, cloud in ipairs({ { 12, 5, 34, 2 }, { 58, 9, 40, 3 }, { 86, 3, 26, 2 }, { 24, 14, 46, 2 }, { 76, 19, 30, 2 } }) do
      local ink = i % 2 == 0 and inks[1] or inks[2]
      add(list, cloud[1], cloud[2], cloud[3], cloud[4], ink)
      add(list, cloud[1] + 6, cloud[2] - 1, cloud[3] - 14, 1, ink)
    end
  end
  if theme.backdrop then theme.backdrop(list) end
  return list
end

local PLAIN_DROP = { bands = { C.bg, C.bg, C.panel, C.bg }, scale = 2, fleck = C.tie, lip = C.tie }

--- A chain or a silk line along the edge of a drop, from z nearZ to farZ, a third of the way up to the height of a wall.
local function railAlong(list, edge, nearZ, farZ, rail)
  columns(edge, nearZ, farZ, function(col, top, bottom, u, shade)
    local tall = bottom - top
    local steps = DARKENS[shade]
    local y = bottom - round(tall * (0.34 - sin(u * pi) * 0.06))
    if u < 0.1 then add(list, col, y, 1, bottom - y, faded(rail[1], steps)) end
    add(list, col, y, 1, max(1, round(tall / 44)), faded(rail[col % 3 == 0 and 2 or 1], steps))
  end)
end

local function railAcross(list, x1, x2, z, rail)
  local half = TILE_H / 2 / z
  local tall = half * 2
  local steps = DARKENS[min(6, floor(z + 0.55))]
  local bottom = round(CY + half)
  for x = x1, x2 - 1 do
    local u = (x - x1) / max(x2 - x1, 1)
    local y = bottom - round(tall * (0.34 - sin(u * pi) * 0.06))
    add(list, x, y, 1, max(1, round(tall / 44)), faded(rail[x % 3 == 0 and 2 or 1], steps))
  end
  add(list, x1, bottom - round(tall * 0.34), 1, round(tall * 0.34), faded(rail[1], steps))
end

--- What's under a square of ~. Nothing stands there, so the floor of the square is simply painted over: bands that slide with the
-- distance, a few flecks of light on the water or in the mist, and a lip where the far bank drops away, which is what makes it
-- read as a drop and not a dark rug. rails are the edges with floor beside them: near, left, right.
local function bakePit(theme, row, l, bank, railNear, railLeft, railRight)
  local list = {}
  local drop = theme.drop or PLAIN_DROP
  local nearZ, farZ = max(row, 0.3), row + 1
  local y1 = round(CY + TILE_H / 2 / farZ)
  local y2 = min(VIEW_H, round(CY + TILE_H / 2 / nearZ))
  local lip = bank and max(1, round(TILE_H * 0.09 / farZ)) or 0
  local bands = drop.bands
  for y = y1, y2 - 1 do
    local z = (TILE_H / 2) / (y + 0.5 - CY)
    local x1 = round(CX + (l - 0.5) * TILE_W / z)
    local x2 = round(CX + (l + 0.5) * TILE_W / z)
    if y - y1 < lip then
      add(list, x1, y, x2 - x1, 1, (y - y1) * 2 < lip and drop.lip or C.bg)
    else
      add(list, x1, y, x2 - x1, 1, bands[floor(z * drop.scale) % #bands + 1])
      local dash = max(1, round(9 / z))
      for x = x1 + (y * 5) % 11 * dash, x2 - dash, 13 * dash do
        if hash(x, y, 4) < 45 then add(list, x, y, dash, 1, drop.fleck) end
      end
    end
  end
  local rail = theme.rail
  if rail then
    if railLeft then railAlong(list, l - 0.5, nearZ, farZ, rail) end
    if railRight then railAlong(list, l + 0.5, nearZ, farZ, rail) end
    if railNear and row >= 1 then
      railAcross(list, round(CX + (l - 0.5) * TILE_W / row), round(CX + (l + 0.5) * TILE_W / row), row, rail)
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
local function drawSprite(ox, oy, name, row, l, flash, foe)
  name = art.spriteName(name, foe)
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

local pits = {}

--- Is this square a floor you could stand on, seen from the edge of a drop? That's where a rail goes.
local function standable(s, row, l)
  local x, y = squareAt(s, row, l)
  local c = world.tileAt(s.map, x, y)
  return c ~= "~" and not WALLISH[c]
end

local function paintPit(ox, oy, s, theme, row, l)
  local fx, fy = squareAt(s, row + 1, l)
  local bank = world.tileAt(s.map, fx, fy) ~= "~"
  local near, left, right = standable(s, row - 1, l), standable(s, row, l - 1), standable(s, row, l + 1)
  local key = (theme.wall or "") .. ":" .. row .. ":" .. l .. (bank and "b" or "") .. (near and "n" or "") .. (left and "l" or "") .. (right and "r" or "")
  local list = pits[key]
  if not list then
    list = bakePit(theme, row, l, bank, near, left, right)
    pits[key] = list
  end
  blit(ox, oy, list)
end

local function paintSquare(ox, oy, s, theme, row, l, things)
  local x, y = squareAt(s, row, l)
  if world.tileAt(s.map, x, y) == "~" then
    paintPit(ox, oy, s, theme, row, l)
  elseif blocksEye(s, x, y) then
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
        drawSprite(ox, oy, one.sprite, row, l, one.foe and s.fx and (s.fx.flash or 0) > 0 and row == 1 and l == 0, one.foe)
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
    if passes(s, n) then put(n.x, n.y, { sprite = art.lookSprite(n.id) or (art.SPRITES[n.id] and n.id) or n.sprite }) end -- the party have sprites by id
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
