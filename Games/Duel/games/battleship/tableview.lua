-- games/battleship/tableview.lua
-- Duel has no dealer's wall, so the engine never draws this. It is here so the game stays whole if a table with a wall ever takes it,
-- and it holds nothing of its own: the public picture is the one a covered Duel wall shows.

local seatview = require("games.battleship.seatview")

local M = {}

function M.draw(c, view, anim)
  if view.players then seatview.drawBoth(c, view, anim) end
end

return M
