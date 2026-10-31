-- manifest-entrypoint: true
-- manifest-key: hilo
-- manifest-name: Hi-Lo
-- manifest-description: Higher or lower through one deck, with every guess priced from the cards left.
-- manifest-category: Games

require("lib.casino.table").run(require("hilo_game"))
