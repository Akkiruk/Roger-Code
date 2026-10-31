-- manifest-entrypoint: true
-- manifest-key: blackjack
-- manifest-name: Blackjack
-- manifest-description: Six-deck blackjack with a lasting shoe, doubles on 11 and one split.
-- manifest-category: Games

require("lib.casino.table").run(require("blackjack_game"))
