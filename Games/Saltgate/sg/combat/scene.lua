-- combat/scene.lua
-- The things combat puts in the world, added to the renderer's scene list: practice goons (standing, or lying down
-- with stars over them when knocked), ammo and weapon crates that spin, and the player lying on the ground when
-- knocked down on foot (the standing model is sunk out of sight). It wraps the view's scene() (the interface the
-- core and stream A's renderer keep).
--
--   scene.wrap(view, ctx, cb) -> true when wrapped      scene.crate(kind, weapon) -> model

local models = require("sg.models")
local weapons = require("sg.combat.weapons")

local M = {}

local C = rawget(_G, "colors") or rawget(_G, "colours") or {}
local box = models.box

--- A crate model: ammo is a box in the weapon's tracer colour with a dark band, a gun is a case with a gun on it,
-- health is white with a red cross; each floats a bright gem above so it can be seen from a distance.
function M.crate(kind, weapon)
  local list = {}
  local w = weapons.get(weapon)
  local c = kind == "health" and C.white or (C[w and w.tracer or "yellow"] or C.yellow)
  box(list, -0.45, 0, -0.35, 0.45, 0.55, 0.35, c, c, c)
  box(list, -0.46, 0.18, -0.36, 0.46, 0.3, 0.36, C.black, C.black, C.black, { noTop = true })
  if kind == "gun" then
    box(list, -0.4, 0.55, -0.1, 0.4, 0.7, 0.1, C.black, C.black, C.black)
    box(list, 0.15, 0.55, -0.1, 0.3, 0.9, 0.1, C.black, C.black, C.black)
  elseif kind == "health" then
    box(list, -0.3, 0.55, -0.08, 0.3, 0.58, 0.08, C.red)
    box(list, -0.08, 0.55, -0.3, 0.08, 0.58, 0.3, C.red)
  end
  local gem = kind == "gun" and C.cyan or (kind == "health" and C.red or C.yellow)
  box(list, -0.2, 1.2, -0.2, 0.2, 1.6, 0.2, gem, gem, gem)
  return list
end

function M.wrap(view, ctx, cb)
  if type(view.scene) ~= "function" or view.combatSceneWrapped then return false end
  view.combatSceneWrapped = true
  local orig = view.scene
  view.scene = function(self, c)
    local list = orig(self, c)
    local r, cam = self.r, self.cam
    if not cam then return list end
    local fx, fz = math.cos(cam.yaw), math.sin(cam.yaw)
    local function near(x, z, d)
      local dx, dz = x - cam.x, z - cam.z
      return dx * dx + dz * dz < d * d and (dx * fx + dz * fz) > -8
    end
    local p = c.player
    -- the player on the ground
    if p.knocked and not p.car then
      for i = #list, 1, -1 do
        local o = list[i]
        if o[1] == p.x and o[3] == p.z then o[2] = o[2] - 6 break end
      end
      r:place(list, r:variant("wren:down", p.h, function() return models.person("orange", true, "gray") end), p.x, (p.y or 0) + 0.05, p.z)
    end
    for _, e in ipairs(c.world:each("person")) do
      if e.kind == "goon" and near(e.x, e.z, 110) then
        local shirt, down = e.shirt or "purple", e.knocked
        local key = "goon:" .. shirt .. (down and ":down" or "")
        r:place(list, r:variant(key, e.h or 0, function() return models.person(shirt, down, "black") end), e.x, (e.y or 0) + 0.05, e.z)
      end
    end
    for _, e in ipairs(c.world:each("pickup")) do
      if e.pk and not e.hiddenT and near(e.x, e.z, 70) then
        local pk = e.pk
        local key = "crate:" .. pk.type .. ":" .. tostring(pk.weapon)
        r:place(list, r:variant(key, cb.clock * 2, function() return M.crate(pk.type, pk.weapon) end), e.x,
          (e.y or 0) + 0.2 + math.sin(cb.clock * 3 + e.id) * 0.1, e.z)
      end
    end
    return list
  end
  return true
end

return M
