-- games/registry.lua
-- Every game on this computer, in menu order. See "Classics" in Games/Arcade/games/README.md.

return {
  require("games.moag.plugin"),
  require("games.pong.plugin"),
  require("games.bomberman.plugin"),
  require("games.tron.plugin"),
}
