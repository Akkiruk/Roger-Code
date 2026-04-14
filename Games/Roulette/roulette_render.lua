local cfg = require("roulette_config")
local ui = require("lib.ui")
local model = require("roulette_model")

local floor = math.floor
local max = math.max
local min = math.min
local cos = math.cos
local sin = math.sin
local pi = math.pi

local TAU = pi * 2
local TOP_ANGLE = -pi / 2
local POCKET_ANGLE = TAU / #model.WHEEL_ORDER
local WHEEL_VISUAL_Y_SCALE = tonumber(cfg.WHEEL_VISUAL_Y_SCALE) or 1
local SPIN_LOOKUP_SUBDIVISIONS = max(4, tonumber(cfg.SPIN_LOOKUP_SUBDIVISIONS) or 8)
local spinFrameCache = nil
local spinAssetCache = nil

local function invalidateSpinFrameCache()
  spinFrameCache = nil
end

local function invalidateSpinAssets()
  spinAssetCache = nil
  spinFrameCache = nil
end

local function normalizeAngle(angle)
  while angle < 0 do
    angle = angle + TAU
  end
  while angle >= TAU do
    angle = angle - TAU
  end
  return angle
end

local function scaleVisualY(value)
  return max(1, floor((value * WHEEL_VISUAL_Y_SCALE) + 0.5))
end

local function pointOnEllipse(centerX, centerY, radiusX, radiusY, angle)
  return floor(centerX + (cos(angle) * radiusX)), floor(centerY + (sin(angle) * radiusY))
