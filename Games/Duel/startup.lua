-- manifest-entrypoint: true
-- manifest-key: duel
-- manifest-name: Duel
-- manifest-description: One on one for tokens on two equal 6x6 walls back to back: Heads-Up Hold'em, Gin Rummy, Liar's Dice, Battleship, Backgammon, Cribbage, Indian Poker and Farkle.
-- manifest-category: Games
-- manifest-bundle: Games/PokerTable

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.casino.group.dealer").start(require("games.registry")) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Duel", main, { log = "casino.log" }) else main() end
