-- videopoker_config.lua
-- Centralized configuration for the Video Poker (Jacks or Better) game.
-- All tunable constants in one place.

return {
  -- Game rules
  DECK_COUNT          = 1,       -- single deck, reshuffled each hand
  HAND_SIZE           = 5,       -- standard 5-card draw

  -- Jacks or Better payout table (multiplier on bet)
  -- Order matters: evaluated top-down, first match wins
  PAYOUTS = {
    { name = "Royal Flush",     multiplier = 250 },
    { name = "Straight Flush",  multiplier = 50 },
    { name = "Four of a Kind",  multiplier = 25 },
    { name = "Full House",      multiplier = 9 },
    { name = "Flush",           multiplier = 6 },
    { name = "Straight",        multiplier = 4 },
    { name = "Three of a Kind", multiplier = 3 },
    { name = "Two Pair",        multiplier = 2 },
    { name = "Jacks or Better", multiplier = 1 },
  },

  -- Economy
  MAX_BET_PERCENT     = 0.004,   -- max bet = 0.4% of host balance (must cover 250x royal flush)
  HOST_COVERAGE_MULT  = 251,     -- total payout multiplier on a royal (stake + 250x win)
  INACTIVITY_TIMEOUT  = 90000,   -- ms before auto-exit with no input

  -- Peripheral sides
  MONITOR             = "right",
  REDSTONE            = "left",

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY     = 0.05,
  AUTO_PLAY_BET       = 5,

  -- Admin & logging
  GAME_NAME           = "VideoPoker",
  LOG_FILE            = "videopoker_error.log",
  RECOVERY_FILE       = "videopoker_recovery.dat",

  -- UI layout tweaks (pixel offsets)
  LAYOUT = {
    TABLE_COLOR   = colors.blue,
    RESULT_PAUSE  = 2.0,         -- seconds to show result
    CARD_Y        = 18,          -- vertical position for hand
    CARD_SPACING  = 5,           -- gap between cards
    HOLD_Y_OFFSET = 2,           -- pixels above card for HOLD label
    DISCARD_CARD_DROP = 2,       -- drop discarded cards slightly for better readability
  },

  -- Exit codes
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
