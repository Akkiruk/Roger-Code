return {
  DECK_COUNT = 6,
  MIN_CARDS_RESHUFFLE = 78,
  DEALER_STAND = 17,
  DEALER_HIT_SOFT_17 = true,
  BLACKJACK_PAYOUT = 1.5,
  ALLOW_SPLIT = true,
  ALLOW_INSURANCE = true,
  ALLOW_SURRENDER = false,
  MAX_SPLITS = 1,
  RESTRICT_SPLIT_ACES = true,

  MAX_BET_PERCENT = 0.18,
  HOST_COVERAGE_MULT = 5,
  INACTIVITY_TIMEOUT = 30000,

  MONITOR = "right",
  REDSTONE = "left",

  AUTO_PLAY_DELAY = 0.05,
  AUTO_PLAY_BET = 9,
  STRATEGY_CHANGE_FREQ = 10,

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
