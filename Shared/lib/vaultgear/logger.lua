local constants = require("lib.vaultgear.constants")
local logging = require("lib.roger_logging")

local M = {}

local logPath = constants.LOG_FILE
local logger = logging.open(logPath, { namespace = "VaultGear" })

function M.configure(path)
  if type(path) == "string" and path ~= "" then
    logPath = path
    logger = logging.open(logPath, { namespace = "VaultGear" })
  end
end

function M.write(level, message)
  return logger.write(message, level or "INFO")
end

function M.info(message)
  return M.write("INFO", message)
end

function M.error(message)
  return M.write("ERROR", message)
end

return M
