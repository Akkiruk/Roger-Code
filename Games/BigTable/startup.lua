-- manifest-entrypoint: true
-- manifest-key: big-table
-- manifest-name: Big Table
-- manifest-description: Eight casino games for up to eight players, each at their own screen. Install it on every computer: a 6x6 wall becomes the dealer and a smaller one a seat.
-- manifest-category: Games
-- manifest-bundle: Games/PokerTable

require("lib.casino.group.dealer").start(require("games.registry"))
