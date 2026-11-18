-- manifest-entrypoint: true
-- manifest-key: ultimate-holdem
-- manifest-name: Ultimate Texas Hold'em
-- manifest-description: Ante and Blind against the dealer, with one raise from 4x down to 1x and a Trips side bet.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("holdem_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Ultimate Texas Hold'em", main, { log = "casino.log" }) else main() end
