-- games/blightmare/intro_town.lua
-- One night in Scythebreak, the opening's last five pictures: dusk and the lamps, the Dream Book, lights out over the roofs,
-- the knock, and every window dreaming but one. See intro.lua for what a picture file gives.
--
-- Each picture is painted into a grid of colours first, its still parts once at load and the moving parts on top every
-- tick, and the grid goes to the wall as rectangles of one colour, so a frame costs a few hundred fills at most. Everything
-- that moves is worked out from t alone, with fixed hashes for the scatter, so any frame can be drawn on its own.

local ui = require("lib.arcade.ui")

local C = ui.C
local floor, ceil, max, min, abs, sqrt, sin = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt, math.sin

local M = { LENGTH = {}, CUES = {} }

local W, H = 121, 81
local N = W * H

-- ---------------------------------------------------------------- helpers

--- A fixed scatter in 0..1 from up to three whole numbers.
local function hash(a, b, c)
  local n = (a * 7919 + (b or 0) * 104729 + (c or 0) * 1299709 + 4111) % 1000003
  n = (n * n + 12345) % 1000003
  n = (n * 6007 + 7) % 1000003
  return n / 1000003
end

local function round(v) return floor(v + 0.5) end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

--- How far between a and b tick t is, 0 before a and 1 after b.
local function ramp(t, a, b) return clamp01((t - a) / (b - a)) end

local function rect(g, x, y, w, h, c)
  local x1, y1, x2, y2 = max(0, x), max(0, y), min(W - 1, x + w - 1), min(H - 1, y + h - 1)
  for yy = y1, y2 do
    local o = yy * W + 1
    for xx = x1, x2 do g[o + xx] = c end
  end
end

local function dot(g, x, y, c)
  if x >= 0 and x < W and y >= 0 and y < H then g[y * W + x + 1] = c end
end

local function get(g, x, y)
  if x >= 0 and x < W and y >= 0 and y < H then return g[y * W + x + 1] end
end

--- Every cell whose centre lies in the ellipse. Centre and radii are in cells, and a cell spans x to x + 1.
local function ellipse(g, cx, cy, rx, ry, c)
  for yy = max(0, floor(cy - ry)), min(H - 1, ceil(cy + ry)) do
    local dy = (yy + 0.5 - cy) / ry
    if dy >= -1 and dy <= 1 then
      local half = rx * sqrt(1 - dy * dy)
      local x1, x2 = max(0, ceil(cx - half - 0.5)), min(W - 1, floor(cx + half - 0.5))
      local o = yy * W + 1
      for xx = x1, x2 do g[o + xx] = c end
    end
  end
end

