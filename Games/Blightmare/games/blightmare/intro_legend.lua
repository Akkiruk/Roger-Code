-- games/blightmare/intro_legend.lua
-- The first movement of the opening: the gods. Two pictures, drawn for intro.lua.
--   oblivion  the Chained Oblivion, a churning swirl inside a turning ring of chain, with the small world it made below.
--   binding   the swirl awake, the gods' chain going grey link by link, and the Raven Queen holding the last one.
-- Everything that doesn't move is worked out once, here at load time, as runs of colour. A frame only picks colours and fills.
-- Geometry is in pixels of a cell 6 wide and 9 tall, the shape it has on the wall, so a circle comes out round.

local ui = require("lib.arcade.ui")

local C = ui.C
local floor, sqrt, sin, cos, pi, abs = math.floor, math.sqrt, math.sin, math.cos, math.pi, math.abs
local atan2 = math.atan2 or math.atan
local TAU = pi * 2
local CW, CH = 6, 9

local M = { LENGTH = {}, CUES = {} }

local function frac(v) return v - floor(v) end

-- a fixed hash of a few numbers, 0 to 1: the same every load, so the sky never shuffles
local function hash(a, b)
  local h = (a * 7919 + b * 104729 + 1013) % 65521
  h = (h * h + a * 31 + b) % 65521
  h = (h * h + 17) % 65521
  h = (h * h + b * 7) % 65521
  return h / 65521
end

-- ---------------------------------------------------------------- baking shapes into runs

