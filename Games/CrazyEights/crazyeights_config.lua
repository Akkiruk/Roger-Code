return {
  DECK_COUNT = 1,
  HAND_SIZE = 7,
  WIN_ROUNDS = 2,
  DRAW_CHAIN_CAP = 6,

  PAYOUTS = {
    WIN_SWEEP = 1.52,
    WIN_CLOSE = 1.42,
    LOSS_CLOSE = 0.50,
    LOSS_SWEEP = 0.38,
  },

  SCORE_VALUES = {
    EIGHT = 50,
    ACE = 1,
    FACE = 10,
  },

  MAX_BET_PERCENT = 0.03,
  HOST_COVERAGE_MULT = 1.52,

  MONITOR = "right",

  GAME_NAME = "CrazyEights",
  LOG_FILE = "crazyeights_error.log",
  RECOVERY_FILE = "crazyeights_recovery.dat",

  SOUND_IDS = {
    CRAZY_WILD = "minecraft:item.trident.thunder",
    CRAZY_SKIP = "minecraft:block.note_block.chime",
    CRAZY_DRAW = "lightmanscurrency:coins_clinking",
    CRAZY_MATCH = "the_vault:artifact_complete",
  },

  LAYOUT = {
    TABLE_COLOR = colors.green,
    RESULT_PAUSE = 1.4,
    DEALER_Y = 10,
    CENTER_Y = 34,
    PLAYER_BOTTOM_GAP = 6,
  },

  EXIT_CODES = {
    MAIN_MENU = "main_menu",
    USER_TERMINATED = "user_terminated",
    PLAYER_QUIT = "player_quit",
  },
}