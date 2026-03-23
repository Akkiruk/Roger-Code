-- slots_config.lua
-- Configuration for the Slot Machine game.

return {
  -- Peripheral sides
  MONITOR  = "right",
  REDSTONE = "left",    -- auto-play trigger

  -- Economy
  MAX_BET_PERCENT     = 0.005,  -- max bet = 0.5% of host balance (jackpot-safe: worst case takes ~50%)
  HOST_COVERAGE_MULT  = 100,    -- host must hold bet * this to accept wagers (= jackpot multiplier)
  INACTIVITY_TIMEOUT  = 30000,  -- ms before auto-exit

  -- Auto-play
  AUTO_PLAY_DELAY = 0.3,
  AUTO_PLAY_BET   = 9,

  -- Admin & logging
  GAME_NAME     = "Slots",
  LOG_FILE      = "slots_error.log",
  RECOVERY_FILE = "slots_recovery.dat",

  -- Reel symbols (name, color, weight)
  -- Weight controls how often it appears on each reel.
  -- Lower weight = rarer. Weights don't need to sum to anything specific.
  SYMBOLS = {
    { id = "7",       label = "7",   color = colors.red,       weight = 2,  art = "seven.nfp"   },
    { id = "diamond", label = "<>",  color = colors.blue,      weight = 3,  art = "diamond.nfp" },
    { id = "bell",    label = "$$",  color = colors.yellow,    weight = 5,  art = "bell.nfp"    },
    { id = "bar",     label = "BAR", color = colors.red,       weight = 7,  art = "bar.nfp"     },
    { id = "cherry",  label = "@@",  color = colors.red,       weight = 9,  art = "cherry.nfp"  },
    { id = "lemon",   label = "##",  color = colors.yellow,    weight = 10, art = "lemon.nfp"   },
    { id = "melon",   label = "~~",  color = colors.lime,      weight = 10, art = "melon.nfp"   },
  },

  -- Payouts: multiplier of the bet for 3-of-a-kind.
  -- Two-of-a-kind pays 1/5 of the listed multiplier, rounded down.
  --
  -- House edge math (total weight per reel = 46):
  --   3-of-a-kind EV  ~0.187  (per unit bet)
  --   2-of-a-kind EV  ~0.712
  --   Total RTP        ~0.899  (≈90%)
  --   House edge        ~10%
  PAYOUTS = {
    ["7"]       = 100,  -- JACKPOT
    ["diamond"] = 50,
    ["bell"]    = 20,
    ["bar"]     = 10,
    ["cherry"]  = 7,
    ["lemon"]   = 3,
    ["melon"]   = 2,
  },

  -- Special combos
  ANY_TWO_CHERRY_MULT = 1,  -- any 2 cherries = 1x bet back (small win)

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
    REEL_Y         = 12,              -- top of reel display area
    REEL_HEIGHT    = 20,              -- height of each reel cell
    REEL_SPACING   = 4,               -- gap between reels
    REEL_WIDTH     = 18,              -- width of each reel cell
    BUTTON_Y_OFFSET = 14,
    TITLE_Y        = 1,
  },

  -- Exit codes
  EXIT_CODES = {
    INACTIVITY_TIMEOUT = "inactivity_timeout",
    MAIN_MENU          = "main_menu",
    USER_TERMINATED    = "user_terminated",
  },
}
