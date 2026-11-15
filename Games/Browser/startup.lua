-- manifest-entrypoint: true
-- manifest-key: game-browser
-- manifest-name: Game Browser
-- manifest-description: Every free cabinet on one computer: Arcade, Classics, Classics 2, Long Games, Versus and BLIGHTMARE. Pick one on the wall, and CABINETS on its menu swaps to another. No tokens, ever.
-- manifest-category: Arcade
-- manifest-bundle: Games/Arcade>arcade Games/Classics>classics Games/Classics2>classics2 Games/LongGames>longgames Games/Versus>versus Games/Blightmare>blightmare

-- Restarts the Game Browser after a crash and keeps a log. Terminate (Ctrl+T) leaves for the shell.
local LOG = "browser.log"
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
  local callOk, shellOk, shellErr = pcall(shell.run, "browser.lua")
  term.redirect(previous)
  if not callOk then
    if isTerminate(shellOk) then log("terminated"); return end
    log("crash: " .. tostring(shellOk))
  elseif shellOk == false then
    log("browser exited with an error " .. tostring(shellErr or ""))
    local ok = pcall(os.sleep, CRASH_DELAY)
    if not ok then return end
  else
    log("browser exited normally")
    return
  end
end
