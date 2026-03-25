return {
  MONITOR = "right",
  REDSTONE = "left",

  MAX_BET_PERCENT = 0.005,
  HOST_COVERAGE_MULT = 101,
  INACTIVITY_TIMEOUT = 30000,

  AUTO_PLAY_DELAY = 0.3,
  AUTO_PLAY_BET = 9,

  GAME_NAME = "Slots",
  LOG_FILE = "slots_error.log",
  RECOVERY_FILE = "slots_recovery.dat",

  SYMBOLS = {
    { id = "7", label = "7", color = colors.red, weight = 2, art = "seven.nfp" },
    { id = "diamond", label = "<>", color = colors.blue, weight = 3, art = "diamond.nfp" },
    { id = "bell", label = "$$", color = colors.yellow, weight = 5, art = "bell.nfp" },
    { id = "bar", label = "BAR", color = colors.red, weight = 7, art = "bar.nfp" },
    { id = "cherry", label = "@@", color = colors.red, weight = 9, art = "cherry.nfp" },
    { id = "lemon", label = "##", color = colors.yellow, weight = 10, art = "lemon.nfp" },
    { id = "melon", label = "~~", color = colors.lime, weight = 10, art = "melon.nfp" },
  },

  PAYOUTS = {
    ["7"] = 100,
    ["diamond"] = 50,
    ["bell"] = 20,
    ["bar"] = 10,
    ["cherry"] = 7,
    ["lemon"] = 3,
    ["melon"] = 2,
  },

  TWO_OF_A_KIND_PAYOUTS = {
    ["7"] = 10,
    ["diamond"] = 5,
    ["bell"] = 2,
    ["bar"] = 2,
    ["cherry"] = 2,
    ["lemon"] = 0,
    ["melon"] = 0,
  },

  ANY_TWO_CHERRY_MULT = 0,

  REEL_SPIN_TICKS = { 12, 18, 24 },
  SPIN_FRAME_DELAY = 0.04,

  PALETTE = {
    [colors.brown] = 0x1A0033,
  },

  LAYOUT = {
    TABLE_COLOR = colors.brown,
    REEL_BG = colors.black,
    REEL_Y = 12,
    REEL_HEIGHT = 20,
    REEL_SPACING = 4,
    REEL_WIDTH = 18,
    BUTTON_Y_OFFSET = 14,
    TITLE_Y = 1,
  },

  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU = "main_menu",
    USER_TERMINATED = "user_terminated",
    PLAYER_QUIT = "player_quit",
  },
}
