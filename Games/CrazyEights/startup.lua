-- manifest-entrypoint: true
-- manifest-key: crazyeights
-- manifest-name: CrazyEights
-- manifest-description: Fast single-hand Crazy Eights duel with wild 8s and draw 2s.
-- manifest-category: Games

local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "CRAZY EIGHTS"
  local tw = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch to play"
  local sw = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - sw) / 2), scale.idleSubtitleY, colors.white)

  local accent = "Wild 8s. Draw 2s. One hand."
  local aw = env.surface.getTextSize(accent, env.font)
  ui.safeDrawText(screen, accent, env.font, math.floor((env.width - aw) / 2), scale.idleAccentY, colors.cyan)
end

launcher.run({
  startupName = "CrazyEights Startup",
  logFile = "crazyeights_error.log",
  monitorName = "right",
  program = "crazyeights.lua",
  cardAnimation = "random",
  drawOverlay = drawOverlay,
})