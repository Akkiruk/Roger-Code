-- manifest-entrypoint: true
-- manifest-key: crazyeights
-- manifest-name: CrazyEights
-- manifest-description: Fast single-hand Crazy Eights duel with wild 8s and draw 2s.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("crazyeights_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("CrazyEights", main, { log = "casino.log" }) else main() end
