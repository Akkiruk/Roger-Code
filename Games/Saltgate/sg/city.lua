-- city.lua
-- Saltgate: an 8x8 grid of city blocks on a spit of land in the sea, with a ferry pier to the south.
-- Pure data and geometry (no screen): the block layout, buildings as boxes, collision, line of sight, roads and
-- sidewalks for traffic and pedestrians, and the named places missions use.
--
-- Coordinates: x runs east, z runs south, y is up. A tile (i, j) spans x in [i*P, (i+1)*P], z in [j*P, (j+1)*P].
-- Road centre lines lie on the tile edges (x = k*P, z = l*P), ROAD wide, so every tile has a half road round it,
-- then a SIDEWALK ring, then its lot.

local util = require("sg.util")

local M = {}

local N, P, ROAD, SIDEWALK = 8, 44, 12, 3
M.N, M.P, M.ROAD, M.SIDEWALK = N, P, ROAD, SIDEWALK
M.HALF = ROAD / 2
M.LANE = 3 -- a lane's centre from the road's centre line
M.SIZE = N * P
M.EDGE = 8 -- land beyond the outer roads before the seawall

local floor, abs, sqrt = math.floor, math.abs, math.sqrt

-- the ferry pier sticks out of the south shore
M.pier = { x0 = 2 * P + 8, x1 = 2 * P + 30, z0 = N * P + M.EDGE - 1, z1 = N * P + 46 }

M.DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } -- 0 east, 1 south, 2 west, 3 north (index d + 1)
M.DIR_HEADING = { 0, math.pi / 2, math.pi, -math.pi / 2 }

--- Which district a tile belongs to.
function M.district(i, j)
  if j == N - 1 then return "brine" end
  if i >= 5 and j <= 2 then return "gilt" end
  if i <= 2 and j >= 2 and j <= 5 then return "lantern" end
  if i >= 6 then return "cinder" end
  return "mid"
end

M.DISTRICT_NAMES = {
  brine = "The Brine Docks",
  gilt = "Gilt Heights",
  lantern = "Lantern Row",
  cinder = "Cinder Flats",
  mid = "Old Saltgate",
  park = "Gullmere Green",
  sea = "Saltgate Sound",
}

local SPECIAL = {
  ["3,4"] = "park",
  ["4,1"] = "precinct",
  ["2,6"] = "hospital",
  ["1,3"] = "juno",
  ["6,5"] = "rusty",
  ["4,6"] = "respray",
  ["6,1"] = "gilt_tower",
  ["5,7"] = "docks",
}
M.SPECIAL = SPECIAL

local STYLES = {
  gilt = { "glass", "white", "glass" },
  lantern = { "neon", "neon", "pastel" },
  cinder = { "brick", "concrete", "brick" },
  brine = { "warehouse", "concrete" },
  mid = { "pastel", "concrete", "brick", "white" },
}
local HEIGHTS = {
  gilt = { 24, 52 },
  lantern = { 8, 18 },
  cinder = { 6, 12 },
  brine = { 5, 9 },
  mid = { 8, 22 },
}

function M.tileBounds(i, j)
  return i * P, j * P, (i + 1) * P, (j + 1) * P
end

--- The lot inside the sidewalk ring.
function M.lot(i, j)
  local inset = M.HALF + SIDEWALK
  return i * P + inset, j * P + inset, (i + 1) * P - inset, (j + 1) * P - inset
end

