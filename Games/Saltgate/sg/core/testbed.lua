-- core/testbed.lua
-- Step 0's proving ground: a small island made in code with everything the chunk format can say, so the streamer,
-- the 3D drive, the road graph, the maps and the renderer are shown working with curves and heights before the real
-- city exists. Used only when no city is installed (content/world); stream A's city replaces it. Pure and the same every time.
--
--   testbed.chunks() -> { ["cx,cz"] = chunk }   (built once and kept)
--   testbed.source(cx, cz) -> chunk or nil       (for core/stream.lua)
--   testbed.spawn -> x, z, h                     where the player starts (on the coast road)
--   testbed.FEATURES                             what is where, for tests and screenshots

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")

local M = {}

local SIZE = chunkLib.SIZE
M.N = 4 -- 4 x 4 chunks: 352 units across
local SPAN = M.N * SIZE
local CX, CZ = SPAN / 2, SPAN / 2
local sin, cos, sqrt, floor, pi = math.sin, math.cos, math.sqrt, math.floor, math.pi

-- ---------------------------------------------------------------- the land

--- How far the coast is from the middle in direction a: wobbly, not a circle.
local function coastRadius(a)
  return 132 + 14 * sin(a * 3 + 0.7) + 8 * sin(a * 5 + 2.1) + 5 * cos(a * 9)
end

local HILL_X, HILL_Z = CX + 70, CZ - 60

--- The ground before roads are cut into it.
local function rawHeight(x, z)
  local dx, dz = x - CX, z - CZ
  local r = sqrt(dx * dx + dz * dz)
  local a = math.atan2(dz, dx)
  local coast = coastRadius(a)
  local land = math.max(-1, math.min(1, (coast - r) / 18)) -- 1 inland, -1 at sea
  local h = land > 0 and (1 + 2.5 * land) or (-6 + 7 * (land + 1))
  -- the hill, and cliffs where it meets the sea
  local hd = sqrt((x - HILL_X) ^ 2 + (z - HILL_Z) ^ 2)
  if hd < 75 then h = h + 34 * (1 - hd / 75) ^ 1.4 * math.max(0, land) end
  -- a canal across the west
  local canal = math.abs(x - (CX - 75) - 10 * sin(z / 40))
  if canal < 7 and land > 0 then h = math.min(h, -3) end
  -- gentle roll
  h = h + 0.8 * sin(x / 23) * cos(z / 31) * math.max(0, land)
  return h
end
M.rawHeight = rawHeight

-- ---------------------------------------------------------------- what we build

local roads, ribbons, floors, buildings, props, grounds, nodes = {}, {}, {}, {}, {}, {}, {}
local nodeCount, edgeCount = 0, 0
M.FEATURES = {}

