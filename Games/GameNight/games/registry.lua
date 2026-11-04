-- games/registry.lua
-- Every game on Game Night, in the order of the tiles. A new game is one folder under games/ and one line here.
-- Game Night is Big Table's engine with free = true: no buy-in, no tokens, no owed book, only wins. A game is written the same way
-- (Games/BigTable/games/README.md), and its nets are always nought. A game that is missing or will not load is skipped and logged.

local journal = require("lib.casino.journal")

local GAMES = { "catan" }

local M = { key = "gamenight", title = "GAME NIGHT", free = true, list = {} }

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
