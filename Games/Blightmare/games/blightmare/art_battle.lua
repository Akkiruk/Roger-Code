-- games/blightmare/art_battle.lua
-- Everyone in a fight, as shapes in a unit square with the floor along the bottom, the way Dungeon's art works. Foes stand on the
-- left and face right; the party stands on the right and faces left. Bold shapes and one loud colour each, because at 24 cells
-- across fine detail is gone. bake turns a sprite into runs of colour once for each size, and after that it's a short list of fills.

local ui = require("lib.arcade.ui")

local C = ui.C
local ceil, floor, sqrt = math.ceil, math.floor, math.sqrt

local M = {}

-- ---------------------------------------------------------------- shapes

local function E(cx, cy, rx, ry, color) return { kind = "e", cx = cx, cy = cy, rx = rx, ry = ry, color = color } end
local function R(x, y, w, h, color) return { kind = "r", x = x, y = y, w = w, h = h, color = color } end
local function P(color, ...) return { kind = "p", points = { ... }, color = color } end

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
    R(0.38, 0.22, 0.05, 0.05, C.bg),
    R(0.14, 0.42, 0.22, 0.08, C.warn), P(C.text, 0.15, 0.42, 0.0, 0.3, 0.17, 0.5),
    R(0.68, 0.44, 0.16, 0.08, C.warn), P(C.text, 0.84, 0.44, 1, 0.3, 0.82, 0.52),
  }
end

local function asphodel()
  return {
    P(C.redTint, 0.6, 0.34, 0.88, 0.4, 0.94, 0.9, 0.66, 0.8),
    R(0.36, 0.72, 0.13, 0.26, C.redTint), R(0.54, 0.72, 0.13, 0.26, C.redTint),
    P(C.red, 0.28, 0.34, 0.74, 0.34, 0.7, 0.76, 0.3, 0.76), P(C.tie, 0.46, 0.34, 0.56, 0.34, 0.55, 0.76, 0.47, 0.76),
    E(0.5, 0.2, 0.15, 0.16, C.text), P(C.bg, 0.33, 0.16, 0.5, 0.0, 0.68, 0.1, 0.68, 0.34, 0.58, 0.16),
    R(0.38, 0.18, 0.05, 0.05, C.red),
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

local function downed()
  return {
    E(0.5, 0.86, 0.46, 0.12, C.tie), E(0.16, 0.8, 0.13, 0.13, C.line), R(0.62, 0.9, 0.34, 0.06, C.panel),
  }
end

local SPRITES = {
  hero = hero, deserter = deserter, cleric = cleric, owlin = owlin, jezzara = jezzara, asphodel = asphodel,
  crawler = crawler, rat = rat, harpy = harpy, frogman = frogman, stalker = stalker, orderly = orderly, doctor = doctor,
  blighted = blighted, miner = miner, foreman = foreman, downed = downed,
}
M.SPRITES = SPRITES

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

--- Runs { x, y, w, colour, ... } for a sprite w by h cells. look: nil, "flash" (a hit lands) or "dim" (asleep).
function M.bake(name, w, h, look)
  local key = name .. ":" .. w .. "x" .. h .. ":" .. (look or "")
  local runs = baked[key]
  if runs then return runs end
  local list = SPRITES[name]()
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
  outline(grid, w, h)
  runs = toRuns(grid, w, h, look)
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

local GROUNDS = { grass = grass, town = town, mine = mine }

function M.ground(bg, x, y, w, h)
  ui.fill(x, y, w, h, C.bg)
  GROUNDS[bg or "mine"](x, y, w, h)
end

return M
