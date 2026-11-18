-- manifest-entrypoint: true
-- manifest-key: hilo
-- manifest-name: Hi-Lo
-- manifest-description: Higher or lower through one deck, with every guess priced from the cards left.
-- manifest-category: Games

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.table").run(require("hilo_game")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Hi-Lo", main, { log = "casino.log" }) else main() end
