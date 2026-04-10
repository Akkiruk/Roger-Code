-- alert.lua
-- Shared error alerting and debug logging for all casino games.
-- Sends admin alerts via chatBox peripheral and writes to log files.
-- Usage:
--   local alert = require("lib.alert")
--   alert.configure({ logFile = "blackjack_error.log", gameName = "Blackjack" })
--   alert.send("Something went wrong!")
--   alert.log("debug info here")
--
-- adminName is resolved automatically from ccvault.getHostName() (the player
-- who placed this computer). Override with alert.configure({ adminName = ".." })
-- if you need a specific recipient.

local peripherals = require("lib.peripherals")

local DEBUG = settings.get("casino.debug") or false

local adminName  = nil  -- resolved lazily from ccvault host
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
    f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
    f.close()
  end
  if DEBUG then
    print(os.epoch("local"), "[alert] " .. tostring(msg))
  end
end

--- Resolve adminName lazily from ccvault host if not explicitly set.
local function resolveAdmin()
  if adminName then return adminName end
  if ccvault and type(ccvault.getHostName) == "function" then
    local ok, name = pcall(ccvault.getHostName)
    if ok and name and type(name) == "string" and name ~= "" then
      adminName = name
    end
  end
  return adminName
end

--- Send an admin alert via chatbox. Skips planned exits.
-- @param errorMsg string
local function send(errorMsg)
  if isPlannedExit(errorMsg) then
    if DEBUG then
      print(os.epoch("local"), "[alert] Skipping planned exit: " .. tostring(errorMsg))
    end
    return
  end

  log("ALERT: " .. tostring(errorMsg))

  local recipient = resolveAdmin()
  if not recipient then return end

  -- Lazy-init chatbox
  if not chatbox then
    chatbox = peripherals.find("chatBox")
  end

  if chatbox then
    pcall(function()
      chatbox.sendMessageToPlayer(
        "[" .. gameName .. " Error]: " .. tostring(errorMsg),
        recipient,
        gameName,
        "[]",
        "c"
      )
    end)
  end
end

--- Send a notification to a specific player via chatbox.
-- @param playerName string  The player to message
-- @param message    string  The message text
local function notifyPlayer(playerName, message)
  if not playerName or playerName == "" then return end

  -- Lazy-init chatbox
  if not chatbox then
    chatbox = peripherals.find("chatBox")
  end

  if chatbox then
    pcall(function()
      chatbox.sendMessageToPlayer(
        tostring(message),
        playerName,
        gameName,
        "[]",
        "6"
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
  configure       = configure,
  isPlannedExit   = isPlannedExit,
  log             = log,
  send            = send,
  notifyPlayer    = notifyPlayer,
  addPlannedExits = addPlannedExits,
}
