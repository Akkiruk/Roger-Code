local cfg = require("roulette_config")
local ui = require("lib.ui")
local currency = require("lib.currency")
local model = require("roulette_model")

local floor = math.floor
local max = math.max
local min = math.min

local DEFAULT_TRACK_WINDOW_SLOTS = 7
local DEFAULT_TRACK_COMPACT_WINDOW_SLOTS = 5
local DEFAULT_TRACK_SLOT_GAP = 1
local DEFAULT_TRACK_COMPACT_SLOT_GAP = 1

local function getToneColor(tone)
  if tone == "error" then
    return colors.red
  elseif tone == "warning" then
    return colors.orange
  elseif tone == "success" then
    return colors.lime
  elseif tone == "accent" then
    return colors.cyan
  end
  return colors.lightGray
end

local function getCompactHeaderPlayer(playerName)
  if not playerName or playerName == "" then
    return "PLAYER"
  end
  return playerName
end

local function pointInRect(px, py, rect)
  return px >= rect.x and px <= (rect.x + rect.w - 1)
    and py >= rect.y and py <= (rect.y + rect.h - 1)
end

local function drawFrame(screen, rect, fillColor, borderColor)
  screen:fillRect(rect.x, rect.y, rect.w, rect.h, borderColor)
  if rect.w > 2 and rect.h > 2 then
    screen:fillRect(rect.x + 1, rect.y + 1, rect.w - 2, rect.h - 2, fillColor)
  end
end

local function fitTextToWidth(text, maxWidth)
  text = tostring(text or "")
  if maxWidth <= 0 then
    return ""
  end
  if ui.getTextSize(text) <= maxWidth then
    return text
  end

  local length = #text
  while length > 0 do
    local candidate = text:sub(1, length)
    if ui.getTextSize(candidate) <= maxWidth then
      return candidate
    end
    length = length - 1
  end

  return ""
end