-- Cells whose middle a test passes, as runs { x, y, w, key } where key is what the test returned (a shade).
local function bake(x0, y0, x1, y1, test)
  local runs = {}
  for y = y0, y1 do
    local py = y * CH + CH / 2
    local start, key = nil, nil
    for x = x0, x1 + 1 do
      local k = x <= x1 and test(x * CW + CW / 2, py, x, y) or nil
      if k ~= key then
        if key then runs[#runs + 1] = { start, y, x - start, key } end
        start, key = x, k
      end
    end
  end
  return runs
end

-- A ring (or a solid bar when inner is nil) along direction (dx, dy), centred at (cx, cy) in pixels. Shade 1 is the side away
-- from the light (lx, ly), 2 the body, 3 the side facing it.
local function bakeLink(cx, cy, dx, dy, a, b, ia, ib, lx, ly)
  local m = (a > b and a or b) + 2
  local x0, x1 = floor((cx - m) / CW), floor((cx + m) / CW)
  local y0, y1 = floor((cy - m) / CH), floor((cy + m) / CH)
  return bake(x0, y0, x1, y1, function(px, py)
    local ox, oy = px - cx, py - cy
    local u, v = ox * dx + oy * dy, -ox * dy + oy * dx
    if (u / a) ^ 2 + (v / b) ^ 2 > 1 then return nil end
    if ia and (u / ia) ^ 2 + (v / ib) ^ 2 < 1 then return nil end
    local l = (ox * lx + oy * ly) / m
    if l > 0.3 then return 3 elseif l < -0.3 then return 1 end
    return 2
  end)
end

-- A polygon in cell units (points x1, y1, x2, y2, ...), as runs of one key.
local function bakePoly(pts, key)
  local runs = {}
  local n = #pts / 2
  local minY, maxY = 1e9, -1e9
  for i = 1, n do
    local y = pts[i * 2]
    if y < minY then minY = y end
    if y > maxY then maxY = y end
  end
  for y = floor(minY), floor(maxY) do
    local yc = y + 0.5
    local xs = {}
    for i = 1, n do
      local j = i % n + 1
      local xa, ya, xb, yb = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
      if (ya <= yc and yb > yc) or (yb <= yc and ya > yc) then
        xs[#xs + 1] = xa + (yc - ya) / (yb - ya) * (xb - xa)
      end
    end
    table.sort(xs)
    for k = 1, #xs - 1, 2 do
      local a, b = floor(xs[k] + 0.5), floor(xs[k + 1] - 0.5)
      if b >= a then runs[#runs + 1] = { a, y, b - a + 1, key } end
    end
  end
  return runs
end

-- Draw runs, each in colour pal[key].
local function drawRuns(runs, pal)
  local fill = ui.fill
  for i = 1, #runs do
    local r = runs[i]
    local c = pal[r[4]]
    if c then fill(r[1], r[2], r[3], 1, c) end
  end
end

-- ---------------------------------------------------------------- the swirl

-- The Oblivion: a disc of spiral arms that turn. Each cell keeps where it sits on the spiral; a frame shifts that by t and
-- picks a colour, joining cells of one colour on a row into one fill.
local function makeSwirl(cx, cy, R, arms, twist)
  local rows = {}
  local y0, y1 = floor((cy - R) / CH), floor((cy + R) / CH)
  local x0, x1 = floor((cx - R) / CW), floor((cx + R) / CW)
  for y = y0, y1 do
    local row = { y = y, xs = {}, rs = {}, ps = {} }
    local py = y * CH + CH / 2
    for x = x0, x1 do
      local px = x * CW + CW / 2
      local r = sqrt((px - cx) ^ 2 + (py - cy) ^ 2) / R
      if r <= 1 then
        local ang = atan2(py - cy, px - cx) / TAU
        row.xs[#row.xs + 1] = x
        row.rs[#row.rs + 1] = r
        -- a little fixed wobble so the arms aren't ruled lines
        row.ps[#row.ps + 1] = arms * ang + twist * sqrt(r) + (hash(x, y) - 0.5) * 0.03
      end
    end
    if #row.xs > 0 then rows[#rows + 1] = row end
  end
  return { rows = rows }
end

-- shade: 0 dark .. 4 brightest, from where a cell sits on an arm and how far out it is
local function swirlLevel(r, f)
  local k = f < 0.13 and 3 or f < 0.3 and 2 or f < 0.52 and 1 or 0
  if r < 0.34 then k = k + 1 end
  if r > 0.74 then k = k - 1 end
  if r > 0.9 then k = k - 1 end
  return k
end

local function drawSwirl(sw, phase, ramp, eye, eyeRim, rimColor)
  local fill = ui.fill
  for i = 1, #sw.rows do
    local row = sw.rows[i]
    local xs, rs, ps = row.xs, row.rs, row.ps
    local start, cur = xs[1], nil
    local n = #xs
    for j = 1, n + 1 do
      local c
      if j <= n then
        local r = rs[j]
        if r < eye then c = C.bg
        elseif r < eyeRim then c = rimColor
        else
          local k = swirlLevel(r, frac(ps[j] - phase))
          if k < 0 then k = 0 elseif k > 4 then k = 4 end
          c = ramp[k]
        end
      end
      if c ~= cur or (j <= n and xs[j] ~= xs[j - 1] + 1) then
        if cur and cur ~= C.bg then fill(start, row.y, xs[j - 1] - start + 1, 1, cur) end
        if j <= n then start, cur = xs[j], c end
      end
    end
  end
end

-- ---------------------------------------------------------------- stars

local function makeStars(count, seed, avoid)
  local out = {}
  local i = 0
  while #out < count and i < count * 20 do
    i = i + 1
    local x = floor(hash(seed, i) * 121)
    local y = floor(hash(seed + 1, i) * 62)
    if not (avoid and avoid(x, y)) then
      local b = hash(seed + 2, i)
      out[#out + 1] = { x = x, y = y, bright = b > 0.82 and 2 or b > 0.4 and 1 or 0, ph = hash(seed + 3, i) }
    end
  end
  return out
end

-- ================================================================ 1. oblivion

local O = {}
O.cx, O.cy = 60 * CW + CW / 2, 27 * CH     -- the middle of everything, in pixels
O.ringR = 192
O.links = 24
O.phases = 8                               -- steps for the ring to turn by two links, where it looks the same again
O.stepTicks = 3                            -- ticks a step

-- the ring at each step of its turn: edge-on links first so the face-on ones lie over their ends
O.ring = {}
for ph = 0, O.phases - 1 do
  local set = {}
  for pass = 1, 2 do
    for i = 0, O.links - 1 do
      local face = i % 2 == 0
      if (pass == 2) == face then
        local ang = (i + ph * 2 / O.phases) / O.links * TAU
        local lx, ly = O.cx + cos(ang) * O.ringR, O.cy + sin(ang) * O.ringR
        local dx, dy = -sin(ang), cos(ang)                -- along the ring
        local tx, ty = -cos(ang), -sin(ang)               -- toward the swirl, where its light comes from
        local runs = face and bakeLink(lx, ly, dx, dy, 31, 20, 14, 7, tx, ty)
          or bakeLink(lx, ly, dx, dy, 29, 8, nil, nil, tx, ty)
        set[#set + 1] = { ang = ang, runs = runs, face = face }
      end
    end
  end
  O.ring[ph] = set
end

O.swirl = makeSwirl(O.cx, O.cy, 164, 3, 1.5)
O.CALM = { [0] = C.bg, C.panel, C.blueTint, C.accent, C.accent }

-- the stars, kept off the swirl and the world
O.stars = makeStars(110, 11, function(x, y)
  local px, py = x * CW + 3, y * CH + 4.5
  local d = sqrt((px - O.cx) ^ 2 + (py - O.cy) ^ 2)
  if d < 205 then return true end
  if x >= 102 and y <= 8 then return true end
  return false
end)
for _, s in ipairs(O.stars) do
  s.ang = atan2(s.y * CH + 4.5 - O.cy, s.x * CW + 3 - O.cx)
end

-- Elawondra, small and round, turning slowly
O.world = { cx = 60 * CW + CW / 2, cy = 56 * CH + 4.5, R = 37 }
do
  local w = O.world
  local cells = {}
  for y = floor((w.cy - w.R) / CH), floor((w.cy + w.R) / CH) do
    for x = floor((w.cx - w.R) / CW), floor((w.cx + w.R) / CW) do
      local nx, ny = (x * CW + 3 - w.cx) / w.R, (y * CH + 4.5 - w.cy) / w.R
      local rr = nx * nx + ny * ny
      if rr <= 1 then
        local nz = sqrt(1 - rr)
        cells[#cells + 1] = { x = x, y = y, lon = atan2(nx, nz) / TAU, lat = ny,
          lit = -0.55 * nx - 0.5 * ny + 0.67 * nz, edge = rr > 0.72 }
      end
    end
  end
  table.sort(cells, function(a, b) return a.y < b.y or (a.y == b.y and a.x < b.x) end)
  w.cells = cells
end
-- continents: { longitude 0..1, latitude -1..1, half-width, half-height }
O.lands = { { 0.05, -0.25, 0.11, 0.32 }, { 0.12, 0.3, 0.07, 0.3 }, { 0.42, 0.05, 0.13, 0.42 }, { 0.52, -0.55, 0.06, 0.2 },
  { 0.74, 0.25, 0.09, 0.28 }, { 0.8, -0.4, 0.05, 0.18 } }

local function isLand(lon, lat)
  for i = 1, #O.lands do
    local l = O.lands[i]
    local d = abs(frac(lon - l[1] + 0.5) - 0.5)
    if (d / l[3]) ^ 2 + ((lat - l[2]) / l[4]) ^ 2 < 1 then return true end
  end
  return false
end

local function drawWorld(t)
  local w = O.world
  local spin = t / 240
  local fill = ui.fill
  local runX, runY, runW, runC = nil, nil, 0, nil
  for i = 1, #w.cells do
    local c = w.cells[i]
    local land = isLand(c.lon + spin, c.lat)
    local col
    if land then
      col = c.lit > 0.55 and C.soft or c.lit > -0.05 and C.ok or C.hiTint
    else
      col = c.lit > 0.62 and C.info or c.lit > -0.05 and C.blue or C.blueTint
    end
    if c.edge and c.lit > 0.25 and not land then col = C.info end
    if runC == col and runY == c.y and runX + runW == c.x then
      runW = runW + 1
    else
      if runC then fill(runX, runY, runW, 1, runC) end
      runX, runY, runW, runC = c.x, c.y, 1, col
    end
  end
  if runC then fill(runX, runY, runW, 1, runC) end
end

-- the gods: sparks born in the swirl that wind out through the ring and fall to the world
local GOD_COLORS = { C.hi, C.ok, C.red, C.info, C.warn, C.soft, C.accent, C.blue }
local MOTE_LIFE, MOTES = 64, 8

local function drawMotes(t)
  for i = 1, MOTES do
    local age = frac((t + (i - 1) * MOTE_LIFE / MOTES) / MOTE_LIFE)
    local px, py
    if age < 0.62 then
      -- out along the spiral from the eye to the bottom of the ring
      local s = age / 0.62
      local r = 0.18 + s * (O.ringR + 6 - 0.18 * 158)
      local ang = pi / 2 - (1 - s) * TAU * 1.25 + (i % 2) * 0.12
      px, py = O.cx + cos(ang) * r, O.cy + sin(ang) * r
    else
      -- then down to the world
      local s = (age - 0.62) / 0.38
      local sx, sy = O.cx, O.cy + O.ringR + 6
      local ex, ey = O.world.cx + ((i % 3) - 1) * 14, O.world.cy - 16
      px, py = sx + (ex - sx) * s, sy + (ey - sy) * s
    end
    local x, y = floor(px / CW), floor(py / CH)
    local col = GOD_COLORS[i]
    if age > 0.95 then col = C.text end
    ui.fill(x, y, 2, 1, col)
  end
end

local STEEL = { [0] = C.bg, C.panel, C.tie, C.line, C.text, C.hi }
local SWEEP = 96          -- ticks for the unmaking to go once round the sky

local function drawOblivion(L, t)
  ui.fill(0, 0, L.W, L.H, C.bg)

  -- stars: the unmaking sweeps round the sky; a star goes out as it reaches it and is made again behind it, a flash of white
  local sweep = frac(t / SWEEP) * TAU
  for i = 1, #O.stars do
    local s = O.stars[i]
    local d = (s.ang - sweep) % TAU
    local col
    if d < 1.5 then
      col = nil
    elseif d < 1.75 then
      col = C.text
    else
      col = s.bright == 2 and C.text or s.bright == 1 and C.line or C.tie
      if s.bright == 2 and frac(t / 40 + s.ph) < 0.08 then col = C.info end
    end
    if col then ui.fill(s.x, s.y, 1, 1, col) end
  end

  -- the swirl, then the ring around it
  drawSwirl(O.swirl, t / 70, O.CALM, 0.1, 0.16, C.text)

  local step = floor(t / O.stepTicks)
  local ph = step % O.phases
  local turned = floor(step / O.phases) * 2   -- links the ring has turned by whole repeats
  local set = O.ring[ph]
  -- a glint runs round the chain, faster than it turns
  local glint = frac(t / 36) * TAU
  local spacing = TAU / O.links
  local pal = {}
  for i = 1, #set do
    local l = set[i]
    local d = abs((l.ang + turned * spacing - glint + pi) % TAU - pi)
    local boost = d < spacing * 0.6 and 2 or d < spacing * 1.6 and 1 or 0
    pal[1], pal[2], pal[3] = STEEL[1 + boost], STEEL[2 + boost], STEEL[3 + boost]
    drawRuns(l.runs, pal)
  end

  drawMotes(t)
  drawWorld(t)
end

M.LENGTH.oblivion = true
M.CUES.oblivion = { { 1, "intro_chain" } }

-- ================================================================ 2. binding

local B = {}
B.START = 12          -- the first god spends itself
B.GAP = 3             -- ticks between links
B.GODS = 11           -- links that go grey; the twelfth is hers
B.REACH = B.START + B.GAP * B.GODS      -- the last link is reached: the Raven Queen
B.SETTLE = 10                           -- ticks after that for the swirl to quieten and her eyes to light
M.LENGTH.binding = B.REACH + B.SETTLE

B.cx, B.cy, B.R = 27 * CW + 3, 18 * CH, 150
B.swirl = makeSwirl(B.cx, B.cy, B.R, 3, 2.1)
B.AWAKE = { [0] = C.bg, C.redTint, C.accent, C.red, C.warn }
B.EASING = { [0] = C.bg, C.redTint, C.accent, C.accent, C.red }
B.HELD = { [0] = C.bg, C.panel, C.blueTint, C.accent, C.accent }

B.stars = makeStars(55, 41, function(x, y)
  local px, py = x * CW + 3, y * CH + 4.5
  if sqrt((px - B.cx) ^ 2 + (py - B.cy) ^ 2) < B.R + 8 then return true end
  if x >= 102 and y <= 8 then return true end
  if x >= 74 then return true end
  return false
end)

-- the chain: a heavy sag from the swirl's edge to her hands
do
  local p0x, p0y = 43 * CW, 30 * CH
  local c1x, c1y = 55 * CW, 78 * CH
  local p2x, p2y = 86 * CW, 45 * CH
  local pts, lens = {}, { 0 }
  local N = 240
  for i = 0, N do
    local s = i / N
    local a, b, c = (1 - s) ^ 2, 2 * (1 - s) * s, s * s
    pts[i] = { a * p0x + b * c1x + c * p2x, a * p0y + b * c1y + c * p2y }
    if i > 0 then lens[i + 1] = lens[i] + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
  end
  local total = lens[N + 1]
  local count = B.GODS + 1
  local spacing = (total - 10) / (count - 1)
  local function at(dist)
    for i = 1, N do
      if lens[i + 1] >= dist then
        local s = (dist - lens[i]) / math.max(lens[i + 1] - lens[i], 1e-6)
        local x = pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * s
        local y = pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * s
        local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        local m = sqrt(dx * dx + dy * dy)
        return x, y, dx / m, dy / m
      end
    end
    local dx, dy = pts[N][1] - pts[N - 1][1], pts[N][2] - pts[N - 1][2]
    local m = sqrt(dx * dx + dy * dy)
    return pts[N][1], pts[N][2], dx / m, dy / m
  end
  B.links = {}
  for i = 1, count do
    local x, y, dx, dy = at(10 + (i - 1) * spacing)
    -- light from the upper right: her pale halo. Hers is a little bigger.
    local k = i == count and 1.12 or 1
    B.links[i] = { x = x, y = y, runs = bakeLink(x, y, dx, dy, 32 * k, 21 * k, 14 * k, 8 * k, 0.6, -0.8) }
  end
  -- odd links over even ones, so they look woven, and hers over all
  B.order = {}
  for i = 2, count - 1, 2 do B.order[#B.order + 1] = i end
  for i = 1, count - 1, 2 do B.order[#B.order + 1] = i end
  B.order[#B.order + 1] = count
  local last = B.links[count]
  B.handX, B.handY = floor(last.x / CW), floor(last.y / CH)
end

-- one per god: shadow, body, shine
B.GODPAL = {
  { C.redTint, C.red, C.warn }, { C.hiTint, C.hi, C.hi }, { C.hiTint, C.ok, C.soft }, { C.blueTint, C.blue, C.info },
  { C.redTint, C.warn, C.hi }, { C.blueTint, C.accent, C.accent }, { C.hiTint, C.soft, C.soft }, { C.blueTint, C.info, C.info },
  { C.redTint, C.red, C.hi }, { C.hiTint, C.ok, C.hi }, { C.blueTint, C.accent, C.info },
}
B.SPENT = { C.panel, C.tie, C.line }
B.FLASH = { C.line, C.text, C.text }
B.HERS = { C.line, C.text, C.text }

-- the Raven Queen, at the right, in cell units
local Q = {}
local function mirror(pts, axis)
  local out = {}
  for i = 1, #pts, 2 do out[i], out[i + 1] = axis * 2 - pts[i], pts[i + 1] end
  return out
end
do
  local AX = 101
  local wingL = { 95, 24, 92, 19, 87, 14, 81, 10, 75, 7, 72, 9, 74, 13, 72, 16, 76, 18, 74, 22, 78, 23, 77, 27, 81, 27, 81, 31,
    84, 30, 85, 34, 88, 32, 90, 36, 92, 32, 94, 35, 95, 30 }
  local wingR = mirror(wingL, AX)
  -- the inside of each wing, a step in from the rim
  local innerL = { 94, 24, 91, 20, 86, 15, 80, 11, 76, 9, 75, 11, 76, 14, 75, 16, 78, 18, 77, 21, 80, 23, 79, 26, 82, 26, 83, 29,
    85, 29, 86, 32, 88, 30, 90, 33, 92, 30, 94, 32 }
  local innerR = mirror(innerL, AX)
  Q.wings = {}
  for _, p in ipairs({ wingL, wingR }) do for _, r in ipairs(bakePoly(p, 1)) do Q.wings[#Q.wings + 1] = r end end
  for _, p in ipairs({ innerL, innerR }) do for _, r in ipairs(bakePoly(p, 2)) do Q.wings[#Q.wings + 1] = r end end
  -- feathers: dark lines from the shoulder out to each finger of the wing
  Q.feathers = {}
  local tips = { { 72, 9 }, { 72, 16 }, { 74, 22 }, { 77, 27 }, { 81, 31 }, { 85, 34 }, { 90, 36 } }
  -- only the last stretch to each tip, so the long flight feathers part at the ends
  for _, tp in ipairs(tips) do
    local fx, fy = tp[1] + (95 - tp[1]) * 0.45, tp[2] + (25 - tp[2]) * 0.45
    Q.feathers[#Q.feathers + 1] = { floor(fx + 0.5), floor(fy + 0.5), tp[1] + 2, tp[2] }
    Q.feathers[#Q.feathers + 1] = { AX * 2 - floor(fx + 0.5), floor(fy + 0.5), AX * 2 - tp[1] - 2, tp[2] }
  end
  -- the top edge of each wing, catching the light
  Q.rim = {}
  local edge = { 95, 23, 92, 18, 87, 13, 81, 9, 75, 7 }
  for i = 1, #edge - 2, 2 do
    Q.rim[#Q.rim + 1] = { edge[i], edge[i + 1], edge[i + 2], edge[i + 3] }
    Q.rim[#Q.rim + 1] = { AX * 2 - edge[i], edge[i + 1], AX * 2 - edge[i + 2], edge[i + 3] }
  end

  Q.robe = bakePoly({ 96, 22, 106, 22, 109, 36, 113, 52, 116, 63, 86, 63, 89, 52, 93, 36 }, 1)
  Q.folds = { { 101, 30, 100, 63 }, { 96, 42, 93, 63 }, { 106, 42, 109, 63 } }
  Q.robeRim = { { 95, 23, 92, 36 }, { 92, 36, 88, 52 }, { 88, 52, 85, 63 } }
  Q.hood = bakePoly({ 101, 9, 98, 10, 95, 13, 94, 17, 93, 22, 95, 26, 107, 26, 109, 22, 108, 17, 107, 13, 104, 10 }, 1)
  Q.face = bakePoly({ 99, 13, 103, 13, 105, 16, 105, 20, 101, 22, 97, 20, 97, 16 }, 1)
  Q.hoodRim = { { 101, 9, 95, 13 }, { 95, 13, 93, 22 } }
  Q.sleeve = bakePoly({ 95, 25, 100, 27, 93, 45, 88, 47, 86, 44 }, 1)
  Q.sleeve2 = bakePoly({ 105, 26, 108, 29, 96, 47, 91, 47 }, 1)
  Q.sleeveRim = { { 95, 26, 87, 44 } }
end

local PANEL_RUNS = { [1] = C.panel }

local function line(l, col) ui.line(l[1], l[2], l[3], l[4], col) end

local function drawQueen(t, lit)
  -- her pale halo, a moon behind the hood
  ui.ellipse(87, 7, 29, 22, C.tie)
  ui.ellipse(89, 8, 25, 20, C.line)
  ui.ellipse(93, 10, 13, 9, C.text)

  drawRuns(Q.wings, { C.tie, C.panel })
  for _, r in ipairs(Q.rim) do line(r, C.line) end

  drawRuns(Q.robe, PANEL_RUNS)
  for _, f in ipairs(Q.folds) do line(f, C.bg) end
  for _, r in ipairs(Q.robeRim) do line(r, C.tie) end
  -- the cloak's hem stirs
  local stir = floor(t / 4) % 4
  for x = 86, 116, 3 do
    if (x + stir) % 4 < 2 then ui.fill(x, 63, 2, 1, C.bg) end
  end

  drawRuns(Q.hood, PANEL_RUNS)
  for _, r in ipairs(Q.hoodRim) do line(r, C.tie) end
  drawRuns(Q.face, { C.bg })
  local eye = C.info
  ui.fill(99, 17, 1, 1, eye)
  ui.fill(103, 17, 1, 1, eye)
  if lit then
    ui.fill(98, 17, 1, 1, C.blue)
    ui.fill(104, 17, 1, 1, C.blue)
  end

  drawRuns(Q.sleeve2, PANEL_RUNS)
  drawRuns(Q.sleeve, PANEL_RUNS)
  for _, r in ipairs(Q.sleeveRim) do line(r, C.tie) end
end

local function linkPal(i, t)
  if i > B.GODS then return B.HERS end
  local g = B.START + B.GAP * (i - 1)
  if t < g then return B.GODPAL[i] end
  if t < g + 1 then return B.FLASH end
  return B.SPENT
end

local function drawBinding(L, t)
  ui.fill(0, 0, L.W, L.H, C.bg)
  for i = 1, #B.stars do
    local s = B.stars[i]
    ui.fill(s.x, s.y, 1, 1, s.bright == 2 and C.line or C.tie)
  end

  -- the swirl: angry until the chain is done, then held
  local tt = math.min(t, M.LENGTH.binding)
  local ramp = tt < B.REACH and B.AWAKE or tt < B.REACH + 5 and B.EASING or B.HELD
  local phase = (tt < B.REACH and tt / 22) or (B.REACH / 22 + (tt - B.REACH) / 60)
  local lit = tt >= B.REACH
  drawSwirl(B.swirl, phase, ramp, 0.1, 0.16, lit and C.accent or C.hi)

  drawQueen(tt, lit)

  for _, i in ipairs(B.order) do drawRuns(B.links[i].runs, linkPal(i, tt)) end
  -- her hands round the last link
  local hx, hy = B.handX, B.handY
  ui.fill(hx + 4, hy - 3, 2, 2, C.line)
  ui.fill(hx + 5, hy - 1, 1, 1, C.tie)
  -- once it's all that's left, it shines
  if lit then
    local k = floor(tt - B.REACH)
    local r = k < 2 and 4 or 5
    ui.fill(hx - r - 2, hy, 2, 1, C.text)
    ui.fill(hx + r + 2, hy, 2, 1, C.text)
    ui.fill(hx, hy - floor(r / 2) - 2, 1, 1, C.text)
    ui.fill(hx, hy + floor(r / 2) + 2, 1, 1, C.text)
    if k >= 2 then
      ui.fill(hx - r - 1, hy - 2, 1, 1, C.line)
      ui.fill(hx + r + 1, hy + 2, 1, 1, C.line)
      ui.fill(hx - r - 1, hy + 2, 1, 1, C.line)
      ui.fill(hx + r + 1, hy - 2, 1, 1, C.line)
    end
  end
end

M.CUES.binding = {}
for i = 1, B.GODS do M.CUES.binding[#M.CUES.binding + 1] = { B.START + B.GAP * (i - 1), "intro_god_fade" } end
M.CUES.binding[#M.CUES.binding + 1] = { B.REACH, "intro_raven" }

-- ================================================================

function M.draw(L, pic, t)
  t = t or 0
  if t < 0 then t = 0 end
  if pic == "oblivion" then drawOblivion(L, t)
  elseif pic == "binding" then drawBinding(L, t)
  end
end

return M
