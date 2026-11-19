-- core/chunk.lua
-- The world chunk: one square of the city, SIZE units on a side, as plain data. Nothing here is a grid: roads are
-- curves, ground and water are polygons, buildings are rotated boxes, and the land has real height, with bridges,
-- overpasses, ramps, tunnels and parking decks above or below it. The streamer (core/stream.lua) loads chunks round you;
-- core/chunkmodel.lua turns them into models; physics, AI and the maps ask them about the ground. Pure.
--
-- A thing belongs to the chunk its centre (or first point) is in; it may reach into the neighbours, and the streamer's
-- queries look at the 3x3 chunks round a point, so nothing is cut at a chunk edge. Things may reach at most
-- REACH units past their chunk.
--
-- Chunk fields (x, z world coordinates, y up; TERRAIN = "the ground height here"):
--   cx, cz       integers: the chunk covers x in [cx*SIZE, (cx+1)*SIZE), z likewise
--   district     "gilt" | "lantern" | "cinder" | "brine" | "mid" | ... (music, AI and the map read it)
--   heights      HEIGHT_N x HEIGHT_N ground heights, rows of z then x, corners included; nil = flat at 0
--   ground       { { kind, y, pts } }      painted ground: kind "grass" "walk" "lot" "plaza" "sand" "dirt" "rock"
--                                         "rail"; y = TERRAIN (follow the ground) or a height; pts = polygon x,z
--   water        { { level, pts } }        sea, canals, ponds as polygons at a water level
--   buildings    { { x, z, w, d, angle, base, h, style, solid } }  rotated boxes: centre, width along angle, depth
--                                         across, base height (TERRAIN = ground at the centre), height above base
--   props        { { kind, x, z, h, y } }  "lamp" "tree" "bench" "barrier" "ramp" ... h heading, y TERRAIN or height
--   nodes        { { id, x, y, z } }       road graph junctions and ends (ids are unique in the whole world)
--   roads        { { id, a, b, width, lanes, speed, kind, pts } }  road graph edges from node a to node b along a
--                                         3D polyline pts (x,y,z...; first and last points are the nodes);
--                                         kind "road" "avenue" "alley" "path" "highway" "rail"; lanes 1 = one way a->b
--   floors       { { kind, y, pts } }      flat drivable levels: "deck" (car park), "dock", "plaza", "roof"
--   ribbons      { { kind, width, pts } }  drivable strips along a 3D polyline: "bridge" "overpass" "ramp" "tunnel"
--                                         "pier" "stairs"; a tunnel's floor is below the ground and has a roof
--   doors        { { x, z, y, interior } }
--   spawns       { { kind, x, z, h } }     "parked" "ped" "cop" "boat" "player" ...
--   landmarks    { { model, x, z, h, y } }

local geom = require("sg.core.geom")

local M = {}

M.SIZE = 88
M.HEIGHT_N = 17 -- 5.5 units between height samples
M.REACH = 44 -- how far a thing may reach past its chunk
M.TERRAIN = -9999
M.STEP = 1.1 -- how high a surface may be above you and still be stepped (or driven) onto
M.VERSION = "SGC2"

-- list sections: key, letter, fields (n number, s string, b boolean), and whether the last field is a number list
M.SECTIONS = {
  { key = "ground", letter = "G", fields = { "s", "n" }, list = true },
  { key = "water", letter = "W", fields = { "n" }, list = true },
  { key = "buildings", letter = "B", fields = { "n", "n", "n", "n", "n", "n", "n", "s", "b" } },
  { key = "props", letter = "P", fields = { "s", "n", "n", "n", "n" } },
  { key = "nodes", letter = "N", fields = { "s", "n", "n", "n" } },
  { key = "roads", letter = "R", fields = { "s", "s", "s", "n", "n", "n", "s" }, list = true },
  { key = "floors", letter = "F", fields = { "s", "n" }, list = true },
  { key = "ribbons", letter = "Q", fields = { "s", "n" }, list = true },
  { key = "doors", letter = "D", fields = { "n", "n", "n", "s" } },
  { key = "spawns", letter = "S", fields = { "s", "n", "n", "n" } },
  { key = "landmarks", letter = "L", fields = { "s", "n", "n", "n", "n" } },
}

