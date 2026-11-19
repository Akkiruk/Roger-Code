-- world/chunkmodel.lua
-- A chunk of the real city as triangles for Pine3D: the ground (coloured by what is on it, shaded by its slope), sea
-- sheets, roads along their curves with kerbs and centre dashes, rails, bridges and ramps on pillars, tunnels with walls
-- and roofs, car-park decks, buildings in their styles (pitched roofs, windows, crowns), landmarks and props.
-- Two levels of detail ("full" near you, "low" further out). Pure: returns plain triangle lists.
--
-- Colours: only these palette slots appear on the world (see world/sky.lua for what each means over the day):
--   white lightGray gray black brown red yellow lime green cyan blue orange, lightBlue = windows and lamps (lit at night),
--   purple/magenta/pink = the sky (never used on the ground).
--
--   chunkmodel.build(chunk, lod [, yield, baseAt]) -> polys, ox, oz   (relative to the chunk's middle)
--   chunkmodel.STYLES

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")
local mapview = require("sg.world.mapview")
local shapes = require("sg.world.shapes")
local landmarks = require("sg.world.landmarks")

local M = {}

local C = rawget(_G, "colors") or setmetatable({}, { __index = function() return 1 end })
local sqrt, floor, cos, sin, abs, max, min = math.sqrt, math.floor, math.cos, math.sin, math.abs, math.max, math.min
local box = shapes.box

local function poly(list, x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  list[#list + 1] = { x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3, c = c }
end

-- ---------------------------------------------------------------- looks
-- lit side (faces east/west), shaded side (north/south), roof colour, roof shape, window band colour, floors a band per
local STYLES = {
  stucco = { C.white, C.lightGray, C.brown, "gable", C.lightBlue },
  brick = { C.red, C.brown, C.gray, "flat", C.lightBlue },
  slate = { C.lightGray, C.gray, C.blue, "gable", C.lightBlue },
  cottage = { C.yellow, C.white, C.red, "gable", C.lightBlue },
  shop = { C.lightGray, C.gray, C.gray, "flat", C.lightBlue, awning = C.red },
  tower = { C.blue, C.black, C.lightGray, "crown", C.lightBlue, dense = true },
  glass = { C.cyan, C.blue, C.lightGray, "flat", C.lightBlue, dense = true },
  stone = { C.white, C.lightGray, C.gray, "flat", C.gray },
  neon = { C.gray, C.black, C.black, "flat", C.lightBlue, trim = C.red, trim2 = C.cyan },
  warehouse = { C.lightGray, C.gray, C.blue, "gablelow", nil },
  factory = { C.red, C.brown, C.gray, "saw", C.gray },
  shed = { C.lightGray, C.gray, C.gray, "flat", nil },
  villa = { C.white, C.lightGray, C.red, "hip", C.lightBlue },
  gilt = { C.yellow, C.brown, C.yellow, "crown", C.lightBlue },
  resort = { C.white, C.cyan, C.cyan, "flat", C.lightBlue },
  hotel = { C.white, C.lightGray, C.cyan, "crown", C.lightBlue, dense = true, trim = C.cyan },
  wood = { C.brown, C.gray, C.gray, "gable", nil },
  hospital = { C.white, C.lightGray, C.white, "cross", C.red },
  precinct = { C.lightGray, C.white, C.lightGray, "flat", C.blue },
  container = { C.red, C.red, C.red, "flat", nil },
  container_b = { C.blue, C.blue, C.blue, "flat", nil },
  container_c = { C.green, C.green, C.green, "flat", nil },
  container_r = { C.yellow, C.yellow, C.yellow, "flat", nil },
  -- inside the rooms
  wall = { C.white, C.lightGray, C.lightGray, "flat", nil },
  lintel = { C.lightGray, C.lightGray, C.lightGray, "flat", nil },
  counter = { C.brown, C.brown, C.lightGray, "flat", nil },
  shelf = { C.brown, C.brown, C.brown, "flat", nil },
  table = { C.brown, C.brown, C.brown, "flat", nil },
  bed = { C.white, C.lightGray, C.cyan, "flat", nil },
  cell = { C.gray, C.black, C.gray, "flat", nil },
  desk = { C.brown, C.gray, C.brown, "flat", nil },
  sofa = { C.red, C.brown, C.red, "flat", nil },
  plinth = { C.lightGray, C.white, C.white, "flat", nil },
  crate = { C.brown, C.gray, C.brown, "flat", nil },
  lift = { C.yellow, C.gray, C.yellow, "flat", nil },
  stage = { C.red, C.brown, C.red, "flat", nil },
  pillar_i = { C.lightGray, C.white, C.lightGray, "flat", nil },
  vault = { C.gray, C.black, C.lightGray, "flat", nil },
  exhibit = { C.yellow, C.orange, C.yellow, "flat", nil },
}
M.STYLES = STYLES
local FALLBACK = STYLES.stone

-- ---------------------------------------------------------------- the ground
local GROUND = {
  g = { C.lime, C.green }, k = { C.brown, C.gray }, s = { C.yellow, C.lightGray }, l = { C.gray, C.black },
  p = { C.white, C.lightGray }, e = { C.lightGray, C.gray }, w = { C.cyan, C.blue }, W = { C.blue, C.blue },
  u = { C.lightGray, C.gray }, d = { C.lightGray, C.gray }, y = { C.brown, C.brown }, t = { C.gray, C.black },
  q = { C.brown, C.brown }, i = { C.white, C.lightGray }, c = { C.red, C.brown }, v = { C.black, C.black },
  r = { C.gray, C.gray }, a = { C.gray, C.gray }, f = { C.yellow, C.lightGray }, b = { C.lightGray, C.gray },
  o = { C.gray, C.gray }, m = { C.gray, C.gray }, n = { C.gray, C.gray }, x = { C.green, C.green },
}
-- the evening sun is low in the west; the shading is baked into the ground, the palette does the rest
local SUN_X, SUN_Y, SUN_Z = -0.75, 0.6, -0.28

local function terrain(list, c, ox, oz, stride, map)
  local n = chunkLib.HEIGHT_N
  local h = c.heights
  local step = chunkLib.SIZE / (n - 1)
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local interior = c.district == "interior"
  local function H(i, j) return h and h[j * n + i + 1] or 0 end
  local function codeAt(x, z)
    local u = floor((x - x0) / mapview.RES) + 1
    local v = floor((z - z0) / mapview.RES) + 1
    local row = map.codes[v]
    return row and row:sub(u, u) or "g"
  end
  if not h then
    local a, b = -chunkLib.SIZE / 2, chunkLib.SIZE / 2
    if interior then
      -- the room's floor: one coloured patch per ground record, the rest is dark
      poly(list, a, -0.02, a, a, -0.02, b, b, -0.02, b, C.black)
      poly(list, a, -0.02, a, b, -0.02, b, b, -0.02, a, C.black)
      for j = 0, 43 do
        local i = 0
        while i < 44 do
          local code = codeAt(x0 + (i + 0.5) * 2, z0 + (j + 0.5) * 2)
          local k = i
          while k + 1 < 44 and codeAt(x0 + (k + 1.5) * 2, z0 + (j + 0.5) * 2) == code do k = k + 1 end
          if code ~= "v" and code ~= "b" then
            local col = (GROUND[code] or GROUND.v)[1]
            local xa, xb, za, zb = x0 + i * 2 - ox, x0 + (k + 1) * 2 - ox, z0 + j * 2 - oz, z0 + (j + 1) * 2 - oz
            poly(list, xa, 0, za, xa, 0, zb, xb, 0, zb, col)
            poly(list, xa, 0, za, xb, 0, zb, xb, 0, za, col)
          end
          i = k + 1
        end
      end
      return
    end
    local cc = C.lime
    poly(list, a, 0, a, a, 0, b, b, 0, b, cc)
    poly(list, a, 0, a, b, 0, b, b, 0, a, cc)
    return
  end
  local function flatAt(i, j)
    local i1, j1 = min(n - 1, i + stride), min(n - 1, j + stride)
    local y = H(i, j)
    if abs(H(i1, j) - y) < 0.03 and abs(H(i, j1) - y) < 0.03 and abs(H(i1, j1) - y) < 0.03 then return y, i1, j1 end
    return nil
  end
  local function cellCode(i, j) return codeAt(x0 + (i + stride / 2) * step, z0 + (j + stride / 2) * step) end
  for j = 0, n - 2, stride do
    local i = 0
    while i <= n - 2 do
      local fy, fi1, fj1 = flatAt(i, j)
      local merged = false
      if fy then
        -- a run of flat cells of one ground at one height is a single rectangle
        local code0 = cellCode(i, j)
        local runEnd = fi1
        while runEnd <= n - 2 do
          local y2, k1 = flatAt(runEnd, j)
          if not y2 or abs(y2 - fy) > 0.03 or cellCode(runEnd, j) ~= code0 then break end
          runEnd = k1
        end
        if runEnd > fi1 then
          local col = (GROUND[code0] or GROUND.g)[1]
          local xa, xb = x0 + i * step - ox, x0 + runEnd * step - ox
          local za, zb = z0 + j * step - oz, z0 + fj1 * step - oz
          poly(list, xa, fy, za, xa, fy, zb, xb, fy, zb, col)
          poly(list, xa, fy, za, xb, fy, zb, xb, fy, za, col)
          i = runEnd
          merged = true
        end
      end
      if not merged then
      local i1, j1 = min(n - 1, i + stride), min(n - 1, j + stride)
      local xa, xb = x0 + i * step - ox, x0 + i1 * step - ox
      local za, zb = z0 + j * step - oz, z0 + j1 * step - oz
      local y00, y10, y01, y11 = H(i, j), H(i1, j), H(i, j1), H(i1, j1)
      local code = codeAt((xa + xb) / 2 + ox, (za + zb) / 2 + oz)
      local pair = GROUND[code] or GROUND.g
      local function tri(ax, ay, az, bx, by, bz, cx_, cy, cz)
        local ux, uy, uz = bx - ax, by - ay, bz - az
        local vx, vy, vz = cx_ - ax, cy - ay, cz - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local len = sqrt(nx * nx + ny * ny + nz * nz)
        if len == 0 then len = 1 end
        if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
        nx, ny, nz = nx / len, ny / len, nz / len
        local p = pair
        if ny < 0.6 and code ~= "d" and code ~= "y" then p = GROUND.k end
        local lit = nx * SUN_X + ny * SUN_Y + nz * SUN_Z
        poly(list, ax, ay, az, bx, by, bz, cx_, cy, cz, lit > 0.5 and p[1] or p[2])
      end
      tri(xa, y00, za, xa, y01, zb, xb, y11, zb)
      tri(xa, y00, za, xb, y11, zb, xb, y10, za)
      i = i1
      end
    end
  end
end

--- A strip along a 3D polyline, lifted a little, every `every` points.
local function strip(list, pts, width, lift, colour, ox, oz, every)
  local hw = width / 2
  local stride = 3 * (every or 1)
  local i = 1
  while i <= #pts - 3 do
    local j = min(i + stride, #pts - 2)
    local ax, ay, az = pts[i], pts[i + 1] + lift, pts[i + 2]
    local bx, by, bz = pts[j], pts[j + 1] + lift, pts[j + 2]
    local dx, dz = bx - ax, bz - az
    local len = sqrt(dx * dx + dz * dz)
    if len > 0.01 then
      local rx, rz = -dz / len * hw, dx / len * hw
      local p1x, p1z = ax - rx - ox, az - rz - oz
      local p2x, p2z = ax + rx - ox, az + rz - oz
      local p3x, p3z = bx + rx - ox, bz + rz - oz
      local p4x, p4z = bx - rx - ox, bz - rz - oz
      poly(list, p1x, ay, p1z, p2x, ay, p2z, p3x, by, p3z, colour)
      poly(list, p1x, ay, p1z, p3x, by, p3z, p4x, by, p4z, colour)
    end
    i = i + stride
    if j == #pts - 2 then break end
  end
end

--- Turn the triangles from `from` on so they face up (strips go either way along a road).
local function faceUp(list, from)
  for i = from, #list do
    local p = list[i]
    local ux, uz = p.x2 - p.x1, p.z2 - p.z1
    local vx, vz = p.x3 - p.x1, p.z3 - p.z1
    if ux * vz - uz * vx > 0 then
      p.x2, p.x3 = p.x3, p.x2
      p.y2, p.y3 = p.y3, p.y2
      p.z2, p.z3 = p.z3, p.z2
    end
  end
end

--- Two-sided wall strips along a polyline at lateral offset `off` (left/right of travel), from y+y0 to y+y1.
local function wall(list, pts, off, y0, y1, colour, ox, oz, every)
  local stride = 3 * (every or 1)
  local i = 1
  while i <= #pts - 3 do
    local j = min(i + stride, #pts - 2)
    local ax, ay, az, bx, by, bz = pts[i], pts[i + 1], pts[i + 2], pts[j], pts[j + 1], pts[j + 2]
    local dx, dz = bx - ax, bz - az
    local len = sqrt(dx * dx + dz * dz)
    if len > 0.01 then
      local rx, rz = -dz / len * off, dx / len * off
      shapes.flat(list, ax + rx - ox, ay + y0, az + rz - oz, bx + rx - ox, by + y0, bz + rz - oz, bx + rx - ox, by + y1, bz + rz - oz,
        ax + rx - ox, ay + y1, az + rz - oz, colour)
    end
    i = i + stride
    if j == #pts - 2 then break end
  end
end

local function dashes(list, pts, ox, oz, colour, width)
  local len = geom.polylineLength(pts)
  local s = 2
  while s + 2 < len do
    local x, y, z = geom.polylineAt(pts, s)
    local x2, y2, z2 = geom.polylineAt(pts, s + 2.4)
    strip(list, { x, y, z, x2, y2, z2 }, width or 0.3, 0.3, colour, ox, oz)
    s = s + 9
  end
end

local ROAD_COLOUR = { road = C.gray, avenue = C.gray, highway = C.gray, alley = C.gray, path = C.yellow }

-- ---------------------------------------------------------------- buildings
local function building(list, b, c, ox, oz, lod)
  local style = b[8]
  if style == "void" then return end
  local st = STYLES[style] or FALLBACK
  local base = b[6]
  if base == chunkLib.TERRAIN then base = chunkLib.terrainY(c, b[1], b[2]) - 0.3 end
  local l = {}
  local w, d, h = b[3], b[4], b[7]
  local lit, shade, roof, shape, band = st[1], st[2], st[3], st[4], st[5]
  local roofY = base + h
  local interior = c.district == "interior"
  if interior then
    box(l, -w / 2, base, -d / 2, w / 2, roofY, d / 2, lit, lit, shade)
  elseif lod or shape == "flat" or shape == "crown" or shape == "cross" or shape == "saw" then
    box(l, -w / 2, base, -d / 2, w / 2, roofY, d / 2, roof, lit, shade)
  else
    box(l, -w / 2, base, -d / 2, w / 2, roofY, d / 2, roof, lit, shade, { noTop = true })
  end
  if not lod and not interior then
    if shape == "gable" then
      shapes.gable(l, -w / 2 - 0.3, roofY, -d / 2 - 0.3, w / 2 + 0.3, d / 2 + 0.3, min(d, w) * 0.32, roof, lit, true)
    elseif shape == "gablelow" then
      shapes.gable(l, -w / 2, roofY, -d / 2, w / 2, d / 2, 1.8, roof, lit, true)
    elseif shape == "hip" then
      shapes.pyramid(l, -w / 2 - 0.4, roofY, -d / 2 - 0.4, w / 2 + 0.4, d / 2 + 0.4, min(d, w) * 0.28, roof, roof)
    elseif shape == "saw" then
      local teeth = max(2, floor(w / 8))
      for k = 0, teeth - 1 do
        local x0 = -w / 2 + k * w / teeth
        shapes.gable(l, x0, roofY, -d / 2, x0 + w / teeth, d / 2, 2.4, roof, lit, false)
      end
    elseif shape == "crown" then
      box(l, -w / 2 + 1.2, roofY, -d / 2 + 1.2, w / 2 - 1.2, roofY + min(4, h * 0.12), d / 2 - 1.2, roof, lit, shade)
      if style == "tower" and h > 30 then box(l, -0.2, roofY, -0.2, 0.2, roofY + 6, 0.2, C.black, C.black, C.black) end
    elseif shape == "cross" then
      box(l, -3, roofY, -0.8, 3, roofY + 0.4, 0.8, C.red, C.red, C.red)
      box(l, -0.8, roofY, -3, 0.8, roofY + 0.4, 3, C.red, C.red, C.red)
    end
    if band and h >= 5 and w >= 5 then
      local count = min(st.dense and 4 or 2, floor((h - 1.5) / 3.6))
      if count >= 1 then
        local spacing = (h - 2) / max(1, count)
        for k = 0, count - 1 do
          local y = base + 1.7 + k * spacing
          local bh = min(1.1, spacing * 0.45)
          local colour = band
          if st.trim and k % 2 == 1 then colour = (st.trim2 and k % 4 == 3) and st.trim2 or st.trim end
          box(l, -w / 2 - 0.12, y, -d / 2 - 0.12, w / 2 + 0.12, y + bh, d / 2 + 0.12, colour, colour, colour, { noTop = true })
        end
      end
    end
    if st.awning and h >= 4 then
      box(l, -w / 2 - 0.4, base + 3.0, -d / 2 - 0.5, w / 2 + 0.4, base + 3.4, d / 2 + 0.5, st.awning, st.awning, st.awning, { noTop = false })
    end
  end
  for _, p in ipairs(shapes.rotate(l, b[5])) do
    p.x1, p.x2, p.x3 = p.x1 + b[1] - ox, p.x2 + b[1] - ox, p.x3 + b[1] - ox
    p.z1, p.z2, p.z3 = p.z1 + b[2] - oz, p.z2 + b[2] - oz, p.z3 + b[2] - oz
    list[#list + 1] = p
  end
end

-- ---------------------------------------------------------------- props
local function prop(list, p, c, ox, oz)
  local kind, x, z = p[1], p[2], p[3]
  local y = p[5]
  if y == chunkLib.TERRAIN then y = chunkLib.terrainY(c, x, z) end
  local lx, lz = x - ox, z - oz
  if kind == "lamp" then
    box(list, lx - 0.09, y, lz - 0.09, lx + 0.09, y + 4.2, lz + 0.09, C.black, C.black, C.black, { noTop = true })
    box(list, lx - 0.32, y + 4.2, lz - 0.32, lx + 0.32, y + 4.55, lz + 0.32, C.lightBlue, C.lightBlue, C.lightBlue, { bottom = true })
  elseif kind == "tree" then
    box(list, lx - 0.25, y, lz - 0.25, lx + 0.25, y + 2, lz + 0.25, C.brown, C.brown, C.brown, { noTop = true })
    shapes.pyramid(list, lx - 1.7, y + 1.6, lz - 1.7, lx + 1.7, lz + 1.7, 3.6, C.green, C.lime)
    shapes.pyramid(list, lx - 1.2, y + 3.4, lz - 1.2, lx + 1.2, lz + 1.2, 2.6, C.lime, C.green)
  elseif kind == "palm" then
    box(list, lx - 0.18, y, lz - 0.18, lx + 0.18, y + 4.6, lz + 0.18, C.brown, C.brown, C.brown, { noTop = true })
    for k = 0, 3 do
      local a = k * math.pi / 2 + (p[4] or 0)
      local dx, dz = cos(a), sin(a)
      shapes.flat(list, lx, y + 4.6, lz, lx + dx * 2.4, y + 4.1, lz + dz * 2.4, lx + dx * 2.4 - dz * 0.5, y + 4.0, lz + dz * 2.4 + dx * 0.5,
        lx - dz * 0.5, y + 4.6, lz + dx * 0.5, C.green)
    end
  elseif kind == "bench" then
    local a = p[4] or 0
    local dx, dz = cos(a) * 0.8, sin(a) * 0.8
    local nx, nz = -sin(a) * 0.25, cos(a) * 0.25
    shapes.flat(list, lx - dx - nx, y + 0.5, lz - dz - nz, lx + dx - nx, y + 0.5, lz + dz - nz, lx + dx + nx, y + 0.5, lz + dz + nz, lx - dx + nx, y + 0.5, lz - dz + nz, C.brown)
    shapes.flat(list, lx - dx - nx, y + 0.5, lz - dz - nz, lx + dx - nx, y + 0.5, lz + dz - nz, lx + dx - nx, y + 1.0, lz + dz - nz, lx - dx - nx, y + 1.0, lz - dz - nz, C.brown)
  elseif kind == "bollard" then
    box(list, lx - 0.15, y, lz - 0.15, lx + 0.15, y + 0.8, lz + 0.15, C.yellow, C.yellow, C.black)
  elseif kind == "pillar" then
    local height = p[4] or 9
    box(list, lx - 0.5, y, lz - 0.5, lx + 0.5, y + height, lz + 0.5, C.lightGray, C.gray, C.gray)
  else
    box(list, lx - 0.4, y, lz - 0.4, lx + 0.4, y + 0.9, lz + 0.4, C.orange, C.brown, C.brown)
  end
end

-- ---------------------------------------------------------------- the build
local function seaFloorY(c, x, z)
  return chunkLib.terrainY(c, x, z)
end

--- Pillars under a deck: every `every` units, down to the ground.
local function pillars(list, c, rb, ox, oz, every)
  local pts = rb[3]
  local len = geom.polylineLength(pts)
  local kind = rb[1]
  local s = every * 0.5
  while s < len - 2 do
    local x, y, z, dx, dz = geom.polylineAt(pts, s)
    local gy = seaFloorY(c, x, z)
    if y - gy > 1.6 then
      local w = rb[2]
      if kind == "bridge" and w > 8 then
        local rx, rz = -dz * w * 0.28, dx * w * 0.28
        for _, sgn in ipairs({ -1, 1 }) do
          shapes.cyl(list, x + rx * sgn - ox, gy, z + rz * sgn - oz, 1.0, 0.85, y - gy - 0.9, 6, C.lightGray, C.gray, nil)
        end
        box(list, x - ox - 0.5 - abs(rx) * 0, y - 1.7, z - oz - 0.5, x - ox + 0.5, y - 0.9, z - oz + 0.5, C.gray, C.gray, C.gray, { noTop = true })
      elseif kind ~= "pier" or (s % (every * 2) < every) then
        box(list, x - ox - 0.55, gy, z - oz - 0.55, x - ox + 0.55, y - 0.9, z - oz + 0.55, C.gray, C.lightGray, C.gray, { noTop = true })
      end
    end
    s = s + every
  end
end

local function ribbon(list, c, rb, ox, oz, lod)
  local kind, w, pts = rb[1], rb[2], rb[3]
  local every = lod and 3 or 1
  if kind == "tunnel" then
    local colour = C.gray
    local start = #list + 1
    strip(list, pts, w, 0.08, colour, ox, oz, every)
    faceUp(list, start)
    wall(list, pts, w / 2 + 0.2, 0, 5.4, C.lightGray, ox, oz, every * 2)
    wall(list, pts, -(w / 2 + 0.2), 0, 5.4, C.lightGray, ox, oz, every * 2)
    -- the roof, a strip seen from both sides
    local i = 1
    while i <= #pts - 3 do
      local j = min(i + 6, #pts - 2)
      local ax, ay, az, bx, by, bz = pts[i], pts[i + 1] + 5.4, pts[i + 2], pts[j], pts[j + 1] + 5.4, pts[j + 2]
      local dx, dz = bx - ax, bz - az
      local len = sqrt(dx * dx + dz * dz)
      if len > 0.01 then
        local rx, rz = -dz / len * (w / 2 + 0.6), dx / len * (w / 2 + 0.6)
        shapes.flat(list, ax - rx - ox, ay, az - rz - oz, ax + rx - ox, ay, az + rz - oz, bx + rx - ox, by, bz + rz - oz, bx - rx - ox, by, bz - rz - oz, C.gray)
      end
      i = i + 6
      if j == #pts - 2 then break end
    end
    -- the portal frames at both ends
    for _, e in ipairs({ { 1, 4 }, { #pts - 2, -1 } }) do
      local x, y, z = pts[e[1]], pts[e[1] + 1], pts[e[1] + 2]
      local x2, z2 = pts[e[1] + (e[2] > 0 and 3 or -3)], pts[e[1] + (e[2] > 0 and 5 or -1)]
      local dx, dz = x2 - x, z2 - z
      local len = sqrt(dx * dx + dz * dz)
      if len > 0 then
        dx, dz = dx / len, dz / len
        local rx, rz = -dz * (w / 2 + 0.6), dx * (w / 2 + 0.6)
        shapes.flat(list, x - rx - ox, y, z - rz - oz, x + rx - ox, y, z + rz - oz, x + rx - ox, y + 6.6, z + rz - oz, x - rx - ox, y + 6.6, z - rz - oz, C.lightGray)
        shapes.flat(list, x - rx * 0.86 - ox, y, z - rz * 0.86 - oz, x + rx * 0.86 - ox, y, z + rz * 0.86 - oz, x + rx * 0.86 - ox, y + 5.4, z + rz * 0.86 - oz,
          x - rx * 0.86 - ox, y + 5.4, z - rz * 0.86 - oz, C.black)
      end
    end
    return
  end
  local top = (kind == "pier") and C.brown or ((kind == "stairs") and C.lightGray or C.gray)
  local start = #list + 1
  strip(list, pts, w, 0.12, top, ox, oz, every)
  faceUp(list, start)
  if kind == "pier" then
    wall(list, pts, w / 2, -0.9, 0.0, C.brown, ox, oz, every * 2)
    wall(list, pts, -w / 2, -0.9, 0.0, C.brown, ox, oz, every * 2)
  else
    wall(list, pts, w / 2, -1.1, 0.9, C.lightGray, ox, oz, every * 2)
    wall(list, pts, -w / 2, -1.1, 0.9, C.lightGray, ox, oz, every * 2)
  end
  if not lod then pillars(list, c, rb, ox, oz, kind == "pier" and 14 or 12) end
end

--- Triangles for a chunk. lod "full" or "low". baseAt(x, z) says what the ground is made of here (see mapview).
function M.build(c, lod, yield, baseAt)
  local list = {}
  local low = lod == "low"
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local ox, oz = x0 + chunkLib.SIZE / 2, z0 + chunkLib.SIZE / 2
  local map = mapview.raster(c, yield, baseAt)
  terrain(list, c, ox, oz, low and 8 or 2, map)
  if yield then yield() end
  for _, w in ipairs(c.water) do
    local pts = w[2]
    local level = w[1] - 0.05
    for i = 3, #pts / 2 - 1 do
      poly(list, pts[1] - ox, level, pts[2] - oz, pts[i * 2 - 1] - ox, level, pts[i * 2] - oz, pts[i * 2 + 1] - ox, level, pts[i * 2 + 2] - oz, C.blue)
    end
  end
  faceUp(list, 1)
  -- roads, then their kerbs, centre lines and rails
  local start = #list + 1
  local every = low and 3 or 1
  local decks = {}
  for _, rb in ipairs(c.ribbons) do decks[rb[3][1] .. "," .. rb[3][3]] = true end
  for _, rd in ipairs(c.roads) do
    local kind = rd[7]
    local deckish = decks[rd[8][1] .. "," .. rd[8][3]] == true
    local pts = rd[8]
    if kind == "rail" then
      if not deckish then
        strip(list, pts, rd[4], 0.2, C.brown, ox, oz, every)
        if not low then
          strip(list, pts, 0.28, 0.32, C.lightGray, ox, oz, 1)
        end
      end
    elseif not deckish then
      if not low and (kind == "road" or kind == "avenue" or kind == "highway") then
        strip(list, pts, rd[4] + 3.2, 0.1, C.lightGray, ox, oz, 1)
      end
      strip(list, pts, rd[4], 0.25, ROAD_COLOUR[kind] or C.gray, ox, oz, every)
      if not low and (kind == "road" or kind == "avenue" or kind == "highway") then dashes(list, pts, ox, oz, C.yellow, 0.3) end
    end
  end
  for _, f in ipairs(c.floors) do
    local pts = f[3]
    local colour = (f[1] == "dock") and C.brown or C.lightGray
    for i = 3, #pts / 2 - 1 do
      poly(list, pts[1] - ox, f[2] + 0.1, pts[2] - oz, pts[i * 2 - 1] - ox, f[2] + 0.1, pts[i * 2] - oz, pts[i * 2 + 1] - ox, f[2] + 0.1, pts[i * 2 + 2] - oz, colour)
    end
  end
  faceUp(list, start)
  for _, f in ipairs(c.floors) do
    if not low and (f[1] == "deck" or f[1] == "dock") then
      local pts = f[3]
      local n = #pts / 2
      for i = 1, n do
        local j = i % n + 1
        local ax, az, bx, bz = pts[i * 2 - 1] - ox, pts[i * 2] - oz, pts[j * 2 - 1] - ox, pts[j * 2] - oz
        shapes.flat(list, ax, f[2] - 1.0, az, bx, f[2] - 1.0, bz, bx, f[2] + 0.65, bz, ax, f[2] + 0.65, az, f[1] == "deck" and C.lightGray or C.brown)
      end
    end
  end
  for _, rb in ipairs(c.ribbons) do ribbon(list, c, rb, ox, oz, low) end
  if yield then yield() end
  for _, b in ipairs(c.buildings) do building(list, b, c, ox, oz, low) end
  for _, lm in ipairs(c.landmarks) do
    local model = landmarks.build(lm[1])
    if model then
      local y = lm[5]
      if y == chunkLib.TERRAIN then y = chunkLib.terrainY(c, lm[2], lm[3]) end
      for _, p in ipairs(shapes.move(shapes.rotate(model, lm[4]), lm[2] - ox, y, lm[3] - oz)) do list[#list + 1] = p end
    end
  end
  if not low then
    for _, p in ipairs(c.props) do prop(list, p, c, ox, oz) end
    for _, d in ipairs(c.doors) do
      if d[4] ~= "@exit" then
        local lx, lz, y = d[1] - ox, d[2] - oz, d[3]
        box(list, lx - 0.25, y, lz - 0.25, lx + 0.25, y + 3.4, lz + 0.25, C.yellow, C.yellow, C.yellow, { noTop = true })
        box(list, lx - 0.6, y + 3.4, lz - 0.6, lx + 0.6, y + 4.2, lz + 0.6, C.lightBlue, C.lightBlue, C.yellow, { bottom = true })
      else
        local lx, lz, y = d[1] - ox, d[2] - oz, d[3]
        box(list, lx - 1.6, y + 0.02, lz - 0.5, lx + 1.6, y + 0.08, lz + 0.5, C.yellow, C.yellow, C.yellow)
      end
    end
  end
  return list, ox, oz
end

return M
