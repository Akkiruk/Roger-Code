local runtimeExit = require("lib.runtime_exit")
local updater = require("lib.updater")

local function openLogger(path, namespace)
  local ok, logging = pcall(function()
    return require("lib.roger_logging")
  end)

  if ok and type(logging) == "table" and type(logging.open) == "function" then
    return logging.open(path, { namespace = namespace })
  end

  local function write(level, message)
    local handle = fs.open(path, "a")
    if not handle then
      return false
    end

    handle.writeLine(
      "[" .. os.epoch("local") .. "]"
        .. " [" .. tostring(level or "INFO") .. "]"
        .. " [" .. tostring(namespace or "Supervisor") .. "] "
        .. tostring(message)
    )
    handle.close()
    return true
  end

  return {
    info = function(message)
      return write("INFO", message)
    end,
    error = function(message)
      return write("ERROR", message)
    end,
  }
end

local STATE_FILE = ".installed_program"
local LOG_FILE = "roger_supervisor.log"
local INSTALLER_PATH = "installer.lua"
local DEFAULT_RESTART_DELAY = 5
local DEFAULT_UPDATE_INTERVAL = 300
local MIN_UPDATE_INTERVAL = 300     -- an install record from before this was 60 seconds
local BUSY_REPORT_SECONDS = 15      -- a game that stops saying it is busy has stopped being busy
local CRASH_UPDATE_CHECK_COOLDOWN = 30
local CRASHES_BEFORE_REPAIR = 2
local DEFAULT_GAME_MONITOR_IDLE_TIMEOUT = 60
local MONITOR_IDLE_CHECK_INTERVAL = 1
local GAME_CATEGORY = "Games"
local ARCADE_CATEGORY = "Arcade"
local MONITOR_ACTIVITY_EVENTS = {
  monitor_resize = true,
  monitor_touch = true,
  -- A casino table says this while it runs, so a quiet table waiting for its player is not taken for a hung one
  roger_alive = true,
}
local GAME_PROGRAM_KEYS = {
  baccarat = true,
  blackjack = true,
  crazyeights = true,
  hilo = true,
  pokertable = true,
  roulette = true,
  slots = true,
  videopoker = true,
}
local LEGACY_MAIN_FILES = {
  baccarat = "baccarat.lua",
  blackjack = "blackjack.lua",
  hilo = "hilo.lua",
  phone_os = "phone_os.lua",
  pokertable = "pokertable.lua",
  roulette = "Roulette.lua",
  slots = "slots.lua",
  sound_browser = "sound_browser.lua",
  taskmaster = "taskmaster.lua",
  vault_item_analyzer = "vault_item_analyzer.lua",
  vaultgear = "vaultgear.lua",
  vhcctweaks_smoke_test = "vhcctweaks_smoke_test.lua",
  videopoker = "videopoker.lua",
}

local M = {}
local logger = openLogger(LOG_FILE, "Supervisor")

local function logMessage(message)
  logger.info(message)
end

local function isTerminateError(err)
  return runtimeExit.isTerminateError(err)
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

local function saveInstalledState(state)
  if type(state) ~= "table" then
    return false
  end

  local handle = fs.open(STATE_FILE, "w")
  if not handle then
    return false
  end

  handle.write(textutils.serialise(state))
  handle.close()
  return true
end

