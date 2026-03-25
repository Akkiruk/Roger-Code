-- ui.lua
-- Shared UI primitives for surface-based casino games on ComputerCraft monitors.
-- Provides button management, centered text, message overlays, and betting interfaces.
-- Usage:
--   local ui = require("lib.ui")
--   ui.init(surfaceAPI, screen, font)
--   ui.button(screen, "HIT", colors.lightBlue, x, y, callback, true)
--   ui.waitForButton(0, 0)

local _surface = nil
local _font    = nil
local _metrics = nil
local buttons  = {}
local currency = require("lib.currency")
local monitorScale = require("lib.monitor_scale")
local max = math.max

local m_round = function(x) return x + 0.5 - (x + 0.5) % 1 end

local function isAuthorizedMonitorTouch()
  local sessionPlayer = currency.getAuthenticatedPlayerName and currency.getAuthenticatedPlayerName() or nil
  if not sessionPlayer or sessionPlayer == "" then
    return true
  end

  local currentPlayer = nil
  if currency.getLivePlayerName then
    currentPlayer = currency.getLivePlayerName()
  end
  if (not currentPlayer or currentPlayer == "") and currency.getSessionInfo then
    local info = currency.getSessionInfo()
    currentPlayer = info and info.playerName or nil
  end

  return (not currentPlayer) or currentPlayer == sessionPlayer
end

--- Initialize the UI module with the surface API and font.
-- @param surfaceAPI table  The loaded surface library
-- @param font       table  Loaded font from surface.loadFont
local function init(surfaceAPI, font, metrics)
  assert(surfaceAPI, "surfaceAPI is required")
  assert(font, "font is required")
  _surface = surfaceAPI
  _font    = font
  _metrics = metrics or monitorScale.forSurface(160, 96)
end

--- Clear all registered buttons (call at the start of each screen redraw).
local function clearButtons()
  buttons = {}
end

--- Get the current buttons table (for custom iteration).
-- @return table
local function getButtons()
  return buttons
end

--- Create a button surface with text on a colored background.
-- @param text string
-- @param bg   number  ComputerCraft color
-- @return surface, number width, number height
local function getButtonSurface(text, bg)
  assert(_surface, "Call ui.init() first")
  local textSize = _surface.getTextSize(text, _font)
  local btnWidth = textSize + (_metrics.buttonPadX * 2)
  local btn = _surface.create(btnWidth, _metrics.buttonHeight)
  btn:fillRect(0, 0, btnWidth, _metrics.buttonHeight, bg)
  local fg = colors.black
  if bg == colors.black or bg == colors.gray then
    fg = colors.white
  end
  btn:drawText(text, _font, _metrics.buttonPadX, _metrics.buttonTextY, fg)
  return btn
end

--- Create a fixed-width button surface.
-- @param text       string
-- @param bg         number
-- @param fixedWidth number
-- @return surface
local function getFixedWidthButtonSurface(text, bg, fixedWidth)
  assert(_surface, "Call ui.init() first")
  local textSize = _surface.getTextSize(text, _font)
  local minWidth = textSize + (_metrics.buttonPadX * 2)
  local btnWidth = max(fixedWidth or minWidth, minWidth)
  local btn = _surface.create(btnWidth, _metrics.buttonHeight)
  btn:fillRect(0, 0, btnWidth, _metrics.buttonHeight, bg)
  local textX = math.floor((btnWidth - textSize) / 2)
  local fg = colors.black
  if bg == colors.black or bg == colors.gray then
    fg = colors.white
  end
  btn:drawText(text, _font, textX, _metrics.buttonTextY, fg)
  return btn
end

