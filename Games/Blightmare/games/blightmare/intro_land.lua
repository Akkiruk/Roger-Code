-- games/blightmare/intro_land.lua
-- The opening's second movement: the map of Embia and its four kingdoms, the Empire in gold, the ward where the sickness
-- passes from sleeper to sleeper, the plague taking the Empire, and the wall. See intro.lua for what a picture file gives.
--
-- The map is the game's own: overworld.ROWS, one column a tile and two rows for every three tiles, so it keeps its true
-- shape on a wall whose cells are half as wide as they are tall. Everything about it that doesn't move is worked out once,
-- here, at load; a frame just picks a colour for each cell and fills the runs.

local ui = require("lib.arcade.ui")
local overworld = require("games.blightmare.overworld")

local C = ui.C
local floor, max, sin, sqrt, pi = math.floor, math.max, math.sin, math.sqrt, math.pi

local M = { LENGTH = {}, CUES = {} }

local SW = 121                       -- cells across the wall; a cell's index is row * SW + x
local MW, MH = overworld.W, overworld.H
local ROWS = 53                      -- 80 tiles in 53 rows: two rows for every three tiles
local OY = 5                         -- the map's top row; it runs to row 57, clear of the talk box at 64

--- A number from 0 to 99 that's always the same for the same pair.
local function hash(x, y)
  return ((x * 7919 + y * 104729 + x * y * 31 + 12345) % 1009) % 100
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

-- ---------------------------------------------------------------- the map, worked out once

--- Which land a tile lies in, the same lines overworld.lua draws (its landOf is local to it).
local function landOf(x, y)
  if y <= 13 and x <= 62 then return "thuluan" end
  if x <= 60 and (y >= 45 or (y == 44 and x < 20)) then return "empire" end
  if x <= 54 then return "sindal" end
  if y < 44 then return "plexios" end
  return "heart"
end

-- Sites shown as a town's light. Dungeons, the Abyss and Evrastin never show: the opening doesn't point at any of them.
local SHOWN = {}
for _, one in ipairs(overworld.SITES) do
  if (one.kind == "town" or one.kind == "city") and one.id ~= "evrastin" then SHOWN[one.y * 1000 + one.x] = one end
end

local function tileAt(x, y)
  local row = overworld.ROWS[y]
  if not row or x < 1 or x > MW then return "~" end
  local c = row:sub(x, x)
  if c == "O" and not SHOWN[y * 1000 + x] then c = "." end
  return c
end

-- What each cell shows: its tile, the land it's in, the tile it came from, whether a stretch of wall runs through it.
local CH, LAND, TX, TY, HASWALL = {}, {}, {}, {}, {}
local RANK = { O = 5, ["^"] = 3, ["="] = 2, B = 2 }

for r = 0, ROWS - 1 do
  local y1, y2 = floor(r * MH / ROWS) + 1, floor((r + 1) * MH / ROWS)
  for x = 1, MW do
    local i = r * SW + x
    local best, bestY, rank = nil, y1, -1
    for y = y1, y2 do
      local c = tileAt(x, y)
      if c == "W" then
        HASWALL[i] = y
        c = "."
      end
      local k = RANK[c] or 0
      if k > rank then best, bestY, rank = c, y, k end
    end
    CH[i], TX[i], TY[i] = best, x, bestY
    LAND[i] = best == "~" and "sea" or landOf(x, bestY)
  end
  CH[r * SW] = "~"
  LAND[r * SW] = "sea"
end

local function isLand(i) return CH[i] ~= nil and CH[i] ~= "~" end

