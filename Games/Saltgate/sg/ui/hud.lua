-- ui/hud.lua
-- SALTGATE's HUD for the 51x19 terminal, built from widgets in core/ui.lua's slots:
--   row 1       money (with a flash of what just came or went), district and the time, wanted level
--   under the minimap: the compass heading and the district
--   row 2-4     the activity banner (race, taxi, parcels), top left
--   centre      toasts (finds, medals, achievements) and the race count-in
--   row H-2     the prompt for the place you stand at ("ENTER  Race Harbor Dash")
--   row H-1     the car or Wren, speed and a health bar; weapon and ammo on the right
--   row H       the key hints for what you are doing (one key per action)
-- ctx.hud is the small API other parts call:
--   ctx.hud.toast(text, colour, seconds [, sub])      a message in the middle (colour is a name from theme.C)
--   ctx.hud.hint(fn)                                  fn(ctx) -> a hint line or nil; first answer wins (add more specific first)
--   ctx.hud.hidden = true                             hides every widget (the title screen)
-- The numbers it shows: money from ctx.save.player.money, the wanted level from the heat_changed event (or ctx.heat.level),
-- health from ctx.player.health (or the save), the weapon from ctx.player.weapon = { name, ammo, reserve }.

local theme = require("sg.ui.theme")
local C = theme.C
local put, fill = theme.put, theme.fill

local M = {}

M.MAX_HEAT = 6
M.PAGE_SECONDS = 3.5
local KMH = 3.6
local MPH = 2.237

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function colourOf(name)
  return C[name] or C.white
end

--- The compass word for a heading (radians; forward is cos, sin; north is -z).
function M.compass(yaw)
  -- bearing clockwise from north: east (+x) is 90
  local bearing = math.atan2(math.cos(yaw), -math.sin(yaw))
  local i = math.floor((bearing / (math.pi / 4)) + 0.5) % 8
  return COMPASS[i + 1]
end

--- "07:30 PM"-free: just 24 hour "19:30".
function M.clockText(hour)
  local h = math.floor(hour) % 24
  local m = math.floor((hour - math.floor(hour)) * 60)
  return string.format("%02d:%02d", h, m)
end

local function districtName(ctx)
  local ok, layout = pcall(require, "sg.activities.layout")
  local id = ctx.districtName
  if not id then return "" end
  if ok then return layout.districtName(id) end
  return tostring(id)
end

