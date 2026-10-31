-- games/registry.lua
-- Every game on this computer, in menu order. A new game is one folder under games/ and one line here.
-- See games/README.md for what a game provides.

return {
  require("games.uttt.plugin"),
  require("games.connect4.plugin"),
  require("games.reversi.plugin"),
  require("games.checkers.plugin"),
  require("games.dots.plugin"),
  require("games.mancala.plugin"),
  require("games.battleship.plugin"),
  require("games.mastermind.plugin"),
  require("games.snake.plugin"),
}
