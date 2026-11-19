-- ui/testkit.lua
-- What stream E's tests build their games from: a term that remembers what was drawn (text, colours), CC key codes, and a
-- context like the app's, with the real plugins loaded. Not used by the game itself.

local events = require("sg.core.events")
local entity = require("sg.core.entity")
local uiLib = require("sg.core.ui")
local saveLib = require("sg.core.save")
local contentLib = require("sg.core.content")
local budgetLib = require("sg.core.budget")
local vehicles = require("sg.core.vehicles")
local plugins = require("sg.core.plugins")

local M = {}

-- CC's key codes for the keys the menus and the game use
M.KEYS = {
  w = 87, a = 65, s = 83, d = 68, e = 69, r = 82, x = 88, m = 77, p = 80, c = 67, h = 72, q = 81,
  up = 265, down = 264, left = 263, right = 262, enter = 257, numPadEnter = 335, backspace = 259, tab = 258, space = 32,
  leftShift = 340, rightShift = 344, f3 = 292, f = 70,
}

--- A term that keeps what was written: cell(x, y) -> char, fg, bg; row(y) -> text; find(text) -> x, y.
function M.term(w, h)
  w, h = w or 51, h or 19
  local t = { overflow = 0, w = w, h = h, cx = 1, cy = 1, fg = 1, bg = 32768, chars = {}, fgs = {}, bgs = {} }
  for y = 1, h do
    t.chars[y], t.fgs[y], t.bgs[y] = {}, {}, {}
    for x = 1, w do t.chars[y][x], t.fgs[y][x], t.bgs[y][x] = " ", 1, 32768 end
  end
  function t.getSize() return w, h end
  function t.setCursorPos(x, y) t.cx, t.cy = x, y end
  function t.setTextColour(c) t.fg = c end
  function t.setBackgroundColour(c) t.bg = c end
  function t.write(text)
    text = tostring(text)
    for i = 1, #text do
      local x = t.cx + i - 1
      if x >= 1 and x <= w and t.cy >= 1 and t.cy <= h then
        t.chars[t.cy][x], t.fgs[t.cy][x], t.bgs[t.cy][x] = text:sub(i, i), t.fg, t.bg
      else
        t.overflow = t.overflow + 1 -- a screen must never write past the edge: CC would wrap or clip it
      end
    end
    t.cx = t.cx + #text
  end
  function t.clear()
    for y = 1, h do for x = 1, w do t.chars[y][x], t.fgs[y][x], t.bgs[y][x] = " ", 1, t.bg end end
  end
  function t.cell(x, y) return t.chars[y][x], t.fgs[y][x], t.bgs[y][x] end
  function t.row(y) return table.concat(t.chars[y]) end
  function t.text()
    local rows = {}
    for y = 1, h do rows[y] = t.row(y) end
    return table.concat(rows, "\n")
  end
  function t.find(text)
    for y = 1, h do
      local x = t.row(y):find(text, 1, true)
      if x then return x, y end
    end
    return nil
  end
  return t
end

--- Where the game's files are for the tests: the emulator lays the repo out under /repo, desktop Lua runs from its root.
local function root()
  local fs_ = rawget(_G, "fs")
  if fs_ and fs_.exists and fs_.exists("/repo/Games/Saltgate") then return "/repo/Games/Saltgate" end
  return "Games/Saltgate"
end
M.root = root

local function realFs()
  local fs_ = rawget(_G, "fs")
  if fs_ and fs_.exists then return fs_ end
  -- desktop Lua: just enough of fs for core/content.lua
  local shim = {}
  function shim.exists(p)
    local h = io.open(p, "rb")
    if h then h:close() return true end
    return false
  end
  function shim.list() return {} end
  function shim.open(p, mode)
    local h = io.open(p, mode == "r" and "rb" or "wb")
    if not h then return nil end
    return { readAll = function() return h:read("*a") end, write = function(s) h:write(s) end, close = function() h:close() end }
  end
  return shim
end
M.realFs = realFs

--- Make the global `keys` table exist (CC has it; desktop Lua does not).
function M.installKeys()
  if rawget(_G, "keys") == nil then _G.keys = M.KEYS end
  -- sg/models.lua reads CC's colors table when it loads
  if rawget(_G, "colors") == nil then _G.colors = require("sg.ui.theme").C end
  if rawget(_G, "colours") == nil then _G.colours = rawget(_G, "colors") end
end

