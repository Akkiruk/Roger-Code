-- games/uttt/uttt_constants.lua
-- Ultimate Tic-Tac-Toe's own settings and sounds.

local M = {}

M.DATA_FILE = "uttt_data.dat"   -- the same file the old package used, so ratings carry over

M.SETTINGS = {
  timer = 0,          -- seconds per move, 0 = off
  tiebreak = false,   -- house rule: most small boards wins when nothing is left to play (standard rule: draw)
  ai = "medium",      -- default computer level
}

M.SOUNDS = {
  placeRed  = { "casinocraft:casinocraft.card.place", 0.7, 1.15 },
  placeBlue = { "casinocraft:casinocraft.card.place", 0.7, 0.8 },
  capture   = { "the_vault:coin_single_place", 0.8, 1.0 },
  captureRed  = { "the_vault:coin_single_place", 0.8, 1.2 },
  captureBlue = { "the_vault:coin_single_place", 0.8, 0.85 },
  force     = { "quark:ambient.clock", 0.35, 1.0 },
  freeMove  = { "lightmanscurrency:coins_clinking", 0.5, 1.2 },
  threat    = { "the_vault:rampage", 0.25, 1.6 },
}

return M
