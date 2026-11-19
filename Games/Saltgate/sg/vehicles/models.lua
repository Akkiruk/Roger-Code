-- vehicles/models.lua
-- The shapes of every vehicle: cars in a dozen bodies, bikes with riders, trucks and trailers, boats, the police
-- helicopter, each in four states of damage (0 clean, 1 dented, 2 smoking and crumpled, 3 on fire) and wrecked.
-- A model is a list of Pine3D triangles built from boxes (sg/models.lua box), facing +x with z to the right.
--
--   vmodels.build(spec, colour, wrecked) -> model     colour is "body[:stripe][|stage]" (see vehicles/custom.lua)
--   vmodels.install()    route sg/models.lua's car() here for every vehicle that is not an untouched legacy car
--   vmodels.uninstall()
--   vmodels.SHAPES       the body shapes, for tests

local base = require("sg.models")
local custom = require("sg.vehicles.custom")

local M = {}

local C = rawget(_G, "colors") or rawget(_G, "colours") or {}
local box = base.box

--- A box with a single colour (cx for the ends, cz for the sides when given).
local function B(list, x0, y0, z0, x1, y1, z1, c, cx, cz, o)
  box(list, x0, y0, z0, x1, y1, z1, c, cx or c, cz or cx or c, o)
end

local DARKER = { white = "lightGray", lightGray = "gray", yellow = "orange", orange = "brown", red = "brown", lime = "green",
  -- shades never land on the sky's slots (purple, magenta, pink, lightBlue change with the hour)
  green = "gray", cyan = "blue", lightBlue = "blue", blue = "black", purple = "gray", magenta = "red", pink = "red",
  brown = "black", gray = "black", black = "black" }

local function col(name) return C[name] or C.red end
local function darker(name) return col(DARKER[name] or "gray") end

-- ---------------------------------------------------------------- cars

-- lo: where the body's top is, roof: the cabin's top (nil: open), c0 and c1: where the cabin runs, as fractions of the
-- length from the middle (-0.5 tail .. 0.5 nose), wheel: wheel height, ride: how high the body sits, and the extras.
M.SHAPES = {
  sedan = { lo = 1.05, roof = 1.65, c0 = -0.275, c1 = 0.125 },
  hatch = { lo = 1.0, roof = 1.6, c0 = -0.45, c1 = 0.1, spoiler = 1 },
  muscle = { lo = 0.95, roof = 1.5, c0 = -0.3, c1 = -0.02, scoop = 1, stripe = 1 },
  wagon = { lo = 1.05, roof = 1.7, c0 = -0.46, c1 = 0.14, rack = 1 },
  suv = { lo = 1.35, roof = 2.05, c0 = -0.42, c1 = 0.18, wheel = 0.95, ride = 0.5, rack = 1, bullbar = 1 },
  buggy = { lo = 0.85, roof = nil, c0 = -0.1, c1 = 0.1, wheel = 1.0, ride = 0.45, cage = 1 },
  limo = { lo = 1.05, roof = 1.6, c0 = -0.4, c1 = 0.1, stripe = 1 },
  micro = { lo = 1.0, roof = 1.9, c0 = -0.4, c1 = 0.38 },
  roadster = { lo = 0.95, roof = nil, c0 = -0.12, c1 = 0.05, stripe = 1 },
  wedge = { lo = 0.7, roof = 1.15, c0 = -0.12, c1 = 0.3, spoiler = 2, stripe = 1 },
  pickup = { lo = 1.2, roof = 1.95, c0 = -0.08, c1 = 0.24, wheel = 0.85, ride = 0.45, bed = 1 },
  rally = { lo = 1.0, roof = 1.55, c0 = -0.42, c1 = 0.12, spoiler = 1, scoop = 1, stripe = 1 },
  ambulance = { lo = 2.3, roof = nil, van = true, stripe = 1, lightbar = 1 },
  banger = { lo = 1.05, roof = 1.65, c0 = -0.275, c1 = 0.125, mismatch = 1 },
  van = { lo = 2.2, roof = nil, van = true },
  lowsedan = { lo = 0.95, roof = 1.4, c0 = -0.275, c1 = 0.125 },
}

