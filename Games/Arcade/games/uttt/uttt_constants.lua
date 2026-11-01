-- games/uttt/uttt_constants.lua
-- Ultimate Tic-Tac-Toe's own settings and sounds.

local picks = require("lib.sound_picks")

local M = {}

M.DATA_FILE = "uttt_data.dat"   -- the same file the old package used, so ratings carry over

M.SETTINGS = {
  timer = 0,          -- seconds per move, 0 = off
  tiebreak = false,   -- house rule: most small boards wins when nothing is left to play (standard rule: draw)
  ai = "medium",      -- default computer level
}

M.SOUNDS = {
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
