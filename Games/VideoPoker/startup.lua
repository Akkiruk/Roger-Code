-- manifest-entrypoint: true
-- manifest-key: videopoker
-- manifest-name: VideoPoker
-- manifest-description: Jacks or Better draw poker with payout and tutorial screens.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("videopoker_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("VideoPoker", main, { log = "casino.log" }) else main() end
