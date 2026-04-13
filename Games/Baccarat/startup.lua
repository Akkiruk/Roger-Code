-- manifest-entrypoint: true
-- manifest-key: baccarat
-- manifest-name: Baccarat
-- manifest-description: Single-seat baccarat with player, banker, and tie bets.
-- manifest-category: Games
local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "BACCARAT"
  local tw = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch to play"
  local sw = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - sw) / 2), scale.idleSubtitleY, colors.white)
end

launcher.run({
  startupName = "Baccarat Startup",
  logFile = "baccarat_error.log",
  monitorName = "right",
  program = "baccarat.lua",
  cardAnimation = "random",
  drawOverlay = drawOverlay,
})
