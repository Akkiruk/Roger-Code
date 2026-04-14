local peripherals = require("lib.peripherals")
local monitorScale = require("lib.monitor_scale")

local floor = math.floor
local max = math.max
local min = math.min

local DEFAULT_PALETTE = {
  [colors.lightGray] = 0xc5c5c5,
  [colors.orange] = 0xf15c5c,
  [colors.gray] = 0x363636,
  [colors.green] = 0x044906,
}

local M = {}

local function centeredX(surfaceApi, font, width, textValue)
  local textWidth = surfaceApi.getTextSize(textValue, font)
  return floor((width - textWidth) / 2)
end

local function withMonitor(handle, fn)
  local previous = term.current()
  term.redirect(handle.monitor)
  local ok, result = pcall(fn)
  term.redirect(previous)
  if not ok then
    error(result)
  end
  return result
end

local function drawCenteredLine(handle, textValue, y, color)
  local text = tostring(textValue or "")
  local x = centeredX(handle.surface, handle.font, handle.width, text)
  handle.screen:drawText(text, handle.font, x, y, color or colors.white)
end

local function drawSignalBars(handle, y)
  local count = 5
  local barWidth = max(8, floor(handle.width * 0.08))
  local barHeight = max(3, floor(handle.scale.buttonHeight / 3))
  local gap = max(2, floor(handle.width * 0.015))
  local totalWidth = (count * barWidth) + ((count - 1) * gap)
  local startX = floor((handle.width - totalWidth) / 2)
  local active = (handle.frame % count) + 1

  for index = 1, count do
    local color = colors.gray
    if index == active then
      color = colors.lime
    elseif index < active then
      color = colors.yellow
    end
    handle.screen:fillRect(startX + ((index - 1) * (barWidth + gap)), y, barWidth, barHeight, color)
  end
end

local function stageTitle(state)
  if state.stage == "waiting_player" then
    return "WAITING FOR PLAYER"
  end
  if state.stage == "timed_out" then
    return "APPROVAL TIMED OUT"
  end
  if state.stage == "approved" then
    return "AUTHORIZATION ACCEPTED"
  end
  return "PAYMENT AUTH REQUIRED"
end

local function stageAccent(state)
  if state.stage == "waiting_player" then
    return "Step up to the cabinet to begin"
  end
  if state.stage == "timed_out" then
    return "Request expired before approval"
  end
  if state.stage == "approved" then
    return "Wallet link is ready"
  end
  return "Open chat and click APPROVE"
end

function M.create(opts)
  assert(type(opts) == "table", "create expects a table")
  assert(type(opts.monitorName) == "string", "monitorName is required")

  local handle = {}
  handle.monitor = peripherals.require(opts.monitorName, "monitor", "monitor")
  if type(handle.monitor.setTextScale) == "function" then
    handle.monitor.setTextScale(monitorScale.surfaceTextScale(opts.monitorTextScale))
  end

  handle.surface = dofile(opts.surfacePath or "surface")
  handle.font = handle.surface.loadFont(handle.surface.load(opts.fontPath or "font"))
  handle.width, handle.height = handle.monitor.getSize()
  handle.scale = monitorScale.forSurface(handle.width, handle.height)
  handle.screen = handle.surface.create(handle.width, handle.height)
  handle.frame = 0
  handle.title = tostring(opts.title or "CASINO")
  handle.computerId = tonumber(opts.computerId) or os.getComputerID()

  withMonitor(handle, function()
    local palette = opts.palette or DEFAULT_PALETTE
    for colorId, hexValue in pairs(palette) do
      term.setPaletteColor(colorId, hexValue)
    end
  end)

  return handle
end

function M.render(handle, state)
  assert(type(handle) == "table", "render expects a handle")
  assert(type(state) == "table", "render expects a state table")

  handle.frame = handle.frame + 1

  local accent = stageAccent(state)
  local titleY = handle.scale.titleY
  local subtitleY = handle.scale.subtitleY
  local barY = subtitleY + (handle.scale.lineHeight * 2)
  local bodyY = barY + handle.scale.sectionGap + max(4, floor(handle.scale.lineHeight / 2))
  local footerY = max(handle.scale.edgePad, handle.height - handle.scale.lineHeight - handle.scale.edgePad)
  local dots = string.rep(".", (handle.frame % 3) + 1)
  local remaining = tonumber(state.secondsRemaining)
  local playerName = tostring(state.playerName or "Detecting...")

  handle.screen:clear(colors.green)
  handle.screen:fillRect(0, 0, handle.width, max(10, handle.scale.lineHeight + 4), colors.black)
  handle.screen:fillRect(0, max(10, handle.scale.lineHeight + 4), handle.width, 1, colors.orange)

  drawCenteredLine(handle, handle.title, 1, colors.white)
  drawCenteredLine(handle, stageTitle(state), titleY, colors.yellow)
  drawCenteredLine(handle, accent, subtitleY, colors.lightBlue)
  drawSignalBars(handle, barY)
  drawCenteredLine(handle, "Player: " .. playerName, bodyY, colors.white)
  drawCenteredLine(handle, "Computer #" .. tostring(state.computerId or handle.computerId), bodyY + handle.scale.lineHeight + 1, colors.white)

  if state.stage == "waiting_player" then
    drawCenteredLine(handle, "Stand near the monitor" .. dots, bodyY + ((handle.scale.lineHeight + 1) * 2), colors.lightGray)
  elseif state.stage == "timed_out" then
    drawCenteredLine(handle, "Try the wager again to resend it.", bodyY + ((handle.scale.lineHeight + 1) * 2), colors.orange)
  elseif state.stage == "approved" then
    drawCenteredLine(handle, "Wallet access granted.", bodyY + ((handle.scale.lineHeight + 1) * 2), colors.lime)
  else
    drawCenteredLine(handle, "Approve the wallet prompt in chat.", bodyY + ((handle.scale.lineHeight + 1) * 2), colors.lightGray)
  end

  if remaining then
    drawCenteredLine(handle, tostring(max(0, remaining)) .. "s remaining", footerY, colors.orange)
  else
    drawCenteredLine(handle, "Authorization pending", footerY, colors.orange)
  end

  withMonitor(handle, function()
    handle.screen:output()
  end)
end

function M.close(handle)
  if type(handle) ~= "table" or not handle.monitor then
    return
  end

  withMonitor(handle, function()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
  end)
end

return M