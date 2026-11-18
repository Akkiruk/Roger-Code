-- manifest-entrypoint: true
-- manifest-key: gearshop
-- manifest-name: Gear Shop
-- manifest-description: The walk-in gear shop: tap a station to browse a gear type, take what you want onto your tab, PAY at any station. Also buys gear for store credit. Install on the shop computer and on every node that holds its chests and monitors.
-- manifest-category: Utilities

-- A crash goes to the owner as a GitHub issue (lib/crashreport), then on to the supervisor as before; without the module it
-- runs as it always has
local function main() require("lib.gearshop.app").run() end
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if hasReport and type(crashreport) == "table" then crashreport.guard("Gear Shop", main, { log = "gearshop.log" }) else main() end
