-- games/registry.lua
-- Every game on this computer, in menu order. See "Classics" in Games/Arcade/games/README.md.

return {
  require("games.pacman.plugin"),
  require("games.asteroids.plugin"),
  require("games.invaders.plugin"),
  require("games.missile.plugin"),
  require("games.breakout.plugin"),
  require("games.blocks.plugin"),
  require("games.frogger.plugin"),
  require("games.snake.plugin"),
}
