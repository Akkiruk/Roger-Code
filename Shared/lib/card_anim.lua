-- card_anim.lua
-- Animated card dealing for surface-based casino games.
-- Slides cards from off-screen to their target positions with ease-out motion.
-- Usage:
--   local cardAnim = require("lib.card_anim")
--   cardAnim.init(screen, cardBack)
--   cardAnim.slideIn(cardImg, toX, toY, renderBgFn)

local sound = require("lib.sound")

local _screen   = nil
local _cardBack = nil

-- Animation timing (configurable via configure())
local SLIDE_STEPS = 6       -- frames per card slide
local FRAME_DELAY = 0.05    -- seconds between frames
local CARD_PAUSE  = 0.25    -- pause after each card lands

--- Initialize the animation module.
-- @param screen   surface  The off-screen buffer (env.screen)
-- @param cardBack surface  The card-back image (env.cardBack)
local function init(screen, cardBack)
  assert(screen, "card_anim.init: screen is required")
  assert(cardBack, "card_anim.init: cardBack is required")
  _screen   = screen
  _cardBack = cardBack
end

--- Configure animation timing.
-- @param opts table  Optional keys: slideSteps, frameDelay, cardPause
local function configure(opts)
  if not opts then return end
  if opts.slideSteps then SLIDE_STEPS = opts.slideSteps end
  if opts.frameDelay then FRAME_DELAY = opts.frameDelay end
  if opts.cardPause  then CARD_PAUSE  = opts.cardPause end
end

local function slide(cardImg, fromX, fromY, toX, toY, renderBgFn, opts)
  assert(_screen, "Call card_anim.init() first")
  local options = opts or {}
  local steps = options.slideSteps or SLIDE_STEPS
  local frameDelay = options.frameDelay or FRAME_DELAY
  local pauseAfter = options.pauseAfter
  if pauseAfter == nil then
    pauseAfter = CARD_PAUSE
  end

  for i = 1, steps do
    local t = i / steps
    local eased = 1 - (1 - t) * (1 - t)
    local cx = math.floor(fromX + (toX - fromX) * eased + 0.5)
    local cy = math.floor(fromY + (toY - fromY) * eased + 0.5)
    renderBgFn()
    _screen:drawSurface(cardImg, cx, cy)
    _screen:output()
    if i < steps then
      os.sleep(frameDelay)
    end
  end

  if options.playSound ~= false then
    sound.play(options.soundId or sound.SOUNDS.CARD_PLACE, options.soundVolume or 0.7)
  end

  if pauseAfter and pauseAfter > 0 then
    os.sleep(pauseAfter)
  end
end

--- Slide a card from off-screen (top-center) to (toX, toY) with ease-out.
-- renderBgFn is called before every frame to redraw the static background
-- to the screen buffer — it must NOT call screen:output().
-- @param cardImg    surface  The card surface to animate
-- @param toX        number   Destination x pixel
-- @param toY        number   Destination y pixel
-- @param renderBgFn function Redraws background (no output) each frame
local function slideIn(cardImg, toX, toY, renderBgFn)
  assert(_screen, "Call card_anim.init() first")
  local fromX = math.floor(_screen.width / 2) - 6
  local fromY = -_cardBack.height
  slide(cardImg, fromX, fromY, toX, toY, renderBgFn)
end

return {
  init      = init,
  configure = configure,
  slide     = slide,
  slideIn   = slideIn,
}
