-- games/liarsdice/tableView.lua
-- Duel has no dealer's wall, so the engine does not draw this today. It is the public board on its own, for a wall that shows only
-- what anyone may see.

local seatui = require("lib.casino.group.seatui")
local seatView = require("games.liarsdice.seatView")

local M = {}

function M.draw(c, view, anim, info)
  local x, _, w = seatui.tableArea(c)
  seatView.board(c, view, anim, nil, x, w)
end

return M
