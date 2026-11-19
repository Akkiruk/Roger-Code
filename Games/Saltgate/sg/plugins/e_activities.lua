-- plugins/e_activities.lua
-- Stream E: the side activities. Street races with ghosts, taxi shifts and parcel runs, 50 gull totems and 10 postcards,
-- stunt jumps, shops (respray, tune, clothes), property that pays rent, the garage. Where everything is comes from
-- content/activities/layout.lua (made from the city by sg/activities/genlayout.lua); what the shops sell from shops.lua.
-- Other parts reach it as ctx.activities (sg/activities/manager.lua):
--   ctx.activities:hud()  :prompt()  :markers()  :mapMarkers()  :target()  :counts(category)  :cancel()
--   ctx.activities.garage  :store() :takeOut()      ctx.activities.shops   ctx.activities.property
--   ctx.spawnVehicle(kind, x, z, h, colour) -> car     (optional: B's constructor; without it sg/vehicle.lua's is used)
-- Items are drawn in the 3D world through the view's scene list (sg/activities/markers.lua).

local common = require("sg.activities.common")
local manager = require("sg.activities.manager")
local menus = require("sg.activities.menus")
local markers = require("sg.activities.markers")
local saveLib = require("sg.core.save")

local P = { name = "e_activities", order = 30, needs = { "e_progress", "e_ui" } }

function P.init(ctx)
  local layout = ctx.content:data("activities/layout.lua")
  local catalog = ctx.content:data("activities/shops.lua")
  if not layout or not catalog then
    ctx.log("e_activities: no layout or shops")
    layout = layout or {}
    catalog = catalog or { respray = { price = 150, colours = {} }, tune = { slots = {} }, clothes = { outfits = {} }, garage = { base = 3 } }
  end
  saveLib.section("activities", {
    version = 1, owner = "e", blank = function() return common.ensure({}) end,
    migrate = function(old) return common.ensure(old) end,
  })
  local mgr = manager.new(ctx, { layout = layout, catalog = catalog, config = ctx.progress.config })
  ctx.activities = mgr
  menus.new(ctx, mgr, ctx.eui.screens)
  for _, id in ipairs({ "totems", "postcards", "jumps", "races", "taxi", "delivery", "property", "garage" }) do
    ctx.progress.completion:provide(id, function() return mgr:counts(id) end)
  end
  markers.install(ctx, function() return mgr:markers() end)
  -- the outfit you bought last time
  local outfit = ctx.save.player.outfit
  if outfit then mgr.shops:wear(outfit) end
  ctx.bus:on("load", function(d)
    local o = d.data and d.data.player and d.data.player.outfit
    if o then mgr.shops:wear(o) end
  end, "e_activities")
end

function P.update(ctx, dt)
  ctx.activities:update(dt, ctx.eui.keys)
end

return require("sg.ui.guard").plugin(P)
