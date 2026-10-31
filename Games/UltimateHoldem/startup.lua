-- manifest-entrypoint: true
-- manifest-key: ultimate-holdem
-- manifest-name: Ultimate Texas Hold'em
-- manifest-description: Ante and Blind against the dealer, with one raise from 4x down to 1x and a Trips side bet.
-- manifest-category: Games

require("lib.casino.table").run(require("holdem_game"))
