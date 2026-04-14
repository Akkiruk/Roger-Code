local M = {}
local logging = require("lib.roger_logging")

local function appendLine(path, message)
  assert(type(path) == "string", "path must be a string")

  local handle = fs.open(path, "a")
  if not handle then
    return false
  end

  handle.writeLine("[" .. os.epoch("local") .. "] " .. tostring(message))
  handle.close()
  return true
end

function M.write(path, message)
  return logging.write(path, message, {
    level = "INFO",
    namespace = path,
  })
end

function M.new(path, echoToTerminal)
  assert(type(path) == "string", "path must be a string")

  local baseLogger = logging.open(path, {
    namespace = path,
    echoToTerminal = echoToTerminal == true,
  })
  local logger = {}

  logger.file = path

  logger.write = function(message)
    return baseLogger.info(message)
  end

   logger.info = function(message)
    return baseLogger.info(message)
  end

  logger.error = function(message)
    return baseLogger.error(message)
  end

  return logger
end

return M