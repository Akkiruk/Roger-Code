-- idle_screen.lua
-- Shared idle/title screen for casino game startups.
-- Handles surface init, bouncing card animation, and touch detection.
-- Usage:
--   local idle = require("lib.idle_screen")
--   local env = idle.setup({ monitorName = "right" })
--   local action = idle.runLoop(env, { drawOverlay = myDrawFunc })
--   -- action is "play" or a custom string from overlay button hits

local peripherals = require("lib.peripherals")
local cardsLib    = require("lib.cards")
local gameSetup   = require("lib.game_setup")

local DEFAULT_PALETTE = gameSetup.DEFAULT_PALETTE

--- Bounce easing function (decelerate/bounce curve).
-- @param x number  0.0 to 1.0
-- @return number
local function ease(x)
  local n1 = 7.5625
  local d1 = 2.75
  if x < 1 / d1 then
    return n1 * x * x
  elseif x < 2 / d1 then
    x = x - 1.5 / d1
    return n1 * x * x + 0.75
  elseif x < 2.5 / d1 then
    x = x - 2.25 / d1
    return n1 * x * x + 0.9375
  else
    x = x - 2.625 / d1
    return n1 * x * x + 0.984375
  end
end

--- Initialize the idle screen environment.
-- @param cfg table  Required: monitorName. Optional: palette, cardCount, extraAssets
-- @return table  env with surface, screen, font, monitor, width, height, cardBack, deck, bouncingCards
local function setup(cfg)
  assert(type(cfg) == "table", "setup expects a config table")
  assert(cfg.monitorName, "monitorName is required")

  local env = {}

  local ok, s = pcall(dofile, "surface")
  if not ok then error("surface API not found!") end
  env.surface = s

  env.monitor = peripherals.require(cfg.monitorName, "monitor", "monitor")
  if type(env.monitor.setTextScale) == "function" then
    env.monitor.setTextScale(0.5)
  end
  term.redirect(env.monitor)

  local palette = cfg.palette or DEFAULT_PALETTE
  for colorID, hex in pairs(palette) do
    term.setPaletteColor(colorID, hex)
  end

  env.width, env.height = term.getSize()
  env.screen   = env.surface.create(env.width, env.height)
  env.font     = env.surface.loadFont(env.surface.load("font"))

  -- Card assets are optional — games without cards skip the bouncing animation
  env.cardBg   = fs.exists("card.nfp")    and env.surface.load("card.nfp")    or nil
  env.cardBack = fs.exists("cardback.nfp") and env.surface.load("cardback.nfp") or nil

  -- Load extra assets if requested (e.g. logo)
  env.assets = {}
  if cfg.extraAssets then
    for name, path in pairs(cfg.extraAssets) do
      env.assets[name] = env.surface.load(path) or error(path .. " missing")
    end
  end

  env.bouncingCards = {}
  if env.cardBg and env.cardBack then
    cardsLib.initRenderer(env.surface, env.font, env.cardBg)
    env.deck = cardsLib.buildDeck(1)
    cardsLib.shuffle(env.deck)

    local cardCount = cfg.cardCount or 4
    for j = 1, cardCount do
      env.bouncingCards[j] = {
        x            = -math.floor(math.random() * env.width * 2),
        y            = 0,
        speed        = 1 + math.random() * 0.5,
        bounceHeight = 0.6 + math.random() * 0.3,
        mirror       = (math.random() > 0.5),
        card         = env.deck[j],
        yDrift       = math.random() * 2 - 1,
      }
    end
  end

  return env
end

--- Draw one frame of the bouncing card animation.
-- @param env table  The environment from setup()
local function drawFrame(env)
  local screen    = env.screen
  local width     = env.width
  local height    = env.height
  local cardBack  = env.cardBack
  local deck      = env.deck

  screen:clear(colors.green)

  for _, cardObj in ipairs(env.bouncingCards) do
    local xPos = cardObj.x
    if cardObj.mirror then
      xPos = (width - cardBack.width) - xPos
    end

    local cardSurf = cardsLib.renderCard(cardObj.card)
    local bounceY = ease(cardObj.x / width) * (height * cardObj.bounceHeight)
    local y = math.floor(bounceY + (height * 0.25) - cardBack.height + cardObj.yDrift)

    screen:drawSurface(cardSurf, math.floor(xPos), y)

    cardObj.x = cardObj.x + cardObj.speed
    if cardObj.x > width then
      cardObj.x = -cardBack.width - math.random(20)
      cardObj.card = deck[math.random(#deck)]
      cardObj.speed = 1 + math.random() * 0.5
      cardObj.bounceHeight = 0.6 + math.random() * 0.3
      cardObj.yDrift = math.random() * 2 - 1
      if math.random() < 0.3 then
        cardObj.mirror = not cardObj.mirror
      end
    end
  end
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
