-- manifest-entrypoint: true
-- manifest-key: gearlocker
-- manifest-name: Gear Locker
-- manifest-description: Your own vault gear in AE2: finds the bad gear and pulls it to a junk chest, and shows the best upgrade per slot from what's in your ME system. Needs an ME Bridge, a monitor and three chests (staging, junk, pickup). The chests can sit on node computers linked by ender modem: install this on each node too and pick "node".
-- manifest-category: Utilities

local function main() require("lib.gearlocker.app").run() end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Gear Locker", main, { log = "gearlocker.log" }) else main() end
