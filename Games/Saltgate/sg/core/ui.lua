-- core/ui.lua
-- The screen stack and the HUD: plugins add screens (a phone, a shop, the garage) and HUD widgets (a race timer,
-- the radio name) by registering them here, so nobody edits the main loop. Pure.
--
-- A screen: { name, draw(ctx), input(ctx, inp) [optional], update(ctx, dt) [optional], modal (bool: the game
-- under it stops), keepsWorld (bool: the 3D world is drawn under it) }
--   ui.screen(def)             register (a name may be registered once)
--   ui.push(name, args)  ui.pop()  ui.top() -> screen, args  ui.has(name)  ui.depth()
--   ui.modal() -> true when the top screen stops the game
--
-- A HUD widget: { name, slot, priority, draw(ctx), visible(ctx) [optional] }
--   slots: "top-left", "top-right", "objective", "centre", "status", "hints", "bottom-right"
--   ui.widget(def)  ui.widgets(slot) -> visible widgets in that slot, highest priority first

local M = {}

M.SLOTS = { ["top-left"] = true, ["top-right"] = true, objective = true, centre = true, status = true, hints = true,
  ["bottom-right"] = true }

function M.new(bus)
  local self = { screens = {}, stack = {}, widgetList = {}, bus = bus }

  function self.screen(def)
    if type(def.name) ~= "string" or type(def.draw) ~= "function" then error("a screen needs a name and draw", 2) end
    if self.screens[def.name] then error("screen '" .. def.name .. "' is registered twice", 2) end
    self.screens[def.name] = def
    return def
  end

  function self.push(name, args)
    local s = self.screens[name]
    if not s then error("no screen '" .. tostring(name) .. "'", 2) end
    self.stack[#self.stack + 1] = { screen = s, args = args or {} }
    if self.bus then self.bus:emit("screen_push", { name = name }) end
  end

  function self.pop()
    local top = table.remove(self.stack)
    if top and self.bus then self.bus:emit("screen_pop", { name = top.screen.name }) end
    return top and top.screen
  end

  function self.replace(name, args)
    self.stack = {}
    self.push(name, args)
  end

  function self.top()
    local t = self.stack[#self.stack]
    if not t then return nil end
    return t.screen, t.args
  end

  function self.has(name)
    for _, e in ipairs(self.stack) do
      if e.screen.name == name then return true end
    end
    return false
  end

  function self.depth() return #self.stack end

  function self.modal()
    local t = self.top()
    return t ~= nil and t.modal == true
  end

  function self.widget(def)
    if type(def.name) ~= "string" or type(def.draw) ~= "function" then error("a widget needs a name and draw", 2) end
    if not M.SLOTS[def.slot] then error("widget '" .. def.name .. "': unknown slot " .. tostring(def.slot), 2) end
    for _, w in ipairs(self.widgetList) do
      if w.name == def.name then error("widget '" .. def.name .. "' is registered twice", 2) end
    end
    def.priority = def.priority or 50
    self.widgetList[#self.widgetList + 1] = def
    return def
  end

  function self.widgets(slot, ctx)
    local out = {}
    for _, w in ipairs(self.widgetList) do
      if w.slot == slot and (not w.visible or w.visible(ctx)) then out[#out + 1] = w end
    end
    table.sort(out, function(a, b)
      if a.priority ~= b.priority then return a.priority > b.priority end
      return a.name < b.name
    end)
    return out
  end

  return self
end

return M
