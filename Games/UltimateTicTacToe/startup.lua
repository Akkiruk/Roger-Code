-- manifest-entrypoint: true
-- manifest-key: ultimate-tic-tac-toe
-- manifest-name: Ultimate Tic-Tac-Toe
-- manifest-description: Nine boards in one: two players (or the computer) fight for three small boards in a row, with ratings, leaderboards and sound.
-- manifest-category: Games

-- Restarts the game after a crash and keeps a log. Terminate (Ctrl+T) leaves for the shell.
local LOG = "uttt.log"
local CRASH_DELAY = 5

local function log(msg)
  local h = fs.open(LOG, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " [startup] " .. tostring(msg))
    h.close()
  end
end

local function isTerminate(err)
  return type(err) == "string" and err:find("Terminated", 1, true) ~= nil
end

while true do
  local previous = term.current()
  local callOk, shellOk, shellErr = pcall(shell.run, "uttt.lua")
  term.redirect(previous)
  if not callOk then
    if isTerminate(shellOk) then log("terminated"); return end
    log("crash: " .. tostring(shellOk))
  elseif shellOk == false then
    -- shell.run reports the error text itself; a Ctrl+T leaves nothing, so treat a quick false as terminate
    log("game exited with an error " .. tostring(shellErr or ""))
    local ok = pcall(os.sleep, CRASH_DELAY)
    if not ok then return end
  else
    log("game exited normally")
    return
  end
end
