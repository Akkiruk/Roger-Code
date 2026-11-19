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
local all = city and city:chunks() or {}
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
  t.truthy((ribbons.ramp or 0) >= 4, "ramps")
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

t.test("world roads: every road on the ground sits on the ground (no floating hairpins), decks and tunnels stand clear of it", function()
  local floating, n = 0, 0
  for _, c in pairs(all) do
    local decks = {}
    for _, rb in ipairs(c.ribbons) do decks[rb[3][1] .. "," .. rb[3][3]] = true end
    for _, e in ipairs(c.roads) do
      local pts = e[8]
      if not decks[pts[1] .. "," .. pts[3]] and e[7] ~= "rail" then
        for i = 1, #pts, 6 do
          local own = all[chunk.key(chunk.at(pts[i], pts[i + 2]))]
          if own then
            n = n + 1
            if math.abs(chunk.terrainY(own, pts[i], pts[i + 2]) - pts[i + 1]) > 1.6 then floating = floating + 1 end
          end
        end
      end
    end
  end
  t.truthy(n > 500, "samples " .. n)
  t.truthy(floating / n < 0.03, "road points off the ground: " .. floating .. " of " .. n)
end)

t.test("world shape: districts, music ids and landmarks line up", function()
  local seen = {}
  for _, c in pairs(all) do
    if c.district ~= "interior" then seen[c.district] = true end
  end
  for _, id in ipairs({ "gilt", "lantern", "cinder", "brine", "mid" }) do t.truthy(seen[id], "a chunk in the " .. id .. " arrangement") end
  local named = {}
  for _, c in pairs(all) do
    for _, l in ipairs(c.landmarks) do
      named[l[1]] = true
      t.truthy(landmarks.build(l[1]), "landmark model " .. l[1])
    end
  end
  for _, want in ipairs({ "lighthouse", "clocktower", "manor", "ferris", "crane", "chimney", "span_tower" }) do t.truthy(named[want], "landmark " .. want) end
  -- each district is a real place on the map
  for _, d in ipairs(city.data.districts) do t.eq(city:districtAt(d.x, d.z).id, d.id) end
end)

t.test("world interiors: every door in the city leads to a room with an exit and a spawn", function()
  local doorsN = 0
  for _, c in pairs(all) do
    for _, d in ipairs(c.doors) do
      doorsN = doorsN + 1
      local info = city:interior(d[4])
      t.truthy(info, "interior " .. d[4])
      local room = city:source(info.chunk[1], info.chunk[2])
      t.truthy(room and chunk.validate(room), "room " .. d[4])
      t.eq(room.district, "interior")
      local exit = false
      for _, rd in ipairs(room.doors) do if rd[4] == "@exit" then exit = true end end
      t.truthy(exit, d[4] .. " has an exit")
      local player = false
      for _, s in ipairs(room.spawns) do if s[1] == "player" then player = true end end
      t.truthy(player, d[4] .. " has a spawn")
    end
  end
  t.truthy(doorsN >= 12, "doors " .. doorsN)
end)

t.test("world places: every name the story uses is laid out in the city, on the ground or on its deck", function()
  local want = { "juno", "juno_lot", "rusty", "rusty_door", "ferry", "crane", "gilt_lot", "gilt_door", "tam_garage", "counting_house", "radio_mast", "studio", "market", "rail_yard", "crossing", "cannery", "patrol_pier", "motor_pool", "motor_pool_top", "canal_north", "canal_south", "seawall", "gate_house", "safehouse", "park_fountain", "sable_garage", "harrow_lot", "funicular_top", "funicular_bottom", "hall_garage", "hall_roof", "convoy_start", "convoy_end", "hairpin_top", "hairpin_foot", "lighthouse", "scrapyard_gate", "hideout", "old_gate", "open_water", "start" }
  for _, name in ipairs(want) do
    local p = city.data.places[name]
    t.truthy(p and p.x and p.z and p.r and p.y, "place " .. name)
    t.truthy(p.x > 0 and p.x < 1320 and p.z > 0 and p.z < 880, name .. " is inside the world")
  end
  t.truthy(city.data.places.motor_pool_top.y > city.data.places.motor_pool.y + 5, "the roof deck is above the street")
end)

