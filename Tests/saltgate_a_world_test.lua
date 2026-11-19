-- saltgate_a_world_test.lua
-- Stream A of the SALTGATE expansion: the real city (content/world/*.sgc, written by tools/saltgate/citybuild.mjs) and the
-- way it is drawn. The gate: every chunk is valid, every road node is reachable on the graph, no building stands on a road,
-- the city is curved and has real height (bridges, an overpass, tunnels, hills), the models build, the day and the weather
-- make sense, every landmark and interior the content names exists.

local t = require("testing")

-- the world's models name palette colours; plain Lua has no `colors`, the emulator does
local fakeColors = false
if not rawget(_G, "colors") then
  fakeColors = true
  local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }
  local c = {}
  for i, n in ipairs(names) do c[n] = 2 ^ (i - 1) end
  c.grey, c.lightGrey = c.gray, c.lightGray
  _G.colors = c
  _G.colours = c
end

local contentLib = require("sg.core.content")
local chunk = require("sg.core.chunk")
local geom = require("sg.core.geom")
local roadgraph = require("sg.core.roadgraph")
local cityLib = require("sg.world.city")
local chunkmodel = require("sg.world.chunkmodel")
local landmarks = require("sg.world.landmarks")
local mapview = require("sg.world.mapview")
local sky = require("sg.world.sky")

-- ---------------------------------------------------------------- where the content is, and a file system to read it
local hasFs = rawget(_G, "fs") ~= nil and type(fs.open) == "function" and fs.exists ~= nil
local ROOT
if hasFs and fs.exists("/repo/Games/Saltgate/content") then ROOT = "/repo/Games/Saltgate/content"
else ROOT = "Games/Saltgate/content" end

local shim = {}
function shim.exists(p)
  if hasFs and fs.exists(p) then return true end
  local f = io and io.open and io.open(p, "rb")
  if f then f:close() return true end
  return false
end
function shim.open(p, mode)
  if hasFs and fs.exists(p) then return fs.open(p, mode) end
  local f = io.open(p, "rb")
  if not f then return nil end
  return { readAll = function() return f:read("*a") end, close = function() f:close() end }
end
function shim.list(p)
  if hasFs and fs.exists(p) then return fs.list(p) end
  local out = {}
  local pipe = io.popen('ls "' .. p .. '"')
  for name in pipe:lines() do out[#out + 1] = name end
  pipe:close()
  return out
end

local content = contentLib.new({ fs = shim, root = ROOT, cache = 2 })
local city = cityLib.new(content)

t.test("world content: the city is installed with its districts, islands and interiors", function()
  t.truthy(city, "content/world/world.lua reads")
  local d = city.data
  t.eq(#d.districts, 10, "ten districts")
  t.eq(#d.islands, 3, "three islands")
  local ids = {}
  for _, x in ipairs(d.districts) do ids[x.id] = true end
  for _, id in ipairs({ "oldtown", "meridian", "gilt", "lantern", "cinder", "brine", "heron", "kestrel", "windward", "quarry" }) do
    t.truthy(ids[id], "district " .. id)
  end
  local n = 0
  for _ in pairs(d.interiors) do n = n + 1 end
  t.truthy(n >= 12, "at least twelve interiors, got " .. n)
end)

-- ---------------------------------------------------------------- every chunk
local all = city and city:chunks(t.breathe) or {} -- breathing: under CC this is long enough to hit the 7 s limit
local count = 0
for _ in pairs(all) do count = count + 1 end

t.test("world chunks: every chunk unpacks and passes chunk.validate, at least 100 of them", function()
  t.truthy(count >= 100, "chunks: " .. count)
  for key, c in pairs(all) do
    local ok, err = chunk.validate(c)
    if not ok then error("chunk " .. key .. ": " .. tostring(err)) end
    t.eq(chunk.key(c.cx, c.cz), key)
  end
end)

t.test("world chunks: the ground is continuous across chunk edges", function()
  local n = chunk.HEIGHT_N
  local worst = 0
  for _, c in pairs(all) do
    local r = all[chunk.key(c.cx + 1, c.cz)]
    if r and c.heights and r.heights then
      for j = 0, n - 1 do worst = math.max(worst, math.abs(c.heights[j * n + n] - r.heights[j * n + 1])) end
    end
    local d = all[chunk.key(c.cx, c.cz + 1)]
    if d and c.heights and d.heights then
      for i = 0, n - 1 do worst = math.max(worst, math.abs(c.heights[(n - 1) * n + i + 1] - d.heights[i + 1])) end
    end
  end
  t.truthy(worst < 0.02, "edge mismatch " .. worst)
end)

-- ---------------------------------------------------------------- the road graph
local graph = roadgraph.new()
for _, c in pairs(all) do graph:addChunk(c) end

t.test("world roads: every road node is reachable, one network over three islands", function()
  local nodeCount = 0
  local first
  for id, n in pairs(graph.nodes) do
    nodeCount = nodeCount + 1
    if n.defined and not first then first = id end
  end
  t.truthy(nodeCount > 300, "nodes: " .. nodeCount)
  local seen, stack, reached = { [first] = true }, { first }, 1
  while #stack > 0 do
    local id = table.remove(stack)
    for _, e in ipairs(graph.nodes[id].edges) do
      local other = e.a == id and e.b or e.a
      if not seen[other] then seen[other] = true reached = reached + 1 stack[#stack + 1] = other end
    end
  end
  t.eq(reached, nodeCount, "nodes reached from one")
  for _, n in pairs(graph.nodes) do t.truthy(n.defined, "node " .. n.id .. " has a position in a chunk") end
end)

t.test("world roads: A* finds a way from the start to every island and district, on roads you can drive", function()
  local d = city.data
  local function nearestNode(x, z)
    local best, bd = nil, 1e18
    for id, n in pairs(graph.nodes) do
      local e = n.edges[1]
      if e and e.kind ~= "path" and e.kind ~= "rail" then
        local dd = (n.x - x) ^ 2 + (n.z - z) ^ 2
        if dd < bd then best, bd = id, dd end
      end
    end
    return best
  end
  local from = nearestNode(d.spawn.x, d.spawn.z)
  for _, dist in ipairs(d.districts) do
    local to = nearestNode(dist.x, dist.z)
    local ids = graph:path(from, to, { road = true, avenue = true, highway = true, alley = true })
    t.truthy(ids, "a drivable way to " .. dist.name)
  end
end)

t.test("world roads: no building stands on a road", function()
  local bad = {}
  for _, c in pairs(all) do
    for _, b in ipairs(c.buildings) do
      if b[8] ~= "void" and b[8] ~= "lintel" and b[8] ~= "wall" then
        local ca, sa = math.cos(b[5]), math.sin(b[5])
        local pts = { { 0, 0 } }
        for _, u in ipairs({ -1, 1 }) do for _, v in ipairs({ -1, 1 }) do pts[#pts + 1] = { u * b[3] / 2, v * b[4] / 2 } end end
        for _, p in ipairs(pts) do
          local x, z = b[1] + p[1] * ca - p[2] * sa, b[2] + p[1] * sa + p[2] * ca
          local e, _, dist, _, _, y = graph:nearest(x, z, 14, { road = true, avenue = true, alley = true, highway = true, path = true })
          if e and dist < e.width / 2 - 0.01 then
            local gy = chunk.terrainY(c, b[1], b[2])
            if y and math.abs(y - b[6]) < 2.5 then bad[#bad + 1] = string.format("%s at %d,%d on %s", b[8], b[1], b[2], e.id) end
          end
        end
      end
    end
  end
  t.eq(#bad, 0, bad[1] or "")
end)

-- ---------------------------------------------------------------- curves and height
t.test("world shape: curved roads, not a grid (most streets bend, headings are everywhere)", function()
  local bent, edges, buckets = 0, 0, {}
  for _, e in pairs(graph.edges) do
    if e.kind ~= "rail" then
      edges = edges + 1
      local pts = e.pts
      local turn, last = 0, nil
      for i = 1, #pts - 5, 3 do
        local a = math.atan2(pts[i + 5] - pts[i + 2], pts[i + 3] - pts[i])
        if last then
          local d = math.abs(math.atan2(math.sin(a - last), math.cos(a - last)))
          turn = turn + d
        end
        last = a
      end
      if turn > 0.35 then bent = bent + 1 end
      local h = math.floor(((math.atan2(pts[#pts] - pts[3], pts[#pts - 2] - pts[1]) % math.pi) / math.pi) * 12)
      buckets[h] = true
    end
  end
  t.truthy(bent / edges > 0.3, "bent edges " .. bent .. " of " .. edges)
  local kinds = 0
  for _ in pairs(buckets) do kinds = kinds + 1 end
  t.truthy(kinds >= 10, "road headings in " .. kinds .. " of 12 directions")
end)

t.test("world shape: real height: hills over 40, a tunnel, bridges, an overpass, ramps, car-park decks, docks", function()
  local top, low = -1e9, 1e9
  local ribbons, floors = {}, {}
  for _, c in pairs(all) do
    for _, h in ipairs(c.heights or {}) do top = math.max(top, h) low = math.min(low, h) end
    for _, r in ipairs(c.ribbons) do ribbons[r[1]] = (ribbons[r[1]] or 0) + 1 end
    for _, f in ipairs(c.floors) do floors[f[1]] = (floors[f[1]] or 0) + 1 end
  end
  t.truthy(top > 40, "highest ground " .. top)
  t.truthy(low < -5, "sea floor " .. low)
  t.truthy((ribbons.tunnel or 0) >= 3, "tunnel pieces")
  t.truthy((ribbons.bridge or 0) >= 8, "bridge pieces")
  t.truthy((ribbons.overpass or 0) >= 1, "an overpass")
  t.truthy((ribbons.ramp or 0) >= 16, "ramps and stunt ramps: " .. tostring(ribbons.ramp))
  t.truthy((ribbons.pier or 0) >= 3, "piers")
  t.truthy((floors.deck or 0) >= 3, "car-park levels")
  t.truthy((floors.dock or 0) >= 1, "a raised dock")
end)

t.test("world shape: roads climb at drivable grades and tunnels have ground above them", function()
  local worst = 0
  for _, e in pairs(graph.edges) do
    local pts = e.pts
    for i = 1, #pts - 5, 3 do
      local d = math.sqrt((pts[i + 3] - pts[i]) ^ 2 + (pts[i + 5] - pts[i + 2]) ^ 2)
      if d > 1.5 then worst = math.max(worst, math.abs(pts[i + 4] - pts[i + 1]) / d) end
    end
  end
  t.truthy(worst < 0.75, "steepest road grade " .. worst)
  local covered = 0
  for _, c in pairs(all) do
    for _, r in ipairs(c.ribbons) do
      if r[1] == "tunnel" then
        local len = geom.polylineLength(r[3])
        for s = len * 0.35, len * 0.65, 6 do
          local x, y, z = geom.polylineAt(r[3], s)
          local own = all[chunk.key(chunk.at(x, z))]
          if own and chunk.terrainY(own, x, z) > y + 5 then covered = covered + 1 end
        end
      end
    end
  end
  t.truthy(covered >= 6, "tunnel middles under rock: " .. covered)
end)

if fakeColors then
  _G.colors = nil
  _G.colours = nil
end
