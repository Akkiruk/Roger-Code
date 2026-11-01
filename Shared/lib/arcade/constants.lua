-- arcade_constants.lua
-- Settings, palette and sound map for the Arcade. Each game adds its own in games/<id>/.

local picks = require("lib.sound_picks")

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
M.REPLAYS_KEPT = 5         -- finished matches kept for each game, to watch again
M.PAUSE_LIMIT = 60         -- seconds a pause may last before play carries on, so nobody can stall out a loss
M.MAX_PAUSES = 3           -- pauses in one match that stop the clock, for the same reason
M.WALL_GONE = 60           -- seconds a two-wall match waits for a lost wall before it is called off, with no result
M.LOBBY_IDLE = 120         -- seconds of no touch in the lobby before returning to the idle screen
M.GAME_IDLE = 600          -- no moves for this long ends the match the same way as walking away
M.NUDGE_AFTER = 25         -- seconds before the chat box whispers a reminder to the mover
M.MAX_TIMEOUTS = 3         -- missed move timers before a forfeit

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

-- The cabinet's own events. The sounds live in lib/sound_picks.lua.
M.SOUNDS = {
  tap = picks.ui_tap, select = picks.ui_select, back = picks.ui_back, error = picks.ui_error,
  boot = picks.ui_boot, start = picks.ui_start, tick = picks.ui_tick, timeout = picks.ui_timeout,
  win = picks.win_small, winFanfare = picks.win_big, lose = picks.lose, draw = picks.draw,
  resign = picks.resign, rank = picks.ui_rank, achievement = picks.ui_achievement,
  page = picks.ui_page, hint = picks.ui_hint, presence = picks.ui_presence,
}

return M
