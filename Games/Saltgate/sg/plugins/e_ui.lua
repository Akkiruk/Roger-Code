-- plugins/e_ui.lua
-- Stream E: the HUD, the menus (title, pause, settings, controls, stats), transitions and the settings that persist.
-- Other parts reach it as ctx.hud (toasts and hint lines) and ctx.eui (keys, settings, screens, transition):
--   ctx.hud.toast(text, colour, seconds [, sub])     ctx.hud.hint(fn)     ctx.hud.hidden
--   ctx.eui.keys        the menu keys (actions() / pressed(action))
--   ctx.eui.settings    get / set / label
--   ctx.eui.screens     menu(args) confirm(text, yes) settings() controls() stats(tab) title()
--   ctx.eui.transition  start(onCovered, seconds)
-- Needs the main loop only for what the core already does; the keys come from a tee on os.pullEventRaw (ui/keys.lua).

local keysLib = require("sg.ui.keys")
local settingsLib = require("sg.ui.settings")
local transitionLib = require("sg.ui.transition")
local hudLib = require("sg.ui.hud")
local screensLib = require("sg.ui.screens")
local saveLib = require("sg.core.save")

local P = { name = "e_ui", order = 20, needs = { "e_progress" } }

local SAVE_PATH = "saltgate_save2.dat"

local function nowSeconds()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") / 1000 end
  return os.clock()
end

function P.init(ctx)
  local keysTable = rawget(_G, "keys") or {}
  local keys = keysLib.new(keysTable)
  keysLib.attach(keys)
  local save = ctx.save
  save.settings = save.settings or {}
  local settings = settingsLib.new(save.settings)
  local transition = transitionLib.new()
  local hud = hudLib.new(ctx)
  local eui = { keys = keys, settings = settings, transition = transition, lastT = nowSeconds(), titleShown = false }
  ctx.eui = eui
  eui.screens = screensLib.install(ctx, { keys = keys, settings = settings, transition = transition })

  -- a setting changed in a menu is written at once, so it is there next time even if the computer is turned off
  eui.screens.flush = function()
    ctx.bus:emit("save", { data = ctx.save })
    local ok, err = saveLib.write(ctx.fs or rawget(_G, "fs"), ctx.savePath or SAVE_PATH, ctx.save)
    if not ok then ctx.log("settings not saved: " .. tostring(err)) end
  end

  -- a key that opens or closes a screen was meant for the screen before: the one now on top must not read it too
  ctx.bus:on("screen_push", function() keys:flush() end, "e_ui")
  ctx.bus:on("screen_pop", function() keys:flush() end, "e_ui")

  -- a respawn or a door cuts to somewhere else: the curtain draws back from it
  for _, name in ipairs({ "respawn", "interior_enter", "interior_exit" }) do
    ctx.bus:on(name, function() transition:reveal(0.35) end, "e_ui")
  end

  -- graphics quality: AUTO leaves the budget in charge; a number pins it
  local budget = ctx.budget
  local origFrame = budget.frame
  local pinned
  budget.frame = function(self, ...)
    origFrame(self, ...)
    if pinned ~= nil and self.quality ~= pinned then
      local prev = self.quality
      self.quality = pinned
      ctx.bus:emit("quality", { level = pinned, previous = prev })
    end
  end
  settings:hook(function(name, value)
    if name == "quality" then
      if value == "auto" then
        pinned = nil
      else
        pinned = value
        if budget.quality ~= pinned then
          local prev = budget.quality
          budget.quality = pinned
          ctx.bus:emit("quality", { level = pinned, previous = prev })
        end
      end
    end
  end)
  ctx.bus:on("load", function(d)
    if d.data and d.data.settings then
      d.data.settings = d.data.settings or {}
      settings:use(d.data.settings)
      settings:applyAll()
    end
  end, "e_ui")
end

function P.update(ctx, dt)
  ctx.hud.adopt()
  ctx.hud.tick(dt)
  -- the camera key and the rest are the main loop's; here only a title that has not been shown yet
end

function P.draw(ctx)
  local eui = ctx.eui
  local t = nowSeconds()
  eui.dt = math.min(0.25, math.max(0, t - eui.lastT))
  eui.lastT = t
  ctx.hud.adopt()
  -- the title screen, once, before the first frame of play
  if not eui.titleShown then
    local top = ctx.ui.top()
    if top and top.name == "play" then
      eui.titleShown = true
      -- no title over an autopilot demo (bench: the car drives itself) or when the app says so (ctx.noTitle)
      local car = ctx.player.car
      local demo = car and (car.follow ~= nil or math.abs(car.v or 0) > 5)
      local fs_ = ctx.fs or rawget(_G, "fs")
      local skip = ctx.noTitle or (fs_ and fs_.exists and fs_.exists("saltgate_notitle.flag"))
      if not skip and not demo then eui.screens.title() end
    end
  end
end

return require("sg.ui.guard").plugin(P)
