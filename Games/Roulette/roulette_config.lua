-- roulette_config.lua
-- Centralized configuration for the Roulette game.
-- All tunable constants in one place; nothing else should hardcode these values.

return {
  -- Peripheral sides
  MONITOR  = "right",
  REDSTONE = "left",

  -- Economy
  MAX_BET_PERCENT     = 0.10,    -- max bet = 10% of host balance (coverage limits inside bets)
  HOST_COVERAGE_MULT  = 36,      -- host must hold bet * this to accept wager
  INACTIVITY_TIMEOUT  = 30000,   -- ms before auto-exit with no bet

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY = 0.3,
  AUTO_PLAY_BET   = 9,

  -- Admin & logging
  GAME_NAME     = "Roulette",
  LOG_FILE      = "roulette_error.log",
  RECOVERY_FILE = "roulette_recovery.dat",

  -- Spin animation
  SPIN_TICKS       = 40,     -- total animation frames
  SPIN_FRAME_DELAY = 0.04,   -- seconds between frames
  RESULT_PAUSE     = 2.0,    -- seconds to display result

  -- Bet types with their payouts (payout is net winnings, not including original bet)
  BET_TYPES = {
    -- Inside bets
    { id = "straight", label = "Straight Up", payout = 35, description = "Single number" },
    -- Outside bets
    { id = "red",      label = "Red",         payout = 1,  description = "All red numbers" },
    { id = "black",    label = "Black",       payout = 1,  description = "All black numbers" },
    { id = "odd",      label = "Odd",         payout = 1,  description = "All odd numbers" },
    { id = "even",     label = "Even",        payout = 1,  description = "All even numbers" },
    { id = "low",      label = "1-18",        payout = 1,  description = "Numbers 1-18" },
    { id = "high",     label = "19-36",       payout = 1,  description = "Numbers 19-36" },
    { id = "dozen1",   label = "1st 12",      payout = 2,  description = "Numbers 1-12" },
    { id = "dozen2",   label = "2nd 12",      payout = 2,  description = "Numbers 13-24" },
    { id = "dozen3",   label = "3rd 12",      payout = 2,  description = "Numbers 25-36" },
    { id = "col1",     label = "Col 1",       payout = 2,  description = "Column 1 (1,4,7...34)" },
    { id = "col2",     label = "Col 2",       payout = 2,  description = "Column 2 (2,5,8...35)" },
    { id = "col3",     label = "Col 3",       payout = 2,  description = "Column 3 (3,6,9...36)" },
  },

  -- The wheel numbers in order (European single-zero roulette)
  WHEEL_ORDER = {
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36,
    11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9,
    22, 18, 29, 7, 28, 12, 35, 3, 26,
  },

  -- Red numbers on a standard roulette wheel
  RED_NUMBERS = {
    1, 3, 5, 7, 9, 12, 14, 16, 18,
    19, 21, 23, 25, 27, 30, 32, 34, 36,
  },

  -- UI layout
  LAYOUT = {
    TABLE_COLOR     = colors.green,
    WHEEL_Y         = 4,
    WHEEL_RADIUS    = 12,
    BET_SELECT_Y    = 22,
    BUTTON_Y_OFFSET = 14,
    TITLE_Y         = 1,
    NUMBER_SIZE     = 5,
  },

  -- Palette overrides
  PALETTE = {},

  -- Exit codes (intentional, non-error shutdowns)
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
