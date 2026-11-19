-- ui/screens.lua
-- SALTGATE's menus on the screen stack: the title, the pause menu, settings, controls, the stats / achievements /
-- completion screen, a confirm box and a general list menu the shops and the garage use. Every one reads its keys from
-- ui/keys.lua (W/S or the arrows move, A/D change a value, ENTER selects, BACKSPACE goes back) and draws with ui/theme.lua.
--
--   local s = screens.install(ctx, { keys = keysObject, settings = settingsObject, transition = transitionObject })
--   s.menu(args)            push a list menu: { title, items | build(ctx), subtitle = text|fn, footer, width, onBack, draw }
--   s.confirm(text, yes)    push a yes/no box
--   s.title()               push the title screen
--   s.settings() s.controls() s.stats(tab)
-- The core's "pause" and "map" screens are kept (the main loop pushes them) and given this look.

local theme = require("sg.ui.theme")
local menuLib = require("sg.ui.menu")
local settingsLib = require("sg.ui.settings")
local hudLib = require("sg.ui.hud")
local statsLib = require("sg.progress.stats")
local C = theme.C
local put, fill, centre = theme.put, theme.fill, theme.centre

local M = {}

M.FOOT = "W/S choose  ENTER select  BACKSPACE back"
M.FOOT_ADJUST = "W/S choose  A/D change  BACKSPACE back"

M.CONTROLS = {
  { "On foot and in a car", nil },
  { "W A S D", "move, or drive (the arrows work too)" },
  { "SHIFT", "run" },
  { "SPACE", "handbrake" },
  { "E", "get in or out of a car" },
  { "H", "horn" },
  { "Everywhere", nil },
  { "ENTER", "use a place (race, shop, garage)" },
  { "X", "abandon a race, shift or run" },
  { "R", "radio station (then off)" },
  { "C", "camera" },
  { "M", "map" },
  { "P", "pause menu" },
  { "F3", "frame times" },
}

local function colourOf(name) return C[name] or C.white end

-- ---------------------------------------------------------------- running a menu from a screen's draw

--- Feed this frame's keys to a menu. Returns "back" when BACKSPACE (or P/TAB) was pressed, "done" when the screen changed.
local function run(ctx, keys, menu, args)
  local top = ctx.ui.top()
  for _, e in ipairs(keys.queue) do
    local a = e.action
    if a == "up" or a == "down" or a == "left" or a == "right" then
      menu:handle(a)
    elseif a == "select" and not e.held then
      menu:handle("select")
      if ctx.ui.top() ~= top then return "done" end
    elseif a == "back" and not e.held then
      if args and args.onBack then args.onBack() else ctx.ui.pop() end
      return "done"
    end
  end
  return nil
end

local function footerLine(t, x, y, w, text)
  fill(t, x, y, w, 1, theme.PANEL)
  theme.keyline(t, x + 1, y, w - 2, text, C.yellow, C.lightGray, theme.PANEL)
end

