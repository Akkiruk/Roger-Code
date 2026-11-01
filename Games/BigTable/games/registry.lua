-- games/registry.lua
-- Every game on Big Table, in the order of the tiles. A new game is one folder under games/ and one line here.
-- See games/README.md for what a game provides. A game that is missing or will not load is skipped and logged, so the
-- cabinet runs without it.

local journal = require("lib.casino.journal")

local GAMES = { "draw", "holdem", "omaha", "stud", "blackjack", "roulette", "baccarat", "craps" }

local M = { key = "bigtable", title = "BIG TABLE", list = {} }

for _, id in ipairs(GAMES) do
  local ok, plugin = pcall(require, "games." .. id .. ".plugin")
  if ok and type(plugin) == "table" then
    M.list[#M.list + 1] = plugin
  else
    journal.log("game " .. id .. " did not load: " .. tostring(plugin):sub(1, 160))
  end
end

--- A game by its id, or nil.
function M.find(id)
  for _, plugin in ipairs(M.list) do
    if plugin.id == id then return plugin end
  end
  return nil
end

return M
