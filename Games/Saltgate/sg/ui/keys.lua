-- ui/keys.lua
-- Keys for the menus. The v2 main loop only reads keys for play, pause and the map, so a screen added by a plugin
-- never hears them: this listens beside it. attach() wraps os.pullEventRaw once; every key event the main loop pulls is
-- copied to the listeners and passed on untouched.
--
-- How CC sends keys: "key" (code, isHeld=false) when a key goes down, "key" with isHeld=true while it auto-repeats,
-- "key_up" when it is let go. A menu wants every one of those: a tap moves one row, holding scrolls. actions() gives
-- what came in since the last flush(), in order (the last plugin of a frame flushes):
--   "up" "down" "left" "right" "select" "back" "tab" or a raw key name for anything else
--
-- One key per action in every menu: W/S or the arrows move, A/D or the arrows change a value, ENTER selects,
-- BACKSPACE goes back.

local M = {}
local K = {}
K.__index = K

M.MAX = 24
-- a held key repeats in a menu only after this long, then at most this often: a tap is one move however the computer's
-- terminal sends its repeats (some send them from the first moment), and holding scrolls at a steady pace
M.REPEAT_DELAY = 0.4
M.REPEAT_EVERY = 0.08
M.SAME_PRESS = 0.04

local function defaultClock()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") / 1000 end
  return os.clock()
end

--- keys: the CC keys table (or a stand-in with the same names).
function M.new(keysTable, clock)
  local k = keysTable or {}
  local self = setmetatable({ keys = k, queue = {}, down = {}, byCode = {}, since = {}, last = {}, clock = clock or defaultClock }, K)
  local function map(action, ...)
    for _, name in ipairs({ ... }) do
      if k[name] then self.byCode[k[name]] = action end
    end
  end
  map("up", "w", "up")
  map("down", "s", "down")
  map("left", "a", "left")
  map("right", "d", "right")
  map("select", "enter", "numPadEnter")
  map("back", "backspace")
  map("tab", "tab")
  map("pause", "p")
  map("map", "m")
  map("use", "e")
  map("radio", "r")
  map("abandon", "x")
  map("camera", "c")
  return self
end

--- One event, as os.pullEventRaw returns it.
function K:feed(name, code, isHeld)
  if name == "key" and code then
    self.down[code] = true
    local now = self.clock()
    -- a press of a key that is still down (no key_up between) a moment after the first is the same press seen twice
    if not isHeld and self.since[code] and now - self.since[code] < M.SAME_PRESS then return end
    if not isHeld or not self.since[code] then
      self.since[code] = now
      self.last[code] = now
      isHeld = false
    elseif now - self.since[code] < M.REPEAT_DELAY or now - self.last[code] < M.REPEAT_EVERY then
      return
    else
      self.last[code] = now
    end
    local action = self.byCode[code]
    if action then
      if #self.queue >= M.MAX then table.remove(self.queue, 1) end
      self.queue[#self.queue + 1] = { action = action, held = isHeld and true or false, code = code }
    end
  elseif name == "key_up" and code then
    self.down[code] = nil
    self.since[code], self.last[code] = nil, nil
  end
end

--- The actions since the last flush, oldest first, repeats of a held key included. Does not forget them: every
-- plugin and screen in a frame sees the same list, and the frame's last plugin flushes it.
function K:actions()
  local out = {}
  for i, e in ipairs(self.queue) do out[i] = e.action end
  return out
end

--- Only the first press of each action (a held key's repeats dropped): for things that must not repeat.
function K:fresh()
  local out = {}
  for _, e in ipairs(self.queue) do
    if not e.held then out[#out + 1] = e.action end
  end
  return out
end

--- Did this action's key go down this frame?
function K:pressed(action)
  for _, e in ipairs(self.queue) do
    if e.action == action and not e.held then return true end
  end
  return false
end

--- The frame is over: forget what came in.
function K:flush()
  self.queue = {}
end

function K:clear()
  self.queue = {}
end

--- The name a hint shows for an action ("ENTER", "BACKSPACE", "R").
function K:label(action)
  local names = { select = "ENTER", back = "BACKSPACE", tab = "TAB", pause = "P", map = "M", use = "E", radio = "R",
    abandon = "X", camera = "C", up = "W", down = "S", left = "A", right = "D" }
  return names[action] or action:upper()
end

-- ---------------------------------------------------------------- the tee

local listeners = {}
local installed = false
M.original = nil

local function pack(...) return { n = select("#", ...), ... } end

--- Start copying key events to a listener (a keys object). Wraps os.pullEventRaw once for the whole computer: when the
-- game starts again in the same session (startup.lua restarts it after a crash) the wrapper from the last run is
-- reused and pointed at this run's listeners, so wrappers never pile up.
function M.attach(listener)
  for _, l in ipairs(listeners) do
    if l == listener then return end
  end
  listeners[#listeners + 1] = listener
  if installed then return end
  local os_ = rawget(_G, "os")
  if not os_ or not os_.pullEventRaw then return end
  installed = true
  local tee = os_.saltgate_keys_tee
  if tee then
    tee.listeners = listeners
    M.original = tee.raw
    return
  end
  tee = { listeners = listeners, raw = os_.pullEventRaw }
  os_.saltgate_keys_tee = tee
  M.original = tee.raw
  os_.pullEventRaw = function(...)
    local ev = pack(tee.raw(...))
    local name = ev[1]
    if name == "key" or name == "key_up" then
      for _, l in ipairs(tee.listeners) do l:feed(name, ev[2], ev[3]) end
    end
    return unpack(ev, 1, ev.n)
  end
end

--- How many listeners are attached (a test checks it stays one).
function M.count() return #listeners end

function M.detach(listener)
  for i, l in ipairs(listeners) do
    if l == listener then table.remove(listeners, i) return end
  end
end

return M