function M.install(ctx, deps)
  local keys, settings, transition = deps.keys, deps.settings, deps.transition
  local ui = ctx.ui
  local api = {}

  -- ---------------------------------------------------------------- the general list menu

  local function layoutFor(t, args, rows, sub)
    local w, h = t.getSize()
    local pw = math.min(w - 2, args.width or 40)
    local maxRows = h - 6 - sub
    local shown = math.min(rows, maxRows)
    local ph = shown + 3 + sub
    return math.floor((w - pw) / 2) + 1, math.floor((h - ph) / 2) + 1, pw, ph, shown
  end

  local function drawMenu(c, args)
    local t = c.screen
    if not args.menu then
      args.menu = menuLib.new(args.items or args.build(c))
      if args.keepSel then
        args.menu.sel = math.max(1, math.min(args.keepSel, #args.menu.items))
        args.menu:settle(1)
        args.keepSel = nil
      end
    end
    if run(c, keys, args.menu, args) then return end
    local sub = args.subtitle
    if type(sub) == "function" then sub = sub(c) end
    local subLines = type(sub) == "table" and sub or (sub and { sub } or {})
    local x, y, w, h, shown = layoutFor(t, args, #args.menu.items, #subLines)
    local ix, iy, iw = theme.panel(t, x, y, w, h, args.title)
    local row = iy
    for _, line in ipairs(subLines) do
      fill(t, ix, row, iw, 1, theme.PANEL)
      put(t, ix + 1, row, theme.fit(line, iw - 2), C.lightGray, theme.PANEL)
      row = row + 1
    end
    args.menu:draw(t, ix, row, iw, shown)
    footerLine(t, x + 1, y + h - 1, w - 2, args.footer or M.FOOT)
  end

  ui.screen({ name = "e_menu", modal = true, keepsWorld = true, draw = function(c)
    local _, args = ui.top()
    drawMenu(c, args)
  end })

  function api.menu(args)
    ui.push("e_menu", args)
  end

  function api.confirm(text, yes, title)
    api.menu({
      title = title or "Are you sure?", width = 36, footer = "W/S choose  ENTER select",
      subtitle = type(text) == "table" and text or { text },
      items = {
        { label = "Yes", action = function() ui.pop() if yes then yes() end end },
        { label = "No", action = function() ui.pop() end },
      },
    })
  end

  -- ---------------------------------------------------------------- settings and controls

  function api.settings()
    local function toggleItem(label, name, extra)
      return { id = name, label = label, value = function() return settings:label(name) end,
        change = function(dir) settings:cycle(name, dir) if api.flush then api.flush() end end, enabled = extra }
    end
    api.menu({
      title = "Settings", width = 42, footer = M.FOOT_ADJUST,
      items = {
        toggleItem("Sound effects", "sound"),
        toggleItem("Music and radio", "music"),
        toggleItem("Music volume", "musicVolume", function() return settings:get("music") end),
        toggleItem("Graphics quality", "quality"),
        toggleItem("Key hints", "hints"),
        toggleItem("Speed units", "units"),
        { label = "Controls help", action = function() api.controls() end },
        { label = "Back", action = function() ui.pop() end },
      },
    })
  end

  function api.controls()
    api.menu({
      title = "Controls", width = 49, footer = "BACKSPACE back",
      items = { { label = "Back", action = function() ui.pop() end } },
      hideItems = true,
      body = function(c, t, x, y, w, h)
        local row = y
        for _, r in ipairs(M.CONTROLS) do
          if row > y + h - 1 then break end
          if r[2] == nil then
            put(t, x, row, theme.fit(r[1], w), C.orange, theme.PANEL)
          else
            put(t, x + 1, row, r[1], C.yellow, theme.PANEL)
            put(t, x + 11, row, theme.fit(r[2], w - 11), C.white, theme.PANEL)
          end
          row = row + 1
        end
      end,
    })
  end

  -- a menu with a body of its own instead of rows (controls): replaces the draw of e_menu for that args table
  local plain = ui.screens.e_menu.draw
  ui.screens.e_menu.draw = function(c)
    local _, args = ui.top()
    if args.body then
      local t = c.screen
      local w, h = t.getSize()
      local pw = math.min(w - 2, args.width or 40)
      local ph = h - 2
      local x, y = math.floor((w - pw) / 2) + 1, 2
      for _, e in ipairs(keys.queue) do
        if (e.action == "back" or e.action == "select") and not e.held then
          ui.pop()
          return
        end
      end
      local ix, iy, iw, ih = theme.panel(t, x, y, pw, ph, args.title)
      args.body(c, t, ix, iy, iw, ih - 1)
      footerLine(t, x + 1, y + ph - 1, pw - 2, args.footer or M.FOOT)
      return
    end
    plain(c)
  end

  -- ---------------------------------------------------------------- stats, achievements and the 100% tracker

  local TABS = { "Progress", "Stats", "Awards" }

  local function tabBar(t, x, y, w, tab)
    fill(t, x, y, w, 1, theme.PANEL)
    local cx = x + 1
    for i, name in ipairs(TABS) do
      local on = i == tab
      put(t, cx, y, " " .. name .. " ", on and C.black or C.lightGray, on and C.yellow or theme.PANEL)
      cx = cx + #name + 3
    end
  end

  local function progressBody(c, t, x, y, w, h)
    local res = c.progress.completion:compute()
    put(t, x + 1, y, "Completion", C.white, theme.PANEL)
    local text = c.progress.completion:display() .. "%"
    put(t, x + w - #text - 1, y, text, res.percent >= 100 and C.yellow or C.lime, theme.PANEL)
    theme.bar(t, x + 1, y + 1, w - 2, res.percent / 100, res.percent >= 100 and C.yellow or C.lime, C.black)
    local row = y + 3
    for _, p in ipairs(res.parts) do
      if row > y + h - 1 then break end
      local frac = p.done / p.total
      put(t, x + 1, row, theme.fit(p.name, 17), frac >= 1 and C.lime or C.white, theme.PANEL)
      local count = p.done .. "/" .. p.total
      put(t, x + 19, row, count, C.lightGray, theme.PANEL)
      theme.thinBar(t, x + 28, row, 11, frac, frac >= 1 and C.lime or C.orange, C.black, theme.PANEL)
      local pts = string.format("%.1f", p.points)
      put(t, x + w - #pts - 1, row, pts, C.yellow, theme.PANEL)
      row = row + 1
    end
  end

  local function statsBody(c, t, x, y, w, h, scroll)
    local n = #statsLib.LIST
    local rows = h
    if scroll > n - rows then scroll = math.max(0, n - rows) end
    for i = 1, rows do
      local s = statsLib.LIST[i + scroll]
      fill(t, x, y + i - 1, w, 1, theme.PANEL)
      if s then
        put(t, x + 1, y + i - 1, s[2], C.white, theme.PANEL)
        local v = statsLib.format(s[3], s[1] == "maxHeat" and c.progress.stats:get(s[1]) or c.progress.stats:get(s[1]))
        put(t, x + w - #v - 1, y + i - 1, v, C.yellow, theme.PANEL)
      end
    end
    return scroll
  end

  local function awardsBody(c, t, x, y, w, h, args)
    local list = c.progress.achievements:list()
    local rows = h - 2
    args.sel = math.max(1, math.min(args.sel or 1, #list))
    if args.sel <= args.scroll then args.scroll = args.sel - 1 end
    if args.sel > args.scroll + rows then args.scroll = args.sel - rows end
    for i = 1, rows do
      local idx = i + args.scroll
      local a = list[idx]
      local on = idx == args.sel
      local bg = on and C.orange or theme.PANEL
      fill(t, x, y + i - 1, w, 1, bg)
      if a then
        put(t, x + 1, y + i - 1, a.unlocked and "\4" or "-", on and C.black or (a.unlocked and C.lime or C.lightGray), bg)
        put(t, x + 3, y + i - 1, theme.fit(a.name, w - 12), on and C.black or (a.unlocked and C.white or C.lightGray), bg)
        local r = a.reward and a.reward > 0 and ("$" .. a.reward) or ""
        put(t, x + w - #r - 1, y + i - 1, r, on and C.black or (a.unlocked and C.yellow or C.lightGray), bg)
      end
    end
    local sel = list[args.sel]
    fill(t, x, y + h - 2, w, 2, theme.PANEL)
    if sel then
      put(t, x + 1, y + h - 2, theme.fit(sel.desc, w - 2), C.white, theme.PANEL)
    end
    local done = c.progress.achievements:count()
    put(t, x + 1, y + h - 1, done .. "/" .. c.progress.achievements:total() .. " unlocked", C.orange, theme.PANEL)
  end

  ui.screen({ name = "e_stats", modal = true, keepsWorld = true, draw = function(c)
    local _, args = ui.top()
    args.tab = args.tab or 1
    args.scroll = args.scroll or 0
    for _, e in ipairs(keys.queue) do
      local a = e.action
      if a == "left" and not e.held then args.tab = (args.tab + 1) % #TABS + 1 args.scroll = 0
      elseif a == "right" and not e.held then args.tab = args.tab % #TABS + 1 args.scroll = 0
      elseif a == "down" then
        if args.tab == 3 then args.sel = (args.sel or 1) + 1 else args.scroll = args.scroll + 1 end
      elseif a == "up" then
        if args.tab == 3 then args.sel = (args.sel or 1) - 1 else args.scroll = math.max(0, args.scroll - 1) end
      elseif a == "back" and not e.held then ui.pop() return end
    end
    local t = c.screen
    local w, h = t.getSize()
    local pw, ph = math.min(w - 2, 49), h - 2
    local x, y = math.floor((w - pw) / 2) + 1, 2
    local ix, iy, iw, ih = theme.panel(t, x, y, pw, ph, "Wren Calloway: progress")
    tabBar(t, ix, iy, iw, args.tab)
    local by, bh = iy + 1, ih - 3
    if args.tab == 1 then
      progressBody(c, t, ix, by, iw, bh)
    elseif args.tab == 2 then
      args.scroll = statsBody(c, t, ix, by, iw, bh, args.scroll)
    else
      awardsBody(c, t, ix, by, iw, bh, args)
    end
    footerLine(t, x + 1, y + ph - 1, pw - 2, "A/D tab  W/S scroll  BACKSPACE back")
  end })

  function api.stats(tab)
    ui.push("e_stats", { tab = tab or 1 })
  end

  -- ---------------------------------------------------------------- the pause menu

  local function quit()
    os.queueEvent("terminate")
  end

  local pauseItems = function()
    local items = {
      { label = "Resume", action = function() ui.pop() end },
      { label = "Map", action = function() ui.pop() ui.push("map") end },
    }
    if ui.screens.phone then
      items[#items + 1] = { label = "Phone", action = function() ui.push("phone") end }
    end
    items[#items + 1] = { label = "Progress and stats", action = function() api.stats(1) end }
    items[#items + 1] = { label = "Achievements", action = function() api.stats(3) end }
    items[#items + 1] = { label = "Settings", action = function() api.settings() end }
    items[#items + 1] = { label = "Controls", action = function() api.controls() end }
    items[#items + 1] = { label = "Save and quit", action = function() quit() end }
    return items
  end

  local pause = ui.screens.pause
  if pause then
    pause.draw = function(c)
      local _, args = ui.top()
      args.title = "Paused"
      args.width = 38
      args.footer = "W/S choose  ENTER select  P resume"
      if not args.items then
        args.items = pauseItems()
        args.subtitle = function(cc)
          return { "Wren Calloway   " .. cc.progress.completion:display() .. "% complete" }
        end
      end
      -- the core handles P (resume), M (map) and Q (save and quit) itself on this screen
      drawMenu(c, args)
    end
  end

  -- ---------------------------------------------------------------- the title screen

  local function titleWorld(c, dt, state)
    local view = c.view
    local t = c.screen
    local ok = pcall(function()
      local r = view.r
      local p = c.player
      local at = p.car or p
      state.angle = (state.angle or 0) + dt * 0.18
      local rad = 14
      local cx, cz = at.x + math.cos(state.angle) * rad, at.z + math.sin(state.angle) * rad
      local ay = at.y or 0
      local gy = c.stream:groundAt(cx, cz, ay + 6) or ay
      local cy = math.max(ay + 5.5, gy + 3)
      local yaw = math.atan2(at.z - cz, at.x - cx)
      local pitch = -math.deg(math.atan2(cy - (ay + 1.2), rad))
      view.cam = { x = cx, y = cy, z = cz, yaw = yaw, pitch = pitch }
      r.cam = view.cam
      r.frame:setCamera(cx, cy, cz, 0, math.deg(yaw), pitch)
      r:paintSky(C.blue)
      r.frame:drawObjects(view:scene(c))
      local bigtext = require("sg.bigtext")
      local word = "SALTGATE"
      local scale = math.max(1, math.floor(r.pw / (#word * 4 + 6)))
      local x = math.floor((r.pw - bigtext.width(word, scale)) / 2) + 1
      bigtext.draw(r.buffer.colorValues, word, x, math.max(3, math.floor(r.ph * 0.1)), scale, C.yellow, C.black)
      r.frame:drawBuffer()
    end)
    if not ok then
      fill(t, 1, 1, (t.getSize()), select(2, t.getSize()), C.black)
    end
    return ok
  end

  local titleState = {}
  ui.screen({ name = "e_title", modal = true, draw = function(c, dt)
    local _, args = ui.top()
    local t = c.screen
    local w, h = t.getSize()
    if not args.menu then
      local items = {
        { label = "Play", action = function()
            if transition:start(function() ui.pop() c.hud.hidden = false end, 0.3) then end
          end },
        { label = "Stats and awards", action = function() api.stats(1) end },
        { label = "Settings", action = function() api.settings() end },
        { label = "Controls", action = function() api.controls() end },
        { label = "Quit", action = function() quit() end },
      }
      args.menu = menuLib.new(items, { bg = C.black })
    end
    if run(c, keys, args.menu, nil) then return end
    local ok = titleWorld(c, dt or 0.05, titleState)
    local rowTitle = math.floor(h * 0.1) + 4
    centre(t, rowTitle + 1, " L O W   T I D E ", C.orange, C.black, w)
    local mw = 24
    local mx = math.floor((w - mw) / 2) + 1
    local items = #args.menu.items
    local my = h - items - 3
    fill(t, mx - 1, my - 1, mw + 2, items + 2, C.black)
    args.menu:draw(t, mx, my, mw, items)
    fill(t, 1, h, w, 1, C.black)
    theme.keyline(t, 2, h, w - 2, "W/S choose  ENTER select", C.yellow, C.lightGray, C.black)
    local _ = ok
  end })

  function api.title()
    ctx.hud.hidden = true
    ui.push("e_title", {})
  end

  -- ---------------------------------------------------------------- the map screen gets its legend and icons

  local map = ui.screens.map
  if map then
    local orig = map.draw
    map.draw = function(c, dt)
      orig(c, dt)
      local ok = pcall(function() api.mapOverlay(c) end)
      local _ = ok
    end
  end

  function api.mapOverlay(c)
    local t = c.screen
    local w, h = t.getSize()
    local view = c.view
    local project = view and view.mapProject
    if not project then
      local chunks = require("sg.core.testbed").chunks()
      local chunkLib = require("sg.core.chunk")
      local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
      for _, ch in pairs(chunks) do
        local a, b, cc, d = chunkLib.bounds(ch)
        x0, z0, x1, z1 = math.min(x0, a), math.min(z0, b), math.max(x1, cc), math.max(z1, d)
      end
      local W, H = view.r.pw, view.r.ph
      local scale = math.max((x1 - x0) / (W - 2), (z1 - z0) / (H - 6))
      local ox = (W - (x1 - x0) / scale) / 2
      local oy = 4 + (H - 4 - (z1 - z0) / scale) / 2
      project = function(x, z)
        return math.ceil(math.floor(ox + (x - x0) / scale) / 2), math.ceil(math.floor(oy + (z - z0) / scale) / 3)
      end
    end
    fill(t, 1, 1, w, 1, C.black)
    centre(t, 1, "SALTGATE", C.yellow, C.black, w)
    local pct = c.progress.completion:display() .. "%"
    put(t, w - #pct, 1, pct, C.lime, C.black)
    theme.keyline(t, 2, 1, 8, "M close", C.yellow, C.lightGray, C.black)
    fill(t, 1, h, w, 1, C.black)
    local lx = 2
    for _, e in ipairs({ { "R", "orange", "race" }, { "T", "yellow", "taxi" }, { "D", "brown", "depot" }, { "$", "magenta", "shop" },
      { "G", "cyan", "garage" }, { "H", "lime", "home" } }) do
      put(t, lx, h, e[1], C[e[2]], C.black)
      put(t, lx + 2, h, e[3], C.lightGray, C.black)
      lx = lx + #e[3] + 4
    end
    if c.activities then
      for _, m in ipairs(c.activities:mapMarkers()) do
        local cx, cy = project(m.x, m.z)
        if cx and cy and cy >= 2 and cy <= h - 1 and cx >= 1 and cx <= w then put(t, cx, cy, m.icon, C[m.colour] or C.white, C.black) end
      end
    end
  end

  api.keys, api.settings_, api.transition = keys, settings, transition
  return api
end

M.colourOf = colourOf
M.hudLib = hudLib
M.settingsLib = settingsLib

return M
