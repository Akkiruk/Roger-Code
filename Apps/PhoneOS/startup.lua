-- manifest-entrypoint: true
-- manifest-key: phone_os
-- manifest-name: Pocket Casino OS
-- manifest-category: Apps
-- Pocket casino shell for ComputerCraft pocket computers.

local alert = require("lib.alert")
local runtimeExit = require("lib.runtime_exit")

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

local PROGRAM = ROOT ~= "" and fs.combine(ROOT, "phone_os.lua") or "phone_os.lua"

alert.configure({
  gameName = "Pocket OS Startup",
  logFile = "phone_os_startup.log",
})

local function sleepRaw(seconds)
  local timer = os.startTimer(seconds)
  while true do
    local event, id = os.pullEventRaw()
    if event == "timer" and id == timer then
      return
    end
  end
end

local function runProgram()
  local ok, shellOk, shellErr = pcall(shell.run, PROGRAM)
  return runtimeExit.classifyShellRun(ok, shellOk, shellErr, {
    emptyErrorMeansTerminate = true,
  })
end

local function showCrash(err)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("Pocket OS crashed.")
  print("")
  term.setTextColor(colors.white)
  print(tostring(err))
  print("")
  print("Restarting in 5 seconds...")
end

while true do
  local ok, err, runState = runProgram()
  if ok then
    sleepRaw(0.25)
  elseif runtimeExit.isTerminateError(err) then
    if runState == "empty_error_treated_as_terminate" then
      alert.log("Pocket OS returned false without an error message; treating as terminate")
    else
      alert.log("Pocket OS terminated; relaunching")
    end
    sleepRaw(0.25)
  else
    alert.log("Pocket OS crash: " .. tostring(err))
    showCrash(err)
    sleepRaw(5)
  end
end
