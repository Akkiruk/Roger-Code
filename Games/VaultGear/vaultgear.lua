-- manifest-category: Utilities
-- Vault Storage Manager monitor app for live multi-storage routing and repair.

local app = require("lib.vaultgear.app")
local logger = require("lib.vaultgear.logger")

local ok, err = pcall(app.run)
if not ok then
  logger.error("FATAL: " .. tostring(err))
  printError("Vault Storage Manager crashed: " .. tostring(err))
  printError("See vaultgear_error.log for details.")
end
