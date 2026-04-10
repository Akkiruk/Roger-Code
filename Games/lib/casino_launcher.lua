local alertLib = require("lib.alert")
local idleScreen = require("lib.idle_screen")
local ui = require("lib.ui")

local M = {}

local function loadInstallInfo()
  if not fs.exists(".installed_program") then
    return nil
  end

  local handle = fs.open(".installed_program", "r")
  if not handle then
    return nil
  end

  local raw = handle.readAll()
  handle.close()

  local ok, info = pcall(function()
    return textutils.unserialise(raw)
  end)
  if ok and type(info) == "table" then
    return info
  end

  return nil
end

local function makeLogger(enabled, logFn)
  local debugTerm = term.native()

  return function(message)
    if not enabled then
      return
    end

    local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(message)
    local previous = term.redirect(debugTerm)
    print(line)
    term.redirect(previous)
    logFn(message)
  end
end

local function showCrashScreen(delaySeconds, errorMessage)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  term.write("Game crashed! Error reported to admin.")
  term.setCursorPos(1, 3)
  term.setTextColor(colors.white)
  term.write(tostring(errorMessage or "Unknown error"))
  term.setCursorPos(1, 5)
  term.write("The game will restart in " .. tostring(delaySeconds) .. " seconds...")
  os.sleep(delaySeconds)
end

function M.run(opts)
  local options = opts or {}
  local monitorName = options.monitorName or error("monitorName is required")
  local startupName = options.startupName or "Casino Startup"
  local logFile = options.logFile or "casino_startup.log"
  local programs = options.programs or { play = options.program }
  local crashDelay = options.crashDelay or 10

  alertLib.configure({
    gameName = startupName,
    logFile = logFile,
  })
  alertLib.addPlannedExits({
    "inactivity_timeout",
    "main_menu",
    "user_terminated",
  })

  local debugLog = makeLogger(options.debugEnabled ~= false, alertLib.log)
  local idleEnv = nil

  local function setupIdle()
    idleEnv = idleScreen.setup({
      monitorName = monitorName,
      cardCount = options.cardCount,
      cardAnimation = options.cardAnimation,
      extraAssets = options.extraAssets,
      monitorTextScale = options.monitorTextScale,
      palette = options.palette,
    })
    ui.init(idleEnv.surface, idleEnv.font, idleEnv.scale)
  end

  local ok, err = pcall(setupIdle)
  if not ok then
    debugLog("Fatal error in setupIdle: " .. tostring(err))
    alertLib.send("Fatal setupIdle: " .. tostring(err))
    error(err)
  end

  debugLog(startupName .. " idle setup complete.")

  local installInfo = loadInstallInfo()
  if installInfo then
    debugLog("Installed: " .. tostring(installInfo.program)
      .. " v" .. tostring(installInfo.version)
      .. " | commit=" .. tostring(installInfo.source_commit):sub(1, 8)
      .. " | pkg=" .. tostring(installInfo.package_hash or installInfo.content_hash):sub(1, 8))
  else
    debugLog("WARNING: No .installed_program record found!")
  end

  local function runProgram(action)
    local program = programs[action]
    if not program then
      return
    end

    debugLog("startup.lua: Starting " .. tostring(program) .. "...")
    local previous = term.current()
    local runOk, runErr = pcall(shell.run, program)
    if not runOk then
      debugLog("startup.lua: Error in " .. tostring(program) .. ": " .. tostring(runErr))
      alertLib.send(tostring(program) .. " error: " .. tostring(runErr))
      if idleEnv and idleEnv.monitor then
        showCrashScreen(crashDelay, runErr)
      end
    end
    term.redirect(previous)
    debugLog("startup.lua: " .. tostring(program) .. " finished, returning to idle.")
  end

  local function mainLoop()
    while true do
      local idleOk, actionOrError = pcall(idleScreen.runLoop, idleEnv, {
        drawOverlay = options.drawOverlay,
        checkHit = options.checkHit,
      })
      if not idleOk then
        debugLog("Error in idle loop: " .. tostring(actionOrError))
        alertLib.send("Idle loop error: " .. tostring(actionOrError))
        os.sleep(5)
        os.reboot()
      end

      local action = actionOrError
      if action then
        runProgram(action)
      end

      setupIdle()
    end
  end
  mainLoop()
end

return M
