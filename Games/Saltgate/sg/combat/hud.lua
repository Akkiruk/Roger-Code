-- combat/hud.lua
-- What the screen says about guns and vehicles: the key hint line (every key you can press right now, in the 51
-- columns), the weapon and hit points at the bottom right, the lock-on line, messages, and the weapon wheel when you
-- change weapon. Widgets for core/ui.lua.
--
--   hud.hintLine(ctx) -> text      hud.register(ctx)      hud.TEXT (the hint for each situation)

local weapons = require("sg.combat.weapons")
local fx = require("sg.combat.fx")
local hints = require("sg.hints")

local M = {}

local C = rawget(_G, "colors") or rawget(_G, "colours") or {}

-- one key per action; capitals are keys. Each fits in 51 columns.
M.TEXT = {
  foot = "WASD move SHIFT run J fire K aim L gun E car",
  nearCar = "E take car WASD move J fire K aim L gun",
  car = "WASD drive SPACE brake J fire K aim L gun E out",
  bike = "WASD ride SPACE brake J fire K aim L gun E off",
  truck = "WASD drive SPACE brake J fire K aim L gun E out",
  boat = "WASD sail SPACE brake J fire K aim L gun E out",
  down = "Knocked down... getting back up",
}

function M.hintLine(ctx)
  local cb = ctx.combat
  if cb and cb:playerDown() then return M.TEXT.down end
  local car = ctx.player.car
  if car then
    local class = car.spec.class
    return M.TEXT[class == "bike" and "bike" or (class == "boat" and "boat" or (class == "truck" and "truck" or "car"))]
  end
  if ctx.nearCar then return M.TEXT.nearCar end
  return M.TEXT.foot
end

local function put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColour(fg or C.white)
  t.setBackgroundColour(bg or C.black)
  t.write(text)
end

function M.register(ctx)
  local ui = ctx.ui
  -- the hint line: drawn after the core's (lower priority draws later) over its whole row
  ui.widget({ name = "b_hints", slot = "hints", priority = 40, draw = function(c, t)
    local w, h = c.screen.getSize()
    put(t, 1, h, string.rep(" ", w))
    local x = 2
    for word, gap in M.hintLine(c):gmatch("(%S+)(%s*)") do
      if x + #word - 1 > w then break end
      put(t, x, h, word, hints.isKey(word) and C.yellow or C.lightGrey)
      x = x + #word + #gap
    end
  end })
  -- weapon and hit points, bottom right
  ui.widget({ name = "b_weapon", slot = "bottom-right", priority = 50, draw = function(c, t)
    local cb = c.combat
    if not cb then return end
    local w, h = c.screen.getSize()
    local hp = math.floor(cb:hp() + 0.5)
    local wp = cb:weapon()
    local ammo
    if wp.kind == "melee" then ammo = "" else
      local mag, reserve = cb:ammo(wp.id)
      ammo = cb.reloadT > 0 and "RELOAD" or (mag .. "/" .. reserve)
    end
    local text = wp.short .. (ammo ~= "" and (" " .. ammo) or "")
    local hpText = "HP" .. hp
    local total = #hpText + 1 + #text
    local x = w - total
    put(t, x - 1, h - 1, string.rep(" ", total + 2))
    put(t, x, h - 1, hpText, hp < 30 and C.red or (hp < 60 and C.orange or C.lime))
    put(t, x + #hpText + 1, h - 1, text, (cb.reloadT > 0) and C.orange or C.white)
    if cb.lock and not cb.lock.knocked and not cb.lock.removed then
      local p = c.player
      local px, pz = p.x, p.z
      if p.car then px, pz = p.car.x, p.car.z end
      local d = math.floor(math.sqrt((cb.lock.x - px) ^ 2 + (cb.lock.z - pz) ^ 2) + 0.5)
      local label = "LOCK " .. d .. "m"
      put(t, w - #label - 1, h - 2, " " .. label, C.red)
    end
  end })
  -- messages and the weapon wheel, top left under the objective
  ui.widget({ name = "b_messages", slot = "centre", priority = 30, draw = function(c, t)
    local cb = c.combat
    if not cb then return end
    local w = c.screen.getSize()
    local maxw = math.max(10, w - 17)
    if cb.wheelT > 0 then
      local x = 2
      for _, piece in ipairs(fx.wheel(cb)) do
        if x + #piece[1] - 1 > maxw then break end
        put(t, x, 3, piece[1], C[piece[2]] or C.white)
        x = x + #piece[1]
      end
    elseif cb.msg then
      put(t, 2, 3, " " .. cb.msg:sub(1, maxw - 3) .. " ", C.yellow)
    end
  end })
end

local _ = weapons
return M
