-- manifest-entrypoint: true
local launcher = require("lib.casino_launcher")
local ui = require("lib.ui")

local function drawOverlay(env, screen)
  local scale = env.scale
  local title = "VIDEO POKER"
  local tw = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2), scale.idleTitleY, colors.yellow)

  local subtitle = "Touch to play"
  local sw = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - sw) / 2), scale.idleSubtitleY, colors.white)
end

launcher.run({
  startupName = "VideoPoker Startup",
  logFile = "videopoker_error.log",
  monitorName = "right",
  program = "videopoker.lua",
  cardAnimation = "random",
  drawOverlay = drawOverlay,
})
