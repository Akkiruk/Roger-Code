-- manifest-entrypoint: true
-- manifest-key: slots
-- manifest-name: Slots
-- manifest-description: Three-reel slot machine with weighted symbols and pair payouts.
-- manifest-category: Games

require("lib.casino.table").run(require("slots_game"))
