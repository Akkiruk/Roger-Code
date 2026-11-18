-- core/chunkmodel.lua
-- A chunk as triangles for Pine3D: the ground as a height mesh (coloured by what is painted on it, darker where it
-- faces away from the evening sun), water sheets, roads laid along their curves with centre dashes, bridges and
-- overpasses on pillars, car park decks, rotated buildings with window bands, and props. Two levels of detail.
-- Pure: returns plain triangle lists; the renderer turns them into objects.
--
--   chunkmodel.build(chunk, lod [, yield]) -> polys, ox, oz   (polys relative to (ox, 0, oz), the chunk's middle)
-- Stream A owns how the world looks and may replace this builder (render.useBuilder); the chunk format stays.

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")
local mapview = require("sg.core.mapview")
local models = require("sg.models")

local M = {}

local C = rawget(_G, "colors") or setmetatable({}, { __index = function() return 1 end })
local sqrt, floor, cos, sin = math.sqrt, math.floor, math.cos, math.sin

local function poly(list, x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
  list[#list + 1] = { x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3, c = c }
end

-- ground colours by map code: lit, shaded
local GROUND = {
  g = { "lime", "green" }, k = { "brown", "gray" }, s = { "yellow", "orange" }, l = { "lightGray", "gray" },
  p = { "white", "lightGray" }, e = { "lightGray", "gray" }, w = { "cyan", "blue" }, W = { "blue", "blue" },
  t = { "brown", "gray" },
}
-- the evening sun is low in the west
local SUN_X, SUN_Y, SUN_Z = -0.75, 0.6, -0.28

local function shade(code, nx, ny, nz, steep)
  local pair = GROUND[code] or GROUND.g
  if steep then pair = GROUND.k end
  local lit = nx * SUN_X + ny * SUN_Y + nz * SUN_Z
  return C[lit > 0.55 and pair[1] or pair[2]]
end

--- The terrain mesh, every `stride` height samples.
local function terrain(list, c, ox, oz, stride)
  local n = chunkLib.HEIGHT_N
  local h = c.heights
  local step = chunkLib.SIZE / (n - 1)
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local map = c._map or mapview.raster(c)
  local function H(i, j) return h and h[j * n + i + 1] or 0 end
  local function codeAt(x, z)
    local u = floor((x - x0) / mapview.RES) + 1
    local v = floor((z - z0) / mapview.RES) + 1
    local row = map.codes[v]
    local code = row and row:sub(u, u) or "g"
    -- roads and buildings sit on top: under them the ground is plain
    if code == "r" or code == "a" or code == "b" or code == "o" or code == "m" or code == "d" or code == "f" or code == "n" then
      return "l"
    end
    return code
  end
  if not h then
    -- flat: two triangles
    local cc = C.lime
    local a, b = -chunkLib.SIZE / 2, chunkLib.SIZE / 2
    poly(list, a, 0, a, a, 0, b, b, 0, b, cc)
    poly(list, a, 0, a, b, 0, b, b, 0, a, cc)
    return
  end
  for j = 0, n - 2, stride do
    for i = 0, n - 2, stride do
      local i1, j1 = math.min(n - 1, i + stride), math.min(n - 1, j + stride)
      local xa, xb = x0 + i * step - ox, x0 + i1 * step - ox
      local za, zb = z0 + j * step - oz, z0 + j1 * step - oz
      local y00, y10, y01, y11 = H(i, j), H(i1, j), H(i, j1), H(i1, j1)
      local w = (i1 - i) * step
      local code = codeAt((xa + xb) / 2 + ox, (za + zb) / 2 + oz)
      -- two triangles, each shaded by its own slope
      local function tri(ax, ay, az, bx, by, bz, cx_, cy, cz)
        local ux, uy, uz = bx - ax, by - ay, bz - az
        local vx, vy, vz = cx_ - ax, cy - ay, cz - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local len = sqrt(nx * nx + ny * ny + nz * nz)
        if len == 0 then len = 1 end
        if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
        nx, ny, nz = nx / len, ny / len, nz / len
        poly(list, ax, ay, az, bx, by, bz, cx_, cy, cz, shade(code, nx, ny, nz, ny < 0.62))
      end
      tri(xa, y00, za, xa, y01, zb, xb, y11, zb)
      tri(xa, y00, za, xb, y11, zb, xb, y10, za)
      local _ = w
    end
  end
end

--- A strip along a 3D polyline, lifted a little, every `every` units.
local function strip(list, pts, width, lift, colour, ox, oz, every)
  local hw = width / 2
  local stride = 3 * (every or 1)
  for i = 1, #pts - 3, stride do
    local j = math.min(i + stride, #pts - 2)
    local ax, ay, az = pts[i], pts[i + 1] + lift, pts[i + 2]
    local bx, by, bz = pts[j], pts[j + 1] + lift, pts[j + 2]
    local dx, dz = bx - ax, bz - az
    local len = sqrt(dx * dx + dz * dz)
    if len > 0.01 then
      local rx, rz = -dz / len * hw, dx / len * hw
      -- a quad from a to b, facing up (wound like models.quad)
      local p1x, p1z = ax - rx - ox, az - rz - oz
      local p2x, p2z = ax + rx - ox, az + rz - oz
      local p3x, p3z = bx + rx - ox, bz + rz - oz
      local p4x, p4z = bx - rx - ox, bz - rz - oz
      poly(list, p1x, ay, p1z, p2x, ay, p2z, p3x, by, p3z, colour)
      poly(list, p1x, ay, p1z, p3x, by, p3z, p4x, by, p4z, colour)
    end
  end
end

--- Is a triangle facing up the right way for Pine3D's culling? Flip it if not (strips go either way along a road).
local function faceUp(list, from)
  for i = from, #list do
    local p = list[i]
    local ux, uz = p.x2 - p.x1, p.z2 - p.z1
    local vx, vz = p.x3 - p.x1, p.z3 - p.z1
    -- models.quad's winding has a negative cross (x, z) for an up face
    if ux * vz - uz * vx > 0 then
      p.x2, p.x3 = p.x3, p.x2
      p.y2, p.y3 = p.y3, p.y2
      p.z2, p.z3 = p.z3, p.z2
    end
  end
end

local function dashes(list, pts, ox, oz)
  local len = geom.polylineLength(pts)
  local s = 2
  while s + 2 < len do
    local x, y, z, dx, dz = geom.polylineAt(pts, s)
    local x2, y2, z2 = geom.polylineAt(pts, s + 2.2)
    strip(list, { x, y, z, x2, y2, z2 }, 0.3, 0.3, C.yellow, ox, oz)
    local _ = dx and dz
    s = s + 10
  end
end

local ROAD_COLOUR = { road = "gray", avenue = "gray", highway = "gray", alley = "gray", path = "yellow", rail = "brown" }

local function building(list, b, c, ox, oz, lod)
  local base = b[6]
  if base == chunkLib.TERRAIN then base = chunkLib.terrainY(c, b[1], b[2]) - 0.3 end
  local local_ = {}
  local st = models.STYLE[b[8]] or models.STYLE.concrete
  local w, d, h = b[3], b[4], b[7]
  models.box(local_, -w / 2, base, -d / 2, w / 2, base + h + 0.3, d / 2, st[1], st[2], st[3])
  if not lod and st[4] and h >= 5 then
    local count = math.min(5, floor((h - 2) / 3.5))
    local spacing = (h - 2) / math.max(1, count)
    for k = 0, count - 1 do
      local y = base + 1.9 + k * spacing
      local band = st[5] and (k % 2 == 1) and st[5] or st[4]
      models.box(local_, -w / 2 - 0.15, y, -d / 2 - 0.15, w / 2 + 0.15, y + math.min(1.1, spacing * 0.45), d / 2 + 0.15,
        band, band, band, { noTop = true })
    end
  end
  for _, p in ipairs(models.rotated(local_, b[5])) do
    p.x1, p.x2, p.x3 = p.x1 + b[1] - ox, p.x2 + b[1] - ox, p.x3 + b[1] - ox
    p.z1, p.z2, p.z3 = p.z1 + b[2] - oz, p.z2 + b[2] - oz, p.z3 + b[2] - oz
    list[#list + 1] = p
  end
end

local function prop(list, p, c, ox, oz)
  local kind, x, z = p[1], p[2], p[3]
  local y = p[5]
  if y == chunkLib.TERRAIN then y = chunkLib.terrainY(c, x, z) end
  local lx, lz = x - ox, z - oz
  if kind == "lamp" then
    models.box(list, lx - 0.1, y, lz - 0.1, lx + 0.1, y + 4, lz + 0.1, C.black, C.black, C.black, { noTop = true })
    models.box(list, lx - 0.3, y + 4, lz - 0.3, lx + 0.3, y + 4.3, lz + 0.3, C.yellow, C.yellow, C.yellow, { bottom = true })
  elseif kind == "tree" then
    models.box(list, lx - 0.3, y, lz - 0.3, lx + 0.3, y + 2, lz + 0.3, C.brown, C.brown, C.brown, { noTop = true })
    models.box(list, lx - 1.6, y + 2, lz - 1.6, lx + 1.6, y + 4.6, lz + 1.6, C.lime, C.green, C.green, { bottom = true })
  elseif kind == "pillar" then
    models.box(list, lx - 0.5, y, lz - 0.5, lx + 0.5, y + 9, lz + 0.5, C.lightGray, C.gray, C.gray)
  else
    models.box(list, lx - 0.4, y, lz - 0.4, lx + 0.4, y + 0.9, lz + 0.4, C.orange, C.brown, C.brown)
  end
end

--- Triangles for a chunk. lod "full" or "low".
function M.build(c, lod, yield)
  local list = {}
  local low = lod == "low"
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local ox, oz = x0 + chunkLib.SIZE / 2, z0 + chunkLib.SIZE / 2
  mapview.raster(c, yield)
  terrain(list, c, ox, oz, low and 8 or 2)
  if yield then yield() end
  -- water: the chunk's sheets at their level (the land above shows through the depth test)
  for _, w in ipairs(c.water) do
    local pts = w[2]
    local level = w[1] - 0.05
    local start = #list + 1
    for i = 3, #pts / 2 - 1 do
      poly(list, pts[1] - ox, level, pts[2] - oz, pts[i * 2 - 1] - ox, level, pts[i * 2] - oz,
        pts[i * 2 + 1] - ox, level, pts[i * 2 + 2] - oz, C.blue)
    end
    local _ = start
  end
  faceUp(list, 1)
  -- roads
  local start = #list + 1
  for _, rd in ipairs(c.roads) do
    strip(list, rd[8], rd[4], 0.25, C[ROAD_COLOUR[rd[7]] or "gray"], ox, oz, low and 3 or 1)
    if not low and (rd[7] == "road" or rd[7] == "avenue" or rd[7] == "highway") then dashes(list, rd[8], ox, oz) end
  end
  -- bridges, overpasses, ramps: a deck, and pillars down to the ground
  for _, rb in ipairs(c.ribbons) do
    local colour = (rb[1] == "ramp") and C.yellow or C.lightGray
    strip(list, rb[3], rb[2] + 0.6, 0.12, colour, ox, oz, low and 2 or 1)
  end
  for _, f in ipairs(c.floors) do
    local pts = f[3]
    for i = 3, #pts / 2 - 1 do
      poly(list, pts[1] - ox, f[2] + 0.1, pts[2] - oz, pts[i * 2 - 1] - ox, f[2] + 0.1, pts[i * 2] - oz,
        pts[i * 2 + 1] - ox, f[2] + 0.1, pts[i * 2 + 2] - oz, C.lightGray)
    end
  end
  faceUp(list, start)
  if not low then
    for _, rb in ipairs(c.ribbons) do
      if rb[1] ~= "tunnel" then
        local len = geom.polylineLength(rb[3])
        local s = 4
        while s < len - 2 do
          local x, y, z = geom.polylineAt(rb[3], s)
          local gy = chunkLib.terrainY(c, x, z)
          if y - gy > 1.5 then
            models.box(list, x - ox - 0.5, gy, z - oz - 0.5, x - ox + 0.5, y - 0.2, z - oz + 0.5, C.gray, C.gray, C.lightGray,
              { noTop = true })
          end
          s = s + 12
        end
      end
    end
  end
  if yield then yield() end
  for _, b in ipairs(c.buildings) do building(list, b, c, ox, oz, low) end
  if not low then
    for _, p in ipairs(c.props) do prop(list, p, c, ox, oz) end
  end
  return list, ox, oz
end

return M
