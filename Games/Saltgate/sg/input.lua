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

--- Feed one event (the values os.pullEvent returns). t is the time now in seconds.
function I:event(t, name, code, isHeld)
  self.now = t
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

--- Was an action's key pressed since the last frame?
function I:pressedAction(action)
  for _, code in ipairs(self.map[action] or {}) do
    if self.pressed[code] then return true end
  end
  return false
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
end

return M
