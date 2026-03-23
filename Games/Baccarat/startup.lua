---------------------------------------
-- startup.lua (Baccarat)
-- Idle animation until user clicks,
-- then launches baccarat.lua
-- Uses shared idle_screen lib for animation boilerplate.
---------------------------------------

local alertLib   = require("lib.alert")
local idleScreen = require("lib.idle_screen")
local updater    = require("lib.updater")
local ui         = require("lib.ui")

-----------------------------------------------------
-- Config
-----------------------------------------------------
local MONITOR_NAME = "right"

alertLib.configure({
  gameName  = "Baccarat Startup",
  logFile   = "baccarat_error.log",
})
alertLib.addPlannedExits({
  "inactivity_timeout",
  "main_menu",
  "user_terminated",
})

local debugEnabled = true
local debugTerm = term.native()

local function debugLog(msg)
  if debugEnabled then
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. msg
    local prev = term.redirect(debugTerm)
    print(line)
    term.redirect(prev)
    alertLib.log(msg)
  end
end

-----------------------------------------------------
-- Title text overlay
-----------------------------------------------------
local function drawOverlay(env, screen)
  local title = "BACCARAT"
  local tw = env.surface.getTextSize(title, env.font)
  ui.safeDrawText(screen, title, env.font, math.floor((env.width - tw) / 2), math.floor(env.height * 0.15), colors.yellow)

  local subtitle = "Touch to play"
  local sw = env.surface.getTextSize(subtitle, env.font)
  ui.safeDrawText(screen, subtitle, env.font, math.floor((env.width - sw) / 2), math.floor(env.height * 0.28), colors.white)
end

-----------------------------------------------------
-- Setup
-----------------------------------------------------
local idleEnv = nil

local function setupIdle()
  idleEnv = idleScreen.setup({
    monitorName = MONITOR_NAME,
  })
end

-----------------------------------------------------
-- Main
-----------------------------------------------------
local ok, err = pcall(setupIdle)
if not ok then
  debugLog("Fatal error in setupIdle: " .. tostring(err))
  alertLib.send("Fatal setupIdle: " .. tostring(err))
  error(err)
end

debugLog("Baccarat idle setup complete.")

local installInfo = updater.getInstallInfo()
if installInfo then
  debugLog("Installed: " .. tostring(installInfo.program)
    .. " v" .. tostring(installInfo.version)
    .. " | lib v" .. tostring(installInfo.lib_version)
    .. " | hash=" .. tostring(installInfo.content_hash))
else
  debugLog("WARNING: No .installed_program record found!")
end

debugLog("Checking for updates...")
updater.checkForUpdates({
  callback = function(status, msg)
    debugLog("Updater [" .. status .. "] " .. tostring(msg))
  end,
})

debugLog("Entering idle loop...")

local function mainLoop()
  while true do
    local idleOk, actionOrError = pcall(idleScreen.runLoop, idleEnv, {
      drawOverlay = drawOverlay,
    })
    if not idleOk then
      debugLog("Error in idle loop: " .. tostring(actionOrError))
      alertLib.send("Idle loop error: " .. tostring(actionOrError))
      os.sleep(5)
      os.reboot()
    end

    if actionOrError == "play" then
      debugLog("startup.lua: Starting baccarat game...")
      local runOk, runErr = pcall(shell.run, "baccarat.lua")
      if not runOk then
        debugLog("startup.lua: Error in baccarat.lua: " .. tostring(runErr))
        alertLib.send("baccarat.lua error: " .. tostring(runErr))
        if idleEnv.monitor then
          term.clear()
          term.setCursorPos(1, 1)
          term.setTextColor(colors.red)
          term.write("Game crashed! Error reported to admin.")
          term.setCursorPos(1, 3)
          term.setTextColor(colors.white)
          term.write("The game will restart in 10 seconds...")
          os.sleep(10)
        end
      end
      debugLog("startup.lua: baccarat.lua finished, returning to idle.")
    end

    setupIdle()
  end
end

local function updateWatcher()
  updater.watchForUpdates({
    callback = function(status, msg)
      debugLog("BG Updater [" .. status .. "] " .. tostring(msg))
    end,
  })
end

parallel.waitForAny(mainLoop, updateWatcher)
