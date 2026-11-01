-- games/dungeon/art.lua
-- Everything in the dungeon that isn't a wall, as shapes in a unit square with the floor along the bottom. A shape can be
-- drawn at any distance, so a monster stays crisp at every size. bake turns a sprite into runs of colour once for each
-- size it's seen at, and from then on showing it is a short list of fills.

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

-- ---------------------------------------------------------------- monsters

local function skeleton()
  local bone, shade, dark = C.text, C.line, C.bg
  local ribs = {}
  for i = 0, 3 do ribs[#ribs + 1] = R(0.34 + i * 0.015, 0.41 + i * 0.05, 0.32 - i * 0.03, 0.025, bone) end
  return flatten(
    -- the sword arm, raised behind the skull
    shapes(
      P(bone, 0.7, 0.36, 0.74, 0.4, 0.92, 0.27, 0.88, 0.23), P(bone, 0.86, 0.22, 0.93, 0.24, 1, 0.02, 0.97, 0, 0.93, 0),
      P(C.tie, 0.92, 0.2, 0.93, 0.24, 1, 0.02, 0.97, 0), R(0.8, 0.2, 0.2, 0.03, C.warn), E(0.89, 0.25, 0.035, 0.03, bone),
      P(bone, 0.3, 0.38, 0.22, 0.36, 0.1, 0.52, 0.13, 0.55), P(bone, 0.1, 0.52, 0.13, 0.55, 0.2, 0.68, 0.17, 0.7),
      E(0.17, 0.72, 0.05, 0.04, bone)
    ),
    shapes(R(0.27, 0.36, 0.46, 0.035, bone), R(0.485, 0.34, 0.03, 0.34, shade)),
    ribs,
    pair(R(0.4, 0.72, 0.05, 0.2, bone), E(0.425, 0.73, 0.05, 0.03, shade), R(0.36, 0.93, 0.1, 0.04, bone)),
    shapes(P(bone, 0.37, 0.66, 0.63, 0.66, 0.6, 0.73, 0.4, 0.73), E(0.5, 0.17, 0.17, 0.17, bone), R(0.39, 0.25, 0.22, 0.09, bone)),
    pair(E(0.43, 0.16, 0.055, 0.065, dark), E(0.43, 0.165, 0.022, 0.026, C.red), R(0.43, 0.28, 0.012, 0.06, dark)),
    shapes(R(0.47, 0.28, 0.012, 0.06, dark), R(0.51, 0.28, 0.012, 0.06, dark), P(dark, 0.5, 0.19, 0.46, 0.25, 0.54, 0.25),
      R(0.39, 0.27, 0.22, 0.012, shade), P(C.line, 0.55, 0.03, 0.57, 0.1, 0.53, 0.09))
  )
end

local function rat()
  local fur, face, dark = C.tie, C.line, C.bg
  return flatten(
    -- a hunched back with bristles, and a tail whipping up behind
    shapes(
      P(C.red, 0.86, 0.8, 0.92, 0.78, 0.99, 0.5, 0.95, 0.48), E(0.5, 0.6, 0.46, 0.38, fur), E(0.5, 0.86, 0.3, 0.12, C.panel),
      P(fur, 0.14, 0.42, 0.1, 0.24, 0.24, 0.32, 0.26, 0.14, 0.38, 0.26, 0.5, 0.1, 0.62, 0.26, 0.74, 0.14, 0.76, 0.32, 0.9, 0.24, 0.86, 0.42)
    ),
    -- torn ears, laid back
    pair(P(face, 0.3, 0.42, 0.1, 0.3, 0.16, 0.2, 0.2, 0.26, 0.26, 0.2, 0.38, 0.34), P(C.redTint, 0.29, 0.4, 0.16, 0.31, 0.2, 0.28, 0.34, 0.35)),
    -- a wedge of a head, narrowing to the snout
    shapes(P(face, 0.24, 0.42, 0.76, 0.42, 0.68, 0.58, 0.58, 0.7, 0.42, 0.7, 0.32, 0.58)),
    pair(
      P(dark, 0.27, 0.42, 0.47, 0.52, 0.46, 0.56, 0.3, 0.5), P(C.red, 0.33, 0.48, 0.45, 0.54, 0.44, 0.57, 0.35, 0.53), E(0.41, 0.54, 0.012, 0.014, C.hi),
      R(0.16, 0.6, 0.22, 0.008, dark), R(0.15, 0.65, 0.25, 0.008, dark),
      E(0.24, 0.93, 0.1, 0.05, face), P(C.text, 0.15, 0.94, 0.17, 1, 0.19, 0.94), P(C.text, 0.21, 0.95, 0.23, 1, 0.25, 0.95),
      P(C.text, 0.27, 0.95, 0.29, 1, 0.31, 0.95)
    ),
    -- a screaming mouth, red inside, all teeth
    shapes(E(0.5, 0.66, 0.05, 0.035, C.red), P(dark, 0.34, 0.68, 0.66, 0.68, 0.6, 0.9, 0.4, 0.9), P(C.redTint, 0.42, 0.78, 0.58, 0.78, 0.56, 0.88, 0.44, 0.88)),
    pair(P(C.text, 0.36, 0.68, 0.48, 0.68, 0.44, 0.84, 0.42, 0.84), P(C.text, 0.41, 0.9, 0.47, 0.9, 0.45, 0.8))
  )
end

local function bat()
  local wing, rib, body = C.accent, C.redTint, C.tie
  return flatten(
    shapes(E(0.5, 0.97, 0.2, 0.02, C.bg)),
    pair(
      P(wing, 0.5, 0.22, 0.3, 0.1, 0.02, 0.1, 0.0, 0.46, 0.09, 0.36, 0.15, 0.54, 0.25, 0.42, 0.34, 0.62, 0.42, 0.48, 0.5, 0.6),
      P(rib, 0.02, 0.11, 0.05, 0.11, 0.42, 0.34, 0.42, 0.38), P(rib, 0.09, 0.36, 0.11, 0.33, 0.42, 0.36, 0.42, 0.39),
      P(rib, 0.25, 0.42, 0.27, 0.39, 0.42, 0.38, 0.42, 0.41), P(C.text, 0.02, 0.1, 0.0, 0.04, 0.06, 0.1),
      P(body, 0.4, 0.2, 0.33, 0.01, 0.48, 0.14), P(C.redTint, 0.4, 0.17, 0.36, 0.06, 0.45, 0.14)
    ),
    shapes(E(0.5, 0.42, 0.13, 0.2, body), E(0.5, 0.26, 0.15, 0.13, body), E(0.5, 0.48, 0.07, 0.1, C.line)),
    pair(E(0.43, 0.24, 0.04, 0.04, C.hi), E(0.43, 0.245, 0.018, 0.022, C.red), P(C.text, 0.44, 0.33, 0.47, 0.33, 0.455, 0.43)),
    shapes(P(C.bg, 0.44, 0.31, 0.56, 0.31, 0.53, 0.35, 0.47, 0.35), E(0.5, 0.29, 0.025, 0.018, C.bg))
  )
end

local function slime()
  local goo, light, dark = C.ok, C.soft, C.hiTint
  return flatten(
    shapes(
      E(0.5, 0.62, 0.42, 0.42, goo), R(0.08, 0.62, 0.84, 0.3, goo), E(0.14, 0.92, 0.1, 0.07, goo), E(0.36, 0.94, 0.12, 0.06, goo),
      E(0.62, 0.94, 0.13, 0.06, goo), E(0.86, 0.92, 0.1, 0.07, goo), E(0.5, 0.8, 0.34, 0.12, dark), E(0.5, 0.76, 0.38, 0.13, goo),
      E(0.3, 0.38, 0.1, 0.06, light), E(0.2, 0.47, 0.03, 0.05, light), E(0.72, 0.4, 0.035, 0.03, light), E(0.8, 0.6, 0.03, 0.03, light),
      E(0.14, 0.68, 0.025, 0.03, light)
    ),
    pair(E(0.37, 0.56, 0.09, 0.11, C.text), E(0.39, 0.58, 0.05, 0.07, C.red), E(0.39, 0.58, 0.02, 0.04, C.bg), P(goo, 0.25, 0.42, 0.48, 0.52, 0.47, 0.42, 0.28, 0.4)),
    shapes(P(C.bg, 0.28, 0.72, 0.72, 0.72, 0.62, 0.88, 0.38, 0.88)),
    pair(P(C.text, 0.3, 0.72, 0.38, 0.72, 0.34, 0.8), P(C.text, 0.4, 0.72, 0.48, 0.72, 0.44, 0.82), P(C.text, 0.4, 0.88, 0.47, 0.88, 0.44, 0.8))
  )
end

local function orc()
  local skin, dark, steel = C.ok, C.hiTint, C.line
  return flatten(
    -- the axe in the raised hand
    shapes(R(0.87, 0.06, 0.035, 0.72, C.redTint), P(steel, 0.9, 0.08, 1, 0.0, 1, 0.3, 0.9, 0.22), P(C.text, 1, 0.0, 1, 0.3, 0.97, 0.27, 0.97, 0.03)),
    pair(R(0.28, 0.82, 0.17, 0.14, dark), P(C.tie, 0.25, 0.94, 0.47, 0.94, 0.47, 1, 0.22, 1)),
    shapes(
      P(C.redTint, 0.2, 0.5, 0.8, 0.5, 0.74, 0.86, 0.26, 0.86), R(0.25, 0.76, 0.5, 0.05, C.warn), R(0.45, 0.74, 0.1, 0.09, steel),
      P(C.tie, 0.34, 0.5, 0.66, 0.5, 0.5, 0.72), R(0.495, 0.55, 0.01, 0.15, C.bg)
    ),
    pair(
      E(0.17, 0.5, 0.15, 0.11, steel), E(0.17, 0.53, 0.15, 0.06, C.tie), R(0.08, 0.56, 0.1, 0.2, skin), E(0.12, 0.8, 0.07, 0.06, skin),
      P(C.text, 0.1, 0.42, 0.12, 0.3, 0.16, 0.41)
    ),
    shapes(
      E(0.5, 0.28, 0.21, 0.2, skin), P(skin, 0.3, 0.3, 0.7, 0.3, 0.66, 0.52, 0.34, 0.52), E(0.5, 0.48, 0.14, 0.05, dark),
      P(steel, 0.27, 0.22, 0.32, 0.08, 0.5, 0.02, 0.68, 0.08, 0.73, 0.22), R(0.27, 0.2, 0.46, 0.035, C.tie),
      R(0.488, 0.02, 0.024, 0.18, C.tie)
    ),
    pair(
      P(C.text, 0.28, 0.2, 0.14, 0.14, 0.1, 0.01, 0.2, 0.08, 0.31, 0.12),
      P(C.bg, 0.32, 0.25, 0.48, 0.31, 0.47, 0.34, 0.33, 0.29), E(0.41, 0.32, 0.04, 0.022, C.hi), E(0.41, 0.32, 0.018, 0.02, C.red),
      E(0.46, 0.395, 0.016, 0.012, C.bg), P(C.text, 0.36, 0.5, 0.42, 0.5, 0.39, 0.37), R(0.3, 0.45, 0.04, 0.01, dark)
    ),
    shapes(R(0.35, 0.47, 0.3, 0.035, C.bg), R(0.44, 0.47, 0.02, 0.03, C.text), R(0.54, 0.47, 0.02, 0.03, C.text))
  )
end

local function ghost()
  local sheet, edge = C.text, C.info
  return flatten(
    shapes(
      E(0.5, 0.92, 0.26, 0.025, C.bg), P(edge, 0.14, 0.35, 0.86, 0.35, 0.92, 0.86, 0.78, 0.7, 0.65, 0.92, 0.5, 0.72, 0.35, 0.92, 0.22, 0.7, 0.08, 0.86)
    ),
    pair(P(edge, 0.2, 0.4, 0.02, 0.28, 0.0, 0.34, 0.03, 0.42, 0.1, 0.45, 0.04, 0.5, 0.2, 0.56)),
    shapes(
      E(0.5, 0.31, 0.32, 0.3, sheet), P(sheet, 0.19, 0.32, 0.81, 0.32, 0.84, 0.78, 0.74, 0.62, 0.63, 0.82, 0.5, 0.64, 0.37, 0.82, 0.26, 0.62, 0.16, 0.78)
    ),
    pair(E(0.38, 0.3, 0.075, 0.1, C.bg), E(0.385, 0.32, 0.03, 0.035, C.red), P(C.bg, 0.27, 0.15, 0.45, 0.19, 0.44, 0.17, 0.28, 0.12), R(0.26, 0.42, 0.02, 0.2, edge)),
    shapes(E(0.5, 0.52, 0.09, 0.12, C.bg), E(0.5, 0.56, 0.05, 0.05, C.blueTint))
  )
end

local function dragon()
  local scale, dark, belly = C.red, C.redTint, C.warn
  return flatten(
    -- wings spread behind the neck
    pair(
      P(dark, 0.5, 0.32, 0.3, 0.02, 0.0, 0.06, 0.0, 0.7, 0.08, 0.5, 0.15, 0.72, 0.24, 0.5, 0.33, 0.74, 0.5, 0.6),
      P(scale, 0.3, 0.02, 0.33, 0.02, 0.4, 0.5, 0.37, 0.5), P(scale, 0.0, 0.06, 0.04, 0.06, 0.34, 0.2, 0.33, 0.24),
      P(scale, 0.08, 0.5, 0.1, 0.48, 0.35, 0.3, 0.35, 0.33), P(C.hi, 0.3, 0.03, 0.27, 0.0, 0.34, 0.02)
    ),
    -- body, chest plates and claws
    shapes(P(scale, 0.22, 0.98, 0.78, 0.98, 0.7, 0.5, 0.3, 0.5), P(belly, 0.36, 0.98, 0.64, 0.98, 0.6, 0.5, 0.4, 0.5)),
    shapes(R(0.37, 0.84, 0.26, 0.012, dark), R(0.385, 0.74, 0.23, 0.012, dark), R(0.395, 0.65, 0.21, 0.012, dark)),
    pair(
      E(0.2, 0.9, 0.12, 0.1, scale), P(C.text, 0.09, 0.93, 0.11, 1, 0.14, 0.93), P(C.text, 0.15, 0.95, 0.17, 1, 0.2, 0.95),
      P(C.text, 0.21, 0.95, 0.24, 1, 0.26, 0.95)
    ),
    -- horns and head
    pair(
      P(C.text, 0.36, 0.16, 0.2, 0.08, 0.13, 0.0, 0.2, 0.03, 0.42, 0.08), P(C.line, 0.33, 0.16, 0.22, 0.1, 0.2, 0.08, 0.36, 0.12),
      P(scale, 0.3, 0.22, 0.16, 0.26, 0.26, 0.31), P(dark, 0.26, 0.31, 0.17, 0.36, 0.28, 0.38)
    ),
    shapes(
      P(scale, 0.3, 0.14, 0.7, 0.14, 0.76, 0.3, 0.68, 0.46, 0.64, 0.62, 0.36, 0.62, 0.32, 0.46, 0.24, 0.3),
      P(dark, 0.42, 0.05, 0.5, 0.0, 0.58, 0.05, 0.56, 0.2, 0.44, 0.2), P(scale, 0.45, 0.07, 0.5, 0.03, 0.55, 0.07, 0.54, 0.18, 0.46, 0.18),
      P(C.bg, 0.34, 0.44, 0.66, 0.44, 0.61, 0.6, 0.39, 0.6), P(C.warn, 0.41, 0.54, 0.59, 0.54, 0.56, 0.6, 0.44, 0.6),
      P(C.hi, 0.45, 0.56, 0.55, 0.56, 0.53, 0.6, 0.47, 0.6), P(scale, 0.4, 0.34, 0.6, 0.34, 0.63, 0.44, 0.37, 0.44)
    ),
    pair(
      P(C.bg, 0.29, 0.22, 0.46, 0.3, 0.45, 0.34, 0.31, 0.3), P(C.hi, 0.33, 0.25, 0.44, 0.3, 0.43, 0.33, 0.33, 0.29), R(0.385, 0.27, 0.014, 0.06, C.bg),
      E(0.45, 0.4, 0.016, 0.014, C.bg), P(C.text, 0.35, 0.44, 0.39, 0.44, 0.37, 0.52), P(C.text, 0.41, 0.44, 0.45, 0.44, 0.43, 0.5),
      P(C.text, 0.39, 0.6, 0.43, 0.6, 0.41, 0.53), P(dark, 0.32, 0.22, 0.46, 0.17, 0.44, 0.19, 0.33, 0.25)
    )
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

local function potion()
  return shapes(
    E(0.5, 0.66, 0.34, 0.33, C.text), E(0.5, 0.66, 0.3, 0.29, C.red), R(0.2, 0.42, 0.6, 0.12, C.tie), R(0.38, 0.12, 0.24, 0.3, C.text),
    R(0.42, 0.14, 0.16, 0.3, C.tie), R(0.34, 0.03, 0.32, 0.14, C.warn), E(0.37, 0.6, 0.06, 0.1, C.text)
  )
end

local function gold()
  return shapes(
    E(0.5, 0.92, 0.46, 0.09, C.warn), E(0.5, 0.78, 0.36, 0.15, C.hi), E(0.42, 0.64, 0.14, 0.08, C.warn), E(0.42, 0.61, 0.14, 0.08, C.hi),
    E(0.64, 0.7, 0.13, 0.07, C.warn), E(0.64, 0.67, 0.13, 0.07, C.hi), E(0.28, 0.82, 0.12, 0.06, C.text), E(0.56, 0.86, 0.1, 0.05, C.text)
  )
end

local function key()
  return shapes(
    E(0.5, 0.3, 0.3, 0.3, C.hi), E(0.5, 0.3, 0.14, 0.14, C.bg), R(0.43, 0.56, 0.14, 0.44, C.hi), R(0.57, 0.76, 0.2, 0.08, C.hi),
    R(0.57, 0.9, 0.14, 0.1, C.hi), R(0.45, 0.58, 0.04, 0.4, C.text)
  )
end

local function sword()
  return shapes(
    P(C.text, 0.46, 0.68, 0.46, 0.1, 0.5, 0.0, 0.54, 0.1, 0.54, 0.68), P(C.line, 0.5, 0.0, 0.54, 0.1, 0.54, 0.68, 0.5, 0.68),
    R(0.26, 0.68, 0.48, 0.08, C.hi), R(0.45, 0.76, 0.1, 0.18, C.redTint), E(0.5, 0.96, 0.07, 0.05, C.hi)
  )
end

local function armour()
  return shapes(
    P(C.line, 0.1, 0.1, 0.34, 0.03, 0.5, 0.12, 0.66, 0.03, 0.9, 0.1, 0.84, 0.5, 0.74, 0.96, 0.26, 0.96, 0.16, 0.5),
    P(C.text, 0.42, 0.14, 0.58, 0.14, 0.56, 0.9, 0.44, 0.9), R(0.18, 0.5, 0.64, 0.05, C.tie), R(0.24, 0.72, 0.52, 0.05, C.tie),
    E(0.5, 0.34, 0.06, 0.07, C.hi)
  )
end

-- A sprite's size is its share of a square. near is where in its square it stands: 0 at the front, 1 at the back.
local SPRITES = {
  skeleton = { build = skeleton, size = 1, near = 0.1 },
  rat = { build = rat, size = 0.86, near = 0.1 },
  bat = { build = bat, size = 0.95, near = 0.1 },
  slime = { build = slime, size = 0.9, near = 0.1 },
  orc = { build = orc, size = 1.04, near = 0.1 },
  ghost = { build = ghost, size = 1, near = 0.1 },
  dragon = { build = dragon, size = 1.12, near = 0.1 },
  chest = { build = chest, size = 0.42, near = 0.5 },
  openChest = { build = openChest, size = 0.42, near = 0.5 },
  potion = { build = potion, size = 0.2, near = 0.4 },
  gold = { build = gold, size = 0.3, near = 0.4 },
  key = { build = key, size = 0.22, near = 0.4 },
  sword = { build = sword, size = 0.32, near = 0.4 },
  armour = { build = armour, size = 0.3, near = 0.4 },
}
M.SPRITES = SPRITES

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

return M
