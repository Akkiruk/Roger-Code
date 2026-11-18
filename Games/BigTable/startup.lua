-- manifest-entrypoint: true
-- manifest-key: big-table
-- manifest-name: Big Table
-- manifest-description: Eight casino games for up to eight players, each at their own screen. Install it on every computer: a 6x6 wall becomes the dealer and a smaller one a seat.
-- manifest-category: Games
-- manifest-bundle: Games/PokerTable

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.group.dealer").start(require("games.registry")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Big Table", main, { log = "casino.log" }) else main() end
