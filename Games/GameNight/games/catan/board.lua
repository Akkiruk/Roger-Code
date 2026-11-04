-- games/catan/board.lua
-- The shape of the island, worked out once when this file loads: 19 hexes, 54 corners and 72 sides, and what touches what. It holds
-- no game, only geometry, so rules, the computer players and both pictures share it.
--
-- Hexes are pointy-top, in axial coordinates (q, r) with |q|, |r|, |q + r| at most 2, numbered in reading order: 3, 4, 5, 4, 3.
-- Positions are kept in whole half-units: x2 counts steps of (root 3)/2 of the radius across, y2 steps of half the radius down, from
-- the centre of the island. A corner's number and a side's number are their reading order too, top to bottom, left to right, so the
-- labels a player reads on the wall go the way they read.

local M = {}

-- Corner offsets from a hex's centre, clockwise from the top
local CORNERS = { { 0, -2 }, { 1, -1 }, { 1, 1 }, { 0, 2 }, { -1, 1 }, { -1, -1 } }
local NEIGHBORS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }

M.hexes = {}      -- i -> { q, r, x2, y2, corners = { v x6 clockwise from the top }, sides = { e x6 }, near = { hex } }
M.vertices = {}   -- i -> { x2, y2, hexes = { h }, edges = { e }, near = { v } }
M.edges = {}      -- i -> { a, b, x2, y2 (doubled midpoint), hexes = { h }, coast = bool }
M.coast = {}      -- the coastal sides in order round the island
M.harborSides = {} -- the nine sides a harbour sits on