local function wheels(list, sh, L, W, stage, dark)
  local hl, hw = L / 2, W / 2
  local r = (sh.wheel or 0.62) / 2
  local ride = sh.ride or 0.35
  for _, ax in ipairs({ hl * 0.55, -hl * 0.6 }) do
    for _, side in ipairs({ -1, 1 }) do
      if not (stage >= 3 and ax > 0 and side < 0) then -- a front wheel is gone when it burns
        local z0, z1 = side * (hw - 0.2), side * (hw + 0.07)
        B(list, ax - r - 0.05, 0, math.min(z0, z1), ax + r + 0.05, r * 2 + 0.02, math.max(z0, z1), dark, dark, dark, { noTop = true })
      end
    end
  end
  B(list, -hl * 0.6, 0.1, -hw + 0.3, hl * 0.55, ride, hw - 0.3, dark, dark, dark, { noTop = true }) -- the underside
end

local function flames(list, x, y, z, big)
  B(list, x - 0.6, y, z - 0.5, x + 0.4, y + (big and 0.9 or 0.7), z + 0.5, C.orange, C.orange, C.red)
  B(list, x - 0.3, y + 0.7, z - 0.25, x + 0.2, y + (big and 1.7 or 1.4), z + 0.25, C.yellow, C.yellow, C.orange)
end

