local ui = require("lib.ui")
local currency = require("lib.currency")
local model = require("roulette_model")

local floor = math.floor
local max = math.max
local min = math.min

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

local function drawHeader(screen, font, layout, state)
  local header = layout.header
  screen:fillRect(header.x, header.y, header.w, header.h, colors.black)
  screen:fillRect(header.x, header.y + header.h - 1, header.w, 1, colors.yellow)

  local title = "ROULETTE"
  local statusText = state.statusText or "Choose a chip and touch the felt."
  local toneColor = getToneColor(state.statusTone)

  if layout.compact then
    local titleRect = { x = 0, y = header.y + 1, w = layout.width, h = 7 }
    drawCenteredText(screen, font, titleRect, title, colors.yellow)

    if layout.ultraCompact then
      local compactStatus = fitTextToWidth(statusText, layout.width - 4)
      ui.safeDrawText(screen, compactStatus, font, 2, header.y + header.h - 8, toneColor)
      return
    end

    local infoY = header.y + header.h - 8
    local bankText = "Bal " .. formatCompactAmount(state.playerBalance or 0)
    ui.safeDrawText(screen, fitTextToWidth(bankText, max(8, floor(layout.width * 0.4))), font, 2, infoY, colors.lightGray)

    local playerName = getCompactHeaderPlayer(state.currentPlayer or "Unknown")
    drawRightText(screen, font, playerName, layout.width - 2, infoY, colors.lightGray, floor(layout.width * 0.45))
    return
  end

  local titleRect = { x = 0, y = header.y + 1, w = layout.width, h = 7 }
  drawCenteredText(screen, font, titleRect, title, colors.yellow)

  local left = "Bankroll " .. currency.formatTokens(state.playerBalance or 0)
  ui.safeDrawText(screen, left, font, 2, header.y + 8, colors.lightGray)

  local playerName = state.currentPlayer or "Unknown"
  drawRightText(screen, font, "Player " .. playerName, layout.width - 2, header.y + 8, colors.lightGray)

  drawCenteredText(screen, font, {
    x = 0,
    y = header.y + header.h - 8,
    w = layout.width,
    h = 7,
  }, statusText, toneColor)
end

