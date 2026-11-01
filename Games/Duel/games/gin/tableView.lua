-- games/gin/tableView.lua
-- Duel has no dealer's wall, so the engine never calls this. It is here so that the public picture has one name if a game of gin is
-- ever watched from a wall of its own: the same screen a wall with no viewer shows.

local seatView = require("games.gin.seatView")

local M = {}

function M.draw(c, view, anim)
  seatView.draw(c, view, anim)
end

return M
