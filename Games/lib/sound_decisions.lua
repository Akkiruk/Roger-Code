local M = {}

local DEFAULT_ROLE_DECISIONS = {
  ui_error = {
    primary = "the_vault:mob_trap",
    fallback = { "the_vault:puzzle_completion_fail" },
    rationale = "Negative feedback should stay short and clearly distinct from win cues.",
    confidence = 0.75,
  },
  boot = {
    primary = "buildinggadgets:beep",
    fallback = { "the_vault:artifact_complete" },
    rationale = "Boot cues should be brief and readable instead of sounding like a payout.",
    confidence = 0.65,
  },
  bet_place_inside = {
    primary = "the_vault:coin_single_place",
    fallback = { "lightmanscurrency:coins_clinking" },
    rationale = "Inside bets benefit from a small precise currency cue.",
    confidence = 0.8,
  },
  bet_place_outside = {
    primary = "lightmanscurrency:coins_clinking",
    fallback = { "the_vault:coin_pile_place" },
    rationale = "Outside bets can use a broader, slightly fuller currency cue.",
    confidence = 0.8,
  },
  chip_select = {
    primary = "buildinggadgets:beep",
    fallback = { "quark:ambient.clock" },
    rationale = "Chip select should read like a utility click rather than a dramatic event.",
    confidence = 0.7,
  },
  spin_start = {
    primary = "the_vault:raid_gate_open",
    fallback = { "the_vault:artifact_complete" },
    rationale = "Spin start should feel weighty and anticipatory without sounding like a win.",
    confidence = 0.9,
  },
  spin_tick = {
    primary = "quark:ambient.clock",
    fallback = { "buildinggadgets:beep" },
    rationale = "Tick sounds need to survive frequent repetition without getting grating.",
    confidence = 0.85,
  },
  spin_slowdown = {
    primary = "lightmanscurrency:coins_clinking",
    fallback = { "quark:ambient.clock" },
    rationale = "The slowdown cue should add a bit more weight than the rapid spin tick.",
    confidence = 0.72,
  },
  spin_final = {
    primary = "the_vault:coin_pile_place",
    fallback = { "the_vault:raid_gate_open" },
    rationale = "The final lock-in should feel decisive and heavier than the rolling ticks.",
    confidence = 0.8,
  },
  win_small = {
    primary = "the_vault:puzzle_completion_major",
    fallback = { "the_vault:rampage" },
    rationale = "Wins should clearly separate from neutral and failure cues.",
    confidence = 0.8,
  },
  win_big = {
    primary = "the_vault:puzzle_completion_major",
    fallback = { "the_vault:artifact_complete", "the_vault:raid_gate_open" },
    rationale = "Big wins should be celebratory and high-stakes.",
    confidence = 0.74,
  },
  loss = {
    primary = "the_vault:puzzle_completion_fail",
    fallback = { "the_vault:mob_trap" },
    rationale = "Loss cues should be readable immediately and never sound rewarding.",
    confidence = 0.86,
  },
  push = {
    primary = "the_vault:rampage",
    fallback = { "buildinggadgets:beep" },
    rationale = "Push should feel distinct from both wins and losses while still resolving the round.",
    confidence = 0.62,
  },
  timeout_warning = {
    primary = "the_vault:robot_death",
    fallback = { "the_vault:mob_trap" },
    rationale = "Timeout warnings need urgency, but they also need to loop tolerably.",
    confidence = 0.68,
  },
}

local GAME_DECISIONS = {
  roulette = {
    sounds = {
      BET_INSIDE = { role = "bet_place_inside" },
      BET_OUTSIDE = { role = "bet_place_outside" },
      CHIP_SELECT = { role = "chip_select" },
      SPIN_START = { role = "spin_start" },
      SPIN_POINTER = { role = "spin_tick", primary = "quark:ambient.clock" },
      SPIN_TICK = { role = "spin_tick" },
      SPIN_SLOW = { role = "spin_slowdown" },
      SPIN_FINAL = { role = "spin_final" },
      RESULT_WIN = { role = "win_small" },
      RESULT_LOSS = { role = "loss" },
      RESULT_PUSH = { role = "push" },
    },
  },
}

local function copyList(items)
  local result = {}
  local index = 1

  while type(items) == "table" and index <= #items do
    result[index] = items[index]
    index = index + 1
  end

  return result
end

local function choosePrimary(roleId, override, fallback)
  local roleDecision = DEFAULT_ROLE_DECISIONS[roleId] or nil

  if type(override) == "string" and override ~= "" then
    return override
  end

  if roleDecision and type(roleDecision.primary) == "string" and roleDecision.primary ~= "" then
    return roleDecision.primary
  end

  return fallback
end

function M.getRole(roleId)
  local roleDecision = DEFAULT_ROLE_DECISIONS[roleId]
  if not roleDecision then
    return nil
  end

  return {
    primary = roleDecision.primary,
    fallback = copyList(roleDecision.fallback),
    rationale = roleDecision.rationale,
    confidence = roleDecision.confidence,
  }
end

function M.resolveSound(gameId, key, fallback)
  local game = GAME_DECISIONS[gameId]
  local soundDecision = game and game.sounds and game.sounds[key] or nil
  local primary = nil

  if not soundDecision then
    return fallback
  end

  primary = choosePrimary(soundDecision.role, soundDecision.primary, fallback)
  return primary or fallback
end

function M.buildGameSoundMap(gameId, fallbacks)
  local game = GAME_DECISIONS[gameId]
  local result = {}
  local key = nil
  local value = nil

  for key, value in pairs(fallbacks or {}) do
    result[key] = value
  end

  if not game or type(game.sounds) ~= "table" then
    return result
  end

  for key, value in pairs(game.sounds) do
    result[key] = M.resolveSound(gameId, key, result[key])
  end

  return result
end

return M
