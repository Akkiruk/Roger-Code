-- manifest-entrypoint: true
-- manifest-key: videopoker
-- manifest-name: VideoPoker
-- manifest-description: Jacks or Better draw poker with payout and tutorial screens.
-- manifest-category: Games

require("lib.casino.table").run(require("videopoker_game"))
