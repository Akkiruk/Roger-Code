-- games/blightmare/art_battle.lua
-- Everyone in a fight, as shapes in a unit square with the floor along the bottom, the way Dungeon's art works. Foes stand on the
-- left and face right; the party stands on the right and faces left. Bold shapes and one loud colour each, because at 24 cells
-- across fine detail is gone. bake turns a sprite into runs of colour once for each size, and after that it's a short list of fills.

local foes = require("games.blightmare.art_foes")
local ui = require("lib.arcade.ui")

local C = ui.C
local ceil, floor, sin, sqrt = math.ceil, math.floor, math.sin, math.sqrt

local M = {}

-- ---------------------------------------------------------------- shapes

local function E(cx, cy, rx, ry, color) return { kind = "e", cx = cx, cy = cy, rx = rx, ry = ry, color = color } end
local function R(x, y, w, h, color) return { kind = "r", x = x, y = y, w = w, h = h, color = color } end
local function P(color, ...) return { kind = "p", points = { ... }, color = color } end

--- A limb that wanders: from x1, y1 to x2, y2, wide1 thick at the start and wide2 at the end, bending bend either side as it goes.
-- Tentacles, necks and worms are all this.
local function snake(ink, x1, y1, x2, y2, wide1, wide2, bend, waves, phase)
  local out, back = {}, {}
  local dx, dy = x2 - x1, y2 - y1
  local long = sqrt(dx * dx + dy * dy)
  local nx, ny = -dy / long, dx / long
  local steps = 14
  for i = 0, steps do
    local t = i / steps
    local off = sin(t * 3.14159 * (waves or 1) + (phase or 0)) * (bend or 0) * (1 - t * 0.4)
    local half = (wide1 + (wide2 - wide1) * t) / 2
    local cx, cy = x1 + dx * t + nx * off, y1 + dy * t + ny * off
    out[#out + 1] = cx + nx * half
    out[#out + 1] = cy + ny * half
    back[#back + 1] = cy - ny * half
    back[#back + 1] = cx - nx * half
  end
  for i = #back, 1, -1 do out[#out + 1] = back[i] end
  return { kind = "p", points = out, color = ink }
end

--- A big head's many arms of the one list.
local function addAll(list, ...)
  for _, shape in ipairs({ ... }) do list[#list + 1] = shape end
  return list
end

-- ---------------------------------------------------------------- the party

local function hero()
  return {
    P(C.blueTint, 0.62, 0.36, 0.86, 0.42, 0.92, 0.86, 0.68, 0.8),            -- the cloak behind
    R(0.36, 0.72, 0.12, 0.24, C.panel), R(0.54, 0.72, 0.12, 0.24, C.panel),
    R(0.32, 0.92, 0.17, 0.08, C.redTint), R(0.5, 0.92, 0.17, 0.08, C.redTint),
    P(C.blue, 0.3, 0.38, 0.72, 0.38, 0.68, 0.76, 0.32, 0.76),
    R(0.32, 0.6, 0.38, 0.05, C.warn), R(0.46, 0.59, 0.09, 0.07, C.hi),
    E(0.5, 0.22, 0.17, 0.17, C.warn), P(C.redTint, 0.34, 0.2, 0.36, 0.04, 0.6, 0.0, 0.72, 0.1, 0.7, 0.34, 0.58, 0.2), -- hair
    R(0.38, 0.2, 0.05, 0.05, C.bg),
    R(0.14, 0.44, 0.22, 0.08, C.warn), R(0.1, 0.4, 0.06, 0.16, C.hi),         -- the sword arm
    P(C.text, 0.11, 0.4, 0.0, 0.34, 0.03, 0.16, 0.15, 0.4),
  }
end

local function deserter()
  return {
    R(0.38, 0.74, 0.1, 0.24, C.panel), R(0.54, 0.74, 0.1, 0.24, C.panel),
    P(C.line, 0.3, 0.36, 0.72, 0.36, 0.82, 0.84, 0.24, 0.84),                 -- the long Clinic coat
    P(C.text, 0.44, 0.36, 0.58, 0.36, 0.56, 0.84, 0.46, 0.84),
    R(0.62, 0.44, 0.12, 0.1, C.red),                                          -- a torn armband
    E(0.5, 0.22, 0.16, 0.16, C.warn), P(C.tie, 0.3, 0.2, 0.5, 0.0, 0.74, 0.06, 0.74, 0.36, 0.62, 0.26, 0.6, 0.14, 0.4, 0.14),
    R(0.38, 0.2, 0.05, 0.05, C.bg),
    R(0.14, 0.46, 0.2, 0.08, C.line),
    R(0.09, 0.3, 0.07, 0.06, C.redTint), P(C.soft, 0.08, 0.36, 0.17, 0.36, 0.22, 0.52, 0.03, 0.52), -- a flask held up
    E(0.125, 0.46, 0.05, 0.04, C.ok),
  }
end

local function cleric()
  return {
    R(0.8, 0.02, 0.05, 0.96, C.redTint), E(0.825, 0.08, 0.09, 0.08, C.hi),    -- the staff
    P(C.text, 0.34, 0.3, 0.68, 0.3, 0.82, 0.98, 0.2, 0.98),                   -- a pale robe
    P(C.line, 0.5, 0.3, 0.68, 0.3, 0.82, 0.98, 0.62, 0.98),
    R(0.26, 0.86, 0.5, 0.05, C.tie),
    R(0.47, 0.42, 0.07, 0.2, C.hi), R(0.42, 0.47, 0.17, 0.06, C.hi),          -- the charm she hides
    P(C.tie, 0.3, 0.32, 0.36, 0.06, 0.52, 0.0, 0.7, 0.08, 0.72, 0.34),
    E(0.47, 0.2, 0.13, 0.14, C.warn), R(0.39, 0.18, 0.05, 0.05, C.bg),
    R(0.16, 0.44, 0.2, 0.08, C.text),
  }
end

local function owlin()
  return {
    R(0.36, 0.86, 0.1, 0.14, C.warn), R(0.54, 0.86, 0.1, 0.14, C.warn),
    P(C.accent, 0.5, 0.3, 0.92, 0.42, 0.88, 0.84, 0.66, 0.8), P(C.accent, 0.5, 0.3, 0.08, 0.42, 0.12, 0.84, 0.34, 0.8), -- the wings
    E(0.5, 0.6, 0.24, 0.3, C.line), E(0.5, 0.64, 0.14, 0.2, C.text),
    E(0.5, 0.24, 0.26, 0.22, C.line),
    E(0.4, 0.24, 0.09, 0.09, C.text), E(0.62, 0.24, 0.09, 0.09, C.text),
    E(0.38, 0.24, 0.04, 0.05, C.bg), E(0.6, 0.24, 0.04, 0.05, C.bg),
    P(C.warn, 0.46, 0.3, 0.56, 0.3, 0.5, 0.42),
    R(0.28, 0.06, 0.44, 0.05, C.hi), E(0.5, 0.08, 0.05, 0.05, C.info),        -- the circlet
  }
end

local function jezzara()
  return {
    P(C.red, 0.56, 0.1, 0.86, 0.2, 0.9, 0.62, 0.72, 0.56, 0.64, 0.3),         -- the hair, loose
    R(0.38, 0.7, 0.1, 0.28, C.panel), R(0.54, 0.7, 0.1, 0.28, C.panel),
    P(C.tie, 0.34, 0.36, 0.68, 0.36, 0.72, 0.74, 0.3, 0.74),
    R(0.34, 0.6, 0.36, 0.05, C.hi),
    E(0.5, 0.22, 0.16, 0.17, C.warn), P(C.red, 0.34, 0.2, 0.42, 0.03, 0.66, 0.03, 0.7, 0.3, 0.54, 0.14),
    P(C.warn, 0.36, 0.14, 0.34, 0.0, 0.46, 0.08), P(C.warn, 0.58, 0.08, 0.68, 0.0, 0.68, 0.16),  -- cat's ears
    R(0.38, 0.2, 0.09, 0.03, C.tie), R(0.38, 0.22, 0.05, 0.05, C.hi),
    snake(C.panel, 0.66, 0.4, 0.98, 0.04, 0.05, 0.02, 0.06, 1), E(0.98, 0.04, 0.03, 0.03, C.accent),      -- the displacer's arm
    R(0.14, 0.42, 0.22, 0.08, C.warn), P(C.text, 0.15, 0.42, 0.0, 0.3, 0.17, 0.5),
    R(0.68, 0.44, 0.16, 0.08, C.warn), P(C.text, 0.84, 0.44, 1, 0.3, 0.82, 0.52),
  }
end

local function asphodel()
  return {
    P(C.redTint, 0.6, 0.34, 0.88, 0.4, 0.94, 0.9, 0.66, 0.8),
    R(0.36, 0.72, 0.13, 0.26, C.redTint), R(0.54, 0.72, 0.13, 0.26, C.redTint),
    P(C.red, 0.28, 0.34, 0.74, 0.34, 0.7, 0.76, 0.3, 0.76), P(C.tie, 0.46, 0.34, 0.56, 0.34, 0.55, 0.76, 0.47, 0.76),
    snake(C.red, 0.62, 0.72, 0.96, 0.62, 0.05, 0.02, 0.06, 1.4), P(C.red, 0.93, 0.66, 1, 0.56, 0.9, 0.56),   -- the tail
    E(0.5, 0.2, 0.15, 0.16, C.red), P(C.bg, 0.33, 0.16, 0.5, 0.0, 0.68, 0.1, 0.68, 0.34, 0.58, 0.16),
    P(C.text, 0.42, 0.08, 0.3, -0.0, 0.26, 0.14, 0.32, 0.12, 0.36, 0.14), P(C.text, 0.6, 0.06, 0.74, 0.0, 0.76, 0.14, 0.7, 0.12, 0.64, 0.12),  -- the horns
    R(0.38, 0.18, 0.05, 0.05, C.hi),
    R(0.1, 0.46, 0.24, 0.08, C.text),
    P(C.line, 0.13, 0.5, 0.0, 0.02, 0.05, 0.0, 0.19, 0.48), R(0.05, 0.47, 0.16, 0.05, C.red),
  }
end

-- ---------------------------------------------------------------- foes

local function crawler()
  local legs = {}
  for i = 0, 4 do
    local x = 0.14 + i * 0.16
    legs[#legs + 1] = P(C.tie, x, 0.6, x + 0.04, 0.6, x - 0.06, 1, x - 0.1, 1)
  end
  local out = {
    legs[1], legs[2], legs[3], legs[4], legs[5],
    E(0.44, 0.58, 0.42, 0.26, C.redTint), E(0.4, 0.5, 0.34, 0.17, C.red),
    E(0.82, 0.62, 0.15, 0.17, C.red), R(0.26, 0.38, 0.03, 0.34, C.redTint), R(0.46, 0.34, 0.03, 0.38, C.redTint),
    E(0.3, 0.46, 0.06, 0.05, C.accent), E(0.58, 0.44, 0.05, 0.05, C.accent),
    E(0.86, 0.56, 0.05, 0.05, C.hi), E(0.76, 0.54, 0.03, 0.04, C.hi),
    P(C.text, 0.88, 0.72, 0.98, 0.76, 0.86, 0.8),
  }
  return out
end

local function rat()
  return {
    P(C.red, 0.2, 0.74, 0.0, 0.42, 0.04, 0.38, 0.28, 0.66),                   -- the tail, whipping up
    E(0.42, 0.62, 0.3, 0.26, C.tie), E(0.42, 0.72, 0.24, 0.14, C.line),
    P(C.tie, 0.2, 0.42, 0.28, 0.28, 0.34, 0.4, 0.42, 0.24, 0.5, 0.38, 0.58, 0.28, 0.62, 0.42),
    P(C.tie, 0.58, 0.44, 0.86, 0.5, 1, 0.68, 0.78, 0.82, 0.58, 0.78),
    E(0.66, 0.38, 0.08, 0.11, C.line), E(0.66, 0.4, 0.04, 0.07, C.redTint),
    E(0.8, 0.56, 0.04, 0.04, C.red),
    P(C.text, 0.86, 0.72, 0.92, 0.72, 0.88, 0.84), P(C.text, 0.94, 0.7, 0.98, 0.7, 0.95, 0.8),
    R(0.26, 0.86, 0.14, 0.1, C.line), R(0.56, 0.86, 0.14, 0.1, C.line),
  }
end

local function harpy()
  return {
    P(C.blueTint, 0.5, 0.36, 0.2, 0.0, 0.0, 0.1, 0.06, 0.34, 0.0, 0.46, 0.16, 0.5, 0.14, 0.66, 0.4, 0.62),
    P(C.blue, 0.46, 0.36, 0.24, 0.1, 0.1, 0.18, 0.16, 0.42, 0.44, 0.56),
    P(C.warn, 0.42, 0.34, 0.68, 0.34, 0.66, 0.68, 0.46, 0.72),
    E(0.7, 0.2, 0.15, 0.16, C.warn), P(C.accent, 0.52, 0.34, 0.5, 0.06, 0.68, 0.0, 0.82, 0.08, 0.66, 0.14, 0.6, 0.3),
    E(0.76, 0.18, 0.04, 0.04, C.red), P(C.hi, 0.82, 0.22, 0.96, 0.26, 0.82, 0.3),
    R(0.46, 0.7, 0.05, 0.2, C.hi), R(0.6, 0.7, 0.05, 0.2, C.hi),
    P(C.hi, 0.42, 0.9, 0.56, 0.9, 0.58, 1, 0.5, 0.94, 0.44, 1), P(C.hi, 0.56, 0.9, 0.7, 0.9, 0.72, 1, 0.64, 0.94, 0.58, 1),
  }
end

local function frogman()
  return {
    R(0.92, 0.04, 0.04, 0.9, C.redTint), P(C.text, 0.88, 0.1, 0.94, 0.0, 1, 0.1, 0.94, 0.14),  -- the spear
    E(0.26, 0.86, 0.2, 0.13, C.ok), E(0.62, 0.86, 0.2, 0.13, C.ok),
    E(0.44, 0.62, 0.3, 0.28, C.ok), E(0.5, 0.7, 0.18, 0.18, C.soft),
    E(0.54, 0.3, 0.3, 0.2, C.ok), E(0.4, 0.16, 0.12, 0.14, C.hi), E(0.68, 0.16, 0.12, 0.14, C.hi),
    E(0.43, 0.17, 0.05, 0.06, C.bg), E(0.71, 0.17, 0.05, 0.06, C.bg),
    R(0.3, 0.38, 0.54, 0.04, C.bg), R(0.72, 0.5, 0.22, 0.08, C.ok),
  }
end

local function stalker()
  return {
    P(C.tie, 0.14, 0.98, 0.1, 0.5, 0.24, 0.14, 0.56, 0.08, 0.7, 0.3, 0.62, 0.98, 0.5, 0.74, 0.38, 0.98, 0.26, 0.76),
    P(C.panel, 0.2, 0.9, 0.2, 0.5, 0.3, 0.3, 0.3, 0.8),
    E(0.58, 0.22, 0.17, 0.17, C.text), P(C.text, 0.48, 0.3, 0.74, 0.3, 0.66, 0.5),
    E(0.54, 0.2, 0.05, 0.06, C.bg), E(0.68, 0.2, 0.05, 0.06, C.bg),
    E(0.54, 0.21, 0.02, 0.03, C.red), E(0.68, 0.21, 0.02, 0.03, C.red),
    P(C.tie, 0.6, 0.42, 0.9, 0.5, 0.88, 0.56, 0.58, 0.54),
    P(C.text, 0.86, 0.48, 1, 0.42, 0.9, 0.52), P(C.text, 0.87, 0.51, 1, 0.56, 0.88, 0.56), P(C.text, 0.87, 0.54, 0.96, 0.68, 0.84, 0.57),
  }
end

local function orderly()
  return {
    R(0.32, 0.72, 0.14, 0.26, C.tie), R(0.54, 0.72, 0.14, 0.26, C.tie),
    P(C.line, 0.28, 0.34, 0.72, 0.34, 0.74, 0.76, 0.26, 0.76), R(0.46, 0.34, 0.09, 0.42, C.text),
    R(0.42, 0.42, 0.17, 0.06, C.red), R(0.47, 0.37, 0.07, 0.16, C.red),       -- the red cross of the Clinic
    E(0.5, 0.2, 0.16, 0.16, C.warn), R(0.33, 0.04, 0.34, 0.12, C.text), R(0.33, 0.14, 0.38, 0.03, C.line),
    R(0.44, 0.24, 0.26, 0.14, C.text),                                        -- the mask
    R(0.58, 0.18, 0.05, 0.05, C.bg),
    R(0.7, 0.44, 0.14, 0.08, C.line), P(C.warn, 0.78, 0.5, 0.94, 0.12, 1, 0.16, 0.86, 0.54),   -- the baton
  }
end

local function doctor()
  return {
    P(C.tie, 0.26, 0.34, 0.68, 0.34, 0.8, 0.98, 0.14, 0.98),                  -- a long dark coat
    P(C.panel, 0.4, 0.34, 0.56, 0.34, 0.6, 0.98, 0.34, 0.98),
    R(0.1, 0.2, 0.74, 0.05, C.line), R(0.28, 0.0, 0.38, 0.2, C.tie),          -- the hat
    E(0.48, 0.3, 0.14, 0.11, C.line), P(C.line, 0.56, 0.25, 0.98, 0.42, 0.56, 0.38), -- the beak mask
    E(0.52, 0.3, 0.035, 0.035, C.red),
    R(0.68, 0.5, 0.18, 0.07, C.tie), R(0.82, 0.54, 0.03, 0.08, C.line),
    R(0.76, 0.62, 0.15, 0.2, C.hi), R(0.8, 0.66, 0.07, 0.12, C.text),         -- the lantern
  }
end

local function blighted()
  return {
    R(0.3, 0.72, 0.13, 0.26, C.redTint), R(0.54, 0.74, 0.12, 0.24, C.tie),
    P(C.redTint, 0.26, 0.38, 0.68, 0.34, 0.72, 0.78, 0.22, 0.8, 0.3, 0.6),
    E(0.58, 0.26, 0.17, 0.18, C.soft), P(C.tie, 0.42, 0.24, 0.48, 0.06, 0.72, 0.06, 0.7, 0.14, 0.52, 0.18),
    E(0.64, 0.24, 0.05, 0.05, C.red), E(0.72, 0.36, 0.05, 0.03, C.bg),
    E(0.42, 0.26, 0.09, 0.1, C.accent), E(0.32, 0.5, 0.1, 0.09, C.accent), E(0.6, 0.62, 0.08, 0.07, C.accent), -- growths
    E(0.3, 0.48, 0.03, 0.03, C.hiTint),
    P(C.soft, 0.62, 0.42, 0.98, 0.5, 0.96, 0.58, 0.6, 0.54),
    P(C.soft, 0.94, 0.48, 1, 0.42, 0.97, 0.58),
  }
end

local function miner()
  return {
    P(C.redTint, 0.84, 0.0, 0.9, 0.0, 0.96, 0.74, 0.9, 0.74),                 -- the haft
    P(C.line, 0.62, 0.1, 0.84, 0.0, 1, 0.1, 1, 0.16, 0.84, 0.08, 0.64, 0.16),
    R(0.26, 0.8, 0.18, 0.2, C.redTint), R(0.5, 0.8, 0.18, 0.2, C.redTint),
    E(0.46, 0.64, 0.32, 0.26, C.blueTint), R(0.2, 0.68, 0.54, 0.05, C.warn),
    E(0.46, 0.36, 0.22, 0.2, C.soft),
    P(C.line, 0.28, 0.4, 0.68, 0.4, 0.6, 0.74, 0.5, 0.82, 0.36, 0.72),        -- the beard
    E(0.56, 0.32, 0.05, 0.05, C.red),
    P(C.hi, 0.22, 0.28, 0.26, 0.1, 0.46, 0.04, 0.66, 0.1, 0.72, 0.28), R(0.18, 0.26, 0.58, 0.05, C.warn),
    E(0.72, 0.17, 0.06, 0.06, C.text),
    E(0.22, 0.46, 0.1, 0.09, C.accent), E(0.66, 0.58, 0.07, 0.06, C.accent),
    R(0.68, 0.56, 0.2, 0.08, C.soft),
  }
end

local function foreman()
  return {
    -- the great pick, raised over him
    P(C.redTint, 0.82, 0.0, 0.89, 0.0, 0.96, 0.82, 0.89, 0.82),
    P(C.line, 0.5, 0.1, 0.82, 0.0, 1, 0.08, 1, 0.18, 0.84, 0.1, 0.54, 0.18), P(C.text, 0.84, 0.0, 1, 0.08, 1, 0.12, 0.84, 0.04),
    R(0.2, 0.86, 0.26, 0.14, C.redTint), R(0.52, 0.86, 0.26, 0.14, C.redTint),
    R(0.16, 0.94, 0.32, 0.06, C.panel), R(0.5, 0.94, 0.32, 0.06, C.panel),
    E(0.48, 0.66, 0.42, 0.3, C.blue), P(C.blueTint, 0.14, 0.5, 0.82, 0.5, 0.86, 0.92, 0.1, 0.92),
    R(0.14, 0.76, 0.7, 0.06, C.warn), R(0.42, 0.74, 0.12, 0.1, C.hi),
    R(0.26, 0.46, 0.08, 0.32, C.hi), R(0.62, 0.46, 0.08, 0.32, C.hi),          -- the braces of the job he still holds
    E(0.48, 0.34, 0.24, 0.2, C.soft),
    P(C.text, 0.24, 0.38, 0.72, 0.38, 0.66, 0.68, 0.48, 0.8, 0.3, 0.68),       -- a beard gone white
    P(C.line, 0.38, 0.5, 0.58, 0.5, 0.52, 0.72, 0.44, 0.72),
    R(0.3, 0.3, 0.14, 0.05, C.bg), R(0.52, 0.3, 0.14, 0.05, C.bg),
    E(0.37, 0.33, 0.035, 0.03, C.red), E(0.59, 0.33, 0.035, 0.03, C.red),
    P(C.hi, 0.2, 0.26, 0.24, 0.08, 0.48, 0.02, 0.72, 0.08, 0.78, 0.26), R(0.14, 0.24, 0.7, 0.05, C.warn),
    E(0.48, 0.15, 0.07, 0.06, C.text),                                         -- the helmet lamp
    E(0.14, 0.5, 0.14, 0.13, C.accent), E(0.08, 0.66, 0.07, 0.08, C.accent), E(0.2, 0.42, 0.06, 0.05, C.hiTint), -- what's taken him
    E(0.76, 0.56, 0.08, 0.08, C.accent),
    E(0.84, 0.62, 0.09, 0.08, C.soft),
  }
end

-- ---- the Heart, the Gutter, and things that are only hungry

local function bat()
  return {
    P(C.tie, 0.5, 0.36, 0.3, 0.1, 0.0, 0.2, 0.04, 0.5, 0.12, 0.44, 0.16, 0.66, 0.26, 0.54, 0.36, 0.72, 0.48, 0.6),
    P(C.tie, 0.62, 0.36, 0.76, 0.1, 1, 0.2, 0.98, 0.48, 0.9, 0.44, 0.86, 0.64, 0.8, 0.54, 0.74, 0.7, 0.66, 0.6),
    P(C.panel, 0.48, 0.42, 0.3, 0.2, 0.12, 0.26, 0.2, 0.46, 0.4, 0.56), P(C.panel, 0.66, 0.42, 0.76, 0.2, 0.92, 0.26, 0.86, 0.46, 0.68, 0.56),
    E(0.57, 0.56, 0.12, 0.2, C.redTint), E(0.57, 0.36, 0.12, 0.12, C.redTint),
    P(C.redTint, 0.47, 0.3, 0.46, 0.1, 0.55, 0.26), P(C.redTint, 0.67, 0.3, 0.68, 0.1, 0.59, 0.26),
    E(0.61, 0.34, 0.03, 0.03, C.red), E(0.53, 0.34, 0.03, 0.03, C.red), R(0.52, 0.42, 0.1, 0.03, C.bg),
    P(C.text, 0.53, 0.44, 0.56, 0.44, 0.545, 0.5), P(C.text, 0.59, 0.44, 0.62, 0.44, 0.605, 0.5),
  }
end

--- Fat with someone else, and rearing up towards you.
local function leech()
  local list = { snake(C.redTint, 0.02, 0.86, 0.74, 0.34, 0.2, 0.34, 0.16, 1) }
  for i = 1, 6 do
    local t = i / 7
    local x, y = 0.02 + 0.72 * t + 0.09 * sin(t * 3.14), 0.86 - 0.52 * t + 0.13 * sin(t * 3.14)
    list[#list + 1] = E(x, y, 0.03, 0.14 + t * 0.03, C.bg)
    list[#list + 1] = E(x + 0.03, y - 0.05, 0.022, 0.05, C.red)
  end
  return addAll(list,
    E(0.8, 0.32, 0.15, 0.18, C.tie), E(0.83, 0.32, 0.11, 0.13, C.red), E(0.84, 0.32, 0.06, 0.08, C.bg),
    P(C.text, 0.76, 0.24, 0.79, 0.28, 0.82, 0.25), P(C.text, 0.92, 0.28, 0.87, 0.3, 0.89, 0.25), P(C.text, 0.91, 0.38, 0.86, 0.35, 0.88, 0.41), P(C.text, 0.78, 0.42, 0.8, 0.37, 0.83, 0.4),
    E(0.14, 0.92, 0.3, 0.05, C.red))
end

local function skeleton()
  local list = {
    R(0.36, 0.72, 0.07, 0.28, C.line), R(0.56, 0.72, 0.07, 0.28, C.text), R(0.32, 0.95, 0.13, 0.05, C.line), R(0.54, 0.95, 0.15, 0.05, C.text),
    E(0.5, 0.68, 0.17, 0.07, C.line), R(0.47, 0.34, 0.06, 0.34, C.text),
  }
  for i = 0, 3 do list[#list + 1] = R(0.33 + i * 0.015, 0.36 + i * 0.07, 0.34 - i * 0.03, 0.035, i % 2 == 0 and C.text or C.line) end
  return addAll(list,
    E(0.52, 0.17, 0.16, 0.16, C.text), R(0.45, 0.28, 0.16, 0.08, C.line), E(0.46, 0.16, 0.05, 0.05, C.bg), E(0.6, 0.16, 0.05, 0.05, C.bg), E(0.6, 0.16, 0.015, 0.015, C.red),
    R(0.48, 0.3, 0.012, 0.05, C.bg), R(0.52, 0.3, 0.012, 0.05, C.bg), R(0.56, 0.3, 0.012, 0.05, C.bg),
    P(C.line, 0.3, 0.36, 0.34, 0.36, 0.22, 0.7, 0.18, 0.68), R(0.14, 0.68, 0.1, 0.03, C.text),
    P(C.text, 0.68, 0.36, 0.72, 0.36, 0.82, 0.52, 0.79, 0.54), R(0.78, 0.5, 0.1, 0.05, C.line), P(C.redTint, 0.84, 0.54, 0.88, 0.5, 0.99, 0.06, 0.95, 0.04))
end

--- A crown of them, and the wings have been dipped in something.
local function harpyQueen()
  return {
    P(C.redTint, 0.46, 0.4, 0.3, 0.02, 0.0, 0.04, 0.02, 0.4, 0.0, 0.54, 0.12, 0.54, 0.08, 0.76, 0.26, 0.64, 0.3, 0.82, 0.46, 0.66),
    P(C.red, 0.44, 0.38, 0.28, 0.1, 0.1, 0.12, 0.12, 0.4, 0.3, 0.6),
    P(C.accent, 0.42, 0.38, 0.3, 0.2, 0.2, 0.22, 0.22, 0.4, 0.34, 0.54),
    P(C.line, 0.42, 0.38, 0.72, 0.38, 0.68, 0.76, 0.46, 0.8),
    P(C.text, 0.48, 0.38, 0.68, 0.38, 0.62, 0.56, 0.5, 0.56),
    E(0.72, 0.22, 0.15, 0.16, C.line), P(C.accent, 0.52, 0.4, 0.5, 0.08, 0.68, 0.06, 0.84, 0.1, 0.66, 0.16, 0.6, 0.34),
    E(0.78, 0.2, 0.04, 0.04, C.hi), P(C.hi, 0.84, 0.24, 1, 0.3, 0.84, 0.33),
    P(C.hi, 0.6, 0.08, 0.86, 0.08, 0.9, -0.02, 0.8, 0.03, 0.74, -0.04, 0.68, 0.03, 0.57, -0.02), E(0.73, 0.06, 0.02, 0.02, C.red),
    R(0.48, 0.76, 0.06, 0.14, C.hi), R(0.62, 0.76, 0.06, 0.14, C.hi),
    P(C.hi, 0.4, 0.88, 0.56, 0.88, 0.62, 1, 0.53, 0.94, 0.5, 1, 0.47, 0.94, 0.42, 1), P(C.hi, 0.56, 0.88, 0.72, 0.88, 0.8, 1, 0.68, 0.94, 0.65, 1, 0.62, 0.94, 0.58, 1),
    P(C.red, 0.74, 0.28, 0.74, 0.34, 0.68, 0.5, 0.66, 0.48),
  }
end

-- ---- Sindal's people

--- Happy. Terribly happy. Eyes shut, a ribbon at the neck, and two small marks under it.
local function thrall()
  return {
    R(0.36, 0.72, 0.11, 0.26, C.line), R(0.54, 0.72, 0.11, 0.26, C.line), R(0.33, 0.94, 0.15, 0.06, C.tie), R(0.53, 0.94, 0.15, 0.06, C.tie),
    P(C.text, 0.3, 0.34, 0.72, 0.34, 0.76, 0.76, 0.26, 0.76), P(C.line, 0.54, 0.34, 0.72, 0.34, 0.76, 0.76, 0.6, 0.76),
    P(C.red, 0.42, 0.33, 0.62, 0.33, 0.56, 0.4, 0.62, 0.62, 0.53, 0.5, 0.46, 0.62, 0.5, 0.4),
    R(0.68, 0.36, 0.09, 0.26, C.text), E(0.73, 0.64, 0.05, 0.05, C.line), P(C.text, 0.7, 0.66, 0.74, 0.66, 0.99, 0.5, 0.98, 0.47),
    R(0.24, 0.36, 0.09, 0.28, C.text), E(0.28, 0.66, 0.05, 0.05, C.line),
    E(0.53, 0.2, 0.15, 0.16, C.line), P(C.hi, 0.37, 0.18, 0.4, 0.04, 0.54, 0.0, 0.68, 0.05, 0.7, 0.18, 0.62, 0.11, 0.46, 0.11),
    R(0.46, 0.2, 0.08, 0.02, C.bg), R(0.58, 0.2, 0.08, 0.02, C.bg),
    P(C.bg, 0.48, 0.25, 0.54, 0.28, 0.6, 0.28, 0.66, 0.25, 0.6, 0.3, 0.52, 0.3),
    R(0.5, 0.33, 0.015, 0.015, C.red), R(0.54, 0.33, 0.015, 0.015, C.red),
  }
end

--- A Stitcher of Sindal's army: black plate, and a blade made for going in, not for swinging.
local function vampireKnight()
  return {
    P(C.redTint, 0.3, 0.3, 0.06, 0.34, 0.0, 0.98, 0.3, 0.9, 0.46, 0.8),
    R(0.32, 0.72, 0.14, 0.26, C.panel), R(0.54, 0.72, 0.14, 0.26, C.panel), R(0.3, 0.94, 0.18, 0.06, C.tie), R(0.52, 0.94, 0.2, 0.06, C.tie),
    P(C.panel, 0.26, 0.32, 0.74, 0.32, 0.7, 0.76, 0.3, 0.76), P(C.tie, 0.44, 0.32, 0.74, 0.32, 0.7, 0.54, 0.46, 0.6),
    P(C.red, 0.4, 0.7, 0.62, 0.7, 0.66, 0.9, 0.36, 0.9), R(0.28, 0.66, 0.44, 0.05, C.hi),
    E(0.26, 0.34, 0.1, 0.07, C.tie), E(0.74, 0.34, 0.1, 0.07, C.tie),
    E(0.54, 0.18, 0.15, 0.17, C.panel), P(C.tie, 0.42, 0.14, 0.7, 0.1, 0.72, 0.2, 0.42, 0.24),
    E(0.58, 0.22, 0.09, 0.09, C.text), R(0.54, 0.19, 0.05, 0.03, C.red), R(0.62, 0.19, 0.05, 0.03, C.red),
    R(0.55, 0.26, 0.09, 0.015, C.bg), R(0.56, 0.26, 0.012, 0.03, C.text), R(0.62, 0.26, 0.012, 0.03, C.text),
    P(C.red, 0.46, 0.04, 0.58, 0.0, 0.34, 0.0, 0.2, 0.14, 0.34, 0.08),
    R(0.74, 0.46, 0.14, 0.07, C.tie), E(0.86, 0.5, 0.06, 0.06, C.hi), R(0.86, 0.485, 0.14, 0.03, C.text),
  }
end

-- ---- under the world

local function mindflayer()
  local list = {
    P(C.blueTint, 0.34, 0.34, 0.68, 0.34, 0.84, 1, 0.16, 1), P(C.accent, 0.42, 0.34, 0.6, 0.34, 0.62, 1, 0.38, 1), R(0.2, 0.86, 0.6, 0.04, C.hi),
    P(C.hi, 0.26, 0.42, 0.74, 0.42, 0.82, 0.26, 0.68, 0.36, 0.34, 0.36, 0.2, 0.26),       -- the collar, as high as its head
    E(0.52, 0.17, 0.2, 0.17, C.accent), E(0.46, 0.1, 0.12, 0.07, C.soft),
    E(0.64, 0.19, 0.05, 0.05, C.text), E(0.5, 0.2, 0.04, 0.05, C.text), E(0.645, 0.195, 0.022, 0.03, C.bg),
  }
  for i = 0, 3 do
    list[#list + 1] = snake(i % 2 == 0 and C.soft or C.accent, 0.46 + i * 0.075, 0.28, 0.44 + i * 0.12, 0.62 + (i % 2) * 0.1, 0.085, 0.02, 0.05, 2, i)
  end
  return addAll(list,
    R(0.7, 0.42, 0.16, 0.07, C.blueTint), E(0.86, 0.45, 0.05, 0.05, C.accent),
    E(0.94, 0.38, 0.07, 0.07, C.soft), E(0.94, 0.38, 0.04, 0.04, C.text))
end

local function spiderLegs(list, ink, dark)
  for i = 0, 3 do
    local knee, y = 0.08 + i * 0.1, 0.44 + i * 0.03
    list[#list + 1] = P(i % 2 == 0 and dark or ink, 0.34 + i * 0.03, 0.66, knee, y, knee - 0.08, 1, knee - 0.03, 1, knee + 0.04, y + 0.08, 0.36 + i * 0.03, 0.74)
    list[#list + 1] = P(i % 2 == 1 and dark or ink, 0.56 + i * 0.03, 0.66, 0.56 + i * 0.13, y - 0.04, 0.68 + i * 0.1, 1, 0.64 + i * 0.1, 1, 0.53 + i * 0.13, y + 0.04, 0.54 + i * 0.03, 0.74)
  end
  return list
end

local function drider()
  local list = spiderLegs({}, C.line, C.tie)
  return addAll(list,
    E(0.28, 0.68, 0.26, 0.2, C.line), E(0.26, 0.64, 0.17, 0.1, C.tie), E(0.2, 0.7, 0.05, 0.05, C.red),
    E(0.54, 0.66, 0.15, 0.13, C.line),
    P(C.blueTint, 0.46, 0.3, 0.68, 0.3, 0.64, 0.58, 0.46, 0.6), P(C.accent, 0.5, 0.3, 0.64, 0.3, 0.6, 0.44, 0.52, 0.46),
    E(0.58, 0.17, 0.12, 0.14, C.blueTint), P(C.text, 0.42, 0.34, 0.44, 0.1, 0.56, 0.0, 0.7, 0.05, 0.7, 0.14, 0.56, 0.1, 0.52, 0.36),
    P(C.blueTint, 0.68, 0.16, 0.78, 0.1, 0.69, 0.22), R(0.6, 0.15, 0.05, 0.03, C.red),
    R(0.66, 0.36, 0.2, 0.05, C.blueTint), R(0.84, 0.04, 0.03, 0.96, C.redTint), P(C.text, 0.8, 0.08, 0.855, -0.06, 0.91, 0.08))
end

--- The drider's labourers: a fat hunched thing with a spider's jaws, and silk hanging off its hands.
local function ettercap()
  local list = {
    E(0.26, 0.56, 0.24, 0.26, C.tie), E(0.22, 0.5, 0.13, 0.13, C.line), E(0.2, 0.46, 0.04, 0.04, C.red), E(0.28, 0.54, 0.03, 0.03, C.red),
    R(0.34, 0.74, 0.1, 0.24, C.ok), R(0.54, 0.74, 0.1, 0.24, C.ok), P(C.line, 0.3, 0.96, 0.46, 0.96, 0.5, 1, 0.28, 1), P(C.line, 0.52, 0.96, 0.66, 0.96, 0.72, 1, 0.5, 1),
    E(0.54, 0.56, 0.22, 0.26, C.ok), E(0.6, 0.6, 0.12, 0.17, C.soft),
    E(0.7, 0.28, 0.17, 0.15, C.ok), E(0.74, 0.22, 0.04, 0.04, C.red), E(0.84, 0.24, 0.03, 0.03, C.red), E(0.66, 0.2, 0.02, 0.02, C.red),
    P(C.text, 0.74, 0.36, 0.8, 0.36, 0.72, 0.52), P(C.text, 0.82, 0.36, 0.88, 0.36, 0.88, 0.52),
    R(0.68, 0.46, 0.2, 0.07, C.ok),
  }
  for i = 0, 2 do list[#list + 1] = P(C.line, 0.86 + i * 0.03, 0.46, 0.89 + i * 0.03, 0.46, 0.9 + i * 0.04, 0.58, 0.87 + i * 0.04, 0.58) end
  return addAll(list, P(C.text, 0.9, 0.56, 0.96, 0.56, 1, 0.98, 0.84, 0.98), R(0.86, 0.68, 0.13, 0.015, C.line), R(0.85, 0.8, 0.14, 0.015, C.line))
end

--- A bear that a spell got wrong, and an owl's face that stares without blinking.
local function owlBeast()
  return {
    R(0.24, 0.8, 0.18, 0.2, C.redTint), R(0.56, 0.8, 0.18, 0.2, C.redTint),
    E(0.46, 0.62, 0.38, 0.32, C.redTint), E(0.46, 0.66, 0.26, 0.24, C.tie), E(0.5, 0.72, 0.16, 0.16, C.line),
    R(0.42, 0.56, 0.06, 0.02, C.line), R(0.54, 0.62, 0.06, 0.02, C.line), R(0.44, 0.72, 0.06, 0.02, C.tie), R(0.56, 0.76, 0.06, 0.02, C.tie),
    E(0.6, 0.28, 0.25, 0.23, C.redTint), P(C.redTint, 0.38, 0.2, 0.36, 0.0, 0.5, 0.1), P(C.redTint, 0.82, 0.2, 0.86, 0.0, 0.7, 0.1),
    E(0.5, 0.28, 0.12, 0.13, C.line), E(0.72, 0.28, 0.12, 0.13, C.line), E(0.5, 0.28, 0.09, 0.1, C.hi), E(0.72, 0.28, 0.09, 0.1, C.hi), E(0.52, 0.29, 0.04, 0.05, C.bg), E(0.74, 0.29, 0.04, 0.05, C.bg),
    P(C.hi, 0.56, 0.32, 0.66, 0.32, 0.61, 0.46),
    R(0.76, 0.5, 0.2, 0.09, C.redTint), P(C.text, 0.92, 0.5, 1, 0.48, 0.95, 0.54), P(C.text, 0.93, 0.54, 1, 0.56, 0.93, 0.59),
    E(0.16, 0.56, 0.08, 0.1, C.redTint),
  }
end

--- All eye. It knows something about you, and it's hungry to know more.
local function nothic()
  return {
    R(0.3, 0.72, 0.1, 0.2, C.tie), R(0.52, 0.72, 0.1, 0.2, C.tie), P(C.line, 0.26, 0.92, 0.44, 0.92, 0.46, 1, 0.24, 1), P(C.line, 0.48, 0.92, 0.66, 0.92, 0.7, 1, 0.46, 1),
    P(C.tie, 0.14, 0.76, 0.2, 0.38, 0.5, 0.34, 0.74, 0.76), P(C.panel, 0.18, 0.74, 0.24, 0.44, 0.4, 0.42, 0.42, 0.74),
    R(0.22, 0.44, 0.09, 0.42, C.tie), P(C.text, 0.2, 0.86, 0.32, 0.86, 0.28, 0.98),
    E(0.58, 0.3, 0.3, 0.27, C.tie), P(C.tie, 0.34, 0.14, 0.24, 0.02, 0.44, 0.08), P(C.tie, 0.78, 0.12, 0.92, 0.02, 0.74, 0.04),
    E(0.6, 0.28, 0.21, 0.19, C.bg), E(0.6, 0.28, 0.185, 0.165, C.text), E(0.63, 0.28, 0.11, 0.13, C.soft), E(0.64, 0.28, 0.035, 0.12, C.bg), E(0.54, 0.22, 0.03, 0.025, C.text),
    R(0.46, 0.5, 0.26, 0.04, C.bg), P(C.text, 0.48, 0.5, 0.52, 0.5, 0.5, 0.56), P(C.text, 0.56, 0.5, 0.6, 0.5, 0.58, 0.56), P(C.text, 0.64, 0.5, 0.68, 0.5, 0.66, 0.56),
    R(0.68, 0.58, 0.18, 0.07, C.tie), P(C.text, 0.84, 0.56, 1, 0.5, 0.88, 0.6), P(C.text, 0.84, 0.6, 1, 0.66, 0.86, 0.65),
  }
end

--- It lives in the chains, and from any distance you can't tell where it stops and they start.
local function chainWorm()
  local list = {}
  for i = 0, 2 do
    local x = 0.12 + i * 0.3
    for y = -1, 11 do
      list[#list + 1] = y % 2 == 0 and R(x - 0.05, y * 0.095, 0.1, 0.09, C.tie) or R(x - 0.018, y * 0.095 - 0.01, 0.036, 0.11, C.line)
      if y % 2 == 0 then list[#list + 1] = R(x - 0.025, y * 0.095 + 0.02, 0.05, 0.05, C.bg) end
    end
  end
  list[#list + 1] = snake(C.line, 0.0, 0.8, 0.8, 0.3, 0.34, 0.36, 0.26, 2.2, 0.4)
  for i = 1, 11 do
    local t = i / 12
    local x, y = 0.8 * t, 0.8 - 0.5 * t
    local off = sin(t * 3.14159 * 2.2 + 0.4) * 0.26 * (1 - t * 0.4)
    list[#list + 1] = E(x + off * 0.53, y + off * 0.85, 0.035, 0.15, i % 2 == 0 and C.tie or C.panel)
  end
  return addAll(list,
    E(0.8, 0.28, 0.2, 0.22, C.tie), E(0.8, 0.27, 0.15, 0.17, C.text), E(0.84, 0.27, 0.09, 0.12, C.soft), E(0.85, 0.27, 0.03, 0.11, C.bg),
    P(C.text, 0.64, 0.42, 0.7, 0.44, 0.65, 0.54), P(C.text, 0.76, 0.48, 0.82, 0.48, 0.79, 0.6), P(C.text, 0.88, 0.46, 0.94, 0.42, 0.93, 0.56))
end

-- ---- the great ones. These are for a big box: see M.bigBox.

--- What was left of Vierrela once it had finished: the crown, the robes, and nobody holding them up.
local function vierrelaHusk()
  local list = {
    P(C.accent, 0.34, 0.34, 0.66, 0.34, 0.82, 0.92, 0.7, 0.86, 0.6, 1, 0.5, 0.88, 0.4, 1, 0.3, 0.86, 0.16, 0.94),
    P(C.blueTint, 0.42, 0.34, 0.58, 0.34, 0.62, 0.9, 0.5, 0.84, 0.4, 0.9),
    R(0.3, 0.38, 0.4, 0.03, C.text),
  }
  for i = 0, 3 do
    list[#list + 1] = snake(i % 2 == 0 and C.soft or C.ok, 0.34 + i * 0.1, 0.6, 0.1 + i * 0.27, 1, 0.05, 0.012, 0.07, 2.5, i)
  end
  return addAll(list,
    P(C.blueTint, 0.34, 0.42, 0.24, 0.5, 0.12, 0.76, 0.17, 0.78, 0.3, 0.58), P(C.blueTint, 0.66, 0.42, 0.78, 0.5, 0.92, 0.72, 0.87, 0.76, 0.7, 0.58),
    E(0.5, 0.2, 0.15, 0.17, C.blueTint),
    P(C.text, 0.4, 0.08, 0.33, 0.14, 0.27, 0.56, 0.33, 0.5, 0.37, 0.56, 0.4, 0.24), P(C.text, 0.6, 0.08, 0.67, 0.14, 0.73, 0.56, 0.67, 0.5, 0.63, 0.56, 0.6, 0.24), E(0.5, 0.12, 0.12, 0.08, C.bg), E(0.5, 0.11, 0.08, 0.05, C.soft),      -- the top of her head isn't there
    R(0.34, 0.06, 0.32, 0.02, C.soft), P(C.soft, 0.42, 0.06, 0.5, -0.02, 0.58, 0.06),
    E(0.44, 0.22, 0.035, 0.03, C.text), E(0.56, 0.22, 0.035, 0.03, C.text),
    P(C.bg, 0.44, 0.27, 0.56, 0.27, 0.54, 0.34, 0.46, 0.34))
end

--- She got what she came for. There's a good deal of her still in there, and that's the worst of it.
local function coletteChanged()
  local list = {}
  for i = 0, 2 do
    list[#list + 1] = snake(i == 1 and C.soft or C.tie, 0.46, 0.34, 0.06 + i * 0.06, 0.02 + i * 0.22, 0.08, 0.012, 0.09, 2, i)
    list[#list + 1] = snake(i == 1 and C.tie or C.line, 0.56, 0.36, 0.98, 0.1 + i * 0.24, 0.07, 0.012, 0.08, 2.4, i + 1)
  end
  return addAll(list,
    P(C.line, 0.38, 0.32, 0.62, 0.32, 0.7, 0.96, 0.62, 0.86, 0.55, 1, 0.47, 0.88, 0.38, 1, 0.34, 0.86, 0.28, 0.98),
    P(C.text, 0.44, 0.32, 0.56, 0.32, 0.58, 0.9, 0.5, 0.8, 0.42, 0.92),
    R(0.46, 0.4, 0.09, 0.03, C.red), R(0.49, 0.36, 0.03, 0.12, C.red),
    E(0.46, 0.66, 0.05, 0.1, C.red), R(0.52, 0.6, 0.015, 0.34, C.red),
    E(0.52, 0.18, 0.13, 0.16, C.line), P(C.tie, 0.38, 0.22, 0.34, 0.02, 0.48, 0.0, 0.42, 0.06, 0.6, 0.0, 0.7, 0.06, 0.64, 0.12, 0.72, 0.24, 0.62, 0.1, 0.42, 0.1),
    P(C.line, 0.4, 0.16, 0.26, 0.1, 0.4, 0.22), P(C.line, 0.64, 0.14, 0.78, 0.08, 0.64, 0.22),                  -- an elf's ears, still
    R(0.44, 0.17, 0.06, 0.03, C.red), R(0.55, 0.17, 0.06, 0.03, C.red),
    R(0.44, 0.26, 0.16, 0.015, C.bg), R(0.46, 0.25, 0.01, 0.035, C.bg), R(0.5, 0.25, 0.01, 0.035, C.bg), R(0.54, 0.25, 0.01, 0.035, C.bg), R(0.58, 0.25, 0.01, 0.035, C.bg),
    E(0.62, 0.3, 0.06, 0.05, C.soft), E(0.66, 0.26, 0.04, 0.04, C.ok), E(0.38, 0.44, 0.06, 0.07, C.soft), E(0.61, 0.56, 0.05, 0.06, C.ok), E(0.63, 0.5, 0.03, 0.03, C.soft),
    R(0.42, 0.5, 0.2, 0.15, C.redTint), R(0.46, 0.53, 0.12, 0.09, C.red), E(0.52, 0.575, 0.025, 0.03, C.text))  -- the Tome, and it's open
end

--- The Clinic's surgeon-general. Rank is the length of the beak, and he has had to stoop for doors for years.
local function plagueSurgeon()
  return {
    P(C.tie, 0.22, 0.36, 0.66, 0.36, 0.8, 0.98, 0.1, 0.98),
    P(C.line, 0.3, 0.42, 0.62, 0.42, 0.68, 0.96, 0.24, 0.96), R(0.3, 0.42, 0.32, 0.02, C.panel),
    E(0.4, 0.62, 0.09, 0.11, C.red), E(0.52, 0.8, 0.07, 0.07, C.red), R(0.42, 0.7, 0.02, 0.26, C.red), E(0.34, 0.86, 0.04, 0.05, C.redTint),
    R(0.04, 0.17, 0.72, 0.05, C.bg), P(C.bg, 0.24, 0.17, 0.3, 0.0, 0.56, 0.0, 0.6, 0.17), R(0.26, 0.13, 0.32, 0.03, C.red),
    E(0.43, 0.28, 0.17, 0.12, C.text), P(C.text, 0.5, 0.21, 0.82, 0.26, 1, 0.42, 0.97, 0.56, 0.88, 0.42, 0.5, 0.38), P(C.line, 0.5, 0.33, 0.88, 0.42, 0.5, 0.38),
    E(0.48, 0.27, 0.05, 0.05, C.bg), E(0.48, 0.27, 0.03, 0.03, C.info),
    R(0.66, 0.48, 0.14, 0.07, C.tie), E(0.8, 0.5, 0.04, 0.04, C.line),                                     -- the arm with the saw
    P(C.line, 0.78, 0.48, 0.84, 0.48, 0.96, 0.72, 0.84, 0.76), P(C.text, 0.84, 0.76, 0.86, 0.72, 0.89, 0.74, 0.9, 0.7, 0.93, 0.72, 0.95, 0.68, 0.96, 0.72), R(0.74, 0.44, 0.08, 0.05, C.redTint),
    P(C.red, 0.86, 0.6, 0.92, 0.6, 0.9, 0.7),
    R(0.12, 0.5, 0.14, 0.07, C.tie), E(0.12, 0.54, 0.04, 0.04, C.line), P(C.text, 0.1, 0.52, 0.06, 0.34, 0.03, 0.34, 0.08, 0.54),   -- and the one with the knife
    R(0.14, 0.62, 0.05, 0.3, C.redTint), R(0.09, 0.66, 0.15, 0.2, C.hi), R(0.13, 0.7, 0.07, 0.12, C.text), R(0.08, 0.64, 0.17, 0.02, C.bg),
  }
end

--- A thin white dragon with a gecko's face and eyes that bulge. He has eaten other dragons, and looks as if he's still hungry.
local function chylbad()
  local list = {
    snake(C.line, 0.3, 0.7, 0.0, 0.96, 0.14, 0.012, 0.09, 2, 1),                                          -- the long tail
    P(C.tie, 0.42, 0.46, 0.34, 0.0, 0.08, 0.02, 0.0, 0.34, 0.08, 0.28, 0.1, 0.5, 0.2, 0.36, 0.24, 0.6, 0.34, 0.44, 0.38, 0.62),  -- wings like old sails
    P(C.line, 0.42, 0.46, 0.36, 0.04, 0.32, 0.03, 0.34, 0.46),
    P(C.line, 0.36, 0.05, 0.1, 0.05, 0.1, 0.08, 0.34, 0.1),
    P(C.panel, 0.34, 0.1, 0.16, 0.1, 0.1, 0.26, 0.16, 0.4, 0.22, 0.26, 0.28, 0.46, 0.33, 0.3),
    P(C.line, 0.34, 0.8, 0.26, 0.98, 0.33, 1, 0.42, 0.82), P(C.line, 0.56, 0.78, 0.6, 0.98, 0.67, 1, 0.64, 0.78),
    P(C.text, 0.24, 0.98, 0.36, 0.98, 0.38, 1, 0.22, 1), P(C.text, 0.58, 0.98, 0.7, 0.98, 0.74, 1, 0.56, 1),
    E(0.46, 0.66, 0.24, 0.17, C.text), E(0.48, 0.72, 0.17, 0.09, C.line),
  }
  for i = 0, 4 do list[#list + 1] = R(0.34 + i * 0.05, 0.62 + (i % 2) * 0.06, 0.02, 0.1, C.tie) end             -- you can count his ribs
  addAll(list,
    snake(C.text, 0.62, 0.6, 0.76, 0.2, 0.12, 0.06, 0.08, 1.2, 3.14),                                     -- the neck, thin as an arm
    E(0.84, 0.2, 0.16, 0.13, C.text), P(C.text, 0.86, 0.14, 1, 0.26, 1, 0.3, 0.8, 0.3),
    R(0.84, 0.28, 0.16, 0.015, C.bg),
    E(0.78, 0.1, 0.075, 0.08, C.line), E(0.78, 0.1, 0.06, 0.065, C.info), E(0.79, 0.1, 0.018, 0.05, C.bg),
    E(0.9, 0.13, 0.045, 0.05, C.line), E(0.9, 0.13, 0.034, 0.04, C.info), E(0.905, 0.13, 0.012, 0.03, C.bg))
  for i = 0, 3 do list[#list + 1] = P(C.info, 0.86 + i * 0.04, 0.3, 0.88 + i * 0.04, 0.3, 0.87 + i * 0.04, 0.35) end  -- the diamond fang
  return list
end

--- Tiamat's black head, alone, with nothing behind its eyes and nothing at the bottom of its throat. It comes in from the top.
local function tyamet()
  local list = {
    snake(C.tie, 0.0, 0.0, 0.3, 0.42, 0.42, 0.44, 0.07, 1),                                              -- the neck, out of the dark
    snake(C.panel, 0.04, 0.0, 0.3, 0.42, 0.2, 0.26, 0.07, 1),
  }
  for i = 0, 5 do
    list[#list + 1] = P(C.line, 0.02 + i * 0.09, 0.08 + i * 0.09, 0.2 + i * 0.09, -0.04 + i * 0.09, 0.14 + i * 0.09, 0.1 + i * 0.09)
    list[#list + 1] = P(C.panel, 0.0 + i * 0.05, 0.3 + i * 0.1, -0.1 + i * 0.05, 0.42 + i * 0.1, 0.1 + i * 0.05, 0.44 + i * 0.09)
  end
  addAll(list,
    P(C.tie, 0.18, 0.3, 0.42, 0.14, 0.72, 0.16, 1, 0.3, 0.98, 0.44, 0.7, 0.42, 0.56, 0.5, 0.34, 0.66),     -- the upper jaw
    P(C.line, 0.3, 0.22, 0.46, 0.15, 0.72, 0.17, 0.96, 0.3, 0.7, 0.26, 0.46, 0.22),
    P(C.tie, 0.2, 0.6, 0.42, 0.62, 0.7, 0.8, 0.98, 0.84, 0.92, 0.96, 0.62, 0.98, 0.28, 0.84),              -- the lower one
    P(C.bg, 0.3, 0.6, 0.56, 0.48, 0.74, 0.44, 0.98, 0.46, 0.96, 0.82, 0.72, 0.78, 0.44, 0.6),              -- the Maw: nothing in it
    P(C.line, 0.34, 0.22, 0.14, 0.04, 0.22, 0.0, 0.46, 0.16), P(C.line, 0.48, 0.15, 0.36, -0.02, 0.44, -0.02, 0.6, 0.14),  -- horns
    E(0.6, 0.29, 0.085, 0.075, C.accent), E(0.6, 0.29, 0.065, 0.055, C.bg))  -- a socket, and no eye in it
  for i = 0, 6 do
    list[#list + 1] = P(C.text, 0.42 + i * 0.09, 0.44 - (i < 3 and (3 - i) * 0.0 or 0), 0.47 + i * 0.09, 0.44, 0.445 + i * 0.09, 0.56)
    list[#list + 1] = P(C.line, 0.44 + i * 0.085, 0.8, 0.49 + i * 0.085, 0.8, 0.465 + i * 0.085, 0.7)
  end
  for i = 0, 18 do
    list[#list + 1] = R(0.55 + (i * 37 % 40) / 100, 0.52 + (i * 13 % 24) / 100, 0.012, 0.016, i % 3 == 0 and C.accent or C.tie)  -- in there, a long way off, stars
  end
  return list
end

--- It's the shape of an octopus because that's the nearest thing your eyes can do. Some of those are not its eyes.
local function qarhuul()
  local list = {}
  for i = 0, 8 do
    local x = 0.04 + i * 0.115
    list[#list + 1] = snake(i % 3 == 1 and C.line or C.tie, 0.32 + i * 0.045, 0.46, x, i % 2 == 0 and 1 or 0.88, 0.16, 0.02, 0.09 + i % 3 * 0.03, 2.4, i * 1.3)
  end
  list[#list + 1] = snake(C.tie, 0.2, 0.3, 0.0, 0.02, 0.08, 0.012, 0.08, 2.4, 0)
  list[#list + 1] = snake(C.tie, 0.8, 0.3, 1.0, 0.06, 0.08, 0.012, 0.08, 2.4, 1)
  for i = 0, 8 do
    local x = 0.1 + i * 0.1
    list[#list + 1] = E(x, 0.72 + (i * 7 % 5) * 0.04, 0.02, 0.02, C.soft)
    list[#list + 1] = E(x + 0.03, 0.62 + (i * 3 % 4) * 0.05, 0.012, 0.012, C.line)
  end
  addAll(list,
    E(0.5, 0.28, 0.36, 0.28, C.tie), E(0.5, 0.44, 0.38, 0.14, C.panel), E(0.42, 0.18, 0.2, 0.13, C.line), E(0.6, 0.1, 0.11, 0.08, C.tie), E(0.24, 0.3, 0.06, 0.1, C.panel),
    P(C.bg, 0.3, 0.46, 0.7, 0.42, 0.72, 0.5, 0.56, 0.48, 0.5, 0.56, 0.44, 0.48, 0.28, 0.52))
  -- no two of them the same, or at the same height, and one's sideways
  for _, e in ipairs({ { 0.3, 0.3, 0.06, 0.05 }, { 0.42, 0.34, 0.04, 0.06 }, { 0.56, 0.3, 0.075, 0.05 }, { 0.71, 0.26, 0.03, 0.04 }, { 0.66, 0.38, 0.045, 0.03 } }) do
    list[#list + 1] = E(e[1], e[2], e[3], e[4], C.soft)
    list[#list + 1] = E(e[1], e[2], e[3] * 0.72, e[4] * 0.72, C.text)
    list[#list + 1] = E(e[1], e[2], e[3] * 0.3, e[4] * 0.6, C.bg)
  end
  list[#list + 1] = E(0.53, 0.13, 0.016, 0.05, C.soft)
  list[#list + 1] = E(0.53, 0.13, 0.008, 0.035, C.bg)
  return list
end

--- Who hasn't been drawn yet. A foe with no sprite is this, and nobody need know.
local function hooded()
  return {
    P(C.panel, 0.34, 0.26, 0.66, 0.26, 0.82, 1, 0.18, 1),
    P(C.tie, 0.5, 0.3, 0.66, 0.26, 0.82, 1, 0.62, 1),
    P(C.panel, 0.34, 0.34, 0.32, 0.12, 0.5, 0.0, 0.68, 0.12, 0.66, 0.34), E(0.52, 0.2, 0.11, 0.12, C.bg),
    E(0.48, 0.2, 0.02, 0.02, C.red), E(0.57, 0.2, 0.02, 0.02, C.red),
  }
end

local function downed()
  return {
    E(0.5, 0.86, 0.46, 0.12, C.tie), E(0.16, 0.8, 0.13, 0.13, C.line), R(0.62, 0.9, 0.34, 0.06, C.panel),
  }
end

local SPRITES = {
  hero = hero, deserter = deserter, cleric = cleric, owlin = owlin, jezzara = jezzara, asphodel = asphodel,
  crawler = crawler, rat = rat, harpy = harpy, frogman = frogman, stalker = stalker, orderly = orderly, doctor = doctor,
  blighted = blighted, miner = miner, foreman = foreman, downed = downed, hooded = hooded,
  bat = bat, leech = leech, skeleton = skeleton, harpy_queen = harpyQueen, thrall = thrall, vampire_knight = vampireKnight, mindflayer = mindflayer, drider = drider,
  ettercap = ettercap, owl_beast = owlBeast, nothic = nothic, chain_worm = chainWorm, vierrela_husk = vierrelaHusk, colette_changed = coletteChanged,
  plague_surgeon = plagueSurgeon, chylbad = chylbad, tyamet = tyamet, qarhuul = qarhuul,
}
M.SPRITES = SPRITES

-- How much of a square each one takes on a first-person map, where it's not 1. art.lua lends these to the corridors.
M.MAP_SIZE = { bat = 0.55, leech = 0.5, rat = 0.5, crawler = 0.72, owl_beast = 1.2, drider = 1.2, chain_worm = 1.3, chylbad = 1.5, tyamet = 1.6, qarhuul = 1.6, plague_surgeon = 1.1, nothic = 0.8 }

-- What the regions asked for is in art_foes.lua. It all comes through here, so the view and the maps needn't know there are two files.
for name, build in pairs(foes.SPRITES) do SPRITES[name] = build end
for name, size in pairs(foes.MAP_SIZE) do M.MAP_SIZE[name] = size end
M.PROPS = foes.PROPS

-- ---------------------------------------------------------------- baking, as Dungeon does it

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

--- A dark edge round the whole sprite, so it stands clear of the field behind it.
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

local function toRuns(grid, w, h, look)
  local runs = {}
  for row = 0, h - 1 do
    local line = grid[row]
    local col = 0
    while col < w do
      local c = line[col]
      if c then
        local from = col
        while col + 1 < w and line[col + 1] == c do col = col + 1 end
        local ink = c == -1 and C.bg or c
        if look == "flash" and c ~= -1 then ink = C.text end
        if look == "dim" and c ~= -1 then ink = (c == C.text or c == C.line or c == C.hi) and C.line or C.tie end
        local n = #runs
        runs[n + 1], runs[n + 2], runs[n + 3], runs[n + 4] = from, row, col - from + 1, ink
      end
      col = col + 1
    end
  end
  return runs
end

local baked = {}

local grids = {}

--- The painted cells of a sprite at a size. A flash and a sleep share them, since a big boss is a lot of cells to paint three times.
local function gridOf(name, w, h)
  local key = name .. ":" .. w .. "x" .. h
  local grid = grids[key]
  if grid then return grid end
  grid = {}
  for row = -1, h do grid[row] = {} end
  for _, s in ipairs((SPRITES[name] or hooded)()) do
    if s.kind == "e" then
      paintEllipse(grid, w, h, s)
    elseif s.kind == "r" then
      paintRect(grid, w, h, s)
    else
      paintPolygon(grid, w, h, s)
    end
  end
  outline(grid, w, h)
  grids[key] = grid
  return grid
end

--- Runs { x, y, w, colour, ... } for a sprite w by h cells. look: nil, "flash" (a hit lands) or "dim" (asleep). A name that hasn't
-- been drawn gets the hooded shape, so a new foe can never stop a fight.
function M.bake(name, w, h, look)
  if not SPRITES[name] then name = "hooded" end
  local key = name .. ":" .. w .. "x" .. h .. ":" .. (look or "")
  local runs = baked[key]
  if runs then return runs end
  runs = toRuns(gridOf(name, w, h), w, h, look)
  baked[key] = runs
  return runs
end

function M.draw(name, x, y, w, h, look)
  local runs = M.bake(name, w, h, look)
  for i = 1, #runs, 4 do ui.fill(x + runs[i], y + runs[i + 1], runs[i + 2], 1, runs[i + 3]) end
end

-- ---------------------------------------------------------------- the ground under the fight

local function grass(x, y, w, h)
  local sky = floor(h / 4)
  ui.fill(x, y, w, h, C.hiTint)
  ui.fill(x, y, w, sky, C.blueTint)
  ui.fill(x, y + sky, w, 1, C.tie)
  ui.ellipse(x + floor(w * 0.72), y + 1, 12, 6, C.line)
  for row = y + sky + 3, y + h - 1, 4 do
    for col = x + (row * 3) % 11, x + w - 2, 11 do ui.fill(col, row, 2, 1, C.ok) end
  end
end

local function town(x, y, w, h)
  local wall = floor(h / 3)
  ui.fill(x, y, w, h, C.panel)
  ui.fill(x, y, w, wall, C.tie)
  for col = x, x + w - 1, 12 do ui.fill(col, y, 1, wall, C.panel) end
  ui.fill(x, y + floor(wall / 2), w, 1, C.panel)
  ui.fill(x, y + wall, w, 2, C.redTint)
  for row = y + wall + 5, y + h - 1, 5 do
    for col = x + (row * 2) % 9, x + w - 3, 9 do ui.fill(col, row, 4, 1, C.tie) end
  end
end

local function mine(x, y, w, h)
  local roof = floor(h / 4)
  ui.fill(x, y, w, h, C.bg)
  ui.fill(x, y, w, roof, C.panel)
  for col = x + 6, x + w - 6, 22 do
    ui.fill(col, y, 3, roof + 6, C.redTint)                -- timber props
    ui.fill(col - 3, y + roof - 2, 9, 2, C.redTint)
    ui.fill(col + 1, y + roof + 2, 2, 2, C.hi)             -- and their lanterns
  end
  ui.fill(x, y + roof + 6, w, 1, C.tie)
  for row = y + roof + 10, y + h - 1, 4 do
    for col = x + (row * 3) % 13, x + w - 3, 13 do ui.fill(col, row, 3, 1, C.panel) end
  end
end

--- Spots along a row, at a pace that doesn't line up with anything.
local function dots(x, y, w, h, gap, wide, ink, every)
  for row = y, y + h - 1, every do
    for col = x + (row * 3) % gap, x + w - wide - 1, gap do ui.fill(col, row, wide, 1, ink) end
  end
end

local function city(x, y, w, h)
  local sky = floor(h * 0.42)
  ui.fill(x, y, w, h, C.tie)
  ui.fill(x, y, w, sky, C.redTint)
  ui.fill(x, y + floor(sky * 0.6), w, 2, C.red)
  for col = x + 9, x + w - 9, 19 do
    local tall = 8 + (col * 7) % 11
    ui.fill(col, y + sky - tall, 2, tall, C.panel)
    ui.fill(col + 7, y + sky - 6, 1, 6, C.panel)
  end
  ui.fill(x, y + sky, w, 7, C.line)
  for col = x + 4, x + w - 3, 15 do       -- the ribs that hold up the street
    ui.fill(col, y + sky - 3, 3, 10, C.text)
    ui.fill(col + 3, y + sky + 2, 1, 5, C.tie)
  end
  ui.fill(x, y + sky + 7, w, 1, C.panel)
  dots(x, y + sky + 10, w, h - sky - 10, 12, 4, C.panel, 4)
end

local function marble(x, y, w, h)
  local sky = floor(h * 0.34)
  ui.fill(x, y, w, h, C.text)
  ui.fill(x, y, w, floor(sky / 2), C.blue)
  ui.fill(x, y + floor(sky / 2), w, sky - floor(sky / 2), C.info)
  ui.fill(x + 16, y + 3, 22, 2, C.text)
  ui.fill(x + 74, y + 6, 26, 2, C.text)
  ui.fill(x, y + sky, w, 5, C.ok)         -- the hedge
  for col = x + 3, x + w - 3, 7 do ui.fill(col, y + sky + 1 + col % 3, 2, 1, col % 2 == 0 and C.red or C.hi) end
  ui.fill(x, y + sky + 5, w, 1, C.hi)
  for row = y + sky + 9, y + h - 1, 7 do ui.fill(x, row, w, 1, C.line) end
  for col = x + 8, x + w - 2, 20 do ui.fill(col, y + sky + 6, 1, h - sky - 6, C.line) end
end

local function swamp(x, y, w, h)
  local sky = floor(h * 0.36)
  ui.fill(x, y, w, h, C.hiTint)
  ui.fill(x, y, w, sky, C.tie)
  ui.fill(x, y, w, 4, C.panel)
  for col = x + 2, x + w - 2, 5 do
    local tall = 4 + (col * 11) % 8
    ui.fill(col, y + sky - tall + 2, 1, tall, col % 3 == 0 and C.soft or C.ok)
  end
  ui.fill(x, y + sky + 2, w, 2, C.blueTint)
  for row = y + sky + 8, y + h - 1, 5 do
    ui.fill(x + (row * 7) % 30, row, 26, 1, C.blueTint)
    ui.fill(x + (row * 5) % 36 + 50, row, 34, 1, C.blueTint)
  end
  dots(x, y + sky + 6, w, h - sky - 6, 17, 2, C.ok, 5)
end

local function ruin(x, y, w, h)
  local sky = floor(h * 0.4)
  ui.fill(x, y, w, h, C.panel)
  ui.fill(x, y, w, sky, C.blueTint)
  ui.fill(x, y + floor(sky * 0.55), w, sky - floor(sky * 0.55), C.accent)
  ui.fill(x, y + floor(sky * 0.75), w, 1, C.text)
  for col = x + 5, x + w - 8, 23 do
    local tall = 9 + (col * 3) % 9
    ui.fill(col, y + sky - tall, 7, tall, C.bg)
    ui.fill(col + 1, y + sky - tall - 2, 2, 2, C.bg)
    ui.fill(col + 3, y + sky - tall + 3, 1, 2, C.info)
  end
  ui.fill(x, y + sky, w, 1, C.bg)
  dots(x, y + sky + 4, w, h - sky - 4, 16, 5, C.bg, 5)
  dots(x + 7, y + sky + 6, w - 7, h - sky - 6, 23, 3, C.accent, 7)
end

local function cave(x, y, w, h)
  local roof = floor(h / 4)
  ui.fill(x, y, w, h, C.bg)
  ui.fill(x, y, w, roof, C.blueTint)
  for col = x + 3, x + w - 6, 9 do
    local long = 3 + (col * 7) % 6
    for i = 0, long - 1 do ui.fill(col + floor(i / 2), y + roof + i, 5 - i > 0 and 5 - i or 1, 1, C.blueTint) end
  end
  ui.fill(x, y + roof + 11, w, 1, C.hiTint)
  ui.fill(x, y + roof + 12, w, h - roof - 12, C.panel)
  dots(x, y + roof + 14, w, h - roof - 14, 13, 5, C.hiTint, 3)
  for col = x + 6, x + w - 4, 29 do        -- something that glows on a stalk
    ui.fill(col + 1, y + roof + 8, 1, 4, C.line)
    ui.fill(col - 1, y + roof + 6, 5, 2, C.info)
    ui.fill(col, y + roof + 5, 3, 1, C.soft)
  end
end

local function web(x, y, w, h)
  local cx = x + floor(w * 0.5)
  ui.fill(x, y, w, h, C.bg)
  for i = -7, 7 do
    for row = 0, floor(h * 0.45) do
      local col = cx + floor(i * (2 + row * 0.9))
      if col >= x and col < x + w then ui.fill(col, y + row, 1, 1, C.tie) end
    end
  end
  for row = 5, floor(h * 0.45), 6 do
    for i = -7, 6 do
      local x1 = cx + floor(i * (2 + row * 0.9))
      local x2 = math.min(x1 + floor(2 + row * 0.9), x + w)
      x1 = math.max(x1, x)
      ui.fill(x1, y + row + (i % 2), x2 - x1, 1, C.panel)
    end
  end
  local deck = floor(h * 0.45)
  ui.fill(x, y + deck, w, h - deck, C.panel)
  ui.fill(x, y + deck, w, 1, C.text)
  dots(x, y + deck + 3, w, h - deck - 3, 15, 8, C.tie, 4)
  ui.fill(x + 12, y + deck - 12, 5, 9, C.line)
  ui.fill(x + 13, y + deck - 15, 1, 3, C.line)
  ui.fill(x + 94, y + deck - 9, 4, 7, C.text)
  ui.fill(x + 95, y + deck - 13, 1, 4, C.line)
end

local function brine(x, y, w, h)
  local top = floor(h * 0.38)
  ui.fill(x, y, w, h, C.bg)
  ui.fill(x, y, w, top, C.hiTint)
  for i = 0, w - 2, 2 do
    local d = (i - w / 2) / (w / 2)
    ui.fill(x + i, y + floor(2 + d * d * top * 0.9), 2, 1, C.ok)       -- the green bubble, and the rain on it
  end
  dots(x, y + 1, w, top - 2, 19, 1, C.line, 3)
  ui.fill(x, y + top, w, 3, C.blueTint)
  ui.fill(x, y + top + 3, w, 1, C.ok)
  ui.fill(x, y + top + 4, w, h - top - 4, C.hiTint)
  dots(x, y + top + 7, w, h - top - 7, 14, 6, C.bg, 3)
  dots(x + 5, y + top + 9, w - 5, h - top - 9, 31, 3, C.soft, 6)
end

local function chain(x, y, w, h)
  ui.fill(x, y, w, h, C.bg)
  local deck = floor(h * 0.55)
  for _, at in ipairs({ { 8, 6, 2 }, { 25, 2, 4 }, { 46, 9, 2 }, { 66, 3, 3 }, { 86, 7, 2 }, { 104, 1, 4 } }) do
    local col, top, size = x + at[1], y + at[2], at[3]
    ui.fill(col + size, y, 1, top, C.panel)
    ui.fill(col, top, size * 2 + 1, size * 3, C.warn)
    ui.fill(col + size, top, 1, size * 3, C.panel)
    ui.fill(col, top + size, size * 2 + 1, 1, C.panel)
    if size > 2 then ui.fill(col + 1, top + 1, size - 1, size - 1, C.hi) end
  end
  for row = 0, deck - 1, 2 do                   -- a chain thick as a house, and it's moving
    ui.fill(x + 56 + (row % 4 == 0 and -1 or 0), y + row, row % 4 == 0 and 4 or 2, 2, C.tie)
    ui.fill(x + 16 + (row % 4 == 2 and -1 or 0), y + row, row % 4 == 2 and 4 or 2, 2, C.panel)
  end
  ui.fill(x, y + deck - 3, w, 3, C.tie)         -- the mist, past the edge of the planks
  ui.fill(x, y + deck - 1, w, 1, C.line)
  ui.fill(x, y + deck, w, h - deck, C.panel)
  for row = y + deck + 3, y + h - 1, 4 do ui.fill(x, row, w, 1, C.bg) end
  for col = x + 11, x + w - 2, 27 do ui.fill(col, y + deck, 1, h - deck, C.bg) end
end

local function snow(x, y, w, h)
  local sky = floor(h * 0.36)
  ui.fill(x, y, w, h, C.text)
  ui.fill(x, y, w, sky, C.line)
  ui.fill(x, y, w, floor(sky / 2), C.tie)
  for col = x, x + w - 13, 13 do
    local tall = 3 + (col * 5) % 7
    ui.fill(col, y + sky - tall, 13, tall, C.line)
    ui.fill(col + 4, y + sky - tall - 2, 5, 2, C.text)
  end
  ui.fill(x, y + sky, w, 1, C.blueTint)
  dots(x, y + sky + 4, w, h - sky - 4, 17, 7, C.line, 4)
  dots(x, y + 1, w, sky - 1, 11, 1, C.text, 3)
end

local function ash(x, y, w, h)
  local sky = floor(h * 0.42)
  ui.fill(x, y, w, h, C.tie)
  ui.fill(x, y, w, sky, C.line)
  ui.fill(x, y, w, floor(sky / 3), C.panel)
  ui.fill(x + 8, y + floor(sky / 3), 40, 2, C.tie)
  ui.fill(x + 70, y + floor(sky / 3) + 3, 34, 2, C.tie)
  for col = x + 4, x + w - 7, 17 do
    local tall = 6 + (col * 3) % 10
    ui.fill(col, y + sky - tall, 3, tall + 1, C.bg)
    if col % 2 == 0 then ui.fill(col - 3, y + sky - tall + 3, 9, 1, C.bg) end
  end
  ui.fill(x, y + sky, w, 1, C.panel)
  dots(x, y + sky + 3, w, h - sky - 3, 14, 6, C.panel, 3)
  dots(x + 3, y + sky + 5, w - 3, h - sky - 5, 37, 1, C.warn, 7)
end

local function dream(x, y, w, h)
  ui.fill(x, y, w, h, C.bg)
  local base = floor(h * 0.42)
  for i = 0, w - 3, 3 do
    local d = sin(i * 0.11) * 4
    ui.fill(x + i, y + base + floor(d), 3, 1, C.soft)
    ui.fill(x + i, y + base + 8 + floor(d * 1.6), 3, 1, C.tie)
    ui.fill(x + i, y + base + 18 + floor(d * 2.3), 3, 1, C.panel)
  end
  for col = x + 3, x + w - 8, 15 do
    local tall = 6 + (col * 7) % 13
    for row = 0, tall - 1, 2 do ui.fill(col + floor(row / 3), y + 2 + row, 6, 1, row % 6 == 0 and C.soft or C.panel) end
  end
  dots(x, y, w, h, 23, 1, C.tie, 5)
end

local GROUNDS = { grass = grass, town = town, mine = mine, city = city, marble = marble, swamp = swamp, ruin = ruin, cave = cave, web = web, brine = brine, chain = chain, snow = snow, ash = ash, dream = dream }
M.GROUNDS = GROUNDS

function M.ground(bg, x, y, w, h)
  ui.fill(x, y, w, h, C.bg)
  local paint = GROUNDS[bg] or mine
  paint(x, y, w, h)
end

return M
