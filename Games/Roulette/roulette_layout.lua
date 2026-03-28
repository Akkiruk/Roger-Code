local cfg = require("roulette_config")
local model = require("roulette_model")
local monitorScale = require("lib.monitor_scale")

local floor = math.floor
local insert = table.insert
local max = math.max
local min = math.min

local function attachRect(region, x, y, width, height, fillColor, textColor, displayText, drawStyle)
  region.x = x
  region.y = y
  region.w = width
  region.h = height
  region.cx = x + floor(width / 2)
  region.cy = y + floor(height / 2)
  region.fillColor = fillColor
  region.textColor = textColor or colors.white
  region.displayText = displayText or region.label
  region.drawStyle = drawStyle or region.kind
  return region
end

local function appendRegion(regions, hitRegions, region)
  insert(regions, region)
  insert(hitRegions, region)
end

local function makeActionButton(key, label, x, y, width, height, color)
  return {
    key = key,
    label = label,
    x = x,
    y = y,
    w = width,
    h = height,
    cx = x + floor(width / 2),
    cy = y + floor(height / 2),
    color = color,
  }
end

local function buildRangeNumbers(startValue, endValue, step)
  local numbers = {}
  local value = startValue
  step = step or 1
  while value <= endValue do
    insert(numbers, value)
    value = value + step
  end
  return numbers
end

local function getShortOutsideText(key)
  if key == "column:1" then
    return "C1"
  elseif key == "column:2" then
    return "C2"
  elseif key == "column:3" then
    return "C3"
  elseif key == "dozen:1" then
    return "D1"
  elseif key == "dozen:2" then
    return "D2"
  elseif key == "dozen:3" then
    return "D3"
  elseif key == "low" then
    return "1-18"
  elseif key == "even" then
    return "EV"
  elseif key == "red" then
    return "RED"
  elseif key == "black" then
    return "BLK"
  elseif key == "odd" then
    return "ODD"
  elseif key == "high" then
    return "19+"
  end
  return nil
end

local function getTableContentHeight(cellHeight, rowGap, outsideHeight)
  local zeroHeight = cellHeight + 1
  outsideHeight = outsideHeight or (cellHeight + 1)
  return zeroHeight
    + 1
    + (12 * cellHeight)
    + (11 * rowGap)
    + 1
    + outsideHeight
    + 1
    + outsideHeight
    + 1
    + outsideHeight
    + 1
    + outsideHeight
end