--- A filled polygon from corner points { x1, y1, x2, y2, ... }.
local function poly(g, pts, c)
  local n = #pts / 2
  local top, bottom = math.huge, -math.huge
  for i = 1, n do top, bottom = min(top, pts[i * 2]), max(bottom, pts[i * 2]) end
  for yy = max(0, floor(top)), min(H - 1, ceil(bottom)) do
    local v = yy + 0.5
    local xs = {}
    for i = 1, n do
      local j = i % n + 1
      local y1, y2 = pts[i * 2], pts[j * 2]
      if (y1 <= v) ~= (y2 <= v) then
        local x1, x2 = pts[i * 2 - 1], pts[j * 2 - 1]
        xs[#xs + 1] = x1 + (v - y1) / (y2 - y1) * (x2 - x1)
      end
    end
    table.sort(xs)
    local o = yy * W + 1
    for k = 1, #xs - 1, 2 do
      for xx = max(0, ceil(xs[k] - 0.5)), min(W - 1, floor(xs[k + 1] - 0.5)) do g[o + xx] = c end
    end
  end
end

local function line(g, x1, y1, x2, y2, c)
  x1, y1, x2, y2 = round(x1), round(y1), round(x2), round(y2)
  local steps = max(abs(x2 - x1), abs(y2 - y1))
  if steps == 0 then return dot(g, x1, y1, c) end
  for s = 0, steps do dot(g, round(x1 + (x2 - x1) * s / steps), round(y1 + (y2 - y1) * s / steps), c) end
end

--- Light falling on what's already there: inside the ellipse each colour becomes its lit colour from map. soft: the outer
-- part of it is a checker, so the light fades out rather than stopping at a line (it costs a fill a cell there).
local function light(g, cx, cy, rx, ry, map, soft)
  for yy = max(0, floor(cy - ry)), min(H - 1, ceil(cy + ry)) do
    local dy = (yy + 0.5 - cy) / ry
    if dy >= -1 and dy <= 1 then
      local half = rx * sqrt(1 - dy * dy)
      local o = yy * W + 1
      for xx = max(0, ceil(cx - half - 0.5)), min(W - 1, floor(cx + half - 0.5)) do
        local dx = (xx + 0.5 - cx) / rx
        if not soft or dx * dx + dy * dy < 0.6 or (xx + yy) % 2 == 0 then
          local v = g[o + xx]
          g[o + xx] = map[v] or v
        end
      end
    end
  end
end

--- A dark edge round whatever was drawn into the sparse layer o, so a figure stands clear of what's behind it.
local function outlined(o, edge)
  local add = {}
  for i in pairs(o) do
    local x = (i - 1) % W
    if x > 0 and not o[i - 1] then add[i - 1] = true end
    if x < W - 1 and not o[i + 1] then add[i + 1] = true end
    if i - W >= 1 and not o[i - W] then add[i - W] = true end
    if i + W <= N and not o[i + W] then add[i + W] = true end
  end
  for i in pairs(add) do o[i] = edge end
  return o
end

--- A sparse layer laid on a grid.
local function stamp(g, o)
  for i, c in pairs(o) do g[i] = c end
end

local work = {}

--- The grid to the wall, as few rectangles as it will go into: a run that's the same as the row above's grows down.
local function emit(g)
  local fill = ui.fill
  -- the commonest colour goes down first over everything, and then its runs needn't be drawn at all
  local count, under, most = {}, nil, 0
  for i = 1, N, 3 do
    local c = g[i]
    local k = (count[c] or 0) + 1
    count[c] = k
    if k > most then under, most = c, k end
  end
  fill(0, 0, W, H, under)
  local open = {}
  for y = 0, H - 1 do
    local o = y * W
    local nextOpen = {}
    local x = 0
    while x < W do
      local c = g[o + x + 1]
      local s = x
      while x + 1 < W and g[o + x + 2] == c do x = x + 1 end
      local len = x - s + 1
      local key = (s * 128 + len) * 65536 + c
      local r = open[key]
      if r then
        open[key] = nil
        r[4] = r[4] + 1
      else
        r = { s, y, len, 1, c }
      end
      nextOpen[key] = r
      x = x + 1
    end
    for _, r in pairs(open) do if r[5] ~= under then fill(r[1], r[2], r[3], r[4], r[5]) end end
    open = nextOpen
  end
  for _, r in pairs(open) do if r[5] ~= under then fill(r[1], r[2], r[3], r[4], r[5]) end end
end

--- A sparse layer straight to the wall, row by row, for what has to sit on top of small text.
local function emitLayer(o)
  local rows = {}
  for i in pairs(o) do
    local y = floor((i - 1) / W)
    rows[y] = true
  end
  for y in pairs(rows) do
    local base = y * W + 1
    local x = 0
    while x < W do
      local c = o[base + x]
      if c then
        local s = x
        while x + 1 < W and o[base + x + 1] == c do x = x + 1 end
        ui.fill(s, y, x - s + 1, 1, c)
      end
      x = x + 1
    end
  end
end

local function copyInto(dst, src)
  for i = 1, N do dst[i] = src[i] end
  return dst
end

local function newGrid(c)
  local g = {}
  for i = 1, N do g[i] = c end
  return g
end

-- ---------------------------------------------------------------- dreams in windows

-- What a dream looks like through a window at night: a colour that slowly becomes the next, and its tint on the wall round it.
local DREAM = {
  { C.accent, C.blueTint }, { C.blue, C.blueTint }, { C.info, C.blueTint }, { C.soft, C.hiTint },
  { C.hi, C.hiTint }, { C.warn, C.redTint }, { C.red, C.redTint },
}

--- A window's dream at tick t: its colour, the next one it's turning into, how far it's got, and its tint.
local function dreamAt(t, phase, step)
  local u = t / step + phase
  local i = floor(u) % #DREAM + 1
  local j = i % #DREAM + 1
  return DREAM[i][1], DREAM[j][1], u - floor(u), DREAM[i][2]
end

--- A window glowing with a dream: the inside x, y, w by h shifts colour, and the wall right round the frame takes its tint.
local function dreamWindow(g, x, y, w, h, t, phase, step, glowOn)
  local core, nextCore, f, tint = dreamAt(t, phase, step)
  if glowOn == "frame" then
    rect(g, x - 1, y - 1, w + 2, h + 2, tint)
  elseif glowOn then
    for xx = x, x + w - 1 do
      dot(g, xx, y - 2, tint)
      dot(g, xx, y + h + 1, tint)
    end
    for yy = y, y + h - 1 do
      dot(g, x - 2, yy, tint)
      dot(g, x + w + 1, yy, tint)
    end
  end
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      -- the next colour comes in from one corner, cell by cell, so the change is a drift and not a blink
      local edge = ((xx - x) + (yy - y)) / (w + h)
      dot(g, xx, yy, (f > 0.55 and edge < (f - 0.55) * 3) and nextCore or core)
    end
  end
end

--- A window gone grey: the Blightmare, grey with lime that never sits still.
local function greyWindow(g, x, y, w, h, t, seed, glowOn)
  if glowOn then
    for xx = x, x + w - 1 do
      dot(g, xx, y - 2, C.tie)
      dot(g, xx, y + h + 1, C.tie)
    end
    for yy = y, y + h - 1 do
      dot(g, x - 2, yy, C.tie)
      dot(g, x + w + 1, yy, C.tie)
    end
  end
  rect(g, x, y, w, h, C.line)
  local beat = floor(t / 2)
  for k = 1, 2 do
    local fx = x + floor(hash(seed, beat, k) * w)
    local fy = y + floor(hash(seed, k, beat) * h)
    dot(g, fx, fy, C.soft)
  end
  dot(g, x + floor(hash(seed, beat, 9) * w), y + floor(hash(seed, 9, beat) * h), C.tie)
end

-- ---------------------------------------------------------------- 1. dusk: the street, the wall and the lamps

local DUSK = {}
DUSK.LAMPS = { 15, 41, 67, 93 } -- the post's column
DUSK.LIT = { 7, 16, 25, 34 } -- the tick each one catches
-- where Wick's body is at each tick: walking in, a stop at each lamp to reach up, and on along the street
DUSK.WALK = { { 0, -23 }, { 6, 3 }, { 9, 3 }, { 15, 29 }, { 18, 29 }, { 24, 55 }, { 27, 55 }, { 33, 81 }, { 36, 81 }, { 40, 98 } }

-- the wall in perspective: its courses run to a point far off to the left, so it goes up past the top of the picture
local VPX, VPY = -60, 50
local function wallY(x, yRight) return VPY + (yRight - VPY) * (x - VPX) / (W - VPX) end

local SKY = -1 -- a cell of sky in the base grid, coloured as the dusk goes on

-- the bands of the sunset, top down, and the row each one ends on; their edges ripple a little, like thin cloud
local DUSK_BANDS = { { 4, C.blueTint }, { 11, C.accent }, { 17, C.red }, { 24, C.warn }, { 99, C.hi } }
local ripple = {}
for x = 0, W - 1 do ripple[x] = round(sin(x * 0.21) * 0.7 + sin(x * 0.07 + 1) * 0.6) end

local function duskSky(x, y, t)
  local y2 = y - floor(t * 3 / 40) + ripple[x] -- the dark comes down from the top as the lamps are lit
  for k, band in ipairs(DUSK_BANDS) do
    if y2 <= band[1] then
      if k == 1 and hash(x, y, 3) < 0.03 * clamp01(t / 20) + 0.004 then return C.line end -- the first stars
      return band[2]
    end
  end
  return C.hi
end

-- the six houses: left edge, width, eaves row, ridge row, plaster, and whether the gable faces the street
local DUSK_HOUSES = {
  { 0, 19, 42, 33, "hiTint", true },
  { 19, 22, 40, 34, "redTint", false },
  { 41, 18, 43, 31, "hiTint", true },
  { 59, 24, 41, 35, "panel", false },
  { 83, 19, 42, 31, "redTint", true },
  { 102, 19, 40, 33, "hiTint", false },
}

local function buildDusk()
  local g = newGrid(C.panel)
  -- sky everywhere above the wall's top edge
  for x = 0, W - 1 do
    local top = wallY(x, -6)
    for y = 0, H - 1 do
      if y + 0.5 < top then g[y * W + x + 1] = SKY end
    end
  end
  -- the wall's face, grey blocks, the courses meeting far off to the left
  for x = 0, W - 1 do
    local top = wallY(x, -6)
    for y = max(0, ceil(top - 0.5)), 57 do g[y * W + x + 1] = C.tie end
  end
  local courses = { -6, 3, 12, 21, 30, 39, 48 }
  for k = 2, #courses do
    for x = 0, W - 1 do dot(g, x, round(wallY(x, courses[k]) - 0.5), C.panel) end
  end
  for k = 1, #courses - 1 do
    -- joints closer together the further off they are, every other course halfway along
    for j = 0, 9 do
      local u = j + (k % 2 == 0 and 0.5 or 0)
      local x = round(VPX + (W - VPX) * 0.8 ^ u)
      if x >= 0 and x < W then
        for y = round(wallY(x, courses[k])), round(wallY(x, courses[k + 1]) - 1) do dot(g, x, y, C.panel) end
      end
    end
  end
  -- the lit top edge, then the slits the watch looks out of
  for x = 0, W - 1 do dot(g, x, ceil(wallY(x, -6) - 0.5), C.line) end
  for _, s in ipairs({ { 104, 12 }, { 76, 19 }, { 51, 26 } }) do
    rect(g, s[1], s[2], 1, 2, C.bg)
    dot(g, s[1], s[2] + 1, C.warn)
  end
  -- clouds across the sunset, dark against it
  for _, cl in ipairs({ { 2, 15, 22 }, { 9, 16, 12 }, { 28, 9, 14 }, { 33, 10, 9 }, { 0, 22, 9 }, { 14, 24, 13 } }) do
    for x = cl[1], cl[1] + cl[3] - 1 do
      if get(g, x, cl[2]) == SKY then dot(g, x, cl[2], C.redTint) end
    end
  end
  -- the houses
  for n, h in ipairs(DUSK_HOUSES) do
    local x, w, eave, ridge, plaster, gable = h[1], h[2], h[3], h[4], C[h[5]], h[6]
    rect(g, x, eave, w, 58 - eave, plaster)
    -- a chimney on some, before the roof so the roof sits in front of its foot
    if n % 2 == 0 then
      rect(g, x + w - 6, ridge - 4, 3, 6, C.panel)
      rect(g, x + w - 7, ridge - 4, 5, 1, C.bg)
    end
    local roof = C.bg
    if gable then
      poly(g, { x - 1, eave + 1, x + w / 2, ridge, x + w + 1, eave + 1 }, roof)
      -- the gable's own wall inside the roof's edge, with a little window up in it
      poly(g, { x + 2, eave + 1, x + w / 2, ridge + 3, x + w - 2, eave + 1 }, plaster)
      rect(g, floor(x + w / 2) - 1, eave - 3, 2, 2, C.bg)
      -- the west slope catches the sunset
      line(g, x - 1, eave, x + w / 2 - 1, ridge, C.warn)
    else
      poly(g, { x - 1, eave + 1, x + 3, ridge, x + w - 3, ridge, x + w + 1, eave + 1 }, roof)
      line(g, x - 1, eave, x + 2, ridge + 1, C.warn)
      line(g, x + 3, ridge, x + w - 4, ridge, C.redTint)
    end
    -- timbers: the beams under the eaves and at the floor, the posts, and a brace
    rect(g, x, eave + 1, w, 1, C.bg)
    rect(g, x, 49, w, 1, C.bg)
    rect(g, x, eave + 1, 1, 58 - eave, C.bg)
    rect(g, x + w - 1, eave + 1, 1, 58 - eave, C.bg)
    rect(g, x + floor(w / 2), eave + 1, 1, 8 - (eave - 41), C.bg)
    line(g, x + 1, 48, x + floor(w / 2) - 1, eave + 2, C.bg)
    -- the upstairs windows, warm where someone's home
    for k, wx in ipairs({ x + 3, x + w - 7 }) do
      local lit = hash(n, k, 1) < 0.6
      rect(g, wx - 1, 43, 6, 5, C.bg)
      rect(g, wx, 44, 4, 3, lit and C.hi or C.panel)
      rect(g, wx + 2, 44, 1, 3, C.bg)
      if lit then rect(g, wx, 46, 2, 1, C.warn) end
    end
    -- downstairs: a door and a window
    local door = x + (n % 2 == 0 and w - 8 or 3)
    rect(g, door - 1, 50, 6, 8, C.bg)
    rect(g, door, 51, 4, 7, (n % 3 == 0) and C.blueTint or C.redTint)
    dot(g, door + 3, 54, C.hi)
    local win = (n % 2 == 0) and x + 3 or x + w - 8
    rect(g, win - 1, 51, 6, 4, C.bg)
    rect(g, win, 52, 4, 2, hash(n, 7, 2) < 0.5 and C.warn or C.panel)
  end
  -- the street: a kerb, cobbles, and everything below it under the talk box
  rect(g, 0, 58, W, 1, C.tie)
  rect(g, 0, 59, W, H - 59, C.panel)
  for y = 60, 63 do
    for x = (y % 2) * 3, W - 1, 6 do
      if hash(x, y, 5) < 0.5 then rect(g, x, y, 2, 1, C.tie) end
    end
  end
  return g
end

-- light from a lamp: a haze that warms whatever's dark, a bright ring close in, and a pool on the cobbles
local LAMP_HAZE = { [C.bg] = C.redTint, [C.panel] = C.redTint, [C.tie] = C.redTint, [C.blueTint] = C.redTint, [C.hiTint] = C.warn, [C.redTint] = C.warn }
local LAMP_RING = { [C.bg] = C.warn, [C.panel] = C.warn, [C.tie] = C.warn, [C.blueTint] = C.warn, [C.redTint] = C.warn, [C.hiTint] = C.warn, [C.warn] = C.hi }
local LAMP_POOL = { [C.panel] = C.hiTint, [C.tie] = C.warn }

--- A lamp post on the kerb, its head up among the eaves. lit: 0 dark, 1 just caught (a flare), 2 burning.
local function drawLamp(g, lx, lit)
  if lit > 0 then
    -- the glow first, so the iron sits on top of it: a warm haze, then a bright ring right round the glass
    local s = lit == 1 and 1.4 or 1
    light(g, lx + 0.5, 37.5, 8 * s, 5.5 * s, LAMP_HAZE, true)
    light(g, lx + 0.5, 37.5, 3.6 * s, 2.6 * s, LAMP_RING)
    light(g, lx + 0.5, 61, 7, 2.5, LAMP_POOL)
  end
  rect(g, lx, 40, 1, 19, C.bg)
  rect(g, lx - 1, 58, 3, 2, C.bg)
  dot(g, lx, 34, C.bg)
  rect(g, lx - 1, 35, 3, 1, C.bg)
  rect(g, lx - 2, 36, 5, 1, C.bg)
  rect(g, lx - 2, 37, 1, 2, C.bg)
  rect(g, lx + 2, 37, 1, 2, C.bg)
  rect(g, lx - 1, 39, 3, 1, C.bg)
  if lit == 0 then
    rect(g, lx - 1, 37, 3, 2, C.panel)
  else
    rect(g, lx - 1, 37, 3, 2, C.hi)
    dot(g, lx, 37, C.text)
    if lit == 1 then dot(g, lx, 38, C.text) end
  end
end

local function wickAt(t)
  local ks = DUSK.WALK
  if t <= ks[1][1] then return ks[1][2], false end
  for k = 2, #ks do
    local a, b = ks[k - 1], ks[k]
    if t <= b[1] then
      local x = a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
      return round(x), b[2] ~= a[2]
    end
  end
  return ks[#ks][2], false
end

--- Wick and his pole, facing right, his body's left column at bx.
local function drawWick(g, bx, walking, reaching, t)
  local o = {}
  local function put(x, y, c)
    if x >= 0 and x < W and y >= 0 and y < H then o[y * W + x + 1] = c end
  end
  local function block(x, y, w, h, c)
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do put(xx, yy, c) end end
  end
  block(bx + 1, 46, 3, 1, C.tie) -- cap, its peak forward
  block(bx, 47, 6, 1, C.tie)
  put(bx, 48, C.line) -- grey hair, a warm face, grey whiskers
  block(bx + 1, 48, 3, 1, C.warn)
  put(bx + 3, 48, C.bg)
  put(bx, 49, C.line)
  block(bx + 1, 49, 2, 1, C.warn)
  block(bx + 3, 49, 2, 1, C.line)
  put(bx + 2, 50, C.line)
  block(bx, 51, 4, 1, C.tie) -- collar
  block(bx, 52, 4, 4, C.blueTint) -- coat, long, flaring as he walks
  block(bx - 1, 56, 6, 2, C.blueTint)
  put(bx - 1, 52, C.blueTint)
  local stride = walking and floor(t) % 2 == 0
  if stride then
    block(bx - 1, 58, 1, 3, C.bg)
    block(bx + 4, 58, 1, 3, C.bg)
    put(bx - 2, 60, C.bg)
    put(bx + 5, 60, C.bg)
  else
    block(bx, 58, 1, 3, C.bg)
    block(bx + 3, 58, 1, 3, C.bg)
    put(bx + 4, 60, C.bg)
  end
  -- the arm out front, and the long pole with the little flame at its tip
  local hx, hy = bx + 4, reaching and 52 or 54
  block(bx + 4, 52, 1, hy - 52, C.blueTint)
  put(hx, hy, C.warn)
  local tx, ty = bx + 15, 41
  if reaching then tx, ty = bx + 12, 39 end
  local steps = max(abs(tx - hx), abs(ty - hy))
  for s = 1, steps - 1 do put(round(hx + (tx - hx) * s / steps), round(hy + (ty - hy) * s / steps), C.line) end
  outlined(o, C.bg)
  put(tx, ty, C.hi)
  put(tx, ty - 1, C.warn)
  stamp(g, o)
end

local duskBase

local function drawDusk(t)
  duskBase = duskBase or buildDusk()
  local g = work
  for i = 1, N do
    local v = duskBase[i]
    if v == SKY then
      local x = (i - 1) % W
      v = duskSky(x, (i - 1 - x) / W, t)
    end
    g[i] = v
  end
  local reaching = false
  for k, lx in ipairs(DUSK.LAMPS) do
    local age = t - DUSK.LIT[k]
    drawLamp(g, lx, age < 0 and 0 or (age == 0 and 1 or 2))
    if age >= -1 and age <= 1 then reaching = true end
  end
  local bx, walking = wickAt(t)
  drawWick(g, bx, walking, reaching, t)
  emit(g)
end

M.LENGTH.dusk = 40
M.CUES.dusk = { { 1, "intro_dusk" } }
for _, lit in ipairs(DUSK.LIT) do M.CUES.dusk[#M.CUES.dusk + 1] = { lit, "intro_lamp" } end

-- ---------------------------------------------------------------- 2. book: the Dream Book, and the candle that leans

local BOOK = {
  -- the morning's two writers: what they write, where, and when their hand comes and goes
  { text = "MILLER .. bread, still warm", x = 65, y = 44, enter = 2, start = 5, leave = 20, sleeve = C.hiTint, cuff = C.redTint },
  { text = "COOPER .. nothing", x = 65, y = 47, enter = 22, start = 25, sleeve = C.blueTint, cuff = C.tie },
}
local BOOK_PER_TICK = 2
local BOOK_OLD = {
  { "HENWIFE .. the sea, but warm", 44 },
  { "SEXTON .. a stair with no top", 47 },
  { "HANLEY T. .. flying, nearly", 50 },
  { "BAKER .. all my teeth", 53 },
}
-- the lie: the flame starts to lean as "nothing" goes down, and the cleric turns to look after it's leaned
local LIE_AT = BOOK[2].start + 5 -- "COOPER .. " is ten letters, at two a tick
local LEAN_DONE = LIE_AT + 9
local TURN_AT, TURN_DONE = LEAN_DONE - 2, LEAN_DONE + 4

local ARCH_L, ARCH_R, ARCH_TOP, ARCH_BOT = 25, 95, 3, 35
local CLERIC_X = 58

local function inArch(x, y)
  if x < ARCH_L or x > ARCH_R or y > ARCH_BOT then return false end
  if y >= 11 then return true end
  local dx = (x + 0.5 - (ARCH_L + ARCH_R + 1) / 2) / ((ARCH_R - ARCH_L + 1) / 2)
  local dy = (y + 0.5 - 11) / (11 - ARCH_TOP)
  return dx * dx + dy * dy <= 1
end

local function buildBook()
  local g = newGrid(C.line)
  -- pale stone in the morning, blocks and mortar
  for y = 0, 35 do
    if y % 5 == 4 then
      rect(g, 0, y, W, 1, C.tie)
    else
      local off = (floor(y / 5) % 2) * 6
      for x = off, W - 1, 12 do dot(g, x, y, C.tie) end
    end
  end
  -- the arch: a deep stone reveal, then the dark cell with the archive's shelves behind
  for y = 0, 35 do
    for x = 0, W - 1 do
      if inArch(x, y) then dot(g, x, y, C.panel) end
    end
  end
  for y = 0, 35 do
    for x = 0, W - 1 do
      if get(g, x, y) == C.panel and not inArch(x - 2, y) then dot(g, x, y, C.tie) end
      if get(g, x, y) == C.panel and not inArch(x, y - 1) then dot(g, x, y, C.tie) end
    end
  end
  -- shelves of old ledgers, every spine a year of somebody's nights
  local SPINES = { C.redTint, C.blueTint, C.hiTint, C.tie, C.redTint, C.bg, C.blueTint, C.hiTint }
  for _, shelf in ipairs({ 12, 22, 32 }) do
    local x = ARCH_L + 3
    local k = 0
    while x < ARCH_R - 2 do
      k = k + 1
      local w = hash(shelf, k, 1) < 0.7 and 1 or 2
      local tall = 4 + floor(hash(shelf, k, 2) * 4)
      local c = SPINES[floor(hash(shelf, k, 3) * #SPINES) + 1]
      for xx = x, x + w - 1 do
        for yy = shelf - tall, shelf - 1 do
          if inArch(xx, yy) and get(g, xx, yy) == C.panel then dot(g, xx, yy, c) end
        end
      end
      x = x + w + (hash(shelf, k, 4) < 0.25 and 1 or 0)
    end
    for x = ARCH_L, ARCH_R do
      if inArch(x, shelf) and get(g, x, shelf) == C.panel then dot(g, x, shelf, C.redTint) end
    end
  end
  -- the stone sill in front of the bars
  rect(g, 0, 36, W, 1, C.text)
  rect(g, 0, 37, W, 1, C.tie)
  -- the counter, dark wood
  rect(g, 0, 38, W, H - 38, C.redTint)
  for y = 40, 63, 3 do
    for x = (y * 7) % 11, W - 1, 13 do rect(g, x, y, 4 + (x + y) % 5, 1, C.bg) end
  end
  -- the Book: a navy cover, the pages, and the shade either side of the spine
  rect(g, 17, 39, 87, 23, C.blueTint)
  rect(g, 19, 40, 41, 20, C.text)
  rect(g, 61, 40, 41, 20, C.text)
  rect(g, 19, 59, 41, 1, C.line)
  rect(g, 61, 59, 41, 1, C.line)
  rect(g, 58, 40, 2, 20, C.line)
  rect(g, 61, 40, 1, 20, C.line)
  rect(g, 60, 40, 1, 21, C.tie)
  -- the inkwell on the left
  ellipse(g, 9, 47, 4, 2.5, C.bg)
  rect(g, 7, 42, 4, 4, C.bg)
  rect(g, 8, 43, 2, 2, C.blueTint)
  dot(g, 7, 42, C.line)
  return g
end

-- the candle on the counter to the right of the Book, its wick at (CANDLE_X, CANDLE_TOP - 1)
local CANDLE_X, CANDLE_TOP = 111, 50

local function drawCandle(g)
  ellipse(g, CANDLE_X + 0.5, 58, 6, 1.6, C.warn)
  ellipse(g, CANDLE_X + 0.5, 57.6, 4.5, 1, C.hiTint)
  rect(g, CANDLE_X - 1, CANDLE_TOP, 3, 8, C.text)
  rect(g, CANDLE_X + 1, CANDLE_TOP, 1, 8, C.line)
  rect(g, CANDLE_X - 1, CANDLE_TOP + 2, 1, 2, C.line) -- a run of wax
  dot(g, CANDLE_X, CANDLE_TOP - 1, C.bg)
end

--- The cleric behind the bars: a black hood edged in violet, a pale jaw, eyes shut. turn moves the face toward the book's left.
local function drawCleric(g, turn)
  local cx = CLERIC_X - round(turn) -- she leans toward the Book's left, where the writing is
  local o = {}
  -- robe and shoulders, then the hood over them, pointed at the crown
  poly(o, { CLERIC_X - 17, 36, CLERIC_X - 8, 25, CLERIC_X + 8, 25, CLERIC_X + 17, 36 }, C.bg)
  ellipse(o, cx + 0.5, 16, 10, 10.5, C.bg)
  poly(o, { cx - 4, 8, cx + 0.5 + turn, 2, cx + 5, 8 }, C.bg)
  outlined(o, C.accent)
  -- the robe's violet edges
  for y = 27, 36 do
    dot(o, CLERIC_X - floor((y - 27) * 0.6), y, C.accent)
    dot(o, CLERIC_X + 1 + floor((y - 27) * 0.6), y, C.accent)
  end
  for i, c in pairs(o) do
    local x = (i - 1) % W
    if inArch(x, (i - 1 - x) / W) then g[i] = c end
  end
  -- the face, deep in the hood: the brow in shadow, the rest pale
  ellipse(g, cx + 0.5, 19, 5, 6.5, C.panel)
  for y = 18, 25 do
    for x = cx - 5, cx + 6 do
      if get(g, x, y) == C.panel then dot(g, x, y, C.line) end
    end
  end
  if turn < 0.5 then
    -- eyes shut, two short dark lines, and a mouth that has never once smiled
    rect(g, cx - 3, 19, 2, 1, C.tie)
    rect(g, cx + 2, 19, 2, 1, C.tie)
  else
    -- open, white, and looking hard to the left
    rect(g, cx - 3, 19, 2, 1, C.text)
    rect(g, cx + 2, 19, 2, 1, C.text)
    dot(g, cx - 3, 19, C.bg)
    dot(g, cx + 2, 19, C.bg)
    rect(g, cx - 3, 18, 2, 1, C.tie)
    rect(g, cx + 2, 18, 2, 1, C.tie)
  end
  dot(g, cx, 21, C.tie)
  rect(g, cx - 1, 23, 3, 1, C.tie)
end

--- The iron grille over the arch.
local function drawBars(g)
  for x = ARCH_L + 3, ARCH_R - 1, 12 do
    for y = ARCH_TOP, ARCH_BOT do
      if inArch(x, y) then
        dot(g, x, y, C.bg)
        if inArch(x - 1, y) then dot(g, x - 1, y, C.tie) end
      end
    end
  end
  for _, y in ipairs({ 13, 30 }) do
    for x = ARCH_L, ARCH_R do
      if inArch(x, y) then dot(g, x, y, C.bg) end
    end
  end
end

-- the candle's light on the dark wood round it: warm, then cold once it has leaned
local WARM = { [C.redTint] = C.hiTint, [C.bg] = C.hiTint, [C.blueTint] = C.hiTint }
local COLD = { [C.redTint] = C.blueTint, [C.bg] = C.blueTint, [C.hiTint] = C.blueTint, [C.warn] = C.blue }

--- The flame on its wick. lean 0 stands straight up; at 1 it lies hard over to the right. cold 0 is yellow, 1 is blue.
local function drawFlame(g, t, lean, cold)
  local cx, base = CANDLE_X, CANDLE_TOP - 2
  -- a living flame's tip shivers
  local waver = hash(7, floor(t), 1) < 0.4 and 1 or 0
  -- from the wick up: how wide, and how much of the middle is bright, and whether that's white hot
  local rows = { { 3, 1 }, { 5, 3, true }, { 5, 3, true }, { 3, 1, true }, { 3, 1 }, { 1, 0 }, { 1, 0 } }
  local outer = cold > 0.5 and C.blue or C.warn
  local core = cold > 0.5 and C.info or C.hi
  local hot = cold > 0.75 and C.info or C.text
  local px, py
  for k, r in ipairs(rows) do
    local up = k - 1
    -- leaning, it bends: the root stays on the wick and the rest is pushed over, more the higher it is
    local x = cx + round(lean * up * up * 0.22)
    local y = base - up + round(lean * up * 0.4)
    if k >= 6 and lean < 0.5 then x = x + (k == 7 and waver or 0) end
    local w, inner = r[1], r[2]
    if lean > 0.5 and k >= 2 then w, inner = min(w, 3), min(inner, 1) end
    for i = 0, w - 1 do
      local d = abs(i - floor(w / 2))
      local c = outer
      if d * 2 < inner then c = (r[3] and d == 0) and hot or core end
      if k == 7 then c = outer end
      dot(g, x - floor(w / 2) + i, y, c)
    end
    -- laid over, the rows slide apart: join each to the one before so it stays one flame
    if px then
      for xx = px + 1, x - 1 do dot(g, xx, py, outer) dot(g, xx, y, outer) end
    end
    px, py = x, y
  end
end

local bookBase

local function drawBook(t)
  bookBase = bookBase or buildBook()
  local g = copyInto(work, bookBase)
  local lean = ramp(t, LIE_AT, LEAN_DONE)
  lean = lean * lean * (3 - 2 * lean)
  local cold = ramp(t, LIE_AT + 2, LEAN_DONE)
  drawCleric(g, ramp(t, TURN_AT, TURN_DONE))
  drawBars(g)
  -- the candle's glow on the wood round it, and the candle over that
  local gx, gy = CANDLE_X + 0.5 + lean * 3, CANDLE_TOP - 3
  if cold > 0.5 then
    light(g, gx, gy, 12, 7, COLD, true)
  else
    light(g, gx, gy, 7, 5, WARM, true)
  end
  drawCandle(g)
  drawFlame(g, t, lean, cold)
  emit(g)

  -- the old entries, faded, and today's heading
  for _, e in ipairs(BOOK_OLD) do ui.small(e[1], 22, e[2], C.tie, C.text) end
  ui.small("this morning", 65, 41, C.line, C.text)

  -- the writing, and the hand doing it, on top of everything
  local hand = {}
  for k, wr in ipairs(BOOK) do
    local n = max(0, min(#wr.text, (t - wr.start) * BOOK_PER_TICK))
    if t >= wr.start then n = max(n, 0) end
    if n > 0 then ui.small(wr.text:sub(1, n), wr.x, wr.y, C.bg, C.text) end
    local finish = wr.start + ceil(#wr.text / BOOK_PER_TICK)
    local leave = wr.leave or math.huge
    if t >= wr.enter and t < leave + 3 then
      -- the pen's point: in from the bottom left, along the line as it writes, and away again
      local px, py = wr.x + n, wr.y
      if t < wr.start then
        local p = ramp(t, wr.enter, wr.start)
        px, py = round(wr.x - 34 * (1 - p)), round(wr.y + 26 * (1 - p))
      elseif t > leave then
        local p = ramp(t, leave, leave + 3)
        px, py = round(px - 34 * p), round(py + 26 * p)
      elseif t < finish then
        py = py + (t % 2) -- the scratch of it
      elseif k == 2 and t >= LEAN_DONE then
        px = px + 1 -- and the liar's hand stops dead where it was
      end
      local function put(x, y, c)
        if x >= 0 and x < W and y >= 0 and y < 64 then hand[y * W + x + 1] = c end
      end
      -- the quill, leaning back over the hand
      for s = 1, 6 do put(px + floor(s / 2), py - s, s >= 3 and C.text or C.line) end
      put(px + 3, py - 5, C.line)
      put(px + 2, py - 4, C.text)
      put(px, py, C.bg)
      -- the hand round it, then the cuff and sleeve going back down to the corner
      local o = {}
      local function blk(x, y, w, h, c)
        for yy = y, y + h - 1 do for xx = x, x + w - 1 do
          if xx >= 0 and xx < W and yy >= 0 and yy < 64 then o[yy * W + xx + 1] = c end
        end end
      end
      blk(px, py + 1, 5, 2, C.warn)
      blk(px - 1, py + 2, 1, 1, C.warn)
      blk(px + 1, py + 3, 5, 1, C.warn)
      blk(px + 1, py + 4, 6, 2, wr.cuff)
      for yy = py + 6, 63 do
        local d = yy - (py + 6)
        blk(px + 1 - floor(d * 0.8), yy, 8, 1, wr.sleeve)
      end
      outlined(o, C.bg)
      for i, c in pairs(o) do if not hand[i] then hand[i] = c end end
    end
  end
  emitLayer(hand)
end

M.LENGTH.book = TURN_DONE + 8
M.CUES.book = { { 1, "intro_book" } }

-- ---------------------------------------------------------------- 3. night: the windows go out, and the dreams come on

-- the houses in the middle distance: left edge, width, eaves, ridge
local NIGHT_HOUSES = {
  { 13, 18, 38, 30 }, { 32, 18, 37, 31 }, { 51, 16, 39, 32 }, { 68, 20, 38, 30 }, { 89, 18, 37, 31 }, { 108, 13, 39, 32 },
}
-- the windows that matter: inside x, y, w, h, when the lamp goes out, when the dream starts, its phase, grey or not
local NIGHT_WINDOWS = {
  { 18, 42, 4, 3, 10, 22, 0.0, grey = true }, -- the first house by the wall: this is where it starts
  { 39, 41, 4, 3, 14, 28, 3.3 },
  { 56, 42, 4, 3, 4, 20, 1.6 },
  { 74, 41, 4, 3, 18, 34, 5.1 },
  { 96, 41, 4, 3, 6, 24, 2.4 },
  { 112, 42, 4, 3, 16, 32, 4.2 },
  { 30, 55, 5, 3, 8, 26, 6.0 },
  { 86, 53, 5, 3, 12, 30, 0.8 },
}
local SPREAD_FROM, SPREAD_TO = 36, 44 -- the grey creeps from the first window to the second
local NIGHT_STEP = 7 -- ticks a dream spends on each colour

local function buildNight()
  local g = newGrid(C.bg)
  -- sky: black overhead, navy haze down toward the roofs
  for x = 0, W - 1 do
    local edge = 22 + round(sin(x * 0.13) * 1.2 + sin(x * 0.31 + 2) * 0.6)
    rect(g, x, edge, 1, 31 - edge, C.blueTint)
    if x % 5 == 0 then dot(g, x, edge - 2, C.blueTint) end
  end
  -- a thin moon
  ellipse(g, 89, 10, 4, 3, C.text)
  ellipse(g, 87.5, 9.3, 3.8, 3, C.bg)
  -- the far roofs, black against the haze, chimneys and all
  local x = 12
  local k = 0
  while x < W do
    k = k + 1
    local w = 7 + floor(hash(k, 1, 1) * 8)
    local top = 25 + floor(hash(k, 2, 1) * 5)
    poly(g, { x - 1, 40, x - 1, top + 3, x + w / 2, top, x + w + 1, top + 3, x + w + 1, 40 }, C.bg)
    if hash(k, 3, 1) < 0.5 then rect(g, x + 2, top - 2, 2, 4, C.bg) end
    x = x + w + 1
  end
  -- the houses in the middle: dark walls, moonlit roofs
  for _, h in ipairs(NIGHT_HOUSES) do
    local hx, w, eave, ridge = h[1], h[2], h[3], h[4]
    rect(g, hx, eave, w, 55 - eave, C.panel)
    poly(g, { hx - 1, eave + 1, hx + w / 2, ridge, hx + w + 1, eave + 1 }, C.blueTint)
    line(g, hx - 1, eave, hx + w / 2 - 1, ridge, C.tie)
    poly(g, { hx + 3, eave + 1, hx + w / 2, ridge + 3, hx + w - 3, eave + 1 }, C.panel)
    rect(g, hx, eave + 1, w, 1, C.bg)
    rect(g, hx, eave + 1, 1, 55 - eave, C.bg)
    rect(g, hx + w - 1, eave + 1, 1, 55 - eave, C.bg)
    rect(g, hx + w - 5, ridge - 2, 2, 5, C.panel)
    rect(g, hx + w - 6, ridge - 2, 4, 1, C.bg)
  end
  -- the near roofs, big slopes of slate seen from above
  poly(g, { 11, 63, 11, 52, 15, 50, 60, 50, 64, 63 }, C.blueTint)
  poly(g, { 60, 63, 62, 49, 66, 47, 121, 47, 121, 63 }, C.blueTint)
  -- slates: a dark line under each course, and the joints between them staggered
  for _, roof in ipairs({ { 11, 63, 52 }, { 60, W - 1, 50 } }) do
    for y = roof[3], 63 do
      local course = (y - roof[3]) % 3
      for xx = roof[1], roof[2] do
        if get(g, xx, y) == C.blueTint then
          if course == 0 or (course == 2 and (xx + floor((y - roof[3]) / 3) * 4) % 8 == 0) then dot(g, xx, y, C.panel) end
        end
      end
    end
  end
  rect(g, 15, 50, 45, 1, C.tie)
  rect(g, 66, 47, 55, 1, C.tie)
  line(g, 60, 50, 64, 63, C.bg)
  line(g, 62, 49, 60, 63, C.bg)
  -- dormers on the near roofs, each round the window it holds
  for _, d in ipairs({ { 30, 55, 5 }, { 86, 53, 5 } }) do
    local dx, dy, dw = d[1], d[2], d[3]
    rect(g, dx - 2, dy - 2, dw + 4, 7, C.panel)
    poly(g, { dx - 3, dy - 1, dx + dw / 2, dy - 6, dx + dw + 3, dy - 1 }, C.blueTint)
    line(g, dx - 3, dy - 2, dx + dw / 2 - 1, dy - 6, C.tie)
  end
  -- every window's frame, and what's in it at the start: lamplight
  for _, wd in ipairs(NIGHT_WINDOWS) do
    rect(g, wd[1] - 1, wd[2] - 1, wd[3] + 2, wd[4] + 2, C.bg)
  end
  -- the wall, a dark band up the left, its blocks just showing
  rect(g, 0, 0, 11, H, C.panel)
  for y = 0, H - 1, 4 do rect(g, 0, y, 11, 1, C.bg) end
  for y = 0, H - 1 do
    local off = (floor(y / 4) % 2) * 3
    if y % 4 ~= 0 then dot(g, 4 + off, y, C.bg) end
  end
  rect(g, 11, 0, 1, H, C.tie)
  rect(g, 12, 0, 1, H, C.bg)
  return g
end

-- the path the grey takes from the first window to the second, along the wall between the houses
local SEEP = {}
do
  for x = 23, 37 do SEEP[#SEEP + 1] = { x, 43 + round(sin((x - 23) * 0.7) * 0.8) } end
end

local nightBase

local function drawNight(t)
  nightBase = nightBase or buildNight()
  local g = copyInto(work, nightBase)
  -- stars, a few of them breathing
  for k = 1, 40 do
    local sx, sy = 14 + floor(hash(k, 11, 1) * 106), floor(hash(k, 12, 1) * 20)
    if not (sx >= 103 and sy <= 8) and get(g, sx, sy) == C.bg then
      local twinkle = hash(k, floor(t / 6), 2) < 0.2
      dot(g, sx, sy, (k % 5 == 0 and not twinkle) and C.text or (twinkle and C.tie or C.line))
    end
  end
  local spreading = t >= SPREAD_FROM
  local reached = t >= SPREAD_TO
  for n, wd in ipairs(NIGHT_WINDOWS) do
    local x, y, w, h, darkAt, sleepAt, phase = wd[1], wd[2], wd[3], wd[4], wd[5], wd[6], wd[7]
    if t < darkAt then
      -- lamplight, and its spill round the frame
      rect(g, x, y, w, h, C.hi)
      rect(g, x, y + h - 1, w, 1, C.warn)
      rect(g, x + floor(w / 2), y, 1, h, C.warn)
    elseif t < sleepAt then
      rect(g, x, y, w, h, C.bg)
    else
      -- a dream wakes slowly: dim for a moment, then its colour
      local young = t - sleepAt < 2
      local isGrey = wd.grey or (n == 2 and reached)
      if isGrey then
        if young then rect(g, x, y, w, h, C.tie) else greyWindow(g, x, y, w, h, t, n, true) end
        if n == 2 and t < SPREAD_TO + 3 then
          -- the colour it had is going out from the corner the grey came in by
          local left = SPREAD_TO + 3 - t
          dreamWindow(g, x + w - left, y, left, h, t, phase, NIGHT_STEP, false)
        end
      elseif young then
        local _, _, _, tint = dreamAt(t, phase, NIGHT_STEP)
        rect(g, x, y, w, h, tint)
      else
        dreamWindow(g, x, y, w, h, t, phase, NIGHT_STEP, true)
      end
    end
  end
  -- the grey creeping along the wall: a lime head, a grey trail that stays
  if spreading then
    local reach = min(#SEEP, floor((t - SPREAD_FROM) * #SEEP / (SPREAD_TO - SPREAD_FROM)) + 1)
    for k = 1, reach do
      local p = SEEP[k]
      local c = C.line
      if k == reach and not reached then c = C.soft
      elseif hash(k, floor(t / 2), 4) < 0.18 then c = C.soft
      elseif k % 3 == 0 then c = C.tie end
      dot(g, p[1], p[2], c)
    end
  end
  emit(g)
end

M.LENGTH.night = true
M.CUES.night = {}
do
  local cues = {}
  for _, wd in ipairs(NIGHT_WINDOWS) do
    cues[#cues + 1] = { wd[5], "intro_window" }
    cues[#cues + 1] = { wd[6], "intro_dream_rise" }
  end
  cues[#cues + 1] = { SPREAD_FROM, "intro_grey" }
  table.sort(cues, function(a, b) return a[1] < b[1] end)
  M.CUES.night = cues
end

-- ---------------------------------------------------------------- 4. knock: the plague doctors at the door

local KNOCKS = { 5, 8, 11 }
local OPEN_AT = 16
local DOOR_L, DOOR_R, DOOR_T = 80, 98, 27

local function buildKnock()
  local g = newGrid(C.bg)
  -- the great wall behind the street, filling the sky to the top
  rect(g, 0, 0, 62, 30, C.panel)
  for y = 0, 29, 5 do rect(g, 0, y, 62, 1, C.bg) end
  for y = 0, 29 do
    local off = (floor(y / 5) % 2) * 7
    if y % 5 ~= 0 then for x = off, 61, 14 do dot(g, x, y, C.bg) end end
  end
  -- a strip of night between the wall's foot and the roofs across the way
  rect(g, 0, 30, 62, 2, C.bg)
  -- the houses across the street: dark shapes, every window asleep
  poly(g, { 0, 62, 0, 36, 8, 31, 17, 36, 17, 62 }, C.panel)
  poly(g, { 17, 62, 17, 38, 22, 33, 38, 33, 43, 38, 43, 62 }, C.panel)
  poly(g, { 43, 62, 43, 35, 52, 31, 61, 35, 61, 62 }, C.panel)
  for _, wd in ipairs({ { 6, 41 }, { 25, 42 }, { 34, 42 }, { 50, 40 } }) do rect(g, wd[1], wd[2], 3, 3, C.bg) end
  line(g, 0, 36, 8, 31, C.tie)
  line(g, 22, 33, 38, 33, C.tie)
  line(g, 43, 35, 52, 31, C.tie)
  -- the cottage: plaster, timbers, the eaves along the top
  rect(g, 62, 0, W - 62, 63, C.hiTint)
  rect(g, 60, 0, W - 60, 7, C.bg)
  rect(g, 60, 7, W - 60, 1, C.tie)
  for _, x in ipairs({ 62, 75, 103, 119 }) do rect(g, x, 8, 2, 55, C.bg) end
  rect(g, 62, 21, W - 62, 2, C.bg)
  line(g, 64, 20, 74, 9, C.bg)
  line(g, 105, 9, 118, 20, C.bg)
  -- the upstairs window, dark, and the one by the door
  rect(g, 84, 10, 11, 9, C.bg)
  rect(g, 85, 11, 9, 7, C.panel)
  rect(g, 89, 11, 1, 7, C.bg)
  rect(g, 85, 14, 9, 1, C.bg)
  rect(g, 106, 30, 11, 10, C.bg)
  rect(g, 107, 31, 9, 8, C.panel)
  rect(g, 111, 31, 1, 8, C.bg)
  rect(g, 106, 40, 11, 1, C.tie)
  -- the door: a stone frame, planks, iron straps and a ring
  rect(g, DOOR_L - 2, DOOR_T - 2, DOOR_R - DOOR_L + 5, 63 - DOOR_T + 2, C.tie)
  rect(g, DOOR_L - 2, DOOR_T - 2, DOOR_R - DOOR_L + 5, 1, C.line)
  rect(g, DOOR_L, DOOR_T, DOOR_R - DOOR_L + 1, 63 - DOOR_T, C.redTint)
  for x = DOOR_L + 4, DOOR_R - 1, 5 do rect(g, x, DOOR_T, 1, 63 - DOOR_T, C.bg) end
  rect(g, DOOR_L, 32, DOOR_R - DOOR_L + 1, 1, C.bg)
  rect(g, DOOR_L, 55, DOOR_R - DOOR_L + 1, 1, C.bg)
  ellipse(g, DOOR_R - 3.5, 44.5, 1.5, 1.2, C.warn)
  dot(g, DOOR_R - 4, 44, C.redTint)
  -- the step and the street
  rect(g, 0, 63, W, H - 63, C.panel)
  rect(g, DOOR_L - 4, 62, DOOR_R - DOOR_L + 9, 2, C.line)
  for y = 64, 66 do
    for x = (y % 2) * 3, W - 1, 6 do if hash(x, y, 9) < 0.5 then dot(g, x, y, C.tie) end end
  end
  return g
end

-- lantern light: warm on everything close
local LANTERN_HAND = { 44, 41 }
local LANT_FAR = { [C.panel] = C.hiTint, [C.bg] = C.panel }
local LANT_POOL = { [C.hiTint] = C.redTint, [C.tie] = C.warn }
local SPILL = { [C.panel] = C.warn, [C.tie] = C.hi, [C.line] = C.hi, [C.hiTint] = C.warn, [C.redTint] = C.warn, [C.bg] = C.redTint }

--- A Clinic doctor facing right, feet on row 62 at column fx: wide hat, grey mask, long beak, a long grey coat.
-- arm: the hand's place, and whether it holds the lantern. lit: light from the open door on the front edge.
local function drawDoctor(g, fx, hand, lantern, lit, t)
  local o = {}
  local function blk(x, y, w, h, c)
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do
      if xx >= 0 and xx < W and yy >= 0 and yy < H then o[yy * W + xx + 1] = c end
    end end
  end
  local function pts(list, c)
    local tmp = {}
    poly(tmp, list, c)
    for i, v in pairs(tmp) do o[i] = v end
  end
  -- coat, falling wide to the hem, darker at the back
  pts({ fx - 5, 35, fx + 4, 35, fx + 8, 60, fx - 9, 60 }, C.tie)
  pts({ fx - 5, 35, fx - 2, 35, fx - 4, 60, fx - 9, 60 }, C.panel)
  blk(fx - 6, 46, 13, 1, C.bg) -- belt
  blk(fx + 1, 47, 1, 1, C.line)
  -- boots
  blk(fx - 6, 60, 5, 3, C.bg)
  blk(fx + 1, 60, 7, 3, C.bg)
  -- the cowl over the shoulders
  pts({ fx - 6, 38, fx - 4, 32, fx + 4, 32, fx + 6, 38 }, C.line)
  pts({ fx - 6, 38, fx - 4, 32, fx - 1, 32, fx - 2, 38 }, C.tie)
  -- the head and its mask
  blk(fx - 4, 27, 8, 6, C.line)
  blk(fx - 4, 27, 2, 6, C.tie)
  -- the beak, long and tapering down to a point
  pts({ fx + 3, 28, fx + 12, 32.5, fx + 3, 32.5 }, C.line)
  pts({ fx + 3, 31, fx + 12, 32.5, fx + 3, 32.5 }, C.tie)
  -- the glass eye, with the lantern caught in it
  blk(fx + 1, 28, 2, 2, C.bg)
  blk(fx + 2, 28, 1, 1, lit and C.hi or C.warn)
  -- the hat: a tall crown and a broad brim
  blk(fx - 4, 21, 8, 5, C.bg)
  blk(fx - 4, 25, 8, 1, C.tie)
  blk(fx - 8, 26, 17, 1, C.bg)
  -- the arm: a grey sleeve from the shoulder to a black glove
  local sx, sy = fx + 3, 37
  local hx, hy = hand[1], hand[2]
  local steps = max(abs(hx - sx), abs(hy - sy))
  for s = 0, steps do
    local ax, ay = round(sx + (hx - sx) * s / steps), round(sy + (hy - sy) * s / steps)
    blk(ax, ay, 2, 2, C.tie)
  end
  blk(hx, hy, 2, 2, C.bg)
  if lantern then
    blk(hx + 1, hy + 2, 1, 2, C.bg)
    blk(hx - 1, hy + 4, 5, 1, C.bg)
    blk(hx - 1, hy + 5, 1, 4, C.bg)
    blk(hx + 3, hy + 5, 1, 4, C.bg)
    blk(hx, hy + 5, 3, 4, C.hi)
    blk(hx + 1, hy + 6, 1, 2, (floor(t / 3) % 3 == 0) and C.warn or C.text)
    blk(hx - 1, hy + 9, 5, 1, C.bg)
  end
  if lit then
    -- the warm line down the front of everything that faces the door
    for i, c in pairs(o) do
      local x = (i - 1) % W
      if c ~= C.bg and not o[i + 1] and x >= fx then o[i] = c == C.line and C.hi or C.warn end
    end
  end
  outlined(o, C.bg)
  stamp(g, o)
end

local knockBase

local function drawKnock(t)
  knockBase = knockBase or buildKnock()
  local g = copyInto(work, knockBase)
  -- the lantern's warm light, from the second doctor's hand
  local lx, ly = LANTERN_HAND[1] + 1.5, LANTERN_HAND[2] + 7
  light(g, lx, ly, 22, 13, LANT_FAR, true)
  light(g, lx, 63, 12, 2.5, LANT_POOL)
  -- the door opening: a crack of warm light on the latch side, widening
  local open = t < OPEN_AT and 0 or min(3, t - OPEN_AT + 1)
  local lit = open > 0
  if lit then
    rect(g, DOOR_R - open + 1, DOOR_T, open, 63 - DOOR_T, C.hi)
    if open >= 2 then rect(g, DOOR_R - open + 2, DOOR_T + 1, open - 1, 61 - DOOR_T, C.text) end
    rect(g, DOOR_R - open, DOOR_T, 1, 63 - DOOR_T, C.bg) -- the door's own edge, just ajar
    -- the spill: across the step and the street toward the doctors
    local spread = open * 11
    local spill = {}
    poly(spill, { DOOR_R - open, 61.5, DOOR_R + 1, 61.5, DOOR_R + 1, 67, DOOR_R - open - spread, 67 }, 1)
    for i in pairs(spill) do g[i] = SPILL[g[i]] or g[i] end
    light(g, DOOR_R + 1, 45, 3 + open, 20, { [C.tie] = C.line, [C.hiTint] = C.redTint })
  end
  -- the knocker's arm: up at the door from the first knock, back down once the door's open
  local fx1 = 64
  local up = t >= 3 and t < OPEN_AT + 3
  local hand = { fx1 + 3, 49 }
  if up then
    hand = { fx1 + 11, 38 }
    for _, k in ipairs(KNOCKS) do
      if t == k then hand = { DOOR_L - 1, 39 } end
    end
  elseif t >= 2 and t < 3 then
    hand = { fx1 + 8, 43 }
  end
  drawDoctor(g, 34, LANTERN_HAND, true, false, t)
  -- the lantern's own light on the coat that carries it
  light(g, lx, ly, 6, 4, { [C.tie] = C.line, [C.panel] = C.tie })
  drawDoctor(g, fx1, hand, false, lit, t)
  emit(g)
end

M.LENGTH.knock = OPEN_AT + 9
M.CUES.knock = { { KNOCKS[1], "intro_knock" }, { KNOCKS[2], "intro_knock" }, { KNOCKS[3], "intro_knock" }, { OPEN_AT, "intro_door" } }

-- ---------------------------------------------------------------- 5. one: every window dreaming, all but one

local ONE_HOUSES = {
  -- left edge, width, eaves, ridge
  { -2, 19, 48, 42 }, { 18, 22, 47, 41 }, { 41, 17, 49, 43 }, { 59, 22, 48, 40 }, { 82, 18, 49, 42 }, { 101, 21, 48, 42 },
}
local ATTIC = { 28, 44, 2, 2 } -- the small window up in the gable of the second house

local oneWindows = {}

local function buildOne()
  local g = newGrid(C.bg)
  -- a strip of stars above the wall
  for k = 1, 30 do
    local sx, sy = floor(hash(k, 21, 1) * W), floor(hash(k, 22, 1) * 5)
    if not (sx >= 103 and sy <= 8) then dot(g, sx, sy, k % 4 == 0 and C.text or C.tie) end
  end
  -- the wall, as on the title: merlons along the top, courses, and its thin red crack
  local top = 7
  for x = 0, W - 1, 8 do rect(g, x, top - 2, 5, 2, C.panel) end
  rect(g, 0, top, W, 50, C.panel)
  for y = top + 3, 56, 5 do rect(g, 0, y, W, 1, C.bg) end
  for y = top, 56 do
    local off = (floor((y - top - 3) / 5) % 2) * 6
    if (y - top - 3) % 5 ~= 0 then for x = off + 3, W - 1, 12 do dot(g, x, y, C.bg) end end
  end
  local crack = floor(W * 0.62)
  for y = top - 2, 56 do dot(g, crack + (y % 7 < 3 and 1 or -1), y, C.red) end
  for y = top - 2, 56 do dot(g, crack + (y % 7 < 3 and 2 or 0), y, C.red) end
  -- the houses, asleep: black walls, moonlit roofs
  oneWindows = {}
  for n, h in ipairs(ONE_HOUSES) do
    local x, w, eave, ridge = h[1], h[2], h[3], h[4]
    if n % 2 == 1 then
      rect(g, x + w - 6, ridge - 1, 3, 5, C.panel)
      rect(g, x + w - 7, ridge - 1, 5, 1, C.tie)
    end
    rect(g, x, eave, w, 64 - eave, C.bg)
    poly(g, { x - 1, eave + 1, x + w / 2, ridge, x + w + 1, eave + 1 }, C.blueTint)
    line(g, x - 1, eave, x + w / 2 - 1, ridge, C.tie)
    poly(g, { x + 3, eave + 1, x + w / 2, ridge + 3, x + w - 3, eave + 1 }, C.bg)
    -- timbers, just showing
    rect(g, x, eave + 1, w, 1, C.panel)
    rect(g, x, eave + 1, 1, 63 - eave, C.panel)
    rect(g, x + w - 1, eave + 1, 1, 63 - eave, C.panel)
    -- two windows upstairs, every one of them dreaming
    for k, wx in ipairs({ x + 3, x + w - 7 }) do
      oneWindows[#oneWindows + 1] = { wx, eave + 3, 4, 3, hash(n, k, 31) * 7 }
    end
    -- and one by the door, for the houses whose downstairs is a bedroom too
    local door = (n % 2 == 0) and x + w - 7 or x + 3
    if n % 3 ~= 1 then oneWindows[#oneWindows + 1] = { (n % 2 == 0) and x + 3 or x + w - 7, 57, 4, 3, hash(n, 3, 31) * 7 } end
    rect(g, door, 56, 4, 8, C.panel)
    rect(g, door + 1, 57, 2, 7, C.bg)
  end
  -- the attic window: a frame, and nothing in it
  rect(g, ATTIC[1] - 1, ATTIC[2] - 1, ATTIC[3] + 2, ATTIC[4] + 2, C.tie)
  rect(g, ATTIC[1], ATTIC[2], ATTIC[3], ATTIC[4], C.bg)
  -- the ground
  rect(g, 0, 64, W, H - 64, C.panel)
  return g
end

local oneBase

local function drawOne(t)
  oneBase = oneBase or buildOne()
  local g = copyInto(work, oneBase)
  for _, wd in ipairs(oneWindows) do
    dreamWindow(g, wd[1], wd[2], wd[3], wd[4], t, wd[5], 9, "frame")
  end
  -- the attic stays as it is, whatever the light round it does
  rect(g, ATTIC[1] - 1, ATTIC[2] - 1, ATTIC[3] + 2, ATTIC[4] + 2, C.tie)
  rect(g, ATTIC[1], ATTIC[2], ATTIC[3], ATTIC[4], C.bg)
  emit(g)
end

M.LENGTH.one = true
M.CUES.one = {}

-- ---------------------------------------------------------------- drawing

local DRAW = { dusk = drawDusk, book = drawBook, night = drawNight, knock = drawKnock, one = drawOne }

function M.draw(L, pic, t)
  t = max(0, floor(tonumber(t) or 0))
  local length = M.LENGTH[pic]
  if type(length) == "number" and t > length then t = length end
  local f = DRAW[pic]
  if not f then
    ui.fill(0, 0, L.W, L.H, C.bg)
    return
  end
  if L.W > W then ui.fill(W, 0, L.W - W, L.H, C.bg) end
  f(t)
end

return M
