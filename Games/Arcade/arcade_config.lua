-- arcade_config.lua
-- Settings, palette and sound map for the Arcade. Each game adds its own in games/<id>/.

local M = {}

M.NAME = "ARCADE"
M.LOG_FILE = "arcade.log"
M.PREFS_FILE = "arcade_prefs.dat"
M.DEBUG_FLAG = "arcade_debug.flag"

-- Peripherals. Names are discovered automatically; set a name only to pin a specific one.
M.MONITOR = nil            -- main wall (default: the largest monitor)
M.SCOREBOARD = nil         -- optional monitor that shows the leaderboard (default: any monitor that is not a wall)
M.TEXT_SCALE = 0.5

-- Players and presence
M.DETECT_RANGE = 12        -- blocks around the detector that count as "nearby"
M.TOUCH_NEARBY = 30        -- seconds a touch counts as being nearby, for rigs with no detector
M.PRESENCE_WARN = 20       -- seconds a mover may be away before the board says so
M.PRESENCE_LIMIT = 90      -- seconds away before the match ends: a forfeit if the opponent is here, otherwise called off
M.PAUSE_LIMIT = 60         -- seconds a pause may last before play carries on, so nobody can stall out a loss
M.MAX_PAUSES = 3           -- pauses in one match that stop the clock, for the same reason
M.WALL_GONE = 60           -- seconds a two-wall match waits for a lost wall before it is called off, with no result
M.LOBBY_IDLE = 120         -- seconds of no touch in the lobby before returning to the idle screen
M.RESULT_IDLE = 60
M.GAME_IDLE = 600          -- no moves for this long ends the match the same way as walking away
M.NUDGE_AFTER = 25         -- seconds before the chat box whispers a reminder to the mover
M.MAX_TIMEOUTS = 3         -- missed move timers before a forfeit
M.ATTRACT_SWAP = 30        -- seconds each game gets on the idle screen, when there are several

-- Redstone outputs (computer sides, or the integrator's sides when one is attached)
M.REDSTONE = { red = "left", blue = "right", celebrate = "top" }

-- Palette. Colour names are CC slots; the values are what the monitor shows. A game may replace some of them.
M.PALETTE = {
  black = 0x14161C,      -- background
  gray = 0x232733,       -- panels
  lightGray = 0x7C8496,  -- grid lines and dim text
  white = 0xF2F4F8,
  red = 0xE5484D,        -- Red player
  blue = 0x3E82F7,       -- Blue player
  brown = 0x4A2328,      -- Red's dark tint
  lightBlue = 0x1F3560,  -- Blue's dark tint
  yellow = 0xFFD257,     -- highlights, and the game's accent
  magenta = 0x3B3722,    -- highlight background tint
  green = 0x35D07F,
  orange = 0xFF9F43,
  purple = 0x9B7BFF,
  cyan = 0x3CD3E6,
  pink = 0x4A4F60,       -- tied areas
  lime = 0x8BE0A8,
}

-- Every sound is one the other games already use (the_vault, casinocraft, lightmanscurrency, quark,
-- buildinggadgets). Events share a few sounds and differ by pitch and volume.
M.SOUNDS = {
  tap       = { "buildinggadgets:beep", 0.35, 1.4 },
  select    = { "buildinggadgets:beep", 0.5, 1.0 },
  back      = { "buildinggadgets:beep", 0.35, 0.7 },
  error     = { "the_vault:mob_trap", 0.4, 1.0 },
  boot      = { "buildinggadgets:beep", 0.5, 1.0 },
  start     = { "the_vault:raid_gate_open", 0.6, 1.0 },
  tick      = { "quark:ambient.clock", 0.5, 1.5 },
  timeout   = { "the_vault:robot_death", 0.5, 1.0 },
  win       = { "the_vault:puzzle_completion_major", 0.9, 1.0 },
  winFanfare = { "the_vault:artifact_complete", 0.7, 1.0 },
  lose      = { "the_vault:puzzle_completion_fail", 0.5, 1.0 },
  draw      = { "the_vault:rampage", 0.45, 1.0 },
  resign    = { "the_vault:puzzle_completion_fail", 0.4, 0.8 },
  rank      = { "the_vault:coin_pile_place", 0.7, 1.0 },
  achievement = { "the_vault:artifact_complete", 0.55, 1.2 },
  page      = { "buildinggadgets:beep", 0.3, 1.2 },
  hint      = { "lightmanscurrency:coins_clinking", 0.4, 1.4 },
  presence  = { "the_vault:mob_trap", 0.25, 1.4 },
}

return M
