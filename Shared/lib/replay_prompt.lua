local ui = require("lib.ui")
local activityTimeout = require("lib.activity_timeout")

local M = {}
local chooseValue = nil

local function drawCenteredLine(screen, text, y, color)
  local font = ui.getFont()
  local message = tostring(text or "")
  local width = ui.getTextSize(message)
  local x = math.max(0, math.floor((screen.width - width) / 2))
  ui.safeDrawText(screen, message, font, x, y, color or colors.lightGray)
end

local function drawCenteredWrappedText(screen, text, y, color, maxLines)
  local font = ui.getFont()
  local metrics = ui.getMetrics()
  local maxWidth = math.max(1, screen.width - ((metrics.edgePad or 0) * 2))
  local lineSpacing = metrics.lineHeight or 1
  local lines = ui.wrapSurfaceText(text, font, maxWidth, maxLines)
  local startY = y - ((#lines - 1) * lineSpacing)

  for index, line in ipairs(lines) do
    drawCenteredLine(screen, line, startY + ((index - 1) * lineSpacing), color)
  end
end

local function resolveHint(options)
  if type(options.hint) == "function" then
    return options.hint()
  end

  if type(options.hint) == "table" then
    return options.hint.text, options.hint.color
  end

  return options.hint, options.hint_color
end

local function buildButtonRows(buttons, chooseValue, screen)
  local rows = {}

  for rowIndex, row in ipairs(buttons or {}) do
    rows[rowIndex] = {}
    for _, entry in ipairs(row or {}) do
      if entry then
        rows[rowIndex][#rows[rowIndex] + 1] = {
          text = entry.text,
          color = entry.color,
          width = entry.width,
          func = function()
            local enabled = true
            if type(entry.enabled) == "function" then
              enabled = entry.enabled()
            elseif entry.enabled ~= nil then
              enabled = entry.enabled == true
            end

            if enabled then
              if type(entry.onChoose) == "function" then
                entry.onChoose()
              end
              chooseValue(entry.id)
              return
            end

            if type(entry.onDisabled) == "function" then
              entry.onDisabled()
            end

            if entry.disabled_message then
              ui.displayCenteredMessage(
                screen,
                entry.disabled_message,
                entry.disabled_color or colors.orange,
                entry.disabled_pause or 1
              )
            end
          end,
        }
      end
    end
  end

  return rows
end

function M.waitForChoice(screen, opts)
  local options = opts or {}
  local choice = nil
  local timeoutState = options.timeout_state
  if (not timeoutState) and options.inactivity_timeout then
    timeoutState = activityTimeout.create(options.inactivity_timeout, {
      pollSeconds = options.poll_seconds,
    })
  end
  local pollSeconds = options.poll_seconds or (timeoutState and timeoutState.pollSeconds) or 0.25

  chooseValue = function(value)
    choice = value
  end

  while not choice do
    if type(options.render) == "function" then
      options.render()
    end

    local hintText, hintColor = resolveHint(options)
    if hintText and options.hint_y then
      drawCenteredWrappedText(screen, hintText, options.hint_y, hintColor or colors.lightGray, options.hint_max_lines or 3)
    end

    ui.clearButtons()
    ui.layoutButtonGrid(
      screen,
      buildButtonRows(options.buttons, chooseValue, screen),
      options.center_x,
      options.button_y,
      options.row_spacing,
      options.col_spacing
    )
    screen:output()

    if options.auto_choice then
      os.sleep(options.auto_delay or 0)
      ui.clearButtons()
      return options.auto_choice
    end

    local timerID = os.startTimer(pollSeconds)
    while not choice do
      local event, param1, param2, param3 = os.pullEvent()

      if event == "monitor_touch" then
        if ui.isAuthorizedMonitorTouch() then
          if timeoutState then
            timeoutState:touch()
          end
          local callback = ui.checkButtonHit(param2, param3)
          if callback then
            callback()
            break
          end
        else
          os.sleep(0)
        end
      elseif event == "timer" and param1 == timerID then
        if timeoutState and timeoutState:isExpired() then
          ui.clearButtons()
          if type(options.onTimeout) == "function" then
            return options.onTimeout()
          end
          return nil
        end
        break
      end
    end
  end

  ui.clearButtons()
  return choice
end

return M
