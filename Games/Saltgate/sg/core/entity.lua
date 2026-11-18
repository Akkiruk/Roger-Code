-- core/entity.lua
-- The entity world: everything that moves or can be met (cars, people, boats, pickups, the helicopter) is an entity,
-- a plain table of components. Systems update them in a fixed order, near ones every frame and far ones less often.
-- Pure.
--
-- An entity (all fields optional except kind):
--   kind      "car" | "bike" | "boat" | "truck" | "ped" | "cop" | "pickup" | "heli" | ... (free text)
--   x, y, z   position (y up; y defaults to the ground)
--   h         heading in radians (forward is (cos h, sin h) in x, z)
--   vx, vz    velocity, if it has one
--   radius    collision circle
--   health
--   tags      { name = true, ... } for each(tag)
--   model     a key the renderer understands
--   ai        whatever its AI system keeps
--   lod       "near" | "mid" | "far": set by the world each frame from the focus point
--
--   local world = entity.new({ cell = 32 })
--   local e = world:add({ kind = "car", x = 10, z = 20, tags = { traffic = true } })
--   world:move(e, x, z)            -- always move through this so near() stays right
--   for _, e in ipairs(world:each("traffic")) do ... end
--   world:near(x, z, 30, "cop")    -- entities within 30 units, optionally with a tag
--   world:system({ name = "traffic", order = 20, rate = nil, update = function(world, dt) end })
--   world:update(dt)               -- runs the systems; a rate (Hz) system gets its own accumulated dt

local M = {}
local World = {}
World.__index = World

M.NEAR, M.MID = 60, 120 -- level-of-detail distances from the focus

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    cell = opts.cell or 32,
    nextId = 0,
    list = {},
    byId = {},
    grid = {},
    tagged = {},
    systems = {},
    focusX = 0, focusZ = 0,
    timer = opts.timer, -- optional function(name, fn) used by the budget to time each system
  }, World)
end

local function cellKey(world, x, z)
  local c = world.cell
  return math.floor(x / c) .. "," .. math.floor(z / c)
end

local function gridAdd(world, e)
  local key = cellKey(world, e.x or 0, e.z or 0)
  e._cell = key
  local bucket = world.grid[key]
  if not bucket then
    bucket = {}
    world.grid[key] = bucket
  end
  bucket[e] = true
end

local function gridRemove(world, e)
  local bucket = e._cell and world.grid[e._cell]
  if bucket then
    bucket[e] = nil
    if next(bucket) == nil then world.grid[e._cell] = nil end
  end
  e._cell = nil
end

function World:add(e)
  if type(e) ~= "table" or type(e.kind) ~= "string" then error("entity needs a kind", 2) end
  self.nextId = self.nextId + 1
  e.id = e.id or self.nextId
  e.x, e.z = e.x or 0, e.z or 0
  self.list[#self.list + 1] = e
  self.byId[e.id] = e
  gridAdd(self, e)
  for tag in pairs(e.tags or {}) do
    local set = self.tagged[tag]
    if not set then
      set = {}
      self.tagged[tag] = set
    end
    set[e] = true
  end
  return e
end

function World:remove(e)
  if not self.byId[e.id] then return false end
  self.byId[e.id] = nil
  gridRemove(self, e)
  for tag in pairs(e.tags or {}) do
    local set = self.tagged[tag]
    if set then set[e] = nil end
  end
  for i = #self.list, 1, -1 do
    if self.list[i] == e then table.remove(self.list, i) break end
  end
  e.removed = true
  return true
end

function World:get(id)
  return self.byId[id]
end

--- Move an entity (keeps the spatial index right).
function World:move(e, x, z)
  e.x, e.z = x, z
  local key = cellKey(self, x, z)
  if key ~= e._cell then
    gridRemove(self, e)
    gridAdd(self, e)
  end
end

function World:tag(e, tag, on)
  e.tags = e.tags or {}
  local set = self.tagged[tag]
  if on then
    e.tags[tag] = true
    if not set then
      set = {}
      self.tagged[tag] = set
    end
    set[e] = true
  else
    e.tags[tag] = nil
    if set then set[e] = nil end
  end
end

--- Entities with a tag (or all), in the order they were added. A fresh list: safe to remove while walking it.
function World:each(tag)
  local out = {}
  if not tag then
    for i = 1, #self.list do out[i] = self.list[i] end
    return out
  end
  local set = self.tagged[tag]
  if not set then return out end
  for i = 1, #self.list do
    local e = self.list[i]
    if set[e] then out[#out + 1] = e end
  end
  return out
end

function World:count(tag)
  if not tag then return #self.list end
  local n = 0
  for _ in pairs(self.tagged[tag] or {}) do n = n + 1 end
  return n
end

--- Entities within r of (x, z), nearest first, optionally only those with tag.
function World:near(x, z, r, tag)
  local c = self.cell
  local out = {}
  local set = tag and self.tagged[tag]
  if tag and not set then return out end
  local x0, x1 = math.floor((x - r) / c), math.floor((x + r) / c)
  local z0, z1 = math.floor((z - r) / c), math.floor((z + r) / c)
  local r2 = r * r
  for gx = x0, x1 do
    for gz = z0, z1 do
      local bucket = self.grid[gx .. "," .. gz]
      if bucket then
        for e in pairs(bucket) do
          if not set or set[e] then
            local dx, dz = e.x - x, e.z - z
            local d2 = dx * dx + dz * dz
            if d2 <= r2 then out[#out + 1] = { e = e, d2 = d2 } end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.d2 ~= b.d2 then return a.d2 < b.d2 end
    return a.e.id < b.e.id
  end)
  for i = 1, #out do out[i] = out[i].e end
  return out
end

--- Add a system: { name, order (lower first), rate (Hz, nil for every frame), update(world, dt) }.
function World:system(sys)
  if type(sys.name) ~= "string" or type(sys.update) ~= "function" then error("a system needs a name and update", 2) end
  for _, s in ipairs(self.systems) do
    if s.name == sys.name then error("system '" .. sys.name .. "' already exists", 2) end
  end
  sys.order = sys.order or 50
  sys.acc = 0
  self.systems[#self.systems + 1] = sys
  table.sort(self.systems, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  return sys
end

function World:removeSystem(name)
  for i, s in ipairs(self.systems) do
    if s.name == name then table.remove(self.systems, i) return true end
  end
  return false
end

--- Where "near" is measured from (the player, or the camera).
function World:focus(x, z)
  self.focusX, self.focusZ = x, z
end

--- Run the systems for dt seconds, and mark each entity's level of detail.
function World:update(dt)
  local fx, fz = self.focusX, self.focusZ
  local near2, mid2 = M.NEAR * M.NEAR, M.MID * M.MID
  for i = 1, #self.list do
    local e = self.list[i]
    local dx, dz = e.x - fx, e.z - fz
    local d2 = dx * dx + dz * dz
    e.lod = d2 <= near2 and "near" or (d2 <= mid2 and "mid" or "far")
  end
  for _, sys in ipairs(self.systems) do
    local step = dt
    local run = true
    if sys.rate then
      sys.acc = sys.acc + dt
      if sys.acc < 1 / sys.rate then
        run = false
      else
        step = sys.acc
        sys.acc = 0
      end
    end
    if run then
      if self.timer then
        self.timer(sys.name, function() sys.update(self, step) end)
      else
        sys.update(self, step)
      end
    end
  end
end

return M
