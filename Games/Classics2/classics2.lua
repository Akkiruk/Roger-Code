-- classics2.lua
-- The second cabinet of early arcade games, one player at a time, for the high score. The shell is shared: see lib/arcade.

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.arcade.main").run({ name = "CLASSICS 2" }) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Classics 2", main, { log = "arcade.log" }) else main() end
