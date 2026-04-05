local M = {}

local floor = math.floor
local min = math.min
local sin = math.sin
local pi = math.pi

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(a, b, t)
  return a + ((b - a) * t)
end

local function easeBounce(x)
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

local function easeOutCubic(x)
  local inverse = 1 - x
  return 1 - (inverse * inverse * inverse)
end

local function pickCard(env)
  return env.deck[math.random(#env.deck)]
end

local function refreshCard(state, env)
  state.card = pickCard(env)
  state.yDrift = (math.random() * 2) - 1
end

local function spawnBounce(state, env, isInitial)
  refreshCard(state, env)
  state.x = isInitial and -floor(math.random() * env.width * 2) or (-env.cardBack.width - math.random(20))
  state.speed = 1 + (math.random() * 0.5)
  state.bounceHeight = 0.6 + (math.random() * 0.3)
  state.mirror = math.random() > 0.5
end

local function stepBounce(env, state, cardSurf)
  local xPos = state.x
  if state.mirror then
    xPos = (env.width - env.cardBack.width) - xPos
  end

  local progress = 0
  if env.width > 0 then
    progress = clamp(state.x / env.width, 0, 1)
  end
  local bounceY = easeBounce(progress) * (env.height * state.bounceHeight)
  local y = floor(bounceY + (env.height * 0.25) - env.cardBack.height + state.yDrift)

  env.screen:drawSurface(cardSurf, floor(xPos), y)

  state.x = state.x + state.speed
  if state.x > env.width then
    spawnBounce(state, env, false)
  end
end

local function spawnGlide(state, env, isInitial)
  refreshCard(state, env)
  state.direction = (math.random() > 0.5) and 1 or -1
  state.speed = 0.55 + (math.random() * 0.45)
  state.baseY = floor(env.height * (0.15 + (math.random() * 0.45)))
  state.waveAmplitude = 1 + floor(math.random() * 3)
  state.waveRate = 0.08 + (math.random() * 0.05)
  state.phase = math.random() * (pi * 2)
  state.mirror = state.direction < 0

  if state.direction > 0 then
    state.x = isInitial and -floor(math.random() * env.width) or (-env.cardBack.width - math.random(20))
  else
    state.x = isInitial and (env.width + floor(math.random() * env.width)) or (env.width + env.cardBack.width + math.random(20))
  end
end

local function stepGlide(env, state, cardSurf)
  local y = state.baseY + floor(sin(state.phase) * state.waveAmplitude) + state.yDrift
  env.screen:drawSurface(cardSurf, floor(state.x), y)

  state.x = state.x + (state.speed * state.direction)
  state.phase = state.phase + state.waveRate

  if state.direction > 0 and state.x > env.width then
    spawnGlide(state, env, false)
  elseif state.direction < 0 and state.x < -env.cardBack.width then
    spawnGlide(state, env, false)
  end
end

local function spawnArc(state, env, isInitial)
  refreshCard(state, env)
  state.speed = 0.75 + (math.random() * 0.45)
  state.direction = (math.random() > 0.5) and 1 or -1
  state.curveHeight = env.height * (0.12 + (math.random() * 0.16))
  state.baseY = env.height * (0.28 + (math.random() * 0.18))
  state.mirror = state.direction < 0

  if state.direction > 0 then
    state.progressX = isInitial and -floor(math.random() * env.width) or (-env.cardBack.width - math.random(20))
  else
    state.progressX = isInitial and (env.width + floor(math.random() * env.width)) or (env.width + env.cardBack.width + math.random(20))
  end
end

local function stepArc(env, state, cardSurf)
  local fullWidth = env.width + env.cardBack.width
  local normalized
  if state.direction > 0 then
    normalized = clamp((state.progressX + env.cardBack.width) / fullWidth, 0, 1)
  else
    normalized = clamp((env.width - state.progressX) / fullWidth, 0, 1)
  end

  local arcOffset = sin(normalized * pi) * state.curveHeight
  local y = floor(state.baseY - arcOffset + state.yDrift)
  env.screen:drawSurface(cardSurf, floor(state.progressX), y)

  state.progressX = state.progressX + (state.speed * state.direction)

  if state.direction > 0 and state.progressX > env.width then
    spawnArc(state, env, false)
  elseif state.direction < 0 and state.progressX < -env.cardBack.width then
    spawnArc(state, env, false)
  end
end

local function spawnDeal(state, env, isInitial)
  refreshCard(state, env)
  state.sourceX = floor((env.width - env.cardBack.width) / 2)
  state.sourceY = -env.cardBack.height - math.random(8)
  state.targetX = floor(env.width * (0.10 + (math.random() * 0.80))) - floor(env.cardBack.width / 2)
  state.targetY = floor(env.height * (0.16 + (math.random() * 0.42))) - floor(env.cardBack.height / 2)
  state.exitDirection = (state.targetX < (env.width / 2)) and -1 or 1
  state.dealProgress = isInitial and math.random() or 0
  state.dealSpeed = 0.08 + (math.random() * 0.05)
  state.holdFrames = 4 + math.random(8)
  state.exitSpeed = 1.2 + (math.random() * 0.5)
  state.phase = (isInitial and state.dealProgress >= 1) and "hold" or "deal"
  state.x = state.sourceX
  state.y = state.sourceY
  state.mirror = false
end

local function stepDeal(env, state, cardSurf)
  if state.phase == "deal" then
    state.dealProgress = min(1, state.dealProgress + state.dealSpeed)
    local eased = easeOutCubic(state.dealProgress)
    state.x = lerp(state.sourceX, state.targetX, eased)
    state.y = lerp(state.sourceY, state.targetY, eased)
    if state.dealProgress >= 1 then
      state.phase = "hold"
    end
  elseif state.phase == "hold" then
    state.x = state.targetX
    state.y = state.targetY
    state.holdFrames = state.holdFrames - 1
    if state.holdFrames <= 0 then
      state.phase = "exit"
    end
  else
    state.x = state.x + (state.exitSpeed * state.exitDirection)
    state.y = state.y + 0.35
    if state.x > env.width or state.x < -env.cardBack.width or state.y > env.height then
      spawnDeal(state, env, false)
    end
  end

  env.screen:drawSurface(cardSurf, floor(state.x), floor(state.y))
end

M.bounce = {
  description = "Existing bounce motion across the felt.",
  spawn = spawnBounce,
  step = stepBounce,
}

M.glide = {
  description = "Smooth horizontal glide with a soft bob.",
  spawn = spawnGlide,
  step = stepGlide,
}

M.arc = {
  description = "Cards sweep across the screen on shallow arcs.",
  spawn = spawnArc,
  step = stepArc,
}

M.deal = {
  description = "Cards deal into table lanes, hold, and clear away.",
  spawn = spawnDeal,
  step = stepDeal,
}

return Mlocal M = {}

local floor = math.floor
local min = math.min
local sin = math.sin
local pi = math.pi

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(a, b, t)
  return a + ((b - a) * t)
end

local function easeBounce(x)
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

local function easeOutCubic(x)
  local inverse = 1 - x
  return 1 - (inverse * inverse * inverse)
end

local function pickCard(env)
  return env.deck[math.random(#env.deck)]
end

local function refreshCard(state, env)
  state.card = pickCard(env)
  state.yDrift = (math.random() * 2) - 1
end

local function spawnBounce(state, env, isInitial)
  refreshCard(state, env)
  state.x = isInitial and -floor(math.random() * env.width * 2) or (-env.cardBack.width - math.random(20))
  state.speed = 1 + (math.random() * 0.5)
  state.bounceHeight = 0.6 + (math.random() * 0.3)
  state.mirror = math.random() > 0.5
end

local function stepBounce(env, state, cardSurf)
  local xPos = state.x
  if state.mirror then
    xPos = (env.width - env.cardBack.width) - xPos
  end

  local progress = 0
  if env.width > 0 then
    progress = clamp(state.x / env.width, 0, 1)
  end
  local bounceY = easeBounce(progress) * (env.height * state.bounceHeight)
  local y = floor(bounceY + (env.height * 0.25) - env.cardBack.height + state.yDrift)

  env.screen:drawSurface(cardSurf, floor(xPos), y)

  state.x = state.x + state.speed
  if state.x > env.width then
    spawnBounce(state, env, false)
  end
end

local function spawnGlide(state, env, isInitial)
  refreshCard(state, env)
  state.direction = (math.random() > 0.5) and 1 or -1
  state.speed = 0.55 + (math.random() * 0.45)
  state.baseY = floor(env.height * (0.15 + (math.random() * 0.45)))
  state.waveAmplitude = 1 + floor(math.random() * 3)
  state.waveRate = 0.08 + (math.random() * 0.05)
  state.phase = math.random() * (pi * 2)
  state.mirror = state.direction < 0

  if state.direction > 0 then
    state.x = isInitial and -floor(math.random() * env.width) or (-env.cardBack.width - math.random(20))
  else
    state.x = isInitial and (env.width + floor(math.random() * env.width)) or (env.width + env.cardBack.width + math.random(20))
  end
end

local function stepGlide(env, state, cardSurf)
  local y = state.baseY + floor(sin(state.phase) * state.waveAmplitude) + state.yDrift
  env.screen:drawSurface(cardSurf, floor(state.x), y)

  state.x = state.x + (state.speed * state.direction)
  state.phase = state.phase + state.waveRate

  if state.direction > 0 and state.x > env.width then
    spawnGlide(state, env, false)
  elseif state.direction < 0 and state.x < -env.cardBack.width then
    spawnGlide(state, env, false)
  end
end

local function spawnArc(state, env, isInitial)
  refreshCard(state, env)
  state.speed = 0.75 + (math.random() * 0.45)
  state.direction = (math.random() > 0.5) and 1 or -1
  state.curveHeight = env.height * (0.12 + (math.random() * 0.16))
  state.baseY = env.height * (0.28 + (math.random() * 0.18))
  state.mirror = state.direction < 0

  if state.direction > 0 then
    state.progressX = isInitial and -floor(math.random() * env.width) or (-env.cardBack.width - math.random(20))
  else
    state.progressX = isInitial and (env.width + floor(math.random() * env.width)) or (env.width + env.cardBack.width + math.random(20))
  end
end

local function stepArc(env, state, cardSurf)
  local fullWidth = env.width + env.cardBack.width
  local normalized
  if state.direction > 0 then
    normalized = clamp((state.progressX + env.cardBack.width) / fullWidth, 0, 1)
  else
    normalized = clamp((env.width - state.progressX) / fullWidth, 0, 1)
  end

  local arcOffset = sin(normalized * pi) * state.curveHeight
  local y = floor(state.baseY - arcOffset + state.yDrift)
  env.screen:drawSurface(cardSurf, floor(state.progressX), y)

  state.progressX = state.progressX + (state.speed * state.direction)

  if state.direction > 0 and state.progressX > env.width then
    spawnArc(state, env, false)
  elseif state.direction < 0 and state.progressX < -env.cardBack.width then
    spawnArc(state, env, false)
  end
end

local function spawnDeal(state, env, isInitial)
  refreshCard(state, env)
  state.sourceX = floor((env.width - env.cardBack.width) / 2)
  state.sourceY = -env.cardBack.height - math.random(8)
  state.targetX = floor(env.width * (0.10 + (math.random() * 0.80))) - floor(env.cardBack.width / 2)
  state.targetY = floor(env.height * (0.16 + (math.random() * 0.42))) - floor(env.cardBack.height / 2)
  state.exitDirection = (state.targetX < (env.width / 2)) and -1 or 1
  state.dealProgress = isInitial and math.random() or 0
  state.dealSpeed = 0.08 + (math.random() * 0.05)
  state.holdFrames = 4 + math.random(8)
  state.exitSpeed = 1.2 + (math.random() * 0.5)
  state.phase = (isInitial and state.dealProgress >= 1) and "hold" or "deal"
  state.x = state.sourceX
  state.y = state.sourceY
  state.mirror = false
end

local function stepDeal(env, state, cardSurf)
  if state.phase == "deal" then
    state.dealProgress = min(1, state.dealProgress + state.dealSpeed)
    local eased = easeOutCubic(state.dealProgress)
    state.x = lerp(state.sourceX, state.targetX, eased)
    state.y = lerp(state.sourceY, state.targetY, eased)
    if state.dealProgress >= 1 then
      state.phase = "hold"
    end
  elseif state.phase == "hold" then
    state.x = state.targetX
    state.y = state.targetY
    state.holdFrames = state.holdFrames - 1
    if state.holdFrames <= 0 then
      state.phase = "exit"
    end
  else
    state.x = state.x + (state.exitSpeed * state.exitDirection)
    state.y = state.y + 0.35
    if state.x > env.width or state.x < -env.cardBack.width or state.y > env.height then
      spawnDeal(state, env, false)
    end
  end

  env.screen:drawSurface(cardSurf, floor(state.x), floor(state.y))
end

M.bounce = {
  description = "Existing bounce motion across the felt.",
  spawn = spawnBounce,
  step = stepBounce,
}

M.glide = {
  description = "Smooth horizontal glide with a soft bob.",
  spawn = spawnGlide,
  step = stepGlide,
}

M.arc = {
  description = "Cards sweep across the screen on shallow arcs.",
  spawn = spawnArc,
  step = stepArc,
}

M.deal = {
  description = "Cards deal into table lanes, hold, and clear away.",
  spawn = spawnDeal,
  step = stepDeal,
}

return M