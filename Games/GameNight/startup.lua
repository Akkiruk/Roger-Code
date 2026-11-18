-- manifest-entrypoint: true
-- manifest-key: game-night
-- manifest-name: Game Night
-- manifest-description: Free games for up to eight players, each at their own screen: Catan and UNO. Install it on every computer: a 6x6 wall becomes the table and a smaller one a seat. No tokens, ever.
-- manifest-category: Arcade

-- Free play: the stand-ins go in before anything can require the wallet, so nothing on this computer can move a token
require("lib.casino.group.free").install()

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.group.dealer").start(require("games.registry")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Game Night", main, { log = "casino.log" }) else main() end