--- Draw a button on a surface and register it for click detection.
-- @param surfaceObj  surface  The screen to draw on
-- @param text        string   Button label (also used as key in buttons table)
-- @param bg          number   Background color
-- @param x           number   X position
-- @param y           number   Y position
-- @param func        function Callback when clicked
-- @param center      boolean? If true, center the button horizontally on x
-- @return surface  The button surface
local function button(surfaceObj, text, bg, x, y, func, center)
  local btnSurf = getButtonSurface(text, bg)
  if center then
    x = math.floor(x - btnSurf.width / 2)
  end
  surfaceObj:drawSurface(btnSurf, x, y)
  buttons[text] = {
    x = x, y = y,
    width = btnSurf.width, height = btnSurf.height,
    cb = func,
  }
  return btnSurf
end

--- Draw a fixed-width button on a surface and register it.
-- @param surfaceObj  surface
-- @param text        string
-- @param bg          number
-- @param x           number
-- @param y           number
-- @param func        function
-- @param center      boolean?
-- @param fixedWidth  number?
-- @return surface
local function fixedWidthButton(surfaceObj, text, bg, x, y, func, center, fixedWidth)
  local btnSurf = getFixedWidthButtonSurface(text, bg, fixedWidth)
  if center then
    x = math.floor(x - btnSurf.width / 2)
  end
  surfaceObj:drawSurface(btnSurf, x, y)
  buttons[text] = {
    x = x, y = y,
    width = btnSurf.width, height = btnSurf.height,
    cb = func,
  }
  return btnSurf
end

--- Layout rows of buttons in a centered horizontal grid.
-- Automatically wraps a row into multiple sub-rows if it exceeds screen width.
-- @param screen     surface
-- @param buttonRows table  Array of rows; each row is an array of {text, color, func}
-- @param centerX    number
-- @param startY     number
-- @param rowSpacing number
-- @param colSpacing number
local function layoutButtonGrid(screen, buttonRows, centerX, startY, rowSpacing, colSpacing)
  rowSpacing = rowSpacing or _metrics.buttonRowSpacing
  colSpacing = colSpacing or _metrics.buttonColGap
  local screenW = screen.width or (centerX * 2)
  local actualRow = 0
  for _, row in ipairs(buttonRows) do
    -- Pre-render all button surfaces for this row
    local btnSurfs = {}
    for j, btn in ipairs(row) do
      local bs
      if btn.width then
        bs = getFixedWidthButtonSurface(btn.text, btn.color, btn.width)
      else
        bs = getButtonSurface(btn.text, btn.color)
      end
      btnSurfs[j] = { surf = bs, btn = btn }
    end

    -- Split into sub-rows that fit within screen width
    local subRows = {}
    local current = {}
    local currentWidth = 0
    for _, bs in ipairs(btnSurfs) do
      local addedWidth = bs.surf.width
      if #current > 0 then addedWidth = addedWidth + colSpacing end
      if #current > 0 and (currentWidth + addedWidth) > screenW then
        table.insert(subRows, current)
        current = { bs }
        currentWidth = bs.surf.width
      else
        table.insert(current, bs)
        currentWidth = currentWidth + addedWidth
      end
    end
    if #current > 0 then table.insert(subRows, current) end

    -- Draw each sub-row centered
    for _, subRow in ipairs(subRows) do
      local totalWidth = 0
      for j, bs in ipairs(subRow) do
        totalWidth = totalWidth + bs.surf.width
        if j > 1 then totalWidth = totalWidth + colSpacing end
      end
      local x = centerX - math.floor(totalWidth / 2)
      local y = startY + actualRow * rowSpacing
      for _, bs in ipairs(subRow) do
        screen:drawSurface(bs.surf, x, y)
        buttons[bs.btn.text] = {
          x = x, y = y,
          width = bs.surf.width, height = bs.surf.height,
          cb = bs.btn.func,
        }
        x = x + bs.surf.width + colSpacing
      end
      actualRow = actualRow + 1
    end
  end
end

--- Draw a column of buttons centered at (startX, startY).
-- @param screen   surface
-- @param btnList  table   Array of {text, color, func}
-- @param startX   number
-- @param startY   number
-- @param spacing  number  Vertical spacing between buttons
local function drawButtonsColumn(screen, btnList, startX, startY, spacing)
  spacing = spacing or _metrics.buttonRowSpacing
  for i, b in ipairs(btnList) do
    button(screen, b.text, b.color, startX, startY + (i - 1) * spacing, b.func, true)
  end