local floor = math.floor

function M.new(cx, cz, district)
  local c = { cx = cx, cz = cz, district = district or "mid" }
  for _, s in ipairs(M.SECTIONS) do c[s.key] = {} end
  return c
end

function M.key(cx, cz)
  return cx .. "," .. cz
end

function M.at(x, z)
  return floor(x / M.SIZE), floor(z / M.SIZE)
end

function M.bounds(c)
  return c.cx * M.SIZE, c.cz * M.SIZE, (c.cx + 1) * M.SIZE, (c.cz + 1) * M.SIZE
end

-- ---------------------------------------------------------------- pack / unpack

local function num(n)
  n = floor(n * 100 + 0.5) / 100
  if n == floor(n) then return tostring(floor(n)) end
  return tostring(n)
end

local function esc(s)
  return (tostring(s):gsub("[%%,;|\n]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local function unesc(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
  local out = {}
  local start = 1
  while true do
    local i = s:find(sep, start, true)
    if not i then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
end

--- One chunk as one line of text (numbers kept to 0.01).
function M.pack(c)
  local parts = { M.VERSION, num(c.cx), num(c.cz), esc(c.district or "mid") }
  if c.heights then
    local h = {}
    for i = 1, M.HEIGHT_N * M.HEIGHT_N do h[i] = num(c.heights[i] or 0) end
    parts[#parts + 1] = "H" .. table.concat(h, ",")
  end
  for _, s in ipairs(M.SECTIONS) do
    local list = c[s.key]
    if list and #list > 0 then
      local recs = {}
      for i, rec in ipairs(list) do
        local f = {}
        for k, kind in ipairs(s.fields) do
          local v = rec[k]
          if kind == "n" then f[k] = num(v or 0)
          elseif kind == "b" then f[k] = (v == false) and "0" or "1"
          else f[k] = esc(v or "") end
        end
        if s.list then
          local pts = rec[#s.fields + 1] or {}
          for _, v in ipairs(pts) do f[#f + 1] = num(v) end
        end
        recs[i] = table.concat(f, ",")
      end
      parts[#parts + 1] = s.letter .. table.concat(recs, "|")
    end
  end
  return table.concat(parts, ";")
end

local BY_LETTER = {}
for _, s in ipairs(M.SECTIONS) do BY_LETTER[s.letter] = s end

--- The chunk from pack's line, or nil and why.
function M.unpack(line)
  if type(line) ~= "string" then return nil, "not a string" end
  local parts = split(line, ";")
  if parts[1] ~= M.VERSION then return nil, "not a " .. M.VERSION .. " chunk" end
  local cx, cz = tonumber(parts[2]), tonumber(parts[3])
  if not cx or not cz then return nil, "bad chunk position" end
  local c = M.new(cx, cz, unesc(parts[4] or "mid"))
  for i = 5, #parts do
    local p = parts[i]
    local letter, body = p:sub(1, 1), p:sub(2)
    if letter == "H" then
      local h = {}
      for k, v in ipairs(split(body, ",")) do h[k] = tonumber(v) or 0 end
      c.heights = h
    else
      local s = BY_LETTER[letter]
      if not s then return nil, "unknown section " .. letter end
      for _, recText in ipairs(split(body, "|")) do
        local f = split(recText, ",")
        local rec = {}
        for k, kind in ipairs(s.fields) do
          local v = f[k]
          if kind == "n" then rec[k] = tonumber(v) or 0
          elseif kind == "b" then rec[k] = v ~= "0"
          else rec[k] = unesc(v or "") end
        end
        if s.list then
          local pts = {}
          for k = #s.fields + 1, #f do pts[#pts + 1] = tonumber(f[k]) or 0 end
          rec[#s.fields + 1] = pts
        end
        c[s.key][#c[s.key] + 1] = rec
      end
    end
  end
  return c
end

function M.packMany(list)
  local lines = {}
  for i, c in ipairs(list) do lines[i] = M.pack(c) end
  return table.concat(lines, "\n")
end

--- Chunks from a content file, keyed "cx,cz".
function M.unpackMany(text)
  local out = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local c, err = M.unpack(line)
    if not c then return nil, err end
    out[M.key(c.cx, c.cz)] = c
  end
  return out
end

-- ---------------------------------------------------------------- the ground

--- Terrain height at a point (bilinear over the height grid; 0 when the chunk is flat). Points outside the chunk are
-- clamped to its edge.
function M.terrainY(c, x, z)
  local h = c.heights
  if not h then return 0 end
  local n = M.HEIGHT_N
  local x0, z0 = c.cx * M.SIZE, c.cz * M.SIZE
  local step = M.SIZE / (n - 1)
  local fx = math.max(0, math.min(n - 1.0001, (x - x0) / step))
  local fz = math.max(0, math.min(n - 1.0001, (z - z0) / step))
  local ix, iz = floor(fx), floor(fz)
  local tx, tz = fx - ix, fz - iz
  local a = h[iz * n + ix + 1] * (1 - tx) + h[iz * n + ix + 2] * tx
  local b = h[(iz + 1) * n + ix + 1] * (1 - tx) + h[(iz + 1) * n + ix + 2] * tx
  return a * (1 - tz) + b * tz
end

--- The surfaces under (x, z) in this chunk: a list of { y, kind, what }, highest first. Terrain is one of them,
-- unless a tunnel's floor is the only way through there.
--- A record's bounding box (x0, z0, x1, z1), padded, worked out once and kept on it as _box.
local function boxOf(rec, pts, stride, pad)
  local b = rec._box
  if not b then
    local x0, z0, x1, z1 = geom.bounds(pts, stride)
    b = { x0 - pad, z0 - pad, x1 + pad, z1 + pad }
    rec._box = b
  end
  return b
end
M.boxOf = boxOf

--- The raised and sunken surfaces (floors and ribbons, not terrain) of a chunk at a point, added to out.
function M.extraSurfaces(c, x, z, out, groundY)
  for _, f in ipairs(c.floors) do
    local b = boxOf(f, f[3], 2, 0)
    if x >= b[1] and x <= b[3] and z >= b[2] and z <= b[4] and geom.inPolygon(f[3], x, z) then
      out[#out + 1] = { y = f[2], kind = f[1], what = f }
    end
  end
  for _, r in ipairs(c.ribbons) do
    local b = boxOf(r, r[3], 3, r[2] / 2)
    if x >= b[1] and x <= b[3] and z >= b[2] and z <= b[4] then
      local d, y = geom.polylineNearest(r[3], x, z)
      if d <= r[2] / 2 then out[#out + 1] = { y = y, kind = r[1], what = r } end
    end
  end
  -- a road is a surface of its own: on it, the ground is the road's height, whatever the coarse height grid says
  -- (a 5.5-unit grid cannot follow a switchback exactly; the road is the truth). Asked many times a frame, so the
  -- road segments are kept in a grid of ROAD_CELL cells and only those in the point's cell are looked at.
  -- Past the edge a SHOULDER eases from the road's height to the ground's, so a road raised above (or cut below) the
  -- coarse ground is a slope you can walk or drive onto, not a wall. groundY: the ground here (the caller knows it).
  local cell = c._roadGrid or M.roadGrid(c)
  local list = cell[floor(x / M.ROAD_CELL) .. "," .. floor(z / M.ROAD_CELL)]
  if list then
    local best = {}
    local S = M.SHOULDER
    for _, seg in ipairs(list) do
      local t, d2 = geom.segmentNearest(seg[1], seg[3], seg[4], seg[6], x, z)
      local hw = seg[7]
      if d2 <= (hw + S) * (hw + S) then
        local r = seg[8]
        -- one surface a road (the nearest of its segments)
        if not best[r] or d2 < best[r].d2 then best[r] = { d2 = d2, y = seg[2] + (seg[5] - seg[2]) * t, hw = hw } end
      end
    end
    for r, b in pairs(best) do
      local d = math.sqrt(b.d2)
      if d <= b.hw then
        out[#out + 1] = { y = b.y, kind = "road", what = r }
      else
        local gy = groundY or M.terrainY(c, x, z)
        -- (a road far above its ground is a deck, a bridge over the sea: its edge is a drop, not a slope)
        if math.abs(b.y - gy) > 0.3 and math.abs(b.y - gy) <= M.SHOULDER_MAX then
          local f = (d - b.hw) / S
          out[#out + 1] = { y = b.y + (gy - b.y) * f, kind = "shoulder", what = r }
        end
      end
    end
  end
  return out
end

M.ROAD_CELL = 8
M.SHOULDER = 3
M.SHOULDER_MAX = 4 -- a road more than this above (or below) its ground has no shoulder: a deck edge is a drop

--- The chunk's road segments by grid cell (built once, kept as c._roadGrid): each { x1, y1, z1, x2, y2, z2, halfWidth,
-- road }, in every cell its padded box touches.
function M.roadGrid(c)
  local grid = {}
  local size = M.ROAD_CELL
  for _, r in ipairs(c.roads) do
    if r[7] ~= "rail" then
      local p, hw = r[8], r[4] / 2 + M.SHOULDER -- cells reach the shoulder too
      for i = 1, #p - 3, 3 do
        local seg = { p[i], p[i + 1], p[i + 2], p[i + 3], p[i + 4], p[i + 5], r[4] / 2, r }
        local x0, x1 = math.min(p[i], p[i + 3]) - hw, math.max(p[i], p[i + 3]) + hw
        local z0, z1 = math.min(p[i + 2], p[i + 5]) - hw, math.max(p[i + 2], p[i + 5]) + hw
        for gx = floor(x0 / size), floor(x1 / size) do
          for gz = floor(z0 / size), floor(z1 / size) do
            local key = gx .. "," .. gz
            local l = grid[key]
            if not l then
              l = {}
              grid[key] = l
            end
            l[#l + 1] = seg
          end
        end
      end
    end
  end
  c._roadGrid = grid
  return grid
end

function M.surfaces(c, x, z)
  local out = {}
  out[1] = { y = M.terrainY(c, x, z), kind = "terrain" }
  M.extraSurfaces(c, x, z, out)
  if #out > 1 then table.sort(out, function(a, b) return a.y > b.y end) end
  return out
end

--- The surface something at height y stands on: the highest one no more than STEP above y (so you drive up a ramp,
-- stay on a bridge, and stay under it on the road below). y nil: the highest. Returns height and kind.
function M.groundAt(c, x, z, y)
  local list = M.surfaces(c, x, z)
  if y == nil then return list[1].y, list[1].kind end
  for _, s in ipairs(list) do
    if s.y <= y + M.STEP then return s.y, s.kind end
  end
  local low = list[#list]
  return low.y, low.kind
end

--- What is drawn on the ground at a point, for the maps: "water", "building", "road", a ribbon or floor kind, a
-- ground kind, or "land".
function M.surface(c, x, z)
  for _, b in ipairs(c.buildings) do
    if geom.inBox(b, x, z) then return "building" end
  end
  for _, r in ipairs(c.ribbons) do
    local d = geom.polylineNearest(r[3], x, z)
    if d <= r[2] / 2 then return r[1] end
  end
  for _, f in ipairs(c.floors) do
    if geom.inPolygon(f[3], x, z) then return f[1] end
  end
  for _, r in ipairs(c.roads) do
    local d = geom.polylineNearest(r[8], x, z)
    if d <= r[4] / 2 then return r[7] == "rail" and "rail" or "road" end
  end
  for _, w in ipairs(c.water) do
    if geom.inPolygon(w[2], x, z) then return "water" end
  end
  for i = #c.ground, 1, -1 do
    local g = c.ground[i]
    if geom.inPolygon(g[3], x, z) then return g[1] end
  end
  return "land"
end

--- The water level at a point, if it is water and nothing drivable crosses it there at height y.
function M.waterAt(c, x, z)
  for _, w in ipairs(c.water) do
    if geom.inPolygon(w[2], x, z) then return w[1] end
  end
  return nil
end

--- Push a circle at height y out of this chunk's solid buildings whose height range it is in. Water is the mover's
-- business (core/motion.lua): you can drive over it on a bridge. Returns x, z, hit, nx, nz.
function M.collide(c, x, z, r, y)
  local hit, nx, nz = false, 0, 0
  for _, b in ipairs(c.buildings) do
    if b[9] ~= false then
      local base = b[6]
      if base == M.TERRAIN then base = M.terrainY(c, b[1], b[2]) end
      if y == nil or (y + 1.5 > base and y < base + b[7]) then
        local px, pz, bnx, bnz = geom.pushOutOfBox(b, x, z, r)
        if px then
          x, z = px, pz
          nx, nz = nx + bnx, nz + bnz
          hit = true
        end
      end
    end
  end
  if hit then
    local len = math.sqrt(nx * nx + nz * nz)
    if len > 0 then nx, nz = nx / len, nz / len end
  end
  return x, z, hit, nx, nz
end

--- Check a chunk is well formed: true, or false and the first problem.
function M.validate(c)
  if type(c) ~= "table" then return false, "not a table" end
  if type(c.cx) ~= "number" or type(c.cz) ~= "number" then return false, "no position" end
  local x0, z0, x1, z1 = M.bounds(c)
  local R = M.REACH
  local function near(x, z) return x >= x0 - R and x <= x1 + R and z >= z0 - R and z <= z1 + R end
  for _, s in ipairs(M.SECTIONS) do
    if type(c[s.key]) ~= "table" then return false, "no " .. s.key end
    for i, rec in ipairs(c[s.key]) do
      for k, kind in ipairs(s.fields) do
        local v = rec[k]
        if kind == "n" and (type(v) ~= "number" or v ~= v) then return false, s.key .. " " .. i .. " field " .. k .. " is not a number" end
        if kind == "s" and type(v) ~= "string" then return false, s.key .. " " .. i .. " field " .. k .. " is not text" end
      end
      if s.list then
        local pts = rec[#s.fields + 1]
        local stride = (s.key == "roads" or s.key == "ribbons") and 3 or 2
        if type(pts) ~= "table" or #pts < stride * 2 or #pts % stride ~= 0 then
          return false, s.key .. " " .. i .. " needs at least two points of " .. stride .. " numbers"
        end
      end
    end
  end
  for i, b in ipairs(c.buildings) do
    if b[3] <= 0 or b[4] <= 0 or b[7] <= 0 then return false, "building " .. i .. " has no size" end
    if not near(b[1], b[2]) then return false, "building " .. i .. " is too far outside its chunk" end
  end
  local nodes = {}
  for _, nd in ipairs(c.nodes) do nodes[nd[1]] = true end
  for i, r in ipairs(c.roads) do
    if r[4] <= 0 then return false, "road " .. i .. " has no width" end
    if r[2] == r[3] and #r[8] < 12 then return false, "road " .. i .. " is a loop with too few points" end
  end
  if c.heights then
    if #c.heights ~= M.HEIGHT_N * M.HEIGHT_N then return false, "heights must have " .. M.HEIGHT_N ^ 2 .. " values" end
    for i, v in ipairs(c.heights) do
      if type(v) ~= "number" or v ~= v then return false, "height " .. i .. " is not a number" end
    end
  end
  local _ = nodes
  return true
end

return M
