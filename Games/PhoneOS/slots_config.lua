-- slots_config.lua
-- Pocket-install copy of the shared Slots configuration.
-- Keep this aligned with Games/Slots/slots_config.lua.

return {
  -- Peripheral sides
  MONITOR  = "right",
  REDSTONE = "left",    -- auto-play trigger

  -- Economy
  MAX_BET_PERCENT     = 0.005,  -- max bet = 0.5% of host balance (jackpot-safe: worst case takes ~50%)
  HOST_COVERAGE_MULT  = 101,    -- conservative coverage buffer for the 100x top line
  INACTIVITY_TIMEOUT  = 90000,  -- ms before auto-exit

  -- Auto-play
  AUTO_PLAY_DELAY = 0.3,
  AUTO_PLAY_BET   = 9,

  -- Admin & logging
  GAME_NAME     = "Slots",
  LOG_FILE      = "slots_error.log",
  RECOVERY_FILE = "slots_recovery.dat",

  -- Reel symbols (name, color, weight)
  SYMBOLS = {
    { id = "7",       label = "7",   color = colors.red,       weight = 2,  art = "seven.nfp"   },
    { id = "diamond", label = "<>",  color = colors.blue,      weight = 3,  art = "diamond.nfp" },
    { id = "bell",    label = "$$",  color = colors.yellow,    weight = 5,  art = "bell.nfp"    },
    { id = "bar",     label = "BAR", color = colors.red,       weight = 7,  art = "bar.nfp"     },
    { id = "cherry",  label = "@@",  color = colors.red,       weight = 9,  art = "cherry.nfp"  },
    { id = "lemon",   label = "##",  color = colors.yellow,    weight = 10, art = "lemon.nfp"   },
    { id = "melon",   label = "~~",  color = colors.lime,      weight = 10, art = "melon.nfp"   },
  },

  -- Gross return multipliers for 3-of-a-kind.
  -- These include the original stake, so 1 means a push, 2 means double back, etc.
  PAYOUTS = {
    ["7"]       = 100,  -- JACKPOT
    ["diamond"] = 50,
    ["bell"]    = 20,
    ["bar"]     = 10,
    ["cherry"]  = 7,
    ["lemon"]   = 3,
    ["melon"]   = 2,
  },

  -- Gross return multipliers for any paying pair.
  -- Common fruit pairs now return at least the stake, while the overall cabinet
  -- still lands close to a 10% edge with the current reel weights.
  TWO_OF_A_KIND_PAYOUTS = {
    ["7"]       = 10,
    ["diamond"] = 6,
    ["bell"]    = 2,
    ["bar"]     = 2,
    ["cherry"]  = 2,
    ["lemon"]   = 1,
    ["melon"]   = 1,
  },

  -- Special combos
  ANY_TWO_CHERRY_MULT = 0,  -- cherry pairs are handled in TWO_OF_A_KIND_PAYOUTS

  -- Animation
  REEL_SPIN_TICKS = { 12, 18, 24 },  -- each reel spins a different number of frames
  SPIN_FRAME_DELAY = 0.04,            -- seconds between animation frames

  -- Palette remaps (CC color -> custom RGB)
  PALETTE = {
    [colors.brown] = 0x1A0033,  -- deep purple
  },

  -- UI Layout (pixel coords for Surface API)
  LAYOUT = {
    TABLE_COLOR    = colors.brown,     -- remapped via PALETTE above
    REEL_BG        = colors.black,
    REEL_Y         = 15,               -- top of reel display area
    REEL_HEIGHT    = 20,               -- height of each reel cell
    REEL_SPACING   = 4,                -- gap between reels
    REEL_WIDTH     = 18,               -- width of each reel cell
    BUTTON_Y_OFFSET = 14,
    TITLE_Y        = 1,
  },

  -- Exit codes
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
    PLAYER_QUIT        = "player_quit",
  },
}
