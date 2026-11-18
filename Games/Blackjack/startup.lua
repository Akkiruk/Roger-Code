-- manifest-entrypoint: true
-- manifest-key: blackjack
-- manifest-name: Blackjack
-- manifest-description: Six-deck blackjack with a lasting shoe, doubles on 11 and one split.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("blackjack_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Blackjack", main, { log = "casino.log" }) else main() end
