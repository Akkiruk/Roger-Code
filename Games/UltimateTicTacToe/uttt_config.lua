-- uttt_config.lua
-- Settings, palette and sound map for Ultimate Tic-Tac-Toe.

local picks = require("lib.sound_picks")

local M = {}

M.GAME_NAME = "Ultimate Tic-Tac-Toe"
M.DATA_FILE = "uttt_data.dat"
M.SAVE_FILE = "uttt_game.dat"   -- game in progress, so a crash or reboot resumes it
M.LOG_FILE = "uttt.log"

-- Peripherals. Names are discovered automatically; set a name only to pin a specific one.
M.MONITOR = nil            -- main wall (default: the largest monitor)
M.SCOREBOARD = nil         -- optional second monitor that shows the leaderboard (default: any other monitor)
M.TEXT_SCALE = 0.5

-- Players and presence
M.DETECT_RANGE = 12        -- blocks around the detector that count as "nearby"
M.PRESENCE_WARN = 20       -- seconds a mover may be away before the board says so
M.PRESENCE_ABANDON = 90    -- seconds away before the game is abandoned without a rating change
M.LOBBY_IDLE = 120         -- seconds of no touch in the lobby before returning to the idle screen
M.RESULT_IDLE = 60
M.GAME_IDLE = 600          -- no moves for this long: the game is abandoned
M.NUDGE_AFTER = 25         -- seconds before the chat box whispers a reminder to the mover
M.MAX_TIMEOUTS = 3         -- missed move timers before a forfeit

-- Redstone outputs (computer sides, or the integrator's sides when one is attached)
M.REDSTONE = { red = "left", blue = "right", celebrate = "top" }

-- Palette. Colour names are CC slots; the values are what the monitor shows.
M.PALETTE = {
  black = 0x14161C,      -- background
  gray = 0x232733,       -- panels
  lightGray = 0x7C8496,  -- grid lines and dim text
  white = 0xF2F4F8,
  red = 0xE5484D,        -- Red player
  blue = 0x3E82F7,       -- Blue player
  brown = 0x4A2328,      -- board won by Red (dark tint)
  lightBlue = 0x1F3560,  -- board won by Blue (dark tint)
  yellow = 0xFFD257,     -- active board and highlights
  magenta = 0x3B3722,    -- active board background tint
  green = 0x35D07F,
  orange = 0xFF9F43,
  purple = 0x9B7BFF,
  cyan = 0x3CD3E6,
  pink = 0x4A4F60,       -- tied board
  lime = 0x8BE0A8,
}

-- The sounds live in lib/sound_picks.lua.
M.SOUNDS = {
  tap = picks.ui_tap, select = picks.ui_select, back = picks.ui_back, error = picks.ui_error,
  boot = picks.ui_boot, start = picks.ui_start, tick = picks.ui_tick, timeout = picks.ui_timeout,
  win = picks.win_small, winFanfare = picks.win_big, lose = picks.lose, draw = picks.draw,
  resign = picks.resign, rank = picks.ui_rank, achievement = picks.ui_achievement,
  page = picks.ui_page, hint = picks.ui_hint, presence = picks.ui_presence, move = picks.ui_tap,
  placeRed  = picks.piece_a,
  placeBlue = picks.piece_b,
  capture   = picks.capture,
  captureRed  = picks.capture,
  captureBlue = picks.capture,
  force     = picks.ui_tick,
  freeMove  = picks.ui_hint,
  threat    = picks.ui_warning,
}

return M
