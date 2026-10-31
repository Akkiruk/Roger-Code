-- canvas.lua
-- The casino's screen: a buffer of cells drawn to a monitor at text scale 0.5. A 6x6 wall is about 121x81 cells.
-- Coordinates are 1-based, the same as monitor_touch, so a drawn button and a touch can never disagree.
-- flush() writes only the rows that changed.

local font = require("lib.casino.font")

local M = {}
local Canvas = {}
Canvas.__index = Canvas

local rep, floor = string.rep, math.floor

--- Wrap a target with getSize, setCursorPos, blit. Pass nil for a screenless canvas of w x h (tests).
function M.new(target, w, h)
  if target then w, h = target.getSize() end
  local self = setmetatable({ target = target, w = w, h = h, ch = {}, fg = {}, bg = {}, shown = {} }, Canvas)
  for y = 1, h do
    self.ch[y], self.fg[y], self.bg[y] = {}, {}, {}
  end
  self:clear("f")
  return self
end

--- Point this canvas at a monitor again, after a resize. A scene keeps the canvas it started with, and a real monitor says it has
-- resized a tick after setTextScale, so by then one is up: this has to stay the same object, or the scene draws where nothing looks.
function Canvas:attach(target)
  self.target = target
  local w, h = target.getSize()
  if w ~= self.w or h ~= self.h then
    self.w, self.h = w, h
    for y = 1, h do
      self.ch[y], self.fg[y], self.bg[y] = {}, {}, {}
    end
    self:clear("f")
  end
  self:invalidate()
end

function Canvas:clear(bg)
  for y = 1, self.h do
    local c, f, b = self.ch[y], self.fg[y], self.bg[y]
    for x = 1, self.w do
      c[x], f[x], b[x] = " ", "0", bg
    end
  end
end

--- Filled rectangle. Anything outside the screen is cut off.
function Canvas:rect(x, y, w, h, bg)
  local x2, y2 = math.min(self.w, x + w - 1), math.min(self.h, y + h - 1)
  for j = math.max(1, y), y2 do
    local c, b = self.ch[j], self.bg[j]
    for i = math.max(1, x), x2 do
      c[i], b[i] = " ", bg
    end
  end
end

--- One-cell outline.
function Canvas:frame(x, y, w, h, bg)
  self:rect(x, y, w, 1, bg)
  self:rect(x, y + h - 1, w, 1, bg)
  self:rect(x, y, 1, h, bg)
  self:rect(x + w - 1, y, 1, h, bg)
end

--- A filled panel with its corners knocked out, so it reads as rounded.
function Canvas:panel(x, y, w, h, bg, cornerBg)
  self:rect(x, y, w, h, bg)
  if cornerBg then
    self:rect(x, y, 1, 1, cornerBg)
    self:rect(x + w - 1, y, 1, 1, cornerBg)
    self:rect(x, y + h - 1, 1, 1, cornerBg)
    self:rect(x + w - 1, y + h - 1, 1, 1, cornerBg)
  end
end

--- Small text: the monitor's own font, one character per cell. bg nil keeps what is underneath.
function Canvas:text(x, y, str, fg, bg)
  if y < 1 or y > self.h then return end
  str = tostring(str)
  local c, f, b = self.ch[y], self.fg[y], self.bg[y]
  for i = 1, #str do
    local px = x + i - 1
    if px >= 1 and px <= self.w then
      c[px], f[px] = str:sub(i, i), fg
      if bg then b[px] = bg end
    end
  end
end

function Canvas:textCenter(cx, y, str, fg, bg)
  str = tostring(str)
  self:text(cx - floor(#str / 2), y, str, fg, bg)
end

--- Width in cells of big text at a scale.
function Canvas:bigWidth(str, scale)
  return font.width(str) * (scale or 1)
end

--- Big text: the pixel font drawn in background cells. Only the letters are painted.
function Canvas:big(x, y, str, color, scale)
  scale = scale or 1
  str = tostring(str)
  for i = 1, #str do
    local glyph = font.glyph(str:sub(i, i))
    for row = 1, font.HEIGHT do
      local bits = glyph.rows[row]
      for col = 1, glyph.width do
        if bits:sub(col, col) == "#" then
          self:rect(x + (col - 1) * scale, y + (row - 1) * scale, scale, scale, color)
        end
      end
    end
    x = x + (glyph.width + 1) * scale
  end
end

function Canvas:bigCenter(cx, y, str, color, scale)
  self:big(cx - floor(self:bigWidth(str, scale) / 2), y, str, color, scale)
end

--- Rows of characters, one per cell, painted through a colour map. Characters missing from the map stay see-through.
function Canvas:sprite(x, y, rows, map)
  for j = 1, #rows do
    local row = rows[j]
    for i = 1, #row do
      local color = map[row:sub(i, i)]
      if color then self:rect(x + i - 1, y + j - 1, 1, 1, color) end
    end
  end
end

--- Send the rows that changed to the monitor.
function Canvas:flush()
  if not self.target then return end
  local shown, target = self.shown, self.target
  for y = 1, self.h do
    local c, f, b = table.concat(self.ch[y]), table.concat(self.fg[y]), table.concat(self.bg[y])
    local key = c .. f .. b
    if shown[y] ~= key then
      shown[y] = key
      target.setCursorPos(1, y)
      target.blit(c, f, b)
    end
  end
end

--- Forget what the monitor shows, so the next flush redraws everything.
function Canvas:invalidate()
  self.shown = {}
end

--- A debugging aid: one row of the buffer as background colours.
function Canvas:rowColors(y)
  return table.concat(self.bg[y])
end

M.blank = function(n) return rep(" ", n) end

return M
