-- Vault Gear Sorter startup entry point with background updater support.

local updater = require("lib.updater")
local logger = require("lib.vaultgear.logger")

logger.configure("vaultgear_error.log")

local function logUpdate(status, message)
  logger.info("Updater [" .. tostring(status) .. "] " .. tostring(message or ""))
end

local initialStatus = updater.checkForUpdates({
  callback = logUpdate,
})

if initialStatus == "updated" then
  logUpdate("rebooting", "Initial update applied, rebooting")
  os.sleep(1)
  os.reboot()
end

local function runSorter()
  shell.run("vaultgear.lua")
end

local function watchUpdates()
  updater.watchForUpdates({
    interval = 300,
    callback = logUpdate,
  })
end

parallel.waitForAny(runSorter, watchUpdates)
