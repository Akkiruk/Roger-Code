-- world/city.lua
-- The real city's data: which districts are where, and the chunks, read from content/world/*.sgc (written by
-- tools/saltgate/citybuild.mjs). The streamer asks city:source(cx, cz) for a chunk; interiors are chunks a long way
-- from the city (content/interiors/*.sgc), so walking through a door is a move to another place in the same world.
--
--   local city = cityLib.new(content)          content is a core/content.lua reader; nil when there is no city installed
--   city.data                                  world/world.lua: islands, districts, spawn, features, interiors
--   city:source(cx, cz) -> chunk or nil        for core/stream.lua (may yield to spread its work)
--   city:districtAt(x, z) -> district          { id, name, music, x, z, w, island }
--   city:islandAt(x, z) -> island id
--   city:chunks() -> { ["cx,cz"] = chunk }     every world chunk (the map reads this; slow, used once)
--   city:interior(id) -> info                  { name, chunk, size, floor, spawn, exit }

local chunkLib = require("sg.core.chunk")

local M = {}
local C = {}
C.__index = C

local sqrt = math.sqrt
local floor = math.floor

function M.new(content)
  local data = content and content:data("world/world.lua")
  if not data then return nil end
  local self = setmetatable({ content = content, data = data, texts = {}, order = {}, interiorByChunk = {} }, C)
  for id, info in pairs(data.interiors or {}) do
    self.interiorByChunk[info.chunk[1] .. "," .. info.chunk[2]] = id
  end
  return self
end

function C:islandAt(x, z)
  local best, bd = nil, -1e9
  for _, i in ipairs(self.data.islands) do
    local dx, dz = (x - i.cx) / i.rx, (z - i.cz) / i.rz
    local d = 1 - sqrt(dx * dx + dz * dz)
    if d > bd then best, bd = i.id, d end
  end
  return best
end

function C:districtAt(x, z)
  local isl = self:islandAt(x, z)
  local best, bd = nil, 1e18
  for _, d in ipairs(self.data.districts) do
    if d.island == isl then
      local dx, dz = x - d.x, z - d.z
      local v = sqrt(dx * dx + dz * dz) - d.w
      if v < bd then best, bd = d, v end
    end
  end
  return best or self.data.districts[1]
end

function C:interior(id)
  return self.data.interiors and self.data.interiors[id]
end

--- Which district names the chunk (what music and the app's district_enter use): the music id of its middle.
function C:musicAt(x, z)
  return self:districtAt(x, z).music
end

local function fileText(self, path)
  local hit = self.texts[path]
  if hit then return hit end
  local text = self.content:text(path)
  if not text then return nil end
  text = "\n" .. text
  self.texts[path] = text
  self.order[#self.order + 1] = path
  -- keep the two newest files: a chunk's file is read once while the ring round you loads, then stays a while
  while #self.order > 3 do self.texts[table.remove(self.order, 1)] = nil end
  return text
end

local function findLine(text, cx, cz)
  local needle = "\nSGC2;" .. cx .. ";" .. cz .. ";"
  local at = text:find(needle, 1, true)
  if not at then return nil end
  local stop = text:find("\n", at + 1, true) or (#text + 1)
  return text:sub(at + 1, stop - 1)
end

local function maybeYield()
  if coroutine.running() then coroutine.yield() end
end

function C:source(cx, cz)
  local interior = self.interiorByChunk[cx .. "," .. cz]
  if interior then
    local text = self.content:text("interiors/" .. interior .. ".sgc")
    maybeYield()
    return text and chunkLib.unpack(text:match("[^\n]+") or "") or nil
  end
  local block = self.data.block
  local path = "world/w_" .. floor(cx / block) .. "_" .. floor(cz / block) .. ".sgc"
  local text = fileText(self, path)
  if not text then return nil end
  maybeYield()
  local line = findLine(text, cx, cz)
  if not line then return nil end
  local c = chunkLib.unpack(line)
  maybeYield()
  return c
end

--- The whole-city map picture (content/world/map.txt): { w, h, res, codes = { row strings }, heights = { row strings } }.
function C:mapImage()
  if self.image then return self.image end
  local text = self.content:text("world/map.txt")
  if not text then return nil end
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
  local w, h, res = lines[1]:match("^(%d+) (%d+) (%d+)")
  w, h, res = tonumber(w), tonumber(h), tonumber(res)
  local img = { w = w, h = h, res = res, codes = {}, heights = {} }
  for v = 1, h do
    img.codes[v] = lines[1 + v]
    img.heights[v] = lines[1 + h + v]
  end
  self.image = img
  return img
end

--- The far skyline: { w, h, res, rows } with the highest thing in each cell (a char per cell, 1 unit a step from -9).
function C:skyline()
  local s = self.data.skyline
  if s and not s.ready then
    s.ready = true
    s.top = {}
    for v = 1, s.h do
      local row, out = s.rows[v], {}
      for u = 1, s.w do out[u] = row:byte(u) - 35 - 9 end
      s.top[v] = out
    end
  end
  return s
end

--- Every world chunk (for the whole-city map). Reads every file once.
function C:chunks()
  if self.all then return self.all end
  local out = {}
  local data = self.data
  local b = data.bounds
  for cz = b[2], b[4] do
    for cx = b[1], b[3] do
      local c = self:source(cx, cz)
      if c then out[chunkLib.key(cx, cz)] = c end
    end
  end
  self.all = out
  return out
end

return M
