-- Vault Gear Sorter startup entry point with background updater support.

local updater = require("lib.updater")

local function runSorter()
  shell.run("vaultgear.lua")
end

local function watchUpdates()
  updater.watchForUpdates()
end

parallel.waitForAny(runSorter, watchUpdates)
