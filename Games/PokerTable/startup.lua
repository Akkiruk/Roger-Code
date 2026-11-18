-- manifest-entrypoint: true
-- manifest-key: pokertable
-- manifest-name: PokerTable
-- manifest-description: Five-card draw for 2 to 6 players on one wall, player against player, with side pots and no rake.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("pokertable_app").run() end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("PokerTable", main, { log = "casino.log" }) else main() end