local function node(x, y, z)
  nodeCount = nodeCount + 1
  local id = "tb" .. nodeCount
  nodes[#nodes + 1] = { id, x, y, z }
  return id
end

--- Lift a flat x,z control list onto the ground (smoothed), as x,y,z, with extra height where given.
local function onGround(ctrl, lift)
  local out = {}
  for i = 1, #ctrl, 2 do
    local x, z = ctrl[i], ctrl[i + 1]
    out[#out + 1] = x
    out[#out + 1] = math.max(0.5, rawHeight(x, z)) + (lift and lift[(i + 1) / 2] or 0)
    out[#out + 1] = z
  end
  return out
end

--- A road along a 3D polyline, split into edges no longer than maxLen, with nodes between; returns the node ids.
M.MAX_GRADE = 0.2 -- the steepest a testbed road climbs (1 in 5)

--- The height of a node already made (nil if none).
local function nodeY(id)
  for _, nd in ipairs(nodes) do
    if nd[1] == id then return nd[3] end
  end
  return nil
end

--- Keep a road drivable: its ends meet the junctions' heights, and no stretch climbs steeper than MAX_GRADE
-- (passes from both ends; where the ground is steeper the road cuts into it or stands on it, as real roads do).
local function easeGrade(pts, y0, y1)
  local n = #pts / 3
  if y0 then pts[2] = y0 end
  if y1 then pts[#pts - 1] = y1 end
  local function ds(i)
    local a, b = (i - 1) * 3 + 1, i * 3 + 1
    return math.sqrt((pts[b] - pts[a]) ^ 2 + (pts[b + 2] - pts[a + 2]) ^ 2)
  end
  for _ = 1, 2 do
    for i = 2, n do
      local lim = M.MAX_GRADE * ds(i - 1)
      local prev = pts[(i - 2) * 3 + 2]
      local k = (i - 1) * 3 + 2
      if not (i == n and y1) then pts[k] = math.max(prev - lim, math.min(prev + lim, pts[k])) end
    end
    for i = n - 1, 1, -1 do
      local lim = M.MAX_GRADE * ds(i)
      local nxt = pts[i * 3 + 2]
      local k = (i - 1) * 3 + 2
      if not (i == 1 and y0) then pts[k] = math.max(nxt - lim, math.min(nxt + lim, pts[k])) end
    end
  end
  return pts
end

local function road(pts, width, kind, speed, lanes, closeTo)
  -- ends that join existing junctions take those junctions' heights; loops end where they start
  local y0 = closeTo and closeTo[1] and nodeY(closeTo[1]) or nil
  local y1 = closeTo and closeTo[2] and nodeY(closeTo[2]) or nil
  if closeTo and closeTo.loop then y1 = pts[2] end
  if kind ~= "rail" then easeGrade(pts, y0, y1) end
  local length = geom.polylineLength(pts)
  local pieces = math.max(1, math.ceil(length / 60))
  local ids = {}
  local first = closeTo and closeTo[1] or node(pts[1], pts[2], pts[3])
  ids[1] = first
  local s0 = 0
  for p = 1, pieces do
    local s1 = length * p / pieces
    local seg = {}
    local x, y, z = geom.polylineAt(pts, s0)
    seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = x, y, z
    -- the original points between s0 and s1
    local walked = 0
    for i = 1, #pts - 3, 3 do
      local d = sqrt((pts[i + 3] - pts[i]) ^ 2 + (pts[i + 5] - pts[i + 2]) ^ 2)
      walked = walked + d
      if walked > s0 + 0.01 and walked < s1 - 0.01 then
        seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = pts[i + 3], pts[i + 4], pts[i + 5]
      end
    end
    x, y, z = geom.polylineAt(pts, s1)
    seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = x, y, z
    local endId
    if p == pieces and closeTo and closeTo[2] then endId = closeTo[2]
    elseif p == pieces and closeTo and closeTo.loop then endId = first
    else endId = node(x, y, z) end
    edgeCount = edgeCount + 1
    roads[#roads + 1] = { "tbe" .. edgeCount, ids[#ids], endId, width, lanes or 2, speed or 14, kind or "road", seg }
    ids[#ids + 1] = endId
    s0 = s1
  end
  return ids
end

local function ribbon(kind, width, pts)
  local length = geom.polylineLength(pts)
  local pieces = math.max(1, math.ceil(length / 50))
  for p = 1, pieces do
    local s0, s1 = length * (p - 1) / pieces, length * p / pieces
    local seg = {}
    local steps = math.max(2, math.ceil((s1 - s0) / 4))
    for k = 0, steps do
      local x, y, z = geom.polylineAt(pts, s0 + (s1 - s0) * k / steps)
      seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = x, y, z
    end
    ribbons[#ribbons + 1] = { kind, width, seg }
  end
end

-- 1. the coast road: a ring just inside the shore
do
  local ctrl = {}
  for k = 0, 47 do
    local a = k / 48 * pi * 2
    local r = coastRadius(a) - 20
    ctrl[#ctrl + 1] = CX + cos(a) * r
    ctrl[#ctrl + 1] = CZ + sin(a) * r
  end
  ctrl[#ctrl + 1], ctrl[#ctrl + 2] = ctrl[1], ctrl[2]
  local pts = geom.curve(onGround(ctrl), 5)
  M.FEATURES.coast = road(pts, 9, "road", 16, 2, { loop = true })
end

local function nodeById(id)
  for _, nd in ipairs(nodes) do
    if nd[1] == id then return nd end
  end
  return nil
end

--- The coast road node nearest (x, z): roads that meet the coast join it there.
local function coastNode(x, z)
  local best, bd = nil, math.huge
  for _, id in ipairs(M.FEATURES.coast) do
    local nd = nodeById(id)
    local d = (nd[2] - x) ^ 2 + (nd[4] - z) ^ 2
    if d < bd then best, bd = nd, d end
  end
  return best
end

-- 2. hairpins up the hill, from the coast road
do
  local start = coastNode(HILL_X - 64, HILL_Z + 52)
  local ctrl = {
    -- switchbacks about 20 units apart: far enough that each leg keeps its own ground
    start[2], start[4], HILL_X - 24, HILL_Z + 62, HILL_X + 28, HILL_Z + 52, HILL_X - 28, HILL_Z + 32,
    HILL_X - 36, HILL_Z + 12, HILL_X + 24, HILL_Z + 8, HILL_X + 26, HILL_Z - 12, HILL_X - 14, HILL_Z - 18, HILL_X, HILL_Z - 2,
  }
  local pts = geom.curve(onGround(ctrl), 4)
  M.FEATURES.hairpins = road(pts, 7, "road", 9, 2, { start[1] })
end

-- 3. the roundabout and the diagonal avenue through it
local RX, RZ = CX - 10, CZ + 20
do
  -- the ring starts on its south-west side (where the avenue comes in) and goes round once
  local ring = geom.circle(RX, 0, RZ, 16, 24, 3 * pi / 4, 3 * pi / 4 + pi * 2)
  for i = 2, #ring, 3 do ring[i] = math.max(0.5, rawHeight(ring[i - 1], ring[i + 1])) end
  M.FEATURES.roundabout = road(ring, 8, "road", 9, 1, { loop = true })
  props[#props + 1] = { "tree", RX, RZ, 0, chunkLib.TERRAIN }
  local ringStart = nodeById(M.FEATURES.roundabout[1])
  local ringMid = nodeById(M.FEATURES.roundabout[2])
  -- the avenue runs from the coast road in the south-west, through the roundabout, out to the north-east
  local sw = coastNode(RX - 90, RZ + 85)
  local a1 = geom.curve(onGround({ sw[2], sw[4], RX - 45, RZ + 50, ringStart[2], ringStart[4] }), 5)
  M.FEATURES.avenueSW = road(a1, 10, "avenue", 16, 2, { sw[1], ringStart[1] })
  local a2 = geom.curve(onGround({ ringMid[2], ringMid[4], CX + 40, CZ + 4, CX + 92, CZ + 2 }), 5)
  M.FEATURES.avenueNE = road(a2, 10, "avenue", 16, 2, { ringMid[1] })
end

-- 4. the overpass: the avenue climbs over the coast road on a raised ribbon and comes down outside it, by the sea
do
  local ax, az = CX + 92, CZ + 2
  local bx, bz = CX + 147, CZ + 4
  local y0 = math.max(0.5, rawHeight(ax, az))
  local pts = geom.curve({ ax, y0, az, ax + 14, y0 + 4, az, ax + 30, y0 + 7.5, az + 1, ax + 44, y0 + 7.5, az + 2,
    bx, math.max(0.5, rawHeight(bx, bz)) + 0.2, bz }, 4)
  ribbon("overpass", 10, pts)
  M.FEATURES.overpass = { x = ax + 37, z = az + 1.5, y = y0 + 7.5 }
  local endNE = M.FEATURES.avenueNE[#M.FEATURES.avenueNE]
  local ids = road(pts, 10, "avenue", 16, 2, { endNE })
  M.FEATURES.overpassRoad = ids
end

-- 5. the canal bridge on the west side
do
  local z = CZ + 10
  local x0, x1 = CX - 105, CX - 45
  local pts = geom.curve({ x0, math.max(0.5, rawHeight(x0, z)), z, CX - 85, 4.5, z + 2, CX - 75, 5, z + 3, CX - 65, 4.5, z + 2,
    x1, math.max(0.5, rawHeight(x1, z)), z }, 4)
  ribbon("bridge", 9, pts)
  road(pts, 9, "road", 14, 2)
  M.FEATURES.bridge = { x = CX - 75 + 10 * sin(z / 40), z = z + 3, y = 5 }
end

-- 6. the old town: a crooked street with buildings turned to follow it
do
  local ctrl = { CX - 40, CZ + 100, CX - 25, CZ + 80, CX - 30, CZ + 62, CX - 12, CZ + 52, CX + 4, CZ + 66, CX + 20, CZ + 58 }
  local pts = geom.curve(onGround(ctrl), 3)
  M.FEATURES.oldtown = road(pts, 5, "alley", 7)
  local len = geom.polylineLength(pts)
  local s = 6
  local side = 1
  while s < len - 6 do
    local x, y, z, dx, dz = geom.polylineAt(pts, s)
    local w, d = 6 + (floor(s) % 3), 6
    local off = 2.5 + d / 2 + 0.5
    buildings[#buildings + 1] = { x - dz * off * side, z + dx * off * side, w, d, math.atan2(dz, dx), chunkLib.TERRAIN,
      7 + (floor(s * 7) % 5), (floor(s) % 2 == 0) and "pastel" or "brick", true }
    side = -side
    if side == 1 then s = s + w + 1.5 end
  end
end

-- 7. a little downtown grid, only here
do
  local gx, gz = CX + 40, CZ + 50
  -- a real grid: a node at every crossing, an edge between neighbours
  local grid = {}
  for i = 0, 2 do
    grid[i] = {}
    for j = 0, 2 do
      local x, z = gx + i * 22, gz + j * 22
      grid[i][j] = node(x, math.max(0.5, rawHeight(x, z)), z)
    end
  end
  local function link(i0, j0, i1, j1)
    local a, b = nodeById(grid[i0][j0]), nodeById(grid[i1][j1])
    road({ a[2], a[3], a[4], b[2], b[3], b[4] }, 7, "road", 12, 2, { a[1], b[1] })
  end
  for i = 0, 2 do
    for j = 0, 2 do
      if i < 2 then link(i, j, i + 1, j) end
      if j < 2 then link(i, j, i, j + 1) end
    end
  end
  -- and joined to the rest: a street from its north-west corner up to the avenue, one from its south-east corner
  -- down to the coast road
  local function joinTo(gridId, candidates)
    local g = nodeById(gridId)
    local best, bd = nil, math.huge
    for _, id in ipairs(candidates) do
      local nd = nodeById(id)
      local d = (nd[2] - g[2]) ^ 2 + (nd[4] - g[4]) ^ 2
      if d < bd then best, bd = nd, d end
    end
    local pts = geom.curve(onGround({ g[2], g[4], (g[2] + best[2]) / 2 - 6, (g[4] + best[4]) / 2, best[2], best[4] }), 4)
    road(pts, 7, "road", 12, 2, { g[1], best[1] })
  end
  joinTo(grid[0][0], M.FEATURES.avenueNE)
  joinTo(grid[2][2], M.FEATURES.coast)
  for i = 0, 1 do
    for j = 0, 1 do
      buildings[#buildings + 1] = { gx + 11 + i * 22, gz + 11 + j * 22, 12, 12, 0, chunkLib.TERRAIN, 22 + 9 * ((i + j) % 2),
        (i + j) % 2 == 0 and "glass" or "white", true }
    end
  end
  grounds[#grounds + 1] = { "plaza", chunkLib.TERRAIN, { gx - 4, gz - 4, gx + 48, gz - 4, gx + 48, gz + 48, gx - 4, gz + 48 } }
  M.FEATURES.downtown = { x = gx + 22, z = gz + 22 }
end

-- 8. the car park: three levels joined by ramps
do
  local px, pz = CX - 60, CZ - 70
  local base = math.max(0.5, rawHeight(px, pz))
  for level = 0, 2 do
    floors[#floors + 1] = { "deck", base + level * 4, { px, pz, px + 30, pz, px + 30, pz + 20, px, pz + 20 } }
  end
  -- ramps up the east side, one per level
  ribbon("ramp", 5, { px + 27, base, pz + 22, px + 27, base + 4, pz - 2 })
  ribbon("ramp", 5, { px + 3, base + 4, pz - 2, px + 3, base + 8, pz + 22 })
  for _, c in ipairs({ { px, pz }, { px + 30, pz }, { px, pz + 20 }, { px + 30, pz + 20 } }) do
    props[#props + 1] = { "pillar", c[1], c[2], 0, base }
  end
  M.FEATURES.carpark = { x = px + 15, z = pz + 10, top = base + 8 }
end

-- 9. the jump: a ramp that ends in the air beside the coast road
do
  local a = 2.6
  local r = coastRadius(a) - 20 -- on the coast road: cars on it hit the ramp and land on the road ahead
  local x, z = CX + cos(a) * r, CZ + sin(a) * r
  local y = math.max(0.5, rawHeight(x, z))
  local dx, dz = -sin(a), cos(a)
  ribbon("ramp", 5, { x - dx * 8, y, z - dz * 8, x + dx * 6, y + 3.5, z + dz * 6 })
  M.FEATURES.jump = { x = x, z = z, h = math.atan2(dz, dx), top = y + 3.5 }
end

-- 9b. one network: every piece of road that is not joined to the coast road gets a short street to the nearest
-- junction that is (traffic and the Patrol can reach everywhere)
local function connectAll()
  local function reached()
    local adj = {}
    for _, r in ipairs(roads) do
      adj[r[2]] = adj[r[2]] or {}
      adj[r[3]] = adj[r[3]] or {}
      table.insert(adj[r[2]], r[3])
      table.insert(adj[r[3]], r[2])
    end
    local seen, queue = { [M.FEATURES.coast[1]] = true }, { M.FEATURES.coast[1] }
    while #queue > 0 do
      local id = table.remove(queue)
      for _, n in ipairs(adj[id] or {}) do
        if not seen[n] then
          seen[n] = true
          queue[#queue + 1] = n
        end
      end
    end
    return seen
  end
  for _ = 1, 10 do
    local seen = reached()
    local bestA, bestB, bd = nil, nil, math.huge
    for _, a in ipairs(nodes) do
      if not seen[a[1]] then
        for _, b in ipairs(nodes) do
          if seen[b[1]] then
            local d = (a[2] - b[2]) ^ 2 + (a[4] - b[4]) ^ 2
            if d < bd then bestA, bestB, bd = a, b, d end
          end
        end
      end
    end
    if not bestA then break end
    local mx, mz = (bestA[2] + bestB[2]) / 2, (bestA[4] + bestB[4]) / 2
    local pts = geom.curve(onGround({ bestA[2], bestA[4], mx + 4, mz - 4, bestB[2], bestB[4] }), 4)
    road(pts, 6, "road", 10, 2, { bestA[1], bestB[1] })
  end
end

-- 10. houses along the coast road, turned to face it, where there is room
local function clearOfRoads(x, z, pad)
  for _, r in ipairs(roads) do
    local d = geom.polylineNearest(r[8], x, z)
    if d < r[4] / 2 + pad then return false end
  end
  for _, r in ipairs(ribbons) do
    local d = geom.polylineNearest(r[3], x, z)
    if d < r[2] / 2 + pad then return false end
  end
  for _, f in ipairs(floors) do
    local x0, z0, x1, z1 = geom.bounds(f[3])
    if x > x0 - pad and x < x1 + pad and z > z0 - pad and z < z1 + pad then return false end
  end
  return true
end
do
  local styles = { "pastel", "white", "brick", "concrete", "neon" }
  local k = 0
  for i = 0, 89 do
    local a = i / 90 * pi * 2
    local r = coastRadius(a) - 34
    local x, z = CX + cos(a) * r, CZ + sin(a) * r
    local h = rawHeight(x, z)
    if h > 0.6 and h < 14 and clearOfRoads(x, z, 6) then
      k = k + 1
      buildings[#buildings + 1] = { x, z, 8, 7, a + pi / 2, chunkLib.TERRAIN, 5 + (k % 4) * 2, styles[k % #styles + 1], true }
    end
  end
  for i = 0, 40 do
    local a = i / 41 * pi * 2 + 0.05
    local r = coastRadius(a) - 9
    local x, z = CX + cos(a) * r, CZ + sin(a) * r
    if rawHeight(x, z) > 0.4 and clearOfRoads(x, z, 1.5) then props[#props + 1] = { "lamp", x, z, a, chunkLib.TERRAIN } end
  end
  -- a park with a winding path near the roundabout
  grounds[#grounds + 1] = { "grass", chunkLib.TERRAIN, { RX + 20, RZ + 20, RX + 60, RZ + 25, RX + 55, RZ + 60, RX + 22, RZ + 55 } }
  local path = geom.curve(onGround({ RX + 24, RZ + 24, RX + 40, RZ + 34, RX + 30, RZ + 44, RX + 50, RZ + 54 }), 3)
  road(path, 2.5, "path", 3, 2)
  for i = 1, 6 do props[#props + 1] = { "tree", RX + 25 + i * 5, RZ + 30 + (i % 3) * 7, 0, chunkLib.TERRAIN } end
end
connectAll()

-- ---------------------------------------------------------------- cutting roads into the ground, chunking

local built = nil

local function buildChunks(yield)
  local n = chunkLib.HEIGHT_N
  local step = SIZE / (n - 1)
  local out = {}
  -- each road's and ribbon's box, so a height sample only looks at the ones near it
  local function boxed(list, ptsAt, widthAt)
    local out2 = {}
    for _, r in ipairs(list) do
      local x0, z0, x1, z1 = geom.bounds(r[ptsAt], 3)
      local pad = r[widthAt] / 2 + 20
      out2[#out2 + 1] = { r = r, x0 = x0 - pad, z0 = z0 - pad, x1 = x1 + pad, z1 = z1 + pad }
    end
    return out2
  end
  local roadBoxes, ribbonBoxes = boxed(roads, 8, 4), boxed(ribbons, 3, 2)
  local function chunkOf(x, z)
    local cx, cz = chunkLib.at(x, z)
    cx, cz = math.max(0, math.min(M.N - 1, cx)), math.max(0, math.min(M.N - 1, cz))
    local key = chunkLib.key(cx, cz)
    local c = out[key]
    if not c then
      c = chunkLib.new(cx, cz, "mid")
      out[key] = c
    end
    return c
  end
  for cz = 0, M.N - 1 do
    for cx = 0, M.N - 1 do
      local c = chunkOf(cx * SIZE + 1, cz * SIZE + 1)
      c.district = (cx >= 2 and cz <= 1) and "gilt" or ((cx <= 1 and cz >= 2) and "lantern" or (cz >= 3 and "brine" or "mid"))
      local h = {}
      for j = 0, n - 1 do
        for i = 0, n - 1 do
          local x, z = cx * SIZE + i * step, cz * SIZE + j * step
          local y = rawHeight(x, z)
          -- roads flatten the ground under them to their own height (not under bridges and overpasses). Every
          -- height sample within a whole grid cell of a road's edge takes the road's height, so the ground under any
          -- part of the road is the road (a narrower band left hillside corners in the cells under it: the road
          -- floated or sank); past that it eases back over BLEND. Where roads come close (switchbacks), the
          -- nearest one decides.
          local FULL, BLEND = step * 1.45, 6
          local bestD, bestY = math.huge, nil
          for _, box in ipairs(roadBoxes) do
            if x > box.x0 - FULL and x < box.x1 + FULL and z > box.z0 - FULL and z < box.z1 + FULL then
              local r = box.r
              local d, ry = geom.polylineNearest(r[8], x, z)
              local edge = d - r[4] / 2
              if edge < FULL + BLEND and edge < bestD then bestD, bestY = edge, ry end
            end
          end
          if bestY then
            local onBridge = false
            for _, rbox in ipairs(ribbonBoxes) do
              if x > rbox.x0 and x < rbox.x1 and z > rbox.z0 and z < rbox.z1 then
                local d2 = geom.polylineNearest(rbox.r[3], x, z)
                if d2 < rbox.r[2] / 2 + 1 then onBridge = true end
              end
            end
            if not onBridge then
              local t = math.max(0, math.min(1, (bestD - FULL) / BLEND))
              y = bestY * (1 - t) + y * t - 0.05 * (1 - t)
            end
          end
          h[j * n + i + 1] = floor(y * 100 + 0.5) / 100
        end
      end
      c.heights = h
      -- the sea and the canal: one water sheet per chunk at level 0; the ground above it is land
      c.water[1] = { 0, { cx * SIZE, cz * SIZE, (cx + 1) * SIZE, cz * SIZE, (cx + 1) * SIZE, (cz + 1) * SIZE, cx * SIZE, (cz + 1) * SIZE } }
      if yield then yield() end
    end
  end
  for _, nd in ipairs(nodes) do table.insert(chunkOf(nd[2], nd[4]).nodes, nd) end
  for _, r in ipairs(roads) do
    local pts = r[8]
    local mid = floor(#pts / 6) * 3 + 1
    table.insert(chunkOf(pts[mid], pts[mid + 2]).roads, r)
  end
  for _, r in ipairs(ribbons) do
    local pts = r[3]
    local mid = floor(#pts / 6) * 3 + 1
    table.insert(chunkOf(pts[mid], pts[mid + 2]).ribbons, r)
  end
  for _, f in ipairs(floors) do table.insert(chunkOf(f[3][1], f[3][2]).floors, f) end
  -- no building on a road: the joining roads (joinTo, connectAll) came after the blocks were placed, and a few ran
  -- through them (a driver following its lane drove into a wall)
  local roadSamples = {}
  for _, r in ipairs(roads) do
    if r[7] ~= "rail" then
      local pts, hw = r[8], r[4] / 2 + 1.5
      local len = geom.polylineLength(pts)
      local s = 0
      while s <= len do
        local x, _, z = geom.polylineAt(pts, s)
        roadSamples[#roadSamples + 1] = { x, z, hw }
        s = s + 2
      end
    end
  end
  local function onRoad(b)
    local reach = math.max(b[3], b[4]) + 8
    for _, q in ipairs(roadSamples) do
      if math.abs(q[1] - b[1]) < reach and math.abs(q[2] - b[2]) < reach and geom.pushOutOfBox(b, q[1], q[2], q[3]) then
        return true
      end
    end
    return false
  end
  for _, b in ipairs(buildings) do
    if not onRoad(b) then table.insert(chunkOf(b[1], b[2]).buildings, b) end
  end
  for _, p in ipairs(props) do table.insert(chunkOf(p[2], p[3]).props, p) end
  for _, gd in ipairs(grounds) do table.insert(chunkOf(gd[3][1], gd[3][2]).ground, gd) end
  local sx, sz = CX + cos(0.3) * (coastRadius(0.3) - 20), CZ + sin(0.3) * (coastRadius(0.3) - 20)
  local spawnChunk = chunkOf(sx, sz)
  spawnChunk.spawns[#spawnChunk.spawns + 1] = { "player", sx, sz, 0.3 + pi / 2 }
  M.spawn = { x = sx, z = sz, h = 0.3 + pi / 2 }
  return out
end

function M.chunks(yield)
  if not built then built = buildChunks(yield) end
  return built
end

function M.source(cx, cz)
  return M.chunks()[chunkLib.key(cx, cz)]
end

M.CENTRE = { x = CX, z = CZ }
M.HILL = { x = HILL_X, z = HILL_Z }

return M
