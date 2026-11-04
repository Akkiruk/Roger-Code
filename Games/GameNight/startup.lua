-- manifest-entrypoint: true
-- manifest-key: game-night
-- manifest-name: Game Night
-- manifest-description: Free board games for up to eight players, each at their own screen, starting with Catan. Install it on every computer: a 6x6 wall becomes the table and a smaller one a seat. No tokens, ever.
-- manifest-category: Arcade

-- Free play: the stand-ins go in before anything can require the wallet, so nothing on this computer can move a token
require("lib.casino.group.free").install()
require("lib.casino.group.dealer").start(require("games.registry"))