end

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
      local parts = splitWordToWidth(word, maxWidth)
      for _, part in ipairs(parts) do
        words[#words + 1] = part
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
  local renderText = fitTextToWidth(text, max(1, rect.w - inset))
  if renderText == "" then
    return
  end
  local width = ui.getTextSize(renderText)
  local textX = rect.x + floor((rect.w - width) / 2)
  local textY = rect.y + floor((rect.h - 7) / 2) + (yOffset or 0)
  ui.safeDrawText(screen, renderText, font, textX, textY, color)
end

local function drawWrappedCenteredText(screen, font, rect, text, color, maxLines, yOffset)
  local inset = rect.w > 4 and 2 or 0
  local maxWidth = max(1, rect.w - inset)
  local lines = wrapTextToWidth(text, maxWidth, maxLines)
  local _, fontHeight = ui.getTextSize("A")
  fontHeight = max(1, fontHeight or 7)
  local totalHeight = fontHeight + ((#lines - 1) * fontHeight)
  local textY = rect.y + floor((rect.h - totalHeight) / 2) + (yOffset or 0)

  for _, line in ipairs(lines) do
    local width = ui.getTextSize(line)
    local textX = rect.x + floor((rect.w - width) / 2)
    ui.safeDrawText(screen, line, font, textX, textY, color)
    textY = textY + fontHeight
  end
end

local function drawWrappedLeftText(screen, font, x, y, maxWidth, text, color, maxLines, lineAdvance)
  local lines = wrapTextToWidth(text, maxWidth, maxLines)
  local advance = max(1, lineAdvance or 7)

  for index, line in ipairs(lines) do
    ui.safeDrawText(screen, line, font, x, y + ((index - 1) * advance), color)
  end

  return #lines
end

local function drawRightText(screen, font, text, rightX, y, color, leftX)
  local renderText = fitTextToWidth(text, max(1, rightX - (leftX or 0)))
  if renderText == "" then
    return
  end
  local width = ui.getTextSize(renderText)
  ui.safeDrawText(screen, renderText, font, rightX - width, y, color)
end

local function drawFrame(screen, rect, fillColor, borderColor)
  screen:fillRect(rect.x, rect.y, rect.w, rect.h, borderColor)
  if rect.w > 2 and rect.h > 2 then
    screen:fillRect(rect.x + 1, rect.y + 1, rect.w - 2, rect.h - 2, fillColor)
  end
end

local function drawBackgroundBands(screen, width, height, colorsList)
  local bandHeight = max(1, floor(height / #colorsList))
  local y = 0
  for index, color in ipairs(colorsList) do
    local nextY = index == #colorsList and height or min(height, y + bandHeight)
    screen:fillRect(0, y, width, max(1, nextY - y), color)
    y = nextY
  end
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
  for _, bet in ipairs(bets or {}) do
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
  return colors.green, colors.lightGray, hasBet, isHighlighted
end

local function drawPrimaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted)
  if hasBet or isHighlighted then
    screen:fillRect(region.x - 1, region.y - 1, region.w + 2, region.h + 2, isHighlighted and colors.yellow or colors.orange)
  end
  screen:fillRect(region.x, region.y, region.w, region.h, fill)

  local maxLines = 1
  local _, fontHeight = ui.getTextSize("A")
  fontHeight = max(1, fontHeight or 7)
  if region.drawStyle == "outside" and ui.getTextSize(region.displayText or "") > max(1, region.w - 2) and region.h >= (fontHeight * 2) then
    maxLines = 2
  end

  if maxLines > 1 then
    drawWrappedCenteredText(screen, font, region, region.displayText, textColor, maxLines, 0)
  else
    drawCenteredText(screen, font, region, region.displayText, textColor, 0)
  end
end

local function drawSecondaryRegion(screen, font, region, hasBet, isHighlighted, compact)
  if region.drawStyle == "street" then
    local baseColor = colors.green
    local label = ""
    local labelColor = colors.lightGray
    if isHighlighted then
      baseColor = colors.yellow
      label = region.displayText
      labelColor = colors.black
    elseif hasBet then
      baseColor = colors.orange
      label = region.displayText
      labelColor = colors.black
    end
    screen:fillRect(region.x, region.y, region.w, region.h, baseColor)
    if label ~= "" then
      drawCenteredText(screen, font, region, label, labelColor, compact and 0 or 0)
    end
    return
  end

  if hasBet or isHighlighted then
    screen:fillRect(region.x, region.y, region.w, region.h, isHighlighted and colors.yellow or colors.orange)
  end
end

local function drawChip(screen, font, x, y, amount, fillColor, compact)
  local radius = compact and 2 or 3
  local diameter = (radius * 2) + 1
  local chipX = x - radius
  local chipY = y - radius

  screen:fillEllipse(chipX, chipY, diameter, diameter, colors.yellow)
  screen:fillEllipse(chipX + 1, chipY + 1, max(1, diameter - 2), max(1, diameter - 2), fillColor)
  if diameter > 4 then
    screen:fillEllipse(chipX + 2, chipY + 2, max(1, diameter - 4), max(1, diameter - 4), colors.black)
  end

  if not compact then
    local text = formatCompactAmount(amount)
    local textWidth = ui.getTextSize(text)
    ui.safeDrawText(screen, text, font, x - floor(textWidth / 2), chipY - 6, colors.white)
  end
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

  local stakeMap = buildStakeMap(state.bets)
  local highlightKeys = state.highlightKeys

  for _, region in ipairs(layout.regions) do
    local fill, textColor, hasBet, isHighlighted = getRegionFill(region, stakeMap, highlightKeys)
    if region.drawStyle == "straight" or region.drawStyle == "zero" or region.drawStyle == "outside" then
      drawPrimaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted)
    else
      drawSecondaryRegion(screen, font, region, hasBet, isHighlighted, layout.compact)
    end
  end

  for _, bet in ipairs(state.bets or {}) do
    for _, region in ipairs(layout.regions) do
      if region.key == bet.key then
        drawChip(screen, font, region.cx, region.cy, bet.stake or 0, region.fillColor or colors.gray, layout.compact)
        break
      end
    end
  end
end

local function drawHistoryPill(screen, font, x, y, width, height, number)
  local fill = model.getNumberColor(number)
  local textColor = model.getNumberTextColor(number)
  screen:fillRect(x, y, width, height, colors.black)
  if width > 2 and height > 2 then
    screen:fillRect(x + 1, y + 1, width - 2, height - 2, fill)
  end
  drawCenteredText(screen, font, { x = x, y = y, w = width, h = height }, tostring(number), textColor, 0)
end

local function drawBettingHeader(screen, font, layout, state)
  local header = layout.header
  drawBackgroundBands(screen, layout.width, header.h, {
    colors.black,
    colors.gray,
    colors.black,
  })
  screen:fillRect(0, header.h - 1, layout.width, 1, colors.yellow)

  drawCenteredText(screen, font, { x = 0, y = 1, w = layout.width, h = 7 }, "ROULETTE TABLE", colors.yellow, 0)
  drawCenteredText(screen, font, { x = 0, y = 8, w = layout.width, h = 7 }, "Build the layout here. The wheel gets its own page.", colors.lightGray, 0)

  local infoY = header.h - 8
  ui.safeDrawText(screen, fitTextToWidth("Balance " .. formatUiTokens(state.playerBalance or 0), max(12, floor(layout.width * 0.38))), font, 2, infoY, colors.white)
  drawRightText(screen, font, "You " .. (state.currentPlayer or "Unknown"), layout.width - 2, infoY, colors.lightGray, floor(layout.width * 0.48))
end

local function drawBettingHistoryStrip(screen, font, layout, state)
  local track = layout.track
  drawFrame(screen, track, colors.gray, colors.yellow)

  ui.safeDrawText(screen, "RECENT", font, track.x + 3, track.y + 2, colors.white)
  drawRightText(screen, font, state.statusText or "Pick a chip, then tap the table.", track.x + track.w - 3, track.y + 2, getToneColor(state.statusTone), track.x + 30)

  local count = min(layout.compact and 5 or 8, #(state.history or {}))
  local pillW = layout.compact and 7 or 8
  local pillGap = 2
  local totalW = (count * pillW) + max(0, count - 1) * pillGap
  local startX = track.x + floor((track.w - totalW) / 2)
  local y = track.y + track.h - 9

  for index = 1, count do
    drawHistoryPill(screen, font, startX + ((index - 1) * (pillW + pillGap)), y, pillW, 7, state.history[index])
  end
end

local function drawSummaryBox(screen, font, layout, state)
  local box = layout.summaryBox
  drawFrame(screen, box, colors.gray, colors.yellow)

  local headline = "BUILD YOUR BET"
  if (state.totalStake or 0) > 0 then
    headline = "READY TO SPIN"
  end

  drawCenteredText(screen, font, { x = box.x, y = box.y + 1, w = box.w, h = 7 }, headline, colors.white, 0)

  local selectedChip = (state.denominations or {})[state.selectedChipIndex or 1]
  local selectedChipValue = selectedChip and selectedChip.value or 0
  local contentX = box.x + 2
  local rowY = box.y + 8
  local lineGap = max(7, layout.scale.lineHeight - 1)
  local lineW = max(1, box.w - 4)

  ui.safeDrawText(screen, fitTextToWidth("Chip " .. formatUiTokens(selectedChipValue), lineW), font, contentX, rowY, colors.lightGray)
  rowY = rowY + lineGap
  ui.safeDrawText(screen, fitTextToWidth("Bet " .. formatUiTokens(state.totalStake or 0), lineW), font, contentX, rowY, colors.white)
  rowY = rowY + lineGap
  ui.safeDrawText(screen, fitTextToWidth("Best " .. formatUiTokens(state.maxExposure or 0), lineW), font, contentX, rowY, colors.lightGray)

  if not layout.compact then
    rowY = rowY + lineGap
    ui.safeDrawText(screen, fitTextToWidth("Session " .. (state.sessionProfitText or "0"), lineW), font, contentX, rowY, getToneColor(state.sessionProfitTone))
  end
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
    }, "CHIPS", colors.lightGray, 0)
  end

  for index, button in ipairs(layout.chipButtons) do
    local denom = denominations[index]
    if denom then
      local isSelected = index == selectedChipIndex
      local border = isSelected and colors.yellow or colors.black
      local fill = isSelected and denom.color or colors.gray
      screen:fillRect(button.x, button.y, button.w, button.h, border)
      if button.w > 2 and button.h > 2 then
        screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
      end
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

  local actionPanel = layout.rightRail or layout.panel
  if not layout.compact and layout.actionButtons[1] then
    drawCenteredText(screen, font, {
      x = actionPanel.x,
      y = layout.actionButtons[1].y - layout.panelLabelH,
      w = actionPanel.w,
      h = layout.panelLabelH,
    }, "PLAY", colors.lightGray, 0)
  end

  for _, button in ipairs(layout.actionButtons) do
    local fill = enabled[button.key] and button.color or colors.gray
    screen:fillRect(button.x, button.y, button.w, button.h, colors.black)
    if button.w > 2 and button.h > 2 then
      screen:fillRect(button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
    end
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
  local contentX = box.x + 2
  local contentW = max(1, box.w - 4)
  local lineHeight = max(7, layout.scale.lineHeight)
  local y = box.y + 2
  local footerY = box.y + box.h - 8

  drawFrame(screen, box, colors.gray, colors.yellow)
  ui.safeDrawText(screen, #bets == 0 and "FLOW" or "BET SLIP", font, contentX, y, colors.white)
  y = y + lineHeight

  if #bets == 0 then
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "1 Pick a chip.", colors.yellow, 1, lineHeight) * lineHeight)
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "2 Touch a number, split, dozen, or color.", colors.lightGray, 2, lineHeight) * lineHeight)
    y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, "3 Press SPIN to leave this page and watch the wheel.", colors.lightGray, 3, lineHeight) * lineHeight)
    drawWrappedLeftText(screen, font, contentX, y, contentW, "UNDO removes the last move. CLEAR wipes everything.", colors.lightGray, 3, lineHeight)
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
      if y + (lineHeight * 2) > footerY then
        break
      end
      ui.safeDrawText(screen, formatUiTokens(bet.stake or 0), font, contentX, y, colors.yellow)
      y = y + lineHeight
      y = y + (drawWrappedLeftText(screen, font, contentX, y, contentW, tostring(bet.label or bet.key or ""), colors.lightGray, 1, lineHeight) * lineHeight)
      y = y + 1
      index = index - 1
    end

    if index >= 1 and y <= footerY then
      ui.safeDrawText(screen, "+" .. tostring(index) .. " more bets", font, contentX, y, colors.lightGray)
    end
  end

  drawRightText(screen, font, "Session " .. (state.sessionProfitText or "0"), box.x + box.w - 2, box.y + box.h - 8, getToneColor(state.sessionProfitTone))