local function building(list, x0, z0, x1, z1, h, style, solid)
  list[#list + 1] = { x0 = x0, z0 = z0, x1 = x1, z1 = z1, h = h, style = style, solid = solid ~= false }
end

--- Buildings and props of one tile, made the same way every time for a given seed.
local function makeTile(i, j, seed)
  local tile = { i = i, j = j, buildings = {}, props = {}, kind = SPECIAL[i .. "," .. j] or M.district(i, j) }
  tile.district = M.district(i, j)
  local rng = util.rng(seed * 7919 + i * 131 + j * 977 + 17)
  local ax0, az0, ax1, az1 = M.lot(i, j)
  local b = tile.buildings
  local kind = tile.kind
  if kind == "park" then
    tile.ground = "grass"
    local spots = { { 4, 4 }, { 21, 5 }, { 7, 19 }, { 20, 21 }, { 13, 3 }, { 3, 13 }, { 23, 13 } }
    for _, s in ipairs(spots) do
      local x, z = ax0 + s[1], az0 + s[2]
      building(b, x - 0.5, z - 0.5, x + 0.5, z + 0.5, 5, "tree")
    end
    tile.pond = { x0 = ax0 + 9, z0 = az0 + 9, x1 = ax1 - 9, z1 = az1 - 9 }
  elseif kind == "precinct" then
    tile.ground = "concrete"
    building(b, ax0, az0 + 8, ax1, az1, 12, "precinct")
  elseif kind == "hospital" then
    tile.ground = "concrete"
    building(b, ax0 + 2, az0, ax1 - 2, az1 - 9, 16, "hospital")
  elseif kind == "juno" then
    tile.ground = "concrete"
    building(b, ax0, az0, ax0 + 12, az1, 14, "neon")
    building(b, ax0 + 14, az0 + 12, ax1, az1, 10, "neon")
    -- the back lot (ax0+14.., az0..az0+12) stays open for cars
  elseif kind == "rusty" then
    tile.ground = "concrete"
    building(b, ax0, az0, ax1, az0 + 12, 9, "warehouse")
    building(b, ax0, az1 - 4, ax0 + 6, az1, 3, "crate")
  elseif kind == "respray" then
    tile.ground = "concrete"
    building(b, ax0, az0, ax1, az0 + 10, 7, "respray")
    building(b, ax0, az0 + 18, ax0 + 12, az1, 12, "pastel")
    building(b, ax0 + 14, az0 + 18, ax1, az1, 9, "brick")
  elseif kind == "gilt_tower" then
    tile.ground = "plaza"
    building(b, ax0 + 6, az0, ax1, az0 + 15, 66, "gilt")
  elseif kind == "docks" then
    tile.ground = "concrete"
    local colorsList = { "crate", "crate_b", "crate_c" }
    for k = 0, 2 do
      building(b, ax0 + 1 + k * 8, az0 + 1, ax0 + 7 + k * 8, az0 + 4, 2.6, colorsList[k + 1])
    end
    building(b, ax0 + 2, az0 + 14, ax0 + 8, az0 + 17, 5.2, "crate_b")
    building(b, ax1 - 3, az1 - 3, ax1 - 1.5, az1 - 1.5, 14, "crane")
    building(b, ax1 - 3, az1 - 12, ax1 - 1.5, az1 - 10.5, 14, "crane")
  else
    tile.ground = (tile.district == "brine" or tile.district == "cinder") and "concrete" or "lot"
    local styles = STYLES[tile.district]
    local hr = HEIGHTS[tile.district]
    local function pick()
      local h = hr[1] + rng() * (hr[2] - hr[1])
      if tile.district == "gilt" and rng() < 0.3 then h = h * 0.55 end
      return floor(h), styles[rng(#styles)]
    end
    local layout = rng(4)
    local mx, mz = (ax0 + ax1) / 2, (az0 + az1) / 2
    if layout == 1 then
      local h, s = pick()
      building(b, ax0 + 1, az0 + 1, ax1 - 1, az1 - 1, h, s)
    elseif layout == 2 then
      local h, s = pick()
      building(b, ax0, az0, mx - 1.5, az1, h, s)
      h, s = pick()
      building(b, mx + 1.5, az0, ax1, az1, h, s)
    elseif layout == 3 then
      local h, s = pick()
      building(b, ax0, az0, ax1, mz - 1.5, h, s)
      h, s = pick()
      building(b, ax0, mz + 1.5, ax1, az1, h, s)
    else
      for qx = 0, 1 do
        for qz = 0, 1 do
          local h, s = pick()
          local x0 = qx == 0 and ax0 or mx + 1.5
          local x1 = qx == 0 and mx - 1.5 or ax1
          local z0 = qz == 0 and az0 or mz + 1.5
          local z1 = qz == 0 and mz - 1.5 or az1
          building(b, x0, z0, x1, z1, h, s)
        end
      end
    end
  end
  return tile
end

--- Build the whole city. Same seed, same city.
function M.new(seed)
  local city = { seed = seed or 1, tiles = {} }
  for i = 0, N - 1 do
    city.tiles[i] = {}
    for j = 0, N - 1 do
      city.tiles[i][j] = makeTile(i, j, city.seed)
    end
  end
  city.places = M.places()
  return city
end

--- Named spots: mission givers, drop-offs, services. x, z are the centre; r the radius that counts as there.
function M.places()
  local function side(i, j, edge, along)
    -- a point on the sidewalk of tile (i, j): edge "n", "s", "w", "e"; along 0..1 along that edge
    local x0, z0, x1, z1 = M.tileBounds(i, j)
    local inset = M.HALF + SIDEWALK / 2
    if edge == "n" then return util.lerp(x0 + 8, x1 - 8, along), z0 + inset end
    if edge == "s" then return util.lerp(x0 + 8, x1 - 8, along), z1 - inset end
    if edge == "w" then return x0 + inset, util.lerp(z0 + 8, z1 - 8, along) end
    return x1 - inset, util.lerp(z0 + 8, z1 - 8, along)
  end
  local places = {}
  local function add(name, x, z, r, label, icon, color)
    places[name] = { name = name, x = x, z = z, r = r, label = label, icon = icon, color = color }
  end
  local jx, jz = side(1, 3, "n", 0.25)
  add("juno", jx, jz, 3, "Mama Juno's Noodles", "J", "yellow")
  local lx0, lz0 = M.lot(1, 3)
  add("juno_lot", lx0 + 20, lz0 + 6, 5, "Juno's back lot", "L", "cyan")
  local rx0, rz0, rx1, rz1 = M.lot(6, 5)
  add("rusty", (rx0 + rx1) / 2 + 3, rz0 + 18, 5, "Rusty's Chop Yard", "$", "lime")
  add("rusty_door", rx1 - 3, rz0 + 16, 3, "Rusty", "R", "yellow")
  local px0, pz0, px1 = M.lot(4, 6)
  add("respray", (px0 + px1) / 2, pz0 + 14, 4.5, "Paint & Pray", "P", "magenta")
  local hx0, hz0, hx1, hz1 = M.lot(2, 6)
  add("hospital", (hx0 + hx1) / 2, hz1 - 4, 4, "St. Gull's Hospital", "H", "white")
  places.hospital.h = math.pi / 2
  local cx0, cz0, cx1 = M.lot(4, 1)
  add("precinct", (cx0 + cx1) / 2, cz0 + 4, 4, "Harbor Patrol Precinct", "!", "blue")
  places.precinct.h = -math.pi / 2
  local gx0, gz0, gx1, gz1 = M.lot(6, 1)
  add("gilt_lot", gx0 + 16, gz1 - 5, 5, "Gilt Tower plaza", "G", "yellow")
  add("gilt_door", gx0 + 16, gz0 + 17, 4, "Gilt Tower doors", "G", "red")
  local dx0, dz0, dx1, dz1 = M.lot(5, 7)
  add("crane", dx1 - 7, dz1 - 6, 4, "Dock crane", "C", "red")
  add("ferry", (M.pier.x0 + M.pier.x1) / 2, M.pier.z1 - 6, 6, "Ferry pier", "F", "cyan")
  add("start", (cx0 + cx1) / 2 - 6, cz0 + 2, 2, "Lockup gate", "S", "white")
  places.start.h = -math.pi / 2
  return places
end

--- The tile a point is in, or nil off the grid.
function M.tileAt(city, x, z)
  local i, j = floor(x / P), floor(z / P)
  local col = city.tiles[i]
  return col and col[j]
end

local function inBox(bld, x, z, pad)
  return x > bld.x0 - pad and x < bld.x1 + pad and z > bld.z0 - pad and z < bld.z1 + pad
end

--- The building at a point, if any.
function M.buildingAt(city, x, z)
  local tile = M.tileAt(city, x, z)
  if not tile then return nil end
  for _, bld in ipairs(tile.buildings) do
    if bld.solid and inBox(bld, x, z, 0) then return bld end
  end
  return nil
end

--- Is a point on the land, the pier or the sea?
function M.onLand(x, z)
  local lo, hi = -M.EDGE, M.SIZE + M.EDGE
  if x >= lo and x <= hi and z >= lo and z <= hi then return true end
  local p = M.pier
  return x >= p.x0 and x <= p.x1 and z >= p.z0 and z <= p.z1
end

--- Keep a circle (x, z, r) out of buildings and the sea. Returns the corrected x, z and whether it hit something, plus
-- the push direction (nx, nz) when it did.
function M.collide(city, x, z, r)
  local hit, nx, nz = false, 0, 0
  -- the seawall: the land square, joined by the pier
  local lo, hi = -M.EDGE + r, M.SIZE + M.EDGE - r
  local p = M.pier
  local cx, cz = util.clamp(x, lo, hi), util.clamp(z, lo, hi)
  if cx ~= x or cz ~= z then
    -- off the land square: the pier may still hold it, else back to whichever is nearer
    local px, pz = util.clamp(x, p.x0 + r, p.x1 - r), util.clamp(z, hi - 1, p.z1 - r)
    if util.dist2(x, z, px, pz) < util.dist2(x, z, cx, cz) then cx, cz = px, pz end
  end
  if cx ~= x or cz ~= z then
    hit = true
    nx, nz = cx - x, cz - z
    x, z = cx, cz
  end
  local tile = M.tileAt(city, x, z)
  if tile then
    for _, bld in ipairs(tile.buildings) do
      if bld.solid and inBox(bld, x, z, r) then
        local qx = util.clamp(x, bld.x0, bld.x1)
        local qz = util.clamp(z, bld.z0, bld.z1)
        local dx, dz = x - qx, z - qz
        local d = sqrt(dx * dx + dz * dz)
        if d > 0.0001 then
          if d < r then
            local push = (r - d) / d
            x, z = x + dx * push, z + dz * push
            hit = true
            nx, nz = nx + dx, nz + dz
          end
        else
          -- centre inside: out through the nearest side
          local left, right, top, bottom = x - bld.x0, bld.x1 - x, z - bld.z0, bld.z1 - z
          local m = math.min(left, right, top, bottom)
          if m == left then x = bld.x0 - r; nx = nx - 1
          elseif m == right then x = bld.x1 + r; nx = nx + 1
          elseif m == top then z = bld.z0 - r; nz = nz - 1
          else z = bld.z1 + r; nz = nz + 1 end
          hit = true
        end
      end
    end
  end
  if hit then
    local len = sqrt(nx * nx + nz * nz)
    if len > 0 then nx, nz = nx / len, nz / len end
  end
  return x, z, hit, nx, nz
end

--- True when a building stands between two points (sampled every 3 units).
function M.blocked(city, ax, az, bx, bz)
  local d = util.dist(ax, az, bx, bz)
  local steps = floor(d / 3)
  for s = 1, steps - 1 do
    local t = s / steps
    if M.buildingAt(city, ax + (bx - ax) * t, az + (bz - az) * t) then return true end
  end
  return false
end

-- ---------------------------------------------------------------- roads

--- The road node (intersection) nearest a point.
function M.nearestNode(x, z)
  return util.clamp(floor(x / P + 0.5), 0, N), util.clamp(floor(z / P + 0.5), 0, N)
end

function M.nodePos(k, l)
  return k * P, l * P
end

function M.validNode(k, l)
  return k >= 0 and k <= N and l >= 0 and l <= N
end

--- How far a point is from the nearest road centre line.
function M.roadDistance(x, z)
  local fx = abs(x - floor(x / P + 0.5) * P)
  local fz = abs(z - floor(z / P + 0.5) * P)
  return math.min(fx, fz)
end

function M.onRoad(x, z)
  return M.roadDistance(x, z) <= M.HALF and M.onLand(x, z)
end

--- A point a car would drive at: travelling in direction d (0..3), t units past node (k, l), in its right-hand lane.
function M.lanePoint(k, l, d, t)
  local dir = M.DIRS[d + 1]
  local right = M.DIRS[(d + 1) % 4 + 1]
  local x, z = M.nodePos(k, l)
  return x + dir[1] * t + right[1] * M.LANE, z + dir[2] * t + right[2] * M.LANE
end

--- Directions a car may leave node (k, l) by.
function M.exits(k, l)
  local out = {}
  for d = 0, 3 do
    local dir = M.DIRS[d + 1]
    if M.validNode(k + dir[1], l + dir[2]) then out[#out + 1] = d end
  end
  return out
end

-- ---------------------------------------------------------------- sidewalks

--- A point on tile (i, j)'s sidewalk ring, s units round it clockwise from the north-west corner, and the heading there.
function M.ringPoint(i, j, s)
  local inset = M.HALF + SIDEWALK / 2
  local x0, z0 = i * P + inset, j * P + inset
  local side = P - 2 * inset
  local per = side * 4
  s = s % per
  if s < side then return x0 + s, z0, 0 end
  s = s - side
  if s < side then return x0 + side, z0 + s, math.pi / 2 end
  s = s - side
  if s < side then return x0 + side - s, z0 + side, math.pi end
  s = s - side
  return x0, z0 + side - s, -math.pi / 2
end

function M.ringLength()
  return (P - 2 * (M.HALF + SIDEWALK / 2)) * 4
end

-- ---------------------------------------------------------------- the map

--- What the ground is at a point, for the maps: "sea", "road", "walk", "building", "grass", "lot", "pier", "water".
function M.surface(city, x, z)
  if not M.onLand(x, z) then return "sea" end
  local p = M.pier
  if z > M.SIZE + M.EDGE then return "pier" end
  if x < 0 or z < 0 or x > M.SIZE or z > M.SIZE then
    return M.roadDistance(x, z) <= M.HALF and "road" or "walk"
  end
  if M.roadDistance(x, z) <= M.HALF then return "road" end
  local tile = M.tileAt(city, x, z)
  if not tile then return "walk" end
  local ax0, az0, ax1, az1 = M.lot(tile.i, tile.j)
  if x < ax0 or x > ax1 or z < az0 or z > az1 then return "walk" end
  for _, bld in ipairs(tile.buildings) do
    if inBox(bld, x, z, 0) then return bld.style == "tree" and "tree" or "building" end
  end
  local pond = tile.pond
  if pond and x > pond.x0 and x < pond.x1 and z > pond.z0 and z < pond.z1 then return "water" end
  if tile.ground == "grass" then return "grass" end
  local _ = p
  return "lot"
end

--- The district name under a point.
function M.areaName(city, x, z)
  if not M.onLand(x, z) then return M.DISTRICT_NAMES.sea end
  local i = util.clamp(floor(x / P), 0, N - 1)
  local j = util.clamp(floor(z / P), 0, N - 1)
  local tile = city.tiles[i][j]
  if tile.kind == "park" then return M.DISTRICT_NAMES.park end
  return M.DISTRICT_NAMES[tile.district]
end

return M