local function drawTrack(screen, font, layout, state)
  local track = layout.track
  drawFrame(screen, track, colors.gray, colors.yellow)

  local recent = state.history or {}
  local recentX = track.x + 2
  local recentY = track.y + 1
  local recentCount = min(layout.ultraCompact and 2 or (layout.compact and 4 or 6), #recent)
  local slotWidth = layout.ultraCompact and 4 or 5
  local slotGap = 1
  local bandX = track.x + 1
  local bandW = track.w - 2

  if layout.compact then
    if recentCount > 0 then
      local compactRecentWidth = (recentCount * slotWidth) + ((recentCount - 1) * slotGap)
      bandX = recentX + compactRecentWidth + 2
      bandW = track.x + track.w - bandX - 1

      local index = 1
      while index <= recentCount do
        local number = recent[index]
        local bg = model.getNumberColor(number)
        local fg = model.getNumberTextColor(number)
        local slotX = recentX + ((index - 1) * (slotWidth + slotGap))
        screen:fillRect(slotX, recentY, slotWidth, 5, bg)
        local label = tostring(number)
        local labelW = ui.getTextSize(label)
        ui.safeDrawText(screen, label, font, slotX + floor((slotWidth - labelW) / 2), recentY - 1, fg)
        index = index + 1
      end
    end
  else
    local index = 1
    while index <= recentCount do
      local number = recent[index]
      local bg = model.getNumberColor(number)
      local fg = model.getNumberTextColor(number)
      local slotX = recentX + ((index - 1) * (slotWidth + slotGap))
      screen:fillRect(slotX, recentY, slotWidth, 5, bg)
      local label = tostring(number)
      local labelW = ui.getTextSize(label)
      ui.safeDrawText(screen, label, font, slotX + floor((slotWidth - labelW) / 2), recentY - 1, fg)
      index = index + 1
    end

    ui.safeDrawText(screen, "RECENT", font, track.x + track.w - ui.getTextSize("RECENT") - 2, recentY, colors.lightGray)
  end

  local bandY = track.y + (layout.compact and 1 or 5)
  local bandH = track.h - (layout.compact and 2 or 6)
  screen:fillRect(bandX, bandY, max(1, bandW), bandH, colors.black)

  local pointerX = bandX + floor(max(1, bandW) / 2)
  screen:fillRect(pointerX, bandY, 1, bandH, colors.yellow)

  local cellW = track.cellW
  local wheelOffset = state.wheelOffset or 0
  local visible = floor(max(1, bandW) / cellW) + 4
  local baseIndex = floor(wheelOffset)
  local fraction = wheelOffset - baseIndex

  local offset = -visible
  while offset <= visible do
    local wheelIndex = ((baseIndex + offset) % #model.WHEEL_ORDER) + 1
    local number = model.WHEEL_ORDER[wheelIndex]
    local cellX = pointerX + floor((offset - fraction) * cellW) - floor(cellW / 2)
    if cellX < (track.x + track.w) and (cellX + cellW) > track.x then
      local bg = model.getNumberColor(number)
      local fg = model.getNumberTextColor(number)
      screen:fillRect(cellX, bandY, cellW, bandH, bg)
      local label = tostring(number)
      local labelW = ui.getTextSize(label)
      ui.safeDrawText(screen, label, font, cellX + floor((cellW - labelW) / 2), bandY - 1, fg)
    end
    offset = offset + 1
  end
end

local function drawSummaryBox(screen, font, layout, state)
  local box = layout.summaryBox
  drawFrame(screen, box, colors.gray, colors.yellow)

  local headline = "TABLE OPEN"
  if state.phase == "spinning" then
    headline = "SPINNING"
  elseif state.phase == "result" and state.resultNumber ~= nil then
    headline = tostring(state.resultNumber) .. " " .. model.getColorName(state.resultNumber)
  elseif state.autoPlay then
    headline = "AUTO PLAY"
  end
  ui.safeDrawText(screen, headline, font, box.x + 2, box.y + 2, colors.white)

  local exposure = state.maxExposure or 0
  if layout.compact then
    local riskText = "Risk " .. currency.formatTokens(exposure)
    drawCenteredText(screen, font, {
      x = box.x,
      y = box.y + 6,
      w = box.w,
      h = 7,
    }, riskText, colors.lightGray)
    return
  end

  ui.safeDrawText(screen, "Risk " .. currency.formatTokens(exposure), font, box.x + 2, box.y + 11, colors.lightGray)
end

local function drawButtons(screen, font, layout, state)
  local selectedChipIndex = state.selectedChipIndex or 1
  local denominations = state.denominations or {}

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
    rebet = (state.lastResolvedCount or 0) > 0 and (state.totalStake or 0) == 0,
    double = (state.totalStake or 0) > 0,
    quit = true,
  }

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
  drawFrame(screen, box, colors.gray, colors.yellow)

  local title = "BET SLIP"
  ui.safeDrawText(screen, title, font, box.x + 2, box.y + 2, colors.white)

  local linesY = box.y + 8
  local lineHeight = 8
  local shown = 0
  local bets = state.bets or {}
  local index = #bets

  while index >= 1 and shown < layout.maxSlipLines do
    local bet = bets[index]
    local stakeText = formatCompactAmount(bet.stake or 0)
    local line = stakeText .. "  " .. bet.label
    ui.safeDrawText(screen, line, font, box.x + 2, linesY + (shown * lineHeight), colors.lightGray)
    shown = shown + 1
    index = index - 1
  end

  if #bets == 0 then
    local fallback = state.lastResolvedCount and state.lastResolvedCount > 0 and "Tap PLAY AGAIN to replay and spin the last round." or "Tap the felt to place chips."
    ui.safeDrawText(screen, fallback, font, box.x + 2, linesY, colors.lightGray)
  elseif #bets > shown then
    ui.safeDrawText(screen, "+" .. tostring(#bets - shown) .. " more", font, box.x + 2, linesY + (shown * lineHeight), colors.lightGray)
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
  drawCenteredText(screen, font, region, region.displayText, textColor)
end

local function drawSecondaryRegion(screen, font, region, fill, textColor, hasBet, isHighlighted, compact)
  if region.drawStyle == "street" then
    local baseColor = hasBet and colors.orange or colors.green
    if isHighlighted then
      baseColor = colors.yellow
    end
    screen:fillRect(region.x, region.y, region.w, region.h, baseColor)
    if region.displayText ~= "" then
      drawCenteredText(screen, font, region, region.displayText, isHighlighted and colors.black or textColor, compact and -1 or 0)
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

  if compact then
    return
  end

  if region.drawStyle == "line" then
    screen:fillRect(region.x, region.y, region.w, region.h, colors.green)
  elseif region.drawStyle == "split" then
    if region.w <= 2 then
      screen:fillRect(region.x, region.y + 1, region.w, max(1, region.h - 2), colors.green)
    else
      screen:fillRect(region.x + 1, region.y, max(1, region.w - 2), region.h, colors.green)
    end
  elseif region.drawStyle == "corner" then
    screen:fillRect(region.x, region.y, region.w, region.h, colors.green)
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
