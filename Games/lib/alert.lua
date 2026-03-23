-- alert.lua
-- Shared error alerting and debug logging for all casino games.
-- Sends admin alerts via chatBox peripheral and writes to log files.
-- Usage:
--   local alert = require("lib.alert")
--   alert.configure({ adminName = "Akkiruk", logFile = "blackjack_error.log", gameName = "Blackjack" })
--   alert.send("Something went wrong!")
--   alert.log("debug info here")

local peripherals = require("lib.peripherals")

local DEBUG = settings.get("casino.debug") or false

local adminName  = "Akkiruk"
local gameName   = "Casino"
local logFile    = "casino_error.log"
local chatbox    = nil

-- Planned exit codes that should NOT trigger admin alerts
local PLANNED_EXITS = {
  inactivity_timeout = true,
  main_menu          = true,
  user_terminated    = true,
  keyboard_interrupt = true,
}

--- Configure the alert module.
-- @param cfg table  Keys: adminName, gameName, logFile, plannedExits
local function configure(cfg)
  assert(type(cfg) == "table", "configure expects a table")
  if cfg.adminName    then adminName = cfg.adminName    end
  if cfg.gameName     then gameName  = cfg.gameName     end
  if cfg.logFile      then logFile   = cfg.logFile      end
  if cfg.plannedExits then
    for _, code in ipairs(cfg.plannedExits) do
      PLANNED_EXITS[code] = true
    end
  end
end

--- Check whether an error message is a planned/intentional exit.
-- @param msg string
-- @return boolean
local function isPlannedExit(msg)
  return PLANNED_EXITS[tostring(msg)] == true
end

--- Write a line to the log file with a timestamp.
-- @param msg string
local function log(msg)
  local f = fs.open(logFile, "a")
  if f then
    f.writeLine(os.date() .. ": " .. tostring(msg))
    f.close()
  end
  if DEBUG then
    print(os.time(), "[alert] " .. tostring(msg))
  end
end

--- Send an admin alert via chatbox. Skips planned exits.
-- @param errorMsg string
local function send(errorMsg)
  if isPlannedExit(errorMsg) then
    if DEBUG then
      print(os.time(), "[alert] Skipping planned exit: " .. tostring(errorMsg))
    end
    return
  end

  log("ALERT: " .. tostring(errorMsg))

  -- Lazy-init chatbox
  if not chatbox then
    chatbox = peripherals.find("chatBox")
  end

  if chatbox then
    pcall(function()
      chatbox.sendMessageToPlayer(
        "[" .. gameName .. " Error]: " .. tostring(errorMsg),
        adminName,
        gameName,
        "[]",
        "c"
      )
    end)
  end
end

--- Register additional planned exit codes.
-- @param codes table  Array of strings
local function addPlannedExits(codes)
  for _, code in ipairs(codes) do
    PLANNED_EXITS[code] = true
  end
end

return {
  configure      = configure,
  isPlannedExit  = isPlannedExit,
  log            = log,
  send           = send,
  addPlannedExits = addPlannedExits,
}
