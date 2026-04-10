-- manifest-entrypoint: true
-- Vault Storage Manager startup entry point.

local logger = require("lib.vaultgear.logger")

logger.configure("vaultgear_error.log")

logger.info("Launching VaultGear application")
shell.run("vaultgear.lua")
