-- games/backgammon/tableView.lua
-- Duel has no dealer's wall, so the engine does not draw this today. It is the public board on its own, for a wall that shows only
-- what anyone may see.

local seatView = require("games.backgammon.seatView")

local M = {}

function M.draw(c, view, anim, info)
  seatView.draw(c, view, anim, nil)
end

return M
