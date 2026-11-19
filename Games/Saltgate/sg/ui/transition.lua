-- ui/transition.lua
-- A curtain that wipes across the screen: it closes from the left (cover), calls back at the moment the screen is
-- hidden (switch scenes there), then opens again (reveal). It covers the screen with a coloured stripe edge so it reads as
-- a wipe, not a flicker. Pure state; draw() takes a term.
--
--   local tr = transition.new()
--   tr:start(function() ... end, 0.35)       cover, call fn, reveal (total about 2 x seconds)
--   tr:update(dt)   tr:draw(t, w, h)   tr:active()

local theme = require("sg.ui.theme")
local C = theme.C

local M = {}
local T = {}
T.__index = T

function M.new() return setmetatable({ phase = nil, t = 0, dur = 0.35 }, T) end

function T:start(onCovered, seconds, colour)
  if self.phase then return false end
  self.phase, self.t, self.dur, self.cb, self.colour = "cover", 0, seconds or 0.35, onCovered, colour or C.black
  return true
end

--- Only the opening half: the screen was cut to somewhere new (a respawn, a door) and the curtain draws back.
function T:reveal(seconds, colour)
  if self.phase then return false end
  self.phase, self.t, self.dur, self.cb, self.colour = "reveal", 0, seconds or 0.3, nil, colour or C.black
  return true
end

function T:active() return self.phase ~= nil end

function T:update(dt)
  if not self.phase then return end
  self.t = self.t + dt
  if self.t >= self.dur then
    if self.phase == "cover" then
      self.phase, self.t = "reveal", 0
      if self.cb then local cb = self.cb self.cb = nil cb() end
    else
      self.phase = nil
    end
  end
end

--- How far the curtain is across (0..1): closing 0 to 1, opening 1 to 0.
function T:amount()
  if not self.phase then return 0 end
  local f = math.min(1, self.t / self.dur)
  return self.phase == "cover" and f or 1 - f
end

function T:draw(t, w, h)
  if not self.phase then return end
  local f = self:amount()
  local cols = math.floor(f * w + 0.5)
  if cols <= 0 then return end
  local row = string.rep(" ", cols)
  t.setBackgroundColour(self.colour)
  -- covering sweeps in from the left; revealing leaves from the left too (the right edge is the moving one both ways)
  for y = 1, h do
    t.setCursorPos(1, y)
    t.write(row)
  end
  if cols < w then
    t.setBackgroundColour(C.orange)
    t.setCursorPos(cols + 1, 1)
    for y = 1, h do
      t.setCursorPos(cols + 1, y)
      t.write(" ")
    end
  end
end

return M
