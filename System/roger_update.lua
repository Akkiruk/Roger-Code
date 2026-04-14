-- Universal Roger-Code update command.
-- Forces immediate update checks, optional forced reinstalls, and local poll tuning.

local updater = require("lib.updater")
local logging = require("lib.roger_logging")

local LOG_FILE = "roger_update.log"
local logger = logging.open(LOG_FILE, { namespace = "RogerUpdate" })

local function printUsage()
  print("Usage:")
  print("  rogerupdate              Check immediately and reboot if updates apply")
  print("  rogerupdate force        Reinstall the latest package even if hashes match")
  print("  rogerupdate status       Show installed version and polling interval")
  print("  rogerupdate interval 30  Set automatic polling interval in seconds")
  print("  rogerupdate interval default")
  print("  rogerupdate help")
end

local function printInstallStatus()
  local install = updater.getInstallInfo()
  if not install then
    printError("No installed program record was found.")
    return false
  end

  print("Installed Program: " .. tostring(install.program or install.name or "unknown"))
  print("Version: " .. tostring(install.version or "?"))
  print("Commit: " .. tostring(install.source_commit or "unknown"))
  print("Package Hash: " .. tostring(install.package_hash or install.content_hash or "unknown"))
  print("Update Interval: " .. tostring(install.update_interval or updater.getDefaultUpdateInterval()) .. "s")
  return true
end

local function handleIntervalCommand(rawValue)
  if rawValue == nil or rawValue == "" then
    printError("Missing interval value.")
    printUsage()
    return
  end

  local normalized = string.lower(tostring(rawValue))
  local targetValue = nil
  if normalized == "default" or normalized == "reset" then
    targetValue = updater.getDefaultUpdateInterval()
  else
    targetValue = tonumber(rawValue)
  end

  local ok, result = updater.setUpdateInterval(targetValue)
  if not ok then
    printError("Could not update polling interval: " .. tostring(result))
    return
  end

  logger.info("Automatic update interval set to " .. tostring(result) .. " seconds")
  print("Automatic update interval set to " .. tostring(result) .. " seconds.")
  print("This takes effect on the next supervisor polling cycle or next reboot.")
end

local function runUpdate(forceMode)
  local callbackStatus = "checking"
  local callbackMessage = "Preparing update check..."

  local function showProgress()
    term.setCursorPos(1, 1)
    term.clear()
    print("Roger-Code Updater")
    print("")
    print("Status: " .. string.upper(tostring(callbackStatus or "checking")))
    print("Detail: " .. tostring(callbackMessage or ""))
    print("")
    print("Force Mode: " .. (forceMode and "yes" or "no"))
  end

  local function onCallback(status, message)
    callbackStatus = status
    callbackMessage = message
    logger.info("Updater [" .. tostring(status) .. "] " .. tostring(message or ""))
    showProgress()
  end

  showProgress()

  local result = updater.checkForUpdates({
    force = forceMode,
    rebootOnUpdate = true,
    rebootDelay = 1,
    callback = onCallback,
  })

  if result == "up-to-date" and forceMode then
    print("")
    print("Forced reinstall was not needed because the updater reported no rewrite.")
  elseif result == "up-to-date" then
    print("")
    print("This computer is already up to date.")
  elseif result == "skipped" then
    print("")
    print("Update skipped: " .. tostring(callbackMessage or "another update is already running"))
  elseif result == "error" then
    print("")
    printError("Update failed: " .. tostring(callbackMessage or "unknown error"))
  end
end

local args = { ... }
local command = string.lower(tostring(args[1] or "now"))

if command == "help" or command == "--help" or command == "-h" then
  printUsage()
  return
end

if command == "status" then
  printInstallStatus()
  return
end

if command == "interval" then
  handleIntervalCommand(args[2])
  return
end

if command == "force" then
  runUpdate(true)
  return
end

if command == "now" or command == "update" then
  runUpdate(false)
  return
end

printError("Unknown rogerupdate command: " .. tostring(args[1]))
printUsage()