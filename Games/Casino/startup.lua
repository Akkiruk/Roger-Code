-- manifest-entrypoint: true
-- manifest-key: casino
-- manifest-name: Casino
-- manifest-description: Every single-player casino game on one cabinet: pick a game from the menu, and it plays just as its own table does.
-- manifest-category: Games
-- manifest-bundle: Games/Baccarat Games/Blackjack Games/CrazyEights Games/HiLo Games/HorseRacing Games/PokerTable Games/Roulette Games/Slots Games/ThreeCardPoker Games/UltimateHoldem Games/VideoPoker

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("casino_cabinet").run() end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Casino", main, { log = "casino.log" }) else main() end
