local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")
local cfg = require("blackjack_config")

local HOUSE_RULE_LINES = {
  "HOUSE RULES",
  "Dealer draws to " .. tostring(cfg.DEALER_STAND) .. ".",
  "Dealer hits losing " .. tostring(cfg.DEALER_CHASE_TOTAL) .. "s.",
  "Blackjack pays 6:5.",
  "Double on hard 10-11 only.",
  "Max bet 500 tokens.",
  "No splits. No insurance.",
}

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "BLACKJACK"
  local titleWidth = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - titleWidth) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch to play"
  local subtitleWidth = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - subtitleWidth) / 2), scale.idleSubtitleY, colors.white)

  local lineHeight = scale.lineHeight
  local panelWidth = math.max(math.floor(env.width * 0.62), scale:scaledX(90, 72, 120))
  local panelHeight = (lineHeight * #HOUSE_RULE_LINES) + (scale.smallGap * 2)
  local panelX = math.floor((env.width - panelWidth) / 2)
  local panelY = scale.idleSubtitleY + (lineHeight * 2)

  screen:fillRect(panelX, panelY, panelWidth, panelHeight, colors.gray)
  screen:fillRect(panelX + 1, panelY + 1, panelWidth - 2, panelHeight - 2, colors.black)

  for index, line in ipairs(HOUSE_RULE_LINES) do
    local textColor = (index == 1) and colors.yellow or colors.white
    local textWidth = env.surface.getTextSize(line, env.font)
    local textX = panelX + math.floor((panelWidth - textWidth) / 2)
    local textY = panelY + scale.smallGap + ((index - 1) * lineHeight)
    ui.safeDrawText(screen, line, env.font, textX, textY, textColor)
  end
end

launcher.run({
  startupName = "Casino Startup",
  logFile = "debug.txt",
  monitorName = "right",
  cardAnimation = "random",
  program = "blackjack.lua",
  drawOverlay = drawOverlay,
})
