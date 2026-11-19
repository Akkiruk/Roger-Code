-- activities/layout.lua
-- Where the side activities are in a given city. The city's chunks go in; out comes a layout table: 50 gull totems, 10
-- postcards, up to 20 stunt jumps, street races along real curved and hilly routes of the road graph, taxi ranks and
-- parcel depots, shops, garages, properties, and the spots fares and parcels go to. It is deterministic (a seed), so the
-- same city always gives the same layout. A tool writes it to content/activities/layout.lua (see Tests/saltgate_genlayout.lua) and the
-- game only reads that file: a new city means running the tool again.
--
--   layout.generate(chunks, { seed = 1 }) -> layout, warnings      chunks: { key = chunk } or a list
--   layout.serialise(layout) -> Lua source ("return { ... }")
--   layout.counts(layout) -> { totems = 50, ... }
--   layout.check(layout, chunks) -> list of problems (an item off the map, a race that does not follow a road)
--
-- Item positions are x, z (and y, the height there); headings are h in radians (forward is cos h, sin h).

local chunkLib = require("sg.core.chunk")
local geom = require("sg.core.geom")
local roadgraph = require("sg.core.roadgraph")
local util = require("sg.util")

local M = {}

M.TOTEMS = 50
M.POSTCARDS = 10
M.JUMPS = 20
M.RACES = 6

