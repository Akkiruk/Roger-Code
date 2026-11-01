-- games/craps/dice.lua
-- A die on a canvas, and the tumble both screens play while they are in the air. Pure, so a seat and the wall can draw the same roll.

local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

M.LAND = 0.8   -- how far through a roll the dice stop. Nothing the roll decided shows before this

M.BIG_W, M.BIG_H = 18, 12
M.SMALL_W, M.SMALL_H = 12, 7

-- Which of the nine places has a pip: 1 2 3 across the top, 4 5 6, 7 8 9
local FACES = {
  { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 },
}

--- One die. face nil is a die with nothing showing, for before the first roll.
function M.draw(c, x, y, face, big)
  local w, h = big and M.BIG_W or M.SMALL_W, big and M.BIG_H or M.SMALL_H
  c:rect(x + 1, y + 1, w, h, C.ink)
  c:panel(x, y, w, h, C.card, nil)
  local pips = FACES[face or 0]
  if not pips then return end
  local pipW, pipH = big and 4 or 2, big and 2 or 1
  local stepX, stepY = big and 5 or 3, big and 4 or 2
  for _, place in ipairs(pips) do
    local column, row = (place - 1) % 3, math.floor((place - 1) / 3)
    c:rect(x + 2 + column * stepX, y + 1 + row * stepY, pipW, pipH, C.ink)
  end
end

--- Whether this roll is still in the air, so what it decided stays held back.
function M.flying(anim)
  return anim ~= nil and anim.ev ~= nil and anim.ev.type == "roll" and anim.t < M.LAND
end

--- The face a die shows at this moment of a roll. index is 1 or 2.
function M.tumble(anim, index)
  local ev = anim.ev
  if not M.flying(anim) then return index == 1 and ev.d1 or ev.d2 end
  local frame = math.floor(anim.t * 16)
  return (frame * (index == 1 and 5 or 7) + (ev.n or 0) * index + index) % 6 + 1
end

--- How far from its resting place a die is at this moment of a roll: dx cells to the left, and dy up, bouncing as it comes to rest.
function M.flight(anim, reach, height)
  if not M.flying(anim) then return 0, 0 end
  local left = 1 - anim.t / M.LAND
  return math.floor(reach * left * left), math.floor(math.abs(math.sin(anim.t * 12)) * height * left)
end

return M
