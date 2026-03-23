local cfg = require("roulette_config")
local model = require("roulette_model")

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

local function getTableContentHeight(cellHeight, rowGap)
  local zeroHeight = cellHeight + 1
  local outsideHeight = cellHeight + 1
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

local function build(width, height, chipCount)
  chipCount = chipCount or 4

  local layout = {
    width = width,
    height = height,
    margin = 2,
    header = { x = 0, y = 0, w = width, h = 22 },
    regions = {},
    hitRegions = {},
  }

  layout.compact = width < 200 or height < 120

  if layout.compact then
    layout.header.h = 15
  end

  local panelWidth = max(24, min(36, floor(width * 0.30)))
  if layout.compact then
    panelWidth = max(18, min(22, floor(width * 0.20)))
  elseif (width - panelWidth) < 54 then
    panelWidth = max(22, width - 54)
  end

  local panelX = layout.margin
  local panelY = layout.header.h + 2
  local panelH = height - panelY - layout.margin
  local panelW = panelWidth

  local rightX = panelX + panelW + 2
  local rightW = width - rightX - layout.margin
  local trackY = panelY
  local trackH = (height >= 80) and 11 or 9
  if layout.compact then
    trackH = 7
  end
  local feltY = trackY + trackH + 2
  local feltH = height - feltY - layout.margin

  layout.panel = { x = panelX, y = panelY, w = panelW, h = panelH }
  layout.track = {
    x = rightX,
    y = trackY,
    w = rightW,
    h = trackH,
    cellW = max(4, min(7, floor(rightW / 13))),
  }
  layout.felt = { x = rightX, y = feltY, w = rightW, h = feltH }

  local summaryH = layout.compact and 16 or 24
  local buttonGap = 1
  local buttonH = 7
  local panelInnerX = panelX + 1
  local panelInnerW = panelW - 2
  local gridButtonW = floor((panelInnerW - buttonGap) / 2)

  layout.summaryBox = { x = panelX, y = panelY, w = panelW, h = summaryH }

  local chipsStartY = panelY + summaryH + 2
  layout.chipButtons = {}
  local chipIndex = 1
  local chipRow = 0
  while chipIndex <= chipCount do
    local baseY = chipsStartY + (chipRow * (buttonH + buttonGap))
    local leftX = panelInnerX
    local rightButtonX = panelInnerX + gridButtonW + buttonGap
    insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", leftX, baseY, gridButtonW, buttonH, colors.gray))
    chipIndex = chipIndex + 1
    if chipIndex <= chipCount then
      insert(layout.chipButtons, makeActionButton("chip:" .. tostring(chipIndex), "", rightButtonX, baseY, gridButtonW, buttonH, colors.gray))
      chipIndex = chipIndex + 1
    end
    chipRow = chipRow + 1
  end

  local actionsStartY = chipsStartY + (chipRow * (buttonH + buttonGap)) + (layout.compact and 1 or 2)
  layout.actionButtons = {
    makeActionButton("spin", "SPIN", panelInnerX, actionsStartY, gridButtonW, buttonH, colors.lime),
    makeActionButton("undo", "UNDO", panelInnerX + gridButtonW + buttonGap, actionsStartY, gridButtonW, buttonH, colors.orange),
    makeActionButton("clear", layout.compact and "CLR" or "CLEAR", panelInnerX, actionsStartY + buttonH + buttonGap, gridButtonW, buttonH, colors.red),
    makeActionButton("rebet", layout.compact and "RE" or "REBET", panelInnerX + gridButtonW + buttonGap, actionsStartY + buttonH + buttonGap, gridButtonW, buttonH, colors.cyan),
    makeActionButton("double", "DOUBLE", panelInnerX, actionsStartY + (buttonH + buttonGap) * 2, gridButtonW, buttonH, colors.magenta),
    makeActionButton("quit", layout.compact and "OUT" or "QUIT", panelInnerX + gridButtonW + buttonGap, actionsStartY + (buttonH + buttonGap) * 2, gridButtonW, buttonH, colors.gray),
  }
  if layout.compact then
    layout.actionButtons[5].label = "X2"
  end

  local slipY = actionsStartY + ((buttonH + buttonGap) * 3) + 2
  layout.slipBox = {
    x = panelX,
    y = slipY,
    w = panelW,
    h = max(14, panelY + panelH - slipY),
  }
  if layout.compact then
    layout.slipBox.h = 0
  end

  local colGap = 1
  local rowGap = 1
  local streetW = layout.compact and 4 or 6
  local gridBodyW = rightW - 6
  local cellW = max(8, floor((gridBodyW - streetW - (colGap * 2)) / 3))
  if layout.compact then
    cellW = max(9, floor((gridBodyW - streetW - (colGap * 2)) / 3))
  end
  local cellH = layout.compact and 5 or 7
  local minCellHeight = layout.compact and 3 or 4
  while cellH > minCellHeight and getTableContentHeight(cellH, rowGap) > (feltH - 4) do
    cellH = cellH - 1
  end

  local zeroH = cellH + 1
  local outsideH = cellH + 1
  local zeroW = (cellW * 3) + (colGap * 2)
  local totalContentW = zeroW + 1 + streetW
  local contentH = getTableContentHeight(cellH, rowGap)
  local contentX = rightX + max(1, floor((rightW - totalContentW) / 2))
  local contentY = feltY + max(1, floor((feltH - contentH) / 2))
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

  layout.maxSlipLines = max(2, floor((layout.slipBox.h - 10) / 8))

  return layout
end

return {
  build = build,
}
