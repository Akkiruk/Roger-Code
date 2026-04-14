return {
  DECK_COUNT = 6,
  MIN_CARDS_RESHUFFLE = 156,
  DEALER_STAND = 18,
  DEALER_HIT_SOFT_17 = true,
  DEALER_CHASE_TOTAL = 18,
  BLACKJACK_PAYOUT = 1.2,
  ALLOW_SPLIT = true,
  ALLOW_DOUBLE = true,
  ALLOW_DOUBLE_AFTER_SPLIT = false,
  DOUBLE_MIN_TOTAL = 10,
  DOUBLE_MAX_TOTAL = 11,
  ALLOW_SOFT_DOUBLE = false,
  ALLOW_INSURANCE = false,
  ALLOW_SURRENDER = false,
  MAX_SPLITS = 1,
  RESTRICT_SPLIT_ACES = true,

  MAX_BET_TOKENS = 100,
  MAX_BET_PERCENT = 0.036,
  HOST_COVERAGE_MULT = 5,
  INACTIVITY_TIMEOUT = 90000,

  MONITOR = "right",

  GAME_NAME = "Blackjack",
  LOG_FILE = "blackjack_error.log",
  RECOVERY_FILE = "blackjack_recovery.dat",

  ACTIONS = {
    HIT = "hit",
    STAND = "stand",
    DOUBLE = "double",
    SPLIT = "split",
    SURRENDER = "surrender",
  },

  OUTCOMES = {
    PLAYER_WIN = "player win",
    DEALER_WIN = "dealer win",
    BLACKJACK = "blackjack",
    BUST = "bust",
    PUSH = "push",
  },

  LAYOUT = {
    DEALER_Y = 8,
    PLAYER_Y_OFFSET = 2,
    BUTTON_Y_OFFSET = 14,
    DEALER_SCORE_Y = 14,
    SCORE_Y_OFFSET = 6,
    CARD_SPACING = 2,
    TABLE_COLOR = colors.green,
  },

  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU = "main_menu",
    USER_TERMINATED = "user_terminated",
    PLAYER_QUIT = "player_quit",
  },
}
