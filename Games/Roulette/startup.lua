-- manifest-entrypoint: true
-- manifest-key: roulette
-- manifest-name: Roulette
-- manifest-description: Single-zero European roulette with inside and outside bets.
-- manifest-category: Games
local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "ROULETTE"
  local tw = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2) + 1, scale.idleTitleY + 1, colors.black)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch felt to open table"
  local sw = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - sw) / 2), scale.idleSubtitleY, colors.lightGray)

  local strap = "Single-zero European roulette"
  local strapW = env.surface.getTextSize(strap, env.font)
  ui.safeDrawText(screen, strap, env.font, math.floor((env.width - strapW) / 2), scale.idleAccentY, colors.cyan)
end

launcher.run({
  startupName = "Roulette Startup",
  logFile = "roulette_error.log",
  monitorName = "right",
  program = "Roulette.lua",
  drawOverlay = drawOverlay,
  cardCount = 0,
})
