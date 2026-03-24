-- Vault Gear Sorter monitor app for configurable Vault Hunters gear routing.

local app = require("lib.vaultgear.app")
local logger = require("lib.vaultgear.logger")

local ok, err = pcall(app.run)
if not ok then
  logger.error("FATAL: " .. tostring(err))
  printError("Vault Gear Sorter crashed: " .. tostring(err))
  printError("See vaultgear_error.log for details.")
end
