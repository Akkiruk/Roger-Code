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

--- Stream B's customization (paint, stripes, tune tiers and their prices), when its plugin is loaded.
local function custom(ctx)
  if not ctx.fleet then return nil end
  local ok, c = pcall(require, "sg.vehicles.custom")
  if ok and c.data then return c end
  return nil
end
M.custom = custom

local SLOT_LABELS = { engine = "Engine", brakes = "Brakes", grip = "Tyres", armour = "Armour" }

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

--- The paint colours on sale, and what a coat costs for the car you are in.
function Shops:paints()
  local cu = custom(self.ctx)
  local car = self.ctx.player.car
  if cu and car then return cu.data.paints, cu.paintPrice(car.spec.base or car.spec) end
  return self.catalog.respray.colours, self.catalog.respray.price
end

--- The stripes on sale (stream B's data only) and their price.
function Shops:stripes()
  local cu = custom(self.ctx)
  local car = self.ctx.player.car
  if cu and car then return cu.data.stripes, cu.stripePrice(car.spec.base or car.spec) end
  return nil
end

function Shops:currentPaint()
  local car = self.ctx.player.car
  if not car then return nil end
  if car.paint then return car.paint.body, car.paint.stripe end
  return car.colour, nil
end

function Shops:respray(colour)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  local body = self:currentPaint()
  if body == colour then return false, "It is already that colour." end
  local _, price = self:paints()
  local ok = wallet.spend(ctx, price, "respray")
  if not ok then return false, "Not enough money." end
  local cu = custom(ctx)
  if cu then
    local _, stripe = self:currentPaint()
    cu.apply(car, { paint = { body = colour, stripe = stripe } })
  else
    car.colour = colour
    if type(car.paint) == "table" then car.paint.body = colour end
  end
  local e = entryFor(ctx, car)
  if e then e.colour = colour end
  if ctx.progress then ctx.progress.stats:add("resprays", 1) end
  self.section.goals.respray = true
  toast(ctx, "Fresh paint", "magenta", 3, colour)
  return true
end

function Shops:stripe(name)
  local ctx = self.ctx
  local car = ctx.player.car
  local cu = custom(ctx)
  if not car then return false, "Drive a car in first." end
  if not cu then return false, "No stripes on sale." end
  local body, current = self:currentPaint()
  if (current or "none") == name then return false, "It has that stripe already." end
  local _, price = self:stripes()
  local ok = wallet.spend(ctx, price, "stripe")
  if not ok then return false, "Not enough money." end
  cu.apply(car, { paint = { body = body, stripe = name ~= "none" and name or nil } })
  if ctx.progress then ctx.progress.stats:add("resprays", 1) end
  self.section.goals.respray = true
  toast(ctx, "Stripe: " .. name, "magenta", 3)
  return true
end

function Shops:tierOf(slot)
  local car = self.ctx.player.car
  return car and car.tune and car.tune[slot] or 0
end

--- The tune slots for the car you are in: { id, label } in order.
function Shops:slots()
  local cu = custom(self.ctx)
  local out = {}
  if cu then
    for _, id in ipairs(cu.SLOTS) do out[#out + 1] = { id = id, label = SLOT_LABELS[id] or id } end
    return out
  end
  local def
  local car = self.ctx.player.car
  if car and self.ctx.vehicles and self.ctx.vehicles.get then def = self.ctx.vehicles.get(car.kind) end
  local allowed = def and def.tune
  for _, s in ipairs(self.catalog.tune.slots) do
    local ok = not allowed
    if allowed then
      for _, a in ipairs(allowed) do if a == s.id then ok = true end end
    end
    if ok then out[#out + 1] = { id = s.id, label = s.label } end
  end
  return out
end

--- Where a slot stands for the car you are in: tier, the top tier, the next tier's name and its price (nil at the top).
function Shops:tuneInfo(slotId)
  local car = self.ctx.player.car
  local tier = self:tierOf(slotId)
  local cu = custom(self.ctx)
  if cu then
    local s = cu.data.slots[slotId]
    local max = s and #s.price or 3
    if tier >= max then return tier, max end
    local def = car and (car.spec.base or car.spec)
    return tier, max, s.names and s.names[tier + 1], def and cu.price(def, slotId, tier + 1)
  end
  for _, s in ipairs(self.catalog.tune.slots) do
    if s.id == slotId then
      if tier >= #s.prices then return tier, #s.prices end
      return tier, #s.prices, nil, s.prices[tier + 1]
    end
  end
  return tier, 0
end

function Shops:buyTune(slotId)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  local known = false
  for _, s in ipairs(self:slots()) do if s.id == slotId then known = true end end
  if not known then return false, "No such part." end
  local tier, max, _, price = self:tuneInfo(slotId)
  if tier >= max or not price then return false, "Already at the top tier." end
  local ok = wallet.spend(ctx, price, "tune: " .. slotId)
  if not ok then return false, "Not enough money." end
  local cu = custom(ctx)
  tier = tier + 1
  if cu then
    local tune = {}
    for _, id in ipairs(cu.SLOTS) do tune[id] = (car.tune and car.tune[id]) or 0 end
    tune[slotId] = tier
    cu.apply(car, { tune = tune })
  else
    car.tune = car.tune or {}
    car.tune[slotId] = tier
  end
  local e = entryFor(ctx, car)
  if e then e.tune = e.tune or {} e.tune[slotId] = tier end
  if ctx.progress then ctx.progress.stats:max("tuneMax", tier) end
  self.section.goals.tune = true
  if tier >= max then self.section.goals.tunemax = true end
  toast(ctx, (SLOT_LABELS[slotId] or slotId) .. " tier " .. tier, "orange", 3)
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

--- What a stored car looks like in the list: its name and paint.
function M.describe(ctx, e)
  local def = ctx.vehicles and ctx.vehicles.get(e.kind)
  local colour = (e.paint and e.paint.body) or e.colour or "white"
  return def and def.name or e.kind, colour
end

--- Put the car you are driving in the garage: it leaves the street, you stand at the door.
function Garage:store(place)
  local ctx = self.ctx
  local car = ctx.player.car
  if not car then return false, "Drive a car in first." end
  if car.spec and car.spec.police then return false, "That one belongs to the Patrol." end
  if self:count() >= self:capacity() then return false, "The garage is full (" .. self:capacity() .. " cars)." end
  nextId = nextId + 1
  local list = self:cars()
  local entry
  if ctx.fleet then
    entry = ctx.fleet:snapshot(car)
  else
    entry = { kind = car.kind, colour = car.colour, tune = car.tune or {} }
  end
  entry.id = car.garageId or ("g" .. os.time() .. "_" .. nextId)
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
  if ctx.fleet and e.paint then
    car = ctx.fleet:build(e, x, z, h)
  elseif ctx.spawnVehicle then
    car = ctx.spawnVehicle(e.kind, x, z, h, e.colour)
  else
    car = vehicleLib.new(e.kind, x, z, h, e.colour)
  end
  if not car then return false, "That car is not available." end
  ctx.cars[#ctx.cars + 1] = car
  if ctx.stream then car.y = ctx.stream:groundAt(x, z, nil) end
  if e.tune and not car.tune then car.tune = e.tune end
  car.garageId = e.id
  table.remove(list, i)
  ctx.player.car = car
  car.follow = nil
  ctx.player.x, ctx.player.z, ctx.player.y = x, z, car.y
  return true
end

return M