function M.new(ctx, opts)
  opts = opts or {}
  local hud = { toasts = {}, hints = {}, heat = 0, clock = 0, delta = nil, hurt = 0, hidden = false, hour = nil }
  ctx.hud = hud

  function hud.toast(text, colour, seconds, sub, group)
    local t = { text = tostring(text), colour = colour or "white", left = seconds or 3, sub = sub, group = group }
    -- the same message again, or the next one of a group (radio stations), replaces it instead of stacking
    for i, o in ipairs(hud.toasts) do
      if o.text == t.text or (group and o.group == group) then hud.toasts[i] = t return end
    end
    hud.toasts[#hud.toasts + 1] = t
    if #hud.toasts > 4 then table.remove(hud.toasts, 1) end
  end

  function hud.hint(fn) table.insert(hud.hints, 1, fn) end

  function hud.tick(dt)
    hud.clock = hud.clock + dt
    for i = #hud.toasts, 1, -1 do
      local t = hud.toasts[i]
      t.left = t.left - dt
      if t.left <= 0 then table.remove(hud.toasts, i) end
    end
    if hud.delta then
      hud.delta.left = hud.delta.left - dt
      if hud.delta.left <= 0 then hud.delta = nil end
    end
    if hud.hurt > 0 then hud.hurt = hud.hurt - dt end
    local h = ctx.heat
    if type(h) == "table" and type(h.level) == "number" then hud.heat = h.level end
  end

  local bus = ctx.bus
  bus:on("money", function(d)
    if d.amount == 0 then return end
    if hud.delta and hud.delta.left > 1.5 and (hud.delta.n > 0) == (d.amount > 0) then
      hud.delta.n = hud.delta.n + d.amount
      hud.delta.left = 3
    else
      hud.delta = { n = d.amount, left = 3 }
    end
  end, "e_ui")
  bus:on("heat_changed", function(d) hud.heat = d.level end, "e_ui")
  bus:on("player_hurt", function() hud.hurt = 0.4 end, "e_ui")
  bus:on("time_of_day", function(d) hud.hour = d.hour end, "e_ui")
  bus:on("achievement", function(d)
    local a = ctx.progress and ctx.progress.achievements:def(d.id)
    if a then
      hud.toast("ACHIEVEMENT  " .. a.name .. (a.reward and a.reward > 0 and ("  +$" .. a.reward) or ""), "yellow", 5, a.desc)
    end
  end, "e_ui")

  local ui = ctx.ui
  -- the core's own placeholder HUD gives way to this one
  for i = #ui.widgetList, 1, -1 do
    local n = ui.widgetList[i].name
    if n == "core_topbar" or n == "core_status" or n == "core_hints" or n == "core_objective" then table.remove(ui.widgetList, i) end
  end
  local function shown() return not hud.hidden end
  local function size(c) return c.screen.getSize() end

  -- row 1: money, district and time, wanted
  ui.widget({ name = "e_topbar", slot = "top-left", priority = 100, visible = shown, draw = function(c, t)
    local w = size(c)
    fill(t, 1, 1, w, 1, C.black)
    local money = require("sg.util").money(c.save.player.money or 0)
    put(t, 2, 1, money, C.lime)
    local x = 3 + #money
    local mx = x
    if hud.delta then
      local n = hud.delta.n
      local text = (n >= 0 and "+" or "-") .. require("sg.util").money(math.abs(n))
      put(t, x, 1, text, n >= 0 and C.yellow or C.red)
      mx = x + #text
    end
    local pipsW = M.MAX_HEAT * 2 - 1 -- a cell for each level with a gap between
    local hx = w - pipsW - 5
    local label = districtName(c)
    if hud.hour then label = label .. " " .. M.clockText(hud.hour) end
    mx = math.max(14, mx + 1)
    -- the Patrol's own wanted widget (c_wanted: stars, SPOTTED / LOST) draws on the right when it is there; the pips
    -- below are for a game without it
    local patrol = c.heat ~= nil
    put(t, mx, 1, theme.fit(label, (patrol and 33 or hx - 1) - mx), C.lightGray)
    if patrol then return end
    -- wanted: six pips, lit up to the level, flashing while the Patrol is after you
    local flash = hud.heat > 0 and math.floor(hud.clock * 3) % 2 == 0
    put(t, hx, 1, "HEAT", hud.heat > 0 and C.white or C.gray)
    for i = 1, M.MAX_HEAT do
      local on = i <= hud.heat
      put(t, hx + 5 + (i - 1) * 2, 1, " ", C.white, on and (flash and C.blue or C.red) or C.gray)
    end
  end })

  -- under the minimap: where you are facing and the district
  ui.widget({ name = "e_compass", slot = "top-right", priority = 90, visible = function(c)
    return shown() and c.view and c.view.minimapBox ~= nil
  end, draw = function(c, t)
    local b = c.view.minimapBox
    local w, hh = size(c)
    local x0 = math.ceil((b.x0 - 1) / 2)
    local x1 = math.min(w, math.ceil((b.x0 + b.w) / 2))
    local row = math.ceil((b.y0 + b.h) / 3) + 1
    if row > hh - 4 then return end
    local yaw = c.view.cam and c.view.cam.yaw or 0
    local text = M.compass(yaw) .. "  " .. districtName(c)
    fill(t, x0, row, x1 - x0 + 1, 1, C.black)
    put(t, x0, row, theme.fit(text, x1 - x0 + 1), C.lightGray)
    local _ = w
  end })

  -- the activity banner
  ui.widget({ name = "e_activity", slot = "objective", priority = 90, visible = function(c)
    return shown() and c.activities and c.activities:hud() ~= nil
  end, draw = function(c, t)
    local a = c.activities:hud()
    local w = size(c)
    local maxw = (c.view and c.view.minimapBox) and math.ceil((c.view.minimapBox.x0 - 2) / 2) or (w - 14)
    maxw = math.max(20, maxw)
    local function strip(y, text, fg)
      fill(t, 1, y, maxw, 1, C.black)
      put(t, 2, y, theme.fit(text, maxw - 2), fg, C.black)
    end
    strip(2, a.title, C.yellow)
    if a.line then
      strip(3, a.line, a.urgent and C.red or C.white)
      -- an arrow to where you are going, from where the camera looks
      local tx, tz = c.activities:target()
      if tx then
        local p = c.player
        local at = p.car or p
        local yaw = c.view and c.view.cam and c.view.cam.yaw or p.h or 0
        local rel = (math.atan2(tz - at.z, tx - at.x) - yaw + math.pi) % (2 * math.pi) - math.pi
        local arrow = math.abs(rel) <= math.pi / 4 and "\24" or (math.abs(rel) >= 3 * math.pi / 4 and "\25" or (rel > 0 and "\26" or "\27"))
        fill(t, 1, 3, maxw, 1, C.black)
        put(t, 1, 3, " " .. arrow .. " ", C.black, C.yellow)
        put(t, 5, 3, theme.fit(a.line, maxw - 5), a.urgent and C.red or C.white, C.black)
      end
    end
    if a.sub then
      local fg = a.gapSign == 1 and C.red or (a.gapSign == -1 and C.lime or C.lightGray)
      strip(4, a.sub, fg)
    end
  end })

  -- the middle: the count-in and toasts
  ui.widget({ name = "e_centre", slot = "centre", priority = 90, visible = shown, draw = function(c, t)
    local w, h = size(c)
    local a = c.activities and c.activities:hud()
    -- below the minimap and its caption, above the prompt and the status row
    local y = math.max(10, math.floor(h * 0.5) + 1)
    if a and a.centre then
      local text = "  " .. a.centre .. "  "
      theme.centre(t, y, text, C.black, colourOf(a.centreColour or "yellow"), w)
      y = y + 2
    end
    for _, toast in ipairs(hud.toasts) do
      for _, line in ipairs(theme.wrap(toast.text, w - 8)) do
        theme.centre(t, y, " " .. line .. " ", colourOf(toast.colour), C.black, w)
        y = y + 1
      end
      if toast.sub then
        for _, line in ipairs(theme.wrap(toast.sub, w - 6)) do
          theme.centre(t, y, " " .. line .. " ", C.lightGray, C.black, w)
          y = y + 1
        end
      end
      if y > h - 3 then break end
    end
  end })

  -- the place you stand at
  ui.widget({ name = "e_prompt", slot = "hints", priority = 95, visible = function(c)
    return shown() and c.activities and c.activities:prompt() ~= nil
  end, draw = function(c, t)
    local w, h = size(c)
    local p = c.activities:prompt()
    local key = p.key and (p.key .. " ") or ""
    local text = key .. p.text
    text = theme.fit(text, w - 4)
    local x = math.max(1, math.floor((w - #text) / 2))
    fill(t, 1, h - 2, w, 1, C.black)
    if p.key then
      put(t, x + 1, h - 2, p.key, C.yellow)
      put(t, x + 2 + #p.key, h - 2, theme.fit(p.text, w - 6 - #p.key), C.white)
    else
      put(t, x + 1, h - 2, text, C.lightGray)
    end
  end })

  -- status: the car or Wren, a health bar, speed; on the right the weapon and the radio
  ui.widget({ name = "e_status", slot = "status", priority = 90, visible = shown, draw = function(c, t)
    local w, h = size(c)
    local y = h - 1
    local bg = hud.hurt > 0 and C.red or C.black
    fill(t, 1, y, w, 1, C.black)
    local car = c.player.car
    local frac, label
    local speedText = ""
    if car then
      label = theme.fit(car.spec and car.spec.name or "Car", 13)
      local mph = c.save.settings.units == "mph"
      speedText = math.floor(math.abs(car.v or 0) * (mph and MPH or KMH) + 0.5) .. (mph and " mph" or " km/h")
      frac = car.spec and car.spec.health and car.spec.health > 0 and car.health / car.spec.health or 1
    else
      label = "Wren"
      frac = (c.combat and c.combat.hp and c.combat:hp() or c.player.health or c.save.player.health or 100) / 100
    end
    put(t, 2, y, label, car and C.white or C.orange, bg)
    theme.bar(t, 16, y, 8, frac, frac > 0.35 and C.lime or C.red, C.gray)
    if car then put(t, 26, y, speedText, car.airborne and C.cyan or C.lightGray) end
    -- on the right: the weapon (stream B's combat, or a plain { name, ammo, reserve } on the player), else the radio
    local text, tcol
    local cb = c.combat
    local weapon = c.player.weapon
    if cb and cb.weapon then
      local wp = cb:weapon()
      text = wp.short
      if wp.kind ~= "melee" then
        local mag, reserve = cb:ammo(wp.id)
        text = text .. " " .. (cb.reloadT and cb.reloadT > 0 and "RELOAD" or (mag .. "/" .. reserve))
        tcol = ((cb.reloadT or 0) > 0 and C.orange) or (mag == 0 and C.red) or C.white
      end
      if cb.lock and not cb.lock.knocked and not cb.lock.removed then
        local at = c.player.car or c.player
        local d = math.floor(math.sqrt((cb.lock.x - at.x) ^ 2 + (cb.lock.z - at.z) ^ 2) + 0.5)
        local label = "LOCK " .. d .. "m"
        put(t, w - #label, h - 2, label, C.red)
      end
    elseif type(weapon) == "table" and weapon.name then
      text = weapon.name:upper() .. " " .. tostring(weapon.ammo or 0) .. (weapon.reserve and ("/" .. weapon.reserve) or "")
      tcol = (weapon.ammo or 1) == 0 and C.red or C.white
    end
    if text then
      put(t, w - #text, y, theme.fit(text, 15), tcol or C.white)
    elseif car and hud.radioLine and hud.radioLine() then
      local radio = theme.fit(hud.radioLine(), 15)
      put(t, w - #radio, y, radio, C.cyan)
    end
  end })

  -- the key hints
  ui.widget({ name = "e_hints", slot = "hints", priority = 50, visible = shown, draw = function(c, t)
    local w, h = size(c)
    fill(t, 1, h, w, 1, C.black)
    if c.save.settings.hints == false then return end
    local text
    for _, fn in ipairs(hud.hints) do
      text = fn(c)
      if text then break end
    end
    -- a provider may answer with a list of pages: they take turns every few seconds
    if type(text) == "table" then text = text[math.floor(hud.clock / M.PAGE_SECONDS) % #text + 1] end
    if text then theme.keyline(t, 2, h, w - 2, text, C.yellow, C.lightGray, C.black) end
  end })

  -- the default hint lines
  hud.hint(function(c)
    local a = c.activities and c.activities:hud()
    local car = c.player.car
    local cb = c.combat
    local ok, combatHud = pcall(require, "sg.combat.hud")
    local gun = cb and ok and combatHud.hintLine and combatHud.hintLine(c) or nil
    local phone = c.story and " T phone" or ""
    local station = ""
    if car and c.radio then
      local s = c.radio:current()
      station = s and (" R " .. s.name) or " R radio"
    end
    if a then return "WASD drive  X abandon  R radio  P menu" end
    if car then
      if gun then return { gun, "M map  P menu  C camera" .. phone .. station } end
      return "WASD drive SPACE handbrake E out R radio P menu"
    end
    if c.nearCar then
      if gun then return { gun, "M map  P menu  SHIFT run" .. phone } end
      return "E take car  WASD move  SHIFT run  M map  P menu"
    end
    if gun then return { gun, "M map  P menu  C camera" .. phone } end
    return "WASD move  SHIFT run  E car  M map  P menu"
  end)

  --- Take over from the other streams' placeholders once they have registered (the first frame): their hint line, weapon
  -- and hit points are drawn here, in one place, with the same keys on every screen.
  function hud.adopt()
    if hud.adopted then return end
    hud.adopted = true
    for i = #ui.widgetList, 1, -1 do
      local n = ui.widgetList[i].name
      if n == "b_hints" or n == "b_weapon" then table.remove(ui.widgetList, i) end
    end
  end

  return hud
end

return M