local function carModel(spec, bodyName, stripeName, stage, wrecked)
  local list = {}
  local sh = M.SHAPES[spec.shape] or (spec.van and M.SHAPES.van) or (spec.low and M.SHAPES.lowsedan) or M.SHAPES.sedan
  local L, W = spec.length, spec.width
  local hl, hw = L / 2, W / 2
  local ride = sh.ride or 0.35
  local lo = sh.lo
  local body = wrecked and C.gray or col(bodyName)
  local glassName = spec.cabin or "black"
  local glass = wrecked and C.black or (stage >= 2 and C.lightGray or col(glassName))
  local dark = C.black
  local stripe = stripeName and col(stripeName) or nil
  wheels(list, sh, L, W, wrecked and 3 or stage, dark)

  -- the lower body; the nose crumples as it is hurt
  local crumple = wrecked and 0.3 or (stage >= 3 and 0.26 or (stage >= 2 and 0.18 or (stage >= 1 and 0.07 or 0)))
  local frontX = hl * (1 - 2 * crumple)
  B(list, -hl, ride, -hw, frontX, lo, hw, body, body, body)
  if crumple > 0 then
    local drop = stage >= 2 and 0.35 or 0.12
    local nose = darker(bodyName)
    if wrecked then nose = C.black end
    B(list, frontX, ride + drop * 0.5, -hw * 0.95, hl, lo - drop, hw * 0.95, nose, nose, nose)
  end
  -- the cabin
  local c0, c1 = (sh.c0 or -0.28) * L, (sh.c1 or 0.12) * L
  if sh.van then
    -- a van: the tall body up to the nose, a windscreen band at the front
    B(list, -hl, lo - 0.01, -hw, frontX, lo, hw, body, body, body, { noTop = true })
    B(list, hl * 0.45, 1.25, -hw - 0.04, math.min(hl + 0.04, frontX + 0.04), 1.95, hw + 0.04, glass, glass, glass, { noTop = true })
  elseif sh.roof then
    local inset = 0.82
    B(list, c0, lo, -hw * inset, c1, sh.roof, hw * inset, body, glass, glass)
  else
    -- open top: seats, a low windscreen
    B(list, c0, lo, -hw * 0.7, c0 + 0.5, lo + 0.55, hw * 0.7, dark, dark, dark)
    B(list, c1 - 0.15, lo, -hw * 0.8, c1, lo + 0.45, hw * 0.8, glass, glass, glass)
    if sh.cage then
      for _, z in ipairs({ -hw * 0.8, hw * 0.8 }) do
        B(list, c0 - 0.05, lo, z - 0.05, c0 + 0.05, lo + 1.15, z + 0.05, dark)
        B(list, c1 - 0.05, lo, z - 0.05, c1 + 0.05, lo + 1.15, z + 0.05, dark)
      end
      B(list, c0 - 0.05, lo + 1.1, -hw * 0.8, c1 + 0.05, lo + 1.2, hw * 0.8, dark)
    end
  end
  -- extras
  if sh.spoiler then
    local h = sh.spoiler == 2 and 0.55 or 0.3
    B(list, -hl - 0.2, lo + h, -hw * 0.85, -hl + 0.45, lo + h + 0.07, hw * 0.85, dark, dark, dark)
    B(list, -hl + 0.1, lo, -hw * 0.6, -hl + 0.2, lo + h, -hw * 0.5, dark)
    B(list, -hl + 0.1, lo, hw * 0.5, -hl + 0.2, lo + h, hw * 0.6, dark)
  end
  if sh.scoop and sh.roof then B(list, c0 + 0.4, sh.roof, -0.35, c0 + 1.0, sh.roof + 0.25, 0.35, dark, dark, dark) end
  if sh.scoop and not sh.roof then B(list, c1 + 0.3, lo, -0.4, c1 + 1.1, lo + 0.2, 0.4, dark) end
  if sh.rack and sh.roof then
    B(list, c0 + 0.2, sh.roof, -hw * 0.7, c1 - 0.2, sh.roof + 0.12, hw * 0.7, dark, dark, dark)
  end
  if sh.bullbar then B(list, hl - 0.05, 0.5, -hw * 0.8, hl + 0.25, 1.1, hw * 0.8, dark, dark, dark) end
  if sh.bed then B(list, -hl, lo, -hw, c0 - 0.1, lo + 0.45, hw, C.gray, body, body) end
  if sh.lightbar and not wrecked then
    B(list, c1 - 0.6, lo + 0.0, -hw * 0.7, c1 - 0.1, lo + 0.25, 0, C.red, C.red, C.red)
    B(list, c1 - 0.6, lo + 0.0, 0, c1 - 0.1, lo + 0.25, hw * 0.7, C.blue, C.blue, C.blue)
  end
  if spec.police and not wrecked and not sh.lightbar then
    local roof = sh.roof or lo
    B(list, -0.5, roof, -hw * 0.6, 0.3, roof + 0.3, 0, C.red)
    B(list, -0.5, roof, 0, 0.3, roof + 0.3, hw * 0.6, C.blue)
  elseif spec.sign and not wrecked then
    local roof = sh.roof or lo
    B(list, -0.6, roof, -0.4, 0, roof + 0.35, 0.4, C.yellow, C.black, C.yellow)
  end
  if sh.mismatch and not wrecked then
    -- an old banger: one door in another colour, rust
    B(list, -0.4, ride + 0.1, hw, 0.7, lo - 0.05, hw + 0.03, C.lightGray, C.lightGray, C.lightGray, { noTop = true })
    B(list, -hl, ride, hw - 0.1, -hl + 0.7, ride + 0.4, hw + 0.03, C.brown, C.brown, C.brown, { noTop = true })
  end
  -- paint stripe
  if stripe and not wrecked then
    if sh.van then
      B(list, -hl + 0.2, 0.9, -hw - 0.03, frontX - 0.2, 1.2, hw + 0.03, stripe, stripe, stripe, { noTop = true })
    else
      local roof = sh.roof
      B(list, -hl, lo, -0.28, c0, lo + 0.03, 0.28, stripe, stripe, stripe)
      B(list, c1, lo, -0.28, frontX, lo + 0.03, 0.28, stripe, stripe, stripe)
      if roof then B(list, c0, roof, -0.28, c1, roof + 0.03, 0.28, stripe, stripe, stripe) end
    end
  end
  -- lights
  if not wrecked then
    local broken = stage >= 1
    B(list, hl - 0.02, 0.6, -hw * 0.8, hl + 0.06, 0.85, -hw * 0.45, broken and C.black or C.yellow)
    B(list, hl - 0.02, 0.6, hw * 0.45, hl + 0.06, 0.85, hw * 0.8, C.yellow)
    B(list, -hl - 0.06, 0.6, -hw * 0.8, -hl, 0.85, -hw * 0.5, C.red)
    B(list, -hl - 0.06, 0.6, hw * 0.5, -hl, 0.85, hw * 0.8, C.red)
  end
  -- damage
  if stage >= 1 or wrecked then
    local scorch = C.gray
    B(list, -0.2, lo - 0.35, hw, 0.9, lo - 0.05, hw + 0.04, scorch, scorch, scorch, { noTop = true }) -- a dented door
    if stage >= 2 or wrecked then
      B(list, -0.9, lo - 0.5, -hw - 0.04, 0.1, lo - 0.1, -hw, C.black, C.black, C.black, { noTop = true })
      B(list, hl * 0.2, lo + 0.02, -hw * 0.7, hl * 0.6, lo + 0.3, hw * 0.7, darker(bodyName), C.black, C.black) -- the hood sprung up
    end
  end
  if stage >= 3 and not wrecked then flames(list, hl * 0.4, lo + 0.3, 0, false) end
  return list
