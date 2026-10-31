-- manifest-entrypoint: true
-- manifest-key: baccarat
-- manifest-name: Baccarat
-- manifest-description: Eight-deck baccarat with Player, Banker and Tie bets.
-- manifest-category: Games

require("lib.casino.table").run(require("baccarat_game"))
