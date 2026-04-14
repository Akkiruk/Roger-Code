-- manifest-entrypoint: true
-- manifest-key: blackjack
-- manifest-name: Blackjack
-- manifest-description: Single-seat blackjack with split, double, and configurable house rules.
-- manifest-category: Games
local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "BLACKJACK"
  local titleWidth = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - titleWidth) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch to play"
  local subtitleWidth = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - subtitleWidth) / 2), scale.idleSubtitleY, colors.white)
end

launcher.run({
  startupName = "Blackjack Startup",
  logFile = "blackjack_error.log",
  monitorName = "right",
  cardAnimation = "random",
  program = "blackjack.lua",
  drawOverlay = drawOverlay,
})
