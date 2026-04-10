-- blackjack_config.lua
-- Centralized configuration for the Blackjack game.
-- All tunable constants in one place; nothing else should hardcode these values.

return {
  -- Game rules
  DECK_COUNT          = 6,
  MIN_CARDS_RESHUFFLE = 156,     -- reshuffle with 3 decks left to starve card counting
  DEALER_STAND        = 17,
  DEALER_HIT_SOFT_17  = true,    -- fixed H17 dealer rules
  DEALER_CHASE_TOTAL  = 16,      -- set below DEALER_STAND to disable chase logic
  BLACKJACK_PAYOUT    = 1.0,     -- 1:1 payout for natural blackjack
  ALLOW_SPLIT         = true,
  ALLOW_DOUBLE        = true,
  ALLOW_DOUBLE_AFTER_SPLIT = false,
  DOUBLE_MIN_TOTAL    = 11,      -- doubles only on hard 11
  DOUBLE_MAX_TOTAL    = 11,
  ALLOW_SOFT_DOUBLE   = false,
  ALLOW_INSURANCE     = false,
  ALLOW_SURRENDER     = false,
  MAX_SPLITS          = 1,       -- max times a player can split per round
  RESTRICT_SPLIT_ACES = true,    -- split aces receive only one card each (+0.19% house edge)

  -- Economy
  MAX_BET_TOKENS      = 100,     -- absolute cap regardless of host bankroll
  MAX_BET_PERCENT     = 0.036,   -- max bet = 3.6% of host balance
  HOST_COVERAGE_MULT  = 5,       -- covers split + double exposure from the original wager
  INACTIVITY_TIMEOUT  = 90000,   -- ms before auto-exit with no bet

  -- Peripheral sides
  MONITOR             = "right",
  REDSTONE            = "left",

  -- Auto-play (redstone-driven bot testing)
  AUTO_PLAY_DELAY          = 0.05,
  AUTO_PLAY_BET            = 9,
  STRATEGY_CHANGE_FREQ     = 10,

  -- Admin & logging
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
    DEALER_Y          = 8,
    PLAYER_Y_OFFSET   = 2,      -- cards from bottom
    BUTTON_Y_OFFSET   = 14,     -- buttons above player cards
    DEALER_SCORE_Y    = 14,
    SCORE_Y_OFFSET    = 6,
    CARD_SPACING      = 2,      -- px gap between cards
    TABLE_COLOR       = colors.green,
  },

  -- Exit codes (intentional, non-error shutdowns)
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
