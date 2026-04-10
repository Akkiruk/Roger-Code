local M = {}

local abs = math.abs
local ceil = math.ceil
local cos = math.cos
local floor = math.floor
local max = math.max
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

local function easeInOutSine(x)
  return -(cos(pi * clamp(x, 0, 1)) - 1) / 2
end

local function randomFloat(minValue, maxValue)
  return minValue + (math.random() * (maxValue - minValue))
end

local function pickCard(env)
  return env.deck[math.random(#env.deck)]
end

local function refreshCard(state, env)
  state.card = pickCard(env)
  state.yDrift = (math.random() * 2) - 1
end

local function centerCardX(env)
  return floor((env.width - env.cardBack.width) / 2)
end

local function centerCardY(env)
  return floor((env.height - env.cardBack.height) / 2)
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
  state.sourceX = centerCardX(env)
  state.sourceY = -env.cardBack.height - math.random(8)
  state.targetX = floor(env.width * randomFloat(0.10, 0.80)) - floor(env.cardBack.width / 2)
  state.targetY = floor(env.height * randomFloat(0.16, 0.42)) - floor(env.cardBack.height / 2)
  state.exitDirection = (state.targetX < (env.width / 2)) and -1 or 1
  state.dealProgress = isInitial and math.random() or 0
  state.dealSpeed = randomFloat(0.08, 0.13)
  state.holdFrames = 4 + math.random(8)
  state.exitSpeed = randomFloat(1.2, 1.7)
  state.phase = "deal"
  state.x = state.sourceX
  state.y = state.sourceY
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

local function spawnFan(state, env, isInitial)
  refreshCard(state, env)
  local offset = state.index - ((state.total + 1) / 2)
  local spread = max(4, floor(env.cardBack.width * 0.45))
  local centerX = centerCardX(env)
  local centerY = floor(env.height * 0.48) - floor(env.cardBack.height / 2)
  state.sourceX = centerX
  state.sourceY = centerY + floor(abs(offset) * 0.5)
  state.targetX = centerX + floor(offset * spread)
  state.targetY = centerY + floor(abs(offset) * max(1, floor(env.cardBack.height * 0.18)))
  state.progress = isInitial and math.random() or 0
  state.speed = randomFloat(0.04, 0.07)
  state.holdFrames = 6 + math.random(10)
  state.phase = "open"
end

local function stepFan(env, state, cardSurf)
  local x = state.sourceX
  local y = state.sourceY

  if state.phase == "open" then
    state.progress = min(1, state.progress + state.speed)
    local eased = easeInOutSine(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress >= 1 then
      state.phase = "hold"
    end
  elseif state.phase == "hold" then
    x = state.targetX
    y = state.targetY
    state.holdFrames = state.holdFrames - 1
    if state.holdFrames <= 0 then
      state.phase = "close"
    end
  else
    state.progress = max(0, state.progress - state.speed)
    local eased = easeInOutSine(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress <= 0 then
      spawnFan(state, env, false)
      x = state.sourceX
      y = state.sourceY
    end
  end

  env.screen:drawSurface(cardSurf, floor(x), floor(y + state.yDrift))
end

local function spawnFlip(state, env, isInitial)
  refreshCard(state, env)
  state.direction = (math.random() > 0.5) and 1 or -1
  state.startX = state.direction > 0 and (-env.cardBack.width - math.random(12)) or (env.width + math.random(12))
  state.endX = state.direction > 0 and (env.width + math.random(12)) or (-env.cardBack.width - math.random(12))
  state.baseY = floor(env.height * randomFloat(0.18, 0.52))
  state.progress = isInitial and math.random() or 0
  state.speed = randomFloat(0.025, 0.045)
  state.flipAt = randomFloat(0.42, 0.58)
  state.lift = randomFloat(2, 5)
end

local function stepFlip(env, state, cardSurf)
  local eased = easeInOutSine(state.progress)
  local x = lerp(state.startX, state.endX, eased)
  local y = state.baseY - floor(sin(state.progress * pi) * state.lift) + state.yDrift
  local surf = state.progress < state.flipAt and env.cardBack or cardSurf
  env.screen:drawSurface(surf, floor(x), floor(y))

  state.progress = state.progress + state.speed
  if state.progress >= 1 then
    spawnFlip(state, env, false)
  end
end

local function spawnCascade(state, env, isInitial)
  refreshCard(state, env)
  state.direction = (math.random() > 0.5) and 1 or -1
  if state.direction > 0 then
    state.x = -env.cardBack.width - math.random(8) - floor((state.index - 1) * env.cardBack.width * 0.35)
  else
    state.x = env.width + math.random(8) + floor((state.index - 1) * env.cardBack.width * 0.35)
  end
  state.y = -env.cardBack.height - floor((state.index - 1) * env.cardBack.height * 0.45)
  state.xSpeed = state.direction * randomFloat(0.65, 1.15)
  state.ySpeed = randomFloat(0.8, 1.3)
  state.wavePhase = math.random() * (pi * 2)
  state.waveRate = randomFloat(0.08, 0.14)
  state.waveDrift = randomFloat(0.1, 0.28)
  state.delayFrames = isInitial and floor(math.random() * 12) or ((state.index - 1) * 4)
end

local function stepCascade(env, state, cardSurf)
  if state.delayFrames > 0 then
    state.delayFrames = state.delayFrames - 1
    return
  end

  env.screen:drawSurface(cardSurf, floor(state.x), floor(state.y + state.yDrift))

  state.x = state.x + state.xSpeed + (sin(state.wavePhase) * state.waveDrift)
  state.y = state.y + state.ySpeed
  state.wavePhase = state.wavePhase + state.waveRate

  if state.y > env.height + env.cardBack.height
    or state.x > env.width + env.cardBack.width
    or state.x < -(env.cardBack.width * 2) then
    spawnCascade(state, env, false)
  end
end

local function spawnOrbit(state, env, isInitial)
  refreshCard(state, env)
  state.centerX = centerCardX(env)
  state.centerY = centerCardY(env)
  state.radiusX = max(env.cardBack.width + 4, floor(env.width * randomFloat(0.22, 0.34)))
  state.radiusY = max(env.cardBack.height + 3, floor(env.height * randomFloat(0.12, 0.20)))
  state.angle = ((state.index - 1) / max(1, state.total)) * (pi * 2)
  if isInitial then
    state.angle = state.angle + (math.random() * pi * 2)
  end
  state.speed = randomFloat(0.03, 0.06)
  if math.random() > 0.5 then
    state.speed = -state.speed
  end
  state.cycleProgress = isInitial and math.random() or 0
end

local function stepOrbit(env, state, cardSurf)
  local x = state.centerX + (cos(state.angle) * state.radiusX)
  local y = state.centerY + (sin(state.angle) * state.radiusY)
  env.screen:drawSurface(cardSurf, floor(x), floor(y + state.yDrift))

  state.angle = state.angle + state.speed
  state.cycleProgress = state.cycleProgress + (abs(state.speed) / (pi * 2))
  if state.cycleProgress >= 1 then
    state.cycleProgress = state.cycleProgress - 1
    refreshCard(state, env)
  end
end

local function spawnCut(state, env, isInitial)
  refreshCard(state, env)
  local leftCount = ceil(state.total / 2)
  state.centerX = centerCardX(env)
  state.centerY = floor(env.height * 0.40)
  state.group = state.index <= leftCount and -1 or 1
  if state.index <= leftCount then
    state.slot = state.index - 1
  else
    state.slot = state.index - leftCount - 1
  end
  state.progress = isInitial and math.random() or 0
  state.speed = randomFloat(0.02, 0.035)
  state.splitDistance = max(6, floor(env.width * 0.18))
  state.slotOffsetY = state.slot * max(1, floor(env.cardBack.height * 0.18))
end

local function stepCut(env, state, cardSurf)
  local x = state.centerX
  local crossLift = 0

  if state.progress < 0.25 then
    local t = easeInOutSine(state.progress / 0.25)
    x = lerp(state.centerX, state.centerX + (state.group * state.splitDistance), t)
  elseif state.progress < 0.55 then
    local t = easeInOutSine((state.progress - 0.25) / 0.30)
    x = lerp(state.centerX + (state.group * state.splitDistance), state.centerX - (state.group * state.splitDistance), t)
    crossLift = sin(t * pi) * 3
  elseif state.progress < 0.80 then
    local t = easeInOutSine((state.progress - 0.55) / 0.25)
    x = lerp(state.centerX - (state.group * state.splitDistance), state.centerX, t)
  end

  local y = state.centerY + state.slotOffsetY - floor(crossLift) + state.yDrift
  env.screen:drawSurface(cardSurf, floor(x), floor(y))

  state.progress = state.progress + state.speed
  if state.progress >= 1 then
    spawnCut(state, env, false)
  end
end

local function spawnPeek(state, env, isInitial)
  refreshCard(state, env)
  local side = math.random(4)
  if side == 1 then
    state.sourceX = -env.cardBack.width - math.random(10)
    state.sourceY = floor(env.height * randomFloat(0.10, 0.72))
    state.targetX = -floor(env.cardBack.width * 0.35)
    state.targetY = state.sourceY
  elseif side == 2 then
    state.sourceX = env.width + math.random(10)
    state.sourceY = floor(env.height * randomFloat(0.10, 0.72))
    state.targetX = env.width - floor(env.cardBack.width * 0.65)
    state.targetY = state.sourceY
  elseif side == 3 then
    state.sourceX = floor(env.width * randomFloat(0.08, 0.82))
    state.sourceY = -env.cardBack.height - math.random(10)
    state.targetX = state.sourceX
    state.targetY = -floor(env.cardBack.height * 0.35)
  else
    state.sourceX = floor(env.width * randomFloat(0.08, 0.82))
    state.sourceY = env.height + math.random(10)
    state.targetX = state.sourceX
    state.targetY = env.height - floor(env.cardBack.height * 0.65)
  end
  state.progress = isInitial and math.random() or 0
  state.speed = randomFloat(0.05, 0.08)
  state.holdFrames = 4 + math.random(8)
  state.phase = "open"
end

local function stepPeek(env, state, cardSurf)
  local x = state.sourceX
  local y = state.sourceY

  if state.phase == "open" then
    state.progress = min(1, state.progress + state.speed)
    local eased = easeInOutSine(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress >= 1 then
      state.phase = "hold"
    end
  elseif state.phase == "hold" then
    x = state.targetX
    y = state.targetY
    state.holdFrames = state.holdFrames - 1
    if state.holdFrames <= 0 then
      state.phase = "close"
    end
  else
    state.progress = max(0, state.progress - state.speed)
    local eased = easeInOutSine(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress <= 0 then
      spawnPeek(state, env, false)
      x = state.sourceX
      y = state.sourceY
    end
  end

  env.screen:drawSurface(cardSurf, floor(x), floor(y + state.yDrift))
end

local function spawnScatter(state, env, isInitial)
  refreshCard(state, env)
  state.sourceX = centerCardX(env)
  state.sourceY = centerCardY(env)
  state.targetX = floor(randomFloat(-env.cardBack.width * 0.10, env.width - (env.cardBack.width * 0.90)))
  state.targetY = floor(randomFloat(env.height * 0.08, env.height * 0.72))
  state.progress = isInitial and math.random() or 0
  state.speed = randomFloat(0.04, 0.07)
  state.holdFrames = 5 + math.random(8)
  state.phase = "open"
end

local function stepScatter(env, state, cardSurf)
  local x = state.sourceX
  local y = state.sourceY

  if state.phase == "open" then
    state.progress = min(1, state.progress + state.speed)
    local eased = easeOutCubic(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress >= 1 then
      state.phase = "hold"
    end
  elseif state.phase == "hold" then
    x = state.targetX
    y = state.targetY
    state.holdFrames = state.holdFrames - 1
    if state.holdFrames <= 0 then
      state.phase = "close"
    end
  else
    state.progress = max(0, state.progress - state.speed)
    local eased = easeInOutSine(state.progress)
    x = lerp(state.sourceX, state.targetX, eased)
    y = lerp(state.sourceY, state.targetY, eased)
    if state.progress <= 0 then
      spawnScatter(state, env, false)
      x = state.sourceX
      y = state.sourceY
    end
  end

  env.screen:drawSurface(cardSurf, floor(x), floor(y + state.yDrift))
end

local function spawnLaneSweep(state, env, isInitial)
  refreshCard(state, env)
  local laneFraction
  if state.total <= 1 then
    laneFraction = 0.5
  else
    laneFraction = (state.index - 1) / (state.total - 1)
  end
  state.sourceX = centerCardX(env)
  state.sourceY = -env.cardBack.height - math.random(8)
  state.targetX = floor(laneFraction * max(1, env.width - env.cardBack.width))
  state.targetY = floor(env.height * 0.28 + (laneFraction * env.height * 0.22))
  state.dealProgress = isInitial and math.random() or 0
  state.dealSpeed = randomFloat(0.05, 0.08)
  state.holdFrames = 3 + math.random(6)
  state.sweepDirection = laneFraction < 0.5 and -1 or 1
  state.sweepSpeed = randomFloat(1.1, 1.8)
  state.phase = "deal"
  state.x = state.sourceX
  state.y = state.sourceY
end

local function stepLaneSweep(env, state, cardSurf)
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
      state.phase = "sweep"
    end
  else
    state.x = state.x + (state.sweepDirection * state.sweepSpeed)
    state.y = state.targetY + state.yDrift
    if state.x < -env.cardBack.width or state.x > env.width + env.cardBack.width then
      spawnLaneSweep(state, env, false)
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

M.fan = {
  description = "Cards bloom from a center stack into a table fan.",
  spawn = spawnFan,
  step = stepFan,
}

M.flip = {
  description = "Face-down cards glide across the felt and reveal mid-flight.",
  spawn = spawnFlip,
  step = stepFlip,
}

M.cascade = {
  description = "Cards cascade diagonally like a dealer riffling across the table.",
  spawn = spawnCascade,
  step = stepCascade,
}

M.orbit = {
  description = "Cards drift on a slow oval orbit around the table center.",
  spawn = spawnOrbit,
  step = stepOrbit,
}

M.cut = {
  description = "Two packets split, cross, and merge like a deck cut.",
  spawn = spawnCut,
  step = stepCut,
}

M.peek = {
  description = "Cards peek in from the edges, pause, and tuck away again.",
  spawn = spawnPeek,
  step = stepPeek,
}

M.scatter = {
  description = "Cards burst from center, settle around the felt, then collect.",
  spawn = spawnScatter,
  step = stepScatter,
}

M.lane_sweep = {
  description = "Cards deal into fixed lanes, then sweep out like player seats clearing.",
  spawn = spawnLaneSweep,
  step = stepLaneSweep,
}

return M