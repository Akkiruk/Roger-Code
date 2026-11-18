-- models.lua
-- Every shape in Saltgate, as Pine3D models (lists of coloured triangles): city tiles, the sea and pier, cars, people,
-- cash and markers. Boxes copy the winding of Pine3D's own cube, so back-face culling keeps working.

local city = require("sg.city")

local M = {}

local cos, sin = math.cos, math.sin

-- the 12 triangles of a unit cube by corner signs (0 = min, 1 = max), in Pine3D's winding, grouped by face
local CUBE = {
  bottom = { { 0, 0, 0, 1, 0, 1, 0, 0, 1 }, { 0, 0, 0, 1, 0, 0, 1, 0, 1 } },
  top = { { 0, 1, 0, 0, 1, 1, 1, 1, 1 }, { 0, 1, 0, 1, 1, 1, 1, 1, 0 } },
  xneg = { { 0, 0, 0, 0, 0, 1, 0, 1, 0 }, { 0, 0, 1, 0, 1, 1, 0, 1, 0 } },
  xpos = { { 1, 0, 0, 1, 1, 1, 1, 0, 1 }, { 1, 0, 0, 1, 1, 0, 1, 1, 1 } },
  zneg = { { 0, 0, 0, 1, 1, 0, 1, 0, 0 }, { 0, 0, 0, 0, 1, 0, 1, 1, 0 } },
  zpos = { { 0, 0, 1, 1, 0, 1, 0, 1, 1 }, { 1, 0, 1, 1, 1, 1, 0, 1, 1 } },
}