local byAxial = {}
for r = -2, 2 do
  for q = -2, 2 do
    if math.abs(q + r) <= 2 then
      local hex = { q = q, r = r, x2 = 2 * q + r, y2 = 3 * r, corners = {}, sides = {}, near = {} }
      M.hexes[#M.hexes + 1] = hex
      byAxial[q .. "," .. r] = #M.hexes
    end
  end
end

for _, hex in ipairs(M.hexes) do
  for _, d in ipairs(NEIGHBORS) do
    local other = byAxial[(hex.q + d[1]) .. "," .. (hex.r + d[2])]
    if other then hex.near[#hex.near + 1] = other end
  end
end

-- Corners: every hex's six, the same point found from each hex that has it
local points, pointList = {}, {}
for _, hex in ipairs(M.hexes) do
  for _, d in ipairs(CORNERS) do
    local x, y = hex.x2 + d[1], hex.y2 + d[2]
    local key = x .. "," .. y
    if not points[key] then
      points[key] = { x2 = x, y2 = y }
      pointList[#pointList + 1] = points[key]
    end
  end
end
table.sort(pointList, function(a, b)
  if a.y2 ~= b.y2 then return a.y2 < b.y2 end
  return a.x2 < b.x2
end)
local vertexAt = {}
for i, point in ipairs(pointList) do
  M.vertices[i] = { x2 = point.x2, y2 = point.y2, hexes = {}, edges = {}, near = {} }
  vertexAt[point.x2 .. "," .. point.y2] = i
end

-- Sides: each pair of corners next to each other round a hex
local sideKeys, sideList = {}, {}
for h, hex in ipairs(M.hexes) do
  for k, d in ipairs(CORNERS) do
    local v = vertexAt[(hex.x2 + d[1]) .. "," .. (hex.y2 + d[2])]
    hex.corners[k] = v
    local list = M.vertices[v].hexes
    list[#list + 1] = h
  end
  for k = 1, 6 do
    local a, b = hex.corners[k], hex.corners[k % 6 + 1]
    if a > b then a, b = b, a end
    local key = a .. "," .. b
    if not sideKeys[key] then
      sideKeys[key] = { a = a, b = b, hexes = {} }
      sideList[#sideList + 1] = sideKeys[key]
    end
    local side = sideKeys[key]
    side.hexes[#side.hexes + 1] = h
  end
end
for _, side in ipairs(sideList) do
  side.x2 = M.vertices[side.a].x2 + M.vertices[side.b].x2
  side.y2 = M.vertices[side.a].y2 + M.vertices[side.b].y2
end
table.sort(sideList, function(a, b)
  if a.y2 ~= b.y2 then return a.y2 < b.y2 end
  return a.x2 < b.x2
end)
for e, side in ipairs(sideList) do
  M.edges[e] = { a = side.a, b = side.b, x2 = side.x2, y2 = side.y2, hexes = side.hexes, coast = #side.hexes == 1 }
  sideKeys[side.a .. "," .. side.b] = e
  local va, vb = M.vertices[side.a], M.vertices[side.b]
  va.edges[#va.edges + 1] = e
  vb.edges[#vb.edges + 1] = e
  va.near[#va.near + 1] = side.b
  vb.near[#vb.near + 1] = side.a
end
for _, hex in ipairs(M.hexes) do
  for k = 1, 6 do
    local a, b = hex.corners[k], hex.corners[k % 6 + 1]
    if a > b then a, b = b, a end
    hex.sides[k] = sideKeys[a .. "," .. b]
  end
end

--- The side between two corners, or nil.
function M.edgeBetween(a, b)
  if a > b then a, b = b, a end
  return sideKeys[a .. "," .. b]
end

-- The coast in order round the island, starting due west and going clockwise
local SQ3 = math.sqrt(3)
local function angle(edge)
  local a = math.atan2(edge.y2 * 0.5, edge.x2 * SQ3 / 2)
  return (a + math.pi) % (2 * math.pi)
end
for e, edge in ipairs(M.edges) do
  if edge.coast then M.coast[#M.coast + 1] = e end
end
table.sort(M.coast, function(a, b) return angle(M.edges[a]) < angle(M.edges[b]) end)
-- Nine harbours, the sides between them 3, 3, 4 round the 30 coastal sides: the spacing of the printed board
for _, index in ipairs({ 1, 4, 7, 11, 14, 17, 21, 24, 27 }) do
  M.harborSides[#M.harborSides + 1] = M.coast[index]
end

-- ------------------------------------------------------------------ what the pieces are

M.RES = { "brick", "lumber", "wool", "grain", "ore" }
M.RES_NAME = { "BRICK", "WOOD", "WOOL", "GRAIN", "ORE" }
M.RES_SHORT = { "BR", "WD", "WL", "GR", "OR" }
M.TERRAIN_NAME = { [0] = "DESERT", "HILLS", "FOREST", "PASTURE", "FIELDS", "MOUNTAINS" }
-- Terrain i makes resource i; 0 is the desert
M.TERRAINS = { 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5 }
M.NUMBERS = { 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12 }
M.PIPS = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [8] = 5, [9] = 4, [10] = 3, [11] = 2, [12] = 1 }
-- Harbour kinds: 0 is any three for one, 1-5 two of that resource for one
M.HARBORS = { 0, 0, 0, 0, 1, 2, 3, 4, 5 }

M.COST = {
  road = { 1, 1, 0, 0, 0 },
  town = { 1, 1, 1, 1, 0 },
  city = { 0, 0, 0, 2, 3 },
  dev = { 0, 0, 1, 1, 1 },
}
M.PIECES = { road = 15, town = 5, city = 4 }
M.DEV = { knight = 14, vp = 5, roads = 2, plenty = 2, monopoly = 2 }
M.DEV_ORDER = { "knight", "roads", "plenty", "monopoly", "vp" }
M.DEV_NAME = { knight = "KNIGHT", roads = "ROAD BUILDING", plenty = "YEAR OF PLENTY", monopoly = "MONOPOLY", vp = "VICTORY POINT" }
M.BANK = 19
M.WIN = 10

--- A label for a hex: A to S in reading order.
function M.hexLabel(h)
  return string.char(64 + h)
end

--- Whether two hexes touch.
function M.touches(a, b)
  for _, other in ipairs(M.hexes[a].near) do
    if other == b then return true end
  end
  return false
end

return M
