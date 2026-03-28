local ui = require("lib.ui")

local floor = math.floor
local max = math.max
local min = math.min

local M = {}

function M.drawCenteredLine(screen, font, text, y, color)
  local message = tostring(text or "")
  local width = ui.getTextSize(message)
  local x = floor((screen.width - width) / 2)
  ui.safeDrawText(screen, message, font, x, y, color or colors.white)
end

function M.showPagedLines(screen, font, scale, backgroundColor, pages, opts)
  local options = opts or {}
  local page = 1

  while true do
    local current = pages[page]
    screen:clear(backgroundColor)

    M.drawCenteredLine(screen, font, current.title, 1, options.titleColor or colors.yellow)
    M.drawCenteredLine(screen, font, "Page " .. page .. "/" .. #pages, 1 + scale.lineHeight, colors.lightGray)

    local contentY = 1 + (scale.lineHeight * 2) + 2
    local buttonY = options.buttonY or scale.footerButtonY
    local contentLines = #current.lines
    local availableHeight = buttonY - contentY - 2
    local lineSpacing = min(scale.lineHeight, floor(availableHeight / max(contentLines, 1)))
    local lineIndex = 0

    for _, line in ipairs(current.lines) do
      if line.text ~= "" then
        M.drawCenteredLine(screen, font, line.text, contentY + (lineIndex * lineSpacing), line.color)
      end
      lineIndex = lineIndex + 1
    end

    ui.clearButtons()
    local row = {}
    if page > 1 then
      row[#row + 1] = {
        text = "PREV",
        color = colors.lightGray,
        func = function()
          page = page - 1
        end,
      }
    end
    row[#row + 1] = {
      text = "BACK",
      color = colors.red,
      func = function()
        page = nil
      end,
    }
    if page < #pages then
      row[#row + 1] = {
        text = "NEXT",
        color = colors.lime,
        func = function()
          page = page + 1
        end,
      }
    end

    ui.layoutButtonGrid(screen, { row }, options.centerX or floor(screen.width / 2), buttonY, scale.buttonRowSpacing, scale.buttonColGap)
    screen:output()
    ui.waitForButton(0, 0)

    if not page then
      return
    end
  end
end

function M.showStatsScreen(screen, font, scale, backgroundColor, title, lines, opts)
  local options = opts or {}
  screen:clear(backgroundColor)
  M.drawCenteredLine(screen, font, title, 1, options.titleColor or colors.yellow)

  local y = 1 + scale.lineHeight + 2
  local spacing = min(scale.lineHeight, floor((screen.height - y - 10) / max(#lines, 1)))

  for _, line in ipairs(lines) do
    if line.spacer then
      y = y + (line.height or 2)
    else
      local text = line.text
      if not text then
        text = tostring(line.label or "") .. ": " .. tostring(line.value or "")
      end
      M.drawCenteredLine(screen, font, text, y, line.color or colors.white)
      y = y + spacing
    end
  end

  ui.clearButtons()
  ui.layoutButtonGrid(screen, {
    {
      {
        text = "BACK",
        color = colors.red,
        func = function() end,
      },
    },
  }, options.centerX or floor(screen.width / 2), options.buttonY or scale.footerButtonY, scale.buttonRowSpacing, scale.buttonColGap)
  screen:output()
  ui.waitForButton(0, 0)
end

return M
