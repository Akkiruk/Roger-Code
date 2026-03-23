---------------------------------------
-- startup.lua (Roulette)
-- Idle animation until user clicks,
-- then launches Roulette.lua
-- Uses shared idle_screen lib for animation boilerplate.
---------------------------------------

local alertLib   = require("lib.alert")
local idleScreen = require("lib.idle_screen")

-----------------------------------------------------
-- Config
-----------------------------------------------------
local MONITOR_NAME = "right"

alertLib.configure({
  adminName = "Akkiruk",
  gameName  = "Roulette Startup",
  logFile   = "roulette_error.log",
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
-- Title overlay (drawn on top of bouncing cards)
-----------------------------------------------------
local function drawOverlay(env, screen)
  local title = "ROULETTE"
  local tw = env.surface.getTextSize(title, env.font)
  screen:drawText(title, env.font,
    math.floor((env.width - tw) / 2),
    math.floor(env.height * 0.15), colors.yellow)

  local subtitle = "Touch to play"
  local sw = env.surface.getTextSize(subtitle, env.font)
  screen:drawText(subtitle, env.font,
    math.floor((env.width - sw) / 2),
    math.floor(env.height * 0.28), colors.white)
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

debugLog("startup.lua: Idle setup complete. Entering idle loop...")

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

  local action = actionOrError

  if action == "play" then
    debugLog("startup.lua: Starting roulette game...")
    local runOk, runErr = pcall(shell.run, "Roulette.lua")
    if not runOk then
      debugLog("startup.lua: Error in Roulette.lua: " .. tostring(runErr))
      alertLib.send("Roulette.lua error: " .. tostring(runErr))
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
    debugLog("startup.lua: Roulette.lua finished, returning to idle.")
  end

  setupIdle()
end
