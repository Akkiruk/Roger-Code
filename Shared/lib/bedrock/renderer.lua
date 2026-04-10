local theme = require("lib.bedrock.theme")

local M = {}

local Renderer = {}
Renderer.__index = Renderer

local function makeRows(width, height, fillChar, fgHex, bgHex)
  local chars = {}
  local fg = {}
  local bg = {}

  for y = 1, height do
    chars[y] = {}
    fg[y] = {}
    bg[y] = {}

    for x = 1, width do
      chars[y][x] = fillChar
      fg[y][x] = fgHex
      bg[y][x] = bgHex
    end
  end

  return chars, fg, bg
end

function Renderer:setTerm(target)
  self.term = target
  local width, height = target.getSize()
  self.width = width
  self.height = height
  self.prev_chars = {}
  self.prev_fg = {}
  self.prev_bg = {}
  self.force_full = true
  self:beginFrame(self.default_bg, self.default_fg)
end

function Renderer:beginFrame(bgColor, fgColor)
  local width, height = self.term.getSize()
  if width ~= self.width or height ~= self.height then
    self.width = width
    self.height = height
    self.prev_chars = {}
    self.prev_fg = {}
    self.prev_bg = {}
    self.force_full = true
  end

  self.default_bg = bgColor
  self.default_fg = fgColor

  self.chars, self.fg, self.bg = makeRows(
    self.width,
    self.height,
    " ",
    theme.toBlit(fgColor),
    theme.toBlit(bgColor)
  )
end

function Renderer:setCell(x, y, char, fgColor, bgColor)
  if x < 1 or y < 1 or x > self.width or y > self.height then
    return
  end

  self.chars[y][x] = char or self.chars[y][x]
  if fgColor ~= nil then
    self.fg[y][x] = theme.toBlit(fgColor)
  end
  if bgColor ~= nil then
    self.bg[y][x] = theme.toBlit(bgColor)
  end
end

function Renderer:fillRect(rect, bgColor, fgColor, char)
  local fillChar = char or " "
  local left = math.max(1, rect.x)
  local top = math.max(1, rect.y)
  local right = math.min(self.width, rect.x + rect.w - 1)
  local bottom = math.min(self.height, rect.y + rect.h - 1)

  if right < left or bottom < top then
    return
  end

  for y = top, bottom do
    for x = left, right do
      self:setCell(x, y, fillChar, fgColor, bgColor)
    end
  end
end

function Renderer:drawText(x, y, text, fgColor, bgColor)
  local source = tostring(text or "")
  if y < 1 or y > self.height then
    return
  end

  for index = 1, #source do
    local drawX = x + index - 1
    if drawX >= 1 and drawX <= self.width then
      self:setCell(drawX, y, source:sub(index, index), fgColor, bgColor)
    end
  end
end

function Renderer:render()
  for y = 1, self.height do
    local chars = table.concat(self.chars[y])
    local fg = table.concat(self.fg[y])
    local bg = table.concat(self.bg[y])

    if self.force_full or chars ~= self.prev_chars[y] or fg ~= self.prev_fg[y] or bg ~= self.prev_bg[y] then
      self.term.setCursorPos(1, y)
      self.term.blit(chars, fg, bg)
      self.prev_chars[y] = chars
      self.prev_fg[y] = fg
      self.prev_bg[y] = bg
    end
  end

  self.force_full = false
end

function M.new(target, defaultBg, defaultFg)
  local instance = setmetatable({
    term = target,
    width = 0,
    height = 0,
    default_bg = defaultBg,
    default_fg = defaultFg,
    prev_chars = {},
    prev_fg = {},
    prev_bg = {},
    force_full = true,
  }, Renderer)

  instance:setTerm(target)
  return instance
end

return M
