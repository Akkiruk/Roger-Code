-- longgames.lua
-- Early games too long for one sitting, one player at a time, saved between visits. The shell is shared: see lib/arcade.

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.arcade.main").run({ name = "LONG GAMES" }) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Long Games", main, { log = "arcade.log" }) else main() end
