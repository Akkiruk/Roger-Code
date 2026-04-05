-- idle_screen.lua
-- Shared idle/title screen for casino game startups.
-- Handles surface init, bouncing card animation, and touch detection.
-- Usage:
--   local idle = require("lib.idle_screen")
--   local env = idle.setup({ monitorName = "right" })
--   local action = idle.runLoop(env, { drawOverlay = myDrawFunc })
--   -- action is "play" or a custom string from overlay button hits

local peripherals = require("lib.peripherals")
local gameSetup   = require("lib.game_setup")
local idleCardAnimation = require("lib.idle_card_animation")
local monitorScale = require("lib.monitor_scale")

local DEFAULT_PALETTE = gameSetup.DEFAULT_PALETTE

--- Initialize the idle screen environment.
-- @param cfg table  Required: monitorName. Optional: palette, cardCount, cardAnimation, extraAssets
-- @return table  env with surface, screen, font, monitor, width, height, cardBack, deck, cardAnimator
local function setup(cfg)
  assert(type(cfg) == "table", "setup expects a config table")
  assert(cfg.monitorName, "monitorName is required")

  local env = {}

  local ok, s = pcall(dofile, "surface")
  if not ok then error("surface API not found!") end
  env.surface = s

  env.monitor = peripherals.require(cfg.monitorName, "monitor", "monitor")
  if type(env.monitor.setTextScale) == "function" then
    env.monitor.setTextScale(monitorScale.surfaceTextScale(cfg.monitorTextScale))
  end
  term.redirect(env.monitor)

  local palette = cfg.palette or DEFAULT_PALETTE
  for colorID, hex in pairs(palette) do
    term.setPaletteColor(colorID, hex)
  end

  env.width, env.height = term.getSize()
  env.scale = monitorScale.forSurface(env.width, env.height)
  env.screen   = env.surface.create(env.width, env.height)
  env.font     = env.surface.loadFont(env.surface.load("font"))

  -- Card assets are optional — games without cards skip the bouncing animation
  -- Need card bg, card back, AND at least one suit image for the animation
  local hasCards = fs.exists("card.nfp") and fs.exists("cardback.nfp")
    and fs.exists("heart.nfp") and fs.exists("club.nfp")
    and fs.exists("diamond.nfp") and fs.exists("spade.nfp")
  env.cardBg   = hasCards and env.surface.load("card.nfp")    or nil
  env.cardBack = hasCards and env.surface.load("cardback.nfp") or nil

  -- Load extra assets if requested (e.g. logo)
  env.assets = {}
  if cfg.extraAssets then
    for name, path in pairs(cfg.extraAssets) do
      env.assets[name] = env.surface.load(path) or error(path .. " missing")
    end
  end

  idleCardAnimation.setup(env, {
    animation = cfg.cardAnimation,
    cardCount = cfg.cardCount,
  })

  return env
end

--- Draw one frame of the idle card animation.
-- @param env table  The environment from setup()
local function drawFrame(env)
  env.screen:clear(colors.green)
  idleCardAnimation.draw(env)
end

--- Run the idle animation loop until someone touches the monitor.
-- @param env  table  The environment from setup()
-- @param opts table? Optional: drawOverlay(env, screen) function for custom UI on top,
--                     checkHit(x, y, env) function returning action string or nil
-- @return string  "play" or a custom action from checkHit
local function runLoop(env, opts)
  opts = opts or {}
  local drawOverlay = opts.drawOverlay
  local checkHit    = opts.checkHit

  while true do
    drawFrame(env)

    if drawOverlay then
      drawOverlay(env, env.screen)
    end

    env.screen:output()

    local timerID = os.startTimer(0.05)
    local event, side, x, y = os.pullEvent()
    if not (event == "timer" and side == timerID) then
      os.cancelTimer(timerID)
    end
    if event == "monitor_touch" then
      if checkHit then
        local action = checkHit(x, y, env)
        if action then return action end
      end
      return "play"
    end
  end
end

return {
  DEFAULT_PALETTE = DEFAULT_PALETTE,
  setup           = setup,
  drawFrame       = drawFrame,
  runLoop         = runLoop,
}
