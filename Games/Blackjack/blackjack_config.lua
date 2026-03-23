-- blackjack_config.lua
-- Centralized configuration for the Blackjack game.
-- All tunable constants in one place; nothing else should hardcode these values.

return {
  -- Game rules
  DECK_COUNT          = 6,
  DEALER_STAND        = 17,
  DEALER_HIT_SOFT_17  = true,    -- dealer hits on soft 17 (+0.20% house edge)
  BLACKJACK_PAYOUT    = 1.5,    -- 3:2 payout for natural blackjack
  ALLOW_SPLIT         = true,
  ALLOW_INSURANCE     = true,
  ALLOW_SURRENDER     = false,
  MAX_SPLITS          = 1,       -- max times a player can split per round
  RESTRICT_SPLIT_ACES = true,    -- split aces receive only one card each (+0.19% house edge)

  -- Economy
  MAX_BET_PERCENT     = 0.18,    -- max bet = 18% of host balance
  HOST_COVERAGE_MULT  = 3,       -- host must hold bet * this to accept wager
  INACTIVITY_TIMEOUT  = 30000,   -- ms before auto-exit with no bet

  -- Peripheral sides
  MONITOR             = "right",
  REDSTONE            = "left",

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY          = 0.05,
  AUTO_PLAY_BET            = 9,
  STRATEGY_CHANGE_FREQ     = 10,

  -- Admin & logging
  ADMIN_NAME          = "Akkiruk",
  GAME_NAME           = "Blackjack",
  LOG_FILE            = "blackjack_error.log",
  RECOVERY_FILE       = "blackjack_recovery.dat",

  -- Canonical action names (used in actionLog & stats)
  ACTIONS = {
    HIT       = "hit",
    STAND     = "stand",
    DOUBLE    = "double",
    SPLIT     = "split",
    SURRENDER = "surrender",
  },

  -- Canonical outcome names
  OUTCOMES = {
    PLAYER_WIN = "player win",
    DEALER_WIN = "dealer win",
    BLACKJACK  = "blackjack",
    BUST       = "bust",
    PUSH       = "push",
  },

  -- UI layout tweaks (pixel offsets from screen edges)
  LAYOUT = {
    DEALER_Y          = 2,
    PLAYER_Y_OFFSET   = 2,      -- cards from bottom
    BUTTON_Y_OFFSET   = 14,     -- buttons above player cards
    DEALER_SCORE_Y    = 8,
    SCORE_Y_OFFSET    = 6,
    CARD_SPACING      = 2,      -- px gap between cards
    TABLE_COLOR       = colors.green,
  },

  -- Exit codes (intentional, non-error shutdowns)
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
  },
}
