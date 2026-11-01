-- games/blightmare/art.lua
-- Everything that stands in the first-person view, and the faces. A sprite is shapes in a unit square with the floor along the
-- bottom, as in Dungeon, so it stays crisp at every distance, and bake turns it into runs of colour once for each size. A
-- portrait is drawn cell by cell instead: at 20 by 15 a shape can't choose where an eye lands. A cell is 2 wide by 3 tall, so
-- a face 10 cells wide and 8 tall is about the right shape on the wall.
--
-- Skin is the story's language. The living are warm (orange and brown), and whoever the Clinic or the plague has touched is
-- pale. Grey and lime is the Blightmare itself.

local ui = require("lib.arcade.ui")

local C = ui.C
local ceil, floor, sqrt = math.ceil, math.floor, math.sqrt

local M = {}

-- ---------------------------------------------------------------- shapes

local function E(cx, cy, rx, ry, color) return { kind = "e", cx = cx, cy = cy, rx = rx, ry = ry, color = color } end
local function R(x, y, w, h, color) return { kind = "r", x = x, y = y, w = w, h = h, color = color } end
local function P(color, ...) return { kind = "p", points = { ... }, color = color } end

--- The same shapes on the other side of the middle as well.
local function both(...)
  local out = {}
  for _, s in ipairs({ ... }) do
    out[#out + 1] = s
    if s.kind == "e" then
      out[#out + 1] = E(1 - s.cx, s.cy, s.rx, s.ry, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(1 - s.x - s.w, s.y, s.w, s.h, s.color)
    else
      local flipped = {}
      for i, v in ipairs(s.points) do flipped[i] = i % 2 == 1 and 1 - v or v end
      out[#out + 1] = P(s.color, unpack(flipped))
    end
  end
  return unpack(out)
end

local function shapes(...) return { ... } end

--- One flat list from groups of shapes.
local function flatten(...)
  local out = {}
  for _, group in ipairs({ ... }) do
    for _, s in ipairs(group) do out[#out + 1] = s end
  end
  return out
end

local function pair(...) return { both(...) } end

--- Shapes drawn for a body the height of the square, shrunk to stand on the floor at the given share of it.
local function standing(tall, list)
  local top = 1 - tall
  local out = {}
  local function sx(x) return 0.5 + (x - 0.5) * tall end
  local function sy(y) return top + y * tall end
  for _, s in ipairs(list) do
    if s.kind == "e" then
      out[#out + 1] = E(sx(s.cx), sy(s.cy), s.rx * tall, s.ry * tall, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(sx(s.x), sy(s.y), s.w * tall, s.h * tall, s.color)
    else
      local pts = {}
      for i, v in ipairs(s.points) do pts[i] = i % 2 == 1 and sx(v) or sy(v) end
      out[#out + 1] = P(s.color, unpack(pts))
    end
  end
  return out
end

-- ---------------------------------------------------------------- people

--- A body: skin, coat, a second coat colour down the front, and legs. extra goes on top: hats, tools, whatever makes them them.
local function body(look, extra)
  return flatten(
    pair(R(0.39, 0.72, 0.1, 0.24, look.legs), R(0.36, 0.95, 0.14, 0.05, C.bg)),
    pair(P(look.coat, 0.33, 0.34, 0.24, 0.38, 0.2, 0.68, 0.28, 0.7, 0.34, 0.5), E(0.24, 0.7, 0.04, 0.04, look.skin)),
    shapes(
      P(look.coat, 0.34, 0.3, 0.66, 0.3, 0.7, 0.8, 0.3, 0.8), P(look.trim, 0.45, 0.3, 0.55, 0.3, 0.54, 0.8, 0.46, 0.8),
      R(0.44, 0.24, 0.12, 0.08, look.skin), E(0.5, 0.17, 0.12, 0.13, look.skin)
    ),
    pair(R(0.41, 0.13, 0.06, 0.05, C.bg)),
    shapes(R(0.45, 0.23, 0.1, 0.02, C.bg)),
    extra or {}
  )
end

local function hero()
  return body({ skin = C.warn, coat = C.tie, trim = C.panel, legs = C.redTint }, flatten(
    shapes(P(C.bg, 0.36, 0.15, 0.38, 0.05, 0.5, 0.01, 0.62, 0.05, 0.64, 0.15, 0.6, 0.1, 0.5, 0.08, 0.4, 0.1)),
    shapes(R(0.74, 0.56, 0.02, 0.14, C.text), R(0.73, 0.68, 0.04, 0.03, C.redTint))
  ))
end

local function villager()
  return body({ skin = C.warn, coat = C.redTint, trim = C.tie, legs = C.panel }, shapes(
    P(C.tie, 0.37, 0.12, 0.42, 0.03, 0.58, 0.03, 0.63, 0.12), P(C.line, 0.34, 0.32, 0.66, 0.32, 0.5, 0.4)
  ))
end

local function child()
  return body({ skin = C.text, coat = C.tie, trim = C.line, legs = C.panel }, shapes(
    P(C.redTint, 0.36, 0.14, 0.4, 0.03, 0.6, 0.03, 0.64, 0.14, 0.58, 0.09, 0.42, 0.09), E(0.74, 0.7, 0.03, 0.05, C.line), E(0.74, 0.64, 0.025, 0.025, C.text)
  ))
end

local function deserter()
  return body({ skin = C.warn, coat = C.bg, trim = C.line, legs = C.bg }, shapes(
    P(C.panel, 0.38, 0.1, 0.42, 0.03, 0.58, 0.03, 0.62, 0.1), R(0.38, 0.3, 0.24, 0.03, C.text), R(0.3, 0.42, 0.08, 0.06, C.text),
    R(0.33, 0.43, 0.02, 0.04, C.red), R(0.315, 0.445, 0.05, 0.015, C.red), P(C.line, 0.76, 0.2, 0.79, 0.2, 0.8, 0.7, 0.75, 0.7)
  ))
end

local function cleric()
  return body({ skin = C.text, coat = C.bg, trim = C.accent, legs = C.bg }, shapes(
    P(C.bg, 0.33, 0.3, 0.36, 0.08, 0.5, 0, 0.64, 0.08, 0.67, 0.3, 0.6, 0.27, 0.6, 0.1, 0.4, 0.1, 0.4, 0.27), P(C.accent, 0.46, 0.34, 0.54, 0.34, 0.5, 0.44),
    P(C.bg, 0.28, 0.5, 0.72, 0.5, 0.74, 0.92, 0.26, 0.92), R(0.48, 0.5, 0.04, 0.42, C.accent)
  ))
end

local function soldier(coat, trim, cap)
  return body({ skin = C.text, coat = coat, trim = trim, legs = C.bg }, shapes(
    P(cap, 0.36, 0.11, 0.38, 0.03, 0.62, 0.03, 0.64, 0.11), R(0.32, 0.11, 0.36, 0.025, C.bg), R(0.34, 0.32, 0.32, 0.03, C.bg),
    R(0.3, 0.42, 0.07, 0.05, C.text), R(0.33, 0.43, 0.015, 0.03, C.red), R(0.315, 0.44, 0.045, 0.012, C.red)
  ))
end

local function guard()
  return flatten(soldier(C.tie, C.panel, C.line), shapes(R(0.76, 0.02, 0.02, 0.96, C.redTint), P(C.text, 0.77, 0, 0.74, 0.08, 0.8, 0.08)))
end

local function captain()
  return flatten(soldier(C.blueTint, C.hi, C.blueTint), shapes(R(0.47, 0.06, 0.06, 0.03, C.hi)), pair(R(0.26, 0.33, 0.1, 0.03, C.hi)))
end

local function doctor()
  return body({ skin = C.text, coat = C.text, trim = C.line, legs = C.bg }, shapes(
    -- the mask, its beak turned on you, and the wide hat of the Clinic's doctors
    E(0.5, 0.17, 0.13, 0.14, C.text), P(C.line, 0.42, 0.2, 0.58, 0.2, 0.5, 0.44), E(0.43, 0.15, 0.04, 0.04, C.info), E(0.57, 0.15, 0.04, 0.04, C.info),
    P(C.bg, 0.3, 0.1, 0.7, 0.1, 0.62, 0.07, 0.6, 0, 0.4, 0, 0.38, 0.07), R(0.3, 0.52, 0.4, 0.012, C.line), R(0.74, 0.5, 0.05, 0.2, C.redTint)
  ))
end

local function mayor()
  return body({ skin = C.warn, coat = C.accent, trim = C.bg, legs = C.bg }, shapes(
    P(C.bg, 0.36, 0.08, 0.64, 0.08, 0.6, -0.1, 0.4, -0.1), R(0.32, 0.07, 0.36, 0.03, C.bg), R(0.4, 0.05, 0.2, 0.02, C.hi),
    P(C.text, 0.36, 0.2, 0.5, 0.17, 0.64, 0.2, 0.56, 0.24, 0.44, 0.24), P(C.hi, 0.36, 0.33, 0.64, 0.33, 0.5, 0.5, 0.48, 0.5)
  ))
end

local function gnomeBody(coat, trim, extra)
  return body({ skin = C.warn, coat = coat, trim = trim, legs = C.redTint }, flatten(
    shapes(P(C.redTint, 0.37, 0.2, 0.63, 0.2, 0.58, 0.46, 0.5, 0.52, 0.42, 0.46), E(0.5, 0.2, 0.035, 0.03, C.redTint)),
    extra
  ))
end

local function gnome()
  return gnomeBody(C.hiTint, C.tie, shapes(P(C.ok, 0.36, 0.1, 0.64, 0.1, 0.52, -0.2, 0.47, -0.2), R(0.34, 0.09, 0.32, 0.03, C.hiTint)))
end

local function smith()
  return gnomeBody(C.redTint, C.panel, shapes(
    E(0.5, 0.09, 0.11, 0.05, C.warn), P(C.tie, 0.33, 0.46, 0.67, 0.46, 0.7, 0.82, 0.3, 0.82), R(0.76, 0.46, 0.02, 0.24, C.redTint), R(0.72, 0.42, 0.1, 0.05, C.line)
  ))
end

local function innkeeper()
  return body({ skin = C.warn, coat = C.redTint, trim = C.text, legs = C.panel }, shapes(
    P(C.red, 0.36, 0.13, 0.4, 0.03, 0.6, 0.03, 0.64, 0.13), P(C.text, 0.34, 0.46, 0.66, 0.46, 0.7, 0.82, 0.3, 0.82), R(0.72, 0.52, 0.08, 0.1, C.hi), R(0.72, 0.5, 0.08, 0.03, C.text)
  ))
end

local function foremanBody()
  return body({ skin = C.line, coat = C.hiTint, trim = C.soft, legs = C.panel }, shapes(
    P(C.tie, 0.34, 0.1, 0.38, 0.0, 0.62, 0.0, 0.66, 0.1), R(0.3, 0.09, 0.4, 0.03, C.tie), E(0.5, 0.05, 0.05, 0.05, C.hi), R(0.41, 0.13, 0.06, 0.05, C.red),
    R(0.53, 0.13, 0.06, 0.05, C.red), P(C.soft, 0.6, 0.18, 0.72, 0.36, 0.66, 0.4, 0.58, 0.26), E(0.28, 0.55, 0.1, 0.09, C.soft), E(0.26, 0.54, 0.05, 0.05, C.ok),
    R(0.15, 0.3, 0.03, 0.56, C.redTint), P(C.line, 0.03, 0.34, 0.16, 0.26, 0.3, 0.34, 0.16, 0.32)
  ))
end

local function miner()
  return gnomeBody(C.hiTint, C.panel, shapes(
    P(C.tie, 0.34, 0.1, 0.38, 0.01, 0.62, 0.01, 0.66, 0.1), R(0.32, 0.09, 0.36, 0.03, C.tie), R(0.41, 0.13, 0.06, 0.05, C.red), R(0.53, 0.13, 0.06, 0.05, C.red),
    R(0.78, 0.26, 0.03, 0.46, C.redTint), P(C.line, 0.64, 0.3, 0.8, 0.22, 0.94, 0.3, 0.8, 0.28)
  ))
end

local function orderly()
  return body({ skin = C.text, coat = C.text, trim = C.line, legs = C.line }, shapes(
    P(C.text, 0.38, 0.11, 0.4, 0.04, 0.6, 0.04, 0.62, 0.11), R(0.41, 0.13, 0.18, 0.04, C.bg), P(C.line, 0.4, 0.2, 0.6, 0.2, 0.58, 0.28, 0.42, 0.28), E(0.42, 0.62, 0.05, 0.08, C.redTint),
    E(0.58, 0.52, 0.04, 0.05, C.red), R(0.74, 0.5, 0.03, 0.2, C.info), R(0.75, 0.68, 0.01, 0.1, C.text), R(0.73, 0.46, 0.05, 0.02, C.line)
  ))
end

--- What's left of a townsperson once the Blightmare has them: bent, grey, and growing something.
local function blighted()
  return flatten(
    shapes(E(0.5, 0.97, 0.3, 0.03, C.bg)),
    pair(R(0.36, 0.7, 0.1, 0.27, C.tie)),
    shapes(
      P(C.tie, 0.3, 0.4, 0.42, 0.26, 0.7, 0.3, 0.72, 0.78, 0.3, 0.78), P(C.line, 0.34, 0.42, 0.44, 0.3, 0.6, 0.34, 0.6, 0.7, 0.36, 0.7),
      R(0.2, 0.42, 0.1, 0.42, C.tie), R(0.7, 0.4, 0.1, 0.5, C.line), E(0.46, 0.26, 0.13, 0.13, C.line), E(0.56, 0.18, 0.1, 0.08, C.soft), E(0.62, 0.3, 0.07, 0.08, C.ok),
      R(0.38, 0.25, 0.06, 0.03, C.red), R(0.47, 0.25, 0.04, 0.03, C.bg), P(C.bg, 0.38, 0.32, 0.5, 0.32, 0.46, 0.38, 0.42, 0.38), E(0.5, 0.5, 0.06, 0.07, C.soft),
      E(0.42, 0.62, 0.03, 0.04, C.ok)
    )
  )
end

local function frogman()
  local skin, dark, belly = C.ok, C.hiTint, C.soft
  return flatten(
    pair(P(skin, 0.3, 0.7, 0.14, 0.72, 0.1, 0.96, 0.38, 0.98), P(dark, 0.06, 0.96, 0.42, 0.96, 0.42, 1, 0.04, 1)),
    shapes(E(0.5, 0.56, 0.26, 0.28, skin), E(0.5, 0.62, 0.17, 0.19, belly), E(0.5, 0.24, 0.26, 0.15, skin)),
    pair(E(0.32, 0.12, 0.08, 0.08, skin), E(0.32, 0.12, 0.05, 0.05, C.hi), R(0.27, 0.11, 0.1, 0.015, C.bg), R(0.2, 0.38, 0.08, 0.3, skin)),
    shapes(R(0.28, 0.3, 0.44, 0.02, C.bg), R(0.28, 0.32, 0.44, 0.03, dark), R(0.82, 0.08, 0.025, 0.8, C.redTint), P(C.line, 0.83, 0, 0.8, 0.1, 0.87, 0.1))
  )
end

local function harpy()
  local wing, rib = C.redTint, C.tie
  return flatten(
    pair(
      P(wing, 0.46, 0.34, 0.2, 0.08, 0.0, 0.14, 0.04, 0.5, 0.12, 0.42, 0.16, 0.62, 0.26, 0.5, 0.34, 0.68, 0.46, 0.56),
      P(rib, 0.2, 0.08, 0.23, 0.08, 0.42, 0.4, 0.4, 0.42), R(0.41, 0.86, 0.05, 0.08, C.hi), P(C.text, 0.38, 0.94, 0.4, 1, 0.42, 0.94)
    ),
    shapes(
      P(C.tie, 0.4, 0.34, 0.6, 0.34, 0.62, 0.8, 0.5, 0.9, 0.38, 0.8), E(0.5, 0.22, 0.11, 0.12, C.line), P(C.bg, 0.38, 0.22, 0.4, 0.06, 0.6, 0.06, 0.62, 0.22, 0.64, 0.4, 0.58, 0.3, 0.42, 0.3, 0.36, 0.4),
      E(0.5, 0.23, 0.08, 0.09, C.line), R(0.44, 0.2, 0.04, 0.03, C.hi), R(0.52, 0.2, 0.04, 0.03, C.hi), P(C.hi, 0.47, 0.25, 0.53, 0.25, 0.5, 0.33)
    )
  )
end

--- Long, thin and low to the ground. It looks too much like a person.
local function stalker()
  return flatten(
    pair(P(C.panel, 0.34, 0.5, 0.16, 0.54, 0.06, 0.96, 0.12, 0.98, 0.24, 0.62, 0.36, 0.6)),
    shapes(P(C.panel, 0.34, 0.42, 0.66, 0.42, 0.62, 0.74, 0.38, 0.74), E(0.5, 0.36, 0.17, 0.14, C.tie)),
    pair(R(0.4, 0.34, 0.06, 0.03, C.red), P(C.line, 0.1, 0.96, 0.06, 1, 0.14, 1)),
    shapes(P(C.bg, 0.4, 0.42, 0.6, 0.42, 0.56, 0.48, 0.44, 0.48), R(0.46, 0.42, 0.015, 0.05, C.text), R(0.52, 0.42, 0.015, 0.05, C.text))
  )
end

--- A pale, soft thing with too many legs, the size of a dog. What comes through the crack in the wall.
local function crawler()
  local skin, dark = C.line, C.tie
  local legs = {}
  for i = 0, 3 do
    legs[#legs + 1] = P(dark, 0.3 - i * 0.03, 0.62 + i * 0.03, 0.06 + i * 0.02, 0.56 + i * 0.1, 0.02 + i * 0.04, 0.98, 0.08 + i * 0.04, 0.98, 0.32 - i * 0.03, 0.72)
  end
  return flatten(
    { both(unpack(legs)) },
    shapes(E(0.5, 0.68, 0.32, 0.27, skin), E(0.42, 0.62, 0.15, 0.1, C.text), E(0.5, 0.5, 0.2, 0.17, skin), E(0.5, 0.82, 0.22, 0.09, dark)),
    shapes(E(0.5, 0.55, 0.11, 0.1, C.bg), E(0.5, 0.56, 0.07, 0.06, C.red)),
    pair(R(0.36, 0.48, 0.03, 0.03, C.bg), E(0.28, 0.72, 0.03, 0.03, C.soft)),
    shapes(P(C.text, 0.42, 0.47, 0.45, 0.47, 0.44, 0.54), P(C.text, 0.48, 0.45, 0.52, 0.45, 0.5, 0.52), P(C.text, 0.55, 0.47, 0.58, 0.47, 0.56, 0.54), P(C.text, 0.44, 0.65, 0.47, 0.65, 0.46, 0.59), P(C.text, 0.53, 0.65, 0.56, 0.65, 0.54, 0.59))
  )
end

local function rat()
  local fur, face, dark = C.tie, C.line, C.bg
  return flatten(
    shapes(
      P(C.red, 0.86, 0.8, 0.92, 0.78, 0.99, 0.5, 0.95, 0.48), E(0.5, 0.6, 0.46, 0.38, fur), E(0.5, 0.86, 0.3, 0.12, C.panel),
      P(fur, 0.14, 0.42, 0.1, 0.24, 0.24, 0.32, 0.26, 0.14, 0.38, 0.26, 0.5, 0.1, 0.62, 0.26, 0.74, 0.14, 0.76, 0.32, 0.9, 0.24, 0.86, 0.42)
    ),
    pair(P(face, 0.3, 0.42, 0.1, 0.3, 0.16, 0.2, 0.2, 0.26, 0.26, 0.2, 0.38, 0.34), P(C.redTint, 0.29, 0.4, 0.16, 0.31, 0.2, 0.28, 0.34, 0.35)),
    shapes(P(face, 0.24, 0.42, 0.76, 0.42, 0.68, 0.58, 0.58, 0.7, 0.42, 0.7, 0.32, 0.58)),
    pair(
      P(dark, 0.27, 0.42, 0.47, 0.52, 0.46, 0.56, 0.3, 0.5), P(C.red, 0.33, 0.48, 0.45, 0.54, 0.44, 0.57, 0.35, 0.53), R(0.16, 0.6, 0.22, 0.008, dark),
      E(0.24, 0.93, 0.1, 0.05, face), P(C.text, 0.15, 0.94, 0.17, 1, 0.19, 0.94), P(C.text, 0.21, 0.95, 0.23, 1, 0.25, 0.95)
    ),
    shapes(P(dark, 0.34, 0.68, 0.66, 0.68, 0.6, 0.9, 0.4, 0.9), P(C.redTint, 0.42, 0.78, 0.58, 0.78, 0.56, 0.88, 0.44, 0.88)),
    pair(P(C.text, 0.36, 0.68, 0.48, 0.68, 0.44, 0.84, 0.42, 0.84))
  )
end

-- ---------------------------------------------------------------- things on the floor

local function chest()
  local wood, dark, band = C.warn, C.redTint, C.line
  return flatten(
    shapes(
      R(0.02, 0.5, 0.96, 0.48, dark), E(0.5, 0.42, 0.48, 0.22, wood), R(0.02, 0.42, 0.96, 0.14, wood), R(0.02, 0.55, 0.96, 0.06, C.bg),
      R(0.02, 0.61, 0.96, 0.37, wood), R(0.02, 0.74, 0.96, 0.012, dark), R(0.02, 0.86, 0.96, 0.012, dark), R(0.0, 0.92, 1, 0.08, dark),
      R(0.42, 0.48, 0.16, 0.24, C.hi), R(0.47, 0.57, 0.06, 0.09, C.bg)
    ),
    pair(R(0.13, 0.2, 0.08, 0.8, band))
  )
end

local function openChest()
  local wood, dark, band = C.warn, C.redTint, C.line
  return flatten(
    shapes(
      R(0.04, 0.12, 0.92, 0.42, dark), R(0.1, 0.18, 0.8, 0.32, C.bg), R(0.02, 0.5, 0.96, 0.08, C.bg), R(0.02, 0.56, 0.96, 0.42, wood),
      R(0.02, 0.74, 0.96, 0.012, dark), R(0.02, 0.86, 0.96, 0.012, dark), R(0.0, 0.92, 1, 0.08, dark)
    ),
    pair(R(0.13, 0.56, 0.08, 0.44, band), R(0.13, 0.12, 0.08, 0.38, band))
  )
end

--- A wrapped body on the ground, for a map to leave lying about.
local function shroud()
  return shapes(E(0.5, 0.8, 0.46, 0.18, C.line), E(0.5, 0.74, 0.44, 0.13, C.text), R(0.3, 0.64, 0.015, 0.3, C.line), R(0.62, 0.64, 0.015, 0.3, C.line), E(0.82, 0.74, 0.09, 0.09, C.text))
end

local function person(build, size) return { build = build, size = size or 1, near = 0.1 } end

local function small(build) return function() return standing(0.6, build()) end end
local function tiny(build) return function() return standing(0.46, build()) end end

-- A sprite's size is its share of a square. near is where in its square it stands: 0 at the front, 1 at the back.
local SPRITES = {
  hero = person(hero), villager = person(villager), child = person(tiny(child)), deserter = person(deserter), cleric = person(cleric),
  guard = person(guard), soldier = person(guard), captain = person(captain), doctor = person(doctor), mayor = person(small(mayor), 1.04),
  gnome = person(small(gnome)), smith = person(small(smith)), innkeeper = person(innkeeper), foreman = person(small(foremanBody), 1.14),
  miner = person(small(miner)), orderly = person(orderly), blighted = person(blighted), frogman = person(frogman), harpy = person(harpy, 0.95),
  stalker = person(stalker, 0.86), crawler = person(crawler, 0.72), rat = person(rat, 0.5),
  chest = { build = chest, size = 0.42, near = 0.5 }, openChest = { build = openChest, size = 0.42, near = 0.5 },
  shroud = { build = shroud, size = 0.5, near = 0.45 },
}
M.SPRITES = SPRITES

--- A sprite that exists: a map can name someone new and only look like a villager until they're drawn.
function M.spriteName(name) return SPRITES[name] and name or "villager" end

-- ---------------------------------------------------------------- looks
-- A person is a plain description, and both their sprite and their portrait are drawn from it, from the same shapes: the
-- portrait is the top of the sprite, zoomed in. So someone looks the same in the corridor and in the talk box. Shapes are built
-- for a body the height of the square, feet at the bottom, head at about 0.17; tall then shrinks all of it onto the floor.
--
-- Fields, all optional but kind: tall (share of the square), build, lean, skin, hair and hairInk, beard and beardInk, hat, hatInk
-- and hatTrim, hatSmall, cut (tunic, coat, dress, robe), coat, trim, legs, wear (a list), carry, carryInk, eyes, mouth, nose, mark,
-- beak (length of a Clinic mask), blight, back (portrait backdrop), pose ("lying"), stand ("box", "stocks"), oneShoe, empty.

local LOOK_KIND = {
  -- head rx, ry, and what they are unless told otherwise
  human = { 0.125, 0.135, tall = 0.9, skin = C.warn, back = C.hiTint },
  old = { 0.12, 0.13, tall = 0.82, skin = C.warn, back = C.hiTint, eyes = "narrow" },
  child = { 0.15, 0.15, tall = 0.5, skin = C.warn, back = C.tie, eyes = "wide" },
  clinic = { 0.125, 0.135, tall = 0.92, skin = C.text, back = C.redTint, eyes = "lens", mouth = "none", nose = "none" },
  ["half-elf"] = { 0.115, 0.14, tall = 0.95, skin = C.warn, back = C.redTint, ears = "long" },
  gnome = { 0.155, 0.125, tall = 0.54, skin = C.warn, back = C.blueTint, nose = "big", ears = "round" },
  miner = { 0.14, 0.12, tall = 0.68, skin = C.warn, back = C.panel, nose = "big", ears = "round" }, -- dwarf height
  frog = { 0.2, 0.11, tall = 0.86, skin = C.ok, back = C.panel, eyes = "none", mouth = "none", nose = "none" },
  owlin = { 0.155, 0.15, tall = 0.8, skin = C.tie, back = C.blueTint, eyes = "none", mouth = "none", nose = "none" },
}
local LOOK_BUILD = { thin = { 0.115, 0.1 }, normal = { 0.155, 0.14 }, stout = { 0.19, 0.26 }, broad = { 0.25, 0.17 }, hunched = { 0.15, 0.14 } }
local LOOK_HEM = { tunic = 0.66, coat = 0.84, dress = 0.92, robe = 0.97 }
local SKIN_SHADE = { [C.warn] = C.redTint, [C.text] = C.line, [C.line] = C.tie, [C.ok] = C.hiTint, [C.tie] = C.panel, [C.hi] = C.warn, [C.soft] = C.ok }

--- Hats, on a head at hx, hy of rx by ry. Each is as much about the outline as the colour.
local HAT = {}

function HAT.cap(a, hx, hy, rx, ry, ink, trim)
  a(E(hx, hy - ry * 0.55, rx * 1.02, ry * 0.75, ink))
  a(R(hx - rx, hy - ry * 0.5, rx * 2.5, 0.028, trim))
end
function HAT.tophat(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(R(hx - rx * 0.8, top - 0.2, rx * 1.6, 0.22, ink))
  a(R(hx - rx * 0.8, top - 0.03, rx * 1.6, 0.03, trim))
  a(R(hx - rx * 1.3, top + 0.0, rx * 2.6, 0.025, ink))
end
function HAT.stovepipe(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 0.7, top + 0.01, hx + rx * 0.7, top + 0.01, hx + rx, top - 0.32, hx - rx, top - 0.32))
  a(R(hx - rx * 0.3, top - 0.1, rx * 0.6, 0.06, trim))
  a(R(hx - rx * 1.2, top, rx * 2.4, 0.03, ink))
end
function HAT.wide(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(R(hx - rx * 2.1, top + 0.03, rx * 4.2, 0.03, ink))
  a(E(hx, top + 0.01, rx * 0.95, 0.06, ink))
  a(R(hx - rx * 0.95, top + 0.01, rx * 1.9, 0.02, trim))
end
function HAT.straw(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 2.2, top + 0.06, hx + rx * 2.2, top + 0.06, hx + 0.02, top - 0.12))
  a(P(trim, hx - rx * 2.2, top + 0.06, hx + rx * 2.2, top + 0.06, hx + rx * 2, top + 0.03, hx - rx * 2, top + 0.03))
end
function HAT.pointy(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.1, top + 0.05, hx + rx * 1.1, top + 0.05, hx + 0.015, top - 0.34, hx - 0.015, top - 0.34))
  a(R(hx - rx * 1.15, top + 0.03, rx * 2.3, 0.03, trim))
end
function HAT.floppy(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.05, top + 0.05, hx + rx * 1.05, top + 0.05, hx + rx * 0.4, top - 0.17, hx - rx * 2.2, top - 0.12, hx - rx * 2.5, top - 0.02, hx - rx * 1.7, top - 0.08, hx - rx * 0.6, top - 0.1))
  a(R(hx - rx * 1.1, top + 0.03, rx * 2.2, 0.03, trim))
end
function HAT.nightcap(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.05, top + 0.05, hx + rx * 1.05, top + 0.05, hx + rx * 0.5, top - 0.1, hx + rx * 2.2, top + 0.0, hx + rx * 2.4, top + 0.2, hx + rx * 1.9, top + 0.2, hx + rx * 1.7, top + 0.04))
  a(E(hx + rx * 2.15, top + 0.23, 0.04, 0.04, trim))
  a(R(hx - rx * 1.1, top + 0.03, rx * 2.2, 0.035, trim))
end
function HAT.mushroom(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(E(hx, top - 0.02, rx * 2, 0.11, ink))
  a(E(hx - rx, top - 0.05, 0.03, 0.025, trim))
  a(E(hx + rx * 0.7, top - 0.07, 0.035, 0.03, trim))
  a(E(hx + rx * 1.4, top - 0.01, 0.02, 0.02, trim))
end
function HAT.helmet(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(E(hx, top + 0.04, rx * 1.15, 0.085, ink))
  a(R(hx - rx * 1.5, top + 0.05, rx * 3, 0.03, ink))
  a(E(hx, top - 0.005, 0.04, 0.04, trim))
  a(E(hx, top - 0.005, 0.02, 0.02, C.text))
end
function HAT.horned(a, hx, hy, rx, ry, ink, trim)
  HAT.helmet(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(C.text, hx - rx, top + 0.03, hx - rx * 1.8, top - 0.1, hx - rx * 1.05, top - 0.03))
  a(P(C.text, hx + rx, top + 0.03, hx + rx * 1.8, top - 0.1, hx + rx * 1.05, top - 0.03))
end
function HAT.pot(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(R(hx - rx * 1.1, top - 0.03, rx * 2.2, 0.1, ink))
  a(R(hx - rx * 1.25, top + 0.07, rx * 2.5, 0.02, trim))
  a(R(hx + rx * 1.05, top + 0.0, rx * 1.1, 0.025, trim))
  a(E(hx, top - 0.05, 0.022, 0.02, trim))
end
function HAT.feather(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.5, top + 0.06, hx + rx * 1.5, top + 0.06, hx + rx * 0.8, top - 0.06, hx - rx * 0.8, top - 0.06))
  a(P(trim, hx + rx * 0.2, top - 0.03, hx + rx * 0.6, top - 0.03, hx + rx * 2.4, top - 0.3, hx + rx * 1.8, top - 0.3))
end
function HAT.bowler(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(E(hx, top + 0.03, rx * 0.95, 0.08, ink))
  a(R(hx - rx * 1.35, top + 0.05, rx * 2.7, 0.022, ink))
  a(R(hx - rx * 0.95, top + 0.03, rx * 1.9, 0.015, trim))
end
function HAT.earflap(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(E(hx, top + 0.04, rx * 1.1, 0.08, ink))
  a(R(hx - rx * 1.45, top + 0.04, rx * 0.5, 0.15, ink))
  a(R(hx + rx * 0.95, top + 0.04, rx * 0.5, 0.15, ink))
  a(R(hx - rx * 1.2, top + 0.05, rx * 2.4, 0.03, trim))
end
function HAT.scarf(a, hx, hy, rx, ry, ink, trim)
  a(E(hx, hy - ry * 0.45, rx * 1.1, ry * 0.8, ink))
  a(P(ink, hx + rx * 0.7, hy + 0.02, hx + rx * 1.5, hy + 0.14, hx + rx * 0.9, hy + 0.15))
  a(R(hx - rx, hy - ry * 0.25, rx * 2, 0.02, trim))
end
function HAT.visor(a, hx, hy, rx, ry, ink, trim)
  a(P(ink, hx - rx * 1.05, hy - ry * 0.5, hx + rx * 1.05, hy - ry * 0.5, hx + rx * 1.4, hy - ry * 0.15, hx - rx * 1.4, hy - ry * 0.15))
  a(R(hx - rx * 1.05, hy - ry * 0.6, rx * 2.1, 0.02, trim))
end
function HAT.hood(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.5, hy + ry * 1.2, hx - rx * 1.3, top, hx - 0.01, top - 0.1, hx + rx * 1.3, top, hx + rx * 1.5, hy + ry * 1.2, hx + rx * 0.95, hy + ry * 0.8, hx + rx * 0.9, hy - ry * 0.5, hx - rx * 0.9, hy - ry * 0.5, hx - rx * 0.95, hy + ry * 0.8))
  a(R(hx - rx * 1.5, hy + ry * 1.1, rx * 3, 0.02, trim))
end
function HAT.veil(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.25, top + 0.04, hx + rx * 1.25, top + 0.04, hx + rx * 2, hy + 0.26, hx - rx * 2, hy + 0.26, hx - rx * 1.3, hy + 0.1, hx - rx * 0.95, hy - ry * 0.4, hx + rx * 0.95, hy - ry * 0.4, hx + rx * 1.3, hy + 0.1))
  a(R(hx - rx * 1.5, top + 0.02, rx * 3, 0.03, ink))
  a(E(hx, top, 0.06, 0.04, ink))
  a(R(hx - rx * 1.2, top + 0.04, rx * 2.4, 0.012, trim))
end
function HAT.peaked(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.5, top - 0.03, hx + rx * 1.5, top - 0.03, hx + rx * 1.05, top + 0.05, hx - rx * 1.05, top + 0.05))
  a(R(hx - rx * 1.25, top + 0.04, rx * 2.5, 0.03, C.bg))
  a(R(hx - 0.02, top - 0.02, 0.04, 0.04, trim))
end
function HAT.sallet(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(P(ink, hx - rx * 1.1, hy - 0.01, hx + rx * 1.1, hy - 0.01, hx + rx * 1.1, top + 0.02, hx, top - 0.05, hx - rx * 1.1, top + 0.02))
  a(R(hx - rx * 1.45, hy - 0.02, rx * 0.6, 0.11, ink))
  a(R(hx - rx * 1.1, top + 0.05, rx * 2.2, 0.02, trim))
  a(P(trim, hx - 0.01, top - 0.05, hx + 0.01, top - 0.05, hx + 0.012, top - 0.14, hx - 0.012, top - 0.14))
end
function HAT.beakhat(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(R(hx - rx * 2.3, top + 0.04, rx * 4.6, 0.025, ink))
  a(P(ink, hx - rx, top + 0.05, hx + rx, top + 0.05, hx + rx * 0.75, top - 0.13, hx - rx * 0.75, top - 0.13))
  a(R(hx - rx, top + 0.015, rx * 2, 0.02, trim))
end
function HAT.bandage(a, hx, hy, rx, ry, ink, trim)
  a(E(hx, hy - ry * 0.8, rx * 1.02, ry * 0.45, ink))
  a(R(hx - rx * 1.02, hy - ry * 0.6, rx * 2.04, 0.02, trim))
  a(P(ink, hx + rx * 0.7, hy - ry * 0.8, hx + rx * 1.5, hy - ry * 1.3, hx + rx * 1.1, hy - ry * 0.5))
  a(E(hx - rx * 0.5, hy - ry * 1.1, 0.04, 0.03, C.red))
end
--- Tibble's stock in trade, all of it, at once.
function HAT.stack(a, hx, hy, rx, ry)
  local top = hy - ry + 0.04
  local INKS = { C.red, C.hi, C.blue, C.ok, C.accent, C.warn, C.info, C.text, C.tie }
  for i, ink in ipairs(INKS) do
    local wide = rx * (1.3 - (i % 3) * 0.25)
    a(R(hx - wide + (i % 2) * 0.02, top - i * 0.06, wide * 2, 0.06, ink))
  end
end
function HAT.candles(a, hx, hy, rx, ry, ink, trim)
  local top = hy - ry
  a(R(hx - rx * 1.05, top + 0.0, rx * 2.1, 0.04, ink))
  for i = -1, 1 do
    local x = hx + i * rx * 0.75
    a(R(x - 0.015, top - 0.1 + math.abs(i) * 0.03, 0.03, 0.11, trim))
    a(E(x, top - 0.125 + math.abs(i) * 0.03, 0.022, 0.035, C.hi))
  end
end
function HAT.goggles(a, hx, hy, rx, ry, ink, trim)
  a(R(hx - rx, hy - ry * 0.75, rx * 2, 0.03, trim))
  a(E(hx - rx * 0.45, hy - ry * 0.72, 0.042, 0.038, ink))
  a(E(hx + rx * 0.45, hy - ry * 0.72, 0.042, 0.038, ink))
end

local function hairShapes(a, look, hx, hy, rx, ry)
  local style, ink = look.hair, look.hairInk or C.bg
  local top = hy - ry
  if not style then return end
  if style == "short" or style == "long" or style == "bun" or style == "plaits" or style == "pigtails" then
    a(P(ink, hx - rx * 1.05, hy, hx - rx * 1.02, top + 0.03, hx - rx * 0.5, top - 0.015, hx + rx * 0.5, top - 0.015, hx + rx * 1.02, top + 0.03, hx + rx * 1.05, hy, hx + rx * 0.8, hy - ry * 0.5, hx - rx * 0.8, hy - ry * 0.5))
  end
  if style == "long" then
    a(P(ink, hx - rx * 1.2, hy - 0.05, hx - rx * 0.85, hy - 0.05, hx - rx * 0.85, hy + 0.2, hx - rx * 1.4, hy + 0.26))
    a(P(ink, hx + rx * 1.2, hy - 0.05, hx + rx * 0.85, hy - 0.05, hx + rx * 0.85, hy + 0.2, hx + rx * 1.4, hy + 0.26))
  elseif style == "bun" then
    a(E(hx, top - 0.05, 0.07, 0.06, ink))
  elseif style == "plaits" then
    a(P(ink, hx - rx * 1.2, hy - 0.02, hx - rx * 0.9, hy - 0.02, hx - rx * 1.1, hy + 0.32, hx - rx * 1.5, hy + 0.32))
    a(P(ink, hx + rx * 1.2, hy - 0.02, hx + rx * 0.9, hy - 0.02, hx + rx * 1.1, hy + 0.32, hx + rx * 1.5, hy + 0.32))
  elseif style == "pigtails" then
    a(E(hx - rx * 1.5, hy - ry * 0.3, 0.06, 0.09, ink))
    a(E(hx + rx * 1.5, hy - ry * 0.3, 0.06, 0.09, ink))
  elseif style == "wild" then
    a(P(ink, hx - rx * 1.3, hy, hx - rx * 1.7, top - 0.02, hx - rx * 0.9, top - 0.04, hx - rx * 0.9, top - 0.14, hx - rx * 0.2, top - 0.06, hx + rx * 0.3, top - 0.16, hx + rx * 0.7, top - 0.05, hx + rx * 1.7, top - 0.08, hx + rx * 1.35, hy, hx + rx * 0.8, hy - ry * 0.5, hx - rx * 0.8, hy - ry * 0.5))
  elseif style == "curls" then
    for _, at in ipairs({ { -1, 0.1 }, { -0.7, -0.6 }, { 0, -0.95 }, { 0.7, -0.6 }, { 1, 0.1 } }) do a(E(hx + rx * at[1], hy + ry * at[2], 0.058, 0.055, ink)) end
  elseif style == "tufts" then
    a(E(hx - rx * 1.05, hy - ry * 0.2, 0.05, 0.06, ink))
    a(E(hx + rx * 1.05, hy - ry * 0.2, 0.05, 0.06, ink))
  elseif style == "crest" then
    a(P(ink, hx - 0.03, top + 0.02, hx + 0.03, top + 0.02, hx + 0.015, top - 0.17, hx - 0.015, top - 0.17))
  end
end

local function beardShapes(a, look, hx, hy, rx, ry)
  local style, ink = look.beard, look.beardInk or look.hairInk or C.bg
  local chin = hy + ry
  if style == "moustache" then
    a(P(ink, hx - rx * 1.1, hy + 0.045, hx + rx * 1.1, hy + 0.045, hx + rx * 0.5, hy + 0.08, hx - rx * 0.5, hy + 0.08))
  elseif style == "whiskers" then
    a(P(ink, hx - rx * 1.9, hy + 0.035, hx + rx * 1.9, hy + 0.035, hx + rx * 0.4, hy + 0.085, hx - rx * 0.4, hy + 0.085))
  elseif style == "chops" then
    a(E(hx - rx * 0.95, hy + 0.05, 0.05, 0.07, ink))
    a(E(hx + rx * 0.95, hy + 0.05, 0.05, 0.07, ink))
  elseif style == "goatee" then
    a(P(ink, hx - 0.03, chin - 0.03, hx + 0.03, chin - 0.03, hx + 0.01, chin + 0.12, hx - 0.01, chin + 0.12))
  elseif style == "long" then
    a(P(ink, hx - rx, hy + 0.03, hx + rx, hy + 0.03, hx + rx * 0.65, chin + 0.27, hx, chin + 0.34, hx - rx * 0.65, chin + 0.27))
  elseif style == "belted" then
    a(P(ink, hx - rx, hy + 0.03, hx + rx, hy + 0.03, hx + rx * 0.5, chin + 0.42, hx - rx * 0.5, chin + 0.42))
    a(R(hx - rx * 0.7, chin + 0.28, rx * 1.4, 0.03, C.redTint))
  elseif style == "forked" then
    a(P(ink, hx - rx, hy + 0.03, hx + rx, hy + 0.03, hx + rx * 1.2, chin + 0.22, hx + rx * 0.2, chin + 0.04, hx - rx * 1.2, chin + 0.22))
  elseif style == "bolster" then
    a(E(hx, chin + 0.03, rx * 1.75, 0.125, ink))
    a(R(hx - rx * 1.4, chin + 0.03, rx * 2.8, 0.018, look.beardTrim or C.warn))
  elseif style == "plaited" then
    a(P(ink, hx - rx, hy + 0.03, hx + rx, hy + 0.03, hx + rx * 0.25, chin + 0.3, hx - rx * 0.25, chin + 0.3))
    for i = 1, 3 do a(R(hx - rx * 0.4, chin + 0.04 + i * 0.06, rx * 0.8, 0.014, look.beardTrim or C.hi)) end
  elseif style == "stubble" then
    a(P(look.shade, hx - rx * 0.8, hy + 0.05, hx + rx * 0.8, hy + 0.05, hx + rx * 0.5, chin, hx - rx * 0.5, chin))
  end
end

--- Things worn on the body. sh and hip are the half-widths of the shoulders and the hem.
local WEAR = {}

function WEAR.apron(a, sh, hip, hem, look)
  a(P(look.apronInk or C.text, 0.5 - sh * 0.7, 0.42, 0.5 + sh * 0.7, 0.42, 0.5 + hip * 0.85, hem, 0.5 - hip * 0.85, hem))
  a(R(0.5 - sh * 0.75, 0.47, sh * 1.5, 0.02, C.line))
end
function WEAR.belt(a, sh, hip, hem, look)
  a(R(0.5 - sh - 0.01, 0.55, sh * 2 + 0.02, 0.035, C.bg))
  a(R(0.46, 0.545, 0.08, 0.045, look.beltInk or C.hi))
end
function WEAR.chain(a, sh)
  a(P(C.hi, 0.5 - sh * 0.85, 0.31, 0.5 + sh * 0.85, 0.31, 0.5, 0.46, 0.5, 0.42))
  a(E(0.5, 0.46, 0.035, 0.035, C.hi))
end
function WEAR.epaulettes(a, sh)
  a(R(0.5 - sh - 0.05, 0.3, 0.1, 0.03, C.hi))
  a(R(0.5 + sh - 0.05, 0.3, 0.1, 0.03, C.hi))
end
function WEAR.cape(a, sh, hip, hem, look)
  a(P(look.capeInk or C.redTint, 0.5 - sh - 0.03, 0.3, 0.5 + sh + 0.03, 0.3, 0.5 + hip + 0.09, hem + 0.06, 0.5 - hip - 0.09, hem + 0.06))
end
function WEAR.shawl(a, sh, hip, hem, look)
  a(P(look.shawlInk or C.accent, 0.5 - sh - 0.04, 0.3, 0.5 + sh + 0.04, 0.3, 0.5 + sh + 0.02, 0.44, 0.5, 0.56, 0.5 - sh - 0.02, 0.44))
end
function WEAR.waistcoat(a, sh, hip, hem, look)
  a(P(look.vestInk or C.red, 0.5 - sh * 0.8, 0.31, 0.5 + sh * 0.8, 0.31, 0.5 + sh * 0.8, 0.6, 0.5, 0.65, 0.5 - sh * 0.8, 0.6))
  a(R(0.49, 0.31, 0.02, 0.33, C.bg))
  a(R(0.5, 0.45, sh * 0.8, 0.012, C.hi))
end
function WEAR.collar(a) a(P(C.tie, 0.42, 0.28, 0.58, 0.28, 0.66, 0.34, 0.5, 0.4, 0.34, 0.34)) end
function WEAR.patches(a, sh, hip)
  a(R(0.5 - sh * 0.6, 0.38, 0.06, 0.06, C.warn))
  a(R(0.5 + sh * 0.2, 0.5, 0.07, 0.05, C.ok))
  a(R(0.5 - hip * 0.5, 0.62, 0.06, 0.05, C.red))
end
function WEAR.badge(a, sh)
  a(R(0.5 - sh * 0.8, 0.4, 0.07, 0.05, C.text))
  a(R(0.5 - sh * 0.8 + 0.028, 0.405, 0.014, 0.04, C.red))
end
function WEAR.gown(a, sh, hip, hem) a(R(0.5 - hip * 0.9, 0.62, hip * 1.8, 0.015, C.line)) a(R(0.5 - hip, hem - 0.1, hip * 2, 0.015, C.line)) end
function WEAR.strap(a, sh)
  a(P(C.redTint, 0.5 - sh, 0.3, 0.5 - sh + 0.05, 0.3, 0.5 + sh, 0.6, 0.5 + sh - 0.05, 0.6))
  a(R(0.5 + sh - 0.08, 0.56, 0.18, 0.14, C.redTint))
  a(R(0.5 + sh - 0.08, 0.56, 0.18, 0.03, C.warn))
end
function WEAR.tags(a, sh)
  for i = 0, 2 do a(R(0.5 - sh + 0.02 + i * 0.09, 0.34, 0.05, 0.05, C.hi)) end
end

--- Things carried, at the hand at x, y. Behind ones are drawn before the body.
local CARRY = {}

-- A carried thing is half of a small person's outline, so a stick is as thick on a gnome as on anyone: this is set for each
-- person, and it's the share of the body that gives a stick the same width at every height.
local stick = 0.03

function CARRY.lantern(a, x, y)
  a(R(x - 0.003, y, 0.014, 0.05, C.line))
  a(R(x - 0.04, y + 0.05, 0.09, 0.02, C.bg))
  a(R(x - 0.035, y + 0.07, 0.08, 0.08, C.hi))
  a(R(x - 0.015, y + 0.09, 0.04, 0.04, C.text))
  a(R(x - 0.04, y + 0.15, 0.09, 0.02, C.bg))
end
function CARRY.greenlamp(a, x, y)
  a(R(x - 0.05, y, 0.1, 0.13, C.warn))
  a(R(x - 0.05, y + 0.05, 0.1, 0.03, C.ok))
  a(R(x - 0.06, y - 0.02, 0.12, 0.02, C.bg))
end
function CARRY.pick(a, x, y)
  a(P(C.redTint, x - stick / 2, y + 0.08, x + stick / 2, y + 0.08, x - 0.1, y - 0.44, x - 0.1 - stick, y - 0.44))
  a(P(C.line, x - 0.3, y - 0.34, x - 0.11, y - 0.47, x + 0.08, y - 0.44, x - 0.11, y - 0.43))
end
function CARRY.basket(a, x, y)
  a(P(C.redTint, x - 0.03, y + 0.02, x + 0.03, y + 0.02, x + 0.1, y + 0.08, x + 0.09, y + 0.09, x, y + 0.04, x - 0.09, y + 0.09, x - 0.1, y + 0.08))
  a(P(C.warn, x - 0.11, y + 0.08, x + 0.11, y + 0.08, x + 0.08, y + 0.2, x - 0.08, y + 0.2))
  a(R(x - 0.1, y + 0.12, 0.2, 0.012, C.redTint))
end
function CARRY.laundry(a, x, y)
  CARRY.basket(a, x, y)
  a(E(x - 0.04, y + 0.07, 0.05, 0.035, C.text))
  a(E(x + 0.05, y + 0.06, 0.05, 0.04, C.text))
end
function CARRY.cane(a, x, y)
  a(R(x - stick / 2, y, stick, 1 - y, C.redTint))
  a(R(x - 0.04, y - 0.015, 0.06, 0.02, C.hi))
end
function CARRY.ledger(a, _, y, sh)
  a(R(0.5 - sh - 0.03, y - 0.26, sh * 2 + 0.06, 0.3, C.redTint))
  a(R(0.5 - sh - 0.01, y - 0.25, 0.02, 0.28, C.hi))
  a(R(0.5 - sh * 0.5, y - 0.2, sh, 0.05, C.text))
end
function CARRY.mug(a, x, y)
  a(R(x - 0.04, y - 0.1, 0.08, 0.1, C.hi))
  a(R(x - 0.045, y - 0.115, 0.09, 0.025, C.text))
  a(R(x + 0.04, y - 0.08, 0.02, 0.05, C.hi))
end
function CARRY.ladle(a, x, y)
  a(R(x - 0.008, y - 0.34, 0.018, 0.36, C.redTint))
  a(E(x, y - 0.36, 0.05, 0.04, C.line))
end
function CARRY.pole(a, x)
  a(R(x + 0.02, 0.0, stick, 1, C.redTint))
  a(R(x - 0.06, 0.02, 0.11, 0.018, C.line))
  a(R(x - 0.07, 0.04, 0.05, 0.06, C.hi))
end
function CARRY.spear(a, x)
  a(R(x, 0.02, stick, 0.96, C.redTint))
  a(P(C.text, x + 0.01, -0.1, x - 0.02, 0.03, x + 0.04, 0.03))
end
function CARRY.broom(a, x)
  a(R(x, -0.1, stick, 0.95, C.warn))
  a(P(C.hi, x - 0.02, 0.8, x + 0.04, 0.8, x + 0.15, 1, x - 0.13, 1))
  a(R(x - 0.03, 0.8, 0.08, 0.02, C.redTint))
end
function CARRY.bucket(a, x, y)
  a(P(C.line, x - 0.08, y + 0.06, x + 0.08, y + 0.06, x + 0.06, y + 0.22, x - 0.06, y + 0.22))
  a(R(x - 0.075, y + 0.06, 0.15, 0.03, C.blue))
  a(P(C.tie, x - 0.08, y + 0.06, x - 0.06, y + 0.06, x, y - 0.01, x + 0.06, y + 0.06, x + 0.08, y + 0.06, x, y - 0.03))
end
function CARRY.hammer(a, x, y)
  a(R(x - 0.012, y - 0.32, 0.024, 0.36, C.redTint))
  a(R(x - 0.11, y - 0.42, 0.22, 0.13, C.line))
  a(R(x - 0.11, y - 0.42, 0.22, 0.03, C.text))
end
function CARRY.shovel(a, x)
  a(R(x, 0.14, stick, 0.66, C.redTint))
  a(R(x - 0.04, 0.12, 0.1, 0.02, C.redTint))
  a(P(C.line, x - 0.06, 0.78, x + 0.08, 0.78, x + 0.08, 0.95, x + 0.01, 1, x - 0.06, 0.95))
end
function CARRY.board(a, _, y, sh)
  a(R(0.5 - sh - 0.08, y - 0.26, sh * 2 + 0.16, 0.26, C.redTint))
  for i = 0, 3 do
    a(R(0.5 - sh - 0.05 + i * (sh * 2 + 0.06) / 4, y - 0.23, 0.04, 0.05, C.text))
    a(R(0.5 - sh - 0.05 + i * (sh * 2 + 0.06) / 4, y - 0.13, 0.04, 0.05, C.hi))
  end
end
function CARRY.clipboard(a, _, y)
  a(R(0.53, y - 0.2, 0.18, 0.22, C.redTint))
  a(R(0.55, y - 0.18, 0.14, 0.19, C.text))
  a(R(0.59, y - 0.215, 0.06, 0.03, C.line))
end
function CARRY.letter(a, _, y)
  a(R(0.44, y - 0.16, 0.14, 0.1, C.text))
  a(P(C.line, 0.44, y - 0.16, 0.58, y - 0.16, 0.51, y - 0.1))
end
function CARRY.list(a, x, y)
  a(R(x - 0.05, y - 0.02, 0.1, 0.42, C.text))
  for i = 1, 6 do a(R(x - 0.03, y + i * 0.055, 0.06, 0.012, C.tie)) end
end
function CARRY.scroll(a, x, y)
  a(R(x - 0.06, y - 0.02, 0.12, 1.3 - y, C.text))
  a(R(x - 0.08, y - 0.05, 0.16, 0.05, C.line))
  for i = 1, 5 do a(R(x - 0.04, y + i * 0.09, 0.08, 0.014, C.tie)) end
end
function CARRY.keys(a, x, y)
  a(E(x, y + 0.06, 0.05, 0.05, C.hi))
  a(E(x, y + 0.06, 0.028, 0.028, C.bg))
  a(R(x - 0.01, y + 0.1, 0.02, 0.1, C.hi))
  a(R(x + 0.01, y + 0.16, 0.04, 0.02, C.hi))
end
function CARRY.boots(a, x, y)
  a(R(x - 0.05, y, 0.1, 0.16, C.redTint))
  a(R(x - 0.05, y + 0.14, 0.15, 0.06, C.redTint))
  a(R(x - 0.2, y + 0.04, 0.1, 0.14, C.warn))
  a(R(x - 0.2, y + 0.16, 0.15, 0.05, C.warn))
end
function CARRY.pillow(a, x, y) a(E(x + 0.02, y + 0.02, 0.1, 0.075, C.text)) a(E(x + 0.02, y + 0.03, 0.07, 0.04, C.line)) end
function CARRY.doll(a, x, y)
  a(E(x, y + 0.02, 0.03, 0.03, C.text))
  a(R(x - 0.03, y + 0.05, 0.06, 0.09, C.red))
  a(R(x - 0.03, y + 0.14, 0.015, 0.05, C.text))
end
function CARRY.stone(a, x, y) a(E(x, y + 0.03, 0.05, 0.04, C.line)) a(E(x - 0.01, y + 0.015, 0.02, 0.012, C.text)) end
function CARRY.tube(a, x, y)
  a(P(C.hi, x, y, x + 0.03, y, x + 0.03, 1, x, 1))
  a(P(C.hi, x, y + 0.02, x - 0.2, 0.25, x - 0.2, 0.21, x, y))
  a(P(C.warn, x - 0.27, 0.16, x - 0.27, 0.32, x - 0.17, 0.26, x - 0.17, 0.2))
end
function CARRY.cage(a, x, y)
  a(R(x - 0.002, y, 0.012, 0.05, C.line))
  a(E(x, y + 0.08, 0.1, 0.05, C.hi))
  a(E(x, y + 0.09, 0.085, 0.045, C.bg))
  a(R(x - 0.09, y + 0.09, 0.18, 0.15, C.bg))
  for i = 0, 3 do a(R(x - 0.09 + i * 0.056, y + 0.09, 0.012, 0.15, C.hi)) end
  a(R(x - 0.1, y + 0.235, 0.2, 0.02, C.hi))
end
function CARRY.wheel(a, x, y)
  a(E(x - 0.14, y - 0.06, 0.2, 0.2, C.line))
  a(E(x - 0.14, y - 0.06, 0.16, 0.16, C.bg))
  a(R(x - 0.33, y - 0.07, 0.38, 0.03, C.line))
  a(R(x - 0.155, y - 0.25, 0.03, 0.38, C.line))
  a(E(x - 0.14, y - 0.06, 0.04, 0.04, C.red))
end
function CARRY.engine(a)
  -- the Wakefulness Engine, worn: a gantry over the head, and a very small mallet
  a(R(0.2, -0.26, stick, 0.6, C.warn))
  a(R(0.8 - stick, -0.26, stick, 0.6, C.warn))
  a(R(0.2, -0.28, 0.6, stick, C.warn))
  a(R(0.49, -0.26, 0.02, 0.1, C.line))
  a(R(0.41, -0.18, 0.18, 0.09, C.red))
end
function CARRY.bowl(a, x, y)
  a(P(C.line, x - 0.1, y - 0.04, x + 0.1, y - 0.04, x + 0.06, y + 0.04, x - 0.06, y + 0.04))
  a(E(x, y - 0.04, 0.09, 0.015, C.info))
end
function CARRY.pen(a, x, y)
  a(P(C.text, x - 0.01, y, x + 0.01, y, x + 0.05, y - 0.16, x + 0.02, y - 0.16))
end
function CARRY.pie(a, x, y)
  a(P(C.warn, x - 0.11, y - 0.04, x + 0.11, y - 0.04, x + 0.09, y + 0.03, x - 0.09, y + 0.03))
  a(E(x, y - 0.04, 0.11, 0.05, C.hi))
  a(P(C.bg, x, y - 0.045, x + 0.11, y - 0.07, x + 0.09, y - 0.02))
end
function CARRY.goose(a, x, y)
  a(E(x + 0.03, y + 0.05, 0.1, 0.07, C.text))
  a(P(C.text, x + 0.08, y + 0.03, x + 0.12, y + 0.03, x + 0.13, y - 0.14, x + 0.09, y - 0.14))
  a(E(x + 0.115, y - 0.15, 0.03, 0.03, C.text))
  a(P(C.warn, x + 0.14, y - 0.17, x + 0.2, y - 0.14, x + 0.14, y - 0.13))
end
function CARRY.book(a, _, y)
  a(R(0.42, y - 0.2, 0.18, 0.15, C.accent))
  a(R(0.44, y - 0.185, 0.14, 0.12, C.text))
  a(R(0.505, y - 0.2, 0.012, 0.15, C.bg))
end
function CARRY.hen(a, x, y)
  a(E(x, y - 0.04, 0.09, 0.075, C.warn))
  a(E(x + 0.075, y - 0.11, 0.04, 0.04, C.warn))
  a(R(x + 0.06, y - 0.17, 0.05, 0.03, C.red))
  a(P(C.hi, x + 0.11, y - 0.12, x + 0.16, y - 0.105, x + 0.11, y - 0.09))
  a(P(C.redTint, x - 0.09, y - 0.04, x - 0.15, y - 0.11, x - 0.05, y - 0.09))
end
function CARRY.feather(a, x, y) a(P(C.text, x - 0.015, y, x + 0.015, y, x + 0.03, y - 0.14, x, y - 0.17, x - 0.03, y - 0.14)) end
function CARRY.chalk(a, x, y)
  a(R(x - 0.05, y - 0.08, 0.1, 0.09, C.redTint))
  a(R(x - 0.015, y - 0.18, 0.03, 0.12, C.text))
  a(R(x + 0.03, y - 0.14, 0.03, 0.08, C.text))
end
function CARRY.tray(a, _, y, sh)
  a(R(0.5 - sh - 0.14, y - 0.2, sh * 2 + 0.28, 0.03, C.warn))
  a(R(0.5 - sh - 0.1, y - 0.28, 0.06, 0.08, C.red))
  a(R(0.5 - sh * 0.3, y - 0.27, 0.06, 0.07, C.info))
  a(R(0.5 + sh * 0.6, y - 0.29, 0.06, 0.09, C.ok))
  a(R(0.5 - sh - 0.14, y - 0.17, 0.02, 0.14, C.line))
  a(R(0.5 + sh + 0.12, y - 0.17, 0.02, 0.14, C.line))
end
function CARRY.drawer(a, _, y, sh)
  a(R(0.5 - sh - 0.1, y - 0.2, sh * 2 + 0.2, 0.17, C.redTint))
  a(R(0.5 - sh - 0.08, y - 0.24, sh * 2 + 0.16, 0.06, C.text))
  a(R(0.5 - sh - 0.03, y - 0.26, sh * 2 + 0.02, 0.05, C.line))
  a(R(0.46, y - 0.12, 0.08, 0.02, C.hi))
end
function CARRY.kettle(a, x, y)
  a(E(x + 0.01, y + 0.08, 0.1, 0.09, C.line))
  a(R(x - 0.09, y + 0.14, 0.2, 0.04, C.tie))
  a(P(C.line, x + 0.09, y + 0.07, x + 0.18, y + 0.0, x + 0.19, y + 0.02, x + 0.1, y + 0.13))
  a(E(x + 0.2, y - 0.04, 0.03, 0.03, C.text))
  a(E(x + 0.17, y - 0.09, 0.022, 0.022, C.text))
end
function CARRY.bell(a, x, y)
  a(R(x - 0.012, y - 0.1, 0.024, 0.1, C.redTint))
  a(P(C.hi, x - 0.04, y - 0.24, x + 0.04, y - 0.24, x + 0.13, y - 0.06, x - 0.13, y - 0.06))
  a(R(x - 0.13, y - 0.07, 0.26, 0.018, C.warn))
end
function CARRY.knitting(a, x, y)
  a(R(0.42, y - 0.12, 0.16, 1.1 - y, C.blue))
  for i = 1, 5 do a(R(0.42, y - 0.12 + i * 0.09, 0.16, 0.014, C.text)) end
  a(P(C.line, 0.34, y - 0.18, 0.36, y - 0.18, 0.56, y - 0.06, 0.54, y - 0.05))
  a(P(C.line, 0.64, y - 0.18, 0.66, y - 0.18, 0.46, y - 0.05, 0.44, y - 0.06))
  a(E(x, y + 0.04, 0.05, 0.05, C.blue))
end
function CARRY.prop(a, x)
  a(R(x - 0.03, -0.18, 0.07, 1.18, C.warn))
  a(R(x + 0.02, -0.18, 0.015, 1.18, C.redTint))
  a(R(x - 0.2, -0.2, 0.42, 0.06, C.warn))
end
function CARRY.cards(a, x, y)
  a(P(C.text, x - 0.08, y - 0.02, x - 0.04, y - 0.1, x, y - 0.1, x + 0.0, y))
  a(P(C.text, x - 0.02, y, x, y - 0.11, x + 0.05, y - 0.1, x + 0.06, y))
  a(R(x - 0.05, y - 0.08, 0.02, 0.02, C.red))
end
function CARRY.mask(a, x, y)
  a(E(x, y - 0.02, 0.06, 0.06, C.tie))
  a(P(C.line, x - 0.04, y - 0.03, x + 0.05, y - 0.03, x + 0.14, y + 0.06, x, y + 0.04))
  a(E(x - 0.015, y - 0.03, 0.018, 0.018, C.info))
end
function CARRY.crutch(a, x, y)
  a(R(x, 0.32, stick, 0.68, C.warn))
  a(R(x - 0.05, 0.31, 0.12, 0.025, C.redTint))
  a(R(x - 0.02, y, 0.05, 0.016, C.redTint))
end

-- Carried across the body or above the head: drawn on top of the arms.
local CARRY_FRONT = { ledger = true, board = true, clipboard = true, letter = true, tube = true, wheel = true, engine = true, pen = true, book = true, tray = true, drawer = true, knitting = true,
  feather = true, chalk = true, cards = true, mask = true }

--- Stands someone on the floor: shrinks them to tall, leans the top of them, and lifts them onto a box if they need one.
local function placed(list, look)
  local out = {}
  local tall, lean, lift = look.tall, look.lean, look.stand == "box" and 0.14 or 0
  local top = 1 - lift - tall
  local function sx(x, y) return 0.5 + (x - 0.5) * tall + lean * tall * (0.85 - y) end
  local function sy(y) return top + y * tall end
  for _, s in ipairs(list) do
    if s.kind == "e" then
      out[#out + 1] = E(sx(s.cx, s.cy), sy(s.cy), s.rx * tall, s.ry * tall, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(sx(s.x, s.y + s.h / 2), sy(s.y), s.w * tall, s.h * tall, s.color)
    else
      local pts = {}
      for i = 1, #s.points, 2 do pts[i], pts[i + 1] = sx(s.points[i], s.points[i + 1]), sy(s.points[i + 1]) end
      out[#out + 1] = P(s.color, unpack(pts))
    end
  end
  return out
end

--- Fills a description in from its kind and build, once.
local function settle(look)
  if look.settled then return look end
  local kind = LOOK_KIND[look.kind] or LOOK_KIND.human
  look.settled = true
  look.rx, look.ry = kind[1], kind[2]
  look.tall = look.tall or kind.tall
  look.skin = look.skin or kind.skin
  look.back = look.back or kind.back
  look.eyes = look.eyes or kind.eyes or "normal"
  look.mouth = look.mouth or kind.mouth or "line"
  look.nose = look.nose or kind.nose or "small"
  look.ears = look.ears or kind.ears
  look.build = look.build or "normal"
  look.lean = look.lean or (look.build == "hunched" and 0.2 or 0)
  look.shade = SKIN_SHADE[look.skin] or C.tie
  look.coat = look.coat or C.tie
  look.trim = look.trim or C.panel
  look.legs = look.legs or C.bg
  look.cut = look.cut or "coat"
  return look
end

--- The upper shapes, which the sprite and the portrait share: head, hair, beard and hat.
local function headParts(look)
  local under, over = {}, {}
  local addShape = function(s) under[#under + 1] = s end
  local b = function(s) over[#over + 1] = s end
  local hx, hy, rx, ry = 0.5 + (look.tilt or 0), 0.17, look.rx, look.ry
  addShape(R(hx - 0.05, hy + ry - 0.02, 0.1, 0.07, look.shade))
  if look.ears == "long" then
    addShape(P(look.skin, hx - rx * 0.9, hy - 0.01, hx - rx * 2.1, hy - 0.08, hx - rx * 0.9, hy + 0.05))
    addShape(P(look.skin, hx + rx * 0.9, hy - 0.01, hx + rx * 2.1, hy - 0.08, hx + rx * 0.9, hy + 0.05))
  elseif look.ears == "round" then
    addShape(E(hx - rx * 1.05, hy + 0.01, 0.03, 0.04, look.skin))
    addShape(E(hx + rx * 1.05, hy + 0.01, 0.03, 0.04, look.skin))
  end
  if look.kind == "owlin" then
    addShape(P(look.skin, hx - rx, hy - 0.05, hx - rx * 1.2, hy - ry * 1.7, hx - rx * 0.2, hy - ry * 0.9))
    addShape(P(look.skin, hx + rx, hy - 0.05, hx + rx * 1.2, hy - ry * 1.7, hx + rx * 0.2, hy - ry * 0.9))
  end
  addShape(E(hx, hy, rx, ry, look.skin))
  if look.kind == "frog" then
    addShape(E(hx - rx * 0.62, hy - ry * 0.85, 0.075, 0.07, look.skin))
    addShape(E(hx + rx * 0.62, hy - ry * 0.85, 0.075, 0.07, look.skin))
    b(E(hx - rx * 0.62, hy - ry * 0.85, 0.05, 0.05, C.hi))
    b(E(hx + rx * 0.62, hy - ry * 0.85, 0.05, 0.05, C.hi))
    b(R(hx - rx * 0.62 - 0.04, hy - ry * 0.85, 0.08, 0.018, C.bg))
    b(R(hx + rx * 0.62 - 0.04, hy - ry * 0.85, 0.08, 0.018, C.bg))
    b(R(hx - rx * 0.8, hy + 0.035, rx * 1.6, 0.02, C.bg))
    b(E(hx, hy + 0.12, rx * 0.7, 0.05, C.soft))
  elseif look.kind == "owlin" then
    b(E(hx - rx * 0.45, hy - 0.01, 0.06, 0.065, C.text))
    b(E(hx + rx * 0.45, hy - 0.01, 0.06, 0.065, C.text))
    b(E(hx - rx * 0.45, hy - 0.01, 0.03, 0.035, C.bg))
    b(E(hx + rx * 0.45, hy - 0.01, 0.03, 0.035, C.bg))
    b(P(C.hi, hx - 0.03, hy + 0.03, hx + 0.03, hy + 0.03, hx, hy + 0.1))
  end
  if look.blight then
    b(E(hx + rx * 0.7, hy - ry * 0.6, 0.075, 0.065, C.soft))
    b(E(hx + rx * 0.95, hy + 0.03, 0.055, 0.075, C.ok))
    b(E(hx + rx * 0.6, hy + ry * 0.7, 0.04, 0.04, C.soft))
  end
  hairShapes(b, look, hx, hy, rx, ry)
  beardShapes(b, look, hx, hy, rx, ry)
  if look.beak then
    -- the Clinic's mask, turned addShape little aside, so the beak breaks the outline of the head
    b(E(hx, hy, rx * 1.02, ry * 1.02, look.maskInk or C.line))
    b(P(look.beakInk or C.text, hx - 0.03, hy - 0.01, hx + rx * 0.8, hy - 0.04, hx + rx + look.beak, hy + 0.1, hx + rx * 0.5, hy + 0.1))
    b(P(C.tie, hx - 0.03, hy + 0.04, hx + rx * 0.5, hy + 0.1, hx + rx + look.beak, hy + 0.1))
  end
  local hat = HAT[look.hat]
  if hat then
    local scale = look.hatSmall or 1
    hat(b, hx + (look.hatShift or 0), hy, rx * scale, ry, look.hatInk or C.bg, look.hatTrim or C.line)
  end
  return under, over
end

--- A person standing, before they're stood on the floor. Back to front: what's behind them, legs, body, arms, head, what's in
-- front. A portrait is this same body zoomed in, with its eyes and mouth put in by hand, so bare leaves those out.
local function standingBody(look, bare)
  settle(look)
  local list = {}
  local addShape = function(s) list[#list + 1] = s end
  local build = LOOK_BUILD[look.build]
  local sh, hip = build[1], build[2]
  local hem = LOOK_HEM[look.cut] or 0.84
  local handX, handY = 0.5 + sh + 0.075, 0.62
  local carry = CARRY[look.carry]
  local front = CARRY_FRONT[look.carry]
  stick = 0.036 / look.tall
  if look.wear then
    for _, name in ipairs(look.wear) do
      if name == "cape" then WEAR.cape(addShape, sh, hip, hem, look) end
    end
  end
  if carry and not front then carry(addShape, handX, handY, sh) end
  if look.cut ~= "robe" then
    addShape(R(0.5 - hip * 0.8, hem - 0.02, hip * 0.7, 0.96 - hem + 0.02, look.legs))
    addShape(R(0.5 + hip * 0.1, hem - 0.02, hip * 0.7, 0.96 - hem + 0.02, look.legs))
    addShape(R(0.5 - hip * 0.85 - 0.02, 0.95, hip * 0.75 + 0.03, 0.05, look.oneShoe and look.skin or C.redTint))
    addShape(R(0.5 + hip * 0.1, 0.95, hip * 0.75 + 0.03, 0.05, C.redTint))
  end
  addShape(P(look.coat, 0.5 - sh, 0.3, 0.5 + sh, 0.3, 0.5 + hip, hem, 0.5 - hip, hem))
  addShape(P(look.trim, 0.47, 0.3, 0.53, 0.3, 0.52, hem, 0.48, hem))
  if look.wear then
    for _, name in ipairs(look.wear) do
      if name ~= "cape" then WEAR[name](addShape, sh, hip, hem, look) end
    end
  end
  for side = -1, 1, 2 do
    local x = 0.5 + side * (sh + 0.04)
    addShape(P(look.coat, 0.5 + side * sh * 0.9, 0.3, 0.5 + side * (sh + 0.075), 0.33, 0.5 + side * (sh + 0.11), 0.6, 0.5 + side * (sh + 0.04), 0.6, 0.5 + side * sh * 0.85, 0.42))
    addShape(E(x + side * 0.035, 0.625, 0.04, 0.04, look.skin))
  end
  local under, over = headParts(look)
  for _, s in ipairs(under) do addShape(s) end
  if look.kind ~= "frog" and look.kind ~= "owlin" then
    local hx, hy, rx = 0.5 + (look.tilt or 0), 0.17, look.rx
    if look.nose == "big" then addShape(E(hx, hy + 0.035, 0.05, 0.05, look.noseInk or look.shade)) end
    if not look.beak and not bare then
      local ink = look.eyes == "red" and C.red or look.eyes == "closed" and look.shade or C.bg
      local high = (look.eyes == "closed" or look.eyes == "narrow") and 0.022 or 0.055
      addShape(R(hx - rx * 0.62, hy - 0.04, 0.055, high, ink))
      addShape(R(hx + rx * 0.62 - 0.055, hy - 0.04, 0.055, high, ink))
      if look.mouth ~= "none" then addShape(R(hx - 0.05, hy + 0.075, 0.1, 0.02, C.bg)) end
    end
  end
  for _, s in ipairs(over) do addShape(s) end
  if look.beak then
    local hx, hy, rx = 0.5 + (look.tilt or 0), 0.17, look.rx
    addShape(E(hx - rx * 0.5, hy - 0.025, 0.04, 0.04, C.bg))
    addShape(E(hx + rx * 0.45, hy - 0.03, 0.04, 0.04, C.bg))
    addShape(E(hx - rx * 0.5, hy - 0.025, 0.026, 0.026, C.info))
    addShape(E(hx + rx * 0.45, hy - 0.03, 0.026, 0.026, C.info))
  end
  if carry and front then carry(addShape, handX, handY, sh) end
  return list
end

local function standingLook(look)
  local out = placed(standingBody(look), look)
  if look.stand == "box" then
    out[#out + 1] = R(0.28, 0.86, 0.44, 0.14, C.redTint)
    out[#out + 1] = R(0.28, 0.86, 0.44, 0.02, C.warn)
    out[#out + 1] = R(0.3, 0.92, 0.4, 0.012, C.bg)
  elseif look.stand == "stocks" then
    local tall = look.tall
    local y = 1 - tall + 0.31 * tall
    out[#out + 1] = R(0.16, y + 0.02, 0.05, 1 - y - 0.02, C.redTint)
    out[#out + 1] = R(0.79, y + 0.02, 0.05, 1 - y - 0.02, C.redTint)
    out[#out + 1] = R(0.06, y, 0.88, 0.09, C.warn)
    out[#out + 1] = R(0.06, y + 0.04, 0.88, 0.012, C.redTint)
    out[#out + 1] = E(0.26, y + 0.045, 0.035, 0.035, look.skin)
    out[#out + 1] = E(0.74, y + 0.045, 0.035, 0.035, look.skin)
  end
  return out
end

--- Someone lying down: sacking in the mine, addShape Clinic cot in the ward. Their hair and hat still say who it is.
local function lyingLook(look)
  settle(look)
  local list = {}
  local addShape = function(s) list[#list + 1] = s end
  if look.bed then
    addShape(R(0.04, 0.82, 0.03, 0.18, C.line))
    addShape(R(0.93, 0.82, 0.03, 0.18, C.line))
    addShape(R(0.0, 0.72, 1, 0.12, C.line))
    addShape(R(0.92, 0.4, 0.05, 0.42, C.line))
  else
    addShape(R(0.0, 0.88, 1, 0.12, look.sackInk or C.hiTint))
    addShape(R(0.0, 0.9, 1, 0.012, C.panel))
  end
  local ground = look.bed and 0.74 or 0.9
  if not look.empty then
    local big = look.size or 1
    addShape(P(look.coat, 0.08, ground, 0.7, ground, 0.72, ground - 0.28 * big, 0.36, ground - 0.33 * big, 0.12, ground - 0.2 * big))
    addShape(P(look.trim, 0.08, ground, 0.7, ground, 0.7, ground - 0.07, 0.08, ground - 0.04))
    if look.wear and look.wear[1] == "patches" then
      addShape(R(0.2, ground - 0.2, 0.09, 0.08, C.warn))
      addShape(R(0.42, ground - 0.24, 0.1, 0.09, C.ok))
    end
    local hx, hy, rx, ry = 0.8, ground - 0.17, look.rx * 1.05, look.ry * 1.25
    addShape(E(hx, hy, rx, ry, look.skin))
    addShape(R(hx - rx * 0.6, hy - 0.04, 0.06, 0.016, look.shade))
    addShape(R(hx + rx * 0.1, hy - 0.04, 0.06, 0.016, look.shade))
    if look.hair then addShape(P(look.hairInk or C.bg, hx - rx, hy, hx - rx * 0.7, hy - ry, hx + rx * 0.7, hy - ry, hx + rx, hy, hx + rx * 0.6, hy - ry * 0.55, hx - rx * 0.6, hy - ry * 0.55)) end
    if look.beard then addShape(E(hx, hy + ry * 0.75, rx * 0.9, ry * 0.6, look.beardInk or look.hairInk or C.bg)) end
    local hat = HAT[look.hat]
    if hat then hat(addShape, hx, hy, rx, ry, look.hatInk or C.bg, look.hatTrim or C.line) end
    addShape(R(0.58, ground - 0.13, 0.08, 0.03, look.skin))
    if look.thread then addShape(R(0.6, ground - 0.135, 0.02, 0.04, C.bg)) end
  else
    addShape(R(0.08, ground - 0.05, 0.84, 0.05, C.text))
    addShape(R(0.7, ground - 0.12, 0.2, 0.08, C.text))
  end
  local carry = CARRY[look.carry]
  if carry then carry(addShape, look.carryX or 0.14, look.carryY or (ground - 0.24), 0.1) end
  if look.beam then
    -- the prop that came down on Dunnock
    addShape(P(C.redTint, 0.02, 0.5, 0.08, 0.42, 0.68, 0.84, 0.6, 0.9))
    addShape(P(C.warn, 0.05, 0.46, 0.08, 0.42, 0.68, 0.84, 0.65, 0.86))
  end
  return list
end

--- The same shapes the other way round, so that one of addShape pair can face the other.
local function mirrored(list)
  local out = {}
  for _, s in ipairs(list) do
    if s.kind == "e" then
      out[#out + 1] = E(1 - s.cx, s.cy, s.rx, s.ry, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(1 - s.x - s.w, s.y, s.w, s.h, s.color)
    else
      local pts = {}
      for i, v in ipairs(s.points) do pts[i] = i % 2 == 1 and 1 - v or v end
      out[#out + 1] = P(s.color, unpack(pts))
    end
  end
  return out
end

local function lookShapes(look)
  local list = look.pose == "lying" and lyingLook(look) or standingLook(look)
  return look.flip and mirrored(list) or list
end

local function derive(base, over)
  local look = {}
  for k, v in pairs(base) do look[k] = v end
  for k, v in pairs(over) do look[k] = v end
  if over.carry == "none" then look.carry = nil end
  return look
end

--- Lying down as themselves.
local function asleep(base, over)
  local look = derive(base, over)
  look.pose = "lying"
  return look
end

-- ---- Scythebreak

local NAN = { kind = "old", tall = 0.74, build = "stout", cut = "dress", coat = C.redTint, trim = C.redTint, hair = "bun", hairInk = C.text, wear = { "apron" },
  carry = "ladle", mouth = "smile", back = C.hiTint }
local WICK = { kind = "human", tall = 0.98, build = "thin", coat = C.blueTint, trim = C.bg, legs = C.bg, hat = "cap", hatInk = C.tie, hatTrim = C.bg, hair = "short", hairInk = C.line,
  beard = "whiskers", beardInk = C.line, carry = "pole", eyes = "wide", mouth = "line", back = C.blueTint }
local KID = { kind = "child", tall = 0.46, build = "thin", cut = "dress", coat = C.tie, trim = C.line, hair = "pigtails", hairInk = C.redTint, beak = 0.03, maskInk = C.warn, beakInk = C.text,
  carry = "doll", back = C.tie }
local CLERK = { kind = "human", tall = 0.84, build = "hunched", coat = C.panel, trim = C.bg, hair = "short", hairInk = C.tie, hat = "visor", hatInk = C.ok, hatTrim = C.bg, eyes = "specs",
  mouth = "frown", carry = "ledger", back = C.panel }
local GOSSIP = { kind = "human", tall = 0.78, build = "stout", cut = "dress", coat = C.hiTint, trim = C.hiTint, hair = "curls", hairInk = C.redTint, skin = C.warn, wear = { "shawl" },
  carry = "basket", mouth = "open", eyes = "wide", back = C.redTint }
local SERGEANT = { kind = "human", tall = 0.9, build = "stout", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.text, hatTrim = C.red, hair = "short", hairInk = C.line, beard = "whiskers", beardInk = C.text,
  wear = { "collar", "belt", "badge" }, carry = "pie", eyes = "narrow", mouth = "smile", back = C.tie } -- nineteen years on the wall, boots polished, mask off: there's addShape pie
local SEXTON = { kind = "old", tall = 0.92, build = "hunched", lean = 0.12, coat = C.bg, trim = C.panel, cut = "coat", hat = "wide", hatInk = C.bg, hatTrim = C.tie, hair = "short", hairInk = C.text, beard = "stubble",
  skin = C.line, carry = "shovel", mouth = "frown", eyes = "tired", back = C.hiTint }
local HANLEY = { kind = "child", tall = 0.52, cut = "tunic", coat = C.red, trim = C.redTint, legs = C.blueTint, hair = "wild", hairInk = C.redTint, hat = "cap", hatInk = C.hi, hatTrim = C.warn, carry = "goose", mouth = "smile", back = C.blueTint }
local LIOTH = { kind = "half-elf", tall = 0.92, build = "thin", cut = "robe", coat = C.accent, trim = C.blueTint, hair = "plaits", hairInk = C.line, skin = C.text, carry = "book", eyes = "narrow", mouth = "line", back = C.blueTint }
local HENWIFE = { kind = "old", tall = 0.76, build = "stout", cut = "dress", coat = C.blueTint, trim = C.tie, hat = "scarf", hatInk = C.ok, hatTrim = C.hiTint, hair = "tufts", hairInk = C.line, carry = "hen", mouth = "smile", back = C.hiTint }
local SATCHEL = { kind = "clinic", tall = 0.68, build = "thin", cut = "tunic", coat = C.tie, trim = C.line, legs = C.panel, hat = "bowler", hatInk = C.tie, hatTrim = C.bg, beak = 0.03, maskInk = C.tie, beakInk = C.line,
  wear = { "strap" }, back = C.tie }

local LOOKS = {
  nan = NAN, q_nan = derive(NAN, { carry = "none", mouth = "line", eyes = "tired" }),
  wick = WICK, wick_changed = derive(WICK, { skin = C.line, blight = true, tall = 0.9, build = "hunched", lean = 0.28, tilt = 0.05, eyes = "red", mouth = "open", hairInk = C.tie, beardInk = C.tie }),
  kid = KID, q_kid = derive(KID, { beak = false, carry = "none", eyes = "wide", mouth = "line" }),
  clerk = CLERK, q_clerk = derive(CLERK, { carry = "pen", build = "thin", lean = 0.06, mouth = "open" }), -- they didn't let him bring the Book
  gossip = GOSSIP, q_gossip = derive(GOSSIP, { carry = "none", mouth = "frown", eyes = "tired" }),
  widow = { kind = "human", tall = 0.94, build = "stout", cut = "dress", coat = C.bg, trim = C.panel, hat = "veil", hatInk = C.bg, hatTrim = C.tie, hair = "long", hairInk = C.bg, skin = C.text,
    eyes = "tired", mouth = "frown", carry = "letter", back = C.tie },
  tobin = { kind = "human", tall = 0.8, build = "thin", cut = "dress", coat = C.text, trim = C.line, skin = C.text, wear = { "gown" }, eyes = "tired", mouth = "open", nose = "small", back = C.blueTint },
  sexton = SEXTON, q_sexton = derive(SEXTON, { carry = "none", lean = 0, build = "thin" }), -- stand up straight, child
  hanley = HANLEY, q_hanley = derive(HANLEY, { carry = "none", mouth = "line", eyes = "tired" }),
  lioth = LIOTH, q_lioth = derive(LIOTH, { carry = "none", eyes = "shifty" }),
  henwife = HENWIFE, q_henwife = derive(HENWIFE, { carry = "feather", mouth = "line" }),

  -- the Clinic: beaks and grey for all of them, and rank in the height of the hat and the length of the beak
  corner = { kind = "clinic", tall = 0.92, build = "broad", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.line, hatTrim = C.red, beak = 0.08, wear = { "badge", "belt" }, carry = "spear" },
  doorman = { kind = "clinic", tall = 0.97, build = "stout", coat = C.tie, trim = C.bg, hat = "bowler", hatInk = C.panel, hatTrim = C.line, beak = 0.11, wear = { "badge" }, carry = "keys" },
  watch = { kind = "human", tall = 0.87, build = "thin", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.line, hatTrim = C.line, hatSmall = 1.25, skin = C.warn, eyes = "wide",
    mouth = "smile", wear = { "collar", "badge" }, carry = "lantern", back = C.redTint }, -- the mask's down, for the bread
  sergeant = SERGEANT, q_sergeant = derive(SERGEANT, { carry = "none", mouth = "line", eyes = "tired" }),
  gateman = { kind = "clinic", tall = 0.84, build = "normal", cut = "tunic", coat = C.line, trim = C.text, legs = C.tie, hat = "cap", hatInk = C.text, hatTrim = C.line, beak = 0.05, carry = "clipboard" },
  chalker = { kind = "clinic", tall = 0.8, build = "stout", cut = "tunic", coat = C.line, trim = C.tie, legs = C.tie, hat = "visor", hatInk = C.tie, hatTrim = C.text, beak = 0.05, carry = "chalk" },
  satchel = SATCHEL, q_satchel = derive(SATCHEL, { carry = "clipboard" }), n_satchel = derive(SATCHEL, { carry = "lantern" }),
  bascombe = { kind = "clinic", tall = 0.97, build = "hunched", lean = 0.16, coat = C.tie, trim = C.bg, hair = "short", hairInk = C.tie, beak = 0.07, maskInk = C.tie, beakInk = C.line, wear = { "badge" }, carry = "drawer" }, -- stooped: the doors here come up to his chest
  handler_big = { kind = "clinic", tall = 0.98, build = "broad", cut = "tunic", coat = C.panel, trim = C.redTint, legs = C.tie, beak = 0.1, maskInk = C.tie, beakInk = C.tie, carry = "cards", back = C.panel },
  handler_small = { kind = "human", tall = 0.88, build = "stout", cut = "tunic", coat = C.panel, trim = C.redTint, legs = C.tie, hair = "short", hairInk = C.redTint, beard = "stubble", carry = "mask", eyes = "tired", mouth = "frown", back = C.panel },
  captain = { kind = "clinic", tall = 0.96, build = "broad", coat = C.tie, trim = C.hi, hat = "peaked", hatInk = C.bg, hatTrim = C.hi, beak = 0.06, beakInk = C.hi, maskInk = C.text,
    wear = { "cape", "epaulettes", "badge" }, capeInk = C.red, carry = "cane", back = C.panel },
  doctor = { kind = "clinic", tall = 0.94, build = "thin", cut = "robe", coat = C.text, trim = C.line, hat = "beakhat", hatInk = C.bg, hatTrim = C.line, beak = 0.2, maskInk = C.text,
    carry = "clipboard", back = C.redTint },

  -- the ward, that night. Every patient gets addShape bed.
  w_nan = asleep(NAN, { bed = true, coat = C.text, trim = C.line, carry = "none" }),
  w_kid = asleep(KID, { bed = true, coat = C.line, trim = C.text, carry = "doll", carryX = 0.62, carryY = 0.46, beak = false, size = 0.75 }),
  w_clerk = asleep(CLERK, { bed = true, coat = C.text, trim = C.tie, carry = "none", hat = false, eyes = "closed" }),
  w_watch = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.text, hair = "short", hairInk = C.redTint, thread = false, carry = "stone", carryX = 0.6, carryY = 0.56 },
  w_bed = { kind = "human", pose = "lying", bed = true, empty = true },
  w_sergeant = asleep(SERGEANT, { bed = true, coat = C.text, trim = C.line, carry = "none", hat = false, flip = true }),
  w_sexton = asleep(SEXTON, { bed = true, coat = C.line, trim = C.text, carry = "none", hat = false, size = 0.8 }),
  w_hanley = asleep(HANLEY, { bed = true, coat = C.text, trim = C.tie, carry = "none", hat = false, size = 0.7, flip = true }),
  w_lioth = asleep(LIOTH, { bed = true, coat = C.line, trim = C.tie, carry = "none", size = 0.85 }),
  w_henwife = asleep(HENWIFE, { bed = true, coat = C.text, trim = C.warn, carry = "feather", carryX = 0.5, carryY = 0.5, hat = false, flip = true }),

  -- ---- Orrenshire

  innkeeper = { kind = "half-elf", tall = 0.97, build = "broad", cut = "dress", coat = C.redTint, trim = C.red, hair = "long", hairInk = C.hi, hat = "scarf", hatInk = C.red, hatTrim = C.hi,
    wear = { "apron" }, carry = "mug", mouth = "smile", back = C.redTint },
  dozer = { kind = "gnome", tall = 0.56, cut = "dress", coat = C.blueTint, trim = C.text, hat = "nightcap", hatInk = C.blue, hatTrim = C.text, beard = "stubble", carry = "pillow", eyes = "closed",
    mouth = "open", oneShoe = true, back = C.bg },
  smith = { kind = "gnome", tall = 0.62, build = "broad", cut = "tunic", coat = C.tie, trim = C.panel, skin = C.warn, beard = "bolster", beardInk = C.red, hat = "goggles", hatInk = C.info, hatTrim = C.bg,
    hair = "tufts", hairInk = C.red, wear = { "apron" }, apronInk = C.redTint, carry = "hammer", mouth = "line", back = C.panel },
  apprentice = { kind = "gnome", tall = 0.44, build = "thin", cut = "tunic", coat = C.warn, trim = C.redTint, hat = "cap", hatInk = C.redTint, hatTrim = C.bg, hair = "wild", hairInk = C.bg, beard = "stubble",
    carry = "boots", eyes = "tired", back = C.redTint },
  mayor = { kind = "gnome", tall = 0.6, build = "stout", coat = C.accent, trim = C.bg, hat = "stovepipe", hatInk = C.bg, hatTrim = C.hi, hair = "curls", hairInk = C.text, beard = "none", wear = { "chain" },
    carry = "scroll", stand = "box", eyes = "tired", mouth = "open", back = C.hiTint },
  chair = { kind = "gnome", tall = 0.53, cut = "tunic", coat = C.red, trim = C.text, hat = "bandage", hatInk = C.text, hatTrim = C.line, beard = "moustache", beardInk = C.bg, carry = "engine", eyes = "wide",
    mouth = "teeth", back = C.hiTint },
  ledger = { kind = "gnome", tall = 0.59, build = "thin", cut = "coat", coat = C.bg, trim = C.line, hat = "bowler", hatInk = C.bg, hatTrim = C.text, hair = "tufts", hairInk = C.text, beard = "goatee", beardInk = C.text,
    eyes = "specs", carry = "ledger", mark = "ink", back = C.blueTint },
  well = { kind = "gnome", tall = 0.57, cut = "tunic", coat = C.hiTint, trim = C.warn, hat = "straw", hatInk = C.hi, hatTrim = C.warn, beard = "forked", beardInk = C.text, carry = "bucket", back = C.blueTint },
  frog = { kind = "frog", tall = 0.88, build = "stout", coat = C.bg, trim = C.ok, hat = "tophat", hatSmall = 0.42, hatShift = 0.05, hatInk = C.accent, hatTrim = C.hi, wear = { "waistcoat" }, vestInk = C.accent,
    stand = "stocks", back = C.panel },
  stocks = { kind = "gnome", tall = 0.58, build = "broad", cut = "tunic", coat = C.blueTint, trim = C.hi, skin = C.warn, beard = "whiskers", beardInk = C.bg, carry = "keys", eyes = "wide", mouth = "frown", wear = { "belt" },
    back = C.tie }, -- bare-headed: he has lost his hat
  shopkeep = { kind = "gnome", tall = 0.49, build = "stout", cut = "tunic", coat = C.ok, trim = C.hiTint, hat = "mushroom", hatInk = C.red, hatTrim = C.text, beard = "goatee", beardInk = C.bg, wear = { "apron" },
    carry = "mug", eyes = "narrow", mouth = "smile", back = C.hiTint },
  pip = { kind = "child", tall = 0.36, build = "thin", cut = "tunic", coat = C.warn, trim = C.redTint, hat = "helmet", hatInk = C.tie, hatTrim = C.hi, hatSmall = 1.25, nose = "big", ears = "round", carry = "stone",
    eyes = "wide", mouth = "line", back = C.blueTint },
  linen = { kind = "gnome", tall = 0.49, cut = "dress", coat = C.line, trim = C.text, hair = "plaits", hairInk = C.bg, hat = "scarf", hatInk = C.text, hatTrim = C.bg, carry = "laundry", eyes = "shifty", back = C.tie },
  sweeper = { kind = "gnome", tall = 0.5, cut = "tunic", coat = C.hiTint, trim = C.bg, hat = "floppy", hatInk = C.info, hatTrim = C.blueTint, beard = "chops", beardInk = C.text, carry = "broom", eyes = "tired", back = C.hiTint },
  tally = { kind = "miner", tall = 0.68, build = "broad", cut = "tunic", coat = C.tie, trim = C.bg, hat = "helmet", hatInk = C.warn, hatTrim = C.hi, beard = "plaited", beardInk = C.bg, carry = "board", back = C.panel },
  lane = { kind = "gnome", tall = 0.55, build = "thin", cut = "robe", coat = C.bg, trim = C.accent, hat = "feather", hatInk = C.accent, hatTrim = C.soft, beard = "moustache", beardInk = C.warn, eyes = "shifty", mouth = "smile",
    wear = { "cape" }, capeInk = C.blueTint, back = C.bg },
  hatter = { kind = "gnome", tall = 0.46, build = "normal", cut = "coat", coat = C.accent, trim = C.hi, beard = "goatee", beardInk = C.redTint, hat = "stack", eyes = "wide", mouth = "smile", back = C.blueTint },
  marrow = { kind = "gnome", tall = 0.46, build = "hunched", lean = 0.14, cut = "tunic", coat = C.redTint, trim = C.hiTint, skin = C.warn, hair = "tufts", hairInk = C.text, beard = "belted", beardInk = C.text, carry = "boots", oneShoe = true,
    eyes = "narrow", back = C.redTint }, -- he has the first boots ever to go down the shaft, and he's not wearing them
  twin_tick = { kind = "gnome", tall = 0.53, cut = "tunic", coat = C.red, trim = C.blue, hat = "floppy", hatInk = C.blue, hatTrim = C.red, beard = "goatee", beardInk = C.bg, carry = "bell", eyes = "wide", mouth = "open", back = C.redTint },
  twin_tack = { kind = "gnome", tall = 0.53, cut = "tunic", coat = C.blue, trim = C.red, hat = "floppy", hatInk = C.red, hatTrim = C.blue, beard = "goatee", beardInk = C.bg, carry = "pen", eyes = "narrow", mouth = "frown", flip = true, back = C.blueTint },
  silt = { kind = "frog", tall = 0.72, build = "stout", lean = 0.1, cut = "dress", coat = C.hiTint, trim = C.tie, skin = C.ok, wear = { "shawl" }, shawlInk = C.accent, carry = "tray", back = C.hiTint },
  lampwright = { kind = "gnome", tall = 0.52, cut = "dress", coat = C.redTint, trim = C.warn, hat = "candles", hatInk = C.line, hatTrim = C.text, hair = "curls", hairInk = C.hi, wear = { "apron" }, apronInk = C.tie, carry = "lantern", eyes = "tired", back = C.bg },
  bettony = { kind = "gnome", tall = 0.54, build = "stout", cut = "dress", coat = C.hiTint, trim = C.hi, hair = "bun", hairInk = C.red, skin = C.warn, wear = { "apron" }, apronInk = C.line, carry = "kettle", mouth = "smile", back = C.redTint },
  ringer = { kind = "gnome", tall = 0.5, build = "thin", cut = "tunic", coat = C.tie, trim = C.hi, hat = "earflap", hatInk = C.blue, hatTrim = C.hi, hair = "wild", hairInk = C.text, carry = "bell", mouth = "line", eyes = "tired", back = C.tie },
  knitter = { kind = "gnome", tall = 0.43, build = "broad", cut = "dress", coat = C.accent, trim = C.tie, hair = "bun", hairInk = C.text, eyes = "specs", carry = "knitting", mouth = "smile", back = C.hiTint },
  dunnock_up = { kind = "miner", tall = 0.66, build = "normal", cut = "tunic", coat = C.hiTint, trim = C.warn, legs = C.redTint, hat = "cap", hatInk = C.panel, hatTrim = C.warn, beard = "forked", beardInk = C.redTint, carry = "crutch", oneShoe = true, mouth = "open", back = C.blueTint },

  -- ---- the mine

  warden = { kind = "miner", tall = 0.7, build = "stout", cut = "tunic", coat = C.redTint, trim = C.bg, hat = "horned", hatInk = C.tie, hatTrim = C.hi, beard = "long", beardInk = C.bg, carry = "pick", eyes = "red",
    mouth = "teeth", back = C.redTint },
  nurse = { kind = "gnome", tall = 0.6, build = "broad", cut = "dress", coat = C.tie, trim = C.text, hat = "pot", hatInk = C.line, hatTrim = C.text, wear = { "apron" }, carry = "bowl", mouth = "frown", back = C.tie },
  nib = { kind = "gnome", tall = 0.57, build = "thin", cut = "tunic", coat = C.blueTint, trim = C.hi, hair = "wild", hairInk = C.warn, hat = "goggles", hatInk = C.hi, hatTrim = C.redTint, carry = "tube", mouth = "open", back = C.blueTint },
  nob = { kind = "gnome", tall = 0.4, build = "stout", cut = "tunic", coat = C.panel, trim = C.warn, hat = "earflap", hatInk = C.redTint, hatTrim = C.warn, carry = "shovel", eyes = "wide", mouth = "frown", back = C.bg },
  logkeeper = { kind = "gnome", tall = 0.54, cut = "coat", coat = C.hiTint, trim = C.hi, hat = "pointy", hatInk = C.hi, hatTrim = C.bg, beard = "long", beardInk = C.line, eyes = "specs", carry = "cage", back = C.hiTint },
  foreman = { kind = "gnome", tall = 0.41, build = "normal", cut = "tunic", coat = C.bg, trim = C.bg, skin = C.line, hat = "bowler", hatInk = C.tie, hatTrim = C.hi, beard = "chops", beardInk = C.text, wear = { "waistcoat" }, vestInk = C.red,
    carry = "list", blight = true, eyes = "red", mouth = "stitched", tilt = 0.07, lean = 0.08, back = C.redTint },
  valve = { kind = "gnome", tall = 0.42, lean = 0.3, build = "hunched", cut = "tunic", coat = C.panel, trim = C.warn, hat = "cap", hatInk = C.line, hatTrim = C.bg, beard = "stubble", carry = "wheel", eyes = "closed", mouth = "smile", back = C.bg },
  propsetter = { kind = "miner", tall = 0.7, build = "broad", cut = "tunic", coat = C.redTint, trim = C.warn, hat = "helmet", hatInk = C.hi, hatTrim = C.text, beard = "long", beardInk = C.redTint, carry = "prop", mouth = "line", back = C.redTint },
  dunnock = { kind = "miner", pose = "lying", coat = C.hiTint, trim = C.tie, hat = "cap", hatInk = C.panel, hatTrim = C.warn, beard = "forked", beardInk = C.redTint, beam = true },

  -- the sick on their sacking, and the deep shift in its rows, each with what they wore and what they dropped
  sick1 = { kind = "gnome", pose = "lying", coat = C.blueTint, trim = C.tie, hat = "cap", hatInk = C.redTint, thread = true, sackInk = C.line },
  sick2 = { kind = "gnome", pose = "lying", coat = C.redTint, trim = C.tie, hair = "wild", hairInk = C.red, thread = true, sackInk = C.line, flip = true, size = 0.75 },
  sick3 = { kind = "gnome", pose = "lying", coat = C.hiTint, trim = C.tie, hair = "short", hairInk = C.text, beard = "long", beardInk = C.text, thread = true, sackInk = C.line, size = 1.25 },
  sleeper1 = { kind = "gnome", pose = "lying", coat = C.tie, trim = C.panel, hat = "helmet", hatInk = C.warn, hatTrim = C.hi, carry = "shovel", carryX = 0.12, carryY = 0 },
  sleeper2 = { kind = "gnome", pose = "lying", coat = C.redTint, trim = C.panel, hat = "helmet", hatInk = C.tie, hatTrim = C.hi, beard = "forked", beardInk = C.warn, carry = "pick", carryX = 0.34, carryY = 0.86, flip = true },
  sleeper3 = { kind = "gnome", pose = "lying", coat = C.blueTint, trim = C.panel, hair = "plaits", hairInk = C.hi, size = 0.7 },
  sleeper4 = { kind = "gnome", pose = "lying", coat = C.hiTint, trim = C.panel, hat = "earflap", hatInk = C.line, hatTrim = C.bg, beard = "moustache", beardInk = C.bg, carry = "hammer", carryX = 0.2, carryY = 0.8 },
  lampwoman = { kind = "gnome", pose = "lying", coat = C.tie, trim = C.panel, hair = "bun", hairInk = C.redTint, wear = { "patches" }, carry = "greenlamp", carryX = 0.06, carryY = 0.68 },

  -- addShape people of their own, for whoever comes next
  owlin = { kind = "owlin", tall = 0.8, cut = "robe", coat = C.blueTint, trim = C.tie, hair = "tufts", hairInk = C.line, wear = { "shawl" }, shawlInk = C.tie },
}
M.LOOKS = LOOKS

-- A name over addShape talk box, for the people who borrow addShape portrait.
M.NAMES = {
  NAN = "nan", WICK = "wick", CLERK = "clerk", PIP = "pip", NIB = "nib", NOB = "nob", TOBIN = "tobin", ALWIN = "dozer", ["GENTLEMAN BOGG"] = "frog", BOGG = "frog",
  ["OTTILIE BRASSCAP"] = "mayor", ["MAYOR BRASSCAP"] = "mayor", MAYOR = "mayor", CAPTAIN = "captain", DOCTOR = "doctor", INNKEEPER = "innkeeper", SMITH = "smith", FOREMAN = "foreman",
  WIDOW = "widow", ORDERLY = "gateman", SOLDIER = "corner", SERGEANT = "sergeant", SEXTON = "sexton", ["THE HANLEY BOY"] = "hanley", ["MISTRESS LIOTH"] = "lioth", ["CLINIC CLERK"] = "satchel",
  ["HEN WIFE"] = "henwife", CHALKER = "chalker", ["TIBBLE THE HATTER"] = "hatter", ["OLD MARROW"] = "marrow", TICK = "twin_tick", TACK = "twin_tack", ["MOTHER SILT"] = "silt",
  ["CLERK BASCOMBE"] = "bascombe", LAMPWRIGHT = "lampwright", BETTONY = "bettony", ["BELL-RINGER"] = "ringer", KNITTER = "knitter", ["PROP-SETTER"] = "propsetter", DUNNOCK = "dunnock_up",
  ["CASK HANDLER"] = "handler_small",
}

-- Who speaks in addShape borrowed voice: these say ids and names belong to whoever the player is facing, when that person has addShape look.
local BORROWED = { gnome = true, villager = true, child = true }
local BORROWED_NAME = { SOLDIER = true, ORDERLY = true, ["CASK HANDLER"] = true }

--- The portrait for addShape line of speech. say is the script's portrait id, name the name over the box, and npcId whoever the player
-- is facing: addShape name that means someone wins, then addShape borrowed voice goes to the person in front of you, and otherwise it's say.
function M.faceFor(say, name, npcId)
  local spoken = BORROWED[say] or BORROWED_NAME[name]
  if spoken and npcId and LOOKS[npcId] and (BORROWED_NAME[name] or not M.NAMES[name]) then return npcId end
  return M.NAMES[name] or say
end

for id, look in pairs(LOOKS) do
  local lying = look.pose == "lying"
  SPRITES["look:" .. id] = { build = function() return lookShapes(look) end, size = lying and 0.62 or 1, near = lying and 0.45 or 0.1 }
end

--- The sprite of an npc, if it has addShape look of its own.
function M.lookSprite(id) return LOOKS[id] and ("look:" .. id) or nil end

-- ---------------------------------------------------------------- baking

local function paintEllipse(grid, w, h, s)
  local top, bottom = floor((s.cy - s.ry) * h), ceil((s.cy + s.ry) * h)
  for row = math.max(0, top), math.min(h - 1, bottom) do
    local dy = ((row + 0.5) / h - s.cy) / s.ry
    if dy >= -1 and dy <= 1 then
      local half = s.rx * sqrt(1 - dy * dy)
      local line = grid[row]
      for col = math.max(0, ceil((s.cx - half) * w - 0.5)), math.min(w - 1, floor((s.cx + half) * w - 0.5)) do line[col] = s.color end
    end
  end
end

local function paintRect(grid, w, h, s)
  for row = math.max(0, floor(s.y * h + 0.5)), math.min(h - 1, ceil((s.y + s.h) * h - 0.5) - 1) do
    local line = grid[row]
    for col = math.max(0, floor(s.x * w + 0.5)), math.min(w - 1, ceil((s.x + s.w) * w - 0.5) - 1) do line[col] = s.color end
  end
end

local function paintPolygon(grid, w, h, s)
  local pts = s.points
  local n = #pts / 2
  for row = 0, h - 1 do
    local v = (row + 0.5) / h
    local crossings = {}
    for i = 1, n do
      local j = i % n + 1
      local y1, y2 = pts[i * 2], pts[j * 2]
      if (y1 <= v) ~= (y2 <= v) then
        local x1, x2 = pts[i * 2 - 1], pts[j * 2 - 1]
        crossings[#crossings + 1] = x1 + (v - y1) / (y2 - y1) * (x2 - x1)
      end
    end
    table.sort(crossings)
    for i = 1, #crossings - 1, 2 do
      local line = grid[row]
      for col = math.max(0, ceil(crossings[i] * w - 0.5)), math.min(w - 1, floor(crossings[i + 1] * w - 0.5)) do line[col] = s.color end
    end
  end
end

--- A dark edge round the whole sprite, so it stands clear of any wall behind it.
local function outline(grid, w, h)
  for row = 0, h - 1 do
    local line, up, down = grid[row], grid[row - 1], grid[row + 1]
    for col = 0, w - 1 do
      if not line[col] then
        local near = line[col - 1] and line[col - 1] ~= -1 or line[col + 1] and line[col + 1] ~= -1
          or (up and up[col] and up[col] ~= -1) or (down and down[col] and down[col] ~= -1)
        if near then line[col] = -1 end
      end
    end
  end
end

local function toRuns(grid, w, h, remap, edge)
  local runs = {}
  for row = 0, h - 1 do
    local line = grid[row]
    local col = 0
    while col < w do
      local c = line[col]
      if c then
        local from = col
        while col + 1 < w and line[col + 1] == c do col = col + 1 end
        local ink = c == -1 and edge or c
        if remap then ink = remap[ink] or ink end
        local n = #runs
        runs[n + 1], runs[n + 2], runs[n + 3], runs[n + 4] = from, row, col - from + 1, ink
      end
      col = col + 1
    end
  end
  return runs
end

--- A grid of colours, from row -1 to h, with the shapes painted on it.
local function paintGrid(list, w, h)
  local grid = {}
  for row = -1, h do grid[row] = {} end
  for _, s in ipairs(list) do
    if s.kind == "e" then
      paintEllipse(grid, w, h, s)
    elseif s.kind == "r" then
      paintRect(grid, w, h, s)
    else
      paintPolygon(grid, w, h, s)
    end
  end
  return grid
end

local baked = {}

--- Runs { x, y, w, colour, ... } for addShape sprite w by h cells. remap swaps colours, for distance or addShape flash; its name goes in
-- the key, so each look is baked once.
function M.bake(name, w, h, remap, remapName)
  local look = name .. ":" .. w .. "x" .. h .. ":" .. (remapName or "")
  local runs = baked[look]
  if runs then return runs end
  local sprite = SPRITES[name]
  sprite.shapes = sprite.shapes or sprite.build()
  local grid = paintGrid(sprite.shapes, w, h)
  outline(grid, w, h)
  runs = toRuns(grid, w, h, remap, C.bg)
  baked[look] = runs
  return runs
end

-- ---------------------------------------------------------------- portraits

M.PORTRAIT_W, M.PORTRAIT_H = 20, 15

local INK = {
  k = C.bg, g = C.panel, G = C.tie, l = C.line, w = C.text, r = C.red, b = C.redTint, B = C.blue, n = C.blueTint, y = C.hi,
  o = C.warn, v = C.accent, c = C.info, e = C.ok, s = C.soft, m = C.hiTint,
}

-- The faces with no look: the party, drawn by hand, and the stock faces for anyone who just says "gnome" or "villager".
-- 20 by 15, one letter addShape cell, from the table above. A dot is the portrait's backdrop.
local PORTRAITS = {
  hero = { back = C.blueTint, -- young, watchful, addShape chin of scabs from addShape town that doesn't like orphans
    "....................",
    "......kkkkkkkk......",
    "....kkkkkkkkkkkk....",
    "...kkkgkkkgkkkkkk...",
    "...kkkkoookkkoookk..",
    "...kkoooooooooooob..",
    "...koobkkoooobkkob..",
    "....oowkGooooGkwob..",
    "....oooooobooooob...",
    ".....ooooobbooob....",
    ".....boobbbbboob....",
    "......boooooobb.....",
    "....GGGbbbbbbGGG....",
    "..GGgGGGgbbgGGGgGG..",
    ".GGgGGGGGggGGGGGgGG.",
  },
  deserter = { back = C.redTint, -- the Clinic's coat, with the badge cut off. A long scar and no sleep.
    "....................",
    ".......GGGGGG.......",
    ".....GgGGGGGGgG.....",
    "....GGooooooooGG....",
    "....GoooooooorbG....",
    "....oobbooobbrob....",
    "....owkGoooGkwrb....",
    "....oooobbooooob....",
    "....GoooobbooobG....",
    ".....GoooooooGG.....",
    ".....GGbkkkkbG......",
    "......GGooooGG......",
    "..wwwwwkbbbbkwwwww..",
    ".kkkkkkwwkkwwkkkkkk.",
    "kkkkkkkkkkkkgkkrkkkk",
  },
  cleric = { back = C.panel, -- the hood hides everything but the jaw. Her eyes are shut, and she's still looking at you.
    "........kkkk........",
    "......kkvvvvkk......",
    ".....kvvkkkkvvk.....",
    "....kvkkkkkkkkvk....",
    "....kvkkkkkkkkvk....",
    "...kvkkkgggggkkvk...",
    "...kvkkgwwwwwgkvk...",
    "...kvkgGwwGwwGgkvk..",
    "...kvkgwwwwwwwgkvk..",
    "...kvkkwwwlwwwkkvk..",
    "...kvkkgwkkkwgkkvk..",
    "...kvkkkgwwwgkkkvk..",
    "..kkvkkkkkkkkkkkvkk.",
    ".kkvkkkkvkkvkkkkkvkk",
    "kkvkkkkkkvvkkkkkkkvk",
  },
  child = { back = C.tie, -- says hello to people who aren't there
    "....................",
    "......bbbbbbb.......",
    ".....bbbbbbbbbb.....",
    "....bbbkbbbbkbbb....",
    "....bbwwwwwwwwbb....",
    "....bwwwwwwwwwwb....",
    "....wwkkkwwkkkww....",
    "....wwkckwwkckwl....",
    "....wwkkkwwkkkwl....",
    ".....wwwwllwwwl.....",
    ".....wwwwwwwwwl.....",
    "......lwwkkwwl......",
    "........wwww........",
    ".....llllggllll.....",
    "...lllllllggllllll..",
  },
  gnome = { back = C.blueTint, -- two pairs of spectacles and an opinion on your boots
    ".........ee.........",
    "........eeee........",
    ".......eeeeee.......",
    "......eeeeeeee......",
    ".....eeeeeeeeee.....",
    "....mmmmmmmmmmmm....",
    "....ooooooooooob....",
    "...yyyyyoooyyyyy....",
    "...yGwGyyyyyGwGy....",
    "...yyyyyoooyyyyy....",
    "....oooobbbbooob....",
    "....wwooboboowww....",
    "...wwwwwkkkwwwww....",
    "....wwwwwwwwwww.....",
    "..mmmmmmmwwmmmmmmm..",
  },
  villager = { back = C.hiTint, -- has buried people, and got up the next day and fed the hens
    "....................",
    "......GGGGGGGG......",
    ".....GGGGGGGGGG.....",
    "....GGGGGGGGGGGG....",
    "....GGooooooooGG....",
    "....GoooooooooGG....",
    "....oobkkoobkkob....",
    "....oowkoooowkob....",
    "....boooobboooob....",
    ".....oooooooooo.....",
    ".....boobbbboob.....",
    "......boooooob......",
    "...GGlllbbbbllGGG...",
    "..bbbbllllllllbbbb..",
    ".bbbbbbbbbbbbbbbbbb.",
  },
}
M.PORTRAITS = PORTRAITS -- every face there is: anyone with addShape look has one too, so addShape say id can be checked here either way
for id, look in pairs(LOOKS) do PORTRAITS[id] = look end

-- The part of addShape body addShape portrait shows: wide enough for shoulders, tall enough for most hats. 20 cells by 15 is 40 by 45 on the
-- wall, which is why the window is taller than it's wide.
local FACE_X, FACE_Y, FACE_W, FACE_H = 0.22, -0.21, 0.56, 0.63

local function zoomed(list)
  local out = {}
  local function zx(x) return (x - FACE_X) / FACE_W end
  local function zy(y) return (y - FACE_Y) / FACE_H end
  for _, s in ipairs(list) do
    if s.kind == "e" then
      out[#out + 1] = E(zx(s.cx), zy(s.cy), s.rx / FACE_W, s.ry / FACE_H, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(zx(s.x), zy(s.y), s.w / FACE_W, s.h / FACE_H, s.color)
    else
      local pts = {}
      for i = 1, #s.points, 2 do pts[i], pts[i + 1] = zx(s.points[i]), zy(s.points[i + 1]) end
      out[#out + 1] = P(s.color, unpack(pts))
    end
  end
  return out
end

--- Eyes, nose and mouth, addShape cell at addShape time. The eyes are on row 8, either side of the middle, and the mouth on row 11.
local function paintFace(grid, look)
  local dx = floor((look.tilt or 0) / FACE_W * 20 + 0.5)
  local function put(x, y, ink) grid[y][x + dx] = ink end
  local function row(y, ink, ...)
    for _, x in ipairs({ ... }) do put(x, y, ink) end
  end
  local shade, eyes, mouth = look.shade, look.eyes, look.mouth
  if eyes == "wide" then
    row(7, C.text, 7, 8, 11, 12)
    row(8, C.text, 7, 12)
    row(8, C.bg, 8, 11)
  elseif eyes == "red" then
    row(8, C.bg, 7, 12)
    row(8, C.red, 8, 11)
  elseif eyes == "closed" then
    row(8, shade, 7, 8, 11, 12)
  elseif eyes == "narrow" then
    row(8, C.bg, 7, 8, 11, 12)
    row(8, shade, 6, 13)
  elseif eyes == "shifty" then
    row(8, C.text, 7, 11)
    row(8, C.bg, 8, 12)
    row(7, shade, 7, 8, 11, 12)
  elseif eyes == "specs" then
    row(7, C.hi, 6, 7, 8, 9, 10, 11, 12, 13)
    row(8, C.hi, 6, 9, 10, 13)
    row(8, C.text, 7, 12)
    row(8, C.bg, 8, 11)
  elseif eyes ~= "lens" and eyes ~= "none" then
    row(8, C.text, 7, 12)
    row(8, C.bg, 8, 11)
    row(eyes == "tired" and 9 or 7, shade, 7, 8, 11, 12)
  end
  if look.nose == "big" then
    row(9, look.skin, 9, 10)
    row(10, shade, 9, 10)
  elseif look.nose == "small" then
    row(9, shade, 10)
    row(10, shade, 10)
  end
  if look.mark == "ink" then
    row(9, C.blueTint, 13)
    row(10, C.blueTint, 12, 13)
  end
  if mouth == "line" then
    row(11, C.bg, 9, 10)
  elseif mouth == "smile" then
    row(10, C.bg, 7, 12)
    row(11, C.bg, 8, 9, 10, 11)
  elseif mouth == "frown" then
    row(11, C.bg, 7, 12)
    row(10, C.bg, 8, 9, 10, 11)
  elseif mouth == "open" then
    row(11, C.bg, 9, 10)
    row(12, C.bg, 9, 10)
  elseif mouth == "teeth" then
    row(11, C.text, 8, 10, 12)
    row(11, C.bg, 7, 9, 11)
  elseif mouth == "stitched" then
    row(11, C.bg, 6, 7, 8, 9, 10, 11, 12, 13)
    row(10, C.bg, 7, 9, 11)
    row(12, C.bg, 7, 9, 11)
  end
end

--- A person's face, from the same shapes as their sprite. They always stand for it, even if the sprite is lying down.
local function bakeLookFace(look)
  local list = zoomed(standingBody(look, true))
  local w, h = M.PORTRAIT_W, M.PORTRAIT_H
  local grid = paintGrid(list, w, h)
  outline(grid, w, h)
  for row = 0, h - 1 do
    local line = grid[row]
    for col = 0, w - 1 do line[col] = line[col] or look.back end
  end
  paintFace(grid, look)
  return toRuns(grid, w, h, nil, C.bg)
end

local portraitRuns = {}

--- Runs { x, y, w, colour, ... } for addShape portrait. Letters outside the table show as the backdrop, not as addShape crash.
local function bakePortrait(id)
  local runs = {}
  local face = PORTRAITS[id]
  for row, line in ipairs(face) do
    local col = 1
    while col <= M.PORTRAIT_W do
      local c = line:sub(col, col)
      local from = col
      while col < M.PORTRAIT_W and line:sub(col + 1, col + 1) == c do col = col + 1 end
      local n = #runs
      runs[n + 1], runs[n + 2], runs[n + 3], runs[n + 4] = from - 1, row - 1, col - from + 1, INK[c] or face.back
      col = col + 1
    end
  end
  return runs
end

--- A face, 20 cells wide and 15 tall, with its top left corner at x, y. An unknown id gets addShape villager.
function M.portrait(id, x, y)
  id = (LOOKS[id] or PORTRAITS[id]) and id or "villager"
  local runs = portraitRuns[id]
  if not runs then
    runs = LOOKS[id] and bakeLookFace(LOOKS[id]) or bakePortrait(id)
    portraitRuns[id] = runs
  end
  local fill = ui.fill
  for i = 1, #runs, 4 do fill(x + runs[i], y + runs[i + 1], runs[i + 2], 1, runs[i + 3]) end
end

return M
