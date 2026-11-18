-- manifest-entrypoint: true
-- manifest-key: three-card-poker
-- manifest-name: 3 Card Poker
-- manifest-description: Ante and Play against the dealer, with an Ante Bonus and a Pair Plus side bet.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("threecard_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("3 Card Poker", main, { log = "casino.log" }) else main() end
