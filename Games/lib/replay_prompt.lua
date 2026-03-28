local currency = require("lib.currency")
local ui = require("lib.ui")

local M = {}

local function isAuthorizedTouch()
  local sessionPlayer = currency.getAuthenticatedPlayerName and currency.getAuthenticatedPlayerName() or nil
  if not sessionPlayer or sessionPlayer == "" then
    return true
  end

  local currentPlayer = nil
  if currency.getLivePlayerName then
    currentPlayer = currency.getLivePlayerName()
  end
  if (not currentPlayer or currentPlayer == "") and currency.getSessionInfo then
    local info = currency.getSessionInfo()
    currentPlayer = info and info.playerName or nil
  end

  return (not currentPlayer) or currentPlayer == sessionPlayer
end

local function drawCenteredLine(screen, text, y, color)
  local font = ui.getFont()
  local message = tostring(text or "")
  local width = ui.getTextSize(message)
  local x = math.max(0, math.floor((screen.width - width) / 2))
  ui.safeDrawText(screen, message, font, x, y, color or colors.lightGray)
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

local function buildButtonRows(buttons, setChoice, screen)
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
              setChoice(entry.id)
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
  local lastActivityTime = os.epoch("local")
  local pollSeconds = options.poll_seconds or 0.25

  local function setChoice(value)
    choice = value
  end

  while not choice do
    if type(options.render) == "function" then
      options.render()
    end

    local hintText, hintColor = resolveHint(options)
    if hintText and options.hint_y then
      drawCenteredLine(screen, hintText, options.hint_y, hintColor or colors.lightGray)
    end

    ui.clearButtons()
    ui.layoutButtonGrid(
      screen,
      buildButtonRows(options.buttons, setChoice, screen),
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
        if isAuthorizedTouch() then
          lastActivityTime = os.epoch("local")
          local callback = ui.checkButtonHit(param2, param3)
          if callback then
            callback()
            break
          end
        else
          os.sleep(0)
        end
      elseif event == "timer" and param1 == timerID then
        if options.inactivity_timeout and (os.epoch("local") - lastActivityTime) > options.inactivity_timeout then
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
