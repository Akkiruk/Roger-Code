-- manifest-entrypoint: true
-- manifest-key: arcade
-- manifest-name: Arcade
-- manifest-description: One computer, every free game: pick a game on the wall and play a friend or the computer, with ratings and leaderboards.
-- manifest-category: Arcade

-- Restarts the Arcade after a crash and keeps a log. Terminate (Ctrl+T) leaves for the shell.
local LOG = "arcade.log"
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
  local callOk, shellOk, shellErr = pcall(shell.run, "arcade.lua")
  term.redirect(previous)
  if not callOk then
    if isTerminate(shellOk) then log("terminated"); return end
    log("crash: " .. tostring(shellOk))
  elseif shellOk == false then
    -- shell.run reports the error text itself; a Ctrl+T leaves nothing, so treat a quick false as terminate
    log("arcade exited with an error " .. tostring(shellErr or ""))
    local ok = pcall(os.sleep, CRASH_DELAY)
    if not ok then return end
  else
    log("arcade exited normally")
    return
  end
end
