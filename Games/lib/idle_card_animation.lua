local cardsLib = require("lib.cards")
local presets = require("lib.idle_card_animation_presets")

local M = {}

local DEFAULT_ANIMATION = "bounce"
local PRESET_ORDER = {
  "bounce",
  "glide",
  "arc",
  "deal",
}

local function pickRandomPresetName()
  return PRESET_ORDER[math.random(#PRESET_ORDER)]
end

local function resolvePreset(name)
  if name == "random" then
    local randomName = pickRandomPresetName()
    return randomName, presets[randomName]
  end
  if type(name) == "string" and presets[name] then
    return name, presets[name]
  end
  return DEFAULT_ANIMATION, presets[DEFAULT_ANIMATION]
end

function M.setup(env, options)
  assert(type(env) == "table", "env must be a table")

  if not env.cardBg or not env.cardBack then
    env.cardAnimator = nil
    return nil
  end

  cardsLib.initRenderer(env.surface, env.font, env.cardBg)
  env.deck = cardsLib.buildDeck(1)
  cardsLib.shuffle(env.deck)

  local config = options or {}
  local animationName, preset = resolvePreset(config.animation)
  local cardCount = config.cardCount or 4
  local animator = {
    name = animationName,
    preset = preset,
    cards = {},
  }

  for index = 1, cardCount do
    local state = {
      index = index,
      total = cardCount,
    }
    preset.spawn(state, env, true)
    animator.cards[index] = state
  end

  env.cardAnimator = animator
  return animator
end

function M.draw(env)
  local animator = env.cardAnimator
  if not animator then
    return
  end

  for _, state in ipairs(animator.cards) do
    local cardSurf = cardsLib.renderCard(state.card)
    animator.preset.step(env, state, cardSurf)
  end
end

function M.listPresets()
  return PRESET_ORDER
end

function M.getPresetDescription(name)
  local _, preset = resolvePreset(name)
  return preset.description
end

function M.getDefaultPreset()
  return DEFAULT_ANIMATION
end

return M