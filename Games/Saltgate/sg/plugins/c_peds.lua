-- plugins/c_peds.lua
-- Stream C: the people (sg/ai/peds.lua) and how they are drawn. Pavements and paths by district and hour, running from
-- gunfire and crashes (the crime event and ctx.ai.alarm), knocked down and never killed.

local pedsLib = require("sg.ai.peds")
local gangsLib = require("sg.ai.gangs")
local scene = require("sg.ai.scene")

local P = { name = "c_peds", order = 25 }

local SCARE = { gunfire = 45, shots = 45, shooting = 45, gun = 45, explosion = 60, assault = 16, hit_car = 20, hit_cruiser = 20, carjack = 16 }

function P.init(ctx)
  ctx.ai = ctx.ai or {}
  local peds = pedsLib.new(ctx)
  ctx.ai.peds = peds
  local gangs = gangsLib.new(ctx, peds)
  ctx.ai.gangs = gangs
  -- hit one of a crew and the whole crew comes for you
  peds.onKnock = function(ped, byPlayer) if ped.gang and byPlayer then gangs:provoke(ped.x, ped.z, 30) end end
  --- Stream B's combat: knock a person down (never kills) and frighten the street.
  ctx.ai.knock = function(e, vx, vz)
    if e and e.tags and e.tags.ped then peds:knock(e, vx, vz, true) end
  end
  -- gunfire and trouble: people near it run (the data may say where, else it is where the player is)
  ctx.bus:on("crime", function(d)
    local r = SCARE[d.kind] or 12
    local x, z = d.x, d.z
    if not x then
      local p = ctx.player
      x, z = p.x, p.z
    end
    peds:scare(x, z, r, d.kind)
    if r >= 16 then gangs:provoke(x, z, r) end
    if ctx.ai.traffic and r >= 16 then ctx.ai.traffic:alarm(x, z, r) end
  end, "c_peds")
  ctx.bus:on("chunk_loaded", function() peds.dirty = true end, "c_peds")
  ctx.bus:on("chunk_unloaded", function() peds.dirty = true end, "c_peds")
  scene.layer(ctx, "peds", function(c, view, list, cam)
    local models = require("sg.models")
    local aimodels = require("sg.ai.models")
    local r = view.r
    local fx, fz = math.cos(cam.yaw), math.sin(cam.yaw)
    local t = c.time or 0
    for _, ped in ipairs(c.world:each("ped")) do
      local dx, dz = ped.x - cam.x, ped.z - cam.z
      local d2 = dx * dx + dz * dz
      if d2 < 80 * 80 and (dx * fx + dz * fz) > -4 then
        local down = ped.state == "down"
        local shirt = ped.shirt
        local key = "ped:" .. shirt .. (down and ":d" or "")
        local y = (ped.y or 0) + 0.05
        if ped.state == "walk" or ped.state == "flee" then y = y + 0.07 * math.abs(math.sin(t * (ped.state == "flee" and 14 or 7) + (ped.wob or 0))) end
        r:place(list, r:variant(key, ped.h or 0, function() return models.person(shirt, down, "black") end), ped.x, y, ped.z)
        if ped.state == "dazed" then
          r:place(list, r:variant("ped:stars", t * 6, function() return aimodels.stars() end), ped.x, y + 2.0, ped.z)
        end
      end
    end
  end)
end

function P.update(ctx, dt)
  ctx.ai.peds:update(dt)
  ctx.ai.gangs:update(dt)
end

return P
