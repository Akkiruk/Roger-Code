-- world/mapview.lua
-- Fork of core/mapview.lua for the real city. Each chunk is drawn once into a small raster (what is where and how high)
-- when it loads; the 3D ground colours, the minimap and the city map all read it. Differences from core's:
--   * the ground's base depends on the district (opts.baseAt): paved city, mixed yards, grass, rock, sand;
--   * interior floors (wood, tile, carpet) and the void round a room;
--   * piers and docks have their own codes.
-- Pure.
--
--   mapview.raster(chunk [, yield, baseAt]) -> raster (kept on the chunk as chunk._map)
--   mapview.sample(chunkAt, x, z) -> code, height
--   mapview.colour(code, height, heightAbove) -> a colours value     (the 16-colour map palette)
--   mapview.CODES

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")

local M = {}

M.RES = 2
local N = chunkLib.SIZE / M.RES

M.CODES = {
  W = "deep water", w = "shallow water", g = "grass", k = "rock", s = "sand", l = "lot", p = "plaza", e = "walk",
  r = "road", a = "alley", f = "path", t = "rail", o = "bridge or overpass", m = "ramp", d = "deck", b = "building",
  n = "tunnel", x = "unknown", u = "pavement", q = "wood floor", i = "tile floor", c = "carpet", v = "void", y = "pier",
}
local GROUND_CODE = {
  grass = "g", rock = "k", sand = "s", lot = "l", plaza = "p", walk = "e", dirt = "s", rail = "t", wood = "q", tile = "i", carpet = "c",
  dock = "d",
}
local ROAD_CODE = { road = "r", avenue = "r", highway = "r", alley = "a", path = "f", rail = "t" }
local RIBBON_CODE = { ramp = "m", stairs = "m", tunnel = "n", pier = "y" }

local floor = math.floor

local function hchar(h)
  return string.char(math.max(0, math.min(255, floor(h + 40.5))))
end

--- Draw a chunk into its raster. baseAt(x, z) -> "g" | "u" | "l" | "k" | "s" | "m" (paved near buildings, grass between).
function M.raster(c, yield, baseAt)
  if c._map then return c._map end
  local x0, z0 = c.cx * chunkLib.SIZE, c.cz * chunkLib.SIZE
  local codes, heights = {}, {}
  local interior = c.district == "interior"
  for v = 0, N - 1 do
    local crow, hrow = {}, {}
    local z = z0 + (v + 0.5) * M.RES
    for u = 0, N - 1 do
      local x = x0 + (u + 0.5) * M.RES
      local h = chunkLib.terrainY(c, x, z)
      local code = "g"
      local level = chunkLib.waterAt(c, x, z)
      if interior then
        code = "v"
      elseif level and h < level then
        code = h < level - 3 and "W" or "w"
      else
        local h2 = chunkLib.terrainY(c, x + M.RES, z)
        local h3 = chunkLib.terrainY(c, x, z + M.RES)
        if math.abs(h2 - h) + math.abs(h3 - h) > 2.9 then
          code = "k"
        elseif level and h < level + 0.7 then
          code = "s"
        elseif baseAt then
          code = baseAt(x, z) or "g"
          if code == "m" then code = "z" end
        end
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
  for _, rd in ipairs(c.roads) do
    -- bridges and tunnels are drawn by their ribbons below
    stamp(rd[8], rd[4], ROAD_CODE[rd[7]] or "r")
  end
  for _, rb in ipairs(c.ribbons) do
    local code = RIBBON_CODE[rb[1]] or "o"
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
    if b[8] ~= "void" and b[8] ~= "lintel" then
      local r = math.sqrt(b[3] * b[3] + b[4] * b[4]) / 2
      local u0, v0 = px(b[1] - r, b[2] - r)
      local u1, v1 = px(b[1] + r, b[2] + r)
      for v = math.max(1, v0), math.min(N, v1) do
        for u = math.max(1, u0), math.min(N, u1) do
          if geom.inBox(b, x0 + (u - 0.5) * M.RES, z0 + (v - 0.5) * M.RES) then set(u, v, "b") end
        end
      end
    end
  end
  -- "mixed" ground: paved within a few pixels of a building or street, grass in the yards between
  local needMix = false
  for v = 1, N do
    for u = 1, N do
      if codes[v][u] == "z" then needMix = true end
    end
  end
  if needMix then
    local near = { b = true, r = true, a = true, e = true, p = true }
    for v = 1, N do
      for u = 1, N do
        if codes[v][u] == "z" then
          local paved = false
          for dv = -3, 3, 3 do
            for du = -3, 3, 3 do
              local row = codes[v + dv]
              if row and near[row[u + du]] then paved = true end
            end
          end
          codes[v][u] = paved and "u" or "g"
        end
      end
    end
  end
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
  W = "blue", w = "cyan", g = "lime", k = "brown", s = "yellow", l = "gray", p = "white", e = "lightGray",
  r = "white", a = "lightGray", f = "yellow", t = "brown", o = "yellow", m = "orange", d = "lightGray", b = "black", n = "red",
  x = "blue", u = "lightGray", q = "brown", i = "white", c = "red", v = "black", y = "brown",
}
-- the darker tone of each, for contour lines
local DARK = { g = "green", k = "black", s = "orange", l = "black", p = "lightGray", e = "gray", w = "blue", u = "gray" }
M.CONTOUR = 6

function M.colour(code, h, hAbove)
  local name = BASE[code] or "blue"
  if hAbove and DARK[code] and floor(h / M.CONTOUR) ~= floor(hAbove / M.CONTOUR) then name = DARK[code] end
  return C[name] or 1
end

return M
