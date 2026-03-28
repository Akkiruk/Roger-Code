local currency = require("lib.currency")

local M = {}

function M.isAuthorizedMonitorTouch()
  local sessionPlayer = currency.getAuthenticatedPlayerName and currency.getAuthenticatedPlayerName() or nil
  if not sessionPlayer or sessionPlayer == "" then
    return true
  end

  local currentPlayer = nil
  if currency.getLivePlayerName then
    currentPlayer = currency.getLivePlayerName()
  end
  if (not currentPlayer or currentPlayer == "") and currency.getSessionInfo then
    local info = currency.getSessionInfo()
    currentPlayer = info and info.playerName or nil
  end

  return (not currentPlayer) or currentPlayer == sessionPlayer
end

return M
