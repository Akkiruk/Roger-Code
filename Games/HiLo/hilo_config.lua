-- hilo_config.lua
-- Centralized configuration for the Hi-Lo card game.
-- All tunable constants in one place.

return {
  -- Game rules
  DECK_COUNT          = 1,       -- single deck
  MIN_CARDS_RESHUFFLE = 10,      -- reshuffle when deck drops below this

  -- Payout multipliers for consecutive correct guesses
  -- Round 1 correct = 1.5x, Round 2 = 2x, etc.
  MULTIPLIERS = { 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32 },
  MAX_ROUNDS  = 10,              -- cap at 10 correct guesses

  -- Economy
  MAX_BET_PERCENT     = 0.03,    -- max bet = 3% of host balance (must cover 32x worst case)
  HOST_COVERAGE_MULT  = 32,      -- host must hold bet * this to cover max payout
  INACTIVITY_TIMEOUT  = 30000,   -- ms before auto-exit with no bet

  -- Peripheral sides
  MONITOR             = "right",
  REDSTONE            = "left",

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY     = 0.05,
  AUTO_PLAY_BET       = 5,

  -- Admin & logging
  GAME_NAME           = "HiLo",
  LOG_FILE            = "hilo_error.log",
  RECOVERY_FILE       = "hilo_recovery.dat",

  -- UI layout tweaks (pixel offsets)
  LAYOUT = {
    TABLE_COLOR   = colors.green,
    RESULT_PAUSE  = 1.5,         -- seconds to show result
    CARD_Y        = 10,          -- vertical position for cards
  },

  -- Exit codes
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