end

--- Block until a registered button is pressed via monitor_touch.
-- @param ox number  X offset (usually 0)
-- @param oy number  Y offset (usually 0)
local function waitForButton(ox, oy)
  while true do
    local event, side, px, py = os.pullEvent("monitor_touch")
    if not isAuthorizedMonitorTouch() then
      os.sleep(0)
    else
      px = px - (ox or 0)
      py = py - (oy or 0)
      for _, b in pairs(buttons) do
        if px >= b.x and px <= b.x + b.width - 1
           and py >= b.y and py <= b.y + b.height - 1 then
          buttons = {}
          b.cb()
          return
        end
      end
    end
  end
end

--- Wait for a monitor touch that passes the active session guard.
-- @return string side, number x, number y
local function waitForMonitorTouch()
  while true do
    local event, side, px, py = os.pullEvent("monitor_touch")
    if isAuthorizedMonitorTouch() then
      return side, px, py
    end
    os.sleep(0)
  end
end

--- Check if a touch coordinate hit any button. Non-blocking.
-- @param px number  Touch X (already offset-corrected)
-- @param py number  Touch Y
-- @return function|nil  The callback if a button was hit, or nil
local function checkButtonHit(px, py)
  for _, b in pairs(buttons) do
    if px >= b.x and px <= b.x + b.width - 1
       and py >= b.y and py <= b.y + b.height - 1 then
      local cb = b.cb
      buttons = {}
      return cb
    end
  end
  return nil
end

--- Display a centered message on screen, one word per line, uppercase.
-- @param screen   surface
-- @param msg      string
-- @param msgColor number
-- @param pause    number?  Duration in seconds (default 1)
local function displayCenteredMessage(screen, msg, msgColor, pause)
  assert(_surface, "Call ui.init() first")
  pause = pause or 1
  local words = {}
  msg = msg:upper()
  for word in msg:gmatch("%S+") do
    table.insert(words, word)
  end
  local lineHeight = _metrics.messageLineHeight
  local blockHeight = #words * lineHeight
  local startY = math.floor((screen.height - blockHeight) / 2)
  screen:clear(colors.green)
  for i, word in ipairs(words) do
    local textWidth = _surface.getTextSize(word, _font)
    local centerX = math.floor((screen.width - textWidth) / 2)
    local y = startY + (i - 1) * lineHeight
    screen:drawText(word, _font, centerX, y, msgColor)
  end
  screen:output()
  os.sleep(pause)
end

--- Get the loaded font object.
-- @return table  The font table from surface.loadFont
local function getFont()
  return _font
end

--- Get the surface.getTextSize helper (delegates to surface API).
-- @param text string
-- @return number
local function getTextSize(text)
  assert(_surface, "Call ui.init() first")
  return _surface.getTextSize(text, _font)
end

local function getMetrics()
  return _metrics
end

--- Helper for math.round since Lua 5.1 lacks it natively.
-- @param x number
-- @return number
local function round(x)
  return m_round(x)
end

-----------------------------------------------------
-- Term-based UI helpers (for statistics / non-surface screens)
-----------------------------------------------------

