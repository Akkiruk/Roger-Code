local monitorScale = require("lib.monitor_scale")
local text = require("lib.ui_text")
local touch = require("lib.ui_touch")

local M = {}

local _surface = nil
local _font = nil
local _metrics = nil
local buttons = {}
local buttonSurfaceCache = {}
local fixedButtonSurfaceCache = {}

local max = math.max
local min = math.min

local function round(x)
  return x + 0.5 - (x + 0.5) % 1
end

local function clampButtonPlacement(surfaceObj, btnSurf, x, y)
  local surfaceWidth = surfaceObj and surfaceObj.width or nil
  local surfaceHeight = surfaceObj and surfaceObj.height or nil

  if surfaceWidth then
    local maxX = max(0, surfaceWidth - btnSurf.width)
    x = min(max(0, x), maxX)
  end

  if surfaceHeight then
    local maxY = max(0, surfaceHeight - btnSurf.height)
    y = min(max(0, y), maxY)
  end

  return x, y
end

function M.init(surfaceAPI, font, metrics)
  assert(surfaceAPI, "surfaceAPI is required")
  assert(font, "font is required")
  _surface = surfaceAPI
  _font = font
  _metrics = metrics or monitorScale.forSurface(160, 96)
  buttonSurfaceCache = {}
  fixedButtonSurfaceCache = {}
end

function M.clearButtons()
  buttons = {}
end

function M.getButtons()
  return buttons
end

function M.getButtonSurface(textValue, bg)
  assert(_surface, "Call ui.init() first")
  local cacheKey = tostring(textValue) .. "|" .. tostring(bg)
  local cached = buttonSurfaceCache[cacheKey]
  if cached then
    return cached
  end
  local textSize = _surface.getTextSize(textValue, _font)
  local btnWidth = textSize + (_metrics.buttonPadX * 2)
  local btn = _surface.create(btnWidth, _metrics.buttonHeight)
  btn:fillRect(0, 0, btnWidth, _metrics.buttonHeight, bg)
  local fg = colors.black
  if bg == colors.black or bg == colors.gray then
    fg = colors.white
  end
  btn:drawText(textValue, _font, _metrics.buttonPadX, _metrics.buttonTextY, fg)
  buttonSurfaceCache[cacheKey] = btn
  return btn
end

function M.getFixedWidthButtonSurface(textValue, bg, fixedWidth)
  assert(_surface, "Call ui.init() first")
  local cacheKey = tostring(textValue) .. "|" .. tostring(bg) .. "|" .. tostring(fixedWidth or "")
  local cached = fixedButtonSurfaceCache[cacheKey]
  if cached then
    return cached
  end
  local textSize = _surface.getTextSize(textValue, _font)
  local minWidth = textSize + (_metrics.buttonPadX * 2)
  local btnWidth = max(fixedWidth or minWidth, minWidth)
  local btn = _surface.create(btnWidth, _metrics.buttonHeight)
  btn:fillRect(0, 0, btnWidth, _metrics.buttonHeight, bg)
  local textX = math.floor((btnWidth - textSize) / 2)
  local fg = colors.black
  if bg == colors.black or bg == colors.gray then
    fg = colors.white
  end
  btn:drawText(textValue, _font, textX, _metrics.buttonTextY, fg)
  fixedButtonSurfaceCache[cacheKey] = btn
  return btn
end

function M.button(surfaceObj, textValue, bg, x, y, func, center)
  local btnSurf = M.getButtonSurface(textValue, bg)
  if center then
    x = math.floor(x - btnSurf.width / 2)
  end
  x, y = clampButtonPlacement(surfaceObj, btnSurf, x, y)
  surfaceObj:drawSurface(btnSurf, x, y)
  buttons[textValue] = {
    x = x,
    y = y,
    width = btnSurf.width,
    height = btnSurf.height,
    cb = func,
  }
  return btnSurf
end

