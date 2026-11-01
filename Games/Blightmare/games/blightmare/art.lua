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

local baked = {}

--- Runs { x, y, w, colour, ... } for a sprite w by h cells. remap swaps colours, for distance or a flash; its name goes in
-- the key, so each look is baked once.
function M.bake(name, w, h, remap, remapName)
  local look = name .. ":" .. w .. "x" .. h .. ":" .. (remapName or "")
  local runs = baked[look]
  if runs then return runs end
  local sprite = SPRITES[name]
  sprite.shapes = sprite.shapes or sprite.build()
  local grid = {}
  for row = -1, h do grid[row] = {} end
  for _, s in ipairs(sprite.shapes) do
    if s.kind == "e" then
      paintEllipse(grid, w, h, s)
    elseif s.kind == "r" then
      paintRect(grid, w, h, s)
    else
      paintPolygon(grid, w, h, s)
    end
  end
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

-- 20 by 15, one letter a cell, from the table above. A dot is the portrait's backdrop.
local PORTRAITS = {
  hero = { back = C.blueTint, -- young, watchful, a chin of scabs from a town that doesn't like orphans
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
  captain = { back = C.panel, -- pressed, shaved and certain, and he has signed a great many forms
    "....................",
    ".....nnnnnnnnnn.....",
    "....nnnnnnnnnnnn....",
    "...nnnnnnyynnnnnn...",
    "...nnnnnnyynnnnnn...",
    "..kkkkkkkkkkkkkkkk..",
    "....lwwwwwwwwwwl....",
    "....wkkGwwwwGkkw....",
    "....wwcGwwwwGcwl....",
    "....lwwwwllwwwwl....",
    ".....wwwwwwwwwl.....",
    ".....lwkkkkkkwl.....",
    "......lwwwwwwl......",
    "..yyynnnkkkknnnyyy..",
    ".nnnnnnnnkknnnnnnnn.",
  },
  doctor = { back = C.redTint, -- nobody in Scythebreak has seen a doctor's face. The beak is full of herbs. Some of them say.
    "....................",
    ".......kkkkkk.......",
    "......kkkkkkkk......",
    ".....kkkkkkkkkk.....",
    "...kkkkkkkkkkkkkk...",
    ".kkkkkkkkkkkkkkkkkk.",
    "...wwwwwwwwwwwww....",
    "...wkkkwwwwkkkwwl...",
    "...wkcckwwkcckwwl...",
    "...wkkkwwwwkkkwwll..",
    "...wwwwwwwwwwwwwwll.",
    "...lwwwwwwwwwwlwwwll",
    "....lwwwwwlwwlkkllll",
    "..kkkklwwwwlkkk..lll",
    ".kkkkkkkkkkkkkkkk...",
  },
  mayor = { back = C.hiTint, -- a gnome who has been mayor for sixty years and has never once been asked a hard question
    ".......kkkkkk.......",
    ".......kkkkkk.......",
    ".......kkkkkk.......",
    ".......kyyyyk.......",
    ".....kkkkkkkkkk.....",
    "......oooooooo......",
    ".....oooooooooo.....",
    ".....oyyyooyyyo.....",
    ".....oykkyykkyo.....",
    "....boooobboooob....",
    "....wwwwoooowwww....",
    "...wwwwwwwwwwwwww...",
    "....www.wwww.www....",
    "..vvvvyvvvvvvyvvvv..",
    ".vvvvvvyyyyyyvvvvvv.",
  },
  smith = { back = C.panel, -- all soot and forearm, and a beard she's plaited round a burn
    "....................",
    "......kkkkkkkk......",
    ".....koooooooob.....",
    "....koooooooooob....",
    "....kkkkoookkkkb....",
    "....oowkoooowkob....",
    "....boooobboooob....",
    "....oorrooooorrb....",
    "...rrrrrbrrbrrrrr...",
    "...rroyrrrrrryorr...",
    "....rrrrrrrrrrrr....",
    ".....rryrrrryrr.....",
    "...bbbbrrrrrrbbbb...",
    "..bbbbbbbrrbbbbbbb..",
    ".GGGbbGGGGGGGGbbGGG.",
  },
  innkeeper = { back = C.redTint, -- broad, kind, and quietly counting who hasn't come down to breakfast
    "....................",
    "......rrrrrrrr......",
    ".....rrrrrrrrrr.....",
    "....rrrwrrrwrrrr....",
    "....rrkkkkkkkkrr....",
    "...krooooooooooork..",
    "...koobkkoobkkook...",
    "...koowkoooowkook...",
    "...krrooobbooorrb...",
    "...kbrroooooorrbk...",
    "....boowkkkkwoob....",
    ".....boooooooob.....",
    "...wwwwboooobwwww...",
    "..wwbbbwwwwwwbbbww..",
    ".wbbbbbbwwwwbbbbbbw.",
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
  foreman = { back = C.redTint, -- he brought the deep shift up with him. Some of it.
    ".........yy.........",
    "........yyyy........",
    "......GGGyyGGG......",
    ".....GGGGGGGGGG.....",
    "...GGGGGGGGGGGGGG...",
    ".....llllllllsl.....",
    "....llllllsslsss....",
    "....lkkkllkkksee....",
    "....lrrkllkrrses....",
    "....llllGGllllse....",
    "....GllllGlllsss....",
    ".....lkwkwkwklss....",
    "......lGGGGGll......",
    "...mmmmmGGmmmmsss...",
    "..mmmmmmmmmmmmmsee..",
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
M.PORTRAITS = PORTRAITS

local portraitRuns = {}

--- Runs { x, y, w, colour, ... } for a portrait. Letters outside the table show as the backdrop, not as a crash.
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

--- A face, 20 cells wide and 15 tall, with its top left corner at x, y. An unknown id gets a villager.
function M.portrait(id, x, y)
  id = PORTRAITS[id] and id or "villager"
  local runs = portraitRuns[id]
  if not runs then
    runs = bakePortrait(id)
    portraitRuns[id] = runs
  end
  local fill = ui.fill
  for i = 1, #runs, 4 do fill(x + runs[i], y + runs[i + 1], runs[i + 2], 1, runs[i + 3]) end
end

return M
