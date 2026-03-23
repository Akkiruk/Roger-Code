-- baccarat_config.lua
-- Centralized configuration for the Baccarat game.
-- All tunable constants in one place.

return {
  -- Game rules
  DECK_COUNT          = 8,       -- standard baccarat shoe (8 decks)
  BURN_CARDS          = 1,       -- burn cards after shuffle
  MIN_CARDS_RESHUFFLE = 30,      -- reshuffle when shoe drops below this

  -- Payouts
  PLAYER_PAYOUT       = 1,       -- 1:1
  BANKER_PAYOUT       = 1,       -- 1:1 (minus commission)
  BANKER_COMMISSION   = 0.05,    -- 5% commission on banker wins
  TIE_PAYOUT          = 8,       -- 8:1

  -- Economy
  MAX_BET_PERCENT     = 0.11,    -- max bet = 11% of host balance (must stay <= 1/9 for 8:1 tie)
  HOST_COVERAGE_MULT  = 9,       -- host must hold bet * this to cover tie payout
  INACTIVITY_TIMEOUT  = 30000,   -- ms before auto-exit with no bet

  -- Peripheral sides
  MONITOR             = "right",
  REDSTONE            = "left",

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY     = 0.05,
  AUTO_PLAY_BET       = 9,

  -- Admin & logging
  GAME_NAME           = "Baccarat",
  LOG_FILE            = "baccarat_error.log",
  RECOVERY_FILE       = "baccarat_recovery.dat",

  -- Canonical bet types
  BET_TYPES = {
    PLAYER = "player",
    BANKER = "banker",
    TIE    = "tie",
  },

  -- Canonical outcome names
  OUTCOMES = {
    PLAYER_WIN = "player win",
    BANKER_WIN = "banker win",
    TIE        = "tie",
  },

  -- UI layout tweaks (pixel offsets)
  LAYOUT = {
    PLAYER_LABEL_Y    = 2,
    BANKER_LABEL_Y    = 2,
    PLAYER_CARDS_Y    = 10,
    BANKER_CARDS_Y    = 10,
    SCORE_Y_OFFSET    = 6,
    CARD_SPACING      = 2,
    TABLE_COLOR       = colors.green,
    STATUS_Y_OFFSET   = 0,       -- 0 = center of screen
    RESULT_PAUSE      = 2.0,     -- seconds to show result
  },

  -- Exit codes
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
  },
}
