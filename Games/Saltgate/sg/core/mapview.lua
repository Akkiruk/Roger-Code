-- core/mapview.lua
-- The maps' picture of the world: each chunk is drawn once into a small raster (what is where, and how high) when it
-- loads; the minimap and the city map then just read rasters, with contour lines so hills show. Curves, bridges and
-- car parks come out as they are, because the raster is stamped from the chunk's own shapes. Pure.
--
--   mapview.raster(chunk [, yield]) -> raster (kept on the chunk as chunk._map)
--   mapview.sample(chunkAt, x, z) -> code, height     chunkAt(x, z) gives the chunk there (or nil)
--   mapview.colour(code, height, heightAbove) -> a colours value
--   mapview.CODES                                     what each code means
-- RES units a pixel; codes are one character each.

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")

local M = {}

M.RES = 2
local N = chunkLib.SIZE / M.RES

M.CODES = {
  W = "deep water", w = "shallow water", g = "grass", k = "rock", s = "sand", l = "lot", p = "plaza", e = "walk",
  r = "road", a = "alley", f = "path", t = "rail", o = "bridge or overpass", m = "ramp", d = "deck", b = "building",
  n = "tunnel", x = "unknown",
}
local GROUND_CODE = { grass = "g", rock = "k", sand = "s", lot = "l", plaza = "p", walk = "e", dirt = "s", rail = "t" }
local ROAD_CODE = { road = "r", avenue = "r", highway = "r", alley = "a", path = "f", rail = "t" }

local floor = math.floor

local function hchar(h)
  return string.char(math.max(0, math.min(255, floor(h + 40.5))))
end

--- Draw a chunk into its raster.
function M.raster(c, yield)
  if c._map then return c._map end
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local codes, heights = {}, {}
  -- the land and the water
  for v = 0, N - 1 do
    local crow, hrow = {}, {}
    local z = z0 + (v + 0.5) * M.RES
    for u = 0, N - 1 do
      local x = x0 + (u + 0.5) * M.RES
      local h = chunkLib.terrainY(c, x, z)
      local code = "g"
      local level = chunkLib.waterAt(c, x, z)
      if level and h < level then
        code = h < level - 3 and "W" or "w"
      else
        local h2 = chunkLib.terrainY(c, x + M.RES, z)
        local h3 = chunkLib.terrainY(c, x, z + M.RES)
        if math.abs(h2 - h) + math.abs(h3 - h) > 2.6 then code = "k" elseif level and h < level + 0.6 then code = "s" end
      end
      crow[u + 1], hrow[u + 1] = code, h
    end
    codes[v + 1], heights[v + 1] = crow, hrow
  end
  if yield then yield() end
  local function px(x, z)
    return floor((x - x0) / M.RES) + 1, floor((z - z0) / M.RES) + 1
  end
  local function set(u, v, code, h)
    local row = codes[v]
    if row and row[u] then
      row[u] = code
      if h then heights[v][u] = h end
    end
  end
  -- painted ground
  for _, g in ipairs(c.ground) do
    local code = GROUND_CODE[g[1]] or "l"
    local bx0, bz0, bx1, bz1 = geom.bounds(g[3])
    local u0, v0 = px(bx0, bz0)
    local u1, v1 = px(bx1, bz1)
    for v = math.max(1, v0), math.min(N, v1) do
      for u = math.max(1, u0), math.min(N, u1) do
        if geom.inPolygon(g[3], x0 + (u - 0.5) * M.RES, z0 + (v - 0.5) * M.RES) then set(u, v, code) end
      end
    end
  end
  -- strips (roads, then bridges and ramps on top): walk the polyline, stamp its width
  local function stamp(pts, width, code)
    local len = geom.polylineLength(pts)
    local s = 0
    local r = width / 2
    while s <= len do
      local x, y, z = geom.polylineAt(pts, s)
      local u0, v0 = px(x - r, z - r)
      local u1, v1 = px(x + r, z + r)
      for v = v0, v1 do
        for u = u0, u1 do
          local cx, cz = x0 + (u - 0.5) * M.RES, z0 + (v - 0.5) * M.RES
          if (cx - x) ^ 2 + (cz - z) ^ 2 <= r * r + 0.5 then set(u, v, code, y) end
        end
      end
      s = s + M.RES * 0.75
    end
  end
  for _, rd in ipairs(c.roads) do stamp(rd[8], rd[4], ROAD_CODE[rd[7]] or "r") end
  for _, rb in ipairs(c.ribbons) do
    local code = (rb[1] == "ramp" or rb[1] == "stairs") and "m" or (rb[1] == "tunnel" and "n" or "o")
    stamp(rb[3], rb[2], code)
  end
  for _, f in ipairs(c.floors) do
    local bx0, bz0, bx1, bz1 = geom.bounds(f[3])
    local u0, v0 = px(bx0, bz0)
    local u1, v1 = px(bx1, bz1)
    for v = math.max(1, v0), math.min(N, v1) do
      for u = math.max(1, u0), math.min(N, u1) do
        if geom.inPolygon(f[3], x0 + (u - 0.5) * M.RES, z0 + (v - 0.5) * M.RES) then set(u, v, "d", math.max(f[2], heights[v][u])) end
      end
    end
  end
  for _, b in ipairs(c.buildings) do
    local r = math.sqrt(b[3] * b[3] + b[4] * b[4]) / 2
    local u0, v0 = px(b[1] - r, b[2] - r)
    local u1, v1 = px(b[1] + r, b[2] + r)
    for v = math.max(1, v0), math.min(N, v1) do
      for u = math.max(1, u0), math.min(N, u1) do
        if geom.inBox(b, x0 + (u - 0.5) * M.RES, z0 + (v - 0.5) * M.RES) then set(u, v, "b") end
      end
    end
  end
  -- pack the rows into strings
  local map = { codes = {}, heights = {}, x0 = x0, z0 = z0 }
  for v = 1, N do
    local hs = {}
    for u = 1, N do hs[u] = hchar(heights[v][u]) end
    map.codes[v] = table.concat(codes[v])
    map.heights[v] = table.concat(hs)
  end
  c._map = map
  return map
end

--- What the map shows at (x, z), and how high it is there.
function M.sample(chunkAt, x, z)
  local c = chunkAt(x, z)
  if not c then return "x", 0 end
  local map = c._map or M.raster(c)
  local u = floor((x - map.x0) / M.RES) + 1
  local v = floor((z - map.z0) / M.RES) + 1
  local row = map.codes[v]
  if not row or u < 1 or u > N then return "x", 0 end
  return row:sub(u, u), map.heights[v]:byte(u) - 40
end

local C = rawget(_G, "colors") or {}
local BASE = {
  W = "blue", w = "cyan", g = "lime", k = "brown", s = "yellow", l = "lightGray", p = "white", e = "lightGray",
  r = "gray", a = "gray", f = "yellow", t = "brown", o = "white", m = "orange", d = "lightGray", b = "black", n = "black",
  x = "blue",
}
-- the darker tone of each, for contour lines
local DARK = { g = "green", k = "black", s = "orange", l = "gray", p = "lightGray", e = "gray", w = "blue" }
M.CONTOUR = 6

--- The colour for a map pixel; a contour line where the height crosses a CONTOUR step from the pixel above.
function M.colour(code, h, hAbove)
  local name = BASE[code] or "blue"
  if hAbove and DARK[code] and floor(h / M.CONTOUR) ~= floor(hAbove / M.CONTOUR) then name = DARK[code] end
  return C[name] or 1
end

return M