local function splitWordToWidth(word, maxWidth)
  local parts = {}
  local startIndex = 1

  while startIndex <= #word do
    local best = startIndex
    local length = startIndex
    while length <= #word do
      local candidate = word:sub(startIndex, length)
      if ui.getTextSize(candidate) <= maxWidth then
        best = length
        length = length + 1
      else
        break
      end
    end

    if best < startIndex then
      best = startIndex
    end

    parts[#parts + 1] = word:sub(startIndex, best)
    startIndex = best + 1
  end

  return parts
end

local function wrapTextToWidth(text, maxWidth, maxLines)
  text = tostring(text or "")
  if maxWidth <= 0 then
    return { "" }
  end

  local words = {}
  for word in text:gmatch("%S+") do
    if ui.getTextSize(word) <= maxWidth then
      words[#words + 1] = word
    else
      local pieces = splitWordToWidth(word, maxWidth)
      for _, piece in ipairs(pieces) do
        words[#words + 1] = piece
      end
    end
  end

  if #words == 0 then
    return { "" }
  end

  local lines = {}
  local current = ""
  for _, word in ipairs(words) do
    local candidate = current == "" and word or (current .. " " .. word)
    if current == "" or ui.getTextSize(candidate) <= maxWidth then
      current = candidate
    else
      lines[#lines + 1] = current
      current = word
    end
  end

  if current ~= "" then
    lines[#lines + 1] = current
  end

  if maxLines and #lines > maxLines then
    local limited = {}
    local index = 1
    while index <= maxLines do
      limited[index] = lines[index]
      index = index + 1
    end
    limited[maxLines] = fitTextToWidth(limited[maxLines], maxWidth)
    return limited
  end

  return lines
end

local function drawCenteredText(screen, font, rect, text, color, yOffset)
  local inset = rect.w > 4 and 2 or 0
  text = fitTextToWidth(text, max(1, rect.w - inset))
  if text == "" then
    return
  end
  local width = ui.getTextSize(text)
  local textX = rect.x + floor((rect.w - width) / 2)
  local textY = rect.y + floor((rect.h - 7) / 2) + (yOffset or 0)
  ui.safeDrawText(screen, text, font, textX, textY, color)
end

local function drawWrappedCenteredText(screen, font, rect, text, color, maxLines, yOffset)
  local inset = rect.w > 4 and 2 or 0
  local maxWidth = max(1, rect.w - inset)
  local lines = wrapTextToWidth(text, maxWidth, maxLines)
  local _, fontHeight = ui.getTextSize("A")
  fontHeight = max(1, fontHeight or 7)
  local lineAdvance = fontHeight
  local totalHeight = fontHeight + ((#lines - 1) * lineAdvance)
  local textY = rect.y + floor((rect.h - totalHeight) / 2) + (yOffset or 0)

  for _, line in ipairs(lines) do
    local width = ui.getTextSize(line)
    local textX = rect.x + floor((rect.w - width) / 2)
    ui.safeDrawText(screen, line, font, textX, textY, color)
    textY = textY + lineAdvance
  end
end

local function drawWrappedLeftText(screen, font, x, y, maxWidth, text, color, maxLines, lineAdvance)
  local lines = wrapTextToWidth(text, maxWidth, maxLines)
  local advance = max(1, lineAdvance or 7)
  local index = 1

  while index <= #lines do
    ui.safeDrawText(screen, lines[index], font, x, y + ((index - 1) * advance), color)
    index = index + 1
  end

  return #lines
end

local function drawRightText(screen, font, text, rightX, y, color, leftX)
  text = fitTextToWidth(text, max(1, rightX - (leftX or 0)))
  if text == "" then
    return
  end
  local width = ui.getTextSize(text)
  ui.safeDrawText(screen, text, font, rightX - width, y, color)
end

local function formatCompactAmount(amount)
  if amount >= 1000 then
    local scaled = floor((amount + 50) / 100) / 10
    if scaled == floor(scaled) then
      return tostring(floor(scaled)) .. "k"
    end
    return string.format("%.1fk", scaled)
  end
  return tostring(amount)
end

local function formatUiTokens(amount)
  return formatCompactAmount(tonumber(amount) or 0)
end

local function buildStakeMap(bets)
  local map = {}
  for _, bet in ipairs(bets) do
    map[bet.key] = bet.stake or 0
  end
  return map
end

local function getRegionFill(region, stakeMap, highlightKeys)
  local hasBet = stakeMap[region.key] ~= nil
  local isHighlighted = highlightKeys and highlightKeys[region.key] == true

  if region.drawStyle == "straight" or region.drawStyle == "zero" then
    return region.fillColor, region.textColor, hasBet, isHighlighted
  end

  if region.drawStyle == "outside" then
    if isHighlighted then
      return colors.yellow, colors.black, hasBet, isHighlighted
    end
    if hasBet then
      return region.fillColor, region.textColor, hasBet, isHighlighted
    end
    return colors.gray, colors.lightGray, hasBet, isHighlighted
  end

  if isHighlighted then
    return colors.yellow, colors.black, hasBet, isHighlighted
  end
  if hasBet then
    return colors.orange, colors.black, hasBet, isHighlighted
  end
  return colors.gray, colors.lightGray, hasBet, isHighlighted
end

local function drawChip(screen, font, x, y, amount, toneColor)
  local compact = false
  if type(toneColor) == "table" then
    compact = toneColor.compact == true
    toneColor = toneColor.color
  end

  if compact then
    local chipW = 5
    local chipH = 3
    local chipX = x - floor(chipW / 2)
    local chipY = y - floor(chipH / 2)
    screen:fillRect(chipX, chipY, chipW, chipH, colors.yellow)
    screen:fillRect(chipX + 1, chipY + 1, chipW - 2, chipH - 2, toneColor)
    return
  end

  local chipW = 7
  local chipH = 5
  local chipX = x - floor(chipW / 2)
  local chipY = y - floor(chipH / 2)
  screen:fillRect(chipX, chipY, chipW, chipH, colors.yellow)
  screen:fillRect(chipX + 1, chipY + 1, chipW - 2, chipH - 2, toneColor)
  screen:fillRect(chipX + 2, chipY + 2, chipW - 4, chipH - 4, colors.black)

  local text = formatCompactAmount(amount)
  local textW = ui.getTextSize(text)
  ui.safeDrawText(screen, text, font, x - floor(textW / 2), chipY - 1, colors.white)
end

local function getDisplayedWheelNumber(wheelOffset)
  local index = (floor((wheelOffset or 0) + 0.5) % #model.WHEEL_ORDER) + 1
  return model.WHEEL_ORDER[index]
end

local function drawTrackArrow(screen, centerX, topY, bottomY, color)
  if bottomY < topY then
    return
  end

  screen:fillRect(centerX - 2, topY, 5, 1, color)
  if topY + 1 <= bottomY then
    screen:fillRect(centerX - 1, topY + 1, 3, 1, color)
  end
  if topY + 2 <= bottomY then
    screen:fillRect(centerX, topY + 2, 1, 1, color)
  end
end

local function drawTrackSelector(screen, x, y, width, height, color)
  screen:fillRect(x, y, width, 1, color)
  screen:fillRect(x, y + height - 1, width, 1, color)
  screen:fillRect(x, y, 1, height, color)
  screen:fillRect(x + width - 1, y, 1, height, color)
end

local function drawHeader(screen, font, layout, state)
  local header = layout.header
  screen:fillRect(header.x, header.y, header.w, header.h, colors.black)
  screen:fillRect(header.x, header.y + header.h - 1, header.w, 1, colors.yellow)

  local title = "ROULETTE"
  local statusText = state.statusText or "Pick a chip, then tap the table."
  local toneColor = getToneColor(state.statusTone)
  local headerPad = max(3, layout.margin + 2)

  if layout.compact then
    local titleRect = { x = 0, y = header.y + 1, w = layout.width, h = 7 }
    drawCenteredText(screen, font, titleRect, title, colors.yellow)

    if layout.ultraCompact then
      local compactStatus = fitTextToWidth(statusText, layout.width - 4)
      ui.safeDrawText(screen, compactStatus, font, 2, header.y + header.h - 8, toneColor)
      return
    end

    local infoY = header.y + header.h - 8
    local bankText = "Bal " .. formatUiTokens(state.playerBalance or 0)
    ui.safeDrawText(screen, fitTextToWidth(bankText, max(8, floor(layout.width * 0.4))), font, headerPad, infoY, colors.lightGray)

    local playerName = getCompactHeaderPlayer(state.currentPlayer or "Unknown")
    drawRightText(screen, font, playerName, layout.width - headerPad, infoY, colors.lightGray, floor(layout.width * 0.45))
    return
  end

  local titleRect = { x = headerPad, y = header.y + 2, w = layout.width - (headerPad * 2), h = 7 }
  drawCenteredText(screen, font, titleRect, title, colors.yellow)

  local infoY = header.y + 10
  local left = "Balance " .. formatUiTokens(state.playerBalance or 0)
  ui.safeDrawText(screen, fitTextToWidth(left, max(12, floor(layout.width * 0.38))), font, headerPad, infoY, colors.lightGray)

  local playerName = fitTextToWidth("You " .. (state.currentPlayer or "Unknown"), max(12, floor(layout.width * 0.38)))
  drawRightText(screen, font, playerName, layout.width - headerPad, infoY, colors.lightGray, floor(layout.width * 0.46))

  drawCenteredText(screen, font, {
    x = headerPad,
    y = header.y + header.h - 8,
    w = layout.width - (headerPad * 2),
    h = 7,
  }, statusText, toneColor)
end

local function drawTrack(screen, font, layout, state)
  local track = layout.track
  drawFrame(screen, track, colors.gray, colors.yellow)

  local recent = state.history or {}
  local recentLabelW = (layout.compact or #recent == 0) and 0 or (ui.getTextSize("LAST") + 2)
  local recentX = track.x + 2 + recentLabelW
  local recentY = track.y + floor((track.h - 5) / 2)
  local recentCount = min(layout.ultraCompact and 1 or (layout.compact and 2 or 3), #recent)
  local recentCellW = layout.ultraCompact and 4 or 5
  local recentCellH = 5
  local recentGap = 1
  local showFocus = not layout.ultraCompact
  local focusW = showFocus and (layout.compact and 7 or 11) or 0
  local focusGap = showFocus and 2 or 0
  local maxWindowSlots = layout.compact and DEFAULT_TRACK_COMPACT_WINDOW_SLOTS or DEFAULT_TRACK_WINDOW_SLOTS
  local configuredWindowSlots = layout.compact
    and (cfg.TRACK_COMPACT_WINDOW_SLOTS or maxWindowSlots)
    or (cfg.TRACK_WINDOW_SLOTS or maxWindowSlots)
  local configuredWindowGap = layout.compact
    and (cfg.TRACK_COMPACT_SLOT_GAP or DEFAULT_TRACK_COMPACT_SLOT_GAP)
    or (cfg.TRACK_SLOT_GAP or DEFAULT_TRACK_SLOT_GAP)
  local windowSlots = max(3, min(maxWindowSlots, configuredWindowSlots))
  local windowGap = max(1, min(layout.compact and DEFAULT_TRACK_COMPACT_SLOT_GAP or DEFAULT_TRACK_SLOT_GAP, configuredWindowGap))
  local cellW = max(4, min(track.cellW + (layout.compact and 0 or 2), layout.compact and 6 or 9))
  local windowW = (windowSlots * cellW) + ((windowSlots - 1) * windowGap)
  local bandH = layout.compact and 5 or 7
  local bandTopY = track.y + floor((track.h - bandH) / 2)
  local focusX = track.x + track.w - focusW - 2
  local focusRect = nil

  if showFocus then
    focusRect = {
      x = focusX,
      y = track.y + 2,
      w = focusW,
      h = track.h - 4,
    }
  end

  local recentReserve = 0
  if recentCount > 0 then
    recentReserve = (recentCount * recentCellW) + ((recentCount - 1) * recentGap) + 2
  end

  local availableLeft = recentX + recentReserve
  local availableRight = showFocus and (focusX - focusGap - 1) or (track.x + track.w - 2)
  local windowAreaW = max(1, availableRight - availableLeft + 1)

  if windowW > windowAreaW then
    cellW = max(3, floor((windowAreaW - ((windowSlots - 1) * windowGap)) / windowSlots))
    windowW = (windowSlots * cellW) + ((windowSlots - 1) * windowGap)
  end

  local windowX = availableLeft + floor((windowAreaW - windowW) / 2)
  local pointerSlot = floor((windowSlots + 1) / 2)
  local slotPitch = cellW + windowGap
  local pointerX = windowX + floor(cellW / 2) + ((pointerSlot - 1) * slotPitch)
  local bandRect = {
    x = windowX - 1,
    y = bandTopY - 1,
    w = windowW + 2,
    h = bandH + 2,
  }

  drawFrame(screen, bandRect, colors.black, colors.lightGray)

  local recentWidthAvailable = max(0, windowX - recentX - 2)
  local maxRecentCount = floor((recentWidthAvailable + recentGap) / (recentCellW + recentGap))
  recentCount = min(recentCount, maxRecentCount)

  if recentCount > 0 then
    if not layout.compact then
      ui.safeDrawText(screen, "LAST", font, track.x + 2, recentY - 1, colors.lightGray)
    end

    local index = 1
    while index <= recentCount do
      local number = recent[index]
      local bg = model.getNumberColor(number)
      local fg = model.getNumberTextColor(number)
      local slotX = recentX + ((index - 1) * (recentCellW + recentGap))
      screen:fillRect(slotX, recentY, recentCellW, recentCellH, bg)
      local label = tostring(number)
      local labelW = ui.getTextSize(label)
      ui.safeDrawText(screen, label, font, slotX + floor((recentCellW - labelW) / 2), recentY - 1, fg)
      index = index + 1
    end
  end

  drawTrackArrow(screen, pointerX, max(track.y + 1, bandTopY - 3), bandTopY - 1, colors.yellow)

  local wheelOffset = state.wheelOffset or 0
  local baseIndex = floor(wheelOffset)
  local fraction = wheelOffset - baseIndex
  local visibleLeft = pointerSlot + 1
  local visibleRight = windowSlots - pointerSlot + 2

  local offset = -visibleLeft
  while offset <= visibleRight do
    local wheelIndex = ((baseIndex + offset) % #model.WHEEL_ORDER) + 1
    local number = model.WHEEL_ORDER[wheelIndex]
    local cellX = pointerX + floor((offset - fraction) * slotPitch) - floor(cellW / 2)
    if cellX < (windowX + windowW) and (cellX + cellW) > windowX then
      local bg = model.getNumberColor(number)
      local fg = model.getNumberTextColor(number)
      screen:fillRect(cellX, bandTopY, cellW, bandH, bg)
      local label = tostring(number)
      local labelW = ui.getTextSize(label)
      ui.safeDrawText(screen, label, font, cellX + floor((cellW - labelW) / 2), bandTopY - 1, fg)
    end
    offset = offset + 1
  end

  drawTrackSelector(screen, pointerX - floor(cellW / 2) - 1, bandTopY - 1, cellW + 2, bandH + 2, colors.yellow)

  if focusRect then
    local currentNumber = getDisplayedWheelNumber(wheelOffset)
    local bg = model.getNumberColor(currentNumber)
    local fg = model.getNumberTextColor(currentNumber)
    local focusLabel = "NOW"
    if state.phase == "result" then
      focusLabel = "WIN"
    end
    drawFrame(screen, focusRect, bg, colors.yellow)

    if not layout.compact then
      drawCenteredText(screen, font, {
        x = focusRect.x,
        y = focusRect.y + 1,
        w = focusRect.w,
        h = 7,
      }, focusLabel, fg)
    end

    drawCenteredText(screen, font, {
      x = focusRect.x,
      y = focusRect.y + (layout.compact and 1 or 7),
      w = focusRect.w,
      h = max(7, focusRect.h - (layout.compact and 2 or 8)),
    }, tostring(currentNumber), fg, layout.compact and 0 or 1)
  end
end

local function drawSummaryBox(screen, font, layout, state)
  local box = layout.summaryBox
  drawFrame(screen, box, colors.gray, colors.yellow)

  local headline = "READY"
  if state.phase == "spinning" then
    headline = "SPINNING"
  elseif state.phase == "result" and state.resultNumber ~= nil then
    headline = tostring(state.resultNumber) .. " " .. model.getColorName(state.resultNumber)
  elseif state.autoPlay then
    headline = "AUTO PLAY"
  elseif (state.totalStake or 0) > 0 then
    headline = "PRESS SPIN"
  end
  local denominations = state.denominations or {}
  local selectedChip = denominations[state.selectedChipIndex or 1]
  local selectedChipValue = selectedChip and selectedChip.value or 0
  local labelX = box.x + 2
  local valueRight = box.x + box.w - 2
  local valueLeft = labelX + max(8, floor(box.w * 0.45))
  local rowY = box.y + 10
  local rowGap = max(7, layout.scale.lineHeight)

  drawCenteredText(screen, font, {
    x = box.x,
    y = box.y + 1,
    w = box.w,
    h = 7,
  }, headline, colors.white)

  if layout.compact then
    local compactY = box.y + box.h - 8
    ui.safeDrawText(screen, fitTextToWidth("Chip " .. formatUiTokens(selectedChipValue), max(1, floor(box.w * 0.45))), font, labelX, compactY, colors.lightGray)
    drawRightText(screen, font, "Bet " .. formatUiTokens(state.totalStake or 0), valueRight, compactY, colors.white, valueLeft)
    return
  end

  ui.safeDrawText(screen, fitTextToWidth("Chip", max(1, valueLeft - labelX - 1)), font, labelX, rowY, colors.lightGray)
  drawRightText(screen, font, formatUiTokens(selectedChipValue), valueRight, rowY, colors.white, valueLeft)
  rowY = rowY + rowGap

  ui.safeDrawText(screen, fitTextToWidth("Bet", max(1, valueLeft - labelX - 1)), font, labelX, rowY, colors.lightGray)
  drawRightText(screen, font, formatUiTokens(state.totalStake or 0), valueRight, rowY, colors.white, valueLeft)
  rowY = rowY + rowGap

  ui.safeDrawText(screen, fitTextToWidth("Best win", max(1, valueLeft - labelX - 1)), font, labelX, rowY, colors.lightGray)
  drawRightText(screen, font, formatUiTokens(state.maxExposure or 0), valueRight, rowY, colors.white, valueLeft)
end

local function drawButtons(screen, font, layout, state)
  local selectedChipIndex = state.selectedChipIndex or 1
  local denominations = state.denominations or {}

  if not layout.compact and layout.chipButtons[1] then
    drawCenteredText(screen, font, {
      x = layout.panel.x,
      y = layout.chipButtons[1].y - layout.panelLabelH,
      w = layout.panel.w,
      h = layout.panelLabelH,
    }, "PICK CHIP", colors.lightGray)
  end

  for index, button in ipairs(layout.chipButtons) do
    local denom = denominations[index]
    if denom then
      local isSelected = (index == selectedChipIndex)
      local border = isSelected and colors.yellow or colors.black
      local fill = isSelected and denom.color or colors.gray
      screen:fillRect(button.x, button.y, button.w, button.h, border)
      screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
      drawCenteredText(screen, font, button, formatCompactAmount(denom.value), colors.black, layout.compact and -1 or 0)
    end
  end

  local enabled = {
    spin = (state.totalStake or 0) > 0,
    undo = (state.betActionCount or 0) > 0,
    clear = (state.totalStake or 0) > 0,
    double = (state.totalStake or 0) > 0,
    quit = true,
  }

  if not layout.compact and layout.actionButtons[1] then
    drawCenteredText(screen, font, {
      x = layout.panel.x,
      y = layout.actionButtons[1].y - layout.panelLabelH,
      w = layout.panel.w,
      h = layout.panelLabelH,
    }, "ACTIONS", colors.lightGray)
  end

  for _, button in ipairs(layout.actionButtons) do
    local isEnabled = enabled[button.key] == true
    local fill = isEnabled and button.color or colors.gray
    screen:fillRect(button.x, button.y, button.w, button.h, colors.black)
    screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
    local textColor = (fill == colors.black or fill == colors.gray) and colors.white or colors.black
    drawCenteredText(screen, font, button, button.label, textColor, layout.compact and -1 or 0)
  end
end

local function drawSlipBox(screen, font, layout, state)
  if layout.compact or layout.slipBox.h <= 0 then
    return
  end

  local box = layout.slipBox
  local contentX = box.x + 2
  local contentW = max(1, box.w - 4)
  local lineHeight = max(7, layout.scale.lineHeight)
  local footerY = box.y + box.h - 8
  local y = box.y + 2
  drawFrame(screen, box, colors.gray, colors.yellow)

  local bets = state.bets or {}
  local title = (#bets == 0) and "STEPS" or "BETS"
  ui.safeDrawText(screen, title, font, contentX, y, colors.white)
  y = y + lineHeight

  if #bets == 0 then
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "1 Pick chip.", colors.yellow, 1, lineHeight) * lineHeight)
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "2 Tap table.", colors.lightGray, 1, lineHeight) * lineHeight)
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "3 Press SPIN.", colors.lightGray, 1, lineHeight) * lineHeight)
    drawWrappedLeftText(screen, font, contentX, y, contentW, "UNDO = back. CLEAR = all off.", colors.lightGray, 3, lineHeight)
  else
    ui.safeDrawText(screen, fitTextToWidth("Bet " .. formatUiTokens(state.totalStake or 0), contentW), font, contentX, y, colors.yellow)
    y = y + lineHeight
    ui.safeDrawText(screen, fitTextToWidth("Best " .. formatUiTokens(state.maxExposure or 0), contentW), font, contentX, y, colors.lightGray)
    y = y + lineHeight

    screen:fillRect(contentX, y, contentW, 1, colors.yellow)
    y = y + 2

    local index = #bets
    while index >= 1 do
      local bet = bets[index]
      local nextY = y + (lineHeight * 2) + 1
      if nextY > footerY then
        break
      end

      ui.safeDrawText(screen, formatUiTokens(bet.stake or 0), font, contentX, y, colors.yellow)
      y = y + lineHeight
      y = y + (drawWrappedLeftText(
        screen,
        font,
        contentX,
        y,
        contentW,
        tostring(bet.label or bet.key or ""),
        colors.lightGray,
        1,
        lineHeight
      ) * lineHeight)
      y = y + 1
      index = index - 1
    end

    if index >= 1 and y <= footerY then
      ui.safeDrawText(screen, "+" .. tostring(index) .. " more bets", font, contentX, y, colors.lightGray)
    end
  end

  local footer = "Session " .. (state.sessionProfitText or "0")
  drawRightText(screen, font, footer, box.x + box.w - 2, box.y + box.h - 8, getToneColor(state.sessionProfitTone))
end

local function drawPrimaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted)
  screen:fillRect(region.x, region.y, region.w, region.h, fill)
  if hasBet or isHighlighted then
    screen:fillRect(region.x - 1, region.y - 1, region.w + 2, region.h + 2, colors.yellow)
    screen:fillRect(region.x, region.y, region.w, region.h, fill)
  end
  local maxLines = 1
  local _, fontHeight = ui.getTextSize("A")
  fontHeight = max(1, fontHeight or 7)
  if region.drawStyle == "outside" and ui.getTextSize(region.displayText or "") > max(1, region.w - 2) and region.h >= (fontHeight * 2) then
    maxLines = 2
  end

  if maxLines > 1 then
    drawWrappedCenteredText(screen, font, region, region.displayText, textColor, maxLines)
  else
    drawCenteredText(screen, font, region, region.displayText, textColor)
  end
end

local function drawSecondaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted, compact)
  if region.drawStyle == "street" then
    local baseColor = colors.green
    local label = ""
    local labelColor = textColor
    if isHighlighted then
      baseColor = colors.yellow
      label = region.displayText
      labelColor = colors.black
    elseif hasBet then
      baseColor = colors.orange
      label = region.displayText
    end
    screen:fillRect(region.x, region.y, region.w, region.h, baseColor)
    if label ~= "" then
      drawCenteredText(screen, font, region, label, labelColor, compact and -1 or 0)
    end
    return
  end

  if hasBet or isHighlighted then
    local markerColor = isHighlighted and colors.yellow or colors.orange
    screen:fillRect(region.x, region.y, region.w, region.h, markerColor)
    if region.drawStyle == "line" then
      screen:fillRect(region.x, region.y, region.w, region.h, markerColor)
    end
    return
  end

  return
end

local function drawTable(screen, font, layout, state)
  local felt = layout.felt
  drawFrame(screen, felt, colors.green, colors.yellow)

  local tableBox = layout.table
  local boardRect = {
    x = tableBox.x - 1,
    y = tableBox.y - 1,
    w = tableBox.zeroW + tableBox.streetW + 3,
    h = (tableBox.evenBottomY + tableBox.cellH + 2) - (tableBox.y - 1),
  }
  screen:fillRect(boardRect.x, boardRect.y, boardRect.w, boardRect.h, colors.green)

  local stakeMap = buildStakeMap(state.bets or {})
  local highlightKeys = state.highlightKeys

  for _, region in ipairs(layout.regions) do
    local fill, textColor, hasBet, isHighlighted = getRegionFill(region, stakeMap, highlightKeys)

    if region.drawStyle == "straight" or region.drawStyle == "zero" or region.drawStyle == "outside" then
      drawPrimaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted)
    else
      drawSecondaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted, layout.compact)
    end
  end

  for _, bet in ipairs(state.bets or {}) do
    for _, region in ipairs(layout.regions) do
      if region.key == bet.key then
        drawChip(screen, font, region.cx, region.cy, bet.stake or 0, {
          color = region.fillColor or colors.gray,
          compact = layout.compact,
        })
        break
      end
    end
  end
end

local function draw(screen, font, layout, state)
  screen:clear(colors.black)
  drawHeader(screen, font, layout, state)
  drawTrack(screen, font, layout, state)
  drawSummaryBox(screen, font, layout, state)
  drawButtons(screen, font, layout, state)
  drawSlipBox(screen, font, layout, state)
  drawTable(screen, font, layout, state)
  screen:output()
end

return {
  draw = draw,
}
