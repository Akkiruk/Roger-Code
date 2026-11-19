-- activities/services.lua
-- What money buys: shops (respray, tune, clothes), property that pays rent, and the garage that keeps your cars. Pure
-- rules; the screens that show them are built by plugins/e_activities.lua. Every price goes through the wallet.
--
--   local shops = services.shops(ctx, catalog, section)      shops:respray(colour) :buyTune(slot) :buyOutfit(id) :wear(id)
--   local prop = services.property(ctx, layout, section)     prop:buy(id) :advance(hours) :dailyIncome() :slots() :counts()
--   local garage = services.garage(ctx, catalog, prop)       garage:store(car, place) :takeOut(i, place) :capacity()
-- Each action returns true, or false and the reason to show.

local wallet = require("sg.progress.wallet")
local vehicleLib = require("sg.vehicle")

local M = {}

local function toast(ctx, ...)
  if ctx.hud then ctx.hud.toast(...) end
end

local function goal(ctx, section, name)
  section.goals[name] = true
  local _ = ctx
end

-- ---------------------------------------------------------------- shops

local Shops = {}
Shops.__index = Shops

function M.shops(ctx, catalog, section)
  return setmetatable({ ctx = ctx, catalog = catalog, section = section }, Shops)
end

function Shops:use(section) self.section = section end

local function entryFor(ctx, car)
  for _, e in ipairs(ctx.save.garage.cars or {}) do
    if e.id and e.id == car.garageId then return e end
  end
  return nil
end

function Shops:respray(colour)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  if car.colour == colour then return false, "It is already that colour." end
  local ok = wallet.spend(ctx, self.catalog.respray.price, "respray")
  if not ok then return false, "Not enough money." end
  car.colour = colour
  if type(car.paint) == "table" then car.paint.body = colour end
  local e = entryFor(ctx, car)
  if e then e.colour = colour end
  if ctx.progress then ctx.progress.stats:add("resprays", 1) end
  goal(ctx, self.section, "respray")
  self.section.goals.respray = true
  toast(ctx, "Fresh paint", "magenta", 3, colour)
  return true
end

function Shops:tierOf(slot)
  local car = self.ctx.player.car
  return car and car.tune and car.tune[slot] or 0
end

