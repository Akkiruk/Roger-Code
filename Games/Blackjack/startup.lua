local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local statsButton = nil

local function drawOverlay(env, screen)
  local scale = env.scale
  local logo = env.assets.logo
  if logo then
    screen:drawSurface(logo, 0, 0)
  end

  local buttonText = "STATISTICS"
  local textWidth = env.surface.getTextSize(buttonText, env.font)
  local buttonWidth = math.max(scale:buttonWidth(textWidth, scale:scaledX(18, 8, 24)), math.floor(env.width * (scale.compact and 0.42 or 0.34)))
  local buttonHeight = scale.buttonHeight + scale:scaledY(6, 2, 10)
  local buttonX = math.floor((env.width - buttonWidth) / 2)
  local buttonY = math.max(scale.edgePad, scale:bottom(buttonHeight, scale.edgePad * 2))

  screen:fillRect(buttonX, buttonY, buttonWidth, buttonHeight, colors.gray)
  screen:fillRect(buttonX + 2, buttonY + 2, buttonWidth - 4, buttonHeight - 4, colors.lime)
  ui.safeDrawText(
    screen,
    buttonText,
    env.font,
    buttonX + math.floor((buttonWidth - env.surface.getTextSize(buttonText, env.font)) / 2),
    buttonY + 5,
    colors.black
  )

  statsButton = {
    x = buttonX,
    y = buttonY,
    width = buttonWidth,
    height = buttonHeight,
  }
end

local function checkHit(x, y)
  if statsButton
    and x >= statsButton.x and x <= statsButton.x + statsButton.width
    and y >= statsButton.y and y <= statsButton.y + statsButton.height then
    return "statistics"
  end
  return nil
end

launcher.run({
  startupName = "Casino Startup",
  logFile = "debug.txt",
  monitorName = "right",
  programs = {
    play = "blackjack.lua",
    statistics = "statistics.lua",
  },
  drawOverlay = drawOverlay,
  checkHit = checkHit,
  extraAssets = {
    logo = "logo.nfp",
  },
})
