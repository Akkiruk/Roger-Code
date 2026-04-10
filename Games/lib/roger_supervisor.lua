local updater = require("lib.updater")

local STATE_FILE = ".installed_program"
local LOG_FILE = "roger_supervisor.log"
local DEFAULT_RESTART_DELAY = 5
local DEFAULT_UPDATE_INTERVAL = 300

local M = {}

local function logMessage(message)
  local handle = fs.open(LOG_FILE, "a")
  if handle then
    handle.writeLine("[" .. os.epoch("local") .. "] " .. tostring(message))
    handle.close()
  end
end

local function readInstalledState()
  if not fs.exists(STATE_FILE) then
    return nil
  end

  local handle = fs.open(STATE_FILE, "r")
  if not handle then
    return nil
  end

  local raw = handle.readAll()
  handle.close()

  local ok, state = pcall(function()
    return textutils.unserialise(raw)
  end)
  if ok and type(state) == "table" then
    return state
  end

  return nil
end

local function loadRuntimeState()
  local installed = updater.getInstallInfo() or readInstalledState()
  if type(installed) ~= "table" then
    return nil, "No install record found"
  end

  local appEntrypoint = installed.app_entrypoint or installed.entrypoint
  if type(appEntrypoint) ~= "string" or appEntrypoint == "" then
    return nil, "Install record is missing app_entrypoint"
  end

  return {
    installed = installed,
    appEntrypoint = appEntrypoint,
    autoRestart = installed.auto_restart ~= false,
    restartDelay = tonumber(installed.restart_delay) or DEFAULT_RESTART_DELAY,
    updateInterval = tonumber(installed.update_interval) or DEFAULT_UPDATE_INTERVAL,
  }
end

local function waitSeconds(seconds)
  local timer = os.startTimer(seconds)
  while true do
    local event, timerId = os.pullEventRaw()
    if event == "timer" and timerId == timer then
      return
    end
    if event == "terminate" then
      error("Terminated", 0)
    end
  end
end

local function showCrashScreen(entrypoint, errorMessage, delaySeconds)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("Program crashed under Roger supervisor.")
  print("")
  term.setTextColor(colors.white)
  print("Entrypoint: " .. tostring(entrypoint))
  print(tostring(errorMessage or "Unknown error"))
  print("")
  print("Restarting in " .. tostring(delaySeconds) .. " seconds...")
end

local function showExitScreen(entrypoint)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.yellow)
  term.clear()
  term.setCursorPos(1, 1)
  print("Program exited.")
  print("")
  term.setTextColor(colors.white)
  print("Entrypoint: " .. tostring(entrypoint))
  print("Supervisor is still running for updates.")
end

local function runProgram(entrypoint, args)
  local ok, shellOk, shellErr = pcall(shell.run, entrypoint, unpack(args or {}))
  if not ok then
    return false, shellOk
  end
  if shellOk == false then
    return false, shellErr or "Program failed"
  end
  return true, nil
end

local function runInitialUpdateCheck(callback)
  local ok, status = pcall(function()
    return updater.checkForUpdates({
      rebootOnUpdate = true,
      callback = callback,
    })
  end)

  if not ok then
    logMessage("Initial update check crashed: " .. tostring(status))
    return
  end

  if status == "updated" then
    return
  end
end

local function updateWatcher(updateInterval)
  updater.watchForUpdates({
    interval = updateInterval,
    callback = function(status, message)
      logMessage("Updater [" .. tostring(status) .. "] " .. tostring(message or ""))
    end,
  })
end

function M.run(...)
  local args = { ... }
  local runtime, err = loadRuntimeState()
  if not runtime then
    logMessage("Cannot boot installed program: " .. tostring(err))
    if fs.exists("installer.lua") then
      shell.run("installer.lua")
      return
    end
    error(err, 0)
  end

  local installed = runtime.installed
  logMessage(
    "Booting " .. tostring(installed.program or installed.game or installed.name or "program")
      .. " | app=" .. tostring(runtime.appEntrypoint)
      .. " | commit=" .. tostring(installed.source_commit or ""):sub(1, 8)
      .. " | pkg=" .. tostring(installed.package_hash or installed.content_hash or ""):sub(1, 8)
  )

  runInitialUpdateCheck(function(status, message)
    logMessage("Initial updater [" .. tostring(status) .. "] " .. tostring(message or ""))
  end)

  local function appLoop()
    while true do
      local ok, runErr = runProgram(runtime.appEntrypoint, args)
      if ok then
        logMessage("Program exited normally: " .. tostring(runtime.appEntrypoint))
        if not runtime.autoRestart then
          showExitScreen(runtime.appEntrypoint)
          while true do
            waitSeconds(30)
          end
        end
      else
        logMessage("Program crash: " .. tostring(runErr))
        showCrashScreen(runtime.appEntrypoint, runErr, runtime.restartDelay)
      end

      waitSeconds(runtime.restartDelay)
    end
  end

  parallel.waitForAny(appLoop, function()
    updateWatcher(runtime.updateInterval)
  end)
end

return M