--- The tune slots for the car you are in (from its definition if B's data gives one, else the catalog's four).
function Shops:slots()
  local def
  local car = self.ctx.player.car
  if car and self.ctx.vehicles and self.ctx.vehicles.get then def = self.ctx.vehicles.get(car.kind) end
  local allowed = def and def.tune
  local out = {}
  for _, s in ipairs(self.catalog.tune.slots) do
    local ok = not allowed
    if allowed then
      for _, a in ipairs(allowed) do if a == s.id then ok = true end end
    end
    if ok then out[#out + 1] = s end
  end
  return out
end

function Shops:buyTune(slotId)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  local slot
  for _, s in ipairs(self.catalog.tune.slots) do if s.id == slotId then slot = s end end
  if not slot then return false, "No such part." end
  local tier = (car.tune and car.tune[slotId] or 0) + 1
  if tier > #slot.prices then return false, "Already at the top tier." end
  local ok = wallet.spend(ctx, slot.prices[tier], "tune: " .. slot.label)
  if not ok then return false, "Not enough money." end
  car.tune = car.tune or {}
  car.tune[slotId] = tier
  local e = entryFor(ctx, car)
  if e then e.tune = e.tune or {} e.tune[slotId] = tier end
  if ctx.progress then ctx.progress.stats:max("tuneMax", tier) end
  self.section.goals.tune = true
  if tier >= #slot.prices then self.section.goals.tunemax = true end
  toast(ctx, slot.label .. " tier " .. tier, "orange", 3)
  return true
end

function Shops:outfit(id)
  for _, o in ipairs(self.catalog.clothes.outfits) do if o.id == id then return o end end
end

function Shops:wear(id)
  local o = self:outfit(id)
  if not o or not self.section.outfits[id] then return false, "You do not own that." end
  self.ctx.save.player.outfit = id
  self.ctx.player.outfit = { shirt = o.shirt, legs = o.legs }
  return true
end

function Shops:buyOutfit(id)
  local ctx = self.ctx
  local o = self:outfit(id)
  if not o then return false, "No such outfit." end
  if self.section.outfits[id] then return self:wear(id) end
  local ok = wallet.spend(ctx, o.price, "outfit: " .. o.name)
  if not ok then return false, "Not enough money." end
  self.section.outfits[id] = true
  if ctx.progress then ctx.progress.stats:add("outfits", 1) end
  self.section.goals.outfit = true
  self:wear(id)
  toast(ctx, o.name, "yellow", 3, "new outfit")
  return true
end

-- ---------------------------------------------------------------- property

local Prop = {}
Prop.__index = Prop

function M.property(ctx, layout, section)
  return setmetatable({ ctx = ctx, list = layout.properties or {}, section = section }, Prop)
end

function Prop:use(section) self.section = section end

function Prop:owned(id) return self.section.property[id] == true end

function Prop:counts()
  local n = 0
  for _, p in ipairs(self.list) do if self:owned(p.id) then n = n + 1 end end
  return n, #self.list
end

function Prop:slots()
  local n = 0
  for _, p in ipairs(self.list) do if self:owned(p.id) then n = n + (p.slots or 2) end end
  return n
end

function Prop:dailyIncome()
  local n = 0
  for _, p in ipairs(self.list) do if self:owned(p.id) then n = n + p.income end end
  return n
end

function Prop:buy(id)
  local p
  for _, q in ipairs(self.list) do if q.id == id then p = q end end
  if not p then return false, "No such property." end
  if self:owned(id) then return false, "You own it already." end
  local ok = wallet.spend(self.ctx, p.price, "property: " .. p.name)
  if not ok then return false, "Not enough money." end
  self.section.property[id] = true
  toast(self.ctx, p.name .. " is yours", "lime", 4, "+" .. require("sg.util").money(p.income) .. " a day")
  return true
end

--- Game time passes: every 24 hours the rent of everything owned is paid. Returns the money paid now.
function Prop:advance(hours)
  local rent = self.section.rent
  rent.hours = rent.hours + hours
  local paid = 0
  while rent.hours >= 24 do
    rent.hours = rent.hours - 24
    rent.days = rent.days + 1
    local day = self:dailyIncome()
    if day > 0 then
      wallet.add(self.ctx, day, "rent")
      paid = paid + day
      if self.ctx.progress then self.ctx.progress.stats:add("rentEarned", day) end
    end
  end
  if paid > 0 then toast(self.ctx, "Rent day  +" .. require("sg.util").money(paid), "lime", 4) end
  return paid
end

-- ---------------------------------------------------------------- the garage

local Garage = {}
Garage.__index = Garage

function M.garage(ctx, catalog, prop, section)
  return setmetatable({ ctx = ctx, catalog = catalog, prop = prop, section = section }, Garage)
end

function Garage:use(section) self.section = section end

function Garage:cars()
  local g = self.ctx.save.garage
  g.cars = g.cars or {}
  return g.cars
end

function Garage:capacity()
  return (self.catalog.garage and self.catalog.garage.base or 3) + self.prop:slots()
end

function Garage:count() return #self:cars() end

local nextId = 0

--- Put the car you are driving in the garage: it leaves the street, you stand at the door.
function Garage:store(place)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  if car.spec and car.spec.police then return false, "That one belongs to the Patrol." end
  if self:count() >= self:capacity() then return false, "The garage is full (" .. self:capacity() .. " cars)." end
  nextId = nextId + 1
  local list = self:cars()
  local entry = { id = car.garageId or ("g" .. os.time() .. "_" .. nextId), kind = car.kind, colour = car.colour, tune = car.tune or {} }
  list[#list + 1] = entry
  for i = #ctx.cars, 1, -1 do
    if ctx.cars[i] == car then table.remove(ctx.cars, i) end
  end
  local p = ctx.player
  p.car = nil
  p.x, p.z = place.x, place.z
  p.v = 0
  self.section.goals.storecar = true
  toast(ctx, car.spec and car.spec.name or "Car", "cyan", 3, "stored")
  return true
end

--- Bring out the i-th stored car and get in it.
function Garage:takeOut(i, place)
  local ctx = self.ctx
  local list = self:cars()
  local e = list[i]
  if not e then return false, "Nothing there." end
  local h = place.h or 0
  local x, z = place.x + math.cos(h) * 4, place.z + math.sin(h) * 4
  local car
  if ctx.spawnVehicle then
    car = ctx.spawnVehicle(e.kind, x, z, h, e.colour)
  else
    car = vehicleLib.new(e.kind, x, z, h, e.colour)
    ctx.cars[#ctx.cars + 1] = car
  end
  if not car then return false, "That car is not available." end
  if ctx.stream then car.y = ctx.stream:groundAt(x, z, nil) end
  car.tune = e.tune
  car.garageId = e.id
  table.remove(list, i)
  ctx.player.car = car
  car.follow = nil
  ctx.player.x, ctx.player.z, ctx.player.y = x, z, car.y
  return true
end

return M