end

-- ---------------------------------------------------------------- bikes

local BIKES = {
  scooter = { wheel = 0.55, tank = false, shield = true, low = true },
  sport = { wheel = 0.7, tank = true, fairing = true, tuck = true },
  cruiser = { wheel = 0.75, tank = true, bars = 0.5, chrome = true },
  dirt = { wheel = 0.85, tank = true, fender = true, tall = true },
}

local function bikeModel(spec, bodyName, stripeName, stage, wrecked)
  local list = {}
  local sh = BIKES[spec.shape] or BIKES.sport
  local L = spec.length
  local hl = L / 2
  local body = wrecked and C.gray or col(bodyName)
  local dark, chrome = C.black, C.lightGray
  local r = sh.wheel / 2
  local wx = hl * 0.72
  -- wheels (a narrow dark block each)
  B(list, wx - r, 0, -0.1, wx + r, sh.wheel, 0.1, dark, dark, dark, { noTop = true })
  B(list, -wx - r, 0, -0.1, -wx + r, sh.wheel, 0.1, dark, dark, dark, { noTop = true })
  -- frame, engine
  local base0 = sh.low and 0.3 or 0.45
  B(list, -wx * 0.7, base0, -0.17, wx * 0.5, base0 + 0.45, 0.17, dark, dark, dark)
  -- fork, bars and headlight
  local forkTilt = stage >= 2 and -0.15 or 0
  B(list, wx - 0.08 + forkTilt, sh.wheel * 0.5, -0.05, wx + 0.08 + forkTilt, 1.15, 0.05, chrome, chrome, chrome)
  B(list, wx - 0.1, 1.1, -(sh.bars or 0.38), wx + 0.05, 1.2, sh.bars or 0.38, dark, dark, dark)
  if sh.shield then B(list, wx - 0.3, 0.45, -0.3, wx - 0.2, 1.3, 0.3, body, body, body) end
  if sh.fairing then B(list, wx - 0.5, 0.6, -0.25, wx + 0.2, 1.15, 0.25, body, body, body) end
  if not wrecked then B(list, wx + 0.05, 0.85, -0.12, wx + 0.14, 1.05, 0.12, stage >= 1 and C.lightGray or C.yellow) end
  if sh.tank then B(list, -0.1, base0 + 0.45, -0.2, wx * 0.45, base0 + 0.8, 0.2, body, body, body) end
  if sh.fender then B(list, -wx - 0.4, 0.8, -0.1, -wx + 0.2, 0.95, 0.1, body, body, body) end
  -- seat and tail
  B(list, -wx * 0.7, base0 + 0.45, -0.2, -0.1, base0 + 0.62, 0.2, dark, dark, dark)
  if not wrecked then B(list, -wx - 0.15, 0.7, -0.1, -wx - 0.08, 0.85, 0.1, C.red) end
  -- exhaust, stripe
  B(list, -wx * 0.7, 0.3, 0.18, wx * 0.2, 0.42, 0.28, chrome, chrome, chrome)
  if stripeName and not wrecked then
    local s = col(stripeName)
    B(list, -0.1, base0 + 0.8, -0.04, wx * 0.45, base0 + 0.83, 0.04, s, s, s)
  end
  -- the rider (in the player's orange; the model has to show who is on it)
  local shirt = C.orange
  local lean = sh.tuck and 0.35 or 0.1
  B(list, -0.45 + lean, base0 + 0.62, -0.28, -0.05 + lean, base0 + 0.95 + (sh.tall and 0.25 or 0.1), 0.28, shirt, shirt, shirt)
  B(list, -0.45 + lean + 0.1, base0 + 1.0, -0.2, -0.05 + lean + 0.1, base0 + 1.5, 0.2, shirt, shirt, shirt)
  B(list, -0.38 + lean + 0.1, base0 + 1.5, -0.16, -0.12 + lean + 0.1, base0 + 1.8, 0.16, dark, C.pink, C.pink)
  B(list, 0.0 + lean, base0 + 0.9, -0.34, wx - 0.1, base0 + 1.0, -0.26, shirt, shirt, shirt) -- arms to the bars
  B(list, 0.0 + lean, base0 + 0.9, 0.26, wx - 0.1, base0 + 1.0, 0.34, shirt, shirt, shirt)
  if stage >= 3 and not wrecked then flames(list, 0.2, 0.9, 0, false) end
  return list
end

-- ---------------------------------------------------------------- trucks and trailers

local function stackLights(list, hl, y)
  B(list, hl, y, -0.9, hl + 0.06, y + 0.2, -0.5, C.yellow)
  B(list, hl, y, 0.5, hl + 0.06, y + 0.2, 0.9, C.yellow)
end

local function truckModel(spec, bodyName, stripeName, stage, wrecked)
  local list = {}
  local L, W = spec.length, spec.width
  local hl, hw = L / 2, W / 2
  local body = wrecked and C.gray or col(bodyName)
  local glass = wrecked and C.black or (stage >= 2 and C.lightGray or C.black)
  local dark = C.black
  local stripe = stripeName and not wrecked and col(stripeName) or nil
  local nose = hl * (1 - (wrecked and 0.45 or (stage >= 2 and 0.3 or (stage >= 1 and 0.1 or 0))) * 2)
  local function wheelSet(x)
    for _, side in ipairs({ -1, 1 }) do
      local z0, z1 = side * (hw - 0.35), side * (hw + 0.1)
      B(list, x - 0.55, 0, math.min(z0, z1), x + 0.55, 1.1, math.max(z0, z1), dark, dark, dark, { noTop = true })
    end
  end
  if spec.shape == "boxtruck" then
    wheelSet(hl * 0.62) wheelSet(-hl * 0.55) wheelSet(-hl * 0.2)
    B(list, -hl, 0.5, -hw * 0.9, hl, 1.0, hw * 0.9, dark, dark, dark, { noTop = true })
    -- the cargo box and the little cab
    B(list, -hl, 1.0, -hw, hl * 0.3, spec.height, hw, body, body, body)
    B(list, hl * 0.3, 1.0, -hw * 0.95, nose, 2.5, hw * 0.95, body, body, body)
    B(list, hl * 0.52, 1.5, -hw * 0.97, math.min(nose + 0.02, hl + 0.02), 2.3, hw * 0.97, glass, glass, glass, { noTop = true })
    if stripe then B(list, -hl + 0.1, 1.7, -hw - 0.03, hl * 0.3, 2.1, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
    B(list, -hl - 0.05, 1.2, -hw * 0.8, -hl, 2.6, hw * 0.8, C.lightGray, C.lightGray, C.lightGray) -- the rear door
  else
    -- a tractor: long nose, sleeper cab, stacks, the fifth wheel plate
    wheelSet(hl * 0.62) wheelSet(-hl * 0.45) wheelSet(-hl * 0.8)
    B(list, -hl, 0.6, -hw * 0.9, nose, 1.4, hw * 0.9, body, body, body)
    B(list, -hl * 0.2, 1.4, -hw * 0.95, hl * 0.5, spec.height - 0.2, hw * 0.95, body, glass, glass) -- the cab
    B(list, nose * 0.5, 1.4, -hw * 0.8, nose, 2.2, hw * 0.8, body, body, body) -- the hood
    B(list, -hl, 1.4, -hw * 0.6, -hl * 0.3, 1.6, hw * 0.6, C.gray, C.gray, C.gray) -- the plate
    B(list, -hl * 0.05, spec.height - 0.2, -hw * 0.9, hl * 0.3, spec.height, hw * 0.9, body, body, body)
    B(list, -hl * 0.45, 1.6, -hw - 0.1, -hl * 0.35, 3.5, -hw + 0.05, C.lightGray, C.lightGray, C.lightGray) -- stacks
    B(list, -hl * 0.45, 1.6, hw - 0.05, -hl * 0.35, 3.5, hw + 0.1, C.lightGray, C.lightGray, C.lightGray)
    B(list, hl - 0.05, 0.55, -hw * 0.85, hl + 0.2, 1.1, hw * 0.85, dark, dark, dark)
    if stripe then B(list, -hl * 0.2, 2.1, -hw - 0.03, hl * 0.5, 2.4, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
  end
  if not wrecked then stackLights(list, nose, 0.7) end
  if stage >= 1 or wrecked then
    B(list, -0.5, 1.0, hw, 1.0, 1.7, hw + 0.04, C.gray, C.gray, C.gray, { noTop = true })
  end
  if stage >= 3 and not wrecked then flames(list, nose * 0.6, 2.0, 0, true) end
  return list
end

local function trailerModel(spec, bodyName, stripeName, stage, wrecked)
  local list = {}
  local L, W = spec.length, spec.width
  local hl, hw = L / 2, W / 2
  local body = wrecked and C.gray or col(bodyName)
  local dark = C.black
  local stripe = stripeName and not wrecked and col(stripeName) or nil
  for _, x in ipairs({ -hl * 0.7, -hl * 0.45 }) do
    for _, side in ipairs({ -1, 1 }) do
      local z0, z1 = side * (hw - 0.35), side * (hw + 0.1)
      B(list, x - 0.55, 0, math.min(z0, z1), x + 0.55, 1.1, math.max(z0, z1), dark, dark, dark, { noTop = true })
    end
  end
  B(list, hl - 1.5, 0.5, -0.12, hl - 1.3, 1.0, 0.12, C.gray, C.gray, C.gray) -- landing gear
  B(list, -hl, 0.9, -hw * 0.9, hl, 1.2, hw * 0.9, dark, dark, dark)
  if spec.shape == "flatbed" then
    B(list, -hl, 1.2, -hw, hl, 1.45, hw, body, C.gray, body)
    local crates = { { -hl * 0.55, "red" }, { hl * 0.05, "blue" }, { hl * 0.55, "green" } }
    for _, cr in ipairs(crates) do
      local c = col(cr[2])
      B(list, cr[1] - 1.3, 1.45, -hw * 0.8, cr[1] + 1.3, 3.0, hw * 0.8, c, c, darker(cr[2]) and c)
    end
  elseif spec.shape == "tanker" then
    B(list, -hl, 1.2, -hw * 0.65, hl, 3.0, hw * 0.65, body, body, body)
    B(list, -hl, 1.5, -hw, hl, 2.7, hw, body, body, body, { noTop = true })
    B(list, -hl, 2.7, -hw * 0.8, hl, 3.1, hw * 0.8, body, body, body)
    if stripe then B(list, -hl * 0.1, 1.5, -hw - 0.03, hl * 0.1, 2.7, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
    B(list, -hl * 0.3, 3.1, -0.25, -hl * 0.3 + 0.6, 3.3, 0.25, C.lightGray, C.lightGray, C.lightGray)
  else
    B(list, -hl, 1.2, -hw, hl, spec.height, hw, body, body, body)
    if stripe then B(list, -hl + 0.2, 2.0, -hw - 0.03, hl - 0.2, 2.5, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
    B(list, -hl - 0.05, 1.4, -hw * 0.8, -hl, spec.height - 0.2, hw * 0.8, C.lightGray, C.lightGray, C.lightGray)
  end
  B(list, -hl - 0.06, 1.0, -hw * 0.8, -hl, 1.3, -hw * 0.5, C.red)
  B(list, -hl - 0.06, 1.0, hw * 0.5, -hl, 1.3, hw * 0.8, C.red)
  if stage >= 1 or wrecked then B(list, -1, 1.4, hw, 1.5, 2.2, hw + 0.04, C.gray, C.gray, C.gray, { noTop = true }) end
  if stage >= 3 and not wrecked then flames(list, 0, 3.0, 0, true) end
  return list
end

-- ---------------------------------------------------------------- boats

local function hull(list, L, W, floor, rim, body, deck)
  local hl, hw = L / 2, W / 2
  B(list, -hl, floor, -hw, hl * 0.45, rim, hw, deck, body, body)
  B(list, hl * 0.45, floor + 0.05, -hw * 0.72, hl * 0.8, rim + 0.05, hw * 0.72, deck, body, body)
  B(list, hl * 0.8, floor + 0.1, -hw * 0.34, hl, rim + 0.12, hw * 0.34, deck, body, body)
end

local function boatModel(spec, bodyName, stripeName, stage, wrecked)
  local list = {}
  local L, W = spec.length, spec.width
  local hl, hw = L / 2, W / 2
  local body = wrecked and C.gray or col(bodyName)
  local cabin = wrecked and C.black or col(spec.cabin or "black")
  local stripe = stripeName and not wrecked and col(stripeName) or nil
  local dark = C.black
  local shape = spec.shape
  if shape == "jetski" then
    B(list, -hl, -0.25, -hw, hl * 0.6, 0.45, hw, body, body, body)
    B(list, hl * 0.6, -0.2, -hw * 0.6, hl, 0.35, hw * 0.6, body, body, body)
    B(list, -hl * 0.5, 0.45, -hw * 0.4, hl * 0.1, 0.7, hw * 0.4, dark, dark, dark)
    B(list, hl * 0.15, 0.45, -hw * 0.5, hl * 0.35, 1.0, hw * 0.5, body, cabin, cabin)
    B(list, hl * 0.3, 1.0, -hw * 0.9, hl * 0.36, 1.1, hw * 0.9, dark, dark, dark)
    local shirt = C.orange
    B(list, -hl * 0.45, 0.7, -0.25, -hl * 0.1, 1.5, 0.25, shirt, shirt, shirt)
    B(list, -hl * 0.4, 1.5, -0.15, -hl * 0.15, 1.8, 0.15, dark, C.pink, C.pink)
    if stripe then B(list, -hl, 0.45, -0.05, hl * 0.5, 0.48, 0.05, stripe) end
  elseif shape == "barge" then
    B(list, -hl, -0.4, -hw, hl, 1.1, hw, body, body, body)
    B(list, hl * 0.7, 1.1, -hw * 0.5, hl, 1.4, hw * 0.5, body, body, body) -- the bow deck
    B(list, -hl * 0.85, 1.1, -hw * 0.6, -hl * 0.45, 3.2, hw * 0.6, cabin, cabin, cabin) -- the wheelhouse
    B(list, -hl * 0.84, 2.2, -hw * 0.62, -hl * 0.43, 2.9, hw * 0.62, C.black, C.black, C.black, { noTop = true })
    for k = 0, 2 do
      local c = col(({ "red", "blue", "green" })[k + 1])
      B(list, -hl * 0.3 + k * 2.2, 1.1, -hw * 0.6, -hl * 0.3 + k * 2.2 + 1.9, 2.4, hw * 0.6, c, c, c)
    end
    if stripe then B(list, -hl, 0.5, -hw - 0.03, hl, 0.85, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
  else
    local rim = shape == "patrol" and 0.9 or 0.65
    hull(list, L, W, -0.3, rim, body, shape == "skiff" and C.brown or C.lightGray)
    if stripe then B(list, -hl, rim - 0.2, -hw - 0.03, hl * 0.45, rim - 0.05, hw + 0.03, stripe, stripe, stripe, { noTop = true }) end
    if shape == "skiff" then
      B(list, -hl * 0.4, rim, -hw * 0.9, -hl * 0.2, rim + 0.12, hw * 0.9, C.brown, C.brown, C.brown)
      B(list, hl * 0.05, rim, -hw * 0.9, hl * 0.25, rim + 0.12, hw * 0.9, C.brown, C.brown, C.brown)
      B(list, -hl - 0.35, 0.0, -0.2, -hl, 0.95, 0.2, dark, dark, dark)
    elseif shape == "speedboat" then
      B(list, -hl * 0.1, rim, -hw * 0.75, hl * 0.3, rim + 0.7, hw * 0.75, cabin, cabin, cabin)
      B(list, -hl * 0.1, rim + 0.7, -hw * 0.6, hl * 0.25, rim + 0.78, hw * 0.6, body, body, body)
      B(list, -hl * 0.7, rim, -hw * 0.8, -hl * 0.4, rim + 0.4, hw * 0.8, dark, dark, dark)
      B(list, -hl - 0.3, -0.1, -0.5, -hl, 0.5, 0.5, dark, dark, dark)
    else
      -- the patrol boat: a wheelhouse, a light bar, a rail
      B(list, -hl * 0.45, rim, -hw * 0.75, hl * 0.2, rim + 1.5, hw * 0.75, cabin, C.black, C.black)
      B(list, -hl * 0.45, rim + 1.5, -hw * 0.8, hl * 0.25, rim + 1.6, hw * 0.8, body, body, body)
      if not wrecked then
        B(list, -hl * 0.2, rim + 1.6, -hw * 0.5, hl * 0.05, rim + 1.85, 0, C.red)
        B(list, -hl * 0.2, rim + 1.6, 0, hl * 0.05, rim + 1.85, hw * 0.5, C.blue)
      end
      B(list, -hl, rim, -hw, -hl * 0.5, rim + 0.4, hw, C.lightGray, C.lightGray, C.lightGray, { noTop = true })
    end
  end
  if stage >= 1 or wrecked then B(list, -hl * 0.2, 0.15, hw, hl * 0.3, 0.55, hw + 0.04, C.gray, C.gray, C.gray, { noTop = true }) end
  if stage >= 3 and not wrecked then flames(list, -hl * 0.1, 0.9, 0, false) end
  return list
end

-- ---------------------------------------------------------------- the helicopter

local function heliModel(spec, bodyName, _, stage, wrecked)
  local list = {}
  local body = wrecked and C.gray or col(bodyName)
  local glass = wrecked and C.black or C.blue
  local dark = C.black
  B(list, -1.4, 0.7, -1.0, 2.6, 2.4, 1.0, body, body, body)
  B(list, 2.0, 0.9, -0.85, 3.3, 2.1, 0.85, glass, glass, glass)
  B(list, -4.2, 1.5, -0.25, -1.4, 2.1, 0.25, body, body, body) -- the tail boom
  B(list, -4.3, 1.5, -0.08, -3.7, 3.3, 0.08, body, body, body) -- the fin
  B(list, -4.3, 2.8, -0.9, -3.9, 2.9, 0.9, dark, dark, dark)
  B(list, -1.0, 2.4, -0.2, 0.4, 3.0, 0.2, dark, dark, dark) -- the mast
  B(list, -3.9, 3.0, -0.2, 3.9, 3.07, 0.2, dark, dark, dark) -- the blades, one way
  B(list, -0.2, 3.0, -3.9, 0.2, 3.07, 3.9, dark, dark, dark) -- and the other
  B(list, -1.2, 0.0, -0.85, 2.2, 0.12, -0.7, dark, dark, dark) -- the skids
  B(list, -1.2, 0.0, 0.7, 2.2, 0.12, 0.85, dark, dark, dark)
  B(list, -0.5, 0.1, -0.85, -0.4, 0.8, -0.7, dark)
  B(list, -0.5, 0.1, 0.7, -0.4, 0.8, 0.85, dark)
  if not wrecked then
    B(list, 1.0, 0.6, -0.4, 1.9, 0.7, 0.4, C.yellow, C.yellow, C.yellow) -- the searchlight
    B(list, -0.6, 2.4, -0.5, 0.2, 2.55, 0, C.red)
    B(list, -0.6, 2.4, 0, 0.2, 2.55, 0.5, C.blue)
  end
  if stage >= 1 or wrecked then B(list, -0.4, 1.0, 1.0, 1.4, 1.8, 1.04, C.gray, C.gray, C.gray, { noTop = true }) end
  if stage >= 3 and not wrecked then flames(list, -1.5, 2.4, 0, false) end
  return list
end

-- ---------------------------------------------------------------- the entry point

local BUILDERS = { car = carModel, truck = truckModel, trailer = trailerModel, bike = bikeModel, boat = boatModel,
  heli = heliModel }

--- The model of a vehicle spec in a colour string. wrecked is the legacy flag (a burnt-out shell).
function M.build(spec, colour, wrecked)
  local bodyName, stripeName, stage = custom.parse(colour)
  stage = math.min(3, stage or 0)
  local builder = BUILDERS[spec.class or "car"] or carModel
  return builder(spec, bodyName, stripeName, stage, wrecked)
end

local original = nil

--- Whether our builder should answer for this spec and colour: anything with a class, or a legacy car that is
-- damaged or painted with a stripe. A clean legacy car is left to the game's own builder, exactly as before.
function M.mine(spec, colour)
  if spec.class ~= nil then return true end
  return type(colour) == "string" and colour:find("[|:]") ~= nil
end

--- Route sg/models.lua's car() through here. Safe to call twice.
function M.install()
  if original then return end
  original = base.car
  base.car = function(spec, colour, wrecked)
    if M.mine(spec, colour) then return M.build(spec, colour, wrecked) end
    return original(spec, colour, wrecked)
  end
end

function M.uninstall()
  if original then
    base.car = original
    original = nil
  end
end

return M
