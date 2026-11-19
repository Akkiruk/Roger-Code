-- input.lua
-- Turns CC key events into what the game wants each frame. Pure: the key codes come in as a table, so it is tested
-- without a computer.
--
-- How CC sends keys: "key" (code, isHeld) when a key goes down, then again with isHeld = true while it auto-repeats,
-- and "key_up" (code) when it is let go. So:
--   * a key counts as held from its "key" to its "key_up"; repeats change nothing (no extra presses)
--   * a key pressed and let go between two frames still counts for that one frame, so a quick tap of W or A is felt
--   * a one-shot action (get in, map, pause) fires once per press, however long it is held
--   * nothing sticks: if no "key_up" ever comes (the computer screen was closed mid-press), a key not seen for
--     STALE seconds is let go. Auto-repeat refreshes held keys long before that.

local M = {}
local I = {}
I.__index = I

M.STALE = 4

--- keys: the CC keys table (or a stand-in with the same names).
function M.new(keys)
  local k = keys
  local self = setmetatable({ keys = k, held = {}, seen = {}, pressed = {}, tapped = {}, now = 0 }, I)
  -- one action, one key (the arrows are the same as WASD; F is an old alias for E and never shown)
  self.map = {
    forward = { k.w, k.up },
    back = { k.s, k.down },
    left = { k.a, k.left },
    right = { k.d, k.right },
    handbrake = { k.space },
    run = { k.leftShift, k.rightShift },
    use = { k.e, k.f },
    horn = { k.h },
    advance = { k.enter, k.numPadEnter },
    map = { k.m },
    pause = { k.p, k.tab },
    camera = { k.c },
    skip = { k.x },
    quit = { k.q },
    up = { k.w, k.up },
    down = { k.s, k.down },
    perf = { k.f3 },
  }
  return self
end

--- Add (or change) an action and its keys, for parts of the game that bring their own (a plugin's fire, aim, radio).
-- codes: a list of key codes. Read it with down(action) and pressedAction(action).
function I:bind(action, codes)
  if type(action) ~= "string" or type(codes) ~= "table" then error("bind needs an action name and a list of keys", 2) end
  self.map[action] = codes
end

--- Feed one event (the values os.pullEvent returns). t is the time now in seconds.
-- A mouse click on the computer's screen ("mouse_click", button, x, y) is Enter wherever Enter advances or confirms
-- (pressedAction("advance") sees it), unless a screen with options takes it first (takeClick: a click on an option
-- picks it; a click beside them does nothing).
function I:event(t, name, code, isHeld, y)
  self.now = t
  if name == "mouse_click" and isHeld and y then
    self.click = { button = code, x = isHeld, y = y }
    return
  end
  if name == "key" and code then
    if not isHeld or not self.held[code] then
      if not self.held[code] then self.pressed[code] = true end
    end
    self.held[code] = true
    self.seen[code] = t
  elseif name == "key_up" and code then
    if self.held[code] then self.tapped[code] = true end -- it counted for this frame even if let go already
    self.held[code] = nil
    self.seen[code] = nil
  end
end

--- Is any key of an action down (or tapped since the last frame)?
function I:down(action)
  for _, code in ipairs(self.map[action] or {}) do
    if self.held[code] or self.tapped[code] or self.pressed[code] then return true end
  end
  return false
end

--- Was an action's key pressed since the last frame? (A click this frame that no screen took is an "advance".)
-- SPACE is the handbrake in play and ENTER on the screens that stop play (talk, cutscenes, MISSION FAILED, the
-- phone, the map): "advance" is only read there. A screen that opens while SPACE is in use (a talk while you brake)
-- ignores SPACE for SPACE_GUARD seconds, so a handbrake press never skips its first line.
function I:pressedAction(action)
  for _, code in ipairs(self.map[action] or {}) do
    if self.pressed[code] then return true end
  end
  if action == "advance" then
    if self.click and not self.click.taken then return true end
    local space = self.keys and self.keys.space
    if space and self.pressed[space] and self.now >= (self.spaceGuard or 0) then return true end
  end
  return false
end

M.SPACE_GUARD = 0.35

--- A screen that stops play has just opened: SPACE (the handbrake) does not count as ENTER for a moment.
function I:guardSpace(t)
  self.spaceGuard = (t or self.now) + M.SPACE_GUARD
end

--- The click this frame not yet taken: x, y, button (nil when there is none).
function I:clicked()
  local c = self.click
  if c and not c.taken then return c.x, c.y, c.button end
  return nil
end

--- A screen with options has dealt with the click (picked an option, or ignored a click beside them): it is no
-- longer an "advance".
function I:takeClick()
  if self.click then self.click.taken = true end
end

--- What the game gets this frame.
function I:read()
  local throttle = (self:down("forward") and 1 or 0) - (self:down("back") and 1 or 0)
  local steer = (self:down("right") and 1 or 0) - (self:down("left") and 1 or 0)
  return {
    throttle = throttle,
    steer = steer,
    handbrake = self:down("handbrake"),
    sprint = self:down("run"),
    enter = self:pressedAction("use"),
    horn = self:pressedAction("horn"),
    advance = self:pressedAction("advance"),
    skip = self:pressedAction("skip"),
  }
end

--- The frame is over: forget presses and taps, let go of keys that went quiet.
function I:endFrame(t)
  self.pressed = {}
  self.tapped = {}
  self.click = nil
  t = t or self.now
  for code, at in pairs(self.seen) do
    if t - at > M.STALE then
      self.held[code] = nil
      self.seen[code] = nil
    end
  end
end

--- Let go of everything (a screen change).
function I:clear()
  self.held, self.seen, self.pressed, self.tapped = {}, {}, {}, {}
  self.click = nil
end

return M