local function build(width, height, chipCount, scale)
  chipCount = chipCount or 4
  scale = scale or monitorScale.forSurface(width, height)

  local layout = {
    width = width,
    height = height,
    margin = scale.edgePad,
    header = { x = 0, y = 0, w = width, h = scale:scaledY(24, 18, 28) },
    regions = {},
    hitRegions = {},
    scale = scale,
  }

  layout.compact = scale.compact or width < 200 or height < 120

  if layout.compact then
    layout.header.h = max(scale:scaledY(16, 13, 19), scale.lineHeight + scale.smallGap + 4)
  end

  local trackY = layout.header.h + scale.sectionGap
  local trackH = layout.compact and scale:scaledY(18, 17, 20) or scale:scaledY(22, 19, 26)
  local feltX = layout.margin
  local feltW = width - (layout.margin * 2)
  local feltY = trackY + trackH + scale.sectionGap
  local feltH = height - feltY - layout.margin

  local colGap = layout.compact and 1 or scale.smallGap
  local rowGap = layout.compact and 1 or scale.smallGap
  local streetW = max(4, scale:scaledX(layout.compact and 4 or 6, 4, layout.compact and 6 or 9))
  local maxCellW = max(10, scale:scaledX(layout.compact and 12 or 28, 10, layout.compact and 18 or 32))
  local buttonGap = scale.buttonRowGap
  local buttonH = scale.buttonHeight
  local summaryH = layout.compact and scale:scaledY(18, 15, 20) or scale:scaledY(24, 22, 28)
  local contentAreaX = feltX + scale.sectionGap
  local contentAreaW = feltW - (scale.sectionGap * 2)

  layout.track = {
    x = feltX,
    y = trackY,
    w = feltW,
    h = trackH,
    cellW = max(5, min(11, floor(feltW / 12))),
  }
  layout.felt = { x = feltX, y = feltY, w = feltW, h = feltH }
  layout.panelLabelH = layout.compact and 0 or 7
  layout.rightRail = nil
  layout.chipPanel = nil
  layout.actionPanel = nil
  layout.wideControls = false
  layout.chipButtons = {}
  layout.actionButtons = {}
  local contentAreaY = feltY + 1
  local contentAreaH = feltH - 2

  if layout.compact then
    local panelW = max(18, min(22, floor(feltW * 0.20)))
    local panelX = feltX
    local panelY = feltY
    local panelH = feltH
    local panelInnerX = panelX + 1
    local panelInnerW = panelW - 2
    local gridButtonW = max(5, floor((panelInnerW - buttonGap) / 2))
    local tableX = panelX + panelW + scale.sectionGap
    local tableW = feltW - panelW - scale.sectionGap

    layout.panel = { x = panelX, y = panelY, w = panelW, h = panelH }
    layout.summaryBox = { x = panelX, y = panelY, w = panelW, h = summaryH }
    layout.ultraCompact = width < 72 or panelW <= 18 or gridButtonW <= 9

    local chipsStartY = panelY + summaryH + scale.sectionGap + layout.panelLabelH
    local chipIndex = 1
    local chipRow = 0
    while chipIndex <= chipCount do
      local baseY = chipsStartY + (chipRow * (buttonH + buttonGap))
      insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", panelInnerX, baseY, gridButtonW, buttonH, colors.gray))
      chipIndex = chipIndex + 1
      if chipIndex <= chipCount then
        insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", panelInnerX + gridButtonW + buttonGap, baseY, gridButtonW, buttonH, colors.gray))
        chipIndex = chipIndex + 1
      end
      chipRow = chipRow + 1
    end

    local actionsStartY = chipsStartY + (chipRow * (buttonH + buttonGap)) + scale.smallGap + layout.panelLabelH
    local spinLabel = layout.ultraCompact and "GO" or "SPIN"
    local undoLabel = layout.ultraCompact and "UND" or "UNDO"
    local clearLabel = layout.compact and "CLR" or "CLEAR"
    local doubleLabel = layout.compact and "X2" or "DOUBLE"
    layout.actionButtons = {
      makeActionButton("spin", spinLabel, panelInnerX, actionsStartY, gridButtonW, buttonH, colors.lime),
      makeActionButton("undo", undoLabel, panelInnerX + gridButtonW + buttonGap, actionsStartY, gridButtonW, buttonH, colors.orange),
      makeActionButton("clear", clearLabel, panelInnerX, actionsStartY + buttonH + buttonGap, gridButtonW, buttonH, colors.red),
      makeActionButton("double", doubleLabel, panelInnerX + gridButtonW + buttonGap, actionsStartY + buttonH + buttonGap, gridButtonW, buttonH, colors.magenta),
      makeActionButton("quit", "EXIT", panelInnerX, actionsStartY + (buttonH + buttonGap) * 2, (gridButtonW * 2) + buttonGap, buttonH, colors.gray),
    }

    local slipY = actionsStartY + ((buttonH + buttonGap) * 3) + scale.sectionGap + layout.panelLabelH
    layout.slipBox = {
      x = panelX,
      y = slipY,
      w = panelW,
      h = 0,
    }
    contentAreaX = tableX + scale.sectionGap
    contentAreaW = tableW - (scale.sectionGap * 2)
    contentAreaY = feltY + 1
    contentAreaH = feltH - 2
  else
    local railInset = 2
    local innerX = feltX + railInset
    local innerY = feltY + railInset
    local innerW = feltW - (railInset * 2)
    local innerH = feltH - (railInset * 2)
    local railGap = max(2, scale.sectionGap - 1)
    local leftRailW = max(30, min(38, floor(innerW * 0.23)))
    local rightRailW = max(28, min(36, floor(innerW * 0.20)))
    local minTableW = 54
    local availableRailW = innerW - minTableW - (railGap * 2)
    local overflow = max(0, (leftRailW + rightRailW) - availableRailW)

    if overflow > 0 then
      local leftTrim = min(max(0, leftRailW - 28), floor((overflow + 1) / 2))
      leftRailW = leftRailW - leftTrim
      overflow = overflow - leftTrim
      rightRailW = max(26, rightRailW - overflow)
    end

    local leftRailX = innerX
    local rightRailX = innerX + innerW - rightRailW
    local leftInnerX = leftRailX + 1
    local leftInnerW = leftRailW - 2
    local chipButtonW = max(8, floor((leftInnerW - buttonGap) / 2))

    layout.panel = { x = leftRailX, y = innerY, w = leftRailW, h = innerH }
    layout.rightRail = { x = rightRailX, y = innerY, w = rightRailW, h = innerH }
    layout.summaryBox = { x = leftRailX, y = innerY, w = leftRailW, h = summaryH }
    layout.ultraCompact = false

    local chipsStartY = innerY + summaryH + scale.sectionGap + layout.panelLabelH + 3
    local chipIndex = 1
    local chipRow = 0
    while chipIndex <= chipCount do
      local baseY = chipsStartY + (chipRow * (buttonH + buttonGap))
      insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", leftInnerX, baseY, chipButtonW, buttonH, colors.gray))
      chipIndex = chipIndex + 1
      if chipIndex <= chipCount then
        insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", leftInnerX + chipButtonW + buttonGap, baseY, chipButtonW, buttonH, colors.gray))
        chipIndex = chipIndex + 1
      end
      chipRow = chipRow + 1
    end

    local slipY = chipsStartY + (chipRow * (buttonH + buttonGap)) + scale.sectionGap + layout.panelLabelH
    layout.slipBox = {
      x = leftRailX,
      y = slipY,
      w = leftRailW,
      h = 0,
    }

    local actionsStartY = innerY + layout.panelLabelH + 2
    local actionIndex = 1
    local actionKeys = {
      { key = "spin", label = "SPIN", color = colors.lime },
      { key = "undo", label = "UNDO", color = colors.orange },
      { key = "clear", label = "CLEAR", color = colors.red },
      { key = "double", label = "DOUBLE", color = colors.magenta },
      { key = "quit", label = "EXIT", color = colors.gray },
    }
    while actionIndex <= #actionKeys do
      local action = actionKeys[actionIndex]
      insert(layout.actionButtons, makeActionButton(
        action.key,
        action.label,
        rightRailX,
        actionsStartY + ((actionIndex - 1) * (buttonH + buttonGap)),
        rightRailW,
        buttonH,
        action.color
      ))
      actionIndex = actionIndex + 1
    end

    contentAreaX = leftRailX + leftRailW + railGap
    contentAreaW = rightRailX - contentAreaX - railGap
    contentAreaY = innerY
    contentAreaH = innerH
  end

  local gridBodyW = contentAreaW
  local baseCellH = floor((max(8, contentAreaH - (rowGap * 11) - 12) / 17))
  local cellW = max(8, min(maxCellW, floor((gridBodyW - streetW - (colGap * 2)) / 3)))
  if layout.compact then
    cellW = max(9, min(maxCellW, floor((gridBodyW - streetW - (colGap * 2)) / 3)))
  end
  local cellH = layout.compact and scale:scaledY(5, 4, 6) or max(scale:scaledY(7, 6, 8), min(11, baseCellH))
  if not layout.compact then
    streetW = max(7, min(10, floor(cellW * 0.38)))
    cellW = max(11, min(maxCellW, floor((gridBodyW - streetW - (colGap * 2)) / 3)))
  end
  local minCellHeight = layout.compact and 3 or 4
  while cellH > minCellHeight and getTableContentHeight(cellH, rowGap) > max(8, contentAreaH - 2) do
    cellH = cellH - 1
  end

  local zeroH = cellH + 1
  local outsideH = cellH + 1
  if not layout.compact then
    local baseContentH = getTableContentHeight(cellH, rowGap, outsideH)
    local extraOutsideHeight = floor(max(0, max(8, contentAreaH - 2) - baseContentH) / 4)
    outsideH = min(14, outsideH + extraOutsideHeight)
  end
  local zeroW = (cellW * 3) + (colGap * 2)
  local totalContentW = zeroW + 1 + streetW
  local contentH = getTableContentHeight(cellH, rowGap, outsideH)
  local contentX = contentAreaX + max(1, floor((contentAreaW - totalContentW) / 2))
  local contentY = contentAreaY + max(1, floor((contentAreaH - contentH) / 2))
  local streetX = contentX + zeroW + 1

  local colX = {
    contentX,
    contentX + cellW + colGap,
    contentX + ((cellW + colGap) * 2),
  }

  layout.table = {
    x = contentX,
    y = contentY,
    zeroX = contentX,
    zeroY = contentY,
    zeroW = zeroW,
    zeroH = zeroH,
    cellW = cellW,
    cellH = cellH,
    colGap = colGap,
    rowGap = rowGap,
    streetX = streetX,
    streetW = streetW,
    gridY = contentY + zeroH + 1,
    columnsY = contentY + zeroH + 1 + (12 * cellH) + (11 * rowGap) + 1,
    colX = colX,
  }
  layout.table.dozensY = layout.table.columnsY + outsideH + 1
  layout.table.evenTopY = layout.table.dozensY + outsideH + 1
  layout.table.evenBottomY = layout.table.evenTopY + outsideH + 1

  local zeroRegion = model.makeBetDefinition("straight:0", "straight", "0", 35, { 0 }, colors.lime)
  attachRect(zeroRegion, contentX, contentY, zeroW, zeroH, colors.lime, colors.black, "0", "zero")
  insert(layout.regions, zeroRegion)
  insert(layout.hitRegions, zeroRegion)

  local row = 1
  while row <= 12 do
    local rowY = layout.table.gridY + ((row - 1) * (cellH + rowGap))
    local rowNumbers = model.getRowNumbers(row)

    local streetRegion = model.makeBetDefinition(
      "street:" .. tostring(row),
      "street",
      "Street " .. rowNumbers[1] .. "-" .. rowNumbers[3],
      11,
      rowNumbers,
      colors.orange
      )
    attachRect(streetRegion, streetX, rowY, streetW, cellH, colors.orange, colors.black, layout.compact and "S" or "ST", "street")
    insert(layout.regions, streetRegion)
    insert(layout.hitRegions, streetRegion)

    if row < 12 then
      local nextRowNumbers = model.getRowNumbers(row + 1)
      local lineNumbers = {}
      for _, number in ipairs(rowNumbers) do
        insert(lineNumbers, number)
      end
      for _, number in ipairs(nextRowNumbers) do
        insert(lineNumbers, number)
      end

      local lineRegion = model.makeBetDefinition(
        "line:" .. tostring(row),
        "line",
        "Line " .. rowNumbers[1] .. "-" .. nextRowNumbers[3],
        5,
        lineNumbers,
        colors.yellow
      )
      attachRect(lineRegion, streetX, rowY + cellH - 1, streetW, rowGap + 2, colors.yellow, colors.black, layout.compact and "L" or "LN", "line")
      insert(layout.regions, lineRegion)
      insert(layout.hitRegions, lineRegion)
    end

    local column = 1
    while column <= 3 do
      local number = model.getNumberAt(row, column)
      local cellX = colX[column]

      local straightRegion = model.makeBetDefinition(
        "straight:" .. tostring(number),
        "straight",
        tostring(number),
        35,
        { number },
        model.getNumberColor(number)
      )
      attachRect(
        straightRegion,
        cellX,
        rowY,
        cellW,
        cellH,
        model.getNumberColor(number),
        model.getNumberTextColor(number),
        tostring(number),
        "straight"
      )
      insert(layout.regions, straightRegion)

      if column < 3 then
        local nextNumber = model.getNumberAt(row, column + 1)
        local splitRegion = model.makeBetDefinition(
          "split:" .. tostring(number) .. "-" .. tostring(nextNumber),
          "split",
          tostring(number) .. "/" .. tostring(nextNumber),
          17,
          { number, nextNumber },
          colors.yellow
        )
        attachRect(splitRegion, cellX + cellW - 1, rowY, colGap + 2, cellH, colors.yellow, colors.black, "", "split")
        insert(layout.regions, splitRegion)
        insert(layout.hitRegions, splitRegion)
      end

      if row < 12 then
        local belowNumber = model.getNumberAt(row + 1, column)
        local verticalSplit = model.makeBetDefinition(
          "split:" .. tostring(number) .. "-" .. tostring(belowNumber),
          "split",
          tostring(number) .. "/" .. tostring(belowNumber),
          17,
          { number, belowNumber },
          colors.yellow
        )
        attachRect(verticalSplit, cellX, rowY + cellH - 1, cellW, rowGap + 2, colors.yellow, colors.black, "", "split")
        insert(layout.regions, verticalSplit)
        insert(layout.hitRegions, verticalSplit)
      end

      if row < 12 and column < 3 then
        local rightNumber = model.getNumberAt(row, column + 1)
        local belowLeft = model.getNumberAt(row + 1, column)
        local belowRight = model.getNumberAt(row + 1, column + 1)
        local cornerRegion = model.makeBetDefinition(
          "corner:" .. tostring(number) .. "-" .. tostring(rightNumber) .. "-" .. tostring(belowLeft) .. "-" .. tostring(belowRight),
          "corner",
          tostring(number) .. "/" .. tostring(rightNumber) .. "/" .. tostring(belowLeft) .. "/" .. tostring(belowRight),
          8,
          { number, rightNumber, belowLeft, belowRight },
          colors.magenta
        )
        attachRect(cornerRegion, cellX + cellW - 1, rowY + cellH - 1, colGap + 2, rowGap + 2, colors.magenta, colors.white, "", "corner")
        insert(layout.regions, cornerRegion)
        insert(layout.hitRegions, cornerRegion)
      end

      column = column + 1
    end

    row = row + 1
  end

  local function addOutsideRegion(key, kind, label, payout, numbers, x, y, width, height, fillColor, textColor, displayText, drawStyle)
    local region = model.makeBetDefinition(key, kind, label, payout, numbers, fillColor)
    attachRect(region, x, y, width, height, fillColor, textColor, displayText, drawStyle)
    appendRegion(layout.regions, layout.hitRegions, region)
  end

  addOutsideRegion("column:1", "column", "Column 1", 2, model.getColumnNumbers(1), colX[1], layout.table.columnsY, cellW, outsideH, colors.cyan, colors.black, layout.compact and getShortOutsideText("column:1") or "COL 1", "outside")
  addOutsideRegion("column:2", "column", "Column 2", 2, model.getColumnNumbers(2), colX[2], layout.table.columnsY, cellW, outsideH, colors.cyan, colors.black, layout.compact and getShortOutsideText("column:2") or "COL 2", "outside")
  addOutsideRegion("column:3", "column", "Column 3", 2, model.getColumnNumbers(3), colX[3], layout.table.columnsY, cellW, outsideH, colors.cyan, colors.black, layout.compact and getShortOutsideText("column:3") or "COL 3", "outside")

  addOutsideRegion("dozen:1", "dozen", "1st 12", 2, model.getDozenNumbers(1), colX[1], layout.table.dozensY, cellW, outsideH, colors.lightBlue, colors.black, layout.compact and getShortOutsideText("dozen:1") or "1ST 12", "outside")
  addOutsideRegion("dozen:2", "dozen", "2nd 12", 2, model.getDozenNumbers(2), colX[2], layout.table.dozensY, cellW, outsideH, colors.lightBlue, colors.black, layout.compact and getShortOutsideText("dozen:2") or "2ND 12", "outside")
  addOutsideRegion("dozen:3", "dozen", "3rd 12", 2, model.getDozenNumbers(3), colX[3], layout.table.dozensY, cellW, outsideH, colors.lightBlue, colors.black, layout.compact and getShortOutsideText("dozen:3") or "3RD 12", "outside")

  addOutsideRegion("low", "low", "1-18", 1, buildRangeNumbers(1, 18), colX[1], layout.table.evenTopY, cellW, outsideH, colors.brown, colors.white, layout.compact and getShortOutsideText("low") or "1-18", "outside")
  addOutsideRegion("even", "even", "Even", 1, buildRangeNumbers(2, 36, 2), colX[2], layout.table.evenTopY, cellW, outsideH, colors.gray, colors.white, layout.compact and getShortOutsideText("even") or "EVEN", "outside")
  addOutsideRegion("red", "red", "Red", 1, cfg.RED_NUMBERS, colX[3], layout.table.evenTopY, cellW, outsideH, colors.red, colors.white, layout.compact and getShortOutsideText("red") or "RED", "outside")

  local blackNumbers = {}
  local value = 1
  while value <= 36 do
    if model.isBlack(value) then
      insert(blackNumbers, value)
    end
    value = value + 1
  end
  addOutsideRegion("black", "black", "Black", 1, blackNumbers, colX[1], layout.table.evenBottomY, cellW, outsideH, colors.black, colors.white, layout.compact and getShortOutsideText("black") or "BLACK", "outside")

  local oddNumbers = buildRangeNumbers(1, 35, 2)
  addOutsideRegion("odd", "odd", "Odd", 1, oddNumbers, colX[2], layout.table.evenBottomY, cellW, outsideH, colors.gray, colors.white, layout.compact and getShortOutsideText("odd") or "ODD", "outside")

  local highNumbers = buildRangeNumbers(19, 36)
  addOutsideRegion("high", "high", "19-36", 1, highNumbers, colX[3], layout.table.evenBottomY, cellW, outsideH, colors.brown, colors.white, layout.compact and getShortOutsideText("high") or "19-36", "outside")

  for index = #layout.regions, 1, -1 do
    local region = layout.regions[index]
    if region.kind == "straight" then
      insert(layout.hitRegions, region)
    end
  end

  layout.regionByKey = {}
  for _, region in ipairs(layout.regions) do
    layout.regionByKey[region.key] = region
  end

  layout.maxSlipLines = max(2, floor((layout.slipBox.h - 10) / scale.lineHeight))
  layout.tableArea = {
    x = contentAreaX,
    y = contentAreaY,
    w = contentAreaW,
    h = contentAreaH,
  }

  return layout
end

return {
  build = build,
}