function M.fixedWidthButton(surfaceObj, textValue, bg, x, y, func, center, fixedWidth)
  local btnSurf = M.getFixedWidthButtonSurface(textValue, bg, fixedWidth)
  if center then
    x = math.floor(x - btnSurf.width / 2)
  end
  x, y = clampButtonPlacement(surfaceObj, btnSurf, x, y)
  surfaceObj:drawSurface(btnSurf, x, y)
  buttons[textValue] = {
    x = x,
    y = y,
    width = btnSurf.width,
    height = btnSurf.height,
    cb = func,
  }
  return btnSurf
end

function M.layoutButtonGrid(screen, buttonRows, centerX, startY, rowSpacing, colSpacing)
  rowSpacing = rowSpacing or _metrics.buttonRowSpacing
  colSpacing = colSpacing or _metrics.buttonColGap
  local screenW = screen.width or (centerX * 2)
  local plannedRows = {}

  for _, row in ipairs(buttonRows) do
    local btnSurfs = {}
    for index, btn in ipairs(row) do
      local surfaceValue = nil
      if btn.width then
        surfaceValue = M.getFixedWidthButtonSurface(btn.text, btn.color, btn.width)
      else
        surfaceValue = M.getButtonSurface(btn.text, btn.color)
      end
      btnSurfs[index] = {
        surf = surfaceValue,
        btn = btn,
      }
    end

    local subRows = {}
    local current = {}
    local currentWidth = 0
    for _, item in ipairs(btnSurfs) do
      local addedWidth = item.surf.width
      if #current > 0 then
        addedWidth = addedWidth + colSpacing
      end
      if #current > 0 and (currentWidth + addedWidth) > screenW then
        table.insert(subRows, current)
        current = { item }
        currentWidth = item.surf.width
      else
        table.insert(current, item)
        currentWidth = currentWidth + addedWidth
      end
    end
    if #current > 0 then
      table.insert(subRows, current)
    end

    for _, subRow in ipairs(subRows) do
      local totalWidth = 0
      for index, item in ipairs(subRow) do
        totalWidth = totalWidth + item.surf.width
        if index > 1 then
          totalWidth = totalWidth + colSpacing
        end
      end
      plannedRows[#plannedRows + 1] = {
        totalWidth = totalWidth,
        buttons = subRow,
      }
    end
  end

  local totalRows = #plannedRows
  local buttonHeight = _metrics.buttonHeight
  local edgePad = _metrics.edgePad or 0
  local screenH = screen.height

  if screenH and totalRows > 0 then
    local availableHeight = max(buttonHeight, screenH - (edgePad * 2))
    local neededHeight = buttonHeight + ((totalRows - 1) * rowSpacing)

    if totalRows > 1 and neededHeight > availableHeight then
      local compressedSpacing = math.floor((availableHeight - buttonHeight) / (totalRows - 1))
      rowSpacing = max(buttonHeight, compressedSpacing)
      neededHeight = buttonHeight + ((totalRows - 1) * rowSpacing)
    end

    local maxStartY = max(0, screenH - edgePad - neededHeight)
    if startY > maxStartY then
      startY = maxStartY
    end
    if startY < edgePad then
      startY = edgePad
    end
  end

  for rowIndex, rowInfo in ipairs(plannedRows) do
    local x = centerX - math.floor(rowInfo.totalWidth / 2)
    local y = startY + ((rowIndex - 1) * rowSpacing)
    for _, item in ipairs(rowInfo.buttons) do
      local drawX, drawY = clampButtonPlacement(screen, item.surf, x, y)
      screen:drawSurface(item.surf, drawX, drawY)
      buttons[item.btn.text] = {
        x = drawX,
        y = drawY,
        width = item.surf.width,
        height = item.surf.height,
        cb = item.btn.func,
      }
      x = x + item.surf.width + colSpacing
    end
  end
end

function M.drawButtonsColumn(screen, btnList, startX, startY, spacing)
  spacing = spacing or _metrics.buttonRowSpacing
  for index, button in ipairs(btnList) do
    M.button(screen, button.text, button.color, startX, startY + (index - 1) * spacing, button.func, true)
  end
end

