---------------------------------------
-- startup.lua (Blackjack)
-- Idle animation until user clicks,
-- then launches blackjack.lua or statistics.lua
-- Uses shared idle_screen lib for animation boilerplate.
---------------------------------------

local alertLib   = require("lib.alert")
local idleScreen = require("lib.idle_screen")
local updater    = require("lib.updater")

-----------------------------------------------------
-- Config
-----------------------------------------------------
local MONITOR_NAME = "right"

alertLib.configure({
  gameName  = "Casino Startup",
  logFile   = "debug.txt",
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
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg
    debugTerm.write(line .. "\n")
    alertLib.log(msg)
  end
end

-----------------------------------------------------
-- Stats button overlay (drawn on top of bouncing cards)
-----------------------------------------------------
local statsButton = nil

local function drawOverlay(env, screen)
  -- Logo drawn after cards but before button
  local logo = env.assets.logo
  if logo then
    screen:drawSurface(logo, 0, 0)
  end

  -- Statistics button
  local buttonText   = "STATISTICS"
  local buttonWidth  = math.floor(env.width * 0.45) + 22
  local buttonHeight = 16
  local buttonX      = math.floor((env.width - buttonWidth) / 2)
  local buttonY      = math.floor(env.height * 0.8) - 2

  screen:fillRect(buttonX, buttonY, buttonWidth, buttonHeight, colors.gray)
  screen:fillRect(buttonX + 2, buttonY + 2, buttonWidth - 4, buttonHeight - 4, colors.lime)
  screen:drawText(
    buttonText, env.font,
    buttonX + math.floor((buttonWidth - env.surface.getTextSize(buttonText, env.font)) / 2),
    buttonY + 5, colors.black
  )

  statsButton = {
    x      = buttonX,
    y      = buttonY,
    width  = buttonWidth,
    height = buttonHeight,
  }
end

local function checkHit(x, y, env)
  if statsButton
     and x >= statsButton.x and x <= statsButton.x + statsButton.width
     and y >= statsButton.y and y <= statsButton.y + statsButton.height then
    return "statistics"
  end
  return nil  -- fall through to "play"
end

-----------------------------------------------------
-- Setup
-----------------------------------------------------
local idleEnv = nil

local function setupIdle()
  idleEnv = idleScreen.setup({
    monitorName = MONITOR_NAME,
    extraAssets = { logo = "logo.nfp" },
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

debugLog("startup.lua: Idle setup complete. Checking for updates...")

updater.checkForUpdates({
  callback = function(status, msg)
    debugLog("Auto-update: [" .. status .. "] " .. tostring(msg))
  end,
})

debugLog("startup.lua: Entering idle loop...")

while true do
  local idleOk, actionOrError = pcall(idleScreen.runLoop, idleEnv, {
    drawOverlay = drawOverlay,
    checkHit    = checkHit,
  })
  if not idleOk then
    debugLog("Error in idle loop: " .. tostring(actionOrError))
    alertLib.send("Idle loop error: " .. tostring(actionOrError))
    os.sleep(5)
    os.reboot()
  end

  local action = actionOrError

  if action == "play" then
    debugLog("startup.lua: Starting blackjack game...")
    local runOk, runErr = pcall(shell.run, "blackjack.lua")
    if not runOk then
      debugLog("startup.lua: Error in blackjack.lua: " .. tostring(runErr))
      alertLib.send("blackjack.lua error: " .. tostring(runErr))
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
    debugLog("startup.lua: blackjack.lua finished, returning to idle.")

  elseif action == "statistics" then
    debugLog("startup.lua: Starting statistics viewer...")
    local oldTerm = term.current()
    local runOk, runErr = pcall(shell.run, "statistics.lua")
    if not runOk then
      debugLog("startup.lua: Error running statistics.lua: " .. tostring(runErr))
      alertLib.send("statistics.lua error: " .. tostring(runErr))
      term.clear()
      term.setCursorPos(1, 1)
      term.setTextColor(colors.red)
      term.write("Error running statistics")
      term.setCursorPos(1, 3)
      term.setTextColor(colors.white)
      term.write(tostring(runErr))
      term.setCursorPos(1, 5)
      term.write("The system will restart in 5 seconds...")
      os.sleep(5)
    end
    term.redirect(oldTerm)
    debugLog("startup.lua: statistics.lua finished, returning to idle.")
  end

  -- Re-setup idle for clean state
  setupIdle()
end
