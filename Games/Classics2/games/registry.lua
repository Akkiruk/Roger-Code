-- games/registry.lua
-- Every game on this computer, in menu order. See "Classics" in Games/Arcade/games/README.md.

return {
  require("games.digdug.plugin"),
  require("games.flappy.plugin"),
  require("games.minesweeper.plugin"),
  require("games.lander.plugin"),
  require("games.duckhunt.plugin"),
  require("games.tapper.plugin"),
  require("games.pipedream.plugin"),
  require("games.mappy.plugin"),
}