function M.waitForButton(ox, oy, opts)
  local options = opts or {}
  local inactivityTimeout = options.inactivityTimeout
  local pollSeconds = options.pollSeconds or 0.25
  local lastActivityTime = options.lastActivityTime or os.epoch("local")

  while true do
    if not inactivityTimeout then
      local _, _, px, py = os.pullEvent("monitor_touch")
      if not touch.isAuthorizedMonitorTouch() then
        os.sleep(0)
      else
        px = px - (ox or 0)
        py = py - (oy or 0)
        for _, button in pairs(buttons) do
          if px >= button.x and px <= button.x + button.width - 1
            and py >= button.y and py <= button.y + button.height - 1 then
            buttons = {}
            button.cb()
            return
          end
        end
      end
    else
      local timerID = os.startTimer(pollSeconds)
      local event, param1, param2, param3 = os.pullEvent()
      if not (event == "timer" and param1 == timerID) then
        os.cancelTimer(timerID)
      end

      if event == "monitor_touch" then
        if not touch.isAuthorizedMonitorTouch() then
          os.sleep(0)
        else
          local px = param2 - (ox or 0)
          local py = param3 - (oy or 0)
          lastActivityTime = os.epoch("local")
          for _, button in pairs(buttons) do
            if px >= button.x and px <= button.x + button.width - 1
              and py >= button.y and py <= button.y + button.height - 1 then
              buttons = {}
              button.cb()
              return px, py, lastActivityTime
            end
          end
        end
      elseif event == "timer" and param1 == timerID then
        if (os.epoch("local") - lastActivityTime) > inactivityTimeout then
          buttons = {}
          if type(options.onTimeout) == "function" then
            return options.onTimeout()
          end
          return nil
        end
      end
    end
  end
end

function M.waitForMonitorTouch(opts)
  local options = opts or {}
  local inactivityTimeout = options.inactivityTimeout
  local pollSeconds = options.pollSeconds or 0.25
  local lastActivityTime = options.lastActivityTime or os.epoch("local")

  while true do
    if not inactivityTimeout then
      local _, side, px, py = os.pullEvent("monitor_touch")
      if touch.isAuthorizedMonitorTouch() then
        return side, px, py
      end
      os.sleep(0)
    else
      local timerID = os.startTimer(pollSeconds)
      local event, param1, param2, param3 = os.pullEvent()
      if not (event == "timer" and param1 == timerID) then
        os.cancelTimer(timerID)
      end

      if event == "monitor_touch" then
        if touch.isAuthorizedMonitorTouch() then
          lastActivityTime = os.epoch("local")
          return param1, param2, param3, lastActivityTime
        end
        os.sleep(0)
      elseif event == "timer" and param1 == timerID then
        if (os.epoch("local") - lastActivityTime) > inactivityTimeout then
          if type(options.onTimeout) == "function" then
            return options.onTimeout()
          end
          return nil
        end
      end
    end
  end
end

function M.checkButtonHit(px, py)
  for _, button in pairs(buttons) do
    if px >= button.x and px <= button.x + button.width - 1
      and py >= button.y and py <= button.y + button.height - 1 then
      local callback = button.cb
      buttons = {}
      return callback
    end
  end
  return nil
end

