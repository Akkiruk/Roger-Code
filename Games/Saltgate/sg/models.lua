-- models.lua
-- Shapes for Pine3D (lists of coloured triangles): boxes and quads for the world's builders, cars, people, a marker.
-- Boxes copy the winding of Pine3D's own cube, so back-face culling keeps working.


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

--- A tall light for a job marker.
function M.beacon(colour)
  local list = {}
  local c = C[colour] or C.yellow
  M.box(list, -0.35, 0.2, -0.35, 0.35, 9, 0.35, c, c, c)
  M.quad(list, -2, -2, 2, 2, 0.16, c)
  return list
end

return M
