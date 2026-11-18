-- manifest-entrypoint: true
-- manifest-key: slots
-- manifest-name: Slots
-- manifest-description: Three-reel slot machine with weighted symbols and pair payouts.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("slots_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Slots", main, { log = "casino.log" }) else main() end