-- what the districts are called when the chunk says only their id (A's city may use others: the id is capitalised)
M.DISTRICT_NAMES = {
  gilt = "Gilt Heights", lantern = "Lantern Row", cinder = "Cinder Flats", brine = "Brine Docks", mid = "Old Saltgate",
}

local RACE_NAMES = { "Harbor Dash", "Hairpin Hustle", "Lantern Loop", "Cinder Sprint", "Gilt Ascent", "Coast Run", "Tidewater Cup",
  "Midnight Mile" }
local PROPERTY_NAMES = { "Gull's Rest flat", "Net Loft", "Chandlery Rooms", "Lamplighter's House", "Tide Clock Penthouse",
  "Harbour Master's Villa", "Smokehouse Studio", "Cove Cottage" }
local SHOP_NAMES = {
  respray = { "Paint & Pray", "Brine Brush Co.", "Second Coat" },
  tune = { "Rusty's Tune Bay", "Iron Flats Garage", "Torque & Tide" },
  clothes = { "Thread & Needle", "Gull Outfitters", "Dockside Duds" },
}
local GARAGE_NAMES = { "Quay Garage", "Hilltop Lockup", "Old Town Mews" }
local TAXI_NAMES = { "Quay Rank", "Station Rank", "Hill Rank" }
local DEPOT_NAMES = { "Net Depot", "Fish Market Depot", "Chandlery Depot" }

local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min
local atan2 = math.atan2 or math.atan

local function r1(v) return floor(v * 10 + 0.5) / 10 end

function M.districtName(id)
  if not id then return "Saltgate" end
  return M.DISTRICT_NAMES[id] or (tostring(id):gsub("^%l", string.upper):gsub("_", " "))
end

-- ---------------------------------------------------------------- the world as the generator sees it

local function world(chunks)
  local w = { byKey = {}, list = {}, x0 = math.huge, z0 = math.huge, x1 = -math.huge, z1 = -math.huge }
  for _, c in pairs(chunks) do
    w.byKey[chunkLib.key(c.cx, c.cz)] = c
    w.list[#w.list + 1] = c
  end
  table.sort(w.list, function(a, b)
    if a.cz ~= b.cz then return a.cz < b.cz end
    return a.cx < b.cx
  end)
  for _, c in ipairs(w.list) do
    local a, b, cc, d = chunkLib.bounds(c)
    w.x0, w.z0, w.x1, w.z1 = min(w.x0, a), min(w.z0, b), max(w.x1, cc), max(w.z1, d)
  end
  w.roads = roadgraph.new()
  for _, c in ipairs(w.list) do w.roads:addChunk(c) end
  return w
end

local function chunkAt(w, x, z)
  local cx, cz = chunkLib.at(x, z)
  return w.byKey[chunkLib.key(cx, cz)]
end

local function terrain(w, x, z)
  local c = chunkAt(w, x, z)
  if not c then return nil end
  return chunkLib.terrainY(c, x, z), c
end

--- Is a circle of radius pad at (x, z) clear of buildings, roads, ribbons and water? (looks at the 3x3 chunks round it)
-- Under CC a long layout (the whole city) would run past the 7 s limit without a yield: breathe, at most every 0.4 s
-- (and not at all under desktop Lua, where there is no os.queueEvent).
local lastBreath = 0
local function breathe()
  local os_ = rawget(_G, "os")
  if not (os_ and os_.queueEvent and os_.pullEvent and os_.epoch) then return end
  local now = os_.epoch("utc")
  if now - lastBreath < 400 then return end
  lastBreath = now
  os_.queueEvent("sg_layout_breathe")
  os_.pullEvent("sg_layout_breathe")
  lastBreath = os_.epoch("utc")
end
M.breathe = breathe

local function clear(w, x, z, pad)
  breathe()
  local c0 = chunkAt(w, x, z)
  if not c0 then return false end
  local y = chunkLib.terrainY(c0, x, z)
  local level = c0.water[1] and c0.water[1][1] or -1000
  if y < level + 0.8 then return false end
  for dz = -1, 1 do
    for dx = -1, 1 do
      local c = w.byKey[chunkLib.key(c0.cx + dx, c0.cz + dz)]
      if c then
        for _, b in ipairs(c.buildings) do
          if geom.inBox({ b[1], b[2], b[3] + pad * 2, b[4] + pad * 2, b[5] }, x, z) then return false end
        end
        for _, r in ipairs(c.roads) do
          if geom.polylineNearest(r[8], x, z) < r[4] / 2 + pad then return false end
        end
        for _, r in ipairs(c.ribbons) do
          if geom.polylineNearest(r[3], x, z) < r[2] / 2 + pad then return false end
        end
        for _, f in ipairs(c.floors) do
          if geom.inPolygon(f[3], x, z) then return false end
        end
      end
    end
  end
  return true, y, c0
end

--- Pick n of the candidates ({ x, z, ... }) as far from each other (and from fixed) as they go, starting from the one
-- the rng says. minSep stops two being closer than that.
local function spread(cands, n, rng, fixed, minSep)
  local chosen = {}
  if #cands == 0 then return chosen end
  local dmin = {}
  for i, c in ipairs(cands) do
    local d = math.huge
    for _, f in ipairs(fixed or {}) do d = min(d, util.dist(c.x, c.z, f.x, f.z)) end
    dmin[i] = d
  end
  local used = {}
  local first = #(fixed or {}) == 0 and rng(#cands) or nil
  for _ = 1, n do
    local best, bd = first, -1
    if not best then
      for i = 1, #cands do
        if not used[i] then
          -- farthest first, with a little of the candidate's own weight so spots with a view win ties
          local d = dmin[i] + (cands[i].weight or 0)
          if dmin[i] >= (minSep or 0) and d > bd then best, bd = i, d end
        end
      end
    end
    if not best then break end
    first = nil
    used[best] = true
    chosen[#chosen + 1] = cands[best]
    for i, c in ipairs(cands) do
      if not used[i] then
        local d = util.dist(c.x, c.z, cands[best].x, cands[best].z)
        if d < dmin[i] then dmin[i] = d end
      end
    end
  end
  return chosen
end

-- ---------------------------------------------------------------- totems and postcards

local function landCandidates(w, step, pad)
  local out = {}
  local x = w.x0 + step / 2
  while x < w.x1 do
    local z = w.z0 + step / 2
    while z < w.z1 do
      local ok, y, c = clear(w, x, z, pad)
      if ok then out[#out + 1] = { x = x, z = z, y = y, district = c.district, weight = 0 } end
      z = z + step
    end
    x = x + step
  end
  return out
end

-- ---------------------------------------------------------------- roadside spots (shops, ranks, depots, destinations)

local DRIVABLE = { road = true, avenue = true, highway = true }

--- Points beside drivable roads, every ~step units, a little off the kerb, facing the road. Doors of buildings come first.
local function roadside(w, step, rng)
  local out = {}
  local edges = {}
  for _, e in pairs(w.roads.edges) do
    if DRIVABLE[e.kind] then edges[#edges + 1] = e end
  end
  table.sort(edges, function(a, b) return a.id < b.id end)
  for _, e in ipairs(edges) do
    local s = 8 + rng() * 6
    while s < e.length - 8 do
      for _, side in ipairs({ 1, -1 }) do
        local off = e.width / 2 + 3.5
        local x, y, z, dx, dz = w.roads:pointAt(e, s, side * off)
        local ok, ty, c = clear(w, x, z, 1.2)
        if ok then
          -- face the road: the spot is side * off along the edge's right-hand vector (-dz, dx)
          local h = atan2(-side * dx, side * dz)
          out[#out + 1] = { x = x, z = z, y = ty, h = h, district = c.district, road = e.id }
        end
      end
      s = s + step
    end
  end
  return out
end

-- ---------------------------------------------------------------- jumps

local function jumpCandidates(w)
  local out = {}
  -- ramps: the launch is the high end
  for _, c in ipairs(w.list) do
    for _, r in ipairs(c.ribbons) do
      if r[1] == "ramp" then
        local p = r[3]
        local n = #p
        local x, y, z = p[n - 2], p[n - 1], p[n]
        local dx, dz = p[n - 2] - p[n - 5], p[n] - p[n - 3]
        local len = sqrt(dx * dx + dz * dz)
        if len > 0 and p[n - 1] > p[n - 4] then
          out[#out + 1] = { x = x, z = z, y = y, h = atan2(dz, dx), min = 12, kind = "ramp", district = c.district, weight = 30 }
        end
      end
    end
  end
  -- crests: a drivable road that rises, tops out and drops away
  local edges = {}
  for _, e in pairs(w.roads.edges) do
    if DRIVABLE[e.kind] then edges[#edges + 1] = e end
  end
  table.sort(edges, function(a, b) return a.id < b.id end)
  for _, e in ipairs(edges) do
    for _, dir in ipairs({ 1, -1 }) do
      local s = 10
      while s < e.length - 24 do
        local sx, sy, sz, dx, dz = geom.polylineAt(e.pts, dir == 1 and s or e.length - s)
        local _, y1 = geom.polylineAt(e.pts, dir == 1 and s - 8 or e.length - s + 8)
        local _, y2 = geom.polylineAt(e.pts, dir == 1 and s + 18 or e.length - s - 18)
        local _, y3 = geom.polylineAt(e.pts, dir == 1 and s + 4 or e.length - s - 4)
        if sy - y1 > 0.3 and sy - y2 > 1.0 and y3 <= sy + 0.2 then
          local c = chunkAt(w, sx, sz)
          out[#out + 1] = { x = sx, z = sz, y = sy, h = atan2(dir * dz, dir * dx), min = 8, kind = "crest",
            district = c and c.district, weight = (sy - y2) }
          s = s + 40
        end
        s = s + 3
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- races

local function routeFrom(w, fromId, toId)
  breathe()
  local nodes, edges = w.roads:path(fromId, toId, DRIVABLE)
  if not nodes or #edges < 3 then return nil end
  local flat = {}
  local at = fromId
  for _, e in ipairs(edges) do
    local pts = e.pts
    if e.a == at then
      for i = 1, #pts, 3 do flat[#flat + 1] = pts[i] flat[#flat + 1] = pts[i + 1] flat[#flat + 1] = pts[i + 2] end
      at = e.b
    else
      for i = #pts - 2, 1, -3 do flat[#flat + 1] = pts[i] flat[#flat + 1] = pts[i + 1] flat[#flat + 1] = pts[i + 2] end
      at = e.a
    end
  end
  -- resample every 12 units
  local len = geom.polylineLength(flat)
  local out = {}
  local s = 0
  while s < len do
    local x, y, z = geom.polylineAt(flat, s)
    out[#out + 1] = r1(x) out[#out + 1] = r1(y) out[#out + 1] = r1(z)
    s = s + 12
  end
  local x, y, z = geom.polylineAt(flat, len)
  out[#out + 1] = r1(x) out[#out + 1] = r1(y) out[#out + 1] = r1(z)
  return out, len
end

local function routeScore(pts, len)
  local turn, lo, hi = 0, math.huge, -math.huge
  local lastH
  for i = 1, #pts - 3, 3 do
    local h = atan2(pts[i + 5] - pts[i + 2], pts[i + 3] - pts[i])
    if lastH then turn = turn + abs(util.wrap(h - lastH)) end
    lastH = h
    lo, hi = min(lo, pts[i + 1]), max(hi, pts[i + 1])
  end
  return min(len, 700) / 100 + turn * 1.2 + (hi - lo) * 0.3, turn, hi - lo
end

local function races(w, rng, warnings)
  local nodeIds = {}
  for id, n in pairs(w.roads.nodes) do
    local ok = false
    for _, e in ipairs(n.edges) do if DRIVABLE[e.kind] then ok = true end end
    if ok and n.x then nodeIds[#nodeIds + 1] = id end
  end
  table.sort(nodeIds)
  local out, starts = {}, {}
  if #nodeIds < 2 then return out end
  for r = 1, M.RACES do
    local best, bestScore = nil, -1
    for _ = 1, 60 do
      local a = w.roads.nodes[nodeIds[rng(#nodeIds)]]
      local b = w.roads.nodes[nodeIds[rng(#nodeIds)]]
      local d = util.dist(a.x, a.z, b.x, b.z)
      local apart = true
      for _, s in ipairs(starts) do
        if util.dist(a.x, a.z, s.x, s.z) < 60 then apart = false end
      end
      if d > 180 and d < 520 and apart then
        local pts, len = routeFrom(w, a.id, b.id)
        if pts and len >= 250 then
          local score, turn, rise = routeScore(pts, len)
          if score > bestScore then best, bestScore = { a = a, b = b, pts = pts, len = len, turn = turn, rise = rise }, score end
        end
      end
    end
    if best then
      starts[#starts + 1] = best.a
      local c = chunkAt(w, best.a.x, best.a.z)
      local c2 = chunkAt(w, best.b.x, best.b.z)
      local gold = best.len / 17 + best.turn * 0.6
      local pay = floor((150 + best.len * 0.5) / 10 + 0.5) * 10
      out[#out + 1] = {
        id = "race" .. r, name = RACE_NAMES[r] or ("Race " .. r), pts = best.pts, cp = 4, length = r1(best.len),
        turn = r1(best.turn), rise = r1(best.rise),
        from = M.districtName(c and c.district), to = M.districtName(c2 and c2.district),
        gold = r1(gold), silver = r1(gold * 1.18), bronze = r1(gold * 1.4),
        pay = { gold = pay, silver = floor(pay * 0.6 / 10 + 0.5) * 10, bronze = floor(pay * 0.3 / 10 + 0.5) * 10 },
      }
    else
      warnings[#warnings + 1] = "race " .. r .. ": no route of 250+ units found"
    end
  end
  return out
end

-- ---------------------------------------------------------------- the whole layout

local POSTCARDS = {
  "Greetings from the harbour. The gulls here steal chips and opinions in equal measure.",
  "Wish you were here. Not for the weather. For the view.",
  "They told me the tide goes out. They did not say how far. Come see.",
  "Found the best chowder in town. Cannot tell you where. A gull is reading over my shoulder.",
  "Lamps lit at five, bells at six, nobody sleeps. Love it.",
  "Drove the hill road with my eyes shut. Do not recommend. Do recommend the view.",
  "The crane at the docks has a name. The crane at the docks has a union.",
  "Rain on the water looks like the whole bay is thinking. Send umbrellas.",
  "Left a coin under the clock. Take it, or the gulls will.",
  "Last card. The tide came in. So did everyone you know. Saltgate keeps its people.",
}
M.POSTCARD_TEXT = POSTCARDS

--- A layout for the city. Returns the layout table and a list of warnings (things the city could not give).
function M.generate(chunks, opts)
  opts = opts or {}
  local rng = util.rng(opts.seed or 1)
  local w = world(chunks)
  local warnings = {}
  local out = { seed = opts.seed or 1 }

  -- totems and postcards: spread over every bit of open ground, postcards favouring the high ground
  local land = landCandidates(w, opts.step or 8, 2)
  local lo, hi = math.huge, -math.huge
  for _, c in ipairs(land) do lo, hi = min(lo, c.y), max(hi, c.y) end
  for _, c in ipairs(land) do c.weight = (c.y - lo) / max(1, hi - lo) * 6 end
  local totems = spread(land, M.TOTEMS, rng, nil, 14)
  if #totems < M.TOTEMS then warnings[#warnings + 1] = "only " .. #totems .. " totem spots" end
  local cards = spread(land, M.POSTCARDS, rng, totems, 20)
  if #cards < M.POSTCARDS then warnings[#warnings + 1] = "only " .. #cards .. " postcard spots" end
  out.totems = {}
  for i, c in ipairs(totems) do
    out.totems[i] = { id = "totem" .. i, x = r1(c.x), z = r1(c.z), y = r1(c.y), district = c.district }
  end
  out.postcards = {}
  for i, c in ipairs(cards) do
    out.postcards[i] = { id = "card" .. i, x = r1(c.x), z = r1(c.z), y = r1(c.y), district = c.district,
      name = "Postcard " .. i .. ": " .. M.districtName(c.district), text = POSTCARDS[i] or POSTCARDS[1] }
  end

  -- stunt jumps
  local jc = jumpCandidates(w)
  local jumps = spread(jc, M.JUMPS, rng, nil, 14)
  if #jumps < M.JUMPS then warnings[#warnings + 1] = "only " .. #jumps .. " places to jump (" .. M.JUMPS .. " wanted)" end
  out.jumps = {}
  for i, j in ipairs(jumps) do
    out.jumps[i] = { id = "jump" .. i, name = "Jump " .. i .. ": " .. M.districtName(j.district), x = r1(j.x), z = r1(j.z),
      y = r1(j.y), h = r1(j.h * 100) / 100, min = j.min, district = j.district }
  end

  -- races
  out.races = races(w, rng, warnings)

  -- the roadside: ranks, depots, shops, garages, properties and the spots fares and parcels go to
  local side = roadside(w, 18, rng)
  local doors = {}
  for _, c in ipairs(w.list) do
    for _, d in ipairs(c.doors) do doors[#doors + 1] = { x = d[1], z = d[2], y = d[3], h = 0, district = c.district, door = d[4] } end
  end
  local fixed = {}
  local function place(n, names, extra, pool)
    local picks = spread(pool or side, n, rng, fixed, 22)
    local res = {}
    for i, p in ipairs(picks) do
      fixed[#fixed + 1] = p
      local item = { id = (extra.id or "p") .. i, name = names[i] or (extra.label .. " " .. i), x = r1(p.x), z = r1(p.z),
        y = r1(p.y or 0), h = r1((p.h or 0) * 100) / 100, district = p.district }
      for k, v in pairs(extra) do if k ~= "id" and k ~= "label" then item[k] = v end end
      res[#res + 1] = item
    end
    return res
  end
  out.taxi = place(3, TAXI_NAMES, { id = "rank", label = "Rank" })
  out.depots = place(3, DEPOT_NAMES, { id = "depot", label = "Depot" })
  out.shops = {}
  for _, kind in ipairs({ "respray", "tune", "clothes" }) do
    for _, s in ipairs(place(2, SHOP_NAMES[kind], { id = kind, label = kind, kind = kind })) do out.shops[#out.shops + 1] = s end
  end
  out.garages = place(3, GARAGE_NAMES, { id = "garage", label = "Garage" })
  out.properties = {}
  local prices = { 12000, 20000, 28000, 40000, 60000, 90000 }
  local pool = #doors >= 6 and doors or side
  for i, p in ipairs(place(6, PROPERTY_NAMES, { id = "home", label = "Home" }, pool)) do
    p.price = prices[i]
    p.income = floor(prices[i] / 40 / 10 + 0.5) * 10 -- a day's rent: 1/40 of the price
    p.slots = 2
    out.properties[#out.properties + 1] = p
  end
  -- where fares and parcels go: every roadside spot is a candidate, thinned
  local dest = spread(side, 40, rng, nil, 30)
  out.spots = {}
  for i, p in ipairs(dest) do
    out.spots[i] = { id = "spot" .. i, name = M.districtName(p.district) .. " " .. i, x = r1(p.x), z = r1(p.z), y = r1(p.y or 0),
      district = p.district }
  end
  if #out.spots < 10 then warnings[#warnings + 1] = "only " .. #out.spots .. " places for fares and parcels" end
  return out, warnings
end

function M.counts(l)
  local out = {}
  for _, k in ipairs({ "totems", "postcards", "jumps", "races", "taxi", "depots", "shops", "garages", "properties", "spots" }) do
    out[k] = #(l[k] or {})
  end
  return out
end

-- ---------------------------------------------------------------- checks

--- Problems in a layout against the city: items that stand off the map, races that leave the roads.
function M.check(l, chunks)
  local w = world(chunks)
  local bad = {}
  local function on(item, kind)
    if not chunkAt(w, item.x, item.z) then bad[#bad + 1] = kind .. " " .. tostring(item.id) .. " is off the map" end
  end
  for _, k in ipairs({ "totems", "postcards", "jumps", "taxi", "depots", "shops", "garages", "properties", "spots" }) do
    for _, item in ipairs(l[k] or {}) do on(item, k) end
  end
  -- a totem or a postcard must stand on open ground (not in a building, on a road or in the sea)
  for _, k in ipairs({ "totems", "postcards" }) do
    for _, item in ipairs(l[k] or {}) do
      if chunkAt(w, item.x, item.z) and not clear(w, item.x, item.z, 0.8) then
        bad[#bad + 1] = k .. " " .. tostring(item.id) .. " is inside a building, on a road or in the water"
      end
    end
  end
  for _, r in ipairs(l.races or {}) do
    local off = 0
    for i = 1, #r.pts, 3 do
      local e, _, d = w.roads:nearest(r.pts[i], r.pts[i + 2], 6)
      if not e then off = off + 1 end
      local _ = d
    end
    if off > 0 then bad[#bad + 1] = "race " .. r.id .. " leaves the road at " .. off .. " points" end
  end
  return bad
end

-- ---------------------------------------------------------------- writing it out

local function ser(v, indent)
  local t = type(v)
  if t == "number" then
    if v == floor(v) then return string.format("%d", v) end
    return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    -- a flat list of numbers goes on lines of 12
    local isList = #v > 0
    local allNum = isList
    for i = 1, #v do if type(v[i]) ~= "number" then allNum = false break end end
    if allNum then
      local parts = {}
      for i = 1, #v do parts[#parts + 1] = ser(v[i]) end
      local lines = {}
      for i = 1, #parts, 12 do lines[#lines + 1] = indent .. "  " .. table.concat(parts, ",", i, min(i + 11, #parts)) end
      return "{\n" .. table.concat(lines, ",\n") .. "\n" .. indent .. "}"
    end
    local keys = {}
    for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for i = 1, #v do parts[#parts + 1] = indent .. "  " .. ser(v[i], indent .. "  ") end
    for _, k in ipairs(keys) do parts[#parts + 1] = indent .. "  " .. k .. " = " .. ser(v[k], indent .. "  ") end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function M.serialise(l)
  return "-- Generated by Tests/saltgate_genlayout.lua from the city's chunks. Do not edit by hand: run the tool again.\n" ..
    "return " .. ser(l, "") .. "\n"
end

return M
