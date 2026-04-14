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

local function buildPagedLineScreens(screen, font, scale, pages, buttonY)
  local contentY = 1 + (scale.lineHeight * 2) + 2
  local availableHeight = max(1, buttonY - contentY - 2)
  local lineSpacing = max(1, scale.lineHeight)
  local maxLinesPerPage = max(1, floor(availableHeight / lineSpacing))
  local maxWidth = max(1, screen.width - ((scale.edgePad or 0) * 2))
  local displayPages = {}

  for _, sourcePage in ipairs(pages or {}) do
    local currentLines = {}
    local usedLines = 0
    local emitted = false

    local function flushPage()
      local lines = currentLines
      if #lines == 0 then
        lines = { { spacer = 1 } }
      end

      displayPages[#displayPages + 1] = {
        title = sourcePage.title,
        lines = lines,
      }

      currentLines = {}
      usedLines = 0
      emitted = true
    end

    local function pushEntry(entry)
      local needed = entry.spacer or 1
      if usedLines > 0 and (usedLines + needed) > maxLinesPerPage then
        flushPage()
      end

      if entry.spacer then
        if usedLines > 0 then
          currentLines[#currentLines + 1] = entry
          usedLines = usedLines + needed
        end
        return
      end

      currentLines[#currentLines + 1] = entry
      usedLines = usedLines + 1
    end

    for _, line in ipairs(sourcePage.lines or {}) do
      if line.spacer or line.text == "" then
        pushEntry({ spacer = line.height or 1 })
      else
        local wrapped = ui.wrapSurfaceText(line.text, font, maxWidth)
        for _, wrappedLine in ipairs(wrapped) do
          pushEntry({
            text = wrappedLine,
            color = line.color,
          })
        end
      end
    end

    if usedLines > 0 or not emitted then
      flushPage()
    end
  end

  return displayPages, contentY, lineSpacing
end

function M.showPagedLines(screen, font, scale, backgroundColor, pages, opts)
  local options = opts or {}
  local buttonY = options.buttonY or scale.footerButtonY
  local displayPages, contentY, lineSpacing = buildPagedLineScreens(screen, font, scale, pages, buttonY)
  local page = 1

  while true do
    local current = displayPages[page]
    screen:clear(backgroundColor)

    M.drawCenteredLine(screen, font, current.title, 1, options.titleColor or colors.yellow)
    M.drawCenteredLine(screen, font, "Page " .. page .. "/" .. #displayPages, 1 + scale.lineHeight, colors.lightGray)

    local y = contentY

    for _, line in ipairs(current.lines) do
      if line.spacer then
        y = y + (lineSpacing * line.spacer)
      elseif line.text ~= "" then
        M.drawCenteredLine(screen, font, line.text, y, line.color)
        y = y + lineSpacing
      end
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
    if page < #displayPages then
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
    ui.waitForButton(0, 0, {
      timeoutState = options.timeout_state,
      inactivityTimeout = options.inactivity_timeout,
      onTimeout = options.onTimeout,
    })

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
  local maxWidth = max(1, screen.width - ((scale.edgePad or 0) * 2))

  for _, line in ipairs(lines) do
    if line.spacer then
      y = y + (line.height or 2)
    else
      local text = line.text
      if not text then
        text = tostring(line.label or "") .. ": " .. tostring(line.value or "")
      end
      local wrapped = ui.wrapSurfaceText(text, font, maxWidth)
      for _, wrappedLine in ipairs(wrapped) do
        M.drawCenteredLine(screen, font, wrappedLine, y, line.color or colors.white)
        y = y + spacing
      end
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
  ui.waitForButton(0, 0, {
    timeoutState = options.timeout_state,
    inactivityTimeout = options.inactivity_timeout,
    onTimeout = options.onTimeout,
  })
end

return M