--- The context the plugins expect, with the screens the core would have registered, and the named plugins loaded.
-- opts: names (plugin list, default all of E's), w/h (terminal size), money.
function M.game(opts)
  opts = opts or {}
  M.installKeys()
  local bus = events.new()
  vehicles.reset()
  vehicles.registerLegacy()
  local ctx = {
    bus = bus, world = entity.new({ cell = 32 }), content = contentLib.new({ fs = realFs(), root = root() .. "/content" }),
    ui = uiLib.new(bus), vehicles = vehicles, budget = budgetLib.new({ bus = bus }), cars = {},
    log = function(msg) M.logged[#M.logged + 1] = msg end,
    screen = M.term(opts.w, opts.h), save = opts.save or saveLib.blank(), stream = opts.stream, player = { x = 0, y = 0, z = 0, h = 0, v = 0 },
  }
  M.logged = {}
  ctx.fs = opts.fs
  if opts.money then ctx.save.player.money = opts.money end
  -- the play screen draws the HUD's widgets the way core/view.lua does (there is no 3D frame under them here)
  ctx.ui.screen({ name = "play", draw = function(c)
    c.screen.setBackgroundColour(32768)
    c.screen.clear()
    for _, slot in ipairs({ "top-left", "top-right", "objective", "centre", "status", "hints", "bottom-right" }) do
      for _, w in ipairs(c.ui.widgets(slot, c)) do w.draw(c, c.screen) end
    end
  end })
  ctx.ui.screen({ name = "map", modal = true, draw = function() end })
  ctx.ui.screen({ name = "pause", modal = true, draw = function() end })
  local loaded, failed = plugins.load(opts.names or { "e_progress", "e_ui", "e_activities", "e_radio", "e_zlast" }, ctx)
  ctx.plugins = loaded
  ctx.failed = failed
  ctx.ui.push("play")
  return ctx
end

--- A file system in memory, shaped like CC's fs (just what core/save.lua uses).
function M.memfs(files)
  files = files or {}
  local fs = {}
  function fs.exists(p) return files[p] ~= nil end
  function fs.open(p, mode)
    if mode == "r" then
      if not files[p] then return nil end
      return { readAll = function() return files[p] end, close = function() end }
    end
    local buf = {}
    return { write = function(s) buf[#buf + 1] = s end, close = function() files[p] = table.concat(buf) end }
  end
  function fs.delete(p) files[p] = nil end
  function fs.move(a, b) files[b], files[a] = files[a], nil end
  return fs, files
end

--- A stand-in for the music module that records what it is asked.
function M.fakeMusic()
  local m = { cues = {}, volume = nil, enabled = nil, district = nil, stops = 0, updates = 0 }
  function m.init(o) m.inited = o end
  function m.cue(c) m.cues[#m.cues + 1] = c return true end
  function m.stop() m.stops = m.stops + 1 end
  function m.setVolume(v) m.volume = v end
  function m.setEnabled(on) m.enabled = on end
  function m.setDistrict(d) m.district = d end
  function m.update() m.updates = m.updates + 1 end
  function m.last() return m.cues[#m.cues] end
  return m
end

--- One frame as the main loop runs it: plugins' update when nothing modal is up, then the top screen and the plugins' draws.
function M.frame(ctx, dt)
  dt = dt or 0.05
  if not ctx.ui.modal() then
    for _, p in ipairs(ctx.plugins) do
      if p.update then p.update(ctx, dt) end
    end
  end
  local s = ctx.ui.top()
  if s then
    s.draw(ctx, dt)
    for _, p in ipairs(ctx.plugins) do
      if p.draw then p.draw(ctx) end
    end
  end
end

-- the tests' clock: a menu key repeats only after it has been held a while, so time is ours to move
M.time = 0
function M.clock() return M.time end

--- Press a key as CC sends it: "key" (isHeld false), then repeats while held (the held key's repeats start after the
-- menu's repeat delay and come at its pace), then "key_up".
function M.press(ctx, name, repeats)
  local code = M.KEYS[name]
  local k = ctx.eui.keys
  k.clock = M.clock
  M.time = M.time + 1
  k:feed("key", code, false)
  if (repeats or 0) > 0 then M.time = M.time + require("sg.ui.keys").REPEAT_DELAY end
  for _ = 1, repeats or 0 do
    M.time = M.time + require("sg.ui.keys").REPEAT_EVERY + 0.001
    k:feed("key", code, true)
  end
  k:feed("key_up", code)
end

return M
