-- vehicles/custom.lua
-- Garage-ready customization: paint, stripes and tune tiers as plain data, what they cost, and the car's numbers
-- under a tune. The shops and the garage screen (stream E) call this; it keeps no state of its own. Pure.
--
-- A car's customization is { paint = { body = "red", stripe = "white" | nil }, tune = { engine = 0..3, brakes, grip,
-- armour } }. The model builder reads the car's colour string, which is composed here:
--   "body" | "body:stripe", then "|stage" for damage (0 clean .. 3 on fire), e.g. "red:white|2".
--
--   custom.compose(paint, stage) -> colour string      custom.parse(colour) -> body, stripe, stage
--   custom.table -> the data from content/vehicles/tune.lua (set with custom.setData)
--   custom.tuned(def, tune) -> a spec with the tune applied (cached per tune)
--   custom.price(def, slot, tier) -> money for that tier      custom.paintPrice(def)  custom.stripePrice(def)
--   custom.apply(car, { paint =, tune = })      custom.snapshot(car) -> data for the garage save

local M = {}

M.SLOTS = { "engine", "brakes", "grip", "armour" }
M.data = nil

function M.setData(data) M.data = data end

--- Paint and damage stage as the colour string the model cache keys on.
function M.compose(paint, stage)
  paint = paint or {}
  local s = paint.body or "red"
  if paint.stripe and paint.stripe ~= "none" then s = s .. ":" .. paint.stripe end
  if stage and stage > 0 then s = s .. "|" .. stage end
  return s
end

--- body, stripe (or nil), stage (a number) from a colour string.
function M.parse(colour)
  colour = colour or "red"
  local base, stage = colour:match("^([^|]*)|(%d+)$")
  if not base then base, stage = colour, "0" end
  local body, stripe = base:match("^([^:]*):(.*)$")
  if not body then body = base end
  if stripe == "" then stripe = nil end
  return body, stripe, tonumber(stage)
end

local function clampTier(t)
  t = math.floor(tonumber(t) or 0)
  if t < 0 then return 0 end
  if t > 3 then return 3 end
  return t
end

--- A key for a tune, the same for the same tiers.
function M.tuneKey(tune)
  tune = tune or {}
  local parts = {}
  for _, slot in ipairs(M.SLOTS) do parts[#parts + 1] = clampTier(tune[slot]) end
  return table.concat(parts)
end

local cache = {}

--- The def's numbers under a tune: engine raises top speed and acceleration, brakes the braking, grip the grip and
-- turn, armour the health (and weight). Returns def itself for no tune at all.
function M.tuned(def, tune)
  local key = M.tuneKey(tune)
  if key == "0000" or not M.data then return def end
  local ck = (def.id or def.name) .. ":" .. key
  local hit = cache[ck]
  if hit then return hit end
  local spec = {}
  for k, v in pairs(def) do spec[k] = v end
  spec.base = def
  for i, slot in ipairs(M.SLOTS) do
    local tier = tonumber(key:sub(i, i))
    local s = M.data.slots[slot]
    if tier > 0 and s then
      for stat, list in pairs(s) do
        if type(list) == "table" and stat ~= "names" and stat ~= "price" and spec[stat] then
          spec[stat] = spec[stat] * (list[tier] or 1)
        end
      end
    end
  end
  cache[ck] = spec
  return spec
end

--- The value a vehicle's work is priced from: its own, but never under the data's priceFloor (a $160 car would
-- otherwise get a $6 respray, next to jobs paying hundreds).
local function priceBase(def)
  return math.max(def.value or 0, M.data and M.data.priceFloor or 0)
end
M.priceBase = priceBase

--- What tier (1-3) of a slot costs for this vehicle.
function M.price(def, slot, tier)
  local s = M.data and M.data.slots[slot]
  if not s or not s.price[tier] then return nil end
  return math.floor(priceBase(def) * s.price[tier] + 0.5)
end

function M.paintPrice(def) return math.floor(priceBase(def) * (M.data and M.data.paintPrice or 0.04) + 0.5) end
function M.stripePrice(def) return math.floor(priceBase(def) * (M.data and M.data.stripePrice or 0.02) + 0.5) end

--- Is this a colour the paint shop sells?
function M.validPaint(name)
  if not M.data then return false end
  for _, c in ipairs(M.data.paints) do
    if c == name then return true end
  end
  return false
end

--- Set a car's paint and tune (either may be left out). Damage stays; a tuned car keeps its health fraction.
function M.apply(car, c)
  c = c or {}
  local def = car.spec.base or car.spec
  if c.paint then
    car.paint = { body = c.paint.body or (car.paint and car.paint.body) or def.body, stripe = c.paint.stripe }
  end
  if c.tune then
    local frac = car.health / math.max(1, car.spec.health)
    car.tune = {}
    for _, slot in ipairs(M.SLOTS) do car.tune[slot] = clampTier(c.tune[slot]) end
    car.spec = M.tuned(def, car.tune)
    car.health = math.min(car.spec.health, frac * car.spec.health)
  end
  car.colour = M.compose(car.paint or { body = def.body }, car.stage or 0)
  return car
end

--- The data the garage keeps for a car: enough to build it again.
function M.snapshot(car)
  local def = car.spec.base or car.spec
  local tune = {}
  for _, slot in ipairs(M.SLOTS) do tune[slot] = clampTier(car.tune and car.tune[slot]) end
  return {
    kind = car.kind,
    paint = { body = (car.paint and car.paint.body) or def.body, stripe = car.paint and car.paint.stripe },
    tune = tune,
    health = math.floor(car.health / math.max(1, car.spec.health) * 1000 + 0.5) / 1000,
  }
end

return M
