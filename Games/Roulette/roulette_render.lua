local cfg = require("roulette_config")
local ui = require("lib.ui")
local currency = require("lib.currency")
local model = require("roulette_model")

local floor = math.floor
local max = math.max
local min = math.min

local DEFAULT_TRACK_WINDOW_SLOTS = 5
local DEFAULT_TRACK_COMPACT_WINDOW_SLOTS = 3
local DEFAULT_TRACK_SLOT_GAP = 3
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

local function getSmallRectTextOffset(rect)
  if not rect or (rect.h or 0) <= 7 then
    return 0
  end
  if (rect.h or 0) <= 10 then
    return 0
  end
  return 0
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

local function getTrackCaption(state)
  if state.phase == "spinning" then
    return "SPINNING"
  elseif state.phase == "result" then
    return "WINNER"
  elseif (state.totalStake or 0) > 0 then
    return "READY"
  end
  return "WHEEL"
end

local function getTrackPointedNumber(wheelOffset)
  local offset = tonumber(wheelOffset) or 0
  local wheelIndex = (floor(offset + 0.5) % #model.WHEEL_ORDER) + 1
  return model.WHEEL_ORDER[wheelIndex]
end

local function drawTrackCard(screen, font, x, y, width, height, number)
  local bg = model.getNumberColor(number)
  local fg = model.getNumberTextColor(number)
  local insetRect = {
    x = x + 1,
    y = y + 1,
    w = max(1, width - 2),
    h = max(1, height - 2),
  }

  screen:fillRect(x, y, width, height, colors.black)
  if width > 2 and height > 2 then
    screen:fillRect(insetRect.x, insetRect.y, insetRect.w, insetRect.h, colors.black)
  end
  if width > 4 and height > 4 then
    screen:fillRect(x + 2, y + 2, width - 4, height - 4, bg)
    insetRect = {
      x = x + 2,
      y = y + 2,
      w = width - 4,
      h = height - 4,
    }
  else
    screen:fillRect(insetRect.x, insetRect.y, insetRect.w, insetRect.h, bg)
  end

  drawCenteredText(screen, font, insetRect, tostring(number), fg)
end

local function drawTrackArrow(screen, centerX, tipY, color)
  screen:fillRect(centerX, tipY - 5, 1, 2, color)
  screen:fillRect(centerX - 2, tipY - 3, 5, 1, color)
  screen:fillRect(centerX - 1, tipY - 2, 3, 1, color)
  screen:fillRect(centerX, tipY - 1, 1, 1, color)
end

local function drawTrackHistory(screen, font, layout, track, recent, rowY)
  if layout.compact then
    return
  end

  local count = min(layout.compact and 2 or 3, #recent)
  if count <= 0 then
    return
  end

  local pillW = layout.compact and 7 or 8
  local pillH = 7
  local pillGap = 2
  local label = layout.compact and "" or "LAST"
  local labelW = label ~= "" and (ui.getTextSize(label) + 3) or 0
  local maxWidth = floor(track.w * (layout.compact and 0.32 or 0.42))
  local totalW = (count * pillW) + ((count - 1) * pillGap) + labelW
  while count > 1 and totalW > maxWidth do
    count = count - 1
    totalW = (count * pillW) + ((count - 1) * pillGap) + labelW
  end
  local drawX = track.x + track.w - totalW - 3

  if label ~= "" then
    ui.safeDrawText(screen, label, font, drawX, rowY, colors.lightGray)
    drawX = drawX + labelW
  end

  local index = 1
  while index <= count do
    local number = recent[index]
    drawTrackCard(screen, font, drawX, rowY, pillW, pillH, number)
    drawX = drawX + pillW + pillGap
    index = index + 1
  end
end

local function getBetCountLabel(count)
  count = tonumber(count) or 0
  if count == 1 then
    return "1 bet"
  end
  return tostring(count) .. " bets"
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
  local titleY = track.y + 2
  local title = getTrackCaption(state)
  local titleColor = colors.lightGray
  if state.phase == "spinning" then
    titleColor = colors.yellow
  elseif state.phase == "result" then
    titleColor = getToneColor(state.statusTone)
  end
  ui.safeDrawText(screen, title, font, track.x + 3, titleY, titleColor)
  drawTrackHistory(screen, font, layout, track, recent, titleY)

  local maxWindowSlots = layout.compact and DEFAULT_TRACK_COMPACT_WINDOW_SLOTS or DEFAULT_TRACK_WINDOW_SLOTS
  local configuredWindowSlots = layout.compact
    and (cfg.TRACK_COMPACT_WINDOW_SLOTS or maxWindowSlots)
    or (cfg.TRACK_WINDOW_SLOTS or maxWindowSlots)
  local configuredWindowGap = layout.compact
    and (cfg.TRACK_COMPACT_SLOT_GAP or DEFAULT_TRACK_COMPACT_SLOT_GAP)
    or (cfg.TRACK_SLOT_GAP or DEFAULT_TRACK_SLOT_GAP)
  local windowSlots = max(3, min(maxWindowSlots, configuredWindowSlots))
  local windowGap = layout.compact
    and max(1, min(2, configuredWindowGap))
    or max(2, min(4, configuredWindowGap))
  local laneRect = {
    x = track.x + 2,
    y = track.y + (layout.compact and 7 or 10),
    w = track.w - 4,
    h = track.h - (layout.compact and 8 or 12),
  }
  local laneInnerX = laneRect.x + 2
  local laneInnerW = max(1, laneRect.w - 4)
  local laneInnerY = laneRect.y + 2
  local laneInnerH = max(1, laneRect.h - 4)
  local minCellW = layout.compact and 5 or 8
  local minTrackLabelW = ui.getTextSize("36") + 2
  local cellW = max(minCellW, min(layout.compact and 9 or 13, floor((laneInnerW - ((windowSlots - 1) * windowGap)) / windowSlots)))
  local cellH = max(1, min(laneInnerH, layout.compact and 8 or 10))

  while windowSlots > 3 do
    local availableCellW = floor((laneInnerW - ((windowSlots - 1) * windowGap)) / windowSlots)
    if availableCellW >= minTrackLabelW then
      break
    end
    windowSlots = windowSlots - 2
  end

  cellW = max(minTrackLabelW, floor((laneInnerW - ((windowSlots - 1) * windowGap)) / windowSlots))
  local windowW = (windowSlots * cellW) + ((windowSlots - 1) * windowGap)

  drawFrame(screen, laneRect, colors.black, colors.lightGray)

  local windowX = laneInnerX + floor((laneInnerW - windowW) / 2)
  local cellY = laneInnerY + floor((laneInnerH - cellH) / 2)
  local pointerSlot = floor((windowSlots + 1) / 2)
  local slotPitch = cellW + windowGap
  local pointerX = windowX + floor(cellW / 2) + ((pointerSlot - 1) * slotPitch)
  local pointerColor = state.phase == "spinning" and colors.yellow or colors.lightGray

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
    if cellX < (laneInnerX + laneInnerW) and (cellX + cellW) > laneInnerX then
      drawTrackCard(screen, font, cellX, cellY, cellW, cellH, number)
    end
    offset = offset + 1
  end

  drawTrackArrow(screen, pointerX, cellY, pointerColor)

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
  local rowY = box.y + 8
  local rowGap = max(7, layout.scale.lineHeight - 1)
  local lineW = max(1, box.w - 4)

  drawCenteredText(screen, font, {
    x = box.x,
    y = box.y + 1,
    w = box.w,
    h = 7,
  }, headline, colors.white)

  if layout.compact then
    local compactY = box.y + box.h - 8
    ui.safeDrawText(screen, fitTextToWidth("Chip " .. formatUiTokens(selectedChipValue), max(1, floor(box.w * 0.45))), font, labelX, compactY, colors.lightGray)
    drawRightText(screen, font, "Bet " .. formatUiTokens(state.totalStake or 0), box.x + box.w - 2, compactY, colors.white, labelX + max(8, floor(box.w * 0.45)))
    return
  end

  ui.safeDrawText(screen, fitTextToWidth("Chip " .. formatUiTokens(selectedChipValue), lineW), font, labelX, rowY, colors.lightGray)
  rowY = rowY + rowGap

  ui.safeDrawText(screen, fitTextToWidth("Bet " .. formatUiTokens(state.totalStake or 0), lineW), font, labelX, rowY, colors.white)
  rowY = rowY + rowGap

  ui.safeDrawText(screen, fitTextToWidth("Best " .. formatUiTokens(state.maxExposure or 0), lineW), font, labelX, rowY, colors.lightGray)
end

local function drawButtons(screen, font, layout, state)
  local selectedChipIndex = state.selectedChipIndex or 1
  local denominations = state.denominations or {}

  if layout.wideControls and layout.chipPanel ~= nil then
    drawFrame(screen, layout.chipPanel, colors.gray, colors.yellow)
    drawCenteredText(screen, font, {
      x = layout.chipPanel.x,
      y = layout.chipPanel.y + 1,
      w = layout.chipPanel.w,
      h = layout.panelLabelH,
    }, "CHIP", colors.lightGray)
  elseif not layout.compact and layout.chipButtons[1] then
    drawCenteredText(screen, font, {
      x = layout.panel.x,
      y = layout.chipButtons[1].y - layout.panelLabelH,
      w = layout.panel.w,
      h = layout.panelLabelH,
    }, "CHIPS", colors.lightGray)
  end

  for index, button in ipairs(layout.chipButtons) do
    local denom = denominations[index]
    if denom then
      local isSelected = (index == selectedChipIndex)
      local border = isSelected and colors.yellow or colors.black
      local fill = isSelected and denom.color or colors.gray
      screen:fillRect(button.x, button.y, button.w, button.h, border)
      screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
      local textColor = (fill == colors.black or fill == colors.gray) and colors.white or colors.black
      drawCenteredText(screen, font, button, formatCompactAmount(denom.value), textColor, 0)
    end
  end

  local enabled = {
    spin = (state.totalStake or 0) > 0,
    undo = (state.betActionCount or 0) > 0,
    clear = (state.totalStake or 0) > 0,
    double = (state.totalStake or 0) > 0,
    quit = true,
  }

  if layout.wideControls and layout.actionPanel ~= nil then
    drawFrame(screen, layout.actionPanel, colors.gray, colors.yellow)
    drawCenteredText(screen, font, {
      x = layout.actionPanel.x,
      y = layout.actionPanel.y + 1,
      w = layout.actionPanel.w,
      h = layout.panelLabelH,
    }, "PLAY", colors.lightGray)
  elseif not layout.compact and layout.actionButtons[1] then
    local actionPanel = layout.rightRail or layout.panel
    drawCenteredText(screen, font, {
      x = actionPanel.x,
      y = layout.actionButtons[1].y - layout.panelLabelH,
      w = actionPanel.w,
      h = layout.panelLabelH,
    }, "PLAY", colors.lightGray)
  end

  for _, button in ipairs(layout.actionButtons) do
    local isEnabled = enabled[button.key] == true
    local fill = isEnabled and button.color or colors.gray
    screen:fillRect(button.x, button.y, button.w, button.h, colors.black)
    screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
    local textColor = (fill == colors.black or fill == colors.gray) and colors.white or colors.black
    drawCenteredText(screen, font, button, button.label, textColor, 0)
  end
end

local function drawSlipBox(screen, font, layout, state)
  if layout.compact or layout.slipBox.h <= 0 then
    return
  end

  local box = layout.slipBox
  local bets = state.bets or {}

  if layout.wideControls then
    drawFrame(screen, box, colors.gray, colors.yellow)

    local sessionText = "Session " .. (state.sessionProfitText or "0")
    local sessionX = box.x + 3
    local sessionY = box.y + floor((box.h - 7) / 2)
    local sessionW = min(max(26, ui.getTextSize(sessionText) + 8), floor(box.w * 0.28))
    local messageRect = {
      x = box.x + 2,
      y = box.y + 1,
      w = box.w - 4,
      h = box.h - 2,
    }

    if box.w >= 72 then
      ui.safeDrawText(screen, fitTextToWidth(sessionText, max(1, sessionW - 4)), font, sessionX, sessionY, getToneColor(state.sessionProfitTone))
      messageRect.x = box.x + sessionW
      messageRect.w = box.w - sessionW - 2
    end

    if #bets == 0 then
      drawWrappedCenteredText(
        screen,
        font,
        messageRect,
        "1 PICK CHIP   2 TAP A NUMBER OR COLOR   3 PRESS SPIN",
        colors.lightGray,
        box.h >= 14 and 2 or 1
      )
    else
      local message = getBetCountLabel(#bets) .. " ready. Total " .. formatUiTokens(state.totalStake or 0) .. ". Best " .. formatUiTokens(state.maxExposure or 0) .. "."
      drawWrappedCenteredText(
        screen,
        font,
        messageRect,
        message,
        colors.lightGray,
        box.h >= 14 and 2 or 1
      )
    end
    return
  end

  local contentX = box.x + 2
  local contentW = max(1, box.w - 4)
  local lineHeight = max(7, layout.scale.lineHeight)
  local footerY = box.y + box.h - 8
  local y = box.y + 2
  drawFrame(screen, box, colors.gray, colors.yellow)

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
    drawWrappedCenteredText(screen, font, region, region.displayText, textColor, maxLines, getSmallRectTextOffset(region))
  else
    drawCenteredText(screen, font, region, region.displayText, textColor, getSmallRectTextOffset(region))
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
      drawCenteredText(screen, font, region, label, labelColor, compact and 0 or getSmallRectTextOffset(region))
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
  drawTable(screen, font, layout, state)
  drawSummaryBox(screen, font, layout, state)
  drawButtons(screen, font, layout, state)
  drawSlipBox(screen, font, layout, state)
  screen:output()
end

return {
  draw = draw,
  getTrackPointedNumber = getTrackPointedNumber,
}
