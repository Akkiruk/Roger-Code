-- arcade.lua
-- The board games. The shell is shared with the Classics package: see lib/arcade/main.lua.

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.arcade.main").run({ name = "ARCADE" }) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Arcade", main, { log = "arcade.log" }) else main() end