end

local function drawBettingPage(screen, font, layout, state)
  screen:clear(colors.black)
  drawBettingHeader(screen, font, layout, state)
  drawBettingHistoryStrip(screen, font, layout, state)
  drawTable(screen, font, layout, state)
  drawSummaryBox(screen, font, layout, state)
  drawButtons(screen, font, layout, state)
  drawSlipBox(screen, font, layout, state)
  screen:output()
end

local function getTrackPointedNumber(wheelOffset)
  local offset = tonumber(wheelOffset) or 0
  local wheelIndex = (floor(offset + 0.5) % #model.WHEEL_ORDER) + 1
  return model.WHEEL_ORDER[wheelIndex]
end

local function getPocketAngle(index)
  return TOP_ANGLE + ((index - 1) * POCKET_ANGLE)
end

local function getBallAngleForOffset(wheelOffset)
  return TOP_ANGLE + ((tonumber(wheelOffset) or 0) * POCKET_ANGLE)
end

local function normalizeOffset(wheelOffset)
  local wheelSize = #model.WHEEL_ORDER
  local offset = (tonumber(wheelOffset) or 0) % wheelSize
  if offset < 0 then
    offset = offset + wheelSize
  end
  return offset
end

local function drawWheelShadow(screen, metrics)
  screen:fillEllipse(metrics.outerX + 2, metrics.outerY + 3, metrics.diameter, metrics.diameterY, colors.black)
end

local function drawShowcaseBackdrop(screen, layout)
  screen:fillRect(0, 0, layout.width, layout.height, colors.black)
  screen:fillRect(0, 0, layout.width, 12, colors.gray)
  screen:fillRect(0, layout.height - 10, layout.width, 10, colors.gray)
  screen:fillRect(0, 12, layout.width, 1, colors.lightGray)
  screen:fillRect(0, layout.height - 11, layout.width, 1, colors.lightGray)
end

local function getShowcaseWheelMetrics(layout)
  local diameter = floor(min(layout.width - 14, layout.height - 28))
  diameter = max(45, diameter)
  if diameter % 2 == 0 then
    diameter = diameter - 1
  end

  local radius = floor(diameter / 2)
  local radiusY = scaleVisualY(radius)
  local centerX = floor(layout.width / 2)
  local centerY = floor(layout.height / 2) + 2
  if centerY + radiusY > layout.height - 12 then
    centerY = layout.height - 12 - radiusY
  end
  if centerY - radiusY < 15 then
    centerY = 15 + radiusY
  end

  local outerX = centerX - radius
  local outerY = centerY - radiusY
  local pocketOuter = max(16, radius - 5)
  local pocketOuterY = scaleVisualY(pocketOuter)
  local pocketInner = max(8, pocketOuter - max(8, floor(radius * 0.24)))
  local pocketInnerY = scaleVisualY(pocketInner)

  local ballRadius = max(2, floor(radius * 0.07))
  local ballRadiusY = scaleVisualY(ballRadius)
  local ballTrackRadius = min(radius - 2, pocketOuter + max(4, floor(radius * 0.08)))
  local ballTrackRadiusY = scaleVisualY(ballTrackRadius)
  local markerTrackRadius = max(pocketInner + 3, ballTrackRadius - 5)
  local markerTrackRadiusY = max(pocketInnerY + 3, ballTrackRadiusY - scaleVisualY(5))
  local maxDynamicRadius = max(radius, ballTrackRadius + ballRadius)
  local maxDynamicRadiusY = max(radiusY, ballTrackRadiusY + ballRadiusY)
  local dynamicRectX = max(0, centerX - maxDynamicRadius - 4)
  local dynamicRectY = max(0, centerY - maxDynamicRadiusY - 10)
  local dynamicRectRight = min(layout.width - 1, centerX + maxDynamicRadius + 4)
  local dynamicRectBottom = min(layout.height - 1, centerY + maxDynamicRadiusY + 4)

  return {
    diameter = diameter,
    diameterY = (radiusY * 2) + 1,
    radius = radius,
    radiusY = radiusY,
    centerX = centerX,
    centerY = centerY,
    outerX = outerX,
    outerY = outerY,
    pocketOuter = pocketOuter,
    pocketOuterY = pocketOuterY,
    pocketInner = pocketInner,
    pocketInnerY = pocketInnerY,
    ballRadius = ballRadius,
    ballRadiusY = ballRadiusY,
    ballTrackRadius = ballTrackRadius,
    ballTrackRadiusY = ballTrackRadiusY,
    markerTrackRadius = markerTrackRadius,
    markerTrackRadiusY = markerTrackRadiusY,
    dynamicRect = {
      x = dynamicRectX,
      y = dynamicRectY,
      w = max(1, dynamicRectRight - dynamicRectX + 1),
      h = max(1, dynamicRectBottom - dynamicRectY + 1),
    },
  }
end

local function buildBadgeGeometry(metrics)
  local width = max(13, min(19, floor(metrics.radius * 0.9)))
  return {
    width = width,
    height = 9,
    x = metrics.centerX - floor(width / 2),
    y = metrics.centerY - 4,
  }
end

local function buildBadgeSurface(surfaceApi, font, badge, number)
  local surf = surfaceApi.create(badge.width + 2, badge.height + 2)
  surf:fillRect(0, 0, badge.width + 2, badge.height + 2, colors.lightGray)
  surf:fillRect(1, 1, badge.width, badge.height, model.getNumberColor(number))
  drawCenteredText(surf, font, { x = 1, y = 1, w = badge.width, h = badge.height }, tostring(number), model.getNumberTextColor(number), 0)
  return surf
end

local function buildBallSurface(surfaceApi, metrics)
  local width = (metrics.ballRadius * 2) + 3
  local height = (metrics.ballRadiusY * 2) + 3
  local surf = surfaceApi.create(width, height)
  surf:fillEllipse(1, 1, (metrics.ballRadius * 2) + 1, (metrics.ballRadiusY * 2) + 1, colors.black)
  surf:fillEllipse(0, 0, (metrics.ballRadius * 2) + 1, (metrics.ballRadiusY * 2) + 1, colors.white)
  return {
    surface = surf,
    width = width,
    height = height,
  }
end

local function buildSpinLookup(metrics)
  local frames = {}
  local wheelSize = #model.WHEEL_ORDER
  local total = wheelSize * SPIN_LOOKUP_SUBDIVISIONS

  for index = 0, total - 1 do
    local offset = index / SPIN_LOOKUP_SUBDIVISIONS
    local number = getTrackPointedNumber(offset)
    local angle = getBallAngleForOffset(offset)
    local x, y = pointOnEllipse(metrics.centerX, metrics.centerY, metrics.ballTrackRadius, metrics.ballTrackRadiusY, angle)
    frames[index + 1] = {
      offset = offset,
      number = number,
      angle = angle,
      x = x,
      y = y,
    }
  end

  return {
    substeps = SPIN_LOOKUP_SUBDIVISIONS,
    total = total,
    frames = frames,
  }
end

local function ensureSpinAssets(surfaceApi, font, layout)
  if not surfaceApi then
    return nil
  end

  local metrics = getShowcaseWheelMetrics(layout)
  local badge = buildBadgeGeometry(metrics)
  local cache = spinAssetCache
  if cache
    and cache.width == layout.width
    and cache.height == layout.height
    and cache.diameter == metrics.diameter
    and cache.badgeWidth == badge.width then
    return cache
  end

  local badges = {}
  for _, number in ipairs(model.WHEEL_ORDER) do
    badges[number] = buildBadgeSurface(surfaceApi, font, badge, number)
  end

  cache = {
    width = layout.width,
    height = layout.height,
    diameter = metrics.diameter,
    badge = badge,
    badgeWidth = badge.width,
    badges = badges,
    ball = buildBallSurface(surfaceApi, metrics),
    lookup = buildSpinLookup(metrics),
  }

  spinAssetCache = cache
  return cache
end

local function getSpinLookupEntry(assets, wheelOffset)
  if not assets or not assets.lookup then
    return nil
  end

  local lookup = assets.lookup
  local normalized = normalizeOffset(wheelOffset)
  local index = (floor((normalized * lookup.substeps) + 0.5) % lookup.total) + 1
  return lookup.frames[index]
end

local function drawWheelMarker(screen, metrics, angle, fill, border, highlight)
  local markerRadius = highlight and 3 or 2
  local markerRadiusY = scaleVisualY(markerRadius)
  local markerX, markerY = pointOnEllipse(metrics.centerX, metrics.centerY, metrics.markerTrackRadius, metrics.markerTrackRadiusY, angle)

  screen:fillEllipse(markerX - markerRadius, markerY - markerRadiusY, (markerRadius * 2) + 1, (markerRadiusY * 2) + 1, border)
  screen:fillEllipse(markerX - markerRadius + 1, markerY - markerRadiusY + 1, max(1, (markerRadius * 2) - 1), max(1, (markerRadiusY * 2) - 1), fill)
end

local function drawWheelBody(screen, metrics, winningIndex)
  local diameter = metrics.diameter
  local outerX = metrics.outerX
  local outerY = metrics.outerY

  screen:fillEllipse(outerX, outerY, diameter, metrics.diameterY, colors.lightGray)
  screen:fillEllipse(outerX + 2, outerY + 2, max(1, diameter - 4), max(1, metrics.diameterY - 4), colors.gray)
  screen:fillEllipse(outerX + 5, outerY + 5, max(1, diameter - 10), max(1, metrics.diameterY - 10), colors.black)
  screen:fillEllipse(outerX + 10, outerY + 10, max(1, diameter - 20), max(1, metrics.diameterY - 20), colors.gray)

  for index, number in ipairs(model.WHEEL_ORDER) do
    local isWinningPocket = winningIndex ~= nil and winningIndex == index
    local fill = model.getNumberColor(number)
    local border = isWinningPocket and colors.yellow or colors.lightGray
    drawWheelMarker(screen, metrics, getPocketAngle(index), fill, border, isWinningPocket)
  end

  local hubRadius = max(6, floor(metrics.radius * 0.18))
  local hubRadiusY = scaleVisualY(hubRadius)
  screen:fillEllipse(metrics.centerX - hubRadius, metrics.centerY - hubRadiusY, (hubRadius * 2) + 1, (hubRadiusY * 2) + 1, colors.lightGray)
  screen:fillEllipse(metrics.centerX - hubRadius + 1, metrics.centerY - hubRadiusY + 1, max(1, (hubRadius * 2) - 1), max(1, (hubRadiusY * 2) - 1), colors.black)
end

local function drawWheelBall(screen, metrics, assets, wheelOffset, ballAngle)
  local entry = getSpinLookupEntry(assets, wheelOffset)
  if entry and assets.ball then
    screen:drawSurface(assets.ball.surface, entry.x - metrics.ballRadius, entry.y - metrics.ballRadiusY)
    return entry
  end

  local angle = ballAngle or getBallAngleForOffset(wheelOffset)
  local ballX, ballY = pointOnEllipse(metrics.centerX, metrics.centerY, metrics.ballTrackRadius, metrics.ballTrackRadiusY, angle)
  screen:fillEllipse(ballX - metrics.ballRadius + 1, ballY - metrics.ballRadiusY + 1, (metrics.ballRadius * 2) + 1, (metrics.ballRadiusY * 2) + 1, colors.black)
  screen:fillEllipse(ballX - metrics.ballRadius, ballY - metrics.ballRadiusY, (metrics.ballRadius * 2) + 1, (metrics.ballRadiusY * 2) + 1, colors.white)

  return {
    number = getTrackPointedNumber(wheelOffset),
    angle = angle,
    x = ballX,
    y = ballY,
  }
end

local function drawWheelReadout(screen, font, metrics, state, assets, displayNumber)
  displayNumber = displayNumber or state.resultNumber or getTrackPointedNumber(state.wheelOffset)
  if displayNumber == nil then
    return
  end

  local badge = (assets and assets.badge) or buildBadgeGeometry(metrics)
  local badgeX = badge.x
  local badgeY = badge.y
  local badgeFill = model.getNumberColor(displayNumber)
  local labelColor = state.phase == "spinning" and colors.white or badgeFill

  if assets and assets.badges and assets.badges[displayNumber] then
    screen:drawSurface(assets.badges[displayNumber], badgeX - 1, badgeY - 1)
  else
    screen:fillRect(badgeX - 1, badgeY - 1, badge.width + 2, badge.height + 2, colors.lightGray)
    screen:fillRect(badgeX, badgeY, badge.width, badge.height, badgeFill)
    drawCenteredText(screen, font, { x = badgeX, y = badgeY, w = badge.width, h = badge.height }, tostring(displayNumber), model.getNumberTextColor(displayNumber), 0)
  end

  drawCenteredText(
    screen,
    font,
    { x = metrics.centerX - 20, y = badgeY + badge.height + 1, w = 40, h = 7 },
    state.phase == "spinning" and "BALL ON" or model.getColorName(displayNumber),
    labelColor,
    0
  )
end

local function drawShowcaseWheel(screen, font, layout, state, metrics)
  metrics = metrics or getShowcaseWheelMetrics(layout)
  local assets = ensureSpinAssets(state.surfaceApi, font, layout)

  local winningIndex = state.resultNumber and model.getWheelIndex(state.resultNumber) or nil

  drawWheelShadow(screen, metrics)
  drawWheelBody(screen, metrics, winningIndex)
  local ballEntry = drawWheelBall(screen, metrics, assets, state.wheelOffset, state.ballAngle or getBallAngleForOffset(state.wheelOffset))
  drawWheelReadout(screen, font, metrics, state, assets, ballEntry and ballEntry.number or nil)
end

local function drawShowcaseHeader(screen, font, layout, state)
  local headline = state.phase == "spinning" and "SPINNING THE WHEEL" or "WINNING POCKET"
  local subline = state.phase == "spinning"
    and "Bets locked. Wheel page active."
    or ((state.resultNumber and (tostring(state.resultNumber) .. " " .. model.getColorName(state.resultNumber))) or "Result")

  drawCenteredText(screen, font, { x = 0, y = 1, w = layout.width, h = 7 }, headline, colors.yellow, 0)
  drawCenteredText(screen, font, { x = 0, y = 7, w = layout.width, h = 7 }, subline, getToneColor(state.statusTone), 0)
end

local function drawShowcaseHistory(screen, font, layout, state)
  local count = min(layout.compact and 4 or 6, #(state.history or {}))
  if count <= 0 then
    return
  end

  local pillW = layout.compact and 7 or 8
  local pillGap = 2
  local totalW = (count * pillW) + ((count - 1) * pillGap)
  local startX = floor((layout.width - totalW) / 2)
  local y = layout.height - 18

  for index = 1, count do
    drawHistoryPill(screen, font, startX + ((index - 1) * (pillW + pillGap)), y, pillW, 7, state.history[index])
  end
end

local function drawShowcaseFooter(screen, font, layout, state)
  local footerY = layout.height - 8
  ui.safeDrawText(screen, fitTextToWidth("Stake " .. formatUiTokens(state.totalStake or 0), max(12, floor(layout.width * 0.28))), font, 2, footerY, colors.white)
  drawCenteredText(screen, font, { x = floor(layout.width * 0.20), y = footerY - 1, w = floor(layout.width * 0.60), h = 8 }, state.statusText or "Wheel spinning...", getToneColor(state.statusTone), 0)
  drawRightText(screen, font, "Session " .. (state.sessionProfitText or "0"), layout.width - 2, footerY, getToneColor(state.sessionProfitTone), floor(layout.width * 0.68))
end

local function buildSpinFrameCache(screen, font, layout, state)
  local metrics = getShowcaseWheelMetrics(layout)
  local assets = ensureSpinAssets(state.surfaceApi, font, layout)

  screen:clear(colors.black)
  drawShowcaseBackdrop(screen, layout)
  drawShowcaseHeader(screen, font, layout, state)
  drawShowcaseHistory(screen, font, layout, state)
  drawShowcaseFooter(screen, font, layout, state)
  drawWheelShadow(screen, metrics)
  drawWheelBody(screen, metrics, nil)

  spinFrameCache = {
    width = layout.width,
    height = layout.height,
    base = screen:copy(),
    wheelRect = metrics.dynamicRect,
    metrics = metrics,
    assets = assets,
    needsFullOutput = true,
  }

  return spinFrameCache
end

local function drawSpinningShowcasePage(screen, font, layout, state)
  local cache = spinFrameCache
  if not cache or cache.width ~= layout.width or cache.height ~= layout.height then
    cache = buildSpinFrameCache(screen, font, layout, state)
  end

  local wheelRect = cache.wheelRect
  screen:drawSurface(cache.base, wheelRect.x, wheelRect.y, wheelRect.w, wheelRect.h, wheelRect.x, wheelRect.y, wheelRect.w, wheelRect.h)
  local ballEntry = drawWheelBall(screen, cache.metrics, cache.assets, state.wheelOffset, state.ballAngle or getBallAngleForOffset(state.wheelOffset))
  drawWheelReadout(screen, font, cache.metrics, state, cache.assets, ballEntry and ballEntry.number or nil)
  if cache.needsFullOutput then
    screen:output()
    cache.needsFullOutput = false
  else
    screen:output(nil, wheelRect.x, wheelRect.y, wheelRect.x, wheelRect.y, wheelRect.w, wheelRect.h)
  end
end

local function drawShowcasePage(screen, font, layout, state)
  if state.phase == "spinning" then
    drawSpinningShowcasePage(screen, font, layout, state)
    return
  end

  invalidateSpinFrameCache()
  screen:clear(colors.black)
  drawShowcaseBackdrop(screen, layout)
  drawShowcaseHeader(screen, font, layout, state)
  drawShowcaseWheel(screen, font, layout, state)
  drawShowcaseHistory(screen, font, layout, state)
  drawShowcaseFooter(screen, font, layout, state)
  screen:output()
end

local function draw(screen, font, layout, state)
  if type(state) == "table" and state.surfaceApi then
    ensureSpinAssets(state.surfaceApi, font, layout)
  end

  if state.phase == "betting" then
    invalidateSpinFrameCache()
    drawBettingPage(screen, font, layout, state)
    return
  end

  drawShowcasePage(screen, font, layout, state)
end

return {
  draw = draw,
  getTrackPointedNumber = getTrackPointedNumber,
  getBallAngleForOffset = getBallAngleForOffset,
}