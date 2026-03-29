local M = {}

M.LIST = {
  {
    id = "ui_move",
    label = "UI Move",
    description = "Frequent cursor or selection movement.",
    desired_tags = { "ui_candidate", "short", "repetition_safe", "low_intensity" },
    avoid_tags = { "music", "long_form", "creature", "aggressive", "high_intensity" },
  },
  {
    id = "ui_select",
    label = "UI Select",
    description = "Positive click for confirming a menu choice.",
    desired_tags = { "ui_candidate", "percussive", "short", "repetition_safe" },
    avoid_tags = { "music", "creature", "failure", "high_intensity" },
  },
  {
    id = "ui_back",
    label = "UI Back",
    description = "Soft cancel or back-out action.",
    desired_tags = { "ui_candidate", "short", "subtle", "low_intensity" },
    avoid_tags = { "success", "reward", "failure", "high_intensity" },
  },
  {
    id = "ui_error",
    label = "UI Error",
    description = "Denied or invalid input feedback.",
    desired_tags = { "failure", "danger", "short", "ui_candidate" },
    avoid_tags = { "music", "long_form", "celebration", "reward" },
  },
  {
    id = "boot",
    label = "Boot",
    description = "Program startup or machine wake-up cue.",
    desired_tags = { "start_cue", "transition", "mechanical", "dramatic" },
    avoid_tags = { "creature", "failure", "music", "long_form" },
  },
  {
    id = "bet_place_inside",
    label = "Bet Place In",
    description = "Inside bet placement on precise spots.",
    desired_tags = { "casino", "currency", "percussive", "short", "repetition_safe" },
    avoid_tags = { "music", "long_form", "creature", "high_intensity" },
  },
  {
    id = "bet_place_outside",
    label = "Bet Place Out",
    description = "Outside bet placement on broader betting areas.",
    desired_tags = { "casino", "currency", "percussive", "short", "medium_intensity" },
    avoid_tags = { "music", "creature", "failure", "high_intensity" },
  },
  {
    id = "chip_select",
    label = "Chip Select",
    description = "Picking denomination or changing wager chip.",
    desired_tags = { "casino", "currency", "ui_candidate", "short", "repetition_safe" },
    avoid_tags = { "music", "failure", "creature", "high_intensity" },
  },
  {
    id = "spin_start",
    label = "Spin Start",
    description = "Announces the start of a roulette spin.",
    desired_tags = { "transition", "dramatic", "high_stakes", "mechanical", "medium_high_intensity" },
    avoid_tags = { "music", "creature", "failure", "repetition_safe", "long_form" },
  },
  {
    id = "spin_tick",
    label = "Spin Tick",
    description = "Fast repeating wheel or pointer cadence.",
    desired_tags = { "tick", "precise", "mechanical", "short", "repetition_safe", "low_intensity" },
    avoid_tags = { "music", "creature", "high_intensity", "long_form" },
  },
  {
    id = "spin_slowdown",
    label = "Spin Slow",
    description = "Late-stage spin cadence with more weight.",
    desired_tags = { "tick", "precise", "mechanical", "medium_intensity" },
    avoid_tags = { "music", "creature", "failure", "high_intensity" },
  },
  {
    id = "spin_final",
    label = "Spin Final",
    description = "Final settling hit before the result lands.",
    desired_tags = { "impact", "dramatic", "mechanical", "medium_high_intensity" },
    avoid_tags = { "music", "creature", "failure", "long_form" },
  },
  {
    id = "win_small",
    label = "Win Small",
    description = "Modest reward or favorable outcome.",
    desired_tags = { "success", "reward", "short", "medium_intensity" },
    avoid_tags = { "failure", "creature", "music", "long_form" },
  },
  {
    id = "win_big",
    label = "Win Big",
    description = "Large payout or jackpot moment.",
    desired_tags = { "success", "reward", "celebration", "dramatic", "high_intensity", "high_stakes" },
    avoid_tags = { "failure", "creature", "repetition_safe" },
  },
  {
    id = "loss",
    label = "Loss",
    description = "Lost round or failed result.",
    desired_tags = { "failure", "danger", "medium_intensity" },
    avoid_tags = { "success", "reward", "music", "long_form" },
  },
  {
    id = "push",
    label = "Push",
    description = "Neutral result that should not feel too good or too bad.",
    desired_tags = { "transition", "subtle", "medium_intensity" },
    avoid_tags = { "failure", "reward", "celebration", "high_intensity" },
  },
  {
    id = "timeout_warning",
    label = "Timeout",
    description = "Warning that time is running out.",
    desired_tags = { "alert", "danger", "short", "repetition_safe", "medium_intensity" },
    avoid_tags = { "music", "creature", "reward", "long_form" },
  },
  {
    id = "alert",
    label = "Alert",
    description = "General attention-grabbing notification.",
    desired_tags = { "alert", "dramatic", "medium_intensity" },
    avoid_tags = { "music", "creature", "long_form" },
  },
}

M.BY_ID = {}

for _, role in ipairs(M.LIST) do
  M.BY_ID[role.id] = role
end

return M
