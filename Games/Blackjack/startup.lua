local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")
local cfg = require("blackjack_config")

local statsButton = nil
local max = math.max
local floor = math.floor

local HOUSE_RULE_LINES = {
  "HOUSE RULES",
  "Dealer draws to " .. tostring(cfg.DEALER_STAND) .. ".",
  "Blackjack pays 6:5.",
  "Double on hard 10-11 only.",
  "No splits. No insurance.",
}

local function drawOverlay(env, screen)
  local scale = env.scale
  local logo = env.assets.logo
  if logo then
    local logoX = max(0, floor((env.width - logo.width) / 2))
    screen:drawSurface(logo, logoX, 0)
  end

  local ruleTop = (logo and (logo.height + scale.edgePad + scale.smallGap)) or scale.titleY
  local panelWidth = max(floor(env.width * 0.62), scale:scaledX(90, 72, 120))
  local lineHeight = scale.lineHeight
  local panelHeight = (lineHeight * #HOUSE_RULE_LINES) + (scale.smallGap * 2)
  local panelX = floor((env.width - panelWidth) / 2)
  local panelY = ruleTop

  screen:fillRect(panelX, panelY, panelWidth, panelHeight, colors.gray)
  screen:fillRect(panelX + 1, panelY + 1, panelWidth - 2, panelHeight - 2, colors.black)

  for index, line in ipairs(HOUSE_RULE_LINES) do
    local textColor = (index == 1) and colors.yellow or colors.white
    local textWidth = env.surface.getTextSize(line, env.font)
    local textX = panelX + floor((panelWidth - textWidth) / 2)
    local textY = panelY + scale.smallGap + ((index - 1) * lineHeight)
    ui.safeDrawText(screen, line, env.font, textX, textY, textColor)
  end

  local buttonText = "STATISTICS"
  local textWidth = env.surface.getTextSize(buttonText, env.font)
  local buttonWidth = max(scale:buttonWidth(textWidth, scale:scaledX(18, 8, 24)), floor(env.width * (scale.compact and 0.42 or 0.34)))
  local buttonHeight = scale.buttonHeight + scale:scaledY(6, 2, 10)
  local buttonX = floor((env.width - buttonWidth) / 2)
  local buttonY = max(scale.edgePad, scale:bottom(buttonHeight, scale.edgePad * 2))

  screen:fillRect(buttonX, buttonY, buttonWidth, buttonHeight, colors.gray)
  screen:fillRect(buttonX + 2, buttonY + 2, buttonWidth - 4, buttonHeight - 4, colors.lime)
  ui.safeDrawText(
    screen,
    buttonText,
    env.font,
    buttonX + floor((buttonWidth - env.surface.getTextSize(buttonText, env.font)) / 2),
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
  cardAnimation = "random",
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
