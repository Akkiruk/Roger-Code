-- hilo_config.lua
-- Centralized configuration for the Hi-Lo card game.
-- All tunable constants in one place.

return {
  -- Game rules
  DECK_COUNT          = 1,       -- single deck
  MIN_CARDS_RESHUFFLE = 10,      -- reshuffle when deck drops below this
  RESHUFFLE_EACH_ROUND = true,   -- start every round from a fresh deck to block shoe counting

  -- Payout multipliers for consecutive correct guesses.
  -- Tuned for roughly 90% RTP with round-to-nearest token payouts.
  -- Same-value cards lose, so the ladder can stay exciting without turning
  -- edge cards into a guaranteed profit source for the player.
  MULTIPLIERS = { 1.2, 1.45, 1.9, 2.35, 3.3, 4.2, 5.7, 7.6, 10.4, 14.2 },
  MAX_ROUNDS  = 10,              -- cap at 10 correct guesses

  -- Economy
  MAX_BET_PERCENT     = 0.03,    -- conservative table cap; max total return is 14.2x
  HOST_COVERAGE_MULT  = 15,      -- slightly conservative coverage for the 14.2x max return
  INACTIVITY_TIMEOUT  = 90000,   -- ms before auto-exit with no bet
  PRE_ROUND_MENU_TIMEOUT = 10000, -- ms before auto-exit on the title/menu screen

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
