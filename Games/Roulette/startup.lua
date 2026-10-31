-- manifest-entrypoint: true
-- manifest-key: roulette
-- manifest-name: Roulette
-- manifest-description: Single-zero European roulette with inside and outside bets.
-- manifest-category: Games

require("lib.casino.table").run(require("roulette_game"))
