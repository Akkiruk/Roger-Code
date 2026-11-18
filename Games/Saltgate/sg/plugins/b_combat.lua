-- plugins/b_combat.lua
-- Stream B's combat (v2 only): cartoony guns with a keyboard lock-on, ammo and pickups, knockdowns that never kill,
-- the combat HUD and hint line, and the pixel effects. The work is in sg/combat/*; this file joins it to the game.
--   ctx.combat   the combat system (sg/combat/system.lua): shoot(shooter, weapon, angle) for gangs and the Patrol,
--                knock rules, spawnGoon, dropAmmo, give, hurtPlayer
--   keys         J fire (hold), K next target, L next weapon, 1-6 a weapon
-- Drop a file named saltgate_b_demo.flag next to the game to start with every gun, practice goons and crates on the
-- testbed (and a showroom of vehicles: see plugins/b_vehicles.lua).

local system = require("sg.combat.system")
local input = require("sg.combat.input")
local hud = require("sg.combat.hud")
local fx = require("sg.combat.fx")
local overlay = require("sg.combat.overlay")
local scene = require("sg.combat.scene")
local weapons = require("sg.combat.weapons")
local save = require("sg.core.save")

local current = nil

local function playing(ctx)
  return function()
    local top = ctx.ui.top()
    return top ~= nil and top.name == "play"
  end
end

return {
  name = "b_combat",
  order = 30,

  init = function(ctx)
    current = ctx
    local cb = system.new(ctx, { seed = 11 })
    ctx.combat = cb
    input.install(function() return current end)
    hud.register(ctx)
    pcall(save.section, "combat", { version = 1, owner = "b_combat", blank = function() return {} end })
    ctx.bus:on("load", function(d)
      local data = d.data
      if data and data.combat and data.combat.owned then cb:restore(data.combat) end
    end, "b_combat")
    ctx.bus:on("save", function(d)
      if d.data then d.data.combat = cb:snapshot() end
    end, "b_combat")
    if ctx.view and ctx.view.r then
      overlay.install(ctx.view.r.frame, playing(ctx))
      scene.wrap(ctx.view, ctx, cb)
    end
    overlay.add("b_combat", function(frame, rows, W, H) fx.paint(ctx, cb, frame, rows, W, H) end)
    if fs and fs.exists and fs.exists("saltgate_b_demo.flag") then
      for _, w in ipairs(weapons.LIST) do cb:give(w.id, w.reserve + w.mag) end
      require("sg.combat.showroom").combat(ctx, cb)
    end
  end,

  update = function(ctx, dt)
    local cb = ctx.combat
    if ctx.view and ctx.view.r then overlay.install(ctx.view.r.frame, playing(ctx)) end
    cb:update(dt, input.read(ctx.input))
  end,

  draw = function(ctx)
    local cb = ctx.combat
    local top = ctx.ui.top()
    if cb and top and top.name == "play" and ctx.view and ctx.view.r then
      fx.words(ctx, cb, ctx.view.r.frame, ctx.screen)
    end
  end,
}