function M.displayCenteredMessage(screen, msg, msgColor, pause)
  assert(_surface, "Call ui.init() first")
  pause = pause or 1
  local words = {}
  local upper = tostring(msg or ""):upper()
  for word in upper:gmatch("%S+") do
    words[#words + 1] = word
  end
  local lineHeight = _metrics.messageLineHeight
  local blockHeight = #words * lineHeight
  local startY = math.floor((screen.height - blockHeight) / 2)
  screen:clear(colors.green)
  for index, word in ipairs(words) do
    local textWidth = _surface.getTextSize(word, _font)
    local centerX = math.floor((screen.width - textWidth) / 2)
    local y = startY + (index - 1) * lineHeight
    screen:drawText(word, _font, centerX, y, msgColor)
  end
  screen:output()
  os.sleep(pause)
end

function M.getFont()
  return _font
end

function M.getTextSize(textValue)
  assert(_surface, "Call ui.init() first")
  return _surface.getTextSize(textValue, _font)
end

function M.getMetrics()
  return _metrics
end

function M.round(value)
  return round(value)
end

function M.blitWrite(x, y, textValue, textColor, bgColor)
  local oldBg = term.getBackgroundColor()
  local oldText = term.getTextColor()
  local useBg = bgColor or oldBg
  local width = term.getSize()
  local maxLen = width - x + 1
  if maxLen <= 0 then
    return
  end

  local renderText = tostring(textValue or "")
  if #renderText > maxLen then
    renderText = text.truncateText(renderText, maxLen)
  end

  term.setCursorPos(x, y)
  term.blit(
    renderText,
    string.rep(colors.toBlit(textColor or oldText), #renderText),
    string.rep(colors.toBlit(useBg), #renderText)
  )
  term.setTextColor(oldText)
  term.setBackgroundColor(oldBg)
end

function M.drawCenteredText(textValue, yPos, textColor)
  local width = term.getSize()
  local renderText = tostring(textValue or "")
  if #renderText > width then
    renderText = text.truncateText(renderText, width)
  end
  local xPos = math.floor((width - #renderText) / 2) + 1
  M.blitWrite(xPos, yPos, renderText, textColor)
  return {
    x = xPos,
    y = yPos,
    text = renderText,
  }
end

function M.drawBox(x1, y1, x2, y2, bgColor)
  local oldBg = term.getBackgroundColor()
  term.setBackgroundColor(bgColor or colors.black)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
  term.setBackgroundColor(oldBg)
  return {
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
  }
end

function M.drawTermButton(x, y, width, textValue, isSelected)
  local buttonColor = isSelected and colors.lime or colors.blue
  local box = M.drawBox(x, y, x + width, y, buttonColor)
  local textX = x + math.floor((width - #textValue) / 2)
  M.blitWrite(textX, y, textValue, colors.white, buttonColor)
  return box
end

function M.safeWrite(x, y, textValue, maxWidth, textColor, bgColor)
  if textValue == nil or not maxWidth or maxWidth < 1 then
    return
  end
  M.blitWrite(x, y, text.truncateText(textValue, maxWidth), textColor, bgColor)
end

function M.drawWrappedText(x, y, textValue, maxWidth, maxLines, textColor, bgColor)
  local lines = text.wrapText(textValue, maxWidth, maxLines)
  local drawn = 0
  for index, line in ipairs(lines) do
    if maxLines and index > maxLines then
      break
    end
    M.blitWrite(x, y + index - 1, line, textColor, bgColor)
    drawn = drawn + 1
  end
  return drawn
end

function M.safeDrawText(screen, textValue, font, x, y, color)
  assert(_surface, "Call ui.init() first")
  if not textValue or not screen then
    return
  end
  if y < 0 or y >= screen.height or x >= screen.width then
    return
  end

  local drawX = x
  if drawX < 0 then
    drawX = 0
  end

  local renderText = tostring(textValue)
  local textWidth = _surface.getTextSize(renderText, font)
  local available = screen.width - drawX
  if textWidth > available and available > 0 then
    local lo = 1
    local hi = #renderText
    while lo < hi do
      local mid = math.ceil((lo + hi) / 2)
      if _surface.getTextSize(renderText:sub(1, mid), font) <= available then
        lo = mid
      else
        hi = mid - 1
      end
    end

    local dotted = lo > 2 and (renderText:sub(1, lo - 2) .. "..") or renderText:sub(1, lo)
    if _surface.getTextSize(dotted, font) <= available then
      renderText = dotted
    else
      renderText = renderText:sub(1, lo)
    end
  end

  screen:drawText(renderText, font, drawX, y, color)
end

function M.drawPlayerOverlay(monitor, playerName)
  if not monitor or not playerName then
    return
  end
  local oldTerm = term.current()
  term.redirect(monitor)
  local width = term.getSize()
  local textValue = text.truncateText("Player: " .. playerName, width - 2)
  term.setCursorPos(width - #textValue - 1, 1)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.yellow)
  term.write(textValue)
  term.redirect(oldTerm)
end

return M
