-- ai/models.lua
-- The shapes stream C adds to the scene: the police helicopter and its rotor, the patrol boat, roadblock barriers, cones,
-- spike strips, the searchlight's pool of light, a person in the Patrol's blue and the stars over someone who has been
-- knocked down. Built from sg/models.lua's boxes (facing +x, the same winding), so the renderer takes them as they are.

local base = require("sg.models")

local M = {}

local C = rawget(_G, "colors") or rawget(_G, "colours") or {}
local box, quad = base.box, base.quad

--- The police helicopter without its rotor, facing +x.
function M.heli()
  local l = {}
  box(l, -1.8, 0.5, -0.85, 1.7, 1.9, 0.85, C.blue, C.white, C.white)
  box(l, 0.9, 0.8, -0.8, 1.75, 1.7, 0.8, C.cyan, C.cyan, C.cyan, { noTop = true })
  box(l, -5.4, 1.0, -0.18, -1.8, 1.45, 0.18, C.blue, C.blue, C.blue)
  box(l, -5.6, 1.0, -0.06, -4.9, 2.4, 0.06, C.white, C.white, C.white)
  box(l, -1.2, 0.0, -0.85, 1.2, 0.12, -0.7, C.black, C.black, C.black)
  box(l, -1.2, 0.0, 0.7, 1.2, 0.12, 0.85, C.black, C.black, C.black)
  box(l, -0.1, 1.9, -0.12, 0.1, 2.15, 0.12, C.gray, C.gray, C.gray)
  box(l, 0.3, 0.3, -0.25, 0.9, 0.52, 0.25, C.yellow, C.yellow, C.yellow) -- the searchlight under the nose
  box(l, -1.8, 1.6, -0.9, -1.4, 1.75, -0.6, C.red, C.red, C.red)
  box(l, -1.8, 1.6, 0.6, -1.4, 1.75, 0.9, C.blue, C.blue, C.blue)
  return l
end

--- Two rotor blades in a cross (turned by the caller's heading to spin them).
function M.rotor()
  local l = {}
  box(l, -4.2, 0, -0.16, 4.2, 0.07, C.black, C.gray, C.gray)
  box(l, -0.16, 0, -4.2, 0.16, 0.07, C.black, C.gray, C.gray)
  return l
end

--- The patrol boat, facing +x.
function M.boat()
  local l = {}
  box(l, -3.2, 0, -1.2, 2.2, 0.8, 1.2, C.white, C.white, C.white)
  box(l, 2.2, 0.15, -0.8, 3.6, 0.7, 0.8, C.white, C.lightGray, C.lightGray)
  box(l, -1.2, 0.8, -0.9, 1.0, 2.0, 0.9, C.lightGray, C.blue, C.blue)
  box(l, -0.3, 2.0, -0.7, 0.4, 2.3, 0, C.red, C.red, C.red)
  box(l, -0.3, 2.0, 0, 0.4, 2.3, 0.7, C.blue, C.blue, C.blue)
  box(l, -3.2, 0.1, -1.25, -2.8, 0.5, 1.25, C.red, C.red, C.red) -- a red stripe at the stern
  return l
end

--- A roadblock barrier w units wide across the road (along z), striped.
function M.barrier(w)
  local l = {}
  local n = math.max(2, math.floor(w / 1.5))
  local seg = w / n
  for i = 0, n - 1 do
    local c = (i % 2 == 0) and C.red or C.white
    box(l, -0.25, 0.35, -w / 2 + i * seg, 0.25, 1.0, -w / 2 + (i + 1) * seg, c, c, c)
  end
  box(l, -0.15, 0, -w / 2, 0.15, 0.4, -w / 2 + 0.3, C.black, C.black, C.black)
  box(l, -0.15, 0, w / 2 - 0.3, 0.15, 0.4, w / 2, C.black, C.black, C.black)
  return l
end

function M.cone()
  local l = {}
  box(l, -0.25, 0, -0.25, 0.25, 0.7, 0.25, C.orange, C.orange, C.orange)
  box(l, -0.3, 0, -0.3, 0.3, 0.06, 0.3, C.black, C.black, C.black)
  return l
end

--- A spike strip w wide across the road (along z): a dark mat with bright teeth.
function M.spikes(w)
  local l = {}
  box(l, -0.45, 0, -w / 2, 0.45, 0.1, w / 2, C.black, C.black, C.black)
  local n = math.max(3, math.floor(w / 0.8))
  for i = 0, n - 1 do
    local z0 = -w / 2 + (i + 0.3) * (w / n)
    box(l, -0.1, 0.1, z0, 0.1, 0.3, z0 + 0.25, C.lightGray, C.lightGray, C.lightGray)
  end
  return l
end

--- The pool of light on the ground: a pale ring under a bright middle.
function M.lightPool()
  local l = {}
  quad(l, -7, -7, 7, 7, 0, C.yellow)
  quad(l, -4.5, -4.5, 4.5, 4.5, 0.05, C.white)
  return l
end

--- A person in the Patrol's uniform.
function M.officer()
  return base.person("blue", false, "black")
end

--- Stars circling the head of someone who has been knocked down.
function M.stars()
  local l = {}
  box(l, -0.1, 0, -0.5, 0.1, 0.2, -0.3, C.yellow, C.yellow, C.yellow)
  box(l, 0.3, 0, 0.3, 0.5, 0.2, 0.5, C.yellow, C.yellow, C.yellow)
  box(l, -0.4, 0, 0.2, -0.2, 0.2, 0.4, C.white, C.white, C.white)
  return l
end

return M
