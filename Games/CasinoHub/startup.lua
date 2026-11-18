-- manifest-entrypoint: true
-- manifest-key: casino-hub
-- manifest-name: Casino Hub
-- manifest-description: The casino's central board: shared jackpot, leaderboards, each game's measured return, and the tables on the floor.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("casino_hub_app").run() end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Casino Hub", main, { log = "casino.log" }) else main() end