-- The open sea, found by flooding in from the corner: lakes and rivers inland don't get the shallows' rim.
local OCEAN = {}
do
  local todo = { 0 }
  OCEAN[0] = true
  while #todo > 0 do
    local i = table.remove(todo)
    local r, x = floor(i / SW), i % SW
    local near = { x > 0 and i - 1, x < MW and i + 1, r > 0 and i - SW, r < ROWS - 1 and i + SW }
    for k = 1, 4 do
      local j = near[k]
      if j and not OCEAN[j] and CH[j] == "~" then
        OCEAN[j] = true
        todo[#todo + 1] = j
      end
    end
  end
end

-- The plain colour of each cell, in the house's map colours.
local BASE = {}
for r = 0, ROWS - 1 do
  for x = 0, MW do
    local i = r * SW + x
    local c, v = CH[i], hash(TX[i] or x, TY[i] or r)
    local ink
    if c == "~" then
      -- the shallows: open sea that touches land shows a lighter rim, so the coast reads
      local near = OCEAN[i] and ((x > 0 and isLand(i - 1)) or (x < MW and isLand(i + 1)) or (r > 0 and isLand(i - SW))
        or (r < ROWS - 1 and isLand(i + SW)))
      ink = near and C.blue or C.blueTint
    elseif c == "." then
      ink = v < 3 and C.ok or C.hiTint
    elseif c == '"' then
      ink = v < 10 and C.ok or C.hiTint
    elseif c == "T" then
      ink = v < 6 and C.soft or C.ok
    elseif c == "s" then
      ink = v < 30 and C.blueTint or C.panel
    elseif c == "^" then
      local above = TY[i] > 1 and tileAt(TX[i], TY[i] - 1) or "~"
      if v < 5 then ink = C.text elseif above ~= "^" or v < 12 then ink = C.line else ink = C.tie end
    elseif c == "=" or c == "B" then
      ink = C.redTint
    elseif c == "O" then
      ink = C.hi
    else
      ink = C.hiTint
    end
    BASE[i] = ink
  end
end

-- One step darker for every colour, for fading in and for dimming what the picture isn't about.
local DARK = {
  [C.text] = C.line, [C.line] = C.tie, [C.tie] = C.panel, [C.panel] = C.bg, [C.bg] = C.bg,
  [C.soft] = C.hiTint, [C.ok] = C.hiTint, [C.hiTint] = C.panel, [C.hi] = C.warn, [C.warn] = C.redTint,
  [C.redTint] = C.bg, [C.red] = C.redTint, [C.blue] = C.blueTint, [C.blueTint] = C.bg, [C.accent] = C.blueTint,
  [C.info] = C.blue,
}

local function darker(color, n)
  for _ = 1, n do color = DARK[color] end
  return color
end

local GDIST = {}                       -- each Empire cell's distance from the capital, filled in below

-- The Empire in its glory: gold, brightest round the capital and warming to amber toward its edges, the woods a shade deeper.
local function goldOf(i)
  local c, v, d = CH[i], hash(TX[i], TY[i]), GDIST[i] or 99
  if c == "O" then return C.text end
  if c == "=" or c == "B" then return C.hi end
  if c == "^" then return BASE[i] == C.tie and C.hiTint or (BASE[i] == C.text and C.hi or C.warn) end
  if c == "s" then return v < 50 and C.hiTint or C.warn end
  local ink
  d = d + (v % 5) - 2
  if d < 4 then
    ink = C.text
  elseif d < 11 then
    ink = C.hi
  elseif d < 19 then
    ink = (c == "T" and v < 70) and C.warn or C.hi
  elseif d < 30 then
    ink = (c == "T" and v < 50) and C.hiTint or C.warn
  else
    ink = (c == "T" or v < 40) and C.hiTint or C.warn
  end
  return ink
end

-- The Empire sick: dried blood, the roads running red like veins, the towns gone out.
local function sickOf(i)
  local c, v = CH[i], hash(TX[i], TY[i])
  if c == "T" then return v < 30 and C.red or C.redTint end
  if c == "^" then return BASE[i] == C.tie and C.panel or (BASE[i] == C.text and C.tie or C.redTint) end
  if c == "=" or c == "B" then return C.red end
  if c == "O" or c == "s" then return C.bg end
  if v > 92 then return C.bg end
  return v < 6 and C.red or C.redTint
end

-- Every land cell of the Empire, with how far it lies from where the sickness took hold. The place is never marked.
local EMPIRE = {}
local SICK_X, SICK_Y = 45, 60
local DIST = {}
local GOLD_X, GOLD_Y = 30, 57          -- Agoshull, the capital, where the gold blooms from
for r = 0, ROWS - 1 do
  for x = 1, MW do
    local i = r * SW + x
    if LAND[i] == "empire" then
      EMPIRE[i] = true
      local dx, dy = TX[i] - SICK_X, TY[i] - SICK_Y
      DIST[i] = sqrt(dx * dx + dy * dy) + (hash(x, r) % 3) * 0.7
      dx, dy = TX[i] - GOLD_X, TY[i] - GOLD_Y
      GDIST[i] = sqrt(dx * dx + dy * dy)
    end
  end
end

local HEART_LIT = { heart = true }

-- The open sea along the Empire's own shore, and the waters inside it: once it goes dark, these go with it.
local EMPIRE_SHORE = {}
for r = 0, ROWS - 1 do
  for x = 0, MW do
    local i = r * SW + x
    if CH[i] == "~" then
      local mine, other = false, false
      for _, j in ipairs({ i - 1, i + 1, i - SW, i + SW }) do
        if EMPIRE[j] then mine = true elseif isLand(j) then other = true end
      end
      if (mine and not other) or (not OCEAN[i] and landOf(x, TY[i]) == "empire") then EMPIRE_SHORE[i] = true end
    end
  end
end

local function sy(y) return OY + floor((y - 1) * ROWS / MH) end

--- Paint the map, a run of one colour at a time. ink(i) gives a cell's colour; the sea's colour is filled first and skipped.
--- A run with the same ends and colour as the one under it in the row above grows down into a block, one fill for both.
local function paintMap(L, ink, sea)
  ui.fill(0, 0, L.W, L.H, sea)
  local open = {}
  for r = 0, ROWS - 1 do
    local row, y = r * SW, OY + r
    local still = {}
    local run, from = nil, 0
    for x = 0, SW do
      local c = x < SW and (x <= MW and ink(row + x) or sea) or nil
      if c ~= run then
        if run and run ~= sea then
          local key = (run * 128 + from) * 128 + (x - from)
          local block = open[key]
          if block then
            block[4] = block[4] + 1
            open[key] = nil
          else
            block = { from, y, x - from, 1, run }
          end
          still[key] = block
        end
        run, from = c, x
      end
    end
    for _, block in pairs(open) do ui.fill(block[1], block[2], block[3], block[4], block[5]) end
    open = still
  end
  for _, block in pairs(open) do ui.fill(block[1], block[2], block[3], block[4], block[5]) end
end

-- ---------------------------------------------------------------- labels

local LABELS = {
  { lines = { "THE VEINS", "OF SINDAL" }, x = 27, y = 30, at = 8 },
  { lines = { "PLEXIOS" }, x = 89, y = 30, at = 10 },
  { lines = { "THE QYRRISSIAN", "EMPIRE" }, x = 29, y = 63, at = 12 },
  { lines = { "THE HEART" }, x = 86, y = 62, at = 14 },
  { lines = { "EMPYREAL", "MOUNTAINS" }, x = 59, y = 17, at = 16, quiet = true },
}

local function drawLabel(label, fg, edge, y)
  local w = 0
  for _, line in ipairs(label.lines) do w = max(w, #line) end
  local cx, top = label.x, sy(y or label.y)
  local left = cx - floor(w / 2) - 1
  ui.fill(left, top - 1, w + 2, #label.lines + 2, C.bg)
  if edge then
    ui.fill(left, top - 1, w + 2, 1, edge)
    ui.fill(left, top + #label.lines, w + 2, 1, edge)
  end
  for k, line in ipairs(label.lines) do ui.small(line, cx, top + k - 1, fg, C.bg, "center") end
end

-- ---------------------------------------------------------------- 1. embia

local FADE = 6

local function drawEmbia(L, t)
  local n = t >= FADE and 0 or clamp(math.ceil((FADE - t) * 4 / FADE), 0, 4)
  paintMap(L, function(i) return darker(BASE[i], n) end, darker(C.blueTint, n))
  for _, label in ipairs(LABELS) do
    if t >= label.at then
      local fresh = t < label.at + 2
      local fg = fresh and C.hi or (label.quiet and C.line or C.text)
      drawLabel(label, fg, fresh and C.hiTint or C.panel)
    end
  end
end

M.LENGTH.embia = 18
M.CUES.embia = { { 1, "intro_map_open" } }
for _, label in ipairs(LABELS) do M.CUES.embia[#M.CUES.embia + 1] = { label.at, "intro_label" } end

-- ---------------------------------------------------------------- 2. empire

-- Towers of the Empire that catch the light: the capital and a scatter of others. None of them is Evrastin.
local TOWERS = { { 30, 57 }, { 15, 50 }, { 22, 67 }, { 38, 50 }, { 36, 71 }, { 12, 61 }, { 52, 69 }, { 26, 48 } }

local function drawEmpire(L, t)
  local dim = t >= 1 and 1 or 0
  local bloom = t * 8                                 -- the gold spreads from the capital in a few ticks
  local band = (t - 6) * 2.5 % 80 - 15               -- a soft shimmer sweeping south-west to north-east
  paintMap(L, function(i)
    if EMPIRE[i] and GDIST[i] <= bloom then
      local ink = goldOf(i)
      if t >= 6 then
        local d = (TX[i] - TY[i] * 0.6) - band
        if d >= 0 and d < 2 then
          ink = (ink == C.warn or ink == C.hiTint) and C.hi or C.text
        elseif d >= -3 and d < 0 and ink == C.warn then
          ink = C.hi
        end
      end
      return ink
    end
    return darker(BASE[i], dim)
  end, darker(C.blueTint, dim))
  -- the towers: a pale stub with a light on top that flares in turn
  for k, tw in ipairs(TOWERS) do
    local x, y = tw[1], sy(tw[2])
    if sqrt((tw[1] - GOLD_X) ^ 2 + (tw[2] - GOLD_Y) ^ 2) <= bloom then
      ui.fill(x, y, 1, 1, C.redTint)
      local phase = (t + k * 5) % 14
      if t >= 3 and phase < 2 then
        -- the flare: a small white cross, a beat long
        ui.fill(x - 1, y - 1, 3, 1, C.text)
        ui.fill(x, y - 2, 1, 1, C.text)
      else
        ui.fill(x, y - 1, 1, 1, t >= 3 and C.text or C.line)
      end
    end
  end
  -- its name, moved south off the capital so the glow round it shows
  if t >= 3 then drawLabel(LABELS[3], C.hi, C.hiTint, 71) end
end

M.LENGTH.empire = true
M.CUES.empire = { { 1, "intro_empire_glow" } }

-- ---------------------------------------------------------------- 3. ward

local BAY = 24
local BEDS = 5
local CLOUD_EVERY = 6
local function cloudStart(b) return 1 + (b - 1) * CLOUD_EVERY end
local TURN = 29                      -- the sleeper on the middle bed starts to change
local GUTTER, OUT = 32, 37           -- the candle starts to fail, and goes out
local WARD_END = 42

local FLOOR = 55                     -- where the back wall meets the floor
local CANDLE_X, CANDLE_Y = 95, 45    -- the candle's foot, on its stand between the fourth and fifth beds

local function bedX(b) return (b - 1) * BAY + 3 end

local function drawHall(L, lit)
  ui.fill(0, 0, L.W, L.H, C.panel)
  -- the vault: dark above the cornice
  ui.fill(0, 0, L.W, 6, C.bg)
  ui.fill(0, 6, L.W, 1, C.tie)
  for b = 0, BEDS do
    local px = b * BAY
    -- a pillar with its edge caught by the moon
    ui.fill(px - 2, 6, 4, FLOOR - 6, C.tie)
    ui.fill(px - 2, 6, 1, FLOOR - 6, C.line)
    ui.fill(px - 3, 6, 6, 2, C.line)
    ui.fill(px - 3, FLOOR - 2, 6, 2, C.tie)
    -- the ribs of the vault spring from it
    ui.line(px, 5, px - 6, 0, C.tie)
    ui.line(px, 5, px + 6, 0, C.tie)
  end
  for b = 1, BEDS do
    local px = (b - 1) * BAY
    if b == 3 then
      -- the tall window, in a frame, with the moon in it
      ui.ellipse(px + 3, 7, 19, 14, C.tie)
      ui.fill(px + 3, 14, 19, 28, C.tie)
      ui.ellipse(px + 4, 8, 17, 12, C.blueTint)
      ui.fill(px + 4, 14, 17, 26, C.blueTint)
      ui.ellipse(px + 14, 10, 5, 4, C.line)
      ui.ellipse(px + 15, 10, 3, 3, C.text)
      ui.fill(px + 7, 18, 1, 1, C.line)
      ui.fill(px + 9, 29, 1, 1, C.line)
      ui.fill(px + 18, 26, 1, 1, C.line)
      ui.fill(px + 12, 8, 1, 32, C.tie)
      ui.fill(px + 4, 21, 17, 1, C.tie)
      ui.fill(px + 4, 31, 17, 1, C.tie)
      ui.fill(px + 2, 40, 21, 2, C.line)
    else
      -- a deep arched recess
      ui.ellipse(px + 5, 10, 15, 10, C.bg)
      ui.fill(px + 5, 15, 15, FLOOR - 15, C.bg)
    end
  end
  -- the floor, with the moon laid across it from the window
  ui.fill(0, FLOOR, L.W, L.H - FLOOR, C.bg)
  ui.fill(0, FLOOR, L.W, 1, C.tie)
  for y = FLOOR + 1, FLOOR + 12 do
    local k = y - FLOOR - 1
    ui.fill(50 - floor(k * 1.5), y, 19 + floor(k * 0.5), 1, k < 5 and C.tie or C.panel)
  end
  for _, y in ipairs({ 60, 66, 74 }) do ui.fill(0, y, L.W, 1, C.panel) end
  -- the candle's glow on the wall and the floor
  if lit > 0 then
    local w, h = floor(15 * lit), floor(9 * lit)
    if w > 2 then
      ui.ellipse(CANDLE_X - floor(w / 2), CANDLE_Y - 2 - floor(h / 2), w, h, C.hiTint)
      ui.ellipse(CANDLE_X - floor(w / 2), FLOOR + 2, w, 3, C.hiTint)
    end
  end
end

--- One bed, side on, an iron bedstead, with its sleeper's head on the left.
local function drawBed(b, sleeper)
  local x0 = bedX(b)
  -- the frame
  ui.fill(x0, 39, 2, 21, C.tie)
  ui.fill(x0, 38, 2, 1, C.line)
  ui.fill(x0 + 16, 44, 2, 16, C.tie)
  ui.fill(x0 + 16, 43, 2, 1, C.line)
  ui.fill(x0 + 2, 52, 14, 1, C.tie)
  ui.fill(x0 + 2, 49, 14, 3, C.line)
  -- the pillow, and the head on it
  ui.fill(x0 + 2, 45, 5, 4, C.text)
  ui.fill(x0 + 2, 48, 5, 1, C.line)
  if sleeper then
    ui.fill(x0 + 3, 43, 3, 3, C.line)
    ui.fill(x0 + 3, 43, 2, 1, C.tie)
    ui.fill(x0 + 3, 44, 1, 1, C.tie)
  end
  -- the blanket over a body: shoulder, hip, and down to the feet, hanging over the side
  ui.fill(x0 + 6, 44, 4, 1, C.blue)
  ui.fill(x0 + 6, 45, 4, 1, C.blueTint)
  ui.fill(x0 + 10, 45, 3, 1, C.blue)
  ui.fill(x0 + 13, 46, 3, 1, C.blue)
  ui.fill(x0 + 6, 46, 7, 1, C.blueTint)
  ui.fill(x0 + 6, 47, 10, 7, C.blueTint)
  ui.fill(x0 + 6, 45, 1, 9, C.line)
end

-- The lobes of a nightmare cloud: offset from its middle, and size.
local LOBES = {
  { -6, 0, 9, 5 }, { -1, -2, 11, 7 }, { 5, 0, 9, 5 }, { 1, 2, 13, 4 },
}

local function drawCloud(cx, cy, s, t, seed)
  if s <= 0 then return end
  for k, lobe in ipairs(LOBES) do
    local breathe = sin(t * 0.55 + seed + k * 1.7)
    local w = max(1, floor(lobe[3] * s + breathe * s + 0.5))
    local h = max(1, floor(lobe[4] * s + breathe * 0.5 * s + 0.5))
    ui.ellipse(cx + floor(lobe[1] * s) - floor(w / 2), cy + floor(lobe[2] * s) - floor(h / 2), w, h, C.redTint)
  end
  -- ragged underneath: wisps hanging off it
  if s >= 0.5 then
    for k = -2, 2 do
      local len = 1 + (hash(k + 3, floor(seed * 10) + floor(t / 2)) % 3)
      ui.fill(cx + k * 3 - 1, cy + floor(3 * s), 1, len, C.redTint)
    end
  end
  if s >= 0.4 then
    -- the violet inside it, two wisps turning slowly round each other
    local a = t * 0.4 + seed
    local w1, w2 = max(1, floor(7 * s + 0.5)), max(1, floor(5 * s + 0.5))
    ui.ellipse(cx - 2 + floor(sin(a) * 2.5 + 0.5) - floor(w1 / 2), cy - 4, w1, 3, C.accent)
    ui.ellipse(cx + 1 - floor(sin(a) * 2.5 + 0.5) - floor(w2 / 2), cy - 1, w2, 3, C.accent)
    -- and a darker hollow in its heart
    if s >= 1 then ui.fill(cx - 1 + floor(sin(a * 0.7) + 0.5), cy - 2, 2, 1, C.redTint) end
  end
end

--- A thread of the cloud hanging down to the sleeper's head.
local function drawThread(cx, fromY, toY, t, seed)
  for y = fromY, toY do
    local x = cx + floor(sin((y + t) * 0.9 + seed) * 1.2 + 0.5)
    ui.fill(x, y, 1, 1, (y + t) % 3 == 0 and C.accent or C.redTint)
  end
end

--- The sleeper on the middle bed, turned into something else: sitting up, then not a person at all. A silhouette, black.
local function drawTurned(t)
  local f = clamp((t - TURN) / 6, 0, 1)
  if f <= 0 then return end
  local x0 = bedX(3)
  local ink = C.bg
  -- the torso rises out of the blanket
  local rise = floor(clamp(f * 2, 0, 1) * 11)
  local top = 45 - rise
  ui.fill(x0 + 2, top, 6, 48 - top, ink)
  ui.fill(x0 + 1, top + 2, 1, max(0, 46 - top - 2), ink)
  local hy = top - 4
  if f < 0.5 then
    ui.ellipse(x0 + 3, hy, 4, 4, ink)
    return
  end
  local g = (f - 0.5) * 2
  -- hunched, the head too big and pushed forward, horns, one long arm reaching along the bed
  ui.fill(x0, top + 1, 3, 4, ink)
  ui.ellipse(x0 + 3, hy - 1, 6, 6, ink)
  local horn = floor(g * 5)
  ui.line(x0 + 4, hy, x0 + 2, hy - horn, ink)
  ui.line(x0 + 7, hy, x0 + 9, hy - horn - 1, ink)
  local reach = floor(g * 9)
  ui.line(x0 + 7, top + 3, x0 + 8 + reach, top + 6, ink)
  ui.line(x0 + 7, top + 4, x0 + 8 + reach, top + 7, ink)
  if g >= 1 then
    ui.line(x0 + 8 + reach, top + 6, x0 + 10 + reach, top + 4, ink)
    ui.line(x0 + 8 + reach, top + 7, x0 + 11 + reach, top + 7, ink)
    ui.line(x0 + 8 + reach, top + 7, x0 + 10 + reach, top + 9, ink)
  end
  if g >= 0.6 then
    ui.fill(x0 + 4, hy + 2, 1, 1, C.red)
    ui.fill(x0 + 7, hy + 2, 1, 1, C.red)
  end
end

local function drawCandle(t)
  -- the stand
  ui.fill(CANDLE_X - 3, 48, 7, 1, C.redTint)
  ui.fill(CANDLE_X - 2, 49, 1, 10, C.redTint)
  ui.fill(CANDLE_X + 2, 49, 1, 10, C.redTint)
  ui.fill(CANDLE_X - 2, 54, 5, 1, C.redTint)
  ui.fill(CANDLE_X - 1, 47, 3, 1, C.tie)
  ui.fill(CANDLE_X, CANDLE_Y, 1, 2, C.text)
  if t < OUT then
    local flicker = hash(t, 7) % 3 - 1
    local failing = t >= GUTTER
    if failing and (t - GUTTER) % 2 == 1 then
      ui.fill(CANDLE_X, CANDLE_Y - 1, 1, 1, C.redTint)
    else
      ui.fill(CANDLE_X, CANDLE_Y - 1, 1, 1, failing and C.warn or C.hi)
      if not failing then ui.fill(CANDLE_X + (flicker > 0 and 1 or 0), CANDLE_Y - 2, 1, 1, C.warn) end
    end
  elseif t < OUT + 4 then
    -- a curl of smoke going up, and then nothing
    for k = 0, t - OUT do
      local y = CANDLE_Y - 2 - k * 2
      ui.fill(CANDLE_X + floor(sin(k * 1.3) + 0.5), y, 1, 1, k == t - OUT and C.tie or C.line)
    end
  end
end

local function drawWard(L, t)
  local lit = 1
  if t >= OUT then
    lit = 0
  elseif t >= GUTTER then
    lit = ((t - GUTTER) % 2 == 1 and 0.45 or 0.75) * (1 - (t - GUTTER) / (OUT - GUTTER + 1))
  else
    lit = 0.92 + (hash(t, 3) % 3) * 0.04
  end
  drawHall(L, lit)
  for b = 1, BEDS do drawBed(b, not (b == 3 and t > TURN)) end
  if lit > 0.5 then
    -- the candle catches the iron nearest it
    ui.fill(bedX(4) + 16, 43, 2, 1, C.warn)
    ui.fill(bedX(4) + 17, 44, 1, 6, C.hiTint)
    ui.fill(bedX(5), 38, 2, 1, C.warn)
    ui.fill(bedX(5), 39, 1, 8, C.hiTint)
  end
  drawCandle(t)
  -- the nightmare: it settles over each bed in turn, and creeps along the rafters to the next
  for b = 1, BEDS do
    local start = cloudStart(b)
    if t >= start then
      local cx, cy = bedX(b) + 6, 31
      local s = clamp((t - start + 1) / 5, 0, 1)
      if b == 3 and t > TURN then s = s * 1.12 end
      if s >= 0.6 then drawThread(bedX(b) + 4, cy + 4, 42, t, b) end
      drawCloud(cx, cy, s, t, b * 2.3)
      if b < BEDS then
        local f = (t - (start + 2)) / (CLOUD_EVERY - 1)
        if f > 0 and f < 1 then
          local nx = bedX(b + 1) + 6
          local px = floor(cx + (nx - cx) * f + 0.5)
          local py = floor(cy - 6 - 8 * sin(pi * f) + 0.5)
          ui.line(cx + 4, cy - 4, px, py, C.redTint)
          ui.ellipse(px - 3, py - 1, 7, 3, C.redTint)
          ui.ellipse(px - 1, py - 1, 3, 2, C.accent)
        end
      end
    end
  end
  drawTurned(t)
end

M.LENGTH.ward = WARD_END
M.CUES.ward = { { 1, "intro_nightmare" }, { cloudStart(4), "intro_nightmare" }, { OUT, "intro_candle_out" } }

-- ---------------------------------------------------------------- 4. plague

local SPREAD = 2.4                   -- tiles a tick
local PULSE = 14                     -- ticks between the slow beats once it has all of the Empire

local function drawPlague(L, t)
  local reach = t * SPREAD
  local beat = t > 18 and ((t - 18) % PULSE) * 3.2 or -99
  paintMap(L, function(i)
    if EMPIRE[i] then
      local d = DIST[i]
      if d <= reach then
        if reach - d < 2.5 then return hash(TX[i], TY[i] + t) < 30 and C.accent or C.red end
        if d <= beat and beat - d < 2.5 then return CH[i] == "~" and C.redTint or C.red end
        if CH[i] == "~" then return C.redTint end
        return sickOf(i)
      end
      return goldOf(i) == C.text and C.line or darker(goldOf(i), 1)
    end
    return darker(BASE[i], 1)
  end, darker(C.blueTint, 1))
end

M.LENGTH.plague = true
M.CUES.plague = {}

-- ---------------------------------------------------------------- 5. wall

-- The wall's cells in the order it goes up: the north course west to east, then down the Heart's side to the sea.
local WALL = {}
for r = 0, ROWS - 1 do
  for x = 1, MW do
    local i = r * SW + x
    if HASWALL[i] then WALL[#WALL + 1] = { x = x, r = r, ty = HASWALL[i], north = HASWALL[i] <= 44 } end
  end
end
table.sort(WALL, function(a, b)
  if a.north ~= b.north then return a.north end
  if a.north then return a.x < b.x end
  if a.r ~= b.r then return a.r < b.r end
  return a.x < b.x
end)

local BUILD_FROM, BUILD_TO = 3, 27   -- the ticks the wall goes up over
local DARKEN = 3                     -- ticks for the Empire to go out after the last course
local WALL_END = BUILD_TO + DARKEN + 2

local function builtBy(t)
  return floor(clamp((t - BUILD_FROM) / (BUILD_TO - BUILD_FROM), 0, 1) * #WALL + 0.5)
end

-- The survivors, out of the Empire and over the line, each a tick or more before the wall reaches their row (the last two
-- only just). Their tiles, where they set off, where they come to rest and when they start.
local REFUGEES = {
  { 44, 63, 68, 61, 2 }, { 40, 70, 67, 68, 3 }, { 47, 57, 66, 56, 5 }, { 38, 66, 70, 64, 6 },
  { 45, 68, 69, 70, 9 }, { 50, 64, 65, 65, 14 }, { 49, 73, 66, 72, 15 },
}
local WALK = 1.6                     -- tiles a tick

local function refugeeAt(one, t)
  local x0, y0, x1, y1, start = one[1], one[2], one[3], one[4], one[5]
  if t < start then return nil end
  local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  local f = clamp((t - start) * WALK / len, 0, 1)
  return floor(x0 + (x1 - x0) * f + 0.5), floor(y0 + (y1 - y0) * f + 0.5), f
end

local function drawWall(L, t)
  local built = builtBy(t)
  local fade = t >= BUILD_TO and clamp(t - BUILD_TO, 0, DARKEN) or 0
  paintMap(L, function(i)
    if EMPIRE[i] then
      return darker(sickOf(i), fade)
    end
    if EMPIRE_SHORE[i] then return darker(BASE[i], 1 + fade) end
    if HEART_LIT[LAND[i]] then return BASE[i] end
    return darker(BASE[i], 1)
  end, darker(C.blueTint, 1))
  -- the survivors, a pale light each, leaving a short trail, and settling as small warm lights in the Heart
  for _, one in ipairs(REFUGEES) do
    local x, y, f = refugeeAt(one, t)
    if x then
      if f < 1 then
        local px, py = refugeeAt(one, t - 1)
        if px then ui.fill(px, sy(py), 1, 1, C.tie) end
      end
      ui.fill(x, sy(y), 1, 1, f < 1 and C.text or C.hi)
    end
  end
  -- the wall, course by course, the newest stones still bright
  for k = 1, built do
    local cell = WALL[k]
    local y = OY + cell.r
    local fresh = built - k < 3 and t < BUILD_TO + 1
    if cell.north then
      ui.fill(cell.x, y, 1, 1, fresh and C.hi or C.text)
      ui.fill(cell.x, y + 1, 1, 1, C.line)
    else
      ui.fill(cell.x, y, 1, 1, fresh and C.hi or C.text)
      ui.fill(cell.x + 1, y, 1, 1, C.tie)
    end
  end
end

M.LENGTH.wall = WALL_END
M.CUES.wall = { { BUILD_FROM, "intro_wall_course" }, { 4, "intro_refugees" } }
for tick = BUILD_FROM + 4, BUILD_TO - 1, 4 do M.CUES.wall[#M.CUES.wall + 1] = { tick, "intro_wall_course" } end
M.CUES.wall[#M.CUES.wall + 1] = { BUILD_TO, "intro_wall_done" }
table.sort(M.CUES.wall, function(a, b) return a[1] < b[1] end)
-- ---------------------------------------------------------------- the pictures

local DRAW = { embia = drawEmbia, empire = drawEmpire, ward = drawWard, plague = drawPlague, wall = drawWall }

function M.draw(L, pic, t)
  local draw = DRAW[pic]
  t = floor(max(0, tonumber(t) or 0))
  local length = M.LENGTH[pic]
  if type(length) == "number" and t > length then t = length end
  if draw then
    draw(L, t)
  else
    ui.fill(0, 0, L.W, L.H, C.bg)
  end
end

return M
