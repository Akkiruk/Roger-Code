-- manifest-entrypoint: true
-- manifest-key: three-card-poker
-- manifest-name: 3 Card Poker
-- manifest-description: Ante and Play against the dealer, with an Ante Bonus and a Pair Plus side bet.
-- manifest-category: Games

require("lib.casino.table").run(require("threecard_game"))
