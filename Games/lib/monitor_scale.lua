local floor = math.floor
local max = math.max
local min = math.min

local M = {}

local DEFAULT_FONT_HEIGHT = 7
local SURFACE_BASE_WIDTH = 160
local SURFACE_BASE_HEIGHT = 96
local TEXT_SCALES = { 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5 }

local function clamp(value, minValue, maxValue)
  if minValue ~= nil and value < minValue then
    return minValue
  end
  if maxValue ~= nil and value > maxValue then
    return maxValue
  end
  return value
end

local function round(value)
  return floor(value + 0.5)
end

local function appendValue(list, value)
  list[#list + 1] = value
end

local function buildSurfaceProfile(width, height)
  local scaleX = width / SURFACE_BASE_WIDTH
  local scaleY = height / SURFACE_BASE_HEIGHT
  local scale = min(scaleX, scaleY)
  local compact = width < 128 or height < 80
  local tiny = width < 96 or height < 64
  local spacious = width > 184 and height > 110
  local edgePad = clamp(round(min(width, height) * 0.02), 1, 4)
  local smallGap = clamp(round(min(width, height) * 0.014), 1, 4)
  local sectionGap = clamp(round(min(width, height) * 0.025), 2, 6)
  local lineHeight = clamp(round(DEFAULT_FONT_HEIGHT + max(1, height / 64)), DEFAULT_FONT_HEIGHT + 1, 12)
  local buttonPadX = clamp(round(1 + (scale * 1.5)), 1, 6)
  local buttonPadY = clamp(round(scale * 0.75), 0, 3)
  local buttonHeight = max(DEFAULT_FONT_HEIGHT + 2, DEFAULT_FONT_HEIGHT + (buttonPadY * 2) + (compact and 0 or 1))
  local buttonRowGap = clamp(round(height * 0.014), 1, 4)
  local buttonColGap = clamp(round(width * 0.012), 1, 6)

  local profile = {
    kind = "surface",
    width = width,
    height = height,
    scale = scale,
    scaleX = scaleX,
    scaleY = scaleY,
    compact = compact,
    tiny = tiny,
    spacious = spacious,
    wide = width >= (height * 1.45),
    fontHeight = DEFAULT_FONT_HEIGHT,
    edgePad = edgePad,
    smallGap = smallGap,
    sectionGap = sectionGap,
    lineHeight = lineHeight,
    buttonPadX = buttonPadX,
    buttonPadY = buttonPadY,
    buttonHeight = buttonHeight,
    buttonTextY = max(0, floor((buttonHeight - DEFAULT_FONT_HEIGHT) / 2)),
    buttonRowGap = buttonRowGap,
    buttonColGap = buttonColGap,
    buttonRowSpacing = buttonHeight + buttonRowGap,
    messageLineHeight = max(lineHeight, buttonHeight + (compact and 0 or 1)),
    cardSpacing = clamp(round(2 * scale + (spacious and 1 or 0)), 1, 6),
    holdLabelOffset = clamp(round(1 + scale), 1, 4),
  }

  profile.titleY = clamp(round(height * (tiny and 0.07 or 0.10)), 1, max(1, height - 1))
  profile.subtitleY = clamp(round(height * (compact and 0.18 or 0.20)), profile.titleY + lineHeight, max(1, height - 1))
  profile.menuY = clamp(round(height * (compact and 0.30 or 0.35)), profile.subtitleY + lineHeight, max(1, height - buttonHeight - edgePad))
  profile.idleTitleY = clamp(round(height * (tiny and 0.10 or 0.15)), 1, max(1, height - 1))
  profile.idleSubtitleY = clamp(round(height * (compact and 0.22 or 0.28)), profile.idleTitleY + lineHeight, max(1, height - 1))
  profile.idleAccentY = clamp(round(height * (compact and 0.30 or 0.38)), profile.idleSubtitleY + lineHeight, max(1, height - 1))
  profile.footerButtonY = max(edgePad, height - buttonHeight - edgePad - 1)
  profile.bottomTextY = max(edgePad, height - lineHeight - edgePad)

  function profile:centerX(contentWidth, offset)
    return floor((self.width - contentWidth) / 2) + (offset or 0)
  end

  function profile:ratioY(ratio, offset, minValue, maxValue)
    return clamp(floor(self.height * ratio) + (offset or 0), minValue or 0, maxValue or (self.height - 1))
  end

  function profile:bottom(contentHeight, gap)
    return max(0, self.height - contentHeight - (gap or self.edgePad))
  end

  function profile:scaled(value, minValue, maxValue)
    return clamp(round(value * self.scale), minValue or 0, maxValue)
  end

  function profile:scaledX(value, minValue, maxValue)
    return clamp(round(value * self.scaleX), minValue or 0, maxValue)
  end

  function profile:scaledY(value, minValue, maxValue)
    return clamp(round(value * self.scaleY), minValue or 0, maxValue)
  end

  function profile:fitLineSpacing(startY, bottomY, lineCount, preferred, minSpacing)
    if lineCount <= 1 then
      return preferred or self.lineHeight
    end

    local available = max(0, bottomY - startY)
    local spacing = floor(available / (lineCount - 1))
    return clamp(spacing, minSpacing or self.fontHeight, preferred or self.lineHeight)
  end

  function profile:buttonBlockTop(anchorY, rowCount, rowSpacing)
    return anchorY - (max(0, (rowCount or 1) - 1) * (rowSpacing or self.buttonRowSpacing))
  end

  function profile:buttonWidth(textWidth, extraPad)
    return textWidth + (self.buttonPadX * 2) + (extraPad or 0)
  end

  function profile:fixedButtonWidth(textWidths, extraPad)
    local widest = 0
    for _, widthValue in ipairs(textWidths or {}) do
      widest = max(widest, self:buttonWidth(widthValue, extraPad))
    end
    if widest % 2 == 1 then
      widest = widest + 1
    end
    return widest
  end

  function profile:rowsForCount(itemCount, maxColumns)
    local rows = {}
    local columns = max(1, maxColumns or 1)
    local index = 1
    while index <= itemCount do
      local count = min(columns, itemCount - index + 1)
      appendValue(rows, count)
      index = index + count
    end
    return rows
  end

  return profile
end

function M.forSurface(width, height)
  return buildSurfaceProfile(width, height)
end

function M.forTerminal(width, height)
  local edgePad = (width >= 64 and height >= 20) and 2 or 1
  local compact = width < 52 or height < 18

  local profile = {
    kind = "terminal",
    width = width,
    height = height,
    compact = compact,
    tiny = width < 36 or height < 12,
    edgePad = edgePad,
    headerLines = compact and 2 or 3,
    footerLines = 2,
    rowGap = compact and 0 or 1,
  }

  function profile:listCapacity(headerLines, footerLines, linesPerItem)
    local header = headerLines or self.headerLines
    local footer = footerLines or self.footerLines
    local usedLines = header + footer
    local available = max(0, self.height - usedLines)
    return max(1, floor(available / max(1, linesPerItem or 1)))
  end

  return profile
end

function M.surfaceTextScale(preferredScale)
  return preferredScale or 0.5
end

function M.pickTextScale(monitor, opts)
  opts = opts or {}

  local minScale = opts.minScale or 0.5
  local maxScale = opts.maxScale or 5
  local minWidth = opts.minWidth or 1
  local minHeight = opts.minHeight or 1
  local fallback = opts.fallback or 0.5

  for _, scale in ipairs(TEXT_SCALES) do
    if scale >= minScale and scale <= maxScale then
      local ok = pcall(function()
        monitor.setTextScale(scale)
      end)
      if ok then
        local width, height = monitor.getSize()
        if width >= minWidth and height >= minHeight then
          return scale, width, height
        end
      end
    end
  end

  pcall(function()
    monitor.setTextScale(fallback)
  end)
  local width, height = monitor.getSize()
  return fallback, width, height
end

function M.pickTextScaleForLines(monitor, linesNeeded, minWidth, opts)
  opts = opts or {}
  opts.minHeight = max(linesNeeded or 1, opts.minHeight or 1)
  opts.minWidth = minWidth or opts.minWidth or 1
  return M.pickTextScale(monitor, opts)
end

M.clamp = clamp
M.round = round

return M
