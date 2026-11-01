-- manifest-entrypoint: true
-- manifest-key: duel
-- manifest-name: Duel
-- manifest-description: One on one for tokens on two equal 6x6 walls back to back: Heads-Up Hold'em, Gin Rummy, Liar's Dice and Battleship.
-- manifest-category: Games
-- manifest-bundle: Games/PokerTable

require("lib.casino.group.dealer").start(require("games.registry"))
