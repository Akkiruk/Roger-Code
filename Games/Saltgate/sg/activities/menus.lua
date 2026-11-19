-- activities/menus.lua
-- The shop, garage and property screens, built from the manager's rules as list menus (ui/screens.lua menu(args)).
--
--   local m = menus.new(ctx, manager, screensApi)
--   m.open(kind, place)      kind: "shop" | "garage" | "property"

local util = require("sg.util")
local services = require("sg.activities.services")

local M = {}

local function pretty(id)
  local s = tostring(id):gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("^%l", string.upper)
  return s
end
M.pretty = pretty

function M.new(ctx, mgr, screens)
  local api = {}
  local ui = ctx.ui

  local function say(ok, why)
    if not ok and why and ctx.hud then ctx.hud.toast(why, "red", 3) end
  end

  --- Rebuild a menu's rows after something changed, keeping the cursor.
  local function refresh(args)
    if args.menu then args.keepSel = args.menu.sel end
    args.menu = nil
  end

  local function cash(c)
    return "Cash " .. util.money(c.save.player.money or 0)
  end

  local function carLine(c)
    local car = c.player.car
    return car and ((car.spec and car.spec.name or "Car") .. " (" .. pretty(car.colour or "") .. ")") or "No car: drive one in"
  end

  function api.respray(place)
    local colours, price = mgr.shops:paints()
    local stripes, stripePrice = mgr.shops:stripes()
    screens.menu({
      title = place.name .. ": respray", width = 36, footer = "W/S choose  ENTER paint  BACKSPACE leave",
      subtitle = function(c) return { carLine(c), cash(c) .. "   " .. util.money(price) .. " a coat" } end,
      build = function()
        local items = {}
        for _, col in ipairs(colours) do
          items[#items + 1] = { label = pretty(col), swatch = col, value = function()
            local body = mgr.shops:currentPaint()
            return body == col and "now" or util.money(price)
          end, action = function() say(mgr.shops:respray(col)) end }
        end
        if stripes then
          items[#items + 1] = { label = "Stripes", header = true }
          for _, st in ipairs(stripes) do
            items[#items + 1] = { label = pretty(st), swatch = st ~= "none" and st or nil, value = function()
              local _, cur = mgr.shops:currentPaint()
              return (cur or "none") == st and "now" or util.money(stripePrice)
            end, action = function() say(mgr.shops:stripe(st)) end }
          end
        end
        return items
      end,
    })
  end

  function api.tune(place)
    screens.menu({
      title = place.name .. ": tune", width = 42, footer = "W/S choose  ENTER buy next tier  BACKSPACE leave",
      subtitle = function(c) return { carLine(c), cash(c) } end,
      build = function()
        local items = {}
        for _, slot in ipairs(mgr.shops:slots()) do
          items[#items + 1] = {
            label = slot.label,
            value = function()
              local tier, max, name, price = mgr.shops:tuneInfo(slot.id)
              if tier >= max then return "MAX" end
              return (name or ("tier " .. tier .. "/" .. max)) .. "  " .. util.money(price)
            end,
            action = function() say(mgr.shops:buyTune(slot.id)) end,
          }
        end
        return items
      end,
    })
  end

  function api.clothes(place)
    screens.menu({
      title = place.name .. ": clothes", width = 40, footer = "W/S choose  ENTER buy or wear  BACKSPACE leave",
      subtitle = function(c) return { cash(c) } end,
      build = function()
        local items = {}
        for _, o in ipairs(mgr.catalog.clothes.outfits) do
          items[#items + 1] = {
            label = o.name, swatch = o.shirt,
            value = function()
              if ctx.save.player.outfit == o.id or (ctx.save.player.outfit == nil and o.id == "deckhand") then return "WORN" end
              if mgr.section.outfits[o.id] then return "owned" end
              return util.money(o.price)
            end,
            action = function() say(mgr.shops:buyOutfit(o.id)) end,
          }
        end
        return items
      end,
    })
  end

  function api.garage(place)
    local g = mgr.garage
    local args
    args = {
      title = place.name, width = 42, footer = "W/S choose  ENTER select  BACKSPACE leave",
      subtitle = function(c)
        return { "Cars kept: " .. g:count() .. "/" .. g:capacity(), carLine(c) }
      end,
      build = function()
        local items = {}
        if ctx.player.car then
          items[#items + 1] = { label = "Store this car", action = function()
            local ok, why = g:store(place)
            say(ok, why)
            if ok then ui.pop() else refresh(args) end
          end }
        end
        for i, e in ipairs(g:cars()) do
          local name, colour = services.describe(ctx, e)
          items[#items + 1] = { label = "Take out: " .. name, swatch = colour:match("^[^:|]*"), action = function()
            local ok, why = g:takeOut(i, place)
            say(ok, why)
            if ok then ui.pop() else refresh(args) end
          end }
        end
        if #items == 0 then items[1] = { label = "Nothing here yet", header = true } end
        items[#items + 1] = { label = "Leave", action = function() ui.pop() end }
        return items
      end,
    }
    screens.menu(args)
  end

  function api.property(place)
    local p = place.def
    if mgr.property:owned(p.id) then
      if ctx.hud then ctx.hud.toast(p.name, "lime", 3, "yours: " .. util.money(p.income) .. " a day") end
      return
    end
    screens.confirm({ p.name, "Price " .. util.money(p.price) .. "   Rent " .. util.money(p.income) .. " a day",
      "Also gives your garage " .. (p.slots or 2) .. " more places." },
      function() say(mgr.property:buy(p.id)) end, "Buy this place?")
  end

  function api.open(kind, place)
    if kind == "shop" then
      if place.shop == "respray" then
        if not ctx.player.car then say(false, "Drive a car in to respray it.") return end
        api.respray(place)
      elseif place.shop == "tune" then
        if not ctx.player.car then say(false, "Drive a car in to tune it.") return end
        api.tune(place)
      else
        api.clothes(place)
      end
    elseif kind == "garage" then
      api.garage(place)
    elseif kind == "property" then
      api.property(place)
    end
  end

  mgr.open = api.open
  return api
end

return M
