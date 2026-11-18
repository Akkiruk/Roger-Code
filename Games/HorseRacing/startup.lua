-- manifest-entrypoint: true
-- manifest-key: horse-racing
-- manifest-name: Horse Racing
-- manifest-description: Six horses, fresh odds each race, with win, place, show and exacta bets.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("horseracing_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Horse Racing", main, { log = "casino.log" }) else main() end