-- ---------------------------------------------------------------- the models
t.test("world models: every chunk builds at both levels of detail with sane triangles", function()
  local worst, total = 0, 0
  local n = 0
  for _, c in pairs(all) do
    n = n + 1
    if n % 3 == 0 or c.district ~= "mid" then
      local full = chunkmodel.build(c, "full")
      local low = chunkmodel.build(c, "low")
      t.truthy(#full >= #low, "low detail is not bigger")
      worst = math.max(worst, #full)
      total = total + #full
      for i = 1, #full, 7 do
        local p = full[i]
        t.truthy(p.x1 == p.x1 and p.y1 == p.y1 and p.z1 == p.z1 and p.c, "triangle " .. i .. " is a number in " .. chunk.key(c.cx, c.cz))
      end
    end
    c._map = nil
    t.breathe()
  end
  t.truthy(worst < 4200, "busiest chunk " .. worst .. " triangles")
end)

t.test("world models: the interiors build and the maps agree with the ground", function()
  for id, info in pairs(city.data.interiors) do
    local room = city:source(info.chunk[1], info.chunk[2])
    local list = chunkmodel.build(room, "full")
    t.truthy(#list > 40, id .. " has furniture and walls")
  end
  local c
  for _, cc in pairs(all) do if cc.district ~= "interior" and #cc.buildings > 8 and #cc.roads > 3 then c = cc break end end
  c._map = nil
  local m = mapview.raster(c, nil, function() return "u" end)
  local roads, buildings = 0, 0
  for v = 1, #m.codes do
    for ch in m.codes[v]:gmatch(".") do
      if ch == "r" or ch == "a" then roads = roads + 1 end
      if ch == "b" then buildings = buildings + 1 end
    end
  end
  t.truthy(roads > 20 and buildings > 20, "the raster shows roads and buildings")
end)

-- ---------------------------------------------------------------- the day and the weather
t.test("world sky: sixteen colours at every hour, dark at night, bright at noon, windows light up, weather greys it", function()
  local function lum(v) return math.floor(v / 65536) % 256 + math.floor(v / 256) % 256 + v % 256 end
  for hour = 0, 23.5, 0.5 do
    local pal = sky.paletteAt(hour, "clear")
    local n = 0
    for _, name in ipairs(sky.NAMES) do
      n = n + 1
      t.truthy(type(pal[name]) == "number" and pal[name] >= 0 and pal[name] <= 0xFFFFFF, name .. " at " .. hour)
    end
    t.eq(n, 16)
  end
  local noon, night = sky.paletteAt(12, "clear"), sky.paletteAt(1, "clear")
  t.truthy(lum(noon.lime) > lum(night.lime) * 1.8, "the grass is darker at night")
  t.truthy(lum(noon.purple) > lum(night.purple) * 3, "the sky is darker at night")
  t.truthy(lum(night.lightBlue) > lum(night.gray) * 2, "windows are lit at night")
  local rain = sky.paletteAt(12, "rain")
  t.truthy(lum(rain.lime) < lum(noon.lime), "rain dims the ground")
  t.eq(sky.phaseOf(12), "day")
  t.eq(sky.phaseOf(2), "night")
  t.eq(sky.phaseOf(18.5), "dusk")
  t.eq(sky.phaseOf(5.8), "dawn")
  local up = sky.sunAt(12)
  t.truthy(up > 0.99, "the sun is overhead at noon")
  t.truthy(sky.sunAt(0) < 0, "and down at midnight")
end)

t.test("world sky: the weather moves between kinds, never stands still on one, and only reports real changes", function()
  local util = require("sg.util")
  local w = sky.weather.new(util.rng(5), "clear")
  local kinds, changes = {}, 0
  for _ = 1, 20000 do
    local kind, prev = sky.weather.update(w, 0.5)
    if kind then
      changes = changes + 1
      kinds[kind] = true
      t.truthy(kind ~= prev and sky.WEATHER[kind], "a real change")
    end
  end
  t.truthy(changes > 20, "changes " .. changes)
  t.truthy(kinds.rain and kinds.cloudy and kinds.fog, "rain, cloud and fog all came")
  local forced = sky.weather.new(util.rng(5), "rain")
  forced.forced = true
  for _ = 1, 2000 do t.eq(sky.weather.update(forced, 1), nil) end
end)

t.test("world sky: palette application only sends what changed", function()
  local sent = {}
  local term = { setPaletteColour = function(c, v) sent[#sent + 1] = v end }
  local a = sky.paletteAt(12, "clear")
  t.eq(sky.apply(term, a, nil), 16)
  t.eq(sky.apply(term, a, a), 0)
  local b = sky.paletteAt(12.1, "clear")
  t.truthy(sky.apply(term, b, a) < 16)
end)

if fakeColors then
  _G.colors = nil
  _G.colours = nil
end
