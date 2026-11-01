-- games/blightmare/world.lua
-- The squares of the first-person maps, for the rules and the pictures alike. maps.lua is read lazily, so a test can stand in
-- for it through package.loaded.

local M = {}

M.DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- 1 north, then clockwise

-- The squares nobody walks through. A door is one of them until it's opened, and > is not: an exit is a square you step on.
local SOLID = { ["#"] = true, h = true, W = true, ["+"] = true, L = true }

local function maps() return require("games.blightmare.maps") end

--- The map's table, or nil.
function M.map(mapId) return maps().DATA[mapId] end

--- The tile at x, y. Everything off the edge of a map is wall.
function M.tileAt(mapId, x, y)
  local map = maps().DATA[mapId]
  local row = map and map.rows[y]
  if not row or x < 1 or x > #row then return "#" end
  return row:sub(x, x)
end

--- The key of a door in s.opened.
function M.doorKey(mapId, x, y) return mapId .. ":" .. x .. "," .. y end

--- Can't be walked into? Pass s and a door opened in that game counts as open.
function M.solid(mapId, x, y, s)
  local c = M.tileAt(mapId, x, y)
  if (c == "+" or c == "L") and s and s.opened and s.opened[M.doorKey(mapId, x, y)] then return false end
  return SOLID[c] == true
end

--- x, y of the square faced.
function M.ahead(s)
  local d = M.DIRS[s.dir]
  return s.x + d[1], s.y + d[2]
end

return M