--- Truncate text to fit within maxWidth, appending a suffix if truncated.
-- @param text     string
-- @param maxWidth number
-- @param suffix   string?  (default "..")
-- @return string
local function truncateText(text, maxWidth, suffix)
  if not text then return "" end
  if #text <= maxWidth then return text end
  suffix = suffix or ".."
  if maxWidth <= #suffix then return text:sub(1, maxWidth) end
  return text:sub(1, maxWidth - #suffix) .. suffix
end

--- Write text at position using blit to preserve background color.
-- Automatically truncates text that would go past the right screen edge.
-- @param x         number
-- @param y         number
-- @param text      string
-- @param textColor number
-- @param bgColor   number?  If nil, preserves current background
local function blitWrite(x, y, text, textColor, bgColor)
  local oldBg   = term.getBackgroundColor()
  local oldText  = term.getTextColor()
  local useBg = bgColor or oldBg
  -- Auto-truncate to screen bounds
  local w = term.getSize()
  local maxLen = w - x + 1
  if maxLen <= 0 then return end
  if #text > maxLen then
    text = truncateText(text, maxLen)
  end
  term.setCursorPos(x, y)
  term.blit(
    text,
    string.rep(colors.toBlit(textColor or oldText), #text),
    string.rep(colors.toBlit(useBg), #text)
  )
  term.setTextColor(oldText)
  term.setBackgroundColor(oldBg)
end

--- Draw centered text on the terminal.
-- Automatically truncates to screen width if text is too long.
-- @param text      string
-- @param yPos      number
-- @param textColor number
-- @return table  {x, y, text}
local function drawCenteredText(text, yPos, textColor)
  local w = term.getSize()
  if #text > w then
    text = truncateText(text, w)
  end
  local xPos = math.floor((w - #text) / 2) + 1
  blitWrite(xPos, yPos, text, textColor)
  return { x = xPos, y = yPos, text = text }
end

--- Draw a filled rectangle on the terminal.
-- @param x1      number
-- @param y1      number
-- @param x2      number
-- @param y2      number
-- @param bgColor number
-- @return table  {x1, y1, x2, y2}
local function drawBox(x1, y1, x2, y2, bgColor)
  local oldBg = term.getBackgroundColor()
  term.setBackgroundColor(bgColor or colors.black)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
  term.setBackgroundColor(oldBg)
  return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

--- Draw a term-based button with optional highlight.
-- @param x         number
-- @param y         number
-- @param width     number
-- @param text      string
-- @param isSelected boolean?
-- @return table  {x1, y1, x2, y2}
local function drawTermButton(x, y, width, text, isSelected)
  local buttonColor = isSelected and colors.lime or colors.blue
  local box = drawBox(x, y, x + width, y, buttonColor)
  local textX = x + math.floor((width - #text) / 2)
  blitWrite(textX, y, text, colors.white, buttonColor)
  return box
end

--- Wrap text to a max width, returning an array of lines.
-- @param text     string
-- @param maxWidth number
-- @return table  Array of strings
local function wrapText(text, maxWidth)
  if not text then return { "<no text>" } end
  if not maxWidth or maxWidth < 1 then return { "" } end
  if #text <= maxWidth then return { text } end

  local words = {}
  for word in text:gmatch("%S+") do
    -- Split extra-long words so no produced line can exceed maxWidth.
    if #word > maxWidth then
      local i = 1
      while i <= #word do
        table.insert(words, word:sub(i, i + maxWidth - 1))
        i = i + maxWidth
      end
    else
      table.insert(words, word)
    end
  end

  local lines = {}
  local currentLine = ""
  for _, word in ipairs(words) do
    if #currentLine == 0 then
      currentLine = word
    elseif #currentLine + 1 + #word <= maxWidth then
      currentLine = currentLine .. " " .. word
    else
      table.insert(lines, currentLine)
      currentLine = word
    end
  end
  if #currentLine > 0 then
    table.insert(lines, currentLine)
  end
  return lines
end

--- Write text at position, auto-truncating to a specified max width.
-- Convenience wrapper for bounded text output on term screens.
-- @param x         number
-- @param y         number
-- @param text      string
-- @param maxWidth  number   Maximum chars to render (truncates with "..")
-- @param textColor number
-- @param bgColor   number?  If nil, preserves current background
local function safeWrite(x, y, text, maxWidth, textColor, bgColor)
  if not text then return end
  if not maxWidth or maxWidth < 1 then return end
  text = truncateText(text, maxWidth)
  blitWrite(x, y, text, textColor, bgColor)
end

--- Draw multiple lines of word-wrapped text on the terminal.
-- Returns the number of lines actually drawn.
-- @param x         number   Left X position
-- @param y         number   Starting Y position
-- @param text      string   Text to wrap and render
-- @param maxWidth  number   Max chars per line
-- @param maxLines  number?  Max lines to draw (default: unlimited)
-- @param textColor number
-- @param bgColor   number?  If nil, preserves current background
-- @return number  Number of lines drawn
local function drawWrappedText(x, y, text, maxWidth, maxLines, textColor, bgColor)
  local lines = wrapText(text, maxWidth)
  local drawn = 0
  for i, line in ipairs(lines) do
    if maxLines and i > maxLines then break end
    blitWrite(x, y + i - 1, line, textColor, bgColor)
    drawn = drawn + 1
  end
  return drawn
end

--- Draw text on a surface, auto-clipping to screen width.
-- Drop-in safe replacement for screen:drawText() — prevents text from
-- rendering past the right edge of the surface.
-- @param screen surface  The screen surface
-- @param text   string   Text to draw
-- @param font   table    Font object
-- @param x      number   X position
-- @param y      number   Y position
-- @param color  number   Text color
local function safeDrawText(screen, text, font, x, y, color)
  assert(_surface, "Call ui.init() first")
  if not text or not screen then return end
  if y < 0 or y >= screen.height then return end
  if x >= screen.width then return end

  -- Clamp left overflow to the visible area.
  if x < 0 then
    x = 0
  end

  local textWidth = _surface.getTextSize(text, font)
  local available = screen.width - x
  if textWidth > available and available > 0 then
    -- Binary search for max chars that fit
    local lo, hi = 1, #text
    while lo < hi do
      local mid = math.ceil((lo + hi) / 2)
      if _surface.getTextSize(text:sub(1, mid), font) <= available then
        lo = mid
      else
        hi = mid - 1
      end
    end
    -- Try to fit with ellipsis
    local dotW = _surface.getTextSize("..", font)
    if lo > 2 and _surface.getTextSize(text:sub(1, lo - 2) .. "..", font) <= available then
      text = text:sub(1, lo - 2) .. ".."
    else
      text = text:sub(1, lo)
    end
  end
  screen:drawText(text, font, x, y, color)
end

--- Draw a player name overlay in the top-right corner of a monitor.
-- Uses term API directly so it works on any redirected monitor.
-- @param monitor  table   The monitor peripheral (used for term.redirect)
-- @param playerName string The player name to display
local function drawPlayerOverlay(monitor, playerName)
  if not monitor or not playerName then return end
  local oldTerm = term.current()
  term.redirect(monitor)
  local w = term.getSize()
  local text = "Player: " .. playerName
  if #text > w - 2 then
    text = truncateText(text, w - 2)
  end
  term.setCursorPos(w - #text - 1, 1)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.yellow)
  term.write(text)
  term.redirect(oldTerm)
end

return {
  -- Setup
  init             = init,

  -- Surface buttons
  clearButtons         = clearButtons,
  getButtons           = getButtons,
  getButtonSurface     = getButtonSurface,
  button               = button,
  fixedWidthButton     = fixedWidthButton,
  layoutButtonGrid     = layoutButtonGrid,
  drawButtonsColumn    = drawButtonsColumn,
  waitForButton        = waitForButton,
  waitForMonitorTouch  = waitForMonitorTouch,
  checkButtonHit       = checkButtonHit,

  -- Surface text
  displayCenteredMessage = displayCenteredMessage,
  getTextSize            = getTextSize,
  getFont                = getFont,
  getMetrics             = getMetrics,
  round                  = round,

  -- Term-based helpers
  truncateText       = truncateText,
  blitWrite          = blitWrite,
  safeWrite          = safeWrite,
  drawCenteredText   = drawCenteredText,
  drawWrappedText    = drawWrappedText,
  drawBox            = drawBox,
  drawTermButton     = drawTermButton,
  drawPlayerOverlay  = drawPlayerOverlay,
  wrapText           = wrapText,

  -- Surface-based safe text
  safeDrawText       = safeDrawText,
}
