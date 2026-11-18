-- manifest-entrypoint: true
-- manifest-key: saltgate
-- manifest-name: SALTGATE: Low Tide
-- manifest-description: A 3D open-city crime and driving game: steal cars, run jobs for Mama Juno, and keep your heat low in a harbor city at dusk.
-- manifest-category: Games

-- Restarts SALTGATE after a crash and keeps a log. Terminate (Ctrl+T) leaves for the shell.
local LOG = "saltgate.log"
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
  local callOk, shellOk, shellErr = pcall(shell.run, "saltgate.lua")
  term.redirect(previous)
  if not callOk then
    if isTerminate(shellOk) then log("terminated"); return end
    log("crash: " .. tostring(shellOk))
  elseif shellOk == false then
    log("saltgate exited with an error " .. tostring(shellErr or ""))
    local ok = pcall(os.sleep, CRASH_DELAY)
    if not ok then return end
  else
    log("saltgate exited normally")
    return
  end
end
