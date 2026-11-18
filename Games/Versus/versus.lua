-- versus.lua
-- Two players in real time, one wall each, with a computer opponent for one. The shell is shared: see lib/arcade.

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.arcade.main").run({ name = "VERSUS" }) end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Versus", main, { log = "arcade.log" }) else main() end