local function resolveLegacyEntrypoint(installed)
  if type(installed) ~= "table" then
    return nil
  end

  local programKey = tostring(installed.program or installed.game or "")
  local candidates = {}

  if programKey ~= "" then
    candidates[#candidates + 1] = programKey .. "_startup.lua"

    local legacyMain = LEGACY_MAIN_FILES[programKey]
    if type(legacyMain) == "string" and legacyMain ~= "" then
      candidates[#candidates + 1] = legacyMain
    end

    candidates[#candidates + 1] = programKey .. ".lua"
  end

  local seen = {}
  for _, candidate in ipairs(candidates) do
    if candidate ~= "" and candidate ~= "startup.lua" and not seen[candidate] then
      seen[candidate] = true
      if fs.exists(candidate) then
        return candidate
      end
    end
  end

  return nil
end

local function isGameInstall(installed)
  if type(installed) ~= "table" then
    return false
  end

  if tostring(installed.category or "") == GAME_CATEGORY then
    return true
  end

  local programKey = string.lower(tostring(installed.program or installed.game or ""))
  return GAME_PROGRAM_KEYS[programKey] == true
end

local function monitorIdleWatchdog(timeoutSeconds)
  local timeoutMs = (tonumber(timeoutSeconds) or DEFAULT_GAME_MONITOR_IDLE_TIMEOUT) * 1000
  local lastMonitorActivityAt = os.epoch("local")
  local timerId = os.startTimer(MONITOR_IDLE_CHECK_INTERVAL)

  while true do
    local event, param1 = os.pullEventRaw()
    if event == "terminate" then
      error("Terminated", 0)
    end

    if MONITOR_ACTIVITY_EVENTS[event] then
      lastMonitorActivityAt = os.epoch("local")
    elseif event == "timer" and param1 == timerId then
      local idleMs = os.epoch("local") - lastMonitorActivityAt
      if idleMs >= timeoutMs and not updater.isUpdating() then
        logMessage("Monitor idle for " .. tostring(math.floor(idleMs / 1000)) .. "s; rebooting")
        pcall(function()
          term.setBackgroundColor(colors.black)
          term.setTextColor(colors.yellow)
          term.clear()
          term.setCursorPos(1, 1)
          print("No monitor activity for 60 seconds.")
          print("Rebooting...")
        end)
        os.reboot()
      end

      timerId = os.startTimer(MONITOR_IDLE_CHECK_INTERVAL)
    end
  end
end

-- A running game leaves no shell on the computer, so this key is the way to reach the installer.
local function installerKeyWatcher()
  while true do
    local _, typed = os.pullEventRaw("char")
    if typed == "i" or typed == "I" then
      return
    end
  end
end

-- Runs code an admin sent with /vhcc pc exec. The server only accepts the answer to a request it made.
local function remoteAgent()
  while true do
    local event, request, code = os.pullEventRaw("vhcc_rc_exec")
    if event == "vhcc_rc_exec" then
      local chunk, loadErr = load(code, "=remote", "t", _G)
      local results = chunk and { pcall(chunk) } or { false, loadErr }
      local ok, json = pcall(textutils.serialiseJSON, results)
      if not ok then
        json = textutils.serialiseJSON({ false, "result cannot be serialised" })
      end
      pcall(vhcc.rcReply, request, json)
    end
  end
end

local function loadRuntimeState()
  local installed = updater.getInstallInfo() or readInstalledState()
  if type(installed) ~= "table" then
    return nil, "No install record found"
  end

  local appEntrypoint = installed.app_entrypoint or installed.entrypoint
  local recoveredLegacyEntrypoint = false
  if type(appEntrypoint) ~= "string" or appEntrypoint == "" then
    appEntrypoint = resolveLegacyEntrypoint(installed)
    if type(appEntrypoint) ~= "string" or appEntrypoint == "" then
      return nil, "Install record is missing app_entrypoint"
    end

    recoveredLegacyEntrypoint = true
    installed.app_entrypoint = appEntrypoint
    installed.system_entrypoint = installed.system_entrypoint or "startup.lua"
    installed.boot_mode = installed.boot_mode or "supervisor"
    saveInstalledState(installed)
  end

  return {
    installed = installed,
    appEntrypoint = appEntrypoint,
    recoveredLegacyEntrypoint = recoveredLegacyEntrypoint,
    autoRestart = installed.auto_restart ~= false,
    monitorIdleTimeout = isGameInstall(installed) and DEFAULT_GAME_MONITOR_IDLE_TIMEOUT or nil,
    restartDelay = tonumber(installed.restart_delay) or DEFAULT_RESTART_DELAY,
    updateInterval = math.max(MIN_UPDATE_INTERVAL, tonumber(installed.update_interval) or DEFAULT_UPDATE_INTERVAL),
    installerKey = isGameInstall(installed) or tostring(installed.category or "") == ARCADE_CATEGORY,
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
  local runOk, runErr, runState = runtimeExit.classifyShellRun(ok, shellOk, shellErr, {
    emptyErrorMeansTerminate = true,
  })

  if not runOk and runState == "empty_error_treated_as_terminate" then
    logMessage("shell.run returned false without an error message for " .. tostring(entrypoint) .. "; treating as terminate")
  end

  return runOk, runErr
end

-- A game says "roger_busy", true or false, every few seconds. It is a report and not a switch, so a game that crashes
-- halfway through a round cannot hold updates back: its reports just stop.
local busyAt = nil

local function busyListener()
  while true do
    local _, busy = os.pullEventRaw("roger_busy")
    busyAt = busy and os.epoch("utc") or nil
  end
end

local function gameIsBusy()
  return busyAt ~= nil and os.epoch("utc") - busyAt < BUSY_REPORT_SECONDS * 1000
end

local function updateWatcher(updateInterval)
  updater.watchForUpdates({
    interval = updateInterval,
    isBusy = gameIsBusy,
    callback = function(status, message)
      logMessage("Updater [" .. tostring(status) .. "] " .. tostring(message or ""))
    end,
  })
end

local function checkForUpdatesAfterCrash(runErr, repair)
  local status = updater.checkForUpdates({
    repair = repair,
    rebootOnUpdate = true,
    rebootDelay = 1,
    callback = function(updateStatus, message)
      logMessage(
        "Crash updater [" .. tostring(updateStatus) .. "] "
          .. tostring(message or "")
          .. " | error=" .. tostring(runErr or "")
      )
    end,
  })

  if status == "updated" or status == "terminated" then
    return
  end

  logMessage("Crash updater result: " .. tostring(status or "unknown"))
end

function M.run(...)
  local args = { ... }
  -- A game can leave term pointing at anything, and the supervisor still has to draw and update after it dies.
  local homeTerm = term.current()
  updater.clearStaleLock()
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
  if runtime.recoveredLegacyEntrypoint then
    logMessage("Recovered legacy app entrypoint: " .. tostring(runtime.appEntrypoint))
  end
  logMessage(
    "Booting " .. tostring(installed.program or installed.game or installed.name or "program")
      .. " | app=" .. tostring(runtime.appEntrypoint)
      .. " | category=" .. tostring(installed.category or "")
      .. " | commit=" .. tostring(installed.source_commit or ""):sub(1, 8)
      .. " | pkg=" .. tostring(installed.package_hash or installed.content_hash or ""):sub(1, 8)
  )
  logMessage("Time Since Last Update: " .. updater.formatElapsedSince(updater.getLastPackageUpdateAt(installed)))
  if runtime.monitorIdleTimeout then
    logMessage("Monitor idle watchdog enabled for " .. tostring(runtime.monitorIdleTimeout) .. "s")
  end

  local function appLoop()
    local lastCrashUpdateCheckAt = nil
    local crashes = 0

    while true do
      local ok, runErr = runProgram(runtime.appEntrypoint, args)
      term.redirect(homeTerm)
      if ok then
        logMessage("Program exited normally: " .. tostring(runtime.appEntrypoint))
        if not runtime.autoRestart then
          showExitScreen(runtime.appEntrypoint)
          while true do
            waitSeconds(30)
          end
        end
      else
        if isTerminateError(runErr) then
          logMessage("Program terminated: " .. tostring(runtime.appEntrypoint))
          return
        end

        crashes = crashes + 1
        local now = os.epoch("local")
        local shouldCheckForUpdates = (not lastCrashUpdateCheckAt)
          or ((now - lastCrashUpdateCheckAt) >= (CRASH_UPDATE_CHECK_COOLDOWN * 1000))

        logMessage("Program crash: " .. tostring(runErr))
        showCrashScreen(runtime.appEntrypoint, runErr, runtime.restartDelay)

        if shouldCheckForUpdates then
          lastCrashUpdateCheckAt = now
          term.setCursorPos(1, 8)
          term.setTextColor(colors.lightGray)
          print("Checking for updates before restart...")
          checkForUpdatesAfterCrash(runErr, crashes >= CRASHES_BEFORE_REPAIR)
        else
          local secondsUntilRetry = math.ceil(((CRASH_UPDATE_CHECK_COOLDOWN * 1000) - (now - lastCrashUpdateCheckAt)) / 1000)
          logMessage("Skipping crash update check for " .. tostring(secondsUntilRetry) .. "s cooldown")
        end
      end

      waitSeconds(runtime.restartDelay)
    end
  end

  local runners = {
    appLoop,
    function()
      updateWatcher(runtime.updateInterval)
    end,
    busyListener,
  }

  if vhcc and vhcc.rcReply then
    runners[#runners + 1] = remoteAgent
  end

  local installerRequested = false
  if runtime.monitorIdleTimeout then
    runners[#runners + 1] = function()
      monitorIdleWatchdog(runtime.monitorIdleTimeout)
    end
  end
  if runtime.installerKey then
    runners[#runners + 1] = function()
      installerKeyWatcher()
      installerRequested = true
    end
    print("Press I here to open the installer.")
  end

  parallel.waitForAny(unpack(runners))
  term.redirect(homeTerm)

  if installerRequested and fs.exists(INSTALLER_PATH) then
    logMessage("Installer opened from the running game")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    shell.run(INSTALLER_PATH)
    os.reboot()
  end
end

return M