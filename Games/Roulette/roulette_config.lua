local soundDecisions = require("lib.sound_decisions")

-- roulette_config.lua
-- Centralized configuration for the Roulette game.
-- All tunable constants in one place; nothing else should hardcode these values.

return {
  -- Peripheral sides
  MONITOR  = "right",
  REDSTONE = "left",

  -- Economy
  MAX_BET_PERCENT     = 0.10,    -- per-wager net-win cap = 10% of host balance (actual spot limit scales by payout)
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
  SPIN_FULL_ROTATIONS = 2,      -- extra full loops before settling on the winning number
  SPIN_MIN_DELAY      = 0.010,  -- fastest per-number delay during the early spin
  SPIN_MAX_DELAY      = 0.055,  -- slowest per-number delay right before the final stop
  SPIN_SETTLE_DELAY   = 0.030,  -- bounce delay for the final lock-in
  SPIN_FAST_SUBFRAMES = 1,      -- early spin interpolation steps per number
  SPIN_SLOW_SUBFRAMES = 2,      -- late spin interpolation steps per number
  SPIN_SLOWDOWN_AT    = 0.78,   -- progress point where the wheel starts using extra interpolation
  RESULT_PAUSE        = 2.4,    -- seconds to display result
  HISTORY_LENGTH      = 10,

  -- Track rendering
  TRACK_WINDOW_SLOTS        = 9, -- visible numbers in the spin window on roomy monitors
  TRACK_COMPACT_WINDOW_SLOTS = 7,
  TRACK_SLOT_GAP            = 2,
  TRACK_COMPACT_SLOT_GAP    = 1,

  -- Roulette-specific sound effects
  SOUND_IDS = soundDecisions.buildGameSoundMap("roulette", {
    BET_INSIDE = "the_vault:coin_single_place",
    BET_OUTSIDE = "lightmanscurrency:coins_clinking",
    CHIP_SELECT = "buildinggadgets:beep",
    SPIN_START = "the_vault:raid_gate_open",
    SPIN_POINTER = "quark:ambient.clock",
    SPIN_TICK = "quark:ambient.clock",
    SPIN_SLOW = "lightmanscurrency:coins_clinking",
    SPIN_FINAL = "the_vault:coin_pile_place",
    RESULT_WIN = "the_vault:puzzle_completion_major",
    RESULT_LOSS = "the_vault:puzzle_completion_fail",
    RESULT_PUSH = "the_vault:rampage",
  }),

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
  PALETTE = {
    [colors.black]     = 0x101618,
    [colors.gray]      = 0x2a363d,
    [colors.lightGray] = 0xd6d0c2,
    [colors.white]     = 0xf6f1e6,
    [colors.green]     = 0x174a2d,
    [colors.lime]      = 0x3d8f56,
    [colors.yellow]    = 0xd5b46a,
    [colors.orange]    = 0xb87a32,
    [colors.red]       = 0x9b3d34,
    [colors.brown]     = 0x6a4a2c,
    [colors.cyan]      = 0x6ba8b0,
    [colors.lightBlue] = 0x92aebe,
    [colors.magenta]   = 0x9a6c7f,
    [colors.purple]    = 0x735b7d,
  },

  -- Exit codes (intentional, non-error shutdowns)
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