local function poly(list, x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  list[#list + 1] = { x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3, c = c }
end

local function face(list, tris, a, b, c)
  for _, t in ipairs(tris) do
    local x1, y1, z1 = a[t[1] + 1][1], a[t[2] + 1][2], a[t[3] + 1][3]
    local x2, y2, z2 = a[t[4] + 1][1], a[t[5] + 1][2], a[t[6] + 1][3]
    local x3, y3, z3 = a[t[7] + 1][1], a[t[8] + 1][2], a[t[9] + 1][3]
    poly(list, x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  end
  local _ = b
end

--- A box from (x0, y0, z0) to (x1, y1, z1). col: { top, x, z } colours (z defaults to x, top to x).
-- opts.noTop / opts.noBottom (default true) leave faces out.
function M.box(list, x0, y0, z0, x1, y1, z1, top, sx, sz, opts)
  local a = { { x0, y0, z0 }, { x1, y1, z1 } }
  sx = sx or top
  sz = sz or sx
  opts = opts or {}
  if not opts.noTop then face(list, CUBE.top, a, nil, top) end
  if opts.bottom then face(list, CUBE.bottom, a, nil, top) end
  face(list, CUBE.xneg, a, nil, sx)
  face(list, CUBE.xpos, a, nil, sx)
  face(list, CUBE.zneg, a, nil, sz)
  face(list, CUBE.zpos, a, nil, sz)
  return list
end

--- A flat rectangle facing up at height y.
function M.quad(list, x0, z0, x1, z1, y, c)
  poly(list, x0, y, z0, x0, y, z1, x1, y, z1, c)
  poly(list, x0, y, z0, x1, y, z1, x1, y, z0, c)
  return list
end

local C = colors

-- building looks: top, lit side (faces east/west), shaded side (north/south), window bands
M.STYLE = {
  glass = { C.lightGray, C.cyan, C.blue, C.lightBlue },
  white = { C.lightGray, C.white, C.lightGray, C.gray },
  neon = { C.black, C.purple, C.black, C.magenta, C.cyan },
  pastel = { C.white, C.pink, C.orange, C.white },
  concrete = { C.gray, C.lightGray, C.gray, C.black },
  brick = { C.brown, C.orange, C.brown, C.black },
  warehouse = { C.gray, C.lightGray, C.gray, C.blue },
  precinct = { C.lightGray, C.white, C.lightGray, C.blue },
  hospital = { C.lightGray, C.white, C.lightGray, C.red },
  gilt = { C.yellow, C.yellow, C.orange, C.black },
  respray = { C.purple, C.magenta, C.purple, C.yellow },
  crate = { C.red, C.red, C.brown },
  crate_b = { C.blue, C.cyan, C.blue },
  crate_c = { C.green, C.lime, C.green },
  crane = { C.yellow, C.yellow, C.orange },
}

local GROUND = { concrete = C.lightGray, lot = C.green, plaza = C.white, grass = C.lime }

local function building(list, b, ox, oz, lod)
  local x0, z0, x1, z1 = b.x0 - ox, b.z0 - oz, b.x1 - ox, b.z1 - oz
  if b.style == "tree" then
    local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    M.box(list, cx - 0.3, 0, cz - 0.3, cx + 0.3, 2, cz + 0.3, C.brown, C.brown, C.brown, { noTop = true })
    M.box(list, cx - 1.6, 2, cz - 1.6, cx + 1.6, 4.6, cz + 1.6, C.lime, C.green, C.green, { bottom = true })
    return
  end
  local st = M.STYLE[b.style] or M.STYLE.concrete
  M.box(list, x0, 0, z0, x1, b.h, z1, st[1], st[2], st[3])
  if lod or not st[4] or b.h < 5 then return end
  -- window bands: a little proud of the wall so the depth test puts them in front
  local inset = 0.15
  local count = math.min(6, math.floor((b.h - 2) / 3.5))
  local spacing = (b.h - 2) / math.max(1, count)
  for k = 0, count - 1 do
    local y = 1.6 + k * spacing
    local band = st[5] and (k % 2 == 1) and st[5] or st[4]
    M.box(list, x0 - inset, y, z0 - inset, x1 + inset, y + math.min(1.1, spacing * 0.45), z1 + inset, band, band, band,
      { noTop = true })
  end
  if b.style == "gilt" then
    -- a gold crown on the tower
    M.box(list, x0 + 2, b.h, z0 + 2, x1 - 2, b.h + 4, z1 - 2, C.yellow, C.orange, C.yellow)
  elseif b.style == "hospital" then
    local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    M.box(list, cx - 3, b.h, cz - 0.8, cx + 3, b.h + 0.4, cz + 0.8, C.red)
    M.box(list, cx - 0.8, b.h, cz - 3, cx + 0.8, b.h + 0.4, cz + 3, C.red)
  end
end

--- One tile, as a model centred on the tile's middle. lod leaves the small things out.
function M.tile(tile, lod)
  local list = {}
  local P, HALF, SW = city.P, city.HALF, city.SIDEWALK
  local x0, z0 = tile.i * P, tile.j * P
  local ox, oz = x0 + P / 2, z0 + P / 2
  local a, b = -P / 2, P / 2
  -- the roads are not drawn: the ground below the horizon is asphalt, and the sea is drawn round the land instead
  -- sidewalk ring
  local s0, s1 = a + HALF, b - HALF
  local walk = C.lightGray
  local y = 0.12
  M.quad(list, s0, s0, s1, s0 + SW, y, walk)
  M.quad(list, s0, s1 - SW, s1, s1, y, walk)
  M.quad(list, s0, s0 + SW, s0 + SW, s1 - SW, y, walk)
  M.quad(list, s1 - SW, s0 + SW, s1, s1 - SW, y, walk)
  -- the lot
  M.quad(list, s0 + SW, s0 + SW, s1 - SW, s1 - SW, y, GROUND[tile.ground] or C.green)
  if tile.pond then
    local p = tile.pond
    M.quad(list, p.x0 - ox, p.z0 - oz, p.x1 - ox, p.z1 - oz, y + 0.02, C.blue)
  end
  if not lod then
    -- dashed centre lines on the north and west roads (and south/east on the last row/column)
    local function dashesX(z)
      local x = a + HALF + 1
      while x + 2.5 < b - HALF do
        M.quad(list, x, z - 0.15, x + 2.5, z + 0.15, 0.02, C.yellow)
        x = x + 5.5
      end
    end
    local function dashesZ(x)
      local z = a + HALF + 1
      while z + 2.5 < b - HALF do
        M.quad(list, x - 0.15, z, x + 0.15, z + 2.5, 0.02, C.yellow)
        z = z + 5.5
      end
    end
    dashesX(a)
    dashesZ(a)
    if tile.j == city.N - 1 then dashesX(b) end
    if tile.i == city.N - 1 then dashesZ(b) end
    -- a street lamp on two corners
    for _, c in ipairs({ { s0 + 0.5, s0 + 0.5 }, { s1 - 0.5, s1 - 0.5 } }) do
      M.box(list, c[1] - 0.1, 0, c[2] - 0.1, c[1] + 0.1, 4, c[2] + 0.1, C.black, C.black, C.black, { noTop = true })
      M.box(list, c[1] - 0.3, 4, c[2] - 0.3, c[1] + 0.3, 4.3, c[2] + 0.3, C.yellow, C.yellow, C.yellow, { bottom = true })
    end
  end
  for _, bld in ipairs(tile.buildings) do
    building(list, bld, ox, oz, lod)
  end
  return list, ox, oz
end

--- The sea round the land (eight big sheets reaching far enough that the horizon is all water), the pier and its ferry.
function M.waterfront()
  local out = {}
  local lo, hi = -city.EDGE, city.SIZE + city.EDGE
  local far = 900
  local function sheet(x0, z0, x1, z1)
    local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    out[#out + 1] = { model = M.quad({}, x0 - cx, z0 - cz, x1 - cx, z1 - cz, -0.2, C.blue), x = cx, z = cz }
  end
  local edges = { lo - far, lo, hi, hi + far }
  for a = 1, 3 do
    for b = 1, 3 do
      if not (a == 2 and b == 2) then sheet(edges[a], edges[b], edges[a + 1], edges[b + 1]) end
    end
  end
  -- a pale line of surf along the seawall
  local surf = {}
  local mid = (lo + hi) / 2
  M.quad(surf, lo - 1.2 - mid, lo - 1.2 - mid, hi + 1.2 - mid, lo - mid, -0.15, C.lightBlue)
  M.quad(surf, lo - 1.2 - mid, hi - mid, hi + 1.2 - mid, hi + 1.2 - mid, -0.15, C.lightBlue)
  M.quad(surf, lo - 1.2 - mid, lo - mid, lo - mid, hi - mid, -0.15, C.lightBlue)
  M.quad(surf, hi - mid, lo - mid, hi + 1.2 - mid, hi - mid, -0.15, C.lightBlue)
  out[#out + 1] = { model = surf, x = mid, z = mid }
  -- the pier: planks on posts, a ferry at the end
  local p = city.pier
  local px, pz = (p.x0 + p.x1) / 2, (p.z0 + p.z1) / 2
  local pier = {}
  M.quad(pier, p.x0 - px, p.z0 - pz, p.x1 - px, p.z1 - pz, 0.05, C.brown)
  for k = 0, 3 do
    local zz = p.z0 - pz + 8 + k * 10
    M.box(pier, p.x0 - px - 0.4, -0.3, zz - 0.4, p.x0 - px + 0.4, 1, zz + 0.4, C.black, C.brown, C.brown)
    M.box(pier, p.x1 - px - 0.4, -0.3, zz - 0.4, p.x1 - px + 0.4, 1, zz + 0.4, C.black, C.brown, C.brown)
  end
  out[#out + 1] = { model = pier, x = px, z = pz }
  local ferry = {}
  local fx, fz = p.x1 + 9, p.z1 - 12
  M.box(ferry, -3.5, -0.3, -13, 3.5, 2.5, 13, C.white, C.white, C.lightGray)
  M.box(ferry, -2.5, 2.5, -7, 2.5, 5, 6, C.white, C.lightGray, C.white)
  M.box(ferry, -2.6, 3.3, -7.1, 2.6, 4, 6.1, C.black, C.black, C.black, { noTop = true })
  M.box(ferry, -0.8, 5, -1, 0.8, 8, 1, C.black, C.red, C.red)
  out[#out + 1] = { model = ferry, x = fx, z = fz }
  return out
end

-- ---------------------------------------------------------------- things that move

--- Rotate a model about y so local +x points along heading h (forward (cos h, sin h)).
function M.rotated(list, h)
  local c, s = cos(h), sin(h)
  local out = {}
  for _, p in ipairs(list) do
    out[#out + 1] = {
      x1 = p.x1 * c - p.z1 * s, y1 = p.y1, z1 = p.x1 * s + p.z1 * c,
      x2 = p.x2 * c - p.z2 * s, y2 = p.y2, z2 = p.x2 * s + p.z2 * c,
      x3 = p.x3 * c - p.z3 * s, y3 = p.y3, z3 = p.x3 * s + p.z3 * c,
      c = p.c,
    }
  end
  return out
end

--- A car of a type spec, facing +x.
function M.car(spec, colour, wrecked)
  local list = {}
  local L, W = spec.length, spec.width
  local body = wrecked and C.gray or (C[colour] or C.red)
  local glass = wrecked and C.black or (C[spec.cabin] or C.black)
  local hl, hw = L / 2, W / 2
  local ride = 0.35
  local bodyTop = spec.van and 2.2 or (spec.low and 0.95 or 1.05)
  local dark = C.black
  -- wheels: one dark block per axle, a little wider than the body
  M.box(list, hl * 0.55 - 0.38, 0, -hw - 0.06, hl * 0.55 + 0.38, 0.62, hw + 0.06, dark, dark, dark, { noTop = true })
  M.box(list, -hl * 0.6 - 0.38, 0, -hw - 0.06, -hl * 0.6 + 0.38, 0.62, hw + 0.06, dark, dark, dark, { noTop = true })
  M.box(list, -hl, ride, -hw, hl, bodyTop, hw, body, body, body)
  if spec.van then
    M.box(list, hl * 0.45, 1.25, -hw - 0.04, hl + 0.04, 1.95, hw + 0.04, glass, glass, glass, { noTop = true })
  else
    local roof = bodyTop + (spec.low and 0.45 or 0.6)
    local cabin0, cabin1 = -hl * 0.55, hl * 0.25
    M.box(list, cabin0, bodyTop, -hw * 0.82, cabin1, roof, hw * 0.82, body, glass, glass)
    if spec.police and not wrecked then
      M.box(list, -0.5, roof, -hw * 0.6, 0.3, roof + 0.3, 0, C.red, C.red, C.red)
      M.box(list, -0.5, roof, 0, 0.3, roof + 0.3, hw * 0.6, C.blue, C.blue, C.blue)
    elseif spec.sign and not wrecked then
      M.box(list, -0.6, roof, -0.4, 0, roof + 0.35, 0.4, C.yellow, C.black, C.yellow)
    end
  end
  if not wrecked then
    -- headlights and tail lights
    M.box(list, hl, 0.6, -hw * 0.8, hl + 0.06, 0.85, -hw * 0.45, C.yellow, C.yellow, C.yellow)
    M.box(list, hl, 0.6, hw * 0.45, hl + 0.06, 0.85, hw * 0.8, C.yellow, C.yellow, C.yellow)
    M.box(list, -hl - 0.06, 0.6, -hw * 0.8, -hl, 0.85, -hw * 0.5, C.red, C.red, C.red)
    M.box(list, -hl - 0.06, 0.6, hw * 0.5, -hl, 0.85, hw * 0.8, C.red, C.red, C.red)
  end
  return list
end

--- A person facing +x. shirt is a colour name; down lies them flat.
function M.person(shirt, down, legs)
  local list = {}
  local s = C[shirt] or C.red
  if down then
    M.box(list, -0.9, 0, -0.3, 0.55, 0.32, 0.3, s, s, s)
    M.box(list, 0.55, 0, -0.17, 0.9, 0.3, 0.17, C.pink, C.pink, C.pink)
    return list
  end
  local l = C[legs or "black"]
  M.box(list, -0.13, 0, -0.24, 0.13, 0.85, 0.24, l, l, l, { noTop = true })
  M.box(list, -0.17, 0.85, -0.3, 0.17, 1.45, 0.3, s, s, s)
  M.box(list, -0.14, 1.45, -0.14, 0.14, 1.8, 0.14, C.black, C.pink, C.pink)
  M.box(list, 0.14, 1.55, -0.1, 0.17, 1.7, 0.1, C.pink, C.pink, C.pink) -- the face, so you can tell which way they look
  return list
end

--- Mama Juno's noodle stall: a counter under a striped awning, a pot on top. Centred on its counter.
function M.stall()
  local list = {}
  M.box(list, -1.6, 0, -0.25, 1.6, 1.0, 0.25, C.red, C.red, C.brown)
  M.box(list, -0.35, 1.0, -0.2, 0.05, 1.35, 0.2, C.lightGray, C.gray, C.gray)
  M.box(list, -1.6, 0, 0.3, -1.45, 2.5, 0.45, C.black, C.black, C.black, { noTop = true })
  M.box(list, 1.45, 0, 0.3, 1.6, 2.5, 0.45, C.black, C.black, C.black, { noTop = true })
  for k = 0, 3 do
    local c = k % 2 == 0 and C.magenta or C.white
    M.box(list, -1.9 + k * 0.95, 2.5, -0.9, -0.95 + k * 0.95, 2.75, 0.6, c, c, c, { bottom = true })
  end
  return list
end

--- A bundle of cash.
function M.cash()
  local list = {}
  M.box(list, -0.35, 0, -0.2, 0.35, 0.3, 0.2, C.lime, C.green, C.green, { bottom = true })
  M.box(list, -0.05, 0.3, -0.21, 0.05, 0.31, 0.21, C.white, C.white, C.white)
  return list
end

--- A tall light for a job marker.
function M.beacon(colour)
  local list = {}
  local c = C[colour] or C.yellow
  M.box(list, -0.35, 0.2, -0.35, 0.35, 9, 0.35, c, c, c)
  M.quad(list, -2, -2, 2, 2, 0.16, c)
  return list
end

--- Fire on a wreck.
function M.flames()
  local list = {}
  M.box(list, -0.6, 1.1, -0.5, 0.4, 1.9, 0.5, C.orange, C.orange, C.red)
  M.box(list, -0.3, 1.9, -0.25, 0.2, 2.5, 0.25, C.yellow, C.yellow, C.orange)
  return list
end

return M
